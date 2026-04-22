// validationLedgerTests/Auth/SessionLockServiceTests.swift
// Phase 1 FOUND-07 invariants preserved + Phase 3 Plan 06 (D-07/D-08/D-09) extensions.
// Unit tests use Swift Testing (`import Testing`), NOT XCTest.

import Testing
import Foundation
@testable import validationLedger

// MARK: - Test fakes

@MainActor
private final class StubBiometricService: BiometricService {
    // Only written on MainActor via the tests themselves.
    nonisolated(unsafe) var stubbedDomainState: Data?

    func evaluate(reason: String, fallback: BiometricFallback) async throws {}

    nonisolated func currentDomainState() -> Data? {
        stubbedDomainState
    }
}

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}

@Suite("SessionLockService — Phase 1 invariants + Phase 3 lockState (FOUND-07, SESS-01..03)")
@MainActor
struct SessionLockServiceTests {

    // Helper: fresh ephemeral keychain + new service.
    private func makeService(
        stubBiometric: StubBiometricService = StubBiometricService()
    ) -> DefaultSessionLockService {
        let keychain = KeychainStore(service: "vl.test.lock.\(UUID().uuidString)")
        return DefaultSessionLockService(biometric: stubBiometric, keychain: keychain)
    }

    // MARK: - Phase 1 invariants (preserved across the init-signature change)

    @Test("Cold boot — shouldRequireBiometric is true when lastSuccess is nil")
    func coldBoot() {
        #expect(makeService().shouldRequireBiometric(now: Date()) == true)
    }

    @Test("Within 5-minute grace — should NOT require biometric")
    func withinGrace() {
        let svc = makeService()
        let t0 = Date()
        svc.recordBiometricSuccess(at: t0)
        #expect(svc.shouldRequireBiometric(now: t0.addingTimeInterval(60)) == false)
    }

    @Test("After invalidate — requires biometric again")
    func afterInvalidate() {
        let svc = makeService()
        svc.recordBiometricSuccess(at: Date())
        svc.invalidate()
        #expect(svc.shouldRequireBiometric(now: Date()) == true)
    }

    // MARK: - Phase 3 D-07/D-08/D-09

    @Test("D-07 — lockState returns .locked(.coldBoot) when lastSuccess is nil")
    func lockStateColdBoot() {
        #expect(makeService().lockState(now: Date()) == .locked(reason: .coldBoot))
    }

    @Test("D-07 — lockState returns .unlocked when lastSuccess recent + no domain diff")
    func lockStateUnlocked() {
        let svc = makeService()
        let t0 = Date()
        svc.recordBiometricSuccess(at: t0)
        #expect(svc.lockState(now: t0.addingTimeInterval(30)) == .unlocked)
    }

    @Test("D-09 — lockState returns .locked(.biometricReEnrolled) when stored vs current domainState differ (highest priority)")
    func lockStateBiometricReEnrolled() throws {
        let stub = StubBiometricService()
        stub.stubbedDomainState = Data([0x01, 0x02, 0x03])  // current
        let keychain = KeychainStore(service: "vl.test.lock.reenroll.\(UUID().uuidString)")
        // Stored is DIFFERENT:
        try keychain.set(Data([0xFF, 0xEE]), for: .biometricDomainState,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionLockService(biometric: stub, keychain: keychain)
        // Even with a recent recordBiometricSuccess, biometricReEnrolled wins:
        svc.recordBiometricSuccess(at: Date())
        #expect(svc.lockState(now: Date()) == .locked(reason: .biometricReEnrolled))
    }

    @Test("D-09 — lockState does NOT return biometricReEnrolled when stored == current")
    func lockStateNoDiffWhenEqual() throws {
        let stub = StubBiometricService()
        stub.stubbedDomainState = Data([0x01, 0x02, 0x03])
        let keychain = KeychainStore(service: "vl.test.lock.equal.\(UUID().uuidString)")
        try keychain.set(Data([0x01, 0x02, 0x03]), for: .biometricDomainState,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        let svc = DefaultSessionLockService(biometric: stub, keychain: keychain)
        svc.recordBiometricSuccess(at: Date())
        #expect(svc.lockState(now: Date()) == .unlocked)
    }

    @Test("invalidate — clears stored .biometricDomainState (per D-16 step 4 mirror)")
    func invalidateClearsDomainState() throws {
        let keychain = KeychainStore(service: "vl.test.lock.invalidate.\(UUID().uuidString)")
        let svc = DefaultSessionLockService(biometric: StubBiometricService(), keychain: keychain)
        try keychain.set(Data([0xAB]), for: .biometricDomainState,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        svc.invalidate()
        #expect(throws: KeychainError.self) { _ = try keychain.get(.biometricDomainState) }
    }
}
