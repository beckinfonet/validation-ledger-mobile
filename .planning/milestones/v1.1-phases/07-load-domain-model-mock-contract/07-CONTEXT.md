# Phase 7: Load Domain Model & Mock Contract — Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

The contract-first foundation for all of v1.1 — no UI. This phase delivers:

- `Core/Load/` value types — `Load`, `ChainOfTrust`, `TrustNode`, `TrustEdge`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy`, `LoadStatusEvent`, `VerificationState`, `ChainIntegrity` — all `Decodable & Sendable`.
- The load state machine (full lifecycle, server-supplied `stateHistory`).
- `RoleLoadPolicy.actions(for:status:)` — a pure `(Role, LoadStatus) → [LoadAction]` table, exhaustively unit-tested across all 5 roles × every status.
- 3 typed `APIEndpoint` conformers: `LoadListEndpoint`, `LoadDetailEndpoint`, `LoadActionEndpoint`.
- `MockLoadFixtureRegistry` + the full fixture matrix (per-role lists, per-state loads, three fraud-archetype loads, empty/error/latency/action-failure).
- An additive latency / forced-failure capability on `MockURLProtocol` that preserves its existing path+method matching and `register/reset/registerFixture` API.

What this phase is **not**: any view controller, view model, coordinator, cell, tab wire-up, or design-system component. Those land in Phases 8–10 against the contract this phase freezes.

</domain>

<decisions>
## Implementation Decisions

### Status Enum Scope
- **D-01:** `LoadStatus` is a full-lifecycle enum: primary path `draft, posted, tendered, accepted, dispatched, inTransit, delivered`; side-states `rejected, expired, cancelled`; post-delivery `podCaptured, invoiced, funded` are **display-only** (v1.1 has no interactive transitions into the last three). Rationale: Factoring's list and post-delivery loads render with real content; M3/post-v1.1 can add transitions with zero enum churn.
- **D-02:** `Load` carries `stateHistory: [LoadStatusEvent]` — each event is `{ status, timestamp, actor: LoadParty? }`. The LOAD-06 status timeline renders from this array (real "Tendered 2 days ago" data); timeline UI does NOT derive position purely from current status.

### Action Policy Table (`RoleLoadPolicy`)
- **D-03:** Tender gate is `posted`-only. `post` moves `draft → posted`; `tender` acts only on a `posted` load. Single linear timeline — no direct `draft → tendered` path.
- **D-04:** `retender` (ACTION-02) is **not** a distinct `LoadAction`. After a reject or tender expiry the load returns to `posted`, which already affords `tender`. Prior rejected/expired tenders are recorded in `stateHistory`. Retender = `tender` invoked again.
- **D-05:** ACTION-05 status advancement is a **single** `LoadAction.advanceStatus`; the target state is derived as the next step in the canonical order (`dispatched → inTransit → delivered`). `RoleLoadPolicy` returns `[.advanceStatus]`, not three per-transition cases.
- **D-06:** `RoleLoadPolicy` collapses 5 roles to 3 surfaces: Shipper ≡ Broker (`post`, `tender`, `cancel`), Carrier ≡ Dispatch (`accept`, `reject`, `advanceStatus`), Factoring = empty for every state. Not differentiated within each pair.

### Trust Data Model
- **D-07:** `TrustNode` carries **typed** verification-basis fields — `kycCompletedAt: Date?`, `deviceBindingStatus: DeviceBindingStatus`, `usdotNumber: String?` + `usdotAuthorityStatus`, `priorRelationshipCount: Int` (or a small typed list). The four facts are a fixed known set, so the iOS UI controls presentation. NOT an opaque server-formatted fact list.
- **D-08:** `ChainOfTrust = { nodes: [TrustNode], edges: [TrustEdge], integrity: ChainIntegrity }`. `TrustEdge` carries the handoff/tender detail (TRUST-04) and its own edge-level flag state. `ChainIntegrity` = a verdict enum (indicative: `clean / caution / compromised` — exact cases a planner detail) + a human-readable `reason` + the implicated node/edge IDs. `ChainOfTrust` is **embedded in `LoadDetailEndpoint.Response`** — one round-trip, no separate graph fetch, no graph-level loading state.
- **D-09:** `VerificationState` is a closed enum `{ verified, pending, unverified, flagged }`. `flagged` = actively suspicious / known fraud signal — semantically distinct from `unverified` = simply not-yet-verified. Decoding fails **closed**: an unknown/unrecognized JSON value decodes to `unverified` (least-trusted); a **missing** field is a hard decode error (strict contract). No client code path may upgrade trust from local logic.

### Fixture Scenarios
- **D-10:** Fixtures are a **coherent fraud-detection narrative**, not minimal mechanical coverage — a named-load library where every load tells a story that exercises the platform thesis. Mechanical states layer on top.
- **D-11:** **One shared consistent world** — a single underlying load set. Each role's `loads-list-{role}.json` is that role's view onto the same loads (load VL-#### appears in the broker's list as "you tendered this" and in the carrier's list as "tendered to you", with the same `ChainOfTrust`). The 5 role list fixtures are not independent.
- **D-12:** The named-load library collectively covers every `LoadStatus`, all four `VerificationState` values, all `ChainIntegrity` verdicts, and every action path. Indicative set (planner finalizes IDs and count):
  - a clean verified delivered load (full `stateHistory`)
  - a `posted` load awaiting tender (clean chain)
  - an active tender with `respondByAt` deadline (drives accept/reject)
  - an expired-tender load reverted to `posted` (stateHistory shows the expiry → drives retender)
  - a `draft` load (drives `post`)
  - an in-transit / dispatched load (drives `advanceStatus`)
  - a load with an unverified target counterparty (drives ACTION-07 refuse-to-tender)
  - post-delivery loads — `podCaptured`, `invoiced`, `funded` — for Factoring's list
- **D-13:** **All three PROJECT.md fraud archetypes** get a distinct flagged load:
  - (a) double-/triple-brokering — flagged carrier node, flagged edge, `chainIntegrity = compromised`
  - (b) chameleon carrier — suspect identity/authority history surfaced in the node basis + `integrity.reason`
  - (c) factoring fraud — flagged factoring party on a double-brokered shipment
  Same render mechanism for all three (flagged node/edge + `integrity.reason` text); no model change.
- **D-14:** Mechanical fixtures (the matrix beyond the narrative): per-role empty-list fixture, a server-error response, an injected-latency (slow) fixture, and action-failure fixtures — 409 conflict (stale / already-actioned), 422 validation, and timeout. Each exercised by a unit test. Exact HTTP codes are a planner detail; the categories are fixed.

### Contract Shape — Carried from Research (Locked, Not Re-Litigated)
- **D-15:** **Role-in-path URL scheme** — `GET /loads/{role}` (and `/loads/{id}`, `POST /loads/{id}/{action}`), NOT a `?role=` query string. `MockURLProtocol.registerFixture` matches on `request.url?.path`, which excludes the query string (confirmed in `Mock/MockFixture.swift:21`). Role-in-path needs zero matcher change and routes equivalently against a real backend.
- **D-16:** **`LoadListEndpoint.Response` is a paginated envelope from day one** — e.g. `{ loads: [Load], nextCursor: String? }` — even though v1.1 fixtures always return a single page. Prevents the list VM / diffable-snapshot rework at the eventual live-backend swap (research PITFALLS: "load list built without pagination").
- **D-17:** New load fixtures are registered via a **dedicated `MockLoadFixtureRegistry`** mirroring the existing `MockOTPRoleFixtureRegistry` (`Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift`). Called from the DEBUG-gated block in `AppContainer.init` that already calls `MockDefaultFixtures.registerAppDefaults()`. `MockDefaultFixtures` is NOT extended for the load domain — keeps it from growing unbounded and lets the registry vary response by role.
- **D-18:** All `Core/Load/` types are pure `Decodable & Sendable` value types. **No client-derived trust field** — `verificationState` and `chainIntegrity` are server/fixture-supplied and render-only. `APIClient`, `APIEndpoint`, `IdempotencyInterceptor` are **UNCHANGED**; `MockURLProtocol` is extended only **additively** with the latency/failure-injection capability (its existing path+method matching and `register/reset/registerFixture` API stay byte-identical — roadmap SC #5).
- **D-19:** `LoadActionEndpoint` is a POST so it automatically picks up the shipped `IdempotencyInterceptor` (no new infrastructure for action-domain idempotency).

### Claude's Discretion
The planner / researcher may finalize:
- Exact `ChainIntegrity` verdict enum cases (indicative: `clean / caution / compromised`).
- Exact named-load IDs and the precise count of fixture loads (D-12 set is indicative).
- Exact HTTP status codes for the failure fixtures (409/422/timeout are indicative).
- The latency / forced-failure injection mechanism on `MockURLProtocol` (additive; must not change existing API per D-18).
- Whether `priorRelationshipCount` is a bare `Int` or a small `[PriorRelationship]` typed list.
- snake_case ↔ camelCase / ISO-8601 decoding strategy — follow the v1.0 house pattern (see `KYCStatusEndpoint.swift` for the canonical shape).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/REQUIREMENTS.md` — LOAD-01 (mock endpoints + fixture matrix), LOAD-02 (`Core/Load/` domain model); the v1.1 Out-of-Scope table; the per-phase requirement distribution.
- `.planning/ROADMAP.md` — Phase 7 goal, success criteria #1–#5, dependency on Phase 6 (v1.0 networking contract).
- `.planning/PROJECT.md` — v1.1 scope, constraints (UIKit-first, SwiftPM-only, iOS 17, MockURLProtocol-only), Key Decisions table (Phase 7 contract-first decision is row 17).

