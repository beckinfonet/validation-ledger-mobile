// validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift
//
// Phase 9 Plan 06 Task 2 — populates the Plan 02 Wave 0 shell with the
// 12-fingerprint matrix (3 verdicts × 2 devices × 2 Dynamic Type sizes)
// per RESEARCH §3 line 390.
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

    // MARK: - Helpers

    private static let iPhonePortraitSize = CGSize(width: 393, height: 600)
    private static let iPadSplitSize = CGSize(width: 700, height: 600)

    /// Build a TrustGraphView, configure it with a synthetic chain at the
    /// given verdict, and lay it out at the requested canvas size.
    /// `reduceMotionOverride = true` suppresses pulse animations so
    /// compromised snapshots are deterministic.
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
        v.reduceMotionOverride = true // Pitfall 8 — capture resting frame.
        v.bounds = CGRect(origin: .zero, size: size)
        // Drive Dynamic Type via UITraitCollection override. The label fonts
        // inside TrustNodeView pick up the parent trait collection through
        // adjustsFontForContentSizeCategory.
        v.overrideUserInterfaceStyle = .light
        let trait = UITraitCollection(preferredContentSizeCategory: contentSize)
        v.setOverrideTraitCollection(trait, forChild: UIViewController())
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

    // MARK: - clean × iPhone × {Large, XXXLarge}

    func test_cleanVerdict_iPhonePortrait_dynamicTypeLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPhonePortraitSize, contentSize: .large,
               name: "TrustGraph-clean-iPhonePortrait-DTLarge")
    }

    func test_cleanVerdict_iPhonePortrait_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPhonePortraitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-clean-iPhonePortrait-DTAXXXL")
    }

    // MARK: - clean × iPad × {Large, XXXLarge}

    func test_cleanVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadSplitSize, contentSize: .large,
               name: "TrustGraph-clean-iPadSplit-DTLarge")
    }

    func test_cleanVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.clean, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-clean-iPadSplit-DTAXXXL")
    }

    // MARK: - caution × iPhone × {Large, XXXLarge}

    func test_cautionVerdict_iPhonePortrait_dynamicTypeLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPhonePortraitSize, contentSize: .large,
               name: "TrustGraph-caution-iPhonePortrait-DTLarge")
    }

    func test_cautionVerdict_iPhonePortrait_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPhonePortraitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-caution-iPhonePortrait-DTAXXXL")
    }

    // MARK: - caution × iPad × {Large, XXXLarge}

    func test_cautionVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadSplitSize, contentSize: .large,
               name: "TrustGraph-caution-iPadSplit-DTLarge")
    }

    func test_cautionVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.caution, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-caution-iPadSplit-DTAXXXL")
    }

    // MARK: - compromised × iPhone × {Large, XXXLarge} — Pitfall 8 resting frame

    func test_compromisedVerdict_iPhonePortrait_dynamicTypeLarge_rendersExpectedFrame() {
        let view = renderedView(verdict: .compromised, size: Self.iPhonePortraitSize, contentSize: .large)
        for halo in view._testHaloLayers() {
            XCTAssertNil(halo.animation(forKey: "pulse"),
                         "Pitfall 8: compromised snapshot must capture resting frame, no pulse animation attached.")
        }
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPhonePortraitSize),
            name: "TrustGraph-compromised-iPhonePortrait-DTLarge", to: self
        )
    }

    func test_compromisedVerdict_iPhonePortrait_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPhonePortraitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-compromised-iPhonePortrait-DTAXXXL")
    }

    // MARK: - compromised × iPad × {Large, XXXLarge}

    func test_compromisedVerdict_iPadSplit_dynamicTypeLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPadSplitSize, contentSize: .large,
               name: "TrustGraph-compromised-iPadSplit-DTLarge")
    }

    func test_compromisedVerdict_iPadSplit_dynamicTypeXXXLarge_rendersExpectedFrame() {
        render(.compromised, size: Self.iPadSplitSize, contentSize: .accessibilityExtraExtraExtraLarge,
               name: "TrustGraph-compromised-iPadSplit-DTAXXXL")
    }
}
