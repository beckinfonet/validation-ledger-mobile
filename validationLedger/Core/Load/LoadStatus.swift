// validationLedger/Core/Load/LoadStatus.swift
// Phase 7 LOAD-02 (D-01): the full-lifecycle load status enum.
//
// D-01: 13 cases covering the canonical primary path
//   draft → posted → tendered → accepted → dispatched → inTransit → delivered
// plus side-states (rejected, expired, cancelled) and the post-delivery cases
// (podCaptured, invoiced, funded). The post-delivery trio renders read-only in
// v1.1 (factoring's list + post-delivery loads) — interactive transitions into
// them land in M3/post-v1.1. Locking the closed set now means zero enum churn
// when transitions are added.
//
// File-shape analog: validationLedger/Core/Attestation/TrustTier.swift.
// Wire-format: under JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase
// (APIClient.defaultDecoder()), single-word cases pass through automatically.
// Multi-word cases declare explicit snake_case rawValues so the wire form
// (e.g. "in_transit", "pod_captured") decodes deterministically — the
// .convertFromSnakeCase strategy converts JSON KEYS, not VALUES; raw enum
// values bind 1:1 to the JSON string regardless of strategy.
//
// Decoder semantics: unknown wire value throws DecodingError per Swift's
// synthesized init(from:). This is distinct from D-09's fail-closed contract
// (which applies ONLY to VerificationState and ChainIntegrity.Verdict):
// an unknown LoadStatus is a server superstring on a non-fraud-vector field
// — the entire Load fails to decode loudly, surfacing the contract bug.
// See PLAN 07-01 threat T-07-03.

import Foundation

public enum LoadStatus: String, Sendable, Decodable, CaseIterable {
    // Primary lifecycle path
    case draft
    case posted
    case tendered
    case accepted
    case dispatched
    case inTransit = "in_transit"
    case delivered

    // Side-states
    case rejected
    case expired
    case cancelled

    // Post-delivery (display-only in v1.1; transitions land post-v1.1)
    case podCaptured = "pod_captured"
    case invoiced
    case funded
}

// MARK: - Phase 10 LOAD-display helpers (additive — public surface unchanged)
//
// Phase 10 Plan 01 (Pitfall 5 anchor):
//   The Plan 04 terminal empty-state caption interpolates the lowercase
//   localized status name (see 10-UI-SPEC.md lines 297-313 — the format key
//   is `loads.actions.empty.terminal.format`). A naive implementation would
//   pass `rawValue` directly and emit "in_transit" with the underscore. The
//   `localizedDisplayName` computed property below is the SINGLE SOURCE of
//   the lowercase display string for every LoadStatus.
//
// Key naming: `loads.status.<spaced>` — multi-word cases use dot-separated
// words ("loads.status.in.transit", "loads.status.pod.captured") so the
// localization team can keep the namespace flat without underscores. The
// English fallback (`value:`) is the lowercase space-separated form
// (`"in transit"`, `"pod captured"`).
//
// Exhaustive switch with NO `default:` arm — a future LoadStatus case added
// to the enum forces a compile-time update here (Pitfall 5 regression lock).
public extension LoadStatus {
    /// Lowercase, localized display name for this LoadStatus.
    ///
    /// Used by:
    ///   - Phase 10 Plan 04 terminal empty-state caption (UI-SPEC line 307).
    ///   - VoiceOver labels (Phase 10 a11y) — `.posted` becomes
    ///     "Load is posted" / "no posted loads available" through the
    ///     surrounding format string.
    ///
    /// The lookup key is `loads.status.<spaced>`; the English fallback
    /// (`value:`) is the lowercase space-separated form. Future
    /// localizations populate the key in `Localizable.strings`; absent a
    /// translation, NSLocalizedString returns the fallback verbatim.
    var localizedDisplayName: String {
        switch self {
        case .draft:
            return NSLocalizedString(
                "loads.status.draft",
                value: "draft",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .posted:
            return NSLocalizedString(
                "loads.status.posted",
                value: "posted",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .tendered:
            return NSLocalizedString(
                "loads.status.tendered",
                value: "tendered",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .accepted:
            return NSLocalizedString(
                "loads.status.accepted",
                value: "accepted",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .dispatched:
            return NSLocalizedString(
                "loads.status.dispatched",
                value: "dispatched",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .inTransit:
            return NSLocalizedString(
                "loads.status.in.transit",
                value: "in transit",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .delivered:
            return NSLocalizedString(
                "loads.status.delivered",
                value: "delivered",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .rejected:
            return NSLocalizedString(
                "loads.status.rejected",
                value: "rejected",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .expired:
            return NSLocalizedString(
                "loads.status.expired",
                value: "expired",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .cancelled:
            return NSLocalizedString(
                "loads.status.cancelled",
                value: "cancelled",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .podCaptured:
            return NSLocalizedString(
                "loads.status.pod.captured",
                value: "pod captured",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .invoiced:
            return NSLocalizedString(
                "loads.status.invoiced",
                value: "invoiced",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        case .funded:
            return NSLocalizedString(
                "loads.status.funded",
                value: "funded",
                comment: "Load status display name (lowercase) for empty-state captions and a11y labels"
            )
        }
    }
}
