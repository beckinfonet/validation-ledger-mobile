# Phase 2: Networking Contract & Device Keys — Research

**Researched:** 2026-04-21
**Domain:** Contract-first URLSession networking (typed APIClient, MockURLProtocol fixtures, dual-pin SPKI cert pinning, idempotency interceptor, exponential backoff) + Secure Enclave EC P-256 keypair lifecycle with dual-ACL pattern.
**Confidence:** HIGH for networking + cert-pinning surfaces; HIGH for Secure Enclave primitives (SecKeyCreateRandomKey + biometryCurrentSet ACL are well-documented Apple APIs); MEDIUM for device-CI fail-refuse-launch test harness (depends on Phase 1 runner registration — HUMAN-UAT gap).

<user_constraints>
## User Constraints (from CONTEXT.md / inherited from Phase 1 + Phase 2 kickoff)

Phase 2 has no dedicated `02-CONTEXT.md` at research time — this researcher was spawned with a detailed phase kickoff (the `<phase_context>` block in the research brief). Decisions are inherited from Phase 1's locked landscape and the phase-2 kickoff brief. The planner SHOULD confirm these before execution via `/gsd-discuss-phase 2` if any are ambiguous.

### Locked Decisions (from Phase 1 + phase-2 kickoff brief)

- **Tech stack:** UIKit-first, Swift 5.9+, iOS 17.0 deployment, SwiftPM-only. No Alamofire. No KeychainAccess. No Moya. Hand-rolled `URLSessionNetworkClient` + hand-rolled cert pinning. (CLAUDE.md constraints + PROJECT.md)
- **Composition root:** All Phase 2 services resolve through `AppContainer` (initializer-DI only, no singletons, no `.shared`). (ARCH-04, confirmed Phase 1)
- **KeyStore selection gate:** `#if DEBUG && targetEnvironment(simulator)` in `AppContainer` picks `SoftwareKeyStore`; else `SecureEnclaveKeyStore` (after `SecureEnclave.isAvailable` precondition). Already wired in Phase 1. **DO NOT move or re-gate this — Phase 2 fills the else-branch implementation, not the selection logic.** (DEV-03, Phase 1 AppContainer)
- **Production refuses launch without Secure Enclave:** `fatalError` currently in `AppContainer.init` when `SecureEnclave.isAvailable == false` in a Release build. Phase 2 keeps this invariant; SC-4 adds a device CI forced-stub test that validates it. (DEV-03, Phase 1 AppContainer line 42)
- **Two-key pattern (DEV-02):** `deviceKey` with passcode-only ACL (`.devicePasscode`) for device identity; `authorizationKey` with `.biometryCurrentSet` ACL for sensitive-request signing. Both are EC P-256 in the Secure Enclave on a real device. This is an inherited product decision from TechStack.md §6 Security and REQUIREMENTS.md DEV-02.
- **`authorizationKey` is invalidation-sensitive by design:** `.biometryCurrentSet` means "if the user re-enrolls Face ID / Touch ID, this key becomes permanently inaccessible." Phase 3 wires the re-enrollment detection + "re-bind device" flow (SESS-03). Phase 2 MUST NOT switch to `.biometryAny` — invalidation-on-re-enrollment is a product requirement (prevents a compromised fingerprint enrollment from continuing to sign). (SESS-03, DEV-02)
- **Mock/live swap is ONE LINE (NET-03):** `AppContainer.networking = .mock` vs `.live(baseURL:)`. The `NetworkConfig` enum already exists in Phase 1 `NetworkClient.swift` lines 7–10. Phase 2 fills the `.live` branch wiring — base URL resolution from `Environment.apiBaseURL`, session configuration without `MockURLProtocol`, etc. **Call sites must not change.** (NET-03)
- **Idempotency on POST mutations only (NET-04 + NET-05):** Every POST mutation gets an `Idempotency-Key` header (UUID().uuidString). Retry is allowed for idempotent GETs (max 3 retries, exponential backoff); retry on POST is ONLY via explicit idempotency-key replay (no implicit retry). This is a product decision — do not change.
- **Dual-pin cert pinning (SEC-01 / FOUND-05 full):** Leaf SPKI + backup SPKI, both baked into the release binary. Staging pins staging-leaf + staging-backup. (SEC-01)
- **Cert-rotation runbook (FOUND-05 carryover):** `docs/cert-rotation.md` ships as a Phase 1 skeleton (verified) — Phase 2 fills the SPKI extraction procedure, 30-day rotation cadence (already outlined), rollback procedure, key ceremony, and CI check for "both pins present."
- **Install UUID (DEV-05):** Persisted in Keychain (not `UserDefaults`). Device fingerprint on `/device/register` is `{model, iOSVersion, installUUID}` only — no advertising ID, no IDFA, no MAC.
- **No App Attest in Phase 2:** DEV-04 (App Attest) is Phase 4. `/device/register` payload does NOT include an App Attest assertion yet. Phase 2 ships the hook where it will plug in.
- **Phase 1 follow-ups that are Phase 2 scope:**
  - **CR-01:** Replace `response as! HTTPURLResponse` force-cast in `NetworkClient.get/post` with `guard let ... else throw NetworkError.unexpectedResponseType(response)`.
  - **WR-01:** `MockURLProtocol.handlers` global mutable static needs synchronization before Phase 2 fixtures multiply. Prefer NSLock wrapper (sketched below) over rearchitecting to per-session configuration — the Phase 1 API is already consumed by tests.

### Claude's Discretion

These are not user-locked; the researcher recommends and the planner confirms:

- **Typed endpoint shape (NET-01):** `struct OTPRequestEndpoint: APIEndpoint` style vs protocol-with-associatedtype vs free `APIClient.request<T>(endpoint:)` method — researcher recommends the `APIEndpoint` protocol pattern (URL path + HTTP method + request/response types as associatedtypes) because it pins the mock fixture to the endpoint definition.
- **Interceptor composition:** Researcher recommends a plain chain-of-function-closures (`[any RequestInterceptor]`) instead of Combine-based middleware or a custom delegate chain — smallest surface area, Sendable-clean, testable.
- **Exponential backoff parameters:** Recommend 0.5s × 2^n with ±20% jitter, hard ceiling 4s, max 3 retries for GET. (NET-05 says "max 3" — this is the spec; base/ceiling are discretion.)
- **Where `Idempotency-Key` UUID is generated:** Researcher recommends generation at interceptor level (one UUID per `URLRequest` instance, stored on `URLRequest` via `setValue(_:forHTTPHeaderField:)` once). **Do not** store UUIDs in persistent state in Phase 2 — that's a Phase 5 upload-pipeline concern (resumable chunks need persistent idempotency state; single POSTs do not).
- **MockURLProtocol pattern under Swift 6 / parallel testing:** Researcher recommends a `@Suite(.serialized)` trait on every test suite that mutates `MockURLProtocol.handlers`, AND the `NSLock`-wrapped global (see WR-01 fix). Belt + suspenders — the lock covers future parallelism; `.serialized` keeps Phase 2 fixture tests deterministic now.
- **Cert-pinning Info.plist NSPinnedDomains vs hand-rolled URLSessionDelegate:** Researcher recommends **hand-rolled `PinningSessionDelegate`** for the API-traffic session (already skeletoned in Phase 1) and *not* using NSPinnedDomains for the primary API. See §Architecture Patterns Pattern 4 for the rationale.

### Deferred Ideas (OUT OF SCOPE for Phase 2)

- **App Attest attestation in `/device/register`:** Phase 4 (DEV-04).
- **Resumable chunk upload idempotency state (persistent `Idempotency-Key` on disk):** Phase 5 (UPL-02).
- **Typed error mapping from backend error codes to user-facing messages:** Plans should ship typed `NetworkError` with the structure ready, but mapping backend-specific codes (e.g., `"auth.rate_limited"` → "Try again in 60s") lands with Phase 3 AUTH-02.
- **Real backend URL selection (dev / staging / prod):** `Environment.apiBaseURL` is currently `nil` for both DEBUG and Release (Phase 1). Phase 2 wires *the plumbing* to accept a base URL, but the actual URLs don't exist yet (backend is a separate GSD project). A `FIXME(phase-2)` or `PHASE-2-TODO` marker is acceptable pending backend availability. See WR-06 from Phase 1 REVIEW.md.
- **Impossible-travel pre-check:** Downgraded to SHOULD; backend enforces. Not in Phase 2.
- **Sensitive-action biometric re-prompt sign flow (tender/accept/BOL):** AUTH-06 is M2+. Phase 2 ships the `authorizationKey` ACL so Phase 3+M2 can consume it.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (verbatim from REQUIREMENTS.md + phase kickoff brief) | Research Support |
|----|-------------------------------------------------------------------|------------------|
| NET-01 | `APIClient` exposes typed Swift models for every M1 endpoint (OTP request, OTP verify, device register, KYC upload init/chunk/commit, KYC status). | §Standard Stack (APIEndpoint pattern), §Pattern 1 (APIClient + typed endpoints), §Code Examples (OTP + device register endpoint sketches) |
| NET-02 | `MockURLProtocol` returns canned JSON for every M1 endpoint; success + failure fixtures per endpoint. | §Pattern 2 (endpoint-keyed fixture registry), §Code Examples (fixture bundle + handler registration), §Validation Architecture row NET-02 |
| NET-03 | One-line swap between mock and live backend (`AppContainer.networking = .mock` vs `.live(baseURL:)`). | §Pattern 3 (NetworkConfig → URLSession factory), §Code Examples (AppContainer Phase-2 wiring), §Pitfall 5 (mock-vs-live swap traps) |
| NET-04 | `Idempotency-Key` header interceptor on every POST mutation (UUID().uuidString). | §Pattern 5 (RequestInterceptor chain), §Code Examples (IdempotencyInterceptor), §Validation Architecture row NET-04 |
| NET-05 | Exponential backoff on idempotent GETs only (max 3 retries); no retry on POST without explicit idempotency replay. | §Pattern 6 (RetryInterceptor with HTTP-method gate), §Code Examples (exponential-backoff + jitter), §Validation Architecture row NET-05 |
| SEC-01 | Dual-pin SPKI cert pinning on all API traffic; staging pins staging + backup. | §Pattern 4 (PinningSessionDelegate + SPKI extraction), §Code Examples (dual-SPKI compare), §Code Examples (openssl SPKI extraction procedure), §Validation Architecture row SEC-01 |
| DEV-01 | SecureEnclave generates EC P-256 keypair at first successful OTP verify; public key on `/device/register`. | §Pattern 7 (Secure Enclave keypair generation via SecKeyCreateRandomKey), §Code Examples (SecureEnclaveKeyStore), §Validation Architecture row DEV-01 |
| DEV-02 | Two-key pattern: `deviceKey` (passcode-only ACL) + `authorizationKey` (`.biometryCurrentSet` ACL). | §Pattern 7 (two-key ACL separation), §Code Examples (SecAccessControl flags for each), §Pitfall 3 (ACL gotchas) |
| DEV-03 | `SoftwareKeyStore` = simulator/test fallback via `#if DEBUG && targetEnvironment(simulator)`. Production refuses launch if SE unavailable. | §Code Examples (AppContainer gate — unchanged from Phase 1), §Validation Architecture row DEV-03 (forced-stub device CI test) |
| DEV-05 | Device fingerprint (model, iOS version, install UUID) on `/device/register`. Install UUID persisted in Keychain. | §Pattern 8 (DeviceFingerprint + installUUID), §Code Examples (UIDevice + Keychain), §Validation Architecture row DEV-05 |

</phase_requirements>

## Summary

Phase 2 turns the Phase 1 networking + KeyStore skeletons into a production-capable contract-first networking stack with device-bound EC P-256 signing. Ten requirements across NET / SEC / DEV, all backed by well-established Apple APIs — the risk is almost entirely in *precise usage* rather than *whether the APIs exist*. URLSession + URLProtocol + URLSessionDelegate + Security framework (SecKeyCreateRandomKey, SecAccessControlCreate, SecKeyCreateSignature) + CryptoKit interop cover the entire surface; **no external library is required or recommended**.

The highest-risk surface is the Secure Enclave ACL wiring: `.biometryCurrentSet` is intentionally fragile-by-design (re-enrolling a biometric permanently discards the key), and the two-key pattern (DEV-02) requires precise `SecAccessControlCreateWithFlags` argument composition. The second-highest risk is the MockURLProtocol global-state race exposed in Phase 1's WR-01 — it MUST be fixed before Phase 2 fixtures multiply, and Swift Testing's default parallel execution demands `@Suite(.serialized)` on every test that mutates handlers, OR a redesign to instance-scoped handlers (researcher prefers the lock + serialized-suite belt-and-suspenders approach). Third risk is cert-pinning self-brick DoS: a bad pin ships to TestFlight and all users are blocked; **the dual-pin discipline is not optional**, and `docs/cert-rotation.md` must describe the actual SPKI extraction procedure so the on-call engineer has a copy-pasteable runbook when rotation is needed.

