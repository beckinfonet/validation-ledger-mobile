// validationLedgerTests/KYC/KYCUploaderTests.swift
// Requirement: UPL-01 — KYCUploader init → chunk → commit happy path.
// RED scaffold turned GREEN by plan 05-04.
//
// Drives the SHIPPED init/chunk/commit endpoints through the real APIClient +
// MockURLProtocol. The mock backend handler parses the chunk index out of the
// body and returns an incrementing `chunksAcked`.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — init→chunk→commit happy path (UPL-01)", .serialized)
struct KYCUploaderTests {

    /// 3 chunks at 512 KB ⇒ ~1.2 MB. 512 KB + 512 KB + ~228 KB.
    private static let threeChunkBytes = 512 * 1024 * 2 + 233_000

    @Test("UPL-01: a full artifact upload runs exactly init → chunk×3 → commit")
    func happyPathInitChunkCommit() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerHappyPathBackend(recorder: recorder, totalChunks: 3)

        let store = try KYCUploaderTestSupport.makeStore()
        // Seed the artifact bytes into the session — KYCUploader reads them from the store.
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: Self.threeChunkBytes)
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )

        try await uploader.upload(artifactType: .face)

        #expect(recorder.initCount == 1, "exactly one init")
        #expect(recorder.totalChunkRequests == 3, "exactly three chunk POSTs")
        #expect(recorder.commitCount == 1, "exactly one commit")
    }

    @Test("UPL-01: the init body carries totalChunks, totalBytes and a hex SHA-256")
    func initBodyCarriesArtifactMetadata() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let captured = CapturedInitBody()
        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerHappyPathBackend(recorder: recorder, totalChunks: 3, capturedInit: captured)

        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.threeChunkBytes)
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        let json = captured.json
        #expect(json?["total_chunks"] as? Int == 3)
        #expect(json?["total_bytes"] as? Int == Self.threeChunkBytes)
        // Full-artifact hex SHA-256 — 64 lowercase hex chars.
        let sha = json?["sha256"] as? String
        #expect(sha?.count == 64)
        #expect(sha == bytes.kycUploaderSHA256HexForTest)
    }

    @Test("UPL-01: a backend chunkSize override re-chunks the artifact to that size")
    func backendChunkSizeOverrideIsHonoured() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // The artifact is ~1.2 MB. The backend overrides chunkSize to 256 KB,
        // so the loop must produce 5 chunks (256 KB ×4 + remainder), not 3.
        let overrideChunkSize = 256 * 1024
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.threeChunkBytes)
        let expectedChunks = (Self.threeChunkBytes + overrideChunkSize - 1) / overrideChunkSize

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerHappyPathBackend(
            recorder: recorder,
            totalChunks: expectedChunks,
            initChunkSize: overrideChunkSize
        )

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        #expect(recorder.totalChunkRequests == expectedChunks,
                "the loop re-chunks to the backend's 256 KB chunkSize")
    }

    @Test("UPL-01 / D-02: the local artifact Data is deleted after commit succeeds")
    func localDataDeletedAfterCommit() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerHappyPathBackend(recorder: recorder, totalChunks: 3)

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: Self.threeChunkBytes)
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        let after = try #require(try store.loadSession())
        #expect(after.data(for: .face) == nil, "local bytes freed post-commit (D-02)")
        let state = try #require(after.state(for: .face))
        #expect(state.localDataAvailable == false)
        #expect(state.committed == true)
        #expect(state.artifactID != nil)
    }

    @Test("UPL-01: upload throws artifactDataMissing when no bytes were captured")
    func missingArtifactDataThrows() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(KYCSession()) // empty — no artifact bytes

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )

        await #expect(throws: KYCUploadError.self) {
            try await uploader.upload(artifactType: .face)
        }
    }

    // MARK: - Backend handler

    /// Mutable capture box for the init request body.
    final class CapturedInitBody: @unchecked Sendable {
        private let lock = NSLock()
        private var _json: [String: Any]?
        var json: [String: Any]? { lock.withLock { _json } }
        func capture(_ value: [String: Any]?) { lock.withLock { _json = value } }
    }

    /// Register a happy-path KYC backend: one init → N chunk acks → one commit.
    private func registerHappyPathBackend(
        recorder: KYCUploaderTestSupport.BackendRecorder,
        totalChunks: Int,
        initChunkSize: Int = 512 * 1024,
        capturedInit: CapturedInitBody? = nil
    ) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
                if let capturedInit {
                    let body = KYCUploaderTestSupport.bodyData(from: request)
                    capturedInit.capture(
                        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                    )
                }
                let json = #"{"upload_id":"up-test-1","chunk_size":\#(initChunkSize)}"#
                return KYCUploaderTestSupport.make200(json, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                let key = request.value(forHTTPHeaderField: "Idempotency-Key")
                recorder.recordChunkAttempt(index, key: key)
                recorder.recordChunkSuccess(index)
                let acked = index + 1
                let json = #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#
                return KYCUploaderTestSupport.make200(json, url: request.url)
            case "/kyc/upload/commit":
                recorder.recordCommit()
                let json = #"{"artifact_id":"artifact-test-1","status":"pending_review"}"#
                return KYCUploaderTestSupport.make200(json, url: request.url)
            default:
                return nil
            }
        }
    }
}
