// validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift
//
// Phase 9 Plan 07 — TRUST-03 / D-07 / D-08 / D-09 / D-10 / D-11.
//
// === What this is ===
// The verification-basis modal sheet content view-controller. Fired by a
// single-tap on a `TrustNodeView` (Plan 06 callback) and presented via
// `UISheetPresentationController` (Plan 07 — LoadDetailViewController owns
// the presentation; this VC owns the content).
//
// First user of `UISheetPresentationController` in the codebase
// (09-PATTERNS.md § Novel Patterns line 67). The canonical iOS-17 detent
// configuration lives on the PRESENTING side
// (LoadDetailViewController.presentVerificationBasisSheet) — this content
// VC is presentation-agnostic and snapshots cleanly at the
// medium-detent representative size (~393×500 pt).
//
// === Content order (UI-SPEC § Verification-basis sheet lines 410-457) ===
//   1. Header                — role caption + display name + reused
//                              `VerificationBadgeView` (same node-level
//                              state).
//   2. KYC row               — always rendered. Verified → relative time;
//                              not-completed → neutral icon.
//   3. Device-binding row    — always rendered. `bound` / `unbound` /
//                              `mismatched` per DeviceBindingStatus.
//   4. USDOT row             — ONLY when `role == .carrier || .dispatch`
//                              AND `usdotAuthorityStatus != .notApplicable`.
//                              Entirely absent for Shipper/Factoring per
//                              D-09 (no "Not applicable" placeholder).
//   5. Prior relationships   — section header + per-row list OR
//                              empty-state line "First time working
//                              together." (D-14 chameleon fraud signal).
//                              Rows are INERT in v1.1 per D-10 — chevron
//                              affordance is rendered but tap is not
//                              wired; `accessibilityTraits = .staticText`
//                              keeps VoiceOver from promising an action.
//   6. Implicated block      — D-11: ONLY when `partyID ∈
//                              integrity.implicatedNodeIDs`. Soft 0.15
//                              tint (yellow for caution / red for
//                              compromised) + verdict icon + verbatim
//                              `integrity.reason`.
//
// === D-10 inert-tap decision (recorded for SUMMARY) ===
// Prior-relationship rows use `accessibilityTraits = .staticText` (NOT
// `.button`) per UI-SPEC line 446 — better than a misleading hint. The
// chevron affordance is rendered so the future wiring of "tap a prior load
// → push another LoadDetailVC" lands without re-drawing the row, but
// VoiceOver does NOT promise an action. CONTEXT § Deferred Ideas owns the
// future wiring decision.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): every visual flows
// VERBATIM from server-supplied TrustNode + ChainIntegrity fields. No
// derive*() method exists in this file. The implicated-block render is
// gated by a pure Set membership lookup
// (`integrity.implicatedNodeIDs.contains(node.partyID)`).
//
// T-09-04 (PII): zero logger calls in this file (verified by the negative
// grep gate in 09-07-PLAN.md acceptance criteria). Party names, USDOT
// numbers, and prior load IDs are server-supplied and rendered verbatim
// without being logged.
//
// === Accessibility identifiers (UI-SPEC lines 776-781 — LOCKED) ===
//   - view: `load-detail.verification-basis-sheet`
//   - contentStack: `load-detail.verification-basis-sheet.party.<partyID>`
//                   (D-09 partition — XCUITest asserts which party's
//                    sheet opened)
//   - header: `load-detail.verification-basis-sheet.header`
//   - KYC row: `load-detail.verification-basis-sheet.kyc-row`
//   - device row: `load-detail.verification-basis-sheet.device-binding-row`
//   - USDOT row: `load-detail.verification-basis-sheet.usdot-row`
//   - prior-relationships section: `load-detail.verification-basis-sheet.prior-relationships`
//   - prior-relationship row: `load-detail.verification-basis-sheet.prior-relationships.row.<loadID>`
//   - implicated block: `load-detail.verification-basis-sheet.implicated-block`
//
// === Dynamic Type discipline ===
// Every label sets `adjustsFontForContentSizeCategory = true`. Row icons
// scale via `UIImage.SymbolConfiguration(textStyle:)` so they track the
// system font scale.
//
// === iOS 17 deployment minimum ===
// No iOS 18-only APIs used. `RelativeDateTimeFormatter`, `UIStackView`,
// `UIScrollView`, `UIImage.SymbolConfiguration(textStyle:)` are iOS 13+/14+.

import UIKit

