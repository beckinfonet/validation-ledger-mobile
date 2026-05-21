# Phase 8: Role-Filtered Load List — Research

**Researched:** 2026-05-19
**Domain:** UIKit list rendering with diffable datasource + skeleton/shimmer loading + reusable badge components, all consuming a server-projected envelope from a `MockURLProtocol` fixture contract
**Confidence:** HIGH

## Summary

Phase 8 is a 100% UIKit screen built on patterns the codebase already has running in production — MVVM+Coordinators, `APIClient.request<E>`, `MockURLProtocol` per-fixture testing, `KYCStatusViewController`-style fetch-on-appear + `UIRefreshControl`, and DS-token-only styling. The novel ground is (a) introducing the app's first `UICollectionViewCompositionalLayout(.list)` + `UICollectionViewDiffableDataSource` surface, (b) establishing the skeleton-with-shimmer loading-state pattern that Phase 9+ will follow, and (c) wrapping every existing `loads-list-{role}.json` fixture in a new `LoadListItem { load: Load; displayedCounterparty: TrustNode? }` envelope without disturbing the Phase 7 `Load` aggregate. The contract extension (D-01..D-04) is purely additive at the wire layer; only one source file (`LoadListEndpoint.swift`) has its `Response.loads` element type changed, and the first consumer is born in this phase, so the blast radius is contained.

The phase's locked decisions (CONTEXT.md D-01..D-10 and UI-SPEC.md) leave only execution detail unresolved. Every reusable asset Phase 8 needs already exists in the source tree — the DS tokens, the typed `LoadListEndpoint`, the `MockLoadFixtureRegistry`, the latency/forced-failure injectors on `MockURLProtocol`, the `*TabBarController` factory-injection precedent (`kycStatusScreenFactory`), the `UIRefreshControl` precedent on `KYCStatusViewController`, and the `Testing`/XCTest split (Swift Testing for unit + XCUITest for UI smoke). One genuine gap surfaces in research: there is **no snapshot-test infrastructure in the repo** (no `pointfreeco/swift-snapshot-testing` SwiftPM dep, no hand-rolled image-diff helper). The UI-SPEC names snapshot tests as a verification surface; the planner must either (a) introduce a minimal hand-rolled `UIView → UIImage` baseline via `XCTAttachment` (precedent: `KYCThumbnailTests.swift:34` uses `UIGraphicsImageRenderer`) or (b) defer snapshot tests to a follow-up phase. Option (a) is recommended — zero new SwiftPM deps, fits CLAUDE.md's pre-approved-dependency rule.

**Primary recommendation:** Build `LoadListViewController` + `LoadListViewModel` mirroring `KYCStatusViewController` + `KYCStatusViewModel` precedent verbatim (fetch-on-appear, single state enum with `didSet` callback, `UIRefreshControl` attached directly to the collection view, `NSLocalizedString(_:value:)` copy, DS tokens only). Use `UICollectionViewCompositionalLayout.list` with `UICollectionLayoutListConfiguration` and a single section. Use `UIContentUnavailableConfiguration` as the iOS-17-native empty/error host via the VC's `contentUnavailableConfiguration` property — it gives the centered-symbol-heading-body-button layout the UI-SPEC describes for free with `setNeedsUpdateContentUnavailableConfiguration()` + `updateContentUnavailableConfiguration(using:)` as the state-driven update path. Render the skeleton state as a dedicated background view (a stack of `SkeletonLoadRowCell`-shaped subviews with a `CAGradientLayer` shimmer); keep it OFF the diffable datasource (Pitfall: thrashing the datasource on each state transition causes flicker — keep one datasource bound to real cells only, and toggle visibility on the skeleton background instead).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-role load list filtering | Fixture (mock backend) | — | LOAD-03 + D-15 + Phase 7 D-18 — server/fixture filters by role-in-path; iOS never re-filters. |
| Counterparty selection per row | Fixture (mock backend) | — | D-01 — `displayedCounterparty` is server-projected per row. iOS never selects from `ChainOfTrust.nodes`. |
| List rendering (cells, separators, layout) | iOS — `Features/Loads/` | — | Pure UIKit view layer over a passive `[LoadListItem]` payload. |
| Verification badge color/symbol mapping | iOS — `UI/Components/VerificationBadgeView.swift` | — | TRUST-02 — a single component renders the 4-state ramp; the ramp is locked by UI-SPEC. iOS is the only consumer. |
| Status badge label + color | iOS — `UI/Components/LoadStatusBadgeView.swift` | — | UI-SPEC locks the 13-case → 3-tone mapping; pure render-from-input. |
| State machine (loading / empty / loaded / error) | iOS — `LoadListViewModel` | — | View-state derivation lives on the VM (matches `KYCStatusViewModel` precedent). |
| Network errors → user copy | iOS — `LoadListViewModel` | — | Collapse `NetworkError` cases to `String` message per UI-SPEC; the error TEXT is iOS's call. |
| Trust-level computation | Out of scope (server-only) | — | D-18 + REQUIREMENTS.md Out-of-Scope — no client-side trust derivation. |
| Pagination consumption | Deferred (decoded only) | — | D-05 — `nextCursor` is decoded into state but never read. |
| Idempotency on POST actions | N/A this phase (no POSTs) | — | Phase 8 is read-only; the existing `IdempotencyInterceptor` is untouched. |
| iPad readable-width layout | iOS — `LoadListViewController` + compositional layout | — | UI-SPEC SC-#5 — `contentInsetsReference = .readableContent` on the list section. |
| Tab → real Loads VC wiring | iOS — `AppContainer.makeLoadListScreen(role:)` + `*TabBarController.init` | — | Mirrors the Phase 5 `kycStatusScreenFactory` composition-root precedent. |

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Row Counterparty Contract:**
- **D-01:** The list-row counterparty + verification badge data reaches iOS as a **server-projected `TrustNode?` per row** — already role-resolved server-side (Broker→carrier, Carrier→broker, Shipper→broker, Dispatch→broker, Factoring→carrier). iOS never selects which `TrustNode` to render.
- **D-02:** The projection lives in a new envelope type `LoadListItem { load: Load; displayedCounterparty: TrustNode? }` at `Core/Load/LoadListItem.swift`. `LoadListEndpoint.Response.loads` changes from `[Load]` to `[LoadListItem]`. `Load.swift` is **unchanged**.
- **D-03:** `displayedCounterparty` is optional; `nil` semantics are **fail-closed** — render the neutral-grey UNVERIFIED `VerificationBadgeView` with the counterparty name slot suppressed (or `—`). Matches Phase 7 D-09.
- **D-04:** Phase 8 owns the contract extension AND the fixture data — wrap every row in the new envelope across all 6 role/empty JSONs, plus a new `loads-list-degraded-counterparty.json`. Counterparty selection MUST stay consistent with Phase 7 D-11 shared-world. Update `MockLoadFixtureRegistry` to optionally register the degraded fixture in a DEBUG-gated demo lane.

**Pagination Posture:**
- **D-05:** `nextCursor` is decoded only — the VM stores it but never reads it. No infinite-scroll, no prefetch, no second-page fixture.

**List Sort and Grouping:**
- **D-06:** Server-supplied sort order. iOS renders in array order; iOS never sorts.
- **D-07:** Single flat section, no headers.
- **D-08:** Forward-looking implementation choices that keep future sections/filters strictly additive — `UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>` with `enum LoadListSection { case main }` from day one; `UICollectionViewCompositionalLayout(.list)`.

**Loading-State Visual:**
- **D-09:** Skeleton collection view with shimmer (6–8 grey placeholder cells, `CAGradientLayer` + `CABasicAnimation`). `.loading` renders the skeleton; `.loaded` swaps to real cells via the diffable datasource.
- **D-10:** Phase 8 establishes the app-wide "skeleton-with-shimmer" loading-state pattern. Phase 9+ should follow. The shipped `KYCStatusViewController` precedent (centered `UIActivityIndicatorView`) is preserved as-is — no back-port.

### Claude's Discretion

- Skeleton row count (6–8) and shimmer animation timing (~1.0–1.5s, infinite repeat).
- Tab-wiring strategy: factory-via-AppContainer (mirroring `kycStatusScreenFactory`) is the obvious continuation.
- VM error classification (decode/HTTP 4xx/network failure → all collapse to `.error(message: String)`).
- Service-layer abstraction: VM consumes `APIClient` directly OR a typed `LoadListProviding` protocol facade (the v1.0 precedent is direct-client).
- Exact `CGFloat` widths/heights for skeleton blocks.
- The Phase 7 fixture diff granularity (one PR-sized commit or per-fixture commits).
- Whether `MockLoadFixtureRegistry` exposes the degraded fixture as a dedicated `registerForDegradedDemo()` lane or via a query-flagged path.
- snake_case ↔ camelCase wire bridge: handled by `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy — no explicit `CodingKey` needed on `LoadListItem`.

### Deferred Ideas (OUT OF SCOPE)

- Client-side filter chips / segmented status filter on the list.
- Client-side sections grouped by status bucket (Active / Past / Drafts).
- Infinite-scroll consumer for `nextCursor`.
- Tap-to-reveal verification basis on the list-row badge (badge is non-interactive on the list).
- Back-port skeleton-with-shimmer to v1.0 surfaces (KYC status stays on its centered spinner).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **LOAD-03** | User sees a role-filtered load list — each of the 5 roles sees only the loads relevant to it, filtered server/fixture-side. | `LoadListEndpoint(role:)` already places role in the URL path; `MockLoadFixtureRegistry` already dispatches `GET /loads/{role-rawValue}` to per-role JSON. Phase 8 only authors per-role VC wiring + replaces the placeholder tab. No client-side filtering ever runs. |
| **LOAD-04** | Standard freight field set on each row — reference #, origin → destination, pickup/delivery dates, equipment, weight, rate, status badge, counterparty verification badge. | Every field is already on `Load` (verified in source). The two badges are net-new view components in this phase (`VerificationBadgeView` + `LoadStatusBadgeView` under `UI/Components/`). |
| **LOAD-07** | Empty, loading, and error states on the load list. | Per UI-SPEC, four states (loading / empty / loaded / error) drive the VC; the three exercised against `loads-list-empty.json` (empty), the latency injector on `MockURLProtocol` (loading), and the forced-failure injector on `MockURLProtocol` (error). Phase 7 Plan 04 shipped both injectors. |
| **LOAD-08** | Pull-to-refresh re-fetches the list. | `UIRefreshControl.refreshControl = …` attached to the collection view directly (iOS 17 native). Precedent: `KYCStatusViewController.scrollView.refreshControl = refreshControl`. |
| **TRUST-02** | Single reusable verification badge component, 4 states. | `VerificationBadgeView: UIView` at `UI/Components/VerificationBadgeView.swift`. The 4 cases are locked by `VerificationState` enum (`Core/Load/VerificationState.swift`). Phase 9 + 10 will reuse the same component. |

## Project Constraints (from CLAUDE.md)

- **UIKit-first, no SwiftUI on this surface.** All view code in this phase is `UIView` / `UIViewController` / `UICollectionViewListCell` programmatically — no `View` protocol, no `@State`, no `#Preview`. (SwiftUI is permitted ONLY for Settings / static lists; the load list is the highest-touch product surface and must stay UIKit.)
- **SwiftPM only.** No new external dependency unless on the pre-approved shortlist. Phase 8 adds **zero** new packages.
- **iOS 17.0 minimum deployment.** Phase 8 may safely use `UIContentUnavailableConfiguration`, `UICollectionViewCompositionalLayout.list`, `UICollectionLayoutListConfiguration`, `contentInsetsReference = .readableContent` — all are iOS 17 baseline APIs.
- **Zero PII in analytics or crash logs.** No counterparty `displayName`, no `partyID`, no load `referenceNumber` reaches `Logger` events. Match the `LogField.event`-only discipline already enforced by the project's PII-scrub logger.
- **All AI traffic backend-mediated** — N/A for this phase.
- **Backend-mediated; client never calls Anthropic** — N/A.
- **DS tokens only — no raw literals.** Every spacing, color, font is a `DS.Spacing.*` / `DS.Colors.*` / `DS.Typography.*` lookup; the only allowed exceptions are the 44pt touch-target floor (Apple HIG, not a DS token) and the badge corner radius `bounds.height / 2` (geometric, not a layout literal).
- **GSD workflow enforcement** — every file change MUST come from a GSD command. Phase 8's research/plan/execute path satisfies this; no out-of-band edits.

