---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
verified: 2026-05-18T22:30:00Z
status: human_needed
score: 9/9
overrides_applied: 0
human_verification:
  - test: "LimitedTrustBannerContainerViewController re-render on mid-session trustTier mutation"
    expected: "When AppSession.trustTier changes at runtime (e.g. heartbeat downgrades from .hardwareAttested to .softwareOnly), the LimitedTrustBanner appears/disappears in place with no animation and no root-swap."
    why_human: "The NotificationCenter observer and LimitedTrustBannerContainerViewController.update(trustTier:) are unit-tested for the call path, but the visual in-place toggle and the no-animation contract require a running app on a device. Cannot be confirmed by grep or simulator unit tests."
  - test: "Profile-entry KYC status 'Continue' CTA pop/dismiss behavior"
    expected: "Tapping Continue from the KYC status screen reached via Profile tab pops the screen (navigation push path) or dismisses it (modal path) — the user lands back on the Profile tab, NOT on the role-shell root swap."
    why_human: "The onVerified closure wiring is code-verified (AppContainer.makeKYCStatusScreen wraps the VC weakly and calls popViewController or dismiss). The correct UIKit behavior on a physical device/simulator with the full Profile navigation stack requires hands-on confirmation."
  - test: "Banner physical-device UAT (carried from Phase 4)"
    expected: "The 5 open Phase 4 LimitedTrustBanner device-UAT items (iPhone landscape, gesture non-dismiss, iPad portrait/landscape/SplitView, yellow-tone legibility) pass on device. See 04-HUMAN-UAT.md."
    why_human: "Physical-device visual checks that are not automatable — unchanged from Phase 4."
---

# Phase 6 Verification Report

