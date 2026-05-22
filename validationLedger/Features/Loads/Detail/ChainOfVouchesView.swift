// validationLedger/Features/Loads/Detail/ChainOfVouchesView.swift
//
// Phase 9.1 R3 + R4 + R7 + R9 — the vertical attribution tree card. The
// marquee surface of Phase 9.1: a chrome-bound vertical UIStackView of
// `ChainOfVouchesRowView` instances, depth-first canonical-role-ordered,
// connected by dashed `CAShapeLayer` Y-fork connectors, with a 3-tier
// chain-integrity footer pill folded into the card chrome (R4).
//
// === Contract (locked) ===
// Public surface:
//   - init() — programmatic-only (ARCH-04).
//   - required init?(coder:) — traps with fatalError (ARCH-04).
//   - func configure(chainOfTrust:) — rebuild the tree + footer pill.
//   - func applySelectedRole(_ role: Role?) — apply highlight outline to
//                                              every row whose role matches
//                                              (D-10: multi-broker — both
//                                              broker rows light up).
//   - func rowViews(for role: Role) -> [ChainOfVouchesRowView] — let the
//                                              VC compute scroll-anchor
//                                              frames (used by Plan 05).
//
// === Tree-builder (R3, R9, Pitfall 7) ===
// Visits roles in canonical order
// (shipper -> broker -> carrier -> dispatch -> factoring). Within a role,
// nodes are sorted by partyID alphabetical for determinism (RESEARCH §2
// + UI-SPEC §Accessibility Contract VoiceOver traversal order).
//
// Attribution suffix is computed by walking UP the canonical parent table
// from the row's role until a parent role IS PRESENT in the chain
// (Pitfall 7 sparse-chain fallback). If the row's role is .shipper OR no
// canonical ancestor is present in the chain, the row gets the literal
// ROOT suffix (root of a sparse subtree).
//
// The role-hierarchy parent table (LOCKED — UI-SPEC §Role-Hierarchy Parent
// Table):
//   .broker    -> .shipper     (VIA SHP)
//   .carrier   -> .broker      (VIA BRK)
//   .dispatch  -> .carrier     (VIA CAR)
//   .factoring -> .carrier     (VIA CAR)
//
// VL-1009 (two brokers) produces two adjacent broker rows in the stack,
// BOTH with attribution "VIA SHP", with their per-node verification states
// (one .flagged, one .verified) — see Pitfall 3: siblings are vertically
// stacked at adjacent indices, NOT a horizontal sub-stack. The connector
// layer's Y-fork handles the visual; the stack handles only sequencing.
//
// === Footer pill (R4) ===
// Renders on EVERY verdict tier (including .clean with a soft green tint).
// This DIVERGES from Phase 9 `ChainIntegrityBannerView` which
// short-circuits to `isHidden = true` on `.clean` — the 9.1 folded pill
// MUST render on .clean because the affirmative cadence
// ("Chain intact . N vouches, no anonymous parties") is the trust signal.
//
// Footer pill verdict-tier colors (UI-SPEC §Color Footer-pill table):
//   .clean       -> .systemGreen.withAlphaComponent(0.18) bg + .systemGreen fg
//   .caution     -> DS.Colors.caution (.systemYellow) bg + .label fg
//   .compromised -> DS.Colors.destructive (.systemRed) bg + .white fg
//
// SF Symbols (locked):
//   .clean       -> checkmark.seal.fill
//   .caution     -> exclamationmark.triangle.fill
//   .compromised -> exclamationmark.octagon.fill
//
// === D-15 supersedure on iPhone (R7) ===
// ZERO fraud-signaling visual treatment on the tree itself: no dim-others,
// no dashed-flagged-edge stroke (connectors are always dashed-neutral),
// no pulse halo. The footer pill is the SOLE fraud signal on iPhone.
// iPad path (Phase 9 TrustGraphView) keeps D-15 unchanged; this view
// never mounts on iPad.
//
// === Per-row a11y composition (R6 leaf-element model — B2 wiring) ===
// Container: `isAccessibilityElement = false`.
// Each row: `isAccessibilityElement = true`, `accessibilityTraits = .staticText`,
// `accessibilityLabel = composeRowLabel(node:parentNode:stateCopy:)`.
// Composition is computed by the private `composeRowLabel(node:parentNode:stateCopy:)`
// helper and ASSIGNED ONTO EACH ROW INSTANCE inside `buildRows(from:)`
// AFTER the row is constructed and its `parentRow` reference set
// (B2 fix — the labels live on the row instance, NOT only inside the
// container's a11y elements array, so XCTest introspection via
// `treeStack.arrangedSubviews` finds the labels).
//
// Composition template (UI-SPEC §Accessibility Contract):
//   Root row:     "<Role.displayName> <node.displayName>, root of the chain, <stateCopy>"
//   Non-root row: "<Role.displayName> <node.displayName>, vouched by <Parent.role.displayName> <Parent.displayName>, <stateCopy>"
//
// NO implicated-row suffix is appended. SPEC R6 references "UI-SPEC line
// 845" for the suffix, but UI-SPEC.md ends at line 407 and locks no
// implicated suffix; R7 forbids any row-level fraud signaling on iPhone
// (footer pill is the sole fraud signal), so omitting the suffix is the
// consistent interpretation across both spec layers.
//
// Verification-state spoken vocabulary (UI-SPEC §Accessibility Contract):
//   .verified   -> "verified"
//   .pending    -> "verification pending"
//   .unverified -> "not verified"   (T-08-06 "not" prefix LOCKED)
//   .flagged    -> "flagged"
//
// === PII discipline (T-09.1-02, CLAUDE.md SEC-* + PII zero-tolerance) ===
// The composed a11y labels embed party `displayName` values — PII-class
// data. NO view-layer log call sites appear in this file (the standard
// iOS logging APIs and stdout emit functions are forbidden here per
// T-09.1-02). The verify-block grep gate fails on any match in the
// denylist.
//
// === T-09.1-04 (Tampering — client-side trust derivation) ===
// The footer pill switches over `chain.integrity.verdict` only — NEVER
// derives a verdict from edges, node states, or any other property.
// The tree-builder uses the role-hierarchy parent table (UI-layer
// convention) and NEVER reads `edges[].fromPartyID` for attribution
// (R9). The compromised-fixture snapshots verify the footer pill is the
// sole fraud signal (R7).
//
// === T-09.1-01 (Tampering — color-ramp drift) ===
// Footer pill consumes DS.Colors.caution + DS.Colors.destructive
// (existing DS tokens) and the .clean green tint is
// .systemGreen.withAlphaComponent(0.18). NO switch over VerificationState;
// the only mapping is over ChainIntegrity.Verdict. The R12 negative-grep
// gate's expected consumer set is unchanged at
// { VerificationBadgeView.swift, RoleAvatarView.swift }; this file
// composes RoleAvatarView(.tree) rather than calling
// DS.Colors.Verification.color directly.
//
// === File-shape analogs ===
// - validationLedger/Features/Loads/Detail/TrustGraphView.swift — analog
//   for CAShapeLayer ownership, layoutSubviews path recompute, the
//   `currentChain` cache pattern, halo layer lifecycle.
// - validationLedger/Features/Loads/Detail/ChainIntegrityBannerView.swift
//   — analog for the footer pill's per-verdict mapping + AX symbol
//   scaling + NSLocalizedString format-string cadence. CRITICAL
//   difference: that banner short-circuits to isHidden on .clean; the
//   9.1 footer pill MUST render on .clean with the green tint.
// - validationLedger/UI/Components/VerificationBadgeView.swift — analog
//   for Pitfall-8 cornerRadius recompute on the footer pill bounds.

