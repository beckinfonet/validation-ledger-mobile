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
