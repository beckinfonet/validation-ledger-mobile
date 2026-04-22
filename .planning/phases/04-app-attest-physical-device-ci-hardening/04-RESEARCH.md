# Phase 4: App Attest & Physical-Device CI Hardening — Research

**Researched:** 2026-04-22
**Domain:** iOS App Attest (DCAppAttestService) productionization + GitHub Actions physical-device CI hardening
**Confidence:** HIGH on Apple API surface + CI YAML syntax; MEDIUM on undocumented App Attest rate limits; HIGH on integration with existing Phase 1-3 code

## Summary

Phase 4 layers App Attest on top of the three-key `/device/register` payload (deviceKey, authorizationKey, attestedKeyId) and hardens the device CI pipeline into a required branch-protection status check. The work divides cleanly into two parallel tracks: a new `Core/Attestation/` module with a `DCAppAttestAttestationService` production implementation + a `#if DEBUG && targetEnvironment(simulator)` `SimulatorBypassAttestationService` (mirroring the Phase 2 `SecureEnclaveKeyStore`/`SoftwareKeyStore` split), and `.github/workflows/ci-device.yml` upgrades that invoke the full `validationLedgerDeviceTests/` suite with `xcodebuild`'s native `-retry-tests-on-failure -test-iterations 2` for single-retry semantics.

The ecosystem is small: Apple's `DeviceCheck.framework` is already on the iOS 17 SDK, ships the `DCAppAttestService` singleton with three async methods (`generateKey`, `attestKey`, `generateAssertion`), and returns errors through the `DCError.Code` enum (five known cases). No third-party SDKs are needed — `STACK-01`'s pre-approved shortlist already excludes anything attestation-adjacent. The existing `KeyStoreProtocol` + `MockURLProtocol` fixture pattern + `AppContainer` initializer-DI surfaces carry the Phase 4 additions without new architectural primitives.

The three real risks: (1) Apple's undocumented App Attest rate limit — known to exist and surface as `DCError.Code.serverUnavailable` or (in ambiguous reports) `.unknownSystemFailure`, with no published SLA. CONTEXT D-04's backend-driven re-attestation (no client self-rotation) and D-01's once-per-install `generateKey` policy are both correctly calibrated to stay under the quota. (2) Branch protection + required-status-checks has a first-run chicken-and-egg: GitHub only lists a check name in the protection UI after it has run on the protected branch at least once, so Phase 4 must land the workflow with `push: branches: [main]` and let it run once before flipping the required-status-check bit. (3) Unattended biometric testing on physical CI requires a seeded `LAContext` (not real Face ID) — Apple provides no hook for real Face ID in automation, so D-14's seeded-LAContext pattern is the only viable path and the real-hardware Face ID prompt stays HUMAN-UAT forever.

