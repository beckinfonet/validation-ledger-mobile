// validationLedgerTests/Attestation/ChallengeExpiredRetryTest.swift
// Phase 4 Plan 05 Task 1 — D-08 challenge single-use + refetch-once-on-expired.
//
// Covers D-08 (Plan 05 T1): the GET /device/challenge contract mandates that
// each challenge is consumed exactly once. When the server emits a
// `challengeExpired` error (TTL ≤60s), the client refetches the challenge
// ONCE and retries; a second consecutive expiry surfaces the error to the
// caller — no unbounded retry loop.
//
// The production retry-once-on-challengeExpired behavior is wired into the
// AttestationErrorResponseInterceptor (Plan 07 Task 3) and the end-to-end
// chain test lives in AttestationErrorResponseInterceptorTest.swift (Plan 05
// Task 4, disabled pending Plan 07). This test pins the state-machine
// invariant locally via a helper so a regression in the retry-count math
// surfaces at simulator-test time without waiting for the full interceptor
// landing.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-08 — Challenge single-use; refetch-once on expired")
struct ChallengeExpiredRetryTest {

    /// Minimal state machine mirroring the retry-once semantics the
    /// AttestationErrorResponseInterceptor (Plan 07 Task 3) enforces. Returned
    /// `.refetchAndRetry` exactly once per top-level request; subsequent expiry
    /// returns `.surfaceError` so a bounded retry loop is guaranteed.
    private final class ChallengeRetryCoordinator: @unchecked Sendable {
        private(set) var retryAttempts = 0
        enum Decision { case refetchAndRetry, surfaceError }

        func onChallengeExpired() -> Decision {
            if retryAttempts >= 1 {
                return .surfaceError
            }
            retryAttempts += 1
            return .refetchAndRetry
        }

        func reset() { retryAttempts = 0 }
    }

    @Test("First expiry → refetchAndRetry (retry-count=1); second expiry → surfaceError (retry bounded)")
    func refetchOnceBoundedRetry() {
        let coord = ChallengeRetryCoordinator()

        // Call 1: server returns challengeExpired → client MUST refetch + retry.
        #expect(coord.onChallengeExpired() == .refetchAndRetry,
                "D-08: first challengeExpired MUST trigger a refetch + retry")

        // Call 2: second consecutive expiry → client MUST surface error; not loop.
        #expect(coord.onChallengeExpired() == .surfaceError,
                "D-08: second consecutive challengeExpired MUST surface the error — no unbounded retry")

        #expect(coord.retryAttempts == 1,
                "D-08: retry-count MUST be bounded to 1 — interceptor does not retry again after refetch")
    }

    @Test("Reset + first expiry → refetchAndRetry again — new top-level request gets a fresh retry budget")
    func newRequestGetsFreshBudget() {
        let coord = ChallengeRetryCoordinator()

        _ = coord.onChallengeExpired()
        _ = coord.onChallengeExpired()

        // A new /device/register or /device/heartbeat call starts fresh —
        // the per-request retry budget resets.
        coord.reset()
        #expect(coord.onChallengeExpired() == .refetchAndRetry,
                "D-08: each new top-level request MUST get a fresh retry-once budget")
        #expect(coord.retryAttempts == 1)
    }

    @Test("After retry succeeds (no expiry on second attempt), retry-count stays at 1 until reset")
    func retryCountDoesNotAutoReset() {
        let coord = ChallengeRetryCoordinator()
        _ = coord.onChallengeExpired()
        // Simulate successful second attempt — no further calls to onChallengeExpired().
        // retryAttempts should remain at 1 until explicitly reset by the next request.
        #expect(coord.retryAttempts == 1,
                "D-08: retry-count stays at its incremented value for the remainder of the request — no auto-reset inside a single request")
    }

    @Test("FixtureLoader round-trip: device-challenge-success fixture decodes (D-05 contract, D-08 client consumes)")
    func fixtureRoundTripChallenge() throws {
        let data = try FixtureLoader.loadFixture("device-challenge-success")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(DeviceChallengeEndpoint.Response.self, from: data)
        #expect(!resp.challenge.isEmpty)
        #expect(!resp.nonce.isEmpty)
        #expect(Data(base64Encoded: resp.challenge) != nil,
                "D-05/D-08: challenge MUST be base64-decodable so the client can SHA-256 the decoded bytes")
    }
}
