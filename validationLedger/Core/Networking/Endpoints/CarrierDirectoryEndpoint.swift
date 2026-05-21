// validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift
// Phase 10 Plan 05 — GET /carriers/directory returning the static demo carrier
// directory the tender sheet (Plan 06) picker renders.
//
// === Why a dedicated endpoint, not ChainOfTrust.nodes? (RESEARCH § Architectural
// Responsibility Map row 6 + D-07 source decision) ===
// The canonical happy-path tender targets a `.posted` load, which has NO
// carrier in its chain-of-trust yet — the very party the broker is about to
// tender TO. Reusing `LoadDetailEndpoint.Response.chainOfTrust.nodes` would
// mean an empty picker on the most common path. A dedicated endpoint shipping
// the operating carrier set is the correct data shape: the picker reads from
// here, the chain reads from the load's existing endpoint, the two surfaces
// remain orthogonal.
//
// === Envelope shape (LoadListEndpoint precedent) ===
// `{ "carriers": [TrustNode] }` mirrors `LoadListEndpoint.Response.loads:
// [LoadListItem]` — the project's typed-envelope convention for paginated
// or paginatable list endpoints. v1.1 ships a single static page (no cursor),
// matching the demo-fixture scope; a future server can append `next_cursor`
// without breaking the typed shape (synthesized Optional decode of an absent
// key returns nil).
//
// === Domain reuse — NO new type ===
// The element type is the existing Phase 7 frozen `TrustNode` (D-07 D-12 +
// Phase 9 prior-relationships extension). The directory shares the same
// verification-basis fields the chain-of-trust card already renders, so the
// tender-sheet picker rows can reuse the same badge / role-avatar primitives
// without a new domain decoder.
//
// === Trust posture (Phase 7 D-18 inheritance) ===
// Every field on every returned TrustNode is server-supplied; the iOS UI is
// a passive renderer. VerificationState's fail-closed decoder (Phase 7 D-09)
// applies — an unknown wire value degrades to `.unverified`, never softening
// the badge color on the picker.
//
// === DEBUG demo handler ===
// The mock counterpart lives in `MockLoadFixtureRegistry.swift` as the
// inline `tenderCarrierDirectoryPayload` constant + a 4th handler in
// `registerAppDefaults()` (independent of the per-role list / per-VL detail /
// action handlers — the `/carriers/directory` path is a disjoint namespace).
// The fixture file at
// `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json`
// is the authoritative editing source; the inline registry payload mirrors
// it byte-faithfully (T-10-PR-01 mitigation; CarrierDirectoryMockTests Test 5
// is the regression guard).
//
// File-shape analog: LoadListEndpoint.swift (envelope GET endpoint precedent).

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor —
// see APIEndpoint.swift for rationale (RequestBody/Response Sendable
// constraint rejects main-actor-isolated conformances).
nonisolated public struct CarrierDirectoryEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        /// The static demo set of operating carriers spanning all four
        /// `VerificationState` cases (D-07). At least one entry carries the
        /// "Chameleon Cargo" fraud-archetype anchor as the `.flagged` row
        /// (Specifics line 264) so the picker visibly demonstrates the
        /// platform thesis the first time a broker opens it.
        public let carriers: [TrustNode]
    }

    public let path: String = "/carriers/directory"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init() {}
}
