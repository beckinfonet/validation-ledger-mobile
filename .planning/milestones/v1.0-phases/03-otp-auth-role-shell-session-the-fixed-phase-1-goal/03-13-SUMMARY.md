---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 13
subsystem: scenedelegate-biometric-lock-overlay-wiring
gap_closure: true
tags:
  - ios
  - auth
  - session
  - biometric
  - scenedelegate
  - wiring
  - gap-closure
  - wave-6
  - sess-01
  - sess-02
  - sess-03
  - d-07
  - d-08
  - d-13
  - d-14
  - d-15

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 06
    provides: "DefaultSessionLockService.lockState(now:) 4-branch state machine (.coldBoot / .backgroundTimeout / .biometricReEnrolled / .unlocked) + LockReason enum + UIApplication.didEnterBackgroundNotification self-subscription — consumed directly by the new presentBiometricLockIfNeeded helper."
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 10
    provides: "BiometricLockViewController init(reason:biometric:sessionLock:onUnlockSuccess:onReBindRequested:) + D-13 auto-prompt on viewDidLoad + D-14 reason-specific copy + D-15 .devicePasscode fallback + accessibilityViewIsModal — the VC that was orphaned (zero construction sites) before this plan."
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 11
    provides: "SceneDelegate .sessionDidInvalidate observer + presentRoot(_:) root-swap funnel + SessionRestoreProbe cold-boot probe — this plan adds a second observer (didBecomeActive) alongside the Plan 11 pattern and hooks into the .role branch of presentRoot."

provides:
  - "SceneDelegate.presentBiometricLockIfNeeded(container:over:) — idempotent helper that checks container.sessionLock.lockState(now: .now) and presents BiometricLockViewController when .locked(_). No-op on .unlocked or when a lock VC is already up."
  - "SceneDelegate.handleDidBecomeActive() — UIApplication.didBecomeActiveNotification handler that re-runs the lockState check when currentPhase is .role(_). Covers the SESS-02 >5min background → biometric re-prompt requirement."
  - "SceneDelegate.presentRoot(_:checkLockState:) overload — `checkLockState: true` is passed ONLY from the SessionRestoreProbe .restored branch on genuine cold-boot; all other callers use the no-flag overload (checkLockState: false) so post-OTP role transitions, DevMenu role-swaps, and NetworkConfig toggles do not stack a lock VC on a fresh-process SessionLockService."
  - "AppCoordinatorPhase3RoutingTests.biometricLockWiringIsPresent — new structural test asserting 9 landmarks in SceneDelegate source (construction site, didBecomeActive observer, lockState call, helper signatures, logout route, idempotency guard, phase tracking, animated: false). Closes the 03-VERIFICATION.md grep-gap 'zero construction sites for BiometricLockViewController' permanently."

affects:
  - "03-VERIFICATION.md gap 1 — CLOSED. Grep for BiometricLockViewController in validationLedger/ now returns the construction site in SceneDelegate.swift (was 0 before this plan)."
  - "03-HUMAN-UAT.md items 1 (SC-2 cold-boot biometric prompt), 2 (SC-3 >5min background biometric re-prompt), and 3 (SC-4 biometric re-enrollment path) — were blocked by this gap; now legitimately testable on a physical iPhone with Face ID/Touch ID."
  - "Regression surface — the 5 RoleShellSmokeTests continue to pass unchanged (no -MockOTPRoleForUITest path modification needed; the cold-boot-only gate means post-OTP presentRoot(.role(_)) does not trigger the overlay). The 175 unit tests in 31 suites all pass."

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual presentRoot overloads to differentiate cold-boot from intra-session role-swap (Plan 13 pattern): `presentRoot(_:)` is the 1-arg back-compat entry that all post-auth callers use (no lock check); `presentRoot(_:checkLockState:)` is the 2-arg opt-in that ONLY the cold-boot SessionRestoreProbe.restored branch passes true into. Rationale: a fresh AppContainer's SessionLockService has lastSuccess == nil, so lockState() always returns .locked(.coldBoot). That is the CORRECT behavior for process-launch session restore (SESS-01) but WRONG after OTP verify or DevMenu role-swap (the user just authenticated; a biometric gate here is a false-positive). The flag isolates the SESS-01 moment without changing the fresh-container invariant."
    - "Idempotent modal-overlay presentation via weak reference (Plan 13 T-03-13-02 mitigation): `private weak var presentedLockVC: BiometricLockViewController?` — the helper no-ops if non-nil. Prevents stacked lock VCs when didBecomeActive fires during an active biometric prompt (e.g., user backgrounds during Face ID scan, foregrounds back). Weak reference avoids retain cycle; nil-out in the onUnlockSuccess callback closes the loop."
    - "SESS-03 M1 placeholder via LogoutService funnel (explicit design choice per 03-CONTEXT.md / 03-VERIFICATION.md 'missing' item 3): `.biometricReEnrolled` → `BiometricLockViewController.onReBindRequested` → `container.logoutService.logout(reason: .userInitiated)` → `.sessionDidInvalidate` observer → `presentRoot(.auth)`. Forced re-auth is the correct M1 product position because the authorizationKey's SE ACL is already invalidated by the domainState diff; a proper device re-bind UI can replace this in future phases without changing the trigger point."
    - "Per-scene observer lifecycle mirrored on Plan 11's pattern (Plan 13 T-03-13-06 mitigation): `appDidBecomeActiveObserver: NSObjectProtocol?` instance property → addObserver in scene(_:willConnectTo:) → removeObserver in both sceneDidDisconnect AND deinit. Matches the sessionInvalidateObserver + networkConfigObserver cleanup pattern exactly; prevents observer leak across multi-scene reconnects."

