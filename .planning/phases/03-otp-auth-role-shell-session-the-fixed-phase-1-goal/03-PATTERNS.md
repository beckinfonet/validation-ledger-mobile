# Phase 3: OTP Auth + Role Shell + Session — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 47 (15 NEW source + 12 MODIFIED source + 13 NEW tests + 1 MODIFIED test + 1 NEW fixture + 1 MODIFIED tooling + 4 docs/info-plist)
**Analogs found:** 38 / 47 — 9 establish baseline (no closely matching analog in Phase 1+2 code)

**Codebase scope summary (read-only audit):**
- 49 Swift source files in `validationLedger/`
- 18 Swift test files in `validationLedgerTests/`
- 1 UI test file (`validationLedgerUITests/RoleShellSmokeTests.swift`) — currently 5 placeholders to upgrade
- 14 JSON fixtures in `validationLedgerTests/Networking/Fixtures/`
- 4 SwiftLint custom rules in `.swiftlint.yml` (a 5th will be added)

---

## File Classification

### NEW source files (15)

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `Features/Onboarding/Auth/AuthCoordinator.swift` | Coordinator | event-driven (callback) | `Roles/RoleCoordinator.swift` (protocol) + `App/AppCoordinator.swift` (concrete pattern) | exact (role) / partial (concrete VC owner) |
| `Features/Onboarding/Auth/PhoneEntryViewController.swift` | ViewController (UIKit) | request-response | `App/DevMenu/NetworkConfigToggleViewController.swift` | role-match (programmatic UIKit VC + UIStackView + Auto Layout) |
| `Features/Onboarding/Auth/PhoneEntryViewModel.swift` | ViewModel | request-response | NO ANALOG — establish baseline | none (Phase 1+2 has zero ViewModel files) |
| `Features/Onboarding/Auth/OTPViewController.swift` | ViewController (UIKit) | request-response | `App/DevMenu/NetworkConfigToggleViewController.swift` | role-match |
| `Features/Onboarding/Auth/OTPViewModel.swift` | ViewModel | request-response (+ Timer countdown) | NO ANALOG — establish baseline | none |
| `Features/Onboarding/Auth/BiometricLockViewController.swift` | ViewController (UIKit, full-screen modal) | event-driven | `App/DevMenu/NetworkConfigToggleViewController.swift` | role-match (programmatic VC); modal-overlay pattern is new |
| `Features/Onboarding/Auth/NotAvailableInRegionViewController.swift` | ViewController (UIKit) | terminal/static | `App/DevMenu/NetworkConfigToggleViewController.swift` | role-match (text + buttons) |
| `Features/Onboarding/Auth/AnotherActiveSessionViewController.swift` | ViewController (UIKit) | terminal/static | `App/DevMenu/NetworkConfigToggleViewController.swift` | role-match |
| `Features/Profile/ProfileViewController.swift` | ViewController (UIKit, modal) | event-driven (logout tap) | `App/DevMenu/RoleSwitcherViewController.swift` | role-match (modal table-style + injected onSelect closure) |
| `Core/Auth/SessionRestoreService.swift` | Service | request-response | `Core/Auth/SessionLockService.swift` | exact (Foundation-only protocol + impl + initializer-DI) |
| `Core/Auth/BiometricService.swift` | Service | event-driven (LAContext callback) | `Core/Auth/SessionLockService.swift` | role-match (protocol shape); LAContext is new |
| `Core/Auth/SensitiveActionService.swift` | Service | request-response (sign payload) | `Core/Auth/SessionLockService.swift` | role-match |
| `Core/Auth/LogoutService.swift` | Service | event-driven (notification publisher) | `Core/Auth/SessionLockService.swift` | role-match |
| `Core/Identity/PlatformPayloadField.swift` | Type (enum) | transform | `Core/Logging/Logger.swift` `LogField` enum | exact (disjoint-type-family discipline) |
| `Core/Identity/Geo/LocationProvider.swift` | Service (CLLocationManager async wrapper) | request-response | `Core/Identity/DeviceFingerprint.swift` | role-match (Identity/ subsystem service with DI factory) |
| `Core/Identity/Geo/CountryGate.swift` | Service (CLGeocoder wrapper) | transform | `Core/Identity/DeviceFingerprint.swift` | role-match |
| `Core/Networking/Interceptors/Auth401ResponseInterceptor.swift` | Interceptor | request-response wrap | `Core/Networking/Interceptors/RetryInterceptor.swift` | exact |
| `Core/Storage/Keychain/KeychainScope.swift` | Type (enum) | transform | `Core/Storage/Keychain/KeychainAccessibility.swift` | exact |

### MODIFIED source files (12)

| File | Role | Modification | Closest Analog (for the change) | Match Quality |
|------|------|--------------|---------------------------------|---------------|
| `App/SceneDelegate.swift` | Lifecycle | add probe → presentRoot; add `.sessionDidInvalidate` observer; route `.anotherActiveSession` | self (existing `.devMenuNetworkConfigRequested` observer pattern, lines 39–56) | exact |
| `App/AppCoordinator.swift` | Coordinator | fill `case .auth` and `case .anotherActiveSession` in `makeRoot(for:)` | self (existing `case .role(let role)` branch, lines 52–53) | exact |
| `App/AppContainer.swift` | Composition root | construct 4 new services; wire `Auth401ResponseInterceptor` into `responseInterceptors` | self (existing `IdempotencyInterceptor` + `RetryInterceptor` wiring, lines 100–105) | exact |
| `Core/Auth/SessionLockService.swift` | Service | extend `protocol` with `lockState(now:)`; add `LockState` + `LockReason` enums; self-subscribe to `UIApplication` notifications in `init`; remove Foundation-only constraint (add `import UIKit`) | self (existing protocol shape lines 4–15) | exact (extension of own pattern) |
| `Core/KeyStore/SecureEnclaveKeyStore.swift` | KeyStore | CR-02: idempotent guard at top of `generateKey(slot:)`; signature already DER (`.ecdsaSignatureMessageX962SHA256`, line 137) — IN-02 reference impl | self (existing `generateKey(slot:)` lines 71–102) | exact |
| `Core/KeyStore/SoftwareKeyStore.swift` | KeyStore | IN-02: change `signature.rawRepresentation` → `signature.derRepresentation` in `sign(_:)` (line 20) and `signWithAuthorization(_:)` (line 39) | `Core/KeyStore/SecureEnclaveKeyStore.swift` (signs with `.ecdsaSignatureMessageX962SHA256`, lines 135–143 — DER X9.62 native) | exact |
| `Core/KeyStore/KeyStoreProtocol.swift` | Protocol | add `func deleteKey(slot:) throws` | self (existing protocol lines 20–35) | exact |
| `Core/Networking/APIClient.swift` | NetworkClient | parse 429 + Retry-After → `NetworkError.rateLimited(retryAfter:)`; insert detection between line 53 (after wrapped send) and line 54 (status guard) | self (existing 200…299 guard, lines 54–56) | exact |
| `Core/Networking/NetworkError.swift` | Type (enum) | add `case rateLimited(retryAfter: TimeInterval)` | self (existing cases lines 8–23) | exact |
| `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` | Endpoint | IN-01: add `private enum CodingKeys` to `RequestBody` covering `otpSessionID = "otpSessionId"` | self (existing `Response.CodingKeys`, lines 22–26) | exact (already on the Response side) |
| `Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` | Endpoint | IN-05: add `private enum CodingKeys` to `DeviceFingerprintPayload` covering `installUUID = "installUuid"` | `Core/Networking/Endpoints/OTPRequestEndpoint.swift` `Response.CodingKeys` (lines 26–29) | exact |
| `Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` | Endpoint | IN-05: add `CodingKeys` to `RequestBody` for `uploadID = "uploadId"` | `Core/Networking/Endpoints/OTPRequestEndpoint.swift` (lines 26–29) | exact |
| `Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` | Endpoint | IN-05: add `CodingKeys` to `RequestBody` for `uploadID = "uploadId"` | self (already has `Response.CodingKeys` lines 19–22) | exact |
| `Core/Storage/Keychain/KeychainStore.swift` | Storage | add `func deleteAll(under: KeychainScope) throws` | self (existing `enumerateAll()` lines 65–85 + `delete(_:)` lines 56–63) | exact (compose existing methods) |
| `Core/Storage/Keychain/KeychainKey.swift` | Type | add `.sessionRole`, `.sessionUserID`, `.biometricDomainState` | self (existing `.sessionToken`, `.installUUID` lines 10–11) | exact |
| `Roles/Shipper/ShipperTabBarController.swift` (× 5 sibling files) | Tab bar | wrap each tab's UIViewController in a `UINavigationController`; install avatar `UINavigationItem.rightBarButtonItem` per tab; tap presents modal `ProfileViewController` | self (existing `viewDidLoad()` lines 10–18 + `makeTab(...)` lines 23–33) | exact (extend own static helper) |
| `Roles/RoleCoordinator.swift` | Protocol | optionally add an extension/helper `installAvatarBarButton(target:action:)` shared across the 5 tab bars | self (existing minimal protocol, 17 lines) | exact (additive extension) |
| `App/DevMenu/RoleSwitcherViewController.swift` | DevMenu VC | (no changes — the `-MockOTPRoleForUITest` launchArg D-32 reuses the existing `-ForceRoleForUITest` machinery in `SceneDelegate`, lines 61–71) | n/a | n/a |

