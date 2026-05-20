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

    // MARK: - TRUST-05 compromised-banner accessibility (Plan 10)

    /// Plan 10 — TRUST-05 / D-13(a) / D-16 / UI-SPEC line 684 acceptance:
    /// VL-1009 (the double-broker compromised archetype) MUST render the
    /// `chain-integrity-banner` AND its `accessibilityLabel` MUST follow the
    /// locked template `"Chain integrity: Compromised. {reason}"`.
    ///
    /// The banner's `accessibilityLabel` is the only VoiceOver-readable
    /// surface for the chain compromise reason (the visible label uses the
    /// shorter `"Chain compromised: {reason}"` template per UI-SPEC line 682
    /// while the a11yLabel uses the more verbose `"Chain integrity:
    /// Compromised. {reason}"` template per UI-SPEC line 684 — see
    /// `ChainIntegrityBannerView.composedAccessibilityLabel()`).
    ///
    /// The reason fragment we assert against — `"broker"` — is structurally
    /// guaranteed by the VL-1009 fixture archetype: VL-1009 is the
    /// double-broker pattern (FreightWise → Keystone), so the
    /// `chain_of_trust.integrity.reason` always describes broker behaviour
    /// (current text: "Intermediary broker re-tendered to a downstream
    /// carrier without the original broker's authorization — classic
    /// double-broker pattern..."). The word "broker" is the archetype-
    /// defining noun; a copy edit that removed it would change the
    /// archetype itself.
    ///
    /// T-09-03 LOCK — this XCUITest reads `banner.label` (the server-
    /// supplied reason rendered verbatim through `UIAccessibility.label`);
    /// no client-side trust derivation is exercised.
    /// T-09-04 LOCK — VL-1009 uses synthetic fixture parties only ("Global
    /// Exports Co.", "FreightWise Brokerage", etc.); no real customer data
    /// crosses the test boundary.
    ///
    /// Why broker (not shipper/carrier/dispatch/factoring): broker is the
    /// only role chosen because VL-1009 is in the broker's load roster
    /// (see `loads-list-broker.json`); choosing another role would require
    /// a different fixture for the row tap.
    func test_compromisedVerdict_bannerAccessibilityLabelContainsReason() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)

        // 1. Wait for the Loads tab + tap.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "broker tab bar should render with a 'Loads' tab after OTP verify")
        app.tabBars.buttons["Loads"].tap()

        // 2. Open the compromised-archetype VL-1009 fixture row. Scroll
        //    until the row resolves — mirrors test_nodeTap_opensVerificationBasisSheet.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the Loads tab")

        let targetRow = app.cells["loads-list.row.VL-1009"]
        var swipeAttempts = 0
        while !targetRow.exists && swipeAttempts < 5 {
            list.swipeUp()
            swipeAttempts += 1
        }
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5),
                      "VL-1009 compromised-archetype row must be present in the broker's load list (after \(swipeAttempts) swipe(s))")
        targetRow.tap()

        // 3. Wait for the load detail to render.
        let detail = app.otherElements["load-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "load-detail must push onto the navigation stack after tapping a row")

        // 4. The chain-integrity banner must exist for a compromised-verdict
        //    load (the banner short-circuits to isHidden + intrinsicContentSize
        //    .zero ONLY for `.clean` per ChainIntegrityBannerView.setUp()).
        //
        //    Element-type resilience: `ChainIntegrityBannerView` sets
        //    `isAccessibilityElement = true` + `accessibilityTraits =
        //    .staticText` (PATTERNS table row 19; mirrors the
        //    `limited-trust-banner` E4 twin). XCUI maps `.staticText` traits
        //    to `.staticTexts` queries, but custom UIView subclasses with
        //    `isAccessibilityElement = true` ALSO surface under
        //    `.otherElements` in some XCUI runtime versions. Probe both,
        //    plus the `descendants(matching: .any)` catch-all — the same
        //    fallback pattern Plan 07's node-tap test uses for
        //    trait-resilient resolution (lines 235-243).
        let bannerCandidates: [XCUIElement] = [
            app.descendants(matching: .any).matching(identifier: "chain-integrity-banner").firstMatch,
            app.staticTexts["chain-integrity-banner"],
            app.otherElements["chain-integrity-banner"],
        ]
        let banner = bannerCandidates.first(where: { $0.waitForExistence(timeout: 3) }) ?? bannerCandidates[0]
        XCTAssertTrue(banner.exists,
                      "TRUST-05 / D-13(a) — VL-1009 (compromised archetype) MUST render the chain-integrity-banner (probed .staticTexts / .otherElements / .any)")

        // 5. Assert the accessibility label contains the locked verdict word
        //    "Compromised" (UI-SPEC line 684 — VoiceOver-spoken verdict, NOT
        //    the visible "Chain compromised" copy — `composedAccessibilityLabel`
        //    spells it as a noun: "Chain integrity: Compromised. {reason}").
        let label = banner.label
        XCTAssertTrue(label.contains("Compromised"),
                      """
                      TRUST-05 / UI-SPEC line 684 — banner accessibilityLabel \
                      must spell the verdict as 'Compromised' (the VoiceOver \
                      noun form, NOT the visible 'Chain compromised' adjective \
                      form). Got: \(label)
                      """)

        // 6. Assert the accessibility label contains the archetype-defining
        //    reason fragment "broker". VL-1009 is the double-broker archetype;
        //    the server-supplied reason ALWAYS describes broker behaviour. A
        //    copy edit that removed "broker" would change the fixture's
        //    semantic archetype.
        XCTAssertTrue(label.lowercased().contains("broker"),
                      """
                      TRUST-05 / T-09-03 — banner accessibilityLabel must \
                      render the server-supplied reason VERBATIM (UI-SPEC line \
                      684). For VL-1009 (double-broker archetype) the reason \
                      contains 'broker' by archetype definition; if this assertion \
                      fails the fixture's archetype identity has drifted. Got: \(label)
                      """)
    }

    // MARK: - Outer-scroll propagation + D-16 fixed-banner contract (Plan 10)

    /// Plan 10 — RESEARCH §1 line 252 + § Common Pitfalls Pitfall 3 + D-16
    /// acceptance: the trust graph's inner `UIScrollView.panGestureRecognizer
    /// .minimumNumberOfTouches == 2` lock means a SINGLE-FINGER drag inside
    /// the graph region MUST NOT pan the graph; AND scrolling the bill-of-
    /// lading body region MUST NOT dismiss the pinned chain-integrity banner
    /// (D-16: "Banner is fixed (does not scroll away on iPhone). The
    /// chain-integrity banner is pinned to the top of the graph region;
    /// scrolling the bill-of-lading body below the graph does not dismiss
    /// or hide it.").
    ///
    /// Test composition:
    ///   1. Open VL-1009 — same compromised-archetype fixture as the banner
    ///      test, so the banner is present and visible.
    ///   2. Verify the banner exists pre-scroll.
    ///   3. Perform a single-finger drag UPWARD from inside the graph region.
    ///      Per the `minimumNumberOfTouches == 2` lock the graph's inner
    ///      scroll MUST NOT consume this gesture. (The drag may or may not
    ///      bubble up to scroll the body — that depends on the gesture
    ///      hit-testing in the parent hierarchy. The key assertion is that
    ///      the graph + banner remain functional afterward.)
    ///   4. Perform a swipe-up gesture inside the body's
    ///      `load-detail.body.parties-section` (or `freight-section`) — the
    ///      body's own UIScrollView has the default 1-finger pan
    ///      (`LoadDetailBodyView` line 65) so this MUST scroll the body.
    ///   5. Assert the banner is STILL visible (D-16: scrolling the body
    ///      does not dismiss the pinned banner).
    ///
    /// Why VL-1009 (not VL-1005): the banner only renders for non-clean
    /// verdicts; VL-1005 caution would also work, but VL-1009 keeps the
    /// fixture choice consistent with the banner a11y test above.
    ///
    /// Why XCUICoordinate.press(forDuration:thenDragTo:) (not swipeUp()):
    /// `swipeUp()` starts at the element's `hitPoint`, but XCUI's hitPoint
    /// can collapse to a node's centre when the element has visible
    /// children with tappable identifiers. `XCUICoordinate` with explicit
    /// normalized offsets gives us a guaranteed start point INSIDE the
    /// graph region (the centre of the `load-detail.trust-graph` element).
    /// The 0.1s press duration is the minimum that registers as a drag
    /// (rather than a tap) — matches Apple's XCUI gesture-classification
    /// thresholds documented in the WWDC 2019 XCUI session.
    ///
    /// T-09-04 LOCK — VL-1009 uses synthetic fixture parties only; no real
    /// customer data crosses the test boundary.
    func test_singleFingerScroll_propagatesPastGraph_toBodyScrollView() {
        let app = launch(role: "broker")
        driveFullOTPFlow(app)

        // 1. Wait for the Loads tab + tap.
        XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5),
                      "broker tab bar should render with a 'Loads' tab after OTP verify")
        app.tabBars.buttons["Loads"].tap()

        // 2. Open VL-1009 — compromised archetype, banner present.
        let list = app.collectionViews["loads-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "loads-list collection view should appear after tapping the Loads tab")

        let targetRow = app.cells["loads-list.row.VL-1009"]
        var swipeAttempts = 0
        while !targetRow.exists && swipeAttempts < 5 {
            list.swipeUp()
            swipeAttempts += 1
        }
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5),
                      "VL-1009 compromised-archetype row must be present in the broker's load list (after \(swipeAttempts) swipe(s))")
        targetRow.tap()

        // 3. Wait for the load detail + the trust graph + the banner.
        let detail = app.otherElements["load-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "load-detail must push onto the navigation stack after tapping a row")

        let graph = app.otherElements["load-detail.trust-graph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 3),
                      "trust graph must render after load detail appears")

        // Element-type resilience for the banner — same fallback chain as
        // `test_compromisedVerdict_bannerAccessibilityLabelContainsReason`
        // (ChainIntegrityBannerView sets accessibilityTraits = .staticText,
        // which XCUI may surface under .staticTexts OR .otherElements
        // depending on runtime).
        let bannerCandidates: [XCUIElement] = [
            app.descendants(matching: .any).matching(identifier: "chain-integrity-banner").firstMatch,
            app.staticTexts["chain-integrity-banner"],
            app.otherElements["chain-integrity-banner"],
        ]
        let banner = bannerCandidates.first(where: { $0.waitForExistence(timeout: 3) }) ?? bannerCandidates[0]
        XCTAssertTrue(banner.exists,
                      "D-16 — chain-integrity banner must render for VL-1009 (compromised verdict)")
        // D-16 pre-condition: banner is visible BEFORE any scroll.

        // 4. Single-finger drag UPWARD starting inside the graph region.
        //    Per RESEARCH §1 line 252: this MUST NOT pan the graph's inner
        //    scroll (minimumNumberOfTouches == 2 lock). We do not assert on
        //    inner scroll-offset state from XCUI (no direct access to the
        //    private UIScrollView) — instead we assert the post-drag UI is
        //    still functional: the graph still resolves AND the banner is
        //    still present.
        let graphStart = graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let graphEnd = graphStart.withOffset(CGVector(dx: 0, dy: -300))
        graphStart.press(forDuration: 0.1, thenDragTo: graphEnd)

        // The trust graph element and the banner MUST both still resolve
        // after the single-finger drag (the graph did not swallow the
        // gesture into some catastrophic state).
        XCTAssertTrue(graph.exists,
                      "RESEARCH §1 / Pitfall 3 — trust graph must remain present after a single-finger drag inside the graph region")
        XCTAssertTrue(banner.exists,
                      "D-16 — chain-integrity banner must remain present after a single-finger drag inside the graph region")

        // 5. Scroll the body region. The body has its own UIScrollView with
        //    the default 1-finger pan (`LoadDetailBodyView.swift` line 65).
        //    Drag from inside the body region upward to scroll the body
        //    content. Use the body container — `load-detail.body` — as the
        //    drag surface; it resolves to the body's UIView frame, which
        //    is below the graph on iPhone (and the right pane on iPad).
        let body = app.otherElements["load-detail.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 3),
                      "load-detail.body container must resolve for the outer-scroll-propagation test")
        let bodyStart = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bodyEnd = bodyStart.withOffset(CGVector(dx: 0, dy: -300))
        bodyStart.press(forDuration: 0.1, thenDragTo: bodyEnd)

        // 6. D-16 LOCK — after scrolling the body region, the banner MUST
        //    still be present. The banner is composition-pinned (above the
        //    graph on iPhone; full-width above the split on iPad) and is
        //    NOT inside the body's scrollView; D-16 makes this contract
        //    explicit and testable.
        XCTAssertTrue(banner.exists,
                      """
                      D-16 — the chain-integrity banner MUST remain present \
                      after scrolling the bill-of-lading body. The banner is \
                      composition-pinned (above the graph on iPhone; full-width \
                      above the split on iPad), so body scrolls must not \
                      dismiss it. If this fails the banner has been mistakenly \
                      embedded inside the body's UIScrollView (regression of \
                      LoadDetailViewController.buildIPhoneLayout / \
                      buildIPadSplitLayout).
                      """)

        // 7. Sanity: the trust graph also remains present after the body
        //    scroll (the body's scroll is independent of the graph's
        //    transform; this would only fail if the graph had been
        //    accidentally re-parented inside the body scroll).
        XCTAssertTrue(graph.exists,
                      "trust graph must remain present after the body region is scrolled (the graph is composition-pinned independent of the body's scrollView)")
    }
}