key-files:
  created: []
  modified:
    - validationLedger/App/SceneDelegate.swift
    - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift

decisions:
  - "Added a Rule 1 bugfix: gate the lock overlay presentation to cold-boot-only via a new presentRoot(_:checkLockState:) overload. Discovered during RoleShellSmokeTests regression — the plan's assertion that post-OTP flow would not trigger the overlay ignored that presentRoot creates a FRESH AppContainer with a FRESH SessionLockService (lastSuccess == nil, so lockState() returns .locked(.coldBoot)). The fix isolates the genuine cold-boot moment (SessionRestoreProbe.restored) from post-auth role transitions without breaking SESS-01/02/03."
  - "onReBindRequested captures container weakly (not the Coordinator or AppContainer-via-self.appCoordinator) — the closure runs AFTER presentRoot(.auth) ARC-drops the originating container tree; the weak reference means the closure is a no-op if the container is already gone. This matches the Plan 11 pattern of passing the container into closures that may outlive the coordinator swap."
  - "Dismiss with animated: false on onUnlockSuccess per RESEARCH §iOS API #6 line 910 — avoids revealing content during animation (security posture). Present also uses animated: false for the symmetrical reason: the lock overlay must appear instantaneously on cold-boot so there is no window where tab content is visible-but-uninteractive."
  - "Entire helper set (presentBiometricLockIfNeeded, handleDidBecomeActive, presentedLockVC, currentPhase, appDidBecomeActiveObserver) is marked `private` — zero new visibility surface. No other file in the module needs to call into SceneDelegate for this wiring."
  - "Preserved all Plan 11 invariants: SessionRestoreProbe.probe(env:) cold-boot path untouched; .sessionDidInvalidate observer untouched; -ForceRoleForUITest + -MockOTPRoleForUITest DEBUG blocks untouched. The only behavioral change is the new overlay presentation on the SessionRestoreProbe.restored(_) branch."

# Performance metrics
metrics:
  duration_minutes: ~20
  date_completed: 2026-04-22
  tasks_completed: 2
  tests_added: 1
  tests_green: "11 tests in AppCoordinatorPhase3RoutingTests (10 pre-existing + 1 new biometricLockWiringIsPresent); 175 unit tests in 31 suites across validationLedgerTests; 5 RoleShellSmokeTests in validationLedgerUITests"
  deviations: "1 auto-fix (Rule 1 bug: post-OTP lock-overlay regression on fresh SessionLockService)"
---

# Phase 3 Plan 13: SceneDelegate BiometricLockViewController Wiring (Gap Closure) Summary

**One-liner:** Closed 03-VERIFICATION.md gap 1 — BiometricLockViewController now has a live construction site in SceneDelegate.swift. On cold-boot with a restored session, presentRoot checks container.sessionLock.lockState(now:) and presents the lock VC modally (.fullScreen, animated: false) over the role tab-bar; the new UIApplication.didBecomeActiveNotification observer re-runs the check on foreground transitions to cover the SESS-02 >5min background path; `.biometricReEnrolled` routes `onReBindRequested` through `LogoutService.logout(.userInitiated)` as the SESS-03 M1 placeholder. The 3 HUMAN-UAT items blocked by this gap (cold-boot biometric, >5min background, re-enrollment) are now legitimately testable on a physical iPhone. Wave 6 gap-closure complete.

