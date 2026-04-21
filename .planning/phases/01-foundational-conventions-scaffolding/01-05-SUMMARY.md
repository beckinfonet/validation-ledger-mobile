---
phase: 01-foundational-conventions-scaffolding
plan: 05
subsystem: app-composition-root

tags: [app, composition-root, devmenu, uikit, debug-only, appdelegate, scenedelegate, appcontainer, appcoordinator, ios17, adr-0002]

# Dependency graph
requires:
  - phase: 01-01
    provides: iOS-17-retargeted Xcode project, UIKit-first, PBXFileSystemSynchronizedRootGroup auto-inclusion, 3 test targets, deployment target = iOS 17
  - phase: 01-03
    provides: Logger/OSLogLoggerImpl/LoggingSubsystem, KeychainStore/KeychainWiper/KeychainKey, KeyStoreProtocol/SoftwareKeyStore/SecureEnclaveKeyStore stub, SessionLockService/DefaultSessionLockService, NetworkClient/URLSessionNetworkClient/MockURLProtocol, DeepLinkRouter, LogExporter
  - phase: 01-04
    provides: Role enum (5 cases), RoleCoordinator protocol, 5 UITabBarController subclasses (Shipper/Broker/Carrier/Dispatch/Factoring), ATS-strict Info.plist with UISceneDelegateClassName wiring, PrivacyInfo.xcprivacy in built .app bundle
provides:
  - "AppDelegate: UIKit @main (UIResponder + UIApplicationDelegate). Calls KeychainWiper.wipeOnFirstLaunch synchronously BEFORE AppContainer resolves (D-20 invariant)."
  - "SceneDelegate: UIWindowSceneDelegate. Owns presentRoot(_:) root-swap mechanism (D-10 / ADR 0002 — fresh AppContainer + AppCoordinator per role change). Hosts DEBUG-only shake responder (motionEnded) that calls AppCoordinator.presentDevMenu(). Forwards URLOpenContext to DeepLinkRouter."
  - "AppContainer: initializer-DI composition root (ARCH-04 — no .shared, no Swinject). Gates KeyStore selection via #if DEBUG && targetEnvironment(simulator) → SoftwareKeyStore; #else → guard SecureEnclave.isAvailable else fatalError; SecureEnclaveKeyStore (Pitfall P8 / T-05-03). MockURLProtocol registration wrapped in #if DEBUG (T-03-05 mitigation carried forward from Plan 03 deferred list)."
  - "AppCoordinator: resolves AppPhase (.launch/.auth/.role(_:)) to a root UIViewController; presentDevMenu() is #if DEBUG; emits app_coordinator_init / app_coordinator_deinit logs for ADR-0002 observability."
  - "Environment.swift: Phase-1 minimal config (.current = Environment(name:keychainAccessGroup:nil,apiBaseURL:nil)); #if DEBUG debug branch vs #else release branch."
  - "AppPhase enum declared in SceneDelegate.swift (.launch / .auth / .role(Role)) — public so future Phase 3 AuthCoordinator can construct."
  - "DevMenuViewController: 3-section table root (Role Switcher / Keychain Inspector / Log Viewer) per D-11. Entirely #if DEBUG gated."
  - "RoleSwitcherViewController: Role.allCases table → SceneDelegate.presentRoot(.role(_:)) root swap (D-07 demo)."
  - "KeychainInspectorViewController: KeychainStore.enumerateAll() — FOUND-02 fresh-install visual proof (0 items expected)."
  - "LogViewerViewController: LogExporter.fetch(since: 15*60) OSLogStore viewer — LOG-03."
  - "DevMenuShakeResponder.swift: marker file; actual shake wiring is in SceneDelegate.motionEnded per D-14 path-consistency reservation."
affects:
  - 01-06 (SwiftLint — can now lint against real AppDelegate/SceneDelegate/DevMenu code)
  - 01-07 (CI — can now wire xcodebuild build + xcodebuild test against a compilable + linkable app target)
  - 02-* (Phase 2 Networking — URLSessionNetworkClient config swap from .mock to .live(baseURL:); MockURLProtocol registration is already DEBUG-gated)
  - 03-* (Phase 3 Auth/Shell — AppCoordinator adds AuthCoordinator for AppPhase.auth; LaunchCoordinator for AppPhase.launch; callbacks onRoleResolved/onLogout already wired)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@main on UIKit AppDelegate (not SwiftUI App) — ARCH-01 anchor pattern; Plan-03's @UIApplicationMain stub was replaced with @main (iOS 14+ idiom)."
    - "Initializer-DI composition root in a single final class (AppContainer); every Core service is a stored property with an explicit initializer argument — no @propertyWrapper DI, no static .shared accessors, no Swinject-style locator. Satisfies ARCH-04 at the type system level (SwiftLint Plan 06 will enforce via custom rule: no-shared-in-App-slash)."
    - "Single-strong-reference root-swap pattern (ADR 0002): SceneDelegate holds exactly one `appCoordinator: AppCoordinator?` reference. Assigning a new coordinator orphans the old one — ARC deallocates on next runloop tick. Deinit logs (`app_coordinator_deinit`, `app_container_deinit`) are the empirical proof surface."
    - "File-level #if DEBUG gating (D-13 enforcement pattern): every DevMenu file has `#if DEBUG` at line 1 and `#endif` as last non-blank line. Release builds compile zero bytes of DevMenu code — proven via `strings` grep on the Release .app binary (0 matches for DevMenu|LogViewer|RoleSwitcher|KeychainInspector)."
    - "AppPhase enum type-driving root VC resolution (AppCoordinator.makeRoot(for:)). Plan 3 adds AppPhase.launch launch-screen handler; Phase 3 replaces AppPhase.auth placeholder with real OTP flow."
    - "Shake-gesture discoverability (D-12/D-13): UIResponder.motionEnded override in SceneDelegate is DEBUG-only; physical-device shake AND simulator `Device → Shake` (`Ctrl+Cmd+Z`) both trigger it."
    - "SceneDelegate class name auto-discovery via Info.plist `UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).SceneDelegate` (wired by Plan 04). UIKit resolves `validationLedger.SceneDelegate` at scene creation; no programmatic registration needed."

