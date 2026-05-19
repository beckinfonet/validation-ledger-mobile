# Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification - Research

**Researched:** 2026-05-18
**Domain:** iOS gap-closure / cross-phase wiring — App Attest first-login orchestration, Keychain-mediated trustTier hand-off, retroactive phase verification
**Confidence:** HIGH (this is an in-codebase wiring phase; all findings are grep/read-verified against the actual tree, not training data)

## Summary

Phase 6 is a wiring phase, not a greenfield build. Every component it needs already exists and is unit-tested: `AttestationService` (protocol + `DCAppAttestAttestationService` + `SimulatorBypassAttestationService`), `AttestedKeyStore`, `DeviceChallengeEndpoint`, `DeviceRegisterEndpoint` (with `Response.trustTier`), `AppSession`, `LimitedTrustBannerView`, and the `SceneDelegate.performHeartbeatIfNeeded` heartbeat path that is the literal template for the first-login orchestration. The work is connecting them: insert `generateKeyIfNeeded() → GET /device/challenge → attestKey() → POST /device/register` into `OTPViewModel.verify()` STEP 5, capture the discarded `/device/register` response, persist `trustTier` to Keychain, and have the role-shell `AppContainer` seed `AppSession` from it.

The research confirmed all of CONTEXT.md's named integration sites exist with the expected shapes. Line numbers drifted slightly from CONTEXT.md (documented in the Drift table below) but no decision is invalidated. The decisions D6-01..D6-12 are all technically workable against the current code with **one important caveat that the planner must handle** (D6-06 — see BLOCKER-ADJACENT FINDING below): the `challengeExpired` refetch-and-retry-once behaviour that D6-06 says "still applies, unchanged" was a Phase 4 D-08 *decision* that was never actually implemented in production. The `AttestationErrorResponseInterceptor` only handles three codes (`attestationInvalid`/`nonceExpired`/`keyCompromised`), and the only `challengeExpired` artifact in the tree is a toy state-machine unit test. D6-06 is therefore a *new build*, not a "keep existing behaviour" — the planner must scope it as implementation work or the user must be asked to descope it.

**Primary recommendation:** Plan this as 3-4 small waves: (Wave 0) RED tests for the first-login attestation path + trustTier persistence; (Wave 1) `AttestedKeyStore.read/writeTrustTier` + `KeychainKey.trustTier` + `OTPViewModel` DI growth + STEP 5 orchestration + response capture; (Wave 2) `AppContainer`/`AppSession` consumer wiring + `uiTestTrustTierOverride` deletion + the three folded audit fixes (D6-08/09/10); (Wave 3, must run last) the retroactive `04-VERIFICATION.md`. Treat D6-06 as explicit implementation scope.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

> Decision IDs `D6-NN` are Phase 6-local. `D-NN` without the `6` prefix are locked Phase 4 decisions (see `04-CONTEXT.md`) and must NOT be re-litigated.

**trustTier hand-off across the post-OTP container swap**

- **D6-01:** Propagate first-login `trustTier` via **Keychain persistence**. `AttestedKeyStore` gains `readTrustTier()` / `writeTrustTier(_:)` alongside the existing `attestedKeyId` + `lastHeartbeatAt` accessors. `OTPViewModel` writes `trustTier` from the `/device/register` response; the role-shell `AppContainer` reads it at construction and seeds `AppSession`. Chosen over threading it through the `onAuthenticated` callback chain and over a post-OTP heartbeat. Bonus: the cold-boot `.restored` path can also seed `AppSession` from the persisted tier so the banner is correct from frame 1.

- **D6-02:** The `trustTier` Keychain item is **preserved across logout** — it lives in the attestation key group with `attestedKeyId` / `lastHeartbeatAt` (NOT a member of `KeychainScope.session`, so `KeychainStore.deleteAll(under: .session)` does not wipe it). Follow the `device.attestedKeyId` raw-value naming convention (e.g. `device.trustTier`).

- **D6-03:** **Remove** the DEBUG-only `AppContainer.uiTestTrustTierOverride` seam. With the real consumer wired, the mock `/device/register` fixture's `trust_tier` (set by `MockOTPRoleFixtureRegistry` via `-MockOTPTrustTierForUITest`) flows naturally through `OTPViewModel` → Keychain → `AppSession` → banner. The `uiTestTrustTierOverride` static and its read sites are deleted. The `-MockOTPTrustTierForUITest` launchArg + `MockOTPRoleFixtureRegistry` fixture path stay.

**App Attest failure posture at first login**

- **D6-04:** **Permanent failures are already handled — do not change them.** A `generateKeyIfNeeded()` that returns a non-`.attested` status takes the Phase 4 D-09 graceful-skip path: send that status, omit `attestedKeyId` + `attestationObject`. `.simulatorBypass` is treated like `.attested`.

- **D6-05:** **Transient failures degrade and continue — login is never blocked.** When the device *can* attest but a transient failure hits (`GET /device/challenge` errors, or `attestKey()` throws), log a warning, set `attestationStatus: .error`, omit the attestation fields, and **still POST `/device/register`**. No extra inline retry on a generic transient failure.

- **D6-06:** Phase 4 **D-08 still applies, unchanged**: if `/device/register` returns the `challengeExpired` server error code, refetch a fresh challenge and retry the register **once**.

- **D6-07:** PII discipline (Phase 4 04-PATTERNS.md Pattern A) holds: raw `attestationObject` / `attestedKeyId` / challenge bytes and `NSError.userInfo` never enter `Logger` fields — only the event name + status enum rawValue.

**Folded audit fixes**

- **D6-08 (WARNING-1):** Refresh Keychain `kycStatus` after a successful `GET /kyc/status`. The KYC-status fetch path must write the fresh status under `.kycStatus` with the same `.afterFirstUnlockThisDeviceOnly` accessibility. Affects SESS-01 / KYC-01 / D-13.

- **D6-09 (Profile "Continue" CTA):** Wire `onVerified` in `AppContainer.makeKYCStatusScreen()`. `KYCCoordinator.pushStatus()` already wires it on the post-submit path; the Profile-entry factory omits it. One-line parity fix.

- **D6-10 (WARNING-2):** Make `AppSession.trustTier` **observable** so `LimitedTrustBannerView` re-renders — appears on downgrade, disappears on upgrade — whenever the heartbeat (or first-login consumer) mutates the tier. The banner stays non-dismissible (Phase 4 D-11); the change is shown **without animation**. Observation mechanism (NotificationCenter post vs. closure/observer on `AppSession`) is Claude's discretion. `AppSession` stays `@MainActor`.

**Phase 4 verification close-out**

- **D6-11:** `04-VERIFICATION.md` is produced as a tracked task in Phase 6 — the final plan/wave writes + commits `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md`. It MUST run last (Phase 4 SC-1 only passes once D6-01..D6-07 land).

- **D6-12:** The report is a **full Phase 4 re-verification** — all three Phase 4 success criteria + DEV-04 + CI-03. Phase 6 also ticks the still-unchecked roadmap `04-10` checkbox.

### Claude's Discretion

- The exact factoring of the first-login attestation orchestration — inline in `OTPViewModel.verify()` STEP 5 vs. a small shared helper that both the first-login path and `SceneDelegate.performHeartbeatIfNeeded` could call. The heartbeat path already inlines an equivalent dance, so a shared seam is optional, not required.
- `OTPViewModel`'s DI surface growth — it needs `AttestationService` and a path to write `trustTier` (likely `AttestedKeyStore` or the `KeychainStore` it already holds). `AuthCoordinator.swift:51` is the single construction site.
- Whether the `.settingUp(progress:total:)` step total/labels change to reflect the added attestation steps, or the attestation work folds silently into the existing STEP 5 slot. Follow the M1 minimal-UI principle.
- WARNING-2 observation mechanism (see D6-10).

### Deferred Ideas (OUT OF SCOPE)

