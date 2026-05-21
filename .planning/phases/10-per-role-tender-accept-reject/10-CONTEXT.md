# Phase 10: Per-Role Tender / Accept / Reject - Context

**Gathered:** 2026-05-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 10 makes loads ACTIONABLE on the detail screen. Every cross-role action — `.post`, `.tender`, `.accept`, `.reject`, `.cancel`, `.advanceStatus` — runs through a single composed action region inside `LoadDetailBodyView`, gated entirely by `RoleLoadPolicy.actions(for:status:)` (Phase 7) and submitted through `LoadActionEndpoint` (Phase 7). The platform thesis lands in the load domain: the broker cannot tender to an unverified counterparty (ACTION-07), and every cell that ships the screen is computed from policy, not from `switch load.status` branches.

This phase delivers:

- A new `LoadActionsView` (or equivalent) inside `Features/Loads/Detail/`, mounted into `LoadDetailBodyView`'s vertical stack between the status timeline and the freight detail rows. Renders the result of `RoleLoadPolicy.actions(for:status:)` as buttons; renders a localized caption when the action set is empty.
- A modal sheet (`TenderSheetViewController`, `UISheetPresentationController` with `.medium` detent) presented when the broker/shipper taps `Tender`. Carrier picker + respond-by deadline picker. Sends the typed `LoadActionEndpoint.RequestBody` with `actorRole + targetPartyID + respondByAt`.
- A new mock endpoint (planner finalizes path — indicative: `GET /carriers/directory`) returning a static demo carrier directory fixture (~6–8 mock carriers spanning verified / unverified / flagged) — drives the tender carrier picker. Phase 10 owns the endpoint, the fixture, and its `MockURLProtocol` registration.
- Optimistic UI with rollback on the detail screen: load state (status + timeline + action set + deadline) advances visually on tap; the chain-of-trust card stays at its pre-tap rendering with a subtle "updating…" overlay (chain is server-derived — never predicted client-side). On 200 the VM swaps to `response.load + response.chainOfTrust`. On error the predicted load state un-winds and a top toast banner slides in with localized fixed copy (server-supplied error text NEVER reaches the screen — Phase 9 D-20 / T-09-04 lock applies symmetrically).
- The active-tender countdown surface: `Load.respondByAt` rendered for the carrier/dispatch role's view of a `.tendered` load (Phase 9 timeline already renders the timestamps; Phase 10 adds the "respond by" emphasis — UI-SPEC owns the visual).
- ACTION-07 enforcement at TWO gates: (1) the load-level `Load.tenderEligibility.canTender` gate disables the Tender BUTTON on the detail screen, with `disabledReason` shown inline; (2) the carrier-level picker shows unverified/flagged carriers visible-but-disabled with an inline reason. Both gates are SERVER-DRIVEN (Phase 7 D-18).
- DEBUG-only launch-arg toggles enabling on-device exercise of the failure paths: `-MockActionConflict409`, `-MockActionValidation422`, `-MockActionServerError500`, plus `-MockActionLatencySlow` to make the in-flight optimistic state visible during human UAT. Same pattern as `-MockKYCStatusVerified` (Phase 5) and `-Mock2DTrustGraphOnIPhone` (Phase 9.1 D-12). `#if DEBUG`-gated; stripped from Release.
- `Role` propagation from `LoadListViewController` → `AppContainer.makeLoadDetailScreen(loadID:role:)` → `LoadDetailViewController` → `LoadDetailViewModel`. The detail VM needs the actor role to pass into `LoadActionEndpoint.RequestBody.actorRole` and to evaluate `RoleLoadPolicy.actions(for:status:)`. The existing factory closure in `AppContainer.makeLoadListScreen(role:)` (line 255-258) is the natural threading point — the `role` is already captured in the list-VC's environment.
- List refresh on pop-back: `LoadListViewController.viewWillAppear → Task { await viewModel.fetchLoads() }` (already in place since Phase 8, line 381) handles success criteria #5 with zero new wiring.

What this phase is **NOT**:

- A multi-field load-creation form (deferred — PROJECT.md `LOAD-F1`; `.post` acts on pre-existing draft fixtures only).
- An editable-load-fields surface (PROJECT.md Out of Scope — load detail is read-only in v1.1 except for role-action buttons).
- A POD signature/photo capture or `pod_captured` transition (M3).
- A real-time push surface for tender notifications (deferred to a post-v1.1 milestone — RT-02).
- Any client-side trust derivation, action gating from `switch load.status` in views, or chain integrity computation (Phase 7 D-18 — server-supplied only; ROADMAP §Phase 10 explicit lock).
- A `retender` distinct LoadAction — retender is `.tender` invoked again on `.posted` / `.rejected` / `.expired` (Phase 7 D-04). The action bar renders `[.tender, .cancel]` on `.rejected`/`.expired` per `RoleLoadPolicy`.
- A separate `LoadActionViewModel` per detail screen. The action surface extends the existing `LoadDetailViewModel` state machine — see Implementation Decisions §VM ownership.
- A stable-idempotency-key implementation (the `IdempotencyInterceptor` auto-injects a fresh UUID per request — Phase 7 D-19). UI double-submit protection comes from the action-region's "buttons disable in-flight" rule, not from key reuse. Stable-key replay is a post-v1.1 follow-up if a real backend ever needs it.

</domain>

<decisions>
## Implementation Decisions

### Action-Bar Composition

- **D-01:** The action region lives **INSIDE `LoadDetailBodyView`**, positioned in the vertical scroll stack right after `StatusTimelineView` and before the freight detail rows. It is NOT a separate top-level region on `LoadDetailViewController` — adding a fourth top-level child to the iPhone composition would force another `compositionConstraints` rebuild in `traitCollectionDidChange(_:)`. The body view already owns the scroll order; the action region inherits that ownership.

