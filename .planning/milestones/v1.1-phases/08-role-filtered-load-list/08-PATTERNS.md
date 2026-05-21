# Phase 8: Role-Filtered Load List — Pattern Map

**Mapped:** 2026-05-19
**Files in scope (new + modified):** 22
**Analogs found:** 18 / 22 (4 NEW-with-no-analog surfaced explicitly)

> Locked design contract lives in `08-UI-SPEC.md`. Locked decisions live in `08-CONTEXT.md` (D-01..D-10). Confirmed idioms live in `08-RESEARCH.md`. This map points the planner / executor at the **exact existing files + line ranges** to mirror.

---

## File Classification

### NEW (15)

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `validationLedger/Features/Loads/LoadListViewController.swift` | controller (UIKit VC) | request-response (fetch-on-appear + pull-to-refresh, state-machine render) | `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift` | **exact** — same shape, only divergence is `UICollectionView` body + skeleton-loading-visual |
| `validationLedger/Features/Loads/LoadListViewModel.swift` | view-model (state machine over typed endpoint) | request-response | `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift` | **exact** — same `@MainActor public final class` + nested `enum State` + `state.didSet → onStateChange` + initializer-DI |
| `validationLedger/Features/Loads/Cells/LoadRowCell.swift` | view component (cell) | render-from-input | none in tree (no prior `UICollectionView*Cell` exists) | **no analog** — see § No-Analog Construction Guide below |
| `validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift` | view component (cell) | pure animation | none in tree (first skeleton/shimmer in the codebase per D-10) | **no analog** — see § No-Analog Construction Guide below |
| `validationLedger/UI/Components/VerificationBadgeView.swift` | reusable view (pill) | render-from-input (`configure(state:)`) | `validationLedger/UI/LimitedTrustBannerView.swift` (closest existing `UIView` subclass using `DS.*` tokens) | **role-match** — same DS-only styling, similar pill shape; no prior badge-with-pill-fill exists |
| `validationLedger/UI/Components/LoadStatusBadgeView.swift` | reusable view (pill) | render-from-input (`configure(status:)`) | same as above | **role-match** |
| `validationLedger/Core/Load/LoadListItem.swift` | domain model (envelope) | Decodable | `validationLedger/Core/Load/Load.swift` (the type it nests) + `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` `Response.Artifact` (nested-Decodable shape) | **exact** |
| `validationLedger/UI/Components/` | NEW directory | — | — | placeholder for the two badge views above |
| `validationLedger/Features/Loads/` | NEW directory | — | `validationLedger/Features/Onboarding/KYC/` | **role-match** |
| `validationLedger/Features/Loads/Cells/` | NEW directory | — | — | placeholder for the two cells above |
| `validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json` | test fixture (degraded edge) | static JSON | `validationLedgerTests/Networking/Fixtures/loads-list-broker.json` | **role-match** (construction template; semantics are new) |
| `validationLedgerTests/Loads/Snapshot/*Tests.swift` (snapshot suite — VerificationBadge, LoadStatusBadge, LoadRowCell, SkeletonLoadRowCell silhouette) | tests (snapshot) | image-render assertion | `validationLedgerTests/KYC/KYCThumbnailTests.swift` (`UIGraphicsImageRenderer` precedent at line 34) | **role-match** — same hand-rolled image-rendering recipe; no existing UIView-to-image snapshot helper |
| `validationLedgerTests/Loads/LoadListViewModelTests.swift` | tests (VM state machine — 4 transitions) | unit | none in repo for VM state-transition tests; closest: `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` + `MockURLProtocolForcedFailureTests.swift` for latency/failure usage | **role-match** |
| `validationLedgerTests/Loads/LoadListEndpointDecodeTests.swift` | tests (decode) | unit | `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` setUp + `FixtureLoader` usage | **role-match** |
| `validationLedgerUITests/Loads/LoadsListSmokeTests.swift` | tests (5-role UI smoke) | XCUITest | `validationLedgerUITests/RoleShellSmokeTests.swift` | **exact** — same launch-arg-per-role driver, same accessibility-id assertion pattern |

### MODIFIED (7)

| File | Change | Closest Analog (in-file context) |
|------|--------|----------------------------------|
| `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` | 1-line element-type change: `[Load]` → `[LoadListItem]` on `Response.loads` | self (lines 36–48) |
| `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` | (a) additive — register the new degraded fixture lane (DEBUG demo gate per D-04 / Discretion); (b) wrap every embedded list payload under the new `load:` envelope shape | self (lines 89–129 register block; lines 161+ `listPayloads` table) |
| `validationLedger/App/AppContainer.swift` | Add `func makeLoadListScreen(role: Role) -> UIViewController` mirroring `makeKYCStatusScreen()` (lines 167–199) | self (lines 167–199 + `AppCoordinator.swift` lines 191–227 for wiring) |
| `validationLedger/Roles/Shipper/ShipperTabBarController.swift` | Replace placeholder `makeTab(title: "Loads", systemImage: "shippingbox")` (line 34) with `loadListScreenFactory(.shipper)`; thread factory through `init` | self (lines 14–27 init / line 34 placeholder / lines 39–48 untouched avatar wrap) |
| `validationLedger/Roles/Broker/BrokerTabBarController.swift` | Same as Shipper, line 33 placeholder | sibling-identical to Shipper |
| `validationLedger/Roles/Carrier/CarrierTabBarController.swift` | Same, replace Loads placeholder | sibling-identical |
| `validationLedger/Roles/Dispatch/DispatchTabBarController.swift` | Same, replace Loads placeholder | sibling-identical |
| `validationLedger/Roles/Factoring/FactoringTabBarController.swift` | NOTE: Factoring's first tab is "Invoices", not "Loads" (line 33). UI-SPEC and CONTEXT.md still list Factoring among the 5 role shells the load VC slots into. Planner must surface whether Factoring's "Invoices" tab uses the new `LoadListViewController` (data is the per-role list endpoint that does include factoring loads) or stays as the placeholder. RESEARCH.md §Roadmap implies the former. | self (line 33) |

### MODIFIED (fixture data, 6 files)

| File | Change | Template |
|------|--------|----------|
| `validationLedgerTests/Networking/Fixtures/loads-list-broker.json` | Wrap every element of top-level `loads` array under `{ "load": { ... }, "displayed_counterparty": { ... } }` | self (current top-level shape excerpted below) |
| `validationLedgerTests/Networking/Fixtures/loads-list-shipper.json` | Same | sibling-identical |
| `validationLedgerTests/Networking/Fixtures/loads-list-carrier.json` | Same | sibling-identical |
| `validationLedgerTests/Networking/Fixtures/loads-list-dispatch.json` | Same | sibling-identical |
| `validationLedgerTests/Networking/Fixtures/loads-list-factoring.json` | Same | sibling-identical |
| `validationLedgerTests/Networking/Fixtures/loads-list-empty.json` | No-op for the envelope (loads array is empty), but verify still decodes | self (4-line file) |

### MODIFIED (registry inline JSON, same file `MockLoadFixtureRegistry.swift`)

The inline `listPayloads` table inside `MockLoadFixtureRegistry.swift` carries an AUTHORITATIVE COPY banner. The wrap-under-envelope diff must be applied to BOTH the test-fixture JSONs AND the inline Swift `Data(#""" ... """#.utf8)` payloads.

---

## Pattern Assignments

### 1. `LoadListViewController.swift` (controller, request-response)

**Analog:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift`

**Imports & class declaration** (lines 27–32):

```swift
import UIKit

final class KYCStatusViewController: UIViewController {

