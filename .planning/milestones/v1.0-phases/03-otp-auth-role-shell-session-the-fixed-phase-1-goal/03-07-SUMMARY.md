---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 07
subsystem: Core/Auth + Core/Networking/Interceptors
tags:
  - ios
  - auth
  - logout
  - sensitive-action
  - networking-interceptor
  - wave-2
  - tdd
  - d-11
  - d-12
  - d-16
  - d-17
  - d-28
  - d-30
  - blocker-3
  - warning-2

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "Wave 0 test file stubs (SensitiveActionServiceTests + LogoutServiceTests + Auth401ResponseInterceptorTests — placeholders)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 02
    provides: "SecureEnclaveKeyStore + SoftwareKeyStore two-key pattern; DER X9.62 signature unification (IN-02 closed)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 04
    provides: "KeychainStore.deleteAll(under: .session) + KeyStoreProtocol.deleteKey(slot:) + Keyslot top-level + KeychainKey session-scope additions"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 05
    provides: "APIClient 429 parsing (Wave 1 gate; unrelated surface but sequencing dependency)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 06
    provides: "BiometricService + SessionRestoreService + SessionLockService.invalidate() (all three consumed by this plan's LogoutService + intended downstream composition)"

provides:
  - "KeyStoreProtocol.signWithAuthorization(_:context:) context-aware overload — Phase 3 D-11 / Blocker 3 replaces the single-arg protocol requirement; legacy single-arg name remains available via public protocol extension forwarding with context: nil (zero caller breakage)"
  - "KeyStoreProtocol imports LocalAuthentication for LAContext"
  - "SecureEnclaveKeyStore.signWithAuthorization(_:context:) injects kSecUseAuthenticationContext into the SecItem query when context is non-nil — SecKeyCreateSignature reuses the already-authorized LAContext, suppressing the second OS biometric prompt. Shared loadPrivateKey(slot:context:) + sign(data:slot:context:) helpers carry the context through."
  - "SoftwareKeyStore.signWithAuthorization(_:context:) accepts (and intentionally ignores) the context argument — sim has no SE, CryptoKit has no LAContext attachment; protocol uniformity only"
  - "DefaultSensitiveActionService (NEW file Core/Auth/SensitiveActionService.swift) — WWDC22 single-prompt pattern: one fresh LAContext per call, evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics) ONCE, then keyStore.signWithAuthorization(payload, context: ctx) with the SAME context → single OS biometric prompt end-to-end (Blocker 3 fix)"
  - "SensitiveActionError enum: .userCancel, .biometryLockout, .biometricReEnrolled, .signFailed(underlying:) — mapped from LAError via evaluatePolicy continuation"
  - "Default init(keyStore:logger:) — no BiometricService injection (that would imply the deprecated double-prompt design). @MainActor per D-31."
  - "DefaultLogoutService (NEW file Core/Auth/LogoutService.swift) — single source of truth for 6-step D-16 teardown. Step 2+4 collapsed into one keychain.deleteAll(under: .session) call (Warning 2 fix); Step 6 notification post is LAST so observers never see mid-teardown state."
  - "LogoutReason: String enum — .userInitiated / .auth401 / .anotherActiveSession (D-30 stable raw values for Notification userInfo encoding)"
  - "Notification.Name.sessionDidInvalidate + Notification.Name.LogoutReasonKey — the contract SceneDelegate (Plan 11) will observe"
  - "Auth401ResponseInterceptor (NEW file Core/Networking/Interceptors/Auth401ResponseInterceptor.swift) — conforms to ResponseInterceptor; on 401 from a non-excluded path, fires LogoutService.logout(.auth401) via detached Task (fire-and-forget so the 401 still returns to the caller intact)"
  - "defaultExcludedPaths = {/auth/otp/request, /auth/otp/verify} — a 401 there means wrong code, not session expired (D-28)"
  - "14 new tests across 3 new/filled test files + 4 new tests in existing KeyStoreProtocolDeleteTests, all green"

affects:
  - "03-09 (Auth UI / OTP flow) — OTPViewModel D-27 step 6 stays on BiometricService.evaluate, NOT SensitiveActionService (SensitiveActionService has zero call sites in M1 per D-12)"
  - "03-10 (ProfileViewController + BiometricLockViewController) — ProfileViewController Log-Out button constructs LogoutService from AppContainer; single .userInitiated call site (of 3 total funnel paths)"
  - "03-11 (AppContainer composition root + SceneDelegate wiring) — Plan 11 constructs DefaultLogoutService + DefaultSensitiveActionService as AppContainer properties; wires Auth401ResponseInterceptor into APIClient responseInterceptors; SceneDelegate observes .sessionDidInvalidate and routes based on userInfo[.LogoutReasonKey] per D-18"
  - "Phase 4 device CI (CI-03) — real SE single-prompt exercise requires hardware biometric (Face ID / Touch ID); source-grep tests on SensitiveActionService and kSecUseAuthenticationContext confirm the design is in place but runtime single-prompt is HUMAN-UAT per VALIDATION.md"

