# Phase 7: Load Domain Model & Mock Contract — Pattern Map

**Mapped:** 2026-05-19
**Files analyzed:** 23 new files + 2 additive-edit files = 25 total
**Analogs found:** 23 / 25 (the latency/forced-failure capability on `MockURLProtocol` and the fail-closed `VerificationState` decoder have no exact analog — they are net-new patterns; nearest cousins documented below)

---

## File Classification

### `Core/Load/` domain kernel (8 files, all NEW)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Load/Load.swift` | model | transform (decode) | `validationLedger/Core/Identity/KYC/KYCSession.swift` (aggregate value type) + `KYCStatusEndpoint.Response` (nested decode shape) | role-match (aggregate Decodable value type pattern; KYCSession is the closest aggregate `Sendable` value type) |
| `validationLedger/Core/Load/LoadStatus.swift` | model (enum) | transform (decode) | `validationLedger/Core/Attestation/TrustTier.swift` | exact (`String`-raw `Sendable, Codable` closed enum; same one-purpose-per-file pattern) |
| `validationLedger/Core/Load/LoadAction.swift` | model (enum) | transform (decode) | `validationLedger/Core/Attestation/TrustTier.swift`, `validationLedger/Core/Identity/KYC/RejectionReasonCode.swift` (vocabulary enum) | exact |
| `validationLedger/Core/Load/LoadStatusEvent.swift` | model | transform (decode) | `KYCStatusEndpoint.Response.Artifact` (nested `Decodable, Sendable` struct with explicit `CodingKeys`) | exact |
| `validationLedger/Core/Load/ChainOfTrust.swift` | model | transform (decode) | `KYCStatusEndpoint.Response` (aggregate-with-nested-types) + `KYCSession.swift` (aggregate) | role-match (no v1.0 value type currently nests an array-of-nodes + array-of-edges; closest shape is `Response { artifacts: [Artifact] }`) |
| `validationLedger/Core/Load/VerificationState.swift` | model (enum) | transform (decode w/ custom `init`) | `validationLedger/Core/Identity/KYC/RejectionReasonCode.swift` (call-site degrade-on-unknown — NET-NEW: D-09 puts the degrade in `init(from:)`) | partial — net-new pattern; see "No Analog Found" below |
| `validationLedger/Core/Load/ChainIntegrity.swift` | model | transform (decode) | `validationLedger/Core/Attestation/TrustTier.swift` (verdict enum) + `KYCStatusEndpoint.Response.Artifact` (enum-with-rationale-string) | role-match |
| `validationLedger/Core/Load/RoleLoadPolicy.swift` | service (pure rule table) | request-response (function) | `validationLedger/Core/Attestation/TrustTier.swift` is closed-enum but not a table. No `KYCFlowSequencer` exists in source (mentioned in CONTEXT.md but not present). Closest existing pure-rule resolver: `RejectionReasonCode.copy(for:)` (pure `switch self` resolver, no UIKit). | role-match |

### `Core/Networking/Endpoints/` (3 NEW endpoint conformers)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` | controller (endpoint) | request-response (GET) | `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` | exact (both GET, both `RequestBody = EmptyBody`, both nested `Decodable, Sendable Response` with nested types) |
| `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` | controller (endpoint) | request-response (GET) | `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` | exact (GET + EmptyBody; path takes a dynamic ID param like the new endpoint) |
| `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift` | controller (endpoint) | request-response (POST) | `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` + `KYCSubmitEndpoint.swift` | exact (POST + typed `RequestBody` + auto-inherits `IdempotencyInterceptor`) |

### `Core/Networking/Mock/` (1 NEW, 1 MODIFIED additively)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` | service (mock registry) | request-response (registered handlers) | `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` | exact (D-17: explicit mirror; per-role variation) |
| `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` (ADDITIVE) | middleware (URLProtocol) | request-response | `validationLedger/Core/Networking/Mock/MockFixture.swift` (existing `registerFixture<E>` overload — the file the additive overloads sit alongside) | partial — net-new latency/forced-failure injection; see "No Analog Found" below |

### Composition wiring (1 MODIFIED file)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedger/App/AppContainer.swift` (additive — single DEBUG block line) | config | event-driven (init-time DI) | The existing `MockDefaultFixtures.registerAppDefaults()` call at line 454 (the line the new registry call sits next to) | exact — same DEBUG block, same triple-gate, sibling call |

