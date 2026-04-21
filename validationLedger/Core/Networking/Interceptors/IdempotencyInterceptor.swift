// validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift
// NET-04: Inject Idempotency-Key header (UUID().uuidString) on every POST and PUT mutation.
// Skip GET/DELETE — GET is idempotent by HTTP spec, DELETE is out of Phase 2 scope (Research §Pattern 5).
// Do NOT overwrite an existing Idempotency-Key — callers may supply one for Phase 5's
// explicit-replay path (same key across retries so the backend dedupes).
//
// Per-request UUID generation: no persistent state in Phase 2 (upload-chunk idempotency state
// is Phase 5 UPL-02). Stripe's recommendation: UUIDv4 with 128 bits entropy — Foundation's
// UUID() is UUIDv4 by default on Darwin.

import Foundation

public struct IdempotencyInterceptor: RequestInterceptor {
    public init() {}

    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        guard let method = request.httpMethod,
              method == "POST" || method == "PUT" else {
            return request
        }
        // Don't overwrite a caller-supplied key (Phase 5 explicit-replay path).
        guard request.value(forHTTPHeaderField: "Idempotency-Key") == nil else {
            return request
        }
        var mutable = request
        mutable.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        return mutable
    }
}
