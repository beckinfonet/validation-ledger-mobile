---
phase: 04-app-attest-physical-device-ci-hardening
plan: 06
subsystem: auth
tags: [app-attest, dcappattest, attestation, dependency-injection, main-actor, trust-tier, biometric, test-seam]

# Dependency graph
requires:
  - phase: 04-app-attest-physical-device-ci-hardening (wave 1+2)
    provides: "AttestationService protocol, DCAppAttestAttestationService (Plan 03), SimulatorBypassAttestationService (Plan 03 file-gated), AttestedKeyStore (Plan 02), TrustTier enum (Plan 01), AttestationStatus enum (Plan 01), AttestationError (Plan 01)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    provides: "AppContainer composition-root with #if DEBUG && targetEnvironment(simulator) KeyStore gate + preflightSecureEnclave + DefaultBiometricService init(keychain:logger:)"
  - phase: 02-networking-contract-device-keys
    provides: "KeychainStore, KeyStoreProtocol dual-impl pattern that AttestationService mirrors"
  - phase: 01-foundational-conventions-scaffolding
    provides: "Logger protocol + OSLogLoggerImpl + LoggingSubsystem.auth/app"
provides:
  - "AppSession @MainActor class with mutable trustTier: TrustTier (default .softwareOnly) — single source of truth for D-12 backend-driven trust tier"
  - "AppContainer.attestationService: any AttestationService — production-vs-simulator selection via #if DEBUG && targetEnvironment(simulator) mirroring the KeyStore gate"
  - "AppContainer.session: AppSession — injection point for Plan 07 SceneDelegate heartbeat helper + Plan 08 LimitedTrustBanner"
  - "AppContainer.init(biometricServiceOverride: (any BiometricService)? = nil) — D-14 test seam so Plan 09 device tests can inject SeededBiometricService"
  - "AttestationEntitlementPreflightResult enum (available | missing | simulatorBypass)"
  - "AppContainer.preflightAttestationEntitlement(...) static — graceful-skip mirror of preflightSecureEnclave; logs + returns, does NOT fatalError"
affects:
  - 04-07 (SceneDelegate cold-boot heartbeat + didBecomeActive 24h check — reads appContainer.session.trustTier + calls appContainer.attestationService.generateAssertion)
  - 04-08 (LimitedTrustBanner render — reads appContainer.session.trustTier)
  - 04-09 (device tests — injects biometricServiceOverride = SeededBiometricService)
  - 04-10 (DevMenu "Re-attest now" — calls appContainer.attestationService.clearPersistedKeyId)

# Tech tracking
tech-stack:
  added:
    - "DeviceCheck framework (imported in AppContainer for DCAppAttestService.shared support check)"
  patterns:
    - "Dual-impl #if DEBUG && targetEnvironment(simulator) selection mirroring KeyStoreProtocol — now applied to AttestationService (production DCAppAttest vs DEBUG-only SimulatorBypass)"
    - "Main-actor mutable session state holder (AppSession class) to break AppContainer's `let`-only discipline only where reference semantics are required"
    - "Graceful-skip preflight (enum-returning static, not fatalError-ing Bool) — explicit D-09 divergence from preflightSecureEnclave's fail-fast stance, justified by entitlement misses being recoverable via re-sign/re-upload"
    - "Optional-override injection seam pattern: `paramOverride: (any Protocol)? = nil` defaults preserve existing callers, non-nil replaces the Default-constructed implementation"

key-files:
  created:
    - "validationLedger/App/AppSession.swift"
  modified:
    - "validationLedger/App/AppContainer.swift"

