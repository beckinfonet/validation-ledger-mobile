// validationLedger/Features/Loads/Detail/TrustNodeView.swift
//
// Phase 9 Plan 06 Task 1 — TRUST-01 marquee subview.
//
// === Composition (UI-SPEC § Node visuals lines 167-184; PATTERNS E5) ===
// A single TrustNodeView per chain-of-trust party. Composes:
//   * Phase 8 VerificationBadgeView (4-state pill — reused, no parallel copy).
//   * Role caption label  (e.g. "BROKER", caption font, secondary label color).
//   * Display-name label  (e.g. "FreightWise Brokerage", footnote, 2 lines max).
// Layered in a vertical UIStackView inside a rounded-square chrome with
// `cornerRadius = 12`, `borderWidth = 0.5`, `borderColor = DS.Colors.separator`,
// `backgroundColor = DS.Colors.surface`. The 44pt minimum height is locked
// defensively per UI-SPEC line 182 (HIG 44pt touch-target floor).
//
// === Gesture model (D-04 / RESEARCH §1 lines 203-230) ===
// Two UITapGestureRecognizers attached to self with the canonical Pitfall 2
// mitigation:
//   * singleTap (`numberOfTapsRequired = 1`, name "trust-node.singleTap").
//     Fires `onSingleTap(partyID)` which opens the TRUST-03 verification-
//     basis sheet (wiring lands in Plan 07; this plan ships the closure
//     surface).
//   * doubleTap (`numberOfTapsRequired = 2`, name "trust-node.doubleTap").
//     Fires `onDoubleTap(self)` which TrustGraphView translates to a zoom-
//     recenter on this node.
//   * singleTap requires doubleTap to fail before recognising — the LOCKED
//     Pitfall 2 mitigation (call site at the bottom of `setUp()`). Without
//     it, every double-tap fires the single-tap
//     callback FIRST (because the recognizer system can't yet rule out
//     that a second tap is coming). The grep gate in 09-06-PLAN.md
//     acceptance criteria locks this at the source level.
//
// === Accessibility (D-22 / UI-SPEC § Graph accessibility container) ===
// `isAccessibilityElement = true` + `accessibilityTraits = .button` — every
// node is a leaf in the TrustGraphView accessibility container. The
// `accessibilityLabel` is COMPOSED by the PARENT TrustGraphView (which owns
// the chain-integrity context needed to append the implicated-suffix per
// UI-SPEC line 845); the parent calls `applyComposedAccessibilityLabel(_:)`
// after configuration. The view itself does not own the label string.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): the view consumes ONLY
// what `configure(node:isImplicated:isDimmed:)` is given. Every visual
// treatment (alpha, badge state) flows from arguments — never computed from
// other fields. `isImplicated` and `isDimmed` are computed by the parent
// TrustGraphView from `chainIntegrity.implicatedNodeIDs.contains(...)` and
// the verdict — server-supplied membership lookups, never client-derived.
// T-09-04 (PII): zero logger calls in this file. The `displayName` rendered
// in the labels is server-supplied; PII-zero in the synthetic Phase 7
// fixture corpus per Phase 7 D-13. Locked by the negative grep gate.
//
// === Accessibility identifiers (UI-SPEC § Accessibility identifiers) ===
//   - chrome view: `load-detail.trust-graph.node.{partyID}`
//   - composed badge: `load-detail.trust-graph.node.{partyID}.verification-badge`
// Both are set in `configure(node:isImplicated:isDimmed:)` so they survive
// reconfiguration on every chain-of-trust update.

import UIKit

public final class TrustNodeView: UIView {

    // MARK: - Stored

    /// Cached for the single-tap callback dispatch. Re-assigned in
    /// `configure(node:isImplicated:isDimmed:)`. The single-tap closure
    /// receives this value rather than the full `TrustNode` — the consumer
    /// (TrustGraphView → LoadDetailViewController) only needs the identifier
    /// to look up the node again from the server-supplied `ChainOfTrust`.
    private(set) public var partyID: String = ""

    /// The Phase 8 verification-state pill — REUSED, not duplicated (PATTERNS E5).
    private let verificationBadge = VerificationBadgeView()

    /// Role caption ("BROKER", "CARRIER", …) — `DS.Typography.caption`,
    /// uppercase, secondary label color.
    private let roleLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.caption
        l.textColor = DS.Colors.labelSecondary
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// Display-name label ("FreightWise Brokerage") — `DS.Typography.footnote`,
    /// 2 lines max, truncating-tail, centered.
    private let displayNameLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.label
        l.numberOfLines = 2
        l.textAlignment = .center
        l.lineBreakMode = .byTruncatingTail
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// Internal vertical stack — `[roleLabel, verificationBadge, displayNameLabel]`.
    private let internalStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .center
        s.spacing = DS.Spacing.xs
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// Tap recognizers — both named via iOS 17 `UIGestureRecognizer.name`
    /// so the gesture-introspection test can locate them by string match
    /// instead of relying on KVC reflection against private state.
    private let singleTap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()

    // MARK: - Callbacks (set by TrustGraphView during configure)

    /// Fires with the cached `partyID` when the single-tap recognizer
    /// transitions to `.recognized` — i.e. after the double-tap fails to
    /// fire. TrustGraphView wires this to the TRUST-03 sheet open (Plan 07
    /// fills in the actual presentation).
    internal var onSingleTap: ((String) -> Void)?

