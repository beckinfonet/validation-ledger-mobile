// validationLedger/UI/Components/RoleAvatarView.swift
//
// Phase 9.1 R1 — the shared role-avatar primitive. A per-role colored circle
// with a centered 3-letter abbreviation and a bottom-right verification-state
// status dot. Lives in `UI/Components/` alongside `VerificationBadgeView`
// because both are reusable primitives consumed across multiple feature
// surfaces (strip chips in `EveryoneOnLoadStripView`, tree rows in
// `ChainOfVouchesView`, and any future surface that needs a "who is this
// counterparty and is the trust signal current?" glyph).
//
// === Contract (locked) ===
// Public surface:
//   - init(role: Role, state: VerificationState, variant: Variant = .strip)
//       — programmatic-only ARCH-04 constructor.
//   - required init?(coder:) — traps with fatalError (ARCH-04).
//   - configure(role: Role, state: VerificationState)
//       — reconfigure an existing instance (no realloc / no reinstall of
//         constraints). Mirrors `VerificationBadgeView.configure(state:)`.
//   - layoutSubviews() — recomputes `layer.cornerRadius = bounds.width / 2`
//                         and `statusDot.layer.cornerRadius = statusDot.bounds.width / 2`
//                         (Pitfall 8 — circle, not pill).
//
// === Variants (UI-SPEC § Component Geometry → RoleAvatarView table) ===
//   .strip  — 40×40pt circle, 12×12pt status dot, dot offset (+2, +2) from
//             the avatar's bottom-right corner. Consumed by the strip chips.
//   .tree   — 32×32pt circle, 10×10pt status dot, dot offset (+1, +1).
//             Consumed by the vertical attribution tree rows.
//
// === Color sources (TRUST-02 single source-of-truth — R12, D-03) ===
//   - Avatar circle fill: `DS.Colors.Roles.color(for: role)` (the ONLY
//     `Role → UIColor` mapping in the codebase).
//   - Status dot fill:    `DS.Colors.Verification.color(for: state)` (the
//     ONLY `VerificationState → UIColor` mapping in the codebase; same
//     helper `VerificationBadgeView` consumes for its pill background).
//   - Status dot stroke:  2pt `DS.Colors.background` (the "punched-out"
//                          effect — UI-SPEC § Component Geometry).
//
// The TRUST-02 invariant block lives at the helper declaration site in
// `validationLedger/UI/DesignSystem/Colors.swift`. The R12 negative-grep
// gate (CONTEXT D-04 / VALIDATION) asserts the expected-consumer set is
// EXACTLY `{ VerificationBadgeView.swift, RoleAvatarView.swift }` after
// this plan ships.
//
// === Abbreviation literals (R1, UI-SPEC § Per-Role Avatar Palette) ===
// The 3-letter labels are LOCKED LITERALS (`SHP`/`BRK`/`CAR`/`DSP`/`FCT`),
// returned by a private static `abbreviation(for:)` switch. NOT derived
// from `Role.rawValue` or `Role.displayName` — if the enum case names ever
// change (e.g. `.broker` → `.broker_v2`), the abbreviations MUST stay
// canonical. A unit test (`test_abbreviationLiterals_match_lockedSwitch`)
// asserts each literal exactly.
//
// === Accessibility (R6 leaf-element model) ===
// `isAccessibilityElement = false` — the avatar is DECORATIVE. The
// composed VoiceOver label is owned by the parent (strip-chip view or
// tree-row view) per the R6 leaf-element model. A parent with the
// composed string `"Broker FreightWise, vouched by Shipper Global, verified"`
// surfaces a single rich element rather than three separate ones; the
// avatar is purely visual chrome inside that element.
//
// `isUserInteractionEnabled = false` — chip wrappers (in Plan 03's
// EveryoneOnLoadStripView) own the tap recognizer, not the avatar. Tree
// rows are non-interactive in 9.1 (per CONTEXT `<deferred>` —
// tap-on-tree-row → verification-basis sheet is a future iteration).
//
// === Dynamic Type exception (deliberate, documented) ===
// The abbreviation label font is `UIFont.systemFont(ofSize: 11, weight: .semibold)`
// — a LITERAL POINT SIZE, NOT Dynamic Type. Rationale: scaling the
// abbreviation either overflows the 32pt/40pt avatar circle at large
// AX content sizes, or shrinks the circle to a dot to compensate.
// Avatar circle scaling with Dynamic Type is deferred per
// `09.1-CONTEXT.md <deferred>` ("Larger / smaller chip size on the strip
// for accessibility size classes"). UI-SPEC § Accessibility Contract
// explicitly carves out this exception alongside CR-03 (the footer pill
// icon DOES scale, because its parent label scales — different rules).
//
// === PII discipline (T-09.1-02, CLAUDE.md SEC-star + PII zero-tolerance) ===
// This view is PII-FREE by construction. It ingests (role, state) only —
// no displayName, no partyID, no load number. NO view-layer log call
// sites appear in this file (the standard iOS logging APIs and stdout
// emit functions are forbidden here). The threat model T-09.1-02
// mitigation is enforced by a verify-block grep gate that fails on any
// match in the codified denylist.
//
// === Extension contract ===
// Adding a 6th `Role` case requires:
//   1. Extending `Role` (Roles/Role.swift) — compiler enforces exhaustiveness.
//   2. Adding the role to `DS.Colors.Roles.color(for:)`.
//   3. Adding the literal to this view's `abbreviation(for:)` switch.
//   4. Adding a snapshot row for the new role.
// The Swift compiler catches steps 1+2+3 by exhaustiveness; step 4 is a
// process discipline locked by the 5×4×2 = 40 snapshot matrix.
//
// File-shape analog: validationLedger/UI/Components/VerificationBadgeView.swift —
// the structural twin (programmatic UIView, DS-token chrome, per-input
// configure(), layoutSubviews cornerRadius recompute, required init?(coder:)
// trap).

