# Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification - Pattern Map

**Mapped:** 2026-05-18
**Files analyzed:** 8 modified + 1 new doc + ~6 new/extended test files
**Analogs found:** 9 / 9 (all in-codebase — this is a wiring phase, every analog already exists)

> This is a gap-closure / wiring phase. Every "analog" below is an already-shipped,
> already-tested project file. The planner should treat the excerpts as the
> exact code shape to mirror — not as inspiration. Line numbers are verified
> against the current tree (RESEARCH.md "Line-Number Drift" table — trusted over CONTEXT.md).

## File Classification

| Modified / New File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `validationLedger/Core/Attestation/AttestedKeyStore.swift` | service (Keychain wrapper) | file-I/O (Keychain) | self — `read/writeAttestedKeyId` + `read/writeLastHeartbeatAt` in the same file | exact (self-analog) |
| `validationLedger/Core/Storage/Keychain/KeychainKey.swift` | config (key registry) | n/a (static constants) | self — `attestedKeyId` / `lastHeartbeatAt` statics in the same file | exact (self-analog) |
| `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` | view-model | request-response orchestration | `SceneDelegate.performHeartbeatIfNeeded` (`SceneDelegate.swift:568-651`) | role-match (same orchestration shape, one endpoint different) |
| `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` | coordinator (DI construction site) | n/a (composition) | self — existing `OTPViewModel(...)` call at `:51-59` | exact (self-analog) |
| `validationLedger/App/AppSession.swift` | model (mutable state holder) | event-driven (observable mutation) | project NotificationCenter precedent (`.sessionDidInvalidate`) OR `OTPViewModel.onStateChange` closure | role-match (D6-10 discretion) |
| `validationLedger/App/AppContainer.swift` | provider (composition root) | n/a (composition) | self — existing `AppSession` construction at `:394-398`; `makeKYCStatusScreen()` at `:177-185` | exact (self-analog) |
| `validationLedger/App/AppCoordinator.swift` | coordinator (root-VC builder) | event-driven (banner re-render) | self — `wrapWithLimitedTrustBanner` call at `:83` | exact (self-analog) |
| `validationLedger/App/SceneDelegate.swift` | scene lifecycle | n/a (deletion site) | self — `uiTestTrustTierOverride` write at `:187` | exact (self-analog — deletion) |
| `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift` | view-model | request-response (GET /kyc/status) | `OTPViewModel.swift:156-164` kycStatus Keychain write | role-match (same Keychain write pattern, different trigger) |
| `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md` | doc artifact | n/a | `05-VERIFICATION.md` (frontmatter + Goal Achievement + Observable Truths + Requirements Coverage + Human Verification) | role-match (structural template) |

## Pattern Assignments

### `AttestedKeyStore.swift` — add `readTrustTier()` / `writeTrustTier(_:)` (D6-01)

**Role:** service (Keychain wrapper) | **Data flow:** file-I/O
**Analog:** self — the existing `readAttestedKeyId`/`writeAttestedKeyId` pair (`AttestedKeyStore.swift:43-60`).

**Exact pattern to copy** (`AttestedKeyStore.swift:43-60`):
```swift
/// Returns the persisted attestedKeyId, or `nil` if never written (first
/// install or post-clearPersistedKeyId). Throws only on unexpected
/// Keychain errors — `itemNotFound` is translated to `nil`...
public func readAttestedKeyId() throws -> String? {
    do {
        let data = try keychain.get(.attestedKeyId)
        return String(data: data, encoding: .utf8)
    } catch KeychainError.itemNotFound {
        return nil
    }
}

/// Writes `keyId` (UTF-8 bytes) to Keychain under `.attestedKeyId` with
/// `.afterFirstUnlockThisDeviceOnly` accessibility (D-01).
public func writeAttestedKeyId(_ keyId: String) throws {
    try keychain.set(
        Data(keyId.utf8),
        for: .attestedKeyId,
        accessibility: .afterFirstUnlockThisDeviceOnly
    )
}
```

**New methods to add** (the `itemNotFound → nil` translation + `.afterFirstUnlockThisDeviceOnly`
class are non-negotiable — copy them exactly). `TrustTier` is `RawRepresentable: String`, so it
round-trips like a string — but unlike `attestedKeyId`, guard the `TrustTier(rawValue:)` re-hydration:
```swift
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
Add a `// MARK: - trustTier` section and a header-comment lifecycle note mirroring the
existing `attestedKeyId` / `lastHeartbeatAt` lifecycle block (`AttestedKeyStore.swift:13-23`).
**Note:** `AttestedKeyStore` has no `deleteTrustTier` — D6-02 keeps the item across logout;
do not add a delete accessor and do not wire it into `LogoutService`.

