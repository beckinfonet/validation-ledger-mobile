// validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift
// Simulator unit tests for Phase 2 KeyStoreProtocol extensions
// (generateDeviceIdentityKeys + signWithAuthorization).
// Runs in validationLedgerTests (simulator target) — SoftwareKeyStore works everywhere.
// The device-only equivalent for SecureEnclaveKeyStore is in validationLedgerDeviceTests/.

import Testing
import Foundation
@testable import validationLedger

@Suite("SoftwareKeyStore — Phase 2 two-key extensions")
struct SoftwareKeyStoreExtendedTests {

    @Test("generateDeviceIdentityKeys returns two distinct 64-byte public keys")
    func generateReturnsTwoDistinctKeys() throws {
        let store = SoftwareKeyStore()
        let (devicePub, authPub) = try store.generateDeviceIdentityKeys()
        #expect(devicePub.count == 64, "CryptoKit P-256 publicKey.rawRepresentation is 64 bytes (32 X + 32 Y — no 0x04 prefix)")
        #expect(authPub.count == 64)
        #expect(devicePub != authPub, "device + auth keys must be distinct")
    }

    @Test("publicKeyRepresentation returns the device-slot public key")
    func publicKeyRepIsDeviceSlot() throws {
        let store = SoftwareKeyStore()
        let (devicePub, _) = try store.generateDeviceIdentityKeys()
        let resolved = try store.publicKeyRepresentation()
        #expect(resolved == devicePub)
    }

    @Test("sign and signWithAuthorization produce distinct signatures for the same input")
    func twoKeysProduceDistinctSignatures() throws {
        let store = SoftwareKeyStore()
        let payload = Data("test payload for two-key signing".utf8)
        let deviceSig = try store.sign(payload)
        let authSig = try store.signWithAuthorization(payload)
        #expect(!deviceSig.isEmpty)
        #expect(!authSig.isEmpty)
        #expect(deviceSig != authSig, "different keys must produce different signatures")
    }

    @Test("sign produces consistent-size ECDSA P-256 rawRepresentation (64 bytes)")
    func signSize() throws {
        let store = SoftwareKeyStore()
        let sig = try store.sign(Data("x".utf8))
        #expect(sig.count == 64, "P-256 raw ECDSA signature is 32+32 = 64 bytes")
    }
}
