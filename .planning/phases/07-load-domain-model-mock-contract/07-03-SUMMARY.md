---
phase: 07-load-domain-model-mock-contract
plan: 03
subsystem: networking
tags: [swift, api-endpoint, role-in-path, paginated-envelope, post-idempotency, chain-of-trust, embedded-graph]

requires:
  - phase: 02-typed-networking
    provides: APIEndpoint protocol + EmptyBody sentinel + APIClient.defaultEncoder()/defaultDecoder() + IdempotencyInterceptor (auto-picks up POST/PUT)
  - phase: 07-load-domain-model-mock-contract (Plan 01)
    provides: LoadStatus + LoadAction + LoadAction.pathSegment + VerificationState + ChainIntegrity (fail-closed verdicts)
  - phase: 07-load-domain-model-mock-contract (Plan 02)
    provides: Load (aggregate value type) + ChainOfTrust + TrustNode + TrustEdge + RoleLoadPolicy
provides:
  - LoadListEndpoint (GET /loads/{role}, paginated envelope Response)
  - LoadDetailEndpoint (GET /loads/{loadID}, embeds ChainOfTrust per D-08)
  - LoadActionEndpoint (POST /loads/{loadID}/{action.pathSegment}, auto-IDK via D-19)
  - LoadActionEndpoint.RequestBody (actorRole + targetPartyID + respondByAt + note, with explicit acronym CodingKeys bridge)
  - LoadEndpointsTests (6 tests — endpoint shape across all 5 Roles + all 6 LoadActions + RequestBody encoding + Response decode smoke for List and Detail)
  - Role: Encodable conformance (now Codable) so it can be serialised as actor_role on the wire
  - LoadAction.pathSegment: nonisolated so nonisolated endpoint inits can read it
affects:
  - phase 07-load-domain-model-mock-contract (Plan 05 — mock fixture authoring keys off these endpoint paths)
  - phase 07-load-domain-model-mock-contract (Plan 06 — AppContainer wiring exercises the request<E> flow against these endpoints)
  - phase 08-load-list-ui (consumes LoadListEndpoint.Response.loads + nextCursor for the diffable-snapshot list)
  - phase 09-load-detail-trust-graph (consumes LoadDetailEndpoint.Response.load + chainOfTrust for the trust-graph render)
  - phase 10-load-actions (consumes LoadActionEndpoint for every per-role action button)

tech-stack:
  added: []
  patterns:
    - "Role-in-path URL scheme (D-15) — dynamic `path: String` set from init(role:) / init(loadID:) / init(loadID:action:body:), MockURLProtocol matches on url.path so the scheme works identically against mock + real backend."
    - "Paginated-envelope Response from day one (D-16) — `{ loads: [Load], nextCursor: String? }` typed at the endpoint level so Phase 8 list VMs never need a rework when the live backend ships."
    - "Embedded ChainOfTrust in detail Response (D-08) — LoadDetailEndpoint.Response carries `load: Load` AND `chainOfTrust: ChainOfTrust` for a single-round-trip detail screen. Symmetric on LoadActionEndpoint.Response (actions may flag/clean the chain)."
    - "Zero-wiring idempotency on POST (D-19) — LoadActionEndpoint.method = .post means the existing IdempotencyInterceptor auto-injects Idempotency-Key with no new wiring, no new test (IdempotencyInterceptorTests already covers it)."
    - "Explicit trailing-acronym CodingKeys bridge for targetPartyID — pins wire form to `target_party_id` regardless of any future toolchain drift in `.convertToSnakeCase` trailing-acronym handling. Same precedent as OTPVerifyEndpoint.RequestBody."

key-files:
  created:
    - validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift (D-15 role-in-path; D-16 paginated envelope)
    - validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift (D-08 embedded ChainOfTrust)
    - validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift (D-15 action-in-path; D-19 auto-IDK on POST)
    - validationLedgerTests/Networking/LoadEndpointsTests.swift (6 tests — shape + minimal decode)
  modified:
    - validationLedger/Roles/Role.swift (Decodable → Codable so Role serialises as `actor_role` in LoadActionEndpoint.RequestBody)
    - validationLedger/Core/Load/LoadAction.swift (LoadAction.pathSegment marked nonisolated for the nonisolated endpoint init)

