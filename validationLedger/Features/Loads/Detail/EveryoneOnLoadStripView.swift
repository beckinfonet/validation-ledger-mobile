// validationLedger/Features/Loads/Detail/EveryoneOnLoadStripView.swift
//
// Phase 9.1 R2 — the dynamic "everyone on this load" strip. A horizontally-
// scrollable row of role-avatar chips anchored at the top of the iPhone
// Load Detail chain block. Composes `RoleAvatarView(variant: .strip)`
// (Plan 02) for each chip; consumes `ChainOfTrust` directly; emits role
// taps via the public `onRoleTap` closure that LoadDetailViewController
// (Plan 05) wires to ChainOfVouchesView's scroll-and-highlight.
//
// === Contract (locked) ===
// Public surface:
//   - init() — programmatic-only (ARCH-04).
//   - required init?(coder:) — traps with fatalError (ARCH-04).
//   - var onRoleTap: ((Role) -> Void)? — chip-tap closure (D-09).
//   - func configure(chainOfTrust:) — rebuild chip set from a chain.
//   - func applySelectedRole(_ role: Role?) — apply highlight outline
//     to the chip whose role matches; clear all when nil (D-11).
//
// === Composition (UI-SPEC § Component Geometry → EveryoneOnLoadStripView) ===
// Horizontal `UIScrollView` (alwaysBounceHorizontal = true,
// showsHorizontalScrollIndicator = false) holding a horizontal
// `UIStackView` (spacing = DS.Spacing.sm, alignment = .center). The
// trailing "All watching live · tap for details" UILabel lives in a
// sibling subview OUTSIDE the scroll view — right-anchored to the
// strip's trailing edge so it never scrolls off-screen (UI-SPEC).
//
// Each chip is a private `ChipView`: a vertical UIStackView of
// [RoleAvatarView(.strip), UILabel(role.displayName)] with a 44pt-floor
// hit-test surface. The avatar fill, the status-dot color, and the
// 3-letter abbreviation all flow through Plan 01 + Plan 02's
// `DS.Colors.Verification` / `DS.Colors.Roles` helpers — no parallel
// color switches in this file (TRUST-02 / R12).
//
// === Chip-set derivation (R2) ===
// Chip count equals the de-duplicated set of `chainOfTrust.nodes[].role`
// in canonical order (shipper → broker → carrier → dispatch → factoring).
// VL-1009's two brokers collapse to ONE BRK chip (R2 + D-10) — the
// fraud-signaling intent is "the role is suspect, not just one party."
//
// === Multi-node collapsed chip state (D-10, RESEARCH §Open Q1) ===
// When multiple nodes share a role, the collapsed chip's status-dot color
// reflects the MOST-SUSPICIOUS state across those nodes:
//   .flagged > .pending > .unverified > .verified
// VL-1009's BRK chip (one .flagged, one .verified) renders as .flagged.
// The composed a11y label carries the same most-suspicious copy.
//
// === DisplayName slot (planner default per B1 revision) ===
// For single-node roles the chip's a11y label uses the node's
// `displayName` (e.g. "Broker, FreightWise Brokerage, verified"). For
// multi-node collapsed roles (currently only VL-1009 BRK) the label
// uses the literal "multiple parties" (e.g. "Broker, multiple parties,
// flagged"). UI-SPEC does NOT lock a multi-node displayName at any
// line; this is the planner-chosen default per the B1 revision
// directive and lives in NSLocalizedString key
// `loads.detail.chain.9_1.strip.chip.multi_node_displayname`. If
// product subsequently locks a different string, update that
// localized value here.
//
// === Accessibility (R6 leaf-element model — SPEC R6 binding) ===
// Container (EveryoneOnLoadStripView): `isAccessibilityElement = false`.
// The scroll view + caption are NOT individual leaves either; only
// chips are leaves. Each ChipView:
//   - `isAccessibilityElement = true`
//   - `accessibilityTraits = [.button, .staticText]`
//   - `accessibilityLabel = "<RoleDisplayName>, <DisplayName>, <VerificationStateCopy>"`
//     (3-field per SPEC R6 binding; UI-SPEC line 298 shows a 2-field
//     shorthand that SPEC R6 supersedes)
// VoiceOver spoken-state vocabulary (UI-SPEC §Accessibility Contract):
//   .verified   -> "verified"
//   .pending    -> "verification pending"
//   .unverified -> "not verified"        (T-08-06 "not" prefix LOCKED)
//   .flagged    -> "flagged"
//
// === Interaction (D-08, D-09, D-11) ===
// Each chip owns a single `UITapGestureRecognizer` named
// `"everyone-on-load-strip.chip"` (mirror of TrustNodeView.swift:191's
// naming convention). Tap fires `UISelectionFeedbackGenerator.selectionChanged()`
// + the chip's `onTap` closure; the strip forwards via
// `self.onRoleTap?(chip.role)`. Selection highlight is a 2pt
// `DS.Colors.primary` outline on a `CAShapeLayer`, 120ms fade-in,
// 200ms fade-out, sticky until another chip is tapped (D-11; full
// outline-animation contract lives on ChipView).
//
// === PII discipline (T-09.1-02 mitigation — STRENGTHENED in B1 revision) ===
// The B1-revised 3-field a11y label now embeds the party `displayName`
// for single-node chips (e.g. "Broker, FreightWise Brokerage, verified"),
// elevating PII risk vs. the prior 2-field design. The view-layer
// logging lock holds: NO view-layer log call sites appear in this
// file (the standard iOS logging APIs and stdout emit functions are
// forbidden here per T-09.1-02). The verify-block grep gate fails on
// any match.
//
// === NSLocalizedString discipline ===
// All user-facing strings use NSLocalizedString with the
// `loads.detail.chain.9_1.*` phase-prefix and a descriptive comment.
// Phase-prefix-keyed strings allow the M1 English-only ship to evolve
// to v2 i18n without source touch.
//
// File-shape analog (programmatic UIKit chip-like view + tap closure +
// 44pt floor + named recognizer): TrustNodeView.swift lines 109-191.

