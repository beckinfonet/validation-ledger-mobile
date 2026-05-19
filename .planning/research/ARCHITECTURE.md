# Architecture Research

**Domain:** Native iOS feature integration — adding the load domain (list / detail / trust-graph / per-role actions) to a shipped UIKit / MVVM-C / contract-first app
**Researched:** 2026-05-19
**Confidence:** HIGH — every claim below is grounded in the actual v1.0 source tree (`validationLedger/`, ~28,700 LOC), not training data. The v1.0 architecture is settled and the patterns are observed directly in shipped files.

---

## Scope note

This is a SUBSEQUENT-milestone research doc. The v1.0 architecture exists and is not up for redesign. The question is *integration*: where v1.1's load features attach to the existing UIKit AppDelegate + SceneDelegate + AppContainer + AppCoordinator skeleton, the `Core/` modules, the `Features/`+`Roles/` split, and the contract-first `MockURLProtocol` networking. Everything below is either **NEW** (a file/folder v1.1 creates) or **MODIFIES** (an existing v1.0 file v1.1 edits). The two are tagged explicitly because the roadmapper needs that split.

One correction up front: `.planning/codebase/*.md` is **stale** (dated 2026-04-21, "brand-new SwiftUI scaffold"). It predates all of v1.0. The real, current layout is the `validationLedger/` tree on disk — that is what this doc is built against. `TechStack.md` referenced by `CLAUDE.md`/`PROJECT.md` is **not present at the repo root** (removed in commit `7e14f7d` / archived); PROJECT.md is the authoritative scope source and was used instead.

---

## Standard Architecture

### System Overview — v1.1 load slice over the v1.0 skeleton

