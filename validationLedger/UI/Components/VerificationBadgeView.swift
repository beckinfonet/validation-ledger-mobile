// validationLedger/UI/Components/VerificationBadgeView.swift
//
// Phase 8 TRUST-02 — the single reusable verification-state badge component.
// Phase 9 + 10 will reuse this on detail headers and chain-of-trust graph
// nodes — adding a second copy would silently allow the verification color
// ramp to drift between surfaces, which is exactly what TRUST-02 forbids.
//
// === Contract (locked) ===
// Public surface:
//   - init(frame:) / required init?(coder:) — programmatic UIKit, ARCH-04.
//   - configure(state: VerificationState)        — known state.
//   - configure(stateOrNil: VerificationState?)  — server-supplied optional;
//                                                  nil is FAIL-CLOSED (D-03).
//   - layoutSubviews() — recomputes the pill cornerRadius (Pitfall 8).
//
// === Color ramp (UI-SPEC §Color verification-badge color rules — LOCKED) ===
//   .verified   -> DS.Colors.primary       ("checkmark.seal.fill",        white)
//   .pending    -> .systemYellow*          ("clock.fill",                  .label)
//   .unverified -> .tertiarySystemFill*    ("questionmark.circle.fill",    .secondaryLabel)
//   .flagged    -> DS.Colors.destructive   ("exclamationmark.triangle.fill", white)
//
//   * Documented exceptions to the "DS tokens only" rule (UI-SPEC §Color):
//     - .systemYellow on .pending mirrors LimitedTrustBannerView's caution
//       semantic (yellow == "needs attention" — neither verified nor failed).
//     - .tertiarySystemFill on .unverified is a system-managed NEUTRAL grey
//       (NOT a chromatic color — signals "no chromatic semantic claimed").
//
// === D-03 fail-closed nil (LOCKED) ===
// `configure(stateOrNil: nil)` renders the .unverified visuals AND sets the
// accessibilityLabel to "Counterparty not verified" — the literal "not"
// prefix prevents any future test (or VoiceOver listener) from confusing
// the substring "verified" for a trust signal. T-08-06 mitigation.
//
// === Dynamic Type discipline (Pitfall 8) ===
// `layer.cornerRadius = bounds.height / 2` is recomputed in layoutSubviews()
// because the label's font scales with Dynamic Type; the corner radius must
// follow or the pill becomes a slab at large sizes. The label also pins
// `setContentCompressionResistancePriority(.required, for: .vertical)` so
// the badge grows in height rather than truncating the label.
//
// === PII discipline (T-08-05, CLAUDE.md SEC-* + PII zero-tolerance) ===
// This view is PII-FREE by construction. accessibilityLabel uses ONLY
// localized strings (no party `displayName`, no `partyID`, no load number).
// The CELL (Plan 04) is the layer that consumes party names; the badge is
// a pure render-from-input pill.
//
// === Extension contract (UI-SPEC §Color "verification-badge color rules") ===
// Adding a 5th case requires changing the `VerificationState` enum upstream
// (Core/Load/VerificationState.swift) — which would fail decode at the
// Phase 7 contract layer (D-09 fail-closed: unknown wire values degrade to
// .unverified at the decoder, never reaching this view as a "5th case").
//
// File-shape analog: validationLedger/UI/LimitedTrustBannerView.swift —
// programmatic UIView subclass with DS-token styling and per-state
// NSLocalizedString-backed accessibilityLabel.

import UIKit

public final class VerificationBadgeView: UIView {

    // MARK: - Subviews

