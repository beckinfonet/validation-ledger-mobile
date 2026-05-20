// validationLedgerTests/App/AppContainerNetworkConfigTests.swift
// NET-03 simulator tests — verify AppContainer supports one-line .mock/.live swap +
// composes APIClient with the Plan 04 interceptor chain.
//
// The dev-menu interactive swap (SceneDelegate observer + DevMenu) is HUMAN-UAT; these
// tests verify the construction path + interceptor wiring, which together constitute
// NET-03 SC-1 ("one-line swap") + SC-2 ("call sites don't change") programmatic evidence.
//
// @Suite(.serialized) — MockURLProtocol.handlers is a global registry; parallel sibling
// suites would thrash it (Pitfall P20 / Plan 02-03 deferred-items note).

import Testing
import Foundation
@testable import validationLedger

@Suite("AppContainer — NET-03 network config swap", .serialized)
struct AppContainerNetworkConfigTests {

    // MARK: - Helpers

    private func debugEnv(baseURL: URL? = nil) -> Environment {
        Environment(name: "test", keychainAccessGroup: nil, apiBaseURL: baseURL)
    }

    // MARK: - Tests

    @Test("Default construction (no override) constructs apiClient + networkClient in DEBUG")
    func defaultNetworkConfigInDebug() throws {
        // We run tests under DEBUG, so defaultNetworkConfig returns .mock.
        let container = AppContainer(
            env: debugEnv(baseURL: nil),
            networkConfig: nil,
            isSecureEnclaveAvailable: true
        )
        // Smoke: apiClient exists; networkClient is the URLSessionNetworkClient wrapper.
        _ = container.apiClient
        #expect(container.networkClient is URLSessionNetworkClient)
    }

    @Test(".mock override constructs a working APIClient — request/decode via MockURLProtocol")
    func mockOverrideConstructs() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let fixture = try FixtureLoader.loadFixture("otp-request-success")
        MockURLProtocol.registerFixture(
            for: OTPRequestEndpoint.self,
            path: "/auth/otp/request",
            method: .post,
            statusCode: 200,
            body: fixture
        )

        let container = AppContainer(
            env: debugEnv(baseURL: nil),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        // Exercise the full stack: apiClient → IdempotencyInterceptor → NetworkClient
        // → URLSession (.ephemeral + MockURLProtocol) → fixture → decoder.
        let response = try await container.apiClient.request(OTPRequestEndpoint(phone: "+14155550129"))
        #expect(response.otpSessionID == "sess-abc-123")
        #expect(response.expiresInSeconds == 120)
    }

    @Test(".live(baseURL:) override accepts a URL and constructs apiClient without crashing")
    func liveOverrideAcceptsBaseURL() {
        let baseURL = URL(string: "https://api.validationledger.com")!
        // .live installs PinningSessionDelegate(pins: PinnedSPKIs.current) — verify construction
        // doesn't trap even with the staging placeholder pins in DEBUG.
        let container = AppContainer(
            env: debugEnv(baseURL: baseURL),
            networkConfig: .live(baseURL: baseURL),
            isSecureEnclaveAvailable: true
        )
        _ = container.apiClient
        #expect(container.networkClient is URLSessionNetworkClient)
    }

    @Test("Idempotency-Key header injected on POST via the default interceptor chain (NET-04 + NET-03 wiring)")
    func idempotencyInterceptorWired() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // Capture Idempotency-Key via a lock-guarded reference type. MockURLProtocol.register's
        // closure is @Sendable + synchronous — we can't await an actor inside it. An NSLock-backed
        // class mirrors the MockURLProtocol registry's own concurrency-safety pattern.
        let capture = IdempotencyHeaderCapture()
        MockURLProtocol.register { request in
            guard request.url?.path == "/auth/otp/request", request.httpMethod == "POST" else { return nil }
            if let key = request.value(forHTTPHeaderField: "Idempotency-Key") {
                capture.setKey(key)
            }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"otp_session_id":"sess-abc","expires_in_seconds":60}"#.utf8)
            return (resp, body)
        }

        let container = AppContainer(
            env: debugEnv(baseURL: nil),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )
        _ = try await container.apiClient.request(OTPRequestEndpoint(phone: "+14155550100"))

        let capturedKey = capture.current()
        #expect(capturedKey != nil, "Idempotency-Key header should be injected on POST via IdempotencyInterceptor")
        #expect(UUID(uuidString: capturedKey ?? "") != nil, "captured key should be a UUIDv4 string")
    }

    /// NSLock-guarded capture box — required because MockURLProtocol.register's closure is
    /// `@Sendable (URLRequest) -> (HTTPURLResponse, Data)?` (synchronous, so we can't await an
    /// actor). The pattern mirrors MockURLProtocol's own NSLock-backed handler registry
    /// (WR-01 fix from Plan 02-01).
    private final class IdempotencyHeaderCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var key: String?

        func setKey(_ k: String) {
            lock.withLock { self.key = k }
        }

        func current() -> String? {
            lock.withLock { self.key }
        }
    }
}

