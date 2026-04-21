// validationLedger/Core/Networking/NetworkClient.swift
// Phase 1 ships the protocol + a trivial URLSession-backed impl configured
// with MockURLProtocol. Real M1 endpoint typing is Phase 2 (NET-01..NET-05).

import Foundation

public enum NetworkConfig: Sendable {
    case mock
    case live(baseURL: URL)
}

public protocol NetworkClient: AnyObject, Sendable {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse)
    func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionNetworkClient: NetworkClient, @unchecked Sendable {
    private let session: URLSession
    private let config: NetworkConfig

    init(config: NetworkConfig, session: URLSession) {
        self.config = config
        self.session = session
    }

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(from: url)
        return (data, response as! HTTPURLResponse)
    }

    func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        return (data, response as! HTTPURLResponse)
    }
}
