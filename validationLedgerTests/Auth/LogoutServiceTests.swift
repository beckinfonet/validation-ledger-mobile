// validationLedgerTests/Auth/LogoutServiceTests.swift
// Plan 07 TDD — SESS-04 + AUTH-04 + D-16 (6-step orchestration) + Warning 2 fix
// (Step 2/4 collapse because KeychainScope.session includes .biometricDomainState).
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.

import Testing
import Foundation
@testable import validationLedger

@MainActor
private final class StubBiometric: BiometricService {
    nonisolated func currentDomainState() -> Data? { nil }
    func evaluate(reason: String, fallback: BiometricFallback) async throws {}
}

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}

@Suite("LogoutService — single-funnel teardown (SESS-04, AUTH-04, D-16, Warning 2)")
@MainActor
struct LogoutServiceTests {

    @Test("D-30: LogoutReason raw values are stable strings")
    func logoutReasonRawValues() {
        #expect(LogoutReason.userInitiated.rawValue == "userInitiated")
        #expect(LogoutReason.auth401.rawValue == "auth401")
        #expect(LogoutReason.anotherActiveSession.rawValue == "anotherActiveSession")
    }

    @Test("D-16: logout wipes session keychain + deletes auth key + invalidates session lock")
    func logoutFullTeardown() async throws {
        let keychain = KeychainStore(service: "vl.test.logout.\(UUID().uuidString)")
        try keychain.set(Data("tok".utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data("carrier".utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)

        let keyStore = SoftwareKeyStore()
        _ = try keyStore.generateDeviceIdentityKeys()  // populates both slots

        let lock = DefaultSessionLockService(biometric: StubBiometric(), keychain: keychain)
        lock.recordBiometricSuccess(at: Date())

        let nc = NotificationCenter()  // isolated instance for the test
        let svc = DefaultLogoutService(
            keychain: keychain,
            keyStore: keyStore,
            sessionLock: lock,
            logger: NoOpLogger(),
            notificationCenter: nc
        )

        await svc.logout(reason: .userInitiated)

        // Keychain wiped:
        #expect(throws: KeychainError.self) { _ = try keychain.get(.sessionToken) }
        #expect(throws: KeychainError.self) { _ = try keychain.get(.sessionRole) }

        // SessionLock invalidated → cold-boot returns true:
        #expect(lock.shouldRequireBiometric(now: Date()) == true)

        // SE auth key removed (signWithAuthorization throws because key was nil'd):
        #expect(throws: KeyStoreError.self) {
            _ = try keyStore.signWithAuthorization(Data("p".utf8))
        }
        // Device key preserved:
        let sig = try keyStore.sign(Data("p".utf8))
        #expect(sig.first == 0x30)
    }

    @Test("Warning 2: logout clears biometricDomainState from Keychain (Step 2/4 collapse)")
    func logoutClearsBiometricDomainState() async throws {
        let keychain = KeychainStore(service: "vl.test.logout.bdomain.\(UUID().uuidString)")
        try keychain.set(Data([0xAA, 0xBB]), for: .biometricDomainState,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        // Verify it's there:
        #expect((try? keychain.get(.biometricDomainState)) != nil)

        let keyStore = SoftwareKeyStore()
        let lock = DefaultSessionLockService(biometric: StubBiometric(), keychain: keychain)
        let svc = DefaultLogoutService(
            keychain: keychain, keyStore: keyStore, sessionLock: lock,
            logger: NoOpLogger(), notificationCenter: NotificationCenter()
        )
        await svc.logout(reason: .userInitiated)

        // Step 2/4 collapse: deleteAll(under: .session) wiped biometricDomainState too.
        #expect((try? keychain.get(.biometricDomainState)) == nil,
                "biometricDomainState must be wiped post-logout — Step 2/4 collapse per Warning 2 fix")
    }

    @Test("D-16 step 6: notification posted with reason in userInfo")
    func notificationPostedWithReason() async throws {
        let keychain = KeychainStore(service: "vl.test.logout.notify.\(UUID().uuidString)")
        let keyStore = SoftwareKeyStore()
        let lock = DefaultSessionLockService(biometric: StubBiometric(), keychain: keychain)
        let nc = NotificationCenter()

        // Capture the notification via an actor to cross the Sendable boundary safely.
        actor Captured {
            var name: Notification.Name?
            var reason: String?
            func record(_ n: Notification.Name, _ reason: String?) {
                self.name = n
                self.reason = reason
            }
        }
        let captured = Captured()
        let token = nc.addObserver(forName: .sessionDidInvalidate, object: nil, queue: nil) { note in
            let reasonString = note.userInfo?[Notification.Name.LogoutReasonKey] as? String
            Task { await captured.record(note.name, reasonString) }
        }
        defer { nc.removeObserver(token) }

        let svc = DefaultLogoutService(
            keychain: keychain, keyStore: keyStore, sessionLock: lock,
            logger: NoOpLogger(), notificationCenter: nc
        )
        await svc.logout(reason: .auth401)
        // Yield to let the observer Task run.
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(await captured.name == .sessionDidInvalidate)
        #expect(await captured.reason == "auth401")
    }
}
