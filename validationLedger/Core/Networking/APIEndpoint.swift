// validationLedger/Core/Networking/APIEndpoint.swift
// Typed-endpoint protocol for every M1 backend call (NET-01).
// Conforming structs carry:
//   - path: String — server-relative URL path (no scheme/host; APIClient prepends baseURL)
//   - method: HTTPMethod
//   - body: RequestBody? — nil for GET (uses public EmptyBody sentinel)
//   - RequestBody: the Encodable body type (public struct EmptyBody for GETs)
//   - Response: the Decodable response type
//
// APIClient.request<E: APIEndpoint>(_ endpoint: E) is the one call site that ties them together.
// Mock fixtures in Plan 03 key off path + method — the endpoint struct IS the contract.

import Foundation

public protocol APIEndpoint<Response>: Sendable {
    associatedtype RequestBody: Encodable & Sendable
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: RequestBody? { get }

    /// Per-request header seam (Phase 5 / RESEARCH Open Question 2).
    /// APIClient.buildRequest applies each entry via `setValue(_, forHTTPHeaderField:)`
    /// AFTER the Accept/Content-Type defaults but BEFORE the requestInterceptors loop —
    /// so a caller-supplied header (e.g. an explicit-replay `Idempotency-Key` set by
    /// KYCUploader) reaches IdempotencyInterceptor, which already skips a present key.
    /// The default extension below returns `[:]` so every existing endpoint compiles unchanged.
    var headers: [String: String] { get }
}

public extension APIEndpoint {
    /// Default: no per-request headers. Endpoints opt in by overriding `headers`.
    var headers: [String: String] { [:] }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Sentinel body type for GET endpoints (which have no body). Public (not internal) because
/// `KYCStatusEndpoint` declares a public `typealias RequestBody = EmptyBody`, and Swift rejects
/// a public type alias whose underlying type is internal.
/// `nonisolated` is required under the project's SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor setting
/// so the Encodable conformance is not main-actor-isolated — APIEndpoint's `RequestBody: Sendable`
/// constraint rejects main-actor-isolated conformances.
/// Declared at file scope so multiple GET endpoints can share it without each declaring its own.
nonisolated public struct EmptyBody: Encodable, Sendable {
    public init() {}
}
