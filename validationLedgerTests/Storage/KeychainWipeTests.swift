// validationLedgerTests/Storage/KeychainWipeTests.swift
import Testing
import Foundation
@testable import validationLedger

// NOTE: .serialized trait is required because KeychainWiper.wipeOnFirstLaunch
// operates at the class level (no service scope) and manipulates the shared
// system Keychain + UserDefaults.standard. Parallel execution causes one test
// to wipe a second test's seed key mid-flight (Rule-1 bug discovered during
// Task 2 — see SUMMARY.md). Within the suite, tests run in-order (one at a time).
@Suite("KeychainWipe — FOUND-02 enumerate-before-delete contract", .serialized)
struct KeychainWipeTests {
    @Test("Wipe deletes pre-existing items and sets didCompleteFirstLaunch flag")
    func wipeOnFirstLaunch() throws {
        // Arrange — seed the Keychain and clear the flag
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "didCompleteFirstLaunch")
        let store = KeychainStore()
        let seedKey = KeychainKey(rawValue: "seed-\(UUID().uuidString)")
        try store.set(Data("seed".utf8), for: seedKey, accessibility: .afterFirstUnlockThisDeviceOnly)

        // Act — run the wipe function (the AppDelegate-embedded one is Plan 05;
        //         for now, exercise the equivalent KeychainWiper helper that Plan 03 ships
        //         alongside KeychainStore to make wipe logic unit-testable).
        KeychainWiper.wipeOnFirstLaunch(defaults: defaults)

        // Assert — seed key gone, flag true
        #expect(defaults.bool(forKey: "didCompleteFirstLaunch") == true)
        #expect(throws: (any Error).self) {
            _ = try store.get(seedKey)
        }
    }

    @Test("Wipe is no-op on subsequent launches (flag gate)")
    func wipeNoOpWhenFlagSet() throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "didCompleteFirstLaunch")  // simulate prior launch
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "survives-\(UUID().uuidString)")
        try store.set(Data("survives".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        defer { try? store.delete(key) }

        // Act — wipe should NOT delete (flag already set)
        KeychainWiper.wipeOnFirstLaunch(defaults: defaults)

        // Assert — item still there
        let data = try store.get(key)
        #expect(data == Data("survives".utf8))
    }
}
