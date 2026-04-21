// validationLedger/App/AppCoordinator.swift
// Top-level coordinator. In Phase 1 it's thin — just picks a role VC
// from AppPhase. Phase 3 adds real AuthCoordinator + session routing.
//
// `container` is internal (module-visible) rather than private so that SceneDelegate's
// deep-link forwarding and DevMenu's shake-gesture handler can reach it directly
// without a shim extension.

import UIKit

final class AppCoordinator {
    let container: AppContainer
    private let phase: AppPhase
    let rootViewController: UIViewController

    // Callbacks (Plan 07 / Phase 3 wires real trigger points):
    var onRoleResolved: ((Role) -> Void)?
    var onLogout: (() -> Void)?

    init(container: AppContainer, phase: AppPhase) {
        self.container = container
        self.phase = phase
        self.rootViewController = Self.makeRoot(for: phase)
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

    private static func makeRoot(for phase: AppPhase) -> UIViewController {
        switch phase {
        case .launch:
            // Phase 3 adds a proper launch screen + token probe. Phase 1 falls through to shipper shell.
            return ShipperTabBarController()
        case .auth:
            // Phase 3 adds the OTP flow. Phase 1 placeholder.
            let vc = UIViewController()
            vc.view.backgroundColor = .systemBackground
            vc.title = "Auth (Phase 3)"
            return vc
        case .role(let role):
            return Self.roleCoordinator(for: role)
        }
    }

    static func roleCoordinator(for role: Role) -> UITabBarController {
        switch role {
        case .shipper:   return ShipperTabBarController()
        case .broker:    return BrokerTabBarController()
        case .carrier:   return CarrierTabBarController()
        case .dispatch:  return DispatchTabBarController()
        case .factoring: return FactoringTabBarController()
        }
    }

    private static func phaseDescription(_ phase: AppPhase) -> String {
        switch phase {
        case .launch:       return "launch"
        case .auth:         return "auth"
        case .role(let r):  return "role.\(r.rawValue)"
        }
    }
}
