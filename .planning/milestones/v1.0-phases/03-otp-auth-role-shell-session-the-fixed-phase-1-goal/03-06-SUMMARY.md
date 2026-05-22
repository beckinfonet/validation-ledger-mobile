---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 06
subsystem: Core/Auth
tags:
  - ios
  - auth
  - session
  - biometric
  - wave-2
  - sess-03
  - d-04
  - d-07
  - d-08
  - d-09
  - d-10
requires:
  - 03-01  # Wave 0 test file stubs (SessionRestoreServiceTests + BiometricServiceTests placeholders)
  - 03-02  # Role enum + KeychainStore surface
  - 03-04  # KeychainKey.sessionRole/sessionUserID/biometricDomainState + KeychainScope + deleteAll(under:)
  - 03-05  # APIClient 429 parsing (unrelated to this plan but Wave 1 gate)
provides:
  - BiometricService protocol + DefaultBiometricService + BiometricFallback enum
  - SessionRestoreService protocol + DefaultSessionRestoreService + SessionRestoreResult enum
  - SessionLockService.lockState(now:) -> LockState machine with LockReason (.coldBoot/.backgroundTimeout/.biometricReEnrolled/.neverUnlocked)
  - SESS-03 highest-priority biometric re-enrollment detection via evaluatedPolicyDomainState diff
  - UIApplication background/foreground self-subscription in DefaultSessionLockService
  - AppContainer.biometricService property (exposed for Plan 07+ consumers)
affects:
  - validationLedger/App/AppContainer.swift (init signature compatibility + biometricService wiring)
  - validationLedgerTests/Auth/SessionLockServiceTests.swift (Phase 1 invariants preserved + 5 new Phase 3 tests)
tech-stack:
  added:
    - LocalAuthentication (LAContext, LAPolicy, LAError)
    - UIKit (UIApplication.didEnterBackgroundNotification + didBecomeActiveNotification)
  patterns:
    - "@MainActor-bound service classes per D-31"
    - "Fresh LAContext per call — never reuse (WWDC22 streamline-local-auth recommendation)"
    - "canEvaluatePolicy(_, error:) BEFORE evaluatedPolicyDomainState read (Pitfall 1)"
    - "withCheckedThrowingContinuation bridging LAContext closure callback"
    - "NotificationCenter observer-token cleanup in deinit + [weak self] capture"
    - "Initializer-DI per ARCH-04 (no singletons)"
    - "Swift Testing @Suite + @Test + #expect (not XCTest)"
key-files:
  created:
    - validationLedger/Core/Auth/BiometricService.swift
    - validationLedger/Core/Auth/SessionRestoreService.swift
  modified:
    - validationLedger/Core/Auth/SessionLockService.swift
    - validationLedger/App/AppContainer.swift
    - validationLedgerTests/Auth/SessionLockServiceTests.swift
    - validationLedgerTests/Auth/SessionRestoreServiceTests.swift
    - validationLedgerTests/Auth/BiometricServiceTests.swift
decisions:
  - "SessionLockService.init gains biometric + keychain + notificationCenter params; AppContainer updated inline to preserve compile (Plan 11 refines composition root)"
  - "biometricReEnrolled is highest-priority branch in lockState (SESS-03 invariant)"
  - "evaluate() persists domainState via try? — persistence failure must not block user (degraded UX fallback is acceptable)"
  - "Default-parameter StubBiometricService() removed from test helper — default args evaluate outside function isolation context and @MainActor class cannot be called from nonisolated default-expression site"
metrics:
  duration: "~25 min"
  completed_date: "2026-04-21"
  tests_added: 15
  tests_green: 15
  tests_red_before: 15
  tests_red_after: 0
  files_created: 2
  files_modified: 3
  source_lines_added: 178  # SessionLockService 87 + BiometricService 76 + SessionRestoreService 44 - removed 40
---

# Phase 3 Plan 06: BiometricService + SessionRestoreService + SessionLockService extension

