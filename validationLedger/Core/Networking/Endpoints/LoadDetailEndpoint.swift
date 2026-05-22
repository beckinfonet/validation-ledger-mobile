// validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift
// Phase 7 LOAD-01 (Plan 03) — GET /loads/{loadID} returning the updated
// Load + the embedded ChainOfTrust in a single round-trip.
//
// D-15: load ID lives in the URL PATH (`/loads/VL-1042`), matching the
// LoadListEndpoint role-in-path scheme. MockURLProtocol matches on
// `request.url?.path`, so the dynamic-path stored property routes
// equivalently for mock + real backend.
//
// D-08: ChainOfTrust is EMBEDDED in this endpoint's Response — one round-trip
// for the Phase 9 graph render. NO separate `/parties/{id}/verification`
// fetch, no graph-level loading state. The cost is a slightly larger detail
// payload; the win is that the detail screen has every byte it needs to draw
// the trust graph the moment the request returns. The 5-tier topology
// (shipper → broker → carrier → dispatch → factoring) bounds the payload
// size — see Plan 03 threat register entry T-07-14.
//
// File-shape analog: KYCStatusEndpoint.swift (GET-with-EmptyBody template).
//
// Trust posture (D-18): ChainOfTrust embeds TrustNode + TrustEdge +
// ChainIntegrity from Plan 02 — every fail-closed decoder in the chain
// (Plan 01 VerificationState → .unverified; Plan 01 ChainIntegrity.Verdict
// → .compromised) composes through this Response's Decodable synthesized
// init. No client-derived trust — the iOS UI is a passive renderer.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
nonisolated public struct LoadDetailEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        /// The Plan 02 aggregate Load (status, stateHistory, tenderEligibility,
        /// counterparty metadata). Wire key: bare `load`.
        public let load: Load

        /// The Plan 02 ChainOfTrust subgraph (nodes + edges + integrity verdict).
        /// D-08 — embedded sibling field, NOT a separate fetch. Wire key:
        /// `chain_of_trust` (snake_case), handled by
        /// `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy.
        public let chainOfTrust: ChainOfTrust
    }

    /// Dynamic path — set from `init(loadID:)`.
    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    /// Constructs the endpoint for a specific load. The `loadID` is the
    /// stable VL-#### identifier on `Load.id`.
    public init(loadID: String) {
        self.path = "/loads/\(loadID)"
    }
}
