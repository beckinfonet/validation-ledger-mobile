---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 09
subsystem: features-onboarding-auth
tags:
  - ios
  - features
  - uikit
  - mvvm
  - wave-3
  - auth-01
  - auth-02
  - auth-03
  - geo-01
  - geo-02
  - d-01
  - d-02
  - d-06
  - d-20
  - d-21
  - d-22
  - d-26
  - d-27

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "Wave 0 test stubs (PhoneEntryViewModelTests + OTPViewModelTests placeholders) — both filled in this plan"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 02
    provides: "OTPRequestEndpoint / OTPVerifyEndpoint / DeviceRegisterEndpoint with IN-01/05 CodingKeys fixes applied"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 04
    provides: "KeychainKey.sessionRole/sessionUserID + KeychainScope + SessionRestoreService surface"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 05
    provides: "NetworkError.rateLimited(retryAfter:) — consumed by OTPViewModel to drive countdown"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 06
    provides: "BiometricService + DefaultBiometricService + SessionLockService.recordBiometricSuccess(at:) — consumed by OTPViewModel D-27 step 6"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 07
    provides: "KeyStoreProtocol (context-aware signWithAuthorization, generateDeviceIdentityKeys) — consumed by OTPViewModel D-27 steps 3-4"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 08
    provides: "LocationProvider + CountryGate + Info.plist NSLocationWhenInUseUsageDescription — consumed by PhoneEntryViewModel D-20 geo gate"

provides:
  - "PhoneEntryViewModel (@MainActor) — D-20 5-step geo gate orchestration + D-26 format helpers"
  - "PhoneEntryViewController — programmatic UIKit phone-entry surface with Submit button + Open-Settings alert"
  - "OTPViewModel (@MainActor) — D-27 7-step post-verify orchestration + AUTH-02 / D-02 Timer-driven Retry-After countdown"
  - "OTPViewController — programmatic UIKit OTP entry surface with countdown/progress/retry affordances"
  - "AuthCoordinator (@MainActor) — owns UINavigationController(rootViewController: PhoneEntryVC) + onAuthenticated(Role) callback"
  - "AppContainer.locationProvider + AppContainer.countryGate — minimal additions to let AuthCoordinator compile in the worktree (Plan 11 may refine)"
  - "NotAvailableInRegionViewController+Plan09Stub.swift — TEMPORARY; deleted when Plan 10 lands the canonical file"

affects:
  - "03-10 (BiometricLock/NotAvailableInRegion/AnotherActiveSession/Profile VCs) — provides AuthCoordinator that pushes NotAvailableInRegionViewController (Plan 10's canonical impl); Plan 09's stub file must be deleted by Plan 10's merge"
  - "03-11 (AppContainer composition root + SceneDelegate wiring) — Plan 11 constructs AuthCoordinator at AppContainer boot and bridges onAuthenticated → AppCoordinator.onRoleResolved; AppContainer now has locationProvider + countryGate properties"
  - "03-12 (RoleShellSmokeTests UI harness) — exercises the end-to-end auth → role-shell flow; OTP fixture drives role selection"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Closures-over-@Observable for ViewModel state notification: PhoneEntryVM + OTPVM both expose `var onStateChange: ((State) -> Void)?` / `var onAuthenticated: ((Role) -> Void)?` / etc. Preserves CLAUDE.md UIKit-first stance — no SwiftUI Observation framework dependency at the view layer."
    - "didSet-driven callback fan-out: `var state: State = .idle { didSet { onStateChange?(state); onVerifyEnabledChange?(verifyEnabled) } }` — single source of truth mutation triggers all subscriber notifications. OTPVM threads verifyEnabled re-computation into the state didSet because verifyEnabled depends on state (.rateLimited gates to false regardless of code length)."
    - "1-Hz Timer-driven countdown with MainActor hop: Timer.scheduledTimer callback runs on .main runloop but isn't @MainActor-isolated; wrap body in `Task { @MainActor [weak self] in ... }` to cross the isolation boundary. [weak self] avoids retain cycle; `timer.invalidate()` in guard-self-nil branch is the cleanup path."
    - "Forward-declaration stub pattern for Wave-parallel plans: when Plan 09 needs a VC that Plan 10 ships in the same wave, Plan 09 adds a temp stub file at a DIFFERENT filename (`NotAvailableInRegionViewController+Plan09Stub.swift`) with the same class name. Plan 10's merge surfaces redefinition error → engineer deletes stub. Avoids merge conflicts at same filename while keeping both worktrees independently compilable."