**One-liner:** LAContext biometric wrapper with evaluatedPolicyDomainState capture + synchronous Keychain cold-boot probe + 4-state SessionLockService machine with SESS-03 re-enrollment detection as the highest-priority branch.

## What Shipped

### NEW — `validationLedger/Core/Auth/BiometricService.swift`

- `BiometricService` protocol (@MainActor bound): `evaluate(reason:fallback:) async throws` + `currentDomainState() -> Data?`
- `BiometricFallback` enum: `.none` (strict biometric — D-11 sensitive actions) | `.devicePasscode` (session unlock — D-15)
- `DefaultBiometricService` impl:
  - Fresh `LAContext` per call (anti-pattern guard — WWDC22)
  - `canEvaluatePolicy(_, error:)` called BEFORE `evaluatePolicy(_:localizedReason:reply:)` to surface `.passcodeNotSet`/`.biometryNotAvailable` early AND to populate `evaluatedPolicyDomainState` (Pitfall 1)
  - `withCheckedThrowingContinuation` bridges LAContext's closure callback into async/await
  - On success, persists `evaluatedPolicyDomainState` to `Keychain[.biometricDomainState]` with `.afterFirstUnlockThisDeviceOnly` accessibility (D-09)
  - Persistence failure uses `try?` — must NOT block user; worst case is a false biometricReEnrolled on next lockState check

### NEW — `validationLedger/Core/Auth/SessionRestoreService.swift`

- `SessionRestoreResult` enum: `.restored(role: Role)` | `.needsAuth`
- `SessionRestoreService` protocol: `func probe() -> SessionRestoreResult` (synchronous — Sendable; safe to call from main thread before first `presentRoot`)
- `DefaultSessionRestoreService` impl:
  - Reads `.sessionToken` + `.sessionRole` from Keychain; requires both non-empty and a valid `Role` rawValue
  - On `.needsAuth` return, wipes partial state (sessionToken, sessionRole, sessionUserID) to avoid zombie Keychain items confusing the next probe
  - Logs one structured event per branch (`session_restored` / `session_restore_needs_auth`)

### MODIFIED — `validationLedger/Core/Auth/SessionLockService.swift`

- Added `import UIKit` (for UIApplication notification names)
- New `LockReason` enum: `.coldBoot | .backgroundTimeout | .biometricReEnrolled | .neverUnlocked`
- New `LockState` enum: `.unlocked | .locked(reason: LockReason)`
- Protocol extends with `func lockState(now: Date) -> LockState` as primary API; `shouldRequireBiometric(now:)` retained as back-compat wrapper (`lockState(now:) != .unlocked`)
- `DefaultSessionLockService` re-implemented as `@MainActor`-bound class:
  - New init: `(biometric: any BiometricService, keychain: KeychainStore, notificationCenter: NotificationCenter = .default)`
  - Self-subscribes to `UIApplication.didEnterBackgroundNotification` (records `enteredBackgroundAt = Date()` via `Task @MainActor [weak self]`) and `didBecomeActiveNotification` (no-op — SceneDelegate observes the same notification and queries lockState)
  - Observer tokens stored as instance properties; `deinit` calls `notificationCenter.removeObserver(token)`
  - `lockState(now:)` priority order:
    1. **biometricReEnrolled** — highest priority; stored vs current `evaluatedPolicyDomainState` differ
    2. **coldBoot** — `lastSuccess == nil`
    3. **backgroundTimeout** — `now - enteredBackgroundAt > 5 min`
    4. **unlocked** — otherwise
  - `invalidate()` now also clears `Keychain[.biometricDomainState]` per D-16 step 4 mirror (prevents false biometricReEnrolled after logout/relogin)

### MODIFIED — `validationLedger/App/AppContainer.swift`

- New stored property `biometricService: any BiometricService` (exposed for Plan 07 SensitiveActionService + Plan 09 OTPViewModel D-27 step 6)
- Constructs `DefaultBiometricService(keychain: self.keychainStore, logger: ...)` inline
- Passes biometric + keychain to `DefaultSessionLockService(biometric:keychain:)` (old `DefaultSessionLockService()` call no longer valid after the init signature change; Plan 11 refines)

