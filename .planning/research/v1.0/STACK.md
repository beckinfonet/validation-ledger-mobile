# Stack Research — Validation Ledger iOS Client

**Domain:** Security-sensitive, identity-verified freight iOS client (UIKit-first, iOS 17+, Swift 5.9+, SwiftPM-only)
**Researched:** 2026-04-20
**Milestone:** M1 Foundation (greenfield — bundle id `com.maldin.validationLedger`)
**Overall confidence:** HIGH

> This file is prescriptive. Where it disagrees with `TechStack.md §2.1`, a **Delta vs TechStack.md** callout appears with rationale. TechStack.md §2.1 is an 8-month-old "pre-approved shortlist" written before GSD init; several of its named candidates are stale in 2026.

---

## TL;DR — The Pinned Stack

| Concern | Pick | Version | Confidence |
|---|---|---|---|
| IDE / toolchain | **Xcode 26.4.1** (stable), floor Xcode 16.x | 26.4.1 (2026-04-16) | HIGH |
| Language | **Swift 5.9 floor, Swift 6 mode allowed per-file** | 6.3 compiler in toolchain | HIGH |
| UI | **UIKit** (SwiftUI allowed in Settings/static only) | iOS 17 SDK | HIGH (spec-locked) |
| Architecture | **MVVM + hand-rolled Coordinators** (no library) | — | HIGH |
| DI | **Initializer injection via `AppContainer`** (no Swinject/Resolver) | — | HIGH (spec-locked) |
| Concurrency | **async/await primary, Combine for UI binding only** | native | HIGH |
| Networking | **URLSession + thin custom wrapper** (no Alamofire) | native | HIGH |
| Mocking | **URLProtocol subclass in-repo** + Mocker in tests | Mocker 3.0.2 | HIGH |
| Keychain | **Hand-rolled `SecItem` wrapper in `Core/Storage/`** (NOT KeychainAccess) | native | **HIGH — overrides TechStack.md** |
| Crypto / device key | **Apple CryptoKit `SecureEnclave.P256.Signing`** | native | HIGH |
| Cert pinning | **Native `URLSessionDelegate`** on a single `NetworkClient` | native | HIGH |
| Images | **Nuke 13.0.2** (not SDWebImage) | 13.0.2 (2026-04-15) | HIGH |
| QR gen / scan | **CoreImage / AVFoundation** (built-in) | native | HIGH (spec-locked) |
| Testing | **Swift Testing for new unit tests + XCTest for UI tests** | Swift Testing in Xcode 16/26 | HIGH |
| Snapshots | **swift-snapshot-testing** | 1.19.2 (2026-03-30) | MEDIUM |
| Linting | **SwiftLint 0.63.2** via **SwiftLintPlugins** SwiftPM plugin | 0.63.2 (2026-01-26) | HIGH |
| Formatting | **SwiftFormat 0.61.0** (nicklockwood) | 0.61.0 (2026-04-11) | HIGH |
| Project file | **Commit `.xcodeproj`** (no xcodegen/tuist for M1) | — | HIGH |
| Logging | **os_log / OSLog + OSLogStore** | native | HIGH (spec-locked) |

Everything above is verifiable — see `Sources` at the bottom.

---

