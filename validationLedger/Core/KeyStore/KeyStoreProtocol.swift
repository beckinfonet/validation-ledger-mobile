// validationLedger/Core/KeyStore/KeyStoreProtocol.swift
// Protocol for device-bound signing keys. Implementations:
//   - SoftwareKeyStore: simulator + DEBUG only
//   - SecureEnclaveKeyStore: production device (Phase 2 Plan 06 fills in)
// AppContainer selects via #if DEBUG && targetEnvironment(simulator).
//
// Phase 2 Plan 06 extends with:
//   - generateDeviceIdentityKeys()  — DEV-01 / DEV-02 (two-key pattern)
//   - signWithAuthorization(_:)     — DEV-02 biometric-gated signing

import Foundation

public enum KeyStoreError: Error, Sendable {
    case notImplemented
    case signingFailed
    case keyUnavailable
    case keyGenerationFailed(CFError?)  // Phase 2 Plan 06 addition (DEV-01/DEV-02)
    case keyDeletionFailed(OSStatus)    // Phase 3 Plan 04 addition (SESS-04/D-16)
}

/// Identifies which of the two device-bound keypairs a protocol call targets.
///
/// Phase 3 Plan 04 promotes this from a `SecureEnclaveKeyStore`-nested enum to
/// a top-level public type so protocol methods (`deleteKey(slot:)`) can refer
/// to it, and so `SoftwareKeyStore` can share the same slot vocabulary as the
/// SE-backed implementation. The two cases match the two-key pattern from
/// Phase 2 (DEV-02 + ADR 0004):
///
///   - `.device` — device-identity signing key (`.devicePasscode` ACL on device,
///     CryptoKit P-256 in simulator). Survives logout — deviceKey is device
///     identity, not session-bound.
///   - `.authorization` — sensitive-action signing key (`.biometryCurrentSet`
///     ACL on device). Invalidates on biometric re-enrollment. Deleted on
///     logout by LogoutService (Plan 07 → D-16).
public enum Keyslot: Sendable {
    case device
    case authorization
}

public protocol KeyStoreProtocol: AnyObject, Sendable {
    /// Sign with the device-identity key (`deviceKey`). Passcode-only ACL — no biometric prompt.
    func sign(_ data: Data) throws -> Data

    /// Public key bytes for the device-identity key (base64-encodable by caller).
    func publicKeyRepresentation() throws -> Data

    /// DEV-01 / DEV-02: generate the two identity keypairs in a single call.
    /// deviceKey: passcode-only ACL (`.devicePasscode`)
    /// authorizationKey: biometry-current-set ACL (`.biometryCurrentSet`) — invalidates on biometric re-enrollment (SESS-03 detection in Phase 3)
    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data)

    /// DEV-02: sign with the `authorizationKey`. On real device, prompts biometric.
    /// Used for sensitive operations (tender/accept/BOL — M2+). Phase 2 ships the method; Phase 3+ wires call sites.
    func signWithAuthorization(_ data: Data) throws -> Data

    /// Phase 3 SESS-04 / D-16: delete the key in the given slot from persistent storage.
    /// Used by LogoutService (Plan 07) to clear the SE authorizationKey on logout.
    /// The deviceKey is preserved across logout — it's device identity, not
    /// session-bound — so callers pass `.authorization` exclusively in M1.
    /// Idempotent: calling on a missing key succeeds (matches the
    /// `KeychainStore.delete(_:)` contract that treats errSecItemNotFound
    /// as success).
    func deleteKey(slot: Keyslot) throws
}
