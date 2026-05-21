// validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift
// Phase 10 D-19 + ACTION-08 — T-10-08 CRITICAL mitigation: this test asserts
// the `IdempotencyInterceptor`'s auto-injection actually reaches the mock
// handler when a `LoadActionEndpoint` POST is dispatched through the
// production AppContainer composition path.
//
// Pattern: register a side-effect MockURLProtocol handler at index 0 that
// captures the URLRequest (allHTTPHeaderFields snapshot), then returns nil
// to defer to the production action-success handler. Assertions read the
// captured headers + bodies.
//
// D-17 confirms v1.1 ships fresh UUID per request (no stable-key replay) —
// Test 2 asserts the contract is "fresh UUID per call". Stable-key replay
// is post-v1.1 work.

import Testing
import Foundation
@testable import validationLedger

@Suite("MockLoadActionDispatch — Idempotency-Key wire propagation (T-10-08)", .serialized)
struct MockLoadActionDispatchTests {

    // MARK: - Helpers

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

    /// NSLock-guarded capture box for the URLRequest objects the mock receives.
    /// Mirrors `AppContainerNetworkConfigTests.IdempotencyHeaderCapture`.
    private final class RequestCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        func record(_ r: URLRequest) {
            lock.withLock { self._requests.append(r) }
        }
        func all() -> [URLRequest] {
            lock.withLock { self._requests }
        }
    }

    private func makeAcceptBody() -> LoadActionEndpoint.RequestBody {
        LoadActionEndpoint.RequestBody(
            actorRole: .carrier,
            targetPartyID: nil,
            respondByAt: nil,
            note: nil
        )
    }

    private func makeTenderBody() -> LoadActionEndpoint.RequestBody {
        LoadActionEndpoint.RequestBody(
            actorRole: .broker,
            targetPartyID: "party-carrier-acme",
            respondByAt: Date(timeIntervalSinceNow: 3600),
            note: nil
        )
    }

    /// Install a side-effect capture handler in front of the production
    /// handlers. Returns the capture box. Call MockURLProtocol.reset() +
    /// MockLoadFixtureRegistry.resetForTestOnly() BEFORE invoking this so
    /// the side-effect handler registers at index 0 (first-match-wins);
    /// then the AppContainer's DEBUG block re-installs MockDefaultFixtures
    /// + MockLoadFixtureRegistry handlers at index >= 1.
    ///
    /// IMPORTANT: registers the side-effect handler AND constructs the
    /// container; returns both so the caller controls dispatch.
    private func installCapture() -> RequestCapture {
        MockURLProtocol.reset()
        MockLoadFixtureRegistry.resetForTestOnly()
        let capture = RequestCapture()
        MockURLProtocol.register { request in
            capture.record(request)
            return nil   // DEFERS — fall through to the production handlers.
        }
        return capture
    }

    // MARK: - Test 1: POST carries the Idempotency-Key header

    @Test("LoadActionEndpoint POST through AppContainer carries Idempotency-Key + UUIDv4 value")
    func loadActionPost_carriesIdempotencyKeyHeader() async throws {
        let capture = installCapture()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        _ = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1001", action: .accept, body: makeAcceptBody())
        )

        // Find the POST capture for /loads/VL-1001/accept (the side-effect
        // handler also runs on whatever else AppContainer init triggers —
        // we filter to our exact request).
        let captures = capture.all()
        let actionRequest = captures.first { request in
            request.httpMethod == "POST" &&
            request.url?.path == "/loads/VL-1001/accept"
        }
        let req = try #require(actionRequest, "side-effect handler should have seen the accept POST")
        let key = req.value(forHTTPHeaderField: "Idempotency-Key")
        #expect(key != nil, "Idempotency-Key MUST be on the wire — T-10-08 CRITICAL mitigation")
        let unwrapped = try #require(key)
        // UUIDv4 string is 36 chars including hyphens; Foundation's UUID parser
        // is the canonical validator.
        #expect(unwrapped.count == 36, "UUIDv4 string length is 36 chars")
        #expect(UUID(uuidString: unwrapped) != nil, "value MUST parse as a UUID")
    }

    // MARK: - Test 2: two sequential POSTs get different UUIDs (D-17 — fresh UUID per request)

    @Test("Two sequential POSTs receive DIFFERENT Idempotency-Key values (D-17 — fresh UUID per call)")
    func loadActionPost_differentRequests_haveDifferentIdempotencyKeys() async throws {
        let capture = installCapture()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        _ = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1001", action: .accept, body: makeAcceptBody())
        )
        _ = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1002", action: .accept, body: makeAcceptBody())
        )

        let acceptPosts = capture.all().filter { req in
            req.httpMethod == "POST" && req.url?.path.hasSuffix("/accept") == true
        }
        #expect(acceptPosts.count >= 2,
                "two POSTs to .accept should produce two captures")
        let uuid1 = try #require(acceptPosts[0].value(forHTTPHeaderField: "Idempotency-Key"))
        let uuid2 = try #require(acceptPosts[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(uuid1 != uuid2,
                "D-17: each request gets a FRESH UUID — stable-key replay is post-v1.1")
        #expect(uuid1.count == 36 && uuid2.count == 36, "both must be UUIDv4 string length")
        #expect(UUID(uuidString: uuid1) != nil && UUID(uuidString: uuid2) != nil,
                "both must parse as UUIDs (no constant-string regression, no hash regression)")
    }

    // MARK: - Test 3: GET requests do NOT carry the Idempotency-Key header

    @Test("LoadDetailEndpoint GET does NOT carry Idempotency-Key (Phase 2 NET-04 — POST/PUT only)")
    func loadActionPost_getRequest_doesNotCarryIdempotencyKey() async throws {
        let capture = installCapture()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        // VL-1001 is a known fixture loadID in MockLoadFixtureRegistry's
        // detailPayloads; the GET will resolve through (2) per-VL detail.
        _ = try await container.apiClient.request(LoadDetailEndpoint(loadID: "VL-1001"))

        let detailRequest = capture.all().first { req in
            req.httpMethod == "GET" && req.url?.path == "/loads/VL-1001"
        }
        let req = try #require(detailRequest, "side-effect handler should have seen the detail GET")
        #expect(req.value(forHTTPHeaderField: "Idempotency-Key") == nil,
                "GET MUST NOT carry Idempotency-Key — Phase 2 NET-04 contract (interceptor injects only on POST/PUT)")
    }

    // MARK: - Test 4: every LoadAction's POST carries the header

    @Test("All 6 LoadAction path segments carry Idempotency-Key on POST")
    func loadActionPost_allActionPathSegments_carryHeader() async throws {
        let capture = installCapture()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        // Exhaustive sweep — adapted to LoadAction.CaseIterable.allCases. If
        // a future LoadAction case is added that should NOT be a POST, this
        // sweep needs an explicit exclusion. For v1.1, all 6 cases POST.
        for action in LoadAction.allCases {
            let body = action == .tender ? makeTenderBody() : makeAcceptBody()
            _ = try await container.apiClient.request(
                LoadActionEndpoint(loadID: "VL-1004", action: action, body: body)
            )
        }

        // For each path segment, assert the corresponding capture exists +
        // carries a valid UUID. The set of expected segments is the same as
        // LoadAction.pathSegment for all cases.
        let expectedSegments: [String] = LoadAction.allCases.map { $0.pathSegment }
        for segment in expectedSegments {
            let req = capture.all().first { request in
                request.httpMethod == "POST" &&
                request.url?.path == "/loads/VL-1004/\(segment)"
            }
            let unwrapped = try #require(req,
                "POST /loads/VL-1004/\(segment) should have been captured")
            let key = unwrapped.value(forHTTPHeaderField: "Idempotency-Key")
            #expect(key != nil,
                    "Idempotency-Key MUST be present on /loads/VL-1004/\(segment)")
            #expect(UUID(uuidString: key ?? "") != nil,
                    "Idempotency-Key on /loads/VL-1004/\(segment) MUST be UUIDv4 — got \(key ?? "nil")")
        }
    }

    // MARK: - Test 5: tender flow end-to-end carries the header

    @Test("Tender flow with full RequestBody (broker → carrier) propagates Idempotency-Key")
    func loadActionPost_throughTenderSheet_flow_carriesHeader() async throws {
        let capture = installCapture()
        defer { MockURLProtocol.reset() }

        let container = makeMockContainer()
        _ = try await container.apiClient.request(
            LoadActionEndpoint(loadID: "VL-1004", action: .tender, body: makeTenderBody())
        )

        let tenderRequest = capture.all().first { req in
            req.httpMethod == "POST" && req.url?.path == "/loads/VL-1004/tender"
        }
        let req = try #require(tenderRequest, "tender POST should have been captured")
        let key = req.value(forHTTPHeaderField: "Idempotency-Key")
        #expect(key != nil, "Idempotency-Key MUST propagate through the tender flow")
        #expect(UUID(uuidString: key ?? "") != nil,
                "Idempotency-Key on the tender flow MUST be UUIDv4")
        // Defensive: tender's full RequestBody should encode through to a
        // non-empty httpBody on the wire (proves the chain didn't strip the
        // body via the interceptor). The URLSession ephemeral path moves
        // httpBody → httpBodyStream so we read either.
        #expect(req.httpBody != nil || req.httpBodyStream != nil,
                "tender RequestBody MUST have encoded to non-nil httpBody or httpBodyStream")
    }
}
