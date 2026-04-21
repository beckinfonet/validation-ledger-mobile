---
phase: 01-foundational-conventions-scaffolding
verified: 2026-04-21T09:31:59Z
status: human_needed
score: 4/5 roadmap success criteria verified (SC-2 partially verified — CR-02a name-sweep gap; SC-5 app-extract deferred to CI)
overrides_applied: 0
gaps:
  - truth: "PIIScrubber string path redacts all 6 PII categories including full names"
    status: partial
    reason: "scrubString() has no name sweep. The structured path (LogField.fullName) correctly masks to initials. But the string-path 'cannot bypass redaction' claim in D-16 is violated for names — any caller using logger.info('User John Doe failed KYC') bypasses name redaction entirely. CR-02a from REVIEW.md. Note: CR-02b (DL regex false-positives on TX1234567-style strings) is also present but does not create a missing-category gap — DL IS swept, just with a broad regex."
    artifacts:
      - path: "validationLedger/Core/Logging/PIIScrubber.swift"
        issue: "scrubString() (lines 41-68) applies phone, coords, email, MC/DOT, DL sweeps — no fullName regex sweep"
    missing:
      - "Add name sweep to scrubString(): e.g., pattern `\\b[A-Z][a-z]+(?:\\s[A-Z][a-z]+)+` mapping matches to initial-only format"
      - "Optionally tighten DL regex to validated US state codes to prevent over-redaction of transaction IDs (CR-02b warning)"

human_verification:
  - test: "Simulator launch — UIKit tab shell renders with correct Shipper tabs"
    expected: "App launches on simulator (iOS 17.x or latest available) showing 4-tab bar: Loads, Brokers, BOL, Assistant. No crash."
    why_human: "Cannot run simulator headlessly in this verification context; Plan 05 Task 3 manual verification was approved as automated-only and explicitly deferred to HUMAN-UAT"
  - test: "Shake gesture reveals DevMenu with 3 rows (Role Switcher, Keychain Inspector, Log Viewer)"
    expected: "Simulator Device → Shake presents DevMenu modal. All 3 rows tappable. DevMenu absent in Release binary (D-13 compile-out)."
    why_human: "Interactive simulator gesture; Plan 05 Task 3 steps 3-7 deferred to HUMAN-UAT"
  - test: "Role swap end-to-end — D-07 acceptance"
    expected: "Tapping Broker in Role Switcher changes tab bar to Loads/Carriers/Network/Assistant. Xcode console shows app_coordinator_deinit + app_container_deinit + app_container_init + app_coordinator_init sequence (ADR-0002 ARC dealloc proof)."
    why_human: "Interactive; visual + console observation required. Plan 05 Task 3 step 4 deferred to HUMAN-UAT"
  - test: "Keychain Inspector shows 0 items on fresh install (FOUND-02 visual proof)"
    expected: "DevMenu → Keychain Inspector shows '(empty — 0 items)' on first install. Wiper called in AppDelegate BEFORE AppContainer."
    why_human: "Requires physical install-delete-reinstall cycle on device or simulator. Plan 05 Task 3 step 6 deferred to HUMAN-UAT"
  - test: "PII mask spot-check — string-path phone redaction"
    expected: "Test log with +14155550129 renders as +1415•••0129 in Log Viewer. Confirms OSLogLoggerImpl → PIIScrubber → OSLog pipeline is end-to-end wired."
    why_human: "Requires injecting a test log line, running in simulator, and reading the Log Viewer. Plan 05 Task 3 step 8 deferred to HUMAN-UAT"
  - test: "CI Simulator pipeline — PR trigger + planted-violation reject cycle"
    expected: "Push to a PR branch triggers ci-simulator.yml on GitHub Actions; SwiftLint step fires ban_print on a planted print() violation; CI goes red. Revert makes CI green."
    why_human: "Project has no git remote configured (git remote -v is empty). Plan 07 Task 5 steps 2-5 deferred to HUMAN-UAT"
  - test: "Device CI pipeline — SecureEnclaveSmokeTests on physical iPhone"
    expected: "Merge to main triggers ci-device.yml on self-hosted runner. Both @Test cases pass: SecureEnclave.isAvailable == true, Keychain round-trip succeeds."
    why_human: "Requires self-hosted runner registration and DEVICE_UDID secret. Paired iPhone 15 Pro Max available at UDID 48F5B3CC-0E06-50CE-BFD4-8A0A136E144D but test execution deferred to HUMAN-UAT"
  - test: "PrivacyInfo.xcprivacy in .ipa bundle (SC-5 full verification)"
    expected: "Extract .ipa produced by CI, confirm PrivacyInfo.xcprivacy present and declares CA92.1 reason for UserDefaults."
    why_human: "True .ipa extraction requires archive + export step with code signing. Plan 04 confirmed .app bundle presence via PBXFileSystemSynchronizedRootGroup auto-inclusion and local build; .ipa extraction is M5 pre-submission scope. For Phase 1, .app bundle verification is sufficient and was confirmed locally."
---

# Phase 1: Foundational Conventions & Scaffolding Verification Report

