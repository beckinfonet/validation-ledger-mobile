---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 11
subsystem: app-composition-root-role-shell-wiring
tags:
  - ios
  - composition-root
  - scenedelegate
  - appcontainer
  - appcoordinator
  - role-shell
  - avatar-affordance
  - wave-4
  - shell-01
  - shell-02
  - shell-03
  - shell-04
  - sess-01
  - dev-06
  - d-01
  - d-03
  - d-04
  - d-05
  - d-16
  - d-18
  - d-28

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 06
    provides: "BiometricService + SessionLockService + SessionRestoreService protocols + DefaultSessionLockService(biometric:keychain:notificationCenter:) signature (UIApplication observer self-subscription) consumed by AppContainer init order"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 07
    provides: "LogoutService protocol + DefaultLogoutService(keychain:keyStore:sessionLock:logger:notificationCenter:) + SensitiveActionService + Auth401ResponseInterceptor(logoutService:) — all wired into AppContainer + APIClient responseInterceptors chain"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 08
    provides: "LocationProvider + CountryGate defaults — already constructed in Phase 3 Plan 09 AppContainer extension; Plan 11 confirms canonical placement as stored init properties"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 09
    provides: "AuthCoordinator(container:) + onAuthenticated(role:) callback — AppCoordinator makeRoot(.auth) now constructs and retains this coordinator"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 10
    provides: "ProfileViewController(logoutService:) + AnotherActiveSessionViewController(supportEmail:) — both referenced by the Plan 11 avatar affordance and AppCoordinator .anotherActiveSession case respectively"

provides:
  - "AppPhase.anotherActiveSession case — D-18 / DEV-06 root-swap target for LogoutReason.anotherActiveSession"
  - "AppContainer.sessionRestore / .sensitiveAction / .logoutService stored properties (ARCH-04 initializer-DI); 6 Phase 3 services now constructed in canonical dependency order (biometricService → sessionLock → sessionRestore → locationProvider+countryGate → sensitiveAction → logoutService → apiClient)"
  - "Auth401ResponseInterceptor wired alongside RetryInterceptor in APIClient.responseInterceptors — HTTP 401 on non-OTP paths funnels through LogoutService.logout(.auth401) per D-28"
  - "SessionRestoreProbe.probe(env:) static helper (Blocker 6 fix) — lightweight cold-boot probe that constructs only KeychainStore + DefaultSessionRestoreService; does NOT instantiate DefaultSessionLockService, DefaultBiometricService, DefaultLocationProvider, or DefaultCountryGate. Discarding the helper therefore does NOT leak the UIApplication.didEnterBackgroundNotification observer that SessionLockService subscribes to per D-08."
  - "SceneDelegate cold-boot routing: replaced Phase 1 hardcoded presentRoot(.role(.shipper)) with SessionRestoreProbe-driven switch (.restored(role) → .role(role), .needsAuth → .auth) per D-04/D-05"
  - "SceneDelegate .sessionDidInvalidate observer — maps LogoutReason rawValue carried in userInfo[LogoutReasonKey] to the correct AppPhase: .userInitiated/.auth401 → .auth; .anotherActiveSession → .anotherActiveSession. Observer token tracked as instance property; removed in sceneDidDisconnect + deinit (mirrors Phase 1 networkConfigObserver pattern)."
  - "AppCoordinator.makeRoot now fills all 4 AppPhase cases: .launch → ShipperTabBarController (Phase 1 preserve); .auth → AuthCoordinator (retained via instance property so its nav stays live); .role(role) → role-specific TabBarController constructed with container.logoutService; .anotherActiveSession → AnotherActiveSessionViewController(supportEmail:)"
  - "5 role TabBarControllers — init(logoutService:) accepts the injected LogoutService; viewDidLoad calls wrapTabsWithNavAndInstallAvatar after setting tab inventory; the injected service reaches ProfileViewController when the user taps the avatar"
  - "RoleCoordinator extension: wrapTabsWithNavAndInstallAvatar(presenter:) where Self: UITabBarController — DRY helper that wraps each tab in a UINavigationController and installs an avatar UIBarButtonItem with fixed accessibilityIdentifier 'nav-avatar'. Tap fires the presenter closure and presents the result modally in a form-sheet nav. All 5 role shells call this helper so the Profile affordance is consistent by construction."