---

### `KeychainKey.swift` — add `device.trustTier` static (D6-02)

**Role:** config (key registry) | **Data flow:** n/a
**Analog:** self — the `attestedKeyId` / `lastHeartbeatAt` statics (`KeychainKey.swift:35-40`).

**Exact pattern to copy** (`KeychainKey.swift:35-40`):
```swift
// Phase 4 DEV-04 (D-01, D-03): App Attest identifier + last-heartbeat-timestamp Keychain entries.
// Both MUST NOT be members of KeychainScope.session — D-03 preserves attestedKeyId across logout
// so the same install presents the same attestation after re-login. Raw values are referenced
// by name in downstream plans (03, 06, 07, 09); do NOT rename.
public static let attestedKeyId    = KeychainKey(rawValue: "device.attestedKeyId")
public static let lastHeartbeatAt  = KeychainKey(rawValue: "device.lastHeartbeatAt")
```

**New static to add** — joins the SAME attestation group (the `device.` prefix is the grouping
convention; it is deliberately NOT `session.`):
```swift
// Phase 6 DEV-04 (D6-01/D6-02): backend-driven trustTier, persisted across the
// post-OTP container swap (ADR 0002 abrupt-replace). MUST NOT be a member of
// KeychainScope.session — preserved across logout (D6-02), like device.attestedKeyId.
public static let trustTier        = KeychainKey(rawValue: "device.trustTier")
```
**Critical (RESEARCH Pitfall — KeychainScope):** verify `KeychainScope` / `KeychainScope.session`
does NOT enumerate `.trustTier`. `session.kycStatus` IS in `.session` (it gets wiped on logout —
`KeychainKey.swift:33`); `device.trustTier` must NOT be.

---

### `OTPViewModel.swift` — STEP 5 attestation orchestration + response capture (DEV-04 / D6-04..D6-07 / D6-01)

**Role:** view-model | **Data flow:** request-response orchestration
**Primary analog (THE template):** `SceneDelegate.performHeartbeatIfNeeded` (`SceneDelegate.swift:568-651`).

**Core orchestration pattern to mirror** (`SceneDelegate.swift:586-622`) — the key-gen guard,
challenge fetch, base64-decode guard, and crypto-call sequence:
```swift
// Ensure we have an attested key (D-01: idempotent; returns existing on hit).
let (keyId, status) = try await container.attestationService.generateKeyIfNeeded()
guard status == .attested || status == .simulatorBypass else {
    // No usable key — backend already routed to .softwareOnly; skip.
    container.logger.warn(
        event: .init("attestation_heartbeat_skipped_no_key"),
        fields: [.event: status.rawValue]
    )
    return
}

// Fetch challenge (D-05). base64-decode to raw bytes for D-06 SHA-256.
let challengeResponse = try await container.apiClient.request(DeviceChallengeEndpoint())
guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else {
    container.logger.error(event: .init("attestation_heartbeat_bad_challenge"), fields: [:])
    return
}

// Generate assertion (D-07 — SHA-256(challenge) inside the service).
let assertion = try await container.attestationService.generateAssertion(
    keyId: keyId, challenge: challengeData)
```

**The first-login delta vs. the heartbeat template** (apply each row when adapting):

| Step | Heartbeat (template) | First-login (Phase 6, in `OTPViewModel.verify()` STEP 5) |
|------|----------------------|-----------------------------------------------------------|
| key | `generateKeyIfNeeded()`; guard `.attested \|\| .simulatorBypass` | **same** — but a non-passing status is NOT a `return`; it is D6-04 graceful skip → carry `status` into the register payload, `attestedKeyId/attestationObject = nil` |
| challenge | `apiClient.request(DeviceChallengeEndpoint())`; base64-decode | **same** — but a thrown challenge error is D6-05 degrade → `attestationStatus = .error`, omit fields, **still POST register** |
| crypto | `generateAssertion(keyId:challenge:)` | **`attestKey(keyId:challenge:)`** — returns the `attestationObject: Data` |
| POST | `DeviceHeartbeatEndpoint` | **`DeviceRegisterEndpoint`** (already 6-arg with attestation fields) |
| result | `session.trustTier = response.trustTier` (direct, same container) | **`attestedKeyStore.writeTrustTier(response.trustTier)`** (Keychain — cross-swap channel, D6-01) |
| failure posture | silent-fail, role shell still renders | **D6-05 degrade-and-continue**; login is never blocked |

