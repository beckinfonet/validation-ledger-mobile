# Phase 4: App Attest & Physical-Device CI Hardening - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Add the App Attest attestation path to device registration (DEV-04) and harden the on-device CI pipeline so Secure Enclave, Keychain biometric-bound items, and App Attest surfaces are actually exercised and gate merges to `main` (CI-03).

**In scope:**
- `Core/Attestation/` module that wraps `DCAppAttestService` (generateKey, attestKey, generateAssertion) with a testable protocol
- Extending `/device/register` request body with `attestationObject` + `attestedKeyId` + `attestationStatus`
- New `GET /device/challenge` endpoint contract + `MockURLProtocol` fixtures
- `validationLedgerDeviceTests/` target expanded to cover SE keypair generation, Keychain biometric-bound items, and App Attest round-trip
- `.github/workflows/ci-device.yml` upgrades: merge-block as required status check, single retry on failure, full security-surface test plan
- Cold-boot + 24h heartbeat via `generateAssertion()` against a new `/device/heartbeat` endpoint
- Non-dismissible "Limited trust mode" banner on the role shell when `trustTier != hardwareAttested`

**Out of scope (deferred to future phases):**
- Per-request App Attest assertions on M2+ sensitive actions (tender/accept/BOL) — attestation is registration + heartbeat only in M1
- KYC capture / upload (M1 Phase 5)
- Real backend integration — stays mock-backed per M1 convention
- App Attest entitlement provisioning management UX — dev-team process, not app code

</domain>

<decisions>
## Implementation Decisions

### App Attest Key Lifecycle

- **D-01:** `DCAppAttestService.generateKey()` is called exactly ONCE per install, on the first successful OTP verify after fresh install. The returned `attestedKeyId` is persisted in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. All subsequent `/device/register` calls (after cold-boot re-login, after logout+re-login, after force-quit) reuse the persisted `attestedKeyId`. Minimizes exposure to Apple's undocumented rate limit. Aligns with App Attest's per-install design.

- **D-02:** `/device/register` payload carries **three distinct keys**, each with a distinct role:
  1. `deviceKey` SPKI (existing DEV-01, `.devicePasscode` ACL) — device identity
  2. `authorizationKey` SPKI (existing DEV-02, `.biometryCurrentSet` ACL) — sensitive-action signing
  3. `attestedKeyId` + `attestationObject` (new DEV-04, App Attest) — Apple-device-authenticity proof
  ADR 0004 (two-key Secure Enclave pattern) extends to a new **ADR 0005** documenting the three-key registration payload and the distinct roles.

- **D-03:** `attestedKeyId` is **preserved across logout**. Logout's teardown (SESS-04) wipes the session token, clears `authorizationKey` ACL, tears down the role coordinator stack, but does NOT touch the `attestedKeyId` Keychain item. Same device + same install = same attestation. Mirrors the `deviceKey` lifecycle.

- **D-04:** Re-attestation is **backend-driven only**. Client never self-rotates on a schedule. On specific backend error codes — `attestationInvalid` / `nonceExpired` / `keyCompromised` — the client deletes the persisted `attestedKeyId`, calls `generateKey()` again, and re-submits `/device/register`. A **DEBUG-only** dev-menu entry exposes a manual "Re-attest now" button for testing the rotation path locally.

### Challenge / Assertion Protocol

- **D-05:** Challenge delivery uses a **dedicated `GET /device/challenge` endpoint**. Response body: `{ challenge: base64, expiresAt: ISO8601, nonce: string }`. Client calls it immediately before `attestKey()` or `generateAssertion()`, uses the challenge exactly once, discards it. Backend can rate-limit this endpoint independently. Easy to mock in `MockURLProtocol`.

- **D-06:** `clientDataHash = SHA-256(challenge)` — challenge only, no request body or endpoint path binding. Server's challenge already embeds nonce + timestamp + server-side signing-key rotation; replay protection is server-enforced. Matches Apple's reference sample code.

- **D-07:** Attestation cadence is **registration + per-session heartbeat**:
  - `attestKey()` fires once on first `/device/register` (registration proof)
  - `generateAssertion()` fires on **cold-boot re-login** (piggybacking on `SessionRestoreProbe` returning `.restored(role)` — the existing SESS-01 decision point) **AND** when `didBecomeActive` fires on a warm foreground and `lastHeartbeatAt` > 24h ago
  - Heartbeat posts to a new `POST /device/heartbeat` endpoint with `{ sessionToken, attestedKeyId, assertion }`
  - `lastHeartbeatAt` persists in Keychain alongside `attestedKeyId`
  - NO per-request assertions on M1 endpoints — sensitive-action per-request assertions deferred to M2+ if ever needed

