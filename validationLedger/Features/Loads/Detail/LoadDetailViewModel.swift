// validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift
// Phase 9 LOAD-05 / D-20 — the 3-case state machine driving
// LoadDetailViewController.render(state:).
// Phase 10 Plan 03 (D-16) — extended to a 5-case state machine for the
// optimistic-UI action-submission pipeline + the D-22 `role: Role` plumb.
//
// File-shape analog: LoadListViewModel.swift (PATTERNS E2) — the Phase 8 list
// VM Phase 9 mirrors line-for-line with EXACTLY ONE fewer state case (no
// `.empty`; D-20 — detail is by-ID, 404s collapse to `.error`).
//
// === Phase 9 contract anchors ===
// D-20 (CONTEXT): 3-case `.loading / .loaded(Load, ChainOfTrust) / .error`
// state machine. Detail is by-ID; a missing load is a server error, not an
// empty result. NO `.empty` case. The VC's render(state:) switches on this
// enum to toggle `isHidden` on pre-attached state subviews — never to swap
// view controllers.
//
// D-19 (CONTEXT): `.loading` is the skeleton-with-shimmer UI (the VM is
// agnostic to the rendering; it only emits the state).
//
// D-18 (Phase 7 LOCK): NO CLIENT-DERIVED TRUST. The `.loaded` associated
// values carry the WHOLE Decodable `Load + ChainOfTrust` — no derived
// booleans, no precomputed badge enums, no flattened verification flags.
// The VC's render path reads response.verificationState / chainIntegrity
// .verdict / implicatedNodeIDs verbatim. iOS is a passive renderer.
//
// === Phase 10 contract anchors ===
// D-12 (CONTEXT): pure forward state machine — submit() predicts the
// post-action Load via LoadActionPredictor.predict(...) and writes
// .actionInFlight(predicted: predicted, ...) BEFORE awaiting the network.
//
// D-13 (CONTEXT): the chain-of-trust is NEVER predicted client-side.
// .actionInFlight carries the FROZEN pre-tap ChainOfTrust; only a 200
// response (.loaded(response.load, response.chainOfTrust)) or a rollback
// (.actionFailed(rollbackTo: preLoad, frozenChain: preChain, ...))
// transitions the chain.
//
// D-14 (CONTEXT): on success, BOTH response.load AND response.chainOfTrust
// swap from the wire — one assignment, single source of truth.
//
// D-15 (CONTEXT): on error, the VM rolls back to the captured (preLoad,
// preChain) pair. The errorCopyKey is one of the 6 LOCKED per-action keys
// in UI-SPEC line 343-348; no server-supplied error text reaches the UI.
//
// D-16 (CONTEXT): single VM owns the screen's state machine — NO separate
// LoadActionViewModel. The State enum grows from 3 to 5 cases; submit() is
// a new public method; performAction(...) mirrors performFetch() line-for-
// line.
//
// D-22 / D-23 (CONTEXT): the VM gains `public let role: Role` set at
// designated-init time. The role is fixed for the screen's lifetime — NOT
// client-changeable (mirrors v1.0 SHELL-04 lock). A user "switching roles"
// requires logout + re-login.
//
// === T-09-04 / T-08-08 — zero-PII discipline (extended to actions) ===
// `userFacingMessage(for:) -> String` returns the locked localized generic
// copy `loads.detail.error.generic`. Server-supplied error text NEVER
// reaches the screen. Decoding errors, URLErrors, and HTTP 4xx/5xx all
// collapse to the same string. Logger calls (when emitted) use
// `fields: [:]` — never an error description (a stringified DecodingError
// renders the JSON byte slice including party names + load reference
// numbers). The Phase 10 extension keeps the same discipline: every logger
// call in submit(action:body:) / performAction(...) uses `fields: [:]`;
// the rollback `errorCopyKey` is a LOCALIZATION KEY only, never an embedded
// server response substring (T-09-04 view-layer lock extended).
//
// === BL-01 — cancel-and-replace (extended to action submission) ===
// A fresh `fetchLoadDetail()` cancels any in-flight task. The cancelled
// task observes `Task.isCancelled` after the network hop returns and bails
// out BEFORE mutating state. Mirrors LoadListViewModel.fetchLoads()
// (PATTERNS E2 lines 173-195) verbatim — the rationale (last-write-wins
// race silently downgrading verification signals) applies equally to the
// detail screen. Phase 10 Plan 03 extends the same pattern to action
// submission via a parallel `actionTask` slot (D-17 + ACTION-08) —
// Pitfall 9 (rapid back-tap mid-action) inherits the Phase 9 safety.

