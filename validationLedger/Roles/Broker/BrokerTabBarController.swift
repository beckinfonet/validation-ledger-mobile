// validationLedger/Roles/Broker/BrokerTabBarController.swift
// Broker role tab bar per TechStack.md §4 / D-09: Loads, Carriers, Network, Assistant.

import UIKit

final class BrokerTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .broker
    var rootViewController: UIViewController { self }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            ShipperTabBarController.makeTab(title: "Loads",     systemImage: "shippingbox"),
            ShipperTabBarController.makeTab(title: "Carriers",  systemImage: "truck.box"),
            ShipperTabBarController.makeTab(title: "Network",   systemImage: "point.3.connected.trianglepath.dotted"),
            ShipperTabBarController.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
    }
}
