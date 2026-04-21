// validationLedger/Roles/Dispatch/DispatchTabBarController.swift
// Dispatch role tab bar per TechStack.md §4 / D-09: Loads, Fleet, Drivers, Assistant.

import UIKit

final class DispatchTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .dispatch
    var rootViewController: UIViewController { self }

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