# Tech tracking
tech-stack:
  added: []  # LocalAuthentication already added in Plan 06
  patterns:
    - "WWDC22 single-prompt pattern — fresh LAContext per call + evaluatePolicy ONCE + pass the same context to a SecKey operation via kSecUseAuthenticationContext. Eliminates the double-prompt that would otherwise occur when an SE key has a .biometryCurrentSet ACL."
    - "Backward-compatible protocol overload via extension — replace a protocol requirement with a new signature (context-aware), provide the old name as a default protocol-extension method that forwards. Implementations only write the new variant; existing call sites still compile. Zero caller breakage (protocol-surface migration)."
    - "Fire-and-forget side-effect in a response interceptor — detached Task inside intercept(_:request:) triggers the side effect (logout) without blocking the response return. The caller still receives (data, response) intact; SceneDelegate handles the actual UI root-swap on .sessionDidInvalidate."
    - "Notification name doubling as userInfo key — `Notification.Name.LogoutReasonKey` is technically a Notification.Name but serves as a stable String-typed dictionary key (the raw value). Avoids the cross-module coupling of defining a separate AnyHashable constant."
    - "Actor conforming to a Sendable + AnyObject protocol — SpyLogout actor in the interceptor tests conforms to LogoutService directly without @unchecked. Actors are reference types (AnyObject) and automatically Sendable; the protocol's async method contract composes naturally with actor isolation."
    - "Step-collapse with documented invariant — D-16 documents 6 conceptual teardown steps; the implementation collapses Steps 2+4 into a single keychain.deleteAll(under: .session) (Warning 2). The code comment + a dedicated test (`logoutClearsBiometricDomainState`) preserve the contract at the documented level while reducing to one Keychain op."

key-files:
  created:
    - validationLedger/Core/Auth/SensitiveActionService.swift
    - validationLedger/Core/Auth/LogoutService.swift
    - validationLedger/Core/Networking/Interceptors/Auth401ResponseInterceptor.swift
  modified:
    - validationLedger/Core/KeyStore/KeyStoreProtocol.swift
    - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
    - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
    - validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift
    - validationLedgerTests/Auth/SensitiveActionServiceTests.swift
    - validationLedgerTests/Auth/LogoutServiceTests.swift
    - validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift

decisions:
  - "Replace-then-forward for the KeyStoreProtocol migration. The plan text described keeping the old `signWithAuthorization(_:)` declaration alongside the new context-aware overload. Swift protocols can technically have both, but the new approach makes the old declaration redundant — implementations would have to provide BOTH methods. Cleaner path: DELETE the single-arg requirement from the protocol, add the context-aware requirement, and re-expose the old name via a public protocol extension forwarding to the new variant with `context: nil`. Implementations now provide ONLY the context-aware method; existing callers continue to compile and exhibit the legacy SE-driven double-prompt behavior (unchanged)."
  - "kSecUseAuthenticationContext attached at the SecItemCopyMatching query level (where the SE key is loaded), not just at the SecKeyCreateSignature call. Apple's documentation is somewhat ambiguous about which layer honors the attached context for SE-backed keys; empirically — and per WWDC22 sample — the correct location is the item-matching query, so the LAContext authorization accompanies the SecKey pointer into the signing step. Both SE loadPrivateKey and sign helpers thread the context through so any future caller that needs a context-aware sign() (device key, tender-payload signing, etc.) inherits the plumbing."
  - "SensitiveActionService does NOT inject BiometricService. The plan's D-11 offered two valid shapes (inject BiometricService + use SE-driven second prompt, OR raw LAContext with single prompt). Chose the raw-LAContext design because it's (a) the Blocker 3 fix as written, (b) exercised by the single-prompt source-grep test that forbids `biometric: any BiometricService` in the init, (c) simpler — one dependency less, one OS prompt less, and no ambiguity about which prompt the user sees first."
  - "SensitiveActionError maps only the two most user-actionable LAError codes (userCancel + biometryLockout) to dedicated cases; everything else — including authenticationFailed, userFallback, invalidContext, appCancel, systemCancel — collapses into .signFailed(underlying:). M2+ tender/accept call sites can pattern-match against .userCancel (dismiss flow) and .biometryLockout (surface passcode suggestion — though SE ACL won't accept passcode, so UX is 'contact support'). Fine-grained mapping can follow when real call sites reveal which cases need per-user-experience branching."
  - "LogoutService Step 2/4 collapse comment lives in the source file, not only in the plan. Future readers editing logout() need to see the invariant (KeychainScope.session includes biometricDomainState) right next to the code. The test `logoutClearsBiometricDomainState` is the automated complement."
  - "Notification userInfo encodes reason.rawValue (String), not the enum itself. Cross-module Notification consumers (SceneDelegate.observe in Plan 11) should not need to @testable import the auth module to decode the reason. String + switch on raw values is the stable cross-module contract per D-30."
  - "Auth401ResponseInterceptor uses a detached `Task { await service.logout(...) }` to fire the logout call without blocking the response. Alternative (awaiting the logout inline) would delay the 401 reaching the endpoint caller by the duration of a full teardown + notification round-trip, and would serialize logout with the response path — neither is required. Fire-and-forget matches the plan's RESEARCH-note guidance that 'caller still gets the 401 response to handle/decode normally.'"
  - "Actor-based SpyLogout for the interceptor test. Plan text suggested either `actor SpyLogout` or `@MainActor final class SpyLogout`; actor worked out of the box here because LogoutService is `AnyObject + Sendable` and actors satisfy both. No `@unchecked Sendable` shenanigans needed."
  - "Xcode 16+ PBXFileSystemSynchronizedRootGroup means new files under `validationLedger/Core/...` are auto-included in the app target. Xcode does touch `project.pbxproj` with cache-cleanup reshuffles during test runs, but none of those changes are meaningful and per parallel_execution instructions the auto-generated pbxproj mutations are NOT committed (discarded via `git checkout`)."

