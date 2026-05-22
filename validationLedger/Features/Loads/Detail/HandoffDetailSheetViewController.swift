// validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift
//
// Phase 9 Plan 08 — TRUST-04 / D-07 / D-08 / D-11 / D-18.
//
// === What this is ===
// The handoff-detail modal sheet content view-controller. Fired by a
// single-tap on an edge's invisible 28pt-band companion view (Plan 06
// `EdgeCompanionView`) and presented via `UISheetPresentationController`
// (Plan 08 — LoadDetailViewController owns the presentation through the
// shared `presentAsSheet(_:)` helper; this VC owns the content).
//
// Mirrors the file shape of `VerificationBasisSheetViewController` (Plan 07)
// with SMALLER content — UI-SPEC line 470 calls out the handoff sheet as
// "naturally less dense" than the TRUST-03 sheet. The `.medium` detent
// (~50% screen height) is the natural resting position; the user can drag
// to `.large` if they prefer. Same sheet infrastructure recipe per D-08
// (the shared `presentAsSheet(_:)` helper on LoadDetailViewController).
//
// === Content order (UI-SPEC § HandoffDetailSheetViewController lines 459-471) ===
//   1. Header               — "Handoff" title + "{fromRole} → {toRole}"
//                              subtitle + "{fromDisplayName} →
//                              {toDisplayName}" body line.
//   2. Relationship row     — reused `VerificationBadgeView` configured
//                              with `edge.relationshipState` + label
//                              "Relationship: {STATE}".
//   3. Tender-reference row — When `edge.tenderRef != nil`:
//                              "Tender reference: {tenderRef}" with the
//                              ref in `.headline` weight (NSAttributed-
//                              String). When `nil`: a single `.body` line
//                              "No formal tender on file." (UI-SPEC line
//                              731 — informational, not alarming, no
//                              icon).
//   4. Implicated block     — D-11: ONLY when `edge.edgeID ∈
//                              integrity.implicatedEdgeIDs`. Soft 0.15
//                              tint (yellow for caution / red for
//                              compromised) + verdict icon + verbatim
//                              `integrity.reason`.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): every visual flows
// VERBATIM from server-supplied TrustEdge + TrustNode + ChainIntegrity
// fields. No derive*() method exists in this file. The implicated-block
// render is gated by a pure Set-membership lookup
// (`integrity.implicatedEdgeIDs.contains(edge.edgeID)`).
//
// T-09-04 (PII): zero logger calls in this file (verified by the negative
// grep gate in 09-08-PLAN.md acceptance criteria). Tender references and
// party display names are server-supplied and rendered verbatim without
// being logged.
//
// T-09-10 (Sheet detent configuration): the locked
// `largestUndimmedDetentIdentifier = .medium` lives on the PRESENTING
// side (LoadDetailViewController) — Plan 07 added one occurrence; Plan
// 08 adds the second. Both presentations share the recipe through
// `presentAsSheet(_:)`.
//
// === Accessibility identifiers (UI-SPEC lines 782-784 — LOCKED) ===
//   - view: `load-detail.handoff-detail-sheet`
//   - header section container: `load-detail.handoff-detail-sheet.edge.<edgeID>`
//                               (the edge-partition identifier per UI-SPEC
//                               line 783 — set on the header container so
//                               XCUITest can assert which edge's sheet
//                               opened without colliding with the root
//                               identifier; UI-SPEC line 783 leaves the
//                               placement open and this is the cleanest
//                               descendant target)
//   - implicated block: `load-detail.handoff-detail-sheet.implicated-block`
//
// === Dynamic Type discipline ===
// Every label sets `adjustsFontForContentSizeCategory = true`. The
// tender-reference row uses NSAttributedString with `.body` and `.headline`
// preferred-font weights so the ref renders bolder than the prefix while
// both scale with Dynamic Type. Icons scale via
// `UIImage.SymbolConfiguration(textStyle:)`.
//
// === iOS 17 deployment minimum ===
// No iOS 18-only APIs used. `UIStackView`, `UIScrollView`,
// `NSAttributedString`, `UIImage.SymbolConfiguration(textStyle:)` are iOS
// 13+/14+.

import UIKit

public final class HandoffDetailSheetViewController: UIViewController {

    // MARK: - Stored

    private let edge: TrustEdge
    private let fromNode: TrustNode
    private let toNode: TrustNode
    private let integrity: ChainIntegrity

