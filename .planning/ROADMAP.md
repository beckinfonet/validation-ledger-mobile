# Roadmap: Validation Ledger — iOS Client

## Milestones

- ✅ **v1.0 M1 Foundation** — Phases 1-6 (shipped 2026-05-18)
- 🚧 **v1.1 Load Flows** — Phases 7-10 (in progress)

## Phases

<details>
<summary>✅ v1.0 M1 Foundation (Phases 1-6) — SHIPPED 2026-05-18</summary>

- [x] Phase 1: Foundational Conventions & Scaffolding (7/7 plans) — completed 2026-04-21
- [x] Phase 2: Networking Contract & Device Keys (7/7 plans) — completed 2026-04-21
- [x] Phase 3: OTP Auth + Role Shell + Session (13/13 plans) — completed 2026-04-22
- [x] Phase 4: App Attest & Physical-Device CI Hardening (11/11 plans) — completed 2026-05-16
- [x] Phase 5: KYC Capture & Upload Pipeline (13/13 plans) — completed 2026-05-18
- [x] Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification (4/4 plans) — completed 2026-05-18

Full phase detail, success criteria, and milestone summary archived at `.planning/milestones/v1.0-ROADMAP.md`.

</details>

### 🚧 v1.1 Load Flows (In Progress)

**Milestone Goal:** Deliver the freight load domain end-to-end on iOS — a role-filtered load list, a load detail screen with an interactive chain-of-trust graph, and per-role tender/accept/reject — built entirely against `MockURLProtocol` fixtures, with zero backend, real-time, or push dependency.

- [ ] **Phase 7: Load Domain Model & Mock Contract** - The contract-first foundation: `Core/Load/` value types, the load state machine, `RoleLoadPolicy`, the 3 typed endpoints, and the full fixture matrix.
- [ ] **Phase 8: Role-Filtered Load List** - Each of the 5 roles taps a real "Loads" tab and sees only its loads, with verification badges, empty/loading/error states, and pull-to-refresh.
- [ ] **Phase 9: Load Detail & Chain-of-Trust Graph** - Load detail with a status timeline and the interactive shipper→broker→carrier→dispatch→factoring trust graph; tap a node for its verification basis.
- [ ] **Phase 10: Per-Role Tender / Accept / Reject** - Each role takes only its legal actions; loads advance state with optimistic UI and a rollback path; refuse-to-tender-to-unverified is enforced.

## Phase Details

<details>
<summary>✅ v1.0 M1 Foundation — Phase Details (archived)</summary>

Full v1.0 phase goals, success criteria, requirement mappings, and plan lists are archived verbatim at `.planning/milestones/v1.0-ROADMAP.md`. Summary in `.planning/MILESTONES.md`.

</details>

### Phase 7: Load Domain Model & Mock Contract

**Goal**: Establish the contract-first load foundation — the domain value types, the full load state machine, the per-role action policy table, the typed load endpoints, and a fixture matrix covering every state and failure mode — so that every subsequent screen decodes a stable contract and never blocks on schema churn.
**Depends on**: Phase 6 (v1.0 networking contract — `APIClient`, `APIEndpoint`, `MockURLProtocol`)
**Requirements**: LOAD-01, LOAD-02
**Success Criteria** (what must be TRUE):

  1. The 3 load endpoints (`LoadListEndpoint`, `LoadDetailEndpoint`, `LoadActionEndpoint`) decode every fixture — per-role list, per-state load, empty, error, latency, and action-failure — in passing unit tests.
  2. `RoleLoadPolicy.actions(for:status:)` is exhaustively unit-tested across all 5 roles × every `LoadStatus`, and Factoring returns an empty action set for every state.
  3. The `Core/Load/` value types (`Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy`) are pure `Decodable & Sendable` types carrying a server-supplied `verificationState` and `chainIntegrity` (no client-derived trust field).
  4. `MockURLProtocol` supports injectable latency and forced-failure responses, exercised by a test.
  5. The one-line mock/live network swap still compiles and passes with the new endpoints registered — no change to `APIClient` or `MockURLProtocol` core.