**Site being replaced** (`OTPViewModel.swift:187-218`) — the stale comment block `:188-193` MUST be
deleted (it is the promise this phase fulfills); the `_ = try await` discard at `:202` becomes a
captured `let registerResp = try await ...`:
```swift
// === STEP 5: POST /device/register ... ===   <-- REPLACE :187-218
state = .settingUp(progress: 4, total: 6)       // KEEP total:6 — fold attestation into this slot (RESEARCH Pitfall 4)
do {
    let fingerprint = try DeviceFingerprint.current(keychain: keychain)
    let payload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
        model: fingerprint.model,
        iosVersion: fingerprint.iosVersion,
        installUUID: fingerprint.installUUID
    )
    _ = try await apiClient.request(            // <-- DISCARD `_ =` must become a captured `let`
        DeviceRegisterEndpoint(
            devicePublicKey: devicePub.base64EncodedString(),
            authorizationPublicKey: authPub.base64EncodedString(),
            attestedKeyId: nil,                  // <-- becomes real value or nil per D6-04/D6-05
            attestationObject: nil,              // <-- becomes real value or nil
            attestationStatus: .unsupported,     // <-- becomes the real status
            fingerprint: payload
        )
    )
} catch {
    logger.warn(event: .init("device_register_failed"),
                fields: [.event: String(describing: error)])
    state = .registerFailed
    return
}
```

**D6-07 PII discipline — CRITICAL (RESEARCH Pitfall 3):** the existing STEP 5 `catch` at `:212-214`
uses `fields: [.event: String(describing: error)]`. The non-attestation catch blocks (`:132`,
`:166`, `:181`, `:213`, `:229`) keep that idiom — but the NEW attestation catch blocks MUST NOT.
Mirror the heartbeat path's discipline (`SceneDelegate.swift:639-650`):
```swift
} catch {
    // PII discipline: do NOT include error.userInfo or .localizedDescription — those
    // may contain diagnostic bytes. Only the event name carries context.
    container.logger.error(event: .init("attestation_heartbeat_failed"), fields: [:])
}
```
For the graceful-skip log, use the closed-set enum rawValue only — `fields: [.event: status.rawValue]`
(`SceneDelegate.swift:591-594`). Never `String(describing:)` on an `AttestationError` / `NSError`.

**D6-06 `challengeExpired` retry — GENUINELY NEW CODE (RESEARCH Pitfall 1 / BLOCKER-ADJACENT):**
There is NO existing production `challengeExpired` handling — grep returns zero hits; the
`AttestationErrorResponseInterceptor` covers `attestationInvalid`/`nonceExpired`/`keyCompromised`
only. D6-06 is net-new. The detection helper to reuse is `AttestationErrorResponseInterceptor.extractErrorCode(from:)`
(`AttestationErrorResponseInterceptor.swift:132` — `internal static`, accepts both `error_code` and
`errorCode`). The register POST surfaces a stale challenge as `NetworkError.httpError(statusCode, data)`
carrying the body. Recommended shape (inline in STEP 5, keeps the orchestration self-contained):
```swift
// On NetworkError.httpError from the register POST, parse the body:
catch let NetworkError.httpError(_, data)
    where AttestationErrorResponseInterceptor.extractErrorCode(from: data) == "challengeExpired" {
    // refetch GET /device/challenge → re-attestKey → retry register ONCE.
    // A second consecutive challengeExpired surfaces (no second retry — D6-06 "once").
}
```

**`retryRegister()` is idempotent (RESEARCH Pitfall 2):** `retryRegister()` (`:278-281`) just calls
`verify()` again. After Phase 6 that re-runs the attestation orchestration — fine: `generateKeyIfNeeded`
is once-per-install (D-01), `attestKey` is re-callable, `/device/register` is Idempotency-Key-protected
(NET-04). The new RED tests MUST cover the retry path, not just the happy path.

---

### `AuthCoordinator.swift` — `OTPViewModel` DI surface growth (D6-01, Claude's discretion)