affects:
  - "03-12 (UI smoke tests upgrade) — Plan 11 ships the composition-root wiring Plan 12 needs: the 'nav-avatar' accessibilityIdentifier is present on all 5 role shells; ProfileViewController is modally reachable with the 'profile-logout' identifier (Plan 10); SceneDelegate already routes .auth / .role / .anotherActiveSession. Plan 12 adds the -MockOTPRoleForUITest launch-arg + MockOTPRoleFixtureRegistry on top of this base."
  - "RoleCoordinatorTests (pre-existing Phase 1 unit test) — auto-fixed to pass the new init(logoutService:) via a file-scoped NoOpLogoutService stub (Rule 3: directly caused by this plan's signature change)."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Initializer-DI dependency graph for the composition root (ARCH-04): AppContainer constructs 9 service instances in a single init pass with explicit dependency order — biometricService → sessionLock → sessionRestore → (locationProvider, countryGate) → sensitiveAction → logoutService → apiClient. logoutService MUST precede apiClient so Auth401ResponseInterceptor can capture it by closure."
    - "Lightweight probe helper as an alternative to full composition-root construction (Blocker 6): SceneDelegate's cold-boot path calls SessionRestoreProbe.probe(env:) which instantiates ONLY KeychainStore + DefaultSessionRestoreService. This avoids constructing DefaultSessionLockService (which subscribes to UIApplication.didEnterBackgroundNotification per D-08 and whose observer tokens would leak when the probe helper is discarded). presentRoot then builds the real full-shape AppContainer fresh per ADR 0002, and the full container's observers live for the window's rootViewController lifetime — no leak."
    - "Root-swap-on-notification pattern (D-18): LogoutService posts .sessionDidInvalidate as the LAST step of its 6-step teardown (Pitfall 3). SceneDelegate observes on the main queue, maps LogoutReason rawValue → AppPhase, calls presentRoot. This keeps the teardown → re-present handoff race-free because the observer fires only after all Keychain/SE/SessionLock wiping is complete."
    - "AppCoordinator instance retention of sub-coordinator (D-01): AppCoordinator stores the AuthCoordinator as a private var property. UINavigationController is retained by window.rootViewController, but the AuthCoordinator owns closures (onAuthenticated) + push plumbing (pushOTP) — without a strong reference the coordinator deallocates immediately after makeRoot returns. The instance-property retention ties its lifetime to the current AppCoordinator (which SceneDelegate retains)."
    - "Shared protocol-extension affordance helper (D-03): `extension RoleCoordinator where Self: UITabBarController { func wrapTabsWithNavAndInstallAvatar }` lets all 5 role subclasses share the avatar-wiring in ~5 lines of caller code each. UIAction(handler:) is used instead of @objc selector since the receivers are placeholder UIViewControllers (no custom subclass to host the selector); iOS 14+ primaryAction is the clean path for closure-based bar button items."
    - "Swift Testing source-level structural assertions with constructor-pattern matching (Plan 11 test fix): the SessionRestoreProbe 'Blocker 6 lightweight' test scans for constructor patterns (`DefaultSessionLockService(`) rather than bare type names. The probe's explanatory comments deliberately name the services it must NOT construct, which would cause false-positive matches on bare-name substring scans."

key-files:
  created:
    - validationLedger/Core/Auth/SessionRestoreProbe.swift
  modified:
    - validationLedger/App/AppContainer.swift
    - validationLedger/App/AppCoordinator.swift
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/Roles/RoleCoordinator.swift
    - validationLedger/Roles/Shipper/ShipperTabBarController.swift
    - validationLedger/Roles/Broker/BrokerTabBarController.swift
    - validationLedger/Roles/Carrier/CarrierTabBarController.swift
    - validationLedger/Roles/Dispatch/DispatchTabBarController.swift
    - validationLedger/Roles/Factoring/FactoringTabBarController.swift
    - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
    - validationLedgerTests/Roles/RoleCoordinatorTests.swift
  deleted: []

