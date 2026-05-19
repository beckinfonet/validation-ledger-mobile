# Requirements: Validation Ledger — iOS Client

**Milestone:** v1.1 "Load Flows"
**Defined:** 2026-05-19
**Core Value:** Identity that cannot be spoofed and a chain-of-trust that cannot be faked.

v1.1 adds the freight load domain to the shipped v1.0 base — a role-filtered load
list, load detail with an interactive chain-of-trust graph, and per-role
tender/accept/reject — built entirely against `MockURLProtocol` fixtures. No
backend, no real-time, no push. Requirement IDs use new categories (LOAD, TRUST,
ACTION); v1.0's categories (FOUND, ARCH, NET, AUTH, DEV, …) are archived in
`.planning/milestones/v1.0-REQUIREMENTS.md`.

## v1.1 Requirements

Requirements for the v1.1 "Load Flows" milestone. Each maps to a roadmap phase
(phase numbering continues from v1.0 — v1.1 phases start at Phase 7).

### Load Domain

- [ ] **LOAD-01**: Load-domain mock endpoints + fixtures — `GET /loads/{role}`, `GET /loads/{id}`, `GET /parties/{id}/verification`, and `POST /loads/{id}/{tender,accept,reject,status,post,cancel}` — extend the contract-first `MockURLProtocol` pattern with per-role and per-state fixtures, including empty, error, latency, and action-failure responses
- [ ] **LOAD-02**: `Core/Load/` domain model — `Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy` as `Decodable & Sendable` value types implementing the full load state machine
- [ ] **LOAD-03**: User sees a role-filtered load list — each of the 5 roles sees only the loads relevant to it, filtered server/fixture-side (no client-side re-filtering)
- [ ] **LOAD-04**: User sees the standard freight field set on each load row — reference #, origin → destination, pickup/delivery dates, equipment, weight, rate, load-status badge, and counterparty verification badge
- [ ] **LOAD-05**: User can open a load detail screen from a load-list row
- [ ] **LOAD-06**: User sees a load status timeline on load detail — Posted → Tendered → Accepted → Dispatched → In-Transit → Delivered
- [ ] **LOAD-07**: User sees empty, loading, and error states on the load list and load detail
- [ ] **LOAD-08**: User can pull-to-refresh the load list to propagate state changes (the v1.1 substitute for deferred real-time updates)

### Chain of Trust

- [ ] **TRUST-01**: User sees an interactive chain-of-trust graph on load detail — the load's parties (shipper → broker → carrier → dispatch → factoring) rendered as a directed, pannable/zoomable node-graph
- [ ] **TRUST-02**: User sees per-party verification state (verified / pending / unverified / flagged) wherever a party appears — load row, load detail, and every graph node — via a single reusable verification badge component
- [ ] **TRUST-03**: User can tap a graph node to see that party's verification basis — KYC completion date, device-binding status, USDOT authority, and prior-relationship history
- [ ] **TRUST-04**: User can tap a graph edge to see the handoff/tender detail for that link between two parties
- [ ] **TRUST-05**: User sees double-/triple-brokering risk rendered on the graph — flagged nodes/edges and a chain-level integrity verdict, all from fixture-supplied data (never computed client-side)

### Per-Role Actions

- [ ] **ACTION-01**: Broker/Shipper can tender a load to a specific carrier; an active tender displays its respond-by deadline
- [ ] **ACTION-02**: Broker/Shipper can retender a load after a reject or an expired tender
- [ ] **ACTION-03**: Carrier/Dispatch can accept a tendered load
- [ ] **ACTION-04**: Carrier/Dispatch can reject a tendered load — the load returns to posted
- [ ] **ACTION-05**: Carrier/Dispatch can advance a load's status one step at a time — dispatched → in-transit → delivered
- [ ] **ACTION-06**: Shipper/Broker can post a draft load to the board and cancel a pre-delivery load (state actions on fixture loads; no multi-field load-creation form)
- [ ] **ACTION-07**: Broker/Shipper cannot tender to an unverified counterparty — the tender action is hard-disabled with an inline reason
- [ ] **ACTION-08**: Load actions use optimistic UI with a rollback path — the screen reverts to its pre-action state and shows an error when a (mocked) action fails
- [ ] **ACTION-09**: A load's available actions are determined per-role by a single `RoleLoadPolicy` table — each role sees only its legal actions for the load's current state; Factoring sees none