```
┌──────────────────────────────────────────────────────────────────────┐
│  App/ (composition root — MODIFIED, not restructured)                  │
│  AppContainer  ──makeLoadListScreen(role:)──┐  (new factory methods)    │
│                ──makeLoadDetailScreen(id:)──┤                          │
├─────────────────────────────────────────────┼─────────────────────────┤
│  Roles/  (5 tab-bar shells — MODIFIED)        │                         │
│  ShipperTabBarController … FactoringTabBar    │  each swaps its         │
│      └─ "Loads" tab placeholder ──────────────┘  placeholder VC for     │
│                                                   a real Loads stack    │
├──────────────────────────────────────────────────────────────────────┤
│  Features/Loads/  (NEW feature module — the bulk of v1.1)               │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────────────────┐      │
│  │ LoadList   │  │ LoadDetail │  │ TrustGraph (child component)  │      │
│  │ Coordinator│  │ Coordinator│  │  TrustGraphView + ViewModel   │      │
│  │  VC + VM   │  │  VC + VM   │  │  (no coordinator of its own)  │      │
│  └─────┬──────┘  └─────┬──────┘  └──────────────┬───────────────┘      │
│        │ push(loadID)  │ child VC               │ tap → present sheet  │
│        └───────────────┴────────────────────────┘                      │
├──────────────────────────────────────────────────────────────────────┤
│  Core/  (shared kernel — MODIFIED + small NEW additions)                │
│  ┌──────────────────────────┐  ┌────────────────────────────────────┐  │
│  │ Core/Networking/         │  │ Core/Load/  (NEW small module)      │  │
│  │  Endpoints/              │  │  Load, ChainOfTrust, TrustNode,     │  │
│  │   LoadListEndpoint   NEW │  │  LoadStatus, LoadAction,            │  │
│  │   LoadDetailEndpoint NEW │  │  RoleLoadPolicy  (pure value types  │  │
│  │   LoadActionEndpoint NEW │  │  + role-action policy table)        │  │
│  │  Mock/                   │  └────────────────────────────────────┘  │
│  │   MockDefaultFixtures +  │  consumed by ALL 5 role shells; no       │
│  │   MockLoadFixtureRegistry│  feature owns the domain types           │
│  └──────────────────────────┘                                          │
│  Core/Networking/APIClient — UNCHANGED (typed-endpoint facade)          │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | NEW / MODIFIES | Module path |
|-----------|----------------|----------------|-------------|
| `Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadParty`, `VerificationState` | Pure `Decodable & Sendable` value types — the load domain model. Shared by all 5 roles. | NEW | `validationLedger/Core/Load/` |
| `LoadAction` + `RoleLoadPolicy` | Enum of tender/accept/reject + a pure table mapping `(Role, LoadStatus) → [LoadAction]`. The single source of truth for "what can this role do to this load." | NEW | `validationLedger/Core/Load/` |
| `LoadListEndpoint`, `LoadDetailEndpoint`, `LoadActionEndpoint` | Typed `APIEndpoint` conformers — the load-domain wire contract. | NEW | `validationLedger/Core/Networking/Endpoints/` |
| `MockLoadFixtureRegistry` + JSON fixtures | Registers `MockURLProtocol` handlers for the 3 load endpoints; new fixture files. | NEW | `validationLedger/Core/Networking/Mock/` + `validationLedgerTests/Networking/Fixtures/` |
| `LoadsCoordinator` | Owns the Loads-tab `UINavigationController`; pushes list → detail; mediates action results. One per role tab (5 instances, same class). | NEW | `validationLedger/Features/Loads/` |
| `LoadListViewController` + `LoadListViewModel` | Role-filtered load list. VM calls `APIClient.request(LoadListEndpoint(role:))`. | NEW | `validationLedger/Features/Loads/` |
| `LoadDetailViewController` + `LoadDetailViewModel` | Single load detail; hosts the trust-graph child VC; surfaces the role's action set. | NEW | `validationLedger/Features/Loads/` |
| `TrustGraphViewController` + `TrustGraphView` + `TrustGraphViewModel` | The interactive chain-of-trust node-graph. A reusable **child view controller**, not a coordinator. | NEW | `validationLedger/Features/Loads/TrustGraph/` |
| 5 role tab-bar controllers | Swap the placeholder "Loads" tab `UIViewController` for a real `LoadsCoordinator.rootViewController`. | MODIFIES | `validationLedger/Roles/<Role>/` |
| `AppContainer` | Gains `makeLoadListScreen(role:)` / `makeLoadDetailScreen(loadID:)` composition-root factories; registers `MockLoadFixtureRegistry` in the DEBUG mock block. | MODIFIES | `validationLedger/App/AppContainer.swift` |
| `APIClient`, `MockURLProtocol`, `APIEndpoint` | **UNCHANGED.** The typed-endpoint facade already accepts any new `APIEndpoint`; mock matching is path+method-generic. | — | `validationLedger/Core/Networking/` |

---

## Recommended Project Structure

```
validationLedger/
├── Core/
│   ├── Load/                               # NEW — shared load domain kernel
│   │   ├── Load.swift                      #   Load, LoadStop, LoadStatus
│   │   ├── ChainOfTrust.swift              #   ChainOfTrust, TrustNode, LoadParty,
│   │   │                                   #   VerificationState  (graph data model)
│   │   ├── LoadAction.swift                #   enum LoadAction { .tender/.accept/.reject }
│   │   └── RoleLoadPolicy.swift            #   pure (Role, LoadStatus) → [LoadAction] table
│   │
│   └── Networking/
│       ├── Endpoints/
│       │   ├── LoadListEndpoint.swift      # NEW — GET  /loads?role=…
│       │   ├── LoadDetailEndpoint.swift    # NEW — GET  /loads/{id}
│       │   └── LoadActionEndpoint.swift    # NEW — POST /loads/{id}/actions
│       └── Mock/
│           └── MockLoadFixtureRegistry.swift  # NEW — registers the 3 load handlers
│                                              #       (mirrors MockOTPRoleFixtureRegistry)
│
├── Features/
│   └── Loads/                              # NEW — the v1.1 feature module
│       ├── LoadsCoordinator.swift          #   owns the Loads-tab UINavigationController
│       ├── List/
│       │   ├── LoadListViewController.swift
│       │   ├── LoadListViewModel.swift
│       │   └── LoadListCell.swift
│       ├── Detail/
│       │   ├── LoadDetailViewController.swift
│       │   ├── LoadDetailViewModel.swift
│       │   └── LoadActionBar.swift         #   tender/accept/reject UIControl strip
│       └── TrustGraph/
│           ├── TrustGraphViewController.swift   # child VC
│           ├── TrustGraphView.swift             # the node-graph UIView (custom drawing)
│           ├── TrustGraphViewModel.swift        # layout + per-node verification state
│           └── TrustNodeDetailViewController.swift  # the tap-through party sheet
│
├── Roles/
│   ├── ShipperTabBarController.swift       # MODIFIES — "Loads" tab → LoadsCoordinator
│   ├── BrokerTabBarController.swift        # MODIFIES — same
│   ├── CarrierTabBarController.swift       # MODIFIES — same
│   ├── DispatchTabBarController.swift      # MODIFIES — same
│   └── FactoringTabBarController.swift     # MODIFIES — same
│
└── App/
    └── AppContainer.swift                  # MODIFIES — load factories + mock registration

validationLedgerTests/Networking/Fixtures/  # NEW JSON fixtures
    ├── loads-list-{shipper,broker,carrier,dispatch,factoring}.json
    ├── load-detail-success.json
    ├── load-detail-not-found.json
    ├── load-action-success.json
    └── load-action-conflict.json           # 409 — stale action / already-tendered
