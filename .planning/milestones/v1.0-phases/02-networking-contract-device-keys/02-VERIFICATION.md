---
phase: 02-networking-contract-device-keys
verified: 2026-04-21T20:45:00Z
status: human_needed
score: 5/5 roadmap success criteria verified
overrides_applied: 0
human_verification:
  - test: "Dev-menu NetworkConfig toggle — interactive visual verification"
    expected: "Build DEBUG on simulator. Shake device → DevMenu → Network Config → tap 'Use Mock' → Xcode console shows app_container_deinit + app_container_init. Tap 'Use Live' → alert appears (apiBaseURL is nil, WR-06 message). Confirms NET-03 SC-2 one-line runtime flip."
    why_human: "Interactive simulator gesture + console log observation. Plan 07 Task 8 HUMAN-UAT checkpoint. Cannot verify headlessly."
  - test: "Physical device — Secure Enclave P-256 round-trip (SecureEnclaveKeyStoreTests)"
    expected: "Run validationLedgerDeviceTests on paired iPhone 15 Pro Max (UDID 48F5B3CC-0E06-50CE-BFD4-8A0A136E144D). All 6 @Test cases pass: generateDeviceKeys, persistentKeyRetrieval, signAndVerifyDeviceKey, authKeyGenerates, biometricFlagPresent, differentKeysForSlots. Confirms DEV-01/DEV-02 SC-3."
    why_human: "Requires self-hosted runner activation (Phase 1 HUMAN-UAT #7 carryover). SecureEnclave is unavailable in simulator. Device CI pipeline pending."
  - test: "Physical device — Refuse launch without SE (RefuseLaunchWithoutSecureEnclaveTests)"
    expected: "Run validationLedgerDeviceTests on physical device. 5 @Test cases pass: preflightAllowsRealSEOnDevice, preflightAllowsSimulatorDebug, preflightAllowsDeviceDebug, preflightRejectsMissingSEOnRelease, preflightRejectsMissingSEOnDevice. Confirms DEV-03 SC-4."
    why_human: "Same self-hosted runner dependency as above. Plan 07 Task 8 HUMAN-UAT checkpoint."
---

# Phase 2: Networking Contract & Device Keys — Verification Report

**Phase Goal:** Stand up the contract-first networking stack — typed models for every M1 endpoint, MockURLProtocol returning canned JSON, dual-pin certificate pinning, idempotency-key interceptor — and the Secure Enclave keystore so Phase 3's OTP verify can register a device-bound EC P-256 keypair. After this phase, the networking and key primitives exist; what's missing is an end-user flow to exercise them.
**Verified:** 2026-04-21T20:45:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Unit test calls every M1 endpoint via APIClient with MockURLProtocol; success + failure fixtures decode into typed Swift models | VERIFIED | `APIClientEndpointTests.swift` — 14 @Test cases, 7 endpoints × success/failure, all pass |
| 2 | Switching AppContainer.networking between .mock and .live is a single line; dev-menu toggle flips at runtime | VERIFIED (programmatic) | `AppContainer.makeSession(networkConfig:)` single factory; `NetworkConfigToggleViewController` exists; interactive portion pending HUMAN-UAT |
| 3 | Physical device: EC P-256 keypair in SE with .biometryCurrentSet ACL, sign+verify round-trips; simulator uses SoftwareKeyStore | VERIFIED (compile) | `SecureEnclaveKeyStore.swift` two-key pattern confirmed; `SoftwareKeyStore.swift` simulator fallback confirmed; `SecureEnclaveKeyStoreTests.swift` compiled for device — execution pending HUMAN-UAT |
| 4 | Release build refuses launch where SecureEnclave.isAvailable == false | VERIFIED (code) | `AppContainer.preflightSecureEnclave(...)` + `RefuseLaunchWithoutSecureEnclaveTests` (5 tests, device target) — compiled, logic proven; device-CI execution pending HUMAN-UAT |
| 5 | Cert-pinning dual-pin rejects connection to staging host with a third un-pinned cert; docs/cert-rotation.md documents 30-day rotation window | VERIFIED | `CertificatePinningIntegrationTests.rejectsRogue` passes with three-cert test set; `docs/cert-rotation.md` status ACTIVE with Day -30/0/+7 runbook |

