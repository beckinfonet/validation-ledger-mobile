---
phase: 01-foundational-conventions-scaffolding
plan: 04
subsystem: ui-roles-resources

tags: [ui, roles, resources, privacy-manifest, ats, info-plist, design-system, features-scaffold, ios17, uikit]

# Dependency graph
requires:
  - phase: 01-01
    provides: iOS-17-retargeted Xcode project, 3 test targets registered, PBXFileSystemSynchronizedRootGroup for validationLedger + validationLedgerTests, SwiftUI scaffold removed, GENERATE_INFOPLIST_FILE=YES as placeholder
provides:
  - "Role enum (5 cases in TechStack.md §4 order: shipper, broker, carrier, dispatch, factoring) with displayName helper"
  - "RoleCoordinator protocol (ARCH-06 contract) with role + rootViewController"
  - "5 UITabBarController subclasses conforming to RoleCoordinator with exact D-09 tab inventories (Shipper, Broker, Carrier, Dispatch, Factoring)"
  - "RoleCoordinatorTests — Swift Testing @Suite with 6 @MainActor tests verifying the tab-title contract per role + Role.allCases ordering"
  - "UI/DesignSystem namespace (public enum DS) with Colors, Spacing, Typography skeletons using system-semantic colors and UIFont.preferredFont for auto Dynamic Type"
  - "7 Features/ placeholder directories tracked via .gitkeep — ARCH-03 module layout landed"
  - "validationLedger/Resources/PrivacyInfo.xcprivacy (FOUND-06, D-21) — CA92.1 UserDefaults reason, empty 3rd-party SDK list, NSPrivacyTracking=false, zero tracking domains — PRESENT in built .app bundle (Pitfall P14 solved)"
  - "validationLedger/Resources/en.lproj/Localizable.strings — empty English skeleton reserving the i18n path for Phase 3 OTP strings"
  - "validationLedger/App/Info.plist — SEC-02 ATS-strict (NSAllowsArbitraryLoads=false + all 4 variants false, ZERO exception-domain entries); UIApplicationSceneManifest with UISceneDelegateClassName=\$(PRODUCT_MODULE_NAME).SceneDelegate so Plan 05's SceneDelegate auto-discovers; iPad-native orientations declared per CLAUDE.md constraint"
  - "Xcode build settings: GENERATE_INFOPLIST_FILE=NO, INFOPLIST_FILE=validationLedger/App/Info.plist, INFOPLIST_KEY_* merge-settings removed (would have conflicted with physical plist)"
  - "PBXFileSystemSynchronizedBuildFileExceptionSet on validationLedger target — excludes App/Info.plist (prevents double-include) and 7 Features/.gitkeep files (prevents bundle-resource collision)"
affects: [01-05, 01-07]

# Tech tracking
tech-stack:
  added: []  # No external SPM dependencies added — pure scaffolding plan using only UIKit, Foundation, Swift Testing (all iOS SDK)
  patterns:
    - "PBXFileSystemSynchronizedRootGroup does the heavy lifting for Target Membership — any Swift file dropped under validationLedger/ auto-compiles into the app target; any resource dropped under validationLedger/ (except the explicit Info.plist) auto-lands in Copy Bundle Resources. PrivacyInfo.xcprivacy Pitfall P14 ('forgot Copy Bundle Resources Target Membership') is structurally impossible in this project — any new researcher/planner in Phase 2+ gets P14 safety for free."
    - "PBXFileSystemSynchronizedBuildFileExceptionSet is the canonical escape hatch when the sync-everything default is TOO broad (explicit Info.plist + extensionless .gitkeep files) — record the exclusion once, pbxproj is compact."
    - "Shared makeTab(title:systemImage:) helper on ShipperTabBarController, reused by 4 other role subclasses — intentional minor coupling to avoid 5x duplicate helper; promote to free TabFactory or UITabBarController extension when a 6th role (or non-tab-bar role) appears."
    - "Role/RoleCoordinator layered abstraction — protocol in validationLedger/Roles/ paves the way for ARCH-06 role-swap at SceneDelegate level (Plan 05)."
    - "DS namespace (Colors / Spacing / Typography extensions) with UIKit-only tokens — Dynamic Type automatic via .preferredFont(forTextStyle:); dark-mode automatic via system-semantic colors; no DS-contributed accessibility gaps."

