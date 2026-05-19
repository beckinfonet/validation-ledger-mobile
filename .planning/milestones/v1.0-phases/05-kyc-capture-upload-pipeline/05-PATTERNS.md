# Phase 5: KYC Capture & Upload Pipeline - Pattern Map

**Mapped:** 2026-05-16
**Files analyzed:** 24 new/modified files
**Analogs found:** 21 / 24 (3 have no direct in-repo analog — see "No Analog Found")

> Phase 5 is, as RESEARCH.md states, mostly composition of shipped primitives. This map ties
> every new file to the closest in-repo analog and gives the planner concrete excerpts to copy.
> All paths absolute-relative to the repo root `/Users/ustatb01/development/mobileApps/validation-ledger-mobile`.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Features/Onboarding/KYC/KYCCoordinator.swift` | coordinator | event-driven | `Features/Onboarding/Auth/AuthCoordinator.swift` | exact |
| `Features/Onboarding/KYC/KYCStartViewController.swift` | view-controller | request-response | `Features/Profile/ProfileViewController.swift` | role-match |
| `Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift` | view-controller | streaming | `Features/Onboarding/Auth/OTPViewController.swift` | role-match (UIKit), no camera analog |
| `Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift` | view-model | streaming | `Features/Onboarding/Auth/OTPViewModel.swift` | role-match |
| `Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift` | view-controller | streaming | `Features/Onboarding/Auth/OTPViewController.swift` | role-match (UIKit), no scanner analog |
| `Features/Onboarding/KYC/Capture/DLFrontExtractionViewController.swift` | view-controller | request-response | `Features/Onboarding/Auth/OTPViewController.swift` | role-match |
| `Features/Onboarding/KYC/Capture/DLBackCaptureViewController.swift` | view-controller | streaming | `Features/Onboarding/Auth/OTPViewController.swift` | role-match |
| `Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift` | view-controller | streaming | `Features/Onboarding/Auth/OTPViewController.swift` | role-match |
| `Features/Onboarding/KYC/Capture/CapturePreviewViewController.swift` | view-controller | request-response | `Features/Profile/ProfileViewController.swift` | role-match |
| `Features/Onboarding/KYC/KYCReviewViewController.swift` | view-controller | request-response | `Features/Onboarding/Auth/OTPViewController.swift` | role-match |
| `Features/Onboarding/KYC/KYCReviewViewModel.swift` | view-model | event-driven | `Features/Onboarding/Auth/OTPViewModel.swift` | role-match |
| `Features/Onboarding/KYC/KYCStatusViewController.swift` | view-controller | request-response | `Features/Onboarding/Auth/OTPViewController.swift` | role-match |
| `Features/Onboarding/KYC/KYCStatusViewModel.swift` | view-model | request-response | `Features/Onboarding/Auth/OTPViewModel.swift` | role-match |
| `Core/Identity/KYCUploader.swift` | service (actor) | batch/streaming | `Core/Networking/Interceptors/RetryInterceptor.swift` (retry math) + `OTPViewModel.verify()` (multi-step orchestration) | role-match (no actor analog) |
| `Core/Identity/Capture/CameraSession.swift` | service | streaming | `Core/Identity/Geo/LocationProvider.swift` (continuation-bridged delegate wrapper) | role-match |
| `Core/Identity/Capture/FaceQualityGate.swift` | service | streaming | `Core/Identity/Geo/LocationProvider.swift` | partial-match |
| `Core/Identity/Capture/GPSMetadataInjector.swift` | utility | transform | — | **no analog** |
| `Core/Identity/Geo/GeoContext.swift` | service (actor) | request-response | `Core/Identity/Geo/LocationProvider.swift` | exact (builds on it) |
| `Core/Identity/KYC/KYCSession.swift` | model | — | `App/AppSession.swift` (state holder rationale) | partial-match |
| `Core/Identity/KYC/ArtifactUploadState.swift` | model | — | — | **no analog** |
| `Core/Identity/KYC/RejectionReasonCode.swift` | model (enum) | — | `Core/Storage/Keychain/KeychainScope.swift` (Sendable enum + pure resolver) + `LogoutReason` | role-match |
| `Core/Storage/KYCSessionStore.swift` | store | file-I/O | `Core/Storage/Keychain/KeychainStore.swift` | role-match (Keychain, not file) |
| `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` (modify — add `kycStatus`) | endpoint | request-response | `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` (self) | exact |
| `App/AppDelegate.swift` + `App/SceneDelegate.swift` + `App/AppCoordinator.swift` (modify — `.kyc` phase + BGTask) | app-wiring | event-driven | self (existing `.auth` phase wiring) | exact |
| `Core/Networking/Endpoints/KYCSubmitEndpoint.swift` (likely new) | endpoint | request-response | `Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` | exact |
| `validationLedgerTests/...` KYC tests + fixtures | test | — | `validationLedgerTests/Networking/APIClientEndpointTests.swift` | exact |

---

## Pattern Assignments

### `Features/Onboarding/KYC/KYCCoordinator.swift` (coordinator, event-driven)

**Analog:** `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` (entire file, 58 lines — **exact** structural template, explicitly named by CONTEXT/RESEARCH).

Copy the whole shape: `@MainActor final class`, a `let rootViewController: UIViewController` that is a `UINavigationController`, a callback `var`, `private let nav` + `private let container: AppContainer`, and `init(container:)` that builds the root VC, wraps it in a nav controller, stores both, then wires the first VM's callback. New screens are pushed via `private func push…` methods that wire the next VM's callback before `nav.pushViewController`.

**Full structure to copy** (`AuthCoordinator.swift:13-58`):
```swift
@MainActor
final class AuthCoordinator {
    let rootViewController: UIViewController
    var onAuthenticated: ((Role) -> Void)?