    /// Fires with `self` when the double-tap recognizer recognises.
    /// TrustGraphView translates the view reference to the node's center
    /// for the recenter+zoom animation (D-04).
    internal var onDoubleTap: ((TrustNodeView) -> Void)?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("TrustNodeView is constructed programmatically only")
    }

    // MARK: - setUp

    private func setUp() {
        // Chrome — UI-SPEC § Node visuals lines 167-184.
        backgroundColor = DS.Colors.surface
        layer.cornerRadius = 12
        layer.borderWidth = 0.5
        layer.borderColor = DS.Colors.separator.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        // D-22 accessibility — every node is a single VoiceOver leaf with
        // `.button` traits. The composed label is set by the parent
        // TrustGraphView via `applyComposedAccessibilityLabel(_:)`.
        isAccessibilityElement = true
        accessibilityTraits = .button

        // Compose the internal vertical stack — [roleLabel, badge, displayName].
        internalStack.addArrangedSubview(roleLabel)
        internalStack.addArrangedSubview(verificationBadge)
        internalStack.addArrangedSubview(displayNameLabel)

        addSubview(internalStack)

        NSLayoutConstraint.activate([
            // Pin the stack inside the chrome with `sm` (8pt) insets on all
            // sides — leaves room for the chrome border to read cleanly.
            internalStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.sm),
            internalStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.sm),
            internalStack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.sm),
            internalStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.sm),

            // Defensive 44pt touch-target floor (UI-SPEC line 182 — HIG).
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        // Gesture recognizers — D-04 / RESEARCH §1 lines 203-230.
        singleTap.numberOfTapsRequired = 1
        singleTap.name = "trust-node.singleTap"
        singleTap.addTarget(self, action: #selector(handleSingleTap))

        doubleTap.numberOfTapsRequired = 2
        doubleTap.name = "trust-node.doubleTap"
        doubleTap.addTarget(self, action: #selector(handleDoubleTap))

        // The LOCKED Pitfall 2 mitigation. Locked at the source level by the
        // 09-06-PLAN.md acceptance criteria grep gate; locked at the
        // behavioral level by TrustNodeViewGestureTests.
        singleTap.require(toFail: doubleTap)

        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
    }

    // MARK: - Public API — configure from a TrustNode

    /// Render the view from a server-supplied `TrustNode` plus the parent-
    /// computed `isImplicated` (membership in `chainIntegrity.implicatedNodeIDs`)
    /// and `isDimmed` (D-15 dim-others rule: chain verdict != .clean AND
    /// this node is NOT implicated).
    ///
    /// Every visual treatment flows from these three arguments — never from
    /// derived state. Per T-09-03: the trust verdict is read verbatim from
    /// `node.verificationState` (the badge consumer); the implicated check
    /// is a Set membership lookup that the parent performs (this view does
    /// NOT inspect `ChainIntegrity` directly).
    public func configure(node: TrustNode, isImplicated: Bool, isDimmed: Bool) {
        partyID = node.partyID

        // Accessibility identifiers — survive every reconfigure.
        accessibilityIdentifier = "load-detail.trust-graph.node.\(node.partyID)"
        verificationBadge.accessibilityIdentifier =
            "load-detail.trust-graph.node.\(node.partyID).verification-badge"

        // Badge — REUSED Phase 8 component; the verification color ramp lives
        // there and never drifts (TRUST-02 lock).
        verificationBadge.configure(state: node.verificationState)

        // Role caption + display-name body.
        roleLabel.text = node.role.displayName.uppercased()
        displayNameLabel.text = node.displayName

        // D-15 dim-others — when the chain verdict is non-clean and THIS
        // node is not implicated, render at 50% alpha. The parent
        // TrustGraphView pre-computes both `isImplicated` and `isDimmed`;
        // we just consume the booleans.
        alpha = isDimmed ? 0.5 : 1.0
    }

    /// Apply the parent-composed accessibility label. The PARENT
    /// TrustGraphView owns the composition (which needs chain-integrity
    /// context to append the implicated-suffix per UI-SPEC line 845); this
    /// view simply hosts the result so the leaf-level accessibilityLabel is
    /// the same string VoiceOver reads.
    internal func applyComposedAccessibilityLabel(_ label: String) {
        accessibilityLabel = label
    }

    // MARK: - Gesture handlers

    @objc private func handleSingleTap() {
        onSingleTap?(partyID)
    }

    @objc private func handleDoubleTap() {
        onDoubleTap?(self)
    }

    // MARK: - Test seams (internal — accessed by @testable import)
    //
    // The gesture-test harness needs to drive the recognizer closures without
    // a real touch sequence (RESEARCH §1 line 245-253 calls out this novel
    // pattern). We expose a thin pair of internal helpers that invoke the
    // same @objc selectors UIKit would call when the recognizers transition
    // to `.recognized`. The handlers themselves contain ZERO touch-only
    // logic — they just forward to the public closures — so this seam
    // exercises the exact same code path as a real tap.

    /// Test-only — invoke the single-tap path as if the recognizer had
    /// recognised after the double-tap fail window elapsed.
    internal func _testInvokeSingleTap() {
        handleSingleTap()
    }

    /// Test-only — invoke the double-tap path as if the recognizer had
    /// recognised two taps in sequence.
    internal func _testInvokeDoubleTap() {
        handleDoubleTap()
    }
}