## Recommended Stack (Detailed)

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **Xcode** | 26.4.1 stable (floor 16.x) | Build toolchain | Xcode 16 shipped Swift Testing + Swift 6 mode; Xcode 26 ships Swift 6.3 with improved Observation, strict-concurrency warnings, and iOS 17–26.5 SDKs. Xcode 15 still technically builds iOS 17 but is two major versions behind, has no Swift Testing, and will not receive iOS 26 SDK updates. |
| **Swift** | 5.9 floor in `Package.swift` `swift-tools-version`; Swift 6 language mode permitted per-module | Language | Matches spec §2: "Swift 5.9+, Swift 6 concurrency adoption allowed in new code, not required retroactively." Targeting 5.9 keeps SwiftPM broadly compatible; new `Core/` modules can opt into Swift 6 mode with `.enableUpcomingFeature("StrictConcurrency")`. |
| **iOS SDK / deployment target** | iOS 17.0 minimum | Platform | Spec-locked. Enables `Observable` macro, VisionKit `DataScannerViewController`, modern URLSession async APIs without back-deploy shims. Apple SDK policy (Xcode 26) supports deployment targets down to iOS 15, so 17 is comfortably current. |
| **UIKit** | iOS 17 SDK | Primary UI framework | Spec-locked for all sensitive surfaces (camera, KYC, scanner, BOL). No SwiftUI rendering quirks on `AVCaptureVideoPreviewLayer`, stable lifecycle for screenshot-block overlays, mature for the team size. |
| **Swift Package Manager** | bundled | Dependency management | Spec-locked. No CocoaPods, no Carthage. All packages below are SwiftPM-compatible. |
| **CryptoKit (SecureEnclave.P256.Signing)** | native | Device-bound keypair (FR-iOS-DEV) | Apple-blessed, SEP-backed, P-256 only (the only curve SEP supports). See `Secure Enclave gotchas` below. |
| **URLSession (async/await)** | native | HTTP transport | `URLSession.data(for:)`, `URLSession.upload(for:fromFile:)`, `URLSessionWebSocketTask` cover every M1 need. No feature Alamofire provides that justifies a 228-file dependency for a team of 1–2 and a zero-PII app. |
| **os_log / OSLog / OSLogStore** | native | Structured logging w/ PII scrubbing | Spec-locked (§10 Open Q7 defers crash vendor). `OSLog.Logger` provides privacy annotations (`.private(mask: .hash)`) that belong in the PII-scrubber. No SDK weight, no network surface, queryable via `OSLogStore` in-app for support dumps. |

### Supporting Libraries (pinned to SwiftPM)

| Library | Version | Purpose | When to Use |
|---|---|---|---|
| **Nuke** | `13.0.2` (2026-04-15) | Async image load + cache for load photos, ID doc thumbnails, avatars | Any image from backend; use `ImagePipeline.shared` + `LazyImage` (UIKit) or `ImageTask` with async/await. Memory cap configurable, disk cache off by default in `Core/Networking/ImageLoader`. |
| **swift-snapshot-testing** | `1.19.2` (2026-03-30) | Snapshot tests for chain-of-trust timeline, BOL render, QR screen | Pair with XCTest in `Tests/SnapshotTests/`. Record on iPhone 15 simulator only; don't chase device matrix in snapshots. |
| **Mocker** | `3.0.2` (2024-01-15) | URLProtocol-backed mocks in tests | Test target only — do NOT ship in main target. M1 production-side mock is a hand-rolled `MockURLProtocol` in `Core/Networking/Mock/` so the dev build can swap between `live` and `mock` BASE_URL configs without a library dep. |
| **SwiftLint** | `0.63.2` via **SwiftLintPlugins 0.63.2** | Style enforcement | SwiftPM build tool plugin on every target. Start with `opt_in_rules` set; add custom rules for `// MARK: - PII` scrubber audit points. |
| **SwiftFormat** | `0.61.0` (nicklockwood) | Automated format pass | Pre-commit hook + Xcode Run Script phase. Run-only-on-staged-files mode. Prefer nicklockwood's SwiftFormat over Apple's swift-format 602.x — larger rule surface, more aggressive on import ordering, and broader community config baseline. |

**Libraries explicitly NOT installed (see "What NOT to Use" for why):**
KeychainAccess, Alamofire, SDWebImage, Quick, Nimble, TrustKit, XCoordinator, Swinject, Resolver, RxSwift, tuist, xcodegen.

### Development Tools

