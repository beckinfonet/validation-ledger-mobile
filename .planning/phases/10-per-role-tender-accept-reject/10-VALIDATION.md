---
phase: 10
slug: per-role-tender-accept-reject
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-21
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Apple XCTest + in-house `UIKitSnapshot` helper (Phase 8) |
| **Config file** | `validationLedger.xcodeproj` (scheme: `validationLedger`) |
| **Quick run command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:validationLedgerTests/Loads -parallel-testing-enabled NO 2>&1 \| tail -80` |
| **Full suite command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -parallel-testing-enabled NO 2>&1 \| tail -120` |
| **Estimated runtime** | ~25s scoped (Loads tests) / ~3-5 min full suite |

> ⚠️ Bare `xcodebuild test` (un-scoped, parallel-enabled) is known to produce ~67 false failures on this project — see project memory `ios-test-suite-pitfalls`. Always use the scoped serial-simulator form above.

---

## Sampling Rate

- **After every task commit:** Run scoped quick command (target the test file the task touches; fall back to the Loads-scoped command above).
- **After every plan wave:** Run full suite command.
- **Before `/gsd:verify-work`:** Full suite must be green; 65-cell snapshot matrix (Wave 4) must have all baselines recorded and re-verified.
- **Max feedback latency:** ~30s (scoped) / ~5 min (full).

---

## Per-Task Verification Map

> The planner is the source of truth for task IDs. This table maps requirement → validation tier so the planner can attach the right `<automated>` block to each task it emits. Update with concrete `{phase}-{plan}-{task}` IDs when PLAN.md files are written.

| Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File / Symbol | Status |
|---|---|---|---|---|---|---|
| ACTION-01 (per-role action surface, no `switch load.status`) | T-10-01 (privilege escalation via wrong action shown) | `RoleLoadPolicy.availableActions(for:in:)` is the only gate; lint test asserts zero `switch.*status` in `Features/Loads/**/*ViewController.swift` and `**/*Cell.swift` | unit + lint | `xcodebuild test … -only-testing:validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests` + `grep -nE 'switch[[:space:]]+.*\.status' validationLedger/Features/Loads/**/*ViewController.swift \| (! grep .)` | `RoleLoadPolicyAvailableActionsTests.swift` (NEW) | ⬜ pending |
| ACTION-02 (accept / advance forward-path mutates state) | T-10-02 (state mutation without server confirmation) | Mock POST returns symmetric `{ load, chainOfTrust }`; VM swaps to new load; action set recomputes | unit + UI test | `xcodebuild test … -only-testing:validationLedgerTests/Loads/LoadDetailViewModelActionTests/test_acceptForwardPath` + `validationLedgerUITests/LoadActionFlowsTests/test_carrierCanAcceptActiveTender` | `LoadDetailViewModelActionTests.swift` (NEW), `LoadActionFlowsTests.swift` (NEW) | ⬜ pending |
| ACTION-03 (reject returns load to posted) | T-10-02 | `LoadActionPredictor.predict(.reject)` returns load with `.status = .posted`, `respondByAt = nil`, current counterparty cleared | unit + snapshot | `… -only-testing:validationLedgerTests/Loads/LoadActionPredictorTests/test_rejectReturnsToPosted` + Wave 4 snapshot row (carrier × .activeTender → .posted) | `LoadActionPredictorTests.swift` (NEW) | ⬜ pending |
| ACTION-04 (tender requires verified counterparty — hard disable) | **T-10-04 (CRITICAL — platform thesis)** Tender to unverified counterparty | Tender button `isEnabled = false` AND inline reason label visible when no verified counterparties in directory; sheet picker filters `trustTier == .verified` | unit + snapshot + UI test | `… -only-testing:validationLedgerTests/Loads/TenderEligibilityGatingTests` + snapshot row (broker × .posted, no-verified-directory) + `validationLedgerUITests/TenderGateTests/test_unverifiedCounterpartyHardDisable` | `TenderEligibilityGatingTests.swift` (NEW), `TenderGateTests.swift` (NEW) | ⬜ pending |
| ACTION-05 (optimistic UI + rollback on failure) | T-10-05 (state desync after rollback) | VM snapshots pre-action load; applies predictor result; on `URLError` / non-2xx restores snapshot, surfaces toast, re-enables action; in-flight set prevents double-submit | unit (deterministic mock) + UI test | `… -only-testing:validationLedgerTests/Loads/LoadDetailViewModelRollbackTests` + `validationLedgerUITests/LoadActionFlowsTests/test_rollbackOnServerError500` | `LoadDetailViewModelRollbackTests.swift` (NEW) | ⬜ pending |
| ACTION-06 (post / cancel act on existing fixture loads as state actions; no creation form) | T-10-06 (broker accidentally cancels foreign load) | `RoleLoadPolicy.availableActions(broker, .posted)` includes `.cancel`, `.retender`; `.post` only available on `.draft`; no view controller exposes a multi-field create form | unit + UI absence test | `… -only-testing:validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests/test_brokerCancelOnPosted` + `validationLedgerUITests/LoadActionFlowsTests/test_noLoadCreationFormExists` | `RoleLoadPolicyAvailableActionsTests.swift` (NEW) | ⬜ pending |
| ACTION-07 (active-tender deadline visible inline) | T-10-07 (deadline silently passes) | Carrier on `.activeTender` sees inline "Respond by HH:mm · M/d" label sourced from `load.respondByAt` (rendered via `RelativeDateTimeFormatter` or DateFormatter — planner picks) | snapshot + unit | Wave 4 snapshot row (carrier × .activeTender) + `… -only-testing:validationLedgerTests/Loads/RespondByLabelTests` | `RespondByLabelTests.swift` (NEW) | ⬜ pending |
| ACTION-08 (every action endpoint routes through v1.0 idempotency interceptor) | **T-10-08 (CRITICAL)** Replayed POST mutates state twice | `IdempotencyInterceptor` auto-injects `Idempotency-Key: <UUIDv4>` on every POST; assertion test confirms the interceptor is registered in `apiClient.requestInterceptors` AND that the action endpoint chain receives the header in the recorded mock request | unit (interceptor) + integration (mock dispatch) | `… -only-testing:validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests` + `… -only-testing:validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests/test_actionRequestCarriesIdempotencyKey` | `IdempotencyInterceptorRegistrationTests.swift` (NEW or extend Phase-2 file), `MockLoadActionDispatchTests.swift` (NEW) | ⬜ pending |
| ACTION-09 (after success, list reflects new state on pop-back) | T-10-09 (stale list state) | `LoadListViewController.viewWillAppear` → `fetchLoads()` is preserved; integration test pops back from detail and asserts cell shows new status | UI test (XCUITest) | `validationLedgerUITests/LoadActionFlowsTests/test_listReflectsNewStateOnPopBack` | `LoadActionFlowsTests.swift` (NEW) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## 65-Cell Snapshot Matrix (UI-SPEC line 537)

The 5 × 13 = 65 (Role × LoadStatus) action-bar baselines are the regression gate that proves `RoleLoadPolicy.availableActions(for:in:)` never silently drifts.

| Property | Value |
|---|---|
| **Helper** | `UIKitSnapshot.image(of:size:)` (Phase 8 in-house) |
| **Record command** | `xcodebuild test … -only-testing:validationLedgerTests/Loads/LoadActionBarSnapshotMatrixTests RECORD_SNAPSHOTS=YES` |
| **Verify command** | `xcodebuild test … -only-testing:validationLedgerTests/Loads/LoadActionBarSnapshotMatrixTests` |
| **Baseline directory** | `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/` (NEW) |
| **Sign-off** | Wave 4 — after action region + tender sheet have settled and DEBUG toggles are wired |
| **Re-record precedent** | Phase 9.1 D-05 (visual snapshot baseline re-record after redesign) |

