// validationLedgerTests/KYC/KYCUploaderProgressTests.swift
// Requirement: UPL-04 — visible upload progress advances per chunk ack.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-04.
//
// The KYCUploader progress reporting does not exist yet — this file compiles and
// the single @Test fails by design (Nyquist rule). Plan 05-04 replaces the RED
// placeholder with the real progress assertion: progress is monotonic and reaches
// 1.0 only after the commit step, advancing one fraction per acked chunk.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — progress advances per chunk ack (UPL-04)", .serialized)
struct KYCUploaderProgressTests {

    @Test("UPL-04: progress advances monotonically, one step per acked chunk")
    func progressAdvancesPerChunkAck() async throws {
        // RED: KYCUploader progress reporting is implemented in plan 05-04.
        #expect(Bool(false), "RED: KYCUploaderProgressTests — implemented in plan 05-04 (UPL-04)")
    }
}
