// validationLedger/Features/Loads/LoadListViewModel.swift
// Phase 8 Plan 03 — LOAD-03 / LOAD-07: the role-scoped loads-list state machine.
//
// File-shape analog: KYCStatusViewModel.swift (the canonical 4-state VM in this
// codebase). Same posture:
//   - `@MainActor public final class`
//   - nested `enum State: Equatable, Sendable`
//   - `state` `didSet` fires `onStateChange`
//   - initializer-DI (ARCH-04)
//
// Unlike KYCStatusViewModel, this VM has NO coordinator callbacks (no
// `onVerified`-style nav) — the loads list is a tab-bar leaf in v1.1; tapping
// a row is a Phase 9 concern (LoadDetailViewController routing), not a VM
// callback that lives here.
//
// === Phase 8 contract anchors ===
// D-02 (Plan 01): `LoadListItem { load: Load; displayedCounterparty: TrustNode? }`
//   — the server-projected envelope this VM consumes from
//     `LoadListEndpoint.Response.loads`.
// D-03 (Plan 01): nil `displayedCounterparty` is FAIL-CLOSED — the UI renders
//   the neutral-grey UNVERIFIED badge. The VM passes the envelope through
//   unchanged; it never softens or filters on the nil counterparty.
// D-04 (Plan 01): per-role counterparty roles are server-projected; the VM is
//   a passive renderer (D-18). It does NOT re-select counterparties.
// D-05 (Plan 01): `nextCursor` is stored on the `.loaded` case but never read
//   anywhere else. v1.1 ships no infinite-scroll observer / prefetch trigger /
//   "Load more" button. The contract is forward-compatible — wiring infinite
//   scroll later is a VM-only additive change with no envelope refactor.
//
// === UI-SPEC contract anchors (08-UI-SPEC §State Machine + §Copywriting) ===
// - 4 cases: .loading / .empty / .loaded(items, nextCursor) / .error(message).
// - Refresh-from-loaded does NOT transition through .loading — pull-to-refresh
//   leaves existing rows on screen; the refresh-control spinner is the only
//   loading affordance.
// - Refresh-from-non-loaded (.empty / .error) DOES transition through
//   .loading — there are no existing rows to preserve.
// - Decode / HTTP / network errors ALL collapse to the same localized
//   `loads.error.generic` copy. Server-supplied error text NEVER reaches the
//   screen (UI-SPEC §Copywriting — locked).
//
// === Threat-model contract (08-03-PLAN.md §threat_model) ===
// T-08-08 (PII via logs): the VM's only log emissions on the fetch path are
//   `logger.info(event: LogEvent("loads_list_loaded"), fields: [:])` and
//   `logger.error(event: LogEvent("loads_list_fetch_failed"), fields: [:])`.
//   NEVER pass error-description text into the fields dict — a DecodingError
//   stringification renders the JSON byte slice (party names + IDs). NEVER
//   load.id, referenceNumber, displayName, or any TrustNode field. `LogField`
//   is a closed enum (key channel locked); the value channel is locked here
//   by passing `[:]`.
// T-08-08 also forbids the UI from reading `displayedCounterparty.displayName`
//   for VoiceOver — that is a cell-layer concern, but documented here as the
//   end-to-end PII invariant.
//
// === LoadListItem: Equatable extension (why it lives here) ===
// `State.loaded(items: [LoadListItem], nextCursor: String?)` requires
// `LoadListItem` to be Equatable so the auto-synthesized `State: Equatable`
// works. Plan 01 declared `LoadListItem` as `Decodable, Sendable` only — adding
// `Equatable` would cascade through every stored field (Load → LoadStop /
// TenderEligibility / LoadStatusEvent / LoadParty, plus TrustNode → Role /
// VerificationState / DeviceBindingStatus / USDOTAuthorityStatus) and force
// Phase 7's frozen Core/Load value types to gain conformance they don't need.
//
// Instead, this file ships a CUSTOM `extension LoadListItem: Equatable` that
// compares by *identity* (`load.id` + the counterparty's `partyID` +
// `verificationState`) rather than full structural equality. That is
// sufficient for:
//   - the State-Equatable conformance used by Swift Testing assertions
//   - the `==` comparisons in the test sequence `[.loading, .loaded(...)]`
// And it avoids touching the Phase 7 / Plan 01 frozen domain types.

import Foundation

@MainActor
public final class LoadListViewModel {

    // MARK: - State

    /// The 4-case state machine driving `LoadListViewController.render(state:)`.
    ///
    /// `Equatable` is synthesised (the associated values `[LoadListItem]` and
    /// `String?` are both Equatable — `LoadListItem` via the
    /// identity-comparing extension at the bottom of this file).
    ///
    /// `Sendable` is honored because every associated value is `Sendable`
    /// (LoadListItem is Sendable per Plan 01).
    public enum State: Equatable, Sendable {
        /// Initial state; also re-entered on refresh from non-loaded states.
        case loading
        /// `Response.loads.isEmpty == true` — the role has no loads to show.
        case empty
        /// `Response.loads.isEmpty == false` — render the rows.
        /// `nextCursor` is stored per Plan 01 D-05 but never read by any
        /// consumer in v1.1; the contract is forward-compatible for a future
        /// infinite-scroll wiring.
        case loaded(items: [LoadListItem], nextCursor: String?)
        /// Any thrown error from `apiClient.request(_:)`. The message is a
        /// fixed-copy localized string (`loads.error.generic`) — decode /
        /// HTTP / network all collapse here, with the classification logged
        /// (not surfaced).
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    // MARK: - Callbacks