key-files:
  created:
    - validationLedger/Features/Onboarding/Auth/PhoneEntryViewModel.swift
    - validationLedger/Features/Onboarding/Auth/PhoneEntryViewController.swift
    - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
    - validationLedger/Features/Onboarding/Auth/OTPViewController.swift
    - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
    - validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController+Plan09Stub.swift
  modified:
    - validationLedger/App/AppContainer.swift
    - validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift
    - validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift

decisions:
  - "PhoneEntryVM.State.error(message:) carries a human-facing string rather than a typed enum — the UI path is trivial (`messageLabel.text = msg`) and the plan's must_haves don't require error categorization. When M2+ adds telemetry that needs to distinguish transport from business errors, the type can be promoted; for M1 the string surface is simpler and matches what UX needs."
  - "OTPViewModel.verifyEnabled guards .rateLimited regardless of code length — rationale: even if the user types 6 digits during the countdown, Verify must be disabled (AUTH-02). Encoding this as a computed property keyed off the current state (not a stored bool) avoids the risk of forgetting to flip the stored bool at state transitions."
  - "AuthCoordinator is `final class` with internal visibility (not public) — AppContainer is internal, so any init taking AppContainer as a parameter cannot be public. All 5 new source files follow the same internal-visibility rule for consistency within the Features module."
  - "AppContainer inline init for locationProvider/countryGate rather than plan's suggested static factory + extension trick — easier to refactor in Plan 11 (composition root) because the properties are already in the init body; Plan 11 just needs to change the construction, not promote extension statics into stored properties. Also preserves the single-source-of-truth boot path (everything in AppContainer.init so the CR-01 `grep URLSession validationLedger/` audit still returns one-file single-source)."
  - "NotAvailableInRegionViewController forward-declaration as a SEPARATE stub file (rather than inlined in AuthCoordinator) — makes the deletion boundary crisp when Plan 10 lands: `rm` the `+Plan09Stub.swift` file. If it were inlined in AuthCoordinator, Plan 10's merge would have to surgically remove the inline class definition, which is a merge-conflict generator. Separate file = clean delete."
  - "OTPViewModel D-27 step 5 failure (register) stays in .registerFailed state and exposes retryRegister() — the plan says 'does NOT clear keychain — retry-able'. retryRegister() simply calls verify() again; idempotency guards at the Keychain (upsert), KeyStore (Plan 02 CR-02), and APIClient (NET-04 Idempotency-Key) layers make the retry safe."
  - "Simulator destination iPhone 17 Pro / iOS 26.4 — consistent with Plans 01-08 env-correction. iPhone 15 / iOS 17.5 runtime not installed; project deployment target is iOS 17.0, so any iOS 17+ simulator is equivalent."

patterns-established:
  - "Two-commit atomic TDD cycle for single-task plans: one `test(03-XX): ... (RED)` commit with failing tests, one `feat(03-XX): ... (GREEN)` commit with implementation. RED commit has its compile-error evidence in the commit message body ('cannot find type X in scope'); GREEN commit has the test pass evidence."
  - "Internal-visibility default for Feature-layer types: because AppContainer is internal, anything that takes AppContainer as a parameter cannot be public. This extends naturally to AuthCoordinator (internal) and the VM/VC types it constructs. Only types that cross into tests via @testable need `public` — state enums etc. stay internal-by-default and `public` only when @testable can't reach them."

requirements-completed:
  - AUTH-01
  - AUTH-02
  - AUTH-03
  - GEO-01
  - GEO-02

# Metrics
duration: 8min
completed: 2026-04-21
---

# Phase 03 Plan 09: Auth UI Active-Flow Surface Summary