- **Near-term re-attest after a degraded first login** — ruled out; a degraded first login waits for the existing D-07 24h heartbeat / next cold boot.
- **Shared first-login/heartbeat attestation seam** — left as planner discretion; only worthwhile if a future phase adds a third caller.
- **Nyquist gap-fills for Phase 1 (partial) and Phase 2 (missing)** — handled separately via `/gsd-validate-phase 1` / `2`.
- **Other audit tech-debt** (CR-02b PIIScrubber over-redaction, CR-03 force unwrap, `DeviceFingerprint` `try?` install-UUID, IN-02 wire-format skew, the `CameraPermissionViewController` product decision) — unrelated pre-Phase-6 debt.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-04 | `Core/Attestation` calls App Attest on first successful login; attestation payload included in `/device/register`. Gracefully skipped if App Attest is unavailable (older device, entitlement missing) with a logged warning — backend decides policy. | The first-login orchestration (Standard Stack / Code Examples below) inserts `generateKeyIfNeeded → GET /device/challenge → attestKey → POST /device/register` into `OTPViewModel.verify()` STEP 5. D-09 graceful-skip (D6-04) is already enforced by `DCAppAttestAttestationService.statusForDCError` + `DeviceRegisterEndpoint`'s `Optional.none` omission. The retroactive `04-VERIFICATION.md` (D6-11/D6-12) closes the verification gap that hid this. **Note:** REQUIREMENTS.md line 62 already marks DEV-04 `[x] Validated Phase 4` — that line is *premature*; the audit downgraded it to `partial`. The planner should expect the milestone-close archive step to re-sync REQUIREMENTS.md. |
| CI-03 | Physical-device test plan covers Secure Enclave keypair generation, Keychain biometric-bound item storage, App Attest assertion generation. Runs on every merge to `main`. | CI-03 is satisfied at the artifact level (`ci-device.yml` `device-security-surface` job exists, `AppAttestRoundTripTests` runs green). Phase 6's only CI-03 work is the **verification close-out** — `04-VERIFICATION.md` must verify SC-3 against the existing pipeline, and Phase 6 ticks the roadmap `04-10` checkbox (`04-10-SUMMARY.md` already exists). No new CI code is in scope. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| First-login App Attest orchestration (key gen → challenge → attest) | API / Backend client (`OTPViewModel` calling `Core/Attestation` + `Core/Networking`) | — | `OTPViewModel` is the existing owner of the post-OTP `/device/register` step (D-27 STEP 5). Attestation is a registration concern; it belongs in the same orchestration, not in a view or coordinator. |
| `trustTier` persistence | Database / Storage (`Keychain` via `AttestedKeyStore`) | — | D6-01 mandates Keychain as the cross-container-swap channel. `AttestedKeyStore` already owns the attestation Keychain group. |
| `trustTier` → `AppSession` seeding | Frontend Server / composition root (`AppContainer.init`) | — | `AppContainer` is the composition root that builds `AppSession`; it is the single construction site per ADR 0002. |
| `LimitedTrustBannerView` visibility / re-render | Browser / Client (UIKit view layer) | App composition root (`AppCoordinator.wrapWithLimitedTrustBanner`) | The banner is a pure UIKit view; D6-10 observability bridges a mutable model (`AppSession`) to the view. |
| KYC status Keychain refresh (D6-08) | Database / Storage (Keychain) driven from the status-fetch path | API client (`KYCStatusViewModel.fetchStatus`) | The fix is a write to the same `.kycStatus` Keychain key, triggered after a successful `GET /kyc/status`. |
| Phase 4 verification report (D6-11/D6-12) | Documentation / planning artifact | — | `04-VERIFICATION.md` is a `.planning/` document, not code. |

## Standard Stack

This is an in-codebase wiring phase. There are **no new external packages**. Every "library" below is an already-shipped project component.

### Core (existing project components — all VERIFIED by Read of the source file)

| Component | File | Purpose | Why Standard |
|-----------|------|---------|--------------|
| `AttestationService` protocol | `validationLedger/Core/Attestation/AttestationService.swift` | `generateKeyIfNeeded()` + `attestKey(keyId:challenge:)` are the two methods the first-login path calls | The protocol surface Phase 4 built for exactly this. `[VERIFIED: source read]` |
| `DCAppAttestAttestationService` / `SimulatorBypassAttestationService` | `Core/Attestation/` | Production / simulator impls; selected in `AppContainer.init` via `#if DEBUG && targetEnvironment(simulator)` | `OTPViewModel` consumes `container.attestationService` — no new selection logic (D6 code_context). `[VERIFIED: source read]` |
| `AttestedKeyStore` | `Core/Attestation/AttestedKeyStore.swift` | Keychain wrapper; gains `readTrustTier()`/`writeTrustTier(_:)` (D6-01) | `read/writeAttestedKeyId` + `read/writeLastHeartbeatAt` are the exact pattern the new accessors copy. `[VERIFIED: source read]` |
| `DeviceChallengeEndpoint` | `Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` | `GET /device/challenge` — `Response { challenge, expiresAt, nonce }` | The challenge fetch the first-login path adds; identical to the heartbeat path's call. `[VERIFIED: source read]` |
| `DeviceRegisterEndpoint` | `Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` | `POST /device/register`; `Response { deviceID, registeredAt, trustTier }` | Contract unchanged. `Response.trustTier: TrustTier` is the value to capture. `[VERIFIED: source read]` |
| `AppSession` | `App/AppSession.swift` | `@MainActor final class` holding `var trustTier: TrustTier` | `trustTier` becomes observable (D6-10); role-shell `AppContainer` seeds it from Keychain (D6-01). `[VERIFIED: source read]` |
| `KeychainKey` | `Core/Storage/Keychain/KeychainKey.swift` | Source-of-truth key registry; add `device.trustTier` static | `attestedKeyId` (`device.attestedKeyId`) + `lastHeartbeatAt` (`device.lastHeartbeatAt`) are the naming + grouping precedent. `[VERIFIED: source read]` |
| `LimitedTrustBannerView` + `UITabBarController.wrapWithLimitedTrustBanner` | `UI/LimitedTrustBannerView.swift`, `Roles/RoleCoordinator.swift` | The banner + the conditional wrap | WARNING-2 (D6-10) makes the wrap reactive to `trustTier` mutation. `[VERIFIED: source read]` |

### Supporting (reference templates — not modified, but read before planning)

| Component | File | Purpose | When to Use |
|-----------|------|---------|-------------|
| `SceneDelegate.performHeartbeatIfNeeded` | `App/SceneDelegate.swift:~568-651` | The heartbeat orchestration — `generateKeyIfNeeded → GET /device/challenge → generateAssertion → POST → session.trustTier = response.trustTier` | **The direct template** for the first-login path. First-login swaps `attestKey()` + `DeviceRegisterEndpoint` for `generateAssertion()` + `DeviceHeartbeatEndpoint`. `[VERIFIED: source read]` |
| `FakeAttestationService` | `validationLedgerTests/Attestation/FakeAttestationService.swift` | Scriptable test double — `nextGenerateKeyIfNeeded`, `nextAttestKey`, call counters, last-args capture | The test double the new RED tests for `OTPViewModel`'s attestation path will inject. `[VERIFIED: source read]` |
| `MockOTPRoleFixtureRegistry` | `Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift` | DEBUG-only fixture registrar; `registerForRole(_:trustTier:)` already emits `trust_tier` on the `/device/register` response | With D6-03, this becomes the *only* trustTier seam for XCUITests — fixture drives the real consumer. `[VERIFIED: source read]` |

### Alternatives Considered

All architectural alternatives were already evaluated and **locked** in CONTEXT.md (D6-01 over callback-threading / post-OTP heartbeat; D6-10 NotificationCenter-vs-closure left to discretion). No new alternatives to surface — the locked decisions stand.

**Installation:** None. No `npm`/`pip`/SwiftPM dependency changes. The project is SwiftPM-only with a deliberately shallow graph (CLAUDE.md); Phase 6 adds zero packages.

## Package Legitimacy Audit

**Not applicable.** Phase 6 installs no external packages. The entire phase is wiring of already-shipped, already-tested project components. The Package Legitimacy Gate is skipped because there is nothing to audit — `slopcheck` / `npm view` / `pip index` have no inputs. (CLAUDE.md constraint: any new dependency requires explicit approval; Phase 6 introduces none.)

## Architecture Patterns

### System Architecture Diagram — first-login attestation + trustTier flow