Roles axis: `broker, shipper, carrier, dispatch, factoring`. Status axis: every case of `LoadStatus` (current enum — planner verifies count in `Load.swift`; UI-SPEC assumes 13).

---

## XCUITest Smoke Flows (Wave 5)

| Flow | Coverage |
|---|---|
| `test_brokerCanTenderToVerifiedCarrier` | ACTION-04 success path + idempotency header in dispatched request |
| `test_carrierCanAcceptActiveTender` | ACTION-02 + ACTION-09 (pop-back list reflects new state) |
| `test_carrierCanRejectActiveTender` | ACTION-03 (returns to .posted) + ACTION-09 |
| `test_unverifiedCounterpartyHardDisable` | ACTION-04 (gate, with inline reason) |
| `test_rollbackOnServerError500` | ACTION-05 (DEBUG `-MockLoadActionFailServerError500` toggle drives the failure-injection path) |
| `test_doubleSubmitPrevented` | ACTION-05 in-flight gating |

Mock-toggle precedent: `-MockKYCStatusVerified` (`MockDefaultFixtures.swift:60-76`).

---

## Wave 0 Requirements

> "Wave 0" here means "test infrastructure that must land alongside Wave 1, before any later wave can ship its automated verify."

- [ ] `validationLedgerTests/Loads/LoadActionPredictorTests.swift` — predictor unit test scaffold (RED) before `LoadActionPredictor.swift` exists.
- [ ] `validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift` — `availableActions(for:in:)` matrix test scaffold (RED) before policy extension lands.
- [ ] `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift` — VM action-dispatch test scaffold.
- [ ] `validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift` — confirms `apiClient.requestInterceptors` contains `IdempotencyInterceptor` (may already exist from Phase 2 — planner verifies).
- [ ] `validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift` — mock-bus dispatch assertions (idempotency header propagation).
- [ ] `validationLedgerUITests/LoadActionFlowsTests.swift` — XCUITest scaffold for the 6 flows above.

Framework install: **none required** — XCTest + `UIKitSnapshot` are already in repo.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|---|---|---|---|
| Toast banner animation feels right (rise duration, dwell, fade) | ACTION-05 (rollback toast) | Animation timing is a feel call; XCUITest cannot assert "feels right" — only that the toast appeared and disappeared. | On the device, hit the DEBUG "fail next action" toggle → tap Accept → confirm toast slides up over the chain overlay, dwells for ~3s, then fades. Check both light and dark mode. |
| Tender sheet `.medium` detent feels correct for one-handed iPhone reach | ACTION-04 sheet | Detent ergonomics are subjective; UI-SPEC mandates `.medium` but only device feel confirms reach. | Device UAT — launch tender flow as broker, confirm sheet sits in lower 50% and the date picker is reachable with the thumb. |
| 65-cell snapshot matrix legibility at Default + Large Dynamic Type | ACTION-01 | The matrix proves *layout exists*; whether each cell reads cleanly at Default vs. Large is a visual judgment. | After baseline-record (Wave 4), spot-check 5 rows (one per role) at Default and Large in the `__Snapshots__` PNGs. |

---

## Validation Sign-Off

- [ ] All ACTION-XX requirements have an automated `<automated>` verify in their plan's task (unit, snapshot, or XCUITest tier).
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (planner enforces).
- [ ] Wave 0 scaffolds land in the same plan as the implementation they test (RED-before-GREEN preserved).
- [ ] No watch-mode flags in any command (CI must be deterministic).
- [ ] Quick scoped feedback latency < 30s.
- [ ] 65-cell snapshot matrix recorded and verified before phase verification.
- [ ] DEBUG-only failure-injection toggles wrapped in `#if DEBUG` AND default to OFF when launch arg absent.
- [ ] `nyquist_compliant: true` set in frontmatter after planner verifies all 9 ACTION-XX requirements map to at least one automated command.

**Approval:** pending
