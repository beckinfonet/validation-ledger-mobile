---
status: partial
phase: 10-per-role-tender-accept-reject
source: [10-VERIFICATION.md]
started: 2026-05-21T20:05:00Z
updated: 2026-05-21T20:05:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Toast banner animation feel — slide-in duration, dwell, auto-dismiss fade
expected: Banner rises from top, dwells ~3.5s, fades cleanly. Medium-impact haptic at slide-in start. Swipe-up dismisses it.
why_human: Animation timing and haptic feel cannot be asserted by XCTest. XCUITest soft-asserts toast existence only (3.5s auto-dismiss window too narrow for deterministic XCUI snapshot).
result: [pending]

### 2. Tender sheet `.medium` detent ergonomics on real iPhone
expected: Sheet sits in the lower 50% of the screen. Carrier picker and deadline chips are reachable with one thumb. Date picker opens cleanly at Custom.
why_human: UISheetPresentationController detent ergonomics are a physical-feel call that cannot be verified on a simulator. Requires device.
result: [pending]

### 3. 65-cell snapshot matrix legibility at Default + Large Dynamic Type
expected: Each (Role × LoadStatus) cell reads cleanly at both content sizes. No button text truncation that hides intent. Destructive tint visually distinct on Cancel / Reject buttons.
why_human: PNG baselines prove layout exists; visual quality judgment requires human eyeball review of the snapshot PNGs.
result: [pending]

### 4. DEBUG launch-arg failure toggles exercised on a real device
expected: With `-MockActionServerError500 -MockActionLatencySlow`: optimistic predict state is visible during the ~1.5s latency window, then rollback fires and toast banner slides in. With `-MockActionConflict409` and `-MockActionValidation422`: same rollback + toast behavior.
why_human: `-MockActionLatencySlow` injects a 1.5s `Thread.sleep` on the mock URLSession handler — the in-flight optimistic state is only perceptible to a human watching real hardware. Simulator is too fast and lacks haptic feedback.
result: [pending]

### 5. End-to-end broker tender → carrier accept pop-back on device
expected: Broker taps Tender on VL-1003 (posted), sheet opens, picks Acme Logistics (verified), sets 1-day deadline, taps Send. Load transitions to tendered. Carrier role opens same load, sees Respond by deadline, taps Accept. Pops back to list: load row shows 'Accepted' status badge.
why_human: Multi-role happy-path flow requires exercising two role contexts sequentially. Covers ACTION-01 through ACTION-03 plus ACTION-09 list-refresh in a single observed interaction. Not automatable in a single XCUITest session.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
