// validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift
// Phase 7 LOAD-01 (Plan 03) — POST /loads/{loadID}/{action} for every
// LoadAction the role policy table permits.
//
// D-15: action lives in the URL PATH (`/loads/VL-1042/tender`,
// `/loads/VL-1042/accept`, `/loads/VL-1042/status` — D-05's collapse of the
// 3 advanceStatus transitions to a single "status" segment). The path
// composition uses `action.pathSegment` (Plan 01 — LoadAction.swift) so the
// closed-enum surface is the single source of truth for the wire form.
//
// D-19: ZERO-WIRING IDEMPOTENCY. Because `method == .post`, the existing
// `IdempotencyInterceptor` (already in `apiClient.requestInterceptors` per
// `AppContainer.swift:476`) injects `Idempotency-Key: UUID().uuidString` on
// every request. No new interceptor wiring is added by this endpoint; no
// Phase 7 test asserts the header injection — `IdempotencyInterceptorTests`
// already covers the wiring end-to-end. This zero-wiring guarantee is the
// reason the endpoint MUST stay POST (per the threat register T-07-13).
//
// File-shape analog: OTPVerifyEndpoint.swift (POST with typed RequestBody
// and explicit CodingKeys for trailing acronyms) + KYCSubmitEndpoint.swift
// (thin-finalizer POST convention).
//
// Trust posture (D-18): the Response carries both the updated `Load` and a
// re-supplied `ChainOfTrust` because actions may flag or clean the chain
// (e.g. a `tender` to a previously-unverified counterparty flips an edge's
// flag state; an `accept` clears the load's `respondByAt`). Embedding the
// chain here is symmetric with LoadDetailEndpoint.Response (D-08) — every
// post-action UI render has the freshly-derived trust graph in hand without
// a follow-up fetch. Both fields route into the Plan 01 fail-closed value
// types, preserving the "iOS is a passive renderer" invariant.
//
// RequestBody scope (planner-finalized for Phase 7 SC #1): the catch-all
// shape below — `actorRole`, `targetPartyID`, `respondByAt`, `note` — is
// sufficient for every action the Plan 05 fixture matrix exercises. A
// post-v1.1 follow-up may extend this with per-action fields; for v1.1 a
// `tender` carries `targetPartyID + respondByAt` (the carrier being
// tendered to + the response deadline), and every other action ignores
// those two fields server-side.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
nonisolated public struct LoadActionEndpoint: APIEndpoint {

    /// Typed request payload sent on every load-action POST.
    ///
    /// `actorRole` is required — the server validates that the role is legal
    /// for the action per the server-side mirror of `RoleLoadPolicy`
    /// (Plan 02). The other three fields are action-specific:
    ///
    /// - `tender` reads `targetPartyID` (the carrier the broker is
    ///   tendering to) and `respondByAt` (the deadline the broker sets).
    /// - `accept`, `reject`, `cancel`, `post`, `advanceStatus` ignore
    ///   `targetPartyID` and `respondByAt` — pass `nil` for both.
    /// - `note` is an optional human-readable annotation that the server
    ///   may surface in `Load.stateHistory`. `nil` is acceptable for every
    ///   action; v1.1 UIs do not collect a note.
    public struct RequestBody: Encodable, Sendable {

        /// The role the caller is acting as. The server cross-checks this
        /// against the session role and the role policy table.
        public let actorRole: Role

        /// On a `tender`, the `partyID` of the carrier being tendered to.
        /// Nil for every other action. Wire key (post-explicit-CodingKey
        /// bridge): `target_party_id`.
        public let targetPartyID: String?

        /// On a `tender`, the deadline by which the target party must
        /// accept or reject. Nil for every other action. Encoded as ISO-8601
        /// via `APIClient.defaultEncoder()`'s `.iso8601` strategy.
        public let respondByAt: Date?

        /// Optional human-readable annotation, surfaced in
        /// `Load.stateHistory` if the server preserves it.
        public let note: String?

        public init(
            actorRole: Role,
            targetPartyID: String?,
            respondByAt: Date?,
            note: String?
        ) {
            self.actorRole = actorRole
            self.targetPartyID = targetPartyID
            self.respondByAt = respondByAt
            self.note = note
        }

        // Explicit CodingKeys — acronym bridge for `targetPartyID`. Under
        // `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`,
        // `targetPartyID` would mangle to `target_party_i_d` on toolchains
        // that mishandle trailing acronyms; pinning the wire key to
        // camelCase `targetPartyId` (the strategy's well-defined input form)
        // forces `target_party_id` on the wire. Same precedent as
        // OTPVerifyEndpoint.RequestBody.CodingKeys.
        private enum CodingKeys: String, CodingKey {
            case actorRole
            case targetPartyID = "targetPartyId"
            case respondByAt
            case note
        }
    }

    /// Server response after a successful action. Carries the post-action
    /// `Load` (status may have advanced, `stateHistory` has a new event)
    /// and a re-supplied `ChainOfTrust` because actions may flag or clean
    /// the chain (D-08-symmetric).
    public struct Response: Decodable, Sendable {
        /// The updated load after the action applied. Wire key: bare `load`.
        public let load: Load

        /// The re-supplied chain-of-trust subgraph for this load. Wire key:
        /// `chain_of_trust` (snake_case), handled by `.convertFromSnakeCase`.
        public let chainOfTrust: ChainOfTrust
    }

    /// Dynamic path — `/loads/{loadID}/{action.pathSegment}` (D-15).
    public let path: String
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    /// Constructs the endpoint. The action is encoded into the URL path via
    /// its `pathSegment` (Plan 01) — e.g. `LoadAction.advanceStatus` maps
    /// to `"status"` (D-05). The typed `body` is sent as the POST payload.
    public init(loadID: String, action: LoadAction, body: RequestBody) {
        self.path = "/loads/\(loadID)/\(action.pathSegment)"
        self.body = body
    }
}