- **D-02:** **Buttons are arranged side-by-side equal width** in a horizontal `UIStackView` (`.fillEqually`). NOT primary-vs-secondary visual hierarchy. The carrier's `[reject, accept]` decision is a true fork, not a recommended-default pattern; treating the buttons as equal weight matches the underlying semantics. The 44pt touch-target floor (UI-SPEC universal) is satisfied via `automaticDimension` row height + minimum button height; Dynamic Type scaling stacks the buttons vertically when content gets long.

- **D-03:** **Destructive actions (`.cancel`, `.reject`) get a destructive tint.** This is a UI-SPEC visual concern, not a layout concern — the equal-weight layout doesn't preclude destructive-color treatment. UI-SPEC 10 owns the exact token (likely `DS.Colors.destructive`, already present and consumed by Phase 9 error states).

- **D-04:** **Empty state shows a tasteful localized caption** when `RoleLoadPolicy.actions(for:status:) == []` — the region stays present in the scroll order, but renders explanatory copy in place of buttons. Two indicative copies (UI-SPEC owns final strings + localization keys):
  - Factoring on any state: `"This is a view-only role. No actions available."` (`loads.actions.empty.factoring`)
  - Terminal states (`.delivered`, `.cancelled`, `.podCaptured`, `.invoiced`, `.funded`) for non-Factoring roles: `"This load is [delivered|cancelled|invoiced|…]. No actions available."` (`loads.actions.empty.terminal`)
  Hiding the region silently would force callers to read "no buttons" as either "nothing for me to do" or "the screen is broken" — caption removes that ambiguity.

- **D-05:** **iPad split layout: the action region stays in the RIGHT pane** (the body pane), immediately after the status timeline. Identical iPhone/iPad logic — the body is the body in both compositions, just rescaled. No spanning bottom bar, no floating overlay on the graph. Consistent with Phase 9 D-03 ("the body view itself never branches on size class — branching happens at the VC level").

### Tender Flow UX

- **D-06:** **Tender opens a `UISheetPresentationController` modal sheet** with `.medium` detent (`.large` available for tall accessibility content sizes). The sheet hosts a new `TenderSheetViewController` containing the carrier picker + deadline picker + Send / Cancel actions. Same sheet API Phase 9 D-08 uses for the verification-basis + handoff-detail sheets — single source of presentation infrastructure across detail-screen modals.

- **D-07:** **The carrier list in the picker comes from a static demo directory fixture.** New JSON fixture `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` with ~6–8 mock carriers spanning the four `VerificationState` cases. New mock endpoint (indicative path — planner finalizes: `GET /carriers/directory`) registered via `MockLoadFixtureRegistry` (or a sibling registry for symmetry). The same directory is shown for every load — crucially this means the picker works on `.posted` loads whose `ChainOfTrust.nodes` contains no carriers yet (the canonical happy path is `.posted → tender`, which would have an empty picker if sourced from the chain).

- **D-08:** **ACTION-07 enforcement in the picker is "visible but disabled with inline reason."** Unverified and flagged carriers appear in the list, render their `VerificationBadgeView` (Phase 8 component), are unselectable (`isUserInteractionEnabled = false` + visual disable treatment), and show a one-line localized reason underneath (e.g. `"Not verified — cannot tender"` / `"Flagged — cannot tender"`). Indicative localization keys: `loads.actions.tender.disabled.unverified` / `loads.actions.tender.disabled.flagged`. Hiding the bad carriers would let the user assume "there were just no other carriers" — the platform thesis is most useful when the user SEES the fraud signal and learns it can't be bypassed.

- **D-09:** **The load-level ACTION-07 gate is independent** of D-08's carrier-level gate. When `Load.tenderEligibility?.canTender == false`, the Tender BUTTON on the detail screen is hard-disabled before the sheet ever opens — with `tenderEligibility.disabledReason` rendered inline below the button. Server-driven (Phase 7 D-18 `TenderEligibility`). When `disabledReason == nil`, fall back to generic copy `loads.actions.tender.disabled.generic` (`"Tender is unavailable"`).

- **D-10:** **Deadline picker = preset chips + Custom… → full date/time picker.** Four chips: `1h`, `4h`, `24h`, `48h`. Default selection is `24h`. A fifth row `Custom…` opens an iOS-17 `UIDatePicker` (`.dateAndTime`, `.compact` style) so the broker can pick an arbitrary date/time. The resolved date/time renders below the chips (e.g. `"↳ Tomorrow, 5:00 PM"`) so the broker confirms the chip's literal value before sending. The resolved `Date` is what flows into `LoadActionEndpoint.RequestBody.respondByAt`.

- **D-11:** **The Send button is enabled only when** (a) a carrier is selected AND (b) the selected carrier is not the disabled-by-verification group AND (c) the deadline is in the future. (c) is a sanity guard — if the user selects `1h` and an iOS clock change pushes "now" past the deadline, the button gracefully disables. Indicative validation is planner-level. ALL Send-disabled states render a single localized helper line near the button (UI-SPEC owns copy).

### Optimistic UI Semantics

- **D-12:** **On tap, the WHOLE load state predicts forward — status, timeline, action set, deadline countdown all advance immediately.** The detail VM transitions to a new "in-flight" sub-state (see D-15) carrying the predicted post-action `Load` value (derived locally from the `LoadAction` + current `Load` — pure forward state-machine logic, NOT trust-derived). The VC re-renders against the predicted load. This buys the snappiest possible feel — taps land immediately.

- **D-13:** **The chain-of-trust card is NEVER predicted.** When the predict transition fires, the chain card (everyone-on-load strip + chain-of-vouches card / 2D graph on iPad + chain-integrity verdict) renders with a subtle "updating…" overlay — low-opacity layer or small spinner badge, exact visual is UI-SPEC. Chain is server-derived (Phase 7 D-18 lock); predicting it would risk showing a misleading trust state for milliseconds, exactly the thing the platform thesis attacks. The overlay says "this card will refresh" without making any trust claim.