    // MARK: - Layout — scroll container so the content survives the
    // smallest dynamic-type-friendly canvas. Mirrors the Plan 07 posture
    // even though the content is shorter (UI-SPEC line 470).

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = DS.Spacing.lg
        s.translatesAutoresizingMaskIntoConstraints = false
        s.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.lg, left: DS.Spacing.md,
            bottom: DS.Spacing.lg, right: DS.Spacing.md
        )
        s.isLayoutMarginsRelativeArrangement = true
        return s
    }()

    // MARK: - Init

    public init(edge: TrustEdge, fromNode: TrustNode, toNode: TrustNode, integrity: ChainIntegrity) {
        self.edge = edge
        self.fromNode = fromNode
        self.toNode = toNode
        self.integrity = integrity
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("HandoffDetailSheetViewController is constructed programmatically only")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        view.accessibilityIdentifier = "load-detail.handoff-detail-sheet"

        installScrollContainer()
        composeContent()
    }

    // MARK: - Scroll container

    private func installScrollContainer() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Pin contentStack to the scroll view's content layout guide for
            // scroll geometry, and to the frame layout guide horizontally so
            // the stack's width matches the visible scroll area (Plan 07 +
            // KYCStatusViewController precedent).
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    // MARK: - Content composition

    private func composeContent() {
        // 1. Header — also carries the edge-partition identifier so
        //    XCUITest can assert which edge's sheet opened (UI-SPEC line
        //    783 — placement left to the planner; the header container is
        //    the cleanest non-root target).
        contentStack.addArrangedSubview(makeHeader(edge: edge, fromNode: fromNode, toNode: toNode))

        // 2. Relationship-state row (always — every edge carries a state).
        contentStack.addArrangedSubview(makeRelationshipStateRow(state: edge.relationshipState))

        // 3. Tender-reference row — branches on `tenderRef` presence per
        //    UI-SPEC lines 730-731.
        contentStack.addArrangedSubview(makeTenderReferenceRow(tenderRef: edge.tenderRef))

        // 4. Implicated block (D-11 — ONLY when implicated).
        if integrity.implicatedEdgeIDs.contains(edge.edgeID) {
            contentStack.addArrangedSubview(makeImplicatedBlock(integrity: integrity))
        }
    }

    // MARK: - Header (title + role arrow + display-name line)

    private func makeHeader(edge: TrustEdge, fromNode: TrustNode, toNode: TrustNode) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = DS.Typography.headline
        titleLabel.textColor = DS.Colors.label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.text = NSLocalizedString(
            "loads.detail.handoff.title",
            value: "Handoff",
            comment: "Phase 9 handoff-detail sheet — header title (UI-SPEC line 728)."
        )

        // "{fromRole.displayName} → {toRole.displayName}" — UI-SPEC line 728.
        let subtitleLabel = UILabel()
        subtitleLabel.font = DS.Typography.body
        subtitleLabel.textColor = DS.Colors.label
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        subtitleLabel.text = "\(fromNode.role.displayName) → \(toNode.role.displayName)"

        // "{fromNode.displayName} → {toNode.displayName}" — UI-SPEC line 728
        // bottom line. Renders the actual party display names beneath the
        // role-only arrow line.
        let displayNamesLabel = UILabel()
        displayNamesLabel.font = DS.Typography.body
        displayNamesLabel.textColor = DS.Colors.labelSecondary
        displayNamesLabel.adjustsFontForContentSizeCategory = true
        displayNamesLabel.numberOfLines = 0
        displayNamesLabel.text = "\(fromNode.displayName) → \(toNode.displayName)"

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, displayNamesLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Spacing.xs

        // Edge-partition identifier (UI-SPEC line 783). The XCUITest can
        // assert this descendant resolves WITHOUT colliding with the root
        // sheet identifier on `view`.
        stack.accessibilityIdentifier = "load-detail.handoff-detail-sheet.edge.\(edge.edgeID)"
        return stack
    }

    // MARK: - Relationship-state row (badge + label)

    private func makeRelationshipStateRow(state: VerificationState) -> UIView {
        let badge = VerificationBadgeView()
        badge.configure(state: state)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.font = DS.Typography.body
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1

        // "Relationship: {STATE}" — UI-SPEC line 729 — STATE is the
        // uppercased VerificationState label (matches Phase 8
        // VerificationBadgeView's locked copy: VERIFIED / PENDING /
        // UNVERIFIED / FLAGGED). NSLocalizedString-wrapped per state so
        // future localization can vary the prefix per language.
        let template: String
        switch state {
        case .verified:
            template = NSLocalizedString(
                "loads.detail.handoff.relationship.verified",
                value: "Relationship: VERIFIED",
                comment: "Phase 9 handoff-detail sheet — relationship row, verified state (UI-SPEC line 729)."
            )
        case .pending:
            template = NSLocalizedString(
                "loads.detail.handoff.relationship.pending",
                value: "Relationship: PENDING",
                comment: "Phase 9 handoff-detail sheet — relationship row, pending state (UI-SPEC line 729)."
            )
        case .unverified:
            template = NSLocalizedString(
                "loads.detail.handoff.relationship.unverified",
                value: "Relationship: UNVERIFIED",
                comment: "Phase 9 handoff-detail sheet — relationship row, unverified state (UI-SPEC line 729)."
            )
        case .flagged:
            template = NSLocalizedString(
                "loads.detail.handoff.relationship.flagged",
                value: "Relationship: FLAGGED",
                comment: "Phase 9 handoff-detail sheet — relationship row, flagged state (UI-SPEC line 729)."
            )
        }
        label.text = template

        let row = UIStackView(arrangedSubviews: [badge, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DS.Spacing.sm
        return row
    }

    // MARK: - Tender-reference row (UI-SPEC lines 730-731)

    private func makeTenderReferenceRow(tenderRef: String?) -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.textColor = DS.Colors.label

        if let ref = tenderRef, !ref.isEmpty {
            // UI-SPEC line 730: "Tender reference: {tenderRef}" with the
            // ref in `.headline` weight. NSAttributedString lets the two
            // weights coexist on a single line while both track Dynamic
            // Type (both fonts come from `UIFont.preferredFont(forTextStyle:)`).
            let prefix = NSLocalizedString(
                "loads.detail.handoff.tenderRef.prefix",
                value: "Tender reference: ",
                comment: "Phase 9 handoff-detail sheet — tender-reference row prefix (UI-SPEC line 730). The reference value follows in headline weight."
            )
            let attributed = NSMutableAttributedString(
                string: prefix,
                attributes: [
                    .font: DS.Typography.body,
                    .foregroundColor: DS.Colors.label,
                ]
            )
            attributed.append(NSAttributedString(
                string: ref,
                attributes: [
                    .font: DS.Typography.headline,
                    .foregroundColor: DS.Colors.label,
                ]
            ))
            label.attributedText = attributed
        } else {
            // UI-SPEC line 731 — informational (NOT alarming) when no
            // tender is on file. Single `.body` sentence, no special
            // icon — "some chain handoffs are tendered out-of-band".
            label.font = DS.Typography.body
            label.text = NSLocalizedString(
                "loads.detail.handoff.tenderRef.absent",
                value: "No formal tender on file.",
                comment: "Phase 9 handoff-detail sheet — tender-reference row, absent (UI-SPEC line 731). Informational, not alarming — some chain handoffs are tendered out-of-band."
            )
        }

        return label
    }

    // MARK: - Implicated block (D-11 — soft tint card with verbatim reason)

    private func makeImplicatedBlock(integrity: ChainIntegrity) -> UIView {
        let isCompromised = integrity.verdict == .compromised
        // WR-02 fix (Phase 9 review): use the shared `DS.Colors.caution`
        // token instead of `.systemYellow` so a future re-tinting (APCA
        // contrast bump, brand refresh) keeps the handoff implicated block
        // in lockstep with every other caution surface in the chain-of-
        // trust UI (banner / verdict block / flagged-edge dash / halo).
        let tintBase: UIColor = isCompromised ? DS.Colors.destructive : DS.Colors.caution
        let iconName = isCompromised ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"

        let container = UIView()
        container.backgroundColor = tintBase.withAlphaComponent(0.15)
        container.layer.cornerRadius = 8
        container.accessibilityIdentifier = "load-detail.handoff-detail-sheet.implicated-block"

        // Icon
        let icon = UIImageView()
        icon.image = UIImage(systemName: iconName,
                             withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline))
        icon.tintColor = tintBase
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Title (UI-SPEC line 732)
        let title = UILabel()
        title.font = DS.Typography.headline
        title.textColor = DS.Colors.label
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.text = NSLocalizedString(
            "loads.detail.handoff.implicated.title",
            value: "Why this handoff is flagged",
            comment: "Phase 9 handoff-detail sheet — implicated block title (UI-SPEC line 732)."
        )

        // Header row — icon + title.
        let header = UIStackView(arrangedSubviews: [icon, title])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = DS.Spacing.sm

        // Body — server-supplied reason rendered VERBATIM (T-09-03 / D-18).
        let body = UILabel()
        body.font = DS.Typography.body
        body.textColor = DS.Colors.label
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 0
        body.text = integrity.reason

        let inner = UIStackView(arrangedSubviews: [header, body])
        inner.axis = .vertical
        inner.alignment = .fill
        inner.spacing = DS.Spacing.sm
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        inner.isLayoutMarginsRelativeArrangement = true

        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}
