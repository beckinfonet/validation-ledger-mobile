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
}