### NEW test files (12) + MODIFIED (1)

| File | Role | Closest Analog | Match Quality |
|------|------|----------------|---------------|
| `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` | Test (XCTest/Swift Testing) | `validationLedgerTests/Auth/SessionLockServiceTests.swift` | exact |
| `validationLedgerTests/Auth/LogoutServiceTests.swift` | Test | `validationLedgerTests/Auth/SessionLockServiceTests.swift` | exact |
| `validationLedgerTests/Auth/BiometricServiceTests.swift` | Test | `validationLedgerTests/Auth/SessionLockServiceTests.swift` | exact |
| `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` | Test (constructibility-only per D-12) | `validationLedgerTests/Auth/SessionLockServiceTests.swift` | role-match |
| `validationLedgerTests/Auth/SessionLockServiceTests.swift` (MODIFY) | Test | self (existing 4 @Test methods) | exact |
| `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` | Test | `validationLedgerTests/Networking/RetryInterceptorTests.swift` | exact |
| `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` | Test (compile-shape assertion) | `validationLedgerTests/Logging/PIIScrubberTests.swift` (LogField cases coverage — already wired through PIIScrubberTests indirectly) | role-match |
| `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` | Test (mock CLLocationManager via injectable protocol) | `validationLedgerTests/Identity/DeviceFingerprintTests.swift` | role-match |
| `validationLedgerTests/Identity/Geo/CountryGateTests.swift` | Test (injected geocoder protocol) | `validationLedgerTests/Identity/DeviceFingerprintTests.swift` | role-match |
| `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` | Test (ViewModel) | NO ANALOG — first ViewModel test | none |
| `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` | Test (ViewModel + Timer) | NO ANALOG — first ViewModel test | none |
| `validationLedgerUITests/RoleShellSmokeTests.swift` (MODIFY — D-32) | UI test (XCUITest) | self (5 placeholders, lines 18–66) | exact (extend each test with OTP fixture drive + logout assert) |
| `validationLedgerDeviceTests/BiometricSESmokeTests.swift` | Device test (HUMAN-UAT for SC-2/SC-3) | `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` | exact |
| `validationLedgerDeviceTests/EvaluatedPolicyDomainStateTests.swift` | Device test (HUMAN-UAT for SESS-03) | `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` | role-match |

### NEW fixture (1) + MODIFIED tooling (1) + Resources (1)

| File | Role | Closest Analog | Match Quality |
|------|------|----------------|---------------|
| `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` | Fixture | `validationLedgerTests/Networking/Fixtures/otp-verify-failure.json` | exact |
| `.swiftlint.yml` (MODIFY) | Tooling | self (existing 4 custom rules lines 62–98) | exact |
| `validationLedger/Resources/Info.plist` (MODIFY) | Resource (XML plist) | NO ANALOG — first NS*UsageDescription added | establish baseline (Apple-documented key) |

---

## Pattern Assignments — Source Files

### `Features/Onboarding/Auth/AuthCoordinator.swift` (Coordinator, event-driven)

**Primary analog:** `validationLedger/Roles/RoleCoordinator.swift` (protocol shape) + `validationLedger/App/AppCoordinator.swift` (concrete coordinator pattern with callbacks)

**Pattern: minimal coordinator protocol surface** (`Roles/RoleCoordinator.swift:12-16`)
```swift
public protocol RoleCoordinator: AnyObject {
    var role: Role { get }
    /// The root view controller installed as window.rootViewController.
    var rootViewController: UIViewController { get }
}
```

**Pattern: callback-based event escalation** (`App/AppCoordinator.swift:14-19`)
```swift
let container: AppContainer
private let phase: AppPhase
let rootViewController: UIViewController

// Callbacks (Plan 07 / Phase 3 wires real trigger points):
var onRoleResolved: ((Role) -> Void)?
var onLogout: (() -> Void)?
```

**Pattern: factory init that owns its UIViewController** (`App/AppCoordinator.swift:20-25`)
```swift
init(container: AppContainer, phase: AppPhase) {
    self.container = container
    self.phase = phase
    self.rootViewController = Self.makeRoot(for: phase)
    container.logger.info(event: .init("app_coordinator_init"), fields: [.event: Self.phaseDescription(phase)])
}
```

**Apply to AuthCoordinator:**
- Hold a `UINavigationController` as `rootViewController`
- Construct `PhoneEntryViewModel` + `PhoneEntryViewController` in `init(container:)`
- Expose `var onAuthenticated: ((Role) -> Void)?`
- Bubble verify-success up to `AppCoordinator.onRoleResolved` (which already exists per `SceneDelegate.swift:125-127`)

---

### `Features/Onboarding/Auth/PhoneEntryViewController.swift` & sibling UIKit VCs (ViewController, request-response)

**Primary analog:** `validationLedger/App/DevMenu/NetworkConfigToggleViewController.swift`

**Pattern: programmatic UIKit VC + UIStackView + Auto Layout** (`NetworkConfigToggleViewController.swift:28-62`)
```swift
final class NetworkConfigToggleViewController: UIViewController {

    private let stack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 16
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Network Config"
        view.backgroundColor = .systemBackground

        let currentLabel = UILabel()
        currentLabel.numberOfLines = 0
        // ... compose label + buttons …

        stack.addArrangedSubview(currentLabel)
        stack.addArrangedSubview(mockButton)
        stack.addArrangedSubview(liveButton)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }
```

**Pattern: button factory + @objc selector** (`NetworkConfigToggleViewController.swift:64-71`)
```swift
private func makeButton(title: String, action: Selector) -> UIButton {
    let b = UIButton(type: .system)
    var cfg = UIButton.Configuration.bordered()
    cfg.title = title
    b.configuration = cfg
    b.addTarget(self, action: action, for: .touchUpInside)
    return b
}
```

**Pattern: alert-on-error** (`NetworkConfigToggleViewController.swift:97-105`)
```swift
let alert = UIAlertController(
    title: "Cannot switch to live",
    message: "...",
    preferredStyle: .alert
)
alert.addAction(UIAlertAction(title: "OK", style: .default))
present(alert, animated: true)
```

**Apply to all 5 NEW UIKit VCs:**
- `PhoneEntryViewController` — UITextField (phonePad) + UIButton in a UIStackView
- `OTPViewController` — UITextField (numberPad, 6 digits) + UIButton + UILabel for countdown
- `BiometricLockViewController` — UIImageView (logo) + UILabel (reason copy) + UIButton (Unlock)
- `NotAvailableInRegionViewController` — UILabel (copy) + UIButton (Try again)
- `AnotherActiveSessionViewController` — UILabel + UIButton (Contact support → mailto:)

**Pattern: initializer-DI VM injection** (`App/DevMenu/RoleSwitcherViewController.swift:9-16`)
```swift
final class RoleSwitcherViewController: UITableViewController {
    private let onSelect: (Role) -> Void

    init(onSelect: @escaping (Role) -> Void) {
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
```

Apply to all 5 VCs — inject `viewModel:` (or `onSelect:` for terminal screens) at init.

---

### `Features/Onboarding/Auth/PhoneEntryViewModel.swift` & `OTPViewModel.swift` (ViewModel)

**NO ANALOG — establish baseline.** Phase 1+2 ship zero ViewModel files (the only state holders are Coordinators + Services).

**Recommended scaffold** (per RESEARCH.md §Architecture Patterns "MVVM + Coordinators"):
- Use `final class` (not struct — must be reference for VC weak-binding)
- `@MainActor` isolation (RESEARCH D-31)
- Initializer-DI per ARCH-04 (no `.shared`)
- Combine-style `@Published` properties OR plain closures (`var onStateChange: ((State) -> Void)?`) — planner picks based on iOS-17 Observation framework availability vs project's stated UIKit-first stance
- For OTPViewModel: hold a `Timer?` for the Retry-After countdown; invalidate in deinit

