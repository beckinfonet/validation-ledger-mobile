# Phase 8: Role-Filtered Load List - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire a real, role-scoped Loads list into each of the 5 role tab shells (Broker, Shipper, Carrier, Dispatch, Factoring), consuming Phase 7's `LoadListEndpoint` + the `loads-list-{role}.json` fixtures. This phase delivers:

- A `LoadListViewController` + `LoadListViewModel` pair under `validationLedger/Features/Loads/` that owns the screen for all 5 roles (constructed with a `Role` parameter).
- A `LoadRowCell` (in `Features/Loads/Cells/`) composing the two new reusable badge components.
- Two reusable view-layer components under `validationLedger/UI/Components/` (NEW directory) — `VerificationBadgeView` (4-state pill) and `LoadStatusBadgeView` (13-state pill) — sized and styled by the UI-SPEC's `DS.Spacing/Typography/Colors` contract.
- A `SkeletonLoadRowCell` + shimmer for the `.loading` state (establishes the iOS app's first skeleton-with-shimmer pattern; Phase 9+ should follow).
- The `.empty` / `.loaded(loads)` / `.error(message)` states from the UI-SPEC's state machine, each backed by its Phase 7 fixture, with `UIRefreshControl` pull-to-refresh on `.loaded` and `.error`.
- One *additive* contract extension on the list endpoint: a new `LoadListItem { load: Load; displayedCounterparty: TrustNode? }` envelope replaces `[Load]` inside `LoadListEndpoint.Response.loads`. The server (fixture) projects the role-resolved counterparty per row — iOS never selects.
- A fixture refresh for the 5 role-list JSONs to add `displayed_counterparty` per row, plus one new `loads-list-degraded-counterparty.json` exercising the fail-closed UNVERIFIED render path (nil counterparty + `.flagged` counterparty in the same fixture).
- Replacement of each role tab bar's placeholder Loads tab (currently `ShipperTabBarController.makeTab(title: "Loads", systemImage: "shippingbox")` — a generic `UIViewController`) with the real `LoadListViewController` for that role.
- iPad `readableContentGuide` pinning on `horizontalSizeClass == .regular` per UI-SPEC's SC-#5 native-render contract.

What this phase is **not**:
- Any load *detail* screen, chain-of-trust graph, status timeline, or any `LoadDetailEndpoint` consumer (Phase 9).
- Any action buttons, tender/accept/reject UI, or any `LoadActionEndpoint` consumer (Phase 10).
- Any client-side trust derivation, role re-filtering, or sort/group computation — D-18 holds.
- A multi-field load-creation form (deferred — see PROJECT.md `LOAD-F1`).
- Infinite-scroll or any second-page fetch path — `nextCursor` is decoded only.

</domain>

<decisions>
## Implementation Decisions

### Row Counterparty Contract (the UI-SPEC "Open Question")

- **D-01:** The list-row counterparty + verification badge data reaches iOS as a **server-projected `TrustNode?` per row** — already role-resolved server-side (Broker→carrier, Carrier→broker, Shipper→broker, Dispatch→broker, Factoring→carrier). iOS never selects which `TrustNode` to render; it reads what the server hands it. Preserves Phase 7 D-18 ("iOS is a passive renderer").

- **D-02:** The projection lives in a **new envelope type**:
    ```swift
    public struct LoadListItem: Decodable, Sendable {
        public let load: Load
        public let displayedCounterparty: TrustNode?
    }
    ```
    `Core/Load/LoadListItem.swift`. `LoadListEndpoint.Response.loads` changes from `[Load]` to `[LoadListItem]`. `Load.swift` is **unchanged** — the row vs detail aggregate is cleanly separated by the envelope. Detail's `LoadDetailEndpoint.Response { load: Load, chainOfTrust: ChainOfTrust }` is untouched.

- **D-03:** `displayedCounterparty` is **optional**. `nil` semantics are **fail-closed**: the row renders the neutral-grey UNVERIFIED `VerificationBadgeView` with the counterparty name slot suppressed (or a literal `—`). Matches Phase 7 D-09's fail-closed posture; never implies trust we don't have. `nil` is reserved for degraded server responses and (rare) draft/posted loads with no counterparty yet.

- **D-04:** Phase 8 owns the contract extension AND the fixture-data authoring:
    - Update all 5 role-list JSONs (`loads-list-{broker,shipper,carrier,dispatch,factoring}.json`) under `validationLedgerTests/Networking/Fixtures/` to wrap every row in the new envelope (existing `Load` fields nest under `load:`) and add `displayed_counterparty` per row.
    - Counterparty selection per role MUST stay consistent with the shared-world D-11 (a load shared between role lists carries the role-appropriate counterparty: load VL-1001 in `loads-list-broker.json` carries its carrier `TrustNode`; the same VL-1001 in `loads-list-shipper.json` carries the broker `TrustNode`).
    - Add one new fixture `loads-list-degraded-counterparty.json` with at least one `nil`-counterparty row + one `.flagged`-counterparty row, used to exercise the fail-closed UI path in tests.
    - Update `MockLoadFixtureRegistry` to optionally register the degraded fixture in a DEBUG-gated demo lane.

### Pagination Posture

- **D-05:** `LoadListEndpoint.Response.nextCursor` is **decoded only** — the VM stores it in state but never reads it. No infinite-scroll observer, no prefetch trigger, no "Load more" button, no second-page fixture. v1.1 demos run on the named-load library (~12 loads). The consumer is strictly additive: a future backend or fixture upgrade wires in infinite-scroll with no refactor of what Phase 8 ships.

### List Sort and Grouping

- **D-06:** **Server-supplied sort order.** iOS renders `LoadListEndpoint.Response.loads` in the exact array order the server (or fixture) returns. iOS never sorts. D-18 holds; sort semantics are a server/product decision iOS doesn't own. Fixture authoring becomes the place where "a sensible default order" is curated for the v1.1 demo (planner's discretion on the curated default — e.g. active tenders before delivered loads).

