---
phase: 10-per-role-tender-accept-reject
verified: 2026-05-21T20:00:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Toast banner animation feel — slide-in duration, dwell, auto-dismiss fade"
    expected: "Banner rises from top, dwells ~3.5s, fades cleanly. Medium-impact haptic at slide-in start. Swipe-up dismisses it."
    why_human: "Animation timing and haptic feel cannot be asserted by XCTest. XCUITest soft-asserts toast existence only (3.5s auto-dismiss window too narrow for deterministic XCUI snapshot)."

  - test: "Tender sheet .medium detent ergonomics on real iPhone"
    expected: "Sheet sits in the lower 50% of the screen. Carrier picker and deadline chips are reachable with one thumb. Date picker opens cleanly at Custom."
    why_human: "UISheetPresentationController detent ergonomics are a physical-feel call that cannot be verified on a simulator. Requires device."

  - test: "65-cell snapshot matrix legibility at Default + Large Dynamic Type"
    expected: "Each (Role × LoadStatus) cell reads cleanly at both content sizes. No button text truncation that hides intent. Destructive tint visually distinct on Cancel / Reject buttons."
    why_human: "PNG baselines prove layout exists; visual quality judgment requires human eyeball review of the snapshot PNGs."

  - test: "DEBUG launch-arg failure toggles exercised on a real device"
    expected: "With -MockActionServerError500 + -MockActionLatencySlow: optimistic predict state is visible during the ~1.5s latency window, then rollback fires and toast banner slides in. With -MockActionConflict409 and -MockActionValidation422: same rollback + toast behavior."
    why_human: "-MockActionLatencySlow injects a 1.5s Thread.sleep on the mock URLSession handler — the in-flight optimistic state is only perceptible to a human watching real hardware. Simulator is too fast and lacks haptic feedback."

  - test: "End-to-end broker tender → carrier accept pop-back on device"
    expected: "Broker taps Tender on VL-1003 (posted), sheet opens, picks Acme Logistics (verified), sets 1-day deadline, taps Send. Load transitions to tendered. Carrier role opens same load, sees Respond by deadline, taps Accept. Pops back to list: load row shows 'Accepted' status badge."
    why_human: "Multi-role happy-path flow requires exercising two role contexts sequentially. Covers ACTION-01 through ACTION-03 plus ACTION-09 list-refresh in a single observed interaction. Not automatable in a single XCUITest session."
---

# Phase 10: Per-Role Tender / Accept / Reject — Verification Report

**Phase Goal:** Make loads actionable — each role sees and can take only its legal actions for the load's current state, every action mutates load state through optimistic UI with a rollback path, and the platform thesis is enforced in the load domain by hard-disabling tender to an unverified counterparty.

