// validationLedger/Core/Networking/APIClient.swift
// Typed facade over NetworkClient. Composes:
//   1. buildRequest(endpoint:) — endpoint path + baseURL → URLRequest, encode body if present
//   2. requestInterceptors in order — header injection (Idempotency-Key in Plan 04)
//   3. responseInterceptors wrapping the send call — retry (Plan 04)
//   4. decode(Data, HTTPURLResponse) → E.Response — wrap DecodingError as NetworkError.decodingFailed
//
// APIClient throws EXCLUSIVELY NetworkError cases; never DecodingError, EncodingError, or URLError
// raw. Callers (Phase 3 AuthRepository, Phase 5 KYCUploader) build UX against NetworkError.
//
// Initializer-DI per ARCH-04 — no singletons, no .shared. AppContainer (Plan 07) constructs.

import Foundation

public final class APIClient: Sendable {
    private let baseURL: URL
    private let networkClient: any NetworkClient
    private let requestInterceptors: [any RequestInterceptor]
    private let responseInterceptors: [any ResponseInterceptor]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        networkClient: any NetworkClient,
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = [],
        encoder: JSONEncoder = APIClient.defaultEncoder(),
        decoder: JSONDecoder = APIClient.defaultDecoder()
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.encoder = encoder
        self.decoder = decoder
    }

    public func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        var req = try buildRequest(endpoint)
        for interceptor in requestInterceptors {
            req = try await interceptor.intercept(req)
        }

        // Compose response interceptors around the send call (innermost = last in array).
        let base: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { [networkClient] request in
            try await networkClient.send(request)
        }
        let wrapped = responseInterceptors.reversed().reduce(base) { next, interceptor in
            { request in try await interceptor.intercept(send: next, request: request) }
        }

        let (data, response) = try await wrapped(req)
        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.httpError(statusCode: response.statusCode, data: data)
        }
        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    // MARK: - Private

    private func buildRequest<E: APIEndpoint>(_ endpoint: E) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            do {
                req.httpBody = try encoder.encode(body)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw NetworkError.encodingFailed(error)
            }
        }
        return req
    }

    // MARK: - Default encoders

    public static func defaultEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func defaultDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - NetworkClient.send default implementation

/// Generic send(_:) for NetworkClient — routes URLRequest through Phase 1's get/post primitives.
/// This preserves NetworkClient's Phase 1 API (get, post) while letting APIClient use a single
/// URLRequest-based call. URLSessionNetworkClient could override this for a direct
/// `session.data(for: request)` call, but the default works for Plan 02+.
public extension NetworkClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw NetworkError.baseURLMissing
        }
        switch request.httpMethod {
        case "GET", nil:
            return try await get(url)
        case "POST", "PUT", "DELETE":
            return try await post(url, body: request.httpBody ?? Data())
        default:
            throw NetworkError.unexpectedResponseType(
                HTTPURLResponse(url: url, statusCode: 0, httpVersion: nil, headerFields: nil)!
            )
        }
    }
}
