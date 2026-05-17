// validationLedgerTests/KYC/KYCCoordinatorTests.swift
// Requirement: KYC-01 — KYC capture flow-state sequencing.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-05.
//
// The KYCCoordinator production type does not exist yet — this file compiles and
// the single @Test fails by design (Nyquist rule). Plan 05-05 replaces the RED
// placeholder with the real sequencing assertion: the coordinator advances through
// the capture steps (face → DL front → DL back → vehicle → trailer → plate → review)
// in order and routes to Review only once every step is complete.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCCoordinator — capture flow-state sequencing (KYC-01)")
struct KYCCoordinatorTests {

    @Test("KYC-01: the coordinator sequences capture steps in order and routes to Review last")
    func flowStateSequencing() async throws {
        // RED: KYCCoordinator is implemented in plan 05-05.
        #expect(Bool(false), "RED: KYCCoordinatorTests — implemented in plan 05-05 (KYC-01)")
    }
}