### Test files (8 NEW Swift Testing suites)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedgerTests/Load/LoadDomainDecodeTests.swift` | test | transform (fixture decode) | `validationLedgerTests/Networking/DeviceChallengeEndpointTests.swift` | exact (fixture-round-trip via `FixtureLoader` + `APIClient.defaultDecoder()`) |
| `validationLedgerTests/Load/VerificationStateDecoderTests.swift` | test | transform | `validationLedgerTests/KYC/RejectionReasonCodeTests.swift` | role-match (closed-enum decode + unknown-input branch coverage) |
| `validationLedgerTests/Load/RoleLoadPolicyTests.swift` | test | request-response (function) | `validationLedgerTests/KYC/RejectionReasonCodeTests.swift` (exhaustive `CaseIterable` sweep) | role-match (exhaustive sweep across `Role.allCases × LoadStatus.allCases`) |
| `validationLedgerTests/Load/ChainOfTrustDecodeTests.swift` | test | transform | `DeviceChallengeEndpointTests.swift` + `RejectionReasonCodeTests.swift` | role-match |
| `validationLedgerTests/Load/LoadStateHistoryTests.swift` | test | request-response | `RejectionReasonCodeTests.swift` (exhaustive vocabulary coverage) | role-match |
| `validationLedgerTests/Networking/LoadEndpointsTests.swift` | test | request-response | `validationLedgerTests/Networking/DeviceChallengeEndpointTests.swift` | exact (shape-assert + fixture-decode triple test pattern) |
| `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` | test | request-response | `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` | exact (`.serialized` suite + register-then-session-fetch pattern) |
| `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` | test | request-response | `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` | exact |

### JSON fixture files (NEW — ~20 files, exact count is planner discretion D-12)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `validationLedgerTests/Networking/Fixtures/loads-list-{role}.json` (5 files) | test data | transform | `validationLedgerTests/Networking/Fixtures/kyc-status-pending.json`, `kyc-status-rejected.json` | exact (snake_case wire keys, ISO-8601 dates, per-state file naming) |
| `validationLedgerTests/Networking/Fixtures/load-detail-{vl-id}.json` (~12 files for named library D-12) | test data | transform | `kyc-status-rejected.json` (richest nested fixture) | exact |
| `validationLedgerTests/Networking/Fixtures/load-action-{success,conflict-409,validation-422,server-error-500}.json` | test data | transform | `kyc-submit-failure.json`, `otp-verify-failure.json` | exact |
| `validationLedgerTests/Networking/Fixtures/loads-list-empty.json` | test data | transform | `kyc-status-pending.json` (empty `artifacts` array) | exact |

---

## Pattern Assignments

### `Core/Load/Load.swift` (model, transform/decode)

**Analog:** `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` (aggregate decode shape) + `validationLedger/Core/Attestation/TrustTier.swift` (file-header doc style).

**File header pattern** (KYCStatusEndpoint lines 1-7):
```swift
// validationLedger/Core/Load/Load.swift
// LOAD-02 (Phase 7): the aggregate Load value type — Decodable & Sendable.
// Embedded in LoadListEndpoint.Response (paginated envelope D-16) and as the
// top-level of LoadDetailEndpoint.Response (which also carries ChainOfTrust per D-08).
// stateHistory: [LoadStatusEvent] per D-02 — the timeline UI in Phase 9 renders from this.

import Foundation
```

**Aggregate Decodable & Sendable struct shape** (KYCStatusEndpoint.swift lines 12-28):
```swift
public struct Response: Decodable, Sendable {
    public struct Artifact: Decodable, Sendable {
        public let artifactID: String
        public let status: String
        public let rejectionReason: String?
        private enum CodingKeys: String, CodingKey {
            case artifactID = "artifactId"
            case status
            case rejectionReason
        }
    }
    public let overallStatus: String
    public let artifacts: [Artifact]
}
```

Apply to `Load` as `public struct Load: Decodable, Sendable { … }` with nested types if any. Place each top-level type in its own file per the v1.0 one-type-per-file rule.

**Acronym CodingKeys override** (KYCStatusEndpoint.swift lines 18-24):
```swift
// Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
// Raw values are camelCase (post-.convertFromSnakeCase form).
private enum CodingKeys: String, CodingKey {
    case artifactID = "artifactId"
    case status
    case rejectionReason
}
```

Apply to every `*ID` field in the load domain (`loadID`, `partyID`, `nodeID`, `edgeID`, `usdotID` if present) so the wire ↔ camelCase mapping survives any toolchain change in `.convertFromSnakeCase` trailing-acronym handling.

---

### `Core/Load/LoadStatus.swift`, `LoadAction.swift`, `ChainIntegrity.swift` (model, transform)

**Analog:** `validationLedger/Core/Attestation/TrustTier.swift` (entire file is 16 lines).

**Single-purpose-per-file closed enum** (TrustTier.swift lines 1-15):
```swift
// validationLedger/Core/Attestation/TrustTier.swift
// Phase 4 DEV-04 (D-12): backend-driven trust tier returned by /device/register
// + /device/heartbeat. Client is a passive renderer — the banner in Plan 08
// decides visibility based on whether this equals .hardwareAttested.
//
// Future tiers (attestedUnverified, revoked, ...) can be added server-side
// without client changes, subject to an `@unknown default:` update here when
// the decoder is extended to a broader closed-set enum.

import Foundation

public enum TrustTier: String, Sendable, Codable {
    case hardwareAttested
    case softwareOnly
}
```