- **D-14:** **On server 200, the VM swaps state to `response.load + response.chainOfTrust`** in one assignment. `LoadActionEndpoint.Response` already carries both fields (Phase 7 contract — symmetric with `LoadDetailEndpoint.Response`). NO follow-up `GET /loads/{id}` is needed; the response is the truth. Predicted load state confirmed (or replaced if server made adjustments the client couldn't predict); chain overlay removes; the fresh `chainOfTrust` renders.

- **D-15:** **On error, the predicted state un-winds AND a top toast banner slides in.** The VM transitions back to the pre-tap `.loaded(load, chainOfTrust)` state — the same values that were in `state` before the tap. The chain overlay removes. A toast banner slides down from the top of the screen with **generic localized copy** (NEVER server-supplied error text — Phase 9 D-20 / T-09-04 lock symmetric here), auto-dismisses after ~3–4s, swipe-to-dismiss enabled. Indicative copies (UI-SPEC owns finals):
  - `loads.actions.error.tender_failed` (`"Couldn't send tender. Try again."`)
  - `loads.actions.error.accept_failed` (`"Couldn't accept this tender."`)
  - `loads.actions.error.advance_failed` (`"Couldn't advance the load."`)
  - …one per `LoadAction` case.
  The error classification (409 vs 422 vs 500 vs network) is LOGGED (with `fields: [:]` per T-09-04) but never rendered.

- **D-16:** **VM ownership: extend `LoadDetailViewModel`, do NOT introduce a separate `LoadActionViewModel`.** The state machine evolves from Phase 9's 3-case `.loading / .loaded(Load, ChainOfTrust) / .error(message)` to:
  ```swift
  enum State: Equatable, Sendable {
      case loading
      case loaded(Load, ChainOfTrust)
      case actionInFlight(predicted: Load, frozenChain: ChainOfTrust, action: LoadAction)
      case actionFailed(rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String)
      case error(message: String)
  }
  ```
  (Planner finalizes exact case shape; the indicative set above captures the predict/rollback flow.) Rationale: a separate `LoadActionViewModel` would need a back-channel to the detail VM for the chain swap on success — that coupling is the cost of separation, with no isolation benefit. The detail VM already owns the `Load + ChainOfTrust` state; adding action submission to it keeps the entire screen's state in one place.

- **D-17:** **Buttons disable for the duration of `.actionInFlight`** — prevents double-submit at the UI level. Combined with `IdempotencyInterceptor`'s automatic `Idempotency-Key: <UUID>` injection (Phase 7 D-19, NET-04), this satisfies the dual lock from ROADMAP §Phase 10 ("in-flight actions are disabled to prevent double-submit and route through the v1.0 idempotency interceptor"). The idempotency key is a fresh UUID per request — stable-key replay is NOT implemented for v1.1 (the UI guard makes user-driven duplicates impossible; stable-key replay only matters for a real-backend scenario that doesn't exist in v1.1).

- **D-18:** **List refresh on pop-back leverages Phase 8's existing `viewWillAppear → fetchLoads()`** (`LoadListViewController.swift:381`). NO push-notification observer between detail and list. NO custom propagation channel. Costs one extra `GET /loads/{role}` per pop-back from a detail screen the user acted on — acceptable for v1.1 mock-only against ~12 loads. Correct by construction; zero new code. If a future milestone needs sub-100ms list refresh after action, a push-from-detail observer can be added additively.

### Failure-Path Exercise Mechanism (DEBUG-only)

- **D-19:** **Four DEBUG launch arguments enable on-device exercise of the rollback path** during human UAT. All four are `#if DEBUG`-gated and parsed via `ProcessInfo.processInfo.arguments.contains(...)` — same shape as `-MockKYCStatusVerified` (Phase 5, `MockDefaultFixtures.swift:32/69/71/200/222`) and `-Mock2DTrustGraphOnIPhone` (Phase 9.1 D-12):
  - `-MockActionConflict409` — every POST `/loads/{id}/{action}` returns the existing `load-action-conflict-409.json` fixture.
  - `-MockActionValidation422` — every action returns `load-action-validation-422.json`.
  - `-MockActionServerError500` — every action returns `load-action-server-error-500.json`.
  - `-MockActionLatencySlow` — the mock action handler delays its response by a fixed interval (indicative ~1.5s; planner-finalizes). Makes the optimistic-predict state visible to the human eye during UAT. Can be combined with any of the failure flags so the rollback + toast banner are also visible.

- **D-20:** **Toggle precedence is "first-match-wins" at registration time.** If the user sets multiple failure flags simultaneously, the registration order in `MockLoadFixtureRegistry` decides which fires — planner can hardcode an order (e.g. conflict → validation → server-error) and document it. In practice the QA workflow is "set exactly one failure flag at a time"; the multi-flag case is a defensive fallback, not a feature.

- **D-21:** **The default mock action handler (registered in Phase 7 — `MockLoadFixtureRegistry.swift:154`) returns `load-action-success.json` on every action.** Phase 10 does NOT change the default. It ADDS the four DEBUG-toggle-gated registration branches that take precedence when their flag is set. Release builds compile away the branches entirely; the success handler is the only behaviour shipped to TestFlight/App Store.

### Role Propagation (the structural gap Phase 10 closes)

- **D-22:** **`AppContainer.makeLoadDetailScreen(loadID:)` becomes `makeLoadDetailScreen(loadID:role:)`.** The factory closure threaded through `LoadListViewController` (constructed in `AppContainer.makeLoadListScreen(role:)`, lines 255-258) already captures the calling role — the closure becomes `{ [weak self] loadID in self?.makeLoadDetailScreen(loadID: loadID, role: role) }`. The detail VM gains `role: Role` as a designated-initializer parameter; the VC reads it via the VM for `RoleLoadPolicy.actions(for:status:)` calls and passes it through to `LoadActionEndpoint.RequestBody.actorRole`.

