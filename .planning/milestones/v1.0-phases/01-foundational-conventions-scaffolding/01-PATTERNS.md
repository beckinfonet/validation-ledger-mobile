# Phase 1: Foundational Conventions & Scaffolding — Pattern Map

**Mapped:** 2026-04-20
**Files analyzed:** 51 files (47 new, 4 modified)
**Analogs found:** 47 external / 51 (4 novel — no analog, invented-in-phase)
**Greenfield note:** The existing codebase is the raw Xcode SwiftUI template only. There are NO in-project analogs to copy from. All "analogs" below are EXTERNAL references — RESEARCH.md excerpts, Apple documentation URLs, or pinned research artifacts in `.planning/research/`.

---

## File Classification

### Composition Root (App/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/App/AppDelegate.swift` | composition-root | event-driven (lifecycle) | `01-RESEARCH.md` §Pattern 2 (Swift sketch lines 432–469) + Apple UIApplicationDelegate docs | exact (research-sketched) |
| `validationLedger/App/SceneDelegate.swift` | composition-root | event-driven (scene lifecycle) | `01-RESEARCH.md` §Pattern 10 (Swift sketch lines 814–865) + `.planning/research/ARCHITECTURE.md` Amendment #3 | exact (research-sketched) |
| `validationLedger/App/AppCoordinator.swift` | coordinator | request-response (navigation) | `01-RESEARCH.md` §Pattern 10 (coordinator field usage lines 826, 844–851) + `.planning/research/ARCHITECTURE.md` Pattern 1 MVVM-C | role-match (invoked but not fully sketched) |
| `validationLedger/App/AppContainer.swift` | composition-root (DI) | request-response (initializer DI) | `01-RESEARCH.md` §Pattern 8 (Swift sketch lines 716–748) | exact (research-sketched) |
| `validationLedger/App/Environment.swift` | config | transform (env → config) | `01-RESEARCH.md` Pattern 8 (referenced as `Environment.current` line 727/842) | role-match (referenced, not sketched) |
| `validationLedger/App/Info.plist` | config | static | `01-RESEARCH.md` Example 3 (lines 1138–1151) — ATS strict block | exact (research-sketched) |

### Core Protocol Definitions

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Logging/Logger.swift` | core-protocol | transform (log → OSLog) | `01-RESEARCH.md` Example 1 (lines 993–1037) | exact (research-sketched) |
| `validationLedger/Core/Logging/PIIScrubber.swift` | core-protocol + impl | transform (PII redaction) | `01-RESEARCH.md` §Pattern 1 + Example 2 fixture tests (lines 1075–1131); see rule table lines 402–409 | role-match (API sketched in usage; implementation is NOVEL — see §No Analog) |
| `validationLedger/Core/Logging/Subsystems.swift` | core-util (config) | static (string constants) | `01-RESEARCH.md` D-17 (line 71) — subsystem taxonomy | role-match (named, not sketched) |
| `validationLedger/Core/Logging/LogExporter.swift` | core-util (OSLogStore pull) | batch (log read) | Apple `OSLogStore` docs; `01-RESEARCH.md` line 283 + LOG-03 row | external-doc (API is standard) |
| `validationLedger/Core/Storage/Keychain/KeychainStore.swift` | core-impl | CRUD (SecItem) | `.planning/research/STACK.md` (150-LOC hand-rolled); `01-RESEARCH.md` Pattern 2 (lines 451–466) for enumerate pattern; Apple `SecItem` docs | role-match (enumerate+delete shown; full CRUD is NOVEL — see §No Analog) |
| `validationLedger/Core/Storage/Keychain/KeychainKey.swift` | core-model | static (typed keys) | `01-RESEARCH.md` Device Smoke Test (line 577: `KeychainKey(rawValue:)`) | role-match (usage shown) |
| `validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift` | core-enum | static | `01-RESEARCH.md` Device Smoke Test (line 578: `.afterFirstUnlockThisDeviceOnly`) + Apple `kSecAttrAccessible*` docs | external-doc |
| `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` | core-protocol | request-response (sign/verify) | `01-RESEARCH.md` Pattern 8 (line 723 usage) + `.planning/research/ARCHITECTURE.md` Security Architecture | role-match (usage shown) |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | core-impl (test stub) | request-response (CryptoKit P256) | `01-RESEARCH.md` Pattern 8 (line 733 `SoftwareKeyStore()`) | role-match (construction shown) |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | core-impl (Phase-2 stub) | request-response | `01-RESEARCH.md` Assumption A8 (line 1301) — `fatalError("Phase 2")` stub pattern | exact (stub pattern stated) |
| `validationLedger/Core/Auth/SessionLockService.swift` | core-protocol + stub impl | request-response (should-prompt) | `01-RESEARCH.md` §Pattern 6 (Swift sketch lines 644–668) | exact (research-sketched) |
| `validationLedger/Core/Networking/NetworkClient.swift` | core-protocol | request-response (HTTP) | `01-RESEARCH.md` Pattern 8 (line 742 usage) + REQUIREMENTS.md NET-01 (protocol-only Phase 1) | role-match (usage shown, impl is Phase 2) |
| `validationLedger/Core/Networking/MockURLProtocol.swift` | test-scaffold | request-response (URLProtocol override) | Apple `URLProtocol` subclassing docs; `01-RESEARCH.md` Flag #4 (line 1464) + Assumption A4 | external-doc (standard URLProtocol subclass) |
| `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` | core-impl (skeleton) | event-driven (URLSession challenge) | `01-RESEARCH.md` Validation Architecture row V9 (line 1416) — skeleton only | skeleton (impl Phase 2) |
| `validationLedger/Core/Navigation/DeepLinkRouter.swift` | core-service | pub-sub (queue + drain) | `01-RESEARCH.md` §Pattern 7 (Swift sketch lines 677–707) | exact (research-sketched) |

### Role Scaffolding (Roles/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Roles/Role.swift` | core-enum | static | `01-CONTEXT.md` D-08 (line 43): `.shipper \| .broker \| .carrier \| .dispatch \| .factoring` | exact (enum cases declared) |
| `validationLedger/Roles/RoleCoordinator.swift` | core-protocol | request-response (navigation) | `01-CONTEXT.md` D-08 + `.planning/research/ARCHITECTURE.md` Pattern 5 | role-match (protocol named, not sketched) |
| `validationLedger/Roles/Shipper/ShipperTabBarController.swift` | ui-controller (UITabBarController subclass) | event-driven | `01-CONTEXT.md` D-09 tab inventory: Loads, Brokers, BOL, Assistant | role-match (tab inventory stated) |
| `validationLedger/Roles/Broker/BrokerTabBarController.swift` | ui-controller | event-driven | `01-CONTEXT.md` D-09: Loads, Carriers, Network, Assistant | role-match |
| `validationLedger/Roles/Carrier/CarrierTabBarController.swift` | ui-controller | event-driven | `01-CONTEXT.md` D-09: Loads, Drivers, Documents, Assistant | role-match |
| `validationLedger/Roles/Dispatch/DispatchTabBarController.swift` | ui-controller | event-driven | `01-CONTEXT.md` D-09: Loads, Fleet, Drivers, Assistant | role-match |
| `validationLedger/Roles/Factoring/FactoringTabBarController.swift` | ui-controller | event-driven | `01-CONTEXT.md` D-09: Invoices, Carriers, Chain, Assistant | role-match |

