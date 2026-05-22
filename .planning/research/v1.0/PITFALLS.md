# Pitfalls Research — Validation Ledger iOS Client

**Domain:** Identity-verified freight iOS client (security-sensitive, five-role, offline-tolerant, 24-week v1)
**Researched:** 2026-04-20
**Confidence:** HIGH on Secure Enclave / Keychain / cert pinning / Privacy Manifest / CoreLocation API shapes (current Apple docs + WWDC23/24). MEDIUM on App Store review specifics (behavior changes quarterly) and Critical Alerts entitlement acceptance bar. LOW on specific false-reject rates for Vision-only liveness (deferred Open Q1).

**Reading order for the roadmap author:** Critical pitfalls are ordered by milestone cost-to-fix. M1-relevant pitfalls (Secure Enclave, Keychain, cert pinning, PII, MVVM-C, KYC capture, uploads) appear first and are the most load-bearing for the 4-week Foundation milestone. M2-M5 pitfalls follow. Each pitfall lists warning signs + prevention + phase ownership + whether TechStack.md already covers it.

**Legend for "TechStack.md coverage":**
- **Covered** = spec explicitly addresses the pitfall
- **Partial** = spec names the risk but prevention is underspecified
- **Not covered** = spec is silent; roadmap must add it

---

## Critical Pitfalls (M1 Foundation — Weeks 1-4)

### Pitfall 1: Secure Enclave key tied to `.biometryCurrentSet` silently bricks session on biometric re-enrollment

**What goes wrong:**
TechStack.md §8 specifies `.biometryCurrentSet` for the device key "so biometric re-enrollment invalidates the key and forces re-binding." Correct as a security posture, but if the app does not detect the `errSecItemNotFound` / `errSecAuthFailed` code path and surface a recovery flow, the user sees a cryptic login failure. They cannot re-bind without going through re-KYC (per FR-iOS-DEV one-active-device policy). They call support. Support has no playbook.

A second failure mode: the key generated with `.biometryCurrentSet` cannot be retrieved without user-present biometric, which means ANY attempt to sign a request fails silently when Face ID is disabled in Settings → Face ID & Passcode → App Usage. iOS does not emit a clear error; you get `errSecAuthFailed` (-25293).

**Why it happens:**
Documentation of `SecAccessControlCreateFlags` is scattered. Developers pick `.biometryCurrentSet` as the "most secure" option without wiring the invalidation path. Simulator tests pass (simulator biometrics behave differently). Real-device failure appears at beta when the first user changes a Face ID scan.

**How to avoid:**
1. In Phase 1, write a `DeviceKeyService` that explicitly handles three outcomes on every signing attempt: (a) success, (b) `errSecItemNotFound` → trigger re-enrollment flow, (c) `errSecAuthFailed` → show "Face ID required; re-enable in Settings" with deep link to `UIApplication.openSettingsURLString`.
2. Test biometric-invalidation on a physical device by: enroll Face ID → login → settings → remove Face ID → re-enroll → try signed action → must fail cleanly → must offer "re-bind this device" path.
3. Design the **re-bind flow copy before M1 ends** — do not ship the Secure Enclave path without a decision on whether re-bind = re-KYC or a faster recovery. TechStack.md §12 Open Q5 flags this for SIM swap; it applies equally to biometric re-enrollment.
4. Consider using `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` as a pre-flight gate before attempting to fetch the key, so you can show the right message instead of decoding `OSStatus`.

**Warning signs:**
- Internal testing where engineers don't re-enroll Face ID between builds (99% of testing).
- Zero handling of `errSecAuthFailed` in `DeviceKeyService` code.
- No "switch to this device" flow in design.
- Tests pass only on simulator (see Pitfall 15).

**Phase to address:** Phase 1 of M1 (Foundation). Re-bind flow can be a stub dialog + support-link in Phase 1, but the error-code surface must be wired from day one or it becomes invisible tech debt.

**TechStack.md coverage:** **Partial.** §8 picks `.biometryCurrentSet` but does not describe the invalidation UX or `errSecAuthFailed` path. The roadmap must add this.

---

### Pitfall 2: Keychain items surviving app delete leaks prior user identity on reinstall

**What goes wrong:**
iOS Keychain is deliberately persistent across app delete+reinstall. When user A logs out implicitly by deleting the app, then user B reinstalls it on the same device, B gets A's Keychain tokens on first launch — zero-auth access to A's account until the token expires. For an identity-verification product, this is a showstopper: the product's entire premise is that the identity on the device is demonstrably real.

A related leak: even if the token has expired, Keychain-held refresh tokens, device key identifiers, or cached KYC-complete flags can "resurrect" stale identity state.

**Why it happens:**
Default Keychain behavior. Apple tried to change it in iOS 10.3 beta, reverted it because it broke existing apps. The behavior "data survives uninstall" is a side-effect of the implementation, not a feature, but developers reasonably assume the OS cleans up when the app is deleted.