**Verified:** 2026-05-21
**Status:** human_needed — 5/5 automated truths verified; 5 device/visual items require human sign-off (VALIDATION.md Manual-Only + launch-arg UAT + end-to-end device flow)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A load's action bar shows only the legal actions for the signed-in role and load state, driven entirely by `RoleLoadPolicy` — Broker/Shipper can tender/retender/post/cancel; Carrier/Dispatch can accept/reject/advance; Factoring sees none | ✓ VERIFIED | `LoadDetailViewController.swift:1266` calls `RoleLoadPolicy.availableActions(for: viewModel.role, in: load)` as the single action source. `LoadDetailNoStatusSwitchTests` (1 test) lint-locks zero `switch.*\.status` in `Features/Loads/`. `RoleLoadPolicyAvailableActionsTests` (9 tests) + `LoadActionsViewTests` (18 tests) all green per SUMMARY. |
| 2 | Accepting, rejecting, or advancing a load visibly changes its state and recomputes the available action set; active tender displays respond-by deadline; reject returns load to posted | ✓ VERIFIED | `LoadDetailViewModel` 5-case state machine with `.actionInFlight(predicted:frozenChain:action:)` confirmed in source (`grep -c 'case actionInFlight'` = 1). `LoadActionPredictor.predict(.reject)` → `.rejected` with `respondByAt = nil` confirmed by `LoadActionPredictorTests/test_rejectReturnsToPosted`. `LoadActionsView` renders `respondByLabel` when `role ∈ {.carrier, .dispatch} AND currentStatus == .tendered AND respondByAt != nil` (line 296 area). XCUITest flows `test_carrierCanAcceptActiveTender` + `test_carrierCanRejectActiveTender` passed (171s run). |
| 3 | The tender action is hard-disabled with an inline reason when the target counterparty is not verified | ✓ VERIFIED | Two-gate model confirmed: (1) `LoadActionsView.swift` — `disabledReasonLabel` present + `tenderEligibility.canTender == false` disables Tender button with inline reason. (2) `TenderSheetCarrierRowView.configure(carrier:)` — `isUserInteractionEnabled = false` + `contentView.alpha = 0.6` + `badgeView.alpha = 1.0` (fraud signal preserved) for non-`.verified` carriers. `TenderEligibilityGatingTests` (6 tests) cover both gates. `test_unverifiedCounterpartyHardDisable` XCUITest flow passed. See WARNING re CR-01 below. |
| 4 | A failed action rolls the screen back to its pre-action state and shows an error; in-flight actions are disabled to prevent double-submit and route through the v1.0 idempotency interceptor | ✓ VERIFIED | `LoadDetailViewModel.submit()` confirmed to transition `.loaded → .actionInFlight → .actionFailed(rollbackTo: preLoad, ...)`. `LoadDetailViewModelRollbackTests` (8 tests) pin 4 fault classes (500/422/409/URLError). `LoadActionToastBannerView` wired in `.actionFailed` render arm (`LoadDetailViewController.swift:1214+`). `IdempotencyInterceptor` at `AppContainer.swift:591` confirmed unchanged. `MockLoadActionDispatchTests` (5 tests) assert `Idempotency-Key` header on wire. `test_rollbackOnServerError500` + `test_doubleSubmitPrevented` XCUITest flows passed. See WARNING re CR-01 and CR-02 below. |
| 5 | After a successful action, the load list reflects the new state on pop-back | ✓ VERIFIED | `LoadListViewController.swift:387` — `viewWillAppear → Task { await viewModel.fetchLoads() }` confirmed present. `test_carrierCanAcceptActiveTender` and `test_carrierCanRejectActiveTender` XCUITest flows include pop-back list-refresh assertions. Zero new wiring required — Phase 8 contract intact. |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Purpose | Status | Evidence |
|----------|---------|--------|----------|
| `validationLedger/Core/Load/LoadActionPredictor.swift` | Pure predictor `(Load, LoadAction, RequestBody?) -> Load` | ✓ VERIFIED | Exists (135 lines). `grep -c 'public enum LoadActionPredictor'` = 1 (ignoring comment hit). `body?.respondByAt` hit at line 88 (Pitfall 3). Defensive bottom arm: 1 `default:` arm. |
| `validationLedger/Core/Load/LoadStatus.swift` | `localizedDisplayName` — Pitfall 5 guard | ✓ VERIFIED | `var localizedDisplayName` present. "in transit" string confirmed (no underscore). |
| `validationLedger/Core/Load/Load.swift` | `with(status:respondByAt:)` value-type helper | ✓ VERIFIED | `func with(status` confirmed present. |
| `validationLedger/Core/Load/RoleLoadPolicy.swift` | `availableActions(for:in:)` wrapper | ✓ VERIFIED | `grep -c 'static func availableActions(for'` = 1. |
| `validationLedger/Core/Load/LoadActionTitleResolver.swift` | Pure title resolver | ✓ VERIFIED | `public enum LoadActionTitleResolver` present. |
| `validationLedger/Features/Loads/Detail/LoadActionsView.swift` | Action region UIView (ACTION-01, -04, -07, -09) | ✓ VERIFIED | Exists (461 lines). `public class LoadActionsView: UIView` = 1. |
| `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` | `actionsContainer` at index 2 | ✓ VERIFIED | `actionsContainer` count = 3 (declaration + add + doc). |
| `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` | 5-case state machine + `submit()` + `role` | ✓ VERIFIED | `case actionInFlight` = 1, `case actionFailed` = 1, `public let role: Role` = 2 (declaration + doc). |
| `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` | Render arms + overlay + toast + tender routing | ✓ VERIFIED | `presentToastBanner` wired at `.actionFailed` arm. Chain overlay identifiers present. `case .actionInFlight` = 1, `case .actionFailed` = 1. |
| `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift` | Modal tender sheet (ACTION-01, -04) | ✓ VERIFIED | Exists (625 lines). Three accessibility identifiers wired (carrier-row, deadline-chip, send-button). `isUserInteractionEnabled = false` present (carrier-level gate). |
| `validationLedger/Features/Loads/Detail/TenderSheetCarrierRowView.swift` | Carrier picker row (D-08 visible-but-disabled) | ✓ VERIFIED | Exists (217 lines). `isUserInteractionEnabled = false` × 4, `alpha = 1.0` × 4 (badge signal preserved). |
| `validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift` | Rollback failure toast (D-15) | ✓ VERIFIED | Exists (351 lines). `chain-updating-overlay` identifier in `LoadDetailViewController` = 2. |
| `validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift` | `GET /carriers/directory` typed endpoint | ✓ VERIFIED | Exists. |
| `validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift` | `#if DEBUG` launch-arg toggles | ✓ VERIFIED | Exists. `#if DEBUG` gate at line 44. `public enum DebugActionFailureOverride` = 1. |
| `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` | 7-carrier synthetic fixture | ✓ VERIFIED | Exists. |
| `validationLedger/App/AppContainer.swift` | `makeLoadDetailScreen(loadID:role:)` D-22 | ✓ VERIFIED | `func makeLoadDetailScreen(loadID: String, role: Role)` = 1. Closure capture `self.makeLoadDetailScreen(loadID: loadID, role: role)` = 1. `requestInterceptors: [IdempotencyInterceptor()]` = 1 (unchanged). |
| `validationLedgerUITests/Loads/LoadActionFlowsTests.swift` | 6 XCUITest smoke flows | ✓ VERIFIED | Exists (~768 lines). 6 flows passed on iPhone 17 simulator (171s). |
| `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/` | 76 PNG baselines (65-cell matrix + variants) | ✓ VERIFIED | 76 PNG files confirmed on disk. |
| `validationLedgerTests/__Snapshots__/TenderSheetViewControllerSnapshot/` | 4 PNG baselines | ✓ VERIFIED | 4 PNG files confirmed on disk. |
| `validationLedgerTests/__Snapshots__/LoadActionToastBannerViewSnapshot/` | 6 PNG baselines (one per LOCKED error key) | ✓ VERIFIED | 6 PNG files confirmed on disk. |
| `.planning/phases/10-per-role-tender-accept-reject/10-MANUAL-TESTS.md` | Device-UAT checklist | ✓ VERIFIED | Exists (249 lines). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `LoadDetailViewController.render(state: .loaded)` | `RoleLoadPolicy.availableActions(for:in:)` | `viewModel.role + load` at line 1266 | ✓ WIRED | Single source of truth for action set; no switch on status in Features/Loads/ |
| `LoadDetailViewController.handleActionTap(.tender)` | `TenderSheetViewController` via `presentTenderSheet()` | Calls `viewModel.fetchCarrierDirectory()` then presents sheet | ✓ WIRED | Directory fetch error silently drops (WR-05 WARNING) |
| `TenderSheetViewController.handleSendTap()` | `viewModel.submit(action: .tender, body:)` | `onSend` closure in parent VC captures `viewModel.role` | ✓ WIRED | CR-01 defense-in-depth gap: no re-validation of `carrier.verificationState` in `handleSendTap()` itself — WARNING |
| `LoadDetailViewModel.submit()` | `LoadActionEndpoint` POST | `apiClient.request(LoadActionEndpoint(...))` via AppContainer APIClient | ✓ WIRED | IdempotencyInterceptor auto-injects `Idempotency-Key` header; confirmed by MockLoadActionDispatchTests |
| `LoadDetailViewModel.submit()` → `.actionFailed` | `LoadDetailViewController.presentToastBanner(copyKey:)` | `.actionFailed` render arm at line 1214 | ✓ WIRED | LOCKED per-action key resolved via `defaultEnglishFallback(for:)`; T-09-04 view-layer lock — server text never reaches the screen |
| `MockLoadFixtureRegistry` action-success handler | Returns `actionSuccessPayload` (VL-1004 hardcoded) | All action POSTs against any VL- loadID | WARNING | CR-02: `actionSuccessPayload` always returns `"id": "VL-1004"` load regardless of requested loadID. Demo sessions on VL-1003/VL-1008/VL-1009 swap the screen to VL-1004 data on action success (DEBUG-only but affects TestFlight). |
| `LoadListViewController.viewWillAppear` | `viewModel.fetchLoads()` | Existing Phase 8 pattern at line 387 | ✓ WIRED | ACTION-09 / SC#5 satisfied with zero new code |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `LoadActionsView` | `actions: [LoadAction]` | `RoleLoadPolicy.availableActions(for: viewModel.role, in: load)` in VC render arm | Yes — policy lookup against frozen Phase 7 table | ✓ FLOWING |
| `LoadActionsView` | `tenderEligibility: TenderEligibility?` | `Load.tenderEligibility` from server response | Yes — fixture supplies the gate state | ✓ FLOWING |
| `LoadActionsView` | `respondByAt: Date?` | `Load.respondByAt` from fixture | Yes — `.tendered` fixtures carry respondByAt | ✓ FLOWING |
| `TenderSheetViewController` | `directory: [TrustNode]` | `viewModel.fetchCarrierDirectory()` → `CarrierDirectoryEndpoint` → 7-carrier fixture | Yes — fixture is 7 carriers with all 4 VerificationState cases | ✓ FLOWING |
| `LoadActionToastBannerView` | `text: String` | `NSLocalizedString(errorCopyKey, value: defaultEnglishFallback)` in VC | Yes — LOCKED key table, English fallback | ✓ FLOWING — T-09-04 view-layer lock respected |
| Mock action-success response → `LoadDetailViewModel.state` | `response.load` (post-action) | `actionSuccessPayload` in `MockLoadFixtureRegistry` | No — hardcoded VL-1004 for all loadIDs | WARNING (CR-02) — data flows but is always wrong load |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `LoadActionPredictor.predict(.tender, .posted)` → `.tendered` with `body.respondByAt` | Source grep: `body?.respondByAt` at line 88 | Hit confirmed | ✓ PASS |
| `RoleLoadPolicy.availableActions(for:in:)` drives action bar (not switch) | `grep -rnE 'switch[[:space:]]+[^{]*\.status' validationLedger/Features/Loads/` | 0 hits | ✓ PASS |
| `#if DEBUG` gate on `DebugActionFailureOverride` | File-level `#if DEBUG` at line 44 in MockActionFailureToggles.swift | Confirmed | ✓ PASS |
| `AppContainer` `requestInterceptors: [IdempotencyInterceptor()]` unchanged | `grep -c` = 1 | Confirmed | ✓ PASS |
| TenderSheetCarrierRowView `badgeView.alpha = 1.0` (fraud signal preserved) | `grep -c 'alpha = 1\.0'` = 4 | Confirmed | ✓ PASS |
| Wave 1-7 test counts | 36+15+46+46+21+86+6 = 256 tests documented in phase evidence | All green per SUMMARY wave reports | ✓ PASS |
| `handleSendTap()` re-validates `carrier.verificationState` before calling `onSend` | Source read of `handleSendTap()` body | Guard absent in `handleSendTap()` itself | WARNING (CR-01) |
| Mock action-success returns correct loadID per request | `grep -n '"id": "VL-1004"' MockLoadFixtureRegistry.swift` | Multiple hits; always VL-1004 | WARNING (CR-02) |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| ACTION-01 | Broker/Shipper can tender a load; active tender displays respond-by deadline | ✓ SATISFIED | `TenderSheetViewController` + deadline chips + `respondByLabel` in `LoadActionsView`. `test_brokerCanTenderToVerifiedCarrier` XCUITest passed. |
| ACTION-02 | Broker/Shipper can retender after reject or expired tender | ✓ SATISFIED | `RoleLoadPolicy` returns `[.tender, .cancel]` on `.rejected`/`.expired`. `LoadActionPredictor` handles `.tender` on `.rejected`/`.expired` identically to `.posted`. `test_tender_onRejected_predictsTendered_identicalToPosted` + `test_tender_onExpired_...` unit tests confirmed. |
| ACTION-03 | Carrier/Dispatch can accept a tendered load | ✓ SATISFIED | `RoleLoadPolicy.availableActions(.carrier, .tendered)` includes `.accept`. `LoadDetailViewModel.submit(.accept, ...)` fires `LoadActionEndpoint` POST. `test_carrierCanAcceptActiveTender` XCUITest passed. |
| ACTION-04 | Carrier/Dispatch can reject tendered load — load returns to posted | ✓ SATISFIED | `LoadActionPredictor.predict(.reject, .tendered)` → `.rejected`. Server authoritative per D-04. `test_carrierCanRejectActiveTender` XCUITest passed. |
| ACTION-05 | Carrier/Dispatch can advance status one step | ✓ SATISFIED | `LoadActionTitleResolver` maps `.advanceStatus × .accepted` → "Dispatch" etc. `LoadActionPredictor.predict(.advanceStatus, .accepted)` → `.dispatched`. `LoadDetailViewModelActionTests` cover dispatch. |
| ACTION-06 | Shipper/Broker can post draft load and cancel pre-delivery load | ✓ SATISFIED | `RoleLoadPolicy` returns `.post` on `.draft`, `[.tender, .cancel]` on `.posted`+`.rejected`+`.expired`, `[.cancel]` on `.tendered`+`.accepted`. Action bar renders these per policy. No multi-field creation form (per scope). |
| ACTION-07 | Broker/Shipper cannot tender to unverified counterparty — hard-disabled with inline reason | ✓ SATISFIED | Two-gate model (load-level `tenderEligibility.canTender == false` + carrier-level `TenderSheetCarrierRowView` visible-but-disabled). `TenderEligibilityGatingTests` (6 tests). `test_unverifiedCounterpartyHardDisable` XCUITest. CR-01 WARNING: defense-in-depth gap in `handleSendTap()` does not break the primary gate. |
| ACTION-08 | Load actions use optimistic UI with rollback path | ✓ SATISFIED | `LoadDetailViewModel` `.actionInFlight` → predict; `.actionFailed` → rollback. `LoadActionToastBannerView` on failure. Buttons disabled during in-flight. `LoadDetailViewModelRollbackTests` (8 tests). `test_rollbackOnServerError500` + `test_doubleSubmitPrevented` XCUITest. |
| ACTION-09 | Available actions determined per-role by single `RoleLoadPolicy` table | ✓ SATISFIED | `LoadDetailViewController` calls `RoleLoadPolicy.availableActions(for:in:)` once per `.loaded` render. `LoadDetailNoStatusSwitchTests` lint-locks zero `switch.*\.status`. Factoring role returns `[]` per policy. |