```

### Structure Rationale

- **`Core/Load/` is a NEW shared kernel — not a feature, not duplicated per role.** The load domain types (`Load`, `ChainOfTrust`, `LoadAction`, `RoleLoadPolicy`) are consumed by **all 5 role shells** and by the single `Features/Loads/` module. v1.0 already establishes this exact pattern: `Roles/Role.swift`, `Core/Identity/KYC/KYCSession.swift`, and `KYCUploadInitEndpoint.ArtifactType` are shared domain types that live in `Core/` (or `Roles/`) and are imported freely by features. Putting load types in `Core/Load/` makes them importable by everyone *without* tripping the no-cross-feature-import rule (that rule only fires on `import Features_X` — see §Internal Boundaries). This is the single most important placement decision in v1.1.

- **One `Features/Loads/` module, not five.** The list and detail screens are *structurally identical* across roles — same network call shape, same VC, same VM. Only two things vary by role: (a) which loads come back (server-side / fixture-side filter, keyed by the `role` query param) and (b) which action buttons show (`RoleLoadPolicy`, a pure data table). Neither variation justifies a per-role VC. v1.0 already proved this generalization works: `VehicleCaptureViewController` is one VC parameterized by `ArtifactType` for dlBack/truck/trailer/plate. The load screens follow the same "one VC, parameterized" rule — parameterized by `Role`.

- **`Features/Loads/` uses `List/ Detail/ TrustGraph/` subfolders.** v1.0's largest feature, `Features/Onboarding/`, already nests (`Auth/`, `KYC/`, `KYC/Capture/`). The Loads feature is comparably sized (list + detail + an interactive graph + actions) and benefits from the same internal grouping. Critically, the no-cross-feature-import lint rule keys on the *first* path segment under `Features/` (`Features/[^/]+/`), so `Features/Loads/List/` and `Features/Loads/TrustGraph/` are the **same** feature — subfolders inside one feature import each other freely.

- **`TrustGraph/` is inside `Features/Loads/`, not in `Core/` or `UI/`.** The graph *renders* a `Core/Load/ChainOfTrust` value, but it is not a generic, reusable design-system widget — it is specific to the load-detail surface. It belongs to the Loads feature. Only the *data* it renders (`ChainOfTrust`/`TrustNode`) is in `Core/Load/`. (Contrast: `UI/DesignSystem/` holds `Colors`, `Spacing`, `Typography` — genuinely cross-feature primitives. The trust graph is not that.)

- **The 5 role tab-bar controllers each get a one-line edit, no new files.** Today every role's "Loads" tab is `Self.makeTab(title: "Loads", systemImage: "shippingbox")` — a placeholder bare `UIViewController`. v1.1 replaces that single array entry with a real `LoadsCoordinator(role:container:).rootViewController`. Five small, mechanically-identical edits; no new files in `Roles/`.

---

## Architectural Patterns

### Pattern 1: Role-parameterized feature, role-keyed network filter

**What:** One `LoadListViewController` / `LoadListViewModel`, constructed with a `Role`. The VM issues `LoadListEndpoint(role: role)` — a GET with the role as a query parameter. The server (and, for v1.1, the `MockURLProtocol` fixture) returns the already-filtered list for that role. The client does **not** filter client-side; filtering is a contract concern, so the eventual mock→live swap needs zero list-screen changes.

**When to use:** Whenever the same screen is surfaced across all 5 role shells with a role-scoped data set. Applies to both list and detail.

**Trade-offs:** (+) Zero code duplication; one VC/VM to test and maintain. (+) Filtering logic stays server-authoritative — matches the v1.0 principle "backend is the sole authority" and means no refactor at live-swap. (−) Each role needs its own mock fixture file (`loads-list-<role>.json`) — 5 small JSON files, an acceptable cost and exactly how `MockOTPRoleFixtureRegistry` already varies its response by role.

**Example:**
```swift
// Core/Networking/Endpoints/LoadListEndpoint.swift  (NEW)
nonisolated public struct LoadListEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable { public let loads: [Load] }
    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil
    public init(role: Role) { self.path = "/loads?role=\(role.rawValue)" }
}
// LoadsCoordinator builds LoadListViewModel(role: role, apiClient: container.apiClient, …)
```

### Pattern 2: Per-role action sets as a pure policy table (`RoleLoadPolicy`)

**What:** "Which of tender/accept/reject can role X take on a load in status Y?" is answered by a **pure function over data**, not by branching scattered through the detail VC. `RoleLoadPolicy.actions(for: role, status: load.status) -> [LoadAction]` is a single deterministic table in `Core/Load/`. `LoadDetailViewModel` calls it once; `LoadActionBar` renders exactly the returned buttons.

**When to use:** Whenever behavior varies along two axes (role × state) and must stay consistent across 5 entry points. v1.0 uses the same shape: `KYCFlowSequencer` is a "pure, simulator-testable" struct extracted from `KYCCoordinator` precisely so the rule logic is unit-tested without UIKit. `RoleLoadPolicy` is the load-domain analog.

**Trade-offs:** (+) Exhaustively unit-testable with zero UIKit — 5 roles × N statuses is a table-driven test. (+) Adding a role or status is a one-line table edit, not a VC change. (+) The server can return its *own* allowed-actions list later; `RoleLoadPolicy` then becomes a client-side pre-filter / fallback, no structural change. (−) The policy must be kept in sync with backend authorization — but the action endpoint still fails server-side, so a client/table drift is a UX bug, never a security hole.

**Example:**
```swift
// Core/Load/RoleLoadPolicy.swift  (NEW)
public enum LoadAction: String, Sendable, CaseIterable { case tender, accept, reject }