**Phase Goal:** Close the two Phase 4 gaps the v1.0 milestone audit found: (1) wire `AttestationService` into the first-login `/device/register` path so App Attest fires at first OTP verify — `OTPViewModel.swift` previously hardcoded `attestationStatus: .unsupported` and never called `AttestationService` (DEV-04 / Phase 4 SC-1 unmet); (2) capture the discarded `/device/register` response and write `AppSession.trustTier` from the login path (closes the cross-phase wiring break + Phase 4 `deferred-items.md` #2); (3) produce a real `04-VERIFICATION.md` for the previously-unverified Phase 4.

**Verified:** 2026-05-18T22:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `OTPViewModel.verify()` STEP 5 fires the full App Attest orchestration (`generateKeyIfNeeded()` → `GET /device/challenge` → `attestKey()` → `POST /device/register`) and the hardcoded `attestationStatus: .unsupported` is gone. | VERIFIED | `OTPViewModel.swift` lines 346-401: `buildAttestationFields()` calls `attestationService.generateKeyIfNeeded()` (L349), fetches `DeviceChallengeEndpoint` (L359), calls `attestationService.attestKey(keyId:challenge:)` (L367-370). `grep 'attestationStatus: .unsupported' OTPViewModel.swift` → 0 matches. `grep 'Plan 06 AppContainer wiring' OTPViewModel.swift` → 0 matches (stale comment deleted). Commit `85b0846`. |
| 2 | `OTPViewModel.init` accepts `attestationService: any AttestationService` and `AuthCoordinator.pushOTP` passes `container.attestationService`. | VERIFIED | `OTPViewModel.swift` L105, L124: `private let attestationService: any AttestationService`; init param at L124. `AuthCoordinator.swift` L61: `attestationService: container.attestationService`. |
| 3 | The `/device/register` response is captured (not discarded) and `trustTier` is persisted to Keychain via `AttestedKeyStore.writeTrustTier`. | VERIFIED | `OTPViewModel.swift` L249-286: `let registerResponse = try await postDeviceRegister(...)` (assigned, not `_ =`). `grep '_ = try await apiClient.request' OTPViewModel.swift` → 0 matches. L286: `try? attestedKeyStore.writeTrustTier(registerResponse.trustTier)`. `AttestedKeyStore.writeTrustTier` (L127-133): writes `tier.rawValue.utf8` to `.trustTier` with `.afterFirstUnlockThisDeviceOnly`. |
| 4 | `AppContainer` seeds `AppSession.trustTier` from the persisted `device.trustTier` Keychain item; absent item falls back to `.softwareOnly`. | VERIFIED | `AppContainer.swift` L421-422: `let seededTrustTier = (try? attestedKeyStore.readTrustTier()) ?? .softwareOnly; self.session = AppSession(trustTier: seededTrustTier)`. The prior `#if DEBUG` trustTier branch is replaced. `grep 'uiTestTrustTierOverride' validationLedger/` → 0 matches (all 3 deletion sites confirmed). |
| 5 | `AppSession.trustTier` is observable (NotificationCenter); `AppCoordinator` subscribes and re-renders the `LimitedTrustBanner` on mutation without animation, without root-swap. | VERIFIED | `AppSession.swift` L72-79: `trustTier` `didSet` posts `.trustTierDidChange` with `userInfo[trustTierUserInfoKey]`. `AppCoordinator.swift` L151-167: subscribes `forName: .trustTierDidChange, object: container.session, queue: .main`; closure calls `bannerContainer.update(trustTier: newTier)`. Observer torn down in `deinit` L173-176. `AppSession` is still a plain `@MainActor final class` — no `ObservableObject`/`@Observable` (grep confirmed). |
| 6 | `KeychainKey.trustTier` exists as raw value `device.trustTier` in the attestation key group and is NOT in `KeychainScope.session`. | VERIFIED | `KeychainKey.swift` L49: `public static let trustTier = KeychainKey(rawValue: "device.trustTier")`. Comment L46-48 documents it MUST NOT be in `.session`. `KeychainScopeTests.swift` L31-35: asserts `KeychainScope.session.contains(.trustTier) == false`. `grep -c 'device.trustTier' KeychainKey.swift` → 2 (declaration + comment). No `deleteTrustTier` anywhere. |
| 7 | Graceful-skip (non-`.attested` status) and degrade-and-continue (transient failure) both send a register POST and complete login. The `challengeExpired` retry path refetches challenge, re-attests, and retries exactly once. | VERIFIED | `OTPViewModel.swift` L352-355: guard for `.attested`/`.simulatorBypass`; otherwise returns nil fields + real status. L375-379: catch path sets `status = .error` and returns nil fields without throwing. L258-272: `catch ... where extractErrorCode(...) == "challengeExpired"` re-runs `buildAttestationFields()` and retries once. A second consecutive `challengeExpired` falls through to the outer catch and sets `.registerFailed`. |
| 8 | `04-VERIFICATION.md` exists for Phase 4, is a real verification report (163 lines), covers all 3 Phase 4 SCs plus DEV-04 and CI-03 with concrete evidence citations, and records Phase 4 status as `human_needed` / score `3/3`. | VERIFIED | File exists at `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md` (163 lines). YAML frontmatter: `status: human_needed`, `score: 3/3`, `gaps: []`. Contains `SC-1`, `SC-2`, `SC-3`, `DEV-04`, `CI-03` rows each with evidence citing named artifacts (commits `5c0db4c`/`85b0846`, `OTPViewModelTests`, `AppAttestRoundTripTests.swift` device run 2026-05-16, `ci-device.yml`, `DeviceRegisterOmissionTests.swift`, `docs/ci.md`). No invented evidence — all cited artifacts confirmed present on disk. |
| 9 | ROADMAP.md `04-10-PLAN.md` checkbox is ticked `[x]`. | VERIFIED | `grep '04-10-PLAN' ROADMAP.md` → `- [x] 04-10-PLAN.md — Wave 5: CI pipeline...`. Already ticked before Plan 04 ran (commit `07af505` during Phase 6 planning). |

**Score: 9/9 truths verified.**

---

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `validationLedger/Core/Storage/Keychain/KeychainKey.swift` | VERIFIED | `device.trustTier` static at L49, attestation group, not in session scope. |
| `validationLedger/Core/Attestation/AttestedKeyStore.swift` | VERIFIED | `readTrustTier()` / `writeTrustTier(_:)` accessors at L115-133. `itemNotFound→nil` in `readTrustTier`. `.afterFirstUnlockThisDeviceOnly` in `writeTrustTier`. No `deleteTrustTier`. |
| `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` | VERIFIED | STEP 5 rewritten (L219-286). Contains `generateKeyIfNeeded`, `attestKey`, `writeTrustTier`, `challengeExpired` retry, `buildAttestationFields()`, `postDeviceRegister()`. 437 lines total. |
| `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` | VERIFIED | L61: `attestationService: container.attestationService` at the single `OTPViewModel` construction site. |
| `validationLedger/App/AppSession.swift` | VERIFIED | `.trustTierDidChange` `Notification.Name` + `trustTierUserInfoKey` + `didSet` at L47-79. Plain `@MainActor final class`. |
| `validationLedger/App/AppContainer.swift` | VERIFIED | L421-422: Keychain seed read. No `uiTestTrustTierOverride` anywhere. `makeKYCStatusScreen()` passes `keychain:` and wires `onVerified`. |
| `validationLedger/App/AppCoordinator.swift` | VERIFIED | `LimitedTrustBannerContainerViewController` retained at L51; observer wired at L151-167; torn down in `deinit`. |
| `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift` | VERIFIED | `init` accepts `keychain: KeychainStore` (L119, L125). `refreshCachedKYCStatus(_:)` writes `.kycStatus` with `.afterFirstUnlockThisDeviceOnly` (L160-178). |
| `validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift` | VERIFIED | Exists. 4 `@Test` functions (round-trip `.hardwareAttested`, round-trip `.softwareOnly`, fresh-store-nil, overwrite). |
| `validationLedgerTests/Storage/KeychainScopeTests.swift` | VERIFIED | Extended with 2 new `@Test`: `device.trustTier` NOT in `.session`, and `device.trustTier` survives `deleteAll(under: .session)`. |
| `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` | VERIFIED | 15 `@Test` functions (4 original + 10 new behavioral + 1 D6-07 PII source-grep, based on file grep count of 15). FakeAttestationService injected. Covers `.attested` happy path, D6-01 trustTier persistence, D6-04 graceful skip (`.unsupported`/`.entitlementMissing`), D6-05 degrade (challenge failure/attestKey throw), D6-06 retry-once/second-expiry, retryRegister idempotency, PII source-grep. |
| `validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift` | VERIFIED | Exists. Seeds `.hardwareAttested`, seeds `.softwareOnly`, absent → `.softwareOnly` default. |
| `validationLedgerTests/App/AppSessionTrustTierObservationTests.swift` | VERIFIED | Exists. Asserts mutation posts `.trustTierDidChange` with new tier; instance-scoped. |
| `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md` | VERIFIED | Exists at 163 lines. All required sections present. All 3 SCs + DEV-04 + CI-03 covered with evidence. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `OTPViewModel.swift` | `AttestationService.generateKeyIfNeeded / attestKey` | `attestationService` param injected through `init` | WIRED | `attestationService.generateKeyIfNeeded()` at L349; `attestationService.attestKey(keyId:challenge:)` at L367. |
| `OTPViewModel.swift` | `AttestedKeyStore.writeTrustTier` | Captured `/device/register` response; `attestedKeyStore` built from `keychain` | WIRED | `attestedKeyStore.writeTrustTier(registerResponse.trustTier)` at L286. `attestedKeyStore` constructed `AttestedKeyStore(keychain: keychain)` at L134. |
| `AuthCoordinator.swift` | `OTPViewModel.init` | Single construction site `pushOTP` | WIRED | L61: `attestationService: container.attestationService` confirmed. |
| `AppContainer.swift` | `AttestedKeyStore.readTrustTier` | `AppSession` seeding at init | WIRED | L421: `(try? attestedKeyStore.readTrustTier()) ?? .softwareOnly`. |
| `AppCoordinator.swift` | `AppSession.trustTier` observation | `.trustTierDidChange` NotificationCenter observer scoped to `container.session` | WIRED | L151-167: `addObserver(forName: .trustTierDidChange, object: container.session)`. |
| `KYCStatusViewModel.swift` | `KeychainStore .kycStatus` | `refreshCachedKYCStatus` call after `KYCStatusEndpoint` success | WIRED | L160-178: `keychain.set(Data(...), for: .kycStatus, accessibility: .afterFirstUnlockThisDeviceOnly)` after successful fetch. |
| `04-VERIFICATION.md` | ROADMAP.md Phase 4 success criteria | Observable Truths + Requirements Coverage tables | WIRED | SC-1, SC-2, SC-3 each appear as rows. DEV-04 and CI-03 in Requirements Coverage. |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `OTPViewModel.verify()` | `registerResponse.trustTier` | `postDeviceRegister()` → `DeviceRegisterEndpoint.Response` | Yes — typed `Decodable` endpoint response; not hardcoded | FLOWING |
| `AppContainer.init` | `seededTrustTier` | `attestedKeyStore.readTrustTier()` → Keychain `device.trustTier` | Yes — reads live Keychain item written by OTPViewModel | FLOWING |
| `AppCoordinator` banner update | `newTier` | `.trustTierDidChange` notification `userInfo` → `TrustTier(rawValue:)` | Yes — driven by `AppSession.trustTier` `didSet` | FLOWING |
| `KYCStatusViewModel.fetchStatus()` | `response.overallStatus` | `apiClient.request(KYCStatusEndpoint())` | Yes — real API call; Keychain write after success | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — behavioral spot-checks require a running simulator/device. The verification context confirms the post-merge simulator test suite (391 tests including 11 UI tests) passed. Specific new test targets verified in summaries: `OTPViewModelTests` (15/15), `AttestedKeyStoreTrustTierTests` (4/4), `KeychainScopeTests` (extension tests pass), `AppContainerTrustTierSeedingTests` (3/3), `AppSessionTrustTierObservationTests` (2/2), `KYCStatusViewModelTests` (8/8), `LimitedTrustBannerTests` (2/2 UI tests). All 9 Phase 6 commits confirmed in git log.

---

### Probe Execution

Step 7c: No `probe-*.sh` scripts declared in any Phase 6 PLAN. SKIPPED — not applicable.

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DEV-04 | 06-01, 06-02, 06-03 | App Attest called on first successful login; attestation payload in `/device/register`; graceful skip if unavailable. | SATISFIED | The milestone audit's `partial` (first-login trigger missing + trustTier consumer missing) is fully closed. Plan 02 wired STEP 5 orchestration (commits `5c0db4c`/`85b0846`); Plan 01 added `device.trustTier` Keychain contract; Plan 03 wired `AppContainer` consumer. `grep 'attestationStatus: .unsupported' OTPViewModel.swift` → 0. `grep 'uiTestTrustTierOverride' validationLedger/` → 0. REQUIREMENTS.md traceability table still shows "Pending" for DEV-04 — this table has not been updated since 2026-04-20 and reflects a pre-Phase-4 snapshot; the `[x]` checkbox on the DEV-04 requirement text line is the authoritative status. The table staleness is pre-existing across all phases and is not a Phase 6 gap. |
| CI-03 | 06-04 | Physical-device test plan covers SE keypair-gen + Keychain biometric-bound storage + App Attest assertion tests; runs on every merge to `main`. | SATISFIED | The audit's `partial` was a missing verification gap (no `04-VERIFICATION.md`). `04-VERIFICATION.md` now exists (Plan 04, commit `a69e497`) with SC-3 row citing `ci-device.yml` `device-security-surface` job, 2026-05-16 green device run, and `docs/ci.md`. REQUIREMENTS.md traceability table shows "Pending" — same pre-existing staleness as DEV-04 (see above). |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `OTPViewModel.swift` | L432-434 | `retryRegister()` calls `verify()` which re-issues `POST /auth/otp/verify` with a consumed OTP code. This is a pre-existing design (Phase 3), NOT introduced by Phase 6. Documented as CR-01 in `06-REVIEW.md`. | WARNING (pre-existing, advisory) | A user in `.registerFailed` state who retries will likely see a spurious "Invalid code" error because the OTP code was already consumed by STEP 1. Does not block the Phase 6 goal (STEP 5 fires App Attest on successful first login); this is a recovery-path robustness issue. The CR-01 fix (cache STEP 1-4 outputs, resume from STEP 5) is the correct remedy but is out of scope for this verification. |

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 6 modified source file. No placeholder text, no hardcoded empty arrays/dicts returned from meaningful functions.

---

### Human Verification Required

#### 1. LimitedTrustBannerContainerViewController re-render on mid-session trustTier mutation

**Test:** Start the app, log in as a user whose device would be `.softwareOnly`. Confirm the LimitedTrustBanner is visible. Then (in a test build or DevMenu) trigger a `trustTier` mutation to `.hardwareAttested`. Verify the banner disappears in place with no animation and no root-swap. Then mutate back to `.softwareOnly` and verify the banner reappears.

**Expected:** Banner appears/disappears in place without animation. The role-shell tab bar remains the same UIViewController hierarchy; only the banner subview is toggled.

**Why human:** The `LimitedTrustBannerContainerViewController.update(trustTier:)` method and the observer path are code-verified. The UIKit in-place toggle behavior (no animation, correct subview insertion point, no root-swap) requires visual confirmation in a running app.

#### 2. Profile-entry KYC status "Continue" CTA pop/dismiss behavior

**Test:** From the role shell, tap Profile. Tap the KYC status entry point. Verify the KYC status screen appears (pushed or modally presented). Tap "Continue". Verify the screen dismisses/pops back to the Profile tab — NOT a root-swap to the role shell.

**Expected:** User lands on the Profile tab. No coordinator handoff, no role-shell recreation.

**Why human:** The `onVerified` closure (pop when on nav stack, dismiss otherwise) is wired in `AppContainer.makeKYCStatusScreen()`. The correct UIKit navigation behavior requires hands-on confirmation with the actual Profile → KYC status push flow.

#### 3. Banner physical-device UAT (carried from Phase 4)

**Test:** See `04-HUMAN-UAT.md` items 1-5: iPhone landscape safe-area pinning, gesture non-dismiss, iPad portrait/landscape/SplitView layout, yellow-tone legibility.

**Expected:** All 5 items pass on physical iPhone 16 and iPad Pro 11-inch.

**Why human:** Physical-device visual checks — orientation, Dynamic Island, native-iPad rendering, real-gesture rejection, ambient-light legibility.

---

### Gaps Summary

No open code gaps blocking the Phase 6 goal.

The three goal deliverables are confirmed in the codebase:

1. **DEV-04 first-login App Attest wiring** — `OTPViewModel.verify()` STEP 5 fires `generateKeyIfNeeded()` → `GET /device/challenge` → `attestKey()` → `POST /device/register`. The hardcoded `.unsupported` is gone. Graceful-skip, degrade-and-continue, and challengeExpired-retry-once paths are all implemented. 15 behavioral tests cover these paths.

2. **trustTier producer → Keychain → consumer wiring** — `OTPViewModel` captures the register response and writes `trustTier` via `AttestedKeyStore.writeTrustTier`. `AppContainer` reads it at init via `readTrustTier()` and seeds `AppSession`. The `uiTestTrustTierOverride` seam is deleted at all 3 sites. Cross-phase wiring break from the milestone audit is closed.

3. **`04-VERIFICATION.md` exists and is substantive** — 163-line retroactive Phase 4 verification report. All 3 Phase 4 SCs verified with named evidence citations. DEV-04 and CI-03 in Requirements Coverage. Open Phase 4 device-UAT items carried in `human_verification`.

**Advisory note (CR-01, non-blocking):** `retryRegister()` re-issues `POST /auth/otp/verify` with a consumed OTP code, making the retry path unreliable in production (the OTP backend will likely return 401). This is a pre-existing Phase 3 design issue, NOT introduced by Phase 6. The Phase 6 goal is achieved; CR-01 should be addressed in a future robustness pass.

**REQUIREMENTS.md traceability table:** DEV-04 and CI-03 rows still show "Pending" in the table at the bottom of REQUIREMENTS.md (last updated 2026-04-20). This table has never been updated by any phase (all rows for phases 1-4 show "Pending" despite `[x]` checkboxes on the same requirements' text lines). Not a Phase 6 gap — not part of Phase 6 scope.

---

_Verified: 2026-05-18T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