- **D-07:** **Single flat section, no headers.** Phase 8 ships the UI-SPEC's already-stated "single un-headered section" posture. No section header views, no group separators.

- **D-08:** Two **forward-looking implementation choices** that keep future sections/filters strictly additive:
    1. The diffable datasource is typed as `UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>` with `enum LoadListSection { case main }` defined from day one. Later adding `.active / .past / .drafts` is an additive enum extension + a one-line classifier function — no datasource refactor.
    2. The layout uses `UICollectionViewCompositionalLayout(.list)` (already in UI-SPEC). Switching section headers on later is one config flag (`UICollectionLayoutListConfiguration.headerMode = .supplementary`) + a header-cell registration — ~30 LOC.

    Rationale: future client-side sections **and** client-side filters both land additively in ~half a day each. The only expensive future path (server-driven sections breaking the wire format into a discriminated `[row | header]` union) is the one Phase 8 explicitly avoids.

### Loading-State Visual

- **D-09:** **Skeleton collection view with shimmer** for the `.loading` state — 6–8 grey placeholder cells mimicking the `LoadRowCell` silhouette (rounded blocks for reference number, origin→destination, the two badges), with a horizontal `CAGradientLayer` shimmer sweep animated via `CABasicAnimation`. The `.loading` state renders the skeleton collection view; `.loaded` swaps to real cells via the diffable datasource (the existing collection view, repopulated). A snapshot test confirms the skeleton silhouette matches the real cell at default Dynamic Type.

- **D-10:** **Phase 8 establishes the app-wide "skeleton-with-shimmer" loading-state pattern.** Phase 9's chain-of-trust party list and any future list-style fetch surface SHOULD follow this precedent (mixing spinners and skeletons across surfaces would be visually inconsistent). The shipped `KYCStatusViewController` precedent (centered `UIActivityIndicatorView`) is preserved as-is — Phase 8 does not back-port the skeleton to v1.0 surfaces.

### Claude's Discretion

The planner / researcher may finalize without re-asking the user:

- The exact skeleton row count (6–8) and the shimmer animation timing (~1.0–1.5 s duration, infinite repeat) — pick what reads as "loading" on a 60 Hz display without distracting motion.
- The tab-wiring strategy: factory-via-AppContainer (matches the v1.0 `kycStatusScreenFactory` precedent on `*TabBarController.init(logoutService:kycStatusScreenFactory:)`) is the obvious continuation; the planner may keep that pattern or extract a shared protocol if cleaner.
- VM error classification (decode error vs HTTP 4xx vs network failure → all collapse to `.error(message: String)` per UI-SPEC; whether `message` is the raw NSLocalizedDescription, a fixed copy string, or a discriminated enum mapped to copy is implementation detail).
- Service-layer abstraction: VM consumes `APIClient` directly OR a typed `LoadListProviding` protocol facade. The v1.0 precedent is direct-client; the planner may introduce a typed facade if it simplifies VM testing.
- The exact `CGFloat` widths/heights for skeleton blocks — must visually approximate the real cell's three-tier hierarchy (anchor / sub-anchor / metadata).
- The Phase 7 fixture diff (D-04) granularity: whether the envelope wrap lands as one PR-sized commit or per-fixture commits. The planner should keep all 6 role-fixture diffs in a single contained plan; the new degraded fixture can land in the same or adjacent plan.
- The chosen `MockURLProtocol` fixture-swap mechanism for the degraded edge fixture (an extra `MockLoadFixtureRegistry.registerForDegradedDemo()` lane or an XCUITest-only `?demo=degraded` query — the existing Phase 7 `MockLoadFixtureRegistry` shape decides which is idiomatic).
- snake_case ↔ camelCase wire bridge: `displayed_counterparty` → `displayedCounterparty` is handled by `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy (no explicit `CodingKey` needed); same for `next_cursor` already in place.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope, requirements, and design contract
- `.planning/phases/08-role-filtered-load-list/08-UI-SPEC.md` — **LOCKED design contract.** Visual, typography, color, copy, accessibility-identifiers, the four-state state machine, the iPad readable-content-guide pinning rule, and the open Counterparty Question that D-01..D-04 above resolve.
- `.planning/REQUIREMENTS.md` — LOAD-03 (role-filtered list), LOAD-04 (standard freight field set + counterparty badge), LOAD-07 (3 distinct states), LOAD-08 (pull-to-refresh), TRUST-02 (single reusable verification badge component).
- `.planning/ROADMAP.md` — Phase 8 goal, the 5 success criteria, the dependency on Phase 7.
- `.planning/PROJECT.md` — v1.1 scope, constraints (UIKit-first, SwiftPM-only, iOS 17, `MockURLProtocol`-only, zero PII in analytics/logs).

### Phase 7 contract that Phase 8 reads against
- `.planning/phases/07-load-domain-model-mock-contract/07-CONTEXT.md` — **D-01..D-19 of the Phase 7 contract.** Especially D-09 (fail-closed `VerificationState`), D-11 (shared-world fixture consistency), D-15 (role-in-path URL scheme), D-16 (paginated envelope from day one), D-18 (iOS is a passive renderer — server supplies all trust).
- `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` — the `Response { loads: [Load], nextCursor: String? }` envelope Phase 8 modifies: `loads: [Load]` → `loads: [LoadListItem]`.
- `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` / `LoadActionEndpoint.swift` — Phase 8 does NOT touch these; reference for cross-endpoint contract consistency.
- `validationLedger/Core/Load/Load.swift` — UNCHANGED. The aggregate Load value type.
- `validationLedger/Core/Load/ChainOfTrust.swift` — defines `TrustNode`, the type `displayedCounterparty: TrustNode?` carries on the new envelope.
- `validationLedger/Core/Load/VerificationState.swift` — the 4-case fail-closed enum the verification badge consumes.
- `validationLedger/Core/Load/LoadStatus.swift` — the 13-case full-lifecycle enum the status badge consumes.
- `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — the Phase 7 registry that registers the per-role list fixtures; Phase 8 extends it for the new degraded edge fixture.
- `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — extended additively in Phase 7 with latency/forced-failure injection; Phase 8 uses the latency injector to exercise the `.loading` state and the failure injector to exercise the `.error` state.
- `validationLedgerTests/Networking/Fixtures/loads-list-{broker,shipper,carrier,dispatch,factoring}.json` — the 5 role fixtures that Phase 8 re-wraps under the new envelope.
- `validationLedgerTests/Networking/Fixtures/loads-list-empty.json` — the empty-list fixture; should also be re-wrapped (a `LoadListItem[]` of length 0).
- `validationLedgerTests/Networking/Fixtures/load-detail-VL-1001.json` (and siblings) — UNTOUCHED; references the same `TrustNode` shape Phase 8 inlines into list rows.

### v1.0 UIKit precedents the planner mirrors
- `validationLedger/UI/DesignSystem/{Spacing,Typography,Colors}.swift` — the `DS.*` token namespace; UI-SPEC pins which tokens go where.
- `validationLedger/Roles/Shipper/ShipperTabBarController.swift` — `makeTab(title:systemImage:)` placeholder pattern Phase 8 replaces with the real `LoadListViewController`. Lines 33–38 are the placeholder; the `wrapTabsWithNavAndInstallAvatar` machinery on lines 39–48 stays.
- `validationLedger/Roles/{Broker,Shipper,Carrier,Dispatch,Factoring}/*TabBarController.swift` — the 5 sibling tab bar controllers; each gets the same factory-injected Loads VC.
- `validationLedger/Features/KYC/Status/KYCStatusViewController.swift` (v1.0 archived under `.planning/milestones/v1.0-phases/...` — source file path is the production location) — the canonical fetch-on-appear + `UIRefreshControl` + 4-state UIKit precedent. Phase 8 mirrors its state-machine structure; the only divergence is loading-visual (skeleton, not spinner).
- `validationLedger/App/AppContainer.swift` — composition root. Phase 8 adds a `loadListScreenFactory: (Role) -> UIViewController` (or similar) wired through each `*TabBarController` constructor, mirroring the Phase 5 `kycStatusScreenFactory` plumbing.
- `validationLedger/Core/Networking/APIClient.swift` — the typed-endpoint facade the VM (or a typed `LoadListProviding` service) consumes; UNCHANGED.

### Local repo intel that's stale — do NOT rely on
- `.planning/codebase/*.md` (all 7 files dated 2026-04-21, "brand-new SwiftUI scaffold") — predates all of v1.0. Phase 7 flagged this explicitly. The source tree is authoritative.

### Informational milestone context
- `.planning/milestones/v1.0-REQUIREMENTS.md` — archived v1.0 requirements (FOUND/ARCH/NET/AUTH/DEV/KYC/UPL/SHELL/SESS/GEO/SEC/LOG/CI). Cite if needed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`DS.Spacing` / `DS.Typography` / `DS.Colors`** (`validationLedger/UI/DesignSystem/`): every spacing, font, and color token the UI-SPEC names is already present and exported. Phase 8 consumes these tokens only — no raw literals.
- **`APIClient.request<E: APIEndpoint>(_:)`** (`Core/Networking/APIClient.swift`): the typed-endpoint facade. `APIClient.request(LoadListEndpoint(role: .broker))` returns the typed `LoadListEndpoint.Response` (which becomes the new `[LoadListItem]` envelope).
- **`MockLoadFixtureRegistry`** (`Core/Networking/Mock/MockLoadFixtureRegistry.swift`): the Phase 7 per-role registry; extended additively for the new `loads-list-degraded-counterparty.json` fixture.
- **`MockURLProtocol` latency/failure injection** (Phase 7 D-14): Phase 8 uses the latency injector to exercise `.loading` state and the failure injector to exercise `.error` state — zero new test-infra additions needed.
- **`ProfileViewController` + `kycStatusScreenFactory` pattern** (passed through every `*TabBarController.init`): the canonical "composition-root factory injected through the tab bar" pattern; Phase 8 mirrors it for `loadListScreenFactory`.
- **`UIRefreshControl` precedent** in `KYCStatusViewController`: the same attach-to-scroll-view + `addTarget(_:action:for: .valueChanged)` pattern; pull-to-refresh on the load list is identical wire-up.
- **`wrapTabsWithNavAndInstallAvatar`** (shared `RoleCoordinator` helper): wraps each tab in a `UINavigationController` and installs the avatar affordance — Phase 8 does NOT touch this machinery; the real Loads VC slots into the existing wrap automatically.
- **`Roles/Role.swift`** (`Role` enum): consumed by `LoadListEndpoint(role:)` and the new `LoadListViewModel(role:apiClient:)`.

### Established Patterns
- **MVVM + Coordinators** (project-wide): `LoadListViewController` (UIKit view) + `LoadListViewModel` (state machine + APIClient consumer). The VM publishes a single state enum `(loading / empty / loaded(loads) / error(message))` matching the UI-SPEC's locked state machine; the VC observes and switches the rendered subview.
- **Diffable datasource for any UICollectionView with mutation** (UI-SPEC's locked posture): `UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>`; snapshot-based updates from the VM's state changes.
- **Per-state JSON fixture per endpoint** (`validationLedgerTests/Networking/Fixtures/`): one JSON file per scenario; tests register the file they need after `MockURLProtocol.reset()`.
- **`nonisolated public struct` for typed endpoints** (every Phase 6/7 endpoint follows this): the modified `LoadListEndpoint` keeps its `nonisolated public struct` declaration; only the nested `Response` shape changes.
- **`.convertFromSnakeCase` decoding strategy** (`APIClient.defaultDecoder()`): handles `displayed_counterparty` → `displayedCounterparty` and `next_cursor` → `nextCursor` transparently — no explicit `CodingKey` enums needed on `LoadListItem`.
- **Fail-closed `Decodable` initializers** (Phase 7 D-09): `VerificationState` already decodes unknown values to `.unverified`; `LoadListItem.displayedCounterparty` defaults to `nil` via synthesized-optional `decodeIfPresent` — Phase 8 adds no new custom decoder logic on top.
- **44 pt minimum touch target** (UI-SPEC + Phase 3 precedent): the "Try again" CTA on `.error` and the pull-to-refresh affordance both honor the 44 pt floor. The cell's `automaticDimension` row height satisfies it intrinsically.

### Integration Points
- **NEW directory:** `validationLedger/UI/Components/` — hosts `VerificationBadgeView.swift` and `LoadStatusBadgeView.swift`. Phase 9 and Phase 10 reuse these.
- **NEW directory:** `validationLedger/Features/Loads/` — hosts `LoadListViewController.swift`, `LoadListViewModel.swift`, and `Cells/LoadRowCell.swift` + `Cells/SkeletonLoadRowCell.swift`.
- **NEW file:** `validationLedger/Core/Load/LoadListItem.swift` — the envelope from D-02.
- **MODIFIED:** `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` — `Response.loads: [Load]` → `Response.loads: [LoadListItem]`. Source-incompatible; the only call site is the new VM (Phase 8 introduces the first consumer), so blast radius is contained to this phase.
- **MODIFIED:** `validationLedger/Roles/{Broker,Shipper,Carrier,Dispatch,Factoring}/*TabBarController.swift` (5 files) — replace each tab's placeholder `makeTab(title:"Loads", systemImage:"shippingbox")` with the real Loads VC, factory-injected per-role through the `*TabBarController.init`.
- **MODIFIED:** `validationLedger/App/AppContainer.swift` — add a `loadListScreenFactory: (Role) -> UIViewController` (or analogous shape) wired into each `*TabBarController.init`, mirroring `kycStatusScreenFactory`. DEBUG-block extras: register the degraded edge fixture if a demo lane is exposed.
- **MODIFIED:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — additive: optionally register the new degraded edge fixture.
- **MODIFIED (fixture data):** `validationLedgerTests/Networking/Fixtures/loads-list-{broker,shipper,carrier,dispatch,factoring,empty}.json` (6 files) — wrap each row in the `LoadListItem` envelope (existing `Load` fields nest under `"load":`) and add `displayed_counterparty` per row. Counterparty selection per role MUST stay consistent with Phase 7 D-11 shared-world (same load = role-appropriate counterparty across role-list files).
- **NEW (fixture data):** `validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json` — at least one `nil`-counterparty row + one `.flagged`-counterparty row to drive the fail-closed UI tests.
- **NEW (tests):** under `validationLedgerTests/`: VM state-machine tests (4 transitions per UI-SPEC), endpoint decode tests covering the envelope + degraded fixture, snapshot tests for the two badge components + `LoadRowCell` + `SkeletonLoadRowCell` (silhouette match). Under `validationLedgerUITests/`: a 5-role smoke flow that taps "Loads" on each role shell and asserts the `loads-list` accessibility identifier resolves to a non-empty list (or the empty-state copy for fixtures returning zero rows).

</code_context>

<specifics>
## Specific Ideas

- **The `displayed_counterparty` field is a product surface, not just a contract field.** The 5 role fixtures should carry counterparty names that read realistically and that visibly demonstrate the platform thesis — e.g. on `loads-list-broker.json`, the carrier `TrustNode` on the double-brokered load (Phase 7 D-13's flagged archetype) MUST surface as a `.flagged` badge with a recognizable name in the row, so the demo flow shows the fraud signal even before the user taps into Phase 9's chain-of-trust graph. The list is where most users will *first* see fraud signals.
- **Phase 8 establishes the skeleton-with-shimmer pattern for the whole app.** That decision (D-10) reaches beyond this phase. The planner should document the pattern in a small reference comment block at the top of `SkeletonLoadRowCell.swift` so Phase 9+ and any future contributor knows to follow it.
- **The degraded-counterparty edge fixture (D-04 second half) is a security test, not just a UI test.** It exercises three guarantees simultaneously: `decodeIfPresent` handles the missing field, the row renders the neutral UNVERIFIED badge (never green), and the row's accessibility label does not leak a fake "verified" status to VoiceOver. A unit test on the decoder + a snapshot test on the row + an accessibility-label assertion together cover those guarantees.
- **The 5 role fixtures' counterparty selection MUST stay consistent with Phase 7's shared world (D-11).** If load VL-1001 appears in `loads-list-broker.json` (where the broker sees the carrier), the SAME VL-1001 appearing in `loads-list-shipper.json` MUST carry the broker as its counterparty — the shared-world narrative is the v1.1 demo. The planner should curate this cross-fixture consistency as part of the fixture-update plan.

</specifics>

<deferred>
## Deferred Ideas

- **Client-side filter chips / segmented status filter on the list** (e.g. Active / Past / Drafts segmented control above the list) — additive client-side filter applied to the diffable snapshot before render. ~half-day implementation when wanted; no contract change. Defer until a future phase or post-v1.1 when real list volumes justify it.
- **Client-side sections grouped by status bucket** (Active / Past / Drafts) — `enum LoadListSection` extension + classifier function + `headerMode = .supplementary`. ~half-day when real volume justifies it. The D-08 forward-looking implementation choices already make this strictly additive.
- **Infinite-scroll consumer for `nextCursor`** — additive VM upgrade when a real backend (or a multi-page fixture) starts returning paginated responses. Requires adding multi-page fixtures and a stale-cursor failure case. Out of v1.1 scope; the contract is ready (D-05).
- **Tap-to-reveal verification basis on the list-row badge** — UI-SPEC locked the badge as non-interactive on the list ("Phase 9 makes the graph-node container tappable, not the badge itself"). If product wants a quick tappable affordance later (e.g. long-press a flagged row to surface a popover with the verification basis), it can be added without contract change.
- **Back-port skeleton-with-shimmer to v1.0 surfaces** — the shipped `KYCStatusViewController` precedent stays on the centered `UIActivityIndicatorView`; Phase 8 does not retrofit. Could be a small cleanup phase later if visual consistency across all loading surfaces matters before TestFlight.

### Reviewed Todos (not folded)

- **`device-ci-biometric-infra.md`** — v1.0 physical-device CI infrastructure todo (a Face ID prompt hangs the device-CI lane as an unsatisfiable biometric input, manifesting as a 35-minute timeout). Matched on generic keywords (`status`, `pending`, `phase`); unrelated to a UI list feature. **Not folded.** Remains a carried v1.0 infrastructure item; the same todo was reviewed-but-not-folded in Phase 7.

</deferred>

---

*Phase: 8 — Role-Filtered Load List*
*Context gathered: 2026-05-19*