**Closest secondary reference:** `Core/Auth/SessionLockService.swift` — the `lock` + `lastSuccess` mutable-state pattern (lines 18–40) is the closest existing example of stateful service-style logic:
```swift
public final class DefaultSessionLockService: SessionLockService, @unchecked Sendable {
    private var lastSuccess: Date?
    private let backgroundGrace: TimeInterval = 5 * 60
    private let lock = NSLock()
```

---

### `Core/Auth/SessionRestoreService.swift`, `BiometricService.swift`, `SensitiveActionService.swift`, `LogoutService.swift` (Service)

**Primary analog:** `validationLedger/Core/Auth/SessionLockService.swift` (entire file, 41 lines)

**Pattern: protocol + Default impl + initializer-DI** (`SessionLockService.swift:4-40`)
```swift
public protocol SessionLockService: AnyObject, Sendable {
    /// True if the app MUST show a biometric prompt before revealing content.
    func shouldRequireBiometric(now: Date) -> Bool

    /// Record a successful biometric. Called from Phase 3 biometric service.
    func recordBiometricSuccess(at: Date)

    /// Clear the stored timestamp (e.g., on logout).
    func invalidate()
}

public final class DefaultSessionLockService: SessionLockService, @unchecked Sendable {
    private var lastSuccess: Date?
    private let backgroundGrace: TimeInterval = 5 * 60
    private let lock = NSLock()

    public init() {}

    public func shouldRequireBiometric(now: Date) -> Bool { ... }
    public func recordBiometricSuccess(at date: Date) { ... }
    public func invalidate() { ... }
}
```

**Apply to each new service:**

| New Service | Protocol Methods | Dependencies (init) |
|-------------|------------------|---------------------|
| `SessionRestoreService` | `func probe() -> SessionRestoreResult` | `keychainStore: KeychainStore`, `logger: any Logger` |
| `BiometricService` | `func evaluate(reason: String, fallback: BiometricFallback) async throws` | (none — wraps `LAContext`) |
| `SensitiveActionService` | `func authorize(_ payload: Data, reason: String) async throws -> Signature` | `biometricService:`, `keyStore: any KeyStoreProtocol`, `logger:` |
| `LogoutService` | `func logout(reason: LogoutReason) async` | `keychainStore:`, `keyStore:`, `sessionLock: any SessionLockService`, `notificationCenter: NotificationCenter`, `logger:` |

**Pattern: `LogoutService` 6-step orchestration is fully spec'd in CONTEXT D-16** — planner should reference `Core/Storage/Keychain/KeychainStore.swift:56-63` (existing `delete(_:)` for the new `deleteAll(under:)` extension) and `Core/KeyStore/KeyStoreProtocol.swift:20-35` (for the new `deleteKey(slot:)` method to add).

**Pattern: thread-safe mutable state** (`SessionLockService.swift:21,25-29`) — the `NSLock` + `lock.lock(); defer { lock.unlock() }` idiom for any service that mutates state from arbitrary callers.

---

### `Core/Auth/SessionLockService.swift` (MODIFY — extend, don't replace)

**Primary analog:** self (the existing 41-line file).

**Existing protocol** (lines 4–15) — keep `shouldRequireBiometric` as convenience wrapper or remove (planner decides per D-07):
```swift
public protocol SessionLockService: AnyObject, Sendable {
    func shouldRequireBiometric(now: Date) -> Bool
    func recordBiometricSuccess(at: Date)
    func invalidate()
}
```

**Phase 3 extensions per D-07/D-08/D-09:**
- Add `func lockState(now: Date) -> LockState`
- Add `enum LockState { case unlocked; case locked(reason: LockReason) }`
- Add `enum LockReason { case coldBoot, backgroundTimeout, biometricReEnrolled, neverUnlocked }`
- Self-subscribe to `UIApplication.didEnterBackgroundNotification` + `didBecomeActiveNotification` in `init(notificationCenter: NotificationCenter = .default)` — store observer tokens, remove in `deinit`
- Add `import UIKit` (currently Foundation-only — see file line 2)

**Observer pattern reference:** `App/SceneDelegate.swift:42-55`
```swift
networkConfigObserver = NotificationCenter.default.addObserver(
    forName: .devMenuNetworkConfigRequested,
    object: nil,
    queue: .main
) { [weak self] note in
    guard let self,
          let config = note.userInfo?[DevMenuNetworkConfigKey.config] as? NetworkConfig else {
        return
    }
    self.currentNetworkConfigOverride = config
    self.presentRoot(.role(.shipper))
}
```

…and the matching `deinit` cleanup (`SceneDelegate.swift:95-101`):
```swift
deinit {
    #if DEBUG
    if let token = networkConfigObserver {
        NotificationCenter.default.removeObserver(token)
    }
    #endif
}
```

---

### `Core/Identity/PlatformPayloadField.swift` (Type, transform — GEO-03)

**Primary analog:** `validationLedger/Core/Logging/Logger.swift` `LogField` enum (lines 6–17)

**Pattern: phantom-typed enum disjoint family** (`Logger.swift:6-17`)
```swift
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
```

**Apply to `PlatformPayloadField`:**
- `case coordinate(CLLocationCoordinate2D)` — associated value carries CLLocationCoordinate2D
- `case timestamp(Date)`
- `case phoneE164(String)`
- Anyone calling `Logger.log(_:event:fields:)` cannot pass `PlatformPayloadField` — wrong type → compile error

**D-23 critical action — REMOVE the existing `.coordinates` case** from `LogField` (Logger.swift line 13) AND the corresponding handling in `PIIScrubber.scrub` (`PIIScrubber.swift:30-31` `case .coordinates: continue`). After Phase 3, no `LogField.coordinates` case exists — analytics + logger APIs cannot accept coordinates by construction.

**Note: there is currently NO `AnalyticsField` type in the codebase** (verified by grep — only `LogField` exists). RESEARCH D-23 mentions both as "existing — verify by code grep"; the planner should treat `AnalyticsField` creation as out-of-scope or deferred unless Phase 3 explicitly adds an analytics subsystem (it does not per the Recommended File Layout). The compile-time invariant relies solely on `LogField` having no coordinate case.

---

### `Core/Identity/Geo/LocationProvider.swift` & `CountryGate.swift` (Service)

**Primary analog:** `validationLedger/Core/Identity/DeviceFingerprint.swift` (lines 23–43)

**Pattern: Identity-subsystem service with factory** (`DeviceFingerprint.swift:23-43`)
```swift
public struct DeviceFingerprint: Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String

    public init(model: String, iosVersion: String, installUUID: String) {
        self.model = model
        self.iosVersion = iosVersion
        self.installUUID = installUUID
    }

    /// Factory: read or generate the installUUID via the supplied KeychainStore.
    /// The model + iOS version are always fresh from UIDevice/utsname.
    public static func current(keychain: KeychainStore) throws -> DeviceFingerprint { ... }
```

**Apply to LocationProvider:**
- Define a `protocol LocationProvider` returning `func currentLocation() async throws -> CLLocation`
- Default impl wraps `CLLocationManager` via `withCheckedThrowingContinuation` (see RESEARCH §Pattern 2, lines 469–567)
- Inject the protocol (not the concrete) into `PhoneEntryViewModel` — testable seam

**Apply to CountryGate:**
- Define `protocol CountryGate` with `func resolveCountry(for: CLLocation) async throws -> String?`
- Default impl wraps `CLGeocoder.reverseGeocodeLocation` returning `placemark.isoCountryCode`
- Inject into `PhoneEntryViewModel`

---

### `Core/Networking/Interceptors/Auth401ResponseInterceptor.swift` (Interceptor, request-response wrap)

**Primary analog:** `validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift` (entire file)

**Pattern: ResponseInterceptor protocol shape** (`RequestInterceptor.swift:16-21`)
```swift
public protocol ResponseInterceptor: Sendable {
    func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}
```

**Pattern: dependency-injected interceptor with `init`** (`RetryInterceptor.swift:19-31`)
```swift
public struct RetryInterceptor: ResponseInterceptor {
    private let maxRetries: Int
    private let baseDelayMs: UInt64
    private let ceilingMs: UInt64

    public init(maxRetries: Int = 3, baseDelayMs: UInt64 = 500, ceilingMs: UInt64 = 4_000) {
        precondition(maxRetries >= 0, "maxRetries must be non-negative")
        // …
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        // path-based gating — RetryInterceptor uses method:
        guard request.httpMethod == "GET" else {
            return try await send(request)
        }
        // …
    }
```

