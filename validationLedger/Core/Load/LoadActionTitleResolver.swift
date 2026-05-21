// validationLedger/Core/Load/LoadActionTitleResolver.swift
// Phase 10 Plan 02 Task 2 — pure title resolver for the action region.
//
// `LoadActionTitleResolver` is a `public enum` with no cases (a namespace) —
// analog shape to `RoleLoadPolicy` and `LoadActionPredictor` (Plan 01).
// Two public static functions:
//
//   1. `nextStatus(from:)` — the pure LoadStatus → LoadStatus? helper that
//      maps a current status to the canonical-lifecycle next state for the
//      three forward advance transitions (accepted -> dispatched ->
//      inTransit -> delivered). Every other current status returns nil.
//
//   2. `title(for:currentStatus:)` — the visible button title for a given
//      LoadAction. For the five status-independent actions (.tender,
//      .accept, .reject, .cancel, .post) the resolver returns the LOCKED
//      UI-SPEC title via NSLocalizedString (English fallback in source for
//      the unit-test invariant; localized strings ship via Localizable.strings
//      under a later milestone). For `.advanceStatus` the title varies by
//      `nextStatus(from: currentStatus)`:
//
//        .accepted   -> "Dispatch"          (loads.actions.button.advance.dispatched)
//        .dispatched -> "Mark in transit"   (loads.actions.button.advance.in_transit)
//        .inTransit  -> "Mark delivered"    (loads.actions.button.advance.delivered)
//        other / nil -> "Advance"           (loads.actions.button.advance.generic)
//
// === Why Core/Load/, not Features/Loads/ ===
// The Plan 04 lint test greps `Features/Loads/**/*ViewController.swift` and
// `**/*Cell.swift` for `switch.*\.status` — locating this resolver in
// Core/Load/ keeps the title computation OUTSIDE the lint's scope. The gate
// stays with RoleLoadPolicy (Phase 7 truth table + Plan 02's wrapper);
// the title computation runs ONLY after the gate opens. UI-SPEC line 282
// is explicit: "MUST be in a pure helper, NOT inline in the action region".
//
// === Exhaustive switch — no `default:` arm ===
// `nextStatus(from:)` lists every LoadStatus case explicitly. A future
// LoadStatus case lands here at compile time (Swift's exhaustiveness check
// flags it) — mitigating T-10-PR-02 (a silently-missed arm).
//
// === D-09 (no `switch load.status` in views) — analog to Phase 9 ===
// Phase 9 Plan 03's timeline display-string resolver was the same exception:
// a pure helper in Core/ may switch on LoadStatus to produce a display
// string, but no view code may. This resolver follows the same pattern.

import Foundation

/// Pure namespace producing the visible button title for a `LoadAction`,
/// with the `.advanceStatus` title varying by the load's current status.
///
/// File-shape analog: `LoadActionPredictor` (Plan 01) and `RoleLoadPolicy`
/// (Phase 7 / Plan 02) — `public enum` with no cases + static API surface.
public enum LoadActionTitleResolver {

    /// The canonical-lifecycle next status for the three forward advance
    /// transitions. Every other current status returns nil.
    ///
    /// Exhaustive switch with NO `default:` arm — a future LoadStatus case
    /// forces a compile-time update here (T-10-PR-02 mitigation).
    public static func nextStatus(from current: LoadStatus) -> LoadStatus? {
        switch current {
        case .accepted:    return .dispatched
        case .dispatched:  return .inTransit
        case .inTransit:   return .delivered
        case .draft,
             .posted,
             .tendered,
             .rejected,
             .expired,
             .delivered,
             .cancelled,
             .podCaptured,
             .invoiced,
             .funded:      return nil
        }
    }

    /// The localized button title for `action` given the load's current
    /// `currentStatus`. For status-independent actions the `currentStatus`
    /// argument is ignored; for `.advanceStatus` the title varies per
    /// `nextStatus(from: currentStatus)`.
    ///
    /// Returns a non-empty string for every (action, currentStatus) input —
    /// defensive against out-of-band callers; the policy gate prevents
    /// (advanceStatus, .posted) etc. from rendering in production, but this
    /// resolver MUST NOT trap on those combinations.
    public static func title(for action: LoadAction, currentStatus: LoadStatus?) -> String {
        switch action {
        case .tender:
            return NSLocalizedString(
                "loads.actions.button.tender",
                value: "Tender",
                comment: "Action button title — broker offers a load to a carrier"
            )

        case .accept:
            return NSLocalizedString(
                "loads.actions.button.accept",
                value: "Accept",
                comment: "Action button title — carrier accepts an active tender"
            )

        case .reject:
            return NSLocalizedString(
                "loads.actions.button.reject",
                value: "Reject",
                comment: "Action button title — carrier rejects an active tender"
            )

        case .cancel:
            return NSLocalizedString(
                "loads.actions.button.cancel",
                value: "Cancel load",
                comment: "Action button title — broker cancels the load"
            )

        case .post:
            return NSLocalizedString(
                "loads.actions.button.post",
                value: "Post",
                comment: "Action button title — broker posts a draft load to make it tenderable"
            )

        case .advanceStatus:
            // `currentStatus` may be nil at the call site; `nextStatus(from:)`
            // expects a non-nil input — fall through to the generic
            // "Advance" fallback for nil/unmapped statuses.
            let next: LoadStatus?
            if let currentStatus {
                next = nextStatus(from: currentStatus)
            } else {
                next = nil
            }

            switch next {
            case .dispatched:
                return NSLocalizedString(
                    "loads.actions.button.advance.dispatched",
                    value: "Dispatch",
                    comment: "Action button title — carrier moves load from accepted to dispatched"
                )

            case .inTransit:
                return NSLocalizedString(
                    "loads.actions.button.advance.in_transit",
                    value: "Mark in transit",
                    comment: "Action button title — carrier moves load from dispatched to in transit"
                )

            case .delivered:
                return NSLocalizedString(
                    "loads.actions.button.advance.delivered",
                    value: "Mark delivered",
                    comment: "Action button title — carrier moves load from in transit to delivered"
                )

            default:
                // Generic fallback for combinations the policy gate already
                // prevents from rendering (e.g. (advanceStatus, .posted))
                // or for `currentStatus: nil`. Non-empty by contract.
                return NSLocalizedString(
                    "loads.actions.button.advance.generic",
                    value: "Advance",
                    comment: "Action button title — generic advance-status fallback (defensive)"
                )
            }
        }
    }
}
