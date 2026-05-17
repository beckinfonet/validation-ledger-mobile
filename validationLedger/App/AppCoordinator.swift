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

    /// Phase 5 D-12: fires when a just-authenticated user is not yet KYC-verified —
    /// SceneDelegate root-swaps to `AppPhase.kyc(role)`, the KYC hard gate.
    /// Bubbled from `AuthCoordinator.onKYCRequired` ← `OTPViewModel.onKYCRequired`.
    var onKYCRequired: ((Role) -> Void)?

    /// Phase 3 Plan 11 — D-01: strong reference to the AuthCoordinator that owns the
    /// UINavigationController installed as window.rootViewController for AppPhase.auth.
    /// Without this retention the AuthCoordinator deallocates immediately after `makeRoot`
    /// returns — the nav stays alive (UIKit retains it via window.rootViewController) but
    /// the coordinator's `onAuthenticated` closure + `pushOTP` plumbing would be orphaned.
    /// Cleared automatically when SceneDelegate root-swaps to a non-.auth phase (new
    /// AppCoordinator constructed; this one deallocates).
    private var authCoordinator: AuthCoordinator?

    /// Phase 5 Plan 07 — D-12: strong reference to the KYCCoordinator that owns the
    /// UINavigationController installed as window.rootViewController for AppPhase.kyc.
    /// Mirrors `authCoordinator` EXACTLY (RESEARCH Pitfall 6): without this retention the
    /// KYCCoordinator deallocates immediately after the init switch returns — the nav
    /// stays alive (UIKit retains it via window.rootViewController) but the coordinator's
    /// `onKYCSubmitted` / `onSignOut` closures + every `push…` capture would be orphaned.
    /// This was a real Phase-3 bug fixed for AuthCoordinator; do not reintroduce it.
    /// Held for the AppCoordinator's full lifetime; cleared automatically when
    /// SceneDelegate root-swaps to a non-.kyc phase (this AppCoordinator deallocates).
    private var kycCoordinator: KYCCoordinator?

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
        case .kyc:
            // Phase 5 D-12: the KYC hard gate. Construct the KYCCoordinator and store
            // it in the `kycCoordinator` strong property BEFORE surfacing its
            // rootViewController (mirrors the .auth two-phase init). The callback
            // wiring (`onKYCSubmitted` / `onSignOut`) is done after `self` is fully
            // initialized — see below.
            let coord = KYCCoordinator(container: container)
            self.kycCoordinator = coord
            self.rootViewController = coord.rootViewController
        case .role(let role):
            // Phase 4 D-11 + D-12: wrap the role tab bar with the non-dismissible
            // limited-trust banner when container.session.trustTier != .hardwareAttested.
            // Default AppSession.trustTier is .softwareOnly (Plan 06 safe default), so the
            // banner shows on first cold-launch before any /device/register or
            // /device/heartbeat response has confirmed .hardwareAttested (D-12). The
            // wrapper is idempotent on the hardware-attested branch (returns `self`).
            //
            // Placement rationale: this is the single construction site for the .role
            // root VC; wrapping here keeps the banner attached to every path that lands
            // on a role shell (cold-boot restore, post-OTP verify, DevMenu role-swap,
            // NetworkConfig toggle — all funnel through SceneDelegate.presentRoot which
            // constructs a fresh AppCoordinator with a fresh AppContainer per ADR 0002).
            let tabBar = Self.roleCoordinator(for: role, container: container)
            self.rootViewController = tabBar.wrapWithLimitedTrustBanner(trustTier: container.session.trustTier)
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
            // Phase 5 D-12: a not-yet-KYC-verified user post-OTP routes to the
            // `.kyc` hard gate instead of the role shell.
            auth.onKYCRequired = { [weak self] role in
                self?.onKYCRequired?(role)
            }
        }
        // Phase 5 D-12 / D-14: wire the KYCCoordinator callbacks after `self` is
        // fully initialized. `onKYCSubmitted` routes to the role shell — the role
        // is carried in the `.kyc(Role)` phase payload (the cached/restored
        // session role). `onSignOut` (D-14) runs `LogoutService.logout(.userInitiated)`:
        // that wipes the session-scope Keychain (incl. the cached `kycStatus`) and
        // posts `.sessionDidInvalidate`, which SceneDelegate's existing observer
        // root-swaps to phone-entry. The on-disk `KYCSessionStore` blob is NOT in
        // LogoutService teardown (D-02) — the partial KYC resumes on next login.
        if let kyc = self.kycCoordinator, case .kyc(let role) = phase {
            kyc.onKYCSubmitted = { [weak self] in
                self?.onRoleResolved?(role)
            }
            kyc.onSignOut = { [weak container] in
                guard let container else { return }
                Task { @MainActor in
                    await container.logoutService.logout(reason: .userInitiated)
                }
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
        case .kyc(let r):           return "kyc.\(r.rawValue)"
        case .role(let r):          return "role.\(r.rawValue)"
        case .anotherActiveSession: return "anotherActiveSession"
        }
    }
}
