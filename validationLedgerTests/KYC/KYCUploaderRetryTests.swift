// validationLedgerTests/KYC/KYCUploaderRetryTests.swift
// Requirement: UPL-03 — chunk-upload retry with exponential backoff caps at 5 attempts.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-04.
//
// The KYCUploader retry path does not exist yet — this file compiles and the
// single @Test fails by design (Nyquist rule). Plan 05-04 replaces the RED
// placeholder with the real backoff assertion: a chunk that fails repeatedly,
// asserting the uploader stops after 5 attempts and surfaces a typed error.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — retry backoff caps at 5 attempts (UPL-03)", .serialized)
struct KYCUploaderRetryTests {

    @Test("UPL-03: a persistently-failing chunk stops retrying after 5 attempts")
    func backoffCapsAtFiveAttempts() async throws {
        // RED: KYCUploader retry/backoff path is implemented in plan 05-04.
        #expect(Bool(false), "RED: KYCUploaderRetryTests — implemented in plan 05-04 (UPL-03)")
    }
}