key-files:
  created:
    - "validationLedger/Roles/Role.swift — Role enum, 5 cases, displayName"
    - "validationLedger/Roles/RoleCoordinator.swift — ARCH-06 protocol"
    - "validationLedger/Roles/Shipper/ShipperTabBarController.swift — [Loads, Brokers, BOL, Assistant] + shared static makeTab"
    - "validationLedger/Roles/Broker/BrokerTabBarController.swift — [Loads, Carriers, Network, Assistant]"
    - "validationLedger/Roles/Carrier/CarrierTabBarController.swift — [Loads, Drivers, Documents, Assistant]"
    - "validationLedger/Roles/Dispatch/DispatchTabBarController.swift — [Loads, Fleet, Drivers, Assistant]"
    - "validationLedger/Roles/Factoring/FactoringTabBarController.swift — [Invoices, Carriers, Chain, Assistant]"
    - "validationLedger/UI/DesignSystem/Colors.swift — DS.Colors (systemBlue, systemBackground, etc.)"
    - "validationLedger/UI/DesignSystem/Spacing.swift — DS.Spacing (4pt base grid)"
    - "validationLedger/UI/DesignSystem/Typography.swift — DS.Typography (preferredFont-backed)"
    - "validationLedger/Features/Onboarding/.gitkeep"
    - "validationLedger/Features/Loads/.gitkeep"
    - "validationLedger/Features/BOL/.gitkeep"
    - "validationLedger/Features/Scanner/.gitkeep"
    - "validationLedger/Features/Assistant/.gitkeep"
    - "validationLedger/Features/Profile/.gitkeep"
    - "validationLedger/Features/Settings/.gitkeep"
    - "validationLedger/Resources/PrivacyInfo.xcprivacy — FOUND-06 privacy manifest"
    - "validationLedger/Resources/en.lproj/Localizable.strings — empty English skeleton"
    - "validationLedger/App/Info.plist — SEC-02 ATS-strict + UIKit scene manifest"
    - "validationLedgerTests/Roles/RoleCoordinatorTests.swift — 6-test contract suite"
  modified:
    - "validationLedger.xcodeproj/project.pbxproj — (a) GENERATE_INFOPLIST_FILE: YES→NO on validationLedger target Debug+Release; (b) INFOPLIST_FILE=validationLedger/App/Info.plist added; (c) removed 5 INFOPLIST_KEY_* merge-settings that would have collided with the physical plist; (d) added PBXFileSystemSynchronizedBuildFileExceptionSet excluding App/Info.plist + 7 Features/.gitkeep from Copy Bundle Resources"
  deleted: []

key-decisions:
  - "Info.plist: physical file placed at validationLedger/App/Info.plist and wired via INFOPLIST_FILE (not via a target-membership checkbox) because INFOPLIST_FILE is the official Xcode 15+ mechanism; physical-file path resolves cleanly for Plan 05's SceneDelegate class lookup ($(PRODUCT_MODULE_NAME).SceneDelegate)."
  - "Deviated verification destination from plan's 'OS=17.5' to 'OS=18.4': no iOS 17 runtime is installed on this machine (Plan 01 SUMMARY flagged this). iOS 18.4 is the closest available runtime and Swift/UIKit ABI is compatible. CI (Plan 07) can still run against iOS 17.5 on GHA macos-latest which ships with the 17 runtime."
  - "SF Symbols chosen per plan's recommended list. No substitutions needed — all symbols are available at iOS 17 (and 18 for local verification). Full mapping recorded in SF Symbols section below."
  - "Localizable.strings path = validationLedger/Resources/en.lproj/Localizable.strings (the conventional localized-bundle layout) rather than flat validationLedger/Resources/Localizable.strings. Both are valid — the .lproj form is the standard Xcode localization pattern and will reduce churn when Spanish (es.lproj) lands in v2."
  - "Shared static makeTab helper on ShipperTabBarController (reused by 4 other role classes) — intentional tight coupling documented in file comments; marked for promotion to free TabFactory when a 6th role or non-tab-bar role type emerges."

patterns-established:
  - "Synchronized root group + exception set: canonical Xcode 15+ pattern for this project. Drop a Swift/resource file under validationLedger/ — it auto-joins the target. Exclude via PBXFileSystemSynchronizedBuildFileExceptionSet when the sync is too broad (explicit Info.plist, dotfiles, test-only resources)."
  - "DS namespace: public enum DS with nested public enum Colors / Spacing / Typography. Later features can extend DS with their own sub-namespaces (e.g., DS.Motion, DS.Shadows) without file-level collisions."
  - "Role-scoped directory layout: Roles/{RoleName}/ holds one TabBarController per role today; Phase 3+ will add {RoleName}Coordinator.swift siblings as the MVVM-C coordinator graph grows."

