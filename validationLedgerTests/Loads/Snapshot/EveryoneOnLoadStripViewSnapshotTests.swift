// validationLedgerTests/Loads/Snapshot/EveryoneOnLoadStripViewSnapshotTests.swift
//
// Phase 9.1 Plan 03 Task 3 — EveryoneOnLoadStripView snapshot matrix.
//
// 10 attachments = 5 fixtures × 2 iPhone widths.
//
// === Locked matrix (per Plan 03 PLAN Task 3 + UI-SPEC § Snapshot Test Matrix → Strip) ===
//   Widths:
//     iPhone 15 portrait  — 390pt (modern baseline)
//     iPhone SE 3 portrait — 375pt (narrowest target, worst-case "must fit")
//   Fixtures:
//     VL-1003 (2 chips) / VL-1005 (3 chips) / VL-1007 (4 chips)
//     VL-1001 (5 chips) / VL-1009 (5 chips after BRK collapse)
//
// The SE 3 width is the "must fit without truncating the trailing caption"
// gate per UI-SPEC § Component Geometry. With 5 chips + the caption, the
// strip is the worst case at SE width — the snapshot bundle survives into
// the CI artefact set for human inspection.
//
// === Pitfall 8 / WR-04 (trait override applied BEFORE configure) ===
// The `traitOverrides.preferredContentSizeCategory = .large` is applied
// BEFORE `configure(chainOfTrust:)` + `layoutIfNeeded()` so the view sees
// the override during its initial layout pass. This mirrors the WR-04 fix
// in TrustGraphViewSnapshotTests.renderedView (line 63) — the trait
// override is scoped to this view's subtree (no global state mutation,
// no XCTestCase tearDown required).
//
// === Why explicit per-cell test methods over a parameterised loop ===
// Mirrors Plan 02's RoleAvatarViewSnapshotTests Pattern 6: discrete test
// names make a failing cell unambiguous in the Xcode test navigator
// (e.g. `test_VL_1009_iPhoneSE3Portrait_rendersExpected` is unambiguous
// when one cell breaks). A parameterised loop would collapse 10 cells
// into a single failing test name.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Mirrors
// the in-repo precedent (TrustGraphViewSnapshotTests, RoleAvatarViewSnapshotTests).
//
// === T-09.1-02 (PII) ===
// Snapshots render synthetic party names from ChainOfTrustFactory
// (vl1001_…/vl1009_…). The factory comments document its PII-zero posture.
// Per UIKitSnapshot.swift's threat-model header: "Zero PII in CI snapshot
// artefacts."

import XCTest
@testable import validationLedger

final class EveryoneOnLoadStripViewSnapshotTests: XCTestCase {

    // MARK: - Locked geometry

    /// iPhone 15 portrait width — the modern baseline.
    private static let iPhone15PortraitWidth: CGFloat = 390

    /// iPhone SE 3 portrait width — the narrowest target, worst-case
    /// "must fit without truncating the caption" per UI-SPEC § Component
    /// Geometry → EveryoneOnLoadStripView.
    private static let iPhoneSE3PortraitWidth: CGFloat = 375

    /// Canvas height — chip vertical stack (avatar 40 + label 8 + spacing)
    /// + outer DS.Spacing.sm vertical insets = 80pt, matches the strip's
    /// natural intrinsic height with the trailing caption row.
    private static let canvasHeight: CGFloat = 80

    // MARK: - render helper

    /// Render a strip configured with `chain` at the given `width` and
    /// attach the resulting image under `name`.
    ///
    /// Order of operations (Pitfall 8 / WR-04):
    ///   1. Instantiate the view.
    ///   2. Set bounds (drives layout's available width).
    ///   3. Force light user interface style for deterministic snapshots.
    ///   4. Apply the Dynamic Type trait override BEFORE configure(...) —
    ///      the override is captured during the initial layout pass.
    ///   5. configure(chainOfTrust:).
    ///   6. layoutIfNeeded().
    ///   7. Render + attach via UIKitSnapshot.
    private func render(chain: ChainOfTrust, width: CGFloat, name: String) {
        let view = EveryoneOnLoadStripView()
        view.bounds = CGRect(x: 0, y: 0, width: width, height: Self.canvasHeight)
        view.overrideUserInterfaceStyle = .light
        // WR-04: inject the Dynamic Type content-size category via the
        // iOS 17 trait-override channel. Must be applied BEFORE
        // configure(...) + layoutIfNeeded() so the view sees the
        // override during its initial layout pass. Scoped to this
        // view's subtree — no global state mutation.
        view.traitOverrides.preferredContentSizeCategory = .large
        view.configure(chainOfTrust: chain)
        view.layoutIfNeeded()
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: view.bounds.size),
            name: name,
            to: self
        )
    }

    // MARK: - VL-1001 (5 distinct roles — all verified, clean)

    func test_VL_1001_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1001_fiveRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1001-iPhone15Portrait"
        )
    }

    func test_VL_1001_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1001_fiveRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1001-iPhoneSE3Portrait"
        )
    }

    // MARK: - VL-1003 (2 distinct roles — clean)

    func test_VL_1003_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1003_twoRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1003-iPhone15Portrait"
        )
    }

    func test_VL_1003_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1003_twoRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1003-iPhoneSE3Portrait"
        )
    }

    // MARK: - VL-1005 (3 distinct roles — carrier pending, caution)

    func test_VL_1005_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1005_threeRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1005-iPhone15Portrait"
        )
    }

    func test_VL_1005_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1005_threeRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1005-iPhoneSE3Portrait"
        )
    }

    // MARK: - VL-1007 (4 distinct roles — clean)

    func test_VL_1007_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1007_fourRolesClean(),
            width: Self.iPhone15PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1007-iPhone15Portrait"
        )
    }

    func test_VL_1007_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1007_fourRolesClean(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1007-iPhoneSE3Portrait"
        )
    }

    // MARK: - VL-1009 (6 nodes / 5 distinct roles — two brokers collapse, compromised)
    //
    // The marquee fraud-archetype fixture. After the BRK collapse + most-
    // suspicious-wins rule (D-10 / RESEARCH §Open Q1), the BRK chip's
    // status dot is .flagged red. SE 3 width is the worst case here —
    // the 5-chip strip + trailing caption must fit at 375pt without
    // truncating either.

    func test_VL_1009_iPhone15Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised(),
            width: Self.iPhone15PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1009-iPhone15Portrait"
        )
    }

    func test_VL_1009_iPhoneSE3Portrait_rendersExpected() {
        render(
            chain: ChainOfTrustFactory.vl1009_sixNodesTwoBrokersCompromised(),
            width: Self.iPhoneSE3PortraitWidth,
            name: "EveryoneOnLoadStrip-VL-1009-iPhoneSE3Portrait"
        )
    }
}
