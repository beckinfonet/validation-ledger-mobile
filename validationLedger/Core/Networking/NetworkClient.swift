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
    /// Send an arbitrary URLRequest (preserving ALL headers set by RequestInterceptors).
    /// Declared in the protocol so concrete types can provide an override that dynamic-dispatches
    /// through the existential (`any NetworkClient`). A default implementation lives in APIClient.swift
    /// for back-compat, but URLSessionNetworkClient MUST override to call `session.data(for: request)`
    /// directly — otherwise interceptor-injected headers (Idempotency-Key) are dropped when the
    /// default routes through `post(_:body:)`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
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

    /// Override the default `NetworkClient.send(_:)` to preserve the full URLRequest —
    /// including headers injected by RequestInterceptors (Idempotency-Key, Content-Type).
    /// The default extension routes through get/post which rebuild URLRequest from scratch
    /// and drop all headers; that is safe in isolation but breaks NET-04 header propagation
    /// once the interceptor chain is wired (Plan 02-07 integration bug — caught by
    /// AppContainerNetworkConfigTests.idempotencyInterceptorWired).
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unexpectedResponseType(response)
        }
        return (data, http)
    }
}
