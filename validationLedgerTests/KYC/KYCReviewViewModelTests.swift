// validationLedgerTests/KYC/KYCReviewViewModelTests.swift
// Requirement: KYC-01 / D-03 — the Review-screen gated-Submit state machine.
//
// This file was a Wave-0 RED scaffold (plan 05-01 Task 3) with a single
// placeholder @Test. Plan 05-06 fills it in (turns it GREEN): the real
// gated-Submit assertions — Submit is disabled until all 6 artifacts are
// committed, enabled exactly when all 6 are committed, `submit()` fires
// `KYCSubmitEndpoint` exactly once, and `retryUpload` re-invokes the uploader.
//
// Drives the real `APIClient` + `MockURLProtocol` (reusing KYCUploaderTestSupport)
// and a real temp-directory `KYCSessionStore`. `.serialized` because the suite
// mutates the global MockURLProtocol handler registry.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCReviewViewModel — gated-Submit state machine (KYC-01 / D-03)", .serialized)
struct KYCReviewViewModelTests {

    // MARK: - Fixtures

    /// Build a `KYCSession` whose artifacts are all committed (each with a
    /// server `artifactID`) — the all-6-acked Submit-enabled state.
    private func allCommittedSession() -> KYCSession {
        var session = KYCSession()
        for artifact in KYCReviewViewModel.artifactOrder {
            session.uploadStates[artifact.rawValue] = ArtifactUploadState(
                artifactType: artifact,
                uploadID: "up-\(artifact.rawValue)",
                totalChunks: 3,
                totalBytes: 1024,
                chunkSize: 512,
                chunksAcked: 3,
                sha256: "deadbeef",
                committed: true,
                artifactID: "art-\(artifact.rawValue)-001",
                localDataAvailable: false
            )
        }
        return session
    }

    /// A `KYCSession` with only `committedCount` artifacts committed; the rest
    /// are mid-upload (not committed).
    private func partialSession(committedCount: Int) -> KYCSession {
        var session = KYCSession()
        for (index, artifact) in KYCReviewViewModel.artifactOrder.enumerated() {
            let committed = index < committedCount
            session.uploadStates[artifact.rawValue] = ArtifactUploadState(
                artifactType: artifact,
                uploadID: "up-\(artifact.rawValue)",
                totalChunks: 3,
                totalBytes: 1024,
                chunkSize: 512,
                chunksAcked: committed ? 3 : 1,
                sha256: "deadbeef",
                committed: committed,
                artifactID: committed ? "art-\(artifact.rawValue)-001" : nil,
                localDataAvailable: !committed
            )
        }
        return session
    }

    @MainActor
    private func makeViewModel(store: KYCSessionStore, apiClient: APIClient) -> KYCReviewViewModel {
        KYCReviewViewModel(
            apiClient: apiClient,
            store: store,
            kycUploader: KYCUploader(
                apiClient: apiClient,
                store: store,
                logger: KYCUploaderTestSupport.makeLogger()
            ),
            logger: KYCUploaderTestSupport.makeLogger()
        )
    }

    /// A mutable, lock-guarded counter so the @Sendable MockURLProtocol handler
    /// can tally `/kyc/submit` POSTs across a test.
    private final class SubmitRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.withLock { _count } }
        func record() { lock.withLock { _count += 1 } }
    }

    // MARK: - Tests

    @Test("KYC-01: Submit is gated until all 6 artifacts are captured and confirmed")
    func submitGatedUntilBundleComplete() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 5)) // 5 of 6 committed

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        let enabled = await viewModel.submitEnabled
        #expect(enabled == false, "Submit must be disabled while only 5 of 6 are committed")
    }

    @Test("KYC-01 / D-03: Submit enables exactly when all 6 artifacts are committed")
    func submitEnabledWhenAllSixCommitted() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(allCommittedSession())

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        let enabled = await viewModel.submitEnabled
        #expect(enabled == true, "Submit must enable once all 6 artifacts are committed")

        let rows = await viewModel.rows
        #expect(rows.count == 6)
        #expect(rows.allSatisfy { $0.status == .uploaded })
    }

    @Test("D-03: submit() fires KYCSubmitEndpoint exactly once with the 6 artifact IDs")
    func submitFiresFinalizerExactlyOnce() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = SubmitRecorder()
        MockURLProtocol.register { request in
            guard request.url?.path == "/kyc/submit" else { return nil }
            recorder.record()
            return KYCUploaderTestSupport.make200(
                #"{"overall_status":"under_review"}"#, url: request.url)
        }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(allCommittedSession())

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        var submittedFired = false
        await MainActor.run { viewModel.onSubmitted = { submittedFired = true } }

        await viewModel.submit()

        #expect(recorder.count == 1, "KYCSubmitEndpoint must be POSTed exactly once")
        #expect(submittedFired == true, "onSubmitted must bubble to the coordinator on success")

        let state = await viewModel.state
        #expect(state == .submitted)
    }

    @Test("D-03: submit() is a no-op when the all-6-committed gate is closed")
    func submitNoOpWhenGateClosed() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = SubmitRecorder()
        MockURLProtocol.register { request in
            guard request.url?.path == "/kyc/submit" else { return nil }
            recorder.record()
            return KYCUploaderTestSupport.make200(
                #"{"overall_status":"under_review"}"#, url: request.url)
        }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 4))

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()
        await viewModel.submit()

        #expect(recorder.count == 0, "submit() must not POST while the gate is closed")
    }

    @Test("D-03: retryUpload re-invokes the uploader for a failed artifact")
    func retryUploadReinvokesUploader() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // A backend recorder over the init/chunk/commit pipeline — a non-zero
        // initCount proves retryUpload re-invoked KYCUploader.upload(...).
        let backend = KYCUploaderTestSupport.BackendRecorder()
        MockURLProtocol.register { request in
            guard let path = request.url?.path else { return nil }
            switch path {
            case "/kyc/upload/init":
                backend.recordInit()
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-face-retry","chunk_size":524288}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? 0
                backend.recordChunkAttempt(index, key: nil)
                backend.recordChunkSuccess(index)
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(index + 1),"total_chunks":2}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                backend.recordCommit()
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"art-face-retry","status":"pending_review"}"#,
                    url: request.url)
            default:
                return nil
            }
        }

        let store = try KYCUploaderTestSupport.makeStore()
        // Seed a session whose face artifact has local bytes to (re-)upload.
        var session = partialSession(committedCount: 5)
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: 600_000)
        // The face artifact is NOT committed — it is the failed one.
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = nil
        try store.persist(session)

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()
        await viewModel.retryUpload(artifactType: .face)

        #expect(backend.initCount == 1, "retryUpload must re-invoke KYCUploader.upload — one init")
        #expect(backend.commitCount == 1, "the re-invoked upload must run through commit")
    }
}