**Requirements coverage: 9/9 ACTION-XX requirements satisfied.**

---

### Anti-Patterns Found

| File | Finding | Severity | Impact |
|------|---------|----------|--------|
| `TenderSheetViewController.swift:553-577` | `handleSendTap()` has NO `carrier.verificationState == .verified` re-check before calling `onSend`. The gate is enforced at the delegate (`didSelectRowAt`) and `computeSendButtonState()`, but not at the actual fire site. Defense-in-depth violation on the platform's T-10-04 invariant. (CR-01 from 10-REVIEW.md) | WARNING | A future programmatic seam or a Voice Control "Tap Send" bypass on a non-verified row could tender to a flagged carrier. Does not break the current user-path but contradicts CLAUDE.md "Identity that cannot be spoofed" posture. Not a phase blocker because the primary gate (button disabled) functions correctly; flagged for pre-App-Store fix. |
| `MockLoadFixtureRegistry.swift:244-261,4743-4809` | `actionSuccessPayload` is a hardcoded `"id": "VL-1004"` Load + chain for EVERY action POST against EVERY VL- loadID. VM writes `state = .loaded(response.load, response.chainOfTrust)` — so any action on VL-1003/VL-1008/VL-1009 transitions the detail screen to VL-1004 data. File is `#if DEBUG` only, but TestFlight builds include DEBUG config. (CR-02 from 10-REVIEW.md) | WARNING | Demo and UAT sessions on fraud-archetype loads (VL-1009 multi-broker, VL-1008 unverified carrier) produce visually wrong post-action screens. Undermines the platform-thesis demo flow. Non-blocking for phase verification (DEBUG-only), but should be fixed before any broker/customer demo. |
| `MockActionFailureToggles.swift:83-103` | `public static var …Active: () -> Bool` closures are mutable globals with no isolation — data race surface on URLSession worker threads under Swift 6 strict concurrency. (WR-01 from 10-REVIEW.md) | WARNING (code quality) | DEBUG-only. Tests serialize via XCTest default ordering; practical risk is low. Not a phase blocker but should be fixed before Swift 6 migration. |
| `MockLoadFixtureRegistry.swift:239` | `Thread.sleep(forTimeInterval: 1.5)` inside MockURLProtocol handler blocks URLSession worker thread. (WR-02 from 10-REVIEW.md) | WARNING (code quality) | DEBUG-only. Human-UAT use case (one tap at a time) is low risk. Test suite uses isolation. Not a phase blocker. |
| `LoadDetailViewController.swift:1711-1724` | `presentTenderSheet()` catch arm is silent — no toast on directory-fetch failure. User tap is silently dropped. (WR-05 from 10-REVIEW.md) | WARNING | Rare failure path (static mock fixture always succeeds in DEBUG). UX gap: user gets no feedback that the Tender tap was heard but the directory load failed. Non-blocking for v1.1. |

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 10 modified source file. Debt marker gate: PASS.

