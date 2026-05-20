// validationLedger/UI/Components/LoadStatusBadgeView.swift
//
// Phase 8 — the 13-state status pill consumed by:
//   - Phase 8 LoadRowCell (this phase),
//   - Phase 9 detail header,
//   - Phase 9 timeline current-state marker.
//
// === IMPORTANT: NOT a security primitive ===
// The status badge is INFORMATIONAL. It MUST NEVER reuse the verification
// color ramp (the blue/red tokens used by VerificationBadgeView). Sharing
// color across two unrelated meanings is the design bug UI-SPEC §Color
// "Status badge color rules" explicitly forbids — and the snapshot test
// `test_statusBadgeNeverReusesVerificationRampColors` LOCKS this invariant
// for all 13 cases. The grep-based done-criterion in 08-02-PLAN.md verifies
// neither the blue (primary) nor red (destructive) DS token name appears
// anywhere in this file.
//
// === Tone tiers (UI-SPEC §Color status table — LOCKED) ===
//   Pre-life:                     .systemGray6,         .secondaryLabel
//     - .draft
//   In-progress (active):         .tertiarySystemFill,  .label
//     - .posted, .tendered, .accepted, .dispatched, .inTransit
//   Done:                         .systemGray5,         .secondaryLabel
//     - .delivered, .podCaptured, .invoiced, .funded
//   Terminal-error:               .systemGray5 + strikethrough on label
//     - .rejected, .expired, .cancelled
//
// The neutral palette (.systemGray6 / .tertiarySystemFill / .systemGray5)
// is a documented exception to "DS tokens only" — these are NON-CHROMATIC
// system-managed neutrals; they signal "no chromatic semantic claimed."
//
// === Copywriting Contract (UI-SPEC §Copywriting — LOCKED) ===
// Labels are uppercase:
//   "DRAFT / POSTED / TENDERED / ACCEPTED / DISPATCHED / IN TRANSIT /
//    DELIVERED / REJECTED / EXPIRED / CANCELLED / POD CAPTURED /
//    INVOICED / FUNDED"
//
// Note the multi-word labels ("IN TRANSIT", "POD CAPTURED") bridge the
// camelCase Swift case (`.inTransit`, `.podCaptured`) to space-separated
// uppercase wire copy — see UI-SPEC §Copywriting cell-content-status-badge-
// label row.
//
// === Pitfall 7 (LoadStatus.cancelled spelling) ===
// `LoadStatus.cancelled` is double-l on both Swift and wire sides; no
// spelling drift. Compiler-enforced exhaustive switch keeps drift from
// silently sneaking in.
//
// === Geometry / accessibility / typography ===
// Mirrors VerificationBadgeView exactly:
//   - layoutSubviews recomputes layer.cornerRadius = bounds.height/2 (Pitfall 8)
//   - DS.Spacing.xs four-edge padding
//   - DS.Typography.footnote, adjustsFontForContentSizeCategory = true
//   - isAccessibilityElement = true, accessibilityTraits = .staticText
//   - isUserInteractionEnabled = false on the internal stack
//
// === Layout shape ===
// LABEL-ONLY (no SF Symbol slot) per UI-SPEC §Color status table — the
// status badge has no symbol icon, only the uppercase label.
//
// === PII discipline (T-08-05) ===
// Pure render-from-input. accessibilityLabel uses ONLY localized strings.
// Per T-08-06: this view does NOT consume `VerificationState` — verification
// semantics are isolated to `VerificationBadgeView`. UI-SPEC: "The status
// badge does NOT reuse the verification ramp."

import UIKit

public final class LoadStatusBadgeView: UIView {

    // MARK: - Subviews

