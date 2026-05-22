// validationLedger/Core/Load/Load.swift
// Phase 7 LOAD-02 (D-02, D-07, D-18): the aggregate Load value type.
//
// `Load` is the central domain entity for v1.1 — every Phase 8 list cell,
// every Phase 9 detail screen field, and every Phase 10 action button reads
// from it. It composes the full Plan 01 leaf-and-aggregate hierarchy
// (LoadStatus, LoadStatusEvent, TenderEligibility) and is embedded in:
//   - LoadListEndpoint.Response.loads: [LoadListItem]    (Plan 03 + Phase 8 D-02 — each row wraps a Load under `load:` and adds `displayedCounterparty: TrustNode?`)
//   - LoadDetailEndpoint.Response.load: Load             (Plan 03)
//   - LoadActionEndpoint.Response.load: Load             (Plan 03 — server returns the updated Load after each action)
//
// D-02 — `stateHistory: [LoadStatusEvent]` IS the source of timeline data.
// The Phase 9 LOAD-06 timeline UI ("Tendered 2 days ago", "Tender expired",
// "Re-tendered") renders from this array; it does NOT synthesise positions
// from `status` alone. Prior rejected/expired tenders that returned the load
// to `posted` (D-04) are recorded as LoadStatusEvent entries here.
//
// D-18 — NO CLIENT-DERIVED TRUST. `Load` does NOT expose `verificationState`
// directly — that lives on the per-party `TrustNode` records inside the
// associated `ChainOfTrust` (carried separately in `LoadDetailEndpoint.Response`).
// `tenderEligibility` is server-supplied; the iOS UI never derives `canTender`
// client-side.
//
// === Currency representation ===
// `rate` is `Decimal` — NOT `Double`. Currency must never use binary
// floating-point (compounding rounding errors); the codebase precedent for
// monetary values is `Decimal` per the Foundation guidance for currency.
//
// === Wire-format / CodingKeys ===
// Under `JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase`
// (APIClient.defaultDecoder()), `.convertFromSnakeCase` cleanly handles every
// field on this type: `id`, `referenceNumber`, `origin`, `destination`,
// `equipment`, `weight`, `rate`, `pickupAt`, `deliverAt`, `status`,
// `stateHistory`, `respondByAt`, `tenderEligibility`. None has a trailing
// acronym that requires an explicit CodingKey bridge — the convention
// matches Plan 05 fixture authoring (`"id": "VL-1001"`, NOT `"load_id"`).
// LoadStop and TenderEligibility likewise need no explicit CodingKeys —
// every field maps cleanly under `.convertFromSnakeCase`.
//
// === Name choice ===
// `LoadStop` (not `Stop`) is chosen to avoid grep collision with `APIEndpoint`
// /HTTPMethod/etc. — per 07-RESEARCH.md "Naming note". Specific-enough to be
// trivially greppable within the Core/Load/ kernel.

import Foundation

/// A pickup or delivery location on a Load. Used as `Load.origin` and
/// `Load.destination`. The fields are render-ready strings; no geocoding,
/// no coordinate composition (those live in a later milestone alongside the
/// real-backend integration).
public struct LoadStop: Decodable, Sendable {

    /// City name (e.g. "Dallas").
    public let city: String

    /// US state code or full name as the server emits (e.g. "TX").
    public let state: String

    /// Postal code (e.g. "75201"). String — leading zeros must survive.
    public let postalCode: String

    /// ISO country code or country name. For v1.1 fixtures this is always
    /// "US" per the GEO-02 US-only constraint, but the field is server-
    /// supplied to keep iOS a passive renderer (no client default).
    public let country: String
}

/// Server-supplied tender eligibility signal driving ACTION-07's hard-disable
/// behaviour on the broker's tender button.
///
/// D-18 — server-derived only. The Phase 10 action bar reads
/// `canTender == false` and renders the disabled-tender button with the
/// server-supplied `disabledReason` inline ("counterparty unverified",
/// "destination outside service area", etc.). iOS NEVER derives this client-
/// side; doing so would let local logic upgrade trust on an otherwise-
/// blocked tender. The TenderEligibility itself is `Decodable, Sendable`
/// with no setter, no mutating method, no init beyond the synthesized one.
public struct TenderEligibility: Decodable, Sendable {

    /// `true` if the broker may issue a tender on this load. When `false`,
    /// the ACTION-07 UI renders the disabled-tender button + `disabledReason`.
    public let canTender: Bool

    /// Server-supplied reason text rendered inline next to a disabled tender
    /// button. `nil` when `canTender == true` (no reason needed) — and may
    /// be `nil` even when `canTender == false` (degraded server response;
    /// the UI falls back to a generic "Tender is unavailable" copy).
    public let disabledReason: String?
}

