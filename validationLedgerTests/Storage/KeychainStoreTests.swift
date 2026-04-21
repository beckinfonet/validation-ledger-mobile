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
}
