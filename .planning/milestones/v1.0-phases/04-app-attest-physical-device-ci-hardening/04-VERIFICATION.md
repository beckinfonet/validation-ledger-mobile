---
phase: 04-app-attest-physical-device-ci-hardening
verified: 2026-05-18T21:40:00Z
status: human_needed
score: 3/3
re_verification:
  note: >-
    This is the FIRST verification of Phase 4 — the phase was completed on disk
    (11/11 plans, 11/11 summaries) but never run through /gsd-verify-work. Its
    absence (Critical Gap #1 in the v1.0 milestone audit, 2026-05-18) directly
    hid the DEV-04 first-login App Attest gap (Critical Gap #2). Both gaps were
    closed by Phase 6 (plans 06-01, 06-02, 06-03); this retroactive report
    records the now-true state of all three Phase 4 success criteria.
  produced_by: "Phase 6 Plan 04 (D6-11 / D6-12)"
gaps: []
human_verification:
  - test: "Banner safe-area pinning on iPhone landscape"
    expected: "LimitedTrustBannerView pinned to the safe-area top in landscape; no Dynamic Island overlap; full D-11 copy legible (may wrap to 2 lines at narrower widths)."
    why_human: "Physical-device visual check — orientation + Dynamic Island safe-area behaviour cannot be asserted by an XCUITest or in the simulator with confidence. Tracked in 04-HUMAN-UAT.md item 1."
  - test: "Banner non-dismissibility via user gestures"
    expected: "Swipe (left/right/up/down) and tap on the banner do NOT dismiss or hide it. isUserInteractionEnabled = false enforces this at the UIKit layer."
    why_human: "Physical-device gesture check — confirming a real finger gesture is ignored is a hands-on visual UAT, not an automatable assertion. Tracked in 04-HUMAN-UAT.md item 2."
  - test: "Banner layout on iPad Pro 11-inch (portrait, landscape, Split View)"
    expected: "Banner renders above the tab bar, full width, pinned to the safe-area top; copy on a single line at 11in width; in Split View it reflows to the narrower width, still pinned."
    why_human: "Physical-iPad multi-orientation + Split View visual check — native iPad rendering (CLAUDE.md devices constraint) is a hands-on UAT. Tracked in 04-HUMAN-UAT.md items 3-4."
  - test: "Yellow tone acceptability across ambient light"
    expected: "systemYellow @ 85% alpha is legible against the role shell's white/system background across indoor fluorescent, sunlight, and night-mode conditions."
    why_human: "Subjective legibility judgement across real ambient-light conditions — not measurable in CI. Tracked in 04-HUMAN-UAT.md item 5."
---

# Phase 4: App Attest & Physical-Device CI Hardening — Verification Report

**Phase Goal:** Add App Attest to the device-registration flow with server-side
counter/challenge handling, and harden the physical-device CI pipeline to actually
exercise Secure Enclave keypair generation, Keychain biometric-bound item storage,
and App Attest assertion generation on every merge to `main`. After this phase the
attestation surface exists and the test surface that exercises it is real.

**Verified:** 2026-05-18T21:40:00Z
**Status:** human_needed
**Score:** 3/3 — all three Phase 4 success criteria satisfied.

---

## Re-verification Context

This is a **retroactive first verification** of Phase 4. Phase 4 was completed on
disk (11 plans, 11 summaries) but — uniquely among the five M1 phases — was never
run through `/gsd-verify-work`. The v1.0 milestone audit (`v1.0-MILESTONE-AUDIT.md`,
2026-05-18) recorded this as **Critical Gap #1** ("Phase 4 was never verified — no
`04-VERIFICATION.md`") and noted that its absence directly hid **Critical Gap #2**:
DEV-04 / Phase 4 SC-1 require App Attest on the *first successful OTP verify*, but
`OTPViewModel.swift` hardcoded `attestationStatus: .unsupported` and never called
`AttestationService` — App Attest ran only later, via the cold-boot / 24h heartbeat.

Both gaps have since been closed by **Phase 6** (insert phase "Close gap: DEV-04
App Attest at first login + trustTier consumer + Phase 4 verification"):

- **06-02** rewrote `OTPViewModel.verify()` STEP 5 to fire `generateKeyIfNeeded()` →
  `GET /device/challenge` → `attestKey()` → `POST /device/register` on first login,
  with graceful-skip / degrade-and-continue / challengeExpired-retry-once postures —
  this is the literal SC-1 closure.
- **06-01** added the `device.trustTier` Keychain contract; **06-03** wired the
  `AppContainer` consumer so the captured `/device/register` `trustTier` survives the
  post-OTP container swap and re-renders the `LimitedTrustBanner`.

This report therefore verifies the **now-true** state of Phase 4 — all three success
criteria — citing the original Phase 4 artifacts where they stood and the Phase 6
plans where a gap was closed.

---

## Goal Achievement

Phase 4 delivered the App Attest attestation surface and the physical-device CI lane
that exercises it. At the original (never-run) Phase 4 verification, **SC-2 and SC-3
were already satisfied** by Phase 4's own plans (04-01..04-11), and the attestation
*infrastructure* SC-1 depends on (`Core/Attestation`, `AttestationService`,
`AttestedKeyStore`, `DeviceChallenge`/`DeviceRegister` endpoints, the
`AttestationErrorResponseInterceptor`) was present and functional. **SC-1's literal
"on first successful login" trigger was a GAP** — the milestone audit found
`OTPViewModel.swift` hardcoding `.unsupported` and never invoking `AttestationService`,
with a stale in-code comment ("Plan 06 AppContainer wiring will replace this") marking
a replacement that never landed. Phase 6 Plan 02 landed that replacement; SC-1 is now
satisfied. The Phase 4 goal — "the attestation surface exists and the test surface
that exercises it is real" — is met, with the first-login trigger closed retroactively
by Phase 6.

### Observable Truths

| # | Truth (Phase 4 Success Criterion) | Status | Evidence |
|---|-----------------------------------|--------|----------|
| SC-1 | On a physical device, first successful OTP verify generates an App Attest key once, persists its identifier to Keychain, and includes an assertion (server challenge + request-body hash) in the `/device/register` payload. | SATISFIED (gap closed by Phase 6) | **Was a GAP at original Phase 4** — `OTPViewModel.verify()` STEP 5 hardcoded `attestationStatus: .unsupported`, never called `AttestationService` (v1.0-MILESTONE-AUDIT.md Critical Gap #2). **Closed by Phase 6 Plan 02** (`06-02-SUMMARY.md`, commits `5c0db4c` RED / `85b0846` GREEN): STEP 5 now fires `generateKeyIfNeeded()` → `GET /device/challenge` → `attestKey()` → `POST /device/register` on first login; the App Attest key id persists to Keychain via `AttestedKeyStore` (`attestedKeyId` / Phase 4 04-03); `grep 'attestationStatus: .unsupported' OTPViewModel.swift` → 0 matches. Behavioural proof: the 14-test `OTPViewModelTests` suite (`.attested` happy path drives the full `verify → GET /device/challenge → POST /device/register` sequence). Hardware round-trip evidence: the existing `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` (Phase 4 Plan 04-09) — `generateKey → attestKey → generateAssertion` ran green on the physical-device CI (iPhone 16, 2026-05-16 device run, per REQUIREMENTS.md DEV-04). No new device test was required (06-RESEARCH Environment Availability). |
| SC-2 | On a device where App Attest is unavailable (older hardware, entitlement missing), registration proceeds with a logged warning and a graceful-skip flag in the payload — no user-facing error. | SATISFIED | Phase 4 landed the graceful-skip attestation status surface (`AttestationStatus` incl. `.unsupported` / `.entitlementMissing`) and the `DeviceRegisterEndpoint` three-key payload (04-04). Phase 6 Plan 02's D6-04 `buildAttestationFields()` is the non-throwing boundary: a non-`.attested` status returns the graceful-skip tuple (nil `attestedKeyId` / `attestationObject` + the real status, `attestKey` not called) and STILL POSTs `/device/register`; any throw degrades to the D6-05 tuple (`status = .error`) — login is never blocked (`06-02-SUMMARY.md`). PII-disciplined `attestation_first_login_skipped_no_key` / `_degraded` log events carry only the event name + `AttestationStatus.rawValue`. Behavioural proof: the graceful-skip `OTPViewModelTests` cases (`.unsupported` / `.entitlementMissing` + challenge-fetch-failure / `attestKey`-throw degrade) and `validationLedgerTests/Networking/DeviceRegisterOmissionTests.swift` for the field-omission rule. |
| SC-3 | CI physical-device pipeline runs Secure Enclave keypair-generation + Keychain biometric-bound storage + App Attest assertion tests on every merge to `main`, and blocks merges that break any of them. | SATISFIED | `.github/workflows/ci-device.yml` `device-security-surface` job (Phase 4 Plan 04-10) runs `-only-testing:validationLedgerDeviceTests` — `AppAttestRoundTripTests.swift`, `KeychainBiometricACLTests.swift`, `SecureEnclaveKeyStoreTests.swift`, `LogoutClearsAuthorizationKeyTests.swift` — on a self-hosted runner + physical iPhone, triggered on every `push` to `main` and every `pull_request` to `main`. It is a **required branch-protection check** on `main` (gate verified 2026-05-16 per REQUIREMENTS.md CI-03), so a broken security-surface test blocks the merge. `docs/ci.md` ("Device Pipeline" section) documents the job structure and the path-gated job-level trigger. **Operational caveat:** a locked runner iPhone surfaces as a ~35-min "cancelled" timeout from an unsatisfiable Face ID prompt — not a code failure (project memory: device-ci-biometric-infra). |

**Score: 3/3** — all three Phase 4 success criteria satisfied. Status is `human_needed`
because the Phase 4 `LimitedTrustBanner` (D-11) carries 5 open physical-device visual
UAT items (`04-HUMAN-UAT.md`) that are not code gaps.

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| DEV-04 | 04-01, 04-03, 04-05, 04-06, 04-07, 04-09 (Phase 4); 06-01, 06-02, 06-03 (Phase 6 closure) | `Core/Attestation` calls App Attest on first successful login; attestation payload included in `/device/register`; gracefully skipped if App Attest is unavailable, with a logged warning. | SATISFIED | The milestone audit marked DEV-04 **partial** — the attestation infrastructure existed but the first-login trigger and the `/device/register` response consumer were unwired. **Phase 6 closed both halves:** Plan 02 wired `AttestationService` into `OTPViewModel.verify()` STEP 5 (first-login trigger — closes the `partial`); Plans 01 + 03 added the `device.trustTier` Keychain contract and the `AppContainer` consumer (closes deferred-items #2, the user-accepted 2026-04-22 follow-up). The graceful-skip path is the D6-04 `buildAttestationFields()` boundary (SC-2 above). |
| CI-03 | 04-09, 04-10 (Phase 4) | Physical-device test plan covers Secure Enclave keypair generation, Keychain biometric-bound item storage, App Attest assertion generation; runs on every merge to `main`. | SATISFIED | The milestone audit marked CI-03 **partial** — satisfied at the artifact level (`ci-device.yml` `device-security-surface` job exists; 2026-05-16 gate-verified run) but carrying an **unclosed verification gap** because no `04-VERIFICATION.md` existed. **This report closes the verification half:** the `device-security-surface` job runs `validationLedgerDeviceTests` (`AppAttestRoundTripTests`, `KeychainBiometricACLTests`, `SecureEnclaveKeyStoreTests`, `LogoutClearsAuthorizationKeyTests`) green on the self-hosted device runner, is a required branch-protection check on `main`, and is documented in `docs/ci.md`. With this verification produced, CI-03's verification gap is closed. |

Both requirements were `partial` in `v1.0-MILESTONE-AUDIT.md` (65/67 satisfied, DEV-04
+ CI-03 the two partials). With Phase 6's first-login wiring and this retroactive
report, both are now SATISFIED.

---

### Human Verification Required

The following items are physical-device visual checks on the Phase 4
`LimitedTrustBannerView` (D-11). They are tracked verbatim in
`04-HUMAN-UAT.md` (5 items, all `pending` — iPhone-portrait was confirmed PASS on
2026-04-22). They are **UI visual UAT, not code gaps**, and do not affect the 3/3
success-criteria score:

1. **Banner safe-area pinning on iPhone landscape** — pinned to safe-area top, no
   Dynamic Island overlap, full D-11 copy legible.
2. **Banner non-dismissibility via user gestures** — swipe/tap do not dismiss or hide
   the banner (`isUserInteractionEnabled = false`).
3. **Banner layout on iPad Pro 11-inch (portrait)** — renders above the tab bar, full
   width, pinned to safe-area top, copy on a single line.
4. **Banner layout on iPad Pro 11-inch (landscape + Split View)** — pinned in
   landscape; in Split View reflows to the narrower width, still pinned.
5. **Yellow tone acceptability** — `systemYellow @ 85% alpha` legible against the role
   shell background across indoor / sunlight / night-mode ambient light.

These items remain genuinely human-only (orientation, Dynamic Island, native-iPad
rendering, real-gesture rejection, subjective ambient-light legibility). They are
carried, not marked passed.

---

### Gaps Summary

**No open code gaps.** The two gaps the milestone audit attributed to Phase 4 are
both closed:

- **SC-1 / DEV-04 first-login App Attest** — closed by Phase 6 Plan 02
  (`OTPViewModel` STEP 5 rewrite; `06-02-SUMMARY.md`).
- **`/device/register` → `AppSession.trustTier` consumer** (Phase 4 `deferred-items.md`
  #2, the user-accepted follow-up) — closed by Phase 6 Plans 01 + 03.

The `human_needed` status reflects only the 5 open Phase 4 `LimitedTrustBanner`
device-UAT visual items — physical-device checks, not code defects.

Pre-existing Phase 4 tech debt carried forward unchanged (not re-opened by this
verification): `deferred-items.md` #1 (the pre-existing MockURLProtocol fixture-registry
leak — Phase 5 since reports 367 / 383 simulator tests green, so the race is a
test-infra item only) and the now-removed `AppContainer.uiTestTrustTierOverride`
DEBUG seam (deleted by Phase 6 Plan 03's D6-03).

---

_Verified: 2026-05-18T21:40:00Z_
_Verifier: Claude (gsd-executor) — retroactive Phase 4 verification produced by Phase 6 Plan 04 (D6-11 / D6-12)_
