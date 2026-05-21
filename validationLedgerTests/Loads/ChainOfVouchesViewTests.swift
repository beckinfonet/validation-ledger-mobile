// validationLedgerTests/Loads/ChainOfVouchesViewTests.swift
//
// Phase 9.1 Plan 04 Task 2 — ChainOfVouchesView tree-builder + footer-pill
// + D-15 supersedure unit tests.
//
// === Locked test surface (per Plan 04 PLAN Task 2 acceptance) ===
//   1. test_VL1001_rowCount_andAttribution_perRole
//      — 5 rows in canonical depth-first order shipper/broker/carrier/
//        dispatch/factoring; attribution prefixes
//        ROOT / VIA SHP / VIA BRK / VIA CAR / VIA CAR.
//
//   2. test_VL1005_threeRoles_attributionChain
//      — 3 rows ROOT / VIA SHP / VIA BRK.
//
//   3. test_VL1007_fourRoles_attributionChain
//      — 4 rows ROOT / VIA SHP / VIA BRK / VIA CAR.
//
//   4. test_VL1009_multiBrokerSiblings_bothBrokersAttributeToShipper
//      — 6 rows total; the two broker rows are at ADJACENT indices in
//        treeStack.arrangedSubviews; both broker rows' attribution
//        prefix labels read EXACTLY "VIA SHP" (R9 forced-siblings rule).
//
//   5. test_sparseChain_shipperPlusCarrier_carrierAttributesToShipper_pitfall7
//      — twoRoleShipperCarrierClean() — the carrier row's attribution
//        prefix is "VIA SHP" (walks UP the canonical hierarchy when
//        BRK is missing), NOT "VIA BRK".
//
//   6. test_footerPill_renders_for_cleanVerdict_withGreenTint
//      — clean-verdict chain: footer pill is NOT hidden; its background
//        color alpha is between 0.1 and 0.3 (the soft green tint);
//        pillLabel text contains "Chain intact".
//
//   7. test_footerPill_renders_for_cautionVerdict
//      — footer pill background == DS.Colors.caution; label contains
//        "Risk flagged".
//
//   8. test_footerPill_renders_for_compromisedVerdict
//      — footer pill background == DS.Colors.destructive; label
//        contains "Chain compromised".
//
//   9. test_D15_supersedure_allRowsRenderAtFullAlpha_evenForCompromisedFixture
//      — VL-1010 (compromised): EVERY row.alpha == 1.0. R7 forbids
//        dim-others on iPhone; the footer pill is the sole signal.
//
//  10. test_D15_supersedure_noPulseHaloLayer_onAnyRow
//      — iterate each row's layer.sublayers; assert NO sublayer has
//        animation(forKey: "pulse") or name == "pulse-halo".
//
// === Why XCTest, not Swift Testing ===
// Matches the in-repo convention (TrustGraphViewLayoutTests,
// TrustGraphViewAccessibilityTests, EveryoneOnLoadStripViewTests at
// Plan 03). UIKit introspection (treeStack.arrangedSubviews,
// row.accessibilityLabel) is XCTest-native.
//
// === T-09.1-02 (PII) ===
// Every party displayName referenced in tests comes from the synthetic
// ChainOfTrustFactory fixtures (vl1001_…/vl1010_…/twoRoleShipperCarrierClean).
// The factory comments document the PII-zero posture.

import XCTest
@testable import validationLedger

final class ChainOfVouchesViewTests: XCTestCase {

    // MARK: - Helpers

    /// Build a tree, configure with the fixture, force a layout pass.
    /// Mirrors TrustGraphViewLayoutTests.makeLaidOutView (lines 58-81).
    private func makeTree(for chain: ChainOfTrust) -> ChainOfVouchesView {
        let view = ChainOfVouchesView()
        view.bounds = CGRect(x: 0, y: 0, width: 390, height: 600)
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()
        return view
    }

    /// Convenience: pull the tree's rows in their canonical order.
    private func rows(in view: ChainOfVouchesView) -> [ChainOfVouchesRowView] {
        view.treeStack.arrangedSubviews.compactMap { $0 as? ChainOfVouchesRowView }
    }

    // MARK: - 1. VL-1001 — 5 rows, full attribution chain

