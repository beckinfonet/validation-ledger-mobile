// validationLedgerTests/Auth/SessionRestoreServiceTests.swift
// Phase 3 Plan 06 (D-04): cold-boot Keychain probe for SESS-01, AUTH-03.
// Unit tests use Swift Testing (`import Testing`), NOT XCTest.

import Testing
import Foundation
@testable import validationLedger

@Suite("SessionRestoreService — cold-boot probe (SESS-01, AUTH-03)")
struct SessionRestoreServiceTests {

    // Fresh ephemeral keychain per test — unique service name avoids cross-test bleed.
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "vl.test.restore.\(UUID().uuidString)")
    }

    @Test("probe with both sessionToken+sessionRole → .restored(role:)")
    func restoresWithBothKeys() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("carrier".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .restored(role: .carrier))
    }

    @Test("probe with only sessionToken → .needsAuth + wipes partial state")
    func needsAuthAndCleansPartial() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        // No sessionRole set
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .needsAuth)
        // Cleanup verified — token is wiped:
        #expect(throws: KeychainError.self) { _ = try store.get(.sessionToken) }
    }

    @Test("probe with empty keychain → .needsAuth (no-op cleanup)")
    func needsAuthOnEmpty() {
        let store = makeStore()
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .needsAuth)
    }

    @Test("probe with invalid role string → .needsAuth")
    func needsAuthOnInvalidRole() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("not-a-real-role".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .needsAuth)
    }
}

// MARK: - Test fakes

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