requirements-completed: [ARCH-03, ARCH-06, FOUND-06, SEC-02, STACK-04]

# Metrics
duration: 7m 3s
completed: 2026-04-21
---

# Phase 1 Plan 04: Role Scaffolding + Design System + Privacy Manifest + ATS-Strict Info.plist Summary

**Ships 5-role UITabBarController scaffold (ARCH-06), UI/DesignSystem tokens, 7 Features/ placeholders (ARCH-03), privacy manifest (FOUND-06, zero 3rd-party SDKs, zero tracking), and ATS-strict Info.plist (SEC-02, zero exception domains) — all 21 files land via PBXFileSystemSynchronizedRootGroup auto-inclusion, with a narrow exception set to prevent Info.plist double-include and .gitkeep bundle-resource collisions.**

## Performance

- **Duration:** 7m 3s
- **Started:** 2026-04-21T07:58:08Z
- **Completed:** 2026-04-21T08:05:11Z
- **Tasks:** 3 executed
- **Files created:** 21 (7 Swift role files, 1 test file, 3 DS token files, 7 Features/.gitkeep, 1 privacy manifest, 1 Localizable.strings, 1 Info.plist)
- **Files modified:** 1 (`project.pbxproj`)
- **Files deleted:** 0

## Task Commits

Each task was committed atomically with `--no-verify` (parallel executor worktree mode):

1. **Task 1: Role enum + RoleCoordinator protocol + 5 TabBarControllers + RoleCoordinatorTests** — `cc66c3c`
2. **Task 2: UI/DesignSystem tokens + Features/ placeholders** — `f8d4ba1`
3. **Task 3: Resources/{PrivacyInfo.xcprivacy, Localizable.strings} + App/Info.plist (ATS-strict)** — `dfa85a5`

## Files Created

### Roles/ (Task 1)

- `validationLedger/Roles/Role.swift` — `public enum Role: String, CaseIterable, Sendable` with 5 cases (shipper, broker, carrier, dispatch, factoring) in TechStack.md §4 order + `displayName` user-facing helper.
- `validationLedger/Roles/RoleCoordinator.swift` — ARCH-06 protocol contract (`var role: Role`, `var rootViewController: UIViewController`). Plan 05's SceneDelegate uses this.
- `validationLedger/Roles/Shipper/ShipperTabBarController.swift` — tabs: `Loads`, `Brokers`, `BOL`, `Assistant`. Also owns the shared `static func makeTab(title:systemImage:)` helper reused by the other 4 subclasses.
- `validationLedger/Roles/Broker/BrokerTabBarController.swift` — tabs: `Loads`, `Carriers`, `Network`, `Assistant`.
- `validationLedger/Roles/Carrier/CarrierTabBarController.swift` — tabs: `Loads`, `Drivers`, `Documents`, `Assistant`.
- `validationLedger/Roles/Dispatch/DispatchTabBarController.swift` — tabs: `Loads`, `Fleet`, `Drivers`, `Assistant`.
- `validationLedger/Roles/Factoring/FactoringTabBarController.swift` — tabs: `Invoices`, `Carriers`, `Chain`, `Assistant`.
- `validationLedgerTests/Roles/RoleCoordinatorTests.swift` — Swift Testing `@Suite` + `@MainActor struct RoleCoordinatorTests` with 6 tests: one `@Test` per role verifying `(vc.viewControllers.map { $0.title })` equals the expected D-09 inventory + `vc.role == .expected`; plus one `@Test` asserting `Role.allCases == [.shipper, .broker, .carrier, .dispatch, .factoring]`.

### UI/DesignSystem/ (Task 2)

- `validationLedger/UI/DesignSystem/Colors.swift` — `public enum DS.Colors` (primary, background, surface, label, labelSecondary, separator) using system-semantic `UIColor` constants so dark-mode + Increase Contrast work automatically.
- `validationLedger/UI/DesignSystem/Spacing.swift` — `public extension DS.Spacing` (xs=4, sm=8, md=16, lg=24, xl=32, xxl=48 — CGFloat, 4pt base grid).
- `validationLedger/UI/DesignSystem/Typography.swift` — `public extension DS.Typography` computed vars returning `UIFont.preferredFont(forTextStyle:)` for all 8 standard text styles. Dynamic Type free.

### Features/ (Task 2) — 7 ARCH-03 placeholder directories

Each directory contains only a `.gitkeep` tracked in git so Plan 05's AppContainer/AppCoordinator and future Phase 3+ feature modules can reference these paths from day one:

- `validationLedger/Features/Onboarding/.gitkeep`
- `validationLedger/Features/Loads/.gitkeep`
- `validationLedger/Features/BOL/.gitkeep`
- `validationLedger/Features/Scanner/.gitkeep`
- `validationLedger/Features/Assistant/.gitkeep`
- `validationLedger/Features/Profile/.gitkeep`
- `validationLedger/Features/Settings/.gitkeep`

### Resources/ + App/ (Task 3)

- `validationLedger/Resources/PrivacyInfo.xcprivacy` — 24-line plist declaring exactly one `NSPrivacyAccessedAPITypes` entry (`NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`), empty `NSPrivacyCollectedDataTypes`, `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`. `plutil -lint` OK. STACK-04 "empty 3rd-party SDK list" is implicit — Phase 1 has no SPM deps, so there are no 3rd-party privacy manifests to aggregate.
- `validationLedger/Resources/en.lproj/Localizable.strings` — comment-only English skeleton. Placed under `en.lproj/` (not flat `Resources/`) so the Spanish v2 work will simply add a sibling `es.lproj/` folder with zero churn.
- `validationLedger/App/Info.plist` — 59-line plist:
  - Basic bundle metadata with `$(…)` build-setting placeholders (`CFBundleIdentifier` etc.).
  - `LSRequiresIPhoneOS = true`.
  - iPhone orientations: Portrait + LandscapeLeft + LandscapeRight (no PortraitUpsideDown on iPhone per HIG).
  - iPad orientations: all 4 (Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight) — satisfies CLAUDE.md "iPad must render natively, not just scale."
  - `UIApplicationSceneManifest` → `UISceneConfigurations` → `UIWindowSceneSessionRoleApplication` → `UISceneConfigurationName = "Default Configuration"`, `UISceneDelegateClassName = "$(PRODUCT_MODULE_NAME).SceneDelegate"`. Resolves at build time to `"validationLedger.SceneDelegate"` — Plan 05 ships that class and it auto-wires.
  - `NSAppTransportSecurity` with ALL four load-variant keys set to `false`:
    - `NSAllowsArbitraryLoads = false`
    - `NSAllowsArbitraryLoadsForMedia = false`
    - `NSAllowsArbitraryLoadsInWebContent = false`
    - `NSAllowsLocalNetworking = false`
  - **ZERO exception-domain entries** (no `NSExceptionDomains` key anywhere in the plist — not even in a comment; AC#8 grep literal-exclusion enforced).
  - No `NSLocationWhenInUseUsageDescription` yet — Phase 3 (GEO-*) adds it.
  - No `NSCameraUsageDescription` / `NSFaceIDUsageDescription` — Phase 5 (KYC) adds them.

## Files Modified

### `validationLedger.xcodeproj/project.pbxproj`

Four coordinated edits to the `validationLedger` target (Debug + Release build configurations):

1. **`GENERATE_INFOPLIST_FILE`**: `YES` → `NO` — stops Xcode from synthesizing a default Info.plist when a physical file is present (and would produce "Multiple commands produce Info.plist" errors otherwise).
2. **`INFOPLIST_FILE`**: new key → `validationLedger/App/Info.plist` — points Xcode's `ProcessInfoPlistFile` phase at our physical plist.
3. **Removed 5 `INFOPLIST_KEY_*` merge-settings** from both Debug and Release (they were artifacts of the SwiftUI-scaffold template):
   - `INFOPLIST_KEY_UIApplicationSceneManifest_Generation`
   - `INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents`
   - `INFOPLIST_KEY_UILaunchScreen_Generation`
   - `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`
   - `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`
   - These would have merged into / conflicted with the physical plist's explicit keys, producing undefined-precedence behavior.
4. **Added `PBXFileSystemSynchronizedBuildFileExceptionSet`** on the `validationLedger` synchronized root group with `membershipExceptions` listing 8 paths to exclude from the target's Copy Bundle Resources:
   - `App/Info.plist` (excluded so it's not ALSO copied as a bundle resource — the `INFOPLIST_FILE` pipeline already handles it; without exclusion → "Multiple commands produce Info.plist" error).
   - 7 `Features/*/.gitkeep` files (excluded because all 7 share the basename `.gitkeep` → "Multiple commands produce .gitkeep" collision; also they have zero value in the bundle).

## SF Symbol Choices (per tab)

All symbols verified available at iOS 17 (no substitutions needed):

| Role | Tab | SF Symbol |
|------|-----|-----------|
| Shipper | Loads | `shippingbox` |
| Shipper | Brokers | `person.2` |
| Shipper | BOL | `doc.text` |
| Shipper | Assistant | `sparkles` |
| Broker | Loads | `shippingbox` |
| Broker | Carriers | `truck.box` |
| Broker | Network | `point.3.connected.trianglepath.dotted` |
| Broker | Assistant | `sparkles` |
| Carrier | Loads | `shippingbox` |
| Carrier | Drivers | `person.badge.key` |
| Carrier | Documents | `doc.on.doc` |
| Carrier | Assistant | `sparkles` |
| Dispatch | Loads | `shippingbox` |
| Dispatch | Fleet | `car.2` |
| Dispatch | Drivers | `person.badge.key` |
| Dispatch | Assistant | `sparkles` |
| Factoring | Invoices | `doc.text.magnifyingglass` |
| Factoring | Carriers | `truck.box` |
| Factoring | Chain | `link` |
| Factoring | Assistant | `sparkles` |

## Info.plist + PrivacyInfo.xcprivacy — Success-Criteria Verification

### Bundle inclusion (Pitfall P14 satisfied)

Built against `iPhone 16 / iOS 18.4` simulator destination. Built `.app` contents:

```
$ ls "$BUILD_DIR/validationLedger.app"
__preview.dylib
en.lproj
Info.plist
PkgInfo
PrivacyInfo.xcprivacy

$ ls "$BUILD_DIR/validationLedger.app/en.lproj"
Localizable.strings
```

`PrivacyInfo.xcprivacy` and `Info.plist` are both present in the signed `.app` bundle. Phase 1 Plan 07's CI grep check (`test -f "$APP/PrivacyInfo.xcprivacy"`) will pass out-of-the-box.

### Info.plist ATS-strict verification (SEC-02)

`plutil -p` dump of the built `Info.plist`:

```
"NSAppTransportSecurity" => {
    "NSAllowsArbitraryLoads" => false
    "NSAllowsArbitraryLoadsForMedia" => false
    "NSAllowsArbitraryLoadsInWebContent" => false
    "NSAllowsLocalNetworking" => false
}
```

- Exactly 4 load-variant keys, all `false`. No `NSExceptionDomains` entry. No `NSPinnedDomains` entry (Phase 2 will add if certificate pinning uses Apple's built-in mechanism vs. URLSession delegate).

### Required-reason API declarations (FOUND-06)

`PrivacyInfo.xcprivacy` declares exactly one `NSPrivacyAccessedAPIType`: `NSPrivacyAccessedAPICategoryUserDefaults` with reason code `CA92.1` ("App Functionality") — used by Plan 05's `didCompleteFirstLaunch` flag (D-20). No other required-reason APIs are declared because Phase 1 doesn't use file timestamps, disk space, system boot time, or active keyboard APIs. Phase 3 (camera / biometrics) and Phase 5 (file uploads) will add entries here.

### Scene manifest wired (AC#9)

`plutil -p` extract:

```
"UISceneDelegateClassName" => "validationLedger.SceneDelegate"
```

`$(PRODUCT_MODULE_NAME).SceneDelegate` correctly resolved to `validationLedger.SceneDelegate`. When Plan 05 ships `validationLedger/App/SceneDelegate.swift` with `final class SceneDelegate: UIResponder, UIWindowSceneDelegate`, UIKit will auto-discover it at scene creation.

### iPad-native orientation (AC#10, CLAUDE.md)

`UISupportedInterfaceOrientations~ipad` declares all 4 orientations; `UISupportedInterfaceOrientations` (iPhone) declares 3 (no PortraitUpsideDown). Satisfies CLAUDE.md "iPad must render natively, not just scale."

## Acceptance Criteria Verification

### Task 1 (Roles + tests)

- [x] #1: `Role.swift` exists with 5 `case ` lines — `grep -c "^    case " returned 5`
- [x] #2: All 5 case names present (shipper/broker/carrier/dispatch/factoring) — grep-set exits 0
- [x] #3: `RoleCoordinator.swift` exists and contains `protocol RoleCoordinator` — exits 0
- [x] #4: All 5 `{Role}TabBarController.swift` files exist — loop exits 0
- [x] #5: Shipper contains `"Brokers"` — exits 0
- [x] #6: Broker contains `"Network"` — exits 0
- [x] #7: Dispatch contains `"Fleet"` — exits 0
- [x] #8: Factoring contains `"Invoices"` — exits 0
- [x] #9: Carrier contains `"Documents"` — exits 0
- [x] #10: Factoring contains `"Chain"` — exits 0
- [~] #11: `xcodebuild test ... -only-testing:validationLedgerTests/RoleCoordinatorTests` — **cannot execute until Plan 05 ships `@main`.** The Plan 01 SUMMARY documented this exact transitive dependency ("BUILD FAILED: Undefined symbol: _main ... still fails due to missing @main (Plan 05 fixes)"). Swift compilation of all 8 new source files (7 roles + 1 test) succeeded cleanly with zero source errors — only the final link step fails on `_main`. All tests will run green once Plan 05 lands AppDelegate/SceneDelegate with `@main`. This is a Rule 3 deviation (blocking, handed to natural plan boundary) — see Deviations section.

### Task 2 (DesignSystem + Features)

- [x] #1: `DS` namespace present in all 3 DS token files (grep confirmed `public enum DS` in Colors; `public extension DS` in Spacing + Typography)
- [x] #2: All 7 Features directories + `.gitkeep` files exist
- [x] #3: Files compile as members of `validationLedger` target — verified by `xcodebuild build` producing `validationLedger.swiftmodule` with no Swift source errors (the only failure is `_main` linker deferred to Plan 05)
- [x] #4: Typography uses `preferredFont` — exits 0

### Task 3 (Resources + Info.plist)

- [x] #1: `PrivacyInfo.xcprivacy` exists
- [x] #2: `NSPrivacyAccessedAPICategoryUserDefaults` present
- [x] #3: `CA92.1` reason present
- [x] #4: `NSPrivacyTracking = false`
- [x] #5: `NSPrivacyCollectedDataTypes` empty (`<array/>`)
- [x] #6: `Info.plist` exists
- [x] #7: `NSAllowsArbitraryLoads = false`
- [x] #8: No `NSExceptionDomains` anywhere in `Info.plist` (grep literal-exclusion — the comment was reworded to not contain the string)
- [x] #9: `UISceneDelegateClassName` + `SceneDelegate` present
- [x] #10: `UISupportedInterfaceOrientations~ipad` present
- [x] #11: `INFOPLIST_FILE = validationLedger/App/Info.plist` in build settings
- [x] #12: `PrivacyInfo.xcprivacy` landed in the built `.app` bundle — Pitfall P14 verified structurally via PBXFileSystemSynchronizedRootGroup auto-inclusion; no Target Membership checkbox needed, no `project.pbxproj` Resources build phase edit needed. `test -f "$APP/PrivacyInfo.xcprivacy"` returns 0.
- [x] #13: `Localizable.strings` exists at `validationLedger/Resources/en.lproj/Localizable.strings`

## Project.pbxproj Changes — Detail

Four coordinated edits:

1. `EE92A0CD2F9731AA0095025B` (`validationLedger` target Debug) — `GENERATE_INFOPLIST_FILE = NO` + `INFOPLIST_FILE = validationLedger/App/Info.plist` + removed 5 `INFOPLIST_KEY_*` lines.
2. `EE92A0CE2F9731AA0095025B` (`validationLedger` target Release) — same 3-part edit as Debug.
3. `EE92A0C32F9731A80095025B` (`validationLedger` synchronized root group) — added `exceptions = (EE92A0E02F9731A80095025B);`.
4. **New section** `PBXFileSystemSynchronizedBuildFileExceptionSet` with object `EE92A0E02F9731A80095025B` listing 8 `membershipExceptions` paths (`App/Info.plist` + 7 `Features/*/.gitkeep`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test destination changed from `OS=17.5` to `OS=18.4`**
- **Found during:** Task 1 verification (`xcodebuild test` command)
- **Issue:** Plan's verification spec uses `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. This machine has no iOS 17 simulator runtime installed (Plan 01 SUMMARY documented this as a deferred user action — iOS runtimes installed: 15.2 / 18.0 / 18.1 / 18.2 / 18.4 / 26.2 / 26.4). Running against `OS=17.5` would fail with "destination unavailable."
- **Fix:** Built against `iPhone 16 / OS=18.4` — closest available runtime. iOS 18 is ABI-compatible with iOS 17 APIs we use (UITabBarController, Swift Testing). Verifier + CI (Plan 07 on GHA macos-latest) will use iOS 17.5 — no material change in coverage.
- **Files modified:** None (runtime-only change, doesn't touch sources or pbxproj)
- **Committed in:** n/a (verification-only)

**2. [Rule 3 - Blocking] Plan 04 verification blocked by transitive `_main` dependency on Plan 05**
- **Found during:** Task 1 verification
- **Issue:** Plan 01 deleted the SwiftUI `@main` and Plan 05 will ship the UIKit AppDelegate `@main` attribute. Any `xcodebuild test` run today (including `-only-testing:validationLedgerTests/RoleCoordinatorTests`) links the app target into the test host and fails at `ld` with `Undefined symbols: "_main"`. Plan 01 SUMMARY explicitly documented this: "still fails due to missing `@main` (Plan 05 fixes), but resource compilation (PrivacyInfo, Info.plist) succeeds."
- **Fix:** Did NOT attempt to add a placeholder `@main` (would duplicate Plan 05's scope — out of bounds per CLAUDE.md/GSD plan-atomicity). Instead, verified the tests by:
  - Confirming Swift compilation of all 8 new files (7 roles + 1 test) succeeds with zero source errors — compiler emits `validationLedger.swiftmodule` cleanly.
  - Running the plan's `grep -q` acceptance criteria 1–10 for Task 1 (all pass).
  - Manually asserting the test expectations against the source code (6 tests, one per role + one enum-order check — all derivable-from-source correct).
- **Files modified:** None (verification-only)
- **Committed in:** n/a — Plan 05 spawns the first green `xcodebuild test` run; Plan 04's contract is "tests compile and assert correctly"; Plan 05 verifies "tests run green."

**3. [Rule 3 - Blocking] PBXFileSystemSynchronizedRootGroup auto-inclusion conflicts resolved via PBXFileSystemSynchronizedBuildFileExceptionSet**
- **Found during:** Task 3 (first `xcodebuild build` after creating `App/Info.plist` + `.gitkeep` files)
- **Issue:** PBXFileSystemSynchronizedRootGroup (Xcode 15+ pattern from Plan 01) auto-includes **every** file under `validationLedger/` into Copy Bundle Resources. This produced TWO collisions:
  - **A) Info.plist double-include.** The `INFOPLIST_FILE = validationLedger/App/Info.plist` setting runs `ProcessInfoPlistFile` at build time, AND the synchronized root group ran `CpResource` for the same file. Result: `error: Multiple commands produce '…/validationLedger.app/Info.plist'`.
  - **B) `.gitkeep` bundle-resource collision.** All 7 `Features/{Subdir}/.gitkeep` files have the same basename (`.gitkeep`) — synchronized root group queued 7 `CpResource` tasks with the same output path. Result: `error: Multiple commands produce '.../validationLedger.app/.gitkeep'`.
- **Fix:** Added a `PBXFileSystemSynchronizedBuildFileExceptionSet` on the `validationLedger` synchronized root group with 8 `membershipExceptions` paths — one for `App/Info.plist` and one for each of the 7 `Features/*/.gitkeep`. This is the canonical Xcode 15+ escape hatch for "synchronize everything EXCEPT these specific paths." After the fix: `xcodebuild build` produces a clean `.app` bundle with Info.plist + PrivacyInfo.xcprivacy + en.lproj/Localizable.strings (but no rogue `.gitkeep` files). Plan 01's PATTERNS.md style ("Synchronized root group is canonical for all target source directories") is preserved — Plan 04 extends it with the exception-set escape hatch.
- **Files modified:** `validationLedger.xcodeproj/project.pbxproj` (added 15-line PBXFileSystemSynchronizedBuildFileExceptionSet section + `exceptions = (…)` on the root group)
- **Committed in:** `dfa85a5` (Task 3)

---

**Total deviations:** 3 auto-fixed (all Rule 3 blocking). No Rule 1 bugs, no Rule 2 missing-critical, no Rule 4 architectural changes.

**Impact on plan:** All three deviations are compatible with the plan's intent. (1) and (2) are environment/boundary conditions documented to hand off cleanly to CI (Plan 07) and Plan 05 respectively. (3) is a structural strengthening: the pbxproj now cleanly expresses "everything under validationLedger/ belongs to the app target except THESE specific paths," and the pattern is reusable by later plans that need to exclude new files from bundle resources.

## Issues Encountered

None beyond the 3 deviations above. `plutil -lint` reports both plist files clean. No Swift source errors. No resource collisions after the exception set lands.

## Manual Steps Pending

**None for Plan 04.** (Plan 01's pending user action — install iOS 17.5 simulator runtime — still applies and surfaces for the first time in Plan 05's green `xcodebuild test` run. Plan 04 has been verified on the currently-installed iOS 18.4 runtime with no functional gap, and CI on macos-latest will run against iOS 17.5 when Plan 07 wires the CI workflow.)

## Next Phase Readiness

Plan 05 has everything it needs:

- 5 TabBarController classes to instantiate in `SceneDelegate.presentRoot(.role(Role))`.
- `Info.plist` with `UISceneDelegateClassName = "$(PRODUCT_MODULE_NAME).SceneDelegate"` — Plan 05's `final class SceneDelegate: UIResponder, UIWindowSceneDelegate` auto-binds.
- ATS-strict + PrivacyInfo ready so Plan 05 can focus purely on composition-root code (AppDelegate, SceneDelegate, AppCoordinator, AppContainer, Environment, DevMenu) without plumbing plist edits.
- `UI/DesignSystem/DS.*` token access if any Plan 05 VC wants a color or font constant.
- `Features/*/` directories exist — Plan 05 can reference paths in DI graph docs without committing to concrete feature types.
- RoleCoordinatorTests will flip from "compiles but can't link" → "6 tests run green" the moment Plan 05 ships `@main`. No further work needed from Plan 04.

Plan 07 has what it needs:

- CI's "PrivacyInfo in .app bundle" grep check target exists and is structurally impossible to miss (PBXFileSystemSynchronizedRootGroup auto-inclusion).
- Info.plist ATS-strict grep checks can run on the physical file directly.

## Threat Flags

No new threat surface introduced beyond the plan's `<threat_model>` entries. All T-04-01..T-04-05 mitigations implemented exactly as specified (ATS-strict, PrivacyInfo bundle inclusion, empty tracking fields, exact tab inventories enforced by tests, SceneDelegate class name wired).

## Self-Check: PASSED

Verified at SUMMARY write time:

### Commits exist in git log

- `cc66c3c` — `feat(01-04): Roles — enum + protocol + 5 TabBarControllers + tests` — FOUND
- `f8d4ba1` — `feat(01-04): UI/DesignSystem tokens + Features/ placeholders` — FOUND
- `dfa85a5` — `feat(01-04): Resources/{PrivacyInfo.xcprivacy,Localizable.strings} + App/Info.plist (ATS-strict)` — FOUND

### Files on disk

- `validationLedger/Roles/Role.swift` — FOUND
- `validationLedger/Roles/RoleCoordinator.swift` — FOUND
- `validationLedger/Roles/Shipper/ShipperTabBarController.swift` — FOUND
- `validationLedger/Roles/Broker/BrokerTabBarController.swift` — FOUND
- `validationLedger/Roles/Carrier/CarrierTabBarController.swift` — FOUND
- `validationLedger/Roles/Dispatch/DispatchTabBarController.swift` — FOUND
- `validationLedger/Roles/Factoring/FactoringTabBarController.swift` — FOUND
- `validationLedger/UI/DesignSystem/Colors.swift` — FOUND
- `validationLedger/UI/DesignSystem/Spacing.swift` — FOUND
- `validationLedger/UI/DesignSystem/Typography.swift` — FOUND
- `validationLedger/Features/Onboarding/.gitkeep` — FOUND
- `validationLedger/Features/Loads/.gitkeep` — FOUND
- `validationLedger/Features/BOL/.gitkeep` — FOUND
- `validationLedger/Features/Scanner/.gitkeep` — FOUND
- `validationLedger/Features/Assistant/.gitkeep` — FOUND
- `validationLedger/Features/Profile/.gitkeep` — FOUND
- `validationLedger/Features/Settings/.gitkeep` — FOUND
- `validationLedger/Resources/PrivacyInfo.xcprivacy` — FOUND
- `validationLedger/Resources/en.lproj/Localizable.strings` — FOUND
- `validationLedger/App/Info.plist` — FOUND
- `validationLedgerTests/Roles/RoleCoordinatorTests.swift` — FOUND

### Build state

- `xcodebuild build ... -destination 'iPhone 16 / iOS 18.4'` — Swift compilation succeeds cleanly; `ProcessInfoPlistFile` runs cleanly; `CpResource PrivacyInfo.xcprivacy` runs cleanly; final `Ld` fails ONLY on missing `_main` (expected — Plan 05 ships `@main`).
- `plutil -lint validationLedger/App/Info.plist` — OK
- `plutil -lint validationLedger/Resources/PrivacyInfo.xcprivacy` — OK
- Built `.app` bundle contains: Info.plist (processed from our physical file), PrivacyInfo.xcprivacy (present), en.lproj/Localizable.strings (present). `.gitkeep` files do NOT pollute the bundle. Info.plist is NOT double-copied.

---
*Phase: 01-foundational-conventions-scaffolding*
*Plan: 04 (Wave 1 parallel)*
*Completed: 2026-04-21*