**Primary recommendation:** Build `Core/Attestation/AttestationService.swift` as a protocol mirror of `KeyStoreProtocol`, with `DCAppAttestAttestationService` for device and `SimulatorBypassAttestationService` for `#if DEBUG && targetEnvironment(simulator)`. Extend `DeviceRegisterEndpoint.RequestBody` with optional `attestationObject`/`attestedKeyId`/required `attestationStatus` fields. Add two new endpoints (`DeviceChallengeEndpoint` GET + `DeviceHeartbeatEndpoint` POST) following the existing `APIEndpoint` pattern. Upgrade `ci-device.yml` to run the full `validationLedgerDeviceTests/` suite with `-retry-tests-on-failure -test-iterations 2` and configure a single required-status-check via the Repository Settings UI (rulesets import-from-JSON exists but isn't the Apple-sanctioned path). Every `[ASSUMED]` tag below must be confirmed by the user or the executor before that item becomes a locked decision.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**App Attest Key Lifecycle**

- **D-01:** `DCAppAttestService.generateKey()` is called exactly ONCE per install, on the first successful OTP verify after fresh install. Returned `attestedKeyId` persisted in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. All subsequent `/device/register` calls reuse the persisted `attestedKeyId`.
- **D-02:** `/device/register` payload carries three distinct keys: `deviceKey` SPKI (DEV-01, `.devicePasscode`), `authorizationKey` SPKI (DEV-02, `.biometryCurrentSet`), and `attestedKeyId` + `attestationObject` (new DEV-04). Write new **ADR 0005** documenting the three-key registration payload.
- **D-03:** `attestedKeyId` preserved across logout. Logout's teardown wipes session token, clears `authorizationKey` ACL, tears down role coordinator stack, but does NOT touch `attestedKeyId` Keychain item. Same device + same install = same attestation.
- **D-04:** Re-attestation is backend-driven only. On error codes `attestationInvalid` / `nonceExpired` / `keyCompromised`, client deletes persisted `attestedKeyId`, calls `generateKey()` again, resubmits `/device/register`. DEBUG-only dev-menu entry exposes manual "Re-attest now" button.

**Challenge / Assertion Protocol**

- **D-05:** Challenge delivery uses a dedicated `GET /device/challenge` endpoint. Response: `{ challenge: base64, expiresAt: ISO8601, nonce: string }`. Used once, discarded.
- **D-06:** `clientDataHash = SHA-256(challenge)` — challenge only, no request body or endpoint path binding. Matches Apple's reference sample.
- **D-07:** Attestation cadence = registration + per-session heartbeat. `attestKey()` once on first `/device/register`. `generateAssertion()` on cold-boot re-login (piggybacking `SessionRestoreProbe.restored`) AND on `didBecomeActive` with `lastHeartbeatAt > 24h`. Heartbeat posts to `POST /device/heartbeat` with `{ sessionToken, attestedKeyId, assertion }`. `lastHeartbeatAt` persists in Keychain. No per-request assertions on M1.
- **D-08:** Challenge freshness: single-use, immediate consumption. Client fetches, uses within seconds, submits. No caching. On `challengeExpired` error, refetch + retry ONCE. Backend TTL ≤60s.

**Graceful-Skip Contract**

- **D-09:** `/device/register` payload always carries explicit `attestationStatus` enum with values `"attested" | "unsupported" | "entitlementMissing" | "quotaExceeded" | "simulatorBypass" | "error"`. When != `"attested"`, `attestationObject` + `attestedKeyId` fields are omitted. Each status maps to a distinct client path.
- **D-10:** `#if targetEnvironment(simulator)` simulator-bypass path emits a DEBUG-only fixed fake `attestationObject` + `attestedKeyId = "sim-bypass-{installUUID}"`. Mock backend's `/device/register` fixture recognizes this shape, accepts with `trustTier: "softwareOnly"`. Production builds never ship this code path.
- **D-11:** Non-dismissible "Limited trust mode" banner on role shell whenever `trustTier != "hardwareAttested"`. Copy: "Limited trust mode — this device can't fully verify. Some features may be restricted." Thin banner at top of tab-bar shell (above role tabs). English-only M1, structure ready for v2 localization.
- **D-12:** Backend-driven trust tier. `/device/register` and `/device/heartbeat` return `{ registered: true, trustTier: "hardwareAttested" | "softwareOnly" }`. Client stores `trustTier` in session state (`AppContainer.session`). Server decides policy.

**Device CI — Coverage & Merge Policy**

- **D-13:** Device pipeline runs full security surface: (1) SecureEnclaveKeyStore real-SE EC P-256 keypair generation + sign/verify (DEV-01/02); (2) Keychain `.biometryCurrentSet` ACL item storage + retrieval behind seeded `LAContext` (DEV-03 device path); (3) `Core/Attestation` App Attest `attestKey` + `generateAssertion` round-trip against MockURLProtocol-driven `/device/challenge` + `/device/register` + `/device/heartbeat`; (4) Logout ACL clearing on SE keys.
- **D-14:** Biometric-prompt tests use seeded `LAContext` injected via `AppContainer` — no real Face ID prompt in unattended CI. Seeded `LAContext` returns `.success` synchronously. Tests verify Keychain ACL creation path, SE ACL-clearing path, and all code paths that assume successful biometric.
- **D-15:** Flakiness: retry once, then fail. On single test failure, pipeline reruns only that failed test once. Pass-on-retry logs "flaky-passed" warning to Slack. Fail twice → workflow fails. Quarantine is explicit via `.flaky` annotation + tracking issue.
- **D-16:** Merge gate: device pipeline is required GitHub branch-protection status check on `main`. Red device pipeline blocks merge. Admins need explicit UI override.

### Claude's Discretion

- Exact Swift protocol surface for `AttestationService` — planner decides based on Phase 2 `KeyStoreProtocol`/`SessionLockService` testability patterns.
- Dev-menu "Re-attest now" button placement within `DevMenuViewController` — existing DEBUG-only rows follow a consistent pattern.
- Error-code enum value names on backend side — coordinate with backend team; iOS emits generic `AttestationError` case with raw server code string.
- Exact banner visual styling (height, background color, icon) — follow M1 "minimal UI" principle; system-colored warning tone.
- `/device/heartbeat` HTTP method + idempotency-key usage — researcher confirms against NET-04 idempotency interceptor conventions.

### Deferred Ideas (OUT OF SCOPE)

- Per-request App Attest assertions for M2+ sensitive actions (tender / accept / BOL). Ruled out for M1 — `authorizationKey` ECDSA signatures (DEV-02) already cover per-request integrity.
- Time-based re-attestation (every 90 days). Ruled out in D-04.
- App Attest entitlement / provisioning profile management UX — dev-team process, not app code.
- Real Face ID prompt in CI via `xcrun simctl biometric enroll/match` — ruled out in D-14; physical-iPhone support is undocumented/flaky.
- Multi-user attestation keys — ruled out in D-03; revisit if dispatch-handoff devices become a real use case.
- Attestation telemetry dashboard — surfacing `attestationStatus` distribution across the fleet. Observability / analytics phase, not M1.

## Project Constraints (from CLAUDE.md)

Every Phase 4 implementation MUST honor these directives. Deviations require explicit user override.

- **UIKit-first** for sensitive surfaces: the "Limited trust mode" banner (D-11) is a UIKit view added to the role shell's navigation/tab container — not SwiftUI. Banner integration point is below the UINavigationItem and above the UITabBar on each role's `UITabBarController`.
- **SPM only** — no CocoaPods, no Carthage. All Apple-framework APIs used (`DeviceCheck.framework`, `Security.framework`, `LocalAuthentication.framework`) are part of the iOS SDK; zero new SwiftPM dependencies are needed for Phase 4.
- **iOS 17 minimum deployment** — `DCAppAttestService` first shipped iOS 14; iOS 17's `DeviceCheck` SDK surface is stable. No availability guards required beyond `#available(iOS 14.0, *)` which is always-true at our deployment target.
- **Zero PII in analytics/crash logs** — `attestationObject` raw bytes and `attestedKeyId` raw bytes are sensitive. The existing `LogField` / `AnalyticsField` structured API must receive only the `attestationStatus` enum, challenge-fetched-at timestamp, and `DCError.Code` value. Raw blob bytes must never reach the logger — enforced by type discipline the same way GEO-03 enforces no-coordinates-in-logs.
- **All tokens in Keychain; all keys in Secure Enclave** — `attestedKeyId` is persisted in Keychain (D-01); the App Attest key itself is stored in Secure Enclave by Apple's framework (opaque to us, which is the point).
- **No sensitive data in UserDefaults** — `lastHeartbeatAt` goes in Keychain (per `<specifics>` section of CONTEXT.md), not UserDefaults.
- **AI traffic never calls Anthropic directly** — not applicable to Phase 4.
- **US-only login enforced by backend; client country pre-check** — already closed in Phase 3 (GEO-02); Phase 4 makes no geo changes.
- **TestFlight closed beta for v1; App Store submission is M5** — App Attest entitlement environment is `development` for dev builds; `production` is applied automatically by TestFlight + App Store distribution regardless of the entitlement value (see Pitfall 3 below). Phase 4's entitlement file MUST use `development` to keep internal TestFlight builds working.
- **Pre-approved dependency shortlist** — Phase 4 adds zero new dependencies. `DCAppAttestService` ships with the OS.
- **Timeline**: Phase 4 is one phase of a 24-week plan; the context's 16 locked decisions keep Phase 4 scope tight.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **DEV-04** | `Core/Attestation` calls App Attest on first successful login; attestation payload included in `/device/register`. Gracefully skipped if unavailable with logged warning — backend decides policy. | See §Standard Stack (DCAppAttestService API), §Code Examples (generateKey / attestKey / generateAssertion flows), §Architecture Patterns (Pattern 1: `AttestationService` protocol mirror), §Common Pitfalls (Pitfall 2: rate limits, Pitfall 3: entitlement environment). |
| **CI-03** | Physical-device test plan covers Secure Enclave keypair generation, Keychain biometric-bound item storage, App Attest assertion generation. Runs on every merge to `main`. | See §Standard Stack (xcodebuild `-retry-tests-on-failure`), §Architecture Patterns (Pattern 4: CI YAML upgrade), §Code Examples (device YAML with retries + required status check), §Common Pitfalls (Pitfall 4: required-status-check chicken-and-egg). |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| App Attest key generation | Device (Secure Enclave via `DCAppAttestService`) | — | Apple-owned — the key is opaque to us, generated + stored in SE by the framework. |
| `attestedKeyId` persistence | Device (Keychain) | — | Client-local identifier; binds Keychain item to this install (`afterFirstUnlockThisDeviceOnly`). |
| `lastHeartbeatAt` persistence | Device (Keychain) | — | Sensitive timestamp — not UserDefaults per CLAUDE.md + SEC-03. |
| Challenge generation | API / Backend | — | Server must control nonce + TTL for replay protection; client is a passive consumer. |
| Attestation verification | API / Backend | — | Cryptographic validation + counter tracking is server-side. Client never validates its own attestation. |
| `trustTier` policy decision | API / Backend | Device (renderer only) | Server decides whether a device is `hardwareAttested` or `softwareOnly`; client renders the "Limited Trust" banner based on server-returned value (D-12). |
| `attestationStatus` classification | Device (Client) | — | Only the client knows why attestation was skipped (unsupported vs entitlementMissing vs quotaExceeded vs simulatorBypass vs error). Backend receives the enum value. |
| Simulator bypass fake attestation | Device (DEBUG-only) | Mock Backend | The fake `attestationObject` + `attestedKeyId = sim-bypass-{installUUID}` is a contract between client DEBUG path and MockURLProtocol fixtures — purely local. |
| CI merge-block | GitHub / Infra | — | Required-status-check is a repository-level Settings configuration, not app code. |
| CI flaky-test retry | CI runner (xcodebuild) | — | `xcodebuild -retry-tests-on-failure -test-iterations 2` runs at the test-harness level, not the YAML step level — more surgical than wrapping the whole step in a retry action. |
| Limited-trust banner rendering | Device (UIKit) | — | UIKit view added to each role's `UITabBarController` container — not SwiftUI per CLAUDE.md. |

## Standard Stack

### Core — Apple Framework (iOS SDK built-in)

| API | Availability | Purpose | Why Standard |
|-----|-------------|---------|--------------|
| `DCAppAttestService.shared` | iOS 14+ (our target: iOS 17+) | Singleton entry to App Attest framework | Apple-sanctioned. Only supported path. [CITED: developer.apple.com/documentation/devicecheck/dcappattestservice/shared] |
| `DCAppAttestService.isSupported: Bool` | iOS 14+ | Runtime capability check | Returns `false` on simulator, app extensions, or pre-A10 devices. First call in every attestation path (D-09 `unsupported` branch). [CITED: developer.apple.com/documentation/devicecheck/dcappattestservice/issupported] |
| `generateKey() async throws -> String` | iOS 14+ | Generates SE-backed keypair; returns opaque `keyId` | Called ONCE per install (D-01). Errors: `featureUnsupported`, `unknownSystemFailure`. [CITED: adjoe.io blog + Apple Developer forum thread 821283] |
| `attestKey(_:clientDataHash:) async throws -> Data` | iOS 14+ | Requests Apple server attestation for a generated key | Returns CBOR-encoded `attestationObject` for backend verification. Errors: `featureUnsupported`, `unknownSystemFailure`, `invalidInput`, `invalidKey`, `serverUnavailable`. [CITED: developer.apple.com/documentation/devicecheck/dcappattestservice/attestkey] |
| `generateAssertion(_:clientDataHash:) async throws -> Data` | iOS 14+ | Generates per-request assertion using attested key | Used by D-07 heartbeat path. Same error surface as `attestKey`. [CITED: developer.apple.com/documentation/devicecheck/dcappattestservice/generateassertion] |
| `DCError.Code` enum | iOS 11+ (DeviceCheck); App-Attest-specific cases from iOS 14 | Error classification | Five public cases: `featureUnsupported`, `invalidInput`, `invalidKey`, `serverUnavailable`, `unknownSystemFailure`. Quota-exceeded surfaces as `serverUnavailable` in most reports. [CITED: developer.apple.com/documentation/devicecheck/dcerror-swift.struct/code] |
| `com.apple.developer.devicecheck.appattest-environment` entitlement | — | Specifies `development` or `production` environment for App Attest server calls | Required — without it, `generateKey()` fails with `featureUnsupported`. TestFlight + App Store distributions **ignore** the entitlement value and always use `production`. [CITED: developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment] |

### Supporting — Apple Framework (already in use, Phases 1-3)

| API | Purpose | Used By |
|-----|---------|---------|
| `Security.framework` — `SecItemAdd`/`SecItemCopyMatching` (via existing `KeychainStore`) | Persist `attestedKeyId` + `lastHeartbeatAt` | D-01 / D-07 persistence; integrates with `KeychainStore.set(_:for:accessibility:)` + `KeychainKey` + `KeychainScope` (session scope MUST NOT include `attestedKeyId` — per D-03 it survives logout) |
| `LocalAuthentication.framework` — `LAContext` | Biometric gating (existing Phase 3 usage) | D-14 seeded `LAContext` for CI — new work is a protocol abstraction, not framework change |
| `CryptoKit.SHA256` | `clientDataHash = SHA256(challenge)` (D-06) | New work in `Core/Attestation` |
| `Foundation.URLRequest` / existing `APIEndpoint` | `DeviceChallengeEndpoint` + `DeviceHeartbeatEndpoint` | Mirror existing `OTPRequestEndpoint` / `DeviceRegisterEndpoint` |

### CI Stack

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `xcodebuild test -retry-tests-on-failure -test-iterations 2` | Xcode 13+ (CI currently Xcode 16.4, dev machine Xcode 26.4) | Retry-once-then-fail at the test-harness level | Native Xcode flag; no third-party action. Runs only the failed tests on retry, not the whole suite. [CITED: developer.apple.com/videos/play/wwdc2021/10296/ + avanderlee.com flaky tests] |
| GitHub Actions branch protection — required status checks | — | Blocks merge when device pipeline fails | Standard GitHub feature. [CITED: docs.github.com/en/repositories/configuring-branches-and-merges/managing-protected-branches/managing-a-branch-protection-rule] |
| Self-hosted macOS runner with attached iPhone | — | Actually exercises Secure Enclave + biometric + App Attest | Already configured for Phase 1 CI-device pipeline (`.github/workflows/ci-device.yml` labels `[self-hosted, macOS, device]` + `secrets.DEVICE_UDID`). [VERIFIED: .github/workflows/ci-device.yml lines 18-33 — file read during research] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `DCAppAttestService` | Firebase App Check with App Attest provider | REJECTED — adds Firebase SDK dependency (violates STACK-01 + STACK-04 zero-third-party-SDK stance). Apple's framework is already available and we own the server side. |
| `xcodebuild -retry-tests-on-failure` | `nick-fields/retry@v3` marketplace action | Native xcodebuild flag is more surgical (retries only failed tests, not the entire CI step) and has no external-action supply-chain risk. Marketplace action is the fallback if per-test retry ever stops working. |
| Required status check via repository Settings UI | Ruleset imported from JSON in `.github/ruleset-recipes` style | UI path is Apple/GitHub-sanctioned for simple cases; ruleset-as-JSON is better for enterprise-scale policy but overkill for a single-repo + single-check setup. [ASSUMED — ruleset file commit-to-repo discovery is partial per WebFetch on docs.github.com/rulesets; confirm with ops before choosing file path.] |
| Self-hosted runner | GitHub-hosted macOS + real iPhone attached to it | REJECTED — GitHub-hosted runners cannot attach a physical device. Self-hosted is already the Phase 1 choice. [VERIFIED: .github/workflows/ci-device.yml line 18] |

**Installation:** No new SwiftPM packages needed. Phase 4 adds ONE entitlement file and zero external dependencies.

**Version verification:** Not applicable — all Apple frameworks ship with iOS 17 SDK; `DeviceCheck.framework` first shipped iOS 11, `DCAppAttestService` first shipped iOS 14. Deployment target of iOS 17 guarantees availability. [VERIFIED: Package.swift line 17 pins `.iOS(.v17)`.]

## Architecture Patterns

### System Architecture Diagram

```
Cold-boot / First OTP Verify                    24h Heartbeat (didBecomeActive)
        │                                              │
        ▼                                              ▼
 ┌──────────────────┐                     ┌──────────────────────────┐
 │ AttestationService│                    │  AttestationService       │
 │  (new protocol)  │                     │   .generateAssertion(     │
 │                  │                     │     keyId,                │
 │ isSupported?     │                     │     hash)                 │
 │  ├─ false → D-09 │                     └──────────────────────────┘
 │  │    .unsupported                                   │
 │  │                                                   ▼
 │  └─ true                             ┌───────────────────────────────┐
 │      │                               │ POST /device/heartbeat         │
 │      ▼                               │  { sessionToken,               │
 │  Keychain read                       │    attestedKeyId,              │
 │  attestedKeyId                       │    assertion }                 │
 │      │                               │  Response:                     │
 │      ├─ found → reuse                │    { registered: true,         │
 │      │                               │      trustTier:                │
 │      └─ missing (fresh install)      │        "hardwareAttested"      │
 │          │                           │        | "softwareOnly" }      │
 │          ▼                           └───────────────────────────────┘
 │  generateKey() ──► Secure Enclave                    │
 │          │ (one-time per install)                    ▼
 │          ▼                              AppContainer.session.trustTier
 │  GET /device/challenge ◄─────── Backend nonce + TTL ≤60s
 │          │ challenge: base64
 │          ▼
 │  clientDataHash = SHA-256(challenge)   [D-06]
 │          │
 │          ▼
 │  attestKey(keyId, hash)
 │          │ attestationObject: CBOR
 │          ▼
 │  POST /device/register                 [D-02 three-key payload]
 │   { deviceKey SPKI,
 │     authorizationKey SPKI,
 │     attestedKeyId,
 │     attestationObject,
 │     attestationStatus: "attested" | ...,
 │     deviceFingerprint }
 │          │
 │          ▼
 │  Backend verifies attestationObject
 │  against Apple's public keys
 │          │
 │          ▼
 │  Response: { registered: true, trustTier: "hardwareAttested" | "softwareOnly" }
 │          │
 │          ▼
 │  Persist attestedKeyId + lastHeartbeatAt in Keychain
 │          │
 │          ▼
 │  Render role shell
 │    + if trustTier != "hardwareAttested": show Limited-Trust banner (D-11)
 │
 ▼

Error paths (all flow through AttestationError mapping → attestationStatus enum):
  .featureUnsupported        → attestationStatus: "entitlementMissing" OR "unsupported"
                               (if isSupported was true but framework now returns this,
                                 it means the entitlement was missing at build time)
  .serverUnavailable (≈rate)  → attestationStatus: "quotaExceeded"  [D-09]
  .invalidInput / .invalidKey → attestationStatus: "error"
  .unknownSystemFailure       → attestationStatus: "error"
  #if targetEnvironment(simulator)  → attestationStatus: "simulatorBypass" [D-10]
```

### Recommended Project Structure

```
validationLedger/
├── Core/
│   ├── Attestation/                    # NEW (Phase 4)
│   │   ├── AttestationService.swift          # Protocol — mirrors KeyStoreProtocol pattern
│   │   ├── DCAppAttestAttestationService.swift  # Production impl
│   │   ├── SimulatorBypassAttestationService.swift  # #if DEBUG && targetEnvironment(simulator)
│   │   ├── AttestationError.swift             # DCError.Code → enum mapping
│   │   ├── AttestationStatus.swift            # 5-value enum matches D-09
│   │   └── TrustTier.swift                    # "hardwareAttested" | "softwareOnly" (D-12)
│   ├── Networking/
│   │   ├── Endpoints/
│   │   │   ├── DeviceChallengeEndpoint.swift       # NEW GET
│   │   │   ├── DeviceHeartbeatEndpoint.swift       # NEW POST
│   │   │   └── DeviceRegisterEndpoint.swift        # EXTENDED — optional attestation fields
│   │   └── Mock/Fixtures/
│   │       ├── device-challenge-success.json       # NEW
│   │       ├── device-heartbeat-success.json       # NEW
│   │       ├── device-heartbeat-attestation-invalid.json  # NEW (D-04 re-attest trigger)
│   │       └── device-register-software-only.json  # NEW (D-10 simulator-bypass path)
│   └── Storage/Keychain/
│       └── KeychainKey.swift                       # EXTENDED — new keys
│                                                   #   device.attestedKeyId
│                                                   #   device.lastHeartbeatAt
├── App/
│   ├── AppContainer.swift              # EXTENDED — attestationService prop
│   └── SceneDelegate.swift             # EXTENDED — cold-boot heartbeat + didBecomeActive 24h check
├── UI/                                 # NEW or extension of existing UI/
│   └── LimitedTrustBannerView.swift    # UIKit view inserted into role shell (D-11)
├── Roles/
│   └── RoleCoordinator.swift           # EXTENDED — wraps TabBarController with banner when trustTier != "hardwareAttested"
├── docs/
│   ├── ci.md                           # EXTENDED — Phase 4 Device Pipeline section
│   ├── attestation-rotation.md         # NEW (optional — runbook for D-04 re-attest)
│   └── adr/
│       └── 0005-three-key-device-register-payload.md  # NEW
└── validationLedger.entitlements       # NEW — com.apple.developer.devicecheck.appattest-environment = development

validationLedgerDeviceTests/            # EXTENDED (D-13 full-security-surface)
├── SecureEnclaveKeyStoreTests.swift              # Already exists — Phase 2
├── SecureEnclaveSmokeTests.swift                 # Already exists — Phase 1
├── KeychainBiometricACLTests.swift               # NEW — seeded LAContext path
├── AppAttestRoundTripTests.swift                 # NEW — MockURLProtocol-backed
├── LogoutClearsAuthorizationKeyTests.swift       # NEW — retires 1 of Phase 3 HUMAN-UAT
└── SeededLAContext.swift                         # NEW — injectable LAContext for D-14

.github/workflows/
└── ci-device.yml                       # UPGRADED — full suite + retry + required-status-check trigger
```

### Pattern 1: `AttestationService` Protocol Mirror

**What:** A protocol + two implementations mirroring Phase 2's `KeyStoreProtocol` + `SecureEnclaveKeyStore` / `SoftwareKeyStore` split.
**When to use:** Every Phase 4 call to `DCAppAttestService` — never call the Apple singleton directly from Features or Coordinators.
**Example:**
```swift
// Source: mirrors Core/KeyStore/KeyStoreProtocol.swift (Phase 2 — verified in codebase)
import Foundation
import DeviceCheck
import CryptoKit

public enum AttestationStatus: String, Sendable, Codable {
    case attested
    case unsupported
    case entitlementMissing
    case quotaExceeded
    case simulatorBypass
    case error
}

public enum AttestationError: Error, Sendable {
    case notSupported                  // DCAppAttestService.isSupported == false
    case featureUnsupported            // Entitlement missing
    case rateLimited                   // serverUnavailable interpreted as quota per Pitfall 2
    case serverUnavailable             // Transient
    case invalidKey                    // Key rotation required
    case invalidInput
    case unknownSystemFailure
    case underlying(NSError)
}

public protocol AttestationService: AnyObject, Sendable {
    /// Returns a persisted `attestedKeyId` if one exists, or generates a new one
    /// (once per install — D-01). On failure, returns the appropriate `AttestationStatus`.
    func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus)

    /// Given a server-provided challenge, produces the CBOR-encoded attestationObject.
    /// `clientDataHash = SHA-256(challenge)` per D-06.
    func attestKey(keyId: String, challenge: Data) async throws -> Data

    /// Given a server-provided challenge, produces an assertion for the existing key.
    /// Used for /device/heartbeat (D-07).
    func generateAssertion(keyId: String, challenge: Data) async throws -> Data

    /// Deletes the persisted `attestedKeyId` from Keychain so the next call regenerates.
    /// Called by LogoutService? NO — D-03 says preserve across logout. Called only on
    /// backend-driven re-attestation signal (D-04).
    func clearPersistedKeyId() throws
}

// Production impl — `#else` branch
@MainActor
public final class DCAppAttestAttestationService: AttestationService {
    private let service = DCAppAttestService.shared
    private let keychain: KeychainStore
    private let logger: any Logger

    public func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus) {
        guard service.isSupported else {
            return ("", .unsupported)
        }
        if let existing = try? keychain.get(.attestedKeyId),
           let decoded = String(data: existing, encoding: .utf8) {
            return (decoded, .attested)
        }
        do {
            let keyId = try await service.generateKey()
            try keychain.set(
                Data(keyId.utf8),
                for: .attestedKeyId,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
            return (keyId, .attested)
        } catch let err as NSError where err.domain == DCError.errorDomain {
            return ("", statusForDCError(err))
        }
    }

    private func statusForDCError(_ err: NSError) -> AttestationStatus {
        guard let code = DCError.Code(rawValue: err.code) else { return .error }
        switch code {
        case .featureUnsupported: return .entitlementMissing
        case .serverUnavailable:  return .quotaExceeded  // D-09 interprets as quota per Pitfall 2
        case .invalidInput, .invalidKey, .unknownSystemFailure: return .error
        @unknown default: return .error
        }
    }

    public func attestKey(keyId: String, challenge: Data) async throws -> Data {
        let hash = Data(SHA256.hash(data: challenge))
        return try await service.attestKey(keyId, clientDataHash: hash)
    }

    public func generateAssertion(keyId: String, challenge: Data) async throws -> Data {
        let hash = Data(SHA256.hash(data: challenge))
        return try await service.generateAssertion(keyId, clientDataHash: hash)
    }
}

// Simulator-bypass impl — `#if DEBUG && targetEnvironment(simulator)` branch
#if DEBUG && targetEnvironment(simulator)
public final class SimulatorBypassAttestationService: AttestationService {
    private let keychain: KeychainStore
    public func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus) {
        // D-10: sim-bypass-{installUUID} — the fixture recognizes this prefix
        let installUUID = try DeviceFingerprint.current(keychain: keychain).installUUID
        return ("sim-bypass-\(installUUID)", .simulatorBypass)
    }
    public func attestKey(keyId: String, challenge: Data) async throws -> Data {
        // Fixed fake CBOR-ish shape per D-10
        return Data("sim-bypass-attestation-object-v1".utf8)
    }
    public func generateAssertion(keyId: String, challenge: Data) async throws -> Data {
        return Data("sim-bypass-assertion-v1".utf8)
    }
    public func clearPersistedKeyId() throws {
        try keychain.delete(.attestedKeyId)
    }
}
#endif
```
**Provenance:** API shape `[CITED: Apple DeviceCheck docs]`; `clientDataHash = SHA256(challenge)` `[CITED: adjoe.io engineering blog — `Data(SHA256.hash(data: challenge))` pattern verified]`; protocol structure mirrors Phase 2 `[VERIFIED: validationLedger/Core/KeyStore/KeyStoreProtocol.swift]`.

### Pattern 2: Extended `DeviceRegisterEndpoint` with Optional Attestation Fields

**What:** Extending the Phase 2 `DeviceRegisterEndpoint.RequestBody` to carry the three-key payload, with `attestationObject` + `attestedKeyId` as optional (omitted when `attestationStatus != "attested"`).
**When to use:** Every `/device/register` call Phase 4+ makes.
**Example:**
```swift
// Source: extending existing validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
// The existing file's comment at line 5 explicitly anticipates this extension:
//   "Phase 4 will ADD an optional attestation field — that's a non-breaking Decodable extension."
public struct RequestBody: Encodable, Sendable {
    public let devicePublicKey: String            // deviceKey SPKI (Phase 2 DEV-01)
    public let authorizationPublicKey: String    // authorizationKey SPKI (Phase 2 DEV-02)
    public let attestedKeyId: String?             // Phase 4 DEV-04 — nil when status != .attested
    public let attestationObject: Data?           // Phase 4 DEV-04 — nil when status != .attested
    public let attestationStatus: AttestationStatus // Phase 4 DEV-04 — ALWAYS present (D-09)
    public let deviceFingerprint: DeviceFingerprintPayload
}
public struct Response: Decodable, Sendable {
    public let deviceID: String
    public let registeredAt: Date
    public let trustTier: TrustTier               // NEW Phase 4 D-12
}
```
**Provenance:** `[VERIFIED: DeviceRegisterEndpoint.swift line 5 comment]` explicitly anticipates this extension path.

### Pattern 3: `DeviceChallengeEndpoint` and `DeviceHeartbeatEndpoint`

**What:** Two new endpoint structs following the Phase 2 `APIEndpoint` pattern.
**When to use:** Challenge is fetched immediately before every `attestKey()` / `generateAssertion()` call (D-05). Heartbeat fires on cold-boot and 24h-since-last `didBecomeActive` (D-07).
**Example:**
```swift
// DeviceChallengeEndpoint — GET /device/challenge
nonisolated public struct DeviceChallengeEndpoint: APIEndpoint {
    public struct Response: Decodable, Sendable {
        public let challenge: String     // base64
        public let expiresAt: Date
        public let nonce: String
    }
    public let path = "/device/challenge"
    public let method: HTTPMethod = .get
    public let body: EmptyBody? = nil
}