    private let label: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        return l
    }()

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadStatusBadgeView is constructed programmatically only")
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 8: recompute pill cornerRadius on every layout pass so
        // Dynamic Type growth keeps the shape (full pill, never a slab).
        layer.cornerRadius = bounds.height / 2
    }

    // MARK: - setUp

    private func setUp() {
        layer.masksToBounds = true

        isAccessibilityElement = true
        accessibilityTraits = .staticText

        // Label-only layout (no SF Symbol slot per UI-SPEC §Color status table).
        // Using a stack keeps the structural shape consistent with
        // VerificationBadgeView and reserves an additive seam for a future
        // status-symbol experiment without changing the public surface.
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.xs),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.xs),
        ])
    }

    // MARK: - Public API

    /// Render any of the 13 `LoadStatus` cases per the UI-SPEC §Color status
    /// table 3-tone mapping. The switch is EXHAUSTIVE — relying on the closed
    /// `LoadStatus` enum's CaseIterable + Swift's exhaustiveness check is the
    /// locked discipline per Phase 7 D-01 (no `@unknown default` allowed; a
    /// future case addition must update the upstream enum AND this switch).
    public func configure(status: LoadStatus) {
        apply(status: status)
    }

    // MARK: - Internal rendering

    private func apply(status: LoadStatus) {
        // Compute the (background, foreground, label, strikethrough) tuple
        // for every one of the 13 cases. Exhaustive switch — compiler enforces
        // total coverage.
        let backgroundColor: UIColor
        let foregroundColor: UIColor
        let labelText: String
        let isTerminalErrorStrikethrough: Bool

        switch status {
        // -- Pre-life tone --
        case .draft:
            backgroundColor = .systemGray6
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.draft.label",
                value: "DRAFT",
                comment: "Phase 8 status-badge label — draft (pre-life tone)."
            )
            isTerminalErrorStrikethrough = false

        // -- In-progress (active) tone --
        case .posted:
            backgroundColor = .tertiarySystemFill
            foregroundColor = .label
            labelText = NSLocalizedString(
                "status_badge.posted.label",
                value: "POSTED",
                comment: "Phase 8 status-badge label — posted (in-progress)."
            )
            isTerminalErrorStrikethrough = false

        case .tendered:
            backgroundColor = .tertiarySystemFill
            foregroundColor = .label
            labelText = NSLocalizedString(
                "status_badge.tendered.label",
                value: "TENDERED",
                comment: "Phase 8 status-badge label — tendered (in-progress)."
            )
            isTerminalErrorStrikethrough = false

        case .accepted:
            backgroundColor = .tertiarySystemFill
            foregroundColor = .label
            labelText = NSLocalizedString(
                "status_badge.accepted.label",
                value: "ACCEPTED",
                comment: "Phase 8 status-badge label — accepted (in-progress)."
            )
            isTerminalErrorStrikethrough = false

        case .dispatched:
            backgroundColor = .tertiarySystemFill
            foregroundColor = .label
            labelText = NSLocalizedString(
                "status_badge.dispatched.label",
                value: "DISPATCHED",
                comment: "Phase 8 status-badge label — dispatched (in-progress)."
            )
            isTerminalErrorStrikethrough = false

        case .inTransit:
            backgroundColor = .tertiarySystemFill
            foregroundColor = .label
            labelText = NSLocalizedString(
                "status_badge.in_transit.label",
                value: "IN TRANSIT",
                comment: "Phase 8 status-badge label — in transit (in-progress, space-separated)."
            )
            isTerminalErrorStrikethrough = false

        // -- Done tone --
        case .delivered:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.delivered.label",
                value: "DELIVERED",
                comment: "Phase 8 status-badge label — delivered (done tone)."
            )
            isTerminalErrorStrikethrough = false

        case .podCaptured:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.pod_captured.label",
                value: "POD CAPTURED",
                comment: "Phase 8 status-badge label — POD captured (done tone, space-separated)."
            )
            isTerminalErrorStrikethrough = false

        case .invoiced:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.invoiced.label",
                value: "INVOICED",
                comment: "Phase 8 status-badge label — invoiced (done tone)."
            )
            isTerminalErrorStrikethrough = false

        case .funded:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.funded.label",
                value: "FUNDED",
                comment: "Phase 8 status-badge label — funded (done tone)."
            )
            isTerminalErrorStrikethrough = false

        // -- Terminal-error tone (with strikethrough on the label) --
        case .rejected:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.rejected.label",
                value: "REJECTED",
                comment: "Phase 8 status-badge label — rejected (terminal-error tone)."
            )
            isTerminalErrorStrikethrough = true

        case .expired:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.expired.label",
                value: "EXPIRED",
                comment: "Phase 8 status-badge label — expired (terminal-error tone)."
            )
            isTerminalErrorStrikethrough = true

        case .cancelled:
            backgroundColor = .systemGray5
            foregroundColor = .secondaryLabel
            labelText = NSLocalizedString(
                "status_badge.cancelled.label",
                value: "CANCELLED",
                comment: "Phase 8 status-badge label — cancelled (terminal-error tone). Pitfall 7: double-l spelling on both Swift and wire side."
            )
            isTerminalErrorStrikethrough = true
        }

        // Apply the resolved styling.
        self.backgroundColor = backgroundColor
        label.textColor = foregroundColor

        if isTerminalErrorStrikethrough {
            // UI-SPEC §Color status table — terminal-error tones render with
            // strikethrough on the label.
            //
            // IMPORTANT: do NOT assign `label.text = nil` after setting
            // `attributedText`. UILabel's `text` setter (even to nil) clears
            // the previously-set `attributedText`, which silently strips the
            // strikethrough at runtime. Setting `attributedText` is enough —
            // `text` returns the plain string of the attributed payload.
            label.attributedText = NSAttributedString(
                string: labelText,
                attributes: [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: foregroundColor,
                ]
            )
        } else {
            // Reset any prior strikethrough that a recycled cell might carry.
            // Order matters: clear `attributedText` BEFORE assigning `text`
            // — otherwise the prior attributedText survives a `text =` set
            // in some iOS versions (mirror image of the trap above).
            label.attributedText = nil
            label.text = labelText
        }

        // accessibilityLabel — VoiceOver-ready, with "Status: " prefix so the
        // user knows this is a load status rather than free-floating text.
        // Uses the same NSLocalizedString discipline as the verification badge.
        accessibilityLabel = a11yLabel(for: status)
    }

    /// Per-case VoiceOver string. Uses NSLocalizedString so the v2 i18n pass
    /// can localize each independently of the on-screen uppercase label.
    private func a11yLabel(for status: LoadStatus) -> String {
        switch status {
        case .draft:
            return NSLocalizedString("status_badge.draft.a11y",
                value: "Status: Draft",
                comment: "VoiceOver — load status, draft.")
        case .posted:
            return NSLocalizedString("status_badge.posted.a11y",
                value: "Status: Posted",
                comment: "VoiceOver — load status, posted.")
        case .tendered:
            return NSLocalizedString("status_badge.tendered.a11y",
                value: "Status: Tendered",
                comment: "VoiceOver — load status, tendered.")
        case .accepted:
            return NSLocalizedString("status_badge.accepted.a11y",
                value: "Status: Accepted",
                comment: "VoiceOver — load status, accepted.")
        case .dispatched:
            return NSLocalizedString("status_badge.dispatched.a11y",
                value: "Status: Dispatched",
                comment: "VoiceOver — load status, dispatched.")
        case .inTransit:
            return NSLocalizedString("status_badge.in_transit.a11y",
                value: "Status: In transit",
                comment: "VoiceOver — load status, in transit.")
        case .delivered:
            return NSLocalizedString("status_badge.delivered.a11y",
                value: "Status: Delivered",
                comment: "VoiceOver — load status, delivered.")
        case .podCaptured:
            return NSLocalizedString("status_badge.pod_captured.a11y",
                value: "Status: POD captured",
                comment: "VoiceOver — load status, POD captured.")
        case .invoiced:
            return NSLocalizedString("status_badge.invoiced.a11y",
                value: "Status: Invoiced",
                comment: "VoiceOver — load status, invoiced.")
        case .funded:
            return NSLocalizedString("status_badge.funded.a11y",
                value: "Status: Funded",
                comment: "VoiceOver — load status, funded.")
        case .rejected:
            return NSLocalizedString("status_badge.rejected.a11y",
                value: "Status: Rejected",
                comment: "VoiceOver — load status, rejected.")
        case .expired:
            return NSLocalizedString("status_badge.expired.a11y",
                value: "Status: Expired",
                comment: "VoiceOver — load status, expired.")
        case .cancelled:
            return NSLocalizedString("status_badge.cancelled.a11y",
                value: "Status: Cancelled",
                comment: "VoiceOver — load status, cancelled. Pitfall 7: double-l on both sides.")
        }
    }
}