**How to avoid:**
1. On first launch, check a `UserDefaults` boolean `didCompleteFirstLaunch`. `UserDefaults` IS cleared on uninstall. If absent, wipe all Keychain items under the app's access group before any auth work, then set the flag.
2. Scope the Keychain access group deliberately — `$(AppIdentifierPrefix)com.maldin.validationLedger` — and enumerate-then-delete everything under it at first-run wipe. Do not rely on deleting known keys; iterate with `SecItemCopyMatching` + `kSecMatchLimitAll`.
3. Add an explicit "sign out everywhere on this device" Settings action that wipes Keychain + Secure Enclave key handles regardless of server state.
4. On Secure Enclave: the private key reference (`SecKey`) is not recoverable after app delete (the Keychain reference entry is stored with the app's access group, and while the Secure Enclave has the key material, the reference handle is gone), so device-binding naturally re-provisions — but the TOKEN is not auto-cleaned. The token is what leaks.

**Warning signs:**
- No `didCompleteFirstLaunch` logic at app launch.
- `KeychainAccess` wrapper initialized with default accessibility and no access group.
- Manual test: delete the app, reinstall, launch — are you still logged in? If yes, fix before M1 closes.

**Phase to address:** Phase 1 of M1, before Keychain-backed token storage is merged. This is cheap in Phase 1 and extremely expensive later (every session created from M1 → M5 pre-fix inherits the bug).

**TechStack.md coverage:** **Not covered.** §5.1 and §8 reference Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` but do not address the uninstall-persistence gotcha. Critical gap; roadmap must add.

---

### Pitfall 3: Certificate pinning with no rotation plan self-locks out users when cert rotates

**What goes wrong:**
Pinning the leaf certificate's SPKI hash, per FR-iOS-SEC. Backend rotates the TLS cert (routine — Let's Encrypt is 90-day renewal, many CDNs auto-rotate every 60 days). Every installed app copy is now bricked. Users cannot reach the backend to download an update. TestFlight is fine (auto-update), App Store beta is fine (most users on auto-update), production beta 6 months in is catastrophic.

A recent real-world case: Let's Encrypt retired the R3 intermediate in 2024 and auto-renewals switched to R10/R11, bricking every app pinned to R3. Apps pinning the root (ISRG X1) were fine. Apps pinning leaves with no backup pin were dead.

A second failure mode: pinning breaks in staging (different cert) but works in production, so QA signs off on something that will fail on rotation, OR pinning works in production but breaks in staging, so staging is shut off and drift creeps in.

**Why it happens:**
Pinning is easy to implement naively (one `URLSessionDelegate` method, one hash). Rotation plan is not part of "making it work." The first rotation in 6-24 months is when the pain hits.

**How to avoid:**
1. Pin **two** SPKI hashes from day one: the current leaf public key AND a pre-provisioned backup public key that's generated but unused on the server. This is RFC 7469 convention.
2. Prefer pinning an **intermediate or root** (ISRG Root X1 for Let's Encrypt, DigiCert Global Root, whatever) over the leaf for longer rotation windows. Trade-off: wider trust surface, but survives leaf rotation automatically.
3. Build a **remote-kill-switch for pinning**: a signed config endpoint (served from a different CA) that can disable pinning in an emergency. Controversial (pinning without kill switch is safer against MITM, with kill switch is recoverable from bricking) — pick a side explicitly and document.
4. Ship pinning in M1 but put it behind a debug-build-only flag first. Enable pinning on release builds no earlier than M2 when backend cert lifecycle is documented.
5. Write a **cert rotation runbook** before M5: "30 days before production cert expires, deploy new cert with both old+new SPKI pinned in next iOS build, wait for 99% TestFlight update propagation, rotate server cert, remove old pin in next-next build." Document. Test on staging.
6. Pin on `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` → validate against `SecTrustEvaluateWithError` first, then check SPKI hash of `SecTrustCopyKey(trust).map { SecKeyCopyExternalRepresentation($0) }`.

**Warning signs:**
- Single hash in the pinning code.
- No mention of "backup pin" in PRs.
- Staging uses Let's Encrypt, production uses something else — pinning will silently pass QA.
- No reference to rotation in TechStack.md §5.5.

**Phase to address:** M1 Foundation (build the pinning code with dual-pin support from the start). M5 Beta hardening (write and test the rotation runbook).

**TechStack.md coverage:** **Partial.** §5.5 says "with rotation plan documented" but doesn't specify dual-pin, backup hash, or kill-switch. Roadmap must expand.

---

### Pitfall 4: PII leakage through crash logs, analytics events, and URL query params

**What goes wrong:**
Default crash reporter (Sentry, Crashlytics) captures view controller titles, debug descriptions, last user actions, and occasionally `UIAlertController` text. KYC screens with titles like `"Upload DL for +1 415 555 0129"` leak phone numbers. Analytics events named `"kyc_upload_success"` are fine; event payloads with `{ "phone": "...", "dl_last4": "..." }` are disqualifying. URL requests with `?phone=...` show up in every HTTP proxy log, server access log, and crash stack frame. Deep-link payloads (`validationledger://load/LOAD_ID?assignee=phone-number`) leak via Shortcuts, Spotlight, and clipboard auto-suggest.

The product's entire premise is trust. One screenshot of a crash report with a phone number in a bug-tracking tool on a shared Slack channel ends the trust.

**Why it happens:**
Developers log liberally during M1 because errors are frequent; they forget to redact before ship. Analytics/crash SDKs capture more than you realize by default. View controller naming is a habit. URL construction uses query params because POST bodies require more boilerplate. Deep links are typed manually with IDs that happen to be PII.

**How to avoid:**
1. **In M1, build `Core/Logging/` with a PII scrubber from day one.** TechStack.md active item already calls for this. Make it the ONLY log API available — no direct `os_log`, no `print`. Enforce via SwiftLint custom rule or a `@available(*, unavailable)` on top-level `print`.
2. PII scrubber approach: regex pre-emit to redact E.164 phone numbers, SSNs, DL patterns per state, lat/long coordinate pairs, email addresses. Allowlist-based logging for event names, denylist for payload keys (`phone`, `dl`, `lat`, `lng`, `email`, `name`, `address`).
3. Never put PII in URL query strings. All sensitive ids go in POST body or in `Authorization` / `X-Device-Signature` / custom headers.
4. Deep links use opaque load IDs (UUIDs), never PII. Design the deep-link URL format in Phase 1 so the habit sticks.
5. View controller titles do NOT contain PII — use generic titles ("Upload License") and put any identifying context in non-breadcrumb state.
6. When picking a crash vendor in M2 (§12 Open Q7), configure `beforeSend` hook to run through the same scrubber before upload. Test by intentionally crashing with `phone = "+14155550129"` in a local variable — confirm redaction in the dashboard.
7. Analytics events: implement a typed `AnalyticsEvent` enum with compile-time-bounded payload keys. No `[String: Any]` event payloads.
8. Audit EVERY log statement before M5. Grep for `log.info.*phone`, `log.*lat`, `log.*dl`, etc.

**Warning signs:**
- `print()` or `NSLog()` anywhere in the codebase.
- `[String: Any]` payloads to analytics.
- Query params on KYC/auth endpoints.
- Crash vendor chosen without scrubber configuration.
- Screen titles with dynamic user data.

**Phase to address:** M1 Phase 1 (scrubber + logging abstraction) is cheap and load-bearing. M2 (crash vendor integration with scrubber). M5 (full PII audit before App Store submission).

**TechStack.md coverage:** **Partial.** §8 says "no PII in analytics or crash logs" and mentions scrubber middleware. But URL query params, deep link PII, and VC titles aren't called out. Roadmap must expand.

---

### Pitfall 5: MVVM-C + Combine retain cycles leak ViewModels, Coordinators, and Cancellables

**What goes wrong:**
Four distinct leak patterns appear in every MVVM-C + Combine codebase. If not gated early, they compound and the app leaks memory monotonically.

1. **ViewModel → Coordinator strong ref.** ViewModel holds `coordinator` strongly; coordinator holds child coordinators and view controllers that own the ViewModel. Cycle.
2. **`sink` closures capturing self strongly** while `cancellables` is stored on `self`. The cancellable keeps the sink alive; the sink keeps self alive; self owns cancellables. Cycle.
3. **`assign(to:on:)` has no weak variant.** `publisher.assign(to: \.foo, on: self)` captures self strongly. The `AnyCancellable` returned is stored in `self.cancellables`. Cycle.
4. **`@Published` update storms on the main thread**, where changes from background fire `objectWillChange` on whatever queue the assignment happened on, creating `Publishing changes from background threads is not allowed` purple warnings or simply dropped updates.

The app works fine for the first 100 navigations. Then memory creeps, CPU spikes, the kernel starts warning, and users complain about "lag."

**Why it happens:**
Combine's ergonomics reward concise closures that implicitly capture self. The retain-cycle trap is not a compile error. Developers use `assign(to:on:)` because it reads cleanly. Threading issues hide in dev builds because `@Published` silently allows background-thread writes until iOS decides to complain.

**How to avoid:**
1. **House rule: every `sink` closure starts with `[weak self] ... guard let self else { return }`.** Enforce via code review and SwiftLint.
2. **Never use `publisher.assign(to: \.foo, on: self)`.** Write a `assignWeak(to:on:)` extension once, require it everywhere. Or use `sink { [weak self] in self?.foo = $0 }` (more explicit).
3. **Coordinators hold ViewModels; ViewModels hold `weak var coordinator: CoordinatorProtocol?`.** Not the other way. Document in an ADR at the end of Phase 1.
4. **All ViewModels receive their `Scheduler` via DI, and all `@Published` mutations go through `.receive(on: scheduler.mainQueue)` if they come from network calls.** No `DispatchQueue.main.async { self.foo = ... }` — it's a smell.
5. **Every `cancellables: Set<AnyCancellable>` in a ViewModel is cleared in `deinit` via assertion.** Add `assert(cancellables.isEmpty || Thread.isCurrentThread)` or at minimum `#if DEBUG; print("ViewModel deinit"); #endif` so leaks are visible in console during dev.
6. **Use Instruments (Leaks + Allocations) once per phase** — push a screen, dismiss, check that the VM is deallocated. Ten-minute check; saves weeks later.
7. **Prefer async/await for one-shot network work; Combine for UI state only.** Mixing GCD + Combine + async/await is where leaks multiply. TechStack.md §3.4 already says this; enforce.

**Warning signs:**
- `.assign(to: \..., on: self)` anywhere.
- `sink` closures without `[weak self]`.
- `cancellables` declared but never inspected in `deinit`.
- Memory warnings during basic navigation testing.
- Engineers say "it feels slow after a while."

**Phase to address:** M1 Phase 1. The MVVM-C + Combine conventions must be codified before the module proliferation starts. Every feature that ships in M2+ assumes these conventions are in place.

**TechStack.md coverage:** **Not covered.** §3.1 specifies the pattern; §3.4 the concurrency model. Memory-management rules are absent. Roadmap must add.

---

### Pitfall 6: KYC camera pipeline silently strips GPS metadata via `UIImage` conversion

**What goes wrong:**
FR-iOS-KYC requires GPS metadata attached at capture time. Engineer captures a frame from `AVCapturePhotoOutput` → converts to `UIImage` for on-screen preview → saves with `UIImageJPEGRepresentation`. GPS EXIF is gone. The upload succeeds, backend verification accepts the DL photo but cannot correlate location with the verified identity because the location tag was stripped client-side. Fraud detection has a blind spot and nobody notices until an adversary exploits it six months in.

Related failure: engineer adds GPS manually via `CLLocationManager` but the capture happens on a different thread than the location read, and the location is stale by 60+ seconds, or worse, is the wrong location (previous capture's location). Or: the photo is captured while the app is backgrounded waiting for location permission prompt, and the location is never read.

**Why it happens:**
`UIImage` is the obvious abstraction for a view-facing image. Developers don't know that `UIImage` does not carry EXIF. `UIImageJPEGRepresentation` produces clean JPEG with no metadata. Stack Overflow answers conflate "save image with location" with "use `UIImageWriteToSavedPhotosAlbum`" which does preserve EXIF only because the Photos app adds it back, not because `UIImage` retained it.

**How to avoid:**
1. **Capture path: `AVCapturePhotoOutput` → `AVCapturePhoto.fileDataRepresentation()` → `Data`.** Never go through `UIImage` before upload. Render a separate `UIImage` for preview, but upload the raw `Data`.
2. Attach GPS using `CGImageSource` / `CGImageDestination` / `CGImageMetadata`:
   - Read EXIF from raw data, inject `kCGImagePropertyGPSDictionary` with `latitude`, `longitude`, `timestamp`, `horizontalAccuracy`, finalize.
   - Verify server-side expects this structure before shipping.
3. **Cache a fresh `CLLocation` in a `GeoContext` actor** updated by `CLLocationManager` at the start of the KYC flow. The capture step reads from that actor synchronously. Reject the photo if the cached location is older than 30s or accuracy is worse than 100m.
4. **Server-side schema validation must check that EXIF GPS is present** — reject uploads without it. Build this into the mock backend in M1 so the bug is caught in dev, not in prod.
5. Alternative path: upload location as a separate signed field in the multipart body (`X-Capture-Location: lat,lng,timestamp,accuracy` with a device signature). Less coupled to EXIF; easier to validate; preferred for tamper-evidence anyway. But TechStack.md explicitly says EXIF, so do both.
6. Add a unit test that encodes a known image with a known GPS value, runs through the pipeline, decodes EXIF, asserts the value round-trips.

**Warning signs:**
- `UIImage(data: photoData)` before upload.
- `UIImageJPEGRepresentation(...)` or `jpegData(compressionQuality:)` on a `UIImage` before upload.
- No `CGImageMetadataRef` manipulation anywhere.
- Server-side mock does not assert EXIF.
- No staleness check on `CLLocation` before attaching.

**Phase to address:** M1 Foundation (subsequent phase — KYC capture). The capture-to-upload pipeline is the entire product's trust boundary; get this right once.

**TechStack.md coverage:** **Partial.** §5.2 requires GPS metadata at capture time. It doesn't warn about `UIImage` stripping it. Roadmap must add.

---

### Pitfall 7: Resumable upload that isn't actually resumable + exponential backoff that DDOSes your own backend

**What goes wrong:**
"Resumable upload" gets implemented as "POST the whole thing, retry on failure." Under typical dev conditions (WiFi, 2MB images) that works. In the field (dock cell coverage, 10MB raw DL + vehicle photos), a 40% upload that fails at the connection drop restarts from zero. The user tries six times, gets frustrated, gives up. KYC never completes. Funnel collapses.

The backoff-DDOSes-yourself pattern: N phones come back online simultaneously after a regional carrier blip. They all retry with the same backoff schedule (e.g., exponent starts at 1s with 2x multiplier, no jitter). 10,000 phones hit the backend in a synchronized wave at t=1s, t=3s, t=7s, t=15s. Backend is fine for baseline load but gets swamped by the synchronized retry.

Progress bars that lie: the upload stream reports bytes written to a buffer, not bytes acknowledged by the server. User sees 100%, it hangs for 30s while the server processes, then errors. Feels broken.

Background task extension: `beginBackgroundTask` gives you ~30s of continued execution. If the user backgrounds the app mid-upload, iOS kills it before the upload completes. The upload appears to have succeeded (progress bar said so) but the server never got the final bytes.

**Why it happens:**
Real resumable upload is hard. `URLSession` background uploads are NOT resumable by default for uploads (downloads are). You have to implement chunking + tracking. Exponential backoff without jitter is the textbook example. Progress reporting from URLSession gives you byte-level, not request-level. `beginBackgroundTask` is the documented pattern but it's time-limited.

**How to avoid:**
1. **Chunk the upload into ≤1MB chunks** each with an `Idempotency-Key` header. Store chunk state (index, hash, uploaded-bool) in CoreData/SQLite. On resume, query what's uploaded, re-send what isn't. Backend exposes a `PUT /upload/:id/chunks/:index` endpoint that's safe to retry.
2. **Use `URLSessionConfiguration.background(withIdentifier:)`** so iOS manages resumption across app suspend/relaunch. iOS will relaunch the app in the background when the upload completes and fire `URLSessionDelegate.urlSessionDidFinishEvents(forBackgroundURLSession:)`. TechStack.md's "never lose an in-progress KYC to a network blip" requires this.
3. **Backoff with jitter**: `delay = min(cap, base * 2^attempt) * randomDouble(0.5, 1.5)`. Cap at 5 minutes. Reset on successful response. Randomization prevents synchronized retry storms.
4. **Idempotency-Key header on every chunk request and every create-KYC-submission request.** Generate UUID client-side; backend stores the key. Retries with same key get cached response, never create a duplicate.
5. **Progress from server ack, not client buffer.** Report upload progress as `chunksAcked / totalChunks`, not `bytesWritten / totalBytes`. Only bump the progress bar when the server confirms.
6. **Don't use `beginBackgroundTask` for uploads.** Use background URLSession as primary. `beginBackgroundTask` is acceptable only as a flush-and-finish on app termination.
7. **Server-side: log `Idempotency-Key` collisions and alert on repeat rates > baseline** — if you see surge patterns, the client backoff is wrong.

**Warning signs:**
- Upload implemented as a single `URLSessionUploadTask` with the whole file.
- No `Idempotency-Key` header in any request.
- `base * 2^attempt` with no jitter.
- Progress from `didSendBodyData` delegate alone.
- `beginBackgroundTask` as the primary background strategy.

**Phase to address:** M1 Foundation (subsequent phase — upload pipeline). The upload spec is explicitly a MUST in §5.2; the chunking architecture must be decided in M1 because it shapes the backend contract.

**TechStack.md coverage:** **Partial.** §5.2 says "resumable, retry with exponential backoff, progress visible." Doesn't say chunked, jittered, idempotency-keyed, background-session. Roadmap must add these specifics as acceptance criteria.

---

### Pitfall 8: Secure Enclave unavailable in simulator; developer testing falsely green

**What goes wrong:**
`SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave` fails on simulator (Secure Enclave is hardware-only). Engineer adds a `#if targetEnvironment(simulator)` fallback to a keychain-only RSA key. Fallback code is written quickly, barely tested. It diverges from real-device behavior. Bug reports only appear on device. Tests that pass in CI (iOS Simulator) don't catch real regressions.

Worse: engineer adds the fallback globally (not just dev) "to keep things working" and the production build uses software keys on some devices, silently undermining the device-binding security premise.

**Why it happens:**
Xcode's default test target is simulator. CI typically runs simulator tests. Physical-device CI is expensive. The path of least resistance is simulator-always.

**How to avoid:**
1. **Declare simulator as second-class for security code.** `DeviceKeyService` throws `SecureEnclaveUnavailable` on simulator; dev builds skip the signing requirement via a `#if DEBUG` capability flag, NEVER in release.
2. **Enforce `FR-iOS-DEV` MUST: "refuse production login if Secure Enclave unavailable."** This means production builds crash-on-launch if `SecureEnclave.isAvailable` returns false on simulator (and the simulator refuses to run release builds — acceptable).
3. **CI runs two pipelines**: (a) unit tests on simulator (fast, excludes security code), (b) smoke tests on real-device farm (BrowserStack App Automate, AWS Device Farm, or a Mac mini + attached iPhone) gating PR merge for any change touching `Core/Auth/`, `Core/Security/`, `Core/Identity/`.
4. **Don't even attempt a fallback keypair on simulator.** Use a hardcoded "developer session" shim on simulator — no signing, the mock backend accepts unsigned dev requests.
5. **XCTest-skip annotation:** `throw XCTSkip("Requires Secure Enclave")` for tests that need the real thing. Makes gaps visible.

**Warning signs:**
- `#if targetEnvironment(simulator)` branching inside `Core/Auth/` or `Core/Security/`.
- Passing tests on simulator, missing tests on device.
- No "real device required" CI job.
- Engineers don't know which tests ran on device vs. simulator.

**Phase to address:** M1 Phase 1. The simulator-vs-device split must be declared in the testing strategy before security code is written.

**TechStack.md coverage:** **Partial.** §5.3 says refuse production login if Secure Enclave unavailable. Doesn't specify dev/sim/CI split. Roadmap must add.

---

### Pitfall 9: MVVM-C projects that silently become "Massive ViewModel"

**What goes wrong:**
MVVM starts clean: small ViewModels, clear Coordinators, dumb Views. By M3, the Load Detail ViewModel is 800 lines with eight Combine publishers, three `@Published` properties that depend on six inputs, a nested switch on load status, an embedded eBOL fetch, and a local subscription to real-time updates. Tests are hard to write. Bugs compound. Engineers start dreading the file. Adding a new role-specific action takes a day because the ViewModel is too tangled.

**Why it happens:**
MVVM has no teeth. Nothing stops a ViewModel from growing. The Coordinator boundary only governs navigation. Without sub-domain abstractions (repositories, use cases, services), the ViewModel becomes the dumping ground for everything. With 1-2 engineers, nobody refactors until it's too late.

**How to avoid:**
1. **Draw a hard line: ViewModels do not do I/O.** All network, disk, keychain, location calls go through injected services (`AuthService`, `LoadRepository`, `GeoService`). ViewModels orchestrate services and transform outputs for views. Services are tested independently.
2. **Per-screen budget: ViewModel < 300 lines.** Enforce via SwiftLint `file_length`. When exceeded, the ViewModel either splits (extract a sub-VM for a sub-section) or extracts to a service.
3. **Use Swift Concurrency for one-shot async work**, Combine only for reactive UI streams. Mixing them in every VM doubles complexity.
4. **Repository pattern for all data access**, with an interface + mock + live implementation. TechStack.md §3.2 already calls for "repository interfaces" in each feature module — enforce at PR review.
5. **Coordinators are dumb too.** Just navigation. If a Coordinator accumulates business logic, split it.
6. **Weekly architectural review in M1-M3** — review one VM per week, score on lines/responsibilities/testability. This is cheap and catches rot early.

**Warning signs:**
- Any ViewModel > 400 lines.
- ViewModels that directly call `URLSession` or `Keychain` APIs.
- No mock services for testing (ViewModels tested by mocking `URLSession`).
- PR diffs where a "small feature" touches a 500-line ViewModel.

**Phase to address:** M1 Phase 1 (repository pattern + service boundaries). M2 (first real features — re-evaluate). M3 (mid-project review to prune).

**TechStack.md coverage:** **Partial.** §3.1 + §3.2 describe MVVM-C and module layout. Doesn't enforce VM size, service boundaries, or review cadence. Roadmap must add.

---

### Pitfall 10: Session persistence across cold boot silently reveals session without biometric

**What goes wrong:**
TechStack.md: "Session persistence across cold boot + clean logout + >5min background → biometric re-prompt." Typical implementation: `AppCoordinator` at launch checks Keychain for token → if present, routes to home. User who got the phone stolen has the attacker open the app — token is there — attacker sees the chain-of-trust, the KYC status, the loads, the eBOL. No biometric prompt because the app thinks it's a routine cold boot.

The implementation misses that "cold boot" and "backgrounded > 5 min" both imply the same security state: un-authenticated session. The `>5 min` check happens in `applicationWillEnterForeground`, which doesn't fire on cold launch.

**Why it happens:**
Two separate code paths (`didFinishLaunching` and `willEnterForeground`) each implement "maybe show biometric prompt" in isolation. The shared invariant ("show biometric if last successful biometric >5min ago OR cold boot") is never declared in one place.

**How to avoid:**
1. **Single source of truth**: `SessionLockService.shouldRequireBiometric` reads a `lastBiometricSuccessTimestamp` from Keychain, compares to wall clock. Called unconditionally on every app activation, whether cold or warm.
2. **Guard the root UI**: root `UINavigationController` starts with an opaque lock screen that blocks all content until biometric succeeds. On cold launch: show lock screen, then evaluate `SessionLockService`. If biometric passes, reveal content. If not, route to re-login.
3. **Test matrix**: cold launch with valid token (must prompt), background 10 minutes then foreground (must prompt), background 2 minutes then foreground (must not prompt), unlock phone fresh after > 1 hour (must prompt).
4. **Clipboard/screenshot hygiene during lock**: while the lock screen is displayed, sensitive surfaces below are not rendered. Use the lock screen also as the "app switcher preview" placeholder (set `window.isHidden = true` or install a privacy screen view on `willResignActive`).

**Warning signs:**
- Separate code paths in `AppDelegate.didFinishLaunching` and `SceneDelegate.sceneWillEnterForeground` implementing biometric prompts.
- No `SessionLockService` abstraction.
- No privacy-screen overlay on app switcher.
- QA does not test cold-boot re-auth.

**Phase to address:** M1 Phase 1 (session lifecycle is core to the role-switched tab shell).

**TechStack.md coverage:** **Partial.** §5.1 lists the requirements but doesn't call out the single-source-of-truth invariant. Roadmap must add.

---

## Critical Pitfalls (M2-M5)

### Pitfall 11: iOS 17 vs iOS 18 CoreLocation API divergence — `CLServiceSession` / `CLLocationUpdate.liveUpdates`

**What goes wrong:**
iOS 17 introduced `CLLocationUpdate.liveUpdates` (async sequence of updates). iOS 18 introduced `CLServiceSession` (explicit session object you must hold to keep background updates alive). Different semantics. On iOS 17 with "when in use," iterating `liveUpdates` mostly works. On iOS 18, iterating `liveUpdates` without a `CLServiceSession(authorization: .always)` for background or the app goes to background and updates silently stop.

A second gotcha: on iOS 17, `liveUpdates` returns nothing when `fullAccuracy` is denied. On iOS 18, it returns reduced-accuracy updates. So a user with "precise location off" gets no updates at all on iOS 17, breaking carrier background tracking for a known minority of users.

The classic pre-iOS-17 API (`CLLocationManager.startUpdatingLocation` + delegate) still works but is deprecated in the new docs; mixing paradigms creates subtle bugs.

**Why it happens:**
TechStack.md targets iOS 17+. Both iOS 17 and iOS 18 are in scope. The APIs differ. Training data and Stack Overflow lean heavily on the old delegate API.

**How to avoid:**
1. **Pick one API path**: either classic delegate API (well-documented, works on all iOS 17+) or new async-sequence API (iOS 17.4+ for full behavior). Don't mix within the same feature.
2. **Recommend: classic `CLLocationManager` + delegate for M3 carrier background tracking.** The new API matures in iOS 18. Target iOS 17 correctly, upgrade in v1.1.
3. **iOS 17 specific: handle `fullAccuracy` denied explicitly.** If denied, show a "need precise location on while on trip" prompt deep-linking to Settings.
4. **Test on both iOS 17.x and iOS 18.x physical devices** for background location flows specifically.
5. **Background modes:** enable `location` UIBackgroundModes; set `allowsBackgroundLocationUpdates = true` ONLY after `.always` is granted; set `showsBackgroundLocationIndicator = true` (the blue bar). Hiding the blue bar is an App Store rejection.

**Warning signs:**
- Code that uses `CLLocationUpdate.liveUpdates` without `CLServiceSession`.
- Background location tested only on iOS 18 simulator.
- No handling for reduced-accuracy path.
- Missing `location` in `UIBackgroundModes`.

**Phase to address:** M3 Dock & BOL (when background location for carriers on active load ships). Pre-select API strategy in M2 planning.

**TechStack.md coverage:** **Partial.** §5.4 calls out background location as SHOULD. API choice is implicit. Roadmap must specify.

---

### Pitfall 12: `isSecureTextEntry` screenshot trick is fragile; doesn't cover AirPlay/mirroring; bypassed by Accessibility Inspector

**What goes wrong:**
The `UITextField.isSecureTextEntry` layer trick is used to prevent sensitive content from appearing in screenshots. Works on iOS 16; works on iOS 17 with adjusted implementation (secure field must be the last sublayer, not the first). Ergonomically brittle — any view hierarchy change breaks it. On iPadOS with external display (Stage Manager, mirrored display), the protection may not propagate to the external display. On AirPlay/mirroring, the underlying content stream bypasses the on-device capture layer and the external receiver gets clean content.

Accessibility Inspector (enabled on-device in developer settings) can read content out of any view, secure or not. Not usable by a typical attacker but is a real leak vector for insider threats.

Screen-recording detection (`UIScreen.main.isCaptured`) fires when recording starts but not on AirPlay (AirPlay sets `UIScreen.screens.count > 1` instead). Two different signals, frequently confused.

**Why it happens:**
The `isSecureTextEntry` trick is unsupported/undocumented. Apple can and does change internal layer handling between iOS versions. TechStack.md picks this approach as a MUST, implicitly accepting the fragility.

**How to avoid:**
1. **Layer the defenses**: (a) `isSecureTextEntry` trick for baseline screenshot blocking, (b) `UIScreen.capturedDidChangeNotification` handler to blank the view during recording, (c) detect `UIScreen.screens.count > 1` for mirroring/AirPlay and blank sensitive screens, (d) `UIApplication.didChangeStatusBarOrientationNotification` / `UIScreen.didConnectNotification` / `didDisconnectNotification` for late-attach of external displays.
2. **Declare "sensitive screens" explicitly** in a `SecuritySensitiveScreen` protocol. Each sensitive VC overlays a black "content hidden" view when `isCaptured` or `mirrored` state is active.
3. **Test on iPadOS 17 and 18** with Stage Manager + external display. Test with AirPlay mirroring to an Apple TV. Test with QuickTime screen recording via Lightning cable.
4. **Accept reality: you cannot fully block screen capture.** The goal is to raise the bar and detect. Communicate this to product: "screenshot blocking is best-effort, not a hard guarantee."
5. **Screenshot detection, not just blocking**: listen for `UIApplication.userDidTakeScreenshotNotification` on sensitive screens, log a security event to the backend. If a user is repeatedly screenshotting the eBOL, that's a fraud signal.
6. **On iOS 17+, consider Sensitive Content Analysis framework** — different use case but sibling concept for content filtering; reference Apple docs for latest.

**Warning signs:**
- Only the `isSecureTextEntry` trick is in the codebase; no multi-signal defense.
- No testing on external display or AirPlay.
- `UIScreen.main.isCaptured` conflated with "any capture event."
- No screenshot-taken telemetry to backend.

**Phase to address:** M3 Dock & BOL (screenshot blocking is a M3 deliverable per TechStack.md §10).

**TechStack.md coverage:** **Partial.** §5.5 lists MUST screenshot + recording blocking. Doesn't address AirPlay, external display, Stage Manager. Roadmap must add.

---

### Pitfall 13: App Attest rate limits, assertion replay, and simulator-unfriendliness

**What goes wrong:**
App Attest key generation is rate-limited per Apple ID per day. Users who reinstall frequently (internal testers + TestFlight churn during M1-M2) hit the limit, get `DCErrorInvalidKey` on every login attempt, think the app is broken. Apple doesn't document the exact rate.

Assertion replay: if the server doesn't enforce the `counter` (monotonic increment stored in each assertion) strictly, an attacker can replay a valid assertion for a later request. Mis-implementing the challenge-response (server generates random challenge, client signs, server verifies) by skipping the nonce or using a predictable challenge enables replay.

Simulator: `DCAppAttestService.isSupported` returns false on simulator. Any testing of the attestation path must be on device.

Apple DeviceCheck revocation: if Apple revokes a device (rare, happens on mass-reinstall or abuse patterns), users get permanently stuck with no path to recover. The flow is a re-KYC.

**Why it happens:**
App Attest is a newer API (2020) with incomplete documentation. Rate limits are implied by "don't thrash." Server-side implementation requires careful challenge/response/counter design. Training data on App Attest is thin.

**How to avoid:**
1. **Generate App Attest key once, persist the key identifier to Keychain tied to device-not-biometric**, reuse for all assertions. Only regenerate if `DCErrorInvalidKey`. Document the regeneration trigger clearly.
2. **Server-generated challenge, embedded into every assertion request**: client never reuses. Challenge TTL ~60 seconds. Assertion signed = server-generated challenge + request-body hash.
3. **Server tracks per-key counter**; rejects any assertion with counter ≤ last-seen.
4. **Simulator fallback**: `#if DEBUG && targetEnvironment(simulator)`, send a well-known debug attestation token that the mock backend accepts. Real backend rejects this token. Production builds skip attestation if not supported but only after telemetry proves this is a tiny user cohort; prefer "attestation required."
5. **Rate-limit telemetry**: log `DCErrorInvalidKey` occurrences. If they exceed 0.1% of logins, rethink the regeneration logic.
6. **Document revocation UX**: if attestation fails with `DCError.serverUnavailable` vs `DCError.invalidKey` vs revocation, show different messages. Revocation = "contact support, re-verify identity."
7. **Don't attest every request; attest at login and sensitive actions.** TechStack.md §5.3 says "include attestation in login payload" — follow, don't expand.

**Warning signs:**
- App Attest key generated on every launch.
- Server-side code has no counter check.
- Challenge is client-generated or reused.
- No `#if targetEnvironment(simulator)` bypass in the attestation client.

**Phase to address:** M1 Foundation (subsequent phase — App Attest is part of FR-iOS-DEV). Server-side challenge/counter logic defined during the API contract work.

**TechStack.md coverage:** **Partial.** §5.3 mentions DeviceCheck / App Attest with attestation in login payload. Doesn't specify counter/challenge design or rate limit posture. Roadmap must add.

---

### Pitfall 14: Privacy Manifest omissions — required-reason API usage not declared — submission rejection

**What goes wrong:**
`PrivacyInfo.xcprivacy` is required for apps using "required reason APIs" (as of iOS 17 + May 2024 enforcement). This includes: user defaults, file timestamp, disk space, system boot time, active keyboards. The validation ledger app uses ALL of these (Keychain via iOS security APIs, disk space via URLSession background config reserving space, file timestamp via offline queue, active keyboards for input method logging). Xcode does NOT add `PrivacyInfo.xcprivacy` to the bundle by default — you must add it to "Copy Bundle Resources" manually.

First App Store submission fails at build validation or App Review within 24 hours with a cryptic error about required-reason APIs. Team scrambles. Loses a day.

Separately: third-party SDKs (Sentry, Crashlytics, image loaders) must themselves provide privacy manifests starting Feb 2025. An older SDK version without a manifest blocks submission.

**Why it happens:**
It's new-ish (2024). Documentation is scattered. Xcode's integration is half-baked (file must be manually added). SDKs were slow to comply.

**How to avoid:**
1. **Add `PrivacyInfo.xcprivacy` in M1 Phase 1**, not M5. Include a comprehensive declaration of: data types collected (see NSPrivacyCollectedDataTypes enum), linked reasons, tracking domains (none), API usage rationales. Apple publishes the required-reason list; map every use in the app.
2. **Automate required-reason API detection** in CI: a script that greps for `UserDefaults`, `NSData.creationDate`, `FileManager.attributesOfItem`, etc., and asserts each is declared in the manifest.
3. **SDK audit**: every third-party SDK in SwiftPM must have a privacy manifest at the version pinned. Check `KeychainAccess`, `Sentry`, `Nuke`/`SDWebImage`, etc. Upgrade any without a manifest before M5.
4. **Add `PrivacyInfo.xcprivacy` to "Copy Bundle Resources"** in Xcode project settings — not just in the file system. Verify the `.ipa` contains it (extract, inspect).
5. **Test submission via TestFlight early** (M3 or M4) with internal testers. TestFlight validation runs the same required-reason check as App Store. Catch rejections before M5.
6. **Keep App Store privacy labels in sync** — they're a separate product, separately rejectable. Update checklist part of release runbook.

**Warning signs:**
- No `PrivacyInfo.xcprivacy` in `Resources/` by end of M1.
- SDK versions in SwiftPM are >1 year old.
- Never submitted to TestFlight before M5.
- No privacy manifest CI check.

**Phase to address:** M1 Foundation (establish manifest skeleton). M4 Intelligence & polish (final audit). M5 Beta hardening (TestFlight validation dry run).

**TechStack.md coverage:** **Partial.** §8 mentions `PrivacyInfo.xcprivacy` but doesn't describe Copy Bundle Resources gotcha, SDK audit, or required-reason API enumeration. Roadmap must add.

---

### Pitfall 15: Jailbreak-detection code causing App Store rejection

**What goes wrong:**
TechStack.md §5.3 specifies jailbreak detection as SHOULD. Common implementations: test `/Applications/Cydia.app` existence, test write to `/private/`, try to `fork()`, check `dyld` image list for known unsigned libraries. App Reviewers have rejected apps that explicitly reference "jailbreak" in code or that use aggressive detection (appears as anti-user behavior). Some reviewers are fine with quiet detection → backend reporting.

The broader trap: client-side jailbreak detection is trivially bypassable (Frida, objc_msgSend hooks). Apps that BLOCK based on client-only jailbreak signals lock out users with legitimate reasons (jailbroken for accessibility, research, OEM QA) while not stopping real attackers who bypass the check in seconds. TechStack.md §5.3 is right to say "Report to backend; backend decides policy. Do not block based on client-only signal."

**Why it happens:**
Mobile security vendors sell jailbreak detection as a product. Developers Copy-paste detection code from Stack Overflow without reading Apple's review guidelines on anti-user behavior.

**How to avoid:**
1. **Strings matter**: do not put user-visible "jailbreak" strings in code or resources. Use a generic "device integrity signal" abstraction.
2. **Collect the signal, don't act on it client-side.** Ship signal to backend; backend correlates with other risk signals; backend decides whether to limit functionality.
3. **Avoid `/private/jailbreak_test` style write probes** — some reviewers flag these as suspicious file I/O.
4. **Prefer App Attest + DeviceCheck as the primary integrity signal.** Jailbreak heuristics supplement, not replace.
5. **Review App Review guidelines §2.5.4 and §4.0** for relevant language on "attempting to detect or obscure jailbreaking."
6. **If rejected on review, appeal citing security-sensitive product.** Banking apps ship with jailbreak detection; so can Validation Ledger. The reviewer's call is often negotiable.

**Warning signs:**
- `isJailbroken()` as a user-facing function name.
- Alert dialogs saying "jailbreak detected."
- Client code hard-refuses to run based on the signal.
- Reviewer rejection cites anti-user behavior.

**Phase to address:** M1 Foundation (subsequent phase — device integrity). M5 Beta hardening (review submission audit).

**TechStack.md coverage:** **Covered.** §5.3 already specifies "report to backend; backend decides policy." Enforce in code review.

---

### Pitfall 16: "Always" location authorization silently reverted by iOS without user action

**What goes wrong:**
iOS periodically prompts users "You haven't used [App] in a while. Do you want to change 'Always Allow' to 'While Using the App'?" — sometimes users tap yes reflexively. Carrier's background location tracking silently stops mid-trip. App thinks it's still getting updates. Shipment visibility goes dark. No error, no callback, just absence of data. Next app-open, the app discovers it's now on "when in use" but has no trip-level reconciliation of lost hours.

**Why it happens:**
iOS behaves this way to protect battery. `CLLocationManager.authorizationStatus` changes to `.authorizedWhenInUse`. If the app doesn't listen for `locationManagerDidChangeAuthorization(_:)`, the change is invisible.

**How to avoid:**
1. **Observe `locationManagerDidChangeAuthorization(_:)` always**, not only during onboarding.
2. **If a carrier is on an active load and authorization drops to `.authorizedWhenInUse`**, generate a local alert (notification, in-app banner) explaining the impact and deep link to Settings.
3. **Backend should receive "location tracking degraded" events** and surface to dispatchers.
4. **On app launch while an active load is tracked**, re-check authorization. If degraded, pause-resume tracking loop cleanly.
5. **Document the trade-off to users explicitly during initial permission flow**: "We need 'Always' while on an active load. iOS may prompt you to change this — please keep it 'Always' during active loads."
6. **Significant location change (SLC) fallback**: if `startUpdatingLocation` stops working, fall back to `startMonitoringSignificantLocationChanges` which works with wider permissions and wakes terminated apps (within constraints).

**Warning signs:**
- No `locationManagerDidChangeAuthorization(_:)` implementation.
- Tracking code assumes authorization never changes.
- No in-app state for "location tracking degraded."

**Phase to address:** M3 Dock & BOL (background location lands). M4 (beta telemetry on location-lost events).

**TechStack.md coverage:** **Not covered.** §5.4 requires background location but doesn't address revocation mid-trip. Roadmap must add.

---

### Pitfall 17: Critical Alerts entitlement rejection and permission confusion

**What goes wrong:**
TechStack.md §5.10 MUST: "Critical alerts for auth anomalies require user to be able to receive them; guide through permission setup." Critical Alerts require (a) an Apple-approved entitlement that must be requested via a special form and justified based on public safety / medical use, (b) user explicitly opting in per-app, separate from standard notifications, (c) code that registers for the critical alert category.

Apple has historically granted this entitlement sparingly. A fintech/freight identity product may or may not qualify. Expect 2-8 week response time. Rejection means the auth-anomaly-push UX must fall back to standard alerts, which can be silenced by Do Not Disturb.

**Why it happens:**
TechStack.md over-promises a feature that's gated by an Apple entitlement decision.

**How to avoid:**
1. **Request the entitlement at M1 or M2**, not M5. Longest lead time in the project. Include use case: fraud-related auth anomaly where delayed notification creates financial loss / identity compromise.
2. **Prepare fallback UX**: if entitlement denied, standard push notifications with time-sensitive interruption level (`.timeSensitive` on iOS 15+). Still better than nothing, not as invasive as critical alerts.
3. **Design the permission UX as a conditional flow**: detect entitlement availability at runtime, show "critical alerts" request only if entitlement present in build.
4. **Document the non-critical path in requirements** — don't treat critical alerts as table stakes.
5. **Document the "auth anomaly" types that qualify**: new-device-login-attempt, impossible-travel-detected are plausibly security-relevant; route spam/newsletter pushes through standard APNs.

**Warning signs:**
- No Apple entitlement request filed by end of M2.
- Code assumes critical alerts always available.
- No fallback path to `.timeSensitive`.

**Phase to address:** M2 Core flows (file entitlement request). M3 Dock & BOL (push notification implementation). M5 (fallback behavior verification).

**TechStack.md coverage:** **Partial.** §5.10 lists it as MUST; doesn't flag the entitlement application process. Roadmap should downgrade to SHOULD with fallback, OR accept calendar risk.

---

### Pitfall 18: Deep link arrives before app state is ready (cold launch race)

**What goes wrong:**
Push notification or universal link fires `scene(_:continue:)` or `scene(_:openURLContexts:)` before `applicationDidFinishLaunching` completes its async bootstrap (reading Keychain, restoring session, hydrating `AppContainer`). Deep link handler tries to route to `LoadDetailViewController(loadId: "xxx")` but `LoadRepository` is nil. Crash. User taps notification → crash. Bug looks random because it depends on cold-vs-warm launch.

Related: `openURL` fires twice on some iOS versions when the app is cold-launched via URL, leading to double navigation / duplicate analytics events.

**Why it happens:**
App launch bootstrapping is async-ish (Keychain reads happen on first access), but deep-link handlers fire synchronously from system frameworks. Two independent control flows with no coordination.

**How to avoid:**
1. **Central `DeepLinkRouter` with a pending-queue**: if bootstrap is not complete, enqueue the deep link. Drain the queue after bootstrap completes. Every entry point (URL scheme, universal link, push notification, widget) funnels through this router.
2. **Bootstrap as a deterministic state machine**: `.cold → .authenticating → .authenticated → .ready`. Router only routes in `.ready`. Between states, queue.
3. **Deduplicate by URL hash + timestamp** to handle the double-`openURL` case on cold launch.
4. **Testing**: deep link tests include "launch app from killed state via notification" case. XCUITest can do this.
5. **Instrument with analytics**: log "deep link received in state X" and watch for anomalies.

**Warning signs:**
- Deep link handler calls into `AppCoordinator.navigate(to:)` directly without state check.
- No pending-queue in the deep link code.
- No cold-launch deep-link testing.
- Crashes reports with "NSInvalidArgumentException" from `nil` repository.

**Phase to address:** M3 Dock & BOL (when push notifications + deep links land).

**TechStack.md coverage:** **Not covered.** §5.10 requires deep link to relevant screen, doesn't address bootstrap race. Roadmap must add.

---

### Pitfall 19: Offline queue duplicate submission + idempotency key collision + encrypted-storage-not-surviving-restore

**What goes wrong:**
Offline queue flushes on connectivity return. Multiple conditions flush simultaneously: `NWPathMonitor` says online, `applicationDidBecomeActive` says active, a user tap triggers a submit. Same action submitted multiple times. Backend creates duplicate "arrived at shipper" records.

Idempotency keys chosen as `hash(userId + actionType + timestamp)` — which yields collisions if two different updates share the same second.

Queue stored with `Data Protection: Complete` (file-level encryption tied to device passcode) — survives iCloud restore but sometimes doesn't decrypt on the new device because device-specific key material is gone. Queued mutations silently lost.

Duplicate submission on backend retry: backend receives `POST /updates` with idempotency key K, processes, 200 OK, response lost in network. Client retries → backend sees key K, returns cached 200 (good). But if client changed the body on retry (bug), backend returns stale response. Out-of-sync state.

**Why it happens:**
Offline queues look simple ("list of pending requests") but correct implementation requires careful invariants. iCloud device migration edge cases are rarely tested.

**How to avoid:**
1. **Queue entries have a UUID idempotency key** generated at enqueue time. Never regenerated. Stored with the entry.
2. **Queue is a SQLite/CoreData table with state machine**: `pending → inflight → synced` / `failed`. State transitions atomic (wrap in transaction).
3. **Single flush loop**, serialized via an actor or a dispatch queue. `NWPathMonitor` / `applicationDidBecomeActive` / user-tap all request flush from the same actor. Actor ensures only one flush at a time.
4. **Encrypt queue payloads with a key derived from the Keychain-stored app secret**, not device-level encryption. Survives iCloud restore via Keychain migration (which iCloud restore handles for most Keychain items — but not all; test explicitly).
5. **Backend enforces idempotency strictly**: key → hash of canonical request body. Retry with different body but same key returns an error. This catches client bugs.
6. **Test matrix**: kill app mid-enqueue, relaunch, confirm queue intact. Toggle airplane mode during flush, confirm no duplicates. iCloud backup → restore to fresh device, confirm queue state.

**Warning signs:**
- Multiple code paths calling `flushQueue()` without serialization.
- Idempotency key derived from non-unique inputs.
- No state machine on queue entries.
- Queue never tested with airplane mode.

**Phase to address:** M4 Intelligence & polish (offline mode lands).

**TechStack.md coverage:** **Partial.** §5.11 requires queue persisted to disk, encrypted. Doesn't address serialization, idempotency-key schema, or iCloud restore. Roadmap must add.

---

### Pitfall 20: Timeline trap — M1 scope that doubles from "hidden work"

**What goes wrong:**
M1 scope list looks like "auth shim + Keychain + Secure Enclave + role-switched tab shell + KYC capture + upload pipeline." Reads as 4 weeks for 1-2 engineers. Actual hidden work:
- Proper error handling on every network call (~30% of time).
- Logging + PII scrubber + os_log integration (week).
- First-launch Keychain wipe (half-day).
- Biometric-invalidation re-bind flow (2-3 days).
- Certificate pinning dual-pin code (day).
- `PrivacyInfo.xcprivacy` setup (day).
- SwiftLint + CI + pre-commit hooks (2 days).
- Snapshot test baseline (2 days).
- iPad layout sanity check (2-3 days).
- Accessibility basic pass (Dynamic Type, VoiceOver) (week).
- WWDC26 API churn absorbing time every June (uncontrollable, plan for 1 week).

M1 becomes M1+M2-shaped and the roadmap cascades.

**Why it happens:**
Specs describe features. Features imply plumbing that isn't named. Estimates anchor on feature names.

**How to avoid:**
1. **Acceptance criteria per M1 deliverable include the plumbing**: "Keychain token storage" expands to "Keychain token storage + first-launch wipe + access-group config + ErrorTaxonomy on all failures + logging scrubber integration + unit + device test."
2. **Budget 30% of M1 for "infrastructure tax"**: logging, error handling, CI, accessibility, privacy manifest. Call it out explicitly in the roadmap.
3. **Define M1 "done" crisply**: TestFlight internal build, all 5 roles logged in, KYC photo captured and uploaded end-to-end. Anything beyond is M1.5.
4. **Re-estimate at week 2**: if week 2 is behind, cut scope — defer App Attest to M2, defer impossible-travel pre-check (already downgraded), defer live face capture (already downgraded re: liveness). Ship the skeleton on time.
5. **WWDC26 lands in June — if M2-M3 overlaps**, absorb 1-2 weeks of adjustment time. Don't promise WWDC26 features as scope.

**Warning signs:**
- Estimate of M1 < 4 weeks with no infrastructure tax budget.
- "Error handling" not in acceptance criteria.
- Tests deferred to "later phases."
- No week-2 scope reassessment planned.

**Phase to address:** Roadmap creation itself. And week-2 of M1.

**TechStack.md coverage:** **Not covered.** §10 milestone table is feature-focused. Roadmap must add infrastructure tax.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using `@Published` without `.receive(on: DispatchQueue.main)` in ViewModels | Cleaner code, one less line | Purple warnings, dropped UI updates on background-originated changes | Never. Explicit `.receive(on:)` or dedicated main-actor isolation from day one. |
| Skipping PII scrubber "until we have real analytics" | Faster M1 ship | Every log from M1 → M5 leaks PII; audit at M5 is massive | Never. Stub scrubber is cheap; retrofit is not. |
| `#if targetEnvironment(simulator)` fallback for Secure Enclave | Enables simulator dev | Real-device bugs missed; risk of production fallback leak | Only in `#if DEBUG` branches with compile-time assertion. |
| Single-hash certificate pinning | Easy to ship | First cert rotation bricks the app; no emergency recovery | Never for production. Dual-pin from day one. |
| Deep links bypassing a central router | Easier one-off features | Cold-launch crash + double-fire bugs accumulate; every new entry point (widget, Siri intent) re-solves the problem | Only in `#if DEBUG` debug-menu deep links. |
| Hand-rolled Keychain wrapper | No dependency, control everything | Every code path re-implements access control; audit painful | OK if one person writes it in Phase 1 and treats it as a library (tests, API surface, don't touch after Phase 1). Prefer `KeychainAccess`. |
| Offline queue that's "an array in UserDefaults" for M1 | Ship faster | Race conditions, no durability, no state machine, rewrite needed at M4 | Acceptable ONLY if clearly marked as stub, replaced before M4. |
| 70% unit-test coverage as a goal | Sounds rigorous | Coverage metric gamed (testing getters, not logic); real surfaces (KYC pipeline, Keychain) may have 30% coverage despite hitting 70% overall | Reframe: test services and critical paths to high coverage. ViewModels 80%. UI snapshots for key screens. Ignore overall %. |
| `[String: Any]` analytics payloads | Fast to prototype | PII leaks, no compile-time safety, refactor nightmare | Never in production code. Typed enums. |
| JPEG compression at capture for bandwidth savings | Smaller uploads | Server-side image validation rejects over-compressed images; DL text OCR fails | Use HEIC with quality 0.85+ for KYC. JPEG only with explicit quality floor. Never pre-compress before location-metadata injection. |
| Assuming iOS 17 == iOS 18 for CoreLocation | Single code path | Either iOS 17 or iOS 18 users get broken background tracking | Never. Branch on `if #available(iOS 18, *)` for API-divergent paths. |
| Shipping without `PrivacyInfo.xcprivacy` "because we'll add it at M5" | No Xcode warnings in M1 | App Store rejection at M5 submission; scramble to comply | Never. Add skeleton in M1, fill in progressively. |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Keychain | Items survive uninstall, leaking prior user identity | First-launch wipe gated by `UserDefaults` flag; enumerate-and-delete all items under the app's access group. |
| Secure Enclave | Using `.biometryCurrentSet` without re-bind recovery | Full `errSecAuthFailed` / `errSecItemNotFound` handling + explicit re-bind flow with product-approved copy. |
| App Attest / DeviceCheck | Regenerating key on every launch, hitting rate limits | Generate once, persist key identifier, regenerate only on `DCErrorInvalidKey`; simulator bypass in DEBUG only. |
| Certificate pinning | Single pin, no rotation plan | Dual-pin (current + backup SPKI hashes), documented rotation runbook, optional remote kill switch. |
| APNs / Push Notifications | Assuming silent push is reliable; assuming critical alerts entitlement is granted | Silent push is best-effort, always have a foreground refresh; file critical alerts entitlement request by M2 with fallback to `.timeSensitive`. |
| URLSession background uploads | Treating as synchronous; no chunking | Background session with `URLSessionConfiguration.background`; chunks with idempotency keys; server-ack-based progress. |
| Deep links | Handler fires before app state ready | Central router with bootstrap-aware pending queue; cold-launch testing mandatory. |
| CoreLocation (iOS 17+18) | Mixing old delegate + new `CLLocationUpdate.liveUpdates` APIs | Pick one path per feature; delegate-API is safer through iOS 17/18; `if #available` for divergence. |
| Crash reporter (Sentry/Crashlytics) | Default config uploads VC titles + breadcrumbs that contain PII | `beforeSend` hook that runs through PII scrubber; test with intentional crash carrying known PII patterns. |
| `AVCapturePhoto` | Going through `UIImage` which strips EXIF | Work with `AVCapturePhoto.fileDataRepresentation()`; inject GPS via `CGImageSource` / `CGImageDestination`. |
| VisionKit liveness | Single blink prompt → high false-reject | Multi-stage prompts (blink → head turn → smile); fallback to commercial SDK if Vision-only FRR >5% per TechStack.md §12 Open Q1. |
| Analytics vendor (TBD M2) | Vendor-specific PII handling assumed | Wrap vendor SDK in an adapter that enforces the scrubber; swap-friendly. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `@Published` on a background thread creates Purple warnings and dropped updates | UI feels janky; console warnings during testing | `.receive(on: DispatchQueue.main)` before `.assign` / `.sink` in every ViewModel pipeline | As soon as any network response updates state |
| Combine subscription leak = monotonic memory growth | Memory usage increases with each navigation; not reclaimed on pop | `[weak self]` in every closure; inspect `cancellables` in `deinit`; Instruments pass per phase | After ~100-500 screen navigations or within an hour of stress use |
| Thermal throttling during continuous KYC capture | Face capture slows, frame rate drops, iPhone warm | Lower capture preset from 4K to 1080p; release capture session immediately on dismissal; don't hold retains on `AVCaptureSession` | Outdoor summer usage on older iPhones (12/13) |
| Upload thundering herd after network blip | Backend spikes every time a regional outage recovers | Jittered exponential backoff; server-side monitoring of idempotency-key churn | At > 100 concurrent users recovering from same outage |
| Resumable upload that restarts from 0 on each retry | KYC photos take 3+ attempts to upload; users drop off | Chunked upload with resume; background URLSession | Cell-coverage edge cases (dock, rural, mobile in truck) |
| Offline queue unbounded growth | App storage grows; launch slows | Cap queue size; fail-hard on cap; send telemetry | User with 2+ week offline period |
| Image cache (Nuke/SDWebImage) default unbounded | App storage grows | Configure max cache size (50-100MB); TTL on identity documents = 0 (never cache) | After weeks of use with many load photos |
| Combine `@Published` storm on rapid state changes (e.g., scroll) | CPU spikes during scroll | Debounce with `.throttle(for:scheduler:latest:)` before UI updates | Scrolling a large load list with real-time status |
| Background location polling too aggressively | Battery drain >3%/hour budget (NFR target) | Distance filter + significant change threshold; stop updates when stationary | On active load for 8+ hours |
| `URLSession` cached request of signed API responses | Stale chain-of-trust data shown | Disable URL cache on authenticated endpoints (`request.cachePolicy = .reloadIgnoringLocalCacheData`) | As soon as a chain-of-trust changes server-side |

---

## Security Mistakes

Beyond OWASP MASVS basics — domain-specific issues for verified-identity freight.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Validating JWT / session claims client-side instead of treating the backend as authority | Attacker mints a JWT and the client "trusts" it because client-side check passes | Client never validates claims. Only stores and sends. Backend is sole authority per FR-iOS-LOAD and FR-iOS-SCAN. |
| Hardcoding the API base URL or device-secret in the app bundle | Strings extractable via `strings` on the `.ipa`; allows targeted attacks | Use build configurations, `.xcconfig` files. Obfuscate (splits + XOR) only for the release base URL. Accept that obfuscation is speed bump, not security. No secrets in the app. |
| Generating the live QR payload client-side | Attacker generates valid QRs without backend verification → fraud | Client only displays backend-signed QR with TTL. Client never computes QR content. TechStack.md §5.7 already specifies; enforce at code review. |
| Caching identity documents on device after upload | Stolen/lost phone leaks DL, face, vehicle photos | Upload then delete local copy. Keychain has no business storing KYC photos. `FileManager` temp dir with explicit cleanup in `defer`. TechStack.md §8 already specifies. |
| Using `UserDefaults` for auth state, "remember me," or role | Not encrypted, readable via backup extraction | Keychain for tokens, Secure Enclave for keys, no sensitive state in `UserDefaults`. TechStack.md §8 specifies. |
| Debug menu visible in release build | Bypass routes to any screen; internal API exposed | `#if DEBUG` gate + assertion on `DEBUG_DEBUG_MENU_FORCE_ENABLED` env var present and matching; remove before release. Test via `RELEASE` scheme before TestFlight. |
| Signing requests with device key but not binding to request body | Replay attack with different body | Sign `SHA256(canonicalize(method + path + body + timestamp + nonce))` — include the body. Backend re-canonicalizes. |
| Trusting the `Authorization` header alone for sensitive actions (tender, accept, BOL) | If a token leaks, attacker can impersonate | Require device-signed header (FR-iOS-AUTH MUST) on every sensitive action; backend re-verifies signature + device pubkey + freshness. |
| Letting URL redirects follow across hosts | Token leaks to malicious host via `Referer` / logs | `URLSessionDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` — verify host is allowlist; return nil otherwise. |
| No clipboard wipe of copied values | Sensitive data lingers in clipboard; other apps read | `UIPasteboard.general.items = []` after 30s on sensitive fields; disable copy on QR payload. TechStack.md §5.5 already SHOULD this. |
| Face ID context shared across operations | Single biometric prompt authorizes multiple operations, one of which user didn't expect | Per-operation `LAContext` with `localizedReason` specific to the action. Never reuse `LAContext.evaluateAccessControl(...)` across operations. |
| App Attest assertion replayed | Attacker records + replays valid assertion | Server-issued challenge per request + monotonic counter + body hash binding. |
| Chain-of-trust visualization cached locally without verification | User sees stale chain that looks current | Always re-verify chain server-side before showing. No "offline chain-of-trust." |
| Obfuscating API URL as "security" | False confidence | Accept that this is speed bump. Don't treat as layer of defense. Security is TLS + cert pinning + server-side auth. TechStack.md §5.5 correctly flags this as "raises bar for casual RE; not a real defense." |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Camera permission prompt during first KYC attempt with no context | User denies camera → KYC completion drops | Pre-permission explainer screen first ("We need camera to verify your identity — your photos are uploaded securely and deleted from the device"); only then show system prompt. Funnel improves 20-40%. |
| "Always" location prompt fired immediately on app launch | Users deny reflexively | Two-stage: request "while in use" at first relevant action; upgrade to "always" only when user accepts first active load. |
| Biometric re-auth every 5 minutes feels punitive | User frustration, workaround (keep app foregrounded) | Re-auth on 5-min BACKGROUND, not inactivity. User scrolling the app for 20 minutes should not re-prompt. |
| Upload progress bar that goes 0-100% then hangs | User thinks app is frozen | Show "processing..." state when client done but server not ack; distinct UI from upload progress. |
| "Identity rejected" with no reason | User gives up | Specific rejection reason + action ("Your DL photo was unreadable — retry with better lighting" + retry button). |
| Full-screen error on every network blip | User trapped in error state | Inline banner + optimistic UI for non-destructive actions; full-screen only for auth expiry / server outage. |
| Five-role switch at account creation with no preview | User picks wrong role; support burden | Preview screenshots of each role's home; confirm selection; role is still backend-enforced. |
| QR scanner that demands perfect framing | User abandons scan | Widen the detection window; auto-torch in low light; offer "can't scan?" manual entry fallback per load (if product allows). |
| eBOL PDF export triggers share sheet with arbitrary destinations | User shares to iMessage with PII attached to clipboard log | Curated share sheet (AirDrop, Mail, Files only); remove general Copy / Open In. |
| Notification that deep-links to a screen requiring re-auth | User taps notification → biometric prompt → lands on screen; 3-tap flow feels wrong | If notification was fired within "trusted window," bypass re-auth; otherwise show lock + post-unlock navigate. |
| Offline queue "pending" state invisible | User submits action, closes app, loses state | Persistent bottom-of-screen "3 updates pending sync" pill; tappable for details. |
| "New device login detected" notification triggered by OWN new device | Noise; users tune out real alerts | Server correlates known devices; only alert on truly new device fingerprint, and only after 2-minute grace for user to confirm. |

---

## "Looks Done But Isn't" Checklist

Things that appear complete in internal demo but have critical gaps in production. Run this list as explicit acceptance criteria before marking items complete.

- [ ] **Keychain token storage:** Items are also wiped on first-launch-after-reinstall. Test: delete app → reinstall → launch → not logged in.
- [ ] **Secure Enclave key binding:** Handles biometric re-enrollment cleanly. Test: enroll Face ID → login → remove Face ID → re-enroll → login attempt shows re-bind flow, not cryptic error.
- [ ] **Certificate pinning:** Backup pin shipped; rotation runbook written. Test: mock cert rotation on staging; app survives.
- [ ] **PII scrubber:** Verifiable redaction. Test: intentional log of fake phone number; confirm redacted in crash dashboard / log file / analytics event.
- [ ] **Session lock:** Fires on cold boot with valid token. Test: force-quit app → launch → biometric required before any UI visible.
- [ ] **KYC upload:** Resumable across connection drops. Test: kill network mid-upload; reconnect; upload completes without restart from zero.
- [ ] **KYC GPS metadata:** Actually attached to uploaded image. Test: inspect uploaded `.heic`/`.jpeg` EXIF server-side; GPS dict present.
- [ ] **Role-switched tab shell:** All 5 roles render correctly on iPhone AND iPad. Test: one test pass per role, one device size of each.
- [ ] **Deep link routing:** Works on cold launch with no session AND with expired session AND with valid session. Test: push notification → app killed → tap → correct navigation after auth.
- [ ] **Offline queue:** Survives force-quit and airplane mode toggle without duplicates. Test: submit action → airplane mode on → force quit → airplane mode off → launch → action syncs once, not zero or twice.
- [ ] **Screenshot blocking:** Works on iPhone, iPad, with external display, with AirPlay. Test: all four capture scenarios on a sensitive screen.
- [ ] **Push permissions:** Critical alerts entitlement fallback path exists if denied. Test: run build with entitlement removed; auth anomaly uses `.timeSensitive` push.
- [ ] **Privacy manifest:** In the built `.ipa`, not just the project. Test: extract IPA, confirm `PrivacyInfo.xcprivacy` in root.
- [ ] **App Attest:** Simulator-safe. Test: simulator build runs; production build rejects simulator.
- [ ] **CoreLocation authorization reversion:** Handled at runtime, not only at onboarding. Test: on an active load, change "Always" to "When in Use" in Settings → app detects and alerts.
- [ ] **Background location battery:** ≤3%/hour per NFR. Test: 4-hour active-load simulation with location on; inspect battery graph.
- [ ] **Biometric re-prompt:** Only on background >5min, not foreground inactivity. Test: foreground for 20 minutes → no prompt. Background for 6 minutes → prompt.
- [ ] **URL cache:** Signed API responses not cached. Test: GET chain-of-trust, backend changes, second GET returns new data (not cached response).
- [ ] **Debug menu:** Removed in release. Test: ship a release build through TestFlight; confirm no debug UI accessible.
- [ ] **Accessibility:** Dynamic Type AND VoiceOver on KYC flow. Test: VoiceOver-only capture of a face photo possible. Dynamic Type XXL readable.

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Certificate pinning bricked users at rotation | HIGH | Emergency: deploy a TestFlight build with updated pins; coordinate with users to update. If App Store: expedited review (Apple grants for security-critical bugs); may take 24-48h. Long-term: implement kill-switch. |
| Keychain leak across reinstall shipped to prod | HIGH | Deploy fix that wipes on first-launch-after-build-version-change; release notes warn users; backend force-logout all sessions created before the fix. |
| PII in crash logs | MEDIUM | Purge crash reports from vendor dashboard (Sentry has purge APIs). Deploy scrubber fix. Audit all retained logs. GDPR/CCPA implications if EU/CA users affected. |
| Secure Enclave re-bind flow missing, users locked out | MEDIUM | Hotfix release with re-bind flow; support ticket flow for locked-out users pre-fix (re-KYC) |
| App Store rejection on jailbreak detection | MEDIUM | Rephrase strings ("device integrity check"); re-submit with explanation that report is backend-only; expedited review for minor rejections. |
| App Attest rate limit hit in testing | LOW | Wait 24h, avoid reinstall cycle. Use `.isSupported` + manual fallback for integration tests. |
| Upload queue overflow after outage | MEDIUM | Backend throttles idempotency-key processing; communicates status to client; client shows "backlog" UI. Build into design from start. |
| MVVM retain cycle discovered at M4 | HIGH | Feature-freeze 1-2 weeks; Instruments pass; fix all weak captures; regression test. Prevention of next occurrence via CI lint. |
| Offline queue duplicates on backend | MEDIUM | Backend-side dedup-by-key + user-visible "duplicate update suppressed" telemetry; retroactive cleanup of duplicate records if financial. |
| Critical alerts entitlement denied by Apple | LOW | Fallback to `.timeSensitive` ship; revisit application every 6 months. |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls. Cross-phase dependencies marked.

| # | Pitfall | Prevention Phase | Verification | Depends On |
|---|---------|------------------|--------------|------------|
| 1 | Secure Enclave biometric-invalidation silent brick | M1 Phase 1 | Physical-device test: re-enroll Face ID → re-bind flow appears | Re-bind UX decision (Open Q5 analogue) |
| 2 | Keychain items survive app delete | M1 Phase 1 | Delete-reinstall test: not logged in | — |
| 3 | Certificate pinning no rotation plan | M1 (dual-pin code) + M5 (runbook) | Staging cert rotation simulated without user action | Backend cert strategy |
| 4 | PII leakage via logs/analytics/URLs | M1 Phase 1 (scrubber) + M2 (vendor integration) + M5 (audit) | Intentional-leak test returns scrubbed output | Analytics vendor choice (M2 Open Q7) |
| 5 | MVVM-C + Combine retain cycles | M1 Phase 1 (conventions) + ongoing | Instruments pass per phase | — |
| 6 | KYC GPS metadata stripped by UIImage | M1 KYC phase | EXIF inspection on uploaded file | Mock backend GPS validation |
| 7 | Upload non-resumable, no jitter, no idempotency | M1 upload phase | Connection-drop test completes without restart | Backend chunk endpoint |
| 8 | Secure Enclave simulator falsely green | M1 Phase 1 (CI structure) | CI split: simulator tests + device tests | Physical device CI farm |
| 9 | Massive ViewModel rot | M1 Phase 1 (conventions) + M3 (review) | Per-VM line count ≤ 400; service layer present | — |
| 10 | Cold-boot session reveal | M1 Phase 1 (session lock) | Cold-launch biometric test | — |
| 11 | iOS 17 vs 18 CoreLocation divergence | M2 (API strategy) + M3 (background location) | Tests on both iOS versions physically | iOS-version policy |
| 12 | Screenshot blocking incomplete (AirPlay/mirror) | M3 Dock & BOL | Multi-display capture test | TechStack.md §5.5 expanded |
| 13 | App Attest replay / rate limit | M1 (subsequent phase) + M2 (server contract) | Monotonic counter + challenge test | Backend counter endpoint |
| 14 | Privacy Manifest omissions | M1 (skeleton) + M4 (audit) + M5 (TestFlight validation) | TestFlight submission passes | Third-party SDK selection |
| 15 | Jailbreak detection App Store rejection | M1 (subsequent phase) + M5 (review audit) | TestFlight submission accepted | — |
| 16 | CoreLocation authorization reverted mid-trip | M3 Dock & BOL | Settings-toggle test on active load | — |
| 17 | Critical Alerts entitlement confusion | M2 (entitlement request) + M3 (push impl) | Entitlement decision received | Apple entitlement pipeline |
| 18 | Deep link cold-launch race | M3 Dock & BOL | Cold-launch + push + deep-link test | Router design |
| 19 | Offline queue duplicate + encryption + restore | M4 Intelligence & polish | Airplane-mode + iCloud-restore tests | — |
| 20 | M1 scope doubling from hidden work | Roadmap creation + week-2 re-estimate | Mid-M1 checkpoint | — |

**Cross-phase dependency hotspots:**
- Pitfalls 1, 4, 7, 13 have **backend contract dependencies**. If backend GSD project lags, these slip. Define contract in M1 regardless.
- Pitfalls 3, 14, 15, 17 have **Apple external dependencies** (cert rotation, App Store review, entitlement approval). File all applications and documents **by M2** to absorb calendar risk.
- Pitfalls 8 requires **physical device CI** to be budgeted in M1; not having it infects every security test.

---

## Summary: TechStack.md Coverage Audit

The TechStack.md spec is strong on feature-level requirements but light on **implementation-risk details** and **cross-phase dependencies**. This analysis flags:

**Already well-covered in TechStack.md (enforce, don't re-spec):**
- Jailbreak detection policy (§5.3) — "don't block on client-only signal"
- Backend as sole authority for QR validation (§5.8)
- No client-side JWT claims validation (§5.6)
- No PII in analytics/crash (§8) — premise correct, implementation missing
- Biometric on `.biometryCurrentSet` (§8) — intent correct, recovery missing
- App Transport Security strict (§5.5)
- Identity documents never cached post-upload (§8)
- AI assistant is SHOULD-tier, app must work without it (§13)

**Partially covered — roadmap must expand:**
- Certificate pinning (needs dual-pin + rotation runbook + kill switch)
- KYC upload pipeline (needs chunking + idempotency + background session)
- Secure Enclave integration (needs re-bind UX + error code surface)
- Screenshot/recording blocking (needs AirPlay/Stage Manager/multi-display coverage)
- App Attest (needs challenge/counter design + simulator bypass)
- Privacy Manifest (needs Copy Bundle Resources step + SDK audit + CI check)
- MVVM-C (needs memory management conventions + VM size limits + service boundaries)
- PII scrubbing (needs URL-query/deep-link/VC-title coverage beyond "no PII in logs")
- Critical alerts (needs entitlement request timeline + fallback UX)
- Background location (needs CLServiceSession vs delegate decision + iOS 17/18 split)
- Session persistence (needs cold-boot+background unified invariant)
- Offline queue (needs idempotency-key schema + serialization + iCloud restore)

**Not covered in TechStack.md — roadmap must add:**
- Keychain-survives-uninstall wipe (Pitfall 2)
- iOS 17 vs iOS 18 CoreLocation API divergence (Pitfall 11)
- CoreLocation authorization reverted mid-trip (Pitfall 16)
- Deep link cold-launch race (Pitfall 18)
- M1 scope inflation / infrastructure tax (Pitfall 20)
- Physical-device CI requirement (Pitfall 8)
- URL redirect hopping (Security Mistakes table)
- Biometric re-prompt on 5-min background, not inactivity (UX Pitfalls)
- Debug menu gating in release builds

---

## Sources

Verified against Apple official documentation and community sources. Confidence level noted per source.

**HIGH confidence (Apple official + multi-source verified):**
- Apple Developer — [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- Apple Developer — [biometryCurrentSet (SecAccessControlCreateFlags)](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset)
- Apple Developer — [Preparing to use the app attest service](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service)
- Apple Developer — [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- Apple Developer — [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- Apple Developer — [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- Apple Developer — [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- Apple Developer — [liveUpdates (CLLocationUpdate)](https://developer.apple.com/documentation/corelocation/cllocationupdate/liveupdates(_:))
- WWDC23 — [Discover streamlined location updates](https://developer.apple.com/videos/play/wwdc2023/10180/)
- WWDC24 — [What's new in location authorization](https://developer.apple.com/videos/play/wwdc2024/10212/)
- WWDC23 — [Build robust and resumable file transfers](https://developer.apple.com/videos/play/wwdc2023/10006/)
- WWDC21 — [Mitigate fraud with App Attest and DeviceCheck](https://developer.apple.com/videos/play/wwdc2021/10244/)
- Apple Developer — [Identity Pinning: How to configure server certificates for your app](https://developer.apple.com/news/?id=g9ejcf8y)

**MEDIUM confidence (community sources verified against Apple docs):**
- [Core Location Modern API Tips (twocentstudios)](https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/)
- [Managing self and cancellable references when using Combine (Swift by Sundell)](https://www.swiftbysundell.com/articles/combine-self-cancellable-memory-management/)
- [Memory management in Combine (Tanaschita)](https://tanaschita.com/20220912-memory-management-in-combine/)
- [URLSession: Common pitfalls with background download & upload tasks (avanderlee.com)](https://www.avanderlee.com/swift/urlsession-common-pitfalls-with-background-download-upload-tasks/)
- [Task Cancellation in Swift Concurrency (Swift with Majid)](https://swiftwithmajid.com/2025/02/11/task-cancellation-in-swift-concurrency/)
- [iOS Keychain vs. Android Keystore (Talsec)](https://docs.talsec.app/appsec-articles/articles/ios-keychain-vs.-android-keystore)
- [This iOS Security Flaw Needs To Be Addressed In Every App (Tom Colvin)](https://tdcolvin.medium.com/this-ios-security-flaw-needs-to-be-addressed-in-every-app-e2b7d8b6cd95)
- [Certificate Pinning Pitfalls: Why Rotation Breaks Apps (Lotushints)](https://www.lotushints.com/2026/03/certificate-pinning-pitfalls-why-rotation-breaks-apps/)
- [After using short certificate chain, trust is broken in certificate pinning mechanism (Let's Encrypt Community)](https://community.letsencrypt.org/t/after-using-short-certificate-chain-trust-is-broken-in-certificate-pinning-mechanism/218512)
- [Dangers of Cert Pinning (Production ESP32)](https://productionesp32.com/posts/dangers-of-cert-pinning/)
- [Required Reason API: Troubleshooting your iOS Privacy Manifest file (Jochen Holzer)](https://jochen-holzer.medium.com/required-reason-api-troubleshooting-your-ios-privacy-manifest-file-privacyinfo-xcprivacy-c81084dc9d51)
- [Apple App Store Rejection Reasons In 2025 (Twinr)](https://twinr.dev/blogs/apple-app-store-rejection-reasons-2025/)
- [Preserving and Updating Image EXIF data in iOS (Startxlabs)](https://www.startxlabs.com/post/preserving-and-updating-image-exif-data-in-ios/)
- [In-Depth Guide on Image Metadata in iOS Swift (Shubham Kaliyar)](https://shubhamkaliyar.medium.com/an-in-depth-guide-on-image-metadata-in-ios-swift-6551cbd24d08)
- [Silent Push Notifications in iOS: Opportunities, Not Guarantees (Mohsin Khan)](https://mohsinkhan845.medium.com/silent-push-notifications-in-ios-opportunities-not-guarantees-2f18f645b5d5)
- [Understanding Silent Push Notification Behavior and Limits on iOS (Pushwoosh)](https://help.pushwoosh.com/hc/en-us/articles/26713265335581-Understanding-Silent-Push-Notification-Behavior-and-Limits-on-iOS)
- [Exposing the Shortcomings of Apple DeviceCheck and Apple App Attest (Approov)](https://approov.io/blog/limitations-of-apple-devicecheck-and-apple-app-attest)
- [iOS App Attest + DeviceCheck: Building Real Trust Into Your App (Wesley Matlock)](https://medium.com/@wesleymatlock/%EF%B8%8F-ios-app-attest-devicecheck-building-real-trust-into-your-app-without-losing-your-mind-c98bc39eb142)
- [The Hidden Problems of Offline-First Sync: Idempotency, Retry Storms, and Dead Letters (DEV)](https://dev.to/salazarismo/the-hidden-problems-of-offline-first-sync-idempotency-retry-storms-and-dead-letters-1no8)
- [Implementing Idempotency Keys in REST APIs (Zuplo)](https://zuplo.com/learning-center/implementing-idempotency-keys-in-rest-apis-a-complete-guide)
- [Screenshot Prevention in iOS: Advanced Techniques (Neeshu Kumar)](https://medium.com/@thakurneeshu280/screenshot-prevention-in-ios-advanced-techniques-inspired-by-banking-authenticator-apps-0d1900c2a1bb)
- [Prevent Screen Capture on iOS17 (SIDESTEP)](https://tigi44.github.io/ios/iOS,-Swift-Prevent-Screen-Capture-on-iOS17/)
- [Beyond the Basics: Architecting Next-Gen Deep Linking in iOS (Neeshu Kumar)](https://medium.com/@thakurneeshu280/beyond-the-basics-architecting-next-gen-deep-linking-in-ios-64c31cf68c36)

**LOW confidence (single-source, training-data-only, or specific numbers uncertain):**
- App Attest rate limit exact numbers — Apple does not publish; inferred from developer forum reports
- Critical Alerts entitlement approval rate — based on developer community anecdotes, no Apple-published data
- VisionKit liveness false-reject rate — entirely application-specific; TechStack.md §12 Open Q1 parks this for M1 prototyping
- iOS 17.x vs iOS 17.4 behavior differences for `liveUpdates` — some community observation, not Apple-documented

---

*Pitfalls research for: Validation Ledger iOS client (identity-verified freight, MVVM+Coordinators+Combine, iOS 17+, UIKit-first, 1-2 engineers, 24-week v1 to TestFlight beta)*
*Researched: 2026-04-20*