import UIKit

public final class EveryoneOnLoadStripView: UIView {

    // MARK: - Public callbacks

    /// Fires with the tapped chip's `Role` after the chip's single-tap
    /// recognizer transitions to `.recognized`. LoadDetailViewController
    /// (Plan 05) wires this to `ChainOfVouchesView.applySelectedRole(_:)`
    /// to scroll-and-highlight the corresponding tree row(s) (D-08, D-09,
    /// D-10 multi-broker: tapping BRK lights BOTH broker rows).
    public var onRoleTap: ((Role) -> Void)?

    // MARK: - Subviews

    /// The horizontal scroll view that hosts the chip stack. Trailing
    /// caption lives OUTSIDE this view so it never scrolls off-screen.
    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.alwaysBounceHorizontal = true
        s.showsHorizontalScrollIndicator = false
        s.showsVerticalScrollIndicator = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// The horizontal chip stack inside the scroll view. Rebuilt on every
    /// `configure(chainOfTrust:)`.
    private let chipStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = DS.Spacing.sm
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// Trailing "All watching live · tap for details" caption — sibling of
    /// the scroll view (NOT inside it) so it stays pinned to the strip's
    /// trailing edge regardless of scroll position.
    let captionLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = .secondaryLabel
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    /// The active set of chip views, in canonical role order. Internal
    /// access so the unit-test target can iterate via `@testable import`.
    private(set) var chips: [ChipView] = []

    // MARK: - Init

    public init() {
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("EveryoneOnLoadStripView is constructed programmatically only")
    }

    // MARK: - setUp

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        // R6 leaf-element model: the container is NOT a leaf. Only the
        // chips (and only the chips) are VoiceOver elements.
        isAccessibilityElement = false