key-decisions:
  - "AppSession picked over struct + mutating property on AppContainer — AppContainer's `let`-only convention is preserved; trustTier needs reference semantics because Plan 07 heartbeat helper and Plan 08 banner render must share state; class + @MainActor enforces serialization without ad-hoc locks"
  - "Default trustTier = .softwareOnly (safe direction of ambiguity) — banner shows until backend confirms .hardwareAttested; brief over-showing is preferable to ever missing the banner when backend actually said softwareOnly"
  - "biometricServiceOverride parameter name + optional-with-nil-default — explicit `Override` suffix signals test seam intent; nil-default means zero changes to Phase 1/2/3 call sites; sessionLock + sensitiveAction observe the override transitively via the shared local `biometricService` binding"
  - "preflightAttestationEntitlement returns an enum (available | missing | simulatorBypass) rather than Bool — distinguishes simulator-bypass from genuine production-device availability for operational logging, and refuses to fatalError since entitlement absence is recoverable"
  - "PII discipline: Logger.LogField is a closed enum that cannot admit attestation bytes — preflight logs use fields: [:] and rely on event-name strings (`attestation_preflight_*`) alone; T-APP-ATTEST-02 mitigation enforced at the type level"
  - "Local `session` variable (URLSession return) kept — shadowing `self.session` inside init scope is syntactically safe in Swift and the rename would be churn-for-churn"

patterns-established:
  - "Pattern: optional-override injection seams — `(any Protocol)? = nil` defaults preserve callers; match found in Phase 3 `AppContainer.uiTestLocationProvider` static override; Plan 04-06 adds an instance-level variant via init parameter"
  - "Pattern: enum-returning preflight vs Bool-returning preflight — choose enum when the caller needs to log/route distinct outcomes (available/missing/simulatorBypass for attestation) vs single fail-fast branch (Secure Enclave)"
  - "Pattern: AppSession as sibling to AppContainer — mutable per-session state that outlives individual coordinators but dies with the container; future session-scoped mutable fields land here instead of polluting AppContainer"

requirements-completed: [DEV-04]

# Metrics
duration: 14min
completed: 2026-04-22
---

# Phase 4 Plan 06: AppContainer Wire-Up for Attestation + Session + Biometric Test-Seam Summary

**AppContainer composition root now selects DCAppAttestAttestationService on device/Release and SimulatorBypassAttestationService on DEBUG+simulator via the KeyStore gate analog; a new @MainActor AppSession holder carries the D-12 trustTier (default .softwareOnly); AppContainer.init accepts a biometricServiceOverride parameter so Plan 09 device tests can inject SeededBiometricService without a real Face ID prompt.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-04-22T11:46:15Z
- **Completed:** 2026-04-22T12:00:38Z
- **Tasks:** 2 of 2
- **Files created:** 1
- **Files modified:** 1

## Accomplishments

- Created `AppSession` (`@MainActor public final class`) with mutable `trustTier: TrustTier` defaulting to `.softwareOnly` — safe default means LimitedTrustBanner (Plan 08) renders until backend confirms `.hardwareAttested`
- Extended `AppContainer` with `attestationService: any AttestationService` selected via `#if DEBUG && targetEnvironment(simulator)` gate mirroring the existing KeyStore dual-impl resolver
- Extended `AppContainer` with `session: AppSession` property; constructed at end of attestation-setup block so Plan 07 heartbeat + Plan 08 banner both have a single injection point
- Added `biometricServiceOverride: (any BiometricService)? = nil` init parameter — D-14 test seam for Plan 09 device tests to inject `SeededBiometricService`; nil default preserves all existing Phase 1/2/3 call sites
- Added top-level `AttestationEntitlementPreflightResult` enum (available | missing | simulatorBypass)
- Added `AppContainer.preflightAttestationEntitlement(isSupported:isSimulatorBuild:isDebugBuild:)` static mirror of `preflightSecureEnclave` — logs but does NOT fatalError per D-09 graceful-skip
- Both simulator Debug and generic iOS Release configurations build clean — exercises both branches of the attestation selection `#if`

## Task Commits

Each task was committed atomically with `--no-verify` (parallel worktree convention):

1. **Task 1: Create AppSession.swift — main-actor mutable session state holder** — `45e1515` (feat)
2. **Task 2: Extend AppContainer with attestationService, preflightAttestationEntitlement, session, biometricServiceOverride seam** — `f5fe541` (feat)