key-files:
  created:
    - "validationLedger/App/AppDelegate.swift (32 LOC) — @main UIResponder/UIApplicationDelegate; KeychainWiper.wipeOnFirstLaunch before AppContainer resolves"
    - "validationLedger/App/SceneDelegate.swift (73 LOC) — UIWindowSceneDelegate; presentRoot(_:) root-swap; AppPhase enum; DEBUG-only motionEnded shake responder; openURLContexts deep-link forwarding"
    - "validationLedger/App/AppContainer.swift (59 LOC) — initializer-DI composition root; #if DEBUG && targetEnvironment(simulator) KeyStore gate; MockURLProtocol DEBUG-gated; deinit observability"
    - "validationLedger/App/AppCoordinator.swift (67 LOC) — AppPhase → root VC; DEBUG presentDevMenu; init/deinit logs"
    - "validationLedger/App/Environment.swift (27 LOC) — Phase-1 minimal Environment with DEBUG/Release .current static"
    - "validationLedger/App/DevMenu/DevMenuViewController.swift (93 LOC) — 3-section DevMenu root (D-11)"
    - "validationLedger/App/DevMenu/RoleSwitcherViewController.swift (42 LOC) — Role.allCases → D-10 root swap"
    - "validationLedger/App/DevMenu/KeychainInspectorViewController.swift (71 LOC) — enumerateAll visual proof (FOUND-02)"
    - "validationLedger/App/DevMenu/LogViewerViewController.swift (54 LOC) — OSLogStore viewer (LOG-03)"
    - "validationLedger/App/DevMenu/DevMenuShakeResponder.swift (13 LOC) — marker file (D-14 path consistency)"
  modified: []
  deleted:
    - "validationLedger/App/validationLedgerApp.swift — the Plan-03 Rule-1 UIKit @UIApplicationMain stub; replaced entirely by AppDelegate.swift + SceneDelegate.swift (Plan 03 SUMMARY explicitly scheduled this deletion under 'Deferred Work for Plan 05 → Replace the @main stub body')"

key-decisions:
  - "Kept AppCoordinator.container as `internal` (implicit module access) rather than `private` — removed the shim extension at the bottom of SceneDelegate.swift that the plan's verbatim sketch included but then explicitly called 'awkward'. Per plan's 'Important fix' note, using internal access is cleaner and sufficient."
  - "Used `@main` on AppDelegate (iOS 14+ idiom) rather than `@UIApplicationMain` (legacy). `@main` is the official Swift-language attribute post-iOS-14 and is what Xcode templates emit today. Plan-03's stub used `@UIApplicationMain`; this plan replaces with `@main`."
  - "Simulator destination substituted `iPhone 17 Pro / iOS 26.4` for the plan's `iPhone 15 / iOS 17.5` — no iOS 17.5 simulator runtime is installed on this machine (inherited deviation from Plan 01's deferred user-setup step; documented in Plan 03 + Plan 04 SUMMARies). iOS 26.4 is ABI-compatible with the iOS 17 deployment target; all 30 tests pass."
  - "Release build verification uses `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` to permit unsigned Release build (no Apple Developer team configured in this worktree). Build compilation alone is what validates D-13 #if DEBUG gating; strings-grep on the unsigned binary is equally valid for the T-05-02 mitigation check."
  - "Plan's Task 1 AC#11 (xcodebuild build exits 0) is not verifiable standalone in Debug configuration — AppCoordinator.presentDevMenu() is `#if DEBUG` gated and references DevMenuViewController from Task 2. Committed Task 1 code-only first, then verified build after Task 2 landed. This is a sequencing note, not a deviation — the plan's Verification section (plan-wide) expects both tasks to have landed by the time `xcodebuild build` runs."
  - "Task 3 (checkpoint:human-verify) cannot be fully executed by the parallel executor — manual simulator interaction (Device → Shake, tap sequence, visual tab-title verification) requires the user. Automated portion (build + tests + strings-grep on Release) completed; manual 8-step checklist documented below for the user."

patterns-established:
  - "ARCH-04 at the type system: no .shared anywhere under validationLedger/App/. Plan 06 SwiftLint will codify."
  - "D-13 proven empirically: strings validationLedger.app/validationLedger | grep -iE 'DevMenu|LogViewer|RoleSwitcher|KeychainInspector' returns 0 matches on a Release build. Plan 07 CI can add this as a pre-archive check."
  - "ADR 0002 observability contract: `app_coordinator_init`, `app_coordinator_deinit`, `app_container_init`, `app_container_deinit` OSLog events on subsystem `com.maldin.validationLedger.app`/category `bootstrap`. Plan 07 CI OSLog smoke test can assert init-deinit-init-deinit sequence on a role swap."
  - "AppPhase enum pattern: add a case + an AppCoordinator.makeRoot handler when a new top-level app phase appears (Phase 3 replaces the .auth placeholder, M3 adds .deepLinkLoading or similar if needed for universal-link resolution)."
  - "Weak-capture coordinator callback wiring (SceneDelegate.presentRoot sets onRoleResolved / onLogout with [weak self]) — avoids the retain cycle SceneDelegate → AppCoordinator → closure → SceneDelegate that would break ADR 0002 deterministic dealloc."

