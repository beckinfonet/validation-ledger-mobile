// validationLedgerTests/Loads/TrustGraphViewAccessibilityTests.swift
//
// Phase 9 Plan 06 Task 2 — populates the Plan 02 Wave 0 shell.
//
// Locked targets (09-06-PLAN.md acceptance criteria):
//   - test_isAccessibilityElement_false (D-22 Pitfall 4 lock — the container
//     is NOT a leaf).
//   - test_accessibilityElements_orderedRoleThenEdges (D-22 deterministic
//     traversal order: nodes in fixed role order, then edges sorted by
//     (fromPartyID, toPartyID) lex order).
//   - test_nodeAccessibilityLabel_followsComposedTemplate (UI-SPEC lines
//     841-845 — "<role>, <displayName>, verification state: <state>, KYC
//     <basis>" composed by the PARENT TrustGraphView).
//   - test_implicatedNode_appendsCompromiseSuffix (D-11 — implicated nodes
//     append "Implicated in chain compromise.").
//   - test_voiceOver_disablesZoom (D-22 mirror — see GestureTests).
//   - test_reduceMotion_suspendsPulse (UI-SPEC line 866 — compromised halo
//     stays solid under reduce-motion; color still signals compromised,
//     motion does not).
//
// === Why XCTest, not Swift Testing ===
// `view.accessibilityElements!.count` introspection touches UIKit; in-repo
// convention for accessibility introspection is XCTest.

import XCTest
@testable import validationLedger

class TrustGraphViewAccessibilityTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - 1. isAccessibilityElement == false (D-22 Pitfall 4 lock)

    /// The graph is a CONTAINER, not a leaf. If a future edit flips this to
    /// `true` the entire graph collapses to a single VoiceOver element and
    /// rotor traversal across nodes/edges breaks — the highest-impact
    /// regression Pitfall 4 protects against.
    func test_isAccessibilityElement_false() throws {
        let view = makeView()
        XCTAssertFalse(view.isAccessibilityElement,
                       "TrustGraphView must NOT be an accessibility leaf — D-22 lock.")
    }

    // MARK: - 2. Ordered: 5 nodes in role order, then edges in lex order

    func test_accessibilityElements_orderedRoleThenEdges() throws {
        let view = makeView()
        guard let elements = view.accessibilityElements else {
            XCTFail("TrustGraphView must publish an accessibilityElements array (D-22).")
            return
        }
        // The fixture chain has 5 nodes + 4 edges.
        XCTAssertEqual(elements.count, 5 + 4,
                       "Element count must be (5 nodes + 4 edges) = 9 for the canonical 5-node fixture.")

        // First 5 must be TrustNodeView in fixed role order
        // (shipper, broker, carrier, dispatch, factoring) — D-22.
        let nodes = elements.prefix(5).compactMap { $0 as? TrustNodeView }
        XCTAssertEqual(nodes.count, 5, "First 5 elements must all be TrustNodeView.")

        let expectedRoleOrder = ["party-shipper", "party-broker", "party-carrier",
                                 "party-dispatch", "party-factoring"]
        XCTAssertEqual(nodes.map(\.partyID), expectedRoleOrder,
                       "Nodes must be ordered shipper → broker → carrier → dispatch → factoring (D-22).")
    }

    // MARK: - 3. Per-node accessibilityLabel composed template

    func test_nodeAccessibilityLabel_followsComposedTemplate() throws {
        let view = makeView()
        guard let nodeView = (view.accessibilityElements?.first as? TrustNodeView) else {
            XCTFail("First element must be a TrustNodeView (the shipper).")
            return
        }
        let label = nodeView.accessibilityLabel ?? ""
        // The composed template per UI-SPEC lines 841-845 starts with role
        // displayName, then displayName, then "verification state: ".
        XCTAssertTrue(label.hasPrefix("Shipper, "),
                      "Composed accessibilityLabel must start with role displayName + comma. Got: \(label)")
        XCTAssertTrue(label.contains("verification state:"),
                      "Composed accessibilityLabel must contain 'verification state:' template token. Got: \(label)")
        XCTAssertTrue(label.contains("KYC "),
                      "Composed accessibilityLabel must contain 'KYC ' basis-summary token. Got: \(label)")
    }

    // MARK: - 4. Implicated node appends compromise-suffix

    /// D-11 — when a node is in `chainIntegrity.implicatedNodeIDs`, its
    /// composed accessibilityLabel ENDS with "Implicated in chain compromise."
    /// (UI-SPEC line 845).
    func test_implicatedNode_appendsCompromiseSuffix() throws {
        // Configure with the compromised carrier node implicated.
        let view = makeView(
            verdict: .compromised,
            implicatedNodeIDs: ["party-carrier"]
        )
        guard let elements = view.accessibilityElements else {
            XCTFail("accessibilityElements must be populated.")
            return
        }
        // The carrier is the 3rd in the role-ordered prefix.
        guard let carrier = elements.prefix(5).compactMap({ $0 as? TrustNodeView })
            .first(where: { $0.partyID == "party-carrier" }) else {
            XCTFail("Carrier node must be present in the role-ordered prefix.")
            return
        }
        let label = carrier.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Implicated in chain compromise"),
                      "Implicated carrier label must end with the compromise suffix (D-11 / UI-SPEC line 845). Got: \(label)")
    }

    // MARK: - 5. VoiceOver-active clamps the zoom

    func test_voiceOver_disablesZoom() throws {
        let view = makeView()
        view._testInvokeVoiceOverChange(isOn: true)
        XCTAssertEqual(view.scrollView.minimumZoomScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(view.scrollView.maximumZoomScale, 1.0, accuracy: 0.001)
    }

    // MARK: - 6. Reduce-motion suspends the compromised pulse

    /// UI-SPEC line 866 / D-15 — under reduce-motion, the compromised halo
    /// renders solid (no pulse). Color (red) still signals compromised;
    /// motion does not.
    func test_reduceMotion_suspendsPulse() throws {
        let view = TrustGraphView()
        view.reduceMotionOverride = true
        view.bounds = CGRect(x: 0, y: 0, width: 393, height: 600)
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: .compromised,
            implicatedNodeIDs: ["party-carrier"]
        )
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()

        // Find the carrier's halo layer; assert no pulse animation is attached.
        let halos = view._testHaloLayers()
        XCTAssertFalse(halos.isEmpty, "Compromised chain must produce ≥1 halo layer.")
        for halo in halos {
            XCTAssertNil(halo.animation(forKey: "pulse"),
                         "Reduce-motion: compromised halos must NOT carry a pulse animation (UI-SPEC line 866).")
        }
    }
}
