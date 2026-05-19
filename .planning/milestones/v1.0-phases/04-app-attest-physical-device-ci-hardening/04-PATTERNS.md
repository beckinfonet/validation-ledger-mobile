# Phase 4: App Attest & Physical-Device CI Hardening — Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 23 (new / modified / extended)
**Analogs found:** 22 / 23 (entitlements file is greenfield with no in-repo analog)

> **How to read this doc:** For each file to be created or modified, the planner looks up (a) **Closest Analog** — the existing file to copy the shape, naming, and header-comment style from, (b) **Code Excerpt** — the concrete lines that define the pattern to mirror, and (c) **Deltas** — how the new file differs from the analog. Excerpts are verbatim; line numbers are stable as of commit `7678a34`.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Attestation/AttestationService.swift` (NEW) | protocol + error + status enum | service | `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` | exact (protocol + error-enum + shared-type-for-dual-impl) |
| `validationLedger/Core/Attestation/AttestationError.swift` (NEW) | error enum | type-only | `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` `KeyStoreError` | exact (`@Sendable` error enum with associated NSError case) |
| `validationLedger/Core/Attestation/AttestationStatus.swift` (NEW) | enum | type-only | Inline `LogoutReason` (`validationLedger/Core/Auth/LogoutService.swift` lines 21-25) | exact (`String` raw-value + `Sendable`) |
| `validationLedger/Core/Attestation/TrustTier.swift` (NEW) | enum (wire-compat) | type-only | `validationLedger/Roles/Role.swift` + `LogoutReason` | exact |
| `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` (NEW) | service (production impl) | request-response (async) | `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | exact (production impl of dual-impl protocol) |
| `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` (NEW) | service (simulator impl, `#if DEBUG && targetEnvironment(simulator)`) | request-response (async) | `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | exact (simulator impl of dual-impl protocol) |
| `validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` (NEW) | endpoint (GET) | request-response | `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` | exact (GET with `EmptyBody` sentinel + snake_case CodingKeys) |
| `validationLedger/Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift` (NEW) | endpoint (POST) | request-response | `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` | exact (POST with RequestBody + Response nested structs) |
| `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` (EXTENDED) | endpoint (POST) | request-response | Self (prior Phase 2 shape) | direct in-place extension — file comment at line 5 explicitly anticipates |
| `validationLedger/Core/Storage/Keychain/KeychainKey.swift` (EXTENDED) | constants | type-only | Self (existing constants lines 10-21) | direct in-place extension |
| `validationLedger/Core/Storage/Keychain/KeychainScope.swift` (EXTENDED) | scope predicate | type-only | Self (existing `.session` case) | direct — but note D-03 says `.attestedKeyId` + `.lastHeartbeatAt` MUST NOT be in `.session` |
| `validationLedger/App/AppContainer.swift` (EXTENDED) | composition-root DI | config | Self (existing `preflightSecureEnclave(...)` lines 303-327) | exact — mirror `preflightAttestationEntitlement(...)` |
| `validationLedger/App/SceneDelegate.swift` (EXTENDED) | UIKit scene lifecycle | event-driven | Self (existing `handleDidBecomeActive()` lines 371-376 + `.restored` branch lines 183-193) | exact — third responsibility in didBecomeActive + new `performHeartbeatIfNeeded` helper alongside `presentBiometricLockIfNeeded` |
| `validationLedger/UI/LimitedTrustBannerView.swift` (NEW) | UIKit view | UI | *No direct analog* — but `validationLedger/Roles/RoleCoordinator.swift` `wrapTabsWithNavAndInstallAvatar` is the composition wrapper that inserts it | role-match (UIKit + shared across 5 roles) |
| `validationLedger/Roles/RoleCoordinator.swift` (EXTENDED) | coordinator extension | UI composition | Self (existing `wrapTabsWithNavAndInstallAvatar` lines 45-67) | exact — add sibling `wrapWithLimitedTrustBanner(trustTier:)` extension |
| `validationLedger/App/DevMenu/DevMenuViewController.swift` (EXTENDED) | DEBUG table row | UI | Self (existing `Row` enum + `didSelectRowAt` lines 19-108) | exact — add `.reattestNow` case |
| `validationLedger/validationLedger.entitlements` (NEW) | Xcode entitlements plist | config | *No analog in repo* — new file | — |
| `.github/workflows/ci-device.yml` (UPGRADED) | CI workflow | CI | Self + `.github/workflows/ci-simulator.yml` | direct in-place upgrade |
| `scripts/report-flaky-passes.sh` (NEW) | shell script | CI helper | *No analog in repo* (first shell script in this project) | — (use plain POSIX sh) |
| `docs/attestation-rotation.md` (NEW) | runbook | docs | `docs/cert-rotation.md` | exact (same "Why ... Is Not Optional" + procedures + Emergency Revoke structure) |
| `docs/adr/0005-three-key-device-register-payload.md` (NEW) | ADR | docs | `docs/adr/0004-secure-enclave-two-key-pattern.md` | exact (same 6-section structure; Phase 4 extends Phase 2 two-key story) |
| `validationLedgerTests/Networking/Fixtures/device-challenge-success.json` (NEW) | JSON fixture | data | `validationLedgerTests/Networking/Fixtures/device-register-success.json` | exact (snake_case, flat, ISO8601 dates) |
| `validationLedgerTests/Networking/Fixtures/device-heartbeat-success.json` (NEW) | JSON fixture | data | Same | exact |
| `validationLedgerTests/Networking/Fixtures/device-heartbeat-attestation-invalid.json` (NEW) | JSON fixture (error) | data | `validationLedgerTests/Networking/Fixtures/device-register-failure.json` | exact |
| `validationLedgerTests/Networking/Fixtures/device-register-software-only.json` (NEW) | JSON fixture | data | `validationLedgerTests/Networking/Fixtures/device-register-success.json` | exact |
| `validationLedgerTests/Attestation/*.swift` (NEW folder — 12+ suites) | Swift Testing suites | test | `validationLedgerTests/Networking/EndpointEncodingTests.swift` | exact (Swift Testing + `@Suite` + `@Test` + fixture-loader) |
| `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` (NEW) | device integration test | test | `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` | exact (device-only target; defer-block Keychain purge; accept-either-outcome on CI) |
| `validationLedgerDeviceTests/KeychainBiometricACLTests.swift` (NEW) | device integration test | test | `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` | exact (adds seeded `LAContext` injection) |
| `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift` (NEW) | device integration test | test | `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` | exact |
| `validationLedgerDeviceTests/SeededLAContext.swift` (NEW) | test helper (SeededBiometricService) | test fixture | `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` `StubLocationProviderForUITest` | role-match (protocol-conforming stub that returns deterministic values) |

---

## Pattern Assignments

### 1. `Core/Attestation/AttestationService.swift` — protocol + error + status

**Analog:** `validationLedger/Core/KeyStore/KeyStoreProtocol.swift`

**Header-comment pattern** (KeyStoreProtocol.swift lines 1-10) — mirror the "two impls" summary + AppContainer-selection + later-phase-extension notes:

```swift
// validationLedger/Core/KeyStore/KeyStoreProtocol.swift
// Protocol for device-bound signing keys. Implementations:
//   - SoftwareKeyStore: simulator + DEBUG only
//   - SecureEnclaveKeyStore: production device (Phase 2 Plan 06 fills in)
// AppContainer selects via #if DEBUG && targetEnvironment(simulator).
//
// Phase 2 Plan 06 extends with:
//   - generateDeviceIdentityKeys()  — DEV-01 / DEV-02 (two-key pattern)
//   - signWithAuthorization(_:)     — DEV-02 biometric-gated signing
```

**Error-enum pattern** (KeyStoreProtocol.swift lines 14-20) — `Error, Sendable` enum with associated NSError/CFError cases:

```swift
public enum KeyStoreError: Error, Sendable {
    case notImplemented
    case signingFailed
    case keyUnavailable
    case keyGenerationFailed(CFError?)  // Phase 2 Plan 06 addition (DEV-01/DEV-02)
    case keyDeletionFailed(OSStatus)    // Phase 3 Plan 04 addition (SESS-04/D-16)
}
```

**Shared-type pattern** (KeyStoreProtocol.swift lines 36-39) — Keyslot is the top-level shared type between the two impls. `AttestationStatus` + `TrustTier` play the same role:

```swift
public enum Keyslot: Sendable {
    case device
    case authorization
}
```

**Protocol pattern** (KeyStoreProtocol.swift lines 41-76):

```swift
public protocol KeyStoreProtocol: AnyObject, Sendable {
    /// Sign with the device-identity key (`deviceKey`). Passcode-only ACL — no biometric prompt.
    func sign(_ data: Data) throws -> Data

    /// Public key bytes for the device-identity key (base64-encodable by caller).
    func publicKeyRepresentation() throws -> Data

    /// DEV-01 / DEV-02: generate the two identity keypairs in a single call.
    ...
    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data)

    ...
    func signWithAuthorization(_ data: Data, context: LAContext?) throws -> Data

    /// Phase 3 SESS-04 / D-16: delete the key in the given slot from persistent storage.
    ...
    func deleteKey(slot: Keyslot) throws
}
```

**Deltas:**
- Methods are `async throws` (not plain `throws`) because `DCAppAttestService` is async. Mirror RESEARCH Pattern 1 line 308-321.
- Protocol is `AnyObject, Sendable` (same as `KeyStoreProtocol`).
- `AttestationStatus` is a `String` raw-value enum (matches wire format per D-09) — add `Codable` beyond `Sendable`.
- `AttestationError` uses `underlying(NSError)` for `DCError.errorDomain` cases; other cases are atomic enum values.
- Add header doc-comment to each protocol method quoting the decision ID (D-01, D-05, D-06, D-07, D-04) in the same style KeyStoreProtocol uses ("DEV-01 / DEV-02").
- `clearPersistedKeyId()` called ONLY on backend re-attestation (D-04) — NOT on logout (D-03). Document this explicitly in the doc-comment.

---

### 2. `Core/Attestation/DCAppAttestAttestationService.swift` — production impl

**Analog:** `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift`

**Header-comment pattern** (SecureEnclaveKeyStore.swift lines 1-16) — mirror the "simulator vs device" + test-target + Pitfall notes:

```swift
// validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
// DEV-01 + DEV-02 + DEV-03 (production side): Secure-Enclave-backed EC P-256 signing.
//
// Two-key pattern per DEV-02:
//   - deviceKey: [.privateKeyUsage, .devicePasscode]       — device identity, no biometric prompt
//   - authorizationKey: [.privateKeyUsage, .biometryCurrentSet] — sensitive actions, prompts biometric
//                                                             AND invalidates on biometric re-enrollment
//                                                             (Research Pitfall 1 — INTENTIONAL behavior)
//
// Key material NEVER leaves the enclave. Keychain stores only the application-tag reference;
// SecItemCopyMatching returns a SecKey pointer back to the enclave-held key.
//
// Runs on device only. Simulator uses SoftwareKeyStore via AppContainer's
// #if DEBUG && targetEnvironment(simulator) gate. Test membership: validationLedgerDeviceTests/
// (Research Pitfall 2 — simulator has no SE; tests there would silently "pass" without
// exercising this file at all).
```

**Class declaration pattern** (SecureEnclaveKeyStore.swift line 45) — simple `final class`, no `@MainActor` attribute required at class level (individual methods add it if touching LAContext):

```swift
final class SecureEnclaveKeyStore: KeyStoreProtocol {
    init() {}
    // ...
}
```

**Idempotency-guard pattern** (SecureEnclaveKeyStore.swift lines 102-110) — the D-01 "once per install" rule mirrors SE's CR-02 "don't regenerate if one exists":

```swift
private func generateKey(slot: Keyslot) throws -> Data {
    // CR-02 (Phase 2 carryover, closed Phase 3 Plan 02): idempotent guard.
    // If a key already exists for this slot, return its public representation
    // instead of inserting a second key. Without this, a second generateKey(slot:)
    // call silently inserts a new SecKey alongside the old one and loadPrivateKey
    // may return either — breaking pub/priv pairing on the next sign call.
    if let existingPub = try? loadPublicKey(slot: slot) {
        return existingPub
    }
    // ... proceed with SecKeyCreateRandomKey ...
}
```

**Error-mapping pattern** (SecureEnclaveKeyStore.swift lines 116-119) — guard + throw `KeyStoreError.keyGenerationFailed(acError?.takeRetainedValue())`. For DCAppAttest, translate `NSError where err.domain == DCError.errorDomain` → `AttestationStatus` via a `statusForDCError(_:)` helper (see RESEARCH Pattern 1 lines 352-360).

**Deltas:**
- Class is `@MainActor` (per RESEARCH Pattern 1 line 325 — `DCAppAttestService` callbacks arrive on an unspecified queue; mark the service MainActor so `await` hops back).
- Dependencies injected via init: `keychain: KeychainStore`, `logger: any Logger` (SE impl has zero deps; Attestation impl persists `attestedKeyId` via keychain).
- `generateKeyIfNeeded()` reads Keychain FIRST (D-01 discipline) — direct parallel to the `loadPublicKey` idempotent guard above.
- Hash-of-challenge uses `Data(SHA256.hash(data: challenge))` — call site analog is elsewhere; RESEARCH Pattern 1 line 363 has verbatim example.

---

### 3. `Core/Attestation/SimulatorBypassAttestationService.swift` — simulator impl

**Analog:** `validationLedger/Core/KeyStore/SoftwareKeyStore.swift`

**`#if DEBUG && targetEnvironment(simulator)` gate is applied at AppContainer selection site, NOT at file top.** The file itself is NOT gated. But note `SoftwareKeyStore` has **no `#if` wrapper** — it compiles on device too (just unused). RESEARCH Pattern 1 line 374 says the simulator-bypass impl IS wrapped in `#if DEBUG && targetEnvironment(simulator)` at file top — that is a Phase 4 deviation from the SoftwareKeyStore pattern, justified by D-10 ("production builds never ship this code path"). Confirm the tradeoff during planning.

**Header-comment pattern** (SoftwareKeyStore.swift lines 1-10):

```swift
// validationLedger/Core/KeyStore/SoftwareKeyStore.swift
// In-memory P256 keypairs — SIMULATOR + DEBUG ONLY.
// AppContainer's #if DEBUG && targetEnvironment(simulator) branch is the only resolver.
//
// Phase 2 Plan 06 extends Phase 1's single-key impl to the two-key pattern:
//   - devicePrivateKey — Phase 1 "privateKey" renamed; sign(_:) + publicKeyRepresentation route here
//   - authPrivateKey   — authorization-key simulator equivalent; signWithAuthorization routes here
// Simulator does NOT prompt biometric — signWithAuthorization signs directly.
// Biometric semantics are exercised only on device (validationLedgerDeviceTests/SecureEnclaveKeyStoreTests).
```

**Wire-format-matches-device pattern** (SoftwareKeyStore.swift lines 30-33) — simulator must emit wire bytes byte-compatible with the production impl so the backend can't tell them apart at the wire. Same idea applies to D-10's fixed fake `"sim-bypass-attestation-object-v1"` bytes — the mock backend's fixture must accept them verbatim:

```swift
// IN-02 (Phase 2 carryover, closed Phase 3 Plan 02):
// Return DER X9.62 to match SecureEnclaveKeyStore's wire format
// (ecdsaSignatureMessageX962SHA256 — see SecureEnclaveKeyStore.sign(data:slot:)).
// Backend sees identical signature bytes from sim and device.
return signature.derRepresentation
```

**Deltas:**
- `attestedKeyId` format: `"sim-bypass-\(installUUID)"` per D-10. Mock fixture matches on this prefix.
- `attestationObject` is a fixed-content Data blob per D-10 — document "backend test fixture recognizes this verbatim" in the header comment.
- `clearPersistedKeyId()` deletes the Keychain entry — mirrors SoftwareKeyStore's `deleteKey(slot:)` contract of setting to nil.

---

### 4. `Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` — GET endpoint

**Analog:** `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift`

**Full file pattern** (KYCStatusEndpoint.swift lines 1-34) — GET endpoint using `EmptyBody` typealias + snake_case bridge:

```swift
// validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift
// GET /kyc/status — poll overall KYC status + per-artifact status.
// Consumed by Phase 5 KYC-05 (status UI).
// GET endpoint: no body — uses internal EmptyBody sentinel from APIEndpoint.swift.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCStatusEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable {
        ...
        private enum CodingKeys: String, CodingKey {
            case artifactID = "artifactId"
            case status
            case rejectionReason
        }
        ...
    }
    public let path = "/kyc/status"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init() {}
}
```

**Deltas:**
- Path is `/device/challenge`.
- Response: `challenge: String (base64)`, `expiresAt: Date (ISO8601)`, `nonce: String`.
- No CodingKeys bridge needed — all property names are lowercase (no trailing uppercase acronym).
- RESEARCH Pattern 3 lines 429-438 has verbatim shape.

---

### 5. `Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift` — POST endpoint

**Analog:** `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift`

**Full file pattern** (DeviceRegisterEndpoint.swift lines 1-54) — POST endpoint with RequestBody/Response nested structs, explicit CodingKeys for acronym-tail properties, `init(...)` that wraps body:

```swift
// validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
// POST /device/register — register Secure-Enclave-generated device public key + fingerprint.
// Consumed by Phase 3 (post-OTP-verify) + Phase 4 (App Attest augmentation, DEV-04).
// Phase 2 scope: devicePublicKey (DEV-01) + deviceFingerprint (DEV-05).
// Phase 4 will ADD an optional attestation field — that's a non-breaking Decodable extension.

import Foundation

nonisolated public struct DeviceRegisterEndpoint: APIEndpoint {
    public struct DeviceFingerprintPayload: Encodable, Sendable {
        public let model: String
        public let iosVersion: String
        public let installUUID: String
        ...
        private enum CodingKeys: String, CodingKey {
            case model
            case iosVersion
            case installUUID = "installUuid"
        }
    }
    public struct RequestBody: Encodable, Sendable {
        public let devicePublicKey: String  // base64-encoded DER, from SecureEnclaveKeyStore (Plan 06)
        public let deviceFingerprint: DeviceFingerprintPayload
    }
    public struct Response: Decodable, Sendable {
        public let deviceID: String
        public let registeredAt: Date
        ...
        private enum CodingKeys: String, CodingKey {
            case deviceID = "deviceId"
            case registeredAt
        }
    }
    public let path = "/device/register"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(devicePublicKey: String, fingerprint: DeviceFingerprintPayload) {
        self.body = RequestBody(devicePublicKey: devicePublicKey, deviceFingerprint: fingerprint)
    }
}
```

**Deltas:**
- Path is `/device/heartbeat`.
- RequestBody: `sessionToken: String`, `attestedKeyId: String`, `assertion: Data` (base64-encoded at wire time by APIClient's JSONEncoder).
- Response: `heartbeatAcceptedAt: Date`, `trustTier: TrustTier`. Add `TrustTier: Decodable, Sendable` conformance on the type itself.
- No CodingKeys bridge needed — `attestedKeyId` maps cleanly to `attested_key_id` under `.convertToSnakeCase` (the trailing `Id` is a two-letter acronym that the strategy handles correctly; verify with an `EndpointEncodingTests` entry).
- RESEARCH Pattern 3 lines 441-454 has verbatim shape.

---

### 6. `Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — EXTEND existing

**Analog:** Self (existing file at `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift`). The file-top comment at line 5 explicitly anticipates:

```swift
// Phase 4 will ADD an optional attestation field — that's a non-breaking Decodable extension.
```

**Extension rule (D-09):** `attestationStatus` is ALWAYS present in the payload; `attestationObject` + `attestedKeyId` are **optional** — omitted entirely when `attestationStatus != .attested`.

**Test pattern for the omission rule:** `validationLedgerTests/Networking/EndpointEncodingTests.swift` (lines 23-63) is the template for asserting snake-case wire shape. Example pattern at lines 33-46:

```swift
@Test("IN-05 — DeviceRegisterEndpoint.DeviceFingerprintPayload encodes installUUID → install_uuid")
func deviceRegisterFingerprint() throws {
    let payload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
        model: "iPhone15,2",
        iosVersion: "17.5",
        installUUID: "11111111-1111-1111-1111-111111111111"
    )
    let json = try Self.snakeEncoder.encode(payload)
    let str = String(data: json, encoding: .utf8) ?? ""
    #expect(str.contains("\"install_uuid\""), "Expected install_uuid in JSON, got: \(str)")
    #expect(str.contains("\"ios_version\""), "ios_version should still snake-case correctly")
    #expect(str.contains("\"model\""))
    #expect(!str.contains("install_u_u_i_d"), "Mangled key still present: \(str)")
}
```

**Deltas:**
- Add two optional fields to `RequestBody`: `attestedKeyId: String?`, `attestationObject: Data?`.
- Add one required field: `attestationStatus: AttestationStatus` (the enum from Core/Attestation).
- Extend `Response` with `trustTier: TrustTier` (D-12).
- Add a new `init(...)` overload that takes attestation params; keep the existing Phase-2 init for back-compat OR add default-nil args to avoid breaking callers.
- Write the D-09f parameterized test (RESEARCH Phase Requirements → Test Map line 874) asserting that `attestationStatus != .attested` omits both fields from JSON. `JSONEncoder` with Swift `Optional` already omits nil values by default — the test verifies this AT the contract-pinning level, same idea as `EndpointEncodingTests.deviceRegisterFingerprint`.

---

### 7. `Core/Storage/Keychain/KeychainKey.swift` — EXTEND

**Analog:** Self (existing file lines 10-21). Add two new constants with the same convention:

```swift
// validationLedger/Core/Storage/Keychain/KeychainKey.swift — existing
public static let sessionToken = KeychainKey(rawValue: "session.token")
public static let installUUID  = KeychainKey(rawValue: "install.uuid")

// Phase 3 D-33: cached session metadata + biometric domain state.
public static let sessionRole          = KeychainKey(rawValue: "session.role")
public static let sessionUserID        = KeychainKey(rawValue: "session.userID")
public static let biometricDomainState = KeychainKey(rawValue: "biometric.domainState")
```

**Deltas:**
- Add `public static let attestedKeyId = KeychainKey(rawValue: "device.attestedKeyId")`.
- Add `public static let lastHeartbeatAt = KeychainKey(rawValue: "device.lastHeartbeatAt")`.
- Match existing `device.*` / `install.*` / `session.*` / `biometric.*` dot-qualified naming.
- Add header-inline comment noting Phase 4 DEV-04 + the D-03 preservation-across-logout invariant (mirror the "Raw values are referenced by name in downstream plans (06, 09); do NOT rename." comment style).

---

### 8. `Core/Storage/Keychain/KeychainScope.swift` — EXTEND (critical D-03 invariant)

**Analog:** Self (existing `.session` case).

**Existing pattern** (KeychainScope.swift lines 16-35):

```swift
public enum KeychainScope: Sendable {
    /// All keys tied to an authenticated session (wiped on logout).
    /// Members: sessionToken, sessionRole, sessionUserID, biometricDomainState.
    case session

    public func contains(_ key: KeychainKey) -> Bool {
        switch self {
        case .session:
            return [
                KeychainKey.sessionToken,
                KeychainKey.sessionRole,
                KeychainKey.sessionUserID,
                KeychainKey.biometricDomainState,
            ].contains(key)
        }
    }
}
```

**Deltas:**
- **No code change to the `contains` function is expected.** The file's existing doc-comment says `installUUID` is INTENTIONALLY outside `.session`. Phase 4's `attestedKeyId` + `lastHeartbeatAt` follow the same rule.
- **Add a test** in `validationLedgerTests/Storage/KeychainScopeTests.swift` (D-03 validation map, RESEARCH line 860) named `testAttestedKeyIdNotInSessionScope` — mirrors the idea of the existing `installUUID` exclusion. The test is the enforcement mechanism; code doesn't change.
- Update the `.session` doc comment to explicitly name the excluded keys (same style): "Excluded from .session: installUUID (device identity, D-05); attestedKeyId + lastHeartbeatAt (device identity, D-03)."

---

### 9. `App/AppContainer.swift` — EXTEND

**Analog:** Self (existing `preflightSecureEnclave(...)` lines 303-327).

**Existing preflight pattern** (AppContainer.swift lines 303-327):

```swift
/// Preflight the Secure Enclave invariant. Returns true if launch should proceed, false if not.
/// `AppContainer.init` uses this via the `isSecureEnclaveAvailable` parameter and fatalErrors
/// on false in production paths — this static lets device tests assert the false-path outcome
/// WITHOUT triggering the process-aborting fatalError.
///
/// Defaults for `isSimulatorBuild` / `isDebugBuild` reflect the build configuration of the
/// test process itself; tests inject values to simulate production Release + device.
static func preflightSecureEnclave(
    isSecureEnclaveAvailable: Bool,
    isSimulatorBuild: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }(),
    isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
) -> Bool {
    if isDebugBuild && isSimulatorBuild {
        return true
    }
    return isSecureEnclaveAvailable
}
```

**Existing keystore-selection pattern** (AppContainer.swift lines 107-115) — the `#if DEBUG && targetEnvironment(simulator)` gate is where `AttestationService` selection mirrors:

```swift
#if DEBUG && targetEnvironment(simulator)
self.keyStore = SoftwareKeyStore()
#else
guard Self.preflightSecureEnclave(isSecureEnclaveAvailable: isSecureEnclaveAvailable) else {
    // FR-iOS-DEV MUST / DEV-03 SC-4: refuse to launch on a production device lacking SEP.
    fatalError("Production build requires Secure Enclave; device reports SecureEnclave.isAvailable = false")
}
self.keyStore = SecureEnclaveKeyStore()
#endif
```

**Composed-service injection pattern** (AppContainer.swift lines 185-196) — how later services (LogoutService) get constructed and stored on `self`:

```swift
let logoutLogger = OSLogLoggerImpl(
    subsystem: LoggingSubsystem.auth,
    category: "auth.logout"
)
let logoutService = DefaultLogoutService(
    keychain: self.keychainStore,
    keyStore: self.keyStore,
    sessionLock: sessionLock,
    logger: logoutLogger,
    notificationCenter: .default
)
self.logoutService = logoutService
```

**Deltas:**
- Add `let attestationService: any AttestationService` property in the ordered let-block (alongside `biometricService`, `sensitiveAction`, `logoutService`).
- Add `preflightAttestationEntitlement(...)` static mirroring `preflightSecureEnclave` — returns a `AttestationEntitlementPreflightResult` enum (`.available | .missing | .simulatorBypass`) INSTEAD of `Bool`, per RESEARCH Pattern 5 line 534. Unlike SE, do NOT fatalError on false — entitlement miss is recoverable, log at error (see RESEARCH Pattern 5 line 542 rationale).
- Inside `init`, select between `DCAppAttestAttestationService(...)` and `SimulatorBypassAttestationService(...)` using the same `#if DEBUG && targetEnvironment(simulator)` pattern.
- Add `session` property gaining `trustTier: TrustTier` (D-12) — this requires constructing a new `Session` holder type, OR adding a mutable property on an existing container. Planner decides between:
  - (a) Introduce `AppSession` class-backed holder with `var trustTier: TrustTier`, injected into SceneDelegate's `performHeartbeatIfNeeded`, or
  - (b) Use an `@MainActor` `class` with a single `trustTier` Published-style property.
- Planner's choice guided by existing `AppContainer` fields being `let` — a mutable trust tier needs a class (reference semantics) OR an `actor`.

---

### 10. `App/SceneDelegate.swift` — EXTEND

**Analog:** Self (existing `scene(_:willConnectTo:)` + `handleDidBecomeActive()` patterns).

**Cold-boot restore-branch pattern** (SceneDelegate.swift lines 177-193) — D-07's "heartbeat on cold-boot piggybacking on `SessionRestoreProbe.restored`":

```swift
// Phase 3 D-04/D-05 (Blocker 6): probe the session via the lightweight
// SessionRestoreProbe helper BEFORE first paint.
switch SessionRestoreProbe.probe(env: .current) {
case .restored(let role):
    // Phase 3 gap-closure (Plan 13): pass checkLockState: true ONLY on the
    // genuine cold-boot restore path.
    presentRoot(.role(role), checkLockState: true)
case .needsAuth:
    presentRoot(.auth)
}
```

**didBecomeActive handler pattern** (SceneDelegate.swift lines 371-376) — the exact extension point for the D-07 24h-since-last-heartbeat check:

```swift
/// Handler for UIApplication.didBecomeActiveNotification — re-runs the lockState
/// check only when the current phase is .role(_). On .auth or .anotherActiveSession,
/// a lock overlay is meaningless (the user has not authenticated or is on a terminal
/// support screen respectively).
private func handleDidBecomeActive() {
    guard case .role = currentPhase else { return }
    guard let container = appCoordinator?.container else { return }
    guard let rootVC = window?.rootViewController else { return }
    presentBiometricLockIfNeeded(container: container, over: rootVC)
}
```

**Observer-token cleanup pattern** (SceneDelegate.swift lines 204-233) — the `didBecomeActive` observer is already wired; heartbeat reuses it, no new observer needed:

```swift
func sceneDidDisconnect(_ scene: UIScene) {
    if let token = sessionInvalidateObserver {
        NotificationCenter.default.removeObserver(token)
        sessionInvalidateObserver = nil
    }
    if let token = appDidBecomeActiveObserver {
        NotificationCenter.default.removeObserver(token)
        appDidBecomeActiveObserver = nil
    }
    // ...
}
```

**Helper-function presentation pattern** (SceneDelegate.swift lines 327-365) — `presentBiometricLockIfNeeded(container:over:)` is the template for `performHeartbeatIfNeeded(container:)`:

```swift
private func presentBiometricLockIfNeeded(container: AppContainer, over presenter: UIViewController) {
    // Idempotency: if a lock VC is already up, don't stack another one.
    if presentedLockVC != nil { return }
    let state = container.sessionLock.lockState(now: .now)
    guard case .locked(let reason) = state else { return }
    // ... construct + present ...
}
```

**Deltas:**
- Add a new `performHeartbeatIfNeeded(container:)` async @MainActor helper mirroring `presentBiometricLockIfNeeded` shape — idempotency check up front (read `lastHeartbeatAt`, `< 24h` → return), then do the work (see RESEARCH Common Operation 1 lines 666-696 for the full body).
- Call `performHeartbeatIfNeeded` from TWO sites: (a) inside `scene(_:willConnectTo:)` `.restored` arm (D-07 cold-boot path), (b) inside `handleDidBecomeActive` AFTER the biometric-lock check (D-07 warm-foreground 24h path).
- The heartbeat call is fire-and-forget `Task { @MainActor in ... }` per RESEARCH Common Operation 1 line 658-660; a heartbeat failure does NOT block role-shell render (RESEARCH assumption A4).
- On heartbeat failure, silent-log at error level + let backend drive re-attest via next register (RESEARCH Common Operation 1 lines 690-695).

---

### 11. `UI/LimitedTrustBannerView.swift` — NEW UIKit banner

**Analog:** No direct banner analog exists. Closest role-match is `RoleCoordinator.wrapTabsWithNavAndInstallAvatar` at `validationLedger/Roles/RoleCoordinator.swift` lines 45-67 — a shared-across-5-roles UIKit composition helper:

```swift
// validationLedger/Roles/RoleCoordinator.swift
/// Wraps each existing tab root in a `UINavigationController` and installs an
/// avatar `UIBarButtonItem` on the embedded root's `navigationItem`. Tapping the
/// avatar calls the `presenter` closure — role TabBarControllers pass a closure
/// that constructs `ProfileViewController(logoutService:)` and it gets presented
/// modally in a fresh UINavigationController.
///
/// Accessibility: the bar button item's `accessibilityIdentifier` is fixed at
/// `"nav-avatar"` so Plan 12 UI smoke tests can target it deterministically across
/// all 5 role shells without needing role-specific selectors.
///
/// System image "person.crop.circle" is the SF Symbol; every iOS 17 device ships
/// with it. No asset catalog entry needed.
func wrapTabsWithNavAndInstallAvatar(presenter: @escaping () -> UIViewController) {
    let wrapped: [UIViewController] = (viewControllers ?? []).map { tabRoot in
        // ...
        let item = UIBarButtonItem(
            image: UIImage(systemName: "person.crop.circle"),
            primaryAction: UIAction { [weak root] _ in ... }
        )
        item.accessibilityIdentifier = "nav-avatar"
        item.accessibilityLabel = "Profile"
        root.navigationItem.rightBarButtonItem = item
        return nav
    }
    viewControllers = wrapped
}
```

**Integration-via-wrapper pattern** (same file, lines 27-43) — note the `where Self: UITabBarController` extension is the DRY mechanism; Phase 4's banner composition follows the same extension approach.

**Deltas (banner file itself):**
- `final class LimitedTrustBannerView: UIView` — UIKit (no SwiftUI per CLAUDE.md).
- Auto Layout constraints pinning height (~36pt), top anchor to superview's `safeAreaLayoutGuide.topAnchor` (avoid iPad notch/Dynamic-Island overlap — RESEARCH Pitfall 7 line 639-646).
- Fixed copy (D-11 / CONTEXT specifics line 174): `"Limited trust mode — this device can't fully verify. Some features may be restricted."` Wrap in `NSLocalizedString(...)` + Localizable.strings entry (English-only for M1 per CONTEXT D-11 i18n note, structure ready for v2).
- `isUserInteractionEnabled = false` — RESEARCH assumption A9 (non-dismissible via gesture-blocking).
- `accessibilityIdentifier = "limited-trust-banner"` so UI smoke tests can target it (RESEARCH validation map D-11 line 876).
- System-colored warning tone (CONTEXT claude-discretion line 94: "system-colored warning tone") — use `UIColor.systemYellow.withAlphaComponent(0.85)` or `UIColor.systemOrange`; planner picks one with PM.

**Deltas (RoleCoordinator.swift extension):**
- Add sibling extension method: `wrapWithLimitedTrustBanner(trustTier: TrustTier) -> UIViewController`. When `trustTier != .hardwareAttested`, wrap `self` (the tab bar controller) in a parent `UIViewController` whose view stack is `[tabBarController.view, LimitedTrustBannerView()]` (RESEARCH Pitfall 7 line 643 "wrapper approach"). When `trustTier == .hardwareAttested`, return `self` unchanged.

---

### 12. `App/DevMenu/DevMenuViewController.swift` — EXTEND

**Analog:** Self (existing `Row` enum + `didSelectRowAt` lines 19-108).

**Row enum pattern** (DevMenuViewController.swift lines 19-42):

```swift
private enum Row: Int, CaseIterable {
    case roleSwitcher
    case keychainInspector
    case logViewer
    case networkConfig  // Phase 2 Plan 07 addition — NET-03 SC-2 demonstrator

    var title: String {
        switch self {
        case .roleSwitcher:      return "Role Switcher"
        case .keychainInspector: return "Keychain Inspector"
        case .logViewer:         return "Log Viewer (OSLogStore)"
        case .networkConfig:     return "Network Config"
        }
    }

    var subtitle: String {
        switch self {
        case .roleSwitcher:      return "Swap to any of the 5 roles (D-07)"
        case .keychainInspector: return "Enumerate Keychain items under app service (D-11)"
        case .logViewer:         return "Last 15 min of OSLog entries (LOG-03)"
        case .networkConfig:     return "Toggle mock ↔ live (NET-03)"
        }
    }
}
```

**Row-handler pattern** (DevMenuViewController.swift lines 78-108) — each case in `didSelectRowAt` either pushes a sub-VC or triggers an action:

```swift
override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard let row = Row(rawValue: indexPath.row) else { return }
    switch row {
    case .roleSwitcher:
        let vc = RoleSwitcherViewController { [weak self] role in
            self?.dismiss(animated: true) { /* ... */ }
        }
        navigationController?.pushViewController(vc, animated: true)
    case .keychainInspector:
        let vc = KeychainInspectorViewController(store: container.keychainStore)
        navigationController?.pushViewController(vc, animated: true)
    // ...
    }
}
```

**Deltas:**
- Add `case reattestNow` to `Row` enum.
- `title`: `"Re-attest now"`.
- `subtitle`: `"Force-rotate App Attest key (D-04 re-attestation test path)"`.
- Handler calls `container.attestationService.clearPersistedKeyId()` + re-fires `/device/register` via a one-off Task; surfaces result via a quick toast/alert (mirror RoleSwitcher's dismiss pattern).
- Entire file is already `#if DEBUG`-gated at top — no additional gating needed.

