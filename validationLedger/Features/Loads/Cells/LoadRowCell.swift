// validationLedger/Features/Loads/Cells/LoadRowCell.swift
// Phase 8 Plan 03 — LOAD-04 / TRUST-02: the role-filtered-load-list row cell.
//
// LoadRowCell is a `UICollectionViewListCell` consumed by
// `LoadListViewController`'s `UICollectionViewCompositionalLayout(.list)` +
// `UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>`. The
// cell-registration idiom in Task 4 reuses `LoadRowCell` directly via
// `UICollectionView.CellRegistration<LoadRowCell, LoadListItem>`.
//
// === Composition (Plan 02 + Plan 01) ===
// - VerificationBadgeView (Plan 02 — TRUST-02) consumes
//   `configure(stateOrNil: item.displayedCounterparty?.verificationState)`.
//   The `(stateOrNil:)` overload is the D-03 FAIL-CLOSED entry point: nil
//   counterparty renders neutral-grey UNVERIFIED visuals + the locked
//   accessibilityLabel "Counterparty not verified" (T-08-06). This cell
//   therefore NEVER reads the counterparty's `displayName` property for
//   VoiceOver — the badge speaks the verification state, the counterparty-
//   name slot is suppressed (UI-SPEC line 60).
// - LoadStatusBadgeView (Plan 02) consumes `configure(status: item.load.status)`
//   with an exhaustive 13-case switch on the badge side.
//
// === 7-field freight row layout (UI-SPEC §LoadRowCell) ===
//   reference | status-badge
//   origin → destination                      (single line, truncating tail)
//   pickup • deliver                          (footnote, secondary label)
//   equipment • weight                        (footnote, secondary label)
//   verification-badge        rate            (footnote, right-aligned rate)
//
// The cell uses a vertical UIStackView with inner horizontal stack views; the
// outer stack is layout-margins driven so DS.Spacing.md gutter survives
// Dynamic Type growth. 44pt min touch target is satisfied by the cell's
// intrinsic content height under default Dynamic Type.
//
// === T-08-07 — cell-reuse fail-closed reset ===
// `prepareForReuse()` resets BOTH badges to neutral defaults BEFORE the next
// `configure(item:)`. Without this, a recycled cell could briefly render the
// previous row's `.verified` badge against a NEW row's freight reference —
// a spoofing surface that contradicts the project's "identity that cannot be
// faked" core value. The snapshot test
// `test_prepareForReuseResetsVerificationBadgeToUnverified` locks this.
//
// === Accessibility identifiers (UI-SPEC §Accessibility Identifiers — locked) ===
// Identifiers are set on the CELL and its directly-managed subviews — NOT on
// the badges themselves (RESEARCH §Pitfall 6). XCUITest probes the row by
// `loads-list.row.{loadID}` (cell-level), then drills into
// `.verification-badge` / `.status-badge` (badge-level).
//
// === Date / number formatting (RESEARCH §"Don't Hand-Roll") ===
// - rate: NumberFormatter (currency en_US, maximumFractionDigits = 0).
// - pickup/deliver: DateFormatter (.medium date, .short time).
// - weight: NumberFormatter (.decimal, grouping separators).
// Formatters are statics on the cell so they aren't re-created per row.
//
// === Localization discipline ===
// Every user-visible string flows through `NSLocalizedString(_:value:comment:)`
// with key prefix `loads.row.*`. The wire form of `load.equipment` (e.g.
// `"dry_van"`) is rendered AS-IS per UI-SPEC §Copywriting — no client-side
// title-casing.
//
// === No logging ===
// T-08-08 — view-layer surfaces never call into the logger. The VM owns
// every log emission on the fetch path.
//
// === Test-target reachability ===
// `verificationBadge` and `statusBadge` are declared `internal let` (not
// `private let`) so the LoadRowCellSnapshotTests + LoadListViewController
// can read their `accessibilityIdentifier` / `accessibilityLabel` via
// `@testable import validationLedger`. All other UILabel subviews stay
// `private` — they are not part of the public test surface.

import UIKit

public final class LoadRowCell: UICollectionViewListCell {

    // MARK: - Static formatters (initialized once, reused per cell layout)

    private static let rateFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    private static let weightFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Subviews

    private let referenceLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.headline
        l.textColor = DS.Colors.label
        l.numberOfLines = 1
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let originDestinationLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.label
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let pickupDeliverLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 1
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let equipmentWeightLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 1
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let rateLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.label
        l.textAlignment = .right
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        // The rate must keep its trailing right-edge — give it strict
        // horizontal compression resistance so the verification badge folds
        // first under tight widths.
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    /// `internal` (not `private`) so LoadRowCellSnapshotTests + LoadList-
    /// ViewController can probe its accessibility surface via
    /// `@testable import validationLedger`.
    let verificationBadge = VerificationBadgeView()

