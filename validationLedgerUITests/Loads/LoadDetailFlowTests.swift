// validationLedgerUITests/Loads/LoadDetailFlowTests.swift
//
// Phase 9 Plan 03 — LOAD-05 XCUITest smoke flow: tap a load-list row on
// each of the 5 roles, assert `load-detail` accessibility identifier
// resolves on the navigation stack. Populates the Wave 0 shell's
// `test_rowTap_pushesDetail()` method body; the other 4 methods stay
// shelled until Plans 07/08/10 populate them.
//
// Locked targets:
//   - VALIDATION.md line 80 (Wave 0 list).
//   - PATTERNS.md table row line 47 / E11 — direct twin
//     `validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift` (the
//     Phase 8 5-role XCUITest flow). Reuses `driveFullOTPFlow(_:)` shape
//     verbatim, then taps the first `loads-list.row.VL-*` cell.
//
// Shell — methods populated by Plan and downstream plans:
//   - test_rowTap_pushesDetail() — POPULATED HERE (Plan 03 LOAD-05).
//     For each of the 5 roles, drive OTP, tap the Loads/Invoices tab, tap
//     the first row, assert `load-detail` element appears (the LOAD-05
//     acceptance criterion — the detail VC pushes onto the nav stack).
//   - test_nodeTap_opensVerificationBasisSheet() — Plan 10.
//   - test_edgeTap_opensHandoffSheet() — Plan 10.
//   - test_compromisedVerdict_bannerAccessibilityLabelContainsReason() — Plan 10.
//   - test_singleFingerScroll_propagatesPastGraph_toBodyScrollView() — Plan 10.
//
// === STACK-03 ===
// XCUITest IS XCTest, NOT Swift Testing — `XCUIApplication` does not bridge
// to Swift Testing as of iOS 17.
//
// === No @testable import ===
// UI tests target the product, NOT internal symbols. The accessibility
// identifiers `load-detail`, `loads-list.row.VL-*` are PUBLIC API per
// PATTERNS § "Accessibility identifier discipline" line 500-502.
//
// === Warning 5 (executionTimeAllowance) ===
// `executionTimeAllowance = 30` hard cap per test prevents a hung XCUI
// element-wait from cascading the suite — matches RoleLoadsTabSmokeTests
// line 45 verbatim.

import XCTest

final class LoadDetailFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Warning 5: 30s hard cap per test.
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    // MARK: - Helpers (mirror RoleLoadsTabSmokeTests verbatim)

    private func launch(role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MockOTPRoleForUITest", role]
        app.launch()
        return app
    }

    /// Drives phone-entry → Submit → OTP entry → Verify. After this returns,
    /// the role tab bar is visible (or will be shortly — per-role assertions
    /// follow). Mirrors `RoleLoadsTabSmokeTests.driveFullOTPFlow(_:)`
    /// verbatim — copied per PATTERNS E11 (the simpler path — no shared
    /// helper file to invent).
    private func driveFullOTPFlow(_ app: XCUIApplication) {
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

        let otpField = app.textFields["otp-field"]
        XCTAssertTrue(otpField.waitForExistence(timeout: 5),
                      "OTP field should appear after phone submit (mock-backed — 5s cap)")
        otpField.tap()
        otpField.typeText("123456")
        app.buttons["otp-verify"].tap()
    }

    /// Shared per-role assertion body. Mirrors `assertLoadsTabResolvesList`
    /// in RoleLoadsTabSmokeTests but extends the flow: after the
    /// `loads-list` resolves, tap the first row and assert the
    /// `load-detail` element appears on the navigation stack within 5s.
    private func assertRowTapPushesDetail(
        _ app: XCUIApplication,
        tabName: String,
        role: String
    ) {
        // 1. Wait for the tab bar to render with the expected tab.
        XCTAssertTrue(app.tabBars.buttons[tabName].waitForExistence(timeout: 5),
                      "\(role) tab bar should render with a '\(tabName)' tab after OTP verify")
        app.tabBars.buttons[tabName].tap()

        // 2. Wait for the loads list to render with at least one row.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the \(tabName) tab")

        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'loads-list.row.VL-'")
        let firstRow = app.cells.matching(rowPredicate).element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                      "At least one loads-list.row.VL-* row should appear for role \(role)")

        // 3. Tap the first row — LOAD-05: this MUST push the detail VC onto
        //    the navigation stack.
        firstRow.tap()

        // 4. Assert the `load-detail` accessibility identifier resolves —
        //    the locked Phase 9 root identifier on `LoadDetailViewController
        //    .view` (UI-SPEC § Accessibility identifiers locked list,
        //    PATTERNS § Accessibility identifier discipline line 500-502).
        //    The VC is constructed by `AppContainer.makeLoadDetailScreen
        //    (loadID:)` via the threaded factory closure (Phase 9 Plan 03
        //    Task 2 wiring).
        let detail = app.otherElements["load-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      """
                      LOAD-05 — load-detail element MUST appear after \
                      tapping the first loads-list.row.VL-* on role \(role); \
                      either the row-tap handler is not pushing the detail \
                      VC, or the VC's view.accessibilityIdentifier is not \
                      'load-detail'.
                      """)
    }

    // MARK: - 5-role row-tap → detail push (LOAD-05)

    func test_rowTap_pushesDetail() {
        // Per the LOAD-05 truth: "Tapping a load-list row in any role's
        // LoadListViewController pushes LoadDetailViewController onto the
        // navigation stack." Iterating the 5 roles in subtests via
        // XCTContext.runActivity gives per-role failure scoping without
        // multiplying the method count.
        let roles: [(role: String, tab: String)] = [
            ("broker", "Loads"),
            ("shipper", "Loads"),
            ("carrier", "Loads"),
            ("dispatch", "Loads"),
            // T-08-12 lock: the Factoring role's tab is literally "Invoices".
            ("factoring", "Invoices"),
        ]
        for entry in roles {
            XCTContext.runActivity(named: "Role: \(entry.role)") { _ in
                let app = launch(role: entry.role)
                driveFullOTPFlow(app)
                assertRowTapPushesDetail(app, tabName: entry.tab, role: entry.role)
                // Best-effort teardown — terminate the app so the next role's
                // launch starts cold. If the test framework already torn it
                // down, terminate() is a no-op.
                app.terminate()
            }
        }
    }

    // MARK: - Shells — populated by Plan 10.

    func test_nodeTap_opensVerificationBasisSheet() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }

    func test_edgeTap_opensHandoffSheet() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }

    func test_compromisedVerdict_bannerAccessibilityLabelContainsReason() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }

    func test_singleFingerScroll_propagatesPastGraph_toBodyScrollView() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }
}
