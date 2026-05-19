---
phase: 07
slug: load-domain-model-mock-contract
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-19
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Authoritative source for Test Infrastructure, Sampling Rate, and Wave 0 Gaps is `07-RESEARCH.md` § "Validation Architecture" — the planner copies the relevant rows into the Per-Task Verification Map below when writing PLAN.md files.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 26 bundled) + XCUITest where physical-device UAT applies (not Phase 7) |
| **Config file** | `validationLedger.xcodeproj` schemes — `validationLedgerTests` target; no separate config file |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.x' -only-testing:validationLedgerTests/Load -only-testing:validationLedgerTests/Networking` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.x' -only-testing:validationLedgerTests` (use the scoped serial simulator-lane command — bare `xcodebuild test` gives ~67 false failures per memory `ios-test-suite-pitfalls`) |
| **Estimated runtime** | ~< 30 seconds for the scoped Load+Networking run on Simulator |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test ... -only-testing:validationLedgerTests/Load` (~< 5s on Simulator)
- **After every plan wave:** Run the scoped Load + Networking quick command above (~< 30s)
- **Before `/gsd:verify-work`:** Full simulator suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| {N}-01-01 | 01 | 1 | REQ-{XX} | T-{N}-01 / — | {expected secure behavior or "N/A"} | unit | `{command}` | ✅ / ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> Populated by the planner during PLAN.md generation, from `07-RESEARCH.md` § Validation Architecture → "Phase Requirements → Test Map" + the planner's task IDs.

---

## Wave 0 Requirements

Per `07-RESEARCH.md` § Validation Architecture → Wave 0 Gaps, the entire test infrastructure for `Core/Load/` is new:

- [ ] `validationLedgerTests/Load/` directory creation (mirrors `validationLedgerTests/KYC/`, `validationLedgerTests/Networking/`)
- [ ] `validationLedgerTests/Load/LoadDomainDecodeTests.swift` — base fixture-decode coverage (per VL-id success path)
- [ ] `validationLedgerTests/Load/VerificationStateDecoderTests.swift` — fail-closed edge cases (LOAD-02 D-09)
- [ ] `validationLedgerTests/Load/RoleLoadPolicyTests.swift` — 5 × 13 exhaustive matrix (LOAD-02 D-06)
- [ ] `validationLedgerTests/Load/ChainOfTrustDecodeTests.swift` — 3 fraud archetypes + clean (LOAD-02 D-08)
- [ ] `validationLedgerTests/Load/LoadStateHistoryTests.swift` — stateHistory ordering (LOAD-02 D-02)
- [ ] `validationLedgerTests/Networking/LoadEndpointsTests.swift` — the 3 endpoints × success/error fixtures (LOAD-01)
- [ ] `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` — additive latency (LOAD-01 SC #4)
- [ ] `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` — additive forced-failure (LOAD-01 SC #4)
- [ ] Extension to `validationLedgerTests/App/AppContainerNetworkConfigTests.swift` — mock/live swap with new endpoints (LOAD-01 SC #5)
- [ ] Fixture authoring: `loads-list-{role}.json` × 5 + `load-detail-VL-{id}.json` × 12 + `loads-list-empty.json` + `load-action-{success,conflict-409,validation-422,server-error-500}.json`

**Framework install:** None — Swift Testing is bundled with Xcode 26.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| — | — | — | — |

*All Phase 7 behaviors have automated verification — this is a pure contract/data-model phase with no UI or device-specific behavior.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (all 11 test files + fixture set)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
