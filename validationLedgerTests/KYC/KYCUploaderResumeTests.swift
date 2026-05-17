// validationLedgerTests/KYC/KYCUploaderResumeTests.swift
// Requirement: UPL-02 / SC-2 — resumable upload survives a simulated force-quit.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-04.
//
// The KYCUploader resume path does not exist yet — this file compiles and the
// single @Test fails by design (Nyquist rule). Plan 05-04 replaces the RED
// placeholder with the real resume assertion: a partially-acked upload, an
// interrupted process, then a fresh KYCUploader continuing from the last acked chunk.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — force-quit resume (UPL-02 / SC-2)", .serialized)
struct KYCUploaderResumeTests {

    @Test("UPL-02 / SC-2: a simulated force-quit resumes from the last acked chunk")
    func resumesFromLastAckedChunk() async throws {
        // RED: KYCUploader resume path is implemented in plan 05-04.
        #expect(Bool(false), "RED: KYCUploaderResumeTests — implemented in plan 05-04 (UPL-02 / SC-2)")
    }
}
