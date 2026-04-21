---
phase: 01-foundational-conventions-scaffolding
plan: 03
subsystem: core
tags: [logging, keychain, keystore, session, networking, navigation, swift-testing, piiscrubber, p256, nslock]

# Dependency graph
requires:
  - phase: 01-foundational-conventions-scaffolding
    provides: Xcode project retargeted to iOS 17, UIKit-first, 3 test targets registered (Plan 01)
provides:
  - Logger protocol + LogLevel (5 cases) + LogField (10 cases) + LogEvent + Sendable extension methods
  - OSLogLoggerImpl (OSLog-backed, PIIScrubber-injected via init)
  - PIIScrubber (hybrid — structured path + string path; .coordinates removed entirely)
  - LoggingSubsystem constants (D-17 — one per Core module)
  - LogExporter (OSLogStore wrapper for Plan-05 DevMenu LogViewer)
  - KeychainKey (typed rawValue struct, sessionToken/installUUID defaults)
  - KeychainAccessibility enum (only two ThisDeviceOnly cases — type-blocks T-03-02)
  - KeychainStore (hand-rolled SecItem wrapper, set/get/delete/enumerateAll, upsert pattern)
  - KeychainWiper.wipeOnFirstLaunch(defaults:accessGroup:) — FOUND-02 first-launch contract
  - KeyStoreProtocol + SoftwareKeyStore (P256 CryptoKit, internal access) + SecureEnclaveKeyStore stub
  - SessionLockService protocol + DefaultSessionLockService (backgroundGrace=300s, NSLock)
  - DeepLinkRouter (cold→ready state machine, NSLock, FIFO drain on bootstrap)
  - NetworkClient protocol + URLSessionNetworkClient skeleton + MockURLProtocol + PinningSessionDelegate skeleton
  - Minimal UIKit @UIApplicationMain stub at validationLedger/App/validationLedgerApp.swift (Rule-1 fix)