// DeviceHeartbeatEndpoint — POST /device/heartbeat
nonisolated public struct DeviceHeartbeatEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let sessionToken: String
        public let attestedKeyId: String
        public let assertion: Data  // base64-encoded at wire time
    }
    public struct Response: Decodable, Sendable {
        public let heartbeatAcceptedAt: Date
        public let trustTier: TrustTier
    }
    public let path = "/device/heartbeat"
    public let method: HTTPMethod = .post
    public let body: RequestBody?
}
```

**Idempotency:** `POST /device/heartbeat` is a NET-04 interceptor POST, so `IdempotencyInterceptor` injects `Idempotency-Key: UUID().uuidString` automatically. Per `[VERIFIED: IdempotencyInterceptor.swift lines 16-28]`, the interceptor skips GET/DELETE and doesn't overwrite caller-supplied keys — the heartbeat call produces a fresh key per invocation, which is correct (each heartbeat is a distinct event, not a retry of a previous one). `[ASSUMED]` The backend should reject duplicate `Idempotency-Key` replays for heartbeat, but confirm with backend team during Phase 4 execution.

### Pattern 4: CI YAML Upgrade (Device Pipeline)

**What:** Full-security-surface run with native xcodebuild retry.
**When to use:** Replace the current single-test `SecureEnclaveSmokeTests` invocation in `.github/workflows/ci-device.yml`.
**Example:**
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
      - 'validationLedger/Core/Attestation/**'      # Phase 4 addition

jobs:
  device-security-surface:
    runs-on: [self-hosted, macOS, device]
    timeout-minutes: 25    # bumped from 15 — attestation tests involve real Apple round-trip
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Show Xcode version
        run: xcodebuild -version

      - name: Run full device security surface (D-13) with single-retry (D-15)
        # -retry-tests-on-failure + -test-iterations 2 means: on first failure, retry the
        # failed test ONCE. If it fails twice → workflow fails. If it passes on retry,
        # xcodebuild emits a flaky-pass annotation we surface to Slack via the post step.
        # WHY native flag over nick-fields/retry: xcodebuild retries only the FAILED test,
        # not the whole 25-min CI step. Much tighter feedback loop.
        run: |
          set -o pipefail
          xcodebuild test \
            -project validationLedger.xcodeproj \
            -scheme validationLedger \
            -destination "platform=iOS,id=${{ secrets.DEVICE_UDID }}" \
            -only-testing:validationLedgerDeviceTests \
            -retry-tests-on-failure \
            -test-iterations 2 \
            -resultBundlePath $PWD/build/DeviceTestResults.xcresult

      - name: Upload device test result bundle
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: device-test-results
          path: build/DeviceTestResults.xcresult
          retention-days: 14

      - name: Notify Slack on flaky-pass (D-15 visibility)
        if: success()
        # Parse .xcresult for "retry"-labeled tests; post to Slack if any retries happened.
        # Quiet when zero retries — only speaks up on flaky passes that could mask real bugs.
        run: bash scripts/report-flaky-passes.sh $PWD/build/DeviceTestResults.xcresult
```
**Provenance:** `-retry-tests-on-failure` / `-test-iterations` `[CITED: WWDC21 session 10296 + avanderlee.com flaky tests blog]`; existing self-hosted runner config `[VERIFIED: .github/workflows/ci-device.yml lines 17-34]`; path-trigger pattern `[VERIFIED: .github/workflows/ci-device.yml lines 8-15]`.