```
                      OTPViewModel.verify()  (auth-phase AppContainer)
                                 │
        STEP 1  OTPVerifyEndpoint │  → sessionToken / role / userID / kycStatus
        STEP 2  persist to Keychain (sessionToken, role, userID, kycStatus)
        STEP 3+4 keyStore.generateDeviceIdentityKeys() → devicePub, authPub
                                 │
        STEP 5  ┌────────────────┴───────────────────────────────┐
                │  NEW: attestation orchestration                 │
                │                                                 │
                │  attestationService.generateKeyIfNeeded()       │
                │        │                                        │
                │        ├── status ∈ {.unsupported,              │
                │        │   .entitlementMissing,.quotaExceeded,   │
                │        │   .error}  ──► D6-04 graceful skip:     │
                │        │              attestationStatus=status, │
                │        │              attestedKeyId=nil,        │
                │        │              attestationObject=nil     │
                │        │                                        │
                │        └── status ∈ {.attested,.simulatorBypass}│
                │                 │                               │
                │            GET /device/challenge                │
                │                 │                               │
                │            ├─ error ──► D6-05 transient degrade: │
                │            │            attestationStatus=.error,│
                │            │            omit fields, CONTINUE    │
                │            │                                     │
                │            └─ ok ─► attestKey(keyId, challenge)  │
                │                       │                          │
                │                       ├─ throws ─► D6-05 degrade │
                │                       └─ ok ─► attestationObject │
                └────────────────────────┬────────────────────────┘
                                          │
        STEP 5  POST /device/register  ◄──┘  (real attestation payload)
                  │
                  ├─ D6-06: response error_code == challengeExpired
                  │         ──► refetch challenge, re-attest, retry register ONCE
                  │
                  └─ success: CAPTURE response  (was discarded `_ = try await`)
                         │
                         ├─ AttestedKeyStore.writeTrustTier(response.trustTier)   ◄── D6-01 Keychain
                         │
        STEP 6  biometric.evaluate()
        STEP 7  onAuthenticated(role) / onKYCRequired(role)
                         │
                         ▼
              SceneDelegate.presentRoot(.role(role))
                         │
                  builds FRESH AppContainer  (ADR 0002 abrupt-replace)
                         │
              AppContainer.init: AppSession(trustTier:
                  AttestedKeyStore.readTrustTier() ?? .softwareOnly)   ◄── D6-01 consumer
                         │
              AppCoordinator .role case:
                  tabBar.wrapWithLimitedTrustBanner(trustTier: session.trustTier)
                         │
              AppSession.trustTier mutates (heartbeat) ──► D6-10 observable
                         │                                  ──► banner re-renders
                         ▼
              LimitedTrustBannerView  (visible iff trustTier != .hardwareAttested)
```

### Recommended structure (files touched — no new directories)

```
validationLedger/
├── Core/
│   ├── Attestation/
│   │   └── AttestedKeyStore.swift        # + readTrustTier()/writeTrustTier(_:)  (D6-01)
│   └── Storage/Keychain/
│       └── KeychainKey.swift             # + static device.trustTier             (D6-02)
├── Features/Onboarding/
│   ├── Auth/
│   │   ├── OTPViewModel.swift            # STEP 5 attestation orchestration + response capture
│   │   └── AuthCoordinator.swift         # :51 — OTPViewModel DI surface growth
│   └── KYC/
│       └── KYCStatusViewModel.swift      # D6-08 — write kycStatus after GET /kyc/status
├── App/
│   ├── AppSession.swift                  # D6-10 — observable trustTier
│   ├── AppContainer.swift                # D6-03 delete uiTestTrustTierOverride;
│   │                                     #   seed AppSession from Keychain (D6-01);
│   │                                     #   D6-09 wire onVerified in makeKYCStatusScreen()
│   ├── AppCoordinator.swift              # D6-10 — banner re-render wiring (~:83)
│   └── SceneDelegate.swift               # D6-03 delete uiTestTrustTierOverride read site
```

### Pattern 1: First-login attestation orchestration mirrors the heartbeat path

**What:** The heartbeat helper `SceneDelegate.performHeartbeatIfNeeded` already does the exact dance the first-login path needs, one endpoint different. The planner should treat it as the reference implementation.

**When to use:** Whenever scoping the STEP 5 orchestration tasks. Read `SceneDelegate.swift:~568-651` first.

**Heartbeat path (existing) vs first-login path (Phase 6) — the delta:**

| Step | Heartbeat (`performHeartbeatIfNeeded`) | First-login (Phase 6, in `OTPViewModel.verify()` STEP 5) |
|------|----------------------------------------|-----------------------------------------------------------|
| key | `generateKeyIfNeeded()`; guard `status == .attested \|\| .simulatorBypass` | same |
| challenge | `apiClient.request(DeviceChallengeEndpoint())`; base64-decode | same |
| crypto | `generateAssertion(keyId:challenge:)` | **`attestKey(keyId:challenge:)`** |
| POST | `DeviceHeartbeatEndpoint` | **`DeviceRegisterEndpoint`** (already 6-arg with attestation fields) |
| result | `session.trustTier = response.trustTier` (direct, same container) | **`AttestedKeyStore.writeTrustTier(response.trustTier)`** (Keychain, cross-swap) |
| failure | silent-fail, role shell still renders | **D6-05 degrade-and-continue: `attestationStatus = .error`, still POST register** |

**Example (verified shape — from `SceneDelegate.performHeartbeatIfNeeded`):**
```swift
// Source: validationLedger/App/SceneDelegate.swift:586-606  [VERIFIED: source read]
let (keyId, status) = try await container.attestationService.generateKeyIfNeeded()
guard status == .attested || status == .simulatorBypass else {
    container.logger.warn(event: .init("attestation_heartbeat_skipped_no_key"),
                          fields: [.event: status.rawValue])
    return
}
let challengeResponse = try await container.apiClient.request(DeviceChallengeEndpoint())
guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else { ... }
let assertion = try await container.attestationService.generateAssertion(
    keyId: keyId, challenge: challengeData)
```

### Pattern 2: D-09 omission rule is automatic — do not hand-code field stripping

**What:** `DeviceRegisterEndpoint.RequestBody.attestedKeyId` and `.attestationObject` are `Optional`. Swift's `JSONEncoder` drops `Optional.none` entirely (no `null` on the wire). So on a non-`.attested` status, the orchestration just passes `nil` for both — the omission is free.

**When to use:** STEP 5 payload construction. The planner should NOT write a task that "strips attestation fields" — it is a property of passing `nil`. `DeviceRegisterOmissionTests` already pins this.

### Pattern 3: The cross-container-swap problem (why D6-01 is Keychain, not a callback)

**What:** `OTPViewModel` runs inside the *auth-phase* `AppContainer`. On verify success, `SceneDelegate.presentRoot(.role(role))` builds a **brand new** `AppContainer` with a **fresh** `AppSession(trustTier: .softwareOnly)` (ADR 0002 abrupt-replace, verified in `AppContainer.swift:389-398` + `SceneDelegate.swift:389-407`). A `trustTier` written into the auth-phase `AppSession` is discarded. Keychain is the only channel that survives the swap. The cold-boot `.restored` path benefits too — `AppContainer.init` seeds `AppSession` from `readTrustTier()` so the banner is correct from frame 1.

### Anti-Patterns to Avoid