_No TDD cycle for this plan — Task type is `auto` (composition-root wiring); behavior tests for AttestationService were landed in Plan 03; integration tests for heartbeat + banner land in Plans 07/08/09._

## Files Created/Modified

- `validationLedger/App/AppSession.swift` (NEW, 47 lines) — `@MainActor public final class AppSession` with `var trustTier: TrustTier = .softwareOnly`; referenced by `AppContainer.session`
- `validationLedger/App/AppContainer.swift` (modified, +145 / −5 lines) —
  - `import DeviceCheck` added at top for `DCAppAttestService.shared`
  - Top-level `public enum AttestationEntitlementPreflightResult: String, Sendable`
  - Two new `let` properties: `attestationService`, `session`
  - `init` gains `biometricServiceOverride: (any BiometricService)? = nil` parameter (fourth position, after `isSecureEnclaveAvailable`)
  - Biometric construction refactored from direct `DefaultBiometricService(...)` assignment to `if let override { } else { Default... }` branch
  - Attestation setup block added after `self.logoutService = logoutService` — preflight enum switch (3 log cases), `AttestedKeyStore` construction, `#if DEBUG && targetEnvironment(simulator)` gate selecting simulator-bypass vs DCAppAttest, `self.session = AppSession(trustTier: .softwareOnly)`
  - New `preflightAttestationEntitlement` static after `preflightSecureEnclave` — parameters default to `DCAppAttestService.shared.isSupported`, simulator detection, DEBUG detection; returns the enum

## Decisions Made