### DevMenu (DEBUG-only, App/DevMenu/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/App/DevMenu/DevMenuViewController.swift` | ui-controller (DEBUG) | event-driven | `01-CONTEXT.md` D-11 (single centralized menu) + `01-RESEARCH.md` ASCII diagram lines 255–259 | role-match (contents stated, not sketched) |
| `validationLedger/App/DevMenu/DevMenuShakeResponder.swift` | ui-responder (DEBUG) | event-driven (motionEnded) | `01-RESEARCH.md` §Pattern 10 shake block (lines 856–863) | exact (research-sketched) |
| `validationLedger/App/DevMenu/RoleSwitcherViewController.swift` | ui-controller (DEBUG) | request-response (role swap) | `01-CONTEXT.md` D-07, D-10 + `01-RESEARCH.md` line 257 (`sceneDelegate.presentRoot(.role(X))`) | role-match (action shown) |
| `validationLedger/App/DevMenu/KeychainInspectorViewController.swift` | ui-controller (DEBUG) | CRUD-read (SecItemCopyMatching) | `01-CONTEXT.md` D-11 + D-20 (enumerate-before-delete pattern, line 84) | role-match (enumerate API shown) |
| `validationLedger/App/DevMenu/LogViewerViewController.swift` | ui-controller (DEBUG) | batch (OSLogStore pull) | `01-CONTEXT.md` D-11 + Apple `OSLogStore.getEntries` docs | external-doc |

### Design System (UI/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/UI/DesignSystem/Colors.swift` | ui-token | static | `01-RESEARCH.md` line 361 — "minimal, unblocks VC constants" | skeleton only |
| `validationLedger/UI/DesignSystem/Spacing.swift` | ui-token | static | `01-RESEARCH.md` line 362 | skeleton only |
| `validationLedger/UI/DesignSystem/Typography.swift` | ui-token | static | `01-RESEARCH.md` line 363 | skeleton only |

### Test Targets

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedgerTests/Logging/PIIScrubberTests.swift` | test-unit (Swift Testing) | assertion | `01-RESEARCH.md` Example 2 (lines 1075–1131) — full fixture | exact (research-sketched) |
| `validationLedgerTests/Logging/LoggerLevelsTests.swift` | test-unit | assertion | `01-RESEARCH.md` Example 1 Logger protocol + LOG-02 (trace/debug/info/warn/error) | role-match (protocol is sketched) |
| `validationLedgerTests/Storage/KeychainStoreTests.swift` | test-unit | CRUD round-trip | `01-RESEARCH.md` Device Smoke Test lines 574–583 (same round-trip pattern) | exact (pattern sketched) |
| `validationLedgerTests/Storage/KeychainWipeTests.swift` | test-integration | CRUD (wipe) | `01-RESEARCH.md` §Pattern 2 + Validation row FOUND-02 | role-match (wipe code shown) |
| `validationLedgerTests/Networking/MockURLProtocolTests.swift` | test-scaffold | request-response | Apple URLProtocol test pattern; `01-RESEARCH.md` Assumption A4 (trivial happy path) | external-doc |
| `validationLedgerTests/Auth/SessionLockServiceTests.swift` | test-unit | request-response | `01-RESEARCH.md` §Pattern 6 (DefaultSessionLockService is directly testable) | exact (impl is sketched) |
| `validationLedgerTests/Navigation/DeepLinkRouterTests.swift` | test-unit | pub-sub | `01-RESEARCH.md` §Pattern 7 (queue + drain assertions directly derivable) | exact (impl is sketched) |
| `validationLedgerUITests/RoleShellSmokeTests.swift` | test-ui (XCUITest placeholder) | event-driven | `01-RESEARCH.md` Assumption A10 + Flag #3 — 5 trivial "TabBarController instantiates with N tabs" tests | role-match (placeholder scope stated) |
| `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` | test-device (Swift Testing) | assertion | `01-RESEARCH.md` §Pattern 4 (Swift sketch lines 561–583) | exact (research-sketched) |

### Config / Tooling (Repo Root)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Package.swift` | config (SwiftPM) | static | `01-RESEARCH.md` Installation block (lines 186–211) | exact (research-sketched) |
| `.swiftlint.yml` | config (lint) | static | `01-RESEARCH.md` §Pattern 9 (YAML lines 757–804) | exact (research-sketched) |
| `.swiftformat` | config (format) | static | `.planning/research/STACK.md` (SwiftFormat 0.61.0 default config) | external-doc |
| `.gitignore` | config (vcs) | static | `01-RESEARCH.md` line 296: `xcuserdata/, DerivedData/, .build/` | role-match (entries enumerated) |
| `.git/hooks/pre-commit` | script | batch (lint staged) | `01-RESEARCH.md` Example 5 (bash, lines 1209–1224) | exact (research-sketched) |

