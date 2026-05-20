// validationLedgerTests/Loads/TrustGraphViewLayoutTests.swift
//
// Phase 9 device-UAT bug regression — Phase 9 trust-graph rendering
// (2026-05-20). See debug session `.planning/debug/trust-graph-device-bugs.md`.
//
// === What this test pins ===
// Each per-node TrustNodeView ends up at the role-slot position the
// `iPhoneSlots` / `iPadSlots` tables in TrustGraphView declare — NOT
// collapsed to (0, 0).
//
// === The bug this catches ===
// The Phase 9 implementation set
// `v.translatesAutoresizingMaskIntoConstraints = false` on each freshly
// allocated TrustNodeView inside `TrustGraphView.configure(chainOfTrust:)`.
// Combined with the frame-write-driven layout in `layoutSubviews()` (which
// does `nodeView.frame = CGRect(...)`), TAMIC = false instructed Auto Layout
// to OVERRIDE the frame writes from the constraint engine. Because
// TrustNodeView declares only internal stack + 44pt intrinsic-size
// constraints — NO positioning constraints — Auto Layout placed every
// node at (0, 0) with intrinsic size, stacking every node tile on the
// canvas origin. The device-side symptom was scrambled overlapping text
// in multi-node chains (VL-1001 / VL-1009 / VL-1010) and an apparently-
// solid pink-red rounded square mid-canvas on compromised chains
// (VL-1009 / VL-1010) — the latter being the halo CAShapeLayer drawn at
// its slot center with no node chrome on top to occlude it.
//
// The fix flips that single line to `= true`. This test pins the
// invariant at the layout level so a future re-introduction fails CI
// instead of shipping to device UAT.
//
// === Why a layout test, not a snapshot test ===
// `UIKitSnapshot.attach(...)` writes pixels to an XCTAttachment for
// human triage — there is NO baseline diff. So the existing
// TrustGraphViewSnapshotTests would not have caught Bug A (and didn't).
// Frame assertions are deterministic and CI-meaningful.

import XCTest
@testable import validationLedger

final class TrustGraphViewLayoutTests: XCTestCase {

    // The canonical iPhone-portrait canvas used by accessibility tests.
    private static let iPhoneCanvas = CGSize(width: 393, height: 600)

    // The role-slot fractional coordinates that TrustGraphView.iPhoneSlots
    // declares (`private static let iPhoneSlots: [Role: CGPoint] = ...`).
    // Mirrored here because the table is private to TrustGraphView; if the
    // table changes, BOTH this expected map AND the production table must
    // change in lockstep — that lockstep is the contract this test pins.
    private static let expectedIPhoneSlots: [Role: CGPoint] = [
        .shipper:   CGPoint(x: 0.18, y: 0.18),
        .broker:    CGPoint(x: 0.50, y: 0.30),
        .carrier:   CGPoint(x: 0.50, y: 0.55),
        .dispatch:  CGPoint(x: 0.82, y: 0.55),
        .factoring: CGPoint(x: 0.50, y: 0.85),
    ]

    private func makeLaidOutView(
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
        // Pulse-suppress so the compromised path is deterministic.
        v.reduceMotionOverride = true
        // Match the existing accessibility-tests pattern: set bounds at
        // the canonical iPhone-portrait canvas, configure, layoutIfNeeded.
        // The production fix in TrustGraphView.layoutSubviews() forces the
        // inner scroll-view / contentContainer constraint chain to flush
        // BEFORE reading the canvas — so the assertions in this suite
        // exercise the same code path on the simulator as on device.
        v.bounds = CGRect(origin: .zero, size: Self.iPhoneCanvas)
        v.configure(chainOfTrust: chain)
        v.layoutIfNeeded()
        return v
    }

    /// Pull the TrustNodeView instances out of the published
    /// accessibilityElements prefix (D-22 ordering — first N are nodes in
    /// fixed role order shipper → broker → carrier → dispatch → factoring).
    private func nodeViews(of view: TrustGraphView) -> [TrustNodeView] {
        let elements = view.accessibilityElements ?? []
        return elements.prefix(5).compactMap { $0 as? TrustNodeView }
    }

    // MARK: - The Bug A regression

