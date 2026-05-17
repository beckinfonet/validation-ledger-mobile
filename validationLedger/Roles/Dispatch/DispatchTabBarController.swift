// validationLedger/Roles/Dispatch/DispatchTabBarController.swift
// Dispatch role tab bar per TechStack.md §4 / D-09: Loads, Fleet, Drivers, Assistant.

import UIKit

final class DispatchTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .dispatch
    var rootViewController: UIViewController { self }

    /// Phase 3 Plan 11 (D-03 / AUTH-04): LogoutService is injected so the avatar
    /// affordance (installed in Task 2 via the shared RoleCoordinator helper) can
    /// present `ProfileViewController(logoutService:)` modally on tap.
    let logoutService: any LogoutService

    /// Phase 5 Plan 08 (D-08): the composition-root factory for the KYC status
    /// screen, forwarded into the modal `ProfileViewController`. `nil` hides the row.
    let kycStatusScreenFactory: (() -> UIViewController)?

    init(
        logoutService: any LogoutService,
        kycStatusScreenFactory: (() -> UIViewController)? = nil
    ) {
        self.logoutService = logoutService
        self.kycStatusScreenFactory = kycStatusScreenFactory
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            ShipperTabBarController.makeTab(title: "Loads",     systemImage: "shippingbox"),
            ShipperTabBarController.makeTab(title: "Fleet",     systemImage: "car.2"),
            ShipperTabBarController.makeTab(title: "Drivers",   systemImage: "person.badge.key"),
            ShipperTabBarController.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
        // Phase 3 D-03: shared avatar affordance — see ShipperTabBarController for rationale.
        wrapTabsWithNavAndInstallAvatar { [weak self] in
            guard let self else { return UIViewController() }
            return ProfileViewController(
                logoutService: self.logoutService,
                kycStatusScreenFactory: self.kycStatusScreenFactory
            )
        }
    }
}