    private let viewModel: KYCStatusViewModel
```

→ Mirror as `final class LoadListViewController: UIViewController { private let viewModel: LoadListViewModel }`.

**Initializer-DI pattern** (lines 115–120):

```swift
init(viewModel: KYCStatusViewModel) {
    self.viewModel = viewModel
    super.init(nibName: nil, bundle: nil)
}

required init?(coder: NSCoder) { fatalError("not used") }
```

→ Copy verbatim, rename type.

**viewDidLoad + viewWillAppear (fetch-on-appear) pattern** (lines 124–143):

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    title = NSLocalizedString(
        "kyc.status.nav_title",
        value: "Verification",
        comment: "KYC status screen nav-bar title"
    )
    view.backgroundColor = DS.Colors.background

    layoutContent()
    wireActions()
    bindViewModel()
}

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // D-09 — fetch-on-appear: fires every time the screen appears (both
    // post-submit and from a role-shell re-entry). No background polling.
    Task { await viewModel.fetchStatus() }
}
```

→ Title becomes `NSLocalizedString("loads.list.nav_title", value: "Loads", comment: ...)` per UI-SPEC. Replace `fetchStatus()` with `fetchLoads()`.

**UIRefreshControl wire-up** (lines 51 declaration, 150 attach, 180–183 target):

```swift
private let refreshControl = UIRefreshControl()
...
scrollView.refreshControl = refreshControl
...
private func wireActions() {
    // D-09 — pull-to-refresh re-fires GET /kyc/status. No polling timer.
    refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
    continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
}

@objc private func pulledToRefresh() {
    Task { await viewModel.fetchStatus() }
}
```

→ The Phase 8 surface attaches `refreshControl` directly to the **collection view** (not a scroll view): `collectionView.refreshControl = refreshControl`. UI-SPEC line 41 + LOAD-08 + RESEARCH §Primary Recommendation all confirm. Accessibility id: `"loads-list.refresh-control"`.

**VM-binding pattern** (lines 186–188):

```swift
private func bindViewModel() {
    viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
}
```

→ Copy verbatim, signature is `(LoadListViewModel.State) -> Void`.

**State-switch render pattern** (lines 202–315):

The canonical "reset shared chrome → switch over enum cases" structure. Key excerpts:

```swift
private func handle(state: KYCStatusViewModel.State) {
    // Reset shared chrome before applying the state.
    refreshControl.endRefreshing()
    rejectedListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    rejectedListStack.isHidden = true
    continueButton.isHidden = true
    activityIndicator.stopAnimating()

    switch state {
    case .loading:
        symbolView.image = nil
        headingLabel.text = ""
        bodyLabel.text = ""
        if !refreshControl.isRefreshing {
            activityIndicator.startAnimating()
        }
    ...
    case .error(let message):
        symbolView.image = UIImage(systemName: "wifi.exclamationmark")
        symbolView.tintColor = DS.Colors.destructive
        headingLabel.textColor = DS.Colors.label
        headingLabel.text = NSLocalizedString(
            "kyc.status.error.title",
            value: "Couldn't load status",
            comment: "KYC status screen — fetch error heading"
        )
        bodyLabel.text = message
        bodyLabel.textColor = DS.Colors.labelSecondary
    }
}
```

→ The 4 Phase 8 cases (per UI-SPEC § State Machine) are:
- `.loading` — hide the diffable-datasource backed collection view, show the **skeleton background view** (per D-09, NOT a centered spinner).
- `.empty` — set `contentUnavailableConfiguration` to a `UIContentUnavailableConfiguration` per UI-SPEC §State Machine (iOS 17 native). Role-specific body copy per UI-SPEC §Copywriting table.
- `.loaded(loads, nextCursor)` — apply diffable snapshot; show the collection view.
- `.error(message)` — set `contentUnavailableConfiguration` with the "We couldn't load loads" heading + "Try again" CTA (accessibility id `"loads-list.error-state.retry"`).

Always call `refreshControl.endRefreshing()` at the top of the handler (mirrors KYCStatusViewController line 204).

**Constraints + safe-area pattern** (lines 159–177):

```swift
let guide = view.safeAreaLayoutGuide
NSLayoutConstraint.activate([
    scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
    scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
    scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
    ...
])
```

→ Mirror with the collection view. For iPad (`horizontalSizeClass == .regular`) per UI-SPEC SC-#5, pin to `view.readableContentGuide`; for iPhone compact, pin to `safeAreaLayoutGuide`. Toggle in `traitCollectionDidChange(_:)` per UI-SPEC § iPad Native-Rendering Contract.

---

### 2. `LoadListViewModel.swift` (view-model, request-response)

**Analog:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift`

**Class shape + state enum** (lines 33–96):

```swift
import Foundation

@MainActor
public final class KYCStatusViewModel {
    ...
    public enum State: Equatable, Sendable {
        case loading
        case pending
        case underReview
        case verified
        case rejected(artifacts: [RejectedArtifact])
        case noSubmission
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    public var onStateChange: ((State) -> Void)?
```

→ Phase 8 enum (per UI-SPEC § State Machine + D-05 `nextCursor` decoded-only):

```swift
public enum State: Equatable, Sendable {
    case loading
    case empty
    case loaded(loads: [LoadListItem], nextCursor: String?)  // D-05: nextCursor stored, never read
    case error(message: String)
}
```

**Initializer-DI** (lines 122–132):

```swift
private let apiClient: APIClient
private let store: KYCSessionStore
private let keychain: KeychainStore
private let logger: any Logger

public init(
    apiClient: APIClient,
    store: KYCSessionStore,
    keychain: KeychainStore,
    logger: any Logger
) {
    self.apiClient = apiClient
    self.store = store
    self.keychain = keychain
    self.logger = logger
}
```

→ Phase 8 simplifies to `init(role: Role, apiClient: APIClient, logger: any Logger)`. Per CONTEXT.md Claude's Discretion: VM consumes `APIClient` directly (matches the v1.0 precedent); no `LoadListProviding` facade. The `role` is stored so `fetchLoads()` constructs `LoadListEndpoint(role: self.role)`.

**fetch method (the canonical request-response with error mapping)** (lines 138–157):

```swift
public func fetchStatus() async {
    state = .loading
    let response: KYCStatusEndpoint.Response
    do {
        response = try await apiClient.request(KYCStatusEndpoint())
    } catch {
        logger.error(
            event: LogEvent("kyc_status_fetch_failed"),
            fields: [.event: String(describing: error)]
        )
        state = .error(message: NSLocalizedString(
            "kyc.status.error",
            value: "We couldn't load your verification status. Pull down to try again.",
            comment: "KYC status screen — fetch failed error"
        ))
        return
    }
    refreshCachedKYCStatus(response.overallStatus)
    state = mapState(from: response)
}
```

→ Phase 8 mirror:

```swift
public func fetchLoads() async {
    state = .loading
    let response: LoadListEndpoint.Response
    do {
        response = try await apiClient.request(LoadListEndpoint(role: role))
    } catch {
        logger.error(
            event: LogEvent("loads_list_fetch_failed"),
            fields: [.event: String(describing: error)]  // PII: no load reference numbers, no party names — only the error description
        )
        state = .error(message: NSLocalizedString(
            "loads.list.error.body",
            value: "Check your connection and try again. Your loads are safe.",
            comment: "Load list — fetch failed body"
        ))
        return
    }
    state = response.loads.isEmpty
        ? .empty
        : .loaded(loads: response.loads, nextCursor: response.nextCursor)
}
```

Note: per UI-SPEC § Copywriting the error body is `"Check your connection and try again. Your loads are safe."` — heading copy is set by the VC, not threaded through `message`. Planner's call: either (a) keep `message: String` and use it for body only (heading is hardcoded on the VC), or (b) collapse to `case .error` with no associated value and let the VC always render the fixed copy. The UI-SPEC's "all errors collapse to .error(message: String) per UI-SPEC" wording leans (a).

**PII discipline** (line 145):

```swift
fields: [.event: String(describing: error)]
```

→ Phase 8 MUST follow: the `event:` field carries only the error description, **never** load reference numbers, party display names, or `displayed_counterparty.partyID`. Matches CLAUDE.md "Zero PII in analytics or crash logs".

---

### 3. `LoadListItem.swift` (domain envelope, Decodable)

**Analog (primary):** `validationLedger/Core/Load/Load.swift` (the nested type)

**Analog (shape):** `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` `Response.Artifact` (nested-Decodable, Sendable struct with public-let fields)

**Imports + nonisolated-vs-not** (`Load.swift` lines 45–46, then 101):

```swift
import Foundation
...
public struct Load: Decodable, Sendable {
    public let id: String
    public let referenceNumber: String
    ...
}
```

→ The Phase 8 envelope:

```swift
// validationLedger/Core/Load/LoadListItem.swift
// Phase 8 D-02: row envelope projecting Load + the role-resolved counterparty.
// The server (or fixture) projects displayed_counterparty per row — iOS NEVER
// selects which TrustNode to render (D-01 / D-18). nil is fail-closed: render
// the neutral-grey UNVERIFIED badge with counterparty slot suppressed (D-03).

import Foundation

public struct LoadListItem: Decodable, Sendable {
    /// The full Load aggregate (Phase 7 LOAD-02). Unchanged by Phase 8.
    public let load: Load

