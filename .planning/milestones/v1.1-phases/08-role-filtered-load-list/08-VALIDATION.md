---
phase: 8
slug: role-filtered-load-list
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-19
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Detailed validation architecture lives in `08-RESEARCH.md` `## Validation Architecture`.
> Per-task verification rows are populated by the planner from PLAN.md frontmatter and
> filled in during execution. This file is the contract between planning and execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (iOS-bundled) + handful of Swift Testing macros where already used (Phase 7) |
| **Config file** | `validationLedger.xcodeproj/project.pbxproj` (test targets: `validationLedgerTests`, `validationLedgerUITests`) |
| **Quick run command** | `xcodebuild -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerTests/<Suite> test` (per-suite — see `[[ios-test-suite-pitfalls]]`; bare `xcodebuild test` produces ~67 false failures) |
| **Full suite command** | Scoped serial simulator-lane command from `[[ios-test-suite-pitfalls]]` memory — `xcodebuild -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -test-iterations 1 -parallel-testing-enabled NO -only-testing:validationLedgerTests -only-testing:validationLedgerUITests test` |
| **Estimated runtime** | Quick (single-suite unit): ~10–20 s. Full simulator lane (unit + UI smoke): ~3–5 min. Device CI lane (Phase 4 close-out): ~12–18 min — see `[[phase-4-ci-closeout]]`. |

---

## Sampling Rate

- **After every task commit:** Run the per-suite `-only-testing:` quick command for the suite under change.
- **After every plan wave:** Run the full simulator-lane scoped command.
- **Before `/gsd:verify-work`:** Full suite must be green (simulator lane). Device CI lane is exercised per `[[phase-4-ci-closeout]]` cadence (do NOT chain `xcodebuild test` on device — Face ID prompts hang the lane; see `[[device-ci-locked-iphone]]`).
- **Max feedback latency:** 20 s for per-suite unit; 5 min for full simulator lane.

---

## Per-Task Verification Map

> Populated by the planner from PLAN.md frontmatter. One row per task. The planner sets
> the first 6 columns; execution fills `File Exists` / `Status`.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _populated by planner_ | | | | | | | | | |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

> Wave 0 = test infrastructure that must exist before any feature task can run its automated verification.
> The full list is enumerated in `08-RESEARCH.md` `## Validation Architecture`. Headline items:

- [ ] Hand-rolled snapshot helper (`UIView` → `UIImage` via `UIGraphicsImageRenderer` + `XCTAttachment`) in `validationLedgerTests/Support/UIKitSnapshot.swift` — precedent at `validationLedgerTests/KYC/KYCThumbnailTests.swift:34`. Zero new SwiftPM deps (STACK-04 / CLAUDE.md).
- [ ] `validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift` — fixture-decode tests for the new `LoadListItem` envelope (D-02), the snake_case bridge (`displayed_counterparty` → `displayedCounterparty`), and the fail-closed `nil` path (D-03).
- [ ] `validationLedgerTests/Loads/LoadListViewModelTests.swift` — VM state-machine harness (loading → loaded / loading → empty / loading → error / loaded → loading via refresh).
- [ ] `validationLedgerTests/Loads/Snapshot/` — snapshot baselines for `VerificationBadgeView` (4 states), `LoadStatusBadgeView` (13 states), `LoadRowCell` (verified / pending / unverified / flagged variants), `SkeletonLoadRowCell`.
- [ ] `validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift` — 5-role smoke flow (tap "Loads" on each role tab bar; assert `loads-list` accessibility identifier resolves).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Shimmer animation reads as "loading" on a 60 Hz display without distracting motion | LOAD-07 (loading state) + D-09 | `CABasicAnimation` timing is a perceptual call; snapshot tests cover silhouette but not motion feel | Run `Loads` tab on a fixture with injected latency ≥ 1.5 s; verify the shimmer sweep duration (~1.0–1.5 s) reads as activity without flicker. Test on iPhone 15 simulator at 60 Hz. |
| iPad regular-width native render (not scaled) | SC-#5 of phase + LOAD-04 | Visual: confirm `readableContentGuide` pinning vs auto-scale | Run on iPad Pro 12.9" simulator in regular width; confirm row content sits inside the readable-content guide (~700 pt max), not stretched edge-to-edge. |
| Fail-closed UNVERIFIED render on degraded fixture does not leak "verified" to VoiceOver | TRUST-02 + D-03 | A11y label semantics on `nil` counterparty | Run `loads-list-degraded-counterparty.json` fixture; enable VoiceOver; navigate to the `nil`-counterparty row; confirm spoken label contains "unverified" (or omits "verified" entirely) — never the optimistic-default "verified" string. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (snapshot helper is the only known gap)
- [ ] No watch-mode flags (`xcodebuild` is one-shot per invocation)
- [ ] Feedback latency < 5 min for the full simulator lane
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
