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
    /// WR-04 — `title` / `systemImage` are explicit parameters so the
    /// Factoring caller can ALSO route through this helper (passing
    /// `"Invoices"` / `"doc.text.magnifyingglass"`). Pre-WR-04, Factoring
    /// duplicated the entire title-override flow inline in its own
    /// `viewDidLoad()` (a fresh `UITabBarItem(title:image:selectedImage:)`
    /// after `wrapTabsWithNavAndInstallAvatar` that discarded any
    /// `accessibilityIdentifier` set on the inner VC's tabBarItem). The
    /// single-place implementation here:
    ///   1. Mutates the existing `tabBarItem` in place — preserves any
    ///      `accessibilityIdentifier` set elsewhere (the avatar's
    ///      `nav-avatar` identifier lives on `navigationItem
    ///      .rightBarButtonItem`, not on `tabBarItem`, but the principle
    ///      generalizes: in-place mutation never clobbers identifiers).
    ///   2. Defaults `title` to `"Loads"` and `systemImage` to `"shippingbox"`
    ///      so the four existing callers (Broker/Shipper/Carrier/Dispatch)
    ///      keep their call sites unchanged.
    ///   3. Centralizes the role→Loads-tab construction so a future edit
    ///      (icon swap, accessibility-identifier addition) lands in ONE place,
    ///      not five.
    static func makeLoadsTab(
        loadListScreenFactory: ((Role) -> UIViewController)?,
        role: Role,
        title: String = "Loads",
        systemImage: String = "shippingbox"
    ) -> UIViewController {
        let vc = loadListScreenFactory?(role)
            ?? makeTab(title: title, systemImage: systemImage)
        // Note: `vc.title` drives the IN-SCREEN nav-bar title via UIKit's
        // implicit propagation. BL-02 owns that string explicitly through
        // `LoadListViewController.init(viewModel:navTitle:)` for the real
        // factory path; the fallback `makeTab(...)` path already set
        // `vc.title = title` itself, so this line is redundant for the
        // fallback but needed for the factory path to override
        // `LoadListViewController`'s default "Loads" title when this helper
        // is invoked with a non-default title (Factoring → "Invoices").
        vc.title = title
        // WR-04 — mutate the EXISTING `tabBarItem` instead of replacing it
        // wholesale. This preserves any `accessibilityIdentifier` /
        // `accessibilityLabel` future plans may set on the inner VC's
        // tabBarItem (the avatar's `nav-avatar` is on a different
        // navigationItem, but the in-place mutation pattern is the
        // generalizable safe default for tab-bar customization).
        vc.tabBarItem.title = title
        vc.tabBarItem.image = UIImage(systemName: systemImage)
        vc.tabBarItem.selectedImage = nil
        return vc
    }
}
