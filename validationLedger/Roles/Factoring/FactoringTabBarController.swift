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
        //
        // WR-04 — route through the centralized
        // `ShipperTabBarController.makeLoadsTab(...)` helper with the
        // Factoring overrides (`title: "Invoices"`, `systemImage:
        // "doc.text.magnifyingglass"`). Pre-WR-04 this file open-coded the
        // entire title-override flow inline AND issued a second
        // `viewControllers?.first?.tabBarItem = UITabBarItem(...)` REPLACEMENT
        // after `wrapTabsWithNavAndInstallAvatar` — the latter discarded
        // any `accessibilityIdentifier` the inner VC may have set on its
        // tab-bar item (and duplicated the role→title mapping logic in a
        // second place where a future edit could drift). The helper now
        // mutates `tabBarItem` in place and is the single source of truth for
        // Loads-tab construction across all 5 roles.
        //
        // BL-02 — the in-screen nav-bar title is owned by the composition
        // root: `AppContainer.makeLoadListScreen(role:)` threads
        // `navTitle: "Invoices"` for `.factoring` into
        // `LoadListViewController.init`, so the loads VC's `viewDidLoad`
        // assigns `title = "Invoices"` itself. `makeLoadsTab` also assigns
        // `vc.title = title` ("Invoices" here) as a belt-and-braces measure
        // for any future caller that constructs the tab without the factory.
        viewControllers = [
            ShipperTabBarController.makeLoadsTab(
                loadListScreenFactory: loadListScreenFactory,
                role: role,
                title: "Invoices",
                systemImage: "doc.text.magnifyingglass"
            ),
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
        // WR-04 — the post-wrap "override the outer nav's tabBarItem" block
        // is GONE. `makeLoadsTab` set the inner VC's `tabBarItem` properties
        // in place BEFORE wrapping, and `wrapTabsWithNavAndInstallAvatar`
        // propagates the inner tabBarItem to the wrapping nav by default
        // (UIKit's `UINavigationController.tabBarItem` is forwarded from its
        // root VC unless overridden). T-08-12 stays locked because
        // `makeLoadsTab(..., title: "Invoices", ...)` is the single source of
        // truth; `RoleShellSmokeTests:151` continues to assert `tabBars
        // .buttons["Invoices"]`.
    }
}
