// validationLedgerTests/Loads/ChainOfVouchesViewAccessibilityTests.swift
//
// Phase 9.1 Plan 04 Task 2 — ChainOfVouchesView leaf-element accessibility
// assertions (R6 binding + B2 wiring).
//
// === Locked test surface (per Plan 04 PLAN Task 2 acceptance) ===
//   (a) test_container_isAccessibilityElement_false_forVL1001
//       — Container is NOT a leaf (R6 leaf-element model).
//
//   (b) test_eachRow_isAccessibilityLeaf_withStaticTextTrait
//       — Every row is a leaf with .staticText (NOT .button — tree
//         rows are non-interactive per CONTEXT `<deferred>`).
//
//   (c) test_rootRow_a11yLabel_containsRootOfChain
//       — VL-1001's shipper row label starts with "Shipper " AND
//         contains "root of the chain" AND ends with "verified".
//
//   (d) test_nonRootRow_a11yLabel_containsVouchedBy
//       — VL-1001's broker row label starts with "Broker " AND
//         contains "vouched by Shipper " AND ends with "verified".
//
//   (e) test_footerPill_a11yLeaf
//       — Footer pill isAccessibilityElement == true, traits
//         contain .staticText, label contains "Chain integrity".
//
//   (f) test_VL1009_bothBrokerRows_a11yLabels_carryPerNodeState
//       — VL-1009's two broker rows publish their PER-NODE state in
//         the composed label: one ends with "flagged", one ends with
//         "verified". NOT collapsed.
//
// === T-09.1-02 (PII) ===
// The B2-wired composed labels embed party `displayName` values — PII-
// class data. These tests never log a row's accessibilityLabel via
// os_log/Logger/print; assertions surface failures via XCTest only.

import XCTest
@testable import validationLedger

final class ChainOfVouchesViewAccessibilityTests: XCTestCase {

    // MARK: - Helpers

    private func makeTree(for chain: ChainOfTrust) -> ChainOfVouchesView {
        let view = ChainOfVouchesView()
        view.bounds = CGRect(x: 0, y: 0, width: 390, height: 600)
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()
        return view
    }

    private func rows(in view: ChainOfVouchesView) -> [ChainOfVouchesRowView] {
        view.treeStack.arrangedSubviews.compactMap { $0 as? ChainOfVouchesRowView }
    }

    // MARK: - (a) Container is NOT a leaf