// MARK: - Phase 7 LOAD-01 (Plan 07-06) — SC #5 mock/live swap tests for the 3 new Load endpoints
//
// Roadmap SC #5: "the one-line swap to .live config still compiles + passes
// with the new endpoints registered." These tests pin three claims:
//
//   1. With .mock config, the new MockLoadFixtureRegistry handlers (Plan 07-06
//      Task 1) are wired through AppContainer.init's DEBUG block (Task 2) and
//      the 3 new Load endpoints flow end-to-end through apiClient.request<E>
//      (compile + run + decode).
//   2. With .live config, AppContainer's apiClient accepts the new endpoint
//      types at the request<E> call site (compile-clean — the request itself
//      may not be invoked because .live routes through PinningSessionDelegate
//      against a baseURL that does not resolve in test environments).
//   3. The .mock-config end-to-end pipeline produces semantically correct
//      Response values for each of the 3 endpoints — proves the entire stack
//      composes (registry → MockURLProtocol → APIClient → endpoint Decodable
//      Response → Plan 01 fail-closed decoders).
//
// .serialized — shares MockURLProtocol's global handler registry with the
// sibling .mock tests; parallelism here would thrash the handler list.

@Suite("AppContainer — Phase 7 load endpoints config swap (Plan 07-06 SC #5)", .serialized)
struct AppContainerLoadEndpointsConfigSwapTests {

    // MARK: - Helpers

    private func debugEnv(baseURL: URL? = nil) -> Environment {
        Environment(name: "test", keychainAccessGroup: nil, apiBaseURL: baseURL)
    }

    /// Helper that registers the Plan 07-06 MockLoadFixtureRegistry handlers
    /// after a clean MockURLProtocol reset. The .mock AppContainer DEBUG-block
    /// wiring path requires going through the AppContainer initializer (which
    /// already does this); in tests we replicate that wiring by hand so the
    /// test sees the same handler set even with an explicit reset at top.
    private func registerLoadFixtures() {
        MockURLProtocol.reset()
        MockLoadFixtureRegistry.registerAppDefaults()
    }

    // MARK: - Test 1 — .mock-config end-to-end swap

    @Test("loadEndpointsConfigSwap: with .mock config + load-fixture registry, the 3 Load endpoints flow through apiClient.request<E> end-to-end")
    func mockConfigEndToEndSwap() async throws {
        registerLoadFixtures()
        defer { MockURLProtocol.reset() }

        let container = AppContainer(
            env: debugEnv(baseURL: nil),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        // List — broker fixture has 9 loads (Plan 07-05 SUMMARY).
        let listResponse = try await container.apiClient.request(LoadListEndpoint(role: .broker))
        #expect(listResponse.loads.count == 9, "broker list fixture is the 9-load fixture from Plan 07-05")

        // Detail — VL-1001 is the clean verified delivered load.
        let detailResponse = try await container.apiClient.request(LoadDetailEndpoint(loadID: "VL-1001"))
        #expect(detailResponse.load.id == "VL-1001")
        #expect(detailResponse.chainOfTrust.integrity.verdict == .clean)

        // Action — POST /loads/VL-1004/accept returns the canonical success body.
        let actionBody = LoadActionEndpoint.RequestBody(
            actorRole: .carrier,
            targetPartyID: nil,
            respondByAt: nil,
            note: nil
        )
        let actionResponse = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1004", action: .accept, body: actionBody)
        )
        #expect(actionResponse.load.id.hasPrefix("VL-"))
    }

    // MARK: - Test 2 — .live-config compile-clean swap (SC #5)

