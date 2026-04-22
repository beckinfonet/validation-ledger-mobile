// validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
// DEV-01 + DEV-02 + DEV-03 (production side): Secure-Enclave-backed EC P-256 signing.
//
// Two-key pattern per DEV-02:
//   - deviceKey: [.privateKeyUsage, .devicePasscode]       — device identity, no biometric prompt
//   - authorizationKey: [.privateKeyUsage, .biometryCurrentSet] — sensitive actions, prompts biometric
//                                                             AND invalidates on biometric re-enrollment
//                                                             (Research Pitfall 1 — INTENTIONAL behavior)
//
// Key material NEVER leaves the enclave. Keychain stores only the application-tag reference;
// SecItemCopyMatching returns a SecKey pointer back to the enclave-held key.
//
// Runs on device only. Simulator uses SoftwareKeyStore via AppContainer's
// #if DEBUG && targetEnvironment(simulator) gate. Test membership: validationLedgerDeviceTests/
// (Research Pitfall 2 — simulator has no SE; tests there would silently "pass" without
// exercising this file at all).

import Foundation
import Security
import CryptoKit

final class SecureEnclaveKeyStore: KeyStoreProtocol {

    enum Keyslot {
        case device
        case authorization

        var applicationTag: Data {
            switch self {
            case .device:        return Data("com.maldin.validationLedger.deviceKey".utf8)
            case .authorization: return Data("com.maldin.validationLedger.authKey".utf8)
            }
        }

        var accessControlFlags: SecAccessControlCreateFlags {
            switch self {
            case .device:        return [.privateKeyUsage, .devicePasscode]
            case .authorization: return [.privateKeyUsage, .biometryCurrentSet]
            }
        }
    }

    init() {}

    // MARK: - KeyStoreProtocol

    func sign(_ data: Data) throws -> Data {
        try sign(data: data, slot: .device)
    }

    func publicKeyRepresentation() throws -> Data {
        try loadPublicKey(slot: .device)
    }

    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data) {
        let devicePub = try generateKey(slot: .device)
        let authPub = try generateKey(slot: .authorization)
        return (devicePub, authPub)
    }

    func signWithAuthorization(_ data: Data) throws -> Data {
        // On device, this triggers Face ID / Touch ID prompt because of .biometryCurrentSet.
        // On biometric re-enrollment (user adds a finger, replaces a face scan), this call
        // throws with errSecAuthFailed or -25293 errSecInvalidKey — Phase 3 SESS-03 catches
        // that error pattern and surfaces the "re-bind device" flow.
        try sign(data: data, slot: .authorization)
    }

    // MARK: - Private

    private func generateKey(slot: Keyslot) throws -> Data {
        // CR-02 (Phase 2 carryover, closed Phase 3 Plan 02): idempotent guard.
        // If a key already exists for this slot, return its public representation
        // instead of inserting a second key. Without this, a second generateKey(slot:)
        // call silently inserts a new SecKey alongside the old one and loadPrivateKey
        // may return either — breaking pub/priv pairing on the next sign call.
        if let existingPub = try? loadPublicKey(slot: slot) {
            return existingPub
        }
        var acError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            slot.accessControlFlags,
            &acError
        ) else {
            throw KeyStoreError.keyGenerationFailed(acError?.takeRetainedValue())
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: slot.applicationTag,
                kSecAttrAccessControl: accessControl,
            ] as CFDictionary,
        ]

        var genError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &genError) else {
            throw KeyStoreError.keyGenerationFailed(genError?.takeRetainedValue())
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeyStoreError.keyGenerationFailed(nil)
        }
        return data
    }

    private func loadPrivateKey(slot: Keyslot) throws -> SecKey {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: slot.applicationTag,
            kSecReturnRef: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeyStoreError.keyUnavailable
        }
        guard let key = item, CFGetTypeID(key) == SecKeyGetTypeID() else {
            throw KeyStoreError.keyUnavailable
        }
        // Force-cast would crash on nil; we guarded above with CFGetTypeID.
        return key as! SecKey
    }

    private func loadPublicKey(slot: Keyslot) throws -> Data {
        let privateKey = try loadPrivateKey(slot: slot)
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeyStoreError.keyUnavailable
        }
        return data
    }

    private func sign(data: Data, slot: Keyslot) throws -> Data {
        let privateKey = try loadPrivateKey(slot: slot)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw KeyStoreError.signingFailed
        }
        return signature
    }
}
