// validationLedgerTests/Components/RoleAvatarViewTests.swift
//
// Phase 9.1 Plan 02 Task 2 — RoleAvatarView unit tests.
//
// === Why XCTest, not Swift Testing ===
// Matches the in-repo convention established by VerificationBadgeViewTests
// (Plan 01) and VerificationBadgeViewSnapshotTests (Phase 8). Future
// snapshot coverage for RoleAvatarView (Task 3) requires XCTest because
// `UIKitSnapshot.attach(_:name:to:)` uses XCTestCase.add(_:) to surface
// rendered images in the CI artefact bundle.
//
// === Locked test surface ===
//   1. test_allRoleStateCombinations_dotColorMatchesVerificationHelper
//      — 20 assertions (5 roles × 4 verification states). Each asserts
//        `view.statusDot.backgroundColor == DS.Colors.Verification.color(for: state)`.
//        This is the R12 single-source-of-truth invariant for the status
//        dot — proves the avatar consumes the SAME helper as
//        VerificationBadgeView's pill background, locking TRUST-02 at
//        the test layer.
//
//   2. test_allRoleStateCombinations_avatarFillMatchesRolesHelper
//      — 20 assertions. Each asserts
//        `view.backgroundColor == DS.Colors.Roles.color(for: role)`.
//        Locks the per-role palette to the helper rather than to literal
//        colors — if a future palette refinement changes the helper's
//        return value, this test stays green automatically.
//
//   3. test_abbreviationLiterals_match_lockedSwitch
//      — 5 assertions, one per Role. Each asserts the abbreviation label
//        text EXACTLY matches the locked literal (SHP/BRK/CAR/DSP/FCT).
//        Proves the abbreviation is the literal switch, NOT a derived
//        `String(role.rawValue.prefix(3)).uppercased()`. If a future
//        refactor "simplifies" to a derivation, this test catches it.
//
//   4. test_isAccessibilityElement_false_decorative
//      — Locks R6 leaf-element model: the avatar is decorative; the
//        parent (strip chip / tree row) owns the composed VoiceOver
//        label.
//
//   5. test_isUserInteractionEnabled_false
//      — Locks the non-interactive posture: chip wrappers (Plan 03) own
//        the tap recognizer, not the avatar.
//
//   6. test_cornerRadius_recomputesForStripVariant
//      — Pitfall 8 (circle, not pill): at bounds (0,0,40,40) the
//        cornerRadius must be 20 (bounds.width / 2).
//
//   7. test_cornerRadius_recomputesForTreeVariant
//      — Pitfall 8 mirror at the .tree variant: at bounds (0,0,32,32)
//        the cornerRadius must be 16.
//
// === Relationship to VerificationBadgeViewTests (Plan 01) ===
// VerificationBadgeViewTests asserts the badge's backgroundColor == the
// shared helper. THESE tests do the same for RoleAvatarView's status
// dot. After both ship, ANY drift between the badge background, the
// avatar status dot, and the shared helper is caught by either suite.
//
// === T-08-05 / T-09.1-02 (PII) ===
// Tests construct views with synthetic enum values only — no party names,
// no IDs ever reach the rendered view, the asserted colors, or the
// abbreviation labels. The view is structurally incapable of receiving
// PII (its API is `(Role, VerificationState)` only).

import XCTest
@testable import validationLedger

final class RoleAvatarViewTests: XCTestCase {

    // MARK: - Test 1: 20 (role, state) combinations — status-dot color matches helper (R12)

    /// For every Role × VerificationState pair (5 × 4 = 20), the status dot's
    /// `backgroundColor` MUST equal `DS.Colors.Verification.color(for: state)`.
    /// This is the locked R12 single-source-of-truth invariant for the avatar
    /// dot — the same helper VerificationBadgeView consumes for its pill.
    func test_allRoleStateCombinations_dotColorMatchesVerificationHelper() {
        for role in Role.allCases {
            for state in VerificationState.allCases {
                let view = RoleAvatarView(role: role, state: state, variant: .strip)
                view.layoutIfNeeded()

                XCTAssertEqual(
                    view.statusDot.backgroundColor,
                    DS.Colors.Verification.color(for: state),
                    "R12 invariant: status dot for (\(role), \(state)) must equal " +
                    "DS.Colors.Verification.color(for: \(state)) — same source-of-truth " +
                    "function VerificationBadgeView consumes."
                )
            }
        }
    }

    // MARK: - Test 2: 20 (role, state) combinations — avatar fill matches helper

    /// For every Role × VerificationState pair (5 × 4 = 20), the avatar
    /// circle's `backgroundColor` MUST equal `DS.Colors.Roles.color(for: role)`.
    /// Locks the per-role palette to the helper, NOT to literal colors — a
    /// palette refinement in Colors.swift propagates automatically.
    func test_allRoleStateCombinations_avatarFillMatchesRolesHelper() {
        for role in Role.allCases {
            for state in VerificationState.allCases {
                let view = RoleAvatarView(role: role, state: state, variant: .strip)
                view.layoutIfNeeded()

                XCTAssertEqual(
                    view.backgroundColor,
                    DS.Colors.Roles.color(for: role),
                    "Avatar fill for (\(role), \(state)) must equal " +
                    "DS.Colors.Roles.color(for: \(role)) — single source-of-truth " +
                    "for Role → UIColor mapping."
                )
            }
        }
    }

