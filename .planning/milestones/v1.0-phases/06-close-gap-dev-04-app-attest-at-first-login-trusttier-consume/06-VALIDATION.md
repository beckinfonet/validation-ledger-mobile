---
phase: 6
slug: close-gap-dev-04-app-attest-at-first-login-trusttier-consume
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-18
validated: 2026-05-18
---

# Phase 6 — Validation Strategy

> Per-phase validation contract. Reconstructed and audited 2026-05-18 — the file was
> created as an unfilled template at plan time; this audit populates it against the
> as-executed plans, summaries, and a live re-run of every phase-6 test suite.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite` / `@Test`, `#expect`) + XCTest, run via `xcodebuild` |
| **Config file** | none — `validationLedger.xcodeproj` (no `.xctestplan`); test targets `validationLedgerTests` (simulator lane) + `validationLedgerDeviceTests` (device-CI lane) |
| **Quick run command** | `xcodebuild test-without-building -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:validationLedgerTests/<Suite> -parallel-testing-enabled NO` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO` |
| **Estimated runtime** | ~0.1–0.4 s test execution per phase-6 suite; ~1–3 min including a clean `build-for-testing` |

**Environment caveats** (apply on every run — see project memory `ios-test-suite-pitfalls`):
- `iPhone 16` is **not installed** on this host — substitute `iPhone 17` for `-destination` only.
- `validationLedgerDeviceTests` holds Secure-Enclave tests that error on the simulator
  (`-1020`); always `-skip-testing:validationLedgerDeviceTests` on the simulator lane.
- The simulator suite shares a process-global `MockURLProtocol` registry — run with
  `-parallel-testing-enabled NO` and isolate `MockURLProtocol`-driving suites into separate
  processes, or a known cross-suite race produces spurious `httpError 404` failures.

---

## Sampling Rate

- **After every task commit:** Run the quick command for the suite(s) touched by the task.
- **After every plan wave:** Run all that wave's suites with `-parallel-testing-enabled NO`.
- **Before `/gsd:verify-work`:** Full simulator suite green (`-skip-testing:validationLedgerDeviceTests`).
- **Max feedback latency:** < 180 s (build-for-testing once, then `test-without-building` per suite).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | DEV-04 | T-06-01-02 / T-06-01-03 | `device.trustTier` lives in Keychain only (no `UserDefaults`/file); unknown wire value re-hydrates as `nil` → safe `.softwareOnly` default, never fails open to `.hardwareAttested` | unit | `…-only-testing:validationLedgerTests/AttestedKeyStoreTrustTierTests` | ✅ | ✅ green (4/4) |
| 06-01-02 | 01 | 1 | DEV-04 | T-06-01-01 | `device.trustTier` is NOT a `KeychainScope.session` member — survives `deleteAll(under: .session)` (preserved across logout); no `deleteTrustTier` accessor exists | unit | `…-only-testing:validationLedgerTests/KeychainScopeTests` | ✅ | ✅ green (6/6) |
| 06-02-01 | 02 | 2 | DEV-04 | T-06-02-01 | RED behavioural surface for STEP 5; D6-07 PII source-grep — attestation `catch` blocks contain no `String(describing:)` token | unit | `…-only-testing:validationLedgerTests/OTPViewModelTests` | ✅ | ✅ green (14/14) |
| 06-02-02 | 02 | 2 | DEV-04 | T-06-02-02 / T-06-02-03 / T-06-02-05 | App Attest is never a login gate — graceful-skip (non-`.attested`) and degrade (transient throw) both still POST `/device/register`; `challengeExpired` refetch-and-retry-once, second expiry surfaces | unit | `…-only-testing:validationLedgerTests/OTPViewModelTests` | ✅ | ✅ green (14/14) |
| 06-03-01 | 03 | 3 | DEV-04 | T-06-03-01 / T-06-03-02 / T-06-03-05 | `uiTestTrustTierOverride` DEBUG seam deleted at all 3 sites; banner seeded from the backend-driven Keychain item; trustTier observation is in-process only | unit | `…-only-testing:validationLedgerTests/AppContainerTrustTierSeedingTests -only-testing:validationLedgerTests/AppSessionTrustTierObservationTests` | ✅ | ✅ green (5/5) |
| 06-03-02 | 03 | 3 | DEV-04 | T-06-03-03 / T-06-03-04 | `kycStatus` refreshed to Keychain `.kycStatus` with `.afterFirstUnlockThisDeviceOnly` after `GET /kyc/status`; fail-closed routing preserved (non-`verified` cached verbatim, still routes to KYC gate) | unit | `…-only-testing:validationLedgerTests/KYCStatusViewModelTests` | ✅ | ✅ green (8/8, incl. 3× D6-08) |
| 06-04-01 | 04 | 4 | DEV-04, CI-03 | T-06-04-01 | `04-VERIFICATION.md` cites only named existing artifacts — no invented evidence; genuinely-unverified device-UAT items carried in `human_verification`, not marked passed | doc-check | `test -f .../04-VERIFICATION.md && grep -q 'SC-1' && grep -q 'DEV-04' && grep -q 'CI-03'` | ✅ | ✅ green (`VERIFICATION_OK`) |
| 06-04-02 | 04 | 4 | CI-03 | T-06-04-02 | exactly one `[ ]`→`[x]` change to `ROADMAP.md`; no other checkbox or SC text altered | doc-check | `grep -qE '^\s*-\s*\[x\]\s*04-10-PLAN\.md' .planning/ROADMAP.md` | ✅ | ✅ green (`ROADMAP_TICKED`) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Quick-command prefix elided in the table: `xcodebuild test-without-building -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' … -parallel-testing-enabled NO`*

