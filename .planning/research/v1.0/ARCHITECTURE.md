# Architecture Research — Validation Ledger iOS Client

**Domain:** Identity-verified, security-sensitive freight iOS client (UIKit-first, iOS 17+, Swift 5.9+, 1–2 engineers + AI coding tools)
**Researched:** 2026-04-20
**Overall confidence:** HIGH

> This file is prescriptive. Where it disagrees with `TechStack.md §3`, a **Delta vs TechStack.md** callout appears with rationale. TechStack.md §3 was written before GSD init and holds up well — the deltas below are surgical, not structural.

---

## TL;DR — Does TechStack.md §3 Hold Up in 2026?

**Yes, with four clarifying amendments.** The MVVM + Coordinators + AppContainer + Core/Features split is still the 2026 consensus for UIKit apps of this size and security posture. Uber/DoorDash-scale RIBs/VIPER and TCA are overkill for 1–2 engineers. SwiftUI-only patterns (FlowStacks, stinsen) don't apply because the spec is UIKit-first for the sensitive surfaces that dominate M1–M3.

**Amendments to §3:**

1. **Split `Core/Security` into three modules** (`Core/Security`, `Core/KeyStore`, `Core/Attestation`). Single-bucket security modules become junk drawers. (see §5, §6)
2. **Module cross-talk rule is stricter than §3.2 states.** Cross-feature communication goes through `Core/` **protocol interfaces** — never through `Core/` implementation types. This is the difference between testable and untestable Features. (see §3, §10)
3. **Role-based shell uses a `RoleCoordinator` swap at the SceneDelegate level, not a TabBarCoordinator swap.** Cleanly wipes state on role change (currently impossible per spec — role change requires re-KYC — but the pattern is correct for logout/switch-account). (see §7)
4. **ObservableObject + `@Published` stays for M1**, but plan a Swift 6 / `@Observable` migration gate for M4. WWDC23/24/25 signals Combine is in maintenance mode; Observation is the path forward. (see §4)

Everything else in §3 is current.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            App/  (composition root)                       │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────────┐     │
│  │ AppDelegate    │  │ SceneDelegate  │  │ AppContainer            │     │
│  │ (APNs reg,     │  │ (owns window,  │  │ (builds all deps,       │     │
│  │  background    │  │  routes to     │  │  passes to root coord)  │     │
│  │  tasks)        │  │  RoleCoord)    │  │                         │     │
│  └────────────────┘  └───────┬────────┘  └────────────┬────────────┘     │
│                              │                        │                   │
│                              ▼                        ▼                   │
│                     ┌─────────────────────────────────────┐               │
│                     │       AppCoordinator                │               │
│                     │  (launch → auth → role selection)   │               │
│                     └──────────┬──────────────────────────┘               │
│                                │                                          │
│        ┌───────────────────────┼───────────────────────┐                  │
│        ▼                       ▼                       ▼                  │
│  ┌──────────┐            ┌──────────┐            ┌──────────┐             │
│  │ AuthCoord│            │OnboardC. │            │RoleCoord │             │
│  │ (OTP,    │            │(KYC flow)│            │(per-role │             │
│  │  bio)    │            │          │            │ tab bar) │             │
│  └──────────┘            └──────────┘            └─────┬────┘             │
└───────────────────────────────────────────────────────┼──────────────────┘
                                                        │
                     ┌──────────────────────────────────┼──────────────────┐
                     │           Features/              │                  │
                     │  ┌────────┐  ┌────────┐  ┌───────▼──┐  ┌─────────┐ │
                     │  │ Loads  │  │ BOL    │  │ Scanner  │  │ Profile │ │
                     │  │ (VM+C) │  │ (VM+C) │  │ (VM+C)   │  │ (VM+C)  │ │
                     │  └───┬────┘  └───┬────┘  └────┬─────┘  └────┬────┘ │
                     └──────┼───────────┼────────────┼─────────────┼──────┘
                            │           │            │             │
                            ▼           ▼            ▼             ▼
                     ┌──────────────────────────────────────────────────┐
                     │                     Core/                         │
                     │  (Features depend ONLY on Core protocol types)    │
                     │                                                    │
                     │  ┌────────────┐  ┌────────────┐  ┌─────────────┐ │
                     │  │ Networking │  │ Auth       │  │ KeyStore    │ │
                     │  │ (NetClient │◄─┤ (Session,  │◄─┤ (SecEnclave │ │
                     │  │  interceptr│  │  tokens)   │  │  P-256)     │ │
                     │  │  cert pin) │  │            │  │             │ │
                     │  └─────┬──────┘  └─────┬──────┘  └──────┬──────┘ │
                     │        │               │                │        │
                     │  ┌─────▼──────┐  ┌─────▼──────┐  ┌──────▼──────┐ │
                     │  │ Storage    │  │ Identity   │  │ Attestation │ │
                     │  │ (Keychain, │  │ (KYC capt, │  │ (AppAttest, │ │
                     │  │  SQLCipher,│  │  Vision)   │  │  DeviceChk) │ │
                     │  │  queue)    │  │            │  │             │ │
                     │  └────────────┘  └────────────┘  └─────────────┘ │
                     │                                                    │
                     │  ┌────────────┐  ┌────────────┐  ┌─────────────┐ │
                     │  │ Realtime   │  │ Logging    │  │ Security    │ │
                     │  │ (WS/SSE    │  │ (os_log +  │  │ (screenshot │ │
                     │  │  abstrn)   │  │  PII scrub)│  │  block, JB) │ │
                     │  └────────────┘  └────────────┘  └─────────────┘ │
                     │                                                    │
                     │  ┌────────────┐  ┌────────────┐                   │
                     │  │ Analytics  │  │ AIKit      │                   │
                     │  │ (PII-aware)│  │ (backend-  │                   │
                     │  │            │  │  mediated) │                   │
                     │  └────────────┘  └────────────┘                   │
                     └───────────────────────────────────────────────────┘
                                      │
                     ┌────────────────▼────────────────────┐
                     │            UI/  (design system)      │
                     │  Shared components, colors, spacing  │
                     │  (no Core/ or Features/ deps)        │
                     └──────────────────────────────────────┘
```

**Dependency direction (strict, enforced by SPM module boundaries):**

```
App/  →  Features/  →  Core/ (protocols)  ←  Core/ (implementations)
                                 ↑
                                 UI/  (pure visual, depends on nothing)
