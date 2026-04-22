// validationLedgerUITests/LimitedTrustBannerTests.swift
// Phase 4 Plan 08 (DEV-04 / D-11 / D-12) — XCUITest smoke coverage for the
// LimitedTrustBanner. Drives the full OTP flow under two -MockOTPTrustTierForUITest
// launchArg variants:
//   - softwareOnly    → banner MUST be visible above the tab bar + non-hittable.
//   - hardwareAttested → banner MUST be absent.
//
// Launch-arg plumbing (Plan 08 Task 3 Step A + SceneDelegate handler):
//   1. SceneDelegate parses -MockOTPTrustTierForUITest into a TrustTier.
//   2. MockOTPRoleFixtureRegistry.registerForRole(role, trustTier:) emits the
//      matching `trust_tier` field in the /device/register response.
//   3. AppContainer.uiTestTrustTierOverride seeds AppSession.trustTier at
//      construction so the banner wrap decision in AppCoordinator hits the
//      correct branch without waiting for a post-register mutation (wiring
//      the real response → session.trustTier mutation is Plan 07 scope).
//
// STACK-03: XCUITest stays on XCTest (Swift Testing does not support
// XCUIApplication). Matches Phase 3 Plan 12 RoleShellSmokeTests.
//
// Warning 5: per-test executionTimeAllowance = 30s (matches Phase 3 cap).

import XCTest

final class LimitedTrustBannerTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launch with a role + trustTier launch-arg pair.
    private func launch(role: String, trustTier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-MockOTPRoleForUITest", role,
            "-MockOTPTrustTierForUITest", trustTier,
        ]
        app.launch()
        return app
    }

    /// Drives phone-entry → Submit → OTP entry → Verify. After this returns,
    /// the role tab bar (and banner, if applicable) is rendering. Mirrors the
    /// helper in RoleShellSmokeTests.swift (Phase 3 Plan 12).
    private func driveFullOTPFlow(_ app: XCUIApplication) {
        let phoneField = app.textFields["phone-entry-field"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10),
                      "Phone entry field should appear on cold launch")
        phoneField.tap()
        phoneField.typeText("5551234567")

        let submit = app.buttons["phone-entry-submit"]
        let submitEnabled = NSPredicate(format: "isEnabled == true")
        expectation(for: submitEnabled, evaluatedWith: submit, handler: nil)
        waitForExpectations(timeout: 5)
        submit.tap()

        let otpField = app.textFields["otp-field"]
        XCTAssertTrue(otpField.waitForExistence(timeout: 5),
                      "OTP field should appear after phone submit (mock-backed — 5s cap)")
        otpField.tap()
        otpField.typeText("123456")
        app.buttons["otp-verify"].tap()
    }

    // MARK: - Tests

    /// Look up the banner by accessibilityIdentifier across any element type.
    ///
    /// LimitedTrustBannerView sets `accessibilityTraits = .staticText` AND
    /// `isAccessibilityElement = true`, which makes XCUITest map the element to
    /// `.staticText` (not `.other`). Querying `app.descendants(matching: .any)`
    /// by identifier is trait-agnostic and robust against future trait
    /// adjustments while staying anchored to the stable
    /// `accessibilityIdentifier = "limited-trust-banner"` locator.
    private func bannerQuery(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["limited-trust-banner"]
    }

    /// D-11 / T-APP-ATTEST-11: when trustTier = .softwareOnly the LimitedTrustBanner
    /// MUST render above the tab bar AND be non-dismissible (isHittable == false
    /// because LimitedTrustBannerView has isUserInteractionEnabled = false).
    func testBannerVisibleWhenTrustTierIsSoftwareOnly() {
        let app = launch(role: "shipper", trustTier: "softwareOnly")
        driveFullOTPFlow(app)

        // The role shell should render; tab bar is the positive signal that we
        // have landed past OTP (mirrors RoleShellSmokeTests).
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "Role tab bar should appear after OTP verify (mock-backed — 5s cap)")

        // D-11: banner identifier is "limited-trust-banner" (LimitedTrustBannerView
        // setUp). Use waitForExistence rather than .exists because banner install
        // may race with the tab bar mount by a frame.
        let banner = bannerQuery(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5),
                      "D-11: LimitedTrustBanner MUST be visible when trustTier = .softwareOnly")

        // D-11 / T-APP-ATTEST-11 non-dismissibility — XCUITest-observable proxies:
        //   1. Element type is .staticText (LimitedTrustBannerView sets
        //      `accessibilityTraits = .staticText`). A .staticText element has no
        //      tap-fires-action semantics; there is no gesture for the user to
        //      invoke. This is the structural non-dismissibility invariant.
        //   2. No dismiss button exists inside the banner (scoped query: the
        //      banner's `otherElements.matching(.button)` must return zero).
        //      Defence-in-depth against a future edit that adds a dismiss control.
        //
        // Note: we intentionally do NOT assert `banner.isHittable == false`.
        // XCUITest's `isHittable` is a VoiceOver/automation reachability query;
        // it returns true for any on-screen accessibility element regardless of
        // `isUserInteractionEnabled`. UIKit-layer touch blocking is enforced at
        // the view (`isUserInteractionEnabled = false`) and verified in unit
        // tests / human checkpoint (Task 4 swipe-tap evaluation); XCUITest
        // observes only the accessibility runtime.
        XCTAssertEqual(banner.elementType, .staticText,
                       "D-11: banner trait must be .staticText (no interactive semantics)")
        XCTAssertEqual(banner.buttons.count, 0,
                       "D-11: banner must contain no dismiss buttons (non-dismissibility defence-in-depth)")
    }

    /// D-12: when trustTier = .hardwareAttested the banner MUST be absent
    /// (RoleCoordinator.wrapWithLimitedTrustBanner returns self unchanged).
    func testBannerHiddenWhenTrustTierIsHardwareAttested() {
        let app = launch(role: "shipper", trustTier: "hardwareAttested")
        driveFullOTPFlow(app)

        // Positive signal that we landed on the role shell — wait for the tab
        // bar rather than sleeping, to avoid racing with the mount.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "Role tab bar should appear after OTP verify (mock-backed — 5s cap)")

        // D-12: banner MUST NOT exist on the hardwareAttested path.
        let banner = bannerQuery(app)
        XCTAssertFalse(banner.exists,
                       "D-12: LimitedTrustBanner MUST be absent when trustTier = .hardwareAttested")
    }
}
