# Phase 7: Load Domain Model & Mock Contract - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 7-Load Domain Model & Mock Contract
**Areas discussed:** Status enum scope, Action policy table, Trust data model, Fixture scenarios

Discussion order: Status enum → Action policy → Trust data model → Fixture scenarios (foundation-first; fixtures depend on the prior three).

---

## Status Enum Scope

### Q1: How far should the LoadStatus enum extend past 'delivered'?

| Option | Description | Selected |
|--------|-------------|----------|
| Full lifecycle (Recommended) | Enum carries draft, posted, tendered, accepted, dispatched, in_transit, delivered + rejected/expired/cancelled side-states + pod_captured, invoiced, funded as display-only (no v1.1 interactive transitions). Factoring's list and post-delivery loads have real content; M3/post-v1.1 adds transitions with zero enum churn. | ✓ |
| Stop at delivered | Enum is draft..delivered + rejected/expired/cancelled only. Omit pod_captured/invoiced/funded until the milestone that actually transitions through them. Smaller surface; Factoring sees delivered loads as its terminal state. | |

**User's choice:** Full lifecycle
**Notes:** Matches research recommendation; gives Factoring's list content without enum churn later.

### Q2: How should the load detail status timeline (LOAD-06) get its data?

| Option | Description | Selected |
|--------|-------------|----------|
| Server-supplied history (Recommended) | Load carries a stateHistory: [LoadStatusEvent] array (status + timestamp + optional actor party). Timeline renders real data ('Tendered 2 days ago'), stays render-only per the platform thesis, and matches what a live backend will return. | ✓ |
| Derive from current status | Timeline UI computes completed/current/future purely from the current status's position in the canonical order. No history array, no per-transition timestamps. Simpler contract, but the timeline can't show when each step happened. | |

**User's choice:** Server-supplied history
**Notes:** Reinforces render-only; future-proof for the live backend.

---

## Action Policy Table

Treated as locked (not asked): Shipper ≡ Broker, Carrier ≡ Dispatch, Factoring = empty — research collapsed the 5 roles to 3 surfaces and ACTION-01/-06 consistently pair "Broker/Shipper".

### Q1: What state must a load be in to be tendered?

| Option | Description | Selected |
|--------|-------------|----------|
| Posted only (Recommended) | A draft must be posted to the board first; tender acts only on a 'posted' load. Single clean linear timeline (draft → posted → tendered) that matches the LOAD-06 timeline and the EDI 204 model. RoleLoadPolicy stays a simple table. | ✓ |
| Posted or draft | Broker/Shipper can tender a draft directly to a carrier without publishing to the board (real freight behavior — direct tender vs. load board). 'post' becomes a separate optional board-publish action. More faithful, but two tender entry states to test and render. | |

**User's choice:** Posted only

### Q2: Is 'retender' (ACTION-02) a distinct action from 'tender'?

| Option | Description | Selected |
|--------|-------------|----------|
| Same action, reused (Recommended) | After a reject/expiry the load returns to 'posted', and 'posted' already affords 'tender' — so retender is just tender again. RoleLoadPolicy needs no extra case; the load's tender history lives in stateHistory. One fewer action to enum and test. | ✓ |
| Distinct LoadAction.retender | Retender is its own enum case with its own button label and audit/idempotency identity. Clearer intent in logs and UI, but adds a case to the action enum and the policy table. | |

**User's choice:** Same action, reused

### Q3: How should one-step status advancement (ACTION-05: dispatched → in_transit → delivered) be modeled?

| Option | Description | Selected |
|--------|-------------|----------|
| Single advanceStatus action (Recommended) | One LoadAction.advanceStatus whose target is derived from the current status (the next step in the canonical order). RoleLoadPolicy returns [.advanceStatus]; the next state is a pure function. One action, one button, label adapts ('Mark In-Transit'). | ✓ |
| Explicit per-transition actions | Separate LoadAction.dispatch, .markInTransit, .markDelivered cases — no derived targets. More explicit and each transition is independently testable/gateable, but three more enum cases and policy-table rows. | |

**User's choice:** Single advanceStatus action

---

## Trust Data Model

### Q1: How should a TrustNode carry its verification basis (TRUST-03: KYC date, device-binding, USDOT authority, prior-relationship history)?

| Option | Description | Selected |
|--------|-------------|----------|
| Typed fields (Recommended) | TrustNode carries strongly-typed fields: kycCompletedAt: Date?, deviceBindingStatus, usdotNumber/authorityStatus, priorRelationshipCount. The four facts are a fixed known set, so the iOS UI controls presentation. The trust *signal* stays the opaque verificationState enum regardless — typed basis fields don't let the client compute trust. | ✓ |
| Opaque fact list | TrustNode carries verificationBasis: [VerificationFact] — server-formatted {label, value, emphasis} pairs the client renders verbatim in order. Maximally render-only; a live backend can add facts with no iOS release. But the client can't style individual fact types and the detail sheet is a generic list. | |

**User's choice:** Typed fields

### Q2: How should ChainOfTrust represent the graph and its double-/triple-brokering risk (TRUST-04 edge-tap, TRUST-05 flagged edges + chain verdict)?