key-decisions:
  - "LoadActionEndpoint.RequestBody — chose the 4-field catch-all (actorRole, targetPartyID, respondByAt, note) over per-action sum-type variants. Rationale: SC #1 only requires the endpoint compile and decode the Plan 05 success / 409 / 422 fixtures, and the 4 fields cover every action the v1.1 fixture matrix will exercise (tender uses targetPartyID + respondByAt; every other action passes nil for both). A per-action sum-type is a post-v1.1 refinement; today's typing trades a marginally looser server-side schema for v1.1 simplicity."
  - "LoadDetailEndpoint AND LoadActionEndpoint both embed ChainOfTrust in the Response. D-08 only mandates the embed on LoadDetailEndpoint, but the action Response carries it too because actions can flag/clean the chain (a tender to a previously-unverified counterparty flips an edge's verification state; an accept clears respondByAt). Symmetric embedding avoids a follow-up detail fetch after every action."
  - "Test suite is plain `@Suite(...)`, NOT `.serialized` — these tests do not touch MockURLProtocol's global handler array. .serialized stays reserved for Plan 04/06 tests that mutate the registry."
  - "Plan-specified simulator destination 'iPhone 15, OS=17.5' substituted with 'iPhone 17' (per CI workflow .github/workflows/ci-simulator.yml + project memory ios-test-suite-pitfalls.md). Carried convention from Plan 01 (07-01-SUMMARY.md). No CI impact — the canonical CI destination is iPhone 17."

patterns-established:
  - "GET-with-dynamic-path APIEndpoint conformer — `nonisolated public struct E: APIEndpoint`, `typealias RequestBody = EmptyBody`, `let path: String` (stored, set from init), `let method = .get`, `let body = nil`. Mirrors KYCStatusEndpoint with the path made dynamic via init parameters. Applied to LoadListEndpoint (role) and LoadDetailEndpoint (loadID)."
  - "POST-with-action-in-path APIEndpoint conformer — same shape as OTPVerifyEndpoint but the path is composed from a typed action enum's `pathSegment` instead of a hardcoded string. Closes the surface so the closed LoadAction enum is the single source of truth for the wire form (T-07-12 mitigation)."
  - "Embedded-graph Response — when a detail screen needs a subgraph, embed the subgraph value type alongside the primary entity in the same Response (LoadDetailEndpoint.Response = `{ load, chainOfTrust }`). Trades a bounded payload-size increase for a single round-trip + no graph-level loading state."
  - "Endpoint-shape-only test suite — plain `@Suite(...)` (no .serialized) sweeping all enum cases via `for case in EnumType.allCases { ... }`. Path/method/body assertions + a minimal Response decode smoke test. Fixture-decode matrix is owned by the downstream fixture plan."

requirements-completed: [LOAD-01]

# Metrics
duration: ~12 min
completed: 2026-05-19
---

# Phase 07 Plan 03: Load Endpoints (GET + POST) Summary

**Three typed APIEndpoint conformers — LoadListEndpoint (GET /loads/{role}, paginated envelope), LoadDetailEndpoint (GET /loads/{loadID}, embedded ChainOfTrust), LoadActionEndpoint (POST /loads/{loadID}/{action}, zero-wiring idempotency) — plus a 6-test endpoint-shape + minimal-decode suite covering all 5 Roles and all 6 LoadActions.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-20T00:00 (approx; commits run 16:59-17:05 PT)
- **Completed:** 2026-05-20T00:05Z
- **Tasks:** 3 (all completed)
- **Files created:** 4
- **Files modified:** 2 (Rule 3 unblocks)

## Accomplishments

- LoadListEndpoint, LoadDetailEndpoint, LoadActionEndpoint all compile against the v1.0 `APIClient.request<E: APIEndpoint>` facade with no contract changes (D-18 honoured).
- Endpoint shape verified across the entire enum surface: 5 Role × LoadListEndpoint, 6 LoadAction × LoadActionEndpoint. The D-05 spot-check confirms `advanceStatus → /loads/{id}/status` (not `/advance_status`).
- IdempotencyInterceptor auto-pickup confirmed by inspection of `Interceptors/IdempotencyInterceptor.swift:17-29` (method == "POST" || "PUT" branch) — LoadActionEndpoint.method = .post matches, no new wiring (D-19).
- Wire-format encoding verified — `actor_role`, `target_party_id` snake_case keys produced under `APIClient.defaultEncoder()`'s `.convertToSnakeCase` strategy; trailing-acronym mangling (`target_party_i_d`) explicitly negative-asserted.
- Minimal Response decode round-trips work: empty paginated envelope decodes for List; embedded ChainOfTrust with a `.clean` verdict round-trips for Detail.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LoadListEndpoint + LoadDetailEndpoint (GET endpoints)** — `1fd81fc` (feat)
2. **Task 2: Create LoadActionEndpoint (POST — auto-IDK via D-19)** — `83eeac1` (feat, includes 2 Rule-3 unblocks)
3. **Task 3: Endpoint-shape tests for the 3 new endpoints** — `a16a441` (test)

