// validationLedgerUITests/KYCCaptureLifecycleUITests.swift
// Phase 5 Plan 12 Task 3 (Test-10, lifecycle portion) — device XCUITest that
// automates ONLY the background/foreground portion of HUMAN-UAT item 5 / Test 10:
// backgrounding the app on a live capture screen and foregrounding it restores a
// working `AVCaptureSession` with a responsive shutter.
//
// === SCOPE — what this test DOES and DOES NOT cover ===
// COVERED: the app-lifecycle half of Test 10. `XCUIDevice.shared.press(.home)`
// backgrounds the app on the face-capture screen; `activate()` foregrounds it.
// The test then asserts the shutter (`kyc-face-shutter`) is hittable — proving the
// `AVCaptureSession` `didEnterBackground` / `willEnterForeground` observers
// (plan 05-10) tore down and restored a working session, and the shutter is not a
// dead control.
//
// NOT COVERED — REMAINS A HUMAN-UAT ITEM: the deliberate
// `AVCaptureSessionRuntimeError` injection. A real camera-hardware runtime fault
// cannot be forced on demand from an XCUITest — it is a live AVFoundation
// notification that fires only on genuine hardware failure. The runtime-error
// resilience path (the recoverable "The camera needs a moment. Try the photo
// again." cue with the shutter re-enabled) therefore STAYS a physical-device
// human-UAT item. A future reader must NOT assume Test 10 is fully automated by
// this file — only its background/foreground lifecycle portion is.
//
// === Device-only meaning, simulator-clean compile ===
// This test exercises a LIVE `AVCaptureSession`. It is meaningful only on the
// device CI lane — the iOS Simulator produces no camera frames, so the Vision
// face-quality gate never reaches `.readyToCapture` and the shutter stays
// disabled there. The file MUST still COMPILE cleanly under `build-for-testing`
// for the simulator destination so the device-lane test action (plan 05-13) can
// include it; it is simply not expected to pass on the simulator.
//
// Launch contract (plan 05-11, DEBUG only):
//   -KYCTestSeedForUITest nonVerified → routes to the KYC hard-gate flow
//   (KYCStartViewController); tapping `kyc-start-cta` enters the capture flow and
//   the face-capture screen is the first live-camera surface.
//
// STACK-03: XCUITest stays on XCTest (Swift Testing does not support
// XCUIApplication). Mirrors RoleShellSmokeTests.swift / LimitedTrustBannerTests.swift.
//
// Warning 5: per-test executionTimeAllowance = 30s hard cap.

import XCTest

final class KYCCaptureLifecycleUITests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Warning 5: 30s hard cap per test (matches the Phase 3/4 smoke tests).
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launch the app under a `-KYCTestSeedForUITest` mode (plan 05-11 DEBUG seam).
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KYCTestSeedForUITest", seed]
        app.launch()
        return app
    }

    /// Look up the face-capture preview across any element type. `kyc-face-preview`
    /// is the camera preview view (FaceCaptureViewController); the trait-agnostic
    /// query stays anchored to the stable accessibility identifier.
    private func facePreviewQuery(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["kyc-face-preview"]
    }

    // MARK: - Tests

    /// Test 10 (lifecycle portion of HUMAN-UAT item 5): backgrounding the app on
    /// the face-capture screen and foregrounding it restores a live capture
    /// session with a responsive shutter.
    func testBackgroundThenForegroundRestoresLiveCaptureSession() {
        // 1. Launch into the KYC hard-gate flow (KYCStartViewController).
        let app = launch(seed: "nonVerified")

        let startCTA = app.buttons["kyc-start-cta"]
        XCTAssertTrue(startCTA.waitForExistence(timeout: 10),
                      "nonVerified seed should land on the KYC hard-gate "
                      + "(kyc-start-cta) on launch")

        // 2. Enter the capture flow. The face-capture screen is the first
        //    live-camera surface reached from the gate.
        startCTA.tap()
        let facePreview = facePreviewQuery(app)
        XCTAssertTrue(facePreview.waitForExistence(timeout: 10),
                      "tapping kyc-start-cta should reach the face-capture screen "
                      + "(kyc-face-preview)")

        // 3. Background the app — a real OS suspension on a live capture screen.
        XCUIDevice.shared.press(.home)

        // 4. Foreground the app WITHOUT relaunching — `activate()` re-activates
        //    the suspended process, exercising the willEnterForeground observers.
        app.activate()

        // 5. Assert the capture screen is restored and the session is live. The
        //    preview view must still exist, and the shutter must be hittable —
        //    proving the plan 05-10 AVCaptureSession background/foreground
        //    observers restored a working session rather than leaving a dead
        //    shutter on a half-torn-down session.
        XCTAssertTrue(facePreview.waitForExistence(timeout: 5),
                      "Test 10: the face-capture screen must be restored after "
                      + "background → foreground")
        let shutter = app.buttons["kyc-face-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5),
                      "Test 10: the shutter (kyc-face-shutter) must exist after "
                      + "foreground")
        XCTAssertTrue(shutter.isHittable,
                      "Test 10: the shutter must be hittable after background → "
                      + "foreground — proving the AVCaptureSession observers "
                      + "(plan 05-10) restored a working session, not a dead "
                      + "shutter. (Device lane only — the simulator produces no "
                      + "camera frames.)")
    }
}
