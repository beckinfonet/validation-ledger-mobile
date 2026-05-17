// validationLedgerTests/KYC/RejectionReasonCodeTests.swift
// Requirement: D-11 — rejection reason code → human copy mapping + unknown-code fallback.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-02.
//
// The RejectionReasonCode production type does not exist yet — this file compiles
// and the single @Test fails by design (Nyquist rule). Plan 05-02 replaces the RED
// placeholder with the real mapping assertion: known backend codes (dl_front_glare,
// face_not_centered, ...) map to iOS-owned copy, and an unknown code falls back to a
// safe generic message rather than crashing or showing the raw code.

import Testing
import Foundation
@testable import validationLedger

@Suite("RejectionReasonCode — code→copy mapping + unknown fallback (D-11)")
struct RejectionReasonCodeTests {

    @Test("D-11: known codes map to copy; an unknown code falls back to a generic message")
    func codeMapsToCopyWithUnknownFallback() async throws {
        // RED: RejectionReasonCode is implemented in plan 05-02.
        #expect(Bool(false), "RED: RejectionReasonCodeTests — implemented in plan 05-02 (D-11)")
    }
}
