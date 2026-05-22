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

    /// Phase 6 D6-10: strong reference to the `.role`-phase limited-trust banner
    /// container so the `.trustTierDidChange` observer can re-render the banner
    /// on a `trustTier` mutation. Non-nil ONLY for the `.role` phase; nil for
    /// every other phase. Held for the AppCoordinator's full lifetime — released
    /// when SceneDelegate root-swaps to a fresh AppCoordinator (ADR 0002).
    private var limitedTrustBannerContainer: LimitedTrustBannerContainerViewController?

    /// Phase 6 D6-10: observer token for `.trustTierDidChange`, scoped to this
    /// container's `AppSession`. Removed on `deinit` so a root-swapped (dropped)
    /// AppCoordinator does not keep observing — mirrors the SceneDelegate
    /// observer-token cleanup discipline.
    private var trustTierObserver: NSObjectProtocol?

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
            // Phase 4 D-11 + D-12 / Phase 6 D6-10: wrap the role tab bar in the
            // limited-trust banner container. The banner shows when
            // container.session.trustTier != .hardwareAttested. AppContainer
            // now seeds session.trustTier from the persisted device.trustTier
            // Keychain item (D6-01 consumer) so the banner is correct from
            // frame 1 on both cold-boot restore and post-OTP verify.
            //
            // The container is retained in `limitedTrustBannerContainer` so the
            // `.trustTierDidChange` observer wired below can re-render the
            // banner when a heartbeat (D-12) or the first-login consumer
            // mutates the tier mid-session (D6-10).
            //
            // Placement rationale: this is the single construction site for the .role
            // root VC; wrapping here keeps the banner attached to every path that lands
            // on a role shell (cold-boot restore, post-OTP verify, DevMenu role-swap,
            // NetworkConfig toggle — all funnel through SceneDelegate.presentRoot which
            // constructs a fresh AppCoordinator with a fresh AppContainer per ADR 0002).
            let tabBar = Self.roleCoordinator(for: role, container: container)
            let bannerContainer = LimitedTrustBannerContainerViewController(child: tabBar)
            bannerContainer.update(trustTier: container.session.trustTier)
            self.limitedTrustBannerContainer = bannerContainer
            self.rootViewController = bannerContainer
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
        // Phase 6 D6-10: observe `.trustTierDidChange` on this container's
        // `AppSession` so the role-shell limited-trust banner re-renders when a
        // heartbeat (D-12) or the first-login consumer mutates the tier
        // mid-session. Scoped to `container.session` as the notification
        // `object` so a sibling AppSession (a different scene / a dropped
        // container) cannot drive this coordinator's banner. The observer is
        // only meaningful for the `.role` phase — `limitedTrustBannerContainer`
        // is nil for every other phase, so the closure is a guarded no-op
        // there. `[weak self]` discipline matches the AuthCoordinator /
        // KYCCoordinator callback wiring above.
        if self.limitedTrustBannerContainer != nil {
            self.trustTierObserver = NotificationCenter.default.addObserver(
                forName: .trustTierDidChange,
                object: container.session,
                queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let bannerContainer = self.limitedTrustBannerContainer else { return }
                    let raw = note.userInfo?[AppSession.trustTierUserInfoKey] as? String
                    let newTier = raw.flatMap { TrustTier(rawValue: $0) } ?? .softwareOnly
                    // D6-10 / ADR 0002: re-render the banner with no animation,
                    // no root-swap — the container toggles the banner in place.
                    bannerContainer.update(trustTier: newTier)
                }
            }
        }
        container.logger.info(event: .init("app_coordinator_init"), fields: [.event: Self.phaseDescription(phase)])
    }

    deinit {
        // Phase 6 D6-10: drop the `.trustTierDidChange` observer so a
        // root-swapped (ARC-dropped) AppCoordinator stops observing.
        if let token = trustTierObserver {
            NotificationCenter.default.removeObserver(token)
        }
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
        // Phase 5 D-08: hand each role tab bar the composition-root KYC-status
        // factory so the modal `ProfileViewController` can open the KYC status
        // screen (the screen's second entry point). The closure weakly captures
        // `container` — the tab bar controller retains the closure, so a strong
        // capture would cycle the container alive past a role swap (ADR 0002).
        let kycStatusFactory: () -> UIViewController = { [weak container] in
            guard let container else { return UIViewController() }
            return container.makeKYCStatusScreen()
        }
        // Phase 8 LOAD-03 (T-08-11): the per-role Loads screen factory. Same
        // [weak container] capture discipline as kycStatusFactory above — a
        // strong capture would cycle the container alive past a role swap
        // (ADR 0002). The SAME closure instance is passed into every
        // *TabBarController; the role-specific routing happens inside each
        // tab bar's viewDidLoad() by invoking loadListScreenFactory?(self.role)
        // where self.role is the controller's stored `let role: Role` constant
        // (T-08-11 — each tab bar is the single source of truth for its own
        // role).
        let loadListFactory: (Role) -> UIViewController = { [weak container] role in
            guard let container else { return UIViewController() }
            return container.makeLoadListScreen(role: role)
        }
        switch role {
        case .shipper:
            return ShipperTabBarController(
                logoutService: container.logoutService,
                kycStatusScreenFactory: kycStatusFactory,
                loadListScreenFactory: loadListFactory
            )
        case .broker:
            return BrokerTabBarController(
                logoutService: container.logoutService,
                kycStatusScreenFactory: kycStatusFactory,
                loadListScreenFactory: loadListFactory
            )
        case .carrier:
            return CarrierTabBarController(
                logoutService: container.logoutService,
                kycStatusScreenFactory: kycStatusFactory,
                loadListScreenFactory: loadListFactory
            )
        case .dispatch:
            return DispatchTabBarController(
                logoutService: container.logoutService,
                kycStatusScreenFactory: kycStatusFactory,
                loadListScreenFactory: loadListFactory
            )
        case .factoring:
            return FactoringTabBarController(
                logoutService: container.logoutService,
                kycStatusScreenFactory: kycStatusFactory,
                loadListScreenFactory: loadListFactory
            )
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
