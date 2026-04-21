---
phase: 1
slug: foundational-conventions-scaffolding
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 16+ bundled) for unit tests; XCTest + XCUITest for UI tests |
| **Config file** | None — Swift Testing requires no config; `Package.swift` `swift-tools-version: 6.0` is sufficient |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests/Logging/PIIScrubberTests` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -enableCodeCoverage YES` |
| **Device smoke command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests` |
| **Estimated runtime** | ~90s quick / ~10min full simulator / ~2min device smoke |

---

## Sampling Rate

- **After every task commit:** `swift run swiftlint --strict` + quickest relevant unit test (e.g., `-only-testing:validationLedgerTests/Logging/PIIScrubberTests`). Target < 60s.
- **After every plan wave:** Full simulator suite with coverage: `xcodebuild test -enableCodeCoverage YES`. Target < 10 min.
- **Before `/gsd-verify-work`:** Full simulator suite green + SwiftLint strict + device CI smoke green + `PrivacyInfo.xcprivacy` grep check + DevMenu manual pass of 5-role swap.
- **Max feedback latency:** 60s per task, 600s per wave.

---

## Per-Task Verification Map

> Per-REQ coverage; Task IDs are filled in by the planner once plans are written. Test Type column indicates the stratum.

| REQ-ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|--------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| FOUND-01 | TBD | 0→A | PIIScrubber redacts 6 categories | T-01 PII-in-logs | Only logging path; string overload routes through scrubber | unit | `xcodebuild test -only-testing:validationLedgerTests/Logging/PIIScrubberTests` | ❌ W0 | ⬜ pending |
| FOUND-02 | TBD | A | First-launch Keychain wipe deletes pre-existing items | T-02 Keychain reinstall leak | Enumerate-before-delete under app access group | integration + manual | `xcodebuild test -only-testing:validationLedgerTests/Storage/KeychainWipeTests` + DevMenu visual confirm | ❌ W0 | ⬜ pending |
| FOUND-03 | TBD | B | MVVM-C memory conventions codified in ADR 0001 | — | N/A | manual/review | `test -f docs/adr/0001-mvvm-c-memory-conventions.md` | ❌ W0 | ⬜ pending |
| FOUND-04 | TBD | C | Two CI pipelines exist and run on defined triggers | — | N/A | CI script | `gh workflow view ci-simulator.yml && gh workflow view ci-device.yml`; planted-violation PR must fail | ❌ W0 | ⬜ pending |
| FOUND-05 | TBD | B | `docs/cert-rotation.md` skeleton exists (full runbook Phase 2) | T-05 Self-brick pinning | Skeleton reserves path + 30-day rotation pattern note | manual/review | `test -f docs/cert-rotation.md && grep -q "30-day" docs/cert-rotation.md` | ❌ W0 | ⬜ pending |
| FOUND-06 | TBD | C | `PrivacyInfo.xcprivacy` in `.app` bundle (Copy Bundle Resources) | T-08 ITMS-91053 rejection | Manifest present post-build | CI script | `test -f "$BUILT_PRODUCTS_DIR/validationLedger.app/PrivacyInfo.xcprivacy"` | ❌ W0 | ⬜ pending |
| FOUND-07 | TBD | A | SessionLockService protocol + stub + `shouldRequireBiometric` logic | T-03 Session invariant | Single source of truth for biometric prompt | unit | `xcodebuild test -only-testing:validationLedgerTests/Auth/SessionLockServiceTests` | ❌ W0 | ⬜ pending |
| FOUND-08 | TBD | A | DeepLinkRouter queues pre-bootstrap, drains on ready | — | N/A | unit | `xcodebuild test -only-testing:validationLedgerTests/Navigation/DeepLinkRouterTests` | ❌ W0 | ⬜ pending |
| ARCH-01 | TBD | A | UIKit launch path; no SwiftUI in `App/` | — | N/A | build + review | `! grep -r "import SwiftUI" validationLedger/App/ validationLedger/Features/ validationLedger/Core/` returns 0 (no hits); `xcodebuild build` succeeds | — | ⬜ pending |
| ARCH-02 | TBD | A | iOS deployment target = 17.0 | — | N/A | review | `grep IPHONEOS_DEPLOYMENT_TARGET validationLedger.xcodeproj/project.pbxproj` shows `17.0` | — | ⬜ pending |
| ARCH-03 | TBD | A | Module layout matches TechStack.md §3.2 + ARCHITECTURE.md amendments | — | N/A | review | File tree matches §Recommended Project Structure from RESEARCH.md | — | ⬜ pending |
| ARCH-04 | TBD | A | `AppContainer` initializer-DI; no singletons in application code | — | Composition root is only place that sees concretes | unit + review | No `.shared` references outside `OSLog.Logger`; `AppContainer.init` takes `Environment` | — | ⬜ pending |
| ARCH-05 | TBD | B | Features do not import each other | T-09 Cross-feature coupling | Lint rule enforces boundary | SwiftLint | `swift run swiftlint lint --strict` with rule `no_cross_feature_import` passes; planted violation fails | ❌ W0 | ⬜ pending |
| ARCH-06 | TBD | A+C | `RoleCoordinator` root-swap at `SceneDelegate`; fresh `AppContainer` per swap | T-04 Dev surface in Release | Abrupt replace, deterministic dealloc | unit + DevMenu manual | `xcodebuild test -only-testing:validationLedgerTests/Roles/RoleCoordinatorTests` + DevMenu visual — old coordinator deinit logs | ❌ W0 | ⬜ pending |
| STACK-01 | TBD | A | `Package.swift` declares only allowed deps | — | N/A | review | `cat Package.swift` matches RESEARCH.md §Installation; only Nuke allowed | ❌ W0 | ⬜ pending |
| STACK-02 | TBD | B | SwiftLint + SwiftFormat + pre-commit hook | — | N/A | CI + review | `swift run swiftlint --version` ok; `swiftformat --version` ok; `.git/hooks/pre-commit` exists | ❌ W0 | ⬜ pending |
| STACK-03 | TBD | A | Swift Testing for unit tests; XCTest for UI tests | — | N/A | review | `grep -r "import Testing" validationLedgerTests/` has hits; `grep -r "import XCTest" validationLedgerUITests/` has hits | ❌ W0 | ⬜ pending |
| STACK-04 | TBD | A | Zero crash/analytics SDK | — | N/A | review | `grep -E "(Sentry\|Crashlytics\|Firebase\|Amplitude\|Mixpanel)" Package.swift` returns empty | — | ⬜ pending |
| LOG-01 | TBD | B | No direct `print()` / `os_log()` outside `Core/Logging/` | T-01 PII-in-logs | SwiftLint enforcement | SwiftLint | `swift run swiftlint --strict` with rules `ban_print` + `ban_direct_os_log`; planted violation fails | ❌ W0 | ⬜ pending |
| LOG-02 | TBD | A | `Logger` supports 5 levels with correct defaults | — | N/A | unit | `xcodebuild test -only-testing:validationLedgerTests/Logging/LoggerLevelsTests` | ❌ W0 | ⬜ pending |
| LOG-03 | TBD | C | DevMenu exposes `OSLogStore` viewer in DEBUG; absent in Release | T-04 Dev surface in Release | `#if DEBUG` physical absence | build + manual | DEBUG build: shake gesture → log viewer. Release build: `strings validationLedger.app/validationLedger \| grep -i "LogViewer"` returns empty | ❌ W0 | ⬜ pending |
| SEC-02 | TBD | A | ATS strict in `Info.plist`; no exceptions | T-07 Plaintext HTTP | No `NSAllowsArbitraryLoads`, no `NSExceptionDomains` | review | `! grep NSAllowsArbitraryLoads validationLedger/App/Info.plist && ! grep NSExceptionDomains validationLedger/App/Info.plist` | — | ⬜ pending |
| SEC-03 | TBD | B | SwiftLint flags `UserDefaults` writes of sensitive keys | T-03 Token in UserDefaults | Lint rule `ban_userdefaults_tokens` | SwiftLint | Plant `UserDefaults.standard.set("abc", forKey: "sessionToken")` → lint fails strict | ❌ W0 | ⬜ pending |
| CI-01 | TBD | C | ≥70% coverage on `Core/` | — | N/A | CI script | `xcodebuild test -enableCodeCoverage YES` + coverage parser ≥ 70% on `Core/**` | ❌ W0 | ⬜ pending |
| CI-02 | TBD | C | 5 placeholder UI tests (one per role) render + pass | — | N/A | CI script | `xcodebuild test -only-testing:validationLedgerUITests/RoleShellSmokeTests` — 5 placeholder tests per role (tab title + SF Symbol render only; full OTP→logout flow is Phase 3 per Assumption A10) | ❌ W0 | ⬜ pending |
| CI-04 | TBD | C | `docs/ci.md` documents both pipelines | — | N/A | review | `test -f docs/ci.md && grep -q "Simulator Pipeline" docs/ci.md && grep -q "Device Pipeline" docs/ci.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Wave labels — A: structural, B: conventions + lint rules, C: CI + privacy + DevMenu (from RESEARCH.md suggested grouping).*

---

## Wave 0 Requirements

Phase 1 test infrastructure does not exist yet. Wave 0 creates these test targets + files BEFORE any feature code:

- [ ] `validationLedgerTests/` Swift-Testing target registered in `validationLedger.xcodeproj` — covers FOUND-01/02/07/08, ARCH-06 (unit slice), LOG-02, CI-01 scaffolding
- [ ] `validationLedgerTests/Logging/PIIScrubberTests.swift` — FOUND-01 (6-category redaction)
- [ ] `validationLedgerTests/Logging/LoggerLevelsTests.swift` — LOG-02 (5-level defaults)
- [ ] `validationLedgerTests/Storage/KeychainWipeTests.swift` — FOUND-02 (enumerate-before-delete)
- [ ] `validationLedgerTests/Auth/SessionLockServiceTests.swift` — FOUND-07 (`shouldRequireBiometric` stub)
- [ ] `validationLedgerTests/Navigation/DeepLinkRouterTests.swift` — FOUND-08 (queue + drain)
- [ ] `validationLedgerTests/Roles/RoleCoordinatorTests.swift` — ARCH-06 (protocol contract + swap dealloc)
- [ ] `validationLedgerUITests/` XCUITest target — covers CI-02 placeholder
- [ ] `validationLedgerUITests/RoleShellSmokeTests.swift` — CI-02 (5 per-role placeholder tests)
- [ ] `validationLedgerDeviceTests/` device-CI target — covers D-06 smoke
- [ ] `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` — D-06 (`SecureEnclave.isAvailable == true` + Keychain round-trip)
- [ ] `.swiftlint.yml` with 4 custom rules (`ban_print`, `ban_direct_os_log`, `ban_userdefaults_tokens`, `no_cross_feature_import`)
- [ ] `.swiftformat` config
- [ ] `.git/hooks/pre-commit` running `swiftlint --strict` + `swiftformat --lint`
- [ ] `.github/workflows/ci-simulator.yml`
- [ ] `.github/workflows/ci-device.yml`
- [ ] Swift Testing framework install: **none — bundled with Xcode 16+ (verified)**

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| DevMenu shake-gesture invocation reveals role switcher + Keychain inspector + `OSLogStore` viewer | LOG-03, D-11, D-12 | Simulator "Device → Shake" not reliably scriptable in CI | Launch DEBUG build on iPhone 15 simulator → Device menu → Shake → DevMenu appears → tap Roles → select each of 5 roles → confirm tab bar icons + titles match TechStack.md §4 for that role |
| Keychain wipe before/after first launch (DevMenu inspector) | FOUND-02, D-20 | Requires app reinstall on physical device | Install on device → DevMenu → Keychain Inspector → plant a fake item with `security add-generic-password` equivalent → delete app → reinstall → DevMenu → Keychain Inspector → 0 items |
| DevMenu absent from Release build (strings probe) | LOG-03, D-13 | Release archive required | Build Release configuration → extract `.ipa` → `strings validationLedger.app/validationLedger \| grep -iE "DevMenu\|LogViewer\|RoleSwitcher"` returns empty |
| `PrivacyInfo.xcprivacy` in Copy Bundle Resources (post-build .ipa inspection) | FOUND-06, SEC-02, D-21 | `.ipa` must be built by CI and inspected | After CI simulator build: `unzip -p validationLedger.ipa Payload/validationLedger.app/PrivacyInfo.xcprivacy` shows declared APIs (CA92.1 for UserDefaults) |
| SceneDelegate root-swap deterministic dealloc | ARCH-06, D-10 | Runtime deinit observation | DEBUG build → DevMenu → role swap → old `AppCoordinator` `deinit` log message appears in Xcode console before new root renders |
| Physical device Secure Enclave smoke test | D-06, CI-02-precursor | Real hardware required | Self-hosted runner executes `validationLedgerDeviceTests/SecureEnclaveSmokeTests`; passes on paired iPhone attached to dev MacBook |

---

## Validation Sign-Off

- [ ] All 26 REQ-IDs have `<automated>` verify or are mapped to Wave 0 test files
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all ❌ MISSING references above (10+ test files + 2 lint configs + 2 CI workflows)
- [ ] No watch-mode flags in any command (one-shot xcodebuild invocations only)
- [ ] Feedback latency < 60s per task, < 600s per wave
- [ ] `nyquist_compliant: true` set in frontmatter after planner completes Wave 0 task enumeration

**Approval:** pending
