# Project Research Summary

**Project:** Validation Ledger iOS Client — v1.1 "Load Flows"
**Domain:** Identity-verified freight load management — role-filtered list, load detail, interactive chain-of-trust graph, and per-role tender/accept/reject — built against MockURLProtocol fixtures on a shipped UIKit/MVVM-C base
**Researched:** 2026-05-19
**Confidence:** HIGH overall (all four research files grounded directly in the shipped v1.0 source tree and high-quality freight-domain primary sources)

---

## Executive Summary

v1.1 "Load Flows" is a subsequent milestone adding the freight load domain to an already-shipped, architecturally settled iOS app (~28,700 LOC, 207 files, 6 phases of v1.0 completed 2026-05-18). The stack, architecture patterns, and dependency graph are fixed; the only genuine open question was how to render the interactive chain-of-trust graph — and research concludes unambiguously: custom UIKit `UIView` nodes with `CAShapeLayer` edges, zero new dependencies. The trust graph is a fixed 5-node directed chain, not an arbitrary topology, so force-directed libraries and SpriteKit are both wrong tools and both violate hard project constraints (UIKit-for-critical-surfaces, closed dependency shortlist). Everything new in v1.1 slots into proven v1.0 patterns: a new `Core/Load/` domain kernel, new `APIEndpoint` conformers extending the contract-first mock networking, a single role-parameterized `Features/Loads/` module consumed by all 5 role shells.

The load domain is well-understood from freight industry standards. The state machine maps directly to the EDI 204/990 tender handshake. The five-role action matrix collapses to three distinct action surfaces (Shipper/Broker share tendering, Carrier/Dispatch share accept/reject/advance, Factoring is read-only), reducing the apparent complexity. The chain-of-trust graph's node/edge data model is a Validation Ledger-specific design synthesized from FMCSA fraud patterns and the v1.0 identity primitives — defensible and grounded, but with no published competitor rendering it exactly this way. This warrants a design review during Phase 9 planning.

The primary risks are: (1) the trust graph becoming a source of client-derived trust signals — verification state must be server-supplied and render-only, never computed client-side; (2) fixture design that only covers the happy path, leaving error/empty/latency states unbuilt; (3) the mock-to-live contract drift if the load list is built without pagination or with loose JSON decoding; and (4) gesture conflicts on the graph surface if tap, page-scroll, and optional pan/zoom are not architected deliberately. All four are preventable if the Phase 7 foundation (contract, data model, fixture matrix) is done correctly before any UI work starts — exactly as v1.0's contract-first discipline proved.

---

## Key Findings

### Recommended Stack

v1.1 reuses the v1.0 stack wholesale. There are no new dependencies and no version bumps. `Package.swift` and `Package.resolved` are unchanged: two packages only — Nuke 13.0.2 (pinned exact) for async image loading, and SwiftLintPlugins 0.63.2 for lint enforcement. All load-domain features are built on first-party Apple frameworks (UIKit, Core Animation, `UIScrollView`, `UICollectionView`).

The only framework decision specific to v1.1 is the trust-graph renderer. Four options were evaluated (custom `UIView` nodes, `UICollectionView` custom layout, SpriteKit, and Grape — a third-party SwiftPM graph library). Custom `UIView` nodes with `CAShapeLayer` edges wins on every criterion: interactivity via native hit-testing and `UIScrollView` zoom, trivial layout for a fixed 5-node chain, native iPad rendering via Auto Layout and size classes, and full VoiceOver accessibility because each node is a real view. SpriteKit is rejected for poor VoiceOver support (disqualifying on a trust product). Grape is rejected because it is SwiftUI-only (violates UIKit-first for critical surfaces) and requires a dependency-shortlist exception with no justification.

**Core technologies (v1.1 additions):**
- `UIView` / `UIControl` node subclasses + `CAShapeLayer` edges: trust-graph rendering — deterministic fixed-topology layout, full accessibility, zero new deps
- `UIScrollView` (with `viewForZooming`): graph pan/zoom — canonical UIKit solution, no custom gesture math
- `UICollectionView` compositional layout: load list — already the v1.0 default for list surfaces
- `MockURLProtocol` + `APIClient` + `Endpoint` (in-repo, v1.0): extended with 3 new load-domain endpoints and a `MockLoadFixtureRegistry` — no networking-layer change

