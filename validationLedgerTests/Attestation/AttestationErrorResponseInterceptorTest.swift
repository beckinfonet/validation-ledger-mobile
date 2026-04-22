// validationLedgerTests/Attestation/AttestationErrorResponseInterceptorTest.swift
// Phase 4 Plan 05 Task 4 — D-04 end-to-end interceptor chain (DISABLED IN WAVE 3).
//
// STATUS: Suite is @Suite(.disabled(...)) pending Plan 07 Task 3 (Wave 4) which
// creates the AttestationErrorResponseInterceptor production type. Plan 07's
// executor is responsible for:
//   1. Landing AttestationErrorResponseInterceptor as a ResponseInterceptor.
//   2. Removing the .disabled condition below.
//   3. Replacing the TODO(04-07) placeholder test bodies with real assertions
//      per the spec table below (against the FakeAttestationService spy).
//
// Cross-wave rationale: the 04-05 plan frontmatter lists this file among its
// files_modified, but the production type it validates ships in 04-07. Per
// STATE.md Wave-3-to-Wave-4 handoff protocol, Plan 05 lands the skeleton +
// intent documentation; Plan 07 fleshes out the assertions when the type
// exists. This avoids stubbing a fake interceptor here that would conflict
// with the real one in Plan 07.
//
// =============================================================================
// INTENT SPEC (flesh out in Plan 07 Task 3):
// =============================================================================
//
// The AttestationErrorResponseInterceptor conforms to ResponseInterceptor:
//
//   public func intercept(
//       send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
//       request: URLRequest
//   ) async throws -> (Data, HTTPURLResponse)
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
// Test spec (5 tests; all drive the fake via FakeAttestationService spy):
//
//   TEST 1: interceptorRetriesOnAttestationInvalid
//     - Given: /device/register, first-response = 400 + {error_code:"attestationInvalid"}
//       + second-response = 200 OK.
//     - When: interceptor.intercept(send: spy, request: register) is called.
//     - Then:
//         fake.clearPersistedKeyIdCallCount == 1
//         fake.generateKeyIfNeededCallCount == 1
//         spy.invocations == 2  (original + retry-once)
//         final response has statusCode == 200
//
//   TEST 2: interceptorRetriesOnNonceExpired
//     - Same as TEST 1 but with /device/heartbeat + "nonceExpired" error_code.
//
//   TEST 3: interceptorRetriesOnKeyCompromised
//     - Same as TEST 1 but with "keyCompromised" error_code.
//
//   TEST 4: interceptorIgnoresUnrelatedErrors
//     - Given: 500 + {error_code:"internalServerError"}
//     - Then:
//         fake.clearPersistedKeyIdCallCount == 0
//         fake.generateKeyIfNeededCallCount == 0
//         spy.invocations == 1  (no retry on non-attestation errors)
//
//   TEST 5: interceptorIgnoresNonAttestationPaths
//     - Given: /auth/otp/verify + 400 + {error_code:"attestationInvalid"}
//     - Then: interceptor MUST NOT act — path filter excludes non-device paths.
//         fake.clearPersistedKeyIdCallCount == 0
//         spy.invocations == 1
//
// =============================================================================

import Testing
import Foundation
@testable import validationLedger

@Suite(
    "D-04 — AttestationErrorResponseInterceptor chain (DISABLED PENDING PLAN 07 TASK 3)",
    .disabled("Awaiting AttestationErrorResponseInterceptor from Plan 07 Task 3 — re-enable + flesh out assertions in Wave 4")
)
struct AttestationErrorResponseInterceptorTest {

    /// Helper that builds a scripted `send` closure returning the supplied
    /// responses in order. Captures invocation count for assertions.
    /// Kept here so Plan 07 Task 3's executor can wire it into the real
    /// interceptor call without re-authoring the scaffolding.
    private actor SendSpy {
        var invocations = 0
        let responses: [(Data, HTTPURLResponse)]

        init(_ responses: [(Data, HTTPURLResponse)]) {
            self.responses = responses
        }

        func next() -> (Data, HTTPURLResponse) {
            defer { invocations += 1 }
            let idx = min(invocations, responses.count - 1)
            return responses[idx]
        }
    }

    private func makeResponse(url: String, statusCode: Int, body: String) -> (Data, HTTPURLResponse) {
        let u = URL(string: url)!
        let r = HTTPURLResponse(url: u, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), r)
    }

    // TODO(04-07): Remove the @Suite(.disabled) condition above AND populate
    // test bodies per the INTENT SPEC header block. The scaffolding (SendSpy +
    // makeResponse + FakeAttestationService) is ready — only the interceptor
    // call + assertions need filling in once the production type exists.

    @Test("TODO(04-07): 4xx attestationInvalid on /device/register → clearPersistedKeyId + generateKeyIfNeeded + retry-once")
    func interceptorRetriesOnAttestationInvalid() async throws {
        // Pending Plan 07 Task 3.
        // Expected assertions per spec (for Plan 07 executor):
        //   fake.clearPersistedKeyIdCallCount == 1
        //   fake.generateKeyIfNeededCallCount == 1
        //   await spy.invocations == 2
        //   finalResponse.statusCode == 200
    }

    @Test("TODO(04-07): 4xx nonceExpired on /device/heartbeat → same chain")
    func interceptorRetriesOnNonceExpired() async throws {
        // Pending Plan 07 Task 3.
        // Expected assertions per spec:
        //   fake.clearPersistedKeyIdCallCount == 1
        //   fake.generateKeyIfNeededCallCount == 1
        //   await spy.invocations == 2
    }

    @Test("TODO(04-07): 4xx keyCompromised → same chain")
    func interceptorRetriesOnKeyCompromised() async throws {
        // Pending Plan 07 Task 3.
        // Expected assertions per spec:
        //   fake.clearPersistedKeyIdCallCount == 1
        //   fake.generateKeyIfNeededCallCount == 1
    }

    @Test("TODO(04-07): 4xx unrelated error code → chain does NOT fire; no retry")
    func interceptorIgnoresUnrelatedErrors() async throws {
        // Pending Plan 07 Task 3.
        // Expected assertions per spec:
        //   fake.clearPersistedKeyIdCallCount == 0
        //   fake.generateKeyIfNeededCallCount == 0
        //   await spy.invocations == 1  (no retry on non-attestation errors)
        //   finalResponse.statusCode == 500
    }

    @Test("TODO(04-07): 4xx attestationInvalid on NON-attestation path (/auth/otp/verify) → no interference")
    func interceptorIgnoresNonAttestationPaths() async throws {
        // Pending Plan 07 Task 3.
        // Expected assertions per spec:
        //   fake.clearPersistedKeyIdCallCount == 0
        //   await spy.invocations == 1  (path filter excludes non-device endpoints)
    }
}