import Foundation

@MainActor
public final class LoadDetailViewModel {

    // MARK: - State (D-20 — Phase 9 3 cases; D-16 — Phase 10 grows to 5)

    /// The 5-case state machine. The VC's render(state:) toggles
    /// `isHidden` on its pre-attached `skeletonContainer / bodyContainer /
    /// errorContainer` (Phase 9) + the action-region overlay (Plan 04 lands
    /// the two new render arms) based on this case.
    ///
    /// Phase 9 cases: `.loading / .loaded / .error`.
    /// Phase 10 cases: `.actionInFlight / .actionFailed`.
    ///
    /// `Equatable` is synthesised — the associated values are themselves
    /// `Equatable` only via the same identity-shaped extension the Phase 8
    /// VM applies (Load isn't structurally Equatable). For Phases 9-10 the
    /// VM's own tests assert the case shape, not deep payload equality, so
    /// the synthesised conformance is sufficient for the test contract — see
    /// the Equatable extension at the bottom of this file. `LoadAction` is
    /// `Equatable` for free (the underlying enum has no associated values
    /// per Phase 7).
    ///
    /// `Sendable` is honored — Load and ChainOfTrust are both Sendable;
    /// LoadAction is Sendable.
    public enum State: Equatable, Sendable {
        /// Initial state and re-entered on every fresh `fetchLoadDetail()`.
        /// VC renders skeleton-with-shimmer (D-19).
        case loading
        /// Successful fetch (or successful action terminal — D-14). Carries
        /// the WHOLE Decodable Load + ChainOfTrust (D-18 — no derived
        /// state). VC renders the body composition (graph + timeline +
        /// bill-of-lading) populated by Plans 04-09.
        case loaded(Load, ChainOfTrust)
        /// Phase 10 D-12 / D-13 — optimistic in-flight state. `predicted` is
        /// the LoadActionPredictor result (the WHOLE forward-predicted Load,
        /// per D-12); `frozenChain` is the pre-tap ChainOfTrust (NEVER
        /// predicted client-side, per D-13); `action` is the action that
        /// produced the prediction. The VC re-renders against `predicted`
        /// and keeps `frozenChain` rendered unchanged; the action-region
        /// overlay shows a per-action spinner.
        case actionInFlight(predicted: Load, frozenChain: ChainOfTrust, action: LoadAction)
        /// Phase 10 D-15 — rollback terminal state. `rollbackTo` is the
        /// pre-tap Load (the snapshot captured BEFORE the predict); same
        /// for `frozenChain`. `errorCopyKey` is one of the 6 LOCKED
        /// localization keys per UI-SPEC line 343-348 (the per-action
        /// taxonomy `loads.actions.error.<action>_failed`); the server-
        /// supplied error text NEVER reaches this string (T-09-04 lock).
        case actionFailed(rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String)
        /// Any thrown error from `apiClient.request(_:)` on the FETCH path.
        /// Action failures route through `.actionFailed` (D-15); this case
        /// covers the initial fetch's terminal-error path only. The message
        /// is the locked localized fixed-copy sentence
        /// (`loads.detail.error.generic`) — decode / HTTP / network all
        /// collapse here, with the classification logged (NOT surfaced).
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    // MARK: - Callbacks

    /// Fires on every `state` mutation. The VC binds this to its
    /// `render(state:)` dispatcher.
    public var onStateChange: ((State) -> Void)?

