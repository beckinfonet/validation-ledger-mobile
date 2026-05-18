// validationLedger/App/SceneDelegate.swift
// UIKit scene lifecycle + root-swap mechanism (D-10 / ADR 0002).
// Also hosts the DEBUG-only shake responder that presents DevMenu (D-12).
//
// No SwiftUI in this file (ARCH-01).

import UIKit

public enum AppPhase {
    case launch
    case auth
    /// Phase 5 D-12: the KYC hard-gate phase. After OTP-verify a user whose
    /// `kycStatus != "verified"` is routed here (and on cold boot, a restored
    /// session with a non-verified cached `kycStatus` lands here). Produces a
    /// `KYCCoordinator`-driven capture flow; the role shell is unreachable until
    /// KYC is submitted.
    case kyc(Role)
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

    /// Phase 3 gap-closure (Plan 13) — observes UIApplication.didBecomeActiveNotification
    /// so SESS-02 (>5min background → biometric re-prompt) works on device. Stored as
    /// instance property so we can remove the observer on sceneDidDisconnect + deinit
    /// (mirrors the sessionInvalidateObserver / networkConfigObserver cleanup pattern).
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    /// Tracks the current AppPhase so didBecomeActive handler knows whether to re-check
    /// lockState (only meaningful when we're in .role(_) — .auth and .anotherActiveSession
    /// don't need a lock overlay). Updated in presentRoot(_:).
    private var currentPhase: AppPhase?

    /// Weak reference to the currently-presented BiometricLockViewController. Prevents
    /// stacking duplicate lock VCs if didBecomeActive fires while one is already on-screen
    /// (e.g. user backgrounds during biometric prompt, foregrounds again).
    private weak var presentedLockVC: BiometricLockViewController?

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

        // Phase 3 gap-closure (Plan 13) — SESS-02: >5min background → biometric re-prompt.
        // SessionLockService.lockState(now:) already tracks enteredBackgroundAt via its own
        // UIApplication.didEnterBackgroundNotification self-subscription (SessionLockService.swift
        // lines 62-83). This observer re-runs the SceneDelegate-level lockState check on
        // foreground — if now - enteredBackgroundAt > 5min, lockState returns .locked(.backgroundTimeout)
        // and we present BiometricLockViewController. The per-Scene observer stays alive for the
        // window's lifetime; removed in sceneDidDisconnect + deinit.
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidBecomeActive()
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
                // Phase 4 Plan 08 / Phase 6 Plan 03 (D-11 / D-12 / D6-01):
                // optional `-MockOTPTrustTierForUITest` launchArg selects the
                // trust tier returned in the mocked /device/register response's
                // `trust_tier` field. Phase 6 Plan 02 wired OTPViewModel STEP 5
                // to consume that response and persist `trustTier` to Keychain,
                // and Plan 03's AppContainer seeds AppSession.trustTier from
                // that Keychain item — so the fixture path now drives the REAL
                // consumer end-to-end. The prior DEBUG trust-tier static
                // override seam is deleted (D6-03 / 06-RESEARCH Pitfall 6); the
                // launchArg lives on. Default to `.hardwareAttested` so
                // existing Phase 3 RoleShellSmokeTests keep their banner-absent
                // expectations.
                let uiTestTrustTier: TrustTier = {
                    guard let ttIdx = ProcessInfo.processInfo.arguments.firstIndex(of: "-MockOTPTrustTierForUITest"),
                          ttIdx + 1 < ProcessInfo.processInfo.arguments.count,
                          let tier = TrustTier(rawValue: ProcessInfo.processInfo.arguments[ttIdx + 1])
                    else { return .hardwareAttested }
                    return tier
                }()
                // 1. Register fixtures — OTPRequest + OTPVerify(role) + DeviceRegister
                //    (Phase 4 D-12: fixture `trust_tier` mirrors uiTestTrustTier)
                MockOTPRoleFixtureRegistry.registerForRole(role, trustTier: uiTestTrustTier)
                // 2. Inject stubbed location + country gate (Warning 4). The
                //    trustTier no longer needs an override seam — the fixture
                //    `/device/register` response's `trust_tier` (registered in
                //    step 1) flows through the real OTPViewModel -> Keychain ->
                //    AppContainer seed consumer (06-03 D6-01).
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