| Option | Description | Selected |
|--------|-------------|----------|
| Nodes + edges + integrity (Recommended) | ChainOfTrust { nodes: [TrustNode], edges: [TrustEdge], integrity: ChainIntegrity }. TrustEdge carries handoff/tender detail (TRUST-04) and its own flag state. ChainIntegrity = a verdict enum (clean/caution/compromised) + a human-readable reason + the implicated node/edge IDs. Mirrors exactly what the graph renders. | ✓ |
| Nodes-only + bare verdict | No separate edge objects — each node carries its inbound-handoff detail and its own flag; integrity is a bare enum with no reason text. Simpler model, but the graph UI must synthesize edges and TRUST-04 edge detail gets bolted onto nodes. | |

**User's choice:** Nodes + edges + integrity

### Q3: How should the verification-state enum and its decoding behave?

| Option | Description | Selected |
|--------|-------------|----------|
| Four states, fail-closed (Recommended) | Closed enum {verified, pending, unverified, flagged}. 'flagged' = actively suspicious / known fraud signal, distinct from 'unverified' = simply not-yet-verified. Unknown/unrecognized JSON value decodes to 'unverified' (fail-closed to least-trusted); a *missing* field is a hard decode error (strict contract). | ✓ |
| Four states, strict only | Same four states, but any unknown value is also a decode error — fixtures must always specify a recognized state. Treats verification state like every other strict contract field; no security-specific fallback. | |

**User's choice:** Four states, fail-closed

---

## Fixture Scenarios

### Q1: Should the load fixtures tell a coherent fraud-detection story, or be minimal mechanical coverage?

| Option | Description | Selected |
|--------|-------------|----------|
| Coherent narrative (Recommended) | Named loads exercising the platform thesis: a clean verified chain, a load with a pending counterparty, a double-brokered load with a flagged carrier + 'compromised' chain verdict, an expired tender awaiting retender, a load you cannot tender to (unverified counterparty). Phase 8-10 demos show the product's reason to exist. Mechanical states (empty/error/latency/action-failure) layer on top. | ✓ |
| Minimal mechanical | Fixtures sized just to exercise decode paths and each state once — generic loads, no narrative. Faster to author; but Phase 8-10 demos look like placeholder data and never show double-brokering risk in action. | |

**User's choice:** Coherent narrative

### Q2: Should the 5 per-role load fixtures be one shared world or independent sets?

| Option | Description | Selected |
|--------|-------------|----------|
| Shared consistent world (Recommended) | One underlying set of loads; each role's loads-list-{role}.json is that role's view of the same loads. Load VL-1001 appears in the broker's list as 'you tendered this' and in the carrier's list as 'tendered to you', with the same chain-of-trust graph. Cross-role demos stay coherent; the trust graph is consistent whoever views it. | ✓ |
| Independent per-role sets | Each role's fixture is its own unrelated set of loads. Simpler to author each file in isolation, but switching roles in a demo shows disconnected data and the same load can't be followed across roles. | |

**User's choice:** Shared consistent world

### Q3: How many of the product's fraud archetypes should the flagged fixtures cover?

| Option | Description | Selected |
|--------|-------------|----------|
| All three archetypes (Recommended) | A distinct flagged load for each fraud pattern PROJECT.md names: double-/triple-brokered (flagged carrier + 'compromised' chain), chameleon carrier (suspect identity/authority history), and factoring fraud (flagged factoring party on a double-brokered shipment). Same render mechanism (flagged node/edge + integrity.reason text) for all three — no model change, just more JSON. The milestone demos the full fraud thesis. | ✓ |
| One canonical double-brokering load | Exactly one flagged/'compromised' load — double-brokering — since that is what TRUST-05 explicitly names. Chameleon-carrier and factoring-fraud fixtures are deferred. Tighter Phase 7 fixture-authoring scope. | |

**User's choice:** All three archetypes

---

## Claude's Discretion

The user did not invoke "you decide" at any decision point — every option was an explicit choice. Items left to the planner/researcher are derivative implementation details, listed in CONTEXT.md `<decisions>` under "Claude's Discretion":

- Exact `ChainIntegrity` verdict enum cases
- Exact named-load IDs and the precise count of fixture loads
- Exact HTTP status codes for the failure fixtures (409/422/timeout are indicative)
- The latency / forced-failure injection mechanism on `MockURLProtocol` (additive only)
- Whether `priorRelationshipCount` is a bare `Int` or a small `[PriorRelationship]` typed list
- The snake_case ↔ camelCase / ISO-8601 decoding strategy (follow the v1.0 house pattern)

## Deferred Ideas

None. The discussion stayed inside Phase 7's boundary — every selected gray area resolved into a contract decision that this phase delivers. Items deferred from v1.1 entirely (real-time updates, APNs push, real backend, background `URLSession` rework, crash/analytics vendor) are already recorded in PROJECT.md and ROADMAP.md and were not re-litigated.

### Todos reviewed but not folded

- **`device-ci-biometric-infra.md`** — a v1.0 physical-device CI infrastructure todo. Matched on the generic keywords `status` and `phase` (score 0.4) and is unrelated to a contract / data-model phase. Not folded.
