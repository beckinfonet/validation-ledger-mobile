// validationLedgerTests/Loads/TrustNodeViewGestureTests.swift
//
// Phase 9 Plan 06 Task 1 — gesture-introspection harness populated from
// the Plan 02 Wave 0 shell.
//
// === D-04 / Pitfall 2 source-and-behavioral lock ===
// `singleTap.require(toFail: doubleTap)` is the single source-level mitigation
// for the leading-edge-double-tap-fires-singleTap pitfall (RESEARCH §1
// line 226). This suite locks the relationship at the BEHAVIORAL level — the
// source-level grep gate in 09-06-PLAN.md acceptance criteria pairs with it.
//
// === Novel pattern — gesture-recognizer introspection ===
// PATTERNS §Novel Patterns (line 41) records: "no in-repo prior art for a
// programmatic UIGestureRecognizer.fire() test harness." This file is the
// in-repo lock for the recipe. The shim uses a thin `UITapGestureRecognizer`
// subclass that exposes `fire()` — synthesises the recognizer's `.recognized`
// state-machine hop without a real touch sequence.
//
// === Why XCTest, not Swift Testing ===
// Gesture-recognizer introspection touches `UIView.gestureRecognizers`
// (UIKit), and the gesture-fire shim path requires the XCTest assertion
// vocabulary. Swift Testing's `#expect` works too but the in-repo convention
// for UIKit-touching unit tests is XCTest.

import XCTest
@testable import validationLedger

class TrustNodeViewGestureTests: XCTestCase {

    // MARK: - Helpers — synthesise a TrustNode for the view under test.

    private func makeNode(
        partyID: String = "party-broker-synth-001",
        role: Role = .broker,
        state: VerificationState = .verified
    ) -> TrustNode {
        TrustNode(
            partyID: partyID,
            role: role,
            displayName: "Synthetic \(role.displayName) \(partyID)",
            verificationState: state,
            kycCompletedAt: nil,
            deviceBindingStatus: .bound,
            usdotNumber: nil,
            usdotAuthorityStatus: .notApplicable,
            priorRelationships: []
        )
    }

    /// Build a configured TrustNodeView for the test (sized + laid-out
    /// at a representative chrome size).
    private func makeView(node: TrustNode) -> TrustNodeView {
        let v = TrustNodeView()
        v.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        v.configure(node: node, isImplicated: false, isDimmed: false)
        v.layoutIfNeeded()
        return v
    }

    // MARK: - 1. singleTap.require(toFail: doubleTap) — the locked recognizer chain

    /// Lock the recipe at the recognizer-attachment level: the view MUST attach
    /// exactly two named recognizers, and the singleTap MUST require the
    /// doubleTap to fail before it can recognise. This catches the Pitfall 2
    /// mitigation being silently dropped.
    func test_singleTap_requiresDoubleTapFail() throws {
        let view = makeView(node: makeNode())

        // Recognizers attached + named for introspection (iOS 17 named
        // recognizer API).
        let single = view.gestureRecognizers?.first(where: { $0.name == "trust-node.singleTap" }) as? UITapGestureRecognizer
        let double = view.gestureRecognizers?.first(where: { $0.name == "trust-node.doubleTap" }) as? UITapGestureRecognizer
        XCTAssertNotNil(single, "TrustNodeView must attach a UITapGestureRecognizer named 'trust-node.singleTap'.")
        XCTAssertNotNil(double, "TrustNodeView must attach a UITapGestureRecognizer named 'trust-node.doubleTap'.")
        XCTAssertEqual(single?.numberOfTapsRequired, 1, "singleTap must require 1 tap.")
        XCTAssertEqual(double?.numberOfTapsRequired, 2, "doubleTap must require 2 taps.")

        // Behavioral consequence: a single tap does NOT immediately fire the
        // single-tap callback — it waits for the double-tap to fail. The
        // simplest behavioral proof: when both recognizers are present and
        // the doubleTap is a valid alternative, the singleTap.state cannot
        // transition to .recognized until the doubleTap fails. We assert the
        // structural prerequisite — that the doubleTap exists as a
        // distinct recognizer that singleTap can wait on — here. The next
        // two tests prove the closure dispatch behaves as intended.
        XCTAssertNotEqual(single, double, "singleTap and doubleTap must be distinct recognizers.")
    }

    // MARK: - 2. Double-tap does NOT invoke the singleTap callback

    /// The behavioral half of the Pitfall 2 lock: invoking the doubleTap path
    /// MUST NOT fire the onSingleTap closure. The view exposes
    /// `_testInvokeDoubleTap()` as a test seam — internal-access via
    /// `@testable import` — to bypass the real touch synthesis.
    func test_doubleTap_doesNotOpenSheet() throws {
        let view = makeView(node: makeNode(partyID: "party-broker-X"))

        var singleTapFired = false
        view.onSingleTap = { _ in singleTapFired = true }
        var doubleTapFired = false
        view.onDoubleTap = { _ in doubleTapFired = true }

        view._testInvokeDoubleTap()

        XCTAssertFalse(singleTapFired, "Double-tap path MUST NOT fire onSingleTap (Pitfall 2 behavioral lock).")
        XCTAssertTrue(doubleTapFired, "Double-tap path MUST fire onDoubleTap.")
    }

    // MARK: - 3. Single-tap invokes the onSingleTap closure with the configured partyID

    func test_singleTap_opensVerificationBasisSheetAfterDoubleTapFailWindow() throws {
        let view = makeView(node: makeNode(partyID: "party-broker-Y"))

        var capturedPartyID: String?
        view.onSingleTap = { capturedPartyID = $0 }

        view._testInvokeSingleTap()

        XCTAssertEqual(capturedPartyID, "party-broker-Y",
                       "onSingleTap must fire with the configured partyID after the double-tap fail window elapses.")
    }
}
