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
    // Phase 3 Plan 04 (SESS-04 / D-16): optional storage so deleteKey(slot:)
    // can nil them out — mirrors SecureEnclave's key-gone-after-delete
    // semantics. Keys are lazily initialized at init (backwards-compatible
    // with pre-Phase-3 callers that don't call generateDeviceIdentityKeys
    // first); deleteKey sets the relevant slot to nil, after which any
    // sign call throws .keyUnavailable.
    private var devicePrivateKey: P256.Signing.PrivateKey? = P256.Signing.PrivateKey()
    private var authPrivateKey: P256.Signing.PrivateKey? = P256.Signing.PrivateKey()

    func sign(_ data: Data) throws -> Data {
        guard let key = devicePrivateKey else { throw KeyStoreError.keyUnavailable }
        let signature = try key.signature(for: data)
        // IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
        // Return DER X9.62 to match SecureEnclaveKeyStore's wire format
        // (ecdsaSignatureMessageX962SHA256 — see SecureEnclaveKeyStore.sign(data:slot:)).
        // Backend sees identical signature bytes from sim and device.
        return signature.derRepresentation
    }

    func publicKeyRepresentation() throws -> Data {
        guard let key = devicePrivateKey else { throw KeyStoreError.keyUnavailable }
        return key.publicKey.rawRepresentation
    }

    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data) {
        // Keys are already generated at init; this returns their public representations.
        // Matches the protocol shape so call sites (Phase 3 AuthRepository) don't branch on key store type.
        //
        // Phase 3 Plan 04 CR-02-adjacent idempotency: if a slot was cleared by
        // deleteKey(slot:) and then re-generateDeviceIdentityKeys is called
        // (D-27 step 3–4 sequential orchestration), regenerate the missing slot
        // so callers always get a usable pair back.
        if devicePrivateKey == nil { devicePrivateKey = P256.Signing.PrivateKey() }
        if authPrivateKey == nil { authPrivateKey = P256.Signing.PrivateKey() }
        guard let devKey = devicePrivateKey, let authKey = authPrivateKey else {
            throw KeyStoreError.keyUnavailable  // unreachable — we just assigned both
        }
        return (
            devKey.publicKey.rawRepresentation,
            authKey.publicKey.rawRepresentation
        )
    }

    func signWithAuthorization(_ data: Data) throws -> Data {
        // Simulator has no biometric — sign directly with the auth key.
        guard let key = authPrivateKey else { throw KeyStoreError.keyUnavailable }
        let signature = try key.signature(for: data)
        // IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
        // Return DER X9.62 to match SecureEnclaveKeyStore's wire format.
        return signature.derRepresentation
    }

    // Phase 3 Plan 04 (SESS-04 / D-16):
    // Sim/test fallback: in-memory keys, set to nil for symmetry with
    // SecureEnclave's SecItemDelete. Idempotent — calling on an
    // already-nil slot is a no-op and does not throw.
    func deleteKey(slot: Keyslot) throws {
        switch slot {
        case .device:
            devicePrivateKey = nil
        case .authorization:
            authPrivateKey = nil
        }
    }
}