## Standard Stack

### Core (already in tree — Phase 8 adds zero new dependencies)

| Library / Framework | Version | Purpose | Why Standard |
|---------------------|---------|---------|--------------|
| UIKit | iOS 17 SDK | View layer (VCs, cells, layout, refresh control, content-unavailable view) | CLAUDE.md UIKit-first mandate; every existing role/Feature uses it. [VERIFIED: codebase grep across all `Features/` and `Roles/`] |
| Foundation | iOS 17 SDK | `Decodable`, `JSONDecoder`, `Decimal`, `Date`, `NumberFormatter`, `RelativeDateTimeFormatter` | Baseline iOS; matches existing fixture decode pattern. |
| Swift Testing | bundled | Unit tests (`@Suite`, `@Test`, `#expect`) | Phase 7 test suite uses it; precedent: `validationLedgerTests/Load/VerificationStateDecoderTests.swift:15` `import Testing`. STACK-03 ratified. |
| XCTest | bundled | UI tests (`XCUIApplication`) and any test that drives `MockURLProtocol` registries | Swift Testing does not support XCUIApplication; the 5-role smoke pattern (`RoleShellSmokeTests.swift`) is the precedent to mirror for a Phase 8 smoke test. |
| Core Animation (`CAGradientLayer`, `CABasicAnimation`) | iOS 17 SDK | Skeleton-shimmer effect (D-09) | First-party; no third-party shimmer library needed (and none would be allowed under STACK-04). |

### Supporting (codebase-internal, already shipped)

| Asset | Path | Purpose | When to Use |
|-------|------|---------|-------------|
| `APIClient` | `validationLedger/Core/Networking/APIClient.swift` | Typed-endpoint facade | VM calls `appContainer.apiClient.request(LoadListEndpoint(role:))` |
| `LoadListEndpoint` | `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` | `GET /loads/{role}` | Modify `Response.loads` element type from `[Load]` to `[LoadListItem]` |
| `MockURLProtocol.registerFixtureWithLatency<E>` | `Mock/MockURLProtocol.swift` lines 139–162 | Inject latency to exercise `.loading` state in tests | VM `.loading`-state assertion test |
| `MockURLProtocol.registerForcedFailure(for:method:kind:)` | `Mock/MockURLProtocol.swift` lines 175–186 | Inject HTTP error or `URLError` to exercise `.error` state | VM `.error`-state assertion test (e.g., `.urlError(.notConnectedToInternet)` and `.http(statusCode: 500, body:)`) |
| `MockLoadFixtureRegistry` | `Mock/MockLoadFixtureRegistry.swift` | DEBUG organic tap-through registry | Extend additively for the new degraded fixture (D-04 second half) |
| `DS.Spacing` / `DS.Typography` / `DS.Colors` | `UI/DesignSystem/` | Locked token namespace | Every UIView property reads tokens, not literals |
| `Role` enum | `validationLedger/Roles/Role.swift` | The 5-case role identity | Consumed by `LoadListViewModel(role:apiClient:)` and `LoadListEndpoint(role:)` |
| `KYCStatusViewController` | `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift` | Canonical UIKit fetch-on-appear + `UIRefreshControl` + 4-state precedent | Mirror its structure; only divergence is loading-visual (skeleton, not spinner) and the list-based content body |
| `KYCStatusViewModel` | same dir | Canonical VM state-machine precedent (`@MainActor final class`, nested `enum State`, `state.didSet` fires `onStateChange`) | Mirror exactly |
| `FixtureLoader` | `validationLedgerTests/Networking/FixtureLoader.swift` | Test bundle JSON loader | New endpoint decode tests reuse this verbatim |
| `wrapTabsWithNavAndInstallAvatar` | `Roles/RoleCoordinator.swift` | Wraps each tab in a nav controller + installs avatar item | UNTOUCHED; the real Loads VC slots into the existing wrap |

### Alternatives Considered (and rejected)

| Instead of | Could Use | Tradeoff — why rejected |
|------------|-----------|-------------------------|
| `UICollectionView.list` + diffable | `UITableView` + `UITableViewDiffableDataSource` | UI-SPEC lines 38–43 ratify the choice: cleaner iPad readable-content-guide behavior on compositional list, modern diffable. UITableView would also work but the UI-SPEC mandates exactly one of the two with no mixing. |
| `UIContentUnavailableConfiguration` (iOS 17) | Hand-rolled centered stack-view with symbol + heading + body + button | iOS 17 deployment minimum means we can take the native path; UI-SPEC §State Machine explicitly names `UIContentUnavailableView` for the empty/error states. Hand-rolled would re-implement what the system gives for free. |
| `pointfreeco/swift-snapshot-testing` SwiftPM dep | Hand-rolled `UIView → UIImage` baseline via `UIGraphicsImageRenderer` + `XCTAttachment` | STACK-04 + CLAUDE.md pre-approved-list rule — a new SPM dep needs explicit approval; precedent for hand-rolled image rendering exists at `validationLedgerTests/KYC/KYCThumbnailTests.swift:34`. |
| Typed `LoadListProviding` protocol facade between VM and APIClient | VM consumes `APIClient` directly | The v1.0 precedent is direct-client (see `KYCStatusViewModel.init(apiClient:store:keychain:logger:)`). A facade adds a layer for tests; for one read-only endpoint with no caching the precedent is cleaner. Planner's discretion (CONTEXT.md). |

**Installation:** None. No `swift package` additions.

**Version verification:** Not applicable — no external packages introduced in this phase.

## Package Legitimacy Audit

*Not applicable — Phase 8 introduces zero new SwiftPM dependencies. Every framework consumed (`UIKit`, `Foundation`, `Testing`, `XCTest`, `QuartzCore` for `CAGradientLayer` + `CABasicAnimation`) is bundled with the iOS SDK. The pre-approved shortlist in CLAUDE.md is not exercised.*

| Package | Registry | Disposition |
|---------|----------|-------------|
| (none) | — | No external packages installed |

## Architecture Patterns

### System Architecture Diagram

```
                       UITabBarController (per role)
                                  │
                                  │ tap "Loads" tab
                                  ▼
                       UINavigationController
                                  │
                                  │ root VC
                                  ▼
                        LoadListViewController  ◄────────  AppContainer.makeLoadListScreen(role:)
                                  │                                       │
                  ┌───────────────┼───────────────┐                       │ wired via the
                  ▼               ▼               ▼                       │ *TabBarController.init's
            UICollectionView   skeleton      contentUnavailable           │ loadListScreenFactory: (Role) -> UIViewController
            + Compositional    background    Configuration                │ (mirrors Phase 5 kycStatusScreenFactory)
            (.list)            view          (empty / error)              │
                  │                                                       │
                  │ diffable                                              │
                  ▼                                                       │
            UICollectionViewDiffableDataSource<                           │
              LoadListSection,                                            │
              LoadRowItem>                                                │
                                                                          │
                                  ▲                                       │
                                  │ snapshot(for state)                   │
                                  │                                       │
                       LoadListViewModel  ◄─────────────────────────────  ┘
                       (@MainActor final class)                            consumes
                                  │                                       APIClient
                                  │ state didSet → onStateChange          (initializer-DI)
                                  │
                                  │ State = { loading | empty | loaded([LoadListItem], nextCursor: String?) | error(String) }
                                  │
                                  │ fetchLoads() called from
                                  │   - viewWillAppear (fetch-on-appear)
                                  │   - UIRefreshControl .valueChanged (pull-to-refresh)
                                  ▼
                          APIClient.request(LoadListEndpoint(role:))
                                  │
                                  │ MockURLProtocol intercepts (DEBUG+.mock)
                                  ▼
                       MockLoadFixtureRegistry handler 1
                       (path: /loads/{role-rawValue})
                                  │
                                  │ returns 200 + JSON
                                  ▼
                       LoadListEndpoint.Response {
                         loads: [LoadListItem],    ← envelope (D-02)
                         nextCursor: String?       ← decoded, never read (D-05)
                       }
                                  │
                                  ▼
                       LoadRowCell  (Features/Loads/Cells/)
                       ├─ reference # label (DS.Typography.headline)
                       ├─ origin → destination label (DS.Typography.body)
                       ├─ pickup/delivery dates (DS.Typography.footnote)
                       ├─ equipment + weight (DS.Typography.footnote)
                       ├─ rate (DS.Typography.body, NumberFormatter .currency)
                       ├─ LoadStatusBadgeView   ◄── UI/Components/
                       └─ VerificationBadgeView ◄── UI/Components/
                                                    consumes
                                                    LoadListItem.displayedCounterparty?.verificationState
                                                    (nil → .unverified fail-closed render)
```

