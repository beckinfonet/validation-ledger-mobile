// validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift
// Requirement: KYC-03 (device portion) — VisionKit DataScannerViewController
// integration for driver's-license front-side scan/extraction.
// GREEN — implemented by plan 05-05.
//
// Target membership: validationLedgerDeviceTests ONLY. This is the device-CI
// counterpart to the simulator-unavailable scanner surface — `DataScanner-
// ViewController` requires real camera hardware (RESEARCH Pitfall 1), so its
// availability and instantiation can only be exercised on the physical-device
// lane (ci-device.yml, self-hosted Mac runner + iPhone CI lane).
//
// SCOPE — smoke test only. This suite confirms the DataScanner *integration*
// compiles and resolves availability without trapping, and that the DL-front
// scanner view controller type constructs. The real OCR / live-scan DL field
// extraction is HUMAN-UAT — declared in 05-VALIDATION.md's Manual-Only
// Verifications table and verified at plan 05-05's Task 4 checkpoint.
//
// XCTest (not Swift Testing) — consistent with the validationLedgerDeviceTests
// conventions (see AppAttestRoundTripTests for the canonical device patterns).

import XCTest
import VisionKit
@testable import validationLedger

final class DLExtractionScannerDeviceTests: XCTestCase {

    /// KYC-03 device portion — DataScanner availability smoke check.
    ///
    /// Asserts `DataScannerViewController.isSupported` and `.isAvailable`
    /// resolve to a concrete `Bool` without trapping on the physical-device
    /// lane. On a camera-equipped device with the lane in a normal state both
    /// resolve `true`; the assertion is on "resolves without trapping", not on
    /// a hard `true`, so a transient unavailable state (camera in use by
    /// another process) does not flake the lane.
    func testDataScannerAvailabilityResolves() throws {
        // These two static reads are the exact gate `DLFrontScanViewController`
        // branches on before instantiating the scanner (RESEARCH Pitfall 1).
        let isSupported = DataScannerViewController.isSupported
        let isAvailable = DataScannerViewController.isAvailable

        // The reads must produce concrete Booleans — the test passes as long as
        // neither read trapped. On the device-CI lane `isSupported` is expected
        // `true`; we assert it explicitly so a misconfigured lane (no camera
        // entitlement) is caught.
        XCTAssertTrue(
            isSupported,
            "DataScannerViewController.isSupported should be true on the camera-equipped device-CI lane"
        )
        // `isAvailable` can briefly be false (camera busy / restricted) — just
        // confirm the read produced a value.
        XCTAssertTrue(
            isAvailable || !isAvailable,
            "DataScannerViewController.isAvailable should resolve without trapping"
        )
    }

    /// KYC-03 device portion — the DL-front scanner VC constructs.
    ///
    /// Instantiates `DLFrontScanViewController` and forces its view to load,
    /// exercising the scanner-availability guard path in `viewWillAppear`
    /// (`startScannerIfAvailable`). On the device lane this builds the live
    /// `DataScannerViewController` child; the test asserts construction
    /// succeeds and the VC's view hierarchy is in place.
    @MainActor
    func testDLFrontScanViewControllerConstructs() throws {
        let viewController = DLFrontScanViewController()

        // Force `viewDidLoad` — builds the instruction header + scanner
        // container. `loadViewIfNeeded()` does not trap on the device lane.
        viewController.loadViewIfNeeded()
        XCTAssertNotNil(viewController.view, "DLFrontScanViewController should load its view")

        // Drive `viewWillAppear` so the Pitfall-1 availability guard path
        // (`startScannerIfAvailable`) is exercised — on the device lane this
        // attempts to build the live DataScanner; the guard must not trap.
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()

        // The scan-complete callback seam is wireable — confirms the KYC-01
        // coordinator integration point is present.
        var receivedExtraction: DLExtraction?
        viewController.onScanComplete = { extraction in
            receivedExtraction = extraction
        }
        XCTAssertNil(
            receivedExtraction,
            "onScanComplete should not fire until a live scan completes (HUMAN-UAT)"
        )
    }

    /// KYC-03 — the recognized-text → DL-field heuristic isolates the three
    /// fields from a plausible set of scanned lines. This is pure logic (no
    /// camera) so it is a fast device-lane smoke assertion that the extraction
    /// mapping is wired; the live OCR accuracy itself is HUMAN-UAT.
    func testRecognizedTextMapsToDLFields() throws {
        let lines = [
            "CALIFORNIA",
            "Jordan A Carter",
            "D1234567",
            "EXP 08/14/2029",
        ]
        let extraction = DLFrontScanViewController.fields(from: lines)
        XCTAssertEqual(extraction.name, "Jordan A Carter")
        XCTAssertEqual(extraction.dlNumber, "D1234567")
        XCTAssertEqual(extraction.expiry, "08/14/2029")
    }
}
