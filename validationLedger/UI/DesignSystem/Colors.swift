// validationLedger/UI/DesignSystem/Colors.swift
// Phase-1 design system color tokens. Skeleton only — expanded in Phase 3+.
// All colors default to iOS system semantic colors so dark-mode + Dynamic
// Type support is automatic.

import UIKit

public enum DS {
    public enum Colors {
        public static let primary:    UIColor = .systemBlue
        public static let background: UIColor = .systemBackground
        public static let surface:    UIColor = .secondarySystemBackground
        public static let label:      UIColor = .label
        public static let labelSecondary: UIColor = .secondaryLabel
        public static let separator:  UIColor = .separator
        // Phase 5 (05-UI-SPEC) — failed-upload status, rejection-reason text,
        // inline error labels, and destructive confirmation actions.
        public static let destructive: UIColor = .systemRed
        // Phase 9 (09-UI-SPEC § Banner lines 212-225, § Verdict block lines
        // 389-402) — caution-tier chain-integrity surfaces: yellow banner
        // background and 0.15-alpha verdict-block tint. The token consolidates
        // the "this needs attention" color hand across the chain-integrity
        // banner + verdict block + flagged-edge dash + caution halo so future
        // re-tinting touches one site. Uses `.systemYellow` so dark-mode and
        // dynamic-range adapt automatically (matches LimitedTrustBannerView
        // line 71 precedent of `UIColor.systemYellow`).
        public static let caution:     UIColor = .systemYellow

        // ====================================================================
        // TRUST-02 INVARIANT (Phase 9.1 — single source-of-truth color ramp)
        // ====================================================================
        // The verification color ramp lives in EXACTLY ONE PLACE: the
        // `Verification.color(for:)` helper below. Two views consume it:
        //   1. `VerificationBadgeView` — pill background (Phase 8, refactored
        //      in 9.1 Plan 01 Task 2 to call the helper instead of switching
        //      inline).
        //   2. `RoleAvatarView` — bottom-right status-dot fill (Phase 9.1
        //      Plan 02, arriving after this file ships).
        //
        // NO OTHER CODE in the codebase may switch on `VerificationState` to
        // assign a `UIColor`. The 9.1 negative-grep gate (R12 / CONTEXT D-04)
        // enforces this by asserting `git grep -l 'DS\.Colors\.Verification\.color'`
        // returns exactly the expected consumer set:
        //   - Plan 01: { VerificationBadgeView.swift }
        //   - Plan 02 onward: { VerificationBadgeView.swift, RoleAvatarView.swift }
        // and the R12 strict gate asserts no `.swift` file outside `Colors.swift`
        // maps `VerificationState` cases to color literals.
        //
        // ORIGINAL HOME (Phase 8): `VerificationBadgeView.swift` header. The
        // ramp moved here in 9.1 so the avatar status dot can consume the
        // same source without duplication — a structural guarantee that
        // strengthens the Phase 8 comment-and-discipline lock into a
        // tooling-enforced invariant.
        //
        // Color ramp (UI-SPEC §New token additions — LOCKED):
        //   .verified   → DS.Colors.primary       (.systemBlue)
        //   .pending    → .systemYellow            (documented exception —
        //                                           "needs attention" semantic)
        //   .unverified → .tertiarySystemFill      (neutral grey — no chromatic
        //                                           semantic claimed; T-08-06
        //                                           fail-closed safe color)
        //   .flagged    → DS.Colors.destructive   (.systemRed — fraud signal)
        //
        // Adding a 5th `VerificationState` case requires changing the enum
        // upstream (`Core/Load/VerificationState.swift`) AND adding a case
        // here; the Swift compiler enforces exhaustiveness on the `switch`.

        /// TRUST-02 single-source-of-truth verification color ramp.
        /// Consumed by `VerificationBadgeView` (pill background) and
        /// `RoleAvatarView` (status-dot fill). Locked by SPEC R12 + the
        /// CONTEXT D-04 negative-grep gate.
        public enum Verification {
            /// Map a `VerificationState` to its canonical UI color.
            public static func color(for state: VerificationState) -> UIColor {
                switch state {
                case .verified:   return DS.Colors.primary           // .systemBlue
                case .pending:    return .systemYellow                // documented exception
                case .unverified: return .tertiarySystemFill          // neutral grey
                case .flagged:    return DS.Colors.destructive       // .systemRed
                }
            }
        }

        /// Per-role avatar circle palette (UI-SPEC §Per-Role Avatar Palette —
        /// LOCKED). The SINGLE SOURCE OF TRUTH for `Role → UIColor` mapping.
        /// Consumed by `RoleAvatarView` (avatar circle fill, Phase 9.1 Plan 02
        /// onward). No other code in the codebase may switch on `Role` to
        /// assign a color.
        ///
        /// Per-role values (locked from the reference photo):
        ///   .shipper   → .systemBlue
        ///   .broker    → .systemOrange
        ///   .carrier   → .systemGreen
        ///   .dispatch  → .systemPurple
        ///   .factoring → .systemTeal     (hue-distinct from .systemBlue
        ///                                 shipper at iPhone widths under
        ///                                 light + dark mode — a11y-contrast
        ///                                 review deferred per CONTEXT)
        public enum Roles {
            /// Map a `Role` to its canonical avatar fill color.
            public static func color(for role: Role) -> UIColor {
                switch role {
                case .shipper:   return .systemBlue
                case .broker:    return .systemOrange
                case .carrier:   return .systemGreen
                case .dispatch:  return .systemPurple
                case .factoring: return .systemTeal
                }
            }
        }
    }
}
