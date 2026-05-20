// validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift
// Phase 7 LOAD-01 (Plan 03) — GET /loads/{role} returning a paginated envelope.
//
// D-15: role lives in the URL PATH, not a query string. MockURLProtocol's
// fixture matcher keys on `request.url?.path` (excludes the query string),
// and a real backend routes equivalently — the role-in-path scheme survives
// both halves of the M3 mock-to-live swap with zero matcher changes.
//
// D-16: Response is a paginated envelope from day one
//   `{ loads: [Load], nextCursor: String? }`
// Even though v1.1 fixtures always return a single page, encoding the
// paginated envelope in the typed Response now prevents a Phase 8 list-VM /
// diffable-snapshot rework at the eventual live-backend swap. The
// `nextCursor` wire key is `next_cursor` (snake_case) and is handled by
// `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy. An absent
// `next_cursor` decodes to `nil` (synthesized-optional `decodeIfPresent`
// behavior), which is exactly the semantics callers want — "no more pages".
//
// File-shape analog: KYCStatusEndpoint.swift (the canonical GET-with-
// EmptyBody template — `nonisolated public struct`, `RequestBody = EmptyBody`,
// nested `Decodable & Sendable Response`).
//
// Trust posture (D-18): every field on `Response.loads` ultimately routes
// into the Plan 01 fail-closed value types (LoadStatus throws on unknown,
// VerificationState/ChainIntegrity.Verdict degrade fail-closed). The Phase 9
// list cell renders this Response unchanged — no client-derived trust.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor —
// see APIEndpoint.swift for rationale (RequestBody/Response Sendable
// constraint rejects main-actor-isolated conformances).
nonisolated public struct LoadListEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        /// The page of loads for this role. Phase 8 D-02: each row is a
        /// `LoadListItem` envelope wrapping the Phase 7 `Load` aggregate under
        /// `load:` and carrying the server-projected `displayedCounterparty:
        /// TrustNode?` (nil is FAIL-CLOSED per D-03 — the UI renders the
        /// neutral-grey UNVERIFIED badge). `LoadDetailEndpoint.Response.load:
        /// Load` is UNTOUCHED — list vs detail are cleanly separated by the
        /// envelope.
        public let loads: [LoadListItem]

        /// Server-supplied opaque pagination cursor. `nil` means "no more
        /// pages". Wire form is `next_cursor` (snake_case); the synthesized
        /// optional decoder + `.convertFromSnakeCase` handles absent/null
        /// values transparently. Phase 8 D-05: VMs DECODE-ONLY this field;
        /// v1.1 ships no infinite-scroll observer, no prefetch trigger, and
        /// no "Load more" button. The contract is forward-compatible — a
        /// future backend or fixture upgrade wires in infinite-scroll with
        /// no Phase 8 refactor.
        public let nextCursor: String?
    }

    /// Dynamic path — set from `init(role:)`. KYCStatusEndpoint hardcodes
    /// `let path = "/kyc/status"` because its path is fixed; here the role
    /// segment is the dispatching key, so `path` is a stored property.
    public let path: String
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    /// Constructs the endpoint for a given role. D-15: the role lives in the
    /// URL path. `Role.rawValue` is the lowercased case name
    /// (`"shipper" | "broker" | "carrier" | "dispatch" | "factoring"`).
    public init(role: Role) {
        self.path = "/loads/\(role.rawValue)"
    }
}