**Role:** coordinator (DI construction site) | **Data flow:** n/a
**Analog:** self — the existing `OTPViewModel(...)` call (`AuthCoordinator.swift:50-59`), the SINGLE construction site.

**Exact pattern to extend** (`AuthCoordinator.swift:50-59`):
```swift
private func pushOTP(otpSessionID: String) {
    let vm = OTPViewModel(
        otpSessionID: otpSessionID,
        apiClient: container.apiClient,
        keychain: container.keychainStore,
        keyStore: container.keyStore,
        biometric: container.biometricService,
        sessionLock: container.sessionLock,
        logger: container.logger
    )
```
`OTPViewModel` needs (a) `AttestationService` — pass `container.attestationService`; and (b) a path
to write `trustTier`. Two options for (b), planner's discretion:
- pass `container.keychainStore` (already passed as `keychain`) and have `OTPViewModel` construct
  `AttestedKeyStore(keychain:)` internally — `SceneDelegate.performHeartbeatIfNeeded` does exactly
  this (`SceneDelegate.swift:570`: `let attestedKeyStore = AttestedKeyStore(keychain: container.keychainStore)`); OR
- inject an `AttestedKeyStore` directly into the `OTPViewModel` initializer.
Keep initializer-DI (CLAUDE.md / ARCH-04) — no service locator. The `OTPViewModel.init`
(`OTPViewModel.swift:88-104`) and this call site are the two places the new args land.

---

### `AppSession.swift` — make `trustTier` observable (D6-10, Claude's discretion)

**Role:** model (mutable state holder) | **Data flow:** event-driven
**Current shape** (`AppSession.swift:36-47`):
```swift
@MainActor
public final class AppSession {
    public var trustTier: TrustTier
    public init(trustTier: TrustTier = .softwareOnly) {
        self.trustTier = trustTier
    }
}
```

**Two project-precedent mechanisms — pick one (D6-10 discretion):**
1. **NotificationCenter post** — precedent: the project's `.sessionDidInvalidate` notification.
   Add a `didSet` on `trustTier` that posts a `Notification.Name` (e.g. `.trustTierDidChange`);
   `AppCoordinator` adds an observer that rebuilds / toggles the banner.
2. **Closure/observer on `AppSession`** — precedent: `OTPViewModel.onStateChange: ((State) -> Void)?`
   (`OTPViewModel.swift:41-46, 61`). Add `var onTrustTierChange: ((TrustTier) -> Void)?` fired from
   a `didSet`; `AppCoordinator` assigns it.

**Constraints (RESEARCH Project Constraints):** `AppSession` STAYS a plain `@MainActor final class`
— do NOT introduce SwiftUI `@Observable` / `ObservableObject` (UIKit-first). The banner change is
shown **WITHOUT animation** (D6-10 / ADR 0002 abrupt-replace).

---

### `AppContainer.swift` — seed `AppSession` from Keychain, delete `uiTestTrustTierOverride`, wire `onVerified` (D6-01 / D6-03 / D6-09)

**Role:** provider (composition root) | **Data flow:** n/a
**Analog:** self — three distinct sites in the same file.

**(D6-01 + D6-03) Replace the `AppSession` construction** (`AppContainer.swift:386-398`). Current:
```swift
#if DEBUG
self.session = AppSession(trustTier: AppContainer.uiTestTrustTierOverride ?? .softwareOnly)
#else
self.session = AppSession(trustTier: .softwareOnly)
#endif
```
`attestedKeyStore` is already constructed in `init` at `AppContainer.swift:374`
(`let attestedKeyStore = AttestedKeyStore(keychain: self.keychainStore)`). Replace the whole
`#if DEBUG` block with a single seed read — the DEBUG branch is DELETED (D6-03):
```swift
// D6-01: seed AppSession.trustTier from the persisted device.trustTier so the
// LimitedTrustBanner is correct from frame 1 on cold boot AND the post-OTP role shell
// (the auth-phase trustTier survives the ADR 0002 abrupt-replace via Keychain).
let seededTier = (try? attestedKeyStore.readTrustTier()) ?? .softwareOnly
self.session = AppSession(trustTier: seededTier)
```
**(D6-03) Also delete:** the `uiTestTrustTierOverride` static declaration at `AppContainer.swift:75`
(and its comment block `:66-74`). RESEARCH confirms exactly 3 sites: declaration (`:75`),
seed-read (`:394-398`, replaced above), and the SceneDelegate write (`:187`, below). After deletion,
`grep -r uiTestTrustTierOverride validationLedger/` must return 0. Do NOT touch `uiTestLocationProvider`
/ `uiTestCountryGate` / `kycTestSeed` — only the trustTier override goes.