---

### 13. `validationLedger.entitlements` — NEW file

**Analog:** None in repo. Reference the plist format directly from Apple's documentation.

**Content to write** (plist XML — Xcode generates this format; write it by hand to match):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.devicecheck.appattest-environment</key>
    <string>development</string>
</dict>
</plist>
```

**Deltas:**
- Value is `development` for Phase 4 dev + TestFlight — Apple IGNORES this value in TestFlight / App Store and always uses production routing (RESEARCH Pitfall 3 lines 602-608).
- Xcode project's CODE_SIGN_ENTITLEMENTS build setting must reference this file — that is a `.pbxproj` change, NOT a source-code change, but must be planned.
- Add a top-of-file XML comment explaining Pitfall 3's "Apple ignores in TestFlight/AppStore" so future devs don't try to flip this to `production` for release.

---

### 14. `.github/workflows/ci-device.yml` — UPGRADE

**Analog:** Self (existing file at `.github/workflows/ci-device.yml`).

**Existing full file** (34 lines):

```yaml
name: CI (Device)

on:
  # D-05(a): every merge to main
  push:
    branches: [main]
  # D-05(b): security-path PR gate
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
      - name: Checkout
        uses: actions/checkout@v4

      - name: Show Xcode version
        run: xcodebuild -version

      - name: Build + Test on connected iPhone (D-06 smoke)
        run: |
          set -o pipefail
          xcodebuild test \
            -project validationLedger.xcodeproj \
            -scheme validationLedger \
            -destination "platform=iOS,id=${{ secrets.DEVICE_UDID }}" \
            -only-testing:validationLedgerDeviceTests/SecureEnclaveSmokeTests
