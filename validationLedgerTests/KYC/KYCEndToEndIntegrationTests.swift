// validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift
// Phase 5 Plan 08 Task 1 — the simulator-side end-to-end KYC pipeline proof.
// Requirements: KYC-01 / KYC-06 / UPL-02 — SC-1 / SC-3 / SC-5 simulator portion.
//
// This suite drives the WHOLE KYC pipeline against MockURLProtocol fixtures —
// init → chunk → commit (×6 artifacts) → submit → status — and asserts the
// end-to-end result is the expected backend verdict and that all 6 artifacts
// committed. The not-simulator-testable behaviors (SC-2 force-quit, SC-4
// background upload) are routed to the device lane + the Task-3 HUMAN-UAT
// checkpoint; this suite proves everything the simulator CAN exercise.
//
// === Why this is a real end-to-end test, not a unit test ===
// It composes the SHIPPED pieces exactly as the app does: a real `KYCUploader`
// actor driving the real `APIClient` (+ real `IdempotencyInterceptor`) through
// `MockURLProtocol`, a real `KYCSessionStore` on disk (a temp directory), the
// shipped `KYCSubmitEndpoint`, and the real `KYCStatusViewModel.mapState(from:)`
// verdict mapping. Nothing here is stubbed except the network transport.
//
// `@Suite(.serialized)` is mandatory — every `@Test` mutates the global
// `MockURLProtocol` handler registry (Phase 2 SUMMARY; KYCUploader* pattern).

import Testing
import Foundation
@testable import validationLedger

@Suite("KYC end-to-end pipeline — init→chunk→commit→submit→status (KYC-01/06, UPL-02)", .serialized)
struct KYCEndToEndIntegrationTests {

    /// The 6 KYC artifacts the capture flow produces (D-01).
    private static let allArtifacts: [KYCUploadInitEndpoint.ArtifactType] =
        [.face, .dlFront, .dlBack, .truck, .trailer, .plate]

    /// A small synthetic artifact — 3 chunks at 512 KB so the chunk loop is
    /// genuinely exercised (init/chunk×3/commit), but the test stays fast.
    /// "Small" here means small relative to a real multi-MB identity image;
    /// the SC-2 device test uses the real 6 MB payload on hardware.
    private static let artifactByteCount = 512 * 1024 * 2 + 64_000

    @Test("SC-1/SC-3/SC-5: a full 6-artifact KYC flow runs init→chunk→commit→submit→status end-to-end")
    func fullPipelineReachesUnderReview() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // --- Mock KYC backend ------------------------------------------------
        // One handler covering every KYC endpoint the pipeline touches. The
        // recorder tallies init/chunk/commit so the test can assert exact
        // request counts across all 6 artifacts.
        let backend = EndToEndBackend()
        backend.register()

        // --- Seed the in-progress KYC session --------------------------------
        // A fresh on-disk KYCSessionStore in a temp directory, seeded with all
        // 6 captured artifacts — exactly what the capture flow persists.
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        for artifact in Self.allArtifacts {
            session.artifactData[artifact.rawValue] =
                KYCUploaderTestSupport.artifactData(byteCount: Self.artifactByteCount)
        }
        try store.persist(session)

        // --- 1. Upload all 6 artifacts through the real KYCUploader ----------
        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        for artifact in Self.allArtifacts {
            try await uploader.upload(artifactType: artifact)
        }

        // Every artifact ran exactly one init → 3 chunk POSTs → one commit.
        #expect(backend.initCount == 6, "exactly one init per artifact")
        #expect(backend.commitCount == 6, "exactly one commit per artifact")
        #expect(backend.totalChunkRequests == 18, "3 chunk POSTs × 6 artifacts")