public enum RoleLoadPolicy {
    public static func actions(for role: Role, status: LoadStatus) -> [LoadAction] {
        switch (role, status) {
        case (.broker,  .draft):     return [.tender]
        case (.carrier, .tendered):  return [.accept, .reject]
        case (.dispatch, .tendered): return [.accept, .reject]
        // … one row per legal (role, status) pair; default → []
        default:                     return []
        }
    }
}
```

### Pattern 3: Trust graph as a self-contained child view controller

**What:** The interactive chain-of-trust graph is a `TrustGraphViewController` *embedded as a child VC* inside `LoadDetailViewController` (`addChild` / `didMove(toParent:)`). It owns a `TrustGraphView` (a custom `UIView` that draws the shipper→broker→carrier→dispatch→factoring nodes + edges) and a `TrustGraphViewModel` (computes node layout + per-node `VerificationState`). It is **not** a coordinator and has **no navigation stack of its own** — when a node is tapped it calls a `var onNodeTapped: (TrustNode) -> Void` closure that the *parent* (`LoadDetailViewController` / `LoadsCoordinator`) handles by presenting `TrustNodeDetailViewController` modally.

**When to use:** A rich, interactive, but navigationally-shallow component that lives inside one screen. The graph never *owns* a flow — it owns a view and emits taps. A coordinator would be overkill (coordinators exist to own multi-screen `push` chains; `AuthCoordinator`/`KYCCoordinator` each drive a `UINavigationController`). The graph drives nothing.

**Trade-offs:** (+) Child-VC containment gives the graph its own `viewDidLoad`/lifecycle, trait-collection callbacks (needed for iPad-native layout + rotation), and testability in isolation. (+) The closure-out / parent-presents split keeps the graph reusable — if M3's eBOL screen ever wants the same graph, it embeds the same child VC. (−) Slightly more wiring than a bare `UIView`, but the v1.0 KYC capture screens already use the VC-with-injected-VM shape everywhere, so it is the house style. **Must be UIKit** per the project constraint (it is an interactive sensitive-surface component); SwiftUI is not permitted here.

**Example:**
```swift
// LoadDetailViewController embeds the graph as a child VC:
let graphVM = TrustGraphViewModel(chain: load.chainOfTrust)
let graphVC = TrustGraphViewController(viewModel: graphVM)
graphVC.onNodeTapped = { [weak self] node in self?.onTrustNodeTapped?(node) }
addChild(graphVC)
contentStack.addArrangedSubview(graphVC.view)
graphVC.didMove(toParent: self)
```

### Pattern 4: Coordinator-owned action flow with optimistic-but-confirmed result

**What:** Tender/accept/reject are POSTs to `LoadActionEndpoint`. The flow: `LoadActionBar` button → `LoadDetailViewModel.perform(_:)` → `APIClient.request(LoadActionEndpoint(loadID:action:))` → on success the VM sets `state = .actionCompleted(updatedLoad)` and re-renders (the load's `status` changed, so `RoleLoadPolicy` now returns a new — possibly empty — action set). On failure (`409` conflict = stale/already-actioned, `httpError`) the VM surfaces a loud error and re-fetches the detail. The `LoadsCoordinator` is told via `onLoadActioned: (LoadID) -> Void` so it can mark the list row stale / refresh on pop-back.

**When to use:** Any state-mutating action whose result changes what the screen offers next. The "re-render from server truth, never guess locally" rule mirrors `KYCStatusViewModel` (which always re-derives `State` from a fresh `GET /kyc/status`).

**Trade-offs:** (+) The detail screen is always consistent with server state — no drift. (+) The action endpoint, being a POST, automatically picks up the shipped `IdempotencyInterceptor` (the request-interceptor that injects `Idempotency-Key`) — a double-tapped Accept is safe with zero new code. (−) A round-trip per action (no offline optimism) — acceptable: v1.1 is explicitly mock-backed and offline mode is deferred to M4.

---

## Data Flow

### List → Detail → Action flow

```
[Role shell: tap "Loads" tab]
    ↓
LoadsCoordinator(role:) builds LoadListViewController(viewModel:)
    ↓
LoadListViewModel.load()  →  APIClient.request(LoadListEndpoint(role: role))
    ↓                              ↓ (MockURLProtocol matches "/loads?role=…" → loads-list-<role>.json)
[list renders]  ←  Response.loads: [Load]   ←  decode (snake_case → camelCase, ISO-8601 dates)
    ↓
[tap a row] → viewModel.onLoadSelected?(loadID) → LoadsCoordinator.pushDetail(loadID)
    ↓
LoadDetailViewController(viewModel: LoadDetailViewModel(loadID:role:apiClient:))
    ↓
LoadDetailViewModel.load() → APIClient.request(LoadDetailEndpoint(loadID:))
    ↓                              ↓ (MockURLProtocol → load-detail-success.json)
