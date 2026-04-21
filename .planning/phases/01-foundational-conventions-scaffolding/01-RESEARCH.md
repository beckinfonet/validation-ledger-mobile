# Phase 1: Foundational Conventions & Scaffolding — Research

**Researched:** 2026-04-20
**Domain:** UIKit iOS 17.0 app scaffolding + tooling/CI/logging conventions for a security-sensitive, 5-role freight identity product
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (copied verbatim from CONTEXT.md)

**CI — Simulator pipeline**
- **D-01:** GitHub Actions runs the simulator pipeline on every PR. macOS-latest runner image. (FOUND-04, CI-01, CI-04)
- **D-02:** Simulator CI minimum-gate bar for Phase 1: `xcodebuild build -destination 'platform=iOS Simulator,...'` must succeed + SwiftLint passes + unit tests pass on `Core/Logging/PIIScrubber`, `Core/Storage/Keychain/KeychainStore`, `Core/Networking/MockURLProtocol` (scaffolding + fixtures), `Core/Auth/SessionLockService` logic. Target coverage ≥70% on `Core/` (CI-01).
- **D-03:** Simulator CI explicitly excludes Secure Enclave / biometric code paths (they require real hardware).

**CI — Physical-device pipeline**
- **D-04:** Self-hosted runner on the developer MacBook with an attached iPhone. GitHub Actions self-hosted runner mode. *Re-evaluate at M2 boundary.*
- **D-05:** Device CI trigger policy = merge-to-main + security-path PR gate. Device pipeline runs on (a) every merge to `main` AND (b) any PR that modifies files under `Core/Auth/`, `Core/KeyStore/`, `Core/Identity/`, or `Core/Networking/CertificatePinning/`.
- **D-06:** Device CI minimum-gate bar for Phase 1: a single smoke test asserting `SecureEnclave.isAvailable == true` and that a test Keychain item can be written + read.

**Role scaffolding — Phase 1 depth**
- **D-07:** Phase 1 delivers the full dev-menu demo of ARCH-06: the `Role` enum, the `RoleCoordinator` protocol, 5 concrete per-role `UITabBarController` subclasses, and a DEBUG-only developer menu that swaps the root coordinator on tap.
- **D-08:** `Roles/` directory layout: `Roles/Role.swift`, `Roles/RoleCoordinator.swift`, `Roles/{Shipper,Broker,Carrier,Dispatch,Factoring}/{Role}TabBarController.swift`.
- **D-09:** Tab inventory per role matches TechStack.md §4 exactly:
  - Shipper: Loads, Brokers, BOL, Assistant
  - Broker: Loads, Carriers, Network, Assistant
  - Carrier: Loads, Drivers, Documents, Assistant
  - Dispatch: Loads, Fleet, Drivers, Assistant
  - Factoring: Invoices, Carriers, Chain, Assistant
- **D-10:** Root-swap mechanism at `SceneDelegate` level per research/ARCHITECTURE.md amendment #3: on role change, `SceneDelegate` constructs a fresh `AppCoordinator` on a fresh `AppContainer` scope. Abrupt replace — not a cross-dissolve.

**Dev menu**
- **D-11:** Single centralized `DevMenu` — role switcher + Keychain-item inspector + `OSLogStore` viewer.
- **D-12:** Invocation = iPhone shake gesture (`UIResponder.motionEnded(_:with:)`), matched by `Device → Shake` in Simulator.
- **D-13:** Release-build safety = `#if DEBUG` compile-out.
- **D-14:** `DevMenu` lives at `App/DevMenu/`.

**Claude's Discretion (defaults)**
- **D-15:** Single Xcode target with directory groups for Phase 1. Nuke stays as an external SwiftPM dependency. ARCH-05's "no cross-feature import" enforced by SwiftLint custom rule (D-19), not SPM packages.
- **D-16:** Hybrid PII scrubber, structured preferred. Primary API is structured with typed fields; secondary string overload exists but routes through the same scrubber.
- **D-17:** One `OSLog` subsystem per top-level `Core/` module (`com.maldin.validationLedger.networking`, `.auth`, `.keystore`, `.storage`, `.identity`, `.navigation`, etc.), with categories inside.
- **D-18:** ADRs at `docs/adr/NNNN-title.md`. Phase 1 ships: `0001-mvvm-c-memory-conventions.md`, `0002-role-coordinator-swap-pattern.md`, `0003-module-layout-and-target-strategy.md`, `docs/ci.md`, `docs/cert-rotation.md` (skeleton only).
- **D-19:** Four SwiftLint custom rules ship Phase 1: ban `print(_:)`, ban direct `os_log(...)` outside `Core/Logging/`, ban `UserDefaults` writes to keys named `*token*`/`*key*`/`*session*`, ban cross-feature imports. **Raw-coordinate-literal ban DEFERRED to Phase 3.**
- **D-20:** First-launch Keychain wipe in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` **before** any auth service resolves from `AppContainer`. `UserDefaults` `didCompleteFirstLaunch` gate. Enumerate-before-delete so the DevMenu inspector can show before/after.
- **D-21:** `PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPITypeUserDefaults` (reason `CA92.1`), empty 3rd-party SDK list, must be in Copy Bundle Resources.

### Claude's Discretion (this researcher's freedom)

Everything not locked in the decisions above. Primarily:
- Internal shape of the `AppContainer` (struct vs. class, scoping mechanism)
- Internal shape of the `PIIScrubber` (regex vs. structured field enum)
- Internal shape of the `KeychainStore` SecItem wrapper API surface
- Internal shape of the `SessionLockService` stub
- The exact SwiftLint custom rule regexes
- The test fixture format for the PII-scrubber unit test

### Deferred Ideas (OUT OF SCOPE for Phase 1)

- Raw-coordinate-literal SwiftLint ban — lands with GEO-03 in Phase 3
- Real Secure Enclave keypair generation, cert-pinning activation, `APIClient` typed endpoints — Phase 2
- 5-role OTP login, session persistence, biometric re-prompt, logout — Phase 3
- App Attest productionization + device CI real assertions — Phase 4
- KYC capture + resumable upload — Phase 5
- **Profile tab reconciliation** — Phase 3 CONTEXT decides whether Profile is a 5th tab, a top-bar avatar, or a subsurface of Assistant. Phase 1 ships §4 tabs verbatim.
- **Cert rotation runbook content** — Phase 2 fills `docs/cert-rotation.md`; Phase 1 ships only the skeleton file.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (from REQUIREMENTS.md) | Research Support |
|----|------------------------------------|------------------|
| FOUND-01 | `Core/Logging` exposes `Logger` protocol + `PIIScrubber` middleware redacting phone/name/DL/MC-DOT/email/coords before reaching `os_log`/`OSLogStore`; verified by unit test. | §Standard Stack (OSLog), §Pattern 1 (PIIScrubber design), §Code Examples (PIIScrubber sketch), §Validation Architecture row FOUND-01 |
| FOUND-02 | On first app launch, Keychain wiped for bundle id + access group; triggered once per install via `UserDefaults` flag. | §Pattern 2 (first-launch wipe), §Pitfalls P1 (canonical), §Code Examples (`enumerateAndWipe`), §Validation Architecture row FOUND-02 |
| FOUND-03 | MVVM-C memory conventions documented in CLAUDE.md (via ADR 0001) and enforced at review. | §Pattern 3 (MVVM-C rules), §ADR-0001 skeleton in §Phase 1 Deliverables, §Validation Architecture row FOUND-03 |
| FOUND-04 | CI split: simulator on every PR, physical-device on every merge to `main`; Secure Enclave / biometric / App Attest only on device. | §Pattern 4 (CI-split), §Standard Stack (GitHub Actions), §Code Examples (workflow YAML), §Validation Architecture row FOUND-04 |
| FOUND-05 | Cert pinning in `Core/Networking/CertificatePinning/` via `URLSessionDelegate`; dual-pin SPKI hash. Runbook at `docs/cert-rotation.md`. | §Scope clarification — Phase 1 ships SKELETON docs only; implementation Phase 2. §Validation Architecture row FOUND-05 (skeleton-only verification) |
| FOUND-06 | `PrivacyInfo.xcprivacy` skeleton committed, declares required-reason APIs, zero 3rd-party SDKs. | §Pattern 5 (Privacy manifest), §Code Examples (xcprivacy plist), §Validation Architecture row FOUND-06 |
| FOUND-07 | `Core/Auth/SessionLockService` single source of truth for "is current session active." | §Pattern 6 (SessionLockService stub), §Validation Architecture row FOUND-07 |
| FOUND-08 | `Core/Navigation/DeepLinkRouter` accepts links before `AppContainer` ready; queues for replay. | §Pattern 7 (bootstrap-aware deep-link queue), §Validation Architecture row FOUND-08 |
| ARCH-01 | SwiftUI scaffold removed; replaced by UIKit `AppDelegate` + `SceneDelegate` + `RootCoordinator`. No SwiftUI in launch path. | §Standard Stack (UIKit), §Build Order step 1, §Code Examples (AppDelegate+SceneDelegate) |
| ARCH-02 | iOS deployment target 17.0. Swift 5.9+. Xcode 16+ floor for CI. | §Standard Stack version table, §Version Verification section, §Discrepancy Flag #2 (Xcode version on dev machine vs CI floor) |
| ARCH-03 | Module layout matches TechStack.md §3.2 with research refinements: `App/`, `Core/{...}`, `Features/{...}`, `Roles/`, `UI/`, `Resources/`. | §Recommended Project Structure, §Build Order step 1, §Architectural Responsibility Map |
| ARCH-04 | `AppContainer` initializer DI. No Swinject, no Resolver, no singletons. | §Pattern 8 (AppContainer sketch), §Code Examples (AppContainer) |
| ARCH-05 | Cross-feature comms through `Core/` protocols only; SwiftLint custom rule enforces. | §Pattern 9 (no-cross-feature-import rule), §Code Examples (rule YAML) |
| ARCH-06 | `Roles/RoleCoordinator` swaps root at `SceneDelegate` level on active role change. | §Pattern 10 (SceneDelegate root swap), §Code Examples (SceneDelegate.presentRoot) |
| STACK-01 | `Package.swift` declares Nuke 13.0.2, no KeychainAccess, no Alamofire, no XCoordinator. Versions locked. | §Standard Stack (pinned versions), §Installation block |
| STACK-02 | SwiftLint + SwiftFormat with `.swiftlint.yml` + `.swiftformat` in repo root; pre-commit hook. | §Standard Stack (SwiftLint 0.63.2, SwiftFormat 0.61.0), §Code Examples (configs + hook) |
| STACK-03 | Swift Testing for new unit tests; XCTest for UI tests. | §Standard Stack (Swift Testing), §Code Examples (first Swift Testing file) |
| STACK-04 | Zero 3rd-party analytics or crash SDK in M1. Logging uses `os_log` + `OSLogStore`. | §Standard Stack (no crash vendor), §PrivacyInfo.xcprivacy "empty 3rd-party SDK list" (D-21) |
| LOG-01 | All logging through `Core/Logging/Logger`; no direct `print()` / `os_log()` in app code. SwiftLint enforces. | §Pattern 1 (PIIScrubber), §Pattern 9 (lint rules) |
| LOG-02 | Levels trace/debug/info/warn/error. Release → info; DEBUG → debug. | §Pattern 1 (Logger protocol sketch) |
| LOG-03 | `OSLogStore` retrieval from DevMenu in DEBUG builds. Release does not expose. | §Pattern 6 (DevMenu design — OSLogStore viewer tab) |
| SEC-02 | App Transport Security strict in `Info.plist`. No `NSAllowsArbitraryLoads`. | §Code Examples (Info.plist ATS block), §Validation Architecture row SEC-02 |
| SEC-03 | Keychain for all tokens. Secure Enclave for all keys. Zero sensitive data in `UserDefaults`. SwiftLint custom rule flags `UserDefaults` writes to `*token*`/`*key*`/`*session*`. | §Pattern 9 (lint rules), §Code Examples (rule YAML) |
| CI-01 | Unit tests cover PIIScrubber, APIClient+MockURLProtocol, SoftwareKeyStore, SessionLockService, idempotency interceptor. ≥70% coverage on `Core/`. | §Validation Architecture (Phase-Requirements-to-Test-Map), §D-02 scope |
| CI-02 | One smoke UI test per role (5 total): launch → OTP → role shell → logout. | §Scope clarification — CI-02 Phase 1 ships placeholder UI tests gated by Phase 3 OTP flow. Test targets exist in Phase 1. |
| CI-04 | `xcodebuild` + `xcrun xctest` CI invocation documented in `docs/ci.md`. | §Code Examples (docs/ci.md outline) |

</phase_requirements>

## Summary

Phase 1 rebuilds the Xcode SwiftUI template as a UIKit module layout matching TechStack.md §3.2 (with the 4 research/ARCHITECTURE.md amendments), lands 8 foundational conventions (PII scrubber, first-launch Keychain wipe, MVVM-C memory rules, CI sim/device split, cert-pinning skeleton, PrivacyInfo.xcprivacy, SessionLockService, bootstrap-aware DeepLinkRouter), and stands up the tooling/CI/logging baseline that every later phase depends on. Twenty-six REQ-IDs are in scope across FOUND/ARCH/STACK/LOG/SEC/CI. Twenty-one user decisions (D-01..D-21) are locked; this research informs HOW, not WHETHER. The infrastructure tax (30% of M1 per ROADMAP.md + PITFALLS.md P20) is real and must be budgeted by the planner.

The build order is fixed by research/ARCHITECTURE.md's 12-step table; Phase 1 implements **steps 1–9** (skeleton → UI tokens → Logging → Keychain → KeyStore protocol → Networking skeleton → Auth skeleton → AuthCoordinator stub → RoleCoordinator + 5 tab bars). Steps 10–12 span into Phases 2–5. Steps 5–7 ship as **protocol sketches + test-only implementations** in Phase 1 — the real `SecureEnclaveKeyManager`, real network traffic, and real OTP flow land in Phases 2–3. What Phase 1 proves at success-criterion level: the app builds clean on iOS 17, the SwiftLint custom rules catch what they should, the Keychain wipes on first install, PrivacyInfo.xcprivacy is in the IPA, CI runs both pipelines, and the DEBUG dev-menu successfully swaps between all 5 role tab bars end-to-end. [VERIFIED: research/ARCHITECTURE.md §Build Order, CONTEXT.md D-07..D-14]

**Primary recommendation:** Group Phase 1 work into 3 waves — Wave A "structural" (ARCH-01/02/03, STACK-01/02/03/04, docs skeletons), Wave B "conventions" (FOUND-01/02/03/07/08, ARCH-04/05/06, LOG-01/02/03, SEC-02/03, D-19 lint rules), Wave C "CI + privacy + dev menu" (FOUND-04/05/06, CI-01/02/04, D-11..D-14, D-20, D-21). Waves are dependency-ordered; B cannot start until A's module layout exists; C cannot start until B's conventions exist to test. [ASSUMED — planner to confirm wave grouping]

## Architectural Responsibility Map

Phase 1 capability-to-tier mapping. "Tier" here is the iOS-client architectural layer, not a multi-tier web application.

| Capability (Phase 1) | Primary Tier | Secondary Tier | Rationale |
|----------------------|--------------|----------------|-----------|
| App launch / bootstrap | `App/` composition root | — | AppDelegate + SceneDelegate own the lifecycle; AppContainer is composed here before anything else is resolved. [VERIFIED: research/ARCHITECTURE.md §Component Responsibilities] |
| First-launch Keychain wipe (D-20) | `App/AppDelegate` | `Core/Storage/Keychain` | Must run in AppDelegate BEFORE any service resolves from AppContainer; the implementation lives in Core/Storage but the invocation point is AppDelegate. [VERIFIED: CONTEXT.md D-20] |
| Role root swap (D-10) | `App/SceneDelegate` | `Roles/RoleCoordinator` | Per research/ARCHITECTURE.md amendment #3: window.rootViewController swap happens at SceneDelegate, never via TabBarCoordinator child mutation. [VERIFIED: research/ARCHITECTURE.md §Pattern 5] |
| PII scrubber + structured logging | `Core/Logging` | — | All logging paths funnel through Core/Logging; no direct os_log outside this module (enforced by SwiftLint rule D-19). [VERIFIED: CONTEXT.md D-16/D-17/D-19] |
| Hand-rolled Keychain wrapper | `Core/Storage/Keychain` | — | Per STACK.md decision: no KeychainAccess library (abandoned 2021). 150-line SecItem wrapper. [VERIFIED: research/STACK.md §Deltas vs TechStack.md §2.1] |
| Secure Enclave protocol + software fallback | `Core/KeyStore` | `App/AppContainer` | KeyStore module defines the protocol; AppContainer selects `SecureEnclaveKeyStore` (production/device) vs `SoftwareKeyStore` (simulator DEBUG) via `#if` branch. Phase 1 ships protocol + SoftwareKeyStore only; real SE impl is Phase 2. [VERIFIED: research/ARCHITECTURE.md §Security Architecture + Testing Security-Sensitive Modules] |
| SessionLockService stub | `Core/Auth` | — | Single source of truth for "require biometric re-prompt." Phase 1 ships the protocol + skeleton; actual biometric wiring lands Phase 3. [VERIFIED: research/PITFALLS.md P10] |
| DeepLinkRouter skeleton | `Core/Navigation` | `App/SceneDelegate` | Accepts links pre-bootstrap, queues them; SceneDelegate forwards `openURLContexts` and `continue` to it. Phase 1 is skeleton only (real deep-link targets land Phase 3). [VERIFIED: research/PITFALLS.md P18] |
| SwiftLint custom rules | Repo-root `.swiftlint.yml` | All source dirs | Not a runtime tier — a build-time enforcement tier. Rules live outside source. [VERIFIED: research/STACK.md §Installation] |
| PrivacyInfo.xcprivacy | `Resources/` (Copy Bundle Resources) | CI (grep check) | Must be in Copy Bundle Resources phase, not just project tree. CI verifies. [VERIFIED: research/PITFALLS.md P14 + CONTEXT.md D-21] |
| GitHub Actions simulator workflow | `.github/workflows/ci-simulator.yml` | — | Repo-root CI config; runs on GitHub-hosted `macos-latest`. [VERIFIED: CONTEXT.md D-01] |
| GitHub Actions device workflow | `.github/workflows/ci-device.yml` | Self-hosted runner on dev MacBook | `runs-on: [self-hosted, macOS, device]` label. [VERIFIED: CONTEXT.md D-04] |
| DevMenu | `App/DevMenu/` (DEBUG-only) | All Core modules | Composition-root concern, not a Feature. `#if DEBUG` compile-out. [VERIFIED: CONTEXT.md D-11..D-14] |
| 5 role TabBarController subclasses | `Roles/{Shipper,Broker,Carrier,Dispatch,Factoring}/` | — | Each one `UITabBarController` subclass per D-08/D-09. [VERIFIED: CONTEXT.md D-08/D-09] |

