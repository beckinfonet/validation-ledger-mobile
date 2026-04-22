// validationLedgerUITests/RoleShellSmokeTests.swift
// Phase 3 D-32 / SC-1: 5 role smoke tests driving the full OTP → role shell → logout
// cycle via -MockOTPRoleForUITest <role> launchArg.
//
// Pattern per role:
//   launch → phone-entry visible → type 5551234567 → Submit → OTP screen visible
//     → type 123456 → Verify → role tab bar appears with TechStack §4 tabs
//     → tap nav-avatar → ProfileVC modal → tap profile-logout → returns to phone-entry
//
// STACK-03: XCUITest retained on XCTest (NOT Swift Testing). Swift Testing does not
// support XCUIApplication — UI tests must stay on XCTest.
//
// Warning 5: per-test executionTimeAllowance = 30s hard cap to prevent a hung test
// from cascading the whole suite. Individual waitForExistence timeouts are 5s for
// mock-backed screens (MockURLProtocol returns synchronously) except the initial
// cold-launch which uses 10s.
//
// Fixture environment: SceneDelegate's -MockOTPRoleForUITest handler (Plan 12 Task 1):
//   - registers MockURLProtocol fixtures via MockOTPRoleFixtureRegistry.registerForRole
//   - installs StubLocationProviderForUITest + StubCountryGateForUITest (Warning 4)
//   - forces .mock NetworkConfig so MockURLProtocol intercepts
//   - wipes session-scope Keychain (T-03-12-04 — clean state per test)
//   - presentRoot(.auth) — lands on phone-entry for the UI test to drive

import XCTest

final class RoleShellSmokeTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Warning 5: 30s hard cap per test. Expected per-test runtime is ~20-25s.
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MockOTPRoleForUITest", role]
        app.launch()
        return app
    }

    /// Drives phone-entry → Submit → OTP entry → Verify. After this returns, the
    /// role tab bar is visible (or will be shortly — per-role assertions follow).
    private func driveFullOTPFlow(_ app: XCUIApplication) {
        // Phone entry — initial cold-launch wait; 10s is generous for first paint.
        let phoneField = app.textFields["phone-entry-field"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10),
                      "Phone entry field should appear on cold launch")
        phoneField.tap()
        phoneField.typeText("5551234567")

        // Submit-enable wait: geo gate uses StubLocationProviderForUITest +
        // StubCountryGateForUITest (no real CLLocationManager prompt or
        // CLGeocoder network call — synchronous success). 5s cap covers the
        // 10-digit input evaluation + submitEnabled didSet fan-out.
        let submit = app.buttons["phone-entry-submit"]
        let submitEnabled = NSPredicate(format: "isEnabled == true")
        expectation(for: submitEnabled, evaluatedWith: submit, handler: nil)
        waitForExpectations(timeout: 5)
        submit.tap()

        // OTP entry — Warning 5: 5s cap for mock-backed transition.
        // MockURLProtocol returns the OTPRequest fixture synchronously; screen
        // transition is the only real delay.
        let otpField = app.textFields["otp-field"]
        XCTAssertTrue(otpField.waitForExistence(timeout: 5),
                      "OTP field should appear after phone submit (mock-backed — 5s cap)")
        otpField.tap()
        otpField.typeText("123456")
        app.buttons["otp-verify"].tap()
    }

    /// After role tab bar assertions, exercise avatar tap → Profile modal → Log out
    /// → return to phone entry.
    private func assertProfileFlowAndLogout(_ app: XCUIApplication) {
        // Avatar — role-shell mounted; nav bar should appear within 5s.
        let avatar = app.navigationBars.buttons["nav-avatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5),
                      "Avatar bar button should appear in role shell (mock-backed — 5s cap)")
        avatar.tap()

        // Profile modal — Logout button.
        let logout = app.buttons["profile-logout"]
        XCTAssertTrue(logout.waitForExistence(timeout: 5),
                      "Profile logout button should appear in modal")
        logout.tap()

        // Returns to phone entry — Warning 5: 5s cap (logout funnel is
        // synchronous/async with no network; SceneDelegate observer root-swaps
        // the moment LogoutService posts .sessionDidInvalidate).
        let phoneField = app.textFields["phone-entry-field"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 5),
                      "Should return to phone entry after logout (mock-backed — 5s cap)")
    }

    // MARK: - 5 role smoke tests (TechStack §4 verbatim tab inventory)

    func testShipperFullFlow() {
        let app = launch(role: "shipper")
        driveFullOTPFlow(app)
        // TechStack §4 Shipper: Loads, Brokers, BOL, Assistant
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Brokers"].exists)
        XCTAssertTrue(app.tabBars.buttons["BOL"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
        assertProfileFlowAndLogout(app)
    }

    func testBrokerFullFlow() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)
        // TechStack §4 Broker: Loads, Carriers, Network, Assistant
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Carriers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Network"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
        assertProfileFlowAndLogout(app)
    }

    func testCarrierFullFlow() {
        let app = launch(role: "carrier")
        driveFullOTPFlow(app)
        // TechStack §4 Carrier: Loads, Drivers, Documents, Assistant
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Drivers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Documents"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
        assertProfileFlowAndLogout(app)
    }

    func testDispatchFullFlow() {
        let app = launch(role: "dispatch")
        driveFullOTPFlow(app)
        // TechStack §4 Dispatch: Loads, Fleet, Drivers, Assistant
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Fleet"].exists)
        XCTAssertTrue(app.tabBars.buttons["Drivers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
        assertProfileFlowAndLogout(app)
    }

    func testFactoringFullFlow() {
        let app = launch(role: "factoring")
        driveFullOTPFlow(app)
        // TechStack §4 Factoring: Invoices, Carriers, Chain, Assistant
        XCTAssertTrue(app.tabBars.buttons["Invoices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Carriers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Chain"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
        assertProfileFlowAndLogout(app)
    }
}