import UIKit

public final class ChainOfVouchesView: UIView {

    // MARK: - Subviews
    //
    // Internal-default access so the unit-test target (under
    // `@testable import`) can introspect the tree stack, footer pill,
    // and rows directly. Mirrors the Plan 02 RoleAvatarView precedent of
    // exposing test-introspectable subviews without making them public.

    /// Eyebrow caption above the title ("Every party attested").
    let eyebrowLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.footnote
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.labelSecondary
        return l
    }()

    /// Card title ("Chain of vouches").
    let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.headline
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.label
        return l
    }()

    /// Subtitle paragraph (2 lines max, truncating tail).
    let subtitleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.body
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    /// The vertical stack of tree rows. Empty until the first
    /// `configure(chainOfTrust:)` call.
    let treeStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.md
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// The chain-integrity footer pill — renders on EVERY verdict tier.
    let footerPill: ChainOfVouchesFooterPillView = ChainOfVouchesFooterPillView()

    /// The outer vertical stack that owns the card chrome's vertical
    /// rhythm (eyebrow -> title -> subtitle -> tree -> footer pill).
    private let mainStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 0
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - Cached state

    /// Snapshot of the data the configure call ingested; available to
    /// `layoutSubviews` if needed to re-path connectors against the live
    /// canvas geometry. Mirrors `TrustGraphView.swift:126-128`.
    private var currentChain: ChainOfTrust?

    // MARK: - Init

    public init() {
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("ChainOfVouchesView is constructed programmatically only")
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // Card chrome (UI-SPEC §Component Geometry → ChainOfVouchesView).
        backgroundColor = DS.Colors.surface
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        // R6 leaf-element model: container is NOT a leaf. Each row + the
        // footer pill are leaves owning their own composed labels.
        isAccessibilityElement = false

        // Locked copy from UI-SPEC §Copywriting Contract.
        eyebrowLabel.text = NSLocalizedString(
            "loads.detail.chain.9_1.card.eyebrow",
            value: "Every party attested",
            comment: "Phase 9.1 ChainOfVouchesView — eyebrow caption above the card title (UI-SPEC §Copywriting Contract)."
        )
        titleLabel.text = NSLocalizedString(
            "loads.detail.chain.9_1.card.title",
            value: "Chain of vouches",
            comment: "Phase 9.1 ChainOfVouchesView — card title (UI-SPEC §Copywriting Contract)."
        )
        subtitleLabel.text = NSLocalizedString(
            "loads.detail.chain.9_1.card.subtitle",
            value: "Every party on this load is here because someone above them attested to them. Tap a chip to see the vouch.",
            comment: "Phase 9.1 ChainOfVouchesView — subtitle paragraph (UI-SPEC §Copywriting Contract)."
        )

        // mainStack composes the card's vertical rhythm with explicit
        // per-pair custom spacing (UI-SPEC §Component Geometry):
        //   eyebrow -> title:    DS.Spacing.xs (4pt)
        //   title -> subtitle:   DS.Spacing.sm (8pt)
        //   subtitle -> tree:    DS.Spacing.lg (24pt)
        //   tree -> footer pill: DS.Spacing.lg (24pt)
        mainStack.addArrangedSubview(eyebrowLabel)
        mainStack.addArrangedSubview(titleLabel)
        mainStack.addArrangedSubview(subtitleLabel)
        mainStack.addArrangedSubview(treeStack)
        mainStack.addArrangedSubview(footerPill)
        mainStack.setCustomSpacing(DS.Spacing.xs, after: eyebrowLabel)
        mainStack.setCustomSpacing(DS.Spacing.sm, after: titleLabel)
        mainStack.setCustomSpacing(DS.Spacing.lg, after: subtitleLabel)
        mainStack.setCustomSpacing(DS.Spacing.lg, after: treeStack)

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.lg),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.lg),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.md),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.md),
        ])
    }

    // MARK: - Public API

    /// Rebuild the tree + footer pill from the supplied chain. The tree
    /// stack is torn down and rebuilt from scratch; per-row connector
    /// + highlight layers are recomputed in `layoutSubviews()` once the
    /// row frames settle (Pitfall 1).
    public func configure(chainOfTrust chain: ChainOfTrust) {
        currentChain = chain

        // Tear down the existing tree.
        for sub in treeStack.arrangedSubviews {
            treeStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        // Build + install rows.
        let rows = buildRows(from: chain)
        for row in rows {
            treeStack.addArrangedSubview(row)
        }

        // Footer pill: ALWAYS render — even on .clean (R4 divergence vs
        // Phase 9 ChainIntegrityBannerView which short-circuits to hidden).
        footerPill.apply(verdict: chain.integrity.verdict, reason: chain.integrity.reason)

        // Mark for re-layout so connector + highlight paths recompute
        // against the new row geometry.
        setNeedsLayout()
    }

    /// Apply the chip-tap highlight outline to every row whose role
    /// matches `role`. Pass `nil` to clear all highlights. The multi-
    /// broker case (D-10 — VL-1009) lights up BOTH broker rows.
    public func applySelectedRole(_ role: Role?) {
        for sub in treeStack.arrangedSubviews {
            guard let row = sub as? ChainOfVouchesRowView else { continue }
            let on = (role != nil) && (row.node?.role == role)
            row.setHighlighted(on, animated: true)
        }
    }

    /// Return every row whose role matches `role`. Used by the VC
    /// (Plan 05) to compute scroll-anchor frames; the multi-broker case
    /// (D-10) means a single role lookup may return 2+ rows.
    public func rowViews(for role: Role) -> [ChainOfVouchesRowView] {
        return treeStack.arrangedSubviews.compactMap { sub in
            guard let row = sub as? ChainOfVouchesRowView, row.node?.role == role else { return nil }
            return row
        }
    }

    // MARK: - traitCollectionDidChange (Pitfall 1)

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Size-class or Dynamic Type change -> connector + highlight
        // paths need a re-path. layoutSubviews on each row handles the
        // actual recompute; we just need to invalidate the layout pass.
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
            || previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            setNeedsLayout()
        }
    }

    // MARK: - Tree-builder (RESEARCH §2 + Pitfall 7)

    /// Walk the chain in canonical depth-first role order, sort siblings
    /// by partyID alphabetical for determinism, build one
    /// `ChainOfVouchesRowView` per node, set the parent-row pointer, and
    /// assign the composed accessibility label onto each row instance
    /// (B2 wiring).
    private func buildRows(from chain: ChainOfTrust) -> [ChainOfVouchesRowView] {
        var rows: [ChainOfVouchesRowView] = []
        var rowsByRole: [Role: [ChainOfVouchesRowView]] = [:]

        let presentRoles = Set(chain.nodes.map { $0.role })

        // Canonical depth-first walk order.
        let roleOrder: [Role] = [.shipper, .broker, .carrier, .dispatch, .factoring]
        for role in roleOrder {
            let nodes = chain.nodes
                .filter { $0.role == role }
                .sorted { $0.partyID < $1.partyID }

            for node in nodes {
                // Attribution: walk UP the canonical hierarchy until a
                // parent role is present (Pitfall 7 sparse-chain fallback).
                let parentRole = AttributionParents.attributionParent(for: role, presentRoles: presentRoles)
                let attributionText: String
                if let pr = parentRole {
                    attributionText = String(
                        format: NSLocalizedString(
                            "loads.detail.chain.9_1.row.attribution.format",
                            value: "VIA %@",
                            comment: "Phase 9.1 ChainOfVouchesView — non-root row attribution suffix; %@ is the parent role's 3-letter uppercase abbreviation (SHP/BRK/CAR/DSP/FCT)."
                        ),
                        Self.abbreviation(for: pr)
                    )
                } else {
                    attributionText = NSLocalizedString(
                        "loads.detail.chain.9_1.row.attribution.root",
                        value: "ROOT",
                        comment: "Phase 9.1 ChainOfVouchesView — root row attribution suffix (shipper, OR the topmost present role in a sparse chain)."
                    )
                }

                let row = ChainOfVouchesRowView()
                row.configure(node: node, attributionText: attributionText)

                // Parent row pointer — first row in the parentRole's
                // bucket; nil for root rows.
                row.parentRow = parentRole.flatMap { rowsByRole[$0]?.first }

                // B2 wiring — assign the composed accessibility label
                // onto the row instance BEFORE it lands in the tree
                // stack, so introspection from XCTest finds it.
                row.isAccessibilityElement = true
                row.accessibilityTraits = .staticText
                row.accessibilityLabel = composeRowLabel(
                    node: node,
                    parentNode: row.parentRow?.node,
                    stateCopy: Self.verificationStateSpoken(node.verificationState)
                )

                rows.append(row)
                rowsByRole[role, default: []].append(row)
            }
        }
        return rows
    }

    // MARK: - Accessibility composition (B2)

    /// Compose the row's VoiceOver label per UI-SPEC §Accessibility
    /// Contract. The root variant says "root of the chain"; the
    /// non-root variant says "vouched by <Parent.role.displayName>
    /// <Parent.displayName>". NO implicated suffix is appended (see
    /// file header rationale).
    ///
    /// Method reference: `composeRowLabel(node:parentNode:stateCopy:)`
    private func composeRowLabel(node: TrustNode, parentNode: TrustNode?, stateCopy: String) -> String {
        if parentNode == nil {
            return String(
                format: NSLocalizedString(
                    "loads.detail.chain.9_1.row.a11y_label.root.format",
                    value: "%1$@ %2$@, root of the chain, %3$@",
                    comment: "Phase 9.1 ChainOfVouchesView tree-row VoiceOver label for the ROOT row (UI-SPEC §Accessibility Contract). %1$@ = role displayName, %2$@ = party displayName, %3$@ = verification-state spoken copy."
                ),
                node.role.displayName,
                node.displayName,
                stateCopy
            )
        } else {
            return String(
                format: NSLocalizedString(
                    "loads.detail.chain.9_1.row.a11y_label.nonRoot.format",
                    value: "%1$@ %2$@, vouched by %3$@ %4$@, %5$@",
                    comment: "Phase 9.1 ChainOfVouchesView tree-row VoiceOver label for NON-ROOT rows (UI-SPEC §Accessibility Contract). %1$@ = row role displayName, %2$@ = row party displayName, %3$@ = parent role displayName, %4$@ = parent party displayName, %5$@ = verification-state spoken copy."
                ),
                node.role.displayName,
                node.displayName,
                parentNode!.role.displayName,
                parentNode!.displayName,
                stateCopy
            )
        }
    }

    /// LOCKED verification-state spoken vocabulary (UI-SPEC §Accessibility
    /// Contract). The "not verified" literal carries the T-08-06 fail-
    /// closed "not" prefix lock from Phase 8's VerificationBadgeView.
    internal static func verificationStateSpoken(_ state: VerificationState) -> String {
        switch state {
        case .verified:   return "verified"
        case .pending:    return "verification pending"
        case .unverified: return "not verified"
        case .flagged:    return "flagged"
        }
    }

    // MARK: - Abbreviation literals (locked — UI-SPEC §Per-Role Avatar Palette)

    /// 3-letter role abbreviation used in the attribution suffix
    /// ("VIA %@"). LITERAL switch — NOT derived from `Role.rawValue` so
    /// a future enum-case rename (e.g. `.broker` -> `.broker_v2`)
    /// preserves the canonical SHP/BRK/CAR/DSP/FCT cadence.
    private static func abbreviation(for role: Role) -> String {
        switch role {
        case .shipper:   return "SHP"
        case .broker:    return "BRK"
        case .carrier:   return "CAR"
        case .dispatch:  return "DSP"
        case .factoring: return "FCT"
        }
    }

    // MARK: - Attribution parent table (R9, Pitfall 7)

    /// UI-layer convention encoding the role hierarchy. Lives here (not
    /// on `Role` in `Core/Load/`) because the parent table is a
    /// presentation rule, not a domain truth (R11 forbids changes under
    /// `Core/Load/`).
    fileprivate enum AttributionParents {
        /// Direct canonical parent per UI-SPEC §Role-Hierarchy Parent
        /// Table — LOCKED.
        static let canonical: [Role: Role] = [
            .broker:    .shipper,
            .carrier:   .broker,
            .dispatch:  .carrier,
            .factoring: .carrier,
        ]

        /// Walk UP the canonical hierarchy until a parent role is
        /// present in the chain. Returns `nil` for the root (.shipper)
        /// OR when no canonical ancestor is in the chain.
        ///
        /// Example (sparse-chain fallback — Pitfall 7): a chain with
        /// only [.shipper, .carrier] attributes the carrier to
        /// .shipper (VIA SHP), NOT to a non-existent .broker.
        static func attributionParent(for role: Role, presentRoles: Set<Role>) -> Role? {
            var current = role
            while let parent = canonical[current] {
                if presentRoles.contains(parent) { return parent }
                current = parent
            }
            return nil
        }
    }
}

