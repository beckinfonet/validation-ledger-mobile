// validationLedgerUITests/Loads/LoadDetailFlowTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 80 (Wave 0 list).
//   - PATTERNS.md table row line 47 — direct twin
//     `validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift` (PATTERNS
//     E11 — the Phase 8 5-role XCUITest flow). Reuses
//     `driveFullOTPFlow(_:)` shape verbatim.
//
// Shell preparing the 5-role XCUITest smoke flow + sheet-opens scaffold:
//   - test_rowTap_pushesDetail() — tap a `loads-list.row.VL-*` row on each
//     role; assert `load-detail` accessibility identifier resolves.
//   - test_nodeTap_opensVerificationBasisSheet() — tap a graph node; assert
//     `verification-basis-sheet` element appears.
//   - test_edgeTap_opensHandoffSheet() — tap a graph edge; assert
//     `handoff-detail-sheet` element appears.
//   - test_compromisedVerdict_bannerAccessibilityLabelContainsReason() —
//     VL-1009/1010/1011 archetype loads; assert
//     `chain-integrity-banner.label.contains("compromised")` + the reason
//     fragment per UI-SPEC § Copywriting banner template.
//   - test_singleFingerScroll_propagatesPastGraph_toBodyScrollView() —
//     D-04 + Pitfall arbitration: single-finger drag inside the graph
//     region must NOT be eaten by the inner UIScrollView (which has
//     `panGestureRecognizer.minimumNumberOfTouches == 2`).
//
// Populated by Plan 03 (basic row-tap → detail push) and Plan 10
// (full 5-role smoke + sheet-opens assertions).
//
// === STACK-03 ===
// XCUITest IS XCTest, NOT Swift Testing — `XCUIApplication` does not bridge
// to Swift Testing as of iOS 17.
//
// === No @testable import ===
// UI tests target the product, NOT internal symbols. The accessibility
// identifiers `load-detail`, `chain-integrity-banner`, `verification-basis-
// sheet`, `handoff-detail-sheet`, `loads-list.row.VL-*` are PUBLIC API per
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

    // MARK: - Shells — populated by Plan 03 (row-tap) and Plan 10 (full flow).

    func test_rowTap_pushesDetail() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 03 / Plan 10")
    }

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