---

### Human Verification Required

1. **Toast Banner Animation Feel**

   **Test:** Install a DEBUG build on physical device. Set `-MockActionServerError500` + `-MockActionLatencySlow` in Xcode scheme arguments. Open a tendered load as carrier. Tap Accept.
   **Expected:** Optimistic state advances immediately. After ~1.5s, rollback fires: load returns to tendered, medium-impact haptic fires, toast banner slides down from top ("Couldn't accept this tender. Try again."), dwells ~3.5s, fades. Swipe-up dismisses it early.
   **Why human:** Animation timing, haptic feel, and auto-dismiss behavior are subjective and not assertable by XCTest. XCUITest test_rollbackOnServerError500 soft-asserts only (3.5s window too narrow for deterministic XCUI capture).

2. **Tender Sheet .medium Detent Ergonomics on Real Device**

   **Test:** On iPhone (ideally iPhone SE-class for worst-case reach test), open a posted load as broker. Tap Tender. Sheet presents at .medium detent.
   **Expected:** Sheet occupies lower ~50% of screen. Carrier list rows and deadline chips are reachable with the thumb without repositioning grip. Custom date picker opens cleanly inline. Send button is within reach.
   **Why human:** UISheetPresentationController detent ergonomics and one-handed reach are physical properties not verifiable on simulator.