### v1.1 research (current, source-grounded — read before stale codebase maps)
- `.planning/research/SUMMARY.md` — executive synthesis; the canonical load state machine; the per-role action matrix; the 5 critical pitfalls.
- `.planning/research/ARCHITECTURE.md` — the integration architecture; `Core/Load/` placement; `MockLoadFixtureRegistry` pattern; the role-in-path caveat (the source of D-15).
- `.planning/research/FEATURES.md` — load-domain feature coverage and dependency order.
- `.planning/research/PITFALLS.md` — the 10 v1.1 pitfalls; verification-state-must-be-server-supplied, fixture matrix, optimistic-with-rollback, pagination.
- `.planning/research/STACK.md` — confirms zero new dependencies; the trust-graph rendering decision (Phase 9 concern, but the contract here must not foreclose it).

### v1.0 source files this phase extends (treat as authoritative — codebase maps are stale)
- `validationLedger/Core/Networking/APIEndpoint.swift` — the `APIEndpoint` protocol the 3 new endpoints conform to.
- `validationLedger/Core/Networking/APIClient.swift` — `request<E: APIEndpoint>` accepts the new endpoints with zero change.
- `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — the protocol that needs the additive latency/failure-injection capability (currently synchronous/instant; confirmed lines 21–60).
- `validationLedger/Core/Networking/Mock/MockFixture.swift` — `registerFixture<E: APIEndpoint>`; matches on `url.path + method` (not query string — basis of D-15).
- `validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` — the exact per-role registry pattern `MockLoadFixtureRegistry` mirrors.
- `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift` — the DEBUG organic tap-through registration site; AppContainer calls it from the DEBUG block where the new load registry also goes.
- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` — POST endpoints auto-pick up idempotency keys (relevant to `LoadActionEndpoint` shape; gates Phase 10).
- `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` — the canonical `APIEndpoint` conformer shape the 3 new endpoints should mirror (`nonisolated public struct`, `EmptyBody` for GETs, `Decodable & Sendable Response`).
- `validationLedger/Roles/Role.swift` — the existing `Role` type consumed by `RoleLoadPolicy` and `LoadListEndpoint(role:)`.
- `validationLedger/App/AppContainer.swift` — the only MODIFIED file outside `Core/Load/` and the new endpoint/registry files; load fixture registry registers in its DEBUG block.
- `validationLedgerTests/Networking/Fixtures/kyc-status-*.json` — the JSON-fixture-per-endpoint-state convention (file naming, per-state granularity).