- **D-08:** Challenge freshness: **single-use, immediate consumption**. Client fetches a challenge, uses it within seconds, submits the attestation/assertion. No client-side caching. If `/device/register` or `/device/heartbeat` fails with `challengeExpired`, client refetches a new challenge and retries **once**. Backend enforces a tight TTL (≤60s recommended).

### Graceful-Skip Contract

- **D-09:** `/device/register` payload always carries an **explicit `attestationStatus` enum** with five distinct values: `"attested" | "unsupported" | "entitlementMissing" | "quotaExceeded" | "simulatorBypass" | "error"`. When `attestationStatus != "attested"`, `attestationObject` + `attestedKeyId` fields are omitted. Each status maps to a distinct client path:
  - `unsupported` — `DCAppAttestService.isSupported == false` (pre-A10 / missing iOS version). Silent-log.
  - `entitlementMissing` — isSupported true but `generateKey()` returns `.featureUnsupported`. Log at **error** level (build-config bug in prod).
  - `quotaExceeded` — `generateKey()` returns the undocumented rate-limit error. Client applies backoff + retry with TTL.
  - `simulatorBypass` — `#if targetEnvironment(simulator)` path. Client emits a fixed fake attestation object. Backend in non-prod env accepts it.
  - `error` — catch-all for anything else. Log at error level with the underlying NSError.

- **D-10:** The `#if targetEnvironment(simulator)` simulator-bypass path emits a DEBUG-only fixed fake `attestationObject` + `attestedKeyId = "sim-bypass-{installUUID}"`. The mock backend's `/device/register` fixture recognizes this shape and accepts with `trustTier: "softwareOnly"`. Production builds never ship this code path (guarded by `#if DEBUG`, same pattern as Phase 2 `SoftwareKeyStore`).

- **D-11:** UX posture: **non-dismissible "Limited trust mode" banner** on the role shell whenever `trustTier != "hardwareAttested"`. Banner copy: "Limited trust mode — this device can't fully verify. Some features may be restricted." Permanent thin banner at the top of the tab-bar shell (above the role tabs). Honest with the user about the device's trust state. Localized at string-catalog time per CLAUDE.md i18n deferral (English-only for M1, structure ready for v2).

- **D-12:** Backend-driven trust tier: `/device/register` and `/device/heartbeat` return `{ registered: true, trustTier: "hardwareAttested" | "softwareOnly" }`. Client stores `trustTier` in session state (`AppContainer.session`). Client is a dumb enforcer — server decides the policy. Forward-compatible with future tiers (`attestedUnverified`, `revoked`, etc.) without client changes.

### Device CI — Coverage & Merge Policy

- **D-13:** Device pipeline runs the **full security surface** in `validationLedgerDeviceTests/`:
  1. `SecureEnclaveKeyStore` real-SE EC P-256 keypair generation + sign/verify round-trip (DEV-01/02)
  2. Keychain `.biometryCurrentSet` ACL item storage + retrieval behind a seeded `LAContext` (DEV-03 device path)
  3. `Core/Attestation` App Attest `attestKey` + `generateAssertion` round-trip against `MockURLProtocol`-driven `/device/challenge` + `/device/register` + `/device/heartbeat`
  4. Logout ACL clearing on SE keys (closes 3 of the 4 Phase 3 HUMAN-UAT items into CI coverage)

- **D-14:** Biometric-prompt tests use **seeded `LAContext` injected via `AppContainer`** — no real Face ID prompt in unattended CI. The seeded `LAContext` returns `.success` synchronously without evaluating hardware. Tests verify the Keychain ACL creation path, SE ACL-clearing path, and all code paths that assume a successful biometric. This is the standard iOS industry pattern; Apple does not provide a reliable automation hook for real Face ID prompts in unattended CI on physical devices.

- **D-15:** Flakiness handling: **retry once, then fail**. On a single test failure, the pipeline reruns only that failed test once. If it passes on retry, pipeline proceeds and logs a "flaky-passed" warning (surfaced to a Slack channel for engineer investigation). If it fails twice, the workflow fails. Balances App Attest rate-limit pressure (retries consume quota) against quarantine-forever anti-patterns. Quarantine is explicit: engineer adds a `.flaky` annotation in source code to exclude a test from the gate, with a tracking issue required.

