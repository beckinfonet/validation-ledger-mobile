// validationLedgerTests/KYC/KYCStatusViewModelTests.swift
// Requirement: KYC-05 — KYC status UI renders four states from backend fixtures.
//
// This file was a Wave-0 RED scaffold (plan 05-01 Task 3) with a single
// placeholder @Test. Plan 05-06 fills it in (turns it GREEN): the real
// four-state assertions — the kyc-status-pending / -under-review / -verified /
// -rejected fixtures each map to the correct view-model `State`; a rejected
// artifact's `rejectionReason` code maps to a non-empty localized sentence; an
// unknown code degrades to the generic copy (D-11).
//
// Drives the real `APIClient` + `MockURLProtocol` (reusing KYCUploaderTestSupport)
// and a real temp-directory `KYCSessionStore`. `.serialized` because the suite
// mutates the global MockURLProtocol handler registry.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCStatusViewModel — four-state rendering from fixtures (KYC-05)", .serialized)
struct KYCStatusViewModelTests {

    // MARK: - Helpers

    /// Register a MockURLProtocol handler that serves `fixture` for GET /kyc/status.
    private func registerStatusFixture(_ fixtureName: String) throws {
        let fixture = try FixtureLoader.loadFixture(fixtureName)
        MockURLProtocol.register { request in
            guard request.url?.path == "/kyc/status" else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, fixture)
        }
    }

    /// A fresh, uniquely-serviced `KeychainStore` per test so the `.kycStatus`
    /// refresh write (Phase 6 D6-08) lands in an isolated keychain partition.
    private func makeKeychain() -> KeychainStore {
        KeychainStore(service: "vl.test.kyc.status.\(UUID().uuidString)")
    }

    @MainActor
    private func makeViewModel(
        store: KYCSessionStore,
        keychain: KeychainStore? = nil
    ) -> KYCStatusViewModel {
        KYCStatusViewModel(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            keychain: keychain ?? makeKeychain(),
            logger: KYCUploaderTestSupport.makeLogger()
        )
    }

    // MARK: - Tests

    @Test("KYC-05: pending / under_review / verified / rejected fixtures each map to the right state")
    func fourStatesRenderFromFixtures() async throws {
        // --- pending ---
        do {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            try registerStatusFixture("kyc-status-pending")
            let store = try KYCUploaderTestSupport.makeStore()
            let viewModel = await makeViewModel(store: store)
            await viewModel.fetchStatus()
            let state = await viewModel.state
            #expect(state == .pending, "pending fixture must map to .pending")
        }

        // --- under_review ---
        do {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            try registerStatusFixture("kyc-status-under-review")
            let store = try KYCUploaderTestSupport.makeStore()
            let viewModel = await makeViewModel(store: store)
            await viewModel.fetchStatus()
            let state = await viewModel.state
            #expect(state == .underReview, "under_review fixture must map to .underReview")
        }

        // --- verified ---
        do {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            try registerStatusFixture("kyc-status-verified")
            let store = try KYCUploaderTestSupport.makeStore()
            let viewModel = await makeViewModel(store: store)
            await viewModel.fetchStatus()
            let state = await viewModel.state
            #expect(state == .verified, "verified fixture must map to .verified")
        }

        // --- rejected ---
        do {
            MockURLProtocol.reset()
            defer { MockURLProtocol.reset() }
            try registerStatusFixture("kyc-status-rejected")
            let store = try KYCUploaderTestSupport.makeStore()
            let viewModel = await makeViewModel(store: store)
            await viewModel.fetchStatus()
            let state = await viewModel.state
            guard case .rejected(let artifacts) = state else {
                Issue.record("rejected fixture must map to .rejected, got \(state)")
                return
            }
            // The rejected fixture has 2 rejected artifacts (face, dl_front).
            #expect(artifacts.count == 2, "two artifacts are rejected in the fixture")
        }
    }

    @Test("D-11: a rejected artifact's reason code maps to a non-empty localized sentence")
    func rejectedArtifactReasonMapsToLocalizedCopy() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        try registerStatusFixture("kyc-status-rejected")

        let store = try KYCUploaderTestSupport.makeStore()
        let viewModel = await makeViewModel(store: store)
        await viewModel.fetchStatus()

        let state = await viewModel.state
        guard case .rejected(let artifacts) = state else {
            Issue.record("expected .rejected, got \(state)")
            return
        }
        for artifact in artifacts {
            #expect(!artifact.reasonCopy.isEmpty,
                    "every rejected artifact must carry non-empty reason copy")
            // The fixture codes (face_not_centered, dl_front_glare) are in the
            // controlled vocabulary — the copy must NOT be the raw code string.
            #expect(artifact.reasonCopy != "face_not_centered")
            #expect(artifact.reasonCopy != "dl_front_glare")
        }
        // face_not_centered must resolve to its finalized sentence.
        let faceCopy = RejectionReasonCode.copy(for: "face_not_centered")
        #expect(artifacts.contains { $0.reasonCopy == faceCopy })
    }

    @Test("D-11: an unknown rejection code degrades to the generic copy")
    func unknownReasonCodeDegradesToGeneric() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // A synthetic fixture with an out-of-vocabulary rejection code.
        let json = """
        {
          "overall_status": "rejected",
          "artifacts": [
            { "artifact_id": "art-face-001", "status": "rejected",
              "rejection_reason": "totally_unknown_future_code" }
          ]
        }
        """
        MockURLProtocol.register { request in
            guard request.url?.path == "/kyc/status" else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data(json.utf8))
        }

        let store = try KYCUploaderTestSupport.makeStore()
        let viewModel = await makeViewModel(store: store)
        await viewModel.fetchStatus()

        let state = await viewModel.state
        guard case .rejected(let artifacts) = state, let only = artifacts.first else {
            Issue.record("expected .rejected with one artifact, got \(state)")
            return
        }
        // The raw unknown code must NEVER surface — it degrades to generic copy.
        let generic = RejectionReasonCode.copy(for: "totally_unknown_future_code")
        #expect(only.reasonCopy == generic)
        #expect(only.reasonCopy != "totally_unknown_future_code")
    }

    @Test("D-02: a verified verdict clears the on-disk KYC session")
    func verifiedVerdictClearsSession() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        try registerStatusFixture("kyc-status-verified")

        let store = try KYCUploaderTestSupport.makeStore()
        // Seed a non-empty in-progress session.
        var session = KYCSession()
        session.artifactData["face"] = Data([0x01, 0x02, 0x03])
        try store.persist(session)
        #expect(try store.loadSession() != nil, "session is seeded before the fetch")

        let viewModel = await makeViewModel(store: store)
        await viewModel.fetchStatus()

        let state = await viewModel.state
        #expect(state == .verified)
        // D-02 — the verified-clear path: the in-progress session is gone.
        #expect(try store.loadSession() == nil,
                "a verified verdict must clear the on-disk KYC session (D-02)")
    }

    @Test("KYC-05: artifact IDs map to artifact types for targeted re-capture (D-10)")
    func artifactIDMapsToTypeForRecapture() throws {
        #expect(KYCStatusViewModel.artifactType(forID: "art-face-001") == .face)
        #expect(KYCStatusViewModel.artifactType(forID: "art-dl-front-002") == .dlFront)
        #expect(KYCStatusViewModel.artifactType(forID: "art-dl-back-003") == .dlBack)
        #expect(KYCStatusViewModel.artifactType(forID: "art-trailer-005") == .trailer)
        #expect(KYCStatusViewModel.artifactType(forID: "art-plate-006") == .plate)
        // An unrecognized ID shape returns nil — that row simply has no Retake target.
        #expect(KYCStatusViewModel.artifactType(forID: "opaque-uuid-xyz") == nil)
    }

    // MARK: - Phase 6 D6-08 — kycStatus Keychain refresh after GET /kyc/status

    /// Read back the cached `.kycStatus` string from a test keychain.
    private func cachedKYCStatus(in keychain: KeychainStore) -> String? {
        guard let data = try? keychain.get(.kycStatus) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @Test("D6-08: a verified fetch refreshes Keychain .kycStatus to \"verified\"")
    func verifiedFetchRefreshesKeychainStatus() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        try registerStatusFixture("kyc-status-verified")

        let store = try KYCUploaderTestSupport.makeStore()
        let keychain = makeKeychain()
        let viewModel = await makeViewModel(store: store, keychain: keychain)

        await viewModel.fetchStatus()

        // D6-08: the fresh backend `overall_status` is now cached so the
        // fail-closed cold-boot SessionRestoreProbe routes on current truth.
        #expect(cachedKYCStatus(in: keychain) == "verified",
                "a verified GET /kyc/status must refresh Keychain .kycStatus to \"verified\"")
    }

    @Test("D6-08: a non-verified fetch caches the non-verified status verbatim (fail-closed preserved)")
    func nonVerifiedFetchCachesNonVerifiedStatus() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        try registerStatusFixture("kyc-status-under-review")

        let store = try KYCUploaderTestSupport.makeStore()
        let keychain = makeKeychain()
        let viewModel = await makeViewModel(store: store, keychain: keychain)

        await viewModel.fetchStatus()

        // D6-08 is a CORRECTNESS fix, not a relaxation: a non-"verified" status
        // is cached verbatim. The cold-boot probe still fails CLOSED on any
        // non-"verified" value — caching `under_review` keeps that gate honest.
        #expect(cachedKYCStatus(in: keychain) == "under_review",
                "a non-verified GET /kyc/status must cache the non-verified status verbatim")
        let state = await viewModel.state
        #expect(state == .underReview,
                "the routing/state mapping is unchanged — under_review still maps to .underReview")
    }

    @Test("D6-08: a fresh status overwrites a stale cached .kycStatus")
    func freshStatusOverwritesStaleCachedStatus() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        try registerStatusFixture("kyc-status-verified")

        let store = try KYCUploaderTestSupport.makeStore()
        let keychain = makeKeychain()
        // Seed a STALE cached status — a prior session's value.
        try keychain.set(
            Data("pending".utf8),
            for: .kycStatus,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        #expect(cachedKYCStatus(in: keychain) == "pending", "stale value is seeded")

        let viewModel = await makeViewModel(store: store, keychain: keychain)
        await viewModel.fetchStatus()

        #expect(cachedKYCStatus(in: keychain) == "verified",
                "a successful GET /kyc/status must overwrite the stale cached .kycStatus")
    }
}
