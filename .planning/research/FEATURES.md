# Feature Research — v1.1 "Load Flows"

**Domain:** Identity-verified freight load management (iOS, five roles: Shipper, Broker, Carrier, Dispatch, Factoring)
**Milestone:** v1.1 "Load Flows" — the load slice of the original M2 "Core Flows"
**Researched:** 2026-05-19
**Confidence:** HIGH for the freight-domain model (EDI 204/990, factoring, FMCSA 2025 changes cross-verified); HIGH for feature scoping (1:1 against PROJECT.md Active list + v1.0 codebase contracts); MEDIUM for the trust-graph node/edge semantics (a Validation Ledger-specific design synthesised from FMCSA fraud patterns + v1.0 identity primitives — no published competitor renders it exactly this way).

---

## Scope of This Research

This file covers **only the five new v1.1 load-domain features**. v1.0 features (OTP auth, role tab shells, KYC capture, device binding) are shipped and excluded — they appear here only as **dependencies** the load domain consumes.

**v1.1 hard constraints that shape every feature below:**
- **iOS-only against `MockURLProtocol` fixtures.** No backend, no real-time (WS/SSE), no APNs push. Every "live" behaviour is a fixture response, not a server event.
- New load endpoints extend the v1.0 contract-first pattern: a typed `APIEndpoint` struct per call, fixtures keyed off `path` + `method` (`Core/Networking/Mock/MockURLProtocol.swift`, fixtures in `validationLedgerTests/Networking/Fixtures`).
- `Features/Loads/` exists as an empty `.gitkeep` directory — this milestone fills it.
- All five role tab shells (`Roles/{Broker,Carrier,Dispatch,Factoring,Shipper}TabBarController.swift`) exist as placeholders — v1.1 wires a real Loads tab into each.
- UIKit-first; the trust graph, load list, and load detail are non-trivial interactive surfaces → UIKit (SwiftUI only acceptable for static sub-rows if at all).

---

## The Load State Model (canonical, for REQUIREMENTS.md)

Freight loads move through a well-defined lifecycle. The industry-standard sequence — cross-verified against TMS shipment-status documentation and the EDI 204/990 tender handshake — is the basis for v1.1's model. Because v1.1 is mock-only and excludes the dock/BOL/POD milestone (M3) and real backend, the **v1.1 state model is deliberately truncated at `Delivered`** and treats post-delivery funding states as display-only.

**Canonical Validation Ledger load state machine:**

```
                  ┌─────────────────────────────────────────────┐
   Draft ──post──▶ Posted ──tender──▶ Tendered ──accept──▶ Accepted (Booked)
                      │                  │ │
                      │                  │ └─reject──▶ Rejected ──┐
                      │                  └─expire──▶ Expired ──────┤
                      │                                            │
                      │◀───────── retender / repost ───────────────┘
                      ▼
   Accepted ──dispatch──▶ Dispatched ──pickup──▶ In-Transit ──deliver──▶ Delivered
                                                                            │
                                              (M3+: ──▶ POD-Captured)        │
                                              (post-v1.1: ──▶ Invoiced ──▶ Funded)
   Any non-terminal state ──cancel──▶ Cancelled
```

