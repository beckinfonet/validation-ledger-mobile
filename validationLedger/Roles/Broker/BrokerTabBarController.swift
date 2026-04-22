// validationLedger/Roles/Broker/BrokerTabBarController.swift
// Broker role tab bar per TechStack.md §4 / D-09: Loads, Carriers, Network, Assistant.

import UIKit

final class BrokerTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .broker
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
            ShipperTabBarController.makeTab(title: "Carriers",  systemImage: "truck.box"),
            ShipperTabBarController.makeTab(title: "Network",   systemImage: "point.3.connected.trianglepath.dotted"),
            ShipperTabBarController.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
        // Phase 3 D-03: shared avatar affordance — see ShipperTabBarController for rationale.
        wrapTabsWithNavAndInstallAvatar { [weak self] in
            guard let self else { return UIViewController() }
            return ProfileViewController(logoutService: self.logoutService)
        }
    }
}