    // MARK: - In-flight fetch coordination (BL-01 — cancel-and-replace)
    //
    // `fetchLoadDetail()` is reachable from `viewWillAppear` on every tab
    // switch / modal dismiss and (in future plans) from a "Try again" CTA.
    // With no coordination, two overlapping `await apiClient.request(...)`
    // calls produce a last-write-wins race; the older response silently
    // overwrites the newer state, including downgrading verification signals
    // — directly contradicting CLAUDE.md "trust that cannot be faked." The
    // cancel-and-replace pattern (mirror of PATTERNS E2 LoadListViewModel
    // lines 173-195) closes the race: a fresh fetch cancels any in-flight
    // task, then awaits its own task. The cancelled task observes
    // `Task.isCancelled` after the network hop returns and bails out BEFORE
    // mutating `state`.
    private var fetchTask: Task<Void, Never>?

    // MARK: - In-flight action coordination (Phase 10 D-17 / ACTION-08)
    //
    // Twin of `fetchTask` for action submission. The same BL-01 cancel-and-
    // replace pattern applies: a fresh submit() cancels any in-flight
    // action; the cancelled task observes `Task.isCancelled` after the
    // network hop returns and bails out BEFORE mutating state. Without
    // this, a rapid double-tap (the user re-taps before the spinner
    // finishes) or a back-tap that re-enters the screen while an action is
    // mid-flight would produce a last-write-wins race; the older response
    // could overwrite the newer state, including silently rolling back a
    // successful action whose terminal `.loaded` had already landed —
    // directly contradicting the optimistic-UI rollback contract (D-15).
    //
    // Pitfall 9 (10-RESEARCH.md): the [weak self] capture in the Task's
    // closure inherits the same Phase 9 safety — VC dealloc mid-action is
    // a no-op rather than a crash.
    private var actionTask: Task<Void, Never>?

    // MARK: - Last-server-confirmed snapshot (WR-06 rollback-truth)
    //
    // BL-06 WR-06 — the optimistic-predict rollback contract (D-15) requires
    // that the pre-tap snapshot is the LAST SERVER-CONFIRMED `(load, chain)`,
    // NOT a predicted Load from a prior in-flight action. Without this
    // separation, a cancel-after-tender on an in-flight action would
    // capture `preLoad = predicted` (e.g. `.tendered`), so a failed cancel
    // would roll the UI back to `.tendered` — a state the server never
    // confirmed. The first successful `fetchLoadDetail` and every
    // successful `performAction` swaps `lastConfirmed*` to the wire
    // response. submit() reads these in the `.actionInFlight` arm so the
    // rollback snapshot is always restorable on the server.
    private var lastConfirmedLoad: Load?
    private var lastConfirmedChain: ChainOfTrust?

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let loadID: String

    /// The session role this detail screen is being viewed under. Phase 10
    /// D-22 / D-23: set at designated-init time by AppContainer.
    /// `makeLoadDetailScreen(loadID:role:)` — the captured role from the
    /// `makeLoadListScreen(role:)` outer scope — and FIXED for the
    /// screen's lifetime (mirrors v1.0 SHELL-04 lock; a user switching
    /// roles requires logout + re-login). `public let` (not a computed
    /// var) is the simplest shape: matches the existing `public let
    /// loadID` precedent, no setter to misuse, no value/reference
    /// ambiguity. The VC reads `viewModel.role` when calling
    /// `RoleLoadPolicy.availableActions(for: viewModel.role, in: load)`
    /// in Plan 04.
    public let role: Role

    private let apiClient: APIClient
    private let logger: (any Logger)?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - loadID: the stable VL-#### identifier consumed by
    ///             `LoadDetailEndpoint(loadID:)`.
    ///   - role:   the session role under which this detail screen is being
    ///             rendered (D-22). Set once at construction; FIXED for the
    ///             screen's lifetime (D-23). Consumed by Plan 04's action-
    ///             region call to `RoleLoadPolicy.availableActions(for:in:)`.
    ///   - apiClient: typed-endpoint facade; injected by AppContainer.
    ///   - logger: optional. The view layer NEVER logs (T-08-08 / T-09-04
    ///             mirror); the VM may emit `fields: [:]` events for
    ///             operational visibility. When nil, no logging happens.
    public init(
        loadID: String,
        role: Role,
        apiClient: APIClient,
        logger: (any Logger)? = nil
    ) {
        self.loadID = loadID
        self.role = role
        self.apiClient = apiClient
        self.logger = logger
    }