    func test_VL1001_rowCount_andAttribution_perRole() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 5,
                       "VL-1001 has 5 nodes (one per role) -> 5 rows. Got \(allRows.count).")

        let expectedRoles: [Role] = [.shipper, .broker, .carrier, .dispatch, .factoring]
        let actualRoles = allRows.compactMap { $0.node?.role }
        XCTAssertEqual(actualRoles, expectedRoles,
                       "Rows must be ordered SHP -> BRK -> CAR -> DSP -> FCT. Got: \(actualRoles)")

        let expectedAttributions = ["ROOT", "VIA SHP", "VIA BRK", "VIA CAR", "VIA CAR"]
        let actualAttributions = allRows.map { $0.attributionPrefixLabel.text ?? "" }
        XCTAssertEqual(actualAttributions, expectedAttributions,
                       "Attribution suffixes must follow the LOCKED role-hierarchy parent table. Got: \(actualAttributions)")
    }

    // MARK: - 2. VL-1005 — 3 rows

    func test_VL1005_threeRoles_attributionChain() {
        let view = makeTree(for: ChainOfTrustFactory.vl1005_threeRolesClean())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 3,
                       "VL-1005 has 3 nodes (shipper, broker, carrier) -> 3 rows. Got \(allRows.count).")

        let actualAttributions = allRows.map { $0.attributionPrefixLabel.text ?? "" }
        XCTAssertEqual(actualAttributions, ["ROOT", "VIA SHP", "VIA BRK"],
                       "VL-1005 attributions must be ROOT / VIA SHP / VIA BRK. Got: \(actualAttributions)")
    }

    // MARK: - 3. VL-1007 — 4 rows

    func test_VL1007_fourRoles_attributionChain() {
        let view = makeTree(for: ChainOfTrustFactory.vl1007_fourRolesClean())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 4,
                       "VL-1007 has 4 nodes (shipper, broker, carrier, dispatch) -> 4 rows. Got \(allRows.count).")

        let actualAttributions = allRows.map { $0.attributionPrefixLabel.text ?? "" }
        XCTAssertEqual(actualAttributions, ["ROOT", "VIA SHP", "VIA BRK", "VIA CAR"],
                       "VL-1007 attributions must be ROOT / VIA SHP / VIA BRK / VIA CAR. Got: \(actualAttributions)")
    }

    // MARK: - 4. VL-1009 — multi-broker forced-siblings rule (R9)

    /// THE binding assertion for R9 — VL-1009 has two brokers + 1 each
    /// of every other role = 6 nodes total. BOTH brokers must render at
    /// adjacent indices in the tree stack, BOTH with attribution
    /// "VIA SHP" (the role-hierarchy parent table drives attribution,
    /// NOT edges[].fromPartyID).
    func test_VL1009_multiBrokerSiblings_bothBrokersAttributeToShipper() {
        let view = makeTree(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 6,
                       "VL-1009 has 6 nodes (SHP + 2x BRK + CAR + DSP + FCT) -> 6 rows. Got \(allRows.count).")

        // Identify the broker row indices in the stack.
        let brokerIndices: [Int] = allRows.enumerated().compactMap { (idx, row) in
            row.node?.role == .broker ? idx : nil
        }
        XCTAssertEqual(brokerIndices.count, 2,
                       "VL-1009 must produce EXACTLY 2 broker rows (R9 — tree does NOT collapse; only the strip does).")

        if brokerIndices.count == 2 {
            XCTAssertEqual(brokerIndices[1] - brokerIndices[0], 1,
                           "The two broker rows must be ADJACENT indices in the tree stack (siblings). Got indices \(brokerIndices).")
        }

        let brokerRows = allRows.filter { $0.node?.role == .broker }
        let brokerAttributions = brokerRows.map { $0.attributionPrefixLabel.text ?? "" }
        XCTAssertEqual(brokerAttributions, ["VIA SHP", "VIA SHP"],
                       "R9: BOTH broker rows must attribute to SHP. Got: \(brokerAttributions)")
    }

    // MARK: - 5. Sparse chain (Pitfall 7) — SHP+CAR only

    /// Pitfall 7 sparse-chain fallback: the carrier's attribution walks
    /// UP the canonical hierarchy when BRK is missing and lands on SHP
    /// ("VIA SHP"), NOT a non-existent "VIA BRK".
    func test_sparseChain_shipperPlusCarrier_carrierAttributesToShipper_pitfall7() {
        let view = makeTree(for: ChainOfTrustFactory.twoRoleShipperCarrierClean())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 2, "Sparse chain has 2 nodes -> 2 rows.")

        guard let carrierRow = allRows.first(where: { $0.node?.role == .carrier }) else {
            XCTFail("Sparse chain must produce a CAR row.")
            return
        }
        XCTAssertEqual(carrierRow.attributionPrefixLabel.text, "VIA SHP",
                       "Pitfall 7: sparse-chain CAR (no BRK) must attribute to SHP. Got: \(carrierRow.attributionPrefixLabel.text ?? "<nil>")")
    }

    // MARK: - 6. Footer pill — clean verdict (R4 divergence)

    /// R4 divergence vs Phase 9 ChainIntegrityBannerView (which hides on
    /// .clean): the 9.1 folded footer pill MUST render on .clean with a
    /// soft green tint and the affirmative "Chain intact ." cadence.
    func test_footerPill_renders_for_cleanVerdict_withGreenTint() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        let pill = view.footerPill

        XCTAssertFalse(pill.isHidden,
                       "Footer pill must NOT hide on .clean (R4 divergence vs Phase 9 banner).")

        var alpha: CGFloat = 0
        pill.backgroundColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertTrue(alpha >= 0.1 && alpha <= 0.3,
                      "Clean-tier footer pill background alpha must be in the soft-tint range [0.1, 0.3]. Got: \(alpha)")

        let labelText = pill.pillLabel.text ?? ""
        XCTAssertTrue(labelText.contains("Chain intact"),
                      "Clean-tier footer pill copy must contain 'Chain intact'. Got: \"\(labelText)\"")
    }

    // MARK: - 7. Footer pill — caution verdict

    func test_footerPill_renders_for_cautionVerdict() {
        let view = makeTree(for: ChainOfTrustFactory.vl1005_threeRolesClean())
        let pill = view.footerPill

        XCTAssertEqual(pill.backgroundColor, DS.Colors.caution,
                       "Caution-tier footer pill background must equal DS.Colors.caution. Got: \(String(describing: pill.backgroundColor))")

        let labelText = pill.pillLabel.text ?? ""
        XCTAssertTrue(labelText.contains("Risk flagged"),
                      "Caution-tier footer pill copy must contain 'Risk flagged'. Got: \"\(labelText)\"")
    }

    // MARK: - 8. Footer pill — compromised verdict

    func test_footerPill_renders_for_compromisedVerdict() {
        let view = makeTree(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        let pill = view.footerPill

        XCTAssertEqual(pill.backgroundColor, DS.Colors.destructive,
                       "Compromised-tier footer pill background must equal DS.Colors.destructive. Got: \(String(describing: pill.backgroundColor))")

        let labelText = pill.pillLabel.text ?? ""
        XCTAssertTrue(labelText.contains("Chain compromised"),
                      "Compromised-tier footer pill copy must contain 'Chain compromised'. Got: \"\(labelText)\"")
    }

    // MARK: - 9. R7 supersedure — full alpha on every row, even compromised

    /// R7 forbids any row-level fraud signaling on iPhone. ALL rows
    /// render at full alpha regardless of verdict / implicated set;
    /// the footer pill is the sole fraud signal.
    func test_D15_supersedure_allRowsRenderAtFullAlpha_evenForCompromisedFixture() {
        let view = makeTree(for: ChainOfTrustFactory.vl1010_compromisedChain())
        let allRows = rows(in: view)
        XCTAssertFalse(allRows.isEmpty, "Pre-condition: VL-1010 produces at least one row.")

        for row in allRows {
            XCTAssertEqual(row.alpha, 1.0, accuracy: 0.001,
                           "R7: every row must render at alpha 1.0 regardless of verdict. Row \(row.node?.role.displayName ?? "?") -> alpha \(row.alpha).")
        }
    }

    // MARK: - 10. R7 supersedure — no pulse halo layer on any row

    /// R7 forbids pulse halo / pulse animation on rows. Iterate every
    /// row's CALayer sublayers; assert NO sublayer has an animation
    /// keyed "pulse" and NO sublayer's name is "pulse-halo".
    func test_D15_supersedure_noPulseHaloLayer_onAnyRow() {
        let view = makeTree(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        let allRows = rows(in: view)
        XCTAssertFalse(allRows.isEmpty, "Pre-condition: VL-1009 produces at least one row.")

        for row in allRows {
            let sublayers = row.layer.sublayers ?? []
            for sub in sublayers {
                XCTAssertNil(sub.animation(forKey: "pulse"),
                             "R7: no row may carry a 'pulse' animation. Row \(row.node?.role.displayName ?? "?") sublayer \(sub) has one.")
                XCTAssertNotEqual(sub.name, "pulse-halo",
                                  "R7: no row's sublayer may be named 'pulse-halo'. Row \(row.node?.role.displayName ?? "?") has one.")
            }
        }
    }
}
