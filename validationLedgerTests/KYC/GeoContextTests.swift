// validationLedgerTests/KYC/GeoContextTests.swift
// Requirement: Pitfall 5 — GPS freshness/accuracy gate for capture-time geo context.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-03.
//
// The GeoContext production type does not exist yet — this file compiles and the
// single @Test fails by design (Nyquist rule). Plan 05-03 replaces the RED
// placeholder with the real gate assertion: a stale or low-accuracy location is
// rejected as unfit for EXIF injection; only a fresh, sufficiently-accurate fix passes.

import Testing
import Foundation
@testable import validationLedger

@Suite("GeoContext — freshness/accuracy gate (Pitfall 5)")
struct GeoContextTests {

    @Test("Pitfall 5: a stale or low-accuracy fix is rejected; a fresh accurate fix passes")
    func stalenessAndAccuracyGate() async throws {
        // RED: GeoContext is implemented in plan 05-03.
        #expect(Bool(false), "RED: GeoContextTests — implemented in plan 05-03 (Pitfall 5)")
    }
}