**One-liner:** Single-task TDD cycle landed PhoneEntryVC + PhoneEntryVM (D-20 5-step geo gate + D-26 format helpers) + OTPVC + OTPVM (D-27 7-step post-verify orchestration + D-02 Timer-driven Retry-After countdown) + AuthCoordinator (D-01 owns UINavigationController + onAuthenticated callback), unblocking Plan 11 to wire AuthCoordinator into the composition root.

## Performance

- **Duration:** ~8 min wall-clock (RED + GREEN atomic commits)
- **Started:** 2026-04-21 21:10 local
- **Completed:** 2026-04-21 21:18 local
- **Tasks:** 1 / 1 (TDD: RED + GREEN = 2 commits)
- **Files created:** 6 source (5 canonical + 1 stub)
- **Files modified:** 3 (AppContainer + 2 Wave-0 test stubs filled)

## Accomplishments

- **PhoneEntryViewModel landed.** Implements the D-20 5-step geo gate:
  1. `requestPermission()` — delegate-driven CLAuthorizationStatus
  2. `currentLocation(maxAge: 30, maxAccuracy: 100)` — one-shot fix
  3. `resolveCountry(for:)` — CLGeocoder reverse-geocode via CountryGate
  4. If `iso != "US"` → `.nonUSCountry` (UI pushes NotAvailableInRegionVC)
  5. POST `/auth/otp/request` via OTPRequestEndpoint → `.otpRequested(otpSessionID:)` → `onPhoneSubmitted` callback
  D-21 defense-in-depth collapses ALL failure paths (location error, geocode throw, empty/nil placemark flow through CountryGate) into `.nonUSCountry`. Permission denial is the single exception, surfacing `.needsLocationPermission` so the UI can present the Open-Settings alert.
  Static helpers: `formatDisplay(_:)` (10-digit `(XXX) XXX-XXXX`), `formatE164(_:)` (prepends `+1`). D-26 Submit gate: exactly 10 digits.
- **OTPViewModel landed.** Implements the D-27 7-step post-verify orchestration:
  1. OTPVerifyEndpoint → sessionToken/role/userID
  2. Persist 3 keys to Keychain under `.afterFirstUnlockThisDeviceOnly` (D-06/AUTH-03)
  3+4. `keyStore.generateDeviceIdentityKeys()` — returns devicePublicKey
  5. `DeviceRegisterEndpoint(devicePublicKey: base64, fingerprint: DeviceFingerprint.current)` → POST /device/register (DEV-05)
  6. `biometric.evaluate(reason:, fallback: .none)` — records initial evaluatedPolicyDomainState (D-09); sim failure is a logged warn but does NOT block flow (T-03-09-04 mitigated)
  7. `Role(rawValue: resp.role)` → `.success(role:)` → `onAuthenticated` callback
  AUTH-02 / D-02 Retry-After countdown: `catch NetworkError.rateLimited(let retryAfter)` starts a 1-Hz `Timer` driving `.rateLimited(remainingSeconds:)` state; Verify button disabled while non-zero. D-27 step 5 (device/register) failure routes to `.registerFailed` without clearing Keychain; `retryRegister()` re-runs the full sequence.