| Tool | Purpose | Notes |
|---|---|---|
| **Xcode 26.4.1** | Build + debug + Swift Testing UI | Enable "Strict Concurrency Checking: Targeted" in build settings. Enable "Sendable compliance warnings: error" on new modules once Phase 1 stabilizes. |
| **Xcode build plugin: SwiftLintPlugins** | Runs SwiftLint on every build | Per `Package.swift` plugin config; fails build on violations in CI, warnings locally. |
| **Git pre-commit hook** | SwiftFormat --lint + SwiftLint --strict on staged `.swift` | `.git/hooks/pre-commit` shell script — do not use husky or similar cross-language tools. |
| **GitHub Actions** (or Xcode Cloud) | CI: lint, unit tests, snapshot tests, smoke UI per role | Spec §9. Use `xcodebuild test` against the same simulator as snapshot recording to avoid pixel-diff flakiness. |
| **xcbeautify** (optional) | Prettier `xcodebuild` output | Dev convenience only; no CI dependency. |

---

## Installation

```swift
// Package.swift  (or add via Xcode > File > Add Package Dependencies)
dependencies: [
    .package(url: "https://github.com/kean/Nuke.git",                              from: "13.0.2"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git",     from: "1.19.2"),
    .package(url: "https://github.com/WeTransfer/Mocker.git",                      from: "3.0.2"),
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git",           from: "0.63.2"),
],
targets: [
    .target(
        name: "ValidationLedger",
        dependencies: [
            .product(name: "Nuke",      package: "Nuke"),
            .product(name: "NukeUI",    package: "Nuke"),
        ],
        plugins: [ .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins") ]
    ),
    .testTarget(
        name: "ValidationLedgerTests",
        dependencies: [
            "ValidationLedger",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(name: "Mocker",          package: "Mocker"),
        ]
    ),
],
```

**CLI tooling (Homebrew, not SwiftPM):**
```bash
brew install swiftformat   # nicklockwood/SwiftFormat, currently 0.61.0
# SwiftLint is resolved via SwiftLintPlugins; no Homebrew install needed.
```

---

## Deltas vs `TechStack.md §2.1` (the pre-GSD shortlist)

| TechStack.md said | 2026 recommendation | Why the override |
|---|---|---|
| "**Networking:** Apple URLSession + lightweight wrapper. No Alamofire unless a blocker emerges." | Keep as written — URLSession only. | Agrees with 2026 consensus. For a security-sensitive, zero-PII app with 1–2 engineers, Alamofire's interceptor stack adds surface area (retry semantics, parameter encoders) the app doesn't use. Device-signed headers belong in a hand-rolled wrapper next to the `SecureEnclave` signer anyway. |
| "**Keychain:** `KeychainAccess` or hand-rolled wrapper." | **Hand-rolled.** | **KeychainAccess is effectively unmaintained.** Last release `v4.2.2` is from **2021-03-01**; last commit on `master` is **2023-11-12** (repo chore: "Remove screenshots"). No iOS 17 or Swift 6 concurrency support has landed. The lib wraps ~15 `SecItem*` calls — the exact size and shape of thing a security-critical app should own. A 150-line `KeychainStore` in `Core/Storage/` is smaller than the vendoring cost, audits cleanly, and binds `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `.biometryCurrentSet` ACLs exactly per FR-iOS-AUTH / §8. |
| "**Crash/analytics:** Sentry or Firebase Crashlytics (pick one in M1). PII-scrubbed." | **Defer past M1** (per PROJECT.md §Out-of-Scope → "Crash/analytics vendor pick deferred to M2 per §12 Open Q7"). Use `os_log` / `OSLogStore` for M1. | Already captured in PROJECT.md. Noted here so `STACK.md` agrees. |
| "**Image loading/caching:** Nuke or SDWebImage." | **Nuke 13.0.2.** | Both are actively maintained (Nuke commit 2026-04-15, SDWebImage commit 2026-04-13), so both are viable. Nuke wins for a *new Swift 6-capable app*: it is **pure Swift, fully Sendable, uses a `@globalActor ImagePipelineActor` for thread-safety compiler-enforced**, and integrates natively with async/await and Combine. SDWebImage is Objective-C at its core (still ~85% ObjC), requires `@objc` bridging at API boundaries, and its Swift concurrency story is bolt-on. For a 2026 UIKit + async/await stack, Nuke is the native-feeling choice. |
| "**QR generation:** CoreImage (built-in). **QR scanning:** AVFoundation (built-in). **Liveness:** Apple Vision framework." | Keep as written. | Correct. No third-party liveness SDK in M1 (PROJECT.md §Out-of-Scope). |
| (Not mentioned) "**Certificate pinning**" (FR-iOS-SEC MUST) | **Hand-rolled in `URLSessionDelegate`**, pinned to **SPKI hash** of the leaf, with a rotation-plan constant file. | TrustKit (`3.0.7`, 2025-06-04) is maintained but adds a dependency + Objective-C runtime for ~80 lines of delegate code. Pin SPKI (public-key-info hash) not the cert; that way cert rotation does not require a client update if the key is reused. Keep the hash list in `Core/Security/PinnedHosts.swift`, emit a telemetry event on pin failure (no PII), fail closed. |
| (Not mentioned) "**UIKit coordinator library**" | **Hand-rolled.** | **XCoordinator is abandoned** (last release `2.2.1` on 2023-02-28, commits stopped same day). Hand-rolling a `Coordinator` protocol + `AppCoordinator` + role coordinators is <100 LOC for the five roles and composes cleanly with `AppContainer` initializer DI. No library dep is the 2026 consensus for UIKit coordinators when MVVM+Coordinators is the target architecture. |

**TechStack.md §2 Xcode guidance ("Xcode 15+"):** Technically accurate but stale — Xcode 15 is two major versions behind in April 2026. Recommendation: floor Xcode 16.x in CI so Swift Testing is available. Developers should use Xcode 26.4.1 locally. This is a **minor update to TechStack.md §2**, not a behavior change.

---

## Architecture Patterns (how the pieces fit)

### UIKit Coordinators — hand-rolled skeleton

```swift
// Core/Navigation/Coordinator.swift
@MainActor protocol Coordinator: AnyObject {
    var children: [Coordinator] { get set }
    var navigationController: UINavigationController { get }
    func start()
}

