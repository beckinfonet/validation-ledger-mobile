# Phase 10: Per-Role Tender / Accept / Reject — Research

**Researched:** 2026-05-21
**Domain:** UIKit per-role action surface on a load detail screen — `RoleLoadPolicy`-driven action bar, modal tender sheet with verified-counterparty picker, optimistic-UI with rollback, idempotency-interceptor-routed mutations, DEBUG-only failure-injection toggles, exhaustive `(Role × LoadStatus)` snapshot coverage.
**Confidence:** HIGH (every contract Phase 10 reads — `RoleLoadPolicy`, `LoadAction`, `LoadActionEndpoint`, `IdempotencyInterceptor`, `MockLoadFixtureRegistry`, `UIKitSnapshot`, the `-Mock…` launch-arg pattern — was verified by direct file read against the source tree, not assumed.)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

All 23 decisions D-01..D-23 from `10-CONTEXT.md` are locked. Summary (planner must read CONTEXT.md verbatim — this is a high-level index):

- **Action-bar composition (D-01..D-05):** Action region mounted INSIDE `LoadDetailBodyView.contentStack` at index 2 (between timeline and freight rows). Side-by-side equal-width buttons (`UIStackView` `.fillEqually`). Destructive (`.reject`, `.cancel`) gets red tint. Empty state renders a tasteful centered caption (Factoring view-only / terminal status) — region stays present, never collapses. iPad: action region lives in the right pane immediately after timeline.
- **Tender flow UX (D-06..D-11):** `UISheetPresentationController.medium` detent. Carrier list = static `/carriers/directory` fixture (~6-8 carriers spanning `VerificationState` cases). Unverified/flagged carriers visible-but-disabled in the picker with inline reason. Independent load-level ACTION-07 gate uses `Load.tenderEligibility.canTender` + `disabledReason`. Deadline = chip preset (1h/4h/24h/48h/Custom…) with default 24h.
- **Optimistic UI semantics (D-12..D-18):** WHOLE load predicts forward on tap; chain-of-trust NEVER predicted (it gets an "updating…" overlay). 200 → swap to `response.load + response.chainOfTrust`. Error → unwind + top toast banner with GENERIC localized copy (NEVER server text). VM ownership: extend existing `LoadDetailViewModel` — NOT a separate action VM. Buttons disable for `.actionInFlight` (combined with `IdempotencyInterceptor`'s automatic `Idempotency-Key` UUID — D-17). List refresh on pop-back uses Phase 8's existing `viewWillAppear → fetchLoads()` — zero new wiring.
- **Failure-path DEBUG toggles (D-19..D-21):** Four `#if DEBUG`-gated launch args: `-MockActionConflict409`, `-MockActionValidation422`, `-MockActionServerError500`, `-MockActionLatencySlow`. Same shape as `-MockKYCStatusVerified` / `-Mock2DTrustGraphOnIPhone`. Default success handler unchanged.
- **Role propagation (D-22..D-23):** `AppContainer.makeLoadDetailScreen(loadID:)` becomes `makeLoadDetailScreen(loadID:role:)`. Role threaded through the factory closure `LoadListViewController` already captures. Role not client-changeable on the detail screen.

### Claude's Discretion

The planner / UI-researcher may finalize without re-asking the user (CONTEXT.md § Claude's Discretion):
- Exact `LoadActionsView` class structure (separate file vs. extension on `LoadDetailBodyView`).
- Exact `TenderSheetViewController` file partitioning.
- Exact carrier-directory endpoint path + envelope shape.
- Carrier-directory fixture exact list (cross-reference Phase 7's named-load fraud archetypes).
- Exact respond-by countdown UI for carrier/dispatch on `.tendered` — UI-SPEC chose static "Respond by Tomorrow 5:00 PM"; live counter deferred.
- Exact toast banner taxonomy — UI-SPEC chose 6 per-action keys.
- Exact predicted-state derivation (pure function `(Load, LoadAction, RequestBody) -> Load`).
- Exact chain-overlay visual (UI-SPEC: 0.6 alpha on `DS.Colors.surface`).
- Exact destructive-button tint (UI-SPEC: `DS.Colors.destructive` = `.systemRed`).
- Exact mock-toggle precedence in `MockLoadFixtureRegistry`.
- Exact `-MockActionLatencySlow` interval (UI-SPEC indicative: ~1.5s).
- Localization keys (UI-SPEC owns canonical namespace).
- VM state-enum exact case shape (D-16 indicative).
- Exact XCUITest coverage matrix.

### Deferred Ideas (OUT OF SCOPE)

- Stable-idempotency-key replay for retry-on-failure (post-v1.1; v1.1 ships fresh UUID per request).
- Push-from-detail observer for sub-100ms list refresh.
- Live-updating respond-by countdown.
- Multi-field load-creation form (LOAD-F1).
- Tap-on-tender-sheet-carrier-row to push verification-basis sheet.
- Audit-history sheet for prior tenders.
- Inline note field on actions (`LoadActionEndpoint.RequestBody.note` exists; v1.1 leaves it nil).
- Real backend tender/accept/reject (BE-01).
- Push notification on tender received (RT-02).
- Background tender expiry handling on the client.
- Per-action toast taxonomy vs. single generic — UI-SPEC chose per-action 6 keys (not deferred — locked at UI-SPEC).
- `.cancel` confirmation alert (documented gap; v1.1 ships tap-and-go).
</user_constraints>

## Project Constraints (from CLAUDE.md)

Treat with the same authority as locked decisions:

- **UIKit-first for sensitive surfaces.** Every action button, the tender sheet, the toast banner, the chain overlay are UIKit. SwiftUI is forbidden on this entire phase's surface area (the action region is critical-class — a misfire on Tender is a fraud vector). `required init?(coder:)` traps everywhere; programmatic constructors only.
- **iOS 17.0 minimum deployment.** `UISheetPresentationController` (.medium / .large detents), `UIDatePicker.compact`, `UIButton.Configuration`, `UIContentSizeCategory.isAccessibilityCategory`, `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator` — all iOS 17-native.
- **SPM-only, pre-approved shortlist.** ZERO new dependencies in Phase 10. The toast banner is hand-rolled (`UIView.animate` + `transform` + `alpha`); no SnackBar / Toast-Swift import. Snapshot tests use the existing `UIKitSnapshot` helper.
- **Zero PII in analytics or crash logs.** `feature.loads` category logger, `fields: [:]` discipline. Server-supplied error text NEVER reaches the screen (D-15 / T-09-04 view-layer lock). The one DOCUMENTED exception: `Load.tenderEligibility.disabledReason` is server-supplied and rendered verbatim because it is load-state metadata (loaded with the load), not an error-response payload.
- **Zero `switch load.status` in any view controller or cell** (ROADMAP §Phase 10 lock). All action gating flows from `RoleLoadPolicy.actions(for:status:)`. **Documented exception:** the `.advanceStatus` button-title resolver (`nextStatus(from: LoadStatus) -> LoadStatus?`) reads `LoadStatus` to produce the localized title ("Dispatch" / "Mark in transit" / "Mark delivered"). The GATE stays with `RoleLoadPolicy`; the title computation runs only after the gate opens. This is UI-SPEC-sanctioned and must be in a pure helper, NOT inline in the action region.
- **iPad must render natively** (not just scale). The action region lives in the right pane on iPad regular; no spanning bottom bar, no floating overlay on the graph.
- **44pt touch-target floor everywhere.** Action buttons are 50pt min (Dynamic Type + `DS.Typography.headline`). Toast banner is 56pt min. Disabled controls retain hit area so VoiceOver reads the disabled reason.
- **AI traffic: not applicable to Phase 10** — no Claude calls in this surface.

## Project Skills

`.claude/skills/`, `.agents/skills/` — none present. No project skills to consume.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACTION-01 | Broker/Shipper can tender a load; active tender displays respond-by deadline | `LoadActionsView` renders `[.tender, .cancel]` for `(.broker/.shipper, .posted)` per `RoleLoadPolicy`. `TenderSheetViewController` collects `targetPartyID + respondByAt`. `Load.respondByAt` drives the carrier/dispatch countdown UI on `.tendered`. |
| ACTION-02 | Broker/Shipper can retender after reject/expired | `RoleLoadPolicy.actions(.broker, .rejected) == [.tender, .cancel]` (same for `.expired`). NO `retender` LoadAction case — same Tender button reuses the same `TenderSheetViewController` (Phase 7 D-04). Predictor must handle `tender on .rejected → predicted .tendered` identically to `tender on .posted`. |
| ACTION-03 | Carrier/Dispatch can accept a tendered load | `RoleLoadPolicy.actions(.carrier, .tendered) == [.accept, .reject]`. Tap-and-go optimistic predict → `LoadAction.accept`. |
| ACTION-04 | Carrier/Dispatch can reject — load returns to posted | `RoleLoadPolicy.actions(.carrier, .tendered) == [.accept, .reject]`. The PREDICTED state for `reject on .tendered` is `.rejected` (server may return `.posted` directly per Phase 7 D-04 — predictor sketches both; planner picks the right convention via the action-success fixture). Server-supplied `response.load.status` is authoritative on 200. |
| ACTION-05 | Carrier/Dispatch can advance status one step | Single `.advanceStatus` LoadAction case (Phase 7 D-05). `RoleLoadPolicy.actions(.carrier, .accepted/.dispatched/.inTransit) == [.advanceStatus]`. Button title computed via pure `nextStatus(from:)` helper. Predicted forward: `.accepted → .dispatched`, `.dispatched → .inTransit`, `.inTransit → .delivered`. |
| ACTION-06 | Shipper/Broker can post a draft, cancel a pre-delivery load | `RoleLoadPolicy.actions(.broker, .draft) == [.post]`; `.cancel` available on `.draft/.posted/.tendered/.accepted/.dispatched/.inTransit/.rejected/.expired`. NO multi-field create form — `.post` acts on existing fixture drafts (UI-SPEC). |
| ACTION-07 | Cannot tender to an unverified counterparty — hard-disabled with inline reason | TWO gates (D-08 / D-09): load-level via `Load.tenderEligibility.canTender` + `disabledReason` (the Tender BUTTON is hard-disabled before the sheet opens); carrier-level inside the picker (unverified/flagged/pending carriers visible-but-disabled with localized reason — `loads.detail.tender.carrier.disabled.{state}`). Both server-driven (Phase 7 D-18). |
| ACTION-08 | Optimistic UI with rollback — screen reverts + shows error on (mocked) failure | VM state machine adds `.actionInFlight(predicted, frozenChain, action)` and `.actionFailed(rollbackTo, frozenChain, errorCopyKey)` per D-16. Predictor is a pure `(Load, LoadAction, RequestBody?) -> Load` function (mirror of `RoleLoadPolicy`). Failure path: VM transitions back to pre-tap `.loaded(load, chain)`, VC slides in `LoadActionToastBannerView`. Server text NEVER rendered (D-15 / T-09-04). |
| ACTION-09 | Available actions determined per-role by single `RoleLoadPolicy` — Factoring sees none | `RoleLoadPolicy.actions(for:status:)` is the ONLY action source. Factoring renders empty-state caption `loads.actions.empty.factoring`. Plan must include the 5×13 = 65 `(Role × LoadStatus)` snapshot matrix as the verification gate (UI-SPEC line 537). |
</phase_requirements>

## Summary

Phase 10 is unusual: the "what" is fully decided (CONTEXT.md = 23 locked decisions; UI-SPEC.md = the complete pixel-and-token contract). The research focus shifts entirely to the **"how"** — verifying that the Phase 7 contracts the action surface reads from are exactly the shape the planner needs, mapping the precise files the planner will modify, identifying the half-dozen reusable patterns (cancel-and-replace task lifecycle, snapshot helper, launch-arg parsing, `UISheetPresentationController` recipe, MockURLProtocol `register` shape, `viewWillAppear`-driven pop-back refresh), and surfacing the small set of structural gaps that are non-obvious — chiefly the `AppContainer.makeLoadDetailScreen` role-propagation gap, the predictor pure function as the unit-testable rollback foundation, and the 65-cell snapshot matrix as the gate that `RoleLoadPolicy` and the UI never drift.

Every Phase 7 contract Phase 10 reads has been confirmed in source (not assumed):

- `RoleLoadPolicy.actions(for:status:)` is a single-source nested-switch resolver — every entry was inspected in `validationLedger/Core/Load/RoleLoadPolicy.swift`. The truth table the action region renders is exactly the table in UI-SPEC § Per-Action State / Visibility Matrix.
- `LoadActionEndpoint` already returns `{ load: Load, chainOfTrust: ChainOfTrust }` — symmetric with `LoadDetailEndpoint`, so the success path swap is a single VM assignment.
- `IdempotencyInterceptor` (`validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift`) automatically injects `Idempotency-Key: UUID().uuidString` on every POST/PUT and is already in `apiClient.requestInterceptors` (AppContainer.swift:476 per the file header). ZERO new wiring; the v1.0 idempotency-interceptor checklist item from ROADMAP §Phase 10 is satisfied by the existing infrastructure.
- `MockLoadFixtureRegistry`'s action handler at line 154 returns `load-action-success.json` for every action. The four DEBUG toggles slot in as additional `MockURLProtocol.register { … }` handlers registered BEFORE the success handler (first-match-wins ordering — confirmed by reading the file).
- `LoadListViewController.viewWillAppear` (line 381) already calls `viewModel.fetchLoads()` — success criterion #5 is satisfied with zero new code.
- `UIKitSnapshot.image(of:size:)` (`validationLedgerTests/Support/UIKitSnapshot.swift`) is the in-house snapshot helper Phases 8 / 9 / 9.1 use; Phase 10 consumes it for the 65-cell matrix.
- The `-MockKYCStatusVerified` precedent (`MockDefaultFixtures.swift:60-76`) and `-Mock2DTrustGraphOnIPhone` precedent (`LoadDetailViewController.swift:98-131`) give the exact `#if DEBUG` + `ProcessInfo.processInfo.arguments.contains(...)` shape for the four new toggles.

**Primary recommendation:** The plan should land in 5 waves — a foundation wave that adds the pure predictor function + extends `LoadDetailViewModel` + threads role through `AppContainer.makeLoadDetailScreen`; a wave that builds `LoadActionsView` + the empty-state caption + the disabled-reason inline label; a wave for `TenderSheetViewController` + `CarrierDirectoryEndpoint` + the fixture + the carrier-directory mock handler; a wave for the toast banner + chain "updating…" overlay + the four DEBUG toggle handlers in `MockLoadFixtureRegistry`; and a final test-only wave that lands the 65-cell snapshot matrix + per-state XCUITest smoke flows. The role-propagation fix (D-22) ships in wave 1 of the action region (NOT separated) so there is no window where `LoadDetailVC` has `role:` plumbed but no consumer.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Action gating (which buttons appear for a role on a load state) | Domain Kernel (`Core/Load/RoleLoadPolicy.swift`) | View (`LoadActionsView` renders the policy's output) | Single source of truth. Zero `switch load.status` in views (ROADMAP lock). |
| Predicted-state derivation (forward state machine: `(Load, LoadAction, RequestBody?) -> Load`) | Domain Kernel (NEW `Core/Load/LoadActionPredictor.swift`) | VM (consumes it on `submit(action:)`) | Pure function — exhaustively unit-testable without UIKit. Mirrors `RoleLoadPolicy` shape. |
| Action submission + state machine (`.loading → .loaded → .actionInFlight → .loaded/.actionFailed`) | VM (`LoadDetailViewModel`) | VC (`render(state:)` toggles `isHidden` + overlays) | One VM owns the screen's state per D-16; no separate `LoadActionViewModel` (avoids back-channel coupling). |
| Idempotency-key injection on every action POST | Networking (`IdempotencyInterceptor`, already wired) | — | Zero new wiring. Auto-injects fresh UUID per request per `IdempotencyInterceptor.intercept(_:)`. |
| Server-supplied action response fixture (success/409/422/500/latency) | Mock layer (`MockLoadFixtureRegistry` + per-toggle handlers) | DEBUG-only launch args (`ProcessInfo.processInfo.arguments`) | Failure-path UAT exercise lives in DEBUG; Release ships only the success handler. |
| Carrier-directory list (the tender picker's data source) | NEW endpoint `CarrierDirectoryEndpoint` + NEW fixture | Mock registry handler | Cannot be sourced from `ChainOfTrust.nodes` (a `.posted` load may have no carrier yet — the canonical happy path). |
| Tender modal — picker UX + deadline UX + Send | View (`TenderSheetViewController`) + internal sheet VM for picker/deadline state | Parent VC (presents the sheet, owns the action submission) | Sheet is content-only; submission flows back through the parent's VM (`submit(action: .tender, body:)`). |
| Optimistic UI orchestration (chain overlay, toast banner, button in-flight visuals) | VC (`LoadDetailViewController.render(state:)`) | View components (`LoadActionToastBannerView`, chain overlay subview, action button spinner) | VC mounts transient overlays + banner over the body; subviews stay purely presentational. |
| List pop-back reconciliation | VC (`LoadListViewController.viewWillAppear`) | VM (`fetchLoads()`) | EXISTING code path — zero new wiring. |
| Role propagation (List VC → Detail VC → Detail VM → endpoint body) | Composition root (`AppContainer.makeLoadDetailScreen`) | Factory closure threaded in `makeLoadListScreen(role:)` | Structural gap closed by D-22; one factory-signature change cascades through one call site. |

## Standard Stack

ZERO new external dependencies. Every library and API used is iOS-bundled. The "stack" for Phase 10 is the curated set of system APIs:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| UIKit | iOS 17 SDK | All VCs, views, gestures, animations | CLAUDE.md UIKit-first mandate; sensitive surface |
| Foundation | iOS 17 SDK | `Decimal`, `Date`, `UUID`, `ProcessInfo`, `NSLocalizedString`, `DateFormatter` | Standard library |
| Swift Concurrency | Swift 5.9+ | `Task`, `async/await`, `Task.isCancelled`, `@MainActor` | Already pervasive in `LoadDetailViewModel` |

### Supporting iOS APIs
| API | iOS Min | Purpose | Phase 10 Usage |
|-----|---------|---------|----------------|
| `UISheetPresentationController` | iOS 15 | Modal sheet with detents | `TenderSheetViewController`; same recipe Phase 9 D-08 uses |
| `UIButton.Configuration` | iOS 15 | Filled / bordered / tinted button styles, automatic disabled treatment | Every action button + Send + Cancel + deadline chips |
| `UIStackView` (`.fillEqually`, axis toggle) | iOS 9 (constants iOS 11) | Equal-width button row + Dynamic-Type axis flip | `LoadActionsView` button row + tender sheet content layout |
| `UIActivityIndicatorView` (`.medium`) | iOS 13 | In-flight spinner over action button title + chain overlay center | Spinner pattern Phase 9 uses (skeleton-shimmer is different) |
| `UIDatePicker` (`.compact` style, `.dateAndTime` mode) | iOS 14 | Custom deadline picker | UI-SPEC D-10 |
| `UIImpactFeedbackGenerator` (.medium) | iOS 10 | Haptic on toast slide-in | UI-SPEC |
| `UISelectionFeedbackGenerator` | iOS 10 | Haptic on deadline chip select | UI-SPEC |
| `UITableView` (`.insetGrouped`) | iOS 13 | Tender sheet carrier list | UI-SPEC |
| `UIAccessibility.post(notification: .announcement, argument:)` | iOS 11 | VoiceOver toast announcement | UI-SPEC § Accessibility |
| `traitCollectionDidChange(_:)` | iOS 8 | Dynamic Type axis flip; iPhone↔iPad composition rebuild | Phase 9 precedent (LoadDetailVC) |

### Alternatives Considered
| Instead of | Could Use | Why Rejected |
|------------|-----------|--------------|
| Hand-rolled toast banner (`UIView.animate` + `transform`) | `SnackBar.swift` / Toast-Swift / similar SPM package | CLAUDE.md pre-approved-shortlist — no new dep; toast geometry is trivial (~80 lines per UI-SPEC component-geometry table) |
| `UISheetPresentationController` for tender modal | Full-screen modal VC, custom modal transition, popover | iOS 17-native, Phase 9 precedent, retains parent context (largestUndimmedDetentIdentifier = .medium) |
| Pure local predictor function | Server round-trip without optimistic UI | UI-SPEC D-12 explicitly requires optimistic predict for snappy taps |
| Separate `LoadActionViewModel` | Extended `LoadDetailViewModel` | D-16: separate VM would need back-channel to detail VM for chain swap on success — no isolation benefit, real coupling cost |
| `swift-snapshot-testing` SPM package | In-house `UIKitSnapshot` helper | Phase 8 already shipped `UIKitSnapshot.image(of:size:)`; 65-cell matrix doesn't need a library |
| `Combine` for state propagation | Closure-based `onStateChange: ((State) -> Void)?` | EXISTING `LoadDetailViewModel` pattern (closure callback per D-20); no `Combine` precedent in this VC family |

**Installation:**
No new packages. Zero SPM additions.

## Package Legitimacy Audit

> NOT APPLICABLE — Phase 10 installs ZERO new external packages. Every Swift/UIKit API consumed is iOS 17 SDK-bundled (verified by direct file read against the source tree). The `UIKitSnapshot` snapshot helper is in-house at `validationLedgerTests/Support/UIKitSnapshot.swift` (read line-by-line). No PyPI / npm / crates verification is meaningful for a pure-Swift / iOS-SDK phase.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────┐
                    │ LoadListViewController                      │
                    │  (Phase 8 — UNCHANGED structurally)          │
                    │   • detailScreenFactory(loadID) → push       │
                    │   • viewWillAppear → fetchLoads()            │  ← Pop-back reconciliation
                    │     (success criterion #5 — free)            │
                    └─────────────────────────┬───────────────────┘
                                              │ pushViewController
                                              ▼
                    ┌──────────────────────────────────────────────┐
                    │ LoadDetailViewController (MODIFIED)          │
                    │  • render(state:) handles 2 new VM states:   │
                    │     .actionInFlight, .actionFailed           │
                    │  • Mounts LoadActionsView in body            │
                    │  • Presents TenderSheetViewController        │
                    │  • Presents LoadActionToastBannerView        │
                    │  • Mounts chain "updating…" overlay          │
                    └─────────┬────────────────────┬───────────────┘
                              │                    │
                              ▼                    ▼
        ┌──────────────────────────────┐  ┌──────────────────────────┐
        │ LoadDetailViewModel          │  │ LoadActionsView          │
        │  (MODIFIED — D-16)           │  │  (NEW)                   │
        │                              │  │   • Renders the result   │
        │  State:                      │  │     of RoleLoadPolicy    │
        │   .loading                   │  │     .actions(for:status:)│
        │   .loaded(Load, Chain)       │  │   • N equal-width buttons│
        │   .actionInFlight(           │  │   • Empty-state caption  │
        │      predicted, frozenChain, │  │   • Disabled-reason label│
        │      action)                 │  │     (ACTION-07 load-level│
        │   .actionFailed(             │  │     gate via tender      │
        │      rollbackTo, frozenChain,│  │     Eligibility)         │
        │      errorCopyKey)           │  └──────────┬───────────────┘
        │   .error(message)            │             │ button tap
        │                              │             │
        │  Methods:                    │◀────────────┘
        │   • fetchLoadDetail() async  │
        │   • submit(action:body:) async│
        │                              │
        │  Reads:                      │
        │   • role: Role  ← D-22       │
        │   • RoleLoadPolicy.actions   │
        │   • LoadActionPredictor      │
        │                              │
        │  Cancel-and-replace lifecycle│
        │  (BL-01) extends to actions  │
        └──────────────┬───────────────┘
                       │ apiClient.request(LoadActionEndpoint(…))
                       ▼
        ┌──────────────────────────────────────────────────────────┐
        │ APIClient + IdempotencyInterceptor (UNCHANGED — Phase 2) │
        │  • Auto-injects Idempotency-Key: <UUID> on POST          │
        │  • Routes through MockURLProtocol (DEBUG)                │
        └──────────────────────────────┬───────────────────────────┘
                                       ▼
        ┌──────────────────────────────────────────────────────────┐
        │ MockLoadFixtureRegistry (MODIFIED — adds 4 DEBUG handlers│
        │  + 1 carrier-directory handler)                          │
        │                                                          │
        │  Registration order (first-match-wins):                  │
        │   1. -MockActionConflict409   → load-action-conflict-409 │
        │   2. -MockActionValidation422 → load-action-validation…  │
        │   3. -MockActionServerError500 → load-action-server-…    │
        │   4. -MockActionLatencySlow   → delay then success       │
        │   5. Default action handler   → load-action-success.json │
        │   6. NEW: GET /carriers/directory → tender-carrier-…json │
        └──────────────────────────────────────────────────────────┘

Tender flow inset (broker taps Tender):

   LoadActionsView ─[Tender tap]─▶ LoadDetailViewController
                                         │
                                         ▼ present(TenderSheetVC, animated:)
                                   TenderSheetViewController (NEW)
                                         │
                                         │ on viewDidLoad:
                                         │   apiClient.request(CarrierDirectoryEndpoint())
                                         │
                                         │ user picks verified carrier + deadline + taps Send
                                         │
                                         ▼ closure callback to parent VC
                                   LoadDetailViewModel.submit(
                                     action: .tender,
                                     body: RequestBody(actorRole: role,
                                                       targetPartyID: carrier.partyID,
                                                       respondByAt: resolvedDate,
                                                       note: nil))
                                         │
                                         ▼
                                   .actionInFlight(predicted, frozenChain, .tender)
                                         │
                                         ▼ APIClient → Mock → 200 / 4xx / 5xx
                                         │
                              ┌──────────┴──────────┐
                              │                     │
                              ▼ 200                 ▼ 4xx/5xx
                .loaded(response.load,      .actionFailed(rollbackTo: preLoad,
                        response.chainOfTrust)                frozenChain: preChain,
                              │                      errorCopyKey: "loads.actions.error.tender_failed")
                              │                              │
                              │                              ▼
                       Sheet dismisses                 Toast slides in
                       Chain overlay fades             Sheet stays visible
                                                       Spinner removes; Send re-enables
```

### Recommended Project Structure (additions / modifications only)

```
validationLedger/
├── App/
│   └── AppContainer.swift                            [MODIFIED — makeLoadDetailScreen(loadID:role:)]
├── Core/
│   ├── Load/
│   │   └── LoadActionPredictor.swift                 [NEW — pure (Load, LoadAction, RequestBody?) -> Load]
│   └── Networking/
│       ├── Endpoints/
│       │   └── CarrierDirectoryEndpoint.swift        [NEW — GET /carriers/directory]
│       └── Mock/
│           └── MockLoadFixtureRegistry.swift         [MODIFIED — +4 toggle handlers, +1 directory handler]
└── Features/
    └── Loads/
        ├── LoadListViewController.swift              [UNCHANGED — pop-back refresh free]
        └── Detail/
            ├── LoadActionsView.swift                  [NEW — action region container]
            ├── LoadActionToastBannerView.swift        [NEW — top-anchored failure banner]
            ├── TenderSheetViewController.swift        [NEW — modal sheet with picker + deadline]
            ├── TenderSheetCarrierRowView.swift        [NEW — table-row cell composition (optional split)]
            ├── LoadDetailViewController.swift         [MODIFIED — render .actionInFlight/.actionFailed]
            ├── LoadDetailViewModel.swift              [MODIFIED — +State cases, +submit method, +role]
            └── LoadDetailBodyView.swift               [MODIFIED — insertArrangedSubview at index 2]

validationLedgerTests/
├── Loads/
│   ├── LoadActionPredictorTests.swift                [NEW — exhaustive (LoadAction × LoadStatus)]
│   ├── LoadDetailViewModelActionTests.swift          [NEW — predict → 200 → loaded; predict → error → rollback]
│   ├── MockLoadFixtureRegistryActionToggleTests.swift [NEW — each of the 4 toggles fires the right fixture]
│   ├── CarrierDirectoryDecodeTests.swift             [NEW — fixture decodes; verification-state coverage]
│   └── Snapshot/
│       ├── LoadActionsViewSnapshotTests.swift        [NEW — 5×13 = 65-cell (Role × LoadStatus) matrix]
│       ├── TenderSheetViewControllerSnapshotTests.swift [NEW — 4 picker states × per-VerificationState rows]
│       └── LoadActionToastBannerViewSnapshotTests.swift  [NEW — per-action × failure-state]
└── Networking/Fixtures/
    └── tender-carrier-directory.json                  [NEW — ~6-8 carriers spanning 4 verification states]

validationLedgerUITests/
└── Loads/
    └── LoadActionFlowsTests.swift                     [NEW — happy-path tender, rollback flow with -MockActionValidation422, ACTION-07 disabled smoke]
```

### Pattern 1: Cancel-and-Replace Task Lifecycle (BL-01)

**What:** Phase 8 / Phase 9 use this pattern for `fetchLoads()` / `fetchLoadDetail()`. A fresh call cancels any in-flight task; the cancelled task's `Task.isCancelled` checkpoints (1) after the network hop returns and (2) before the terminal state assignment close the last-write-wins window.

**When to use:** Every action submission. A rapid Broker tap-tap on Tender (or Cancel mid-flight) must NOT race two responses into the VM. The pattern is already proven for fetch; extend identically for action submission.

**Example (source: `LoadDetailViewModel.swift:135-206` — verbatim shape):**
```swift
// New method on LoadDetailViewModel — mirrors fetchLoadDetail line-for-line.
public func submit(action: LoadAction, body: LoadActionEndpoint.RequestBody) async {
    // BL-01 — cancel-and-replace. A fresh action supersedes any in-flight one.
    actionTask?.cancel()
    // Capture the rollback snapshot BEFORE any state mutation.
    guard case .loaded(let preLoad, let preChain) = state else { return }
    // Compute the predicted forward state — pure helper.
    let predicted = LoadActionPredictor.predict(load: preLoad, action: action, body: body)
    state = .actionInFlight(predicted: predicted, frozenChain: preChain, action: action)
    let task = Task { [weak self] in
        guard let self else { return }
        await self.performAction(loadID: preLoad.id, action: action, body: body, rollbackTo: preLoad, frozenChain: preChain)
    }
    actionTask = task
    await task.value
}
```

### Pattern 2: VM State Machine with `isHidden`-Toggled Subviews (D-20)

**What:** Phase 9 pre-attaches `skeletonContainer / bodyContainer / errorContainer` as siblings; `render(state:)` toggles `isHidden`. NEVER swaps view controllers; NEVER tears down + rebuilds subviews. Constraint stability across state transitions is the safety property.

**When to use:** Phase 10's `.actionInFlight` and `.actionFailed` reuse the existing `bodyContainer` (the body keeps rendering — with predicted Load on `.actionInFlight`, with rollback Load on `.actionFailed`). The toast banner and chain overlay are NEW transient subviews mounted on the VC's root view (NOT inside the body), pinned at attach time, removed on dismiss.

**Example:**
```swift
// LoadDetailViewController.render(state:) extension
private func render(_ state: LoadDetailViewModel.State) {
    switch state {
    case .loading:          // unchanged Phase 9 path
    case .loaded(let load, let chain):
        renderBody(load: load, chain: chain)
        chainOverlay.removeFromSuperview()  // idempotent on first call
    case .actionInFlight(let predicted, let frozenChain, _):
        renderBody(load: predicted, chain: frozenChain)
        mountChainOverlayIfNeeded()
        // Tapped button's spinner is owned by LoadActionsView based on the action.
    case .actionFailed(let rollbackTo, let frozenChain, let errorCopyKey):
        renderBody(load: rollbackTo, chain: frozenChain)
        chainOverlay.fadeOutAndRemove()
        presentToastBanner(copyKey: errorCopyKey)
    case .error:            // unchanged Phase 9 path
    }
}
```

### Pattern 3: `UISheetPresentationController` Modal Recipe (Phase 9 D-08)

**What:** Phase 9's `presentVerificationBasisSheet(for:)` and `presentHandoffDetailSheet(for:)` use an identical 7-line recipe (verified at `LoadDetailViewController.swift:1316-1334` and 1367-1386). Phase 10 mirrors verbatim for `TenderSheetViewController`.

**Example (verbatim from `LoadDetailViewController.swift:1322-1333`):**
```swift
let sheetVC = TenderSheetViewController(directory: carriers, onSend: { [weak self] body in
    await self?.viewModel.submit(action: .tender, body: body)
})
sheetVC.modalPresentationStyle = .pageSheet
if let sheet = sheetVC.sheetPresentationController {
    sheet.detents = [.medium(), .large()]
    sheet.selectedDetentIdentifier = .medium
    sheet.prefersGrabberVisible = true
    sheet.largestUndimmedDetentIdentifier = .medium   // keeps detail interactive behind
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    sheet.prefersEdgeAttachedInCompactHeight = true
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
}
present(sheetVC, animated: true)
```

### Pattern 4: DEBUG Launch-Arg Toggle

**What:** Both `-MockKYCStatusVerified` (`MockDefaultFixtures.swift:60-76`) and `-Mock2DTrustGraphOnIPhone` (`LoadDetailViewController.swift:118-131`) use this exact shape. Three Phase 10 toggles + one latency toggle follow it.

**Example (source: `MockDefaultFixtures.swift:60-76` — verbatim shape):**
```swift
#if DEBUG
public enum DebugActionFailureOverride {
    public static let conflict409Flag       = "-MockActionConflict409"
    public static let validation422Flag     = "-MockActionValidation422"
    public static let serverError500Flag    = "-MockActionServerError500"
    public static let latencySlowFlag       = "-MockActionLatencySlow"

    public static var conflict409Active: Bool {
        ProcessInfo.processInfo.arguments.contains(conflict409Flag)
    }
    // …same shape for the other three
}
#endif
```

The four registrations in `MockLoadFixtureRegistry` are gated `#if DEBUG` AND on the corresponding `…Active` boolean. Registration order in the registry decides precedence (D-20: planner picks order — recommended `conflict409 → validation422 → serverError500 → latencySlow`). The latency toggle does NOT short-circuit the success path — it inserts a delay then falls through to success (or one of the failure toggles if combined).

### Pattern 5: `MockURLProtocol.register { request in … }` Handler Shape

**What:** Confirmed at `MockLoadFixtureRegistry.swift:129-167`. A handler receives a `URLRequest`, returns `(HTTPURLResponse, Data)?`; returning `nil` defers to the next registered handler. The default action handler matches POST + `/loads/{VL-…}/{actionSegment}`.

**Example (Phase 10 conflict-409 handler — derived from the existing success handler):**
```swift
#if DEBUG
if DebugActionFailureOverride.conflict409Active {
    MockURLProtocol.register { request in
        guard request.httpMethod == "POST" else { return nil }
        guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
        let suffix = String(path.dropFirst("/loads/".count))
        let parts = suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard String(parts[0]).hasPrefix("VL-") else { return nil }
        guard actionPathSegments.contains(String(parts[1])) else { return nil }
        return make409(body: conflict409Payload, url: request.url)  // NEW helper
    }
}
#endif
```

The four fixtures (`load-action-conflict-409.json`, `…-validation-422.json`, `…-server-error-500.json`, `…-success.json`) ALREADY EXIST at `validationLedgerTests/Networking/Fixtures/` (confirmed by `ls`). Phase 10 either inlines each fixture's bytes into the registry (matches the existing `listPayloads` discipline) OR references them via test-bundle resource loading — the existing pattern inlines. **Recommendation: inline**, to keep the DEBUG App bundle independent of the test bundle (per the existing file's invariant).

### Pattern 6: `UIKitSnapshot.image(of:size:) + attach(_:name:to:)` (Phase 8 Wave 0)

**What:** Hand-rolled `UIGraphicsImageRenderer` + `view.layer.render(in:)`. Zero SPM dependency. Used by 13 existing snapshot test files in `validationLedgerTests/Loads/Snapshot/`.

**Phase 10 application — the 65-cell matrix:**
```swift
// LoadActionsViewSnapshotTests.swift sketch
final class LoadActionsViewSnapshotTests: XCTestCase {
    func test_actionRegion_matrix_5roles_x_13statuses() {
        for role in Role.allCases {
            for status in LoadStatus.allCases {
                let actions = RoleLoadPolicy.actions(for: role, status: status)
                let view = LoadActionsView()
                view.configure(actions: actions, role: role, status: status,
                               tenderEligibility: nil)  // separate test for the disabled-gate variant
                let img = UIKitSnapshot.image(of: view, size: CGSize(width: 393, height: 120))
                UIKitSnapshot.attach(img, name: "actions-\(role.rawValue)-\(status.rawValue)", to: self)
                // ASSERT against a checked-in baseline by pixel-difference threshold
                // (Phase 9.1 D-05 precedent — baselines re-record post-Wave 4).
            }
        }
    }
}
```

### Anti-Patterns to Avoid

- **`switch load.status` inside any VC, cell, or LoadActionsView render method.** ROADMAP §Phase 10 lock. The ONLY status read in the action region is the call to `RoleLoadPolicy.actions(for:status:)` — that result is the rendering contract. The `nextStatus(from:)` button-title resolver is an exception, but it must live in a separate pure helper, NOT inline.
- **Predicting the chain-of-trust forward.** D-13 lock. The chain card always renders pre-tap state during `.actionInFlight`; the overlay communicates "this will refresh." Predicting an edge flip "to save a round-trip" directly attacks the platform thesis.
- **Rendering server-supplied error text from `LoadActionEndpoint` failures.** D-15 / T-09-04 / T-08-08 view-layer lock. Error classification (409 vs 422 vs 500 vs network) is logged with `fields: [:]`, never rendered. The ONE exception is `Load.tenderEligibility.disabledReason` — explicitly DOCUMENTED in UI-SPEC line 293 as load-state metadata, not error-response payload.
- **Hiding the action region when `RoleLoadPolicy.actions == []`.** D-04 — the region renders a tasteful caption ("This is a view-only role…" / "This load is delivered…"). Hiding silently makes Factoring's role indistinguishable from a screen bug.
- **Hiding unverified/flagged carriers in the tender picker.** D-08 — the platform thesis is at its strongest when the broker SEES the fraud signal and can't bypass it. Visible-but-disabled with localized reason.
- **Adding a separate `LoadActionViewModel`.** D-16 — the back-channel for chain swap on success makes separation worse, not better. Extend the existing `LoadDetailViewModel`.
- **`isEnabled = false` without `accessibilityHint`.** UI-SPEC § Accessibility — every disabled button speaks the disabled reason on focus, including in-flight peers.
- **Auto-dismissing the tender sheet on Send tap (before the response).** UI-SPEC line 454 — sheet stays visible during the in-flight; on 200 the parent VC dismisses it; on error the sheet stays visible while the toast appears over the parent.
- **Computing `LoadStatus.localizedDisplayName` ad-hoc inside `LoadActionsView`.** Phase 9 timeline already established `LoadStatus.localizedDisplayName` (per UI-SPEC line 307); Phase 10 reuses it for the terminal-status caption interpolation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotency-key header on every action POST | A second interceptor; a per-action UUID generator; a stable-key store | EXISTING `IdempotencyInterceptor` (already in `apiClient.requestInterceptors`) | Auto-injects fresh UUID per request; v1.0 contract; zero new wiring (D-17 / D-19) |
| Modal sheet with detents | Hand-rolled modal transition + custom presentation controller | `UISheetPresentationController` with the Phase 9 recipe | iOS 17-native; Phase 9 D-08 precedent; 7 lines |
| Sliding toast banner | `MaterialComponents.MDCSnackbar` / Toast-Swift / SwiftMessages | Hand-rolled `UIView.animate` + `transform` (UI-SPEC component-geometry table) | CLAUDE.md pre-approved-shortlist; toast geometry is ~80 LoC |
| `viewWillAppear` pop-back data refresh | NotificationCenter; observer pattern; shared load cache | EXISTING `LoadListViewController.viewWillAppear → fetchLoads()` (line 381) | Free — success criterion #5 has zero new code (D-18) |
| Per-`(Role × LoadStatus)` action gating | `switch load.status` inside `LoadActionsView` | `RoleLoadPolicy.actions(for:status:)` | Exhaustively unit-tested in Phase 7; the rendering contract |
| Date formatting for the respond-by countdown | Hand-rolled `Date → String` | `DateFormatter` with `.relative` + `.short` time (UI-SPEC line 326) | Standard library + localization-aware |
| Snapshot baseline framework | `swift-snapshot-testing` SPM dep | EXISTING `UIKitSnapshot.image(of:size:)` + `attach(_:name:to:)` | Phase 8 Wave 0 helper; no new dep |
| DEBUG launch-arg parsing | A flags framework; an environment-variable library | `ProcessInfo.processInfo.arguments.contains(...)` + `#if DEBUG` | Already used twice in this codebase; trivial |
| MockURLProtocol failure-injection wiring | A new mock framework; a per-test failure registrar | EXISTING `MockURLProtocol.register { … }` + `MockURLProtocol.latency` / `MockURLProtocol.forcedFailure` (Phase 7 D-14) | Same registry the success handler uses |
| Verification-badge rendering on a carrier row | A new badge view | EXISTING `VerificationBadgeView` (Phase 8) + `DS.Colors.Verification.color(for:)` (Phase 9.1 lock) | Single source of truth for verification visual; TRUST-02 invariant |
| Predicted-state derivation | Inline `switch action { … }` in the VM | NEW pure `LoadActionPredictor.predict(load:action:body:)` namespace | Mirror of `RoleLoadPolicy` shape; exhaustively unit-testable; no UIKit |

**Key insight:** Phase 10 has ZERO new infrastructure work. Every piece — idempotency, mock fixtures, sheet presentation, snapshot baselines, launch-arg parsing, pop-back refresh, badge rendering, design tokens — already exists. The plan's risk surface is entirely in the new presentation code and the predictor function, both of which are bounded and unit-testable. Watch for "let's build a small helper" temptations.

## Common Pitfalls

### Pitfall 1: The chain overlay outlives the action

**What goes wrong:** The chain "updating…" overlay is mounted on `.actionInFlight` and faded out on `.loaded` (success) or `.actionFailed` (error). A new fetch driven by `viewWillAppear` could land mid-flight, transitioning state to `.loading → .loaded` while an action is still in flight (cancel-and-replace fires); the overlay's fade-out animation could race the new mount.

**Why it happens:** Two state-machine paths can both want the overlay attached or removed; without an explicit "current overlay" reference, two animations stack.

**How to avoid:** Hold a single `private var chainOverlay: UIView?` reference on the VC. Every transition to a non-`.actionInFlight` state calls `chainOverlay?.fadeOutAndRemove()` then sets `chainOverlay = nil` in the completion block. Every transition INTO `.actionInFlight` checks if one already exists and reuses it.

**Warning signs:** Overlay visible after the action completes; double-fade animation; overlay flickers on a fast tap-then-back tap.

### Pitfall 2: Mock-toggle handler order silently changes when CONTEXT D-21 line is moved

**What goes wrong:** `MockLoadFixtureRegistry` registers handlers as a sequence — first match wins. If a future plan reorganizes the registry file, the four DEBUG toggle branches might end up AFTER the success handler, breaking failure-injection silently (the success handler matches first).

**Why it happens:** Registration is procedural; order is invisible at call-site without reading the registry file.

**How to avoid:** Add a comment block at the registry function head listing the registration order with rationale. Add a test that verifies: with `-MockActionConflict409` injected into `ProcessInfo.processInfo.arguments` (test-local override; planner finds the seam), `apiClient.request(LoadActionEndpoint(...))` returns a 409 fixture body. Same for the other three flags.

**Warning signs:** Failure-path UAT shows success behavior despite the flag being set.

### Pitfall 3: The predictor reads `Load.respondByAt` instead of `RequestBody.respondByAt`

**What goes wrong:** On `.tender`, the predicted `Load.respondByAt` is what the broker JUST chose in the sheet — `body.respondByAt`. If the predictor reads `currentLoad.respondByAt` (which is `nil` on a `.posted` load), the predicted-state carrier countdown UI shows nothing during in-flight.

**Why it happens:** The predictor signature `(Load, LoadAction) -> Load` looks complete; in practice it needs the `RequestBody` too.

**How to avoid:** Predictor signature is `(load: Load, action: LoadAction, body: LoadActionEndpoint.RequestBody?) -> Load`. The body is non-nil for `.tender` (drives `respondByAt`); planner documents the per-action body-field dependencies.

**Warning signs:** During-in-flight UI on `.tender` shows the timeline advance but no respond-by line.

### Pitfall 4: Role propagation lands but the VM doesn't actually pass it

**What goes wrong:** D-22 changes `AppContainer.makeLoadDetailScreen(loadID:)` to `(loadID:role:)`, plumbing `role` to `LoadDetailViewModel`. If the VM stores `role` but never reads it (because the new `submit` method's signature passes the role from the call-site directly), the role propagation is dead code.

**Why it happens:** Two valid wirings — VM stores role, or call-sites pass role each time.

**How to avoid:** The VM stores `role` as a designated-initializer parameter; the `submit(action:body:)` method uses `body.actorRole` from the body the call-site composes; BUT the VM is what TRIGGERS the rendering of the action region with the right policy result, so `LoadActionsView.configure(...)` is called with `viewModel.role`. Test: VM-init with role; assert `viewModel.role == .broker`; render the body; assert the action region's available actions match `RoleLoadPolicy.actions(for: .broker, status: load.status)`.

**Warning signs:** A carrier-role detail screen shows broker actions, or vice versa.

### Pitfall 5: `loads.actions.empty.terminal.format` is interpolated with the rawValue, not the localized name

**What goes wrong:** UI-SPEC line 304 specifies `"This load is %@. No actions available."` — `%@` is the LOCALIZED lowercase status name. A naive implementation passes `load.status.rawValue` ("in_transit" with underscore) or `load.status.displayName.lowercased()` (if a `displayName` helper exists at PascalCase).

**Why it happens:** The codebase has a `Role.displayName` but no canonical `LoadStatus.localizedDisplayName` lock — UI-SPEC line 307 says "(already established for the timeline component; planner re-uses)" — but the planner has to VERIFY this helper exists and matches the format.

**How to avoid:** Verify `LoadStatus.localizedDisplayName` exists before the snapshot tests are written. If absent, ADD it as part of the predictor wave (it's a closed enum's localized display string — a 13-case switch). Cross-reference with Phase 9 `StatusTimelineView` for the source of truth.

**Warning signs:** Empty-state caption reads "This load is in_transit. No actions available."

### Pitfall 6: `LoadActionsView` re-renders on every `.actionInFlight` tick

**What goes wrong:** During `.actionInFlight`, the predicted-Load's `status` changes (e.g. `.posted → .tendered`). If `LoadActionsView` re-renders against the predicted status, the action set MIGHT change mid-flight (`[.tender, .cancel] → [.cancel]`), causing the tapped button to disappear before its spinner animation completes.

**Why it happens:** The action region naturally renders against current Load's status; a state transition that includes status advance also triggers a re-render against the new action set.

**How to avoid:** During `.actionInFlight`, `LoadActionsView` should render the PRE-TAP action set with the TAPPED button in-flight and other buttons disabled — NOT the post-tap action set. Concretely: the view's `configure(...)` method during `.actionInFlight` receives the pre-tap actions + the in-flight action ID; only on transition back to `.loaded` does the re-render snap to the new action set. This is a configure-method-signature decision the planner finalizes.

**Warning signs:** The tapped button disappears immediately after tap; the spinner appears for an instant then vanishes.

### Pitfall 7: Snapshot tests don't reset state between iterations of the 65-cell matrix

**What goes wrong:** `UIKitSnapshot.image(of:size:)` renders a configured `UIView`. If the same `LoadActionsView` instance is reconfigured for all 65 cells, residual state (selection, in-flight spinner, hidden labels) can leak between snapshots.

**Why it happens:** It's tempting to allocate one view and reconfigure repeatedly for perf.

**How to avoid:** Allocate a fresh `LoadActionsView()` for each cell. Cost is trivial (65 small UIView allocations per test run).

**Warning signs:** Snapshot diff failures on adjacent cells that share state (e.g. a `.tendered` snapshot has remnants from the prior `.posted` snapshot's button layout).

### Pitfall 8: The tender sheet's Send-button helper line lingers when Send becomes enabled

**What goes wrong:** UI-SPEC § Tender sheet copy specifies three helper-line copies for "Send disabled because…" The most natural implementation toggles `isHidden` on the label. If the label's layout participates in the sheet's content height, hiding it can cause a sheet-detent reflow that looks janky.

**Why it happens:** The helper line lives in the bottom-anchored layout; toggling its presence changes the bottom-anchored region's height.

**How to avoid:** Allocate the helper-line label with a fixed height + `alpha 0/1` toggle instead of `isHidden`. The layout stays stable; only opacity animates. Confirm with a snapshot test of all four helper states (no-carrier / unverified-carrier / past-deadline / no-helper).

**Warning signs:** The sheet detent jumps a few points when the user picks a carrier.

### Pitfall 9: A second `viewWillAppear`-driven refresh races a still-pending action

**What goes wrong:** Broker taps Tender; the action is in-flight. The user swipes back to the list before the response lands. The list's `viewWillAppear → fetchLoads()` fires. The detail VC is dismissed. The list refreshes. But the action task is still alive in memory (the VC owns the VM owns the task) — if the response arrives after the VC's view is gone, the VM's `state` mutation triggers a `onStateChange` callback on a dealloc'd VC's closure.

**Why it happens:** Task lifetime exceeds VC lifetime; the closure captures `[weak self]` (it must), so the trailing state mutation is a no-op — but the state mutation still happens.

**How to avoid:** Confirm the VM's `submit` method's terminal state assignments are no-ops when `[weak self]` is nil. Confirm the VC's `onStateChange` closure is `[weak self]`. Add a unit test: simulate the VC dismissal mid-action, assert no crash. This pattern is identical to Phase 9's existing detail-fetch lifecycle — Phase 10 inherits.

**Warning signs:** A flaky crash on rapid back-tap while the network is slow.

## Runtime State Inventory

> Phase 10 is a feature-addition phase, not a rename/refactor. This section is included for completeness — most categories are empty.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 10 introduces NO new persistence. Load state lives in the in-memory VM; no UserDefaults / no Keychain / no Core Data writes. | None |
| Live service config | None — `MockURLProtocol` is the only "service"; all configuration lives in `MockLoadFixtureRegistry` (in-source, version-controlled). | None |
| OS-registered state | None — Phase 10 registers nothing with the OS (no Task Scheduler, no launchd, no push categories). | None |
| Secrets/env vars | None — Phase 10 adds NO secrets and NO environment variables. The four DEBUG launch arguments (`-MockActionConflict409` / `-MockActionValidation422` / `-MockActionServerError500` / `-MockActionLatencySlow`) are configuration flags, not secrets. | None |
| Build artifacts | None — pure Swift source; no generated artifacts. The four new `Mock…` toggles compile to ZERO bytes in Release (`#if DEBUG` gated). | None |

**Nothing found in any category:** Verified by scanning the Phase 7 / 8 / 9 / 9.1 close-out memories (`phase-4-ci-closeout`, `phase-9-execution-closeout`, `phase-9.1-execution-closeout`); none flagged a runtime-state migration concern for the next phase. Phase 10 is structurally additive.

## Code Examples

Verified patterns lifted from the existing source tree:

### Adding a new MockURLProtocol handler (carrier directory)

```swift
// In MockLoadFixtureRegistry.swift — register alongside the existing handlers
MockURLProtocol.register { request in
    guard request.httpMethod == "GET" else { return nil }
    guard request.url?.path == "/carriers/directory" else { return nil }
    return make200(body: tenderCarrierDirectoryPayload, url: request.url)
}

private static let tenderCarrierDirectoryPayload: Data = Data(#"""
{
  "carriers": [
    {
      "party_id": "party-carrier-acme",
      "role": "carrier",
      "display_name": "Acme Trucking Inc.",
      "verification_state": "verified",
      "kyc_completed_at": "2025-09-22T13:05:00Z",
      "device_binding_status": "bound",
      "usdot_number": "0123456",
      "usdot_authority_status": "active",
      "prior_relationships": []
    },
    {
      "party_id": "party-carrier-chameleon",
      "role": "carrier",
      "display_name": "Chameleon Cargo LLC",
      "verification_state": "flagged",
      "kyc_completed_at": null,
      "device_binding_status": "mismatched",
      "usdot_number": "9999999",
      "usdot_authority_status": "revoked",
      "prior_relationships": []
    }
    // … 4-6 more spanning .verified / .pending / .unverified / .flagged
  ]
}
"""#.utf8)
```

Source: existing `MockLoadFixtureRegistry.swift:4734-4738` (degraded-demo handler) — same registration shape, same payload-inline discipline.

### Pure predictor function (sketch)

```swift
// Core/Load/LoadActionPredictor.swift — NEW
import Foundation

public enum LoadActionPredictor {
    /// Compute the optimistic forward Load value for `(current, action, body)`.
    /// Pure — no UIKit, no I/O. Exhaustively unit-tested in
    /// `LoadActionPredictorTests`.
    public static func predict(
        load current: Load,
        action: LoadAction,
        body: LoadActionEndpoint.RequestBody?
    ) -> Load {
        switch (action, current.status) {
        case (.post, .draft):
            return current.with(status: .posted)
        case (.tender, .posted), (.tender, .rejected), (.tender, .expired):
            return current.with(status: .tendered, respondByAt: body?.respondByAt)
        case (.accept, .tendered):
            return current.with(status: .accepted, respondByAt: nil)
        case (.reject, .tendered):
            // D-04: server returns the load to .posted (eventually). Predict
            // .rejected as the visible transitional state; the 200 response's
            // load.status is authoritative — likely .posted by the server.
            return current.with(status: .rejected, respondByAt: nil)
        case (.cancel, _):
            return current.with(status: .cancelled, respondByAt: nil)
        case (.advanceStatus, .accepted):
            return current.with(status: .dispatched)
        case (.advanceStatus, .dispatched):
            return current.with(status: .inTransit)
        case (.advanceStatus, .inTransit):
            return current.with(status: .delivered)
        default:
            // Policy gate should have prevented this combination from reaching
            // the predictor. Return current as a defensive no-op.
            return current
        }
    }
}
```

`Load.with(status:respondByAt:)` is a small extension helper the planner adds — Load is `Decodable`-only currently, so the helper builds a new `Load` via the synthesized memberwise init Swift provides on structs (or, if the synthesized init isn't accessible due to `public` properties + non-public init, the planner adds a `public init(...)` to `Load.swift` as part of this wave — verify this constraint).

Source-pattern analog: no exact predecessor; the shape mirrors `RoleLoadPolicy.actions(for:status:)`.

### Extending LoadDetailViewModel.State

```swift
// LoadDetailViewModel.swift — D-16 indicative; planner finalizes
public enum State: Equatable, Sendable {
    case loading
    case loaded(Load, ChainOfTrust)
    case actionInFlight(predicted: Load, frozenChain: ChainOfTrust, action: LoadAction)
    case actionFailed(rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String)
    case error(message: String)
}
```

The `Equatable` synthesized conformance works given the existing identity-only `Load` and `ChainOfTrust` Equatable extensions at `LoadDetailViewModel.swift:253-279` (verified). `LoadAction` is `Equatable` for free as a `String`-raw-value enum. Plain `String` is `Equatable`. No new conformance work needed.

Source: `LoadDetailViewModel.swift:61-74` (existing 3-case State).

### Threading role through AppContainer (D-22)

```swift
// AppContainer.swift — MODIFIED
@MainActor
func makeLoadDetailScreen(loadID: String, role: Role) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(subsystem: LoggingSubsystem.app, category: "feature.loads")
    let viewModel = LoadDetailViewModel(loadID: loadID, role: role, apiClient: apiClient, logger: featureLogger)
    return LoadDetailViewController(viewModel: viewModel)
}

// And in makeLoadListScreen(role:), the factory closure becomes:
let detailFactory: (String) -> UIViewController = { [weak self] loadID in
    guard let self else { return UIViewController() }
    return self.makeLoadDetailScreen(loadID: loadID, role: role)  // ← role captured from outer scope
}
```

Source: `AppContainer.swift:218-294` (the current `makeLoadListScreen(role:)` + `makeLoadDetailScreen(loadID:)` pair — confirmed at exact line numbers).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `switch load.status` in cell / VC code | `RoleLoadPolicy.actions(for:status:)` (single source) | Phase 7 (2026-05-19) | The architectural ban is the heart of Phase 10's per-role correctness. |
| Custom modal transitions for sheet content | `UISheetPresentationController` with detents (iOS 15+) | Phase 9 D-08 (2026-05-20) | Native infrastructure, predictable z-order, undimmed parent context retained |
| Hand-rolled animation libraries for in-app banners | `UIView.animate` + `transform` + haptics | iOS 7+ — never needed a library here | Zero deps; geometry is trivial; CLAUDE.md mandates |
| Server round-trip blocking the action button (waterfall UX) | Optimistic predict + rollback on failure | UI-SPEC D-12..D-15 | Snappy taps; one-way trust direction (load predicted; chain NEVER predicted) |
| Stable-key idempotency replay | Fresh-UUID-per-request via `IdempotencyInterceptor` (UI guard prevents user-driven dupes) | Phase 2 NET-04 / Phase 7 D-19 | Stable-key only matters for real-backend retry-on-failure; deferred to post-v1.1 |

**Deprecated/outdated:**
- The old `.planning/codebase/*.md` files (dated 2026-04-21) reference a "brand-new SwiftUI scaffold." Every Phase 7..9.1 CONTEXT.md flagged this. The source tree is authoritative; don't read those files.

## Assumptions Log

Every claim in this RESEARCH.md was verified against the source tree (read line-by-line) or the locked CONTEXT.md / UI-SPEC.md. No `[ASSUMED]` claims — every package / API / pattern citation is a `[VERIFIED:` against the file path given.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | (none — table intentionally empty) | — | — |

**All claims verified.** No user confirmation needed on infrastructure claims. The planner can build directly from this research. The ONE area where the planner has unbounded discretion (and the user has explicitly delegated it — see "Claude's Discretion" above) is the per-action carrier-directory fixture's exact carrier list, the predictor's specific `Load.with(status:respondByAt:)` helper shape, the toggle-precedence order, the latency interval, and the VM state-enum case shape's exact field names. The planner should pick and document, not re-ask.

## Open Questions

1. **Does `Load` have a synthesized memberwise initializer accessible to the predictor's `with(...)` helper?**
   - What we know: `Load` is declared `public struct Load: Decodable, Sendable` (`Load.swift:101`). All properties are `public let`. Swift synthesizes a memberwise `init(...)` for structs with stored properties — but only with `internal` access by default. A `public` synthesized memberwise init requires explicit declaration.
   - What's unclear: Whether the predictor's `Load.with(status:)` helper can construct a new `Load` from outside the module (the predictor is in the same module, so `internal` is fine — verify this).
   - Recommendation: The predictor lives in `validationLedger/Core/Load/LoadActionPredictor.swift` — same module as `Load.swift`. The synthesized internal memberwise init is accessible. If the planner places the predictor elsewhere or wants to expose `Load.with(...)` for tests, an explicit `public init` is added to `Load.swift` (additive — Phase 7 contract isn't broken). **Probability:** the same-module path is the natural choice; no action needed.

2. **Does `LoadStatus.localizedDisplayName` (or equivalent) already exist?**
   - What we know: UI-SPEC line 307 asserts "already established for the timeline component; planner re-uses." `StatusTimelineView.swift` exists at `Features/Loads/Detail/StatusTimelineView.swift` (confirmed by `ls`).
   - What's unclear: Whether the helper is `LoadStatus.localizedDisplayName` (a domain-side extension) or `StatusTimelineView`-internal (a view-side helper). UI-SPEC implies the former; the codebase may have the latter.
   - Recommendation: Before writing the empty-state caption code, the planner verifies the helper's location with a grep for "localizedDisplayName" against `validationLedger/Core/Load/` and `validationLedger/Features/Loads/Detail/`. If only view-side, lift to a `LoadStatus` extension in `Core/Load/` (additive, low-risk).

3. **What is the exact respond-by countdown rendering for the carrier/dispatch view of a `.tendered` load?**
   - What we know: UI-SPEC line 317-335 LOCKS the static rendering (not live counter) and the date-format mapping. The data source is `Load.respondByAt` (Phase 7 contract).
   - What's unclear: WHERE in the action region the respond-by label renders — above the `[.accept, .reject]` buttons, below them, or as a separate label INSIDE `LoadActionsView`. UI-SPEC line 323 says "planner picks position."
   - Recommendation: Planner picks "below the action buttons, leading-anchored, `DS.Spacing.xs` (4pt) gap" — visually a clear "context for the buttons above." Adopt without re-asking the user (Claude's Discretion).

4. **How does the tender sheet learn that the parent VC's action submission succeeded (so it can auto-dismiss)?**
   - What we know: UI-SPEC line 455 — "On 200 success: the sheet auto-dismisses with `dismiss(animated: true)`." But the SHEET doesn't observe the parent VM's state; it just calls back to the parent on Send.
   - What's unclear: The exact callback shape — does the parent VC dismiss the sheet imperatively after `viewModel.submit(...)` resolves, or does the sheet observe its own `state` independently?
   - Recommendation: The sheet's `onSend: (RequestBody) async -> Void` closure RETURNS when the action settles (success or failure). The sheet awaits the closure, then: if successful (the parent VC dismissed because the VM transitioned to `.loaded`), the sheet is already gone; if failure (the parent VC kept the screen and slid in the toast), the sheet recovers Send-button state and stays visible. This makes the sheet's lifecycle deterministic. Alternative: an explicit `Result<Void, Error>` from the closure. Planner picks; both are clean.

## Environment Availability

> Phase 10 is a pure iOS/Xcode phase against the existing simulator + device CI infrastructure. No external runtime tools are introduced. This section is brief.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build + simulator + device CI | ✓ | 26.4 (per CLAUDE.md / pinned in v1.0 close-out) | — |
| iOS Simulator (iPhone 17 lane) | Snapshot tests, unit tests | ✓ | iOS 17+ | — |
| iOS Simulator (iPad lane) | iPad composition rebuild tests | ✓ | iOS 17+ | — |
| Physical device CI (self-hosted) | XCUITest happy-path flows | ✓ (closed at v1.0; available for Phase 10) | iOS 17+ | Simulator-only XCUITest if device CI is offline (slower but valid) |
| `xcodebuild` test scoped lane | Unit + snapshot + XCUITest invocation | ✓ | (project memory `ios-test-suite-pitfalls` — `-skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO` for the in-process suite) | — |
| `gsd-sdk` CLI | Workflow orchestration | ✓ | (project memory `gsd-sdk-node16-workaround` — `NODE_OPTIONS="--require /tmp/structured-clone-polyfill.js"` prefix mandatory) | — |
| Slopcheck | Package legitimacy | NOT APPLICABLE | — | — (no new packages) |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Validation Architecture

Nyquist validation is enabled (`workflow.nyquist_validation: true` in config.json).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (in-process unit + snapshot) + XCTest (XCUITest only — STACK-03 lock) |
| Config file | Project-level (`.xcodeproj` test plans); no per-package config |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:validationLedgerTests/Loads/LoadActionPredictorTests -skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO` |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO` (per project memory `ios-test-suite-pitfalls` — bare `xcodebuild test` gives ~67 false failures) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACTION-01 | Broker on `.posted` sees `[.tender, .cancel]`; Tender opens sheet; sheet posts `targetPartyID + respondByAt` | unit (predictor + VM) + snapshot (action region) + XCUITest (smoke flow) | `… -only-testing:validationLedgerTests/Loads/LoadDetailViewModelActionTests/test_tenderSubmission_predictsTendered` + `…/LoadActionFlowsTests/test_brokerTenderHappyPath` | ❌ Wave 0 |
| ACTION-02 | Broker on `.rejected` / `.expired` sees `[.tender, .cancel]`; retender uses the same Tender button | unit (predictor — `tender on .rejected → predicted .tendered`) + snapshot (action region on `.rejected` × `broker`) | `… -only-testing:…/LoadActionPredictorTests/test_tenderOnRejected_predictsTendered` | ❌ Wave 0 |
| ACTION-03 | Carrier on `.tendered` taps Accept → predicted `.accepted` → 200 → `response.load.status == .accepted` swap | unit (predictor) + VM (state transition) + XCUITest (smoke) | `…/LoadDetailViewModelActionTests/test_acceptSubmission_predictsAccepted` + `…/LoadActionFlowsTests/test_carrierAcceptHappyPath` | ❌ Wave 0 |
| ACTION-04 | Carrier on `.tendered` taps Reject → predicted `.rejected` → server returns `.posted` (eventually) | unit (predictor) + VM (state swap on response) | `…/LoadDetailViewModelActionTests/test_rejectSubmission_serverReturnsPosted` | ❌ Wave 0 |
| ACTION-05 | Carrier on `.accepted/.dispatched/.inTransit` → `[.advanceStatus]` button title resolved via `nextStatus(from:)` | unit (button title resolver) + snapshot (3 advance variants) | `…/LoadActionPredictorTests/test_advanceStatus_each_transition` + snapshot matrix cell | ❌ Wave 0 |
| ACTION-06 | Broker `.draft → .post` produces `.posted`; broker `.posted → .cancel` produces `.cancelled` | unit (predictor) + snapshot (draft action set) | `…/LoadActionPredictorTests/test_post_and_cancel` | ❌ Wave 0 |
| ACTION-07 | Load-level: Tender button disabled with `disabledReason` when `tenderEligibility.canTender == false`. Carrier-level: unverified/flagged carriers visible-but-disabled in picker. | snapshot (action region — load-level disabled state) + snapshot (tender sheet — picker with mixed verification states) + XCUITest (smoke) | `…/Snapshot/LoadActionsViewSnapshotTests/test_tenderDisabledByEligibility` + `…/TenderSheetViewControllerSnapshotTests/test_pickerWithMixedVerification` + `…/LoadActionFlowsTests/test_action07_hardDisabled` | ❌ Wave 0 |
| ACTION-08 | Predict → 422 → rollback + toast | VM unit (predict → error → rollback) + XCUITest with `-MockActionValidation422` | `…/LoadDetailViewModelActionTests/test_actionFailure_rollsBackAndPresentsToast` + `…/LoadActionFlowsTests/test_actionRollback` | ❌ Wave 0 |
| ACTION-09 | 5×13 (Role × LoadStatus) → action set matches `RoleLoadPolicy` | snapshot matrix (65 cells) + policy contract (already covered by `RoleLoadPolicyTests` from Phase 7) | `…/Snapshot/LoadActionsViewSnapshotTests/test_actionRegion_matrix_5roles_x_13statuses` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme validationLedger -only-testing:validationLedgerTests/Loads/LoadActionPredictorTests` (~5s; planner extends per-wave)
- **Per wave merge:** Full scoped simulator suite (`-skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO`) — runs all phase tests + the full Loads test directory
- **Phase gate:** Full suite green (simulator + device-CI XCUITest lane) before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `validationLedgerTests/Loads/LoadActionPredictorTests.swift` — unit tests for every `(LoadAction × LoadStatus)` combination the policy permits, plus the predicted `respondByAt` from the body
- [ ] `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift` — VM state transitions for `submit(action:body:)`: predict → 200 → loaded; predict → error → rollback; cancel-and-replace mid-flight; double-submit guard
- [ ] `validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift` — each of the 4 DEBUG toggles fires the right fixture body; precedence order is documented and tested
- [ ] `validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift` — the new carrier-directory fixture decodes; spans the 4 `VerificationState` cases
- [ ] `validationLedgerTests/Loads/Snapshot/LoadActionsViewSnapshotTests.swift` — 65-cell matrix + the `tenderEligibility.canTender == false` variant + the empty-state variants
- [ ] `validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift` — sheet at default state, sheet with each `VerificationState` row, sheet at `.actionInFlight` Send button state, sheet with each helper-line copy
- [ ] `validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift` — toast for each of the 6 per-action error keys
- [ ] `validationLedgerUITests/Loads/LoadActionFlowsTests.swift` — minimum 3 flows per CONTEXT D-19's QA expectation: (a) broker happy-path tender (sheet → Send → 200 → list reflects `.tendered`), (b) carrier accept (`.tendered` → Accept → `.accepted` → advance to delivered chain), (c) rollback flow with `-MockActionValidation422` (toast slides in, action region restores)

*(All gaps are NEW files — no existing test infrastructure is missing. The `UIKitSnapshot` helper, the launch-arg pattern, the XCUITest scaffolding, and the `MockURLProtocol.register` shape are all present.)*

## Security Domain

> `security_enforcement` is not explicitly set in `.planning/config.json` (key absent → treat as enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Auth lives in v1.0 (OTP + device binding); Phase 10 reuses the session role. No new auth surface. |
| V3 Session Management | no | Session management is v1.0; Phase 10 reads `role: Role` (set at OTP verify); no session mutation. |
| V4 Access Control | **yes** | `RoleLoadPolicy.actions(for:status:)` is the client-side access-control table (server enforces independently per Phase 7 D-18). The ACTION-07 hard-disable on Tender to an unverified counterparty is access-control-on-display. |
| V5 Input Validation | **yes** | `LoadActionEndpoint.RequestBody` is typed (`Role`, `String?`, `Date?`); decoding fails closed (Phase 7 D-09 contract); deadline-in-future validation is a client-side sanity guard. Tender sheet validates: `carrierSelected != nil` (V5.1.1), `carrierSelected.verificationState == .verified` (business validation), `respondByAt > Date()` (V5.1.4 — temporal). |
| V6 Cryptography | no | No new crypto surface; `IdempotencyInterceptor` uses `UUID()` which is UUIDv4 (128 bits entropy on Darwin) — already a v1.0 control. |
| V7 Error Handling | **yes** | T-09-04 / T-08-08 view-layer lock: error classification is logged (`fields: [:]`), NEVER rendered. Generic localized fixed-copy toast banner per `LoadAction` case. |
| V8 Data Protection | **yes (passive)** | Zero PII in logs (`fields: [:]` discipline). The predictor consumes Load values in-memory only; no leak surface added. The toast banner renders only client-localized strings — no server text. |
| V9 Communication | no | Already covered by v1.0 TLS / certificate pinning. |
| V13 API & Web Service | **yes** | `LoadActionEndpoint` POSTs route through `IdempotencyInterceptor` — every action is automatically idempotent at the request layer (V13.1.4). The UI guard (buttons disabled during `.actionInFlight`) is the user-driven dedup layer (D-17). |

### Known Threat Patterns for {UIKit per-role action surface}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Client-side trust derivation (e.g. inferring "this carrier is OK to tender to" from local logic instead of `tenderEligibility.canTender`) | **Tampering / Elevation of Privilege** | Phase 7 D-18 lock — every gate is server-supplied. `Load.tenderEligibility` is the ONLY trust signal driving the Tender button's disabled state. NEVER derive client-side. (Threat T-07-08 mirror.) |
| Server error text rendered in the UI (DecodingError stringification leaks JSON bytes including party names) | **Information Disclosure** | T-09-04 / T-08-08 view-layer lock. The 6 localized fixed-copy toast keys (one per `LoadAction` case). Logger calls use `fields: [:]`. Phase 9 verification gate `LoadDetailViewModelTests Test 4` is the precedent — Phase 10 adds the symmetric assertion for the action path. |
| Double-submit via rapid tap (broker double-taps Tender, two carriers' parallel tenders land) | **Tampering (state corruption)** | Two-layer defense: UI guard (`isEnabled = false` for all buttons during `.actionInFlight` — D-17) + auto-injected `Idempotency-Key: <UUID>` per request (`IdempotencyInterceptor`). Stable-key replay deferred to post-v1.1 (D-17). |
| Action submitted with `actorRole` that doesn't match the session role (privilege elevation) | **Elevation of Privilege** | `LoadActionEndpoint.RequestBody.actorRole` is set from `viewModel.role` (D-22), which is set at composition root from the OTP-verified session role. Client-side is the same trust as the session; server cross-checks (Phase 7 RoleLoadPolicy server mirror). The detail screen is NOT role-changeable mid-screen (D-23). |
| Sheet content prediction (chain edge flipped optimistically) | **Repudiation / Tampering** | D-13 lock — chain is NEVER predicted. Overlay communicates "this will refresh." Predicting an edge flip directly attacks the platform thesis. |
| Static carrier-directory fixture leaks PII into CI snapshot artifacts | **Information Disclosure** | The fixture's "Acme Trucking Inc." / "Chameleon Cargo LLC" / etc. are synthetic names (per T-08-04 / `UIKitSnapshot.swift:21-26`). Snapshot tests render only synthetic data. |
| Disabled buttons hide the disabled reason from VoiceOver (a11y regression that masks ACTION-07 platform thesis) | **Repudiation (a11y / regulatory)** | UI-SPEC § Accessibility — every disabled button has `accessibilityHint` set to the disabled reason verbatim; the disabled-reason inline label is its own `accessibilityElement`. VoiceOver hears why the action is unavailable. |

## Sources

### Primary (HIGH confidence)
- `validationLedger/Core/Load/RoleLoadPolicy.swift` (verbatim read) — the (Role × LoadStatus) → [LoadAction] policy table
- `validationLedger/Core/Load/LoadAction.swift` (verbatim read) — 6-case enum, `pathSegment` mapping, encoding-only contract
- `validationLedger/Core/Load/LoadStatus.swift` (verbatim read) — 13-case lifecycle enum + snake_case raw values
- `validationLedger/Core/Load/Load.swift` (verbatim read) — `Load`, `LoadStop`, `TenderEligibility` definitions
- `validationLedger/Core/Load/ChainOfTrust.swift` (verbatim read) — `ChainOfTrust`, `TrustNode` (with `partyID`, `displayName`, `verificationState`, etc.)
- `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift` (verbatim read) — request/response shape, idempotency note, path composition
- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` (verbatim read) — UUID-per-request injection on POST/PUT
- `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` (line 129-189 + 4734-4738 verbatim read) — handler registration shape, action-success handler, registration order
- `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift:60-76` — `-MockKYCStatusVerified` precedent
- `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (header + 98-131, 1280-1387 verbatim read) — composition, sheet recipe, `-Mock2DTrustGraphOnIPhone` precedent
- `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` (entirely read) — 3-case state machine, cancel-and-replace, T-09-04 lock, `userFacingMessage(for:)`
- `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift:200-298` — contentStack arrangement, `hidesPinnedSummaryHeader`, internal scroll flag
- `validationLedger/Features/Loads/LoadListViewController.swift:380-385` + 623-635 — `viewWillAppear → fetchLoads()` (success criterion #5 free); list-to-detail push via `detailScreenFactory`
- `validationLedger/Features/Loads/LoadListViewModel.swift:125-198` — cancel-and-replace task lifecycle precedent
- `validationLedger/App/AppContainer.swift:218-294` — current `makeLoadListScreen(role:)` + `makeLoadDetailScreen(loadID:)` factories
- `validationLedger/Roles/Role.swift` — 5-case enum, Codable, `displayName`
- `validationLedger/UI/DesignSystem/Colors.swift` — `DS.Colors.primary/destructive/caution/surface/separator/label/labelSecondary/Verification.color(for:)/Roles.color(for:)`
- `validationLedgerTests/Support/UIKitSnapshot.swift` (entirely read) — `image(of:size:)` + `attach(_:name:to:)`
- `validationLedgerTests/Networking/Fixtures/` (directory listing) — confirmed presence of `load-action-success.json`, `load-action-conflict-409.json`, `load-action-validation-422.json`, `load-action-server-error-500.json`
- `validationLedgerUITests/Loads/LoadDetailFlowTests.swift` + `RoleLoadsTabSmokeTests.swift` — XCUITest launch-arg pattern, OTP-flow helper shape
- `.planning/phases/10-per-role-tender-accept-reject/10-CONTEXT.md` (entirely read) — 23 locked decisions
- `.planning/phases/10-per-role-tender-accept-reject/10-UI-SPEC.md` (entirely read) — complete UI design contract
- `.planning/REQUIREMENTS.md` — ACTION-01..09 definitions
- `.planning/ROADMAP.md` §Phase 10 — 5 success criteria, idempotency-interceptor checklist, zero-switch lock
- `.planning/STATE.md` — current Phase 10 position, milestone state

### Secondary (MEDIUM confidence)
- Project memories (read in init context — `phase-9.1-execution-closeout`, `mock-kyc-status-verified-toggle`, `ios-test-suite-pitfalls`, `gsd-sdk-node16-workaround`, `phase-9-execution-closeout`)

### Tertiary (LOW confidence)
- None — every claim was verified against primary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages; all APIs verified against the iOS 17 SDK + existing in-repo precedents.
- Architecture patterns: HIGH — every pattern (cancel-and-replace, isHidden-toggled state subviews, UISheetPresentationController recipe, DEBUG launch-arg toggle, MockURLProtocol register shape, UIKitSnapshot helper) was located in the source tree and read verbatim.
- Don't-hand-roll list: HIGH — exhaustive; every entry is a known-existing piece of infrastructure.
- Common pitfalls: MEDIUM-HIGH — most pitfalls are derived from CONTEXT.md / UI-SPEC.md edge cases plus the existing Phase 8/9 close-out lessons; pitfalls 3, 6, and 8 are new analyses (Phase-10-specific predictor + action-region + sheet-helper-line) and warrant the planner's particular attention.
- Validation architecture: HIGH — the test framework + scoped command + 65-cell snapshot matrix + per-requirement automated commands map cleanly to existing infrastructure.

**Research date:** 2026-05-21
**Valid until:** 2026-06-21 (30 days — Phase 7 contracts are locked / frozen; the only churn risk is a Phase 9.1 close-out follow-up that touches `LoadDetailBodyView.contentStack`'s arrangement, which would invalidate the "insertArrangedSubview at index 2" claim. No such churn is on the immediate roadmap.)

---

*Phase: 10-per-role-tender-accept-reject*
*Research authored: 2026-05-21*
*Author: gsd-phase-researcher (Claude Opus 4.7 / 1M context)*