    /// Server-projected counterparty (Broker→carrier, Carrier→broker,
    /// Shipper→broker, Dispatch→broker, Factoring→carrier). `nil` is
    /// fail-closed per D-03 — render the UNVERIFIED badge, no name.
    public let displayedCounterparty: TrustNode?
}
```

**CodingKeys** — none needed. Per `Load.swift` lines 30–38, `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` handles `displayed_counterparty → displayedCounterparty` transparently (no acronym at the tail). RESEARCH §Discretion confirms: "no explicit CodingKey needed on `LoadListItem`."

**Fail-closed nil semantics** — automatic via Swift's synthesized `Optional<T>` decoder behaviour (`decodeIfPresent` for an optional property). No custom `init(from:)` needed. Per CONTEXT.md D-03.

---

### 4. `LoadListEndpoint.swift` (MODIFIED — single-line element-type change)

**Current (lines 36–48):**

```swift
public struct Response: Decodable, Sendable {
    /// The page of loads for this role. Each `Load` is the Plan 02
    /// aggregate value type; its `status` field decodes via the closed
    /// `LoadStatus` enum (throws on unknown — see Plan 01 file header).
    public let loads: [Load]

    /// Server-supplied opaque pagination cursor. `nil` means "no more
    /// pages". Wire form is `next_cursor` (snake_case); the synthesized
    /// optional decoder + `.convertFromSnakeCase` handles absent/null
    /// values transparently. Phase 8 list VMs pass this back unchanged
    /// on the next page-fetch request.
    public let nextCursor: String?
}
```

**Change:** Replace `[Load]` with `[LoadListItem]` (D-02). Update the doc comment to call out the envelope. Optionally append a note: "Phase 8 D-02: list rows wrap `Load` under `load:` and add server-projected `displayedCounterparty: TrustNode?` per row. Detail's `LoadDetailEndpoint.Response.load: Load` is UNTOUCHED — list vs detail are cleanly separated by the envelope."

Source-incompatible diff but contained: the only call site is born in Phase 8's new `LoadListViewModel.fetchLoads()`.

---

### 5. `MockLoadFixtureRegistry.swift` (MODIFIED — additive degraded lane + inline-payload envelope wrap)

**Per-role list handler** (lines 90–99):

```swift
// (1) Per-role list handler: GET /loads/{role-rawValue}
MockURLProtocol.register { request in
    guard request.httpMethod == "GET" else { return nil }
    guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
    let suffix = String(path.dropFirst("/loads/".count))
    // Suffix must be exactly the role rawValue (no further slashes).
    guard !suffix.contains("/") else { return nil }
    guard let body = listPayloads[suffix] else { return nil }
    return make200(body: body, url: request.url)
}
```

→ UNTOUCHED — the dispatcher is correct. The change is in `listPayloads` table (inline Data literals must be re-wrapped under the envelope, matching the parallel JSON fixture edits).

**Degraded-fixture additive lane (per D-04 + Discretion):**

Add a sibling `static func registerDegradedDemoLane()` that appends one handler dispatching on a sentinel role rawValue or query flag. RESEARCH §Discretion: "an extra `MockLoadFixtureRegistry.registerForDegradedDemo()` lane or an XCUITest-only `?demo=degraded` query — the existing Phase 7 `MockLoadFixtureRegistry` shape decides which is idiomatic." Given the existing shape (lines 89–129) uses path-suffix dispatch with no query parsing, the idiomatic addition is a sentinel-role `/loads/degraded` lookup OR (cleaner) a sibling registry method gated by `AppContainer.kycTestSeed`-style DEBUG static. Planner's call.

**File-level gate** (lines 78 + last line):

```swift
#if DEBUG

import Foundation

enum MockLoadFixtureRegistry { ... }

#endif
```

→ Preserve. The whole degraded-lane addition must remain inside the `#if DEBUG`.

**AUTHORITATIVE COPY banner** (lines 30–47, summarized):

The inline JSON in `listPayloads` is duplicated with the test-target fixture files (the Xcode `PBXFileSystemSynchronizedRootGroup` constraint blocks sharing). Any envelope-wrap edit must be applied to BOTH locations in lockstep. The planner should write this as a single coordinated commit.

---

### 6. `AppContainer.swift` (MODIFIED — add `makeLoadListScreen(role:)`)

**Analog (in same file):** `makeKYCStatusScreen()` (lines 167–199).

**Pattern to mirror exactly** (lines 167–199):

```swift
@MainActor
func makeKYCStatusScreen() -> UIViewController {
    let viewModel = KYCStatusViewModel(
        apiClient: apiClient,
        store: kycSessionStore,
        keychain: keychainStore,
        logger: logger
    )
    let viewController = KYCStatusViewController(viewModel: viewModel)
    viewModel.onVerified = { [weak viewController] in
        guard let viewController else { return }
        if let nav = viewController.navigationController,
           nav.viewControllers.first !== viewController {
            nav.popViewController(animated: true)
        } else {
            viewController.dismiss(animated: true)
        }
    }
    return viewController
}
```

→ Phase 8 mirror:

```swift
@MainActor
func makeLoadListScreen(role: Role) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(
        subsystem: LoggingSubsystem.app,  // or a new .loads subsystem if/when added
        category: "feature.loads"
    )
    let viewModel = LoadListViewModel(
        role: role,
        apiClient: apiClient,
        logger: featureLogger
    )
    return LoadListViewController(viewModel: viewModel)
}
```

The factory shape is the closure-factory pattern, plumbed through `*TabBarController.init` per Phase 5 `kycStatusScreenFactory` precedent. The wiring point is `AppCoordinator.roleCoordinator(for:container:)` lines 191–227.

---

### 7. `AppCoordinator.swift` (MODIFIED — thread the new factory)

**Current (lines 191–227):**

```swift
@MainActor
static func roleCoordinator(for role: Role, container: AppContainer) -> UITabBarController {
    let kycStatusFactory: () -> UIViewController = { [weak container] in
        guard let container else { return UIViewController() }
        return container.makeKYCStatusScreen()
    }
    switch role {
    case .shipper:
        return ShipperTabBarController(
            logoutService: container.logoutService,
            kycStatusScreenFactory: kycStatusFactory
        )
    case .broker:
        return BrokerTabBarController(
            logoutService: container.logoutService,
            kycStatusScreenFactory: kycStatusFactory
        )
    ...
    }
}
```

→ Phase 8 mirror — add a parallel closure:

```swift
let loadListFactory: (Role) -> UIViewController = { [weak container] role in
    guard let container else { return UIViewController() }
    return container.makeLoadListScreen(role: role)
}
```

And thread it into each role tab bar `init`:

```swift
return ShipperTabBarController(
    logoutService: container.logoutService,
    kycStatusScreenFactory: kycStatusFactory,
    loadListScreenFactory: loadListFactory  // NEW
)
```

The closure takes a `Role` so each tab bar can call `loadListScreenFactory(.shipper)` etc., or the closure is curried at this site (planner's call — currying here is slightly cleaner since each tab bar already knows its role; the role is a stored property on every `*TabBarController`).

---

### 8. The 5 `*TabBarController.swift` files (MODIFIED — replace placeholder Loads tab)

**Analog:** `ShipperTabBarController.swift` (the CONTEXT.md-named exemplar).

**Current pattern** (lines 14–48):

```swift
let logoutService: any LogoutService
let kycStatusScreenFactory: (() -> UIViewController)?

init(
    logoutService: any LogoutService,
    kycStatusScreenFactory: (() -> UIViewController)? = nil
) {
    self.logoutService = logoutService
    self.kycStatusScreenFactory = kycStatusScreenFactory
    super.init(nibName: nil, bundle: nil)
}

required init?(coder: NSCoder) { fatalError("not used") }

override func viewDidLoad() {
    super.viewDidLoad()
    viewControllers = [
        Self.makeTab(title: "Loads",     systemImage: "shippingbox"),  // ← LINE 34: PLACEHOLDER
        Self.makeTab(title: "Brokers",   systemImage: "person.2"),
        Self.makeTab(title: "BOL",       systemImage: "doc.text"),
        Self.makeTab(title: "Assistant", systemImage: "sparkles"),
    ]
    wrapTabsWithNavAndInstallAvatar { [weak self] in   // ← lines 42–48: UNTOUCHED
        guard let self else { return UIViewController() }
        return ProfileViewController(
            logoutService: self.logoutService,
            kycStatusScreenFactory: self.kycStatusScreenFactory
        )
    }
}
```

→ Diff for each of the 5 files:

```swift
let logoutService: any LogoutService
let kycStatusScreenFactory: (() -> UIViewController)?
let loadListScreenFactory: ((Role) -> UIViewController)?   // NEW

init(
    logoutService: any LogoutService,
    kycStatusScreenFactory: (() -> UIViewController)? = nil,
    loadListScreenFactory: ((Role) -> UIViewController)? = nil  // NEW
) {
    self.logoutService = logoutService
    self.kycStatusScreenFactory = kycStatusScreenFactory
    self.loadListScreenFactory = loadListScreenFactory  // NEW
    super.init(nibName: nil, bundle: nil)
}

override func viewDidLoad() {
    super.viewDidLoad()
    let loadsTab: UIViewController = loadListScreenFactory?(role)
        ?? Self.makeTab(title: "Loads", systemImage: "shippingbox")  // fallback preserves the v1.1 placeholder for tests that don't inject the factory
    loadsTab.title = "Loads"
    loadsTab.tabBarItem = UITabBarItem(
        title: "Loads",
        image: UIImage(systemName: "shippingbox"),
        selectedImage: nil
    )
    viewControllers = [
        loadsTab,
        Self.makeTab(title: "Brokers",   systemImage: "person.2"),
        Self.makeTab(title: "BOL",       systemImage: "doc.text"),
        Self.makeTab(title: "Assistant", systemImage: "sparkles"),
    ]
    wrapTabsWithNavAndInstallAvatar { ... }  // UNCHANGED — lines 42–48
}
```

`wrapTabsWithNavAndInstallAvatar` (RoleCoordinator.swift lines 45–67) auto-wraps every tab root in a `UINavigationController` and installs the avatar — the new `LoadListViewController` slots into that wrap automatically. Do not touch that helper.

**Factoring (`FactoringTabBarController.swift`):** first tab is "Invoices" (line 33), not "Loads". The 5-role smoke UI test in `RoleShellSmokeTests.swift` line 151 asserts `tabBars.buttons["Invoices"]` for factoring. Per RESEARCH §Phase Requirements LOAD-03 ("each of the 5 roles sees only the loads relevant to it") + the existing `loads-list-factoring.json` fixture, factoring DOES consume the load list endpoint. The planner must decide: (a) the "Invoices" tab is renamed to "Loads" for factoring (breaks the existing UI test naming contract) or (b) the "Invoices" tab is backed by `LoadListViewController(.factoring)` with the tab title kept as "Invoices" (the loads ARE invoices for the factoring role). Option (b) is consistent with CONTEXT.md §Boundary and RESEARCH §Phase Requirements ("each role's Loads tab"). Surface this in PLAN.md.

---

### 9. `loads-list-{role}.json` (6 fixture files MODIFIED, 1 NEW)

**Current shape of every row inside the `loads` array** (excerpted from `loads-list-broker.json` rows 4–93):

```json
{
  "loads": [
    {
      "id": "VL-1001",
      "reference_number": "REF-1001-AA",
      "origin": { "city": "Anaheim", "state": "CA", "postal_code": "92805", "country": "US" },
      "destination": { "city": "Atlanta", "state": "GA", "postal_code": "30303", "country": "US" },
      "equipment": "dry_van",
      "weight": 42500,
      "rate": 3850.0,
      "pickup_at": "2026-04-02T08:00:00Z",
      "deliver_at": "2026-04-06T17:00:00Z",
      "status": "delivered",
      "state_history": [ ... ],
      "respond_by_at": null,
      "tender_eligibility": { "can_tender": true, "disabled_reason": null }
    },
    ...
  ],
  "next_cursor": null
}
```

**Target shape after Phase 8 envelope wrap:**

```json
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
        ... (all existing Load fields nested unchanged under "load") ...
        "tender_eligibility": { "can_tender": true, "disabled_reason": null }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "1234567",
        "usdot_authority_status": "active",
        "prior_relationship_count": 32
      }
    },
    ...
  ],
  "next_cursor": null
}
```

The shape of `displayed_counterparty` is the existing `TrustNode` schema — verify against `ChainOfTrust.swift` lines 79–133 (TrustNode definition with `partyID`, `role`, `displayName`, `verificationState`, `kycCompletedAt`, `deviceBindingStatus`, `usdotNumber`, `usdotAuthorityStatus`, `priorRelationshipCount`). The wire form (snake_case) is verified by the existing `load-detail-VL-1001.json` `chain_of_trust.nodes[i]` shape — visible in `MockLoadFixtureRegistry.swift` lines 3107–3127 (excerpted above in research read).

**Per-role counterparty assignment (D-04 + Phase 7 D-11 shared-world):**

| Role fixture | Counterparty role on each row |
|--------------|-------------------------------|
| `loads-list-broker.json` | carrier (the broker sees the carrier counterparty) |
| `loads-list-shipper.json` | broker |
| `loads-list-carrier.json` | broker |
| `loads-list-dispatch.json` | broker |
| `loads-list-factoring.json` | carrier |
| `loads-list-empty.json` | (no rows; envelope-shape passthrough only) |

**SHARED WORLD CONSISTENCY (D-11):** load `VL-1001` appearing in `loads-list-broker.json` and `loads-list-shipper.json` MUST carry the role-appropriate counterparty in each: in broker's list, `displayed_counterparty` is the carrier (Acme); in shipper's list, the same `VL-1001` carries the broker (FreightWise). The counterparty `TrustNode` should reuse the `partyID` + `displayName` + `verificationState` from `load-detail-VL-1001.json`'s `chain_of_trust.nodes` so detail and list never disagree.

**NEW: `loads-list-degraded-counterparty.json`** (no analog — D-04 second half):

Construct from a copy of one role file (any of the 5; CONTEXT.md doesn't pin which). Must include:
- at least one row with `displayed_counterparty: null` (fail-closed UNVERIFIED render),
- at least one row with `displayed_counterparty.verification_state: "flagged"` (red badge render path),
- the rest of the rows valid for contrast.

This file exercises three guarantees simultaneously (per CONTEXT.md §Specifics #3):
1. `decodeIfPresent` handles the missing `displayed_counterparty` field,
2. the row renders the neutral UNVERIFIED badge (never green) on nil,
3. the accessibility label does not leak a fake "verified" status to VoiceOver.

---

### 10. Snapshot test files (NEW under `validationLedgerTests/Loads/Snapshot/`)

**Analog (image-rendering recipe):** `validationLedgerTests/KYC/KYCThumbnailTests.swift` lines 32–42:

```swift
private static func sampleJPEG(side: Int = 1_200) -> Data {
    let size = CGSize(width: side, height: side)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { ctx in
        UIColor.systemTeal.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor.systemOrange.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side / 2, height: side / 2))
    }
    return image.jpegData(compressionQuality: 0.9)!
}
```

→ Adapt for Phase 8 as a `func snapshot(of view: UIView, size: CGSize) -> UIImage` helper:

```swift
// validationLedgerTests/Loads/Snapshot/SnapshotHelpers.swift  (NEW)
import UIKit

enum SnapshotHelpers {
    /// Render a UIView at the given size into a UIImage. The view is forced
    /// to lay out at the supplied size before drawing. Caller compares the
    /// resulting PNG bytes (or attaches via XCTAttachment) to a baseline.
    /// RESEARCH §Summary "Option (a) — minimal hand-rolled UIView → UIImage
    /// baseline via XCTAttachment".
    static func snapshot(of view: UIView, size: CGSize) -> UIImage {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }
}
```

**Test class shape (Swift Testing — STACK-03):** mirror `KYCThumbnailTests.swift` line 19–25:

```swift
import Testing
import Foundation
import UIKit
@testable import validationLedger

@Suite("VerificationBadgeView snapshot — TRUST-02 color ramp", .serialized)
struct VerificationBadgeViewSnapshotTests {
    @Test("verified renders blue fill + checkmark + 'VERIFIED' label")
    func verifiedBadge() {
        let view = VerificationBadgeView()
        view.configure(state: .verified)
        let image = SnapshotHelpers.snapshot(of: view, size: CGSize(width: 120, height: 24))
        // Either:
        //  (a) compare image.pngData() to a baseline file checked into the test bundle, or
        //  (b) attach the image as an XCTAttachment for manual review on first run.
        // RESEARCH leans (b) for the initial Phase 8 baseline generation pass.
        ...
    }
}
```

**Coverage matrix (per UI-SPEC + RESEARCH):**
- `VerificationBadgeViewSnapshotTests`: 4 states (verified / pending / unverified / flagged) per UI-SPEC §Color verification table
- `LoadStatusBadgeViewSnapshotTests`: 13 states per UI-SPEC §Color status table (or 3 group representatives if the planner narrows scope — 1 in-progress, 1 done, 1 terminal, 1 pre-life)
- `LoadRowCellSnapshotTests`: at least 2 (verified counterparty + flagged counterparty); UI-SPEC §Specifics implies the flagged-row visual is a key v1.1 demo signal
- `SkeletonLoadRowCellSilhouetteTests`: silhouette match — render the skeleton, render the real cell with placeholder data of the same length, assert they overlay within tolerance (or just attach both for review per CONTEXT.md D-09 acceptance)

---

### 11. `LoadListViewModelTests.swift` (NEW — VM state-machine, 4 transitions)

**Analog (Swift Testing shape + MockURLProtocol usage):** `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` lines 26–60:

```swift
@Suite("MockURLProtocol latency injection", .serialized)
struct MockURLProtocolLatencyTests {

    @Test("registerFixtureWithLatency delivers the response after at least the specified delay")
    func deliversAfterDelay() async throws {
        ...
        MockURLProtocol.registerFixtureWithLatency(
            for: TestEndpoint.self,
            path: "/test",
            method: .get,
            statusCode: 200,
            body: ...,
            latency: 0.5
        )
        ...
    }
}
```

→ Mirror the `.serialized` attribute (shared global registry state) and the per-test setup → registration → fetch → assertion pattern.

**Required transitions (per UI-SPEC § State Machine):**
1. `.loading → .loaded(loads:_)` — register a valid envelope-wrapped fixture; call `fetchLoads()`; observe state sequence.
2. `.loading → .empty` — register `loads-list-empty.json` envelope; call `fetchLoads()`; assert `state == .empty`.
3. `.loading → .error(message:)` — register `MockURLProtocol.registerForcedFailure` with `.urlError(.notConnectedToInternet)` and again with `.http(statusCode: 500, body: ...)`; assert state collapses to `.error` on both.
4. `.loaded → .loading → .loaded` (pull-to-refresh) — observe two-transition sequence on a second `fetchLoads()` call.

For tests 1 and 2 use `MockURLProtocol.registerFixture<E>` (default path); for the `.loading`-state observation in test 4 use `registerFixtureWithLatency` to hold the response long enough to capture the `.loading` state.

**Per-test cleanup:** `MockURLProtocol.reset()` + `MockURLProtocol.resetFailureHandlers()` at top of test and matching `defer` for teardown.

---

### 12. `LoadListEndpointDecodeTests.swift` (NEW — envelope + degraded decode)

**Analog:** Any existing endpoint decode test that uses `FixtureLoader`. Per RESEARCH §Supporting, `validationLedgerTests/Networking/FixtureLoader.swift` is the test-bundle JSON loader.

**Coverage:**
1. Decode `loads-list-broker.json` → assert `response.loads.count == N`, `response.loads[0].load.id == "VL-1001"`, `response.loads[0].displayedCounterparty?.role == .carrier`.
2. Decode `loads-list-shipper.json` for the SAME `VL-1001` → assert `response.loads[indexOf VL-1001].displayedCounterparty?.role == .broker` (Phase 7 D-11 shared-world cross-fixture invariant).
3. Decode `loads-list-empty.json` → assert `response.loads.isEmpty`.
4. Decode `loads-list-degraded-counterparty.json` → assert at least one row has `displayedCounterparty == nil` AND at least one row has `displayedCounterparty?.verificationState == .flagged`.
5. Decode `next_cursor` field — present vs null — asserts `nextCursor` Optional<String> round-trips correctly under `.convertFromSnakeCase`.

---

### 13. `LoadsListSmokeTests.swift` (NEW — 5-role XCUITest)

**Analog:** `validationLedgerUITests/RoleShellSmokeTests.swift` (every line of this file is the template).

**setUp pattern** (lines 31–36):

```swift
override func setUp() {
    super.setUp()
    // Warning 5: 30s hard cap per test. Expected per-test runtime is ~20-25s.
    executionTimeAllowance = 30
    continueAfterFailure = false
}
```

→ Copy verbatim.

**Launch + drive-OTP-flow pattern** (lines 40–76):

```swift
private func launch(role: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-MockOTPRoleForUITest", role]
    app.launch()
    return app
}

private func driveFullOTPFlow(_ app: XCUIApplication) {
    let phoneField = app.textFields["phone-entry-field"]
    XCTAssertTrue(phoneField.waitForExistence(timeout: 10), ...)
    phoneField.tap()
    phoneField.typeText("5551234567")
    ...
}
```

→ Reuse verbatim — Phase 8 smoke continues to drive the OTP flow first, then asserts the Loads tab content.

**Per-role test method pattern** (lines 103–112, Shipper case):

```swift
func testShipperFullFlow() {
    let app = launch(role: "shipper")
    driveFullOTPFlow(app)
    // TechStack §4 Shipper: Loads, Brokers, BOL, Assistant
    XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Brokers"].exists)
    XCTAssertTrue(app.tabBars.buttons["BOL"].exists)
    XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)
    assertProfileFlowAndLogout(app)
}
```

→ Phase 8 mirror: after the tab-button existence asserts, **tap the Loads tab** and assert the `loads-list` accessibility identifier resolves to a collection view AND that it contains at least one row (or the empty-state copy for the empty fixture). The accessibility identifiers (UI-SPEC § Copywriting locked):
- `loads-list` — the `UICollectionView`
- `loads-list.row.{loadID}` — each cell
- `loads-list.empty-state` — the empty `UIContentUnavailableView`
- `loads-list.error-state` — the error `UIContentUnavailableView`
- `loads-list.error-state.retry` — the "Try again" button

```swift
// New test addition pattern:
app.tabBars.buttons["Loads"].tap()
let list = app.collectionViews["loads-list"]
XCTAssertTrue(list.waitForExistence(timeout: 5),
              "Loads list collection view should appear after tapping the Loads tab")
// Mock data is the per-role list fixture — at least one VL-prefixed row should resolve.
let firstRow = app.cells.containing(.init(format: "identifier BEGINSWITH 'loads-list.row.VL-'"))
XCTAssertGreaterThan(firstRow.count, 0)
```

The Factoring case (line 147–156) currently asserts `Invoices` as the first tab — see § File 8 above for the open question.

---

## No-Analog Construction Guide

Four NEW assets have no in-tree precedent. Build them from documented idioms + the DS-token contract.

### `VerificationBadgeView.swift` / `LoadStatusBadgeView.swift`

**No analog in repo.** `LimitedTrustBannerView.swift` is the closest existing `UIView` subclass with DS-token styling, but it is a banner (full-width informational chrome), not a pill (intrinsic-content-sized inline tag). Build from scratch following UI-SPEC §Reusable Component Inventory + §Color + §Spacing + §Typography:

**Skeleton (planner template — NOT verbatim mandatory):**

```swift
// validationLedger/UI/Components/VerificationBadgeView.swift
// Phase 8 TRUST-02: reusable 4-state pill consumed by:
//   - Phase 8 LoadRowCell (this phase),
//   - Phase 9 detail header,
//   - Phase 9 chain-of-trust graph nodes,
//   - Phase 10 disabled-tender inline reason.
// Pure render-from-input — no Combine, no async, no state beyond the
// last `configure(state:)` call. The fail-closed VerificationState
// security primitive (Core/Load/VerificationState.swift D-09) means
// any unknown wire value already became .unverified before reaching
// this view — the view itself NEVER tries to soften .unverified.

import UIKit

public final class VerificationBadgeView: UIView {

    private let iconView = UIImageView()
    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // ...layout iconView + label horizontally with DS.Spacing.xs gap...
        // ...horizontal padding DS.Spacing.xs, vertical padding DS.Spacing.xs...
        label.font = DS.Typography.footnote
        label.adjustsFontForContentSizeCategory = true
        layer.cornerRadius = bounds.height / 2  // full pill — UI-SPEC §Spacing
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    public func configure(state: VerificationState) {
        switch state {
        case .verified:
            backgroundColor = DS.Colors.primary    // systemBlue
            iconView.image = UIImage(systemName: "checkmark.seal.fill")
            iconView.tintColor = .white
            label.textColor = .white
            label.text = NSLocalizedString("verification.badge.verified", value: "VERIFIED", comment: "")
        case .pending:
            backgroundColor = .systemYellow         // UI-SPEC §Color verification table
            iconView.image = UIImage(systemName: "clock.fill")
            iconView.tintColor = .label
            label.textColor = .label
            label.text = NSLocalizedString("verification.badge.pending", value: "PENDING", comment: "")
        case .unverified:
            backgroundColor = .tertiarySystemFill
            iconView.image = UIImage(systemName: "questionmark.circle.fill")
            iconView.tintColor = .secondaryLabel
            label.textColor = .secondaryLabel
            label.text = NSLocalizedString("verification.badge.unverified", value: "UNVERIFIED", comment: "")
        case .flagged:
            backgroundColor = DS.Colors.destructive  // systemRed
            iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            iconView.tintColor = .white
            label.textColor = .white
            label.text = NSLocalizedString("verification.badge.flagged", value: "FLAGGED", comment: "")
        }
    }

    public override var intrinsicContentSize: CGSize { /* derived from label.intrinsicContentSize + paddings + icon */ }
}
```

Color and SF Symbol mapping is locked by UI-SPEC §Color §Verification badge color rules. Copy is locked by UI-SPEC §Copywriting Contract cell-content-verification-badge-label row. No 5th case is allowed (UI-SPEC: "Adding a 5th case requires changing the VerificationState enum upstream, which would fail decode at the Phase 7 contract layer.").

`LoadStatusBadgeView` is the same shape, with `configure(status: LoadStatus)` mapping the 13 cases through UI-SPEC §Color status badge group table.

### `LoadRowCell.swift`

**No analog in repo.** Per the codebase scan (`grep "UICollectionViewListCell\|UICollectionViewCell"` returned zero hits in `validationLedger/`), Phase 8 introduces the FIRST `UICollectionViewListCell` in the codebase. RESEARCH §Standard Stack confirms this: "introducing the app's first `UICollectionViewCompositionalLayout(.list)` + `UICollectionViewDiffableDataSource` surface."

**Construction reference (Apple-docs idiom flagged in RESEARCH §Primary Recommendation):**

```swift
// validationLedger/Features/Loads/Cells/LoadRowCell.swift
// Phase 8 LOAD-04: the standard freight row.
//   reference # (headline) | status badge
//   origin → destination (body)
//   pickup • deliver (footnote) | verification badge
//   equipment • weight (footnote) | rate (footnote, trailing)
// Three-tier hierarchy locked by UI-SPEC §Typography reference-number-rendering-note.

import UIKit

public final class LoadRowCell: UICollectionViewListCell {

    private let referenceLabel = UILabel()
    private let originDestinationLabel = UILabel()
    private let pickupDeliverLabel = UILabel()
    private let equipmentWeightLabel = UILabel()
    private let rateLabel = UILabel()
    private let verificationBadge = VerificationBadgeView()
    private let statusBadge = LoadStatusBadgeView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // ...layout with DS.Spacing.md outer padding, DS.Spacing.sm row gaps...
        referenceLabel.font = DS.Typography.headline
        originDestinationLabel.font = DS.Typography.body
        pickupDeliverLabel.font = DS.Typography.footnote
        equipmentWeightLabel.font = DS.Typography.footnote
        rateLabel.font = DS.Typography.footnote
        // ALL labels: adjustsFontForContentSizeCategory = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    public func configure(item: LoadListItem) {
        let load = item.load
        referenceLabel.text = load.referenceNumber
        originDestinationLabel.text = "\(load.origin.city), \(load.origin.state) → \(load.destination.city), \(load.destination.state)"
        // ...pickup/deliver via RelativeDateTimeFormatter (UI-SPEC §Copywriting)
        // ...equipment + weight via NumberFormatter (no client-side title-casing — UI-SPEC pin)
        // ...rate via NumberFormatter.currency en_US, no cents on the cell

        // D-03 fail-closed: nil counterparty → render UNVERIFIED with name suppressed
        if let counterparty = item.displayedCounterparty {
            verificationBadge.configure(state: counterparty.verificationState)
        } else {
            verificationBadge.configure(state: .unverified)  // never green, never inferring trust
        }
        statusBadge.configure(status: load.status)

        // Accessibility identifiers (UI-SPEC §Copywriting — locked):
        accessibilityIdentifier = "loads-list.row.\(load.id)"
        verificationBadge.accessibilityIdentifier = "loads-list.row.\(load.id).verification-badge"
        statusBadge.accessibilityIdentifier = "loads-list.row.\(load.id).status-badge"
    }
}
```

**Cell registration (Apple-idiom for diffable + compositional list):**

```swift
// Inside LoadListViewController:
private lazy var cellRegistration = UICollectionView.CellRegistration<LoadRowCell, LoadListItem> { cell, _, item in
    cell.configure(item: item)
}

private lazy var dataSource = UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>(
    collectionView: collectionView
) { [unowned self] cv, indexPath, item in
    cv.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item.item)
}

// where:
enum LoadListSection: Hashable { case main }  // D-08 forward-looking single section
struct LoadRowItem: Hashable {                 // hashable wrapper for diffable
    let item: LoadListItem
    // Hash on load.id only (stable across refreshes); content-equality drives reload via reconfigureItems
}
```

Per CONTEXT.md D-08 the section enum is defined from day one so adding `.active / .past / .drafts` later is additive.

### `SkeletonLoadRowCell.swift`

**No analog in repo.** First skeleton/shimmer in the app per CONTEXT.md D-10. Construction documents the app-wide skeleton-with-shimmer pattern for Phase 9+.

**Construction reference:**

```swift
// validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift
// Phase 8 D-09: skeleton-with-shimmer placeholder row for the .loading state.
//
// === Phase 8 establishes the app-wide skeleton-with-shimmer pattern (D-10) ===
// Phase 9's chain-of-trust party list and any future list-style fetch surface
// SHOULD follow this precedent. The shipped KYCStatusViewController precedent
// (centered UIActivityIndicatorView) is preserved as-is — Phase 8 does NOT
// back-port the skeleton to v1.0 surfaces. See CONTEXT.md D-10.
//
// Silhouette matches the real LoadRowCell at default Dynamic Type:
//   ┌────────────────────────────────────────┐
//   │  ████████████          ████             │  ← reference + status badge
//   │  ██████████████████████                 │  ← origin → destination
//   │  ████████████           ████            │  ← pickup/deliver + verif badge
//   │  ██████████             ████            │  ← equipment + rate
//   └────────────────────────────────────────┘
//
// Shimmer: a single CAGradientLayer animated via CABasicAnimation, ~1.2s loop,
// infinite repeat. RESEARCH §Standard Stack ratifies CAGradientLayer +
// CABasicAnimation (first-party, no third-party shimmer library).

import UIKit
import QuartzCore

public final class SkeletonLoadRowCell: UICollectionViewListCell {
    private let blocks: [UIView] = (0..<6).map { _ in UIView() }
    private let shimmerLayer = CAGradientLayer()
    ...
}
```

Block sizes are planner's discretion (CONTEXT.md §Discretion — must visually approximate the three-tier hierarchy of the real cell).

---

## Shared Patterns

### Initializer-DI (ARCH-04)

**Source:** every `*ViewModel.init(apiClient:store:keychain:logger:)` and `*ViewController.init(viewModel:)` in the codebase.

**Canonical example:** `KYCStatusViewModel.swift` lines 122–132 (excerpted above in § File 2).

**Apply to:** `LoadListViewModel.init(role:apiClient:logger:)`, `LoadListViewController.init(viewModel:)`. Composition in `AppContainer.makeLoadListScreen(role:)`.

### DS-token-only styling (no raw literals)

**Source:** `validationLedger/UI/DesignSystem/{Spacing.swift, Typography.swift, Colors.swift}` — three small files.

**Excerpt — `Spacing.swift` lines 6–15:**

```swift
public extension DS {
    enum Spacing {
        public static let xs:  CGFloat = 4
        public static let sm:  CGFloat = 8
        public static let md:  CGFloat = 16
        public static let lg:  CGFloat = 24
        public static let xl:  CGFloat = 32
        public static let xxl: CGFloat = 48
    }
}
```

**Excerpt — `Typography.swift` lines 7–18:**

```swift
public extension DS {
    enum Typography {
        public static var largeTitle: UIFont { .preferredFont(forTextStyle: .largeTitle) }
        public static var title1:     UIFont { .preferredFont(forTextStyle: .title1) }
        public static var headline:   UIFont { .preferredFont(forTextStyle: .headline) }
        public static var body:       UIFont { .preferredFont(forTextStyle: .body) }
        public static var footnote:   UIFont { .preferredFont(forTextStyle: .footnote) }
        ...
    }
}
```

**Excerpt — `Colors.swift` lines 8–20:**

```swift
public enum DS {
    public enum Colors {
        public static let primary:    UIColor = .systemBlue
        public static let background: UIColor = .systemBackground
        public static let surface:    UIColor = .secondarySystemBackground
        public static let label:      UIColor = .label
        public static let labelSecondary: UIColor = .secondaryLabel
        public static let separator:  UIColor = .separator
        public static let destructive: UIColor = .systemRed
    }
}
```

**Apply to:** every NEW view file. The only allowed exceptions per UI-SPEC + RESEARCH:
- `44pt` minimum touch-target floor (Apple HIG, not a token) — on the "Try again" button and any other actionable affordance,
- `bounds.height / 2` badge corner radius (geometric, not a layout literal),
- `.systemYellow` on the `.pending` verification badge (UI-SPEC §Color rationale),
- `.tertiarySystemFill` / `.systemGray5` / `.systemGray6` on status badge neutrals (UI-SPEC §Status badge color rules).

### NSLocalizedString copy pattern

**Source:** every `NSLocalizedString` call in `KYCStatusViewController.swift` (lines 95–101, 125–129, 224–234, 254–262, etc.).

**Excerpt (lines 95–101):**

```swift
cfg.title = NSLocalizedString(
    "kyc.status.continue",
    value: "Continue",
    comment: "KYC status screen — verified-path CTA into the role shell"
)
```

**Apply to:** every user-visible string in Phase 8. UI-SPEC §Copywriting Contract pins every string. Suggested key namespacing: `loads.list.*` (e.g. `loads.list.nav_title`, `loads.list.empty.heading`, `loads.list.error.body`, `loads.list.retry`, `verification.badge.verified`, `status.badge.in_transit`).

### PII discipline in logger fields

**Source:** `KYCStatusViewModel.swift` lines 143–147 + 173–186, `AppContainer.swift` lines 379–382.

**Excerpt:**

```swift
logger.error(
    event: LogEvent("kyc_status_fetch_failed"),
    fields: [.event: String(describing: error)]
)
```

**Apply to:** every `logger.*` call from `LoadListViewModel`. CRITICAL: NEVER pass `load.referenceNumber`, `load.id`, `displayedCounterparty?.displayName`, or `displayedCounterparty?.partyID` into `fields`. CLAUDE.md "Zero PII in analytics or crash logs" + RESEARCH §Project Constraints. The `event:` field is the only allowed channel — and it carries only error descriptions or controlled-vocabulary status strings, never load identifiers or party names.

### `MockURLProtocol` test setup (latency / forced-failure)

**Source:** `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` (canonical setUp) + `MockURLProtocolForcedFailureTests.swift`.

**Apply to:** `LoadListViewModelTests.swift`. Pattern:

```swift
@Suite("LoadListViewModel state machine", .serialized)
struct LoadListViewModelTests {

    @Test("loading → loaded on a successful fixture")
    func loadingToLoaded() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        // register the role fixture...
        // construct vm with a real APIClient pointed at the mock URLSession
        // ...assert state transitions
    }
}
```

The `.serialized` attribute is REQUIRED because tests mutate the global MockURLProtocol handler registry (KYCThumbnailTests line 24 + MockURLProtocolLatencyTests precedent).

### 5-role XCUITest pattern (launch-arg + per-tab assert)

**Source:** `validationLedgerUITests/RoleShellSmokeTests.swift` (the entire file).

**Apply to:** `validationLedgerUITests/Loads/LoadsListSmokeTests.swift`. The launch-arg mock OTP role + driveFullOTPFlow + per-role tab assertion are all reusable verbatim. The Phase 8 ADDITION is: after the tab-button existence asserts, tap "Loads" (or "Invoices" for factoring per § File 8 open question) and assert `app.collectionViews["loads-list"]` exists with at least one row prefixed `loads-list.row.VL-`.

---

## Accessibility-Identifier Inventory (UI-SPEC § Copywriting — locked)

The planner / executor must wire EXACTLY these identifiers (XCUITest stable locators):

| Identifier | Owner |
|------------|-------|
| `loads-list` | the `UICollectionView` on each role's Loads tab |
| `loads-list.row.{loadID}` | each `LoadRowCell` (e.g. `loads-list.row.VL-1001`) |
| `loads-list.row.{loadID}.verification-badge` | `VerificationBadgeView` inside the row |
| `loads-list.row.{loadID}.status-badge` | `LoadStatusBadgeView` inside the row |
| `loads-list.refresh-control` | the `UIRefreshControl` attached to the collection view |
| `loads-list.empty-state` | the empty `UIContentUnavailableView` |
| `loads-list.error-state` | the error `UIContentUnavailableView` |
| `loads-list.error-state.retry` | the "Try again" `UIButton` |
| `loads-list.loading-indicator` | the loading-state container (skeleton background view) |

---

## No Analog Found — Summary

| File | Closest "almost-analog" | Why no exact analog |
|------|-------------------------|---------------------|
| `VerificationBadgeView.swift` | `LimitedTrustBannerView.swift` (DS-token-only `UIView` subclass) | No pill / inline-tag component exists in v1.1 source |
| `LoadStatusBadgeView.swift` | same as above | same |
| `LoadRowCell.swift` | none — first `UICollectionView*Cell` in the codebase | every shipped v1.0 surface used `UIStackView`-based content; cells are new ground |
| `SkeletonLoadRowCell.swift` | none — first skeleton/shimmer in the codebase per D-10 | the v1.0 KYC status precedent uses a centered `UIActivityIndicatorView` — preserved as-is per D-10 |

The planner must construct these four from the UI-SPEC contract + RESEARCH §Standard Stack (CAGradientLayer + CABasicAnimation, UICollectionView.CellRegistration, UIContentUnavailableConfiguration), with the DS-token-only styling discipline and the locked accessibility identifiers.

---

## Metadata

**Analog search scope:**
- `validationLedger/**/*.swift` (53 files scanned)
- `validationLedgerTests/**/*.swift` (test analogs)
- `validationLedgerUITests/**/*.swift` (XCUITest analog)
- `validationLedgerTests/Networking/Fixtures/*.json` (fixture analogs)

**Files scanned (key reads):**
- `KYCStatusViewController.swift` (361 lines — primary VC analog)
- `KYCStatusViewModel.swift` (268 lines — primary VM analog)
- `LoadListEndpoint.swift` (63 lines — modified file)
- `Load.swift` + `ChainOfTrust.swift` + `VerificationState.swift` + `LoadStatus.swift` (domain types)
- `ShipperTabBarController.swift` + 4 sibling tab bars
- `AppContainer.swift` (key composition-root sections)
- `AppCoordinator.swift` lines 191–227 (role-coordinator factory wiring)
- `RoleCoordinator.swift` (wrap helper)
- `MockLoadFixtureRegistry.swift` (registry analog + inline payload table)
- `MockURLProtocol.swift` lines 120–195 (latency + forced-failure injectors)
- `Role.swift` + `DesignSystem/*.swift` (3 files)
- `RoleShellSmokeTests.swift` (157 lines — UI smoke analog)
- `KYCThumbnailTests.swift` lines 32–42 (snapshot rendering recipe)
- `MockURLProtocolLatencyTests.swift` (Swift Testing + MockURLProtocol pattern)
- `loads-list-broker.json` first 200 lines (fixture shape analog)
- `loads-list-empty.json` (4 lines)

**Stale intel NOT used:** `.planning/codebase/*.md` (all 7 files dated 2026-04-21, describe a "SwiftUI scaffold" that does not match the current source tree per CONTEXT.md §Canonical References "Local repo intel that's stale — do NOT rely on").

**Pattern extraction date:** 2026-05-19

---

## PATTERN MAPPING COMPLETE

**Phase:** 08 — role-filtered-load-list
**Files classified:** 22 (15 NEW + 7 MODIFIED, plus 1 NEW directory triplet)
**Analogs found:** 18 / 22

### Coverage
- Files with exact analog: 10
- Files with role-match analog: 8
- Files with no analog: 4 (VerificationBadgeView, LoadStatusBadgeView, LoadRowCell, SkeletonLoadRowCell — construction guide provided)

### Key Patterns Identified
- VC + VM mirror `KYCStatusViewController` / `KYCStatusViewModel` verbatim (state-machine, fetch-on-appear, `UIRefreshControl`, initializer-DI). The ONLY divergence is loading-visual (skeleton instead of spinner) and the list-based content body (collection view + diffable datasource instead of a stack view).
- `LoadListItem` envelope decodes without explicit `CodingKeys` under `.convertFromSnakeCase` — synthesized optional handles fail-closed nil counterparty per D-03.
- `AppContainer.makeLoadListScreen(role:)` mirrors `makeKYCStatusScreen()` (composition-root factory closure), plumbed through `AppCoordinator.roleCoordinator(for:container:)` + each `*TabBarController.init` exactly as `kycStatusScreenFactory` was in Phase 5.
- Fixture envelope wrap is a coordinated edit across (a) 6 JSON files under `validationLedgerTests/Networking/Fixtures/`, (b) the inline AUTHORITATIVE COPY in `MockLoadFixtureRegistry.swift` `listPayloads` — the planner must surface this lockstep requirement.
- 4 NEW UI components (the two badges + the two cells) have no in-tree analog — construction guide provided, anchored in DS tokens + UI-SPEC §Color §Spacing §Typography contracts + Apple-first-party APIs (`UICollectionView.CellRegistration`, `CAGradientLayer`/`CABasicAnimation`, `UIContentUnavailableConfiguration`).

### File Created
`/Users/ustatb01/development/mobileApps/validation-ledger-mobile/.planning/phases/08-role-filtered-load-list/08-PATTERNS.md`

### Ready for Planning
Pattern mapping complete. Planner can now reference analog patterns + concrete excerpts in PLAN.md files.

### Open Questions Surfaced for the Planner
1. **Factoring tab naming.** The first tab in `FactoringTabBarController.swift` is "Invoices" (line 33), not "Loads". The 5-role smoke UI test asserts `tabBars.buttons["Invoices"]` for factoring. Per RESEARCH/CONTEXT, factoring DOES consume the per-role load list (the `loads-list-factoring.json` fixture exists). Two options: (a) rename to "Loads" (breaks XCUITest), or (b) keep "Invoices" and back it with `LoadListViewController(.factoring)`. Recommended: (b).
2. **Error message threading.** The UI-SPEC pins both the error heading ("We couldn't load loads") and the error body ("Check your connection and try again. Your loads are safe."). The VM's `.error(message: String)` payload threads ONE string. Options: (a) thread the body, hardcode the heading on the VC; (b) collapse to no-associated-value `.error` and let the VC hardcode both. (a) preserves VM-side error-classification flexibility for telemetry. Recommended: (a).
3. **Degraded-fixture exposure mechanism.** Either (a) sentinel role path `/loads/degraded` in `MockLoadFixtureRegistry`, or (b) a sibling `registerDegradedDemoLane()` method gated by an `AppContainer`-static DEBUG flag (mirrors the `KYCUITestSeed` discipline). Recommended: (b) for consistency with the existing DEBUG test-seam pattern.
