// validationLedger/Features/Loads/Detail/ChainIntegrityBannerView.swift
//
// Phase 9 TRUST-05 / D-15 / D-16 — the chain-integrity banner. File-shape
// twin of `LimitedTrustBannerView` (PATTERNS E4). accessibilityIdentifier
// `chain-integrity-banner` mirrors the `limited-trust-banner` precedent.
//
// === Per-verdict deltas vs the LimitedTrustBannerView twin ===
// - Per-verdict color tier (caution → yellow, compromised → red); not the
//   single `.systemYellow.withAlphaComponent(0.85)` posture of the trust-tier
//   banner.
// - Per-verdict SF Symbol icon (caution → triangle, compromised → octagon;
//   UI-SPEC line 220 — octagon is the "louder" shape, visual escalation
//   parallels color escalation).
// - Per-verdict copy template (UI-SPEC § Copywriting lines 681-682):
//   caution → "Risk flagged: {reason}"; compromised → "Chain compromised:
//   {reason}". `chainIntegrity.reason` is server-supplied; iOS is a passive
//   renderer (Phase 7 D-18 LOCK).
// - Clean verdict short-circuits: `setUp()` sets `isHidden = true` and
//   `intrinsicContentSize` returns `.zero`. The banner MUST NOT claim hit-
//   test surface when the chain is clean (UI-SPEC line 118).
// - The banner sits ABOVE content (D-16 pinned to the top of the graph
//   region on iPhone; full-width above the iPad split). It is NOT pinned
//   to the screen top — the LoadDetailViewController owns the pinning
//   geometry.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): every visual element
// (background color, icon, copy, accessibilityLabel) is driven by the
// `verdict` enum case + `reason` literal. No derive*() methods; no derived
// bools. The contract layer (`ChainIntegrity.swift` line 83) already fail-
// closed-decodes unknown verdicts to `.compromised`; this view trusts that
// contract.
// T-09-04 (Information Disclosure — PII): `reason` is rendered verbatim
// from server data in both the visible label and the accessibilityLabel.
// Zero logger calls (T-08-08 / VIEW-LAYER LOCK mirror).
//
// === Accessibility (UI-SPEC line 684 + PATTERNS E4) ===
// `accessibilityLabel = "Chain integrity: {verdictSpoken}. {reason}"` where
// `verdictSpoken` is "Caution" / "Compromised". `accessibilityTraits =
// .staticText`; banner is a single VoiceOver element.
//
// === iOS 17 deployment minimum ===
// `UIImage(systemName:)` is iOS 13+; `UIStackView` is iOS 9+; `UIFont
// .preferredFont(forTextStyle:)` + `adjustsFontForContentSizeCategory` are
// iOS 10+. No iOS 18-only APIs.

import UIKit

public final class ChainIntegrityBannerView: UIView {

    /// Minimum intrinsic height. Mirrors `LimitedTrustBannerView.bannerHeight`
    /// (PATTERNS E4 line 39). The UILabel is allowed to expand past this via
    /// Dynamic Type (up to 2 lines).
    private static let bannerHeight: CGFloat = 36.0

    // MARK: - Stored

    private let verdict: ChainIntegrity.Verdict
    private let reason: String?

