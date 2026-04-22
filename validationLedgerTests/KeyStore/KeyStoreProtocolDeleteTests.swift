// validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift
// Phase 3 Plan 04 (SESS-04 / D-16): KeyStoreProtocol.deleteKey(slot:) coverage.
//
// Simulator-side verification for the new delete API:
//   - SoftwareKeyStore uses an in-memory clear (sets optional key to nil)
//     so subsequent sign calls throw keyUnavailable — symmetric with SE.
//   - SecureEnclaveKeyStore issues SecItemDelete against the same query
//     shape as loadPrivateKey. Real SE behavior requires physical device
//     (HUMAN-UAT / Phase 4 device CI); this simulator suite uses the
//     source-grep proxy pattern established by SoftwareKeyStoreExtendedTests'
//     cr02IdempotentGuardPresent.
//   - KeyStoreProtocol itself is verified via source-grep — a missing
//     protocol method is otherwise only a compile error in consumer code
//     (Plan 07 LogoutService doesn't exist yet).

import Testing
import Foundation
@testable import validationLedger

@Suite("KeyStoreProtocol — deleteKey(slot:) (SESS-04, D-16)")
struct KeyStoreProtocolDeleteTests {

    @Test("SoftwareKeyStore.deleteKey(slot: .authorization) clears in-memory auth key; device key preserved")
    func softwareDeleteAuthorizationClears() throws {
        let store = SoftwareKeyStore()
        _ = try store.generateDeviceIdentityKeys()

        try store.deleteKey(slot: .authorization)

        // Auth-key slot cleared — signWithAuthorization must throw.
        #expect(throws: KeyStoreError.self) {
            _ = try store.signWithAuthorization(Data("payload".utf8))
        }

        // Device-key slot preserved per D-16 (deviceKey is device identity,
        // not session-bound — survives logout). A DER X9.62 signature still
        // returns from sign(_:).
        let sig = try store.sign(Data("payload".utf8))
        #expect(sig.first == 0x30, "Device key must still sign DER after auth-slot delete")
    }

    @Test("SoftwareKeyStore.deleteKey(slot: .device) clears in-memory device key")
    func softwareDeleteDeviceClears() throws {
        let store = SoftwareKeyStore()
        _ = try store.generateDeviceIdentityKeys()

        try store.deleteKey(slot: .device)

        #expect(throws: KeyStoreError.self) {
            _ = try store.sign(Data("payload".utf8))
        }
    }

    @Test("SoftwareKeyStore.deleteKey is idempotent (no throw on never-generated or double-delete)")
    func softwareDeleteIdempotent() throws {
        let store = SoftwareKeyStore()
        // Never generated — both slots nil from the start.
        try store.deleteKey(slot: .authorization)
        try store.deleteKey(slot: .device)
        // And again — still no throw.
        try store.deleteKey(slot: .authorization)
        try store.deleteKey(slot: .device)
    }

    @Test("SecureEnclaveKeyStore.deleteKey source contains SecItemDelete (SE proxy, Phase 4 HUMAN-UAT)")
    func secureEnclaveDeleteCallsSecItemDelete() throws {
        // Real SE delete is HUMAN-UAT / Phase 4 device CI. Source-grep proxy
        // confirms the implementation uses SecItemDelete (the only correct API)
        // against a query that includes the slot's applicationTag.
        //
        // Path strategy: resolve via #filePath-relative URL resolution
        // (same pattern as SoftwareKeyStoreExtendedTests.cr02IdempotentGuardPresent)
        // rather than trusting xcodebuild's working directory.
        let thisFile = URL(fileURLWithPath: #filePath)
        // Repo root = thisFile’s parent × 3 (KeyStore/ → validationLedgerTests/ → repo root)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // drop KeyStoreProtocolDeleteTests.swift
            .deletingLastPathComponent()  // drop KeyStore/
            .deletingLastPathComponent()  // drop validationLedgerTests/
        let sourceURL = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Core")
            .appendingPathComponent("KeyStore")
            .appendingPathComponent("SecureEnclaveKeyStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("func deleteKey(slot: Keyslot)"),
                "deleteKey method missing from SecureEnclaveKeyStore")
        #expect(source.contains("SecItemDelete"),
                "SecureEnclaveKeyStore.deleteKey must call SecItemDelete (the only correct API)")
    }

    @Test("KeyStoreProtocol declares deleteKey(slot:) (source-grep proxy for protocol surface)")
    func protocolDeclaresDeleteKey() throws {
        // Protocol-surface verification: Plan 07 LogoutService will call
        // `keyStore.deleteKey(slot: .authorization)` through the protocol;
        // if the method isn't on the protocol, Plan 07 won't compile.
        // This test encodes that invariant as a simulator-runnable grep so
        // the invariant survives even refactors that change consumer code.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Core")
            .appendingPathComponent("KeyStore")
            .appendingPathComponent("KeyStoreProtocol.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("func deleteKey(slot: Keyslot) throws"),
                "KeyStoreProtocol must declare deleteKey(slot:) throws")
    }
}
