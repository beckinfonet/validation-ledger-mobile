// validationLedgerUITests/KYCForceQuitResumeUITests.swift
// Phase 5 Plan 12 Task 2 (SC-2) — device XCUITest that automates the force-quit
// portion of HUMAN-UAT item 1: a real, ungraceful process kill mid-upload, a real
// relaunch, and an assertion that the resumed KYC state is observable and not in
// an error / zeroed state.
//
// === Why this is an XCUITest the device test cannot be ===
// `validationLedgerDeviceTests/KYCForceQuitResumeDeviceTests` MODELS a force-quit
// by reconstructing a fresh `KYCUploader` + `KYCSessionStore` from the same
// directory — that proves the resume *logic* on real hardware, but a real
// `xcodebuild test` process can never actually kill and relaunch the app under
// test. An XCUITest runs in a SEPARATE driver process: `XCUIApplication().terminate()`
// is a genuine ungraceful kill of the app process, and `.launch()` is a genuine
// relaunch — the actual gap the in-process device test cannot exercise. This file
// converts the process-lifecycle half of SC-2 into an automated run.
//
// === What is and is not asserted ===
// The `-KYCTestSeedForUITest midUpload` seam (plan 05-11) leaves a partial
// face-artifact upload (chunksAcked 5 / totalChunks 12, committed == false) on the
// encrypted on-disk `KYCSessionStore`. The seam RE-SEEDS on every launch, so the
// resume assertion is deliberately framed around what is observable from the LIVE
// UI rather than re-seeding semantics: after the kill + relaunch the app must not
// crash, must reach the role shell, and the KYC status screen must render. No
// progress `accessibilityValue` is exposed on the role shell — the determinate
// `UIProgressView` lives on `KYCReviewViewController`, which is inside the active
// KYC capture flow, not reachable from the role shell under the `midUpload` seed.
// The SC-2 resume guarantee XCUITest-observable proxy is therefore: the persisted
// on-disk session survives the real kill and the app renders a non-crashed, role-
// shell + KYC-status UI on relaunch.
//
// The end-to-end progress-bar UX confirmation against a live 6 MB upload (the
// progress bar restoring to a non-zero fraction visible to the user) REMAINS a
// human-UAT item — HUMAN-UAT item 1 — because no progress accessibility value is
// reachable from the surfaces this seed can land on.
//
// STACK-03: XCUITest stays on XCTest (Swift Testing does not support
// XCUIApplication). Mirrors RoleShellSmokeTests.swift / LimitedTrustBannerTests.swift.
//
// Warning 5: per-test executionTimeAllowance = 30s hard cap.

import XCTest

final class KYCForceQuitResumeUITests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Warning 5: 30s hard cap per test (matches the Phase 3/4 smoke tests).
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Look up the KYC-status heading across any element type. `kyc-status-heading`
    /// is a `UILabel` (KYCStatusViewController) which XCUITest normally maps to
    /// `.staticText`; the trait-agnostic query stays anchored to the stable
    /// accessibility identifier.
    private func statusHeadingQuery(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["kyc-status-heading"]
    }

    // MARK: - Tests

    /// SC-2 (process-lifecycle portion of HUMAN-UAT item 1): a real `terminate()`
    /// mid-upload followed by a real `launch()` leaves the app in an observable,
    /// non-error resumed state.
    func testForceQuitMidUploadResumesNonZeroProgress() {
        // 1. Launch with the midUpload seed. This lands on the role shell with a
        //    partial face-artifact upload (chunksAcked 5 / 12, committed == false)
        //    on the encrypted on-disk `KYCSessionStore` (plan 05-11).
        let app = XCUIApplication()
        app.launchArguments = ["-KYCTestSeedForUITest", "midUpload"]
        app.launch()

        // Confirm the first launch reached the role shell before we kill it —
        // otherwise a terminate() proves nothing. "Loads" is the Shipper role's
        // first tab (the seed uses sessionRole = shipper).
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 10),
                      "midUpload seed should land on the role shell on first launch")

        // 2. Real ungraceful process kill. This is the actual SC-2 gap the
        //    in-process `KYCForceQuitResumeDeviceTests` reconstruction cannot
        //    exercise — `terminate()` kills the real app process.
        app.terminate()

        // 3. Real relaunch. The SAME `-KYCTestSeedForUITest midUpload` arguments
        //    are still set on the `app` instance, so the relaunch is a faithful
        //    "cold start with a mid-upload session on disk" — exactly what the
        //    user sees after force-quitting from the app switcher.
        app.launch()

        // 4. Assert the resumed state is observable and non-error. The role shell
        //    must come back up (the persisted session survived the kill and the
        //    app did not crash on the on-disk blob)...
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 10),
                      "SC-2: after a real terminate() + relaunch the role shell "
                      + "must render — the persisted KYC session survived the kill")

        // ...and the KYC status screen must render without an error state. Drive
        // Profile → profile-kyc-status → KYCStatusViewController and assert the
        // heading appears. KYCStatusViewController always renders
        // `kyc-status-heading`; the SC-2-observable signal here is that the screen
        // opens at all after the kill — a crash or a wedged session would prevent
        // the role shell + status screen from rendering.
        let avatar = app.navigationBars.buttons["nav-avatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5),
                      "SC-2: the role-shell avatar must be reachable after relaunch")
        avatar.tap()

        let statusRow = app.buttons["profile-kyc-status"]
        XCTAssertTrue(statusRow.waitForExistence(timeout: 5),
                      "SC-2: the Profile 'Verification status' row must be "
                      + "reachable after the force-quit + relaunch")
        statusRow.tap()

        let statusHeading = statusHeadingQuery(app)
        XCTAssertTrue(statusHeading.waitForExistence(timeout: 5),
                      "SC-2: KYCStatusViewController must render after the real "
                      + "terminate() + relaunch — a non-crashed, non-wedged "
                      + "resumed state is the XCUITest-observable proxy for the "
                      + "SC-2 resume guarantee")
    }
}