**(D6-09) Wire `onVerified` in `makeKYCStatusScreen()`** (`AppContainer.swift:177-185`). Current
factory omits the `onVerified` callback, leaving a dead "Continue" button:
```swift
@MainActor
func makeKYCStatusScreen() -> UIViewController {
    let viewModel = KYCStatusViewModel(
        apiClient: apiClient,
        store: kycSessionStore,
        logger: logger
    )
    return KYCStatusViewController(viewModel: viewModel)   // <-- onVerified never set
}
```
**Analog for the wiring** — `KYCCoordinator.pushStatus()` (`KYCCoordinator.swift:497-499`):
```swift
viewModel.onVerified = { [weak self] in
    self?.onKYCSubmitted?()        // <-- routes to role shell — WRONG for the Profile entry
}
```
**Do NOT copy that routing literally** (RESEARCH A4 / Open Question 2). The Profile entry is
ALREADY inside the role shell — "Continue to role shell" is a no-op-equivalent. `onVerified` here
must **dismiss / pop the modally-presented KYC status screen back to the Profile tab**. This factory
has no coordinator/route, so the dismissal must be done via the returned `UIViewController` (or a
presenter handle the planner threads in). Surface this micro-decision in the plan for checker confirmation.

---

### `SceneDelegate.swift` — delete the `uiTestTrustTierOverride` write (D6-03)

**Role:** scene lifecycle | **Data flow:** n/a (deletion site)
**Site** (`SceneDelegate.swift:172-187`) — the `-MockOTPTrustTierForUITest` parsing block. Delete
ONLY the override write at `:187`:
```swift
let uiTestTrustTier: TrustTier = { ... }()        // KEEP — drives the mock fixture's trust_tier
MockOTPRoleFixtureRegistry.registerForRole(role, trustTier: uiTestTrustTier)   // KEEP
AppContainer.uiTestLocationProvider = StubLocationProviderForUITest()          // KEEP
AppContainer.uiTestCountryGate = StubCountryGateForUITest()                    // KEEP
AppContainer.uiTestTrustTierOverride = uiTestTrustTier                         // <-- DELETE this line only
```
After D6-01's consumer is wired, the `MockOTPRoleFixtureRegistry` fixture's `trust_tier` flows
through `OTPViewModel` → Keychain → `AppContainer` → `AppSession` → banner naturally. The
`-MockOTPTrustTierForUITest` launchArg + the `uiTestTrustTier` computation + the
`MockOTPRoleFixtureRegistry.registerForRole(...)` call all STAY (RESEARCH Anti-Pattern).
**Sequencing (RESEARCH Pitfall 6):** this deletion must land in the SAME wave as, or AFTER,
D6-01's consumer wiring — never before, or `LimitedTrustBannerTests` loses its trustTier source.

**Also note:** `performHeartbeatIfNeeded` (`SceneDelegate.swift:568-651`) is the orchestration
template for `OTPViewModel` STEP 5 (see that section) — it is NOT itself modified in Phase 6.

---

### `AppCoordinator.swift` — banner re-render wiring (D6-10)

**Role:** coordinator (root-VC builder) | **Data flow:** event-driven
**Analog:** self — the `wrapWithLimitedTrustBanner` call (`AppCoordinator.swift:82-83`).

**Current site** (`AppCoordinator.swift:69-83`, the `.role(role)` case):
```swift
case .role(let role):
    // Phase 4 D-11 + D-12: wrap the role tab bar with the non-dismissible
    // limited-trust banner when container.session.trustTier != .hardwareAttested.
    let tabBar = Self.roleCoordinator(for: role, container: container)
    self.rootViewController = tabBar.wrapWithLimitedTrustBanner(trustTier: container.session.trustTier)
```
Today the banner is computed ONCE at role-shell construction; a later heartbeat mutation is
invisible until the next root-swap (WARNING-2). D6-10: subscribe to the `AppSession` observation
mechanism chosen in `AppSession.swift` and re-apply / remove the banner wrapper on mutation,
**without animation**. The observer wiring should sit alongside the existing post-init callback
wiring in this file (`AppCoordinator.swift:87-100`, where `auth.onAuthenticated` etc. are wired
after `self` is fully initialized — use the same `[weak self]` discipline).