**Primary recommendation:** Group Phase 2 work into four waves:
- **Wave 0** (tests-first gate): Fix CR-01 (force-cast) + WR-01 (MockURLProtocol lock); define `NetworkError` enum; add Swift Testing fixtures directory.
- **Wave 1** (parallel after Wave 0): NET-01 typed endpoints + models; NET-02 MockURLProtocol fixture registry + per-endpoint success/failure fixtures; NET-03 `.mock` vs `.live` switch in `AppContainer`.
- **Wave 2** (parallel after Wave 1): NET-04 idempotency interceptor; NET-05 retry interceptor with HTTP-method gate; SEC-01 PinningSessionDelegate dual-SPKI implementation + cert-rotation runbook fleshed out.
- **Wave 3** (parallel after Wave 1): DEV-01/02 SecureEnclaveKeyStore implementation (two-key pattern + sign API); DEV-05 DeviceFingerprint + installUUID.
- **Wave 4** (after all): device CI forced-stub test for DEV-03 "refuse to launch without SE"; networking integration test for dual-pin rejection of a third un-pinned cert. [ASSUMED wave grouping — planner confirms]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Typed endpoint definitions (NET-01) | `Core/Networking/Endpoints/` | — | Per-endpoint struct carries path + method + request/response types. Pure value types; no dependencies on session. [VERIFIED: research/ARCHITECTURE.md Pattern 4 + research kickoff brief] |
| `APIClient` façade over `NetworkClient` | `Core/Networking/` | `App/AppContainer` | `APIClient` owns the typed-endpoint → raw-request → raw-response → typed-response transform; `NetworkClient` owns the wire. AppContainer composes both. [VERIFIED: research/STACK.md + kickoff brief NET-01] |
| MockURLProtocol fixture registry (NET-02) | `Core/Networking/Mock/` | test target | Fixtures live in a registry keyed by `APIEndpoint` path+method; unit tests register handlers before each test; `@Suite(.serialized)` keeps parallel test runs safe. [VERIFIED: REVIEW.md WR-01 + Swift Testing docs] |
| `NetworkConfig` `.mock` vs `.live` switch (NET-03) | `App/AppContainer` | `Core/Networking/NetworkClient` | Already scaffolded in Phase 1. AppContainer constructs URLSession with different `protocolClasses` (mock) or with `PinningSessionDelegate` (live). One-line swap is the call site; session factory internals do the work. [VERIFIED: Phase 1 AppContainer.swift:50-58] |
| Request interceptors (NET-04, NET-05) | `Core/Networking/Interceptors/` | `Core/Networking/NetworkClient` | Chain of `RequestInterceptor` protocol conformers; `NetworkClient` applies them in order. Idempotency interceptor adds header; retry interceptor wraps the send call. [VERIFIED: researcher recommendation; see Pattern 5] |
| Cert pinning (SEC-01) | `Core/Networking/CertificatePinning/PinningSessionDelegate` | `App/AppContainer` (live-only composition) | Delegate validates server trust against baked-in dual-SPKI. AppContainer installs the delegate only on the `.live` URLSession — mock session does not need pinning. [VERIFIED: CONTEXT.md D-05 security-path CI trigger + kickoff brief SEC-01] |
| SPKI hash storage | Compiled-in Swift constants (`PinnedSPKIs.swift`) | Release vs Debug build config | Do NOT store SPKI hashes in JSON or Info.plist — easier to tamper with. Compiling into the binary makes repackaging visible. Separate `.debug` / `.release` constants let DEBUG builds accept `mock.local` without pinning. [VERIFIED: Guardsquare blog + kickoff brief SEC-01] |
| `SecureEnclaveKeyStore` (DEV-01, DEV-02) | `Core/KeyStore/SecureEnclaveKeyStore` | `Core/Storage/Keychain` (persistent-ref storage) | Generates EC P-256 keypair via `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`; stores the persistent reference (NOT the key itself — the key lives in the enclave) via `kSecAttrApplicationTag`. Keychain holds the tag; enclave holds the key. [VERIFIED: Apple `protecting-keys-with-the-secure-enclave` docs] |
| `SoftwareKeyStore` (DEV-03) | `Core/KeyStore/SoftwareKeyStore` | `App/AppContainer` (DEBUG+simulator gate) | Phase 1 already ships this using `P256.Signing.PrivateKey()` from CryptoKit. Phase 2 does not touch it. [VERIFIED: Phase 1 SoftwareKeyStore.swift] |
| Device fingerprint (DEV-05) | `Core/Identity/DeviceFingerprint` | `Core/Storage/Keychain` (install UUID) | `UIDevice.current.model` + `UIDevice.current.systemVersion` + Keychain-persisted installUUID. Install UUID is generated on first launch AFTER the D-20 wipe; persists across reinstall until next wipe. [VERIFIED: kickoff brief DEV-05 + Phase 1 KeychainStore] |
| Idempotency UUID generation (NET-04) | `Core/Networking/Interceptors/IdempotencyInterceptor` | — | Per-request `UUID().uuidString`. No persistent state in Phase 2 (upload chunks are Phase 5). [VERIFIED: Stripe idempotency docs + kickoff brief NET-04] |
| Retry scheduling (NET-05) | `Core/Networking/Interceptors/RetryInterceptor` | `Core/Networking/NetworkClient` | Wraps the send call; checks HTTP method; only retries GET on 5xx/URLError.networkError; exponential backoff with jitter. POST never retries without explicit idempotency-replay (which is a different flow than generic retry — Phase 5 upload). [VERIFIED: kickoff brief NET-05] |

**Why this matters:** The planner assigns each task to exactly one directory owner. The "mock vs live URLSession factory" MUST stay inside `AppContainer` composition — leaking it into `NetworkClient` would turn the one-line swap into a multi-site change. The "PinningSessionDelegate is ONLY on the live session" invariant is easy to miss; if someone attaches it to the mock session, every test breaks mysteriously when they try to hit `mock.local` without a matching SPKI.

## Standard Stack

### Core (unchanged from Phase 1 — inherited stack)

