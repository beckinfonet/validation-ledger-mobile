// validationLedger/Core/Load/LoadStatusEvent.swift
// Phase 7 LOAD-02 (D-02): the per-transition timeline event for a Load.
//
// D-02 — `Load.stateHistory: [LoadStatusEvent]` is the SOURCE OF TIMELINE DATA.
// The Phase 9 LOAD-06 status-timeline UI ("Tendered 2 days ago") renders from
// this array — it does NOT derive position purely from `Load.status`. Prior
// rejected/expired tenders that returned the load to `posted` (D-04) are
// recorded here, not synthesised from current status.
//
// LoadStatusEvent carries:
//   - status: the LoadStatus the load transitioned INTO at `timestamp`.
//   - timestamp: ISO-8601 wire form, parsed by APIClient.defaultDecoder()'s
//     `.iso8601` dateDecodingStrategy.
//   - actor: the lightweight participant reference responsible for the
//     transition. Optional — system transitions (auto-expiry, server-side
//     timer firings) carry no actor. Decodes as `nil` when absent under the
//     synthesized Decodable initializer.
//
// LoadParty is the LIGHTWEIGHT participant reference distinct from
// `ChainOfTrust.TrustNode` (which carries the typed verification-basis fields
// per D-07). LoadParty appears in timeline rows; TrustNode appears in the
// trust-graph. The two are kept separate so the timeline doesn't carry the
// trust-basis payload (D-07's 9 fields) on every event.
//
// === Wire-format / CodingKeys ===
// `partyID` is a trailing-acronym field. Under
// `JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase` (APIClient
// .defaultDecoder()) the wire key `party_id` converts to `partyId` (NOT
// `partyID`). The explicit `private enum CodingKeys` bridges the gap per the
// KYCStatusEndpoint precedent (the canonical trailing-acronym pattern in this
// codebase). All other fields (`role`, `displayName`, `status`, `timestamp`,
// `actor`) rely on the synthesized decoder + `.convertFromSnakeCase` and do
// not need explicit CodingKeys cases.
//
// === D-18 constraint ===
// LoadStatusEvent and LoadParty are pure `Decodable, Sendable` value types.
// No client-derived trust field, no computed `var isVerified: Bool`, no
// mutating method. Server (or fixture) supplies the data; iOS renders it.

import Foundation

/// A single transition in `Load.stateHistory` (D-02). The Phase 9 LOAD-06
/// timeline UI renders from this array — never from `Load.status` alone.
public struct LoadStatusEvent: Decodable, Sendable {

    /// The status the load transitioned INTO at `timestamp`.
    public let status: LoadStatus

    /// Wall-clock time of the transition. ISO-8601 wire form, decoded by
    /// `APIClient.defaultDecoder()`'s `.iso8601` dateDecodingStrategy.
    public let timestamp: Date

    /// The party responsible for the transition. `nil` for system-driven
    /// transitions (auto-expiry, server timer fire). The Phase 9 timeline
    /// renders "Expired" without an actor row when `nil`.
    public let actor: LoadParty?
}

/// Lightweight participant reference carried on timeline events (D-02) and
/// other places that need to identify a party without the typed
/// verification-basis payload that lives on `ChainOfTrust.TrustNode` (D-07).
public struct LoadParty: Decodable, Sendable {

    /// Stable party identifier (e.g. "party-broker-acme-001"). Same identity
    /// space as `TrustNode.partyID` — a LoadParty on a stateHistory event
    /// references the same party that appears as a TrustNode in the chain.
    public let partyID: String

    /// The party's role in the platform (shipper, broker, carrier, dispatch,
    /// factoring). Drives role-styled rendering of the timeline row.
    public let role: Role

    /// User-facing display name (e.g. "Acme Brokerage"). Server-supplied.
    public let displayName: String

    /// Acronym bridge — see KYCStatusEndpoint.Response.Artifact for rationale.
    /// `partyID` is the only trailing-acronym field on this type; the others
    /// pass through `.convertFromSnakeCase` unchanged.
    private enum CodingKeys: String, CodingKey {
        case partyID = "partyId"
        case role
        case displayName
    }
}
