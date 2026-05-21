---
phase: 10
slug: per-role-tender-accept-reject
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-21
---

# Phase 10 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time (all 10 PLAN files carry a `<threat_model>` block).
> Audit mode: verify mitigations exist — no new-threat scan.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| caller (VM) → `LoadActionPredictor` | Predictor trusts that `RoleLoadPolicy.actions(for:status:)` was checked at the call site; an out-of-policy `(action, status)` is a caller contract bug — defensive no-op contains blast radius. | `(LoadAction, Load)` value types |
| VC → VM | VC invokes `viewModel.submit(action:body:)` / reads `viewModel.role`; trusts the VM state machine for predict / 200 / error transitions. | action requests, OTP-verified `Role` |
| VM → network | VM dispatches via `apiClient.request(LoadActionEndpoint(...))`; trusts `IdempotencyInterceptor` to auto-inject the `Idempotency-Key` header. | POST mutation, idempotency key |
| `AppContainer.role` → VM.role | `role` is set at the composition root from the OTP-verified session; stored as `public let`, NOT client-changeable mid-screen (D-23). | session role |
| sheet → parent VC (`onSend`) | Sheet collects only `(targetPartyID, respondByAt)`; parent composes the full request with `actorRole: viewModel.role`. | tender target + deadline |
| user → action button / carrier row | Disabled buttons/rows must not silently submit; gate state carries an inline reason + accessibility hint. | tap intent |
| client → mock network | Mock returns server-shape data; client decoder fails closed on contract drift. | decoded `Load` / carrier directory |
| QA → DEBUG launch arguments | DEBUG flags forbidden in Release; `#if DEBUG` end-to-end gate compiles the toggle enum to zero bytes in Release. | failure-injection toggles |
| baseline PNG → CI snapshot artifact | Baselines must contain no real party/carrier names — synthetic fixtures only. | snapshot images |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-10-04 (CRITICAL) | Elevation of Privilege | Tender to unverified counterparty | mitigate | Three gates: (a) load-level Tender button disabled on `canTender == false` — `LoadActionsView.swift:508-536`; (b) carrier-picker non-`.verified` rows non-selectable + Send-button `verificationState == .verified` gate — `TenderSheetCarrierRowView.swift:156-194`, `TenderSheetViewController.swift:555-581`; (c) CR-01 fire-site re-validation in `handleSendTap()` — `TenderSheetViewController.swift:603`. | closed |
| T-10-08 (CRITICAL) | Tampering | Replayed POST mutates state twice (idempotency) | mitigate | `IdempotencyInterceptor()` registered in `apiClient.requestInterceptors` — `AppContainer.swift:591`; injects fresh `UUID().uuidString` per POST/PUT — `IdempotencyInterceptor.swift:21-26`; UI guard disables all action buttons while in-flight — `LoadActionsView.swift:476`. Wire-level: `IdempotencyInterceptorRegistrationTests` + `MockLoadActionDispatchTests`. | closed |
| T-10-01 | Elevation of Privilege | Wrong action set shown for role×status (UI gate bypass) | mitigate | `RoleLoadPolicy.availableActions(for:in:)` single source — `RoleLoadPolicy.swift:160`; `LoadActionsView` consumes `actions[]` verbatim, never branches on `load.status`; `LoadDetailNoStatusSwitchTests` lint guard. | closed |
| T-10-02 | Tampering | State mutation without server confirmation | mitigate | Forward-only predict; 200 swaps to `response.load + chainOfTrust` — `LoadDetailViewModel.swift:526-530`; error rollback to captured `(rollbackTo, frozenChain)` — `:500-504`; WR-06 rollback uses `lastConfirmedLoad` from server response — `:415-425, 526`. | closed |
| T-10-05 | Tampering | State desync after rollback (stale failure overwrites fresher state) | mitigate | `if Task.isCancelled { return }` before `.actionFailed` write — `LoadDetailViewModel.swift:489`; second checkpoint before terminal `.loaded` write — `:515`. | closed |
| T-10-09 | Tampering | Stale list state on pop-back | mitigate | `viewWillAppear` triggers `Task { await viewModel.fetchLoads() }` — `LoadListViewController.swift:385-388`; `LoadActionFlowsTests` Test 2 pops back and asserts the row badge. | closed |
| T-09-04 (extended) | Information Disclosure | Server error text leaking into UI / logs | mitigate | `errorCopyKey(for:)` exhaustive 6-case switch → LOCKED localization keys, no `default:` — `LoadDetailViewModel.swift:568-576`; server body never reaches `state.actionFailed`; logger calls use `fields: [:]` — `:303, 319, 496, 521`; toast resolves key via `NSLocalizedString` — `LoadDetailViewController.swift:1682-1687`. | closed |
| T-10-PR-predictor | Tampering | `LoadActionPredictor` mutates input / new `LoadStatus` case misses an arm | mitigate | Pure value-semantic `enum` namespace; purity test `LoadActionPredictorTests.swift:244`; defensive no-op test `:263`. Compile-time `LoadStatus` exhaustiveness lives in `LoadActionTitleResolver.nextStatus(from:)` (no `default:`) — `LoadActionTitleResolver.swift:56-77`. See Note 1. | closed |
| T-10-PR-pitfalls | Tampering | Overlay double-mount, mock-registry handler shadowing, DEBUG flags leaking into Release | mitigate | Single `chainOverlay: UIView?` ref + idempotent `mountChainOverlayIfNeeded` — `LoadDetailViewController.swift:192, 1475-1476`; mock exact-match `path == "/carriers/directory"` — `MockLoadFixtureRegistry.swift:307`; `#if DEBUG` end-to-end gate on `DebugActionFailureOverride` + all 4 handler registrations — `:78, 113-125, 181-259`. | closed |
| T-10-PR-fixtures | Information Disclosure | Test fixtures / snapshot baselines leaking real-world PII | accept | Synthetic carrier/party names only; `CarrierDirectoryDecodeTests` Test 5 asserts synthetic discipline — `CarrierDirectoryDecodeTests.swift:79-88`. See Accepted Risks Log. | closed |
| T-10-PR-SC | Tampering | Package legitimacy on new installs | accept | Phase 10 installs zero new packages; `project.pbxproj` has 0 remote package references, no `Package.resolved`. See Accepted Risks Log. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-10-01 | T-10-PR-fixtures | Phase 10 fixtures and snapshot baselines use synthetic carrier/party names exclusively — no real-world brand names. Same lock as the CLAUDE.md zero-PII rule / Phase 8 T-08-04. Verified by `CarrierDirectoryDecodeTests` Test 5 (`CarrierDirectoryDecodeTests.swift:79`); Plan 09 snapshot baselines inherit the discipline (`10-09-SUMMARY.md` Threat Flags: None). | gsd-security-auditor | 2026-05-21 |
| AR-10-02 | T-10-PR-SC | Phase 10 introduces no new SPM/CocoaPods/Carthage dependencies — no new supply-chain attack surface. `project.pbxproj` contains 0 remote package references; no `Package.resolved` exists; no dependency-config commit in `git log` for `*.pbxproj`. | gsd-security-auditor | 2026-05-21 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-21 | 11 | 11 | 0 | gsd-security-auditor (ASVS L1, block-on critical+high) |