    // MARK: - fetchLoadDetail() — BL-01 cancel-and-replace

    /// Fetch `GET /loads/{loadID}` and transition the state machine to the
    /// terminal `.loaded(Load, ChainOfTrust)` or `.error(message:)` state.
    ///
    /// Every call:
    ///   1. cancels any in-flight `fetchTask`
    ///   2. (re-)assigns `state = .loading` so the VC re-shows the skeleton
    ///   3. starts a fresh Task and awaits its completion
    ///
    /// The cancelled task's `Task.isCancelled` checkpoints (1) AFTER the
    /// network hop returns and (2) BEFORE the terminal state assignment
    /// close the last-write-wins window.
    public func fetchLoadDetail() async {
        // BL-01 — cancel-and-replace (mirror of LoadListViewModel.fetchLoads
        // lines 173-195). A fresh fetch supersedes any in-flight one.
        fetchTask?.cancel()
        // (Re-)enter loading so the VC re-renders the skeleton on a fresh
        // fetch even if we were already .loaded. didSet fires on every
        // assignment, including same-value, so .loaded → .loading → .loaded
        // is observable in the recorder; .loading → .loading is also
        // observable (a perf no-op in the VC because render-state-loading
        // is idempotent on isHidden toggles).
        state = .loading
        let task = Task { [weak self] in
            // Guard-let bridge so the task return type is `Void`, not `Void?`
            // — Task<Void?, Never> would not satisfy the stored
            // Task<Void, Never>? declaration. (Mirrors PATTERNS E2.)
            guard let self else { return }
            await self.performFetch()
        }
        fetchTask = task
        await task.value
    }

    /// Body of `fetchLoadDetail()` — separated so the cancel-and-replace
    /// guard above is the only public entry point. Callers do NOT invoke
    /// this directly.
    ///
    /// Cancellation honors two checkpoints (BL-01):
    ///   1. AFTER the network hop returns — if the task was superseded
    ///      mid-flight, bail without mutating state (older response loses).
    ///   2. BEFORE setting the terminal `.loaded` / `.error` state —
    ///      close the last-write-wins window where the cancelled task's
    ///      response arrived between checkpoint 1 and the state write.
    private func performFetch() async {
        let response: LoadDetailEndpoint.Response
        do {
            response = try await apiClient.request(LoadDetailEndpoint(loadID: loadID))
        } catch is CancellationError {
            // Superseded by a fresher fetch — newer task already owns state.
            return
        } catch {
            // BL-01 — if THIS task was cancelled mid-flight (URLSession
            // returns the request's underlying NSURLErrorCancelled, not a
            // CancellationError), the fresher fetch already drove state.
            // Don't overwrite it with our (now-stale) error.
            if Task.isCancelled { return }
            // T-09-04 / T-08-08 — fields: [:] is mandatory. NEVER pass an
            // error-description string into the fields dict: a
            // DecodingError stringified through Swift.String(describing:)
            // renders the JSON byte slice (party names + IDs). Even though
            // `LogField` is a closed enum, the value channel is locked here
            // by passing `[:]`.
            logger?.error(event: LogEvent("load_detail_fetch_failed"), fields: [:])
            // The error argument is consumed by userFacingMessage only for
            // type dispatch; the returned string NEVER reflects any field
            // of the error (T-09-04 lock — Plan 03 Test 4 enforces).
            state = .error(message: Self.userFacingMessage(for: error))
            return
        }

        // BL-01 — race-close checkpoint. The fresher fetch may have begun
        // (and cancelled THIS task) while we were awaiting the network hop;
        // bail before mutating state so the newer task's response is what
        // the UI sees.
        if Task.isCancelled { return }

        // T-09-04 — success log carries no PII either. The `load_detail_loaded`
        // event name is the closed LogEvent constructor; fields stay empty.
        logger?.info(event: LogEvent("load_detail_loaded"), fields: [:])
        // D-18 — the WHOLE Decodable response flows into the associated
        // values verbatim. No derived state, no flattened booleans.
        // WR-06 — also record (load, chain) as the last-server-confirmed
        // snapshot so any subsequent `.actionInFlight` → `.actionFailed`
        // rollback restores to a state the server actually acknowledged
        // (D-15 rollback truth).
        lastConfirmedLoad = response.load
        lastConfirmedChain = response.chainOfTrust
        state = .loaded(response.load, response.chainOfTrust)
    }