**Apply to Auth401ResponseInterceptor:**
```swift
public struct Auth401ResponseInterceptor: ResponseInterceptor {
    private let logoutService: any LogoutService          // injected
    private let excludedPaths: Set<String>                // ["/auth/otp/request", "/auth/otp/verify"] per D-28

    public init(logoutService: any LogoutService,
                excludedPaths: Set<String> = ["/auth/otp/request", "/auth/otp/verify"]) {
        self.logoutService = logoutService
        self.excludedPaths = excludedPaths
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await send(request)
        if response.statusCode == 401,
           let path = request.url?.path,
           !excludedPaths.contains(path) {
            await logoutService.logout(reason: .auth401)
        }
        return (data, response)
    }
}
```

**Wiring into APIClient** (`AppContainer.swift:100-105` — extend the existing array):
```swift
self.apiClient = APIClient(
    baseURL: apiBaseURL,
    networkClient: networkClient,
    requestInterceptors: [IdempotencyInterceptor()],
    responseInterceptors: [RetryInterceptor()]   // ← Phase 3: append Auth401ResponseInterceptor(logoutService: …)
)
```

---

### `Core/Networking/APIClient.swift` (MODIFY — 429 + Retry-After)

**Primary analog:** self (existing status guard, lines 53–56).

**Existing pattern** (`APIClient.swift:53-61`):
```swift
let (data, response) = try await wrapped(req)
guard (200...299).contains(response.statusCode) else {
    throw NetworkError.httpError(statusCode: response.statusCode, data: data)
}
do {
    return try decoder.decode(E.Response.self, from: data)
} catch {
    throw NetworkError.decodingFailed(error)
}
```

**Phase 3 modification — insert 429 detection BEFORE the generic httpError throw:**
```swift
let (data, response) = try await wrapped(req)
if response.statusCode == 429 {
    let retryAfter = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
    throw NetworkError.rateLimited(retryAfter: retryAfter)
}
guard (200...299).contains(response.statusCode) else {
    throw NetworkError.httpError(statusCode: response.statusCode, data: data)
}
```

**`NetworkError.swift` modification** — add to existing enum (lines 8–23):
```swift
case rateLimited(retryAfter: TimeInterval)
```

---

### `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` IN-01 fix

**Primary analog:** self — the `Response.CodingKeys` already exists (lines 22–26). Apply the same pattern to `RequestBody`.

**Existing Response pattern** (`OTPVerifyEndpoint.swift:20-26`):
```swift
// Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
// Raw values are camelCase (post-.convertFromSnakeCase form).
private enum CodingKeys: String, CodingKey {
    case sessionToken
    case role
    case userID = "userId"
}
```

**Apply to RequestBody (Phase 3 IN-01 fix)** — RequestBody currently has no CodingKeys (lines 11–14):
```swift
public struct RequestBody: Encodable, Sendable {
    public let otpSessionID: String
    public let code: String

    // Phase 3 IN-01 fix: convertToSnakeCase mangles "otpSessionID" → "otp_session_i_d"
    // Same camelCase-bridge rationale as Response.CodingKeys above.
    private enum CodingKeys: String, CodingKey {
        case otpSessionID = "otpSessionId"
        case code
    }
}
```

**Reference to canonical comment:** `OTPRequestEndpoint.swift:20-29` is the in-tree gold-standard explanation:
```swift
// Explicit CodingKeys: `.convertFromSnakeCase` maps "otp_session_id" -> "otpSessionId"
// (lowercase 'd'), but the property is `otpSessionID` (uppercase). With
// `.convertFromSnakeCase` enabled, the decoder converts JSON keys to camelCase BEFORE
// matching against CodingKeys — so CodingKeys raw values must be the camelCase form
// (e.g., "otpSessionId"), not the original snake_case. Acronyms in property names are a
// known JSONDecoder strategy limitation — this bridges the gap.
```

(Note: encoder uses `.convertToSnakeCase` per `APIClient.swift:86` — the encoding-side mangle for acronyms is what IN-01 fixes; decoder side is symmetric.)

---

### `Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` IN-05 fix

**Primary analog:** self (`Response.CodingKeys` lines 32–35) + `OTPRequestEndpoint.swift:26-29`.

**Existing fingerprint payload** (`DeviceRegisterEndpoint.swift:12-21`) — needs a new CodingKeys:
```swift
public struct DeviceFingerprintPayload: Encodable, Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String  // ← acronym-tail; needs CodingKeys
    public init(model: String, iosVersion: String, installUUID: String) { ... }
}
```

**Apply Phase 3 IN-05 fix:**
```swift
public struct DeviceFingerprintPayload: Encodable, Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String
    public init(model: String, iosVersion: String, installUUID: String) { ... }

    private enum CodingKeys: String, CodingKey {
        case model
        case iosVersion
        case installUUID = "installUuid"
    }
}
```

---

### `Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` and `KYCUploadCommitEndpoint.swift` IN-05 fixes

**Primary analog:** `OTPRequestEndpoint.swift:26-29` (and `KYCUploadCommitEndpoint.swift:19-22` already does this on the Response side — copy that pattern to RequestBody).

**KYCUploadChunkEndpoint RequestBody** (`KYCUploadChunkEndpoint.swift:11-16`) — currently no CodingKeys:
```swift
public struct RequestBody: Encodable, Sendable {
    public let uploadID: String        // ← acronym-tail
    public let chunkIndex: Int
    public let chunkData: String
    public let chunkSha256: String
}
```

**Phase 3 fix:**
```swift
private enum CodingKeys: String, CodingKey {
    case uploadID = "uploadId"
    case chunkIndex
    case chunkData
    case chunkSha256
}
```

**KYCUploadCommitEndpoint RequestBody** (`KYCUploadCommitEndpoint.swift:10-12`):
```swift
public struct RequestBody: Encodable, Sendable {
    public let uploadID: String
}
```

**Phase 3 fix:**
```swift
private enum CodingKeys: String, CodingKey {
    case uploadID = "uploadId"
}
```

---

### `Core/KeyStore/SecureEnclaveKeyStore.swift` CR-02 idempotent guard fix

**Primary analog:** self (the existing `generateKey(slot:)` body, lines 71–102).

**Existing function** (`SecureEnclaveKeyStore.swift:71-102`):
```swift
private func generateKey(slot: Keyslot) throws -> Data {
    var acError: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        slot.accessControlFlags,
        &acError
    ) else {
        throw KeyStoreError.keyGenerationFailed(acError?.takeRetainedValue())
    }
    // …
    var genError: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &genError) else {
        throw KeyStoreError.keyGenerationFailed(genError?.takeRetainedValue())
    }
    // …
}
```

**Phase 3 CR-02 fix — add idempotent guard at the very top:**
```swift
private func generateKey(slot: Keyslot) throws -> Data {
    // CR-02: idempotent guard. If a key already exists for this slot, return its
    // public representation instead of inserting a second key. Without this, a
    // second call silently inserts a new key alongside the old one and
    // loadPrivateKey may return either — breaking pub/priv match.
    if let existingPub = try? loadPublicKey(slot: slot) {
        return existingPub
    }
    // ... existing body unchanged from line 72 ...
}
```

(The existing `loadPublicKey(slot:)` at lines 123–130 throws on missing key — the `try?` converts to nil-on-missing, which is exactly the contract needed.)

---

### `Core/KeyStore/SoftwareKeyStore.swift` IN-02 DER unification

**Primary analog:** `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` (the device-side reference, lines 132–144) — uses `.ecdsaSignatureMessageX962SHA256` which IS DER X9.62 native.

**Existing SoftwareKeyStore.sign** (`SoftwareKeyStore.swift:18-21`):
```swift
func sign(_ data: Data) throws -> Data {
    let signature = try devicePrivateKey.signature(for: data)
    return signature.rawRepresentation        // ← 64-byte compact (NOT DER); IN-02 fix changes this
}
```

**Phase 3 IN-02 fix:**
```swift
func sign(_ data: Data) throws -> Data {
    let signature = try devicePrivateKey.signature(for: data)
    return signature.derRepresentation        // ← DER X9.62 — matches SE wire format
}
```

**Apply same fix to `signWithAuthorization(_:)` (line 36–40):**
```swift
func signWithAuthorization(_ data: Data) throws -> Data {
    let signature = try authPrivateKey.signature(for: data)
    return signature.derRepresentation        // ← DER X9.62
}
```