requirements-completed:
  - ARCH-01   # @main on UIKit AppDelegate; zero SwiftUI imports under validationLedger/App/
  - ARCH-04   # initializer-DI composition root; no .shared anywhere in App/
  - ARCH-06   # ARCH-06 role-swap mechanism now end-to-end wired (SceneDelegate.presentRoot(.role(_:)) allocates fresh AppContainer + AppCoordinator); D-07 full dev-menu demo delivered via DevMenu
  - FOUND-02  # KeychainWiper.wipeOnFirstLaunch invoked from AppDelegate BEFORE AppContainer resolves (D-20 invariant wired at the one place it can be)
  - LOG-03    # OSLogStore viewer shipped (LogViewerViewController, DEBUG-only)
  - ARCH-03   # App/DevMenu/ subtree under validationLedger/App/; no cross-layer imports (DevMenu imports Core/Roles, not Features — correct per the module layout table)

# Metrics
duration: 5m 21s
completed: 2026-04-21
---

# Phase 1 Plan 5: App Composition Root + DevMenu Summary

**Ships the UIKit composition root (AppDelegate + SceneDelegate + AppContainer + AppCoordinator + Environment + AppPhase enum) plus the full DEBUG-only DevMenu subtree (RoleSwitcher + KeychainInspector + LogViewer + DevMenuShakeResponder marker) — 10 Swift files under `validationLedger/App/` that deliver the FIRST fully-linking-and-launching `xcodebuild build` since Plan 01 retargeted the project, unblock all 30 unit tests (24 Plan-03 + 6 Plan-04 RoleCoordinator) that previously failed with `Undefined symbols: _main`, and empirically prove D-13 compile-out via a zero-match `strings` grep on the Release binary.**

## Performance

