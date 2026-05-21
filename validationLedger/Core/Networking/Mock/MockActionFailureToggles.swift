// validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift
// Phase 10 D-19 — four DEBUG-only launch-arg toggles enabling on-device
// exercise of the action-rollback path during human UAT.
//
// === Phase 5 precedent (verbatim shape) ===
// Mirrors `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift:60-76`
// (`-MockKYCStatusVerified`) — same `#if DEBUG`-gated `public enum` with a
// `…Flag` constant per toggle and an `…Active` reader per toggle.
//
// === Production shape vs. test seam (D-19 + Pattern 4) ===
// Phase 5 used a computed property:
//   `static var verifiedKYCStatusOverrideActive: Bool { ProcessInfo... }`
// Phase 10's tests need to override the value without mutating process-wide
// `ProcessInfo.arguments`. To keep the production semantics identical while
// preserving an injectable seam, the 4 `…Active` checks are exposed as
// `static var … : () -> Bool` closures with default values that read
// `ProcessInfo.processInfo.arguments` — semantically equivalent to a
// computed property in every release-build code path. Tests reassign in
// setUp + restore in tearDown. The trade-off is documented inline below.
//
// === Release safety (CLAUDE.md `#if DEBUG`-gated launch args + zero-bytes-in-Release) ===
// File-level `#if DEBUG ... #endif` gate; Release builds compile this entire
// enum to ZERO bytes. The 4 handler registrations in `MockLoadFixtureRegistry`
// are likewise `#if DEBUG`-wrapped, so a Release build cannot reach the
// failure-injection branches. The default mock action-success handler
// (Phase 7) is untouched and remains the ONLY action-response shape shipped
// to TestFlight/App Store.
//
// === Pitfall 2 (registration-order precedence) ===
// In `MockLoadFixtureRegistry.registerAppDefaults()` the 4 toggle handlers
// register BEFORE the existing action-success handler with first-match-wins
// ordering:
//   (3a) conflict409  → 409 + load-action-conflict-409.json
//   (3b) validation422 → 422 + load-action-validation-422.json
//   (3c) serverError500 → 500 + load-action-server-error-500.json
//   (3d) latencySlow   → inserts ~1.5s delay, then returns nil to DEFER
//                        to the next matching handler (success OR 3a/3b/3c
//                        if combined).
//   (3)  action-success → 200 + load-action-success.json (unchanged).
// QA workflow guidance: set exactly ONE failure flag at a time; the
// combined-flag case is a defensive fallback and is tested for behavior,
// not a feature.

#if DEBUG
import Foundation

public enum DebugActionFailureOverride {

    // MARK: - Launch-argument constants

    /// Launch arg that forces every `LoadActionEndpoint` POST to return a
    /// `409 Conflict` carrying `load-action-conflict-409.json` (error_code:
    /// `load.stale_state`). Models the "another party already actioned this
    /// load" race that drives the optimistic-predict → rollback path.
    public static let conflict409Flag    = "-MockActionConflict409"

    /// Launch arg that forces every `LoadActionEndpoint` POST to return a
    /// `422 Unprocessable Entity` carrying `load-action-validation-422.json`
    /// (error_code: `load.invalid_transition`). Models "cannot accept a load
    /// that is not currently tendered" and similar server-side guards.
    public static let validation422Flag  = "-MockActionValidation422"

    /// Launch arg that forces every `LoadActionEndpoint` POST to return a
    /// `500 Internal Server Error` carrying `load-action-server-error-500.json`
    /// (error_code: `server.internal`). Models the generic backend-failure
    /// rollback path.
    public static let serverError500Flag = "-MockActionServerError500"

    /// Launch arg that inserts a ~1.5s `Thread.sleep` on every
    /// `LoadActionEndpoint` POST then DEFERS to the next matching handler.
    /// Makes the optimistic-predict + chain-overlay visible to the human eye
    /// during device UAT without short-circuiting the response. Combined
    /// with a failure flag: delay then failure-fixture body.
    public static let latencySlowFlag    = "-MockActionLatencySlow"

    // MARK: - Activation closures (production shape + test seam)

    /// True when `-MockActionConflict409` is present in this process's
    /// launch arguments. Exposed as a closure rather than a computed
    /// property so unit tests can override without mutating process-wide
    /// `ProcessInfo.arguments`. Production builds run the default closure
    /// — semantically identical to the Phase-5 computed-property pattern.
    public static var conflict409Active: () -> Bool = {
        ProcessInfo.processInfo.arguments.contains(conflict409Flag)
    }

    /// True when `-MockActionValidation422` is present in this process's
    /// launch arguments. See `conflict409Active` for the closure-seam rationale.
    public static var validation422Active: () -> Bool = {
        ProcessInfo.processInfo.arguments.contains(validation422Flag)
    }

    /// True when `-MockActionServerError500` is present in this process's
    /// launch arguments. See `conflict409Active` for the closure-seam rationale.
    public static var serverError500Active: () -> Bool = {
        ProcessInfo.processInfo.arguments.contains(serverError500Flag)
    }

    /// True when `-MockActionLatencySlow` is present in this process's
    /// launch arguments. See `conflict409Active` for the closure-seam rationale.
    public static var latencySlowActive: () -> Bool = {
        ProcessInfo.processInfo.arguments.contains(latencySlowFlag)
    }

    /// Production-equivalent constant for the latency handler's sleep
    /// interval. ~1.5s makes the optimistic-predict + chain overlay visible
    /// to the human eye during device UAT without being annoying during
    /// repeated test runs.
    public static let latencySlowInterval: TimeInterval = 1.5
}
#endif