| Library / API | Version | Purpose | Phase 2 Usage |
|---------------|---------|---------|---------------|
| URLSession | native | HTTP transport | Phase 2 fills the `URLSessionNetworkClient` body — real `data(for:)` calls through configured sessions (mock or live). [VERIFIED: Phase 1 NetworkClient.swift] |
| URLSessionDelegate | native | Server trust challenge handling | `PinningSessionDelegate` already skeletoned (Phase 1). Phase 2 fills the challenge body with dual-SPKI validation. [VERIFIED: Phase 1 PinningSessionDelegate.swift] |
| URLProtocol | native | Mock transport for tests | Phase 2 extends `MockURLProtocol` from 1 fixture to per-endpoint fixtures; adds NSLock around the global handlers array (WR-01 fix). [CITED: [swiftlang/swift-corelibs-foundation URLProtocol.swift](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/FoundationNetworking/URLProtocol.swift)] |
| Security framework | native | Cert/key/Keychain primitives | `SecKeyCreateRandomKey`, `SecAccessControlCreateWithFlags`, `SecKeyCreateSignature`, `SecTrustCopyKey`, `SecCertificateCopyData`, `SecItemCopyMatching`. [VERIFIED: [Apple protecting-keys-with-the-secure-enclave docs](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)] |
| CryptoKit | native | EC P-256 interop + SHA-256 | `SHA256.hash(data:)` for SPKI hashing; `P256.Signing.PrivateKey` for `SoftwareKeyStore` (already Phase 1). `SecureEnclave.P256.Signing.PrivateKey` is CryptoKit's newer convenience wrapper but **not used in DEV-01/DEV-02 here** — we use `SecKeyCreateRandomKey` with explicit ACL because `SecureEnclave.P256.Signing.PrivateKey` does not expose the ACL flag set we need. See Pitfall 3. [VERIFIED: [Apple SecureEnclave.P256 docs](https://developer.apple.com/documentation/cryptokit/secureenclave/p256) + Gridnev article] |
| Foundation `UUID` | native | Idempotency-Key values | `UUID().uuidString` per POST mutation. [VERIFIED: Stripe idempotency docs recommend UUIDv4, which matches Foundation's `UUID()` default behavior.] |
| UIKit `UIDevice` | native | Device model + iOS version | `UIDevice.current.model` + `UIDevice.current.systemVersion`. No advertising ID; no IDFA. [VERIFIED: Apple UIDevice docs] |
| Swift Testing | bundled | Unit tests | Already Phase 1 baseline; Phase 2 adds `@Suite(.serialized)` on every test suite that mutates `MockURLProtocol.handlers`. [VERIFIED: [Swift Testing `.serialized` docs](https://developer.apple.com/documentation/testing/trait/serialized)] |

### Supporting (no new Phase 2 dependencies)

**Researcher recommendation:** Phase 2 adds ZERO new SwiftPM dependencies. The entire stack is available in the iOS SDK. Alternatives like Alamofire (banned by STACK-01), Moya (not in dependency shortlist), or KeychainAccess (abandoned per STACK.md) are not options. Hand-rolled URLSession + interceptor chain is a ~250-LOC surface that the security-first constraint favors anyway.

### Alternatives Considered

| Instead of | Could Use | Why NOT in Phase 2 |
|------------|-----------|--------------------|
| Hand-rolled cert pinning in URLSessionDelegate | **NSPinnedDomains** in Info.plist (iOS 14+) | Apple's declarative pinning is trivially bypassable by app repackaging (the pin hash is in a plist file) — for a security-first freight-identity product this is the wrong trust model. Compile-time Swift constants in the binary require a binary-patching attack. Also, Apple docs explicitly do not clarify NSPinnedDomains' behavior across all CFNetwork APIs (there are reports it works with WKWebView on iOS 16+ but URLSession semantics are underspecified). [VERIFIED: [Guardsquare blog: Leveraging Info.plist Based Certificate Pinning on iOS](https://www.guardsquare.com/blog/leveraging-infoplist-based-certificate-pinning-ios-and-making-its-shortcomings), [Apple NSPinnedDomains docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nspinneddomains)] |
| `SecureEnclave.P256.Signing.PrivateKey` (CryptoKit) | `SecKeyCreateRandomKey` + `kSecAttrTokenIDSecureEnclave` + `SecAccessControlCreateWithFlags` | CryptoKit's `SecureEnclave.P256.Signing.PrivateKey` is a convenience wrapper but does NOT expose a way to set `.biometryCurrentSet` ACL — it defaults to no biometric gating. DEV-02's `authorizationKey` REQUIRES `.biometryCurrentSet`. So we use the lower-level Security framework API. [VERIFIED: Apple `SecAccessControl` docs, cross-verified with [Gridnev — iOS Keychain using Secure Enclave-stored keys](https://medium.com/@alx.gridnev/ios-keychain-using-secure-enclave-stored-keys-8f7c81227f4)] |
| Retry via URLSession's built-in retry policy | Custom `RetryInterceptor` wrapping the send call | URLSession does not expose configurable per-request retry. `URLSessionConfiguration.timeoutIntervalForRequest` controls a single attempt timeout; there is no retry knob. A custom interceptor gives us method-gated retry (GET-only per NET-05) and injectable jitter. [VERIFIED: URLSession API surface; no retry API exists] |
| AsyncRequestChain / Combine-based middleware | Plain `async`/`await` interceptor chain | Combine adds a dependency graph complexity for a synchronous-in-behavior transform (add header → send → maybe retry). Plain `async`/`await` with `[any RequestInterceptor]` is 1/3 the code and Sendable-clean under Swift 6 concurrency. [ASSUMED — researcher discretion; planner may override] |
| Per-session `URLProtocol` registration via `URLSessionConfiguration.protocolClasses` | Global `URLProtocol.registerClass` | The Phase 1 MockURLProtocol design already uses session-scoped `protocolClasses` (see AppContainer.swift line 52) — this is correct. Global `URLProtocol.registerClass` pollutes URLSession.shared and is a common test-isolation bug. **Keep the session-scoped pattern; do not switch to global registration.** [VERIFIED: [Swift Forums — Mock URLProtocol with strict Swift 6 concurrency](https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135) + Phase 1 AppContainer implementation] |

### Version Verification

No new package versions to verify. iOS SDK primitives are tied to the iOS 17.0 deployment target (already fixed in Phase 1).

Run at execution time:
```bash
# Confirm iOS SDK deployment target is still 17.0 (should be — Phase 1 locked it)
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 17.0" validationLedger.xcodeproj/project.pbxproj
# Expected: 8 (Phase 1 VERIFIED)

# Confirm no forbidden deps slipped in since Phase 1
grep -E "Alamofire|Moya|KeychainAccess|XCoordinator" Package.swift
# Expected: no output
```

## Architecture Patterns

### System Architecture Diagram (Phase 2 data flow)

```
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                      APIClient (Core/Networking)                          │
 │                                                                            │
 │  Caller: authRepo.requestOTP(phone: "+14155550129")                       │
 │        │                                                                   │
 │        ▼                                                                   │
 │  APIClient.request(OTPRequestEndpoint(phone: phone))                      │
 │        │ (typed endpoint → typed response)                                 │
 │        ▼                                                                   │
 │  APIClient.encode(endpoint) → URLRequest                                   │
 │        │                                                                   │
 │        ▼                                                                   │
 │   ┌──────────── Interceptor Chain ────────────┐                           │
 │   │                                              │                         │
 │   │  IdempotencyInterceptor (NET-04)             │                         │
 │   │    if method == POST: set Idempotency-Key:   │                         │
 │   │                       UUID().uuidString      │                         │
 │   │                                              │                         │
 │   │  AuthTokenInterceptor (Phase 3)              │                         │
 │   │    (not Phase 2 scope; header hook exists)   │                         │
 │   │                                              │                         │
 │   │  RetryInterceptor (NET-05)                   │                         │
 │   │    if method == GET and (5xx or networkErr): │                         │
 │   │       retry up to 3× with exponential        │                         │
 │   │       backoff (0.5s × 2^n + ±20% jitter,     │                         │
 │   │       ceiling 4s)                            │                         │
 │   │    if method == POST: NEVER retry            │                         │
 │   │                                              │                         │
 │   └──────────────┬───────────────────────────────┘                         │
 │                  ▼                                                          │
 │   NetworkClient.send(URLRequest) → (Data, HTTPURLResponse)                 │
 │        │                                                                   │
 │        ▼                                                                   │
 │   URLSession (selected by AppContainer per NetworkConfig)                  │
 │        │                                                                   │
 │        ├─── .mock ────▶ URLSessionConfiguration.ephemeral                  │
 │        │                + protocolClasses = [MockURLProtocol.self]         │
 │        │                (no pinning; hits in-process fixtures)             │
 │        │                                                                   │
 │        └─── .live(baseURL:) ─▶ URLSessionConfiguration.default             │
 │                                 + delegate: PinningSessionDelegate          │
 │                                 (SEC-01 dual-SPKI validation)               │
 │                                                                              │
 │  Response decode: APIClient.decode(Data, HTTPURLResponse) → T.Response     │
 │        │                                                                   │
 │        └─▶ Typed success (or throws typed NetworkError on decode/http)     │
 └──────────────────────────────────────────────────────────────────────────┘

 ┌──────────────────────────────────────────────────────────────────────────┐
 │                Secure Enclave KeyStore (Core/KeyStore)                    │
 │                                                                            │
 │  First successful OTP verify (Phase 3 trigger):                           │
 │    authRepo.onOTPVerified() →                                             │
 │      keyStore.generateDeviceIdentityKeys()  ← DEV-01                      │
 │                                                                            │
 │  generateDeviceIdentityKeys():                                             │
 │    1. deviceKey = SecKeyCreateRandomKey({                                  │
 │         kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,                  │
 │         kSecAttrKeySizeInBits: 256,                                        │
 │         kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,                     │
 │         kSecPrivateKeyAttrs: {                                             │
 │           kSecAttrIsPermanent: true,                                       │
 │           kSecAttrApplicationTag: "com.maldin.validationLedger.deviceKey",│
 │           kSecAttrAccessControl: SecAccessControlCreateWithFlags(          │
 │             kSecAttrAccessibleWhenUnlockedThisDeviceOnly,                  │
 │             [.privateKeyUsage, .devicePasscode],  // DEV-02 deviceKey      │
 │             &error)                                                        │
 │         }                                                                  │
 │       })                                                                   │
 │                                                                            │
 │    2. authorizationKey = SecKeyCreateRandomKey({                           │
 │         kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,                  │
 │         kSecAttrKeySizeInBits: 256,                                        │
 │         kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,                     │
 │         kSecPrivateKeyAttrs: {                                             │
 │           kSecAttrIsPermanent: true,                                       │
 │           kSecAttrApplicationTag: "com.maldin.validationLedger.authKey",  │
 │           kSecAttrAccessControl: SecAccessControlCreateWithFlags(          │
 │             kSecAttrAccessibleWhenUnlockedThisDeviceOnly,                  │
 │             [.privateKeyUsage, .biometryCurrentSet],  // DEV-02 authKey    │
 │             &error)                                                        │
 │         }                                                                  │
 │       })                                                                   │
 │                                                                            │
 │    3. Public key: SecKeyCopyPublicKey(deviceKey) → sent on /device/register│
 │       (DEV-01 registration payload)                                        │
 │                                                                            │
 │  Signing (sensitive operations, DEV-02):                                    │
 │    SecKeyCreateSignature(authorizationKey,                                  │
 │                          .ecdsaSignatureMessageX962SHA256,                  │
 │                          data,                                              │
 │                          &err)                                              │
 │    → iOS prompts Face ID / Touch ID because of .biometryCurrentSet         │
 │    → returns DER-encoded ECDSA signature                                    │
 │                                                                            │
 │  Key retrieval (subsequent launches):                                       │
 │    SecItemCopyMatching({                                                    │
 │      kSecClass: kSecClassKey,                                               │
 │      kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,                      │
 │      kSecAttrApplicationTag: "com.maldin.validationLedger.deviceKey",      │
 │      kSecReturnRef: true                                                    │
 │    }) → SecKey reference (the key material stays in the enclave)           │
 │                                                                            │
 │  Biometric re-enrollment (Phase 3 SESS-03 consumer):                        │
 │    authorizationKey signing fails with errSecAuthFailed or                  │
 │    errSecInvalidKey (-25293) → SessionLockService triggers re-bind flow    │
 └──────────────────────────────────────────────────────────────────────────┘
```

[VERIFIED: Apple `protecting-keys-with-the-secure-enclave`, Apple `SecKeyCreateSignature` docs, Gridnev Medium article cross-check]

### Recommended Project Structure (Phase 2 end state)

```
validationLedger/
├── Core/
│   ├── Networking/
│   │   ├── NetworkClient.swift          # FIX CR-01; NetworkError enum here
│   │   ├── APIClient.swift              # NEW — typed endpoint facade
│   │   ├── APIEndpoint.swift            # NEW — protocol (path, method, request/response types)
│   │   ├── NetworkError.swift           # NEW — typed errors (unexpectedResponseType, decode, http)
│   │   ├── Endpoints/
│   │   │   ├── OTPRequestEndpoint.swift            # NET-01 M1 endpoint 1
│   │   │   ├── OTPVerifyEndpoint.swift             # NET-01 M1 endpoint 2
│   │   │   ├── DeviceRegisterEndpoint.swift        # NET-01 + DEV-01 + DEV-05
│   │   │   ├── KYCUploadInitEndpoint.swift         # NET-01 M1 endpoint 4
│   │   │   ├── KYCUploadChunkEndpoint.swift        # NET-01 M1 endpoint 5
│   │   │   ├── KYCUploadCommitEndpoint.swift       # NET-01 M1 endpoint 6
│   │   │   └── KYCStatusEndpoint.swift             # NET-01 M1 endpoint 7
│   │   ├── Interceptors/
│   │   │   ├── RequestInterceptor.swift            # protocol
│   │   │   ├── IdempotencyInterceptor.swift        # NET-04
│   │   │   └── RetryInterceptor.swift              # NET-05
│   │   ├── Mock/
│   │   │   ├── MockURLProtocol.swift               # EXTEND: per-endpoint registry + NSLock (WR-01 fix)
│   │   │   ├── MockFixture.swift                   # NEW — JSON fixture container
│   │   │   └── Fixtures/
│   │   │       ├── otp-request-success.json        # NET-02 success fixture
│   │   │       ├── otp-request-failure.json        # NET-02 failure fixture
│   │   │       ├── otp-verify-success.json
│   │   │       ├── otp-verify-failure.json
│   │   │       ├── device-register-success.json
│   │   │       ├── device-register-failure.json
│   │   │       ├── kyc-upload-init-success.json
│   │   │       ├── kyc-upload-init-failure.json
│   │   │       ├── kyc-upload-chunk-success.json
│   │   │       ├── kyc-upload-chunk-failure.json
│   │   │       ├── kyc-upload-commit-success.json
│   │   │       ├── kyc-upload-commit-failure.json
│   │   │       ├── kyc-status-success.json
│   │   │       └── kyc-status-failure.json
│   │   └── CertificatePinning/
│   │       ├── PinningSessionDelegate.swift        # FILL IN — dual-SPKI validation
│   │       ├── PinnedSPKIs.swift                   # NEW — compile-time SPKI constants (staging + release)
│   │       └── SPKIHasher.swift                    # NEW — SubjectPublicKeyInfo → SHA-256 → Base64
│   ├── KeyStore/
│   │   ├── KeyStoreProtocol.swift                  # EXTEND: add generateDeviceIdentityKeys() + signWithAuthorization()
│   │   ├── SoftwareKeyStore.swift                  # EXTEND: match new protocol surface for sim
│   │   └── SecureEnclaveKeyStore.swift             # FILL IN — SecKeyCreateRandomKey + SecKeyCreateSignature
│   └── Identity/
│       └── DeviceFingerprint.swift                 # NEW — DEV-05
├── App/
│   ├── AppContainer.swift                          # EXTEND: URLSession factory switch .mock vs .live(baseURL:)
│   └── Environment.swift                           # EXTEND: apiBaseURL non-nil for Phase 2 (or PHASE-2-TODO marker)
├── validationLedgerTests/
│   └── Networking/
│       ├── APIClientEndpointTests.swift            # NET-01 + NET-02 success/failure decode
│       ├── IdempotencyInterceptorTests.swift       # NET-04
│       ├── RetryInterceptorTests.swift             # NET-05 (uses @Test with parameterized status codes)
│       ├── MockURLProtocolRegistryTests.swift      # WR-01 lock + serialized suite
│       └── CertificatePinningTests.swift           # SEC-01 dual-pin accept + third-cert reject
├── validationLedgerDeviceTests/
│   ├── SecureEnclaveKeyStoreTests.swift            # DEV-01/02 real-device round-trip
│   └── RefuseLaunchWithoutSecureEnclaveTests.swift # DEV-03 forced-stub test (SC-4)
└── docs/
    └── cert-rotation.md                            # EXPAND Phase 1 skeleton to full runbook (SEC-01)
```

[VERIFIED: file paths cross-checked against Phase 1 directory layout + kickoff brief requirements]

### Pattern 1: Typed APIEndpoint protocol (NET-01)

**What:** Each M1 endpoint is a struct conforming to `APIEndpoint` with associatedtypes for request body and response body. `APIClient.request(_ endpoint: some APIEndpoint)` is the one call site.

**When to use:** Every non-streaming HTTP call. Chunked uploads (Phase 5) get a separate endpoint-streaming protocol.

**Why this shape:**
- Pins the mock fixture to the endpoint type (one endpoint = one fixture file naming convention).
- Compiles out call-site type errors: `try await client.request(OTPRequestEndpoint(phone: "..."))` returns `OTPRequestResponse` statically.
- Swappable base URL: endpoint holds `path`; `APIClient` composes with `Environment.apiBaseURL` (live) or `URL(string: "https://mock.local")` (mock).

```swift
// Core/Networking/APIEndpoint.swift
public protocol APIEndpoint<Response>: Sendable {
    associatedtype RequestBody: Encodable & Sendable
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: RequestBody? { get }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// Core/Networking/Endpoints/OTPRequestEndpoint.swift
public struct OTPRequestEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable { public let phone: String }  // E.164
    public struct Response: Decodable, Sendable { public let otpSessionID: String; public let expiresInSeconds: Int }
    public let path = "/auth/otp/request"
    public let method: HTTPMethod = .post
    public let body: RequestBody?
    public init(phone: String) { self.body = RequestBody(phone: phone) }
}
```

[VERIFIED: researcher recommendation; planner confirms against other endpoint shapes like `Request<Endpoint>` (Kickstarter-style) or Moya-style enum. Rejected Moya — banned dep.]

### Pattern 2: MockURLProtocol fixture registry (NET-02) + WR-01 lock fix

**What:** Upgrade the Phase 1 single-handler array to an endpoint-keyed fixture registry, plus NSLock synchronization (fixes WR-01).

**Why the lock is not optional:** Swift Testing runs tests in parallel by default. Two tests registering different handlers concurrently are a write-write race on `Self.handlers`. The Phase 1 REVIEW flagged this; Phase 2 MUST fix before adding 14 new fixtures (7 endpoints × 2 outcomes).

**Why also use `@Suite(.serialized)`:** The lock protects the handlers array, but if test A registers a fixture, test B runs concurrently on the same MockURLProtocol, they'll see each other's fixtures and mismatch. `.serialized` serializes the suite; the lock is still needed for robustness against future accidental parallel calls. Belt + suspenders.

```swift
// Core/Networking/Mock/MockURLProtocol.swift (replacement)
public final class MockURLProtocol: URLProtocol {
    public typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)?

    private static let handlersLock = NSLock()
    private static var _handlers: [Handler] = []

    public static func register(_ handler: @escaping Handler) {
        handlersLock.withLock { _handlers.append(handler) }
    }

    public static func reset() {
        handlersLock.withLock { _handlers.removeAll() }
    }

    private static var currentHandlers: [Handler] {
        handlersLock.withLock { _handlers }
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func stopLoading() {}

    public override func startLoading() {
        for handler in Self.currentHandlers {
            if let (response, data) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        // No handler matched — 404
        let url = request.url ?? URL(string: "about:blank")!
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// Test-side fixture helper:
extension MockURLProtocol {
    /// Convenience: register a fixture for a specific endpoint by matching path + method.
    public static func registerFixture<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data
    ) {
        register { request in
            guard request.url?.path == path,
                  request.httpMethod == method.rawValue else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
    }
}
```

Test usage:
```swift
@Suite("APIClient OTP endpoints", .serialized)
struct APIClientOTPTests {
    @Test("OTP request success decodes typed model")
    func otpRequestSuccess() async throws {
        MockURLProtocol.reset()
        let fixtureData = try fixtureBundle.loadJSON("otp-request-success")
        MockURLProtocol.registerFixture(
            for: OTPRequestEndpoint.self,
            path: "/auth/otp/request",
            method: .post,
            statusCode: 200,
            body: fixtureData
        )
        let client = makeTestAPIClient()
        let resp = try await client.request(OTPRequestEndpoint(phone: "+14155550129"))
        #expect(resp.otpSessionID == "sess-abc-123")
    }
}
```

[VERIFIED: Phase 1 REVIEW.md WR-01 fix sketch + [Swift Testing `.serialized` docs](https://developer.apple.com/documentation/testing/trait/serialized)]

### Pattern 3: NetworkConfig → URLSession factory (NET-03)

**What:** `AppContainer` holds a single method that builds the URLSession based on `NetworkConfig`. Swap site = `AppContainer.init(env:)` — nothing else changes.

```swift
// App/AppContainer.swift (excerpt — Phase 2 additions)
final class AppContainer {
    // ...existing Phase 1 properties...
    let apiClient: APIClient

    init(env: Environment, networkConfig: NetworkConfig = Self.defaultNetworkConfig(env: env)) {
        // ...existing Phase 1 wiring...

        let session = Self.makeSession(networkConfig: networkConfig)
        let networkClient = URLSessionNetworkClient(config: networkConfig, session: session)
        let interceptors: [any RequestInterceptor] = [
            IdempotencyInterceptor(),
            RetryInterceptor(maxRetries: 3),
        ]
        self.apiClient = APIClient(
            baseURL: networkConfig.baseURL ?? URL(string: "https://mock.local")!,
            networkClient: networkClient,
            interceptors: interceptors
        )
    }

    private static func defaultNetworkConfig(env: Environment) -> NetworkConfig {
        #if DEBUG
        return .mock
        #else
        guard let baseURL = env.apiBaseURL else {
            fatalError("Release build requires Environment.apiBaseURL (fix WR-06 before Phase 2 Release build)")
        }
        return .live(baseURL: baseURL)
        #endif
    }

    private static func makeSession(networkConfig: NetworkConfig) -> URLSession {
        switch networkConfig {
        case .mock:
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            return URLSession(configuration: config)
        case .live:
            let config = URLSessionConfiguration.default
            return URLSession(
                configuration: config,
                delegate: PinningSessionDelegate(pins: PinnedSPKIs.current),
                delegateQueue: nil
            )
        }
    }
}

extension NetworkConfig {
    var baseURL: URL? {
        switch self {
        case .mock: return URL(string: "https://mock.local")
        case .live(let url): return url
        }
    }
}
```

**Call-site invariant:** NO caller ever references `URLSession`, `URLProtocol`, or `PinningSessionDelegate` directly. They all go through `AppContainer.apiClient`. This is how "swap is one line" stays true.

[VERIFIED: Phase 1 AppContainer.swift pattern + kickoff brief NET-03]

### Pattern 4: PinningSessionDelegate — dual-SPKI validation (SEC-01)

**What:** Server trust challenge callback validates the leaf cert's SPKI hash against TWO pinned hashes (primary + backup). Accept if *either* matches. Reject otherwise with `.cancelAuthenticationChallenge`.

**Why dual-pin, not single-pin:** A single-pin deployment means the day the cert expires OR is compromised, every installed app version is bricked. Apps take days to propagate. Dual-pin gives a ≥30-day rotation window (swap primary → primary+backup → ship → wait for adoption → rotate → ship). This is the industry standard; the self-brick DoS without it is a cert-rotation-phase incident waiting to happen.

**Why hand-rolled, not NSPinnedDomains:** See §Alternatives Considered. The one-sentence version: NSPinnedDomains stores the hashes in a plaintext plist that's trivially tamperable via app repackaging. For a security-first freight-identity product, that's the wrong trust model. Compile-time Swift constants require binary patching.

**Why SPKI hashes, not full-cert hashes:** SPKI (Subject Public Key Info) survives certificate renewal as long as the same key pair is used. Full-cert hash invalidates on every renewal. SPKI is the RFC-7469 recommended format.

```swift
// Core/Networking/CertificatePinning/PinnedSPKIs.swift
public struct PinnedSPKIs: Sendable {
    /// Base64-encoded SHA-256 of SubjectPublicKeyInfo (DER).
    public let primary: String
    public let backup: String

    public static let staging = PinnedSPKIs(
        primary: "PHASE2-TODO-STAGING-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-STAGING-BACKUP-SPKI-SHA256-BASE64"
    )
    public static let release = PinnedSPKIs(
        primary: "PHASE2-TODO-RELEASE-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-RELEASE-BACKUP-SPKI-SHA256-BASE64"
    )
    public static var current: PinnedSPKIs {
        #if DEBUG
        return .staging
        #else
        return .release
        #endif
    }
}

// Core/Networking/CertificatePinning/PinningSessionDelegate.swift (FILL IN)
import Foundation
import Security
import CryptoKit

public final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    private let pins: PinnedSPKIs
    public init(pins: PinnedSPKIs) { self.pins = pins; super.init() }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let leafCert = SecTrustCopyCertificateChain(serverTrust).flatMap({
                  ($0 as? [SecCertificate])?.first
              }) ?? SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate the server trust first (chain + hostname + expiry).
        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract SPKI from the leaf cert and compare against pinned hashes.
        guard let leafSPKIHash = SPKIHasher.spkiSHA256Base64(from: leafCert) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if leafSPKIHash == pins.primary || leafSPKIHash == pins.backup {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Pin mismatch — log via Core/Logging (DO NOT log the actual hash —
            // it's not PII but is infrastructure signal that shouldn't be in info logs).
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

**SPKI extraction helper:** This is the tricky bit — the public key from `SecCertificateCopyKey` needs the correct ASN.1 header prepended before hashing for RFC-7469 compliance. For EC P-256 certificates (what Validation Ledger's backend will use per the typical TLS profile), the ASN.1 header is a 26-byte prefix.

```swift
// Core/Networking/CertificatePinning/SPKIHasher.swift
import Foundation
import Security
import CryptoKit

public enum SPKIHasher {
    /// ASN.1 header for EC P-256 SubjectPublicKeyInfo (secp256r1 / prime256v1).
    /// Precedes the raw public key bytes returned by SecKeyCopyExternalRepresentation.
    private static let ecP256ASN1Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    public static func spkiSHA256Base64(from certificate: SecCertificate) -> String? {
        // iOS 15+: SecCertificateCopyKey replaces deprecated SecTrustCopyPublicKey.
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        // The raw key bytes need the ASN.1 header prepended for RFC-7469 SPKI hash.
        // Note: If the backend serves RSA certs, the header is different — extend as needed.
        var spki = Data()
        spki.append(contentsOf: ecP256ASN1Header)
        spki.append(keyData)
        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }
}
```

**Known complexity:** The ASN.1 header varies by key algorithm. EC P-256 is 26 bytes (shown above); RSA 2048 is 24 bytes with different values; RSA 4096 is 25 bytes. If the backend serves a mixed-algorithm cert chain, the header must match the actual key algorithm. **For Validation Ledger M1, the backend is TBD (separate GSD project), but EC P-256 is the modern default and a reasonable assumption. Flag for confirmation with backend team once real URL exists.** [ASSUMED]

**SPKI extraction procedure (for `docs/cert-rotation.md` flesh-out):**
```bash
# Extract from live server:
openssl s_client -connect api.validationledger.com:443 -servername api.validationledger.com </dev/null 2>/dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64

# Extract from a PEM cert file:
openssl x509 -in leaf-cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
```

[VERIFIED: [Secure Vale — Deep Dive into Certificate Pinning on iOS](https://securevale.blog/articles/deep-dive-into-certificate-pinning-on-ios/), [Serverless.lk — Certificate Pinning in iOS: The Right Way](https://serverless.lk/certificate-pinning-in-ios-the-right-way/), [Guardsquare — Leveraging Info.plist-based pinning](https://www.guardsquare.com/blog/leveraging-infoplist-based-certificate-pinning-ios-and-making-its-shortcomings)]

### Pattern 5: IdempotencyInterceptor (NET-04)

**What:** On every POST (and PUT) request, inject an `Idempotency-Key` header set to `UUID().uuidString`. Header is per-request, not persistent, not cached.

**Why UUID().uuidString and not hash(body)?** Stripe recommends UUIDv4 with 128 bits of entropy. `Foundation.UUID()` is UUIDv4 by default on Darwin. Content hashing would be a valid alternative but ties the idempotency semantics to body equivalence — if the user retries with a slightly modified body, it's a new operation, which is wrong. A fresh UUID per original request + replay (Phase 5 upload chunks) is the industry pattern.

**Why only POST + PUT, not GET?** GET is idempotent by HTTP spec; no key needed. NET-05 says "retry on idempotent GETs only," which assumes GET is idempotent. DELETE is idempotent (deleting twice is the same as once) but server-side idempotency-key machinery usually covers it. Scope Phase 2 to POST + PUT; extend if needed.

```swift
// Core/Networking/Interceptors/RequestInterceptor.swift
public protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

public protocol ResponseInterceptor: Sendable {
    func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}

// Core/Networking/Interceptors/IdempotencyInterceptor.swift
public struct IdempotencyInterceptor: RequestInterceptor {
    public init() {}
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        guard let method = request.httpMethod,
              method == "POST" || method == "PUT" else { return request }
        // Only inject if absent — caller may have set it (explicit replay path for Phase 5).
        guard request.value(forHTTPHeaderField: "Idempotency-Key") == nil else { return request }
        var req = request
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        return req
    }
}
```

**Testing note:** IdempotencyInterceptor is deterministic-modulo-UUID-generation. Parameterized unit tests should verify (a) header is set for POST, (b) header is set for PUT, (c) header is NOT set for GET, (d) header is NOT overwritten if already present (Phase 5 replay path). Don't assert the exact UUID value.

[VERIFIED: [Stripe: Designing robust and predictable APIs with idempotency](https://stripe.com/blog/idempotency), [IETF draft-ietf-httpapi-idempotency-key-header](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/)]

### Pattern 6: RetryInterceptor with HTTP-method gate (NET-05)

**What:** Wrap the send call; if method is GET and response is 5xx or URLError.networkConnectionLost, retry up to 3× with exponential backoff + jitter. POST never retries implicitly — if the caller wants retry on POST, they do it explicitly with `Idempotency-Key` replay (which reuses the same UUID across retries — out-of-scope for Phase 2; Phase 5 UPL-03 builds this).

**Backoff schedule (researcher recommendation; planner confirms):**
- Base: 500ms
- Backoff: `base * 2^attempt` → 500ms, 1000ms, 2000ms
- Jitter: ±20% (uniform random)
- Ceiling: 4000ms (caps runaway backoff)

**Why GET-only retry:** Per NET-05. A retry on POST without an idempotency key is *unsafe* — the server may have committed the first attempt before the response was lost on the network. The idempotency-key mechanism is how POST retries work correctly.

```swift
// Core/Networking/Interceptors/RetryInterceptor.swift
public struct RetryInterceptor: ResponseInterceptor {
    private let maxRetries: Int
    private let baseDelayMs: UInt64
    private let ceilingMs: UInt64

    public init(maxRetries: Int = 3, baseDelayMs: UInt64 = 500, ceilingMs: UInt64 = 4000) {
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.ceilingMs = ceilingMs
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        // Only GET is retry-eligible per NET-05.
        guard request.httpMethod == "GET" else { return try await send(request) }

        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await send(request)
                // Retry on 5xx; return on 4xx (caller handles).
                if (500...599).contains(response.statusCode), attempt < maxRetries {
                    try await Task.sleep(nanoseconds: delayForAttempt(attempt) * 1_000_000)
                    continue
                }
                return (data, response)
            } catch let error as URLError where isRetryable(error) {
                lastError = error
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: delayForAttempt(attempt) * 1_000_000)
                    continue
                }
            }
        }
        throw lastError ?? NetworkError.retriesExhausted
    }

    private func delayForAttempt(_ attempt: Int) -> UInt64 {
        let base = baseDelayMs << attempt  // 500, 1000, 2000
        let capped = min(base, ceilingMs)
        // ±20% jitter
        let jitterRange = Double(capped) * 0.2
        let jitter = Int64.random(in: Int64(-jitterRange)...Int64(jitterRange))
        return UInt64(max(0, Int64(capped) + jitter))
    }

    private func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
```

**Test strategy:** Parameterized `@Test` with status codes [500, 502, 503, 504, 429] asserting retry; status codes [200, 400, 401, 404] asserting NO retry; HTTP methods [POST, PUT, DELETE] asserting NO retry. URLError cases exercised via a throwing handler in MockURLProtocol.

[VERIFIED: Stripe exponential-backoff-with-jitter pattern; kickoff brief NET-05]

### Pattern 7: SecureEnclaveKeyStore — two-key pattern (DEV-01 + DEV-02)

**What:** Generate and store two distinct EC P-256 keypairs in the Secure Enclave, each with a different Access Control profile. Never reuse the same key for both identity and authorization.

**Why two keys:**
- `deviceKey` (passcode-only ACL): Used for device-identity signatures on every request. Accessible whenever the device is unlocked. If this required biometric prompt, every API call would prompt Face ID — UX failure.
- `authorizationKey` (biometry-current-set ACL): Used ONLY for sensitive operations (tender/accept/BOL generation in M2+). Prompts biometric each time. Invalidates on biometric re-enrollment by design (SESS-03 detection).

**Why `.biometryCurrentSet` and NOT `.biometryAny`:** `.biometryCurrentSet` invalidates the key if the user re-enrolls Face ID (adds a finger, replaces the face scan, etc.). This is the ENTIRE POINT — if someone steals the phone and enrolls their own biometrics, the key becomes useless. `.biometryAny` would continue working, defeating the security posture. **DO NOT change this to `.biometryAny` for UX convenience — it breaks the trust story.**

**Why not `SecureEnclave.P256.Signing.PrivateKey` (CryptoKit):** CryptoKit's convenience wrapper does not expose `.biometryCurrentSet` — it creates keys with no access control (just enclave-scoped). For DEV-02 we need explicit ACL flags, which requires the lower-level `SecKeyCreateRandomKey` + `SecAccessControlCreateWithFlags` path.

**Key storage model:** The actual EC private key material NEVER leaves the Secure Enclave. What we store in Keychain is the *persistent reference* (the `kSecAttrApplicationTag`). On relaunch, `SecItemCopyMatching` returns a `SecKey` reference that points back to the enclave-held key.

```swift
// Core/KeyStore/SecureEnclaveKeyStore.swift (FILL IN)
import Foundation
import Security
import CryptoKit

public final class SecureEnclaveKeyStore: KeyStoreProtocol {
    public enum Keyslot {
        case device
        case authorization
        public var applicationTag: Data {
            switch self {
            case .device:        return "com.maldin.validationLedger.deviceKey".data(using: .utf8)!
            case .authorization: return "com.maldin.validationLedger.authKey".data(using: .utf8)!
            }
        }
    }

    public init() {}

    /// DEV-01: Generate both keys on first successful OTP verify.
    public func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data) {
        let devKey = try generateKey(
            slot: .device,
            flags: [.privateKeyUsage, .devicePasscode]  // DEV-02: passcode-only
        )
        let authKey = try generateKey(
            slot: .authorization,
            flags: [.privateKeyUsage, .biometryCurrentSet]  // DEV-02: biometric, invalidate on re-enroll
        )
        return (devKey, authKey)
    }

    /// Sign with deviceKey — used for regular API requests (e.g. request signing).
    public func sign(_ data: Data) throws -> Data {
        try sign(data: data, slot: .device)
    }

    /// Sign with authorizationKey — biometric prompt; used for sensitive operations.
    /// Phase 2 ships this method; Phase 3+ SESS-03 consumes it to detect re-enrollment.
    public func signWithAuthorization(_ data: Data) throws -> Data {
        try sign(data: data, slot: .authorization)
    }

    public func publicKeyRepresentation() throws -> Data {
        try loadPublicKey(slot: .device)
    }

    // MARK: - Private

    private func generateKey(slot: Keyslot, flags: SecAccessControlCreateFlags) throws -> Data {
        var acError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &acError
        ) else {
            throw KeyStoreError.keyGenerationFailed(acError?.takeRetainedValue())
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: slot.applicationTag,
                kSecAttrAccessControl: accessControl,
            ] as CFDictionary,
        ]

        var genError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &genError) else {
            throw KeyStoreError.keyGenerationFailed(genError?.takeRetainedValue())
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeyStoreError.keyGenerationFailed(nil)
        }
        return data
    }

    private func loadPrivateKey(slot: Keyslot) throws -> SecKey {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: slot.applicationTag,
            kSecReturnRef: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let key = item else {
            throw KeyStoreError.keyUnavailable
        }
        return (key as! SecKey)
    }

    private func loadPublicKey(slot: Keyslot) throws -> Data {
        let privateKey = try loadPrivateKey(slot: slot)
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw KeyStoreError.keyUnavailable
        }
        return data
    }

    private func sign(data: Data, slot: Keyslot) throws -> Data {
        let privateKey = try loadPrivateKey(slot: slot)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw KeyStoreError.signingFailed
        }
        return signature
    }
}

