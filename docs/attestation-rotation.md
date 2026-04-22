# Attestation Rotation Runbook

**Status:** ACTIVE — Phase 4 DEV-04 runbook. Review when backend emits `attestationInvalid` /
`nonceExpired` / `keyCompromised` error codes.
**Canonical file to edit during rotation:** `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift`
(clearPersistedKeyId → regenerate on next /device/register)

## Why Client-Self-Rotation Is Forbidden

App Attest's `DCAppAttestService.generateKey()` is gated by an **undocumented per-bundle-id
rate limit** enforced by Apple's attestation servers. Community reports indicate that
quota exhaustion surfaces ambiguously as `DCError.Code.serverUnavailable` (sometimes
`unknownSystemFailure`), with no published SLA for quota increases and no retry-safe backoff
window (see `04-RESEARCH.md` Pitfall 2, lines 594-600).

A client that self-rotates on a schedule — e.g. "regenerate the attestation key every 90 days"
— burns quota on every installed device every 90 days regardless of server need. Multiplied
across the user fleet, this consumes the budget for legitimate bad-device replacements and
for new-install growth. Apple's published mitigation for quota pressure is "gradually onboard
users over 30 days"; the client has no room to spend quota on speculative rotation.

D-04 (CONTEXT.md) codifies the posture: **the server owns rotation policy**. The client only
regenerates when the backend explicitly asks — because only the backend can see the fleet-wide
signal that a rotation is warranted (compromised root, revocation event, key-attestation
invalidation).

## `attestedKeyId` Regeneration Procedure

1. **Backend emits one of three error codes** on `/device/register` or `/device/heartbeat`:
   - `attestationInvalid` — the stored `attestedKeyId` no longer validates against the
     attestation object. Usually means Apple-side state drift, a stale assertion, or a
     replay attempt.
   - `nonceExpired` — the challenge used to generate the last assertion is past its
     server-side TTL. Reissue with a fresh challenge.
   - `keyCompromised` — backend has flagged this `attestedKeyId` as potentially compromised
     (see "Emergency Revoke Path" below).
2. **Client receives the error** at its network call site (the `APIClient.send` path used by
   Phase 4 heartbeat + register flows).
3. **Client calls `AttestationService.clearPersistedKeyId()`**. This deletes the
   Keychain entry under `device.attestedKeyId` (see `KeychainKey.attestedKeyId`). The
   `lastHeartbeatAt` entry is preserved — the next heartbeat will overwrite it with a fresh
   timestamp.
4. **On the next `/device/register` call**, `AttestationService.generateKeyIfNeeded()` sees an
   absent Keychain entry and calls `DCAppAttestService.generateKey()` — producing a fresh
   `attestedKeyId` and, via a fetch-fresh-challenge-then-`attestKey()` call, a new
   `attestationObject`.
5. **Register response** carries a fresh `trustTier` (per D-12); the Limited Trust Mode
   banner updates accordingly (Plan 08).

> **Wire-format note.** The three canonical trigger codes above are notional as of the Phase 4
> planning checkpoint (RESEARCH Open Question 1). Coordinate with the backend team before
> Phase 4 execution to confirm the exact wire-format field name. Until confirmed, the client
> emits `AttestationError.underlying(NSError)` for any server-reported attestation error and
> the translation to `clearPersistedKeyId()` is wired as a single catch-all path in
> `DCAppAttestAttestationService` (Plan 03).

## Emergency Revoke Path

If backend detects a fleet-wide or high-risk attestation compromise:

1. Backend returns `keyCompromised` on `/device/heartbeat` for affected devices.
2. Client response is **silent** — `clearPersistedKeyId()` fires without user notification
   (RESEARCH Open Question 4 — no user UI for attestation revocation in M1). The next
   cold-boot or `didBecomeActive` triggers `/device/register`, which regenerates the key
   automatically.
3. Fleet-wide compromise: backend can return `keyCompromised` on every connected device;
   within one heartbeat cycle (24h max, typically faster on cold-boot), the entire fleet
   rotates without user intervention.
4. Backend is expected to log + monitor per-device `keyCompromised` emissions; a sudden
   spike indicates either legitimate fleet-wide rotation or a bug in the backend verification
   logic. Operational dashboards should alarm on `keyCompromised` rate > baseline.

## Manual Re-attestation (DEBUG-only)

The Phase 4 DevMenu "Re-attest now" row (Plan 07) triggers the same
`clearPersistedKeyId()` + forced `/device/register` path without waiting for a backend
trigger. It exists to let engineers exercise the rotation code path locally during
development — e.g. against a `MockURLProtocol` fixture that returns an
`attestationInvalid` response, or to verify the UI behaves correctly when a fresh attestation
cycle runs.

DEBUG builds only. The row is compiled out of Release (the entire `DevMenuViewController`
file is `#if DEBUG`-gated at top), so there is no way to invoke this path in a shipping
build — rotation in production is strictly backend-driven.

## CI Checks

`AppAttestRoundTripTests` (Plan 09, `validationLedgerDeviceTests/`) exercises the
re-attestation trigger on physical device CI via a `MockURLProtocol`-driven
`attestationInvalid` response. The test asserts that after the mock 4xx response, the
Keychain entry at `device.attestedKeyId` is deleted and a subsequent `/device/register`
call produces a fresh `generateKey()`-derived identifier.

Per D-13 + D-15, this test runs on every merge to `main` (D-16 branch-protection status
check) and retries once on flake (D-15).

## Related

- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-CONTEXT.md` D-04
- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-RESEARCH.md` Open Q1 + Open Q4 (lines ~800-806)
- `.planning/REQUIREMENTS.md` DEV-04
- `docs/adr/0005-three-key-device-register-payload.md` (three-key payload rationale)
- `docs/adr/0004-secure-enclave-two-key-pattern.md` (Phase 2 two-key baseline)
- Apple — [Assessing the fraud risk of a new device](https://developer.apple.com/documentation/devicecheck/assessing-the-fraud-risk-of-a-new-device)