**Phase Goal:** Rebuild the Xcode SwiftUI scaffold as the UIKit module layout specified in TechStack.md §3.2 (with ARCHITECTURE.md refinements), land the 8 foundational conventions that must exist before feature code is written, and stand up the tooling/CI/logging baseline that every later phase depends on. No user-visible behavior; but after this phase the project *has* conventions.
**Verified:** 2026-04-21T09:31:59Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Reviewer clones repo, runs xcodebuild against main scheme: builds cleanly with iOS 17.0 deployment target, SwiftPM-only deps, no SwiftUI in launch path, UIKit AppDelegate + SceneDelegate + AppContainer | ✓ VERIFIED | `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (8 occurrences in pbxproj, 0 occurrences of 26); `grep -r "import SwiftUI" validationLedger/` = 0; `@main` on `AppDelegate: UIResponder, UIApplicationDelegate`; `SceneDelegate: UIWindowSceneDelegate`; `AppContainer` initializer-DI composition root. Plan 05 confirms `** BUILD SUCCEEDED **` on Debug + Release. |
| SC-2 | Unit test asserts PIIScrubber redacts E.164 phones, DL numbers, full names, MC/DOT, emails, coordinates — AND test suite fails SwiftLint rules for print(), direct os_log(), raw coordinate literals | ⚠ PARTIAL | PIIScrubberTests.swift has 7 test cases covering all 6 structured-path categories (phone, DL, fullName, MC/DOT, email, coords) and passes. BUT: `scrubString()` string-path has no fullName sweep (CR-02a) — D-16 "string path cannot bypass redaction" is violated for names. All 4 D-19 SwiftLint rules fire on planted violations (ban_print, ban_direct_os_log, ban_userdefaults_tokens, no_cross_feature_import). Raw-coordinate-literal rule explicitly deferred to Phase 3 per D-19/Flag #1, documented in .swiftlint.yml header. |
| SC-3 | Deleting and reinstalling the app wipes Keychain; debug-only button enumerates items before/after first launch; didCompleteFirstLaunch flag gates it | ✓ VERIFIED (automated portion) | `KeychainWiper.wipeOnFirstLaunch(defaults: .standard, accessGroup: nil)` called synchronously in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` at line 18, before `SceneDelegate` constructs `AppContainer` (D-20 invariant). `KeychainWipeTests` (2 tests, `.serialized`) prove enumerate-before-delete + flag-idempotency. `KeychainInspectorViewController` (DEBUG-only, #if DEBUG gated) provides the enumeration UI. `didCompleteFirstLaunch` key present in tests. Manual visual verification (simulator fresh install → 0 items) deferred to HUMAN-UAT. |
| SC-4 | CI runs two pipelines: simulator on every PR (excluding security code), physical-device on every merge to main; both documented in docs/ci.md | ✓ VERIFIED (structural) | `.github/workflows/ci-simulator.yml` committed — triggers on `pull_request` to main + `push` to main; uses `macos-latest`, Xcode 16.4 pin, iPhone 15/iOS 17.5 destination; excludes `validationLedgerDeviceTests` (D-03). `.github/workflows/ci-device.yml` committed — triggers on `push to main` + security-path `pull_request`; uses `[self-hosted, macOS, device]` runner + `DEVICE_UDID` secret. `docs/ci.md` documents both pipelines with triggers, runners, Xcode version policy, known tradeoff. Actual PR trigger + planted-violation cycle + device CI execution pending git remote + runner setup (Plan 07 Task 5 steps 2-5, deferred to HUMAN-UAT). |
| SC-5 | PrivacyInfo.xcprivacy in Copy Bundle Resources, declares required-reason APIs in use; verified by .ipa extraction from CI | ✓ VERIFIED (app bundle; .ipa deferred) | `validationLedger/Resources/PrivacyInfo.xcprivacy` exists, declares `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`, `NSPrivacyTracking=false`, empty `NSPrivacyCollectedDataTypes`. Plan 04 confirms file present in built `.app` bundle via PBXFileSystemSynchronizedRootGroup auto-inclusion (structural impossibility of P14). `scripts/check-privacy-manifest.sh` runs on every CI PR and gates on presence. True `.ipa` extraction is M5 pre-submission scope — Phase 1 acceptance is `.app` bundle presence, which is confirmed. |

**Score:** 4/5 roadmap success criteria verified (SC-2 partial due to CR-02a string-path name gap)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|---------|--------|---------|
| `validationLedger.xcodeproj/project.pbxproj` | iOS 17.0 target, 3 test targets | ✓ VERIFIED | 8× `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; 0× `= 26`; 2× `unit-test` product type; 1× `ui-testing` product type |
| `validationLedgerTests/.gitkeep` | Swift Testing unit test target dir | ✓ VERIFIED | Exists |
| `validationLedgerUITests/.gitkeep` | XCUITest UI test target dir | ✓ VERIFIED | Exists |
| `validationLedgerDeviceTests/.gitkeep` | Device-only Swift Testing target dir | ✓ VERIFIED | Exists |
| `validationLedger.xcodeproj/xcshareddata/xcschemes/validationLedger.xcscheme` | Shared scheme excluding device tests (D-03) | ✓ VERIFIED | `validationLedgerDeviceTests` absent from scheme Test action |
| `Package.swift` | swift-tools-version 6.0, Nuke 13.0.2, SwiftLintPlugins 0.63.2 | ✓ VERIFIED | All three confirmed; `.iOS(.v17)` platform; no forbidden deps |
| `.gitignore` | Excludes xcuserdata/, DerivedData/, .build/ | ✓ VERIFIED | All three exclusions present |
| `.swiftformat` | SwiftFormat config | ✓ VERIFIED | Exists with --swiftversion 5.9 |
| `docs/ci.md` | Both CI pipelines documented (CI-04) | ✓ VERIFIED | Simulator Pipeline + Device Pipeline + Xcode version policy + DEVICE_UDID |
| `docs/cert-rotation.md` | FOUND-05 skeleton with STUB marker and 30-day reference | ✓ VERIFIED | Both present |
| `docs/adr/0001-mvvm-c-memory-conventions.md` | 6 MVVM-C memory rules, Status:Accepted | ✓ VERIFIED | `assign(to:on:) is BANNED` present; all 6 rules present |
| `docs/adr/0002-role-coordinator-swap-pattern.md` | SceneDelegate root-swap, abrupt-replace | ✓ VERIFIED | SceneDelegate, fresh AppContainer, Abrupt replace |
| `docs/adr/0003-module-layout-and-target-strategy.md` | Single Xcode target + re-evaluation triggers | ✓ VERIFIED | "single Xcode target", "Re-evaluation Triggers" section, 15 Features trigger |
| `validationLedger/Core/Logging/Logger.swift` | Logger protocol, 5 log levels | ✓ VERIFIED | `public protocol Logger` exists |
| `validationLedger/Core/Logging/PIIScrubber.swift` | Hybrid scrubber — structured + string paths | ✓ VERIFIED (partial) | Structured path: all 6 categories correct. String path: 5 of 6 categories (no fullName sweep — CR-02a) |
| `validationLedger/Core/Logging/OSLogLoggerImpl.swift` | OSLog-backed impl, PIIScrubber injected | ✓ VERIFIED | `scrubber.scrub(fields)` and `scrubber.scrubString(message)` both called in log paths |
| `validationLedger/Core/Logging/Subsystems.swift` | D-17 subsystem constants, one per Core module | ✓ VERIFIED | `com.maldin.validationLedger.networking` and 6 other module subsystems present |
| `validationLedger/Core/Logging/LogExporter.swift` | OSLogStore wrapper | ✓ VERIFIED | Exists with OSLogStore/fetch |
| `validationLedger/Core/Storage/Keychain/KeychainStore.swift` | Hand-rolled SecItem wrapper + KeychainWiper | ✓ VERIFIED | `public final class KeychainStore` with set/get/delete/enumerateAll + `KeychainWiper.wipeOnFirstLaunch` |
| `validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift` | Only ThisDeviceOnly cases (SEC-03) | ✓ VERIFIED | `afterFirstUnlockThisDeviceOnly` + `whenUnlockedThisDeviceOnly` only — never kSecAttrAccessibleAlways |
| `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` | Protocol for key operations | ✓ VERIFIED | Exists |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | P256 CryptoKit simulator fallback | ✓ VERIFIED | `P256.Signing.PrivateKey` present, internal access |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | Phase-2 fatalError stub | ✓ VERIFIED | fatalError stub; `Phase 2` reference present |
| `validationLedger/Core/Auth/SessionLockService.swift` | Protocol + Default impl, backgroundGrace=300s | ✓ VERIFIED | `backgroundGrace: TimeInterval = 5 * 60` at line 20; shouldRequireBiometric logic present |
| `validationLedger/Core/Networking/NetworkClient.swift` | Protocol + URLSession skeleton | ⚠ CODE-REVIEW | Exists and compiles; force-casts `response as! HTTPURLResponse` at lines 28+35 (CR-01 from REVIEW.md — not a Phase 1 goal failure, goal is skeleton compilation) |
| `validationLedger/Core/Navigation/DeepLinkRouter.swift` | Bootstrap-aware queue, NSLock, bootstrapComplete | ✓ VERIFIED | `bootstrapComplete()` at line 31; NSLock present in design |
| `validationLedger/Roles/Role.swift` | 5 cases in TechStack.md §4 order | ✓ VERIFIED | 5 case lines (shipper, broker, carrier, dispatch, factoring) |
| `validationLedger/Roles/RoleCoordinator.swift` | ARCH-06 protocol | ✓ VERIFIED | `protocol RoleCoordinator` |
| `validationLedger/Roles/Shipper/ShipperTabBarController.swift` | Loads, Brokers, BOL, Assistant tabs | ✓ VERIFIED | "Brokers" present |
| `validationLedger/Roles/Broker/BrokerTabBarController.swift` | Loads, Carriers, Network, Assistant | ✓ VERIFIED | "Network" present |
| `validationLedger/Roles/Carrier/CarrierTabBarController.swift` | Loads, Drivers, Documents, Assistant | ✓ VERIFIED | "Drivers" present |
| `validationLedger/Roles/Dispatch/DispatchTabBarController.swift` | Loads, Fleet, Drivers, Assistant | ✓ VERIFIED | "Fleet" present |
| `validationLedger/Roles/Factoring/FactoringTabBarController.swift` | Invoices, Carriers, Chain, Assistant | ✓ VERIFIED | "Invoices" present |
| `validationLedger/Resources/PrivacyInfo.xcprivacy` | CA92.1 + NSPrivacyTracking=false | ✓ VERIFIED | Both present; NSPrivacyCollectedDataTypes is empty array; zero tracking domains |
| `validationLedger/App/Info.plist` | ATS-strict, UISceneDelegateClassName wired | ✓ VERIFIED | All 4 NSAllowsArbitrary* = false; no NSExceptionDomains; SceneDelegate class wired |
| `validationLedger/App/AppDelegate.swift` | @main UIKit AppDelegate, Keychain wipe before AppContainer | ✓ VERIFIED | `@main` present; `KeychainWiper.wipeOnFirstLaunch` at line 18 (before scene construction) |
| `validationLedger/App/SceneDelegate.swift` | UIWindowSceneDelegate, presentRoot, DEBUG shake | ✓ VERIFIED | All three present; ForceRoleForUITest DEBUG launch-arg handler present |
| `validationLedger/App/AppContainer.swift` | Initializer DI, #if DEBUG && targetEnvironment(simulator) KeyStore gate, MockURLProtocol #if DEBUG | ✓ VERIFIED | All three confirmed at lines 38, 52 |
| `validationLedger/App/AppCoordinator.swift` | AppPhase → root VC resolver | ✓ VERIFIED | Exists |
| `validationLedger/App/DevMenu/DevMenuViewController.swift` | #if DEBUG gated, 3-section table | ✓ VERIFIED (with CR-03 note) | #if DEBUG in first 10 lines; CR-03 force-unwrap on Row(rawValue:)! at line 68 (DEBUG-only; doesn't affect Phase 1 goal but is a known code quality issue) |
| `validationLedger/App/DevMenu/KeychainInspectorViewController.swift` | enumerateAll, #if DEBUG | ✓ VERIFIED | Both confirmed |
| `validationLedger/App/DevMenu/LogViewerViewController.swift` | LogExporter, #if DEBUG | ✓ VERIFIED | Both confirmed |
| `.swiftlint.yml` | 4 D-19 custom rules, Phase 3 deferral note for raw-coord rule | ✓ VERIFIED | ban_print, ban_direct_os_log, ban_userdefaults_tokens, no_cross_feature_import all present; Phase 3 deferral documented; no `no_raw_coordinate_literals` literal string |
| `scripts/pre-commit.sh` | Executable, swiftformat + swiftlint --strict | ✓ VERIFIED | Executable; both references present |
| `scripts/install-hooks.sh` | Executable, worktree-safe installer | ✓ VERIFIED | Executable |
| `.github/workflows/ci-simulator.yml` | macos-latest, Xcode 16.4, iPhone 15/iOS 17.5, excludes device tests, check-privacy-manifest, coverage gate | ✓ VERIFIED | All confirmed; `validationLedgerDeviceTests` absent from -only-testing flags |
| `.github/workflows/ci-device.yml` | self-hosted runner, DEVICE_UDID, security-path filter | ✓ VERIFIED | `[self-hosted, macOS, device]`, `secrets.DEVICE_UDID`, Core/Auth/**, Core/KeyStore/**, Core/Identity/**, Core/Networking/CertificatePinning/** paths |
| `validationLedgerUITests/RoleShellSmokeTests.swift` | 5 per-role XCUITest cases (CI-02) | ✓ VERIFIED | `grep -c "func test"` = 5; all 5 role names + D-09 tab titles present |
| `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` | 2 @Test cases (D-06 device smoke) | ✓ VERIFIED | `@Test` count = 2; SecureEnclave.isAvailable + Keychain round-trip |
| `scripts/check-privacy-manifest.sh` | Executable, PrivacyInfo check | ✓ VERIFIED | Executable; ITMS-91053 diagnostic present |
| `scripts/check-coverage.sh` | Executable, 70% threshold, /Core/ filter | ✓ VERIFIED | Executable; threshold 70 + /Core/ filter confirmed |
| `validationLedgerTests/Logging/PIIScrubberTests.swift` | 7 test cases (all 6 categories + string-path) | ✓ VERIFIED | @Suite present; 7 @Test functions: phone, DL, fullName, MC/DOT (parameterized), email, coords-removed, string-path-phone. Plan 05 confirms 30/30 tests passing |
| `validationLedgerTests/Storage/KeychainWipeTests.swift` | FOUND-02 enumerate-before-delete + flag-gated | ✓ VERIFIED | `didCompleteFirstLaunch` present; .serialized suite trait |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `AppDelegate` | `KeychainWiper.wipeOnFirstLaunch` | synchronous call before SceneDelegate | ✓ WIRED | Line 18 of AppDelegate.swift, before any window/scene creation |
| `AppContainer` | `SecureEnclaveKeyStore` / `SoftwareKeyStore` | `#if DEBUG && targetEnvironment(simulator)` gate | ✓ WIRED | Lines 38-44 of AppContainer.swift |
| `AppContainer` | `MockURLProtocol` | `#if DEBUG` gate | ✓ WIRED | Lines 52-53 of AppContainer.swift |
| `OSLogLoggerImpl` | `PIIScrubber` | initializer injection + `scrubber.scrub()` call | ✓ WIRED | scrubber injected in init; called in both log paths |
| `SceneDelegate` | `DeepLinkRouter.receive` | `openURLContexts` delegation | ✓ WIRED | SceneDelegate.scene(_:openURLContexts:) calls router |
| `SceneDelegate.presentRoot` | `AppContainer` + `AppCoordinator` | fresh alloc per role swap (ADR-0002) | ✓ WIRED | Plan 05 confirms single strong reference pattern |
| `DevMenuViewController` | `KeychainInspectorViewController` | UIKit push | ✓ WIRED | `KeychainInspectorViewController` referenced in `didSelectRowAt` |
| `KeychainInspectorViewController` | `KeychainStore.enumerateAll` | direct call | ✓ WIRED | Confirmed by grep |
| `LogViewerViewController` | `LogExporter.fetch` | direct call | ✓ WIRED | Confirmed by grep |
| `ci-simulator.yml` | `validationLedgerTests` + `validationLedgerUITests` (NOT device tests) | `-only-testing:` flags | ✓ WIRED | Device tests excluded; D-03 enforced |
| `ci-device.yml` | `SecureEnclaveSmokeTests` | `-only-testing:validationLedgerDeviceTests/SecureEnclaveSmokeTests` | ✓ WIRED | Confirmed in YAML |
| `Package.swift` | Nuke 13.0.2 + SwiftLintPlugins 0.63.2 | `.package(url:exact:)` + `.package(url:from:)` | ✓ WIRED | Both confirmed |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `PIIScrubberTests` | scrubber output | `PIIScrubber.scrub()` / `scrubString()` | Yes — real regex transforms on test inputs | ✓ FLOWING |
| `KeychainWipeTests` | Keychain items | `KeychainStore.enumerateAll()` / `SecItemCopyMatching` | Yes — real SecItem calls on simulator Keychain | ✓ FLOWING |
| `SessionLockServiceTests` | `shouldRequireBiometric` | `DefaultSessionLockService` state + `Date()` | Yes — real date arithmetic | ✓ FLOWING |
| `KeychainInspectorViewController` | items array | `KeychainStore.enumerateAll()` | Yes — real SecItem calls | ✓ FLOWING |
| `LogViewerViewController` | log entries | `LogExporter.fetch(since:)` → OSLogStore | Yes — real OSLog store query | ✓ FLOWING |
| `RoleShellSmokeTests` | tab bar state | `SceneDelegate.presentRoot` via `-ForceRoleForUITest` launch arg | Yes — real UIKit tab bar construction from TabBarController subclasses | ✓ FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Deployment target is iOS 17.0 | `grep -c "IPHONEOS_DEPLOYMENT_TARGET = 17.0" project.pbxproj` | 8 (≥2 required) | ✓ PASS |
| No SwiftUI in app launch path | `grep -r "import SwiftUI" validationLedger/ --include="*.swift"` | 0 matches | ✓ PASS |
| SwiftUI scaffold deleted | `test ! -f validationLedger/validationLedgerApp.swift && test ! -f validationLedger/ContentView.swift` | Both exit 0 | ✓ PASS |
| Package.swift tools version | `grep -q "swift-tools-version: 6.0" Package.swift` | Found | ✓ PASS |
| No forbidden SDKs in Package.swift | `grep -E "(Alamofire|KeychainAccess|XCoordinator|Sentry|Firebase|Crashlytics)" Package.swift` | 0 matches | ✓ PASS |
| PIIScrubber structured-path all 6 categories | Reviewed PIIScrubber.swift scrub() switch cases | phone/DL/fullName/mcNumber/dotNumber/email/coordinates all handled | ✓ PASS |
| PIIScrubber string-path fullName sweep | Reviewed scrubString() body | No name pattern — only phone, coords, email, MC/DOT, DL | ✗ FAIL (CR-02a) |
| PrivacyInfo.xcprivacy CA92.1 + zero tracking | `plutil` + file inspection | NSPrivacyAccessedAPICategoryUserDefaults/CA92.1; NSPrivacyTracking=false; empty collected data | ✓ PASS |
| ATS-strict Info.plist | `grep -q "NSAllowsArbitraryLoads" + no NSExceptionDomains` | 4 keys all false; no exceptions | ✓ PASS |
| DevMenu #if DEBUG gated | `head -10 validationLedger/App/DevMenu/*.swift \| grep "#if DEBUG"` | All 5 DevMenu files have #if DEBUG in first 10 lines | ✓ PASS |
| KeychainWiper in AppDelegate before AppContainer | `grep -n "wipeOnFirstLaunch" AppDelegate.swift` | Line 18 — before scene construction | ✓ PASS |
| AppContainer no .shared | `grep -rq "\.shared" validationLedger/App/` | UIApplication.shared at DevMenuViewController line 84 (UIKit platform API — not a singleton DI violation; ARCH-04 is about service injection, not UIKit framework APIs) | ✓ PASS (UIApplication.shared is UIKit framework access, not an ARCH-04 violation) |
| Simulator CI excludes device tests (D-03) | `grep -q "validationLedgerDeviceTests" ci-simulator.yml` | Not found — D-03 satisfied | ✓ PASS |
| Shared xcscheme excludes device tests | `grep "validationLedgerDeviceTests" validationLedger.xcscheme` | Not found | ✓ PASS |
| SwiftLint 4 custom rules present | `grep -q "ban_print\|ban_direct_os_log\|ban_userdefaults_tokens\|no_cross_feature_import" .swiftlint.yml` | All 4 found | ✓ PASS |
| Raw-coord rule absent (deferred to Phase 3) | `! grep -q "no_raw_coordinate_literals" .swiftlint.yml` | Not present | ✓ PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FOUND-01 | 01-03 | PIIScrubber with 6 redaction categories | ✓ SATISFIED (partial gap) | Structured path: all 6 categories correct. String path: 5/6 (no name sweep, CR-02a). Tests pass for structured path + phone in string path. |
| FOUND-02 | 01-03, 01-05 | First-launch Keychain wipe | ✓ SATISFIED | KeychainWiper.wipeOnFirstLaunch in AppDelegate line 18; 2 serialized tests prove contract; KeychainInspector UI |
| FOUND-03 | 01-02 | MVVM-C memory conventions documented | ✓ SATISFIED | docs/adr/0001-mvvm-c-memory-conventions.md; Status: Accepted; all 6 rules including assign(to:on:) BANNED |
| FOUND-04 | 01-07 | CI pipeline split (sim + device) | ✓ SATISFIED (structural) | Both YAML files committed; docs/ci.md documents both; actual first-run pending HUMAN-UAT |
| FOUND-05 | 01-02 | Cert rotation runbook skeleton | ✓ SATISFIED | docs/cert-rotation.md with STUB marker, 30-day rotation outline, Phase 2 deferral explicit |
| FOUND-06 | 01-04, 01-07 | PrivacyInfo.xcprivacy with required-reason APIs | ✓ SATISFIED | File present; CA92.1 for UserDefaults; zero tracking; check-privacy-manifest.sh in CI |
| FOUND-07 | 01-03 | SessionLockService unified source of truth | ✓ SATISFIED | Protocol + DefaultSessionLockService; backgroundGrace=300s; 4 tests cover state machine |
| FOUND-08 | 01-03 | DeepLinkRouter bootstrap queue | ✓ SATISFIED | bootstrapComplete() drains FIFO queue; NSLock; 3 tests verify |
| ARCH-01 | 01-01, 01-05 | No SwiftUI in launch path; UIKit AppDelegate/SceneDelegate | ✓ SATISFIED | SwiftUI files deleted; @main on UIKit AppDelegate; 0 import SwiftUI in validationLedger/ |
| ARCH-02 | 01-01 | iOS 17.0 deployment target | ✓ SATISFIED | 8× = 17.0 in pbxproj; 0× = 26 remaining |
| ARCH-03 | 01-04, 01-05 | Module layout matches TechStack.md §3.2 | ✓ SATISFIED | App/, Core/{Logging,Storage,KeyStore,Auth,Networking,Navigation}, Features/{7 dirs}, Roles/, UI/DesignSystem, Resources/ all present |
| ARCH-04 | 01-05 | AppContainer initializer DI, no singletons | ✓ SATISFIED | AppContainer final class with stored service properties; no .shared on app services; UIApplication.shared at DevMenu line 84 is UIKit framework access (not a service singleton) |
| ARCH-05 | 01-06 | No cross-feature imports; SwiftLint rule | ✓ SATISFIED | no_cross_feature_import rule in .swiftlint.yml; fires on planted violations |
| ARCH-06 | 01-04, 01-05 | RoleCoordinator swaps root at SceneDelegate | ✓ SATISFIED | SceneDelegate.presentRoot(_:) allocates fresh AppContainer + AppCoordinator per role change; 6 RoleCoordinatorTests pass |
| STACK-01 | 01-02 | Package.swift SwiftPM-only, Nuke 13.0.2, no forbidden deps | ✓ SATISFIED | Confirmed via grep; swift package describe parses cleanly |
| STACK-02 | 01-06 | SwiftLint + SwiftFormat configured | ✓ SATISFIED | .swiftlint.yml + .swiftformat at repo root; pre-commit hook installable |
| STACK-03 | 01-03, 01-07 | Swift Testing for unit tests; XCTest for UI tests | ✓ SATISFIED | @Suite/@Test in unit tests; XCTestCase in RoleShellSmokeTests; 35 total tests pass |
| STACK-04 | 01-02, 01-06 | No analytics/crash SDKs; os_log + OSLogStore | ✓ SATISFIED | Package.swift has zero forbidden deps; ban_userdefaults_tokens rule active; logging via OSLog |
| LOG-01 | 01-06 | No direct print()/os_log() in app code; SwiftLint rule | ✓ SATISFIED | ban_print + ban_direct_os_log rules active; ban_direct_os_log correctly excludes Core/Logging/; both fire on planted violations |
| LOG-02 | 01-03 | Logger protocol with 5 levels | ✓ SATISFIED | LogLevel enum with trace/debug/info/warn/error; extension methods; 2 tests verify |
| LOG-03 | 01-05 | OSLogStore viewer in DEBUG dev menu | ✓ SATISFIED | LogViewerViewController (#if DEBUG); uses LogExporter.fetch(since:); accessible via shake → DevMenu |
| SEC-02 | 01-04 | ATS-strict Info.plist | ✓ SATISFIED | All 4 NSAllowsArbitrary* = false; zero NSExceptionDomains; plutil -lint clean |
| SEC-03 | 01-06 | Keychain for tokens; ban_userdefaults_tokens rule | ✓ SATISFIED | KeychainStore with ThisDeviceOnly accessibility; ban_userdefaults_tokens fires on "sessionToken" key pattern; hand-rolled (no KeychainAccess dep) |
| CI-01 | 01-07 | Coverage gate ≥70% on Core/ | ✓ SATISFIED | scripts/check-coverage.sh committed; 70% threshold; invoked in ci-simulator.yml; local run confirmed 77.43% on Core/ |
| CI-02 | 01-07 | 5 per-role UI smoke tests | ✓ SATISFIED (Phase 1 scope) | RoleShellSmokeTests.swift with 5 XCUITest cases; all 5 pass locally; full OTP→logout flow explicitly deferred to Phase 3 per Assumption A10/Flag #3 |
| CI-04 | 01-02 | CI documented in docs/ci.md | ✓ SATISFIED | Both pipelines documented with triggers, runners, Xcode version policy, secrets, known tradeoff |

**All 26 Phase 1 REQ-IDs addressed. CI-02 Phase 1 scope is placeholder UI tests (tab inventory verification); full OTP→logout smoke is Phase 3 scope per ROADMAP.**

---

### Code-Review-Flagged Issues (from 01-REVIEW.md)

These are code quality issues identified in the post-execution review. They are noted here for traceability but evaluated against phase goal achievement, not as verification failures unless they break a success criterion.

**CR-01 (Critical): `URLSessionNetworkClient` force-casts `URLResponse` to `HTTPURLResponse`**
- File: `validationLedger/Core/Networking/NetworkClient.swift` lines 28, 35
- Issue: `response as! HTTPURLResponse` crashes on non-HTTP responses
- Phase 1 goal impact: LOW — Phase 1 goal is "NetworkClient protocol + skeleton compiles"; the force-cast is a correctness defect in the skeleton that will manifest in Phase 2 when real networking lands. Does not break any Phase 1 success criterion.
- Recommendation: Fix before Phase 2 networking work begins (net fix is a `guard let http = response as? HTTPURLResponse else { throw NetworkError.unexpectedResponseType(response) }` pattern)

**CR-02 (Critical): PIIScrubber string-path missing fullName sweep; DL regex prone to false-positives**
- File: `validationLedger/Core/Logging/PIIScrubber.swift` lines 41-68
- Issue (a): `scrubString()` has no fullName/name pattern sweep — D-16 "string path cannot bypass redaction" is violated for names
- Issue (b): DL regex `\b[A-Z]{1,2}[0-9]{5,8}\b` matches transaction IDs like TX1234567
- Phase 1 goal impact: MODERATE for (a) — SC-2 requires the PII scrubber to redact full names, and the string path bypass is a real gap. This is the sole item preventing SC-2 from being fully verified. (b) is a warning-level over-redaction concern, not a missing category.

**CR-03 (Critical): `DevMenuViewController.cellForRowAt` force-unwraps `Row(rawValue:)!`**
- File: `validationLedger/App/DevMenu/DevMenuViewController.swift` line 68
- Issue: Will crash on row-count mismatch under accessibility or mid-scroll reload
- Phase 1 goal impact: LOW — DevMenu is entirely #if DEBUG gated; crash is DEBUG-only and only under edge-case UIKit conditions. Does not affect any Phase 1 success criterion. Fix is trivial (guard let row = ...).

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `validationLedger/Core/Logging/PIIScrubber.swift` | 41-68 | Missing `fullName` sweep in `scrubString()` | BLOCKER | SC-2 partially unmet — string-path cannot bypass redaction claim violated for names |
| `validationLedger/Core/Networking/NetworkClient.swift` | 28, 35 | `response as! HTTPURLResponse` force-cast | WARNING | Phase 2 crash risk on non-HTTP responses; Phase 1 skeleton still compiles |
| `validationLedger/App/DevMenu/DevMenuViewController.swift` | 68 | `Row(rawValue: indexPath.row)!` force-unwrap | WARNING | DEBUG-only crash under edge-case UIKit conditions; low Phase 1 impact |
| `validationLedger/Core/Networking/MockURLProtocol.swift` | 10 | `static var handlers` global mutable state | INFO | Phase 2 test race risk when parallel tests mutate handlers; Phase 1 has only 2 tests |
| `scripts/check-coverage.sh` | 50-52 | Integer truncation on coverage percentage | INFO | 69.99% prints as 69 in output (misleading log); gate math is actually correct |
| `scripts/pre-commit.sh` | 53-55 | Silent 20-file cap on staged files linted | INFO | Files >20 in staging not linted; no warning emitted |

---

### Human Verification Required

#### 1. Simulator UIKit Launch + Full DevMenu Interaction (Plan 05 Task 3)

**Test:** Open `validationLedger.xcodeproj` in Xcode, select iPhone 17 Pro (iOS 26.4) or any available simulator, run (Cmd+R).
**Expected:** App launches showing 4-tab bar (Loads, Brokers, BOL, Assistant). Simulator shake (Device → Shake or Ctrl+Cmd+Z) presents DevMenu with 3 rows. Tapping Role Switcher → Broker changes tabs to Loads/Carriers/Network/Assistant. Xcode console shows `app_coordinator_deinit` / `app_container_deinit` / `app_container_init` / `app_coordinator_init` sequence.
**Why human:** Interactive simulator gestures and visual/console observation required. Parallel executor confirmed automated gates (35/35 tests, Release strings grep, Debug + Release builds) but deferred 8-step manual checklist.

#### 2. Keychain Wipe Visual Proof (FOUND-02 device-level)

**Test:** Fresh install on simulator or device. DevMenu → Keychain Inspector.
**Expected:** Shows "(empty — 0 items)" confirming wipe ran on first launch.
**Why human:** Requires interactive install + DevMenu navigation.

#### 3. PII String-Path Name Redaction (SC-2 gap)

**Test:** Once CR-02a fix is applied, inject `logger.info("User John Doe failed KYC")` and check Log Viewer.
**Expected:** Log shows "User J. D. failed KYC" (name reduced to initials).
**Why human:** Currently a code gap — fix must be written first, then manually tested. Automated test (unit test in PIIScrubberTests) should be added alongside the fix.

#### 4. CI Simulator Pipeline — PR Trigger (Plan 07 Task 5 Step 2)

**Test:** Add git remote, push branch, open PR against main. Confirm `CI (Simulator)` workflow runs green on GitHub Actions.
**Expected:** All CI steps pass including SwiftLint strict (0 violations), xcodebuild test (35/35), privacy manifest check, coverage gate (≥70%).
**Why human:** Requires git remote configuration and GitHub Actions — worktree has no remote configured.

#### 5. Planted-Violation CI Reject Cycle (Plan 07 Task 5 Step 3)

**Test:** Insert `print("test")` in AppDelegate.swift, push to PR branch, confirm CI fails at SwiftLint step with `ban_print` violation. Revert and confirm CI goes green.
**Expected:** ban_print rule blocks merge; revert unblocks it.
**Why human:** Requires PR infrastructure.

#### 6. Device CI Pipeline (Plan 07 Task 5 Step 4)

**Test:** Register self-hosted runner with labels [self-hosted, macOS, device]. Add DEVICE_UDID secret (48F5B3CC-0E06-50CE-BFD4-8A0A136E144D). Merge PR to main. Confirm `CI (Device)` workflow triggers and both SecureEnclaveSmokeTests pass on paired iPhone 15 Pro Max.
**Expected:** `SecureEnclave.isAvailable == true` + Keychain round-trip both pass on physical hardware.
**Why human:** Requires self-hosted runner setup + physical device.

---

### Gaps Summary

One programmatically-verified gap (SC-2 partial):

**`PIIScrubber.scrubString()` missing fullName sweep (CR-02a):** The string path in `scrubString()` applies regex sweeps for phone, coordinates, email, MC/DOT, and DL patterns — but has no sweep for full names. The structured path via `LogField.fullName` correctly reduces names to initials. However, any caller using the string convenience API (e.g., `logger.info("User John Doe failed KYC")`) bypasses name redaction entirely. D-16 states "string-based Logger calls cannot bypass redaction" — this claim is violated for names. SC-2 requires the PII scrubber to redact full names; the structured path satisfies this but the string path does not.

**Fix required before SC-2 is fully met:** Add a name pattern sweep to `scrubString()`:
```swift
let namePattern = #"\b[A-Z][a-z]+(?:\s[A-Z][a-z]+)+"#
s = Self.regexReplace(s, pattern: namePattern) { match in
    let parts = match.split(separator: " ")
    return parts.map { "\($0.first!)." }.joined(separator: " ")
}
```
And add a corresponding test case to `PIIScrubberTests` for the string-path name redaction.

All other 25 Phase 1 REQ-IDs are satisfied. The 8 human verification items are either interactive UX flows (simulator DevMenu, PII spot-check), CI infrastructure that requires a git remote (PR trigger, planted-violation cycle, device CI), or require the CR-02a fix first. None of the human items represent missing code — they are observation tasks against code that exists and compiles.

---

_Verified: 2026-04-21T09:31:59Z_
_Verifier: Claude (gsd-verifier)_
