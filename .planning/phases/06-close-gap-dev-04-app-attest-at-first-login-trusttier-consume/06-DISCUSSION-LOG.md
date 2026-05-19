# Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
**Areas discussed:** trustTier hand-off, App Attest failure posture, Optional audit fixes, 04-VERIFICATION.md close-out

---

## trustTier hand-off

### Q1 — How should the first-login trustTier cross the post-OTP container swap?

| Option | Description | Selected |
|--------|-------------|----------|
| Persist to Keychain | `AttestedKeyStore` gains `read/writeTrustTier`; `OTPViewModel` writes from the `/device/register` response, the role-shell `AppContainer` seeds `AppSession` at construction. Symmetric with existing attestation persistence, no callback churn, fixes the cold-boot banner too. | ✓ |
| Thread through callbacks | Add `trustTier` to the `onAuthenticated` → coordinator chain; productionizes the DEBUG `uiTestTrustTierOverride` seam. ~4 signature changes, no cold-boot benefit. | |
| Post-OTP heartbeat | Fire a heartbeat right after the role shell builds. Extra round-trip, visible banner flicker. | |

**User's choice:** Persist to Keychain
**Notes:** —

### Q2 — Where does the persisted trustTier Keychain item sit relative to logout?

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve across logout | Lives with `attestedKeyId`/`lastHeartbeatAt` (not `KeychainScope.session`); a device-attestation fact, overwritten by the next register. Correct banner on the first frame after re-login. | ✓ |
| Wipe on logout | Joins `.session` scope; post-logout falls back to `.softwareOnly` until the next register. | |

**User's choice:** Preserve across logout
**Notes:** —

### Q3 — Fate of the DEBUG `AppContainer.uiTestTrustTierOverride` seam

| Option | Description | Selected |
|--------|-------------|----------|
| Remove it | Delete the override; XCUITests drive the genuine path via the mock `/device/register` fixture's `trust_tier`. | ✓ |
| Keep it | Leave it as a belt-and-suspenders test hook. | |

**User's choice:** Remove it
**Notes:** —

---

## App Attest failure posture

### Q1 (first pass) — On a mid-sequence App Attest throw, what happens to the login?

User selected "Other" and asked a clarifying question rather than answering:
*"When and how can it fail? What are the factors that can prevent attestation
from succeeding?"* Claude answered in prose — enumerated the `generateKey` /
challenge-fetch / `attestKey` failure modes, grouped them into permanent
(device capability, entitlement) vs. transient (Apple's App Attest service,
the `/device/challenge` endpoint) — then re-posed the decision scoped to
transient failures.

### Q1 (re-posed) — On a TRANSIENT failure (Apple service or `/device/challenge` momentarily down), what happens to the login?

| Option | Description | Selected |
|--------|-------------|----------|
| Degrade + continue | Log a warning, set `attestationStatus: .error`, omit fields, still POST `/device/register`. Login completes; backend returns `.softwareOnly`; banner shows; heartbeat retries. | ✓ |
| Retry once, then degrade | Refetch a challenge and retry the attest sequence once inline before degrading. | |
| Hard-fail login | Treat as a `/device/register` failure → retry-able `.registerFailed` state. | |

**User's choice:** Degrade + continue
**Notes:** Permanent failures (`.unsupported`, `.entitlementMissing`,
`.quotaExceeded`) keep their Phase 4 D-09 graceful-skip path. Phase 4 D-08's
`challengeExpired` refetch+retry-once remains in force for that specific server
error code — it is a deterministic signal, distinct from a generic transient
failure.

---

## Optional audit fixes

### Q1 — Which of the audit's optional fixes should Phase 6 fold in? (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| WARNING-1: kycStatus refresh | Write `kycStatus` to Keychain after a successful `GET /kyc/status` — fixes the fail-closed cold-boot misroute for a user who completes KYC in-session then force-quits. | ✓ |
| Profile "Continue" CTA | Wire `onVerified` in `AppContainer.makeKYCStatusScreen()` — fixes the dead button. | ✓ |
| WARNING-2: banner re-render | Make `AppSession.trustTier` observable so `LimitedTrustBannerView` re-renders/removes on tier change. | ✓ |

**User's choice:** All three folded into Phase 6 scope.
**Notes:** All three originate from the same `v1.0-MILESTONE-AUDIT.md`; WARNING-2
is especially adjacent since Phase 6 already owns the trustTier/banner path.

---

## 04-VERIFICATION.md close-out

### Q1 — How should Phase 6 produce the retroactive 04-VERIFICATION.md?

| Option | Description | Selected |
|--------|-------------|----------|
| Tracked task in Phase 6 | Final plan/wave verifies Phase 4 against the now-fixed code and writes + commits `04-VERIFICATION.md`. | ✓ |
| Separate /gsd-verify-work 4 | Phase 6 fixes code only; verification run separately afterward. | |

**User's choice:** Tracked task in Phase 6
**Notes:** Must run last — Phase 4 SC-1 only passes once the Phase 6 wiring lands.

### Q2 — What should the retroactive 04-VERIFICATION.md cover?

| Option | Description | Selected |
|--------|-------------|----------|
| Full Phase 4 re-verification | All 3 Phase 4 success criteria + DEV-04 + CI-03; Phase 6 also ticks the roadmap `04-10` checkbox. | ✓ |
| Just the closed gap | Focus on SC-1 / DEV-04; note SC-2/SC-3/CI-03 as artifact-satisfied. | |

**User's choice:** Full Phase 4 re-verification
**Notes:** The gap was the *absence* of a verification record — so produce a
genuine, complete one.

---

## Claude's Discretion

- Factoring of the first-login attestation orchestration — inline in
  `OTPViewModel.verify()` STEP 5 vs. a shared helper also used by the heartbeat
  path.
- `OTPViewModel` DI surface shape for the new `AttestationService` +
  trustTier-write dependencies (`AuthCoordinator.swift:51` is the sole call site).
- Whether `.settingUp(progress:total:)` step labels change for the added
  attestation steps.
- WARNING-2 observation mechanism — NotificationCenter post vs. closure/observer
  on `AppSession`.

## Deferred Ideas

- Near-term re-attest after a degraded first login — ruled out; rely on the
  Phase 4 D-07 24h heartbeat / next cold boot.
- A shared first-login/heartbeat attestation seam — left as planner discretion;
  worthwhile only if a third attestation caller appears.
- Nyquist gap-fills for Phase 1 (partial) / Phase 2 (missing) — audit recommends
  `/gsd-validate-phase 1` and `/gsd-validate-phase 2` instead.
- Other audit tech-debt (CR-02b, CR-03, `DeviceFingerprint` `try?`, IN-02
  wire-format skew, `CameraPermissionViewController` product decision) —
  unrelated pre-Phase-6 debt, not Phase 6 scope.