        // Phase 5 Plan 11 (SC-2 / D-08 / D-12 / Test-10): the `-KYCTestSeedForUITest`
        // launch-argument seam. The plan 05-12 device XCUITests must arrive at
        // three specific KYC states deterministically; an XCUITest driver runs in
        // a separate process and can only cross into the app via launch arguments.
        //
        // Sequence on `-KYCTestSeedForUITest <mode>` detection:
        //   1. Force `.mock` NetworkConfig so MockURLProtocol intercepts the
        //      `GET /kyc/status` + KYC upload routes (the plan 05-09 mock fixtures
        //      already serve these).
        //   2. Set `AppContainer.kycTestSeed` to the matching `KYCUITestSeed` case.
        //   3. Construct ONE throwaway `AppContainer` to TRIGGER the DEBUG seeding
        //      side-effect: `AppContainer.init` reads `kycTestSeed` and seeds the
        //      Keychain `session`-scope state (and, for `.midUpload`, the on-disk
        //      `KYCSessionStore`). This mirrors the `-MockOTPRoleForUITest`
        //      throwaway-`scrubContainer` discipline above — `AppContainer` owns
        //      the `KeychainStore` + `KYCSessionStore`, so the seam runs in init.
        //
        // DELIBERATE difference from `-MockOTPRoleForUITest`: this block does NOT
        // call `presentRoot` and does NOT `return` early. It only SEEDS state,
        // then falls through to the existing `SessionRestoreProbe.probe` switch
        // below so the seeded Keychain state drives the REAL routing decision:
        //   nonVerified → probe `.needsKYC` → presentRoot(.kyc(role))
        //   underReview / midUpload → probe `.restored` → presentRoot(.role(role))
        // (`-MockOTPRoleForUITest` returns early because it drives the auth flow
        // from scratch; this seam instead exercises the genuine restore path.)
        //
        // Entire block is `#if DEBUG` — Release compiles it to zero bytes
        // (threat T-05-11-01).
        #if DEBUG
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KYCTestSeedForUITest"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            let mode = ProcessInfo.processInfo.arguments[idx + 1]
            let seed: AppContainer.KYCUITestSeed?
            switch mode {
            case "nonVerified": seed = .nonVerified
            case "underReview": seed = .underReview
            case "midUpload":   seed = .midUpload
            default:            seed = nil
            }
            if let seed {
                // 1. Force .mock so MockURLProtocol serves the KYC routes.
                self.currentNetworkConfigOverride = .mock
                // 2. Set the seed the AppContainer init-time block consumes.
                AppContainer.kycTestSeed = seed
                // 3. Throwaway container TRIGGERS the DEBUG seeding side-effect
                //    BEFORE the probe runs (mirrors -MockOTPRoleForUITest's
                //    scrubContainer). We discard it; presentRoot below builds a
                //    fresh, fully-wired container for the probed phase per ADR 0002.
                _ = AppContainer(env: .current, networkConfig: .mock)
                // NO presentRoot, NO return — fall through to the probe switch so
                // the seeded Keychain state drives the genuine routing decision.
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
            // Phase 3 gap-closure (Plan 13): pass checkLockState: true ONLY on the
            // genuine cold-boot restore path. This is the exact moment SESS-01
            // requires a biometric gate before tab content is interactive.
            // Post-OTP verify, DevMenu role-swap, and NetworkConfig toggle all use
            // the no-flag overload which passes checkLockState: false.
            presentRoot(.role(role), checkLockState: true)
            // Phase 4 D-07 cold-boot heartbeat. Fire-and-forget — does not block role-shell
            // render. Biometric lock (Plan 13) presents above via checkLockState: true; the
            // heartbeat runs concurrently in the background. If biometric denies, the user
            // re-auths, the heartbeat may land on a dead session, and the existing
            // Auth401ResponseInterceptor (Phase 3) handles the 401 via LogoutService.
            // performHeartbeatIfNeeded reads the AppContainer constructed by presentRoot —
            // `self.appCoordinator?.container` is non-nil here because presentRoot wires it.
            if let container = self.appCoordinator?.container {
                Task { @MainActor in
                    await self.performHeartbeatIfNeeded(container: container)
                }
            }
        case .needsKYC(let role):
            // Phase 5 D-12/D-13: a restored session whose cached `kycStatus` is not
            // "verified" routes into the KYC hard gate. No biometric lock overlay —
            // the KYC capture flow has its own D-14 sign-out affordance, and the
            // role shell is not constructed at all until KYC is submitted.
            presentRoot(.kyc(role))
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
        if let token = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
            appDidBecomeActiveObserver = nil
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
        if let token = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
        }
        #if DEBUG
        if let token = networkConfigObserver {
            NotificationCenter.default.removeObserver(token)
        }
        #endif
    }

    // MARK: - Phase 5 Plan 07 (UPL-05) — background upload continuation

    /// Phase 5 UPL-05: when the app backgrounds with at least one incomplete KYC
    /// upload, submit a `BGProcessingTaskRequest` so the OS grants runtime to keep
    /// the foreground chunk loop alive (RATIFIED USER DECISION — foreground loop +
    /// BGTask, NOT a file-based background URLSession).
    ///
    /// The pending-upload check reads the SCENE AppContainer's `KYCSessionStore`
    /// (`loadSession()` — a non-committed artifact means an upload is in flight)
    /// and the scheduling uses that scene container's `KYCUploadScheduler`. No new
    /// `AppContainer` is constructed anywhere (threat T-05-07-06).
    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let container = appCoordinator?.container else { return }
        // A non-committed artifact in the on-disk session = an upload still owes
        // chunks. An absent session / a fully-committed session = nothing pending.
        let hasPendingUploads: Bool
        if let session = try? container.kycSessionStore.loadSession() {
            hasPendingUploads = session.uploadStates.values.contains { !$0.committed }
        } else {
            hasPendingUploads = false
        }
        container.kycUploadScheduler.scheduleUploadContinuation(
            hasPendingUploads: hasPendingUploads
        )
    }

    // MARK: - Deep-link forwarding

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            appCoordinator?.container.deepLinkRouter.receive(context.url)
        }
    }

    // MARK: - Root-swap mechanism (D-10 / ADR 0002)

    /// Default entry point — used by post-auth coordinator callbacks, DevMenu RoleSwitcher,
    /// and NetworkConfig toggle. These callers JUST authenticated (OTP verify step 6 recorded
    /// a biometric success) OR are DEBUG-only developer paths; they do NOT want the biometric
    /// lock overlay on top of the fresh role shell.
    ///
    /// The cold-boot path in `scene(_:willConnectTo:)` uses `presentRoot(_:checkLockState:)`
    /// with `checkLockState: true` to drive the SESS-01 biometric gate on process-launch
    /// session restore only.
    func presentRoot(_ phase: AppPhase) {
        presentRoot(phase, checkLockState: false)
    }

    /// Cold-boot-aware entry. `checkLockState: true` is passed ONLY from the SessionRestoreProbe
    /// .restored branch in `scene(_:willConnectTo:)` — that is the exact moment the app is
    /// resuming a persisted session on process launch and SESS-01 requires biometric unlock
    /// before tab content is interactive. All other callers pass `false` (or use the no-flag
    /// overload above), because their SessionLockService is a fresh-in-this-process instance
    /// whose `lastSuccess == nil` would otherwise always trip `.locked(.coldBoot)` and stack
    /// a lock VC that blocks the role shell immediately after OTP verify or DevMenu role-swap.
    func presentRoot(_ phase: AppPhase, checkLockState: Bool) {
        // Fresh container + fresh coordinator per D-10.
        // In DEBUG, respect the DevMenu NetworkConfig override (NET-03 SC-2 demonstrator)
        // so toggling mock/live persists across subsequent role swaps.
        //
        // Phase 5 Plan 07 (UPL-05): pass the AppDelegate-owned `KYCUploadScheduler`
        // into every AppContainer — the BGTask handler is registered on THAT
        // scheduler at launch, so its live-uploader slot (filled below) must be
        // the same instance every scene container sees.
        let scheduler = (UIApplication.shared.delegate as? AppDelegate)?.kycUploadScheduler
        #if DEBUG
        let container = AppContainer(
            env: .current,
            networkConfig: currentNetworkConfigOverride,
            kycUploadScheduler: scheduler
        )
        #else
        let container = AppContainer(env: .current, kycUploadScheduler: scheduler)
        #endif

        // UPL-05: hand the scheduler this scene container's `kycUploader` so the
        // BGTask handler resumes THIS container's foreground chunk loop. The
        // handler captures this uploader via the scheduler's live-uploader slot —
        // it never constructs a fresh AppContainer (threat T-05-07-06).
        container.kycUploadScheduler.setLiveUploader(container.kycUploader)

        let coordinator = AppCoordinator(container: container, phase: phase)

        // Wire callbacks that can trigger re-routing in Phase 3+.
        // onRoleResolved fires post-OTP verify — the user just authenticated, so we do NOT
        // want the lock overlay on top of the fresh role shell (uses no-flag overload which
        // passes checkLockState: false).
        coordinator.onRoleResolved = { [weak self] role in
            self?.presentRoot(.role(role))
        }
        coordinator.onLogout = { [weak self] in
            self?.presentRoot(.auth)   // Phase 3 replaces with real phone-entry screen
        }
        // Phase 5 D-12: a not-yet-KYC-verified user (post-OTP-verify) root-swaps
        // into the `.kyc` hard gate. The role shell is unreachable until the
        // KYCCoordinator's `onKYCSubmitted` fires `onRoleResolved`.
        coordinator.onKYCRequired = { [weak self] role in
            self?.presentRoot(.kyc(role))
        }

        self.appCoordinator = coordinator                       // single strong reference
        self.window?.rootViewController = coordinator.rootViewController
        // Previous coordinator tree orphaned; ARC deallocates on next runloop.
        // Abrupt replace — no animation (D-10 mandate).

        // Signal the DeepLinkRouter that bootstrap is complete — pending links drain now.
        container.deepLinkRouter.bootstrapComplete()

        // Phase 3 gap-closure (Plan 13): track the phase so didBecomeActive knows whether
        // to re-check lockState. Lock overlay is only meaningful on .role — .auth and
        // .anotherActiveSession do not present a lock VC (the user must auth fresh anyway).
        self.currentPhase = phase

        // Phase 3 gap-closure (Plan 13) — SESS-01/SESS-03: on cold-boot restore to .role,
        // check lockState and present BiometricLockViewController if locked. This closes
        // 03-VERIFICATION.md gap 1 — prior to this plan, BiometricLockViewController had
        // zero construction sites anywhere in the app, making SC-2/SC-3 unachievable.
        //
        // Guarded by `checkLockState` so post-OTP / DevMenu / NetworkConfig re-presents do NOT
        // trip the lock overlay with a fresh-process SessionLockService whose lastSuccess == nil.
        if checkLockState, case .role = phase {
            presentBiometricLockIfNeeded(container: container, over: coordinator.rootViewController)
        }
    }

    // MARK: - Biometric lock overlay (Phase 3 gap-closure Plan 13 — D-13/D-14/D-15)

    /// Checks container.sessionLock.lockState(now:) and — when locked — constructs
    /// BiometricLockViewController(reason:biometric:sessionLock:onUnlockSuccess:onReBindRequested:)
    /// and presents it modally (.fullScreen) over the role VC. No-op when lockState is
    /// .unlocked. No-op when a lock VC is already presented (prevents stacking duplicates
    /// if didBecomeActive fires during an active biometric prompt).
    ///
    /// Called from:
    ///   - presentRoot(_:) on cold-boot .role path — covers SESS-01 (.coldBoot reason)
    ///   - handleDidBecomeActive() on foreground — covers SESS-02 (.backgroundTimeout)
    ///
    /// onReBindRequested (SESS-03 M1 placeholder): routes through LogoutService.logout(.userInitiated)
    /// which already funnels through the existing .sessionDidInvalidate observer
    /// (lines 72-86) and root-swaps to .auth. Future phases replace this with a proper
    /// device re-bind UI; for M1 the "re-bind" is a forced re-auth.
    private func presentBiometricLockIfNeeded(container: AppContainer, over presenter: UIViewController) {
        #if DEBUG
        // Phase 5 Plan 11 device-XCUITest seam. A `-KYCTestSeedForUITest` launch seeds a
        // synthetic session and falls through to the genuine cold-boot `.role` restore
        // path — which presents BiometricLockViewController and invokes LAContext / Face ID
        // (SESS-01). A headless XCUITest driver on a real device cannot satisfy that Face ID
        // prompt; the `com.apple.localauthentication` system alert then blocks every KYC
        // XCUITest that reaches the role shell (KYCProfileEntryUITests, KYCForceQuitResumeUITests).
        // Suppress the cold-boot lock when the seam is active. DEBUG-only — Release compiles
        // this to zero bytes and the production cold-boot biometric lock is unaffected
        // (consistent with threat T-05-11-01: the entire seam is `#if DEBUG`).
        if ProcessInfo.processInfo.arguments.contains("-KYCTestSeedForUITest") { return }
        #endif

        // Idempotency: if a lock VC is already up, don't stack another one.
        if presentedLockVC != nil { return }

        let state = container.sessionLock.lockState(now: .now)
        guard case .locked(let reason) = state else { return }

        let lockVC = BiometricLockViewController(
            reason: reason,
            biometric: container.biometricService,
            sessionLock: container.sessionLock,
            onUnlockSuccess: { [weak self] in
                // Dismiss with animated: false per RESEARCH §iOS API #6 line 910 —
                // no reveal animation, tighter security posture.
                self?.presentedLockVC?.dismiss(animated: false)
                self?.presentedLockVC = nil
            },
            onReBindRequested: { [weak self, weak container] in
                // SESS-03 M1 placeholder per 03-CONTEXT.md / 03-VERIFICATION.md gap 1 "missing" item 3.
                // Forced re-auth: logoutService.logout(.userInitiated) wipes Keychain + SE auth key +
                // sessionLock.invalidate() + posts .sessionDidInvalidate. SceneDelegate's existing
                // .sessionDidInvalidate observer (lines 72-86) root-swaps to .auth. From the user's
                // perspective they see the lock VC dismiss → phone-entry appears.
                guard let container else { return }
                Task { @MainActor in
                    await container.logoutService.logout(reason: .userInitiated)
                    // Note: no explicit dismiss here — the .sessionDidInvalidate observer
                    // triggers presentRoot(.auth), which ARC-drops the current coordinator
                    // tree (including the presented lock VC) per ADR 0002.
                    self?.presentedLockVC = nil
                }
            }
        )

        // The VC already sets modalPresentationStyle = .fullScreen + accessibilityViewIsModal = true
        // in its init (BiometricLockViewController.swift lines 44-47) — do not override here.
        self.presentedLockVC = lockVC
        presenter.present(lockVC, animated: false)
    }

    /// Handler for UIApplication.didBecomeActiveNotification — re-runs the lockState
    /// check only when the current phase is .role(_). On .auth or .anotherActiveSession,
    /// a lock overlay is meaningless (the user has not authenticated or is on a terminal
    /// support screen respectively).
    ///
    /// Phase 4 D-07: after the biometric-lock check, fires the 24h heartbeat probe.
    /// performHeartbeatIfNeeded gates internally on the 86400s threshold so it is safe
    /// to call on every didBecomeActive — the helper returns early when lastHeartbeatAt
    /// is fresh. Fire-and-forget: heartbeat errors do NOT block role-shell interaction.
    private func handleDidBecomeActive() {
        guard case .role = currentPhase else { return }
        guard let container = appCoordinator?.container else { return }
        guard let rootVC = window?.rootViewController else { return }
        presentBiometricLockIfNeeded(container: container, over: rootVC)
        // Phase 4 D-07: 24h heartbeat check runs AFTER biometric-lock check.
        // The helper is @MainActor and performs its own threshold gating.
        Task { @MainActor in
            await self.performHeartbeatIfNeeded(container: container)
        }
    }

    // MARK: - Phase 4 D-07 heartbeat helper (cold-boot + 24h warm-foreground)

    /// Phase 4 D-07 heartbeat helper. Fire-and-forget: a failed heartbeat does NOT block
    /// role-shell render. Errors log at .error level with safe fields only (event name +
    /// .count rawValue); attestationObject / attestedKeyId bytes NEVER enter Logger fields
    /// (FOUND-01 PII discipline — 04-PATTERNS.md Pattern A).
    ///
    /// Invocation sites (D-07):
    ///   1. scene(_:willConnectTo:) .restored branch — cold-boot heartbeat
    ///   2. handleDidBecomeActive — warm-foreground 24h check
    ///
    /// 24h threshold: reads AttestedKeyStore.readLastHeartbeatAt(); if nil or older
    /// than 86400s (24h), fires heartbeat. On success, updates container.session.trustTier
    /// (D-12) and persists lastHeartbeatAt via AttestedKeyStore.writeLastHeartbeatAt.
    ///
    /// Stale-session edge case (RESEARCH Pitfall 6): if the session token is server-stale,
    /// the heartbeat POST returns 401 → existing Auth401ResponseInterceptor triggers
    /// LogoutService.logout(.auth401). This is NORMAL; heartbeat serves dual duty as
    /// session validity probe.
    @MainActor
    private func performHeartbeatIfNeeded(container: AppContainer) async {
        let attestedKeyStore = AttestedKeyStore(keychain: container.keychainStore)

        // 24h threshold check — 86400s = 24 hours.
        do {
            if let last = try attestedKeyStore.readLastHeartbeatAt(),
               Date().timeIntervalSince(last) < 86400 {
                return  // Heartbeat is fresh; nothing to do.
            }
        } catch {
            container.logger.error(
                event: .init("attestation_heartbeat_read_last_failed"),
                fields: [:]
            )
            // Fall through — err on the side of heartbeating if we cannot read state.
        }

        do {
            // Ensure we have an attested key (D-01: idempotent; returns existing on hit).
            let (keyId, status) = try await container.attestationService.generateKeyIfNeeded()
            guard status == .attested || status == .simulatorBypass else {
                // No usable key — backend already routed to .softwareOnly; skip heartbeat.
                container.logger.warn(
                    event: .init("attestation_heartbeat_skipped_no_key"),
                    fields: [.event: status.rawValue]
                )
                return
            }

            // Fetch challenge (D-05). base64-decode to raw bytes for D-06 SHA-256.
            let challengeResponse = try await container.apiClient.request(DeviceChallengeEndpoint())
            guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else {
                container.logger.error(
                    event: .init("attestation_heartbeat_bad_challenge"),
                    fields: [:]
                )
                return
            }

            // Generate assertion (D-07 — SHA-256(challenge) inside the service).
            let assertion = try await container.attestationService.generateAssertion(
                keyId: keyId,
                challenge: challengeData
            )

            // Read session token from Keychain (existing Phase 3 pattern).
            let sessionTokenData = try container.keychainStore.get(.sessionToken)
            guard let sessionToken = String(data: sessionTokenData, encoding: .utf8) else {
                container.logger.error(
                    event: .init("attestation_heartbeat_no_session_token"),
                    fields: [:]
                )
                return
            }

            // POST /device/heartbeat.
            let heartbeatResponse = try await container.apiClient.request(DeviceHeartbeatEndpoint(
                sessionToken: sessionToken,
                attestedKeyId: keyId,
                assertion: assertion
            ))

            // D-12: update trustTier from response + persist lastHeartbeatAt (D-07).
            container.session.trustTier = heartbeatResponse.trustTier
            try attestedKeyStore.writeLastHeartbeatAt(heartbeatResponse.heartbeatAcceptedAt)

            container.logger.info(
                event: .init("attestation_heartbeat_ok"),
                fields: [.event: heartbeatResponse.trustTier.rawValue]
            )
        } catch {
            // Silent-fail: do not block role-shell render. Backend will drive re-attest
            // on next /device/register if trustTier demands it. 401 errors on /device/heartbeat
            // are handled by the existing Auth401ResponseInterceptor (Phase 3 D-28).
            //
            // PII discipline: do NOT include error.userInfo or .localizedDescription — those
            // may contain diagnostic bytes. Only the event name carries context.
            container.logger.error(
                event: .init("attestation_heartbeat_failed"),
                fields: [:]
            )
        }
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