**Plans**: 6 plans

Plans:
**Wave 1**

- [ ] 07-01-PLAN.md — Core/Load/ leaf enums (LoadStatus, LoadAction, VerificationState, ChainIntegrity, DeviceBindingStatus, USDOTAuthorityStatus) + fail-closed decoder tests
- [ ] 07-04-PLAN.md — Additive MockURLProtocol latency + forced-failure injection + 8 verification tests

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 07-02-PLAN.md — Core/Load/ aggregates (LoadStatusEvent, ChainOfTrust, Load) + RoleLoadPolicy + 5×13 matrix tests

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 07-03-PLAN.md — 3 typed APIEndpoint conformers (LoadList, LoadDetail, LoadAction) + endpoint-shape tests

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 07-05-PLAN.md — 22 JSON fixtures (12 named loads + 5 role lists + empty + 4 action outcomes) + 3 decode-coverage test suites

**Wave 5** *(blocked on Wave 4 completion)*

- [ ] 07-06-PLAN.md — MockLoadFixtureRegistry + AppContainer.init wiring + SC #5 mock/live swap smoke test

### Phase 8: Role-Filtered Load List

**Goal**: Give every one of the 5 roles a working "Loads" tab that fetches and renders only its own loads from the mock contract, with the standard freight row, the reusable verification badge, the empty/loading/error states, and pull-to-refresh as the v1.1 state-propagation path.
**Depends on**: Phase 7
**Requirements**: LOAD-03, LOAD-04, LOAD-07, LOAD-08, TRUST-02
**Success Criteria** (what must be TRUE):

  1. Tapping "Loads" in any of the 5 role shells shows a list scoped to that role — the list is filtered fixture-side, never re-filtered on the client.
  2. Each load row shows the standard freight field set — reference #, origin → destination, pickup/delivery dates, equipment, weight, rate, status badge, and a counterparty verification badge.
  3. The list shows distinct empty, loading, and error states, each exercised against its own fixture.
  4. Pull-to-refresh re-fetches the list and reflects any fixture state change.
  5. A single reusable verification badge component renders the four states (verified / pending / unverified / flagged) and is used on the load row; the list renders natively (not scaled) on iPad regular width.

**Plans**: TBD
**UI hint**: yes

Plans:

- [ ] 08-01: TBD

### Phase 9: Load Detail & Chain-of-Trust Graph

**Goal**: Deliver the load detail screen — the host for the marquee chain-of-trust graph — with a load status timeline and an interactive, pannable/zoomable shipper→broker→carrier→dispatch→factoring node-graph that renders server-supplied verification state and double-brokering risk, and lets the user tap a node for its verification basis and an edge for handoff detail.
**Depends on**: Phase 8
**Requirements**: LOAD-05, LOAD-06, TRUST-01, TRUST-03, TRUST-04, TRUST-05
**Success Criteria** (what must be TRUE):

  1. Tapping a load-list row opens a read-only load detail screen showing the full load summary.
  2. Load detail shows a status timeline rendering the Posted → Tendered → Accepted → Dispatched → In-Transit → Delivered progression with completed, current, and future states visually distinct.
  3. Load detail renders an interactive chain-of-trust graph — the load's parties as a directed, pannable/zoomable node-graph, each node carrying a verification badge.
  4. Tapping a graph node opens that party's verification basis (KYC completion date, device-binding status, USDOT authority, prior-relationship history); tapping an edge shows that handoff/tender detail.
  5. Flagged nodes/edges and the chain-level integrity verdict are rendered distinctly from fixture-supplied data — the client never computes trust or integrity; the graph renders natively on iPad and is VoiceOver-traversable.

