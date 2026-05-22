// validationLedgerTests/Loads/EveryoneOnLoadStripViewTests.swift
//
// Phase 9.1 Plan 03 Task 2 — EveryoneOnLoadStripView unit tests.
//
// === Locked test surface (per Plan 03 PLAN Task 2 acceptance) ===
//   1. test_chipCount_per_fixture
//      — 5 fixtures (VL-1001/1003/1005/1007/1009) assert chip count
//        matches expected (5/2/3/4/5). VL-1009's 6 nodes collapse to 5
//        chips per R2 + D-10 (duplicate broker collapse).
//
//   2. test_chipOrder_canonical_shipper_broker_carrier_dispatch_factoring
//      — VL-1001 (all 5 roles present) asserts canonical order
//        SHP → BRK → CAR → DSP → FCT.
//
//   3. test_VL1009_duplicateBroker_collapses_to_one_chip
//      — VL-1009 chip count = 5 (not 6) — the two-broker collapse.
//
//   4. test_VL1009_collapsedBrokerChip_a11yLabel_isThreeFieldAndCarriesMostSuspiciousState
//      — The collapsed BRK chip's accessibilityLabel:
//        * splits on ", " into EXACTLY 3 components (3-field per SPEC R6
//          binding);
//        * component[0] == "Broker";
//        * component[1] == "multiple parties" (planner-default
//          multi-node displayName per B1);
//        * component[2] == "flagged" (most-suspicious wins per
//          RESEARCH §Open Q1).
//
//   5. test_singleNodeChip_a11yLabel_isThreeFieldAndUsesNodeDisplayName
//      — For VL-1001's Shipper chip (single-node role):
//        * 3 components (3-field per SPEC R6 binding);
//        * component[0] == "Shipper";
//        * component[1] == "Pacific Goods LLC" (the VL-1001 shipper
//          node's displayName);
//        * component[2] == "verified".
//
//   6. test_onRoleTap_closure_fires_with_tappedRole
//      — Setting `onRoleTap = { ... }`, then invoking the ChipView's
//        internal `onTap` closure, fires exactly one Role and it
//        matches the chip's role.
//
//   7. test_container_isAccessibilityElement_false
//      — Container is NOT a VoiceOver leaf (R6 leaf-element model).
//
//   8. test_eachChip_isAccessibilityLeaf_withButtonAndStaticTextTraits
//      — Every chip is a leaf with both .button and .staticText traits
//        (R6 + D-08).
//
//   9. test_trailingCaption_matchesLockedLocalizedString
//      — Caption text equals exactly the LOCKED localized value
//        "All watching live\u{00A0}·\u{00A0}tap for details" (UI-SPEC
//        §Copywriting Contract; non-breaking-space middle-dot separator).
//
// === Why XCTest, not Swift Testing ===
// Matches the in-repo convention established by the Phase 9 trust-graph
// accessibility tests (TrustGraphViewAccessibilityTests at lines 26-32) and
// Plan 02 RoleAvatarViewTests. The accessibilityElement / accessibilityLabel
// introspection used here is XCTest-native.
//
// === T-09.1-02 (PII) ===
// Every party displayName referenced in tests comes from the synthetic
// ChainOfTrustFactory fixtures (vl1001_…/vl1009_…). The factory comments
// document its PII-zero posture. These tests never log a chip's
// accessibilityLabel via os_log/Logger/print — assertions surface
// failures via XCTest only.

import XCTest
@testable import validationLedger

final class EveryoneOnLoadStripViewTests: XCTestCase {

    // MARK: - Helpers

    /// Build a strip, set a fixed iPhone-15-portrait-ish bounds, configure
    /// with the fixture chain, force layout. Matches TrustGraphViewAccessibilityTests
    /// makeView() precedent (lines 32-47).
    private func makeStrip(for chain: ChainOfTrust) -> EveryoneOnLoadStripView {
        let view = EveryoneOnLoadStripView()
        view.bounds = CGRect(x: 0, y: 0, width: 390, height: 80)
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()
        return view
    }

    /// Locate the chip whose `role == role`. Returns the FIRST such chip
    /// (in the strip's canonical-order chip array) — there is at most one
    /// chip per role by R2's de-dup rule.
    private func chip(for role: Role, in view: EveryoneOnLoadStripView) -> EveryoneOnLoadStripView.ChipView? {
        return view.chips.first { $0.role == role }
    }

    // MARK: - 1. Chip count per fixture (R2)

