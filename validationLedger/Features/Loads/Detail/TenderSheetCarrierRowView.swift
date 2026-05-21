// validationLedger/Features/Loads/Detail/TenderSheetCarrierRowView.swift
//
// Phase 10 Plan 06 — D-08 / ACTION-04 (CRITICAL — T-10-04) carrier-row cell.
//
// === What this is ===
// The UITableViewCell that composes one carrier row inside the tender
// sheet's picker (Plan 06 — TenderSheetViewController). Per UI-SPEC line
// 444 + D-08: each row is RoleAvatarView(.tree) + carrier displayName +
// VerificationBadgeView + (if disabled) inline verification-reason line.
//
// === Carrier-level ACTION-04 gate (CRITICAL — T-10-04 platform thesis) ===
// Per D-08 + UI-SPEC line 446: unverified / flagged / pending carriers
// remain VISIBLE in the picker but become:
//   - contentView.alpha = 0.6        (the rest of the row dims)
//   - badgeView.alpha   = 1.0 ALWAYS (the badge is the SIGNAL — must NOT dim)
//   - isUserInteractionEnabled = false
//   - reasonLabel visible with the disabled-reason copy resolved by state
// HIDING the disabled rows is the wrong choice — the broker SEES the fraud
// signal and learns "I cannot tender to this party" (Specifics line 263).
//
// === Trust-component reuse (TRUST-02 + 9.1 R12) ===
// `VerificationBadgeView` (Phase 8) renders the 4-state pill. Its background
// color comes from `DS.Colors.Verification.color(for:)` (Phase 9.1 R12), the
// same helper `RoleAvatarView`'s status dot consumes — so the badge and the
// avatar can never drift apart.
//
// === Accessibility ===
// The row is a single accessibility element with a composed label:
//   "[carrier name], [verification state], [disabled reason if any]"
// Cell's accessibilityIdentifier is set externally (by the sheet VC) to
// `load-detail.tender-sheet/carrier-row.<partyID>` so plan 10-10 XCUITest
// queries can target rows by stable partyID interpolation (ISSUE-04 fix).
//
// === PII discipline (T-10-04 mirror of T-08-05) ===
// The cell ingests a `TrustNode` (server-supplied). NO `Logger` /
// `os_log` / `OSLog` call sites — the view layer never logs (T-09-04
// view-layer lock). Party names are rendered verbatim from the server.

import UIKit

final class TenderSheetCarrierRowView: UITableViewCell {

    // MARK: - Subviews
    //
    // Internal access so the unit-test target (`@testable import`) can assert
    // `cell.badgeViewForTesting.alpha == 1.0` (UI-SPEC line 446 invariant)
    // and `cell.reasonLabelForTesting.text == "Flagged — cannot tender"`
    // without exposing them as `public` API.

    private let avatarView: RoleAvatarView = RoleAvatarView(role: .carrier, state: .unverified, variant: .tree)

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.label
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let badgeView: VerificationBadgeView = {
        let v = VerificationBadgeView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        return v
    }()

    private let reasonLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Test seams (internal — @testable import surface)

    internal var badgeViewForTesting: VerificationBadgeView { badgeView }
    internal var reasonLabelForTesting: UILabel { reasonLabel }

    // MARK: - Reuse identifier

    static let reuseIdentifier = "TenderSheetCarrierRowView"

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        installLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("TenderSheetCarrierRowView is constructed programmatically only")
    }

    // MARK: - Layout

    private func installLayout() {
        contentView.backgroundColor = DS.Colors.background

        avatarView.translatesAutoresizingMaskIntoConstraints = false

        // Top row: avatar + name + badge.
        let topRow = UIStackView(arrangedSubviews: [avatarView, nameLabel, badgeView])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = DS.Spacing.sm
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // Outer vertical stack: top row + reason label (when visible).
        let stack = UIStackView(arrangedSubviews: [topRow, reasonLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DS.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DS.Spacing.sm),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Spacing.md),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Spacing.md),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DS.Spacing.sm),

            // Indent the reason label to align with the carrier name (UI-SPEC
            // line 386 — reason indents to align with the name's leading edge).
            // We approximate by adding leading padding equal to avatar
            // diameter + the topRow's spacing — same horizontal datum as
            // nameLabel inside topRow.
            reasonLabel.leadingAnchor.constraint(
                equalTo: stack.leadingAnchor,
                constant: RoleAvatarView.Variant.tree.diameter + DS.Spacing.sm
            ),
        ])
    }

    // MARK: - Configure

    /// Apply the carrier's verification state to the row's interaction +
    /// alpha contract per D-08 / UI-SPEC line 446. Called by the sheet's
    /// tableView(_:cellForRowAt:).
    func configure(carrier: TrustNode) {
        avatarView.configure(role: carrier.role, state: carrier.verificationState)
        nameLabel.text = carrier.displayName
        badgeView.configure(state: carrier.verificationState)

        // UI-SPEC line 446 INVARIANT — the badge stays at full alpha always.
        // The badge is the SIGNAL; dimming it would suppress the fraud cue.
        badgeView.alpha = 1.0

        switch carrier.verificationState {
        case .verified:
            // Verified row: selectable, full alpha, no inline reason.
            contentView.alpha = 1.0
            isUserInteractionEnabled = true
            reasonLabel.isHidden = true
            reasonLabel.text = nil
            accessibilityLabel = "\(carrier.displayName), verified"

        case .unverified:
            contentView.alpha = 0.6
            isUserInteractionEnabled = false
            reasonLabel.isHidden = false
            reasonLabel.text = NSLocalizedString(
                "loads.detail.tender.carrier.disabled.unverified",
                value: "Not verified — cannot tender",
                comment: "Phase 10 Plan 06 — tender-sheet carrier row, unverified disabled reason (UI-SPEC line 381)"
            )
            accessibilityLabel = "\(carrier.displayName), unverified, cannot tender"

        case .pending:
            contentView.alpha = 0.6
            isUserInteractionEnabled = false
            reasonLabel.isHidden = false
            reasonLabel.text = NSLocalizedString(
                "loads.detail.tender.carrier.disabled.pending",
                value: "Verification pending — cannot tender",
                comment: "Phase 10 Plan 06 — tender-sheet carrier row, pending disabled reason (UI-SPEC line 383)"
            )
            accessibilityLabel = "\(carrier.displayName), verification pending, cannot tender"

        case .flagged:
            contentView.alpha = 0.6
            isUserInteractionEnabled = false
            reasonLabel.isHidden = false
            reasonLabel.text = NSLocalizedString(
                "loads.detail.tender.carrier.disabled.flagged",
                value: "Flagged — cannot tender",
                comment: "Phase 10 Plan 06 — tender-sheet carrier row, flagged disabled reason (UI-SPEC line 382 — fraud archetype signal)"
            )
            accessibilityLabel = "\(carrier.displayName), flagged, cannot tender"
        }

        // The cell is a single VoiceOver element with composed label.
        isAccessibilityElement = true
        accessibilityTraits = isUserInteractionEnabled ? .button : .staticText
    }

    // MARK: - Reuse hygiene

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        contentView.alpha = 1.0
        badgeView.alpha = 1.0
        isUserInteractionEnabled = true
        reasonLabel.isHidden = true
        reasonLabel.text = nil
        accessibilityIdentifier = nil
        accessibilityLabel = nil
    }
}
