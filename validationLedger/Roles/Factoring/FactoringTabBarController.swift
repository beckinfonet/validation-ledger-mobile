// validationLedger/Roles/Factoring/FactoringTabBarController.swift
// Factoring role tab bar per TechStack.md §4 / D-09: Invoices, Carriers, Chain, Assistant.

import UIKit

final class FactoringTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .factoring
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
            ShipperTabBarController.makeTab(title: "Invoices",  systemImage: "doc.text.magnifyingglass"),
            ShipperTabBarController.makeTab(title: "Carriers",  systemImage: "truck.box"),
            ShipperTabBarController.makeTab(title: "Chain",     systemImage: "link"),
            ShipperTabBarController.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
    }
}