## What shipped

Two files modified, three commits:

1. **`validationLedger/App/SceneDelegate.swift`** (+118/-2, commit `2adb166` + follow-up bugfix `0655e72`):
   - Three new `private` stored properties: `appDidBecomeActiveObserver: NSObjectProtocol?`, `currentPhase: AppPhase?`, `weak var presentedLockVC: BiometricLockViewController?`.
   - New `UIApplication.didBecomeActiveNotification` observer registered in `scene(_:willConnectTo:)` alongside the existing `.sessionDidInvalidate` observer — calls `handleDidBecomeActive()` on foreground.
   - New `presentBiometricLockIfNeeded(container:over:)` private helper — idempotently constructs `BiometricLockViewController(reason:biometric:sessionLock:onUnlockSuccess:onReBindRequested:)` when `sessionLock.lockState(now: .now)` returns `.locked(_)` and presents modally with `animated: false`.
   - New `handleDidBecomeActive()` private handler — re-runs the helper only when `currentPhase` is `.role(_)`.
   - New `presentRoot(_:checkLockState:)` overload — `checkLockState: true` is passed ONLY from the `SessionRestoreProbe.restored` branch on genuine cold-boot; the 1-arg overload (and all existing callers) pass `false` implicitly.
   - Observer cleanup in both `sceneDidDisconnect(_:)` and `deinit` — mirrors the existing `sessionInvalidateObserver` + `networkConfigObserver` pattern.

2. **`validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift`** (+44, commit `902eacf`):
   - New `@Test("SceneDelegate source wires BiometricLockViewController (Phase 3 gap-closure Plan 13 — SESS-01/02/03)") func biometricLockWiringIsPresent()` — uses the existing `readSource` helper + source-contains pattern established by the `sceneDelegateObserves` test to assert 9 structural landmarks. Closes the 03-VERIFICATION.md grep-gap permanently.

## Gap closure

03-VERIFICATION.md documented a single high-confidence gap: "`grep -r BiometricLockViewController validationLedger/` returns only the file itself + comments in SensitiveActionService/BiometricService. Zero construction sites." This made the three SESS requirement paths unreachable even though every underlying service and VC was correctly implemented:

| Requirement | Before Plan 13 | After Plan 13 |
|-------------|----------------|---------------|
| SESS-01 (cold-boot biometric gate) | Blocked — no construction site | SceneDelegate `presentRoot(_:checkLockState:true)` on `SessionRestoreProbe.restored` triggers the overlay on `.locked(.coldBoot)` |
| SESS-02 (>5min background → biometric re-prompt) | Blocked — no construction site | `UIApplication.didBecomeActiveNotification` observer re-runs `lockState(now:)` when in `.role(_)`; `.locked(.backgroundTimeout)` triggers the overlay |
| SESS-03 (biometric re-enrollment) | Blocked — no construction site; onReBindRequested had nowhere to go | `.biometricReEnrolled` → `BiometricLockViewController.onReBindRequested` → `container.logoutService.logout(.userInitiated)` → `.sessionDidInvalidate` observer → `presentRoot(.auth)` |

The three HUMAN-UAT items in 03-HUMAN-UAT.md (items 1, 2, 3) previously marked "blocked by SceneDelegate wiring gap" are now legitimately testable on a physical iPhone with Face ID/Touch ID. Item 4 (SC-4 Secure Enclave inspection) was never blocked by this gap — it remains pending physical-device execution.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Post-OTP lock-overlay regression on fresh SessionLockService**

- **Found during:** Task 1 verification via `xcodebuild test -only-testing:validationLedgerUITests/RoleShellSmokeTests`. All 5 smoke tests failed at the "Loads" tab existence check — the biometric lock overlay was stacking on top of the role shell immediately after OTP verify, blocking the tab bar.

- **Issue:** The plan's `<preservation_invariants>` section asserted: "UI smoke tests wipe session Keychain → SessionRestoreProbe returns `.needsAuth` → .auth path → no lock overlay (since `if case .role = phase` is false on the .auth phase). The 5 existing UI smoke tests in Plan 12 are unaffected." This is true for the initial cold-boot presentRoot(.auth) but ignores that after OTP verify, AuthCoordinator's `onAuthComplete` fires `SceneDelegate.presentRoot(.role(role))` which creates a FRESH `AppContainer` with a FRESH `DefaultSessionLockService`. The fresh service has `lastSuccess == nil`, so `lockState(now:)` falls through the re-enrollment check + cold-boot check and returns `.locked(.coldBoot)`. The original Plan 13 code then stacked a lock VC on top of the just-built role TabBarController.