**Plans**: TBD
**UI hint**: yes
**Notes**: Highest-complexity, highest-design-investment phase in v1.1. Research flags this phase for a design spike at plan time — Phase 9 planning should open with an explicit half-day spike resolving (a) the four-state visual language as a design artifact, (b) the gesture-arbitration model (tap vs. page-scroll vs. graph pan/zoom) written into the plan before code, (c) VoiceOver traversal order and accessibility element setup, and (d) the iPad-wide vs. iPhone-tall graph layout decision. The rendering approach is already settled by research — custom UIKit `UIView` nodes with `CAShapeLayer` edges, zero new dependencies, no SwiftUI; ratify this in the plan before any graph code is written. Edge-tap detail (TRUST-04) is the most plausible scope-trim candidate if the phase runs long — node-tap (TRUST-03) is essential, edge-tap is the cut line.

### Phase 10: Per-Role Tender / Accept / Reject

**Goal**: Make loads actionable — each role sees and can take only its legal actions for the load's current state, every action mutates load state through optimistic UI with a rollback path, and the platform thesis is enforced in the load domain by hard-disabling tender to an unverified counterparty.
**Depends on**: Phase 9 (load detail VM) and Phase 7 (`RoleLoadPolicy`)
**Requirements**: ACTION-01, ACTION-02, ACTION-03, ACTION-04, ACTION-05, ACTION-06, ACTION-07, ACTION-08, ACTION-09
**Success Criteria** (what must be TRUE):

  1. A load's action bar shows only the legal actions for the signed-in role and the load's current state, driven entirely by `RoleLoadPolicy` — Broker/Shipper can tender, retender, post, and cancel; Carrier/Dispatch can accept, reject, and advance status one step at a time; Factoring sees no actions.
  2. Accepting, rejecting, or advancing a load visibly changes its state and recomputes the available action set; an active tender displays its respond-by deadline, and a reject returns the load to posted.
  3. The tender action is hard-disabled with an inline reason when the target counterparty is not verified.
  4. A failed (mocked) action rolls the screen back to its pre-action state and shows an error; in-flight actions are disabled to prevent double-submit and route through the v1.0 idempotency interceptor.
  5. After a successful action, the load list reflects the new state on pop-back.

**Plans**: TBD
**UI hint**: yes
**Notes**: The most cross-role-sensitive surface. Plan-time checklist must include an explicit item verifying every action endpoint is registered with the v1.0 idempotency interceptor, and that the rollback path ships in the same plan as the forward path for every action. Zero `switch load.status` in any view controller or cell — all action gating flows from `RoleLoadPolicy`. `post` and `cancel` (ACTION-06) act on pre-existing fixture loads as state actions — there is no multi-field load-creation form in v1.1.

## Progress

**Execution Order:**
Phases execute in numeric order: 7 → 8 → 9 → 10

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundational Conventions & Scaffolding | v1.0 | 7/7 | Complete | 2026-04-21 |
| 2. Networking Contract & Device Keys | v1.0 | 7/7 | Complete | 2026-04-21 |
| 3. OTP Auth + Role Shell + Session | v1.0 | 13/13 | Complete | 2026-04-22 |
| 4. App Attest & Physical-Device CI Hardening | v1.0 | 11/11 | Complete | 2026-05-16 |
| 5. KYC Capture & Upload Pipeline | v1.0 | 13/13 | Complete | 2026-05-18 |
| 6. Close gap: DEV-04 + trustTier + Phase 4 verification | v1.0 | 4/4 | Complete | 2026-05-18 |
| 7. Load Domain Model & Mock Contract | v1.1 | 0/6 | Planned | - |
| 8. Role-Filtered Load List | v1.1 | 0/TBD | Not started | - |
| 9. Load Detail & Chain-of-Trust Graph | v1.1 | 0/TBD | Not started | - |
| 10. Per-Role Tender / Accept / Reject | v1.1 | 0/TBD | Not started | - |

---
*Milestone v1.0 "M1 Foundation" shipped 2026-05-18 — see `.planning/MILESTONES.md`. Roadmap created 2026-04-20. v1.1 "Load Flows" phases 7-10 added 2026-05-19.*
