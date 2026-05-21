// validationLedgerTests/Components/VerificationBadgeViewTests.swift
//
// Phase 9.1 Plan 01 Task 3 — R12 single-source-of-truth invariant tests.
//
// === Why XCTest, not Swift Testing ===
// The validationLedger test target standardises on XCTest for UIKit-rendered
// surfaces because `UIKitSnapshot.attach(_:name:to:)` requires the
// `XCTestCase.add(_:)` API to surface rendered images in the CI artefact
// bundle (Phase 8 08-PATTERNS.md §10, 08-RESEARCH.md A2 — locked precedent).
// These tests do NOT take snapshots — they are pure assertions — but match
// the in-repo convention so the entire badge test surface uses the same base
// class and lifecycle. Future R12 additions (e.g. RoleAvatarView coverage in
// Plan 02) will also live under this `Components/` directory using XCTest.
//
// === Locked test surface ===
//   - 4 per-state tests (verified / pending / unverified / flagged), each
//     asserting `view.backgroundColor == DS.Colors.Verification.color(for: <case>)`.
//     This proves the badge consumes the helper as its background source-of-
//     truth — the same helper the future `RoleAvatarView` will read for its
//     status-dot fill. If TRUST-02 ever erodes (a future edit puts the badge
//     and the avatar on different colors), these tests catch it FIRST because
//     the helper return value and the badge backgroundColor are compared
//     directly, not via a literal intermediary.
//
// === Relationship to VerificationBadgeViewSnapshotTests ===
// The existing Phase 8 snapshot tests assert the badge backgroundColor equals
// the LITERAL color (e.g. `DS.Colors.primary`). If a future refactor changes
// the helper's return value AND a Phase-8-style test's RHS together, the
// drift could slip through. THESE tests assert the badge equals the HELPER —
// so any future change to the helper that the badge doesn't track will fail
// here. The two suites are complementary: Phase 8 locks the visual contract;
// this Phase 9.1 suite locks the wiring contract.
//
// === T-08-05 (PII) ===
// Tests construct views with synthetic enum values only — no party names,
// no IDs ever reach the rendered view or the asserted color.

import XCTest
@testable import validationLedger

final class VerificationBadgeViewTests: XCTestCase {

    // MARK: - R12 single-source-of-truth invariants

    /// `.verified` — badge background must equal `DS.Colors.Verification.color(for: .verified)`.
    func test_apply_verified_backgroundMatchesHelper() {
        let view = VerificationBadgeView()
        view.configure(state: .verified)

        XCTAssertEqual(
            view.backgroundColor,
            DS.Colors.Verification.color(for: .verified),
            "TRUST-02 invariant: badge backgroundColor must equal DS.Colors.Verification.color(for: .verified) — R12 single-source-of-truth."
        )
    }

    /// `.pending` — badge background must equal `DS.Colors.Verification.color(for: .pending)`.
    func test_apply_pending_backgroundMatchesHelper() {
        let view = VerificationBadgeView()
        view.configure(state: .pending)

        XCTAssertEqual(
            view.backgroundColor,
            DS.Colors.Verification.color(for: .pending),
            "TRUST-02 invariant: badge backgroundColor must equal DS.Colors.Verification.color(for: .pending) — R12 single-source-of-truth."
        )
    }

    /// `.unverified` — badge background must equal `DS.Colors.Verification.color(for: .unverified)`.
    func test_apply_unverified_backgroundMatchesHelper() {
        let view = VerificationBadgeView()
        view.configure(state: .unverified)

        XCTAssertEqual(
            view.backgroundColor,
            DS.Colors.Verification.color(for: .unverified),
            "TRUST-02 invariant: badge backgroundColor must equal DS.Colors.Verification.color(for: .unverified) — R12 single-source-of-truth."
        )
    }

    /// `.flagged` — badge background must equal `DS.Colors.Verification.color(for: .flagged)`.
    func test_apply_flagged_backgroundMatchesHelper() {
        let view = VerificationBadgeView()
        view.configure(state: .flagged)

        XCTAssertEqual(
            view.backgroundColor,
            DS.Colors.Verification.color(for: .flagged),
            "TRUST-02 invariant: badge backgroundColor must equal DS.Colors.Verification.color(for: .flagged) — R12 single-source-of-truth."
        )
    }
}