**Reader's trace (Broker user pulls to refresh a 10-row list):**
1. User taps "Loads" tab → `BrokerTabBarController`'s viewControllers[0] is the `LoadListViewController(role: .broker, ...)` returned by `loadListScreenFactory(.broker)`.
2. `viewWillAppear` fires → `Task { await viewModel.fetchLoads() }`.
3. VM sets `state = .loading`. The VC's `onStateChange` shows the skeleton background view (hidden until now) and starts the shimmer animation; the empty/error `contentUnavailableConfiguration` is set to `nil`.
4. VM awaits `apiClient.request(LoadListEndpoint(role: .broker))`. In DEBUG `MockURLProtocol` intercepts; handler 1 in `MockLoadFixtureRegistry` matches `/loads/broker` and returns the broker fixture's JSON (the rewritten envelope shape).
5. `LoadListEndpoint.Response` decodes via `APIClient.defaultDecoder()` (`.convertFromSnakeCase` + `.iso8601`); `displayed_counterparty` → `displayedCounterparty` happens transparently; `next_cursor` → `nextCursor` already proven by Phase 7 tests.
6. VM sets `state = .loaded([LoadListItem], nextCursor: nil)`. The VC stops the shimmer and hides the skeleton; applies a new diffable snapshot with one `LoadRowItem` per `LoadListItem` (the `LoadRowItem.id == LoadListItem.load.id`); the datasource diffs against any prior snapshot and animates the row insertions (default).
7. Pull-to-refresh path: `UIRefreshControl .valueChanged` → `fetchLoads()` again. The VM does NOT transition to `.loading` on a re-fetch when prior data is on screen (UI-SPEC: "the existing rows stay on screen during refresh and the `UIRefreshControl` spinner is the only visual indicator"); it transitions directly to the next terminal state on completion and calls `refreshControl.endRefreshing()`.

### Component Responsibilities

| File / Type | Responsibility |
|-------------|---------------|
| `validationLedger/Core/Load/LoadListItem.swift` (NEW) | The envelope value type (D-02). `public struct LoadListItem: Decodable, Sendable { public let load: Load; public let displayedCounterparty: TrustNode? }`. Pure value type — no logic. |
| `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` (MODIFIED) | `Response.loads: [Load]` → `Response.loads: [LoadListItem]`. The only source-incompatible change in this phase; the first consumer (the new VM) is born in this phase, so the change has zero downstream call sites to update outside Phase 8 itself. |
| `validationLedger/Features/Loads/LoadListViewModel.swift` (NEW) | `@MainActor public final class LoadListViewModel`. Holds `state: State`, `role: Role`, `apiClient: APIClient`. Exposes `func fetchLoads() async`. `state.didSet` fires `onStateChange`. |
| `validationLedger/Features/Loads/LoadListViewController.swift` (NEW) | UIKit programmatic VC. Owns the `UICollectionView`, the diffable datasource, the cell registration, the skeleton background view, the `UIRefreshControl`, and the four-state state machine handler. Mirrors `KYCStatusViewController` structure. |
| `validationLedger/Features/Loads/Cells/LoadRowCell.swift` (NEW) | `UICollectionViewListCell` subclass. Programmatic auto-layout. Composes `LoadStatusBadgeView` and `VerificationBadgeView`. Single `func configure(item: LoadListItem)` entry. Sets cell-level `accessibilityIdentifier` to `"loads-list.row.\(item.load.id)"`. |
| `validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift` (NEW) | Shimmer-driven placeholder cell. The 3-tier silhouette: anchor block, sub-anchor block, two short metadata blocks, two pill-sized blocks. Contains the `CAGradientLayer` + `CABasicAnimation`. **Pattern note** (D-10): the file's top comment block documents this as the app-wide "skeleton-with-shimmer" pattern for Phase 9+. |
| `validationLedger/Features/Loads/LoadRowItem.swift` (NEW) | Hashable identifier wrapper for diffable datasource: `struct LoadRowItem: Hashable { let id: String; let item: LoadListItem }`. `Hashable` keyed on `id` only (`id == LoadListItem.load.id`). The `item` is the render payload. (Note: `Load` is not `Hashable` itself; wrapping it in a key-only-hashable struct is the idiomatic diffable pattern.) |
| `validationLedger/Features/Loads/LoadListSection.swift` (NEW) | `enum LoadListSection: Hashable { case main }`. D-08 — additive enum extension keeps future client-side sections strictly additive. |
| `validationLedger/UI/Components/VerificationBadgeView.swift` (NEW) | `UIView` subclass. `func configure(state: VerificationState)` and `func configure(stateOrNil state: VerificationState?)` (the `nil` overload renders the `.unverified` fail-closed visual + sets `accessibilityLabel` accordingly). |
| `validationLedger/UI/Components/LoadStatusBadgeView.swift` (NEW) | `UIView` subclass. `func configure(status: LoadStatus)`. Maps the 13 cases to the 3 informational tones per UI-SPEC § "Status badge color rules." |
| `validationLedger/Roles/{Broker,Shipper,Carrier,Dispatch,Factoring}/*TabBarController.swift` (MODIFIED ×5) | Each gets a new constructor parameter `loadListScreenFactory: ((Role) -> UIViewController)?` (matching `kycStatusScreenFactory` shape). `viewDidLoad` replaces `Self.makeTab(title: "Loads", systemImage: "shippingbox")` with `loadListScreenFactory?(role) ?? Self.makeTab(...)` — preserving the existing makeTab fallback when no factory is supplied (defensive for tests that don't wire the factory). |
| `validationLedger/App/AppCoordinator.swift` (MODIFIED) | The 5 `*TabBarController` constructor calls in `roleCoordinator(for:container:)` gain a `loadListScreenFactory: { container.makeLoadListScreen(role: $0) }` argument, weakly capturing `container`. |
| `validationLedger/App/AppContainer.swift` (MODIFIED) | Adds `@MainActor func makeLoadListScreen(role: Role) -> UIViewController` mirroring the existing `makeKYCStatusScreen()`. No change to `init` other than the load-fixture-registry DEBUG block (already there for the per-role list handlers; only adds the optional degraded fixture if a demo lane is exposed). |
| `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` (MODIFIED — additive only) | Optional extension surface: a `static func registerForDegradedDemo()` lane (DEBUG-only) that registers the degraded fixture. Existing handlers byte-identical. |
| `validationLedgerTests/Networking/Fixtures/loads-list-{broker,shipper,carrier,dispatch,factoring,empty}.json` (MODIFIED ×6) | Wrap every row in the new envelope (existing `Load` fields nest under `"load":`). Add `"displayed_counterparty": {...}` (or `null`) per row. Empty fixture: `{"loads":[],"next_cursor":null}` stays effectively the same (zero rows means zero envelopes — but the **decode test** changes because `Response.loads` is now typed `[LoadListItem]`). |
| `validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json` (NEW) | At least one row with `"displayed_counterparty": null` and one row with `"displayed_counterparty": {... "verification_state": "flagged"}`. Drives the fail-closed render unit test + the accessibility-label assertion. |

### Recommended Project Structure

```
validationLedger/
├── Core/
│   ├── Load/
│   │   └── LoadListItem.swift                              [NEW — D-02 envelope]
│   ├── Networking/
│   │   ├── Endpoints/LoadListEndpoint.swift                [MODIFIED — element type change]
│   │   └── Mock/MockLoadFixtureRegistry.swift              [MODIFIED — additive degraded lane]
├── Features/
│   └── Loads/                                              [NEW dir]
│       ├── LoadListViewController.swift                    [NEW]
│       ├── LoadListViewModel.swift                         [NEW]
│       ├── LoadListSection.swift                           [NEW]
│       ├── LoadRowItem.swift                               [NEW]
│       └── Cells/
│           ├── LoadRowCell.swift                           [NEW]
│           └── SkeletonLoadRowCell.swift                   [NEW]
├── UI/
│   └── Components/                                         [NEW dir]
│       ├── VerificationBadgeView.swift                     [NEW — TRUST-02]
│       └── LoadStatusBadgeView.swift                       [NEW]
├── App/
│   ├── AppContainer.swift                                  [MODIFIED — makeLoadListScreen factory]
│   └── AppCoordinator.swift                                [MODIFIED — pass factory into 5 tab bars]
└── Roles/
    ├── Shipper/ShipperTabBarController.swift               [MODIFIED — factory param + replace placeholder]
    ├── Broker/BrokerTabBarController.swift                 [MODIFIED]
    ├── Carrier/CarrierTabBarController.swift               [MODIFIED]
    ├── Dispatch/DispatchTabBarController.swift             [MODIFIED]
    └── Factoring/FactoringTabBarController.swift           [MODIFIED]

validationLedgerTests/
├── Networking/
│   ├── Fixtures/                                           [MODIFIED ×6]
│   │   ├── loads-list-{broker,shipper,carrier,dispatch,factoring,empty}.json
│   │   └── loads-list-degraded-counterparty.json           [NEW]
│   └── LoadEndpointsTests.swift                            [MODIFIED — envelope-shape decode tests]
├── Load/
│   └── LoadListItemDecodeTests.swift                       [NEW — fail-closed nil decode test]
├── Features/
│   └── Loads/                                              [NEW dir]
│       ├── LoadListViewModelTests.swift                    [NEW — 4-state state machine]
│       ├── LoadRowCellTests.swift                          [NEW — snapshot via hand-rolled UIView→UIImage]
│       ├── VerificationBadgeViewTests.swift                [NEW — 4-state snapshot + a11y label]
│       ├── LoadStatusBadgeViewTests.swift                  [NEW — 13-state snapshot]
│       └── SkeletonLoadRowCellTests.swift                  [NEW — silhouette snapshot (frozen shimmer)]
└── validationLedgerUITests/
    └── LoadListSmokeTests.swift                            [NEW — 5-role tap-Loads-tab smoke]
```

### Pattern 1: Diffable Datasource with Cell Registration

**What:** Modern iOS 14+ pattern — register cell class declaratively with a configuration closure, drive updates via `NSDiffableDataSourceSnapshot`. Avoids index-path bookkeeping, animates inserts/deletes for free, and survives state-machine snapshot swaps without dataSource churn.

**When to use:** Every `UICollectionView` with mutating content. D-08 ratifies this for Phase 8 from day one.

**Example (synthesized from the canonical iOS 17 pattern + the precedent at `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift` for the surrounding VC structure):**

```swift
// Source pattern: useyourloaf.com / Apple iOS 17 documentation
// Surrounding VC structure mirrors KYCStatusViewController verbatim.

private lazy var dataSource: UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem> = {
    let registration = UICollectionView.CellRegistration<LoadRowCell, LoadRowItem> { cell, _, rowItem in
        cell.configure(item: rowItem.item)
        cell.accessibilityIdentifier = "loads-list.row.\(rowItem.id)"
    }
    return UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, rowItem in
        cv.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: rowItem)
    }
}()

private func applyLoaded(_ items: [LoadListItem]) {
    var snapshot = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
    snapshot.appendSections([.main])
    snapshot.appendItems(items.map { LoadRowItem(id: $0.load.id, item: $0) })
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

### Pattern 2: iOS 17 `UIContentUnavailableConfiguration` for empty + error states

**What:** Native iOS 17 idiom for replacing centered placeholder VCs. The VC's `contentUnavailableConfiguration` property is set to a `UIContentUnavailableConfiguration` value; the system renders a centered symbol + text + secondary text + button stack inside the VC's view. Trigger an update via `setNeedsUpdateContentUnavailableConfiguration()` and override `updateContentUnavailableConfiguration(using:)` to compute the config from the current state. [VERIFIED: Apple Developer Documentation; UI-SPEC §Design System.]

**When to use:** Empty state and error state on the load list (UI-SPEC §State Machine). NOT for the loading state — loading uses the skeleton (D-09).

**Example (synthesized — UIKit iOS 17 canonical):**

```swift
// Source: Apple Developer Documentation — UIContentUnavailableConfiguration
// (https://developer.apple.com/documentation/uikit/uicontentunavailableconfiguration)

override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
    switch viewModel.state {
    case .empty:
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "shippingbox")
        config.text = NSLocalizedString("loads.empty.title",
            value: "No loads yet",
            comment: "Load list — empty state heading")
        config.secondaryText = emptyBodyCopy(for: role)
        contentUnavailableConfiguration = config

    case .error(let message):
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "wifi.exclamationmark")
        config.text = NSLocalizedString("loads.error.title",
            value: "We couldn't load loads",
            comment: "Load list — error heading")
        config.secondaryText = message
        var buttonConfig = UIButton.Configuration.borderedProminent()
        buttonConfig.title = NSLocalizedString("loads.error.retry",
            value: "Try again",
            comment: "Load list — error retry CTA")
        config.button = buttonConfig
        config.buttonProperties.primaryAction = UIAction { [weak self] _ in
            Task { await self?.viewModel.fetchLoads() }
        }
        contentUnavailableConfiguration = config

    case .loading, .loaded:
        contentUnavailableConfiguration = nil
    }
}
```

The button's `accessibilityIdentifier` is set via the button-properties path — surface in the planner's task: confirm `UIContentUnavailableConfiguration` exposes a button-accessibility-identifier hook (it does NOT directly; the workaround is to set the identifier on the `UIContentUnavailableView` itself via the VC's view hierarchy walk, OR — cleaner — fall back to a hand-rolled stack-view for the error state so the retry button gets a stable `accessibilityIdentifier = "loads-list.error-state.retry"`). The UI-SPEC explicitly names this identifier as locked, so the hand-rolled fallback is the safer choice. **Recommend:** use `UIContentUnavailableConfiguration` for the empty state (no button, no identifier conflict) and a hand-rolled stack-view background for the error state (so the retry button's identifier is fully controllable). Decision belongs to the planner.

### Pattern 3: iPad readable-content-guide pinning for the list

**What:** The collection view stays full-width on the screen; the *section* inside the compositional list is inset to the readable content guide. The idiomatic iOS 17 approach is to set `contentInsetsReference = .readableContent` on the `NSCollectionLayoutSection` produced by `UICollectionViewCompositionalLayout.list(using:)`. [VERIFIED: Apple Developer Documentation `UIContentInsetsReference.readableContent`; Apple Developer Forums thread 679863.]

**Example:**

```swift
// Source: Apple Developer Forums thread 679863 + Apple Documentation
let listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
// listConfig customization (separator, swipe actions, etc.) goes here.