/// The aggregate Load value type — the central domain entity for v1.1
/// (D-02 / D-07 / D-18).
///
/// `Load` is decoded from `LoadListEndpoint.Response.loads`,
/// `LoadDetailEndpoint.Response.load`, and `LoadActionEndpoint.Response.load`.
/// It composes the Plan 01 leaf-and-aggregate hierarchy (LoadStatus,
/// LoadStatusEvent, LoadStop, TenderEligibility) but DELIBERATELY does NOT
/// nest the `ChainOfTrust` — that lives as a sibling field on
/// `LoadDetailEndpoint.Response` per D-08, so the list payload stays small
/// and only the detail screen carries the trust graph.
public struct Load: Decodable, Sendable {

    /// Stable load identifier (e.g. "VL-1001"). Wire form is the bare string
    /// "id" per the Plan 05 fixture convention (`"id": "VL-1001"`) — NOT
    /// "load_id". The default synthesized decoder maps wire `id` → property
    /// `id` directly.
    public let id: String

    /// Human-readable reference number rendered on every cell (e.g. "REF-100A").
    public let referenceNumber: String

    /// Pickup location.
    public let origin: LoadStop

    /// Delivery location.
    public let destination: LoadStop

    /// Equipment string ("dry_van", "reefer", "flatbed", etc.). Render-side
    /// freeform string in v1.1 — NOT a closed enum. M3/post-v1.1 may close
    /// the set; for now the server controls the vocabulary and iOS displays
    /// what it receives.
    public let equipment: String

    /// Weight in pounds (integer; the wire form is an integer JSON number).
    public let weight: Int

    /// Tendered rate in USD. `Decimal` — NEVER `Double` — for currency
    /// representation. Wire form is a JSON number (e.g. `2150.00`).
    public let rate: Decimal

    /// Scheduled pickup time. ISO-8601 wire form parsed by
    /// `APIClient.defaultDecoder()`'s `.iso8601` strategy.
    public let pickupAt: Date

    /// Scheduled delivery time. ISO-8601 wire form.
    public let deliverAt: Date

    /// Current load status — the canonical lifecycle position (D-01). The
    /// Phase 8 list and Phase 10 action bar read from this; the Phase 9
    /// timeline does NOT derive position from this alone (D-02 — see
    /// `stateHistory`).
    public let status: LoadStatus

    /// D-02 — full transition history for the LOAD-06 timeline UI. Each
    /// event records the LoadStatus the load transitioned INTO and the
    /// actor responsible (nil for system transitions like auto-expiry).
    /// Prior rejected/expired tenders that returned the load to `posted`
    /// (D-04) appear here, not synthesised from current status.
    public let stateHistory: [LoadStatusEvent]

    /// Active-tender response deadline. Non-nil ONLY on a `.tendered` load
    /// with an outstanding tender; nil on every other status (including a
    /// load that was tendered, expired, and is now back in `.posted`).
    /// Drives the carrier/dispatch countdown UI in Phase 10.
    public let respondByAt: Date?

    /// Server-supplied tender eligibility (D-18). Nil-equivalent to
    /// "default to allowed" — when the field is absent the broker UI does
    /// not impose a hard-disable on the tender button. When present and
    /// `canTender == false` the ACTION-07 UI renders the disabled button
    /// + `disabledReason`.
    public let tenderEligibility: TenderEligibility?
}

// MARK: - Phase 10 (per D-16) — predictor helper extension
//
// Internal-access helper consumed by LoadActionPredictor; same module, no
// public-init exposure (Phase 7 contract unchanged at the public surface).
//
// Rationale per 10-RESEARCH.md § Open Question 1:
//   Every stored property on Load is `public let`, so Swift synthesizes an
//   internal-access memberwise `init(id:referenceNumber:...:tenderEligibility:)`.
//   The synthesized init is accessible from a same-module extension WITHOUT
//   widening Load's public surface — exactly the access level the predictor
//   needs (it lives in the same module under Core/Load/).
//
// Signature is the minimal one the predictor needs:
//   `with(status:respondByAt:)` — both ACTION-02/04/05 and the .accept/.reject
//   arms only need to override these two fields. Every other field forwards.
extension Load {
    /// Returns a new Load with `status` and `respondByAt` overridden and
    /// every other stored property forwarded unchanged.
    ///
    /// Pure value-type construction — does NOT mutate `self`. The
    /// LoadActionPredictor calls this on the current Load to produce the
    /// optimistic-forward predicted Load that lands in the ViewModel's
    /// `.actionInFlight` state (per Plan 03's D-16 rollback contract).
    func with(status: LoadStatus, respondByAt: Date?) -> Load {
        Load(
            id: self.id,
            referenceNumber: self.referenceNumber,
            origin: self.origin,
            destination: self.destination,
            equipment: self.equipment,
            weight: self.weight,
            rate: self.rate,
            pickupAt: self.pickupAt,
            deliverAt: self.deliverAt,
            status: status,
            stateHistory: self.stateHistory,
            respondByAt: respondByAt,
            tenderEligibility: self.tenderEligibility
        )
    }
}