- **D-23:** **Roles are NOT client-changeable on the detail screen.** Once the detail screen is mounted by a tab shell, the role is fixed for that screen's lifetime — mirrors the v1.0 SHELL-04 ("role not client-changeable") lock at the navigation level. A user "switching roles" requires logout and re-login.

### Claude's Discretion

The planner / researcher / UI-researcher may finalize without re-asking the user:

- **Exact `LoadActionsView` class structure** — separate file under `Features/Loads/Detail/`, or inline as an extension of `LoadDetailBodyView`. Either is acceptable; planner picks the cleanest fit for Phase 9 D-19's skeleton-with-shimmer pattern (the action region should mimic its silhouette during `.loading`).

- **Exact `TenderSheetViewController` file partitioning** — one file or split into picker + deadline picker subviews; consistent with Phase 9's `VerificationBasisSheetViewController` / `HandoffDetailSheetViewController` precedent (one VC per sheet content type).

- **Exact carrier-directory endpoint path + struct shape** — `GET /carriers/directory` returning `[TrustNode]` is the indicative shape; planner finalizes (e.g. wrap in an envelope `{ carriers: [TrustNode] }` for consistency with the LoadListEndpoint envelope precedent).

- **Carrier-directory fixture exact list** — ~6–8 carriers across the four `VerificationState` values, ideally cross-referencing Phase 7's named-load library where carrier names recur (e.g. "Chameleon Cargo" matching the chameleon-carrier fraud archetype). The fixture is a PRODUCT SURFACE — the picker is where the broker meets the platform thesis.

- **Exact respond-by countdown UI for the carrier/dispatch view of `.tendered`** — static "Respond by Tomorrow 5:00 PM" vs. live-updating countdown ("2h 13m left"). Live countdown needs a `Timer` and a re-render cadence; UI-SPEC owns the call. The data source (`Load.respondByAt`) is locked.

- **Exact toast banner taxonomy** — one toast per `LoadAction` failure case (D-15 indicative list) OR a single generic "Couldn't complete that action" copy with the action name interpolated. UI-SPEC owns; the negative constraint (NEVER server text) is non-negotiable.

- **Exact predicted-state derivation** — the local pure forward state-machine that derives `predicted: Load` from `(currentLoad: Load, action: LoadAction)`. Planner builds this as a pure function (analogous to `RoleLoadPolicy.actions(for:status:)`) so it's unit-testable without UIKit. E.g. `tender on .posted → predicted .tendered + respondByAt = picked deadline`; `accept on .tendered → predicted .accepted + respondByAt = nil`. Planner sketches the full table.

- **Exact chain-overlay visual** (D-13) — opacity value, optional spinner badge, fade-in/fade-out duration. UI-SPEC 10.

- **Exact destructive-button tint** (D-03) — `DS.Colors.destructive` is the natural pick; UI-SPEC 10 owns.

- **Exact mock-toggle precedence** (D-20) — registration order in `MockLoadFixtureRegistry`. Planner picks and documents.

- **Exact `-MockActionLatencySlow` interval** — ~1.5s is indicative; planner picks what reads as "in-flight" without being annoying during repeated test runs.

- **Localization keys** — every user-facing string above uses an indicative key. UI-SPEC 10 finalizes the canonical key namespace (precedent: `loads.detail.error.generic`, `loads.list.nav_title.factoring`).

- **VM state-enum exact case shape** (D-16 indicative) — planner can shrink to fewer cases by using sub-types for the in-flight payload, or expand to handle finer sub-states. The contract is "predict on tap, swap on 200, rollback on error" — case shape is implementation.

- **Exact XCUITest coverage** — at minimum: one happy-path tender flow (broker → success), one rollback flow (carrier → 422 via `-MockActionValidation422`), one ACTION-07 hard-disable smoke (broker, `Load.tenderEligibility.canTender == false`). Planner picks the full matrix.

### Folded Todos

None folded — the only matching todo (`device-ci-biometric-infra.md`) is unrelated to action-bar functionality. See Reviewed Todos in `<deferred>`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope, requirements, and roadmap
- `.planning/ROADMAP.md` §Phase 10 — phase goal, 5 success criteria, dependency on Phase 9 (detail VM) and Phase 7 (`RoleLoadPolicy`), the explicit "Zero `switch load.status` in any view controller or cell" lock, the per-action rollback-ships-with-forward-path constraint, the idempotency-interceptor checklist item.
- `.planning/REQUIREMENTS.md` §v1.1 §Per-Role Actions — ACTION-01 through ACTION-09 (the 9 requirements Phase 10 satisfies); ACTION-07 is the platform-thesis-on-display requirement.
- `.planning/PROJECT.md` — v1.1 scope; load-detail OOS (read-only except for role-action buttons); UIKit-first / SwiftPM-only / iOS 17 / `MockURLProtocol`-only constraints; zero PII / Keychain-tokens / Secure-Enclave-keys posture; "trust that cannot be faked" core value.