# Metrics
duration: 10m
completed: 2026-04-22

requirements-completed:
  - AUTH-04
  - AUTH-05
  - AUTH-06
  - SESS-04
---

# Phase 03 Plan 07: LogoutService + SensitiveActionService + Auth401ResponseInterceptor Summary

**One-liner:** Single-funnel 6-step logout teardown + WWDC22 single-prompt sensitive-action signing + 401-on-non-OTP-path → logout response interceptor. 14 new tests green; Blocker 3 (double-prompt) and Warning 2 (Step 2/4 redundancy) both closed; `KeyStoreProtocol.signWithAuthorization` gains a context-aware overload with zero-break backward compatibility via protocol extension.

## Performance

- **Duration:** ~10 min (plan estimated: ~25-30% context per task × 3 tasks)
- **Started:** 2026-04-22T03:40:27Z (first RED commit `6adcf26`)
- **Completed:** 2026-04-22T03:50:34Z (final GREEN commit `b31aaac`)
- **Tasks:** 3 / 3 (TDD: each split RED + GREEN = 6 commits total)
- **Files created:** 3 source + 0 test (tests filled existing Wave 0 stubs)
- **Files modified:** 3 source + 4 test

## Accomplishments

### Task 1 — KeyStoreProtocol context-aware overload (D-11 single-prompt plumbing)

