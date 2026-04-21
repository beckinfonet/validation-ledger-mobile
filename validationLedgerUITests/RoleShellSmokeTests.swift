// validationLedgerUITests/RoleShellSmokeTests.swift
// CI-02 Phase 1 placeholder scope per Assumption A10 + Flag #3 (01-RESEARCH.md).
// 5 per-role tests verify each TabBarController renders its D-09 tab inventory.
// Full OTP -> shell -> logout smoke lands Phase 3 when AUTH-* + SHELL-* are implemented.
//
// STACK-03: XCUITest retained for UI tests (XCTest, not Swift Testing).
//
// Driven by the DEBUG-only `-ForceRoleForUITest <rawValue>` launch argument in
// SceneDelegate; Release builds cannot be forced into a non-default role via the arg.

import XCTest

final class RoleShellSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testShipperShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceRoleForUITest", "shipper"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Brokers"].exists)
        XCTAssertTrue(app.tabBars.buttons["BOL"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    }

    func testBrokerShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceRoleForUITest", "broker"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Carriers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Network"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    }

    func testCarrierShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceRoleForUITest", "carrier"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Drivers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Documents"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    }

    func testDispatchShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceRoleForUITest", "dispatch"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Fleet"].exists)
        XCTAssertTrue(app.tabBars.buttons["Drivers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    }

    func testFactoringShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ForceRoleForUITest", "factoring"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Invoices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Carriers"].exists)
        XCTAssertTrue(app.tabBars.buttons["Chain"].exists)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    }
}