### Pattern 5: `preflightAttestationEntitlement()` Mirror

**What:** A pure-Bool static mirror of `AppContainer.preflightSecureEnclave(...)` that logs (does NOT fatalError) when the App Attest entitlement is missing in production.
**When to use:** Logs at `error` level during `AppContainer.init`; does not block launch. D-09's `entitlementMissing` enum value carries the information to the backend, which decides policy (D-12).
**Example:**
```swift
// In AppContainer.swift — mirror of preflightSecureEnclave (lines 303-327, VERIFIED read)
static func preflightAttestationEntitlement(
    isSupported: Bool = DCAppAttestService.shared.isSupported,
    isSimulatorBuild: Bool = { /* ... */ }(),
    isDebugBuild: Bool = { /* ... */ }()
) -> AttestationEntitlementPreflightResult {
    // Unlike Secure Enclave — DO NOT fatalError on missing entitlement.
    // Missing entitlement is recoverable (ship a fix, re-sign, re-upload TestFlight).
    // Log at error so the dev team notices in Console; return softwareOnly via D-09.
    if isDebugBuild && isSimulatorBuild { return .simulatorBypass }
    return isSupported ? .available : .missing
}
```
**Why not fatalError like SE:** Secure Enclave absence is a deterministic hardware fact — a device without SEP cannot ever recover. Entitlement absence is a config bug that's fixable in the next build — fatalError'ing in Release would brick every user with a bad build. D-09's graceful-skip contract is the correct posture.

### Anti-Patterns to Avoid

- **Storing the App Attest key / private key anywhere outside Secure Enclave:** Apple's framework keeps the private key opaque in SE. We only persist the `attestedKeyId` identifier (D-01). A plan that suggests exporting the key material is rejected at review.
- **Calling `DCAppAttestService.shared` directly from Features or Coordinators:** All calls go through `AttestationService` protocol so tests can inject a fake. Mirrors the existing `KeyStoreProtocol` / `BiometricService` / `LocationProvider` disciplines.
- **Hand-coding the server challenge nonce or TTL:** Backend owns all challenge semantics. Client is a passive consumer (D-05 + D-08). A plan that suggests client-side challenge generation is rejected.
- **Binding `clientDataHash` to request body:** D-06 is explicit — `SHA256(challenge)` only. Apple's reference sample does the same. Binding body bytes into the hash creates versioning headaches when the body evolves.
- **Persisting `lastHeartbeatAt` in UserDefaults:** CLAUDE.md + SEC-03 forbid sensitive data in UserDefaults. Use Keychain per `<specifics>` section of CONTEXT.md.
- **Retrying App Attest on every cold boot:** D-01 is ONCE PER INSTALL. Each extra `generateKey()` consumes a slot against Apple's undocumented quota (Pitfall 2).
- **Using `#available(iOS 14.0, *)` availability guards:** Deployment target is iOS 17 — such guards are always-true and the SwiftLint linter should flag them as dead checks.
- **Writing attestation blob bytes to `LogField`:** PII-scrubbed structured logging — log only the `attestationStatus` enum value and `DCError.Code` raw value. Extend `LogField` to reject Data types at the type level if not already enforced.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| App Attest protocol | Custom cryptographic attestation scheme | `DCAppAttestService` | Apple's framework is the ONLY way to bind to hardware attestation; rolling our own would require Apple's signing keys we don't have. |
| CBOR encoding of `attestationObject` | A hand-rolled CBOR decoder on client or server | Framework returns raw bytes; backend uses a verified CBOR library (e.g., `veehaitch/devicecheck-appattest` Kotlin lib referenced in WebSearch results) | CBOR + COSE validation has many edge cases; correctness matters for security. Backend verification is out of Phase 4 scope (client-side). |
| Challenge generation | Local UUID → sign → send as challenge | `GET /device/challenge` (D-05) | Server must control nonce + TTL + single-use invariant; only server can validate its own challenges are authentic. |
| Biometric OS prompt UI in tests | Subclass `LAContext` with custom Face ID mock UI | Seeded `LAContext` via protocol (`BiometricService` already exists; D-14 leverages it) | OS prompt UI is chrome — we test the auth path, not Apple's UI. Seeding a protocol that returns `.success` is industry-standard. |
| Flaky-test retry machinery | Custom shell script wrapping xcodebuild with pass-counts + exit-code parsing | `xcodebuild -retry-tests-on-failure -test-iterations 2` | Native Xcode flag; handles per-test retry (not per-step retry) — more surgical. |
| Required-status-check config | Custom GitHub App that posts commit statuses + custom merge-gate logic | GitHub branch protection rules / rulesets | Built-in feature. Any custom solution risks drift from GitHub's security model. |
| Trust-tier policy decisions | Client-side rules engine for when to show Limited Trust banner | Backend returns `trustTier` enum; client renders based on value (D-12) | Policy belongs server-side — new tiers can be added without shipping a new client. |
| Secure Enclave key export for attestation | Bridge SE keys into App Attest key | App Attest has its own independent SE keypair (D-02 three-key design) | Apple's framework generates + manages its own key; trying to reuse `deviceKey`/`authorizationKey` breaks the hardware attestation contract. |

**Key insight:** Phase 4 is almost entirely a thin wrapper around Apple's framework + contract-first endpoint plumbing + CI YAML edits. The three-key split (D-02) exists specifically because rolling our own attestation on top of `deviceKey`/`authorizationKey` would fail — only Apple can produce `attestationObject`, and it only works with an App-Attest-owned SE key.

## Runtime State Inventory

