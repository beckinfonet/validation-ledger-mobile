# Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the two Phase 4 gaps surfaced by `v1.0-MILESTONE-AUDIT.md`:

1. **Wire App Attest into the first-login path.** `OTPViewModel.verify()` STEP 5 currently hardcodes `attestationStatus: .unsupported` / `attestedKeyId: nil` / `attestationObject: nil` and never calls `AttestationService` (`OTPViewModel.swift:202-211`). DEV-04 / Phase 4 SC-1 require App Attest to fire on the **first successful OTP verify**, with the assertion carried in the `/device/register` payload. Phase 6 inserts `generateKeyIfNeeded()` → `GET /device/challenge` → `attestKey()` before `/device/register` and sends the real attestation fields.

2. **Consume the discarded `/device/register` response.** The response (which carries `trustTier`, D-12) is thrown away with `_ = try await ...`. Phase 6 captures it and propagates `trustTier` so `AppSession.trustTier` is correct on the first role shell — closing the broken OTP-verify → `/device/register` → `AppSession.trustTier` flow and Phase 4 `deferred-items.md` #2.

3. **Produce a real `04-VERIFICATION.md`.** Phase 4 was never run through verification — the missing report is what hid gap #1. Phase 6 retroactively verifies Phase 4 against current code.

Plus three audit fixes the user folded into scope (WARNING-1, the dead Profile CTA, WARNING-2).

**In scope:**
- `OTPViewModel` first-login attestation orchestration (`generateKeyIfNeeded` → challenge → `attestKey` → real `/device/register` payload)
- `trustTier` Keychain persistence + the role-shell consumer that seeds `AppSession`
- Removal of the DEBUG `AppContainer.uiTestTrustTierOverride` seam
- WARNING-1: refresh Keychain `kycStatus` after a successful `GET /kyc/status`
- Profile "Continue" CTA: wire `onVerified` in `AppContainer.makeKYCStatusScreen()`
- WARNING-2: make `AppSession.trustTier` observable so `LimitedTrustBannerView` re-renders/removes on change
- Retroactive `04-VERIFICATION.md` (full Phase 4 re-verification) + ticking the roadmap `04-10` checkbox

**Out of scope (not this phase):**
- New attestation cadences (per-request assertions, time-based re-attest) — locked out by Phase 4 D-04/D-07; M2+
- Backend changes — iOS stays mock-backed per the M1 convention
- The other audit tech-debt items (CR-02b, CR-03, install-UUID `try?`, etc.) — unrelated pre-Phase-6 debt
- Nyquist gap-fills for Phase 1 / Phase 2 — handled separately via `/gsd-validate-phase`

</domain>

<decisions>
## Implementation Decisions

> Decision IDs below are **Phase 6-local** (`D6-NN`). References to `D-NN`
> without the `6` prefix are **locked Phase 4 decisions** (see `04-CONTEXT.md`)
> and must NOT be re-litigated.

### trustTier hand-off across the post-OTP container swap

**Problem found while scouting:** `OTPViewModel` runs inside the *auth-phase*
`AppContainer`. On successful verify, `onAuthenticated(role)` bubbles up and
`SceneDelegate.presentRoot(.role(role))` builds a **fresh** `AppContainer` with
a fresh `AppSession(trustTier: .softwareOnly)` (ADR 0002 abrupt-replace). The
role tab bar is wrapped by `wrapWithLimitedTrustBanner(trustTier: container.session.trustTier)`
at construction. A `trustTier` written into the auth-phase container's
`AppSession` is therefore discarded — the banner would always show
`.softwareOnly` on the first role shell.

- **D6-01:** Propagate first-login `trustTier` via **Keychain persistence**.
  `AttestedKeyStore` gains `readTrustTier()` / `writeTrustTier(_:)` alongside the
  existing `attestedKeyId` + `lastHeartbeatAt` accessors. `OTPViewModel` writes
  `trustTier` from the `/device/register` response; the role-shell `AppContainer`
  reads it at construction and seeds `AppSession`. Chosen over threading it
  through the `onAuthenticated` callback chain (would churn ~4 signatures, no
  cold-boot benefit) and over a post-OTP heartbeat (extra round-trip, banner
  flicker). Bonus: the cold-boot `.restored` path can also seed `AppSession`
  from the persisted tier, so the banner is correct from frame 1 — before the
  cold-boot heartbeat lands.