decisions:
  - "Coordinator retention strategy for .auth — selected option (2) from the plan's three alternatives (static-holder / instance-property / notification-bubble). The plan initially favored option 3 (Notification.Name.authResolved), but closer inspection of the Plan 09 AuthCoordinator API showed it already exposes an `onAuthenticated: ((Role) -> Void)?` closure callback. Storing AuthCoordinator as a `private var authCoordinator` on AppCoordinator and forwarding onAuthenticated → onRoleResolved is simpler than adding a second notification channel. The SceneDelegate.onRoleResolved wiring (Phase 1) remains the single re-present trigger point; we don't introduce a parallel .authResolved notification."
  - "@MainActor on AppCoordinator — the AuthCoordinator is @MainActor (Plan 09), and AppCoordinator now constructs it directly plus calls `onAuthenticated = ...` on a MainActor-isolated property. Annotating the whole AppCoordinator class with @MainActor closes the Swift-concurrency hygiene gap. Existing SceneDelegate call sites were already MainActor-isolated (SceneDelegate conforms to UIWindowSceneDelegate on MainActor); no caller needed to change."
  - "SessionRestoreProbe uses a NoOpProbeLogger rather than OSLogLoggerImpl — the probe's one log line is re-emitted by the real AppContainer's logger on the next (real) service call, so suppressing it in the probe has no observability cost. This keeps the helper's import surface minimal (Foundation only; no OSLog) and makes the 'lightweight' property easier to enforce with structural tests."
  - "Tab inventory unchanged — SHELL-02 contract mandates the 5 inventories match TechStack.md §4 verbatim. Phase 1 already matched; Plan 11 only adds the nav-wrap + avatar on top, leaving the tab titles and icons bit-identical. Phase 1 RoleShellSmokeTests still pass because they target tab-bar buttons by title (which the nav-wrap does not change)."
  - "Preserved back-compat with -ForceRoleForUITest (Phase 1 launch arg) rather than removing it. Plan 12 will add -MockOTPRoleForUITest alongside (not replacing) per D-32 and 03-RESEARCH.md Open Q1. Keeping both paths means Phase 1 RoleShellSmokeTests continue to pass while Plan 12 lands the upgraded smoke tests."

# Performance metrics
metrics:
  duration_hours: ~2
  date_completed: 2026-04-21
  tasks_completed: 2
  tests_added: 10
  tests_total_green: "full validationLedgerTests + RoleShellSmokeTests suites green"
---

# Phase 3 Plan 11: Composition Root + Role Shell Wiring Summary

Land the composition root that turns the Plans 06–10 services + UI into a working app. After this plan: SceneDelegate cold-boot probe routes to `.auth` or `.role(role)` based on Keychain state; successful auth lands on the role shell with an avatar affordance; tap avatar → ProfileVC → tap "Log out" → LogoutService.logout(.userInitiated) → SceneDelegate observer roots-swap to `.auth`. Wave 4 of 6 now complete. Plan 12 (UI smoke tests) can drive the end-to-end flow per SC-1.

## What shipped

**Composition root (Task 1):**
- `AppContainer` gained 3 new stored properties (`sessionRestore`, `sensitiveAction`, `logoutService`) on top of the Phase 2 surface + Phase 3 Plan 09 `locationProvider`/`countryGate`. 9 services constructed in explicit dependency order; `logoutService` precedes `apiClient` so `Auth401ResponseInterceptor(logoutService:)` can be appended to `responseInterceptors` alongside `RetryInterceptor()`.
- `SessionRestoreProbe.probe(env:)` — Blocker 6 fix. Lightweight helper; constructs only KeychainStore + DefaultSessionRestoreService; NOT DefaultSessionLockService / DefaultBiometricService / DefaultLocationProvider / DefaultCountryGate. Called from SceneDelegate before first presentRoot so we don't leak UIApplication observer tokens by discarding a temp full AppContainer.
- `SceneDelegate.scene(_:willConnectTo:)` — Phase 1's hardcoded `presentRoot(.role(.shipper))` replaced with SessionRestoreProbe-driven switch; `.sessionDidInvalidate` observer added that maps LogoutReason → AppPhase.
- `AppPhase` gained `.anotherActiveSession` case (D-18).
- `AppCoordinator.makeRoot` switched from private static to inline switch inside the initializer so AuthCoordinator retention (as instance property) can happen before self is fully formed; now fills all 4 AppPhase cases.
- `roleCoordinator(for:container:)` promoted to pass `container.logoutService` into each role TabBarController init.