    private let symbolView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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
        fatalError("VerificationBadgeView is constructed programmatically only")
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 8: recompute the pill cornerRadius on every layout pass so
        // Dynamic Type growth keeps the shape (full pill, never a slab).
        layer.cornerRadius = bounds.height / 2
    }

    // MARK: - setUp

    private func setUp() {
        layer.masksToBounds = true

        // Accessibility: the badge is a single VoiceOver element with static
        // text traits (UI-SPEC: non-interactive — Phase 9 makes the graph-node
        // container tappable, not the badge itself).
        isAccessibilityElement = true
        accessibilityTraits = .staticText

        let stack = UIStackView(arrangedSubviews: [symbolView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Non-interactive (UI-SPEC §Reusable Component Inventory).
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.xs),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.xs),
            // Square icon — width pinned to height so the SF Symbol stays
            // proportional as Dynamic Type grows the label height.
            symbolView.widthAnchor.constraint(equalTo: symbolView.heightAnchor),
        ])
    }

    // MARK: - Public API

    /// Render a known `VerificationState`.
    ///
    /// The state is rendered visually (background, foreground, SF Symbol,
    /// uppercase label) and as a VoiceOver `accessibilityLabel` — both are
    /// driven by `apply(state:)` so the two channels never drift.
    public func configure(state: VerificationState) {
        apply(state: state)
    }

    /// Render a server-supplied OPTIONAL `VerificationState`.
    ///
    /// D-03 FAIL-CLOSED: `nil` renders the `.unverified` visuals AND sets the
    /// accessibilityLabel to "Counterparty not verified" — the literal "not"
    /// prefix is the locked T-08-06 mitigation so the substring "verified"
    /// never appears in a security-sensitive VoiceOver context without it.
    public func configure(stateOrNil state: VerificationState?) {
        apply(state: state ?? .unverified)
    }

    // MARK: - Internal rendering

    private func apply(state: VerificationState) {
        switch state {
        case .verified:
            backgroundColor = DS.Colors.primary
            symbolView.image = UIImage(systemName: "checkmark.seal.fill")
            symbolView.tintColor = .white
            label.text = NSLocalizedString(
                "verification_badge.verified",
                value: "VERIFIED",
                comment: "Phase 8 verification-badge label — verified counterparty (TRUST-02)."
            )
            label.textColor = .white
            accessibilityLabel = NSLocalizedString(
                "verification_badge.verified.a11y",
                value: "Counterparty verified",
                comment: "Phase 8 verification-badge VoiceOver label — verified counterparty (TRUST-02)."
            )

        case .pending:
            backgroundColor = .systemYellow
            symbolView.image = UIImage(systemName: "clock.fill")
            symbolView.tintColor = .label
            label.text = NSLocalizedString(
                "verification_badge.pending",
                value: "PENDING",
                comment: "Phase 8 verification-badge label — verification pending (TRUST-02)."
            )
            label.textColor = .label
            accessibilityLabel = NSLocalizedString(
                "verification_badge.pending.a11y",
                value: "Counterparty verification pending",
                comment: "Phase 8 verification-badge VoiceOver label — verification pending."
            )

        case .unverified:
            backgroundColor = .tertiarySystemFill
            symbolView.image = UIImage(systemName: "questionmark.circle.fill")
            symbolView.tintColor = .secondaryLabel
            label.text = NSLocalizedString(
                "verification_badge.unverified",
                value: "UNVERIFIED",
                comment: "Phase 8 verification-badge label — unverified counterparty (TRUST-02, fail-closed)."
            )
            label.textColor = .secondaryLabel
            // FAIL-CLOSED: the literal "not" prefix locks T-08-06 — no future
            // edit may drop "not" without breaking the snapshot test that
            // asserts the literal substring.
            accessibilityLabel = NSLocalizedString(
                "verification_badge.unverified.a11y",
                value: "Counterparty not verified",
                comment: "Phase 8 verification-badge VoiceOver label — unverified / fail-closed (T-08-06)."
            )

        case .flagged:
            backgroundColor = DS.Colors.destructive
            symbolView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            symbolView.tintColor = .white
            label.text = NSLocalizedString(
                "verification_badge.flagged",
                value: "FLAGGED",
                comment: "Phase 8 verification-badge label — flagged counterparty (TRUST-02, fraud signal)."
            )
            label.textColor = .white
            accessibilityLabel = NSLocalizedString(
                "verification_badge.flagged.a11y",
                value: "Counterparty flagged",
                comment: "Phase 8 verification-badge VoiceOver label — flagged counterparty."
            )
        }
    }
}