let layout = UICollectionViewCompositionalLayout { sectionIndex, env in
    let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: env)
    // SC-#5: pin section to readable content guide on regular width;
    // edge-to-edge on compact. iOS 17 automatically respects the
    // readableContentGuide-derived insets when this reference is set.
    section.contentInsetsReference = .readableContent
    return section
}
```

This is the cleanest path for compositional list layouts on iOS 17. The alternative (manually constraining the collection view's leading/trailing to the superview's `readableContentGuide`) would over-inset on iPhone compact (the readable guide is narrower than safe-area on compact too, just less obvious) and is harder to maintain across size-class changes.

### Pattern 4: Programmatic UIKit VC mirroring KYCStatusViewController

**What:** `@MainActor public final class …ViewModel` + `final class …ViewController: UIViewController`. VM owns `state: State` with `didSet { onStateChange?(state) }` and an async `fetch…()` method. VC sets `viewModel.onStateChange = { [weak self] in self?.handle(state: $0) }` in `viewDidLoad`. `viewWillAppear` triggers `Task { await viewModel.fetchLoads() }`. `UIRefreshControl` attaches to the scroll-view-like surface (here: the collection view) via the iOS 14+ direct attachment.

**When to use:** Every freshly-built UIKit feature in this codebase. The KYC status precedent is the v1.0 archetype.

**Example (KYCStatusViewController is the source; the snippet below shows the Load List adaptation):**

```swift
// Source: KYCStatusViewController.swift lines 138–183 — adapted

override func viewDidLoad() {
    super.viewDidLoad()
    title = NSLocalizedString("loads.nav_title", value: "Loads", comment: "Load list nav-bar title")
    view.backgroundColor = DS.Colors.background

    layoutCollectionView()
    layoutSkeletonBackground()
    layoutRefreshControl()
    bindViewModel()
}

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    Task { await viewModel.fetchLoads() }
}

private func bindViewModel() {
    viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
}

@objc private func pulledToRefresh() {
    Task { await viewModel.fetchLoads() }
}

