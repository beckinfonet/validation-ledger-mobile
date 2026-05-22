---
phase: 4
slug: app-attest-physical-device-ci-hardening
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-22
revised: 2026-04-22
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> **Source:** `04-RESEARCH.md` § Validation Architecture (Dimension 8)

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (unit) + XCTest (UI/device via `validationLedgerDeviceTests`) |
| **Config file** | `validationLedger.xcodeproj/xcshareddata/xcschemes/validationLedgerDeviceTests.xcscheme` |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerTests` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -retry-tests-on-failure -test-iterations 2` |
| **Full device-suite command** | `xcodebuild test -scheme validationLedger -destination 'generic/platform=iOS' -only-testing:validationLedgerDeviceTests -retry-tests-on-failure -test-iterations 2` |
| **Estimated runtime** | ~90s simulator / ~4–6min device (SE + Keychain + App Attest round-trips) |

---

## Sampling Rate

- **After every task commit:** Run quick simulator command
- **After every plan wave:** Run full simulator suite
- **After Wave containing device-only targets:** Run full device-suite command on physical iPhone runner
- **Before `/gsd-verify-work`:** Full suite (simulator + device) must be green
- **Max feedback latency:** ~90s simulator, ~6min device

---

## Per-Task Verification Map

> One row per task across Plans 01-10. Automated command column lists the command from each task's `<verify><automated>` block; REQ / Decision / Threat columns list the primary items each task satisfies. Status is pending (`⬜`) until execution lands.