    private let nav: UINavigationController
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        let phoneVM = PhoneEntryViewModel(/* deps from container */)
        let phoneVC = PhoneEntryViewController(viewModel: phoneVM)
        let nav = UINavigationController(rootViewController: phoneVC)
        self.nav = nav
        self.rootViewController = nav
        phoneVM.onPhoneSubmitted = { [weak self] otpSessionID in
            self?.pushOTP(otpSessionID: otpSessionID)
        }
    }

    private func pushOTP(otpSessionID: String) {
        let vm = OTPViewModel(/* deps */)
        let vc = OTPViewController(viewModel: vm)
        vm.onAuthenticated = { [weak self] role in self?.onAuthenticated?(role) }
        nav.pushViewController(vc, animated: true)
    }
}
```

**For `KYCCoordinator`:** rename `onAuthenticated` → `onKYCSubmitted: (() -> Void)?`, add `onSignOut: (() -> Void)?` (D-14). The push chain is `pushFaceCapture()` → `pushDLFront()` → `pushDLBack()` → `pushTruck()` → `pushTrailer()` → `pushPlate()` → `pushReview()` → `pushStatus()`, each advancing on the per-shot Use/Retake confirm (D-07).

> **Retention rule (MUST copy):** `AppCoordinator` must hold the `KYCCoordinator` in a strong instance property — see the `private var authCoordinator: AuthCoordinator?` pattern in `AppCoordinator.swift:28` and the detailed comment at lines 21-28. Without it the coordinator deallocates immediately after `makeRoot` and the callback plumbing is orphaned.

---

### `Features/Onboarding/KYC/Capture/*ViewController.swift` (view-controllers, UIKit)

**Analog:** `validationLedger/Features/Onboarding/Auth/OTPViewController.swift` (entire file, 192 lines — the canonical programmatic-UIKit VC pattern).

Copy the file scaffold exactly:
- `public final class …: UIViewController` with `private let viewModel: …`
- UI components declared as lazy property closures with `translatesAutoresizingMaskIntoConstraints = false` and an `accessibilityIdentifier` set (`OTPViewController.swift:21-80`).
- `public init(viewModel:)` + `required init?(coder:) { fatalError("not used") }` (`:84-89`).
- `viewDidLoad` builds a `UIStackView`, pins it to `safeAreaLayoutGuide` with constants, then `addTarget` + wires `viewModel.onStateChange` / `onVerifyEnabledChange` closures (`:93-126`).
- `@objc private func` action handlers wrap async VM calls in `Task { await viewModel.… }` (`:139-145`).
- A `private func handle(state:)` switch maps each VM state enum case to concrete UI mutations (`:149-191`).

**UI-SPEC deltas the planner must apply (these are NOT in the analog):**
- The analog uses raw literals `32 / 24 / 12` for stack insets/spacing. Phase 5 MUST use `DS.Spacing` tokens instead — `topAnchor` constant `DS.Spacing.xl` (32), leading/trailing `DS.Spacing.lg` (24), default stack spacing `DS.Spacing.md` (16) / compact `DS.Spacing.sm` (8). The `DS` enum lives at `validationLedger/UI/DesignSystem/Spacing.swift`. Do not copy the OTP literal `12`.
- Fonts: use `DS.Typography` tokens (`validationLedger/UI/DesignSystem/Typography.swift`), set `adjustsFontForContentSizeCategory = true` on every label.
- Colors: `DS.Colors` (`validationLedger/UI/DesignSystem/Colors.swift`); add `DS.Colors.destructive = .systemRed` per UI-SPEC.
- All copy via `NSLocalizedString(_, value:)` (the `LimitedTrustBannerView` pattern; `Resources/en.lproj`).

> Camera/scanner VCs (`FaceCaptureViewController`, `DLFrontScanViewController`) have **no in-repo
> AVFoundation/VisionKit analog** — only the UIKit VC scaffold above transfers. The
> `AVCaptureVideoPreviewLayer` / `DataScannerViewController` body comes from RESEARCH Patterns 2-3,
> not the codebase. The simulator cannot exercise these — see "No Analog Found" + RESEARCH's
> device-CI note.

---

### `Features/Onboarding/KYC/*ViewModel.swift` (view-models)

**Analog:** `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` (entire file, 248 lines).

Copy the VM contract exactly:
- `@MainActor public final class …` (`OTPViewModel.swift:26-27`).
- A nested `public enum State: Equatable, Sendable` enumerating every UI state (`:31-39`).
- `public private(set) var state: State` with a `didSet` that fires `onStateChange?(state)` (`:41-46`).
- `public var on…: ((…) -> Void)?` callbacks — UIKit-first, no Combine (`:61-63`).
- Dependencies are all `private let`, injected via `init` — initializer-DI per ARCH-04 (`:65-93`).
- Async methods set `state = .…`, `do/catch` on `apiClient.request(…)`, pattern-match typed `NetworkError` cases (`:104-214`).

**Multi-step orchestration to mirror for `KYCUploader` callers** — `OTPViewModel.verify()` (`:104-214`) is the model for any "do step, set progress state, catch typed error, continue" sequence. The `state = .settingUp(progress:total:)` progression maps directly onto `KYCReviewViewModel`'s per-artifact upload-status surface (D-03) and `KYCUploader`'s init→chunk→commit progression.

**Error catch pattern to copy** (`OTPViewModel.swift:114-124`):
```swift
} catch let NetworkError.rateLimited(retryAfter) {
    startCountdown(seconds: Int(retryAfter))
    return
} catch let NetworkError.httpError(statusCode, _) where statusCode == 401 {
    state = .error(message: "Invalid code. Try again.")
    return
} catch {
    logger.error(event: .init("otp_verify_failed"), fields: [.event: String(describing: error)])
    state = .error(message: "Verification failed. Try again.")
    return
}
```

---

### `Core/Identity/KYCUploader.swift` (service actor, batch/streaming — UPL-01..04)

**No single exact analog** — compose three shipped patterns:

1. **Endpoint orchestration** — `OTPViewModel.verify()` (`OTPViewModel.swift:104-214`): the "step → state → typed-error catch → next step" loop is the template for `init` → `chunk`-loop → `commit`. Each step is `try await apiClient.request(<KYCEndpoint>)`.

2. **Jittered exponential backoff** — `RetryInterceptor.delayForAttempt(_:)` (`RetryInterceptor.swift:81-102`) — copy this math verbatim into `KYCUploader`'s own POST-aware retry loop:
```swift
func delayForAttempt(_ attempt: Int) -> UInt64 {
    let rawShift = attempt >= 62 ? UInt64.max : baseDelayMs << attempt
    let capped = min(rawShift, ceilingMs)
    let maxJitter = Int64(Double(capped) * 0.2)
    let jitter: Int64 = maxJitter > 0 ? Int64.random(in: -maxJitter...maxJitter) : 0
    return UInt64(max(0, Int64(capped) + jitter))
}
```
   Also copy `isRetryable(_:)` (`RetryInterceptor.swift:109-120`) for the URLError classification. **UPL-03 cap is 5 attempts** (not the interceptor's default 3); `Task.sleep(nanoseconds: delay * 1_000_000)` between attempts (`:51`).

> **CRITICAL — do NOT reuse `RetryInterceptor` itself.** `RetryInterceptor.intercept(...)` (`RetryInterceptor.swift:38`) hard-guards `request.httpMethod == "GET"` and passes POST through unretried by design (NET-05, comment lines 7-9). Chunk uploads are POSTs. The retry loop must live *inside* `KYCUploader`, reusing only the backoff math + URLError classifier.

3. **Idempotency key per chunk** — `IdempotencyInterceptor` (`IdempotencyInterceptor.swift:21-27`) does **not overwrite a caller-supplied `Idempotency-Key`** — this is the seam built for Phase 5. The endpoint structs route bodies through `APIClient` which has no per-header API, so the planner must surface a way to set a header on the request (either an endpoint-level header hook or a dedicated upload path). The key MUST be **stable** per `(uploadID, chunkIndex)` so retries dedupe (UPL-03 / SC-5) — a deterministic string like `"\(uploadID).chunk.\(chunkIndex)"` or a UUIDv5-style derivation, persisted in the chunk state so it survives a force-quit resume.

**KYCUploader shape:** `actor` in `Core/Identity/`, injected `apiClient: APIClient`, `store: KYCSessionStore`, `logger: any Logger` via `init` (ARCH-04). Per artifact: `POST init` → loop `POST chunk` (persist `chunksAcked` after each via the store) → `POST commit` → delete local artifact copy (D-02). Progress is server-driven: `chunksAcked / totalChunks` from the `KYCUploadChunkEndpoint.Response` (`KYCUploadChunkEndpoint.swift:28-32`) — never byte-counted (UPL-04, RESEARCH Pitfall 3).

**SHA-256:** `CryptoKit.SHA256` for both the full-artifact `sha256` (`KYCUploadInitEndpoint.RequestBody.sha256`) and per-chunk `chunkSha256` (`KYCUploadChunkEndpoint.RequestBody.chunkSha256`), hex-encoded.

---

### `Core/Identity/Geo/GeoContext.swift` (service actor — Pitfall 6 step 3)

**Analog:** `validationLedger/Core/Identity/Geo/LocationProvider.swift` (entire file, 123 lines — **exact**; CONTEXT D-discretion says build on it, do not duplicate).

`GeoContext` is a thin actor cache **over** `LocationProvider`. Reuse:
- The freshness/accuracy thresholds already encoded in `DefaultLocationProvider.currentLocation(maxAge: 30, maxAccuracy: 100)` (`LocationProvider.swift:72-86`) and the `didUpdateLocations` guards (`:106-112`) — `loc.timestamp.timeIntervalSinceNow < -30` → `staleFix`, `horizontalAccuracy > 100 || < 0` → `lowAccuracy`.
- The `LocationError` enum (`:30-41`) — `GeoContext` can throw the same cases or wrap them.

**GeoContext addition:** at KYC-flow start, call `locationProvider.currentLocation(...)` once and cache the `CLLocation`; at each capture, read the cached fix synchronously and re-validate age (<30s) / accuracy (<100m), refreshing if stale. The directory `Core/Identity/Geo/` is the SwiftLint `ban_raw_coordinate_literal` allow-list (`LocationProvider.swift:9-12`) — `CLLocationCoordinate2D` construction is permitted there, so `GeoContext` belongs in that directory.

> **PII routing:** coordinates must go through `Core/Identity/PlatformPayloadField` types (Phase 3 D-23, GEO-03), never `LogField`/`AnalyticsField`. Never log a raw coordinate (RESEARCH Pitfall 1/6).

---

### `Core/Identity/Capture/CameraSession.swift` + `FaceQualityGate.swift` (services, streaming)

**Analog:** `validationLedger/Core/Identity/Geo/LocationProvider.swift` — for the **protocol + Default impl + continuation-bridged delegate** shape only.

Copy the structural pattern (`LocationProvider.swift:19-59`):
- A `public protocol …` declaring the async surface; a `public final class Default…: NSObject, …Delegate` that bridges the delegate callbacks.
- The `NSObject` subclass + delegate-callback → `CheckedContinuation` / async-stream bridge (`:80-122`) is the model for wrapping `AVCapturePhotoCaptureDelegate` and `AVCaptureVideoDataOutputSampleBufferDelegate`.
- `@MainActor`-isolated public methods with `nonisolated` delegate callbacks that hop back via `Task { @MainActor [weak self] in … }` (`:90-122`).

The actual `AVCaptureSession` / `VNDetectFaceRectanglesRequest` bodies come from RESEARCH Patterns 1-2 — there is no AVFoundation/Vision code in the repo to copy. Keep the camera/Vision logic behind a protocol so the upload pipeline and quality-gate decision logic stay simulator-testable (RESEARCH device-CI note).

---

### `Core/Storage/KYCSessionStore.swift` (store, file-I/O — KYC-06 / UPL-02)

**Analog:** `validationLedger/Core/Storage/Keychain/KeychainStore.swift` (entire file, 156 lines — **role-match**: same `Core/Storage` layer, same store contract; mechanism differs — Keychain vs. file).

Copy the store API shape:
- A `public enum …Error: Error, Sendable` with descriptive cases (`KeychainStore.swift:8-13`).
- A `public final class …: @unchecked Sendable` (or an actor) with a typed `init` (`:15-22`).
- `set` / `get` / `delete` methods; `delete` is **idempotent** — missing item is success (`:56-63`).
- A scope/bulk-delete extension — `deleteAll(under:)` (`:114-128`) — the model for "clear the whole KYC session on full-submit or explicit discard" (D-02).

**Mechanism (Claude's Discretion — planner picks):** RESEARCH recommends `NSFileProtectionComplete`-protected files for the multi-MB artifact `Data` blobs plus a small JSON/SQLite index. Honour PROJECT.md "no sensitive data in plain files" — set `.completeFileProtection` on every written file and on the containing directory. The artifact `Data` is large so it does **not** go in the Keychain.

> **D-02 — survives logout.** `LogoutService.logout(...)` (`LogoutService.swift:63-94`) wipes only `KeychainScope.session` keys (`KeychainStore.swift:114-128`) and the SE auth key — it never touches `Core/Storage` files. So the KYC on-disk session naturally survives logout *as long as the planner does NOT add the KYC store to a logout teardown step*. Assumption A4 holds by default; the planner must simply not wire KYC-store deletion into `LogoutService`. The store is cleared only by `KYCCoordinator` on full-submit or explicit discard (D-02).

---

### `Core/Identity/KYC/RejectionReasonCode.swift` (model enum — D-11)

**Analog:** `validationLedger/Core/Storage/Keychain/KeychainScope.swift` (42 lines) + `LogoutReason` in `LogoutService.swift:21-25`.

Copy the typed-vocabulary-enum pattern:
- `public enum …: String, Sendable` with one case per controlled-vocabulary code (`LogoutReason` is the closest — `String`-raw, `Sendable`).
- A pure resolver function on the enum — `KeychainScope.contains(_:)` (`KeychainScope.swift:30-40`) is the model: a `switch self` returning a derived value, with a documented fallback for non-members.

For D-11, the resolver maps each code → a localized sentence; add an `unknown` / `init(rawValue:)`-fallback case so an unmapped backend code degrades gracefully (RESEARCH D-11). Strings via `NSLocalizedString` from `Resources/en.lproj`. The reason string arrives as `KYCStatusEndpoint.Response.Artifact.rejectionReason: String?` (`KYCStatusEndpoint.swift:16`).

---

### `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` (modify — add `kycStatus`)

**Analog:** the file itself (`OTPVerifyEndpoint.swift`, **exact**) — extend `Response`.

Add `public let kycStatus: String` to `Response` (`:27-39`). Mirror the **explicit `CodingKeys`** discipline already in the struct (`:34-38`): the strategy is `.convertFromSnakeCase`, raw values are camelCase post-conversion form. Add `case kycStatus`. The 8 KYC fixtures use snake_case keys (`kyc-status-success.json` shows `overall_status`, `artifact_id`, `rejection_reason`) so the wire key is `kyc_status`.

---

### `Core/Networking/Endpoints/KYCSubmitEndpoint.swift` (likely new — D-03 finalizer)

**Analog:** `validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` (40 lines — **exact** template; smallest endpoint, same shape as the thin finalizer).

Copy verbatim: `nonisolated public struct …: APIEndpoint`, nested `RequestBody`/`Response`, explicit `CodingKeys` with `case xID = "xId"` acronym bridge (`KYCUploadCommitEndpoint.swift:17-19, 27-30`), `let path` / `let method = .post` / `let body: RequestBody?`, and an `init` that builds the body. Planner must first confirm whether a `/kyc/submit` endpoint/fixture already exists — CONTEXT lists only init/chunk/commit/status.

---

### `App/AppDelegate.swift` + `SceneDelegate.swift` + `AppCoordinator.swift` (modify — `.kyc` phase, BGTask)

**Analog:** the existing `.auth` phase wiring across these three files (**exact**).

**`AppPhase` (`SceneDelegate.swift:9-16`):** add a `case kyc` to the enum, mirroring `case auth`.

**`AppCoordinator` (`AppCoordinator.swift:30-72`):** add a `case .kyc:` branch in the `init` switch that constructs `KYCCoordinator(container:)`, stores it in a new `private var kycCoordinator: KYCCoordinator?` strong property (mirror `authCoordinator` — `:28`), and surfaces `coord.rootViewController`. After init, wire `kyc.onKYCSubmitted` → `onRoleResolved` and `kyc.onSignOut` (forwarding to the existing logout path) the same way `auth.onAuthenticated` is wired at `:66-70`. Also add `.kyc` to `phaseDescription(_:)` (`:99-106`).

**`SceneDelegate`:** cold-boot routing (`:203-225`). The `SessionRestoreProbe.probe()` switch currently yields `.restored(role)` or `.needsAuth`. D-13 extends this: after OTP-verify and on cold boot, read the cached `kycStatus` and route to `.kyc` when not yet verified. Mirror the `SessionRestoreService.probe()` Keychain-read pattern (`SessionRestoreService.swift:29-47`) — read a new `KeychainKey.kycStatus` value optimistically, no round-trip (Phase 3 D-04 philosophy). The `presentRoot(_:)` mechanism (`SceneDelegate.swift:285-341`) handles any new phase unchanged — just add a `case .kyc` to any phase switch.

**`AppDelegate` (`AppDelegate.swift:11-21`):** add `BGTaskScheduler.shared.register(forTaskWithIdentifier:…)` inside `application(_:didFinishLaunchingWithOptions:)` for the UPL-05 upload-continuation task — placed alongside the existing `KeychainWiper.wipeOnFirstLaunch` call.

> **`KeychainKey` addition (D-13):** add `static let kycStatus = KeychainKey(rawValue: "session.kycStatus")` to `KeychainKey.swift` next to `sessionRole` / `sessionUserID` (`KeychainKey.swift:19-21`). Decide deliberately whether it joins `KeychainScope.session` — D-02 says the KYC *on-disk session* survives logout, but the cached *status string* is session metadata. Adding it to `.session` (`KeychainScope.swift:32-39` + `KeychainStore.deleteAll` `:117-124`) is consistent with `sessionRole`; the on-disk artifact store is the thing that must NOT be wiped, and that is a separate store.

---

### KYC Tests + Fixtures

**Analog:** `validationLedgerTests/Networking/APIClientEndpointTests.swift` (393 lines — **exact**; already contains the KYC init/chunk/commit/status endpoint tests at lines 214-391).

Copy the test conventions:
- `swift-testing` (`import Testing`), `@Suite("…", .serialized)` because every test mutates the shared `MockURLProtocol` handler registry (`:12`).
- Each `@Test` opens with `MockURLProtocol.reset()` + `defer { MockURLProtocol.reset() }` (`:50-51`).
- `FixtureLoader.loadFixture("name")` loads a JSON file from `validationLedgerTests/Networking/Fixtures/`; register via `MockURLProtocol.registerFixture(for:path:method:statusCode:body:)` (`MockFixture.swift:14-21`).
- Success-path: decode + `#expect` on typed fields; failure-path: `assertHTTPError` helper (`APIClientEndpointTests.swift:36-45`).

**New fixtures needed** (CONTEXT line 114 / RESEARCH): the 8 shipped KYC fixtures cover only one status state. Add fixtures for `overall_status` = `pending` / `verified` / `rejected`, and per-artifact `rejection_reason` codes for each `RejectionReasonCode`. Match the existing snake_case JSON shape (`kyc-status-success.json`).

**Simulator constraint:** keep `KYCUploader`, `GPSMetadataInjector`, `KYCSessionStore`, `RejectionReasonCode`, and the status state machine as pure logic behind protocols so they run on simulator CI. Live-camera/`DataScanner` surfaces go to the Phase-4 physical-device CI lane or HUMAN-UAT (RESEARCH).

---

## Shared Patterns

### Initializer DI via `AppContainer` (ARCH-04)
**Source:** `validationLedger/App/AppContainer.swift` (composition root) + every Default* service.
**Apply to:** `KYCUploader`, `GeoContext`, `CameraSession`, `FaceQualityGate`, `KYCSessionStore`, all KYC ViewModels and the `KYCCoordinator`.
Every dependency is a `private let` injected through `init` — no singletons, no `.shared`. The new services slot into `AppContainer` as `let` properties constructed in `init` (the file constructs `apiClient`, `locationProvider`, `logoutService`, etc. in dependency order at `AppContainer.swift:138-384`). `KYCCoordinator(container:)` takes the whole container exactly as `AuthCoordinator(container:)` does.

### Typed networking facade
**Source:** `validationLedger/Core/Networking/APIClient.swift` + `APIEndpoint.swift`.
**Apply to:** every KYC backend call.
`KYCUploader` and the status VMs call `container.apiClient.request(<KYCEndpoint>)` — they never build their own `APIClient` or `URLSession` (`APIClient.swift:8-11` comment). `APIClient` throws **exclusively** `NetworkError` cases (`APIClient.swift:7-9`); callers `do/catch` and pattern-match (`OTPViewModel.swift:114-124`). New endpoint structs follow `APIEndpoint` (`APIEndpoint.swift:15-21`): `nonisolated public struct`, `RequestBody`/`Response`, explicit `CodingKeys` acronym bridge for any `…ID` field.

### PII-scrubbed structured logging (LOG-01 / FOUND-01)
**Source:** `validationLedger/Core/Logging/Logger.swift`; usage at `OTPViewModel.swift:121`, `SceneDelegate.swift:450-520`.
**Apply to:** `KYCUploader`, `GeoContext`, all capture services.
`logger.info/warn/error(event: .init("event_name"), fields: [.event: <safe string>])`. `LogField` is a closed enum — it physically cannot carry image bytes, DL numbers, or coordinates. **Never** log raw artifact `Data`, extracted DL fields, or `CLLocation` coordinates (RESEARCH Pitfall 1/6). On errors, log only the event name (see the empty-`fields` discipline in `SceneDelegate.swift:450-453, 517-520`).

### `MockURLProtocol` + contract-first fixtures, TDD RED→GREEN
**Source:** `MockURLProtocol.swift`, `MockFixture.swift`, `APIClientEndpointTests.swift`.
**Apply to:** every KYC endpoint touch + the new status-state / rejection-reason fixtures.
Fixtures land before production code. The mock session is wired in `AppContainer.makeSession` (`AppContainer.swift:427-445`); `MockURLProtocol` is in `protocolClasses` only on `.mock`. JSON fixtures use snake_case keys (`.convertFromSnakeCase`).

### `#if DEBUG` compile-out for dev affordances
**Source:** `SceneDelegate.swift:122-195` (`-ForceRoleForUITest` / `-MockOTPRoleForUITest`), `MockDefaultFixtures.swift` (whole file DEBUG-gated).
**Apply to:** any KYC dev seam — e.g. a launch-arg that drives a fixed KYC status for UI tests, or seeds a fake `KYCSession`. Release must compile to zero bytes. Mirror the triple-gating in `AppContainer.swift:345-350`.

### Design-System tokens (UI-SPEC contract)
**Source:** `validationLedger/UI/DesignSystem/{Spacing,Typography,Colors}.swift`.
**Apply to:** every KYC UIKit screen.
`DS.Spacing` / `DS.Typography` / `DS.Colors` — never raw literals. The existing Auth VCs use raw `8/12/16/24/32`; Phase 5 must NOT copy that — use tokens (`Spacing.swift`: `xs=4, sm=8, md=16, lg=24, xl=32, xxl=48`). 44pt touch-target floor for shutter / Use-Retake / Retry buttons. Add `DS.Colors.destructive = .systemRed` (UI-SPEC).

### Coordinator retention by `AppCoordinator`
**Source:** `AppCoordinator.swift:21-28` (the `authCoordinator` strong-property comment).
**Apply to:** `KYCCoordinator`.
`AppCoordinator` MUST keep a strong `private var kycCoordinator: KYCCoordinator?` or the coordinator deallocates right after `makeRoot` and its callbacks are orphaned. This was a real Phase-3 bug.

---

## No Analog Found

Files with no close in-repo match — planner should use RESEARCH.md patterns:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `Core/Identity/Capture/GPSMetadataInjector.swift` | utility | transform | No EXIF/ImageIO/CoreGraphics code exists in the repo. The `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` primary path + `CGImageSource`/`CGImageDestination` fallback come from RESEARCH Pattern 3 / Pitfall 6. The only in-repo constraint that applies: coordinates route through `Core/Identity/PlatformPayloadField` (GEO-03), never `LogField`. |
| `Core/Identity/KYC/ArtifactUploadState.swift` | model | — | No persisted per-chunk progress model exists. It is a plain `Codable` struct (artifactType, uploadID, totalChunks, chunksAcked, stable per-chunk idempotency keys). Closest *spirit* is `AppSession` as a state holder, but the shape is novel. Persisted by `KYCSessionStore`. |
| `FaceCaptureViewController` / `DLFrontScanViewController` camera+scanner bodies | view-controller | streaming | The UIKit VC *scaffold* copies from `OTPViewController`, but the `AVCaptureSession` / `AVCaptureVideoPreviewLayer` / `VisionKit.DataScannerViewController` interaction has no in-repo analog. Use RESEARCH Patterns 1-2. Not simulator-testable — device CI / HUMAN-UAT. |

---

## Metadata

**Analog search scope:** `validationLedger/{App,Core,Features,Roles,UI}/`, `validationLedgerTests/`, `validationLedgerTests/Networking/Fixtures/`.
**Files scanned:** 24 Swift sources read in full + 8 KYC fixture files inspected.
**Pattern extraction date:** 2026-05-16
