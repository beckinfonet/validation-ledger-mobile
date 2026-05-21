// validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift
//
// Phase 9 Plan 06 Task 1 — populates the Wave 0 shell from Plan 02.
// **Phase 9.1 D-05**: this suite is now iPad-only. TrustNodeView is mounted
// only on the iPad path after 9.1 (R5: iPhone uses the new vertical-tree
// layout from Plans 03 + 04). The chrome-size constant has been renamed
// to convey iPad-only intent.
//
// Locked targets:
//   - 09-06-PLAN.md Task 1 (4 representative verification-state × role frames).
//   - 09-PATTERNS.md E5 — TrustNodeView composes VerificationBadgeView.
//   - 09-UI-SPEC.md § Node visuals lines 167-184 (chrome + badge + role label
//     + displayName label).
//   - 09-CONTEXT.md D-15 dim-others rule (alpha == 0.5 when chain verdict !=
//     clean AND this node is not implicated).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`; mirrors
// VerificationBadgeViewSnapshotTests precedent.
//
// === T-09-04 (PII) / T-09-03 (no client-trust derivation) ===
// Tests construct nodes with synthetic VL-9xxx-style party IDs and synthetic
// display names. Every visual treatment is driven directly by the configured
// VerificationState + the isImplicated/isDimmed inputs — never derived.

import XCTest
@testable import validationLedger

class TrustNodeViewSnapshotTests: XCTestCase {

    // MARK: - Helpers — Phase 9.1 D-05 iPad-only intent

    /// Default node chrome canvas — square 100×100pt mirrors the iPad
    /// fit-all-nodes-tight rendering (≈90pt node chrome at default zoom).
    /// Renamed from `chromeSize` to `iPadChromeSize` per Phase 9.1 D-05 to
    /// convey the iPad-only mounting posture (iPhone no longer renders
    /// TrustNodeView in the production composition).
    private static let iPadChromeSize = CGSize(width: 100, height: 100)

    private func makeNode(
        role: Role,
        state: VerificationState,
        partyID: String
    ) -> TrustNode {
        TrustNode(
            partyID: partyID,
            role: role,
            displayName: "Synthetic \(role.displayName)",
            verificationState: state,
            kycCompletedAt: nil,
            deviceBindingStatus: .bound,
            usdotNumber: nil,
            usdotAuthorityStatus: role == .carrier || role == .dispatch ? .active : .notApplicable,
            priorRelationships: []
        )
    }

    private func renderedNode(
        node: TrustNode,
        isImplicated: Bool = false,
        isDimmed: Bool = false
    ) -> TrustNodeView {
        let v = TrustNodeView()
        v.bounds = CGRect(origin: .zero, size: Self.iPadChromeSize)
        v.configure(node: node, isImplicated: isImplicated, isDimmed: isDimmed)
        v.layoutIfNeeded()
        return v
    }

    // MARK: - 4 representative (verification-state × role) snapshots

    func test_verifiedCarrierNode_rendersExpectedFrame() {
        let view = renderedNode(
            node: makeNode(role: .carrier, state: .verified, partyID: "party-carrier-VL-9001")
        )

        XCTAssertEqual(view.layer.cornerRadius, 12,
                       "TrustNodeView chrome cornerRadius must be 12pt (UI-SPEC § Node visuals).")
        XCTAssertEqual(view.alpha, 1.0,
                       "Verified carrier on a clean chain must render at full alpha (no dim-others).")
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.trust-graph.node.party-carrier-VL-9001",
                       "Node identifier must follow load-detail.trust-graph.node.{partyID} convention.")

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadChromeSize),
            name: "TrustNode-verified-carrier", to: self
        )
    }

    /// Dim-others rule — a flagged carrier on a compromised chain when this
    /// node is NOT itself implicated renders at alpha 0.5.
    func test_flaggedCarrierNode_compromised_rendersExpectedFrame() {
        let view = renderedNode(
            node: makeNode(role: .carrier, state: .flagged, partyID: "party-carrier-VL-9002"),
            isImplicated: false,
            isDimmed: true
        )

        XCTAssertEqual(Double(view.alpha), 0.5, accuracy: 0.001,
                       "isDimmed=true must render at alpha 0.5 (D-15 dim-others).")

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadChromeSize),
            name: "TrustNode-flagged-carrier-dimmed", to: self
        )
    }

    func test_pendingBrokerNode_rendersExpectedFrame() {
        let view = renderedNode(
            node: makeNode(role: .broker, state: .pending, partyID: "party-broker-VL-9003")
        )

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadChromeSize),
            name: "TrustNode-pending-broker", to: self
        )
    }

    func test_unverifiedShipperNode_rendersExpectedFrame() {
        let view = renderedNode(
            node: makeNode(role: .shipper, state: .unverified, partyID: "party-shipper-VL-9004")
        )

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadChromeSize),
            name: "TrustNode-unverified-shipper", to: self
        )
    }
}