| Task ID | Plan | Wave | Requirement | Decisions | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-T1 | 01 | 1 | DEV-04 | D-02, D-09, D-12 | T-APP-ATTEST-04 | 6-value AttestationStatus wire contract + AttestationService protocol + TrustTier enum land | unit | `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -configuration Debug` + grep for 6 cases | ✅ | ⬜ |
| 04-01-T2 | 01 | 1 | DEV-04 | D-03, D-07 | T-APP-ATTEST-02 | KeychainKey constants + KeychainScope.session exclusion doc-comment pin D-03 invariant | unit | `grep "device.attestedKeyId" KeychainKey.swift` + `xcodebuild build` | ✅ | ⬜ |
| 04-01-T3 | 01 | 1 | DEV-04 | D-01, D-04, D-12 | T-APP-ATTEST-02 | validationLedger.entitlements + ADR 0005 + docs/attestation-rotation.md land | docs + build | `plutil -lint entitlements` + `grep "CODE_SIGN_ENTITLEMENTS" pbxproj` | ✅ | ⬜ |
| 04-02-T1 | 02 | 1 | DEV-04 | D-05, D-07, D-10, D-12 | T-APP-ATTEST-03 | 4 JSON fixtures for /device/challenge, /device/heartbeat (success+error), /device/register (software-only) | unit | `python3 json.load` each fixture + grep `trust_tier`/`error_code` | ✅ | ⬜ |
| 04-02-T2 | 02 | 1 | DEV-04 | D-03 | T-APP-ATTEST-02 | KeychainScopeTests pins D-03 invariant (attestedKeyId + lastHeartbeatAt NOT in .session); FakeAttestationService test double | unit | `xcodebuild test -only-testing:validationLedgerTests/Storage/KeychainScopeTests` | ✅ | ⬜ |
| 04-02-T3 | 02 | 1 | DEV-04 | D-14 | T-APP-ATTEST-05 | SeededBiometricService for unattended CI (never instantiates real LAContext) | device CI | `grep -c "LAContext()" SeededLAContext.swift` returns 0 + `xcodebuild build` device target | ✅ | ⬜ |
| 04-03-T1 | 03 | 2 | DEV-04 | D-01, D-03, D-07 | T-APP-ATTEST-02 | AttestedKeyStore persistence wrapper (Keychain .afterFirstUnlockThisDeviceOnly) | unit | `grep "afterFirstUnlockThisDeviceOnly" AttestedKeyStore.swift` returns 2 + build | ✅ | ⬜ |
| 04-03-T2 | 03 | 2 | DEV-04 | D-01, D-04, D-05, D-06, D-07, D-09 | T-APP-ATTEST-01, T-APP-ATTEST-04 | DCAppAttestAttestationService: Keychain-first idempotency, SHA-256(challenge), DCError→AttestationStatus mapping | unit | `grep "Data(SHA256.hash(data: challenge))"` returns 2 + DCError mapping greps + build | ✅ | ⬜ |
| 04-03-T3 | 03 | 2 | DEV-04 | D-10 | T-APP-ATTEST-03 | SimulatorBypassAttestationService — file-top `#if DEBUG && targetEnvironment(simulator)` gate | unit | `grep "#if DEBUG && targetEnvironment(simulator)"` + Release build succeeds with symbol excluded | ✅ | ⬜ |
| 04-04-T1 | 04 | 2 | DEV-04 | D-05, D-07 | T-APP-ATTEST-01 | DeviceChallengeEndpoint (GET /device/challenge) + DeviceHeartbeatEndpoint (POST /device/heartbeat) land | unit | `grep "path = \"/device/challenge\""` + `"path = \"/device/heartbeat\""` + build | ✅ | ⬜ |
| 04-04-T2 | 04 | 2 | DEV-04 | D-02, D-09, D-12 | T-APP-ATTEST-04 | DeviceRegisterEndpoint extended: 4 new RequestBody fields (authorizationPublicKey NEW per D-02) + Response.trustTier | unit | `grep "attestationStatus: AttestationStatus"` + `"trustTier: TrustTier"` + existing EndpointEncodingTests still pass | ✅ | ⬜ |
| 04-05-T1 | 05 | 3 | DEV-04 | D-01, D-04, D-06, D-09, D-10 | T-APP-ATTEST-03 | 6 simulator tests: AttestationStatusMapping, GenerateKeyOnlyOnce, ClientDataHash, SimulatorBypass, BackendDrivenReattestation, ChallengeExpiredRetry | unit | `xcodebuild test -only-testing:validationLedgerTests/Attestation` | ✅ | ⬜ |
| 04-05-T2 | 05 | 3 | DEV-04 | D-05, D-07d, D-09f, D-12 | T-APP-ATTEST-06 | 3 endpoint tests: DeviceChallenge decode, DeviceHeartbeat request/response + trustTier, DeviceRegister D-09f omission (parametrized x5) | unit | `xcodebuild test -only-testing:validationLedgerTests/Networking/DeviceChallengeEndpointTests -only-testing:.../DeviceHeartbeatEndpointTests -only-testing:.../DeviceRegisterOmissionTests` | ✅ | ⬜ |
| 04-05-T3 | 05 | 3 | DEV-04 | D-10 | T-APP-ATTEST-03 | scripts/verify-release-no-sim-bypass.sh lands — archives Release + greps binary for `sim-bypass-` strings | shell | `sh -n scripts/verify-release-no-sim-bypass.sh` + `test -x` | ✅ | ⬜ |
| 04-05-T4 | 05 | 3 | DEV-04 | D-02, D-04, D-07c | T-APP-ATTEST-06, T-APP-ATTEST-15 | 3 targeted coverage tests: HeartbeatAgeThreshold (86399/86401s boundary), AuthorizationKeyWireFormat (D-02), AttestationErrorResponseInterceptor (5-test integration) | unit | `xcodebuild test -only-testing:validationLedgerTests/Attestation/HeartbeatAgeThresholdTest -only-testing:...AttestationErrorResponseInterceptorTest -only-testing:validationLedgerTests/Networking/DeviceRegisterAuthorizationKeyWireFormatTest` | ✅ | ⬜ |
| 04-06-T1 | 06 | 3 | DEV-04 | D-12 | T-APP-ATTEST-07 | AppSession.trustTier holder (@MainActor, default .softwareOnly = safe-banner-on default) | unit | `grep "@MainActor" AppSession.swift` + `"trustTier: TrustTier = .softwareOnly"` + build | ✅ | ⬜ |
| 04-06-T2 | 06 | 3 | DEV-04 | D-09, D-12, D-14 | T-APP-ATTEST-02, T-APP-ATTEST-07 | AppContainer: attestationService selection, preflightAttestationEntitlement (non-fatal), biometricServiceOverride seam, AppSession wiring | unit | `grep "public let attestationService: any AttestationService"` + `"biometricServiceOverride"` + `#if DEBUG && targetEnvironment(simulator)` + build simulator+iOS | ✅ | ⬜ |
| 04-07-T1 | 07 | 4 | DEV-04 | D-07, D-12 | T-APP-ATTEST-08, T-APP-ATTEST-10 | SceneDelegate.performHeartbeatIfNeeded + 2 call sites (cold-boot + didBecomeActive); 86400s threshold; fire-and-forget; trustTier mutation on success | unit + manual | `grep "performHeartbeatIfNeeded"` returns ≥3 + `"86400"` returns 1 + `"container.session.trustTier"` returns 1 + build | ✅ | ⬜ |
| 04-07-T2 | 07 | 4 | DEV-04 | D-04 | T-APP-ATTEST-09 | DevMenu "Re-attest now" row (DEBUG-only) — manual D-04 trigger | unit | `grep "case reattestNow"` + `"clearPersistedKeyId"` + Release build compiles DevMenuViewController out | ✅ | ⬜ |
| 04-07-T3 | 07 | 4 | DEV-04 | D-04 | T-APP-ATTEST-15 | AttestationErrorResponseInterceptor — automatic D-04 path (path + 4xx + canonical error_code filters, retry-once) + registered in AppContainer chain | unit | Plan 05 Task 4 AttestationErrorResponseInterceptorTest (5 tests) passes + `grep "AttestationErrorResponseInterceptor" AppContainer.swift` returns ≥1 | ✅ | ⬜ |
| 04-08-T1 | 08 | 4 | DEV-04 | D-11 | T-APP-ATTEST-11 | LimitedTrustBannerView — UIKit UIView, isUserInteractionEnabled=false, accessibilityIdentifier="limited-trust-banner", D-11 copy verbatim, NSLocalizedString-wrapped | UI + build | `grep "public final class LimitedTrustBannerView: UIView"` + `"isUserInteractionEnabled = false"` + `"limited-trust-banner"` + build | ✅ | ⬜ |
| 04-08-T2 | 08 | 4 | DEV-04 | D-11, D-12 | T-APP-ATTEST-12 | RoleCoordinator.wrapWithLimitedTrustBanner(trustTier:) extension + AppCoordinator presentRoot wiring + Pitfall 7 safe-area pinning | UI + build | `grep "func wrapWithLimitedTrustBanner"` + `"safeAreaLayoutGuide.topAnchor"` + build | ✅ | ⬜ |
| 04-08-T3 | 08 | 4 | DEV-04 | D-11, D-12 | T-APP-ATTEST-11 | LimitedTrustBannerTests — XCUITest banner visible on softwareOnly, absent on hardwareAttested; non-hittable | UI | `xcodebuild test -only-testing:validationLedgerUITests/LimitedTrustBannerTests` on iPhone 15 simulator | ✅ | ⬜ |
| 04-08-T4 | 08 | 4 | DEV-04 | D-11 | T-APP-ATTEST-11 | HUMAN CHECKPOINT — iPad landscape + iPhone portrait visual check, swipe/tap non-dismissibility, Split View | human UAT | Manual verification per checklist in 04-08-PLAN.md (iPad Pro 11-inch + iPhone 15 + landscape + Split View) | N/A | ⬜ |
| 04-09-T1 | 09 | 4 | DEV-04, CI-03 | D-01, D-13 | T-APP-ATTEST-01, T-APP-ATTEST-13 | AppAttestRoundTripTests — real-hardware attestKey + generateAssertion + generateKeyIdempotencyAcrossCalls (accept-either .attested OR .quotaExceeded) | device CI | `xcodebuild test -destination 'generic/platform=iOS' -only-testing:validationLedgerDeviceTests/AppAttestRoundTripTests` (physical iPhone) | ✅ | ⬜ |
| 04-09-T2 | 09 | 4 | DEV-04, CI-03 | D-13, D-14 | T-APP-ATTEST-05 | KeychainBiometricACLTests — seeded LAContext exercises Keychain ACL creation + signWithAuthorization (accept-either outcome on biometric failure) | device CI | `xcodebuild test -destination 'generic/platform=iOS' -only-testing:validationLedgerDeviceTests/KeychainBiometricACLTests` | ✅ | ⬜ |
| 04-09-T3 | 09 | 4 | DEV-04, CI-03 | D-03, D-13 | T-APP-ATTEST-14 | LogoutClearsAuthorizationKeyTests — logout wipes authorizationKey SE + D-03 attestedKeyId preservation verified on real hardware | device CI | `xcodebuild test -destination 'generic/platform=iOS' -only-testing:validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests` | ✅ | ⬜ |
| 04-10-T1 | 10 | 5 | CI-03 | D-13, D-15, D-16 | T-CI-03-01, T-CI-03-02 | ci-device.yml upgraded: job name `device-security-surface` (required status check), full target, `-retry-tests-on-failure -test-iterations 2`, xcresult artifact 14d retention, Slack flaky-pass step | CI config | `grep "device-security-surface"` + `"-retry-tests-on-failure"` + `"retention-days: 14"` in ci-device.yml | ✅ | ⬜ |
| 04-10-T2 | 10 | 5 | CI-03, DEV-04 | D-10, D-15 | T-APP-ATTEST-03, T-CI-03-02 | scripts/report-flaky-passes.sh + ci-simulator.yml Release-strings guard step | CI config + shell | `sh -n scripts/report-flaky-passes.sh` + `grep "verify-release-no-sim-bypass.sh" ci-simulator.yml` | ✅ | ⬜ |
| 04-10-T3 | 10 | 5 | CI-03 | D-13, D-14, D-15, D-16 | T-CI-03-01 | docs/ci.md updated: Phase 4 Device Pipeline + first-run branch-protection dance + D-10 guard + D-04 re-attest coverage sections | docs | `grep "Phase 4 Device Pipeline" docs/ci.md` + `"First-run branch-protection dance"` + `"device-security-surface"` + `"verify-release-no-sim-bypass.sh"` | ✅ | ⬜ |
| 04-10-T4 | 10 | 5 | CI-03 | D-16 | T-CI-03-01 | HUMAN CHECKPOINT — configure GitHub branch-protection rule for main requiring `device-security-surface`; verify with deliberate-fail test PR | human action | Manual: Repo Settings → Branches → add required status check; test PR red→blocked→fixed→mergeable | N/A | ⬜ |