affects:
  - 01-04 (Role shell + PrivacyInfo — will reference Core types)
  - 01-05 (AppContainer composition root — consumes every protocol here; gates SoftwareKeyStore/SecureEnclaveKeyStore via #if DEBUG && targetEnvironment(simulator))
  - 01-06 (SwiftLint 4-rule bundle — must ratify LOG-01 os_log-only-in-Core/Logging, already compliant)
  - 02-01..02-05 (Networking — fills endpoint fixtures into MockURLProtocol, wires PinningSessionDelegate dual-SPKI)
  - 03-* (Auth — calls SessionLockService.recordBiometricSuccess, extends KeychainKey set)
  - 04-* (App Attest / Device CI — SecureEnclaveKeyStore fatalError stub gets replaced)

# Tech tracking
tech-stack:
  added:
    - Swift Testing (STACK-03) — @Suite / @Test / #expect / parameterized arguments
    - CryptoKit (P256.Signing.PrivateKey) for SoftwareKeyStore
    - Security framework (SecItem*, kSecClass*) hand-rolled in KeychainStore
    - OSLog (os.Logger, OSLogStore)
    - UIKit (@UIApplicationMain launch stub — CLAUDE.md UIKit-first)
  patterns:
    - Hybrid PII scrubbing (D-16) — structured path preferred, string path as forced-route pressure valve
    - One OSLog subsystem per top-level Core/ module (D-17)
    - Upsert-style Keychain writes (SecItemAdd, fallback to SecItemUpdate on errSecDuplicateItem)
    - First-launch-wipe gated by UserDefaults("didCompleteFirstLaunch") — idempotent
    - Protocol-first Core services (every service has a protocol + Default impl)
    - NSLock-serialized mutable state for Sendable final classes
    - Bootstrap-aware queue pattern (DeepLinkRouter state = cold/ready)
    - Phase-2 stubs via fatalError for compile-time type referenceability
    - .serialized @Suite trait for tests that mutate shared system resources (Keychain, UserDefaults)

key-files:
  created:
    - validationLedger/Core/Logging/Logger.swift (45 LOC) — protocol + LogLevel + LogField + LogEvent + extensions
    - validationLedger/Core/Logging/OSLogLoggerImpl.swift (32 LOC) — OSLog-backed impl, PIIScrubber injected
    - validationLedger/Core/Logging/PIIScrubber.swift (120 LOC) — hybrid scrubber (NOVEL)
    - validationLedger/Core/Logging/Subsystems.swift (15 LOC) — D-17 subsystem constants
    - validationLedger/Core/Logging/LogExporter.swift (25 LOC) — OSLogStore wrapper
    - validationLedger/Core/Storage/Keychain/KeychainKey.swift (12 LOC)
    - validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift (18 LOC)
    - validationLedger/Core/Storage/Keychain/KeychainStore.swift (125 LOC + KeychainWiper)
    - validationLedger/Core/KeyStore/KeyStoreProtocol.swift (16 LOC)
    - validationLedger/Core/KeyStore/SoftwareKeyStore.swift (18 LOC) — internal (mitigates T-03-03)
    - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift (14 LOC) — Phase-2 stub
    - validationLedger/Core/Auth/SessionLockService.swift (40 LOC) — VERBATIM RESEARCH.md Pattern 6
    - validationLedger/Core/Networking/NetworkClient.swift (36 LOC)
    - validationLedger/Core/Networking/MockURLProtocol.swift (41 LOC)
    - validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift (22 LOC)
    - validationLedger/Core/Navigation/DeepLinkRouter.swift (45 LOC) — VERBATIM RESEARCH.md Pattern 7
    - validationLedger/App/validationLedgerApp.swift (30 LOC) — Rule-1 fix, minimal @UIApplicationMain
    - validationLedgerTests/Logging/PIIScrubberTests.swift (56 LOC) — VERBATIM RESEARCH.md Example 2
    - validationLedgerTests/Logging/LoggerLevelsTests.swift (38 LOC)
    - validationLedgerTests/Storage/KeychainStoreTests.swift (48 LOC)
    - validationLedgerTests/Storage/KeychainWipeTests.swift (50 LOC, .serialized)
    - validationLedgerTests/Auth/SessionLockServiceTests.swift (38 LOC)
    - validationLedgerTests/Navigation/DeepLinkRouterTests.swift (34 LOC)
    - validationLedgerTests/Networking/MockURLProtocolTests.swift (26 LOC)
    - .gitignore (23 LOC) — Xcode/SPM/IDE exclusions
  modified: []

key-decisions:
  - "Added minimal UIKit @UIApplicationMain stub so xcodebuild test can link (Plan 01 removed @main, which broke TEST_HOST linking — surfaced in Plan 03 as Rule-1 bug)"
  - ".serialized Swift Testing trait applied to KeychainWipeTests to prevent intra-suite Keychain wipe race (Rule-1 fix)"
  - "Simulator destination substituted iPhone 17 Pro / iOS 26.4 for plan-specified iPhone 15 / iOS 17.5 (not installed; deployment target remains iOS 17.0)"
  - "SoftwareKeyStore + SecureEnclaveKeyStore declared `final class` (internal access) — instantiation only from inside validationLedger module, satisfies T-03-03 mitigation"
  - "Novel PIIScrubber impl passes all 7 verbatim RESEARCH.md Example 2 test cases without modification (contract preserved)"

patterns-established:
  - "Protocol + Default impl pairing: every Core service exposes a protocol (public) + a DefaultXxx final class (public) backed by @unchecked Sendable + NSLock for mutable state"
  - "Phase-2 stub convention: `fatalError(\"Xxx not implemented until Phase N\")` for types that must compile today but cannot run until later"
  - "Hybrid PII scrubber: structured path preferred (O(1) per-field rule), string path as regex sweep so string-based Logger calls cannot bypass redaction"
  - "Keychain upsert: SecItemAdd → on errSecDuplicateItem → SecItemUpdate (both paths throw unified KeychainError.unexpectedStatus)"
  - "Test suite mutating shared system resources MUST declare @Suite(..., .serialized) — prevents inter-test races"

requirements-completed:
  - FOUND-01
  - FOUND-02
  - FOUND-07
  - FOUND-08
  - LOG-02
  - STACK-03
  - ARCH-03
  - SEC-03

# Metrics
duration: 69min
completed: 2026-04-21
---

# Phase 1 Plan 3: Core Services Summary

**8 Core/ modules (Logging, Storage/Keychain, KeyStore, Auth, Networking, Navigation) plus a hybrid PII scrubber and 24 Swift Testing unit tests — the protocol + test foundation that every later wave composes against.**

## Performance

- **Duration:** ~69 min
- **Started:** 2026-04-21T07:57:00Z
- **Completed:** 2026-04-21T08:06:43Z
- **Tasks:** 2
- **Files created:** 25 (17 Swift source + 7 test + .gitignore)
- **Files modified:** 0

## Accomplishments

- **FOUND-01 — Hybrid PII scrubber:** 6 redaction categories across two paths (structured dict + string regex); `.coordinates` is REMOVED entirely (not masked) per RESEARCH.md Example 2 Test 6; string path cannot bypass redaction (Test 7 is the bypass-resistance assertion).
- **FOUND-02 — KeychainWiper first-launch contract:** Testable `KeychainWiper.wipeOnFirstLaunch(defaults:accessGroup:)` deletes across all kSecClass* classes gated by `didCompleteFirstLaunch` UserDefaults flag; proven idempotent + flag-gated via 2 tests.
- **FOUND-07 — SessionLockService unified invariant:** `shouldRequireBiometric(now:)` true on cold boot OR past 5-min grace; false within grace; `invalidate()` clears state (logout path). 4 tests pass covering the full state machine.
- **FOUND-08 — DeepLinkRouter bootstrap queue:** URLs received pre-bootstrap queue in FIFO order; `bootstrapComplete()` drains the queue THEN flips state to `.ready`; post-bootstrap URLs route immediately. NSLock-serialized across threads. 3 tests verify.
- **LOG-02 — 5-level logger:** LogLevel enum with `trace=0, debug=1, info=2, warn=3, error=4`; extension methods route to base `log(_:event:fields:)` and `log(_:_:)`; SpyLogger test verifies routing.
- **STACK-03 — Swift Testing installed in practice:** 7 @Suite-decorated structs, 24 @Test functions including 1 parameterized (8 test cases with MC/DOT arguments), all passing; bare imports of `Testing` work; `@testable import validationLedger` works.
- **ARCH-03 — Simulator gate:** `SoftwareKeyStore` is `final class` (internal access) — AppContainer (Plan 05) is the only possible call site and will wrap instantiation in `#if DEBUG && targetEnvironment(simulator)` per threat T-03-03.
- **SEC-03 — Accessibility ceiling:** `KeychainAccessibility` enum exposes only two `ThisDeviceOnly` cases; never `kSecAttrAccessibleAlways`. The type system blocks T-03-02 (backup-extractable keychain items) at compile time.

## Task Commits

| # | Task | Commit | Type | Files |
|---|------|--------|------|-------|
| pre | Add .gitignore for Xcode build artifacts | `2bf13d7` | chore | `.gitignore` |
| pre | Minimal UIKit @main stub (Rule-1 deviation) | `4a71159` | fix | `validationLedger/App/validationLedgerApp.swift` |
| 1 | Core/Logging — Logger + PIIScrubber + OSLogLoggerImpl + tests | `993ca18` | feat | 5 src + 2 test = 7 files |
| 2 | Core/{Storage,KeyStore,Auth,Navigation,Networking} — protocols + impls + tests | `80a2a14` | feat | 11 src + 5 test = 16 files |

**Per-plan total commits:** 4 (1 chore, 1 fix, 2 feat). Final metadata commit added after SUMMARY.md creation.

## Test Results

Full validationLedgerTests target (run on iPhone 17 Pro / iOS 26.4 simulator):

| Suite | Tests | Status |
|-------|-------|--------|
| PIIScrubberTests (6-category redaction contract) | 7 (with 1 parameterized giving 8 cases) | all passing |
| LoggerLevelsTests (LOG-02 5-level contract) | 2 | all passing |
| KeychainStoreTests (SecItem round-trip) | 4 | all passing |
| KeychainWipeTests (FOUND-02, .serialized) | 2 | all passing |
| SessionLockServiceTests (FOUND-07 state machine) | 4 | all passing |
| DeepLinkRouterTests (FOUND-08 queue) | 3 | all passing |
| MockURLProtocolTests (scaffolding) | 2 | all passing |
| **Total** | **24 tests / 7 suites** | **24/24 passing** |

Run command: `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`

## Files Created

17 Swift source files under `validationLedger/Core/` + `validationLedger/App/`, 7 test files under `validationLedgerTests/`, plus `.gitignore`:

### Core Source (17 files)

- `validationLedger/App/validationLedgerApp.swift` — UIKit @main stub (Plan 05 replaces with full AppDelegate)
- `validationLedger/Core/Logging/Logger.swift` — protocol + LogLevel + LogField + LogEvent + extensions
- `validationLedger/Core/Logging/OSLogLoggerImpl.swift` — OSLog-backed impl, scrubber-injected
- `validationLedger/Core/Logging/PIIScrubber.swift` — hybrid scrubber (NOVEL — passes verbatim test contract)
- `validationLedger/Core/Logging/Subsystems.swift` — D-17 subsystem constants
- `validationLedger/Core/Logging/LogExporter.swift` — OSLogStore wrapper for Plan-05 DevMenu
- `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — typed keys
- `validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift` — type-safe accessibility
- `validationLedger/Core/Storage/Keychain/KeychainStore.swift` — SecItem wrapper + KeychainWiper
- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — sign + publicKeyRepresentation
- `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` — P256 CryptoKit (internal, simulator-only)
- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — Phase-2 fatalError stub
- `validationLedger/Core/Auth/SessionLockService.swift` — VERBATIM RESEARCH.md Pattern 6
- `validationLedger/Core/Networking/NetworkClient.swift` — protocol + URLSession impl
- `validationLedger/Core/Networking/MockURLProtocol.swift` — scaffolding + /ping fixture
- `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` — Phase-1 skeleton
- `validationLedger/Core/Navigation/DeepLinkRouter.swift` — VERBATIM RESEARCH.md Pattern 7

### Tests (7 files)

- `validationLedgerTests/Logging/PIIScrubberTests.swift` — VERBATIM RESEARCH.md Example 2
- `validationLedgerTests/Logging/LoggerLevelsTests.swift`
- `validationLedgerTests/Storage/KeychainStoreTests.swift`
- `validationLedgerTests/Storage/KeychainWipeTests.swift` — `.serialized` suite trait
- `validationLedgerTests/Auth/SessionLockServiceTests.swift`
- `validationLedgerTests/Navigation/DeepLinkRouterTests.swift`
- `validationLedgerTests/Networking/MockURLProtocolTests.swift`

### Other (1 file)

- `.gitignore` — Xcode build artifacts, SPM, IDE caches

## Decisions Made

- **Minimal @main stub** — Plan 01's retarget removed SwiftUI scaffold including `@main` entry, which broke `xcodebuild test` (TEST_HOST pointed at `validationLedger.app` requiring a linkable `_main` symbol). Chose minimal UIKit `@UIApplicationMain` stub with empty `didFinishLaunchingWithOptions` over: (a) reverting Plan 01 (would regress ARCH-01), (b) changing test host to nil (would hide future AppDelegate-level bugs). Plan 05 replaces the stub body with real composition-root wiring.
- **`.serialized` trait on KeychainWipeTests** — Chose Swift Testing's native `.serialized` trait over alternative scoping strategies (per-test service strings, Keychain access groups) because the wiper operates at the class level (no service scope) — scoping would misrepresent what the wiper actually does.
- **Simulator destination substitution** — The plan specifies iPhone 15 / iOS 17.5 simulator; only iOS 18.x and iOS 26.x runtimes are installed on this machine. Used `iPhone 17 Pro / iOS 26.4` (booted + available). Deployment target remains iOS 17.0 (unchanged). This substitution does not affect compile semantics; all tests exercise APIs available since iOS 17.
- **Novel PIIScrubber implementation passes verbatim test contract** — The test fixture (RESEARCH.md Example 2) is VERBATIM; the implementation body was derived to satisfy it. All 7 test cases (8 including parameterized MC/DOT) pass on first run after implementation.
- **`SoftwareKeyStore` + `SecureEnclaveKeyStore` declared internal `final class`** — Satisfies T-03-03 (SoftwareKeyStore leak into production) at the type system level: only code inside the `validationLedger` module can instantiate these. AppContainer (Plan 05) becomes the single resolver gated by `#if DEBUG && targetEnvironment(simulator)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan 01 removed `@main` entry point; `xcodebuild test` cannot link app host**

- **Found during:** Task 1 (first `xcodebuild test` run during GREEN phase)
- **Issue:** The test scheme's `TEST_HOST = $(BUILT_PRODUCTS_DIR)/validationLedger.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/validationLedger` requires the app target to produce a linkable Mach-O executable. Plan 01 (commit `c13ff3d`) deleted both `validationLedger/validationLedgerApp.swift` and `validationLedger/ContentView.swift` to satisfy ARCH-01 (no SwiftUI launch path). With no `@main`-annotated type, the linker reports: `Undefined symbols for architecture arm64: "_main"` and the test build fails before any test can run.
- **Fix:** Added a minimal UIKit `@UIApplicationMain` stub at `validationLedger/App/validationLedgerApp.swift` (30 LOC). The stub is UIKit-based (CLAUDE.md: "UIKit-first"; ARCH-01: no SwiftUI launch path), has no views/scenes/container, and documents itself as a Phase-1 Plan-5 placeholder.
- **Files modified:** Created `validationLedger/App/validationLedgerApp.swift`.
- **Verification:** After adding the stub, `xcodebuild test` links cleanly and runs all 24 tests.
- **Committed in:** `4a71159` (`fix(01-03): add minimal UIKit @main stub so test host links [Rule 1]`)

**2. [Rule 1 - Bug] KeychainWipeTests parallel execution caused Keychain wipe race**

- **Found during:** Task 2 (first full test run after Task 2 impl landed)
- **Issue:** Swift Testing runs `@Test` functions in parallel by default. `KeychainWiper.wipeOnFirstLaunch` operates at the class level (no service scope), iterating all `kSecClass*` classes and deleting every item on the shared system Keychain. The two KeychainWipe tests share `UserDefaults.standard["didCompleteFirstLaunch"]` and the Keychain; when `wipeOnFirstLaunch` ran concurrently with `wipeNoOpWhenFlagSet`, the first test's wipe deleted the second test's seed key mid-flight, causing `store.get(key)` in the second test to throw `.itemNotFound` (1 test fail out of 15).
- **Fix:** Added `.serialized` trait to `@Suite("KeychainWipe — FOUND-02 enumerate-before-delete contract", .serialized)`. Within the suite, tests now run one-at-a-time. No change to `KeychainWiper` semantics (it's intentionally broad — first-launch semantics require wiping everything).
- **Files modified:** `validationLedgerTests/Storage/KeychainWipeTests.swift` (added `.serialized` + explanatory comment).
- **Verification:** Re-ran `KeychainWipeTests` — both tests pass in 0.04s. Full suite rerun — 24/24 pass.
- **Committed in:** `80a2a14` (Task 2 commit — both the test file and fix landed together)

**3. [Rule 3 - Blocking] Simulator destination substitution (iPhone 15 / iOS 17.5 unavailable)**

- **Found during:** Task 1 (first `xcodebuild test` invocation)
- **Issue:** The plan's verification command specifies `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. Only iOS 18.x (iPhone 16 family, iPhone SE 3rd gen) and iOS 26.x (iPhone 17 Pro family) simulator runtimes are installed on this machine. iOS 17.x is not installed.
- **Fix:** Substituted `iPhone 17 Pro / iOS 26.4` (already booted, latest available, above the iOS 17.0 deployment target). Installing an iOS 17 simulator runtime (~5GB) was deemed out of scope for this plan — Plan 07 (CI hardening) will standardize a pinned simulator version.
- **Files modified:** None (build-command substitution only).
- **Verification:** `xcodebuild -version` reports `Xcode 26.4`; `xcrun simctl list devices available` shows `iPhone 17 Pro` booted on `iOS 26.4`; target build succeeds with `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (deployment target unchanged).
- **Committed in:** `993ca18` (Task 1 commit — discovery documented in the commit body's deviation note)

---

**Total deviations:** 3 auto-fixed (2 Rule-1 bugs, 1 Rule-3 blocking). No Rule-4 architectural changes.

**Impact on plan:** All three deviations were necessary for correctness or execution; none changed plan scope. Deviation #1 unblocks all future test execution for Phase 1+, not just this plan. Deviation #2 reveals a design consideration for the Plan-05 AppDelegate (its `KeychainWiper.wipeOnFirstLaunch` call is OK because AppDelegate runs once; tests exercising shared system state must use `.serialized`). Deviation #3 is environmental and will be revisited in Plan 07.

## Issues Encountered

- None beyond the three deviations documented above.

## Authentication Gates

- None — all work in this plan is local to the simulator (no network, no backend credentials, no secrets).

## User Setup Required

- None — no external service configuration is required for Plan 03.

## Known Stubs

These files are intentional Phase-1 stubs with clear upgrade paths. Flagged for verifier awareness:

| File | Stub Type | Reason | Resolved In |
|------|-----------|--------|-------------|
| `validationLedger/App/validationLedgerApp.swift` | Rule-1 stub: minimal UIKit AppDelegate with empty `didFinishLaunchingWithOptions` | Plan 01 removed `@main`; needed so test host links. No views shown. | Plan 05 (AppContainer composition root) |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | Phase-2 fatalError stub | Needed so AppContainer `#else` branch compiles; real SEP-backed signing lands Phase 2 (DEV-01/02/03) | Phase 2 |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | In-memory P256 — simulator/DEBUG only | Plan-defined; production always uses SecureEnclaveKeyStore | N/A (keeps its role; simply gated by AppContainer) |
| `validationLedger/Core/Networking/NetworkClient.swift` — `URLSessionNetworkClient` | Skeleton (no retry, no baseURL resolution, no headers) | Real M1 endpoint typing is Phase 2 NET-01..NET-05 | Phase 2 |
| `validationLedger/Core/Networking/MockURLProtocol.swift` | Single /ping fixture | Per A4 Flag #4 — real OTP/register/upload fixtures Phase 2 | Phase 2 |
| `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` | Skeleton — `performDefaultHandling` (NO pinning yet) | Phase 2 adds dual-SPKI validation per PITFALLS P3 / SEC-01 | Phase 2 |
| `validationLedger/Core/Navigation/DeepLinkRouter.swift` — `private func route(_:)` | No-op body | Real handlers land Phase 3 (SHELL-*) and M3 (push + universal links) | Phase 3 / M3 |

These stubs are DOCUMENTED in the plan (every one is listed in the plan's acceptance criteria or `must_haves.truths`). None are accidental; all are intentional Phase-1 surface area for compile-time cohesion.

## Deferred Work for Plan 05 (AppContainer)

Plan 05 MUST:

1. **Replace the @main stub body** — `validationLedger/App/validationLedgerApp.swift` currently returns `true` with no work. Plan 05 wires:
   - `KeychainWiper.wipeOnFirstLaunch(defaults: .standard)` BEFORE any service resolves
   - `AppContainer.resolve()` (composition root)
   - `RoleCoordinator.bootstrap()` (post-Plan-04)
   - `DeepLinkRouter.bootstrapComplete()` AFTER coordinator is ready
2. **Wrap MockURLProtocol registration in `#if DEBUG`** — threat T-03-05 notes: MockURLProtocol lives in the app target (necessary for AppContainer swap); Plan 05's AppContainer is the enforcement point. Acceptance: `grep "MockURLProtocol.register" validationLedger/App/` must be inside a `#if DEBUG` block in Plan 05.
3. **Gate SoftwareKeyStore vs SecureEnclaveKeyStore** — per ARCH-03 + T-03-03: `#if DEBUG && targetEnvironment(simulator)` → `SoftwareKeyStore()`; `#else` → `guard SecureEnclave.isAvailable else { fatalError } ; SecureEnclaveKeyStore()` (the guard prevents reaching Phase-2 stub fatalError on production devices without SEP).
4. **Inject PIIScrubber (and Logger) into service initializers** — Plan 03 ships default instances; Plan 05 wires them via AppContainer so production and test code get the right scrubber.

## TDD Gate Compliance

Plan 03 is marked `type: execute` (not `type: tdd` at the plan level). Both tasks are `type="auto" tdd="true"`, executed as RED → GREEN (no REFACTOR needed — implementations were correct on first run after test fixture settled). Commits follow the `test/feat` split only for Task-2's deviation fix (the `.serialized` trait change landed in the Task-2 feat commit alongside the test + impl, since it was a test-file fix coupled to the concurrency model). For Task 1, tests and impl were bundled into a single `feat(01-03)` commit per the plan's commit-message specification.

## Self-Check: PASSED

Verified existence of all 25 created files and all 4 commit hashes.

- **Files check:** `validationLedger/App/validationLedgerApp.swift`, `Logger.swift`, `OSLogLoggerImpl.swift`, `PIIScrubber.swift`, `Subsystems.swift`, `LogExporter.swift`, `KeychainKey.swift`, `KeychainAccessibility.swift`, `KeychainStore.swift`, `KeyStoreProtocol.swift`, `SoftwareKeyStore.swift`, `SecureEnclaveKeyStore.swift`, `SessionLockService.swift`, `NetworkClient.swift`, `MockURLProtocol.swift`, `PinningSessionDelegate.swift`, `DeepLinkRouter.swift`, 7 test files, and `.gitignore` — all exist.
- **Commits check:** `2bf13d7` (.gitignore), `4a71159` (@main stub), `993ca18` (Task 1), `80a2a14` (Task 2) — all present in `git log HEAD ^2b664ce`.
- **Tests check:** `xcodebuild test -only-testing:validationLedgerTests` → `** TEST SUCCEEDED **`; 24 tests across 7 suites, all passing.
- **Acceptance criteria:** All 17 static AC + 10 test-run AC from Tasks 1+2 verified green.
- **Forbidden imports check:** Zero occurrences of `Alamofire|KeychainAccess|XCoordinator|Sentry|Firebase|Crashlytics|SwiftUI` in `validationLedger/Core/`.

## Next Phase Readiness

- **Plan 01-04 (Role shell + PrivacyInfo) READY** — can reference any Core service protocol by import of `validationLedger` module.
- **Plan 01-05 (AppContainer composition root) READY** — every protocol it needs to wire is now in place; stub `@main` gives Plan 05 a clear replacement target; "Deferred Work for Plan 05" section above is the concrete checklist.
- **Plan 01-06 (SwiftLint rule bundle) READY** — current Core/ code is already LOG-01 compliant (no `os_log(` outside `Core/Logging/`); verified via grep.
- **Plan 01-07 (CI workflows) NEEDS:** pinned simulator version decision (Plan 03 used iPhone 17 Pro / iOS 26.4 ad-hoc; CI must pin explicitly).
- **Phase 2 (Networking + Device Keys):** `NetworkClient`, `MockURLProtocol`, `PinningSessionDelegate`, `KeyStoreProtocol` skeletons are ready for Phase-2 expansion.

---

*Phase: 01-foundational-conventions-scaffolding*
*Plan: 03*
*Completed: 2026-04-21*
