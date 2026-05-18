// validationLedgerTests/KYC/KYCUploaderResumeTests.swift
// Requirement: UPL-02 / SC-2 — resumable upload survives a simulated force-quit.
// RED scaffold turned GREEN by plan 05-04.
//
// Pre-seeds the store with a partially-acked ArtifactUploadState (a persisted
// uploadID + chunksAcked == 2 for a 4-chunk artifact) — the simulator portion of
// SC-2. A fresh KYCUploader must skip `init` and re-send only chunks 2 and 3.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — force-quit resume (UPL-02 / SC-2)", .serialized)
struct KYCUploaderResumeTests {

    /// 4 chunks at 512 KB.
    private static let fourChunkBytes = 512 * 1024 * 3 + 64_000

    @Test("UPL-02 / SC-2: a re-init with chunksAcked==2 sends only chunks 2 and 3, no init")
    func resumesFromLastAckedChunk() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let chunkSize = 512 * 1024
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.fourChunkBytes)
        let totalChunks = (Self.fourChunkBytes + chunkSize - 1) / chunkSize
        #expect(totalChunks == 4)

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerResumeBackend(recorder: recorder, totalChunks: totalChunks)

        // Pre-seed: an in-progress upload, force-quit after the 2nd chunk acked.
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = ArtifactUploadState(
            artifactType: .face,
            uploadID: "up-resume-1",
            totalChunks: totalChunks,
            totalBytes: Self.fourChunkBytes,
            chunkSize: chunkSize,
            chunksAcked: 2,
            sha256: bytes.kycUploaderSHA256HexForTest
        )
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        #expect(recorder.initCount == 0, "init is skipped — uploadID already persisted")
        #expect(recorder.totalChunkRequests == 2, "only the two remaining chunks are sent")
        #expect(recorder.attempts(forChunk: 0) == 0, "chunk 0 was already acked — not resent")
        #expect(recorder.attempts(forChunk: 1) == 0, "chunk 1 was already acked — not resent")
        #expect(recorder.attempts(forChunk: 2) == 1, "chunk 2 resumed")
        #expect(recorder.attempts(forChunk: 3) == 1, "chunk 3 resumed")
        #expect(recorder.commitCount == 1)
    }

    @Test("UPL-02: chunksAcked is persisted to the store after every ack")
    func chunksAckedPersistedAfterEachAck() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let chunkSize = 512 * 1024
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.fourChunkBytes)
        let totalChunks = 4

        // The store this inspection wraps — observe chunksAcked mid-upload by
        // hooking the chunk handler to read the store between acks.
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        try store.persist(session)

        let observed = ObservedAckedCursors()
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-persist-1","chunk_size":\#(chunkSize)}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                // Before this chunk's ack lands, the store reflects `index` acked.
                if let s = try? store.loadSession(), let state = s.state(for: .face) {
                    observed.record(beforeChunk: index, ackedInStore: state.chunksAcked)
                }
                let acked = index + 1
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"artifact-1","status":"pending_review"}"#, url: request.url)
            default:
                return nil
            }
        }

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        // Each chunk ack persists chunksAcked == index. By chunk 3's request the
        // store already holds chunksAcked == 3 (chunks 0,1,2 acked + persisted).
        #expect(observed.acked(beforeChunk: 0) == 0)
        #expect(observed.acked(beforeChunk: 1) == 1)
        #expect(observed.acked(beforeChunk: 2) == 2)
        #expect(observed.acked(beforeChunk: 3) == 3)

        let final = try #require(try store.loadSession())
        #expect(final.state(for: .face)?.chunksAcked == 4)
    }

    // MARK: - Helpers

    final class ObservedAckedCursors: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int: Int] = [:]
        func record(beforeChunk index: Int, ackedInStore: Int) {
            lock.withLock { values[index] = ackedInStore }
        }
        func acked(beforeChunk index: Int) -> Int? { lock.withLock { values[index] } }
    }

    private func registerResumeBackend(
        recorder: KYCUploaderTestSupport.BackendRecorder,
        totalChunks: Int
    ) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-resume-1","chunk_size":\#(512 * 1024)}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                recorder.recordChunkAttempt(index, key: request.value(forHTTPHeaderField: "Idempotency-Key"))
                recorder.recordChunkSuccess(index)
                let acked = index + 1
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                recorder.recordCommit()
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"artifact-resume-1","status":"pending_review"}"#, url: request.url)
            default:
                return nil
            }
        }
    }
}