**Role shell avatar affordance (Task 2):**
- `wrapTabsWithNavAndInstallAvatar(presenter:)` extension on `RoleCoordinator where Self: UITabBarController` — shared helper that wraps each tab in a UINavigationController and installs a "person.crop.circle" UIBarButtonItem with accessibilityIdentifier "nav-avatar". Tap fires the presenter closure and presents its result modally.
- All 5 role TabBarControllers call the helper from viewDidLoad after setting their TechStack §4 tab inventory (tabs unchanged).
- Presenter closure constructs `ProfileViewController(logoutService: self.logoutService)` (Plan 10 view) — the funnel is: avatar tap → Profile modal → Log out → LogoutService.logout(.userInitiated) → .sessionDidInvalidate → SceneDelegate root-swap to .auth.

## Tests

Added 10 Swift-Testing tests in `AppCoordinatorPhase3RoutingTests`:
1. `appPhaseCases` — compile-time exhaustiveness for all 4 AppPhase cases.
2. `containerHasPhase3Services` — all 6 typed services exist on AppContainer.
3. `auth401InterceptorWired` — source contains `Auth401ResponseInterceptor` + `RetryInterceptor`.
4. `sceneDelegateObserves` — SceneDelegate uses SessionRestoreProbe + observes .sessionDidInvalidate + probe block does NOT construct AppContainer (Blocker 6).
5. `appCoordinatorHandlesPhase3Cases` — AppCoordinator source references AuthCoordinator + AnotherActiveSessionViewController.
6. `makeRootAnotherActiveSession` — runtime: returns AnotherActiveSessionViewController.
7. `makeRootAuth` — runtime: returns a UINavigationController (AuthCoordinator's root).
8. `makeRootRole` — runtime: returns CarrierTabBarController for `.role(.carrier)`.
9. `sessionRestoreProbeIsLightweight` — structural: probe source uses constructor patterns matching only the permitted types.
10. `sessionRestoreProbeRuns` — runtime: probe returns a valid SessionRestoreResult without crashing.

Updated `RoleCoordinatorTests` (6 Phase 1 tests) to pass a file-scoped `NoOpLogoutService` stub through the new `init(logoutService:)` signature — blocking auto-fix (Rule 3) directly caused by Plan 11's TabBarController signature change.

Phase 1 `RoleShellSmokeTests` (XCUITests, 5 tests) still pass — they target tab-bar buttons by title, which the nav-wrap does not change.

Full regression: `xcodebuild test -only-testing:validationLedgerTests -only-testing:validationLedgerUITests/RoleShellSmokeTests` — `** TEST SUCCEEDED **`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] `RoleCoordinatorTests` broken by new `init(logoutService:)` signature**
- **Found during:** Task 1 build verification.
- **Issue:** Pre-existing Phase 1 unit tests constructed `ShipperTabBarController()`/etc. with the no-arg init that Plan 11 replaced.
- **Fix:** Added a file-scoped `NoOpLogoutService` stub conforming to `LogoutService` with an empty `logout(reason:)` body; updated each test site to pass `stubLogout()`. Also tightened the type annotation on `titles` (`[String?]`) to satisfy Swift Testing's `#expect` comparison when the UIKit optional-chain inference picks up SwiftUI's `Optional.map` in scope.
- **Files modified:** `validationLedgerTests/Roles/RoleCoordinatorTests.swift`
- **Commit:** `ed608e6`

