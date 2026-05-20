// validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift
//
// Phase 9 Plan 09 Task 1 — populated banner snapshot suite for the
// ChainIntegrityBannerView (D-15 / D-16). Mirrors the Plan 04
// LoadDetailSkeletonViewSnapshotTests pattern: structural + accessibility
// assertions + UIKitSnapshot.attach for visual review on CI.
//
// === Three methods covering the three Verdict cases ===
//   1. test_cautionVerdict_rendersYellowBanner — `.caution` snapshot +
//      yellow-background + accessibilityLabel content assertion.
//   2. test_compromisedVerdict_rendersRedBanner — `.compromised` snapshot
//      + red-background + accessibilityLabel content assertion.
//   3. test_cleanVerdict_bannerIsHidden — `.clean` unit assertion:
//      `isHidden == true` AND `intrinsicContentSize == .zero`. NO snapshot
//      is attached for clean — the banner does not render any chrome and
//      MUST NOT claim hit-test surface (UI-SPEC line 118).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Mirrors
// the existing snapshot-suite locked precedent across Loads/Snapshot/.
//
// === T-09-04 (PII) ===
// All test reason strings are synthetic ("Broker re-tendered to chameleon
// carrier", "Carrier identity does not match assigned MC") — no real freight
// reference numbers, no real party names.

import XCTest
@testable import validationLedger

class ChainIntegrityBannerViewSnapshotTests: XCTestCase {

    // MARK: - Helpers — banner canvas size

    /// Banner canvas: iPhone 17 width × 36pt fixed banner height (PATTERNS E4
    /// mirror — LimitedTrustBannerView.bannerHeight). Snapshot at the exact
    /// intrinsic height so the rendered chrome is the entire banner surface.
    private static let bannerSize = CGSize(width: 393, height: 36)

    // MARK: - 1. caution → yellow banner

    func test_cautionVerdict_rendersYellowBanner() {
        let reason = "Broker re-tendered to chameleon carrier"
        let banner = ChainIntegrityBannerView(verdict: .caution, reason: reason)
        banner.bounds = CGRect(origin: .zero, size: Self.bannerSize)
        banner.layoutIfNeeded()

        // Attach the rendered snapshot for visual review on CI.
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: banner, size: Self.bannerSize),
            name: "ChainIntegrityBanner-caution-yellow", to: self
        )

        // Background color must be the locked DS.Colors.caution token.
        XCTAssertEqual(banner.backgroundColor, DS.Colors.caution,
                       "caution verdict must paint DS.Colors.caution background (UI-SPEC § Banner lines 212-225)")

        // accessibilityLabel must contain "Caution" + the reason fragment
        // verbatim per UI-SPEC line 684.
        let label = banner.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Caution"),
                      "accessibilityLabel must contain spoken verdict 'Caution': \(label)")
        XCTAssertTrue(label.contains(reason),
                      "accessibilityLabel must contain server-supplied reason verbatim: \(label)")

        // Locked identifier — XCUITest probe (PATTERNS table row 19 mirror
        // of `limited-trust-banner`).
        XCTAssertEqual(banner.accessibilityIdentifier, "chain-integrity-banner",
                       "Banner identifier must be the locked 'chain-integrity-banner'")

        // Banner is informational, not tappable.
        XCTAssertFalse(banner.isUserInteractionEnabled,
                       "Banner must not accept touches (UI-SPEC line 223)")

        // Intrinsic height: 36pt fixed (matches LimitedTrustBannerView).
        XCTAssertEqual(banner.intrinsicContentSize.height, 36,
                       "caution banner must claim 36pt intrinsic height")
    }

    // MARK: - 2. compromised → red banner

    func test_compromisedVerdict_rendersRedBanner() {
        let reason = "Carrier identity does not match assigned MC"
        let banner = ChainIntegrityBannerView(verdict: .compromised, reason: reason)
        banner.bounds = CGRect(origin: .zero, size: Self.bannerSize)
        banner.layoutIfNeeded()

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: banner, size: Self.bannerSize),
            name: "ChainIntegrityBanner-compromised-red", to: self
        )

        // Background color must be the locked DS.Colors.destructive token.
        XCTAssertEqual(banner.backgroundColor, DS.Colors.destructive,
                       "compromised verdict must paint DS.Colors.destructive background")

        // accessibilityLabel must contain "Compromised" + the reason fragment.
        let label = banner.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("Compromised"),
                      "accessibilityLabel must contain spoken verdict 'Compromised': \(label)")
        XCTAssertTrue(label.contains(reason),
                      "accessibilityLabel must contain server-supplied reason verbatim: \(label)")

        XCTAssertEqual(banner.accessibilityIdentifier, "chain-integrity-banner")
        XCTAssertFalse(banner.isUserInteractionEnabled)
        XCTAssertEqual(banner.intrinsicContentSize.height, 36)
    }

    // MARK: - 3. clean → hidden, zero intrinsic size, no chrome

    /// Unit-style assertion (NO snapshot) — the clean verdict MUST render
    /// no chrome AND MUST NOT claim any hit-test surface (UI-SPEC line 118).
    /// Attaching a snapshot would only attach a 0×0 transparent image; the
    /// invariant under test is the size-and-hidden contract.
    func test_cleanVerdict_bannerIsHidden() {
        let banner = ChainIntegrityBannerView(verdict: .clean, reason: "")
        XCTAssertTrue(banner.isHidden,
                      "clean verdict must produce an isHidden banner (UI-SPEC line 118)")
        XCTAssertEqual(banner.intrinsicContentSize, .zero,
                       "clean verdict must claim zero intrinsic content size — no hit-test surface")
    }
}