    func test_container_isAccessibilityElement_false_forVL1001() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        XCTAssertFalse(view.isAccessibilityElement,
                       "R6: ChainOfVouchesView container must NOT be a VoiceOver leaf.")
    }

    // MARK: - (b) Each row is a leaf with .staticText (NOT .button)

    func test_eachRow_isAccessibilityLeaf_withStaticTextTrait() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        let allRows = rows(in: view)
        XCTAssertEqual(allRows.count, 5, "Pre-condition: VL-1001 produces 5 rows.")

        for row in allRows {
            XCTAssertTrue(row.isAccessibilityElement,
                          "R6: every tree row must be an accessibility leaf. Row \(row.node?.role.displayName ?? "?") is not.")
            XCTAssertTrue(row.accessibilityTraits.contains(.staticText),
                          "R6: every tree row must carry .staticText. Row \(row.node?.role.displayName ?? "?") does not.")
            XCTAssertFalse(row.accessibilityTraits.contains(.button),
                           "Tree rows are non-interactive in 9.1 (CONTEXT <deferred>) — must NOT carry .button. Row \(row.node?.role.displayName ?? "?") does.")
        }
    }

    // MARK: - (c) Root row composed label

    /// UI-SPEC §Accessibility Contract — root row template:
    /// "<RoleDisplayName> <DisplayName>, root of the chain, <stateCopy>"
    /// e.g. "Shipper Pacific Goods LLC, root of the chain, verified".
    func test_rootRow_a11yLabel_containsRootOfChain() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        guard let shipperRow = rows(in: view).first(where: { $0.node?.role == .shipper }) else {
            XCTFail("VL-1001 must produce a SHP row.")
            return
        }
        let label = shipperRow.accessibilityLabel ?? ""
        XCTAssertTrue(label.hasPrefix("Shipper "),
                      "Root row label must start with 'Shipper '. Got: \"\(label)\"")
        XCTAssertTrue(label.contains("root of the chain"),
                      "Root row label must contain 'root of the chain'. Got: \"\(label)\"")
        XCTAssertTrue(label.hasSuffix("verified"),
                      "Root row label must end with 'verified' for VL-1001's verified shipper. Got: \"\(label)\"")
    }

    // MARK: - (d) Non-root row composed label

    /// UI-SPEC §Accessibility Contract — non-root row template:
    /// "<RoleDisplayName> <DisplayName>, vouched by <ParentRoleDisplayName> <ParentDisplayName>, <stateCopy>"
    /// e.g. "Broker FreightWise Brokerage, vouched by Shipper Pacific Goods LLC, verified".
    func test_nonRootRow_a11yLabel_containsVouchedBy() {
        let view = makeTree(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        guard let brokerRow = rows(in: view).first(where: { $0.node?.role == .broker }) else {
            XCTFail("VL-1001 must produce a BRK row.")
            return
        }
        let label = brokerRow.accessibilityLabel ?? ""
        XCTAssertTrue(label.hasPrefix("Broker "),
                      "Non-root row label must start with 'Broker '. Got: \"\(label)\"")
        XCTAssertTrue(label.contains("vouched by Shipper "),
                      "Non-root row label must contain 'vouched by Shipper '. Got: \"\(label)\"")
        XCTAssertTrue(label.hasSuffix("verified"),
                      "VL-1001 broker row must end with 'verified'. Got: \"\(label)\"")
    }

    // MARK: - (e) Footer pill is its own leaf

    func test_footerPill_a11yLeaf() {
        let view = makeTree(for: ChainOfTrustFactory.vl1005_threeRolesClean())
        let pill = view.footerPill

        XCTAssertTrue(pill.isAccessibilityElement,
                      "R6: footer pill must be its OWN VoiceOver leaf.")
        XCTAssertTrue(pill.accessibilityTraits.contains(.staticText),
                      "R6: footer pill traits must include .staticText.")

        let label = pill.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Chain integrity"),
                      "R6: footer pill composed label must contain 'Chain integrity'. Got: \"\(label)\"")
    }

    // MARK: - (f) VL-1009 — both broker rows carry per-node state

    /// VL-1009 has two brokers with DIFFERENT verification states
    /// (FreightWise .verified, Keystone .flagged). The tree-builder
    /// does NOT collapse them; each row's composed label reflects its
    /// PER-NODE verification state.
    func test_VL1009_bothBrokerRows_a11yLabels_carryPerNodeState() {
        let view = makeTree(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        let brokerRows = rows(in: view).filter { $0.node?.role == .broker }
        XCTAssertEqual(brokerRows.count, 2,
                       "VL-1009 must produce 2 broker rows (the tree does NOT collapse; only the strip does).")

        let brokerLabels = brokerRows.compactMap { $0.accessibilityLabel }
        XCTAssertEqual(brokerLabels.count, 2, "Both broker rows must publish non-nil accessibility labels.")

        // Exactly one row's label ends with "flagged"; exactly one ends with "verified".
        let flaggedCount = brokerLabels.filter { $0.hasSuffix("flagged") }.count
        let verifiedCount = brokerLabels.filter { $0.hasSuffix("verified") }.count
        XCTAssertEqual(flaggedCount, 1,
                       "Exactly one broker row's label must end with 'flagged' (per-node state, NOT collapsed). Got labels: \(brokerLabels)")
        XCTAssertEqual(verifiedCount, 1,
                       "Exactly one broker row's label must end with 'verified' (per-node state, NOT collapsed). Got labels: \(brokerLabels)")
    }
}
