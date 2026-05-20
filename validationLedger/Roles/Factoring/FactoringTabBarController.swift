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

    /// Phase 5 Plan 08 (D-08): the composition-root factory for the KYC status
    /// screen, forwarded into the modal `ProfileViewController`. `nil` hides the row.
    let kycStatusScreenFactory: (() -> UIViewController)?

    /// Phase 8 LOAD-03 (D-01..D-04). Composition-root factory for the
    /// role-scoped Loads screen; forwarded by
    /// `AppCoordinator.roleCoordinator(for:container:)`. The closure is
    /// parameterized by `Role` so this tab bar invokes
    /// `loadListScreenFactory?(.factoring)` to back the Factoring "Invoices"
    /// tab — the loads ARE invoices for the factoring role per the existing
    /// fixture set (Plan 01 D-04). The TAB TITLE remains `"Invoices"` (T-08-12
    /// / PATTERNS Q1). `nil` fallback preserves the v1.1 placeholder.
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
        // PATTERNS.md Q1 + T-08-12 / RoleShellSmokeTests.swift:151. The
        // factoring "Invoices" tab is backed by the real
        // `LoadListViewController(.factoring)` — the loads ARE invoices for
        // the factoring role per the existing fixture set (Plan 01 D-04). The
        // TAB ITEM TITLE remains `"Invoices"` exactly
        // (RoleShellSmokeTests:151 assertion).
        let invoicesTab: UIViewController = loadListScreenFactory?(role)
            ?? ShipperTabBarController.makeTab(title: "Invoices", systemImage: "doc.text.magnifyingglass")
        invoicesTab.title = "Invoices"
        invoicesTab.tabBarItem = UITabBarItem(
            title: "Invoices",
            image: UIImage(systemName: "doc.text.magnifyingglass"),
            selectedImage: nil
        )
        viewControllers = [
            invoicesTab,
            ShipperTabBarController.makeTab(title: "Carriers",  systemImage: "truck.box"),
            ShipperTabBarController.makeTab(title: "Chain",     systemImage: "link"),
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
        // T-08-12 lock: override the wrapping UINavigationController's
        // tabBarItem so the tab bar continues to render `"Invoices"` even
        // after `LoadListViewController.viewDidLoad` sets its `title = "Loads"`
        // (UIKit propagates `title` into the implicit tabBarItem.title).
        // Setting tabBarItem here on the OUTER wrapper short-circuits that
        // inheritance — the wrapper's tabBarItem is independently owned. The
        // literal string `"Invoices"` appears twice in this file (the inner
        // VC's tabBarItem above and the wrapper's tabBarItem here), both must
        // remain in lockstep so a future refactor that touches one still
        // preserves the locked product surface.
        if let invoicesNav = viewControllers?.first {
            invoicesNav.tabBarItem = UITabBarItem(
                title: "Invoices",
                image: UIImage(systemName: "doc.text.magnifyingglass"),
                selectedImage: nil
            )
        }
    }
}