3. **65-Cell Snapshot Matrix Legibility at Default + Large Dynamic Type**

   **Test:** Open `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/` and spot-check at least 5 rows (one per role) — confirm text is readable, destructive tint is visually distinct on Cancel/Reject buttons, respond-by label appears for carrier/dispatch × .tendered cells, empty-state captions read naturally.
   **Expected:** No button text truncated to the point of ambiguity. "Cancel load" and "Reject" use destructive tint. Factoring cell shows "This is a view-only role. No actions available." Pitfall 5 cell shows "This load is in transit. No actions available." (no underscore).
   **Why human:** PNG baselines confirm layout exists; readability and tint judgment require human review of the rendered images.

4. **DEBUG Launch-Arg Failure Toggles on Real Device**

   **Test:** Exercise each of the four toggles individually via Xcode scheme: `-MockActionConflict409`, `-MockActionValidation422`, `-MockActionServerError500` (with `-MockActionLatencySlow` to make in-flight state visible). Confirm rollback + toast for each failure class.
   **Expected:** Each toggle fires the correct HTTP error, rollback returns the screen to pre-tap state, toast copy matches the failing action ("Couldn't send tender", "Couldn't accept", etc.). Combined latency + error toggle shows optimistic in-flight state, then rolls back.
   **Why human:** `Thread.sleep` latency on the mock handler makes in-flight state only perceptible to a human watching real hardware. Haptic feedback is device-only.

