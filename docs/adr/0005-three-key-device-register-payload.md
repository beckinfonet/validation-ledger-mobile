# ADR 0005: Three-key /device/register payload — deviceKey + authorizationKey + attestedKey

**Date:** 2026-04-22
**Status:** Accepted
**Supersedes:** — extends ADR 0004 (two-key pattern)
**Superseded by:** — (current)

## Context

Phase 4 DEV-04 introduces Apple App Attest to the device-registration flow. The Phase 2
`/device/register` payload already carries **two** Secure-Enclave-backed public keys — `deviceKey`
(DEV-01, `.devicePasscode` ACL) for device identity and `authorizationKey` (DEV-02,
`.biometryCurrentSet` ACL) for sensitive-action signing (ADR 0004). DEV-04 adds a **third**
credential: the App Attest `attestedKeyId` + CBOR-encoded `attestationObject` pair.

D-02 (CONTEXT.md):

> `/device/register` payload carries **three distinct keys**, each with a distinct role:
>
> 1. `deviceKey` SPKI (existing DEV-01, `.devicePasscode` ACL) — device identity
> 2. `authorizationKey` SPKI (existing DEV-02, `.biometryCurrentSet` ACL) — sensitive-action signing
> 3. `attestedKeyId` + `attestationObject` (new DEV-04, App Attest) — Apple-device-authenticity proof
>
> ADR 0004 (two-key Secure Enclave pattern) extends to a new **ADR 0005** documenting the
> three-key registration payload and the distinct roles.

App Attest is the **only** way to bind a device-held keypair to hardware attestation that
Apple's backend will sign. `DCAppAttestService` manages its own Secure-Enclave keypair opaquely
— the private key is never exposed, and the framework refuses to reuse an existing
`deviceKey` / `authorizationKey` as the attestation key. Any attempt to "consolidate" attestation
onto one of the existing two keys fails at the framework boundary (see 04-RESEARCH.md
"Don't Hand-Roll" table). Three keys for three distinct roles is not a choice — it is the
contract Apple enforces.

## Decision

The Phase 4 `/device/register` request body carries three independent credentials:

- **`deviceKey` SPKI** — device identity.
  - ACL: `[.privateKeyUsage, .devicePasscode]` (ADR 0004).
  - Lifecycle: DEV-01 generate-once on first launch; preserved across logout;
    signs every authenticated request without biometric prompt.

- **`authorizationKey` SPKI** — sensitive-action signing.
  - ACL: `[.privateKeyUsage, .biometryCurrentSet]` (ADR 0004).
  - Lifecycle: DEV-02 generate-once on first launch; invalidates on biometric re-enrollment
    (Phase 3 SESS-03 re-bind flow); deleted from SE on logout (Phase 3 D-16).
  - Prompts biometric on every sign call (M2+ tender/accept/BOL endpoints).

- **`attestedKeyId` + `attestationObject`** — hardware attestation.
  - Managed by `DCAppAttestService` (DEV-04).
  - Lifecycle: D-01 once-per-install `generateKey()`; D-03 preserved across logout;
    D-04 regenerated ONLY on backend triggers (`attestationInvalid` / `nonceExpired` /
    `keyCompromised`).
  - `attestedKeyId` persists in Keychain under `device.attestedKeyId` with
    `.afterFirstUnlockThisDeviceOnly` accessibility. The private key material is SE-held
    and framework-opaque — we store only the identifier.

Per D-09, `/device/register` always carries an explicit `attestationStatus` enum with six
values (`attested | unsupported | entitlementMissing | quotaExceeded | simulatorBypass | error`).
When `attestationStatus != .attested`, `attestedKeyId` + `attestationObject` are omitted from
the payload. Per D-12, the response carries a `trustTier` (`hardwareAttested | softwareOnly`)
that drives the Limited Trust Mode banner (Plan 08).

## Consequences

### Positive

- **Hardware-rooted proof of identity.** An attacker cannot forge `attestationObject` without
  the SE-held private key; Apple's backend signs the root of trust.
- **Trust tier is server-side policy (D-12).** Future tiers (`attestedUnverified`, `revoked`, ...)
  can be added without client releases — the backend decides, the client renders.