// Core/KeyStore/KeyStoreProtocol.swift — EXTEND:
public enum KeyStoreError: Error, Sendable {
    case notImplemented
    case signingFailed
    case keyUnavailable
    case keyGenerationFailed(CFError?)
}
```

**Protocol extension required:** `KeyStoreProtocol` currently (Phase 1) exposes `sign(_:)` and `publicKeyRepresentation()`. Phase 2 must extend it:
```swift
public protocol KeyStoreProtocol: AnyObject, Sendable {
    func sign(_ data: Data) throws -> Data
    func publicKeyRepresentation() throws -> Data

    // NEW in Phase 2:
    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data)
    func signWithAuthorization(_ data: Data) throws -> Data
}
```
`SoftwareKeyStore` must also implement the new methods — in-memory CryptoKit `P256.Signing.PrivateKey` for each slot; biometry not applicable on simulator.

[VERIFIED: [Apple protecting-keys-with-the-secure-enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave), [Apple biometryCurrentSet flag docs](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/ksecaccesscontrolbiometrycurrentset), [Gridnev — iOS Keychain using Secure Enclave-stored keys](https://medium.com/@alx.gridnev/ios-keychain-using-secure-enclave-stored-keys-8f7c81227f4)]

### Pattern 8: DeviceFingerprint + installUUID (DEV-05)

**What:** A tiny service that assembles the `/device/register` device-fingerprint payload. Install UUID is generated on first launch AFTER the Phase 1 D-20 wipe; persisted to Keychain; survives reinstall only until the next fresh install.

**Why Keychain for installUUID and not UserDefaults:** UserDefaults is cleared on uninstall — which is what we WANT for the FOUND-02 wipe flag (re-wipes on reinstall). The installUUID should likewise be new on every reinstall (because the FOUND-02 wipe clears it too). But it MUST be stable across app launches, and MUST NOT appear in plaintext plists. Keychain with `afterFirstUnlockThisDeviceOnly` is the right profile.

```swift
// Core/Identity/DeviceFingerprint.swift
import UIKit