5. **End-to-End Broker Tender → Carrier Accept Pop-Back Flow**

   **Test:** As described in `10-MANUAL-TESTS.md`. Use two scheme configurations (broker role, carrier role). Broker tenders VL-1003 (posted) to Acme Logistics with 1-day deadline. Carrier accepts. Pop back to list.
   **Expected:** Load row shows "Accepted" badge after carrier pop-back. Broker's view of the same load (re-open from list) shows accepted state. No load-switching to VL-1004 (if this happens, CR-02 has manifested — file the note).
   **Why human:** Multi-role happy-path flow requires exercising two role contexts sequentially. Covers ACTION-01 through ACTION-03 plus ACTION-09 list-refresh as a single observed interaction.

---

### Gaps Summary

No blocking gaps. All 5 success criteria are met at the automated-verification level.

Two WARNING-grade code review findings (CR-01, CR-02) require human attention before the App Store submission milestone but do not block this phase:

- **CR-01** (defense-in-depth gap in `handleSendTap`): The primary ACTION-07 gate functions correctly via button disable + delegate guard. The missing re-validation in `handleSendTap()` itself is a defense-in-depth gap. The recommended fix is one `guard carrier.verificationState == .verified else { updateSendButton(); return }` at the top of `handleSendTap()`. Recommend fixing in a follow-up before the next phase that touches `TenderSheetViewController`.

- **CR-02** (mock action-success returns hardcoded VL-1004): The VM's `state = .loaded(response.load, response.chainOfTrust)` assignment is correct; the fixture is wrong. Fix by synthesizing the response from the per-VL detail fixture keyed on the requested loadID, or at minimum adding a banner comment flagging the limitation. Recommend fixing before any broker/customer demo session.

The pre-existing `AppContainerLoadEndpointsConfigSwapTests` failures are documented in `deferred-items.md` as Phase 7-06 suite-order pollution, not Phase 10 regressions.

---

_Verified: 2026-05-21_
_Verifier: Claude (gsd-verifier)_
