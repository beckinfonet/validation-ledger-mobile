// validationLedger/Core/Identity/KYCUploader.swift
// Phase 5 Plan 04 (UPL-01..04 / SC-5): the resumable, retrying, idempotency-keyed
// chunked-upload pipeline.
//
// KYCUploader is the reliability core of Phase 5 — it gets six identity artifacts
// to the backend over poor dock LTE without restarting from zero and without
// DDoSing the backend. It composes shipped primitives only:
//   - the `APIClient` typed facade (throws exclusively `NetworkError`)
//   - the shipped `KYCUploadInitEndpoint` / `KYCUploadChunkEndpoint` /
//     `KYCUploadCommitEndpoint` structs
//   - the `APIEndpoint.headers` per-request seam (plan 01) — so the stable
//     per-chunk `Idempotency-Key` reaches `IdempotencyInterceptor`, which
//     preserves a caller-supplied key
//   - the `KYCSessionStore` encrypted on-disk persistence (plan 02)
//
// === RATIFIED USER DECISION — foreground session, JSON chunk contract ===
// This uploader drives the SHIPPED `init`/`chunk`/`commit` endpoints through the
// normal foreground `APIClient`. It does NOT build a background `URLSession` and
// does NOT switch to file-based `uploadTask(with:fromFile:)`. The true file-based
// background-session rework (RESEARCH Pitfall 2 option 2) is an explicit M2
// follow-up. M1 ships this foreground chunk loop; plan 07 keeps it alive across a
// background transition via `BGProcessingTaskRequest`.
//
// === Logging discipline (LOG-01 / RESEARCH Pitfall 1/6) ===
// Every log call routes through the injected `Logger` and carries event names
// only — never artifact `Data`, chunk bytes, or any DL / coordinate value. The
// `LogField` enum cannot physically carry image bytes.

import Foundation
import CryptoKit

