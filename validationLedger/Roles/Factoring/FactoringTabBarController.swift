// validationLedger/Roles/Factoring/FactoringTabBarController.swift
// Factoring role tab bar per TechStack.md §4 / D-09: Invoices, Carriers, Chain, Assistant.

import UIKit

final class FactoringTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .factoring
    var rootViewController: UIViewController { self }

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
