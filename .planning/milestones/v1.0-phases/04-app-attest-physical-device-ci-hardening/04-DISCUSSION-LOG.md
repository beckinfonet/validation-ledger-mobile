# Phase 4: App Attest & Physical-Device CI Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 04-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 04-app-attest-physical-device-ci-hardening
**Areas discussed:** App Attest key lifecycle, Challenge / assertion protocol, Graceful-skip contract, Device CI coverage & merge policy

---

## App Attest Key Lifecycle

### Q1: When does iOS call DCAppAttestService.generateKey()?

| Option | Description | Selected |
|--------|-------------|----------|
| Install-scoped, once (Recommended) | One call on first OTP verify after install; persist attestedKeyId in Keychain; reuse for all subsequent /device/register | ✓ |
| Per-login | generateKey on every OTP verify — burns through Apple's undocumented rate limit | |
| Explicit rotation only | Once on first OTP verify; thereafter only on explicit rotation trigger | |

**User's choice:** Install-scoped, once
**Notes:** Minimizes rate-limit exposure; aligns with App Attest's per-install design.

### Q2: How does the App Attest keyId relate to DEV-01's deviceKey?

| Option | Description | Selected |
|--------|-------------|----------|
| Alongside (three fields) (Recommended) | deviceKey + authorizationKey + attestedKeyId, three distinct roles | ✓ |
| Replaces deviceKey | App Attest keyId becomes device identity, drop DEV-01 | |
| Derived signature on deviceKey | App Attest attests the deviceKey's SPKI as clientDataHash | |

**User's choice:** Alongside (three fields)
**Notes:** ADR 0004 extends cleanly to ADR 0005.

### Q3: What happens on user logout?

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve across logout (Recommended) | attestedKeyId survives logout; SESS-04 wipes only session token + authorizationKey ACL + role coordinator | ✓ |
| Destroy on logout | Logout deletes attestedKeyId; next login must generateKey() again | |
| Preserve only for same user | Preserve keyed by userID; destroy on different-user login | |

**User's choice:** Preserve across logout
**Notes:** Same device + same install = same attestation; mirrors deviceKey lifecycle.

### Q4: What triggers forced re-attestation after initial?

| Option | Description | Selected |
|--------|-------------|----------|
| Backend-driven only (Recommended) | Client never self-rotates; responds to specific backend error codes + DEBUG-only dev-menu button | ✓ |
| Time-based + backend-driven | Every 90 days OR backend-triggered | |
| Never after initial | One attestation per install, permanent | |

**User's choice:** Backend-driven only

---

## Challenge / Assertion Protocol

### Q1: How does iOS obtain the server-generated challenge?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated endpoint (Recommended) | GET /device/challenge returns { challenge, expiresAt, nonce } | ✓ |
| Piggyback on OTP verify | Extend /otp/verify response with challenge | |
| Challenge embedded in /device/register two-step | POST /device/register → 202 { challenge } → POST again with attestation | |

**User's choice:** Dedicated endpoint

### Q2: What goes into SHA-256 clientDataHash?

| Option | Description | Selected |
|--------|-------------|----------|
| Server challenge only (Recommended) | clientDataHash = SHA-256(challenge) | ✓ |
| Challenge + request body | Binds attestation to specific payload | |
| Challenge + endpoint + body | Maximum binding per-endpoint | |

**User's choice:** Server challenge only

### Q3: Does iOS call generateAssertion() per-request, or only attest at registration?

| Option | Description | Selected |
|--------|-------------|----------|
| Registration-only (Recommended) | attestKey once at /device/register; no per-request assertions | |
| Per-request on sensitive endpoints | generateAssertion on every AUTH-06 sensitive call | |
| Registration + periodic heartbeat | attestKey at registration + generateAssertion once per session as heartbeat | ✓ |

**User's choice:** Registration + periodic heartbeat
**Notes:** User diverged from recommended — wants a "device still genuine" signal beyond one-shot registration.

### Q4: Challenge-freshness policy?

| Option | Description | Selected |
|--------|-------------|----------|
| Single-use, immediate (Recommended) | Fetch, use within seconds, no client caching; retry once on challengeExpired | ✓ |
| Short-lived cache | Cache up to 30s | |
| Server-dictated TTL | Use expiresAt from response | |

**User's choice:** Single-use, immediate

### Follow-up Q: What triggers the per-session heartbeat?

| Option | Description | Selected |
|--------|-------------|----------|
| Cold-boot re-login only (Recommended) | SessionRestoreProbe.restored → single generateAssertion | |
| Cold-boot + every 24h | Cold-boot AND lastHeartbeatAt > 24h check on didBecomeActive | ✓ |
| Driven by sensitive actions | Lazy heartbeat on first sensitive action | |

**User's choice:** Cold-boot + every 24h
**Notes:** More robust against long-running foreground sessions; requires lastHeartbeatAt Keychain persistence.

---

## Graceful-Skip Contract

### Q1: Wire-format when App Attest didn't run?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit status enum (Recommended) | attestationStatus: attested | unsupported | entitlementMissing | quotaExceeded | simulatorBypass | error | ✓ |
| Optional field, omitted | attestationObject optional; present = attested, absent = anything else | |
| Attestation always present | Client refuses /device/register without valid attestation | |

