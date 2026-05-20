// validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift
// Phase 8 LOAD-03 (Plan 04 integration cap): the 5-role smoke flow that
// proves each role's tab shell renders the real Loads tab post-OTP. Drives
// the same `-MockOTPRoleForUITest <role>` launch-arg path that
// `RoleShellSmokeTests` uses, then taps the Loads (Invoices on Factoring)
// tab and asserts:
//   1. `loads-list` collection-view accessibility identifier resolves.
//   2. At least one `loads-list.row.VL-*` row identifier resolves from the
//      role-appropriate populated fixture (T-08-11 — proves the role flows
//      end-to-end through loadListScreenFactory?(self.role) into
//      LoadListEndpoint(role:) into the per-role fixture lookup).
//
// This file does NOT duplicate the tab-button existence assertions from
// `RoleShellSmokeTests` — those stay in `RoleShellSmokeTests`. This file
// extends the smoke flow by tapping INTO the Loads/Invoices tab.
//
// STACK-03: XCUITest is XCTest, not Swift Testing — `XCUIApplication` does
// not bridge to Swift Testing in iOS 17.
//
// Empty-state probe — DEFERRED. The `-MockOTPRoleForUITest <role>` path
// serves the populated `loads-list-{role}.json` fixture for every role (via
// `MockLoadFixtureRegistry.registerAppDefaults()` appended onto the
// MockURLProtocol handler chain by `MockOTPRoleFixtureRegistry.registerForRole`,
// see Plan 04 Task 3's fixture-registry extension). There is no organic role
// launch path that lands on the empty fixture. The empty-state UNIT test
// `Test_loadingToEmptyOnEmptyFixture` in Plan 03 Task 2's
// `LoadListViewModelTests.swift` covers the LOAD-07 empty-state contract;
// a future plan can add an `-MockEmptyLoadsForUITest <role>` launch arg to
// swap in the empty fixture and add an `loads-list.empty-state`
// identifier-resolution XCUITest.
//
// Warning 5 — per-test executionTimeAllowance = 30s hard cap to prevent a
// hung test from cascading the suite. Mock-backed transitions use a 5s
// waitForExistence cap; the initial cold-launch uses 10s.

import XCTest

final class RoleLoadsTabSmokeTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        // Warning 5: 30s hard cap per test. Expected per-test runtime is ~15–20s.
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers (mirror RoleShellSmokeTests verbatim)

    private func launch(role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MockOTPRoleForUITest", role]
        app.launch()
        return app
    }

    /// Drives phone-entry → Submit → OTP entry → Verify. After this returns,
    /// the role tab bar is visible (or will be shortly — per-role assertions
    /// follow). Mirrors `RoleShellSmokeTests.driveFullOTPFlow(_:)` verbatim.
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
        let otpField = app.textFields["otp-field"]
        XCTAssertTrue(otpField.waitForExistence(timeout: 5),
                      "OTP field should appear after phone submit (mock-backed — 5s cap)")
        otpField.tap()
        otpField.typeText("123456")
        app.buttons["otp-verify"].tap()
    }

    /// Shared per-role assertion body. Taps the Loads/Invoices tab and
    /// asserts the locked Phase 8 accessibility identifiers resolve on the
    /// role-appropriate populated fixture (Plan 01 D-04 + Plan 03 cell
    /// identifier `loads-list.row.\(load.id)` where every fixture row carries
    /// a `VL-`-prefixed `load.id`).
    private func assertLoadsTabResolvesList(
        _ app: XCUIApplication,
        tabName: String,
        role: String
    ) {
        // 1. Wait for the tab bar to render with the expected tab.
        XCTAssertTrue(app.tabBars.buttons[tabName].waitForExistence(timeout: 5),
                      "\(role) tab bar should render with a '\(tabName)' tab after OTP verify")

        // 2. Tap the tab.
        app.tabBars.buttons[tabName].tap()

        // 3. Assert the `loads-list` collection view resolves.
        //    Every role's Loads tab is backed by `LoadListViewController`
        //    whose collection view has accessibilityIdentifier = "loads-list"
        //    (Plan 03 lock); the role does not change the identifier.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the \(tabName) tab")

        // 4. Assert at least one `loads-list.row.VL-*` row identifier resolves.
        //    The role's populated fixture (Plan 01 D-04) carries at least
        //    one `VL-`-prefixed `load.id`; each cell sets its own
        //    `accessibilityIdentifier = "loads-list.row.\(load.id)"`
        //    (Plan 03 LoadRowCell.configure). This assertion proves T-08-11
        //    end-to-end: the role flowed from `*TabBarController.role`
        //    through `loadListScreenFactory?(self.role)` into
        //    `LoadListViewModel(role:)` into `LoadListEndpoint(role:)` into
        //    the role-appropriate fixture file.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'loads-list.row.VL-'")
        let rows = app.cells.matching(predicate)
        XCTAssertGreaterThan(rows.count, 0,
                             "At least one loads-list.row.VL-* identifier should resolve from the populated \(role) fixture")

        // 5. BL-02 — assert the IN-SCREEN nav-bar title matches the tab-item
        //    title (T-08-12 + BL-02 lock). Pre-BL-02, the Factoring tab bar
        //    correctly read "Invoices" at the tab-bar layer, but the nav bar
        //    above the loads list unconditionally said "Loads" because
        //    `LoadListViewController.viewDidLoad` hard-coded that string.
        //    BL-02 threads the title through the composition root
        //    (`AppContainer.makeLoadListScreen(role:)` → `LoadListViewController
        //    .init(viewModel:navTitle:)`) so Factoring's nav bar now reads
        //    "Invoices" end-to-end.
        XCTAssertTrue(app.navigationBars[tabName].waitForExistence(timeout: 5),
                      "BL-02 — \(role) nav bar title should match tab-item title '\(tabName)'")
    }

    // MARK: - 5 role smoke tests (one per Role)

    func test_brokerLoadsTabRendersList() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)
        assertLoadsTabResolvesList(app, tabName: "Loads", role: "broker")
    }

    func test_shipperLoadsTabRendersList() {
        let app = launch(role: "shipper")
        driveFullOTPFlow(app)
        assertLoadsTabResolvesList(app, tabName: "Loads", role: "shipper")
    }

    func test_carrierLoadsTabRendersList() {
        let app = launch(role: "carrier")
        driveFullOTPFlow(app)
        assertLoadsTabResolvesList(app, tabName: "Loads", role: "carrier")
    }

    func test_dispatchLoadsTabRendersList() {
        let app = launch(role: "dispatch")
        driveFullOTPFlow(app)
        assertLoadsTabResolvesList(app, tabName: "Loads", role: "dispatch")
    }

    // T-08-12 lock: factoring taps the LITERAL `"Invoices"` tab (NOT "Loads").
    // The same literal that `RoleShellSmokeTests.swift:151` asserts —
    // together the two test sites provide double coverage of the locked tab
    // title. A regression to `"Loads"` for factoring would fail BOTH suites.
    func test_factoringInvoicesTabRendersList() {
        let app = launch(role: "factoring")
        driveFullOTPFlow(app)
        assertLoadsTabResolvesList(app, tabName: "Invoices", role: "factoring")
    }
}
