// validationLedger/Core/Load/LoadListItem.swift
// Phase 8 Plan 01 — D-02: server-projected list-row envelope.
//
// LoadListItem wraps a Load with the server-projected counterparty TrustNode
// for one row in the role-filtered loads list. The server already resolves the
// counterparty role per requesting role (Broker → carrier, Carrier → broker,
// Shipper → broker, Dispatch → broker, Factoring → carrier — 08-CONTEXT D-04);
// iOS NEVER selects which TrustNode to render. This preserves Phase 7 D-18
// ("iOS is a passive renderer; the server supplies all trust").
//
// === D-03 fail-closed nil semantic ===
// `displayedCounterparty: TrustNode?` is OPTIONAL. The Decodable conformance
// uses the SYNTHESIZED initializer + `decodeIfPresent` for the Optional, which
// handles BOTH the JSON `null` case AND the missing-key case identically: both
// decode to Swift `nil`. The UI layer (Phase 8 Plan 04 `LoadRowCell`) renders
// `nil` as the neutral-grey UNVERIFIED VerificationBadgeView (Phase 7 D-09
// fail-closed parity) — never green. `nil` is reserved for degraded server
// responses and draft/posted loads with no counterparty yet.
//
// === Why no explicit Coding Keys enum and no custom decoder initializer ===
// 1. Snake-case bridge: `APIClient.defaultDecoder()` sets
//    `keyDecodingStrategy = .convertFromSnakeCase`, which converts the wire
//    key `displayed_counterparty` to the Swift property `displayedCounterparty`
//    transparently. The only acronym bridge in the embedded `TrustNode` is its
//    own `partyID` ↔ `party_id`, handled INSIDE its own enum
//    (ChainOfTrust.swift line 122-132) — LoadListItem itself has no acronym
//    fields. 08-RESEARCH Pitfall 2 confirms this.
// 2. Synthesized decoder: the compiler-synthesized initializer +
//    `decodeIfPresent` is precisely the D-03 fail-closed semantic; writing a
//    custom decoder would either be a no-op or risk subtly different behavior
//    (Threat T-08-03 — decoder safety). 08-RESEARCH Assumption A5 + Pitfall 3.
//
// === Threat surface ===
// T-08-03 (Decoder safety): no custom Decodable initializer; rely on the synthesized
// initializer + decodeIfPresent. Unknown verification_state values on the
// embedded TrustNode degrade to .unverified at the Phase 7 VerificationState
// decoder layer (D-09) — LoadListItem inherits that fail-closed posture.
// T-08-04 (PII): pure value type; no logging, no toString customization.

import Foundation

/// Server-projected list-row envelope for the role-filtered loads list (D-02).
/// Each row carries the Phase 7 `Load` aggregate under `load` plus the server-
/// resolved counterparty `TrustNode?` under `displayedCounterparty`. The Phase 8
/// `LoadListViewModel` consumes `[LoadListItem]` directly from
/// `LoadListEndpoint.Response.loads`.
public struct LoadListItem: Decodable, Sendable {

    /// The Phase 7 Load aggregate — UNCHANGED by Phase 8. Wire form is the same
    /// JSON object Phase 7's fixtures author at the top level; here it lives
    /// nested under the `"load":` key per D-02 envelope shape.
    public let load: Load

    /// Server-projected counterparty for THIS row given the requesting role
    /// (D-01 + D-04). The server already resolved which TrustNode to render:
    /// broker requests get the carrier, carrier requests get the broker, etc.
    /// `nil` is FAIL-CLOSED (D-03): the UI renders the neutral-grey UNVERIFIED
    /// badge — never green — and the synthesized `decodeIfPresent` handles
    /// both JSON `null` and missing-key forms identically.
    public let displayedCounterparty: TrustNode?
}