- **Duration:** 5m 21s
- **Started:** 2026-04-21T08:17:44Z
- **Completed:** 2026-04-21T08:23:05Z
- **Tasks:** 2 fully executed; Task 3 (checkpoint) — automated sub-steps completed, 8-step manual simulator verification pending user.
- **Files created:** 10 (5 composition-root + 5 DevMenu)
- **Files modified:** 0
- **Files deleted:** 1 (Plan-03 Rule-1 stub `validationLedgerApp.swift` — explicitly scheduled for deletion in Plan 03 SUMMARY's "Deferred Work for Plan 05" section)

## Task Commits

| # | Task | Commit | Type | Files |
|---|------|--------|------|-------|
| 1 | App composition root — AppDelegate + SceneDelegate + AppContainer + AppCoordinator + Environment | `d90bb70` | feat | 5 created + 1 deleted |
| 2 | App/DevMenu — RoleSwitcher + KeychainInspector + LogViewer (DEBUG-only) | `2173a12` | feat | 5 created |

**Per-plan commits so far:** 2 (both `feat`). Final metadata commit (this SUMMARY.md) will follow.

## Accomplishments

- **ARCH-01 delivered end-to-end:** `@main` is now on a UIKit `AppDelegate: UIResponder, UIApplicationDelegate`. Zero SwiftUI imports anywhere under `validationLedger/App/` — verified by `grep -rq "import SwiftUI" validationLedger/App/` returning zero.
- **ARCH-04 delivered end-to-end:** `AppContainer` is an initializer-DI composition root. Zero `.shared` references anywhere under `validationLedger/App/` — verified by grep. Every Core service (Logger, KeychainStore, KeyStoreProtocol, SessionLockService, NetworkClient, DeepLinkRouter) is constructed in `AppContainer.init(env:)` and held as a stored property.
- **ARCH-06 delivered end-to-end (D-07 full demo wire):** `SceneDelegate.presentRoot(_:)` allocates a fresh `AppContainer` + `AppCoordinator` per role change. The old coordinator deterministically deallocates via ARC on next runloop (ADR 0002). Deinit logging (`app_coordinator_deinit`, `app_container_deinit`) emits on subsystem `com.maldin.validationLedger.app`/category `bootstrap` for observability; user's manual Task 3 step 4 will empirically confirm the sequence in the Xcode console.
- **FOUND-02 wire:** `AppDelegate.application(_:didFinishLaunchingWithOptions:)` calls `KeychainWiper.wipeOnFirstLaunch(defaults: .standard, accessGroup: nil)` synchronously BEFORE SceneDelegate constructs the first `AppContainer`. D-20 invariant enforced by placement (the only place it CAN run). `KeychainInspectorViewController` provides the visual verification surface — fresh install should show 0 items.
- **LOG-03 wire:** `LogViewerViewController` (DEBUG-only) pulls the last 15 minutes of OSLog entries via `LogExporter.fetch(since:)`. Entries are already PII-scrubbed (PIIScrubber ran before they reached OSLog via `OSLogLoggerImpl.log(_:event:fields:)`).
- **ARCH-03 wire:** All 10 new files live under `validationLedger/App/` per the Phase-1 module table. DevMenu subtree lives at `validationLedger/App/DevMenu/` per D-14.
- **Pitfall P8 / T-05-03 mitigation:** `AppContainer`'s `#else` branch has `guard SecureEnclave.isAvailable else { fatalError(...) }`. Production devices without SEP refuse to launch — no silent fallback to SoftwareKeyStore.
- **T-05-02 mitigation (D-13 physical absence) proven empirically:** `strings` on the built Release `.app` binary returns 0 matches for `DevMenu|LogViewer|RoleSwitcher|KeychainInspector`. The `#if DEBUG` file-level gating compiles zero bytes of DevMenu code into Release.
- **T-03-05 mitigation carried forward from Plan 03:** `MockURLProtocol` registration in `AppContainer` is wrapped in `#if DEBUG` so Release builds never include the mock transport in the URLSession protocol chain.
- **First fully-linking `xcodebuild test`:** 30 tests across 8 suites all pass — 24 from Plan 03 (Logging/Storage/Auth/Navigation/Networking) + 6 from Plan 04 (RoleCoordinator — previously blocked per Plan 04 SUMMARY's deviation #2 "transitive `_main` dependency on Plan 05"). Plan 04's deferred test execution is now unblocked.

## Files Created (10 files)

### Composition Root (Task 1 — 5 files, 258 LOC total)

- `validationLedger/App/AppDelegate.swift` (32 LOC) — `@main`; UIKit lifecycle; `KeychainWiper.wipeOnFirstLaunch` synchronous invocation; `UISceneConfiguration(name: "Default Configuration", ...)` — matches Info.plist scene manifest (wired by Plan 04).
- `validationLedger/App/SceneDelegate.swift` (73 LOC) — `UIWindowSceneDelegate`; `AppPhase` enum; `presentRoot(_:)` single-strong-reference root-swap; DEBUG `motionEnded` shake responder; `openURLContexts` deep-link forwarding to `DeepLinkRouter`.
- `validationLedger/App/AppContainer.swift` (59 LOC) — `final class AppContainer`; stored properties for all 6 Core services; `#if DEBUG && targetEnvironment(simulator)` KeyStore gate; `#if DEBUG` MockURLProtocol registration; `deinit` emits `app_container_deinit`.
- `validationLedger/App/AppCoordinator.swift` (67 LOC) — `final class AppCoordinator`; internal `container` field; `AppPhase → root UIViewController` resolver; `#if DEBUG func presentDevMenu()`; init/deinit logs.
- `validationLedger/App/Environment.swift` (27 LOC) — `public struct Environment: Sendable`; `static let current` with `#if DEBUG` branch.

### DevMenu Subtree (Task 2 — 5 files, 273 LOC total, all #if DEBUG gated)

- `validationLedger/App/DevMenu/DevMenuViewController.swift` (93 LOC) — 3-section `UITableViewController` root.
- `validationLedger/App/DevMenu/RoleSwitcherViewController.swift` (42 LOC) — `Role.allCases` table; calls `SceneDelegate.presentRoot(.role(_:))`.
- `validationLedger/App/DevMenu/KeychainInspectorViewController.swift` (71 LOC) — `KeychainStore.enumerateAll()` table.
- `validationLedger/App/DevMenu/LogViewerViewController.swift` (54 LOC) — `LogExporter.fetch(since: 15*60)` → monospaced `UITextView`.
- `validationLedger/App/DevMenu/DevMenuShakeResponder.swift` (13 LOC) — marker enum (actual shake logic is in `SceneDelegate.motionEnded`; file kept for D-14 path consistency).

## Files Deleted (1 file)

- `validationLedger/App/validationLedgerApp.swift` — the Plan-03 Rule-1 auto-fix stub (`@UIApplicationMain` with empty `didFinishLaunchingWithOptions`). Explicitly scheduled for deletion in Plan 03 SUMMARY's "Deferred Work for Plan 05 → 1. Replace the @main stub body" checklist. Replaced entirely by the new `AppDelegate.swift` + `SceneDelegate.swift` composition root.

## Acceptance Criteria Verification

### Task 1 (5 composition-root files)

- [x] #1: `AppDelegate.swift` exists, contains `@main` and `UIApplicationDelegate` — grep PASS
- [x] #2: `KeychainWiper.wipeOnFirstLaunch` in `AppDelegate.swift` (D-20 wired) — grep PASS
- [x] #3: No `import SwiftUI` in `AppDelegate.swift` or `SceneDelegate.swift` (ARCH-01) — grep PASS
- [x] #4: `SceneDelegate.swift` contains `UIWindowSceneDelegate` and `func presentRoot` — grep PASS
- [x] #5: `SceneDelegate.swift` has `#if DEBUG` and `motionEnded` (D-12/D-13 shake gesture) — grep PASS
- [x] #6: `AppContainer.swift` has `SecureEnclave.isAvailable` and `#if DEBUG && targetEnvironment(simulator)` (Pitfall P8) — grep PASS
- [x] #7: No `.shared` in `AppContainer.swift` (ARCH-04 — no singletons) — grep PASS (0 matches across all of `validationLedger/App/`)
- [x] #8: `AppCoordinator.swift` contains `rootViewController` — grep PASS
- [x] #9: All 5 TabBarController names (Shipper/Broker/Carrier/Dispatch/Factoring) in `AppCoordinator.swift` — grep PASS
- [x] #10: `Environment.swift` has `static let current` — grep PASS
- [x] #11: `xcodebuild build -destination 'iPhone 17 Pro / iOS 26.4' -configuration Debug` — **BUILD SUCCEEDED** (verified after Task 2 landed DevMenu; AppCoordinator.presentDevMenu references DevMenuViewController inside `#if DEBUG`)
- [x] #12: `xcodebuild test -only-testing:validationLedgerTests` — **TEST SUCCEEDED**, 30 tests in 8 suites, all green
- [~] #13: Manual simulator launch verification — **Pending user** (Task 3 step 2)

### Task 2 (5 DevMenu files)

- [x] #1: All 5 DevMenu files exist (DevMenuViewController, DevMenuShakeResponder, RoleSwitcherViewController, KeychainInspectorViewController, LogViewerViewController) — file-existence loop PASS
- [x] #2: Every DevMenu file has `#if DEBUG` at top (within first 10 lines) and `#endif` as last non-blank line — loop PASS for all 5 files
- [x] #3: `Role.allCases` in `RoleSwitcherViewController.swift` — grep PASS
- [x] #4: `enumerateAll` in `KeychainInspectorViewController.swift` — grep PASS
- [x] #5: `LogExporter` in `LogViewerViewController.swift` — grep PASS
- [x] #6: Debug build succeeds — **BUILD SUCCEEDED** on iPhone 17 Pro / iOS 26.4
- [x] #7: Release build succeeds (DevMenu `#if DEBUG` gating compiles out cleanly) — **BUILD SUCCEEDED** on generic/platform=iOS, code-signing disabled. Release binary `strings` grep for DevMenu|LogViewer|RoleSwitcher|KeychainInspector: **0 matches** (T-05-02 / D-13 empirically confirmed)
- [~] #8: Manual shake-gesture DevMenu reveal + 3-section navigation — **Pending user** (Task 3 steps 3-7)

### Task 3 (Checkpoint — 8-step manual verification)

- [x] Step 1 automated portion: `xcodebuild build` exit 0 (both Debug iPhone 17 Pro/iOS 26.4 and Release generic/platform=iOS)
- [~] Step 2: Manual — user runs from Xcode on iPhone 17 Pro simulator and confirms 4-tab launch
- [~] Step 3: Manual — user shakes, confirms DevMenu presents
- [~] Step 4: Manual — user taps Role Switcher → Broker, confirms tab change + Xcode console deinit logs
- [~] Step 5: Manual — user swaps through all 5 roles, confirms per-role tab inventories
- [~] Step 6: Manual — user opens Keychain Inspector, confirms 0 items on fresh install
- [~] Step 7: Manual — user opens Log Viewer, confirms bootstrap log entries visible
- [~] Step 8: Manual — user injects test PII log, confirms `+14155550129` is masked to `+1415•••0129`

## Build + Test Evidence

### Debug build (Task 1 AC#11, Task 2 AC#6)

Command:
```
xcodebuild build -project validationLedger.xcodeproj -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -configuration Debug
```

Result: `** BUILD SUCCEEDED **`

Built `.app` bundle contents (at `DerivedData/.../Build/Products/Debug-iphonesimulator/validationLedger.app`):
```
__preview.dylib
_CodeSignature
en.lproj
Info.plist
PkgInfo
PrivacyInfo.xcprivacy
validationLedger         ← Mach-O 64-bit executable arm64 (first time linking succeeds since Plan 01!)
validationLedger.debug.dylib
```

### Unit tests (Task 1 AC#12)

Command:
```
xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:validationLedgerTests
```

Result: `** TEST SUCCEEDED **`

Test run with **30 tests in 8 suites** passed after 0.140 seconds:

| Suite | Tests | Status | Source Plan |
|-------|-------|--------|-------------|
| PIIScrubber — 6 category redaction contract | 7 (incl. 1 parameterized @ 2 cases) | all passing | Plan 03 |
| Logger — 5-level contract (LOG-02) | 2 | all passing | Plan 03 |
| KeychainStore — SecItem round-trip | 4 | all passing | Plan 03 |
| KeychainWipe — FOUND-02 enumerate-before-delete (.serialized) | 2 | all passing | Plan 03 |
| SessionLockService — unified invariant (FOUND-07) | 4 | all passing | Plan 03 |
| DeepLinkRouter — bootstrap-aware queue (FOUND-08) | 3 | all passing | Plan 03 |
| MockURLProtocol — scaffolding (Phase 1) | 2 | all passing | Plan 03 |
| **RoleCoordinator — 5 TabBarController contract (ARCH-06, D-07..D-09)** | **6** | **all passing** | **Plan 04 (previously blocked on `_main`)** |
| **Total** | **30** | **30/30 passing** | |

### Release build (Task 2 AC#7)

Command:
```
xcodebuild build -configuration Release -project validationLedger.xcodeproj \
  -scheme validationLedger -destination 'generic/platform=iOS' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`

### D-13 compile-out verification (T-05-02 mitigation)

Command:
```
strings /Users/.../Release-iphoneos/validationLedger.app/validationLedger | \
  grep -ciE "DevMenu|LogViewer|RoleSwitcher|KeychainInspector"
```

Result: `0`

**Interpretation:** Zero references to any DevMenu symbol names in the Release binary. The file-level `#if DEBUG` gating compiles zero bytes of DevMenu code into Release. This is stronger than a runtime flag — a motivated attacker with a Release binary cannot toggle DevMenu because the code literally is not there.

## Manual Verification Checklist (Task 3 — pending user)

The parallel executor cannot interact with the simulator (Device → Shake, tap sequences, visual confirmation). The 8-step verification below is for the user to run on their local dev machine.

**Simulator substitution note:** The plan specifies `iPhone 15 / iOS 17.5`, but this machine has only iOS 18.x and iOS 26.x simulator runtimes installed (inherited environmental deviation from Plan 01's deferred user-setup). Use `iPhone 17 Pro` on `iOS 26.4` instead (already booted on this machine) — documented as Deviation #1 below.

### Steps

1. **Clean + build (automated portion already complete)**

   Already confirmed: both Debug and Release builds pass. If the user wants to re-run locally:
   ```
   xcodebuild clean -project validationLedger.xcodeproj -scheme validationLedger
   xcodebuild build -project validationLedger.xcodeproj -scheme validationLedger \
       -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'
   ```

2. **Run on simulator (manual)**

   - Open `validationLedger.xcodeproj` in Xcode 26.4.
   - Select destination: **iPhone 17 Pro (iOS 26.4)** (in the destination picker at the top).
   - Press **Cmd+R** to run.
   - **Expected:** app launches showing a tab bar with 4 tabs: **Loads**, **Brokers**, **BOL**, **Assistant**. Each tab icon renders. No crash.

3. **Shake gesture → DevMenu (manual)**

   - In the simulator menu bar: **Device → Shake** (or **Ctrl+Cmd+Z**).
   - **Expected:** DevMenu modally appears with 3 rows: **Role Switcher**, **Keychain Inspector**, **Log Viewer (OSLogStore)**.
   - If nothing appears: set an Xcode breakpoint on `SceneDelegate.motionEnded(_:with:)` and confirm `motion == .motionShake`. Check `canBecomeFirstResponder` is `true`.

4. **Role swap test — D-07 acceptance (manual)**

   - Tap **Role Switcher** → 5 rows appear (Shipper, Broker, Carrier, Dispatch, Factoring).
   - Tap **Broker**.
   - **Expected:** DevMenu dismisses; tab bar changes to **Loads, Carriers, Network, Assistant**.
   - **Expected Xcode console output:**
     ```
     [com.maldin.validationLedger.app / bootstrap]  app_coordinator_deinit           ← old Shipper coordinator
     [com.maldin.validationLedger.app / bootstrap]  app_container_deinit             ← old container
     [com.maldin.validationLedger.app / bootstrap]  app_container_init   event=debug ← new container
     [com.maldin.validationLedger.app / bootstrap]  app_coordinator_init event=role.broker ← new Broker coordinator
     ```
   - This is the **ADR 0002 empirical proof** — deterministic ARC deallocation of the orphaned coordinator + container on the next runloop tick.

5. **Repeat swap for all 5 roles (manual)**

   | Role | Expected tabs |
   |------|---------------|
   | Shipper | Loads, Brokers, BOL, Assistant |
   | Broker | Loads, Carriers, Network, Assistant |
   | Carrier | Loads, Drivers, Documents, Assistant |
   | Dispatch | Loads, Fleet, Drivers, Assistant |
   | Factoring | Invoices, Carriers, Chain, Assistant |

6. **Keychain Inspector — FOUND-02 verification (manual)**

   - Shake → **Keychain Inspector**.
   - **Expected:** shows 0 items (row reads "(empty — 0 items)"; footer reads "FOUND-02 verification: install → this screen should show 0 items.").
   - If you see items from a prior install: long-press the app icon on the simulator home screen → **Delete App** → **Delete** → re-run step 1-2 (fresh install). The wiper runs once per install; after deletion + reinstall, the inspector should show 0 items.

7. **Log Viewer — LOG-03 verification (manual)**

   - Shake → **Log Viewer**.
   - **Expected:** shows OSLog entries whose category is `bootstrap` and whose composed messages include `app_container_init`, `app_coordinator_init`, `app_coordinator_deinit`. If empty, trigger a role swap first (step 4), then reopen the Log Viewer.

8. **PII mask spot-check — D-16 full-circle validation (manual)**

   - In Xcode, add to `SceneDelegate.scene(_:willConnectTo:options:)` a test log line:
     ```swift
     appCoordinator?.container.logger.info("test phone +14155550129")
     ```
   - Rebuild and re-run. Shake → Log Viewer → search for the entry.
   - **Expected:** the log shows `test phone +1415•••0129` (E.164 phone masked to first-3-last-2 per PIIScrubber rule #1).
   - **If the log shows the raw `+14155550129`:** the PIIScrubber is not in the log path. File as a CRITICAL blocker — something regressed in `OSLogLoggerImpl.log(_:_:)`.
   - **REMOVE** the test log line after verification — it must not land in committed code.

### Optional — iPad native render (CLAUDE.md "iPad must render natively, not just scale")

   - Change simulator to **iPad Air (iOS 26.4)** or **iPad Pro (iOS 26.4)**.
   - Re-run. Tab bar renders natively (at iPad width, not iPhone-scaled). No letterboxing.

### Resume signal

Type one of the following back in the chat when verification is complete:

- `approved — all 8 steps pass + PII mask verified + 5-role swap works` (preferred)
- `approved — with notes: <list minor cosmetic issues>` (for non-blocking findings)
- `blocked — <step N failed>: <what happened>` (DO NOT proceed to Plan 06 / Phase 1 completion)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Simulator destination substituted `iPhone 17 Pro / iOS 26.4` for `iPhone 15 / iOS 17.5`**

- **Found during:** Task 1 verification and Task 3 checkpoint orchestration.
- **Issue:** The plan specifies `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. No iOS 17.5 simulator runtime is installed on this machine. The machine has iOS 18.0, 18.1, 18.2, 18.4, 26.2, 26.4 runtimes; `iPhone 17 Pro` is already booted on iOS 26.4 (per Plan 03's prior test runs). Installing an iOS 17 runtime (~5 GB) was deemed out of scope.
- **Fix:** Used `iPhone 17 Pro / iOS 26.4` throughout. Deployment target remains iOS 17.0 (unchanged — `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in project.pbxproj). ABI compatibility: all APIs used (`UITabBarController`, `UIResponder.motionEnded`, `OSLogStore`, `SecureEnclave.isAvailable`, Swift Testing, Swift Concurrency) are available on iOS 17+. Plan 07 (CI hardening) will standardize a pinned simulator version.
- **Files modified:** None (build-command substitution only).
- **Committed in:** n/a (verification-only; documented in commit message bodies).

**2. [Rule 3 — Blocking] Release build uses `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`**

- **Found during:** Task 2 verification (Release build for D-13 compile-out proof).
- **Issue:** The plan's Release-build command doesn't specify code signing, but this worktree has no Apple Developer team configured. Plain `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` fails with `Signing for "validationLedger" requires a development team`.
- **Fix:** Added `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` xcconfig flags. Compilation alone is what validates the `#if DEBUG` gating (T-05-02 mitigation check). The unsigned binary is equally valid for the `strings` grep. M5 archive/submission will require proper code signing; that's out of scope for Phase 1.
- **Files modified:** None (build-command flag addition only).
- **Committed in:** n/a (verification-only).

**3. [Rule 1 — Bug / Minor] AppCoordinator `container` kept as internal (removed awkward shim extension)**

- **Found during:** Writing SceneDelegate.swift (Step E).
- **Issue:** The plan's verbatim SceneDelegate sketch included an extension-shim at the bottom that exposed `container` on `AppCoordinator` via a backing store — then explicitly called the shim "awkward" and recommended making `container` `internal` (not `private`) on `AppCoordinator` instead. Two code paths, one marked awkward, is confusing.
- **Fix:** Declared `let container: AppContainer` (default internal access) on `AppCoordinator`. Removed the extension shim. `SceneDelegate.scene(_:openURLContexts:)` can now read `appCoordinator?.container.deepLinkRouter.receive(context.url)` directly without any shim.
- **Files modified:** `AppCoordinator.swift` (internal `container` field), `SceneDelegate.swift` (no shim extension).
- **Committed in:** `d90bb70` (Task 1).

**4. [Rule 1 — Bug / Minor] Used `@main` instead of `@UIApplicationMain`**

- **Found during:** Writing AppDelegate.swift.
- **Issue:** The plan's verbatim AppDelegate sketch used `@main`, which is the iOS-14+ idiom. Plan 03's Rule-1 stub used the legacy `@UIApplicationMain` which has been soft-deprecated since Swift 5.3. Mixing would be inconsistent.
- **Fix:** Used `@main` throughout. Modern Swift compilers emit identical Mach-O symbols for `@main` on a `UIApplicationDelegate` subclass as they do for `@UIApplicationMain`, so the linker behavior is unchanged.
- **Files modified:** `AppDelegate.swift`.
- **Committed in:** `d90bb70` (Task 1).

### Task-Ordering Note (not a deviation — a sequencing clarification)

- **Task 1 AC#11** (plain `xcodebuild build` exit 0) is not verifiable standalone in Debug configuration — AppCoordinator's `#if DEBUG func presentDevMenu()` references `DevMenuViewController`, which doesn't exist until Task 2 lands. This is by design in the plan's task structure (Task 1 = composition root including DEBUG shake-gesture hook; Task 2 = DevMenu itself; both must land for the Debug build to compile). Committed Task 1 code-only first (all 10 static AC pass), then verified build after Task 2 landed. The plan's plan-wide Verification section (lines 973-980) correctly expects both tasks complete.

---

**Total deviations:** 4 auto-fixed (2 Rule 3 environmental, 2 Rule 1 minor code-style refinements). No Rule 2 missing-critical, no Rule 4 architectural changes.

**Impact on plan:** All four deviations preserve plan intent. (1) and (2) are environmental boundary conditions that CI (Plan 07) will standardize. (3) is the plan's own stated preference ("Important fix" note). (4) modernizes the language idiom without behavior change.

## Authentication Gates

None — Plan 5 is entirely local to the simulator. No backend credentials, no network (MockURLProtocol only), no biometric enrollment (DefaultSessionLockService always returns true initially). No OTP, no keychain access group, no entitlements beyond Xcode's automatic simulator signing.

## User Setup Required

Only the Task 3 manual verification checklist (8 steps above). No credentials, no device provisioning, no backend endpoints needed.

## Known Stubs

These are intentional Phase-1 stubs with clear upgrade paths, all documented in the plan or inherited from Plan 03:

| File | Stub Type | Reason | Resolved In |
|------|-----------|--------|-------------|
| `validationLedger/App/AppCoordinator.swift` — `.auth` case body | Returns a placeholder `UIViewController` with title "Auth (Phase 3)" | Phase 3 adds the real OTP flow; Phase 1 only exercises `.role(_:)` cases | Phase 3 |
| `validationLedger/App/AppCoordinator.swift` — `.launch` case body | Falls through to `ShipperTabBarController()` | Phase 3 adds a real launch screen + session-token probe | Phase 3 |
| `validationLedger/App/AppCoordinator.swift` — `onRoleResolved` / `onLogout` callbacks | Set by `SceneDelegate.presentRoot` but never invoked in Phase 1 | Phase 3 wires real trigger points (backend response → onRoleResolved, logout button → onLogout) | Phase 3 |
| `validationLedger/App/Environment.swift` — both `#if DEBUG` and `#else` branches | Phase-1 minimal config (name only; no real apiBaseURL, no keychainAccessGroup) | Phase 2 adds dev/staging/prod with real URLs; Phase 2+ entitlements introduce access group | Phase 2 |
| `validationLedger/App/DevMenu/DevMenuShakeResponder.swift` | Empty marker enum | D-14 path consistency — real shake logic is in SceneDelegate.motionEnded | N/A (reserved for future custom gestures) |

All stubs inherited from Plan 03 (SecureEnclaveKeyStore fatalError, SoftwareKeyStore simulator-only, NetworkClient skeleton, MockURLProtocol single fixture, PinningSessionDelegate no-op, DeepLinkRouter.route no-op) remain intact — Plan 5 does not modify them.

## TDD Gate Compliance

Plan 05 is `type: execute` (not `type: tdd`). Both tasks are `type="auto" tdd="false"` — this is composition-root wiring where the verification is "does it build + does the existing test suite still pass," not a behavior-driven feature. Commits follow the plan's commit-message spec (one `feat(01-05):` commit per task). Task 3 is a `checkpoint:human-verify` gate.

## Self-Check: PASSED

Verified at SUMMARY write time:

### Commits exist in git log

- `d90bb70` — `feat(01-05): App composition root — AppDelegate + SceneDelegate + AppContainer + AppCoordinator` — FOUND
- `2173a12` — `feat(01-05): App/DevMenu — RoleSwitcher + KeychainInspector + LogViewer (DEBUG-only)` — FOUND

### Files on disk (10 created)

- `validationLedger/App/AppDelegate.swift` — FOUND
- `validationLedger/App/SceneDelegate.swift` — FOUND
- `validationLedger/App/AppContainer.swift` — FOUND
- `validationLedger/App/AppCoordinator.swift` — FOUND
- `validationLedger/App/Environment.swift` — FOUND
- `validationLedger/App/DevMenu/DevMenuViewController.swift` — FOUND
- `validationLedger/App/DevMenu/DevMenuShakeResponder.swift` — FOUND
- `validationLedger/App/DevMenu/RoleSwitcherViewController.swift` — FOUND
- `validationLedger/App/DevMenu/KeychainInspectorViewController.swift` — FOUND
- `validationLedger/App/DevMenu/LogViewerViewController.swift` — FOUND

### Files deleted (1 — intentional, documented)

- `validationLedger/App/validationLedgerApp.swift` — GONE (replaced by AppDelegate.swift + SceneDelegate.swift; deletion scheduled by Plan 03 SUMMARY)

### Build + test state

- `xcodebuild build -configuration Debug -destination 'iPhone 17 Pro/iOS 26.4'` — `** BUILD SUCCEEDED **`
- `xcodebuild test -only-testing:validationLedgerTests` — `** TEST SUCCEEDED **` (30 tests / 8 suites)
- `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` (with code-signing disabled) — `** BUILD SUCCEEDED **`
- `strings <Release>/validationLedger | grep -ciE 'DevMenu|LogViewer|RoleSwitcher|KeychainInspector'` — **0**

### Forbidden-pattern greps (ARCH invariants)

- `grep -rq 'import SwiftUI' validationLedger/App/` — **0 matches** (ARCH-01)
- `grep -rq '\.shared' validationLedger/App/` — **0 matches** (ARCH-04)
- `grep -rq 'Alamofire\|KeychainAccess\|XCoordinator\|Sentry\|Firebase\|Crashlytics\|Swinject' validationLedger/App/` — **0 matches** (CLAUDE.md dependency shortlist)

### Acceptance criteria

- Task 1 AC 1-12: PASS (AC 13 manual — pending user)
- Task 2 AC 1-7: PASS (AC 8 manual — pending user)
- Task 3: automated sub-steps complete; 8-step manual checklist documented above for user execution

## Next Plan Readiness

**Plan 01-06 (SwiftLint + SwiftFormat + custom rules) READY:**
- Real `validationLedger/App/` code now exists to lint (AppDelegate, SceneDelegate, AppContainer, AppCoordinator, DevMenu — ~530 LOC).
- ARCH-04 custom rule ("no `.shared` under `validationLedger/App/`") has real sources to match against; current code already compliant.
- ARCH-01 custom rule ("no `import SwiftUI` under `validationLedger/App/`") has real sources to match against; current code already compliant.
- LOG-01 custom rule (already established in Plan 03 — "no `os_log(` outside `Core/Logging/`") — current code already compliant (only `OSLogLoggerImpl` and `LogExporter` reference OSLog).

**Plan 01-07 (CI workflows) READY:**
- `xcodebuild build` compiles successfully on iPhone 17 Pro / iOS 26.4 simulator — CI can run the same on GHA macos-latest with iOS 17.5.
- `xcodebuild test -only-testing:validationLedgerTests` runs 30 tests in ~5 seconds on the simulator — CI can use the same command.
- Release build succeeds (with code-signing disabled via xcconfig flag) — CI can add a "Release-build-must-succeed" job without needing a signing team (Plan 07 can provision one if it wants `archive` instead of `build`).
- D-13 compile-out grep (`strings <Release>/validationLedger | grep -ciE ...`) returns 0 — CI can assert this as a Phase-1 acceptance gate.
- Built `.app` bundle contains `PrivacyInfo.xcprivacy` and `Info.plist` — Plan 04's grep checks pass.

**Phase 2 (Networking + Device Keys) READY:**
- `AppContainer` already gates `URLSessionNetworkClient`'s `NetworkConfig` (`.mock` vs `.live(baseURL:)`) and `MockURLProtocol` registration (DEBUG-only) — Phase 2's job is just to wire `.live(baseURL:)` when real endpoints come online.
- `#if DEBUG && targetEnvironment(simulator)` KeyStore gate is already in place — Phase 2's `SecureEnclaveKeyStore` real implementation slots straight into the `#else` branch.

**ADR 0002 deterministic ARC dealloc contract:**
- Every role swap emits `app_coordinator_deinit` + `app_container_deinit` on OSLog subsystem `com.maldin.validationLedger.app` category `bootstrap`. Plan 07 CI can add an OSLog smoke test that pipes the log stream and asserts the deinit-init sequence fires on a simulated role swap.

## Threat Flags

No new threat surface introduced beyond the plan's `<threat_model>` entries. All T-05-01..T-05-06 mitigations implemented as specified:

- **T-05-01 (Keychain carryover):** AppDelegate wipes before AppContainer resolves — verified by AC#2 grep and by KeychainInspector visual UI.
- **T-05-02 (DevMenu in Release):** `#if DEBUG` file-level gating — **empirically verified** via 0-match strings grep on Release binary.
- **T-05-03 (SoftwareKeyStore in production):** `#if DEBUG && targetEnvironment(simulator)` gate + `SecureEnclave.isAvailable` pre-check — verified by AC#6 grep.
- **T-05-04 (DevMenu path in Release code):** `AppCoordinator.presentDevMenu()` itself is `#if DEBUG` — if Release code accidentally called it, compile would fail.
- **T-05-05 (Pre-bootstrap deep-link crash):** `SceneDelegate.scene(_:openURLContexts:)` forwards to `DeepLinkRouter.receive(url)` which queues in `.cold` state; `presentRoot(_:)` calls `bootstrapComplete()` to drain the queue. Plan 03's `DeepLinkRouterTests` already covers this.
- **T-05-06 (Role-change timing in logs):** Accepted; `app_coordinator_deinit` emits empty fields and the event name is not PII. OSLog on-device observability is a known iOS feature.

---

*Phase: 01-foundational-conventions-scaffolding*
*Plan: 05 (Wave 2)*
*Completed: 2026-04-21*
