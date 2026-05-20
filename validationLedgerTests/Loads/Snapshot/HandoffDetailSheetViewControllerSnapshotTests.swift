// validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift
//
// Phase 9 Plan 08 Task 1 — TRUST-04 handoff-detail sheet snapshot suite
// (populates the Plan 02 Wave-0 shell).
//
// === Plan 02 Wave-0 shell → Plan 08 population ===
// The three locked scenarios per 09-RESEARCH.md §3 line 402 plus an
// optional null-tender informational-line case (UI-SPEC line 731):
//   1. clean edge — verified relationship, no implicated block, basic rows.
//   2. caution × implicated — D-11 inline block with yellow tint.
//   3. compromised × implicated — D-11 inline block with red tint, server-
//                                  supplied reason rendered verbatim.
//   4. null tenderRef — UI-SPEC line 731 informational line "No formal
//                       tender on file." (added for coverage of the
//                       tender-reference branch).
//
// Locked targets:
//   - 09-08-PLAN.md Acceptance Criteria — zero test-method skip stubs in
//     this file (the grep gate is a plain-text contract; the doc-comment
//     describes the requirement without using the trigger token literally,
//     mirroring the Plan 07 SUMMARY deviation #3 re-phrase precedent).
//   - 09-UI-SPEC.md § HandoffDetailSheetViewController lines 459-471 (content
//     order) + § Copywriting Handoff detail sheet lines 723-733.
//   - 09-UI-SPEC.md § Accessibility identifiers lines 782-784 (sheet root +
//     edge partition identifier + implicated-block identifier).
//   - 09-PATTERNS.md table row 24 — HandoffDetailSheetViewController
//     mirrors the VerificationBasisSheetViewController scroll-stack shape
//     with smaller content (UI-SPEC line 470).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Sheet
// snapshots render the VC's `view` at the medium-detent representative
// size (~393×350 pt — naturally less dense than TRUST-03 per UI-SPEC
// line 470).
//
// === T-09-04 (PII) ===
// Synthetic `ChainOfTrustFactory` fixtures only. No real party names, no
// real tender references. Production fixtures are not loaded here.

import XCTest
@testable import validationLedger

class HandoffDetailSheetViewControllerSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// iPhone medium-detent representative canvas. The handoff sheet is
    /// less dense than the verification-basis sheet (UI-SPEC line 470), so
    /// the canvas is shorter (350 vs 500 pt).
    private static let sheetCanvasSize = CGSize(width: 393, height: 350)

    // MARK: - Helpers

    /// Layout the VC at the sheet canvas size and return the rendered view.
    private func renderedView(_ vc: HandoffDetailSheetViewController) -> UIView {
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(origin: .zero, size: Self.sheetCanvasSize)
        vc.view.layoutIfNeeded()
        return vc.view
    }

    /// Walk the entire subview tree and collect every descendant.
    private func collectAllSubviews(_ root: UIView) -> [UIView] {
        var result: [UIView] = []
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            result.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return result
    }

    /// Look up a node by partyID inside a chain.
    private func node(forPartyID partyID: String, in chain: ChainOfTrust) -> TrustNode {
        guard let node = chain.nodes.first(where: { $0.partyID == partyID }) else {
            preconditionFailure("test fixture missing party '\(partyID)'")
        }
        return node
    }

    /// Look up an edge by edgeID inside a chain.
    private func edge(forEdgeID edgeID: String, in chain: ChainOfTrust) -> TrustEdge {
        guard let edge = chain.edges.first(where: { $0.edgeID == edgeID }) else {
            preconditionFailure("test fixture missing edge '\(edgeID)'")
        }
        return edge
    }

    /// Build a copy of a TrustEdge with an overridden `tenderRef`. The
    /// memberwise initializer is synthesized; this helper keeps the call-
    /// site tidy.
    private func makeEdge(
        from base: TrustEdge,
        relationshipState: VerificationState? = nil,
        tenderRef: String?? = nil
    ) -> TrustEdge {
        TrustEdge(
            edgeID: base.edgeID,
            fromPartyID: base.fromPartyID,
            toPartyID: base.toPartyID,
            relationshipState: relationshipState ?? base.relationshipState,
            tenderRef: tenderRef ?? base.tenderRef
        )
    }

    // MARK: - 1. clean edge — basic rows, no implicated block

    func test_cleanEdge_rendersBasicRows() {
        // Clean chain; pick the verified broker→carrier edge (priors=[],
        // verified relationship, no implicated block).
        let chain = ChainOfTrustFactory.fiveNodeClean()
        let baseEdge = edge(forEdgeID: "edge-broker-carrier", in: chain)
        let cleanEdge = makeEdge(from: baseEdge, tenderRef: .some("TNDR-CLEAN-001"))
        let fromNode = node(forPartyID: cleanEdge.fromPartyID, in: chain)
        let toNode = node(forPartyID: cleanEdge.toPartyID, in: chain)

        let vc = HandoffDetailSheetViewController(
            edge: cleanEdge, fromNode: fromNode, toNode: toNode, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "HandoffDetailSheet-cleanEdge", to: self
        )

        let all = collectAllSubviews(view)

        // Root identifier — UI-SPEC line 782.
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.handoff-detail-sheet",
                       "root view must carry the locked sheet identifier")

        // Edge-partition identifier on a descendant — UI-SPEC line 783.
        // Either the root view OR a sibling descendant carries the partition
        // identifier; we accept either placement.
        let partitionID = "load-detail.handoff-detail-sheet.edge.\(cleanEdge.edgeID)"
        let hasPartition = all.contains(where: { $0.accessibilityIdentifier == partitionID })
            || view.accessibilityIdentifier == partitionID
        XCTAssertTrue(hasPartition,
                      "edge-partition identifier '\(partitionID)' must appear on either the root or a descendant view (UI-SPEC line 783)")

        // Clean verdict → NO implicated block.
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "load-detail.handoff-detail-sheet.implicated-block" },
                     "clean chain MUST NOT render the implicated block")
    }

    // MARK: - 2. caution × implicated — yellow-tinted implicated block

    func test_cautionImplicatedEdge_rendersImplicatedBlock() {
        // Caution verdict with the broker→carrier edge implicated.
        let edgeID = "edge-broker-carrier"
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: .caution,
            implicatedEdgeIDs: [edgeID]
        )
        let baseEdge = edge(forEdgeID: edgeID, in: chain)
        let cautionEdge = makeEdge(from: baseEdge,
                                   relationshipState: .pending,
                                   tenderRef: .some("TNDR-CAUTION-001"))
        let fromNode = node(forPartyID: cautionEdge.fromPartyID, in: chain)
        let toNode = node(forPartyID: cautionEdge.toPartyID, in: chain)

        let vc = HandoffDetailSheetViewController(
            edge: cautionEdge, fromNode: fromNode, toNode: toNode, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "HandoffDetailSheet-cautionImplicatedEdge", to: self
        )

        let all = collectAllSubviews(view)

        // D-11 — implicated block MUST render.
        guard let implicated = all.first(where: { $0.accessibilityIdentifier == "load-detail.handoff-detail-sheet.implicated-block" }) else {
            return XCTFail("implicated block MUST render when edgeID ∈ implicatedEdgeIDs (caution verdict)")
        }

        // UI-SPEC line 454/468 — caution → ~0.15 yellow tint background.
        let bg = implicated.backgroundColor
        XCTAssertNotNil(bg, "implicated block must have a tinted background")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let resolved = bg!.resolvedColor(with: lightTrait)
        let yellow = UIColor.systemYellow
            .withAlphaComponent(0.15)
            .resolvedColor(with: lightTrait)
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        yellow.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(Double(red), Double(r2), accuracy: 0.05, "implicated block tint must be ~yellow R")
        XCTAssertEqual(Double(green), Double(g2), accuracy: 0.05, "implicated block tint must be ~yellow G")
        XCTAssertEqual(Double(alpha), Double(a2), accuracy: 0.05, "implicated block alpha must be ~0.15")
    }

    // MARK: - 3. compromised × implicated — red tint + reason rendered verbatim

    func test_compromisedImplicatedEdge_rendersRedTintImplicatedBlock() {
        // Compromised verdict + implicated edge. The integrity.reason must
        // appear verbatim in the implicated block body (D-18 lock — server-
        // supplied text rendered as-is).
        let edgeID = "edge-broker-carrier"
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: .compromised,
            implicatedEdgeIDs: [edgeID]
        )
        let baseEdge = edge(forEdgeID: edgeID, in: chain)
        let compromisedEdge = makeEdge(from: baseEdge,
                                       relationshipState: .flagged,
                                       tenderRef: .some("TNDR-COMPROMISED-001"))
        let fromNode = node(forPartyID: compromisedEdge.fromPartyID, in: chain)
        let toNode = node(forPartyID: compromisedEdge.toPartyID, in: chain)

        let vc = HandoffDetailSheetViewController(
            edge: compromisedEdge, fromNode: fromNode, toNode: toNode, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "HandoffDetailSheet-compromisedImplicatedEdge", to: self
        )

        let all = collectAllSubviews(view)

        // D-11 — implicated block MUST render with red tint.
        guard let implicated = all.first(where: { $0.accessibilityIdentifier == "load-detail.handoff-detail-sheet.implicated-block" }) else {
            return XCTFail("implicated block MUST render for compromised + implicated edge")
        }
        let bg = implicated.backgroundColor
        XCTAssertNotNil(bg)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let resolved = bg!.resolvedColor(with: lightTrait)
        let red = DS.Colors.destructive
            .withAlphaComponent(0.15)
            .resolvedColor(with: lightTrait)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        resolved.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        red.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(Double(r1), Double(r2), accuracy: 0.05, "implicated block tint must be ~red R")
        XCTAssertEqual(Double(b1), Double(b2), accuracy: 0.05, "implicated block tint must be ~red B")
        XCTAssertEqual(Double(a1), Double(a2), accuracy: 0.05, "implicated block alpha must be ~0.15")

        // D-18 LOCK — `integrity.reason` rendered verbatim somewhere inside
        // the implicated block. The block's subtree must contain a label
        // whose text equals the server-supplied reason exactly.
        let expectedReason = chain.integrity.reason
        XCTAssertFalse(expectedReason.isEmpty,
                       "precondition: synthetic compromise reason should be non-empty")
        let implicatedSubtree = collectAllSubviews(implicated)
        let reasonLabels = implicatedSubtree.compactMap { $0 as? UILabel }.filter { $0.text == expectedReason }
        XCTAssertFalse(reasonLabels.isEmpty,
                       "D-18 — implicated block must render integrity.reason verbatim ('\(expectedReason)' not found in subtree)")
    }

    // MARK: - 4. null tenderRef — informational "No formal tender on file." line

    func test_nullTenderRef_rendersInformationalLine() {
        // UI-SPEC line 731 — when `tenderRef == nil`, the row renders the
        // informational sentence "No formal tender on file." as a `.body`
        // label (no icon, not alarming).
        let chain = ChainOfTrustFactory.fiveNodeClean()
        let baseEdge = edge(forEdgeID: "edge-broker-carrier", in: chain)
        let nilTenderEdge = makeEdge(from: baseEdge, tenderRef: .some(nil))
        XCTAssertNil(nilTenderEdge.tenderRef, "precondition: tenderRef must be nil")
        let fromNode = node(forPartyID: nilTenderEdge.fromPartyID, in: chain)
        let toNode = node(forPartyID: nilTenderEdge.toPartyID, in: chain)

        let vc = HandoffDetailSheetViewController(
            edge: nilTenderEdge, fromNode: fromNode, toNode: toNode, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "HandoffDetailSheet-nullTenderRef", to: self
        )

        let all = collectAllSubviews(view)

        // Locate the informational sentence verbatim.
        let infoText = "No formal tender on file."
        let matches = all.compactMap { $0 as? UILabel }.filter { $0.text == infoText }
        XCTAssertFalse(matches.isEmpty,
                       "UI-SPEC line 731 — when tenderRef is nil, '\(infoText)' MUST be rendered as a plain label")
    }
}