**Reference for SE-side DER format** (`SecureEnclaveKeyStore.swift:135-143`):
```swift
guard let signature = SecKeyCreateSignature(
    privateKey,
    .ecdsaSignatureMessageX962SHA256,         // ← X9.62 = DER-encoded — backend sees this
    data as CFData,
    &error
) as Data? else {
    throw KeyStoreError.signingFailed
}
return signature
```

---

### `Core/KeyStore/KeyStoreProtocol.swift` (MODIFY — add deleteKey)

**Primary analog:** self — the existing protocol (lines 20–35).

**Add a 5th method** (insert after line 34 `signWithAuthorization`):
```swift
/// Phase 3 SESS-04 / D-16: delete the key in the given slot.
/// Used by LogoutService to clear the SE authorizationKey on logout (deviceKey is
/// preserved across logout — it's device identity, not session-bound).
func deleteKey(slot: Keyslot) throws
```

**Implementation hint for SecureEnclaveKeyStore** — `SecItemDelete` against the same query shape as `loadPrivateKey` (`SecureEnclaveKeyStore.swift:104-121`).

**Implementation hint for SoftwareKeyStore** — no-op (or zero out the in-memory key) since simulator software keys live for process lifetime only.

---

### `Core/Storage/Keychain/KeychainStore.swift` (MODIFY — add deleteAll(under:))

**Primary analog:** self — compose existing `enumerateAll()` (lines 65–85) + `delete(_:)` (lines 56–63).

**Existing enumerate** (`KeychainStore.swift:65-85`):
```swift
public func enumerateAll() throws -> [(KeychainKey, Data)] {
    var query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecReturnAttributes: true,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitAll,
    ]
    if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
    // …
}
```

**Existing delete** (`KeychainStore.swift:56-63`):
```swift
public func delete(_ key: KeychainKey) throws {
    let query = baseQuery(for: key)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.unexpectedStatus(status)
    }
}
```

**Phase 3 `deleteAll(under:)` — compose both, gated by KeychainScope** (RESEARCH Code Examples lines 1658+):
```swift
public func deleteAll(under scope: KeychainScope) throws {
    let allItems = try enumerateAll()
    for (key, _) in allItems where scope.contains(key) {
        try delete(key)
    }
}
```

**`KeychainScope.swift` (NEW)** — analog: `KeychainAccessibility.swift` (lines 5–19):
```swift
public enum KeychainScope: Sendable {
    case session

    func contains(_ key: KeychainKey) -> Bool {
        switch self {
        case .session:
            return [.sessionToken, .sessionRole, .sessionUserID, .biometricDomainState].contains(key)
        }
    }
}
```

---

### `Core/Storage/Keychain/KeychainKey.swift` (MODIFY — add 3 keys)

**Primary analog:** self — existing static keys (lines 10–11).

**Existing pattern:**
```swift
public static let sessionToken = KeychainKey(rawValue: "session.token")
public static let installUUID  = KeychainKey(rawValue: "install.uuid")
```

**Phase 3 additions per D-33:**
```swift
public static let sessionRole          = KeychainKey(rawValue: "session.role")
public static let sessionUserID        = KeychainKey(rawValue: "session.userID")
public static let biometricDomainState = KeychainKey(rawValue: "biometric.domainState")
```

---

### `Roles/Shipper/ShipperTabBarController.swift` (× 5 sibling files) — avatar affordance

**Primary analog:** self — existing 35-line file (Shipper) + 4 siblings that all share the same shape.

**Existing pattern** (`ShipperTabBarController.swift:10-33`):
```swift
override func viewDidLoad() {
    super.viewDidLoad()
    viewControllers = [
        Self.makeTab(title: "Loads",     systemImage: "shippingbox"),
        Self.makeTab(title: "Brokers",   systemImage: "person.2"),
        Self.makeTab(title: "BOL",       systemImage: "doc.text"),
        Self.makeTab(title: "Assistant", systemImage: "sparkles"),
    ]
}

static func makeTab(title: String, systemImage: String) -> UIViewController {
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
```

**Phase 3 modifications per D-03:**
1. Wrap each tab VC in a `UINavigationController` (so each tab has a navigation bar that can host a right bar button item).
2. On each `UINavigationController.viewControllers.first`, install:
   ```swift
   tabRoot.navigationItem.rightBarButtonItem = UIBarButtonItem(
       image: UIImage(systemName: "person.crop.circle"),
       style: .plain,
       target: self,
       action: #selector(presentProfile)
   )
   ```
3. Add `@objc func presentProfile()` that constructs `ProfileViewController(...)` and `.present(_:animated:)`.

**Reference for UIBarButtonItem + selector pattern:** `App/DevMenu/DevMenuViewController.swift:55-59` + `:63`:
```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    barButtonSystemItem: .done,
    target: self,
    action: #selector(dismissSelf)
)
// …
@objc private func dismissSelf() { dismiss(animated: true) }
```

**Recommended D-03 helper** — extend `RoleCoordinator.swift` (currently 17 lines) with a default-implementation extension so all 5 tab bars share the wiring without copy-paste:
```swift
public extension RoleCoordinator where Self: UITabBarController {
    func wrapTabsWithNavAndAvatar(target: Any, action: Selector) {
        viewControllers = (viewControllers ?? []).map { tab in
            tab.navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "person.crop.circle"),
                style: .plain,
                target: target,
                action: action
            )
            return UINavigationController(rootViewController: tab)
        }
    }
}
```

---

### `App/SceneDelegate.swift` (MODIFY)

**Primary analog:** self — the existing observer pattern (lines 39–56) and root-swap (lines 113–139).

**Phase 3 modifications:**

**1. Replace the hardcoded shipper default** (`SceneDelegate.swift:73-75`):
```swift
// Phase 1 default: start at shipper. DevMenu (DEBUG) swaps to other roles;
// Phase 3 replaces with .launch/.auth routing based on session-token probe.
presentRoot(.role(.shipper))
```

**Replace with** (Phase 3 — D-04/D-05):
```swift
// Phase 3 D-05: probe session before first paint.
let restoreSvc = SessionRestoreService(keychainStore: KeychainStore(accessGroup: Environment.current.keychainAccessGroup))
switch restoreSvc.probe() {
case .restored(let role):
    presentRoot(.role(role))
case .needsAuth:
    presentRoot(.auth)
}
```

**2. Add `.sessionDidInvalidate` observer** alongside the existing DevMenu observer (`SceneDelegate.swift:42-55` is the analog):
```swift
private var sessionInvalidateObserver: NSObjectProtocol?
// …
sessionInvalidateObserver = NotificationCenter.default.addObserver(
    forName: .sessionDidInvalidate,
    object: nil,
    queue: .main
) { [weak self] note in
    let reason = note.userInfo?[LogoutNotificationKey.reason] as? LogoutReason ?? .userInitiated
    switch reason {
    case .userInitiated, .auth401:    self?.presentRoot(.auth)
    case .anotherActiveSession:       self?.presentRoot(.anotherActiveSession)
    }
}
```

**3. Extend `AppPhase` enum** (`SceneDelegate.swift:9-13`):
```swift
public enum AppPhase {
    case launch
    case auth
    case role(Role)
    case anotherActiveSession      // ← Phase 3 D-18
}
```

**4. Mirror the deinit cleanup** (`SceneDelegate.swift:95-101` is the template for `sessionInvalidateObserver` removal).

---

### `App/AppCoordinator.swift` (MODIFY — fill `case .auth` and `.anotherActiveSession`)

**Primary analog:** self — `makeRoot(for:)` (lines 41–55).

**Existing placeholder** (`AppCoordinator.swift:46-51`):
```swift
case .auth:
    // Phase 3 adds the OTP flow. Phase 1 placeholder.
    let vc = UIViewController()
    vc.view.backgroundColor = .systemBackground
    vc.title = "Auth (Phase 3)"
    return vc
```

**Phase 3 replacement (D-01):**
```swift
case .auth:
    let coordinator = AuthCoordinator(container: container)
    // Bubble verify-success up to AppCoordinator.onRoleResolved (already wired by SceneDelegate)
    coordinator.onAuthenticated = { [weak self] role in self?.onRoleResolved?(role) }
    // Hold a strong reference (existing Phase 1 has none for .auth — add a stored property)
    self.authCoordinator = coordinator
    return coordinator.rootViewController

case .anotherActiveSession:
    return AnotherActiveSessionViewController(container: container)
```

**Add stored property near line 12-15:**
```swift
private var authCoordinator: AuthCoordinator?     // strong reference; lives until next root-swap
```

---

### `App/AppContainer.swift` (MODIFY — register Phase 3 services)

**Primary analog:** self — the existing service block (lines 33–42 and 83–105).

