// validationLedger/Core/Storage/KYCSessionStore.swift
// Phase 5 Plan 02 (KYC-06 / UPL-02): the encrypted on-disk KYC session store.
//
// Persists a `KYCSession` (the in-progress KYC capture + chunked-upload state)
// to a JSON file written with `Data.WritingOptions.completeFileProtection`, and
// sets `FileProtectionType.complete` on the containing directory. This is the
// at-rest encryption layer for the multi-MB identity artifacts (DL + face
// images) — they are far too large for the Keychain (RESEARCH "Alternatives
// Considered"), so they live on the file system under OS-managed protection.
//
// === Concurrency: serialized read-modify-write (debug: kyc-session-store-data-race) ===
// The store is shared between two genuinely parallel execution contexts: the
// @MainActor capture path (FaceCaptureViewModel / VehicleCaptureViewModel /
// DLFrontScanViewController) and the `KYCUploader` background actor, and D-01
// pipelined upload is DESIGNED to overlap them. The on-disk session is a single
// JSON file; every mutation is a load -> mutate -> persist of the whole file.
//
// To make those mutations safe, ALL file I/O is guarded by a single private
// `NSLock`, and — critically — the lock is held across the WHOLE read-modify-
// write, not merely across each individual file op. A per-method lock would
// still let a caller that does `loadSession()` then a separate `persist()` race
// an interleaving writer. Callers that need an atomic update MUST use
// `withSession(_:)`, which loads, hands the caller an `inout KYCSession`, and
// persists — all inside one held lock. The capture writers and every
// `KYCUploader` mutate-helper route through it.
//
// The critical section does only fast, bounded file I/O (no `await`, no
// re-entrancy into the store's own public API), so a plain `NSLock` — not a
// serial queue or an `actor` — is the correct primitive: it keeps the
// synchronous API the synchronous `SceneDelegate` / `KYCReviewViewModel`
// callers depend on, with zero async ripple.
//
// === Crypto: never hand-rolled (RESEARCH "Don't Hand-Roll #1") ===
// `NSFileProtectionComplete` is OS-managed at-rest encryption tied to the device
// passcode — readable only while the device is unlocked. This file does not
// import or call any symmetric-cipher, key-derivation, or key-handle API — the
// OS owns the cipher end-to-end. The `grep` acceptance gate confirms zero
// hand-rolled cryptography in this file (threat T-05-02-02).
//
// === D-02 / RESEARCH Assumption A4 — the KYC store SURVIVES logout ===
// This store is NEVER wired into `LogoutService` teardown. `LogoutService.logout`
// wipes only `KeychainScope.session` Keychain keys and the Secure Enclave auth
// key; it never touches `Core/Storage` files. The on-disk KYC session therefore
// outlives a logout by design — a user who logs out mid-KYC and logs back in
// resumes exactly where they left off. The session is cleared ONLY by
// `KYCCoordinator` on full submit or explicit discard (D-02). DO NOT add this
// store to any logout step — that invariant is a load-bearing acceptance
// criterion for plan 05-07.
//
// API shape analog: `Core/Storage/Keychain/KeychainStore.swift` — same
// `Core/Storage` layer, same store contract (typed Error enum, idempotent
// delete, bulk-clear). The mechanism differs: file system, not the Keychain.

import Foundation

/// Errors surfaced by `KYCSessionStore`.
public enum KYCSessionStoreError: Error, Sendable {
    /// The session could not be JSON-encoded.
    case encodingFailed(Error)
    /// The on-disk session file could not be JSON-decoded.
    case decodingFailed(Error)
    /// A file-system read/write/create operation failed.
    case ioFailed(Error)
}

/// Encrypted on-disk store for the in-progress KYC session + per-chunk upload
/// state. Survives an indefinite cold boot (KYC-06) and a logout (D-02).
///
/// Thread-safe: every public method is guarded by a private `NSLock`, and the
/// read-modify-write helpers (`withSession`, `markChunkAcked`, `markCommitted`,
/// `deleteLocalArtifactData`) hold that lock across the whole load->mutate->
/// persist so concurrent capture / upload writers can never lose an update.
public final class KYCSessionStore: @unchecked Sendable {