Apply identically to `LoadStatus`, `LoadAction`, `ChainIntegrity`, `DeviceBindingStatus`, `USDOTAuthorityStatus`. Use `String, Sendable, Decodable` (not `Codable` — encoding is not required for these client-side decode-only types). Add `CaseIterable` on `LoadStatus` + `LoadAction` so the exhaustive policy test in `RoleLoadPolicyTests` can sweep `LoadStatus.allCases × Role.allCases` (per Pattern 3 in RESEARCH).

---

### `Core/Load/VerificationState.swift` (model, fail-closed custom decoder — NET-NEW)

**Analog:** `validationLedger/Core/Identity/KYC/RejectionReasonCode.swift` is the closest cousin — but RejectionReasonCode does the degrade-on-unknown at the **call site** (`copy(for:)`), not in `init(from:)`. D-09 explicitly rules out call-site-only degrade.

**Cousin pattern — RejectionReasonCode `String, Decodable` shape** (RejectionReasonCode.swift lines 30-39):
```swift
public enum RejectionReasonCode: String, Decodable, Sendable, CaseIterable {
    case dlFrontGlare = "dl_front_glare"
    case dlFrontBlurry = "dl_front_blurry"
    // …
}
```

**Cousin pattern — RejectionReasonCode call-site degrade** (RejectionReasonCode.swift lines 107-114) — this is what `VerificationState` **must NOT** do (consumers could bypass):
```swift
public static func copy(for rawCode: String) -> String {
    RejectionReasonCode(rawValue: rawCode)?.localizedCopy
        ?? NSLocalizedString(
            "kyc.reject.generic",
            value: "This photo needs to be retaken. Tap to try again.",
            comment: "KYC rejection reason — generic fallback for an unrecognized backend code"
        )
}
```

**Required pattern for `VerificationState` (custom `init(from:)` — D-09):**
```swift
// validationLedger/Core/Load/VerificationState.swift
// LOAD-02 (Phase 7) D-09: fail-closed verification state.
// Unknown JSON value → .unverified (least-trusted, fail-closed).
// A missing field is a hard decode error (strict contract).
//
// Pattern contrast with RejectionReasonCode (Core/Identity/KYC/): that enum
// does its degrade-on-unknown at the call site (`copy(for:)`). D-09 forbids
// the call-site form — the degrade MUST live in init(from:) so no consumer
// can bypass it. This is the net-new "fail-closed closed-enum decode" pattern
// (RESEARCH Pattern 4).

import Foundation

public enum VerificationState: String, Sendable, CaseIterable {
    case verified
    case pending
    case unverified
    case flagged
}

extension VerificationState: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Known string → exact case. Unknown string → .unverified (fail-closed).
        // A missing parent field is a hard error — the `try container.decode(...)`
        // above throws keyNotFound, never reaches here. D-09 strict contract.
        self = VerificationState(rawValue: raw) ?? .unverified
    }
}
```

**Test analog — `RejectionReasonCodeTests.swift`** (lines 45-53):
```swift
@Test("D-11: an unknown code falls back to the generic sentence, never the raw code")
func unknownCodeFallsBackToGeneric() {
    let unknownCopy = RejectionReasonCode.copy(for: "some_future_code")
    #expect(unknownCopy != "some_future_code")
    #expect(!unknownCopy.isEmpty)
    #expect(unknownCopy == RejectionReasonCode.copy(for: "another_unknown_code"))
}
```

Apply the analogous test in `VerificationStateDecoderTests.swift` — feed `"\"compromised\""` JSON, assert decode succeeds with `.unverified`; feed each known string, assert exact case; feed `{}` (parent with missing key) into a wrapping struct, assert decode throws `DecodingError.keyNotFound`.

---

### `Core/Load/LoadStatusEvent.swift` (model, transform)

**Analog:** `KYCStatusEndpoint.Response.Artifact` (lines 13-25 of `KYCStatusEndpoint.swift`).

**Nested Decodable + acronym CodingKeys** (KYCStatusEndpoint.swift lines 13-25):
```swift
public struct Artifact: Decodable, Sendable {
    public let artifactID: String
    public let status: String
    public let rejectionReason: String?
    private enum CodingKeys: String, CodingKey {
        case artifactID = "artifactId"
        case status
        case rejectionReason
    }
}
```

`LoadStatusEvent` carries `{ status: LoadStatus, timestamp: Date, actor: LoadParty? }` per D-02. Timestamp uses ISO-8601 via the `APIClient.defaultDecoder()` `.iso8601` strategy (no per-endpoint decoder customization). The optional `actor` decodes as `nil` when the field is absent — match the `rejectionReason: String?` pattern above.

