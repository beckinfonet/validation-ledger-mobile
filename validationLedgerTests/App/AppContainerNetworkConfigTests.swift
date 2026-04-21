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
