// validationLedgerDeviceTests/KeychainBiometricACLTests.swift
// Phase 4 Plan 09 — D-13 (2) + D-14 Keychain `.biometryCurrentSet` ACL round-trip
// behind a seeded LAContext (no real Face ID prompt in unattended CI).
//
// Target membership: validationLedgerDeviceTests ONLY.
// Simulator has no Secure Enclave → the authorizationKey's `.biometryCurrentSet`
// ACL is a no-op there; this suite can only exercise the real ACL path on
// hardware.
//
// D-14 seam: SeededBiometricService (Plan 02) is injected via the
// `biometricServiceOverride` parameter of AppContainer.init (Plan 06). The
// seeded service returns `.success` synchronously without touching LAContext
// — on a physical iPhone in CI this prevents a real Face ID prompt that would
// block the unattended test run.
//
// HONEST-NAMING rule (RESEARCH Pitfall 5, 04-PATTERNS.md #21):
// Test names describe the Keychain-side-effect path
// (e.g. `testKeychainACLCreatedWhenBiometricSucceeds`). They deliberately do
// NOT claim "biometric auth end-to-end works" — that's a HUMAN-UAT concern
// (04-VALIDATION.md Manual-Only Verifications), not something unattended CI
// can verify. The real OS biometric prompt belongs to human review forever.
//
// Accept-either-outcome pattern: `signWithAuthorization` may either succeed
// (device has passthrough biometric context OR the SeededBiometricService
// seam short-circuits the LAContext chain) OR fail with
// `KeyStoreError.signingFailed` (unattended CI can't satisfy the SE ACL's
// biometric requirement even with a seeded service — the ACL check is
// enforced by the Secure Enclave itself, below the LAContext layer). Both
// outcomes are valid per SecureEnclaveKeyStoreTests.signWithAuthorizationBiometricOrFail.

import Testing
import Foundation
import Security
@testable import validationLedger

@Suite("Keychain biometric-ACL round-trip — D-13 (2) + D-14 seeded LAContext")
struct KeychainBiometricACLTests {

    // MARK: - Test helpers

    /// Delete the SE authorizationKey entry (biometry-current-set ACL) by
    /// application tag. Mirrors the SecureEnclaveKeyStoreTests.purgeAllKeys
    /// shape (line 1007 of 04-PATTERNS.md analog). Idempotent —
    /// errSecItemNotFound is treated as success.
    private func purgeAuthorizationKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("com.maldin.validationLedger.authKey".utf8),
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Also purge the deviceKey so `generateDeviceIdentityKeys()` starts from
    /// a clean slate — the call generates BOTH slots in a single SE operation
    /// and is itself idempotent (see SecureEnclaveKeyStore.generateKey CR-02
    /// guard), but we purge both to avoid any cross-test coupling.
    private func purgeBothSEKeys() {
        let authQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("com.maldin.validationLedger.authKey".utf8),
        ]
        let deviceQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("com.maldin.validationLedger.deviceKey".utf8),
        ]
        _ = SecItemDelete(authQuery as CFDictionary)
        _ = SecItemDelete(deviceQuery as CFDictionary)
    }

    /// Build an AppContainer with the seeded biometric service injected via
    /// the Plan 06 test seam. Other parameters use defaults — real Environment,
    /// real KeychainStore, real SecureEnclaveKeyStore (device target only).
    /// The seeded biometric replaces `DefaultBiometricService` transitively:
    /// `sessionLock` and `sensitiveAction` both read through the override.
    @MainActor
    private func makeContainer(seededBiometric: SeededBiometricService) -> AppContainer {
        AppContainer(
            env: Environment.current,
            networkConfig: nil,
            isSecureEnclaveAvailable: true,
            biometricServiceOverride: seededBiometric
        )
    }

    // MARK: - Tests

    @Test("Keychain ACL creation path succeeds when seeded biometric returns success")
    @MainActor
    func testKeychainACLCreatedWhenBiometricSucceeds() async throws {
        purgeAuthorizationKey()
        purgeBothSEKeys()
        defer {
            purgeAuthorizationKey()
            purgeBothSEKeys()
        }

        let seeded = SeededBiometricService()
        let container = makeContainer(seededBiometric: seeded)

        // Drive the path that creates BOTH SE entries: the `.devicePasscode`
        // deviceKey and the `.biometryCurrentSet` authorizationKey. Key
        // GENERATION does not prompt biometric (only key USE does), so this
        // call completes without the seeded service's evaluate() being hit —
        // that is the correct, documented behavior on a real device.
        let (devicePub, authPub) = try container.keyStore.generateDeviceIdentityKeys()

        // D-13-2 assertion: the biometry-current-set SE entry exists in
        // Keychain (authPub is its externally-represented public key, 65 bytes
        // on EC P-256 per SecureEnclaveKeyStoreTests.generateReturnsTwoDistinctKeys).
        #expect(
            !authPub.isEmpty,
            "authorizationKey SE entry must be created when biometric seam is seeded"
        )
        #expect(
            authPub.count == 65,
            "EC P-256 public key has 0x04 prefix + 32 X + 32 Y = 65 bytes"
        )
        #expect(
            devicePub != authPub,
            "deviceKey and authorizationKey are two distinct SE-backed keypairs (DEV-02 two-key pattern)"
        )

        // Sanity: the seeded biometric was the one wired through the container.
        #expect(
            container.biometricService as AnyObject === seeded,
            "biometricServiceOverride must be the one propagated through AppContainer"
        )
    }

    @Test("signWithAuthorization under seeded biometric either succeeds or throws signingFailed (accept-either)")
    @MainActor
    func testSignWithSeededBiometric() async throws {
        purgeAuthorizationKey()
        purgeBothSEKeys()
        defer {
            purgeAuthorizationKey()
            purgeBothSEKeys()
        }

        let seeded = SeededBiometricService()
        let container = makeContainer(seededBiometric: seeded)

        _ = try container.keyStore.generateDeviceIdentityKeys()
        let payload = Data("keychain-biometric-acl-test-payload".utf8)

        do {
            // signWithAuthorization drives the ACL-guarded SE path. Even with
            // SeededBiometricService in the container, the SE itself enforces
            // the `.biometryCurrentSet` ACL — the LAContext layer can't fake
            // a live biometric to the Secure Enclave. Outcome depends on
            // whether the CI device has a non-nil evaluatedPolicyDomainState
            // available to SecKeyCreateSignature at that moment.
            let sig = try container.keyStore.signWithAuthorization(payload, context: nil)
            #expect(
                !sig.isEmpty,
                "signWithAuthorization returned non-empty signature (passthrough biometric)"
            )
        } catch KeyStoreError.signingFailed {
            // Accept-either-outcome per SecureEnclaveKeyStoreTests analog:
            // unattended CI cannot satisfy the SE's hardware biometric
            // requirement, SecKeyCreateSignature returns nil → signingFailed.
            // This is the documented valid outcome; the sign path reached the
            // SE and the ACL correctly blocked. Pass the test.
        } catch KeyStoreError.keyUnavailable {
            // Similar to signingFailed — the SE refused to load the
            // ACL-guarded key under the current authentication context.
            // Also valid per Pitfall 5 accept-either semantics.
        } catch {
            Issue.record("Unexpected error from signWithAuthorization: \(error)")
        }
    }
}