## Files Created/Modified

### Created
- `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` — GET /loads/{role} with paginated `Response { loads, nextCursor }` (D-15, D-16).
- `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` — GET /loads/{loadID} with embedded `Response { load, chainOfTrust }` (D-08, D-15).
- `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift` — POST /loads/{loadID}/{action.pathSegment} with typed `RequestBody { actorRole, targetPartyID, respondByAt, note }` and `Response { load, chainOfTrust }` (D-15, D-19).
- `validationLedgerTests/Networking/LoadEndpointsTests.swift` — 6 tests covering endpoint shape + RequestBody encoding + minimal Response decode.

### Modified (Rule 3 unblocks)
- `validationLedger/Roles/Role.swift` — `Decodable` → `Codable` so `Role` can serialise as the `actor_role` field on the wire (synthesised String-rawValue encoding; encodes as `"shipper"`, etc.).
- `validationLedger/Core/Load/LoadAction.swift` — `pathSegment` marked `nonisolated` so the `nonisolated` LoadActionEndpoint init can read it under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## Decisions Made

- **RequestBody shape (planner-finalized).** Chose the 4-field catch-all (`actorRole`, `targetPartyID`, `respondByAt`, `note`) over a per-action sum type. Rationale: every action the Plan 05 fixture matrix exercises is covered (`tender` uses targetPartyID + respondByAt; every other action passes nil for both), and SC #1 only requires the endpoint compile + decode the Plan 05 success/409/422 fixtures. A per-action sum-type variant is a post-v1.1 refinement.
- **Symmetric ChainOfTrust embed on action Response.** D-08 only mandates embedding on LoadDetailEndpoint; LoadActionEndpoint mirrors the shape so a post-action UI render (in Phase 10) does not need a follow-up detail fetch. Symmetric with the fact that actions can flag/clean the chain.
- **Plain (not `.serialized`) Swift Testing suite.** Plan 03 tests do NOT touch MockURLProtocol's global handler array; `.serialized` is reserved for Plan 04/06 mock-touching tests.
- **Simulator destination substitution.** Plan-specified `iPhone 15, OS=17.5` substituted with `iPhone 17` (the CI workflow's canonical destination at `.github/workflows/ci-simulator.yml:75`, plus the local toolchain only has iPhone 17 family installed). Same substitution rationale as Plan 01 (carried forward via 07-01-SUMMARY.md key-decisions).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Added `Encodable` conformance to `Role`**
- **Found during:** Task 2 (LoadActionEndpoint compile)
- **Issue:** Plan 02 made `Role` `Decodable` only. LoadActionEndpoint.RequestBody declares `actorRole: Role` and conforms to `Encodable`, so the synthesised Encodable conformance on RequestBody failed: `note: cannot automatically synthesize 'Encodable' because 'Role' does not conform to 'Encodable'`.
- **Fix:** Changed `public enum Role: String, CaseIterable, Sendable, Decodable` → `public enum Role: String, CaseIterable, Sendable, Codable`. Since `Role` is `String`-raw, Encodable synthesis is trivial and produces the lowercased case name on the wire (`"shipper"`, `"broker"`, etc.) — exactly the form the server's role vocabulary uses. Added a file-header note explaining the Plan 03 addition alongside the Plan 02 Decodable note.
- **Files modified:** `validationLedger/Roles/Role.swift`
- **Verification:** `xcodebuild build` succeeds; `actor_role` + the literal string `"broker"` both appear in the encoded RequestBody (Test 4 in LoadEndpointsTests).
- **Committed in:** `83eeac1` (Task 2 commit)

**2. [Rule 3 — Blocking] Marked `LoadAction.pathSegment` as `nonisolated`**
- **Found during:** Task 2 (LoadActionEndpoint compile)
- **Issue:** Under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, the `public extension LoadAction { var pathSegment: String }` in Plan 01 was inferred as main-actor-isolated. LoadActionEndpoint is a `nonisolated public struct` (required by the APIEndpoint contract's `Sendable` constraint), so its init reading `action.pathSegment` triggered: `warning: main actor-isolated property 'pathSegment' can not be referenced from a nonisolated context`. While this surfaced as a warning, it is a contract violation under strict Swift Concurrency and would have eventually escalated to an error under `-warnings-as-errors`. Belongs to Rule 3 (blocking — needed for the endpoint init to remain nonisolated).
- **Fix:** Added `nonisolated` to the `pathSegment` extension property. The computation is a pure `switch self` and main-actor-free.
- **Files modified:** `validationLedger/Core/Load/LoadAction.swift`
- **Verification:** `xcodebuild build` succeeds with zero new warnings.
- **Committed in:** `83eeac1` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 — Blocking)
**Impact on plan:** Both unblocks are scoped to what Plan 03's new code needs to compile under the v1.0 contract — neither expanded scope, neither changed `APIClient`/`APIEndpoint`/`IdempotencyInterceptor` surface (D-18 honoured). Plan 02's `Role` is now Codable (a strict superset of Decodable; no Decodable callers broken). Plan 01's `LoadAction.pathSegment` gained `nonisolated` (no isolation-narrowing — same property, broader callability).

## Issues Encountered

None beyond the two Rule 3 unblocks documented above. The test suite passed on the first run after the unblocks landed (`Executed 6 tests, with 0 failures`).

## User Setup Required

None — no external service configuration required for this plan. The 3 new endpoints inherit `apiClient.requestInterceptors` (including IdempotencyInterceptor) from the existing v1.0 wiring (D-18 / D-19).

## Threat Surface Scan

All threat-register entries from Plan 03's `<threat_model>` are honoured by inspection:

- **T-07-12 (Tampering on action.pathSegment):** Test 3 sweeps all 6 LoadAction cases; advanceStatus → "status" spot-checked. No untyped string interpolation in any endpoint init.
- **T-07-13 (Repudiation on POST without IDK):** Verified by inspection of `Interceptors/IdempotencyInterceptor.swift:17-29` — method == "POST"/"PUT" branch matches; no new wiring needed. LoadActionEndpoint.method = .post asserted in Test 3.
- **T-07-14 (Info disclosure via embedded ChainOfTrust payload):** Accepted per plan — D-08 trades round-trip for payload, bounded by the 5-tier topology.
- **T-07-15 (Spoofing via manipulated verificationState):** Test 5 (LoadDetailEndpoint smoke) decodes a ChainOfTrust with `verdict: "clean"` via the Plan 01 fail-closed `ChainIntegrity.Verdict.init(from:)`. Composition through TrustNode.verificationState is validated by the existing Plan 01 VerificationStateDecoderTests; this plan extends nothing.
- **T-07-16 (DoS via unbounded paginated envelope):** Accepted per plan — server enforces page size; Plan 05 mock fixtures author at most ~10 loads per role.

No new threat surface introduced beyond the plan's documented register.

## Next Phase Readiness

- **Plan 05 (mock fixture authoring) is unblocked.** Plan 05 will key fixtures off the paths these 3 endpoints expose (`/loads/{role}`, `/loads/{loadID}`, `/loads/{loadID}/{action}`) and the typed Response shapes they declare. The minimal Response decode smoke tests in this plan are the contract Plan 05's full fixture-decode matrix extends.
- **Plan 06 (AppContainer integration) is unblocked.** The 3 endpoints are ready to flow through `apiClient.request<E>`; the existing IdempotencyInterceptor (line 476 of AppContainer.swift) auto-picks up LoadActionEndpoint's POST without any AppContainer change.
- **Phase 8 list VM is unblocked.** LoadListEndpoint.Response's paginated envelope shape is the contract Phase 8's diffable-snapshot VM consumes.
- **Phase 9 detail/graph VM is unblocked.** LoadDetailEndpoint.Response's embedded chainOfTrust is the contract Phase 9's trust-graph render consumes.
- **Phase 10 action surface is unblocked.** LoadActionEndpoint and its typed RequestBody cover every per-role action button in the v1.1 fixture matrix.

No blockers. No carry-overs into Plan 04+.

## Self-Check: PASSED

**Created files verified:**
- `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` — FOUND
- `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` — FOUND
- `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift` — FOUND
- `validationLedgerTests/Networking/LoadEndpointsTests.swift` — FOUND

**Modified files verified:**
- `validationLedger/Roles/Role.swift` — FOUND (now Codable)
- `validationLedger/Core/Load/LoadAction.swift` — FOUND (pathSegment nonisolated)

**Commits verified in git log:**
- `1fd81fc` feat(07-03): add LoadListEndpoint and LoadDetailEndpoint (GET) — FOUND
- `83eeac1` feat(07-03): add LoadActionEndpoint (POST with auto-IDK) — FOUND
- `a16a441` test(07-03): add LoadEndpointsTests — shape + minimal decode — FOUND

**Test command exit verified:** `xcodebuild test … -only-testing:validationLedgerTests/LoadEndpointsTests` printed `** TEST SUCCEEDED **` (exit 0), 6/6 tests passing on iPhone 17 simulator destination.

---
*Phase: 07-load-domain-model-mock-contract*
*Completed: 2026-05-19*
