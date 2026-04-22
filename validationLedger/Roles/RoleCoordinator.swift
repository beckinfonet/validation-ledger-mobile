// validationLedger/Roles/RoleCoordinator.swift
// ARCH-06: protocol that each role's root coordinator conforms to.
// Concrete role coordinators live in later phases; Phase 1 ships only the
// UITabBarController subclasses (one per role) because that is what the
// DevMenu swap (D-07) needs to demonstrate end-to-end.
//
// SceneDelegate (Plan 05) uses this protocol to present a new root when
// the active role changes; the abrupt-replace semantics are ADR 0002.
//
// Phase 3 Plan 11 (D-03 / SHELL-03): shared avatar affordance helper.
// The 5 role TabBarControllers all install the same top-bar avatar item —
// placing the implementation here keeps the wiring DRY and ensures the
// accessibility identifier ("nav-avatar") + the Profile modal presentation
// stay consistent across all 5 shells. Required for Plan 12 UI smoke tests
// which target the avatar via accessibilityIdentifier.

import UIKit

public protocol RoleCoordinator: AnyObject {
    var role: Role { get }
    /// The root view controller installed as window.rootViewController.
    var rootViewController: UIViewController { get }
}

// MARK: - Phase 3 D-03 avatar affordance (SHELL-03)

@MainActor
public extension RoleCoordinator where Self: UITabBarController {
    /// Wraps each existing tab root in a `UINavigationController` and installs an
    /// avatar `UIBarButtonItem` on the embedded root's `navigationItem`. Tapping the
    /// avatar calls the `presenter` closure — role TabBarControllers pass a closure
    /// that constructs `ProfileViewController(logoutService:)` and it gets presented
    /// modally in a fresh UINavigationController.
    ///
    /// Called from each role's `viewDidLoad` AFTER `viewControllers` has been assigned
    /// with the raw tab VCs. The helper replaces `viewControllers` with nav-wrapped
    /// variants in-place.
    ///
    /// Accessibility: the bar button item's `accessibilityIdentifier` is fixed at
    /// `"nav-avatar"` so Plan 12 UI smoke tests can target it deterministically across
    /// all 5 role shells without needing role-specific selectors.
    ///
    /// System image "person.crop.circle" is the SF Symbol; every iOS 17 device ships
    /// with it. No asset catalog entry needed.
    func wrapTabsWithNavAndInstallAvatar(presenter: @escaping () -> UIViewController) {
        let wrapped: [UIViewController] = (viewControllers ?? []).map { tabRoot in
            // Preserve existing nav controllers if a future plan ever wraps tabs upstream —
            // this helper currently always constructs fresh navs in M1.
            let nav = (tabRoot as? UINavigationController) ?? UINavigationController(rootViewController: tabRoot)
            let root = nav.viewControllers.first ?? nav
            let item = UIBarButtonItem(
                image: UIImage(systemName: "person.crop.circle"),
                primaryAction: UIAction { [weak root] _ in
                    guard let root else { return }
                    let profile = presenter()
                    let modalNav = UINavigationController(rootViewController: profile)
                    modalNav.modalPresentationStyle = .formSheet
                    root.present(modalNav, animated: true)
                }
            )
            item.accessibilityIdentifier = "nav-avatar"
            item.accessibilityLabel = "Profile"
            root.navigationItem.rightBarButtonItem = item
            return nav
        }
        viewControllers = wrapped
    }
}

// MARK: - Phase 4 D-11 / D-12 limited-trust banner wrapper

@MainActor
public extension UITabBarController {
    /// Phase 4 D-11 + D-12: conditionally wraps the tab bar controller with a
    /// non-dismissible limited-trust banner when the backend-returned
    /// `trustTier` is not `.hardwareAttested`.
    ///
    /// Returns:
    /// - `trustTier == .hardwareAttested` → `self` unchanged (no wrapper).
    /// - `trustTier == .softwareOnly`     → a parent `UIViewController` whose
    ///   view stack is `[self.view (pinned to safe-area bottom + sides + under
    ///   banner), LimitedTrustBannerView (pinned to safe-area top)]`. The
    ///   wrapper becomes the new `window.rootViewController` for the `.role`
    ///   phase; `SceneDelegate.presentRoot` swaps to this wrapper.
    ///
    /// Layout (04-RESEARCH.md Pitfall 7): banner pins to the parent container
    /// view's safe-area top, NOT raw `topAnchor`. This is the discipline that
    /// survives iPad notch, Dynamic Island, and portrait↔landscape rotation.
    /// Raw `topAnchor` pinning breaks under the status bar on notched devices.
    ///
    /// Why the banner is a sibling (NOT a subview of `self.tabBar`):
    /// Apple does not support adding arbitrary subviews to `UITabBarController.tabBar`
    /// — it breaks on iPad landscape where the tab bar layout changes. Installing the
    /// banner inside a parent container VC sidesteps the constraint entirely.
    ///
    /// Re-wrapping semantics: if `trustTier` mutates from `.softwareOnly` →
    /// `.hardwareAttested` mid-session via a Plan 07 heartbeat (D-12), the
    /// banner does NOT auto-remove this session. A fresh `presentRoot(.role)`
    /// call (app relaunch, role switch, logout+login) re-evaluates. This is
    /// the M1 tradeoff per CLAUDE.md simplicity posture; M2 can introduce a
    /// reactive update via NotificationCenter if product demands it.
    func wrapWithLimitedTrustBanner(trustTier: TrustTier) -> UIViewController {
        guard trustTier != .hardwareAttested else {
            return self
        }

        let container = UIViewController()
        container.view.backgroundColor = .systemBackground

        let banner = LimitedTrustBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(banner)

        // UIKit parent-child containment discipline (addChild → addSubview → didMove).
        // Without this, rotation callbacks + size-class propagation would bypass the
        // child tab bar controller, which would break iPad landscape layout (the exact
        // scenario Pitfall 7 warns about).
        container.addChild(self)
        self.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(self.view)
        self.didMove(toParent: container)

        NSLayoutConstraint.activate([
            // Banner pinned to safe-area top (04-RESEARCH.md Pitfall 7).
            banner.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),

            // Tab bar controller's view pinned below the banner + to all remaining
            // edges. The tab bar's own safe-area handling continues to manage the
            // bottom inset; the banner just steals the top safe-area strip.
            self.view.topAnchor.constraint(equalTo: banner.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            self.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])

        return container
    }
}
