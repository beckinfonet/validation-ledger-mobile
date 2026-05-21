// validationLedgerTests/Loads/Snapshot/ChainOfVouchesViewSnapshotTests.swift
//
// Phase 9.1 Plan 04 Task 3 — ChainOfVouchesView snapshot matrix.
//
// === Locked matrix (per Plan 04 PLAN Task 3 + UI-SPEC §Snapshot Test Matrix Tree row) ===
//   Widths:
//     iPhone 15 portrait  — 390pt (modern baseline)
//     iPhone SE 3 portrait — 375pt (narrowest, worst-case must-fit)
//   Base fixtures (10 attachments):
//     VL-1003 (2 rows / clean / "1 vouch, no anonymous parties")
//     VL-1005 (3 rows / caution / "2 vouches, no anonymous parties")
//     VL-1007 (4 rows / clean / "3 vouches, no anonymous parties")
//     VL-1001 (5 rows / clean / "4 vouches, no anonymous parties")
//     VL-1009 (6 rows / compromised — two brokers as adjacent siblings
//              under SHP with VIA SHP)
//   Verdict-coverage extras (3 attachments — drives R4 + R7 + R9):
//     VL-1009 (compromised) at iPhone 15 portrait — the marquee
//             multi-broker fraud-archetype snapshot
//     VL-1010 (compromised, fewer roles) at iPhone 15 portrait —
//             demonstrates R7 supersedure with a simpler chain
//     VL-1005 (caution) at iPhone 15 portrait — yellow footer pill
//
// 13 total attachments.
//
// === R4 acceptance (footer pill on EVERY verdict) ===
// The 4 clean fixtures (VL-1001/1003/1005-as-caution/1007) test the
// soft-green-tinted pill; VL-1009 + VL-1010 test the red compromised
// tier; VL-1005 tests the yellow caution tier (its JSON fixture is
// .caution despite the "clean fixture" label in PLAN Task 3 — the
// affirmative-cadence fixture-text edit is text-only and does NOT
// change verdict).
//
// === R7 acceptance (footer pill is sole fraud signal on iPhone) ===
// VL-1009 + VL-1010 attachments visually demonstrate: every row at
// full alpha, connectors stay dashed-neutral, NO pulse halo. The
// footer pill (red) carries the fraud signal alone.
//
// === Pitfall 8 / WR-04 (trait override applied BEFORE configure) ===
// `traitOverrides.preferredContentSizeCategory = .large` is applied
// BEFORE `configure(chainOfTrust:)` + `layoutIfNeeded()`. Mirrors
// the WR-04 fix in TrustGraphViewSnapshotTests.renderedView (line 63).
//
// === Why explicit per-cell test methods over a parameterised loop ===
// Mirrors Plan 02 Pattern 6 + Plan 03 Pattern 6 — discrete CI test
// names make a failing cell unambiguous in the Xcode test navigator.
//
// === T-09.1-02 (PII) ===
// Snapshots render synthetic party names from ChainOfTrustFactory.

import XCTest
@testable import validationLedger

final class ChainOfVouchesViewSnapshotTests: XCTestCase {

    // MARK: - Locked geometry

    /// iPhone 15 portrait width — the modern baseline.
    private static let iPhone15PortraitWidth: CGFloat = 390

    /// iPhone SE 3 portrait width — the narrowest target.
    private static let iPhoneSE3PortraitWidth: CGFloat = 375

    /// Canvas height — enough room for the card chrome + tree + footer
    /// pill at the widest fixture (VL-1009 6 rows) without clipping.
    private static let canvasHeight: CGFloat = 600

    // MARK: - render helper
    //
    // Order of operations (Pitfall 8 / WR-04):
    //   1. Instantiate the view.
    //   2. Set bounds.
    //   3. Force light user interface style for deterministic snapshots.
    //   4. Apply the Dynamic Type trait override BEFORE configure(...).
    //   5. configure(chainOfTrust:).
    //   6. layoutIfNeeded().
    //   7. Render + attach via UIKitSnapshot.

    private func render(
        chain: ChainOfTrust,
        width: CGFloat,
        contentSize: UIContentSizeCategory = .large,
        name: String
    ) {
        let view = ChainOfVouchesView()
        view.bounds = CGRect(x: 0, y: 0, width: width, height: Self.canvasHeight)
        view.overrideUserInterfaceStyle = .light
        view.traitOverrides.preferredContentSizeCategory = contentSize
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: view.bounds.size),
            name: name,
            to: self
        )
    }

    // MARK: - 5 fixtures × 2 widths (10 attachments)

    // VL-1001 (5 rows / clean)

    func test_VL_1001_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1001_fiveRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1001-iPhone15Portrait-DTLarge"
        )
    }

    func test_VL_1001_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1001_fiveRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "ChainOfVouches-VL-1001-iPhoneSE3Portrait-DTLarge"
        )
    }

    // VL-1003 (2 rows / clean)

    func test_VL_1003_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1003_twoRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1003-iPhone15Portrait-DTLarge"
        )
    }

    func test_VL_1003_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1003_twoRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "ChainOfVouches-VL-1003-iPhoneSE3Portrait-DTLarge"
        )
    }

    // VL-1005 (3 rows / caution)

    func test_VL_1005_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1005_threeRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1005-iPhone15Portrait-DTLarge"
        )
    }

    func test_VL_1005_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1005_threeRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "ChainOfVouches-VL-1005-iPhoneSE3Portrait-DTLarge"
        )
    }

    // VL-1007 (4 rows / clean)

    func test_VL_1007_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1007_fourRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1007-iPhone15Portrait-DTLarge"
        )
    }

    func test_VL_1007_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1007_fourRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "ChainOfVouches-VL-1007-iPhoneSE3Portrait-DTLarge"
        )
    }

    // VL-1009 (6 rows / compromised — two brokers as adjacent siblings)

    func test_VL_1009_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1009-iPhone15Portrait-DTLarge"
        )
    }

    func test_VL_1009_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "ChainOfVouches-VL-1009-iPhoneSE3Portrait-DTLarge"
        )
    }

    // MARK: - Verdict-coverage extras (3 attachments)

    /// VL-1010 (compromised, fewer roles) — R7 supersedure with a
    /// simpler chain. The 3 rows + red footer pill make the "footer
    /// pill is the sole fraud signal" intent legible.
    func test_VL_1010_iPhone15Portrait_compromisedFewerRoles_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1010_compromisedChain(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1010-iPhone15Portrait-DTLarge-compromised"
        )
    }

    /// VL-1009 at iPhone 15 portrait — marquee multi-broker
    /// fraud-archetype snapshot (R9 forced-siblings + R7 footer-pill-only
    /// fraud signal). Named with a "marquee" suffix so the CI artefact
    /// reviewer knows this is the most-important attachment of the
    /// matrix.
    func test_VL_1009_iPhone15Portrait_compromisedMarquee_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1009-iPhone15Portrait-DTLarge-compromisedMarquee"
        )
    }

    /// VL-1005 at iPhone 15 portrait — caution-tier footer pill
    /// (yellow). The 3 rows + yellow pill exercises R4's "every
    /// verdict renders" guarantee at the middle tier.
    func test_VL_1005_iPhone15Portrait_cautionTier_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1005_threeRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "ChainOfVouches-VL-1005-iPhone15Portrait-DTLarge-cautionTier"
        )
    }
}
