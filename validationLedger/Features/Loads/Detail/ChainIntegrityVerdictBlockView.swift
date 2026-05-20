// validationLedger/Features/Loads/Detail/ChainIntegrityVerdictBlockView.swift
//
// Phase 9 TRUST-05 / D-02 — the in-body chain-integrity verdict block.
// D-16 INTENTIONAL DUPLICATION: this view renders the SAME chain-integrity
// data as the pinned ChainIntegrityBannerView (above-the-fold marquee
// surface). The verdict block lives below-the-fold in the scroll body and
// is the in-context reading surface; the banner is the persistent fraud
// signal. Same data, two surfaces — by design.
//
// === Renders only when verdict != .clean (UI-SPEC line 402) ===
// `LoadDetailBodyView.installVerdictBlock(...)` (Plan 09 Task 1) handles
// the conditional add — for `.clean` the verdict block is NOT instantiated.
// This view's `init` still tolerates `.clean` defensively (sets isHidden
// = true and returns from setUp early) but the parent never reaches that
// branch.
//
// === Visual structure (UI-SPEC § Chain-integrity verdict block lines 389-402) ===
// Rounded card, cornerRadius 8pt, soft 0.15-alpha verdict tint as
// background. Vertical stack of 2-3 rows:
//   1. Horizontal row: SF Symbol (triangle/octagon, full-saturation verdict
//      color) + verdict label (.headline, "Caution"/"Compromised").
//   2. Reason text — .body, .label color, multi-line, server-supplied verbatim.
//   3. (optional) "{N} parties implicated" footnote when implicatedNodeCount > 0.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): every visual element
// (tint, icon, copy) is driven by the verdict enum case + reason literal +
// implicatedNodeCount Int. No derive*() methods.
// T-09-04 (Information Disclosure — PII): reason rendered verbatim from
// server data. Zero logger calls.
//
// === Accessibility identifier ===
// `accessibilityIdentifier = "load-detail.body.verdict-block"` — same
// identifier as the parent `verdictBlockContainer` slot on LoadDetailBodyView
// (the inner view's identifier wins when both are addressable; the slot's
// identifier survives the removeFromSuperview cycle between installs).
//
// === Pluralization ===
// "1 party implicated" uses a separate localized key from "{N} parties
// implicated" (the simple `%d %@` template breaks at zero/one in non-English
// locales; this app ships English-only for v1.x but the NSLocalizedString
// scaffold is structured for v2 plural rules). Swift conditional dispatch
// selects between the two keys before format-substitution.
//
// === iOS 17 deployment minimum ===
// `UIImage(systemName:)`, `UIStackView`, `UILabel.numberOfLines = 0`,
// `adjustsFontForContentSizeCategory = true` are all iOS 11+.

import UIKit

public final class ChainIntegrityVerdictBlockView: UIView {

    // MARK: - Stored

    private let verdict: ChainIntegrity.Verdict
    private let reason: String?
    private let implicatedNodeCount: Int

    // MARK: - Init

    public init(verdict: ChainIntegrity.Verdict, reason: String?, implicatedNodeCount: Int) {
        self.verdict = verdict
        self.reason = reason
        self.implicatedNodeCount = implicatedNodeCount
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("ChainIntegrityVerdictBlockView is constructed programmatically only")
    }

    // MARK: - Setup