    private let label: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 2
        lbl.textAlignment = .left
        lbl.font = UIFont.preferredFont(forTextStyle: .footnote)
        lbl.adjustsFontForContentSizeCategory = true
        return lbl
    }()

    private let symbolView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        // CR-03 fix (Phase 9 review): icon must scale with Dynamic Type
        // alongside the .footnote label. Without
        // adjustsImageSizeForAccessibilityContentSizeCategory, the SF Symbol
        // stays at default point size while body text grows ~2.4x at
        // .accessibilityExtraExtraExtraLarge — the icon becomes illegible
        // relative to the surrounding copy (WCAG 1.4.4 / CLAUDE.md "Dynamic
        // Type fully supported" mandate).
        iv.adjustsImageSizeForAccessibilityContentSizeCategory = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        iv.setContentHuggingPriority(.required, for: .vertical)
        iv.setContentCompressionResistancePriority(.required, for: .vertical)
        return iv
    }()

    // MARK: - Init

    public init(verdict: ChainIntegrity.Verdict, reason: String?) {
        self.verdict = verdict
        self.reason = reason
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("ChainIntegrityBannerView is constructed programmatically only")
    }

    // MARK: - Setup

    private func setUp() {
        // PATTERNS table row 19 — clean verdict short-circuit: NO chrome, NO
        // hit-test surface. The view stays in the hierarchy but claims zero
        // intrinsic size + isHidden so the parent stack collapses it.
        if verdict == .clean {
            isHidden = true
            return
        }

        // D-15 — per-verdict background color tier.
        backgroundColor = backgroundColorForVerdict()

        // D-16 — banner is informational, not tappable. Mirrors PATTERNS E4
        // LimitedTrustBannerView line 65 (interaction flag disabled).
        isUserInteractionEnabled = false

        // PATTERNS table row 19 — locked identifier mirroring the
        // `limited-trust-banner` precedent. XCUITest probes this.
        accessibilityIdentifier = "chain-integrity-banner"
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = composedAccessibilityLabel()

        // Symbol + text per the verdict-specific copy template.
        // CR-03: scale the symbol with the .footnote text style so it
        // tracks the surrounding label under Dynamic Type. Combined with
        // `adjustsImageSizeForAccessibilityContentSizeCategory = true` on
        // symbolView, this ensures the icon grows along with the body
        // text at accessibility-tier content size categories.
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .footnote)
        symbolView.image = UIImage(
            systemName: symbolNameForVerdict(),
            withConfiguration: symbolConfig)
        symbolView.tintColor = foregroundColorForVerdict()
        label.textColor = foregroundColorForVerdict()
        label.text = visibleCopyForVerdict()

        // Horizontal stack: [symbol, label]. DS.Spacing.sm inter-element
        // spacing; DS.Spacing.md leading/trailing; DS.Spacing.sm top/bottom
        // (UI-SPEC line 222).
        let stack = UIStackView(arrangedSubviews: [symbolView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: DS.Spacing.md),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -DS.Spacing.md),
            stack.topAnchor.constraint(
                equalTo: topAnchor, constant: DS.Spacing.sm),
            stack.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -DS.Spacing.sm),
            // CR-03: NO fixed width/height on symbolView — the SF Symbol's
            // intrinsicContentSize (driven by the textStyle config above
            // and adjustsImageSizeForAccessibilityContentSizeCategory)
            // owns sizing. A hard 16x16pt frame failed WCAG 1.4.4 at the
            // accessibility-tier size categories.
        ])
    }

    // MARK: - Per-verdict mapping (DRIVEN BY VERDICT ENUM — NO DERIVATION)

    /// D-15 background-color tier. Caution → DS.Colors.caution (yellow);
    /// compromised → DS.Colors.destructive (red). Clean is short-circuited
    /// by `setUp()` and never reaches this method.
    private func backgroundColorForVerdict() -> UIColor {
        switch verdict {
        case .caution:     return DS.Colors.caution
        case .compromised: return DS.Colors.destructive
        case .clean:       return .clear // unreachable — setUp short-circuits
        }
    }

    /// Foreground (icon + text) color. Caution → `.label` (yellow needs dark
    /// text per UI-SPEC line 219); compromised → `.white` (red needs white
    /// text for contrast).
    private func foregroundColorForVerdict() -> UIColor {
        switch verdict {
        case .caution:     return .label
        case .compromised: return .white
        case .clean:       return .clear // unreachable
        }
    }

    /// UI-SPEC line 220 — caution gets the triangle (the universal "warning"
    /// shape); compromised gets the octagon (the universal "stop" shape,
    /// louder than triangle, visual escalation parallels color escalation).
    private func symbolNameForVerdict() -> String {
        switch verdict {
        case .caution:     return "exclamationmark.triangle.fill"
        case .compromised: return "exclamationmark.octagon.fill"
        case .clean:       return "" // unreachable
        }
    }

    /// UI-SPEC § Copywriting Chain-integrity banner lines 676-684 — verdict-
    /// specific template with the server-supplied reason rendered verbatim.
    /// NSLocalizedString-wrapped for v2 i18n readiness; M1 ships English only.
    private func visibleCopyForVerdict() -> String {
        let reasonText = reason ?? ""
        switch verdict {
        case .caution:
            return String(
                format: NSLocalizedString(
                    "loads.detail.banner.caution.format",
                    value: "Risk flagged: %@",
                    comment: "Phase 9 ChainIntegrityBannerView — caution-tier banner copy template; %@ is server-supplied chainIntegrity.reason rendered verbatim (UI-SPEC line 681)"
                ),
                reasonText
            )
        case .compromised:
            return String(
                format: NSLocalizedString(
                    "loads.detail.banner.compromised.format",
                    value: "Chain compromised: %@",
                    comment: "Phase 9 ChainIntegrityBannerView — compromised-tier banner copy template; %@ is server-supplied chainIntegrity.reason rendered verbatim (UI-SPEC line 682)"
                ),
                reasonText
            )
        case .clean:
            return "" // unreachable
        }
    }

    /// UI-SPEC line 684 — VoiceOver composition:
    /// "Chain integrity: {verdictSpoken}. {reason}".
    /// `verdictSpoken` is the localized "Caution" / "Compromised" string.
    private func composedAccessibilityLabel() -> String {
        let verdictSpoken: String
        switch verdict {
        case .caution:
            verdictSpoken = NSLocalizedString(
                "loads.detail.banner.verdict.caution",
                value: "Caution",
                comment: "Phase 9 ChainIntegrityBannerView — caution verdict spoken via VoiceOver"
            )
        case .compromised:
            verdictSpoken = NSLocalizedString(
                "loads.detail.banner.verdict.compromised",
                value: "Compromised",
                comment: "Phase 9 ChainIntegrityBannerView — compromised verdict spoken via VoiceOver"
            )
        case .clean:
            verdictSpoken = "" // unreachable
        }
        return String(
            format: NSLocalizedString(
                "loads.detail.banner.a11yLabel.format",
                value: "Chain integrity: %@. %@",
                comment: "Phase 9 ChainIntegrityBannerView — VoiceOver label composition; first %@ is the spoken verdict (Caution/Compromised), second %@ is the server-supplied reason rendered verbatim (UI-SPEC line 684)"
            ),
            verdictSpoken,
            reason ?? ""
        )
    }

    // MARK: - intrinsicContentSize — clean → .zero (no hit-test surface)

    public override var intrinsicContentSize: CGSize {
        // Clean verdict → no chrome AND no claimed layout space.
        // UI-SPEC line 118: "when clean: isHidden = true AND removed from
        // any UIStackView arranged subview to avoid invisible-height hit-
        // test surfaces."
        if verdict == .clean { return .zero }
        return CGSize(width: UIView.noIntrinsicMetric, height: Self.bannerHeight)
    }
}
