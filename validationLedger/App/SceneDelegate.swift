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
    /// Phase 3 D-18 / DEV-06: routed to after `LogoutService.logout(.anotherActiveSession)`.
    /// Produces an `AnotherActiveSessionViewController` (terminal support-contact screen).
    case anotherActiveSession
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    /// Phase 3 Plan 11 / D-18: observer token for `.sessionDidInvalidate`. LogoutService posts
    /// this as the LAST step of its teardown orchestration (Pitfall 3). SceneDelegate maps the
    /// `LogoutReason` carried in `userInfo` to an AppPhase and root-swaps via `presentRoot`.
    private var sessionInvalidateObserver: NSObjectProtocol?

    #if DEBUG
    /// Holds the strong-typed observer token so we can remove it on deinit / scene disconnect.
    /// Phase 2 Plan 07: DevMenu NetworkConfig toggle (NET-03 SC-2) posts
    /// `.devMenuNetworkConfigRequested`; we root-swap with a fresh AppContainer bound to the
    /// requested NetworkConfig. ADR-0002 pattern — previous coordinator drops on next runloop.
    private var networkConfigObserver: NSObjectProtocol?
    /// Currently-active NetworkConfig override (nil → AppContainer.defaultNetworkConfig).
    /// Persists across role-swap so toggling DevMenu → Live → Role-switcher stays on Live.
    private var currentNetworkConfigOverride: NetworkConfig?
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        #if DEBUG
        // Observe the DevMenu NetworkConfig toggle (NET-03 SC-2 demonstrator).
        // Observer is removed in `sceneDidDisconnect` and deinit to avoid leaks.
        networkConfigObserver = NotificationCenter.default.addObserver(
            forName: .devMenuNetworkConfigRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let config = note.userInfo?[DevMenuNetworkConfigKey.config] as? NetworkConfig else {
                return
            }
            self.currentNetworkConfigOverride = config
            // Re-present the current phase (shipper by default) with a fresh AppContainer bound
            // to the new config — matches the RoleSwitcher root-swap pattern.
            self.presentRoot(.role(.shipper))
        }
        #endif

        // Phase 3 Plan 11 — D-18: observe `.sessionDidInvalidate` and root-swap based on reason.
        //   .userInitiated / .auth401        → .auth  (phone-entry)
        //   .anotherActiveSession            → .anotherActiveSession  (terminal support screen)
        // LogoutService posts this notification as the LAST step of its teardown orchestration
        // (Pitfall 3), so when this observer fires the Keychain + SE auth key + SessionLock
        // state are already cleared — presentRoot builds a fresh AppContainer for the new phase.
        sessionInvalidateObserver = NotificationCenter.default.addObserver(
            forName: .sessionDidInvalidate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let rawReason = note.userInfo?[Notification.Name.LogoutReasonKey] as? String
            let reason = rawReason.flatMap { LogoutReason(rawValue: $0) } ?? .userInitiated
            switch reason {
            case .userInitiated, .auth401:
                self.presentRoot(.auth)
            case .anotherActiveSession:
                self.presentRoot(.anotherActiveSession)
            }
        }

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

        // Phase 3 D-32 / SC-1: drive the OTP flow end-to-end via fixtures for UI smoke tests.
        // This path runs the FULL flow (phone entry → OTP entry → role shell + logout)
        // — distinct from -ForceRoleForUITest (above) which BYPASSES auth.
        //
        // Per RESEARCH Open Q1: both launchArg paths coexist. -ForceRoleForUITest is
        // retained for the DevMenu RoleSwitcher fast-path + Phase 1 placeholder tests;
        // -MockOTPRoleForUITest is the Phase 3 smoke-test path that exercises the full
        // OTP → role-shell → logout cycle Plan 12 ships.
        //
        // Sequence on launchArg detection:
        //   1. Register MockURLProtocol fixtures with role-specific verify response.
        //   2. Inject stub LocationProvider + CountryGate (Warning 4) so the geo gate
        //      is network-free + prompt-free.
        //   3. Force AppContainer to construct with .mock NetworkConfig so fixtures bite.
        //   4. Wipe session-scope Keychain so SessionRestoreProbe returns .needsAuth
        //      (guarantees the test starts on phone-entry regardless of prior state).
        //   5. presentRoot(.auth) — land on PhoneEntryVC; tests drive from there.
        // Entire block is `#if DEBUG` so Release compiles to zero bytes (T-03-12-01).
        #if DEBUG
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-MockOTPRoleForUITest"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            let raw = ProcessInfo.processInfo.arguments[idx + 1]
            if let role = Role(rawValue: raw) {
                // 1. Register fixtures — OTPRequest + OTPVerify(role) + DeviceRegister
                MockOTPRoleFixtureRegistry.registerForRole(role)
                // 2. Inject stubbed location + country gate (Warning 4)
                AppContainer.uiTestLocationProvider = StubLocationProviderForUITest()
                AppContainer.uiTestCountryGate = StubCountryGateForUITest()
                // 3. Force .mock network config so MockURLProtocol intercepts (reuses
                //    the existing DevMenu override seam).
                self.currentNetworkConfigOverride = .mock
                // 4. Wipe session-scope Keychain so SessionRestoreProbe returns
                //    .needsAuth (guaranteed clean start — T-03-12-04 mitigation).
                let scrubContainer = AppContainer(env: .current, networkConfig: .mock)
                try? scrubContainer.keychainStore.deleteAll(under: .session)
                // 5. Land on phone-entry; UI test drives the flow from there.
                presentRoot(.auth)
                window.makeKeyAndVisible()
                return
            }
        }
        #endif

        // Phase 3 D-04/D-05 (Blocker 6): probe the session via the lightweight
        // SessionRestoreProbe helper BEFORE first paint. The probe constructs ONLY
        // KeychainStore + DefaultSessionRestoreService (no SessionLockService, no
        // BiometricService, no LocationProvider) so discarding the helper does NOT
        // leak UIApplication notification observers per D-08. presentRoot then
        // constructs a fresh, full AppContainer for the selected phase per ADR 0002.
        switch SessionRestoreProbe.probe(env: .current) {
        case .restored(let role):
            presentRoot(.role(role))
        case .needsAuth:
            presentRoot(.auth)
        }

        window.makeKeyAndVisible()

        // FOUND-08 / Pitfall P18: if this scene launched from a deep link,
        // forward to DeepLinkRouter now (it will queue until bootstrapComplete).
        if let urlContext = connectionOptions.urlContexts.first {
            appCoordinator?.container.deepLinkRouter.receive(urlContext.url)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let token = sessionInvalidateObserver {
            NotificationCenter.default.removeObserver(token)
            sessionInvalidateObserver = nil
        }
        #if DEBUG
        if let token = networkConfigObserver {
            NotificationCenter.default.removeObserver(token)
            networkConfigObserver = nil
        }
        #endif
    }

    deinit {
        if let token = sessionInvalidateObserver {
            NotificationCenter.default.removeObserver(token)
        }
        #if DEBUG
        if let token = networkConfigObserver {
            NotificationCenter.default.removeObserver(token)
        }
        #endif
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
        // In DEBUG, respect the DevMenu NetworkConfig override (NET-03 SC-2 demonstrator)
        // so toggling mock/live persists across subsequent role swaps.
        #if DEBUG
        let container = AppContainer(env: .current, networkConfig: currentNetworkConfigOverride)
        #else
        let container = AppContainer(env: .current)
        #endif
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
