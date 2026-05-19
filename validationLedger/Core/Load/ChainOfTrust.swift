// validationLedger/Core/Load/ChainOfTrust.swift
// Phase 7 LOAD-02 (D-07, D-08): the aggregate trust-graph value type embedded
// in `LoadDetailEndpoint.Response`. The Phase 9 trust-graph view renders
// directly from this — every node is a UIKit `UIView` drawn from a TrustNode,
// every edge is a `CAShapeLayer` drawn from a TrustEdge, and the top-banner
// reads from `integrity` (a ChainIntegrity per Plan 07-01).
//
// D-08 — ChainOfTrust = { nodes: [TrustNode], edges: [TrustEdge],
//                         integrity: ChainIntegrity }. One round-trip; no
// separate graph fetch. The wire shape is:
//   { "nodes": [...], "edges": [...], "integrity": {...} }
// where the `integrity` key is the bare string "integrity" — NOT
// "chain_integrity". The Plan 05 fixture authoring uses the bare form
// (`"chain_of_trust": { "nodes": [...], "edges": [...], "integrity": {...} }`),
// and the property is declared with NO custom `CodingKey` alias so the
// Swift-synthesized decoder under `.convertFromSnakeCase` maps wire-key
// `integrity` directly to property `integrity`.
//
// D-07 — TrustNode carries TYPED verification-basis fields. The four facts
// (KYC, device-binding, USDOT authority, prior-relationship count) plus the
// three identity fields (partyID, role, displayName) plus the
// verification-state ladder give the Phase 9 tappable verification-basis sheet
// its content. The iOS UI controls presentation; the server supplies the
// typed facts. NOT an opaque server-formatted fact list.
//
// === D-18 constraint — NO CLIENT-DERIVED TRUST ===
// Every field on every type in this file is server- or fixture-supplied.
// No computed Bool property derives trust state from verificationState. The
// trust-graph view code in Phase 9 may compute presentation helpers (badge
// color, banner copy) — but those live in Phase 8/9 view code, NOT here.
//
// === Wire-format / CodingKeys ===
// Trailing-acronym fields require an explicit CodingKey bridge under
// `.convertFromSnakeCase` (which converts wire-key `party_id` → `partyId`,
// NOT `partyID`). The KYCStatusEndpoint precedent (private enum CodingKeys
// listing only the acronym cases) is followed here. All OTHER fields rely on
// the synthesized decoder + `.convertFromSnakeCase` and do NOT need explicit
// CodingKeys cases:
//   - TrustNode: only `partyID` needs the bridge. `kycCompletedAt`,
//     `deviceBindingStatus`, `usdotNumber`, `usdotAuthorityStatus`,
//     `priorRelationshipCount`, `role`, `displayName`, `verificationState`
//     all map cleanly under `.convertFromSnakeCase` — none has a trailing
//     acronym followed by a different letter (the case `.convertFromSnakeCase`
//     mis-handles).
//   - TrustEdge: `edgeID`, `fromPartyID`, `toPartyID` need the bridge.
//     `relationshipState` and `tenderRef` map cleanly under
//     `.convertFromSnakeCase` (`relationship_state` → `relationshipState`,
//     `tender_ref` → `tenderRef`).
//   - ChainOfTrust: no acronym bridge needed; `integrity` is bare-string-keyed.

import Foundation

/// The chain-of-trust subgraph for a single Load (D-08). Embedded in
/// `LoadDetailEndpoint.Response` so the trust-graph view has all the data it
/// needs from one round-trip.
public struct ChainOfTrust: Decodable, Sendable {

    /// The party nodes (typed verification-basis per D-07). Each TrustNode is
    /// rendered as a draggable UIView in the Phase 9 trust-graph.
    public let nodes: [TrustNode]

    /// The trust relationships between parties (D-08). Each TrustEdge is
    /// rendered as a CAShapeLayer between two node views in the Phase 9
    /// trust-graph. TRUST-04 surfaces an edge's handoff/tender detail.
    public let edges: [TrustEdge]