    /// VL-1003 (2 distinct roles) → 2 chips.
    func test_chipCount_VL1003_twoRoles_rendersTwoChips() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1003_twoRolesClean())
        XCTAssertEqual(view.chips.count, 2,
                       "VL-1003 has 2 distinct roles (shipper, broker) → 2 chips.")
    }

    /// VL-1005 (3 distinct roles) → 3 chips.
    func test_chipCount_VL1005_threeRoles_rendersThreeChips() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1005_threeRolesClean())
        XCTAssertEqual(view.chips.count, 3,
                       "VL-1005 has 3 distinct roles (shipper, broker, carrier) → 3 chips.")
    }

    /// VL-1007 (4 distinct roles) → 4 chips.
    func test_chipCount_VL1007_fourRoles_rendersFourChips() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1007_fourRolesClean())
        XCTAssertEqual(view.chips.count, 4,
                       "VL-1007 has 4 distinct roles (shipper, broker, carrier, dispatch) → 4 chips.")
    }

    /// VL-1001 (5 distinct roles) → 5 chips.
    func test_chipCount_VL1001_fiveRoles_rendersFiveChips() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        XCTAssertEqual(view.chips.count, 5,
                       "VL-1001 has all 5 distinct roles → 5 chips.")
    }

    /// VL-1009 (6 nodes, 5 distinct roles — two brokers collapse) → 5 chips.
    func test_chipCount_VL1009_sixNodesFiveDistinctRoles_rendersFiveChips() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        XCTAssertEqual(view.chips.count, 5,
                       "VL-1009 has 6 nodes / 5 distinct roles — the two brokers collapse to ONE BRK chip (R2 + D-10).")
    }

    // MARK: - 2. Canonical chip order (R2)

    /// VL-1001 has all 5 roles. Chip order MUST be the canonical
    /// shipper → broker → carrier → dispatch → factoring.
    func test_chipOrder_canonical_shipper_broker_carrier_dispatch_factoring() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        let expected: [Role] = [.shipper, .broker, .carrier, .dispatch, .factoring]
        let actual = view.chips.map { $0.role }
        XCTAssertEqual(actual, expected,
                       "Chip order must follow the canonical role hierarchy SHP → BRK → CAR → DSP → FCT. Got: \(actual)")
    }

    // MARK: - 3. VL-1009 duplicate broker collapse

    /// Repeats the chip-count assertion above with a more explicit name —
    /// surfaces the collapse rule loudly in CI test reports.
    func test_VL1009_duplicateBroker_collapses_to_one_chip() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        XCTAssertEqual(view.chips.count, 5,
                       "VL-1009: 6 nodes (SHP + 2× BRK + CAR + DSP + FCT) → 5 chips. The duplicate broker MUST collapse to one BRK chip.")

        // Belt-and-suspenders: assert there is EXACTLY ONE broker chip.
        let brokerChips = view.chips.filter { $0.role == .broker }
        XCTAssertEqual(brokerChips.count, 1,
                       "After collapse, exactly one BRK chip must exist for VL-1009.")
    }

    // MARK: - 4. VL-1009 collapsed BRK chip — 3-field a11y label + most-suspicious wins

    /// THE binding assertion for D-10 + SPEC R6:
    ///   - 3 components (split on ", ")
    ///   - component[0] == "Broker"
    ///   - component[1] == "multiple parties" (B1 planner-default)
    ///   - component[2] == "flagged" (most-suspicious wins per RESEARCH §Open Q1)
    func test_VL1009_collapsedBrokerChip_a11yLabel_isThreeFieldAndCarriesMostSuspiciousState() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised())
        guard let brokerChip = chip(for: .broker, in: view) else {
            XCTFail("VL-1009 must produce a BRK chip after collapse.")
            return
        }
        guard let label = brokerChip.accessibilityLabel, !label.isEmpty else {
            XCTFail("BRK chip must publish a non-empty accessibilityLabel (R6 leaf-element model).")
            return
        }

        // 3-field per SPEC R6 (binding). UI-SPEC line 298's 2-field
        // shorthand is SUPERSEDED.
        let components = label.components(separatedBy: ", ")
        XCTAssertEqual(components.count, 3,
                       "BRK chip a11y label must have EXACTLY 3 fields (SPEC R6 binding). Got components: \(components) — full label: \"\(label)\"")

        if components.count == 3 {
            XCTAssertEqual(components[0], "Broker",
                           "Field 1 must be the role's displayName 'Broker'. Got: \(components[0])")
            XCTAssertEqual(components[1], "multiple parties",
                           "Field 2 for the multi-node collapsed BRK chip must be the planner-default 'multiple parties' (B1 — key loads.detail.chain.9_1.strip.chip.multi_node_displayname). Got: \(components[1])")
            XCTAssertEqual(components[2], "flagged",
                           "Field 3 for VL-1009 (one .verified, one .flagged) must be 'flagged' — most-suspicious wins per RESEARCH §Open Q1. Got: \(components[2])")
        }
    }

    // MARK: - 5. Single-node chip — 3-field a11y label + node displayName

    /// VL-1001's Shipper chip is a single-node role. Its 3-field a11y
    /// label MUST use the node's displayName (NOT "multiple parties"):
    ///   - component[0] == "Shipper"
    ///   - component[1] == "Pacific Goods LLC" (the VL-1001 shipper node's displayName)
    ///   - component[2] == "verified"
    func test_singleNodeChip_a11yLabel_isThreeFieldAndUsesNodeDisplayName() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        guard let shipperChip = chip(for: .shipper, in: view) else {
            XCTFail("VL-1001 must produce a SHP chip.")
            return
        }
        guard let label = shipperChip.accessibilityLabel, !label.isEmpty else {
            XCTFail("SHP chip must publish a non-empty accessibilityLabel (R6 leaf-element model).")
            return
        }

        let components = label.components(separatedBy: ", ")
        XCTAssertEqual(components.count, 3,
                       "Single-node SHP chip a11y label must have EXACTLY 3 fields (SPEC R6 binding). Got components: \(components) — full label: \"\(label)\"")

        if components.count == 3 {
            XCTAssertEqual(components[0], "Shipper",
                           "Field 1 must be the role's displayName 'Shipper'. Got: \(components[0])")
            XCTAssertEqual(components[1], "Pacific Goods LLC",
                           "Field 2 for a single-node SHP chip must be the node's displayName. Got: \(components[1])")
            XCTAssertEqual(components[2], "verified",
                           "Field 3 for a .verified single-node chip must be 'verified'. Got: \(components[2])")
        }
    }

    // MARK: - 6. onRoleTap closure fires with the tapped role

    /// Setting `onRoleTap = { ... }`, then invoking the ChipView's
    /// internal `onTap` closure (the seam the gesture recognizer fires)
    /// MUST capture exactly one Role, and it must match the chip's role.
    func test_onRoleTap_closure_fires_with_tappedRole() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        var tappedRoles: [Role] = []
        view.onRoleTap = { role in tappedRoles.append(role) }

        guard let carrierChip = chip(for: .carrier, in: view) else {
            XCTFail("VL-1001 must produce a CAR chip.")
            return
        }
        // Invoke the chip's onTap closure directly (the same closure the
        // UITapGestureRecognizer's @objc handler invokes after the
        // selection-feedback haptic). This avoids needing a real touch
        // sequence for a unit test and mirrors TrustNodeView's
        // _testInvokeSingleTap precedent.
        carrierChip.onTap?(carrierChip.role)

        XCTAssertEqual(tappedRoles.count, 1,
                       "onRoleTap must fire EXACTLY once per chip tap. Got: \(tappedRoles)")
        XCTAssertEqual(tappedRoles.first, .carrier,
                       "onRoleTap must carry the chip's role. Got: \(String(describing: tappedRoles.first))")
    }

    // MARK: - 7. Container is not an accessibility leaf (R6)

    /// R6 leaf-element model: the EveryoneOnLoadStripView container is NOT
    /// a VoiceOver leaf — only chips are. If a future edit flips this to
    /// true, every chip's composed label would be shadowed by a single
    /// container leaf, breaking the R6 binding.
    func test_container_isAccessibilityElement_false() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        XCTAssertFalse(view.isAccessibilityElement,
                       "EveryoneOnLoadStripView container must NOT be a leaf (R6).")
    }

    // MARK: - 8. Each chip is an accessibility leaf with the right traits

    /// Every chip MUST be a leaf with BOTH `.button` and `.staticText`
    /// traits (R6 + D-08). The .button trait signals interactivity to
    /// VoiceOver; .staticText signals the composed label is the
    /// authoritative text.
    func test_eachChip_isAccessibilityLeaf_withButtonAndStaticTextTraits() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        XCTAssertEqual(view.chips.count, 5, "Pre-condition: VL-1001 produces 5 chips.")

        for chip in view.chips {
            XCTAssertTrue(chip.isAccessibilityElement,
                          "Chip for role \(chip.role) must be a VoiceOver leaf (R6).")
            XCTAssertTrue(chip.accessibilityTraits.contains(.button),
                          "Chip for role \(chip.role) must carry the .button trait (D-08).")
            XCTAssertTrue(chip.accessibilityTraits.contains(.staticText),
                          "Chip for role \(chip.role) must carry the .staticText trait (R6).")
        }
    }

    // MARK: - 9. Trailing caption matches the LOCKED NSLocalizedString

    /// The trailing caption label's text MUST equal exactly the
    /// LOCKED localized value from UI-SPEC §Copywriting Contract:
    /// "All watching live\u{00A0}·\u{00A0}tap for details"
    /// (non-breaking space + middle dot + non-breaking space).
    func test_trailingCaption_matchesLockedLocalizedString() {
        let view = makeStrip(for: ChainOfTrustFactory.vl1001_fiveRolesClean())
        let expected = "All watching live\u{00A0}·\u{00A0}tap for details"
        XCTAssertEqual(view.captionLabel.text, expected,
                       "Trailing caption text must equal the LOCKED localized value. Got: \"\(view.captionLabel.text ?? "<nil>")\"")
    }
}
