// validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift
//
// Phase 9 Plan 06 Task 2 — populated the original 12-fingerprint matrix
// (3 verdicts × 2 devices × 2 Dynamic Type sizes). PHASE 9.1 D-05
// **constrains this suite to iPad sizes only** — iPhone no longer mounts
// TrustGraphView (R5: iPhone uses the new vertical-tree layout from Plans
// 03 + 04; TrustGraphView is mounted only on iPad regular). The Phase 9
// iPhone-sized snapshot methods have been REMOVED — keeping them would
// test a code path the app no longer presents in production.
//
// === Phase 9.1 D-05 / D-06 — iPad-only snapshot posture ===
// New iPad sizes per UI-SPEC §Snapshot Test Matrix:
//   - iPadMiniPortraitSize   = 744 × 1024
//   - iPadMiniLandscapeSize  = 1133 × 744
// The previous iPadSplitSize (700×600) is retained as a regression for
// the existing iPad split-pane render scenario.
// WR-04 baseline sanity-check (Phase 9 close-out) collapses into this
// re-record pass — the human reviewer walks the new iPad attachments once.
//
// === Pitfall 8 / RESEARCH §3 line 408 ===
// Every compromised-verdict snapshot test sets `halo.opacity = 1.0` BEFORE
// rendering. We achieve this via the `reduceMotionOverride = true` test
// seam which suppresses pulse animations entirely — the halo paints its
// resting frame. Mixed effect is the same: deterministic compromised
// renders for visual diffing.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`; mirrors
// the LoadDetailSkeletonViewSnapshotTests precedent.

import XCTest
@testable import validationLedger

class TrustGraphViewSnapshotTests: XCTestCase {

    // MARK: - Helpers — iPad-only canvas sizes (Phase 9.1 D-05)

    /// Phase 9 split-pane width retained as a regression scenario (the
    /// iPad bodyContainer's left 60% pane is roughly this width on iPad
    /// mini / iPad Air landscape splits).
    private static let iPadSplitSize = CGSize(width: 700, height: 600)
    /// Phase 9.1 D-05 / UI-SPEC §Snapshot Test Matrix — iPad mini portrait.
    private static let iPadMiniPortraitSize = CGSize(width: 744, height: 1024)
    /// Phase 9.1 D-05 / UI-SPEC §Snapshot Test Matrix — iPad mini landscape.
    private static let iPadMiniLandscapeSize = CGSize(width: 1133, height: 744)

    /// Build a TrustGraphView, configure it with a synthetic chain at the
    /// given verdict, and lay it out at the requested canvas size.
    /// `reduceMotionOverride = true` suppresses pulse animations so
    /// compromised snapshots are deterministic (Pitfall 8 — capture
    /// resting frame).
    ///
    /// WR-04 fix (Phase 9 review): the `contentSize` parameter drives
    /// `view.traitOverrides.preferredContentSizeCategory` so the DTLarge
    /// vs DTAXXXL snapshot variants actually render at different sizes.
    private func renderedView(
        verdict: ChainIntegrity.Verdict,
        size: CGSize,
        contentSize: UIContentSizeCategory
    ) -> TrustGraphView {
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: verdict,
            implicatedNodeIDs: verdict != .clean ? ["party-carrier"] : [],
            implicatedEdgeIDs: verdict != .clean ? ["edge-broker-carrier"] : []
        )
        let v = TrustGraphView()
        v.reduceMotionOverride = true
        v.bounds = CGRect(origin: .zero, size: size)
        v.overrideUserInterfaceStyle = .light
        // WR-04: inject the Dynamic Type content-size category via the iOS
        // 17 trait-override channel. Must be applied BEFORE configure(...)
        // + layoutIfNeeded() so the view sees the override during its
        // initial layout pass.
        v.traitOverrides.preferredContentSizeCategory = contentSize
        v.configure(chainOfTrust: chain)
        v.layoutIfNeeded()
        return v
    }

    private func render(_ verdict: ChainIntegrity.Verdict,
                        size: CGSize,
                        contentSize: UIContentSizeCategory,
                        name: String) {
        let view = renderedView(verdict: verdict, size: size, contentSize: contentSize)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: size),
            name: name, to: self
        )
    }

    // MARK: - clean × iPad split × {Large, XXXLarge}

    func test_cleanVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadSplitSize, contentSize: .large,
               name: "TrustGraph-clean-iPadSplit-DTLarge")
    }

    func test_cleanVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-clean-iPadSplit-DTAXXXL")
    }

    // MARK: - clean × iPad mini portrait

    func test_cleanVerdict_iPadMiniPortrait_dynamicTypeLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadMiniPortraitSize, contentSize: .large,
               name: "TrustGraph-clean-iPadMiniPortrait-DTLarge")
    }

    // MARK: - clean × iPad mini landscape

    func test_cleanVerdict_iPadMiniLandscape_dynamicTypeLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadMiniLandscapeSize, contentSize: .large,
               name: "TrustGraph-clean-iPadMiniLandscape-DTLarge")
    }

    // MARK: - caution × iPad split × {Large, XXXLarge}

    func test_cautionVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadSplitSize, contentSize: .large,
               name: "TrustGraph-caution-iPadSplit-DTLarge")
    }

    func test_cautionVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-caution-iPadSplit-DTAXXXL")
    }

    // MARK: - caution × iPad mini portrait

    func test_cautionVerdict_iPadMiniPortrait_dynamicTypeLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadMiniPortraitSize, contentSize: .large,
               name: "TrustGraph-caution-iPadMiniPortrait-DTLarge")
    }

    // MARK: - caution × iPad mini landscape

    func test_cautionVerdict_iPadMiniLandscape_dynamicTypeLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadMiniLandscapeSize, contentSize: .large,
               name: "TrustGraph-caution-iPadMiniLandscape-DTLarge")
    }

    // MARK: - compromised × iPad split × {Large, XXXLarge} — Pitfall 8 resting frame

    func test_compromisedVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        let view = renderedView(verdict: .compromised, size: Self.iPadSplitSize, contentSize: .large)
        for halo in view._testHaloLayers() {
            XCTAssertNil(halo.animation(forKey: "pulse"),
                         "Pitfall 8: compromised snapshot must capture resting frame, no pulse animation attached.")
        }
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadSplitSize),
            name: "TrustGraph-compromised-iPadSplit-DTLarge", to: self
        )
    }

    func test_compromisedVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-compromised-iPadSplit-DTAXXXL")
    }

    // MARK: - compromised × iPad mini portrait

    func test_compromisedVerdict_iPadMiniPortrait_dynamicTypeLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPadMiniPortraitSize, contentSize: .large,
               name: "TrustGraph-compromised-iPadMiniPortrait-DTLarge")
    }

    // MARK: - compromised × iPad mini landscape

    func test_compromisedVerdict_iPadMiniLandscape_dynamicTypeLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPadMiniLandscapeSize, contentSize: .large,
               name: "TrustGraph-compromised-iPadMiniLandscape-DTLarge")
    }
}