---

### `Core/Load/ChainOfTrust.swift` (model, transform — aggregate)

**Analog:** `KYCStatusEndpoint.Response` (aggregate with array-of-nested-types) — closest existing shape; no v1.0 type currently nests `[Node] + [Edge] + Verdict`.

```swift
public struct ChainOfTrust: Decodable, Sendable {
    public let nodes: [TrustNode]
    public let edges: [TrustEdge]
    public let integrity: ChainIntegrity
}
```

`TrustNode` and `TrustEdge` follow the `Artifact`-nested-struct shape with their own explicit `CodingKeys` for trailing-acronym fields (`nodeID`, `edgeID`, `partyID`, `usdotID`, `kycCompletedAt`, `usdotNumber`).

---

### `Core/Load/RoleLoadPolicy.swift` (service, pure rule table)

**Analog:** `RejectionReasonCode.swift` (pure `switch self` resolver, no UIKit). No `KYCFlowSequencer` exists in source — D-06 introduces this pure-table pattern fresh for v1.1.

**Pure `switch self` resolver** (RejectionReasonCode.swift lines 44-101):
```swift
public var localizedCopy: String {
    switch self {
    case .dlFrontGlare:
        return NSLocalizedString( /* … */ )
    case .dlFrontBlurry:
        return NSLocalizedString( /* … */ )
    // … all 9 cases exhaustively …
    }
}
```

**Apply to `RoleLoadPolicy`** — a `public enum` with a single static func, the body is one exhaustive nested switch on `(role, status)`. Per D-06, collapse 5 roles into 3 surfaces:
- `.shipper, .broker` → policy table A
- `.carrier, .dispatch` → policy table B
- `.factoring` → always `[]`

```swift
public enum RoleLoadPolicy {
    public static func actions(for role: Role, status: LoadStatus) -> [LoadAction] {
        switch role {
        case .shipper, .broker:
            switch status {
            case .draft:     return [.post]
            case .posted:    return [.tender, .cancel]
            // … exhaustive over LoadStatus.allCases …
            }
        case .carrier, .dispatch:
            switch status {
            case .tendered:    return [.accept, .reject]
            case .accepted,
                 .dispatched,
                 .inTransit:    return [.advanceStatus]
            // …
            }
        case .factoring:
            return []
        }
    }
}
```

**Test pattern — exhaustive sweep** (analog: `RejectionReasonCodeTests.swift` lines 17-25):
```swift
@Test("Policy table is total: every (Role, LoadStatus) pair has a defined action list")
func policyIsTotal() {
    for role in Role.allCases {
        for status in LoadStatus.allCases {
            _ = RoleLoadPolicy.actions(for: role, status: status)  // must not crash
        }
    }
}
```

---

### `Core/Networking/Endpoints/LoadListEndpoint.swift` (controller, GET request-response)

**Analog:** `KYCStatusEndpoint.swift` (entire file is 34 lines — copy this template).

**GET endpoint full template** (KYCStatusEndpoint.swift lines 1-34):
```swift
// validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift
// GET /kyc/status — poll overall KYC status + per-artifact status.
// …
// GET endpoint: no body — uses internal EmptyBody sentinel from APIEndpoint.swift.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCStatusEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable {
        public struct Artifact: Decodable, Sendable {
            public let artifactID: String
            // …
        }
        public let overallStatus: String
        public let artifacts: [Artifact]
    }
    public let path = "/kyc/status"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init() {}
}
```

**Apply to `LoadListEndpoint`** with two adjustments:
1. The path is **dynamic** on `Role`: `public let path: String` (stored, set from init) — `KYCStatusEndpoint` uses a hardcoded `let path = "/kyc/status"` because the path is fixed. The `LoadListEndpoint` init takes a `role: Role` and computes `path = "/loads/\(role.rawValue)"`.
2. Response is the **paginated envelope** per D-16:
   ```swift
   public struct Response: Decodable, Sendable {
       public let loads: [Load]
       public let nextCursor: String?  // decodeIfPresent — wire key: next_cursor
   }
   ```

---

### `Core/Networking/Endpoints/LoadDetailEndpoint.swift` (controller, GET request-response)

**Analog:** `KYCStatusEndpoint.swift` (same GET-with-EmptyBody pattern; dynamic path on `loadID`).

```swift
nonisolated public struct LoadDetailEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable {
        public let load: Load
        public let chain: ChainOfTrust   // D-08: embedded — one round-trip, no separate fetch
    }
    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init(loadID: String) {
        self.path = "/loads/\(loadID)"
    }
}
```

---

### `Core/Networking/Endpoints/LoadActionEndpoint.swift` (controller, POST request-response)

