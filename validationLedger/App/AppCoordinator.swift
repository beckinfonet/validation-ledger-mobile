// validationLedger/App/AppCoordinator.swift
// Top-level coordinator. In Phase 1 it's thin — just picks a role VC
// from AppPhase. Phase 3 adds real AuthCoordinator + session routing.
//
// `container` is internal (module-visible) rather than private so that SceneDelegate's
// deep-link forwarding and DevMenu's shake-gesture handler can reach it directly
// without a shim extension.

import UIKit

@MainActor
final class AppCoordinator {
    let container: AppContainer
    private let phase: AppPhase
    let rootViewController: UIViewController

    // Callbacks (Plan 07 / Phase 3 wires real trigger points):
    var onRoleResolved: ((Role) -> Void)?
    var onLogout: (() -> Void)?

    /// Phase 3 Plan 11 — D-01: strong reference to the AuthCoordinator that owns the
    /// UINavigationController installed as window.rootViewController for AppPhase.auth.
    /// Without this retention the AuthCoordinator deallocates immediately after `makeRoot`
    /// returns — the nav stays alive (UIKit retains it via window.rootViewController) but
    /// the coordinator's `onAuthenticated` closure + `pushOTP` plumbing would be orphaned.
    /// Cleared automatically when SceneDelegate root-swaps to a non-.auth phase (new
    /// AppCoordinator constructed; this one deallocates).
    private var authCoordinator: AuthCoordinator?

    init(container: AppContainer, phase: AppPhase) {
        self.container = container
        self.phase = phase
        // Two-phase init so we can store the AuthCoordinator strong reference BEFORE
        // surfacing its rootViewController. Phase 1's static makeRoot path is preserved
        // for .launch / .role / .anotherActiveSession; .auth now hydrates an instance
        // property for coordinator retention.
        switch phase {
        case .launch:
            self.rootViewController = ShipperTabBarController(logoutService: container.logoutService)
        case .auth:
            let coord = AuthCoordinator(container: container)
            self.authCoordinator = coord
            self.rootViewController = coord.rootViewController
        case .role(let role):
            self.rootViewController = Self.roleCoordinator(for: role, container: container)
        case .anotherActiveSession:
            self.rootViewController = AnotherActiveSessionViewController(supportEmail: Environment.supportEmail)
        }
        // Wire the AuthCoordinator's onAuthenticated callback AFTER self is fully
        // initialized so we can forward through `onRoleResolved` without capturing a
        // not-yet-initialized self. SceneDelegate sets `onRoleResolved` from outside
        // after init returns (existing Phase 1 wiring); forwarding here preserves that.
        if let auth = self.authCoordinator {
            auth.onAuthenticated = { [weak self] role in
                self?.onRoleResolved?(role)
            }
        }
        container.logger.info(event: .init("app_coordinator_init"), fields: [.event: Self.phaseDescription(phase)])
    }

    deinit {
        container.logger.info(event: .init("app_coordinator_deinit"), fields: [:])
    }

    #if DEBUG
    /// Invoked by SceneDelegate's shake-gesture handler.
    func presentDevMenu() {
        let devMenu = DevMenuViewController(container: container, appCoordinator: self)
        rootViewController.present(UINavigationController(rootViewController: devMenu), animated: true)
    }
    #endif

    // MARK: - Private

    @MainActor
    static func roleCoordinator(for role: Role, container: AppContainer) -> UITabBarController {
        switch role {
        case .shipper:   return ShipperTabBarController(logoutService: container.logoutService)
        case .broker:    return BrokerTabBarController(logoutService: container.logoutService)
        case .carrier:   return CarrierTabBarController(logoutService: container.logoutService)
        case .dispatch:  return DispatchTabBarController(logoutService: container.logoutService)
        case .factoring: return FactoringTabBarController(logoutService: container.logoutService)
        }
    }

    private static func phaseDescription(_ phase: AppPhase) -> String {
        switch phase {
        case .launch:               return "launch"
        case .auth:                 return "auth"
        case .role(let r):          return "role.\(r.rawValue)"
        case .anotherActiveSession: return "anotherActiveSession"
        }
    }
}