    // MARK: - submit(action:body:) — Phase 10 D-16 / BL-01 cancel-and-replace
    //
    // The single public action-submission entry. Mirrors fetchLoadDetail()'s
    // shape (PATTERNS §8 — verbatim):
    //
    //   1. cancels any in-flight `actionTask`
    //   2. captures the rollback snapshot `(preLoad, preChain)` from the
    //      current `.loaded(...)` state — submit() is a no-op from any
    //      other state (PATTERNS §8 line 361 guard).
    //   3. predicts the post-action Load via `LoadActionPredictor.predict(...)`
    //      — D-12: pure forward prediction; the WHOLE Load predicts forward.
    //   4. writes `.actionInFlight(predicted: predicted, frozenChain: preChain,
    //      action: action)` — D-13: the chain is FROZEN, NEVER predicted.
    //   5. starts a fresh Task that runs `performAction(...)` and awaits its
    //      completion. The `[weak self]` capture inherits the Phase 9 safety
    //      (VC dealloc mid-action is a no-op).
    //
    // D-14: on success, performAction transitions to `.loaded(response.load,
    // response.chainOfTrust)` — both fields swap from the wire in one
    // assignment. D-15: on error, performAction transitions to
    // `.actionFailed(rollbackTo: preLoad, frozenChain: preChain,
    //  errorCopyKey: ...)`.
    //
    // T-09-04 / T-08-08 view-layer lock extended: logger calls use
    // `fields: [:]`. `errorCopyKey` is a LOCKED localization key per UI-SPEC
    // line 343-348, NEVER a server-supplied error substring.