## Future Requirements

Deferred to a post-v1.1 milestone — all require a running backend. Tracked but
not in the current roadmap.

### Real-Time & Notifications

- **RT-01**: Real-time load updates (WebSocket or SSE) — replaces LOAD-08 pull-to-refresh as the state-propagation mechanism
- **RT-02**: APNs push for tender and status-change notifications, with deep links and notification categories

### Backend & Infrastructure

- **BE-01**: Real backend integration — swap the contract-first `MockURLProtocol` fixtures for the live backend (one-line config swap by design)
- **BE-02**: File-based background `URLSession` upload rework (ratified M2 follow-up from v1.0's KYC uploader)
- **BE-03**: Crash/analytics vendor pick behind a `CrashReporter` protocol

### Load Domain (post-v1.1)

- **LOAD-F1**: Full multi-field load-creation form (multi-stop, commodity, accessorials, rate entry) for Shipper/Broker
- **LOAD-F2**: Factoring invoice-submission write-path and the `invoiced` / `funded` state transitions

## Out of Scope

Explicitly excluded from v1.1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Client-side load filtering / re-scoping the list | A client that can see other roles' loads is a data-exposure bug and a fraud vector — the mock/backend filters by role, the client only renders |
| Client-side trust or chain-integrity computation | Client-derived trust is bypassable and contradicts "the chain of trust cannot be faked" — verification state and the integrity verdict are server-supplied, render-only |
| eBOL rendering / rotating QR / dock scanner on load detail | Explicit M3 milestone; pulls in the deferred backend-signing dependency |
| POD signature/photo capture + `pod_captured` transition | M3 (eBOL/POD milestone) |
| Map / live truck-location tracking on a load | Needs M3 background location + a live backend feed |
| In-app messaging between load counterparties | M4/v2 concern; must never be a third-party SDK |
| Editable load fields on the detail screen | Mutable load data mid-lifecycle is a rate/commodity tampering surface — v1.1 load detail is read-only except for role-action buttons |
| Real-time updates, APNs push, real backend, background `URLSession`, crash/analytics vendor | Deferred to a post-v1.1 milestone — see Future Requirements (all need a running server) |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LOAD-01 | Phase 7 | Pending |
| LOAD-02 | Phase 7 | Pending |
| LOAD-03 | Phase 8 | Pending |
| LOAD-04 | Phase 8 | Pending |
| LOAD-05 | Phase 9 | Pending |
| LOAD-06 | Phase 9 | Pending |
| LOAD-07 | Phase 8 | Pending |
| LOAD-08 | Phase 8 | Pending |
| TRUST-01 | Phase 9 | Pending |
| TRUST-02 | Phase 8 | Pending |
| TRUST-03 | Phase 9 | Pending |
| TRUST-04 | Phase 9 | Pending |
| TRUST-05 | Phase 9 | Pending |
| ACTION-01 | Phase 10 | Pending |
| ACTION-02 | Phase 10 | Pending |
| ACTION-03 | Phase 10 | Pending |
| ACTION-04 | Phase 10 | Pending |
| ACTION-05 | Phase 10 | Pending |
| ACTION-06 | Phase 10 | Pending |
| ACTION-07 | Phase 10 | Pending |
| ACTION-08 | Phase 10 | Pending |
| ACTION-09 | Phase 10 | Pending |

**Coverage:**
- v1.1 requirements: 22 total
- Mapped to phases: 22 ✓
- Unmapped: 0 ✓

**Per-phase distribution:**
- Phase 7 (Load Domain Model & Mock Contract): LOAD-01, LOAD-02 — 2 requirements
- Phase 8 (Role-Filtered Load List): LOAD-03, LOAD-04, LOAD-07, LOAD-08, TRUST-02 — 5 requirements
- Phase 9 (Load Detail & Chain-of-Trust Graph): LOAD-05, LOAD-06, TRUST-01, TRUST-03, TRUST-04, TRUST-05 — 6 requirements
- Phase 10 (Per-Role Tender / Accept / Reject): ACTION-01 through ACTION-09 — 9 requirements

---
*Requirements defined: 2026-05-19*
*Last updated: 2026-05-19 — traceability populated against the v1.1 roadmap (Phases 7-10)*
