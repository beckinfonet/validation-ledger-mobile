// validationLedgerTests/Networking/MockURLProtocolTests.swift
// Phase 2 Plan 01 update: the Phase 1 defaultPingHandler was removed from MockURLProtocol
// (WR-01 fix). This test now registers its own /ping fixture via the new register(_:) API.
// @Suite(.serialized) is mandatory for any suite that mutates MockURLProtocol handlers.

import Testing
import Foundation
@testable import validationLedger

@Suite("MockURLProtocol — scaffolding (Phase 1 test retained, WR-01-updated)", .serialized)
struct MockURLProtocolTests {
    @Test("MockURLProtocol class exists and can be registered")
    func canRegister() {
        URLProtocol.registerClass(MockURLProtocol.self)
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }

    @Test("GET /ping with explicit handler returns 200 + {\"ok\":true}")
    func pingFixture() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.register { request in
            guard let url = request.url, url.path.hasSuffix("/ping") else { return nil }
            let resp = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data(#"{"ok":true}"#.utf8))
        }
        defer { MockURLProtocol.reset() }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let url = URL(string: "https://mock.local/ping")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse, got \(type(of: response))")
            return
        }
        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("\"ok\""))
    }
}