Phase 4 introduces new runtime state. Audit:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | New Keychain entries: `device.attestedKeyId` (opaque string from Apple), `device.lastHeartbeatAt` (ISO8601 timestamp). On backend-driven re-attestation (D-04), `device.attestedKeyId` is deleted + regenerated — `device.lastHeartbeatAt` stays (next heartbeat will overwrite). On logout (D-03), both entries PRESERVED. On FOUND-02 first-launch wipe (reinstall), both are wiped along with everything else. | Code edit: new `KeychainKey.attestedKeyId` + `KeychainKey.lastHeartbeatAt` constants; extend `KeychainScope.session.contains(_:)` to EXCLUDE these two keys (D-03). No data migration — fresh Phase 4 install starts empty. |
| **Live service config** | None — Phase 4 is code + CI YAML, not an external service with its own config DB. | None. |
| **OS-registered state** | `com.apple.developer.devicecheck.appattest-environment` entitlement in `validationLedger.entitlements` (new file) gets baked into the signed app binary's embedded.mobileprovision blob at build time. Once signed + distributed, the entitlement value lives in the binary; changing it requires re-signing + re-uploading. | Code edit: create `validationLedger.entitlements`; add entitlement value `development`; update Xcode project's code signing entitlements setting to point to the new file. Dev-team process: ensure the provisioning profile (via Apple Developer portal) includes the App Attest capability. |
| **Secrets / env vars** | `secrets.DEVICE_UDID` already exists `[VERIFIED: .github/workflows/ci-device.yml line 33]`. No new secrets required for Phase 4 — attestation uses no API keys. | None. |
| **Build artifacts / installed packages** | `DeviceTestResults.xcresult` bundle produced per CI run; uploaded as artifact with 14-day retention (Phase 4 bumps from Phase 1's 7-day simulator retention — attestation failures are harder to diagnose, longer retention helps). Also: SwiftPM package cache unchanged (no new dependencies). | None — existing artifact workflow covers this. |

**Canonical question:** After every file in the repo is updated, what runtime systems still have the old string cached, stored, or registered? Answer: none — Phase 4 is additive, not a rename. Existing Phase 3 Keychain contents + SE keys + session state all survive intact. The only new persistent state is the two new Keychain keys above, which only exist after Phase 4 lands.

## Common Pitfalls

### Pitfall 1: Calling `generateKey()` on every cold boot

**What goes wrong:** Each `generateKey()` consumes quota against Apple's undocumented rate limit. Repeated cold-boots by one user could exhaust the quota for the entire app.
**Why it happens:** D-01's once-per-install discipline is easy to violate — a developer might forget to check the Keychain cache before calling `generateKey()`, or clear the cache on logout by accident.
**How to avoid:** `AttestationService.generateKeyIfNeeded()` always reads Keychain FIRST; only calls `generateKey()` when the Keychain entry is absent. The key surviving logout (D-03) is the mechanism that preserves this across the ONLY cold-boot scenario where a developer might be tempted to regenerate.
**Warning signs:** Integration test that calls `generateKeyIfNeeded()` twice and asserts `generateKey` (the SE one) was called exactly once.
[CITED: approov.io App Attest limitations; developer.apple.com/forums/thread/722988]

### Pitfall 2: Misinterpreting `serverUnavailable` as a transient server issue

**What goes wrong:** The documented meaning is "Apple's attestation server is unreachable." In practice, community reports indicate that quota-exhaustion ALSO surfaces as `serverUnavailable` (sometimes `unknownSystemFailure`) — there's no dedicated "rate limited" error code. A client that retries on `serverUnavailable` burns more quota, compounding the problem.
**Why it happens:** Apple has not published a dedicated rate-limit error code. Reliable sources indicate the quota is enforced per-app-bundle-id across all users, with no published SLA for increases.
**How to avoid:** Treat `serverUnavailable` as `quotaExceeded` in D-09's enum (client code catches `DCError.Code.serverUnavailable` → emits `attestationStatus: "quotaExceeded"`). Apply D-04's backend-driven re-attestation posture: don't retry on the client, let backend decide when to prompt a retry. Include exponential-backoff in any retry path `[ASSUMED — D-04's "backend-driven only" suggests client doesn't retry at all on quotaExceeded; confirm with backend team that the protocol doesn't need a client-side retry window before Phase 4 execution.]`
**Warning signs:** Spike in `attestationStatus: "quotaExceeded"` telemetry. The Apple-recommended mitigation is "gradually onboard users" — a billion users over 30 days.
[CITED: approov.io; apple.com/forums/thread/759285; apple.com/forums/thread/821283]

### Pitfall 3: Entitlement environment value in TestFlight / App Store builds

**What goes wrong:** A developer sets the `com.apple.developer.devicecheck.appattest-environment` entitlement to `production` in a TestFlight build, expecting it to behave differently. Apple actually IGNORES the entitlement value in TestFlight and App Store distributions and always uses `production` regardless.
**Why it happens:** The entitlement documentation is easy to misread — it sounds like the value is authoritative at all times. Only in Xcode-direct development installs does the value matter (`development` routes to the staging attestation servers; `production` routes to prod).
**How to avoid:** For Phase 4 dev + internal TestFlight work, use `development`. Phase 4's M5 App Store submission path doesn't need an entitlement flip — Apple handles the routing. Document this explicitly in `validationLedger.entitlements`.
**Warning signs:** If `generateKey()` returns `.featureUnsupported` for a TestFlight build, the most common cause is that the entitlement is missing entirely, NOT that the environment value is wrong. Check the provisioning profile embeds the App Attest capability.
[CITED: developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment]

### Pitfall 4: GitHub Actions required-status-check first-run chicken-and-egg

**What goes wrong:** The required-status-check config in GitHub's Settings UI only LISTS check names that have actually run on the protected branch within the last 7 days. If you flip the branch-protection "Require status checks" ON before the `ci-device` job has ever run on `main`, the job name isn't in the dropdown and you can't require it. If you require a name that hasn't run yet, `main` is locked with no way to merge.
**Why it happens:** GitHub's check-name registration is emergent (seeded by actual workflow runs), not declarative.
**How to avoid:** Phase 4 execution order:
1. Land the upgraded `ci-device.yml` workflow (with push + pr triggers) in a normal PR.
2. Merge the PR — this triggers the workflow on `main` for the first time.
3. Wait for the workflow to complete (pass or fail).
4. Go to Settings → Branches → Edit `main` rule → tick "Require status checks to pass" → select `device-security-surface` (the job name) from the dropdown.
5. Save. Now the next PR to `main` is gated.
The `push: branches: [main]` trigger on the workflow (already present) ensures step 2 fires the check on `main`; the current PR-only `paths:` filter is also still present, which is fine.
**Warning signs:** Opening the branch-protection rule editor and not seeing `device-security-surface` in the available-checks dropdown. If this happens, the workflow hasn't run on `main` yet.
[CITED: docs.github.com branch protection rules discussion #167194 + #54877]

### Pitfall 5: LAContext seeded mock lets false positives through

**What goes wrong:** A seeded `LAContext` that always returns `.success` masks bugs where the production code forgets to wire biometric gating at all. A test that uses the seeded context passes; production hits a real SE key with no biometric check and silently succeeds or silently fails depending on ACL.
**Why it happens:** D-14's seeded `LAContext` is for testing the CLIENT code path ("what does the app do when biometric succeeds?") — not for testing Apple's biometric hardware (which is what HUMAN-UAT does). It's easy to misuse as an end-to-end biometric test.
**How to avoid:** Keep the test scope explicit in test names: `testKeychainACLCreatedWhenBiometricSucceeds` is honest; `testBiometricAuthFlow` is misleading. Every seeded-LAContext test should have a HUMAN-UAT counterpart that verifies real Face ID on hardware. D-14 names this explicitly — the seeded context tests Keychain ACL creation, not the OS biometric UI.
**Warning signs:** A test name that implies "biometric auth works" without a paired HUMAN-UAT item on the real device.
[CITED: navoshta.com unit tests for Touch ID; OWASP MASTG local auth guide]

### Pitfall 6: Heartbeat fires from a restored-session cold-boot BEFORE the session is confirmed valid

**What goes wrong:** `SessionRestoreProbe.probe()` returns `.restored(role)` based purely on the presence of a Keychain session token — it does NOT validate the token against the backend (`[VERIFIED: phase 3 CONTEXT.md D-04 "no JWT exp parse, no /auth/me round-trip"]`). If the token is server-side stale (revoked + not yet 401'd on first request), a cold-boot heartbeat fires against a dead session and wastes quota on an `attestationInvalid` response.
**Why it happens:** D-07's cold-boot heartbeat piggybacks on `SessionRestoreProbe.restored` — but probe-success ≠ session-still-valid.
**How to avoid:** The heartbeat request itself is the server-validity check. `POST /device/heartbeat` with an expired session returns 401, which triggers the existing Phase 3 `Auth401ResponseInterceptor` → `LogoutService.logout(.auth401)` → root-swap to `.auth`. So the "wasted" heartbeat actually serves dual duty as session validation. Document this in the `Core/Attestation/` module header comment so future engineers don't add a redundant `/auth/me` check.
**Warning signs:** Telemetry showing a spike of 401s from `/device/heartbeat` immediately after app launch — this is NORMAL (legitimate stale-session detection) but looks alarming in dashboards.

### Pitfall 7: Banner layout breaks when rotated to iPad landscape

**What goes wrong:** D-11's "Limited trust mode" banner is a thin strip above the tab bar. A naive implementation adds it as a subview of `UITabBarController.tabBar`, which Apple does not support (and which breaks on iPad landscape / Split View).
**Why it happens:** Developers reach for the most visually-obvious container; UITabBarController's tab bar is not a general-purpose container for added views.
**How to avoid:** Add a `UIView` subclass as a subview of the tab bar controller's VIEW (its `.view`), positioned above the tabBar via Auto Layout. Or: wrap each role's `UITabBarController` in a parent container `UIViewController` whose view stack is `[tabBarController.view, limitedTrustBannerView]`. The wrapper approach is cleaner. Check the existing `RoleCoordinator.wrapTabsWithNavAndInstallAvatar` extension `[VERIFIED: referenced in 03-VERIFICATION.md line 152]` — Phase 4 extends that wrapper to conditionally insert a banner when `trustTier != .hardwareAttested`.
**Warning signs:** Banner disappears, overlaps tab icons, or renders partially offscreen on iPad landscape.
[ASSUMED — the current `wrapTabsWithNavAndInstallAvatar` internal structure is assumed from verification-report references; confirm during Phase 4 plan authorship.]

## Code Examples

### Common Operation 1: Cold-boot heartbeat invocation

```swift
// In SceneDelegate.scene(_:willConnectTo:), immediately after SessionRestoreProbe returns .restored
// Extension of the current path at SceneDelegate.swift lines 183-193 (VERIFIED read).
switch SessionRestoreProbe.probe(env: .current) {
case .restored(let role):
    // Phase 4 addition: fire-and-forget 24h heartbeat on cold-boot.
    // Errors are handled inline — a failed heartbeat does NOT block role-shell render.
    Task { @MainActor in
        await self.performHeartbeatIfNeeded(container: container)
    }
    presentRoot(.role(role), checkLockState: true)
case .needsAuth:
    presentRoot(.auth)
}

