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

    /// Phase 8 LOAD-03 (D-01..D-04). Composition-root factory for the
    /// role-scoped Loads screen; forwarded by
    /// `AppCoordinator.roleCoordinator(for:container:)`. The closure is
    /// parameterized by `Role` so this tab bar invokes
    /// `loadListScreenFactory?(self.role)` to back the role-appropriate Loads
    /// tab (Invoices on Factoring). `nil` fallback preserves the v1.1
    /// placeholder for any test that constructs the tab bar without injecting
    /// the factory.
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
            Self.makeLoadsTab(loadListScreenFactory: loadListScreenFactory, role: role),
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

    /// Phase 8 LOAD-03: build the role-scoped Loads tab. If
    /// `loadListScreenFactory` is non-nil, returns the real
    /// `LoadListViewController` for the given role (constructed lazily by the
    /// composition root). Else falls back to the v1.1 placeholder
    /// `makeTab(title:systemImage:)` — preserves source compatibility for any
    /// test that constructs a tab bar without injecting the factory.
    ///
    /// Tab item title is always `"Loads"` (UI-SPEC: tab title is "Loads" —
    /// never "Broker Loads" etc.). The Factoring caller does NOT route through
    /// this helper — it has its own inline `"Invoices"` branch in
    /// `FactoringTabBarController.viewDidLoad()` (PATTERNS Q1; T-08-12) so the
    /// tab title literal `"Invoices"` is preserved end-to-end.
    static func makeLoadsTab(
        loadListScreenFactory: ((Role) -> UIViewController)?,
        role: Role
    ) -> UIViewController {
        let vc = loadListScreenFactory?(role)
            ?? makeTab(title: "Loads", systemImage: "shippingbox")
        vc.title = "Loads"
        vc.tabBarItem = UITabBarItem(
            title: "Loads",
            image: UIImage(systemName: "shippingbox"),
            selectedImage: nil
        )
        return vc
    }
}