**Score:** 5/5 truths verified (3 require human execution for device/interactive portions)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `validationLedger/Core/Networking/APIClient.swift` | Typed facade over NetworkClient | VERIFIED | 97 lines; `request<E: APIEndpoint>` pipeline + interceptor composition |
| `validationLedger/Core/Networking/APIEndpoint.swift` | Protocol + HTTPMethod + EmptyBody | VERIFIED | Public protocol with primary associated type |
| `validationLedger/Core/Networking/Endpoints/*.swift` | 7 M1 endpoint structs | VERIFIED | All 7 files present: OTPRequest, OTPVerify, DeviceRegister, KYCUploadInit, KYCUploadChunk, KYCUploadCommit, KYCStatus |
| `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` | NSLock-guarded registry | VERIFIED | Moved from flat location to Mock/ subdirectory; lock-guarded register/reset API |
| `validationLedger/Core/Networking/Mock/MockFixture.swift` | `registerFixture<E>` extension | VERIFIED | One-line fixture-registration API for all test suites |
| `validationLedger/Core/Networking/NetworkError.swift` | 7-case typed error enum | VERIFIED | NetworkError: unexpectedResponseType, httpError, decodingFailed, encodingFailed, retriesExhausted, pinningFailed, baseURLMissing |
| `validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift` | Protocol definitions | VERIFIED | RequestInterceptor + ResponseInterceptor both Sendable |
| `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` | POST/PUT Idempotency-Key injection | VERIFIED | Overwrite-guard present; method gate present |
| `validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift` | GET-only exponential backoff | VERIFIED | maxRetries=3, GET-only gate, jittered backoff |
| `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift` | Dual-pin compile-time constants | VERIFIED | staging + release structs; PHASE2-TODO placeholders gated by noReleasePlaceholders test |
| `validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift` | EC P-256 SPKI hasher | VERIFIED | RFC 7469 compliant; openssl ground-truth test passes |
| `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` | URLSessionDelegate dual-pin | VERIFIED | 4 rejection paths + 1 accept path; completionHandler invariant enforced |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | Full SE two-key implementation | VERIFIED | deviceKey (.devicePasscode) + authorizationKey (.biometryCurrentSet) via SecKeyCreateRandomKey |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | Simulator two-key fallback | VERIFIED | Two P256.Signing.PrivateKey slots; `generateDeviceIdentityKeys()` returns both public keys |
| `validationLedger/Core/Identity/DeviceFingerprint.swift` | DeviceFingerprint with Keychain UUID | VERIFIED | model + iosVersion + Keychain-persisted installUUID |
| `validationLedger/App/AppContainer.swift` | Composition root with all Phase 2 wiring | VERIFIED | makeSession factory, APIClient with interceptors, preflightSecureEnclave seam |
| `validationLedger/App/DevMenu/NetworkConfigToggleViewController.swift` | DEBUG-only toggle UI | VERIFIED | File exists; #if DEBUG gated; D-13 Release strings scan = 0 hits |
| `validationLedgerTests/Networking/APIClientEndpointTests.swift` | 14 @Test endpoint decode tests | VERIFIED | 14 @Test cases; all pass with -parallel-testing-enabled NO |
| `validationLedgerTests/Networking/CertificatePinningIntegrationTests.swift` | Three-cert dual-pin integration tests | VERIFIED | 4 @Tests; rejectsRogue confirmed |
| `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` | 6 device-target SE tests | COMPILED (execution pending) | `build-for-testing -destination 'generic/platform=iOS'` succeeded; device run pending HUMAN-UAT |
| `validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift` | 5 device-target preflight tests | COMPILED (execution pending) | Same device CI dependency |
| `docs/cert-rotation.md` | Active 30-day rotation runbook | VERIFIED | Status ACTIVE; Day -30/0/+7 procedure; emergency path; openssl pipelines |
| `docs/adr/0004-secure-enclave-two-key-pattern.md` | ADR for two-key decision | VERIFIED | Commit 4a358ad |
| `validationLedgerTests/Networking/Fixtures/` | 14 JSON fixtures | VERIFIED | 14 files (7 endpoints × success + failure) |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AppContainer` | `APIClient` | `makeSession(networkConfig:)` + `APIClient(baseURL:networkClient:requestInterceptors:responseInterceptors:)` | WIRED | Single URLSession factory; IdempotencyInterceptor + RetryInterceptor composed |
| `AppContainer` | `PinningSessionDelegate` | `makeSession(.live)` branch | WIRED | Installed ONLY on `.live` branch; `.mock` branch has no delegate |
| `AppContainer` | `SoftwareKeyStore` / `SecureEnclaveKeyStore` | `#if DEBUG && targetEnvironment(simulator)` | WIRED | Conditional compilation gate correct |
| `URLSessionNetworkClient.send(_:)` | `session.data(for: request)` | Protocol method (Plan 07 fix) | WIRED | `send(_:)` declared in `NetworkClient` protocol; `URLSessionNetworkClient` overrides with full URLRequest pass-through; dynamic dispatch confirmed by `AppContainerNetworkConfigTests.idempotencyInterceptorWired` |
| `IdempotencyInterceptor` | `Idempotency-Key` header | `setValue(UUID().uuidString, forHTTPHeaderField:)` | WIRED | Overwrite-guard present; header reaches wire via URLSessionNetworkClient override |
| `RetryInterceptor` | GET-only retry | `request.httpMethod == "GET"` gate | WIRED | Non-GET requests pass through single-attempt |
| `APIClient.request<E>` | `requestInterceptors` | `for interceptor in requestInterceptors { req = try await interceptor.intercept(req) }` | WIRED | Chain executes before send |
| `APIClient.request<E>` | `responseInterceptors` | `reversed().reduce(base)` | WIRED | Interceptors compose innermost-last |
| `MockURLProtocol` | `.mock` URLSession | `config.protocolClasses = [MockURLProtocol.self]` | WIRED | Ephemeral config, no pinning delegate |
| `SceneDelegate` | `NetworkConfigToggleViewController` | `.devMenuNetworkConfigRequested` NotificationCenter | WIRED | Observer on `queue: .main`; stores `currentNetworkConfigOverride`; calls `presentRoot` |

