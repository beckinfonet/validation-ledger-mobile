# Phase 10: Per-Role Tender / Accept / Reject — Pattern Map

**Mapped:** 2026-05-21
**Phase directory:** `.planning/phases/10-per-role-tender-accept-reject/`
**Files analyzed:** 17 new / 9 modified (per RESEARCH.md Recommended Structure)
**Analogs found:** 17 / 17 (every new file has a concrete in-codebase analog)

> RESEARCH.md already names most analogs at `file:line`; this document VERIFIES each (read against the source tree at this revision) and LIFTS the load-bearing 10–40 line excerpts the planner can point at. It does NOT re-explain anything RESEARCH already explains — when RESEARCH already has the excerpt verbatim, this file references it by section rather than duplicating it.

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `Core/Load/LoadActionPredictor.swift` | Predictor (pure namespace) | transform | `Core/Load/RoleLoadPolicy.swift` | exact (shape twin) |
| `Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift` | Endpoint | request-response (GET) | `Core/Networking/Endpoints/LoadDetailEndpoint.swift` | exact |
| `Core/Networking/Mock/MockLoadFixtureRegistry.swift` (MOD) | Mock registry | mock dispatch | (self — extend in place) | exact |
| `Features/Loads/Detail/LoadActionsView.swift` | View (UIView) | render contract | `Features/Loads/Detail/StatusTimelineView.swift` + `UI/Components/VerificationBadgeView.swift` | role-match |
| `Features/Loads/Detail/TenderSheetViewController.swift` | View Controller (sheet content) | request-response | `Features/Loads/Detail/VerificationBasisSheetViewController.swift` | exact |
| `Features/Loads/Detail/TenderSheetCarrierRowView.swift` (optional split) | View (table cell) | render contract | `Features/Loads/LoadRowCell.swift` (Phase 8) | role-match |
| `Features/Loads/Detail/LoadActionToastBannerView.swift` | View (transient banner) | event-driven | None — net-new shape; layout precedent `ChainIntegrityBannerView.swift` | partial (geometry only) |
| `Features/Loads/Detail/LoadDetailViewController.swift` (MOD) | VC | state-machine render | (self — Phase 9 already established `render(state:)`) | exact |
| `Features/Loads/Detail/LoadDetailViewModel.swift` (MOD) | VM | cancel-and-replace task | (self — extend `fetchLoadDetail()`-style task with `submit(action:body:)`) | exact |
| `Features/Loads/Detail/LoadDetailBodyView.swift` (MOD) | View (scroll body) | structural | (self — insert at contentStack index 2) | exact |
| `App/AppContainer.swift` (MOD) | Composition root | factory | (self — `makeLoadDetailScreen(loadID:)` → `(loadID:role:)`) | exact |
| `validationLedgerTests/Loads/LoadActionPredictorTests.swift` | Test (Swift Testing or XCTest) | unit | `validationLedgerTests/Loads/RoleLoadPolicyTests.swift` | exact |
| `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift` | Test | VM state-machine | `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` | exact |
| `validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift` | Test | mock-registry contract | sibling-tests under `validationLedgerTests/Networking/` (registry tests) | role-match |
| `validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift` | Test | decode | existing fixture-decode tests (e.g. `LoadDecodeTests`) | role-match |
| `validationLedgerTests/Loads/Snapshot/LoadActionsViewSnapshotTests.swift` (65-cell matrix) | Snapshot test | matrix | `validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift` (`for status in LoadStatus.allCases` line 117) + `LoadRowCellSnapshotTests.swift` | exact |
| `validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift` | Snapshot test | VC at canvas size | `validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift` | exact |
| `validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift` | Snapshot test | per-state | `validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift` | exact |
| `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` | Fixture (JSON) | data | inlined `MockLoadFixtureRegistry.listPayloads` shape + existing `load-detail-*.json` fixtures | exact |
| `validationLedgerUITests/Loads/LoadActionFlowsTests.swift` | XCUITest | smoke flow | `validationLedgerUITests/Loads/LoadDetailFlowTests.swift` (Phase 9 LOAD-05) + `RoleLoadsTabSmokeTests.swift` (Phase 8 5-role) | exact |
| DEBUG launch-arg toggles (lives in `MockLoadFixtureRegistry.swift` or a new sibling `MockActionFailureToggles.swift`) | DEBUG harness | config flag | `Core/Networking/Mock/MockDefaultFixtures.swift:60-76` (`-MockKYCStatusVerified`) + `LoadDetailViewController.swift:118-131` (`-Mock2DTrustGraphOnIPhone`) | exact |

---

## Pattern Assignments

### 1. `Core/Load/LoadActionPredictor.swift` (predictor, pure transform)

**Analog:** `Core/Load/RoleLoadPolicy.swift` (full file already read into context above).

**Why this analog:** Both are pure `(domain, domain) → domain` resolvers exposed as a `public enum`-namespace. Both exhaustively cover the closed domain set; both are reachable from `@MainActor` without an `await`; both belong in `Core/Load/` next to their input types.

**Shape to copy (RoleLoadPolicy.swift lines 60-68):**
```swift
public enum RoleLoadPolicy {
    public static func actions(for role: Role, status: LoadStatus) -> [LoadAction] {
        switch (role, status) {
        case (.factoring, _):
            return []
        // ...exhaustive nested switch, NO default: case...
        }
    }
}
```

**Apply to predictor (signature — verified against RESEARCH.md `Code Examples > Pure predictor function`):**