    /// The chain-level integrity verdict + reason + implicated IDs (D-08).
    /// The Phase 9 banner reads color and copy from this value.
    ///
    /// NOTE: No `CodingKey` alias — the wire key is bare `integrity`, NOT
    /// `chain_integrity`. The Plan 05 fixtures write
    /// `"integrity": { ... }` inside each `chain_of_trust` object.
    public let integrity: ChainIntegrity
}

/// A party node in the trust graph — the typed verification-basis payload
/// for a single party on a load (D-07). The Phase 9 verification-basis tap
/// target renders directly from these fields.
public struct TrustNode: Decodable, Sendable {

    /// Stable party identifier (e.g. "party-broker-acme-001"). Same identity
    /// space as `LoadParty.partyID` on `LoadStatusEvent`.
    public let partyID: String

    /// The party's role on the platform.
    public let role: Role

    /// User-facing display name (e.g. "Acme Brokerage"). Server-supplied.
    public let displayName: String

    /// The fail-closed verification state (D-09 — Plan 01). An unknown server
    /// superstring decodes to `.unverified`, never softening the trust signal.
    public let verificationState: VerificationState

    /// When the party's KYC verification completed. `nil` for unverified /
    /// pending / flagged parties. Renders as "KYC verified <relative-time>"
    /// in the verification-basis sheet when non-nil.
    public let kycCompletedAt: Date?

    /// Whether the party's device is registered + actively bound (D-07).
    /// Renders the "device-bound" badge state.
    public let deviceBindingStatus: DeviceBindingStatus

    /// The party's USDOT number (carriers, dispatch). `nil` for parties whose
    /// role does not carry a USDOT number (shipper, factoring) — in that
    /// case `usdotAuthorityStatus == .notApplicable`.
    public let usdotNumber: String?

    /// FMCSA-derived operating-authority status (D-07). For shippers /
    /// factoring this is `.notApplicable`; for carriers / dispatch it drives
    /// the badge color (active=ok, suspended=caution, revoked=compromised).
    public let usdotAuthorityStatus: USDOTAuthorityStatus

    /// How many prior loads this party has shared with the current viewer's
    /// counterparty graph (D-07). The verification-basis sheet renders
    /// "First time working together" vs. "5 prior loads" from this number.
    public let priorRelationshipCount: Int

    /// Acronym bridge — see KYCStatusEndpoint.Response.Artifact for rationale.
    /// `partyID` is the only trailing-acronym field; the others map cleanly
    /// under `.convertFromSnakeCase`.
    private enum CodingKeys: String, CodingKey {
        case partyID = "partyId"
        case role
        case displayName
        case verificationState
        case kycCompletedAt
        case deviceBindingStatus
        case usdotNumber
        case usdotAuthorityStatus
        case priorRelationshipCount
    }
}

/// A trust relationship between two parties on the chain (D-08). Each edge
/// is rendered as a `CAShapeLayer` in the Phase 9 trust-graph; TRUST-04
/// surfaces `tenderRef` when the user taps an edge.
public struct TrustEdge: Decodable, Sendable {

    /// Stable edge identifier (e.g. "edge-broker→carrier-VL-1001"). Used by
    /// `ChainIntegrity.implicatedEdgeIDs` to highlight an edge.
    public let edgeID: String

    /// The `partyID` of the upstream party in the relationship.
    public let fromPartyID: String

    /// The `partyID` of the downstream party in the relationship.
    public let toPartyID: String

    /// The fail-closed verification state of the EDGE itself (D-09) — the
    /// same trust ladder applies (verified / pending / unverified / flagged).
    /// An unknown server superstring decodes to `.unverified`.
    public let relationshipState: VerificationState

    /// The tender / handoff reference surfaced on the TRUST-04 tap-edge
    /// (e.g. a tender ID or BOL reference). `nil` for relationships that
    /// have not been formalized through a tender.
    public let tenderRef: String?

    /// Acronym bridge — see KYCStatusEndpoint.Response.Artifact for rationale.
    /// The three trailing-acronym fields need explicit cases; the two
    /// non-acronym fields rely on the synthesized decoder under
    /// `.convertFromSnakeCase`.
    private enum CodingKeys: String, CodingKey {
        case edgeID = "edgeId"
        case fromPartyID = "fromPartyId"
        case toPartyID = "toPartyId"
        case relationshipState
        case tenderRef
    }
}