public final class VerificationBasisSheetViewController: UIViewController {

    // MARK: - Stored

    private let node: TrustNode
    private let integrity: ChainIntegrity

    // MARK: - Layout — scroll container so long prior-relationship lists
    // can scroll inside the .medium detent. The presenting side caps the
    // sheet scrolling from auto-promoting via
    // `prefersScrollingExpandsWhenScrolledToEdge = false` per D-10.

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
        s.spacing = DS.Spacing.md
        s.translatesAutoresizingMaskIntoConstraints = false
        s.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.lg, left: DS.Spacing.md,
            bottom: DS.Spacing.lg, right: DS.Spacing.md
        )
        s.isLayoutMarginsRelativeArrangement = true
        return s
    }()

    // MARK: - Init

    public init(node: TrustNode, integrity: ChainIntegrity) {
        self.node = node
        self.integrity = integrity
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("VerificationBasisSheetViewController is constructed programmatically only")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        view.accessibilityIdentifier = "load-detail.verification-basis-sheet"

        installScrollContainer()
        composeContent()
    }

    // MARK: - Scroll container

    private func installScrollContainer() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        // Partition identifier per UI-SPEC line 777 — XCUITest asserts which
        // party's sheet opened by looking up the contentStack identifier.
        contentStack.accessibilityIdentifier =
            "load-detail.verification-basis-sheet.party.\(node.partyID)"

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Pin contentStack to the scroll view's content layout guide for
            // scroll geometry, and to the frame layout guide horizontally so
            // the stack's width matches the visible scroll area (KYCStatus-
            // ViewController precedent — PATTERNS table row 23).
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    // MARK: - Content composition

    private func composeContent() {
        // 1. Header (always)
        contentStack.addArrangedSubview(makeHeaderRow(node: node))

        // 2. KYC row (always — every role)
        contentStack.addArrangedSubview(makeKYCRow(node: node))

        // 3. Device-binding row (always — every role)
        contentStack.addArrangedSubview(makeDeviceBindingRow(node: node))

        // 4. USDOT row — Carrier + Dispatch only (D-09). Skip entirely for
        //    Shipper/Factoring (no "Not applicable" placeholder).
        if node.role == .carrier || node.role == .dispatch {
            if let usdotRow = makeUSDOTRow(node: node) {
                contentStack.addArrangedSubview(usdotRow)
            }
        }

        // 5. Prior relationships (always — empty array is the chameleon
        //    fraud signal per D-14).
        contentStack.addArrangedSubview(makePriorRelationshipsSection(node: node))

        // 6. Implicated block (D-11 — ONLY when implicated).
        if integrity.implicatedNodeIDs.contains(node.partyID) {
            contentStack.addArrangedSubview(makeImplicatedBlock(integrity: integrity))
        }
    }

    // MARK: - Header (role caption + display name + reused VerificationBadgeView)

    private func makeHeaderRow(node: TrustNode) -> UIView {
        let roleLabel = UILabel()
        roleLabel.font = DS.Typography.footnote
        roleLabel.textColor = DS.Colors.labelSecondary
        roleLabel.adjustsFontForContentSizeCategory = true
        roleLabel.text = node.role.displayName.uppercased()
        roleLabel.setContentHuggingPriority(.required, for: .horizontal)
        roleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nameLabel = UILabel()
        nameLabel.font = DS.Typography.headline
        nameLabel.textColor = DS.Colors.label
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.text = node.displayName

        let badge = VerificationBadgeView()
        badge.configure(state: node.verificationState)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [roleLabel, nameLabel, badge])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.sm
        stack.accessibilityIdentifier = "load-detail.verification-basis-sheet.header"
        return stack
    }

    // MARK: - KYC row (D-09)

    private func makeKYCRow(node: TrustNode) -> UIView {
        let symbolName: String
        let tintColor: UIColor
        let text: String

        if let completedAt = node.kycCompletedAt {
            symbolName = "checkmark.seal.fill"
            tintColor = DS.Colors.primary
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: completedAt, relativeTo: Date())
            let template = NSLocalizedString(
                "loads.detail.sheet.kyc.verified",
                value: "KYC verified %@",
                comment: "Phase 9 verification-basis sheet — KYC row, verified state (UI-SPEC line 706). %@ is RelativeDateTimeFormatter output."
            )
            text = String(format: template, relative)
        } else {
            symbolName = "xmark.seal"
            tintColor = DS.Colors.labelSecondary
            text = NSLocalizedString(
                "loads.detail.sheet.kyc.notCompleted",
                value: "KYC not completed",
                comment: "Phase 9 verification-basis sheet — KYC row, not-completed state (UI-SPEC line 707)."
            )
        }

        let row = makeFactRow(symbolName: symbolName, tintColor: tintColor, text: text)
        row.accessibilityIdentifier = "load-detail.verification-basis-sheet.kyc-row"
        return row
    }

    // MARK: - Device-binding row (D-09 mapped to DeviceBindingStatus cases)

    private func makeDeviceBindingRow(node: TrustNode) -> UIView {
        let symbolName: String
        let tintColor: UIColor
        let text: String

        // DeviceBindingStatus cases are .bound, .unbound, .mismatched. The
        // UI-SPEC contract maps these to the locked sheet copy (UI-SPEC
        // lines 708-710). `.mismatched` is the v1.1 nearest-fit for the
        // copy table's "revoked" semantic — both are the destructive-tinted
        // "device binding broken" branch.
        switch node.deviceBindingStatus {
        case .bound:
            symbolName = "lock.shield.fill"
            tintColor = DS.Colors.primary
            // UI-SPEC line 708: "Device bound · {short device label} · since {month year}".
            // The current TrustNode contract carries neither the short
            // device label nor the bound-since date — that level of detail
            // is a future Phase 7 contract evolution. v1.1 surfaces the
            // simplest accurate copy: "Device bound" (no fabricated label
            // or date — per T-09-03 zero client derivation).
            text = NSLocalizedString(
                "loads.detail.sheet.deviceBinding.bound",
                value: "Device bound",
                comment: "Phase 9 verification-basis sheet — device-binding row, bound state (UI-SPEC line 708, simplified for v1.1 contract)."
            )
        case .unbound:
            symbolName = "lock.open"
            tintColor = DS.Colors.labelSecondary
            text = NSLocalizedString(
                "loads.detail.sheet.deviceBinding.notRegistered",
                value: "Device not registered",
                comment: "Phase 9 verification-basis sheet — device-binding row, unbound state (UI-SPEC line 709)."
            )
        case .mismatched:
            symbolName = "lock.slash"
            tintColor = DS.Colors.destructive
            text = NSLocalizedString(
                "loads.detail.sheet.deviceBinding.mismatched",
                value: "Device binding mismatched",
                comment: "Phase 9 verification-basis sheet — device-binding row, mismatched state (analogue of UI-SPEC line 710 'revoked'; the v1.1 contract case)."
            )
        }

        let row = makeFactRow(symbolName: symbolName, tintColor: tintColor, text: text)
        row.accessibilityIdentifier = "load-detail.verification-basis-sheet.device-binding-row"
        return row
    }

    // MARK: - USDOT row (D-09 — Carrier + Dispatch only; .notApplicable hides the row)

    private func makeUSDOTRow(node: TrustNode) -> UIView? {
        // Defensive: the caller (composeContent) already gates on role; this
        // also gates on .notApplicable per UI-SPEC line 714 (row not rendered).
        guard node.usdotAuthorityStatus != .notApplicable else { return nil }

        // WR-01 fix (Phase 9 review): when usdotNumber is nil but the
        // authority row is still rendered (Carrier / Dispatch role whose
        // authority status is active/suspended/revoked but the number
        // itself is missing from an incomplete server response), the
        // template "USDOT %@ · Authority …" would render as "USDOT  ·
        // Authority …" — a leading double-space + bullet ahead of an
        // empty number. Substitute the locked em-dash placeholder so the
        // row still reads cleanly while making the missing data visible.
        let usdot = node.usdotNumber ?? NSLocalizedString(
            "loads.detail.sheet.usdot.placeholder",
            value: "—",
            comment: "Phase 9 verification-basis sheet — placeholder shown in the USDOT row when the server-supplied usdotNumber is nil but the authority row is still rendered (WR-01)."
        )
        let symbolName: String
        let tintColor: UIColor
        let text: String

        switch node.usdotAuthorityStatus {
        case .active:
            symbolName = "checkmark.shield.fill"
            tintColor = DS.Colors.primary
            let template = NSLocalizedString(
                "loads.detail.sheet.usdot.active",
                value: "USDOT %@ · Authority active",
                comment: "Phase 9 verification-basis sheet — USDOT row, active state (UI-SPEC line 711). %@ is the USDOT number."
            )
            text = String(format: template, usdot)
        case .suspended:
            symbolName = "exclamationmark.shield"
            tintColor = .systemYellow // UI-SPEC line 604 caution semantic (no DS.Colors.caution token yet — additive token deferred)
            let template = NSLocalizedString(
                "loads.detail.sheet.usdot.suspended",
                value: "USDOT %@ · Authority suspended",
                comment: "Phase 9 verification-basis sheet — USDOT row, suspended state (UI-SPEC line 712)."
            )
            text = String(format: template, usdot)
        case .revoked:
            symbolName = "xmark.shield.fill"
            tintColor = DS.Colors.destructive
            let template = NSLocalizedString(
                "loads.detail.sheet.usdot.revoked",
                value: "USDOT %@ · Authority revoked",
                comment: "Phase 9 verification-basis sheet — USDOT row, revoked state (UI-SPEC line 713)."
            )
            text = String(format: template, usdot)
        case .notApplicable:
            return nil
        }

        let row = makeFactRow(symbolName: symbolName, tintColor: tintColor, text: text)
        row.accessibilityIdentifier = "load-detail.verification-basis-sheet.usdot-row"
        return row
    }

    // MARK: - Prior relationships section (D-10 — LIST not count; D-14 empty-state)

    private func makePriorRelationshipsSection(node: TrustNode) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = "load-detail.verification-basis-sheet.prior-relationships"

        let sectionStack = UIStackView()
        sectionStack.axis = .vertical
        sectionStack.alignment = .fill
        sectionStack.spacing = DS.Spacing.xs
        sectionStack.translatesAutoresizingMaskIntoConstraints = false

        // Section header — UI-SPEC line 715: "Prior relationships (N)" when
        // non-empty; "Prior relationships" when empty (no count badge).
        let headerLabel = UILabel()
        headerLabel.font = DS.Typography.headline
        headerLabel.textColor = DS.Colors.label
        headerLabel.adjustsFontForContentSizeCategory = true
        headerLabel.numberOfLines = 1
        if node.priorRelationships.isEmpty {
            headerLabel.text = NSLocalizedString(
                "loads.detail.sheet.priorRelationships.header",
                value: "Prior relationships",
                comment: "Phase 9 verification-basis sheet — prior relationships section header (empty state)."
            )
        } else {
            let template = NSLocalizedString(
                "loads.detail.sheet.priorRelationships.headerWithCount",
                value: "Prior relationships (%d)",
                comment: "Phase 9 verification-basis sheet — prior relationships section header with count (UI-SPEC line 715)."
            )
            headerLabel.text = String(format: template, node.priorRelationships.count)
        }
        sectionStack.addArrangedSubview(headerLabel)

        if node.priorRelationships.isEmpty {
            // D-14 chameleon fraud signal — empty-state line.
            let emptyLine = UILabel()
            emptyLine.font = DS.Typography.body
            emptyLine.textColor = DS.Colors.label
            emptyLine.adjustsFontForContentSizeCategory = true
            emptyLine.numberOfLines = 0
            emptyLine.text = NSLocalizedString(
                "loads.detail.sheet.priorRelationships.empty",
                value: "First time working together.",
                comment: "Phase 9 verification-basis sheet — prior relationships empty-state line (UI-SPEC line 716 / D-14 chameleon fraud signal)."
            )
            sectionStack.addArrangedSubview(emptyLine)
        } else {
            for rel in node.priorRelationships {
                sectionStack.addArrangedSubview(makePriorRelationshipRow(rel: rel, viewerRole: node.role))
            }
        }

        container.addSubview(sectionStack)
        NSLayoutConstraint.activate([
            sectionStack.topAnchor.constraint(equalTo: container.topAnchor),
            sectionStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sectionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sectionStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    /// Build one prior-relationship list row. D-10: chevron affordance is
    /// rendered but tap is INERT in v1.1; `.staticText` keeps VoiceOver
    /// from promising an action that doesn't fire. The future wiring (tap
    /// → push another LoadDetailVC) is deferred per CONTEXT § Deferred
    /// Ideas — when it lands, this row's view code stays the same but the
    /// traits flip to `.button` and a tap recognizer is attached.
    private func makePriorRelationshipRow(rel: PriorRelationship, viewerRole: Role) -> UIView {
        // Load ref — .headline weight, semibold.
        let loadRefLabel = UILabel()
        loadRefLabel.font = DS.Typography.headline
        loadRefLabel.textColor = DS.Colors.label
        loadRefLabel.adjustsFontForContentSizeCategory = true
        loadRefLabel.text = rel.loadID
        loadRefLabel.setContentHuggingPriority(.required, for: .horizontal)
        loadRefLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Framing — UI-SPEC line 718: "{ours} → {theirs}" or
        // "{theirs} → {ours}". v1.1 ships the simpler form
        // "{viewerRole} → {counterpartyRole}" (role-only, no display
        // names) — see SUMMARY Open Questions.
        let framingLabel = UILabel()
        framingLabel.font = DS.Typography.footnote
        framingLabel.textColor = DS.Colors.label
        framingLabel.adjustsFontForContentSizeCategory = true
        framingLabel.text = "\(viewerRole.displayName) → \(rel.counterpartyRole.displayName)"

        // Relative timestamp — UI-SPEC line 719.
        let timestampLabel = UILabel()
        timestampLabel.font = DS.Typography.footnote
        timestampLabel.textColor = DS.Colors.labelSecondary
        timestampLabel.adjustsFontForContentSizeCategory = true
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        timestampLabel.text = formatter.localizedString(for: rel.occurredAt, relativeTo: Date())

        // Chevron affordance — D-10 / UI-SPEC line 443 right-edge chevron.
        let chevron = UIImageView()
        chevron.image = UIImage(systemName: "chevron.right",
                                withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote))
        chevron.tintColor = DS.Colors.labelSecondary
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [loadRefLabel, framingLabel, timestampLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DS.Spacing.sm
        row.accessibilityIdentifier =
            "load-detail.verification-basis-sheet.prior-relationships.row.\(rel.loadID)"

        // D-10 LOCKED — .staticText (NOT .button). The row LOOKS tappable
        // (chevron present) but does NOT fire navigation in v1.1. A hint
        // that lies to VoiceOver is worse than a missing affordance —
        // UI-SPEC line 446 explicit recommendation.
        row.isAccessibilityElement = true
        row.accessibilityTraits = .staticText
        row.accessibilityLabel = "\(rel.loadID), \(framingLabel.text ?? ""), \(timestampLabel.text ?? "")"

        // 44pt touch-target floor — kept for the future tap wiring without
        // requiring a relayout when the row becomes interactive.
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        return row
    }

    // MARK: - Implicated block (D-11 — soft tint card with verbatim reason)

    private func makeImplicatedBlock(integrity: ChainIntegrity) -> UIView {
        let isCompromised = integrity.verdict == .compromised
        // WR-02 fix (Phase 9 review): the caution branch must use the
        // shared `DS.Colors.caution` token (introduced in Phase 9 to
        // consolidate the chain-integrity banner + verdict block +
        // flagged-edge dash + caution halo). Reaching for `.systemYellow`
        // directly here bypasses that consolidation, so a future
        // re-tinting (APCA contrast bump, brand refresh) silently
        // diverges this implicated block from every other caution
        // surface in the chain-of-trust UI.
        let tintBase: UIColor = isCompromised ? DS.Colors.destructive : DS.Colors.caution
        let iconName = isCompromised ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"

        let container = UIView()
        container.backgroundColor = tintBase.withAlphaComponent(0.15)
        container.layer.cornerRadius = 8
        container.accessibilityIdentifier = "load-detail.verification-basis-sheet.implicated-block"

        // Icon
        let icon = UIImageView()
        icon.image = UIImage(systemName: iconName,
                             withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline))
        icon.tintColor = tintBase
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Title
        let title = UILabel()
        title.font = DS.Typography.headline
        title.textColor = DS.Colors.label
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.text = NSLocalizedString(
            "loads.detail.sheet.implicated.title",
            value: "Why this party is flagged",
            comment: "Phase 9 verification-basis sheet — implicated block title (UI-SPEC line 720)."
        )

        // Header row — icon + title (single line).
        let header = UIStackView(arrangedSubviews: [icon, title])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = DS.Spacing.sm

        // Body — server-supplied reason rendered VERBATIM (T-09-03).
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

    // MARK: - Shared fact-row builder

    /// Build a horizontal stack [icon, multi-line label] with the shared
    /// fact-row geometry. Icon uses the headline symbol scale so it tracks
    /// Dynamic Type. The label is `.body` weight, multi-line, label color.
    private func makeFactRow(symbolName: String, tintColor: UIColor, text: String) -> UIView {
        let icon = UIImageView()
        icon.image = UIImage(systemName: symbolName,
                             withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline))
        icon.tintColor = tintColor
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.font = DS.Typography.body
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.text = text

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DS.Spacing.sm
        return row
    }
}