    @Test("loadEndpointsConfigSwap: with .live config, apiClient.request<E> accepts all 3 new Load endpoints at the call site (compile-clean — SC #5)")
    func liveConfigCompileCleanSwap() async throws {
        // Roadmap SC #5: the .live config must compile + accept the new
        // endpoint types at the apiClient.request<E> call site, even though
        // PinningSessionDelegate's pinned URLSession on .live cannot resolve
        // https://api.validationledger.com from the simulator. We assert
        // construction-shape only — the existing liveOverrideAcceptsBaseURL
        // test (above) sets the precedent.
        let baseURL = URL(string: "https://api.validationledger.com")!
        let container = AppContainer(
            env: debugEnv(baseURL: baseURL),
            networkConfig: .live(baseURL: baseURL),
            isSecureEnclaveAvailable: true
        )

        // Compile-time proof that apiClient.request<E> accepts the 3 new
        // endpoint TYPES. We construct each endpoint and bind it to its
        // protocol-existential surface (`any APIEndpoint`); the Swift
        // typechecker rejects a struct that doesn't conform to APIEndpoint
        // at this assignment. We DELIBERATELY do not invoke `request<E>` on
        // .live because PinningSessionDelegate's pinned session cannot
        // resolve the staging baseURL from the simulator — SC #5 is a
        // COMPILE-time guarantee, not a network round-trip guarantee.
        let listEndpoint: any APIEndpoint = LoadListEndpoint(role: .broker)
        let detailEndpoint: any APIEndpoint = LoadDetailEndpoint(loadID: "VL-1001")
        let actionEndpoint: any APIEndpoint = LoadActionEndpoint(
            loadID: "VL-1004",
            action: .accept,
            body: LoadActionEndpoint.RequestBody(
                actorRole: .carrier,
                targetPartyID: nil,
                respondByAt: nil,
                note: nil
            )
        )
        // Compile-shape assertions: each endpoint's path encodes the route
        // the apiClient.request<E> stack will build URLRequests against.
        #expect(listEndpoint.path == "/loads/broker")
        #expect(detailEndpoint.path == "/loads/VL-1001")
        #expect(actionEndpoint.path == "/loads/VL-1004/accept")

        // Smoke: the container's apiClient is wired (existing-test precedent).
        _ = container.apiClient
        #expect(container.networkClient is URLSessionNetworkClient)
    }

    // MARK: - Test 3 — end-to-end Response decoding for each of the 3 endpoints

    @Test("loadEndpointsConfigSwap: .mock pipeline decodes each endpoint's Response into the correct typed value (registry → MockURLProtocol → APIClient → Decodable)")
    func mockConfigEndToEndDecode() async throws {
        registerLoadFixtures()
        defer { MockURLProtocol.reset() }

        let container = AppContainer(
            env: debugEnv(baseURL: nil),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        // VL-1009 is the double-broker fraud archetype — chainIntegrity.verdict
        // == .compromised exercises the fail-closed VerificationState / ChainIntegrity
        // decoder pipeline end-to-end (Plan 07-01 D-09).
        let detail = try await container.apiClient.request(LoadDetailEndpoint(loadID: "VL-1009"))
        #expect(detail.load.id == "VL-1009")
        #expect(detail.chainOfTrust.integrity.verdict == .compromised,
                "VL-1009 is the double-broker archetype — compromised verdict pins the full fail-closed decode pipeline")

        // List for carrier — Plan 07-05 confirms 6 loads.
        let list = try await container.apiClient.request(LoadListEndpoint(role: .carrier))
        #expect(list.loads.count == 6, "carrier list fixture is the 6-load fixture from Plan 07-05")
        // Pagination envelope decodes cleanly even when nextCursor is null.
        #expect(list.nextCursor == nil)

        // Action — verifies POST round-trip + RequestBody encoding + Response
        // decoding all compose. The fixture body is the VL-1004 post-accept
        // response; the chain's integrity.verdict is .clean (Plan 07-05).
        let action = try await container.apiClient.request(
            LoadActionEndpoint(
                loadID: "VL-1004",
                action: .accept,
                body: LoadActionEndpoint.RequestBody(
                    actorRole: .carrier,
                    targetPartyID: nil,
                    respondByAt: nil,
                    note: nil
                )
            )
        )
        #expect(action.load.id == "VL-1004")
        #expect(action.chainOfTrust.integrity.verdict == .clean)
    }
}