### v1.0 milestone context (informational; cite if needed)
- `.planning/milestones/v1.0-REQUIREMENTS.md` — archived v1.0 requirements (FOUND/ARCH/NET/AUTH/DEV/KYC/UPL/SHELL/SESS/GEO/SEC/LOG/CI).
- `.planning/milestones/v1.0-MILESTONE-AUDIT.md` — v1.0 close-out audit; tech debt that did NOT block v1.1.

### Stale — do not rely on
- `.planning/codebase/*.md` (all 7 files dated 2026-04-21, "brand-new SwiftUI scaffold") — predates all of v1.0. Research ARCHITECTURE.md flags this explicitly. The source tree is authoritative.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`APIEndpoint` / `APIClient` facade** (`Core/Networking/APIEndpoint.swift`, `APIClient.swift`): the 3 new load endpoints conform to `APIEndpoint`; `APIClient.request<E>` accepts them unchanged.
- **`MockURLProtocol` + `MockFixture.registerFixture`** (`Core/Networking/Mock/`): the registration helper is generic over `E: APIEndpoint` and matches on `url.path` + method; new endpoints "just work" once registered.
- **`MockOTPRoleFixtureRegistry`** (`Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift`): the per-role registry pattern. `MockLoadFixtureRegistry` mirrors it exactly (takes a `Role`, varies response by role).
- **`MockDefaultFixtures.registerAppDefaults()`** (`Core/Networking/Mock/MockDefaultFixtures.swift`): the DEBUG organic tap-through pattern. The new load registry is registered from the same `AppContainer.init` DEBUG block (parallel call, not an extension of MockDefaultFixtures).
- **`IdempotencyInterceptor`** (`Core/Networking/Interceptors/IdempotencyInterceptor.swift`): POST endpoints auto-pick up idempotency keys — `LoadActionEndpoint` (POST) inherits this with zero new wiring; double-tap protection is free.
- **v1.0 endpoint conformers** (`Core/Networking/Endpoints/KYCStatusEndpoint.swift` et al.): the canonical `nonisolated public struct` shape with `EmptyBody`/typed `RequestBody` and `Decodable & Sendable Response`.
- **`Roles/Role.swift`**: the existing `Role` enum, consumed by `RoleLoadPolicy.actions(for:status:)` and `LoadListEndpoint(role:)`.
- **Test fixture convention** (`validationLedgerTests/Networking/Fixtures/`): JSON-file-per-endpoint-state naming (e.g. `kyc-status-pending.json`, `kyc-status-rejected.json`). Load fixtures follow the same naming: `loads-list-{role}.json`, `load-detail-{state-or-scenario}.json`, `load-action-{outcome}.json`.

