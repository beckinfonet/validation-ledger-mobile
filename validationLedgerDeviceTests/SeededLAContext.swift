// validationLedgerDeviceTests/SeededLAContext.swift
// D-14: seeded biometric service for unattended CI (Plan 02 Wave 0).
// Returns .success synchronously without touching real LAContext — no Face ID prompt.
// Production code path (Plan 03+) uses DefaultBiometricService; tests inject this via the
// AppContainer test seam landed in Plan 06.
//
// HONEST-NAMING rule (RESEARCH Pitfall 5, lines 625-629): any test using this seeded
// service MUST name the test after the Keychain side-effect (e.g.,
// `testKeychainACLCreatedWhenBiometricSucceeds`), NEVER after the OS biometric prompt
// (`testBiometricAuthFlow` is a PROHIBITED test name pattern). Real Face ID hardware
// verification lives in HUMAN-UAT (04-VALIDATION.md Manual-Only Verifications).
//
// Protocol surface mirrored from validationLedger/Core/Auth/BiometricService.swift:
//   - func evaluate(reason: String, fallback: BiometricFallback) async throws
//   - func currentDomainState() -> Data?
// Deliberately does NOT instantiate a real LAContext in any method path so unattended CI
// cannot accidentally trigger a real biometric prompt (T-APP-ATTEST-05 compensating control).

import Foundation
@testable import validationLedger

final class SeededBiometricService: BiometricService, @unchecked Sendable {

    /// Scriptable failure injection — default nil means evaluate() succeeds as a no-op.
    /// Tests that need to model a biometric-failure path set this to a concrete Error
    /// (typically an NSError in LAErrorDomain) before invoking evaluate().
    var shouldThrowOnEvaluate: Error?

    /// Call counters — let tests assert side-effect wiring (D-01-style contract pins).
    private(set) var evaluateCallCount = 0
    private(set) var currentDomainStateCallCount = 0

    /// Last-args capture for the Keychain-side-effect assertions the plan's HONEST-NAMING
    /// rule requires tests to use (e.g., "did evaluate run with the expected reason?").
    private(set) var lastEvaluateReason: String?
    private(set) var lastEvaluateFallback: BiometricFallback?

    /// Fixed seeded domain state per RESEARCH line 716 — deterministic for test assertions.
    /// Tests that need to model "no enrolled biometric" can subclass or swap to a different
    /// test double; this baseline returns a stable non-nil value.
    private let seededDomainStatePayload = Data("seeded-domain-state".utf8)

    func evaluate(reason: String, fallback: BiometricFallback) async throws {
        evaluateCallCount += 1
        lastEvaluateReason = reason
        lastEvaluateFallback = fallback
        if let err = shouldThrowOnEvaluate {
            throw err
        }
        // Seeded success — no LAContext, no hardware interaction.
    }

    func currentDomainState() -> Data? {
        currentDomainStateCallCount += 1
        return seededDomainStatePayload
    }
}
