// validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift
// Requirement: debug session `kyc-upload-capture-bugs` — Issue 2a (mock KYC
// fixtures) + the upload-pipeline reachability of all 6 KYC artifacts (Issue 2b).
//
// Issue 2a: a DEBUG build on a physical device runs networkConfig == .mock, but
// `MockDefaultFixtures` registered handlers for only the 5 auth/device endpoints
// — the 4 KYC upload endpoints (`/kyc/upload/init`, `/kyc/upload/chunk`,
// `/kyc/upload/commit`, `/kyc/submit`) 404'd, so every artifact's upload threw
// at init and the Review screen stuck at `.pending` forever.
//
// This suite drives the REAL `MockDefaultFixtures.dispatchHandler` (the exact
// catch-all the device build registers) through a real `APIClient` +
// `KYCUploader`, and verifies a full init→chunk→commit upload succeeds for every
// one of the 6 artifacts — including trailer and plate, the two the Issue 2b
// coordinator off-by-one never kicked on a real device. `.serialized` because
// the suite mutates the global `MockURLProtocol` handler registry.
//
// Extended for debug session `kyc-status-under-review-trap`:
// asserts the `-MockKYCStatusVerified` launch-arg toggle flips both
// /kyc/submit and /kyc/status to `verified` (and stays off by default).

import Testing
import Foundation
@testable import validationLedger

@Suite("MockDefaultFixtures — KYC upload endpoints (Issue 2a / 2b)", .serialized)
struct MockDefaultFixturesKYCTests {

    /// 3 chunks at the 512 KB default ⇒ ~1.2 MB (512 KB + 512 KB + ~228 KB).
    private static let threeChunkBytes = 512 * 1024 * 2 + 233_000

    // MARK: - Issue 2a — the four KYC endpoints respond 200

    @Test("Issue 2a: the device-mock dispatch handler answers POST /kyc/upload/init with 200 + a decodable Response")
    func mockHandlerAnswersUploadInit() async throws {
        let response = try await requestThroughMockDefaults(
            KYCUploadInitEndpoint(
                artifactType: .face,
                totalChunks: 3,
                totalBytes: Self.threeChunkBytes,
                sha256: String(repeating: "a", count: 64)
            )
        )
        // A non-empty uploadID + a positive chunkSize is the contract the
        // KYCUploader's init step depends on.
        #expect(!response.uploadID.isEmpty)
        #expect(response.chunkSize > 0)
    }

    @Test("Issue 2a: the device-mock dispatch handler answers POST /kyc/upload/chunk with 200 + a decodable Response")
    func mockHandlerAnswersUploadChunk() async throws {
        let response = try await requestThroughMockDefaults(
            KYCUploadChunkEndpoint(
                uploadID: "dev-mock-upload-1",
                chunkIndex: 0,
                chunkData: Data([0x01, 0x02]).base64EncodedString(),
                chunkSha256: String(repeating: "b", count: 64)
            )
        )
        // The mock reports totalChunks == 0; KYCUploader falls back to its own
        // locally-computed total when the server reports 0.
        #expect(response.totalChunks == 0)
        #expect(response.chunksAcked >= 1)
    }

    @Test("Issue 2a: the device-mock dispatch handler answers POST /kyc/upload/commit with 200 + a decodable Response")
    func mockHandlerAnswersUploadCommit() async throws {
        let response = try await requestThroughMockDefaults(
            KYCUploadCommitEndpoint(uploadID: "dev-mock-upload-1")
        )
        #expect(!response.artifactID.isEmpty)
        #expect(response.status == "pending_review")
    }

    @Test("Issue 2a: the device-mock dispatch handler answers POST /kyc/submit with 200 + a decodable Response")
    func mockHandlerAnswersSubmit() async throws {
        let response = try await requestThroughMockDefaults(
            KYCSubmitEndpoint(artifactIDs: ["a", "b", "c", "d", "e", "f"])
        )
        #expect(response.overallStatus == "under_review")
    }

    @Test("Gap (Test 9): the device-mock dispatch handler answers GET /kyc/status with 200 + a decodable Response")
    func mockHandlerAnswersStatus() async throws {
        // Before plan 05-09 added the (GET, /kyc/status) route, this request
        // 404'd — `requestThroughMockDefaults` would throw
        // `NetworkError.httpError(404)` and `KYCStatusViewModel.fetchStatus()`
        // fell into `.error` ("Couldn't load status"). A non-throwing decode
        // proves the route now serves a verdict.
        let response = try await requestThroughMockDefaults(KYCStatusEndpoint())
        // Must agree with kycSubmitResponseJSON()'s post-submit `under_review`.
        #expect(response.overallStatus == "under_review")
        // The device mock cannot read the request body, so it serves no
        // per-artifact detail.
        #expect(response.artifacts.isEmpty)
    }