    /// Dispatch a role-policy-permitted action against the current load.
    ///
    /// - Parameters:
    ///   - action: the LoadAction the user invoked (per the role policy
    ///             gate the caller is responsible for). For an out-of-policy
    ///             call the LoadActionPredictor defensively returns the
    ///             current Load unchanged (a no-op predicted state); the
    ///             VM still dispatches the network call and lets the server
    ///             be the authority.
    ///   - body:   the typed `LoadActionEndpoint.RequestBody`. For `.tender`
    ///             the body's `respondByAt` is the broker's chosen deadline
    ///             (Pitfall 3 — the predictor reads body.respondByAt, NOT
    ///             load.respondByAt).
    ///
    /// Submit is a no-op from `.loading` or `.error` — the screen has no
    /// load payload, so there is nothing to act against. Submit IS permitted
    /// from `.loaded` (the canonical entry point), `.actionInFlight` (the
    /// user is overriding an in-flight action mid-spinner — BL-01 cancel-
    /// and-replace), and `.actionFailed` (the user is retrying a different
    /// action after a rollback — the rollback snapshot IS the pre-tap
    /// snapshot for the new action). Pitfall 9 + must_haves truth #3: rapid
    /// back-tap / mid-action retry must be safe.
    public func submit(action: LoadAction, body: LoadActionEndpoint.RequestBody) async {
        // BL-01 — cancel-and-replace; a fresh action supersedes any
        // in-flight one. The cancelled task's `Task.isCancelled` checkpoints
        // (AFTER the network hop AND inside the catch arm) close the
        // last-write-wins window.
        actionTask?.cancel()
        // Capture rollback snapshot BEFORE any state mutation (D-15). The
        // pre-tap snapshot is derived from the current state:
        //   - .loaded(load, chain): the canonical entry point — (load, chain).
        //   - .actionInFlight(predicted, frozenChain, _): the user is
        //     overriding an in-flight action. The optimistic predicted Load
        //     is the visible truth on screen, so (predicted, frozenChain) is
        //     the pre-tap snapshot for the new action (chain remains FROZEN
        //     per D-13). The prior actionTask was already cancelled above.
        //   - .actionFailed(rollbackTo, frozenChain, _): the user is
        //     retrying a different action after a rollback. The rollback
        //     snapshot IS the pre-tap snapshot — (rollbackTo, frozenChain).
        //   - .loading / .error: no load payload to act against — no-op.
        let preLoad: Load
        let preChain: ChainOfTrust
        switch state {
        case .loaded(let load, let chain):
            preLoad = load
            preChain = chain
        case .actionInFlight(_, let frozenChain, _):
            // WR-06 — override-in-flight (BL-01 cancel-and-replace). The
            // OPTIMISTIC predicted Load is visible on screen, but the server
            // has NOT confirmed it. Per D-15 the rollback snapshot MUST be
            // a state the server actually acknowledged; otherwise a failed
            // cancel-after-tender would roll the UI to `.tendered` — a state
            // that never existed on the server. Read the last-server-
            // confirmed Load instead. The chain stayed frozen across the
            // in-flight transition (D-13), so frozenChain is already the
            // last-confirmed chain — use it directly to preserve the D-13
            // chain-stays-frozen invariant exactly.
            guard let confirmedLoad = lastConfirmedLoad else {
                // Defensive: no server-confirmed Load yet (shouldn't be
                // reachable — .actionInFlight is only entered from a
                // submit() that itself came from .loaded → so
                // lastConfirmedLoad MUST have been set by the prior
                // performAction's success arm or fetchLoadDetail). If it
                // ever is, bail rather than capture a fabricated snapshot.
                return
            }
            preLoad = confirmedLoad
            preChain = frozenChain
        case .actionFailed(let rollbackTo, let frozenChain, _):
            // `.actionFailed.rollbackTo` was itself derived from a
            // last-server-confirmed snapshot at the previous submit's entry
            // (D-15 invariant maintained by induction), so it IS restorable.
            preLoad = rollbackTo
            preChain = frozenChain
        case .loading, .error:
            return
        }
        // D-12 — pure forward prediction. The predictor reads body.respondByAt
        // for .tender (Pitfall 3) and otherwise produces the canonical
        // forward Load per the (action × status) cross-product. D-13 — the
        // chain is FROZEN; predictor returns Load only.
        let predicted = LoadActionPredictor.predict(load: preLoad, action: action, body: body)
        // (Re-)enter actionInFlight so the VC re-renders the predicted Load
        // + the frozen chain. didSet fires on every assignment.
        state = .actionInFlight(predicted: predicted, frozenChain: preChain, action: action)
        let task = Task { [weak self] in
            // Guard-let bridge so the task return type is `Void`, not
            // `Void?`. Mirrors fetchLoadDetail() above + PATTERNS E2.
            guard let self else { return }
            await self.performAction(
                loadID: preLoad.id,
                action: action,
                body: body,
                rollbackTo: preLoad,
                frozenChain: preChain
            )
        }
        actionTask = task
        await task.value
    }

