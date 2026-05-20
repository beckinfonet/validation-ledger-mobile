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
//   - test_nodeTap_opensVerificationBasisSheet() — POPULATED HERE (Plan 07
//     TRUST-03). As the broker on VL-1009 (compromised double-broker
//     archetype), tap the flagged broker node and assert the sheet appears
//     with the KYC row + the implicated block (D-11).
//   - test_edgeTap_opensHandoffSheet() — Plan 08.
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

    // MARK: - TRUST-03 node-tap → verification-basis sheet (Plan 07)

    /// Plan 07 — TRUST-03 acceptance: tapping a `TrustNodeView` opens
    /// `VerificationBasisSheetViewController` with the kyc-row + (when the
    /// chain verdict ≠ .clean and the node is implicated) the
    /// "Why this party is flagged" block per D-11.
    ///
    /// Driven as the broker on VL-1005 (caution archetype). VL-1005
    /// implicates `party-carrier-nationallink` — the only carrier in the
    /// 3-node chain (shipper → broker → carrier), so the role-slot
    /// position is unambiguous (no slot collision). Tapping the implicated
    /// carrier node must surface BOTH `.kyc-row` and `.implicated-block`.
    ///
    /// Why not VL-1009: the double-broker archetype puts TWO broker nodes
    /// (freightwise + keystone) into the SAME broker role-slot per the
    /// D-06 fixed-slot layout. The second-rendered broker view occludes
    /// the first, making XCUI tap-targeting brittle. VL-1005's single-
    /// flagged-carrier chain avoids the collision while still exercising
    /// the full TRUST-03 + D-11 contract.
    ///
    /// Note on row discovery: VL-1005 is the 5th cell in the broker's
    /// fixture roster (per `loads-list-broker.json`). The
    /// `UICollectionView` lazily renders cells, so the cell may be
    /// outside the initial viewport. We scroll the list until the row
    /// appears (mirrors the standard XCUI swipe-to-find idiom).
    func test_nodeTap_opensVerificationBasisSheet() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)

        // 1. Wait for the Loads tab + tap.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "broker tab bar should render with a 'Loads' tab after OTP verify")
        app.tabBars.buttons["Loads"].tap()

        // 2. Open the caution-archetype VL-1005 fixture row.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the Loads tab")

        // Scroll the list until the VL-1005 cell becomes hittable.
        let targetRow = app.cells["loads-list.row.VL-1005"]
        var swipeAttempts = 0
        while !targetRow.exists && swipeAttempts < 5 {
            list.swipeUp()
            swipeAttempts += 1
        }
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5),
                      "VL-1005 caution-archetype row must be present in the broker's load list (after \(swipeAttempts) swipe(s))")
        targetRow.tap()

        // 3. Wait for the load detail to render.
        let detail = app.otherElements["load-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "load-detail must push onto the navigation stack after tapping a row")

        // 4. Tap the flagged carrier node. VL-1005 implicates
        //    `party-carrier-nationallink` (see load-detail-VL-1005.json —
        //    the caution pending-carrier pattern). The node element
        //    resolves via the UI-SPEC § Accessibility identifiers locked
        //    locator `load-detail.trust-graph.node.<partyID>`.
        //
        //    `TrustNodeView` sets `isAccessibilityElement = true` +
        //    `accessibilityTraits = .button` (Plan 06), so XCUI exposes
        //    it as a `.button` query target. We fall back through
        //    `.otherElements` (custom container) → `.buttons` (semantic
        //    button) → `.descendants(matching: .any)` to keep the test
        //    robust against any future trait re-tagging upstream.
        let nodeID = "load-detail.trust-graph.node.party-carrier-nationallink"
        let nodeCandidates: [XCUIElement] = [
            app.descendants(matching: .any).matching(identifier: nodeID).firstMatch,
            app.buttons[nodeID],
            app.otherElements[nodeID],
        ]
        let flaggedNode = nodeCandidates.first(where: { $0.waitForExistence(timeout: 5) }) ?? nodeCandidates[0]
        XCTAssertTrue(flaggedNode.exists,
                      "VL-1005 — the flagged carrier node MUST resolve via '\(nodeID)' (.button or .otherElements)")
        flaggedNode.tap()

        // 5. The verification-basis sheet must present within the single-tap
        //    require-toFail window + presentation animation budget (3s).
        let sheet = app.otherElements["load-detail.verification-basis-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3),
                      "TRUST-03 — the verification-basis sheet must appear after a single-tap on a TrustNodeView")

        // 6. Sheet content checks: KYC row must always be present (every
        //    role, every party — D-09 locked).
        let kycRow = app.otherElements["load-detail.verification-basis-sheet.kyc-row"]
        XCTAssertTrue(kycRow.waitForExistence(timeout: 2),
                      "D-09 — KYC row MUST render (every role, every party)")

        // 7. D-11 — VL-1005 is a caution chain with the carrier
        //    implicated; the "Why this party is flagged" block MUST render.
        let implicated = app.otherElements["load-detail.verification-basis-sheet.implicated-block"]
        XCTAssertTrue(implicated.waitForExistence(timeout: 2),
                      "D-11 — implicated block MUST render for a caution + implicated node")
    }

    // MARK: - TRUST-04 edge-tap → handoff-detail sheet (Plan 08)

    /// Plan 08 — TRUST-04 acceptance: tapping a graph edge (the invisible
    /// 28pt-band companion view that wraps each `CAShapeLayer` line per
    /// Plan 06) opens `HandoffDetailSheetViewController` with the
    /// edge-partition identifier resolved AND, for the implicated edge in a
    /// non-clean chain, the "Why this handoff is flagged" block per D-11.
    ///
    /// Driven as the broker on VL-1005 (caution archetype). VL-1005
    /// implicates `edge-VL-1005-broker-carrier` — the only carrier edge in
    /// the 3-node chain (shipper → broker → carrier). Tapping the
    /// implicated edge MUST surface BOTH the sheet root identifier AND the
    /// `.implicated-block` identifier.
    ///
    /// Why not VL-1009 (compromised double-broker archetype): the double-
    /// broker chain places two broker nodes in the SAME broker role-slot
    /// per the D-06 fixed-slot layout; the second-rendered broker view
    /// occludes the first, making both XCUI node-tap AND edge-companion-
    /// tap targeting brittle (an edge between two co-located broker nodes
    /// degenerates to a near-zero-length stroke). VL-1005's two-edge chain
    /// has well-separated endpoints — deterministic tap target — while
    /// still exercising the full TRUST-04 + D-11 contract.
    ///
    /// Row discovery mirrors `test_nodeTap_opensVerificationBasisSheet`:
    /// VL-1005 is the 5th cell in the broker's fixture roster, so we
    /// swipe-to-find before tapping.
    func test_edgeTap_opensHandoffSheet() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)

        // 1. Wait for the Loads tab + tap.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "broker tab bar should render with a 'Loads' tab after OTP verify")
        app.tabBars.buttons["Loads"].tap()

        // 2. Open the caution-archetype VL-1005 fixture row.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the Loads tab")

        let targetRow = app.cells["loads-list.row.VL-1005"]
        var swipeAttempts = 0
        while !targetRow.exists && swipeAttempts < 5 {
            list.swipeUp()
            swipeAttempts += 1
        }
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5),
                      "VL-1005 caution-archetype row must be present in the broker's load list (after \(swipeAttempts) swipe(s))")
        targetRow.tap()

        // 3. Wait for the load detail to render.
        let detail = app.otherElements["load-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "load-detail must push onto the navigation stack after tapping a row")

        // 4. Tap the flagged broker→carrier edge. VL-1005 implicates
        //    `edge-VL-1005-broker-carrier` (see load-detail-VL-1005.json —
        //    the only flagged edge in the caution chain). The edge
        //    companion view resolves via UI-SPEC § Accessibility
        //    identifiers `load-detail.trust-graph.edge.<edgeID>`.
        //
        //    Plan 06's `EdgeCompanionView` sets `isAccessibilityElement =
        //    true` + `accessibilityTraits = .button`, so XCUI may expose
        //    it as a `.button` query target. We fall back through
        //    `.descendants(matching: .any)` → `.buttons` →
        //    `.otherElements` for trait resilience.
        let edgeID = "load-detail.trust-graph.edge.edge-VL-1005-broker-carrier"
        let edgeCandidates: [XCUIElement] = [
            app.descendants(matching: .any).matching(identifier: edgeID).firstMatch,
            app.buttons[edgeID],
            app.otherElements[edgeID],
        ]
        let flaggedEdge = edgeCandidates.first(where: { $0.waitForExistence(timeout: 5) }) ?? edgeCandidates[0]
        XCTAssertTrue(flaggedEdge.exists,
                      "VL-1005 — the flagged broker→carrier edge MUST resolve via '\(edgeID)' (.button or .otherElements)")
        flaggedEdge.tap()

        // 5. The handoff-detail sheet must present within the single-tap
        //    + presentation animation budget (3s).
        let sheet = app.otherElements["load-detail.handoff-detail-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3),
                      "TRUST-04 — the handoff-detail sheet must appear after a single-tap on an edge companion view")

        // 6. D-11 — VL-1005 is a caution chain with the broker→carrier
        //    edge implicated; the "Why this handoff is flagged" block
        //    MUST render.
        let implicated = app.otherElements["load-detail.handoff-detail-sheet.implicated-block"]
        XCTAssertTrue(implicated.waitForExistence(timeout: 2),
                      "D-11 — implicated block MUST render for a caution + implicated edge")
    }

    // MARK: - Shells — populated by Plan 10.

    func test_compromisedVerdict_bannerAccessibilityLabelContainsReason() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }

    func test_singleFingerScroll_propagatesPastGraph_toBodyScrollView() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 10")
    }
}
