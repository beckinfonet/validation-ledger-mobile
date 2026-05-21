# Phase 9: Load Detail & Chain-of-Trust Graph - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

The marquee surface of v1.1 — the load detail screen and the interactive chain-of-trust graph. This phase delivers:

- A new `LoadDetailViewController` + `LoadDetailViewModel` pair under `validationLedger/Features/Loads/Detail/`, reached by tapping a row in Phase 8's `LoadListViewController` (a `UICollectionViewDelegate.collectionView(_:didSelectItemAt:)` hookup the phase wires, since the Phase 8 VC is currently inert on tap).
- A consumer of Phase 7's `LoadDetailEndpoint` returning the embedded `{ load: Load, chainOfTrust: ChainOfTrust }` payload (one round-trip — Phase 7 D-08).
- A composed screen with three regions: pinned load-summary header (reference #, origin→destination, load status badge), the **interactive chain-of-trust graph** (the dominant region on iPhone — see Composition), and a "full bill-of-lading" scroll body (status timeline + freight detail rows + parties inline + chain-integrity verdict block).
- A new `TrustGraphView: UIView` — the graph canvas. Custom UIKit `UIView` nodes (one per `TrustNode`) + `CAShapeLayer` edges (one per `TrustEdge`). Zero new dependencies; no SwiftUI. Hosted inside a `UIScrollView` for pan+zoom (per the gesture model below).
- A new `TrustNodeView: UIView` per node, composing the Phase 8 `VerificationBadgeView` + node chrome + role label + display-name label. Tappable.
- The **fraud visual language** layered on the graph: animated CAShapeLayer halos, banner, dim treatment — see Decisions §Fraud Visual Language.
- A **status-timeline view** rendering the Posted → Tendered → Accepted → Dispatched → In-Transit → Delivered progression as a horizontal stepper + a "current state" expanded card. Reads `Load.stateHistory` for real timestamps; side-states are NOT surfaced here.
- Two tap surfaces — node-tap (TRUST-03) and edge-tap (TRUST-04) — both implemented as `UISheetPresentationController` modals with `.medium` + `.large` detents. Same surface pattern, different content.
- A **Phase 7 contract evolution**: `TrustNode.priorRelationshipCount: Int` is replaced by `TrustNode.priorRelationships: [PriorRelationship]` (new nested type). Every Phase 7 detail fixture is re-authored to populate it. Phase 9 owns this contract refactor, parallel to how Phase 8 D-02 evolved the list-endpoint envelope from `[Load]` to `[LoadListItem]`.
- The full pinch-zoom + double-tap-recenter gesture choreography on the graph (see Decisions §Graph Interaction Model).
- iPad regular-width gets a **side-by-side split** layout: graph fills the LEFT ~60% as a fixed canvas; the full bill-of-lading scroll body lives in the RIGHT ~40% pane. iPhone gets the single-column "graph dominates" composition.
- A `LoadDetailViewModel` state machine: `.loading` (skeleton-with-shimmer, per Phase 8 D-10 app-wide pattern) → `.loaded(load, chainOfTrust)` → `.error(message)`. No `.empty` — detail fetches are by ID and 404s collapse to `.error`.

What this phase is **NOT**:
- Any role-action buttons / tender / accept / reject UI / `LoadActionEndpoint` consumer (Phase 10).
- Any editable load fields (PROJECT.md OOS — load detail is read-only in v1.1).
- Any POD signature/photo capture or `pod_captured` transition (M3).
- Any map / live truck-location tracking (M3 background location).
- Any in-app messaging between counterparties (M4/v2).
- Any client-side trust derivation or chain-integrity computation (Phase 7 D-18 — server-supplied only).
- A separate `/parties/{id}/verification` fetch (Phase 7 D-08 — `ChainOfTrust` is embedded in the detail response).
- Any client-side re-rendering of side-states (rejections, expiries) on the timeline (kept clean here; audit-history is a future concern).

</domain>

<decisions>
## Implementation Decisions

### Screen Composition (the marquee posture)

- **D-01:** **Graph dominates.** On iPhone (`horizontalSizeClass == .compact`), the trust graph fills the upper ~60–70% of the screen as the focal region. Above it: a pinned load-summary header (reference #, origin→destination, load-status badge — compact). Below it: the bill-of-lading scroll body. The trust graph IS the screen — first frame, every load. This is the platform thesis made visible.
- **D-02:** **iPhone below-the-fold = bill-of-lading scroll.** Below the graph region on iPhone, the user scrolls through: status timeline → freight detail rows (origin/destination + dates + equipment + weight + rate) → each party listed inline with `VerificationBadgeView` → chain-integrity verdict block (rendered when verdict is non-clean; reads `chainIntegrity.reason`).
- **D-03:** **iPad regular-width = side-by-side split.** The graph fills the LEFT ~60% of the screen as a fixed canvas (the right edge is the split boundary). The RIGHT ~40% pane is the same bill-of-lading scroll content as iPhone below-the-fold — pinned header on top of the right pane + scrollable body below. Implemented via a `UIStackView`/Auto-Layout that branches on `traitCollection.horizontalSizeClass`; rotation from compact→regular animates the split into existence. Satisfies the PROJECT.md "iPad must render natively, not just scale" constraint.

### Graph Interaction Model

- **D-04:** **Pinch zoom + double-tap recenter.** `TrustGraphView` is hosted inside a `UIScrollView` with `minimumZoomScale=1.0`, `maximumZoomScale=2.5`. The `UIScrollView` natively handles two-finger pan + pinch. A separate `UITapGestureRecognizer(numberOfTapsRequired: 2)` recognizes double-tap; double-tap on a node → animate-recenter+zoom to that node (~250ms ease-in-out, scale ~1.8x); double-tap on empty canvas → reset to the default zoom + center. Single-tap on a node opens the verification-basis sheet (TRUST-03); single-tap on an edge opens the handoff sheet (TRUST-04). Outside the graph region the page scrolls normally — the `UIScrollView`'s gesture recognizers are scoped to the graph view's bounds. **This is the gesture-arbitration resolution called out as spike item (b) in the ROADMAP Phase 9 note.**
- **D-05:** **Default zoom: fit-all-nodes tight.** When the detail screen opens, `TrustGraphView.layoutSubviews` computes a fit-to-bounds transform that makes all present nodes (3–5 depending on the load) as large as possible while still showing every node + every edge. The whole chain is visible at-a-glance on the first frame. User pinches in to inspect a specific node. Every load opens with the full trust picture — marquee posture.
- **D-06:** **Fixed role slots.** Node positions are hard-coded by `Role` on the canvas (shipper top-left, broker upper-center, carrier center, dispatch right-center, factoring bottom-right — exact coordinates a planner detail). Every load's graph LOOKS at-a-glance similar — users learn "I check the carrier spot for the red glow." Missing roles are simply absent; edges drawn between whatever nodes are present. **Phase 7's `TrustNode` carries NO position data** — no contract change for layout. **This resolves spike item (d) "iPad-wide vs. iPhone-tall graph layout" — same role-slot logic on both, just rescaled into the available canvas dimensions.**

### Tap Surfaces (TRUST-03 + TRUST-04)

- **D-07:** **Ship both TRUST-03 (node-tap) and TRUST-04 (edge-tap) at FULL quality in Phase 9.** No trim, no defer, no follow-up-phase. The ROADMAP Phase 9 note's edge-tap scope-trim option is explicitly rejected. Edges are tappable from day one with the same surface treatment as nodes.
- **D-08:** **Modal sheet with detents.** Both node-tap and edge-tap open a `UISheetPresentationController` with `.medium` + `.large` detents. At `.medium` (~50% height) the graph stays visible behind the sheet — the user keeps context while reading. iOS 17-native (matches deployment minimum). On iPad the same sheet API renders as a floating card. Single source of presentation infrastructure for both tap types.

### Verification-Basis Sheet Content (TRUST-03)

- **D-09:** **Role-relevant facts only.** The sheet shows:
    - **KYC** (everyone): "KYC verified <relative time>" when `kycCompletedAt != nil`; "KYC not completed" with neutral-grey icon otherwise.
    - **Device-binding** (everyone): rendered from `deviceBindingStatus` (e.g. "Device bound · iPhone · since Apr 2026" / "Device not registered").
    - **USDOT authority** (Carrier + Dispatch ONLY): rendered from `usdotNumber` + `usdotAuthorityStatus`; row HIDDEN for Shipper / Factoring (no "Not applicable" placeholder).
    - **Prior relationships** (everyone): rendered as a LIST — see D-10.
- **D-10:** **Prior relationships rendered as a tappable LIST, not a count.** Each list row: prior load reference (e.g. `VL-1023`) · relative time (`3 months ago`) · relationship framing (`broker → carrier`). The sheet pulls this from `TrustNode.priorRelationships: [PriorRelationship]` (see D-12). Row taps in Phase 9 are inert (a UI affordance documented but not wired — wiring "tap a prior load → push another LoadDetailVC" is a future-phase concern; Phase 9 ships only the rendering).
- **D-11:** **Chain-integrity reason rendered inline when this node is implicated.** When the tapped node's `partyID` appears in `chainIntegrity.implicatedNodeIDs`, an inline "Why this party is flagged" block renders at the bottom of the sheet showing the verdict (`caution` / `compromised`) + `chainIntegrity.reason` copy. Clean nodes don't get this block at all.

### Phase 7 Contract Evolution (owned by Phase 9)

- **D-12:** **Replace `TrustNode.priorRelationshipCount: Int` with `TrustNode.priorRelationships: [PriorRelationship]`.** This is a **breaking** change to the Phase 7 shipped contract. Justification: every Phase 7 detail fixture (`load-detail-VL-*.json`) is already being re-authored in Phase 9 anyway (the fraud-archetype loads need recognizable prior-load history to dramatize the platform thesis), and the count-as-derivation-of-array is cleaner than maintaining both fields. Precedent: Phase 8 D-02 evolved `LoadListEndpoint.Response.loads: [Load]` → `[LoadListItem]` mid-milestone with the same kind of contract refactor.
- **D-13:** **`PriorRelationship` value type** (new, lives at `validationLedger/Core/Load/PriorRelationship.swift`). Pure `Decodable & Sendable`. Fields (indicative; planner finalizes): `loadID: String`, `occurredAt: Date`, `counterpartyRole: Role`, `counterpartyDisplayName: String?` (optional — the display name is denormalized for sheet rendering convenience). Wire-key: `prior_relationships` → `priorRelationships` under `APIClient.defaultDecoder()`'s `.convertFromSnakeCase`; explicit `CodingKey` enum only for `loadID` (the only trailing-acronym field).
- **D-14:** **Phase 7 fixture re-authoring** is a Phase 9 deliverable: every existing Phase 7 detail fixture's `TrustNode` entries get the bare `prior_relationship_count` removed and a fully-populated `prior_relationships` array added — with prior-load IDs that read realistically and that, for the three fraud-archetype loads (Phase 7 D-13), surface a recognizable pattern (e.g. a chameleon-carrier flagged node carries 0 prior relationships; a clean carrier flagged node carries 5+). Fixture-as-product-surface (Phase 7's specific-ideas posture extends here).

### Fraud Visual Language

- **D-15:** **Tiered visual response to `chainIntegrity`** (resolving ROADMAP spike item (a) "four-state visual language"):
    - `clean` → no extra chrome. Standard node/edge rendering. No banner.
    - `caution` → **yellow banner** at the top of the graph region with `chainIntegrity.reason` copy; flagged nodes get a **yellow CAShapeLayer halo** (static, no pulse); flagged edges render as **yellow dashed lines**; unflagged nodes/edges **dim to ~50% opacity**. The "this needs attention" state.
    - `compromised` → **red banner** + **red CAShapeLayer halo** with **animated subtle pulse** (~1.2s loop, opacity 0.6→1.0, infinite repeat); flagged edges render as **red dashed lines**; unflagged nodes/edges **dim to ~50% opacity**. The "this is bad" state.
    - **Pulse is the "this is BAD" tell; color is the "how bad" tell.** Pulse fires ONLY on `compromised`. Color (yellow vs red) distinguishes `caution` from `compromised`.
- **D-16:** **Banner is fixed (does not scroll away on iPhone).** The chain-integrity banner is pinned to the top of the graph region; scrolling the bill-of-lading body below the graph does not dismiss or hide it. Fraud signal is persistent. The chain-integrity verdict block in the scroll body (D-02) is a separate, scrollable render of the same data — duplication is intentional (above-the-fold marquee + in-context reading).

### Status Timeline (LOAD-06)

- **D-17:** **Hybrid: horizontal stepper + current-state expanded card.** A 6-pill horizontal stepper renders the primary lifecycle (Posted → Tendered → Accepted → Dispatched → In-Transit → Delivered) — completed pills solid, current pill accented + larger, future pills outlined. Below the stepper, a card shows the current state in detail: actor party name (from `LoadStatusEvent.actor`), full timestamp, and a "next milestone" line (e.g. "Awaiting delivery"). Renders from `Load.stateHistory` (Phase 7 D-02 — real `(status, timestamp, actor)` data). Lives in the right pane on iPad / below-graph in the iPhone scroll body.
- **D-18:** **Side-states are NOT surfaced in the timeline.** Even when `stateHistory` contains rejected / expired / cancelled events, the stepper renders only the primary 6-pill lifecycle. The "current state" card likewise shows only the current state, not the history. **Architectural separation:** trust-graph + chain-integrity banner = fraud-signal surface; status timeline = pure logistics ("where is this freight on its happy path"). Audit-history is a future-phase concern. The fixture-history of a previously-rejected-then-retendered load is identical visually to a clean load in this timeline — that's accepted.

### Loading / Error States

- **D-19:** **Skeleton-with-shimmer for the `.loading` state.** Follows the app-wide pattern established by Phase 8 D-10. The skeleton mimics the detail screen silhouette — pinned-header rectangle on top, a placeholder graph region (5 grey circles in the role slots connected by grey lines), and 3–4 grey placeholder rows for the bill-of-lading body — with the same horizontal `CAGradientLayer` shimmer sweep. On iPad, the skeleton mirrors the split layout. On `.loaded` the skeleton swaps to the real layout.
- **D-20:** **No `.empty` state.** Detail is by-ID; a missing load is a server error, not an empty result. The VM's state machine is `.loading` → `.loaded(load, chainOfTrust)` → `.error(message)`. The error state mirrors Phase 8's UI-SPEC posture: a centered `UIContentUnavailableView` (iOS 17+) with the generic localized copy `loads.detail.error.generic` and a "Try again" button that re-fires the fetch. Server-supplied error text NEVER reaches the screen (consistent with Phase 8 UI-SPEC §Copywriting).

### VoiceOver / Accessibility (ROADMAP spike item (c))

- **D-21:** **VoiceOver traversal order is locked.** On iPhone (single column): pinned header → graph region (as one accessibility container — see D-22) → status timeline (stepper as a single combined element + current-card as its own element) → freight detail rows → chain-integrity verdict block. On iPad split: same order, but the right pane is traversed first (it has the freight metadata), then the left pane (the graph). The user can pre-jump to the graph with the rotor.
- **D-22:** **Graph accessibility container model.** `TrustGraphView` is a single `accessibilityElements` parent whose ordered children are the node views (in fixed role order: shipper → broker → carrier → dispatch → factoring), followed by the edge views (in `fromPartyID` order then `toPartyID` order — deterministic traversal). Each node view's `accessibilityLabel` is a composed string: "<role>, <displayName>, verification state: <state>, KYC <basis-summary>". Each edge view's `accessibilityLabel`: "Handoff from <fromRole> to <toRole>, <relationshipState>". When the user activates an accessibility element (single-finger double-tap), the corresponding tap surface opens — same node/edge tap codepath. Pinch-zoom is disabled while VoiceOver is active (`UIAccessibility.isVoiceOverRunning`); the canvas stays at fit-all-nodes-tight zoom.

### Claude's Discretion

The planner / researcher / UI-researcher may finalize without re-asking the user:

- Exact role-slot coordinates on the canvas (the geometry that makes the 5 fixed slots look balanced at fit-all-nodes-tight zoom on both iPhone and iPad split widths).
- The exact zoom animation curve and duration (~250ms ease-in-out is indicative).
- The exact maximumZoomScale (2.5 is indicative — anything that lets a node read clearly at max zoom on iPhone).
- The exact pulse animation parameters on compromised nodes (~1.2s, 0.6→1.0 opacity, infinite repeat is indicative).
- The exact `PriorRelationship` field set on the new value type (D-13 is indicative; the planner picks the final field list that fixture authoring + UI rendering need together).
- The split-percentage on iPad (60/40 is indicative — anything that gives the graph the dominant share while keeping the right pane legible).
- The exact node visual: chrome (rounded square vs. circle), size, label placement (above/below/centered), and the layered composition of `VerificationBadgeView` + role label + display-name label inside `TrustNodeView`. UI-SPEC owns this.
- Edge-color rules when the chain is `clean` but an individual edge's `relationshipState` is `.unverified` (UI-SPEC owns; the planner can decide whether such edges still get any neutral chrome or render identically to verified edges).
- Banner copy template (e.g. "⚠ Chain compromised — <reason>" vs. "Risk flagged: <reason>"). UI-SPEC owns; product copywriting concern.
- Terminal-state card content (what the "current state" card shows when the load is `delivered` or `cancelled` — likely a static "Delivered <date>" / "Cancelled <date>" without a "next milestone" line).
- The exact `UISheetPresentationController` detent configuration (`.medium` + `.large` vs `.large` only for content density) per tap-surface content size.
- Whether the row-tap from Phase 8's `LoadListViewController` wires through a coordinator pattern (`LoadCoordinator`) or a direct `present/push` from the VC. The v1.0 precedent is coordinators (`KYCCoordinator`, `AuthCoordinator`); Phase 9 SHOULD continue the precedent but the planner can introduce a thin `LoadCoordinator` or extend an existing one.
- snake_case ↔ camelCase wire bridge for `prior_relationships` → `priorRelationships` is handled by `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy; explicit `CodingKey` only for the trailing-acronym field on `PriorRelationship`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope, requirements, and roadmap
- `.planning/ROADMAP.md` — Phase 9 goal, the 5 success criteria, the dependency on Phase 8, the design-spike note calling out spike items (a)–(d) (resolved here in D-15/D-04/D-21/D-03/D-06), the TRUST-04 scope-trim cut line (rejected here in D-07).
- `.planning/REQUIREMENTS.md` — LOAD-05 (open detail from row), LOAD-06 (status timeline), TRUST-01 (interactive chain-of-trust graph), TRUST-03 (node verification basis), TRUST-04 (edge handoff detail), TRUST-05 (flagged + integrity-verdict render from fixture).
- `.planning/PROJECT.md` — v1.1 scope; constraints (UIKit-first; SwiftPM-only; iOS 17; iPad must render natively, NOT just scale; zero PII; mock-only); Out-of-Scope (read-only detail in v1.1, no editable load fields, no POD/map/messaging).

### Phase 7 contract that Phase 9 reads against AND evolves
- `.planning/phases/07-load-domain-model-mock-contract/07-CONTEXT.md` — D-02 (`stateHistory` is the timeline source), D-07 (TrustNode typed verification-basis fields — the four facts D-09 renders), D-08 (`ChainOfTrust` embedded in `LoadDetailEndpoint.Response`), D-09 (`VerificationState` fail-closed decode), D-13 (the three fraud archetypes — double-brokering, chameleon carrier, factoring fraud — the marquee data D-15 renders), D-18 (iOS = passive renderer).
- `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` — the typed endpoint Phase 9 consumes. `Response { load: Load, chainOfTrust: ChainOfTrust }`. UNCHANGED in Phase 9.
- `validationLedger/Core/Load/ChainOfTrust.swift` — defines `ChainOfTrust { nodes: [TrustNode], edges: [TrustEdge], integrity: ChainIntegrity }`, `TrustNode`, `TrustEdge`. **MODIFIED in Phase 9 (D-12):** `TrustNode.priorRelationshipCount: Int` → `TrustNode.priorRelationships: [PriorRelationship]`. The `CodingKeys` private enum on `TrustNode` updates accordingly.
- `validationLedger/Core/Load/Load.swift` — the aggregate Load value type carrying `stateHistory: [LoadStatusEvent]`. UNCHANGED.
- `validationLedger/Core/Load/LoadStatusEvent.swift` — `(status, timestamp, actor: LoadParty?)`. The timeline reads this. UNCHANGED.
- `validationLedger/Core/Load/LoadStatus.swift` — 13-case lifecycle enum; the stepper's 6 primary-lifecycle pills are a subset; side-states are NOT rendered (D-18). UNCHANGED.
- `validationLedger/Core/Load/VerificationState.swift` — 4-case fail-closed enum the badge consumes on each node and on each edge. UNCHANGED.
- `validationLedger/Core/Load/ChainIntegrity.swift` — verdict + reason + implicated IDs. D-15 reads `verdict` for color tier; D-11 reads `implicatedNodeIDs` for inline reason rendering; D-16 reads `reason` for banner copy. UNCHANGED.
- **NEW file:** `validationLedger/Core/Load/PriorRelationship.swift` — D-13's new nested value type. Phase 9 owns its creation.
- `validationLedger/Core/Networking/APIClient.swift` — typed-endpoint facade; `.convertFromSnakeCase` strategy handles `prior_relationships` → `priorRelationships`. UNCHANGED.

### Phase 8 contract Phase 9 builds on (reusable assets)
- `.planning/phases/08-role-filtered-load-list/08-CONTEXT.md` — D-09/D-10 (skeleton-with-shimmer is the app-wide loading pattern; Phase 9 follows verbatim per D-19). LoadListVC integration point — Phase 9 wires the row-tap navigation.
- `.planning/phases/08-role-filtered-load-list/08-UI-SPEC.md` — the established design contract: `DS.Spacing` / `DS.Typography` / `DS.Colors` token namespace; `UIContentUnavailableView` for error states; 44pt touch-target floor; readable-content-guide pinning on iPad regular width (D-03 here extends this with split-pane geometry); accessibility-identifier conventions.
- `validationLedger/UI/Components/VerificationBadgeView.swift` — the 4-state pill component, **reused** on every TrustNodeView and on inline party-list rows. UNCHANGED.
- `validationLedger/UI/Components/LoadStatusBadgeView.swift` — the 13-state pill component, **reused** in the pinned summary header and on the stepper's current-pill accent. UNCHANGED.
- `validationLedger/Features/Loads/LoadListViewController.swift` — **MODIFIED in Phase 9:** wire `collectionView(_:didSelectItemAt:)` to push the new `LoadDetailViewController`. Currently inert on tap.
- `validationLedger/Features/Loads/LoadListViewModel.swift` — UNCHANGED (the list VM doesn't own detail navigation).
- `validationLedger/Features/Loads/Cells/LoadRowCell.swift` — UNCHANGED.
- `validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift` — pattern reference for the new `LoadDetailSkeletonView` (D-19).

### v1.0 UIKit precedents Phase 9 mirrors
- `validationLedger/App/AppContainer.swift` — composition root. Phase 9 adds a `loadDetailScreenFactory: (Load.ID) -> UIViewController` (or analogous shape) wired through the `loadListScreenFactory` already in place (Phase 8 plumbing), so the list VC can push the detail VC without depending on the container directly. Mirrors the Phase 5 `kycStatusScreenFactory` pattern.
- `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift` — the canonical fetch-on-appear + state-machine + `UIRefreshControl` UIKit precedent. The Phase 9 detail VC mirrors its overall posture; divergence: skeleton (not spinner) for loading per D-19, no pull-to-refresh on detail (refresh on detail is a future-phase concern).
- `validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift` — coordinator pattern precedent. Phase 9 SHOULD continue the precedent with a thin `LoadDetailCoordinator` (or extend an existing one) for the row-tap → push → modal-sheet-presentation flow. Planner discretion.

### Phase 7 fixtures Phase 9 re-authors (D-14)
- `validationLedgerTests/Networking/Fixtures/load-detail-VL-*.json` — every existing detail fixture is re-authored to: (1) replace `prior_relationship_count` with `prior_relationships: [...]` on every TrustNode; (2) populate realistic prior-load IDs that reinforce the platform thesis (clean carriers carry 5+ priors; chameleon carriers carry 0; etc.); (3) where the fixture is a fraud archetype (Phase 7 D-13), the chain-integrity `reason` copy is reviewed for marquee-quality rendering against D-15's banner.
- `validationLedgerTests/Networking/Fixtures/load-detail-VL-*-error*.json` (if any) — error-response fixtures that drive D-20's `.error` state.

### Stale — do NOT rely on
- `.planning/codebase/*.md` (all 7 files dated 2026-04-21, "brand-new SwiftUI scaffold") — predates all of v1.0. Phase 7 and 8 contexts flagged this. The source tree is authoritative.

### Informational milestone context
- `.planning/milestones/v1.0-REQUIREMENTS.md` — archived v1.0 requirements (FOUND/ARCH/NET/AUTH/DEV/KYC/UPL/SHELL/SESS/GEO/SEC/LOG/CI). Cite if needed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`LoadDetailEndpoint`** (`Core/Networking/Endpoints/LoadDetailEndpoint.swift`): the typed Phase 7 endpoint; `APIClient.request(LoadDetailEndpoint(loadID:))` returns `{ load: Load, chainOfTrust: ChainOfTrust }` — one round-trip. Zero contract changes here.
- **`VerificationBadgeView`** (`UI/Components/VerificationBadgeView.swift`): the 4-state pill from Phase 8 — reused on every `TrustNodeView`, on inline party-list rows, and (potentially) on the chain-integrity banner. Phase 8 D-08 explicitly anticipated this reuse on graph nodes.
- **`LoadStatusBadgeView`** (`UI/Components/LoadStatusBadgeView.swift`): the 13-state load-status pill from Phase 8 — reused in the pinned summary header and on the timeline stepper's current-pill accent.
- **`DS.Spacing` / `DS.Typography` / `DS.Colors`** (`UI/DesignSystem/`): every spacing, font, and color token is already present. The fraud visual language (D-15 yellow / red / dimmed-50% / pulse) consumes existing `DS.Colors` semantic tokens; if new tokens are required (e.g. a "danger-banner-bg" or a "compromised-pulse-glow"), UI-SPEC adds them under the existing namespace.
- **`MockURLProtocol` latency / forced-failure injection** (Phase 7 D-14): drives the `.loading` skeleton (latency injector) and the `.error` state (failure injector) without any new test infra.
- **`MockLoadFixtureRegistry`** (`Core/Networking/Mock/MockLoadFixtureRegistry.swift`): the Phase 7 registry registering per-fixture detail responses. Phase 9 extends it additively for any new fixtures (e.g. an extra detail fixture that exhibits the dimmed-others rendering across all verdicts).
- **`UISheetPresentationController` with detents** (iOS 17+, deployment minimum): native infrastructure for D-08's modal-sheet tap surfaces. No new presentation infrastructure needed.
- **`UIScrollView` with min/max zoom + delegate `viewForZooming`**: native infrastructure for D-04's pan+zoom on the `TrustGraphView`. No third-party gesture libraries.
- **`CAShapeLayer` + `CABasicAnimation`** (already used in `SkeletonLoadRowCell` shimmer): the same pattern animates D-15's compromised-pulse glow.

### Established Patterns
- **MVVM + Coordinators** (project-wide): `LoadDetailViewController` (UIKit view) + `LoadDetailViewModel` (state machine + APIClient consumer). VM publishes `enum State: Equatable { case loading, loaded(Load, ChainOfTrust), error(String) }`; the VC observes and switches the rendered subview. A thin `LoadDetailCoordinator` (or extension of an existing one) owns the push from list → detail and the modal presentation for tap surfaces.
- **Skeleton-with-shimmer for `.loading`** (Phase 8 D-09/D-10 app-wide pattern): the detail skeleton mimics the detail screen silhouette (pinned-header rectangle, graph-region placeholder with 5 grey circles in role slots, 3–4 grey body rows). On iPad mirrors the split layout.
- **Diffable datasource for any UICollectionView with mutation** (Phase 8 precedent): the bill-of-lading scroll body (or the right-pane scroll on iPad) MAY use a single-section diffable datasource if it's a `UICollectionView`, or a plain `UIStackView`-in-`UIScrollView` if simpler. Planner discretion — the list of party rows + timeline + detail rows + verdict block is short and has no mutation, so a stack-in-scroll is likely fine.
- **`adjustsFontForContentSizeCategory = true` on every label** (codebase-wide): Dynamic Type fully supported on every label in the detail screen + the sheets + the timeline.
- **`UICollectionViewListCell` for any list-style row** (Phase 8 precedent): the bill-of-lading party rows + the prior-relationship list inside the sheet both use list-cells if rendered in a collection-view, or pure auto-layout UIView if rendered in a stack.
- **`nonisolated public struct` for typed endpoints** (every Phase 6/7 endpoint follows this): `LoadDetailEndpoint` already does. Unchanged.
- **`.convertFromSnakeCase` decoding strategy** (`APIClient.defaultDecoder()`): handles `prior_relationships` → `priorRelationships` transparently. No explicit `CodingKey` on the new field; explicit `CodingKey` only for `loadID` on the new `PriorRelationship` (trailing-acronym).
- **44pt touch target** (UI-SPEC + Phase 3 precedent): every tappable surface in Phase 9 (node containers, edge tap targets, sheet rows, the "Try again" CTA, etc.) honors the 44pt floor. Edges are tappable; the tap target is a wider invisible hit-region around the `CAShapeLayer` line.

### Integration Points
- **NEW directory:** `validationLedger/Features/Loads/Detail/` — hosts `LoadDetailViewController.swift`, `LoadDetailViewModel.swift`, and the graph subviews `TrustGraphView.swift`, `TrustNodeView.swift`, `TrustEdgeRenderer.swift` (or similar), plus the timeline subview `StatusTimelineView.swift`, the chain-integrity banner `ChainIntegrityBannerView.swift`, the bill-of-lading body `LoadDetailBodyView.swift`, the skeleton `LoadDetailSkeletonView.swift`, and the sheet content VCs `VerificationBasisSheetViewController.swift` + `HandoffDetailSheetViewController.swift`. Exact file partitioning is planner discretion.
- **NEW file:** `validationLedger/Core/Load/PriorRelationship.swift` — D-13's new value type.
- **MODIFIED:** `validationLedger/Core/Load/ChainOfTrust.swift` — D-12: `TrustNode.priorRelationshipCount: Int` removed; `TrustNode.priorRelationships: [PriorRelationship]` added. Header comment updated. `CodingKeys` enum updated.
- **MODIFIED:** `validationLedger/Features/Loads/LoadListViewController.swift` — wire `collectionView(_:didSelectItemAt:)` to push the detail VC. The currently-inert row-tap becomes a navigation push (or coordinator-handled push).
- **MODIFIED:** `validationLedger/App/AppContainer.swift` — add a `loadDetailScreenFactory: (String) -> UIViewController` injected into the existing `loadListScreenFactory: (Role) -> UIViewController` (or threaded via a thin `LoadDetailCoordinator`). Composition-root continuation.
- **MODIFIED (fixture data):** every `validationLedgerTests/Networking/Fixtures/load-detail-VL-*.json` — `prior_relationship_count` → `prior_relationships: [...]` on every TrustNode, with realistic prior-load history. Fraud-archetype fixtures get curated history.
- **MODIFIED (unit tests):** Phase 7's TrustNode decode tests are updated for the new field. Snapshot tests for the badges and skeleton continue to apply unchanged (badges are Phase 8 components; skeleton silhouette is new). Phase 9 adds: TrustGraphView snapshot tests (per verdict tier × per device); StatusTimelineView snapshot tests; VerificationBasisSheetViewController + HandoffDetailSheetViewController snapshot tests; LoadDetailViewModel state-machine tests; gesture tests (programmatically simulate tap, double-tap, pinch); accessibility-label assertions on every node + edge in the graph.
- **POTENTIAL NEW:** `validationLedgerUITests/LoadDetailFlowTests.swift` — 5-role XCUITest smoke flow: tap a load row on each role → assert the detail screen renders with the expected accessibility identifier; on the compromised-archetype load, assert the banner accessibility label contains the reason text; assert the verification-basis sheet opens on node tap.

</code_context>

<specifics>
## Specific Ideas

- **The trust graph is the marquee surface of the entire v1.1 milestone.** Every other decision in Phase 9 was made to serve making the chain-of-trust graph the first thing the user sees on every load — D-01 (graph dominates), D-05 (fit-all-nodes-tight on open), D-15 (banner + pulse + dim others), D-07 (ship TRUST-04 at full quality). The planner should treat the graph rendering and gestures as the centerpiece — every design tradeoff during planning should resolve in favor of the graph's polish.
- **Fixed role slots over server-supplied positions is a recognizability decision, not a simplicity decision.** Users are meant to learn the canvas — "I check the carrier spot for the red glow." Every load's graph LOOKS at-a-glance similar; the fraud signal is positional, not just chromatic. Planner should ensure the iPhone and iPad split-canvas use proportionally the SAME role-slot geometry so the user's spatial memory transfers across devices.
- **The pulse-only-on-compromised tell is the marquee fraud animation.** It must be subtle enough not to be distracting on a clean screen the user happens to switch to, but loud enough that a flagged-carrier load draws the eye on first frame. UI-SPEC owns the exact parameters; the planner should snapshot-test the static `compromised` frame, not the animated one (animation parity in snapshot tests is brittle).
- **Side-states NOT shown on the timeline is an architectural separation.** Trust-graph + banner = fraud surface; timeline = logistics surface. A previously-rejected-then-retendered load looks identical to a clean one in the timeline. **That's intentional.** Anyone reading this context who thinks the timeline should show rejections — they should re-read D-18 first, and then if they still disagree, raise the issue as a deferred idea for a future audit-history phase. Don't quietly add side-state rendering to the timeline.
- **Phase 9 owns a Phase 7 contract evolution.** This is consistent with the Phase 8 precedent (D-02). The planner should treat `TrustNode` as a live contract that the v1.1 milestone keeps refining, NOT a frozen Phase 7 artifact. The fixture re-authoring is fixture-as-product-surface work — author realistic prior-load history that reinforces the platform thesis.
- **VoiceOver is a first-class spike output, not an afterthought.** The graph accessibility container model (D-22) is locked: nodes traversed in role-order then edges, single-finger double-tap opens the same sheet as a sighted user's tap, pinch-zoom disabled while VoiceOver runs. The planner should write the XCUITest assertions for this from day one.

</specifics>

<deferred>
## Deferred Ideas

- **Tap a prior-relationship row to push another LoadDetailVC** — the verification-basis sheet's prior-relationships LIST (D-10) shows tappable-looking rows, but Phase 9 ships them as inert affordances. Wiring "tap a prior load → push another LoadDetailVC" is a future-phase concern (introduces a navigation cycle to manage, an "are we already viewing this load?" check, and a back-navigation policy for the modal sheet flow). The visual affordance is documented but the wire-up is deferred.
- **Audit-history view rendering side-states (rejections, expiries, cancellations) inline on the timeline or as a separate disclosure** — explicitly deferred per D-18. If product later wants the fraud history surfaced, it should be a separate "Load History" surface (a new phase) — NOT a modification of the Phase 9 timeline.
- **Pull-to-refresh on the load detail screen** — Phase 8's pull-to-refresh pattern (LOAD-08) lives on the list, not on the detail. v1.1 detail is a one-shot fetch on appear; if real-time updates land in a post-v1.1 milestone (PROJECT.md "Real-time load updates"), the detail screen will need a refresh mechanism — but it's deferred.
- **Map / live truck-location pin on the detail screen** — explicitly deferred to M3 (background location). The graph is the trust surface; geography is a future concern.
- **Editable load fields on the detail screen** — explicitly PROJECT.md OOS (editable load data mid-lifecycle is a tampering surface). Detail stays read-only in v1.1.
- **Edge-color rules for `unverified` edges in `clean` chains** — UI-SPEC concern; if product wants individual-edge trust signaling independent of chain integrity, that's a UI-SPEC refinement, not a new contract.
- **Banner copy A/B variants** — the exact banner copy ("⚠ Chain compromised — <reason>" vs "Risk flagged: <reason>") is UI-SPEC owned; copy variants are deferred to product copywriting.
- **Tap-to-recenter feedback (haptic on node-tap, soft tap on double-tap reset)** — `UIImpactFeedbackGenerator.medium` on node-tap could improve the polish; not specified in the discussion but a small Phase 9 micro-feature the planner may include or defer.

### Reviewed Todos (not folded)

- **`device-ci-biometric-infra.md`** — v1.0 physical-device-CI infrastructure todo (a Face ID prompt hangs the device-CI lane as an unsatisfiable biometric input, manifesting as a 35-minute timeout). Matched on generic keywords (`status`, `device`, `phase`, `plan`) with score 0.6; unrelated to a UI graph + detail screen feature. **Not folded** — third consecutive review (Phases 7, 8, 9). Remains a carried v1.0 infrastructure item.

</deferred>

---

*Phase: 9 — Load Detail & Chain-of-Trust Graph*
*Context gathered: 2026-05-20*