---

## Data-Flow Trace (Level 4)

Phase 2 produces infrastructure primitives (no user-visible rendering). All dynamic data flows are through `MockURLProtocol` in tests — no production UI renders live data in this phase. Data-flow trace is not applicable for this infrastructure phase.

---

## Behavioral Spot-Checks

Step 7b: Infrastructure-only phase (no runnable CLI / server). Test suite was confirmed passing (90 tests / 17 suites) per Plan 07 Summary. Spot-check of specific behaviors:

| Behavior | Observation | Status |
|----------|-------------|--------|
| IdempotencyInterceptor injects header on POST | 5/5 tests pass (`IdempotencyInterceptorTests`) | PASS |
| RetryInterceptor retries GET on 5xx (max 3) | 9/9 tests pass (`RetryInterceptorTests`) | PASS |
| MockURLProtocol returns fixture for all 7 endpoints | 14/14 tests pass (`APIClientEndpointTests`) | PASS |
| CertificatePinningIntegrationTests rejects third cert | 4/4 tests pass; `rejectsRogue` is the primary SC-5 assertion | PASS |
| AppContainer .mock/.live swap (programmatic) | 4/4 `AppContainerNetworkConfigTests` pass | PASS |
| SoftwareKeyStore two-key sign+verify | 4/4 `SoftwareKeyStoreExtendedTests` pass | PASS |
| DeviceFingerprint installUUID persistence | 4/4 `DeviceFingerprintTests` pass | PASS |
| SecureEnclaveKeyStore device tests | Compiled; device execution pending | HUMAN-UAT |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| NET-01 | Plan 02-02 | Typed Swift models for all M1 endpoints | SATISFIED | 7 endpoint structs with nested RequestBody + Response |
| NET-02 | Plan 02-03 | MockURLProtocol with canned JSON for every M1 endpoint | SATISFIED | 14 JSON fixtures + registerFixture API + 14 decode tests |
| NET-03 | Plan 02-07 | One-line mock/live swap | SATISFIED | AppContainer.makeSession factory; `mockOverrideConstructs` test |
| NET-04 | Plan 02-04 | Idempotency-Key interceptor on POST | SATISFIED | IdempotencyInterceptor + end-to-end wired test |
| NET-05 | Plan 02-04 | Exponential backoff on GET only | SATISFIED | RetryInterceptor with GET gate |
| SEC-01 | Plan 02-05 + 02-07 | Dual-pin SPKI cert pinning | SATISFIED | PinningSessionDelegate + CertificatePinningIntegrationTests.rejectsRogue |
| DEV-01 | Plan 02-06 | SecureEnclaveKeyStore generates EC P-256 keypair | SATISFIED | SecureEnclaveKeyStore.generateDeviceIdentityKeys() — device execution pending |
| DEV-02 | Plan 02-06 | Two-key pattern (deviceKey + authorizationKey) | SATISFIED | Keyslot enum with .devicePasscode / .biometryCurrentSet ACL |
| DEV-03 | Plan 02-06 + 02-07 | SoftwareKeyStore simulator fallback; Release refuses without SE | SATISFIED | #if DEBUG && simulator gate + preflightSecureEnclave + RefuseLaunchWithoutSecureEnclaveTests |
| DEV-05 | Plan 02-06 | Device fingerprint with Keychain installUUID | SATISFIED | DeviceFingerprint.swift + DeviceFingerprintTests |

