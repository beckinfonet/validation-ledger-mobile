// validationLedger/Core/Load/RoleLoadPolicy.swift
// Phase 7 LOAD-02 (D-03, D-04, D-05, D-06): the pure (Role, LoadStatus) →
// [LoadAction] resolver — the single source of truth for "what can this
// role do on a load in this state".
//
// This file is the heart of the Phase 7 contract that Phase 10 reads to
// render its action bar. Extracting it as a pure function (D-06) is what
// lets Phase 10's action-bar code NEVER contain a `switch load.status` in
// any view controller — the policy lives here, exhaustively tested by
// RoleLoadPolicyTests.
//
// D-03 — Tender gate is `posted`-only. `post` moves `draft → posted`;
//        `tender` acts ONLY on a `posted` load. No direct `draft → tendered`
//        path. The shipper/broker draft action is therefore `[.post]`, and
//        the shipper/broker posted action set includes `.tender`.
//
// D-04 — `retender` is NOT a distinct LoadAction. After a reject or tender
//        expiry the load returns to `.posted`, which already affords
//        `.tender`. Prior rejected/expired tenders are recorded in
//        `Load.stateHistory` (D-02). For UX visibility while the load is
//        STILL in `.rejected` or `.expired` (server has not yet transitioned
//        it back to `.posted`), the policy returns `[.tender, .cancel]` so
//        the broker can re-tender directly from the rejected/expired state.
//
// D-05 — ACTION-05 status advancement collapses to a SINGLE
//        `.advanceStatus` case. The backend derives the target state as
//        the next step in the canonical order
//        (accepted → dispatched → inTransit → delivered). For
//        carrier/dispatch on `.accepted`, `.dispatched`, `.inTransit` the
//        policy returns `[.advanceStatus]` — NOT three per-transition cases.
//
// D-06 — 5 roles collapse to 3 surfaces:
//        - Shipper ≡ Broker  → ownership/lifecycle actions
//        - Carrier ≡ Dispatch → counterparty response + status advance
//        - Factoring         → always [] (view-only for every state)
//        Within each pair the action sets are IDENTICAL. The Plan 10
//        action bar must NOT differentiate within a pair.
//
// === Switch shape — tuple over (role, status) ===
// The body is a SINGLE nested switch on the (role, status) tuple. The
// Factoring-empty invariant is encoded as `case (.factoring, _): return []`
// — one line that handles all 13 LoadStatus cases for Factoring per D-06.
// The shipper/broker and carrier/dispatch surfaces each nest an inner switch
// over LoadStatus that is EXHAUSTIVE — no `default:` fallback — so a future
// LoadStatus case added to Plan 01 forces a compile-time update here.
//
// === Threat T-07-08 (Elevation of Privilege) mitigation ===
// Per-role surface returns hardcoded action arrays. The server remains the
// enforcement boundary on every action; this client-side policy is the UX
// gating that decides what's tappable.

import Foundation

/// The pure `(Role, LoadStatus) → [LoadAction]` policy resolver per D-06.
///
/// This is a `public enum` with no cases (a namespace) — analogous to
/// `RejectionReasonCode.copy(for:)` in shape (pure `switch` resolver, no
/// UIKit, no state). The Phase 10 action bar wires the result of
/// `actions(for:status:)` directly into the visible buttons.
public enum RoleLoadPolicy {

    /// Returns the legal `[LoadAction]` for `(role, status)`.
    ///
    /// Total function — every (Role, LoadStatus) pair returns a defined
    /// (possibly empty) action array. Verified by the exhaustive sweep in
    /// `RoleLoadPolicyTests.policyIsTotal`.
    public static func actions(for role: Role, status: LoadStatus) -> [LoadAction] {
        switch (role, status) {

        // D-06 — Factoring is VIEW-ONLY for every LoadStatus. One case
        // handles all 13 LoadStatus values via the wildcard pattern.
        case (.factoring, _):
            return []

        // Shipper ≡ Broker — ownership / lifecycle surface (D-06).
        case (.shipper, _), (.broker, _):
            switch status {
            // D-03 — post moves draft → posted.
            case .draft:        return [.post]
            // D-03 — tender gate is posted-only. Cancel always available
            // for an in-flight broker-owned load.
            case .posted:       return [.tender, .cancel]
            // Active tender — broker can still cancel the load.
            case .tendered:     return [.cancel]
            // Carrier has accepted / is moving the load — broker retains
            // the ownership-side cancel.
            case .accepted,
                 .dispatched,
                 .inTransit:    return [.cancel]
            // D-04 — server has the load in .rejected / .expired; the
            // broker can re-tender directly from here. Re-tender = .tender
            // invoked again (no separate retender case). Cancel also
            // remains available.
            case .rejected,
                 .expired:      return [.tender, .cancel]
            // Terminal states — no actions.
            case .delivered,
                 .cancelled,
                 .podCaptured,
                 .invoiced,
                 .funded:       return []
            }

        // Carrier ≡ Dispatch — counterparty-response surface (D-06).
        case (.carrier, _), (.dispatch, _):
            switch status {
            // The carrier/dispatch decision point on an active tender.
            case .tendered:     return [.accept, .reject]
            // D-05 — single .advanceStatus case for the three forward
            // transitions accepted → dispatched → inTransit → delivered.
            // Backend derives the target state from the load's current
            // status when the request lands.
            case .accepted,
                 .dispatched,
                 .inTransit:    return [.advanceStatus]
            // No action for the carrier/dispatch in these states.
            case .draft,
                 .posted,
                 .delivered,
                 .rejected,
                 .expired,
                 .cancelled,
                 .podCaptured,
                 .invoiced,
                 .funded:       return []
            }
        }
    }
}

// MARK: - Phase 10 — VM-facing call shape (D-22 / Pitfall 4)
//
// `availableActions(for:in:)` is the SINGLE call shape the action region
// (Plan 04) uses. The VM stores `role`; the load comes from the VM's `.loaded`
// state — `availableActions(for: viewModel.role, in: load)` matches that
// composition naturally.
//
// This extension is **naming sugar**, NOT new policy. It delegates one-to-one
// to the frozen Phase 7 `actions(for:status:)` truth table. The 5 × 13
// invariant continues to live in the Phase 7 tests
// (validationLedgerTests/Load/RoleLoadPolicyTests.swift); the Phase 10
// `RoleLoadPolicyAvailableActionsTests` asserts only the delegation.
//
// Locating this extension in the SAME file as the underlying enum keeps the
// truth-table and its VM-facing wrapper visible together — any future change
// to the policy table forces a re-read of this delegation in the same diff.
public extension RoleLoadPolicy {

    /// The legal `[LoadAction]` for a given role on the given load — VM
    /// composition shape.
    ///
    /// Pure delegation to `actions(for: role, status: load.status)`. No
    /// additional read from the Load aggregate; the Phase 7 policy contract
    /// is `(Role, LoadStatus) → [LoadAction]`, full stop. This wrapper exists
    /// so the action region can call `availableActions(for: viewModel.role,
    /// in: load)` without the calling-site re-extracting `load.status` —
    /// keeping the gate logic with `RoleLoadPolicy` (no `switch load.status`
    /// in any Phase 10 view controller per the ROADMAP § Phase 10
    /// invariant).
    static func availableActions(for role: Role, in load: Load) -> [LoadAction] {
        actions(for: role, status: load.status)
    }
}