### Established Patterns
- **Contract-first** (v1.0 Phase 2 lesson): endpoints + mock fixtures land before any UI consumes them; this phase IS that contract for v1.1.
- **`nonisolated public struct` APIEndpoint conformers**: `path`, `method`, `body`, an `Encodable RequestBody` (or `EmptyBody` for GETs), and a `Decodable & Sendable Response`. Three new conformers follow this shape.
- **Pure, simulator-testable rule objects extracted from UIKit**: `KYCFlowSequencer` is the v1.0 analog for what `RoleLoadPolicy` becomes here — a table you exhaustively unit-test without UIKit.
- **Per-role mock fixture variation**: `MockOTPRoleFixtureRegistry.registerForRole(_:)` is the model `MockLoadFixtureRegistry` follows.
- **`Core/` holds shared domain types** importable by all `Roles/` and `Features/` without tripping `no_cross_feature_import`. `Core/Load/` is the new sibling of `Core/Identity/`, `Core/Auth/`, `Core/KeyStore/`.
- **JSON fixture per endpoint state**: one file per scenario, not one mega-fixture; tests register the file they need after `MockURLProtocol.reset()`.

### Integration Points
- **NEW directory:** `validationLedger/Core/Load/` — the load domain kernel (8–10 small files).
- **NEW files in `validationLedger/Core/Networking/Endpoints/`**: `LoadListEndpoint.swift`, `LoadDetailEndpoint.swift`, `LoadActionEndpoint.swift`.
- **NEW file:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` (mirrors `MockOTPRoleFixtureRegistry.swift`).
- **NEW JSON fixtures** under `validationLedgerTests/Networking/Fixtures/`: per-role list, per-scenario detail, action-outcome variants, mechanical states.
- **MODIFIED:** `validationLedger/App/AppContainer.swift` — one DEBUG-block addition to register the load fixture registry. This is the **only** non-`Core/Load/`-or-new-fixture-file change in Phase 7. No `Roles/`, `Features/`, coordinator, or VC edits.
- **MODIFIED (additively only):** `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — gains latency / forced-failure injection without altering its existing path+method matching or the `register/reset/registerFixture` API surface (roadmap SC #5).

</code_context>

<specifics>
## Specific Ideas

- **Named-load library is "demo data" for v1.1, not test fixtures.** Phase 7's success bar is decode-tests-pass, but the same fixtures are what Phase 8 (list) and Phase 9 (detail + graph) actually render. Treat fixture authoring as a product surface — names, dates, parties, dollar amounts that read realistically.
- **The three fraud archetypes are the milestone's reason to exist.** The double-brokered load, chameleon-carrier load, and factoring-fraud load are not edge cases — they are the loads the trust graph exists to render. The flagged-node + flagged-edge + `chainIntegrity.reason` data must be specific enough that the Phase 9 graph demo shows a recognizable fraud pattern.
- **Shared consistent world across role fixtures.** A demo switching from broker → carrier → factoring on the same load is the v1.1 narrative. Author fixtures with that in mind: VL-#### appears in N role list files with role-appropriate framing, the same `ChainOfTrust` across them.
- **Fail-closed verification decoding is a security primitive, not polish.** D-09's "unknown value → `unverified`" must be implemented as a custom `Decodable` initializer with a default-on-unknown branch, not a regex-and-pray afterthought. The custom decoder is itself unit-tested.

</specifics>

<deferred>
## Deferred Ideas

No scope-creep ideas emerged in this discussion — every gray area resolved into a Phase 7 contract decision. The discussion stayed inside the phase boundary.

The roadmap and PROJECT.md already record what's deferred from v1.1 to a later milestone (real-time updates, APNs push, real backend, background `URLSession` rework, crash/analytics vendor pick); none of those touch the Phase 7 contract.

### Reviewed Todos (not folded)
- **`device-ci-biometric-infra.md`** — v1.0 physical-device CI infrastructure todo (a Face ID prompt hangs the device-CI lane as an unsatisfiable biometric input, manifesting as a 35-minute timeout). Matched only on the generic keywords `status` and `phase`; unrelated to a contract / data-model phase. **Not folded.** Remains a carried v1.0 infrastructure item.

</deferred>

---

*Phase: 7 — Load Domain Model & Mock Contract*
*Context gathered: 2026-05-19*