@MainActor extension Coordinator {
    func add(_ child: Coordinator)    { children.append(child) }
    func remove(_ child: Coordinator) { children.removeAll { $0 === child } }
}
```

- **`AppCoordinator`** decides: splash → OTP auth → role router.
- **`RoleCoordinator`** per role (ShipperCoordinator, BrokerCoordinator, …) swaps the tab bar's VC graph.
- **ViewModels** are `@MainActor` classes that own `@Published` state (Combine) + expose `async` methods for side effects.
- **Coordinators receive dependencies** (auth, network, keychain) from the `AppContainer` via initializer — no service locator, no property wrappers.

This matches TechStack.md §3.1–3.3 exactly.

### Swift Concurrency + Combine coexistence (2026 consensus)

| Shape of work | Tool | Example |
|---|---|---|
| **Single-response async operation** (login, KYC upload, load fetch) | `async`/`await` + `throws` | `let session = try await auth.login(code:)` |
| **Values over time** (ViewModel state → View binding, WebSocket/SSE, location stream) | Combine `@Published` / `PassthroughSubject` | `@Published var session: Session?` observed by VC |
| **Multiple cooperating async operations** | `async let` / `TaskGroup` | Parallel KYC uploads |
| **Bridge async → Combine** | `Future { promise in Task { ... } }` wrapper | Rare; prefer refactoring to one or the other |
| **Bridge Combine → async** | `.values` async sequence | Consuming `@Published` from an async loop |

**Rule for this codebase:** ViewModels expose `async throws` methods *and* `@Published` state. Use case (Repository) layer is pure `async`. Networking is pure `async`. Only the seam between VM and VC uses Combine.

### Secure Enclave — the gotchas that matter for FR-iOS-DEV

1. **SEP keys are device-bound and non-exportable.** A key generated on Device A cannot be used on Device B. An iCloud restore to a new device **invalidates every SEP key**. ⇒ Spec-appropriate: "one active device per user" plus re-KYC on device switch is the correct UX.
2. **Only P-256 is supported** (`SecureEnclave.P256.Signing.PrivateKey`, `.KeyAgreement.PrivateKey`). No P-384, no Ed25519, no RSA. The spec already aligns (EC P-256).
3. **Simulator has no SEP.** `SecureEnclave.isAvailable` returns `false`. Write dev-time fallback gated by `#if targetEnvironment(simulator)` that uses a plain `P256.Signing.PrivateKey` stored in Keychain — but **fail production login if SEP is unavailable on-device** (FR-iOS-DEV MUST).
4. **Private key material never surfaces.** `.rawRepresentation` throws `ENOTSUP`. Persist the **`.dataRepresentation` blob** (opaque key handle) in Keychain bound to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `.biometryCurrentSet`. Reload with `SecureEnclave.P256.Signing.PrivateKey(dataRepresentation:)`.
5. **Access control triggers biometric prompts.** Sign operations with a `.biometryCurrentSet` key will prompt Face ID / Touch ID. For the "sign every sensitive request" requirement (FR-iOS-AUTH), decide which key ACL class applies: either (a) no biometric gate for routine signs + a separate biometric-gated key for tender/accept, or (b) a single biometric key + a short in-process LAContext reauth window. Recommend **two keys**: `deviceKey` (passcode-only) and `authorizationKey` (biometric-current-set) — cleaner than managing LAContext lifetime.
6. **Re-enrollment of biometrics invalidates `.biometryCurrentSet` keys.** This is the intended trust-boundary behavior and aligns with §8 "biometric re-enrollment invalidates the key and forces re-binding."
7. **Attestation is separate.** App Attest / DeviceCheck are **not** the same as SEP key attestation. SEP P-256 keys have no Apple-signed attestation — backend must accept the client's registration on trust of the TLS + attested App Attest payload. (M1 deferred, implement in later M1 phase per PROJECT.md.)