---

## Notes

**Note 1 — T-10-PR-predictor documentation imprecision (not a gap).** The plan-time register text states the predictor uses an "exhaustive nested switch with no top-level default (compile-time exhaustiveness)." The actual `LoadActionPredictor.predict` is a flat tuple switch over `(action, current.status)` that carries a bottom `default:` arm (`LoadActionPredictor.swift:128`) as an intentional defensive no-op for policy-illegal combinations. A tuple switch with a reachable `default:` does not produce a Swift compile-time error when a new `LoadStatus` case is added — such a case falls silently into `default`. The compile-time-exhaustiveness guarantee actually lives in `LoadActionTitleResolver.nextStatus(from:)` (no `default:` arm — `LoadActionTitleResolver.swift:56-77`). The predictor's real mitigations — value-semantic purity and the defensive no-op — are present and regression-tested. Wording inaccuracy in the register, not an absent mitigation. The next plan author should not rely on the predictor's `default:`-bearing switch for new-case detection.

**Note 2 — T-10-08 line reference.** The register and Plan 03 trust-boundary cite the `IdempotencyInterceptor` registration at "AppContainer.swift:572"; the actual registration is at `AppContainer.swift:591`. The registration is unambiguously present and asserted by `IdempotencyInterceptorRegistrationTests` — the stale line number is cosmetic.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-21
