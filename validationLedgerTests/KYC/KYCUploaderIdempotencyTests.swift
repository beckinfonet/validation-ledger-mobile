// validationLedgerTests/KYC/KYCUploaderIdempotencyTests.swift
// Requirement: SC-5 — no duplicate chunk commits under replay.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-04.
//
// The KYCUploader per-chunk idempotency path does not exist yet — this file
// compiles and the single @Test fails by design (Nyquist rule). Plan 05-04
// replaces the RED placeholder with the real idempotency assertion: MockURLProtocol
// counts requests per chunk index and asserts the same Idempotency-Key is reused
// across retries so the backend dedupes — no duplicate commit per chunk.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — per-chunk idempotency, no duplicate commits (SC-5)", .serialized)
struct KYCUploaderIdempotencyTests {

    @Test("SC-5: a retried chunk reuses its Idempotency-Key — no duplicate commit")
    func retriedChunkReusesIdempotencyKey() async throws {
        // RED: KYCUploader per-chunk idempotency is implemented in plan 05-04.
        #expect(Bool(false), "RED: KYCUploaderIdempotencyTests — implemented in plan 05-04 (SC-5)")
    }
}