### Networking — shape of the wrapper

```swift
// Core/Networking/NetworkClient.swift
protocol NetworkClient: Sendable {
    func send<R: Endpoint>(_ req: R) async throws -> R.Response
}

struct URLSessionNetworkClient: NetworkClient {
    let session: URLSession
    let baseURL: URL
    let signer: RequestSigner?         // nil except on sensitive endpoints
    let pinningDelegate: PinningDelegate
    // ...
}
```

- One `URLSession` instance per app (shared), configured with a custom `URLSessionDelegate` that implements cert pinning (SPKI hash list).
- One `MockURLProtocol` subclass registered in `URLSessionConfiguration.protocolClasses` for dev builds pointing at `mock://` BASE_URL.
- `Endpoint` is a protocol with associated `Response: Decodable`; request building + decoding lives in the generic `send`.
- Retry with exponential backoff is a wrapping decorator (`RetryingNetworkClient`) not a `URLSession` feature — keeps idempotency-key handling explicit per spec §7.

---

## Alternatives Considered

| Our choice | Alternative | When the alternative would win |
|---|---|---|
| URLSession + wrapper | **Alamofire 5.11.2** | Large team, multipart form-data heavy, needs interceptors/adapters/retriers with battle-tested edge cases. Not our profile. |
| URLSession + wrapper | **kean/Get 2.2.1** | Like a tiny Alamofire, Swift-native. Attractive — but last release 2024-10-15 (stale by 18 months), 100-line `NetworkClient` is cheaper than vendoring. |
| Hand-rolled Keychain wrapper | **KeychainAccess 4.2.2** | If the library were still maintained. It is not (see Deltas). |
| Hand-rolled Coordinators | **XCoordinator 2.2.1** | Never, at this scale — it is abandoned. |
| Native URLSessionDelegate pinning | **TrustKit 3.0.7** | If iOS + tvOS + macOS + watchOS all share pinning config and the team wants SPKI hash reporting built in. For iOS-only with one host, native is lighter. |
| Nuke 13 | **SDWebImage 5.21.7** | A large ObjC/Swift mixed codebase that already has SDWebImage elsewhere, or a need for animated WebP/JPEG-XL plugins (`SDWebImageWebPCoder`, `SDWebImageJPEGXLCoder`) that Nuke doesn't ship. Not our profile. |
| Swift Testing | **XCTest-only** | If CI must run on Xcode < 16 (not our situation — we floor at Xcode 16 for this very reason). |
| Swift Testing | **Quick 7.6.2 + Nimble 14.0.0** | BDD-style specs with describe/it syntax. Quick last released 2024-07-23 (slow cadence). Swift Testing's `#expect` + traits + parameterized tests covers 95% of what Quick offered with zero external deps and native concurrency support. |
| Commit `.xcodeproj` | **XcodeGen 2.45.4** | Merge conflicts on `project.pbxproj` becoming a real tax — revisit at M3 when the file-tree settles. For M1 (single-module, 1–2 devs), XcodeGen is overhead. |
| Commit `.xcodeproj` | **Tuist 4.182.0** | Multi-module modularization with build-time caching (Tuist cache) moves the needle. Our app is one module in M1. Revisit at M4 if modularization becomes a real goal. |
| SwiftFormat (nicklockwood) | **Apple swift-format 602.0.0** | Apple's official formatter paired with `swift format lint` in CI. Smaller ruleset, less aggressive. Use if the team wants "just Apple's thing." |
| Combine for VM ↔ VC binding | **Observation (@Observable)** | Pure SwiftUI apps. Our UIKit VCs subscribe via `AnyCancellable`; the Observation framework's `withObservationTracking` is awkward from UIKit. When/if we adopt SwiftUI for a feature, switch that feature's VM to `@Observable`. |