**2. [Rule 3 — Blocking] Test suite substring-match false positive on probe's explanatory comments**
- **Found during:** First Task 1 test run.
- **Issue:** The initial `sessionRestoreProbeIsLightweight` test asserted `!source.contains("DefaultSessionLockService")` — but the probe's top-of-file comment INTENTIONALLY names the services it must not construct (for engineer clarity). Bare-name substring match tripped on the comment and reported 3 false-positive failures.
- **Fix:** Tightened the assertions to match CONSTRUCTOR patterns (e.g. `DefaultSessionLockService(` with open paren). A comment mention no longer matches; a real instantiation does.
- **Files modified:** `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift`
- **Commit:** `ed608e6` (included in the GREEN task commit since this was a test-refinement discovered mid-cycle).

### Design Decisions Made During Execution

**Coordinator retention (D-01) — selected Option 2 rather than the plan's preferred Option 3.** The plan text presented 3 options for keeping AuthCoordinator alive while the nav sits at `window.rootViewController`:
1. Static-property holder
2. AppCoordinator instance property
3. Notification.Name.authResolved bubble

The plan recommended option 3. But Plan 09's `AuthCoordinator` already exposes `onAuthenticated: ((Role) -> Void)?`. Adding a second notification channel duplicates the callback path that already exists — so this plan stored `private var authCoordinator: AuthCoordinator?` and forwards `onAuthenticated → onRoleResolved`. The existing SceneDelegate wiring (`coordinator.onRoleResolved = { self?.presentRoot(.role($0)) }` from Phase 1, preserved) remains the single re-present trigger. No new notification names introduced.

## Authentication Gates

None. This plan is entirely local composition-root wiring — no network calls, no real auth, no user prompts required during execution.

## Plan 12 Handoff Contract

Plan 12 (UI smoke tests upgrade) can assume:
- `"nav-avatar"` accessibilityIdentifier present on all 5 role shells' top-right bar button item.
- `"profile-logout"` identifier on the Profile modal's Log out button (Plan 10).
- SceneDelegate responds to `.sessionDidInvalidate` with root-swap; observe `.sessionDidInvalidate` in UI tests via NotificationCenter equivalent if needed.
- `-ForceRoleForUITest <role>` launch arg preserved (Phase 1) — Plan 12 adds `-MockOTPRoleForUITest <role>` alongside it.
- AppContainer's APIClient has Auth401ResponseInterceptor wired — any test fixture returning 401 on a non-OTP path will trigger the logout funnel (useful if Plan 12 wants to exercise AUTH-05 end-to-end).

## Threat Flags

None. Plan 11's composition-root wiring introduces no new network surface, no new auth paths beyond what Plans 06–10 already shipped, and no new file-access patterns. The `nav-avatar` affordance is a UI affordance on existing UINavigationControllers; the ProfileViewController presented is from Plan 10 and was already threat-modeled there.

## Self-Check

- [x] validationLedger/Core/Auth/SessionRestoreProbe.swift — created and verified (grep for `static func probe(env: Environment) -> SessionRestoreResult`).
- [x] validationLedger/App/AppContainer.swift — modified; contains `Auth401ResponseInterceptor(logoutService: logoutService)`, `DefaultLogoutService`, `DefaultSessionRestoreService`, `DefaultSensitiveActionService`.
- [x] validationLedger/App/AppCoordinator.swift — modified; contains `AuthCoordinator(container:)`, `AnotherActiveSessionViewController(supportEmail:)`, `.anotherActiveSession` case.
- [x] validationLedger/App/SceneDelegate.swift — modified; contains `SessionRestoreProbe.probe(env:`, `.sessionDidInvalidate`, `case anotherActiveSession`.
- [x] validationLedger/Roles/RoleCoordinator.swift — modified; contains `wrapTabsWithNavAndInstallAvatar(presenter:)` extension + `"nav-avatar"` identifier.
- [x] All 5 role TabBarControllers — modified; call `wrapTabsWithNavAndInstallAvatar` in viewDidLoad; init accepts `logoutService`.
- [x] validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift — 10 tests, all green.
- [x] validationLedgerTests/Roles/RoleCoordinatorTests.swift — 6 Phase 1 tests updated to pass `NoOpLogoutService` stub; all green.
- [x] Commits present in git log: `97a0e6a` (RED) → `ed608e6` (GREEN) → `80c6f2d` (avatar affordance).

## Self-Check: PASSED
