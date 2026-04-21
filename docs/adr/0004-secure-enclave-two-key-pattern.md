# ADR 0004: Secure Enclave two-key pattern with `.biometryCurrentSet` for authorization

**Date:** 2026-04-21
**Status:** Accepted
**Supersedes:** — (new decision)
**Superseded by:** — (current)

## Context

DEV-02 (REQUIREMENTS.md) requires two distinct device-bound EC P-256 keypairs:

- **deviceKey** — device-identity signatures on every authenticated request (e.g., `/device/register`, future Phase 3 session-token signing).
- **authorizationKey** — sensitive-action signatures (tender/accept/BOL generation — M2+). Must prompt biometric every use.

A single-key design (biometry always required) would force Face ID on every API call — UX failure. A
single-key design (biometry never required) would leave no way to hardware-gate sensitive actions
against a phone lying unlocked on a desk. The two-key split is the only way to serve both
requirements: frequent low-friction signatures use `deviceKey`; infrequent high-stakes signatures
use `authorizationKey`.

Apple's Security framework exposes the Access Control list via `SecAccessControlCreateWithFlags`.
The relevant flags:

- `.privateKeyUsage` — required for any key-bound operation (signing, decrypting).
- `.devicePasscode` — accessible when the device is unlocked; no biometric prompt.
- `.biometryAny` — accepts current + future biometric enrollments; survives re-enrollment.
- `.biometryCurrentSet` — accepts ONLY the biometric set enrolled AT KEY CREATION TIME; ANY later enrollment change (adding a fingerprint, replacing a Face ID scan, disabling/re-enabling Touch ID) makes the key **permanently inaccessible**.

## Decision

- **deviceKey** uses flags `[.privateKeyUsage, .devicePasscode]`.
- **authorizationKey** uses flags `[.privateKeyUsage, .biometryCurrentSet]`.
- Both are EC P-256, generated in the Secure Enclave via `SecKeyCreateRandomKey` with `kSecAttrTokenID = kSecAttrTokenIDSecureEnclave`.
- Application tags are `com.maldin.validationLedger.deviceKey` and `com.maldin.validationLedger.authKey` respectively.
- Accessibility on both is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — standard posture for device-bound keys.
- The `.biometryCurrentSet` invalidation-on-re-enrollment is NOT a bug to be worked around — it IS the security mechanism. Phase 3's `SESS-03` re-binding flow detects the `errSecAuthFailed` / `errSecInvalidKey` patterns and surfaces a "re-bind device" UI.

## Consequences

### Positive

- A stolen phone + stolen biometric (unlikely but possible) has a limited window: the moment the attacker
  re-enrolls their own biometrics, the authorizationKey invalidates and sensitive signing fails.
  Combined with the backend's counter/challenge + App Attest (Phase 4) this significantly raises
  the bar for identity takeover.
- deviceKey's low-friction access keeps API call UX smooth — users never see a Face ID prompt for routine network I/O.

### Negative

- Legitimate user Face ID re-enrollments (adding a new finger, replacing a face scan due to appearance changes) WILL invalidate the authorizationKey and force a re-bind flow. Expected to be rare in practice; the UX cost is accepted.
- Two keys means two `kSecAttrApplicationTag` values and two distinct generation + retrieval paths in `SecureEnclaveKeyStore` — more code to audit than a single-key design.

### Acknowledged but NOT addressed

- **We do NOT use `.biometryAny`** — it would retain key access across biometric changes, defeating
  the security property. Research Pitfall 1 is explicit: do not "fix" UX by switching to `.biometryAny`.
- **We do NOT use CryptoKit's `SecureEnclave.P256.Signing.PrivateKey`** — the convenience wrapper does
  not expose `.biometryCurrentSet` ACL. Phase 2 uses the lower-level Security framework path.

## Alternatives Considered

1. **Single key with `.biometryAny`**: REJECTED. Every API call prompts biometric. UX unacceptable.
2. **Single key with `.devicePasscode`**: REJECTED. No hardware-gated sensitive-action path. Fails DEV-02.
3. **Single key + separate symmetric wrapping key for sensitive actions**: REJECTED. Adds crypto
   complexity without meaningfully improving on the two-key design.
4. **CryptoKit `SecureEnclave.P256.Signing.PrivateKey`**: REJECTED. Does not expose `.biometryCurrentSet`.

## Operational Notes

- When the user re-enrolls biometrics, `authorizationKey` signing returns `errSecAuthFailed` (or
  `-25293 errSecInvalidKey`). Phase 3's `SessionLockService` catches this and triggers the re-bind
  flow (stubbed in Phase 3; the sensitive-action call sites don't exist until M2+).
- For testing: `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` exercises the two-key
  round-trip on physical hardware. Simulator tests use `SoftwareKeyStore` (which does NOT enforce
  biometric — biometric semantics are device-only, per Research Pitfall 2).

## References

- Apple — [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- Apple — [SecAccessControlCreateFlags](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags)
- Apple — [biometryCurrentSet](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/ksecaccesscontrolbiometrycurrentset)
- Gridnev — [iOS Keychain using Secure Enclave-stored keys](https://medium.com/@alx.gridnev/ios-keychain-using-secure-enclave-stored-keys-8f7c81227f4)
- `.planning/phases/02-networking-contract-device-keys/02-RESEARCH.md` Pattern 7 + Pitfall 1
- `.planning/REQUIREMENTS.md` DEV-02
