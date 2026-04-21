// validationLedger/App/SceneDelegate.swift
// UIKit scene lifecycle + root-swap mechanism (D-10 / ADR 0002).
// Also hosts the DEBUG-only shake responder that presents DevMenu (D-12).
//
// No SwiftUI in this file (ARCH-01).

import UIKit

public enum AppPhase {
    case launch
    case auth
    case role(Role)
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        // XCUITest override — CI-02 placeholder tests use this to drive each role shell.
        // Production / Release builds NEVER see this path (file-level DEBUG gate below);
        // even Debug only reacts if launchArguments include the sentinel flag.
        #if DEBUG
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ForceRoleForUITest"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            let raw = ProcessInfo.processInfo.arguments[idx + 1]
            if let role = Role(rawValue: raw) {
                presentRoot(.role(role))
                window.makeKeyAndVisible()
                return
            }
        }
        #endif

        // Phase 1 default: start at shipper. DevMenu (DEBUG) swaps to other roles;
        // Phase 3 replaces with .launch/.auth routing based on session-token probe.
        presentRoot(.role(.shipper))

        window.makeKeyAndVisible()

        // FOUND-08 / Pitfall P18: if this scene launched from a deep link,
        // forward to DeepLinkRouter now (it will queue until bootstrapComplete).
        if let urlContext = connectionOptions.urlContexts.first {
            appCoordinator?.container.deepLinkRouter.receive(urlContext.url)
        }
    }

    // MARK: - Deep-link forwarding

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            appCoordinator?.container.deepLinkRouter.receive(context.url)
        }
    }

    // MARK: - Root-swap mechanism (D-10 / ADR 0002)

    func presentRoot(_ phase: AppPhase) {
        // Fresh container + fresh coordinator per D-10.
        let container = AppContainer(env: .current)
        let coordinator = AppCoordinator(container: container, phase: phase)

        // Wire callbacks that can trigger re-routing in Phase 3+.
        coordinator.onRoleResolved = { [weak self] role in
            self?.presentRoot(.role(role))
        }
        coordinator.onLogout = { [weak self] in
            self?.presentRoot(.auth)   // Phase 3 replaces with real phone-entry screen
        }

        self.appCoordinator = coordinator                       // single strong reference
        self.window?.rootViewController = coordinator.rootViewController
        // Previous coordinator tree orphaned; ARC deallocates on next runloop.
        // Abrupt replace — no animation (D-10 mandate).

        // Signal the DeepLinkRouter that bootstrap is complete — pending links drain now.
        container.deepLinkRouter.bootstrapComplete()
    }

    // MARK: - DEBUG shake gesture (D-12 / D-13)

    #if DEBUG
    override var canBecomeFirstResponder: Bool { true }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        appCoordinator?.presentDevMenu()
    }
    #endif
}
