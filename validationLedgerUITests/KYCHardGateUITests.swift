// validationLedgerUITests/KYCHardGateUITests.swift
// Phase 5 Plan 12 Task 1 (D-12) — device XCUITest that automates HUMAN-UAT item 4:
// a non-verified account CANNOT reach the role shell; it is hard-gated into the
// KYC flow.
//
// Launch contract (plan 05-11, DEBUG only):
//   -KYCTestSeedForUITest nonVerified → AppContainer.kycTestSeed seeds a synthetic
//   sessionToken + sessionRole(shipper) + cached kycStatus "pending"; the real
//   SessionRestoreProbe then resolves `.needsKYC` and SceneDelegate routes to
//   `presentRoot(.kyc(role))` — i.e. KYCCoordinator / KYCStartViewController, never
//   the role tab bar.
//
// Why this is an XCUITest and not an in-process XCTest:
//   `validationLedgerDeviceTests` (in-process) can prove SessionRestoreProbe's
//   routing *logic*, but only a separate XCUITest driver process can launch the
//   real app and assert on the LIVE UI tree — that the role tab bar element was
//   never even constructed. That live "no tab bar exists" assertion is the D-12
//   end-to-end proof.
//
// STACK-03: XCUITest stays on XCTest (Swift Testing does not support
// XCUIApplication). Mirrors RoleShellSmokeTests.swift / LimitedTrustBannerTests.swift.
//
// Warning 5: per-test executionTimeAllowance = 30s hard cap.

import XCTest

final class KYCHardGateUITests: XCTestCase {

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

    /// Look up the KYC-start heading across any element type. `kyc-start-heading`
    /// is a `UILabel` (KYCStartViewController) which XCUITest normally maps to
    /// `.staticText`; the trait-agnostic `descendants(matching: .any)` query stays
    /// anchored to the stable accessibility identifier and is robust if the element
    /// type ever shifts.
    private func startHeadingQuery(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["kyc-start-heading"]
    }

    // MARK: - Tests

    /// D-12 (HUMAN-UAT item 4): a non-verified account is hard-gated out of the
    /// role shell and lands on the KYC flow.
    ///
    /// This is the automated equivalent of HUMAN-UAT item 4 — "after OTP-verify on
    /// a non-verified account, the app lands in the KYC flow (KYCCoordinator), not
    /// the role tab bar".
    func testNonVerifiedAccountIsGatedFromRoleShell() {
        let app = launch(seed: "nonVerified")

        // Positive signal: the KYC hard-gate screen (KYCStartViewController) is
        // what `presentRoot(.kyc(role))` mounts. 10s covers the cold launch.
        let startHeading = startHeadingQuery(app)
        XCTAssertTrue(startHeading.waitForExistence(timeout: 10),
                      "D-12: a non-verified account must land on the KYC hard-gate "
                      + "screen (kyc-start-heading) on launch")

        // D-12 negative signal: the role tab bar must NOT exist. A non-verified
        // account routing to `.kyc` means RoleCoordinator / the role tab-bar
        // controller was never constructed — so NONE of the TechStack §4 role
        // tabs can be present. "Loads" is the shared first tab of 4 of the 5
        // roles; "Invoices" is the Factoring equivalent. Asserting both are
        // absent proves no role shell was built for any role.
        XCTAssertFalse(app.tabBars.buttons["Loads"].exists,
                       "D-12: the role tab bar must be absent — a non-verified "
                       + "account must not reach the role shell")
        XCTAssertFalse(app.tabBars.buttons["Invoices"].exists,
                       "D-12: the Factoring role tab must also be absent — the "
                       + "hard gate blocks every role")
        XCTAssertEqual(app.tabBars.count, 0,
                       "D-12: no tab bar of any kind should exist on the KYC hard "
                       + "gate — the role shell was never constructed")
    }
}