private func handle(state: LoadListViewModel.State) {
    refreshControl.endRefreshing()
    switch state {
    case .loading:                  showSkeleton(); contentUnavailableConfiguration = nil
    case .empty:                    hideSkeleton(); setNeedsUpdateContentUnavailableConfiguration()
    case .loaded(let items, _):     hideSkeleton(); contentUnavailableConfiguration = nil; applyLoaded(items)
    case .error:                    hideSkeleton(); setNeedsUpdateContentUnavailableConfiguration()
    }
}
```

### Anti-Patterns to Avoid

- **Toggling the diffable datasource's cell registration between Skeleton and Real cells in the same datasource.** This is tempting (one datasource, two registrations, swap registration per state) but causes layout jank on the transition because the cell type changes mid-flight. Instead: a **single** datasource bound to `LoadRowCell` only; the skeleton lives as a **separate background view** that overlays the collection view while `.loading`. The collection view stays empty during loading (the datasource has zero snapshot items).
- **Re-filtering server data client-side.** D-06 + D-18 forbid this. No `loads.sorted { ... }`, no `loads.filter { $0.role == … }`, no client-side grouping. iOS renders exactly what the fixture returns.
- **Setting `accessibilityLabel` to "VERIFIED" on a `nil`/UNVERIFIED `displayedCounterparty`.** D-03 fail-closed: a degraded server response must render UNVERIFIED, and the VoiceOver-readable label must say "Unverified counterparty" (or similar), never inherit a default that leaks "verified" semantics. The `VerificationBadgeView`'s `configure(stateOrNil:)` overload is the locked entry point for the nil case; a unit test must assert the resulting `accessibilityLabel`.
- **Using `CADisplayLink`-driven shimmer instead of `CABasicAnimation`.** `CADisplayLink` ties the animation to the main-thread runloop — fine, but heavier than needed; `CABasicAnimation` runs on the render server, off-main, and is the standard iOS shimmer recipe.
- **Reading `nextCursor` anywhere in the VC.** D-05: the VM stores it, the VC never references it. A search for `nextCursor` in `Features/Loads/` should match the VM only.
- **Hardcoding role-shell strings or letting the role leak into screen chrome.** UI-SPEC: navigation title is "Loads" — never "Broker Loads," "Shipper Loads," etc.
- **Mixing `UICollectionView` and `UITableView`.** UI-SPEC §UIKit decision: use exactly one. The phase uses `UICollectionView`; no `UITableView` anywhere in the new code.
- **Forgetting `adjustsFontForContentSizeCategory = true` on a `UILabel`.** Every label MUST set this. Precedent: every `UILabel` in `KYCStatusViewController` sets it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| List view with diffable updates | Custom `UITableView` + `reloadData()` index-path math | `UICollectionViewDiffableDataSource` + `NSDiffableDataSourceSnapshot` | Apple's diffable engine handles inserts/deletes/moves with animations; manual index-path bookkeeping is error-prone and reloads thrash. |
| Empty / error placeholder VC | Custom centered stack-view subclass | `UIContentUnavailableConfiguration` (empty state) | iOS 17 baseline; matches the centered-symbol-title-body-button layout the UI-SPEC describes for free. (Error state may justify a hand-rolled stack-view so the retry button gets a stable `accessibilityIdentifier`.) |
| Currency formatting | `String(format: "$%.2f", rate)` | `NumberFormatter(style: .currency, locale: en_US)` | Locale-correct, handles thousands separators, "$" placement, decimal precision. Cell shows whole-dollar rates per UI-SPEC; the formatter handles that via `maximumFractionDigits = 0`. |
| Relative-date copy ("Pickup Tue 9 AM") | Manual `Calendar` math + day-of-week strings | `RelativeDateTimeFormatter` (close dates) + `DateFormatter` (further dates) | Apple's formatters are locale-correct and handle weekday-vs-date boundary at the system level. |
| Pull-to-refresh control | Custom drag-tracking + spinner view | `UIRefreshControl` (attached to collection view's `refreshControl` property on iOS 14+) | First-class API; works on `UICollectionView` directly without a wrapper `UIScrollView`. |
| Shimmer effect | Third-party shimmer library | `CAGradientLayer` + `CABasicAnimation` (Core Animation) | A 30-line recipe; STACK-04 forbids new SDK deps regardless. |
| Snake-case JSON decode | Manual `CodingKey` enums on every property | `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` (already set by `APIClient.defaultDecoder()`) | `LoadListItem` needs **zero** explicit `CodingKey`s; `displayed_counterparty` → `displayedCounterparty` is automatic. (Acronym fields like `partyID` STILL need the bridge — see `TrustNode` precedent.) |
| Date decoding | Manual `ISO8601DateFormatter` + custom init | `JSONDecoder.dateDecodingStrategy = .iso8601` (already set) | Phase 7 proved it works for every existing date field. |
| Skeleton + shimmer | Whole library / abstract framework | Plain `UIView` subclass with `CAGradientLayer` sublayer animated by `CABasicAnimation` | Skeleton is 6–8 grey blocks; library adds dependency weight + style drift for a 100-line recipe. |

**Key insight:** UIKit + Foundation in iOS 17 give us a built-in tool for every named requirement on this phase. The shipped codebase already exercises every one of these tools elsewhere. Phase 8 is integration, not invention.

## Common Pitfalls

### Pitfall 1: Shimmer animation does not restart after `prepareForReuse`

**What goes wrong:** `SkeletonLoadRowCell` adds its `CAGradientLayer` + `CABasicAnimation` on `init`; UICollectionView reuses cells aggressively; on reuse, the animation has detached from the layer and the next visible cell renders a frozen-grey block.

**Why it happens:** `CABasicAnimation` attached via `layer.add(_:forKey:)` survives `prepareForReuse` ONLY if the cell does not remove it. But `CAGradientLayer.frame` updates on layout (rotation, size-class change) may de-attach the animation. Also, removing the cell from the view hierarchy de-attaches the animation under iOS 14+.

**How to avoid:** Override `prepareForReuse` to re-add the animation:
```swift
override func prepareForReuse() {
    super.prepareForReuse()
    startShimmer()  // re-adds CABasicAnimation with stable forKey "shimmer"
}
```
Also call `startShimmer()` in `layoutSubviews()` after frame settles (to handle rotation/size-class changes), but guard with `if layer.animation(forKey: "shimmer") == nil` to avoid re-adding on every layout pass.

**Warning signs:** Pull-to-refresh on a long list with skeleton state visible — scroll the skeleton cells; if any go grey-frozen on reuse, this is the bug.

### Pitfall 2: Snake-case acronym bridge missing on `TrustNode.partyID` (but already handled in Phase 7)

**What goes wrong:** Decoder strategy `.convertFromSnakeCase` converts `party_id` → `partyId` (no trailing-letter capitalization), NOT `partyID`. A property named `partyID` without an explicit `CodingKey` would fail decode.

**Why it happens:** The synthesized `convertFromSnakeCase` produces `partyId`, mismatching the property. **Confirmed:** Phase 7's `TrustNode` already declares the explicit `CodingKeys` enum (`Core/Load/ChainOfTrust.swift` lines 122–132); `partyID` is the only acronym field bridged. `LoadListItem` itself has no acronym fields (`load` and `displayedCounterparty`), so it needs ZERO custom `CodingKey`s.

**How to avoid:** When authoring `LoadListItem.swift`, do NOT add a CodingKeys enum. Rely entirely on the synthesized decoder + `.convertFromSnakeCase`. A test should assert this by decoding the JSON `{"load": {...}, "displayed_counterparty": null}` and verifying `displayedCounterparty == nil`.

**Warning signs:** A decode test for `LoadListItem` returns `nil` on a present field, or throws `keyNotFound`.

### Pitfall 3: `displayed_counterparty: null` should decode to `nil`, NOT throw

**What goes wrong:** A custom decoder on `LoadListItem` that does `try container.decode(TrustNode.self, forKey: .displayedCounterparty)` would throw on `null`; the row would then fail decode and the entire list response would error out at `LoadListEndpoint.Response.loads`.

**Why it happens:** D-03's fail-closed contract requires `nil` to be a valid value. The synthesized `Decodable` initializer ALREADY handles this via `decodeIfPresent` for `Optional` properties.

**How to avoid:** Declare `public let displayedCounterparty: TrustNode?` — the synthesized decoder uses `decodeIfPresent`, which correctly handles both `null` and a missing key by returning `nil`. **Do not write a custom `init(from:)`.** A unit test must assert: `(a)` `{"load": {...}, "displayed_counterparty": null}` decodes to `displayedCounterparty == nil`; `(b)` `{"load": {...}}` (key omitted) also decodes to `displayedCounterparty == nil`. The Phase 7 `VerificationStateDecoderTests.swift` is the structural precedent for fail-closed decode tests.

**Warning signs:** A test that registers the degraded fixture and the entire response throws `DecodingError.valueNotFound` or `.typeMismatch`.

### Pitfall 4: Pull-to-refresh `endRefreshing()` race against snapshot apply

**What goes wrong:** A race where `endRefreshing()` is called before `dataSource.apply(snapshot, animatingDifferences:)` finishes can leave the refresh spinner visible while the new rows animate in, or vice versa.

**Why it happens:** `apply` is asynchronous (animated). The shipped `KYCStatusViewController` calls `endRefreshing()` at the top of `handle(state:)` BEFORE any view mutation; that ordering works there because there's only one symbol view and a few labels — not a collection-view diff.

**How to avoid:** Call `endRefreshing()` *after* the snapshot apply, NOT before. Use the `apply(_:animatingDifferences:completion:)` overload's completion handler:
```swift
dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
    self?.refreshControl.endRefreshing()
}
```
Or call it on `viewModel.state == .loaded(let items, _)` only after the snapshot is committed. This ensures the refresh affordance and the row-insert animation don't compete.

**Warning signs:** Visual test on slow simulator (or `MockURLProtocol.registerFixtureWithLatency` injecting 2s): refresh spinner disappears before rows finish animating.

### Pitfall 5: iPad split-view rotation breaks the readable-content inset

**What goes wrong:** `traitCollectionDidChange(_:)` doesn't fire on every layout — only on actual trait changes. If the layout was built once with `contentInsetsReference = .readableContent`, it should adapt automatically — but if any custom code uses `view.readableContentGuide` constraints, those don't auto-update.

**Why it happens:** The compositional layout's section-level inset reference IS dynamic and updates with the size class. A manual `view.readableContentGuide.leadingAnchor` constraint, by contrast, is set once and doesn't reactively re-resolve.

**How to avoid:** Stick with `section.contentInsetsReference = .readableContent` on the compositional layout — it's reactive. Do NOT build manual `view.readableContentGuide` constraints on the collection view itself. The UI-SPEC mentions both options ("`contentInset` / layout `contentInsetsReference = .readableContent` on `UICollectionLayoutListConfiguration` vs manual `readableContentGuide` constraint"); the **compositional-layout-section** path is the idiomatic iOS 17 choice.

**Warning signs:** XCUITest at iPad split-view: rotate device → list goes edge-to-edge or stays inset incorrectly.

### Pitfall 6: VoiceOver row order matches diffable snapshot order — but only if accessibility identifiers are set on the cells, not on subviews

**What goes wrong:** Setting `accessibilityIdentifier = "loads-list.row.\(loadID)"` on a SUBVIEW of the cell instead of on the cell itself means XCUITest cannot find the row deterministically (the cell is the accessibility-element host for the row).

**How to avoid:** Inside the cell registration closure, set the identifier on the cell:
```swift
let registration = UICollectionView.CellRegistration<LoadRowCell, LoadRowItem> { cell, _, rowItem in
    cell.configure(item: rowItem.item)
    cell.accessibilityIdentifier = "loads-list.row.\(rowItem.id)"   // ← on the CELL, not on a subview
}
```
And ensure inner badges have their own identifiers nested under the cell:
```swift
cell.verificationBadge.accessibilityIdentifier = "loads-list.row.\(rowItem.id).verification-badge"
cell.statusBadge.accessibilityIdentifier = "loads-list.row.\(rowItem.id).status-badge"
```
This matches the UI-SPEC's locked identifier map.

**Warning signs:** XCUITest looks for `app.cells["loads-list.row.VL-1001"]` and times out, but `app.staticTexts["REF-1001"]` is found.

### Pitfall 7: `LoadStatus.cancelled` raw-value compatibility

**What goes wrong:** `LoadStatus.cancelled` (American spelling, single L) is the case name; the wire form is `"cancelled"` (double L). Verified in source: `LoadStatus.swift:42` declares `case cancelled` with NO explicit rawValue, meaning the synthesized rawValue is `"cancelled"` (single L). **However the JSON fixtures use `"cancelled"` (double-L) per US conventions (no — Swift's enum case `cancelled` IS double-L; this is fine).** This is not a real pitfall — but the planner should verify the cell display label string in the UI-SPEC matches: "CANCELLED" (double L). Verified — UI-SPEC §Copywriting Contract line 196 lists "CANCELLED" double-L correctly.

(Listed here only because it's the kind of detail that gets misread on a quick scan; no action needed.)

### Pitfall 8: VerificationBadgeView Dynamic Type breaks the pill shape

**What goes wrong:** The badge is a pill (corner radius = `bounds.height / 2`). At larger Dynamic Type sizes, the badge's label needs more height; the pill height grows; the corner radius does NOT automatically recompute unless `layoutSubviews` re-derives it.

**How to avoid:** Override `layoutSubviews` to set `layer.cornerRadius = bounds.height / 2` after the label has been laid out. Verified by Apple HIG pill recipes. Pair this with `setContentCompressionResistancePriority(.required, for: .vertical)` on the label so the pill scales rather than truncating.

**Warning signs:** Increase iOS accessibility text size to xxxLarge; the badge corners become square instead of pill-shaped.

## Runtime State Inventory

> **Not applicable for this phase** — Phase 8 introduces a contract extension and net-new view code. No rename, no migration of stored state, no rebranding of existing keys.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified by grep over `validationLedger/Core/Storage` and `validationLedger/Core/Networking` for any persisted `Load`/`LoadListItem` reference. The contract addition is wire-only; no Keychain/UserDefaults/`KYCSessionStore` key carries load data. | None |
| Live service config | None — backend is `MockURLProtocol`; no external service to reconfigure. | None |
| OS-registered state | None — no Background Tasks, no `UNNotification`, no `pm2`-equivalent. | None |
| Secrets / env vars | None — `LoadListEndpoint` is unauthenticated against the mock; no new secret keys. | None |
| Build artifacts / installed packages | None — no SwiftPM dep added; no `.xcframework`; no DerivedData layout change. | None |

**Canonical question:** *After every file in the repo is updated, what runtime systems still have the old shape cached, stored, or registered?* — Answer: **None.** This is a greenfield-feature phase against an in-process mock contract. The only state to flush is the runtime-only `MockURLProtocol` handler array, which `MockLoadFixtureRegistry.registerAppDefaults()` (re)installs at every `AppContainer.init`.

## Environment Availability

> Skipped — Phase 8 has no external CLI / runtime / service dependency beyond the Xcode build toolchain already configured for v1.0. The simulator-lane test command from MEMORY.md `ios-test-suite-pitfalls.md` is the standard test invocation; nothing new required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode + iOS 17 simulator runtime | All build + test work | ✓ (v1.0 baseline) | iOS 17 SDK | — |
| `xcodebuild` scoped serial simulator-lane command | Test execution (per MEMORY) | ✓ | — | — |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) for unit tests; XCTest (`XCUIApplication`) for UI tests |
| Config file | None — bundled with Xcode toolchain |
| Quick run command | (project convention — scoped simulator-lane `xcodebuild test -only-testing:` invocation; see MEMORY `ios-test-suite-pitfalls.md`. Bare `xcodebuild test` gives ~67 false failures and is forbidden.) |
| Full suite command | scoped serial simulator-lane command (project convention) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command (scope) | File Exists? |
|--------|----------|-----------|---------------------------|-------------|
| **LOAD-03** | Per-role fixture is served on `GET /loads/{role}` and decodes into `[LoadListItem]` | unit (decode) | scoped `LoadEndpointsTests/LoadListEndpointTests` | ❌ Wave 0 — `LoadEndpointsTests.swift` needs envelope-aware decode assertions |
| **LOAD-03** | Each of 5 role tab shells, on "Loads" tap, shows a `loads-list` accessibility identifier and a non-empty cell set (or the empty-state copy for empty fixtures) | UI smoke | scoped `LoadListSmokeTests` 5-role suite | ❌ Wave 0 — new XCUITest file |
| **LOAD-04** | A `LoadRowCell` configured with a full `LoadListItem` exposes every standard field (reference, origin→destination, dates, equipment, weight, rate, status, verification) | unit (cell config) + snapshot | scoped `LoadRowCellTests` | ❌ Wave 0 |
| **LOAD-07** | VM transitions `loading → loaded` on a normal fixture | unit (state machine) | scoped `LoadListViewModelTests/loadedTransition` | ❌ Wave 0 |
| **LOAD-07** | VM transitions `loading → empty` on the empty fixture | unit | scoped `LoadListViewModelTests/emptyTransition` | ❌ Wave 0 |
| **LOAD-07** | VM transitions `loading → error` on a forced-failure (`MockURLProtocol.registerForcedFailure`) | unit | scoped `LoadListViewModelTests/errorTransitionFromForcedFailure` | ❌ Wave 0 |
| **LOAD-07** | VM `.loading` state is observed for the latency-injected fixture | unit (latency) | scoped `LoadListViewModelTests/loadingObservedWithLatency` | ❌ Wave 0 |
| **LOAD-08** | Pull-to-refresh re-fires `fetchLoads()` and updates the snapshot | unit (drives `valueChanged` on the refresh control under a hosted VC) | scoped `LoadListViewControllerTests/pullToRefreshRefires` | ❌ Wave 0 (optional — can be exercised via XCUITest if VC test infra is heavy) |
| **TRUST-02** | `VerificationBadgeView.configure(state: .verified)` renders the verified visuals + correct `accessibilityLabel` | unit + snapshot | scoped `VerificationBadgeViewTests` | ❌ Wave 0 |
| **TRUST-02** | `VerificationBadgeView.configure(stateOrNil: nil)` renders the UNVERIFIED visuals + does NOT include "verified" in the `accessibilityLabel` (fail-closed) | unit | scoped `VerificationBadgeViewTests/nilCounterpartyRendersUnverifiedAccessibilityLabel` | ❌ Wave 0 |
| **D-03 fail-closed** | `LoadListItem` decodes `displayed_counterparty: null` to `displayedCounterparty == nil` (`decodeIfPresent` synthesized) | unit | scoped `LoadListItemDecodeTests` | ❌ Wave 0 |
| **D-03 fail-closed** | `LoadListItem` decodes a present `displayed_counterparty` with `verification_state: "compromised"` (unknown) to `.unverified` (degrades via Phase 7's fail-closed `VerificationState.init(from:)`) | unit | scoped `LoadListItemDecodeTests/unknownVerificationStateDegradesToUnverified` | ❌ Wave 0 |
| **iPad SC-#5** | List renders at readable-content width on iPad regular | XCUITest trait override + screenshot | scoped `LoadListSmokeTests/iPadRegularReadableWidth` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** the test file(s) that cover the task's surface (e.g., the cell-config task runs `LoadRowCellTests` only).
- **Per wave merge:** the entire Phase 8 test set (`LoadListViewModelTests`, `LoadRowCellTests`, `VerificationBadgeViewTests`, `LoadStatusBadgeViewTests`, `SkeletonLoadRowCellTests`, `LoadListItemDecodeTests`, the modified `LoadEndpointsTests`, and the XCUITest smoke).
- **Phase gate:** Full suite green before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `validationLedgerTests/Load/LoadListItemDecodeTests.swift` — net-new file for envelope + fail-closed nil + unknown-verification-state-degrade assertions.
- [ ] `validationLedgerTests/Features/Loads/LoadListViewModelTests.swift` — net-new file for the 4-state machine.
- [ ] `validationLedgerTests/Features/Loads/LoadRowCellTests.swift` — cell-config unit assertions; snapshot via hand-rolled `UIView → UIImage` (no SnapshotTesting dep).
- [ ] `validationLedgerTests/Features/Loads/VerificationBadgeViewTests.swift` — 4-state visual + a11y assertions.
- [ ] `validationLedgerTests/Features/Loads/LoadStatusBadgeViewTests.swift` — 13-case label + tone-tier mapping.
- [ ] `validationLedgerTests/Features/Loads/SkeletonLoadRowCellTests.swift` — silhouette snapshot (frozen shimmer — disable `CABasicAnimation` via `UIView.setAnimationsEnabled(false)` or by not adding the animation in the test path).
- [ ] `validationLedgerUITests/LoadListSmokeTests.swift` — 5-role smoke flow + iPad readable-width trait test (mirrors `RoleShellSmokeTests.swift`'s `-MockOTPRoleForUITest` launch-arg pattern).
- [ ] (modified) `validationLedgerTests/Networking/LoadEndpointsTests.swift` — update the existing `loadListResponseDecodesEmptyEnvelope` to decode through `LoadListItem`; the existing test currently decodes `Response.loads` as `[Load]` semantically and will need its assertion to match the new element type.
- [ ] Snapshot-test infrastructure decision: **proposed approach** — hand-rolled `UIView → UIImage` baseline using `UIGraphicsImageRenderer` (precedent: `validationLedgerTests/KYC/KYCThumbnailTests.swift:34`) + `XCTAttachment` for visual diff in CI failures. The first PR that ships a snapshot test creates a small helper `UIViewSnapshot.image(of:size:)` extension under `validationLedgerTests/Snapshot/`. No new SwiftPM dep.

*(If no gaps: would say "None — existing test infrastructure covers all phase requirements" — but every test surface above is net-new for this phase.)*

## Security Domain

> Required because `security_enforcement` is not explicitly false in config. Phase 8 is a view-layer + envelope-shape phase; security touch points are narrower than a network or auth phase. The matrix below is scoped to *what Phase 8 actually exposes*.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth code in this phase. Network call rides the shipped session/Keychain stack. |
| V3 Session Management | no | No session mutations. `LogoutService` untouched. |
| V4 Access Control | yes (informational) | Per-role data scoping is fixture-side (LOAD-03 + D-15 + D-18). iOS does not implement access control here; backend/fixture does. The client must NEVER re-filter or re-shape the per-role payload (PROJECT.md Out-of-Scope: "client-side load filtering"). |
| V5 Input Validation | yes | Decoder is the contract boundary. `LoadStatus` (closed enum, hard throw on unknown) + `VerificationState` (fail-closed enum, degrades on unknown). `LoadListItem.displayedCounterparty: TrustNode?` uses `decodeIfPresent` for nil-tolerance. Wire-format injection (e.g., a malformed JSON from a future live backend) surfaces as `NetworkError.decodingFailed`, surfaced to the user as a generic error-state copy. |
| V6 Cryptography | no | No new crypto in this phase. Existing TLS pinning + Secure Enclave keys are off the codepath. |
| V7 Error Handling and Logging | yes | UI error copy must NOT include the raw `NSError.localizedDescription` if it leaks server detail. PII discipline: load `referenceNumber`, counterparty `displayName`, `partyID` MUST NOT reach `Logger` events. The shipped `LogField` is closed-enum + `.event` field only — match that discipline. |
| V11 Business Logic | yes | The fail-closed nil-counterparty render is a business-logic safety primitive (D-03). The platform thesis ("identity that cannot be spoofed") survives a degraded server response only if the client refuses to render misleading state. A unit test must lock this. |

### Known Threat Patterns for {UIKit + iOS 17 + MockURLProtocol fixture rendering}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| **Information disclosure via VoiceOver label on UNVERIFIED row** | Information disclosure | The `VerificationBadgeView`'s `accessibilityLabel` for the `.unverified` / `nil-counterparty` case must explicitly say "Unverified" (or "Counterparty not yet verified"). A snapshot of the label string is asserted in unit test; no default-inherited label that could imply trust. |
| **PII in log fields** | Information disclosure | Logger calls in this phase use `LogField.event` only — no counterparty names, no party IDs, no load reference numbers. The PIIScrubber regex coverage on the existing logger handles a defense-in-depth slip. |
| **Stale-fixture leakage across XCUITests** | Tampering / parallelism race | `MockURLProtocol.reset()` + `resetFailureHandlers()` at the top of every `@Test` body that mutates the registry. The serialization discipline from Phase 7 ("`@Suite(.serialized)` when the global mock handler array is mutated") applies here too. |
| **Client-side re-derivation of trust** | Tampering | D-18 forbids any `var isVerified: Bool { displayedCounterparty?.verificationState == .verified }`-style helper anywhere in the view layer. A SwiftLint custom rule (existing in project) or a manual `grep` gate in CR can catch this. |
| **Snapshot of UI exposes party `displayName` to a screenshot stored in CI** | Information disclosure (low) | Use synthetic party names ("Acme Trucking Inc." etc. — already used in the fixture set) in the snapshot test inputs. Never inject real customer names into test fixtures (PROJECT.md PII discipline). |
| **An unknown server-supplied `verification_state` superstring upgrades trust** | Tampering | Phase 7 D-09's fail-closed decoder already mitigates this at the `VerificationState.init(from:)` layer. The `LoadListItemDecodeTests` should include a regression test that an unknown `verification_state` value on the `displayed_counterparty.verification_state` field still decodes to `.unverified`. |

## Code Examples

### Example 1: `LoadListItem` envelope value type

**Source:** synthesized to match Phase 7 `TrustNode` decoder discipline (`Core/Load/ChainOfTrust.swift` lines 79–133) and CONTEXT.md D-02 exactly.

```swift
// validationLedger/Core/Load/LoadListItem.swift
//
// Phase 8 D-02: the server-projected list-row envelope.
//
// The list response is `[LoadListItem]` (replacing the prior `[Load]`).
// Each item carries the row's Load aggregate AND the counterparty TrustNode
// the server resolved for the signed-in role (D-01). `displayedCounterparty`
// is OPTIONAL — `nil` is a fail-closed signal (D-03) that the row must render
// as the neutral-grey UNVERIFIED badge, never as a verified affordance.
//
// === Wire-format / CodingKeys ===
// `.convertFromSnakeCase` (APIClient.defaultDecoder()) handles
// `displayed_counterparty` → `displayedCounterparty` cleanly — NO explicit
// CodingKey enum needed. The two property names (`load`, `displayedCounterparty`)
// have no trailing-acronym fields. TrustNode's own CodingKeys (Phase 7)
// handle the `partyID` bridge inside this envelope automatically.
//
// === Fail-closed nil decode (D-03) ===
// The synthesized `Decodable` initializer uses `decodeIfPresent` for the
// Optional property. JSON `null` → `nil`. Missing key → `nil`. Both paths
// route the row to the UNVERIFIED render. NO custom `init(from:)` is needed;
// adding one would risk masking the fail-closed discipline.

