// validationLedgerDeviceTests/KYCForceQuitResumeDeviceTests.swift
// Phase 5 Plan 08 Task 2 — SC-2 (device portion): a force-quit mid-upload
// resumes from the last committed chunk, not from zero.
// Requirement: UPL-02 — threat T-05-08-01 (a "resumable" upload that silently
// restarts from zero after a force-quit).
//
// Target membership: validationLedgerDeviceTests ONLY. This is the
// physical-device counterpart to plan 04's `KYCUploaderResumeTests` (which
// proves the resume *logic* on the simulator). This suite proves the same
// contract on REAL HARDWARE with a REAL 6 MB payload — exercising the actual
// `NSFileProtectionComplete` on-disk store and the real process-storage path
// the simulator downgrades (05-02 SUMMARY: simulator downgrades file protection
// to CompleteUntilFirstUserAuthentication; strict `.complete` is device-only).
//
// === How a force-quit is modeled in an XCTest ===
// A real app-kill cannot be triggered inside `xcodebuild test` (RESEARCH
// Pitfall 4 — that is exactly why the full end-to-end UX needs the Task-3
// HUMAN-UAT checkpoint). What this device test CAN exercise — and what proves
// the SC-2 contract — is the resume mechanism:
//   1. Start a 6 MB upload, but make the mock backend fail a chunk partway so
//      `KYCUploader.upload` throws after only N chunks have been acked.
//   2. The persisted `chunksAcked` cursor is written to the encrypted on-disk
//      `KYCSessionStore` immediately after every server ack (Pitfall 4) — so
//      the cursor is on disk at the point of failure.
//   3. RECONSTRUCT a brand-new `KYCUploader` + `KYCSessionStore` from the same
//      directory — exactly what a fresh process does after a force-quit: it
//      re-reads the on-disk session, it does NOT inherit any in-memory state.
//   4. Call `upload(...)` again and assert it resumes from the persisted
//      `chunksAcked` cursor (no `init`, only the remaining chunks), NOT from 0.
// The fresh-object reconstruction is the device-faithful stand-in for a process
// relaunch: the only state that crosses the boundary is the encrypted on-disk
// blob — precisely the SC-2 invariant.
//
// XCTest (not Swift Testing) — consistent with the validationLedgerDeviceTests
// conventions (DLExtractionScannerDeviceTests / the device-target pattern).
//
// SCOPE — the upload pipeline + persistence ONLY. No camera/AVFoundation/Vision
// surface is touched; both the pipeline and the store are device-and-simulator
// runnable, but the device run is what validates real-storage / real-process-
// lifecycle behavior (the simulator's downgraded file protection cannot).

import XCTest
@testable import validationLedger

final class KYCForceQuitResumeDeviceTests: XCTestCase {

    // MARK: - Tunables

    /// A real ~6 MB artifact — the SC-2 / RESEARCH Pitfall 4 spec payload.
    /// 12 chunks at the 512 KB `KYCUploader.defaultChunkSize`.
    private static let sixMegabytes = 512 * 1024 * 12

    /// The mock backend acks this many chunks, then fails — modeling the
    /// force-quit point partway through the 6 MB upload.
    private static let killAfterChunks = 5

    // MARK: - Lifecycle

