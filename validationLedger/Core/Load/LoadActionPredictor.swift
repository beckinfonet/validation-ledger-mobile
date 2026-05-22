// validationLedger/Core/Load/LoadActionPredictor.swift
// Phase 10 Plan 01 Task 2 — the pure (Load, LoadAction, LoadActionEndpoint.RequestBody?)
// → Load predictor that the Wave-2 ViewModel consumes when transitioning into
// `.actionInFlight`.
//
// D-12: pure forward state machine — the WHOLE Load predicts forward (not the
//       chain-of-trust subgraph). The predicted Load lands in the VM's
//       in-flight state and is rolled back to `current` on server error.
// D-13: the chain-of-trust is NEVER predicted client-side. This function
//       returns Load only — the ViewModel separately holds the unchanged
//       ChainOfTrust through the in-flight transition. Re-fetching trust is a
//       server prerogative.
// D-15: optimistic-UI rollback contract — the function is total over the
//       policy-permitted (action, status) cross-product so the VM never needs
//       a defensive fallback that would silently mask a contract drift.
// D-16: rollback foundation — pure value-semantic Swift means the VM holds
//       `current` (the pre-tap Load) and `predicted` (this function's return)
//       independently; on server error the VM swaps back to `current` with no
//       cleanup beyond a single property assignment.
//
// === Pitfall 3 anchor (10-RESEARCH.md) ===
// The `.tender` arm reads `body.respondByAt`, NOT `load.respondByAt`. A
// posted load's respondByAt is `nil` before the broker taps tender — the
// in-flight timeline + respond-by line must reflect the broker's CHOSEN
// deadline, which is carried on the RequestBody, not on the source load.
//
// === Shape: pure namespace per RoleLoadPolicy ===
// `public enum LoadActionPredictor` with a single `public static` entry —
// the same shape as `RoleLoadPolicy.actions(for:status:)` (analog at
// `validationLedger/Core/Load/RoleLoadPolicy.swift` lines 60-128). One file,
// no UIKit, no I/O, no state. Exhaustively unit-tested in
// `LoadActionPredictorTests`.
//
// === Defensive bottom arm ===
// The top-level switch enumerates EVERY policy-permitted (action, status)
// combination explicitly. The bottom catch-all arm handles policy-illegal
// combinations (e.g. `.accept` on `.posted` — no role's policy returns
// `.accept` on `.posted`) and returns `current` unchanged. The policy gate
// should have prevented reaching this arm; the no-op contains the blast
// radius without crashing the in-flight VM transition. See
// LoadActionPredictorTests.test_outOfPolicyCombination_returnsCurrent_defensiveNoOp.

import Foundation

/// The pure `(Load, LoadAction, LoadActionEndpoint.RequestBody?) → Load`
/// predictor per D-12 / D-15 / D-16.
///
/// `public enum` with no cases — a namespace, analogous to
/// `RoleLoadPolicy.actions(for:status:)` in shape. The Wave-2 ViewModel
/// (Plan 03) calls `LoadActionPredictor.predict(...)` at the moment the
/// in-flight transition starts and holds the result alongside the original
/// Load until the server response lands or an error triggers rollback.
public enum LoadActionPredictor {

    /// Compute the optimistic forward Load value for `(current, action, body)`.
    ///
    /// Pure — no UIKit, no I/O. The function is total over the
    /// policy-permitted (action, status) cross-product (D-15). Out-of-policy
    /// combinations return `current` unchanged (defensive no-op — the policy
    /// gate should have prevented them from reaching here).
    ///
    /// Pitfall 3: the `.tender` arm reads `body?.respondByAt` — NOT
    /// `current.respondByAt`. The broker's chosen deadline lives on the
    /// RequestBody; the pre-tap posted load's respondByAt is `nil`.
    ///
    /// `@MainActor` matches the project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor`. The VM in Plan 03 calls this without `await`.
    @MainActor
    public static func predict(
        load current: Load,
        action: LoadAction,
        body: LoadActionEndpoint.RequestBody?
    ) -> Load {
        switch (action, current.status) {

        // D-03 — .post moves draft → posted. No respondByAt yet (nothing
        // tender-related has happened).
        case (.post, .draft):
            return current.with(status: .posted, respondByAt: nil)

        // D-04 / ACTION-02 — .tender on .posted is the canonical issue path;
        // .tender on .rejected and .tender on .expired are the retender
        // alias path (no separate .retender action). All three arms produce
        // an identical predicted Load with body.respondByAt (Pitfall 3).
        case (.tender, .posted),
             (.tender, .rejected),
             (.tender, .expired):
            return current.with(status: .tendered, respondByAt: body?.respondByAt)

        // The carrier/dispatch decision point on an active tender. Both
        // arms clear respondByAt — the tender is no longer in flight after
        // a decision lands. ACTION-04: server is authoritative on .reject
        // (may return .posted directly per D-04); the predictor surfaces
        // .rejected as the transitional state for the optimistic UI.
        case (.accept, .tendered):
            return current.with(status: .accepted, respondByAt: nil)
        case (.reject, .tendered):
            return current.with(status: .rejected, respondByAt: nil)

        // .cancel collapses every non-terminal load to .cancelled with
        // respondByAt cleared. The wildcard pattern is the one general-
        // fanout arm in this switch — the UI-SPEC Per-Action State /
        // Visibility Matrix permits .cancel from every non-terminal status
        // (.draft/.posted/.tendered/.accepted/.dispatched/.inTransit/
        // .rejected/.expired). Terminal cases fall through to the bottom
        // defensive default and return current unchanged.
        case (.cancel, .draft),
             (.cancel, .posted),
             (.cancel, .tendered),
             (.cancel, .accepted),
             (.cancel, .dispatched),
             (.cancel, .inTransit),
             (.cancel, .rejected),
             (.cancel, .expired):
            return current.with(status: .cancelled, respondByAt: nil)

        // D-05 / ACTION-05 — .advanceStatus walks the canonical forward
        // ladder accepted → dispatched → inTransit → delivered. The
        // backend would derive the same target server-side; the predictor
        // mirrors it for the optimistic UI.
        case (.advanceStatus, .accepted):
            return current.with(status: .dispatched, respondByAt: nil)
        case (.advanceStatus, .dispatched):
            return current.with(status: .inTransit, respondByAt: nil)
        case (.advanceStatus, .inTransit):
            return current.with(status: .delivered, respondByAt: nil)

        default:
            // Policy gate should have prevented reaching this arm. Defensive
            // no-op so a stray caller does not crash. See
            // LoadActionPredictorTests test_outOfPolicyCombination_returnsCurrent_defensiveNoOp.
            return current
        }
    }
}
