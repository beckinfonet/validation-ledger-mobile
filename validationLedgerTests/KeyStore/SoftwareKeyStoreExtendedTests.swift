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

    @Test("sign produces DER X9.62 ECDSA P-256 signature (IN-02 — matches SE wire format)")
    func signSize() throws {
        let store = SoftwareKeyStore()
        let sig = try store.sign(Data("x".utf8))
        // IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
        // sign(_:) now returns DER X9.62 (same wire format as SecureEnclaveKeyStore).
        // DER ECDSA signature is ASN.1 SEQUENCE starting with 0x30; P-256 DER length is
        // typically 70–72 bytes depending on r/s leading-zero padding.
        #expect(sig.first == 0x30, "DER SEQUENCE tag expected at byte 0")
        #expect(sig.count >= 70 && sig.count <= 72, "P-256 DER ECDSA is 70–72 bytes; got \(sig.count)")
    }

    // MARK: - IN-02 DER unification (Pre-Phase-3 carryover, closed Phase 3 Plan 02)

    @Test("IN-02 — sign(_:) returns DER X9.62 (starts with 0x30 SEQUENCE tag)")
    func signReturnsDER() throws {
        let store = SoftwareKeyStore()
        // generateDeviceIdentityKeys is a no-op here since keys are created at init,
        // but invoking it matches the documented API contract downstream callers use.
        _ = try store.generateDeviceIdentityKeys()
        let payload = Data("test-payload".utf8)
        let sig = try store.sign(payload)
        // DER ECDSA signature is ASN.1 SEQUENCE — first byte is 0x30.
        // 64-byte compact format would start with the r-coordinate's first byte (random).
        #expect(sig.first == 0x30, "Expected DER SEQUENCE tag (0x30); got \(sig.first.map { String(format: "0x%02x", $0) } ?? "nil")")
        #expect(sig.count >= 70 && sig.count <= 72, "DER length for P-256 is 70–72 bytes; got \(sig.count)")
    }

    @Test("IN-02 — signWithAuthorization(_:) returns DER X9.62")
    func signWithAuthorizationReturnsDER() throws {
        let store = SoftwareKeyStore()
        _ = try store.generateDeviceIdentityKeys()
        let payload = Data("test-payload".utf8)
        let sig = try store.signWithAuthorization(payload)
        #expect(sig.first == 0x30)
        #expect(sig.count >= 70 && sig.count <= 72)
    }

    // MARK: - CR-02 idempotent guard (source-grep proxy; real SE verification is device-only)

    @Test("CR-02 — SecureEnclaveKeyStore.generateKey idempotent guard is present (source-grep proxy)")
    func cr02IdempotentGuardPresent() throws {
        // Real CR-02 verification requires SE hardware (HUMAN-UAT / Phase 4 device CI).
        // Simulator proxy: assert the source file contains the idempotent-guard string,
        // proving the fix is in place even though we can't exercise it on a sim.
        //
        // Path strategy: resolve via #filePath (this test file's path) instead of relying
        // on xcodebuild's working directory, which is not guaranteed to be the repo root.
        let thisFile = URL(fileURLWithPath: #filePath)
        // Repo root = thisFile’s parent × 3 (KeyStore → validationLedgerTests → repo root)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // drop SoftwareKeyStoreExtendedTests.swift
            .deletingLastPathComponent()  // drop KeyStore/
            .deletingLastPathComponent()  // drop validationLedgerTests/
        let sourceURL = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Core")
            .appendingPathComponent("KeyStore")
            .appendingPathComponent("SecureEnclaveKeyStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("try? loadPublicKey(slot: slot)"),
                "CR-02 idempotent guard missing from generateKey — expected `try? loadPublicKey(slot: slot)` near top of generateKey")
        #expect(source.contains("CR-02"),
                "CR-02 fix marker comment missing — make the carryover-fix lineage visible")
    }
}