    /// `internal` for the same reason as `verificationBadge`.
    let statusBadge = LoadStatusBadgeView()

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadRowCell is constructed programmatically only")
    }

    // MARK: - Layout

    private func setUp() {
        backgroundColor = DS.Colors.background

        verificationBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.translatesAutoresizingMaskIntoConstraints = false

        // Row 1: reference | status-badge
        let row1 = UIStackView(arrangedSubviews: [referenceLabel, statusBadge])
        row1.axis = .horizontal
        row1.alignment = .firstBaseline
        row1.spacing = DS.Spacing.sm
        // reference grows; status badge takes intrinsic
        referenceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusBadge.setContentHuggingPriority(.required, for: .horizontal)
        statusBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Row 2: origin → destination
        let row2 = UIStackView(arrangedSubviews: [originDestinationLabel])
        row2.axis = .horizontal
        row2.alignment = .firstBaseline

        // Row 3: pickup • deliver
        let row3 = UIStackView(arrangedSubviews: [pickupDeliverLabel])
        row3.axis = .horizontal
        row3.alignment = .firstBaseline

        // Row 4: equipment • weight
        let row4 = UIStackView(arrangedSubviews: [equipmentWeightLabel])
        row4.axis = .horizontal
        row4.alignment = .firstBaseline

        // Row 5: verification-badge        rate
        let row5 = UIStackView(arrangedSubviews: [verificationBadge, UIView(), rateLabel])
        row5.axis = .horizontal
        row5.alignment = .firstBaseline
        row5.spacing = DS.Spacing.sm
        verificationBadge.setContentHuggingPriority(.required, for: .horizontal)
        rateLabel.setContentHuggingPriority(.required, for: .horizontal)

        let outer = UIStackView(arrangedSubviews: [row1, row2, row3, row4, row5])
        outer.axis = .vertical
        outer.alignment = .fill
        outer.spacing = DS.Spacing.sm
        outer.isLayoutMarginsRelativeArrangement = true
        outer.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        outer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Default to a fail-closed posture on first instantiation — the cell
        // is in this state for the brief window between dequeue and the next
        // `configure(item:)`. T-08-07: matches the prepareForReuse defaults
        // so a never-configured cell never renders an upgraded trust signal.
        verificationBadge.configure(state: .unverified)
        statusBadge.configure(status: .draft)
    }

    // MARK: - Public API

    /// Render a `LoadListItem` (Plan 01 envelope) onto the cell. Idempotent:
    /// calling `configure(item:)` twice with the same item is a no-op visually.
    public func configure(item: LoadListItem) {
        let load = item.load

        referenceLabel.text = load.referenceNumber

        // UI-SPEC §Copywriting — arrow glyph, no client-side title-casing on
        // city/state strings.
        originDestinationLabel.text = "\(load.origin.city), \(load.origin.state) → \(load.destination.city), \(load.destination.state)"

        // Pickup • Deliver (.medium / .short — RESEARCH §"Don't Hand-Roll")
        let pickup = Self.dateTimeFormatter.string(from: load.pickupAt)
        let deliver = Self.dateTimeFormatter.string(from: load.deliverAt)
        pickupDeliverLabel.text = String(
            format: NSLocalizedString(
                "loads.row.pickup_deliver",
                value: "Pick up %@  •  Deliver %@",
                comment: "Phase 8 LoadRowCell — pickup and deliver date/time row"
            ),
            pickup, deliver
        )

        // Equipment • Weight. Equipment is rendered AS-IS per UI-SPEC.
        let weightText = Self.weightFormatter.string(from: NSNumber(value: load.weight))
            ?? String(load.weight)
        equipmentWeightLabel.text = String(
            format: NSLocalizedString(
                "loads.row.equipment_weight",
                value: "%@  •  %@ lbs",
                comment: "Phase 8 LoadRowCell — equipment and weight row"
            ),
            load.equipment, weightText
        )

        // Rate (currency, locale-correct).
        rateLabel.text = Self.rateFormatter.string(from: load.rate as NSDecimalNumber) ?? ""

        // === D-03 fail-closed verification badge ===
        // The `(stateOrNil:)` overload is the contract entry point:
        //   nil               → .unverified visuals + "Counterparty not verified" a11y
        //   .verified         → blue, "Counterparty verified"
        //   .pending          → yellow, "Counterparty verification pending"
        //   .unverified       → grey, "Counterparty not verified"
        //   .flagged          → red, "Counterparty flagged"
        verificationBadge.configure(stateOrNil: item.displayedCounterparty?.verificationState)

        // Status badge (Plan 02 — exhaustive 13-case switch on the badge side).
        statusBadge.configure(status: load.status)

        // Accessibility identifiers — Pitfall 6: SET ON THE CELL, not on the
        // arbitrary subview hierarchy. XCUITest probes the locked strings.
        self.accessibilityIdentifier = "loads-list.row.\(load.id)"
        verificationBadge.accessibilityIdentifier = "loads-list.row.\(load.id).verification-badge"
        statusBadge.accessibilityIdentifier = "loads-list.row.\(load.id).status-badge"
    }

    // MARK: - prepareForReuse — T-08-07 fail-closed cell-reuse reset

    public override func prepareForReuse() {
        super.prepareForReuse()
        // T-08-07 — reset both badges BEFORE the next configure(item:) lands.
        // Without this, a recycled cell could briefly render the previous
        // row's .verified pill against a NEW row's freight reference, which
        // would be a spoofing surface (a glimpse of trust that doesn't
        // belong to the new row).
        verificationBadge.configure(state: .unverified)
        statusBadge.configure(status: .draft)
        // Clear text content so a recycled cell mid-scroll doesn't show stale
        // pickup/deliver times against fresh badges.
        referenceLabel.text = nil
        originDestinationLabel.text = nil
        pickupDeliverLabel.text = nil
        equipmentWeightLabel.text = nil
        rateLabel.text = nil
        // Clear accessibilityIdentifier so a never-reconfigured cell does not
        // claim the prior row's identifier in a snapshot or VoiceOver query.
        self.accessibilityIdentifier = nil
        verificationBadge.accessibilityIdentifier = nil
        statusBadge.accessibilityIdentifier = nil
    }
}