- **PhoneEntryViewController landed.** Programmatic UIKit (no SwiftUI). UITextField (phonePad) + prefixLabel "+1" + borderedProminent Submit button in a UIStackView anchored to safeAreaLayoutGuide. `phoneChanged` editingChanged handler filters non-digits, formats via `PhoneEntryViewModel.formatDisplay`, caps at 10, and forwards to VM. `handle(state:)` bridges VM state to UI: needsLocationPermission → UIAlertController with "Open Settings" → `UIApplication.shared.open(UIApplication.openSettingsURLString)`.
- **OTPViewController landed.** Programmatic UIKit. UITextField (numberPad, 6-digit max) + Verify button + countdown label (`"Try again in Xs"`) + progress label (`"Setting up your account (N/6)…"`) + UIActivityIndicatorView + hidden retry button (registerFailed recovery) + error label. Accessibility identifiers wired for Plan 12 smoke tests: `otp-field`, `otp-verify`, `otp-countdown`, `otp-progress`, `otp-retry`, `otp-error`.
- **AuthCoordinator landed.** `@MainActor final class` (internal — AppContainer is internal). Owns `UINavigationController(rootViewController: PhoneEntryViewController)`. `init(container: AppContainer)` constructs PhoneEntryVM with container-provided apiClient/location/countryGate/logger, then installs onPhoneSubmitted callback that pushes OTPVC. OTPVM's onAuthenticated bubbles to the coordinator's onAuthenticated callback, which Plan 11 wires to AppCoordinator.onRoleResolved.
- **AppContainer.swift minor additions.** Two new stored properties: `locationProvider: any LocationProvider` + `countryGate: any CountryGate`. Defaults construct `DefaultLocationProvider()` + `DefaultCountryGate()`. Plan 11's composition-root refactor may (a) keep these and add test-double injection paths, (b) promote them to init parameters with defaults. Either is compatible with this plan's stored-property shape.
- **NotAvailableInRegionViewController stub (temp).** Compiled at a DIFFERENT filename (`NotAvailableInRegionViewController+Plan09Stub.swift`) than Plan 10's canonical path so Plan 10's merge surfaces a redefinition error that flags this stub for deletion. Stub body is a minimal placeholder VC with one centered label — adequate for Plan 09's compile gate, never ships to Release (Plan 10's file supersedes).
- **PhoneEntryViewModelTests filled (Wave 0 stub → 7 real @Tests).** Swift Testing @Suite bound to `@MainActor`. Covers all 4 format-helper + submit-gate cases, denied-permission, non-US passthrough, and geocode-failure defense-in-depth. Fake `LocationProvider` + `CountryGate` isolated to the suite.
- **OTPViewModelTests filled (Wave 0 stub → 4 real @Tests).** Initial-state invariant + verify-gate contract + source-grep for D-27 7-step contract (`OTPVerifyEndpoint`, `generateDeviceIdentityKeys`, `DeviceRegisterEndpoint`, `biometric.evaluate`, `onAuthenticated`) + source-grep for D-02 rate-limit countdown (`NetworkError.rateLimited`, `Timer`). Rich fixture-driven happy-path tests deferred to Plan 12 smoke tests per plan's Task 1 Step F note.

## Task Commits

Atomic TDD cycle (RED → GREEN) with `--no-verify` per parallel-execution policy:

| Commit | Type | Subject |
|--------|------|---------|
| `589b490` | test | add failing tests for PhoneEntry + OTP ViewModels (RED) |
| `94a6d4f` | feat | add PhoneEntry + OTP VCs/VMs + AuthCoordinator (GREEN) |

**Plan metadata commit:** pending (appended with SUMMARY.md by orchestrator).

## Files Created / Modified

### Source — created (5 canonical + 1 stub)

| Path | Lines | Role |
|------|-------|------|
| `validationLedger/Features/Onboarding/Auth/PhoneEntryViewModel.swift` | 161 | D-20 5-step geo gate + D-26 helpers |
| `validationLedger/Features/Onboarding/Auth/PhoneEntryViewController.swift` | 139 | Programmatic UIKit phone-entry surface |
| `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` | 238 | D-27 7-step orchestration + D-02 countdown |
| `validationLedger/Features/Onboarding/Auth/OTPViewController.swift` | 166 | Programmatic UIKit OTP-entry surface |
| `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` | 49 | Owns UINavigationController + onAuthenticated callback |
| `validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController+Plan09Stub.swift` | 51 | TEMPORARY — deleted when Plan 10 lands |

### Source — modified (1)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/App/AppContainer.swift` | +2 stored properties (locationProvider, countryGate) + 2-line init construction | +11 |

### Tests — modified (2)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` | Filled Wave 0 stub with 7 @Tests + FakeLocation + FakeCountryGate + NoOpLogger | +125 / −2 |
| `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` | Filled Wave 0 stub with 4 @Tests + StubBio + 4-hop source resolver + NoOpLogger | +96 / −6 |

## Test Results