/// The resumable chunked-upload pipeline for one KYC artifact at a time.
///
/// `actor` isolation serializes the per-artifact pipeline: the resume cursor
/// (`chunksAcked`) is read, advanced, and persisted without races even when
/// `resumeAllPendingUploads()` walks several artifacts.
public actor KYCUploader {

    // MARK: - Tunables

    /// UPL-01 default chunk size — 512 KB. The backend's init-response
    /// `chunkSize` overrides this.
    static let defaultChunkSize = 512 * 1024

    /// UPL-03 retry cap — a chunk POST is attempted at most this many times
    /// before `retriesExhausted` is thrown. Note this is 5, not the shipped
    /// GET-only interceptor's default of 3.
    static let maxChunkAttempts = 5

    /// Backoff base / ceiling in milliseconds — the same vetted defaults the
    /// shipped GET-only interceptor uses; the values are copied, not shared.
    static let backoffBaseDelayMs: UInt64 = 500
    static let backoffCeilingMs: UInt64 = 30_000

    // MARK: - Dependencies (initializer DI — ARCH-04)

    private let apiClient: APIClient
    private let store: KYCSessionStore
    private let logger: any Logger

    /// UPL-04 progress observer — invoked once per server chunk-ack with the
    /// fraction `chunksAcked / totalChunks`. Never byte-driven (Pitfall 3).
    private let onProgress: (@Sendable (KYCUploadInitEndpoint.ArtifactType, Double) -> Void)?

    public init(
        apiClient: APIClient,
        store: KYCSessionStore,
        logger: any Logger,
        onProgress: (@Sendable (KYCUploadInitEndpoint.ArtifactType, Double) -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.store = store
        self.logger = logger
        self.onProgress = onProgress
    }

    // MARK: - Public pipeline

    /// Upload one artifact end-to-end: resume-aware `init` → chunk loop →
    /// `commit` → delete the local copy.
    ///
    /// Called the instant an artifact is captured + confirmed (D-01), while the
    /// user keeps capturing the remaining artifacts. Safe to call again after a
    /// force-quit — it resumes from the persisted `chunksAcked` cursor.
    public func upload(artifactType: KYCUploadInitEndpoint.ArtifactType) async throws {
        logger.info(event: LogEvent("kyc_upload_started"),
                    fields: [.event: artifactType.rawValue])

        // --- 1. Resume-aware init -------------------------------------------
        let resumeState = try store.loadSession()?.state(for: artifactType)
        let uploadID: String
        let chunkSize: Int

        if let resumeState, let existingID = resumeState.uploadID {
            // An init already succeeded for this artifact — skip it, resume.
            uploadID = existingID
            chunkSize = resumeState.chunkSize
            logger.info(event: LogEvent("kyc_upload_resumed"),
                        fields: [.event: artifactType.rawValue,
                                 .count: resumeState.chunksAcked])
        } else {
            // Fresh upload — read the artifact bytes, chunk at the 512 KB
            // default, POST init, persist a fresh ArtifactUploadState.
            guard let data = try store.loadSession()?.data(for: artifactType) else {
                logger.error(event: LogEvent("kyc_upload_data_missing"),
                             fields: [.event: artifactType.rawValue])
                throw KYCUploadError.artifactDataMissing(artifactType)
            }
            let initialChunks = data.chunked(into: Self.defaultChunkSize)
            let initResponse: KYCUploadInitEndpoint.Response
            do {
                initResponse = try await apiClient.request(KYCUploadInitEndpoint(
                    artifactType: artifactType,
                    totalChunks: initialChunks.count,
                    totalBytes: data.count,
                    sha256: data.sha256Hex()
                ))
            } catch let error as NetworkError {
                logger.error(event: LogEvent("kyc_upload_init_failed"),
                             fields: [.event: artifactType.rawValue])
                throw KYCUploadError.nonRetryable(error)
            }
            uploadID = initResponse.uploadID
            // The backend may override the 512 KB default.
            chunkSize = initResponse.chunkSize
            let totalChunks = chunkSize == Self.defaultChunkSize
                ? initialChunks.count
                : data.chunked(into: chunkSize).count
            try persistFreshState(
                artifactType: artifactType,
                uploadID: uploadID,
                chunkSize: chunkSize,
                totalChunks: totalChunks,
                totalBytes: data.count,
                sha256: data.sha256Hex()
            )
        }

        // --- 2. Chunk loop ---------------------------------------------------
        // Re-read the artifact bytes (a resume may have a different chunkSize
        // than the in-memory default) and re-chunk at the persisted chunkSize.
        guard let data = try store.loadSession()?.data(for: artifactType) else {
            // The local copy is gone — already committed (D-02). Nothing to do.
            logger.info(event: LogEvent("kyc_upload_already_committed"),
                        fields: [.event: artifactType.rawValue])
            return
        }
        let chunks = data.chunked(into: chunkSize)
        let totalChunks = chunks.count
        let startIndex = try store.loadSession()?.state(for: artifactType)?.chunksAcked ?? 0

        for index in startIndex..<totalChunks {
            let chunk = chunks[index]
            let idempotencyKey = idempotencyKey(uploadID: uploadID, chunkIndex: index)
            let ackResponse = try await sendChunkWithRetry(
                uploadID: uploadID,
                chunkIndex: index,
                chunkData: chunk,
                idempotencyKey: idempotencyKey
            )
            // Persist the resume cursor IMMEDIATELY after the server ack
            // (Pitfall 4 — a force-quit between chunks loses at most the
            // in-flight chunk, never the whole artifact).
            try store.markChunkAcked(artifactType, upTo: index + 1)
            // UPL-04 — progress is driven from the server ack, never bytes.
            let total = ackResponse.totalChunks > 0 ? ackResponse.totalChunks : totalChunks
            let fraction = Double(ackResponse.chunksAcked) / Double(total)
            onProgress?(artifactType, fraction)
        }

        // --- 3. Commit, then free the local copy (D-02) ----------------------
        let commitResponse: KYCUploadCommitEndpoint.Response
        do {
            commitResponse = try await apiClient.request(
                KYCUploadCommitEndpoint(uploadID: uploadID)
            )
        } catch {
            logger.error(event: LogEvent("kyc_upload_commit_failed"),
                         fields: [.event: artifactType.rawValue])
            throw KYCUploadError.commitFailed
        }
        try store.markCommitted(artifactType, artifactID: commitResponse.artifactID)
        // D-02 footprint control — the committed artifact's local bytes are freed.
        try store.deleteLocalArtifactData(artifactType)
        logger.info(event: LogEvent("kyc_upload_committed"),
                    fields: [.event: artifactType.rawValue])
    }

    /// Resume every not-yet-committed artifact in the persisted `KYCSession`.
    /// This is the entry point plan 07's `BGProcessingTaskRequest` handler calls.
    public func resumeAllPendingUploads() async {
        guard let session = try? store.loadSession() else { return }
        for (rawType, state) in session.uploadStates where !state.committed {
            guard let artifactType = KYCUploadInitEndpoint.ArtifactType(rawValue: rawType) else {
                continue
            }
            do {
                try await upload(artifactType: artifactType)
            } catch {
                // One artifact failing must not abort the rest — log and move on.
                logger.error(event: LogEvent("kyc_upload_resume_artifact_failed"),
                             fields: [.event: rawType])
            }
        }
    }

    // MARK: - Chunk send (retry layer — Task 2)

    /// Send one chunk through `APIClient`, retrying retryable failures with
    /// jittered exponential backoff, capped at `maxChunkAttempts` (UPL-03).
    ///
    /// The chunk request carries a stable per-`(uploadID, chunkIndex)`
    /// `Idempotency-Key` via the `APIEndpoint.headers` seam — a retry (even
    /// across a force-quit + resume) reproduces the SAME key, so the backend
    /// dedupes rather than committing the chunk twice (SC-5).
    private func sendChunkWithRetry(
        uploadID: String,
        chunkIndex: Int,
        chunkData: Data,
        idempotencyKey: String
    ) async throws -> KYCUploadChunkEndpoint.Response {
        let endpoint = ChunkUploadRequest(
            uploadID: uploadID,
            chunkIndex: chunkIndex,
            chunkData: chunkData.base64EncodedString(),
            chunkSha256: chunkData.sha256Hex(),
            idempotencyKey: idempotencyKey
        )

        var attempt = 0
        while true {
            do {
                let response = try await apiClient.request(endpoint)
                return response
            } catch let error {
                // Rate-limit: honour the server's Retry-After, then retry —
                // this does NOT consume the jitter-schedule attempt budget the
                // same way, but it still counts toward the cap.
                if case let NetworkError.rateLimited(retryAfter) = error {
                    attempt += 1
                    guard attempt < Self.maxChunkAttempts else {
                        logger.error(event: LogEvent("kyc_chunk_retries_exhausted"),
                                     fields: [.count: chunkIndex])
                        throw KYCUploadError.retriesExhausted(chunkIndex: chunkIndex)
                    }
                    let ns = UInt64(max(0, retryAfter) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: ns)
                    continue
                }
                // Retryable transport failure (5xx or a connectivity URLError).
                if Self.isRetryable(error) {
                    attempt += 1
                    guard attempt < Self.maxChunkAttempts else {
                        logger.error(event: LogEvent("kyc_chunk_retries_exhausted"),
                                     fields: [.count: chunkIndex])
                        throw KYCUploadError.retriesExhausted(chunkIndex: chunkIndex)
                    }
                    let delayMs = Self.delayForAttempt(attempt)
                    try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                    continue
                }
                // Non-retryable (a 4xx other than 429, a decoding failure) —
                // surface immediately, no retry.
                logger.error(event: LogEvent("kyc_chunk_failed_nonretryable"),
                             fields: [.count: chunkIndex])
                if let networkError = error as? NetworkError {
                    throw KYCUploadError.nonRetryable(networkError)
                }
                throw error
            }
        }
    }

    // MARK: - Backoff math (copied from the shipped GET-only interceptor)

    // The shipped response-interceptor that retries idempotent GETs hard-guards
    // `httpMethod == "GET"` and passes POSTs through unretried by design
    // (NET-05). Chunk uploads are POSTs, so the retry loop lives HERE — only the
    // backoff math + URLError classifier are copied, never the interceptor type
    // itself (RESEARCH Pitfall 7).

    /// Jittered exponential backoff: `min(base << attempt, ceiling) ± 20%`.
    static func delayForAttempt(_ attempt: Int) -> UInt64 {
        let rawShift: UInt64
        if attempt >= 62 {
            rawShift = UInt64.max
        } else {
            rawShift = backoffBaseDelayMs << attempt
        }
        let capped = min(rawShift, backoffCeilingMs)
        let maxJitter = Int64(Double(capped) * 0.2)
        let jitter: Int64 = maxJitter > 0
            ? Int64.random(in: -maxJitter...maxJitter)
            : 0
        return UInt64(max(0, Int64(capped) + jitter))
    }

    /// Classify a thrown error as retryable: any 5xx `httpError`, or a
    /// `NetworkError` wrapping a connectivity `URLError`.
    static func isRetryable(_ error: Error) -> Bool {
        if case let NetworkError.httpError(statusCode, _) = error {
            return (500...599).contains(statusCode)
        }
        let urlError: URLError?
        switch error {
        case let direct as URLError:
            urlError = direct
        case let NetworkError.decodingFailed(inner):
            urlError = inner as? URLError
        case let NetworkError.encodingFailed(inner):
            urlError = inner as? URLError
        default:
            urlError = nil
        }
        if let urlError {
            return isRetryableURLError(urlError)
        }
        return false
    }

    /// The retryable `URLError` cases — copied from the shipped GET-only
    /// interceptor's `isRetryable` classifier (the math, not the type).
    static func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .timedOut,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    // MARK: - Idempotency key

    /// The deterministic per-chunk `Idempotency-Key` — `"<uploadID>.chunk.<n>"`.
    /// Derived purely from persisted fields, so a retry across a force-quit +
    /// resume reproduces the same key and the backend dedupes (SC-5).
    private func idempotencyKey(uploadID: String, chunkIndex: Int) -> String {
        "\(uploadID).chunk.\(chunkIndex)"
    }

    // MARK: - Private

    /// Persist a fresh `ArtifactUploadState` for a just-initialized upload,
    /// preserving the artifact `Data` already in the session.
    private func persistFreshState(
        artifactType: KYCUploadInitEndpoint.ArtifactType,
        uploadID: String,
        chunkSize: Int,
        totalChunks: Int,
        totalBytes: Int,
        sha256: String
    ) throws {
        var session = (try store.loadSession()) ?? KYCSession()
        session.uploadStates[artifactType.rawValue] = ArtifactUploadState(
            artifactType: artifactType,
            uploadID: uploadID,
            totalChunks: totalChunks,
            totalBytes: totalBytes,
            chunkSize: chunkSize,
            chunksAcked: 0,
            sha256: sha256,
            committed: false,
            artifactID: nil,
            localDataAvailable: true
        )
        try store.persist(session)
    }
}

// MARK: - Chunk-upload request with a per-request Idempotency-Key

/// A `KYCUploadChunkEndpoint`-equivalent that carries a per-request
/// `Idempotency-Key` header through the `APIEndpoint.headers` seam (plan 01).
///
/// The shipped `KYCUploadChunkEndpoint` cannot carry a custom header (its
/// `headers` defaults to `[:]`), so this small wrapper re-declares the identical
/// path / method / body and adds the header. The wire contract is unchanged —
/// same `/kyc/upload/chunk` POST, same `RequestBody`, same `Response`.
nonisolated struct ChunkUploadRequest: APIEndpoint {
    typealias RequestBody = KYCUploadChunkEndpoint.RequestBody
    typealias Response = KYCUploadChunkEndpoint.Response

    let path = "/kyc/upload/chunk"
    let method: HTTPMethod = .post
    let body: KYCUploadChunkEndpoint.RequestBody?
    let headers: [String: String]

    init(
        uploadID: String,
        chunkIndex: Int,
        chunkData: String,
        chunkSha256: String,
        idempotencyKey: String
    ) {
        self.body = KYCUploadChunkEndpoint(
            uploadID: uploadID,
            chunkIndex: chunkIndex,
            chunkData: chunkData,
            chunkSha256: chunkSha256
        ).body
        // The header reaches the request before IdempotencyInterceptor runs;
        // the interceptor preserves a caller-supplied key (NET-04 Phase 5 seam).
        self.headers = ["Idempotency-Key": idempotencyKey]
    }
}

// MARK: - Data hashing + chunking (RESEARCH "Code Examples")

// File-private so the SHA-256 / chunking helpers are scoped to `KYCUploader`
// and do not leak into the module namespace (RESEARCH "private Data extension").
private extension Data {
    /// Hex-encoded SHA-256 of the receiver — `CryptoKit.SHA256`, never
    /// hand-rolled (RESEARCH "Don't Hand-Roll"). Used for the full-artifact
    /// `sha256` and each chunk's `chunkSha256`.
    func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }

    /// Split the receiver into `size`-byte chunks (the last may be shorter).
    func chunked(into size: Int) -> [Data] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            subdata(in: $0 ..< Swift.min($0 + size, count))
        }
    }
}