**Why this matters:** The planner can use this map as the task-to-directory assignment authority. Every Phase 1 task should declare the tier it belongs to; mis-assignments (e.g., putting the Keychain-wipe invocation in Core/Storage instead of App/AppDelegate) will break D-20's "before any auth service resolves" invariant.

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| Xcode | 26.4 locally; **floor Xcode 16.x in CI** | Build toolchain | Xcode 26.4 confirmed installed on dev MacBook (`xcodebuild -version` → "Xcode 26.4, Build 17E192"). Xcode 16+ is the floor because it bundles Swift Testing; Xcode 15 lacks it. [VERIFIED: `xcodebuild -version` + research/STACK.md] |
| Swift | 5.9 floor in `Package.swift`; Swift 6.3 compiler in toolchain | Language | Matches TechStack.md §2 "Swift 5.9+, Swift 6 concurrency adoption allowed in new code, not required retroactively." `swift --version` confirms 6.3 locally. New `Core/` modules can opt into Swift 6 mode per-file with `.enableUpcomingFeature("StrictConcurrency")`. [VERIFIED: local `swift --version`] |
| iOS SDK / deployment target | **iOS 17.0 minimum** | Platform | Spec-locked (ARCH-02). Enables VisionKit DataScannerViewController, Observable macro, modern URLSession async APIs. [VERIFIED: TechStack.md §2] |
| UIKit | iOS 17 SDK | Primary UI | Spec-locked. All Phase 1 launch-path code is UIKit. SwiftUI permitted only for Settings/static surfaces (not relevant to Phase 1 — Phase 1 has no user-visible screens). [VERIFIED: CLAUDE.md constraints + TechStack.md §2] |
| Swift Package Manager | bundled | Dep mgmt | Spec-locked. No CocoaPods / Carthage. [VERIFIED: CLAUDE.md] |
| URLSession | native | HTTP transport (skeleton only in Phase 1) | Phase 1 ships the `NetworkClient` protocol + `MockURLProtocol` scaffolding; real endpoints land Phase 2. [CITED: research/STACK.md] |
| os_log / OSLog / OSLogStore | native | Structured logging + PII scrubbing | Phase 1 builds `Core/Logging/` as the ONLY logging path. Direct `os_log` outside `Core/Logging/` banned by SwiftLint rule D-19. [VERIFIED: CONTEXT.md D-17/D-19] |
| CryptoKit `SecureEnclave.P256.Signing` | native | Device-bound keypair (protocol only in Phase 1) | Phase 1 ships KeyStoreProtocol + SoftwareKeyStore fallback. Real Secure Enclave impl is Phase 2 (DEV-01/02/03). [VERIFIED: research/ARCHITECTURE.md §Testing Security-Sensitive Modules] |

### Supporting (pinned SwiftPM)

