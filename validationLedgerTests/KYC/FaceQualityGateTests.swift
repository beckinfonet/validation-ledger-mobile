// validationLedgerTests/KYC/FaceQualityGateTests.swift
// Requirement: KYC-02 — face-capture quality gate over Vision observations.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-03.
//
// The FaceQualityGate production type does not exist yet — this file compiles and
// the single @Test fails by design (Nyquist rule). Plan 05-03 replaces the RED
// placeholder with the real gate assertion over stub face observations: a centered,
// single, well-lit face passes; off-center / multiple / no-face cases are rejected.

import Testing
import Foundation
@testable import validationLedger

@Suite("FaceQualityGate — gate logic over stub observations (KYC-02)")
struct FaceQualityGateTests {

    @Test("KYC-02: a centered single face passes; off-center / multi / no-face are rejected")
    func gateLogicOverStubObservations() async throws {
        // RED: FaceQualityGate is implemented in plan 05-03.
        #expect(Bool(false), "RED: FaceQualityGateTests — implemented in plan 05-03 (KYC-02)")
    }
}