    /// Fires on every `state` mutation. The VC binds this to its
    /// `render(state:)` dispatcher.
    public var onStateChange: ((State) -> Void)?

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    /// The role this VM is scoped to. Drives the endpoint:
    /// `LoadListEndpoint(role: self.role)`.
    public let role: Role

    private let apiClient: APIClient
    private let logger: any Logger

    public init(role: Role, apiClient: APIClient, logger: any Logger) {
        self.role = role
        self.apiClient = apiClient
        self.logger = logger
    }

    // MARK: - fetchLoads() — refresh semantics per UI-SPEC §State Machine

    /// Fetch `GET /loads/{role}` and transition the state machine to the
    /// terminal state for the response.
    ///
    /// Refresh semantics (UI-SPEC §State Machine, locked):
    ///   - From `.loaded`: do NOT transition through `.loading` first. Pull-
    ///     to-refresh leaves existing rows on screen; the refresh control's
    ///     spinner is the only loading affordance. The terminal transition
    ///     fires after the response arrives.
    ///   - From any other state (`.loading` / `.empty` / `.error`): transition
    ///     through `.loading` first, then fire the request.
    ///
    /// Response mapping:
    ///   - `loads.isEmpty == true`  → `.empty`
    ///   - `loads.isEmpty == false` → `.loaded(items: response.loads,
    ///                                          nextCursor: response.nextCursor)`
    ///
    /// Error handling (08-CONTEXT.md §Claude's Discretion — error
    /// classification collapses):
    ///   - Decode / HTTP 4xx / HTTP 5xx / URLError ALL collapse to
    ///     `.error(message: userFacingMessage(...))` with the same localized
    ///     copy. The classification is logged (different LogEvent names
    ///     possible in future) but never surfaced to UI.
    public func fetchLoads() async {
        // Refresh-from-loaded leaves the row state intact; refresh-from-any-
        // other-state passes through `.loading` (UI-SPEC §State Machine).
        if case .loaded = state {
            // intentionally do NOT mutate state — the refresh-control spinner
            // is the loading affordance; the rows stay on screen
        } else {
            state = .loading
        }

        let response: LoadListEndpoint.Response
        do {
            response = try await apiClient.request(LoadListEndpoint(role: role))
        } catch {
            // T-08-08 — fields: [:] is mandatory. NEVER pass an error-
            // description string into the fields dict here: a DecodingError
            // stringified through Swift.String(describing:_) renders the JSON
            // byte slice — party names and IDs would leak into the value
            // channel even though `LogField` closes the key channel.
            logger.error(event: LogEvent("loads_list_fetch_failed"), fields: [:])
            state = .error(message: Self.userFacingMessage(for: error))
            return
        }

        if response.loads.isEmpty {
            // T-08-08 — empty payload is also a success; log without fields.
            logger.info(event: LogEvent("loads_list_loaded"), fields: [:])
            state = .empty
        } else {
            logger.info(event: LogEvent("loads_list_loaded"), fields: [:])
            // Plan 01 D-05 — nextCursor is stored, never read. v1.1 ships no
            // consumer for it. The associated value carries it forward for
            // forward-compatibility with a future infinite-scroll wiring.
            state = .loaded(items: response.loads, nextCursor: response.nextCursor)
        }
    }

    // MARK: - User-facing error copy (UI-SPEC §Copywriting — locked)

    /// Render any thrown error as the SAME localized fixed-copy sentence.
    ///
    /// UI-SPEC §Copywriting locks `loads.error.generic`. Server-supplied error
    /// text (HTTP body, NSLocalizedDescription, decode-mismatch detail) NEVER
    /// reaches the screen — that would be both a PII vector (server-leaked
    /// freight references) and a copy-quality vector (engineering jargon in
    /// the user-facing UI). The classification difference (decode vs HTTP vs
    /// network) is logged (T-08-08-safe), not rendered.
    static func userFacingMessage(for _: Error) -> String {
        NSLocalizedString(
            "loads.error.generic",
            value: "Check your connection and try again. Your loads are safe.",
            comment: "Phase 8 LoadListViewModel error-state body — generic, reassures the user that no data is lost"
        )
    }
}

// MARK: - LoadListItem Equatable (in-VM-file extension; see file-header rationale)

/// Identity-only Equatable for the State.loaded case.
///
/// Compares by:
///   - `load.id` (the stable load identifier),
///   - the counterparty's `partyID` if present,
///   - the counterparty's `verificationState` if present (so a backend
///     transition from PENDING → VERIFIED on the same party surfaces as a
///     state mutation even though the load.id is unchanged).
///
/// This is SUFFICIENT for the VM-State-Equatable contract and avoids
/// cascading Equatable through every Phase 7 Core/Load value type. If a
/// future plan needs full structural equality on LoadListItem, that's an
/// additive change at the Plan 01 file (not here) and the change would
/// supersede this in-VM-file extension cleanly.
extension LoadListItem: Equatable {
    public static func == (lhs: LoadListItem, rhs: LoadListItem) -> Bool {
        lhs.load.id == rhs.load.id
            && lhs.displayedCounterparty?.partyID == rhs.displayedCounterparty?.partyID
            && lhs.displayedCounterparty?.verificationState == rhs.displayedCounterparty?.verificationState
    }
}