| State | Meaning | Set by | Terminal? | v1.1 scope |
|-------|---------|--------|-----------|------------|
| `draft` | Load created, not yet offered | Shipper / Broker | No | Display only — fixtures may include; no create-load UI in v1.1 |
| `posted` | Load is on the board / available, not assigned | Shipper / Broker | No | **In scope** — list source for Carrier/Dispatch |
| `tendered` | Load offered to a specific carrier; awaiting accept/reject | Broker / Shipper | No | **In scope** — core v1.1 interaction |
| `accepted` (a.k.a. `booked`) | Carrier accepted the tender; load is committed | Carrier (or Dispatch on carrier's behalf) | No | **In scope** — core v1.1 interaction |
| `rejected` | Carrier declined the tender | Carrier / Dispatch | No (can retender) | **In scope** — terminal-for-that-tender; load returns to `posted` |
| `expired` | Tender's must-respond-by deadline lapsed with no response | System (fixture-simulated) | No (can retender) | **In scope** — see Tender section |
| `dispatched` | Pickup/delivery details confirmed with driver; en route to pickup | Carrier / Dispatch | No | **In scope** (status display + action) |
| `in_transit` | Freight loaded; truck moving to delivery | Carrier / Dispatch | No | **In scope** (status display + action) |
| `delivered` | Freight unloaded at consignee | Carrier / Dispatch | Yes (for v1.1) | **In scope** — v1.1 timeline ends here |
| `pod_captured` | Signed proof-of-delivery captured | Carrier | — | **OUT** — M3 (eBOL/POD milestone) |
| `invoiced` | Carrier submitted invoice + BOL to factoring | Carrier / Factoring | — | **Display-only** — fixture may show a `funded`-track load so Factoring role has content; no invoice-submission UI |
| `funded` | Factoring advanced payment against the invoice | Factoring | Yes | **Display-only** — same as above |
| `cancelled` | Load voided before delivery | Shipper / Broker | Yes | **In scope** — fixtures include; no cancel UI required (display-only acceptable) |

**Roadmap note:** v1.1 must implement the state *enum* and *transitions* fully (the state machine is cheap and the fixtures need it), but only `posted → tendered → accepted/rejected/expired` and `accepted → dispatched → in_transit → delivered` require **interactive transitions** (action buttons). `invoiced`/`funded`/`pod_captured` are render-only in v1.1 — keep them in the enum so Factoring's list isn't empty and so the model doesn't need a breaking change in M3.

---

## Per-Role Action Matrix (canonical, for REQUIREMENTS.md)

The five roles do **not** have symmetric power over a load. The freight industry's structural reality: a **broker** represents the shipper and is paid by the shipper; a **dispatcher** represents the carrier and is paid by the carrier; **factoring** is a financier sitting downstream of delivery. This asymmetry is the entire point of the chain-of-trust and must be enforced in the UI.

| Action | Shipper | Broker | Carrier | Dispatch | Factoring |
|--------|---------|--------|---------|----------|-----------|
| **View load** (list + detail) | ✅ own loads | ✅ loads it brokers | ✅ loads tendered/assigned to it | ✅ loads for its carrier(s) | ✅ loads tied to invoices it factors |
| **Post / offer a load** | ✅ (origin of freight) | ✅ (on shipper's behalf) | ❌ | ❌ | ❌ |
| **Tender** (offer to a specific carrier) | ✅ (direct-to-carrier shippers) | ✅ (primary tendering party) | ❌ | ❌ | ❌ |
| **Accept a tender** | ❌ | ❌ | ✅ (primary) | ✅ (acts *for* the carrier) | ❌ |
| **Reject a tender** | ❌ | ❌ | ✅ (primary) | ✅ (acts *for* the carrier) | ❌ |
| **Re-tender after reject/expire** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Advance status** (dispatched → in_transit → delivered) | ❌ | ❌ | ✅ (primary) | ✅ (on carrier's behalf) | ❌ |
| **Cancel a load** | ✅ (pre-delivery) | ✅ (pre-delivery) | ❌ | ❌ | ❌ |
| **View chain-of-trust graph** | ✅ | ✅ | ✅ | ✅ | ✅ (all 5 — it's the shared trust surface) |
| **Fund / mark invoiced** | ❌ | ❌ | ❌ (submits invoice — M3) | ❌ | ✅ (display-only in v1.1) |

**Per-role action-set summary (what each role's Loads tab actually offers in v1.1):**

- **Shipper** — owns the freight. Sees its own loads across all states. Can post and tender (direct-to-carrier case). Read-only on status progression and the trust graph. *v1.1 action set: post (optional), tender, cancel (optional).*
- **Broker** — the central tendering actor; represents the shipper. Sees loads it brokers. The classic Tender screen lives here. Can tender, retender, cancel. **D4 "refuse-to-tender-to-unverified-counterparty" (a v1.0-thesis differentiator) is primarily a Broker surface** — the Tender action is hard-disabled when the target carrier's verification state ≠ verified. *v1.1 action set: tender, retender, cancel.*
- **Carrier** — receives tenders, accepts/rejects, then advances status. The accept/reject screen and the one-tap status updates live here. *v1.1 action set: accept, reject, advance-status.*
- **Dispatch** — acts *for* a carrier (a dispatcher works for the motor carrier, not the shipper — a load is never tendered *to* the dispatcher). In v1.1, Dispatch sees the same tender/accept/status surfaces as Carrier but scoped to all carriers it represents. *v1.1 action set: accept, reject, advance-status — identical to Carrier, multi-carrier scope.*
- **Factoring** — a financier downstream of delivery. Does not touch tender/accept/status at all. Sees loads tied to invoices it factors, and the chain-of-trust graph (factoring's whole job is verifying the load was real and the chain was clean before advancing money — this is why factoring is a node on the graph). *v1.1 action set: view only (funding is display-only).*

**Critical roadmap implication:** Carrier and Dispatch share an action set (accept/reject/advance) — build one set of action components, parameterise by carrier scope. Shipper and Broker share a tendering action set. Factoring is read-only. This collapses "per-role action sets across all 5 roles" into **3 distinct action surfaces**, not 5 — a meaningful complexity reduction for the roadmap.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any freight load app must have for the load domain to feel complete. Missing them = the v1.1 milestone reads as a non-functional placeholder.

| # | Feature | Why Expected | Complexity | Notes |
|---|---------|--------------|------------|-------|
| L1 | **Role-filtered load list** | Every TMS app (Samsara, Uber Freight, TruckLogics, Truckstop ITS) scopes the load list to the signed-in party. A carrier seeing a broker's full book, or vice versa, is a data-leak bug, not a feature gap. | MEDIUM | One `LoadListViewController` + `LoadListViewModel`, instantiated per role by the existing `RoleCoordinator`. Backend (here: the mock) filters by role token — **client must not re-filter** (matches v1.0 "backend filters, client renders" rule). Each role gets a fixture file: `loads-shipper.json`, `loads-broker.json`, etc. Depends on v1.0 session/role (SHELL-01). |
| L2 | **Load row with the standard freight field set** | Load boards and TMS lists have a near-universal row shape; users scan for these fields. | LOW | Row fields: load reference #, origin city/state → destination city/state, pickup date, delivery date, equipment type, weight, rate, commodity (short), **load state badge**, **counterparty verification badge** (the VL-specific addition). Keep the row dense but legible — drivers scan one-handed. |
| L3 | **Load detail screen** | Tapping a load row must open a full detail view; this is universal. The detail screen is also the host for the trust graph and the action buttons. | MEDIUM | `LoadDetailViewController` + `LoadDetailViewModel`. Sections: load summary, stops (pickup/delivery with addresses, dates, appointment windows, contact), commodity/equipment/weight/dimensions, rate + accessorials, **status timeline**, **chain-of-trust graph**, **role-specific action bar**. Depends on L1. |
| L4 | **Load status timeline** | The "Posted → Tendered → Accepted → Dispatched → In-Transit → Delivered" progression rendered as a vertical timeline is the standard Uber Freight / Convoy pattern. Users expect to see *where the load is*. | LOW-MEDIUM | Distinct from the trust graph — the timeline is *load state over time*; the trust graph is *who's involved and are they real*. Render completed states filled, current state highlighted, future states dimmed. Drives off the `load.state` field + a `stateHistory` array in the fixture. |
| L5 | **Tender → Accept / Reject interaction** | The single most universal TMS flow. Broker offers, carrier accepts or rejects. Mirrors the EDI 204 (tender) / EDI 990 (response) handshake every freight system implements. | MEDIUM | See "Tender / Accept / Reject Semantics" below. Tender from Shipper/Broker; accept/reject from Carrier/Dispatch. Each is a typed endpoint (`POST /loads/{id}/tender`, `/accept`, `/reject`) with a fixture response. v1.0's idempotency-key interceptor already covers double-submit. |
| L6 | **One-tap status advancement** (dispatched / in_transit / delivered) | Convoy-popularised, now universal. Carriers will not adopt an app that needs more than one tap per checkpoint. | LOW | Carrier/Dispatch only. `POST /loads/{id}/status` with the next state. Action button shows only the *next legal* transition (state machine drives button visibility). No geofencing in v1.1 (that's M3+ background location). |
| L7 | **Empty / loading / error states for the list and detail** | A list that shows nothing on a network failure, or a spinner forever, reads as broken. App Store quality bar. | LOW | Standard UIKit pattern. Particularly relevant because v1.1 is mock-driven — fixtures should include an empty-list fixture and an error fixture so these states are actually exercised. |
| L8 | **Pull-to-refresh on the load list** | Because v1.1 has no real-time/push, refresh is the *only* way state changes propagate. Without it the list is frozen. | LOW | `UIRefreshControl`. This is the v1.1 substitute for the deferred WS/SSE — call it out in REQUIREMENTS as the explicit no-real-time mitigation. |

### Differentiators (Competitive Advantage)

Features that exist because Validation Ledger is an *identity-first* freight platform, not a generic TMS. These are anchored to PROJECT.md Core Value: "identity that cannot be spoofed and a chain-of-trust that cannot be faked." For v1.1 these are the reason the milestone exists.

| # | Feature | Value Proposition | Complexity | Notes |
|---|---------|-------------------|------------|-------|
| L9 | **Interactive chain-of-trust graph on load detail** | The user-facing manifestation of the entire product thesis. No competitor (Highway, Trustd, Verified Carrier) renders the *full counterparty chain for a specific load* as a tappable node-graph. This is the marquee v1.1 screen. | **HIGH** | See "Chain-of-Trust Graph: Node & Edge Semantics" below. The single highest-design-investment, highest-risk feature in v1.1 — flag for deeper phase-level research. UIKit custom view (likely `UICollectionView` with a custom layout, or a hand-drawn `CALayer`/`UIBezierPath` graph). |
| L10 | **Per-party verification state badges, everywhere a party appears** | The verification state (verified / unverified / flagged / pending) of each counterparty must be visible on the load row, in load detail, and on every graph node. A user should never see a party name without its trust state attached. | MEDIUM | A reusable `VerificationBadge` component in `UI/DesignSystem`. Consumes a `verificationState` enum on every party object in the fixtures. Consistency is the differentiator — banks show a verified checkmark everywhere; VL shows trust state everywhere. |
| L11 | **Tap-a-node-for-verification-basis detail** | Tapping any party in the trust graph opens *why* that party is trusted: KYC completion date, identity-document type verified, device-binding status, USDOT authority status, prior-relationship history. This is "the chain of trust cannot be faked" made inspectable. | MEDIUM-HIGH | A `PartyVerificationDetailViewController` presented from a graph-node tap. Content comes from a `GET /parties/{id}/verification` fixture. This is where v1.1 surfaces the v1.0 identity primitives (KYC status, device binding) *about other people*. |
| L12 | **Refuse-to-tender / reject-action-disabled when a counterparty is unverified** | Highway and Trustd *warn* about unverified carriers; none *block* the action client-side with an inline reason. This moves VL from "carrier-vetting tool" to "fraud-prevention rail." | MEDIUM | The Tender button (Broker/Shipper) is hard-disabled — with visible reason copy — when the target carrier's `verificationState != verified`. Reason text comes from the fixture (`tenderEligibility` object). This is the load-domain expression of the v1.0 thesis; it depends on L10's verification-state data being present on every party. |
| L13 | **Trust graph reflects double-/triple-brokering risk visually** | Double brokering is the #1 fraud the platform attacks. If a load's chain has *more broker hops than authorised*, or an unverified intermediary, the graph should make that legible at a glance (e.g., a flagged edge, a warning node). | MEDIUM | Mostly a rendering concern: the graph data model already carries the ordered chain; v1.1 just needs to render an extra/unauthorised hop or a `flagged` party distinctly. The *detection* logic is backend's job (out of scope) — v1.1 renders the fixture's `chainIntegrity` verdict. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that will be requested for the load domain but are wrong for v1.1 — either they violate the milestone's mock-only scope, or they violate the platform's trust posture.

| # | Anti-Feature | Why Requested | Why Problematic | Alternative |
|---|--------------|---------------|-----------------|-------------|
| AL1 | **Real-time load updates (WebSocket/SSE) in v1.1** | "Dispatchers check status obsessively; polling feels broken." True — but… | v1.1 is explicitly mock-only with no backend. Real-time needs a running server. Building a WS/SSE abstraction against a mock is throwaway work. | Pull-to-refresh (L8) is the v1.1 substitute. WS/SSE is deferred to a post-v1.1 milestone per PROJECT.md. |
| AL2 | **APNs push for tender notifications** | "Carrier should get a lock-screen alert when tendered." | No backend to send pushes; APNs is deferred per PROJECT.md. A mock cannot originate a push. | The carrier sees the tender on next list refresh. Push lands in the post-v1.1 milestone with the real backend. |
| AL3 | **Client-side load filtering / re-scoping the list** | "Just filter the array by role on the client — simpler than per-role fixtures." | Breaks the v1.0 "backend is the authority, client renders" rule. A client that *can* see other roles' loads (even if it filters them) is a data-exposure bug and a fraud vector. | Per-role fixture files; the mock returns only that role's loads, exactly as the real backend will. |
| AL4 | **Client-side trust-graph computation / chain-integrity verdict** | "The client has the chain data — just compute whether it's clean." | Client-side trust computation is bypassable by any attacker and contradicts "the chain of trust cannot be faked." The verdict must be authoritative. | The fixture (later: backend) supplies the computed `chainIntegrity` verdict and per-party `verificationState`; the client *renders* them, never derives them. |
| AL5 | **Create-load / full load-entry form** | "A shipper needs to create loads." | True for the real product, but a full load-creation form (multi-stop, commodity, accessorials, rate) is a large surface that v1.1's mock-only scope and the "list/detail/trust-graph/tender" framing do not include. | v1.1 fixtures pre-populate loads in every state. Load creation is a later milestone. `post`/`cancel` actions, if included, act on pre-existing fixture loads. |
| AL6 | **eBOL rendering / rotating QR / dock scanner on the load detail** | "The load detail is the natural home for the BOL and the dock QR." | eBOL, the rotating QR, and the scanner are the explicit M3 milestone. Pulling them into v1.1 blows the milestone scope and pulls in the deferred backend-signing dependency. | Load detail in v1.1 has a *placeholder* or omits the BOL section entirely. M3 adds it. Keep the detail layout extensible so M3 slots in cleanly. |
| AL7 | **Editable load fields on the detail screen** | "Let the broker fix a typo'd weight inline." | Mutable load data mid-lifecycle is both a scope expansion and a fraud surface (rate/commodity tampering). v1.1 detail is read-only except for the role-action buttons. | Load detail is read-only. Corrections are a later-milestone concern with backend validation + audit trail. |
| AL8 | **Map / live truck-location tracking on the load** | "Show the truck on a map en route." | Live location needs background location (M3) + a real backend feed. A static map adds little and a live one is out of scope. | Status timeline (L4) communicates progress without a map. Map/tracking is post-v1.1. |
| AL9 | **In-app messaging between load counterparties** | "Broker and carrier need to talk about the load." | Messaging is an M4/v2 concern and (per v1.0 research A4) must never be a third-party SDK. Not a load-domain feature. | Out of v1.1 entirely. |

---

## Chain-of-Trust Graph: Node & Edge Semantics (canonical, for REQUIREMENTS.md)

This is the v1.1 marquee feature (L9/L11) and the most design-novel. Here is the concrete model the requirements and roadmap should adopt.

### What the graph *is*

A directed, ordered visual representation of **every party in a specific load's transaction chain**, in handoff order, each annotated with its real-time verification state. It answers, for the user looking at this one load: *"Who is in this deal, and is every one of them demonstrably real?"*

### Nodes — one per party in the chain

Canonical node order (a node is omitted if that role isn't in this particular load's chain — e.g., a direct shipper→carrier load has no broker node):

```
[ Shipper ] ──▶ [ Broker ] ──▶ [ Carrier ] ──▶ [ Dispatch ] ──▶ [ Factoring ]
```

Each **node** carries:

| Node field | What it is | Source |
|------------|------------|--------|
| `partyId` | Stable party identifier | fixture |
| `role` | shipper / broker / carrier / dispatch / factoring | fixture |
| `displayName` | Company / person name | fixture |
| `verificationState` | `verified` \| `unverified` \| `pending` \| `flagged` | fixture (authoritative) |
| `usdotNumber` | USDOT # (the post-Oct-2025 sole FMCSA identifier; MC numbers are eliminated) | fixture |
| `authorityType` | carrier / broker / forwarder authority, suffixed on the USDOT # | fixture |
| `kycCompletedAt` | When this party's identity was verified | fixture |
| `deviceBound` | Whether the party has an active device-bound identity (the v1.0 Secure Enclave primitive) | fixture |
| `isCurrentUser` | Highlights the signed-in user's own node in the chain | derived client-side (the one allowed derivation) |

**The four verification states (the heart of "verified vs unverified vs flagged"):**

| State | Meaning | Visual | What it means for actions |
|-------|---------|--------|---------------------------|
| `verified` | Identity proofed (KYC complete), USDOT authority active, device-bound. The party is demonstrably real. | Green node, check glyph | Actions toward this party are enabled |
| `pending` | KYC submitted but not yet cleared, or authority filing in progress | Amber node, clock glyph | Actions may be soft-warned; not necessarily blocked |
| `unverified` | No completed KYC / no device binding / authority not confirmed. Identity is *not* established. | Grey node, hollow glyph | Tender/accept toward this party is **hard-disabled** (L12) |
| `flagged` | Active fraud signal — authority revoked, identity mismatch, prior double-brokering, impossible-travel hit, or an unauthorised extra broker hop | Red node, warning glyph | Actions hard-disabled + prominent inline warning |

### Edges — one per handoff between adjacent parties

Each **edge** represents a *counterparty relationship / handoff* (shipper→broker, broker→carrier, etc.) and carries:

| Edge field | What it is |
|------------|------------|
| `fromPartyId` / `toPartyId` | The two parties this handoff connects |
| `relationshipState` | `established` (a verified prior relationship or a clean handoff) \| `new` (first-time counterparties — not wrong, but noted) \| `flagged` (the handoff itself is suspect — e.g., an unauthorised re-broker) |
| `tenderRef` | If the handoff was a tender, the tender record id (links the edge to L5 data) |

An edge is the visual home for **double-/triple-brokering risk (L13)**: a clean broker→carrier edge renders as a solid connector; an unauthorised additional broker hop, or an edge between two parties with no legitimate relationship, renders `flagged` (red, dashed) — making the fraud legible at a glance.

### Chain-level verdict

The graph as a whole carries one `chainIntegrity` field — `clean` \| `caution` \| `compromised` — supplied by the fixture (later: backend; **never computed client-side**, per AL4). The graph header renders this verdict.

### Interaction

- Tapping a **node** → `PartyVerificationDetailViewController` (L11): the verification basis for that party.
- Tapping an **edge** → optional: the handoff/tender detail. v1.1 may scope edge-tap as a "nice to have."
- The graph is **read-only** — it visualises trust, it never edits it.

### Roadmap risk callout

The trust graph is the only **HIGH-complexity** feature in v1.1 and has no off-the-shelf UIKit component. It needs its own phase (or a dedicated design spike): node layout, edge drawing, the four-state visual language, accessibility (VoiceOver must read the chain as an ordered list), and iPad-native layout (the chain is wider — dispatch/factoring use iPad). **Flag this phase for deeper research during roadmap planning.**

---

## Feature Dependencies

```
[v1.0: OTP auth + session + role]  ── required by ──▶  [L1 Role-filtered load list]
[v1.0: RoleCoordinator / 5 tab shells] ── required by ──▶ [L1 Role-filtered load list]
[v1.0: APIEndpoint + MockURLProtocol contract] ── required by ──▶ [all new load endpoints]
[v1.0: device-bound identity (Secure Enclave)] ── surfaced-as-data-by ──▶ [L11 verification basis]
[v1.0: KYC status model] ── surfaced-as-data-by ──▶ [L10, L11 verification badges/basis]

[L1 Load list]
    └── required by ──▶ [L3 Load detail screen]
                            └── required by ──▶ [L4 Status timeline]
                            └── required by ──▶ [L5 Tender/Accept/Reject]
                            └── required by ──▶ [L6 One-tap status advance]
                            └── required by ──▶ [L9 Chain-of-trust graph]

[L2 Load row field set] ── needs ──▶ [L10 verification badge component]  (the row shows a trust badge)

[L9 Chain-of-trust graph]
    └── required by ──▶ [L11 Tap-node-for-verification-basis]
    └── required by ──▶ [L13 Double-brokering risk visualisation]
    └── shares-data-with ──▶ [L12 Refuse-to-tender]   (both consume per-party verificationState)

[L10 Verification badges] ── required by ──▶ [L12 Refuse-to-tender]   (the disable rule reads the same state)

[L8 Pull-to-refresh] ── substitutes-for ──▶ [deferred WS/SSE real-time]

[AL5 Create-load] ── conflicts-with ──▶ [v1.1 mock-only scope]   (fixtures pre-populate instead)
[AL6 eBOL/QR/scanner] ── conflicts-with ──▶ [v1.1 scope]   (explicit M3 milestone)
```

### Dependency Notes

- **L1 (load list) is the v1.1 critical-path root.** Load detail, the timeline, the trust graph, and every action all hang off being able to fetch and render a load. The list + the load data model + the mock endpoints should be the first phase.
- **L9 (trust graph) depends on L3 (load detail) existing as a host**, and on the load fixture carrying a full `chain` object. The graph cannot be a standalone screen — it lives inside detail.
- **L10 (verification badges) and L12 (refuse-to-tender) consume the same `verificationState` field.** Build the data model once; both features read it. If the load/party fixture schema doesn't carry `verificationState` on every party from day one, L12 and the whole graph are blocked — so the fixture schema is itself a gating dependency, design it up front.
- **The new load endpoints depend on the v1.0 contract-first pattern.** Every load call is a typed `APIEndpoint` struct + a `path`/`method`-keyed fixture. This is a *known, proven* pattern from v1.0 (7 endpoints shipped this way) — LOW risk, but it is a hard prerequisite and should be scoped as its own early slice (the "new load-domain mock endpoints + fixtures" Active item).
- **L5 (tender/accept/reject) depends on the load state machine being implemented.** Accept/reject is only legal from `tendered`; the buttons' visibility is state-driven. Implement the state enum + transition rules before the action UI.
- **No v1.1 feature depends on a backend, WS/SSE, or APNs.** This is the milestone's defining property — every "live" behaviour is a fixture, every state change propagates via pull-to-refresh.

---

## Tender / Accept / Reject Semantics (for REQUIREMENTS.md)

Modelled on the EDI 204 (Motor Carrier Load Tender) / EDI 990 (Response to a Load Tender) handshake — the freight industry's universal tender protocol — adapted to a mock-only iOS client.

**A tender contains** (the offer a Broker/Shipper sends, surfaced as a fixture object on the load):
- Target carrier (the specific party being offered the load — a tender is always to *one* carrier)
- The full load details required to decide: stops, dates/appointment windows, equipment type, weight, commodity
- The offered rate (carrier rate)
- A **must-respond-by deadline** (`respondByAt`) — the EDI 204 G62 "must-respond-by" segment
- Tender reference id

**Accept semantics:**
- Only the targeted Carrier (or its Dispatch) can accept; only when the load is in `tendered`.
- Accept transitions `tendered → accepted`. The load is now committed to that carrier.
- `POST /loads/{id}/accept` — fixture returns the updated load.

**Reject semantics:**
- Only the targeted Carrier (or its Dispatch); only from `tendered`.
- Reject transitions `tendered → rejected`; the load returns to `posted` and can be re-tendered (by Broker/Shipper) to a different carrier.
- An optional reason code is good practice (mirrors the EDI 990 rejection code).
- `POST /loads/{id}/reject`.

**Expiration semantics:**
- A tender **can and does expire.** If `respondByAt` lapses with no accept/reject, the tender is `expired`; like a reject, the load returns to `posted` and can be re-tendered.
- v1.1 is mock-only — there is no server clock. **Expiration is fixture-simulated:** ship a fixture load whose tender's `respondByAt` is already in the past so the `expired` state and its UI are exercised. The client may also render a live countdown from `respondByAt` for an active tender (the deadline is real data even if enforcement isn't).
- Roadmap note: real server-side expiry enforcement is a post-v1.1/backend concern. v1.1 only needs to *render* the expired state and the countdown.

**Refuse-to-tender (L12) interacts with this:** the Broker's Tender action is disabled before a tender can even be created, when the chosen carrier's `verificationState != verified`.

---

## MVP Definition

### Launch With (v1.1 — the milestone itself)

The five PROJECT.md Active items, decomposed:

- [ ] **New load-domain mock endpoints + fixtures** — `GET /loads` (role-scoped), `GET /loads/{id}`, `GET /parties/{id}/verification`, `POST /loads/{id}/{tender|accept|reject|status}`; per-role fixture files + per-state fixture loads + an empty-list and an error fixture. *Essential: everything else reads this.*
- [ ] **L1 Role-filtered load list** — one list screen, instantiated per role, mock-filtered. *Essential: the critical-path root.*
- [ ] **L2 Standard load row** + **L10 verification badge component**. *Essential: the list is unreadable without a row design and trust badges.*
- [ ] **L3 Load detail screen** + **L4 status timeline** + **L7 empty/loading/error** + **L8 pull-to-refresh**. *Essential: the host for the graph and actions; refresh is the only state-propagation path.*
- [ ] **L5 Tender / Accept / Reject** + the load state machine + **L6 one-tap status advance**. *Essential: "per-role tender/accept/reject action sets" is a named milestone deliverable.*
- [ ] **L9 Interactive chain-of-trust graph** + **L11 tap-node-for-verification-basis** + **L13 double-brokering risk rendering**. *Essential: the marquee differentiator; the milestone is named after the load domain but the trust graph is its reason to exist.*
- [ ] **L12 Refuse-to-tender-to-unverified** with inline reason. *Essential: the load-domain expression of the platform thesis; cheap once L10's data exists.*

### Add After Validation (v1.x — post-v1.1, needs the real backend)

- [ ] Real-time load updates (WebSocket/SSE) — replaces L8 pull-to-refresh as the propagation mechanism.
- [ ] APNs push for tender / status-change notifications with deep links.
- [ ] Edge-tap detail on the trust graph (handoff/tender drill-down) — if cut from v1.1 for scope.
- [ ] Full load-creation form (multi-stop, commodity, accessorials, rate entry) for Shipper/Broker.

### Future Consideration (v2+ / later milestones)

- [ ] eBOL rendering + rotating QR + dock scanner on load detail — explicit M3 milestone.
- [ ] POD signature/photo capture + the `pod_captured` state transition — M3.
- [ ] Factoring invoice-submission write-path + the `invoiced`/`funded` transitions — post-v1.1.
- [ ] Map / live truck-location tracking — needs M3 background location + a backend feed.
- [ ] AI assistant grounded in the chain-of-trust ("this carrier's verification lapsed — do not tender") — M4.

---

## Feature Prioritization Matrix

| # | Feature | User Value | Implementation Cost | Priority | Notes |
|---|---------|------------|---------------------|----------|-------|
| — | New load mock endpoints + fixtures | HIGH | MEDIUM | P1 | Gates everything; known v1.0 pattern → low risk, but must be first |
| L1 | Role-filtered load list | HIGH | MEDIUM | P1 | Critical-path root |
| L2 | Standard load row | HIGH | LOW | P1 | The list's primary surface |
| L3 | Load detail screen | HIGH | MEDIUM | P1 | Host for graph + actions |
| L4 | Status timeline | MEDIUM | LOW-MEDIUM | P1 | Standard pattern; cheap |
| L5 | Tender / Accept / Reject | HIGH | MEDIUM | P1 | Named milestone deliverable |
| L6 | One-tap status advance | MEDIUM | LOW | P1 | Carrier/Dispatch; state-machine-driven |
| L7 | Empty / loading / error states | MEDIUM | LOW | P1 | App Store quality bar |
| L8 | Pull-to-refresh | HIGH | LOW | P1 | The *only* state-propagation path in a mock-only milestone |
| L9 | **Chain-of-trust graph** | HIGH | **HIGH** | P1 | The marquee differentiator; flag for deeper phase research |
| L10 | Verification badge component | HIGH | MEDIUM | P1 | Reused by row, detail, graph, L12 |
| L11 | Tap-node-for-verification-basis | HIGH | MEDIUM-HIGH | P1 | "Trust cannot be faked" made inspectable |
| L12 | Refuse-to-tender-to-unverified | HIGH | MEDIUM | P1 | Platform thesis in the load domain; cheap given L10 |
| L13 | Double-brokering risk rendering | HIGH | MEDIUM | P1 | Mostly rendering; verdict comes from fixture |

**Priority key:** P1 = must have for the v1.1 milestone · P2 = post-v1.1 · P3 = later milestone.

*All v1.1 features are P1 — the milestone was already scoped down to a tight vertical slice, so there is no P2/P3 within v1.1. The relevant ordering signal is the dependency chain (endpoints → list → detail → graph/actions), not priority tiers.*

---

## Competitor Feature Analysis

| Feature | Samsara / Uber Freight / McLeod (legacy TMS) | Highway / Verified Carrier / Trustd (identity-first) | Validation Ledger v1.1 |
|---------|----------------------------------------------|------------------------------------------------------|------------------------|
| Role-filtered load list | Yes — but split across separate apps per role | Partial — carrier-facing only | Yes (L1) — all 5 roles, one binary, mock-scoped |
| Load detail + status timeline | Yes — universal | Limited (identity-focused, not load-ops) | Yes (L3, L4) |
| Tender / accept / reject | Yes — EDI 204/990 backed | Mostly N/A (not load-execution tools) | Yes (L5) — EDI-204/990-modelled, mock-only |
| Counterparty verification state on the load | No — identity is a signup step, not load-attached | Yes — but as a separate vetting screen, not per-load | Yes (L10) — trust state attached to every party, everywhere |
| **Chain-of-trust graph per load** | No | Partial — Highway has a carrier-relationship view; none render the full per-load chain as a tappable node-graph | **Yes (L9)** — first-class, per-load, interactive |
| Tap-for-verification-basis | No | Partial — credential lists exist | Yes (L11) — KYC date, device binding, USDOT authority, relationship history |
| Refuse-to-tender-to-unverified | No | Advisory warning only (Highway, Trustd) | **Yes (L12)** — hard client-side block + inline reason |
| Double-brokering visualised on the load | No | Detected in back-office dashboards, not on the load | Yes (L13) — flagged node/edge on the graph |

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| Load state model | HIGH | EDI 204/990 handshake and TMS shipment-status sequences are well-documented and consistent across sources; the v1.1 truncation at `Delivered` is a deliberate scope decision, not a knowledge gap. |
| Per-role action matrix | HIGH | The broker-represents-shipper / dispatcher-represents-carrier / factoring-is-downstream structure is the freight industry's settled reality, cross-verified across multiple 2025–2026 sources. |
| Load list / detail field set | HIGH | The origin/destination/commodity/weight/rate/dates field set is near-universal across load boards and TMS products. |
| Tender semantics + expiration | HIGH | Directly modelled on EDI 204 G62 "must-respond-by" and EDI 990 accept/reject — the documented industry protocol. |
| Trust-graph node/edge semantics | MEDIUM | The freight-fraud problem (double brokering, chameleon carriers, USDOT-only identity post-Oct-2025) is HIGH-confidence; the *specific* node/edge data model and four-state visual language is a Validation Ledger design synthesis — defensible and grounded, but no published competitor renders it exactly this way, so it warrants a design/security review during the roadmap. |
| v1.1 scope boundaries | HIGH | Mapped 1:1 against PROJECT.md's Active list, Deferred-from-M2 list, and the v1.0 codebase contracts (`APIEndpoint`, `MockURLProtocol`, `Features/Loads/` stub, role tab shells). |

**Gaps / open items for phase-specific follow-up:**

- **The chain-of-trust graph (L9) needs a dedicated design + research spike** during roadmap planning: UIKit rendering approach (custom `CALayer`/`UIBezierPath` vs. `UICollectionView` custom layout), the four-state visual language, VoiceOver semantics (ordered-list reading of the chain), and iPad-native wide layout. It is the only HIGH-complexity feature and the milestone's headline — it should be its own phase.
- **The load/party fixture schema is itself a gating design artifact.** Every party object must carry `verificationState`, `usdotNumber`, `authorityType`, `kycCompletedAt`, `deviceBound` from day one; every load must carry an ordered `chain`, a `chainIntegrity` verdict, a `stateHistory`, and tender data with `respondByAt`. Get this schema right before building the list — it is consumed by L1, L9, L10, L11, L12, L13.
- **Edge-tap interaction (L9)** is the most plausible scope-trim candidate if the trust-graph phase runs long — node-tap (L11) is essential, edge-tap is a "nice to have."
- **`post`/`cancel` actions for Shipper/Broker** are listed in the action matrix as optional — confirm during requirements whether v1.1 includes them as real interactions or display-only, since there is no load-creation form (AL5).

## Sources

**Load lifecycle & tender protocol:**
- [What is Shipment Status Updates? — Owlery](https://owlery.ai/glossary/shipment-status-updates)
- [Shipment Status & Alerts Workflows — TAI Software](https://learn.tai-software.com/knowledge/shipment-status)
- [EDI X12 204 Motor Carrier Load Tender overview — EDI2XML](https://www.edi2xml.com/blog/edi-x12-204-motor-carrier-load-tender-overview/)
- [X12 EDI 204 Motor Carrier Load Tender — Stedi](https://www.stedi.com/edi/x12/transaction-set/204)
- [EDI 990 Response to a Load Tender — Infocon Systems](https://www.infoconn.com/EDIDOCS/EDI990.htm)
- [How to automate EDI 204s truckload tender process — Coneksion](https://www.coneksion.com/blog/how-to-automate-edi-204s-truckload-tender-process)

**Roles (broker / dispatcher / carrier / factoring):**
- [Freight Broker vs. Dispatcher: What's the Difference? — altLINE](https://altline.sobanco.com/freight-broker-vs-dispatcher-differences/)
- [Freight Broker vs Dispatcher: Key Differences (2026) — O Trucking](https://otrucking.com/resources/guides/freight-broker-vs-dispatcher/)
- [Freight Brokers vs. Dispatchers — Freight 360](https://www.freight360.net/freight-brokers-vs-dispatchers/)
- [The Complete Guide to Freight Factoring — Transwest Capital](https://www.transwestcapital.com/blog/the-complete-guide-to-freight-factoring-for-trucking-companies)
- [Comprehensive Guide to Freight Invoice Factoring — Triumph](https://triumph.io/blog/carrier/comprehensive-guide-to-freight-invoice-factoring/)
- [What Is Freight Factoring & How Does It Work? — altLINE](https://altline.sobanco.com/freight-factoring/)

**Fraud, chain-of-trust & FMCSA identity (2025–2026):**
- [Broker and Carrier Fraud and Identity Theft — FMCSA](https://www.fmcsa.dot.gov/mission/help/broker-and-carrier-fraud-and-identity-theft)
- [Double Brokering: Legal Consequences and FMCSA Penalties (2026) — O Trucking](https://otrucking.com/resources/guides/double-brokering-legal-consequences/)
- [FMCSA Ditches MC Numbers: What Carriers Must Know — FreightWaves](https://www.freightwaves.com/news/what-it-means-for-the-industry-as-fmcsa-eliminates-mc-numbers-in-2025)
- [Registration Modernization FAQs — FMCSA](https://www.fmcsa.dot.gov/registration/modernization-faqs)
- [How Carriers Can Spot and Report Double-Brokering — Truckstop](https://truckstop.com/blog/how-to-report-double-brokering/)

**Load detail / TMS field set:**
- [Load Board (Truckstop) — TMS Wiki](https://wiki.tms.ai/load-board-truckstop)
- [Transportation Management Systems (TMS): Features and Providers — AltexSoft](https://www.altexsoft.com/blog/transportation-management-system/)

---
*Feature research for: Validation Ledger iOS Client — v1.1 "Load Flows" milestone (load domain only)*
*Researched: 2026-05-19*
*Feeds: REQUIREMENTS.md categorisation + REQ-IDs and the v1.1 roadmap phase structure*