- **Fix:** Added `presentRoot(_:checkLockState:)` overload. The no-flag `presentRoot(_:)` calls the 2-arg version with `checkLockState: false`; only the `SessionRestoreProbe.restored` branch in `scene(_:willConnectTo:)` passes `checkLockState: true`. This isolates the genuine cold-boot moment (process-launch session restore — SESS-01) from post-auth role transitions and DevMenu role-swaps (where the user just authenticated and a biometric gate would be a false-positive). SESS-02 (didBecomeActive foreground re-check) is unaffected because `handleDidBecomeActive` calls `presentBiometricLockIfNeeded` directly, not through `presentRoot`. SESS-03 (biometricReEnrolled) is unaffected because the re-enrollment check is priority 1 in `lockState`, so the `.biometricReEnrolled` path triggers regardless of `lastSuccess` state — in practice this fires on cold-boot after a user changes their Face ID/Touch ID enrollment outside the app.

- **Files modified:** validationLedger/App/SceneDelegate.swift (one additional method added, one call site updated).

- **Commit:** 0655e72

- **Why this is Rule 1 (bug), not Rule 4 (architectural):** The fix touches only SceneDelegate internal dispatch — no change to SessionLockService, no change to AppContainer's fresh-container invariant (ADR 0002), no change to the composition-root architecture. It is a 30-line tactical fix that preserves all design decisions made in Plans 06/10/11 while correctly implementing the plan's stated intent (lock overlay on cold-boot, not on post-auth role transition).

## Self-Check: PASSED

**SceneDelegate.swift source-level landmarks (all 14 required by Task 1 acceptance criteria):**

- `[2] BiometricLockViewController(` — PRESENT (construction site closes gap 1)
- `[3] UIApplication.didBecomeActiveNotification` — PRESENT (SESS-02 observer)
- `[2] sessionLock.lockState(now:` — PRESENT (explicit lockState call)
- `[3] presentBiometricLockIfNeeded(container:` — PRESENT (helper signature)
- `[3] handleDidBecomeActive` — PRESENT (observer handler)
- `[1] logoutService.logout(reason: .userInitiated)` — PRESENT (SESS-03 route)
- `[6] presentedLockVC` — PRESENT (idempotency guard)
- `[3] currentPhase` — PRESENT (phase tracking)
- `[3] animated: false` — PRESENT (security posture)
- `[1] appDidBecomeActiveObserver = nil` — PRESENT (observer cleanup)
- `[1] SessionRestoreProbe.probe(env:` — PRESENT (cold-boot probe preserved)
- `[7] sessionDidInvalidate` — PRESENT (logout observer preserved)
- `[2] MockOTPRoleForUITest` — PRESENT (UI-test path preserved)
- `[3] ForceRoleForUITest` — PRESENT (DevMenu path preserved)

**Files confirmed:**

- validationLedger/App/SceneDelegate.swift: FOUND
- validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift: FOUND

**Commits confirmed in git log:**

- 2adb166 (feat 03-13 wire SceneDelegate): FOUND
- 0655e72 (fix 03-13 gate lock overlay): FOUND
- 902eacf (test 03-13 add structural test): FOUND

**Test runs:**

- `xcodebuild build -scheme validationLedger -destination 'iPhone 17 Pro / iOS 26.4'` → `** BUILD SUCCEEDED **`
- `xcodebuild test -only-testing:validationLedgerTests/AppCoordinatorPhase3RoutingTests` → `** TEST SUCCEEDED **` — 11 tests pass (10 pre-existing + 1 new `biometricLockWiringIsPresent`)
- `xcodebuild test -only-testing:validationLedgerTests -parallel-testing-enabled NO` → `** TEST SUCCEEDED **` — 175 tests in 31 suites pass
- `xcodebuild test -only-testing:validationLedgerUITests/RoleShellSmokeTests -parallel-testing-enabled NO` → `** TEST SUCCEEDED **` — 5 smoke tests pass (runtime ~85s)

Note on parallel-testing: running `validationLedgerTests` WITH `-parallel-testing-enabled YES` (xcodebuild default) surfaces the pre-existing MockURLProtocol concurrency failures documented in PROJECT.md Phase 2 (WR-01 / ci-simulator.yml propagates `-parallel-testing-enabled NO`). Those failures are unrelated to Plan 13 changes; the unit-test gate matches the CI configuration.