**Analog:** `OTPVerifyEndpoint.swift` (POST + typed `RequestBody` + dynamic init) and `KYCSubmitEndpoint.swift` (thin-finalizer POST with typed body).

**POST endpoint with typed RequestBody** (OTPVerifyEndpoint.swift lines 10-57):
```swift
nonisolated public struct OTPVerifyEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let otpSessionID: String
        public let code: String
        private enum CodingKeys: String, CodingKey {
            case otpSessionID = "otpSessionId"
            case code
        }
    }
    public struct Response: Decodable, Sendable {
        public let sessionToken: String
        public let role: String
        public let userID: String
        public let kycStatus: String?
        private enum CodingKeys: String, CodingKey {
            case sessionToken
            case role
            case userID = "userId"
            case kycStatus
        }
    }
    public let path = "/auth/otp/verify"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(otpSessionID: String, code: String) {
        self.body = RequestBody(otpSessionID: otpSessionID, code: code)
    }
}
```

**Apply to `LoadActionEndpoint`**:
```swift
nonisolated public struct LoadActionEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        // Per-action payload. For most actions the body is the action-name only;
        // tender carries respondByAt + counterpartyID; advanceStatus carries no extra fields.
        public let loadID: String
        // … action-specific fields …
        private enum CodingKeys: String, CodingKey {
            case loadID = "loadId"
        }
    }
    public struct Response: Decodable, Sendable {
        public let load: Load   // server returns the updated Load after the action
    }
    public let path: String
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(loadID: String, action: LoadAction, payload: RequestBody) {
        self.path = "/loads/\(loadID)/\(action.pathSegment)"  // pathSegment computed on LoadAction
        self.body = payload
    }
}
```

**Idempotency** (D-19): zero new wiring. `LoadActionEndpoint`'s `method = .post` causes `IdempotencyInterceptor` (already in `apiClient.requestInterceptors` per `AppContainer.swift:476`) to inject `Idempotency-Key: UUID().uuidString`. See `IdempotencyInterceptor.swift` lines 17-29:
```swift
public func intercept(_ request: URLRequest) async throws -> URLRequest {
    guard let method = request.httpMethod,
          method == "POST" || method == "PUT" else {
        return request
    }
    guard request.value(forHTTPHeaderField: "Idempotency-Key") == nil else {
        return request
    }
    var mutable = request
    mutable.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
    return mutable
}
```

---

### `Core/Networking/Mock/MockLoadFixtureRegistry.swift` (service, mock registry)

**Analog:** `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` (D-17 explicit mirror).

**Full DEBUG-gated registry shape** (MockOTPRoleFixtureRegistry.swift lines 17-101):
```swift
#if DEBUG

import CoreLocation
import Foundation

enum MockOTPRoleFixtureRegistry {

    static func registerForRole(_ role: Role, trustTier: TrustTier = .hardwareAttested) {
        MockURLProtocol.reset()

        // OTP request → returns otpSessionID
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/request" else { return nil }
            let body = Data("""
            {"otp_session_id": "ui-test-session-id", "expires_in_seconds": 300}
            """.utf8)
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
        // … additional handlers …
    }
}

#endif
```

**Apply to `MockLoadFixtureRegistry`**:
- `#if DEBUG`-gated enum.
- Static entry point — name it `registerAppDefaults()` (matches `MockDefaultFixtures.registerAppDefaults()` so the `AppContainer` call site stays consistent across the two registries).
- **Do NOT call `MockURLProtocol.reset()`** inside `registerAppDefaults()` — that would clobber the `MockDefaultFixtures` handlers registered immediately before it. (`MockOTPRoleFixtureRegistry.registerForRole` does call reset because it owns the entire UI-test request set; `MockLoadFixtureRegistry` shares the registry with `MockDefaultFixtures`.) Author handlers as *appended* not *replacing*.
- Use **the underlying `MockURLProtocol.register(_:)` directly** (not `MockFixture.registerFixture<E>`) so a single handler can vary response by URL-path-suffix (the role segment in `/loads/{role}`).
- Wire JSON via `FixtureLoader.loadFixture("loads-list-\(role.rawValue)")` for each per-role list, plus per-state detail handlers and the action-outcome handlers.

**Anti-pattern to avoid (Pitfall 4):** never add load cases to `MockDefaultFixtures.dispatchHandler`'s switch (lines 60-105). D-17 explicitly forbids it; PR diff on `MockDefaultFixtures.swift` must be zero lines.

---

### `Core/Networking/Mock/MockURLProtocol.swift` (middleware, additive extension)