    private func setUp() {
        accessibilityIdentifier = "load-detail.body.verdict-block"
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        layer.masksToBounds = true

        // Clean short-circuit — defensive; the parent's installVerdictBlock
        // skips clean before calling init. Match the banner posture: hide +
        // skip content build.
        if verdict == .clean {
            isHidden = true
            return
        }

        backgroundColor = tintForVerdict()

        // Row 1: icon + verdict-name headline.
        let iconView = UIImageView(image: UIImage(systemName: symbolNameForVerdict()))
        iconView.tintColor = fullSaturationColorForVerdict()
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])

        let verdictLabel = UILabel()
        verdictLabel.font = DS.Typography.headline
        verdictLabel.textColor = DS.Colors.label
        verdictLabel.adjustsFontForContentSizeCategory = true
        verdictLabel.numberOfLines = 1
        verdictLabel.text = verdictTitle()

        let titleRow = UIStackView(arrangedSubviews: [iconView, verdictLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = DS.Spacing.sm
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        // Row 2: reason body text — verbatim, multi-line.
        let reasonLabel = UILabel()
        reasonLabel.font = DS.Typography.body
        reasonLabel.textColor = DS.Colors.label
        reasonLabel.numberOfLines = 0
        reasonLabel.adjustsFontForContentSizeCategory = true
        reasonLabel.text = reason ?? ""
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false

        // Row 3 (optional): implicated count footnote.
        var verticalArranged: [UIView] = [titleRow, reasonLabel]
        if implicatedNodeCount > 0 {
            let countLabel = UILabel()
            countLabel.font = DS.Typography.footnote
            countLabel.textColor = DS.Colors.labelSecondary
            countLabel.numberOfLines = 1
            countLabel.adjustsFontForContentSizeCategory = true
            countLabel.text = implicatedCountText()
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            verticalArranged.append(countLabel)
        }

        let outer = UIStackView(arrangedSubviews: verticalArranged)
        outer.axis = .vertical
        outer.alignment = .leading
        outer.spacing = DS.Spacing.sm
        outer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.md),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.md),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.md),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.md),
        ])
    }

    // MARK: - Per-verdict mapping

    /// Soft 0.15-alpha tint (UI-SPEC line 391). Caution → yellow @ 0.15;
    /// compromised → red @ 0.15.
    private func tintForVerdict() -> UIColor {
        switch verdict {
        case .caution:     return DS.Colors.caution.withAlphaComponent(0.15)
        case .compromised: return DS.Colors.destructive.withAlphaComponent(0.15)
        case .clean:       return .clear // unreachable
        }
    }

    /// Full-saturation icon color (UI-SPEC line 393 — icon tints the
    /// verdict's full color so the soft background tint reads as a wash and
    /// the icon as the primary signal).
    private func fullSaturationColorForVerdict() -> UIColor {
        switch verdict {
        case .caution:     return DS.Colors.caution
        case .compromised: return DS.Colors.destructive
        case .clean:       return .clear // unreachable
        }
    }

    /// SF Symbol mirror of the banner — same triangle/octagon visual
    /// escalation parallels the banner per UI-SPEC line 220 + 393.
    private func symbolNameForVerdict() -> String {
        switch verdict {
        case .caution:     return "exclamationmark.triangle.fill"
        case .compromised: return "exclamationmark.octagon.fill"
        case .clean:       return "" // unreachable
        }
    }

    /// Localized verdict title — "Caution" / "Compromised".
    private func verdictTitle() -> String {
        switch verdict {
        case .caution:
            return NSLocalizedString(
                "loads.detail.verdict.title.caution",
                value: "Caution",
                comment: "Phase 9 ChainIntegrityVerdictBlockView — caution verdict headline"
            )
        case .compromised:
            return NSLocalizedString(
                "loads.detail.verdict.title.compromised",
                value: "Compromised",
                comment: "Phase 9 ChainIntegrityVerdictBlockView — compromised verdict headline"
            )
        case .clean:
            return "" // unreachable
        }
    }

    /// Implicated count text — pluralized via conditional Swift dispatch.
    /// Singular ("1 party implicated") and plural ("{N} parties implicated")
    /// use SEPARATE NSLocalizedString keys so the v2 i18n pass can plumb
    /// each through its locale's plural rule.
    private func implicatedCountText() -> String {
        if implicatedNodeCount == 1 {
            return NSLocalizedString(
                "loads.detail.verdict.implicated_singular",
                value: "1 party implicated",
                comment: "Phase 9 ChainIntegrityVerdictBlockView — implicated count footnote (singular form, English fallback)"
            )
        }
        return String(
            format: NSLocalizedString(
                "loads.detail.verdict.implicated_plural",
                value: "%d parties implicated",
                comment: "Phase 9 ChainIntegrityVerdictBlockView — implicated count footnote (plural form, English fallback); %d is implicatedNodeCount"
            ),
            implicatedNodeCount
        )
    }
}
