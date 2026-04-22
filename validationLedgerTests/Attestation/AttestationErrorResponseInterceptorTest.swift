// validationLedgerTests/Attestation/AttestationErrorResponseInterceptorTest.swift
// Phase 4 Plan 05 Task 4 — D-04 end-to-end interceptor chain.
//
// STATUS: Re-enabled in Wave 4 by Plan 07 Task 3 (this commit). Exercises
// AttestationErrorResponseInterceptor against a FakeAttestationService spy +
// scripted SendSpy. Covers the 3 canonical D-04 trigger codes
// (attestationInvalid / nonceExpired / keyCompromised) plus 2 negative paths
// (unrelated error code, non-attestation path).
//
// Behavior contract (D-04):
//   Path filter: only /device/register + /device/heartbeat — all other paths
//   pass the response through unmodified.
//   Status filter: only 4xx.
//   Body filter: JSON body MUST have error_code ∈ {attestationInvalid,
//     nonceExpired, keyCompromised}.
//   On trigger: calls attestationService.clearPersistedKeyId() +
//     attestationService.generateKeyIfNeeded(), then re-sends the request.
//   Retry budget: retry-once per top-level request. A second consecutive
//     attestation-error response surfaces to the caller.
//
// Threat coverage: T-APP-ATTEST-06 (backend-driven re-attest chain) and
// T-APP-ATTEST-15 (retry-once, no recursion — the SendSpy script demonstrates
// that the interceptor never calls `send` a third time).

import Testing
import Foundation
@testable import validationLedger

@Suite("D-04 — AttestationErrorResponseInterceptor chain")
struct AttestationErrorResponseInterceptorTest {

    /// Helper that builds a scripted `send` closure returning the supplied
    /// responses in order. Captures invocation count for assertions.
    private actor SendSpy {
        private(set) var invocations = 0
        let responses: [(Data, HTTPURLResponse)]

        init(_ responses: [(Data, HTTPURLResponse)]) {
            self.responses = responses
        }

        func next() -> (Data, HTTPURLResponse) {
            defer { invocations += 1 }
            let idx = min(invocations, responses.count - 1)
            return responses[idx]
        }

        func invocationCount() -> Int { invocations }
    }