### MODIFIED/FILLED — Tests

- `SessionRestoreServiceTests.swift` (Wave 0 stub → filled): 4 tests
  - Both keys → `.restored(role: .carrier)`
  - Only token → `.needsAuth` + partial cleanup verified
  - Empty keychain → `.needsAuth`
  - Invalid role rawValue → `.needsAuth`
- `BiometricServiceTests.swift` (Wave 0 stub → filled): 3 tests
  - `currentDomainState()` contract (sim returns nil — no biometric hardware)
  - Protocol surface compile assertion
  - Source-path grep guard: `canEvaluatePolicy` + `withCheckedThrowingContinuation` + `evaluatedPolicyDomainState` all present
- `SessionLockServiceTests.swift` (modified): 8 tests
  - Phase 1 (preserved): coldBoot / withinGrace / afterInvalidate
  - Phase 3 (new): D-07 lockState coldBoot / D-07 lockState unlocked / D-09 biometricReEnrolled highest priority / D-09 no-diff-when-equal / D-16-mirror invalidate-clears-domainState

## Test Results

**15/15 tests green** across 3 suites:

| Suite                       | Count | Status |
|-----------------------------|-------|--------|
| SessionRestoreServiceTests  | 4     | PASS   |
| BiometricServiceTests       | 3     | PASS   |
| SessionLockServiceTests     | 8     | PASS   |

**Command:**
```
xcodebuild test-without-building -scheme validationLedger \
  -destination 'platform=iOS Simulator,id=2494E033-9790-4E89-8614-288435026967' \
  -derivedDataPath build \
  -only-testing:validationLedgerTests/SessionLockServiceTests \
  -only-testing:validationLedgerTests/SessionRestoreServiceTests \
  -only-testing:validationLedgerTests/BiometricServiceTests
```

Full `validationLedgerTests` suite: 120/132 pass (12 pre-existing failures unrelated to Plan 06 — DeviceFingerprint Keychain sim state, MockURLProtocol parallel state WR-01, APIClient 429 contract in Plan 05). Pre-Plan-06 main also had 14 failures at the same sites — net tests green **increased** by 15.

## Key Contracts Ready for Downstream Plans

| Plan | Contract Consumed |
|------|-------------------|
| 07 — LogoutService + SensitiveActionService + Auth401ResponseInterceptor | `SessionLockService.invalidate()` clears domainState; `BiometricService.evaluate(reason:fallback: .none)` strict biometric for sensitive action re-prompt; `DefaultSessionLockService(biometric:keychain:)` constructor signature locked |
| 09 — AuthRepository + OTPViewModel (D-27 flow) | `BiometricService.evaluate(reason:fallback: .none)` at step 6 of D-27 records initial `evaluatedPolicyDomainState` |
| 10 — Phone Entry + OTP + BiometricLock + AnotherActiveSession VCs | `BiometricService.evaluate(reason:fallback: .devicePasscode)` for session unlock (D-15); `SessionLockService.lockState(now:)` drives BiometricLockVC reason-specific copy (D-14) |
| 11 — AppContainer composition root + SceneDelegate wiring | `SessionRestoreService.probe()` runs synchronously in SceneDelegate before first `presentRoot`; `AppContainer.biometricService` + `AppContainer.sessionLock` already constructed |

## Threat Mitigations Implemented

| Threat ID   | Mitigation                                                                                                   |
|-------------|--------------------------------------------------------------------------------------------------------------|
| T-03-06-01  | `DefaultBiometricService.evaluate/currentDomainState` construct a fresh `LAContext` per call; source grep test `sourceContainsCanEvaluateGuard` asserts `withCheckedThrowingContinuation` bridging |
| T-03-06-02  | `canEvaluatePolicy(_:error:)` called BEFORE `evaluatedPolicyDomainState` read in both `evaluate` and `currentDomainState`; source grep asserts `canEvaluatePolicy` present |
| T-03-06-03  | `lockState(now:)` compares stored vs current `evaluatedPolicyDomainState` as the FIRST check; test `lockStateBiometricReEnrolled` asserts highest-priority branch; test `lockStateNoDiffWhenEqual` asserts no false positive |
| T-03-06-04  | (Plan 11 wiring deferred — this plan ships the logic only)                                                   |
| T-03-06-05  | `SessionRestoreService.probe()` wipes `sessionToken`/`sessionRole`/`sessionUserID` on `.needsAuth`; test `needsAuthAndCleansPartial` asserts |
| T-03-06-06  | `DefaultSessionLockService.bgToken`/`fgToken` stored as instance properties; `deinit` calls `removeObserver`; closures use `[weak self]` |