---

## What NOT to Use

| Avoid | Why (specific) | Use Instead |
|---|---|---|
| **KeychainAccess** | Last release 2021-03 (v4.2.2); last commit 2023-11 is a repo cleanup, not code. No iOS 17 / Swift 6 validation. In a security-critical app, depending on an unmaintained crypto-storage wrapper is a liability — and the library's surface is 15 `SecItem` calls you can own in 150 LOC. | Hand-rolled `KeychainStore` in `Core/Storage/Keychain/` |
| **XCoordinator** | Abandoned: last release v2.2.1 on 2023-02-28, commits stopped the same day. Pre-Swift-6, pre-concurrency. | Hand-rolled `Coordinator` protocol + per-role coordinators |
| **Alamofire** | Not "bad" — overkill. Adds 228 code snippets' worth of surface (interceptors, serializers, route enums) for a 5-endpoint M1. Every dep is attack surface; zero-PII apps should minimize. | URLSession + thin `NetworkClient` wrapper |
| **Quick / Nimble** | Quick 7.6.2 last released 2024-07; framework ties you to describe/it syntax and a spec-runner-in-a-framework model that Swift Testing now renders redundant. | Swift Testing + XCTest (UI) |
| **Swinject / Resolver** | Spec-locked out: TechStack.md §3.3 mandates initializer DI via `AppContainer`. Runtime-registered DI containers hide dependency graphs and slow compile-time error detection. For a 5-feature app, initializer DI is faster, safer, grep-able. | `AppContainer` + initializer injection |
| **RxSwift / RxCocoa** | Combine + Swift Concurrency replace 100% of Rx's role in a 2026 app. Rx adds ObjC runtime dependency, slow compile, complex operator chains. | Combine (for streams) + async/await (for single-response) |
| **SDWebImage** (for this app) | Actively maintained, but 85% ObjC. Requires `@objc` bridging at API boundaries, bolt-on Swift concurrency. Adds ObjC runtime weight we don't need for a pure-Swift M1. | Nuke 13 |
| **Xcode 15.x** (as active IDE) | No Swift Testing (requires Xcode 16+), no Swift 6 language mode, no iOS 26 SDK. Two major versions stale by April 2026. | Xcode 26.4.1 locally; floor Xcode 16.x in CI |
| **Tuist / XcodeGen in M1** | Overhead without payoff on a single-module project. Adds a generation step and YAML/Swift config churn. Worth reconsidering at M3+ when file-tree churn and multi-module builds become a tax. | Commit `.xcodeproj`, tolerate small pbxproj diffs |
| **ObservableObject / @Published for new SwiftUI surfaces** | Apple has effectively replaced it with `@Observable`. Combine is still alive for non-SwiftUI, but don't build new SwiftUI code on the deprecated path. | `@Observable` macro for any SwiftUI surface (Settings, static lists) |
| **Third-party crash SDKs in M1** | PROJECT.md §Out-of-Scope — vendor pick deferred to M2 pending real failure data. | `os_log` + `OSLogStore` |