[detail renders]  ←  Load (incl. embedded ChainOfTrust)
    │
    ├─→ TrustGraphViewModel(chain: load.chainOfTrust) → TrustGraphViewController (child VC)
    │       ↓ [tap a node] → onNodeTapped(node) → LoadsCoordinator presents
    │                                              TrustNodeDetailViewController (modal sheet)
    │
    └─→ RoleLoadPolicy.actions(for: role, status: load.status) → [LoadAction]
            ↓ → LoadActionBar renders only those buttons
            ↓ [tap "Accept"] → LoadDetailViewModel.perform(.accept)
            ↓ → APIClient.request(LoadActionEndpoint(loadID:action:))   ← IdempotencyInterceptor adds key
            ↓ → on 200: state = .actionCompleted(updatedLoad); re-render action bar
            ↓ → on 409/error: loud error + re-fetch detail
            ↓ → LoadsCoordinator.onLoadActioned(loadID) → list refreshes on pop-back
```

### State management

There is **no app-wide store** and v1.1 must not add one — the v1.0 house pattern is per-screen MVVM. Each ViewModel:
- is `@MainActor public final class`,
- holds a nested `enum State: Equatable, Sendable`,
- exposes `private(set) var state` with a `didSet { onStateChange?(state) }`,
- exposes `on…` closure callbacks for coordinator plumbing,
- takes dependencies by initializer-DI (`APIClient`, `Logger`).

`LoadListViewModel.State` ≈ `.loading / .loaded([Load]) / .empty / .error(message:)`.
`LoadDetailViewModel.State` ≈ `.loading / .loaded(Load) / .actionInFlight / .actionCompleted(Load) / .error(message:)`.
This is the exact `KYCStatusViewModel` shape — copy it.

### Key data flows

1. **Role-scoped list fetch:** `Role` flows from the tab-bar controller → `LoadsCoordinator` → `LoadListViewModel` → into the `LoadListEndpoint` path. The role never leaves the client as anything but a query param; the filtered result is the server's responsibility.
2. **Chain-of-trust hydration:** `ChainOfTrust` is **embedded in the `LoadDetailEndpoint.Response`**, not a separate fetch. One `GET /loads/{id}` returns the load *and* its 5-party verification graph. This keeps the detail screen a single round-trip and means the graph never has its own loading state.
3. **Action → status mutation → action-set recompute:** a successful action returns the *updated* `Load`; the detail VM re-runs `RoleLoadPolicy` against the new status, so the action bar self-updates (e.g. after Accept, the accept/reject buttons vanish). No manual button-hiding logic.

---

## Mock-endpoint extension (preserving the one-line mock/live swap)

The v1.0 contract-first pattern has three observed layers, and v1.1 extends each *additively* — no existing file is restructured:

1. **`APIEndpoint` conformers** (`Core/Networking/Endpoints/`). Each is a `nonisolated public struct` with `path`, `method`, `body`, an `Encodable RequestBody` (or the `EmptyBody` sentinel for GETs), and a `Decodable & Sendable Response`. v1.1 adds **3 files** here. `APIClient.request<E: APIEndpoint>` already accepts any conformer — **zero change to `APIClient`**.

2. **`MockURLProtocol` matching is endpoint-agnostic.** `MockURLProtocol` matches purely on `(path, method)` and the `registerFixture(for:path:method:statusCode:body:)` helper is generic over `E: APIEndpoint`. **No change to `MockURLProtocol` or `MockFixture`.** New endpoints "just work" the moment a handler is registered.

3. **Two fixture-registration sites, both extended additively:**
   - **Tests:** new JSON files in `validationLedgerTests/Networking/Fixtures/` (e.g. `loads-list-broker.json`, `load-detail-success.json`, `load-action-conflict.json`), registered per-test via the existing `registerFixture` helper after `MockURLProtocol.reset()`.
   - **Organic DEBUG tap-through:** add load cases to `MockDefaultFixtures.dispatchHandler`'s `switch (method, path)` — three new `case`s for `GET /loads`, `GET /loads/{id}`, `POST /loads/{id}/actions`. **OR** (cleaner, recommended) create a parallel `MockLoadFixtureRegistry` modeled exactly on `MockOTPRoleFixtureRegistry`, and call it from the same DEBUG-gated block in `AppContainer.init` that already calls `MockDefaultFixtures.registerAppDefaults()`. A separate registry keeps `MockDefaultFixtures` from growing unbounded and lets the load fixtures vary their response by role (the registry takes a `Role`, like `MockOTPRoleFixtureRegistry.registerForRole(_:)`).

**Why the live swap stays one-line:** the swap is `AppContainer.defaultNetworkConfig` → `.live(baseURL:)` vs `.mock`, which only changes whether `MockURLProtocol` is in the `URLSession.protocolClasses`. Because the load ViewModels depend on `APIClient` + typed `LoadXxxEndpoint` structs — and *never* on `MockURLProtocol` directly — flipping to `.live` requires **no load-feature code change at all**. The endpoint structs *are* the contract; the fixtures are a swappable backing. This is identically how all 7 v1.0 endpoints behaved through M1.

**One contract-design caveat for the roadmap:** the `path`-with-query-string form (`/loads?role=broker`) works against `MockURLProtocol` only if the mock matches on `url.path` *plus* query, OR the fixture is registered per-role. `MockURLProtocol`'s current `registerFixture` matches `request.url?.path` (which **excludes** the query string). So either (a) put the role in the URL *path* (`/loads/broker` — simplest, matches the existing matcher unchanged) or (b) make the load registry inspect `URLComponents.queryItems`. Recommend **(a) role-in-path** for v1.1 — it needs zero matcher change and a real backend can still route it. Flag this as a Phase-7 (model + mocks) design decision.

---

## Phase build order (v1.1 starts at Phase 7)

Dependency-ordered. Each phase is independently demoable, mirroring v1.0's "leanest visible-win slice" discipline.

| Phase | Scope | Depends on | NEW vs MODIFIES | Visible win |
|-------|-------|-----------|------------------|-------------|
| **Phase 7 — Load domain model + mock contract** | `Core/Load/` value types (`Load`, `ChainOfTrust`, `TrustNode`, `LoadStatus`, `LoadAction`, `RoleLoadPolicy`); the 3 `APIEndpoint` structs; `MockLoadFixtureRegistry` + all JSON fixtures; `RoleLoadPolicy` table-driven unit tests. | v1.0 networking (done) | NEW: `Core/Load/`, 3 endpoints, mock registry, fixtures. MODIFIES: `AppContainer` DEBUG mock block. | Endpoints decode every fixture in a unit test; `RoleLoadPolicy` proven across all 5 roles × all statuses. No UI yet — this is the contract foundation. |
| **Phase 8 — Role-filtered load list** | `LoadsCoordinator`, `LoadListViewController/ViewModel/Cell`; wire the "Loads" tab in all 5 role shells. | Phase 7 | NEW: `Features/Loads/` + `List/`. MODIFIES: 5 role tab-bar controllers, `AppContainer` (`makeLoadListScreen`). | Tap "Loads" in any of the 5 shells → a real, role-correct list renders from mocks. |
| **Phase 9 — Load detail + chain-of-trust graph** | `LoadDetailViewController/ViewModel`; `TrustGraph/` (graph VC + view + VM + node-detail sheet); list→detail push. | Phase 8 | NEW: `Detail/`, `TrustGraph/`. MODIFIES: `LoadsCoordinator` (push), `AppContainer` (`makeLoadDetailScreen`). | Tap a load → detail screen with the live interactive shipper→…→factoring graph; tap a node → its verification basis. |
| **Phase 10 — Per-role tender / accept / reject** | `LoadActionBar`; `LoadDetailViewModel.perform(_:)`; action→status→action-set re-render; list-refresh-on-pop. | Phase 9 (needs `RoleLoadPolicy` from 7, detail from 9) | NEW: `LoadActionBar`. MODIFIES: `LoadDetailViewModel`, `LoadsCoordinator` (`onLoadActioned`). | Each of the 5 roles can take its legal actions; the load's state visibly advances; the list reflects it. |

**Ordering rationale:**
- **Model + mocks first (Phase 7)** is non-negotiable — both the list and detail screens decode `Core/Load/` types, and `RoleLoadPolicy` is needed by Phase 10. Building the contract first means Phases 8–10 never block on schema churn. This is exactly the v1.0 lesson: M1 built `APIEndpoint` + `MockURLProtocol` in Phase 2 before any feature consumed them.
- **List before detail (8 before 9)** — the detail screen is reached *by tapping a list row*; the list is the entry point and the cheaper screen. A working list is also the natural place to prove the role-parameterization (Pattern 1) in isolation before the graph adds complexity.
- **Detail+graph together (9)** — the graph data (`ChainOfTrust`) is embedded in the detail response (Data flow #2), so the graph cannot be built before the detail screen exists, and the detail screen is thin without it. Keep them in one phase. If the trust-graph custom drawing proves heavy, the graph is the one part of v1.1 most likely to need its own deeper research spike — **flag Phase 9 for a possible research pass.**
- **Actions last (10)** — actions mutate state that only exists once detail renders it, and the action set depends on `RoleLoadPolicy` (Phase 7) *and* the detail VM (Phase 9). It is also the most cross-role-sensitive surface (5 roles × the action matrix), so doing it last lets it build on a proven list+detail.

---

## Scaling Considerations

Not a user-scale question — v1.1 is a fixed mock-backed iOS client. The relevant axes are *data volume per screen* and *graph rendering cost*.

| Concern | v1.1 (mocks) | At live-backend swap | If graph parties grow |
|---------|--------------|----------------------|-----------------------|
| Load list size | Fixtures are small (tens of rows) — a plain `UITableView`/diffable data source is fine. | Add pagination to `LoadListEndpoint` (`cursor`/`page` param) — an additive endpoint change, no VC restructure. | n/a |
| Trust graph nodes | Fixed at 5 parties (shipper→broker→carrier→dispatch→factoring) — a hand-laid-out static graph, no layout engine needed. | Same 5 — the chain is domain-fixed. | Only if the product later adds sub-brokers/co-brokers: the graph would need a real layout pass. Out of v1.1 scope; `TrustGraphViewModel` should still own layout so that change stays contained to one file. |
| Detail re-fetch on every action | One round-trip per action — fine against mocks and fine live. | No change. | n/a |

**First bottleneck if anything:** the trust-graph custom drawing on iPad in landscape (the constraint says iPad must render *natively*). Mitigation: `TrustGraphView` lays out from `TrustGraphViewModel`-computed positions in `layoutSubviews` / on `traitCollectionDidChange`, never from hard-coded frames — the same safe-area discipline `LimitedTrustBannerContainerViewController` already follows.

---

## Anti-Patterns

### Anti-Pattern 1: Five per-role load features (`Features/ShipperLoads/`, `Features/BrokerLoads/`, …)

**What people do:** Create a load list/detail per role because "the roles see different things."
**Why it's wrong:** The screens are structurally identical; the only differences are a query param and a button set. Five copies = 5× the test surface, 5× the bug-fix cost, and it invites real cross-feature imports if one role wants to reuse another's cell. It also fragments the domain model across features.
**Do this instead:** One `Features/Loads/` module, role-parameterized (Pattern 1), with the domain model in `Core/Load/`. The role variation is *data* (`RoleLoadPolicy`, the role query param), not *structure*.

### Anti-Pattern 2: Load domain types inside `Features/Loads/`

**What people do:** Define `struct Load`, `ChainOfTrust`, `LoadAction` inside the Loads feature folder.
**Why it's wrong:** The 5 role tab-bar controllers (`Roles/`) and `AppContainer` (`App/`) need to reference load types to construct screens — and a future M3 eBOL feature will too. If the types live in `Features/Loads/`, every other consumer either reaches into a feature (architecturally wrong) or, once `Features/` become SPM modules, *cannot* import them without tripping `no_cross_feature_import`.
**Do this instead:** Domain value types go in `Core/Load/`. `Core/` is the shared kernel everything may import. v1.0 already does this — `Role` is in `Roles/Role.swift` (importable everywhere), `KYCSession` is in `Core/Identity/KYC/`.

### Anti-Pattern 3: Giving the trust graph its own coordinator

**What people do:** Build a `TrustGraphCoordinator` because the graph "has a tap-through screen."
**Why it's wrong:** Coordinators in this codebase exist to own a `UINavigationController` and a multi-screen `push` chain (`AuthCoordinator`, `KYCCoordinator`). The graph drives no flow — it shows nodes and emits one tap event. A coordinator adds a retain-cycle-prone object (v1.0 has explicit ADRs about coordinator retention) for zero navigation.
**Do this instead:** The graph is a child view controller that exposes `onNodeTapped: (TrustNode) -> Void`. The owning `LoadsCoordinator` (or `LoadDetailViewController`) presents the node-detail sheet. The graph owns a view, not a flow.

### Anti-Pattern 4: Client-side load filtering / per-feature mock plumbing

**What people do:** Fetch *all* loads and filter by role in `LoadListViewModel`; or have `LoadListViewModel` talk to `MockURLProtocol` directly in DEBUG.
**Why it's wrong:** Client-side filtering bakes a business rule into the client that the backend must also enforce — and it breaks the one-line live swap (the live backend filters, the client would double-filter or under-filter). Touching `MockURLProtocol` from a VM couples the feature to the test double.
**Do this instead:** The role is a contract parameter (`LoadListEndpoint(role:)`); the server/fixture returns the filtered set. The VM only ever knows `APIClient` + typed endpoints. Mock wiring lives in `Core/Networking/Mock/` and `AppContainer`'s DEBUG block — never in a feature.

### Anti-Pattern 5: SwiftUI for the trust graph

**What people do:** Reach for SwiftUI `Canvas`/`Path` because a node-graph "feels declarative."
**Why it's wrong:** The project constraint is explicit — UIKit-first, SwiftUI permitted *only* for non-critical surfaces (Settings/static lists). An interactive verification-state graph on the load-detail screen is a core sensitive surface.
**Do this instead:** `TrustGraphView` is a UIKit `UIView` with custom `draw(_:)` / `CAShapeLayer` edges and `UIControl`/`UIButton` nodes. UIKit also gives the precise iPad-landscape trait-collection control the constraint demands.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Backend load API | None in v1.1 — `MockURLProtocol` fixtures only. | The 3 `LoadXxxEndpoint` structs are the forward contract; the live swap is `AppContainer.defaultNetworkConfig` → `.live`. Real-time/push/WebSocket are explicitly deferred (PROJECT.md). |
| Anthropic / Claude | Not touched by v1.1. | The Loads feature has no AI surface. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `Features/Loads/` ↔ `Core/Load/`, `Core/Networking/` | Direct `import` (same module today; `Core` import when `Features/` become SPM packages). | **Allowed.** The `no_cross_feature_import` lint rule (`regex: '^\s*import\s+Features_[A-Z]'`, scoped to `Features/[^/]+/`) only bans `import Features_X`. Importing `Core` is always fine — that is the whole point of the shared kernel. Putting the domain model in `Core/Load/` is what *keeps* v1.1 lint-clean. |
| `Features/Loads/List/` ↔ `Features/Loads/Detail/` ↔ `Features/Loads/TrustGraph/` | Direct reference. | **Allowed — same feature.** The lint rule keys on the first segment under `Features/`; all three subfolders are `Features/Loads/…` = one feature. Subfolders are organization, not module boundaries. |
| `Roles/<Role>TabBarController` ↔ `Features/Loads/LoadsCoordinator` | The tab-bar controller constructs `LoadsCoordinator` and installs `.rootViewController` as the "Loads" tab. | `Roles/` already constructs `Features/` content (it builds `ProfileViewController`). Constructing a `LoadsCoordinator` is the same shape. The `LoadsCoordinator` must be **retained** by the tab-bar controller in a strong property — v1.0 has explicit ADRs/comments (`AuthCoordinator`/`KYCCoordinator` retention bugs) about coordinators that deallocate after `makeRoot` returns. Apply the same discipline. |
| `AppContainer` ↔ `Features/Loads/` | Composition-root factories: `makeLoadListScreen(role:)`, `makeLoadDetailScreen(loadID:)`. | Mirrors the shipped `makeKYCStatusScreen()` pattern exactly — the factory builds the VM from `Core/` deps and returns an opaque `UIViewController`, so a role shell can get a load screen *without* the Roles layer knowing the feature's internal VM types. Recommended over the tab-bar controller building VMs itself, because it keeps DI in the one composition root. |
| `LoadsCoordinator` ↔ its ViewModels | Initializer-DI of `APIClient` + `Logger`; `on…` closure callbacks bubble selections/actions up. | The exact `AuthCoordinator`/`KYCCoordinator` shape — `@MainActor final class`, a `let rootViewController: UINavigationController`, `private let container: AppContainer`, `private func push…` methods that wire the next callback before `nav.pushViewController`. Copy `AuthCoordinator` as the structural template. |

---

## Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Module placement (`Core/Load/`, `Features/Loads/`, `Roles/` edits) | HIGH | Directly mirrors observed v1.0 placement of `Core/Identity/`, `Features/Onboarding/`, and the `Roles/`-builds-`Features/` pattern in `AppCoordinator.roleCoordinator`. |
| Mock-endpoint extension preserving the one-line swap | HIGH | `APIClient`, `APIEndpoint`, `MockURLProtocol`, `MockFixture` read in full; the additive-only path is verified against the actual files. |
| Role-sharing approach vs. the lint rule | HIGH | `.swiftlint.yml` rule 4 read verbatim — the regex demonstrably only matches `import Features_X`, and `Core/` imports are unaffected. |
| Trust graph as child VC | MEDIUM-HIGH | Child-VC containment is standard UIKit and consistent with the v1.0 VC+VM house style; the *exact* drawing approach (CAShapeLayer vs `draw(_:)`) is an implementation detail to settle in Phase 9. |
| Build order | HIGH | Dependency-forced (model→list→detail+graph→actions); matches v1.0's contract-first phase discipline. |

## Sources

- `validationLedger/` source tree, v1.0 "M1 Foundation" (shipped 2026-05-18, ~28,700 LOC) — primary source. Files read in full: `Core/Networking/APIClient.swift`, `APIEndpoint.swift`, `Mock/MockURLProtocol.swift`, `Mock/MockFixture.swift`, `Mock/MockDefaultFixtures.swift`, `Mock/MockOTPRoleFixtureRegistry.swift`, `Endpoints/KYCStatusEndpoint.swift`, `Endpoints/KYCUploadInitEndpoint.swift`, `App/AppCoordinator.swift`, `App/AppContainer.swift` (factory section), `Roles/Role.swift`, `Roles/RoleCoordinator.swift`, `Roles/Shipper|BrokerTabBarController.swift`, `Features/Onboarding/Auth/AuthCoordinator.swift`, `Features/Onboarding/KYC/KYCCoordinator.swift`, `Features/Onboarding/KYC/KYCStatusViewModel.swift`.
- `.swiftlint.yml` — the `no_cross_feature_import` custom rule (rule 4) and the full lint charter.
- `.planning/PROJECT.md` — v1.1 "Load Flows" scope, constraints, key decisions, the mock-only / no-backend boundary.
- `Package.swift` — SwiftPM-only dependency set (Nuke, SwiftLintPlugins).
- Not used: `.planning/codebase/*.md` (stale, dated 2026-04-21, predates all of v1.0); `TechStack.md` (not present at repo root — removed/archived; PROJECT.md used as the authoritative scope source instead).

---
*Architecture research for: load-domain feature integration into a shipped UIKit/MVVM-C iOS app*
*Researched: 2026-05-19*