- **Threading `trustTier` through `onAuthenticated`:** explicitly rejected by D6-01 (churns ~4 callback signatures, no cold-boot benefit). Do not let a plan reintroduce this.
- **Adding an inline retry on a generic transient attestation failure:** D6-05 forbids it. The only retry permitted in the first-login path is the D6-06 `challengeExpired` single retry.
- **Deleting `-MockOTPTrustTierForUITest` / `MockOTPRoleFixtureRegistry`:** D6-03 deletes *only* the `uiTestTrustTierOverride` static + its two read sites. The launchArg + fixture registry STAY — they drive the real consumer.
- **Animating the banner appearance/removal:** D6-10 mandates no animation, consistent with ADR 0002.
- **`fatalError` on missing entitlement:** `preflightAttestationEntitlement` deliberately does NOT `fatalError` (unlike `preflightSecureEnclave`) — entitlement absence routes to `attestationStatus: .entitlementMissing`. Phase 6 must not change this.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| App Attest key gen / assertion | A new attestation routine | `container.attestationService.generateKeyIfNeeded()` / `attestKey()` | Phase 4 built, tested, and CI-verified `DCAppAttestAttestationService` on a real iPhone. |
| Keychain string round-trip for `trustTier` | A bespoke Keychain call in `OTPViewModel` | `AttestedKeyStore.write/readTrustTier(_:)` (new methods, same pattern as `attestedKeyId`) | `TrustTier` is `RawRepresentable: String` — it round-trips as a string exactly like `attestedKeyId`. The `itemNotFound → nil` translation is already the established pattern. |
| `challengeExpired` JSON error-code extraction | A new JSON parser | `AttestationErrorResponseInterceptor.extractErrorCode(from:)` (already accepts `error_code` + `errorCode`) | See BLOCKER-ADJACENT FINDING — this helper exists but the interceptor does not currently *act* on `challengeExpired`. |
| First-login orchestration shape | A novel sequence | Copy `SceneDelegate.performHeartbeatIfNeeded` step-for-step (Pattern 1) | Proven, PII-disciplined, error-handled. The only deltas are the table in Pattern 1. |
| Banner re-render plumbing | A KVO subclass or Combine pipeline | NotificationCenter post (project precedent: `.sessionDidInvalidate`) OR a closure/observer on `AppSession` (precedent: `OTPViewModel.onStateChange`) — D6-10 discretion | Both patterns already exist in the codebase; no third mechanism needed. |

**Key insight:** Phase 6 should add almost no *new* logic — it should *connect* existing logic. Any plan task that proposes building a new service, a new endpoint, or a new crypto routine is a scope error: every primitive already exists and is tested. The single genuine *new build* is the D6-06 `challengeExpired` retry path (see below).

## Runtime State Inventory

> This phase deletes a DEBUG seam and changes a Keychain-write contract. It is a wiring/refactor phase, so the inventory applies.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **New Keychain item `device.trustTier`** introduced by D6-01/D6-02. No *existing* stored data is renamed or migrated — this is a net-new key. The first `/device/register` after the Phase 6 build writes it; before that, `readTrustTier()` returns `nil` and `AppSession` falls back to `.softwareOnly` (the safe default). No data migration needed. Existing `device.attestedKeyId` / `device.lastHeartbeatAt` / `session.kycStatus` are untouched in shape. | Code edit only (add key + accessors). No migration task. |
| Live service config | iOS app is mock-backed for M1 (CLAUDE.md / CONTEXT.md out-of-scope: "Backend changes — iOS stays mock-backed"). No external service config carries the renamed/affected strings. **None — verified: no backend, no live service in M1 scope.** | None. |
| OS-registered state | No OS-registered state (Task Scheduler / launchd / pm2) — this is an iOS app. The only OS-managed attestation state is the App Attest key inside the Secure Enclave, owned by `DCAppAttestService` and keyed by `attestedKeyId` (untouched by Phase 6). **None affected.** | None. |
| Secrets / env vars | No SOPS/`.env`/CI secret names reference `trustTier` or the affected paths. The `-MockOTPTrustTierForUITest` launch *argument* is referenced in `LimitedTrustBannerTests.swift` and `SceneDelegate.swift` — it STAYS (D6-03). The thing deleted is the `AppContainer.uiTestTrustTierOverride` *static var*, an in-process symbol, not an env var. | None for secrets. The `uiTestTrustTierOverride` deletion is a code edit (3 sites — see Drift table). |
| Build artifacts / installed packages | No pip egg-info / compiled binaries / Docker tags. The Xcode project is SwiftPM-only. The one build-system touchpoint: deleting the `uiTestTrustTierOverride` static must not orphan a reference — `grep` confirms exactly 3 sites (declaration + 2 reads). XCUITests (`LimitedTrustBannerTests`) reference only the launch *arg*, not the static, so they survive the deletion. | Code edit; verify zero dangling references after deletion (`grep uiTestTrustTierOverride` returns 0). |

**The canonical question — after every file is updated, what runtime systems still have the old state?** Answer: none. There is no persisted/cached/registered copy of `uiTestTrustTierOverride` (it is an in-process `static var`, reset every launch). The new `device.trustTier` Keychain item is forward-only — no pre-Phase-6 data exists to migrate. The only cross-build subtlety: a device that had a Phase 4/5 build installed has `device.attestedKeyId` already in Keychain (preserved across logout per D-03); the first Phase 6 `generateKeyIfNeeded()` will *read that existing key* (D-01 once-per-install) rather than mint a new one — which is correct and desired.

## Common Pitfalls

### Pitfall 1: D6-06 `challengeExpired` retry was never actually implemented (BLOCKER-ADJACENT)

**What goes wrong:** D6-06 says "Phase 4 D-08 still applies, unchanged" — implying `challengeExpired` refetch-and-retry-once is existing behaviour Phase 6 merely preserves. **It is not existing behaviour.** Grep of the entire `validationLedger/` tree for `challengeExpired` returns **zero production hits**. The only artifacts are:
- `ChallengeExpiredRetryTest.swift` — a *toy* `ChallengeRetryCoordinator` state machine that tests retry-count math, with a comment stating "The production retry-once-on-challengeExpired behavior is wired into the AttestationErrorResponseInterceptor (Plan 07 Task 3)".
- `AttestationErrorResponseInterceptor` — which handles **only** `attestationInvalid` / `nonceExpired` / `keyCompromised` (`canonicalTriggerCodes`). It does **not** include `challengeExpired`, and `challengeExpired` is semantically *different* from those three (it triggers a refetch+re-attest+register-retry, not a key-clear+regenerate+retry).

