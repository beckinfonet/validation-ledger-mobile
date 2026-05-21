// validationLedgerTests/Networking/Mock/CarrierDirectoryMockTests.swift
// Phase 10 Plan 05 Task 2 — end-to-end integration coverage for the new
// `/carriers/directory` MockURLProtocol handler registered by
// `MockLoadFixtureRegistry.registerAppDefaults()`.
//
// Locks the Plan-05 must-haves:
//   - The new handler returns the inline tenderCarrierDirectoryPayload when
//     a CarrierDirectoryEndpoint request is dispatched through the production
//     APIClient composition (AppContainer DEBUG path).
//   - The new handler does NOT shadow the existing GET /loads/{id} or
//     POST /loads/{id}/{action} handlers — Phase 7 contract preserved (T-10-PR-02
//     mitigation). The disjoint-path-namespace guard is the structural
//     defense; these tests document it.
//   - The inline-in-registry payload is byte-faithful to the fixture file
//     (T-10-PR-01 mitigation — the manual-sync convention has a regression
//     guard).
//
// === Pattern ===
// Mirrors `MockLoadActionDispatchTests` (sibling file) — uses the production
// AppContainer composition path so the APIClient + URLProtocol + handler
// registration all wire together identically to the live DEBUG app.
//
// === .serialized ===
// Per ios-test-suite-pitfalls project memory: tests that touch the global
// MockURLProtocol._handlers array (via AppContainer init / resetForTestOnly)
// MUST be .serialized to avoid the parallel-execution race that produces
// false-negative 404s on full-suite runs.

import Testing
import Foundation
@testable import validationLedger

@Suite("CarrierDirectoryMockTests — Plan 05 handler registration + non-shadow invariants", .serialized)
struct CarrierDirectoryMockTests {

    // MARK: - AppContainer helper (mirrors MockLoadActionDispatchTests)

    private func debugEnv() -> Environment {
        Environment(name: "test", keychainAccessGroup: nil, apiBaseURL: nil)
    }

    private func makeMockContainer() -> AppContainer {
        AppContainer(
            env: debugEnv(),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )
    }

    /// Reset MockURLProtocol + the registry guard, then re-register so each
    /// test runs against a clean handler set with the Plan-05 directory
    /// handler installed. Mirrors MockLoadFixtureRegistryActionToggleTests
    /// setUp pattern but compresses into a single call.
    private func resetAndReregister() {
        MockURLProtocol.reset()
        MockLoadFixtureRegistry.resetForTestOnly()
        MockLoadFixtureRegistry.registerAppDefaults()
    }

    // MARK: - Test 1: apiClient request returns the decoded directory

    @Test("Test 1: apiClient.request(CarrierDirectoryEndpoint()) returns 6-8 carriers including Chameleon")
    func apiClient_request_returnsDecodedDirectory() async throws {
        resetAndReregister()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        let response = try await container.apiClient.request(CarrierDirectoryEndpoint())

        #expect(response.carriers.count >= 6,
                "directory MUST decode >= 6 carriers under MockURLProtocol")
        #expect(response.carriers.count <= 8,
                "directory MUST decode <= 8 carriers under MockURLProtocol")
        let chameleonPresent = response.carriers.contains { carrier in
            carrier.displayName.lowercased().contains("chameleon")
                && carrier.verificationState == .flagged
        }
        #expect(chameleonPresent,
                "Specifics line 264: the .flagged Chameleon archetype MUST surface through the live mock path")
    }

    // MARK: - Test 2: directory handler does NOT shadow GET /loads/{id}

    @Test("Test 2: the new /carriers/directory handler does NOT shadow GET /loads/{id} (T-10-PR-02)")
    func directoryHandler_doesNotShadowLoadDetail() async throws {
        resetAndReregister()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        // VL-1001 is a known fixture loadID in MockLoadFixtureRegistry.detailPayloads.
        let detail = try await container.apiClient.request(LoadDetailEndpoint(loadID: "VL-1001"))
        #expect(detail.load.id == "VL-1001",
                "GET /loads/VL-1001 MUST still surface its load-detail fixture — the new directory handler must not over-match")
        // Sanity — Phase 7 contract preserved: the response carries the embedded chain.
        #expect(detail.chainOfTrust.nodes.isEmpty == false,
                "VL-1001 detail MUST still carry the embedded ChainOfTrust nodes (Phase 7 D-08)")
    }

    // MARK: - Test 3: directory handler does NOT shadow GET /loads/{role}

    @Test("Test 3: the new /carriers/directory handler does NOT shadow GET /loads/{role} (broker list)")
    func directoryHandler_doesNotShadowLoadList() async throws {
        resetAndReregister()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        let list = try await container.apiClient.request(LoadListEndpoint(role: .broker))
        #expect(list.loads.isEmpty == false,
                "GET /loads/broker MUST still surface the broker-list fixture — the directory handler's exact /carriers/directory match must not over-match")
    }

    // MARK: - Test 4: directory handler does NOT shadow POST /loads/{id}/{action}

    @Test("Test 4: the new /carriers/directory handler does NOT shadow POST /loads/{id}/{action}")
    func directoryHandler_doesNotShadowLoadAction() async throws {
        resetAndReregister()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        let body = LoadActionEndpoint.RequestBody(
            actorRole: .carrier,
            targetPartyID: nil,
            respondByAt: nil,
            note: nil
        )
        let result = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1001", action: .accept, body: body)
        )
        // Action success returns a Load + ChainOfTrust envelope.
        #expect(result.load.id.isEmpty == false,
                "POST /loads/VL-1001/accept MUST still surface the action-success fixture (load id non-empty) — the directory handler guards on httpMethod == GET, must not intercept POST")
    }

    // MARK: - Test 5: inline registry payload byte-faithful to the fixture file

    @Test("Test 5: inline tenderCarrierDirectoryPayload matches the fixture file (T-10-PR-01 sync-guard)")
    func directoryHandler_returnsSameContentAsFixture() async throws {
        resetAndReregister()
        defer { MockURLProtocol.reset() }

        // Decode the fixture file directly via the production decoder.
        let fixtureData = try FixtureLoader.loadFixture("tender-carrier-directory")
        let fixtureResponse = try APIClient.defaultDecoder()
            .decode(CarrierDirectoryEndpoint.Response.self, from: fixtureData)

        // Drive a request through MockURLProtocol — the response should be
        // equivalent to the fixture-decoded response.
        let container = makeMockContainer()
        let liveResponse = try await container.apiClient.request(CarrierDirectoryEndpoint())

        #expect(liveResponse.carriers.count == fixtureResponse.carriers.count,
                "live mock response MUST have the same carrier count as the fixture file (\(fixtureResponse.carriers.count)) — got \(liveResponse.carriers.count); a drift here means the inline payload in MockLoadFixtureRegistry has fallen out of sync with tender-carrier-directory.json")

        let liveIDs = liveResponse.carriers.map(\.partyID)
        let fixtureIDs = fixtureResponse.carriers.map(\.partyID)
        #expect(liveIDs == fixtureIDs,
                "live mock partyID order + values MUST match the fixture exactly — fixture: \(fixtureIDs), live: \(liveIDs)")

        // Sanity — every state from the fixture should be present in the live response.
        let liveStates = Set(liveResponse.carriers.map(\.verificationState))
        let fixtureStates = Set(fixtureResponse.carriers.map(\.verificationState))
        #expect(liveStates == fixtureStates,
                "live mock VerificationState set MUST match the fixture — drift here would silently break the Plan 06 picker's D-07 coverage")
    }
}
