// validationLedger/Roles/Shipper/ShipperTabBarController.swift
// Shipper role tab bar per TechStack.md §4 / D-09: Loads, Brokers, BOL, Assistant.

import UIKit

final class ShipperTabBarController: UITabBarController, RoleCoordinator {
    let role: Role = .shipper
    var rootViewController: UIViewController { self }

    /// Phase 3 Plan 11 (D-03 / AUTH-04): LogoutService is injected so the avatar
    /// affordance (installed in Task 2 via the shared RoleCoordinator helper) can
    /// present `ProfileViewController(logoutService:)` modally on tap.
    let logoutService: any LogoutService

    /// Phase 5 Plan 08 (D-08): the composition-root factory for the KYC status
    /// screen, forwarded into the modal `ProfileViewController` so its
    /// "Verification status" row can open the screen. `nil` hides the row.
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
            Self.makeTab(title: "Loads",     systemImage: "shippingbox"),
            Self.makeTab(title: "Brokers",   systemImage: "person.2"),
            Self.makeTab(title: "BOL",       systemImage: "doc.text"),
            Self.makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
        // Phase 3 D-03: wrap each tab in a UINavigationController and install the
        // shared avatar affordance via the RoleCoordinator helper. Tap → present
        // ProfileViewController modally with the injected LogoutService.
        wrapTabsWithNavAndInstallAvatar { [weak self] in
            guard let self else { return UIViewController() }
            return ProfileViewController(
                logoutService: self.logoutService,
                kycStatusScreenFactory: self.kycStatusScreenFactory
            )
        }
    }

    /// Shared helper for all 5 role tab bars (reused across subclasses).
    /// Placeholder per D-09: title + SF Symbol + .systemBackground only.
    /// Phase 3 fills tab content.
    static func makeTab(title: String, systemImage: String) -> UIViewController {
        let vc = UIViewController()
        vc.title = title
        vc.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: nil
        )
        vc.view.backgroundColor = .systemBackground
        return vc
    }
}