---

## Anti-Patterns Found

| File | Issue | Severity | Assessment |
|------|-------|----------|------------|
| `APIClient.swift:116-118` | Default `NetworkClient.send(_:)` extension `default:` arm force-unwraps `HTTPURLResponse(...)!` | Warning | CR-01 partially addressed: production path uses `URLSessionNetworkClient.send(_:)` override via dynamic dispatch. The default extension is reachable only by custom conformers. Misleading but not a blocker — document as Phase 3 cleanup item. |
| `SecureEnclaveKeyStore.swift:71-101` | `generateKey(slot:)` does not guard against duplicate Keychain entries | Warning | CR-02: Calling `generateDeviceIdentityKeys()` twice silently generates duplicate keys. Stale private key may be used for signing while new public key was returned. Phase 2 never calls this in a real flow; Phase 3 should fix before its first `onAuthSuccess` trigger. See remediation below. |
| `OTPVerifyEndpoint.swift:12` | `RequestBody.otpSessionID` lacks CodingKeys — encodes as `otp_session_i_d` not `otp_session_id` | Warning | IN-01: Mock tests accept any request body; this only breaks production wire protocol. Must be fixed before Phase 3's first real OTP verify call. See remediation below. |
| `KYCUploadChunkEndpoint.swift:12` | `RequestBody.uploadID` lacks CodingKeys — encodes as `upload_i_d` not `upload_id` | Warning | IN-05: Same root cause as IN-01. High-frequency endpoint (called per chunk). Must be fixed before Phase 5. |
| `KYCUploadCommitEndpoint.swift:11` | `RequestBody.uploadID` lacks CodingKeys — encodes as `upload_i_d` | Warning | Same root cause as IN-05. |
| `DeviceRegisterEndpoint.swift:15` | `DeviceFingerprintPayload.installUUID` lacks CodingKeys — encodes as `install_u_u_i_d` | Warning | Same root cause as IN-01. Affects `/device/register` payload; must fix before Phase 3. |
| `CertificatePinningTests.swift:noReleasePlaceholders` | Test is DEBUG-skipped; Release-build CI job does not exist in `ci-simulator.yml` | Warning | CR-04: The placeholder guard never runs in CI. SC-5's integration test passes; this gap is about shipping hygiene, not the SC-5 assertion itself. Should be addressed before TestFlight (M5 milestone). |

No 🛑 BLOCKER anti-patterns found that prevent Phase 2 goal achievement.

---

## Human Verification Required

### 1. Dev-menu NetworkConfig toggle — visual + console (SC-2 interactive portion)

**Test:** Build DEBUG scheme on simulator or device. Run the app. Shake device to reveal DevMenu. Tap "Network Config". Tap "Use Mock". Observe Xcode console for `app_container_deinit` + `app_container_init` log lines (ADR-0002 root-swap evidence confirming the old container was released and a new `.mock` one was created). Then tap "Use Live" — a UIAlertController should appear explaining that apiBaseURL is nil (WR-06 user-facing message).

