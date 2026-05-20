// validationLedger/Core/Load/PriorRelationship.swift
// Phase 9 D-12 / D-13 — the new `priorRelationships` element type that replaces
// the legacy `priorRelationshipCount: Int` on TrustNode. Pure value type —
// server-supplied data, iOS renders only (Phase 7 D-18 inheritance).
//
// Renders in the TRUST-03 verification-basis sheet (Plan 07) as a tappable
// LIST of prior loads:
//   "VL-1023 · 3 months ago · Broker → Carrier"
// The empty array is the marquee fraud signal — a flagged carrier with `[]`
// surfaces as "First time working together" (D-14 chameleon archetype).
//
// === Wire-format / CodingKeys ===
// Trailing-acronym fields require an explicit CodingKey bridge under
// `APIClient.defaultDecoder()`'s `.convertFromSnakeCase` strategy. The
// converter rewrites wire-key `load_id` → `loadId` BEFORE matching against
// CodingKey raw values — so the raw value MUST be the post-conversion form
// `"loadId"`, NEVER `"load_id"` (RESEARCH §7 Pitfall 5).
//
// Field map:
//   - loadID                   ← explicit CodingKey bridge (trailing
//                                 acronym; .convertFromSnakeCase would
//                                 otherwise produce `loadId` which does NOT
//                                 match the synthesized `loadID` property)
//   - occurredAt               ← synthesized + .convertFromSnakeCase
//                                 (`occurred_at` → `occurredAt`)
//   - counterpartyRole         ← synthesized + .convertFromSnakeCase
//                                 (`counterparty_role` → `counterpartyRole`)
//   - counterpartyDisplayName  ← synthesized + .convertFromSnakeCase
//                                 (`counterparty_display_name` →
//                                  `counterpartyDisplayName`). Optional —
//                                 server may omit the denormalized name.
//
// `occurredAt` is decoded via `.iso8601` (the second strategy on
// `APIClient.defaultDecoder()`). The synthesized initializer handles all four
// fields; NO custom decoder is declared — keeps the decode contract trivially
// auditable per T-09-01.
//
// File-shape analog: ChainOfTrust.swift TrustNode lines 32-49, 79-133.

import Foundation

/// A single prior load shared between this party and a counterparty (D-13).
/// Server-supplied; the verification-basis sheet in Plan 07 renders these as
/// list rows. The platform thesis: clean carriers carry 5+ priors; chameleon
/// carriers carry `[]` ("First time working together" — the fraud signal).
public struct PriorRelationship: Decodable, Sendable {

    /// Stable VL-#### reference of the prior load. Wire key `load_id` is
    /// pre-converted to `loadId` by `.convertFromSnakeCase`; the explicit
    /// CodingKey bridge maps that to the trailing-acronym `loadID` property.
    public let loadID: String

    /// ISO-8601 timestamp of when the prior load occurred. Renders via
    /// `RelativeDateTimeFormatter` ("3 months ago", "Last week").
    public let occurredAt: Date

    /// The OTHER role on the prior load relative to this node. On a Broker
    /// node, prior relationships' `counterpartyRole` is typically `.carrier`
    /// or `.shipper`; the UI sheet framing is "Broker → Carrier" rendered
    /// from this field.
    public let counterpartyRole: Role

    /// Denormalized display name of the counterparty (e.g. "Acme Brokerage").
    /// Optional — server may omit when the denormalized name is not yet
    /// indexed; the sheet row degrades to role-only framing when absent.
    public let counterpartyDisplayName: String?

    /// Acronym bridge — the only trailing-acronym field is `loadID`. The
    /// other three properties map cleanly under `.convertFromSnakeCase` and
    /// require NO explicit case (per ChainOfTrust.swift line 39-44 doctrine).
    ///
    /// IMPORTANT: raw value is `"loadId"` (POST-conversion form), NOT
    /// `"load_id"`. `.convertFromSnakeCase` rewrites wire keys BEFORE
    /// matching — RESEARCH §7 Pitfall 5.
    private enum CodingKeys: String, CodingKey {
        case loadID = "loadId"
        case occurredAt
        case counterpartyRole
        case counterpartyDisplayName
    }
}