### Phase 7 contract Phase 10 reads (FROZEN — do not modify in Phase 10)
- `.planning/phases/07-load-domain-model-mock-contract/07-CONTEXT.md` — D-03 (tender gate is .posted-only), D-04 (retender = .tender invoked again; no separate case), D-05 (.advanceStatus is a single case; backend derives target), D-06 (5 roles collapse to 3 surfaces; Factoring is empty), D-09 (`VerificationState` fail-closed decode), D-13 (3 fraud archetypes — the carrier-directory fixture should cross-reference these), D-14 (action-failure fixtures already exist), D-15 (action lives in URL path), D-18 (iOS is a passive renderer — every gate is server-supplied), D-19 (idempotency interceptor is wired — zero new infra).
- `validationLedger/Core/Load/LoadAction.swift` — the 6-case enum (`.post / .tender / .accept / .reject / .cancel / .advanceStatus`); `pathSegment` property maps `.advanceStatus → "status"` per D-05. NOT Decodable — encoding-only (client-to-server via URL path). UNCHANGED in Phase 10.
- `validationLedger/Core/Load/RoleLoadPolicy.swift` — the pure `(Role, LoadStatus) → [LoadAction]` resolver. Phase 10's action-bar code calls `RoleLoadPolicy.actions(for:status:)` and NEVER `switch load.status`. UNCHANGED in Phase 10.
- `validationLedger/Core/Load/LoadStatus.swift` — 13-case lifecycle enum; the action region renders against the current `Load.status`. UNCHANGED.
- `validationLedger/Core/Load/Load.swift` — `Load.respondByAt: Date?` (drives the carrier countdown UI), `Load.tenderEligibility: TenderEligibility?` (drives ACTION-07 load-level gate), `Load.stateHistory: [LoadStatusEvent]` (driven by Phase 9's timeline — unchanged here). UNCHANGED.
- `validationLedger/Core/Load/ChainOfTrust.swift` — `TrustNode`, `TrustEdge`, `ChainIntegrity`; the carrier directory fixture's items decode as `TrustNode` (matches the existing carrier-rendering surface in `VerificationBadgeView`). UNCHANGED.
- `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift` — POST `/loads/{loadID}/{action.pathSegment}`; `RequestBody = { actorRole, targetPartyID, respondByAt, note }`; `Response = { load: Load, chainOfTrust: ChainOfTrust }`. UNCHANGED.
- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` — auto-injects `Idempotency-Key: <UUID>` on every POST/PUT request. ZERO new wiring for Phase 10. UNCHANGED.
- `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — current action handler (line ~154) returns `load-action-success.json` for every action. Phase 10 ADDS the four DEBUG-toggle-gated registration branches (D-19). Existing handler stays.
- `validationLedgerTests/Networking/Fixtures/load-action-success.json` — default success fixture, returned by the unchanged success handler.
- `validationLedgerTests/Networking/Fixtures/load-action-conflict-409.json` — 409 fixture, consumed by `-MockActionConflict409`.
- `validationLedgerTests/Networking/Fixtures/load-action-validation-422.json` — 422 fixture, consumed by `-MockActionValidation422`.
- `validationLedgerTests/Networking/Fixtures/load-action-server-error-500.json` — 500 fixture, consumed by `-MockActionServerError500`.

### Phase 8 contract Phase 10 reuses
- `.planning/phases/08-role-filtered-load-list/08-CONTEXT.md` — D-09/D-10 (skeleton-with-shimmer pattern Phase 9 inherited; Phase 10's action region inherits when the VM is `.loading`). The `LoadListViewController.viewWillAppear → fetchLoads()` pattern (line 381) is the mechanism for success criteria #5 — no new code.
- `validationLedger/UI/Components/VerificationBadgeView.swift` — reused in the tender carrier picker for each carrier's verification state (per D-08). UNCHANGED.
- `validationLedger/UI/Components/LoadStatusBadgeView.swift` — already in use on the detail pinned header (Phase 9). Phase 10 re-uses for the predicted-status rendering during `.actionInFlight`. UNCHANGED.
- `validationLedger/Features/Loads/LoadListViewController.swift` — `viewWillAppear` re-fetch logic at line 381 is what makes list-refresh-on-popback free. UNCHANGED.
- `validationLedger/Features/Loads/LoadListViewModel.swift` — handles the role-scoped re-fetch. UNCHANGED.

### Phase 9 / 9.1 contract Phase 10 extends
- `.planning/phases/09-load-detail-chain-of-trust-graph/09-CONTEXT.md` — D-01/D-02 (iPhone composition; the action region inserts into the body view's vertical stack), D-03 (iPad split — action region in the right pane), D-08 (`UISheetPresentationController` precedent — same modal infrastructure for tender sheet), D-19 (skeleton-with-shimmer for `.loading`), D-20 (3-case VM state machine — Phase 10 evolves this to add `.actionInFlight` / `.actionFailed`), D-21/D-22 (VoiceOver traversal order — Phase 10 must extend the order to include the action region; the tender sheet is its own modal screen with its own a11y model).
- `.planning/phases/09.1-chain-of-vouches-redesign-vertical-attribution-tree-everyone/09.1-CONTEXT.md` — D-01 / D-12 (shared verification color helper and the `-Mock2DTrustGraphOnIPhone` DEBUG-only launch-arg pattern — Phase 10's four toggles mirror the exact pattern: `#if DEBUG`-gated, parsed via `ProcessInfo.arguments.contains(...)`, documented inline with rationale).
- `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` — the host VC. Phase 10 MODIFIES: state-machine render() handles two new cases (`.actionInFlight`, `.actionFailed`); the action region inserts into the body view; the toast banner is a new top-level transient subview presented by the VC on `.actionFailed`. The Phase 9 composition rebuild (CR-02) doesn't need to expand — the action region lives in the body, not as a top-level child.
- `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` — MODIFIED for D-16: new state cases, new action-submission method, predicted-state derivation pure function, BL-01 cancel-and-replace pattern extends to action submission (a new action supersedes an in-flight one).
- `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` — MODIFIED: the action region inserts in the contentStack between `StatusTimelineView` and the freight-detail rows. The body's `accessibilityElements` extends to include the action region.
- `validationLedger/Features/Loads/Detail/StatusTimelineView.swift` — the predicted-state path re-renders the timeline. UNCHANGED structurally; Phase 10 just feeds it different `Load.stateHistory` during predict.
- `validationLedger/Features/Loads/Detail/ChainOfVouchesView.swift` / `EveryoneOnLoadStripView.swift` / `TrustGraphView.swift` — chain-card components that gain the "updating…" overlay during `.actionInFlight`. Implementation may live on the host VC (an overlay subview pinned over the chain region) rather than mutating each chain-card component. Planner discretion.

### v1.0 UIKit precedents Phase 10 mirrors
- `validationLedger/App/AppContainer.swift` lines 218-294 — `makeLoadListScreen(role:)` and `makeLoadDetailScreen(loadID:)`. Phase 10 MODIFIES `makeLoadDetailScreen` to accept `role:` (D-22). The factory closure threading inside `makeLoadListScreen` becomes `{ [weak self] loadID in self?.makeLoadDetailScreen(loadID: loadID, role: role) }`.
- `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift` lines 32, 69, 71, 200, 222 — `-MockKYCStatusVerified` launch-arg precedent; the four Phase 10 toggles mirror this exact shape.
- `validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift` — coordinator pattern. Phase 10 does NOT introduce a new coordinator (the tender sheet is a single modal — `UISheetPresentationController.present`, mirrors Phase 9's verification-basis sheet which also has no coordinator).

### Test infrastructure
- `validationLedgerTests/Support/UIKitSnapshot.swift` — in-house snapshot helper; Phase 10 uses it for action-region snapshots × per-role × per-status, tender sheet snapshots × per-VerificationState combination, toast-banner snapshot.
- `validationLedger/Core/Logging/` — `OSLogLoggerImpl` + `LoggingSubsystem.app` + `feature.loads` category already set up by `AppContainer.makeLoadDetailScreen`. Phase 10's VM uses the same logger for action submission events. `fields: [:]` discipline holds (T-09-04 / T-08-08 — VIEW-LAYER LOCK extends to the new action region; the action region does NOT log).

### Project memories the planner / executor MUST honor
- `gsd-sdk-node16-workaround` — every `gsd-sdk query …` Bash call MUST prefix `NODE_OPTIONS="--require /tmp/structured-clone-polyfill.js"`. Without it the workflow tooling breaks.
- `ios-test-suite-pitfalls` — verification uses the scoped serial simulator-lane (`-skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO`); never bare `xcodebuild test`.
- `mock-kyc-status-verified-toggle` — the launch-arg pattern Phase 10's four toggles mirror.
- `phase-9.1-execution-closeout` — Phase 9.1 R-truths verified; the action region must NOT mount on iPad's iPhone-2D-graph DEBUG fallback path (D-12 in 9.1) any differently than on the default iPhone path.

### Stale — do NOT rely on
- `.planning/codebase/*.md` (all 7 files dated 2026-04-21, "brand-new SwiftUI scaffold") — predates v1.0 entirely. Every prior CONTEXT.md flagged this. The source tree is authoritative.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`RoleLoadPolicy.actions(for:status:)`** (`Core/Load/RoleLoadPolicy.swift`): the SINGLE source of truth for action gating. Phase 10's action region calls this once per `(role, status)` and renders the returned `[LoadAction]` array. The exhaustive unit tests already exist (`RoleLoadPolicyTests`); Phase 10 doesn't add policy tests, only UI tests against the policy's output.
- **`LoadActionEndpoint`** (`Core/Networking/Endpoints/LoadActionEndpoint.swift`): typed POST endpoint; `apiClient.request(LoadActionEndpoint(loadID:action:body:))` returns `Response { load: Load, chainOfTrust: ChainOfTrust }`. Auto-picks up `IdempotencyInterceptor` (D-17 / D-19).
- **`Load.respondByAt`** + **`Load.tenderEligibility`** (`Core/Load/Load.swift`): the data that drives the carrier countdown UI (D-15 indicative — UI-SPEC owns visual) and the ACTION-07 load-level gate (D-09).
- **`VerificationBadgeView`** (`UI/Components/VerificationBadgeView.swift`): reused in the tender carrier picker — every carrier row renders its verification state via this component. Phase 9.1 D-01..D-04 strengthened TRUST-02 via `DS.Colors.Verification.color(for:)` — Phase 10 inherits that lock automatically.
- **`LoadStatusBadgeView`** (`UI/Components/LoadStatusBadgeView.swift`): reused for the predicted-status render during `.actionInFlight`.
- **`UISheetPresentationController` with `.medium` detent**: Phase 9 D-08's modal precedent. Phase 10 uses the same API for the tender sheet — no new presentation infrastructure.
- **`DS.Spacing / DS.Typography / DS.Colors`** (`UI/DesignSystem/`): every spacing, font, and color token already present. The action region, tender sheet, and toast banner consume existing tokens; UI-SPEC 10 may add a small set (toast-banner background, the chain "updating" overlay opacity token, the destructive-button tint formalization) under the existing namespace.
- **`MockURLProtocol` latency / forced-failure injection** (Phase 7 D-14): consumed verbatim by `-MockActionLatencySlow` (latency) and the three failure-fixture toggles. ZERO new test infrastructure.
- **`LoadDetailViewController.composition rebuild safety`** (Phase 9, T-09-11 noted in the file header): the action region lives in the body view, NOT as a top-level child, so the existing composition rebuild path on `traitCollectionDidChange(_:)` doesn't expand.
- **`LoadListViewController.viewWillAppear → fetchLoads()`** (line 381): success criteria #5 (list reflects new state on pop-back) is satisfied by the EXISTING code path. Zero new wiring.
- **`OSLogLoggerImpl + feature.loads category`** (`AppContainer.makeLoadDetailScreen`): the logger the action VM events fire against. `fields: [:]` discipline applies (T-09-04 / T-08-08).

### Established Patterns
- **MVVM + Coordinators** (project-wide): Phase 10 extends the existing `LoadDetailViewModel` (D-16) — no new coordinator, no new VM. The tender sheet's content VC has its own small VM internal to itself for picker/deadline state; the sheet's "Send" tap calls the detail VM's action-submit method.
- **Pure rule resolvers extracted from UIKit**: `RoleLoadPolicy` is the canonical analog for the new predicted-state derivation function (D-16) — a pure `(Load, LoadAction) → Load` function, exhaustively unit-testable without UIKit.
- **Skeleton-with-shimmer for `.loading`** (Phase 8 D-09/D-10, Phase 9 D-19 app-wide pattern): the action region's `.loading` rendering follows this — when the detail VM is `.loading`, the action region renders a small skeleton silhouette in its scroll slot. UI-SPEC owns the silhouette.
- **`UISheetPresentationController` with detents** (iOS 17-native, deployment min): Phase 9 D-08 precedent; Phase 10 uses identical infrastructure for the tender sheet.
- **`#if DEBUG`-gated launch arguments via `ProcessInfo.processInfo.arguments.contains(...)`** (Phase 5 `-MockKYCStatusVerified` / Phase 9.1 `-Mock2DTrustGraphOnIPhone`): Phase 10's four toggles follow this exact pattern.
- **`.convertFromSnakeCase` + explicit `CodingKeys` only for trailing-acronym fields** (Phase 7 D-19): `LoadActionEndpoint.RequestBody.CodingKeys` already has `targetPartyID = "targetPartyId"`. Phase 10 doesn't add any new wire fields; the existing CodingKeys cover the tender payload.
- **44pt touch-target floor** (UI-SPEC universal): every action button, every carrier row in the picker, the deadline chips, the Send button, the toast-banner dismiss target — all 44pt minimum.
- **Composed `accessibilityLabel` applied externally** (Phase 9 D-22, Phase 9.1 leaf-element model): the action region's individual buttons get their own composed labels (e.g. "Tender, button" / "Accept tender, button, disabled" when in-flight); the tender sheet's picker rows compose role + display name + verification state into a single label.
- **Cancel-and-replace task lifecycle** (Phase 8 / Phase 9 BL-01 — `LoadListViewModel.fetchLoads` / `LoadDetailViewModel.fetchLoadDetail`): Phase 10's action-submission method follows the same shape — a fresh action call cancels any in-flight one (rare but possible if the optimistic-predict landed and another action quickly arrived; serves as an invariant guard, not a feature).
- **Zero-PII discipline** (T-09-04 / T-08-08 view-layer lock): the action region renders only localized fixed copy; the toast banner renders only localized fixed copy; logger calls in the VM use `fields: [:]`; the predicted-state derivation reads `Load.respondByAt` etc. but emits NO derived state into logs.

### Integration Points
- **NEW file:** `validationLedger/Features/Loads/Detail/LoadActionsView.swift` — the action region container, mounted in `LoadDetailBodyView` between the status timeline and the freight detail rows. Pure presentation; the action set is computed externally (via `RoleLoadPolicy`) and passed in.
- **NEW file(s):** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift` (+ subviews if the planner chooses to split) — the modal sheet hosting carrier picker + deadline picker.
- **NEW file:** `validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift` (or similar) — the top-of-screen transient banner that slides in on `.actionFailed`. May live on the VC or as a sibling helper; planner decides.
- **NEW file:** `validationLedger/Core/Load/LoadActionPredictor.swift` (or `Core/Load/PredictedLoadStateBuilder.swift`) — the pure `(currentLoad: Load, action: LoadAction, payload: LoadActionEndpoint.RequestBody?) → predicted: Load` resolver. Exhaustively unit-testable. Mirror of `RoleLoadPolicy` shape (a `public enum` namespace).
- **NEW endpoint:** `validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift` (indicative — planner finalizes name/path) — `GET /carriers/directory` returning `[TrustNode]` (or wrapped envelope). Drives the tender carrier picker.
- **NEW fixture:** `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` — the static demo carrier list (D-07).
- **MODIFIED:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — adds (a) the carrier-directory handler and (b) four DEBUG-gated branches in front of the action-success handler that intercept when `-MockActionConflict409 / -MockActionValidation422 / -MockActionServerError500` is set. The default success handler is unchanged.
- **MODIFIED:** `validationLedger/App/AppContainer.swift` — `makeLoadDetailScreen(loadID:)` → `makeLoadDetailScreen(loadID:role:)` (D-22); the factory closure in `makeLoadListScreen(role:)` (lines 255-258) passes the captured `role` through.
- **MODIFIED:** `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` — new state cases (`.actionInFlight`, `.actionFailed`) per D-16; new action-submission method `submit(action:body:) async`; cancel-and-replace lifecycle for actions.
- **MODIFIED:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` — render() handles two new states (in-flight + failed); the action region inserts into the body view's content stack; the toast banner is a new top-level transient subview; the chain "updating…" overlay is a new pinnable subview over the chain region.
- **MODIFIED:** `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` — the action region inserts in the contentStack between `StatusTimelineView` and the freight-detail rows; `accessibilityElements` extends.
- **MODIFIED (tests):** Phase 10 adds tests under `validationLedgerTests/Loads/` — predictor unit tests (every `(Load, LoadAction)` combination across the policy), action-region snapshot tests (5 roles × representative statuses), tender sheet snapshot tests (per-VerificationState picker states), VM state-machine tests (predict → 200 → loaded; predict → error → rollback), action-failure-toggle integration tests (each of the 4 DEBUG flags triggers the right code path). Under `validationLedgerUITests/`: smoke flows for each action × role combination, with at least one rollback flow using `-MockActionValidation422 -MockActionLatencySlow`.

</code_context>

<specifics>
## Specific Ideas

- **The action region is where the platform thesis MEETS the user — not just where they tap buttons.** ACTION-07's "visible-but-disabled-with-reason" carrier rendering (D-08) and the load-level `tenderEligibility.disabledReason` inline copy (D-09) are the two surfaces where "identity that cannot be spoofed" becomes a UX moment. Both surfaces should be implemented with the same care Phase 9's chain-of-trust card received — not as a quick "set isEnabled = false" treatment. The carrier picker is where most brokers will FIRST encounter "I cannot tender to this party."

- **The static demo carrier directory is a product surface, not just a fixture.** The ~6-8 carriers should cross-reference Phase 7's named-load library where possible — e.g. include "Chameleon Cargo" (or whatever the planner names it) as the flagged-verification-state row, so the picker visibly shows the chameleon-carrier fraud archetype any time a broker opens it. The same archetype-as-UX work that Phase 7 did for the named loads (D-13) extends here to the directory.

- **The optimistic predict + chain "updating…" overlay is a TRUST POSTURE choice, not just a perf choice.** D-13 explicitly excludes the chain from prediction because predicting trust is exactly the thing the platform doesn't do. The overlay surfaces this honestly: "the load state is mine to predict; the chain is the server's to confirm." Anyone reading this context who's tempted to "just optimize one round-trip away" by predicting a simple chain delta (e.g. flipping an edge's `relationshipState`) should re-read this section. The cost of getting the prediction wrong is "we showed verified-looking state that wasn't," which is exactly the platform's enemy.

- **`-MockActionLatencySlow` is for human-eye verification on real hardware**, not for automated tests. Unit and UI tests should NOT enable the latency toggle — they should use the immediate-response success/failure fixtures so the test suite stays fast. The latency toggle is for the device-UAT walk-through where a human needs to SEE the predicted state and feel the rollback. The two QA disciplines are separate.

- **The role propagation gap (D-22) is the structural surprise of Phase 10.** Nothing in Phase 9 needed the role at the detail level — the detail screen just renders. Phase 10 changes that. The fix is mechanical but it changes the factory signature, which cascades through one call site (the closure in `makeLoadListScreen`). The planner should land it as part of the SAME plan that introduces the action region — separating it would create a window where the detail VC has `role:` plumbed but no consumer.

- **Phase 7 D-04 (no `retender` LoadAction case) plays out at the UI in a specific way:** when the carrier rejects a tender, the load goes from `.tendered → .rejected`, then back to `.posted` (eventually, via server side-effect or timer). During `.rejected` the broker sees `[.tender, .cancel]` (per `RoleLoadPolicy`); when the broker taps Tender, the same modal sheet opens (D-06). There is NO separate "re-tender" UX — the planner should verify the predicted-state derivation handles `.tender on .rejected → predicted .tendered` exactly the same as `.tender on .posted`.

</specifics>

<deferred>
## Deferred Ideas

- **Stable-idempotency-key replay for retry-on-failure** — D-17 explicitly defers. The UI guard (buttons disable during in-flight) prevents user-driven double-submit; stable-key replay only matters when a real backend can dedupe across retries. Post-v1.1 follow-up if real backend integration requires it.

- **Push-from-detail observer for instantaneous list refresh on pop-back** — D-18 chose the simpler `viewWillAppear` re-fetch. If a future milestone needs <100ms list refresh after action, a NotificationCenter (or a shared observable load-cache) can be added additively.

- **Live-updating respond-by countdown for the carrier/dispatch view** — Claude's Discretion notes static "Respond by Tomorrow 5:00 PM" vs. live "2h 13m left" is UI-SPEC's call. A live countdown needs a `Timer` and re-render cadence; UI-SPEC 10 decides whether v1.1 ships the live variant or the static one. Either way, the data source (`Load.respondByAt`) is locked.

- **Multi-field load-creation form for `.post` (Shipper/Broker)** — explicitly deferred to LOAD-F1 (post-v1.1). v1.1's `.post` acts on pre-existing draft fixtures.

- **Tap-on-tender-sheet-carrier-row to push a verification-basis sheet** — the verification badge in the picker is currently render-only. If product wants "tap the badge to see why this carrier is unverified," scope a follow-up. The existing `VerificationBasisSheetViewController` (Phase 9) could be reused.

- **Audit-history surface for prior tenders / rejections / expiries on a single load** — Phase 9 D-18 deferred this; Phase 10 honors the deferral. `Load.stateHistory` contains the data, but the timeline only renders the primary-lifecycle 6-pill stepper (not side-states). A "see history" sheet is a future surface.

- **Inline note field on actions** — `LoadActionEndpoint.RequestBody.note` exists on the wire (Phase 7 D-19); v1.1 UIs do NOT collect a note. Adding a note field to one or more action sheets is a small additive surface that some freight workflows want (e.g. "rejecting because vehicle in shop"). Scope a follow-up when product asks.

- **Real backend tender / accept / reject — replace MockURLProtocol** — explicitly deferred to a post-v1.1 milestone (PROJECT.md Out of Scope; needs the running backend that the iOS project is intentionally decoupled from).

- **Push notification on tender received / tender response received** — RT-02 in the deferred-future-requirements. v1.1 stays pull-only.

- **Background tender expiry handling on the client** — if a load's `respondByAt` passes while the user has the screen open, the screen could auto-transition to `.expired` without a fresh server poll. Deferred — the screen re-fetches on `viewWillAppear` (and could in a future iteration poll periodically) but a client-side "the deadline just passed" trigger is post-v1.1.

- **Per-action toast taxonomy vs. single generic toast copy** — Claude's Discretion (D-15 indicative gives a per-action list of localization keys; UI-SPEC 10 may consolidate to a single key with action-name interpolation). Deferred to UI-SPEC.

### Reviewed Todos (not folded)

- **`device-ci-biometric-infra.md`** — v1.0 physical-device-CI infrastructure todo (the Face ID prompt that hangs the device-CI lane). Matched on generic keywords; unrelated to a per-role action surface. **Not folded** — fifth consecutive review (Phases 7, 8, 9, 9.1, 10). Remains a carried v1.0 infrastructure item, separate track.

</deferred>

---

*Phase: 10-per-role-tender-accept-reject*
*Context gathered: 2026-05-21*