### CI (.github/workflows/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `.github/workflows/ci-simulator.yml` | ci-config | event-driven (PR trigger) | `01-RESEARCH.md` §Pattern 4 simulator YAML (lines 487–527) | exact (research-sketched) |
| `.github/workflows/ci-device.yml` | ci-config | event-driven (push + path filter) | `01-RESEARCH.md` §Pattern 4 device YAML (lines 531–557) | exact (research-sketched) |

### Documentation (docs/)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `docs/ci.md` | doc | static | `01-RESEARCH.md` Example 4 (lines 1157–1203) | exact (research-sketched) |
| `docs/cert-rotation.md` | doc (skeleton only) | static | `01-RESEARCH.md` Flag #5 (line 1474) — stub note + 30-day rotation outline | skeleton only |
| `docs/adr/0001-mvvm-c-memory-conventions.md` | doc (ADR) | static | `01-RESEARCH.md` Example 6 (lines 1230–1266) | exact (research-sketched) |
| `docs/adr/0002-role-coordinator-swap-pattern.md` | doc (ADR) | static | `01-CONTEXT.md` D-18 (line 74) + `.planning/research/ARCHITECTURE.md` Amendment #3 | role-match (purpose stated, content novel) |
| `docs/adr/0003-module-layout-and-target-strategy.md` | doc (ADR) | static | `01-CONTEXT.md` D-15 (line 69) + D-18 — records single-target + re-eval trigger | role-match (decision stated) |

### Resources

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Resources/PrivacyInfo.xcprivacy` | config (privacy manifest) | static | `01-RESEARCH.md` §Pattern 5 sample (lines 614–638) | exact (research-sketched) |
| `validationLedger/Resources/Localizable.strings` | config (empty EN file) | static | None — empty file per `01-RESEARCH.md` line 367 | skeleton only |

### Features (empty placeholders)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Features/{Onboarding,Loads,BOL,Scanner,Assistant,Profile,Settings}/` | directory-only | — | `01-RESEARCH.md` line 338 — "empty placeholder subdirs (ARCH-03)" | skeleton only (`.gitkeep` per directory) |

### Modified / Removed Files (existing Xcode scaffold)

| File | Action | Rationale |
|------|--------|-----------|
| `validationLedger/validationLedgerApp.swift` | DELETE | Replaced by UIKit `AppDelegate` + `SceneDelegate` per ARCH-01 + `01-CONTEXT.md` line 147 |
| `validationLedger/ContentView.swift` | DELETE | Replaced per ARCH-01 |
| `validationLedger/Assets.xcassets/` | RETAIN | Accent color + app icon sets retained; moved under `validationLedger/Resources/` per §Recommended Project Structure line 365 |
| `validationLedger.xcodeproj/project.pbxproj` | MODIFY | `IPHONEOS_DEPLOYMENT_TARGET` 26.4 → 17.0 (ARCH-02); add scene manifest to Info.plist; add UIKit framework; register new targets (validationLedgerTests, validationLedgerUITests, validationLedgerDeviceTests); mark `PrivacyInfo.xcprivacy` in Copy Bundle Resources phase (P14) |

---

## Pattern Assignments (Concrete Excerpts)

### `validationLedger/App/AppDelegate.swift`

**Role:** composition-root (UIKit lifecycle) — runs first-launch Keychain wipe BEFORE AppContainer resolves.
**Analog:** `01-RESEARCH.md` §Pattern 2 lines 432–469 (Swift sketch); Apple [UIApplicationDelegate docs](https://developer.apple.com/documentation/uikit/uiapplicationdelegate).

**Copy verbatim from RESEARCH.md lines 432–469:**

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
            ]
            SecItemDelete(query as CFDictionary)
        }
        defaults.set(true, forKey: flagKey)
    }
}
```

**Pitfalls to avoid (from CONTEXT.md D-20 + RESEARCH.md §Pitfall P1):**
- The wipe MUST run here — NOT in `AppContainer.init()`. If moved to AppContainer, any service depending on Keychain could read pre-wipe state (see RESEARCH.md line 430).
- DO NOT delete-by-known-key; enumerate-and-delete under the app's access group so the DevMenu inspector (D-11) can show before/after counts and so items from prior app versions are caught.
- Do not call the Logger here — Logger is resolved in SceneDelegate, after AppContainer. Log the count via a deferred hook once the logger exists (RESEARCH.md line 466 comment).

---

### `validationLedger/App/SceneDelegate.swift`

**Role:** composition-root (scene lifecycle) + root-swap mechanism for RoleCoordinator (D-10).
**Analog:** `01-RESEARCH.md` §Pattern 10 lines 814–865 (Swift sketch); `.planning/research/ARCHITECTURE.md` Amendment #3 (root swap at SceneDelegate level, not TabBarCoordinator).

**Copy verbatim from RESEARCH.md lines 814–865:**

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
        self.appCoordinator = coordinator
        self.window?.rootViewController = coordinator.rootViewController
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

**Pitfalls to avoid:**
- Do NOT mutate a `TabBarCoordinator`'s children to change roles. Recreate the root (D-10 rationale, RESEARCH.md line 867).
- `appCoordinator` must be the single strong reference — on reassignment, ARC deallocates the old tree deterministically (RESEARCH.md line 751). If you hold a second strong reference anywhere (e.g., in a static cache), the deallocation contract breaks.
- Abrupt replace — NO cross-dissolve animation (D-10, line 56). This is a dev affordance, not a product flow.

---

### `validationLedger/App/AppContainer.swift`

**Role:** initializer-DI composition root (ARCH-04).
**Analog:** `01-RESEARCH.md` §Pattern 8 lines 716–748.

**Copy verbatim from RESEARCH.md lines 716–748:**

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
        self.logger = OSLogLoggerImpl(subsystem: "com.maldin.validationLedger.app", category: "bootstrap")
        self.keychainStore = KeychainStore(accessGroup: env.keychainAccessGroup)

        #if DEBUG && targetEnvironment(simulator)
        self.keyStore = SoftwareKeyStore()
        #else
        guard SecureEnclave.isAvailable else {
            fatalError("Production build on non-SE device")
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

**Pitfalls to avoid:**
- NO singletons. No `AppContainer.shared`. Every service is stored as an instance property and passed via initializer.
- NO Swinject / Resolver / runtime DI libraries (ARCH-04, spec-locked in CLAUDE.md).
- The `#if DEBUG && targetEnvironment(simulator)` branch is load-bearing for Pitfall P8 (simulator falsely green for SE). Production must refuse launch if SE unavailable (RESEARCH.md line 736).

