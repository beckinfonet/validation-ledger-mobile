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

    /// Phase 5 Plan 08 (D-08): the composition-root factory for the KYC status
    /// screen, forwarded into the modal `ProfileViewController`. `nil` hides the row.
    let kycStatusScreenFactory: (() -> UIViewController)?

    /// Phase 8 LOAD-03 (D-01..D-04). Composition-root factory for the
    /// role-scoped Loads screen; forwarded by
    /// `AppCoordinator.roleCoordinator(for:container:)`. The closure is
    /// parameterized by `Role` so this tab bar invokes
    /// `loadListScreenFactory?(self.role)` to back the Broker Loads tab. `nil`
    /// fallback preserves the v1.1 placeholder for any test that constructs the
    /// tab bar without injecting the factory.
    let loadListScreenFactory: ((Role) -> UIViewController)?

    init(
        logoutService: any LogoutService,
        kycStatusScreenFactory: (() -> UIViewController)? = nil,
        loadListScreenFactory: ((Role) -> UIViewController)? = nil
    ) {
        self.logoutService = logoutService
        self.kycStatusScreenFactory = kycStatusScreenFactory
        self.loadListScreenFactory = loadListScreenFactory
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            ShipperTabBarController.makeLoadsTab(loadListScreenFactory: loadListScreenFactory, role: role),
            ShipperTabBarController.makeTab(title: "Carriers",  systemImage: "truck.box"),
            ShipperTabBarController.makeTab(title: "Network",   systemImage: "point.3.connected.trianglepath.dotted"),
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
