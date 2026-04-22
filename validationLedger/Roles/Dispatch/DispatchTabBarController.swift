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

    init(logoutService: any LogoutService) {
        self.logoutService = logoutService
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
    }
}