**Expected:** Console shows root-swap sequence. Alert appears on "Use Live" tap. DevMenu row is absent in Release binary (D-13; already verified programmatically: xcrun strings returns 0 hits).

**Why human:** Interactive shake gesture + visual observation of Xcode console + alert presentation. Cannot verify headlessly. Plan 07 Task 8 deferred item.

### 2. Physical-device Secure Enclave round-trip — SecureEnclaveKeyStoreTests (SC-3)

**Test:** Activate the self-hosted macOS runner (Phase 1 HUMAN-UAT #7). Connect paired iPhone 15 Pro Max (UDID 48F5B3CC-0E06-50CE-BFD4-8A0A136E144D). Run `xcodebuild test -scheme validationLedgerDeviceTests -destination 'id=48F5B3CC-0E06-50CE-BFD4-8A0A136E144D'`. Observe 6/6 `SecureEnclaveKeyStoreTests` pass:
- `generateDeviceKeys` — two public keys returned, both 65 bytes (SE DER format)
- `persistentKeyRetrieval` — key survives store dealloc + reload
- `signAndVerifyDeviceKey` — P256.Signing.ECDSASignature(derRepresentation:) round-trip passes
- `authKeyGenerates` — authorization key slot produces distinct 65-byte key
- `biometricFlagPresent` — accessControl flags contain `.biometryCurrentSet`
- `differentKeysForSlots` — device and auth slots return distinct public key data

**Expected:** 6/6 pass. No crash. Face ID/Touch ID prompt appears during `authKey` operations if device has biometrics enrolled.

**Why human:** Secure Enclave is unavailable in simulator; these tests are in `validationLedgerDeviceTests/` target for that reason. Runner activation is a Phase 1 pending item.

### 3. Physical-device RefuseLaunchWithoutSecureEnclaveTests — DEV-03 SC-4 device execution

**Test:** Same runner + device as item 2. Observe 5/5 `RefuseLaunchWithoutSecureEnclaveTests` pass:
- `preflightAllowsRealSEOnDevice` — `isSecureEnclaveAvailable: true, isSimulatorBuild: false, isDebugBuild: false` → returns true
- `preflightRejectsMissingSEOnRelease` — `isSecureEnclaveAvailable: false, isSimulatorBuild: false, isDebugBuild: false` → returns false (SC-4 primary assertion)
- `preflightAllowsSimulatorDebug` — sim+DEBUG → true regardless of SE availability
- `preflightAllowsDeviceDebug` — device+DEBUG+no-SE → true (DEBUG gate permits)
- `preflightRejectsMissingSEOnDevice` — `isSecureEnclaveAvailable: false, isSimulatorBuild: false, isDebugBuild: false` → false

**Expected:** 5/5 pass. Tests assert on the Bool return value; the fatalError in `AppContainer.init` is never triggered because tests call the static `preflightSecureEnclave(...)` directly.

**Why human:** Same runner dependency as item 2. Plan 07 Task 8 deferred item.

---

## REVIEW.md Issue Classification

The four critical issues from 02-REVIEW.md are classified as follows:

### CR-01: APIClient.send default extension interceptor-header drop

**Classification: Follow-up (Phase 3 cleanup), NOT a phase-blocking gap.**

The production code path is correct: Plan 07 moved `send(_:)` into the `NetworkClient` protocol so that `URLSessionNetworkClient.send(_:)` is dynamically dispatched through `any NetworkClient`, preserving all interceptor-injected headers. Confirmed by `AppContainerNetworkConfigTests.idempotencyInterceptorWired`. The default extension in `APIClient.swift` remains reachable only by custom conformers that don't override `send(_:)` — which is currently no conformer in the codebase other than test doubles. The `default:` arm force-unwrap at line 116-118 is a code smell but not a live bug. Recommend Phase 3 cleanup: replace the default extension with a `fatalError` or add `NetworkError.unsupportedMethod` to surface the issue loudly.

### CR-02: SecureEnclaveKeyStore duplicate key generation

**Classification: Pre-Phase-3 required fix, NOT a Phase-2 phase-blocking gap.**

Phase 2's contract is that the Secure Enclave primitives exist. They do. The duplicate-key bug only manifests when `generateDeviceIdentityKeys()` is called a second time on a device that already has keys in the Keychain (e.g., after reinstall or on a second call within Phase 3's `onAuthSuccess`). Phase 2 never calls this method in a real flow — only in device tests that use a `purgeAllKeys` cleanup. The fix must land before Phase 3's first real `/device/register` call.