**Plan-scope suites — 11 tests pass green** (iPhone 17 Pro / iOS 26.4 simulator, `-parallel-testing-enabled NO`):

| Suite | Count | Status |
|-------|-------|--------|
| `PhoneEntryViewModelTests` | 7 | PASS |
| `OTPViewModelTests` | 4 | PASS |

**Full-suite regression — 170/170 tests pass across 32 suites:**
- 165 Swift Testing tests in 31 suites
- 5 XCUITests in 1 suite

**Command used:**
```
xcodebuild test-without-building -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath build -parallel-testing-enabled NO
```

Result: `** TEST EXECUTE SUCCEEDED **` — no regressions introduced by Plan 09.

## Key Contracts Ready for Downstream Plans

| Plan | Contract Consumed |
|------|-------------------|
| 10 — Lock/Region/Profile VCs | Plan 10 creates the canonical `NotAvailableInRegionViewController.swift`; Plan 10's merge must DELETE `NotAvailableInRegionViewController+Plan09Stub.swift` to resolve the redefinition. AuthCoordinator is already wired to push-via-`NotAvailableInRegionViewController()` — no changes needed in Plan 10 beyond the stub removal. |
| 11 — Composition root + SceneDelegate | Plan 11 constructs `AuthCoordinator(container:)` in AppContainer (or a factory method), bridges `coordinator.onAuthenticated` to `AppCoordinator.onRoleResolved`, and sets `window.rootViewController = coordinator.rootViewController` on `.auth` phase. AppContainer already has `locationProvider` + `countryGate` stored properties — Plan 11 may refactor the defaults into injection parameters or leave them as-is. |
| 12 — RoleShellSmokeTests | Accessibility identifiers `phone-entry-field`, `phone-entry-submit`, `otp-field`, `otp-verify`, `otp-countdown`, `otp-progress`, `otp-retry`, `otp-error`, `phone-entry-message` are wired on all interactive elements — XCUITest queries can target them directly. |

## Threat Mitigations Implemented

Per plan `<threat_model>`: all 4 Plan 09 threats are `mitigate` disposition; all 4 mitigations landed.

| Threat ID | Component | Mitigation landed? | Evidence |
|-----------|-----------|---------------------|----------|
| T-03-09-01 (Info-disclosure: coordinate in logs) | PhoneEntryViewModel.submit | YES | VM logs use `Logger.warn` with `.event` field carrying `String(describing: error)` — no coordinate leaks. Plan 03 D-23 compile-time invariant (LogField has no coordinate case) guarantees no regression is possible. |
| T-03-09-02 (Tampering: bypass geo gate) | PhoneEntryViewModel.submit | YES | State machine returns early on `.needsLocationPermission` / `.nonUSCountry` — OTP request only fires on US path. Backend re-verifies authoritatively. Tests `submitNonUS` + `submitGeocodeFailure` + `submitWithDeniedPermission` lock the early-return paths. |
| T-03-09-03 (Spoofing: OTP brute force via local retry) | OTPViewModel.verify | YES | `.rateLimited` state disables `verifyEnabled`; Timer-driven countdown; APIClient.parseRetryAfter (Plan 05) is the server-authoritative source. Local count is impossible — iOS cannot increment a counter to force a lockout. |
| T-03-09-04 (Spoofing: happy path proceeds despite sim biometric failure) | OTPViewModel.verify step 6 | MITIGATED (accept on sim) | Step 6 catch logs `initial_biometric_failed_sim_or_cancel` warn but proceeds — sim has no biometric hardware. SC-2 HUMAN-UAT validates real-device behavior; the sim path is acceptable degraded UX per plan's explicit guidance. |

No new threat surface introduced — changes are (a) new ViewModel logic consuming existing service seams, (b) new UIKit view controllers with no PII exposure, (c) two new stored properties on AppContainer for dependency wiring. No new network endpoints, no new file access, no schema changes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking API-level correction] AuthCoordinator public init incompatible with internal AppContainer type**

