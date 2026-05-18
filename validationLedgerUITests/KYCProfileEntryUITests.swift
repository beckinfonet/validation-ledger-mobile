// validationLedgerUITests/KYCProfileEntryUITests.swift
// Phase 5 Plan 12 Task 1 (D-08) — device XCUITest that automates HUMAN-UAT item 3:
// the live Profile tap-through into the KYC status screen.
//
// Launch contract (plan 05-11, DEBUG only):
//   -KYCTestSeedForUITest underReview → AppContainer.kycTestSeed seeds a synthetic
//   sessionToken + sessionRole(shipper) + a cached "verified" kycStatus that the
//   fail-closed SessionRestoreProbe routes to the role shell. (Plan 05-11
//   deviation: the probe only forwards a "verified" cached value to `.restored`;
//   the "Under Review" status COPY this test could observe is served by the
//   plan 05-09 `GET /kyc/status` mock route, not the cached Keychain string.)
//
// Flow under test:
//   role shell → tap nav-avatar (top-bar avatar) → Profile modal →
//   tap profile-kyc-status ("Verification status" row) → KYCStatusViewController.
//
// Why this is an XCUITest and not an in-process XCTest:
//   `KYCEndToEndIntegrationTests` covers the pipeline-level wiring (the
//   composition-root factory closure), but only a separate XCUITest driver
//   process can drive the LIVE tap-through — avatar tap, Profile modal present,
//   row tap — and assert KYCStatusViewController actually opened. That live
//   tap-through is the D-08 end-to-end proof.
//
// STACK-03: XCUITest stays on XCTest (Swift Testing does not support
// XCUIApplication). Mirrors RoleShellSmokeTests.swift / LimitedTrustBannerTests.swift.
//
// Warning 5: per-test executionTimeAllowance = 30s hard cap.

import XCTest

final class KYCProfileEntryUITests: XCTestCase {

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

    /// Look up the KYC-status heading across any element type. `kyc-status-heading`
    /// is a `UILabel` (KYCStatusViewController) which XCUITest normally maps to
    /// `.staticText`; the trait-agnostic query stays anchored to the stable
    /// accessibility identifier.
    private func statusHeadingQuery(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["kyc-status-heading"]
    }

    // MARK: - Tests

    /// D-08 (HUMAN-UAT item 3): from the role shell, tapping the Profile avatar
    /// then the "Verification status" row opens KYCStatusViewController.
    ///
    /// This is the automated equivalent of HUMAN-UAT item 3 — "in the role shell,
    /// tapping the Profile avatar opens Profile, which shows a 'Verification
    /// status' row that opens KYCStatusViewController". On open, that screen
    /// re-fetches `GET /kyc/status`, which the plan 05-09 mock route serves with
    /// an `under_review` verdict under the `.mock` network config the
    /// `-KYCTestSeedForUITest` seam forces.
    func testProfileVerificationStatusRowOpensKYCStatusScreen() {
        let app = launch(seed: "underReview")

        // Positive signal that we landed on the role shell — wait for the tab
        // bar rather than sleeping. "Loads" is the Shipper role's first tab
        // (the seed uses sessionRole = shipper). 10s covers the cold launch.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 10),
                      "underReview seed should land on the role shell (Shipper "
                      + "tab bar) on launch")

        // Tap the top-bar avatar (RoleCoordinator sets accessibilityIdentifier
        // "nav-avatar" on the navigation bar button item).
        let avatar = app.navigationBars.buttons["nav-avatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5),
                      "nav-avatar bar button should appear in the role shell")
        avatar.tap()

        // The Profile modal presents the "Verification status" row — shown only
        // because the composition root supplied the KYC status screen factory
        // for the role shell (ProfileViewController D-08 conditional).
        let statusRow = app.buttons["profile-kyc-status"]
        XCTAssertTrue(statusRow.waitForExistence(timeout: 5),
                      "D-08: the Profile 'Verification status' row "
                      + "(profile-kyc-status) should appear in the role-shell "
                      + "Profile modal")
        statusRow.tap()

        // D-08 proof: KYCStatusViewController opened. `kyc-status-heading` is the
        // heading label that screen renders — its appearance is the deterministic
        // XCUITest-observable signal that the status screen pushed.
        let statusHeading = statusHeadingQuery(app)
        XCTAssertTrue(statusHeading.waitForExistence(timeout: 5),
                      "D-08: tapping 'Verification status' must open "
                      + "KYCStatusViewController (kyc-status-heading visible)")
    }
}