import UIKit

public final class RoleAvatarView: UIView {

    // MARK: - Variant

    /// Size variant — locks all geometry (avatar diameter, status-dot
    /// diameter, status-dot offset) per UI-SPEC § Component Geometry.
    public enum Variant {
        /// 40×40pt circle, 12×12pt status dot at (+2, +2) offset. Consumed
        /// by the strip chips in `EveryoneOnLoadStripView`.
        case strip
        /// 32×32pt circle, 10×10pt status dot at (+1, +1) offset. Consumed
        /// by the tree rows in `ChainOfVouchesView`.
        case tree

        /// Diameter of the avatar circle in points.
        public var diameter: CGFloat {
            switch self {
            case .strip: return 40
            case .tree:  return 32
            }
        }

        /// Diameter of the status dot (bottom-right) in points.
        public var dotDiameter: CGFloat {
            switch self {
            case .strip: return 12
            case .tree:  return 10
            }
        }

        /// Bottom-right offset of the status dot from the avatar's
        /// trailing/bottom edge in points (positive = outward).
        public var dotInset: CGPoint {
            switch self {
            case .strip: return CGPoint(x: 2, y: 2)
            case .tree:  return CGPoint(x: 1, y: 1)
            }
        }
    }

    // MARK: - Subviews
    //
    // Internal access so the unit-test target (under `@testable import`) can
    // assert `view.statusDot.backgroundColor == DS.Colors.Verification.color(for:)`
    // and `view.abbreviationLabel.text == "SHP"` (R12 helper-equality +
    // abbreviation literal locks). Matches the precedent of allowing test
    // introspection without exposing these as `public` API.