---

### `validationLedger/Core/Logging/Logger.swift` + `OSLogLoggerImpl.swift`

**Role:** core-protocol + OSLog-backed impl; the ONLY logging path (LOG-01).
**Analog:** `01-RESEARCH.md` Example 1 lines 993–1070.

**Copy verbatim from RESEARCH.md lines 996–1070:**

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
}

public struct LogEvent: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public static let keychainWiped = LogEvent("keychain_wiped")
    public static let firstLaunchDetected = LogEvent("first_launch_detected")
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

**Pitfalls to avoid (from RESEARCH.md Pitfall P4):**
- Both API paths (structured + string) MUST run through the same scrubber (D-16). The string path is a pressure valve, not a bypass (RESEARCH.md line 413).
- `os.Logger` is the native Apple Logger (OSLog), NOT `Logger` — alias `import OSLog` then use `os.Logger`.
- `privacy: .public` is intentional here because the scrubber has already redacted. Do NOT switch to `.private` thinking it adds safety; it would hide fields during Console.app debugging without changing the redaction contract.

---

### `validationLedger/Core/Logging/PIIScrubber.swift`

**Role:** core-impl (transform: raw PII → redacted per category).
**Analog (API shape):** `01-RESEARCH.md` §Pattern 1 rule table (lines 402–409); usage in Example 1 (`scrubber.scrub(fields)`, `scrubber.scrubString(message)`).
**Analog (test contract):** `01-RESEARCH.md` Example 2 (lines 1075–1131).

**NOVEL — this is the invented pattern (see §No Analog section).** RESEARCH.md specifies the behavior table and test contract but not the implementation. Planner writes it to pass Example 2 tests exactly.

**Redaction rule table to encode (RESEARCH.md lines 402–409):**

| Field | Rule | Example Input → Output |
|-------|------|-------------------------|
| `.phone` | Mask middle digits | `+14155550129` → `+1415•••0129` |
| `.driversLicense` | Redact entirely | `CA1234567` → `[REDACTED:DL]` |
| `.fullName` | First-initial-only | `Jane Doe` → `J. D.` |
| `.mcNumber` | Redact entirely | `MC-123456` → `[REDACTED:MC]` |
| `.dotNumber` | Redact entirely | `DOT1234567` → `[REDACTED:DOT]` |
| `.email` | Mask local part | `jane.doe@acme.com` → `j•••e@acme.com` |
| `.coordinates` | REMOVE from dict entirely (not masked) | `"37.7749,-122.4194"` → key absent |
| `.count` / `.duration` / `.event` | pass through unscrubbed (safe) | `42` → `42` |

**String-path regex fallbacks (from RESEARCH.md lines 402–409):**
- Phone: `\+?[1-9]\d{1,14}` → mask middle
- DL: `[A-Z]{1,2}[0-9]{5,8}` → `[REDACTED:DL]`
- MC/DOT: `\b(MC|DOT)[- ]?\d{5,8}\b` (case-insensitive) → `[REDACTED:MC/DOT]`
- Email: `[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}` → mask local part
- Coordinates: `-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}` → `[REDACTED:GPS]`
- Full name: hard regex infeasible; string path emits WARN telemetry `"name_in_string_log"` instead (RESEARCH.md line 406).

**Pitfalls to avoid:**
- The scrubber MUST satisfy the property-based test fixture (Example 2) — structured-path and string-path for the same input must produce equivalent redaction. Mismatch is a bug.
- Coordinates must be REMOVED from the dict, not masked (RESEARCH.md line 409). Tests assert `out[.coordinates] == nil`.

---

### `validationLedger/Core/Storage/Keychain/KeychainStore.swift`

**Role:** hand-rolled SecItem wrapper (no KeychainAccess — abandoned library).
**Analog (usage):** `01-RESEARCH.md` Device Smoke Test lines 574–583; enumerate-pattern from AppDelegate wipe (lines 451–466); `.planning/research/STACK.md` "150 LOC hand-rolled".

**NOVEL — full CRUD API is invented in this phase.** RESEARCH.md shows the caller-side contract only:

```swift
// From RESEARCH.md line 577:
let store = KeychainStore()
let key = KeychainKey(rawValue: "smoke-test-\(UUID().uuidString)")
try store.set(Data("hello".utf8), for: key, accessibility: .afterFirstUnlockThisDeviceOnly)
let out = try store.get(key)
try store.delete(key)
```

**Required API surface (derived from callers):**

```swift
public struct KeychainKey: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String)

    // Typed keys per RESEARCH.md line 322:
    public static let sessionToken: KeychainKey
    public static let installUUID: KeychainKey
}

public enum KeychainAccessibility: Sendable {
    case afterFirstUnlockThisDeviceOnly       // maps to kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    case whenUnlockedThisDeviceOnly           // kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    // ... add as needed
}

public final class KeychainStore {
    public init(accessGroup: String? = nil)                                    // RESEARCH.md line 730
    public func set(_ data: Data, for key: KeychainKey, accessibility: KeychainAccessibility) throws
    public func get(_ key: KeychainKey) throws -> Data
    public func delete(_ key: KeychainKey) throws
    public func enumerateAll() throws -> [(KeychainKey, Data)]                 // for DevMenu inspector (D-11)
}
```

