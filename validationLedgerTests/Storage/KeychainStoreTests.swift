// validationLedgerTests/Storage/KeychainStoreTests.swift
import Testing
import Foundation
@testable import validationLedger

@Suite("KeychainStore — SecItem round-trip (Phase 1 simulator; device equivalent in DeviceTests)")
struct KeychainStoreTests {
    @Test("set → get round-trips Data")
    func setGet() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "test-set-get-\(UUID().uuidString)")
        let payload = Data("hello".utf8)
        try store.set(payload, for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        defer { try? store.delete(key) }
        let out = try store.get(key)
        #expect(out == payload)
    }

    @Test("set → delete → get throws")
    func deleteRemovesItem() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "test-delete-\(UUID().uuidString)")
        try store.set(Data("x".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.delete(key)
        #expect(throws: (any Error).self) {
            _ = try store.get(key)
        }
    }

    @Test("delete is idempotent (absent key does not throw)")
    func deleteIdempotent() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "never-exists-\(UUID().uuidString)")
        // Second delete (on absent key) must not throw
        try store.delete(key)
        try store.delete(key)
    }

    @Test("enumerateAll returns items we set")
    func enumerate() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "enum-\(UUID().uuidString)")
        try store.set(Data("e".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        defer { try? store.delete(key) }
        let all = try store.enumerateAll()
        #expect(all.contains(where: { $0.0 == key }))
    }

    // MARK: - Phase 3 Plan 04: D-33 new session-scope keys + D-16 deleteAll(under:) bulk wipe

    @Test("Phase 3 D-33 — KeychainKey.sessionRole / .sessionUserID / .biometricDomainState exist with correct raw values")
    func phase3KeychainKeysPresent() {
        #expect(KeychainKey.sessionRole.rawValue == "session.role")
        #expect(KeychainKey.sessionUserID.rawValue == "session.userID")
        #expect(KeychainKey.biometricDomainState.rawValue == "biometric.domainState")
    }

    @Test("Phase 3 D-16 — deleteAll(under: .session) wipes all 4 session-scope keys")
    func deleteAllSessionScope() throws {
        // Unique service per test run isolates keychain state from concurrent suites.
        let store = KeychainStore(service: "vl.test.deleteAllSessionScope.\(UUID().uuidString)")
        try store.set(Data("token".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("shipper".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("u-1".utf8), for: .sessionUserID, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data([0xAA, 0xBB]), for: .biometricDomainState, accessibility: .afterFirstUnlockThisDeviceOnly)

        try store.deleteAll(under: .session)

        for key in [KeychainKey.sessionToken, .sessionRole, .sessionUserID, .biometricDomainState] {
            #expect(throws: KeychainError.self) { _ = try store.get(key) }
        }
    }

    @Test("Phase 3 D-16 — deleteAll(under: .session) is idempotent on empty keychain")
    func deleteAllIdempotent() throws {
        let store = KeychainStore(service: "vl.test.deleteAllIdempotent.\(UUID().uuidString)")
        // No keys set; deleteAll should not throw.
        try store.deleteAll(under: .session)
        // And still works on a second call:
        try store.deleteAll(under: .session)
    }

    @Test("Phase 3 D-16 — deleteAll(under: .session) does NOT touch non-session keys")
    func deleteAllPreservesOutOfScopeKeys() throws {
        let store = KeychainStore(service: "vl.test.deleteAllPreserves.\(UUID().uuidString)")
        try store.set(Data("token".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("uuid-xyz".utf8), for: .installUUID, accessibility: .afterFirstUnlockThisDeviceOnly)
        defer { try? store.delete(.installUUID) }

        try store.deleteAll(under: .session)

        // sessionToken gone:
        #expect(throws: KeychainError.self) { _ = try store.get(.sessionToken) }
        // installUUID survives:
        let installData = try store.get(.installUUID)
        #expect(String(data: installData, encoding: .utf8) == "uuid-xyz")
    }
}
