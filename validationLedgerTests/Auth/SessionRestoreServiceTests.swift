// validationLedgerTests/Auth/SessionRestoreServiceTests.swift
// Phase 3 Plan 06 (D-04): cold-boot Keychain probe for SESS-01, AUTH-03.
// Phase 5 Plan 07 (D-13): the probe additionally reads the cached `kycStatus`
// and routes a non-verified session to `.needsKYC(role:)` — the KYC hard gate.
// Unit tests use Swift Testing (`import Testing`), NOT XCTest.

import Testing
import Foundation
@testable import validationLedger

@Suite("SessionRestoreService — cold-boot probe (SESS-01, AUTH-03, D-13)")
struct SessionRestoreServiceTests {

    // Fresh ephemeral keychain per test — unique service name avoids cross-test bleed.
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "vl.test.restore.\(UUID().uuidString)")
    }

    @Test("probe with token+role+kycStatus=verified → .restored(role:)")
    func restoresWithVerifiedKYC() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("carrier".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        // D-13: a verified KYC status routes to the role shell.
        try store.set(Data("verified".utf8), for: .kycStatus, accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .restored(role: .carrier))
    }

    @Test("D-13: probe with token+role but kycStatus absent → .needsKYC(role:)")
    func needsKYCWhenStatusAbsent() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("broker".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        // No kycStatus key set — fails CLOSED to the KYC gate (T-05-07-02).
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .needsKYC(role: .broker))
    }

    @Test("D-13: probe with kycStatus != verified → .needsKYC(role:)")
    func needsKYCWhenStatusNotVerified() throws {
        let store = makeStore()
        try store.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try store.set(Data("shipper".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        // A "pending" / "under_review" / "rejected" status all route to the KYC gate.
        try store.set(Data("pending".utf8), for: .kycStatus, accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionRestoreService(keychain: store, logger: NoOpLogger())
        #expect(svc.probe() == .needsKYC(role: .shipper))
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