**Pitfalls to avoid (RESEARCH.md Pitfall P1 + §Security V8):**
- Default accessibility MUST be `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (line 1415) — NOT `kSecAttrAccessibleAlways`.
- Every `SecItem` call must include the app's access group in its query dict if `accessGroup` is non-nil. Missing access group in set/get/delete is a silent bug — items end up in the default group and are invisible to the wipe routine.
- Round-trip test on device (KeychainStoreTests) must run the same set→get→delete sequence as the device smoke test (RESEARCH.md lines 576–582).

---

### `validationLedger/Core/KeyStore/SoftwareKeyStore.swift`

**Role:** test-only P256 keypair backed by CryptoKit, used on simulator + DEBUG.
**Analog:** Apple [CryptoKit `P256.Signing`](https://developer.apple.com/documentation/cryptokit/p256) docs; RESEARCH.md line 733 (construction).

**Contract (inferred from AppContainer usage):**

```swift
public protocol KeyStoreProtocol: AnyObject, Sendable {
    func sign(_ data: Data) throws -> Data
    func publicKeyRepresentation() throws -> Data
}

final class SoftwareKeyStore: KeyStoreProtocol {
    private let privateKey = P256.Signing.PrivateKey()   // in-memory, per-instance
    // ...
}
```

**Pitfalls to avoid:**
- MUST NOT compile into production builds. The `AppContainer` `#if DEBUG && targetEnvironment(simulator)` branch (RESEARCH.md line 732) is what gates it. If the class is referenced outside that branch, production builds will include it — add a SwiftLint rule or review checklist entry if this risks happening.

---

### `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift`

**Role:** Phase-1 STUB file — compiles but `fatalError("Phase 2")` at runtime.
**Analog:** `01-RESEARCH.md` Assumption A8 (line 1301).

**Pattern:**

```swift
// Core/KeyStore/SecureEnclaveKeyStore.swift
import CryptoKit

final class SecureEnclaveKeyStore: KeyStoreProtocol {
    func sign(_ data: Data) throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
    func publicKeyRepresentation() throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
}
```

**Pitfalls to avoid:**
- File must EXIST in Phase 1 so `AppContainer`'s `#else` branch compiles. Empty file breaks compilation.
- The production `#else` branch in AppContainer is gated by `guard SecureEnclave.isAvailable else { fatalError(...) }` BEFORE resolving this type (RESEARCH.md line 735), so a Phase 1 production build on a non-SE device still fails at the guard, not at this stub.

---

### `validationLedger/Core/Auth/SessionLockService.swift`

**Role:** core-protocol + stub (FOUND-07).
**Analog:** `01-RESEARCH.md` §Pattern 6 lines 644–668.

**Copy verbatim from RESEARCH.md:**

```swift
// Core/Auth/SessionLockService.swift
public protocol SessionLockService: AnyObject, Sendable {
    func shouldRequireBiometric(now: Date) -> Bool
    func recordBiometricSuccess(at: Date)
    func invalidate()
}

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

**Pitfalls to avoid (RESEARCH.md Pitfall P10):**
- Stub must still exercise the contract via tests NOW (SessionLockServiceTests). Phase 3 wires biometrics; the contract must not change under Phase 3 or Phase 3 slips.

---

### `validationLedger/Core/Navigation/DeepLinkRouter.swift`

**Role:** bootstrap-aware router with pending queue (FOUND-08).
**Analog:** `01-RESEARCH.md` §Pattern 7 lines 677–707.

**Copy verbatim from RESEARCH.md:**

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
        // Phase 1: log and no-op. Real handlers wire in Phase 3.
    }
}
```

**Pitfalls to avoid (RESEARCH.md Pitfall P18):**
- SceneDelegate's `scene(_:openURLContexts:)` must call `deepLinkRouter.receive(url)` IMMEDIATELY (even pre-bootstrap). The bootstrap-complete drain happens after AppContainer is fully resolved.
- `NSLock` not `@MainActor` isolation — deep links can arrive from any thread via scene callbacks.

---

### `validationLedger/Roles/Role.swift`

**Role:** core-enum (D-08).
**Analog:** `01-CONTEXT.md` D-08 line 43.

**Pattern:**

```swift
// Roles/Role.swift
public enum Role: String, CaseIterable, Sendable {
    case shipper
    case broker
    case carrier
    case dispatch
    case factoring
}
```

---

### `validationLedger/Roles/{RoleName}/{RoleName}TabBarController.swift` (×5)

**Role:** UITabBarController subclass (placeholder per D-09).
**Analog:** `01-CONTEXT.md` D-09 tab inventories line 50–55.

**Pattern (Shipper example — same shape for all 5):**

```swift
// Roles/Shipper/ShipperTabBarController.swift
import UIKit

final class ShipperTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            makeTab(title: "Loads",     systemImage: "shippingbox"),
            makeTab(title: "Brokers",   systemImage: "person.2"),
            makeTab(title: "BOL",       systemImage: "doc.text"),
            makeTab(title: "Assistant", systemImage: "sparkles"),
        ]
    }

    private func makeTab(title: String, systemImage: String) -> UIViewController {
        let vc = UIViewController()
        vc.title = title
        vc.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: nil
        )
        vc.view.backgroundColor = .systemBackground
        return vc
    }
}
```

**Tab inventories per D-09 (exact — no deviation):**

| Role | Tabs |
|------|------|
| Shipper | Loads, Brokers, BOL, Assistant |
| Broker | Loads, Carriers, Network, Assistant |
| Carrier | Loads, Drivers, Documents, Assistant |
| Dispatch | Loads, Fleet, Drivers, Assistant |
| Factoring | Invoices, Carriers, Chain, Assistant |

**Pitfalls to avoid:**
- No content in placeholder VCs. Just title + `.systemBackground`. Phase 3 fills content (per D-09 line 51).
- SF Symbol choices are planner's discretion EXCEPT: do NOT use custom image assets — SF Symbols only (no assets to add in Phase 1).

---

### `validationLedger/Resources/PrivacyInfo.xcprivacy`

**Role:** privacy manifest (FOUND-06, D-21).
**Analog:** `01-RESEARCH.md` §Pattern 5 sample lines 614–638.

**Copy verbatim from RESEARCH.md:**

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

