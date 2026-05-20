---
phase: 09-load-detail-chain-of-trust-graph
created: 2026-05-20
status: pending
source: 09-VERIFICATION.md (status=human_needed) + 09-MANUAL-TESTS.md (Plan 10 device-test checklist)
canonical_checklist: .planning/phases/09-load-detail-chain-of-trust-graph/09-MANUAL-TESTS.md
pending_scenarios: 6
total_scenarios: 6
---

# Phase 9 Human UAT — Load Detail & Chain-of-Trust Graph

**Convention pointer.** This file exists to honor the `XX-HUMAN-UAT.md` convention used across v1.0 Phases 1–6 (STATE.md "Deferred Items" tracks `uat_gap: XX-HUMAN-UAT.md`). The **canonical device-test checklist authored by Plan 10 lives in [09-MANUAL-TESTS.md](./09-MANUAL-TESTS.md)** — go there for the full per-device (iPhone 17 + iPad Air) checkbox protocol.

The 6 items below mirror what `09-VERIFICATION.md` surfaced as `human_needed` after automated verification confirmed 5/5 must-haves are achieved in code. They cannot be automated because they are observational (gesture feel, animation continuity across rotation, VoiceOver runtime behavior, layout aesthetics, shimmer cadence comparison, dim-others visual readability).

## Pending Scenarios (6)

| # | Scenario | Device targets | Linked in MANUAL-TESTS.md |
|---|----------|----------------|---------------------------|
| 1 | Pinch-zoom gesture feel + outer-scroll preservation | iPhone 17 + iPad Air | yes |
| 2 | Halo pulse animation continuity (rotation, lock-screen, backgrounding) on VL-1009 | iPad Air primary | yes |
| 3 | VoiceOver traversal order (iPhone + iPad landscape) + activation behavior + zoom-suspend | iPhone 17 + iPad Air | yes |
| 4 | iPad split layout 60/40 ratio + rotation animation aesthetics | iPad Air | yes |
| 5 | Skeleton-with-shimmer visual continuity matching Phase 8 cadence | iPhone 17 + iPad Air | yes |
| 6 | Dim-others (~0.6 opacity) visual readability on VL-1009 | iPhone 17 + iPad Air | yes |

Per-test full preconditions, steps, and pass criteria are in `09-MANUAL-TESTS.md`. Mark items resolved there; this file's `pending_scenarios` count reflects whatever remains unchecked.

## Resolution Protocol

When a tester executes the MANUAL-TESTS.md protocol on real hardware:

1. Tick the appropriate `iPhone 17` / `iPad Air` checkbox in `09-MANUAL-TESTS.md` for each scenario.
2. If a scenario fails, open a GSD debug session or amend `09-VERIFICATION.md` with a `gaps_found` entry referencing the failing item.
3. When all 6 scenarios pass on at least one device of each form factor, rerun `/gsd:verify-work 09` (or the orchestrator's verify gate) so `09-VERIFICATION.md` flips from `status: human_needed` → `status: passed`.
4. Bump this file's `pending_scenarios` count and `status` accordingly.

## Why This is the Expected Posture

Phase 9 is the marquee surface of v1.1 (the trust graph) and is deeply gesture-, animation-, and VoiceOver-driven. The v1.0 milestone-audit already established that physical-device observation items are a normal part of the GSD close-out cycle (see STATE.md "Deferred Items" → 18 acknowledged-and-deferred artifacts from Phases 1–6). Phase 9 inherits the same posture: code-complete + automation-green + device-UAT pending.