import Foundation

public struct LoadListItem: Decodable, Sendable {

    /// The Load aggregate for this row. Decoded directly from the nested
    /// `"load": {...}` object in the fixture (no shape change to Load itself).
    public let load: Load

    /// The server-projected counterparty TrustNode the signed-in role sees
    /// on this row's verification badge. `nil` is a fail-closed signal —
    /// the row renders the neutral-grey UNVERIFIED badge; the cell's
    /// counterparty name slot is suppressed (or shows `—`).
    public let displayedCounterparty: TrustNode?
}
```

### Example 2: `VerificationBadgeView` 4-state component with fail-closed nil

```swift
// validationLedger/UI/Components/VerificationBadgeView.swift
//
// Phase 8 TRUST-02 — the single reusable verification-state badge.
// Phase 9 + 10 will reuse this on detail headers and chain-of-trust graph nodes.
//
// Pill geometry: corner radius is bounds.height/2, recomputed in layoutSubviews
// so Dynamic Type scaling preserves the pill shape (Pitfall 8).
//
// Fail-closed nil (D-03): configure(stateOrNil: nil) renders the .unverified
// visuals AND sets an accessibilityLabel that NEVER inherits "verified"
// semantics. Unit-tested.

import UIKit

public final class VerificationBadgeView: UIView {