### Expected Features

The feature set is scoped tightly to what PROJECT.md marks Active. All 13 load-domain features are P1 for v1.1 — there is no P2/P3 within the milestone. The relevant signal is dependency order, not priority tiers.

**Must have (table stakes — the load domain does not exist without these):**
- L1 Role-filtered load list — each of 5 roles sees only its relevant loads via server-side fixture filter
- L2 Standard load row with freight field set + verification badge
- L3 Load detail screen — host for the graph and action bar
- L4 Load status timeline — Posted to Tendered to Accepted to Dispatched to In-Transit to Delivered
- L5 Tender / Accept / Reject interaction — EDI 204/990 modelled, mock-only
- L6 One-tap status advancement (Carrier/Dispatch only)
- L7 Empty / loading / error states on list and detail
- L8 Pull-to-refresh — the only state-propagation path in a mock-only milestone

**Should have (Validation Ledger differentiators — the reason this milestone exists):**
- L9 Interactive chain-of-trust graph — the marquee v1.1 feature; no competitor renders the full per-load chain as a tappable node-graph
- L10 Per-party verification state badges everywhere a party appears — reusable `VerificationBadge` component
- L11 Tap-a-node for verification basis detail — KYC date, device binding, USDOT authority, relationship history
- L12 Refuse-to-tender when counterparty unverified — hard client-side disable with inline reason
- L13 Double-brokering risk rendered on the graph — flagged nodes/edges from fixture-supplied `chainIntegrity` verdict

**Defer (post-v1.1, requires running backend):**
- Real-time load updates (WebSocket/SSE) — replaces pull-to-refresh post-v1.1
- APNs push for tender/status-change notifications
- Full load-creation form for Shipper/Broker
- Edge-tap detail on the trust graph (scope-trim candidate if Phase 9 runs long)
- eBOL / rotating QR / dock scanner — explicit M3 milestone
- Factoring invoice-submission write-path — post-v1.1