**Constraint (D-18, SC #5):** the existing `register(_:)`, `reset()`, and `MockFixture.registerFixture(for:path:method:statusCode:body:)` API surface must stay **byte-identical**. The diff is **append-only at end of file** — no edits to lines 18-58 of `MockURLProtocol.swift` or lines 14-21 of `MockFixture.swift`.

**Existing API to preserve verbatim** (MockURLProtocol.swift lines 18-58):
```swift
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
    // …
    public override func startLoading() {
        for handler in Self.currentHandlers {
            if let (response, data) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        // No handler matched — return 404 so tests fail loudly rather than hang.
        let url = request.url ?? URL(string: "about:blank")!
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
```

**Existing `registerFixture<E>` to preserve verbatim** (MockFixture.swift lines 14-33):
```swift
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
        let resp = HTTPURLResponse(/* … */)!
        return (resp, body)
    }
}
```

**Net-new additive overloads** (RESEARCH Pattern Pitfall 2 — author as separate functions so the original signature is provably untouched):
```swift
// New file or append-only extension on MockURLProtocol
extension MockURLProtocol {
    /// Net-new (Phase 7): the failure kinds the test can force on a registered route.
    public enum FailureKind: Sendable {
        case timeout                          // -> URLError(.timedOut)
        case serverError(statusCode: Int)     // -> HTTPURLResponse with the given code, empty body
        case urlError(URLError.Code)          // -> URLError(<code>)
    }

    /// Net-new (Phase 7): registerFixture variant that wraps the response in a Task.sleep
    /// before delivering. Existing register/reset/registerFixture API is untouched.
    public static func registerFixtureWithLatency<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data,
        latency: TimeInterval,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) { /* register a handler that Task.sleep’s then delivers */ }

    /// Net-new (Phase 7): force a failure on the given path+method.
    public static func registerForcedFailure(
        for path: String,
        method: HTTPMethod,
        kind: FailureKind
    ) { /* register a handler that invokes client?.urlProtocol(_:didFailWithError:) */ }
}
```

**Test pattern — register-then-session-fetch** (analog: `MockURLProtocolRegistryTests.swift` lines 13-19 and 41-64):
```swift
@Suite("…", .serialized)
struct …Tests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("…")
    func someBehavior() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        // register; perform request; assert response
    }
}
```

---

### `App/AppContainer.swift` (config — one-line addition)

**Analog:** the existing call at line 454 — the new line sits adjacent, inside the same DEBUG block:

```swift
#if DEBUG
let isUITestRolePath = ProcessInfo.processInfo.arguments.contains("-MockOTPRoleForUITest")
if case .mock = resolvedConfig, !isUITestRolePath {
    MockDefaultFixtures.registerAppDefaults()
    MockLoadFixtureRegistry.registerAppDefaults()   // NEW (Phase 7) — D-17
}
#endif
```

**Order matters:** `MockDefaultFixtures` registers a single catch-all `dispatchHandler`. Adding the load registry **after** means load-domain paths are checked first (first-match-wins per `MockURLProtocolRegistryTests.firstMatchWins`). Since `MockDefaultFixtures.dispatchHandler` returns `nil` for unknown paths (line 102-103), even reversing the order would technically work — but documenting the order matches the registry-call convention.

---

### Test files

**Analog template — fixture-decode test** (`DeviceChallengeEndpointTests.swift` lines 12-58):
```swift
import Testing
import Foundation
@testable import validationLedger

@Suite("D-05 — GET /device/challenge decodes fixture round-trip")
struct DeviceChallengeEndpointTests {

    @Test("Fixture decodes into Response with all 3 fields")
    func decodesResponse() throws {
        let data = try FixtureLoader.loadFixture("device-challenge-success")
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceChallengeEndpoint.Response.self, from: data)
        #expect(!response.challenge.isEmpty, "…")
    }

    @Test("Endpoint shape: path is /device/challenge, method is GET, body is nil")
    func endpointShape() {
        let ep = DeviceChallengeEndpoint()
        #expect(ep.path == "/device/challenge")
        #expect(ep.method == .get)
        #expect(ep.body == nil)
    }
}
```

Apply this 3-test template to every load fixture (1 decode test + 1 endpoint-shape test + per-fixture variants).

**Analog template — exhaustive-sweep policy test** (`RejectionReasonCodeTests.swift` lines 17-25):
```swift
@Test("D-11: every defined backend code string decodes to its enum case")
func everyDefinedCodeDecodes() throws {
    for code in RejectionReasonCode.allCases {
        let decoded = RejectionReasonCode(rawValue: code.rawValue)
        #expect(decoded == code)
    }
    #expect(RejectionReasonCode.allCases.count >= 9)
}
```

Apply to `RoleLoadPolicyTests` as a `for role in Role.allCases { for status in LoadStatus.allCases { … } }` sweep.

---

### JSON fixture files

**Analog templates:**
- Empty array fixture: `validationLedgerTests/Networking/Fixtures/kyc-status-pending.json`:
  ```json
  { "overall_status": "pending", "artifacts": [] }
  ```
- Rich nested fixture: `kyc-status-rejected.json`:
  ```json
  {
    "overall_status": "rejected",
    "artifacts": [
      { "artifact_id": "art-face-001", "status": "rejected", "rejection_reason": "face_not_centered" },
      { "artifact_id": "art-dl-back-003", "status": "verified", "rejection_reason": null }
    ]
  }
  ```
- Flat OTP-style: `otp-verify-success.json`:
  ```json
  {
    "session_token": "test-session-token-xyz",
    "role": "carrier",
    "user_id": "u-42",
    "kyc_status": "verified"
  }
  ```

**Conventions to copy:**
1. **snake_case wire keys** — `overall_status`, `artifact_id`, `next_cursor`, `state_history`, `chain_of_trust`, `verification_state`, `respond_by_at`, `kyc_completed_at`, `usdot_number`, `usdot_authority_status`.
2. **ISO-8601 dates** — `"2026-04-22T12:01:00Z"` (verified by `DeviceChallengeEndpointTests.decodesExpiresAt`).
3. **Explicit `null`** for absent optionals in arrays (kyc-status-rejected line 6-9 pattern).
4. **Omit the field entirely** for top-level absent optionals (the pre-Phase-5 `otp-verify-success.json` omitting `kyc_status` is the precedent — `decodeIfPresent`/synthesized-optional-decoder handles it).
5. **One file per scenario** — not one mega-fixture (Pitfall 5 of the v1.0 fixture convention).

Per Pitfall 5 (RESEARCH §"Common Pitfalls"), at least 2-3 fixtures must deliberately omit optional fields (e.g. `respond_by_at`, `kyc_completed_at`, `next_cursor`, empty `edges` array) to test the optionality boundary.

---

## Shared Patterns

### `nonisolated public struct APIEndpoint` conformance
**Source:** `validationLedger/Core/Networking/APIEndpoint.swift` lines 15-52
**Apply to:** `LoadListEndpoint`, `LoadDetailEndpoint`, `LoadActionEndpoint` (all 3 new endpoints)
```swift
public protocol APIEndpoint<Response>: Sendable {
    associatedtype RequestBody: Encodable & Sendable
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: RequestBody? { get }
    var headers: [String: String] { get }  // default `[:]` via extension
}

nonisolated public struct EmptyBody: Encodable, Sendable {
    public init() {}
}
```
Every new endpoint is a **`nonisolated public struct`** (required under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). GETs `typealias RequestBody = EmptyBody`. POSTs declare a nested `RequestBody: Encodable, Sendable` struct.

### Snake-case wire ↔ camelCase types decoder strategy
**Source:** `validationLedger/Core/Networking/APIClient.swift` lines 110-115
**Apply to:** Every `Decodable` value type in `Core/Load/` + every endpoint `Response` + every test that decodes a fixture.
```swift
public static func defaultDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .iso8601
    return d
}
```
- Every field is named camelCase in Swift, snake_case on the wire — handled by the decoder strategy automatically for 95% of cases.
- For any trailing-acronym field (`loadID`, `partyID`, `nodeID`, `edgeID`, `usdotNumber`) add an explicit `private enum CodingKeys: String, CodingKey { case loadID = "loadId" }` per `KYCStatusEndpoint.swift` lines 18-24.
- Tests must use **`APIClient.defaultDecoder()`** (not a fresh `JSONDecoder()`) so any decoder drift surfaces in tests — see `DeviceChallengeEndpointTests` line 24.

### Idempotency on POST (free, no new wiring)
**Source:** `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` lines 13-29 + `validationLedger/App/AppContainer.swift` line 476
**Apply to:** `LoadActionEndpoint` (the one POST in this phase) — D-19, automatic.
Because `LoadActionEndpoint.method == .post`, the existing `IdempotencyInterceptor` (already in `apiClient.requestInterceptors`) injects `Idempotency-Key: UUID().uuidString`. No new code, no opt-in. Phase 7 tests do not need to assert idempotency-key injection — it is already covered by `IdempotencyInterceptorTests.swift`.

### `#if DEBUG`-gated mock fixture registries
**Source:** `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` lines 17-101, `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift` lines 46-201, `validationLedger/App/AppContainer.swift` lines 451-456
**Apply to:** `MockLoadFixtureRegistry.swift`
```swift
#if DEBUG
import Foundation

enum MockLoadFixtureRegistry {
    static func registerAppDefaults() { /* register handlers */ }
}
#endif
```
The triple-gate at `AppContainer.swift:451-456` (DEBUG + `.mock` config + not `-MockOTPRoleForUITest`) is preserved; the new call sits adjacent to the existing `MockDefaultFixtures.registerAppDefaults()` line.

### `.serialized` Swift Testing suite for tests that touch `MockURLProtocol`
**Source:** `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` lines 12-19, 41-64
**Apply to:** `LoadEndpointsTests`, `MockURLProtocolLatencyTests`, `MockURLProtocolForcedFailureTests`
```swift
@Suite("…", .serialized)
struct …Tests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("…")
    func body() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        // …
    }
}
```
- `.serialized` is mandatory whenever the test mutates the global `MockURLProtocol._handlers` array — WR-01 lock guards the registry but cannot guard against test-A's handler observing test-B's request.
- `MockURLProtocol.reset()` at top of every test body, plus `defer { MockURLProtocol.reset() }` for clean teardown.

### Fixture-loading via `FixtureLoader`
**Source:** `validationLedgerTests/Networking/FixtureLoader.swift` lines 11-27
**Apply to:** Every Phase 7 test that decodes JSON.
```swift
let data = try FixtureLoader.loadFixture("loads-list-broker")
let decoder = APIClient.defaultDecoder()
let response = try decoder.decode(LoadListEndpoint.Response.self, from: data)
```
`FixtureLoader` already resolves `validationLedgerTests/Networking/Fixtures/*.json` via the subdirectory fallback (line 19) — no Xcode project changes required for new fixture files **provided the fixtures are added to the test target's Resources phase** (the planner must flag this in the Xcode project step).

### Test target import + `@testable`
**Source:** Every test in `validationLedgerTests/Networking/` — e.g. `DeviceChallengeEndpointTests.swift` lines 12-14
**Apply to:** Every new test file.
```swift
import Testing
import Foundation
@testable import validationLedger
```
Swift Testing (`import Testing`), not XCTest. `@testable import validationLedger` to reach internal types. UI tests use XCTest in a separate target — Phase 7 has no UI tests.

---

## No Analog Found

Files with no close existing match — planner should use RESEARCH.md patterns + the indications below.

| File | Role | Data Flow | Reason / Where the Pattern is Defined |
|------|------|-----------|---------------------------------------|
| `validationLedger/Core/Load/VerificationState.swift` (custom fail-closed `init(from:) throws`) | model | transform | No v1.0 enum currently has decoder-layer-degrade-on-unknown behavior. `RejectionReasonCode` is the closest cousin but does call-site degrade (forbidden by D-09). RESEARCH §"Pattern 4: Fail-closed closed-enum decode (NET-NEW for v1.1)" specifies the pattern; this PATTERNS.md "Pattern Assignments → VerificationState" block contains the implementation excerpt to copy. |
| `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` (additive latency + forced-failure overloads) | middleware | request-response | The existing `MockURLProtocol` has only synchronous, instant, success-or-404 handlers (lines 44-58). No latency injection, no `client?.urlProtocol(_:didFailWithError:)` failure path exists in v1.0. RESEARCH §"Code Examples → additive latency/failure injection" and this PATTERNS.md "MockURLProtocol" block describe the additive overloads. Append-only at file end; do NOT edit lines 18-58 (SC #5). |
| `validationLedger/Core/Load/RoleLoadPolicy.swift` (`(Role, LoadStatus) → [LoadAction]` table) | service (rule table) | request-response | CONTEXT.md mentions `KYCFlowSequencer` as a v1.0 analog but it does **not exist in the source tree** (verified via `find`). The closest existing pure-rule resolver is `RejectionReasonCode.copy(for:)` — single axis (`String → String`), not the two-axis `(Role, LoadStatus) → [LoadAction]` table this requires. The "Pattern Assignments → RoleLoadPolicy" block above defines the structure; RESEARCH §"Pattern 3" confirms it as a net-new pattern. |

---

## Metadata

**Analog search scope:**
- `validationLedger/Core/Networking/` — APIEndpoint, APIClient, all 8 shipped endpoint conformers, 4 interceptors, all 4 mock files
- `validationLedger/Core/Identity/KYC/` — RejectionReasonCode, KYCSession, KYCUploader (for aggregate value type shape)
- `validationLedger/Core/Attestation/` — TrustTier, AttestationStatus (closed-enum analogs)
- `validationLedger/Core/Auth/` — checked for service/coordinator patterns; none used directly in Phase 7
- `validationLedger/Roles/Role.swift` — consumed by `RoleLoadPolicy` and `LoadListEndpoint`
- `validationLedger/App/AppContainer.swift` — DEBUG block at lines 440-456
- `validationLedgerTests/Networking/` — FixtureLoader, all Phase 2-4 endpoint tests, MockURLProtocolRegistryTests, EndpointEncodingTests
- `validationLedgerTests/KYC/RejectionReasonCodeTests.swift` — exhaustive-vocabulary sweep template
- `validationLedgerTests/Networking/Fixtures/*.json` — all 24 existing JSON fixtures

**Files scanned:** ~50 source files + ~24 fixture files

**Pattern extraction date:** 2026-05-19
