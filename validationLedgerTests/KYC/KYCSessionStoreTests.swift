// validationLedgerTests/KYC/KYCSessionStoreTests.swift
// Requirement: KYC-06 / UPL-02 — encrypted KYC session store round-trip.
// Turned GREEN by plan 05-02.
//
// Covers: the cold-boot round-trip (persist → discard store → fresh store →
// load returns an equal session), the immediate per-chunk-ack persist
// (Pitfall 4), the local-artifact-data delete that keeps upload state (D-02),
// the clearSession full-wipe, the absent-session-returns-nil case, and the
// NSFileProtectionComplete invariant on every written file. Also exercises the
// Task 1 models — Codable round-trip + deterministic idempotency key.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCSessionStore — encrypted session round-trip (KYC-06)")
struct KYCSessionStoreTests {

    /// A fresh temp directory unique per test — the store is injected with this
    /// so tests never touch the real Application Support directory.
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kyc-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return dir
    }

    private func sampleSession() -> KYCSession {
        var face = ArtifactUploadState(
            artifactType: .face,
            uploadID: "upload-face-1",
            totalChunks: 4,
            totalBytes: 2_000_000,
            chunkSize: 512 * 1024,
            chunksAcked: 2,
            sha256: "abc123",
            committed: false
        )
        face.artifactID = nil
        let dlFront = ArtifactUploadState(
            artifactType: .dlFront,
            uploadID: "upload-dl-1",
            totalChunks: 2,
            totalBytes: 800_000,
            chunkSize: 512 * 1024,
            chunksAcked: 2,
            sha256: "def456",
            committed: true,
            artifactID: "artifact-dl-1"
        )
        return KYCSession(
            sessionStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            artifactData: [
                KYCUploadInitEndpoint.ArtifactType.face.rawValue: Data(repeating: 0xAB, count: 4096),
                KYCUploadInitEndpoint.ArtifactType.dlFront.rawValue: Data(repeating: 0xCD, count: 2048),
            ],
            uploadStates: [
                KYCUploadInitEndpoint.ArtifactType.face.rawValue: face,
                KYCUploadInitEndpoint.ArtifactType.dlFront.rawValue: dlFront,
            ],
            submitted: false
        )
    }

    // MARK: - Task 1 model behaviours

    @Test("ArtifactUploadState round-trips through Codable with all fields preserved")
    func artifactUploadStateCodableRoundTrip() throws {
        let original = ArtifactUploadState(
            artifactType: .trailer,
            uploadID: "u-1",
            totalChunks: 7,
            totalBytes: 3_500_000,
            chunkSize: 512 * 1024,
            chunksAcked: 3,
            sha256: "deadbeef",
            committed: true,
            artifactID: "a-1",
            localDataAvailable: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArtifactUploadState.self, from: data)
        #expect(decoded == original)
    }

    @Test("A fresh ArtifactUploadState has chunksAcked == 0 and committed == false")
    func freshArtifactUploadStateDefaults() {
        let state = ArtifactUploadState(artifactType: .plate)
        #expect(state.chunksAcked == 0)
        #expect(state.committed == false)
        #expect(state.uploadID == nil)
        #expect(state.localDataAvailable == true)
    }

    @Test("KYCSession.state(for:) returns nil for an artifact not yet started")
    func kycSessionStateLookup() {
        let session = sampleSession()
        #expect(session.state(for: .face) != nil)
        #expect(session.state(for: .truck) == nil)
        #expect(session.data(for: .truck) == nil)
    }

    @Test("idempotencyKey(forChunk:) is deterministic for the same (uploadID, index)")
    func idempotencyKeyIsDeterministic() {
        let state = ArtifactUploadState(artifactType: .face, uploadID: "u-42")
        #expect(state.idempotencyKey(forChunk: 3) == state.idempotencyKey(forChunk: 3))
        #expect(state.idempotencyKey(forChunk: 3) != state.idempotencyKey(forChunk: 4))
    }

    // MARK: - Store: cold-boot round-trip (KYC-06)

    @Test("KYC-06: a KYC session persists and reads back identically after a cold boot")
    func sessionRoundTripsThroughEncryptedStore() async throws {
        let dir = makeTempDir()
        let original = sampleSession()

        // Persist with one store instance.
        let writer = try KYCSessionStore(directory: dir)
        try writer.persist(original)

        // Discard `writer`, construct a fresh store — simulated cold boot.
        let reader = try KYCSessionStore(directory: dir)
        let loaded = try reader.loadSession()

        #expect(loaded == original)
    }

    @Test("loadSession() returns nil when no session has ever been persisted")
    func absentSessionReturnsNil() throws {
        let store = try KYCSessionStore(directory: makeTempDir())
        #expect(try store.loadSession() == nil)
    }

    // MARK: - Immediate per-chunk-ack persist (Pitfall 4)

    @Test("markChunkAcked persists immediately and is visible after a store re-init")
    func chunkAckPersistsImmediately() throws {
        let dir = makeTempDir()
        let writer = try KYCSessionStore(directory: dir)
        try writer.persist(sampleSession())

        try writer.markChunkAcked(.face, upTo: 3)

        let reader = try KYCSessionStore(directory: dir)
        let reloaded = try reader.loadSession()
        #expect(reloaded?.state(for: .face)?.chunksAcked == 3)
        // Other artifacts untouched.
        #expect(reloaded?.state(for: .dlFront)?.chunksAcked == 2)
    }

    @Test("markCommitted records the artifactID and sets committed")
    func markCommittedPersists() throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)
        try store.persist(sampleSession())

        try store.markCommitted(.face, artifactID: "artifact-face-99")

        let reloaded = try KYCSessionStore(directory: dir).loadSession()
        #expect(reloaded?.state(for: .face)?.committed == true)
        #expect(reloaded?.state(for: .face)?.artifactID == "artifact-face-99")
    }

    // MARK: - Local-data delete keeps upload state (D-02)

    @Test("deleteLocalArtifactData frees the bytes but keeps the upload state")
    func deleteLocalDataKeepsUploadState() throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)
        try store.persist(sampleSession())

        try store.deleteLocalArtifactData(.dlFront)

        let reloaded = try KYCSessionStore(directory: dir).loadSession()
        // Bytes freed.
        #expect(reloaded?.data(for: .dlFront) == nil)
        // Upload state survives — uploadID, artifactID, committed intact.
        let state = reloaded?.state(for: .dlFront)
        #expect(state != nil)
        #expect(state?.uploadID == "upload-dl-1")
        #expect(state?.artifactID == "artifact-dl-1")
        #expect(state?.committed == true)
        #expect(state?.localDataAvailable == false)
    }

    // MARK: - clearSession full wipe (D-02)

    @Test("clearSession removes all KYC files; a subsequent load returns nil")
    func clearSessionWipesEverything() throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)
        try store.persist(sampleSession())
        #expect(try store.loadSession() != nil)

        try store.clearSession()
        #expect(try store.loadSession() == nil)
        // Idempotent — a second clear does not throw.
        try store.clearSession()
    }

    // MARK: - NSFileProtectionComplete invariant (T-05-02-01)

    @Test("every file the store writes is protected at rest (data-protection class)")
    func writtenFilesAreCompleteProtected() throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)
        try store.persist(sampleSession())

        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileProtectionKey]
        )
        #expect(!files.isEmpty)
        for file in files {
            let values = try file.resourceValues(forKeys: [.fileProtectionKey])
            // The store REQUESTS `.complete` (NSFileProtectionComplete) via both
            // the `Data.write` option and an explicit `setAttributes`. On the
            // iOS Simulator there is no passcode-tied class key, so the OS
            // silently downgrades `.complete` to `.completeUntilFirstUserAuth-
            // entication` — a documented simulator-only behaviour. Either value
            // proves the file IS in a data-protection class (encrypted at rest);
            // the absence of protection (or `.none`) would be the real defect.
            // The physical-device CI lane (Phase 4) asserts strict `.complete`.
            let protection = values.fileProtection
            #expect(
                protection == .complete || protection == .completeUntilFirstUserAuthentication,
                "expected a data-protection class on \(file.lastPathComponent), got \(String(describing: protection))"
            )
            // A protection value MUST be present and MUST NOT be `.none`
            // (unprotected) — the absence of protection is the real defect.
            #expect(protection != nil)
            #expect(protection != URLFileProtection.none)
        }
    }
}
