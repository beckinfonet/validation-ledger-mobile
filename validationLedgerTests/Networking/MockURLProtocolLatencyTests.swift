// validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift
// Phase 7 Plan 04 — verifies LOAD-01 SC #4 (latency) on the additive
// MockURLProtocol.registerFixtureWithLatency capability.
//
// .serialized is mandatory: tests mutate MockURLProtocol's global
// _handlers array (registerFixtureWithLatency routes through the
// existing register(_:) API).
//
// Tolerances: simulator scheduling adds noise. The lower-bound assertions
// (elapsed >= latency) are the load-bearing checks; the upper bounds are
// padded (50ms / 150ms) to absorb timer jitter without flaking.

import Testing
import Foundation
@testable import validationLedger

@Suite("MockURLProtocol latency injection (LOAD-01 SC #4)", .serialized)
struct MockURLProtocolLatencyTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("registerFixtureWithLatency delivers the response after at least the specified delay")
    func deliversAfterSpecifiedDelay() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let latency: TimeInterval = 0.2
        let body = Data(#"{"ok":true}"#.utf8)
        // DeviceChallengeEndpoint is the simplest existing APIEndpoint conformer; the type
        // parameter is for documentation/binding only — match is by path + method.
        MockURLProtocol.registerFixtureWithLatency(
            for: DeviceChallengeEndpoint.self,
            path: "/test/latency",
            method: .get,
            statusCode: 200,
            body: body,
            latency: latency
        )

        let url = URL(string: "https://mock.local/test/latency")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let start = Date()
        let (_, response) = try await makeSession().data(for: req)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= latency, "elapsed \(elapsed)s should be >= \(latency)s")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("registerFixtureWithLatency: zero latency behaves like the standard registerFixture (no measurable delay)")
    func zeroLatencyHasNoMeasurableDelay() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let body = Data(#"{"ok":true}"#.utf8)
        MockURLProtocol.registerFixtureWithLatency(
            for: DeviceChallengeEndpoint.self,
            path: "/test/instant",
            method: .get,
            statusCode: 200,
            body: body,
            latency: 0.0
        )

        let url = URL(string: "https://mock.local/test/instant")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        let start = Date()
        let (_, response) = try await makeSession().data(for: req)
        let elapsed = Date().timeIntervalSince(start)

        // Bound padded to 50ms to absorb scheduler jitter on the simulator.
        #expect(elapsed < 0.05, "elapsed \(elapsed)s should be < 50ms when latency=0")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test("Multiple latency-injected fixtures on different paths each apply their own latency")
    func perPathLatencyIsolation() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let bodyFast = Data(#"{"speed":"fast"}"#.utf8)
        let bodySlow = Data(#"{"speed":"slow"}"#.utf8)
        MockURLProtocol.registerFixtureWithLatency(
            for: DeviceChallengeEndpoint.self,
            path: "/test/fast",
            method: .get,
            statusCode: 200,
            body: bodyFast,
            latency: 0.05
        )
        MockURLProtocol.registerFixtureWithLatency(
            for: DeviceChallengeEndpoint.self,
            path: "/test/slow",
            method: .get,
            statusCode: 200,
            body: bodySlow,
            latency: 0.3
        )

        let session = makeSession()

        // Fast path
        var reqFast = URLRequest(url: URL(string: "https://mock.local/test/fast")!)
        reqFast.httpMethod = "GET"
        let startFast = Date()
        let (dataFast, _) = try await session.data(for: reqFast)
        let elapsedFast = Date().timeIntervalSince(startFast)

        // Slow path
        var reqSlow = URLRequest(url: URL(string: "https://mock.local/test/slow")!)
        reqSlow.httpMethod = "GET"
        let startSlow = Date()
        let (dataSlow, _) = try await session.data(for: reqSlow)
        let elapsedSlow = Date().timeIntervalSince(startSlow)

        // Upper bound on fast is padded to 150ms (= 50ms latency + 100ms jitter); the lower
        // bound on slow (>= 0.3) is the load-bearing assertion that per-handler latency
        // isolates — the slow path does NOT pick up the fast path's 50ms latency or vice versa.
        #expect(elapsedFast < 0.15, "fast path elapsed \(elapsedFast)s should be < 150ms")
        #expect(elapsedSlow >= 0.3, "slow path elapsed \(elapsedSlow)s should be >= 300ms")
        #expect(dataFast == bodyFast)
        #expect(dataSlow == bodySlow)
    }
}