    override func tearDown() {
        // Clear any handlers a test registered so the device-lane registry is
        // clean for the next suite on the same iPhone.
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - SC-2 — force-quit resume

    /// SC-2 device portion — a 6 MB upload interrupted partway resumes from the
    /// persisted `chunksAcked` cursor when the pipeline is reconstructed fresh
    /// (the device-faithful model of a force-quit + relaunch).
    func testForceQuitMidUploadResumesFromPersistedChunksAcked() async throws {
        // --- A persistent on-disk KYC session store -------------------------
        // One directory shared across the "before force-quit" and "after
        // relaunch" pipelines — the fresh post-relaunch store reads the SAME
        // encrypted file the pre-kill store wrote.
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kyc-forcequit-resume-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        // Seed the 6 MB artifact into the session — what the capture flow
        // persists before the upload begins.
        let firstStore = try KYCSessionStore(directory: storeDir)
        var session = KYCSession()
        let artifactBytes = Self.syntheticArtifact(byteCount: Self.sixMegabytes)
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = artifactBytes
        try firstStore.persist(session)

        // --- Phase 1: upload starts, then is "force-quit" partway -----------
        // The mock backend acks `killAfterChunks` chunks, then returns a
        // non-retryable 400 so `upload` throws — the upload did NOT finish.
        let totalChunks = (Self.sixMegabytes + KYCUploader.defaultChunkSize - 1)
            / KYCUploader.defaultChunkSize
        Self.registerBackend(failChunkAtIndexOrAbove: Self.killAfterChunks)

        let firstUploader = KYCUploader(
            apiClient: Self.makeMockClient(),
            store: firstStore,
            logger: Self.SilentLogger()
        )

        var firstUploadThrew = false
        do {
            try await firstUploader.upload(artifactType: .face)
        } catch {
            // Expected — the "force-quit" point. The upload was interrupted.
            firstUploadThrew = true
        }
        XCTAssertTrue(
            firstUploadThrew,
            "the interrupted upload must throw — it did not complete before the force-quit"
        )

        // The persisted cursor must be on disk: chunks were acked up to the
        // kill point and `markChunkAcked` writes immediately after every ack.
        let interruptedSession = try XCTUnwrap(
            try firstStore.loadSession(),
            "the on-disk session survives the interrupted upload"
        )
        let interruptedState = try XCTUnwrap(
            interruptedSession.state(for: .face),
            "an ArtifactUploadState was persisted for the in-flight artifact"
        )
        XCTAssertEqual(
            interruptedState.chunksAcked, Self.killAfterChunks,
            "the resume cursor persisted exactly the acked-chunk count at the force-quit point"
        )
        XCTAssertFalse(
            interruptedState.committed,
            "the artifact is NOT committed — the upload was interrupted"
        )
        let resumeUploadID = try XCTUnwrap(
            interruptedState.uploadID,
            "the uploadID persisted so the resume can skip init"
        )

        // --- Phase 2: "relaunch" — reconstruct the pipeline from scratch ----
        // A fresh process keeps NOTHING in memory; it re-reads the on-disk
        // session. Model that by building a brand-new store + uploader from the
        // SAME directory. Re-register a fully-successful backend (the network
        // is fine now — only the app was killed).
        MockURLProtocol.reset()
        // Register the OBSERVER first: handlers are consulted in registration
        // order and the first non-nil return wins. The recorder always returns
        // nil, so it tallies the request and then the backend handler responds.
        let backendRecorder = Self.ChunkRecorder()
        Self.registerChunkRecorder(backendRecorder)
        Self.registerBackend(failChunkAtIndexOrAbove: nil)

        let secondStore = try KYCSessionStore(directory: storeDir)
        let secondUploader = KYCUploader(
            apiClient: Self.makeMockClient(),
            store: secondStore,
            logger: Self.SilentLogger()
        )

        // The resume call — this is the SC-2 assertion target.
        try await secondUploader.upload(artifactType: .face)

        // --- Assert: resumed from the cursor, NOT from chunk 0 --------------
        XCTAssertEqual(
            backendRecorder.initCount, 0,
            "SC-2: the resumed upload must NOT re-run init — it had an uploadID"
        )
        XCTAssertEqual(
            backendRecorder.firstChunkIndexSeen, Self.killAfterChunks,
            "SC-2: the resume sent its FIRST chunk at index \(Self.killAfterChunks) — "
                + "it resumed from the persisted chunksAcked cursor, not from chunk 0"
        )
        let remainingChunks = totalChunks - Self.killAfterChunks
        XCTAssertEqual(
            backendRecorder.chunkRequestCount, remainingChunks,
            "SC-2: only the \(remainingChunks) chunks AFTER the cursor were re-sent"
        )

        // The resumed artifact reaches committed — the resume completed the
        // 6 MB upload end-to-end across the simulated relaunch.
        let finalSession = try XCTUnwrap(try secondStore.loadSession())
        let finalState = try XCTUnwrap(finalSession.state(for: .face))
        XCTAssertTrue(
            finalState.committed,
            "the resumed 6 MB upload committed — the force-quit cost zero chunk re-uploads beyond the cursor"
        )
        XCTAssertEqual(
            finalState.chunksAcked, totalChunks,
            "chunksAcked / totalChunks restored correctly — the full 6 MB artifact is acked"
        )
        XCTAssertEqual(
            finalState.uploadID, resumeUploadID,
            "the resume reused the SAME uploadID — the backend sees one continuous upload"
        )
    }

    // MARK: - Test scaffolding

    /// Deterministic synthetic artifact bytes of an exact length so the chunk
    /// math is exact (no camera — this suite is pipeline + persistence only).
    private static func syntheticArtifact(byteCount: Int) -> Data {
        Data((0..<byteCount).map { UInt8($0 & 0xFF) })
    }

    /// A `MockURLProtocol`-backed `APIClient` with the real `IdempotencyInterceptor`
    /// — the same wiring the app uses for the mock network config. Self-contained
    /// because `KYCUploaderTestSupport` lives in the simulator test target, not
    /// this device target.
    private static func makeMockClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let networkClient = URLSessionNetworkClient(config: .mock, session: session)
        return APIClient(
            baseURL: URL(string: "https://mock.local")!,
            networkClient: networkClient,
            requestInterceptors: [IdempotencyInterceptor()],
            responseInterceptors: []
        )
    }