- **D6-02:** The `trustTier` Keychain item is **preserved across logout** — it
  lives in the attestation key group with `attestedKeyId` / `lastHeartbeatAt`
  (NOT a member of `KeychainScope.session`, so `KeychainStore.deleteAll(under: .session)`
  does not wipe it). It is a device-attestation fact, not session data; the
  next login's `/device/register` overwrites it anyway. Follow the
  `device.attestedKeyId` raw-value naming convention (e.g. `device.trustTier`).

- **D6-03:** **Remove** the DEBUG-only `AppContainer.uiTestTrustTierOverride`
  seam. The audit calls it out as papering over the missing consumer. With the
  real consumer wired, the mock `/device/register` fixture's `trust_tier` (set
  by `MockOTPRoleFixtureRegistry` via `-MockOTPTrustTierForUITest`) flows
  naturally through `OTPViewModel` → Keychain → `AppSession` → banner. XCUITests
  exercise the genuine path; the `AppContainer.uiTestTrustTierOverride` static
  and its read sites (`AppContainer.swift:~395`, `SceneDelegate.swift:~187`) are
  deleted. The `-MockOTPTrustTierForUITest` launchArg + `MockOTPRoleFixtureRegistry`
  fixture path stay — they drive the real path.

### App Attest failure posture at first login

The first-login sequence inserts before `/device/register`:
`generateKeyIfNeeded()` → `GET /device/challenge` → `attestKey(keyId:challenge:)`.

- **D6-04:** **Permanent failures are already handled — do not change them.**
  A `generateKeyIfNeeded()` that returns a non-`.attested` status
  (`.unsupported`, `.entitlementMissing`, `.quotaExceeded`, `.error`) takes the
  Phase 4 D-09 graceful-skip path: send that status, omit `attestedKeyId` +
  `attestationObject`. `.simulatorBypass` is treated like `.attested` (mirrors
  the heartbeat path in `SceneDelegate.performHeartbeatIfNeeded`).