**Pitfalls to avoid (RESEARCH.md Pitfall P14):**
- File MUST be in the Xcode target's "Copy Bundle Resources" build phase, not just in the folder. Xcode Target Membership checkbox must be ON.
- CI MUST grep the built `.app` to verify the file landed (RESEARCH.md lines 602–609 show the bash check). Add this grep to `ci-simulator.yml` after the build step.

---

### `.swiftlint.yml`

**Role:** lint config with 4 custom rules (D-19, STACK-02).
**Analog:** `01-RESEARCH.md` §Pattern 9 lines 757–804.

**Copy verbatim from RESEARCH.md:**

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

**Pitfalls to avoid:**
- Rule 4 triggers zero Phase 1 violations (single-target build means `Features_X` are not modules) — this is future-proofing (RESEARCH.md line 806, Assumption A3). Include it now; do not delete.
- The raw-coordinate-literal rule is explicitly DEFERRED to Phase 3 (D-19 line 83 + Flag #1). Do NOT ship it in Phase 1.
- Validation (Success Criterion 2): plant a `print(...)` call in a test branch, run `swift run swiftlint --strict`, confirm exit code ≠ 0; remove the planted violation before merge.

---

### `.github/workflows/ci-simulator.yml`

**Role:** PR-gate CI (D-01, D-02).
**Analog:** `01-RESEARCH.md` §Pattern 4 lines 487–527.

**Copy verbatim from RESEARCH.md:**

```yaml
name: CI (Simulator)
on:
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.4.app
      - name: Install iOS 17 simulator runtime (if missing)
        run: |
          xcodebuild -downloadPlatform iOS -buildVersion 17.5 || true
      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
          key: spm-${{ hashFiles('Package.resolved') }}
      - name: SwiftLint
        run: swift run swiftlint --strict
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
```

**Add post-build PrivacyInfo grep (from RESEARCH.md lines 602–609):**

```yaml
      - name: Verify PrivacyInfo.xcprivacy in bundle
        run: |
          BUILD_DIR=$(xcodebuild -showBuildSettings | awk '/ CONFIGURATION_BUILD_DIR / {print $3}')
          APP_PATH="$BUILD_DIR/validationLedger.app"
          if [ ! -f "$APP_PATH/PrivacyInfo.xcprivacy" ]; then
            echo "ERROR: PrivacyInfo.xcprivacy missing from .app bundle. Add to Copy Bundle Resources."
            exit 1
          fi
```

**Pitfalls to avoid:**
- `xcode-select -s /Applications/Xcode_16.4.app` pins the CI floor (D-03 + Flag #2). Dev machine has 26.4; CI uses 16.4 for Swift Testing + iOS 17 SDK stability.
- `-only-testing:` flags are how D-03 exclusion of SE/biometric paths is enforced (RESEARCH.md line 524) — device tests are a separate target that isn't run here.
- macos-latest image Xcode version drifts (RESEARCH.md Tertiary source line 1509); verify at plan execution time.

---

### `.github/workflows/ci-device.yml`

**Role:** merge-to-main + security-path-PR gate on self-hosted runner (D-04/D-05/D-06).
**Analog:** `01-RESEARCH.md` §Pattern 4 device YAML lines 531–557.

**Copy verbatim from RESEARCH.md:**

```yaml
name: CI (Device)
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
    paths:
      - 'validationLedger/Core/Auth/**'
      - 'validationLedger/Core/KeyStore/**'
      - 'validationLedger/Core/Identity/**'
      - 'validationLedger/Core/Networking/CertificatePinning/**'
jobs:
  smoke:
    runs-on: [self-hosted, macOS, device]
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
```

**Pitfalls to avoid:**
- Self-hosted runner must have the `self-hosted`, `macOS`, `device` labels configured (Assumption A9). Registration steps are in `docs/ci.md`.
- `DEVICE_UDID` must be a GitHub Actions secret (not a literal in the file).
- Path filter is load-bearing for D-05(b) — do NOT broaden it; unrelated PRs should not trigger device CI.
- `Core/Identity/**` path doesn't exist in Phase 1 (Identity module is M2+) — harmless now; future-proofs the gate.

---

### `validationLedgerTests/Logging/PIIScrubberTests.swift`

**Role:** Swift Testing fixture for FOUND-01 redaction contract.
**Analog:** `01-RESEARCH.md` Example 2 lines 1075–1131.

**Copy verbatim from RESEARCH.md Example 2.** This is the acceptance test for PIIScrubber; the scrubber implementation must pass these assertions.

**Pitfalls to avoid:**
- Both paths (structured `scrub(fields:)` and string `scrubString(_:)`) are tested. Do not skip the string-path test — it's the bypass-resistance check (RESEARCH.md line 415).
- Parameterized test for MC/DOT uses `arguments:` — requires Swift Testing (not XCTest). Verify `@Test(arguments:)` syntax against current Xcode 16+ Swift Testing docs.

---

### `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift`

**Role:** device-only smoke (D-06).
**Analog:** `01-RESEARCH.md` §Pattern 4 lines 561–583.

**Copy verbatim from RESEARCH.md:**

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

**Pitfalls to avoid (RESEARCH.md Pitfall P8):**
- This target does NOT link into simulator CI (`-only-testing:` in ci-simulator.yml excludes it).
- If `SecureEnclave.isAvailable == false` on the connected iPhone, stop — check Xcode's device trust, provisioning, and that the device is a real iPhone (not iPad with no SE in some older models).

---

### `Package.swift`

**Role:** SwiftPM companion manifest pulling Nuke + SwiftLintPlugins into the single app target (STACK-01).
**Analog:** `01-RESEARCH.md` Installation block lines 188–211.

**Copy verbatim from RESEARCH.md.**

**Pitfalls to avoid:**
- Re-verify versions at plan-execution time — RESEARCH.md line 184 warns versions may have advanced since 2026-04-20.
- Do NOT add SDWebImage, Alamofire, KeychainAccess, XCoordinator, Sentry, Firebase, Amplitude, or Mixpanel (CLAUDE.md dependency allowlist + STACK-04 "zero crash/analytics SDK in M1").
- The `Package.swift` is a COMPANION to `.xcodeproj`, not a replacement (RESEARCH.md line 213). The `.xcodeproj` remains source-of-truth for target structure.

---

### `docs/adr/0001-mvvm-c-memory-conventions.md`

**Role:** ADR (FOUND-03).
**Analog:** `01-RESEARCH.md` Example 6 lines 1230–1266.

**Copy verbatim from RESEARCH.md.** This ADR is the canonical content for CLAUDE.md's eventual link target.

**Pitfalls to avoid (RESEARCH.md Pitfall P5):**
- All 6 rules in the decision section are load-bearing. Do not trim.
- Status `Accepted` on first commit — ADRs are immutable once accepted; corrections go in a new numbered ADR that supersedes this one (D-18 line 72).

---

### `docs/adr/0002-role-coordinator-swap-pattern.md`

**Role:** ADR (ARCH-06).
**Analog:** D-18 line 74 + `.planning/research/ARCHITECTURE.md` Amendment #3 (root-swap at SceneDelegate).

**NOVEL content — no verbatim sketch in RESEARCH.md.** Planner drafts using the structure of ADR 0001 (Context / Decision / Consequences / Related). Content must state:
- **Context:** Why role changes need full-tree reset (security-sensitive state isolation, RESEARCH.md line 867).
- **Decision:** `SceneDelegate.presentRoot(_:)` allocates a fresh `AppContainer` + `AppCoordinator` on every role change; previous coordinator tree deallocates via ARC.
- **Consequences:** Old services (loggers, stateless protocols, stub keystore) are cheap to recreate in Phase 1; flag for audit when services grow in Phase 2+ (RESEARCH.md line 751).
- **Related:** PITFALLS.md Anti-Pattern 4, ARCH-06, D-10.

---

### `docs/adr/0003-module-layout-and-target-strategy.md`

**Role:** ADR (D-15 re-evaluation trigger).
**Analog:** D-15 line 69 + D-18 line 75.

**NOVEL content.** Planner drafts:
- **Context:** Spec §3.2 allows per-Feature local SPM packages; research/SUMMARY.md says "no payoff on single-module M1."
- **Decision:** Single Xcode target with directory groups for Phase 1. ARCH-05 enforcement via SwiftLint rule 4, not SPM boundaries.
- **Consequences:** Cross-feature isolation is lint-enforced (weaker than compile-enforced); re-evaluate at M2 boundary OR when codebase crosses ~15 Features (deferred trigger, CONTEXT.md line 191).
- **Related:** ARCH-05, D-15, Assumption A3.

---

### `docs/ci.md`

**Role:** CI documentation (CI-04).
**Analog:** `01-RESEARCH.md` Example 4 lines 1157–1203.

**Copy verbatim from RESEARCH.md.** Add per Flag #2 (line 1449): explicit line that dev uses Xcode 26.4; CI pins 16.4; reason is Swift Testing + iOS 17 SDK stability.

---

### `docs/cert-rotation.md`

**Role:** skeleton only (FOUND-05 full runbook deferred to Phase 2, Flag #5).
**Analog:** `01-RESEARCH.md` Flag #5 line 1474.

**Content pattern:**

```markdown
# Cert Rotation Runbook

**Status:** STUB — full content ships in Phase 2 alongside SEC-01 cert pinning implementation.

## 30-Day Rotation Window (outline)

1. Backup pin is deployed alongside primary pin. Both are valid simultaneously.
2. When primary expiry approaches, rotate primary to the next-gen cert; backup remains as fallback.
3. Full step-by-step procedure + emergency-revoke path: Phase 2 deliverable.

## Related
- PITFALLS.md P3 (cert pinning without rotation plan = self-brick DoS)
- REQUIREMENTS.md FOUND-05, SEC-01
```

---

### `.git/hooks/pre-commit`

**Role:** git hook (STACK-02).
**Analog:** `01-RESEARCH.md` Example 5 lines 1209–1224.

**Copy verbatim from RESEARCH.md.** Also create `scripts/install-hooks.sh` to symlink the hook into `.git/hooks/` on clone (hooks aren't committed into `.git/` directly).

---

## Shared Patterns

### Authentication / Authorization
Not applicable in Phase 1 — no auth surfaces land until Phase 3. `SessionLockService` is a protocol + stub only.

### Error Handling
**Source:** Swift `throws` + typed errors (to be established per file).
**Apply to:** All `Core/` services that interact with OS APIs (KeychainStore, KeyStore impls, NetworkClient, DeepLinkRouter).
**Pattern:** Each module defines a typed error enum (`KeychainError`, `KeyStoreError`, etc.) conforming to `Error` + `Sendable`. Services `throw`; callers handle. No force-try (`try!`) outside test targets (`validationLedgerTests/*`, `validationLedgerDeviceTests/*` — RESEARCH.md line 762 `excluded:` shows tests skip SwiftLint).

**Pitfalls to avoid:**
- Do NOT use NSError pattern. Typed enums + associated values only.
- Errors surface to Logger via `logger.error(event:fields:)` — NOT via `logger.error(error.localizedDescription)` (string path would run through scrubber but loses structured metadata). Use `LogField.event` to name the failure class.

### Logging (single cross-cutting path)
**Source:** `Core/Logging/Logger` protocol (this phase).
**Apply to:** EVERY file outside `Core/Logging/` that emits to console or OSLog.
**Enforcement:** SwiftLint rules `ban_print` + `ban_direct_os_log` (D-19). The only legal `os_log(...)` in the codebase lives inside `Core/Logging/OSLogLoggerImpl.swift` and is permitted via `excluded: '.*/Core/Logging/.*'` in the rule definition.

### DI / Service Resolution
**Source:** `AppContainer` (this phase).
**Apply to:** Every VC and VM that needs a Core service.
**Pattern:** Services are passed via initializer. No `AppContainer.shared`. No `@Environment` injection (SwiftUI-only pattern; Phase 1 is UIKit).

**Pitfalls to avoid:**
- Do NOT store `container` directly on a VC — that leaks the whole graph into places that shouldn't see it (ARCH-05 spirit). Pass only the services the VC actually uses.

### PII Safety (data-protection cross-cutting)
**Source:** `PIIScrubber` (this phase) + SwiftLint `ban_userdefaults_tokens` rule (D-19).
**Apply to:** Every log emit (via Logger); every storage write of sensitive data (Keychain only — SwiftLint blocks UserDefaults writes matching `*token*`/`*key*`/`*session*`).

### DEBUG-only Code Gating
**Source:** `#if DEBUG` compile-out (D-13, RESEARCH.md line 62).
**Apply to:** Entire `App/DevMenu/` subtree + shake responder in SceneDelegate (RESEARCH.md lines 857–863).
**Verification:** Release build of `.app` grepped for DevMenu symbols returns empty (LOG-03 verification, RESEARCH.md line 1372).

---

## No Analog — Novel Patterns (Planner Must Invent)

These files have no prior art in the codebase AND no complete sketch in RESEARCH.md. The planner must design the implementation to match the stated contract.

| File | Contract Source | Why Novel |
|------|-----------------|-----------|
| `Core/Logging/PIIScrubber.swift` | RESEARCH.md §Pattern 1 rule table (lines 402–409) + Example 2 test fixture (lines 1075–1131) | D-16 hybrid Field-typed API has no prior art. Rule table defines BEHAVIOR; planner writes implementation to pass fixture tests. Structured path is a `[LogField: Any] → [LogField: Any]` transform where each field category applies its own redaction; string path is a regex sweep with WARN telemetry emit for unmatched name-like patterns. |
| `Core/Storage/Keychain/KeychainStore.swift` | RESEARCH.md Device Smoke Test lines 574–583 (API contract) + AppDelegate enumerate pattern (lines 451–466) | Apple's SecItem API is well-documented externally, but the hand-rolled `KeychainStore` class (set/get/delete/enumerate with typed `KeychainKey` + `KeychainAccessibility` enum) is specific to this codebase. Target size per STACK.md: ~150 LOC. |
| `docs/adr/0002-role-coordinator-swap-pattern.md` | `.planning/research/ARCHITECTURE.md` Amendment #3 + D-10 | No content template; structure borrows from ADR 0001. |
| `docs/adr/0003-module-layout-and-target-strategy.md` | D-15 + D-18 + Assumption A3 | No content template; structure borrows from ADR 0001. Must include re-evaluation trigger. |

**All four have clear contracts and constraints — novelty is in expressing them as code/prose, not in designing the behavior.**

---

## Metadata

**Analog search scope:**
- `.planning/phases/01-foundational-conventions-scaffolding/01-CONTEXT.md` (21 decisions D-01..D-21)
- `.planning/phases/01-foundational-conventions-scaffolding/01-RESEARCH.md` (10 Patterns + 6 Code Examples + YAML workflows)
- `.planning/codebase/{STRUCTURE,CONVENTIONS,STACK}.md` (confirmed empty baseline)
- `CLAUDE.md` (dependency allowlist + UIKit-first + iOS 17 + zero-PII constraints)

**External references cited:**
- Apple [UIApplicationDelegate](https://developer.apple.com/documentation/uikit/uiapplicationdelegate)
- Apple [UISceneDelegate](https://developer.apple.com/documentation/uikit/uiscenedelegate)
- Apple [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- Apple [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- Apple [SecItem](https://developer.apple.com/documentation/security/keychain_services/keychain_items)
- Apple [CryptoKit P256](https://developer.apple.com/documentation/cryptokit/p256)
- Apple [OSLogStore](https://developer.apple.com/documentation/oslog/oslogstore)
- [SwiftLint custom_rules](https://realm.github.io/SwiftLint/custom_rules.html)
- [ITMS-91053 Missing Privacy Manifest](https://blog.ni18.in/itms-91053-missing-api-declaration-privacy/)

**Files scanned:** 6 planning documents; 2 scaffold source files (pending deletion in ARCH-01).

**Pattern extraction date:** 2026-04-20

---

## PATTERN MAPPING COMPLETE

**Phase:** 1 — Foundational Conventions & Scaffolding
**Files classified:** 51 (47 new, 4 modified/deleted)
**Analogs found:** 47 external / 51 total

### Coverage
- Files with exact analog (research-sketched verbatim): **28**
- Files with role-match analog (API shown, body inferable): **15**
- Files with skeleton-only content: **4** (design tokens, Localizable.strings, cert-rotation stub, Features/ placeholders)
- Files with no analog (novel patterns): **4** (PIIScrubber, KeychainStore, ADR 0002, ADR 0003)

### Key Patterns Identified
- **Greenfield phase = external analogs only.** Every "analog" is either a RESEARCH.md Swift sketch (28 files) or an Apple/tool documentation URL (~15 files). Zero in-project analogs exist — this is by design; Phase 1 IS the codebase's convention-establishment phase.
- **RESEARCH.md pre-sketched 10 of the 10 structural patterns** (AppDelegate wipe, SceneDelegate swap, AppContainer DI, Logger protocol, PIIScrubber behavior, KeychainStore contract, SessionLockService stub, DeepLinkRouter queue, SwiftLint rules, CI workflows). The planner's job is to wire these sketches into action blocks, not to invent patterns.
- **4 novel patterns remain** — PIIScrubber implementation body, KeychainStore SecItem body, and 2 ADRs with no verbatim template. All have clear contracts (test fixtures or decision briefs); novelty is only in expression.
- **Cross-cutting enforcement = SwiftLint rules.** The 4 custom rules (D-19) are the mechanism that makes the conventions stick in every future phase — not a code analog but an enforcement analog.
- **30% infrastructure tax (Pitfall P20)** is concretized in this phase — ~600–900 LOC of hand-rolled infrastructure in `Core/` that the team owns forever.

### File Created
`/Users/beckmaldinVL/development/mobileApps/ValidationLedger/validationLedger/.planning/phases/01-foundational-conventions-scaffolding/01-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Planner can now inline RESEARCH.md excerpts directly into PLAN.md action blocks for 28 files, reference the API contract for 15 files, and invent bodies for 4 novel patterns using the test fixtures + decision briefs as acceptance criteria.