        // Caption text — LOCKED NSLocalizedString key per UI-SPEC
        // §Copywriting Contract. Uses \u{00A0}·\u{00A0} (non-breaking
        // space + middle dot + non-breaking space) so the separator
        // never line-wraps awkwardly.
        captionLabel.text = NSLocalizedString(
            "loads.detail.chain.9_1.strip.caption",
            value: "All watching live\u{00A0}·\u{00A0}tap for details",
            comment: "Phase 9.1 EveryoneOnLoadStripView trailing meta caption — static text, NOT realtime backed (M3); rendered to the right of the chip strip OUTSIDE the horizontal scroll view so it stays pinned to the trailing edge regardless of scroll position."
        )

        scrollView.addSubview(chipStack)
        addSubview(scrollView)
        addSubview(captionLabel)

        NSLayoutConstraint.activate([
            // Scroll view fills from leading edge to the caption's leading
            // edge. The trailing caption is pinned to the strip's
            // trailing edge OUTSIDE the scroll view (UI-SPEC).
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: captionLabel.leadingAnchor, constant: -DS.Spacing.sm),

            // Caption pinned to trailing edge, centered vertically.
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            captionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Chip stack inside scroll view — top + bottom insets of
            // DS.Spacing.sm (8pt) per UI-SPEC §Component Geometry. The
            // scroll-view contentLayoutGuide drives horizontal scrolling.
            chipStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: DS.Spacing.sm),
            chipStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -DS.Spacing.sm),
            chipStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DS.Spacing.sm),
            chipStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DS.Spacing.sm),
            // Chip stack height tracks the scroll view's frameLayoutGuide
            // so the chip row is centered vertically inside the strip.
            chipStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -DS.Spacing.sm * 2),
        ])
    }

    // MARK: - Public API

    /// Rebuild the chip set from the given chain. Chip count equals the
    /// de-duplicated `chainOfTrust.nodes[].role` count in canonical
    /// order. For multi-node roles, the chip's status reflects the
    /// MOST-SUSPICIOUS state across nodes of that role (D-10 / RESEARCH
    /// §Open Q1).
    public func configure(chainOfTrust chain: ChainOfTrust) {
        // Tear down any prior chips. Each ChipView holds its own gesture
        // recognizer, label, avatar, and highlight layer — removing from
        // the stack releases them via ARC; explicit nil-out of onTap
        // helps avoid retain cycles if a future closure captures self.
        for chip in chips {
            chip.onTap = nil
            chipStack.removeArrangedSubview(chip)
            chip.removeFromSuperview()
        }
        chips.removeAll()

        // Derive present roles in canonical order.
        let presentRoles = Self.presentRoles(in: chain)

        // Build a chip per role.
        for role in presentRoles {
            let state = Self.mostSuspiciousState(in: chain, role: role)
            let displayName = Self.chipDisplayName(in: chain, role: role)
            let chip = ChipView(role: role, displayName: displayName, state: state)
            chip.onTap = { [weak self] tappedRole in
                self?.onRoleTap?(tappedRole)
            }
            chipStack.addArrangedSubview(chip)
            chips.append(chip)
        }
    }

    /// Apply the selection highlight outline to the chip whose role
    /// matches; clear the outline on any non-matching chips. Pass `nil`
    /// to clear all (D-11).
    public func applySelectedRole(_ role: Role?) {
        for chip in chips {
            chip.setHighlighted(chip.role == role, animated: true)
        }
    }

    // MARK: - Internal — chip-state derivation

    /// Canonical role-order comparator used to sort the present-role set.
    /// Mirrors UI-SPEC's "shipper → broker → carrier → dispatch → factoring."
    private static let canonicalOrder: [Role] = [.shipper, .broker, .carrier, .dispatch, .factoring]

    /// The set of distinct roles present in the chain, in canonical order.
    static func presentRoles(in chain: ChainOfTrust) -> [Role] {
        let set = Set(chain.nodes.map { $0.role })
        return canonicalOrder.filter { set.contains($0) }
    }

    /// Suspicion ordering for the most-suspicious-wins collapsed chip
    /// rule (D-10, RESEARCH §Open Q1):
    ///     .flagged > .pending > .unverified > .verified
    /// Higher rank == more suspicious. The collapsed chip's status-dot
    /// AND its composed a11y label both reflect the most-suspicious
    /// state across nodes sharing the role.
    private static func suspicionRank(_ state: VerificationState) -> Int {
        switch state {
        case .flagged:    return 3
        case .pending:    return 2
        case .unverified: return 1
        case .verified:   return 0
        }
    }

    /// Compute the most-suspicious verification state across all nodes of
    /// the given role. For single-node roles this is simply the node's
    /// state. For multi-node roles (currently only VL-1009's two
    /// brokers) the ordering above selects the most-suspicious. Falls
    /// back to `.unverified` defensively if no node has the role
    /// (unreachable — `configure` only iterates roles that are present).
    static func mostSuspiciousState(in chain: ChainOfTrust, role: Role) -> VerificationState {
        let states = chain.nodes.filter { $0.role == role }.map { $0.verificationState }
        guard !states.isEmpty else { return .unverified }
        return states.max(by: { suspicionRank($0) < suspicionRank($1) }) ?? .unverified
    }

    /// Compute the chip's displayName slot for its composed a11y label.
    /// For single-node roles returns the node's `displayName`. For
    /// multi-node roles returns the localized "multiple parties"
    /// literal (B1 planner default; key
    /// `loads.detail.chain.9_1.strip.chip.multi_node_displayname`).
    static func chipDisplayName(in chain: ChainOfTrust, role: Role) -> String {
        let matching = chain.nodes.filter { $0.role == role }
        if matching.count == 1, let only = matching.first {
            return only.displayName
        }
        return NSLocalizedString(
            "loads.detail.chain.9_1.strip.chip.multi_node_displayname",
            value: "multiple parties",
            comment: "Phase 9.1 EveryoneOnLoadStripView collapsed-chip displayName slot when a role has >1 node (VL-1009 BRK case — two brokers collapsing into one chip). UI-SPEC does not lock this string at any line; planner-chosen default per B1 revision; if user/UI-SPEC subsequently lock a different string, update the localized value here."
        )
    }

    // MARK: - ChipView (private nested)
    //
    // A single role-avatar chip. Wraps RoleAvatarView(.strip) + a role-
    // name label in a vertical stack with a 44pt-floor hit-test surface,
    // a CAShapeLayer highlight outline, a named tap recognizer, and a
    // composed `accessibilityLabel` per SPEC R6 (3-field).
    //
    // Internal access on the class itself so the unit-test target can
    // introspect `chips[i].accessibilityLabel`, `chips[i].role`, and
    // drive `chips[i].onTap?(role)` via `@testable import`.

    final class ChipView: UIView {

        // MARK: ChipView — Stored

        /// The role this chip represents. Drives the avatar's circle
        /// fill, the abbreviation, the role-name label, and the tap
        /// callback's payload.
        let role: Role

        /// The composed displayName slot (single-node node displayName
        /// OR the multi-node "multiple parties" literal). Kept here so
        /// the chip can recompose its accessibility label without
        /// re-walking the chain.
        let displayName: String

        /// The chip's status-dot state (single-node node state OR the
        /// most-suspicious across multi-node roles).
        let state: VerificationState

        /// Closure invoked on chip tap. The strip wires this to forward
        /// to `EveryoneOnLoadStripView.onRoleTap`.
        var onTap: ((Role) -> Void)?

        // MARK: ChipView — Subviews

        private let avatar: RoleAvatarView
        private let roleLabel: UILabel = {
            let l = UILabel()
            l.font = DS.Typography.footnote
            l.textColor = .label
            l.textAlignment = .center
            l.adjustsFontForContentSizeCategory = true
            l.numberOfLines = 1
            l.translatesAutoresizingMaskIntoConstraints = false
            return l
        }()
        private let vStack: UIStackView = {
            let s = UIStackView()
            s.axis = .vertical
            s.alignment = .center
            s.spacing = DS.Spacing.xs
            s.translatesAutoresizingMaskIntoConstraints = false
            s.isUserInteractionEnabled = false
            return s
        }()

        /// The selection-highlight outline layer. 2pt
        /// `DS.Colors.primary` stroke, no fill, cornerRadius 22 (matches
        /// the 44pt hit-test radius per UI-SPEC § Component Geometry).
        /// Opacity transitions 0↔1 on `setHighlighted(_:animated:)`
        /// using 120ms fade-in / 200ms fade-out per RESEARCH Pattern 4.
        private let highlightLayer: CAShapeLayer = {
            let l = CAShapeLayer()
            l.strokeColor = DS.Colors.primary.cgColor
            l.fillColor = nil
            l.lineWidth = 2
            l.opacity = 0
            return l
        }()

        /// Named tap recognizer (mirror of TrustNodeView.swift's
        /// `"trust-node.singleTap"` naming) so future gesture-introspection
        /// tests can locate by string match rather than KVC reflection.
        private let tapRecognizer: UITapGestureRecognizer = {
            let r = UITapGestureRecognizer()
            r.numberOfTapsRequired = 1
            r.name = "everyone-on-load-strip.chip"
            return r
        }()

        // MARK: ChipView — Init

        init(role: Role, displayName: String, state: VerificationState) {
            self.role = role
            self.displayName = displayName
            self.state = state
            self.avatar = RoleAvatarView(role: role, state: state, variant: .strip)
            super.init(frame: .zero)
            setUp()
        }

        required init?(coder: NSCoder) {
            fatalError("ChipView is constructed programmatically only")
        }

        // MARK: ChipView — Layout

        override func layoutSubviews() {
            super.layoutSubviews()
            // Recompute the highlight outline path on every layout pass
            // (Pitfall 8 mirror — the path tracks the bounds, which can
            // change as Dynamic Type scales the role-name label below).
            highlightLayer.path = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: bounds.height / 2
            ).cgPath
        }

        // MARK: ChipView — setUp

        private func setUp() {
            translatesAutoresizingMaskIntoConstraints = false
            backgroundColor = .clear

            // The avatar's inline `isUserInteractionEnabled = false` from
            // Plan 02 ensures taps land on this ChipView rather than the
            // avatar subview. Belt-and-suspenders: this view OWNS the
            // tap; subviews defer.
            isUserInteractionEnabled = true

            roleLabel.text = role.displayName

            vStack.addArrangedSubview(avatar)
            vStack.addArrangedSubview(roleLabel)
            addSubview(vStack)
            layer.addSublayer(highlightLayer)

            NSLayoutConstraint.activate([
                // 44pt hit-test floor (UI-SPEC § Spacing Scale / CLAUDE.md
                // HIG mandate). The visual avatar is 40pt; the surrounding
                // padding ring brings the touch target to ≥44pt.
                widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

                // Vertical stack centered in the chip with `sm` horizontal
                // inset (so the 40pt avatar + role-name leaves room for
                // the hit-test ring without competing for layout space).
                vStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                vStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                vStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: DS.Spacing.sm),
                vStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Spacing.sm),
                vStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                vStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            ])

            // R6 leaf-element model: the chip is THE leaf — its avatar
            // and role-name subviews are NOT individually accessible.
            // The composed label (role + displayName + state) is the
            // single string VoiceOver speaks per SPEC R6 (binding).
            isAccessibilityElement = true
            accessibilityTraits = [.button, .staticText]
            accessibilityLabel = Self.composeAccessibilityLabel(role: role, displayName: displayName, state: state)

            // Tap recognizer.
            tapRecognizer.addTarget(self, action: #selector(handleTap))
            addGestureRecognizer(tapRecognizer)
        }

        // MARK: ChipView — Public API

        /// Animate the selection outline on/off. Sticky variant per
        /// D-11: the outline stays until another chip is tapped (no
        /// timer). The strip's `applySelectedRole(_:)` calls this on
        /// every chip after a role tap (passing `chip.role == newRole`).
        func setHighlighted(_ highlighted: Bool, animated: Bool) {
            let target: Float = highlighted ? 1.0 : 0.0
            if !animated {
                highlightLayer.opacity = target
                return
            }
            let duration: CFTimeInterval = highlighted ? 0.120 : 0.200
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = highlightLayer.opacity
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(
                name: highlighted ? .easeOut : .easeIn)
            highlightLayer.add(animation, forKey: "opacity")
            highlightLayer.opacity = target
        }

        // MARK: ChipView — Gesture handler

        @objc private func handleTap() {
            // Soft selection-change haptic — the platform precedent for
            // discrete-set selection (segmented controls). UI-SPEC
            // §Interaction & Animation Contract.
            let haptic = UISelectionFeedbackGenerator()
            haptic.selectionChanged()
            onTap?(role)
        }

        // MARK: ChipView — Internal: a11y composition

        /// Compose the 3-field accessibility label per SPEC R6
        /// (binding). Method reference: `composeAccessibilityLabel(role:displayName:state:)`.
        /// The 3 fields are `(role.displayName, displayName,
        /// verificationStateSpoken(state))` joined by ", " — for
        /// example "Broker, FreightWise Brokerage, verified" or, for
        /// VL-1009's collapsed BRK chip, "Broker, multiple parties,
        /// flagged". Note that SPEC R6 (line 52) is BINDING — the 3-field
        /// shape supersedes UI-SPEC line 298's 2-field shorthand.
        ///
        /// Uses a positional format string so future localizations can
        /// reorder slots (e.g. some languages prefer state-first
        /// framing) without touching this composition code.
        static func composeAccessibilityLabel(role: Role, displayName: String, state: VerificationState) -> String {
            let template = NSLocalizedString(
                "loads.detail.chain.9_1.strip.chip.a11y_label.format",
                value: "%1$@, %2$@, %3$@",
                comment: "Phase 9.1 EveryoneOnLoadStripView per-chip VoiceOver label — 3-field positional format per SPEC R6 binding. Slot 1: Role.displayName (e.g. \"Broker\"). Slot 2: single-node node displayName OR the multi-node \"multiple parties\" literal. Slot 3: locked spoken verification-state copy (\"verified\" / \"verification pending\" / \"not verified\" / \"flagged\")."
            )
            return String(
                format: template,
                role.displayName,
                displayName,
                Self.verificationStateSpoken(state)
            )
        }

        /// LOCKED spoken-state vocabulary per UI-SPEC §Accessibility
        /// Contract. T-08-06 mitigation: `.unverified` speaks "not
        /// verified" — the literal "not" prefix prevents any VoiceOver
        /// listener (or test substring match) from confusing the
        /// substring "verified" for a trust signal.
        private static func verificationStateSpoken(_ state: VerificationState) -> String {
            switch state {
            case .verified:
                return NSLocalizedString(
                    "loads.detail.chain.9_1.verification.spoken.verified",
                    value: "verified",
                    comment: "Phase 9.1 spoken verification-state copy — verified."
                )
            case .pending:
                return NSLocalizedString(
                    "loads.detail.chain.9_1.verification.spoken.pending",
                    value: "verification pending",
                    comment: "Phase 9.1 spoken verification-state copy — pending; phrased \"verification pending\" not \"pending\" so VoiceOver framing is unambiguous."
                )
            case .unverified:
                return NSLocalizedString(
                    "loads.detail.chain.9_1.verification.spoken.unverified",
                    value: "not verified",
                    comment: "Phase 9.1 spoken verification-state copy — unverified; T-08-06 \"not\" prefix LOCKED so no VoiceOver listener confuses the substring \"verified\" for a trust signal."
                )
            case .flagged:
                return NSLocalizedString(
                    "loads.detail.chain.9_1.verification.spoken.flagged",
                    value: "flagged",
                    comment: "Phase 9.1 spoken verification-state copy — flagged."
                )
            }
        }
    }
}
