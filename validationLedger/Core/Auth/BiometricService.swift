// validationLedger/Core/Auth/BiometricService.swift
// Phase 3 Plan 06 (D-09/D-10): LAContext wrapper. Used by:
//   - SessionLockService (currentDomainState read for SESS-03 re-enrollment check)
//   - SensitiveActionService (evaluate(reason:fallback: .none) — strict biometric)
//   - OTPViewModel D-27 step 6 (evaluate(reason: ..., fallback: .none) records initial domainState)
//   - BiometricLockViewController (evaluate(reason: ..., fallback: .devicePasscode) — session unlock)
//
// Anti-pattern guarded against: storing LAContext as a property and reusing it — every
// call constructs a fresh LAContext. WWDC22 streamline-local-auth recommendation.

import Foundation
import LocalAuthentication

public enum BiometricFallback: Sendable {
    case none           // Strict biometric (sensitive actions — D-11)
    case devicePasscode // Biometric with passcode fallback (session unlock — D-15)
}

public protocol BiometricService: AnyObject, Sendable {
    /// Evaluates the requested policy. On success, persists evaluatedPolicyDomainState
    /// to Keychain[.biometricDomainState] (D-09). MUST be called from MainActor.
    func evaluate(reason: String, fallback: BiometricFallback) async throws

    /// Reads the current LAContext.evaluatedPolicyDomainState. Calls
    /// canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error:) FIRST to
    /// populate the property (Pitfall 1: nil otherwise). Returns nil if the device
    /// has no biometric hardware or no enrolled biometric.
    func currentDomainState() -> Data?
}

@MainActor
public final class DefaultBiometricService: BiometricService {
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(keychain: KeychainStore, logger: any Logger) {
        self.keychain = keychain
        self.logger = logger
    }

    public func evaluate(reason: String, fallback: BiometricFallback) async throws {
        let ctx = LAContext()
        let policy: LAPolicy = (fallback == .devicePasscode)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        // canEvaluatePolicy first — surfaces .passcodeNotSet / .biometryNotAvailable
        // before we display the OS prompt; also populates evaluatedPolicyDomainState
        // (Pitfall 1).
        var canError: NSError?
        guard ctx.canEvaluatePolicy(policy, error: &canError) else {
            throw canError ?? NSError(
                domain: LAErrorDomain,
                code: LAError.invalidContext.rawValue
            )
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? NSError(
                        domain: LAErrorDomain,
                        code: LAError.authenticationFailed.rawValue
                    ))
                }
            }
        }

        // After successful evaluate, persist domain state per D-09.
        // Using try? — domain state persistence failure should NOT block the user;
        // worst case is a false biometricReEnrolled on the next lockState check, which
        // the user can resolve by re-binding (acceptable degraded UX).
        if let domainState = ctx.evaluatedPolicyDomainState {
            try? keychain.set(
                domainState,
                for: .biometricDomainState,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
    }

    public func currentDomainState() -> Data? {
        // Fresh LAContext — never reuse (anti-pattern guard).
        let ctx = LAContext()
        var err: NSError?
        // Must call canEvaluatePolicy FIRST per Pitfall 1.
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return ctx.evaluatedPolicyDomainState
    }
}