- **Found during:** First GREEN `xcodebuild build-for-testing` invocation.
- **Issue:** Plan's code sketch declared `public final class AuthCoordinator` with `public init(container: AppContainer)`. Compile error: `initializer cannot be declared public because its parameter uses an internal type`. `AppContainer` is internal (declared `final class AppContainer` with no `public` keyword); `public` APIs cannot expose internal types.
- **Fix:** Removed all `public` modifiers from AuthCoordinator (the class, the stored properties, the callback var, and the init). Kept `@MainActor`. All call sites remain within the app module (`AppCoordinator.makeRoot(for:)` Plan 11 edit; SceneDelegate is in the same module).
- **Files modified:** `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` (1 edit — removed `public` modifiers).
- **Verification:** `** TEST BUILD SUCCEEDED **` on retry.
- **Committed in:** `94a6d4f` (Task 1 GREEN — same commit as implementation, since the fix landed before the GREEN commit).
- **Rationale:** The plan's code sketch was illustrative; the internal/public access-level alignment is dictated by the surrounding codebase (AppContainer's internal visibility is the Phase 1 convention). No scope change; all `must_haves` satisfied.

**2. [Rule 3 — Blocking env correction, same as Plans 01-08] Destination substitution iPhone 17 Pro / iOS 26.4**

