// validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift
//
// Phase 8 Plan 02 Task 3 — VerificationBadgeView snapshot + a11y assertions.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires the `XCTestCase.add(_:)` API to
// surface the rendered image in the CI artefact bundle for visual triage.
// Swift Testing has no equivalent attachment surface as of iOS 17 / Xcode 26.4
// (Phase 8 08-PATTERNS.md §10 "Snapshot test files" and 08-RESEARCH.md
// Assumption A2 document this choice). Subsequent snapshot suites in Plans 04
// and 05 will follow the same XCTest precedent.
//
// === Locked test surface ===
//   - 4 per-state tests (verified / pending / unverified / flagged) — each
//     asserts the locked background color + accessibilityLabel substring +
//     attaches the rendered image via UIKitSnapshot.attach.
//   - 1 nil fail-closed test (D-03 + T-08-06): configure(stateOrNil: nil)
//     renders the .unverified visuals AND the accessibilityLabel contains
//     "not verified" (literal prefix — fail-closed).
//   - 1 pill cornerRadius recomputation test (Pitfall 8): assert
//     layer.cornerRadius == bounds.height/2 across two different heights.
//
// === T-08-05 (PII) ===
// Tests construct views with synthetic enum values only — no party names,
// no IDs ever reach the rendered image or the accessibilityLabel.
//
// === T-08-06 (fail-closed VoiceOver) ===
// Two tests assert the accessibilityLabel substring discipline:
//   - test_unverifiedBadgeRendersUnverifiedVisuals — explicit literal check.
//   - test_nilCounterpartyRendersUnverifiedFailClosed — D-03 lock.
// Both ensure the substring "verified" never appears without the "not"
// prefix on unverified / nil paths.

import XCTest
@testable import validationLedger

class VerificationBadgeViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// Lay out the view at a representative pill size before snapshotting.
    /// 140×28 is the visual scale that mirrors the Phase 8 row's badge slot
    /// at default Dynamic Type (footnote, single line).
    private static let pillSize = CGSize(width: 140, height: 28)

    // MARK: - 4-state visual + a11y tests

    func test_verifiedBadgeRendersVerifiedVisuals() {
        let view = VerificationBadgeView()
        view.configure(state: .verified)

        // Locked color ramp — UI-SPEC §Color verification table.
        XCTAssertEqual(view.backgroundColor, DS.Colors.primary,
                       "Verified badge background must be DS.Colors.primary (systemBlue).")

        // VoiceOver-safe label per T-08-06.
        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("verified"),
                      "Verified badge a11y label must contain 'verified'. Got: \(a11y)")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-verified", to: self)
    }

    func test_pendingBadgeRendersPendingVisuals() {
        let view = VerificationBadgeView()
        view.configure(state: .pending)

        // Locked: .systemYellow — documented exception per UI-SPEC §Color.
        XCTAssertEqual(view.backgroundColor, .systemYellow,
                       "Pending badge background must be .systemYellow (caution semantic).")

        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("pending"),
                      "Pending badge a11y label must contain 'pending'. Got: \(a11y)")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-pending", to: self)
    }

    func test_unverifiedBadgeRendersUnverifiedVisuals() {
        // FAIL-CLOSED LOCK (T-08-06): the .unverified accessibilityLabel
        // MUST contain "not verified" (literal "not" prefix). If a future
        // edit drops the "not" or rewords to "Counterparty (un)verified",
        // this test will catch it because the substring "verified" without
        // the "not" prefix is the VoiceOver-trust-leak the threat model
        // explicitly prohibits.
        let view = VerificationBadgeView()
        view.configure(state: .unverified)

        XCTAssertEqual(view.backgroundColor, .tertiarySystemFill,
                       "Unverified badge background must be .tertiarySystemFill (neutral grey).")

        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("not verified"),
                      "Unverified badge a11y label must contain 'not verified' (fail-closed). Got: \(a11y)")
        // Defence-in-depth: prove the substring "verified" is ONLY present
        // because of the "not verified" phrasing, never as a free-floating
        // trust signal.
        XCTAssertFalse(
            a11y.contains("verified") && !a11y.contains("not verified"),
            "Fail-closed: UNVERIFIED badge a11y label must NEVER read as 'verified' without the 'not' prefix. Got: \(a11y)"
        )

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-unverified", to: self)
    }

    func test_flaggedBadgeRendersFlaggedVisuals() {
        let view = VerificationBadgeView()
        view.configure(state: .flagged)

        XCTAssertEqual(view.backgroundColor, DS.Colors.destructive,
                       "Flagged badge background must be DS.Colors.destructive (systemRed).")

        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("flagged"),
                      "Flagged badge a11y label must contain 'flagged'. Got: \(a11y)")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-flagged", to: self)
    }

    // MARK: - D-03 + T-08-06 fail-closed nil

    /// The D-03 lock: a nil server-projected counterparty MUST render the
    /// `.unverified` visuals — never a default-inherited "verified" trust
    /// signal in either the visible pill or the VoiceOver-readable label.
    /// This test locks Phase 7 D-03 + UI-SPEC fail-closed + T-08-06.
    func test_nilCounterpartyRendersUnverifiedFailClosed() {
        let view = VerificationBadgeView()
        view.configure(stateOrNil: nil)

        // Visual identity with .unverified — same neutral-grey fill.
        XCTAssertEqual(view.backgroundColor, .tertiarySystemFill,
                       "nil-counterparty must render the .unverified visual (neutral grey).")

        // T-08-06 fail-closed VoiceOver discipline.
        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("not verified"),
                      "nil-counterparty a11y label must contain 'not verified' (fail-closed D-03). Got: \(a11y)")
        XCTAssertFalse(
            a11y.contains("verified") && !a11y.contains("not verified"),
            "Fail-closed: nil-counterparty a11y label must NEVER read as 'verified' without the 'not' prefix (T-08-06). Got: \(a11y)"
        )

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-nil-failclosed", to: self)
    }

    // MARK: - Pitfall 8 (Dynamic Type pill geometry)

    /// Verifies that `layer.cornerRadius` recomputes as `bounds.height / 2`
    /// on every layout pass — the locked Pitfall 8 mitigation that keeps
    /// the pill from becoming a slab when Dynamic Type grows the label
    /// (and therefore the badge's intrinsic height).
    func test_pillCornerRadiusRecomputesOnLayout() {
        let view = VerificationBadgeView()
        view.configure(state: .verified)

        view.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        view.layoutIfNeeded()
        XCTAssertEqual(view.layer.cornerRadius, 20,
                       "At height 40 the corner radius must be 20 (bounds.height / 2).")

        view.bounds = CGRect(x: 0, y: 0, width: 100, height: 60)
        view.layoutIfNeeded()
        XCTAssertEqual(view.layer.cornerRadius, 30,
                       "At height 60 the corner radius must be 30 (bounds.height / 2). " +
                       "If this fails, layoutSubviews has stopped recomputing — Dynamic Type will break the pill (Pitfall 8).")
    }
}
