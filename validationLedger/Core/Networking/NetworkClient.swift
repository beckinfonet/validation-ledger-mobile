// validationLedger/Core/Networking/NetworkClient.swift
// Phase 1 shipped the protocol + URLSession-backed impl configured with MockURLProtocol.
// Phase 2 Plan 01: replaces Phase 1 CR-01 force-casts with guard-cast throws.
// Phase 2 Plan 02: APIClient (typed facade) composes this protocol.

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
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unexpectedResponseType(response)
        }
        return (data, http)
    }

    func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unexpectedResponseType(response)
        }
        return (data, http)
    }
}