    /// REGRESSION — Phase 9 trust-graph device-UAT bug 2026-05-20.
    ///
    /// Every TrustNodeView must end up at a DISTINCT non-origin position
    /// driven by the role-slot table. The buggy state stacked every node
    /// at (0, 0); this assertion fails loudly if that ever returns.
    func test_nodeFrames_areDistinctAndPositionedFromRoleSlots() throws {
        let view = makeLaidOutView()
        let nodes = nodeViews(of: view)
        XCTAssertEqual(nodes.count, 5,
                       "Canonical 5-node fixture must produce 5 TrustNodeView leaves in the accessibility container.")

        // 1) No two nodes share a center.
        var seen: [CGPoint] = []
        for n in nodes {
            for s in seen {
                let dx = abs(s.x - n.center.x)
                let dy = abs(s.y - n.center.y)
                XCTAssertFalse(dx < 1.0 && dy < 1.0,
                               "Two TrustNodeView centers within 1pt of each other (\(s) vs \(n.center)) — Bug A regression: TAMIC was probably re-flipped to false in TrustGraphView.configure(...).")
            }
            seen.append(n.center)
        }

        // 2) No node is parked at (0, 0) — the canonical buggy collapse.
        for n in nodes {
            XCTAssertFalse(n.frame.origin == .zero,
                           "TrustNodeView for partyID=\(n.partyID) is at frame.origin == (0, 0) — Bug A regression: the layoutSubviews frame write is being overridden by Auto Layout.")
        }

        // 3) Each node's center matches `canvas * iPhoneSlots[role]` within
        // 1pt. Pinned via a lookup keyed by partyID → role; the factory
        // uses `party-<rolename>` for each canonical role.
        let canvas = Self.iPhoneCanvas
        let roleByPartyID: [String: Role] = [
            "party-shipper":   .shipper,
            "party-broker":    .broker,
            "party-carrier":   .carrier,
            "party-dispatch":  .dispatch,
            "party-factoring": .factoring,
        ]
        for n in nodes {
            guard let role = roleByPartyID[n.partyID],
                  let slot = Self.expectedIPhoneSlots[role] else {
                XCTFail("Unknown partyID/role mapping: \(n.partyID)")
                continue
            }
            let expectedCX = canvas.width * slot.x
            let expectedCY = canvas.height * slot.y
            XCTAssertEqual(n.center.x, expectedCX, accuracy: 1.0,
                           "Node \(n.partyID) center.x mismatch: expected canvas.w * \(slot.x) = \(expectedCX), got \(n.center.x).")
            XCTAssertEqual(n.center.y, expectedCY, accuracy: 1.0,
                           "Node \(n.partyID) center.y mismatch: expected canvas.h * \(slot.y) = \(expectedCY), got \(n.center.y).")
        }
    }

    // MARK: - The Bug B regression (halo correctly under chrome)

    /// REGRESSION — Phase 9 trust-graph device-UAT Bug B 2026-05-20.
    ///
    /// On a compromised chain, the red halo CAShapeLayer must be located
    /// such that the implicated node's chrome paints OVER it (the halo
    /// frames the chrome, the chrome doesn't disappear from over the
    /// halo). Concretely: the implicated TrustNodeView's frame must
    /// CONTAIN the halo path's bounding box's center — i.e. the halo is
    /// centered on the same point as the node chrome. The buggy state
    /// painted the halo at the slot center while the chrome was parked
    /// at (0, 0), exposing a bare red square.
    func test_compromisedHalo_isCenteredOnImplicatedNodeChrome() throws {
        let view = makeLaidOutView(
            verdict: .compromised,
            implicatedNodeIDs: ["party-carrier"],
            implicatedEdgeIDs: ["edge-broker-carrier"]
        )
        let nodes = nodeViews(of: view)
        guard let carrier = nodes.first(where: { $0.partyID == "party-carrier" }) else {
            XCTFail("Carrier node must be present in the role-ordered prefix.")
            return
        }
        let halos = view._testHaloLayers()
        XCTAssertEqual(halos.count, 1,
                       "Exactly one halo expected for the single implicated carrier — got \(halos.count).")
        guard let halo = halos.first, let path = halo.path else {
            XCTFail("Implicated halo must carry a CGPath after layout.")
            return
        }
        let haloBBox = path.boundingBox
        let haloCenter = CGPoint(x: haloBBox.midX, y: haloBBox.midY)
        let chromeCenter = carrier.center
        XCTAssertEqual(haloCenter.x, chromeCenter.x, accuracy: 1.0,
                       "Halo center.x must match implicated node chrome center.x — otherwise the halo paints uncovered as a bare red square (Bug B). halo=\(haloCenter) chrome=\(chromeCenter).")
        XCTAssertEqual(haloCenter.y, chromeCenter.y, accuracy: 1.0,
                       "Halo center.y must match implicated node chrome center.y — otherwise the halo paints uncovered as a bare red square (Bug B). halo=\(haloCenter) chrome=\(chromeCenter).")
    }
}