```

Features never import Core implementation types. They receive them via initializer injection as protocol existentials (`any AuthService`, `any NetworkClient`, etc.). This is the boundary that makes the Core/ testable without feature coupling (see Quality Gate item #10).

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **App/AppDelegate** | APNs registration, background task registration (`BGTaskScheduler`), crash-handler install | Thin — delegates to `AppContainer` |
| **App/SceneDelegate** | Owns `UIWindow`, picks root coordinator (launch → auth → role), handles scene lifecycle (>5min background → biometric re-prompt trigger) | Single SceneDelegate; no multi-scene in v1 |
| **App/AppContainer** | Instantiates every `Core/` service once, holds strong refs, hands them to coordinators | Plain struct or class, no DI framework |
| **App/AppCoordinator** | Top-level flow: launch → (auth needed? → `AuthCoordinator`) → (kyc pending? → `OnboardingCoordinator`) → `RoleCoordinator` | Standard coordinator — owns a `UINavigationController` or root `UIWindow.rootViewController` |
| **Features/\*/Coordinator** | Per-feature navigation, push/present, deep-link handling | One coordinator per feature; holds weak ref to parent |
| **Features/\*/ViewModel** | Presentation state, exposes `@Published` properties, owns async tasks for that screen | `@MainActor` class, `ObservableObject` in M1, `@Observable` after M4 migration |
| **Features/\*/ViewController** | Dumb — binds ViewModel via Combine subscribers, forwards user actions | UIKit; no business logic, no networking |
| **Core/Networking/NetworkClient** | All HTTP; owns URLSession, auth header injection, cert pin delegate, retry policy | Actor-based `URLSession` wrapper; exposes async/await API |
| **Core/Networking/Interceptor** | Request-signing (device key), idempotency-key injection, auth refresh | Chain of interceptor protocols; `AuthInterceptor`, `DeviceSignatureInterceptor`, `IdempotencyInterceptor` |
| **Core/Auth** | Session state, token storage orchestration, OTP flow, biometric gate | Owns `SessionStore` (actor), `OTPService`, `BiometricService` |
| **Core/KeyStore** (new, split from §3 `Security/`) | Secure Enclave P-256 key lifecycle, sign/verify, key rotation | Thin wrapper over `SecureEnclave.P256.Signing.PrivateKey` from CryptoKit |
| **Core/Attestation** (new, split from §3 `Security/`) | App Attest key + assertion, DeviceCheck token | `DCAppAttestService` wrapper; deferred past M1 per PROJECT.md |
| **Core/Security** (narrowed) | Screenshot/recording block, jailbreak heuristics, cert-pin configuration (NOT cert-pin implementation — that lives in Networking) | Standalone observers + feature flags |
| **Core/Storage** | Keychain (`SecItem` wrapper), encrypted SQLite outbound queue, file-backed caches | Hand-rolled Keychain wrapper per STACK.md; SQLCipher or `CryptoKit.AES.GCM` over SQLite for queue |
| **Core/Identity** | KYC capture orchestration, Vision face-landmark pipeline, DL scan, upload-pipeline facade | Coordinates `AVCaptureSession` + `VisionKit` + `Core/Networking` upload |
| **Core/Realtime** | WebSocket/SSE abstraction (`RealtimeChannel` protocol), retry + reconnect + heartbeat | `URLSessionWebSocketTask` impl for M2+; SSE impl behind same protocol |
| **Core/Logging** | `OSLog.Logger` facades per subsystem, PII scrubber, `OSLogStore` export for support dumps | Structured — `Logger(subsystem: "com.maldin.validationLedger", category: "auth")` |
| **Core/Analytics** | Event abstraction, PII-aware serializer (compile-time prevents raw PII attach) | Phantom-typed events so a `RawCoordinate` cannot be attached to an `AnalyticsEvent` |
| **Core/AIKit** | Assistant client (backend-mediated only, never calls Anthropic) | Thin wrapper over `Core/Networking` with SSE stream rendering |
| **UI/** | Design system, shared `UIView` subclasses, spacing/color tokens, accessibility helpers | No Core/ dependencies; no networking |

---

## Recommended Project Structure

```
ValidationLedger/
├── App/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── AppContainer.swift
│   ├── AppCoordinator.swift
│   └── Environment.swift            # dev/staging/prod config
│
├── Core/                            # each is a local SPM package in M2+
│   ├── Networking/
│   │   ├── NetworkClient.swift      # protocol + actor impl
│   │   ├── MockURLProtocol.swift    # M1 contract-first stub
│   │   ├── Interceptors/
│   │   │   ├── AuthInterceptor.swift
│   │   │   ├── DeviceSignatureInterceptor.swift
│   │   │   └── IdempotencyInterceptor.swift
│   │   ├── CertificatePinning/
│   │   │   ├── PinningSessionDelegate.swift
│   │   │   └── PinnedCertificateStore.swift
│   │   └── Errors/
│   ├── Auth/
│   │   ├── SessionStore.swift       # actor, observable state
│   │   ├── OTPService.swift
│   │   ├── BiometricService.swift
│   │   └── TokenRefreshPolicy.swift
│   ├── KeyStore/                    # split from Security/
│   │   ├── SecureEnclaveKeyManager.swift
│   │   ├── KeyStoreProtocol.swift   # for mocking in tests
│   │   └── MockKeyStore.swift       # test-target only
│   ├── Attestation/                 # split from Security/
│   │   ├── AppAttestService.swift
│   │   └── DeviceCheckService.swift
│   ├── Security/                    # narrowed scope
│   │   ├── ScreenshotGuard.swift
│   │   ├── ScreenRecordingDetector.swift
│   │   ├── JailbreakHeuristics.swift
│   │   └── SecurityConfig.swift     # pin config lives here
│   ├── Storage/
│   │   ├── Keychain/
│   │   │   ├── KeychainStore.swift
│   │   │   └── KeychainKey.swift
│   │   ├── OutboundQueue/           # offline mutation queue
│   │   │   ├── QueuedMutation.swift
│   │   │   ├── EncryptedQueueStore.swift
│   │   │   └── QueueFlusher.swift
│   │   └── Cache/                   # BOL cache, image cache
│   ├── Identity/
│   │   ├── KYCCoordinator.swift     # captures flow
│   │   ├── LivenessDetector.swift   # Vision wrapper
│   │   ├── DocumentScanner.swift    # VisionKit wrapper
│   │   └── UploadPipeline.swift
│   ├── Realtime/
│   │   ├── RealtimeChannel.swift    # protocol
│   │   ├── WebSocketChannel.swift
│   │   ├── SSEChannel.swift
│   │   └── ReconnectPolicy.swift
│   ├── Logging/
│   │   ├── Loggers.swift            # category-specific OSLog instances
│   │   ├── PIIScrubber.swift
│   │   └── LogExporter.swift        # OSLogStore dumps
│   ├── Analytics/
│   │   ├── AnalyticsEvent.swift     # phantom-typed
│   │   ├── AnalyticsTransport.swift # protocol
│   │   └── NoOpAnalytics.swift      # M1 impl
│   └── AIKit/
│       ├── AssistantClient.swift
│       └── StreamDecoder.swift      # SSE stream parser
│
├── Features/                        # each a local SPM package in M2+
│   ├── Onboarding/                  # auth + KYC flows
│   │   ├── OnboardingCoordinator.swift
│   │   ├── PhoneEntry/ …
│   │   ├── OTPEntry/ …
│   │   └── KYCCapture/ …
│   ├── Loads/
│   │   ├── LoadsCoordinator.swift
│   │   ├── LoadList/ …
│   │   └── LoadDetail/ …
│   ├── BOL/
│   ├── Scanner/
│   ├── Assistant/
│   ├── Profile/
│   └── Settings/
│
├── Roles/                           # NEW — per TechStack.md §4, five roles
│   ├── RoleCoordinator.swift        # base — swaps tab bar per role
│   ├── Shipper/ShipperCoordinator.swift
│   ├── Broker/BrokerCoordinator.swift
│   ├── Carrier/CarrierCoordinator.swift
│   ├── Dispatch/DispatchCoordinator.swift
│   └── Factoring/FactoringCoordinator.swift
│
├── UI/
│   ├── DesignSystem/
│   │   ├── Colors.swift
│   │   ├── Spacing.swift
│   │   └── Typography.swift
│   └── Components/
│       ├── VLButton.swift
│       ├── VLTextField.swift
│       └── ChainOfTrustTimeline.swift   # FR-iOS-LOAD hero component
│
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.strings
    └── PrivacyInfo.xcprivacy
