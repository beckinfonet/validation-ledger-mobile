// validationLedgerTests/KYC/KYCReviewViewModelTests.swift
// Requirement: KYC-01 / D-03 — the Review-screen gated-Submit state machine.
//
// This file was a Wave-0 RED scaffold (plan 05-01 Task 3) with a single
// placeholder @Test. Plan 05-06 fills it in (turns it GREEN): the real
// gated-Submit assertions — Submit is disabled until all 6 artifacts are
// committed, enabled exactly when all 6 are committed, `submit()` fires
// `KYCSubmitEndpoint` exactly once, and `retryUpload` re-invokes the uploader.
//
// Debug session `kyc-review-stale-status` adds the live-refresh assertions:
// `updateProgress` / `markFailed` flip a single row and recompute `submitEnabled`
// WITHOUT a store re-read — the path the coordinator-installed
// `KYCUploader.onProgress` observer drives so an upload that commits after the
// Review screen's single `viewWillAppear` refresh still reaches the grid (the
// last-captured Plate artifact in the device repro).
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

    // MARK: - Live-refresh path (debug: kyc-review-stale-status)
    //
    // These exercise `updateProgress` / `markFailed` — the methods the
    // coordinator-installed `KYCUploader.onProgress` observer drives. They are
    // the VM-level reproduction of the device bug: the LAST artifact (Plate)
    // commits AFTER the Review screen's single `viewWillAppear` refresh, so the
    // grid only reaches the all-6-`.uploaded` Submit-enabling state if a live
    // callback (not a store re-read) flips the row.

    @Test("D-01 live-refresh: updateProgress at 1.0 flips a pending row to .uploaded and enables Submit")
    func updateProgressCommitsLastArtifactAndEnablesSubmit() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // The exact device repro: 5 of 6 committed, the 6th (Plate) is the
        // last-captured artifact whose commit lands after the single refresh.
        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 5))

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        // Pre-condition — the stale state the device screenshot showed: Plate is
        // not `.uploaded`, and Submit is therefore gated closed.
        let beforeStatus = await viewModel.rowStatus(for: .plate)
        #expect(beforeStatus != .uploaded, "Plate starts NOT uploaded — the stuck-row state")
        let beforeEnabled = await viewModel.submitEnabled
        #expect(beforeEnabled == false, "Submit must be gated while Plate is not uploaded")

        // The live `onProgress` callback the coordinator installs — `fraction
        // == 1.0` is the post-commit emission `KYCUploader.upload` makes.
        var enabledChanges: [Bool] = []
        await MainActor.run {
            viewModel.onSubmitEnabledChange = { enabledChanges.append($0) }
            viewModel.updateProgress(for: .plate, fraction: 1.0)
        }

        // The row flips to `.uploaded` WITHOUT a store re-read.
        let afterStatus = await viewModel.rowStatus(for: .plate)
        #expect(afterStatus == .uploaded, "updateProgress at 1.0 must flip Plate to .uploaded")

        // Submit enables — the all-6-committed gate is now satisfied (D-03).
        let afterEnabled = await viewModel.submitEnabled
        #expect(afterEnabled == true, "Submit must enable once the last artifact reaches .uploaded")
        #expect(enabledChanges.last == true,
                "onSubmitEnabledChange must fire true so the VC re-enables the button")
    }

    @Test("D-01 live-refresh: updateProgress below 1.0 shows .uploading and keeps Submit gated")
    func updateProgressBelowOneShowsUploadingAndGatesSubmit() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 5))

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        await MainActor.run { viewModel.updateProgress(for: .plate, fraction: 0.5) }

        let status = await viewModel.rowStatus(for: .plate)
        #expect(status == .uploading(progress: 0.5),
                "a sub-1.0 chunk-ack fraction must render as determinate .uploading")
        let enabled = await viewModel.submitEnabled
        #expect(enabled == false, "Submit stays gated while Plate is only mid-upload")
    }

    @Test("D-01 live-refresh: a redundant updateProgress at the same status is a no-op")
    func updateProgressIsIdempotentAtSameStatus() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(allCommittedSession())

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        // All 6 are already `.uploaded`; a 1.0 callback for one of them (the
        // uploader's post-commit emission, harmless if the row is already
        // uploaded) must not churn `onRowsChange`.
        var rowsChangeCount = 0
        await MainActor.run {
            viewModel.onRowsChange = { _ in rowsChangeCount += 1 }
            viewModel.updateProgress(for: .plate, fraction: 1.0)
        }

        #expect(rowsChangeCount == 0,
                "updateProgress to the SAME status must not re-fire onRowsChange")
        let enabled = await viewModel.submitEnabled
        #expect(enabled == true, "Submit stays enabled — the redundant callback changed nothing")
    }

    @Test("D-03 live-refresh: markFailed flips a row to .failed and keeps Submit gated")
    func markFailedFlipsRowAndGatesSubmit() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 5))

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        var rowsChangeCount = 0
        await MainActor.run {
            viewModel.onRowsChange = { _ in rowsChangeCount += 1 }
            // The pipelined upload exhausted its retries — the coordinator's
            // `kickUpload` catch path drives this.
            viewModel.markFailed(.plate)
        }

        let status = await viewModel.rowStatus(for: .plate)
        #expect(status == .failed, "markFailed must flip the row to .failed (the ⚠ badge state)")
        #expect(rowsChangeCount == 1, "markFailed must re-fire onRowsChange exactly once")

        let enabled = await viewModel.submitEnabled
        #expect(enabled == false, "Submit must stay gated while an artifact is .failed")
    }

    @Test("D-03 live-refresh: a redundant markFailed at the same status is a no-op")
    func markFailedIsIdempotentAtSameStatus() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let store = try KYCUploaderTestSupport.makeStore()
        try store.persist(partialSession(committedCount: 5))

        let viewModel = await makeViewModel(store: store, apiClient: KYCUploaderTestSupport.makeClient())
        await viewModel.refresh()

        var rowsChangeCount = 0
        await MainActor.run {
            viewModel.markFailed(.plate)
            viewModel.onRowsChange = { _ in rowsChangeCount += 1 }
            viewModel.markFailed(.plate) // second call — already .failed
        }

        #expect(rowsChangeCount == 0,
                "a second markFailed on an already-.failed row must not re-fire onRowsChange")
    }
}
