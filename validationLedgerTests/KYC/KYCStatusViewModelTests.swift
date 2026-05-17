// validationLedgerTests/KYC/KYCStatusViewModelTests.swift
// Requirement: KYC-05 — KYC status UI renders four states from backend fixtures.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-06.
//
// The KYCStatusViewModel production type does not exist yet — this file compiles
// and the single @Test fails by design (Nyquist rule). Plan 05-06 replaces the RED
// placeholder with the real four-state assertion: the kyc-status-pending /
// -under-review / -verified / -rejected fixtures each map to the correct
// view-model state, with rejected surfacing per-artifact rejection reasons.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCStatusViewModel — four-state rendering from fixtures (KYC-05)", .serialized)
struct KYCStatusViewModelTests {

    @Test("KYC-05: pending / under_review / verified / rejected fixtures each map to the right state")
    func fourStatesRenderFromFixtures() async throws {
        // RED: KYCStatusViewModel is implemented in plan 05-06.
        #expect(Bool(false), "RED: KYCStatusViewModelTests — implemented in plan 05-06 (KYC-05)")
    }
}