- **D-16:** Merge gate: **device pipeline is a required GitHub branch-protection status check on `main`**. A red device pipeline blocks merge. Even admins need explicit manual override via GitHub UI. Satisfies CI-03's literal intent ("blocks merges that break any of them"). Pairs with D-15 to reduce false-positive blocks.

### Claude's Discretion

- Exact Swift protocol surface for `AttestationService` (protocol members, associated types) — planner decides based on testability patterns established in Phase 2 (`KeyStoreProtocol`, `SessionLockService`).
- Dev-menu "Re-attest now" button placement within `DevMenuViewController` — existing DEBUG-only rows follow a consistent pattern.
- Error-code enum value names on the backend side — coordinate with backend team during Phase 4 execution; iOS emits a generic `AttestationError` case with the server's raw code string.
- Exact banner visual styling (height, background color, icon) — follow the M1 "minimal UI" principle; use system-colored warning tone.
- `/device/heartbeat` HTTP method and idempotency-key usage — researcher confirms against NET-04 idempotency interceptor conventions.

### Folded Todos

_None — no pending todos matched Phase 4 scope._

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architectural Decisions (ADRs)

- `.planning/adr/0004-two-key-secure-enclave-pattern.md` — Existing two-key SE pattern (deviceKey + authorizationKey). Phase 4 extends this; write new **ADR 0005** documenting the three-key `/device/register` payload.

### Requirements & Roadmap

- `.planning/REQUIREMENTS.md` lines 62 (DEV-04), 119 (CI-03), 18 (FOUND-04 — CI pipeline split rationale), 55-64 (AUTH + DEV carryovers)
- `.planning/ROADMAP.md` lines 92-100 (Phase 4 goal + 3 success criteria)

### Prior Phase Context

- `.planning/phases/02-networking-contract-device-keys/02-CONTEXT.md` — DEV-01/02/03/05 decisions, two-key SE pattern rationale, preflight-SE refuse-launch policy
- `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-CONTEXT.md` — SessionRestoreProbe cold-boot pattern, SessionLockService, AppContainer DI surface
- `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-VERIFICATION.md` — Phase 3 HUMAN-UAT items (3 of 4 are retired by Phase 4 D-13 device CI coverage)

### Existing Code Integration Points

- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — Request body extended with `attestationObject` + `attestedKeyId` + `attestationStatus`
- `validationLedger/Core/Networking/Mock/` — MockURLProtocol fixtures extended with `/device/challenge` + `/device/heartbeat` + attestation-aware `/device/register` variants
- `validationLedger/Core/Identity/DeviceFingerprint.swift` — Already registers `installUUID` (DEV-05); `attestedKeyId` storage can follow the same Keychain-persistence pattern
- `validationLedger/App/AppContainer.swift` — New `attestationService: any AttestationService` property added; `preflightSecureEnclave()` pattern mirrored for `preflightAttestationEntitlement()`
- `validationLedger/App/SceneDelegate.swift` — Cold-boot heartbeat fires inside `presentRoot(.role(role))` after `SessionRestoreProbe.restored` returns; didBecomeActive observer (plan 03-13) extended to check `lastHeartbeatAt` age

### Operational Docs

- `docs/ci.md` — Device pipeline already documented; Phase 4 plans must update the "Device Pipeline" section with the Phase 4 test plan + merge-gate behavior
- `docs/cert-rotation.md` — Existing cert-rotation runbook; consider a companion `docs/attestation-rotation.md` for the re-attestation playbook
- `.github/workflows/ci-device.yml` — Existing device workflow; Phase 4 upgrades it for required-status-check + single-retry behavior
- `validationLedger/validationLedger.entitlements` (to be created) — App Attest entitlement provisioning — coordinate with dev-team signing workflow

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`AppContainer` initializer-DI pattern** (Phase 1/2) — `attestationService: any AttestationService` slots in alongside `biometricService`, `sessionLock`, `logoutService`
- **`KeyStoreProtocol` dual-impl pattern** (Phase 2) — `SecureEnclaveKeyStore` + `SoftwareKeyStore` via `#if DEBUG && targetEnvironment(simulator)`. `AttestationService` mirrors this: `DCAppAttestAttestationService` + `SimulatorBypassAttestationService`.
- **`AppContainer.preflightSecureEnclave()` + `RefuseLaunchWithoutSecureEnclaveTests`** — Template for a `preflightAttestationEntitlement()` that logs (not refuses) when entitlement is missing, per D-09 `entitlementMissing` status.
- **`MockURLProtocol` fixture registry** (Phase 2) — Seed fixtures for `/device/challenge` + `/device/heartbeat` + attestation-aware `/device/register` success/failure variants
- **`SessionRestoreProbe`** (Phase 3 Plan 11) — Cold-boot path where heartbeat fires on `.restored(role)`
- **`SceneDelegate.handleDidBecomeActive`** (Phase 3 Plan 13 / 03-13) — Already observes `UIApplication.didBecomeActiveNotification`; extends to check `lastHeartbeatAt` age
- **`DevMenu`** (Phase 1 Plan 05) — DEBUG-only shake-gesture menu; extend with "Re-attest now" row
- **`LogExporter`** (Phase 1 Plan 04) — Already exports structured logs; attestation status logs flow through the existing Logger

