// validationLedgerTests/KYC/KYCReviewViewModelTests.swift
// Requirement: KYC-01 — the Review-screen gated-Submit state machine.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-06.
//
// The KYCReviewViewModel production type does not exist yet — this file compiles
// and the single @Test fails by design (Nyquist rule). Plan 05-06 replaces the RED
// placeholder with the real gated-Submit assertion: Submit is disabled until all 6
// artifacts are captured and confirmed, and enabled exactly when the bundle is complete.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCReviewViewModel — gated-Submit state machine (KYC-01)")
struct KYCReviewViewModelTests {

    @Test("KYC-01: Submit is gated until all 6 artifacts are captured and confirmed")
    func submitGatedUntilBundleComplete() async throws {
        // RED: KYCReviewViewModel is implemented in plan 05-06.
        #expect(Bool(false), "RED: KYCReviewViewModelTests — implemented in plan 05-06 (KYC-01)")
    }
}