```

**Deltas:**
- Rename job from `smoke` → `device-security-surface` (required for GitHub branch-protection UI check-name per Pitfall 4 line 621).
- Extend `paths:` filter with `validationLedger/Core/Attestation/**`.
- Bump `timeout-minutes: 15` → `25` (attestation round-trip adds latency).
- Replace single `-only-testing:validationLedgerDeviceTests/SecureEnclaveSmokeTests` with full target: `-only-testing:validationLedgerDeviceTests` + `-retry-tests-on-failure` + `-test-iterations 2`.
- Add `-resultBundlePath $PWD/build/DeviceTestResults.xcresult` so flaky-pass parsing script can read xcresult.
- Add upload-artifact step with 14-day retention.
- Add notify-slack step running `scripts/report-flaky-passes.sh $PWD/build/DeviceTestResults.xcresult` on `success()`.
- Verbatim full upgrade in RESEARCH Pattern 4 lines 464-520.

---

### 15. `scripts/report-flaky-passes.sh` — NEW shell script

**Analog:** None in repo. Use plain POSIX sh + `xcrun xcresulttool get` (native to Xcode toolchain).

**Deltas:**
- Input: `$1 = $PWD/build/DeviceTestResults.xcresult` path.
- Output: POST to `$SLACK_WEBHOOK_URL` (GitHub secret) ONLY when xcresult shows at least one test that retried.
- Use `|| true` on curl step so missing webhook doesn't fail the CI job (RESEARCH Environment Availability line 834).
- Keep it minimal (<50 lines); reference `.github/workflows/ci-simulator.yml` for any existing POSIX sh idioms (though none exist in repo).

---

### 16. `docs/attestation-rotation.md` — NEW runbook

**Analog:** `docs/cert-rotation.md`.

**Structure to mirror** (cert-rotation.md section headers):

```
# Cert Rotation Runbook
**Status:** ACTIVE — Phase 2 SEC-01 / FOUND-05 runbook. Review before every cert rotation.
**Canonical file to edit during rotation:** `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift`

## Why Dual-Pin Rotation Is Not Optional
## SPKI Hash Extraction
### From a live server
### From a PEM cert file (pre-deployment)
### Generating a test cert (for unit tests)
### Algorithm assumption
## 30-Day Rotation Window Procedure
### Day -30 (preparation)
### Day 0 (cert swap)
### Day +7 (cleanup)
## Emergency Revoke Path
## Rollback Procedure
## CI Checks (ship with Phase 2)
## Related
```

**Deltas (content adaptation for Phase 4):**
- `# Attestation Rotation Runbook`
- `**Status:** ACTIVE — Phase 4 DEV-04 runbook. Review when backend emits `attestationInvalid` / `nonceExpired` / `keyCompromised` error codes.`
- `**Canonical file to edit during rotation:** `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` (clearPersistedKeyId → regenerate)`.
- Replace "Why Dual-Pin Rotation Is Not Optional" with "Why Client-Self-Rotation Is Forbidden" (D-04 rationale — quota pressure per RESEARCH Pitfall 2 lines 594-600).
- Replace SPKI Hash Extraction with `attestedKeyId` Regeneration procedure (D-04 trigger → `clearPersistedKeyId()` → next `/device/register` calls `DCAppAttestService.generateKey()`).
- Replace "30-Day Rotation Window" with the backend-error-code-driven reactive flow.
- Keep "Emergency Revoke Path" structure — Phase 4's analog is "keyCompromised error code from backend → silent `clearPersistedKeyId()` + next register regenerates" (RESEARCH Open Q4 line 806).
- Keep "Related" section structure — point to RESEARCH file, ADR 0005, REQUIREMENTS.md DEV-04, CONTEXT.md D-04.

---

### 17. `docs/adr/0005-three-key-device-register-payload.md` — NEW ADR

**Analog:** `docs/adr/0004-secure-enclave-two-key-pattern.md`.

**Full-file structural pattern** (ADR 0004 sections):

```markdown
# ADR 0004: Secure Enclave two-key pattern with `.biometryCurrentSet` for authorization

**Date:** 2026-04-21
**Status:** Accepted
**Supersedes:** — (new decision)
**Superseded by:** — (current)

## Context
## Decision
## Consequences
### Positive
### Negative
### Acknowledged but NOT addressed
## Alternatives Considered
## Operational Notes
## References
```

**Deltas (ADR 0005 content):**
- `# ADR 0005: Three-key /device/register payload — deviceKey + authorizationKey + attestedKey`
- `**Date:** 2026-04-22`
- `**Status:** Accepted`
- `**Supersedes:** — extends ADR 0004`
- `**Superseded by:** — (current)`
- Context section: quote CONTEXT.md D-02 verbatim — three distinct keys with distinct roles; Apple App Attest is the ONLY way to bind to hardware attestation (RESEARCH Don't Hand-Roll table); trying to reuse deviceKey/authorizationKey for attestation breaks the contract.
- Decision section: bullet the three keys + each's role + each's lifecycle (D-01 once-per-install, D-03 preserved-across-logout for attestedKeyId; DEV-02 biometry-current-set for authorizationKey; DEV-01 device-passcode for deviceKey).
- Consequences/Positive: hardware-rooted proof; server-side policy can key off `trustTier` without client changes (D-12).
- Consequences/Negative: rate-limit risk (Pitfall 2); requires entitlement provisioning process (Pitfall 3).
- Alternatives Considered: (1) Reuse deviceKey as attestation key — rejected, Apple framework owns its own SE key. (2) Two-key design with attestation assertion per request — rejected per D-07 cadence (heartbeat only).
- References: RESEARCH file line numbers + REQUIREMENTS DEV-04 + CONTEXT D-01 through D-12 + Apple DeviceCheck docs.

---

### 18. Fixture JSON files — 4 new

**Analog:** `validationLedgerTests/Networking/Fixtures/device-register-success.json`:

```json
{
  "device_id": "dev-abc-123",
  "registered_at": "2026-04-21T12:00:00Z"
}
```

**Deltas for new fixtures:**
- `device-challenge-success.json`:
  ```json
  {
    "challenge": "Y2hhbGxlbmdlLW5vbmNlLWZvci10ZXN0aW5n",
    "expires_at": "2026-04-22T12:01:00Z",
    "nonce": "nonce-abc-123"
  }
  ```
- `device-heartbeat-success.json`:
  ```json
  {
    "heartbeat_accepted_at": "2026-04-22T12:00:00Z",
    "trust_tier": "hardwareAttested"
  }
  ```
- `device-heartbeat-attestation-invalid.json` — mirrors device-register-failure.json error shape (loaded via `FixtureLoader` + served with 400-range HTTPURLResponse):
  ```json
  {
    "error_code": "attestationInvalid",
    "error_message": "Attestation is no longer valid — re-attest via /device/register"
  }
  ```
- `device-register-software-only.json`:
  ```json
  {
    "device_id": "dev-sim-bypass-123",
    "registered_at": "2026-04-22T12:00:00Z",
    "trust_tier": "softwareOnly"
  }
  ```

All JSON uses snake_case keys (matches `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` per APIClient). ISO8601 dates match existing `RFC3339` decoding convention (see `device-register-success.json`).

---

### 19. `validationLedgerTests/Attestation/` — new folder, 12+ Swift Testing suites

**Analog:** `validationLedgerTests/Networking/EndpointEncodingTests.swift`.

**Swift Testing + fixture-loader pattern** (EndpointEncodingTests.swift lines 1-31):

```swift
// validationLedgerTests/Networking/EndpointEncodingTests.swift
// Phase 3 Plan 02: assert IN-01 + IN-05 explicit CodingKeys produce correct
// snake_case wire format for acronym-tail properties under .convertToSnakeCase.
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.

import Testing
import Foundation
@testable import validationLedger

@Suite("Endpoint encoding — acronym CodingKeys snake_case bridge (Pre-Phase-3 IN-01, IN-05)")
struct EndpointEncodingTests {

    private static let snakeEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    @Test("IN-01 — OTPVerifyEndpoint.RequestBody encodes otpSessionID → otp_session_id")
    func otpVerifyRequestBody() throws {
        let body = OTPVerifyEndpoint.RequestBody(otpSessionID: "abc", code: "123456")
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"otp_session_id\""), "Expected otp_session_id in JSON, got: \(str)")
        // ...
    }
}
```

**Fixture-load pattern via FixtureLoader** (FixtureLoader.swift lines 1-28):

```swift
static func loadFixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: FixtureBundleMarker.self)
    if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
        return try Data(contentsOf: url)
    }
    // ...
}
```

**MockURLProtocol fixture-registration pattern** (MockFixture.swift lines 10-34):

```swift
extension MockURLProtocol {
    public static func registerFixture<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        register { request in
            guard request.url?.path == path else { return nil }
            guard request.httpMethod == method.rawValue else { return nil }
            // ...
        }
    }
}
```

**Deltas:**
- Each test file conforms to `@Suite("...")` + `struct ...Tests { @Test("...") func ...() async throws { ... } }` pattern.
- Every test that uses MockURLProtocol starts with `MockURLProtocol.reset()` — see MockOTPRoleFixtureRegistry line 29 for the analog.
- For MockURLProtocol-backed integration tests, fixtures are loaded via `FixtureLoader.loadFixture("device-challenge-success")` + registered with `MockURLProtocol.registerFixture(for: DeviceChallengeEndpoint.self, path: "/device/challenge", method: .get, statusCode: 200, body: data)`.
- 12 test files map to D-01..D-12 per the Validation Architecture table (RESEARCH lines 854-882). Each test file has a single `@Suite` with 1–4 `@Test` methods.

---

### 20. `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` + siblings — NEW device tests

**Analog:** `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift`.

**Device-test shape** (SecureEnclaveKeyStoreTests.swift lines 1-40):

```swift
// validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift
// DEV-01 + DEV-02 device-target tests for SecureEnclaveKeyStore round-trip.
//
// Target membership: validationLedgerDeviceTests ONLY. Simulator has no SEP — this suite
// WILL NOT pass on simulator (keys would fail with errSecUnimplemented). Research Pitfall 2.
//
// Test cleanup: each @Test deletes both application tags from Keychain in defer blocks —
// avoids persistent-state leakage across test runs on the same physical device.
//
// Biometric handling in CI: tests that use signWithAuthorization may prompt Face ID / Touch ID
// on interactive device runs. In unattended CI (self-hosted runner), those prompts fail with
// errSecAuthFailed — the relevant test accepts either outcome as valid (documented inline).

import Testing
import Foundation
import Security
import CryptoKit
@testable import validationLedger

@Suite("SecureEnclaveKeyStore — DEV-01/02 device round-trip")
struct SecureEnclaveKeyStoreTests {

    private func deleteKeychainKey(tag: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: tag,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    private func purgeAllKeys() {
        deleteKeychainKey(tag: Data("com.maldin.validationLedger.deviceKey".utf8)),
        deleteKeychainKey(tag: Data("com.maldin.validationLedger.authKey".utf8))
    }

    @Test("Secure Enclave is available on this device")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true, "Device tests require Secure Enclave; simulator would fail here")
    }
    // ... purgeAllKeys + defer { purgeAllKeys() } pattern in every test body ...
}
```

**Accept-either-outcome pattern** (SecureEnclaveKeyStoreTests.swift lines 98-119) — the honest CI-biometric-failure pattern:

```swift
@Test("signWithAuthorization either succeeds or fails with errSecAuthFailed (biometric required)")
func signWithAuthorizationBiometricOrFail() throws {
    purgeAllKeys()
    defer { purgeAllKeys() }

    let store = SecureEnclaveKeyStore()
    _ = try store.generateDeviceIdentityKeys()
    let payload = Data("auth-key test".utf8)
    do {
        let sig = try store.signWithAuthorization(payload)
        #expect(!sig.isEmpty)
    } catch KeyStoreError.signingFailed {
        // Biometric prompt was denied or unattended; this is a valid outcome for CI.
        // Documented acceptable outcome; pass the test.
    } catch {
        Issue.record("Unexpected error from signWithAuthorization: \(error)")
    }
}
```

**Deltas:**
- `AppAttestRoundTripTests.swift`: purge `device.attestedKeyId` + `device.lastHeartbeatAt` Keychain keys in defer — mirrors the application-tag purge above. Use `keychain.delete(.attestedKeyId)` + `keychain.delete(.lastHeartbeatAt)` (RESEARCH validation map line 856).
- `KeychainBiometricACLTests.swift`: use `SeededBiometricService` (see #21 below) injected via AppContainer's test seam — prevents real Face ID prompt in unattended CI (D-14).
- `LogoutClearsAuthorizationKeyTests.swift`: call `logoutService.logout(reason: .userInitiated)` + assert `keyStore.deleteKey(slot: .authorization)` was called (or the key is no longer retrievable). Mirrors SecureEnclaveKeyStoreTests' SecItem round-trip assertion pattern.
- `secureEnclaveAvailable()` smoke-baseline at top of every device suite — mirrored from SecureEnclaveKeyStoreTests line 36-39.
- App Attest round-trip test uses MockURLProtocol-driven endpoints (challenge + register + heartbeat) — register fixtures at test entry, reset on teardown. Apple's `DCAppAttestService.shared` is NOT mockable, so the test calls the real service on hardware and validates the returned `attestationObject` is non-empty Data.

---

### 21. `validationLedgerDeviceTests/SeededLAContext.swift` — NEW test helper

**Analog:** `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` `StubLocationProviderForUITest` (lines 84-98).

**Stub-protocol-conforming pattern** (MockOTPRoleFixtureRegistry.swift lines 83-106):

```swift
/// Stub LocationProvider for UI tests — always returns a US coordinate immediately.
/// No CLLocationManager permission prompt; no hardware dependency; synchronous success.
/// Injected via `AppContainer.uiTestLocationProvider` static override.
@MainActor
final class StubLocationProviderForUITest: LocationProvider {
    func requestPermission() async -> CLAuthorizationStatus { .authorizedWhenInUse }

    func currentLocation(
        maxAge: TimeInterval,
        maxAccuracy: CLLocationDistance
    ) async throws -> CLLocation {
        CLLocation(latitude: 37.3349, longitude: -122.0090)
    }
}

/// Stub CountryGate for UI tests — always returns "US".
final class StubCountryGateForUITest: CountryGate, @unchecked Sendable {
    func resolveCountry(for location: CLLocation) async throws -> String { "US" }
}
```

**RESEARCH verbatim reference** (Common Operation 2 lines 707-717):

```swift
import LocalAuthentication
@testable import validationLedger

final class SeededBiometricService: BiometricService, @unchecked Sendable {
    func evaluate(reason: String, fallback: BiometricFallback) async throws {
        // No-op. Tests that depend on the KeychainStore side effect
        // should also inject a KeychainStore stub, or tolerate that the write is skipped.
    }
    func currentDomainState() -> Data? { Data("seeded-domain-state".utf8) }
}
```

**Deltas:**
- `SeededBiometricService` conforms to existing `BiometricService` protocol (in `validationLedger/Core/Auth/BiometricService.swift` lines 19-29).
- `evaluate(...)` returns without throwing (seeded success); does NOT touch real `LAContext` (per D-14 — no real Face ID in unattended CI).
- `currentDomainState()` returns a fixed-content `Data` so re-enrollment-diff logic always reports unchanged.
- File lives in `validationLedgerDeviceTests/` target, NOT production target. Add `@unchecked Sendable` conformance per the analog.
- AppContainer needs a test seam to inject `biometricService` — RESEARCH Common Operation 2 line 726 TODO explicitly flags this as "Phase 4 planner surface a BiometricService injection parameter on AppContainer.init OR wire seeded service via a separate factory path". Planner decides during plan authorship.

---

## Shared Patterns

### Pattern A: PII-Scrubbed Structured Logging

**Source:** `validationLedger/Core/Logging/Logger.swift` lines 6-19 + `OSLogLoggerImpl.swift`.
**Apply to:** All `Core/Attestation/*` files — MUST NOT log raw `attestationObject` or `attestedKeyId` bytes (CONTEXT line 156). Log only `AttestationStatus` enum + DCError code integer.

```swift
public enum LogField: Hashable, Sendable {
    case phone           // E.164 → masked
    case fullName        // "Jane Doe" → "J. D."
    case driversLicense  // → [REDACTED:DL]
    case mcNumber        // → [REDACTED:MC]
    case dotNumber       // → [REDACTED:DOT]
    case email           // local part masked
    // (Phase 3 D-23 / GEO-03: `.coordinates` case removed — coordinates can only
    // flow through `Core/Identity/PlatformPayloadField` to networking endpoint
    // payloads. Logger cannot accept them by construction. Do not re-add.)
    case count           // safe — integer
    case duration        // safe — TimeInterval
    case event           // safe — string event name
}
```

**Deltas for Phase 4:**
- Open Q2 (RESEARCH line 793-796) raises whether to add a `.status(String)` case or reuse `.event`. Planner decides — leaning toward reusing `.event` with prefix convention (`attestation_status_attested`, `attestation_status_quotaExceeded`) to avoid new LogField cases.
- Do NOT add a `.attestationObject` or `.attestedKeyId` LogField case — that would open the exact PII leak path the enum is designed to prevent.

### Pattern B: `@MainActor` on Services That Touch UIKit/LAContext/OS Callbacks

**Source:** `validationLedger/Core/Auth/BiometricService.swift` line 31 + `SessionLockService.swift`.
**Apply to:** `DCAppAttestAttestationService` (DeviceCheck callbacks are not thread-specified; `@MainActor` on the class ensures all mutation hops to the main thread).

```swift
@MainActor
public final class DefaultBiometricService: BiometricService {
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(keychain: KeychainStore, logger: any Logger) {
        self.keychain = keychain
        self.logger = logger
    }
    // ...
}
```

### Pattern C: OSLog Subsystem Naming

**Source:** `validationLedger/App/AppContainer.swift` lines 97-102, 121-124, 140-143, 171-174, 185-188.
**Apply to:** `DCAppAttestAttestationService` init — construct `OSLogLoggerImpl(subsystem: LoggingSubsystem.auth, category: "auth.attestation")`.

```swift
let logoutLogger = OSLogLoggerImpl(
    subsystem: LoggingSubsystem.auth,
    category: "auth.logout"
)
```

**Deltas:** Choose `subsystem: LoggingSubsystem.auth` (Attestation belongs to the auth surface) with `category: "auth.attestation"`. Confirm `LoggingSubsystem.auth` exists at `validationLedger/Core/Logging/Subsystems.swift`.

### Pattern D: Keychain Accessibility

**Source:** `validationLedger/Core/Identity/DeviceFingerprint.swift` lines 54-60 + existing `.afterFirstUnlockThisDeviceOnly` usage.
**Apply to:** Both new Keychain keys (`attestedKeyId`, `lastHeartbeatAt`) use `.afterFirstUnlockThisDeviceOnly` per CONTEXT D-01.

```swift
try keychain.set(
    Data(fresh.utf8),
    for: installUUIDKey,
    accessibility: .afterFirstUnlockThisDeviceOnly
)
```

### Pattern E: Test Bundle Fixture Loading

**Source:** `validationLedgerTests/Networking/FixtureLoader.swift` lines 9-27.
**Apply to:** All Phase 4 tests that load `device-challenge-success.json`, `device-heartbeat-*.json`, `device-register-software-only.json`.

```swift
private final class FixtureBundleMarker {}

enum FixtureLoader {
    enum Error: Swift.Error { case fixtureNotFound(String) }

    static func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        throw Error.fixtureNotFound(name)
    }
}
```

**Deltas:** Reuse the existing `FixtureLoader` — no new copy. All Phase 4 fixtures land in `validationLedgerTests/Networking/Fixtures/` so the existing subdirectory resolution works unchanged.

### Pattern F: NotificationCenter Observer Token + Cleanup

**Source:** `validationLedger/App/SceneDelegate.swift` lines 88-102, 111-117, 204-233.
**Apply to:** Phase 4 does NOT add any new Notification observers on SceneDelegate (heartbeat reuses `appDidBecomeActiveObserver`). Documented here so planner doesn't accidentally add a new one.

### Pattern G: `#if DEBUG`-Only DevMenu Rows

**Source:** `validationLedger/App/DevMenu/DevMenuViewController.swift` — entire file body is `#if DEBUG`-gated (line 11) so Release compiles zero bytes.
**Apply to:** DevMenu's new "Re-attest now" row — no additional `#if` needed inside the file because the whole file is already gated.

### Pattern H: SwiftLint `.biometryAny` / `.biometryCurrentSet` Audit

**Source:** ADR 0004 — explicit rejection of `.biometryAny`. Phase 4 does NOT touch biometric ACL flags (those live in `Core/KeyStore/`). Attestation adds its OWN SE-managed key (Apple-framework-owned), so ADR 0004's biometric discussion is NOT applicable to attestation — but attestation DOES enumerate as the third ACL regime, meriting ADR 0005.

---

## No Analog Found

| File | Role | Data Flow | Why no analog |
|------|------|-----------|---------------|
| `validationLedger/validationLedger.entitlements` | Xcode entitlements plist | config | No .entitlements file exists in the repo yet (Phase 4 is the first to need one). Write by hand per Apple's plist format; use `development` value per RESEARCH Pitfall 3. |
| `scripts/report-flaky-passes.sh` | shell script | CI helper | No shell scripts exist in this repo (it's a Swift+CI-YAML codebase). Use plain POSIX sh + `xcrun xcresulttool`. Script stays < 50 lines; no external dependencies. |
| `validationLedger/UI/LimitedTrustBannerView.swift` | UIKit banner view | UI | No existing UIKit banner/toast component. Closest conceptual analog is the RoleCoordinator avatar-wrapping helper — use it for the composition pattern but not the banner view itself. Build from `UIView` + Auto Layout. |

---

## Pattern-Application Order (advisory for planner)

1. Types first (enums, errors) — `AttestationStatus`, `TrustTier`, `AttestationError`. Zero dependencies.
2. Protocol next — `AttestationService`. Depends on the types.
3. Endpoints (can parallel) — `DeviceChallengeEndpoint`, `DeviceHeartbeatEndpoint`, `DeviceRegisterEndpoint` extension. Depend on `AttestationStatus` + `TrustTier`.
4. Keychain key constants — `KeychainKey` + KeychainScope test.
5. Fixture JSONs — depend on endpoint shapes.
6. Production impl — `DCAppAttestAttestationService`. Depends on protocol + endpoint types + Keychain keys.
7. Simulator bypass impl — `SimulatorBypassAttestationService`. Same deps.
8. AppContainer extension — `preflightAttestationEntitlement` + `attestationService` property. Depends on both impls.
9. SceneDelegate extension — `performHeartbeatIfNeeded`. Depends on AppContainer wiring.
10. Role shell banner — `LimitedTrustBannerView` + RoleCoordinator extension. Depends on `TrustTier` + AppSession holder.
11. DevMenu row — trivial extension.
12. Entitlements + CI YAML + ADR 0005 + attestation-rotation runbook — parallel to each other, independent of code deps.
13. Test suites — land alongside their production counterparts per TDD RED→GREEN (CONTEXT code-context line 159).

---

## Metadata

**Analog search scope:**
- `validationLedger/Core/{Attestation,KeyStore,Networking,Storage,Auth,Identity,Logging}/` (production code)
- `validationLedger/App/` (composition root + SceneDelegate + DevMenu)
- `validationLedger/Roles/` (role shell composition)
- `validationLedger/UI/` (none yet exists)
- `validationLedgerDeviceTests/` (existing device tests)
- `validationLedgerTests/{Networking,Storage,Auth,App,Roles}/` (simulator tests)
- `.github/workflows/` (CI)
- `docs/` + `docs/adr/` (documentation)

**Files scanned:** 42 Swift files read; 2 YAML, 2 markdown docs, 1 ADR, 1 plist format reviewed.

**Pattern extraction date:** 2026-04-22

**Commit pinned to:** `7678a34` (HEAD at mapping time)
