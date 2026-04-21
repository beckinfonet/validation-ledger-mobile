// validationLedger/Core/Networking/APIEndpoint.swift
// Typed-endpoint protocol for every M1 backend call (NET-01).
// Conforming structs carry:
//   - path: String — server-relative URL path (no scheme/host; APIClient prepends baseURL)
//   - method: HTTPMethod
//   - body: RequestBody? — nil for GET (uses internal EmptyBody sentinel)
//   - RequestBody: the Encodable body type (internal struct EmptyBody for GETs)
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
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Sentinel body type for GET endpoints (which have no body). Internal — consumed by KYCStatusEndpoint.
/// Declared at file scope so multiple GET endpoints can share it without each declaring its own.
struct EmptyBody: Encodable, Sendable {}