- **Found during:** RED `xcodebuild build-for-testing` invocation.
- **Issue:** `xcrun simctl list devices available` shows no iPhone 15 / iOS 17.5 runtime installed. Available: iOS 15.2, 18.0-18.4, 26.2, 26.4. Project deployment target is iOS 17.0 — any iOS 17+ simulator is equivalent for verification. Consistent with Plans 01-08.
- **Fix:** All `xcodebuild` invocations used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`.
- **Files modified:** None (CLI only).
- **Verification:** `** TEST BUILD SUCCEEDED **` + `** TEST EXECUTE SUCCEEDED **` on all runs.

**3. [Rule 2 — Defensive correctness] NotAvailableInRegionViewController separate-file stub instead of inline**

- **Found during:** Task 1 GREEN design phase.
- **Issue:** Plan 10 (sister plan in Wave 3) ships the canonical `NotAvailableInRegionViewController.swift` at `validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController.swift`. Plan 09's AuthCoordinator references the class — the worktree must compile standalone. Parallel execution means both plans produce worktrees that merge back to main; inlining the stub in AuthCoordinator would make Plan 10's merge a surgical source-editing problem.
- **Fix:** Added the stub at a DIFFERENT filename (`NotAvailableInRegionViewController+Plan09Stub.swift`) with a crisp `DELETE WHEN PLAN 10 LANDS` banner in the top comment. When Plan 10's merge lands, the Swift compiler surfaces a redefinition error on `class NotAvailableInRegionViewController` — resolution is `rm` the stub file.
- **Files modified:** Created new stub file (51 lines).
- **Verification:** Build + 11 plan-scope tests + 170-test full regression pass.
- **Committed in:** `94a6d4f`.
- **Rationale:** The plan's parallel_execution note explicitly permits "forward declaration / protocol or a temporary stub" for this exact scenario. Separate-file approach is cleaner than inlining because the Plan 10 merge resolution is a clear file-level delete.

**4. [Rule 2 — Defensive correctness] AppContainer stored-property addition instead of extension-static factory**

- **Found during:** Task 1 GREEN, after reading AuthCoordinator's `container.locationProvider` / `container.countryGate` call sites.
- **Issue:** Plan's "recommendation" was to add `static var defaultLocationProvider: () -> any LocationProvider = { ... }` as an extension on AppContainer. But AuthCoordinator reads `container.locationProvider` (instance property access) — the extension-static approach doesn't satisfy that call site.
- **Fix:** Added two stored properties on AppContainer (`locationProvider`, `countryGate`) with `DefaultLocationProvider()` / `DefaultCountryGate()` initialization in the init body. Commented that Plan 11 may refactor. This is strictly additive — no existing AppContainer consumer breaks.
- **Files modified:** `validationLedger/App/AppContainer.swift` (+2 declarations, +5 init lines, +4 lines of inline comment).
- **Verification:** Build succeeded; AppContainerNetworkConfigTests + all existing AppContainer-dependent tests still pass (170/170 regression).
- **Committed in:** `94a6d4f`.
- **Rationale:** Matches the call-site shape AuthCoordinator is written to consume. Plan 11's composition-root refactor can either (a) keep the stored properties and add injection in the init params, (b) promote to init parameters with defaults that remain `DefaultLocationProvider()` / `DefaultCountryGate()`. Either is a 3-5 line Plan 11 diff, not a restructure.

---

**Total deviations:** 4 auto-fixed (2 env-level, 2 API-level). **Impact on plan:** Zero scope change. All `success_criteria` satisfied; all `must_haves.truths` satisfied; all `must_haves.artifacts.contains` grep patterns satisfied.

## TDD Gate Compliance

Plan frontmatter is `type: execute` with a single task carrying `tdd="true"`. Gate sequence verified:

| Task | RED commit | GREEN commit | RED confirmation |
|------|-----------|--------------|-------------------|
| 1 | `589b490` (test) | `94a6d4f` (feat) | Expected errors confirmed: `cannot find type 'PhoneEntryViewModel' in scope` (×3 sites) + `cannot find type 'OTPViewModel' in scope` + `cannot infer contextual base in reference to member 'idle'` / `.needsLocationPermission` / `.nonUSCountry`. |

`git log --oneline -5` verifies chronological order: `test(03-09) RED` → `feat(03-09) GREEN`. No TDD gate violations.

## Known Stubs

**One intentional stub introduced by this plan, explicitly tracked:**

| File | Reason | Resolution plan |
|------|--------|-----------------|
| `validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController+Plan09Stub.swift` | Forward-declaration to let Plan 09 worktree compile standalone — Plan 10 (sister plan in Wave 3) ships the canonical VC at the same directory. | Plan 10's merge triggers redefinition error → engineer DELETES this stub file. `rm` the `+Plan09Stub.swift` file as part of Plan 10's merge resolution. |

Plan 01's Wave 0 stubs `PhoneEntryViewModelTests.swift` + `OTPViewModelTests.swift` are now FILLED with 7 + 4 real `@Test`s respectively — they are removed from the pending-stub ledger. Per Plan 01's Stub-to-Plan Mapping: this plan closes 2 of the remaining Wave 0 stubs.

The Plan 09-specific stub does NOT prevent the plan's goal — AuthCoordinator-drives-PhoneEntry-→-OTP-→-onAuthenticated works end-to-end with the stub present; the stub only affects the visual copy on the non-US refusal screen. Plan 10 replaces the visual copy without changing the flow behavior.

## Threat Flags

No new threat surface introduced beyond the plan's enumerated threat_model. Omitting Threat Flags table (no rows).

## Issues Encountered

- **`public` visibility on AuthCoordinator.init conflicted with internal AppContainer type.** Standard Swift access-control constraint; fixed by demoting AuthCoordinator to internal visibility (matches the rest of the Features module). Caught in the first GREEN build attempt. Documented in Deviation 1.
- **Stub file placement for NotAvailableInRegionViewController.** Trade-off between inlining (simpler 1-file change but merge-conflict risk with Plan 10) and separate-file stub (1 extra file but clean Plan 10 merge). Chose separate-file after weighing merge complexity. Documented in Deviation 3.

## User Setup Required

**None.** No external services, no secrets, no dashboard changes. All work is source + test edits verifiable via `xcodebuild test`.

**At runtime on a real device** (lands via Plan 11+12): on first Submit tap, the user sees iOS's location permission prompt carrying the "Validation Ledger uses your location at sign-in to verify you're in the United States, our service area." rationale (Plan 08 Info.plist). On first OTP success, the user sees the biometric prompt recording the initial domainState (D-09). Neither is in this plan's scope to exercise — both are observed in Plan 09's downstream HUMAN-UAT flow.

## Next Wave Readiness

- **Plan 10 proceeds.** Plan 10 ships `NotAvailableInRegionViewController.swift` at the canonical path + 3 sister VCs (BiometricLock, AnotherActiveSession, Profile). Plan 10's merge MUST delete `NotAvailableInRegionViewController+Plan09Stub.swift` — that is the single merge-resolution action required. Otherwise the build will fail with "redeclaration of NotAvailableInRegionViewController".
- **Plan 11 proceeds.** Plan 11 (composition root + SceneDelegate) constructs `AuthCoordinator(container:)` at `AppPhase.auth`, wires `coordinator.onAuthenticated` → `AppCoordinator.onRoleResolved`, and presents `coordinator.rootViewController` as `window.rootViewController`. AppContainer already has `locationProvider` + `countryGate` stored properties ready for consumption.
- **Plan 12 proceeds.** The VC accessibility identifiers are in place (`phone-entry-field`, `phone-entry-submit`, `otp-field`, `otp-verify`, `otp-countdown`, `otp-progress`, `otp-retry`, `otp-error`, `phone-entry-message`) — Plan 12's XCUITest smoke tests can target them directly without DOM traversal.
- **Downstream verifier should check:** the plan's `<verify>.automated` grep script (5 file-existence + `formatDisplay` + `rateLimited` + `generateDeviceIdentityKeys` greps) passes end-to-end. Plus the test-only-testing invocation on PhoneEntryViewModelTests passes. Both confirmed locally.

## Self-Check

**Files claimed created:**

- `validationLedger/Features/Onboarding/Auth/PhoneEntryViewModel.swift` — FOUND
- `validationLedger/Features/Onboarding/Auth/PhoneEntryViewController.swift` — FOUND
- `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` — FOUND
- `validationLedger/Features/Onboarding/Auth/OTPViewController.swift` — FOUND
- `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` — FOUND
- `validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController+Plan09Stub.swift` — FOUND

**Files claimed modified:**

- `validationLedger/App/AppContainer.swift` — FOUND (diff +11 lines; `locationProvider` + `countryGate` properties + inline construction)
- `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` — FOUND (filled stub, 7 @Tests)
- `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` — FOUND (filled stub, 4 @Tests)

**Commits claimed made:**

- `589b490` (Task 1 RED — failing tests for PhoneEntry + OTP ViewModels) — FOUND in `git log`
- `94a6d4f` (Task 1 GREEN — PhoneEntry + OTP VCs/VMs + AuthCoordinator) — FOUND in `git log`

**Plan `<verification>` block — all 6 criteria:**

| # | Check | Result |
|---|-------|--------|
| 1 | 5 NEW source files exist at documented paths | PASS |
| 2 | PhoneEntryVM implements D-20 5-step orchestration | PASS (grep `func submit`, `resolveCountry`, `requestPermission`, OTPRequestEndpoint) |
| 3 | OTPViewModel implements D-27 7-step + Retry-After countdown | PASS (grep `OTPVerifyEndpoint`, `generateDeviceIdentityKeys`, `DeviceRegisterEndpoint`, `biometric.evaluate`, `Timer`, `NetworkError.rateLimited`) |
| 4 | AuthCoordinator owns UINavigationController + onAuthenticated callback | PASS (grep `UINavigationController(rootViewController:` + `onAuthenticated: ((Role) -> Void)?`) |
| 5 | 6+ PhoneEntryViewModelTests pass green | PASS (7 tests green) |
| 6 | All VCs UIKit-only (no SwiftUI imports) | PASS (grep `import SwiftUI` in Auth/ returns 0 hits) |

**Plan `<success_criteria>` block — all 7 criteria:**

- [x] All 5 source files (PhoneEntry VC+VM, OTP VC+VM, AuthCoordinator) present
- [x] PhoneEntryVM correctly implements D-20 + D-26
- [x] OTPViewModel correctly implements D-27 + Retry-After countdown
- [x] BiometricLockVC + ProfileVC + AnotherActiveSessionVC + NotAvailableInRegionVC NOT shipped in this plan (confirmed: only stub at +Plan09Stub path)
- [x] PhoneEntryViewModelTests pass (7 tests)
- [x] All VCs UIKit-only
- [x] AuthCoordinator wires PhoneEntry → OTP → onAuthenticated callback

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