    private func makeResponse(url: String, statusCode: Int, body: String) -> (Data, HTTPURLResponse) {
        let u = URL(string: url)!
        let r = HTTPURLResponse(url: u, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), r)
    }

    /// Builds the scripted `send` closure the interceptor will invoke. The
    /// closure delegates to `spy.next()` so invocation count is observable.
    private func makeSend(_ spy: SendSpy) -> @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) {
        return { _ in
            await spy.next()
        }
    }

    private func makeRequest(path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://mock.local\(path)")!)
    }

    // TEST 1: 4xx attestationInvalid on /device/register → D-04 chain fires.
    @Test("4xx attestationInvalid on /device/register → clearPersistedKeyId + generateKeyIfNeeded + retry-once")
    func interceptorRetriesOnAttestationInvalid() async throws {
        let fake = FakeAttestationService()
        let spy = SendSpy([
            makeResponse(url: "https://mock.local/device/register", statusCode: 400,
                         body: #"{"error_code":"attestationInvalid"}"#),
            makeResponse(url: "https://mock.local/device/register", statusCode: 200,
                         body: #"{"device_id":"dev-1","registered_at":"2026-04-22T00:00:00Z","trust_tier":"hardwareAttested"}"#)
        ])
        let interceptor = AttestationErrorResponseInterceptor(attestationService: fake)

        let (_, response) = try await interceptor.intercept(
            send: makeSend(spy),
            request: makeRequest(path: "/device/register")
        )

        #expect(fake.clearPersistedKeyIdCallCount == 1)
        #expect(fake.generateKeyIfNeededCallCount == 1)
        #expect(await spy.invocationCount() == 2)
        #expect(response.statusCode == 200)
    }

    // TEST 2: 4xx nonceExpired on /device/heartbeat → D-04 chain fires.
    @Test("4xx nonceExpired on /device/heartbeat → same chain")
    func interceptorRetriesOnNonceExpired() async throws {
        let fake = FakeAttestationService()
        let spy = SendSpy([
            makeResponse(url: "https://mock.local/device/heartbeat", statusCode: 400,
                         body: #"{"error_code":"nonceExpired"}"#),
            makeResponse(url: "https://mock.local/device/heartbeat", statusCode: 200,
                         body: #"{"heartbeat_accepted_at":"2026-04-22T00:00:00Z","trust_tier":"hardwareAttested"}"#)
        ])
        let interceptor = AttestationErrorResponseInterceptor(attestationService: fake)

        let (_, response) = try await interceptor.intercept(
            send: makeSend(spy),
            request: makeRequest(path: "/device/heartbeat")
        )

        #expect(fake.clearPersistedKeyIdCallCount == 1)
        #expect(fake.generateKeyIfNeededCallCount == 1)
        #expect(await spy.invocationCount() == 2)
        #expect(response.statusCode == 200)
    }

    // TEST 3: 4xx keyCompromised on /device/register → D-04 chain fires.
    @Test("4xx keyCompromised → same chain")
    func interceptorRetriesOnKeyCompromised() async throws {
        let fake = FakeAttestationService()
        let spy = SendSpy([
            makeResponse(url: "https://mock.local/device/register", statusCode: 403,
                         body: #"{"error_code":"keyCompromised"}"#),
            makeResponse(url: "https://mock.local/device/register", statusCode: 200,
                         body: #"{"device_id":"dev-2","registered_at":"2026-04-22T00:00:00Z","trust_tier":"hardwareAttested"}"#)
        ])
        let interceptor = AttestationErrorResponseInterceptor(attestationService: fake)

        let (_, response) = try await interceptor.intercept(
            send: makeSend(spy),
            request: makeRequest(path: "/device/register")
        )

        #expect(fake.clearPersistedKeyIdCallCount == 1)
        #expect(fake.generateKeyIfNeededCallCount == 1)
        #expect(await spy.invocationCount() == 2)
        #expect(response.statusCode == 200)
    }

    // TEST 4: unrelated error code → no chain fire, no retry.
    @Test("4xx/5xx unrelated error code → chain does NOT fire; no retry")
    func interceptorIgnoresUnrelatedErrors() async throws {
        let fake = FakeAttestationService()
        let spy = SendSpy([
            makeResponse(url: "https://mock.local/device/register", statusCode: 500,
                         body: #"{"error_code":"internalServerError"}"#)
        ])
        let interceptor = AttestationErrorResponseInterceptor(attestationService: fake)

        let (_, response) = try await interceptor.intercept(
            send: makeSend(spy),
            request: makeRequest(path: "/device/register")
        )

        #expect(fake.clearPersistedKeyIdCallCount == 0)
        #expect(fake.generateKeyIfNeededCallCount == 0)
        #expect(await spy.invocationCount() == 1)
        #expect(response.statusCode == 500)
    }

    // TEST 5: non-attestation path → no chain fire even with canonical code.
    @Test("4xx attestationInvalid on NON-attestation path (/auth/otp/verify) → no interference")
    func interceptorIgnoresNonAttestationPaths() async throws {
        let fake = FakeAttestationService()
        let spy = SendSpy([
            makeResponse(url: "https://mock.local/auth/otp/verify", statusCode: 400,
                         body: #"{"error_code":"attestationInvalid"}"#)
        ])
        let interceptor = AttestationErrorResponseInterceptor(attestationService: fake)

        let (_, response) = try await interceptor.intercept(
            send: makeSend(spy),
            request: makeRequest(path: "/auth/otp/verify")
        )

        #expect(fake.clearPersistedKeyIdCallCount == 0)
        #expect(fake.generateKeyIfNeededCallCount == 0)
        #expect(await spy.invocationCount() == 1)
        #expect(response.statusCode == 400)
    }
}