---

### `KYCStatusViewModel.swift` — refresh Keychain `kycStatus` after `GET /kyc/status` (D6-08 / WARNING-1)

**Role:** view-model | **Data flow:** request-response (GET /kyc/status)
**Analog:** `OTPViewModel.swift:156-164` — the existing `kycStatus` Keychain write at OTP-verify.

**Exact write pattern to mirror** (`OTPViewModel.swift:156-164`):
```swift
if let kycStatus = verifyResp.kycStatus {
    try keychain.set(Data(kycStatus.utf8),
                     for: .kycStatus,
                     accessibility: .afterFirstUnlockThisDeviceOnly)
} else {
    try keychain.delete(.kycStatus)
}
```
**Where it goes:** `KYCStatusViewModel.fetchStatus()` (`KYCStatusViewModel.swift:131-149`) currently
fetches `GET /kyc/status` and maps to a `State` — it does NOT persist the result. After a successful
fetch (after `response = try await apiClient.request(KYCStatusEndpoint())` at `:135`), write the
fresh `overall_status` string to Keychain `.kycStatus` with the SAME `.afterFirstUnlockThisDeviceOnly`
class, so the fail-closed cold-boot `SessionRestoreProbe` routes on current truth.

**DI growth (RESEARCH Wave 0):** `KYCStatusViewModel` does NOT currently hold a `KeychainStore` —
its init is `(apiClient:, store:, logger:)` (`:117-125`). D6-08 grows its DI surface to add a
`KeychainStore`. The TWO construction sites both need the new arg:
- `AppContainer.makeKYCStatusScreen()` (`AppContainer.swift:179-183`)
- `KYCCoordinator.pushStatus()` (`KYCCoordinator.swift:490-494`)
Both already have `container.keychainStore` available. Keep initializer-DI.

**Fail-closed semantics (RESEARCH Security Domain):** D6-08 is a CORRECTNESS fix to fail-closed
routing — it must NOT relax it. A non-"verified" / absent status still routes to the KYC gate;
D6-08 only ensures the cached value is *fresh*. Preserve the `verified` / non-`verified` distinction.

---

### `04-VERIFICATION.md` — retroactive Phase 4 verification (D6-11 / D6-12)

**Role:** doc artifact | **Data flow:** n/a
**Analog:** `05-VERIFICATION.md` — the structural template.
**Location:** `.planning/phases/04-app-attest-physical-device-ci-hardening/04-VERIFICATION.md`

**Required structure** (mirror `05-VERIFICATION.md`): frontmatter → `## Goal Achievement`
→ `### Observable Truths` table → `### Requirements Coverage` table → `### Human Verification Required`.
**Scope (D6-12):** verify ALL THREE Phase 4 success criteria (SC-1 App Attest at first login,
SC-2 graceful skip, SC-3 device-CI gate) + DEV-04 + CI-03 — a full re-verification, not just the
closed gap. Cite the EXISTING `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` device
run for SC-1/SC-3 evidence (no new device test required — RESEARCH Drift table). Phase 6 also
ticks the still-unchecked roadmap `04-10` checkbox in `.planning/ROADMAP.md`.
**Sequencing (D6-11 / RESEARCH Pitfall 5):** this is the LAST wave — `depends_on` every preceding
Phase 6 wave; SC-1 only passes once D6-01..D6-07 land.

## Shared Patterns

### Pattern A — PII discipline for attestation logging (D6-07)

**Source:** `SceneDelegate.performHeartbeatIfNeeded` (`SceneDelegate.swift:591-594`, `:639-650`);
governed by Phase 4 `04-PATTERNS.md` Pattern A + CLAUDE.md "zero PII in analytics or crash logs".
**Apply to:** every NEW attestation-related `catch` / log call in `OTPViewModel.verify()` STEP 5.
```swift
// Closed-set enum rawValue only — safe:
container.logger.warn(event: .init("attestation_..._skipped_no_key"),
                      fields: [.event: status.rawValue])
// Bare event name — safe when there is no closed-set field:
container.logger.error(event: .init("attestation_..._failed"), fields: [:])
```
**Anti-pattern (RESEARCH Pitfall 3):** `fields: [.event: String(describing: error)]` is the idiom
used by `OTPViewModel`'s NON-attestation catches (`:132`, `:166`, `:181`, `:213`, `:229`) — it is
fine there, but copying it into an attestation catch leaks `NSError.userInfo` diagnostic bytes.
A RED source-grep test should assert the attestation catch blocks contain no `String(describing:`.