    // MARK: - Full pipeline — all 6 artifacts upload against the device mock

    @Test("Issue 2a/2b: every one of the 6 KYC artifacts uploads init→chunk→commit against the device-mock fixtures")
    func allSixArtifactsUploadAgainstMockDefaults() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        // Register the EXACT catch-all the DEBUG device build registers.
        MockURLProtocol.register(MockDefaultFixtures.dispatchHandler)

        // The 6 KYC artifacts, in capture order — including trailer and plate,
        // the two the Issue 2b coordinator off-by-one never kicked on device.
        let allArtifacts: [KYCUploadInitEndpoint.ArtifactType] =
            [.face, .dlFront, .dlBack, .truck, .trailer, .plate]

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        for artifact in allArtifacts {
            session.artifactData[artifact.rawValue] =
                KYCUploaderTestSupport.artifactData(byteCount: Self.threeChunkBytes)
        }
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )

        // Upload every artifact. Before Issue 2a this threw at the init POST
        // for ALL of them (404 → KYCUploadError.nonRetryable).
        for artifact in allArtifacts {
            try await uploader.upload(artifactType: artifact)
        }

        // Every artifact must now be committed with a server artifactID — the
        // exact state the Review screen reads to enable the gated Submit.
        let finalSession = try #require(try store.loadSession())
        for artifact in allArtifacts {
            let state = try #require(
                finalSession.state(for: artifact),
                "no upload state persisted for \(artifact.rawValue)"
            )
            #expect(state.committed, "\(artifact.rawValue) never committed")
            #expect(state.artifactID != nil, "\(artifact.rawValue) has no artifactID")
        }
    }

    // MARK: - `-MockKYCStatusVerified` launch-arg toggle
    //
    // Debug session `kyc-status-under-review-trap`: the under-review pin on
    // /kyc/status blocks the only path past the D-12 gate during device UAT.
    // `-MockKYCStatusVerified` is the documented opt-in escape — it flips
    // BOTH /kyc/submit and /kyc/status to `verified` so the status screen's
    // verified verdict + "Continue" CTA becomes reachable on a no-backend
    // DEBUG build.

    @Test("Toggle off (default): /kyc/status JSON encodes `under_review`")
    func defaultStatusJSONIsUnderReview() {
        let body = MockDefaultFixtures.kycStatusResponseJSON(verifiedOverride: false)
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["overall_status"] as? String == "under_review")
        #expect((json?["artifacts"] as? [Any])?.isEmpty == true)
    }

    @Test("Toggle off (default): /kyc/submit JSON encodes `under_review`")
    func defaultSubmitJSONIsUnderReview() {
        let body = MockDefaultFixtures.kycSubmitResponseJSON(verifiedOverride: false)
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["overall_status"] as? String == "under_review")
    }

    @Test("Toggle on: /kyc/status JSON encodes `verified`")
    func overrideStatusJSONIsVerified() {
        let body = MockDefaultFixtures.kycStatusResponseJSON(verifiedOverride: true)
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["overall_status"] as? String == "verified")
        #expect((json?["artifacts"] as? [Any])?.isEmpty == true)
    }

    @Test("Toggle on: /kyc/submit JSON encodes `verified`")
    func overrideSubmitJSONIsVerified() {
        let body = MockDefaultFixtures.kycSubmitResponseJSON(verifiedOverride: true)
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["overall_status"] as? String == "verified")
    }

    @Test("Test process: -MockKYCStatusVerified is NOT a default launch arg — the test runner never trips the verified branch organically")
    func testRunnerIsOffByDefault() {
        // Guards the call sites in dispatchHandler — the test runner must not
        // carry the launch arg, otherwise the existing `mockHandlerAnswersStatus`
        // / `mockHandlerAnswersSubmit` baseline tests would silently flip.
        #expect(MockDefaultFixtures.verifiedKYCStatusOverrideActive == false)
    }

    // MARK: - Helpers

    /// Issue the endpoint through a real `APIClient` wired to ONLY the
    /// `MockDefaultFixtures` catch-all dispatch handler — the precise
    /// configuration a DEBUG physical-device build runs.
    private func requestThroughMockDefaults<E: APIEndpoint>(
        _ endpoint: E
    ) async throws -> E.Response {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.register(MockDefaultFixtures.dispatchHandler)
        return try await KYCUploaderTestSupport.makeClient().request(endpoint)
    }
}