    private let symbolView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        return l
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    public override var intrinsicContentSize: CGSize {
        // Let the stack of [symbol, label] decide width; the label decides height.
        return super.intrinsicContentSize
    }

    private func setUp() {
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .staticText

        let stack = UIStackView(arrangedSubviews: [symbolView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false  // badge is non-interactive (UI-SPEC)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.xs),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.xs),
            symbolView.widthAnchor.constraint(equalTo: symbolView.heightAnchor),
        ])
    }

    /// Render a known VerificationState.
    public func configure(state: VerificationState) {
        apply(state: state)
    }

    /// Render a server-supplied OPTIONAL VerificationState. `nil` is fail-closed
    /// (D-03): renders UNVERIFIED visuals + an accessibilityLabel that does NOT
    /// inherit any "verified" semantics.
    public func configure(stateOrNil state: VerificationState?) {
        apply(state: state ?? .unverified)
    }

    private func apply(state: VerificationState) {
        switch state {
        case .verified:
            backgroundColor = DS.Colors.primary
            symbolView.image = UIImage(systemName: "checkmark.seal.fill")
            symbolView.tintColor = .white
            label.text = NSLocalizedString("verification_badge.verified", value: "VERIFIED",
                comment: "Verification badge label — verified")
            label.textColor = .white
            accessibilityLabel = NSLocalizedString("verification_badge.verified.a11y",
                value: "Counterparty verified", comment: "VoiceOver — verified")
        case .pending:
            backgroundColor = .systemYellow
            symbolView.image = UIImage(systemName: "clock.fill")
            symbolView.tintColor = .label
            label.text = NSLocalizedString("verification_badge.pending", value: "PENDING",
                comment: "Verification badge label — pending")
            label.textColor = .label
            accessibilityLabel = NSLocalizedString("verification_badge.pending.a11y",
                value: "Counterparty verification pending", comment: "VoiceOver — pending")
        case .unverified:
            backgroundColor = .tertiarySystemFill
            symbolView.image = UIImage(systemName: "questionmark.circle.fill")
            symbolView.tintColor = .secondaryLabel
            label.text = NSLocalizedString("verification_badge.unverified", value: "UNVERIFIED",
                comment: "Verification badge label — unverified")
            label.textColor = .secondaryLabel
            accessibilityLabel = NSLocalizedString("verification_badge.unverified.a11y",
                value: "Counterparty not verified", comment: "VoiceOver — unverified (fail-closed)")
        case .flagged:
            backgroundColor = DS.Colors.destructive
            symbolView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            symbolView.tintColor = .white
            label.text = NSLocalizedString("verification_badge.flagged", value: "FLAGGED",
                comment: "Verification badge label — flagged")
            label.textColor = .white
            accessibilityLabel = NSLocalizedString("verification_badge.flagged.a11y",
                value: "Counterparty flagged", comment: "VoiceOver — flagged")
        }
    }
}
```

### Example 3: VM state machine (mirroring `KYCStatusViewModel`)

```swift
// validationLedger/Features/Loads/LoadListViewModel.swift
//
// Phase 8 — the role-scoped load list state machine.
// Mirrors KYCStatusViewModel structure exactly:
//   - @MainActor public final class
//   - nested `enum State: Equatable, Sendable`
//   - `state` `didSet` fires `onStateChange`
//   - initializer-DI (ARCH-04)

import Foundation

