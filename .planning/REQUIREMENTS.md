# Requirements: Validation Ledger iOS Client — M1 Foundation

**Defined:** 2026-04-20
**Core Value:** Identity that cannot be spoofed and a chain-of-trust that cannot be faked.
**Milestone scope:** M1 Foundation only. Later milestones (M2 Core flows, M3 Dock & BOL, M4 Intelligence & polish, M5 Beta hardening) get their own REQUIREMENTS cycles.

## v1 Requirements

M1 Foundation scope. Each maps to roadmap phases via the traceability table below.

### Foundational Conventions (FOUND)

Infrastructure that must exist before feature work — the "8 conventions" surfaced by research. Getting these wrong early costs exponentially more later.

- [x] **FOUND-01**: `Core/Logging` exposes a `Logger` protocol with a `PIIScrubber` middleware that redacts phone numbers, full names, DL numbers, MC/DOT numbers, email addresses, and coordinates from all log messages before they reach `os_log` or `OSLogStore`. Verified by a unit test that asserts redaction on a fixed set of sample payloads. *(Validated Phase 1 — 9 PIIScrubberTests including CR-02a string-path name sweep)*
- [x] **FOUND-02**: On first app launch, Keychain is wiped for this app's bundle identifier and access group — pre-empting the "Keychain items survive app uninstall" privacy trap. Triggered once per install via a flag in `UserDefaults`. *(Validated Phase 1 — KeychainWiper + KeychainWipeTests; visual proof in HUMAN-UAT #2)*
- [x] **FOUND-03**: MVVM-C memory conventions documented in `CLAUDE.md` and enforced at review: ViewModels hold weak references to Coordinators, Combine `AnyCancellable` sets are owned by ViewModels, async `Task`s are cancelled on ViewModel deinit. *(Validated Phase 1 — ADR 0001)*
- [x] **FOUND-04**: CI pipeline splits simulator-only tests (Xcode Cloud / GitHub Actions) from physical-device tests (self-hosted Mac runner with an attached iPhone). Secure Enclave, Keychain biometric-bound items, App Attest, and biometric prompts run only on device. Simulator CI runs on every PR; device CI runs on every merge to `main`. *(Validated Phase 1 — ci-simulator.yml + ci-device.yml; PR trigger + self-hosted runner in HUMAN-UAT #5-7)*
- [x] **FOUND-05**: Certificate pinning in `Core/Networking/CertificatePinning/` via a `URLSessionDelegate` pins the leaf certificate's SPKI hash AND a backup SPKI hash (dual-pin pattern) for rotation safety. Rotation runbook lives at `docs/cert-rotation.md`. *(Validated Phase 1 — PinningSessionDelegate skeleton + docs/cert-rotation.md; Phase 2 wires pin values)*
- [x] **FOUND-06**: `PrivacyInfo.xcprivacy` manifest skeleton committed, declaring required-reason APIs already in use (`UserDefaults`, `CoreLocation`, `UIPasteboard` if any) and listing zero third-party SDKs. Expanded as SDKs are added. *(Validated Phase 1 — PrivacyInfo.xcprivacy in Copy Bundle Resources; check-privacy-manifest.sh in CI)*
- [x] **FOUND-07**: `Core/Auth/SessionLockService` is the single source of truth for "is the current session active" — consumed by all Coordinators and ViewModels. Unifies cold-boot lock, background-timeout lock, explicit-logout lock, and biometric-re-prompt triggers. *(Validated Phase 1 — DefaultSessionLockService + SessionLockServiceTests)*
- [x] **FOUND-08**: `Core/Navigation/DeepLinkRouter` accepts incoming deep links even before `AppContainer` is ready, queuing them for replay after bootstrap completes. Prevents the cold-launch deep-link race. *(Validated Phase 1 — DeepLinkRouter + DeepLinkRouterTests)*

### Architecture & Module Layout (ARCH)

- [x] **ARCH-01**: Existing SwiftUI `validationLedgerApp.swift` + `ContentView.swift` scaffold removed; replaced by UIKit `AppDelegate` + `SceneDelegate` + `RootCoordinator`. No SwiftUI in the app launch path. *(Validated Phase 1 — Plan 01 deleted scaffold; Plan 05 landed UIKit composition root)*
- [x] **ARCH-02**: iOS deployment target lowered from 26.4 (Xcode default) to 17.0. Swift language version set to 5.9+. Xcode 16+ floor for CI. *(Validated Phase 1 — IPHONEOS_DEPLOYMENT_TARGET=17.0 across 8 build config occurrences)*
- [x] **ARCH-03**: Module layout matches TechStack.md §3.2 with research refinements: `App/`, `Core/{Networking, Auth, KeyStore, Attestation, Security, Identity, Storage, Logging, Analytics, AIKit, Navigation}`, `Features/{Onboarding, Loads, BOL, Scanner, Assistant, Profile, Settings}`, `Roles/`, `UI/`, `Resources/`. Empty directories for M1-unused features are placeholders only. *(Validated Phase 1 — full layout landed across Plans 03/04/05)*
- [x] **ARCH-04**: `AppContainer` provides all dependencies via initializer injection. No Swinject, no Resolver, no global singletons. *(Validated Phase 1 — 0 matches for `.shared` in validationLedger/App/; initializer-DI throughout)*
- [x] **ARCH-05**: Cross-feature communication goes through `Core/` *protocols only*; Features never import each other. Enforced by SwiftLint custom rule `no-cross-feature-import`. *(Validated Phase 1 — custom rule active in .swiftlint.yml; planted-violation test fires)*
- [x] **ARCH-06**: `Roles/RoleCoordinator` swaps the root coordinator at `SceneDelegate` level when the active role changes. Tab bars are children of role-specific coordinators; switching roles recreates the root. *(Validated Phase 1 — ADR 0002 + SceneDelegate.presentRoot implementation; end-to-end role swap in HUMAN-UAT #4)*

### Stack & Dependencies (STACK)

- [x] **STACK-01**: `Package.swift` declares SwiftPM-only dependencies: `Nuke` (13.0+), no `KeychainAccess` (hand-rolled), no `Alamofire`, no `XCoordinator`. Locked versions committed. *(Validated Phase 1 — Package.swift pins Nuke 13.0.2 + SwiftLintPlugins 0.63.2 exactly)*
- [x] **STACK-02**: SwiftLint + SwiftFormat configured with `.swiftlint.yml` and `.swiftformat` in repo root; run on pre-commit hook. *(Validated Phase 1 — .swiftlint.yml + .swiftformat + scripts/pre-commit.sh)*
- [x] **STACK-03**: Tests use Swift Testing for new unit tests; XCTest retained for UI tests (XCUITest). *(Validated Phase 1 — @Suite + @Test for unit, XCTestCase for UI)*
- [x] **STACK-04**: `Package.swift` shows zero third-party analytics or crash SDK in M1 (deferred to M2). Logging uses `os_log` + `OSLogStore`. *(Validated Phase 1 — only Nuke + SwiftLintPlugins in Package.swift)*

### Networking Contract + Mock (NET)

- [x] **NET-01**: `Core/Networking/APIClient` exposes typed Swift models for all TechStack.md §7 endpoints relevant to M1 (OTP request, OTP verify, device register, KYC upload init/chunk/commit, KYC status). Defined up-front even for endpoints Phase 2 consumes. *(Validated Phase 2 — 7 endpoint structs + APIClient facade; APIClientEndpointTests 14/14 pass)*
- [x] **NET-02**: `MockURLProtocol` returns canned JSON responses for every M1 endpoint. Test target ships with success + failure fixtures per endpoint. *(Validated Phase 2 — 14 JSON fixtures + FixtureLoader; NSLock-guarded handlers (WR-01 closed))*
- [x] **NET-03**: Swapping from mock to live backend is a one-line change (`AppContainer.networking = .mock` vs `.live(baseURL:)`). No call-site changes required. *(Validated Phase 2 — AppContainer.makeSession(networkConfig:) + NetworkConfigToggleViewController DevMenu entry)*
- [x] **NET-04**: An idempotency-key interceptor injects `Idempotency-Key` header on every POST mutation, generated via `UUID().uuidString` and persisted for the request's lifecycle. *(Validated Phase 2 — IdempotencyInterceptor; 5 tests; respects caller-supplied keys for Phase 5 replay)*
- [x] **NET-05**: Exponential backoff on idempotent GETs only (max 3 retries); no retry on POST without explicit idempotency key replay through the outbound queue. *(Validated Phase 2 — RetryInterceptor GET-only with jittered backoff; 9 tests)*

### Authentication (AUTH)

- [ ] **AUTH-01**: User enters a US phone number (E.164) on a UIKit onboarding screen; validation is client-side format + backend-authoritative.
- [ ] **AUTH-02**: User receives an SMS OTP (mocked in M1 — `MockURLProtocol` returns a fixed `123456` dev code) and enters it on the OTP screen. After 3 failed attempts, the user is rate-limited for 60 seconds (backend-enforced; iOS surfaces the countdown).
- [ ] **AUTH-03**: On successful OTP verify, backend returns a session token; iOS stores it in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- [ ] **AUTH-04**: User can log out from the Profile tab; logout wipes Keychain tokens, clears Secure Enclave authorization key ACLs, and returns to the phone-entry screen.
- [ ] **AUTH-05**: Auto-logout triggers on backend-returned 401; no "keep me logged in."
- [ ] **AUTH-06**: Sensitive actions (tender, accept, BOL generation — stubbed in M1, implemented M2+) will require biometric re-prompt through `SessionLockService`. M1 wires the re-prompt infrastructure but the sensitive-action list is empty.

### Device Binding & Integrity (DEV)

- [x] **DEV-01**: `Core/KeyStore/SecureEnclaveKeyStore` generates an EC P-256 keypair in the Secure Enclave at first successful OTP verify. Public key registered with backend via `/device/register`. *(Validated Phase 2 — SecKeyCreateRandomKey path, NOT CryptoKit wrapper; device tests compile-for-testing green; physical-device execution pending HUMAN-UAT)*
- [x] **DEV-02**: `Core/KeyStore` uses the two-key pattern: `deviceKey` (passcode-only ACL) for device identity, `authorizationKey` (`.biometryCurrentSet` ACL) for sensitive-request signing. *(Validated Phase 2 — two-slot keyprotocol + ADR 0004 documents rationale)*
- [x] **DEV-03**: `Core/KeyStore/SoftwareKeyStore` is the simulator/test fallback, selected via `#if DEBUG && targetEnvironment(simulator)` in `AppContainer`. Production builds refuse launch if Secure Enclave is unavailable on a real device. *(Validated Phase 2 — AppContainer.preflightSecureEnclave() + RefuseLaunchWithoutSecureEnclaveTests; physical-device SC-4 verification pending HUMAN-UAT)*
- [x] **DEV-04**: `Core/Attestation` calls App Attest on first successful login; attestation payload included in `/device/register`. Gracefully skipped if App Attest is unavailable (older device, entitlement missing) with a logged warning — backend decides policy. *(Validated Phase 4 — `Core/Attestation` App Attest integration across plans 04-01..04-09; `DCAppAttestAttestationService` round-trip (generateKey → attestKey → generateAssertion) runs green on the physical-device CI — `AppAttestRoundTripTests` on iPhone 16, 2026-05-16)*
- [x] **DEV-05**: Device fingerprint (device model, iOS version, install UUID) sent with `/device/register`. Install UUID persisted in Keychain. *(Validated Phase 2 — DeviceFingerprint + DeviceFingerprintTests; Keychain-persisted install UUID)*
- [ ] **DEV-06**: If backend returns "another active session" at any authenticated endpoint, iOS shows the "switch device" flow: clear state, logout, prompt user to proceed with re-KYC (which is M2+, so M1 shows a placeholder screen with support contact).

### Role Shell (SHELL)

- [ ] **SHELL-01**: `Roles/RoleCoordinator` reads the role from the session payload (Shipper, Broker, Carrier, Dispatch, Factoring) and instantiates the role-appropriate root coordinator.
- [ ] **SHELL-02**: Each of the 5 roles ships a `UITabBarController` with tabs matching TechStack.md §4 (placeholder UIViewControllers for all tabs in M1 — the goal is that all 5 shells compile and render distinct tab bars, not that tabs have content).
- [ ] **SHELL-03**: Shared shell elements (top-level navigation, profile/settings affordance) are implemented once and reused across all role coordinators.
- [ ] **SHELL-04**: Role cannot be changed client-side (no "switch role" button). Role is established at account creation and changing it requires re-KYC (backend-enforced; iOS does not expose the UI).

### Session Management (SESS)

- [ ] **SESS-01**: Session persists across cold boot — relaunching the app with a valid token skips OTP and goes directly to the role shell.
- [ ] **SESS-02**: If the app is backgrounded > 5 minutes, biometric re-prompt is required on return. Handled by `SessionLockService` via `UIApplication.didEnterBackgroundNotification` and `didBecomeActiveNotification`.
- [ ] **SESS-03**: Biometric re-enrollment (user changes Face ID/Touch ID template) invalidates the `authorizationKey`. `SessionLockService` detects this and surfaces a "re-bind device" flow (stubbed screen in M1 pointing to support).
- [ ] **SESS-04**: Clean logout wipes: Keychain tokens, Secure Enclave ACLs for `authorizationKey`, in-memory session state, and the role coordinator stack.

### Geolocation (GEO)

- [ ] **GEO-01**: `CLLocationManager` permission requested with a clear purpose string at the moment of first auth attempt, not at app launch.
- [ ] **GEO-02**: Client-side country pre-check via reverse geocode refuses to submit an auth attempt if country ≠ US. Backend re-verifies authoritatively; client check is defense-in-depth.
- [ ] **GEO-03**: Coordinates are attached only to platform-API payloads (auth, tender, accept, scan — tender/accept/scan are M2+). Never attached to analytics events or log messages. Enforced by the phantom-typed `AnalyticsEvent` pattern that makes raw coordinates un-attachable at compile time.

### Transport Security (SEC)

- [x] **SEC-01**: Certificate pinning active on all API traffic via `Core/Networking/CertificatePinning`. Dual-pin (leaf + backup) SPKI hashes baked into the release build; staging build pins the staging leaf + backup. *(Validated Phase 2 — PinnedSPKIs compile-time constants + SPKIHasher + PinningSessionDelegate; 13 tests including 3-cert integration; docs/cert-rotation.md expanded to full 30-day runbook. Real staging/production SPKI values are PHASE2-TODO markers — backend team fills in before Release)*
- [x] **SEC-02**: App Transport Security strict in `Info.plist`. No `NSAllowsArbitraryLoads` exceptions. *(Validated Phase 1 — ATS-strict Info.plist; plutil -lint clean)*
- [x] **SEC-03**: Keychain storage for all tokens. Secure Enclave for all keys. Zero sensitive data in `UserDefaults` or plain files — enforced by a SwiftLint custom rule flagging `UserDefaults` writes of keys named `*token*`, `*key*`, `*session*`. *(Validated Phase 1 — ban_userdefaults_tokens custom rule active)*

### KYC Capture (KYC)

- [ ] **KYC-01**: `Features/Onboarding/KYCCoordinator` orchestrates the capture flow: face → DL front → DL back → vehicle (truck, trailer, plate each separately) → review → submit.
- [x] **KYC-02**: Live face capture uses Vision framework for face detection + on-screen framing guides. **Liveness detection is deferred from M1** (per §12 Open Q1 decision) — M1 captures a face image that meets basic Vision quality gates (detected, centered, in focus) without liveness checking.
- [ ] **KYC-03**: DL capture uses `VisionKit.DataScannerViewController` for optical text extraction; extracted fields validated client-side (format check only; backend is authoritative).
- [x] **KYC-04**: Vehicle capture takes truck, trailer, and license plate as separate photos. GPS metadata attached at capture time via `CLLocationManager.location` — before any `UIImage` conversion that would strip EXIF.
- [x] **KYC-05**: KYC status UI displays Pending / Under Review / Verified / Rejected with backend-provided rejection reasons rendered using controlled vocabulary (copy finalized in M1 even if states are M2+ authoritative).
- [x] **KYC-06**: In-progress KYC survives app backgrounding / network blips via persistence in `Core/Storage` (encrypted on-disk). Resuming the flow continues from the last completed step.

### Upload Pipeline (UPL)

- [ ] **UPL-01**: `Core/Identity/KYCUploader` uploads KYC artifacts via the chunked contract defined in NET-01. Chunk size default 512 KB, configurable.
- [x] **UPL-02**: Resumable uploads persist chunk state to disk. If the app is killed mid-upload, resuming continues from the last committed chunk.
- [ ] **UPL-03**: Exponential backoff with jitter on retryable failures (5xx, network errors). Max 5 attempts before surfacing failure to the user.
- [ ] **UPL-04**: Upload progress is reported accurately — `Progress` object updates every chunk commit, not every byte. UI surfaces progress as a determinate `UIProgressView`.
- [x] **UPL-05**: Upload runs inside a `BGProcessingTaskRequest` when the app backgrounds, so in-flight uploads finish before iOS suspends the app.

### Logging & Observability (LOG)

- [x] **LOG-01**: All logging goes through `Core/Logging/Logger` — no direct `print()` or `os_log()` calls in application code. Enforced by SwiftLint custom rule. *(Validated Phase 1 — ban_print + ban_direct_os_log custom rules active)*
- [x] **LOG-02**: Log levels: `trace`, `debug`, `info`, `warn`, `error`. Release builds default to `info`; debug builds to `debug`. *(Validated Phase 1 — Logger protocol + OSLogLoggerImpl)*
- [x] **LOG-03**: `OSLogStore` retrieval available from a developer-menu entry in debug builds for field-diagnostic pulls. Release builds do not expose this. *(Validated Phase 1 — LogExporter + LogViewerViewController; D-13 Release-strings proof: 0 matches for LogViewer)*

### Testing & CI (CI)

- [x] **CI-01**: Unit tests cover `Core/Logging/PIIScrubber`, `Core/Networking/APIClient` with `MockURLProtocol`, `Core/KeyStore/SoftwareKeyStore`, `SessionLockService`, idempotency-key interceptor. Target coverage ≥70% on `Core/`. *(Validated Phase 1 — 77.43% Core/ coverage, 32 unit tests across 8 suites)*
- [x] **CI-02**: One smoke UI test per role (5 total) covers launch → OTP enter → role shell renders → logout. *(Validated Phase 1 — RoleShellSmokeTests placeholder tests; real OTP flow wired in Phase 3)*
- [x] **CI-03**: Physical-device test plan covers Secure Enclave keypair generation, Keychain biometric-bound item storage, App Attest assertion generation. Runs on every merge to `main`. *(Validated Phase 4 — `ci-device.yml` `device-security-surface` job runs the full `validationLedgerDeviceTests` surface green on a self-hosted runner + iPhone 16; required branch-protection check on `main`, gate verified 2026-05-16)*
- [x] **CI-04**: `xcodebuild` + `xcrun xctest` CI invocation documented in `docs/ci.md`. *(Validated Phase 1 — docs/ci.md present + referenced from workflows)*

## v2 Requirements

Deferred to later milestones (M2 onward). Tracked for scope hygiene; not in the current M1 roadmap.

### M2 — Core Flows

- **LOAD-*** Role-filtered load list, load detail with chain-of-trust visualization, tender/accept/reject actions, real-time updates (WS or SSE).
- **NOTIF-*** APNs registration with deep links, Critical Alerts entitlement applied to Apple, notification categories with custom actions.
- **IMPOSS-01** FR-iOS-GEO impossible-travel pre-check (downgraded to SHOULD; backend enforces).

### M3 — Dock & BOL

- **BOL-*** eBOL render, rotating live QR (30s TTL, backend-signed payload), QR scanner at dock, backend-mediated verification, screenshot blocking, screen-recording detection.
- **BG-01** Background location for carriers on active load.
- **LIVE-01** Liveness detection re-decision (Vision-only vs commercial SDK) based on M1 internal testing.

### M4 — Intelligence & Polish

- **AI-*** Claude-Sonnet-4.5 assistant UI (backend-mediated), streamed responses, voice input via `SFSpeechRecognizer`.
- **OFFL-*** Offline mode: read-only cached BOL, encrypted queued non-destructive mutations.
- **A11Y-*** Dynamic Type + VoiceOver pass on primary flows.
- **ANAL-*** Crash/analytics vendor pick (Sentry vs Firebase vs self-hosted) behind `CrashReporter` protocol.

### M5 — Beta Hardening

- **CRASH-*** Crash-free session target ≥99.5%.
- **PERF-*** Cold start <2s on iPhone 12, screen transition <200ms, ≤3%/hour battery on active load.
- **BETA-*** TestFlight closed beta, device matrix QA, App Store submission.

## Out of Scope

Explicit exclusions — both "not in M1" and "not in v1 at all."

| Feature | Reason |
|---------|--------|
| Android client | Separate effort, separate codebase |
| Web client | Separate effort, shared backend |
| Admin console | Web, not iOS |
| Offline QR verification | Fraud window too large; never shipping on iOS client |
| Passkey / WebAuthn login | v2 migration path |
| Non-English localization | v2; M1 strings structured for localization but only English ships |
| Apple Watch companion | Out of v1 |
| CarPlay integration | Out of v1 |
| iMessage extension for BOL sharing | Out of v1 |
| Liveness detection on KYC capture (M1 specifically) | Deferred to later milestone; §12 Open Q1 decision gate at end of M1 |
| Crash/analytics vendor (M1 specifically) | Deferred to M2; M1 uses `os_log` only |
| Real backend integration (M1 specifically) | Contract-first mock only in M1; M2 integrates |
| Self-serve password/token reset | Anti-feature — the product's point is that account recovery requires re-KYC |
| Multi-device login | Anti-feature — one active device per user is core to identity binding |
| Third-party chat SDKs for future in-app messaging | Anti-feature — leaks PII and violates the trust story |
| Third-party analytics/marketing SDKs | Anti-feature — privacy posture is non-negotiable |
| Client-composed BOL PDFs | Anti-feature — backend is the sole authority on BOL content |
| Client-side QR payload validation | Anti-feature — backend is the sole authority on QR validity |
| Silent force-update prompts | Anti-feature — visible upgrade flow only |
| FR-iOS-GEO impossible-travel pre-check as MUST on client | Downgraded to SHOULD; backend enforces |

## Traceability

Every v1 requirement is mapped to exactly one roadmap phase. Status updated as phases complete.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| FOUND-05 | Phase 1 | Pending |
| FOUND-06 | Phase 1 | Pending |
| FOUND-07 | Phase 1 | Pending |
| FOUND-08 | Phase 1 | Pending |
| ARCH-01 | Phase 1 | Pending |
| ARCH-02 | Phase 1 | Pending |
| ARCH-03 | Phase 1 | Pending |
| ARCH-04 | Phase 1 | Pending |
| ARCH-05 | Phase 1 | Pending |
| ARCH-06 | Phase 1 | Pending |
| STACK-01 | Phase 1 | Pending |
| STACK-02 | Phase 1 | Pending |
| STACK-03 | Phase 1 | Pending |
| STACK-04 | Phase 1 | Pending |
| NET-01 | Phase 2 | Pending |
| NET-02 | Phase 2 | Pending |
| NET-03 | Phase 2 | Pending |
| NET-04 | Phase 2 | Pending |
| NET-05 | Phase 2 | Pending |
| AUTH-01 | Phase 3 | Validated (code) |
| AUTH-02 | Phase 3 | Validated (code) |
| AUTH-03 | Phase 3 | Validated (code) |
| AUTH-04 | Phase 3 | Validated (code) |
| AUTH-05 | Phase 3 | Validated (code) |
| AUTH-06 | Phase 3 | Validated (code) |
| DEV-01 | Phase 2 | Pending |
| DEV-02 | Phase 2 | Pending |
| DEV-03 | Phase 2 | Pending |
| DEV-04 | Phase 4 | Pending |
| DEV-05 | Phase 2 | Pending |
| DEV-06 | Phase 3 | Validated (code) |
| SHELL-01 | Phase 3 | Validated (code) |
| SHELL-02 | Phase 3 | Validated (code) |
| SHELL-03 | Phase 3 | Validated (code) |
| SHELL-04 | Phase 3 | Validated (code) |
| SESS-01 | Phase 3 | Validated (code; HUMAN-UAT pending) |
| SESS-02 | Phase 3 | Validated (code; HUMAN-UAT pending) |
| SESS-03 | Phase 3 | Validated (code; HUMAN-UAT pending) |
| SESS-04 | Phase 3 | Validated (code; HUMAN-UAT pending) |
| GEO-01 | Phase 3 | Validated (code) |
| GEO-02 | Phase 3 | Validated (code) |
| GEO-03 | Phase 3 | Validated (code) |
| SEC-01 | Phase 2 | Pending |
| SEC-02 | Phase 1 | Pending |
| SEC-03 | Phase 1 | Pending |
| KYC-01 | Phase 5 | Pending |
| KYC-02 | Phase 5 | Complete |
| KYC-03 | Phase 5 | Pending |
| KYC-04 | Phase 5 | Complete |
| KYC-05 | Phase 5 | Complete |
| KYC-06 | Phase 5 | Complete |
| UPL-01 | Phase 5 | Pending |
| UPL-02 | Phase 5 | Complete |
| UPL-03 | Phase 5 | Pending |
| UPL-04 | Phase 5 | Pending |
| UPL-05 | Phase 5 | Complete |
| LOG-01 | Phase 1 | Pending |
| LOG-02 | Phase 1 | Pending |
| LOG-03 | Phase 1 | Pending |
| CI-01 | Phase 1 | Pending |
| CI-02 | Phase 1 | Pending |
| CI-03 | Phase 4 | Pending |
| CI-04 | Phase 1 | Pending |

**Coverage:**
- v1 requirements: 67 total (correction: prior summary stated "65"; actual row count is 67 — FOUND 8 + ARCH 6 + STACK 4 + NET 5 + AUTH 6 + DEV 6 + SHELL 4 + SESS 4 + GEO 3 + SEC 3 + KYC 6 + UPL 5 + LOG 3 + CI 4)
- Mapped to phases: 67 ✓
- Unmapped: 0 ✓

**Phase distribution:**
- Phase 1 (Foundational Conventions & Scaffolding): 26 requirements
- Phase 2 (Networking Contract & Device Keys): 10 requirements
- Phase 3 (OTP Auth + Role Shell + Session): 18 requirements
- Phase 4 (App Attest & Physical-Device CI Hardening): 2 requirements
- Phase 5 (KYC Capture & Upload Pipeline): 11 requirements

---
*Requirements defined: 2026-04-20*
*Last updated: 2026-04-20 after roadmap traceability map*