```

### Structure Rationale

- **`App/` is the composition root** — the ONLY place that knows about concrete `Core/` implementations. Everything else sees protocols. This is the single principle that preserves testability as the codebase grows.
- **`Core/KeyStore/` and `Core/Attestation/` are split out** from TechStack.md §3.2's single `Core/Security/` bucket. Security modules that bundle "certificate pinning + screenshot block + jailbreak detection + key management + attestation" become unreadable at 5+ services. Splitting by *trust primitive* (key material, device integrity claim, runtime defense) pays back within the first month.
- **`Roles/` is a new top-level directory** not shown in §3.2. The five-role requirement from §4 is too big to live inside `App/` as nested coordinators and too cross-cutting to live inside one `Features/` module. Its coordinators wire `Features/*` modules into role-specific tab bars.
- **Features are self-contained** exactly per §3.2: each has its own coordinator, view controllers, view models, and repository *protocol* (implementation injected by `AppContainer`).
- **`UI/` has no outward dependencies** — it's the design system. Features depend on it; it depends on nothing. Prevents circular imports when features expand.
- **Local SPM packages** per `Core/*` and `Features/*` module start paying off around ~15 modules or ~30 engineers; for 1–2 engineers, a single target with group folders in M1 is fine, and converting to local SPM is a near-mechanical refactor. The STACK.md note about committing `.xcodeproj` without tuist/xcodegen aligns with this — optimize for M1 simplicity, modularize later ([Modular SPM improves build times ~40%](https://ravi6997.medium.com/modern-ios-architecture-building-a-modular-project-with-swift-package-manager-033d8de9799f)).

**Suggested module migration timeline:**

| Milestone | Structure |
|---|---|
| M1 | Single app target, group folders matching the tree above |
| M2 | Extract `Core/Networking` + `Core/Auth` as local SPM packages (they're used by every feature; biggest build-time win) |
| M3 | Extract `Core/KeyStore`, `Core/Storage`, `Core/Realtime`, `Core/Identity` as local SPM packages |
| M4 | Extract `Features/*` as local SPM packages as needed; leave stable features as-is |

---

## Architectural Patterns

### Pattern 1: MVVM-C with Initializer DI

**What:** Model-View-ViewModel with a Coordinator owning navigation. Every coordinator and view model receives its dependencies through its initializer from `AppContainer`. No singletons. No service locator.

**When to use:** Default for every screen, every feature, every role.

**Trade-offs:**
- **Pro:** Testable without fixtures — you construct a ViewModel with mock protocols. No magic.
- **Pro:** Forces explicit dependency graphs — you can't hide coupling.
- **Con:** Parameter lists get long (10+ deps is a smell — split the ViewModel or extract a facade).
- **Con:** No lazy init — every dep is alive at launch. For 15-20 Core services this is fine; past 50 you need Factory or Needle.

**Example:**

```swift
// Core/Auth/AuthServiceProtocol.swift
protocol AuthService: AnyObject, Sendable {
    var sessionState: AnyPublisher<SessionState, Never> { get }
    func requestOTP(phone: String) async throws
    func verifyOTP(_ code: String) async throws -> Session
    func logout() async
}

// Features/Onboarding/OTPEntryViewModel.swift
@MainActor
final class OTPEntryViewModel: ObservableObject {
    @Published private(set) var state: State = .idle
    @Published var code: String = ""

    private let auth: any AuthService
    private let coordinator: OnboardingCoordinator
    private var tasks: Set<Task<Void, Never>> = []

    init(auth: any AuthService, coordinator: OnboardingCoordinator) {
        self.auth = auth
        self.coordinator = coordinator
    }

    func submit() {
        let task = Task { [weak self] in
            guard let self else { return }
            self.state = .verifying
            do {
                let session = try await self.auth.verifyOTP(self.code)
                self.coordinator.didAuthenticate(session: session)
            } catch {
                self.state = .failed(error)
            }
        }
        tasks.insert(task)
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }
}
```

### Pattern 2: Combine for UI Binding, async/await for Work

**What:** ViewModel exposes `@Published` state (Combine) that the View subscribes to. Inside the ViewModel, all work is async/await. When an async method finishes, it assigns to `@Published` via `@MainActor` isolation.

**When to use:** Every ViewModel. This is the "2026 right way" per Swift by Sundell and the [Medium 2026 article on hybrid ViewModels](https://medium.com/@maatheusgois/hybrid-viewmodels-with-combine-and-swift-concurrency-5bb7dfdc9955).

**Trade-offs:**
- **Pro:** Combine is what UIKit binds to naturally; async/await is what work is written in. Match the tool to the job.
- **Pro:** Structured concurrency prevents zombie tasks when VMs deinit.
- **Con:** Two paradigms to reason about. Solution: rule that Combine stays in the VM boundary; no Combine in `Core/`.

**Task cancellation discipline:**

```swift
// Wrong — leaks if ViewModel is dismissed mid-request
func load() {
    Task {
        self.items = try await repo.fetch()
    }
}

// Right — task is cancelable on deinit and checks cancellation
private var loadTask: Task<Void, Never>?

func load() {
    loadTask?.cancel()
    loadTask = Task { [weak self] in
        guard let self else { return }
        do {
            let items = try await self.repo.fetch()
            try Task.checkCancellation()
            self.items = items
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}

deinit { loadTask?.cancel() }
```

**Delta vs TechStack.md §3.4:** §3.4 says "Combine for UI state binding... Avoid mixing GCD into new code." This is correct but incomplete. Add: **Every `Task` created inside a ViewModel must be stored and cancelled on deinit, or created via `.task` modifier (SwiftUI only).** UIKit VMs don't have `.task` — they must track Task handles manually. This is the #1 Swift Concurrency leak mode per Apple Developer Forums.

**M4 migration gate:** Once iOS 17 features are exercised and Swift 6 strict concurrency is stable, migrate ViewModels from `ObservableObject + @Published` to `@Observable`. The Observation framework offers [higher-precision reactivity and lower allocation cost](https://www.infoq.com/news/2023/06/swiftui-5-wwdc-2023-observation/). For UIKit binding, you'll need an `Observation → AnyPublisher` bridge helper (non-trivial; defer to M4 when the migration is worth doing).

### Pattern 3: Protocol-First Module Boundaries

**What:** Every `Core/*` module exports a protocol. Implementation is private. Features hold `any AuthService`, not `AuthServiceImpl`.

**When to use:** Every cross-module dependency.

**Trade-offs:**
- **Pro:** Test a `LoadListViewModel` by passing a `MockLoadRepository` — no compile-time coupling to `URLSession` or the Keychain.
- **Pro:** Swap mock → live networking at the composition root without changing a Feature file.
- **Con:** Slightly more ceremony — every service needs a protocol and an impl.

**Example (interceptor chain):**

```swift
// Core/Networking/Interceptor.swift
protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

// Core/Networking/DeviceSignatureInterceptor.swift
final class DeviceSignatureInterceptor: RequestInterceptor {
    private let keyStore: any KeyStoreProtocol  // ← injected, not singleton

    init(keyStore: any KeyStoreProtocol) { self.keyStore = keyStore }

    func intercept(_ request: URLRequest) async throws -> URLRequest {
        guard request.requiresDeviceSignature else { return request }
        var signed = request
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data())
        let signature = try await keyStore.sign(Data(bodyHash))
        signed.setValue(signature.base64EncodedString(), forHTTPHeaderField: "X-Device-Signature")
        return signed
    }
}
```

### Pattern 4: Protocol Witnesses for High-Churn Services (M3+)

**What:** Instead of `protocol AuthService { func verifyOTP() }` + `class AuthServiceImpl`, use a struct of closures: `struct AuthServiceWitness { var verifyOTP: (String) async throws -> Session }`.

**When to use:** Services whose test variations explode — anything where tests need to override per-test-case (e.g., a rate-limiting test needs a different `verifyOTP` closure than a happy-path test).

**Trade-offs:**
- **Pro:** No per-test mock class. Override individual closures inline.
- **Pro:** Enables composable dependencies — `preview()`, `mock()`, `live()` factory methods.
- **Con:** Extra ceremony vs protocols. Not worth it for services with 2–3 test variations.
- **Con:** Requires the team to learn [the Point-Free pattern](https://www.pointfree.co/collections/protocol-witnesses); macro-based generators exist ([ProtocolWitness macro](https://github.com/daltonclaybrook/ProtocolWitness)) to reduce boilerplate.

**Verdict for this project:** Start with protocols in M1. If M3 scanner/BOL testing explodes (5+ mock variations per service), introduce protocol witnesses selectively. Do not make it the default — it's a power-user pattern and this is a 1–2 engineer project.

### Pattern 5: Role-Based Shell — Recreate-Root, Don't Swap Children

**What:** On role selection / login / logout, `SceneDelegate` swaps `window.rootViewController` to a brand-new `RoleCoordinator` built from a freshly-constructed `AppContainer` scope. All previous ViewControllers, ViewModels, and coordinators are deallocated.

**Why this, not "TabBarCoordinator.swapChildren(...)":**

Swapping children leaks state. A partially-loaded LoadsViewController from a Broker session can silently survive into a Dispatch session because SwiftUI/UIKit caches, URL caches, and in-flight Tasks outlive the swap. For a security-sensitive app, this is unacceptable.

Recreating the root guarantees:
- Every ViewModel's `deinit` runs → every Task cancels, every Combine subscription tears down.
- URLSession caches survive (fine) but authenticated sessions are forced to rebuild via `Core/Auth`.
- Screenshot-guard observers and screen-recording observers reset cleanly.

```swift
// App/SceneDelegate.swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: ws)
        self.window = window
        presentRoot(.launch)
        window.makeKeyAndVisible()
    }

    func presentRoot(_ phase: AppPhase) {
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
}

enum AppPhase {
    case launch, auth, onboarding, role(UserRole)
}
```

**What the OSS enterprise apps do:** [DoorDash Dasher](https://careersatdoordash.com/blog/adopting-swiftui-with-a-bottom-up-approach-to-minimize-risk/) uses per-module self-contained VIP with routers at module boundaries — conceptually identical. [Uber Freight uses RIBs](https://www.uber.com/us/en/blog/uber-freight-app-architecture-design/) which is overkill for our team size, but also recreates root scopes on major context changes. Neither swaps tab children on role transition.

**Delta vs TechStack.md §4:** §4 says "Role-specific UI is swapped at the coordinator level." True, but leaves ambiguity. Specifically: **swap at the SceneDelegate by recreating the root coordinator, not at an intermediate TabBarCoordinator.** The first form is cleanly correct; the second leaks state in ways that matter for a zero-trust-on-client app.

### Pattern 6: WebSocket + SSE Behind a `RealtimeChannel` Protocol

**What:** `Core/Realtime/RealtimeChannel.swift` is a protocol with a single API: `func subscribe<T: Decodable>(to topic: String) -> AsyncThrowingStream<T, Error>`. Two impls: `WebSocketChannel` (uses `URLSessionWebSocketTask`) and `SSEChannel` (uses `URLSession.bytes(for:)` with line parsing). `Core/Networking` configures which based on backend capability advertised at login.

**2026 consensus:** `URLSessionWebSocketTask` has matured enough to replace Starscream for new projects. [Native Swift WebSockets via URLSession is the default choice for iOS 13+](https://getstream.io/blog/swift-websockets-starscream-urlsession/); Starscream is maintained but adds a dependency for no functional gain when you're iOS 17+. `NWConnection` is lower-level and worth it only if you need raw TCP/UDP — not our case.

**Reconnect policy lives in a separate type:**

```swift
protocol RealtimeChannel: Sendable {
    func subscribe<T: Decodable>(topic: String, as: T.Type) -> AsyncThrowingStream<T, Error>
    func disconnect() async
}

struct ReconnectPolicy: Sendable {
    let initialDelay: Duration
    let maxDelay: Duration
    let jitter: Double   // 0.0...1.0

    func delay(for attempt: Int) -> Duration {
        let base = initialDelay * pow(2.0, Double(attempt))
        let capped = min(base, maxDelay)
        let jittered = capped * (1.0 + .random(in: -jitter...jitter))
        return jittered
    }
}
```

Heartbeat (ping/pong) is the WebSocket impl's responsibility; `URLSessionWebSocketTask.sendPing()` runs on a timer owned by the channel. On `URLSessionWebSocketDelegate.urlSession(_:webSocketTask:didCloseWith:reason:)`, the channel reconnects per policy and re-subscribes to topics from an in-memory topic registry.

**Where it fits:** `Core/Realtime` depends on `Core/Networking` (for auth headers) and `Core/Auth` (for session-scoped connection). Features subscribe via injected `any RealtimeChannel`.

**Build order implication:** `Core/Realtime` is not M1 — it's M2 (FR-iOS-LOAD real-time updates). But its *protocol shape* should be sketched in M1 so `Core/Networking` isn't refactored when it lands.

### Pattern 7: Offline Mutation Queue with Idempotency Keys

**What:** `Core/Storage/OutboundQueue` persists mutations (arrived-at-shipper, BOL scan confirmation) to an encrypted on-disk SQLite with:

- `id: UUID` (the idempotency key sent in `Idempotency-Key` header)
- `endpoint: String`
- `payload: Data` (encrypted with a Keychain-wrapped AES-GCM symmetric key)
- `createdAt: Date`
- `attemptCount: Int`
- `lastError: String?`

A `QueueFlusher` service observes `NWPathMonitor.pathUpdateHandler` and, when connectivity returns, iterates the queue in order, POSTing each mutation. Backend returns 200 OK or "already applied" (dedup). Background continuation uses `BGProcessingTaskRequest` registered at launch — when the app is backgrounded mid-flush, the BGTask completes the flush within its runtime budget.

**Why encrypted at rest:** the queue may contain load IDs, GPS coords (for "arrived" events), and signed timestamps — per PROJECT.md Constraints, "no sensitive data in plain files."

**Idempotency keys are non-negotiable.** Without them, a queue flushed twice after a flaky network looks like two load-arrived events to the backend, which creates duplicate events in a system whose premise is trust. [See Gunnar Morling on idempotency keys](https://www.morling.dev/blog/on-idempotency-keys/) for the rationale pattern.

**Build order:** M4 per TechStack.md §10. But M1 should establish the `IdempotencyInterceptor` (adds header from a request property) so queue flushes use the same code path as live requests.

```
┌─────────────────┐
│ Feature calls   │
│ repo.arrive(...)│
└────────┬────────┘
         │ (offline detected by NWPathMonitor)
         ▼
┌─────────────────────────┐     ┌─────────────────────┐
│ OutboundQueue.enqueue() │────▶│ EncryptedQueueStore │
│   - assigns UUID        │     │  (SQLite + AES-GCM) │
│   - writes to disk      │     └─────────────────────┘
└─────────────────────────┘
         ▲
         │
         │ (online detected)
         │
┌────────┴────────┐         ┌────────────────┐         ┌──────────┐
│  QueueFlusher   │────────▶│ NetworkClient  │────────▶│ Backend  │
│  - FIFO drain   │  sign   │  + Idempotency │         │  (dedup  │
│  - backoff on   │  inject │   Interceptor  │         │   on UUID)│
│    429/5xx      │         └────────────────┘         └──────────┘
└─────────────────┘
```

---

## Data Flow

### Launch → Role-Routed UI (the "happy path" flow)

```
  SceneDelegate.scene(willConnectTo:)
          │
          ▼
  AppContainer()   ←── builds all Core services from protocols
          │
          ▼
  AppCoordinator.start(phase: .launch)
          │
          ├─(no session in Keychain)──► AuthCoordinator (OTP flow)
          │                                  │
          │                                  ▼ (verified)
          │                             AppCoordinator.didAuthenticate()
          │                                  │
          ├─(session + kyc pending)────► OnboardingCoordinator (KYC)
          │                                  │
          │                                  ▼ (KYC uploaded)
          │                             AppCoordinator.didCompleteKYC()
          │                                  │
          ▼                                  │
  RoleCoordinator(role:)   ◄────────────────┘
          │
          └─► UITabBarController
                ├── Loads tab (Features/Loads)
                ├── <role-specific tab>
                ├── BOL / Chain tab
                └── Assistant tab
```

### Signed Request (sensitive action — tender/accept/BOL scan)

```
 Feature ViewModel
      │ repo.tender(loadId, carrierId)
      ▼
 Features/Loads/LoadRepository (impl)
      │ NetworkClient.post("/tenders", body: ...)
      ▼
 Core/Networking/NetworkClient
      │
      ├─► AuthInterceptor           ─── adds Authorization: Bearer <token>
      │        (from SessionStore)
      │
      ├─► DeviceSignatureInterceptor ─── asks KeyStore.sign(body-hash)
      │        │
      │        └─► Core/KeyStore ──► SecureEnclave.P256.Signing.PrivateKey
      │                                                │
      │                                                ▼
      │                              signature returned as raw bytes
      │                              header: X-Device-Signature: <b64>
      │
      ├─► IdempotencyInterceptor    ─── adds Idempotency-Key: <uuid>
      │
      └─► PinningSessionDelegate    ─── on TLS handshake:
               │                        compare server leaf SPKI
               │                        to pinned SPKI set
               │                        (reject if no match)
               ▼
        URLSession.data(for:)
               │
               ▼
         backend (/live or MockURLProtocol in M1)
```

### KYC Capture → Upload (FR-iOS-KYC)

```
 Features/Onboarding/KYCCaptureViewController
      │ "Capture Face" tapped
      ▼
 Core/Identity/KYCCoordinator
      │
      ├─► AVCaptureSession (managed by Core/Identity/CameraSession)
      │        │
      │        └─► CMSampleBuffer stream
      │               │
      │               ▼
      │        Core/Identity/LivenessDetector (VNDetectFaceLandmarks)
      │               │
      │               └─► returns .passed | .failed(reason)
      │
      ├─► On .passed: CLLocationManager snapshot → attach as metadata
      │
      ├─► On .passed: CoreImage JPEG encode → temp file
      │
      └─► Core/Identity/UploadPipeline
               │
               └─► Core/Networking.upload(file:resumable:progress:)
                        │
                        └─► (resumable chunking, exponential backoff)
                                 │
                                 ▼
                       backend /kyc/documents
```

### Offline Status Update (FR-iOS-OFF)

```
 Feature ViewModel: repo.markArrived(loadId)
      │
      ▼
 LoadRepository
      │ NWPathMonitor.currentPath.status == .satisfied?
      │
      ├─► YES: NetworkClient.post(...) → backend
      │
      └─► NO: OutboundQueue.enqueue(
              endpoint: "/loads/\(id)/arrived",
              payload: <encrypted>,
              idempotencyKey: UUID()
           )
              │
              ▼
         EncryptedQueueStore writes to SQLite
              │
              │    ... time passes, app backgrounded ...
              │
              ▼
         NWPathMonitor.pathUpdateHandler fires (connectivity back)
              │
              ▼
         QueueFlusher.drainQueue()
              │
              ▼
         NetworkClient.post(...) with X-Idempotency-Key header
              │
              ▼
         backend dedups on idempotency key
              │
              ▼
         QueueFlusher.markFlushed(id)  → delete from SQLite
```

### Real-Time Load Status (FR-iOS-LOAD)

```
 RoleCoordinator launches LoadsCoordinator
      │
      ▼
 LoadsViewModel.subscribeToUpdates()
      │
      ▼
 any RealtimeChannel.subscribe(topic: "loads.\(userId)", as: LoadUpdate.self)
      │
      ▼
 WebSocketChannel (or SSEChannel if backend advertises SSE)
      │
      ├─► opens URLSessionWebSocketTask
      │        │
      │        └─► sends AUTH frame with session token
      │
      ├─► heartbeat every 30s (sendPing)
      │
      └─► on receive: JSON decode → yield to AsyncThrowingStream
               │
               ▼
          LoadsViewModel merges update into @Published loads
               │
               ▼
          UIKit view controller reacts via Combine subscriber
```

---

## Security Architecture — Where Each Concern Lives

This is the most important table in this document. Security requirements that are scattered across the module graph become untestable and un-auditable. Explicit placement is enforced by `Core/` module boundaries.

| Concern | Module | Entry Point | Notes |
|---|---|---|---|
| **TLS certificate pinning** | `Core/Networking/CertificatePinning/` | `PinningSessionDelegate` attached to the single app `URLSession` | SPKI pinning (not full cert), rotation-friendly. Pins loaded from `Core/Security/SecurityConfig` (bundle-signed JSON). **Do NOT use TrustKit** — it's a transitive CocoaPods-era dep, and URLSession delegate pinning is ~30 lines in Swift per [Medium SSL pinning guide 2025](https://dev.to/arshtechpro/mastering-ssl-pinning-in-ios-from-basics-to-production-4m2e). |
| **Device key generation / sign** | `Core/KeyStore/SecureEnclaveKeyManager` | `sign(Data) async throws -> Data` | CryptoKit `SecureEnclave.P256.Signing.PrivateKey`. Access control: `.privateKeyUsage + .biometryCurrentSet + .or(.devicePasscode)` so biometric re-enrollment rebinds. Public key registered once at first login; wrapped private key blob persisted in Keychain. |
| **Token storage (Bearer)** | `Core/Storage/Keychain/KeychainStore` | `store(key:value:access:)` | Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Hand-rolled `SecItem` wrapper per STACK.md (no KeychainAccess library). |
| **Session state (in memory)** | `Core/Auth/SessionStore` | `actor SessionStore` | Swift actor — isolated access. Publishes `sessionState: AnyPublisher<SessionState, Never>` for UI. Backgrounds >5min → emits `.requiresBiometricRefresh`. |
| **Biometric prompt** | `Core/Auth/BiometricService` | `evaluate(reason:) async throws -> Bool` | Wraps `LAContext.evaluatePolicy`. Separate from KeyStore — biometric for UI gating is not the same as biometric-protected key access. |
| **App Attest / DeviceCheck** | `Core/Attestation/AppAttestService` | `attestKey() async throws -> AttestationBundle` | `DCAppAttestService.generateKey()` + `attestKey(challenge:)`. Challenge fetched from backend per [Apple docs](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). Result sent with login payload. |
| **Jailbreak detection** | `Core/Security/JailbreakHeuristics` | `evaluate() -> JailbreakSignal` | Reports to backend; backend decides policy per spec §5.3. Don't block on client-only signal. |
| **Secure Enclave availability check** | `Core/KeyStore/SecureEnclaveKeyManager` | `SecureEnclave.isAvailable` (static) | Refuse production login if unavailable. Test builds + simulator bypass to `MockKeyStore`. |
| **Screenshot block** | `Core/Security/ScreenshotGuard` | Observes `UIScreen.capturedDidChangeNotification`; exposes a `UIView` overlay | Attached by sensitive ViewControllers via `ScreenshotGuardProtocol`. BOL, identity docs, chain-of-trust, QR opt in. |
| **Screen recording detection** | `Core/Security/ScreenRecordingDetector` | KVO on `UIScreen.main.isCaptured` | Same consumers as ScreenshotGuard. |
| **PII scrubbing — logging** | `Core/Logging/PIIScrubber` | `OSLogPrivacy` rules + `Logger(subsystem:category:)` | Each subsystem gets a `Logger`. PII-containing strings use `\(x, privacy: .private(mask: .hash))`. `OSLogStore` export runs PII scrubber before writing to support-dump files. |
| **PII scrubbing — analytics** | `Core/Analytics/AnalyticsEvent` | Phantom-typed `Event<Scope>` where `Scope: PIIScope` | A `RawCoordinate` type can never be attached to `Event<Public>` at compile time. Enforces FR-iOS-GEO "Never attach raw coordinates to analytics events." |
| **Idempotency key injection** | `Core/Networking/Interceptors/IdempotencyInterceptor` | Reads `URLRequest.idempotencyKey` (custom property), writes header | Set at enqueue time for outbound queue; ensures retries don't double-apply. |
| **Request signing** | `Core/Networking/Interceptors/DeviceSignatureInterceptor` | Conditionally signs based on `URLRequest.requiresDeviceSignature` | Only tender, accept, BOL-generation, sensitive-action endpoints. |

### Security Architecture Dependency Graph

```
                   ┌─────────────────┐
                   │  Secure Enclave │  (hardware)
                   │  (hardware)     │
                   └────────▲────────┘
                            │
                   ┌────────┴────────┐
                   │ Core/KeyStore   │  (CryptoKit wrapper)
                   └───┬─────────┬───┘
                       │         │
               ┌───────▼───┐ ┌───▼──────────────┐
               │Core/Auth  │ │Core/Networking/  │
               │(sign OTP  │ │ Interceptors/    │
               │ challenge)│ │ DeviceSignature  │
               └─────┬─────┘ └───────┬──────────┘
                     │               │
                     └───────┬───────┘
                             │
                             ▼
                   ┌─────────────────┐
                   │ Feature code    │
                   │ (never sees     │
                   │  Enclave API)   │
                   └─────────────────┘
```

**Critical property:** Features never import `CryptoKit` or `LocalAuthentication`. They call `any SessionService`, `any SignedRequestBuilder`. This is what makes the security layer testable and audit-able — there's exactly one place crypto primitives are touched.

### Testing Security-Sensitive Modules Without a Real Secure Enclave

**The hard truth:** the iOS Simulator does not emulate Secure Enclave ([Apple Developer Forums confirmation](https://developer.apple.com/forums/thread/748611)). Key generation with `.biometryAny`/`.biometryCurrentSet` access control fails on simulator.

**Strategy:**

1. **Protocol abstraction in `Core/KeyStore`:**
   ```swift
   protocol KeyStoreProtocol: Sendable {
       func generateKey() async throws -> KeyBundle
       func sign(_ data: Data) async throws -> Data
       var isHardwareBacked: Bool { get }
   }
   ```

2. **Two implementations:**
   - `SecureEnclaveKeyStore` (production — real `SecureEnclave.P256.Signing.PrivateKey`)
   - `SoftwareKeyStore` (test builds — `P256.Signing.PrivateKey` in memory; `isHardwareBacked == false`)

3. **Environment-driven selection in `AppContainer`:**
   ```swift
   let keyStore: any KeyStoreProtocol = {
       #if DEBUG && targetEnvironment(simulator)
       return SoftwareKeyStore()
       #else
       guard SecureEnclave.isAvailable else {
           fatalError("Production build on non-SE device")  // spec §5.3 MUST
       }
       return SecureEnclaveKeyStore()
       #endif
   }()
   ```

4. **Physical-device test gate in CI:** unit tests run on simulator with `SoftwareKeyStore`; a **device-only test plan** runs a smaller "security integration" suite on real iPhone 12 / 15 hardware. GitHub Actions supports runners with connected physical devices, or Xcode Cloud can be configured with real-device destinations.

5. **Explicit tests for the protocol contract,** not the implementation: "key survives app restart," "signature verifies with public key," "biometric re-enrollment invalidates key." These tests run on device; simulator tests are skipped with `XCTSkipUnless(...isHardwareBacked...)`.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **M1 Foundation (single target, ~5k LOC)** | Group folders, single app target, no local SPM. `AppContainer` as a simple struct. 15–20 `Core/` services; initializer DI is trivially tractable. |
| **M2–M3 (dozens of features, 20k LOC, 2 engineers)** | Extract `Core/Networking` and `Core/Auth` as local SPM packages first. Every change to networking triggers minimal rebuilds. |
| **M4–M5 (full v1, ~50k LOC)** | Full modular SPM — every `Core/*` and `Features/*` a local package. Build times benefit most here. Consider Factory library if `AppContainer` parameter lists exceed ~40 services ([Factory is the 2026 recommendation for small teams](https://lucasvandongen.dev/di_frameworks_compared.php)). |
| **Post-v1 (v2, Android parity, 100k+ LOC, 5+ engineers)** | Consider Needle for compile-time DI graph verification. Re-evaluate coordinators vs. `NavigationStack` + SwiftUI if the SwiftUI-first trade-offs flip. |

### Scaling Priorities — What Breaks First

1. **Build times.** Monolith target breaks around 10k LOC for iterative compile. Solution: extract `Core/Networking` as local SPM package at M2 boundary — not earlier (premature) and not later (painful to extract a mature network layer with 50 call sites).

2. **`AppContainer` parameter lists.** If any single coordinator takes more than ~8 dependencies, you have a "god coordinator." Split the feature. This will happen first in `LoadsCoordinator` as chain-of-trust + real-time + offline queue converge.

3. **Cross-module test setup.** When `LoadListViewModelTests` needs to construct 5 mocks + 3 fakes + 1 in-memory queue, the VM is doing too much. Extract a `LoadListDataSource` protocol that composes the plumbing.

4. **Coordinator memory retention.** If a coordinator keeps strong refs to child coordinators and the child to the parent, you leak the whole graph. Parent owns children strongly; children hold `weak var parent: ParentCoordinator?`.

5. **ViewModel Task leaks.** Easy to leak a `Task { ... }` that keeps a VM alive past its view controller's lifetime. Mitigation: audit every `Task {` in VMs by M2 for a `[weak self]` + stored handle + `deinit { task?.cancel() }` pattern.

---

## Anti-Patterns

### Anti-Pattern 1: Singleton "`SessionManager.shared`"

**What people do:** Put the auth session in a static singleton for easy access from every view model. "Just `SessionManager.shared.token` it, we'll refactor later."

**Why it's wrong:** (a) Tests can't swap the session for a fake — tests running in parallel share global state. (b) Deferred-deadlock risk if singleton init does I/O. (c) Obscures the actual dependency graph — you can't see who depends on session without grepping.

**Do this instead:** `any SessionService` injected via `AppContainer` → coordinator → ViewModel. One place holds the session (`AppContainer`), and every dependent explicitly declares it.

### Anti-Pattern 2: Fat Core module ("`Core/Security/` does everything")

**What people do:** Dump cert pinning + screenshot block + jailbreak detection + key management + attestation + PII scrubbing into one `Core/Security/` folder per the literal §3.2 reading.

**Why it's wrong:** Five different concerns, five different review cadences, five different test surfaces. Can't audit "what touches the private key" without reading the whole module. New engineer asks "where does cert pinning live?" → has to read ten files.

**Do this instead:** Split by trust primitive. `Core/KeyStore` (key material), `Core/Attestation` (device integrity), `Core/Security` (runtime defenses like screenshot/JB), `Core/Networking/CertificatePinning/` (TLS-layer concern — lives with the network client, not in Security). Per §5 above.

### Anti-Pattern 3: Combine pipelines inside `Core/`

**What people do:** Use Combine throughout the Core modules because "it's reactive" — `NetworkClient.request() -> AnyPublisher<T, Error>`.

**Why it's wrong:** (a) Combine is in maintenance mode per [WWDC 2023+ shift to Observation](https://www.infoq.com/news/2023/06/swiftui-5-wwdc-2023-observation/). (b) Apple's own new APIs are async/await-native. (c) async/await makes cancellation + backpressure + error propagation trivial; Combine makes them incantations. (d) Combine in `Core/` couples every feature to Combine — you can't migrate piecewise later.

**Do this instead:** async/await + `AsyncThrowingStream` in `Core/`. Combine only inside ViewModels for `@Published` output. If a VM needs to consume an `AsyncThrowingStream`, it bridges locally with `for try await` in a stored Task.

### Anti-Pattern 4: Role swap by mutating the existing TabBarController

**What people do:** `tabBarController.viewControllers = newViewControllers` when the user's role changes.

**Why it's wrong:** The old ViewModels, their `@Published` pipelines, their in-flight `Task`s, their cached `URLSession` delegate challenges are still in memory until ARC decides to drop them. A security-sensitive app with 5 roles and an explicit "role cannot change without re-verification" spec must *definitely* guarantee a clean slate — not rely on ARC timing.

**Do this instead:** `SceneDelegate.presentRoot(.role(newRole))` — build a fresh `AppCoordinator` on a fresh `AppContainer` scope. Window gets a new `rootViewController`. Old graph deallocates deterministically. (Pattern 5 above.)

### Anti-Pattern 5: Hiding async/await failures in `Task { try? await ... }`

**What people do:** `Task { try? await repo.fetch() }` — suppress errors because "it compiled."

**Why it's wrong:** Silently swallowed errors in security-critical flows (token refresh, KYC upload) become production bugs that only show up in the field. For a zero-PII, trust-is-the-product app, silent failure is worse than a visible error.

**Do this instead:** Every `Task` in a ViewModel handles `do { try await ... } catch { self.error = error; logger.error(...) }`. Use `Task.checkCancellation()` before assignment to avoid writing state on cancelled tasks. `try?` is allowed only for best-effort telemetry where a caller has already logged the intent.

### Anti-Pattern 6: "We'll add tests later"

**What people do:** Skip testing `Core/Auth`, `Core/KeyStore`, `Core/Networking` in M1 because "the patterns aren't stable yet."

**Why it's wrong:** These are exactly the modules where a regression = a security incident. They are also the modules whose protocols are used by every feature — if the protocols change in M2 because tests forced better design, it's now a 30-file refactor instead of a 5-file refactor.

**Do this instead:** Tests first for `Core/*`, especially `KeyStore`, `Auth`, `Networking` (interceptors + pinning), `Storage` (Keychain round-trip, queue persistence). Target 80%+ coverage for these. Feature tests are looser (60–70% per spec §9). Per the STACK.md commitment to Swift Testing, use `@Test` and parameterized tests from day 1.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Backend REST API | `Core/Networking/NetworkClient` (single entry), URLProtocol mock in M1, live URL in M2+ | Contract-first. Mock returns realistic payloads. No networking code changes between mock and live — only `BASE_URL`. |
| Backend WebSocket / SSE | `Core/Realtime/RealtimeChannel` protocol + two impls | Backend picks WS or SSE per capability advertise at login. |
| APNs | `AppDelegate.didRegisterForRemoteNotifications` → `Core/Notifications/PushTokenService` → backend `POST /devices/push` | Device token + app-bundle id. Silent push handled in `BackgroundFetchHandler`. |
| Apple App Attest service | `Core/Attestation/AppAttestService` → `DCAppAttestService.attestKey(_:clientDataHash:)` | Challenge fetched from backend per request. |
| FMCSA (via backend) | `Core/Networking` passthrough; iOS never calls FMCSA directly | §5.2 SHOULD. |
| Anthropic (via backend only) | `Core/AIKit` → `NetworkClient.stream("/ai/chat")` with SSE | iOS never holds an Anthropic API key. Per §5.9 MUST. |
| Secure Enclave | `Core/KeyStore` exclusive access | Hardware — no network. |
| Keychain | `Core/Storage/Keychain/KeychainStore` exclusive access | OS subsystem. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Feature A ↔ Feature B | Through `Core/` protocols only; never direct import | If `Loads` needs user role, it gets it from `any SessionService`, not from `Profile`. |
| Coordinator ↔ ViewModel | Coordinator passes closures (`onFinish: () -> Void`) to VM; VM never imports Coordinator type | Inversion of control — coordinator knows about navigation, VM knows nothing of it. |
| ViewModel ↔ ViewController | `@Published` properties consumed by VC via Combine; VC dispatches user actions via methods on VM | Classic MVVM binding. |
| `Core/` service ↔ `Core/` service | Via injected protocols at `AppContainer` construction | E.g., `NetworkClient` receives `any KeyStoreProtocol` — not `SecureEnclaveKeyStore`. |
| `Core/Networking` ↔ `Core/Auth` | Bidirectional-safe via protocol split: `NetworkClient` holds `any AuthTokenProvider`; `AuthService` holds `any NetworkClient` | Break the cycle by splitting the auth contract: `AuthTokenProvider` (what networking needs) vs. `AuthService` (what features need). |

---

## Build Order for M1 Foundation

Derived from the data flows and dependency graph above. If you build in this order, each phase's downstream code has a foundation to stand on.

| Order | Phase Topic | Rationale |
|---|---|---|
| **1** | `App/` skeleton + `AppContainer` shell + `SceneDelegate` | Everything plugs into this. Without it, you can't wire anything. |
| **2** | `UI/` design tokens (colors, spacing, typography) — minimum viable set | Unblocks all subsequent VCs from hardcoding constants. |
| **3** | `Core/Logging` (os_log Loggers + PII scrubber stub) | Every other module uses it. Build first so it can be used in construction logs from day 1. |
| **4** | `Core/Storage/Keychain/KeychainStore` (hand-rolled `SecItem` wrapper) | Prerequisite for `Core/Auth`. Test Keychain roundtrip before anything touches tokens. |
| **5** | `Core/KeyStore` (`SecureEnclaveKeyManager` + `SoftwareKeyStore` for simulator) | Prerequisite for device registration in `Core/Auth`. Physical-device test gate established here. |
| **6** | `Core/Networking` — `NetworkClient` actor + `MockURLProtocol` + `AuthInterceptor` + `DeviceSignatureInterceptor` + `PinningSessionDelegate` | Every feature needs this. Built against a mock first per STACK.md contract-first commitment. Cert pinning wired in even if dev pins are self-signed — production config swap only. |
| **7** | `Core/Auth` — `SessionStore` actor + `OTPService` + `BiometricService` | Depends on KeyStore + Networking + Keychain. First module that combines multiple Core services — good stress test of the DI wiring. |
| **8** | `App/AppCoordinator` + `Features/Onboarding/AuthCoordinator` — OTP screen + OTP verify screen | First user-facing flow end-to-end. Validates MVVM + Coordinators + Combine-binding pattern. |
| **9** | `Roles/RoleCoordinator` base + 5 placeholder tab bars (one per role, each tab a "coming soon" VC) | Spec requires all five roles shippable in M1 with placeholder UI per PROJECT.md Active requirements. Validates role-shell architecture. |
| **10** | Session persistence + biometric re-prompt (>5 min background) wiring across `Core/Auth` + `SceneDelegate` | The "foundation complete" signal — user can cold-boot, resume, and get prompted correctly. |
| **11** | `Core/Identity/KYCCoordinator` + capture UI (face + DL + vehicle) + upload pipeline against MockURLProtocol | Final M1 deliverable per spec §10. Exercises camera, Vision, upload, progress UI. |
| **12** | `Core/Logging/PIIScrubber` production rules + `Core/Analytics/NoOpAnalytics` | Required by spec §8 before any beta. Wire in now so it's exercised against real log output. |

**Post-M1 (M2+), not to start in M1 but to sketch protocols for:**

- `Core/Realtime/RealtimeChannel` protocol (impl M2)
- `Core/Storage/OutboundQueue` protocol (impl M4)
- `Core/Attestation` protocol (impl M2, after M1 auth shim works end-to-end)

---

## Delta Summary vs TechStack.md §3

| TechStack.md §3 | 2026 Consensus | Delta? |
|---|---|---|
| §3.1 MVVM + Coordinators | MVVM + Coordinators still standard for UIKit-first apps this size | **Aligned** |
| §3.2 `Core/` as flat directory of 8 subdirs | Split `Core/Security` into `Core/KeyStore` + `Core/Attestation` + narrowed `Core/Security` | **Delta — split** |
| §3.2 "Cross-feature communication goes through Core/" | Correct but needs sharpening: through Core/ *protocols*, not concrete types | **Delta — clarification** |
| §3.2 No explicit `Roles/` directory | Add `Roles/` at top level; `RoleCoordinator` + per-role subdir | **Delta — addition** |
| §3.3 Initializer DI via single `AppContainer` | Holds up perfectly for 1–2 engineers at this scale; consider Factory post-v1 only | **Aligned** |
| §3.4 async/await for new code, Combine for UI binding | Correct; add explicit Task cancellation discipline and plan M4 `@Observable` migration | **Aligned — with discipline note** |
| (§3 silent) Role swap mechanism | Recreate root coordinator at SceneDelegate, don't mutate TabBar children | **New guidance** |
| (§3 silent) Certificate pinning placement | In `Core/Networking/CertificatePinning/`, not `Core/Security/` | **New guidance** |
| (§3 silent) Realtime abstraction | `URLSessionWebSocketTask` + `RealtimeChannel` protocol; skip Starscream | **New guidance** |
| (§3 silent) Offline queue location | `Core/Storage/OutboundQueue/`, AES-GCM over SQLite, idempotency keys mandatory | **New guidance** |

**Net assessment:** TechStack.md §3 is 85% correct as written. The deltas above are refinements, not rewrites. A human engineer reading §3 and implementing it as written would not produce a bad architecture — they'd produce a working one that benefits from the refinements during M2–M3 refactoring. Shipping §3 as-is to M1 is safe; shipping this ARCHITECTURE.md's refinements to M1 is better.

---

## Sources

Apple / Official:
- [Protecting keys with the Secure Enclave — Apple Developer](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- [SecureEnclave — CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit/secureenclave)
- [Preparing to use the App Attest service — Apple Developer](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service)
- [Establishing your app's integrity — Apple Developer](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- [Architecting Your App for Multiple Windows — WWDC19](https://developer.apple.com/videos/play/wwdc2019/258/)
- [Authentication Services — Apple Developer](https://developer.apple.com/documentation/authenticationservices)
- [Streamline local authorization flows — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10108/)
- [Secure Enclave simulator limitations — Apple Developer Forums](https://developer.apple.com/forums/thread/748611)

Architecture references:
- [iOS Architecture in 2026: Which One Should You Actually Use? — Chandra Welim](https://medium.com/@chandra.welim/ios-architecture-in-2026-which-one-should-you-actually-use-793917181411)
- [Architecture Patterns in Mobile Development 2026: MVVM, MVI, Clean — J@y](https://medium.com/@jyc.dev/architecture-patterns-in-mobile-development-2026-mvvm-mvi-and-clean-architecture-f26583f53522)
- [Building an iOS App with MVVM, Coordinators and Protocol-Oriented Programming — Beyza Nur Tekerek, Dec 2025](https://beyzanurtekerek.medium.com/building-an-ios-app-with-mvvm-coordinators-and-protocol-oriented-programming-3f41afcc0257)
- [awesome-ios-architecture — onmyway133](https://github.com/onmyway133/awesome-ios-architecture)
- [Coordinators and Tab Bars: A Love Story — Holy Swift](https://holyswift.app/coordinators-and-tab-bars-a-love-story/)
- [Using Coordinator With Scene Delegates — Mark Struzinski](https://markstruzinski.com/2019/08/using-coordinator-with-scene-delegates/)

Enterprise / multi-role apps:
- [Building the New Uber Freight App — Uber Engineering](https://www.uber.com/us/en/blog/uber-freight-app-architecture-design/)
- [Uber's iOS RIBs Architecture: A Deep Dive — Gaurav Harkhani](https://medium.com/@gauravharkhani01/ubers-ios-ribs-architecture-a-deep-dive-716105a7454c)
- [DoorDash Adopting SwiftUI with Bottom-Up Approach](https://careersatdoordash.com/blog/adopting-swiftui-with-a-bottom-up-approach-to-minimize-risk/)
- [RIBs — Uber's cross-platform mobile architecture framework](https://github.com/uber/RIBs)

Concurrency + Combine + Observation:
- [SwiftUI 5 Leaves Combine behind, Extends Animations — InfoQ, 2023 on WWDC23 Observation](https://www.infoq.com/news/2023/06/swiftui-5-wwdc-2023-observation/)
- [Mastering SwiftUI: Combine vs Async/Await in 2026 — ViralSwift](https://medium.com/@viralswift/mastering-swiftui-combine-vs-async-await-when-to-use-what-in-2026-c458d64eaf35)
- [Hybrid ViewModels with Combine and Swift Concurrency — Gois](https://medium.com/@maatheusgois/hybrid-viewmodels-with-combine-and-swift-concurrency-5bb7dfdc9955)
- [Creating Combine-compatible versions of async/await-based APIs — Swift by Sundell](https://www.swiftbysundell.com/articles/creating-combine-compatible-versions-of-async-await-apis/)
- [Swift Concurrency: Structured Concurrency, Task Cancellation — Chetansinh Rajput, May 2025](https://medium.com/mobile-innovation-network/part-2-swift-concurrency-structured-concurrency-task-cancellation-and-more-fb6aaba7ea78)
- [Streaming changes with Observations — Swift with Majid, July 2025](https://swiftwithmajid.com/2025/07/30/streaming-changes-with-observations/)

Dependency injection:
- [Comparing Four different approaches to DI — Lucas van Dongen](https://lucasvandongen.dev/di_frameworks_compared.php)
- [Factory — hmlongco/Factory on GitHub](https://github.com/hmlongco/Factory)
- [Needle — uber/needle on GitHub](https://github.com/uber/needle)

Security / networking:
- [SSL Certificate Pinning on iOS Using TrustKit — Bugsee](https://bugsee.com/blog/ssl-certificate-pinning-on-ios-using-trustkit/)
- [Mastering SSL Pinning in iOS: From Basics to Production — DEV.to 2025](https://dev.to/arshtechpro/mastering-ssl-pinning-in-ios-from-basics-to-production-4m2e)
- [Enhancing iOS App Security with SSL Pinning using URLSession — Mohamed Elsdody](https://medium.com/@mohamed.ma872/enhancing-ios-app-security-with-ssl-pinning-a-developers-guide-using-urlsession-fb47c3258304)
- [iOS Keychain: using Secure Enclave-stored keys — Alexei Gridnev](https://medium.com/@alx.gridnev/ios-keychain-using-secure-enclave-stored-keys-8f7c81227f4)
- [CryptoKit and the Secure Enclave — Andy Ibanez](https://www.andyibanez.com/posts/cryptokit-secure-enclave/)
- [Implementing Apple's Device Check App Attest Protocol — DEV.to](https://dev.to/mnelsonwhite/implementing-apples-device-check-app-attest-protocol-4p2g)

Real-time + offline:
- [Real-Time Networking in iOS: WebSocketTask vs Socket.IO vs Starscream vs SSE — Sreejith Bhatt](https://medium.com/@sreejithbhatt/real-time-networking-in-ios-websockettask-vs-socket-io-vs-starscream-vs-server-sent-events-1111b1992de1)
- [Swift WebSockets: Starscream or URLSession in 2021 — Stream.io](https://getstream.io/blog/swift-websockets-starscream-urlsession/)
- [WWDC 2025 - iOS 26 Background APIs: BGContinuedProcessingTask — DEV.to](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)
- [On Idempotency Keys — Gunnar Morling](https://www.morling.dev/blog/on-idempotency-keys/)
- [Handling Offline Support and Data Synchronization in iOS — Kalidoss Shanmugam](https://medium.com/@kalidoss.shanmugam/handling-offline-support-and-data-synchronization-in-ios-with-swift-2130ecb3d7c1)

Modularization / build times:
- [Modern iOS Architecture: Building a Modular Project with SPM — Garejakirit, Mar 2026](https://medium.com/@garejakirit/modern-ios-architecture-building-a-modular-project-with-swift-package-manager-94f6d3fc106c)
- [Modern iOS Architecture: Build Modular Apps with SPM — 2025 Guide](https://ravi6997.medium.com/modern-ios-architecture-building-a-modular-project-with-swift-package-manager-033d8de9799f)
- [What's New in Swift Package Manager for 2025 — Commit Studio](https://commitstudiogs.medium.com/whats-new-in-swift-package-manager-spm-for-2025-d7ffff2765a2)

Testability / protocol witnesses:
- [Protocol Witnesses — Point-Free collection](https://www.pointfree.co/collections/protocol-witnesses)
- [Simplifying Test Writing with Protocol Witnesses in Swift — Oren Idan, DEV.to](https://dev.to/orenidan/simplifying-test-writing-with-protocol-witnesses-in-swift-4nmg)
- [ProtocolWitness macro — daltonclaybrook/ProtocolWitness](https://github.com/daltonclaybrook/ProtocolWitness)
- [Mock-free unit tests in Swift — Swift by Sundell](https://www.swiftbysundell.com/articles/mock-free-unit-tests-in-swift/)

---

*Architecture research for: identity-verified freight iOS client (Validation Ledger)*
*Researched: 2026-04-20*
*Overall confidence: HIGH — Apple official sources + multiple 2025/2026 architecture references + cross-verified with STACK.md decisions and TechStack.md spec.*
