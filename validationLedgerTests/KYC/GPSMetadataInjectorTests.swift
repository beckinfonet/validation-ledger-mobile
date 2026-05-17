// validationLedgerTests/KYC/GPSMetadataInjectorTests.swift
// Requirement: KYC-04 / SC-1 — GPS EXIF metadata is injected into captured artifacts.
// RED scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-03.
//
// The GPSMetadataInjector production type does not exist yet — this file compiles
// and the single @Test fails by design (Nyquist rule). Plan 05-03 replaces the RED
// placeholder with the real round-trip assertion: a known lat/lon is injected into
// image EXIF, then re-read back from the produced data and compared.

import Testing
import Foundation
@testable import validationLedger

@Suite("GPSMetadataInjector — EXIF GPS round-trip (KYC-04 / SC-1)")
struct GPSMetadataInjectorTests {

    @Test("KYC-04 / SC-1: an injected GPS value round-trips through EXIF")
    func gpsValueRoundTrips() async throws {
        // RED: GPSMetadataInjector is implemented in plan 05-03.
        #expect(Bool(false), "RED: GPSMetadataInjectorTests — implemented in plan 05-03 (KYC-04 / SC-1)")
    }
}