- **AppSession as a class (not a struct with mutating functions on AppContainer):** `AppContainer`'s property convention is `let`-only. `trustTier` must mutate on every `/device/register` + `/device/heartbeat` response. A `@MainActor final class` gives reference semantics so Plan 07 heartbeat helper + Plan 08 banner render share the mutation surface; Swift concurrency enforces main-actor isolation without ad-hoc locks.
- **Safe default `.softwareOnly`:** Direction of ambiguity favors showing the banner over missing it. Until backend confirms hardware attestation via `/device/register`, the client treats itself as untrusted.
- **Enum preflight vs Bool preflight:** Secure Enclave absence is a deterministic hardware fact → fatalError in Release is acceptable. App Attest entitlement absence is a fixable build-config issue → a fatalError would brick every installed build. D-09 routes the miss to a graceful-skip status. The enum return distinguishes simulator-bypass from genuine device availability in the log stream.
- **Override parameter name:** `biometricServiceOverride` explicitly signals test-seam intent (not general DI); `nil`-default is backward-compatible with all Phase 1/2/3 callers and tests; pattern deliberately narrower than what Swinject would offer.
- **PII discipline via closed-enum `LogField`:** The Logger's `LogField` is a `public enum LogField: Hashable, Sendable` — it does not admit `Data` or arbitrary `String`. Preflight logs pass `fields: [:]` and rely on event-name strings alone. T-APP-ATTEST-02 enforced at the type level — no developer can accidentally log entitlement contents through this boundary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator name mismatch in plan verification commands**
- **Found during:** Task 1 + Task 2 (build verification)
- **Issue:** Plan verification called `'platform=iOS Simulator,name=iPhone 15'` but only iPhone 16 family simulators are installed locally (`iPhone 16`, `iPhone 16 Pro`, `iPhone 16 Pro Max`, `iPhone 16 Plus`). `xcodebuild` would refuse the destination.
- **Fix:** Ran verification with `'platform=iOS Simulator,name=iPhone 16'` instead. No source-code change required; this is environment-specific (iPhone 15 is no longer in the default simulator catalog on this machine's Xcode 26.4 install).
- **Files modified:** none
- **Verification:** `** BUILD SUCCEEDED **` on both Debug simulator and generic iOS Release
- **Committed in:** (no source change to commit)

**2. [Rule 2 - Missing Critical] Fields-empty log call discipline**
- **Found during:** Task 2 (attestation preflight log block)
- **Issue:** The plan's illustrative code showed `logger.error(event: .init("attestation_preflight_missing"), fields: [/* safe fields — see Plan 03 PII discipline */])`, but `LogField` is a **closed** enum and there is no applicable case for an attestation-preflight outcome that would not itself be an event-name. Leaving the comment placeholder would not compile; inventing a new `LogField` case would expand the PII surface without plan authorization.
- **Fix:** All three preflight log calls use `fields: [:]` — the event-name string carries the full status (`attestation_preflight_available | attestation_preflight_missing | attestation_preflight_simulatorBypass`). This is a stronger mitigation of T-APP-ATTEST-02 than the original sketch: no developer can accidentally leak entitlement contents through the `LogField` surface because nothing structured is ever passed.
- **Files modified:** `validationLedger/App/AppContainer.swift`
- **Verification:** Builds clean; `grep -c 'attestation_preflight_' AppContainer.swift` → 3
- **Committed in:** `f5fe541` (Task 2)

**3. [Rule 2 - Missing Critical] `attestedKeyStore` + `attestationLogger` retained on simulator branch**
- **Found during:** Task 2 (attestation selection block)
- **Issue:** On the `#if DEBUG && targetEnvironment(simulator)` branch, the `let attestedKeyStore = AttestedKeyStore(...)` and `let attestationLogger = ...` locals are constructed but the simulator-bypass impl manages its own `AttestedKeyStore` internally (Plan 03 Pattern), so those locals would be unused and the compiler would warn.
- **Fix:** Added `_ = attestedKeyStore` and `_ = attestationLogger` on the simulator branch to silence the unused warning without restructuring the selection block (restructuring would split the log-category construction across two branches and double the maintenance cost if future loggers are added).
- **Files modified:** `validationLedger/App/AppContainer.swift`
- **Verification:** Clean build with no unused-variable warnings on simulator Debug
- **Committed in:** `f5fe541` (Task 2)

**4. [Deferred — out of scope] Pre-existing MockURLProtocol fixture failures surfaced during test run**
- **Found during:** Task 2 (regression test run)
- **Issue:** 13 failures across `MockURLProtocol`, `AppContainerNetworkConfigTests`, `APIClientEndpointTests`, `APIClientRateLimitTests`, `DeviceFingerprintTests` — fixtures appearing to leak across tests (returning 404/500 instead of expected fixtures).
- **Verification:** Re-ran same failing test set at the base commit (pre-Task 2 edits stashed) — SAME failures reproduce, with 14 failures at base (one fewer at HEAD likely due to ordering shuffle). Confirmed pre-existing; NOT caused by Plan 04-06's AppContainer edits.
- **Action:** Logged to `.planning/phases/04-app-attest-physical-device-ci-hardening/deferred-items.md` per GSD scope-boundary rule. Not auto-fixed — MockURLProtocol internals are not in Plan 04-06's `files_modified` scope.

---

**Total deviations:** 3 auto-fixed (1 blocking environment, 2 critical PII/compile discipline) + 1 out-of-scope deferred
**Impact on plan:** All auto-fixes preserve intent and tighten PII discipline. No scope creep. The one deferred item is unrelated to this plan's scope and pre-exists the plan's first line of code.

## TDD Gate Compliance

Plan type is `execute` (not `tdd`). No RED/GREEN/REFACTOR gates required at plan level. Per-task type is `auto` — AttestationService behavior tests were landed in Plan 03's RED/GREEN; Plan 04-06's task is composition-root wiring, not new behavior to test-drive. Integration tests for the heartbeat + banner arrive in Plans 07/08/09.

## Issues Encountered

- **Xcode simulator catalog drift:** iPhone 15 no longer present in default catalog; used iPhone 16 (Rule 3 auto-fix above). Future plans should avoid hard-coding specific simulator model names in verification commands — prefer `platform=iOS Simulator` without a name, or use the generic simulator destination.
- **Plan's illustrative log call wouldn't compile as-written:** The `fields: [/* safe fields */]` placeholder in the plan expected a structured field dictionary, but `LogField` is closed and nothing in the attestation-preflight surface maps to an existing case. Adopted stricter `fields: [:]` which is a stronger PII mitigation than the illustrative code. See Deviation #2.

## Threat Flags

No new security-relevant surface introduced beyond what's in the plan's `<threat_model>`. The AttestationService selection funnels through existing types (DCAppAttestService via Apple framework, Keychain via KeychainStore). No new network endpoints, no new file-access patterns, no new schema changes at trust boundaries.

Threat register items `T-APP-ATTEST-02` (Information_Disclosure — preflight logs) and `T-APP-ATTEST-07` (Tampering — AppSession.trustTier mutation races) were mitigated as specified:

- T-APP-ATTEST-02: `fields: [:]` on all three preflight log calls; no entitlement contents or `attestationObject` bytes can flow through the LogField closed-enum surface.
- T-APP-ATTEST-07: `AppSession` is `@MainActor public final class`; Swift concurrency enforces all mutations happen on the main actor. Plan 07 heartbeat helper + Plan 08 banner render are both `@MainActor`, so reads and writes serialize correctly.

## User Setup Required

None — no external service configuration required for this plan. Plan 04-04 (entitlement provisioning) handles App Attest entitlement setup separately.

## Next Phase Readiness

- **Plan 04-07 (SceneDelegate heartbeat):** Can now read `appContainer.session.trustTier` and call `appContainer.attestationService.generateAssertion(...)` through the composition-root single-injection-point pattern
- **Plan 04-08 (LimitedTrustBanner):** Can bind to `appContainer.session.trustTier` for conditional render; safe default `.softwareOnly` means banner shows on first launch before any backend round-trip
- **Plan 04-09 (device tests):** Can construct `AppContainer(env: ..., biometricServiceOverride: SeededBiometricService(...))` to bypass real Face ID prompts in unattended CI
- **Plan 04-10 (DevMenu re-attest):** Can call `appContainer.attestationService.clearPersistedKeyId()` via the container

## Self-Check

Verifying claims before reporting completion:

**Files:**
- `validationLedger/App/AppSession.swift` → FOUND (47 lines, `@MainActor public final class AppSession` with `var trustTier: TrustTier` default `.softwareOnly`)
- `validationLedger/App/AppContainer.swift` → FOUND (modified, +145 / −5; includes `import DeviceCheck`, `AttestationEntitlementPreflightResult` enum, `attestationService` + `session` properties, `biometricServiceOverride` init parameter, `preflightAttestationEntitlement(...)` static)

**Commits:**
- `45e1515` (Task 1: AppSession holder) → FOUND in `git log`
- `f5fe541` (Task 2: AppContainer wire-up) → FOUND in `git log`

**Builds:**
- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug` → `** BUILD SUCCEEDED **`
- `xcodebuild build -scheme validationLedger -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **` (exercises production `#else` branch)

**Acceptance grep checks (Task 2):**
- `public let attestationService: any AttestationService` → 1 (expected 1) ✓
- `session: AppSession` → 1 (expected ≥ 1) ✓
- `preflightAttestationEntitlement` → 4 (expected ≥ 2) ✓
- `AttestationEntitlementPreflightResult` → 3 (expected ≥ 1) ✓
- `biometricServiceOverride` → 5 (expected ≥ 2) ✓
- `#if DEBUG && targetEnvironment(simulator)` → 4 (expected ≥ 2: 1 existing KeyStore + 1 new attestation + doc-comment refs) ✓
- `SimulatorBypassAttestationService` → 4 (expected 1; extras are doc-comment references) ✓
- `DCAppAttestAttestationService` → 3 (expected 1; extras are doc-comment references) ✓
- `import DeviceCheck` → 1 (expected 1) ✓

**Regression:** Pre-existing MockURLProtocol fixture failures verified to reproduce at base commit (deferred per scope boundary; logged in `deferred-items.md`).

## Self-Check: PASSED

---
*Phase: 04-app-attest-physical-device-ci-hardening*
*Completed: 2026-04-22*
