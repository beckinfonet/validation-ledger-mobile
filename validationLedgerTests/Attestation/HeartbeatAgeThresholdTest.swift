// validationLedgerTests/Attestation/HeartbeatAgeThresholdTest.swift
// Phase 4 Plan 05 Task 4 — D-07c 24h heartbeat age boundary (86399 vs 86401 guard).
//
// Covers D-07c (Plan 05 T4): the 24h threshold that gates fire-or-skip in
// SceneDelegate.performHeartbeatIfNeeded (Plan 07 Task 1). The production
// comparison is `now.timeIntervalSince(last) >= 86400` meaning 86400s-or-more
// → fire. This test pins the non-degenerate samples around the boundary
// (86399s and 86401s) to guard against a `<` vs `<=` mis-flip.
//
// Helper inlines the production semantics so a drift in SceneDelegate surfaces
// here AS LONG AS the engineer updates both sites. A grep gate in the Plan 05
// verification block asserts that "86400" still appears in SceneDelegate.swift
// (once Plan 07 Task 1 lands) — so if the production threshold changes without
// also updating this test, the grep fails.
//
// NOTE: SceneDelegate.performHeartbeatIfNeeded is added in Plan 07 Task 1
// (Wave 4). This test exercises the BOUNDARY ARITHMETIC only — it doesn't
// couple to the production symbol. Once Plan 07 lands, the grep gate in
// the 04-VALIDATION.md Per-Task Verification Map drifts to require both
// production + this test agree on the threshold constant.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-07c — 24h heartbeat age boundary (< vs <= guards)")
struct HeartbeatAgeThresholdTest {

    /// Exercise the exact Date-subtraction comparison used in
    /// SceneDelegate.performHeartbeatIfNeeded (Plan 07 Task 1). Returns
    /// true if the elapsed time since the last heartbeat is AT OR BEYOND the
    /// 24h threshold — mirrors the `>= 86400` semantic described in D-07c.
    private func shouldFireHeartbeat(now: Date, lastHeartbeatAt: Date?) -> Bool {
        guard let last = lastHeartbeatAt else { return true }   // absent → fire
        return now.timeIntervalSince(last) >= 86400             // D-07c: 24h threshold
    }

    @Test("lastHeartbeatAt 86399s ago — do NOT fire (under 24h)")
    func under24h() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let last = now.addingTimeInterval(-86399)   // 86399s ago = 1s under 24h
        #expect(shouldFireHeartbeat(now: now, lastHeartbeatAt: last) == false,
                "D-07c: 86399s is under the 24h threshold; MUST not fire")
    }

    @Test("lastHeartbeatAt 86401s ago — DO fire (over 24h)")
    func over24h() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let last = now.addingTimeInterval(-86401)   // 86401s ago = 1s over 24h
        #expect(shouldFireHeartbeat(now: now, lastHeartbeatAt: last) == true,
                "D-07c: 86401s exceeds the 24h threshold; MUST fire")
    }

    @Test("lastHeartbeatAt exactly 86400s ago — DO fire (24h boundary fires under >=)")
    func exactBoundary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let last = now.addingTimeInterval(-86400)   // exactly 24h ago
        #expect(shouldFireHeartbeat(now: now, lastHeartbeatAt: last) == true,
                "D-07c: 86400s-exact is the threshold; under `>= 86400` semantics, MUST fire")
    }

    @Test("lastHeartbeatAt absent — DO fire (never-heartbeated)")
    func absent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(shouldFireHeartbeat(now: now, lastHeartbeatAt: nil) == true,
                "D-07c: no persisted heartbeat → fire on first call")
    }

    @Test("lastHeartbeatAt 0s ago — do NOT fire (just-fired, zero elapsed)")
    func zeroElapsed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(shouldFireHeartbeat(now: now, lastHeartbeatAt: now) == false,
                "D-07c: zero elapsed (just-fired) MUST not re-fire")
    }
}