### Pattern B — D-09 omission rule is automatic (no field-stripping code)

**Source:** `DeviceRegisterEndpoint` (`DeviceRegisterEndpoint.swift:44-51, 72-88`).
**Apply to:** `OTPViewModel` STEP 5 payload construction.
`DeviceRegisterEndpoint.RequestBody.attestedKeyId` and `.attestationObject` are `Optional`. Swift's
`JSONEncoder` drops `Optional.none` entirely (no `null` on the wire — `DeviceRegisterEndpoint.swift:14-17`).
On a non-`.attested` / `.error` status, just pass `nil` for both — omission is free. Do NOT write a
task that "strips attestation fields"; `DeviceRegisterOmissionTests` already pins this.

### Pattern C — Keychain write accessibility class

**Source:** `OTPViewModel.swift:141-159`, `AttestedKeyStore.swift:54-59, 87-94`.
**Apply to:** `AttestedKeyStore.writeTrustTier` (D6-01) AND the D6-08 `kycStatus` refresh.
Every session/device Keychain write in this codebase uses `.afterFirstUnlockThisDeviceOnly`. New
writes MUST use the same class — never `UserDefaults`, never a different accessibility (CLAUDE.md).

### Pattern D — initializer-DI, single construction site

**Source:** ARCH-04 / CLAUDE.md ("team size 1-2 → architectural simplicity"); precedent
`OTPViewModel.init` (`:88-104`), `KYCStatusViewModel.init` (`:117-125`).
**Apply to:** the `OTPViewModel` DI growth (D6-01) and the `KYCStatusViewModel` DI growth (D6-08).
All new dependencies go through the initializer — no Swinject, no service locator. When a VM's init
grows, update EVERY construction site (`OTPViewModel`: 1 site — `AuthCoordinator.swift:51`;
`KYCStatusViewModel`: 2 sites — `AppContainer.swift:179` + `KYCCoordinator.swift:490`).

## No Analog Found

| File / behavior | Role | Data Flow | Reason |
|-----------------|------|-----------|--------|
| `challengeExpired` detect → challenge refetch → register retry-once (inside `OTPViewModel` STEP 5, D6-06) | error-recovery logic | request-response | **No existing production analog.** Grep for `challengeExpired` returns zero production hits; `AttestationErrorResponseInterceptor` handles only `attestationInvalid`/`nonceExpired`/`keyCompromised`, and those use a different recovery (key-clear, not challenge-refetch). The ONLY reusable piece is `AttestationErrorResponseInterceptor.extractErrorCode(from:)` (`AttestationErrorResponseInterceptor.swift:132`) for parsing the `error_code` body field. The retry control-flow itself is genuinely new code — the planner must scope it as implementation, unit-tested with an injected `MockURLProtocol` fixture (`challengeExpired` body on first POST, 200 on retry). See RESEARCH Pitfall 1 / Open Question 1: the planner should also surface to the user whether D6-06 can be descoped given the M1 mock backend never emits `challengeExpired`. |

## Metadata

**Analog search scope:**
`validationLedger/Core/Attestation/`, `validationLedger/Core/Storage/Keychain/`,
`validationLedger/Core/Networking/Endpoints/`, `validationLedger/Core/Networking/Interceptors/`,
`validationLedger/Features/Onboarding/Auth/`, `validationLedger/Features/Onboarding/KYC/`,
`validationLedger/App/`.

**Files scanned (read this session):** `AttestedKeyStore.swift`, `KeychainKey.swift`,
`OTPViewModel.swift`, `AuthCoordinator.swift`, `AppSession.swift`, `AppContainer.swift` (3 ranges),
`AppCoordinator.swift`, `SceneDelegate.swift` (2 ranges), `KYCStatusViewModel.swift`,
`KYCCoordinator.swift`, `DeviceRegisterEndpoint.swift`, `DeviceChallengeEndpoint.swift`,
`AttestationService.swift`, `AttestationErrorResponseInterceptor.swift` (grep).

**Pattern extraction date:** 2026-05-18
