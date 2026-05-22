// validationLedgerTests/Loads/TrustGraphViewGestureTests.swift
//
// Phase 9 Plan 06 Task 2 — populates the Plan 02 Wave 0 shell.
//
// Locked targets (09-06-PLAN.md acceptance criteria):
//   - test_innerScroll_minimumNumberOfTouchesEqualsTwo (D-04 / RESEARCH §1
//     line 247 — outer page scroll preserved; single-finger drags propagate
//     to whatever scroll view contains the graph).
//   - test_innerScroll_maximumNumberOfTouchesEqualsTwo (belt-and-braces —
//     RESEARCH §1 line 215).
//   - test_doubleTapOnNode_animatesZoomTowardTargetScale (D-04 recenter+
//     zoom animation, RESEARCH §6 lines 626-666).
//   - test_doubleTapOnEmptyCanvas_resetsZoomToOne (D-05 fit-all-nodes-tight
//     default, RESEARCH §6 line 671).
//   - test_voiceOverActive_disablesPinchZoom (D-22 lock — RESEARCH §4 line 485).
//
// === Novel pattern — UIScrollView introspection at unit-test scale ===
// PATTERNS table line 42 records: no in-repo prior art for a programmatic
// UIScrollView.zoomScale assertion at the unit-test level. The harness uses
// the `_testInvokeDoubleTapOnNode(...)` / `_testInvokeDoubleTapOnEmptyCanvas()`
// / `_testInvokeVoiceOverChange(...)` internal-access seams the production
// type exposes — same approach as TrustNodeViewGestureTests.
//
// === Why XCTest, not Swift Testing ===
// Gesture-recognizer introspection touches UIKit; PATTERNS convention.

import XCTest
@testable import validationLedger

class TrustGraphViewGestureTests: XCTestCase {

    // MARK: - Helpers

    /// Synthesise a 5-node clean chain with edges along the canonical
    /// shipper → broker → carrier → dispatch & carrier → factoring fork.
    /// Returns a fully-configured TrustGraphView laid out at iPhone-portrait
    /// dimensions (393×600pt — fits the marquee canvas budget).
    private func makeView(
        verdict: ChainIntegrity.Verdict = .clean,
        implicatedNodeIDs: [String] = [],
        implicatedEdgeIDs: [String] = []
    ) -> TrustGraphView {
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: verdict,
            implicatedNodeIDs: implicatedNodeIDs,
            implicatedEdgeIDs: implicatedEdgeIDs
        )
        let v = TrustGraphView()
        v.bounds = CGRect(x: 0, y: 0, width: 393, height: 600)
        v.configure(chainOfTrust: chain)
        v.layoutIfNeeded()
        return v
    }

    // MARK: - 1. D-04 outer-page-scroll preservation — minimumNumberOfTouches == 2

    /// The marquee D-04 lock: a single-finger drag MUST propagate to the
    /// outer page scroll. The graph's inner pan recognizer requires 2
    /// fingers — only a two-finger drag scrolls the graph's contents.
    func test_innerScroll_minimumNumberOfTouchesEqualsTwo() throws {
        let view = makeView()
        let pan = view.scrollView.panGestureRecognizer
        XCTAssertEqual(pan.minimumNumberOfTouches, 2,
                       "TrustGraphView's inner scrollView pan must require 2 fingers (D-04 outer-page-scroll lock).")
    }

    /// Belt-and-braces — RESEARCH §1 line 215.
    func test_innerScroll_maximumNumberOfTouchesEqualsTwo() throws {
        let view = makeView()
        let pan = view.scrollView.panGestureRecognizer
        XCTAssertEqual(pan.maximumNumberOfTouches, 2,
                       "TrustGraphView's inner scrollView pan must cap at 2 fingers (RESEARCH §1 line 215).")
    }

    // MARK: - 2. Double-tap-on-node zooms toward the target scale

    /// Invoking the per-node double-tap path must drive `scrollView.zoomScale`
    /// above 1.0 toward the target (~1.8x). The animation is run with
    /// `animated: false` from the test seam so the final state is
    /// deterministic without spinning the run loop.
    func test_doubleTapOnNode_animatesZoomToward1_8() throws {
        let view = makeView()
        XCTAssertEqual(view.scrollView.zoomScale, 1.0, accuracy: 0.01,
                       "Initial zoomScale must be 1.0 (D-05 fit-all-nodes-tight default).")

        view._testInvokeDoubleTapOnAnyNode()

        XCTAssertGreaterThan(view.scrollView.zoomScale, 1.0,
                             "Double-tap-on-node must zoom in past 1.0 (D-04 zoom recipe).")
    }

    // MARK: - 3. Double-tap-on-empty-canvas resets to zoom 1.0

    func test_doubleTapOnEmptyCanvas_resetsZoomToOne() throws {
        let view = makeView()
        view.scrollView.setZoomScale(1.5, animated: false)
        XCTAssertEqual(view.scrollView.zoomScale, 1.5, accuracy: 0.01,
                       "Test precondition: zoomScale must be 1.5 before the reset.")

        view._testInvokeDoubleTapOnEmptyCanvas()

        XCTAssertEqual(view.scrollView.zoomScale, 1.0, accuracy: 0.01,
                       "Double-tap-on-empty-canvas must reset to zoom 1.0 (D-05 fit-all-nodes-tight).")
    }

    // MARK: - 4. VoiceOver-active disables pinch zoom (D-22 lock)

    /// When VoiceOver runs, the canvas stays at fit-all-nodes-tight zoom —
    /// pinch is suspended so the user's rotor traversal across the
    /// accessibilityElements list is the sole interaction model.
    func test_voiceOverActive_disablesPinchZoom() throws {
        let view = makeView()
        XCTAssertGreaterThan(view.scrollView.maximumZoomScale, 1.0,
                             "Test precondition: maximumZoomScale must be > 1.0 with VoiceOver off.")

        view._testInvokeVoiceOverChange(isOn: true)

        XCTAssertEqual(view.scrollView.minimumZoomScale, 1.0, accuracy: 0.001,
                       "VoiceOver active: minimumZoomScale must be clamped to 1.0 (D-22).")
        XCTAssertEqual(view.scrollView.maximumZoomScale, 1.0, accuracy: 0.001,
                       "VoiceOver active: maximumZoomScale must be clamped to 1.0 (D-22).")
    }
}
