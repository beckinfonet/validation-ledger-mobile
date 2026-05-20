// validationLedgerTests/Loads/TrustNodeViewGestureTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 75 (Wave 0 list).
//   - PATTERNS.md table row line 41 — **novel pattern** (no in-repo analog).
//     Closest shape: `KYCCapturePreviewLayoutTests` (XCTest that introspects
//     view geometry). RESEARCH §1 lines 245-253 owns the canonical recipe.
//
// Shell preparing the `singleTap.require(toFail: doubleTap)` + recognizer
// introspection harness:
//   - Method 1: assert `singleTap.failureRequirements.contains(doubleTap)`.
//   - Method 2: assert double-tap does NOT open the verification-basis sheet
//     (leading-edge of a double-tap must NOT trigger single-tap behaviour).
//   - Method 3: assert single-tap opens the sheet AFTER the double-tap-fail
//     window elapses.
//
// Populated by Plan 06 (TrustNodeView production type + gesture wiring).
//
// === Why XCTest, not Swift Testing ===
// Gesture-recognizer introspection touches `UIView.gestureRecognizers`
// (UIKit), and the gesture-fire shim path requires the XCTest assertion
// vocabulary (`XCTAssertTrue` + helper-based UIGestureRecognizer subclass
// for programmatic `fire()`). Swift Testing's `#expect` works too but the
// in-repo convention for UIKit-touching unit tests is XCTest.

import XCTest
@testable import validationLedger

class TrustNodeViewGestureTests: XCTestCase {

    func test_singleTap_requiresDoubleTapFail() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 06")
    }

    func test_doubleTap_doesNotOpenSheet() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 06")
    }

    func test_singleTap_opensVerificationBasisSheetAfterDoubleTapFailWindow() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 06")
    }
}