@MainActor
public final class LoadListViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case empty
        case loaded(items: [LoadListItem], nextCursor: String?)  // D-05 — nextCursor stored, never read
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    public var onStateChange: ((State) -> Void)?

    public let role: Role
    private let apiClient: APIClient

    public init(role: Role, apiClient: APIClient) {
        self.role = role
        self.apiClient = apiClient
    }

    /// Fetch the role-scoped load list. Re-entrant — pull-to-refresh on a
    /// non-empty `.loaded` does NOT transition through `.loading` (UI-SPEC).
    public func fetchLoads() async {
        // First fetch (state == .loading already from init) shows skeleton.
        // Subsequent fetches (refresh) leave existing rows on screen until
        // the new state terminal arrives.
        if case .loaded = state {
            // pull-to-refresh — leave .loaded in place; the refreshControl
            // spinner is the only "loading" indicator. No state change.
        } else {
            state = .loading
        }

        do {
            let response = try await apiClient.request(LoadListEndpoint(role: role))
            if response.loads.isEmpty {
                state = .empty
            } else {
                state = .loaded(items: response.loads, nextCursor: response.nextCursor)
            }
        } catch {
            state = .error(message: Self.userFacingMessage(for: error))
        }
    }

    /// Map any NetworkError / DecodingError into copy that is safe for the UI.
    /// Per UI-SPEC: the message MUST NOT leak raw NSLocalizedDescription that
    /// reveals server detail (V7 — error handling). Generic copy for production
    /// network failures; DEBUG could substitute the underlying error for dev.
    private static func userFacingMessage(for error: Error) -> String {
        // V7 / UI-SPEC: fixed-copy mapping; never echo raw error
        NSLocalizedString("loads.error.generic",
            value: "Check your connection and try again. Your loads are safe.",
            comment: "Load list error-state body — generic, reassures the user no data is lost")
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled empty-state VC with centered stack | `UIContentUnavailableConfiguration` set on `viewController.contentUnavailableConfiguration` | iOS 17 (2023) | First phase in this codebase to use it; matches the iOS 17 deployment minimum already locked. |
| `UITableView` + `reloadData()` index-path bookkeeping | `UICollectionViewCompositionalLayout.list` + `UICollectionViewDiffableDataSource` + `UICollectionView.CellRegistration` | iOS 14 / 15 baseline; mature on iOS 17 | First UICollectionView with diffable in this codebase; sets the precedent for Phase 9 trust graph (graph uses `UIView` nodes, not a collection view — but the cell-registration style is reusable). |
| Manual `readableContentGuide` constraints on `view` | `section.contentInsetsReference = .readableContent` on the compositional layout's `NSCollectionLayoutSection` | iOS 17 | Reactive across size-class changes without `traitCollectionDidChange` plumbing. |
| Third-party shimmer libraries | `CAGradientLayer` + `CABasicAnimation` (Core Animation, always available) | N/A — first-party always available | Zero dependency; ~30 LOC. STACK-04 forbids a new SDK regardless. |

**Deprecated / outdated:**
- `UITableView` for new screens: not deprecated by Apple, but UI-SPEC §UIKit decision pins this codebase to `UICollectionView` going forward.
- `cellForRowAt`-style dataSource methods: superseded by `UICollectionView.CellRegistration` and diffable.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `UIContentUnavailableConfiguration` does NOT expose a stable `accessibilityIdentifier` hook for the embedded retry button. | Pattern 2 / Pitfall list | If wrong: we can use `UIContentUnavailableConfiguration` for both empty AND error states with the locked retry-button identifier (`"loads-list.error-state.retry"`). If right (the assumption): the error state should use a hand-rolled stack-view background, NOT `UIContentUnavailableConfiguration`. The planner should verify in a 15-minute spike — try assigning `config.buttonProperties.identifier` or walk the VC's view hierarchy for a button after the configuration renders. Medium impact (architectural choice). [ASSUMED] |
| A2 | Snapshot tests in this codebase can be implemented with a hand-rolled `UIGraphicsImageRenderer` baseline + `XCTAttachment`, with no new SwiftPM dep. | Validation Architecture | Low impact. The hand-rolled path is a well-known pattern and the existing `KYCThumbnailTests.swift` already uses `UIGraphicsImageRenderer`. If wrong, the next-cleanest path is adding `pointfreeco/swift-snapshot-testing` — which would need explicit user approval per STACK-04 / CLAUDE.md. [ASSUMED] |
| A3 | The 5 role tab bar controllers' constructor extension to accept `loadListScreenFactory: ((Role) -> UIViewController)?` is the cleanest match for the existing `kycStatusScreenFactory: (() -> UIViewController)?` pattern. | Component Responsibilities / Phase 8 wiring | Low impact. The alternative (a shared `RoleTabFactory` protocol) is over-engineered for one new factory; the planner has discretion to revisit. [ASSUMED] |
| A4 | `UIRefreshControl` attached directly to a `UICollectionView` (`collectionView.refreshControl = …`) works on iOS 17 with `UICollectionViewCompositionalLayout(.list)` without needing a wrapper `UIScrollView`. | Pattern 4 / state machine | Low impact — the existing `KYCStatusViewController` precedent attaches the refresh control to a `UIScrollView`. The iOS 14+ API makes `refreshControl` settable on any `UIScrollView` subclass, which `UICollectionView` is. [VERIFIED: Apple Developer Documentation — `UIScrollView.refreshControl` is the canonical attachment point and `UICollectionView` inherits from `UIScrollView`.] |
| A5 | The `LoadListItem` envelope wraps cleanly via the synthesized `Decodable` initializer (no custom `init(from:)`), and `decodeIfPresent` handles both `null` and missing-key for `displayedCounterparty: TrustNode?`. | Pitfall 3 + Example 1 | Low impact. Phase 7 already proves this pattern works for `Load.tenderEligibility: TenderEligibility?` and `Load.respondByAt: Date?` (verified in `Load.swift`). The decoder strategy `.convertFromSnakeCase` on `APIClient.defaultDecoder()` has been exercised across every Phase 6/7 endpoint. [VERIFIED: cross-referenced Load.swift + APIClient.swift + LoadEndpointsTests.swift] |
| A6 | The 6 existing fixtures + 1 new degraded fixture should be hand-edited per-file rather than regenerated from a single source-of-truth document. | Component Responsibilities | Low impact. Phase 7's `MockLoadFixtureRegistry.swift` already inlines the JSON literally (per its file-header comment lines 27–47); there is no fixture-generation script. The hand-edit-per-file approach mirrors the Phase 7 fixture-authoring discipline. The cost is the cross-fixture consistency hand-curation D-04 calls out. [VERIFIED via reading the registry file's documentation] |
| A7 | `MockURLProtocol.register` handler order (first non-nil wins) means the new envelope-shape fixtures, registered via the same per-role list handler in `MockLoadFixtureRegistry`, will continue to be served correctly after the JSON edit — no test-infra change needed. | Component Responsibilities | Low impact. Confirmed in `MockLoadFixtureRegistry.swift` lines 91–99 — handler 1 reads `listPayloads[suffix]` and serves the matching JSON; the wire-shape change is invisible to the registry. [VERIFIED] |
| A8 | The accessibility label on the `.unverified` / nil-counterparty badge needs to be wired in NSLocalizedString form (matching the codebase's i18n discipline) and asserted via a unit test against a snapshot of `view.accessibilityLabel`. | Security Domain / Code Example 2 | Low impact. The pattern matches `LimitedTrustBannerView.swift:77-82` exactly. [VERIFIED] |

**If this table is empty:** would say "no user confirmation needed" — but A1 specifically merits the planner's attention as the only assumption with a meaningful architectural fork.

## Open Questions (RESOLVED)

1. **Does `UIContentUnavailableConfiguration.button` expose an accessibility identifier hook for XCUITest stable selection?**
   - What we know: The configuration's button properties allow setting `primaryAction`, `title`, and standard `UIButton.Configuration` settings; UI-SPEC requires `accessibilityIdentifier = "loads-list.error-state.retry"`.
   - What's unclear: Whether `config.buttonProperties` (or the rendered `UIContentUnavailableView`) exposes the button's identifier hook directly, or whether it requires a view-hierarchy walk.
   - Recommendation: 15-minute spike at the start of the error-state task. If no clean hook: use a hand-rolled stack-view for the error state (same Apple symbol + heading + body + button shape, but full control over `accessibilityIdentifier`). The empty state still uses `UIContentUnavailableConfiguration` (no button, no identifier conflict).
   - **RESOLVED:** Planner surfaced the spike as Task 1 of `08-03-PLAN.md` (15-min `UIContentUnavailableConfiguration.button` accessibility-identifier probe). The spike's verdict gates the implementation choice in Task 4 of the same plan (native config vs hand-rolled stack-view). Empty state stays on `UIContentUnavailableConfiguration` regardless.

2. **Should the degraded-counterparty fixture be registered into the default `MockLoadFixtureRegistry.registerAppDefaults()` lane, or kept in a separate `registerForDegradedDemo()` lane?**
   - What we know: CONTEXT.md Claude's Discretion paragraph defers this. The default lane is the organic DEBUG tap-through; the user would not normally see the degraded fixture there.
   - What's unclear: Whether the user wants a DEBUG menu item ("Inject degraded counterparty into Loads list") or whether the degraded fixture is test-only.
   - Recommendation: keep it test-only by default. The `MockLoadFixtureRegistry` gets a static `registerForDegradedDemo()` lane that is NEVER called from `AppContainer.init` — only by the unit test that exercises the fail-closed render path. A future DEBUG-menu entry could expose it without breaking the contract. (Recommendation can be ratified in the planner's pass without re-asking the user.)
   - **RESOLVED:** Test-only `registerForDegradedDemo()` lane on `MockLoadFixtureRegistry` per Task 3 of `08-01-PLAN.md`. Never called from `AppContainer.init`; only the fail-closed render test calls it. Matches the existing `KYCUITestSeed` static-flag discipline.

3. **Does the planner want the snapshot tests in Wave 0 (build-out wave) or deferred to a follow-up cleanup phase?**
   - What we know: There is no SnapshotTesting infrastructure in the repo; introducing the hand-rolled helper is ~50 LOC.
   - What's unclear: Whether the planner counts snapshot tests as in-scope for Phase 8 or a "nice-to-have."
   - Recommendation: include them — they are the highest-leverage test surface for the two new badges (TRUST-02) and the silhouette-match assertion D-09 names explicitly. The hand-rolled helper is a one-time, ~50-LOC cost. Skipping them risks regressions on Dynamic Type / dark-mode / pill-shape behavior.
   - **RESOLVED:** Snapshot tests are in-scope for Phase 8. The hand-rolled `validationLedgerTests/Support/UIKitSnapshot.swift` helper lands in `08-01-PLAN.md` (Wave 0 dependency); snapshot baselines for `VerificationBadgeView` and `LoadStatusBadgeView` are in `08-02-PLAN.md`; `LoadRowCell` and `SkeletonLoadRowCell` snapshot baselines are in `08-03-PLAN.md`. Zero new SwiftPM deps (STACK-04 / CLAUDE.md).

## Sources

### Primary (HIGH confidence)
- Source tree — every cited file path was read directly (no codebase-map reliance, per CONTEXT.md `stale intel warning`). Specifically:
  - `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift`
  - `validationLedger/Core/Networking/APIClient.swift`
  - `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift`
  - `validationLedger/Core/Networking/Mock/MockURLProtocol.swift`
  - `validationLedger/Core/Load/Load.swift`
  - `validationLedger/Core/Load/ChainOfTrust.swift`
  - `validationLedger/Core/Load/VerificationState.swift`
  - `validationLedger/Core/Load/LoadStatus.swift`
  - `validationLedger/UI/DesignSystem/{Spacing,Typography,Colors}.swift`
  - `validationLedger/UI/LimitedTrustBannerView.swift`
  - `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift`
  - `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift`
  - `validationLedger/Roles/Shipper/ShipperTabBarController.swift`
  - `validationLedger/Roles/Broker/BrokerTabBarController.swift`
  - `validationLedger/Roles/Carrier/CarrierTabBarController.swift`
  - `validationLedger/Roles/RoleCoordinator.swift`
  - `validationLedger/Roles/Role.swift`
  - `validationLedger/App/AppContainer.swift`
  - `validationLedger/App/AppCoordinator.swift`
  - `validationLedgerTests/Networking/LoadEndpointsTests.swift`
  - `validationLedgerTests/Networking/FixtureLoader.swift`
  - `validationLedgerTests/Networking/Fixtures/loads-list-broker.json`
  - `validationLedgerTests/Networking/Fixtures/loads-list-empty.json`
  - `validationLedgerUITests/RoleShellSmokeTests.swift`
  - `validationLedgerTests/Load/VerificationStateDecoderTests.swift`
- Planning context — `08-CONTEXT.md`, `08-UI-SPEC.md`, `07-CONTEXT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `PROJECT.md`, `CLAUDE.md`.
- Apple Developer Documentation — [UIContentUnavailableConfiguration](https://developer.apple.com/documentation/uikit/uicontentunavailableconfiguration), [UICollectionLayoutListConfiguration](https://developer.apple.com/documentation/uikit/uicollectionlayoutlistconfiguration), [UIContentInsetsReference.readableContent](https://developer.apple.com/documentation/uikit/uicontentinsetsreference/readablecontent).
- MEMORY auto-context — `ios-test-suite-pitfalls.md` (use the scoped serial simulator-lane command, NOT bare `xcodebuild test`).

### Secondary (MEDIUM confidence, cross-verified)
- [Use Your Loaf — Creating Lists with Collection View](https://useyourloaf.com/blog/creating-lists-with-collection-view/) — pattern for `UICollectionView.CellRegistration` + diffable.
- [Use Your Loaf — Content Unavailable Views](https://useyourloaf.com/blog/content-unavailable-views/) — `UIContentUnavailableConfiguration` iOS 17 idioms.
- [Apple Developer Forums thread 679863 — Modern Collection Views and Readable Content Width](https://developer.apple.com/forums/thread/679863) — `contentInsetsReference = .readableContent` on the compositional layout section.

### Tertiary (LOW confidence — flagged for validation)
- None for Phase 8. Every architectural and API claim above is rooted in either source-tree verification or first-party Apple documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every framework is iOS-bundled and exercised in the existing codebase.
- Architecture: HIGH — `KYCStatusViewController` + `KYCStatusViewModel` are the locked precedent and were read directly.
- Pitfalls: HIGH — drawn from the source tree's existing patterns (CodingKeys discipline in `ChainOfTrust.swift`, refresh-control attachment in `KYCStatusViewController.swift`) plus iOS 17 documented behaviors.
- Snapshot infra: MEDIUM (flagged as `[ASSUMED]` A2) — no existing infra; the hand-rolled `UIGraphicsImageRenderer` approach has precedent at `KYCThumbnailTests.swift:34` but is not yet generalized into a snapshot helper.
- `UIContentUnavailableConfiguration` retry-button accessibility-identifier hook: MEDIUM (flagged as `[ASSUMED]` A1) — meriting a 15-minute spike.

**Research date:** 2026-05-19
**Valid until:** 2026-06-18 (30 days — stable iOS 17 surface; no API churn expected within the v1.1 cycle)