    private let directory: URL
    private let sessionFileURL: URL

    /// Serializes ALL file I/O. Held across an entire read-modify-write so a
    /// caller's load + mutate + persist is atomic against every other writer.
    /// The critical section is `await`-free and never re-enters the store's own
    /// public API, so a non-recursive lock cannot deadlock.
    private let lock = NSLock()

    /// The single JSON file name holding the encoded `KYCSession`.
    private static let sessionFileName = "kyc-session.json"

    /// - Parameter directory: the base directory for KYC files. Tests inject a
    ///   temp directory; production defaults to a `KYCSession` subdirectory of
    ///   the app's Application Support directory.
    ///
    /// On init the directory is created if absent and `FileProtectionType
    /// .complete` is applied to it, so every file written underneath inherits
    /// complete protection.
    public init(directory: URL? = nil) throws {
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolved = appSupport.appendingPathComponent("KYCSession", isDirectory: true)
        }
        self.directory = resolved
        self.sessionFileURL = resolved.appendingPathComponent(Self.sessionFileName)

        try Self.ensureProtectedDirectory(at: resolved)
    }

    // MARK: - Persist / load

    /// Persist `session` as JSON, written with `completeFileProtection`.
    ///
    /// Use this only for a blind whole-session overwrite. For a read-modify-
    /// write (the capture writers, the uploader helpers) use `withSession(_:)`,
    /// which is atomic against concurrent writers — a bare `loadSession()` then
    /// `persist()` is NOT.
    public func persist(_ session: KYCSession) throws {
        lock.lock()
        defer { lock.unlock() }
        try persistLocked(session)
    }

    /// Load the persisted session, or `nil` if none has ever been persisted.
    /// An absent file is NOT an error — a first-run KYC flow has no session yet.
    public func loadSession() throws -> KYCSession? {
        lock.lock()
        defer { lock.unlock() }
        return try loadSessionLocked()
    }

    /// Atomically load -> mutate -> persist the whole session under a single
    /// held lock. THIS is the safe read-modify-write entry point — every
    /// concurrent capture / upload writer must go through it so no update is
    /// lost (debug: kyc-session-store-data-race).
    ///
    /// `change` receives an `inout KYCSession`; if no session exists yet a fresh
    /// `KYCSession()` is created so a first capture has somewhere to write. The
    /// (possibly mutated) session is persisted before the lock is released.
    ///
    /// The closure runs INSIDE the critical section — it must not call back
    /// into this store (that would deadlock) and must stay fast (no `await`,
    /// no I/O of its own); it should only mutate the passed struct.
    @discardableResult
    public func withSession(_ change: (inout KYCSession) -> Void) throws -> KYCSession {
        lock.lock()
        defer { lock.unlock() }
        var session = (try loadSessionLocked()) ?? KYCSession()
        change(&session)
        try persistLocked(session)
        return session
    }

    // MARK: - Per-chunk ack (Pitfall 4)

    /// Advance the resume cursor for `artifact` to `chunksAcked` and persist
    /// immediately. Called after every server ack so a force-quit between
    /// chunks loses at most the single in-flight chunk (UPL-02 / Pitfall 4).
    public func markChunkAcked(_ artifact: KYCUploadInitEndpoint.ArtifactType, upTo chunksAcked: Int) throws {
        try mutate(artifact) { $0.chunksAcked = chunksAcked }
    }

    /// Record a successful `POST /kyc/upload/commit` for `artifact`.
    public func markCommitted(_ artifact: KYCUploadInitEndpoint.ArtifactType, artifactID: String) throws {
        try mutate(artifact) {
            $0.committed = true
            $0.artifactID = artifactID
        }
    }

    // MARK: - D-02 footprint control

    /// Drop the local artifact `Data` for `artifact` (freeing the multi-MB
    /// bytes) while keeping its `ArtifactUploadState` — `uploadID`, `artifactID`,
    /// `committed` all survive. Used post-commit so the device no longer holds a
    /// copy of the identity image (D-02 footprint control).
    ///
    /// Atomic against concurrent writers — the load/mutate/persist is held under
    /// one lock so it cannot clobber an interleaving capture write.
    public func deleteLocalArtifactData(_ artifact: KYCUploadInitEndpoint.ArtifactType) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var session = try loadSessionLocked() else { return }
        session.artifactData.removeValue(forKey: artifact.rawValue)
        if var state = session.uploadStates[artifact.rawValue] {
            state.localDataAvailable = false
            session.uploadStates[artifact.rawValue] = state
        }
        try persistLocked(session)
    }

    /// Remove all KYC files. Idempotent — a missing file is success (mirrors
    /// `KeychainStore.delete`). This is the D-02 full-submit / explicit-discard
    /// path; it is invoked ONLY by `KYCCoordinator`, never by logout.
    public func clearSession() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: sessionFileURL)
        } catch {
            throw KYCSessionStoreError.ioFailed(error)
        }
    }

    // MARK: - Private

    /// Load → mutate the single `ArtifactUploadState` → persist, all under one
    /// held lock. A no-op if no session exists or the artifact has no state yet.
    private func mutate(
        _ artifact: KYCUploadInitEndpoint.ArtifactType,
        _ change: (inout ArtifactUploadState) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var session = try loadSessionLocked(),
              var state = session.uploadStates[artifact.rawValue] else {
            return
        }
        change(&state)
        session.uploadStates[artifact.rawValue] = state
        try persistLocked(session)
    }

    /// Encode + write the session. Caller MUST already hold `lock`.
    private func persistLocked(_ session: KYCSession) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw KYCSessionStoreError.encodingFailed(error)
        }
        do {
            // `.completeFileProtection` — OS-managed at-rest encryption on the
            // file. `.atomic` so a crash mid-write never leaves a torn file.
            try data.write(to: sessionFileURL, options: [.completeFileProtection, .atomic])
            // Assert FileProtectionType.complete explicitly after the write.
            // An atomic write replaces the file via a rename, and the new inode
            // can inherit the directory's default class rather than the
            // requested one — so re-stamp `.complete` on the file itself to
            // guarantee the T-05-02-01 at-rest-encryption invariant.
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: sessionFileURL.path
            )
        } catch {
            throw KYCSessionStoreError.ioFailed(error)
        }
    }

    /// Read + decode the session, or `nil` if absent. Caller MUST already hold
    /// `lock`.
    private func loadSessionLocked() throws -> KYCSession? {
        guard FileManager.default.fileExists(atPath: sessionFileURL.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: sessionFileURL)
        } catch {
            throw KYCSessionStoreError.ioFailed(error)
        }
        do {
            return try JSONDecoder().decode(KYCSession.self, from: data)
        } catch {
            throw KYCSessionStoreError.decodingFailed(error)
        }
    }

    /// Create `directory` if absent and apply `FileProtectionType.complete` to
    /// it so files written underneath are encrypted at rest.
    ///
    /// `URLResourceValues.fileProtection` is get-only, so the directory's
    /// protection class is set via `FileManager.setAttributes` with
    /// `.protectionKey = FileProtectionType.complete` — the supported write path
    /// for directory-level protection.
    private static func ensureProtectedDirectory(at directory: URL) throws {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directory.path) {
                // `completeFileProtection` on creation — the directory and
                // anything written underneath inherit complete at-rest
                // encryption.
                try fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
            } else {
                // Directory already exists — assert complete protection on it.
                try fm.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: directory.path
                )
            }
        } catch {
            throw KYCSessionStoreError.ioFailed(error)
        }
    }
}
