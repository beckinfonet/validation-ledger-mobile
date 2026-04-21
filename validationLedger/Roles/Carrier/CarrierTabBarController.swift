// validationLedger/Roles/Carrier/CarrierTabBarController.swift
// Carrier role tab bar per TechStack.md §4 / D-09: Loads, Drivers, Documents, Assistant.

import UIKit

final class CarrierTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .carrier
    var rootViewController: UIViewController { self }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            ShipperTabBarController.makeTab(title: "Loads",     systemImage: "shippingbox"),
            ShipperTabBarController.makeTab(title: "Drivers",   systemImage: "person.badge.key"),
            ShipperTabBarController.makeTab(title: "Documents", systemImage: "doc.on.doc"),
            ShipperTabBarController.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
    }
}