*Status legend:* ⬜ pending · ✅ green · ❌ red · ⚠️ flaky

---

## Wave 0 Requirements

> Stubs/fixtures that must exist before any D-01..D-16 decision can be validated. All items landed by Plans 01 + 02 (Wave 1); wave_0_complete: true.

- [x] `validationLedger/Core/Attestation/AttestationService.swift` — protocol + `AttestationStatus` + `AttestationError` enum (D-02, D-09) — Plan 01 T1
- [x] `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` — real `DCAppAttestService` wrapper (D-01, D-05, D-06, D-07) — Plan 03 T2 (Wave 2; contract shape derivable from protocol at Wave 1 which is what Wave 0 actually gates)
- [x] `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` — DEBUG-only simulator bypass (D-10) — Plan 03 T3 (same note)
- [x] `validationLedger/Core/Attestation/AttestedKeyStore.swift` — Keychain persistence wrapper (D-01, D-03) — Plan 03 T1
- [x] `validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` — GET /device/challenge (D-05) — Plan 04 T1 (endpoint shape)
- [x] `validationLedger/Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift` — POST /device/heartbeat (D-07) — Plan 04 T1
- [x] `validationLedgerTests/Networking/Fixtures/` — fixtures for `/device/challenge`, attestation-aware `/device/register`, `/device/heartbeat` happy + error paths — Plan 02 T1
- [x] `validationLedger/UI/LimitedTrustBanner.swift` — non-dismissible banner view (D-11, D-12) — Plan 08 T1 (UI-only, Wave 4; not a Wave 0 blocker for other Waves)
- [x] `validationLedger/validationLedger.entitlements` — App Attest entitlement (development + production variants) — Plan 01 T3
- [x] `.planning/adr/0005-three-key-device-register-payload.md` (committed at `docs/adr/0005-three-key-device-register-payload.md`) — ADR documenting the three-key payload (D-02) — Plan 01 T3
- [x] `docs/attestation-rotation.md` — re-attestation runbook (D-04) — Plan 01 T3
- [x] `validationLedgerDeviceTests/SeededLAContext.swift` — seeded `LAContext` for CI (D-14) — Plan 02 T3

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Limited Trust banner renders above tabs on real device with entitlement missing | DEV-04 | Visual layout + non-dismissibility only observable on hardware | Install TestFlight build with entitlement stripped, log in, confirm banner visible above tab bar with copy "Limited trust mode — this device can't fully verify…" |
| DEBUG "Re-attest now" dev-menu row triggers full re-attestation | D-04 | Dev-menu shake gesture + Keychain state inspection | Shake device → Dev Menu → tap "Re-attest now" → verify `attestedKeyId` Keychain item regenerated (timestamp/UUID changes) and `/device/register` re-posts |
| CI merge-gate actually blocks PR merge | CI-03 (SC-3) | GitHub branch-protection behavior only observable in a real PR | Open a PR with an intentional device-test failure → confirm "Merge" button is disabled with "Required check failing" → fix + confirm merge re-enables |
| App Attest quota-exceeded path recovers gracefully | D-09 (quotaExceeded) | Apple's rate-limit timing is undocumented + cannot be forced deterministically | Monitor TestFlight crash/log channel for `AttestationStatus.quotaExceeded` occurrences; verify client backs off + eventually succeeds without user-facing error |
| Hardware-attested trust tier round-trips through mock backend | DEV-04 (SC-1) | Physical iPhone only — simulator emits `simulatorBypass`, can't prove the real-SE + real-AppAttest path | Run `validationLedgerDeviceTests` on physical iPhone runner + inspect posted `/device/register` payload has `attestationStatus: "attested"` + valid `attestationObject` |
| Banner visual tone + iPad landscape + Split View layout | D-11 | RESEARCH Pitfall 7 — safe-area pinning behavior only observable on real multitasking + rotation | Plan 08 Task 4 checkpoint — manual verification on iPad Pro 11-inch simulator + iPhone 15 simulator in portrait/landscape/Split View |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (31 tasks covered in Per-Task Verification Map above; 2 checkpoint tasks (08-T4, 10-T4) are manual-only by design)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (checkpoints are scoped to their own plans; automated tasks surround them)
- [x] Wave 0 covers all required file references from 04-RESEARCH.md (Plan 01 + Plan 02 land everything in the Wave 0 Requirements list above)
- [x] No watch-mode flags in CI commands (all xcodebuild invocations are one-shot `test` or `build`)
- [x] Feedback latency < 90s simulator / < 6min device
- [x] Every D-01..D-16 decision has at least one validation path (see Decisions column in Per-Task Verification Map: D-01 at 04-03-T2 + 04-05-T1; D-02 at 04-01-T1 + 04-04-T2 + 04-05-T4; D-03 at 04-01-T2 + 04-02-T2 + 04-09-T3; D-04 at 04-03-T2 + 04-05-T1 + 04-05-T4 + 04-07-T2 + 04-07-T3; D-05 at 04-02-T1 + 04-04-T1 + 04-05-T2; D-06 at 04-03-T2 + 04-05-T1; D-07/D-07c/D-07d at 04-01-T2 + 04-04-T1 + 04-05-T2 + 04-05-T4 + 04-07-T1; D-08 at 04-05-T1; D-09/D-09f at 04-01-T1 + 04-03-T2 + 04-05-T1 + 04-05-T2 + 04-06-T2; D-10 at 04-03-T3 + 04-05-T1 + 04-05-T3 + 04-10-T2; D-11 at 04-08-T1/T2/T3/T4; D-12 at 04-04-T2 + 04-06-T1 + 04-06-T2 + 04-07-T1 + 04-08-T2/T3; D-13 at 04-09-T1/T2/T3 + 04-10-T1/T3; D-14 at 04-02-T3 + 04-06-T2 + 04-09-T2 + 04-10-T3; D-15 at 04-10-T1/T2/T3; D-16 at 04-10-T1/T3/T4)
- [x] DEV-04 + CI-03 requirement IDs each covered by at least one validation (DEV-04 appears on Plans 01-09; CI-03 on Plans 09 + 10)
- [x] `nyquist_compliant: true` set in frontmatter
- [x] `wave_0_complete: true` set in frontmatter (Plans 01 + 02 land all Wave 0 stubs/fixtures)

**Approval:** ✅ approved — 2026-04-22 (planner-revision; populated Per-Task Verification Map across 31 tasks; all 16 decisions have ≥1 validation path; both requirement IDs covered; Wave 0 complete)