    /// Body of `submit(action:body:)` — separated so the cancel-and-replace
    /// guard above is the only public entry point. Callers do NOT invoke
    /// this directly. Mirrors `performFetch()` line-for-line per PATTERNS §8.
    ///
    /// Cancellation honors two checkpoints (BL-01):
    ///   1. AFTER the network hop returns — if the task was superseded
    ///      mid-flight, bail without mutating state (older response loses).
    ///   2. BEFORE setting the terminal `.loaded` / `.actionFailed` state —
    ///      close the last-write-wins window where the cancelled task's
    ///      response arrived between checkpoint 1 and the state write.
    private func performAction(
        loadID: String,
        action: LoadAction,
        body: LoadActionEndpoint.RequestBody,
        rollbackTo: Load,
        frozenChain: ChainOfTrust
    ) async {
        let response: LoadActionEndpoint.Response
        do {
            response = try await apiClient.request(
                LoadActionEndpoint(loadID: loadID, action: action, body: body)
            )
        } catch is CancellationError {
            // Superseded by a fresher action — newer task already owns state.
            return
        } catch {
            // BL-01 — if THIS task was cancelled mid-flight (URLSession
            // returns the request's underlying NSURLErrorCancelled, not a
            // CancellationError), the fresher action already drove state.
            // Don't overwrite it with our (now-stale) rollback.
            if Task.isCancelled { return }
            // T-09-04 / T-08-08 — fields: [:] is mandatory. NEVER pass an
            // error-description string into the fields dict. Same lock as
            // performFetch above. The error is NOT consumed beyond
            // dispatching to the rollback state; `errorCopyKey(for:)` is
            // pure on `action`.
            logger?.error(event: LogEvent("load_action_failed"), fields: [:])
            // D-15 — rollback: both load and chain restored to the pre-tap
            // captured values. errorCopyKey is one of the 6 LOCKED
            // localization keys per UI-SPEC line 343-348 — NEVER a server-
            // supplied substring (T-09-04 view-layer lock extended).
            state = .actionFailed(
                rollbackTo: rollbackTo,
                frozenChain: frozenChain,
                errorCopyKey: Self.errorCopyKey(for: action)
            )
            return
        }

        // BL-01 — race-close checkpoint. The fresher action may have begun
        // (and cancelled THIS task) while we were awaiting the network hop;
        // bail before mutating state so the newer task's response is what
        // the UI sees.
        if Task.isCancelled { return }

        // T-09-04 — success log carries no PII either. The
        // `load_action_succeeded` event name is the closed LogEvent
        // constructor; fields stay empty.
        logger?.info(event: LogEvent("load_action_succeeded"), fields: [:])
        // D-14 — the WHOLE Decodable response flows into the associated
        // values verbatim. No derived state, no flattened booleans. Both
        // load AND chainOfTrust swap from the server response.
        // WR-06 — also swap the last-server-confirmed snapshot so a
        // subsequent override-in-flight submit() captures THIS response
        // as its rollback target, not a predicted intermediate.
        lastConfirmedLoad = response.load
        lastConfirmedChain = response.chainOfTrust
        state = .loaded(response.load, response.chainOfTrust)
    }

    // MARK: - Carrier directory fetch (Phase 10 Plan 06 — tender sheet picker source)

    /// Fetch the operating carrier directory used by the Plan 06 tender
    /// sheet's picker. Per D-07: the directory is on a DEDICATED endpoint
    /// (not derived from `ChainOfTrust.nodes`) because the canonical happy-
    /// path tender targets a `.posted` load whose chain has no carrier yet.
    ///
    /// This is a THIN pass-through — no state machine transition. The VC's
    /// `presentTenderSheet()` awaits this method, then constructs
    /// `TenderSheetViewController(directory: result, ...)`.
    ///
    /// T-09-04 view-layer lock: the VC catches errors here and does NOT
    /// render server-supplied error text. The VM's logger fires the fetch-
    /// failed event with `fields: [:]` (no PII).
    public func fetchCarrierDirectory() async throws -> [TrustNode] {
        do {
            let response = try await apiClient.request(CarrierDirectoryEndpoint())
            return response.carriers
        } catch {
            // Mirror performFetch's logging contract: fields stay empty so a
            // server response body (which may carry party names) never leaks
            // to the analytics channel. The error type itself is propagated
            // for the VC to catch; the VC does NOT render the error's
            // description (T-09-04 lock extended).
            logger?.error(event: LogEvent("carrier_directory_fetch_failed"), fields: [:])
            throw error
        }
    }

    // MARK: - Per-action error-copy key resolver (UI-SPEC line 343-348 — LOCKED)

    /// Map a LoadAction to its locked localization key per UI-SPEC line
    /// 343-348. Exhaustive switch over the 6 LoadAction cases — adding a
    /// new LoadAction case forces a compile-time update here (no `default:`
    /// arm). The key is the ONLY string ever stored in
    /// `.actionFailed.errorCopyKey`; the view layer (Plan 04) renders it
    /// via NSLocalizedString. Server-supplied error text NEVER substitutes
    /// for this key (T-09-04 view-layer lock — Plan 03 Test 5 enforces).
    nonisolated static func errorCopyKey(for action: LoadAction) -> String {
        switch action {
        case .tender:         return "loads.actions.error.tender_failed"
        case .accept:         return "loads.actions.error.accept_failed"
        case .reject:         return "loads.actions.error.reject_failed"
        case .cancel:         return "loads.actions.error.cancel_failed"
        case .post:           return "loads.actions.error.post_failed"
        case .advanceStatus:  return "loads.actions.error.advance_failed"
        }
    }

