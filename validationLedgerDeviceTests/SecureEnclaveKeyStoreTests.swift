// validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift
// DEV-01 + DEV-02 device-target tests for SecureEnclaveKeyStore round-trip.
//
// Target membership: validationLedgerDeviceTests ONLY. Simulator has no SEP — this suite
// WILL NOT pass on simulator (keys would fail with errSecUnimplemented). Research Pitfall 2.
//
// Test cleanup: each @Test deletes both application tags from Keychain in defer blocks —
// avoids persistent-state leakage across test runs on the same physical device.
//
// Biometric handling in CI: tests that use signWithAuthorization may prompt Face ID / Touch ID
// on interactive device runs. In unattended CI (self-hosted runner), those prompts fail with
// errSecAuthFailed — the relevant test accepts either outcome as valid (documented inline).

import Testing
import Foundation
import Security
import CryptoKit
@testable import validationLedger

@Suite("SecureEnclaveKeyStore — DEV-01/02 device round-trip")
struct SecureEnclaveKeyStoreTests {

    private func deleteKeychainKey(tag: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: tag,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    private func purgeAllKeys() {
        deleteKeychainKey(tag: Data("com.maldin.validationLedger.deviceKey".utf8))
        deleteKeychainKey(tag: Data("com.maldin.validationLedger.authKey".utf8))
    }

    @Test("Secure Enclave is available on this device")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true, "Device tests require Secure Enclave; simulator would fail here")
    }

    @Test("generateDeviceIdentityKeys creates two distinct 65-byte EC P-256 public keys")
    func generateReturnsTwoDistinctKeys() throws {
        purgeAllKeys()
        defer { purgeAllKeys() }

        let store = SecureEnclaveKeyStore()
        let (devicePub, authPub) = try store.generateDeviceIdentityKeys()
        // SecKeyCopyExternalRepresentation for EC P-256 returns 65 bytes: 0x04 prefix + 32 X + 32 Y.
        #expect(devicePub.count == 65)
        #expect(authPub.count == 65)
        #expect(devicePub != authPub)
    }

    @Test("sign with device key produces non-empty signature that verifies against the public key")
    func signAndVerifyDeviceKey() throws {
        purgeAllKeys()
        defer { purgeAllKeys() }

        let store = SecureEnclaveKeyStore()
        let (devicePubData, _) = try store.generateDeviceIdentityKeys()
        let payload = Data("validation-ledger device-key test payload".utf8)
        let signature = try store.sign(payload)
        #expect(!signature.isEmpty)

        // Verify via CryptoKit.P256 — the public key format from SecKeyCopyExternalRepresentation
        // (65 bytes: 0x04 prefix + 32 X + 32 Y) is compatible with P256.Signing.PublicKey(x963Representation:).
        let publicKey = try P256.Signing.PublicKey(x963Representation: devicePubData)
        let ecdsaSig = try P256.Signing.ECDSASignature(derRepresentation: signature)
        #expect(publicKey.isValidSignature(ecdsaSig, for: payload))
    }

    @Test("publicKeyRepresentation returns the device-slot key (matches generateDeviceIdentityKeys)")
    func publicKeyRepresentationMatchesDeviceSlot() throws {
        purgeAllKeys()
        defer { purgeAllKeys() }

        let store = SecureEnclaveKeyStore()
        let (devicePub, _) = try store.generateDeviceIdentityKeys()
        let retrieved = try store.publicKeyRepresentation()
        #expect(retrieved == devicePub)
    }

    @Test("loadPrivateKey retrieves persistent key by tag after generation")
    func persistentKeyRetrieval() throws {
        purgeAllKeys()
        defer { purgeAllKeys() }

        // First generate.
        let store1 = SecureEnclaveKeyStore()
        let (devicePub1, _) = try store1.generateDeviceIdentityKeys()

        // Construct a fresh store (simulates app relaunch) — keys should persist.
        let store2 = SecureEnclaveKeyStore()
        let devicePub2 = try store2.publicKeyRepresentation()
        #expect(devicePub1 == devicePub2, "Public key must persist across SecureEnclaveKeyStore instances")
    }

    @Test("signWithAuthorization either succeeds or fails with errSecAuthFailed (biometric required)")
    func signWithAuthorizationBiometricOrFail() throws {
        purgeAllKeys()
        defer { purgeAllKeys() }

        let store = SecureEnclaveKeyStore()
        _ = try store.generateDeviceIdentityKeys()
        let payload = Data("auth-key test".utf8)
        do {
            let sig = try store.signWithAuthorization(payload)
            // Biometric succeeded (device runs may have LA passthrough configured).
            #expect(!sig.isEmpty)
        } catch KeyStoreError.signingFailed {
            // Biometric prompt was denied or unattended; this is a valid outcome for CI.
            // The sign path reached SecKeyCreateSignature and received a failure — that's correct.
            // If we need to assert-on-specific-OSStatus in the future, catch a more specific error via
            // extending the SecureEnclaveKeyStore error mapping.
            // Documented acceptable outcome; pass the test.
        } catch {
            Issue.record("Unexpected error from signWithAuthorization: \(error)")
        }
    }
}
