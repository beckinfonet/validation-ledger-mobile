// validationLedgerTests/Networking/MockURLProtocolTests.swift
import Testing
import Foundation
@testable import validationLedger

@Suite("MockURLProtocol — scaffolding (Phase 1)")
struct MockURLProtocolTests {
    @Test("MockURLProtocol class exists and can be registered")
    func canRegister() {
        URLProtocol.registerClass(MockURLProtocol.self)
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }

    @Test("GET /ping fixture returns 200 + {\"ok\":true}")
    func pingFixture() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let url = URL(string: "https://mock.local/ping")!
        let (data, response) = try await session.data(from: url)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("\"ok\""))
    }
}
