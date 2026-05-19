// validationLedger/Core/Load/ChainIntegrity.swift
// Phase 7 LOAD-02 (D-08 / D-09): the chain-integrity verdict carried at the
// top of every ChainOfTrust. The Phase 9 trust-graph banner reads its color
// and copy from this value.
//
// D-08 — `ChainOfTrust = { nodes, edges, integrity: ChainIntegrity }`.
// ChainIntegrity carries a closed Verdict enum (cleanest → most suspicious),
// a human-readable `reason` (the banner subtitle), and the IDs of the
// implicated nodes/edges (the graph highlights these when rendering).
//
// D-09 parity (with a divergence): VerificationState fails closed to
// `.unverified` (least-TRUSTED). ChainIntegrity.Verdict fails closed to
// `.compromised` (most-SUSPICIOUS) — the OPPOSITE direction on the scale,
// but the SAME security intent: an unknown server superstring NEVER softens
// the trust signal on this client. A future "quarantined" / "investigating"
// verdict from the server degrades to `.compromised` until the iOS contract
// is extended, not to `.clean`. See Plan 07-01 threat T-07-02.
//
// Wire-format / CodingKeys:
// `implicatedNodeIDs` / `implicatedEdgeIDs` are explicit-trailing-acronym
// fields. Under the JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase
// strategy the wire keys `implicated_node_ids` / `implicated_edge_ids` convert
// to `implicatedNodeIds` / `implicatedEdgeIds` (NOT `implicatedNodeIDs`).
// We bridge the gap with an explicit `private enum CodingKeys` per the
// KYCStatusEndpoint precedent (the canonical trailing-acronym pattern in this
// codebase). This bridge survives any future drift in the snake-case
// converter's trailing-acronym handling.

import Foundation

public struct ChainIntegrity: Decodable, Sendable {

    /// The chain-integrity verdict, closed set per D-08. Cases ordered from
    /// cleanest to most-suspicious; the decoder fails closed to `.compromised`
    /// per D-09.
    public enum Verdict: String, Sendable, CaseIterable {
        /// No flags — every node verified, every edge consistent.
        case clean
        /// Some suspicious signal present but not a confirmed fraud pattern.
        case caution
        /// A confirmed fraud pattern is present (double-/triple-brokering,
        /// chameleon carrier, etc.). The banner renders red and the graph
        /// highlights the implicated nodes/edges.
        case compromised
    }

    /// The verdict for the chain as a whole.
    public let verdict: Verdict

    /// Human-readable subtitle rendered in the Phase 9 trust-graph banner
    /// (e.g. "This load's carrier identity does not match its assigned MC.").
    /// Server-supplied; iOS is a passive renderer.
    public let reason: String

    /// Party IDs implicated by the verdict. The graph highlights these nodes.
    /// May be an empty array (the verdict applies at chain level only).
    public let implicatedNodeIDs: [String]

    /// Edge IDs implicated by the verdict. The graph highlights these edges.
    /// May be an empty array.
    public let implicatedEdgeIDs: [String]

    /// Explicit acronym bridge — see KYCStatusEndpoint.Response.Artifact for
    /// rationale. Raw values are the post-`.convertFromSnakeCase` form.
    private enum CodingKeys: String, CodingKey {
        case verdict
        case reason
        case implicatedNodeIDs = "implicatedNodeIds"
        case implicatedEdgeIDs = "implicatedEdgeIds"
    }
}

extension ChainIntegrity.Verdict: Decodable {
    /// Fail-closed decoder per D-09 parity, with the divergence noted in the
    /// file header: unknown wire values default to `.compromised`
    /// (most-suspicious) rather than `.clean` (least-suspicious). The intent
    /// matches VerificationState — never let an unknown server superstring
    /// SOFTEN the trust signal — but the closure direction is flipped because
    /// the SUSPICIOUS end of the verdict scale is the safe end here.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ChainIntegrity.Verdict(rawValue: raw) ?? .compromised
    }
}