public struct DeviceFingerprint: Encodable, Sendable {
    public let model: String          // e.g., "iPhone15,2"
    public let iosVersion: String     // e.g., "17.5.1"
    public let installUUID: String    // UUID().uuidString; Keychain-persisted

    public static func current(keychain: KeychainStore) throws -> DeviceFingerprint {
        let installUUIDKey = KeychainKey(rawValue: "device.install_uuid")
        let installUUID: String
        if let existing = try? keychain.get(installUUIDKey),
           let decoded = String(data: existing, encoding: .utf8) {
            installUUID = decoded
        } else {
            installUUID = UUID().uuidString
            try keychain.set(
                Data(installUUID.utf8),
                for: installUUIDKey,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
        return DeviceFingerprint(
            model: UIDevice.current.modelIdentifier(),
            iosVersion: UIDevice.current.systemVersion,
            installUUID: installUUID
        )
    }
}

private extension UIDevice {
    /// Returns hardware identifier (e.g., "iPhone15,2") — more specific than `.model`.
    func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
```

**Privacy-manifest note:** `UIDevice.current.systemVersion` is not a required-reason API. `utsname()` is not either. Install UUID is app-scoped and doesn't meet the IDFA-like definition. No PrivacyInfo.xcprivacy changes needed. [VERIFIED: Apple PrivacyInfo.xcprivacy docs; kickoff brief DEV-05]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding/decoding | Custom codec | `JSONEncoder` + `JSONDecoder` with typed models | Foundation handles Unicode, date strategies, snake_case key conversions. Custom codecs are bug factories. |
| Base64 encoding | Custom encoder | `Data.base64EncodedString()` | Trivially correct in Foundation; no reason to re-derive. |
| SHA-256 | Custom hash | `CryptoKit.SHA256.hash(data:)` | Hardware-accelerated on iOS; constant-time. |
| EC key pair generation | Manual ASN.1 synthesis | `SecKeyCreateRandomKey` with `kSecAttrKeyTypeECSECPrimeRandom` | Producing a valid EC keypair requires curve-point validation that no app should own. |
| EC signing | Manual ECDSA | `SecKeyCreateSignature(.ecdsaSignatureMessageX962SHA256)` | Hardware-accelerated; constant-time; tested by every TLS stack on the planet. |
| UUID generation | Counter + timestamp | `UUID()` (UUIDv4, 122-bit random) | Meets Stripe's "≥128 bits entropy" requirement. |
| Exponential backoff library | Package dep | ~40 LOC hand-rolled `RetryInterceptor` | Interceptor is tiny; libs (Rxswift-style) bring dependency weight. |
| HTTP client | Alamofire, Moya, URLSession wrapper library | `URLSession` directly + interceptor chain | Banned by STACK-01; URLSession + async/await is sufficient for REST on iOS 17. |
| Cert pinning library | TrustKit, AlamofireExtensions | Hand-rolled URLSessionDelegate + SPKIHasher | ~150 LOC; no abandoned-lib risk; security-critical code should live in-tree. |
| Keychain wrapper | KeychainAccess | Phase 1's hand-rolled `KeychainStore` | KeychainAccess is abandoned (2021); our 150-LOC wrapper is already in Phase 1. |
| Idempotency-key server-side machinery | Backend — NOT our code | — | Phase 2 is client-side only. Server enforces deduplication. |

**Key insight:** The entire Phase 2 networking + key stack is ≤ ~500 LOC of hand-rolled code composing Apple APIs. Adding external deps for crypto, HTTP, or key management is strictly worse for a security-first product: more code to audit, more deprecation risk, more supply-chain exposure. The only external dep is Nuke (images) and SwiftLintPlugins (build tool) — both from Phase 1, both consumed for non-security concerns.

## Runtime State Inventory

> This is not a rename/refactor phase. However, Phase 2 *does* add persistent state that later phases depend on — surfacing those items explicitly is useful for the planner and for Phase 3's consumer wiring.

| Category | Items Added by Phase 2 | Downstream Consumers |
|----------|-----------------------|----------------------|
| Stored data (Keychain) | `device.install_uuid` (DEV-05); `com.maldin.validationLedger.deviceKey` persistent ref (DEV-01); `com.maldin.validationLedger.authKey` persistent ref (DEV-02) | Phase 3 (`/device/register` payload uses installUUID + devicePublicKey); Phase 5 KYC submit may sign chunks with deviceKey |
| Secure Enclave state | Two EC P-256 keypairs in the enclave, addressed by applicationTag | Phase 3 SESS-03 re-enrollment detection; M2+ sensitive-action signing |
| OS-registered state | None — Phase 2 registers no OS-level state | — |
| Secrets/env vars | None added — compile-time SPKI constants are source-controlled | — |
| Build artifacts | Compile-time `PinnedSPKIs.release` and `.staging` become part of the binary | Phase 4 TestFlight build picks up release SPKIs |
| Live service config | None — backend is a separate GSD project | — |

**Nothing new in category (explicit):**
- OS-registered state: None.
- Env vars: None.
- Live service config: None — backend URL lives in `Environment.apiBaseURL` (code), not service config.

## Common Pitfalls

### Pitfall 1: `.biometryCurrentSet` re-enrollment invalidation feels like a bug

**What goes wrong:** Developer sets up `authorizationKey` with `.biometryCurrentSet`, tests on device, works great. User in production adds a new fingerprint a week later → every sensitive-action sign suddenly fails with `errSecAuthFailed` (-25293) or `errSecInvalidKey`. Looks like a crypto bug; it's the intended behavior.

**Why it happens:** `.biometryCurrentSet` ties the key to the *set of enrolled biometrics at key generation time*. Any change (adding a finger, replacing a face scan, disabling Touch ID then re-enabling) invalidates the key — the Secure Enclave discards the wrapping key and the private key becomes permanently inaccessible.

**How to avoid:** Phase 3 SESS-03 detection catches this, surfaces a "re-bind device" flow. Document the behavior in the SecureEnclaveKeyStore file header and in ADR (recommend `docs/adr/0004-secure-enclave-two-key-pattern.md` as a Phase 2 deliverable). DO NOT switch to `.biometryAny` to "fix" it — that removes the security property. [VERIFIED: [Apple biometryCurrentSet docs](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/ksecaccesscontrolbiometrycurrentset), [Gridnev — Biometry-protected entries](https://medium.com/@alx.gridnev/biometry-protected-entries-in-ios-keychain-6125e130e0d5)]

**Warning signs:**
- `SecKeyCreateSignature` returns nil with `errSecAuthFailed` after successful signings earlier in the session
- `SecItemCopyMatching` on the authKey returns `errSecItemNotFound` unexpectedly
- Tests pass locally but fail on a device where someone added a new Face ID scan

### Pitfall 2: Simulator tests for SecureEnclaveKeyStore silently "pass" without testing the enclave

**What goes wrong:** Developer writes `SecureEnclaveKeyStoreTests.swift` in `validationLedgerTests/` (simulator target), runs on simulator, tests pass. Code ships. On device, everything fails because the simulator was using `SoftwareKeyStore` the whole time (per the `#if DEBUG && targetEnvironment(simulator)` gate) and the tests never exercised `SecureEnclaveKeyStore` at all.

**Why it happens:** The simulator has no Secure Enclave. Any call to `SecKeyCreateRandomKey(attributes as CFDictionary, &error)` where `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave` is set will fail on simulator with `errSecUnimplemented` or crash depending on the iOS version. The test doesn't exercise the code path it thinks it does.

**How to avoid:** `SecureEnclaveKeyStoreTests.swift` MUST live in `validationLedgerDeviceTests/` (the self-hosted-runner device target). It MUST NOT be in `validationLedgerTests/`. Mirror the Phase 1 `SecureEnclaveSmokeTests.swift` target placement. CI configuration already excludes device tests from simulator (Phase 1 D-03 + VERIFIED Phase 1 report), so this is a discipline issue, not a tooling issue.

Companion rule: `SoftwareKeyStoreTests.swift` can be in `validationLedgerTests/` (simulator) because `SoftwareKeyStore` works everywhere. The DEV-03 forced-stub test for "refuse to launch without SE" (SC-4) goes in device target with a compiled-in override. [VERIFIED: Phase 1 `SecureEnclaveSmokeTests.swift` target membership + CONTEXT.md D-03]

**Warning signs:**
- Test file references `SecureEnclave.isAvailable` in a simulator-target file (it's always `false` there)
- Test runs green on PR CI but device CI catches first failure on merge-to-main

### Pitfall 3: `SecAccessControlCreateWithFlags` silent ACL errors

**What goes wrong:** Developer composes flags `[.privateKeyUsage, .biometryCurrentSet, .or]` thinking "or" means "biometric OR passcode," but `.or` is NOT a valid `SecAccessControlCreateFlags` value. Compilation succeeds (Swift just sees an OptionSet). The ACL is created with wrong semantics; key becomes un-unlockable or too-easily-unlockable.

**Why it happens:** `SecAccessControlCreateFlags` is a flat OptionSet without obvious named combinators. Logical OR between flag groups requires `[.or]` to be added — but only for specific combinations. Apple docs are terse. Many Stack Overflow answers are wrong.

**How to avoid:** 
1. Use EXACTLY the flag combinations documented in this research for `deviceKey` (`[.privateKeyUsage, .devicePasscode]`) and `authorizationKey` (`[.privateKeyUsage, .biometryCurrentSet]`). Do not add `.or`, `.and`, `.applicationPassword` without a review that specifically checks Apple's docs.
2. Add a device-target unit test that generates a key, attempts a sign with wrong biometric state, and asserts the expected failure code. Verifies the ACL behavior empirically.
3. Never `nil`-ignore the `Unmanaged<CFError>?` output. `acError?.takeRetainedValue()` returns the precise reason — log it.

[VERIFIED: [Apple SecAccessControlCreateFlags docs](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags)]

**Warning signs:**
- `SecKeyCreateRandomKey` returns nil and the error says "The specified access control object is invalid"
- Key generation succeeds but `SecItemCopyMatching` on the stored key returns `errSecInteractionNotAllowed` in unexpected contexts

### Pitfall 4: URLSessionDelegate challenge handling — completion handler must fire exactly once on every path

**What goes wrong:** `PinningSessionDelegate.urlSession(_:didReceive:completionHandler:)` has early-return paths that forget to call `completionHandler`. The URLSession hangs the request forever — no timeout, no error, just a stuck async await. Or the handler is called twice on different paths (double callback crashes URLSession).

**Why it happens:** The Apple URLSessionDelegate challenge API is a C-era callback contract grafted onto Swift. The compiler does not enforce that `completionHandler` is called exactly once on every return path. Manual discipline is required.

**How to avoid:**
1. Structure the delegate method as a single `defer`-guarded wrapper where the completion handler is the LAST thing called. If there are multiple early-returns, each must end with `completionHandler(...)`.
2. Write a unit test using a custom `URLProtocol` subclass that simulates the challenge — run with strict concurrency on to catch double-call assertions.
3. Use `.cancelAuthenticationChallenge` as the "safe default" on any unexpected state — never `.performDefaultHandling` as a catchall, because that opens the door to system trust evaluation (bypasses pinning).

The sketch in Pattern 4 already shows the correct single-call-per-path structure. Audit any planner-proposed changes against this rule.

[VERIFIED: Apple URLSessionDelegate docs; cross-reference with [Secure Vale cert pinning article](https://securevale.blog/articles/deep-dive-into-certificate-pinning-on-ios/)]

**Warning signs:**
- Unit test for pinning hangs forever (completion handler missed)
- Crash in URLSession internals after pinning rejection (completion handler called twice)

### Pitfall 5: Mock-vs-live swap — ATS exceptions, MockURLProtocol registration, pinning delegate

**What goes wrong:** Developer toggles `AppContainer.networking = .mock` in DEBUG, everything works. Ships to TestFlight with `.live` on. Live build crashes immediately because:
- `MockURLProtocol` is still in `URLSessionConfiguration.protocolClasses` (wasn't removed in the `.live` branch) — every request short-circuits to MockURLProtocol's 404 fallback.
- OR: `PinningSessionDelegate` was attached to the mock session too, and the mock fixture URLs don't match any pin, causing `cancelAuthenticationChallenge` for every mock response in tests.
- OR: ATS strict mode (SEC-02 Phase 1) rejects a non-HTTPS mock URL like `http://mock.local` — tests that passed in DEBUG fail mysteriously.

**Why it happens:** The mock/live swap has three orthogonal concerns (transport, pinning, protocol registration) that are easy to tangle. The Phase 1 AppContainer already shows the correct pattern (mock gets `.ephemeral` config + MockURLProtocol; live gets `.default` config + PinningSessionDelegate), but a bug-prone refactor might collapse them.

**How to avoid:**
1. The `makeSession(networkConfig:)` factory in AppContainer is the ONLY place that configures URLSessions. Any Phase 2 plan that suggests wiring a session elsewhere should be rejected by the planner.
2. `MockURLProtocol` registration is session-scoped (`config.protocolClasses = [MockURLProtocol.self]`), NEVER global (`URLProtocol.registerClass`). This keeps mock state isolated to the one session.
3. Mock URLs use `https://mock.local` (HTTPS scheme) to satisfy ATS — even though MockURLProtocol short-circuits the request before any TLS happens, URLSession pre-validates the scheme. Unit tests already do this (see Phase 1 `MockURLProtocolTests.swift:19`).
4. `PinningSessionDelegate` is ONLY attached when `networkConfig == .live`. The mock session has NO delegate.

[VERIFIED: Phase 1 AppContainer.swift lines 50-58 show the correct structure; Phase 1 MockURLProtocolTests.swift line 19 uses https://mock.local]

**Warning signs:**
- Live build returns 404 for every endpoint (mock is still registered)
- Test fails with "URL scheme not allowed" in ATS-strict mode (used http:// instead of https://)
- Live requests hang then fail with "The network connection was lost" (pin mismatch, no log)

### Pitfall 6: Cert pinning self-brick DoS

**What goes wrong:** Team rotates the production cert. Forgets to update the primary SPKI hash in the release build. New release ships. Every user's app fails to connect. Backend support tickets flood in. Recovering requires a point-release through the App Store (1-2 days minimum, 7+ days if Apple review flags anything).

**Why it happens:** Single-pin deployment with no rotation process. Or: dual-pin deployment but both pins point to the SAME cert (common mistake when adding the backup pin "later").

**How to avoid:**
1. Dual-pin is mandatory (SEC-01). Both pins MUST be from different key pairs (typically: current leaf + next-release leaf).
2. `PinnedSPKIs` has BOTH a primary and backup — a compile-time assertion or unit test should fail if they are equal strings. Plan a task for this.
3. `docs/cert-rotation.md` must have a step-by-step "before cert expiry" procedure. Phase 2 fills this in (Phase 1 is skeleton only).
4. Consider a CI check: on every cert-pinning file change, require a reviewer to attest the rotation plan.

[VERIFIED: [Serverless.lk — Certificate Pinning in iOS: The Right Way](https://serverless.lk/certificate-pinning-in-ios-the-right-way/), PITFALLS.md P3, Phase 1 `docs/cert-rotation.md` skeleton]

**Warning signs:**
- `PinnedSPKIs.primary == .backup` string equality
- `docs/cert-rotation.md` lacks a concrete "before day -30" checklist
- No CI file-change trigger on cert-pinning files

### Pitfall 7: MockURLProtocol parallel-test race (WR-01 follow-through)

**What goes wrong:** Phase 2 adds 14 fixtures (7 endpoints × 2 outcomes). Fixtures accumulate in `MockURLProtocol.handlers` across tests. Two tests run in parallel; test A registers its fixture, test B registers its fixture on top. Test A's assertion fires while test B's handler matches — test A fails mysteriously. Only reproducible under parallel execution.

**Why it happens:** Swift Testing runs tests in parallel by default. The Phase 1 MockURLProtocol uses a global mutable static array with no lock (REVIEW.md WR-01). Fine with 1 fixture and 1 test; broken at N fixtures and M parallel tests.

**How to avoid:**
1. Wrap `MockURLProtocol.handlers` in `NSLock` (see Pattern 2 code).
2. Add `@Suite(.serialized)` to every test suite that registers fixtures. This forces sequential execution within the suite, but suites run in parallel relative to each other — so add `MockURLProtocol.reset()` at the top of every test case as well. Three layers of defense.
3. Consider a redesign to per-session instance handlers (not global) in a future phase. For Phase 2, lock + serialized + reset is sufficient.

[VERIFIED: Phase 1 REVIEW.md WR-01; [Swift Forums — Mock URLProtocol with strict Swift 6 concurrency](https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135)]

**Warning signs:**
- "Flaky" tests that pass locally but fail in CI
- Tests pass when run individually but fail when run as a suite
- Test output order is non-deterministic

### Pitfall 8: Retry on POST without idempotency key (silent duplicate)

**What goes wrong:** Developer extends RetryInterceptor to retry on POST "because it's easier for the UX." User's phone has a flaky connection; POST gets retried after a transient network error. Backend commits the operation TWICE — two `/device/register` calls, two `OTPRequest` triggers (two SMS messages, rate-limit hit immediately).

**Why it happens:** POST is not idempotent by HTTP spec. A retry without an idempotency key is a second distinct operation from the server's perspective.

**How to avoid:**
1. RetryInterceptor gates on `request.httpMethod == "GET"` (and no other method). POST/PUT/DELETE never retry.
2. Unit test that parameterizes over HTTP methods and asserts retry count == 0 for non-GET.
3. Phase 5 UPL-03's "retry with same Idempotency-Key" is a SEPARATE mechanism (caller passes the same key across calls); Phase 2 does NOT implement this.

[VERIFIED: [IETF idempotency-key draft](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/); kickoff brief NET-05]

**Warning signs:**
- Two SMS OTPs arrive for one user "request OTP" tap
- `/device/register` succeeds twice, backend returns "device already registered" on second
- Backend duplicate-key analytics spike

### Pitfall 9: `Environment.release.apiBaseURL == nil` ships to TestFlight (WR-06 carryover)

**What goes wrong:** Phase 2 ships. Release build on TestFlight shows no network activity, just silently failing requests. Logs show `URLSession` reject with "URL scheme not allowed" or crashes constructing `URL(string: nil!)`. Root cause: `Environment.release` was never updated from the Phase 1 placeholder `apiBaseURL: nil`.

**Why it happens:** Phase 1 set both `.debug` and `.release` to `apiBaseURL: nil` because there was no live backend yet. Phase 2 must update `.release` OR add a fatalError that forces the developer to confront the nil before ship.

**How to avoid:**
1. The `Self.defaultNetworkConfig(env:)` method in Pattern 3 includes a `fatalError` when Release + nil baseURL. This is intentional — you CANNOT ship a Release build without this being addressed.
2. A CI-only check: `grep 'apiBaseURL: nil' validationLedger/App/Environment.swift` must be 1 match or zero; CI fails if the placeholder is present in Release builds.
3. Phase 2 planner adds a `PHASE-2-TODO` marker if the actual Release URL isn't available yet (backend separate project), but also adds the fatalError so shipping without resolving it is impossible.

[VERIFIED: Phase 1 REVIEW.md WR-06 carryover; Phase 1 Environment.swift lines 22-27]

**Warning signs:**
- `grep "apiBaseURL: nil" validationLedger/App/Environment.swift` returns a match after Phase 2 release prep
- CI pipeline has no gate for Environment.release.apiBaseURL

## Code Examples

Consolidated reference patterns from Apple docs + verified research. Planner can copy into task definitions.

### Example 1: NetworkError enum (closes Phase 1 CR-01)

```swift
// Core/Networking/NetworkError.swift
import Foundation

public enum NetworkError: Error, Sendable {
    case unexpectedResponseType(URLResponse)
    case decodingFailed(Error)
    case httpError(statusCode: Int, body: Data)
    case retriesExhausted
    case pinningFailed
    case baseURLMissing
}
```

### Example 2: Phase 1 NetworkClient fix (CR-01)

```swift
// Core/Networking/NetworkClient.swift — FIX CR-01 force-cast
func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw NetworkError.unexpectedResponseType(response)
    }
    return (data, http)
}

func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = body
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw NetworkError.unexpectedResponseType(response)
    }
    return (data, http)
}
```

### Example 3: APIClient facade (ties endpoints + interceptors + network)

```swift
// Core/Networking/APIClient.swift
import Foundation

public final class APIClient: Sendable {
    private let baseURL: URL
    private let networkClient: any NetworkClient
    private let requestInterceptors: [any RequestInterceptor]
    private let responseInterceptors: [any ResponseInterceptor]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        networkClient: any NetworkClient,
        interceptors: [any Sendable] = [],
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init()
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestInterceptors = interceptors.compactMap { $0 as? any RequestInterceptor }
        self.responseInterceptors = interceptors.compactMap { $0 as? any ResponseInterceptor }
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = encoder
        self.decoder = decoder
    }

    public func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        var req = try buildRequest(endpoint)
        for interceptor in requestInterceptors {
            req = try await interceptor.intercept(req)
        }

        // Compose response interceptors around the send call.
        let send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { [networkClient] req in
            try await networkClient.send(req)
        }
        let wrapped = responseInterceptors.reversed().reduce(send) { next, interceptor in
            { req in try await interceptor.intercept(send: next, request: req) }
        }
        let (data, response) = try await wrapped(req)

        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.httpError(statusCode: response.statusCode, body: data)
        }
        do {
            return try decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    private func buildRequest<E: APIEndpoint>(_ endpoint: E) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        if let body = endpoint.body {
            req.httpBody = try encoder.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }
}

// Extend NetworkClient protocol with a generic send method:
public extension NetworkClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Default impl routes via get/post for backward compat with Phase 1 shape.
        // Implementing types (URLSessionNetworkClient) should override this directly
        // to use URLSession.data(for: request) unchanged.
        switch request.httpMethod {
        case "GET":  return try await get(request.url!)
        case "POST": return try await post(request.url!, body: request.httpBody ?? Data())
        default:     fatalError("Unsupported method: \(request.httpMethod ?? "nil")")
        }
    }
}
```

### Example 4: docs/cert-rotation.md — FULL runbook (Phase 2 fills in)

```markdown
# Cert Rotation Runbook

**Status:** ACTIVE — Phase 2 SEC-01/FOUND-05 runbook. Review at every cert rotation.

## SPKI Hash Extraction

### From a live server
\`\`\`bash
openssl s_client -connect api.validationledger.com:443 \
                 -servername api.validationledger.com </dev/null 2>/dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
\`\`\`

### From a PEM cert file (pre-deployment)
\`\`\`bash
openssl x509 -in leaf-cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
\`\`\`

## 30-Day Rotation Window Procedure

### Day -30 (preparation)
1. Backend team generates the NEXT-generation cert with a NEW key pair.
2. Backend team extracts the SPKI hash (procedure above).
3. iOS: update `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift`:
   - Move current `primary` to `backup`.
   - Set new cert's SPKI as `primary`.
4. Ship iOS release with the new pair. Wait for TestFlight adoption ≥ 95% active installs (tracked via... TBD pending M2 analytics decision).

### Day 0 (cert swap)
1. Backend team swaps the live server cert from OLD to NEW.
2. Monitor for pin-mismatch crash reports (none expected if prep step was correct).
3. Verify via `openssl s_client` that the live server now serves the NEW cert.

### Day +7 (cleanup)
1. Backend team generates NEXT-next-generation cert (the new "backup").
2. iOS: update `PinnedSPKIs.swift` again:
   - `primary` stays (current live).
   - Update `backup` to the next-next cert.
3. Ship iOS release.

## Emergency Revoke Path

If the current primary cert is compromised:
1. Backend team immediately swaps to the current backup SPKI on the server.
2. iOS: app continues working (backup was dual-pinned).
3. iOS: ship an emergency release rotating `primary` to the previously-backup and a new `backup`.
4. Target: emergency release shipped to TestFlight within 4 hours; App Store expedited review within 24 hours.

## Rollback Procedure

If a rotation release ships a bad pin:
1. Emergency release with both pins restored to the PRIOR cert's SPKIs.
2. App Store expedited review (cite "security regression blocking users").
3. Backend team DOES NOT rotate the server cert until iOS adoption of the restored pins is ≥ 95%.

## CI Check (ship with Phase 2)

Unit test in `validationLedgerTests/Networking/CertificatePinningTests.swift`:
\`\`\`swift
@Test("PinnedSPKIs.primary and .backup must be different")
func dualPinsDiffer() {
    #expect(PinnedSPKIs.staging.primary != PinnedSPKIs.staging.backup)
    #expect(PinnedSPKIs.release.primary != PinnedSPKIs.release.backup)
}

@Test("No PHASE2-TODO placeholder strings in release pins")
func noPlaceholders() {
    #expect(!PinnedSPKIs.release.primary.contains("PHASE2-TODO"))
    #expect(!PinnedSPKIs.release.backup.contains("PHASE2-TODO"))
}
\`\`\`
(The second test is gated to CI configurations that require real pins — it's OK for local dev during Phase 2 to have the TODO placeholders until real backend URLs exist.)

## Related

- `.planning/research/PITFALLS.md` — P3 (cert pinning without rotation = self-brick DoS)
- `.planning/REQUIREMENTS.md` — FOUND-05, SEC-01
- `docs/ci.md` — Device CI security-path filter includes `Core/Networking/CertificatePinning/**`
```

### Example 5: Device CI forced-stub test (SC-4)

```swift
// validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift
// SC-4: Release build refuses to launch on any device where SecureEnclave.isAvailable == false.
// This test uses a compile-flag override to force the "not available" branch on a real device
// and asserts that AppContainer construction fatalErrors.

import Testing
import CryptoKit
@testable import validationLedger

@Suite("DEV-03 — Refuse launch without Secure Enclave")
struct RefuseLaunchWithoutSecureEnclaveTests {
    /// On a real device WITH Secure Enclave, this test does NOT exercise the fatal-error path
    /// (the guard succeeds). It does verify the baseline invariant that the device has SE.
    /// The fatal-error path is exercised via a compile-time test-only override — see below.
    @Test("Device smoke: SecureEnclave.isAvailable is true on production hardware")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true)
    }

    @Test("AppContainer forced-stub: fatalError fires when SE is stubbed unavailable")
    func appContainerFatalsOnStubbedUnavailable() {
        // This test requires a test-only compilation flag (-DFORCE_SE_UNAVAILABLE_TEST)
        // and a #if FORCE_SE_UNAVAILABLE_TEST override in AppContainer that replaces
        // `SecureEnclave.isAvailable` with a forced false.
        //
        // Without the flag, this test is a no-op (skipped).
        // With the flag (device CI pipeline only), AppContainer.init must fatalError.
        #if FORCE_SE_UNAVAILABLE_TEST
        // The test harness installs a signal handler, captures SIGABRT from fatalError,
        // asserts it fires, and returns success.
        // Implementation: either use XCTExpectFailure with a custom trap, or spawn a
        // subprocess that invokes AppContainer and asserts non-zero exit + specific message.
        // Recommend spawn-subprocess pattern — XCTest's trap mechanism is fragile.
        #else
        // Not in forced-stub mode; record as skipped.
        Issue.record("Test requires -DFORCE_SE_UNAVAILABLE_TEST compile flag; run in device CI pipeline")
        #endif
    }
}
```

**Note on this test:** Swift Testing does not have a stable `@trap-fatal` primitive yet (as of April 2026). The recommended pattern for "assert process exits with a specific fatalError" is to spawn a subprocess and assert its exit code — which requires some plumbing. A simpler alternative is to refactor `AppContainer.init` to accept a `secureEnclaveAvailable: Bool` parameter (injectable), move the fatalError behind a `precondition` + wrapper, and unit-test the wrapper in isolation. **Recommend the parameter-injection refactor for testability — the fatalError is preserved at the call site in `AppDelegate`/composition.** [ASSUMED — planner picks approach]

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|--------------|------------------------|--------------|--------|
| `SecTrustCopyPublicKey` | `SecTrustCopyKey` / `SecCertificateCopyKey` | iOS 14 (2020) | Old APIs still compile with deprecation warnings. Use new. |
| `SecCertificateCopyPublicKey` | `SecCertificateCopyKey` | iOS 12 (2018) | Deprecated; compile warning. |
| `SecKeyRawSign` / `SecKeyRawVerify` | `SecKeyCreateSignature` / `SecKeyVerifySignature` | iOS 10 (2016) | Raw APIs long deprecated. Never use in new code. |
| XCTest for unit tests | Swift Testing | Xcode 16 (2024) | Phase 1 locked Swift Testing for new unit tests; XCTest retained for UI tests only. |
| TrustKit / hand-rolled URLSessionDelegate pinning | NSPinnedDomains (Info.plist) **AND** hand-rolled URLSessionDelegate | iOS 14 (2020) for NSPinnedDomains | Phase 2 uses hand-rolled URLSessionDelegate — NSPinnedDomains is easier-to-bypass-via-repackaging. Rejected for this app's security posture. |
| `SecureEnclave.P256.Signing.PrivateKey` (CryptoKit) | `SecKeyCreateRandomKey` with explicit ACL flags | — | CryptoKit convenience wrapper lacks `.biometryCurrentSet` exposure. Phase 2 uses Security framework directly for DEV-02 compliance. |
| Alamofire request chain | URLSession + async/await + interceptor chain | Swift 5.5+ / iOS 15 (2021) | Modern URLSession async methods make Alamofire redundant. Phase 2 banned Alamofire by stack constraint; not needed anyway. |

**Deprecated / outdated:**
- **SecKeyCreateWithData** for creating from raw key data: still works, but Phase 2 does not need it — keys are always generated fresh via `SecKeyCreateRandomKey`.
- **Manual JSON parsing / Dictionary responses:** Typed `Decodable` models via NET-01 are the standard — never return `[String: Any]` from APIClient methods.
- **UUID.uuidString.lowercased() for idempotency keys:** Case is not specified by the IETF draft; uppercase is fine. Don't over-normalize.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The backend serves EC P-256 certs (not RSA). Validated via "modern default" assumption. | §Pattern 4 SPKIHasher | LOW — if RSA, the ASN.1 header is 24 bytes different values; unit test against a known PEM cert catches mismatch. |
| A2 | Wave grouping (4 waves) is optimal for Phase 2. | §Summary | LOW — planner confirms. Alternative is 2 waves (tests-first then everything else). |
| A3 | `Environment.release.apiBaseURL` can remain `nil` with a `PHASE-2-TODO` marker + fatalError guard until the real backend URL exists (backend is a separate GSD project). | §User Constraints Deferred Ideas + §Pitfall 9 | MEDIUM — if the backend URL becomes available mid-Phase-2, plan should be revised to set it immediately. |
| A4 | Retry base delay 500ms × 2^n, ceiling 4000ms, ±20% jitter is the right tuning. | §Pattern 6 | LOW — parameters are tunable; the *shape* (exponential + jitter + method-gate) is what matters. Stripe uses similar values. |
| A5 | `[.privateKeyUsage, .devicePasscode]` is the right ACL for deviceKey (not `.biometryAny` or `.biometryCurrentSet`). | §Pattern 7 | LOW — DEV-02 explicitly says "passcode-only ACL for device identity." |
| A6 | DEV-01 keypair generation trigger is "first successful OTP verify" — so lives in Phase 3's AuthRepository calling into SecureEnclaveKeyStore. Phase 2 ships the generation API; Phase 3 wires the call site. | §Architectural Responsibility Map | LOW — kickoff brief is explicit. Planner confirms task boundary. |
| A7 | NSPinnedDomains is rejected in favor of hand-rolled URLSessionDelegate pinning. | §Alternatives Considered, §Pattern 4 | LOW — Guardsquare analysis + Apple docs underspecification make the hand-rolled path more defensible for a security-critical product. If user prefers NSPinnedDomains for simplicity, revise. |
| A8 | `@Suite(.serialized)` + NSLock + explicit `MockURLProtocol.reset()` at test-case top is the belt-and-suspenders approach; pick all three rather than one. | §Pattern 2, §Pitfall 7 | LOW — all three are cheap. If just one is chosen, prefer `.serialized` for clearest failure mode. |
| A9 | `SecureEnclaveKeyStoreTests` lives in `validationLedgerDeviceTests/` (NOT `validationLedgerTests/`). | §Pitfall 2 | LOW — Phase 1 `SecureEnclaveSmokeTests.swift` already sets the precedent. |
| A10 | DEV-03 forced-stub test uses parameter-injection on AppContainer instead of subprocess-spawn for fatalError capture. | §Example 5 | MEDIUM — both approaches work; parameter injection requires a modest AppContainer refactor. Planner decides. |

## Open Questions

1. **What is the actual backend API contract for `/device/register`?**
   - What we know: DEV-01 says public key; DEV-05 says `{model, iOSVersion, installUUID}`.
   - What's unclear: Exact JSON shape, error codes, whether `authorizationKey`'s public key is also sent (the kickoff brief only mentions sending deviceKey to `/device/register`).
   - Recommendation: Planner ships a reasonable shape as a typed struct; backend GSD project confirms and iOS iterates. Use MockURLProtocol fixtures as the contract source-of-truth until backend is live.

2. **Does the backend use RSA or EC P-256 certs for TLS?**
   - What we know: EC P-256 is the modern default.
   - What's unclear: Nothing confirmed about the actual backend cert.
   - Recommendation: Ship with EC P-256 ASN.1 header; add a SPKIHasher unit test that round-trips a test PEM cert of the expected algorithm. If RSA is adopted later, add conditional header selection in SPKIHasher.

3. **When does Phase 2 get real staging/production cert SPKIs?**
   - What we know: Backend is a separate GSD project; URLs + certs don't exist yet.
   - What's unclear: Timeline.
   - Recommendation: Ship `PinnedSPKIs.swift` with `PHASE2-TODO-*` placeholders. Add a CI gate that fails Release builds if placeholders are still present. Real values land via PR when backend is ready.

4. **Should the device CI forced-stub test for DEV-03 use subprocess-spawn or parameter injection?**
   - What we know: Both patterns work; Swift Testing lacks a stable `@trap-fatal` primitive.
   - Recommendation: Parameter injection (refactor AppContainer to accept `isSecureEnclaveAvailable: Bool = SecureEnclave.isAvailable`). Cleaner, testable in simulator too.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build | ✓ | 26.4 (Phase 1 VERIFIED) | — |
| Swift | Language | ✓ | 6.3 toolchain, 5.9 pin | — |
| iOS Simulator | PR CI tests | ✓ | iPhone 15 / iOS 17.5 (Phase 1 VERIFIED) | — |
| Physical iOS device + self-hosted runner | SecureEnclave + cert-pinning device CI | ⚠ | Paired iPhone 15 Pro Max registered in Phase 1 config, but Phase 1 HUMAN-UAT #5-7 confirms the runner + DEVICE_UDID secret not yet active. | Execution deferred to HUMAN-UAT; Phase 2 ships the test code; actual run awaits runner activation |
| openssl CLI | SPKI extraction in runbook | ✓ (standard on macOS) | LibreSSL 3.x on macOS | — |
| Live backend API | Live endpoint tests | ✗ | — | `MockURLProtocol` fixtures serve as contract-source-of-truth. Mock-mode is fully functional; live-mode wiring exists but cannot be exercised. This is consistent with the M1 strategy (contract-first). |

**Missing dependencies with no fallback:**
- None. The missing device-CI-runner activation is a HUMAN-UAT carryover from Phase 1; Phase 2 tests can be written without it.

**Missing dependencies with fallback:**
- **Live backend API:** fallback = MockURLProtocol. Expected — this is the whole point of contract-first.
- **Self-hosted device runner activation:** fallback = Phase 2 ships the test code; device CI runs when runner is brought online (HUMAN-UAT).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (unit) + XCTest/XCUITest (UI) — Phase 1 baseline |
| Config file | `validationLedger.xcodeproj/xcshareddata/xcschemes/validationLedger.xcscheme` (simulator-only scheme); `validationLedgerDeviceTests` target for device CI |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests/Networking` (≈20–45s) |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'` (all simulator tests) + device CI for `validationLedgerDeviceTests` |
| Phase gate | Full simulator suite green; device CI green on merge-to-main (FOUND-04) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| NET-01 | APIClient + typed endpoints — all 7 M1 endpoints decode typed models from success fixture | unit (Swift Testing) | `xcodebuild test -only-testing:validationLedgerTests/Networking/APIClientEndpointTests` | ❌ Wave 1 |
| NET-02 | MockURLProtocol fixtures — each endpoint has success + failure fixture, tests decode each | unit | Same as NET-01 (parameterized) | ❌ Wave 1 |
| NET-03 | `AppContainer.networking` swap is one-line | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/AppContainerNetworkConfigTests` | ❌ Wave 1 |
| NET-04 | IdempotencyInterceptor injects header on POST/PUT, not on GET | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/IdempotencyInterceptorTests` | ❌ Wave 2 |
| NET-05 | RetryInterceptor retries GET on 5xx up to 3×; does not retry POST | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/RetryInterceptorTests` | ❌ Wave 2 |
| SEC-01 | PinningSessionDelegate accepts primary OR backup SPKI; rejects any other cert | unit (with synthetic cert) + device CI integration | `xcodebuild test -only-testing:validationLedgerTests/Networking/CertificatePinningTests` | ❌ Wave 2 |
| DEV-01 | SecureEnclaveKeyStore generates EC P-256 keypair; public key round-trips | device | `xcodebuild test -scheme validationLedgerDeviceTests -only-testing:validationLedgerDeviceTests/SecureEnclaveKeyStoreTests` | ❌ Wave 3 (device) |
| DEV-02 | Two-key pattern; deviceKey + authorizationKey have correct ACLs; signing works | device | Same as DEV-01 (suite) | ❌ Wave 3 (device) |
| DEV-03 | Production refuses launch if SE unavailable (forced-stub) | device (forced-stub) | `xcodebuild test -scheme validationLedgerDeviceTests -only-testing:validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests` | ❌ Wave 4 (device) |
| DEV-05 | DeviceFingerprint assembles model + iOS version + installUUID; installUUID persists across launches | unit (simulator) | `xcodebuild test -only-testing:validationLedgerTests/Identity/DeviceFingerprintTests` | ❌ Wave 3 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme validationLedger -only-testing:<specific target>` (the task's tests only) — should complete in < 60s.
- **Per wave merge:** Full simulator suite (`xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`) — target < 5 min.
- **Per phase gate:** Full simulator suite green + `validationLedgerDeviceTests` green on device CI (merge-to-main trigger).

### Wave 0 Gaps

- [ ] `validationLedgerTests/Networking/APIClientEndpointTests.swift` — NET-01 + NET-02 decode tests
- [ ] `validationLedgerTests/Networking/IdempotencyInterceptorTests.swift` — NET-04
- [ ] `validationLedgerTests/Networking/RetryInterceptorTests.swift` — NET-05
- [ ] `validationLedgerTests/Networking/CertificatePinningTests.swift` — SEC-01 unit portion (dual-pin diff check, SPKIHasher round-trip)
- [ ] `validationLedgerTests/Networking/AppContainerNetworkConfigTests.swift` — NET-03
- [ ] `validationLedgerTests/Identity/DeviceFingerprintTests.swift` — DEV-05
- [ ] `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` — DEV-01 + DEV-02 device round-trip
- [ ] `validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift` — DEV-03 forced-stub
- [ ] `validationLedgerTests/Networking/Fixtures/*.json` — 14 fixture files (7 endpoints × 2 outcomes)
- [ ] `docs/adr/0004-secure-enclave-two-key-pattern.md` — NEW ADR recording DEV-02 ACL decision rationale (+ re-enrollment invalidation documented)

Framework install: N/A (Swift Testing + XCTest are already Phase 1 baseline).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | partial | Phase 2 enables backend-delegated authentication via OTP endpoints + device binding. Actual OTP flow is Phase 3. |
| V3 Session Management | partial | `Idempotency-Key` prevents duplicate session-creation operations. Full session lifecycle is Phase 3 SESS-*. |
| V4 Access Control | no | Not in Phase 2 — backend-enforced. |
| V5 Input Validation | yes | `APIClient` uses typed `Decodable` models — malformed JSON from backend throws `NetworkError.decodingFailed` rather than propagating untyped data. Phone format (E.164) validation is Phase 3 AUTH-01. |
| V6 Cryptography | yes | EC P-256 via Security framework + CryptoKit — NEVER hand-roll. SPKI SHA-256 hashing via CryptoKit. All signing via `SecKeyCreateSignature` with `.ecdsaSignatureMessageX962SHA256` algorithm. |
| V9 Communications (TLS) | yes | Dual-pin SPKI cert pinning on all API traffic. ATS strict in Info.plist (Phase 1 SEC-02). No TLS 1.2 fallback — iOS 17 default is TLS 1.3. |
| V10 Malicious Code | partial | Install UUID + device fingerprint (DEV-05) give backend a weak-signal anomaly detector. App Attest (Phase 4 DEV-04) is the hardened version. |
| V14 Configuration | yes | `PinnedSPKIs.release` vs `.staging` compile-time constants; CI guards Release builds against TODO placeholders. No runtime config for pins. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| MITM via compromised CA | Tampering, Disclosure | Dual-pin SPKI cert pinning — rejects any cert not in the pinned set. |
| Replay of stolen POST request | Repudiation | `Idempotency-Key` uniqueness on POST; backend stores keys server-side for deduplication. |
| Cert expiry self-brick | Denial of Service | Dual-pin + 30-day rotation runbook (`docs/cert-rotation.md`). |
| Stolen device → impersonation | Spoofing | Two-key pattern: `authorizationKey` with `.biometryCurrentSet` invalidates on re-enrollment. New biometric enrollment → key discarded → sensitive ops fail → re-bind flow triggered. |
| Simulator exfiltrates keys | Disclosure | `SoftwareKeyStore` is gated to `#if DEBUG && targetEnvironment(simulator)`; production fatalErrors if SE unavailable. Keys never leave enclave on real device. |
| Duplicate retry on POST causes double-charge equivalent | Tampering | RetryInterceptor method-gated to GET only. POST never retries without explicit idempotency replay (Phase 5 pattern, not Phase 2). |
| Plaintext SPKI hashes in plist → trivial tamper | Tampering | Compile-time Swift constants in `PinnedSPKIs.swift` (not Info.plist). Binary patching required; NSPinnedDomains rejected. |
| MockURLProtocol test race leaks state | Tampering (test) | `NSLock` + `@Suite(.serialized)` + `MockURLProtocol.reset()` per test case. |
| Force-cast crash on non-HTTP response | DoS | Replace `as! HTTPURLResponse` force-cast with `guard let ... else throw NetworkError.unexpectedResponseType` (closes Phase 1 CR-01). |

## Sources

### Primary (HIGH confidence)

- [Apple Developer — Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave) — Canonical SecKeyCreateRandomKey + kSecAttrTokenIDSecureEnclave pattern.
- [Apple Developer — biometryCurrentSet flag](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/ksecaccesscontrolbiometrycurrentset) — Re-enrollment invalidation semantics.
- [Apple Developer — NSPinnedDomains](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nspinneddomains) — Info.plist-based pinning (rejected for this app; see Alternatives Considered).
- [Apple Developer — Identity Pinning: How to configure server certificates for your app](https://developer.apple.com/news/?id=g9ejcf8y) — Apple's official guidance on identity pinning; URLSessionDelegate compatibility not clarified.
- [Apple Developer — Swift Testing `.serialized` trait](https://developer.apple.com/documentation/testing/trait/serialized) — Parallel-test isolation mechanism.
- [Stripe — Idempotent requests](https://docs.stripe.com/api/idempotent_requests) + [Stripe blog — Designing robust and predictable APIs with idempotency](https://stripe.com/blog/idempotency) — UUIDv4 + exponential backoff + jitter pattern.
- [IETF draft-ietf-httpapi-idempotency-key-header](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/) — Standard header semantics.
- Phase 1 `.planning/phases/01-foundational-conventions-scaffolding/01-RESEARCH.md` — inherited stack decisions (Swift Testing baseline, hand-rolled Keychain, SwiftPM-only, no Alamofire).
- Phase 1 `.planning/phases/01-foundational-conventions-scaffolding/01-REVIEW.md` — CR-01 (force-cast) + WR-01 (MockURLProtocol lock) + WR-06 (Environment.release apiBaseURL nil) carryovers.
- Phase 1 `.planning/phases/01-foundational-conventions-scaffolding/01-VERIFICATION.md` — confirmed Phase 1 artifacts that Phase 2 composes with.

### Secondary (MEDIUM confidence — verified against primary)

- [Secure Vale — Deep Dive into Certificate Pinning on iOS](https://securevale.blog/articles/deep-dive-into-certificate-pinning-on-ios/) — SPKI extraction + SecTrustCopyKey migration.
- [Serverless.lk — Certificate Pinning in iOS: The Right Way](https://serverless.lk/certificate-pinning-in-ios-the-right-way/) — openssl SPKI extraction command.
- [Guardsquare — Leveraging Info.plist Based Certificate Pinning on iOS](https://www.guardsquare.com/blog/leveraging-infoplist-based-certificate-pinning-ios-and-making-its-shortcomings) — Rationale for rejecting NSPinnedDomains in security-critical apps.
- [Gridnev — iOS Keychain: using Secure Enclave-stored keys](https://medium.com/@alx.gridnev/ios-keychain-using-secure-enclave-stored-keys-8f7c81227f4) + [Biometry-protected entries in iOS keychain](https://medium.com/@alx.gridnev/biometry-protected-entries-in-ios-keychain-6125e130e0d5) — SecAccessControl flag combinations; cross-verified against Apple docs.
- [Swift Forums — Mock URLProtocol with strict Swift 6 concurrency](https://forums.swift.org/t/mock-urlprotocol-with-strict-swift-6-concurrency/77135) — Parallel-test URLProtocol isolation patterns.

### Tertiary (LOW confidence — flagged for validation if used)

- Various Medium tutorials on SecKeyCreateSignature / ECDSA — **used only as cross-reference** against Apple docs; no claim sourced solely from a Medium article.

## Metadata

**Confidence breakdown:**
- Standard stack (no new deps): HIGH — consistent with Phase 1; all primitives are iOS SDK native.
- Architecture patterns (interceptor chain, two-key SE, dual-pin SPKI): HIGH — well-documented Apple APIs; multiple secondary sources cross-verify.
- Pitfalls (SE re-enrollment, force-cast, lint-regex, sim-vs-device target placement): HIGH — either Phase 1 carryover observations or Apple-documented behavior.
- Cert rotation runbook specifics (exact openssl pipeline, day -30 / 0 / +7 schedule): HIGH — standard industry pattern; SPKI extraction commands verified.
- Device CI forced-stub test approach: MEDIUM — Swift Testing lacks stable fatal-error capture primitive; two viable approaches (subprocess, parameter injection); planner decides.
- Backend contract shape (JSON for `/device/register`): LOW — backend is a separate GSD project and contract is TBD; Phase 2 proposes a reasonable shape as MockURLProtocol-served contract source-of-truth.

**Research date:** 2026-04-21
**Valid until:** 30 days for networking + SE primitives (stable APIs). Re-verify SwiftLintPlugins / Nuke / Xcode versions at Phase 2 execution start.
