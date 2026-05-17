// validationLedgerTests/KYC/KYCUploaderIdempotencyTests.swift
// Requirement: SC-5 — no duplicate chunk commits under transient-failure replay.
// RED scaffold turned GREEN by plan 05-04.
//
// Each chunk POST carries a stable per-(uploadID, chunkIndex) Idempotency-Key.
// The mock backend records the set of distinct keys seen per chunk index — a
// retried chunk must reuse the SAME key so a real backend dedupes it. The
// `BackendRecorder` also tallies *successful* acks per chunk: SC-5 asserts at
// most one distinct successful ack per chunk index.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — per-chunk idempotency, no duplicate commits (SC-5)", .serialized)
struct KYCUploaderIdempotencyTests {

    private static let twoChunkBytes = 512 * 1024 + 100_000

    @Test("SC-5: a retried chunk reuses the same Idempotency-Key")
    func retriedChunkReusesIdempotencyKey() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // Chunk 0 fails 503 twice, then succeeds — 3 attempts for chunk 0.
        registerIdempotencyBackend(recorder: recorder, totalChunks: 2,
                                   failChunk: 0, failTimes: 2)

        let uploader = try makeUploader(recorder: recorder)
        try await uploader.upload(artifactType: .face)

        // Chunk 0 was attempted 3 times — but ALL 3 carried the SAME key.
        #expect(recorder.attempts(forChunk: 0) == 3)
        let keys0 = recorder.keys(forChunk: 0)
        #expect(keys0.count == 1, "all retries of chunk 0 reuse one Idempotency-Key")
        // The key is the deterministic (uploadID, chunkIndex) form.
        #expect(keys0.first == "up-idem-1.chunk.0")
        // Chunk 1's key differs from chunk 0's — keys are per (uploadID, index).
        let keys1 = recorder.keys(forChunk: 1)
        #expect(keys1.first == "up-idem-1.chunk.1")
        #expect(keys0.isDisjoint(with: keys1))
    }

    @Test("SC-5: under transient failure the backend records no duplicate successful ack")
    func noDuplicateSuccessfulAckPerChunk() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // Every chunk fails once before succeeding — maximal retry pressure.
        registerIdempotencyBackend(recorder: recorder, totalChunks: 2,
                                   failChunk: -1, failTimes: 1, failEveryChunkOnce: true)

        let uploader = try makeUploader(recorder: recorder)
        try await uploader.upload(artifactType: .face)

        // SC-5: at most one *successful* ack per (uploadID, chunkIndex) — a
        // deduping backend would never double-commit a retried chunk.
        #expect(recorder.successes(forChunk: 0) == 1)
        #expect(recorder.successes(forChunk: 1) == 1)
        #expect(recorder.commitCount == 1)
    }

    @Test("SC-5: the per-chunk key survives a force-quit + resume unchanged")
    func keyStableAcrossResume() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let chunkSize = 512 * 1024
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.twoChunkBytes)
        let totalChunks = 2

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        registerIdempotencyBackend(recorder: recorder, totalChunks: totalChunks,
                                   failChunk: -1, failTimes: 0)

        // Resume mid-upload: chunk 0 already acked, uploadID persisted.
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = ArtifactUploadState(
            artifactType: .face,
            uploadID: "up-idem-1",
            totalChunks: totalChunks,
            totalBytes: Self.twoChunkBytes,
            chunkSize: chunkSize,
            chunksAcked: 1,
            sha256: bytes.kycUploaderSHA256HexForTest
        )
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        // The resumed chunk 1 carries exactly the deterministic key derived
        // from the persisted uploadID + index — stable across the resume.
        #expect(recorder.keys(forChunk: 1).first == "up-idem-1.chunk.1")
    }

    // MARK: - Helpers

    private func makeUploader(
        recorder: KYCUploaderTestSupport.BackendRecorder
    ) throws -> KYCUploader {
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: Self.twoChunkBytes)
        try store.persist(session)
        return KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
    }

    /// A backend that fails `failChunk` for `failTimes` attempts, or — when
    /// `failEveryChunkOnce` is set — fails every chunk exactly once.
    private func registerIdempotencyBackend(
        recorder: KYCUploaderTestSupport.BackendRecorder,
        totalChunks: Int,
        failChunk: Int,
        failTimes: Int,
        failEveryChunkOnce: Bool = false
    ) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-idem-1","chunk_size":\#(512 * 1024)}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                let key = request.value(forHTTPHeaderField: "Idempotency-Key")
                let priorAttempts = recorder.attempts(forChunk: index)
                recorder.recordChunkAttempt(index, key: key)
                let shouldFail: Bool
                if failEveryChunkOnce {
                    shouldFail = priorAttempts < 1
                } else {
                    shouldFail = (index == failChunk) && (priorAttempts < failTimes)
                }
                if shouldFail {
                    return KYCUploaderTestSupport.makeResponse(
                        status: 503,
                        json: #"{"error":"injected transient failure"}"#,
                        url: request.url)
                }
                recorder.recordChunkSuccess(index)
                let acked = index + 1
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                recorder.recordCommit()
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"artifact-idem-1","status":"pending_review"}"#, url: request.url)
            default:
                return nil
            }
        }
    }
}
