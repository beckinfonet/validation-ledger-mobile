// validationLedger/Core/Auth/SensitiveActionService.swift
// Phase 3 D-11 / D-12 (Plan 07 — Blocker 3 fix): AUTH-06 sensitive-action infrastructure.
// M1: ZERO call sites. Constructed in AppContainer (Plan 11); the constructibility
// test (in SensitiveActionServiceTests) is the entire AUTH-06 surface for M1.
// M2+ tender/accept/BOL signing call sites consume this.
//
// === WWDC22 SINGLE-PROMPT DESIGN (D-11 / Blocker 3) ===
//
// The naive 2-step approach (call BiometricService.evaluate, then call
// keyStore.signWithAuthorization) prompts the user TWICE because the SE auth-key
// ACL is `.biometryCurrentSet` — SecKeyCreateSignature triggers its own OS prompt
// independent of any prior LAContext authorization.
//
// The fix (per WWDC22 "Streamline Local Authentication" sample):
//   1. Construct a SINGLE LAContext.
//   2. Call ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)
//      → ONE OS prompt to the user.
//   3. Pass that SAME LAContext to keyStore.signWithAuthorization(payload, context: ctx)
//      → SE-side query injects kSecUseAuthenticationContext: ctx
//      → SecKeyCreateSignature reuses the already-authorized context, NO re-prompt.
//
// Why .deviceOwnerAuthenticationWithBiometrics and NOT .deviceOwnerAuthentication
// (i.e., why we DON'T fall back to passcode here):
//   The SE auth-key ACL is `.biometryCurrentSet`. Even if the LAContext is
//   authorized via passcode, the SE ACL REJECTS passcode unlock — only
//   biometric satisfies the ACL. So passcode fallback would result in
//   "context authorized successfully" + "SE refuses to sign" = bad UX.
//   Strict biometric here is correct.
//
// SessionLockService unlock path (BiometricLockViewController in Plan 10) is
// SEPARATE: it uses BiometricService.evaluate(reason:fallback: .devicePasscode)
// which uses .deviceOwnerAuthentication policy. Passcode fallback IS correct
// for session unlock (no SE key involvement) per D-15.

import Foundation
import LocalAuthentication

public enum SensitiveActionError: Error, Sendable {
    case userCancel
    case biometryLockout
    case biometricReEnrolled
    case signFailed(underlying: Error)
}

public protocol SensitiveActionService: AnyObject, Sendable {
    /// Returns DER X9.62 ECDSA signature on success.
    func authorize(_ payload: Data, reason: String) async throws -> Data
}

@MainActor
public final class DefaultSensitiveActionService: SensitiveActionService {
    private let keyStore: any KeyStoreProtocol
    private let logger: any Logger

    public init(keyStore: any KeyStoreProtocol, logger: any Logger) {
        self.keyStore = keyStore
        self.logger = logger
    }

    public func authorize(_ payload: Data, reason: String) async throws -> Data {
        // === STEP 1: Build fresh LAContext ===
        // Per WWDC22 sample + anti-pattern guard: never reuse LAContext across calls.
        let ctx = LAContext()

        // === STEP 2: Single OS prompt (.deviceOwnerAuthenticationWithBiometrics) ===
        // Strict biometric (no passcode) — see top-of-file comment for rationale.
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: reason) { success, error in
                    if success {
                        cont.resume()
                    } else if let lae = error as? LAError {
                        switch lae.code {
                        case .userCancel:
                            cont.resume(throwing: SensitiveActionError.userCancel)
                        case .biometryLockout:
                            cont.resume(throwing: SensitiveActionError.biometryLockout)
                        default:
                            cont.resume(throwing: SensitiveActionError.signFailed(underlying: lae))
                        }
                    } else {
                        cont.resume(throwing: SensitiveActionError.signFailed(
                            underlying: error ?? NSError(
                                domain: LAErrorDomain,
                                code: LAError.authenticationFailed.rawValue
                            )
                        ))
                    }
                }
            }
        } catch let e as SensitiveActionError {
            logger.warn(event: .init("sensitive_action_denied"),
                        fields: [.event: String(describing: e)])
            throw e
        }

        // === STEP 3: Sign with the SAME context — no re-prompt ===
        // KeyStoreProtocol's context-aware overload (Plan 07 Task 1) injects this
        // LAContext as kSecUseAuthenticationContext into the SE query.
        // SecKeyCreateSignature reuses the existing authorization and does NOT
        // trigger a second prompt.
        do {
            let signature = try keyStore.signWithAuthorization(payload, context: ctx)
            logger.info(event: .init("sensitive_action_signed"),
                        fields: [.count: signature.count])
            return signature
        } catch {
            logger.error(event: .init("sensitive_action_sign_failed"),
                         fields: [.event: String(describing: error)])
            throw SensitiveActionError.signFailed(underlying: error)
        }
    }
}
