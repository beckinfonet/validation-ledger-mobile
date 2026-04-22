// validationLedger/Core/KeyStore/SoftwareKeyStore.swift
// In-memory P256 keypairs — SIMULATOR + DEBUG ONLY.
// AppContainer's #if DEBUG && targetEnvironment(simulator) branch is the only resolver.
//
// Phase 2 Plan 06 extends Phase 1's single-key impl to the two-key pattern:
//   - devicePrivateKey — Phase 1 "privateKey" renamed; sign(_:) + publicKeyRepresentation route here
//   - authPrivateKey   — authorization-key simulator equivalent; signWithAuthorization routes here
// Simulator does NOT prompt biometric — signWithAuthorization signs directly.
// Biometric semantics are exercised only on device (validationLedgerDeviceTests/SecureEnclaveKeyStoreTests).

import Foundation
import CryptoKit

final class SoftwareKeyStore: KeyStoreProtocol {
    private let devicePrivateKey = P256.Signing.PrivateKey()
    private let authPrivateKey = P256.Signing.PrivateKey()

    func sign(_ data: Data) throws -> Data {
        let signature = try devicePrivateKey.signature(for: data)
        // IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
        // Return DER X9.62 to match SecureEnclaveKeyStore's wire format
        // (ecdsaSignatureMessageX962SHA256 — see SecureEnclaveKeyStore.sign(data:slot:)).
        // Backend sees identical signature bytes from sim and device.
        return signature.derRepresentation
    }

    func publicKeyRepresentation() throws -> Data {
        devicePrivateKey.publicKey.rawRepresentation
    }

    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data) {
        // Keys are already generated at init; this returns their public representations.
        // Matches the protocol shape so call sites (Phase 3 AuthRepository) don't branch on key store type.
        return (
            devicePrivateKey.publicKey.rawRepresentation,
            authPrivateKey.publicKey.rawRepresentation
        )
    }

    func signWithAuthorization(_ data: Data) throws -> Data {
        // Simulator has no biometric — sign directly with the auth key.
        let signature = try authPrivateKey.signature(for: data)
        // IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
        // Return DER X9.62 to match SecureEnclaveKeyStore's wire format.
        return signature.derRepresentation
    }
}
