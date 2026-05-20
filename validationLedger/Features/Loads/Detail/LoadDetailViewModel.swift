// validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift
// Phase 9 LOAD-05 / D-20 — the 3-case state machine driving
// LoadDetailViewController.render(state:).
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
// === T-09-04 / T-08-08 — zero-PII discipline ===
// `userFacingMessage(for:) -> String` returns the locked localized generic
// copy `loads.detail.error.generic`. Server-supplied error text NEVER
// reaches the screen. Decoding errors, URLErrors, and HTTP 4xx/5xx all
// collapse to the same string. Logger calls (when emitted) use
// `fields: [:]` — never an error description (a stringified DecodingError
// renders the JSON byte slice including party names + load reference
// numbers).
//
// === BL-01 — cancel-and-replace ===
// A fresh `fetchLoadDetail()` cancels any in-flight task. The cancelled
// task observes `Task.isCancelled` after the network hop returns and bails
// out BEFORE mutating state. Mirrors LoadListViewModel.fetchLoads()
// (PATTERNS E2 lines 173-195) verbatim — the rationale (last-write-wins
// race silently downgrading verification signals) applies equally to the
// detail screen.

import Foundation

@MainActor
public final class LoadDetailViewModel {

    // MARK: - State (D-20 — 3 cases, no .empty)

    /// The 3-case state machine. The VC's render(state:) toggles
    /// `isHidden` on its pre-attached `skeletonContainer / bodyContainer /
    /// errorContainer` subviews based on this case.
    ///
    /// `Equatable` is synthesised — the associated values are themselves
    /// `Equatable` only via the same identity-shaped extension the Phase 8
    /// VM applies (Load isn't structurally Equatable). For Phase 9 the VM's
    /// own tests assert the case shape, not deep payload equality, so the
    /// synthesised conformance is sufficient for the test contract — see the
    /// Equatable extension at the bottom of this file.
    ///
    /// `Sendable` is honored — Load and ChainOfTrust are both Sendable.
    public enum State: Equatable, Sendable {
        /// Initial state and re-entered on every fresh `fetchLoadDetail()`.
        /// VC renders skeleton-with-shimmer (D-19).
        case loading
        /// Successful fetch. Carries the WHOLE Decodable Load + ChainOfTrust
        /// (D-18 — no derived state). VC renders the body composition
        /// (graph + timeline + bill-of-lading) populated by Plans 04-09.
        case loaded(Load, ChainOfTrust)
        /// Any thrown error from `apiClient.request(_:)`. The message is the
        /// locked localized fixed-copy sentence (`loads.detail.error.generic`)
        /// — decode / HTTP / network all collapse here, with the
        /// classification logged (NOT surfaced).
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

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let loadID: String
    private let apiClient: APIClient
    private let logger: (any Logger)?

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - loadID: the stable VL-#### identifier consumed by
    ///             `LoadDetailEndpoint(loadID:)`.
    ///   - apiClient: typed-endpoint facade; injected by AppContainer.
    ///   - logger: optional. The view layer NEVER logs (T-08-08 / T-09-04
    ///             mirror); the VM may emit `fields: [:]` events for
    ///             operational visibility. When nil, no logging happens.
    public init(loadID: String, apiClient: APIClient, logger: (any Logger)? = nil) {
        self.loadID = loadID
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
        state = .loaded(response.load, response.chainOfTrust)
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
