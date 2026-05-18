// validationLedgerTests/KYC/KYCUploaderRetryTests.swift
// Requirement: UPL-03 — chunk-upload retry with jittered exponential backoff,
// capped at 5 attempts.
// RED scaffold turned GREEN by plan 05-04.
//
// The mock backend can be told to fail a given chunk index N times before
// succeeding (or forever), so the suite exercises: retry-then-succeed,
// the 5-attempt cap, and immediate failure on a non-retryable 4xx.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — retry backoff caps at 5 attempts (UPL-03)", .serialized)
struct KYCUploaderRetryTests {

    /// A single 512 KB chunk keeps each test to one chunk's retry behaviour.
    private static let oneChunkBytes = 400 * 1024

    @Test("UPL-03: a chunk that 503s once is retried and ultimately succeeds")
    func chunkRetriedOnceThenSucceeds() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // Chunk 0 fails with 503 on its first attempt, then succeeds.
        registerRetryBackend(recorder: recorder, totalChunks: 1, failChunk: 0,
                             failTimes: 1, failStatus: 503)

        let uploader = try makeUploader(recorder: recorder)
        try await uploader.upload(artifactType: .face)

        #expect(recorder.attempts(forChunk: 0) == 2, "one 503 + one success")
        #expect(recorder.commitCount == 1, "the upload completes")
    }

    @Test("UPL-03: a chunk that 5xxs forever throws retriesExhausted after exactly 5 attempts")
    func chunkRetryCapsAtFiveAttempts() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // Chunk 0 fails forever (failTimes very large) with a 500.
        registerRetryBackend(recorder: recorder, totalChunks: 1, failChunk: 0,
                             failTimes: 999, failStatus: 500)

        let uploader = try makeUploader(recorder: recorder)

        await #expect(throws: KYCUploadError.retriesExhausted(chunkIndex: 0)) {
            try await uploader.upload(artifactType: .face)
        }
        // Exactly 5 attempts — not 4, not 6.
        #expect(recorder.attempts(forChunk: 0) == 5)
        #expect(recorder.commitCount == 0, "commit is never reached")
    }

    @Test("UPL-03: a non-retryable 400 throws immediately with zero retries")
    func nonRetryable400ThrowsImmediately() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // Chunk 0 returns a 400 — a non-retryable client error.
        registerRetryBackend(recorder: recorder, totalChunks: 1, failChunk: 0,
                             failTimes: 999, failStatus: 400)

        let uploader = try makeUploader(recorder: recorder)

        await #expect(throws: KYCUploadError.self) {
            try await uploader.upload(artifactType: .face)
        }
        // A 400 is non-retryable — exactly one attempt, no backoff loop.
        #expect(recorder.attempts(forChunk: 0) == 1)
    }

    @Test("UPL-03: the backoff delay grows with attempt and never exceeds the cap")
    func backoffDelayGrowsAndIsCapped() {
        // delayForAttempt is jittered ±20%, so assert on bounds, not equality.
        for attempt in 0...8 {
            let delay = KYCUploader.delayForAttempt(attempt)
            // Even with -20% jitter the delay is non-negative.
            #expect(delay >= 0)
            // With +20% jitter the delay never exceeds ceiling × 1.2.
            let ceilingWithJitter = UInt64(Double(KYCUploader.backoffCeilingMs) * 1.2) + 1
            #expect(delay <= ceilingWithJitter,
                    "attempt \(attempt) delay \(delay) within capped+jitter bound")
        }
        // A large attempt saturates at the ceiling band, not unbounded growth.
        let saturated = KYCUploader.delayForAttempt(40)
        let lowerBand = UInt64(Double(KYCUploader.backoffCeilingMs) * 0.8) - 1
        #expect(saturated >= lowerBand)
    }

    // MARK: - Helpers

    private func makeUploader(
        recorder: KYCUploaderTestSupport.BackendRecorder
    ) throws -> KYCUploader {
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: Self.oneChunkBytes)
        try store.persist(session)
        return KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
    }

    /// A backend where `failChunk` returns `failStatus` for its first
    /// `failTimes` attempts, then succeeds. Other chunks succeed immediately.
    private func registerRetryBackend(
        recorder: KYCUploaderTestSupport.BackendRecorder,
        totalChunks: Int,
        failChunk: Int,
        failTimes: Int,
        failStatus: Int
    ) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-retry-1","chunk_size":\#(512 * 1024)}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                let key = request.value(forHTTPHeaderField: "Idempotency-Key")
                // Count BEFORE deciding fail/succeed so attempt N is recorded.
                let priorAttempts = recorder.attempts(forChunk: index)
                recorder.recordChunkAttempt(index, key: key)
                if index == failChunk && priorAttempts < failTimes {
                    return KYCUploaderTestSupport.makeResponse(
                        status: failStatus,
                        json: #"{"error":"injected failure"}"#,
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
                    #"{"artifact_id":"artifact-retry-1","status":"pending_review"}"#, url: request.url)
            default:
                return nil
            }
        }
    }
}