**User's choice:** Explicit status enum

### Q2: Which skip reasons does the client distinguish? (multiSelect)

| Option | Description | Selected |
|--------|-------------|----------|
| unsupported (old device) | isSupported == false | ✓ |
| entitlementMissing | isSupported true but generateKey returns .featureUnsupported | |
| quotaExceeded | Undocumented rate-limit error | |
| simulatorBypass | #if targetEnvironment(simulator) fake-attestation path | |

**User's initial choice:** unsupported only — flagged as possible UI misclick on a multiSelect.

### Q2 follow-up: Confirm status granularity

| Option | Description | Selected |
|--------|-------------|----------|
| All four, distinct (Recommended) | Keep full enum — each has different handling | ✓ |
| Just unsupported + error | Collapse to attested | unsupported | error | |
| Unsupported + simulatorBypass only | Two extra statuses; rest bucket as error | |

**User's choice:** All four, distinct
**Notes:** First answer was a multiSelect misclick; confirmed intent was the full granular enum.

### Q3: UX posture when attestation skips?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent + logged (Recommended) | No user-facing indicator; log at warn level | |
| Silent in prod, banner in DEBUG | DEBUG-only debug banner | |
| User-facing warning | Dismissible banner: "Limited trust mode" | ✓ |

**User's choice:** User-facing warning (with follow-up confirmation)
**Notes:** User chose to surface trust-tier state to users; consistent with product's "identity that cannot be spoofed" core value.

### Q3 follow-up: Banner placement + dismissibility?

| Option | Description | Selected |
|--------|-------------|----------|
| Non-dismissible role-shell banner (Recommended given initial pick) | Permanent banner at top of tab bar; copy: "Limited trust mode — this device can't fully verify..." | ✓ |
| Dismissible first-launch modal | One-time modal on first login when trustTier != hardwareAttested | |
| Banner only when restricted action attempted | Just-in-time surfacing on sensitive-action tap | |

**User's choice:** Non-dismissible role-shell banner

### Q4: Client reaction to backend response when attestation skipped?

| Option | Description | Selected |
|--------|-------------|----------|
| Accept server trust tier (Recommended) | Backend returns { registered, trustTier }; client is a dumb enforcer | ✓ |
| Pass/fail only | 200 or 4xx terminal screen | |
| Client interprets status | Client inspects attestationStatus to decide UI | |

**User's choice:** Accept server trust tier

---

## Device CI — Coverage & Merge Policy

### Q1: Which test surface runs on the device pipeline?

| Option | Description | Selected |
|--------|-------------|----------|
| Full security surface (Recommended) | SE keypair + Keychain biometric + App Attest + logout ACL clearing | ✓ |
| Attestation only | Only new Phase 4 App Attest tests | |
| Attestation + SE, biometric stays manual | Middle ground | |

**User's choice:** Full security surface
**Notes:** Retires 3 of 4 Phase 3 HUMAN-UAT items into CI coverage.

### Q2: How do biometric-prompt tests run in unattended CI?

| Option | Description | Selected |
|--------|-------------|----------|
| Seeded LAContext at test setup (Recommended) | DI a seeded LAContext returning .success synchronously | ✓ |
| Real Face ID + xcrun simctl biometric enroll | Simulator-only; flaky on physical iPhone | |
| Manual biometric items stay HUMAN-UAT | Skip automation | |

**User's choice:** Seeded LAContext at test setup

### Q3: What does the device pipeline do on test failure?

| Option | Description | Selected |
|--------|-------------|----------|
| Retry once, then fail (Recommended) | One retry on failed test; log flaky-passed on retry-success | ✓ |
| No retries, hard-fail | First failure fails pipeline | |
| Retry up to 3x | Aggressive retries | |

**User's choice:** Retry once, then fail

### Q4: Does device-CI failure actually block merging?

| Option | Description | Selected |
|--------|-------------|----------|
| Required status check (Recommended) | GitHub branch-protection required on main; admins override manually | ✓ |
| Required on security-path PRs, advisory on others | Weaker than CI-03 literally reads | |
| Advisory only, Slack-notify on failure | Zero safety net | |

**User's choice:** Required status check

---

## Claude's Discretion

- Exact Swift protocol surface for `AttestationService` (planner decides)
- Dev-menu "Re-attest now" row placement (follows existing DEBUG row pattern)
- Backend error-code enum names (coordinate with backend team)
- Banner visual styling (minimal UI principle)
- `/device/heartbeat` HTTP method + idempotency-key usage (researcher confirms vs NET-04)

## Deferred Ideas

- Per-request App Attest assertions for M2+ sensitive actions (ruled out — authorizationKey ECDSA covers it)
- Time-based re-attestation every 90 days (ruled out in D-04)
- App Attest entitlement / provisioning profile management UX (dev-team process, not app code)
- Real Face ID prompt in CI via xcrun simctl (ruled out — undocumented on physical iPhone)
- Multi-user attestation keys (ruled out — not an M1 use case)
- Attestation telemetry dashboard (belongs in observability phase)