---

## Wave 0 Requirements

All Wave 0 RED test files were created during execution and are green:

- [x] `validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift` — DEV-04 trustTier round-trip + `itemNotFound`→`nil` (4 `@Test`)
- [x] `validationLedgerTests/Storage/KeychainScopeTests.swift` — DEV-04 D6-02 preserve-across-logout scope pin (extended: +2 `@Test`)
- [x] `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` — DEV-04 STEP 5 attestation orchestration (extended: +10 behavioural `@Test`)
- [x] `validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift` — DEV-04 Keychain seeding (3 `@Test`)
- [x] `validationLedgerTests/App/AppSessionTrustTierObservationTests.swift` — DEV-04 observable trustTier (2 `@Test`)
- [x] `validationLedgerTests/KYC/KYCStatusViewModelTests.swift` — DEV-04 D6-08 kycStatus refresh (extended: +3 `@Test`)

No framework install required — Swift Testing + XCTest are already in the project. `wave_0_complete: true`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `LimitedTrustBannerContainerViewController` re-render on mid-session `trustTier` mutation | DEV-04 | The NotificationCenter observer + `update(trustTier:)` call path are unit-tested, but the in-place visual toggle and the no-animation / no-root-swap contract need a running app | 06-HUMAN-UAT.md #1 — log in `.softwareOnly` (banner visible), mutate tier to `.hardwareAttested`, confirm the banner disappears in place with no animation; mutate back, confirm it reappears |
| Profile-entry KYC status "Continue" CTA pop/dismiss | DEV-04 | `onVerified` closure wiring is code-verified; correct UIKit navigation on the real Profile → KYC push/modal stack needs hands-on confirmation | 06-HUMAN-UAT.md #2 — Profile tab → KYC status entry → tap Continue → confirm it pops/dismisses back to the Profile tab, NOT a role-shell root swap |
| Phase 4 `LimitedTrustBanner` device-UAT (carried) | DEV-04 | Physical-device visual checks — orientation, Dynamic Island, native-iPad rendering, real-gesture rejection, ambient legibility | 04-HUMAN-UAT.md items 1–5 (iPhone landscape, gesture non-dismiss, iPad portrait/landscape/Split View, yellow-tone legibility) |
| CI-03 physical-device pipeline runs SE keypair-gen + Keychain biometric-bound storage + App Attest assertion tests on every merge to `main` | CI-03 | A device-CI / GitHub-Actions infrastructure check, not a simulator unit test — the device lane (`validationLedgerDeviceTests`) cannot run on the simulator | Verified by the `ci-device.yml` `device-security-surface` job + the 2026-05-16 green device run + `docs/ci.md`; recorded in `04-VERIFICATION.md` SC-3. Note the device-CI biometric-hang operational caveat (project memory) |

The two UIKit-visual items and the carried Phase 4 items are tracked in `06-HUMAN-UAT.md`
(`status: partial`, 3 pending). They are visual/physical checks, not automatable code gaps.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (no MISSING references — all Wave 0 files landed green)
- [x] No watch-mode flags
- [x] Feedback latency < 180 s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-18

---

## Validation Audit 2026-05-18

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

**Method.** State A — the pre-existing `06-VALIDATION.md` was an unfilled template; this audit
reconstructed it from the 4 PLAN/SUMMARY pairs and the `06-VERIFICATION.md` report, then
re-ran every phase-6 test suite live (not transcribed from summaries).

**Live re-run result (2026-05-18, iPhone 17 simulator, `test-without-building`):**

| Suite | Tests | Result |
|-------|-------|--------|
| `AttestedKeyStoreTrustTierTests` | 4 | ✅ pass |
| `KeychainScopeTests` | 6 | ✅ pass |
| `AppContainerTrustTierSeedingTests` | 3 | ✅ pass |
| `AppSessionTrustTierObservationTests` | 2 | ✅ pass |
| `OTPViewModelTests` | 14 | ✅ pass |
| `KYCStatusViewModelTests` | 8 | ✅ pass |
| **Total** | **37 across 6 suites** | **0 failures** |

`build-for-testing` exited 0 (only pre-existing, out-of-scope Swift 6 concurrency warnings).
Every DEV-04 code behaviour across Plans 01–03 has a passing automated test; Plan 04's
documentation tasks pass their `doc-check` verify gates. No requirement is MISSING or PARTIAL.
Remaining non-automated items are genuine physical-device / CI-infrastructure verifications
(see Manual-Only) — not test gaps. **Phase 6 is Nyquist-compliant.**