    // MARK: - Test 3: Abbreviation literal locks (R1)

    /// Each role's abbreviation label MUST be the LOCKED LITERAL — NOT a
    /// derivation from `Role.rawValue` or `Role.displayName`. If a future
    /// refactor "simplifies" to `String(role.rawValue.prefix(3)).uppercased()`,
    /// the result would be `SHI/BRO/CAR/DIS/FAC` — three of which break the
    /// reference-photo contract. This test catches the regression.
    func test_abbreviationLiterals_match_lockedSwitch() {
        let shipper = RoleAvatarView(role: .shipper, state: .verified, variant: .strip)
        shipper.layoutIfNeeded()
        XCTAssertEqual(shipper.abbreviationLabel.text, "SHP",
                       "Shipper abbreviation literal must be \"SHP\".")

        let broker = RoleAvatarView(role: .broker, state: .verified, variant: .strip)
        broker.layoutIfNeeded()
        XCTAssertEqual(broker.abbreviationLabel.text, "BRK",
                       "Broker abbreviation literal must be \"BRK\".")

        let carrier = RoleAvatarView(role: .carrier, state: .verified, variant: .strip)
        carrier.layoutIfNeeded()
        XCTAssertEqual(carrier.abbreviationLabel.text, "CAR",
                       "Carrier abbreviation literal must be \"CAR\".")

        let dispatch = RoleAvatarView(role: .dispatch, state: .verified, variant: .strip)
        dispatch.layoutIfNeeded()
        XCTAssertEqual(dispatch.abbreviationLabel.text, "DSP",
                       "Dispatch abbreviation literal must be \"DSP\".")

        let factoring = RoleAvatarView(role: .factoring, state: .verified, variant: .strip)
        factoring.layoutIfNeeded()
        XCTAssertEqual(factoring.abbreviationLabel.text, "FCT",
                       "Factoring abbreviation literal must be \"FCT\".")
    }

    // MARK: - Test 4: a11y posture (R6 leaf-element model)

    /// The avatar is DECORATIVE — the composed VoiceOver label is owned by
    /// the parent (strip chip in Plan 03, tree row in Plan 04). If a future
    /// edit flips this to true, the parent's composed label would be
    /// shadowed by the avatar's per-leaf label, breaking R6.
    func test_isAccessibilityElement_false_decorative() {
        let view = RoleAvatarView(role: .shipper, state: .verified, variant: .strip)
        XCTAssertFalse(
            view.isAccessibilityElement,
            "R6 leaf-element model: RoleAvatarView is decorative — parent owns " +
            "the composed VoiceOver label."
        )
    }

    // MARK: - Test 5: non-interactive posture

    /// The avatar is non-interactive. The Plan 03 chip wrapper owns the tap
    /// recognizer. If a future edit flips this to true, the avatar would
    /// intercept taps the chip recognizer should receive.
    func test_isUserInteractionEnabled_false() {
        let view = RoleAvatarView(role: .shipper, state: .verified, variant: .strip)
        XCTAssertFalse(
            view.isUserInteractionEnabled,
            "RoleAvatarView is non-interactive — chip wrapper (Plan 03) owns the " +
            "tap recognizer, not the avatar."
        )
    }

    // MARK: - Test 6: Pitfall 8 cornerRadius recompute (.strip variant)

    /// At bounds (0,0,40,40) the cornerRadius MUST be 20 — the locked
    /// Pitfall-8 mitigation that keeps the avatar a perfect circle even
    /// when a test or autolayout cycle resets bounds.
    func test_cornerRadius_recomputesForStripVariant() {
        let view = RoleAvatarView(role: .shipper, state: .verified, variant: .strip)
        view.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        view.layoutIfNeeded()

        XCTAssertEqual(
            view.layer.cornerRadius, 20,
            ".strip variant at 40×40 must have cornerRadius == 20 (bounds.width / 2 — " +
            "Pitfall 8 circle mitigation)."
        )

        XCTAssertEqual(
            view.statusDot.layer.cornerRadius, 6,
            ".strip variant status dot at 12×12 must have cornerRadius == 6 " +
            "(statusDot.bounds.width / 2)."
        )
    }

    // MARK: - Test 7: Pitfall 8 cornerRadius recompute (.tree variant)

    /// At bounds (0,0,32,32) the cornerRadius MUST be 16. Mirrors Test 6 at
    /// the smaller .tree variant — the same Pitfall-8 mitigation must hold
    /// across BOTH variants because both render as circles.
    func test_cornerRadius_recomputesForTreeVariant() {
        let view = RoleAvatarView(role: .broker, state: .pending, variant: .tree)
        view.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        view.layoutIfNeeded()

        XCTAssertEqual(
            view.layer.cornerRadius, 16,
            ".tree variant at 32×32 must have cornerRadius == 16 (bounds.width / 2 — " +
            "Pitfall 8 circle mitigation)."
        )

        XCTAssertEqual(
            view.statusDot.layer.cornerRadius, 5,
            ".tree variant status dot at 10×10 must have cornerRadius == 5 " +
            "(statusDot.bounds.width / 2)."
        )
    }
}