**Recommended fix-in-place before Phase 3 executes:**
```swift
private func generateKey(slot: Keyslot) throws -> Data {
    // Idempotent: return existing public key if already generated.
    if let existing = try? loadPublicKey(slot: slot) {
        return existing
    }
    // ... rest of generation unchanged
}
```

### CR-03: SceneDelegate NotificationCenter cast silent-fail

**Classification: Minor/non-blocking.** The cast failure path returns silently; a debug assertion should be added but this does not affect any Phase 2 success criterion. Confirmed minor in original REVIEW.md assessment — not a gap.

### CR-04: noReleasePlaceholders gate doesn't run in CI

**Classification: Shipping-hygiene concern, NOT a Phase-2 gap.** SC-5 is satisfied by the integration test (`CertificatePinningIntegrationTests.rejectsRogue`). The `noReleasePlaceholders` test protects against accidentally shipping placeholder SPKI hashes in a Release build. Since the backend does not yet exist and no Release build ships until M5, this gap has months of runway. The fix (add a Release-configuration CI job) belongs in Phase 4's CI hardening scope.

### IN-01/IN-05: RequestBody CodingKeys missing for acronym props

**Classification: Pre-Phase-3 required fix, NOT a Phase-2 phase-blocking gap.**

The missing CodingKeys are on **RequestBody** (encoder side), not Response (decoder side). Phase 2's mock tests use `MockURLProtocol` which matches requests by URL path + method only — the request body content is ignored by the mock. Therefore, SC-1 (mock decode tests) is not affected. However, these will cause all four affected endpoints to send malformed JSON to any real backend:

| Endpoint | Property | Encoded as (wrong) | Should be |
|----------|----------|--------------------|-----------|
| `OTPVerifyEndpoint.RequestBody` | `otpSessionID` | `otp_session_i_d` | `otp_session_id` |
| `KYCUploadChunkEndpoint.RequestBody` | `uploadID` | `upload_i_d` | `upload_id` |
| `KYCUploadCommitEndpoint.RequestBody` | `uploadID` | `upload_i_d` | `upload_id` |
| `DeviceRegisterEndpoint.DeviceFingerprintPayload` | `installUUID` | `install_u_u_i_d` | `install_uuid` |

**Fix pattern** (apply before Phase 3 executes any real endpoint call):
```swift
// In OTPVerifyEndpoint.RequestBody:
private enum CodingKeys: String, CodingKey {
    case otpSessionID = "otp_session_id"
    case code
}
```
Repeat for the three other affected RequestBody/payload types.

---

## Gaps Summary

No gaps prevent Phase 2's goal achievement. The goal is "the networking and key primitives exist; what's missing is an end-user flow to exercise them" — all primitives are confirmed present and wired. Three human verification items remain for device/interactive execution, consistent with the pre-disclosed deferrals.

Four items are classified as **pre-Phase-3 required fixes** that must be resolved before Phase 3 executes real backend calls:

1. **CR-02** — `SecureEnclaveKeyStore.generateKey(slot:)` duplicate-key guard (silent pub/priv mismatch on reinstall)
2. **IN-01** — `OTPVerifyEndpoint.RequestBody.otpSessionID` missing CodingKey (`otp_session_i_d` wire encoding)
3. **IN-05** — `KYCUploadChunkEndpoint.RequestBody.uploadID` missing CodingKey (`upload_i_d` wire encoding)
4. **IN-05 (sister)** — `KYCUploadCommitEndpoint.RequestBody.uploadID` and `DeviceRegisterEndpoint.DeviceFingerprintPayload.installUUID` missing CodingKeys

These are low-effort fixes (each is 4-6 lines). Recommend creating a Phase 3 gate task: "Fix pre-Phase-3 RequestBody CodingKeys + SecureEnclaveKeyStore idempotent generate" before the first `AuthRepository` call.

---

_Verified: 2026-04-21T20:45:00Z_
_Verifier: Claude (gsd-verifier)_
_Phase 1 format precedent: .planning/phases/01-foundational-conventions-scaffolding/01-VERIFICATION.md_
