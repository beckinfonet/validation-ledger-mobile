// validationLedgerTests/Auth/SessionLockServiceTests.swift
import Testing
import Foundation
@testable import validationLedger

@Suite("SessionLockService — unified invariant (FOUND-07)")
struct SessionLockServiceTests {
    @Test("Cold boot — shouldRequireBiometric is true when lastSuccess is nil")
    func coldBoot() {
        let svc = DefaultSessionLockService()
        #expect(svc.shouldRequireBiometric(now: Date()) == true)
    }

    @Test("Within 5-minute grace — should NOT require biometric")
    func withinGrace() {
        let svc = DefaultSessionLockService()
        let t0 = Date()
        svc.recordBiometricSuccess(at: t0)
        let within = t0.addingTimeInterval(60)  // 1 minute later
        #expect(svc.shouldRequireBiometric(now: within) == false)
    }

    @Test("Past 5-minute grace — SHOULD require biometric")
    func pastGrace() {
        let svc = DefaultSessionLockService()
        let t0 = Date()
        svc.recordBiometricSuccess(at: t0)
        let past = t0.addingTimeInterval(301)  // 5 min + 1 sec
        #expect(svc.shouldRequireBiometric(now: past) == true)
    }

    @Test("invalidate clears lastSuccess → requires biometric")
    func invalidate() {
        let svc = DefaultSessionLockService()
        svc.recordBiometricSuccess(at: Date())
        svc.invalidate()
        #expect(svc.shouldRequireBiometric(now: Date()) == true)
    }
}