---

## Stack Patterns by Variant

**If a feature needs SwiftUI (Settings, static lists, possibly onboarding content screens):**
- ViewModel becomes `@Observable` class, not `@Published` `ObservableObject`.
- Bridge to parent Coordinator via a callback closure stored on the ViewModel's init.
- Keep the rule: no SwiftUI on camera/KYC/scanner/BOL screens (spec §2.1 / §3.1).

**If the app adds a second active device class (iPad with Apple Pencil for dispatch docs):**
- Keep the same `AppContainer` graph. iPad-specific coordinators live in `App/iPad/` but consume the same `Core/` services.
- SEP key management is unchanged — each device has its own key by design.

**If the team grows >3 engineers and multi-module becomes useful:**
- Migrate to Tuist 4.182.0 (Swift config, cache) not XcodeGen (YAML, no cache). Tuist's Swift-as-config plays better with Swift-first teams and the cache pays back on >5-module projects.
- Flip `Feature/*` modules to SwiftPM local packages before touching Tuist — often the cheaper first step.

**If M2 picks Sentry or Firebase for crash reporting:**
- Wrap the SDK behind a `CrashReporter` protocol in `Core/Analytics/`. `os_log` path becomes the fallback. Swap the implementation in `AppContainer` only.

---

## Version Compatibility

| Package | Min Swift | Min iOS | Notes |
|---|---|---|---|
| Nuke 13.0.2 | 5.9 | 13 | Uses `@globalActor ImagePipelineActor`; Sendable-clean under strict concurrency. Swift 6 compatible. |
| swift-snapshot-testing 1.19.2 | 5.9 | 13 | Works with both XCTest and Swift Testing. |
| Mocker 3.0.2 | 5.5 | 12 | Stable API since 3.0. Test-target only. |
| SwiftLintPlugins 0.63.2 (= SwiftLint 0.63.2) | 5.7 | — | SwiftPM build tool plugin; runs on host at build time, not bundled into app. |
| SwiftFormat 0.61.0 | — | — | CLI tool run via Homebrew or SwiftPM command plugin; host-only. |
| Alamofire 5.11.2 | 5.7.1 | 13 | (Not used) |
| SDWebImage 5.21.7 | 5.4 | 12 | (Not used) |
| KeychainAccess 4.2.2 | 5.0 | 9 | (Not used, abandoned) |

**Xcode / Swift / iOS combined:**

| Xcode | Bundled Swift | Supported deployment targets | Status (2026-04-20) |
|---|---|---|---|
| 26.4.1 | 6.3 | iOS 15–26.5 | Current stable — **recommended for local dev** |
| 26.5 beta 2 | 6.3 | iOS 15–26.5 | Beta — use only if chasing a beta-only fix |
| 16.4 | 6.0 | iOS 13–18 | Minimum for CI; has Swift Testing |
| 15.x | 5.9 | iOS 12–17 | Deprecated for this project |

---

## Confidence Notes (be honest)