**Existing service properties** (lines 33–42):
```swift
final class AppContainer {
    let env: Environment
    let logger: any Logger
    let keychainStore: KeychainStore
    let keyStore: any KeyStoreProtocol
    let sessionLock: any SessionLockService
    let networkClient: any NetworkClient
    let apiClient: APIClient
    let deepLinkRouter: DeepLinkRouter
```

**Phase 3 additions (per D-01/D-04/D-10/D-11/D-16/D-28):**
```swift
let sessionRestore: any SessionRestoreService
let biometric: any BiometricService
let sensitiveAction: any SensitiveActionService
let logoutService: any LogoutService
let locationProvider: any LocationProvider
let countryGate: any CountryGate
```

**Construction order in `init` (insert after line 83 `self.sessionLock = ...`)** :
```swift
self.biometric = DefaultBiometricService()
self.sessionRestore = DefaultSessionRestoreService(keychainStore: keychainStore, logger: logger)
self.locationProvider = DefaultLocationProvider()
self.countryGate = DefaultCountryGate()

// LogoutService depends on most of the above — construct LAST among the auth services.
self.logoutService = DefaultLogoutService(
    keychainStore: keychainStore,
    keyStore: keyStore,
    sessionLock: sessionLock,
    notificationCenter: .default,
    logger: logger
)
self.sensitiveAction = DefaultSensitiveActionService(
    biometric: biometric,
    keyStore: keyStore,
    logger: logger
)
```

**Wire Auth401ResponseInterceptor** — modify the existing apiClient construction (lines 100–105):
```swift
self.apiClient = APIClient(
    baseURL: apiBaseURL,
    networkClient: networkClient,
    requestInterceptors: [IdempotencyInterceptor()],
    responseInterceptors: [
        RetryInterceptor(),
        Auth401ResponseInterceptor(logoutService: logoutService),   // ← Phase 3 D-28
    ]
)
```

---

## Pattern Assignments — Test Files

### `validationLedgerTests/Auth/{SessionRestore,Logout,Biometric,SensitiveAction}ServiceTests.swift`

**Primary analog:** `validationLedgerTests/Auth/SessionLockServiceTests.swift` (entire 40-line file).

**Pattern: Swift Testing @Suite + @Test — fully spec'd in 40 lines** (`SessionLockServiceTests.swift:1-39`):
```swift
import Testing
import Foundation
@testable import validationLedger

@Suite("SessionLockService — unified invariant (FOUND-07)")
struct SessionLockServiceTests {
    @Test("Cold boot — shouldRequireBiometric is true when lastSuccess is nil")
    func coldBoot() {
        let svc = DefaultSessionLockService()
        #expect(svc.shouldRequireBiometric(now: Date()) == true)
    }

    @Test("Within 5-minute grace — should NOT require biometric")
    func withinGrace() {
        let svc = DefaultSessionLockService()
        let t0 = Date()
        svc.recordBiometricSuccess(at: t0)
        let within = t0.addingTimeInterval(60)  // 1 minute later
        #expect(svc.shouldRequireBiometric(now: within) == false)
    }
    // …
}
```