**Why it happens:** Phase 4 D-08 was a design decision; the first-login path that would consume it never landed (that is gap #2 — the whole reason Phase 6 exists). The `challengeExpired` retry has no caller because there was no first-login attestation path to fail with it.

**How to avoid:** The planner MUST treat D6-06 as **new implementation scope**, not a no-op. It is technically workable (`extractErrorCode` exists; the register POST returns `NetworkError.httpError(statusCode, data)` carrying the body — see `NetworkError.swift:12`). Options the planner should weigh and surface:
  1. Inline the `challengeExpired` detection in `OTPViewModel`'s STEP 5: on `NetworkError.httpError` from the register POST, parse the body for `error_code == "challengeExpired"`, refetch `GET /device/challenge`, re-`attestKey`, retry register once.
  2. Extend `AttestationErrorResponseInterceptor` to also handle `challengeExpired` with a *different* recovery (refetch challenge, not clear key). This is heavier — the interceptor cannot re-`attestKey` because it has no `keyId`/challenge context.
Option 1 is simpler and keeps the first-login orchestration self-contained. **This is not a BLOCKER** (the decision is workable) — but the planner must not assume zero work, and should consider asking the user whether D6-06 can be descoped given M1's mock backend never emits `challengeExpired`.

**Warning signs:** A plan that lists D6-06 as "verify existing behaviour" or omits it entirely. A task estimate that assumes the interceptor already covers it.

### Pitfall 2: `OTPViewModel.retryRegister()` re-runs the *entire* `verify()`

**What goes wrong:** `retryRegister()` (`OTPViewModel.swift:278-281`) just calls `verify()` again. After Phase 6, `verify()` includes the attestation orchestration — so a register-failure retry re-runs `generateKeyIfNeeded` + challenge + `attestKey`. This is *fine* (D6 code_context confirms idempotency: `generateKeyIfNeeded` is once-per-install per D-01, `attestKey` is re-callable, `/device/register` is Idempotency-Key-protected per NET-04) — **but** the planner must ensure the new RED tests cover the retry path, not just the happy path, so an accidental non-idempotent edit is caught.

**How to avoid:** Add a RED test asserting `retryRegister()` after a `.registerFailed` produces a single net attestation key (via `FakeAttestationService.generateKeyIfNeededCallCount` — note: the fake increments per call, but the *production* `DCAppAttestAttestationService` reads Keychain on the 2nd call, so the fake's counter is a proxy; assert the *register payload* shape instead).

### Pitfall 3: PII leakage in the new attestation logging (D6-07)

**What goes wrong:** The natural Swift idiom `logger.error(fields: [.event: String(describing: error)])` — used elsewhere in `OTPViewModel` for `otp_verify_failed` — would, for an attestation error, serialize an `AttestationError.underlying(NSError)` whose `userInfo` may carry diagnostic bytes DeviceCheck attaches. `04-PATTERNS.md` Pattern A + `AttestationError.swift` header explicitly forbid this.

**Why it happens:** STEP 5's existing non-attestation `catch` blocks *do* use `String(describing: error)` (lines 132, 166, 181, 213). Copy-pasting that idiom into the new attestation `catch` blocks would leak.

**How to avoid:** In the attestation `catch` blocks, log **only** the event name + the `AttestationStatus.rawValue` (a closed-set string) — mirror `SceneDelegate.performHeartbeatIfNeeded`'s `fields: [.event: status.rawValue]` and `fields: [:]` discipline. A RED test should grep `OTPViewModel.swift` to assert the attestation `catch` blocks do not contain `String(describing:` (the source-grep test pattern already used by `OTPViewModelTests.sourceReferencesExpectedCollaborators`).

### Pitfall 4: The `.settingUp(progress:total:)` step counter

**What goes wrong:** `verify()` currently emits `.settingUp(progress: N, total: 6)` at six points. Inserting attestation work mid-STEP-5 either (a) silently folds into the existing `progress: 4` slot, or (b) needs the `total` bumped and labels re-numbered. CONTEXT.md leaves this to discretion ("Follow the M1 minimal-UI principle").

**How to avoid:** Recommendation: **fold silently** — keep `total: 6`, leave the attestation work inside the existing `progress: 4` STEP 5 slot. M1 minimal-UI; the attestation steps complete in <1s on the happy path; a finer-grained progress bar is UI polish out of scope. The planner should make this an explicit (small) decision, not leave it ambiguous in the plan.

### Pitfall 5: `04-VERIFICATION.md` must run last and re-verify *all three* SC

**What goes wrong:** A plan that schedules `04-VERIFICATION.md` in an early wave would verify Phase 4 against code that still has the gap — it would have to record SC-1 as failing. D6-11 mandates it runs **last**; D6-12 mandates it covers all three SC + DEV-04 + CI-03, not just the closed gap.

**How to avoid:** Make `04-VERIFICATION.md` a dedicated final wave with `depends_on` every preceding Phase 6 wave. Use `05-VERIFICATION.md` (frontmatter + `## Goal Achievement` → `### Observable Truths` table + `### Requirements Coverage` table + `### Human Verification Required`) as the structural template — see Validation Architecture below for the exact required sections.

### Pitfall 6: Deleting `uiTestTrustTierOverride` must not break `LimitedTrustBannerTests`

**What goes wrong:** D6-03 deletes the static. If the deletion is sequenced *before* the real consumer (D6-01) is wired, `LimitedTrustBannerTests.testBannerVisibleWhenTrustTierIsSoftwareOnly` loses its trustTier source and fails (the banner would always read the `.softwareOnly` default — which happens to still pass the *softwareOnly* test but fails the *hardwareAttested* test, since the fixture's `trust_tier` would never reach `AppSession`).

**How to avoid:** Sequence the deletion (D6-03) **after** D6-01's consumer wiring lands. The fixture path (`MockOTPRoleFixtureRegistry` emits `trust_tier`) + the new consumer (`OTPViewModel` → Keychain → `AppContainer` → `AppSession`) must be live before the override is removed. The planner should place D6-03 in the same wave as, or a wave after, D6-01 — never before.

## Code Examples

### New `AttestedKeyStore` accessors (D6-01) — exact pattern to copy

```swift
// Source pattern: AttestedKeyStore.readAttestedKeyId / writeAttestedKeyId  [VERIFIED: source read]
// New methods Phase 6 adds — TrustTier is RawRepresentable<String>, round-trips as a string.

/// Returns the persisted trustTier, or `nil` if never written (pre-first-register).
public func readTrustTier() throws -> TrustTier? {
    do {
        let data = try keychain.get(.trustTier)
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return TrustTier(rawValue: raw)
    } catch KeychainError.itemNotFound {
        return nil
    }
}

/// Writes `tier` to Keychain under `.trustTier` with .afterFirstUnlockThisDeviceOnly (D6-02).
public func writeTrustTier(_ tier: TrustTier) throws {
    try keychain.set(
        Data(tier.rawValue.utf8),
        for: .trustTier,
        accessibility: .afterFirstUnlockThisDeviceOnly
    )
}
```

### New `KeychainKey` static (D6-02)

```swift
// Source: KeychainKey.swift — joins the attestation group, NOT KeychainScope.session.  [VERIFIED: source read]
// Phase 6 DEV-04: backend-driven trustTier, persisted across the post-OTP container swap.
// MUST NOT be a member of KeychainScope.session — preserved across logout (D6-02),
// like device.attestedKeyId / device.lastHeartbeatAt.
public static let trustTier = KeychainKey(rawValue: "device.trustTier")
```

### `AppContainer` `AppSession` seeding from Keychain (D6-01 consumer)

```swift
// Replaces AppContainer.swift:394-398. The DEBUG uiTestTrustTierOverride branch is DELETED (D6-03).
// AttestedKeyStore is already constructed in init (line 374 — `attestedKeyStore`).
let seededTier = (try? attestedKeyStore.readTrustTier()) ?? .softwareOnly
self.session = AppSession(trustTier: seededTier)
```

### Wiring `onVerified` in `makeKYCStatusScreen()` (D6-09) — one-line parity fix

```swift
// AppContainer.makeKYCStatusScreen() — mirror KYCCoordinator.pushStatus():497.  [VERIFIED: source read]
// The Profile-entry factory currently omits this line, leaving a dead "Continue" button.
// NOTE: this factory has no coordinator/route; the planner must decide what onVerified does
// from the Profile entry. KYCCoordinator routes it to onKYCSubmitted → role shell. The
// Profile entry is ALREADY inside the role shell — so onVerified should dismiss the modal
// (the screen is presented modally via RoleCoordinator's avatar → ProfileViewController).
// This is a genuine small design decision, not a literal copy of KYCCoordinator's wiring.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `OTPViewModel` STEP 5 hardcodes `attestationStatus: .unsupported` | STEP 5 calls `AttestationService` and sends the real status + optional attestation fields | Phase 6 (this phase) | Closes DEV-04 / Phase 4 SC-1. The stale `OTPViewModel.swift:188-193` comment ("Plan 06 AppContainer wiring will replace this...") is the promise being fulfilled — that comment must be removed. |
| `/device/register` response discarded with `_ = try await` | Response captured; `trustTier` persisted to Keychain | Phase 6 | Closes the cross-phase wiring break + Phase 4 `deferred-items.md` #2. |
| `AppContainer.uiTestTrustTierOverride` DEBUG static papers over the missing consumer | Real consumer wired; override deleted; fixture drives the genuine path | Phase 6 (D6-03) | XCUITests exercise the production trustTier flow end-to-end. |
| `LimitedTrustBannerView` rendered once at role-shell construction; heartbeat mutation invisible until next root-swap | `AppSession.trustTier` observable; banner re-renders on mutation | Phase 6 (D6-10) | Closes WARNING-2. |
| Keychain `kycStatus` written only at OTP-verify | Also refreshed after a successful `GET /kyc/status` | Phase 6 (D6-08) | Closes WARNING-1 — fixes the fail-closed cold-boot misroute for in-session KYC completion. |

**Deprecated/outdated:**
- The `OTPViewModel.swift:188-193` in-code comment block is now stale and misleading — Phase 6 deletes it as part of the STEP 5 rewrite.
- REQUIREMENTS.md line 62 / 119 already read `[x] Validated Phase 4` for DEV-04 / CI-03 — this is *premature* relative to the audit's `partial` finding. Not Phase 6's job to fix the table mid-phase; the milestone-close archive step re-syncs it. The planner should not be confused by the green checkbox.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | D6-06's `challengeExpired` retry is genuinely *unimplemented* and is new scope. | Pitfall 1 / BLOCKER-ADJACENT | LOW — verified by exhaustive grep (`challengeExpired` → 0 production hits) + reading `AttestationErrorResponseInterceptor` (`canonicalTriggerCodes` excludes it). The only residual risk is a non-obvious dynamic dispatch, which is implausible for a string-keyed error code. The risk if the planner *ignores* this finding is high: a wave under-scoped, D6-06 silently unmet. |
| A2 | `TrustTier` round-trips through Keychain as a string with no custom coding. | Code Examples / Don't Hand-Roll | LOW — `TrustTier: String, Codable` confirmed by source read; `attestedKeyId` already does identical string round-tripping. |
| A3 | Folding attestation work into the existing `.settingUp(progress: 4, total: 6)` slot (no counter change) is the right M1 call. | Pitfall 4 | LOW — a UI-granularity choice; CONTEXT.md explicitly delegates it to discretion under "M1 minimal-UI principle". Worst case is a slightly coarse progress bar. |
| A4 | The D6-09 Profile-entry `onVerified` should dismiss the modal (the Profile KYC-status screen is reached from inside the role shell, so "Continue to role shell" is redundant). | Code Examples (D6-09) | MEDIUM — CONTEXT.md calls D6-09 a "one-line parity fix" implying a literal copy of `KYCCoordinator.pushStatus`'s wiring, but that wiring routes to `onKYCSubmitted → role shell`, which is nonsensical from a Profile entry already in the role shell. The planner should confirm the intended behaviour (dismiss vs. no-op vs. route) — the audit itself rates this "cosmetic, navigation impact nil". |
| A5 | No data migration is needed for `device.trustTier` (forward-only key). | Runtime State Inventory | LOW — it is a net-new Keychain key; `readTrustTier()` returning `nil` falls back to `.softwareOnly`, the existing safe default. |

## Open Questions

1. **D6-06 scope — is `challengeExpired` retry worth building for an M1 mock backend?**
   - What we know: D6-06 mandates it; the production behaviour does not exist (Pitfall 1); the M1 mock backend (`MockDefaultFixtures`, `MockOTPRoleFixtureRegistry`) never emits `challengeExpired` — it always returns 200.
   - What's unclear: whether the user wants the retry path *built and unit-tested against an injected fixture* (defensible — it is real device behaviour, Apple's challenge TTL is ≤60s) or whether D6-06 can be deferred to the same M2 backend-integration phase that would first exercise it.
   - Recommendation: Plan it as built + unit-tested (a `MockURLProtocol` fixture returning a `challengeExpired` body on the first `/device/register`, 200 on the retry — straightforward). But flag it to the user in `/gsd-discuss-phase` or plan-review as the one piece of *genuinely new* code in an otherwise-wiring phase, in case they prefer to descope. Do NOT silently drop it.

2. **D6-09 — what does the Profile-entry "Continue" button do?** (See A4.)
   - What we know: `KYCStatusViewModel.onVerified` exists; `KYCCoordinator.pushStatus()` wires it to `onKYCSubmitted`; the `AppContainer.makeKYCStatusScreen()` factory omits it.
   - What's unclear: from the Profile entry the user is already in the role shell, so "Continue to role shell" is a no-op-equivalent. Dismissing the modal is the likely intent.
   - Recommendation: Plan the D6-09 task to dismiss the presenting modal. Surface this micro-decision in the plan so the checker/user can confirm. The audit's own framing ("redundant navigation... cosmetic") supports dismiss-or-no-op.

3. **Does the `AppContainer.kycTestSeed` CR-01 (seam-not-cleared) interact with D6-08?**
   - What we know: `05-REVIEW.md` CR-01 — `AppContainer.kycTestSeed` static is never cleared after consumption. D6-08 changes the `kycStatus` Keychain-write path.
   - What's unclear: nothing concrete — they touch the same `.kycStatus` key but in different code paths (test-seed vs. status-fetch). Listed only for completeness.
   - Recommendation: No action; CR-01 is explicitly out of Phase 6 scope (CONTEXT.md deferred "other audit tech-debt"). The planner should not fold it in.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode + iOS SDK | All build/test | ✓ (assumed — project builds) | Xcode 26.4 / iOS 26.4 deployment target per CLAUDE.md | — |
| Physical iPhone (App Attest) | `04-VERIFICATION.md` SC-1/SC-3 evidence; `AppAttestRoundTripTests` | ✓ — prior phases ran on `Beck Maldin 16` (iPhone 16) per `05-VERIFICATION.md` + REQUIREMENTS.md ("iPhone 16, 2026-05-16") | iPhone 16 | Simulator covers the `SimulatorBypassAttestationService` path; real-hardware attestation is device-only — `04-VERIFICATION.md` cites the *existing* `AppAttestRoundTripTests` device run rather than requiring a new one. |
| Self-hosted device CI runner | CI-03 / SC-3 verification | ✓ — `ci-device.yml` `device-security-surface` job exists and ran green 2026-05-16 | — | None needed; SC-3 verification reads the existing pipeline + the device-CI biometric-hang caveat (see project memory `device-ci-locked-iphone.md`). |
| `gsd-sdk` CLI | GSD orchestration | ✓ but **see caveat** | — | Project memory `gsd-sdk-node16-workaround.md`: `gsd-sdk` crashes with "structuredClone is not defined" — needs a `NODE_OPTIONS` polyfill. The planner/executor must apply that workaround. |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None blocking. The simulator suite (`validationLedgerTests`) covers all Phase 6 *unit* behaviour; device hardware is only needed to *cite evidence* in `04-VERIFICATION.md`, and that evidence already exists from the Phase 4/5 device runs.

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is REQUIRED.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | **Swift Testing** (`import Testing`, `@Suite`/`@Test`/`#expect`) for unit tests; **XCTest** for XCUITests (Swift Testing cannot drive `XCUIApplication`). Established Phase 3 convention (`03-PATTERNS.md`). |
| Config file | None — Xcode project test targets: `validationLedgerTests` (unit, simulator), `validationLedgerDeviceTests` (device), `validationLedgerUITests` (XCUITest). No `pytest.ini`/`jest.config` analog. |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:validationLedgerTests/OTPViewModelTests -only-testing:validationLedgerTests/Attestation` |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` (367 unit tests as of `05-VERIFICATION.md`; device lane via `ci-device.yml`) |

### Phase Requirements → Test Map

| Req / Decision | Behavior | Test Type | Automated Command | File Exists? |
|----------------|----------|-----------|-------------------|--------------|
| DEV-04 / D6-04 | `OTPViewModel.verify()` with `.attested` status sends real `attestedKeyId` + `attestationObject` in the `/device/register` payload | unit | `-only-testing:validationLedgerTests/OTPViewModelTests` | ❌ Wave 0 — new test in `OTPViewModelTests.swift` (inject `FakeAttestationService` + `MockURLProtocol` fixture, assert payload) |
| D6-04 | A non-`.attested` `generateKeyIfNeeded()` result → graceful skip: status sent, attestation fields omitted | unit | same | ❌ Wave 0 — new test |
| D6-05 | Transient failure (`GET /device/challenge` throws, or `attestKey` throws) → `attestationStatus: .error`, register still POSTed, login completes | unit | same | ❌ Wave 0 — new test (`FakeAttestationService.nextAttestKey = .failure(...)`) |
| D6-06 | `/device/register` returns `challengeExpired` → refetch challenge, re-attest, retry register once; second consecutive expiry surfaces | unit | same | ❌ Wave 0 — new test (`MockURLProtocol` fixture: `challengeExpired` body first, 200 on retry) — see Pitfall 1, this is new scope |
| D6-07 | Attestation `catch` blocks do not pass `String(describing: error)` / `NSError.userInfo` to `Logger` | unit (source-grep, existing idiom) | same | ❌ Wave 0 — extend `OTPViewModelTests.sourceReferencesExpectedCollaborators`-style grep test |
| D6-01 | `AttestedKeyStore.writeTrustTier` / `readTrustTier` round-trip; `OTPViewModel` writes it from the response | unit | `-only-testing:validationLedgerTests/Attestation` (or a new `AttestedKeyStoreTrustTierTests`) | ❌ Wave 0 — new test |
| D6-01 | `AppContainer.init` seeds `AppSession.trustTier` from `readTrustTier()` (and `.softwareOnly` when absent) | unit | `-only-testing:validationLedgerTests/App` | ❌ Wave 0 — new test (or extend `AppContainerNetworkConfigTests`) |
| D6-02 | `device.trustTier` survives `KeychainStore.deleteAll(under: .session)` | unit | `-only-testing:validationLedgerTests/Storage/KeychainScopeTests` | ⚠️ extend — `KeychainScopeTests` already pins `attestedKeyId` scope membership; add a `device.trustTier` case |
| D6-03 | `AppContainer.uiTestTrustTierOverride` is gone; XCUITest trustTier flows via fixture | XCUITest | `ci-device.yml` / `-only-testing:validationLedgerUITests/LimitedTrustBannerTests` | ✅ `LimitedTrustBannerTests.swift` exists — must keep passing after the deletion (no test edit needed; the launchArg path is unchanged) |
| D6-08 | After a successful `GET /kyc/status`, the fresh status is written to Keychain `.kycStatus` | unit | `-only-testing:validationLedgerTests/KYC/KYCStatusViewModelTests` | ⚠️ extend `KYCStatusViewModelTests` — assert the Keychain write |
| D6-09 | `makeKYCStatusScreen()` wires `onVerified` (no dead button) | unit (source-grep) or XCUITest | `KYCProfileEntryUITests` covers the Profile→status tap-through | ✅ `KYCProfileEntryUITests.swift` exists — may extend to tap "Continue"; or a source-grep unit test |
| D6-10 | `AppSession.trustTier` mutation re-renders `LimitedTrustBannerView` (appears/disappears) | unit (observation mechanism) + XCUITest | new unit test for the observer; `LimitedTrustBannerTests` for the visual | ❌ Wave 0 — new test for the chosen mechanism (NotificationCenter post or `AppSession` observer closure) |
| CI-03 / D6-11 / D6-12 | `04-VERIFICATION.md` exists, covers all 3 Phase 4 SC + DEV-04 + CI-03; roadmap `04-10` ticked | doc artifact (verifier reads it) | n/a — produced by the final wave | ❌ new `.planning/.../04-VERIFICATION.md` |

### Sampling Rate

- **Per task commit:** `xcodebuild test ... -only-testing:validationLedgerTests/OTPViewModelTests -only-testing:validationLedgerTests/Attestation` (the directly-affected suites — runs in well under the Nyquist sampling budget).
- **Per wave merge:** full `validationLedgerTests` simulator suite (367+ tests) — catches cross-suite regressions, especially the `MockURLProtocol` fixture-leak class of failure flagged in Phase 4 `deferred-items.md` #1.
- **Phase gate:** full simulator suite green + `LimitedTrustBannerTests` green on the device lane, before `/gsd-verify-work`. The retroactive `04-VERIFICATION.md` is itself the Phase 4 gate.

### Wave 0 Gaps

- [ ] **New tests in `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift`** — the current file is deliberately thin (initial-state + rate-limit-gate + two source-grep contract tests). Phase 6 needs *behavioural* tests of the STEP 5 attestation orchestration. This requires `MockURLProtocol` fixture orchestration for the full `OTPVerify → challenge → register` sequence + a `FakeAttestationService` injected through the (newly grown) `OTPViewModel` initializer. Covers DEV-04 / D6-04 / D6-05 / D6-06 / D6-07 / D6-01.
- [ ] **New `AttestedKeyStore` trustTier tests** — `validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift` (no `AttestedKeyStore` test file exists today; only the services are tested). Covers D6-01 round-trip.
- [ ] **Extend `KeychainScopeTests`** — add `device.trustTier` to the scope-membership pin (D6-02 preserve-across-logout).
- [ ] **Extend `AppContainerNetworkConfigTests`** (or new `AppContainerTrustTierSeedingTests`) — `AppSession` seeded from `readTrustTier()`. Covers D6-01 consumer.
- [ ] **Extend `KYCStatusViewModelTests`** — assert the Keychain `.kycStatus` write after `fetchStatus()` success. Covers D6-08. (Note: `KYCStatusViewModel` does NOT currently hold a `KeychainStore` — D6-08 grows its DI surface; the test must inject one.)
- [ ] **New unit test for the D6-10 observation mechanism** — depends on the chosen mechanism (NotificationCenter vs. `AppSession` observer closure).
- [ ] No test-framework install needed — Swift Testing + XCTest are already wired into all three test targets.

*Wave 0 is substantial for a "wiring" phase precisely because the existing `OTPViewModelTests` deliberately punted behavioural coverage to "Plan 12 UI smoke tests" (see its header comment). Phase 6 must build the unit-level behavioural surface that the first-login attestation path needs.*

## Security Domain

> `security_enforcement` is not set to `false` in config — this section is included. This is a security-critical phase: App Attest *is* the anti-fraud device-identity primitive, and CLAUDE.md's core value is "identity that cannot be spoofed."

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | App Attest binds the device to a hardware-attested key; first-login attestation is the registration-time proof. Phase 6 wires it — it does not invent new auth. The OTP flow itself is unchanged. |
| V3 Session Management | yes (peripheral) | `trustTier` is device-attestation state, deliberately **not** session state — D6-02 keeps `device.trustTier` out of `KeychainScope.session` so logout does not wipe it. The session keys (`session.token`/`role`/`userID`/`kycStatus`) are untouched in scope. |
| V4 Access Control | no | Phase 6 changes no authorization decision. `trustTier` drives a *banner*, not a gate (D-11 — the limited-trust banner is informational, non-blocking). |
| V5 Input Validation | yes | The `/device/register` and `GET /device/challenge` *responses* are decoded through typed `Decodable` endpoints (`TrustTier` is a closed-set enum; an unknown wire value would fail decoding — acceptable, fail-loud). The `challengeExpired` `error_code` parse (D6-06) must use the existing `extractErrorCode` (tolerant `JSONSerialization`, returns `nil` on malformed input — no crash). |
| V6 Cryptography | yes | All crypto is delegated to `DCAppAttestService` (Apple) via `DCAppAttestAttestationService` — `clientDataHash = SHA-256(challenge)` per D-06. Phase 6 writes **no** crypto. The `SHA256.hash` call lives inside the already-shipped service. Never hand-roll. |

### Known Threat Patterns for this stack (App Attest / iOS / Keychain)

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Attestation bytes / `attestedKeyId` / challenge leak into logs or crash reports | Information Disclosure | D6-07 / `04-PATTERNS.md` Pattern A — log only event name + `AttestationStatus.rawValue`; never `String(describing: NSError)`; CLAUDE.md "zero PII in analytics or crash logs". Pitfall 3 is the concrete trap. |
| `trustTier` spoofed client-side to suppress the limited-trust banner | Tampering / Spoofing | `trustTier` is **backend-driven** (D-12) — the client is a passive renderer. The Keychain item is written only from a `/device/register` response, and Keychain `.afterFirstUnlockThisDeviceOnly` items are not user-editable on a non-jailbroken device. The banner being informational (not a gate) bounds the impact. |
| First-login attestation failure used to *block* a legitimate login (DoS-by-strictness) | Denial of Service | D6-05 — transient attestation failure degrades to `.softwareOnly` and **still completes login**. App Attest is never a login gate. This is a deliberate availability-over-strictness posture matching Phase 4 D-09. |
| DEBUG test seam (`uiTestTrustTierOverride`) shipping in Release and forging `trustTier` | Elevation / Tampering | D6-03 *removes* the seam entirely — strictly better than the current `#if DEBUG`-gated state. The remaining `-MockOTPTrustTierForUITest` launch arg is parsed only inside `#if DEBUG` blocks in `SceneDelegate` (Release compiles to zero bytes — confirmed by source read of the `#if DEBUG` gates). |
| Stale `kycStatus` causing a fail-closed *misroute* (WARNING-1) | (correctness, not a classic STRIDE) | D6-08 — refreshing `kycStatus` after `GET /kyc/status` fixes the misroute. Note: the routing already fails **closed** (any non-"verified" value → KYC gate); D6-08 is a correctness fix to that fail-closed logic, **not** a relaxation. The planner must preserve fail-closed semantics — never route to the role shell on a stale/absent value. |

## Sources

### Primary (HIGH confidence — all in-repo, read this session)

- `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` — STEP 5 wiring site; line drift documented below.
- `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` — `OTPViewModel` construction site (`:51`).
- `validationLedger/Core/Attestation/{AttestationService,AttestedKeyStore,AttestationStatus,TrustTier,AttestationError,SimulatorBypassAttestationService,DCAppAttestAttestationService}.swift`.
- `validationLedger/Core/Networking/Endpoints/{DeviceRegisterEndpoint,DeviceChallengeEndpoint,KYCStatusEndpoint}.swift`.
- `validationLedger/Core/Networking/Interceptors/AttestationErrorResponseInterceptor.swift` — confirms `challengeExpired` is NOT in `canonicalTriggerCodes`.
- `validationLedger/Core/Networking/Mock/{MockDefaultFixtures,MockOTPRoleFixtureRegistry}.swift`.
- `validationLedger/Core/Networking/NetworkError.swift`, `Core/Storage/Keychain/KeychainKey.swift`.
- `validationLedger/App/{AppSession,AppContainer,AppCoordinator,SceneDelegate}.swift` — heartbeat path `performHeartbeatIfNeeded` is the orchestration template.
- `validationLedger/UI/LimitedTrustBannerView.swift`, `validationLedger/Roles/RoleCoordinator.swift` (`wrapWithLimitedTrustBanner`).
- `validationLedger/Features/Onboarding/KYC/{KYCStatusViewModel,KYCCoordinator}.swift`.
- Test surface: `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift`, `validationLedgerTests/Attestation/{FakeAttestationService,ChallengeExpiredRetryTest,AttestationErrorResponseInterceptorTest}.swift`, `validationLedgerUITests/LimitedTrustBannerTests.swift`, `validationLedgerDeviceTests/AppAttestRoundTripTests.swift`.
- `.planning/v1.0-MILESTONE-AUDIT.md` (scope source), `.planning/REQUIREMENTS.md` (DEV-04/CI-03), `.planning/ROADMAP.md` (Phase 4 SC + Phase 6 entry), `.planning/phases/04-app-attest-physical-device-ci-hardening/{04-CONTEXT.md,deferred-items.md}`, `.planning/phases/05-kyc-capture-upload-pipeline/05-VERIFICATION.md` (verification format template).
- `./CLAUDE.md` (project constraints).

### Secondary / Tertiary

None — no WebSearch/Context7 was needed. Phase 6 is a closed-world wiring phase over an existing codebase; every claim is grep- or read-verified against the tree.

## Project Constraints (from CLAUDE.md)

Actionable directives the planner must hold the plans to — these have the same authority as locked decisions:

- **UIKit-first.** All camera/KYC/scanner/BOL screens must be UIKit. Phase 6 touches no UI rendering except `LimitedTrustBannerView` (already UIKit) — no SwiftUI may be introduced. `AppSession` stays a plain `@MainActor` class (D6-10 — observation via NotificationCenter or closure, **not** SwiftUI `@Observable`/`ObservableObject`).
- **SwiftPM only — no CocoaPods/Carthage.** Phase 6 adds zero dependencies; this is automatically satisfied.
- **iOS 17.0 minimum** (CLAUDE.md states 17; the tech-stack block says 26.4 deployment target — the planner should follow whichever the `.xcodeproj` actually sets; do not lower it). No API below the project's deployment target.
- **Zero PII in analytics or crash logs.** Directly governs D6-07 — see Pitfall 3 and the Security Domain. No `attestationObject` / `attestedKeyId` / challenge bytes / `NSError.userInfo` in any `Logger` call.
- **All tokens in Keychain; all keys in Secure Enclave; nothing sensitive in `UserDefaults`.** `device.trustTier` correctly goes in Keychain (D6-01/D6-02), never `UserDefaults`. The App Attest key stays in the Secure Enclave (Apple-managed).
- **TestFlight closed beta for v1; App Store is M5.** No distribution work in Phase 6.
- **Dependencies: pre-approved shortlist only.** Apple `DeviceCheck` (App Attest) is on the list; Phase 6 uses only already-present frameworks.
- **iOS never calls Anthropic directly / US-only logins.** Not touched by Phase 6.
- **Team size 1–2 engineers + AI tools → architectural simplicity** (MVVM+Coordinators, initializer DI). The `OTPViewModel` DI growth (Claude's discretion) must stay initializer-DI — no Swinject, no service locator. `AuthCoordinator.swift:51` is the single construction site.
- **GSD workflow enforcement.** All Phase 6 edits go through the GSD execute-phase flow (already the case).

## Line-Number Drift vs CONTEXT.md (verified this session)

CONTEXT.md's line references were checked against the current tree. Minor drift — no decision is invalidated:

| CONTEXT.md reference | CONTEXT.md says | Actual (verified) | Note |
|----------------------|-----------------|-------------------|------|
| `OTPViewModel.swift` STEP 5 | `:187-218` | STEP 5 marker at `:187`; block ends `~:218` | Accurate. |
| `OTPViewModel.swift` stale comment | `:189-193` | comment block `:188-193` | 1-line drift. |
| `OTPViewModel.swift` `_ = try await ...` discard | `:202-211` (the `.unsupported` hardcode) | `_ = try await` at `:202`; `attestationStatus: .unsupported` at `:208`; block `:202-211` | Accurate. |
| `OTPViewModel.swift` `kycStatus` write | `:156-164` | `:156-164` | Accurate. |
| `AuthCoordinator.swift` `OTPViewModel(...)` | `:51` | `:50-59` (call spans; opens at `:51`) | Accurate. |
| `AppContainer.uiTestTrustTierOverride` | declared `:~66-72`, read `:~390-397` | declared `:75`; seeding read `:394-398` (the `#if DEBUG` `AppSession` branch); **plus** the launch-arg consumer write in `SceneDelegate.swift:187` | **3 sites total**, not 2: (1) the `static var` declaration `AppContainer.swift:75`; (2) the read at `AppContainer.swift:394-398`; (3) the *write* at `SceneDelegate.swift:187` (`AppContainer.uiTestTrustTierOverride = uiTestTrustTier`). All three must be deleted; the surrounding `-MockOTPTrustTierForUITest` parsing in `SceneDelegate` stays. |
| `AppContainer.makeKYCStatusScreen()` | `:~178-185` | `:177-185` | Accurate. |
| `SceneDelegate.performHeartbeatIfNeeded` | `:~568-651` | `:568-651` | Accurate. |
| `SceneDelegate` `uiTestTrustTierOverride` removal site | `:~172-187` | `:172-187` (the `-MockOTPTrustTierForUITest` block; the override write is line `187`) | Accurate. |
| `AppCoordinator` `wrapWithLimitedTrustBanner` call | `:~83` | `:83` | Accurate. |
| `KYCCoordinator.pushStatus()` | `:~497` | `pushStatus()` at `:489`; `onVerified` wiring at `:497` | Accurate. |
| `validationLedger(Device)Tests/Attestation/` suites | implied a device-side `Attestation/` dir | **No** `validationLedgerDeviceTests/Attestation/` directory exists. The Attestation unit suites are in `validationLedgerTests/Attestation/`; the device-side App Attest test is the single file `validationLedgerDeviceTests/AppAttestRoundTripTests.swift`. | Place new first-login attestation **unit** tests in `validationLedgerTests/` (alongside `OTPViewModelTests`); no new device-test file is required for Phase 6 (`04-VERIFICATION.md` cites the existing `AppAttestRoundTripTests` device run). |

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every component read directly from source this session; no training-data inference.
- Architecture: HIGH — the orchestration template (`performHeartbeatIfNeeded`) and the container-swap problem (`presentRoot` building a fresh `AppContainer`) were both read and confirmed.
- Pitfalls: HIGH for Pitfalls 2-6 (source-verified). HIGH for Pitfall 1 (the `challengeExpired` gap) — confirmed by exhaustive grep returning zero production hits + reading the interceptor's `canonicalTriggerCodes`. This is the single most important finding for the planner.

**Research date:** 2026-05-18
**Valid until:** 2026-06-17 (30 days — stable in-repo codebase; the only thing that would invalidate it is intervening edits to `OTPViewModel` / `AttestationService` / `AppContainer`).