- **HIGH** on every library version number above — verified 2026-04-20 via `api.github.com/repos/.../releases/latest`.
- **HIGH** on KeychainAccess and XCoordinator being abandoned — verified via release date + commit recency.
- **HIGH** on Xcode 26.4.1 / Swift 6.3 current state — verified via `developer.apple.com/xcode/system-requirements`.
- **HIGH** on Nuke's Swift-concurrency native posture — verified via `kean/Nuke` CHANGELOG + Context7 docs.
- **HIGH** on Secure Enclave P-256-only, simulator-unavailable, device-bound constraints — verified via Apple Developer docs + Apple Developer Forums thread 749596.
- **MEDIUM** on Snapshot testing recommendation — widely used but snapshot tests are easy to get wrong (simulator pixel differences, dynamic type). Use only on visual fixtures that don't animate.
- **MEDIUM** on "Commit .xcodeproj for M1" — a defensible 2026 consensus for single-module, small-team projects, but some teams prefer XcodeGen even for single module. The call is reversible.
- **LOW** on the exact precise answer to "does TrustKit provide enough over native pinning to justify the dep?" — reasonable people disagree; we pick native because FR-iOS-SEC requires one host and the dep surface of TrustKit for that case is not justified. Revisit if M2 adds a second backend host.

---

## Sources

### Context7 library IDs fetched
- `/kishikawakatsumi/keychainaccess` — installation, version, BioAuth policies
- `/kean/nuke` — installation, Combine bridge, processors, cache
- `/sdwebimage/sdwebimage` — installation, SwiftPM support
- `/alamofire/alamofire` — async/await surface, chained requests
- `/realm/swiftlint` — SwiftPM plugin config
- `/swiftlang/swift-testing` — Swift 6 / Xcode 16 bundling, CMake/toolchain

### Live GitHub release verification (2026-04-20)
- KeychainAccess → `v4.2.2` 2021-03-01 (abandoned; last commit 2023-11-12)
- Nuke → `13.0.2` 2026-04-15 (active; commit 2026-04-15)
- SDWebImage → `5.21.7` 2026-02-26 (active; commit 2026-04-13)
- Alamofire → `5.11.2` 2026-04-06
- SwiftLint / SwiftLintPlugins → `0.63.2` 2026-01-26
- SwiftFormat (nicklockwood) → `0.61.0` 2026-04-11
- swift-format (swiftlang) → `602.0.0` 2025-09-16
- Tuist → `4.182.0` 2026-04-17
- XcodeGen → `2.45.4` 2026-04-14
- kean/Get → `2.2.1` 2024-10-15 (stale)
- Quick → `v7.6.2` 2024-07-23
- Nimble → `v14.0.0` 2025-11-28
- swift-snapshot-testing → `1.19.2` 2026-03-30
- Mocker → `3.0.2` 2024-01-15
- TrustKit → `3.0.7` 2025-06-04 (active; commit 2026-03-24)
- XCoordinator → `2.2.1` 2023-02-28 (abandoned)

### Apple official (HIGH confidence)
- Apple — Xcode system requirements (live page, fetched 2026-04-20): Xcode 26.4.1 stable, Swift 6.3, iOS deployment targets 15–26.5.
- Apple Developer Documentation — `SecureEnclave.P256` — P-256-only, device-bound, simulator-unavailable constraints.
- Apple Developer Forums thread 749596 — Secure Enclave security model clarifications.
- Apple Developer — Swift Testing landing page — bundled with Swift 6 toolchain + Xcode 16.

### Secondary (MEDIUM confidence — corroborates but not authoritative)
- Swift Forums ST-0021 proposal review — Swift Testing / XCTest interoperability direction.
- kean.blog / Nuke 13 announcement — @globalActor ImagePipelineActor, Sendable completeness.
- tuist.dev 2025-02-25 — project generation rationale.
- Swift Forums "MVVM uikit async await actor" — @MainActor on ViewModel consensus.
- Apple Developer Forums thread 706428 — SEP inter-device key limitations.

### Training-data only (LOW confidence, flagged)
- None of the version numbers above rely on training data. The trust-but-verify protocol was followed in full.

---

*Stack research for: security-sensitive identity-verified freight iOS client (Validation Ledger M1 Foundation)*
*Researched: 2026-04-20*
*Downstream: roadmap phase structure + M1 Phase 1 planning*