    /// Drain a request body — `URLProtocol` moves `httpBody` into `httpBodyStream`.
    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Decode `chunk_index` out of a `/kyc/upload/chunk` request body.
    private static func chunkIndex(from request: URLRequest) -> Int? {
        let body = bodyData(from: request)
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["chunk_index"] as? Int
    }

    private static func make200(_ json: String, url: URL?) -> (HTTPURLResponse, Data) {
        let resolved = url ?? URL(string: "https://mock.local")!
        let resp = HTTPURLResponse(
            url: resolved, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, Data(json.utf8))
    }

    private static func make400(url: URL?) -> (HTTPURLResponse, Data) {
        let resolved = url ?? URL(string: "https://mock.local")!
        let resp = HTTPURLResponse(
            url: resolved, statusCode: 400, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, Data(#"{"error":"force-quit-injected"}"#.utf8))
    }

    /// Register a KYC backend. When `failChunkAtIndexOrAbove` is non-nil, any
    /// chunk POST at that index or higher returns a non-retryable 400 — the
    /// injected "force-quit" point. When nil, every chunk succeeds.
    private static func registerBackend(failChunkAtIndexOrAbove: Int?) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                return make200(
                    #"{"upload_id":"up-forcequit-face","chunk_size":\#(KYCUploader.defaultChunkSize)}"#,
                    url: request.url)
            case "/kyc/upload/chunk":
                let index = chunkIndex(from: request) ?? -1
                if let failAt = failChunkAtIndexOrAbove, index >= failAt {
                    // The injected force-quit: a non-retryable 400 so the
                    // uploader throws immediately rather than retrying.
                    return make400(url: request.url)
                }
                let acked = index + 1
                return make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":0}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                return make200(
                    #"{"artifact_id":"artifact-up-forcequit-face","status":"pending_review"}"#,
                    url: request.url)
            default:
                return nil
            }
        }
    }

    /// A lock-guarded recorder so the `@Sendable` mock handler can report what
    /// the resume actually sent (init count, first chunk index, chunk count).
    final class ChunkRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _initCount = 0
        private var _chunkRequestCount = 0
        private var _firstChunkIndexSeen: Int?

        var initCount: Int { lock.withLock { _initCount } }
        var chunkRequestCount: Int { lock.withLock { _chunkRequestCount } }
        var firstChunkIndexSeen: Int { lock.withLock { _firstChunkIndexSeen ?? -1 } }

        func recordInit() { lock.withLock { _initCount += 1 } }
        func recordChunk(index: Int) {
            lock.withLock {
                _chunkRequestCount += 1
                if _firstChunkIndexSeen == nil { _firstChunkIndexSeen = index }
            }
        }
    }

    /// Register an OBSERVING handler (returns `nil` so it never satisfies a
    /// request — it only tallies). Registered before `registerBackend` so it
    /// sees every request the responding handler also sees.
    private static func registerChunkRecorder(_ recorder: ChunkRecorder) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
            case "/kyc/upload/chunk":
                if let index = chunkIndex(from: request) {
                    recorder.recordChunk(index: index)
                }
            default:
                break
            }
            return nil  // observe only — the real backend handler responds
        }
    }

    /// A no-op `Logger` — `KYCUploader` requires a logger dependency.
    final class SilentLogger: Logger, @unchecked Sendable {
        func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
        func log(_ level: LogLevel, _ message: String) {}
    }
}