**Apply to all 4 new service tests:**
- Use `import Testing` (NOT `import XCTest` — the project's unit-test target is on Swift Testing per the existing files)
- `@Suite("Name — feature (REQ-ID)")`
- One `@Test` per behavioral assertion
- For services with dependencies: pass mocks to `init(...)` — initializer-DI per ARCH-04

**Pattern: actor-backed counter for async tests** (`RetryInterceptorTests.swift:14-20`) — useful for `LogoutServiceTests` to count Notification posts:
```swift
private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
    func current() -> Int { count }
}
```

---

### `validationLedgerTests/Auth/SessionLockServiceTests.swift` (MODIFY — add lockState cases)

**Primary analog:** self — the existing 4 `@Test` methods.

**Add 4 new tests for `lockState(now:)`:**
- `@Test("lockState returns .locked(.coldBoot) when lastSuccess is nil")`
- `@Test("lockState returns .unlocked within 5-minute grace")`
- `@Test("lockState returns .locked(.backgroundTimeout) past 5 minutes")`
- `@Test("lockState returns .locked(.biometricReEnrolled) when domainState changes")` — requires LAContext stub injection (planner decides exact mock shape)

---

### `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift`

**Primary analog:** `validationLedgerTests/Networking/RetryInterceptorTests.swift` (entire 205-line file).

**Pattern: parameterized @Test with `arguments:`** (`RetryInterceptorTests.swift:43-62`):
```swift
@Test(
    "GET + retryable 5xx → calls send (1 + maxRetries) times",
    arguments: [500, 502, 503, 504]
)
func getRetriesOn5xx(statusCode: Int) async throws {
    let counter = Counter()
    let interceptor = fastInterceptor(maxRetries: 3)
    let response = httpResponse(statusCode: statusCode)
    let (_, out) = try await interceptor.intercept(
        send: { _ in
            await counter.increment()
            return (Data(), response)
        },
        request: request(method: "GET")
    )
    #expect(out.statusCode == statusCode)
    let calls = await counter.current()
    #expect(calls == 4)
}
```

**Apply to Auth401ResponseInterceptorTests:**
- `@Test("401 on non-OTP path triggers logout")` — use a mock `LogoutService` actor that increments a call counter
- `@Test("401 on /auth/otp/request does NOT trigger logout", arguments: ["/auth/otp/request", "/auth/otp/verify"])`
- `@Test("Non-401 status passes through unchanged", arguments: [200, 401-non-applicable, 403, 500])`
- `@Test("Default excluded paths are exactly the OTP endpoints")` — assertion on `Auth401ResponseInterceptor().excludedPaths`

---

### `validationLedgerUITests/RoleShellSmokeTests.swift` (MODIFY per D-32)

**Primary analog:** self — the existing 5 placeholder tests (lines 18–66).

**Existing pattern** (`RoleShellSmokeTests.swift:18-26`):
```swift
func testShipperShell() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-ForceRoleForUITest", "shipper"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Brokers"].exists)
    XCTAssertTrue(app.tabBars.buttons["BOL"].exists)
    XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
}
```

**Phase 3 D-32 modification — three additions per test:**
1. Change `-ForceRoleForUITest` → `-MockOTPRoleForUITest` (D-32 sentinel) so the launcher drives the OTP fixture instead of bypassing auth.
2. After tab assertions, tap the avatar (rightBarButtonItem) to open `ProfileViewController`, tap "Log out", and assert phone-entry screen appears.
3. The existing tab inventory assertions (Loads/Brokers/BOL/Assistant for shipper, etc.) STAY — they directly verify SC-1 ("tab titles match TechStack.md §4 verbatim").

**Note:** XCUITest uses `XCTest`, NOT Swift Testing — see `RoleShellSmokeTests.swift:11` `import XCTest`. Keep that.

**SceneDelegate launchArg handling reference** (`SceneDelegate.swift:61-71`):
```swift
#if DEBUG
if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-ForceRoleForUITest"),
   idx + 1 < ProcessInfo.processInfo.arguments.count {
    let raw = ProcessInfo.processInfo.arguments[idx + 1]
    if let role = Role(rawValue: raw) {
        presentRoot(.role(role))
        window.makeKeyAndVisible()
        return
    }
}
#endif
```

The new `-MockOTPRoleForUITest <role>` sentinel follows the SAME shape — add an additional `#if DEBUG` block in SceneDelegate that, when present, drives the auth flow with a fixture that returns `<role>`.

---

### `validationLedgerDeviceTests/BiometricSESmokeTests.swift` and `EvaluatedPolicyDomainStateTests.swift`

**Primary analog:** `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` (entire 31-line file).

**Pattern: device-only `@Suite` + `@Test`** (`SecureEnclaveSmokeTests.swift:11-31`):
```swift
import Testing
import CryptoKit
@testable import validationLedger

@Suite("Device Smoke — Phase 1 D-06 minimum gate")
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

**Apply to BiometricSESmokeTests:**
- `@Suite("Device Smoke — Phase 3 SC-2/SC-3 biometric (HUMAN-UAT)")` — these are HUMAN-UAT per CONTEXT (not automatable; require human to present face/finger). Document with `@Test(.disabled("HUMAN-UAT — manual verification required"))` or comment-driven invocation.
- Test 1: cold-boot biometric prompt path — instantiate `BiometricService`, call `evaluate(reason:fallback:)`, assert success after human input.
- Test 2: domainState capture round-trip — call `LAContext().evaluatedPolicyDomainState` after `canEvaluatePolicy`, persist, read back.

---

### `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` (NEW)

**Primary analog:** `validationLedgerTests/Networking/Fixtures/otp-verify-failure.json` (4 lines).

**Existing failure fixture** (`otp-verify-failure.json:1-5`):
```json
{
  "error_code": "auth.invalid_code",
  "message": "Invalid OTP code. Please try again.",
  "remaining_attempts": 2
}
```

**Phase 3 D-02 fixture** — content suggestion:
```json
{
  "error_code": "auth.rate_limited",
  "message": "Too many attempts. Try again in 60 seconds.",
  "retry_after_seconds": 60
}
```

**Important: the Retry-After is delivered via HTTP HEADER, not body** — see RESEARCH §4 lines 760–832. The JSON body is informational; the iOS code reads `response.value(forHTTPHeaderField: "Retry-After")`. The fixture handler registration must include a `headers:` argument.

**Pattern: registerFixture with custom headers** — extend the standard registerFixture call to set `Retry-After: 60`. Reference `MockFixture.swift:14-33`:
```swift
public static func registerFixture<E: APIEndpoint>(
    for endpoint: E.Type,
    path: String,
    method: HTTPMethod,
    statusCode: Int,
    body: Data,
    headers: [String: String] = ["Content-Type": "application/json"]
)
```

For the rate-limited fixture, the test passes:
```swift
MockURLProtocol.registerFixture(
    for: OTPVerifyEndpoint.self,
    path: "/auth/otp/verify",
    method: .post,
    statusCode: 429,
    body: fixture,
    headers: ["Content-Type": "application/json", "Retry-After": "60"]
)
```

---

### `.swiftlint.yml` (MODIFY — add 5th custom rule)

**Primary analog:** self — the existing 4 custom rules (lines 62–98).

**Existing pattern** (`.swiftlint.yml:73-78`):
```yaml
ban_direct_os_log:
  name: "Do not call os_log directly"
  regex: '\bos_log\s*\('
  message: "os_log is only allowed inside Core/Logging/. Use the Logger protocol instead."
  excluded: '.*/Core/Logging/.*'
  severity: error
```

**Existing pattern with `included:` allow-list** (`.swiftlint.yml:93-98`):
```yaml
no_cross_feature_import:
  name: "Features must not import other Features"
  regex: '^\s*import\s+Features_[A-Z]'
  message: "Cross-feature communication goes through Core/ protocols. Do not import other Features."
  included: '.*/Features/[^/]+/.*'
  severity: error
```

**Phase 3 D-24 — add 5th rule alongside the others** (insert before line 98):
```yaml
ban_raw_coordinate_literal:
  name: "Do not construct CLLocationCoordinate2D outside the geo subsystem"
  regex: 'CLLocationCoordinate2D\s*\(\s*latitude\s*:'
  message: "Raw CLLocationCoordinate2D literals must live in Core/Networking/Endpoints/ (payload builders) or Core/Identity/Geo/ (the geo subsystem itself). Anywhere else risks GEO-03 leak (raw coords in analytics/logs)."
  excluded: '.*/(Core/Networking/Endpoints|Core/Identity/Geo)/.*'
  severity: error
```

**Note on regex:** D-24 uses `excluded:` (negative match) rather than `included:` because the literal can appear anywhere in `validationLedger/` — we ban EVERYWHERE except the two allow-list paths. SwiftLint's `excluded` on a custom rule supports a single regex; if multiple paths are needed, the regex must use a `(a|b)` group as shown above.

**Also remove the deferred-marker comment** (`.swiftlint.yml:4-7`):
```yaml
# DEFERRED to Phase 3 (per D-19 + Discrepancy Flag #1 in 01-RESEARCH.md):
#   - The raw-coordinate-literal custom rule (GEO-03 phantom-typed AnalyticsEvent)
#     lands alongside GEO-03 in Phase 3. It is NOT added here — …
```
…replace with an in-tree comment block above `ban_raw_coordinate_literal` documenting the GEO-03 link.

---

### `validationLedger/Resources/Info.plist` (MODIFY — NSLocationWhenInUseUsageDescription)

**NO ANALOG — establish baseline.** Phase 1+2 added zero `NS*UsageDescription` keys; this is the first.

**Action per RESEARCH (and Apple platform requirement for `CLLocationManager.requestWhenInUseAuthorization()`):**
- Add `NSLocationWhenInUseUsageDescription` key with a user-facing string explaining: "Validation Ledger is available only in the United States. We use your location once at sign-in to verify your country."
- The string is the App-Store-facing rationale; iOS displays it in the system permission prompt.

**No Swift code analog needed** — Info.plist is XML-edited via Xcode's plist editor or as text.

---

## Shared Patterns — Apply to Multiple Files

### Logging
**Source:** `validationLedger/Core/Logging/Logger.swift` (Logger protocol lines 26–29 + extension lines 31–42).
**Apply to:** Every new service, ViewModel, ViewController, and interceptor in Phase 3.

**Pattern — inject Logger via init:**
```swift
private let logger: any Logger

init(..., logger: any Logger) {
    self.logger = logger
}

// Usage:
logger.info(event: .init("session_restored"), fields: [.event: "shipper"])
logger.warn(event: .init("otp_rate_limited"), fields: [.duration: 60.0])
```

**NEVER use `print()` or `os_log` directly** — `.swiftlint.yml` rules `ban_print` and `ban_direct_os_log` will fail the build.

**NEVER pass coordinates to LogField** — after Phase 3 removes `LogField.coordinates`, this is enforced at compile time. Coordinates flow only through `PlatformPayloadField` to networking endpoints.

---

### Initializer-DI (ARCH-04)
**Source:** `validationLedger/App/AppContainer.swift:55-110` (the entire init body).
**Apply to:** Every new service constructor.

**Rule:** No `.shared`, no `static let instance`, no Swinject/Resolver. Every dependency is an init parameter; AppContainer is the ONE composition root.

**Test seam:** Inject mocks at init for unit tests. Reference `KeychainWipeTests.swift:21` for the Keychain injection pattern (testable via `defaults: UserDefaults` parameter).

---

### Sendable + nonisolated for Encodable/Decodable
**Source:** `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift:8-10`.
**Apply to:** Every new endpoint struct (this Phase has none, but pattern applies if any are added) AND every new payload field type that conforms to Encodable.

**Pattern:**
```swift
// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct OTPVerifyEndpoint: APIEndpoint { ... }
```

---

### Thread-safe mutable state (NSLock)
**Source:** `validationLedger/Core/Auth/SessionLockService.swift:18-40`.
**Apply to:** Any new service that holds mutable state (LogoutService notification queue, BiometricService LAContext token cache, OTPViewModel countdown timer).

**Pattern:**
```swift
public final class DefaultXxxService: XxxService, @unchecked Sendable {
    private var someState: T?
    private let lock = NSLock()

    public func mutate(...) {
        lock.lock(); defer { lock.unlock() }
        // ... mutate someState
    }
}
```

For new services that are MainActor-bound (per D-31), prefer `@MainActor` annotation over NSLock — the actor isolation handles thread safety.

---

### NotificationCenter publisher/observer
**Source:** `validationLedger/App/SceneDelegate.swift:42-55` (observe) + `validationLedger/App/DevMenu/NetworkConfigToggleViewController.swift:87-91` (post).
**Apply to:** `LogoutService` posting `.sessionDidInvalidate`; `SceneDelegate` observing it.

**Post pattern** (`NetworkConfigToggleViewController.swift:87-91`):
```swift
NotificationCenter.default.post(
    name: .devMenuNetworkConfigRequested,
    object: nil,
    userInfo: [DevMenuNetworkConfigKey.config: NetworkConfig.mock]
)
```

**Observe pattern** (`SceneDelegate.swift:42-55`):
```swift
networkConfigObserver = NotificationCenter.default.addObserver(
    forName: .devMenuNetworkConfigRequested,
    object: nil,
    queue: .main
) { [weak self] note in
    guard let self,
          let config = note.userInfo?[DevMenuNetworkConfigKey.config] as? NetworkConfig else {
        return
    }
    // ... handle
}
```

**Cleanup pattern** (`SceneDelegate.swift:86-101`):
```swift
func sceneDidDisconnect(_ scene: UIScene) {
    if let token = networkConfigObserver {
        NotificationCenter.default.removeObserver(token)
        networkConfigObserver = nil
    }
}

deinit {
    if let token = networkConfigObserver {
        NotificationCenter.default.removeObserver(token)
    }
}
```

**Pitfall guard (P6 in RESEARCH lines 1650–1655):** The closure-based `addObserver(forName:object:queue:using:)` retains the closure; the closure captures `self` weakly via `[weak self]` — DO NOT capture strongly.

---

### Acronym CodingKeys Bridge (IN-01/IN-05)
**Source:** `validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift:20-29` (the canonical comment + pattern).
**Apply to:** Every property whose name ends in an acronym (`ID`, `URL`, `UUID`, `OTP`, etc.) on Encodable RequestBody types.

**Pattern + canonical comment** (`OTPRequestEndpoint.swift:20-29`):
```swift
// Explicit CodingKeys: `.convertFromSnakeCase` maps "otp_session_id" -> "otpSessionId"
// (lowercase 'd'), but the property is `otpSessionID` (uppercase). With
// `.convertFromSnakeCase` enabled, the decoder converts JSON keys to camelCase BEFORE
// matching against CodingKeys — so CodingKeys raw values must be the camelCase form
// (e.g., "otpSessionId"), not the original snake_case. Acronyms in property names are a
// known JSONDecoder strategy limitation — this bridges the gap.
private enum CodingKeys: String, CodingKey {
    case otpSessionID = "otpSessionId"
    case expiresInSeconds
}
```

The encoder side (`.convertToSnakeCase`) has the symmetric problem and the same fix — the CodingKeys raw value should be the camelCase form that snake_case-converts cleanly (e.g., `"otpSessionId"` → `"otp_session_id"`).

---

### #if DEBUG compile-out for dev affordances
**Source:** `validationLedger/App/DevMenu/DevMenuViewController.swift:11+112` (entire file gated).
**Apply to:** Any new UI test launch-arg handlers (e.g., `-MockOTPRoleForUITest` D-32) — gate with `#if DEBUG` so Release builds compile zero bytes.

**Pattern:**
```swift
#if DEBUG
import UIKit

final class SomeDevAffordance { ... }

#endif
```

---

## No Analog Found (4 categories)

| Category | Files | Reason |
|----------|-------|--------|
| **ViewModels** | `PhoneEntryViewModel.swift`, `OTPViewModel.swift`, and their tests | Phase 1+2 ship zero ViewModel files (state lives in Services + Coordinators). Establish the MVVM contract here per RESEARCH §Architecture. |
| **AnalyticsField type** | n/a (D-23 mentions but it doesn't exist) | Codebase grep: zero hits for `AnalyticsField` outside planning docs. Phase 3 ships the GEO-03 invariant via `LogField` (existing — remove `.coordinates` case) + new `PlatformPayloadField`. No analytics type is created. |
| **Info.plist NS*UsageDescription** | `validationLedger/Resources/Info.plist` | First privacy-prompt addition. |
| **CLLocationManager + LAContext wrappers** | `LocationProvider.swift`, `BiometricService.swift` | Phase 1+2 has no CoreLocation or LocalAuthentication code. Pattern is fully spec'd in RESEARCH §Pattern 2 + §Pattern 3 (the planner copies from there). |
| **Modal UIKit overlay (BiometricLockViewController)** | `BiometricLockViewController.swift` | No existing full-screen modal that auto-presents on background→foreground. Pattern is in RESEARCH §6 (lines 882–917). |

---

## Critical Cross-References for the Planner

| When Planner Writes Plan For… | Read These Files First (with line ranges) |
|-------------------------------|-------------------------------------------|
| AuthCoordinator | `Roles/RoleCoordinator.swift:1-17`, `App/AppCoordinator.swift:11-65`, RESEARCH §Pattern 1 (lines 418–467) |
| PhoneEntry/OTP/Region/AnotherActiveSession VCs | `App/DevMenu/NetworkConfigToggleViewController.swift:1-117`, `App/DevMenu/RoleSwitcherViewController.swift:1-42` |
| ProfileViewController | `App/DevMenu/RoleSwitcherViewController.swift:1-42`, `App/DevMenu/DevMenuViewController.swift:44-63` |
| BiometricLockViewController | `App/DevMenu/NetworkConfigToggleViewController.swift:28-62`, RESEARCH §6 (lines 882–917) |
| SessionLockService extension | `Core/Auth/SessionLockService.swift:1-40`, `App/SceneDelegate.swift:42-101` (observer pattern + cleanup) |
| SessionRestore/Biometric/SensitiveAction/Logout services | `Core/Auth/SessionLockService.swift:1-40` (pattern shape), `Core/Storage/Keychain/KeychainStore.swift:56-85`, RESEARCH §13 + §14 |
| Auth401ResponseInterceptor | `Core/Networking/Interceptors/RetryInterceptor.swift:1-122`, `Core/Networking/Interceptors/RequestInterceptor.swift:1-22` |
| APIClient 429 + Retry-After | `Core/Networking/APIClient.swift:39-62`, `Core/Networking/NetworkError.swift:1-23` |
| OTPVerifyEndpoint IN-01 fix | `Core/Networking/Endpoints/OTPVerifyEndpoint.swift:11-26` (Response side has the pattern) |
| KYCUpload* and DeviceRegister IN-05 fixes | `Core/Networking/Endpoints/OTPRequestEndpoint.swift:20-29` (canonical comment) |
| SecureEnclaveKeyStore CR-02 | `Core/KeyStore/SecureEnclaveKeyStore.swift:71-130` (existing function + loadPublicKey) |
| SoftwareKeyStore IN-02 | `Core/KeyStore/SoftwareKeyStore.swift:18-40`, `Core/KeyStore/SecureEnclaveKeyStore.swift:132-144` (DER X9.62 reference) |
| KeyStoreProtocol deleteKey | `Core/KeyStore/KeyStoreProtocol.swift:1-35` |
| KeychainStore deleteAll(under:) | `Core/Storage/Keychain/KeychainStore.swift:56-85`, `Core/Storage/Keychain/KeychainAccessibility.swift:1-19` (KeychainScope analog) |
| KeychainKey additions | `Core/Storage/Keychain/KeychainKey.swift:1-12` |
| 5 role TabBarController avatar additions | `Roles/Shipper/ShipperTabBarController.swift:1-34` (Shipper has the canonical `makeTab`), `Roles/{Broker,Carrier,Dispatch,Factoring}TabBarController.swift:1-19` (4 siblings), `App/DevMenu/DevMenuViewController.swift:55-63` (UIBarButtonItem pattern) |
| RoleCoordinator extension | `Roles/RoleCoordinator.swift:1-17` |
| SceneDelegate session probe + observer | `App/SceneDelegate.swift:30-101` (entire scene lifecycle + observer pattern) |
| AppCoordinator .auth/.anotherActiveSession | `App/AppCoordinator.swift:41-65` |
| AppContainer service registration | `App/AppContainer.swift:33-110` |
| PlatformPayloadField | `Core/Logging/Logger.swift:6-17` (LogField shape), `Core/Logging/PIIScrubber.swift:14-37` (the `.coordinates: continue` line that gets removed) |
| LocationProvider/CountryGate | `Core/Identity/DeviceFingerprint.swift:1-74`, RESEARCH §Pattern 2 (lines 469–567) |
| Service unit tests | `validationLedgerTests/Auth/SessionLockServiceTests.swift:1-39` (Swift Testing pattern), `validationLedgerTests/Networking/RetryInterceptorTests.swift:1-205` (parameterized + actor-counter pattern) |
| RoleShellSmokeTests upgrade | `validationLedgerUITests/RoleShellSmokeTests.swift:1-67` (5 placeholders — extend each), `App/SceneDelegate.swift:61-71` (launchArg pattern to mirror) |
| Device tests | `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift:1-31` (single canonical 31-line file) |
| Rate-limited fixture | `validationLedgerTests/Networking/Fixtures/otp-verify-failure.json:1-5` (shape), `validationLedger/Core/Networking/Mock/MockFixture.swift:14-33` (registerFixture with custom headers) |
| SwiftLint rule | `.swiftlint.yml:62-98` (4 existing custom rules — copy ban_direct_os_log shape) |

---

## Metadata

**Analog search scope:**
- `validationLedger/` (49 source files across App/, Core/, Features/, Resources/, Roles/, UI/)
- `validationLedgerTests/` (18 test files across Auth/, Identity/, KeyStore/, Logging/, Navigation/, Networking/, Roles/, Storage/, App/)
- `validationLedgerUITests/` (1 file)
- `validationLedgerDeviceTests/` (3 files)
- `.swiftlint.yml` (4 existing custom rules)
- `validationLedgerTests/Networking/Fixtures/` (14 existing JSON fixtures)

**Files scanned (full read):** 33 source + test files
**Pattern extraction date:** 2026-04-21
**Phase output:** `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-PATTERNS.md`
