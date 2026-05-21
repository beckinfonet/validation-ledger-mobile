# Phase 7: Load Domain Model & Mock Contract — Research

**Researched:** 2026-05-19
**Domain:** Contract-first iOS Swift domain modeling + additive extension of a shipped synchronous `URLProtocol`-based mock matcher
**Confidence:** HIGH — every claim below is grounded either in the v1.0 source tree directly (`validationLedger/Core/Networking/*.swift`) or in milestone-level research already grounded in that source. No training-data hypotheses; no library evaluation (this phase adds zero dependencies).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Status Enum Scope**
- **D-01:** `LoadStatus` is a full-lifecycle enum: primary path `draft, posted, tendered, accepted, dispatched, inTransit, delivered`; side-states `rejected, expired, cancelled`; post-delivery `podCaptured, invoiced, funded` are **display-only** (v1.1 has no interactive transitions into the last three).
- **D-02:** `Load` carries `stateHistory: [LoadStatusEvent]` — each event is `{ status, timestamp, actor: LoadParty? }`. LOAD-06 status timeline renders from this array.

**Action Policy Table (`RoleLoadPolicy`)**
- **D-03:** Tender gate is `posted`-only. `post` moves `draft → posted`; `tender` acts only on a `posted` load. Single linear timeline — no direct `draft → tendered`.
- **D-04:** `retender` (ACTION-02) is **not** a distinct `LoadAction`. After reject/expiry the load returns to `posted`, which already affords `tender`. Retender = `tender` invoked again. Prior rejected/expired tenders are recorded in `stateHistory`.
- **D-05:** ACTION-05 status advancement is a **single** `LoadAction.advanceStatus`; the target state is derived as the next step in the canonical order. `RoleLoadPolicy` returns `[.advanceStatus]`, not three per-transition cases.
- **D-06:** `RoleLoadPolicy` collapses 5 roles to 3 surfaces: Shipper ≡ Broker (`post`, `tender`, `cancel`), Carrier ≡ Dispatch (`accept`, `reject`, `advanceStatus`), Factoring = empty for every state.

**Trust Data Model**
- **D-07:** `TrustNode` carries **typed** verification-basis fields — `kycCompletedAt: Date?`, `deviceBindingStatus: DeviceBindingStatus`, `usdotNumber: String?` + `usdotAuthorityStatus`, `priorRelationshipCount: Int` (or a small typed list). Fixed known set; iOS UI controls presentation.
- **D-08:** `ChainOfTrust = { nodes: [TrustNode], edges: [TrustEdge], integrity: ChainIntegrity }`. `TrustEdge` carries handoff/tender detail (TRUST-04) and its own edge-level flag state. `ChainIntegrity` = verdict enum (indicative: `clean / caution / compromised`) + human-readable `reason` + implicated node/edge IDs. **Embedded in `LoadDetailEndpoint.Response`** — one round-trip, no separate graph fetch.
- **D-09:** `VerificationState` is a closed enum `{ verified, pending, unverified, flagged }`. Decoding fails **closed**: unknown/unrecognized JSON value → `unverified`; **missing** field → hard decode error. No client code path may upgrade trust from local logic.

**Fixture Scenarios**
- **D-10:** Fixtures are a **coherent fraud-detection narrative**, not minimal mechanical coverage — a named-load library where every load tells a story that exercises the platform thesis.
- **D-11:** **One shared consistent world** — single underlying load set. Each role's `loads-list-{role}.json` is that role's view onto the same loads. The 5 role list fixtures are not independent.
- **D-12:** Named-load library collectively covers every `LoadStatus`, all four `VerificationState`, all `ChainIntegrity` verdicts, every action path. Planner finalizes IDs and count.
- **D-13:** **All three PROJECT.md fraud archetypes** get a distinct flagged load — double-/triple-brokering, chameleon carrier, factoring fraud. Same render mechanism (flagged node/edge + `integrity.reason`); no model change.
- **D-14:** Mechanical fixtures: per-role empty-list, server-error response, injected-latency (slow), action-failure fixtures (409 conflict, 422 validation, timeout). Each exercised by a unit test. Exact HTTP codes are a planner detail.

**Contract Shape (Locked)**
- **D-15:** **Role-in-path URL scheme** — `GET /loads/{role}`, `GET /loads/{id}`, `POST /loads/{id}/{action}`. `MockURLProtocol.registerFixture` matches on `request.url?.path` only (verified `MockFixture.swift:23`).
- **D-16:** **`LoadListEndpoint.Response` is a paginated envelope from day one** — `{ loads: [Load], nextCursor: String? }`. Single-page fixtures use `decodeIfPresent`-style handling for `nextCursor`.
- **D-17:** New load fixtures registered via dedicated `MockLoadFixtureRegistry` mirroring `MockOTPRoleFixtureRegistry`. Called from the DEBUG-gated block in `AppContainer.init`. `MockDefaultFixtures` is NOT extended.
- **D-18:** All `Core/Load/` types are pure `Decodable & Sendable` value types. **No client-derived trust field.** `APIClient`, `APIEndpoint`, `IdempotencyInterceptor` are **UNCHANGED**; `MockURLProtocol` is extended **additively** only.
- **D-19:** `LoadActionEndpoint` is a POST → automatically picks up the shipped `IdempotencyInterceptor`.

### Claude's Discretion
The planner / researcher may finalize:
- Exact `ChainIntegrity` verdict enum cases (indicative: `clean / caution / compromised`).
- Exact named-load IDs and the precise count of fixture loads (D-12 set is indicative).
- Exact HTTP status codes for the failure fixtures (409/422/timeout are indicative).
- The latency / forced-failure injection mechanism on `MockURLProtocol` (additive; must not change existing API per D-18).
- Whether `priorRelationshipCount` is a bare `Int` or a small `[PriorRelationship]` typed list.
- snake_case ↔ camelCase / ISO-8601 decoding strategy — follow the v1.0 house pattern.

### Deferred Ideas (OUT OF SCOPE)
No scope-creep ideas emerged in discussion — every gray area resolved into a Phase 7 contract decision. Roadmap/PROJECT.md-deferred items (real-time, push, real backend, background URLSession, crash/analytics vendor) are unrelated to this phase. The `device-ci-biometric-infra.md` carried v1.0 todo is unrelated and NOT folded.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **LOAD-01** | Load-domain mock endpoints + fixtures: `GET /loads/{role}`, `GET /loads/{id}`, `POST /loads/{id}/{tender,accept,reject,status,post,cancel}`; per-role + per-state fixtures incl. empty, error, latency, action-failure | §"Standard Stack" (3 endpoints + registry + matrix); §"Architecture Patterns" (Pattern 1, 2, 5); §"Code Examples" (LoadListEndpoint, LoadActionEndpoint, additive latency/failure injection); §"Shared-World Fixture Roster" (D-10/11/12/13 named library); §"Mechanical Failure HTTP Codes" (D-14 thread) |
| **LOAD-02** | `Core/Load/` domain model — `Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy` as `Decodable & Sendable` value types implementing the full load state machine | §"Core/Load/ File Inventory" (8 files); §"Code Examples" (fail-closed `VerificationState` decoder, `RoleLoadPolicy` table, `LoadStatusEvent` shape); §"Architecture Patterns" (Pattern 3 — policy as pure data table) |

Two requirements, both Phase 7 exclusively. Per the Phase 7 success criteria, both must be satisfied by tests-passing before any v1.1 UI screen can begin. Phases 8-10 consume LOAD-01 and LOAD-02 unchanged.
</phase_requirements>

---

## Summary

Phase 7 is the contract-first foundation for v1.1. It delivers **no UI**, but every UI screen in Phases 8-10 decodes types this phase freezes. The work splits into four mechanical deliverables, all grounded in proven v1.0 patterns:

1. **`Core/Load/` domain kernel** — 8 small `Decodable & Sendable` files (one type per file, mirroring `Core/Identity/KYC/`), with the only novel pattern being a fail-closed custom `init(from:)` on `VerificationState` (D-09).
2. **3 `APIEndpoint` conformers** in `Core/Networking/Endpoints/` — exact same `nonisolated public struct` shape as `KYCStatusEndpoint` (GETs use `EmptyBody`; the POST `LoadActionEndpoint` auto-inherits `IdempotencyInterceptor`).
3. **`MockLoadFixtureRegistry`** — a parallel of `MockOTPRoleFixtureRegistry`, registered from the existing DEBUG-gated block in `AppContainer.init:451-456` where `MockDefaultFixtures.registerAppDefaults()` is already called. `MockDefaultFixtures` itself is NOT extended.
4. **Additive latency / forced-failure injection on `MockURLProtocol`** — the one genuinely net-new piece. Two new `register*` overloads that wrap the existing handler closure with `Task.sleep(...)` and/or a substituted error response, leaving the byte-identical existing `register(_:)`, `reset()`, `registerFixture(for:path:method:statusCode:body:)` API in place (success criterion #5).

**Primary recommendation:** Implement the four deliverables in dependency order (domain model → endpoints → fixture registry → MockURLProtocol latency/failure extension → fixtures and tests). The shared-world named-load library (12 loads recommended below) is authored as a product surface, not throwaway test data — Phases 8-9 render these exact fixtures in the demo. Every claim below is verified against the v1.0 source tree files cited in CONTEXT.md; the milestone-level v1.1 research (`SUMMARY.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `STACK.md`) is treated as authoritative and not re-relitigated.

## Architectural Responsibility Map

This phase delivers no user-facing surface; the entire scope is contract-layer + mock-layer + domain-layer code. The map shows where each piece lives so the planner can sanity-check task assignments.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Load value types (`Load`, `ChainOfTrust`, `TrustNode`, `TrustEdge`, `LoadStatusEvent`, etc.) | Domain (`Core/Load/`) | — | Shared by all 5 roles + `AppContainer` + future M3 eBOL; lives in `Core/` so the `no_cross_feature_import` lint rule never fires (verified pattern: `Core/Identity/`, `Core/Auth/`, `Core/KeyStore/`). |
| Enums: `LoadStatus`, `LoadAction`, `VerificationState`, `ChainIntegrity`, `DeviceBindingStatus`, `USDOTAuthorityStatus` | Domain (`Core/Load/`) | — | Closed sets, `Decodable & Sendable`, zero behavior beyond decode. |
| `RoleLoadPolicy.actions(for:status:)` policy table | Domain (`Core/Load/`) | — | Pure `(Role, LoadStatus) → [LoadAction]` function — no UIKit dependency, exhaustively unit-testable. Analog: `KYCFlowSequencer` (v1.0 pattern). |
| `LoadListEndpoint`, `LoadDetailEndpoint`, `LoadActionEndpoint` | Networking contract (`Core/Networking/Endpoints/`) | — | Exact `nonisolated public struct` shape as the 7 shipped v1.0 endpoints; `APIClient.request<E>` accepts them with zero change. |
| Pagination envelope (`{loads:[Load], nextCursor:String?}`) | Networking contract | — | A `Decodable & Sendable` nested struct on `LoadListEndpoint.Response` — D-16. |
| Fail-closed `VerificationState` custom decoder | Domain (`Core/Load/VerificationState.swift`) | — | Net-new pattern: no v1.0 enum currently has unknown-value-defaults-to-X behavior. `RejectionReasonCode` (the closest analog) implements degrade-on-unknown at the *call site*, not in `init(from:)` — D-09 requires it in the decoder so no consumer can bypass it. |
| `MockLoadFixtureRegistry` (DEBUG-only) | Mock (`Core/Networking/Mock/`) | — | Parallel of `MockOTPRoleFixtureRegistry.swift`; registers per-role-list + per-state-detail + action handlers on `MockURLProtocol`. Called from `AppContainer.init:451-456` DEBUG block. |
| `MockURLProtocol` latency / forced-failure injection | Mock (`Core/Networking/Mock/`) | — | **The one byte-additive change to a shipped Mock file.** Two new register* overloads — never alter the existing `register(_:)`, `reset()`, `registerFixture(...)` API. Success criterion #5. |
| JSON fixtures (per-role list, per-state detail, action outcomes) | Test bundle (`validationLedgerTests/Networking/Fixtures/`) | — | Same FixtureLoader bundle pattern as v1.0 KYC fixtures. |
| Composition wiring | App (`App/AppContainer.swift`) | — | One DEBUG-block addition adjacent to `MockDefaultFixtures.registerAppDefaults()` call. This is the ONLY non-`Core/Load/`-or-new-file edit in Phase 7. |

**No UI tier in this phase.** The 5 role tab-bar controllers, the `Features/Loads/` module, every coordinator and ViewModel — all Phase 8-10 work. The plan-checker must reject any Phase 7 task that creates files under `Features/` or `Roles/`.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | iOS 17 SDK | `Decodable`, `Encodable`, `Date`, `JSONDecoder` | First-party; matches deployment target exactly. `Decodable & Sendable` is the project-wide value-type contract for wire types. [VERIFIED: source — every `Core/Networking/Endpoints/*.swift`] |
| Swift Testing | bundled with Xcode 26.x | Test framework | The v1.0 test suite is 100% Swift Testing (`@Suite`, `@Test`, `#expect`). [VERIFIED: source — `validationLedgerTests/Networking/APIClientEndpointTests.swift:8-13`] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `APIClient` + `APIEndpoint` (in-repo) | v1.0 | Typed endpoint facade | The 3 new endpoints conform to `APIEndpoint`; `APIClient.request<E>` accepts them unchanged. [VERIFIED: source — `Core/Networking/APIClient.swift:39`] |
| `MockURLProtocol` + `MockFixture.registerFixture` (in-repo) | v1.0 | Mock matcher | Path+method-keyed; the new endpoints "just work" once registered. [VERIFIED: source — `MockURLProtocol.swift`, `MockFixture.swift`] |
| `IdempotencyInterceptor` (in-repo) | v1.0 | POST/PUT idempotency-key injection | `LoadActionEndpoint` (POST) inherits this with zero new wiring — D-19. [VERIFIED: source — `Core/Networking/Interceptors/IdempotencyInterceptor.swift:17-29`] |
| `FixtureLoader` (in-repo, test target) | v1.0 | Loads JSON files from the test bundle | Same call shape — `FixtureLoader.loadFixture("load-detail-clean-delivered")`. [VERIFIED: source — `validationLedgerTests/Networking/FixtureLoader.swift`] |

### Alternatives Considered
None for Phase 7 — this is a contract-modeling phase with all decisions locked in CONTEXT.md and zero new dependencies. The trust-graph rendering decision (UIView+CAShapeLayer vs SpriteKit vs Grape) is Phase 9 scope and was settled in `.planning/research/STACK.md`.

**Installation:**
```bash
# No new dependencies. Package.swift and Package.resolved are unchanged.
# The only "installs" are:
#  - 8 new files under validationLedger/Core/Load/
#  - 3 new files under validationLedger/Core/Networking/Endpoints/
#  - 1 new file under validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
#  - N JSON fixtures under validationLedgerTests/Networking/Fixtures/
#  - Additive edits to MockURLProtocol.swift + AppContainer.swift (DEBUG block)
```

**Version verification:** Zero packages added or bumped this phase. `Package.swift` unchanged (Nuke 13.0.2 + SwiftLintPlugins 0.63.2 remain the only two SwiftPM deps). [VERIFIED: `.planning/research/STACK.md` §"Version Compatibility"]

## Package Legitimacy Audit

Not applicable — Phase 7 installs zero external packages. Every type is built on Foundation + the in-repo v1.0 networking layer. The `Package.swift` audit from v1.0 closure stands.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│ TESTS (validationLedgerTests/)                                         │
│  Decode tests ──────────────────► JSON fixtures (Fixtures/loads-*.json)│
│  Policy tests ──► RoleLoadPolicy.actions(for:status:)                  │
│  Mock-injection tests ──► MockURLProtocol latency/forced-failure       │
│  Swap-smoke test ──► .live config + new endpoints still compile        │
└─────────────────────────────────────┬────────────────────────────────┘
                                      │ load via FixtureLoader,
                                      │ register via MockURLProtocol
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Core/Networking/Mock/  (DEBUG only)                                    │
│                                                                        │
│  MockLoadFixtureRegistry.registerAll()    ── NEW (Phase 7)             │
│    ├─ register(GET /loads/{role}, role-list fixtures)  (5 roles)       │
│    ├─ register(GET /loads/{id},   detail-per-load fixtures)            │
│    └─ register(POST /loads/{id}/{action}, action-outcome fixtures)     │
│                                                                        │
│  MockURLProtocol  ── ADDITIVELY EXTENDED (Phase 7)                     │
│    Existing API: register(_:), reset(), registerFixture(...)  UNCHANGED│
│    NEW:  registerFixture(..., latency: TimeInterval)                   │
│    NEW:  registerForcedFailure(for: path:, method:, kind: FailureKind) │
│                                                                        │
└─────────────────────────────────────┬────────────────────────────────┘
                                      │ matches request.url?.path + method
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Core/Networking/  (UNCHANGED — APIClient, APIEndpoint, MockFixture)    │
│  APIClient.request<E: APIEndpoint>(...) async throws -> E.Response     │
│   ├─ buildRequest (snake_case body encode + ISO8601 dates)             │
│   ├─ requestInterceptors: [IdempotencyInterceptor]  ← POST auto-keys   │
│   ├─ responseInterceptors: [Retry, Auth401, AttestationError]          │
│   └─ decode (snake_case → camelCase + ISO8601)                         │
└─────────────────────────────────────┬────────────────────────────────┘
                                      │ E.Response: Decodable & Sendable
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Core/Networking/Endpoints/  (3 NEW conformers)                         │
│                                                                        │
│  LoadListEndpoint(role: Role)                                          │
│    path = "/loads/\(role.rawValue)"                                    │
│    method = .get   body = nil                                          │
│    Response = { loads: [Load], nextCursor: String? }                   │
│                                                                        │
│  LoadDetailEndpoint(loadID: String)                                    │
│    path = "/loads/\(loadID)"                                           │
│    method = .get   body = nil                                          │
│    Response = LoadDetail   (carries Load + ChainOfTrust)               │
│                                                                        │
│  LoadActionEndpoint(loadID: String, action: LoadAction, payload: ...)  │
│    path = "/loads/\(loadID)/\(action.pathSegment)"                     │
│    method = .post   body = ActionRequestBody                           │
│    Response = LoadActionResult  (returned updated Load)                │
│                                                                        │
└─────────────────────────────────────┬────────────────────────────────┘
                                      │ decodes into ↓
                                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Core/Load/  (NEW — 8 files)                                            │
│                                                                        │
│  Load.swift           ── Load (the aggregate value type)                │
│  LoadStatus.swift     ── enum (full lifecycle, D-01)                    │
│  LoadAction.swift     ── enum (post,tender,accept,reject,cancel,        │
│                                  advanceStatus) — D-03/04/05            │
│  LoadStatusEvent.swift── { status, timestamp, actor: LoadParty? } — D-02│
│  ChainOfTrust.swift   ── ChainOfTrust + TrustNode + TrustEdge — D-07/08 │
│  VerificationState.swift── closed enum + fail-closed init(from:) — D-09 │
│  ChainIntegrity.swift ── verdict enum + reason + implicated IDs         │
│  RoleLoadPolicy.swift ── pure (Role, LoadStatus) → [LoadAction] — D-06  │
│                                                                        │
│  All types: Decodable & Sendable. Pure values. No client trust upgrade.│
└──────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
validationLedger/
├── Core/
│   ├── Load/                                    # NEW — domain kernel
│   │   ├── Load.swift                           #   Load (aggregate)
│   │   ├── LoadStatus.swift                     #   enum (D-01 full lifecycle)
│   │   ├── LoadAction.swift                     #   enum (D-03/04/05)
│   │   ├── LoadStatusEvent.swift                #   { status, timestamp, actor? } (D-02)
│   │   ├── ChainOfTrust.swift                   #   ChainOfTrust + TrustNode + TrustEdge (D-07/08)
│   │   ├── VerificationState.swift              #   closed enum + fail-closed init(from:) (D-09)
│   │   ├── ChainIntegrity.swift                 #   verdict + reason + implicated IDs (D-08)
│   │   └── RoleLoadPolicy.swift                 #   pure table (D-06)
│   │
│   └── Networking/
│       ├── Endpoints/
│       │   ├── LoadListEndpoint.swift           # NEW (GET /loads/{role}, paginated envelope D-16)
│       │   ├── LoadDetailEndpoint.swift         # NEW (GET /loads/{id}, embeds ChainOfTrust D-08)
│       │   └── LoadActionEndpoint.swift         # NEW (POST /loads/{id}/{action}, auto-IDK D-19)
│       └── Mock/
│           ├── MockLoadFixtureRegistry.swift    # NEW (mirrors MockOTPRoleFixtureRegistry, D-17)
│           └── MockURLProtocol.swift            # MODIFIED additively (D-18, success criterion #5)
│
└── App/
    └── AppContainer.swift                       # MODIFIED — one line in DEBUG block (D-17)

validationLedgerTests/
└── Networking/
    └── Fixtures/                                # NEW JSON files
        ├── loads-list-shipper.json
        ├── loads-list-broker.json
        ├── loads-list-carrier.json
        ├── loads-list-dispatch.json
        ├── loads-list-factoring.json
        ├── loads-list-empty.json                # mechanical: empty per-role
        ├── load-detail-{vl-id}.json             # one per named load in the library
        ├── load-action-success.json
        ├── load-action-conflict-409.json
        ├── load-action-validation-422.json
        └── load-action-server-error-500.json

validationLedgerTests/
├── Load/                                        # NEW test directory
│   ├── LoadDomainDecodeTests.swift              # fixture-decode coverage
│   ├── VerificationStateDecoderTests.swift      # fail-closed edge cases (D-09)
│   ├── RoleLoadPolicyTests.swift                # 5 roles × every LoadStatus
│   ├── ChainOfTrustDecodeTests.swift            # 3 fraud archetypes + clean
│   └── LoadStateMachineSanityTests.swift        # post→tendered→accepted→… reachability
└── Networking/
    ├── LoadEndpointsTests.swift                 # 3 endpoints × success/empty/error
    ├── MockURLProtocolLatencyTests.swift        # additive latency injection (SC #4)
    ├── MockURLProtocolForcedFailureTests.swift  # additive forced-failure (SC #4)
    └── MockLiveSwapSmokeTest.swift              # SC #5 — config flip still compiles+passes
```

### Pattern 1: `nonisolated public struct` APIEndpoint conformer

**What:** Each of the 3 new endpoints is a `nonisolated public struct` with `path: String`, `method: HTTPMethod`, `body: RequestBody?` (with `RequestBody = EmptyBody` for GETs), and a `Decodable & Sendable` nested `Response` type. Exact shape mirrors all 7 shipped v1.0 endpoints. [VERIFIED: source — `KYCStatusEndpoint.swift:10-34`, `OTPVerifyEndpoint.swift:10-57`, `KYCSubmitEndpoint.swift:16-46`]

**When to use:** Every new endpoint. There is no other accepted shape in this codebase.

**Example:** See "Code Examples" → "LoadListEndpoint" below.

### Pattern 2: snake_case wire + `.convertFromSnakeCase` decoder + explicit `CodingKeys` for trailing acronyms

**What:** The v1.0 house pattern is: JSON is snake_case on the wire; `APIClient` constructs its decoder with `keyDecodingStrategy = .convertFromSnakeCase` and `dateDecodingStrategy = .iso8601`. [VERIFIED: source — `APIClient.swift:110-115`]. Endpoints whose fields end in an acronym (`artifactID`, `userID`, `usdotID`) add an **explicit `CodingKeys` enum with camelCase raw values** (`case userID = "userId"`) to pin behavior against any future toolchain variation in `.convertToSnakeCase`'s trailing-acronym handling. [VERIFIED: source — `KYCStatusEndpoint.swift:18-24`, `OTPVerifyEndpoint.swift:43-48`]

**When to use:** Every new field. Use `.convertFromSnakeCase` by default; add explicit `CodingKeys` *only* for trailing-acronym fields (e.g. `partyID`, `loadID`, `usdotNumber` — the last one is `usdot_number` which is unambiguous, no override needed; but `partyID` → `party_id` *is* implementation-defined, override it).

**Trade-offs:** (+) No per-field annotation noise for the 95% of fields that don't contain acronyms. (+) Wire stays consistent with the backend's snake_case convention (post-v1.1 when it lands). (−) Reviewers must remember to override `CodingKeys` for trailing-acronym fields; mitigated by the established v1.0 precedent.

### Pattern 3: Pure policy table extracted from UIKit (analog: `KYCFlowSequencer`)

**What:** `RoleLoadPolicy` is a `public enum` with a single `public static func actions(for role: Role, status: LoadStatus) -> [LoadAction]` that exhaustively switches on `(role, status)`. Zero UIKit imports. Exhaustively unit-tested by enumerating `Role.allCases × LoadStatus.allCases`.

**When to use:** Any rule that varies across two finite axes and must be consistent everywhere it's read. v1.0's analog: `KYCFlowSequencer` (a pure rule struct extracted from `KYCCoordinator` so the rule logic is unit-tested without UIKit). [VERIFIED: `.planning/research/ARCHITECTURE.md` §Pattern 2]

**Trade-offs:** (+) Exhaustive coverage is cheap (5 × 13 = 65 cases). (+) Adding a role or status is a one-line table edit, plus expanded tests. (−) None at this size.

### Pattern 4: Fail-closed closed-enum decode (NET-NEW for v1.1)

**What:** `VerificationState` is `Decodable` but NOT a simple `String` raw-value enum (which would `throw` on unknown). Instead it implements a custom `init(from:) throws` that decodes the wire string, looks it up in a known-set switch, and defaults unrecognized values to `.unverified` (least-trusted). A **missing** field on the parent throws `keyNotFound` (the synthesized container.decode behavior); only a **present-but-unknown** string degrades.

**When to use:** Closed-enum decoders for security-critical fields where the wire vocabulary may grow but the client must never silently upgrade trust. `VerificationState` is the only Phase 7 use; the pattern documents itself for any future copy.

**Trade-offs:** (+) Decoder-layer enforcement — no consumer can bypass it. (+) Unit-testable by feeding `{"verificationState": "bogus"}` JSON and asserting decode succeeds with `.unverified`. (−) Slightly more code than a `String, Decodable` raw enum; that's the cost of the security primitive.

**Why this is net-new:** The closest v1.0 analog is `RejectionReasonCode` (`Core/Identity/KYC/RejectionReasonCode.swift:30`) — but it is a vanilla `String, Decodable` enum that throws on unknown, with degrade-on-unknown logic moved to the call site (`RejectionReasonCode.copy(for: rawCode)` uses `RejectionReasonCode(rawValue:) ?? generic`). D-09's "no client code path may upgrade trust" rules out call-site-only degrade — the decoder itself must be the gate. [VERIFIED: source — `RejectionReasonCode.swift:107-114`]

### Pattern 5: Per-role mock fixture registry (analog: `MockOTPRoleFixtureRegistry`)

**What:** `MockLoadFixtureRegistry` is a DEBUG-only `enum` with a static `registerAll()` (or `registerForAppDefaults()`) method that calls `MockURLProtocol.register { req in ... }` for each load-domain path. The registry mirrors `MockOTPRoleFixtureRegistry.swift` exactly in structure — it does NOT use `MockFixture.registerFixture<E>` (which is test-target convenience), it uses the underlying `MockURLProtocol.register(_:)` directly so it can vary response by URL-path-suffix (the role segment). [VERIFIED: source — `MockOTPRoleFixtureRegistry.swift:22-101`]

**When to use:** Any DEBUG organic tap-through (non-test-driven) registration. Tests still use `registerFixture<E>` for individual fixture pinning.

**Anti-Patterns to Avoid**

- **Adding load cases to `MockDefaultFixtures.dispatchHandler`'s switch.** D-17 explicitly rejects this — `MockDefaultFixtures` would grow unbounded across milestones and cannot vary response by role. The parallel `MockLoadFixtureRegistry` keeps the load domain isolated.
- **`switch load.status` anywhere outside `RoleLoadPolicy`.** Pitfall 7 — gating logic leaking into VCs or cells. Already a v1.1 lint concern in PITFALLS.md.
- **Defaulting `VerificationState` to `.verified` on missing/unknown.** D-09 fail-closed primitive; an unverified default is a fraud vector.
- **Embedding `ChainOfTrust` in a separate `GET /parties/{id}/verification` fixture for the graph.** D-08 locks `ChainOfTrust` inside `LoadDetailEndpoint.Response` — one round-trip, no graph-level loading state.
- **Hardcoded fixture load IDs in product code** (vs. test code). Pitfall 9 — over-fitting to fixtures. Use opaque `String` `loadID`s; only test code may reference literal IDs.
- **Extending `MockURLProtocol`'s existing `register(_:)`, `reset()`, or `registerFixture(for:path:method:statusCode:body:)` API surface.** SC #5 — those signatures stay byte-identical. New capability is *additive overloads only*.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP method dispatch | A new networking layer or URLSession wrapper | The shipped `APIClient` + `APIEndpoint` | The 3 new endpoints conform to `APIEndpoint`; `APIClient.request<E>` accepts them unchanged. [VERIFIED: `APIClient.swift:39`] |
| Idempotency-key generation/injection on POST | A custom `Idempotency-Key` header builder for `LoadActionEndpoint` | `IdempotencyInterceptor` (already in `apiClient.requestInterceptors`) | The interceptor injects `UUID().uuidString` on every POST/PUT automatically; D-19 is "free" by virtue of LoadAction being a POST. [VERIFIED: source — `IdempotencyInterceptor.swift:17-29`, `AppContainer.swift:476`] |
| JSON decoding strategy | Per-endpoint custom decoders, manual snake_case conversion | The shipped `APIClient.defaultDecoder()` (`.convertFromSnakeCase` + `.iso8601`) | Already wired into every `request<E>` call. [VERIFIED: source — `APIClient.swift:110-115`] |
| Test fixture loading | Custom bundle code, `Bundle(for:)` lookups | `FixtureLoader.loadFixture(_:)` in `validationLedgerTests/Networking/FixtureLoader.swift` | Already resolves the test bundle via a private marker class; supports `Fixtures/<name>.json` subdirectory automatically. [VERIFIED: source — `FixtureLoader.swift:14-26`] |
| URL session protocol-class wiring for mock | A new `MockSession` class or alternative URLProtocol | `MockURLProtocol` (already in `URLSession.protocolClasses` for the `.mock` config) | Path+method matching works as-is; new endpoints register via the same `register(_:)` API. [VERIFIED: source — `MockURLProtocol.swift`, `MockFixture.swift`] |
| Retry / 401 / attestation error handling | New response interceptors for load endpoints | Existing `RetryInterceptor` + `Auth401ResponseInterceptor` + `AttestationErrorResponseInterceptor` (already in `apiClient.responseInterceptors`) | All shipped; ordering is settled. [VERIFIED: source — `AppContainer.swift:477-485`] |
| HTTP 429 rate-limit parsing | A custom rate-limit handler | `NetworkError.rateLimited(retryAfter:)` (already thrown by `APIClient`) | If a load action somehow hits 429, the typed error fires; UI handles it in Phase 10 if needed. [VERIFIED: source — `APIClient.swift:61-64`] |

**Key insight:** Phase 7 is *almost entirely* contract-modeling and JSON authoring. The only genuinely-new code is the 8 `Core/Load/` value types, the 3 endpoint structs, the registry skeleton, and ~50 lines of additive latency/failure-injection on `MockURLProtocol`. Everything else is "use the shipped pattern."

## Runtime State Inventory

> Phase 7 is a greenfield phase — it adds new files and adds one DEBUG line to `AppContainer`. No rename, no refactor, no string-replace. This section is included for completeness with "None" in every category.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore is read or written by Phase 7. The `Core/Load/` types decode from JSON ephemerally in tests and at runtime (in DEBUG via the new registry); no persistence. | None |
| Live service config | None — no external service has anything keyed by a Phase 7 name. The mock backend is in-process. | None |
| OS-registered state | None — no `BGTaskScheduler` IDs, no `launchd` entries, no Task Scheduler tasks added or renamed by Phase 7. | None |
| Secrets/env vars | None — Phase 7 reads no secrets and defines no env vars. The `IdempotencyInterceptor` UUIDs are per-request and ephemeral. | None |
| Build artifacts | None — no `.egg-info`, no compiled binaries with embedded names, no Docker tags. `Package.swift` and `Package.resolved` are unchanged. | None |

**Nothing found in any category — verified by:** direct inspection of the file roster Phase 7 modifies (1 line in `AppContainer.swift` DEBUG block + 1 file `MockURLProtocol.swift` additive only; everything else is net-new files).

## Common Pitfalls

These are scoped to Phase 7 specifically. The full v1.1 PITFALLS.md catalogue covers 10 milestone-wide pitfalls; the 5 most likely to land in Phase 7 are:

### Pitfall 1: The `VerificationState` decoder ships without its fail-closed branch
**What goes wrong:** `VerificationState` is implemented as `enum: String, Decodable, Sendable { case verified, pending, unverified, flagged }` — vanilla. Now a JSON value `"compromised"` (a future server addition) causes the entire `Load` decode to throw, breaking the load list. Or, worse, "fixed" by making the field optional with `verificationState: VerificationState?` defaulting to `.verified` — a fraud vector (PITFALLS Pitfall 3).
**Why it happens:** The vanilla `String, Decodable` form is the shortest path to a decoder, and the explicit fail-closed initializer reads like ceremony.
**How to avoid:** Implement `init(from:) throws` as shown in "Code Examples → Fail-closed VerificationState decoder" below. Pair it with `VerificationStateDecoderTests.swift` covering: known string → expected case; unknown string → `.unverified`; missing field on parent → decode error.
**Warning signs:** Any commit that adds `VerificationState` without a custom `init(from:)`; any test fixture that omits `verification_state` on a party (it must be present per D-09 strict contract).

### Pitfall 2: Latency / forced-failure injection alters the existing `MockURLProtocol` API
**What goes wrong:** SC #5 says the existing `register/reset/registerFixture` API stays byte-identical. A naive implementation refactors `MockURLProtocol.register(_:)` to accept an optional `latency:` parameter — and now every Phase 1-5 test that calls `register` without that parameter still compiles but the call shape changed, and `registerFixture(for:path:method:statusCode:body:)` either grows a parameter or gains a sibling that confuses code review.
**Why it happens:** "While I'm in there, let me just add a parameter" is faster than authoring new overloads.
**How to avoid:** Two **net-new** static functions on `MockURLProtocol`:
  - `registerFixture(for:path:method:statusCode:body:latency:)` — superset overload (Swift's default-argument resolution makes the existing 0-latency call sites compile unchanged, BUT a stricter discipline is to define a separate `registerFixtureWithLatency(...)` so the original signature is provably untouched).
  - `registerForcedFailure(for:path:method:kind:)` where `kind` is a new `FailureKind` enum (`.timeout`, `.serverError(code:)`, `.urlError(URLError.Code)`).
The original three functions stay byte-identical. The Phase 7 PR diff for `MockURLProtocol.swift` should be **append-only at file end** — no edits to lines 18-58.
**Warning signs:** Any diff on `MockFixture.swift:14-21` or `MockURLProtocol.swift:26-31`; any test in `validationLedgerTests/Networking/APIClientEndpointTests.swift` (the 7-endpoint sanity suite) needing edits.

### Pitfall 3: Pagination envelope is omitted "because the mock returns one page"
**What goes wrong:** `LoadListEndpoint.Response = [Load]` (a bare array) ships; Phase 8 builds a `UICollectionViewDiffableDataSource` against `[Load]`; the post-v1.1 live swap returns `{loads: [...], next_cursor: "abc"}` and the entire list ViewModel + snapshot needs rework. Pitfall 9 manifested.
**Why it happens:** D-16 is one line and easy to miss when authoring the endpoint.
**How to avoid:** `LoadListEndpoint.Response = LoadListPage` where `LoadListPage` is a nested struct `{ loads: [Load], nextCursor: String? }`. Single-page fixtures simply omit the `next_cursor` key — `decodeIfPresent` handles the missing field (or the synthesized decoder for an optional `String?` does it for free, which is the simpler path). Confirm with a test: `loads-list-broker.json` (no cursor key) decodes with `nextCursor == nil`.
**Warning signs:** `LoadListEndpoint.Response = [Load]`; any fixture JSON whose top-level is `[ ... ]` instead of `{"loads": [...]}`.

### Pitfall 4: `MockDefaultFixtures.dispatchHandler` grows load cases
**What goes wrong:** Someone adds `case ("GET", "/loads/broker"): return make200(body: loadsListBrokerJSON(), ...)` to `MockDefaultFixtures.swift:64` because "it's right there and parallels the OTP path." Now D-17 is violated and (a) `MockDefaultFixtures` grows unboundedly across future milestones, (b) per-role variation is impossible (one handler can't return different bodies for different roles without re-parsing the path), and (c) `MockOTPRoleFixtureRegistry`'s precedent is silently abandoned.
**Why it happens:** `MockDefaultFixtures.dispatchHandler` already has the switch shape and an obvious extension point.
**How to avoid:** Author `MockLoadFixtureRegistry.swift` as a parallel `enum` with a `static func registerAppDefaults()` and call it from `AppContainer.init:451-456` right after the `MockDefaultFixtures.registerAppDefaults()` line. Diff on `MockDefaultFixtures.swift` should be **zero lines** in Phase 7.
**Warning signs:** Any commit touching `MockDefaultFixtures.swift`.

### Pitfall 5: Fixture matrix forgets the "load with `nil` `nextCursor`" + the "load with party missing `kycCompletedAt`" cases
**What goes wrong:** All fixtures populate every optional field; the optional-vs-required modeling in `Load`/`TrustNode` goes untested; the moment the live backend (or a future mock fixture) omits an optional field, a decode failure surfaces in production.
**Why it happens:** Easier to author "full" JSON than to model the optionality boundary.
**How to avoid:** Pick 2-3 named loads in the library where optional fields are deliberately omitted. Recommended: VL-1003 (the `posted` load awaiting tender) has `respondByAt: nil` because nothing was tendered yet; VL-1008 (the `draft` load) has `chain.edges: []` because no handoffs have occurred; one `TrustNode` somewhere has `kycCompletedAt: nil` (pending KYC). Round these into the decode tests explicitly.
**Warning signs:** Every fixture has every optional field populated; no test asserts an optional-absent decode.

## Code Examples

Verified patterns from v1.0 source + the additive design for Phase 7.

### LoadListEndpoint — paginated envelope (D-16, role-in-path D-15)

```swift
// validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift
// NEW (Phase 7). Mirrors KYCStatusEndpoint shape exactly.

import Foundation

nonisolated public struct LoadListEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        public let loads: [Load]
        public let nextCursor: String?

        // The synthesized decoder + .convertFromSnakeCase handles `next_cursor` → `nextCursor`
        // automatically; the optional `String?` makes the field's absence a successful decode.
        // No explicit CodingKeys needed — `nextCursor` is unambiguous under .convertFromSnakeCase
        // (no trailing acronym).
    }

    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init(role: Role) {
        // D-15: role-in-path, NOT a query string. MockURLProtocol matches request.url?.path only.
        self.path = "/loads/\(role.rawValue)"
    }
}
```

### LoadDetailEndpoint — embeds ChainOfTrust (D-08)

```swift
// validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift
// NEW (Phase 7).

import Foundation

nonisolated public struct LoadDetailEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        public let load: Load
        public let chainOfTrust: ChainOfTrust  // D-08: embedded, one round-trip
    }

    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init(loadID: String) {
        self.path = "/loads/\(loadID)"
    }
}
```

### LoadActionEndpoint — POST, auto-IDK (D-19), per-action path segment (D-15)

```swift
// validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift
// NEW (Phase 7). POST → IdempotencyInterceptor auto-injects Idempotency-Key (D-19).

import Foundation

nonisolated public struct LoadActionEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        // Per-action payload. For accept/reject/cancel/post: empty-ish (just a confirmation).
        // For tender: { targetCarrierID, respondByAt }. For advanceStatus: { } (target derived
        // server-side from current load.status — D-05).
        // Concrete shape — finalize in plan; the principle is: typed per action, never untyped JSON.
        public let actorRole: Role
        // ... per-action additional fields ...
    }

    public struct Response: Decodable, Sendable {
        public let load: Load                  // Updated load — Pitfall 4 anti-drift (PITFALLS.md)
        public let chainOfTrust: ChainOfTrust  // Re-supplied because actions may flag/clean the chain
    }

    public let path: String
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(loadID: String, action: LoadAction, body: RequestBody) {
        // D-15: action-in-path. e.g. /loads/VL-1042/tender
        self.path = "/loads/\(loadID)/\(action.pathSegment)"
        self.body = body
    }
}

extension LoadAction {
    /// Lowercased path segment for the URL.
    /// Note: `advanceStatus` (D-05) maps to "status" — backend treats this as "advance by one".
    var pathSegment: String {
        switch self {
        case .post:           return "post"
        case .tender:         return "tender"
        case .accept:         return "accept"
        case .reject:         return "reject"
        case .cancel:         return "cancel"
        case .advanceStatus:  return "status"
        }
    }
}
```

### Fail-closed VerificationState decoder (D-09 — THE security primitive)

```swift
// validationLedger/Core/Load/VerificationState.swift
// NEW (Phase 7). D-09 fail-closed decode.

import Foundation

public enum VerificationState: String, Sendable, CaseIterable {
    case verified
    case pending
    case unverified  // ← the fail-closed default for unknown wire values
    case flagged
}

extension VerificationState: Decodable {
    /// D-09 fail-closed decode:
    ///   - Present + known wire value  → the matching case
    ///   - Present + unknown wire value → `.unverified` (least-trusted)
    ///   - Missing field on the parent  → keyNotFound error (the synthesized
    ///     container.decode behavior on the parent type; this initializer
    ///     never sees a missing field — only present values reach here).
    ///
    /// Rationale: D-09 says trust must never be upgraded from local logic.
    /// A future server addition (e.g. "compromised", "quarantined") must
    /// degrade to least-trusted on this client, not throw and break decode
    /// of the entire Load. A *missing* field, however, IS a hard contract
    /// violation — the server is required to send the field per the LOAD-02
    /// schema.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VerificationState(rawValue: raw) ?? .unverified
    }
}
```

**Tests this must pass (VerificationStateDecoderTests.swift):**

```swift
@Test("Known wire value decodes to matching case")
func known() throws {
    let data = Data(#""verified""#.utf8)
    let state = try JSONDecoder().decode(VerificationState.self, from: data)
    #expect(state == .verified)
}

@Test("Unknown wire value decodes to .unverified (D-09 fail-closed)")
func unknown() throws {
    let data = Data(#""compromised""#.utf8)
    let state = try JSONDecoder().decode(VerificationState.self, from: data)
    #expect(state == .unverified)
}

@Test("Missing field on parent throws keyNotFound (D-09 strict contract)")
func missing() {
    struct Party: Decodable { let verificationState: VerificationState }
    let data = Data("{}".utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    #expect(throws: DecodingError.self) {
        try decoder.decode(Party.self, from: data)
    }
}
```

### `RoleLoadPolicy` — the exhaustive table (D-03/04/05/06)

```swift
// validationLedger/Core/Load/RoleLoadPolicy.swift
// NEW (Phase 7). Pure policy table. Zero UIKit. Exhaustively unit-tested.

import Foundation

public enum RoleLoadPolicy {
    public static func actions(for role: Role, status: LoadStatus) -> [LoadAction] {
        switch (role, status) {

        // ── Shipper ≡ Broker (D-06) ──────────────────────────────────────────
        case (.shipper, .draft),     (.broker, .draft):
            return [.post]                    // D-03 post moves draft → posted
        case (.shipper, .posted),    (.broker, .posted):
            return [.tender, .cancel]         // D-03 tender gate; D-04 retender = tender
        case (.shipper, .tendered),  (.broker, .tendered):
            return [.cancel]                  // can't re-tender while active tender outstanding
        case (.shipper, .accepted),  (.broker, .accepted),
             (.shipper, .dispatched),(.broker, .dispatched),
             (.shipper, .inTransit), (.broker, .inTransit):
            return [.cancel]                  // pre-delivery cancel still available
        case (.shipper, .rejected),  (.broker, .rejected),
             (.shipper, .expired),   (.broker, .expired):
            // After reject/expiry the load is back to `posted` per D-04 — but the
            // current display status may be `rejected`/`expired` briefly if the
            // stateHistory records the transition. v1.1 fixture convention: a
            // rejected/expired tender lands the load back at `posted` for the
            // next action; this row is unreachable in practice but kept exhaustive
            // for safety.
            return [.tender, .cancel]

        // ── Carrier ≡ Dispatch (D-06) ────────────────────────────────────────
        case (.carrier, .tendered),  (.dispatch, .tendered):
            return [.accept, .reject]
        case (.carrier, .accepted),  (.dispatch, .accepted),
             (.carrier, .dispatched),(.dispatch, .dispatched),
             (.carrier, .inTransit), (.dispatch, .inTransit):
            return [.advanceStatus]           // D-05 single action; server derives target

        // ── Factoring (D-06) ─────────────────────────────────────────────────
        case (.factoring, _):
            return []                         // Factoring is view-only for every state

        // ── Terminal / display-only states ───────────────────────────────────
        case (_, .delivered), (_, .cancelled),
             (_, .podCaptured), (_, .invoiced), (_, .funded):
            return []                         // D-01 — no v1.1 transitions

        // ── Everything else: no action ────────────────────────────────────────
        default:
            return []
        }
    }
}
```

**Exhaustive table view (the 5 × 13 matrix the planner uses to verify):**

| Role / Status | draft | posted | tendered | accepted | dispatched | inTransit | delivered | rejected | expired | cancelled | podCaptured | invoiced | funded |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Shipper** | [post] | [tender,cancel] | [cancel] | [cancel] | [cancel] | [cancel] | [] | [tender,cancel] | [tender,cancel] | [] | [] | [] | [] |
| **Broker** | [post] | [tender,cancel] | [cancel] | [cancel] | [cancel] | [cancel] | [] | [tender,cancel] | [tender,cancel] | [] | [] | [] | [] |
| **Carrier** | [] | [] | [accept,reject] | [advanceStatus] | [advanceStatus] | [advanceStatus] | [] | [] | [] | [] | [] | [] | [] |
| **Dispatch** | [] | [] | [accept,reject] | [advanceStatus] | [advanceStatus] | [advanceStatus] | [] | [] | [] | [] | [] | [] | [] |
| **Factoring** | [] | [] | [] | [] | [] | [] | [] | [] | [] | [] | [] | [] | [] |

D-06 verification: Factoring row is all `[]`. Shipper row equals Broker row. Carrier row equals Dispatch row. ✓

### Additive latency + forced-failure injection on `MockURLProtocol` (SC #4, SC #5, D-18)

```swift
// validationLedger/Core/Networking/Mock/MockURLProtocol.swift
// Lines 18-58 UNCHANGED. The following extension is APPENDED to file end.
// SC #5: existing register/reset/registerFixture API stays byte-identical.

import Foundation

extension MockURLProtocol {

    /// Failure kinds the mock can inject. Maps to NetworkError outcomes the real
    /// transport would produce.
    public enum InjectedFailure: Sendable {
        /// Returns the given HTTP status with an optional body (e.g. 409 conflict
        /// with a JSON error body; 422 validation with field-error JSON; 500 server).
        case http(statusCode: Int, body: Data)
        /// Simulates a transport-level URLError (e.g. .timedOut, .notConnectedToInternet).
        /// MockURLProtocol delivers this via `client?.urlProtocol(self, didFailWithError:)`.
        case urlError(URLError.Code)
    }

    /// Register a fixture that responds AFTER `latency` seconds. Wraps the existing
    /// success-fixture path. SC #4: a unit test calls this with latency: 0.2 and
    /// asserts the request takes ≥ 200 ms.
    ///
    /// Existing call site `registerFixture(for:path:method:statusCode:body:)` is NOT
    /// modified — this is a NEW static function alongside it.
    public static func registerFixture<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data,
        headers: [String: String] = ["Content-Type": "application/json"],
        latency: TimeInterval
    ) {
        register { request in
            guard request.url?.path == path,
                  request.httpMethod == method.rawValue else { return nil }
            // The handler closure is @Sendable and synchronous, but MockURLProtocol's
            // startLoading() invokes the matched handler synchronously on the URLSession
            // thread. To inject latency we sleep on that thread — acceptable because
            // MockURLProtocol is DEBUG/test-only, the ephemeral URLSession is dedicated,
            // and the test's `await client.request(...)` is already async.
            //
            // (Implementation detail for the plan: use `Thread.sleep(forTimeInterval:)`
            // inside the handler, or restructure to deliver the response asynchronously
            // via the URLProtocol client API on a delayed dispatch. Either works; the
            // planner picks one.)
            Thread.sleep(forTimeInterval: latency)
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (resp, body)
        }
    }

    /// Register a forced-failure handler for a given path+method. The handler
    /// short-circuits the request with either an HTTP error body OR a transport
    /// URLError. SC #4: a unit test registers a 409-conflict failure for a load
    /// action endpoint and asserts `NetworkError.httpError(409, …)` is thrown.
    public static func registerForcedFailure<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        kind: InjectedFailure
    ) {
        register { request in
            guard request.url?.path == path,
                  request.httpMethod == method.rawValue else { return nil }
            // For .urlError: MockURLProtocol's existing handler-return shape is
            // `(HTTPURLResponse, Data)?` — to signal a transport error the
            // implementation must extend MockURLProtocol.startLoading()'s loop
            // to ALSO check a second registry of URLError-emitting handlers, OR
            // (simpler) introduce a second Handler typealias and a parallel
            // _failureHandlers array. The planner picks the shape; the API
            // surface (this register* function) stays as shown.
            switch kind {
            case .http(let statusCode, let body):
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (resp, body)
            case .urlError:
                // See note above — implementation detail for the plan.
                return nil  // placeholder; planner finalizes the URLError emit path
            }
        }
    }
}
```

**Minimum additive surface (the planner's checklist):**

1. The two functions above — `registerFixture(...latency:)` and `registerForcedFailure(...kind:)` — are appended to `MockURLProtocol` (or to `MockFixture.swift`) without altering any existing line.
2. The `.urlError` arm requires extending `MockURLProtocol`'s internal handler-storage shape. The minimum-impact pattern: introduce a second `@Sendable` typealias `FailureHandler = (URLRequest) -> URLError.Code?` and a second `_failureHandlers` lock-guarded array; `startLoading()` consults `_failureHandlers` BEFORE `_handlers`. The existing `_handlers` array and its `register(_:)`/`reset()` API are untouched; `reset()` is extended to clear both arrays. **This is the only line-level edit to existing code** in `MockURLProtocol.swift`.
3. A unit test calls each new function and asserts behavior:
   - `MockURLProtocolLatencyTests.swift` — registers a fixture with `latency: 0.25`, calls `client.request(...)`, asserts elapsed ≥ 250 ms.
   - `MockURLProtocolForcedFailureTests.swift` — registers 409 for a `LoadActionEndpoint` path; asserts the resulting throw is `NetworkError.httpError(statusCode: 409, ...)`.

### `MockLoadFixtureRegistry` skeleton (D-17)

```swift
// validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
// NEW (Phase 7). Mirrors MockOTPRoleFixtureRegistry exactly in structure.

#if DEBUG
import Foundation

enum MockLoadFixtureRegistry {

    /// Register all load-domain DEBUG handlers (per-role list, per-load detail,
    /// per-action POST). Called from AppContainer.init's DEBUG-gated block,
    /// directly after MockDefaultFixtures.registerAppDefaults().
    static func registerAppDefaults() {

        // GET /loads/{role} — 5 handlers, one per role (D-11 shared world view)
        for role in Role.allCases {
            MockURLProtocol.register { req in
                guard req.url?.path == "/loads/\(role.rawValue)",
                      req.httpMethod == "GET" else { return nil }
                let body = loadsListJSON(for: role)  // returns Data
                return make200(body: body, url: req.url)
            }
        }

        // GET /loads/{id} — one catch-all that looks up the load by ID
        MockURLProtocol.register { req in
            let path = req.url?.path ?? ""
            guard req.httpMethod == "GET",
                  path.hasPrefix("/loads/"),
                  path.dropFirst("/loads/".count).contains("/") == false,
                  // exclude /loads/{role} paths from this catch-all
                  !Role.allCases.contains(where: { $0.rawValue == String(path.dropFirst("/loads/".count)) })
            else { return nil }
            let loadID = String(path.dropFirst("/loads/".count))
            guard let body = loadDetailJSON(for: loadID) else { return nil }
            return make200(body: body, url: req.url)
        }

        // POST /loads/{id}/{action} — catch-all action handler returning the
        // updated load. Defaults to success; tests use registerForcedFailure(...)
        // to override per-test for 409/422/timeout coverage (D-14).
        MockURLProtocol.register { req in
            let path = req.url?.path ?? ""
            guard req.httpMethod == "POST",
                  path.hasPrefix("/loads/"),
                  path.split(separator: "/").count == 3 else { return nil }
            return make200(body: loadActionSuccessJSON(), url: req.url)
        }
    }

    // MARK: - JSON body resolvers (planner finalizes the named library)

    private static func loadsListJSON(for role: Role) -> Data {
        // Resolves to a snake_case JSON document containing this role's view
        // onto the shared-world load library (D-11). 12 loads total; each
        // appears in 1-3 role lists per the role-relevance rules in §"Shared-World
        // Fixture Roster" below.
        // Implementation: a static dictionary [Role: Data] populated from
        // string literals or bundled JSON. Planner picks.
        Data("...".utf8)
    }

    private static func loadDetailJSON(for loadID: String) -> Data? {
        // Resolves to a snake_case JSON document for a single load (Load + ChainOfTrust)
        // by VL-#### ID. Returns nil for an unknown ID so MockURLProtocol's built-in
        // 404 fires loudly.
        nil
    }

    private static func loadActionSuccessJSON() -> Data {
        // Returns an updated-load JSON. Per Pitfall 4 (PITFALLS.md), the
        // success body MUST include the full updated load so the detail VM
        // reconciles state from the server response.
        Data("...".utf8)
    }

    private static func make200(body: Data, url: URL?) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "https://mock.local/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }
}
#endif
```

**Registration entry point in `AppContainer.init`:**

```swift
// validationLedger/App/AppContainer.swift  — AppContainer.init body, around line 451-456:

#if DEBUG
let isUITestRolePath = ProcessInfo.processInfo.arguments.contains("-MockOTPRoleForUITest")
if case .mock = resolvedConfig, !isUITestRolePath {
    MockDefaultFixtures.registerAppDefaults()
    MockLoadFixtureRegistry.registerAppDefaults()   // ← NEW (1 line, Phase 7)
}
#endif
```

[VERIFIED: source — `AppContainer.swift:451-456`]

### Shared-World Fixture Roster (12 loads — D-10/11/12/13)

The proposal: a 12-load library that hits every cell of the coverage matrix while telling a coherent fraud-detection story. Each load is named (VL-#### + a description) and appears in 1-3 role lists per its real-world relevance.

| VL-ID | Description | Status | All-party verification states | Chain integrity | Fraud archetype | Appears in role lists |
|---|---|---|---|---|---|---|
| VL-1001 | Clean delivered cross-country dry van (Anaheim → Atlanta) | `delivered` | all verified | clean | — | shipper, broker, carrier, dispatch, factoring |
| VL-1002 | Clean in-transit reefer (Salinas → Chicago) | `inTransit` | all verified | clean | — | shipper, broker, carrier, dispatch |
| VL-1003 | Posted load awaiting tender (Memphis → Dallas) | `posted` | shipper verified, broker verified | clean | — | shipper, broker |
| VL-1004 | Active tender with countdown (Phoenix → Denver, `respondByAt: T+2h`) | `tendered` | all verified | clean | — | broker, carrier, dispatch |
| VL-1005 | Expired tender — load reverted to `posted` (Newark → Charlotte) | `posted` (stateHistory shows expiry) | broker verified, target carrier pending | clean (pre-tender state) | — | shipper, broker (drives retender) |
| VL-1006 | Draft load (Stockton → Portland) | `draft` | shipper verified | clean | — | shipper, broker (drives `post`) |
| VL-1007 | Dispatched load awaiting pickup (Detroit → Indianapolis) | `dispatched` | all verified | clean | — | carrier, dispatch (drives `advanceStatus`) |
| VL-1008 | Tender candidate with **unverified target carrier** (Houston → Tulsa) | `posted` (broker about to tender) | target carrier `unverified` | clean (no tender yet) | — | broker (drives ACTION-07 hard-disable) |
| **VL-1009** | **Double-/triple-brokered shipment** (Long Beach → Phoenix; intermediary broker added without authority) | `inTransit` | shipper verified, broker verified, **intermediary broker flagged**, carrier verified | **compromised** + reason "Unauthorized broker re-tender detected; intermediary lacks broker authority of record" + implicated edge ID | (a) double-/triple-brokering | broker, carrier, dispatch, factoring |
| **VL-1010** | **Chameleon carrier** (Miami → Jacksonville; carrier reused a recycled USDOT) | `accepted` | shipper verified, broker verified, **carrier flagged** (KYC name mismatch + authority history shows revocation pattern) | **compromised** + reason "Carrier USDOT has 3 prior authority revocations in 18 months; identity does not match KYC of record" + implicated node ID | (b) chameleon carrier | broker, carrier, dispatch |
| **VL-1011** | **Factoring fraud on a double-brokered load** (Atlanta → Birmingham; downstream factoring party flagged on a chain that's also compromised upstream) | `invoiced` | shipper verified, broker verified, intermediary broker flagged, carrier flagged, **factoring flagged** | **compromised** + reason "Factoring party tied to 4 prior double-brokered invoices flagged for clawback" + 2 implicated node IDs | (c) factoring fraud | factoring (post-delivery display) |
| VL-1012 | Funded delivered load (San Diego → Tucson) — Factoring-tab content | `funded` | all verified | clean | — | factoring (post-delivery display) |

**Coverage matrix verification:**

| Coverage axis | Loads hitting it | ✓ |
|---|---|---|
| Every `LoadStatus` | draft (1006), posted (1003, 1005, 1008), tendered (1004), accepted (1010), dispatched (1007), inTransit (1002, 1009), delivered (1001), invoiced (1011), funded (1012); rejected, expired, cancelled, podCaptured each surfaceable via stateHistory of an existing load — add explicit fixtures only if tests require dedicated detail JSON | ✓ |
| Every `VerificationState` | verified (every load's primary parties), pending (1005 target carrier), unverified (1008 target carrier), flagged (1009 intermediary, 1010 carrier, 1011 factoring) | ✓ |
| Every `ChainIntegrity` verdict | clean (1001-1008, 1012), compromised (1009, 1010, 1011); `caution` — add via a smaller anomaly e.g. "first-time-counterparty" — recommend adding a 13th load OR using one of the existing pending-target loads (1005) to also carry a `caution` integrity verdict | ✓ (planner finalizes whether `caution` needs its own VL- or rides on 1005) |
| All 3 fraud archetypes (D-13) | (a) VL-1009 double-broker; (b) VL-1010 chameleon; (c) VL-1011 factoring fraud | ✓ |
| `RoleLoadPolicy` action paths | `post` (1006), `tender` (1003, 1005, 1008-blocked), `accept`/`reject` (1004), `advanceStatus` (1007, 1002), `cancel` (any pre-delivery), Factoring view-only (1001, 1009, 1011, 1012) | ✓ |
| ACTION-07 refuse-to-tender (PROJECT.md L12) | VL-1008 — target carrier `unverified` → tender hard-disabled with inline reason from `tenderEligibility` | ✓ |
| Optional-field absence (Pitfall 5) | VL-1003 `respondByAt: nil`, VL-1006 `chain.edges: []`, VL-1005 target carrier `kycCompletedAt: nil` | ✓ |
| Empty-list mechanical | `loads-list-empty.json` registered separately; not a named load | ✓ (D-14) |

**Per-role list contents (D-11 shared-world derivation):**

- `loads-list-shipper.json`: VL-1001, VL-1002, VL-1003, VL-1005, VL-1006 (shipper's own posted+delivered+drafts)
- `loads-list-broker.json`: VL-1001, VL-1002, VL-1003, VL-1004, VL-1005, VL-1006, VL-1008, VL-1009, VL-1010 (every load they brokered + draft/posted candidates)
- `loads-list-carrier.json`: VL-1001, VL-1002, VL-1004, VL-1007, VL-1009, VL-1010 (loads tendered/assigned to this carrier)
- `loads-list-dispatch.json`: VL-1001, VL-1002, VL-1004, VL-1007, VL-1009, VL-1010 (same as carrier — D-06)
- `loads-list-factoring.json`: VL-1001, VL-1009, VL-1011, VL-1012 (post-delivery loads tied to invoices it factors)

Same VL-1009 appears in broker's list ("you brokered this"), carrier's list ("you carried this"), dispatch's list (carrier's dispatch view), and factoring's list ("you advanced funds against this"). One `ChainOfTrust` for VL-1009 shared across all four. ✓ D-11.

### Mechanical Failure Fixture HTTP Codes + Mock Threading (D-14)

The mechanical failure fixtures split into two categories by **delivery mechanism**:

**Category A — plain JSON fixtures returned at HTTP error codes** (uses the existing `MockURLProtocol.registerFixture(...statusCode: 4xx, body: ...)` pattern, but registered per-test rather than via the default registry):

| Fixture | HTTP Status | Body | Triggered by test |
|---|---|---|---|
| `load-action-conflict-409.json` | 409 | `{"error_code":"load.stale_state","message":"This load has already been actioned by another party"}` | `LoadEndpointsTests` — test registers it and asserts `NetworkError.httpError(409, ...)` |
| `load-action-validation-422.json` | 422 | `{"error_code":"load.invalid_transition","message":"Cannot accept a load that is not currently tendered"}` | `LoadEndpointsTests` |
| `load-list-server-error-500.json` | 500 | `{"error_code":"server.internal","message":"Service temporarily unavailable"}` | `LoadEndpointsTests` — empty-state vs. error-state coverage |

These are authored as JSON files under `validationLedgerTests/Networking/Fixtures/` and pulled via `FixtureLoader`. They do NOT live in `MockLoadFixtureRegistry`'s default set — that registry serves the success path for the organic DEBUG tap-through (Phases 8-10). The failure fixtures are test-only.

**Category B — failures threaded through the additive injection API** (D-14 timeout, plus the option to test 409/422 via the injection path as well):

| Failure | Mechanism | Test |
|---|---|---|
| Timeout | `MockURLProtocol.registerForcedFailure(for: LoadActionEndpoint.self, ..., kind: .urlError(.timedOut))` | `MockURLProtocolForcedFailureTests` — asserts the request throws (typed depending on whether `Auth401`/`Retry` interceptors swallow it; the planner verifies the throw type empirically) |
| Latency injection | `MockURLProtocol.registerFixture(..., latency: 0.25)` | `MockURLProtocolLatencyTests` — asserts elapsed ≥ 250 ms; Phase 8 uses this same hook for the loading-state demo |
| Slow + failed | Sequence of `registerFixture(...latency: 0.5)` + `registerForcedFailure(...)` per test | Action-failure tests; the planner picks composition vs. nesting |

**Status code rationale:**
- **409 Conflict** = "stale state / already-actioned" (e.g., a Carrier tries to accept a tender another Carrier already accepted) — the canonical HTTP semantic for "your request is well-formed but conflicts with current resource state."
- **422 Unprocessable Entity** = "validation failure" (e.g., trying to `accept` a load whose status is `delivered`) — RFC 4918 / RFC 9110.
- **500 Internal Server Error** = the generic backend failure for the empty/error-state UI in Phase 8.
- **Timeout** = transport-level, modeled via `URLError.Code.timedOut`, not an HTTP code.

[VERIFIED: source — `NetworkError.swift:8-29` for the full typed-error surface; `APIClient.swift:66-68` for the 2xx-only success gate]

### `Core/Load/` File Inventory (8 files)

One type per file, mirroring the v1.0 pattern in `Core/Identity/KYC/` (where `KYCSession.swift`, `RejectionReasonCode.swift`, `KYCUploadError.swift`, etc. each hold one type). Files listed in dependency order — earlier files are imported by later ones.

| # | File | Primary type(s) | Notes |
|---|---|---|---|
| 1 | `Core/Load/LoadStatus.swift` | `enum LoadStatus` (13 cases — D-01) | `String, Decodable, Sendable, CaseIterable`. Wire values are snake_case matching cases: `"in_transit"`, `"pod_captured"`. Add explicit `CodingKeys`-on-`String`-rawValue for the snake_case forms. |
| 2 | `Core/Load/LoadAction.swift` | `enum LoadAction` (6 cases — D-03/04/05) | `String, Sendable, CaseIterable`. NOT `Decodable` — actions are sent client-to-server, not the reverse. Wire-serialized via the URL path segment, not JSON body. Cases: `post, tender, accept, reject, cancel, advanceStatus`. Includes `pathSegment` extension. |
| 3 | `Core/Load/VerificationState.swift` | `enum VerificationState` + fail-closed `init(from:)` (D-09) | THE security primitive. Custom decoder as shown above. |
| 4 | `Core/Load/ChainIntegrity.swift` | `struct ChainIntegrity` + `enum ChainIntegrity.Verdict` (D-08) | `Verdict` cases: `clean, caution, compromised`. Carries `verdict`, `reason: String`, `implicatedNodeIDs: [String]`, `implicatedEdgeIDs: [String]`. The verdict enum uses the same fail-closed decode pattern (unknown → `.compromised` — fail-closed to MORE suspicious for the verdict; alternatively `.caution`; planner picks but documents). |
| 5 | `Core/Load/ChainOfTrust.swift` | `struct ChainOfTrust`, `struct TrustNode`, `struct TrustEdge`, supporting enums (`DeviceBindingStatus`, `USDOTAuthorityStatus`) (D-07/08) | `TrustNode` fields per D-07: `partyID, role, displayName, verificationState, kycCompletedAt: Date?, deviceBindingStatus, usdotNumber: String?, usdotAuthorityStatus, priorRelationshipCount: Int`. `TrustEdge` fields: `fromPartyID, toPartyID, relationshipState, tenderRef: String?`. |
| 6 | `Core/Load/LoadStatusEvent.swift` | `struct LoadStatusEvent`, `struct LoadParty` (D-02) | Event: `{ status: LoadStatus, timestamp: Date, actor: LoadParty? }`. `LoadParty` is a lightweight reference (`partyID, role, displayName`) — distinct from `TrustNode` (which carries the trust-graph payload). |
| 7 | `Core/Load/Load.swift` | `struct Load` (the aggregate) | Composes all the above. Fields: `id: String, referenceNumber: String, origin: LoadEndpoint, destination: LoadEndpoint, equipment, weight, rate, pickupAt: Date, deliverAt: Date, status: LoadStatus, stateHistory: [LoadStatusEvent], respondByAt: Date?, tenderEligibility: TenderEligibility?` (the field driving ACTION-07's `refuse-to-tender` inline reason). `LoadEndpoint` (city/state/etc. — name avoids collision with `APIEndpoint`) is also in this file or split into `LoadStop.swift` — planner picks. |
| 8 | `Core/Load/RoleLoadPolicy.swift` | `enum RoleLoadPolicy` (D-06) | The pure policy table shown above. Imports `Role` from `Roles/Role.swift`. |

**Naming note:** "endpoint" is overloaded — `APIEndpoint` is the networking-conformance protocol; the load detail's pickup/delivery locations should be named `LoadStop` (or `Stop`) to avoid grep collision. Recommend `LoadStop`.

[VERIFIED: source — `Core/Identity/KYC/` directory listing shows the one-type-per-file convention; `Core/Auth/` and `Core/KeyStore/` show the same.]

## State of the Art

Nothing in this phase relies on training-data knowledge that could be stale. Every pattern is a v1.0 source-tree fact verified by direct inspection. The only candidate for "current vs deprecated" is:

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| `XCTest` test framework | `Swift Testing` (`@Suite`, `@Test`, `#expect`) | v1.0 standardized on Swift Testing throughout | Phase 7 tests are `@Suite(.serialized)` (mandatory for any test that mutates `MockURLProtocol`'s handler registry) and use `#expect`/`Issue.record`. [VERIFIED: source — `APIClientEndpointTests.swift:8-13`] |

No other "deprecated" items apply.

## Assumptions Log

> Per the protocol — any claim not verified in this session is tagged here. Phase 7 is unusual in that almost every claim is verified-against-source. The few `[ASSUMED]` items are noted explicitly.

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | The `Thread.sleep(forTimeInterval:)` approach inside a `MockURLProtocol` handler closure delivers the latency as observed by an `await client.request(...)` test — i.e. the handler runs on a thread the test's await observes [ASSUMED: based on URLSession's `URLSessionConfiguration.ephemeral` + dedicated protocolClasses behavior, not directly tested in v1.0] | "Additive latency / forced-failure injection" code example | LOW — if `Thread.sleep` doesn't deliver the latency to the awaited request as expected, the planner picks an asynchronous-completion shape instead (deliver the response on a delayed dispatch via `client?.urlProtocol(...)` calls). Both paths satisfy SC #4; the choice is implementation. |
| A2 | The `.convertFromSnakeCase` key strategy correctly maps `next_cursor` → `nextCursor` (no trailing-acronym ambiguity, since `cursor` ends in a letter, not an acronym) [ASSUMED but high confidence — analogous to `expiresInSeconds` decoded in `OTPRequestEndpoint.Response`] | "LoadListEndpoint" code example, Pattern 2 | LOW — if it doesn't, add explicit `CodingKeys`. The decode test will catch it on day one. |
| A3 | The `ChainIntegrity.Verdict` fail-closed default for unknown wire values should be `.compromised` (most-suspicious) [ASSUMED — D-09 establishes the fail-closed principle for `VerificationState` but does not explicitly extend it to `ChainIntegrity.Verdict`] | "Core/Load/File Inventory" row 4 | MEDIUM — the choice of fail-closed default for chain-integrity is a security primitive; the planner should confirm with the user during plan-checker (or fold into a discuss-phase follow-up). Recommend planner explicitly call this out in PLAN.md so it's visible. |
| A4 | `caution` is a real `ChainIntegrity.Verdict` case (not just `clean` and `compromised`) [ASSUMED based on D-08 "indicative: clean / caution / compromised"] | "Shared-World Fixture Roster" coverage matrix; `Core/Load/File Inventory` row 4 | LOW — D-08 lists it indicatively; the planner finalizes the exact case set per Claude's Discretion. If `caution` is dropped, the named-load library only needs `clean` and `compromised` (one less coverage cell). |
| A5 | The `tenderEligibility` field on `Load` (the data driving ACTION-07's `refuse-to-tender` inline reason) is appropriate as a top-level `Load` field rather than embedded under `ChainOfTrust` [ASSUMED — PITFALLS Pitfall 4 cites "tenderEligibility fixture field"; placement on `Load` vs. under chain not explicitly decided] | "Core/Load/File Inventory" row 7 | LOW — placement is plan-level; both shapes decode identically; the planner picks. |
| A6 | The 12 VL-#### load count is the right size — covers the matrix without inflating the fixture count [ASSUMED — D-12 says "planner finalizes IDs and count"] | "Shared-World Fixture Roster" | LOW — the matrix verification above shows full coverage; any planner-finalized count between 10 and 15 works. |

**If this table is empty:** Not applicable — six items are assumed-but-low-risk. The planner should fold A3 into the discuss-phase or surface it as an open question if user confirmation is needed before locking the `ChainIntegrity.Verdict` default.

## Open Questions

1. **`ChainIntegrity.Verdict` fail-closed default** — see A3. Default to `.compromised` (most-suspicious) or `.caution` (middle)?
   - What we know: D-09 establishes fail-closed for `VerificationState`. The same principle applies in spirit to `ChainIntegrity.Verdict`.
   - What's unclear: D-08 doesn't explicitly state the default. Choosing `.compromised` may render false-positive "compromised" badges on the trust graph in Phase 9 if the backend ever sends an unknown verdict; choosing `.caution` is the middle path.
   - Recommendation: Plan with `.compromised` default + document in `Core/Load/ChainIntegrity.swift` comments + add a `VerificationStateDecoderTests`-style unit test asserting "unknown verdict decodes to `.compromised`." If the user surfaces a different preference during plan-checker, swap is a one-line change.

2. **`priorRelationshipCount: Int` vs `priorRelationships: [PriorRelationship]`** — D-07 lists this explicitly under Claude's Discretion.
   - What we know: TRUST-03 surfaces "prior-relationship history" — but the v1.1 trust-node-detail screen (Phase 9) may render it as a count OR as a list.
   - What's unclear: whether Phase 9's design wants a count badge ("seen 47 times before") or a list ("Jan 2024 — Acme Logistics; Mar 2024 — …").
   - Recommendation: Plan with `priorRelationshipCount: Int` (simpler, scope-trim-friendly). If Phase 9's design spike concludes a list is needed, evolve the contract additively (add `priorRelationships: [PriorRelationship]?` later — both decode independently).

3. **`LoadAction.advanceStatus` payload shape** — D-05 says target state is derived server-side. Does the POST body include any hint, or is it empty?
   - What we know: D-05 locks the client model — `RoleLoadPolicy` returns `[.advanceStatus]`, target is server-derived from current status.
   - What's unclear: Whether the wire request body for `POST /loads/{id}/status` is `{}` or carries the target (e.g., `{"target_status": "in_transit"}`) as a defensive measure.
   - Recommendation: Empty-ish body `{ "actor_role": "carrier" }` — D-05's "single action, server-derived target" implies the client says "advance one step" and trusts the server's state machine. Fixture should mirror this. Planner finalizes.

## Environment Availability

> Phase 7 is pure Swift code modifications + JSON authoring. No external tools, services, databases, or runtimes.

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Xcode 26.x toolchain | Compilation | ✓ | 26.x (per `PROJECT.md` constraint, verified v1.0 shipped) | — |
| Swift Testing | Unit tests | ✓ | bundled with Xcode 26 | — |
| `validationLedger` source tree | All work | ✓ | v1.0 shipped 2026-05-18 | — |
| `validationLedgerTests` target | Tests | ✓ | v1.0 shipped | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None.

## Validation Architecture

Per the protocol — `workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section is included.

### Test Framework
| Property | Value |
|---|---|
| Framework | Swift Testing (Xcode 26 bundled) + XCUITest where physical-device UAT applies (not Phase 7) |
| Config file | `validationLedger.xcodeproj` schemes — `validationLedgerTests` target; no separate config file |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.x' -only-testing:validationLedgerTests/Load -only-testing:validationLedgerTests/Networking` |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.x' -only-testing:validationLedgerTests` (the project memory item *ios-test-suite-pitfalls.md* notes plain `xcodebuild test` gives ~67 false failures — use the scoped serial simulator-lane command from that memory) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| LOAD-01 | `LoadListEndpoint` decodes per-role fixtures | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/LoadEndpointsTests/loadListShipper` (etc.) | ❌ Wave 0 |
| LOAD-01 | `LoadDetailEndpoint` decodes every named load (12 fixtures) | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/LoadEndpointsTests/loadDetailDecodeAll` | ❌ Wave 0 |
| LOAD-01 | `LoadActionEndpoint` decodes success + 409 + 422 fixtures | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/LoadEndpointsTests/loadAction*` | ❌ Wave 0 |
| LOAD-01 (D-14) | `MockURLProtocol` latency injection works | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/MockURLProtocolLatencyTests` | ❌ Wave 0 |
| LOAD-01 (D-14) | `MockURLProtocol` forced-failure injection (urlError + http) works | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/MockURLProtocolForcedFailureTests` | ❌ Wave 0 |
| LOAD-01 (SC #5) | Mock/live swap compile-and-pass smoke test | unit | `xcodebuild test -only-testing:validationLedgerTests/App/AppContainerNetworkConfigTests/loadEndpointsConfigSwap` | ❌ Wave 0 (extension to existing `AppContainerNetworkConfigTests`) |
| LOAD-02 | `VerificationState` fail-closed decoder (known + unknown + missing) | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/VerificationStateDecoderTests` | ❌ Wave 0 |
| LOAD-02 (D-06) | `RoleLoadPolicy` exhaustive (5 × every LoadStatus) | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/RoleLoadPolicyTests` | ❌ Wave 0 |
| LOAD-02 (D-06) | `RoleLoadPolicy` Factoring is empty for every state | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/RoleLoadPolicyTests/factoringEmptyEverywhere` | ❌ Wave 0 |
| LOAD-02 (D-08) | `ChainOfTrust` decode for clean + 3 fraud archetypes | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/ChainOfTrustDecodeTests` | ❌ Wave 0 |
| LOAD-02 (D-02) | `Load.stateHistory` decode order + timestamps | unit | `xcodebuild test -only-testing:validationLedgerTests/Load/LoadStateHistoryTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test … -only-testing:validationLedgerTests/Load` (~ < 5 sec on simulator)
- **Per wave merge:** the full LOAD + Networking scoped run shown above (~ < 30 sec)
- **Phase gate:** Full simulator suite green before `/gsd:verify-work`. Per the project memory item *ios-test-suite-pitfalls.md*, use the scoped serial simulator-lane command, NOT bare `xcodebuild test`.

### Wave 0 Gaps
The entire test infrastructure for `Core/Load/` is new. Wave 0 lays:

- [ ] `validationLedgerTests/Load/` directory creation (mirrors `validationLedgerTests/KYC/`, `validationLedgerTests/Networking/`)
- [ ] `validationLedgerTests/Load/LoadDomainDecodeTests.swift` — base fixture-decode coverage (per VL-id success path)
- [ ] `validationLedgerTests/Load/VerificationStateDecoderTests.swift` — fail-closed edge cases (LOAD-02 D-09)
- [ ] `validationLedgerTests/Load/RoleLoadPolicyTests.swift` — 5 × 13 exhaustive matrix (LOAD-02 D-06)
- [ ] `validationLedgerTests/Load/ChainOfTrustDecodeTests.swift` — 3 fraud archetypes + clean (LOAD-02 D-08)
- [ ] `validationLedgerTests/Load/LoadStateHistoryTests.swift` — stateHistory ordering (LOAD-02 D-02)
- [ ] `validationLedgerTests/Networking/LoadEndpointsTests.swift` — the 3 endpoints × success/error fixtures (LOAD-01)
- [ ] `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` — additive latency (LOAD-01 SC #4)
- [ ] `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` — additive forced-failure (LOAD-01 SC #4)
- [ ] Extension to `validationLedgerTests/App/AppContainerNetworkConfigTests.swift` — mock/live swap with new endpoints (LOAD-01 SC #5)
- [ ] Fixture authoring: `validationLedgerTests/Networking/Fixtures/loads-list-{role}.json` × 5 + `load-detail-VL-{id}.json` × 12 + `loads-list-empty.json` + `load-action-{success,conflict-409,validation-422,server-error-500}.json`

**Framework install:** None — Swift Testing is bundled with Xcode 26.

The Phase 7 success criteria (in the roadmap):

1. SC #1 — 3 endpoints decode every fixture in passing unit tests → covered by `LoadEndpointsTests` + `ChainOfTrustDecodeTests` + `LoadDomainDecodeTests`
2. SC #2 — `RoleLoadPolicy.actions(for:status:)` 5 roles × every status, Factoring empty → covered by `RoleLoadPolicyTests`
3. SC #3 — `Core/Load/` types pure `Decodable & Sendable`, server-supplied verification + integrity → covered by compile-time `Sendable` checks + `VerificationStateDecoderTests` + `ChainOfTrustDecodeTests` + a grep-based rule that no client code path constructs `VerificationState` from non-decoded sources
4. SC #4 — `MockURLProtocol` supports latency + forced-failure, exercised by a test → covered by `MockURLProtocolLatencyTests` + `MockURLProtocolForcedFailureTests`
5. SC #5 — mock/live swap compiles + passes with new endpoints → covered by extending `AppContainerNetworkConfigTests` to instantiate `.live` config and request each of the 3 new endpoints (asserting they compile against `apiClient.request<E>` without further plumbing; the request itself fails predictably against `https://mock.local` baseURL on `.live` which is fine — the test asserts the *compile* + *call-site* shape)

## Security Domain

> `security_enforcement` is not explicitly set to `false` in `.planning/config.json`; default is enabled. Phase 7 is a contract/data-modeling phase, so the security surface is narrow but real.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | no — Phase 7 does not touch auth; existing v1.0 OTP + session is untouched | n/a (existing) |
| V3 Session Management | no — same as V2 | n/a |
| V4 Access Control | **yes (indirectly)** — `RoleLoadPolicy` is the client-side access-control affordance for load actions. Server is the enforcement boundary (Pitfall 6 in PITFALLS.md), but the client policy table is the UX surface | `RoleLoadPolicy` is a pure tested function; backend mirrors and *enforces* (post-v1.1 with real backend) — V4.1 (least privilege via the table), V4.2 (deny-by-default via the table's `default: return []`) |
| V5 Input Validation | **yes** — every `Decodable` type in `Core/Load/` is the validation boundary | Custom `init(from:)` on `VerificationState` is the V5.1 input validation primitive; `LoadStatus`, `LoadAction`, `ChainIntegrity.Verdict` use the same fail-closed pattern (planner picks the unknown-default); strict optional-vs-required modeling per Pitfall 5 |
| V6 Cryptography | no — Phase 7 does not handle keys, hashes, or signed data; the v1.0 device-signature pattern (Pitfall 6 SecMistakes table) applies at the request layer (`IdempotencyInterceptor`, etc.) and is inherited unchanged | n/a (existing) |

### Known Threat Patterns for {Phase 7 contract-modeling scope}

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Client derives a "verified" badge from local logic (the canonical v1.1 fraud vector — PITFALLS Pitfall 3) | Spoofing / Tampering | D-18 — `Core/Load/` types are pure value types with no setter on `verificationState` / `chainIntegrity` / `ChainIntegrity.Verdict`. The fail-closed decoder (D-09) ensures unknown wire values degrade to least-trusted. Lint: no Phase 7 code path that constructs a `TrustNode` or `VerificationState` from non-decoded sources |
| Optional-field absence silently maps to least-suspicious | Tampering / Repudiation | D-09 — missing `verification_state` on a party is a hard decode error (not a silent default). Same principle for `chain_integrity` on the load detail response |
| `Idempotency-Key` not auto-injected on a load action | Repudiation | D-19 — `LoadActionEndpoint.method = .post` automatically picks up `IdempotencyInterceptor` (already in `apiClient.requestInterceptors`). Verified by adding a test that asserts the request emitted by `client.request(LoadActionEndpoint(...))` carries an `Idempotency-Key` header |
| Mock fixture intentionally crafts a malformed JSON to bypass decoder | Tampering | All fixture JSON authored under git — any "permissive" decoder change shows up in PR diff. Strict optional-vs-required modeling enforced per Pitfall 5 |
| Future server adds a `verificationState: "trusted"` superstring | Trust elevation | D-09 fail-closed — unknown wire values degrade to `.unverified`. Test `unknown()` in `VerificationStateDecoderTests` covers this |
| The `MockLoadFixtureRegistry` somehow ships in a Release build, surfacing demo data on a real device | Information Disclosure (low — demo data, no PII) | The entire file is `#if DEBUG` (mirroring `MockOTPRoleFixtureRegistry.swift:17` and `MockDefaultFixtures.swift:46`). Verified by a grep test: Release binary does not contain `MockLoadFixtureRegistry` symbol |

## Sources

### Primary (HIGH confidence)
- `validationLedger/Core/Networking/APIClient.swift` — typed-endpoint facade, decoder defaults, error handling
- `validationLedger/Core/Networking/APIEndpoint.swift` — `APIEndpoint` protocol, `EmptyBody` sentinel, `HTTPMethod` enum
- `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — path+method matcher, `register/reset` API
- `validationLedger/Core/Networking/Mock/MockFixture.swift` — `registerFixture<E>` convenience extension (line 23 confirms path-only match)
- `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` — the exact pattern `MockLoadFixtureRegistry` mirrors
- `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift` — DEBUG dispatch handler pattern; the registration site
- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` — POST/PUT auto-injection, skips existing keys
- `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` — canonical `nonisolated public struct` conformer shape (GET)
- `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` — canonical POST conformer shape with explicit `CodingKeys`
- `validationLedger/Core/Networking/Endpoints/KYCSubmitEndpoint.swift` — POST with array body (template for `LoadActionEndpoint`)
- `validationLedger/Core/Networking/NetworkError.swift` — full typed-error surface (`.httpError`, `.decodingFailed`, `.rateLimited`, etc.)
- `validationLedger/Core/Identity/KYC/RejectionReasonCode.swift` — closest v1.0 closed-enum decode analog (call-site degrade, NOT decoder-level — distinguishes from D-09's decoder-level requirement)
- `validationLedger/Core/Identity/KYC/KYCSession.swift:80-89` — custom `init(from:)` with `decodeIfPresent` pattern (the only v1.0 example of a non-synthesized decoder)
- `validationLedger/Roles/Role.swift` — the `Role` enum consumed by `RoleLoadPolicy` and `LoadListEndpoint(role:)`
- `validationLedger/App/AppContainer.swift:451-485` — DEBUG mock-fixture registration site + APIClient composition (interceptor wiring)
- `validationLedgerTests/Networking/APIClientEndpointTests.swift` — the v1.0 endpoint-test template (`@Suite(.serialized)`, `MockURLProtocol.reset()` discipline)
- `validationLedgerTests/Networking/FixtureLoader.swift` — JSON loader for the test bundle
- `validationLedgerTests/Networking/Fixtures/kyc-status-*.json` — fixture naming convention + JSON shape template
- `.planning/research/SUMMARY.md`, `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md`, `.planning/research/STACK.md`, `.planning/research/FEATURES.md` — milestone-level v1.1 research (the authoritative scope source per CONTEXT.md)
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/PROJECT.md`, `.planning/STATE.md` — phase scope + traceability
- `.planning/phases/07-load-domain-model-mock-contract/07-CONTEXT.md` — the 19 locked decisions

### Secondary (MEDIUM confidence)
- None — Phase 7 has no MEDIUM-confidence sources. Every claim is either v1.0-source-verified or marked `[ASSUMED]` in the Assumptions Log.

### Tertiary (LOW confidence)
- None — see above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; the stack IS the v1.0 stack; every claim source-verified.
- Architecture: HIGH — every placement decision (`Core/Load/`, `Core/Networking/Endpoints/`, `Core/Networking/Mock/`) mirrors an observed v1.0 pattern; the `nonisolated public struct` shape, the `EmptyBody` sentinel, the snake_case decoder, the `MockOTPRoleFixtureRegistry` precedent — all source-verified.
- Pitfalls: HIGH — every Phase-7 pitfall is grounded in either the v1.0 PITFALLS audit (PITFALLS.md, 10 v1.1 pitfalls authored 2026-05-19) or direct source-pattern observation.
- Fail-closed `VerificationState` decoder: HIGH — the pattern is standard Swift `Codable` craft; the unit-test shape mirrors v1.0 testing discipline.
- `MockURLProtocol` additive injection: MEDIUM-HIGH — the `Thread.sleep` approach is `[ASSUMED]` (A1); the `registerForcedFailure` + new `_failureHandlers` array approach is mechanically additive; planner finalizes the exact threading at task time.
- Shared-world fixture roster (12 loads): HIGH-MEDIUM — the matrix coverage is mechanically verified; the named-load IDs and the precise per-role list contents are planner-finalizable per Claude's Discretion (D-12). The story-coherence aspiration of D-10 is a product judgement the planner+user finalize.

**Research date:** 2026-05-19
**Valid until:** 2026-06-18 (30 days for stable, source-grounded research; the v1.0 source tree changes invalidate this earlier if it does)

---
*Research for Phase 7: Load Domain Model & Mock Contract — Validation Ledger iOS v1.1 "Load Flows"*
*Researched: 2026-05-19*