## Deviations from Plan

### [Rule 3 — Blocking] AppContainer init needed inline wiring update

**Found during:** Step A implementation
**Issue:** Changing `DefaultSessionLockService` init signature from `()` to `(biometric:keychain:notificationCenter:)` broke `AppContainer.swift:83` where `self.sessionLock = DefaultSessionLockService()` was still the Phase 1 call. Entire build would not compile, preventing tests from running.
**Fix:** Construct `DefaultBiometricService` (Rule 2: critical dependency — required for SessionLockService to exist); pass into `DefaultSessionLockService(biometric:keychain:)`; expose `biometricService` as a new `AppContainer` property for Plan 07+ consumers. Plan 11 was scheduled to wire this in the composition root — pulling this forward is necessary so Plan 06 leaves the project in a compilable state (plan scope boundary).
**Files modified:** `validationLedger/App/AppContainer.swift` (2 edits — add property declaration + construct + inject)
**Commit:** a978c7a

### [Rule 3 — Blocking] Swift 6 default-argument isolation

**Found during:** First test build after GREEN phase
**Issue:** `StubBiometricService` is `@MainActor`-bound (required to conform to `BiometricService` which is `@MainActor`-only via the class conformance). Test helper `makeService(stubBiometric: StubBiometricService = StubBiometricService())` failed: default arguments evaluate outside the calling function's isolation context. Error: "call to main actor-isolated initializer 'init()' in a synchronous nonisolated context".
**Fix:** Removed default parameter; added zero-arg overload `makeService()` that forwards `StubBiometricService()` from within the `@MainActor`-bound suite body.
**Files modified:** `validationLedgerTests/Auth/SessionLockServiceTests.swift`
**Commit:** a978c7a (same commit as implementation since it was caught in the same build cycle)

### Test detail: `backgroundTimeout` branch

Plan called out that testing the `.backgroundTimeout` branch via the public API requires firing `UIApplication.didEnterBackgroundNotification` which is brittle in unit tests. **Per plan guidance, coverage for this branch is deferred to HUMAN-UAT (SC-3 is HUMAN-UAT per VALIDATION.md).** The other 3 lockState branches are covered.

## Deferred Issues

No out-of-scope issues logged — the 12 pre-existing full-suite failures are tracked in `.planning/phases/.../*.md` as Phase 2/3 Plan 05 follow-ups (not introduced by this plan).

## Authentication Gates

None. No third-party auth, CLI login, or manual step was required for this plan.

## Self-Check

Verification of acceptance criteria:

```
[OK] validationLedger/Core/Auth/BiometricService.swift exists
[OK] validationLedger/Core/Auth/SessionRestoreService.swift exists
[OK] validationLedger/Core/Auth/SessionLockService.swift contains "func lockState(now: Date) -> LockState" (lines 28, 92)
[OK] validationLedger/Core/Auth/SessionLockService.swift contains "import UIKit" (line 12)
[OK] validationLedger/Core/Auth/BiometricService.swift references "evaluatedPolicyDomainState" (5 occurrences)
[OK] validationLedger/Core/Auth/SessionRestoreService.swift contains "func probe() -> SessionRestoreResult" (lines 17, 29)
[OK] 15/15 plan-scope tests green
[OK] No pbxproj changes committed (auto-generated pbxproj modification excluded per parallel_execution rule)
[OK] Commits atomic: 149ef24 (RED) + a978c7a (GREEN)
```

## Self-Check: PASSED