**The load state machine (canonical for REQUIREMENTS.md):**
`draft > posted > tendered > accepted > dispatched > in_transit > delivered` plus `rejected`, `expired`, `cancelled` as non-terminal side-states. `pod_captured`, `invoiced`, `funded` are display-only in v1.1 (kept in the enum so Factoring's list has content; no interactive transitions).

**Per-role action matrix collapses to 3 action surfaces:**
- Shipper + Broker: post, tender, retender, cancel
- Carrier + Dispatch: accept, reject, advance status (dispatched > in_transit > delivered)
- Factoring: view only

### Architecture Approach

v1.1 adds exactly two new structural areas and modifies four existing files/groups. NEW: `Core/Load/` (shared domain kernel — value types, state machine, `RoleLoadPolicy`) and `Features/Loads/` (the feature module — `LoadsCoordinator`, list, detail, trust graph). MODIFIED: the 5 role tab-bar controllers (swap the placeholder Loads tab for a real `LoadsCoordinator`), and `AppContainer` (add load factories and `MockLoadFixtureRegistry` registration). Every other v1.0 file is untouched. The `APIClient`, `MockURLProtocol`, `APIEndpoint`, and `IdempotencyInterceptor` require zero changes — v1.1 simply adds conformers and fixture registrations.

**Major components:**
1. `Core/Load/` — `Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy` as pure `Decodable & Sendable` value types; the single source of truth for the load state machine and the role-to-action-set policy table. Lives in `Core/` so all 5 role shells and `AppContainer` can import it without tripping the `no_cross_feature_import` lint rule.
2. `Features/Loads/` — one module, role-parameterized: `LoadsCoordinator` (owns the Loads-tab nav stack), `List/` (VC + VM + cell), `Detail/` (VC + VM + `LoadActionBar`), `TrustGraph/` (child VC + view + VM + `TrustNodeDetailViewController`). Five role shells each instantiate the same coordinator with their `Role`.
3. `MockLoadFixtureRegistry` + JSON fixtures — extends the v1.0 `MockOTPRoleFixtureRegistry` pattern; a separate registry keeps `MockDefaultFixtures` from growing unbounded. Must cover every verification-state permutation, every load-status state, and both happy-path and failure responses for every action.
4. `RoleLoadPolicy` — a pure `(Role, LoadStatus) -> [LoadAction]` table in `Core/Load/`; `LoadDetailViewModel` calls it once; `LoadActionBar` renders the result. Zero `switch load.status` in any view.
5. `TrustGraphViewController` — a child VC embedded in `LoadDetailViewController` via `addChild`; exposes `onNodeTapped: (TrustNode) -> Void`; the owning coordinator presents `TrustNodeDetailViewController` modally. Not a coordinator — it owns a view, not a flow.

**Key data-flow decisions:**
- `ChainOfTrust` is embedded in the `LoadDetailEndpoint.Response` — one round-trip for the detail screen, no separate graph fetch, no graph-level loading state.
- Role-in-path URL scheme (`/loads/broker`) rather than query-string (`/loads?role=broker`) to match `MockURLProtocol`'s path-only matcher without modifying it.
- The one-line mock/live swap (`AppContainer.defaultNetworkConfig`) requires zero load-feature code changes.

### Critical Pitfalls

1. **Reaching for a third-party graph library or SwiftUI Canvas for the trust graph** — Both violate hard project constraints (UIKit-for-critical-surfaces, closed dependency shortlist). The trust graph is a fixed 5-node directed chain, not an arbitrary topology; it needs a layout, not a layout algorithm. Build it with `UIView` nodes and `CAShapeLayer` edges. Ratify this in the Phase 9 plan before any code is written.

2. **Client-derived verification state** — A green checkmark computed from local fixture fields is a fraud vector on a fraud-prevention product. Verification state must be a server-supplied opaque enum on every party object, rendered as-is, defaulting to least-trusted when absent or unknown. Design this into the Phase 7 contract; no client code path may upgrade trust based on local logic.

3. **Happy-path-only mock fixtures** — `MockURLProtocol` is synchronous and instant. If the fixture matrix only covers 200-OK responses, the UI for loading/empty/error/latency states never gets built. Extend the fixture layer with injectable latency and forced-failure in Phase 7; require per-screen demos against empty, error, and slow fixtures as acceptance criteria.

4. **Optimistic action UI with only a success branch** — Tender/accept/reject actions must ship their rollback path in the same plan as their forward path. The pre-action state snapshot, revert-on-failure, and specific error copy are not polish — they are correct behavior on a chain-of-custody product. Wire every action endpoint through the existing v1.0 idempotency-key interceptor; control disabled in-flight.

5. **Load list built without pagination** — The mock can return everything in page 1, but if the ViewModel and diffable data source are not built for pages, the eventual backend forces a list/VM/snapshot rework. Build pagination from Phase 8; the mock returns a paginated response even if it always has exactly one page.

---

## Implications for Roadmap

Research identifies a clear 4-phase dependency order for v1.1, continuing from v1.0's Phase 6. Phase numbering continues at 7.

### Phase 7: Load Domain Model + Mock Contract

**Rationale:** This is the load-bearing foundation that all subsequent phases consume. The state machine, action policy table, typed endpoints, and fixture matrix must exist before any screen can decode a load. v1.0's identical lesson: the `APIEndpoint` + `MockURLProtocol` infrastructure was built in Phase 2 before any feature consumed it. Skipping this phase produces fixture-over-fitted screens that require a refactor at the live-backend swap.

**Delivers:** `Core/Load/` value types (Load, ChainOfTrust, TrustNode, LoadStatus, LoadAction, RoleLoadPolicy); 3 typed `APIEndpoint` structs (LoadListEndpoint, LoadDetailEndpoint, LoadActionEndpoint); `MockLoadFixtureRegistry`; full fixture matrix (per-role list fixtures, per-state loads, empty/error/large/latency/action-failure fixtures); `RoleLoadPolicy` unit tests covering all (role, status) pairs; MockURLProtocol latency/failure-injection capability.

**Features addressed:** Prerequisite for L1-L13 and the load endpoints Active item. The fixture schema (verificationState, chain, chainIntegrity, stateHistory, respondByAt, tenderEligibility) must be designed here — it gates L9, L10, L11, L12, L13.

**Pitfalls to prevent:** Pitfall 3 (verification state as server-supplied opaque field), Pitfall 7 (state machine + RoleLoadPolicy as a tested module, not view logic), Pitfall 8 (fixture matrix + latency/failure injection), Pitfall 9 (contract-first strict models, pagination shape).

**Research flag:** Standard patterns — follows proven v1.0 contract-first discipline. No deeper research phase needed. The one design decision to ratify here is the role-in-path URL scheme for the load list endpoint.

---

### Phase 8: Role-Filtered Load List

**Rationale:** The load list is the critical-path root. Load detail, the trust graph, and all action surfaces are reached by tapping a list row. The list is also the cheaper screen and the natural place to prove role-parameterization in isolation before the graph adds complexity.

**Delivers:** `LoadsCoordinator`, `LoadListViewController/ViewModel/Cell`; "Loads" tab wired in all 5 role shell tab-bar controllers; `AppContainer` load factory; pull-to-refresh; empty/loading/error states; iPad-native regular-width layout. The `VerificationBadge` design-system component (L10) is created here because the row depends on it; it is reused by L12 and L9.

**Features addressed:** L1 (role-filtered list), L2 (standard load row + L10 verification badge), L7 (empty/loading/error), L8 (pull-to-refresh).

**Pitfalls to prevent:** Pitfall 5 (iPad native layout — multi-column on regular width, size-class-driven), Pitfall 9 (paginated list against a paginated fixture, strict decoding), Pitfall 8 (per-role empty-list and error fixtures exercised before marking done).

**Research flag:** Standard patterns — role-parameterized UICollectionView list against MockURLProtocol fixtures is a proven v1.0 shape. No deeper research phase needed.

---

### Phase 9: Load Detail + Chain-of-Trust Graph

**Rationale:** The load detail screen is the host for the trust graph and cannot exist without the list to navigate from (Phase 8). The `ChainOfTrust` is embedded in the detail response, so the graph cannot be a standalone screen — detail and graph are a single phase. This is the highest-complexity and highest-design-investment phase in v1.1.

**Delivers:** `LoadDetailViewController/ViewModel`; `LoadActionBar` (renders but shows no actions yet — that is Phase 10); `TrustGraph/` sub-module (`TrustGraphViewController` as child VC, `TrustGraphView` with UIView nodes + CAShapeLayer edges, `TrustGraphViewModel`, `TrustNodeDetailViewController`); list-to-detail navigation in `LoadsCoordinator`; `AppContainer` detail factory; status timeline (L4); iPad-native graph layout (horizontal chain on regular width, responsive to traitCollectionDidChange and bounds changes).

**Features addressed:** L3 (load detail), L4 (status timeline), L9 (chain-of-trust graph), L11 (tap-node for verification basis), L13 (double-brokering risk rendering — flagged nodes/edges from fixture's chainIntegrity field).

**Pitfalls to prevent:** Pitfall 1 (UIView nodes + CAShapeLayer edges — ratify before Phase 9 code starts; no library, no SwiftUI), Pitfall 2 (gesture arbitration designed up front — fixed-aspect graph in a scrolling page, generous 44pt hit targets, physical-device smoke test), Pitfall 3 (graph renders server-supplied verification state only; fail-closed to least-trusted; no offline/cached chain), Pitfall 5 (iPad-native graph layout, re-layout on Split View resize), Pitfall 10 (VoiceOver: each node view is an accessibilityElement with role + verification state label; Dynamic Type: UIFont.preferredFont on node labels).

**Research flag:** FLAG FOR DEEPER RESEARCH. The trust graph is the only HIGH-complexity feature with no off-the-shelf component. Phase 9 should open with a brief design-spike step covering: (a) the four-state visual language finalized as a design artifact, (b) gesture arbitration model written into the plan before implementation, (c) VoiceOver traversal order and accessibility element setup, (d) iPad-wide vs. iPhone-tall layout decision. The STACK.md research already resolved the rendering approach (Option A wins unambiguously); the remaining open items are design and interaction decisions.

---

### Phase 10: Per-Role Tender / Accept / Reject

**Rationale:** Action buttons mutate state that only exists once the detail screen renders it (Phase 9). The action set computation depends on `RoleLoadPolicy` (Phase 7) and `LoadDetailViewModel` (Phase 9). Doing actions last lets them build on a proven foundation; it is also the most cross-role-sensitive surface.

**Delivers:** Active `LoadActionBar` buttons (tender, accept, reject, advance-status) driven by `RoleLoadPolicy.actions(for: role, status:)`; `LoadDetailViewModel.perform(_:)` with optimistic UI + rollback path; `LoadsCoordinator.onLoadActioned` -> list refresh on pop-back; L12 refuse-to-tender disable (inline reason from `tenderEligibility` fixture field); action -> status -> action-set recompute loop.

**Features addressed:** L5 (tender/accept/reject), L6 (one-tap status advance), L12 (refuse-to-tender-to-unverified).

**Pitfalls to prevent:** Pitfall 4 (rollback path ships in the same plan as the forward path; pre-action snapshot captured; action demoed against 409/422/timeout fixtures), Pitfall 6 (every action endpoint registered with v1.0 idempotency interceptor; control disabled in-flight; action key generated per-action not per-retry), Pitfall 7 (zero switch load.status in any VC/cell; all gating from RoleLoadPolicy; unit-tested before UI).

**Research flag:** Standard patterns — the action POST -> recompute -> re-render cycle mirrors `KYCStatusViewModel`. The idempotency interceptor is shipped. `RoleLoadPolicy` is designed and tested in Phase 7. No deeper research phase needed, but Phase 10 planning must include an explicit checklist item verifying action endpoints are registered with the interceptor.

---

### Phase Ordering Rationale

- **Contract first (Phase 7) is non-negotiable.** Both list and detail decode `Core/Load/` types; `RoleLoadPolicy` is needed by Phase 10; the fixture schema gates the trust graph, verification badges, and the refuse-to-tender feature. Building the contract first means Phases 8-10 never block on schema churn.
- **List before detail (8 before 9).** Detail is reached by tapping a list row; the list also proves role-parameterization in isolation. The trust graph cannot be a standalone screen.
- **Detail and graph together (Phase 9).** `ChainOfTrust` is embedded in the detail response; the graph has no independent host. Splitting them creates a detail screen with a placeholder graph that then needs to be removed — more total work.
- **Actions last (Phase 10).** Actions depend on `RoleLoadPolicy` (Phase 7) AND the detail VM (Phase 9). They are the most cross-role-sensitive surface and benefit from building on a proven foundation.
- **Each phase is independently demoable:** Phase 7 — endpoint fixtures decode in unit tests. Phase 8 — tap "Loads" in any role shell -> real role-correct list. Phase 9 — tap a load -> detail with live trust graph; tap a node -> verification basis. Phase 10 — each role can take its legal actions; load state advances visibly; list reflects it.

### Research Flags

**Needs deeper research / design spike at phase planning time:**
- **Phase 9** (Load Detail + Trust Graph): The rendering approach is settled (UIKit Option A), but the visual design language, gesture arbitration model, VoiceOver accessibility design, and iPad-wide layout need to be explicit written decisions in the Phase 9 plan before implementation starts. A half-day design spike is appropriate; avoid discovering these mid-build.

**Standard patterns — no research phase needed:**
- **Phase 7** (Load Domain Model + Mock Contract): Follows proven v1.0 contract-first discipline. The `APIEndpoint` + `MockURLProtocol` + fixture registry pattern is well-established in the codebase.
- **Phase 8** (Role-Filtered Load List): Role-parameterized `UICollectionView` list against mock fixtures is the v1.0 house pattern. The iPad multi-column layout is standard UIKit.
- **Phase 10** (Per-Role Actions): The action POST -> recompute -> re-render cycle mirrors `KYCStatusViewModel`. The idempotency interceptor is shipped. `RoleLoadPolicy` is designed and tested in Phase 7.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new technology decisions. Trust-graph rendering choice (UIKit Option A) supported by Apple official docs and a clear four-option decision matrix. Package.swift unchanged. |
| Features | HIGH | Load state model grounded in EDI 204/990 industry standards. Per-role action matrix cross-verified against settled freight industry structure. Scope mapped 1:1 against PROJECT.md Active list. |
| Architecture | HIGH | Every placement decision mirrors an observed v1.0 pattern in the shipped source tree. `Core/Load/` mirrors `Core/Identity/`; `Features/Loads/` mirrors `Features/Onboarding/`; child-VC graph pattern mirrors `KYCCoordinator` shape. |
| Pitfalls | HIGH | UIKit gesture arbitration, diffable data source identifier pitfalls, and security rules are well-documented. The exact `CAShapeLayer` vs `draw(_:)` implementation detail for graph edges is a Phase 9 implementation choice, not a research gap. |

**Overall confidence: HIGH**

### Gaps to Address

- **Trust-graph visual design language**: The four states (verified/pending/unverified/flagged) need a concrete visual design (colors, glyphs, typography) finalized as a design artifact before Phase 9 implementation. This is a design gap, not a research gap.

- **`post`/`cancel` action scope**: The per-role action matrix includes post and cancel as optional for Shipper/Broker, but there is no load-creation form (AL5 is an anti-feature for v1.1). REQUIREMENTS.md should clarify whether these actions are entirely omitted from v1.1 UI or rendered as disabled with a reason.

- **Edge-tap interaction scope**: Tapping a graph edge (the handoff/tender detail) is noted as a "nice to have" and is the most plausible scope-trim candidate if Phase 9 runs long. REQUIREMENTS.md should mark it as optional with a clear cut condition.

- **`MockURLProtocol` latency/failure injection**: The current implementation is synchronous and instant (confirmed by direct source inspection). Phase 7 must extend it with injectable latency and forced-failure capability before any load screen is built.

- **`TechStack.md` dangling reference (minor cleanup)**: `PROJECT.md` and `CLAUDE.md` both reference `TechStack.md` in the repo root as the authoritative v1 iOS spec. That file no longer exists (removed/archived; `PROJECT.md` was used as the authoritative scope source throughout this research without issue). Update those references at the next convenient opportunity. Not a blocker.

---

## Sources

### Primary (HIGH confidence)

- `.planning/PROJECT.md` — v1.1 scope, constraints, Active/Deferred feature list, key decisions, milestone context (authoritative project doc)
- `validationLedger/` source tree, v1.0 "M1 Foundation" shipped 2026-05-18, ~28,700 LOC — all architecture decisions grounded in direct source inspection
- Apple Developer Documentation — `UIScrollView`, UIKit gesture recognizers, `UICollectionViewDiffableDataSource`, Apple HIG minimum tap targets
- [EDI X12 204 Motor Carrier Load Tender — Stedi](https://www.stedi.com/edi/x12/transaction-set/204)
- [EDI 990 Response to a Load Tender — Infocon Systems](https://www.infoconn.com/EDIDOCS/EDI990.htm)
- [FMCSA — Broker and Carrier Fraud and Identity Theft](https://www.fmcsa.dot.gov/mission/help/broker-and-carrier-fraud-and-identity-theft)
- [FMCSA Registration Modernization FAQs](https://www.fmcsa.dot.gov/registration/modernization-faqs) — USDOT-only identity post-Oct-2025
- [SwiftGraphs/Grape — GitHub](https://github.com/SwiftGraphs/Grape) — evaluated and rejected; SwiftUI-only renderer

### Secondary (MEDIUM confidence)

- [altLINE — Freight Broker vs. Dispatcher](https://altline.sobanco.com/freight-broker-vs-dispatcher-differences/)
- [Triumph — Comprehensive Guide to Freight Invoice Factoring](https://triumph.io/blog/carrier/comprehensive-guide-to-freight-invoice-factoring/)
- [AltexSoft — Transportation Management Systems](https://www.altexsoft.com/blog/transportation-management-system/)
- [Jesse Squires — Diffable data source behavior changes iOS 15](https://www.jessesquires.com/blog/2021/07/08/diffable-data-source-behavior-changes-and-reconfiguring-cells-in-ios-15/)
- SpriteKit pan/zoom and `SKShapeNode` performance pitfalls — community sources, corroborated across multiple results
- `.planning/research/v1.0/STACK.md`, `.planning/research/v1.0/PITFALLS.md` — prior milestone research (used as context)

---
*Research completed: 2026-05-19*
*Ready for roadmap: yes*