- **Rate-limit friendly.** D-01's once-per-install discipline and D-03's logout-preservation
  invariant together ensure `DCAppAttestService.generateKey()` is called at most once per
  install under normal operation, minimizing exposure to Apple's undocumented quota
  (RESEARCH Pitfall 2).
- **Backwards-compatible wire format.** `attestedKeyId` + `attestationObject` are optional on
  the request; a Phase 3 client talking to a Phase 4 backend still works.

### Negative

- **Undocumented Apple rate limit.** `DCAppAttestService.generateKey()` contributes to an
  undocumented per-bundle-id quota (RESEARCH Pitfall 2). Quota exhaustion surfaces as the
  ambiguous `DCError.Code.serverUnavailable`, which our graceful-skip contract (D-09)
  interprets as `quotaExceeded`.
- **Entitlement provisioning dependency.** The `validationLedger.entitlements` file must
  embed `com.apple.developer.devicecheck.appattest-environment`, and the provisioning profile
  must include the App Attest capability. A mis-provisioned build surfaces as
  `DCError.Code.featureUnsupported` (RESEARCH Pitfall 3).
- **Apple-framework dependency.** Phase 4 is forever bound to `DCAppAttestService` — there is
  no equivalent open implementation. Apple deprecating or changing the framework forces a
  major rewrite.

### Acknowledged but NOT addressed

- **Per-request App Attest assertions for M2+ sensitive actions** (tender / accept / BOL).
  Deferred per D-07 — the M1 cadence is registration + 24h heartbeat only. If the M2+ threat
  model needs per-request assertions, `authorizationKey` ECDSA signatures will be augmented,
  not replaced.
- **Attestation telemetry dashboard.** Surfacing `attestationStatus` distribution across the
  fleet is deferred to an observability phase; D-13's device CI coverage is the M1 signal.

## Alternatives Considered

1. **Reuse `deviceKey` as the attestation key.** REJECTED — `DCAppAttestService` owns its
   own SE keypair opaquely and refuses to import an external SecKey. No API exists to
   bridge Phase 2's `deviceKey` into App Attest.
2. **Per-request attestation assertion on every M1 endpoint.** REJECTED per D-07 — M1 cadence
   is registration + heartbeat only; per-request assertions burn Apple's undocumented quota
   without adding signal beyond what `authorizationKey` ECDSA signatures already provide
   (which cover the M2+ sensitive-action per-request integrity requirement).
3. **Client-generated challenge (nonce + timestamp hashed locally).** REJECTED per D-05 —
   backend owns the challenge semantics; only the server can validate its own challenges are
   authentic. Client-side challenge generation defeats the nonce's replay-protection purpose.
4. **Two-key design with attestation piggy-backing on `authorizationKey`.** REJECTED — Same
   as (1), framework ownership prevents this. Also collides with the biometric-current-set
   invalidation: re-enrollment would lose attestation proof alongside authorization.

## Operational Notes

- **Re-attestation is backend-driven** (D-04). The client never self-rotates on a schedule.
  On `attestationInvalid` / `nonceExpired` / `keyCompromised` error codes, the client calls
  `AttestationService.clearPersistedKeyId()`, then the next `/device/register` triggers a
  fresh `generateKey()` + attestation cycle. See `docs/attestation-rotation.md`.
- **DEBUG-only "Re-attest now" path** (Plan 07). The DevMenu row calls
  `clearPersistedKeyId()` + fires a one-off `/device/register` without waiting for a backend
  trigger — lets engineers exercise the rotation path locally.
- **Logout preserves `attestedKeyId`** (D-03). `LogoutService` does NOT call
  `clearPersistedKeyId()`. Same device + same install = same attestation across login
  sessions. Mirrors the `deviceKey` and `installUUID` preservation pattern.

## References

- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-CONTEXT.md` D-01 through D-12
- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-RESEARCH.md` Pattern 1 (lines 283-395),
  Pitfall 2 (lines 594-600), Pitfall 3 (lines 602-608)
- `.planning/REQUIREMENTS.md` DEV-04
- `docs/adr/0004-secure-enclave-two-key-pattern.md` (two-key ACL + lifecycle baseline)
- `docs/attestation-rotation.md` (backend-trigger + DEBUG manual re-attest runbook)
- Apple — [DeviceCheck: Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- Apple — [`com.apple.developer.devicecheck.appattest-environment`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment)