// MARK: - ChainOfVouchesRowView (nested by file, top-level by namespace for testability)

/// A single tree row: avatar + role name + attribution suffix + party
/// displayName. Non-interactive in 9.1 (per CONTEXT `<deferred>` —
/// tap-on-row -> verification-basis sheet is a future iteration). Owns
/// its own dashed connector layer and its own highlight outline layer;
/// both are inserted into the parent stack's layer (NOT into the row's
/// own layer) so the geometry spans the inter-row gap cleanly.
public final class ChainOfVouchesRowView: UIView {

    // MARK: - Subviews
    //
    // Internal-default access for `@testable` introspection.

    /// Plan 02 RoleAvatarView, .tree variant — 32pt circle, 10pt dot.
    let avatar: RoleAvatarView = RoleAvatarView(role: .shipper, state: .verified, variant: .tree)

    /// Role name ("Shipper", "Broker", etc.) — `headline` semibold.
    let roleNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.headline
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.label
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        return l
    }()

    /// Attribution prefix ("VIA SHP" / "ROOT") — `footnote` regular.
    let attributionPrefixLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.footnote
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.labelSecondary
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }()

    /// Party displayName — `body` regular, single line, truncating tail.
    let displayNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = DS.Typography.body
        l.adjustsFontForContentSizeCategory = true
        l.textColor = DS.Colors.label
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    // MARK: - Connector + highlight layers

    /// Dashed Y-fork connector from the parent row's avatar bottom-center
    /// to this row's avatar top-center. Inserted into the PARENT stack's
    /// layer (RESEARCH Pattern 1) so the path can span the inter-row gap.
    let connectorLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.strokeColor = DS.Colors.separator.cgColor
        l.lineWidth = 1.5
        l.lineDashPattern = [3, 3]
        l.fillColor = nil
        return l
    }()

    /// 2pt outline highlight layer (sticky, opacity 0/1) — RESEARCH
    /// Pattern 4. Opacity is animated by `setHighlighted(_:animated:)`.
    let highlightLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.strokeColor = DS.Colors.primary.cgColor
        l.lineWidth = 2.0
        l.fillColor = nil
        l.opacity = 0
        return l
    }()

    // MARK: - State

    /// Parent row pointer (RESEARCH Pattern 1). Set by the tree-builder
    /// in `ChainOfVouchesView.buildRows(from:)`. `nil` for root rows.
    weak var parentRow: ChainOfVouchesRowView?

    /// The TrustNode this row renders. Set by `configure(node:attributionText:)`.
    var node: TrustNode?

    // MARK: - Init

    public init() {
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("ChainOfVouchesRowView is constructed programmatically only")
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        // Tree rows are NON-INTERACTIVE in 9.1 — selection highlight is
        // applied externally by `ChainOfVouchesView.applySelectedRole(_:)`.
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // R7 supersedure: every row at full alpha regardless of verdict
        // or implicated set. Explicit assignment for self-documentation.
        alpha = 1.0

        // Add the highlight layer to this row's own layer; the
        // connector layer attaches lazily inside `layoutSubviews()` to
        // the PARENT stack's layer (Pattern 1).
        layer.addSublayer(highlightLayer)

        // Inner horizontal stack: avatar + [roleName / attributionRow].
        let attributionRow = UIStackView(arrangedSubviews: [
            attributionPrefixLabel, displayNameLabel,
        ])
        attributionRow.axis = .horizontal
        attributionRow.alignment = .firstBaseline
        attributionRow.spacing = DS.Spacing.xs
        attributionRow.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = UIStackView(arrangedSubviews: [
            roleNameLabel, attributionRow,
        ])
        labelStack.axis = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = DS.Spacing.xs / 2  // 2pt tight vertical gap
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [avatar, labelStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DS.Spacing.md
        row.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Public API

    /// Reconfigure the row from a TrustNode + the pre-computed
    /// attribution suffix string. The attribution string is computed by
    /// the container (`ChainOfVouchesView.buildRows(from:)`) because
    /// only the container knows the chain's full role set (Pitfall 7
    /// sparse-chain fallback).
    public func configure(node: TrustNode, attributionText: String) {
        self.node = node
        avatar.configure(role: node.role, state: node.verificationState)
        roleNameLabel.text = node.role.displayName
        attributionPrefixLabel.text = attributionText
        displayNameLabel.text = node.displayName
    }

    /// Apply the chip-tap highlight outline to this row. Sticky variant
    /// per UI-SPEC: 120ms fade-in / 200ms fade-out. The CABasicAnimation
    /// uses `fillMode = .forwards` + `isRemovedOnCompletion = false` so
    /// the resting opacity matches the animation's target (the
    /// `highlightLayer.opacity = target` line at the end of this method
    /// ensures the property value also matches, since presentation-layer
    /// state can drift from model-layer state).
    public func setHighlighted(_ on: Bool, animated: Bool) {
        let target: Float = on ? 1.0 : 0.0
        if animated && target != highlightLayer.opacity {
            let duration: TimeInterval = on ? 0.12 : 0.20
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = highlightLayer.opacity
            fade.toValue = target
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(
                name: on ? .easeOut : .easeIn
            )
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            highlightLayer.add(fade, forKey: "highlight")
        }
        highlightLayer.opacity = target
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Recompute the highlight outline path (Pitfall 1). The 4pt
        // inset + 12pt corner radius matches RESEARCH Pattern 4.
        let highlightRect = bounds.insetBy(dx: 4, dy: 4)
        highlightLayer.path = UIBezierPath(
            roundedRect: highlightRect, cornerRadius: 12
        ).cgPath

        // Recompute the connector path. The connector lives in the
        // PARENT stack's layer (RESEARCH Pattern 1) so its geometry
        // spans the inter-row gap; the path is computed in the parent
        // stack's coordinate space.
        guard let parent = parentRow,
              let parentSuperview = parent.superview,
              parentSuperview === self.superview else {
            connectorLayer.path = nil
            return
        }

        // Convert both row avatars' anchor centers into the shared
        // parent-stack coordinate space.
        let parentAvatarCenter = parent.avatar.convert(
            CGPoint(x: parent.avatar.bounds.midX, y: parent.avatar.bounds.maxY),
            to: parentSuperview
        )
        let myAvatarCenter = avatar.convert(
            CGPoint(x: avatar.bounds.midX, y: avatar.bounds.minY),
            to: parentSuperview
        )

        let midY = (parentAvatarCenter.y + myAvatarCenter.y) / 2
        let path = UIBezierPath()
        path.move(to: parentAvatarCenter)
        path.addLine(to: CGPoint(x: parentAvatarCenter.x, y: midY))
        path.addLine(to: CGPoint(x: myAvatarCenter.x, y: midY))
        path.addLine(to: myAvatarCenter)
        connectorLayer.path = path.cgPath

        if connectorLayer.superlayer == nil {
            parentSuperview.layer.insertSublayer(connectorLayer, at: 0)
        }
    }
}

// MARK: - ChainOfVouchesFooterPillView

/// 3-tier chain-integrity footer pill. Renders on EVERY verdict tier
/// (R4 — DIVERGES from Phase 9 `ChainIntegrityBannerView` which hides
/// on .clean). The pill is its own VoiceOver leaf with composed label
/// "Chain integrity: <verdictSpoken>. <reason>".
public final class ChainOfVouchesFooterPillView: UIView {

    // MARK: - Subviews

    let symbolView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        // CR-03 / Pitfall 6: scale with Dynamic Type AND with the
        // accessibility-tier content-size categories.
        iv.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    let pillLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = UIFont.systemFont(
            ofSize: DS.Typography.footnote.pointSize, weight: .semibold
        )
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 2
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    // MARK: - Init

    public init() {
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("ChainOfVouchesFooterPillView is constructed programmatically only")
    }

    // MARK: - Setup

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = true
        // R6 leaf model: the footer pill is its OWN VoiceOver leaf
        // (composed label assigned in `apply(verdict:reason:)`).
        isAccessibilityElement = true
        accessibilityTraits = .staticText

        let stack = UIStackView(arrangedSubviews: [symbolView, pillLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.md),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.md),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.sm),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.sm),
        ])
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 8 — full pill at any height (tracks Dynamic Type).
        layer.cornerRadius = bounds.height / 2
    }

    // MARK: - Public API

    /// Apply a verdict-driven visual + composed accessibilityLabel.
    /// Renders on EVERY verdict tier — including `.clean` (R4 divergence
    /// vs Phase 9 banner).
    public func apply(verdict: ChainIntegrity.Verdict, reason: String) {
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .footnote)

        switch verdict {
        case .clean:
            backgroundColor = UIColor.systemGreen.withAlphaComponent(0.18)
            pillLabel.textColor = .systemGreen
            symbolView.tintColor = .systemGreen
            symbolView.image = UIImage(
                systemName: "checkmark.seal.fill",
                withConfiguration: symbolConfig
            )
            pillLabel.text = String(
                format: NSLocalizedString(
                    "loads.detail.chain.9_1.footer.clean.format",
                    value: "\u{2713} Chain intact\u{00A0}\u{00B7}\u{00A0}%@",
                    comment: "Phase 9.1 ChainOfVouchesView footer pill — .clean verdict copy template (UI-SPEC §Copywriting Contract). %@ is the chainIntegrity.reason rendered verbatim. Leading checkmark + non-breaking-space middle-dot separator."
                ),
                reason
            )

        case .caution:
            backgroundColor = DS.Colors.caution
            pillLabel.textColor = .label
            symbolView.tintColor = .label
            symbolView.image = UIImage(
                systemName: "exclamationmark.triangle.fill",
                withConfiguration: symbolConfig
            )
            pillLabel.text = String(
                format: NSLocalizedString(
                    "loads.detail.chain.9_1.footer.caution.format",
                    value: "\u{26A0} Risk flagged\u{00A0}\u{00B7}\u{00A0}%@",
                    comment: "Phase 9.1 ChainOfVouchesView footer pill — .caution verdict copy template (UI-SPEC §Copywriting Contract). %@ is the chainIntegrity.reason rendered verbatim. Leading warning sign + non-breaking-space middle-dot separator."
                ),
                reason
            )

        case .compromised:
            backgroundColor = DS.Colors.destructive
            pillLabel.textColor = .white
            symbolView.tintColor = .white
            symbolView.image = UIImage(
                systemName: "exclamationmark.octagon.fill",
                withConfiguration: symbolConfig
            )
            pillLabel.text = String(
                format: NSLocalizedString(
                    "loads.detail.chain.9_1.footer.compromised.format",
                    value: "\u{26D4} Chain compromised\u{00A0}\u{00B7}\u{00A0}%@",
                    comment: "Phase 9.1 ChainOfVouchesView footer pill — .compromised verdict copy template (UI-SPEC §Copywriting Contract). %@ is the chainIntegrity.reason rendered verbatim. Leading no-entry sign + non-breaking-space middle-dot separator."
                ),
                reason
            )
        }

        accessibilityLabel = String(
            format: NSLocalizedString(
                "loads.detail.chain.9_1.footer.a11y_label.format",
                value: "Chain integrity: %1$@. %2$@",
                comment: "Phase 9.1 ChainOfVouchesView footer pill — VoiceOver composed label (UI-SPEC §Accessibility Contract). %1$@ is the spoken verdict (clean/risk flagged/compromised); %2$@ is the chainIntegrity.reason text."
            ),
            Self.verdictSpoken(verdict),
            reason
        )
    }

    // MARK: - Internal

    /// LOCKED verdict-spoken vocabulary for VoiceOver composition.
    private static func verdictSpoken(_ verdict: ChainIntegrity.Verdict) -> String {
        switch verdict {
        case .clean:       return "clean"
        case .caution:     return "risk flagged"
        case .compromised: return "compromised"
        }
    }
}
