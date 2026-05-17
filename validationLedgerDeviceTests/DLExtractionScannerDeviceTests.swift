// validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift
// Requirement: KYC-03 (device portion) — VisionKit DataScannerViewController integration
// for driver's-license front-side scan/extraction.
// RED device-test scaffold (Wave 0 / plan 05-01). Turned GREEN by plan 05-05.
//
// Target membership: validationLedgerDeviceTests ONLY. This is the device-CI counterpart
// to the simulator-unavailable scanner surface — `DataScannerViewController` requires real
// camera hardware, so its availability and instantiation can only be exercised on the
// physical-device lane (ci-device.yml, self-hosted Mac runner + iPhone 16). The real OCR /
// live-scan DL extraction is routed to HUMAN-UAT in plan 05-05's checkpoint, as declared in
// 05-VALIDATION.md's Manual-Only Verifications table.
//
// XCTest (not Swift Testing) — consistent with the validationLedgerDeviceTests conventions
// (see AppAttestRoundTripTests for the canonical device-test patterns).

import XCTest
import VisionKit
@testable import validationLedger

final class DLExtractionScannerDeviceTests: XCTestCase {

    // KYC-03 device portion — GREEN delivered in plan 05-05.
    func testDataScannerViewControllerSmoke() throws {
        // RED: DataScannerViewController DL-front integration is implemented in plan 05.
        // The GREEN version asserts DataScannerViewController.isSupported /
        // .isAvailable resolve without trapping on the physical-device lane, and that
        // the DL-front scanner view controller type instantiates.
        XCTFail("RED: DLExtractionScannerDeviceTests — DataScannerViewController smoke test implemented in plan 05")
    }
}
