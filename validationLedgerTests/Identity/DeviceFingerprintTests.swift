// validationLedgerTests/Identity/DeviceFingerprintTests.swift
// DEV-05 validation — simulator tests for DeviceFingerprint.current(keychain:) persistence semantics.
// The KeychainStore used here is a fresh instance per test, scoped to a test-only service
// ("com.maldin.validationLedger.tests.devicefingerprint") — tests MUST clean up by deleting
// installUUIDKey in defer.

import Testing
import Foundation
import UIKit
@testable import validationLedger

@Suite("DeviceFingerprint — simulator installUUID persistence (DEV-05)")
struct DeviceFingerprintTests {

    /// Use a test-only service string so these tests don't conflict with other Keychain users.
    private static let testService = "com.maldin.validationLedger.tests.devicefingerprint"

    private func makeStore() -> KeychainStore {
        KeychainStore(service: Self.testService)
    }

    /// Purge the installUUID key before each test (paranoid — tests already clean up in defer).
    private func purge(_ store: KeychainStore) {
        try? store.delete(DeviceFingerprint.installUUIDKey)
    }

    @Test("current returns non-empty model, iosVersion, installUUID (all fields populated)")
    func currentPopulatesAllFields() throws {
        let store = makeStore()
        purge(store)
        defer { purge(store) }

        let fp = try DeviceFingerprint.current(keychain: store)
        #expect(!fp.model.isEmpty)
        #expect(!fp.iosVersion.isEmpty)
        #expect(!fp.installUUID.isEmpty)
        #expect(UUID(uuidString: fp.installUUID) != nil, "installUUID must parse as a UUID")
    }

    @Test("installUUID persists across two current() calls — same value returned")
    func installUUIDPersists() throws {
        let store = makeStore()
        purge(store)
        defer { purge(store) }

        let first = try DeviceFingerprint.current(keychain: store)
        let second = try DeviceFingerprint.current(keychain: store)
        #expect(first.installUUID == second.installUUID)
    }

    @Test("Deleting the installUUID Keychain item regenerates a new UUID on next current()")
    func deletingInstallUUIDRegenerates() throws {
        let store = makeStore()
        purge(store)
        defer { purge(store) }

        let first = try DeviceFingerprint.current(keychain: store)
        try store.delete(DeviceFingerprint.installUUIDKey)
        let second = try DeviceFingerprint.current(keychain: store)
        #expect(first.installUUID != second.installUUID)
    }

    @Test("iosVersion matches UIDevice.current.systemVersion")
    func iosVersionMatchesUIDevice() throws {
        let store = makeStore()
        purge(store)
        defer { purge(store) }

        let fp = try DeviceFingerprint.current(keychain: store)
        // Use a string-equality check — UIDevice.current.systemVersion is the source of truth.
        #expect(fp.iosVersion == UIDevice.current.systemVersion)
    }
}