// New helper. Reads lastHeartbeatAt, decides if >24h has elapsed, fires heartbeat if yes.
// Cold-boot case: lastHeartbeatAt is Keychain-persisted, so this survives process death.
@MainActor
private func performHeartbeatIfNeeded(container: AppContainer) async {
    do {
        let shouldHeartbeat = try container.attestationService.shouldHeartbeat(now: .now)
        guard shouldHeartbeat else { return }
        let challenge = try await container.apiClient.send(DeviceChallengeEndpoint()).challenge
        let challengeData = Data(base64Encoded: challenge) ?? Data()
        let keyId = try container.keychainStore.get(.attestedKeyId)
        let assertion = try await container.attestationService.generateAssertion(
            keyId: String(decoding: keyId, as: UTF8.self),
            challenge: challengeData
        )
        let response = try await container.apiClient.send(DeviceHeartbeatEndpoint(
            sessionToken: ...,
            attestedKeyId: ...,
            assertion: assertion
        ))
        container.session.trustTier = response.trustTier  // D-12
        try container.keychainStore.set(
            Date().iso8601Data, for: .lastHeartbeatAt,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    } catch {
        container.logger.error(event: .init("attestation_heartbeat_failed"),
                               fields: [.error: String(describing: error)])
        // Silent-fail — user still gets role shell. Backend will re-prompt via trustTier = softwareOnly
        // on next /device/register if policy demands re-attestation.
    }
}
```

### Common Operation 2: Seeded LAContext for unattended CI

```swift
// New file: validationLedgerDeviceTests/SeededLAContext.swift
// Used by D-14 — biometric-prompt tests on device CI without real Face ID.
// The SeededBiometricService below implements the existing Phase 3 BiometricService protocol
// so injection via AppContainer is uniform with production code.
import LocalAuthentication
@testable import validationLedger

final class SeededBiometricService: BiometricService, @unchecked Sendable {
    // Seeded "success" — evaluate returns without throwing, doesn't touch real LAContext.
    func evaluate(reason: String, fallback: BiometricFallback) async throws {
        // No-op. Tests that depend on the KeychainStore side effect (biometricDomainState
        // write) should also inject a KeychainStore stub, or tolerate that the write is skipped.
    }
    // Seeded "stable biometric" — return a fixed non-nil Data so re-enrollment diff is always false.
    func currentDomainState() -> Data? { Data("seeded-domain-state".utf8) }
}

// Wire-up in a device test:
@Test("Keychain biometryCurrentSet ACL round-trip behind seeded biometric")
func keychainBiometricRoundTrip() async throws {
    let container = AppContainer(
        env: .current,
        networkConfig: .mock,
        isSecureEnclaveAvailable: true
        // TODO(Phase 4 planner): surface a BiometricService injection parameter on AppContainer.init,
        // OR make the test wire the seeded service via a separate factory path.
    )
    // ... real-SE Keychain write/read/delete with seeded biometric ...
}
```
**Provenance:** Test pattern `[CITED: navoshta.com Touch ID unit tests; qualitycoding.org Swift mocking]`; AppContainer injection surface `[VERIFIED: AppContainer.swift lines 89-93 `isSecureEnclaveAvailable` parameter already demonstrates the pattern]`.

### Common Operation 3: Branch protection configuration (one-time manual step)

```
GitHub Repository Settings → Branches → Add branch ruleset (or: Classic branch protection rule)
│
├── Apply to branches: main
│
├── Require status checks to pass before merging: [CHECKED]
│   │
│   ├── Require branches to be up to date before merging: [CHECKED or UNCHECKED — team preference]
│   │
│   └── Status checks that are required:
│       ├── CI (Simulator) / test                           (Phase 1 existing)
│       └── CI (Device) / device-security-surface          (Phase 4 NEW — ONLY visible in dropdown
│                                                             AFTER the workflow has run on main
│                                                             at least once per Pitfall 4)
│
└── Do not allow bypassing the above settings: [CHECKED for admins, unless break-glass needed]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No device attestation (Phase 1–3 only had Secure Enclave keys + cert pinning) | App Attest attestation-object bound to SE-hosted key, verified server-side | iOS 14 (App Attest GA) | Adds hardware-rooted proof that a request comes from an unmodified copy of this app on a real iPhone. Defeats attackers who steal Keychain + SE keys from a jailbroken device. |
| Client-side App Attest retry on `serverUnavailable` | Backend-driven re-attestation; client never self-retries (D-04) | Community best-practice 2023+ after production deployments hit rate-limit walls | Prevents quota exhaustion amplification. |
| Single-shot attest-on-registration | Attest + periodic assertion heartbeat | WWDC21 "Mitigate fraud" session 10244 | Ties ongoing session validity to continued device authenticity (D-07). |
| Branch-protection via Classic rules | Branch rulesets (2023+) | GitHub Rulesets GA 2023 | More expressive than Classic rules; supports overlapping rulesets, enterprise import/export. For Phase 4's single-check case, Classic rules are still simpler. |

**Deprecated/outdated:**
- `DCDevice` (the older DeviceCheck API without App Attest) — superseded for authenticity checks by App Attest since iOS 14. DCDevice remains for other DeviceCheck use cases (e.g., setting device-bound bits), but Phase 4 uses only `DCAppAttestService`.
- Xcode 13's `-retry-tests-on-failure` flag — still present and supported in Xcode 16.4 (our CI floor per `docs/ci.md`); no deprecation.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Apple's undocumented App Attest quota is per-app-bundle-id across all users, not per-device | Common Pitfalls §Pitfall 2 | If actually per-device, D-01's once-per-install optimization is less valuable than we think; if per-account, re-install after account switch may hit a different throttle. |
| A2 | Quota-exhaustion surfaces as `DCError.Code.serverUnavailable` in most cases, occasionally `.unknownSystemFailure` | Common Pitfalls §Pitfall 2 | If it surfaces as a different error code (or as multiple codes simultaneously), the D-09 enum mapping is wrong — specifically `quotaExceeded` may need to catch more cases. |
| A3 | Backend will emit error codes `attestationInvalid` / `nonceExpired` / `keyCompromised` for D-04 re-attestation triggers | Standard Stack §`AttestationError`, Architecture §Pattern 1 | If the backend uses different error-code string values, Phase 4 executors must adjust the `AttestationError` enum mapping; client emits a generic `.underlying(...)` case until coordinated with backend team. |
| A4 | D-07 heartbeat POST is fire-and-forget from iOS perspective — failure doesn't block role-shell render | Code Examples §Common Operation 1 | If product policy wants "block rendering if heartbeat fails," the implementation inverts: the `await` is blocking and lock overlay presents on heartbeat failure. CONTEXT.md D-07 doesn't specify; current research assumes fire-and-forget. |
| A5 | `IdempotencyInterceptor` is correct posture for `/device/heartbeat` POST — each heartbeat gets a fresh UUID, backend dedupes duplicate keys | Pattern 3 §Idempotency | If heartbeat is a time-series event (not a mutation), idempotency keys may be meaningless — a pure POST without Idempotency-Key would also be fine. Check with backend team. |
| A6 | GitHub branch-protection UI listing check-names requires at least one prior run on protected branch | Common Pitfalls §Pitfall 4 | If GitHub's UI has a "manual check name entry" option, the first-run dance is unnecessary. Current GitHub docs say the check must have run; but enterprise plans may differ. |
| A7 | `RoleCoordinator.wrapTabsWithNavAndInstallAvatar` is the natural integration point for the Limited-Trust banner | Common Pitfalls §Pitfall 7 | If the method is actually tightly scoped to avatar installation and doesn't compose with banner insertion, Phase 4 needs a new wrapper method. Plan-time code read will resolve. |
| A8 | Xcode 16.4 on CI supports `-retry-tests-on-failure -test-iterations 2` identically to Xcode 26.4 on dev | Pattern 4 | The flag was introduced in Xcode 13 and is stable; extremely unlikely to differ across Xcode 16.4 vs 26.4, but not empirically tested in this repo. |
| A9 | "Limited trust mode" banner non-dismissibility can be enforced purely with `isUserInteractionEnabled = false` + no swipe-to-dismiss gesture | Architecture §Project Structure (UI/LimitedTrustBannerView) | If there's an accessibility requirement (VoiceOver-to-dismiss) the design breaks; English-only M1 per CONTEXT "English-only for M1" suggests accessibility nuances are deferred, but double-check with product. |
| A10 | Mock backend's `/device/register` fixture can recognize `attestedKeyId: "sim-bypass-{installUUID}"` and accept with `trustTier: "softwareOnly"` as documented in D-10 | Pattern 1, Pattern 2 | This is a new MockURLProtocol fixture contract — not yet implemented. Phase 4 plan must land the fixture with exactly this prefix-match behavior for the simulator-bypass integration tests to work. |
| A11 | `DCAppAttestService` is a singleton via `.shared` — there is no per-instance/per-bundle-id alternative instance mechanism | Standard Stack table | If future Apple SDK adds a non-singleton form, the `AttestationService` protocol still abstracts correctly; no downstream impact. |
| A12 | TestFlight + App Store distributions ALWAYS use production-environment attestation regardless of entitlement value | Common Pitfalls §Pitfall 3 | If Apple changes this routing (e.g., allows TestFlight → development), dev-team process for Phase 4 shipping becomes different; this is the officially-documented behavior and is stable. |

**If user disagrees with any assumption here:** surface during Phase 4 plan-discuss to convert the item into an explicit decision in 04-CONTEXT.md before planning proceeds.

## Open Questions

1. **Exact backend error code strings for re-attestation triggers (D-04).**
   - What we know: D-04 says "backend error codes `attestationInvalid` / `nonceExpired` / `keyCompromised`" but this is notional.
   - What's unclear: The wire-format field name (top-level `error_code`? nested `detail.code`?) and exact string values.
   - Recommendation: Client ships with a generic `AttestationError.underlying(code: String)` case + a named case for the three canonical triggers. Coordinate with backend team during Phase 4 plan execution (first plan task); update mapping once confirmed.

2. **Telemetry format for attestationStatus distribution.**
   - What we know: `attestationStatus` is an enum value on the wire; the client will emit a structured log event for each `/device/register` call.
   - What's unclear: Whether the Logger's current `LogField` vocabulary has a "status code" concept, or whether Phase 4 needs to add one.
   - Recommendation: Phase 4 plan surveys `LogField` existing cases; if no suitable case exists, extend with `case status(String)` minimally. Preserve GEO-03 discipline: NEVER emit raw `attestationObject` bytes.

3. **Banner copy approval.**
   - What we know: D-11 text is "Limited trust mode — this device can't fully verify. Some features may be restricted."
   - What's unclear: Product-team final-copy approval (the CONTEXT version is "planner-finalize" territory per D-14 phase-3 pattern).
   - Recommendation: Proceed with the copy as written; leave a task for copy-review with PM before M5.

4. **Is there a "re-bind device" path beyond Face-ID re-enrollment?**
   - What we know: Phase 3's `.biometricReEnrolled` → logout placeholder covers the biometric case.
   - What's unclear: If backend says `keyCompromised` (D-04 trigger), is that the same "re-bind" UI as Face ID re-enrollment? Or a different path?
   - Recommendation: Phase 4 plan should treat `keyCompromised` as a silent `attestedKeyId` regeneration on the next `/device/register` — user-invisible. No new UI. Document this explicitly in ADR 0005.

5. **Does the heartbeat need to run during BiometricLockViewController display?**
   - What we know: On cold-boot, SessionLockService presents `BiometricLockViewController` over the role shell (Phase 3 Plan 13).
   - What's unclear: Should the 24h heartbeat fire BEFORE or AFTER biometric unlock? Firing before: user sees zero network activity. Firing after: loses ~5 seconds of user-friction-blocked validation.
   - Recommendation: Fire heartbeat AFTER biometric unlock — semantically the "session is alive" signal should follow "the user is present." Documented in Code Example §Common Operation 1 via the `await` placement.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Phase 4 dev + CI | ✓ | 26.4 (dev) / 16.4 (CI per docs/ci.md) | — |
| iOS 17 SDK | `DCAppAttestService` (iOS 14+) | ✓ | part of Xcode 16.4 + Xcode 26.4 | — |
| `DeviceCheck.framework` | App Attest | ✓ | iOS SDK built-in | — |
| `LocalAuthentication.framework` | Phase 3 biometric reuse | ✓ | iOS SDK built-in | — |
| `Security.framework` | Phase 2 Keychain + SE | ✓ | iOS SDK built-in | — |
| `CryptoKit.framework` | SHA-256(challenge) | ✓ | iOS SDK built-in | — |
| Self-hosted macOS runner with attached iPhone | Device CI | ✓ | already configured Phase 1 | — |
| `secrets.DEVICE_UDID` GitHub secret | Device CI | ✓ | per docs/ci.md | — |
| Apple Developer App Attest capability on the app's Bundle ID | Real-device attestation | ? | dev-team process, not in repo | Phase 4 D-09 graceful-skip (attestationStatus = `entitlementMissing` if not enabled) |
| Apple Developer portal — provisioning profile with App Attest entitlement | Real-device attestation | ? | dev-team process, not in repo | Same as above — graceful-skip |
| Slack webhook for flaky-pass notifications | D-15 flaky alerting | ? | dev-team process | Phase 4 plan uses `SLACK_WEBHOOK_URL` secret; if not configured, the notification step is best-effort (use `|| true` so it doesn't fail the job) |

**Missing dependencies with no fallback:**
- None — every required framework/tool is available. The only "?" items are Apple Developer portal capabilities that are dev-team coordination, not plan-blocker.

**Missing dependencies with fallback:**
- App Attest entitlement provisioning: if not done by dev-team by Phase 4 execution time, `DCAppAttestService.generateKey()` returns `featureUnsupported` and D-09 routes to `attestationStatus: "entitlementMissing"` path — the app still works, just in the software-only trust tier. Backend records the status and prompts dev-team to fix provisioning.
- Slack webhook: if the webhook secret is missing, the flaky-pass notification step logs a warning but doesn't fail the job. Engineers miss flaky-pass visibility but merge-gate still works.

## Validation Architecture

> `workflow.nyquist_validation` is enabled (absent from config = enabled). `[VERIFIED: .planning/config.json — `nyquist_validation: true`]`

### Test Framework
| Property | Value |
|----------|-------|
| Framework (unit) | Swift Testing (`@Suite`, `@Test`) — STACK-03 verified |
| Framework (UI) | XCTest / XCUITest |
| Config file | `validationLedger.xcodeproj/project.pbxproj` — test targets registered as `validationLedgerTests`, `validationLedgerUITests`, `validationLedgerDeviceTests` |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -parallel-testing-enabled NO -only-testing:validationLedgerTests/Attestation` |
| Full suite command (simulator) | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -parallel-testing-enabled NO -only-testing:validationLedgerTests -only-testing:validationLedgerUITests/RoleShellSmokeTests` |
| Full suite command (device) | `xcodebuild test -scheme validationLedger -destination "platform=iOS,id=$DEVICE_UDID" -only-testing:validationLedgerDeviceTests -retry-tests-on-failure -test-iterations 2` |

### Phase Requirements → Test Map

Every decision D-01..D-16 and every requirement (DEV-04, CI-03) has at least one validation path. Items marked HUMAN-UAT are legitimately device-only or product-approval concerns.

| ID | Behavior | Test Type | Automated Command / Location | File Exists? |
|----|----------|-----------|------------------------------|-------------|
| **DEV-04** | App Attest attestation included in /device/register; gracefully skipped when unavailable | integration | `validationLedgerTests/Attestation/AttestationServiceTests.swift` + `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` | ❌ Wave 0 |
| **CI-03** | Physical-device pipeline runs SE + biometric + App Attest tests on every merge to `main` + blocks merge on failure | device CI + human gate | `.github/workflows/ci-device.yml` push trigger + required-status-check config | ⚠️ Partial — yml exists but must be upgraded in Wave 1 |
| **D-01** | `generateKey()` called exactly ONCE per install; subsequent registers reuse persisted `attestedKeyId` | unit | `validationLedgerTests/Attestation/GenerateKeyOnlyOnceTest.swift` — invokes `/device/register` flow twice with a spy `DCAppAttestService`, asserts `generateKey` spy counter == 1 | ❌ Wave 0 |
| **D-02** | /device/register payload shape contains three distinct keys (deviceKey SPKI, authorizationKey SPKI, attestedKeyId+attestationObject) + attestationStatus | integration | `validationLedgerTests/Networking/DeviceRegisterEndpointTests.swift` — assert Encode() produces wire format with all three keys + status enum | ❌ Wave 0 |
| **D-03** | `attestedKeyId` preserved across logout; `KeychainScope.session.contains(.attestedKeyId) == false` | unit | `validationLedgerTests/Storage/KeychainScopeTests.swift::testAttestedKeyIdNotInSessionScope` | ❌ Wave 0 |
| **D-04** | Re-attestation is backend-driven only — client never self-rotates on schedule; `clearPersistedKeyId()` callable by DEBUG-only dev-menu + by response-interceptor on `attestationInvalid` error code | integration + DEBUG dev-menu HUMAN | `validationLedgerTests/Attestation/BackendDrivenReattestationTest.swift` — feeds a mock `{ error_code: "attestationInvalid" }` response, asserts `attestedKeyId` Keychain entry deleted + next /device/register calls `generateKey` again. Dev-menu button is HUMAN-UAT (tap → observe). | ❌ Wave 0 |
| **D-05** | `GET /device/challenge` endpoint: response shape `{ challenge, expiresAt, nonce }`; called immediately before attestKey/generateAssertion | unit | `validationLedgerTests/Networking/DeviceChallengeEndpointTests.swift` — MockURLProtocol fixture round-trip | ❌ Wave 0 |
| **D-06** | `clientDataHash = SHA-256(challenge)` exactly — no body binding | unit | `validationLedgerTests/Attestation/ClientDataHashTest.swift` — pass a fixed challenge, assert `SHA256.hash(data: challenge)` output matches exactly what's sent to `DCAppAttestService.attestKey` spy | ❌ Wave 0 |
| **D-07a** | `attestKey()` fires once on first `/device/register` (registration proof) | unit | Subsumed by D-01 test | — |
| **D-07b** | `generateAssertion()` fires on cold-boot re-login (piggybacking `SessionRestoreProbe.restored`) | unit + integration | `validationLedgerTests/Attestation/ColdBootHeartbeatTest.swift` — seed Keychain with restored-session values; instantiate SessionRestoreProbe; assert heartbeat path is called. Validation that cold-boot heartbeat is ACTUALLY POSTED is HUMAN-UAT on device (observe network traffic) | ❌ Wave 0 |
| **D-07c** | `didBecomeActive` fires warm foreground + `lastHeartbeatAt > 24h ago` triggers heartbeat | unit | `validationLedgerTests/Attestation/HeartbeatAgeThresholdTest.swift` — inject mock clock + mock lastHeartbeatAt; assert `shouldHeartbeat(now:)` returns true/false around the 24h boundary | ❌ Wave 0 |
| **D-07d** | heartbeat POSTs to `/device/heartbeat` with `{ sessionToken, attestedKeyId, assertion }` | integration | `validationLedgerTests/Networking/DeviceHeartbeatEndpointTests.swift` — MockURLProtocol fixture round-trip | ❌ Wave 0 |
| **D-08** | Challenge single-use; on `challengeExpired` error, refetch + retry exactly ONCE | integration | `validationLedgerTests/Attestation/ChallengeExpiredRetryTest.swift` — seed MockURLProtocol with 1st-call-fails (`challengeExpired`) + 2nd-call-succeeds; assert client refetches challenge + submits again (and does NOT retry a 3rd time on second failure) | ❌ Wave 0 |
| **D-09a** | `attestationStatus = "unsupported"` when `DCAppAttestService.isSupported == false` | unit | `validationLedgerTests/Attestation/AttestationStatusUnsupportedTest.swift` — inject fake service with `isSupported = false`, assert status enum | ❌ Wave 0 |
| **D-09b** | `attestationStatus = "entitlementMissing"` when `DCError.featureUnsupported` returned | unit | `AttestationStatusEntitlementMissingTest.swift` — fake service throws `DCError.featureUnsupported` | ❌ Wave 0 |
| **D-09c** | `attestationStatus = "quotaExceeded"` when `DCError.serverUnavailable` returned | unit | `AttestationStatusQuotaExceededTest.swift` | ❌ Wave 0 |
| **D-09d** | `attestationStatus = "simulatorBypass"` under `#if DEBUG && targetEnvironment(simulator)` | unit | `AttestationStatusSimulatorBypassTest.swift` — only runs on simulator target, asserts `SimulatorBypassAttestationService.generateKeyIfNeeded()` returns `.simulatorBypass` | ❌ Wave 0 |
| **D-09e** | `attestationStatus = "error"` for `invalidKey`, `invalidInput`, `unknownSystemFailure` | unit | `AttestationStatusErrorTest.swift` — parameterized across three DCError codes | ❌ Wave 0 |
| **D-09f** | When `attestationStatus != "attested"`, `attestationObject` + `attestedKeyId` omitted from /device/register payload | unit | `DeviceRegisterEndpointOmissionTest.swift` — parameterized across 5 non-attested statuses, assert JSON lacks both keys | ❌ Wave 0 |
| **D-10** | Simulator bypass emits fake `attestationObject` + `attestedKeyId = sim-bypass-{installUUID}`; `trustTier = softwareOnly`; production builds compile-out | unit | `validationLedgerTests/Attestation/SimulatorBypassTest.swift` (runs only on simulator). Production compile-out verified by `Release-strings` grep in Phase 4 plan verification (mirrors Phase 1 LogViewer Release-strings check). | ❌ Wave 0 |
| **D-11** | Non-dismissible "Limited trust mode" banner on role shell when `trustTier != "hardwareAttested"` | UI smoke + HUMAN | `validationLedgerUITests/LimitedTrustBannerTests.swift` — drive OTP flow with mock `/device/register` returning `trustTier: "softwareOnly"`, assert banner visible. + HUMAN-UAT: visual inspection on iPad landscape. | ❌ Wave 0 (UI test); HUMAN-UAT also pending |
| **D-12** | `/device/register` + `/device/heartbeat` return `trustTier`; client stores in `AppContainer.session.trustTier` | integration | `DeviceRegisterTrustTierTest.swift` + `DeviceHeartbeatTrustTierTest.swift` — assert `session.trustTier` mutated by response | ❌ Wave 0 |
| **D-13** | Device pipeline runs full security surface — SE keygen + Keychain biometric + App Attest + logout ACL clearing | device CI | `validationLedgerDeviceTests/` — 5 suites: SecureEnclaveKeyStoreTests (exists), SecureEnclaveSmokeTests (exists), KeychainBiometricACLTests (NEW), AppAttestRoundTripTests (NEW), LogoutClearsAuthorizationKeyTests (NEW). Invoked by `ci-device.yml`. | ⚠️ Partial — 2 exist, 3 new |
| **D-14** | Biometric-prompt tests use seeded `LAContext` — no real Face ID prompt in unattended CI | device CI | `validationLedgerDeviceTests/SeededLAContext.swift` + `KeychainBiometricACLTests.swift` uses `SeededBiometricService`. Assertion: tests complete in <60s (real Face ID would time-out the unattended runner) | ❌ Wave 0 |
| **D-15** | Retry once, then fail; flaky-pass logged to Slack | CI-gate + HUMAN | `ci-device.yml` uses `-retry-tests-on-failure -test-iterations 2`. Verified by a deliberate test that fails first-run-only (e.g., a count-down flag in UserDefaults) — assert pipeline is GREEN + flaky-pass annotation surfaces. Slack notification is HUMAN-UAT (observe Slack channel). | ❌ Wave 0 |
| **D-16** | Device pipeline is required GitHub branch-protection status check on `main`; red pipeline blocks merge | CI-gate + HUMAN | First-run test (HUMAN): open a PR that deliberately breaks a device test; attempt to merge; confirm merge is blocked. Automated re-verification: PR template includes a "CI device status: green" checklist. | HUMAN only (config is external to codebase) |

### Sampling Rate
- **Per task commit:** `xcodebuild test -only-testing:validationLedgerTests/Attestation` — runs just Phase 4 unit tests in <30s on simulator.
- **Per wave merge:** Full simulator suite (`xcodebuild test -only-testing:validationLedgerTests -only-testing:validationLedgerUITests/RoleShellSmokeTests -only-testing:validationLedgerUITests/LimitedTrustBannerTests`) — covers D-01, D-02, D-03, D-04, D-05, D-06, D-07a/c/d, D-08, D-09a-f, D-10 (simulator side), D-11, D-12.
- **Phase gate:** Full device suite via ci-device.yml (`validationLedgerDeviceTests` with retry) + required-status-check green on the final merge PR — covers D-13, D-14, D-15, D-16, plus device-side confirmation of DEV-04 behavior.

### Wave 0 Gaps

Every file below is new (or new-behavior on existing files). Phase 4 plans must land these in the first wave before any production code.

- [ ] `validationLedger/Core/Attestation/AttestationService.swift` — protocol + errors + status enum + trustTier enum (stubs to compile)
- [ ] `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` — production impl skeleton (for test injection)
- [ ] `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` — DEBUG-simulator impl (required for Phase 4 test fixtures)
- [ ] `validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift`
- [ ] `validationLedger/Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift`
- [ ] `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — add `.attestedKeyId`, `.lastHeartbeatAt` constants
- [ ] `validationLedgerTests/Networking/Fixtures/device-challenge-success.json`
- [ ] `validationLedgerTests/Networking/Fixtures/device-heartbeat-success.json`
- [ ] `validationLedgerTests/Networking/Fixtures/device-heartbeat-attestation-invalid.json`
- [ ] `validationLedgerTests/Networking/Fixtures/device-register-software-only.json`
- [ ] `validationLedgerTests/Attestation/` — new test folder with 12+ Swift Testing suites per the D-* validation map
- [ ] `validationLedgerDeviceTests/SeededLAContext.swift`
- [ ] `validationLedgerDeviceTests/AppAttestRoundTripTests.swift`
- [ ] `validationLedgerDeviceTests/KeychainBiometricACLTests.swift`
- [ ] `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift`
- [ ] `validationLedger/validationLedger.entitlements` — `com.apple.developer.devicecheck.appattest-environment` = `development`
- [ ] `docs/adr/0005-three-key-device-register-payload.md`
- [ ] `.github/workflows/ci-device.yml` — UPGRADE for full suite + retry + expanded paths filter
- [ ] `scripts/report-flaky-passes.sh` — Phase 4-new script for D-15 Slack notification
- [ ] No framework install needed — Apple frameworks already in iOS 17 SDK

## Security Domain

> `security_enforcement` is enabled (absent from config = enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | App Attest hardware attestation binds a cryptographic proof to an unmodified copy of this app on a real iPhone; this supplements (not replaces) Phase 3's OTP + session token. Standard control: Apple's `DCAppAttestService` + server-side attestation verification. |
| V3 Session Management | yes | The heartbeat (D-07) extends session validity; failed heartbeat surfaces as 401 → existing `Auth401ResponseInterceptor` logout. Standard control: HTTPS + sessionToken + Apple-rooted attestation. |
| V4 Access Control | yes | Backend uses `trustTier` (D-12) to decide feature access. Standard control: enforce on backend; client is a passive renderer. |
| V5 Input Validation | yes | Challenge response MUST be base64-validated client-side before SHA-256 hashing; response bodies validated via `Decodable` structural check; unrecognized `attestationStatus` enum values caught by `@unknown default`. Standard control: Swift `Decodable` + compile-time enum exhaustiveness. |
| V6 Cryptography | yes | SHA-256 via `CryptoKit.SHA256` (Apple-provided); ECDSA over P-256 via Apple's `DCAppAttestService` (opaque, managed by framework). NEVER hand-roll hashing or signing. Standard control: `CryptoKit` only. |
| V7 Error Handling | yes | DCError codes mapped to `AttestationStatus` enum for server; internal errors scrubbed of PII before `Logger.error` per FOUND-01. |
| V9 Communications | yes (existing) | Phase 2 cert-pinning (SEC-01) still active on `.live` URLSession; new endpoints use same URLSession. Standard control: PinningSessionDelegate. |

### Known Threat Patterns for iOS client + Apple App Attest

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Reverse-engineered/modified client impersonates legitimate app | Spoofing | App Attest (Phase 4 core goal) — impossible without Apple's signing keys |
| Keychain item exfiltrated from jailbroken device (`attestedKeyId`) | Information Disclosure | `attestedKeyId` alone is useless without the SE-held private key that `DCAppAttestService` refuses to expose; standard control is Apple's SE + ACL |
| Replay of old `attestationObject` | Spoofing / Tampering | Server-side counter tracking + single-use challenge (D-08 client side + backend counter) |
| Man-in-the-middle intercepts challenge + forges assertion | Tampering | TLS with pinned leaf (SEC-01) + challenge TTL ≤60s (D-08) |
| Attacker burns our App Attest quota by repeatedly installing + calling generateKey | Denial of Service | D-01 once-per-install discipline + Apple's per-device throttling (indirectly helpful) + backend rate-limits `/device/register` per-IP |
| Stale session token with valid attestation passes heartbeat on server-dead session | Elevation of Privilege | 401 response triggers Phase 3 `Auth401ResponseInterceptor` → logout. Pitfall 6 covers this. |
| Fake Apple distribution certificate / sideload | Spoofing | App Attest's server-side verification against Apple's root attestation public keys rejects any non-Apple-signed attestation; we don't build this defense, Apple does |
| Logging attestation blob bytes to crash report / analytics | Information Disclosure | Type-level discipline — `Logger.LogField` accepts status enum value only, not `Data`; FOUND-01 PII scrubber catches anything else |

## Sources

### Primary (HIGH confidence)

- Apple Developer — [DCAppAttestService](https://developer.apple.com/documentation/devicecheck/dcappattestservice) — API surface, isSupported, generateKey/attestKey/generateAssertion signatures
- Apple Developer — [DCAppAttestService.attestKey(_:clientDataHash:completionHandler:)](https://developer.apple.com/documentation/devicecheck/dcappattestservice/attestkey(_:clientdatahash:completionhandler:))
- Apple Developer — [DCAppAttestService.generateAssertion(_:clientDataHash:completionHandler:)](https://developer.apple.com/documentation/devicecheck/dcappattestservice/generateassertion(_:clientdatahash:completionhandler:))
- Apple Developer — [DCAppAttestService.isSupported](https://developer.apple.com/documentation/devicecheck/dcappattestservice/issupported) — returns false on simulator + app extensions
- Apple Developer — [DCError.Code.serverUnavailable](https://developer.apple.com/documentation/devicecheck/dcerror-swift.struct/code/serverunavailable)
- Apple Developer — [DCError.Code.invalidKey](https://developer.apple.com/documentation/devicecheck/dcerror-swift.struct/code/invalidkey)
- Apple Developer — [App Attest Environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment) — values `development` / `production`; TestFlight + App Store always use `production`
- Apple Developer — [Preparing to use the App Attest service](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service)
- Apple Developer WWDC21 — [Mitigate fraud with App Attest and DeviceCheck (10244)](https://developer.apple.com/videos/play/wwdc2021/10244/)
- Apple Developer WWDC21 — [Diagnose unreliable code with test repetitions (10296)](https://developer.apple.com/videos/play/wwdc2021/10296/) — `-retry-tests-on-failure` introduction
- `.planning/phases/02-networking-contract-device-keys/02-CONTEXT.md` — DEV-01/02/03/05 two-key SE pattern decisions `[VERIFIED]` (file read during research)
- `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-CONTEXT.md` — SessionRestoreProbe, AppContainer DI surface `[VERIFIED]`
- `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-VERIFICATION.md` — Phase 3 HUMAN-UAT items status `[VERIFIED]`
- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — existing endpoint + line 5 comment explicitly anticipating Phase 4 attestation extension `[VERIFIED]`
- `validationLedger/App/AppContainer.swift` — initializer-DI pattern, `preflightSecureEnclave` template `[VERIFIED]`
- `validationLedger/App/SceneDelegate.swift` — cold-boot routing, didBecomeActive observer `[VERIFIED]`
- `validationLedger/Core/Auth/BiometricService.swift` — LAContext wrapper pattern to mirror `[VERIFIED]`
- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — two-key Keyslot enum + protocol pattern `[VERIFIED]`
- `.github/workflows/ci-device.yml` — existing self-hosted runner + push + PR paths config `[VERIFIED]`
- `.github/workflows/ci-simulator.yml` — reference xcodebuild invocation + artifact upload patterns `[VERIFIED]`
- `docs/ci.md` — CI policy doc `[VERIFIED]`
- `docs/adr/0004-secure-enclave-two-key-pattern.md` — prior ADR to reference for ADR 0005 `[VERIFIED]`
- `Package.swift` — iOS 17 deployment + dependency allowlist `[VERIFIED]`
- `.planning/config.json` — workflow.nyquist_validation + security posture `[VERIFIED]`

### Secondary (MEDIUM confidence — WebSearch verified with community reputation)

- [adjoe.io engineer blog — Apple DeviceCheck & App Attest: Prevent Fraud on iOS](https://adjoe.io/company/engineer-blog/prevent-fraud-on-ios-with-apple-devicecheck-and-app-attest/) — `clientDataHash = Data(SHA256.hash(data: challenge))` pattern; per-method error lists
- [Apple Developer Forums thread 821283 — Production-Grade Implementation Guidance: DCError](https://developer.apple.com/forums/thread/821283) — community-open question confirming official documentation gap (no official per-method error taxonomy)
- [Apple Developer Forums thread 759285 — App Attest / Device Check Quota and Limits](https://developer.apple.com/forums/thread/759285)
- [Apple Developer Forums thread 722988 — DeviceCheck App Attest API throttling](https://developer.apple.com/forums/thread/722988)
- [approov.io — Exposing the Shortcomings of Apple DeviceCheck and Apple App Attest](https://approov.io/blog/limitations-of-apple-devicecheck-and-apple-app-attest) — undocumented quota, recommended gradual rollout
- [guardsquare.com — Remove the Constraints of iOS App Attest and DeviceCheck](https://www.guardsquare.com/blog/remove-constraints-of-ios-app-attest)
- [avanderlee.com — Flaky tests resolving using Test Repetitions in Xcode](https://www.avanderlee.com/debugging/flaky-tests-test-repetitions/) — `-retry-tests-on-failure -test-iterations N` syntax
- [GitHub docs — Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule)
- [GitHub Community Discussion #167194 — No available status checks for branch protections](https://github.com/orgs/community/discussions/167194) — confirms the first-run chicken-and-egg behavior
- [GitHub Community Discussion #54877 — Branch protections when actions use paths-ignore](https://github.com/orgs/community/discussions/54877)
- [medium — iOS App Attest + DeviceCheck by Wesley Matlock](https://medium.com/@wesleymatlock/%EF%B8%8F-ios-app-attest-devicecheck-building-real-trust-into-your-app-without-losing-your-mind-c98bc39eb142)
- [navoshta.com — Unit tests for Touch ID](https://navoshta.com/unit-tests-for-touch-id/) — seeded-LAContext subclassing pattern
- [OWASP MASTG — Local Authentication on iOS](https://mobile-security.gitbook.io/mobile-security-testing-guide/ios-testing-guide/0x06f-testing-local-authentication) — industry guidance on biometric testing discipline

### Tertiary (LOW confidence — reference only)

- [DEV Community — Implementing Apple's Device Check App Attest Protocol](https://dev.to/mnelsonwhite/implementing-apples-device-check-app-attest-protocol-4p2g)
- [Restless Labs — Determine iOS App Authenticity Using Apple App Attest](https://blog.restlesslabs.com/john/ios-app-attest)
- [AppleInsider — How to mitigate fraud on iOS devices using App Attest and DeviceCheck](https://appleinsider.com/articles/24/07/09/how-to-mitigate-fraud-on-ios-devices-using-app-attest-and-devicecheck)
- [GitHub iansampson/AppAttest](https://github.com/iansampson/AppAttest) — server-side Swift reference implementation for App Attest verification
- [GitHub veehaitch/devicecheck-appattest](https://github.com/veehaitch/devicecheck-appattest) — Kotlin server-side reference

## Metadata

**Confidence breakdown:**
- Apple DCAppAttestService API surface: **HIGH** — verified against official Apple docs + cross-referenced with three independent engineering blogs + Apple forums.
- Client-side implementation patterns (`AttestationService` protocol, simulator bypass): **HIGH** — mirrors Phase 2 patterns that are already in the codebase (verified by file reads).
- App Attest rate-limit behavior: **MEDIUM** — Apple has not published quota values or a dedicated error code; community consensus is that `serverUnavailable` is the primary surface but not guaranteed. CONTEXT D-09's `quotaExceeded` mapping is correctly calibrated.
- Backend error codes for re-attestation triggers (D-04): **LOW** — notional only; requires backend coordination during Phase 4 execution (Assumption A3, Open Question 1).
- GitHub Actions CI YAML + required-status-check: **HIGH** — verified against official GitHub docs + existing repo workflow files.
- `xcodebuild -retry-tests-on-failure`: **HIGH** — Apple WWDC21 session + stable Xcode 13+ feature; unchanged in Xcode 16.
- Seeded LAContext pattern: **HIGH** — industry-standard iOS testing approach; `BiometricService` protocol already exists.
- Banner integration point into role-shell UITabBarController: **MEDIUM** — assumed integration via `RoleCoordinator.wrapTabsWithNavAndInstallAvatar`; needs code-read during plan authorship to confirm exact composition.
- App Attest entitlement TestFlight/App Store behavior: **HIGH** — documented by Apple that the entitlement value is ignored in TF/App Store distributions.

**Research date:** 2026-04-22
**Valid until:** 2026-05-22 (30 days — Apple framework surface is stable; re-verify quota behavior + GitHub branch-protection UI flow during execution)

---

*Research complete. Ready for `gsd-planner`.*
