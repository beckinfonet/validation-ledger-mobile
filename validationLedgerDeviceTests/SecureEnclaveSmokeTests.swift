// validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift
// D-06 Phase 1 minimum gate: a single smoke test asserting
//   (a) SecureEnclave.isAvailable == true
//   (b) A test Keychain item round-trips on real hardware.
// Real SE keypair + SE-backed P256 signing are Phase 2 (DEV-01..03).
//
// Target membership: validationLedgerDeviceTests (NOT validationLedgerTests —
// simulator has no Secure Enclave; running this on simulator would fail spuriously,
// per Pitfall P8 / T-05-03).

import Testing
import CryptoKit
@testable import validationLedger

@Suite("Device Smoke — Phase 1 D-06 minimum gate")
struct SecureEnclaveSmokeTests {
    @Test("Secure Enclave is available on device")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true)
    }

    @Test("Keychain round-trip on device")
    func keychainRoundTrip() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "smoke-test-\(UUID().uuidString)")
        try store.set(Data("hello".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        let out = try store.get(key)
        #expect(out == Data("hello".utf8))
        try store.delete(key)
    }
}