### Established Patterns

- **PII-scrubbed structured logging** — `attestationObject` and `attestedKeyId` raw bytes are sensitive; log only status enum + NSError code, never the blob
- **Phantom-typed `AnalyticsEvent`** (Phase 3 GEO-03) — Attestation telemetry uses the same `AnalyticsEvent.safe(...)` API; raw attestation bytes are un-attachable at compile time
- **`gsd-sdk query commit`** with `--no-verify` inside worktrees, plain commits in sequential mode
- **TDD RED→GREEN→REFACTOR** via the Swift Testing framework — MockURLProtocol fixtures land before production code

### Integration Points

- `AppContainer.session` gains `trustTier: TrustTier` property (read by the banner + by future M2+ sensitive-action gates)
- `SceneDelegate.presentRoot(.role(role))` — existing cold-boot path, heartbeat added inline after `SessionRestoreProbe.restored`
- `SceneDelegate.handleDidBecomeActive` — extended with 24h heartbeat check (third responsibility after the Phase 3 lockState re-check and the SESS-02 background-timeout logic)
- New `Core/Attestation/` folder alongside `Core/Auth/`, `Core/KeyStore/`, `Core/Networking/`
- Role shell UI gets a "limited-trust banner" slot at the top of the tab bar container — a single reusable view, not a per-role component

</code_context>

<specifics>
## Specific Ideas

- Banner copy: "Limited trust mode — this device can't fully verify. Some features may be restricted." (non-dismissible, role-shell top)
- `attestationStatus` enum values: `attested | unsupported | entitlementMissing | quotaExceeded | simulatorBypass | error`
- Backend trust tiers (initial M1): `hardwareAttested | softwareOnly`
- `attestedKeyId` Keychain key name convention: `com.maldin.validationLedger.attestation.keyId`
- `lastHeartbeatAt` Keychain key name convention: `com.maldin.validationLedger.attestation.lastHeartbeatAt`
- `/device/heartbeat` new endpoint — researcher should confirm idempotency-key strategy (NET-04 interceptor applies to POST by default)
- Simulator bypass `attestedKeyId` format: `sim-bypass-{installUUID}` — backend test fixture recognizes this prefix

</specifics>

<deferred>
## Deferred Ideas

- **Per-request App Attest assertions for M2+ sensitive actions** (tender / accept / BOL generation). Came up under cadence discussion — ruled out for M1 because authorizationKey ECDSA signatures (DEV-02) already cover per-request integrity for those endpoints. Revisit in M2 if threat model changes.
- **Time-based re-attestation (every 90 days)** — ruled out in D-04; if long-lived installs become a concern, add BGTaskScheduler-driven re-attest in a later phase.
- **App Attest entitlement / provisioning profile management UX** — raised as a "one more area" option but deferred as dev-team process, not app code. If TestFlight / prod provisioning becomes a blocker, open a separate tooling phase.
- **Real Face ID prompt in CI** via `xcrun simctl biometric enroll/match` — ruled out in D-14 because physical-iPhone support is undocumented and flaky. Revisit when Apple ships a supported hook.
- **Multi-user attestation keys** — ruled out in D-03; if dispatch-handoff devices become a real use case, extend with userID-keyed Keychain storage.
- **Attestation telemetry dashboard** — surfacing `attestationStatus` distribution across the fleet. Belongs to observability / analytics phase, not M1.

### Reviewed Todos (not folded)

_No pending todos existed at discussion time._

</deferred>

---

*Phase: 04-app-attest-physical-device-ci-hardening*
*Context gathered: 2026-04-22*