    // MARK: - User-facing error copy (UI-SPEC § Copywriting line 740 — LOCKED)

    /// Render any thrown error as the SAME localized fixed-copy sentence.
    ///
    /// UI-SPEC § Copywriting locks `loads.detail.error.generic`. Server-
    /// supplied error text (HTTP body, `NSLocalizedDescription`, decode-
    /// mismatch detail) NEVER reaches the screen — that would be both a
    /// PII vector (server-leaked freight references in DecodingError
    /// stringification) and a copy-quality vector (engineering jargon in
    /// the user-facing UI). The classification difference (decode vs HTTP
    /// vs network) is logged (T-09-04-safe), not rendered.
    ///
    /// `static` + `_` unused-parameter pattern mirrors
    /// `LoadListViewModel.userFacingMessage` — the test surface calls this
    /// directly (see LoadDetailViewModelTests Test 4) so the symbol stays
    /// addressable without requiring a VM instance.
    ///
    /// `nonisolated` is required because the class is `@MainActor`-isolated
    /// (the project compiles under `-default-isolation=MainActor`), but
    /// this function is pure: it reads no actor-isolated state, calls only
    /// `NSLocalizedString` (which is thread-safe), and is called by the
    /// VM's own `performFetch()` (under @MainActor — Sendable through the
    /// nonisolated hop) AND by `LoadDetailViewModelTests` Test 4 (a
    /// synchronous nonisolated context per Swift Testing's @Test default).
    /// Without `nonisolated`, the test surface would have to wrap the call
    /// in `await MainActor.run { … }` for a function that touches nothing
    /// actor-isolated — a worse API ergonomic for no isolation benefit.
    public nonisolated static func userFacingMessage(for _: Error) -> String {
        NSLocalizedString(
            "loads.detail.error.generic",
            value: "We couldn't load this load. Check your connection and try again.",
            comment: "Phase 9 LoadDetailViewModel error-state body — generic, never reflects server-supplied error text (T-09-04 lock)"
        )
    }
}

// (No LoadListItem-style Equatable extension needed here — Load and
//  ChainOfTrust are not Equatable, but the State's synthesised Equatable
//  conformance compares the associated values via their own ==. For Load
//  + ChainOfTrust without explicit conformance, the synthesizer requires
//  them to be Equatable — see the standalone Equatable shim below kept
//  identity-only on `load.id` so State stays Equatable for the test
//  recorder pattern, matching the Phase 8 precedent without cascading
//  conformance into Core/Load/.)

extension Load: Equatable {
    /// Identity-only Equatable (mirrors Phase 8 `extension LoadListItem:
    /// Equatable` in `LoadListViewModel.swift` — sufficient for the VM
    /// State.Equatable contract; avoids cascading structural Equatable
    /// through every Core/Load value type). Two Loads with the same `id`
    /// are considered equal for the purposes of the LoadDetailViewModel
    /// state machine; payload-equality is not a Phase 9 concern.
    public static func == (lhs: Load, rhs: Load) -> Bool {
        lhs.id == rhs.id
    }
}

extension ChainOfTrust: Equatable {
    /// Identity-only Equatable scoped to the integrity verdict + node count
    /// + edge count. This is sufficient for the VM State.Equatable contract
    /// — Phase 9 plans never assert deep ChainOfTrust equality via `State
    /// == State`; the recorder just needs the case shape and a stable
    /// equality predicate. Avoids cascading Equatable through TrustNode /
    /// TrustEdge / ChainIntegrity / PriorRelationship (all Phase 7 frozen
    /// value types). Mirrors the same minimalist posture the Phase 8 VM
    /// applied to LoadListItem.
    public static func == (lhs: ChainOfTrust, rhs: ChainOfTrust) -> Bool {
        lhs.integrity.verdict == rhs.integrity.verdict
            && lhs.nodes.count == rhs.nodes.count
            && lhs.edges.count == rhs.edges.count
    }
}