| Library | Version | Purpose | Phase 1 Usage |
|---------|---------|---------|---------------|
| **Nuke** | `13.0.2` (2026-04-15) | Async image load + cache | Declared in `Package.swift` per STACK-01. Phase 1 has no image consumers yet — the dep exists to lock the version and validate the SwiftPM integration path. [CITED: research/STACK.md, GitHub releases API] |
| **Swift Testing** | bundled with Xcode 16+ | Unit tests (new) | Primary test framework for all Phase 1 `Core/*Tests` targets. `@Test`, `#expect`, parameterized tests. No package dependency needed when `swift-tools-version` is 6.0+ — Xcode bundles it. [VERIFIED: [Swift Testing docs](https://developer.apple.com/xcode/swift-testing/), web search 2026-04-20] |
| **XCTest + XCUITest** | bundled | UI tests | Retained for Phase 1 placeholder UI test target (CI-02) and for eventual 5-role smoke tests. STACK-03 splits Swift-Testing-for-unit vs XCTest-for-UI. [CITED: research/STACK.md] |
| **SwiftLint 0.63.2** via **SwiftLintPlugins** | `0.63.2` (2026-01-26) | Style + 4 custom rules (D-19) | SwiftPM build tool plugin. Fails build on violations in CI, warns locally. [VERIFIED: research/STACK.md, [SwiftLint 2026 custom_rules docs](https://realm.github.io/SwiftLint/custom_rules.html)] |
| **SwiftFormat** (nicklockwood) | `0.61.0` (2026-04-11) | Automated format pass | Pre-commit hook + Xcode Run Script phase. [CITED: research/STACK.md] |
| **swift-snapshot-testing** | `1.19.2` (2026-03-30) | Deferred to later phase | Not required in Phase 1 — no visual surfaces to snapshot. Recommend deferring dep declaration until Phase 2 UI first-light. [ASSUMED — planner may choose to pre-declare] |

### Alternatives Considered

| Instead of | Could Use | Why NOT in Phase 1 |
|------------|-----------|--------------------|
| Hand-rolled `KeychainStore` | `KeychainAccess` | **Abandoned library**. Last release v4.2.2 (2021-03-01); last commit 2023-11-12. No iOS 17 / Swift 6 validation. For a security-critical app, unmaintained crypto-storage is a liability. [VERIFIED: research/STACK.md, CONTEXT.md implicitly via D-15] |
| XCTest for unit tests | Swift Testing | Swift Testing chosen per STACK-03. XCTest retained for UI tests only. [VERIFIED: REQUIREMENTS.md STACK-03] |
| Separate SPM local packages per `Core/*` module | Single Xcode target + directory groups | Per D-15: no payoff on single-module M1; ARCH-05 enforced by SwiftLint rule not by SPM boundary. Revisit at M2 when network-layer extraction pays back. [VERIFIED: CONTEXT.md D-15] |
| `print()` for debug output | `os_log` via Core/Logging only | Banned by SwiftLint rule D-19. [VERIFIED: CONTEXT.md D-19] |
| Swinject / Resolver DI container | Initializer injection via `AppContainer` | Spec-locked (ARCH-04). Initializer DI for 15–20 Core services is trivially tractable. [VERIFIED: TechStack.md §3.3 + ARCH-04] |

### Version Verification

Run before locking versions in `Package.swift`:

```bash
# Nuke
curl -s https://api.github.com/repos/kean/Nuke/releases/latest | jq -r '.tag_name, .published_at'
# SwiftLintPlugins
curl -s https://api.github.com/repos/SimplyDanny/SwiftLintPlugins/releases/latest | jq -r '.tag_name, .published_at'
# SwiftFormat (nicklockwood)
curl -s https://api.github.com/repos/nicklockwood/SwiftFormat/releases/latest | jq -r '.tag_name, .published_at'
```

At research time (2026-04-20): Nuke `13.0.2` (2026-04-15), SwiftLintPlugins `0.63.2` (2026-01-26), SwiftFormat `0.61.0` (2026-04-11). Re-verify at plan execution time — versions may have advanced.

### Installation (Package.swift excerpt for Phase 1)

```swift
// swift-tools-version: 6.0
// Package.swift (checked into repo root alongside validationLedger.xcodeproj)
dependencies: [
    .package(url: "https://github.com/kean/Nuke.git",                       from: "13.0.2"),
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git",    from: "0.63.2"),
],
targets: [
    .target(
        name: "ValidationLedger",
        dependencies: [
            .product(name: "Nuke",   package: "Nuke"),
            .product(name: "NukeUI", package: "Nuke"),
        ],
        plugins: [
            .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
        ]
    ),
    .testTarget(
        name: "ValidationLedgerTests",
        dependencies: ["ValidationLedger"]
    ),
]
```

**Note on target structure vs D-15:** D-15 locks "single Xcode target with directory groups" — the `Package.swift` above is a *companion manifest* that pulls SwiftPM deps into the single app target. The `.xcodeproj` remains the source-of-truth for target structure; `Package.swift` just declares external deps. [ASSUMED — planner confirms: there are two viable paths, (a) declare deps in `Package.swift` AND link via Xcode's "Add Package Dependencies" UI, or (b) declare directly in Xcode without a Package.swift at all. Path (a) gives reproducibility + grep-ability; path (b) keeps everything in one file.]

## Architecture Patterns

### System Architecture Diagram (Phase 1 data flow)

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                         System Boot Path                              │
  │                                                                       │
  │  UIApplicationMain                                                    │
  │        │                                                              │
  │        ▼                                                              │
  │  AppDelegate.application(didFinishLaunchingWithOptions:)              │
  │        │                                                              │
  │        ├── (D-20) Keychain first-launch wipe                          │
  │        │    ├── reads UserDefaults "didCompleteFirstLaunch"           │
  │        │    └── if false: enumerate+delete all items → set flag       │
  │        │                                                              │
  │        └── returns true (no AppContainer yet — lazy-constructed)      │
  │                                                                       │
  │  SceneDelegate.scene(_:willConnectTo:options:)                        │
  │        │                                                              │
  │        ├── constructs AppContainer(env: .current)                     │
  │        │    ├── Logger instances (one per Core subsystem, D-17)       │
  │        │    ├── KeychainStore (hand-rolled SecItem wrapper)           │
  │        │    ├── KeyStoreProtocol resolves to SoftwareKeyStore         │
  │        │    │    (Phase 1 — real SE impl lands Phase 2)               │
  │        │    ├── SessionLockService (stub)                             │
  │        │    ├── NetworkClient (MockURLProtocol-backed, stub)          │
  │        │    └── DeepLinkRouter (accepts + queues, replays on ready)   │
  │        │                                                              │
  │        ├── presentRoot(.launch)  [Phase 1 → always .role(.shipper)    │
  │        │                          unless DevMenu changes it]          │
  │        │    │                                                         │
  │        │    └── window.rootViewController = AppCoordinator(…)         │
  │        │                                                              │
  │        └── DEBUG only: installs shake-gesture responder for DevMenu   │
  │                                                                       │
  │  User shakes device (DEBUG only)                                      │
  │        │                                                              │
  │        ▼                                                              │
  │  DevMenu presents modally with 3 sections:                            │
  │        ├── "Role Switcher" → sceneDelegate.presentRoot(.role(X))      │
  │        │                     (fresh AppContainer scope, D-10)         │
  │        ├── "Keychain Inspector" → lists items under access group      │
  │        └── "OSLog Viewer" → OSLogStore pull for last 15 min           │
  └─────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────┐
  │                         Log Emit Path                                 │
  │                                                                       │
  │  ViewModel / Service calls:                                           │
  │    logger.info(event: .keychainWiped, fields: [.count: 0])            │
  │        │                                                              │
  │        ▼                                                              │
  │  Core/Logging/Logger (protocol; OSLogLoggerImpl)                      │
  │        │                                                              │
  │        ├── PIIScrubber.scrub(fields)  ← applies per-field rules       │
  │        │    ├── .phone → E.164 mask (first 3 + last 2)                │
  │        │    ├── .name  → first-initial-only                           │
  │        │    ├── .dl    → redacted completely                          │
  │        │    ├── .email → local-part mask                              │
  │        │    ├── .mcDot → redacted completely                          │
  │        │    └── .coordinates → REMOVED (not masked)                   │
  │        │                                                              │
  │        ▼                                                              │
  │  OSLog.Logger(subsystem: "com.maldin.validationLedger.{module}",      │
  │               category: {...}).info("...")                            │
  │        │                                                              │
  │        └── OSLogStore captures for DevMenu viewer (DEBUG only)        │
  └─────────────────────────────────────────────────────────────────────┘
```

[VERIFIED: research/ARCHITECTURE.md System Overview + Data Flow sections]

### Recommended Project Structure (Phase 1 end state)

```
validationLedger/
├── Package.swift                          # SwiftPM dep declaration (Nuke, SwiftLintPlugins)
├── .swiftlint.yml                         # Base ruleset + 4 custom rules (D-19)
├── .swiftformat                           # SwiftFormat config
├── .gitignore                             # xcuserdata/, DerivedData/, .build/
├── validationLedger.xcodeproj/            # Existing; retarget to iOS 17.0
├── validationLedger/                      # Existing app source root
│   ├── App/
│   │   ├── AppDelegate.swift              # NEW — UIKit lifecycle + D-20 wipe
│   │   ├── SceneDelegate.swift            # NEW — UIKit scene lifecycle + D-10 root swap
│   │   ├── AppCoordinator.swift           # NEW — launch/auth/role routing
│   │   ├── AppContainer.swift             # NEW — initializer DI composition root
│   │   ├── Environment.swift              # NEW — dev/staging/prod config
│   │   ├── Info.plist                     # Updated — SEC-02 ATS strict, scene manifest
│   │   └── DevMenu/                       # NEW — #if DEBUG only
│   │       ├── DevMenuViewController.swift         # root screen
│   │       ├── DevMenuShakeResponder.swift         # UIResponder.motionEnded trigger
│   │       ├── RoleSwitcherViewController.swift    # D-11 role switch
│   │       ├── KeychainInspectorViewController.swift # D-11 Keychain viewer
│   │       └── LogViewerViewController.swift       # D-11 OSLogStore viewer
│   ├── Core/
│   │   ├── Logging/
│   │   │   ├── Logger.swift               # protocol (trace/debug/info/warn/error)
│   │   │   ├── OSLogLoggerImpl.swift      # OSLog-backed impl
│   │   │   ├── PIIScrubber.swift          # hybrid (D-16) — structured + string
│   │   │   ├── Subsystems.swift           # one per Core module (D-17)
│   │   │   └── LogExporter.swift          # OSLogStore pull for DevMenu
│   │   ├── Storage/
│   │   │   └── Keychain/
│   │   │       ├── KeychainStore.swift    # hand-rolled SecItem wrapper
│   │   │       ├── KeychainKey.swift      # typed keys (.sessionToken, .installUUID)
│   │   │       └── KeychainAccessibility.swift  # enum for kSecAttrAccessible*
│   │   ├── KeyStore/
│   │   │   ├── KeyStoreProtocol.swift     # ships in Phase 1
│   │   │   ├── SoftwareKeyStore.swift     # Phase 1 — simulator + DEBUG
│   │   │   └── SecureEnclaveKeyStore.swift # STUB in Phase 1; impl Phase 2
│   │   ├── Auth/
│   │   │   └── SessionLockService.swift   # Phase 1 STUB — protocol + timestamp
│   │   ├── Networking/
│   │   │   ├── NetworkClient.swift        # protocol — stub impl Phase 2
│   │   │   ├── MockURLProtocol.swift      # scaffolding only — fixtures Phase 2
│   │   │   └── CertificatePinning/
│   │   │       └── PinningSessionDelegate.swift # SKELETON only; impl Phase 2
│   │   ├── Navigation/
│   │   │   └── DeepLinkRouter.swift       # skeleton with pending queue (FOUND-08)
│   │   └── Analytics/                     # (empty directory — stub for M2)
│   ├── Features/                          # empty placeholder subdirs (ARCH-03)
│   │   ├── Onboarding/
│   │   ├── Loads/
│   │   ├── BOL/
│   │   ├── Scanner/
│   │   ├── Assistant/
│   │   ├── Profile/
│   │   └── Settings/
│   ├── Roles/
│   │   ├── Role.swift                     # enum (D-08)
│   │   ├── RoleCoordinator.swift          # protocol (D-08)
│   │   ├── Shipper/
│   │   │   └── ShipperTabBarController.swift   # tabs per D-09
│   │   ├── Broker/
│   │   │   └── BrokerTabBarController.swift
│   │   ├── Carrier/
│   │   │   └── CarrierTabBarController.swift
│   │   ├── Dispatch/
│   │   │   └── DispatchTabBarController.swift
│   │   └── Factoring/
│   │       └── FactoringTabBarController.swift
│   ├── UI/
│   │   └── DesignSystem/
│   │       ├── Colors.swift               # minimal — unblocks VC constants
│   │       ├── Spacing.swift
│   │       └── Typography.swift
│   └── Resources/
│       ├── Assets.xcassets                # existing; retained
│       ├── PrivacyInfo.xcprivacy          # NEW — D-21 (in Copy Bundle Resources)
│       └── Localizable.strings            # NEW — empty English file
├── validationLedgerTests/                 # NEW — Swift Testing target
│   ├── Logging/
│   │   └── PIIScrubberTests.swift         # FOUND-01 fixture tests
│   ├── Storage/
│   │   └── KeychainStoreTests.swift       # round-trip tests
│   ├── Networking/
│   │   └── MockURLProtocolTests.swift     # scaffolding test
│   └── Auth/
│       └── SessionLockServiceTests.swift  # stub logic tests
├── validationLedgerUITests/               # NEW — XCUITest target
│   └── RoleShellSmokeTests.swift          # placeholder (CI-02 real impl Phase 3)
├── .github/
│   └── workflows/
│       ├── ci-simulator.yml               # D-01/D-02
│       └── ci-device.yml                  # D-04/D-05/D-06
└── docs/
    ├── ci.md                              # CI-04
    ├── cert-rotation.md                   # FOUND-05 skeleton
    └── adr/
        ├── 0001-mvvm-c-memory-conventions.md      # FOUND-03
        ├── 0002-role-coordinator-swap-pattern.md  # ARCH-06
        └── 0003-module-layout-and-target-strategy.md # D-15
```

[VERIFIED: research/ARCHITECTURE.md §Recommended Project Structure, extended with Phase 1 scope annotations]

### Pattern 1: Hybrid PII Scrubber (structured preferred + string fallback) — FOUND-01, D-16

**What:** Primary API is structured: `logger.info(event:fields:)` where `fields: [Field: Any]` is an enum-keyed dict. Each `Field` case declares its redaction rule statically. Secondary `logger.info(_ message: String)` overload exists for ad-hoc strings; routes through `StringScrubber.scrub(_:)` regex pass before emit, so string-based calls cannot bypass redaction.

**When to use:** Every log call in the app. Direct `os_log(...)` is banned outside `Core/Logging/` by SwiftLint rule (D-19).

**Redaction rules per Success-Criterion-2 category:**

| Category | Structured Field | Redaction Rule | String Regex (fallback path) |
|----------|------------------|----------------|------------------------------|
| E.164 phone | `.phone` | Mask middle digits: `+14155550129` → `+1415•••0129` | `\+?[1-9]\d{1,14}` (then mask) |
| DL number | `.driversLicense` | Redact entirely → `[REDACTED:DL]` | State-specific patterns; fallback to `[A-Z]{1,2}[0-9]{5,8}` → `[REDACTED:DL]` |
| Full name | `.fullName` | First-initial-only: "Jane Doe" → "J. D." | Hard regex for names is infeasible; rely on structured API — string path only catches `name: "..."` key patterns and logs a WARN telemetry event "name_in_string_log" |
| MC/DOT number | `.mcNumber` / `.dotNumber` | Redact entirely → `[REDACTED:MC]` / `[REDACTED:DOT]` | `\b(MC|DOT)[- ]?\d{5,8}\b` (case-insensitive) → `[REDACTED:MC/DOT]` |
| Email | `.email` | Mask local part: `jane.doe@acme.com` → `j•••e@acme.com` | `[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}` (then mask local part) |
| Coordinates (lat/lng) | `.coordinates` | **REMOVED ENTIRELY** (not masked — raw coords never useful in logs) | `-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}` → `[REDACTED:GPS]` |

[VERIFIED: CONTEXT.md D-16 + ROADMAP.md Success Criterion 2 + research/PITFALLS.md P4]

**Why string-overload still routes through scrubber:** The SwiftLint custom rules can ban direct `os_log(...)` outside `Core/Logging/`, but they cannot force developers to use the structured API *inside* Core/Logging without another layer. The scrubber pass on the string overload is the second defense: even if someone slips `logger.info("tendering to +14155550129")`, the regex pass catches the phone number before emit. [ASSUMED — planner confirms that the regex pass also runs at DEBUG severity for observability]

**Key insight for tests (FOUND-01 verification):** The unit test fixture is a PROPERTY-BASED table. For each category, provide 3–5 known inputs and the expected scrubbed output. Test the structured path AND the string path with the same inputs — both must produce equivalent redaction. Mismatch = failing test = bug in the string regex.

### Pattern 2: First-launch Keychain wipe — FOUND-02, D-20, P1

**What:** In `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, **before** any service resolves from `AppContainer`:
1. Read `UserDefaults.standard.bool(forKey: "didCompleteFirstLaunch")`.
2. If `false`: enumerate Keychain items under the app's access group via `SecItemCopyMatching(kSecMatchLimitAll)`, delete each, log count deleted.
3. Set `didCompleteFirstLaunch = true`.

**Why `UserDefaults` as the gate:** `UserDefaults` IS cleared on uninstall (unlike Keychain). So `didCompleteFirstLaunch == false` is the reliable signal that "this is a fresh install." [VERIFIED: research/PITFALLS.md P2]

**Why enumerate-before-delete (not delete-by-known-key):** D-20 specifies enumerate-then-delete specifically so the DevMenu Keychain inspector (D-11) can show "before wipe" / "after wipe" on a test install. Also catches Keychain items from *prior app versions* that used different key names. [VERIFIED: CONTEXT.md D-20]

**When to use:** Every first install. Never on subsequent launches (gate prevents re-run).

**Why this MUST run in AppDelegate, not `AppContainer.init()`:** If it ran in AppContainer, any service that depended on Keychain (e.g., `SessionLockService` reading `lastBiometricSuccessTimestamp`) could read pre-wipe state. The AppDelegate hook runs *before* AppContainer is constructed. [VERIFIED: CONTEXT.md D-20 rationale]

**Swift sketch:**
```swift
// App/AppDelegate.swift
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        wipeKeychainOnFirstLaunch()
        return true
    }

    private func wipeKeychainOnFirstLaunch() {
        let flagKey = "didCompleteFirstLaunch"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flagKey) else { return }

        let classes: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity,
        ]
        for secClass in classes {
            let query: [CFString: Any] = [
                kSecClass: secClass,
                // No kSecMatchLimit here — delete ALL matches under the app's access group.
            ]
            SecItemDelete(query as CFDictionary)  // errSecSuccess or errSecItemNotFound both fine
        }
        defaults.set(true, forKey: flagKey)
        // Log count-before-count-after via Core/Logging — once Logger is resolved in SceneDelegate.
    }
}
```

### Pattern 3: MVVM-C memory conventions ADR — FOUND-03, P5

**What goes in ADR 0001:**
1. **Weak back-references:** ViewModels hold `weak var coordinator: CoordinatorProtocol?`; Coordinators hold children strongly, parent weakly.
2. **`[weak self]` in every `sink` closure.** Enforced by code review; SwiftLint rule is optional (regex for `.sink { ` lacking `[weak` is high false-positive).
3. **`assign(to:on:)` is BANNED.** Use an explicit `.sink { [weak self] in self?.property = $0 }` or a custom `assignWeak(to:on:)` extension.
4. **Every `Task` created in a ViewModel is stored as a handle and cancelled in `deinit`.**
5. **`@Published` writes from background threads are forbidden.** Network responses must `.receive(on: DispatchQueue.main)` OR the ViewModel must be `@MainActor`.
6. **`cancellables: Set<AnyCancellable>` is inspected in `deinit` during DEBUG** — `#if DEBUG assert(cancellables.isEmpty) #endif`.

[VERIFIED: research/PITFALLS.md P5 + research/ARCHITECTURE.md Pattern 1 (MVVM-C with Initializer DI)]

### Pattern 4: Sim/Device CI split — FOUND-04, D-01..D-06, P8

**Simulator workflow (`.github/workflows/ci-simulator.yml`):**

```yaml
name: CI (Simulator)
on:
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: macos-latest       # D-01
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
        # Floor Xcode 16.x per STACK.md; macos-latest image may expose Xcode 16.x / 26.x
      - name: Install iOS 17 simulator runtime (if missing)
        run: |
          xcodebuild -downloadPlatform iOS -buildVersion 17.5 || true
          # macos-latest images typically include iOS 17.x by default; fallback only
      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
          key: spm-${{ hashFiles('Package.resolved') }}
      - name: SwiftLint
        run: swift run swiftlint --strict
        # Fail-fast before tests (honors D-02 ordering)
      - name: Build + Test
        run: |
          xcodebuild test \
            -project validationLedger.xcodeproj \
            -scheme validationLedger \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
            -enableCodeCoverage YES \
            -only-testing:validationLedgerTests/Logging \
            -only-testing:validationLedgerTests/Storage \
            -only-testing:validationLedgerTests/Networking \
            -only-testing:validationLedgerTests/Auth
          # D-03: excludes Secure Enclave / biometric — achieved via -only-testing
          # rather than @available, since the test TARGETS are separate from
          # the app targets that contain the SE code.
```

**Device workflow (`.github/workflows/ci-device.yml`):**

```yaml
name: CI (Device)
on:
  push:
    branches: [main]              # D-05(a) merge to main
  pull_request:
    branches: [main]
    paths:                        # D-05(b) security-path PR gate
      - 'validationLedger/Core/Auth/**'
      - 'validationLedger/Core/KeyStore/**'
      - 'validationLedger/Core/Identity/**'
      - 'validationLedger/Core/Networking/CertificatePinning/**'
jobs:
  smoke:
    runs-on: [self-hosted, macOS, device]   # D-04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Build + Test on connected iPhone
        run: |
          xcodebuild test \
            -project validationLedger.xcodeproj \
            -scheme validationLedger \
            -destination 'platform=iOS,id=${{ secrets.DEVICE_UDID }}' \
            -only-testing:validationLedgerDeviceTests/SecureEnclaveSmokeTests
          # D-06: single smoke test — SecureEnclave.isAvailable + Keychain round-trip
```

**Device smoke test (Phase 1 minimum gate, D-06):**

```swift
// validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift
import Testing
import CryptoKit
@testable import ValidationLedger

@Suite("Device Smoke")
struct SecureEnclaveSmokeTests {
    @Test("Secure Enclave is available on device")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true)
    }

    @Test("Keychain round-trip on device")
    func keychainRoundTrip() throws {
        let store = KeychainStore()
        let key = KeychainKey(rawValue: "smoke-test-\(UUID().uuidString)")
        try store.set(Data("hello".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
        let out = try store.get(key)
        #expect(out == Data("hello".utf8))
        try store.delete(key)
    }
}
```

[VERIFIED: research/ARCHITECTURE.md §Testing Security-Sensitive Modules + CONTEXT.md D-01..D-06 + web search 2026-04-20]

**Known environment issue for planner:** The dev MacBook currently has iOS 15.2 / 18.0 / 18.1 / 18.2 / 18.4 / 26.2 / 26.4 simulator runtimes installed, but **no iOS 17 runtime**. The GitHub-hosted `macos-latest` image includes iOS 17 via pre-install, but local reproducibility requires `xcodebuild -downloadPlatform iOS -buildVersion 17.5` (or similar) on the dev machine. Planner should include a "runtime install" task in the dev-onboarding docs. [VERIFIED: local `xcrun simctl list devices available | grep iOS 17` returned empty]

### Pattern 5: PrivacyInfo.xcprivacy in Copy Bundle Resources — FOUND-06, D-21, P14

**What:** An XML plist that declares:
- `NSPrivacyAccessedAPITypes` — required-reason APIs the app uses
- `NSPrivacyCollectedDataTypes` — empty for Phase 1 (no data collection yet)
- `NSPrivacyTracking` — `<false/>`
- `NSPrivacyTrackingDomains` — empty array

**Phase 1 Phase-appropriate content:** Only `NSPrivacyAccessedAPITypeUserDefaults` with reason `CA92.1` (app functionality; used by `didCompleteFirstLaunch` flag, DevMenu preferences). Third-party SDK list: **empty** per STACK-04 + D-21. [VERIFIED: web search 2026-04-20, [Apple required-reason API docs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), CONTEXT.md D-21]

**Critical gotcha (P14):** The file must be added to the **Copy Bundle Resources** build phase in Xcode, not just present in the project tree. Otherwise it does NOT end up in the built `.ipa` and App Store validation rejects. The CI should run a grep-able check:

```bash
# docs/ci.md excerpt — post-build validation
BUILD_DIR=$(xcodebuild -showBuildSettings | awk '/ CONFIGURATION_BUILD_DIR / {print $3}')
APP_PATH="$BUILD_DIR/validationLedger.app"
if [ ! -f "$APP_PATH/PrivacyInfo.xcprivacy" ]; then
  echo "ERROR: PrivacyInfo.xcprivacy missing from .app bundle. Add to Copy Bundle Resources."
  exit 1
fi
```

**Sample content:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
</dict>
</plist>
```

### Pattern 6: SessionLockService stub (Phase 1) — FOUND-07, P10

**What Phase 1 ships:** The protocol + a no-op default implementation + in-memory `lastBiometricSuccessTimestamp` storage. Phase 3 wires the real biometric flow.

```swift
// Core/Auth/SessionLockService.swift
public protocol SessionLockService: AnyObject, Sendable {
    /// True if the app MUST show a biometric prompt before revealing content.
    /// Unified invariant: cold-boot-with-valid-token, OR background>5min-then-foreground, OR never-unlocked-this-session.
    func shouldRequireBiometric(now: Date) -> Bool

    /// Record a successful biometric. Called from Phase 3 biometric service.
    func recordBiometricSuccess(at: Date)

    /// Clear the stored timestamp (e.g., on logout).
    func invalidate()
}

// Phase 1 stub — returns true always (forces caller to handle the unlock path).
final class DefaultSessionLockService: SessionLockService {
    private var lastSuccess: Date?
    private let backgroundGrace: TimeInterval = 5 * 60
    func shouldRequireBiometric(now: Date) -> Bool {
        guard let last = lastSuccess else { return true }
        return now.timeIntervalSince(last) > backgroundGrace
    }
    func recordBiometricSuccess(at date: Date) { lastSuccess = date }
    func invalidate() { lastSuccess = nil }
}
```

**Why Phase 1 stub (not full impl):** FOUND-07 says "single source of truth" — that's the protocol. The real `LAContext` integration is Phase 3 (SESS-02). But the stub must be exercised by unit tests NOW so the contract is stable before Phase 3 wires it to biometrics. [VERIFIED: research/PITFALLS.md P10 + ROADMAP.md Phase 3 SESS-02]

### Pattern 7: Bootstrap-aware DeepLinkRouter — FOUND-08, P18

**What Phase 1 ships:** The router + pending queue + a `bootstrapComplete()` signal that drains the queue. Route targets (load detail, BOL, etc.) come from Features in later phases, so Phase 1's router accepts URLs but only has one no-op route handler.

```swift
// Core/Navigation/DeepLinkRouter.swift
public final class DeepLinkRouter {
    public enum State { case cold, ready }
    private var state: State = .cold
    private var queue: [URL] = []
    private let queueLock = NSLock()

    public func receive(_ url: URL) {
        queueLock.lock(); defer { queueLock.unlock() }
        if state == .cold {
            queue.append(url)
        } else {
            route(url)
        }
    }

    public func bootstrapComplete() {
        queueLock.lock()
        let pending = queue
        queue.removeAll()
        state = .ready
        queueLock.unlock()
        pending.forEach(route)
    }

    private func route(_ url: URL) {
        // Phase 1: log and no-op. Real handlers wire in Phase 3 (SHELL-*) + M3 (push + universal links).
    }
}
```

[VERIFIED: research/PITFALLS.md P18]

### Pattern 8: AppContainer initializer DI — ARCH-04

**Phase 1 surface:**

```swift
// App/AppContainer.swift
import Foundation

final class AppContainer {
    let logger: any Logger
    let keychainStore: KeychainStore
    let keyStore: any KeyStoreProtocol
    let sessionLock: any SessionLockService
    let networkClient: any NetworkClient
    let deepLinkRouter: DeepLinkRouter

    init(env: Environment) {
        // Loggers — one per Core subsystem per D-17
        self.logger = OSLogLoggerImpl(subsystem: "com.maldin.validationLedger.app", category: "bootstrap")
        self.keychainStore = KeychainStore(accessGroup: env.keychainAccessGroup)

        #if DEBUG && targetEnvironment(simulator)
        self.keyStore = SoftwareKeyStore()
        #else
        guard SecureEnclave.isAvailable else {
            fatalError("Production build on non-SE device")  // FR-iOS-DEV MUST
        }
        self.keyStore = SecureEnclaveKeyStore()
        #endif

        self.sessionLock = DefaultSessionLockService()
        self.networkClient = URLSessionNetworkClient(
            config: .mock,            // Phase 1 — Phase 2 swaps to .live(baseURL:)
            session: URLSession(configuration: .ephemeral)
        )
        self.deepLinkRouter = DeepLinkRouter()
    }
}
```

**Why "fresh AppContainer on role change" (D-10) is straightforward:** `SceneDelegate` holds exactly one reference to `AppContainer` (strong, in the coordinator field). On role change, it instantiates a NEW `AppContainer`, passes it to a NEW `AppCoordinator`, assigns the new root — the old `AppContainer` goes out of scope and ARC drops it (and every service inside it) deterministically. This is cheaper than it sounds: the services inside are tiny (loggers + stateless protocols + a stub keystore). In Phase 2+ when the container grows (real NetworkClient with caches, real KeyStore with key handles), the planner should audit the "is this service expensive to re-create" cost — but in Phase 1, all services are cheap. [VERIFIED: research/ARCHITECTURE.md Pattern 5 + CONTEXT.md D-10]

### Pattern 9: SwiftLint custom rules (4 rules ship in Phase 1) — D-19, ARCH-05, LOG-01, SEC-03

**`.swiftlint.yml` snippet:**

```yaml
# .swiftlint.yml — Phase 1 base config + custom rules (D-19)
included:
  - validationLedger

excluded:
  - validationLedgerTests
  - validationLedgerUITests
  - validationLedgerDeviceTests

opt_in_rules:
  - force_unwrapping
  - empty_count
  - closure_spacing
  - explicit_init
  # ... standard SwiftLint opt-in set

custom_rules:
  # Rule 1 — LOG-01: ban print() in application code
  ban_print:
    name: "Do not use print()"
    regex: '\b(Swift\.)?print\s*\('
    message: "Use Core/Logging/Logger instead of print()."
    severity: error

  # Rule 2 — LOG-01: ban direct os_log(...) outside Core/Logging/
  ban_direct_os_log:
    name: "Do not call os_log directly"
    regex: '\bos_log\s*\('
    message: "os_log is only allowed inside Core/Logging/. Use Logger instead."
    excluded: '.*/Core/Logging/.*'
    severity: error

  # Rule 3 — SEC-03: ban UserDefaults writes to sensitive keys
  ban_userdefaults_tokens:
    name: "Do not store tokens/keys/sessions in UserDefaults"
    regex: 'UserDefaults[^\n]*\.set\s*\([^,]+,\s*forKey:\s*"[^"]*(token|key|session)[^"]*"'
    message: "Tokens/keys/sessions must go in Keychain, not UserDefaults."
    severity: error

  # Rule 4 — ARCH-05: ban cross-feature imports
  no_cross_feature_import:
    name: "Features must not import other Features"
    regex: '^\s*import\s+Features_[A-Z]'
    message: "Cross-feature communication goes through Core/ protocols. Do not import other Features."
    included: '.*/Features/[^/]+/.*'
    severity: error
```

**Important caveat on rule 4:** As of D-15 (single target, no SPM packages per Feature), there are **no actual modules to import** between Features in Phase 1 — `import Features_Loads` is not a valid statement because Features don't compile as modules. The rule therefore triggers on **zero** Phase 1 violations. It is future-proofing for when Features become local SPM packages (M2+). [ASSUMED — planner may choose a different phrasing, e.g., a check on explicit path-based imports, or defer the rule until M2]

An alternative rule-4 implementation (more useful in Phase 1) bans **type references** from `Features/X` to `Features/Y` without going through a `Core/` protocol. But this requires AST analysis beyond SwiftLint's regex-based custom rules. Pragmatic recommendation: ship the import-based rule now (zero violations, no false positives), and add an AST-based `FeatureIsolation` SwiftLint source-plugin check in M2 when Features become modules. [ASSUMED — planner picks one of these two paths]

[VERIFIED: web search 2026-04-20 [SwiftLint custom_rules syntax](https://realm.github.io/SwiftLint/custom_rules.html) + research/STACK.md]

### Pattern 10: SceneDelegate root swap — ARCH-06, D-10

```swift
// App/SceneDelegate.swift
import UIKit

enum AppPhase {
    case launch
    case auth
    case role(Role)
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        presentRoot(.role(.shipper))   // Phase 1 default; DevMenu can switch
        window.makeKeyAndVisible()
    }

    func presentRoot(_ phase: AppPhase) {
        // Fresh container per D-10
        let container = AppContainer(env: .current)
        let coordinator = AppCoordinator(container: container, phase: phase)
        coordinator.onRoleResolved = { [weak self] role in
            self?.presentRoot(.role(role))
        }
        coordinator.onLogout = { [weak self] in
            self?.presentRoot(.launch)
        }
        self.appCoordinator = coordinator                  // retain new
        self.window?.rootViewController = coordinator.rootViewController
        // Previous coordinator tree is now orphaned; ARC deallocates on next runloop.
        // Abrupt replace per D-10 — no cross-dissolve animation.
    }

    // MARK: - Shake for DevMenu (D-12, DEBUG only)
    #if DEBUG
    override var canBecomeFirstResponder: Bool { true }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with _: UIEvent?) {
        guard motion == .motionShake else { return }
        appCoordinator?.presentDevMenu()
    }
    #endif
}
```

**Why this pattern over TabBar-child-mutation:** swapping children would leak old ViewModels, in-flight Tasks, cached URLSession delegates. Recreating the root guarantees deterministic deallocation. For a security-sensitive app, deterministic state reset on role change is non-negotiable. [VERIFIED: research/ARCHITECTURE.md Pattern 5 / Anti-Pattern 4]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image loading/caching | Custom `URLCache` with disk eviction | **Nuke 13.0.2** | Sendable, @globalActor ImagePipelineActor, Swift 6-clean. Phase 1 pre-wires the dep for later phases. [VERIFIED: research/STACK.md] |
| SwiftLint custom rule AST inspection | Home-grown Swift parser | **SwiftLint regex `custom_rules`** (Phase 1) → SwiftLint source-plugin (Phase 2+) | Regex is sufficient for print/os_log/UserDefaults bans. [CITED: [SwiftLint custom_rules docs](https://realm.github.io/SwiftLint/custom_rules.html)] |
| Coordinator navigation framework | Custom coordinator DSL | **Hand-rolled Coordinator protocol** | XCoordinator is abandoned (last commit 2023-02-28). The protocol is <50 LOC. [VERIFIED: research/STACK.md] |
| Keychain wrapper | Nothing (use `SecItem` directly all over the codebase) | **Hand-rolled `KeychainStore`** (150 LOC per STACK.md) | KeychainAccess is abandoned (2021). SecItem directly in every call site creates audit hell. Single wrapper = one place to audit. [VERIFIED: research/STACK.md] |
| DI container | Custom runtime DI registry | **Initializer injection via `AppContainer`** | Spec-locked (ARCH-04). Runtime DI hides graphs; initializer DI is explicit. [VERIFIED: TechStack.md §3.3] |
| Swift Testing setup | Pulling swift-testing as a package | **Xcode 16 bundle** | Swift Testing is bundled with Xcode 16+; no package dep needed when `swift-tools-version ≥ 6.0`. [VERIFIED: [Swift Testing docs](https://developer.apple.com/xcode/swift-testing/), web search 2026-04-20] |
| GitHub Actions iOS runner config | Dockerized Mac | **macos-latest** (simulator) + **self-hosted runner on dev MacBook** (device) | macos-latest includes Xcode 16.x + iOS 17.x by default. Self-hosted per D-04. [VERIFIED: web search 2026-04-20 + CONTEXT.md D-01/D-04] |

**Key insight:** Phase 1 is a Hand-Rolling Phase by design — Keychain, Coordinator, AppContainer, PIIScrubber, RoleCoordinator are all hand-rolled because the alternatives are either abandoned, overkill, or spec-locked-out. The tradeoff is explicit: ~600–900 LOC of infrastructure code in `Core/` that the team owns forever. This is the 30% infrastructure tax from PITFALLS.md P20, made concrete. [VERIFIED: research/PITFALLS.md P20 + ROADMAP.md Infrastructure Tax Budget]

## Runtime State Inventory

Phase 1 is a structural refactor of an Xcode SwiftUI scaffold. There is no prior runtime state to migrate, but there IS existing scaffold state to clean up.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | None — the app has never been installed on any device. No Keychain items, no Mem0 records, no databases. | None. |
| **Live service config** | None — no external services are wired up yet. No n8n workflows, no Datadog, no Tailscale, no Cloudflare. | None. |
| **OS-registered state** | None — no Task Scheduler tasks, pm2 processes, launchd plists, or systemd units reference this app. | None. |
| **Secrets and env vars** | None — no secret stores, no `.env` files, no SOPS keys. Xcode will introduce a development code-signing identity (Apple Developer account) when building on device, but that is not a "secret" the app code reads. | Planner should note: device CI will need a connected iPhone paired to the dev MacBook's Xcode trust store. No code-level secrets for Phase 1. |
| **Build artifacts / installed packages** | Current scaffold compiles into `DerivedData/validationLedger-*`. Deployment target currently set to **iOS 26.4** (see `.planning/codebase/STACK.md`) — must drop to **iOS 17.0** per ARCH-02. `.xcuserdata/` directories exist in `.xcodeproj` — these are per-developer and should be `.gitignore`d if not already. | Planner task: (a) retarget deployment to iOS 17.0 in `project.pbxproj`, (b) delete `DerivedData/` and re-build clean (Xcode command `Product → Clean Build Folder`), (c) verify `.gitignore` excludes `xcuserdata/` and `*.xcuserstate`. |

**Nothing else found:** Verified by reading `.planning/codebase/{STRUCTURE,ARCHITECTURE,STACK,CONVENTIONS}.md` — all confirm "brand-new Xcode SwiftUI template scaffold, no architectural layers present." [VERIFIED: codebase docs]

## Common Pitfalls

### Pitfall P1: Keychain items surviving app delete — FOUND-02 regression

**What goes wrong:** iOS Keychain is deliberately persistent across app uninstall. User A's tokens are readable by User B who reinstalls on the same device. Since the product's premise is trust, this single bug ends the product story.

**Why it happens:** Default Keychain behavior. Developers assume the OS cleans up.

**How to avoid:** Pattern 2 above (first-launch wipe). Enumerate-before-delete so the DevMenu inspector confirms visually.

**Warning signs:**
- No `didCompleteFirstLaunch` gate in `AppDelegate`.
- Keychain `set(...)` calls that don't specify the access group.
- Engineer has not tested "delete app → reinstall → launch → am I still logged in?" manually at least once.

[VERIFIED: research/PITFALLS.md P2]

### Pitfall P4: PII leakage through logs — FOUND-01 regression

**What goes wrong:** A single `logger.info("tendering load to \(user.phoneNumber)")` call slips into production. Analytics / crash-report aggregator captures the message. One screenshot in Slack ends the trust story.

**Why it happens:** Developers log liberally during M1 because errors are frequent. The scrubber either doesn't exist or has a bypass path.

**How to avoid:**
- Pattern 1 above (hybrid PIIScrubber with same scrubber on both structured and string paths).
- SwiftLint rule D-19 bans `print()` and direct `os_log(...)`.
- Code review flags any log that takes a non-typed argument.

**Warning signs:**
- `print(...)` or `os_log(...)` anywhere outside `Core/Logging/`.
- Test fixture for scrubber is shallow (< 3 examples per category).
- Scrubber doesn't cover all 6 Success-Criterion-2 categories.

[VERIFIED: research/PITFALLS.md P4]

### Pitfall P5: MVVM-C retain cycles

**What goes wrong:** ViewModels leak, memory climbs, app feels laggy after ~100 navigations. Beta testers report "it gets slow."

**Why it happens:** Combine ergonomics reward concise closures that implicitly capture `self`. `assign(to:on:)` has no weak variant.

**How to avoid:** ADR 0001 codifies the rules (Pattern 3 above). Weekly Instruments check during M1 at minimum.

**Warning signs:**
- Any `.assign(to: \..., on: self)` in the codebase.
- Any `.sink { ` closure without `[weak self]`.
- No `cancellables.isEmpty` assertion in any `deinit`.

[VERIFIED: research/PITFALLS.md P5]

### Pitfall P8: Simulator falsely green for Secure Enclave code

**What goes wrong:** CI runs on simulator. Security code paths are absent on simulator. CI passes, device is broken.

**How to avoid:**
- CI split D-01..D-06 (Pattern 4 above).
- `KeyStoreProtocol` + `SoftwareKeyStore` (simulator) + `SecureEnclaveKeyStore` (device only).
- AppContainer picks via `#if DEBUG && targetEnvironment(simulator)` branch; production build refuses launch if SE is unavailable.

[VERIFIED: research/PITFALLS.md P8]

### Pitfall P14: PrivacyInfo.xcprivacy not in Copy Bundle Resources

**What goes wrong:** File is in the project tree but NOT in the Copy Bundle Resources build phase. The built `.ipa` does not contain the manifest. App Store validation fails cryptically. Team scrambles.

**How to avoid:** Pattern 5 above + CI grep check on the built `.app` bundle.

**Warning signs:**
- File is in `Resources/` folder but Xcode's Target Membership checkbox is unchecked.
- No CI check that asserts `PrivacyInfo.xcprivacy` is in the built `.app`.

[VERIFIED: research/PITFALLS.md P14 + web search 2026-04-20 [Missing API Declaration Privacy](https://blog.ni18.in/itms-91053-missing-api-declaration-privacy/)]

### Pitfall P18: Deep-link race at cold launch

**What goes wrong:** Push notification fires `scene(_:openURLContexts:)` before `AppContainer` is constructed. Handler tries to route, crashes on `nil` service.

**How to avoid:** Pattern 7 above (bootstrap-aware queue). Phase 1 ships the router even though push notifications aren't in scope until M3. [VERIFIED: research/PITFALLS.md P18]

### Pitfall P20: 30% infrastructure tax missed

**What goes wrong:** M1 estimate is feature-focused. The 30% infrastructure tax (logging, CI, lint, ADRs, PII scrubber, Keychain wipe, PrivacyInfo.xcprivacy) is under-budgeted. Week 2 of M1 is quietly behind. Week 4 is a scramble.

**How to avoid:**
- ROADMAP.md already budgets 30% explicitly.
- Planner should size Phase 1 tasks with this in mind; a "simple" task like "set up SwiftLint" is actually "SwiftLint base config + 4 custom rules + pre-commit hook + CI wiring + first-fail validation on a planted violation" which is ~1.5 dev-days, not 2 hours.

**Warning signs:**
- Any Phase 1 wave estimated at <1 day of work.
- No "setup the tooling" tasks in the plan.
- No explicit task for "verify the SwiftLint custom rule actually fires on a planted `print()` call."

[VERIFIED: research/PITFALLS.md P20 + ROADMAP.md Infrastructure Tax Budget]

## Code Examples

### Example 1: Logger protocol + structured emit (FOUND-01, D-16, D-17)

```swift
// Core/Logging/Logger.swift
import OSLog

public enum LogLevel: Int, Sendable { case trace, debug, info, warn, error }

public enum LogField: Hashable, Sendable {
    case phone           // E.164 → masked
    case fullName        // "Jane Doe" → "J. D."
    case driversLicense  // → [REDACTED:DL]
    case mcNumber        // → [REDACTED:MC]
    case dotNumber       // → [REDACTED:DOT]
    case email           // local part masked
    case coordinates     // REMOVED entirely
    case count           // safe — integer
    case duration        // safe — TimeInterval
    case event           // safe — string event name
    // ... extend as needed; safe fields pass through unscrubbed
}

public struct LogEvent: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public static let keychainWiped = LogEvent("keychain_wiped")
    public static let firstLaunchDetected = LogEvent("first_launch_detected")
    // ... extend as features land
}

public protocol Logger: AnyObject, Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any])
    func log(_ level: LogLevel, _ message: String)   // string fallback — scrubbed
}

extension Logger {
    public func info(event: LogEvent, fields: [LogField: Any] = [:]) {
        log(.info, event: event, fields: fields)
    }
    public func info(_ message: String) { log(.info, message) }
    public func error(event: LogEvent, fields: [LogField: Any] = [:]) {
        log(.error, event: event, fields: fields)
    }
    // ... .trace .debug .warn
}

// Core/Logging/OSLogLoggerImpl.swift
final class OSLogLoggerImpl: Logger {
    private let osLog: os.Logger
    private let scrubber: PIIScrubber

    init(subsystem: String, category: String, scrubber: PIIScrubber = .default) {
        self.osLog = os.Logger(subsystem: subsystem, category: category)
        self.scrubber = scrubber
    }

    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {
        let scrubbed = scrubber.scrub(fields)
        let fieldsString = scrubbed.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        osLog.log(level: level.osLogType, "\(event.name, privacy: .public) \(fieldsString, privacy: .public)")
    }

    func log(_ level: LogLevel, _ message: String) {
        let scrubbed = scrubber.scrubString(message)
        osLog.log(level: level.osLogType, "\(scrubbed, privacy: .public)")
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        }
    }
}
```

[CITED: research/ARCHITECTURE.md Component Responsibilities + CONTEXT.md D-16]

### Example 2: PIIScrubber fixture test (Swift Testing, FOUND-01)

```swift
// validationLedgerTests/Logging/PIIScrubberTests.swift
import Testing
@testable import ValidationLedger

@Suite("PIIScrubber — 6 category redaction contract")
struct PIIScrubberTests {
    let scrubber = PIIScrubber.default

    @Test("E.164 phone masked to first-3-last-2")
    func phoneMasked() {
        let out = scrubber.scrub([.phone: "+14155550129"])
        #expect(out[.phone] as? String == "+1415•••0129")
    }

    @Test("DL number fully redacted")
    func dlRedacted() {
        let out = scrubber.scrub([.driversLicense: "CA1234567"])
        #expect(out[.driversLicense] as? String == "[REDACTED:DL]")
    }

    @Test("Full name → initial-only")
    func fullNameMasked() {
        let out = scrubber.scrub([.fullName: "Jane Doe"])
        #expect(out[.fullName] as? String == "J. D.")
    }

    @Test("MC/DOT numbers fully redacted", arguments: [
        (LogField.mcNumber, "MC-123456", "[REDACTED:MC]"),
        (LogField.dotNumber, "DOT1234567", "[REDACTED:DOT]"),
    ])
    func mcDotRedacted(field: LogField, input: String, expected: String) {
        let out = scrubber.scrub([field: input])
        #expect(out[field] as? String == expected)
    }

    @Test("Email local-part masked")
    func emailMasked() {
        let out = scrubber.scrub([.email: "jane.doe@acme.com"])
        #expect(out[.email] as? String == "j•••e@acme.com")
    }

    @Test("Coordinates REMOVED entirely")
    func coordinatesRemoved() {
        let out = scrubber.scrub([.coordinates: "37.7749,-122.4194"])
        #expect(out[.coordinates] == nil, "coordinates must be removed, not masked")
    }

    @Test("String-path fallback catches inline PII")
    func stringPathCatchesPhone() {
        let out = scrubber.scrubString("User phone +14155550129 attempted OTP")
        #expect(!out.contains("+14155550129"))
        #expect(out.contains("+1415•••0129") || out.contains("[REDACTED:PHONE]"))
    }
}
```

[VERIFIED: [Swift Testing docs — @Test, #expect, parameterized tests](https://developer.apple.com/documentation/testing)]

### Example 3: Info.plist ATS-strict block (SEC-02)

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSAllowsArbitraryLoadsForMedia</key>
    <false/>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <false/>
    <key>NSAllowsLocalNetworking</key>
    <false/>
    <!-- No NSExceptionDomains — SEC-02 requires zero exceptions -->
</dict>
```

[VERIFIED: REQUIREMENTS.md SEC-02]

### Example 4: `docs/ci.md` skeleton (CI-04)

```markdown
# CI Pipelines

## Overview

Two pipelines run:
- **Simulator** (every PR) — `.github/workflows/ci-simulator.yml`
- **Device** (every merge to main + security-path PR) — `.github/workflows/ci-device.yml`

## Simulator Pipeline

**Trigger:** `pull_request` on `main`
**Runner:** `macos-latest` (GitHub-hosted)
**Xcode:** floor 16.4 (bundled iOS 17 SDK + Swift Testing)
**Steps:**
1. Checkout
2. Select Xcode 16.4
3. Install iOS 17 runtime (fallback — image usually has it)
4. Restore SwiftPM cache
5. SwiftLint `--strict` (fail-fast before tests)
6. `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -enableCodeCoverage YES -only-testing:...`
7. PrivacyInfo.xcprivacy presence check (grep-able script per D-21)

**Excluded:** Secure Enclave + biometric + App Attest tests (D-03 — require real hardware).
**Coverage target:** ≥70% on `Core/` (CI-01).

## Device Pipeline

**Trigger:** `push` to main OR `pull_request` touching security paths (D-05)
**Runner:** self-hosted MacBook with connected iPhone (D-04)
**Runner labels:** `[self-hosted, macOS, device]`
**Xcode:** 26.4 (dev machine)
**Steps:**
1. Checkout
2. `xcodebuild test -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests`
3. The single smoke test (D-06):
   - `#expect(SecureEnclave.isAvailable == true)`
   - Keychain write → read → delete round-trip on a test key

## Known Trade-off

Self-hosted runner occupies the dev MacBook for ~5–15 min per run. Re-evaluate at M2 boundary (see `.planning/STATE.md` Blockers/Concerns).

## docs/cert-rotation.md

Skeleton only in Phase 1. Full runbook is a Phase 2 deliverable (FOUND-05 content depends on Phase 2's cert pinning implementation).
```

[CITED: CONTEXT.md D-01..D-06]

### Example 5: `Package.swift` pre-commit hook (STACK-02)

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit — run via 'bash scripts/install-hooks.sh' during onboarding
set -euo pipefail

STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$' || true)
[ -z "$STAGED" ] && exit 0

echo "→ SwiftFormat (lint only)"
swiftformat --lint --config .swiftformat $STAGED

echo "→ SwiftLint (strict)"
swift run swiftlint --strict --path $(echo $STAGED | tr ' ' '\n' | head -20)

echo "✓ Pre-commit checks passed"
```

[CITED: research/STACK.md pre-commit hook pattern]

### Example 6: `docs/adr/0001-mvvm-c-memory-conventions.md` skeleton (FOUND-03)

```markdown
# ADR 0001: MVVM-C Memory Conventions

**Status:** Accepted
**Date:** 2026-04-2X
**Supersedes:** None

## Context

MVVM + Coordinators + Combine have four canonical leak patterns (research/PITFALLS.md P5).
Undetected retain cycles compound through M2–M3 and force a feature freeze to fix.

## Decision

The following rules are enforced at code review for every ViewModel + Coordinator pair:

1. **Weak back-references:** `ViewModel` holds `weak var coordinator: CoordinatorProtocol?`.
   Coordinators hold children strongly, parent weakly.
2. **`[weak self]` in every `sink` closure** followed by `guard let self else { return }`.
3. **`assign(to:on:)` is BANNED.** Use explicit `.sink { [weak self] in self?.property = $0 }`
   or a custom `assignWeak(to:on:)` extension.
4. **Every `Task` created in a ViewModel is stored and cancelled in `deinit`.**
5. **`@Published` writes from background threads are forbidden.** Use `@MainActor` on VMs
   OR `.receive(on: DispatchQueue.main)` before assignment.
6. **DEBUG `assert(cancellables.isEmpty)` in VM `deinit`** — makes leaks visible in console.

## Consequences

- Code review cost: +5 min per VM PR; pays back in weeks of non-leak-hunting.
- No runtime performance impact.
- SwiftLint regex for `.assign(to:` can be added later; sink-without-weak is high false-positive.

## Related

- PITFALLS.md P5
- ARCHITECTURE.md Pattern 1 (MVVM-C with Initializer DI)
```

[VERIFIED: research/PITFALLS.md P5 + CONTEXT.md D-18]

## State of the Art

| Old Approach | Current Approach | When Changed | Phase-1 Impact |
|--------------|------------------|--------------|----------------|
| KeychainAccess library | Hand-rolled SecItem wrapper | 2023 (library abandoned) | Phase 1 implements the hand-rolled wrapper |
| XCTest for unit tests | Swift Testing for new unit tests | Xcode 16 (2024-09) | Phase 1 uses Swift Testing — XCTest only for UI tests |
| XCoordinator library | Hand-rolled Coordinator protocol | 2023 (abandoned) | Phase 1 ships hand-rolled coordinator |
| SDWebImage for images | Nuke 13.x (Swift 6/Sendable-clean) | Nuke 13 release 2024 | Phase 1 pre-declares Nuke even though no consumers yet |
| `ObservableObject + @Published` (Combine) | `@Observable` macro | WWDC23 / iOS 17 | Phase 1 sticks with Combine for UIKit VMs; M4 migration gate per research/ARCHITECTURE.md |
| CocoaPods / Carthage | Swift Package Manager only | Spec-locked | Phase 1 declares SwiftPM deps |
| Xcode 15 | Xcode 16+ floor in CI, 26.x locally | Swift Testing requires Xcode 16 | Phase 1 CI workflows select Xcode 16.4 explicitly |
| iOS 17 `CLLocationUpdate.liveUpdates` mixed with `CLServiceSession` | Pick one path; classic delegate API for background in Phase 3+ | iOS 18 introduced `CLServiceSession` | Phase 1 has no location code — flag for Phase 3 |

**Deprecated/outdated for Phase 1:**
- TechStack.md §2 "Xcode 15+" — deprecated. CI floor is Xcode 16.x; dev is Xcode 26.4.
- TechStack.md §2.1 "KeychainAccess or hand-rolled" — hand-rolled only; KeychainAccess abandoned.
- TechStack.md §2.1 "Crash/analytics: pick one in M1" — deferred to M2 per PROJECT.md. M1 uses OSLog.

[VERIFIED: research/STACK.md Deltas vs TechStack.md §2.1]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Planner can group Phase 1 into 3 waves A/B/C as recommended | §Summary | Low — planner can regroup. The underlying dependency chain (structural → conventions → CI/privacy/dev menu) is VERIFIED from research/ARCHITECTURE.md build order. |
| A2 | String-overload regex pass in PIIScrubber runs at DEBUG severity for observability | Pattern 1 | Low — any severity works; confirmation is a tuning detail. |
| A3 | SwiftLint custom rule 4 (no-cross-feature-import) ships as an `import`-based regex check and is future-proofing (zero Phase 1 violations) | Pattern 9 | Medium — if the planner wants AST-based detection, that requires a SwiftLint source-plugin and more work. Alternative phrased in the section. |
| A4 | Phase 1 ships MockURLProtocol as scaffolding only (no fixtures); fixtures are Phase 2 | Phase Requirements table (NET-* is Phase 2), D-02 | Low — CONTEXT.md D-02 explicitly says "MockURLProtocol (scaffolding + fixtures)" which is slightly ambiguous. Researcher reads this as "scaffolding, fixtures TBD per phase." If the planner reads it as "ship some fixtures in Phase 1," that adds ~0.5 dev-days for a trivial happy-path fixture. Flag for Discuss if important. |
| A5 | `Package.swift` at repo root alongside `.xcodeproj` is the preferred pattern (path (a) over path (b)) | §Installation | Low — both paths work; (a) is more reproducible and grep-able, (b) is less config. |
| A6 | `swift-snapshot-testing` dep declaration is deferred to Phase 2 | §Standard Stack | Low — no Phase 1 visual surfaces to snapshot. If planner wants to pre-declare for Phase 3 first-light, that's fine. |
| A7 | The dev MacBook has Xcode 26.4 but missing iOS 17 runtime — planner must include a runtime-install task in dev onboarding docs | §Pattern 4 "Known environment issue" | Medium — skipping the install task means first CI-parity attempt fails locally with cryptic destination errors. VERIFIED via `xcrun simctl list` output. |
| A8 | SECureEnclaveKeyStore.swift ships as a stub `fatalError("Phase 2")` file, not an empty file | §Recommended Project Structure | Low — the file needs to exist for `AppContainer`'s `#if` branch to compile; stubbing is the standard pattern. |
| A9 | Device CI runner needs the connected iPhone's UDID as a GitHub Actions secret (`DEVICE_UDID`) | §Pattern 4 device workflow | Low — standard self-hosted runner pattern. Confirmed by web search. |
| A10 | CI-02 ("one smoke UI test per role, 5 total") ships as Phase 1 placeholder UI tests that verify the 5 TabBarControllers instantiate; the OTP→shell path lands in Phase 3. | §Phase Requirements table | Medium — if the planner interprets CI-02 literally as "must include OTP→shell", that's a Phase 3 dependency and fails Phase 1 gate. ROADMAP.md traceability assigns CI-02 to Phase 1 but the "login → OTP → role shell renders → logout" path requires Phase 3 code. **This is Discrepancy Flag #3 below** — planner must decide whether to ship placeholder tests (recommended) or defer CI-02 to Phase 3. |

**If the planner finds any of these assumptions incorrect, re-run discuss-phase to lock the alternative before executing.**

## Open Questions

1. **CI-02 scope in Phase 1** (see Assumption A10). ROADMAP.md traceability assigns CI-02 to Phase 1, but the test behavior described ("launch → OTP enter → role shell renders → logout") requires Phase 3 code. **What we know:** the 5 `UITabBarController` subclasses exist in Phase 1 per D-07/D-08/D-09. **What's unclear:** does CI-02 Phase-1 scope mean "placeholder test target + 5 `#expect` assertions that each TabBarController instantiates" or "deferred to Phase 3"? **Recommendation:** Phase 1 ships placeholder XCUITest target with 5 trivial tests (each launches the app with a DevMenu-preset role and asserts the tab bar has N tabs with expected titles). Full OTP-to-logout smoke is Phase 3. **Planner route:** confirm with user during plan-check, OR file as Phase 3 CONTEXT input.

2. **SwiftLint rule 4 (no-cross-feature-import) enforcement mechanism** (see Assumption A3). Import-based regex is trivial but has zero Phase 1 violations. AST-based plugin is higher fidelity but harder to build. **Recommendation:** ship the import-based regex now, file the AST plugin as a "when Features become modules" M2 task.

3. **MockURLProtocol Phase-1 depth** (see Assumption A4). D-02 says "MockURLProtocol (scaffolding + fixtures)" — does Phase 1 ship any fixtures? **Recommendation:** ship the `MockURLProtocol` class + 1 trivial happy-path fixture (e.g., `"hello"` response for `GET /ping`) so the test target compiles; Phase 2 adds the real M1-endpoint fixtures.

4. **`Package.swift` vs Xcode-UI dep declaration** (Assumption A5). Which path does the planner choose? Either works; (a) is better for reproducibility, (b) is fewer files. **Recommendation:** (a).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | All Phase 1 builds | ✓ | 26.4 (locally) | — |
| Swift toolchain | All Phase 1 builds | ✓ | 6.3 | — |
| iOS 17 simulator runtime | ARCH-02, simulator CI | ✗ locally; ✓ in `macos-latest` CI image | — locally | `xcodebuild -downloadPlatform iOS -buildVersion 17.x` on dev machine |
| Connected iPhone (for device CI) | D-04/D-06 | (unverified) | — | Planner must confirm dev has a physical iPhone paired to Xcode trust store; without this, device CI cannot run |
| GitHub Actions runner (`macos-latest`) | D-01 | ✓ (hosted) | Xcode 16.x + iOS 17.x pre-installed | — |
| SwiftPM network access (for Nuke + SwiftLintPlugins) | STACK-01/02 | ✓ (standard internet) | — | — |
| `xcodebuild` CLI | CI-04 | ✓ | 26.4 | — |
| `git` | All phases | ✓ | system | — |

**Missing dependencies with no fallback:**
- **None for Phase 1 structural work.** The iOS 17 simulator runtime is "missing-with-fallback" and easily installed via `xcodebuild -downloadPlatform`.

**Missing dependencies to verify before plan execution:**
- Physical iPhone for device CI (D-04/D-06). Planner should have the user confirm availability in plan-check; if no device, device CI tasks must be marked as "pending hardware."

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (Xcode 16+ bundled) for unit tests; XCTest + XCUITest for UI tests |
| Config file | None — Swift Testing does not require a config. `Package.swift` `swift-tools-version: 6.0` is sufficient. |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests/Logging/PIIScrubberTests` |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -enableCodeCoverage YES` |
| Device smoke command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests` |

### Phase Requirements → Test Map

| REQ | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| FOUND-01 | PIIScrubber redacts 6 categories | unit | `xcodebuild test -only-testing:validationLedgerTests/Logging/PIIScrubberTests` | ❌ Wave 0 — `validationLedgerTests/Logging/PIIScrubberTests.swift` |
| FOUND-02 | First-launch Keychain wipe deletes pre-existing items | integration (simulator) | `xcodebuild test -only-testing:validationLedgerTests/Storage/KeychainWipeTests` + manual verify on device (DevMenu shows 0 items post-wipe) | ❌ Wave 0 — `validationLedgerTests/Storage/KeychainWipeTests.swift` + manual |
| FOUND-03 | MVVM-C memory rules codified in ADR | manual/review | grep for file exists: `test -f docs/adr/0001-mvvm-c-memory-conventions.md` | ❌ Wave 0 — `docs/adr/0001-mvvm-c-memory-conventions.md` |
| FOUND-04 | Both CI pipelines exist and run on defined triggers | CI script | `gh workflow view ci-simulator.yml` + `gh workflow view ci-device.yml`; planted-violation fails the pipeline on PR | ❌ Wave 0 — `.github/workflows/*.yml` |
| FOUND-05 | `docs/cert-rotation.md` skeleton exists (full runbook Phase 2) | manual/review | `test -f docs/cert-rotation.md` | ❌ Wave 0 |
| FOUND-06 | `PrivacyInfo.xcprivacy` in `.app` bundle (Copy Bundle Resources) | CI script | Grep-able post-build check: `test -f $BUILT_PRODUCTS_DIR/validationLedger.app/PrivacyInfo.xcprivacy` | ❌ Wave 0 — `Resources/PrivacyInfo.xcprivacy` + CI step |
| FOUND-07 | SessionLockService protocol + stub + shouldRequireBiometric logic | unit | `xcodebuild test -only-testing:validationLedgerTests/Auth/SessionLockServiceTests` | ❌ Wave 0 — `validationLedgerTests/Auth/SessionLockServiceTests.swift` |
| FOUND-08 | DeepLinkRouter queues pre-bootstrap, drains on ready | unit | `xcodebuild test -only-testing:validationLedgerTests/Navigation/DeepLinkRouterTests` | ❌ Wave 0 — `validationLedgerTests/Navigation/DeepLinkRouterTests.swift` |
| ARCH-01 | UIKit launch path, no SwiftUI in App/ | manual/review + build | `grep -r "import SwiftUI" validationLedger/App/` returns empty; `xcodebuild build` succeeds | No test needed — verified by grep + build |
| ARCH-02 | iOS deployment target 17.0 | manual/review | `grep IPHONEOS_DEPLOYMENT_TARGET validationLedger.xcodeproj/project.pbxproj` shows `17.0` | No test needed |
| ARCH-03 | Module layout matches §3.2 + research refinements | manual/review | File tree matches §Recommended Project Structure above | No test needed |
| ARCH-04 | AppContainer initializer DI, no singletons | unit + review | No `.shared` references outside `OSLog.Logger`; AppContainer init takes `Environment` | Partially testable via grep |
| ARCH-05 | Features do not import each other | SwiftLint | `swift run swiftlint lint --strict` (rule `no_cross_feature_import`) | ❌ Wave 0 — `.swiftlint.yml` |
| ARCH-06 | RoleCoordinator root swap at SceneDelegate | integration (DevMenu manual) | DevMenu role switch succeeds → window.rootViewController is new instance → old coordinator deallocates (verify via log message in deinit) | Manual + unit test on RoleCoordinator protocol contract |
| STACK-01 | `Package.swift` declares only allowed deps | manual/review | `cat Package.swift` matches §Installation | No test needed |
| STACK-02 | SwiftLint + SwiftFormat configured + pre-commit hook | CI + manual | `swift run swiftlint --version` works; `swiftformat --version` works; `.git/hooks/pre-commit` exists | No test needed |
| STACK-03 | Swift Testing for unit tests; XCTest for UI tests | manual/review | `grep "import Testing" validationLedgerTests` returns hits; `grep "import XCTest" validationLedgerUITests` returns hits | No test needed |
| STACK-04 | Zero crash/analytics SDK | manual/review | `grep -E "(Sentry\|Crashlytics\|Firebase\|Amplitude\|Mixpanel)" Package.swift` returns empty | No test needed |
| LOG-01 | No direct `print()` or `os_log()` outside `Core/Logging/` | SwiftLint | `swift run swiftlint --strict` with rules `ban_print` + `ban_direct_os_log` | ❌ Wave 0 — SwiftLint rules |
| LOG-02 | Logger supports 5 levels with correct defaults | unit | `xcodebuild test -only-testing:validationLedgerTests/Logging/LoggerLevelsTests` | ❌ Wave 0 |
| LOG-03 | DevMenu exposes OSLogStore viewer in DEBUG; NOT in Release | manual/review + build | DEBUG build: shake device → see log viewer. Release build: `strings validationLedger.app/validationLedger | grep -i "logviewer"` returns empty | Manual |
| SEC-02 | ATS strict in Info.plist, no exceptions | manual/review | `grep NSAllowsArbitraryLoads validationLedger/App/Info.plist` shows `<false/>`; no `NSExceptionDomains` | No test needed |
| SEC-03 | SwiftLint flags UserDefaults writes of sensitive keys | SwiftLint | Plant `UserDefaults.standard.set("abc", forKey: "sessionToken")` → lint fails | ❌ Wave 0 — SwiftLint rule `ban_userdefaults_tokens` |
| CI-01 | ≥70% coverage on `Core/` | CI script | `xcodebuild test -enableCodeCoverage YES` + coverage parse step | ❌ Wave 0 — coverage script |
| CI-02 | 5 placeholder UI tests (one per role) exist and pass | CI script | `xcodebuild test -only-testing:validationLedgerUITests` (5 placeholder tests verifying each TabBarController renders) | ❌ Wave 0 — `validationLedgerUITests/RoleShellSmokeTests.swift` — **see Assumption A10 / Open Question #1** |
| CI-04 | `docs/ci.md` documents both pipelines | manual/review | `test -f docs/ci.md && grep -q "Simulator Pipeline" docs/ci.md && grep -q "Device Pipeline" docs/ci.md` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `swift run swiftlint --strict` + quickest relevant unit test (e.g., `-only-testing:validationLedgerTests/Logging/PIIScrubberTests` for PIIScrubber edits). Target < 60s.
- **Per wave merge:** Full simulator suite: `xcodebuild test -enableCodeCoverage YES` + coverage check. Target < 10 min.
- **Phase gate:** Full suite green + SwiftLint strict + device CI smoke (D-06) green + PrivacyInfo.xcprivacy grep check + DevMenu manual pass of 5-role swap.

### Wave 0 Gaps

- [ ] `validationLedgerTests/` target (Swift Testing) — does not exist; create as Wave 0 (covers FOUND-01/02/07/08, LOG-02, CI-01 scaffolding)
- [ ] `validationLedgerTests/Logging/PIIScrubberTests.swift` — covers FOUND-01
- [ ] `validationLedgerTests/Storage/KeychainWipeTests.swift` — covers FOUND-02
- [ ] `validationLedgerTests/Auth/SessionLockServiceTests.swift` — covers FOUND-07
- [ ] `validationLedgerTests/Navigation/DeepLinkRouterTests.swift` — covers FOUND-08
- [ ] `validationLedgerTests/Logging/LoggerLevelsTests.swift` — covers LOG-02
- [ ] `validationLedgerUITests/` target (XCUITest) — does not exist; create as Wave 0 (covers CI-02 placeholder)
- [ ] `validationLedgerUITests/RoleShellSmokeTests.swift` — covers CI-02 (placeholder per Assumption A10)
- [ ] `validationLedgerDeviceTests/` target — does not exist; create as Wave 0 (covers D-06)
- [ ] `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` — covers D-06
- [ ] `.swiftlint.yml` with 4 custom rules — does not exist
- [ ] Swift Testing framework install: **none — bundled with Xcode 16+ (verified)**

## Security Domain

Security enforcement is on (default; not disabled in config). Phase 1's security posture is "build the skeletons correctly, ship no cryptography or real secret handling."

### Applicable ASVS Categories

| ASVS Category | Applies | Phase 1 Standard Control |
|---------------|---------|---------------------------|
| V1 Architecture | yes | Initializer-DI composition root (AppContainer), protocol-first cross-module boundaries, `App/ → Features/ → Core/ (protocols)` dependency direction enforced by SwiftLint. [VERIFIED: ARCH-04/05] |
| V2 Authentication | partial (Phase 1 ships protocols only) | `SessionLockService` protocol + stub; real OTP + biometric in Phase 3. |
| V3 Session Management | partial | `SessionLockService.shouldRequireBiometric` stub enforces unified invariant. |
| V4 Access Control | N/A in Phase 1 | No real auth until Phase 3. |
| V5 Input Validation | N/A in Phase 1 | No user input surfaces until Phase 3 (OTP). |
| V6 Cryptography | partial | `KeyStoreProtocol` + `SoftwareKeyStore` (test-only); real `SecureEnclaveKeyStore` is Phase 2. **Never hand-roll symmetric crypto** — use CryptoKit. |
| V7 Error Handling | yes | `Logger` + PII scrubber is the only logging path; no `print()` / `os_log` in app code (D-19). |
| V8 Data Protection | yes | `KeychainStore` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; ATS strict (SEC-02); no sensitive data in `UserDefaults` (SEC-03 + SwiftLint rule). |
| V9 Communications (TLS) | partial | `PinningSessionDelegate` skeleton in `Core/Networking/CertificatePinning/`; real dual-pin implementation is Phase 2 (FOUND-05 full, SEC-01). |
| V10 Malicious Code | N/A in Phase 1 | Jailbreak heuristics land later. |
| V11 Business Logic | N/A in Phase 1 | No business logic yet. |
| V14 Configuration | yes | `PrivacyInfo.xcprivacy` declared (FOUND-06); `#if DEBUG` gates dev surfaces (D-13). |

### Known Threat Patterns for iOS Security-Sensitive Apps

| Pattern | STRIDE | Standard Mitigation (Phase 1) |
|---------|--------|-------------------------------|
| Keychain items leak across reinstall (prior user's tokens) | Information Disclosure | First-launch wipe (FOUND-02 + D-20). Enumerate-before-delete under app's access group. |
| PII in logs (phone, DL, GPS in crash reports or analytics) | Information Disclosure | `PIIScrubber` middleware enforced as only logging path (FOUND-01 + D-16). SwiftLint bans direct `print()`/`os_log()` (D-19). |
| Tokens in `UserDefaults` readable from backup extraction | Information Disclosure | SwiftLint rule `ban_userdefaults_tokens` (SEC-03 + D-19). |
| Debug surfaces in Release build | Elevation of Privilege | `#if DEBUG` compile-out for DevMenu (D-13); physical absence is stronger than runtime flag. |
| Cert pinning with no rotation plan | Denial of Service (self-brick) | Phase 1 ships `PinningSessionDelegate` skeleton + `docs/cert-rotation.md` skeleton. Full dual-pin implementation is Phase 2. |
| No ATS → plaintext HTTP possible | Information Disclosure + Tampering | ATS strict in `Info.plist` (SEC-02). |
| Secure Enclave code falsely green on simulator | Spoofing (fake key attestation in dev) | CI split (FOUND-04 + D-01..D-06). Production build refuses launch if SE unavailable. |
| `PrivacyInfo.xcprivacy` missing from bundle → App Store rejection | N/A (submission DoS) | D-21 declares manifest + CI grep check (Pattern 5). |
| Cross-feature tight coupling → test isolation breaks + security audit of one feature requires reading all | Tampering (security-critical module inseparable from non-sensitive code) | SwiftLint `no_cross_feature_import` rule (ARCH-05 + D-19). |

## Discrepancy Flags (surfaces for planner)

### Flag #1: ROADMAP Success Criterion 2 vs CONTEXT.md D-19 — raw-coordinate-literal ban

**Conflict:**
- **ROADMAP.md Phase 1 Success Criterion 2** says: "...the same test suite fails a SwiftLint custom rule when `print()`, direct `os_log(...)`, **or raw coordinate literals** appear in application code."
- **CONTEXT.md D-19** explicitly DEFERS raw-coordinate-literal ban to Phase 3: "Deferred to Phase 3 (not Phase 1 scope): raw-coordinate-literal ban for GEO-03 phantom-typed `AnalyticsEvent`."

**Resolution per GSD workflow:** CONTEXT.md wins. User's locked decision supersedes ROADMAP Success Criterion 2 on this point. Phase 1 ships 3 of 4 SwiftLint rules that the ROADMAP criterion names (`print`, `os_log`, `*token*`/`*key*`/`*session*` UserDefaults), PLUS the no-cross-feature-import rule. Raw-coordinate-literal ban lands in Phase 3 alongside GEO-03.

**Planner action:** (a) Include a note in the Phase 1 plan explaining which 4 rules ship and which one is deferred. (b) Add a reminder task in the Phase 3 plan template ("Add SwiftLint rule `no_raw_coordinate_literals` per deferred D-19 spec"). (c) Verify success criterion 2 can be met with the modified rule list — the test suite should verify the 4 shipping rules fire on planted violations; the 5th (coordinates) is tested in Phase 3.

### Flag #2: Xcode version on dev machine (26.4) vs CI floor (16.x)

**Not a conflict; a documentation gap.** STACK.md says "Xcode 26.4.1 locally; floor Xcode 16.x in CI." The dev MacBook has Xcode 26.4; CI workflow selects Xcode 16.4 via `sudo xcode-select -s`. This is intentional (CI must use the floor version so Swift Testing + iOS 17 SDK are available without surprises) but should be explicit in `docs/ci.md`.

**Planner action:** Ensure `docs/ci.md` clearly documents (a) dev uses Xcode 26.4, (b) CI pins Xcode 16.4, (c) the reason: Swift Testing bundled, iOS 17 SDK available, Swift 6 mode permitted.

### Flag #3: CI-02 Phase-1 scope literal reading

**Conflict (soft):**
- **REQUIREMENTS.md CI-02:** "One smoke UI test per role (5 total) covers launch → OTP enter → role shell renders → logout."
- **ROADMAP.md Phase 1 traceability:** CI-02 is Phase 1.
- **Phase 1 scope:** No OTP flow exists yet (that's Phase 3 AUTH-01/02).

**Resolution recommendation (Assumption A10):** Phase 1 ships `validationLedgerUITests/RoleShellSmokeTests.swift` with **placeholder** tests that verify each of the 5 TabBarController subclasses renders its expected tabs (title + SF Symbol). The full "launch → OTP → logout" path is exercised by Phase 3 when AUTH-01..05 + SHELL-01..04 are complete. The planner's choice is binary: (a) ship placeholders now and update them in Phase 3, or (b) mark CI-02 as Phase 3 in the traceability table.

**Planner action:** Pick one. Surface the decision at plan-check for user confirmation.

### Flag #4: CONTEXT.md D-02 scope of "MockURLProtocol (scaffolding + fixtures)"

**Ambiguous:**
- **CONTEXT.md D-02:** Names MockURLProtocol as a Phase-1 unit-test target.
- **CONTEXT.md out-of-scope note:** Lists NET-01..NET-05 (including NET-02 MockURLProtocol fixtures) as Phase 2.

**Resolution recommendation (Assumption A4):** Phase 1 ships the `MockURLProtocol` class + 1 trivial fixture (e.g., a `GET /ping` returning `{"ok":true}` so the test target compiles and runs). Phase 2 adds real M1-endpoint fixtures.

**Planner action:** Same as Flag #3 — surface at plan-check.

### Flag #5: FOUND-05 cert rotation runbook content

**Not a conflict; explicit deferral per CONTEXT.md D-18 Claude's Discretion section.** "docs/cert-rotation.md skeleton only in Phase 1 (FOUND-05 full runbook content is a Phase 2 deliverable — skeleton exists so the path is reserved)." STATE.md explicitly notes this as a known concern.

**Planner action:** `docs/cert-rotation.md` ships with header + "STUB — full content in Phase 2" note + the 30-day rotation window pattern outline (from PITFALLS.md P3).

## Sources

### Primary (HIGH confidence)

- [Apple Developer — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) — `NSPrivacyAccessedAPICategoryUserDefaults` + `CA92.1` reason code
- [Apple Developer — Swift Testing](https://developer.apple.com/xcode/swift-testing/) — bundled with Xcode 16+, no package dep needed
- [Apple Developer — Swift Testing Documentation](https://developer.apple.com/documentation/testing) — `@Test`, `#expect`, parameterized test syntax
- [SwiftLint custom_rules Reference](https://realm.github.io/SwiftLint/custom_rules.html) — YAML regex custom rules
- [Apple Developer Forums thread 748611](https://developer.apple.com/forums/thread/748611) — Secure Enclave simulator unavailability
- `.planning/research/ARCHITECTURE.md` — 12-step M1 build order (Phase 1 implements steps 1–9); 4 amendments to TechStack.md §3; SceneDelegate root-swap pattern
- `.planning/research/STACK.md` — pinned library versions (Nuke 13.0.2, SwiftLint 0.63.2, SwiftFormat 0.61.0) verified against GitHub releases 2026-04-20
- `.planning/research/PITFALLS.md` — 8 foundational conventions P1–P8; 20 pitfalls total with phase mappings
- `.planning/research/SUMMARY.md` — executive validation of stack + architecture + pitfall priority
- `.planning/research/FEATURES.md` — competitor analysis framing Phase 1 as infrastructure-only
- `CONTEXT.md` (this phase) — 21 locked decisions
- `TechStack.md` — 13-section iOS spec

### Secondary (MEDIUM confidence — web-verified 2026-04-20)

- [GitHub Actions self-hosted runner for iOS CI (MacStadium)](https://macstadium.com/blog/github-actions-self-hosted-runner-for-ios-ci-at-macstadium) — self-hosted runner setup pattern
- [iOS CI/CD with self-hosted Mac Mini (esinx.net)](https://esinx.net/blog/ios-ci-cd-selfhosted/) — runner registration + xcodebuild destination
- [Migrating iOS GitHub Actions to Self-Hosted M1 Mac Runners (Whatnot)](https://medium.com/whatnot-engineering/migrating-ios-github-actions-to-self-hosted-m1-macs-runners-f75fbb00ab1b) — device-attached runner experience report
- [SwiftLint custom rules examples (verbalraj)](https://verbalraj.medium.com/custom-swiftlint-rules-ios-33c0dc780a26) — regex pattern for banning `print()`
- [Useful Custom Rules for SwiftLint (Yonat Sharon)](https://ootips.org/yonat/useful-custom-rules-for-swiftlint/) — regex patterns
- [Swift testing with SwiftPM using Xcode 16 — Swift Forums](https://forums.swift.org/t/swift-testing-with-swiftpm-using-xcode-16-and-swift-6/72372) — no package dep needed with tools 6.0
- [ITMS-91053 Missing API Declaration Privacy (blog.ni18.in)](https://blog.ni18.in/itms-91053-missing-api-declaration-privacy/) — Copy Bundle Resources gotcha + exact App Store rejection error code

### Tertiary (LOW confidence — flagged for verification)

- Exact GitHub-hosted `macos-latest` image Xcode version — varies over time; planner should not pin to macos-14 or macos-15 specifically without checking [runner-images releases](https://github.com/actions/runner-images/releases) at plan execution time.
- Whether `xcodebuild -downloadPlatform iOS -buildVersion 17.5` is the current invocation — Apple CLI has shifted syntax in the past; planner should verify in current Xcode release notes.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions verified against GitHub releases API 2026-04-20 (via research/STACK.md) + local `xcodebuild -version` confirmation
- Architecture: HIGH — research/ARCHITECTURE.md is prescriptive and this phase defers to it explicitly
- Pitfalls: HIGH — research/PITFALLS.md maps all 8 foundational conventions to Phase 1; cross-referenced with CONTEXT.md decisions
- CI: HIGH — CONTEXT.md D-01..D-06 are locked; research confirms feasibility; local runtime gap flagged
- SwiftLint custom rules: MEDIUM — regex patterns work but Rule 4 (no-cross-feature-import) has zero Phase-1 violations and is future-proofing. Flagged as Assumption A3.
- PIIScrubber design: MEDIUM — category rules are derivable from Success Criterion 2 + D-16, but the string-fallback regex set will need iteration during implementation as false positives surface.
- Validation Architecture: HIGH — every REQ mapped to a testable command; 10 Wave-0 test files enumerated.

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (30 days — stack versions and SwiftLint rule docs are stable; if planning extends past 2026-05-20, re-verify Nuke / SwiftLint / SwiftFormat latest versions and Apple Xcode 16.x availability on macos-latest)