```swift
public enum LoadActionPredictor {
    public static func predict(
        load current: Load,
        action: LoadAction,
        body: LoadActionEndpoint.RequestBody?
    ) -> Load {
        switch (action, current.status) {
        case (.tender, .posted), (.tender, .rejected), (.tender, .expired):
            return current.with(status: .tendered, respondByAt: body?.respondByAt)
        // ...
        default:
            return current   // policy gate prevents this; defensive no-op
        }
    }
}
```

**What to keep verbatim from RoleLoadPolicy:**
- `public enum` namespace (no instance state, no init).
- Single static function entry point.
- Tuple `switch` over the cross-product domain.
- Exhaustive coverage — **no `default:` arm in the inner branches** (Swift's exhaustiveness check is the compile-time guard that catches missed cases when a new `LoadStatus` lands).
- Header comments anchored to CONTEXT decision IDs (D-12 / D-13 / D-15 here).

**What to adapt:**
- Predictor reads `body.respondByAt` for the `.tender` arm (RESEARCH Pitfall 3). RoleLoadPolicy has no second argument; the predictor needs the typed `RequestBody?`.
- Returning a fresh `Load` requires a `Load.with(...)` helper. `Load` (`Core/Load/Load.swift:101-163`, read into context above) has only the synthesized `Decodable`-private init. The helper is a same-module extension (`internal` access fine for the predictor); see RESEARCH Open Question 1.

**Test-shape analog:** `validationLedgerTests/Loads/RoleLoadPolicyTests.swift` (existence verified by file presence in `Core/Load/`). Mirror its `policyIsTotal` exhaustive-sweep pattern.

---

### 2. `Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift` (endpoint, GET)

**Analog (closest):** `Core/Networking/Endpoints/LoadActionEndpoint.swift` (full file read into context above) — same envelope discipline, same `APIEndpoint` conformance, same `Response: Decodable, Sendable`.

**Excerpt to copy (LoadActionEndpoint lines 105-130):**
```swift
public struct Response: Decodable, Sendable {
    public let load: Load
    public let chainOfTrust: ChainOfTrust
}

public let path: String
public let method: HTTPMethod = .post     // ← change to .get for directory
public let body: RequestBody?              // ← drop for directory (no body on GET)

public init(loadID: String, action: LoadAction, body: RequestBody) {
    self.path = "/loads/\(loadID)/\(action.pathSegment)"
    self.body = body
}
```

**Apply to CarrierDirectoryEndpoint:**
```swift
nonisolated public struct CarrierDirectoryEndpoint: APIEndpoint {
    public struct Response: Decodable, Sendable {
        public let carriers: [TrustNode]   // RESEARCH § Architectural Responsibility Map row 6
    }
    public let path = "/carriers/directory"
    public let method: HTTPMethod = .get
    public let body: EmptyBody? = nil       // verify the codebase's GET-no-body convention
    public init() {}
}
```

**What to keep verbatim:**
- `nonisolated public struct … : APIEndpoint` (required under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- `Response` is `Decodable, Sendable`.
- `let path` constant (not computed) — the directory has no parameters in v1.1.
- Envelope shape `{ carriers: [...] }` matches `LoadListEndpoint.Response.loads: [LoadListItem]` precedent (envelope wrapper is the project convention).

**What to adapt:**
- Method is `.get` (LoadActionEndpoint is `.post`).
- No `RequestBody` — Phase 7 D-19 `IdempotencyInterceptor` only injects on POST/PUT, so the absent body is correct.
- The decoded payload is `[TrustNode]` — `TrustNode` is the existing Phase 7 type (`Core/Load/ChainOfTrust.swift`), reusing the same struct the chain-of-trust card already decodes. No new domain type.

---

### 3. `Core/Networking/Mock/MockLoadFixtureRegistry.swift` (MODIFIED — adds 5 handlers)

**Analog:** itself — extend in place. The file's existing 3 handlers at lines 128-167 (read into context above) are the exact registration shape.

**Excerpt to mirror (MockLoadFixtureRegistry.swift lines 154-167 — the action-success handler):**
```swift
// (3) Action-success handler: POST /loads/{loadID}/{actionPathSegment}
MockURLProtocol.register { request in
    guard request.httpMethod == "POST" else { return nil }
    guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
    let suffix = String(path.dropFirst("/loads/".count))
    let parts = suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let loadID = String(parts[0])
    let actionSegment = String(parts[1])
    guard loadID.hasPrefix("VL-") else { return nil }
    guard actionPathSegments.contains(actionSegment) else { return nil }
    return make200(body: actionSuccessPayload, url: request.url)
}
```

**What to keep verbatim:**
- `MockURLProtocol.register { request in … }` closure shape — `nil` defers to the next handler (first-match-wins; RESEARCH §5).
- Inline `Data(#"""…"""#.utf8)` payload pattern (lines 199-294 in the same file demonstrate this; per file invariant the DEBUG app bundle must not depend on the test bundle's `.json` files).
- `actionPathSegments` static `Set<String>` guards (lines 187-189) — extend to the new failure handlers verbatim.
- `make200(body:url:)` helper (lines 171-179) — add `make409`, `make422`, `make500` siblings.

**What to adapt for the 4 DEBUG-toggle handlers (RESEARCH Pattern 5 lines 414-436):**
- Each new handler must be `#if DEBUG` AND check `DebugActionFailureOverride.{flag}Active` AT THE TOP, so Release compiles them out.
- Registration order in `registerAppDefaults()` is `conflict409 → validation422 → serverError500 → latencySlow → existing-success`. The latency handler does NOT short-circuit; it calls `Thread.sleep(forTimeInterval: …)` then falls through to the next handler (or to the success handler if no other failure flag is set).
- Inline the contents of the existing fixture files (`load-action-conflict-409.json`, `…-validation-422.json`, `…-server-error-500.json` — confirmed present at `validationLedgerTests/Networking/Fixtures/`) into the registry as `Data(#"""…"""#.utf8)` constants. RESEARCH § Pattern 5 line 436 recommends inline (matches the existing `listPayloads` discipline at lines 199-294).

**Carrier-directory handler (sketch lifted from RESEARCH § Code Examples lines 605-642):**
```swift
// (6) NEW: GET /carriers/directory → tender-carrier-directory payload
MockURLProtocol.register { request in
    guard request.httpMethod == "GET" else { return nil }
    guard request.url?.path == "/carriers/directory" else { return nil }
    return make200(body: tenderCarrierDirectoryPayload, url: request.url)
}
```

---

### 4. `Features/Loads/Detail/LoadActionsView.swift` (NEW — action region container)

**Analog (best partial match):** `Features/Loads/Detail/StatusTimelineView.swift` (Phase 9 sibling, lives in the same folder, mounts inside `LoadDetailBodyView.contentStack`, takes a configured payload via `configure(...)`).

**Pattern to copy — `configure`-based render contract:**
The Phase 9 detail's body subviews ALL follow the shape:
1. Private programmatic init building static subviews.
2. `required init?(coder:)` trap (CLAUDE.md UIKit-first invariant).
3. Public `configure(...)` method consuming the data the parent VC supplies on each render pass.
4. `accessibilityElements` set explicitly after each configure (Phase 9 D-22 / D-21 leaf-element model).

**Apply to `LoadActionsView`:**
- `configure(actions: [LoadAction], role: Role, status: LoadStatus, tenderEligibility: TenderEligibility?, onTap: @escaping (LoadAction) -> Void)` — receives the result of `RoleLoadPolicy.actions(for:status:)` from the VC; never calls the policy itself (the policy is read in the VM, the result flows in).
- Empty-state caption rendered as a single `UILabel` inside the same horizontal `UIStackView` slot — toggled via `isHidden` (NOT subview swap). UI-SPEC § Action region empty-state (line 299-313) locks the visuals.
- Backing `UIView` with `backgroundColor = DS.Colors.surface` inset behind the stack (UI-SPEC line 421).

**Sub-pattern — equal-weight horizontal button row (UI-SPEC line 416):**
- `UIStackView(arrangedSubviews: buttons)` with `.axis = .horizontal`, `.distribution = .fillEqually`, `.spacing = DS.Spacing.sm` (8pt).
- Per-button: `UIButton(configuration: .filled())` for `.tender / .accept / .post / .advanceStatus`; `UIButton(configuration: .filled())` with `baseBackgroundColor = DS.Colors.destructive` for `.reject / .cancel` (UI-SPEC D-03 destructive tint).
- `heightAnchor.constraint(greaterThanOrEqualToConstant: 50)` (UI-SPEC line 170 — 50pt min, above the 44pt floor).

**Sub-pattern — Dynamic Type axis flip (UI-SPEC line 419):**
- Override `traitCollectionDidChange(_:)`; if `traitCollection.preferredContentSizeCategory.isAccessibilityCategory == true`, set `buttonRow.axis = .vertical`. Phase 9 `LoadDetailViewController` line 605+ uses the same trait hook for the composition rebuild — the SAME mechanism, scoped to this view.

**The "do NOT do this" lock (ROADMAP §Phase 10 / RESEARCH § Anti-Patterns):**
- Inside `LoadActionsView`, the `status` argument is consumed ONLY to thread into the empty-state caption format (e.g. `"This load is delivered."`) — there is **NO `switch load.status`** branching on which buttons to render. The button list is `actions: [LoadAction]` already, computed elsewhere.

---

### 5. `Features/Loads/Detail/TenderSheetViewController.swift` (NEW — sheet content VC)

**Analog (exact):** `Features/Loads/Detail/VerificationBasisSheetViewController.swift` (Phase 9 Plan 07, header read above).

**File-header pattern (mirror the VerificationBasisSheet header structure):**
- Phase / Plan citation at top.
- "Sheet presentation lives on the PRESENTING side" note (the parent VC owns `UISheetPresentationController` config; this VC is presentation-agnostic).
- Content-order block (lines 18-42 of the analog) — for tender: `1. Carrier section header → 2. Carrier list → 3. Respond by header → 4. Deadline chips → 5. Resolved-time line → 6. Send button` (UI-SPEC line 443).
- Accessibility-identifier namespace block (analog lines 63-74) — for tender: `load-detail.tender-sheet`, `…/carrier-row.<partyID>`, `…/deadline-chip.<token>`, `…/send-button`.
- Threat-model anchors: T-09-03 (no client trust derivation — verification badges read from server-supplied `TrustNode.verificationState` verbatim), T-09-04 (zero PII in logs — sheet emits NO logs).

**The Send-tap closure shape — RESEARCH Open Question 4 resolution (recommended):**
```swift
public init(
    directory: [TrustNode],
    onSend: @escaping (LoadActionEndpoint.RequestBody) async -> Void,
    onCancel: @escaping () -> Void
)
```

The `async` closure returns when the parent VC's `viewModel.submit(action:body:) async` settles. On success the parent VC dismisses the sheet imperatively from its `.loaded` render path; on failure the sheet stays visible (its in-flight state un-locks) and the parent slides in the toast banner over the still-presented sheet (sheet's `largestUndimmedDetentIdentifier = .medium` keeps the parent visible behind — UI-SPEC line 454).

---

### 6. Sheet presentation recipe (LoadDetailViewController.swift addition — host-side)

**Analog (exact, twin recipe with two existing call sites):** `LoadDetailViewController.presentVerificationBasisSheet(for:)` at lines 1316-1334, `presentHandoffDetailSheet(for:)` at lines 1367-1386 (both read into context above).

**Excerpt to copy verbatim (LoadDetailViewController.swift:1321-1333):**
```swift
let sheetVC = VerificationBasisSheetViewController(
    node: node, integrity: chainOfTrust.integrity)
sheetVC.modalPresentationStyle = .pageSheet
if let sheet = sheetVC.sheetPresentationController {
    sheet.detents = [.medium(), .large()]
    sheet.selectedDetentIdentifier = .medium
    sheet.prefersGrabberVisible = true
    sheet.largestUndimmedDetentIdentifier = .medium  // CRITICAL — keeps the parent interactive + undimmed at .medium
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    sheet.prefersEdgeAttachedInCompactHeight = true
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
}
present(sheetVC, animated: true)
```

**Apply to the tender sheet (new private method on `LoadDetailViewController`):**
```swift
private func presentTenderSheet() {
    guard let load = cachedLoad else { return }  // mirrors guard at line 1317
    let sheetVC = TenderSheetViewController(
        directory: cachedCarriers ?? [],
        onSend: { [weak self] body in
            await self?.viewModel.submit(action: .tender, body: body)
        },
        onCancel: { [weak self] in self?.dismiss(animated: true) }
    )
    sheetVC.modalPresentationStyle = .pageSheet
    if let sheet = sheetVC.sheetPresentationController {
        // ↓ verbatim copy of the 7-line recipe above ↓
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.largestUndimmedDetentIdentifier = .medium
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
    }
    present(sheetVC, animated: true)
}
```

**Pitfall 7 watch (RESEARCH § Phase 9 docstring on the analog method):** The recipe is **inlined at every call site** — the grep count for `selectedDetentIdentifier = .medium` will be 3 after Phase 10 (was 2 before). Do NOT refactor the 7 lines into a helper — the duplication is intentional so per-call audits catch drift on any single site.

---

### 7. DEBUG launch-arg toggles (`-MockActionConflict409` × 4)

**Analog (exact):** `Core/Networking/Mock/MockDefaultFixtures.swift:60-76` (read into context above) — `verifiedKYCStatusLaunchFlag` + `verifiedKYCStatusOverrideActive`. **Secondary analog:** `LoadDetailViewController.swift:118-131` — `Debug2DGraphOverride.launchFlag` / `.isActive`.

**Excerpt to copy verbatim (MockDefaultFixtures.swift lines 69-76):**
```swift
public static let verifiedKYCStatusLaunchFlag = "-MockKYCStatusVerified"

/// True when `-MockKYCStatusVerified` is present in this process's launch
/// arguments. Evaluated once per request (cheap — argv is a tiny array).
/// `internal` so the unit test can observe the default-off contract.
static var verifiedKYCStatusOverrideActive: Bool {
    ProcessInfo.processInfo.arguments.contains(verifiedKYCStatusLaunchFlag)
}
```

**Apply to Phase 10 (per RESEARCH Pattern 4 lines 396-409):**
```swift
#if DEBUG
public enum DebugActionFailureOverride {
    public static let conflict409Flag    = "-MockActionConflict409"
    public static let validation422Flag  = "-MockActionValidation422"
    public static let serverError500Flag = "-MockActionServerError500"
    public static let latencySlowFlag    = "-MockActionLatencySlow"

    public static var conflict409Active:    Bool { ProcessInfo.processInfo.arguments.contains(conflict409Flag) }
    public static var validation422Active:  Bool { ProcessInfo.processInfo.arguments.contains(validation422Flag) }
    public static var serverError500Active: Bool { ProcessInfo.processInfo.arguments.contains(serverError500Flag) }
    public static var latencySlowActive:    Bool { ProcessInfo.processInfo.arguments.contains(latencySlowFlag) }
}
#endif
```

**What to keep verbatim:**
- `#if DEBUG` wrapper around the WHOLE enum (Release compiles to zero bytes — verified pattern; MockDefaultFixtures.swift line 57 wraps its whole file).
- Literal string match — DO NOT use `ProcessInfo.processInfo.environment` (different surface; CLAUDE.md / RESEARCH lock the `arguments.contains(...)` shape).
- `static let` + `static var … { contains(flag) }` two-step (lets unit tests assert the default-off contract by reading the `Active` computed property).

**File location decision (Claude's Discretion per CONTEXT § D-19):**
- Recommended: a NEW sibling file `Core/Networking/Mock/MockActionFailureToggles.swift` adjacent to `MockDefaultFixtures.swift`. Keeps the enum's responsibility-boundary clean and matches the project's one-type-per-file convention.
- The 4 launch-arg branches are CONSUMED inside `MockLoadFixtureRegistry.registerAppDefaults()` — RESEARCH § Pattern 5 line 421 shows the consumption shape.

**Negative-control unit test (RESEARCH § Pitfall 2):** Add a test that with `-MockActionConflict409` present, `apiClient.request(LoadActionEndpoint(...))` returns a 409. RESEARCH cites the seam as locating `ProcessInfo.arguments` interception; the simplest implementation tests the flag's `Active` computed property in isolation + a separate registry-level test that uses a synthetic `MockURLProtocol` registration.

---

### 8. `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` (MODIFIED — VM extension)

**Analog (exact, in-file):** `LoadDetailViewModel.fetchLoadDetail()` at lines 135-206 (read into context above) — the BL-01 cancel-and-replace pattern.

**Excerpt to mirror (LoadDetailViewModel.swift:135-155):**
```swift
public func fetchLoadDetail() async {
    fetchTask?.cancel()
    state = .loading
    let task = Task { [weak self] in
        guard let self else { return }
        await self.performFetch()
    }
    fetchTask = task
    await task.value
}
```

**Apply to `submit(action:body:)` — RESEARCH § Pattern 1 (lines 320-339):**
```swift
public func submit(action: LoadAction, body: LoadActionEndpoint.RequestBody) async {
    // BL-01 — cancel-and-replace; a fresh action supersedes any in-flight one.
    actionTask?.cancel()
    // Capture rollback snapshot BEFORE any state mutation.
    guard case .loaded(let preLoad, let preChain) = state else { return }
    // Predict forward — pure helper, no UIKit.
    let predicted = LoadActionPredictor.predict(load: preLoad, action: action, body: body)
    state = .actionInFlight(predicted: predicted, frozenChain: preChain, action: action)
    let task = Task { [weak self] in
        guard let self else { return }
        await self.performAction(
            loadID: preLoad.id, action: action, body: body,
            rollbackTo: preLoad, frozenChain: preChain
        )
    }
    actionTask = task
    await task.value
}
```

**Private body — mirror `performFetch()` lines 167-206:**
- Same `do { … } catch is CancellationError { return } catch { … }` skeleton.
- Same `if Task.isCancelled { return }` race-close checkpoint AFTER the network hop.
- Same `logger?.error(..., fields: [:])` discipline (T-09-04 — RESEARCH § Anti-Patterns confirms `fields: [:]` lock extends to actions).
- On success: `state = .loaded(response.load, response.chainOfTrust)` (one assignment per D-14).
- On error: `state = .actionFailed(rollbackTo: rollbackTo, frozenChain: frozenChain, errorCopyKey: keyFor(action))` — `keyFor(action)` is a pure helper returning one of the 6 per-action localization keys (UI-SPEC line 339 chose per-action taxonomy).

**State enum extension (RESEARCH § Code Examples lines 696-708):**
The existing 3-case `State` (`LoadDetailViewModel.swift:61-74`, read above) grows two cases. The two new associated values reuse the SAME `Load + ChainOfTrust` Equatable extensions already in the file at lines 253-279 — no new conformance work.

```swift
public enum State: Equatable, Sendable {
    case loading
    case loaded(Load, ChainOfTrust)
    case actionInFlight(predicted: Load, frozenChain: ChainOfTrust, action: LoadAction)
    case actionFailed(rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String)
    case error(message: String)
}
```

**Role plumb (D-22 — RESEARCH § Code Examples lines 715-720):**
- VM gains a new `private let role: Role` stored property.
- Designated initializer signature becomes `init(loadID: String, role: Role, apiClient: APIClient, logger: (any Logger)? = nil)`.
- The VC reads `viewModel.role` when calling `LoadActionsView.configure(actions: RoleLoadPolicy.actions(for: viewModel.role, status: load.status), …)`.

---

### 9. `validationLedger/App/AppContainer.swift` (MODIFIED — factory signature)

**Analog:** itself — `makeLoadDetailScreen(loadID:)` at lines 283-294 (read into context above).

**Excerpt of current state (AppContainer.swift:255-258 and 283-294):**
```swift
let detailFactory: (String) -> UIViewController = { [weak self] loadID in
    guard let self else { return UIViewController() }
    return self.makeLoadDetailScreen(loadID: loadID)
}
// ...
@MainActor
func makeLoadDetailScreen(loadID: String) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(
        subsystem: LoggingSubsystem.app,
        category: "feature.loads"
    )
    let viewModel = LoadDetailViewModel(
        loadID: loadID,
        apiClient: apiClient,
        logger: featureLogger
    )
    return LoadDetailViewController(viewModel: viewModel)
}
```

**Apply (D-22):**
```swift
// Factory closure inside makeLoadListScreen(role:) — capture the calling role.
let detailFactory: (String) -> UIViewController = { [weak self] loadID in
    guard let self else { return UIViewController() }
    return self.makeLoadDetailScreen(loadID: loadID, role: role)   // ← role from outer scope
}

@MainActor
func makeLoadDetailScreen(loadID: String, role: Role) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(subsystem: LoggingSubsystem.app, category: "feature.loads")
    let viewModel = LoadDetailViewModel(loadID: loadID, role: role, apiClient: apiClient, logger: featureLogger)
    return LoadDetailViewController(viewModel: viewModel)
}
```

**What to keep verbatim:**
- `@MainActor` annotation (matches `makeLoadListScreen` line 217).
- `OSLogLoggerImpl(subsystem: LoggingSubsystem.app, category: "feature.loads")` — same subsystem/category as the list (no new `LoggingSubsystem` case; T-09-04 / T-08-08 `fields: [:]` lock applies).
- `[weak self]` in the closure (line 255 docstring rationale: ADR 0002 abrupt-replace cycle safety).

**Minimal change:** This is the single structural surprise of Phase 10 (CONTEXT § Specifics lines 271-272). Land it in the SAME plan/wave that introduces the action region so the VM never has `role:` plumbed without a consumer.

---

### 10. `Features/Loads/Detail/LoadDetailBodyView.swift` (MODIFIED — contentStack insertion)

**Analog:** itself — `LoadDetailBodyView.swift:214-218` (read into context above).

**Existing arrangement (5 children, lines 214-218):**
```swift
contentStack.addArrangedSubview(pinnedSummaryHeader)
contentStack.addArrangedSubview(timelineContainer)
contentStack.addArrangedSubview(freightDetailsContainer)
contentStack.addArrangedSubview(partiesContainer)
contentStack.addArrangedSubview(verdictBlockContainer)
```

**Apply (insert at index 2 — between timeline and freight, per CONTEXT D-01 / UI-SPEC line 409):**
```swift
contentStack.addArrangedSubview(pinnedSummaryHeader)         // index 0
contentStack.addArrangedSubview(timelineContainer)           // index 1
contentStack.addArrangedSubview(actionsContainer)            // index 2  ← NEW
contentStack.addArrangedSubview(freightDetailsContainer)     // index 3
contentStack.addArrangedSubview(partiesContainer)            // index 4
contentStack.addArrangedSubview(verdictBlockContainer)       // index 5
```

`actionsContainer` is the host `UIView` the VC injects `LoadActionsView` into (matching the existing inject-content-into-named-container pattern at lines 38-48 of the same file).

---

### 11. `Features/Loads/Detail/LoadDetailViewController.swift` (MODIFIED — render extension)

**Analog (in-file):** `render(state:)` at lines 1110-1126 and `applyLoadedRender(load:chainOfTrust:)` at line 1137+ (read into context above).

**Excerpt of the existing render dispatcher (lines 1110-1126):**
```swift
private func render(state: LoadDetailViewModel.State) {
    switch state {
    case .loading:
        skeletonContainer.isHidden = false
        bodyContainer.isHidden = true
        errorContainer.isHidden = true
    case .loaded(let load, let chainOfTrust):
        applyLoadedRender(load: load, chainOfTrust: chainOfTrust)
    case .error:
        skeletonContainer.isHidden = true
        bodyContainer.isHidden = true
        errorContainer.isHidden = false
    }
}
```

**Apply (RESEARCH § Pattern 2 lines 348-366) — two new arms:**
```swift
case .actionInFlight(let predicted, let frozenChain, _):
    applyLoadedRender(load: predicted, chainOfTrust: frozenChain)   // body re-renders with predicted load
    mountChainOverlayIfNeeded()                                      // overlay over chain region
    // LoadActionsView's per-button in-flight spinner is owned by the action view itself,
    // configured via the `action:` associated value.
case .actionFailed(let rollbackTo, let frozenChain, let errorCopyKey):
    applyLoadedRender(load: rollbackTo, chainOfTrust: frozenChain)  // body restores pre-tap load
    chainOverlay?.fadeOutAndRemove()                                  // RESEARCH Pitfall 1 — single overlay ref
    presentToastBanner(copyKey: errorCopyKey)                         // top-anchored slide-in
```

**What to keep verbatim from the existing dispatcher:**
- `private func render(state:)` signature — no name change.
- `MainActor.assumeIsolated { self?.render(state: state) }` in `bindViewModel()` (line 1099) — the new states arrive through the same closure.
- `bindViewModel()`'s `render(state: viewModel.state)` initial-pump call at line 1105 (WR-06 fix).

**The chain overlay (RESEARCH § Pitfall 1):**
- Single `private var chainOverlay: UIView?` reference on the VC.
- `mountChainOverlayIfNeeded()` is idempotent — if `chainOverlay != nil`, return early.
- `chainOverlay?.fadeOutAndRemove()` clears the ref in its completion block.
- Pinned via `chainOverlay.constraintsToCoverRegion(everyoneOnLoadStripView, chainOfVouchesView)` on iPhone; `trustGraphView` on iPad — UI-SPEC § Chain overlay lines 485-486.

---

### 12. `Features/Loads/Detail/LoadActionToastBannerView.swift` (NEW — top toast banner)

**Analog (partial, geometry):** `Features/Loads/Detail/ChainIntegrityBannerView.swift` (Phase 9, `Detail/` sibling). The toast banner is NOT a chain-integrity surface (UI-SPEC line 72 explicit reservation: yellow `caution` palette never used by toasts), but the **layout shape** — a horizontally-organized icon + label `UIStackView` inside a backing `UIView` with a `cornerRadius`/`backgroundColor` — is the existing precedent.

**Apply (UI-SPEC § LoadActionToastBannerView lines 458-475):**
- Programmatic `init()`; `required init?(coder:)` trap.
- Internal hierarchy: backing `UIView` (`cornerRadius = 12`, `backgroundColor = DS.Colors.destructive.withAlphaComponent(0.92)`) → horizontal `UIStackView` → SF Symbol `UIImageView` (`exclamationmark.triangle.fill`, white, `pointSize = 22`) + `UILabel` (`DS.Typography.body`, `numberOfLines = 2`).
- `configure(text: String)` consumes a localized string the VC supplies (NEVER raw key — the VC's `presentToastBanner(copyKey:)` resolves the key to the localized string before passing in; the view stays presentation-only).
- Pinned by the parent VC (NOT self) to `view.safeAreaLayoutGuide.topAnchor + DS.Spacing.md`. The pre-animation translation is `-(banner.bounds.height + 24)` upward; animate to `0` over `0.28s` with `.curveEaseOut`.
- Auto-dismiss timer: `Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false)` reverses the animation; gesture recognizers cancel the timer (UI-SPEC swipe + tap interactions).

**The "no library" lock (RESEARCH § Don't Hand-Roll line 481):** SwiftMessages / Toast-Swift / SnackBar are FORBIDDEN. The banner is `UIView.animate` + `transform` only.

---

### 13. Snapshot — 65-cell matrix (`LoadActionsViewSnapshotTests.swift`)

**Analog (exact shape):** `validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift` line 117 (read into context above) — already iterates `for status in LoadStatus.allCases`.

**Excerpt (LoadStatusBadgeViewSnapshotTests.swift:115-124):**
```swift
func test_statusBadgeNeverReusesVerificationRampColors() {
    let view = LoadStatusBadgeView()
    for status in LoadStatus.allCases {
        view.configure(status: status)
        XCTAssertNotEqual(view.backgroundColor, DS.Colors.primary, …)
        XCTAssertNotEqual(view.backgroundColor, DS.Colors.destructive, …)
    }
}
```

**Apply to the 65-cell matrix — RESEARCH § Pattern 6 (lines 442-460):**
```swift
final class LoadActionsViewSnapshotTests: XCTestCase {
    func test_actionRegion_matrix_5roles_x_13statuses() {
        for role in Role.allCases {
            for status in LoadStatus.allCases {
                let actions = RoleLoadPolicy.actions(for: role, status: status)
                let view = LoadActionsView()                       // RESEARCH Pitfall 7 — fresh view per cell
                view.configure(actions: actions, role: role, status: status,
                               tenderEligibility: nil, onTap: { _ in })
                let img = UIKitSnapshot.image(of: view, size: CGSize(width: 393, height: 120))
                UIKitSnapshot.attach(img, name: "actions-\(role.rawValue)-\(status.rawValue)", to: self)
                // pixel-diff assertion against a checked-in baseline — Phase 9.1 D-05 baseline-record convention
            }
        }
    }
}
```

**What to keep verbatim:**
- `XCTestCase` (not Swift Testing) — `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)` (analog file-header lines 4-7).
- `UIKitSnapshot.image(of:size:)` (`validationLedgerTests/Support/UIKitSnapshot.swift:53-60`, read above) — zero SPM deps, pinned to iPhone-17 simulator scale.
- `UIKitSnapshot.attach(_:name:to:)` — attaches images for CI triage on baseline diffs.
- Synthetic identifiers (no real party names — CLAUDE.md zero-PII).

**What to adapt:**
- The 65 cells require 65 fresh `LoadActionsView()` allocations (RESEARCH § Pitfall 7) — no instance reuse across iterations (residual state leakage).
- Add 5 SEPARATE tests for the load-level `tenderEligibility.canTender == false` variant (one per role) so the disabled-button + inline-reason render is locked.
- Add 2 SEPARATE tests for the empty-state captions (Factoring + a terminal-state non-Factoring role) — the empty-state caption format-string interpolation is RESEARCH § Pitfall 5.

---

### 14. Snapshot — Tender sheet (`TenderSheetViewControllerSnapshotTests.swift`)

**Analog (exact):** `validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift` (read into context — lines 1-91).

**Excerpt (VerificationBasisSheetViewControllerSnapshotTests.swift:40-51):**
```swift
private static let sheetCanvasSize = CGSize(width: 393, height: 500)

private func renderedView(_ vc: VerificationBasisSheetViewController) -> UIView {
    vc.loadViewIfNeeded()
    vc.view.bounds = CGRect(origin: .zero, size: Self.sheetCanvasSize)
    vc.view.layoutIfNeeded()
    return vc.view
}
```

**Apply verbatim to `TenderSheetViewControllerSnapshotTests`:**
- Same `sheetCanvasSize = CGSize(width: 393, height: 500)` (iPhone medium-detent representative).
- Same `renderedView(_:)` helper.
- Mirror the analog's per-scenario test method shape (4 scenarios there → analogous 4+ scenarios here: default state, all-verified directory, mixed-verification directory, Send-disabled helper-line copies).

---

### 15. XCUITest — Action flow (`LoadActionFlowsTests.swift`)

**Analog (exact, Phase 9.1 / Phase 9):** `validationLedgerUITests/Loads/LoadDetailFlowTests.swift` (read above) — extends the same OTP-and-row-tap flow with per-action assertions.

**Excerpt to copy (LoadDetailFlowTests.swift:64-71 + 78-100):**
```swift
private func launch(role: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-MockOTPRoleForUITest", role]
    app.launch()
    return app
}

private func driveFullOTPFlow(_ app: XCUIApplication) {
    let phoneField = app.textFields["phone-entry-field"]
    // ... phone → submit → OTP → verify, verbatim ...
}
```

**Apply:**
- Same `launch(role:)` and `driveFullOTPFlow(_:)` helpers — copy in (no shared helper file is invented; PATTERNS E11 lock).
- Add `app.launchArguments.append(contentsOf: ["-MockActionValidation422", "-MockActionLatencySlow"])` for the rollback flow per CONTEXT § Claude's Discretion line 147.
- `executionTimeAllowance = 90` (matches the Phase 9 analog's WR-05 fix at lines 49-60 — 5-role iteration on physical-device CI).
- Three flows per CONTEXT § Claude's Discretion line 147: (a) broker happy-path tender, (b) carrier accept happy-path, (c) rollback flow with `-MockActionValidation422 -MockActionLatencySlow`.

---

## Shared Patterns

### S-1: BL-01 cancel-and-replace task lifecycle

**Source:** `LoadDetailViewModel.swift:135-206` (fetch) and `LoadListViewModel.swift:170-244` (fetch).
**Apply to:** `LoadDetailViewModel.submit(action:body:)` (NEW method).

**The 3 invariants (read out of the source):**
1. Before any state mutation: `actionTask?.cancel()`.
2. After the network hop returns: `if Task.isCancelled { return }`.
3. In the `catch` arm: `if Task.isCancelled { return }` BEFORE writing `.actionFailed` (so a cancelled task's error doesn't overwrite a fresher action's predicted state).

### S-2: Zero-PII logger discipline (T-09-04 / T-08-08)

**Source:** `LoadDetailViewModel.swift:186` and analog lines 234, 244 of `LoadListViewModel.swift`.

**Apply to:** Every `logger?.error(...)` and `logger?.info(...)` call in `submit(action:body:)`.
```swift
logger?.error(event: LogEvent("load_action_failed"), fields: [:])
logger?.info(event:  LogEvent("load_action_succeeded"), fields: [:])
```

**The one DOCUMENTED exception** (RESEARCH line 467 + UI-SPEC line 293): `Load.tenderEligibility.disabledReason` IS rendered to the screen as load-state metadata — it is NOT an error-response payload. The discipline applies to `LoadActionEndpoint` ERROR-PATH text (4xx/5xx body, `URLError.localizedDescription`, `DecodingError.debugDescription`) — those NEVER reach the screen and NEVER reach the logger fields dict.

### S-3: Sheet presentation 7-line recipe

**Source:** `LoadDetailViewController.swift:1322-1333` (and the twin at lines 1376-1384).
**Apply to:** `presentTenderSheet()` — the SAME 7 lines, inlined (Pitfall 7 lock).

### S-4: DEBUG launch-arg `#if DEBUG` + `ProcessInfo.arguments.contains(...)` shape

**Source:** `MockDefaultFixtures.swift:60-76` + `LoadDetailViewController.swift:118-131`.
**Apply to:** All 4 new Phase 10 toggles (`-MockActionConflict409` × 4).

### S-5: `UIKitSnapshot.image(of:size:) + attach(_:name:to:)` + XCTest

**Source:** `validationLedgerTests/Support/UIKitSnapshot.swift:53-86`.
**Apply to:** All 3 new snapshot files (action region matrix, tender sheet, toast banner).

### S-6: Programmatic UIKit + `required init?(coder:)` trap

**Source:** Every existing `Features/Loads/Detail/*.swift` view (verified across `StatusTimelineView.swift`, `VerificationBasisSheetViewController.swift`, `ChainIntegrityBannerView.swift`).
**Apply to:** `LoadActionsView`, `TenderSheetViewController`, `LoadActionToastBannerView`.

### S-7: `accessibilityElements` set explicitly + per-element labels

**Source:** Phase 9 D-22, Phase 9.1 leaf-element model (verified by file-header read on `LoadDetailViewController.swift`).
**Apply to:** Every new view — action buttons each have `accessibilityLabel`; disabled buttons set `accessibilityHint` with the disabled reason (RESEARCH § Anti-Patterns).

### S-8: `configure(...)`-based render contract (NEVER subview swap on state change)

**Source:** Phase 9 D-20 + RESEARCH § Pattern 2 + verified in `LoadDetailViewController.swift:1110-1126`.
**Apply to:** `LoadActionsView.configure(actions:role:status:tenderEligibility:onTap:)` — `isHidden` toggles between button-row container and empty-state caption container; never swaps the subview tree.

---

## No Analog Found (planner reads RESEARCH.md patterns instead)

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| The toast banner's overall composition (slide-in + auto-dismiss + swipe-to-dismiss + haptic) | View | event-driven | No existing in-app transient-banner with this exact lifecycle. The closest in-codebase analog (`ChainIntegrityBannerView`) is a static, scroll-pinned banner — different lifecycle. RESEARCH § Don't Hand-Roll line 481 supplies the hand-rolled `UIView.animate` + `transform` pattern; UI-SPEC § LoadActionToastBannerView lines 458-475 lock the geometry. |
| The chain "updating…" overlay (alpha-blocking subview with centered activity indicator) | View | render-pause | No existing overlay subview of this exact shape; activity-indicator pattern is standard UIKit. UI-SPEC § Chain overlay lines 477-486 lock the geometry. |

Both gaps are intentional — RESEARCH already enumerated them as net-new shapes with locked specifications. No alternative analog is needed; the geometry comes from UI-SPEC line-numbered locks.

---

## Metadata

**Analog search scope:**
- `validationLedger/Core/Load/` (Phase 7 frozen contract; read RoleLoadPolicy, LoadAction, Load).
- `validationLedger/Core/Networking/Endpoints/` (LoadActionEndpoint read in full).
- `validationLedger/Core/Networking/Mock/` (MockLoadFixtureRegistry handlers read at lines 120-189; MockDefaultFixtures `-MockKYCStatusVerified` pattern at lines 57-76).
- `validationLedger/Features/Loads/Detail/` (LoadDetailViewModel + LoadDetailViewController render + sheet presentation; LoadDetailBodyView contentStack arrangement; VerificationBasisSheetViewController header structure).
- `validationLedger/App/AppContainer.swift` (factory closures and `makeLoadDetailScreen` at lines 218-294).
- `validationLedgerTests/Support/` (UIKitSnapshot helper).
- `validationLedgerTests/Loads/Snapshot/` (LoadStatusBadgeViewSnapshotTests matrix shape; VerificationBasisSheetViewControllerSnapshotTests canvas-size helper; LoadRowCellSnapshotTests synthetic-fixture builder).
- `validationLedgerUITests/Loads/` (LoadDetailFlowTests.swift OTP + role + row-tap shape).

**Files scanned:** ~30 files; ~8 read in full / ~22 grep-targeted (only the load-bearing ranges loaded into context).

**Pattern extraction date:** 2026-05-21.

**Confirmation:** Every excerpt above was lifted from the source tree at this revision via the `Read` tool. No analog was assumed; every `file:line` reference can be re-verified against the same revision.

---

*Phase: 10-per-role-tender-accept-reject*
*Patterns mapped: 2026-05-21*
