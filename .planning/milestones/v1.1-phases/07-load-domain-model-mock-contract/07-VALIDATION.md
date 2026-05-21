---
phase: 07
slug: load-domain-model-mock-contract
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-19
updated: 2026-05-19
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Authoritative source for Test Infrastructure, Sampling Rate, and Wave 0 Gaps is `07-RESEARCH.md` § "Validation Architecture" — populated below from the planner's task IDs.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 26 bundled) + XCUITest where physical-device UAT applies (not Phase 7) |
| **Config file** | `validationLedger.xcodeproj` schemes — `validationLedgerTests` target; no separate config file |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests/Load -only-testing:validationLedgerTests/Networking` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests` (use the scoped serial simulator-lane command — bare `xcodebuild test` gives ~67 false failures per memory `ios-test-suite-pitfalls`) |
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
| 07-01-01 | 01 | 1 | LOAD-02 (D-01/D-03/D-04/D-05/D-07) | T-07-03, T-07-04, T-07-05 | LoadStatus/LoadAction/DeviceBindingStatus/USDOTAuthorityStatus exist as closed enums | unit | `xcodebuild build … -scheme validationLedger` | ❌ W0 (source files new) | ⬜ pending |
| 07-01-02 | 01 | 1 | LOAD-02 (D-09) | T-07-01 | VerificationState fail-closed: unknown→.unverified, missing→DecodingError | unit | `xcodebuild test … -only-testing:validationLedgerTests/Load/VerificationStateDecoderTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-01-03 | 01 | 1 | LOAD-02 (D-08/D-09) | T-07-02 | ChainIntegrity.Verdict fail-closed-to-suspicious: unknown→.compromised | unit | `xcodebuild test … -only-testing:validationLedgerTests/Load/VerificationStateDecoderTests` | ❌ W0 (extends 01-02 file) | ⬜ pending |
| 07-02-01 | 02 | 2 | LOAD-02 (D-02/D-07/D-08) | T-07-06, T-07-10 | LoadStatusEvent, LoadParty, ChainOfTrust, TrustNode, TrustEdge are Decodable + Sendable; no client-derived trust property | unit | `xcodebuild build` | ❌ W0 (source files new) | ⬜ pending |
| 07-02-02 | 02 | 2 | LOAD-02 (D-02) | T-07-07, T-07-09 | Load aggregate composes LoadStatusEvent + stateHistory + tenderEligibility | unit | `xcodebuild build` | ❌ W0 (source files new) | ⬜ pending |
| 07-02-03 | 02 | 2 | LOAD-02 (D-03/D-04/D-05/D-06) | T-07-08, T-07-11 | RoleLoadPolicy.actions(for:status:) is total across 5×13; Factoring=[]; Shipper≡Broker; Carrier≡Dispatch | unit | `xcodebuild test … -only-testing:validationLedgerTests/Load/RoleLoadPolicyTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-03-01 | 03 | 3 | LOAD-01 (D-08/D-15/D-16) | T-07-15, T-07-16 | LoadListEndpoint role-in-path + paginated envelope; LoadDetailEndpoint embedded ChainOfTrust | unit | `xcodebuild test … -only-testing:validationLedgerTests/Networking/LoadEndpointsTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-03-02 | 03 | 3 | LOAD-01 (D-15/D-19) | T-07-12, T-07-13 | LoadActionEndpoint method=.post auto-IDK; action-in-path | unit | `xcodebuild test … -only-testing:validationLedgerTests/Networking/LoadEndpointsTests` | ❌ W0 | ⬜ pending |
| 07-03-03 | 03 | 3 | LOAD-01 | T-07-12, T-07-15 | All 3 endpoint shapes + 5 roles × 6 actions matrix verified | unit | `xcodebuild test … -only-testing:validationLedgerTests/Networking/LoadEndpointsTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-04-01 | 04 | 1 | LOAD-01 SC #4, SC #5 (D-14/D-18) | T-07-17, T-07-18, T-07-20 | MockURLProtocol gains additive latency + forced-failure; existing register/reset/registerFixture byte-identical | unit | `xcodebuild build` + `git diff --stat MockFixture.swift` | ❌ W0 (additive edit + storage) | ⬜ pending |
| 07-04-02 | 04 | 1 | LOAD-01 SC #4 | T-07-18, T-07-20 | registerFixtureWithLatency delivers response after ≥ specified delay | unit | `xcodebuild test … -only-testing:validationLedgerTests/Networking/MockURLProtocolLatencyTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-04-03 | 04 | 1 | LOAD-01 SC #4 (D-14) | T-07-20, T-07-21 | registerForcedFailure delivers URLError + HTTP-status forced failures | unit | `xcodebuild test … -only-testing:validationLedgerTests/Networking/MockURLProtocolForcedFailureTests` | ❌ W0 (test file new) | ⬜ pending |
| 07-05-01 | 05 | 3 | LOAD-01 SC #1 (D-10/D-11/D-12/D-13) | T-07-22, T-07-23, T-07-26 | 12 named load-detail JSON fixtures with fraud archetypes flagged (D-13 a/b/c) | unit | `for f in fixtures; do python3 -m json.tool $f; done` | ❌ W0 (fixtures new) | ⬜ pending |
| 07-05-02 | 05 | 3 | LOAD-01 SC #1 (D-11/D-14) | T-07-22, T-07-26 | 5 per-role list fixtures + empty + 4 action-outcome fixtures; D-11 shared-world byte-identity for same VL- | unit | python -c JSON validation | ❌ W0 (fixtures new) | ⬜ pending |
| 07-05-03 | 05 | 3 | LOAD-01 SC #1, LOAD-02 | T-07-24, T-07-25 | All 22 fixtures decode via APIClient.defaultDecoder() into Plan 03 Response types | unit | `xcodebuild test … -only-testing:validationLedgerTests/Load/LoadDomainDecodeTests -only-testing:validationLedgerTests/Load/ChainOfTrustDecodeTests -only-testing:validationLedgerTests/Load/LoadStateHistoryTests` | ❌ W0 (test files new) | ⬜ pending |
| 07-06-01 | 06 | 4 | LOAD-01 (D-15/D-17/D-18) | T-07-27, T-07-28 | MockLoadFixtureRegistry DEBUG-only; mirrors MockOTPRoleFixtureRegistry; no MockDefaultFixtures edit | unit | `xcodebuild build` + `git diff --stat MockDefaultFixtures.swift` | ❌ W0 (registry file new) | ⬜ pending |
| 07-06-02 | 06 | 4 | LOAD-01 (D-17) | T-07-27 | AppContainer.init DEBUG block calls MockLoadFixtureRegistry.registerAppDefaults() | unit | `grep -c MockLoadFixtureRegistry.registerAppDefaults validationLedger/App/AppContainer.swift` ≥ 1 | ❌ W0 (one-line edit) | ⬜ pending |
| 07-06-03 | 06 | 4 | LOAD-01 SC #5 (D-18) | T-07-29, T-07-30, T-07-32 | mock/live swap compiles with new endpoints; end-to-end VL-1009 decodes with .compromised verdict | unit | `xcodebuild test … -only-testing:validationLedgerTests/App/AppContainerNetworkConfigTests` | ❌ W0 (test extension) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Per `07-RESEARCH.md` § Validation Architecture → Wave 0 Gaps, the entire test infrastructure for `Core/Load/` is new. Plans 01–06 collectively create:

- [x] `validationLedgerTests/Load/` directory (created implicitly by Plan 01 Task 2)
- [ ] `validationLedgerTests/Load/VerificationStateDecoderTests.swift` (Plan 01 Task 2 + Task 3 extends it)
- [ ] `validationLedgerTests/Load/RoleLoadPolicyTests.swift` (Plan 02 Task 3)
- [ ] `validationLedgerTests/Load/LoadDomainDecodeTests.swift` (Plan 05 Task 3)
- [ ] `validationLedgerTests/Load/ChainOfTrustDecodeTests.swift` (Plan 05 Task 3)
- [ ] `validationLedgerTests/Load/LoadStateHistoryTests.swift` (Plan 05 Task 3)
- [ ] `validationLedgerTests/Networking/LoadEndpointsTests.swift` (Plan 03 Task 3)
- [ ] `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` (Plan 04 Task 2)
- [ ] `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` (Plan 04 Task 3)
- [ ] Extension to `validationLedgerTests/App/AppContainerNetworkConfigTests.swift` (Plan 06 Task 3 — additive)
- [ ] 22 JSON fixtures under `validationLedgerTests/Networking/Fixtures/` (Plan 05 Task 1 + Task 2)

**Framework install:** None — Swift Testing is bundled with Xcode 26.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| — | — | — | — |

*All Phase 7 behaviors have automated verification — this is a pure contract/data-model phase with no UI or device-specific behavior.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (all 9 test files + fixture set + project.pbxproj resource membership)
- [x] No watch-mode flags
- [x] Feedback latency < 30s (scoped Load + Networking command)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (review after Wave 1 completes — re-approve once Plan 01 + Plan 04 land green on the simulator lane)
