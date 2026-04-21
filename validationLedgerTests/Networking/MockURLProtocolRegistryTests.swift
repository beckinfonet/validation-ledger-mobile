// validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift
// WR-01 validation suite: the NSLock-guarded registry must survive parallel test execution
// under @Suite(.serialized) + MockURLProtocol.reset() at every test entry.
//
// Scope: exercises only MockURLProtocol.register / reset / startLoading / 404-fallback.
// Does NOT depend on APIEndpoint, APIClient, or any Phase 2 Wave 1+ symbol.

import Testing
import Foundation
@testable import validationLedger

@Suite("MockURLProtocol — fixture registry + lock safety (WR-01)", .serialized)
struct MockURLProtocolRegistryTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("reset empties all registered handlers")
    func resetEmpties() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.register { _ in
            let url = URL(string: "https://mock.local/x")!
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        MockURLProtocol.reset()

        // After reset, any request should 404 (no handlers match).
        let session = makeSession()
        let (_, response) = try await session.data(from: URL(string: "https://mock.local/x")!)
        guard let http = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse"); return
        }
        #expect(http.statusCode == 404)
    }

    @Test("register + request returns the fixture response")
    func registerReturnsFixture() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let payload = Data(#"{"hello":"world"}"#.utf8)
        MockURLProtocol.register { request in
            guard request.url?.path == "/hello" else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, payload)
        }

        let session = makeSession()
        let (data, response) = try await session.data(from: URL(string: "https://mock.local/hello")!)
        guard let http = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse"); return
        }
        #expect(http.statusCode == 200)
        #expect(data == payload)
    }

    @Test("first-match-wins when multiple handlers match overlapping paths")
    func firstMatchWins() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // Handler A registered FIRST — should win for /shared.
        MockURLProtocol.register { request in
            guard request.url?.path == "/shared" else { return nil }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("A".utf8))
        }
        // Handler B registered SECOND — also matches /shared, but A wins per first-match-wins.
        MockURLProtocol.register { request in
            guard request.url?.path == "/shared" else { return nil }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("B".utf8))
        }

        let session = makeSession()
        let (data, _) = try await session.data(from: URL(string: "https://mock.local/shared")!)
        #expect(data == Data("A".utf8))
    }

    @Test("unmatched URL returns 404 fallback")
    func unmatchedReturns404() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.register { request in
            guard request.url?.path == "/only-this" else { return nil }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let session = makeSession()
        let (_, response) = try await session.data(from: URL(string: "https://mock.local/nope")!)
        guard let http = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse"); return
        }
        #expect(http.statusCode == 404)
    }

    @Test("consecutive register/reset cycles leave no residual state")
    func cycleHygiene() async throws {
        for iteration in 1...5 {
            MockURLProtocol.reset()
            MockURLProtocol.register { request in
                guard request.url?.path == "/iter" else { return nil }
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("iter-\(iteration)".utf8))
            }
            let session = makeSession()
            let (data, _) = try await session.data(from: URL(string: "https://mock.local/iter")!)
            #expect(data == Data("iter-\(iteration)".utf8))
        }
        MockURLProtocol.reset()
    }
}