- **D6-05:** **Transient failures degrade and continue — login is never
  blocked.** When the device *can* attest but a transient failure hits — the
  `GET /device/challenge` request errors, or `attestKey()` throws (Apple's App
  Attest service unreachable / rate-limiting) — log a warning, set
  `attestationStatus: .error`, omit the attestation fields, and **still POST
  `/device/register`**. Login completes; the backend returns `.softwareOnly`;
  the limited-trust banner shows (honest about the device's current state); the
  Phase 4 D-07 24h heartbeat / next cold boot re-attempts attestation. No extra
  inline retry on a generic transient failure. Matches Phase 4 D-09 +
  Phase 4 SC-2 ("registration proceeds with a logged warning... no user-facing
  error").

- **D6-06:** Phase 4 **D-08 applies**: if `/device/register` itself returns the
  `challengeExpired` server error code, refetch a fresh challenge and retry the
  register **once**. `challengeExpired` is a deterministic "your challenge is
  stale, get a new one" signal — distinct from the generic transient failure in
  D6-05, which degrades immediately.

  > **Resolved 2026-05-18 (post-research):** research found NO existing
  > `challengeExpired` production handling — `AttestationErrorResponseInterceptor`
  > covers `attestationInvalid` / `nonceExpired` / `keyCompromised` only. D6-06 is
  > therefore genuinely **new code** in the first-login path (challengeExpired
  > detection + challenge refetch + register retry-once), unit-tested with an
  > injected fixture — NOT "unchanged" wiring. The decision stands: build it.

- **D6-07:** PII discipline (Phase 4 04-PATTERNS.md Pattern A) holds: raw
  `attestationObject` / `attestedKeyId` / challenge bytes and `NSError.userInfo`
  never enter `Logger` fields — only the event name + status enum rawValue.

### Folded audit fixes

- **D6-08 (WARNING-1):** Refresh Keychain `kycStatus` after a successful
  `GET /kyc/status`. Today `kycStatus` is written only at OTP-verify
  (`OTPViewModel.swift:156-164`); a user who OTP-verifies non-verified,
  completes KYC **in-session**, then force-quits is misrouted back into the KYC
  hard gate on cold boot (the fail-closed `SessionRestoreProbe` sees a stale /
  absent value). The KYC-status fetch path must write the fresh status under
  `.kycStatus` with the same `.afterFirstUnlockThisDeviceOnly` accessibility, so
  the cold-boot probe routes on current truth. Affects SESS-01 / KYC-01 / D-13.

- **D6-09 (Profile "Continue" CTA):** Wire `onVerified` in
  `AppContainer.makeKYCStatusScreen()` (`AppContainer.swift:~178-185`). The
  Profile-entry factory omits the `onVerified` callback, leaving a dead button.

  > **Resolved 2026-05-18 (post-research):** `onVerified` must **dismiss / pop
  > the KYC status screen back to the Profile tab** — NOT a literal copy of
  > `KYCCoordinator.pushStatus()`'s post-submit role-shell routing, which is
  > nonsensical from a Profile entry already inside the role shell. The fix is a
  > Profile-context dismissal, not a coordinator handoff.

- **D6-10 (WARNING-2):** Make `AppSession.trustTier` **observable** so
  `LimitedTrustBannerView` re-renders — appears on downgrade, disappears on
  upgrade — whenever the heartbeat (or first-login consumer) mutates the tier,
  without waiting for the next root-swap. The banner stays non-dismissible
  (Phase 4 D-11); the change is shown **without animation**, consistent with the
  ADR 0002 / D-10 abrupt-replace mandate. Observation mechanism (NotificationCenter
  post vs. a closure/observer on `AppSession`) is Claude's discretion — both fit
  existing patterns (`.sessionDidInvalidate` notifications; `onStateChange`
  closures). `AppSession` stays `@MainActor`.

### Phase 4 verification close-out

- **D6-11:** `04-VERIFICATION.md` is produced as a **tracked task in Phase 6** —
  the final plan/wave verifies Phase 4 against the now-fixed code and writes +
  commits `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md`.
  It MUST run last (Phase 4 SC-1 only passes once D6-01..D6-07 land).

- **D6-12:** The report is a **full Phase 4 re-verification** — all three
  Phase 4 success criteria (SC-1 App Attest at first login, SC-2 graceful skip,
  SC-3 device-CI gate) + DEV-04 + CI-03 — not just the closed gap. Phase 6 also
  ticks the still-unchecked roadmap `04-10` checkbox (`04-10-SUMMARY.md` already
  exists; the box was never checked).

### Claude's Discretion

- The exact factoring of the first-login attestation orchestration — inline in
  `OTPViewModel.verify()` STEP 5 vs. a small shared helper that both the
  first-login path and `SceneDelegate.performHeartbeatIfNeeded` could call. The
  planner decides; note the heartbeat path already inlines an equivalent
  `generateKeyIfNeeded` → challenge → POST dance, so a shared seam is optional,
  not required.
- `OTPViewModel`'s DI surface growth — it needs `AttestationService` and a path
  to write `trustTier` (likely `AttestedKeyStore` or the `KeychainStore` it
  already holds). Planner decides the initializer shape; `AuthCoordinator.swift:51`
  is the single construction site.
- Whether the `.settingUp(progress:total:)` step total/labels change to reflect
  the added attestation steps, or the attestation work folds silently into the
  existing STEP 5 slot. Follow the M1 minimal-UI principle.
- WARNING-2 observation mechanism (see D6-10).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope source (READ FIRST)

- `.planning/v1.0-MILESTONE-AUDIT.md` — the audit that defines this phase. The
  `gaps:` frontmatter block (DEV-04 / CI-03 partials, the integration findings,
  WARNING-1 / WARNING-2), the "Critical Gaps" section, and the "Integration
  Findings" section are the literal scope of Phase 6.

### Locked prior-phase decisions (do NOT re-litigate)

- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-CONTEXT.md` —
  Phase 4 decisions D-01..D-16. Especially D-01 (generateKey once per install),
  D-05 (`GET /device/challenge`), D-06 (`clientDataHash = SHA-256(challenge)`),
  D-08 (challengeExpired refetch+retry-once), D-09 (graceful-skip
  `attestationStatus` enum + omission rule), D-12 (backend-driven `trustTier`).
- `.planning/phases/04-app-attest-physical-device-ci-hardening/04-PATTERNS.md` —
  Pattern A: PII discipline for attestation logging.
- `.planning/phases/04-app-attest-physical-device-ci-hardening/deferred-items.md` —
  item #2 is the `trustTier` consumer follow-up Phase 6 closes.
- `docs/adr/0005-three-key-device-register-payload.md` — the three-key
  `/device/register` payload contract (`deviceKey` + `authorizationKey` +
  `attestedKeyId`/`attestationObject` + `attestationStatus`).
- `docs/adr/0004-secure-enclave-two-key-pattern.md` — the SE two-key pattern
  ADR 0005 extends.
- `docs/adr/0002-role-coordinator-swap-pattern.md` — the abrupt-replace
  root-swap mandate behind the container-swap problem D6-01 solves and the
  no-animation rule in D6-10.

### Requirements & Roadmap

- `.planning/REQUIREMENTS.md` — DEV-04, CI-03.
- `.planning/ROADMAP.md` — Phase 6 entry (lines ~194-203) + Phase 4 goal and
  three success criteria (lines ~108-116) that `04-VERIFICATION.md` checks.

### Existing code integration points

- `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` — STEP 5
  (`:187-218`) is the wiring site; the stale comment at `:189-193` is the
  promise this phase fulfills. `kycStatus` write at `:156-164` is the WARNING-1
  reference point.
- `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift:51` — the
  sole `OTPViewModel(...)` construction site (DI changes land here).
- `validationLedger/Core/Attestation/AttestationService.swift` — protocol;
  `generateKeyIfNeeded()` + `attestKey(keyId:challenge:)` are the methods the
  first-login path calls. Impls: `DCAppAttestAttestationService`,
  `SimulatorBypassAttestationService`.
- `validationLedger/Core/Attestation/AttestedKeyStore.swift` — gains
  `readTrustTier()` / `writeTrustTier(_:)` (D6-01).
- `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — add the
  `device.trustTier` key in the attestation group (NOT `KeychainScope.session`).
- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` —
  unchanged contract; `.Response.trustTier` is the value to capture.
- `validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` —
  the `GET /device/challenge` call the first-login path adds.
- `validationLedger/App/AppSession.swift` — `trustTier` becomes observable
  (D6-10); role-shell `AppContainer` seeds it from Keychain (D6-01).
- `validationLedger/App/AppContainer.swift` — `uiTestTrustTierOverride` removed
  (D6-03, `:~66-72`, `:~390-397`); `AppSession` construction seeds from Keychain;
  `makeKYCStatusScreen()` (`:~178-185`) gets the `onVerified` wiring (D6-09).
- `validationLedger/App/SceneDelegate.swift` — `performHeartbeatIfNeeded`
  (`:~568-651`) is the reference orchestration for the first-login path;
  `:~172-187` is a `uiTestTrustTierOverride` removal site (D6-03).
- `validationLedger/App/AppCoordinator.swift:~83` — `wrapWithLimitedTrustBanner`
  call site for WARNING-2.
- `validationLedger/Core/Networking/Mock/` — `MockOTPRoleFixtureRegistry` +
  the `/device/register` / `GET /kyc/status` fixtures the XCUITests drive.

### Operational docs

- `docs/attestation-rotation.md` — re-attestation playbook; reconfirm it still
  matches the first-login path.
- `docs/ci.md` — device-pipeline section relevant to the CI-03 verification.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`SceneDelegate.performHeartbeatIfNeeded(container:)`** — the heartbeat path
  already does `generateKeyIfNeeded()` → `DeviceChallengeEndpoint` →
  `generateAssertion()` → POST → `session.trustTier = response.trustTier`. The
  first-login path is the same shape with `attestKey()` + `DeviceRegisterEndpoint`
  instead. Direct template (and a candidate shared seam — D6-discretion).
- **`AttestedKeyStore`** — `read/writeAttestedKeyId` + `read/writeLastHeartbeatAt`
  are the exact pattern `read/writeTrustTier` follows; `TrustTier` is a
  `RawRepresentable` enum so it round-trips through Keychain as a string.
- **`AttestationService` dual-impl** (`DCAppAttest...` / `SimulatorBypass...`,
  selected in `AppContainer.init` via `#if DEBUG && targetEnvironment(simulator)`)
  — `OTPViewModel` consumes `container.attestationService`; no new selection logic.
- **`MockOTPRoleFixtureRegistry` + `-MockOTPTrustTierForUITest`** — already sets
  the mock `/device/register` response's `trust_tier`; with D6-03 this becomes
  the *only* trustTier seam for XCUITests.
- **`OTPViewModel.retryRegister()`** — re-runs `verify()` end-to-end; idempotent
  because `generateKeyIfNeeded()` is once-per-install (D-01), `attestKey` is
  re-callable, and `/device/register` is Idempotency-Key-protected (NET-04).

### Established Patterns

- **ADR 0002 abrupt-replace** — every `presentRoot` builds a fresh `AppContainer`
  + `AppSession`. This is *why* trustTier needs a cross-swap channel (D6-01).
- **`KeychainScope.session` vs. attestation keys** — `KeychainKey.swift` already
  documents that `attestedKeyId` is deliberately NOT in `.session` scope
  (D-03 preserve-across-logout). `device.trustTier` joins that group (D6-02).
- **D-09 omission rule** — `JSONEncoder` drops `Optional.none`, so omitting
  `attestedKeyId`/`attestationObject` on a non-`.attested` status is automatic.
- **Fail-closed routing** — `SessionRestoreProbe` / `OTPViewModel` route any
  non-"verified" `kycStatus` (incl. `nil`) to the KYC gate. WARNING-1 (D6-08)
  is a *correctness* fix to that same fail-closed logic, not a relaxation.

### Integration Points

- `OTPViewModel.verify()` STEP 5 — attestation orchestration + response capture.
- `AuthCoordinator.swift:51` — `OTPViewModel` DI surface.
- `AppContainer.init` — `AppSession` seeded from `AttestedKeyStore.readTrustTier()`.
- `AppCoordinator.roleCoordinator` / `wrapWithLimitedTrustBanner` — WARNING-2.
- Phase 4's `validationLedger(Device)Tests/Attestation/` suites — first-login
  attestation gets new RED tests; the device-CI lane already runs the surface.

</code_context>

<specifics>
## Specific Ideas

- New Keychain key raw value: `device.trustTier` (follows `device.attestedKeyId`).
- Transient first-login attestation failure → `attestationStatus: .error` on the
  `/device/register` payload (NOT a new status value — reuse D-09's `.error`).
- `04-VERIFICATION.md` lands at
  `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md`
  and verifies all 3 Phase 4 success criteria; Phase 6 ticks roadmap `04-10`.
- The `uiTestTrustTierOverride` removal is a deletion, not a deprecation — the
  `-MockOTPTrustTierForUITest` launchArg path stays and drives the real consumer.

</specifics>

<deferred>
## Deferred Ideas

- **Near-term re-attest after a degraded first login** — considered under D6-05;
  ruled out for this phase. A first login that degrades to `.softwareOnly` waits
  for the existing D-07 24h heartbeat / next cold boot to recover attestation.
  Adding a sooner retry scheduler is scope creep — revisit only if real fleet
  data shows long limited-trust windows.
- **Shared first-login/heartbeat attestation seam** — left as planner discretion
  (see Claude's Discretion). If a future phase adds a third attestation caller,
  extracting the orchestration becomes worthwhile.
- **Nyquist gap-fills for Phase 1 (partial) and Phase 2 (missing)** — flagged by
  the same audit; the audit itself recommends `/gsd-validate-phase 1` and
  `/gsd-validate-phase 2` rather than folding them into a phase.
- **Other audit tech-debt** (CR-02b PIIScrubber over-redaction, CR-03 force
  unwrap, `DeviceFingerprint` `try?` install-UUID, IN-02 wire-format skew, the
  `CameraPermissionViewController` product decision) — unrelated pre-Phase-6
  debt; not Phase 6 scope.

### Reviewed Todos (not folded)

_No pending todos matched Phase 6 scope (`todo.match-phase 06` → 0 matches)._

</deferred>

---

*Phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume*
*Context gathered: 2026-05-18*