- **`func signWithAuthorization(_ data: Data, context: LAContext?) throws -> Data`** is the new protocol requirement. `LocalAuthentication` imported at the protocol module.
- **Backward-compat extension** exposes the legacy `signWithAuthorization(_ data: Data)` name as a default method that forwards with `context: nil`. Existing call sites compile unchanged; their runtime behavior is the legacy Phase 2 SE-driven prompt (unchanged).
- **`SecureEnclaveKeyStore`** — attached `kSecUseAuthenticationContext: context` into the SecItemCopyMatching query in a refactored `loadPrivateKey(slot:context:)`; the shared `sign(data:slot:context:)` helper propagates the context into `SecKeyCreateSignature`. Legacy paths (device-key sign, public-key load) pass `context: nil` and remain identical to Phase 2.
- **`SoftwareKeyStore`** — accepts the context argument and ignores it with an explicit `_ = context` to document the intentional no-op + suppress unused-parameter diagnostics if Swift ever adds them. Imports `LocalAuthentication` for protocol parameter uniformity.
- **4 new tests in `KeyStoreProtocolDeleteTests`** (all via `#filePath`-relative URL resolution, matching the file's existing source-grep pattern):
  - `signWithAuthorizationContextOverload` — asserts protocol declares the overload and imports LA
  - `sePassesContextToQuery` — asserts `kSecUseAuthenticationContext` appears in SE source
  - `softwareSignWithContextWorks` — runtime assertion: call sign with context: nil → DER SEQUENCE tag
  - `legacySignWithAuthorizationStillWorks` — runtime assertion: legacy single-arg call still returns DER (backward-compat extension delegation works)

### Task 2 — SensitiveActionService + LogoutService

**`validationLedger/Core/Auth/SensitiveActionService.swift` (NEW):**

- `SensitiveActionService` protocol (`AnyObject + Sendable`, `@MainActor`-bound impl)
- `DefaultSensitiveActionService.authorize(_ payload: Data, reason: String) async throws -> Data`
- WWDC22 pattern: fresh `LAContext()` → `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)` → `keyStore.signWithAuthorization(payload, context: ctx)` → SE reuses the already-authorized context via `kSecUseAuthenticationContext` (Task 1) → single OS prompt end-to-end.
- Strict biometric (`.deviceOwnerAuthenticationWithBiometrics`) — the code comment at top-of-file explains why passcode fallback is rejected here (SE ACL `.biometryCurrentSet` rejects passcode, so allowing it would produce a worse UX: "context authorized successfully" + "SE refuses to sign").
- `SensitiveActionError` enum maps the two most user-actionable LAError codes (`.userCancel`, `.biometryLockout`); everything else collapses into `.signFailed(underlying:)` — sufficient for M1 (zero call sites per D-12).
- M1 surface is constructibility only (D-12) — `SensitiveActionServiceTests.constructibleWithSignature` is the entirety of the AUTH-06 runtime coverage.

**`validationLedger/Core/Auth/LogoutService.swift` (NEW):**

- `LogoutReason: String` enum — `.userInitiated / .auth401 / .anotherActiveSession` with stable String raw values (D-30). This is what crosses Notification boundaries to SceneDelegate (Plan 11).
- `Notification.Name.sessionDidInvalidate` + `Notification.Name.LogoutReasonKey` — the cross-module contract.
- `DefaultLogoutService.logout(reason:) async` — 6-step D-16 orchestration:
  1. (implicit) Clear in-memory state — services hold their own; the SceneDelegate root-swap (post-step-6) tears down coordinator/VM state.
  2. + 4. `keychain.deleteAll(under: .session)` — wipes `sessionToken`, `sessionRole`, `sessionUserID`, AND `biometricDomainState` (Warning 2: KeychainScope.session includes all 4, so Step 4 of D-16 is subsumed by Step 2). One Keychain operation; documented inline with a code comment.
  3. `keyStore.deleteKey(slot: .authorization)` — SE `SecItemDelete`; deviceKey preserved (not session-bound).
  5. `sessionLock.invalidate()` — `DefaultSessionLockService` (Plan 06) also clears `.biometricDomainState` from Keychain as its step-4 mirror; this is the race-free single invalidation point.
  6. `notificationCenter.post(.sessionDidInvalidate, userInfo: [.LogoutReasonKey: reason.rawValue])` — LAST step (Pitfall 3): observers must see fully-cleared state.
- `NotificationCenter` is an injected dependency (default `.default`) so tests can use isolated instances.

**Tests (8 new):**

- `SensitiveActionServiceTests` (4): constructibility, strict `.deviceOwnerAuthenticationWithBiometrics` source grep (+ rejection of `.deviceOwnerAuthentication,` / `.deviceOwnerAuthentication)`), context passed to keyStore.signWithAuthorization source grep, no-BiometricService + fresh-LAContext source grep.
- `LogoutServiceTests` (4): D-30 raw values, full teardown runtime (keychain wiped, auth key deleted, device key preserved, lock cold-boot, notification via isolated `NotificationCenter()`), Warning 2 biometricDomainState wipe assertion, notification userInfo carries `reason.rawValue` string (actor-captured cross-boundary).

### Task 3 — Auth401ResponseInterceptor

- **`validationLedger/Core/Networking/Interceptors/Auth401ResponseInterceptor.swift` (NEW)**:
  - Conforms to the existing `ResponseInterceptor` protocol (Plan 02).
  - `defaultExcludedPaths = ["/auth/otp/request", "/auth/otp/verify"]` — a 401 at those paths means "wrong code", not "session expired" (D-28).
  - On a 401 from a non-excluded path: fire a detached `Task { await logoutService.logout(reason: .auth401) }`. Fire-and-forget so the 401 still returns to the caller normally.
- **6 tests in `Auth401ResponseInterceptorTests`**:
  - `defaultExcludedPaths` — exact set equality
  - `authPath401TriggersLogout` — 401 on `/loads` → actor-SpyLogout records `.auth401`
  - `otpRequestPath401Excluded` — 401 on `/auth/otp/request` → no logout
  - `otpVerifyPath401Excluded` — 401 on `/auth/otp/verify` → no logout
  - `nonAuthStatusPassesThrough` — parameterized over {200, 400, 403, 500} — no logout
  - `passesResponseThrough` — response (data + status 401) reaches the caller intact

**Actor-based `SpyLogout`**: declares `private actor SpyLogout: LogoutService`. Actors satisfy `AnyObject + Sendable` without any `@unchecked` annotation and compose cleanly with the async protocol method.

## Task Commits

Each task followed TDD with atomic RED → GREEN commits (worktree mode, `--no-verify` per parallel-execution policy):

| Commit | Type | Task | Subject |
|--------|------|------|---------|
| `6adcf26` | test | 1 RED   | add failing tests for context-aware signWithAuthorization |
| `657368b` | feat | 1 GREEN | add context-aware signWithAuthorization overload |
| `529a6d5` | test | 2 RED   | add failing tests for SensitiveActionService + LogoutService |
| `d67945f` | feat | 2 GREEN | add SensitiveActionService + LogoutService |
| `b6e443a` | test | 3 RED   | add failing tests for Auth401ResponseInterceptor |
| `b31aaac` | feat | 3 GREEN | add Auth401ResponseInterceptor |

**Plan metadata commit:** pending (appended with SUMMARY.md by orchestrator).

## Files Modified / Created

### Source (6)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` | `import LocalAuthentication`; new context-aware `signWithAuthorization(_:context:)` requirement; legacy name kept via public protocol extension forwarding to `context: nil` | +22 / −3 |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | `import LocalAuthentication`; new context-aware `signWithAuthorization(_:context:)` impl; `loadPrivateKey(slot:context:)` + `sign(data:slot:context:)` now thread `kSecUseAuthenticationContext` through | +23 / −7 |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | `import LocalAuthentication`; `signWithAuthorization(_:context:)` accepts and intentionally ignores context; comment explains why | +10 / −3 |
| `validationLedger/Core/Auth/SensitiveActionService.swift` | NEW — single-prompt WWDC22 design; @MainActor; `authorize(_:reason:)` with LAError → SensitiveActionError mapping | +107 |
| `validationLedger/Core/Auth/LogoutService.swift` | NEW — 6-step D-16 teardown with Warning 2 Step 2/4 collapse; LogoutReason String enum; Notification.Name.sessionDidInvalidate + .LogoutReasonKey | +102 |
| `validationLedger/Core/Networking/Interceptors/Auth401ResponseInterceptor.swift` | NEW — fire-and-forget logout on 401 non-OTP-path; defaultExcludedPaths constant | +49 |

### Test (4)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift` | +4 @Tests (context overload + SE grep + sw runtime + legacy passthrough); added #filePath resolver helper | +59 |
| `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` | Filled Wave 0 stub: 4 @Tests covering constructibility + policy + context passing + no-BiometricService invariant | +86 / −10 |
| `validationLedgerTests/Auth/LogoutServiceTests.swift` | Filled Wave 0 stub: 4 @Tests — raw values + full teardown + biometricDomainState clear + notification userInfo | +118 / −6 |
| `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` | Filled Wave 0 stub: 6 @Tests — excluded paths + 401 trigger + OTP exclusions + non-401 passthrough + response-intact | +97 / −6 |

## Test Results

**Plan-scope + related regression — 45/45 tests green across 8 suites** (`-parallel-testing-enabled NO`):

| Suite | Count | Status |
|-------|-------|--------|
| `KeyStoreProtocolDeleteTests` | 9 (5 pre-existing + 4 new) | PASS |
| `SoftwareKeyStoreExtendedTests` | 7 | PASS |
| `SensitiveActionServiceTests` | 4 | PASS |
| `LogoutServiceTests` | 4 | PASS |
| `Auth401ResponseInterceptorTests` | 6 (one parameterized × 4 → 9 test cases) | PASS |
| `SessionLockServiceTests` | 8 | PASS |
| `SessionRestoreServiceTests` | 4 | PASS |
| `BiometricServiceTests` | 3 | PASS |

**Full regression (entire simulator test plan, -parallel-testing-enabled NO):** 147 Swift Testing tests in 31 suites + 5 XCUI tests in 1 suite = **152/152 PASS**. `** TEST SUCCEEDED **` — no regressions introduced by Plan 07.

**Command used:**
```
xcodebuild test -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath build \
  -parallel-testing-enabled NO
```

## Key Contracts Ready for Downstream Plans

| Plan | Contract Consumed |
|------|-------------------|
| 09 — AuthRepository + OTPViewModel (D-27 flow) | `KeyStoreProtocol` context-aware overload means D-27 step 6 (record domainState) stays on BiometricService, NOT SensitiveActionService (zero call sites in M1 per D-12). |
| 10 — ProfileViewController + BiometricLockViewController + AnotherActiveSessionViewController | `DefaultLogoutService` is constructed in AppContainer (Plan 11); ProfileVC tap is the `.userInitiated` call site (one of three funnels). Reason-specific copy on BiometricLockViewController uses `SessionLockService.lockState(now:)` from Plan 06; Logout path does NOT use `LockReason`. |
| 11 — AppContainer composition root + SceneDelegate wiring | Constructs `DefaultLogoutService(keychain, keyStore, sessionLock, logger)` + `DefaultSensitiveActionService(keyStore, logger)` + `Auth401ResponseInterceptor(logoutService:)`. Wires the interceptor into `APIClient.responseInterceptors`. SceneDelegate observes `.sessionDidInvalidate` and reads `userInfo[.LogoutReasonKey]` as String, mapping to `.auth / .anotherActiveSession` per D-18. |
| 12 — final DevMenu hooks | Plan 12 (or later) may add a DevMenu "Trigger logout" affordance; it just calls `logoutService.logout(reason: .userInitiated)` — no additional API needed. |

## Threat Mitigations Implemented

Per plan `<threat_model>`: all 7 Plan 07 threats are `mitigate` disposition; all 7 mitigations landed.

| Threat ID | Mitigation |
|-----------|------------|
| T-03-07-01 Stale sessionToken in Keychain after logout | `LogoutService.logout` step 2+4 `keychain.deleteAll(under: .session)` wipes all 4 session keys; `logoutFullTeardown` + `logoutClearsBiometricDomainState` tests assert. |
| T-03-07-02 SE auth-key surviving logout enables sensitive-action signing | `LogoutService.logout` step 3 calls `keyStore.deleteKey(slot: .authorization)`; `logoutFullTeardown` asserts `signWithAuthorization` throws post-logout. Device key preserved (asserted). |
| T-03-07-03 Logout race (UI dismisses before Keychain wipe completes) | `LogoutService.logout` is `async`; the `.sessionDidInvalidate` Notification post is the LAST step. `notificationPostedWithReason` asserts the notification fires with correct reason string. |
| T-03-07-04 Confused-user double-prompt on sensitive action | D-11 / Blocker 3 single-prompt design: `SensitiveActionService.authorize` creates ONE LAContext, evaluates ONCE, passes it to `keyStore.signWithAuthorization(_:context:)`. SE side honors `kSecUseAuthenticationContext` — no re-prompt. `usesStrictBiometricPolicy`, `passesContextToSign`, `doesNotUseBiometricService` source-grep tests enforce the invariant. |
| T-03-07-05 Passcode-bypass on sensitive action (would satisfy LAContext but SE ACL rejects) | `SensitiveActionService` uses `.deviceOwnerAuthenticationWithBiometrics` (strict biometric, no passcode fallback). `usesStrictBiometricPolicy` rejects both `.deviceOwnerAuthentication,` and `.deviceOwnerAuthentication)` variants in source. Source comment explains SE ACL rationale. |
| T-03-07-06 401 on `/auth/otp/verify` triggers logout (wrong-code UX broken) | `Auth401ResponseInterceptor.defaultExcludedPaths` contains both OTP paths; `otpRequestPath401Excluded` + `otpVerifyPath401Excluded` assert. |
| T-03-07-07 401 storm → repeated logout calls | Per plan: LogoutService is idempotent — `deleteAll(under:)` + `deleteKey(slot:)` both no-op on missing items; double-logout wipes-empty-keychain produces no throws. Auth401ResponseInterceptor fires one logout per 401 response observed; post-first-logout sessions have no token so subsequent 401-generating calls are unlikely. |

## Deviations from Plan

### [Rule 3 — Blocking API-level correction] Replace-then-forward instead of add-alongside for KeyStoreProtocol migration

- **Found during:** Task 1 GREEN design phase
- **Issue:** The plan's Step A described adding the NEW context-aware overload as a SECOND protocol requirement, keeping the original `signWithAuthorization(_ data: Data)` requirement in place. This would require every implementation (`SecureEnclaveKeyStore`, `SoftwareKeyStore`, any future impl) to provide BOTH methods — the old one as a trampoline to the new one with `context: nil`. That's redundant code and a footgun: implementations could diverge (e.g., someone might implement `signWithAuthorization(_:)` differently from `signWithAuthorization(_:context: nil)`).
- **Fix:** REMOVED the old single-arg declaration from the protocol body. Added the new context-aware declaration as the SOLE protocol requirement. Re-exposed the old name as a public protocol extension method that forwards to the new variant with `context: nil`. Implementations now provide ONLY the new variant; callers that use the old name resolve through the extension and get the legacy (Phase 2) SE-driven double-prompt behavior unchanged. Net zero caller impact; implementations get cleaner.
- **Files modified:** `KeyStoreProtocol.swift` (old requirement removed, extension added), `SecureEnclaveKeyStore.swift` (single impl — context-aware variant only), `SoftwareKeyStore.swift` (single impl — context-aware variant only). Same plan-intent surface; cleaner implementation.
- **Verification:** `legacySignWithAuthorizationStillWorks` test asserts the backward-compat path returns a valid DER signature using the OLD method name.
- **Committed in:** `657368b` (Task 1 GREEN).

### [Rule 3 — Blocking env correction, same as Plans 01–06] Destination substitution

- **Found during:** Task 1 build-for-testing
- **Issue:** `xcrun simctl list devices available` shows no iPhone 15 / iOS 17.5 runtime installed. Available runtimes: 15.2, 18.0–18.4, 26.2, 26.4. Project deployment target is iOS 17.0 — any iOS 17+ simulator is equivalent for verification. The currently-booted simulator is iPhone 17 Pro / iOS 26.4.
- **Fix:** All `xcodebuild` invocations used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`. Matches Plans 01–06 conventions documented in their summaries.
- **Verification:** `** TEST SUCCEEDED **` on all plan-scope suites + full regression.
- **Committed in:** N/A — test-run CLI only.

### [Rule 2 — Defensive correctness] Extended `SecureEnclaveKeyStore.loadPrivateKey` to accept an optional LAContext

- **Found during:** Task 1 GREEN — initial attempt put `kSecUseAuthenticationContext` only on an inline query inside the new `signWithAuthorization(_:context:)` method, duplicating the SecItemCopyMatching logic. This left the existing `loadPrivateKey(slot:)` path unchanged, which is fine for deviceKey signs but creates inconsistency for any future consumer that wants a context-aware load of the auth key for non-sign SecKey operations.
- **Fix:** Promoted `loadPrivateKey(slot:)` → `loadPrivateKey(slot:, context: LAContext? = nil)` and `sign(data:slot:)` → `sign(data:slot:, context: LAContext? = nil)`. The new `signWithAuthorization(_:context:)` now funnels through `sign(data: data, slot: .authorization, context: context)` — zero duplicated query boilerplate. All legacy callers (device-key `sign`, `publicKeyRepresentation`, etc.) pass the default `nil` context and exhibit unchanged Phase 2 behavior.
- **Files modified:** `SecureEnclaveKeyStore.swift` (loadPrivateKey + sign signatures extended with default-nil context).
- **Verification:** Phase 2 tests (`SoftwareKeyStoreExtendedTests`, Phase 2 device tests reachable via existing coverage) still pass. The `sePassesContextToQuery` source-grep test confirms `kSecUseAuthenticationContext` appears in SE source.
- **Committed in:** `657368b` (Task 1 GREEN).

---

**Total deviations:** 3 — (1) API-level cleaner-path on the protocol overload migration, (2) env-level destination substitution (consistent with prior plans), (3) defensive-correctness DRY on SE loadPrivateKey/sign helpers. **Impact on plan:** No scope change — all `success_criteria` + all `must_haves.truths` + all `must_haves.artifacts` satisfied as written. The replace-then-forward approach is strictly additive to the plan's intent; the default-nil context propagation is a code-quality improvement that leaves all Phase 2 paths byte-identical.

## TDD Gate Compliance

Plan frontmatter does not carry `type: tdd`, but all three tasks have `tdd="true"`. Each task followed RED → GREEN atomic commits with RED preceding GREEN in git log:

| Task | RED commit | GREEN commit | RED confirmation |
|------|-----------|--------------|-------------------|
| 1 | `6adcf26` (test) | `657368b` (feat) | Expected errors: `extra argument 'context' in call` on `signWithAuthorization(payload, context: nil)` — confirmed by `xcodebuild build-for-testing` output. |
| 2 | `529a6d5` (test) | `d67945f` (feat) | Expected errors: `cannot find type 'SensitiveActionService' in scope`, `cannot find 'DefaultSensitiveActionService' in scope` — confirmed by `xcodebuild build-for-testing` output. (Swift frontend batches files; subsequent LogoutServiceTests errors were masked by the first batch's abort but surface once the first types exist.) |
| 3 | `b6e443a` (test) | `b31aaac` (feat) | Expected errors: 6 × `cannot find 'Auth401ResponseInterceptor' in scope` — one per test that references the interceptor type. Confirmed by `xcodebuild build-for-testing` output. |

All RED commits precede their GREEN commits; `git log --oneline` verifies chronological order. No TDD gate violations.

## Known Stubs

**None introduced by this plan.** Grep for `TODO|FIXME|placeholder|coming soon|not available` across all 3 new source files returned zero matches. `SensitiveActionService` has zero call sites in M1 per D-12 (documented in source header + plan) — this is a planned-surface state, not a stub; the constructibility test is the entirety of the M1 AUTH-06 surface.

## Threat Flags

All 7 plan-defined threats were `mitigate` disposition and all 7 mitigations landed. No new threat surface introduced by this plan beyond the plan's threat_model. Plan 07 adds three new files that are all defensive teardown / single-prompt / 401-routing surfaces — no new network endpoints, no new file access patterns, no new trust boundaries. Omitting the Threat Flags flagged-rows section.

## Issues Encountered

- **Swift frontend batches error emission.** Test-file compilation errors for both `SensitiveActionServiceTests` and `LogoutServiceTests` could not appear simultaneously — the first batch to fail (SensitiveActionServiceTests) aborted the frontend before LogoutServiceTests was processed. Solution: confirm RED via the first-surfaced error, proceed to GREEN, re-run tests to verify GREEN picks up both test files. This is ordinary batch-compile behavior, not a workflow bug.
- **Xcode auto-touches pbxproj during test runs.** Each test run added ~170 lines of PBXContainerItemProxy / cache-reshuffle noise to `validationLedger.xcodeproj/project.pbxproj`. Per `parallel_execution` directive, these auto-generated changes are NOT committed; reverted via `git checkout -- validationLedger.xcodeproj/project.pbxproj` after each GREEN test run before staging files.

## User Setup Required

None. No external services, no secrets, no dashboard changes. All work is source + test edits verifiable via `xcodebuild test`.

## Next Wave Readiness

- **Plan 09 (AuthRepository + OTPViewModel — D-27 orchestration)** can proceed — step 6 of D-27 continues to use `BiometricService.evaluate(reason:fallback: .none)` to record initial `evaluatedPolicyDomainState`; does NOT touch `SensitiveActionService` (zero call sites in M1).
- **Plan 10 (Phone/OTP/BiometricLock/AnotherActiveSession VCs)** can proceed — `DefaultLogoutService` is constructible; `ProfileViewController` (the user-facing Logout entry point in Plan 10) calls `await logoutService.logout(reason: .userInitiated)`. Reason-specific copy on BiometricLockVC comes from Plan 06's `LockReason` (unrelated to `LogoutReason`).
- **Plan 11 (AppContainer composition root + SceneDelegate wiring)** can proceed — the 3 new services have locked init signatures. AppContainer constructs all three + wires `Auth401ResponseInterceptor` into `APIClient.responseInterceptors`. SceneDelegate observes `.sessionDidInvalidate`, reads `userInfo[.LogoutReasonKey]` (String), and routes per D-18.
- **Phase 4 device CI (CI-03)** — real SE single-prompt exercise needs hardware (Face ID / Touch ID round-trip). The source-grep tests (`.deviceOwnerAuthenticationWithBiometrics`, `kSecUseAuthenticationContext`, `context: ctx` pass-through) confirm the design is in place; runtime single-prompt invariant is HUMAN-UAT per VALIDATION.md.
- **Downstream verifier checks:** all plan `<verify>.automated` grep assertions pass (20/20 confirmed locally via one-shot grep script).

## Self-Check

**Files claimed created:**

- `validationLedger/Core/Auth/SensitiveActionService.swift` — FOUND
- `validationLedger/Core/Auth/LogoutService.swift` — FOUND
- `validationLedger/Core/Networking/Interceptors/Auth401ResponseInterceptor.swift` — FOUND

**Files claimed modified:**

- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — FOUND (diff +22/-3, context overload + backward-compat extension)
- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — FOUND (diff +23/-7, kSecUseAuthenticationContext + threaded context through helpers)
- `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` — FOUND (diff +10/-3, context arg intentionally ignored)
- `validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift` — FOUND (diff +59, 4 new @Tests + #filePath helper)
- `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` — FOUND (filled stub, 4 @Tests)
- `validationLedgerTests/Auth/LogoutServiceTests.swift` — FOUND (filled stub, 4 @Tests)
- `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` — FOUND (filled stub, 6 @Tests)

**Commits claimed made:**

- `6adcf26` (Task 1 RED) — FOUND in `git log --oneline -10`
- `657368b` (Task 1 GREEN) — FOUND in `git log --oneline -10`
- `529a6d5` (Task 2 RED) — FOUND
- `d67945f` (Task 2 GREEN) — FOUND
- `b6e443a` (Task 3 RED) — FOUND
- `b31aaac` (Task 3 GREEN) — FOUND

**Grep acceptance checks (all 20 plan `<verify>.automated` checks):**

All 20 grep checks confirmed PASS via one-shot verification script (see "verify" section in execution transcript):

Task 1:
- `signWithAuthorization(_ data: Data, context: LAContext?)` in KeyStoreProtocol.swift — OK
- `import LocalAuthentication` in KeyStoreProtocol.swift — OK
- `kSecUseAuthenticationContext` in SecureEnclaveKeyStore.swift — OK
- `context: LAContext?` in SoftwareKeyStore.swift — OK

Task 2:
- SensitiveActionService.swift exists — OK
- LogoutService.swift exists — OK
- `func authorize(_ payload: Data, reason: String) async throws -> Data` in SensitiveActionService.swift — OK
- `.deviceOwnerAuthenticationWithBiometrics` in SensitiveActionService.swift — OK
- `signWithAuthorization(payload, context:` in SensitiveActionService.swift — OK
- `func logout(reason: LogoutReason) async` in LogoutService.swift — OK
- `case userInitiated` in LogoutService.swift — OK
- `case auth401` in LogoutService.swift — OK
- `case anotherActiveSession` in LogoutService.swift — OK
- `sessionDidInvalidate` in LogoutService.swift — OK
- `Warning 2` in LogoutService.swift — OK

Task 3:
- Auth401ResponseInterceptor.swift exists — OK
- `struct Auth401ResponseInterceptor` in Auth401ResponseInterceptor.swift — OK
- `/auth/otp/request` in Auth401ResponseInterceptor.swift — OK
- `/auth/otp/verify` in Auth401ResponseInterceptor.swift — OK
- `logout(reason: .auth401)` in Auth401ResponseInterceptor.swift — OK

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-22*
