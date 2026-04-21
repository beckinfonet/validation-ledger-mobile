// validationLedgerTests/Networking/IdempotencyInterceptorTests.swift
// NET-04 validation — 5 @Test methods covering IdempotencyInterceptor's behavior.
// No MockURLProtocol mutation here — these tests exercise the interceptor directly.

import Testing
import Foundation
@testable import validationLedger

@Suite("IdempotencyInterceptor — header injection (NET-04)")
struct IdempotencyInterceptorTests {

    private static let url = URL(string: "https://mock.local/test")!

    /// Build a URLRequest with the given method and optional pre-existing Idempotency-Key.
    private func makeRequest(method: String, existingKey: String? = nil) -> URLRequest {
        var req = URLRequest(url: Self.url)
        req.httpMethod = method
        if let existingKey {
            req.setValue(existingKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return req
    }

    /// Validate UUID format using Foundation's UUID initializer — returns nil on invalid.
    private func isValidUUID(_ s: String) -> Bool {
        UUID(uuidString: s) != nil
    }

    @Test("POST request gets a fresh Idempotency-Key header in UUID format")
    func injectsOnPOST() async throws {
        let interceptor = IdempotencyInterceptor()
        let intercepted = try await interceptor.intercept(makeRequest(method: "POST"))
        let key = intercepted.value(forHTTPHeaderField: "Idempotency-Key")
        #expect(key != nil)
        #expect(isValidUUID(key ?? ""))
    }

    @Test("PUT request gets a fresh Idempotency-Key header")
    func injectsOnPUT() async throws {
        let interceptor = IdempotencyInterceptor()
        let intercepted = try await interceptor.intercept(makeRequest(method: "PUT"))
        let key = intercepted.value(forHTTPHeaderField: "Idempotency-Key")
        #expect(key != nil)
        #expect(isValidUUID(key ?? ""))
    }

    @Test("GET request is NOT mutated — no Idempotency-Key header injected")
    func doesNotInjectOnGET() async throws {
        let interceptor = IdempotencyInterceptor()
        let intercepted = try await interceptor.intercept(makeRequest(method: "GET"))
        #expect(intercepted.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test("DELETE request is NOT mutated — Phase 2 scope = POST + PUT only per NET-04")
    func doesNotInjectOnDELETE() async throws {
        let interceptor = IdempotencyInterceptor()
        let intercepted = try await interceptor.intercept(makeRequest(method: "DELETE"))
        #expect(intercepted.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test("POST with caller-supplied Idempotency-Key preserves the original (Phase 5 replay path)")
    func doesNotOverwriteExisting() async throws {
        let interceptor = IdempotencyInterceptor()
        let callerKey = "caller-supplied-replay-key-phase-5"
        let intercepted = try await interceptor.intercept(
            makeRequest(method: "POST", existingKey: callerKey)
        )
        #expect(intercepted.value(forHTTPHeaderField: "Idempotency-Key") == callerKey)
    }
}
