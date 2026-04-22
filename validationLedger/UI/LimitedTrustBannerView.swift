// validationLedger/UI/LimitedTrustBannerView.swift
// D-11: Non-dismissible "Limited trust mode" banner on the role shell.
// Inserted by RoleCoordinator.wrapWithLimitedTrustBanner(trustTier:) when
// AppContainer.session.trustTier != .hardwareAttested.
//
// Layout discipline (04-RESEARCH.md Pitfall 7): pin to safeAreaLayoutGuide.topAnchor
// in the parent container — never raw topAnchor — to survive iPad notch, Dynamic Island,
// and landscape rotation. The wrapper (RoleCoordinator.wrapWithLimitedTrustBanner) owns
// the safe-area pinning against its parent VC's view; this UIView subclass is purely
// the visual + a11y surface.
//
// Wrapper composition (NOT a subview of UITabBarController.tabBar — Apple-unsupported,
// breaks on iPad landscape): the banner becomes a SIBLING of the tab bar controller's
// view inside a new parent UIViewController, installed by RoleCoordinator.
//
// Non-dismissibility (D-11 + T-APP-ATTEST-11 mitigation):
//   - user-interaction flag disabled at setUp() time (blocks tap/swipe gestures)
//   - no UIGestureRecognizers attached (defence-in-depth; nothing to fire even if a
//     future edit flipped the interaction flag)
//   - no dismiss button
//
// Information-disclosure posture (T-APP-ATTEST-12 accepted): banner copy is generic —
// it signals "limited trust mode" but never leaks the specific attestationStatus
// (entitlementMissing vs quotaExceeded vs error) or the device fingerprint. The
// shoulder-surfer threat is accepted per D-11; transparency with the user outweighs
// obfuscation.
//
// Copy (D-11, 04-CONTEXT.md line 174, verbatim): wrapped in NSLocalizedString for v2
// i18n readiness; M1 ships English only per CLAUDE.md i18n deferral. The `value:`
// parameter carries the English fallback so no Localizable.strings entry is required
// for M1 — adding one is a trivial future plan.

import UIKit

public final class LimitedTrustBannerView: UIView {

    /// Minimum intrinsic height. The UILabel is allowed to expand past this via Dynamic
    /// Type (up to 2 lines). 36pt is the 04-PATTERNS.md line 603 recommendation.
    private static let bannerHeight: CGFloat = 36.0

    private let label: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 2
        lbl.textAlignment = .center
        lbl.font = UIFont.preferredFont(forTextStyle: .footnote)
        lbl.adjustsFontForContentSizeCategory = true
        lbl.textColor = .label
        return lbl
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        // D-11 / T-APP-ATTEST-11 non-dismissibility: blocks all hit-testing. The
        // XCUITest asserts `isHittable == false` to lock this invariant into CI.
        isUserInteractionEnabled = false

        // Visual: system-colored warning tone per 04-CONTEXT.md line 94 Claude's-discretion
        // note. systemYellow @ 85% alpha reads as "caution" in both light and dark
        // appearance without being a red/alarm color. The banner is permanent, not
        // transient; a milder tone avoids alarm fatigue.
        backgroundColor = UIColor.systemYellow.withAlphaComponent(0.85)

        // Accessibility (04-PATTERNS.md line 606 + 04-RESEARCH.md validation map D-11
        // line 876). The accessibilityIdentifier is the stable XCUITest locator and
        // MUST match LimitedTrustBannerTests's `app.otherElements["limited-trust-banner"]`.
        accessibilityIdentifier = "limited-trust-banner"
        accessibilityLabel = NSLocalizedString(
            "limited_trust_banner.accessibility_label",
            value: "Limited trust mode",
            comment: "Accessibility label for the role-shell top banner shown when device trust tier is not hardware-attested (D-11)."
        )
        accessibilityTraits = .staticText
        isAccessibilityElement = true

        // D-11 copy (04-CONTEXT.md line 174, verbatim).
        label.text = NSLocalizedString(
            "limited_trust_banner.copy",
            value: "Limited trust mode — this device can't fully verify. Some features may be restricted.",
            comment: "Banner text shown above the tab bar on the role shell when trustTier != hardwareAttested (D-11, Phase 4 DEV-04). English-only for M1 per CLAUDE.md i18n deferral; NSLocalizedString wrapping structures the string for v2 localization."
        )

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.bannerHeight)
    }
}
