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

// MARK: - Phase 6 Plan 03 (D6-10) — re-renderable banner container

/// A parent `UIViewController` that hosts the role tab bar controller as a
/// child and shows/hides the `LimitedTrustBannerView` on demand.
///
/// Phase 4 shipped the banner as a one-shot wrapper decided at `presentRoot`
/// time (a `trustTier` mutation mid-session did NOT update it — see the prior
/// `wrapWithLimitedTrustBanner` doc note). Phase 6 D6-10 makes the banner
/// honest: `AppCoordinator` observes `AppSession.trustTier` and calls
/// `update(trustTier:)` so the banner appears on a downgrade and is removed on
/// an upgrade — WITHOUT a root-swap and WITHOUT animation (ADR 0002
/// abrupt-replace posture). The banner stays non-dismissible (D-11).
@MainActor
public final class LimitedTrustBannerContainerViewController: UIViewController {

    private let child: UITabBarController
    private var banner: LimitedTrustBannerView?

    /// Top constraint of the child tab bar's view. When the banner is present
    /// the child pins below the banner; when absent it pins to the safe-area
    /// top. Swapped in `update(trustTier:)`.
    private var childTopConstraint: NSLayoutConstraint?

    /// - Parameter child: the role tab bar controller hosted as the content.
    ///   The banner's initial visibility is decided by the first
    ///   `update(trustTier:)` call (made by `wrapWithLimitedTrustBanner` /
    ///   `AppCoordinator` immediately after construction).
    public init(child: UITabBarController) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("LimitedTrustBannerContainerViewController is constructed programmatically only")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // UIKit parent-child containment discipline (addChild → addSubview →
        // didMove). Without this, rotation callbacks + size-class propagation
        // would bypass the child tab bar controller, breaking iPad landscape
        // layout (04-RESEARCH.md Pitfall 7).
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        child.didMove(toParent: self)

        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Show the banner when `trustTier != .hardwareAttested`, remove it
    /// otherwise. Idempotent — calling with the current tier is a no-op-ish
    /// re-application. No animation (D6-10 / ADR 0002).
    public func update(trustTier: TrustTier) {
        loadViewIfNeeded()
        let shouldShowBanner = (trustTier != .hardwareAttested)

        if shouldShowBanner, banner == nil {
            let newBanner = LimitedTrustBannerView()
            newBanner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(newBanner)
            NSLayoutConstraint.activate([
                // Banner pinned to safe-area top (04-RESEARCH.md Pitfall 7).
                newBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                newBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            childTopConstraint?.isActive = false
            childTopConstraint = child.view.topAnchor.constraint(equalTo: newBanner.bottomAnchor)
            childTopConstraint?.isActive = true
            banner = newBanner
        } else if !shouldShowBanner, let existing = banner {
            existing.removeFromSuperview()
            banner = nil
            childTopConstraint?.isActive = false
            childTopConstraint = child.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            )
            childTopConstraint?.isActive = true
        } else if childTopConstraint == nil {
            // First call with no banner needed — pin the child to the safe-area
            // top so it is fully constrained.
            childTopConstraint = child.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            )
            childTopConstraint?.isActive = true
        }

        // D6-10 / ADR 0002: abrupt layout, no animation.
        view.layoutIfNeeded()
    }
}