        // All 6 ArtifactUploadStates are committed on disk with a server ID.
        let afterUpload = try #require(try store.loadSession())
        var committedArtifactIDs: [String] = []
        for artifact in Self.allArtifacts {
            let state = try #require(
                afterUpload.state(for: artifact),
                "every artifact has an upload state"
            )
            #expect(state.committed == true, "\(artifact.rawValue) committed")
            #expect(state.localDataAvailable == false, "\(artifact.rawValue) local bytes freed (D-02)")
            let artifactID = try #require(state.artifactID, "\(artifact.rawValue) has a server artifactID")
            committedArtifactIDs.append(artifactID)
        }
        #expect(committedArtifactIDs.count == 6, "6 committed artifact IDs to submit")

        // --- 2. Fire the thin /kyc/submit finalizer with the 6 IDs -----------
        let submitClient = KYCUploaderTestSupport.makeClient()
        let submitResponse = try await submitClient.request(
            KYCSubmitEndpoint(artifactIDs: committedArtifactIDs)
        )
        #expect(submitResponse.overallStatus == "under_review",
                "submit fixture reports the under_review verdict")
        #expect(backend.submitCount == 1, "exactly one /kyc/submit call")
        #expect(backend.lastSubmitArtifactIDCount == 6,
                "the submit body carried all 6 committed artifact IDs")

        // --- 3. Drive the status verdict through the real status VM ----------
        // KYCStatusViewModel.fetchStatus() does GET /kyc/status and maps the
        // verdict; the mock returns the kyc-status-under-review fixture shape.
        let statusViewModel = await KYCStatusViewModel(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            // Phase 6 D6-08: KYCStatusViewModel now refreshes the cached
            // .kycStatus Keychain item after GET /kyc/status. A uniquely-
            // serviced test KeychainStore isolates this suite's partition.
            keychain: KeychainStore(service: "vl.test.kyc.e2e.\(UUID().uuidString)"),
            logger: KYCUploaderTestSupport.makeLogger()
        )
        await statusViewModel.fetchStatus()
        let finalState = await statusViewModel.state
        #expect(finalState == .underReview,
                "the end-to-end pipeline lands on the under-review verdict")
        #expect(backend.statusCount == 1, "exactly one GET /kyc/status")
    }

    @Test("UPL-02: the end-to-end flow resumes a partially-uploaded artifact from its chunksAcked cursor")
    func pipelineResumesPartialArtifact() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let backend = EndToEndBackend()
        backend.register()

        // Seed a session where the `face` artifact is mid-upload: its init has
        // already succeeded and 2 of its 3 chunks are acked. This is the
        // on-disk state after a force-quit between chunk 2 and chunk 3.
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.artifactByteCount)
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            ArtifactUploadState(
                artifactType: .face,
                uploadID: "up-resume-face",
                totalChunks: 3,
                totalBytes: bytes.count,
                chunkSize: KYCUploader.defaultChunkSize,
                chunksAcked: 2,        // 2 of 3 already done
                sha256: "",
                committed: false,
                artifactID: nil,
                localDataAvailable: true
            )
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        // Resume means: NO init (it already succeeded), only the ONE remaining
        // chunk (#2), then the commit — not a restart from chunk 0.
        #expect(backend.initCount == 0, "resume skips init — the upload was already started")
        #expect(backend.totalChunkRequests == 1, "only the single remaining chunk is sent")
        #expect(backend.commitCount == 1, "the resumed artifact still commits")

        let after = try #require(try store.loadSession())
        let state = try #require(after.state(for: .face))
        #expect(state.committed == true, "the resumed artifact reaches committed")
    }

    // MARK: - Mock KYC backend

    /// A lock-guarded recorder + a single `MockURLProtocol` handler covering
    /// every KYC endpoint the end-to-end pipeline touches: init, chunk, commit,
    /// submit, status.
    final class EndToEndBackend: @unchecked Sendable {
        private let lock = NSLock()
        private var _initCount = 0
        private var _commitCount = 0
        private var _submitCount = 0
        private var _statusCount = 0
        private var _chunkRequests = 0
        private var _lastSubmitArtifactIDCount = 0

        var initCount: Int { lock.withLock { _initCount } }
        var commitCount: Int { lock.withLock { _commitCount } }
        var submitCount: Int { lock.withLock { _submitCount } }
        var statusCount: Int { lock.withLock { _statusCount } }
        var totalChunkRequests: Int { lock.withLock { _chunkRequests } }
        var lastSubmitArtifactIDCount: Int { lock.withLock { _lastSubmitArtifactIDCount } }

        func register() {
            MockURLProtocol.register { [self] request in
                guard let path = request.url?.path else { return nil }
                switch (path, request.httpMethod) {
                case ("/kyc/upload/init", "POST"):
                    lock.withLock { _initCount += 1 }
                    // A per-artifact upload_id so the commit can derive a
                    // distinct artifact_id for each of the 6 artifacts.
                    let body = KYCUploaderTestSupport.bodyData(from: request)
                    let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                    let artifactType = (json?["artifact_type"] as? String) ?? "unknown"
                    let payload = #"{"upload_id":"up-\#(artifactType)","chunk_size":\#(KYCUploader.defaultChunkSize)}"#
                    return KYCUploaderTestSupport.make200(payload, url: request.url)

                case ("/kyc/upload/chunk", "POST"):
                    lock.withLock { _chunkRequests += 1 }
                    let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                    let acked = index + 1
                    let payload = #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":3}"#
                    return KYCUploaderTestSupport.make200(payload, url: request.url)

                case ("/kyc/upload/commit", "POST"):
                    lock.withLock { _commitCount += 1 }
                    // Derive the artifact_id from the upload_id in the body so
                    // each of the 6 commits yields a distinct, stable ID.
                    let body = KYCUploaderTestSupport.bodyData(from: request)
                    let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                    let uploadID = (json?["upload_id"] as? String) ?? "up-unknown"
                    let payload = #"{"artifact_id":"artifact-\#(uploadID)","status":"pending_review"}"#
                    return KYCUploaderTestSupport.make200(payload, url: request.url)

                case ("/kyc/submit", "POST"):
                    let body = KYCUploaderTestSupport.bodyData(from: request)
                    let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                    let ids = (json?["artifact_ids"] as? [Any]) ?? []
                    lock.withLock {
                        _submitCount += 1
                        _lastSubmitArtifactIDCount = ids.count
                    }
                    return KYCUploaderTestSupport.make200(
                        #"{"overall_status":"under_review"}"#, url: request.url)

                case ("/kyc/status", "GET"):
                    lock.withLock { _statusCount += 1 }
                    return KYCUploaderTestSupport.make200(
                        #"{"overall_status":"under_review","artifacts":[]}"#, url: request.url)

                default:
                    return nil
                }
            }
        }
    }
}