    /// The 3-letter role abbreviation (e.g. `"SHP"`). Literal point size
    /// (NOT Dynamic Type — see header "Dynamic Type exception").
    let abbreviationLabel: UILabel = {
        let l = UILabel()
        // Documented exception: LITERAL point size, NOT Dynamic Type.
        // Avatar circle geometry is fixed (40pt / 32pt); scaling the
        // abbreviation either overflows the circle or shrinks the
        // visible glyph below readability. Avatar Dynamic-Type scaling
        // is deferred per 09.1-CONTEXT.md <deferred>.
        l.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = false
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// The bottom-right verification-state status dot. Fill comes from
    /// `DS.Colors.Verification.color(for: state)` (R12); 2pt stroke in
    /// `DS.Colors.background` creates the "punched-out" effect against
    /// the parent surface.
    let statusDot: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.borderWidth = 2
        v.layer.borderColor = DS.Colors.background.cgColor
        v.isUserInteractionEnabled = false
        return v
    }()

    // MARK: - State

    /// The size variant — locked at init time. Drives every geometry
    /// constant (diameter, dot diameter, dot inset).
    public let variant: Variant

    // MARK: - Init

    public init(role: Role, state: VerificationState, variant: Variant = .strip) {
        self.variant = variant
        super.init(frame: .zero)
        setUp()
        configure(role: role, state: state)
    }

    public required init?(coder: NSCoder) {
        fatalError("RoleAvatarView is constructed programmatically only")
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 8 — circle, not pill. Recompute the cornerRadius on every
        // layout pass so the avatar stays a perfect circle even if the
        // bounds change (e.g. a test sets a fresh bounds before snapshot).
        layer.cornerRadius = bounds.width / 2
        statusDot.layer.cornerRadius = statusDot.bounds.width / 2
    }

    // MARK: - setUp

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = false  // status dot's stroke extends beyond bounds — must NOT clip.

        // R6 leaf-element model: the avatar is decorative. The parent owns
        // the composed accessibility label.
        isAccessibilityElement = false
        // Chip wrappers (Plan 03) own the tap recognizer, not the avatar.
        isUserInteractionEnabled = false

        addSubview(abbreviationLabel)
        addSubview(statusDot)

        NSLayoutConstraint.activate([
            // Square avatar — width == height; both pinned to the variant
            // diameter so the view has an intrinsic size for autolayout
            // parents and snapshot canvases.
            widthAnchor.constraint(equalTo: heightAnchor),
            widthAnchor.constraint(equalToConstant: variant.diameter),

            // Abbreviation label centered inside the circle.
            abbreviationLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            abbreviationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Status dot — fixed diameter, bottom-right with the variant's
            // outward inset (so the dot's center sits at the avatar's
            // bottom-right edge per UI-SPEC).
            statusDot.widthAnchor.constraint(equalToConstant: variant.dotDiameter),
            statusDot.heightAnchor.constraint(equalToConstant: variant.dotDiameter),
            statusDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: variant.dotInset.x),
            statusDot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: variant.dotInset.y),
        ])
    }

    // MARK: - Public API

    /// Reconfigure the avatar's role + verification state. Both color
    /// assignments flow through the TRUST-02 single-source-of-truth
    /// helpers in `DS.Colors` (R12 + D-03 + UI-SPEC § Per-Role Avatar
    /// Palette). The abbreviation literal is reset from the locked
    /// `abbreviation(for:)` switch.
    public func configure(role: Role, state: VerificationState) {
        backgroundColor = DS.Colors.Roles.color(for: role)
        statusDot.backgroundColor = DS.Colors.Verification.color(for: state)
        abbreviationLabel.text = Self.abbreviation(for: role)
    }

    // MARK: - Internal — abbreviation literal lock

    /// LOCKED literal abbreviations per role (R1, UI-SPEC § Per-Role Avatar
    /// Palette). NOT derived from `Role.rawValue` / `Role.displayName`.
    /// `test_abbreviationLiterals_match_lockedSwitch` asserts each literal
    /// exactly so a future enum-case rename (or a developer "let's just
    /// derive from prefix(3)" refactor) is caught at the test layer.
    private static func abbreviation(for role: Role) -> String {
        switch role {
        case .shipper:   return "SHP"
        case .broker:    return "BRK"
        case .carrier:   return "CAR"
        case .dispatch:  return "DSP"
        case .factoring: return "FCT"
        }
    }
}
