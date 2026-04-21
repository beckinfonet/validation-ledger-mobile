// validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift
// Interceptor protocol surface consumed by APIClient (Plan 02) and implemented by
// IdempotencyInterceptor + RetryInterceptor (Plan 04).
//
// Two protocols kept in one file because they form a conceptual pair:
//  - RequestInterceptor mutates the URLRequest before send (header injection, auth token, idempotency key).
//  - ResponseInterceptor wraps the entire send call (retry, circuit breaker, timing).
// Separating them keeps IdempotencyInterceptor (header-only) from needing the more complex ResponseInterceptor signature.

import Foundation

public protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

public protocol ResponseInterceptor: Sendable {
    func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}
