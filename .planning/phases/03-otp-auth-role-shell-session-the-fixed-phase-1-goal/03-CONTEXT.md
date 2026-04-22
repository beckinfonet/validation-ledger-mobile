# Phase 3: OTP Auth + Role Shell + Session — Context

**Gathered:** 2026-04-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire OTP auth + 5 role shells + session lock + US-geo pre-check end-to-end so any of the 5 roles (Shipper, Broker, Carrier, Dispatch, Factoring) can:

1. Enter an E.164 phone number → submit
2. Receive (mocked) SMS OTP → enter `123456` → verify
3. Land on a role-distinct tab shell whose tabs match TechStack.md §4 verbatim
4. Cold-boot back into that session without re-OTP, *and* see a biometric prompt (via `SessionLockService`) before content is visible
5. After >5 minutes background → biometric re-prompt on return
6. Cleanly log out from a top-bar Profile affordance (Keychain wiped, SE `authorizationKey` ACL cleared, role coordinator stack torn down, root-swap to phone-entry)
7. Refused client-side if `CLLocationManager` reports country ≠ US (raw coordinates never reach analytics — enforced at compile time)

**This phase is the "fixed Phase 1 visible win" referenced in the roadmap title** — Phase 1 deliberately built scaffolding so this phase becomes mostly wiring + product-flow code rather than from-scratch architecture.

**In scope (18 requirements):** AUTH-01..06, SHELL-01..04, SESS-01..04, GEO-01..03, DEV-06.

**Out of scope (fixed by ROADMAP.md):**
- App Attest productionization + physical-device CI hardening (Phase 4: DEV-04, CI-03)
- KYC capture + resumable upload (Phase 5: KYC-*, UPL-*)
- Sensitive-action call sites (tender, accept, BOL) — Phase 3 ships AUTH-06 *infrastructure* with an empty action list; M2+ adds call sites

</domain>

<decisions>
## Implementation Decisions

### Auth flow architecture (AUTH-01..05, SHELL-01..04)

- **D-01:** **Dedicated `AuthCoordinator` in `Features/Onboarding/Auth/`** — owns a `UINavigationController` hosting `PhoneEntryViewController` → `OTPViewController`. On verify success calls `onAuthenticated(role:)` callback that bubbles to `AppCoordinator` → `SceneDelegate` root-swaps to `.role(role)`. Mirrors the planned `KYCCoordinator` pattern (REQUIREMENTS KYC-01) and the existing `Roles/RoleCoordinator` symmetry.
- **D-02:** **AUTH-02 rate-limit countdown comes from the backend, NOT iOS local count.** Backend returns HTTP 429 with `Retry-After` header on the 4th OTP-verify attempt. `APIClient` parses `Retry-After` into a typed `NetworkError.rateLimited(retryAfter: TimeInterval)`. `OTPViewModel` starts a 1-Hz `Timer` that decrements + disables the Verify button; on countdown=0 → enables button, clears error. **New fixture required:** `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` + `MockURLProtocol` handler that returns 429 + `Retry-After: 60`.
- **D-03:** **Top-bar avatar affordance for Profile + logout** — preserves TechStack.md §4 tab inventory verbatim. Each role's `UITabBarController` adds a `UINavigationItem.rightBarButtonItem` (or left, planner's call) showing a circular avatar/initial; tap presents a modal `ProfileViewController` with the logout button. **No 5th "Profile" tab is added to any role.** This resolves the Phase 1 deferred question explicitly recorded in `01-CONTEXT.md`'s Deferred Ideas section.

### Session restore on cold-boot (SESS-01)

- **D-04:** **`SessionRestoreService` in `Core/Auth/`** with `func probe() -> SessionRestoreResult` returning `.restored(role: Role)` or `.needsAuth`. Reads Keychain for both `sessionToken` and a cached `role` string. **"Valid" client-side = both Keychain items present.** No JWT exp parse, no `/auth/me` round-trip. Backend's first authenticated call returns 401 if the token is server-side stale → AUTH-05 auto-logout fires.
- **D-05:** **`SceneDelegate` runs the probe before first `presentRoot(_:)`** — replaces the current Phase 1 default of `presentRoot(.role(.shipper))`. If `.restored(role)` → `presentRoot(.role(role))`; if `.needsAuth` → `presentRoot(.auth)`. Phase 3 also adds `case .auth` handling in `AppCoordinator.makeRoot(for:)` (currently a placeholder VC) — instantiates `AuthCoordinator`.
- **D-06:** **After OTP-verify success, cache `role` + `userID` in Keychain** (alongside the `sessionToken` already mandated by AUTH-03). The `OTPVerifyEndpoint.Response` already exposes `sessionToken: String`, `role: String`, `userID: String` — three new Keychain writes after a successful verify, all under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

### SessionLockService Phase 3 extension (SESS-01..04)

- **D-07:** **`SessionLockService` API extends to `func lockState(now: Date) -> LockState`** where `LockState = .unlocked | .locked(reason: LockReason)` and `LockReason = .coldBoot | .backgroundTimeout | .biometricReEnrolled | .neverUnlocked`. The existing `shouldRequireBiometric(now:) -> Bool` may stay as a convenience wrapper or be deleted — planner chooses based on call-site count. Callers branch on `LockReason` for UX copy on the BiometricLockViewController.
- **D-08:** **`SessionLockService` self-subscribes to `UIApplication.didEnterBackgroundNotification` + `didBecomeActiveNotification` in init.** Takes a `NotificationCenter` injected dep (default `.default`); holds observer tokens; removes them in `deinit`. **SessionLockService gains a UIKit import** (currently Foundation-only) — acceptable trade for keeping the trigger contract self-contained.
- **D-09:** **Biometric re-enrollment detection (SESS-03) uses `LAContext.evaluatedPolicyDomainState` diff** — Apple's canonical approach. Persist `domainState` (Data) in Keychain after each biometric success. On `lockState(now:)` call, instantiate a fresh `LAContext`, read its current `domainState`, compare to stored. If changed → return `LockState.locked(reason: .biometricReEnrolled)`. The `BiometricLockViewController` for that reason routes the user to a "re-bind device" placeholder (which in M1 is a stub VC with support contact, since the re-bind flow itself is M2+).
- **D-10:** **`Core/Auth/BiometricService` is the LAContext wrapper** (or whatever name the planner picks — could be inside SessionLockService). Exposes `func evaluate(reason: String, fallback: BiometricFallback) async throws -> Void` where `BiometricFallback = .none | .devicePasscode`. Used by both the session-unlock path (passes `.devicePasscode`) and `SensitiveActionService` (passes `.none` — strict biometric).

### AUTH-06 Sensitive-action infrastructure (M1: empty action list)

- **D-11:** **Dedicated `SensitiveActionService` in `Core/Auth/`** with protocol `func authorize(_ payload: Data, reason: String) async throws -> Signature`. Implementation:
  1. Calls `BiometricService.evaluate(reason:, fallback: .none)` — strict biometric, no passcode
  2. On success calls `keyStore.sign(slot: .authorization, payload:)` which (because the SE key has `.biometryCurrentSet` ACL) AUTOMATICALLY re-prompts biometric a second time. Planner decides whether to suppress the explicit `evaluate` step and rely solely on the SE-driven biometric — both are valid; simpler is better
  3. Maps `LAError` codes to typed `SensitiveActionError`: `.userCancel`, `.biometryLockout`, `.biometricReEnrolled`, `.signFailed(underlying:)`
- **D-12:** **M1 wiring: `SensitiveActionService` is constructed in `AppContainer` and exposed as a property; ZERO call sites in M1.** AUTH-06 explicitly says "M1 wires the re-prompt infrastructure but the sensitive-action list is empty." A unit test asserts the service is constructible and its `authorize` method exists with the correct signature; that is the entirety of M1's AUTH-06 surface.

### Biometric host UX (SESS-01..03)

- **D-13:** **Full-screen `BiometricLockViewController` (dedicated VC overlaid modally).** When SceneDelegate observes `lockState != .unlocked` (timing: on `didBecomeActive`, on cold-boot probe, on app-foreground), it presents a full-screen `BiometricLockViewController` over the role shell (or over the role-shell-being-prepared in the cold-boot case). Logo + reason-specific copy + "Unlock" button that retriggers `LAContext` on tap. **Content is never visible behind it** — meets Success Criterion 2 ("shows a biometric prompt BEFORE content is visible") unambiguously.
- **D-14:** **Reason-specific copy** (planner finalizes exact strings):
  - `.coldBoot` → "Welcome back" + "Verify identity to continue"
  - `.backgroundTimeout` → "Session paused" + "Verify to continue"
  - `.biometricReEnrolled` → "Biometric changed" + "You'll need to re-bind this device" → routes to a stub re-bind placeholder
  - `.neverUnlocked` → same as `.coldBoot`
- **D-15:** **Session-unlock LAContext policy = `.deviceOwnerAuthentication`** (biometric with device-passcode fallback). After biometric failures, iOS auto-falls-back to passcode. The system enforces its own biometric lockout (5 system-level failures → passcode required) — no extra app-level limit. **NOTE: sensitive-action authorization (AUTH-06) stays strict biometric-only** because the SE `authorizationKey` ACL is `.biometryCurrentSet` — passcode cannot unlock that key, by design.

### Logout teardown contract (SESS-04, AUTH-04)

- **D-16:** **Dedicated `LogoutService` in `Core/Auth/` is the single source of truth** — `func logout(reason: LogoutReason) async`. Orchestration order:
  1. Clear in-memory session state (any `currentRole`/`currentUserID` props)
  2. `keychainStore.deleteAll(under: .session)` — wipes `sessionToken`, cached `role`, `userID`
  3. `keyStore.deleteKey(slot: .authorization)` — `SecItemDelete` on the SE `authorizationKey` (the `deviceKey` is preserved across logout — it's device identity, not session-bound)
  4. Clear stored `LAContext.evaluatedPolicyDomainState` from Keychain
  5. `sessionLock.invalidate()`
  6. Post `.sessionDidInvalidate` `Notification` with `userInfo[.logoutReason] = reason`
- **D-17:** **Three call sites of `LogoutService.logout(reason:)`:**
  - `ProfileViewController` "Log out" tap → `.userInitiated`
  - `APIClient` response interceptor on HTTP 401 → `.auth401` (AUTH-05)
  - DEV-06 path on backend "another active session" response → `.anotherActiveSession`

### DEV-06 routing

- **D-18:** **Extend `AppPhase` enum: add `case anotherActiveSession`.** SceneDelegate observes `.sessionDidInvalidate`; reads `reason` from `userInfo`; maps:
  - `.userInitiated` → `presentRoot(.auth)`
  - `.auth401` → `presentRoot(.auth)`
  - `.anotherActiveSession` → `presentRoot(.anotherActiveSession)`
- **D-19:** **New `AnotherActiveSessionViewController` in `Features/Onboarding/Auth/`** (or a new `Features/Onboarding/AccountStatus/` group — planner picks). Copy: explanation that another device is signed in; re-KYC required to switch (M2+); plus a "Contact support" affordance (planner decides the form — `mailto:`, `tel:`, or in-app composer; defaults to `mailto:` to a constant defined in `Environment.supportEmail`).

### Geo pre-check (GEO-01..03)

- **D-20:** **Location request fires at phone-entry Submit, BEFORE `POST /auth/otp/request`.** `PhoneEntryViewModel` orchestrates:
  1. `locationManager.requestWhenInUseAuthorization()`
  2. Await fresh `CLLocation` (planner picks acceptance window — recommended <30s age, <100m horizontal accuracy)
  3. Reverse-geocode via `CLGeocoder.reverseGeocodeLocation`
  4. If `placemark.isoCountryCode != "US"` → push `NotAvailableInRegionViewController`, no POST fires
  5. If US → POST `/auth/otp/request`; coordinates attached to the request payload (NOT to logs/analytics — see D-23)
- **D-21:** **Permission-denied = blocking state with Settings deep-link.** PhoneEntryViewController shows a "Location required for US-only verification" state (modal or in-place panel — planner picks): copy + "Open Settings" button (`UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`) + "Try again" button that re-runs the location flow. Submit stays disabled until permission granted. Matches GEO-02 ("refuse to submit an auth attempt if country ≠ US" — no location = cannot verify country = refuse).
- **D-22:** **Country ≠ US = dedicated `NotAvailableInRegionViewController`** pushed onto the auth nav. Copy: "Validation Ledger is currently available only in the United States." + "Learn more" link (planner picks form) + "Try again" button (re-runs location). Terminal in this nav stack — user can't accidentally retry via Submit on phone-entry.

### GEO-03 phantom-typed AnalyticsEvent (Phase 1 D-19 deferred)

- **D-23:** **Two disjoint type families enforce "coordinates only flow to platform-API payloads" at compile time:**
  - **`AnalyticsField`/`LogField`** (existing — verify by code grep): MUST NOT have any `.coordinate` / `.latitude` / `.longitude` / `.location` case. If a case like that exists, delete it as part of Phase 3.
  - **NEW `Core/Identity/PlatformPayloadField.swift`** enum: `case coordinate(CLLocationCoordinate2D)`, `case timestamp(Date)`, etc. Consumed ONLY by `Core/Networking/Endpoints/` payload builders for auth/tender/accept/scan endpoints. Analytics + Logger APIs cannot accept this type — wrong parameter type → compile error.
  - **Compile-time invariant:** because `AnalyticsField` doesn't have a coordinate case and `Logger` only takes `[LogField]`, there is *no syntactic way* to pass a coordinate to a log/analytics call. A future engineer who tries gets a "type X cannot be converted to LogField" compile error.
- **D-24:** **New SwiftLint custom rule: `ban_raw_coordinate_literal`** (the rule Phase 1 D-19 deferred to here). Pattern: regex match on `CLLocationCoordinate2D(latitude:` outside an allow-list of paths:
  - `validationLedger/Core/Networking/Endpoints/**` (auth + tender + accept + scan endpoint payload builders)
  - `validationLedger/Core/Identity/Geo*/**` (the geo subsystem itself)
  - `validationLedger*Tests/**` (tests construct fixtures)
  - Any file fail outside the allow-list → SwiftLint error → CI fail. Lives in `.swiftlint.yml` alongside the four Phase 1 custom rules (`ban_print`, `ban_direct_os_log`, `ban_userdefaults_tokens`, `no_cross_feature_import`).
- **D-25:** **Pre-Phase-3 carryover fixes are part of Phase 3 scope** (these are explicitly enumerated in `PROJECT.md`'s "Pre-Phase-3 required fixes" section and MUST land before the first `/device/register` call works correctly):
  - **CR-02 (Phase 2 review):** `SecureEnclaveKeyStore.generateKey(slot:)` needs idempotent guard — second call silently inserts a new key alongside the old; `loadPrivateKey` may return the old key → pub/priv mismatch. 5-line fix at top of `generateKey`.
  - **IN-01/05 (Phase 2 review):** 4 `RequestBody` properties with acronym tails need explicit `CodingKeys` (`otpSessionID` in `OTPVerifyEndpoint.RequestBody`, `uploadID` in two upload endpoints, `installUUID` in `DeviceRegisterEndpoint.DeviceFingerprintPayload`). Without these, `.convertToSnakeCase` produces `otp_session_i_d`-style mangled wire keys that break the first real call. One `case` line per property.
  - **IN-02 (Phase 2 review):** SoftwareKeyStore (sim) returns 64-byte compact ECDSA; SecureEnclaveKeyStore (device) returns DER X9.62 — backend receives different wire-format bytes sim vs device. Pick ONE format at the protocol level (planner recommends DER X9.62 since that's what real Apple SE returns; SoftwareKeyStore wraps to match).

### Claude's Discretion

The following gray areas were not discussed and default to the choices below. The planner will confirm or adjust:

- **D-26 (Phone-entry input UX):** US-only `+1` country code locked (implied by GEO-02). Input field accepts digits only (`UIKeyboardType.phonePad`), formats display as `(XXX) XXX-XXXX` for readability while retaining E.164 internally for submission. No country picker (US-only — picker would be misleading). Submit button enabled when input has 10 digits.
- **D-27 (`/device/register` orchestration timing):** Sequential after OTP-verify success, BEFORE `presentRoot(.role(role))`. Order:
  1. OTP-verify returns 200 + sessionToken/role/userID
  2. Persist sessionToken/role/userID to Keychain (D-06)
  3. `SecureEnclaveKeyStore.generateKey(slot: .device)` (DEV-01) — idempotent guard from D-25 ensures re-runs are safe
  4. `SecureEnclaveKeyStore.generateKey(slot: .authorization)` (DEV-02)
  5. POST `/device/register` with `devicePublicKey` + `deviceFingerprint` (DEV-05)
  6. `BiometricService.evaluate(reason: "Sign in to Validation Ledger", fallback: .none)` to record initial `domainState` and `lastSuccess` (D-09 + D-15)
  7. `presentRoot(.role(role))`
  Steps 3–6 happen on a "Setting up your account..." progress screen; step 5 failure shows retry without blowing away the session.
- **D-28 (`AUTH-05 401 interceptor wiring`):** New `Auth401ResponseInterceptor` in `Core/Networking/Interceptors/`. On any non-OTP-flow response with status 401, calls `LogoutService.logout(reason: .auth401)`. **Excluded paths:** `/auth/otp/request` and `/auth/otp/verify` (a 401 there means "wrong code", not "session expired"). Wired into the response interceptor chain in `AppContainer.apiClient` initialization.
- **D-29 (`lastSuccess` persistence in SessionLockService):** **In-memory only** for M1. Cold-boot intentionally returns `LockState.locked(reason: .coldBoot)` because `lastSuccess == nil` after a fresh process launch — that's the SESS-01/SC-2 product contract. Persisting `lastSuccess` to Keychain would enable a cold-boot "skip biometric" optimization that's explicitly unwanted.
- **D-30 (LogoutReason enum exact values):** `enum LogoutReason: String { case userInitiated, auth401, anotherActiveSession }` — string raw values for stable Notification userInfo encoding.
- **D-31 (Thread/actor model for LAContext + biometric paths):** All LAContext + biometric operations are `async throws` and run on a `MainActor`-bound service unless evidence shows otherwise — LAContext callbacks are documented to fire on an arbitrary queue, but UI-affecting state (BiometricLockViewController dismissal, Submit-button enabling) MUST land on main. Planner picks the exact actor isolation per file based on `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` defaults.
- **D-32 (CI-02 placeholder smoke tests upgrade):** Phase 1 shipped 5 placeholder `RoleShellSmokeTests` (one per role). Phase 3 makes them real per Success Criterion 1 — each test launches with a `-MockOTPRoleForUITest <role>` launchArgument that drives the OTPVerify mock fixture to return that specific role; asserts the appropriate role TabBar renders + tab titles match TechStack.md §4 verbatim + logout returns to phone-entry. Five passing UI tests per Success Criterion 1.
- **D-33 (Cached role storage key):** Use `kSecAttrAccount` value `"session.role"` and `"session.userID"` for the new Keychain entries (alongside the existing `"session.token"`). The `KeychainStore.deleteAll(under: .session)` API is added if it doesn't already exist (a small Phase 3 KeychainStore extension).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### Product spec (authoritative)

- `TechStack.md §4` — role tab inventory (locked, no Profile tab added — see D-03)
- `TechStack.md §5.1` — FR-iOS-AUTH MUSTs (biometric re-prompt on >5min background, no keep-me-logged-in, sign sensitive requests with device key)
- `TechStack.md §5.3` — FR-iOS-DEV (Secure Enclave keypair on first login; refuse production launch without SE; one-active-device)
- `TechStack.md §5.4` — FR-iOS-GEO (CLLocationManager permission with clear purpose string; client-side US-only pre-check; never attach raw coordinates to analytics)

### Planning artifacts

- `.planning/PROJECT.md` — Phase 3 active scope; Pre-Phase-3 required fixes (CR-02, IN-01/05, IN-02)
- `.planning/REQUIREMENTS.md` — AUTH-01..06, SHELL-01..04, SESS-01..04, GEO-01..03, DEV-06 (the 18 requirements)
- `.planning/ROADMAP.md` — Phase 3 goal + 5 success criteria (this is the goal-backward target the planner verifies against)
- `.planning/STATE.md` — current session continuity
- `.planning/phases/01-foundational-conventions-scaffolding/01-CONTEXT.md` — D-09 tab inventory, deferred Profile question (resolved here in D-03), D-19 deferred GEO-03 SwiftLint rule (resolved here in D-24)
- `.planning/phases/02-networking-contract-device-keys/02-RESEARCH.md` — Pattern 7 (Secure Enclave two-key), authorizationKey `.biometryCurrentSet` ACL invalidation behavior

### Phase 1 Code (extension surfaces — DO NOT replace; add to)

- `validationLedger/Core/Auth/SessionLockService.swift` — current API: `shouldRequireBiometric(now:) -> Bool`, `recordBiometricSuccess(at:)`, `invalidate()`. Phase 3 extends to `lockState(now:) -> LockState` with `LockReason` enum (D-07) and self-subscribes to UIApplication notifications (D-08)
- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — two-key pattern; Phase 3 fixes CR-02 idempotent guard (D-25)
- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — `sign(slot:payload:)` API used by SensitiveActionService (D-11)
- `validationLedger/Core/Storage/Keychain/KeychainStore.swift` — Phase 3 adds `deleteAll(under:)` API used by LogoutService (D-16); new keys `session.role`, `session.userID` (D-33)
- `validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift` — Phase 3 consumer
- `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` — Phase 3 consumer; needs IN-01 acronym CodingKeys fix (D-25)
- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — Phase 3 first real consumer; needs IN-05 `installUUID` CodingKeys fix (D-25)
- `validationLedger/Core/Networking/APIClient.swift` — Phase 3 adds Auth401ResponseInterceptor + parses 429 Retry-After into `NetworkError.rateLimited` (D-02, D-28)
- `validationLedger/Core/Identity/DeviceFingerprint.swift` — Phase 3 consumer for `/device/register` (D-27 step 5)
- `validationLedger/App/SceneDelegate.swift` — Phase 3 changes default `presentRoot(.role(.shipper))` to use `SessionRestoreService.probe()` (D-05); adds `.sessionDidInvalidate` observer (D-18); adds `.anotherActiveSession` AppPhase routing (D-18)
- `validationLedger/App/AppCoordinator.swift` — Phase 3 fills `case .auth` in `makeRoot(for:)` with `AuthCoordinator` (D-01); fills `case .anotherActiveSession`; existing `onRoleResolved`/`onLogout` callbacks remain
- `validationLedger/App/AppContainer.swift` — Phase 3 adds construction of `SessionRestoreService`, `BiometricService`, `SensitiveActionService`, `LogoutService` (D-04, D-10, D-11, D-16); wires `Auth401ResponseInterceptor` into APIClient (D-28)
- `validationLedger/Roles/Shipper/ShipperTabBarController.swift` (and 4 sibling files) — Phase 3 adds top-bar avatar `UINavigationItem.rightBarButtonItem` (D-03)

### Phase 1 Tooling (extension)

- `.swiftlint.yml` — Phase 3 adds the 5th custom rule: `ban_raw_coordinate_literal` (D-24) alongside the existing four

### Test surfaces

- `validationLedgerTests/Networking/Fixtures/` — Phase 3 adds `otp-verify-rate-limited.json` (D-02); planner may add others for AUTH/DEV-06 paths
- `validationLedgerUITests/RoleShellSmokeTests*.swift` (placeholders from Phase 1) — Phase 3 makes them real per Success Criterion 1 (D-32)
- `validationLedgerDeviceTests/` — physical-device tests for SecureEnclave biometric paths land here; SC-2 (cold-boot biometric prompt) is HUMAN-UAT, SC-3 (>5min background biometric) is HUMAN-UAT

### Out of scope (deferred to other phases — DO NOT plan in Phase 3)

- App Attest assertion in `/device/register` payload — Phase 4 (DEV-04). The `DeviceRegisterEndpoint.RequestBody` is already structured to allow a non-breaking `attestation` field addition.
- Real backend URL — `Environment.apiBaseURL` stays `nil` for both DEBUG/Release (or PHASE-2-TODO marker) until backend exists
- Sensitive-action call sites (tender/accept/BOL signing) — M2+; Phase 3 ships `SensitiveActionService` infra with zero call sites (D-12)
- KYC capture / upload — Phase 5
- Background location for active loads — M3 (BG-01)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (carried from Phase 1 + Phase 2)

- **5 role TabBarControllers** (`ShipperTabBarController` and 4 siblings) — placeholders with TechStack.md §4 tabs already shipped. Phase 3 only adds the top-bar avatar affordance + wiring; does NOT reconstruct them.
- **`AppContainer` composition root** — initializer-DI; new Phase 3 services slot in
- **`SceneDelegate.presentRoot(_:)`** — fresh AppContainer per phase (D-10/ADR 0002); Phase 3 reuses for `.auth` and `.anotherActiveSession` routing
- **`AppPhase` enum** (`SceneDelegate.swift:9`) — `.launch | .auth | .role(Role)`; Phase 3 extends with `.anotherActiveSession` (D-18)
- **`AppCoordinator.onRoleResolved` and `.onLogout` callbacks** — already wired in Phase 1; Phase 3 fills the trigger paths
- **`SessionLockService` scaffold** — extend, don't replace (D-07)
- **`SecureEnclaveKeyStore` two-key pattern** — Phase 3 first real consumer of authorizationKey via `SensitiveActionService`
- **`OTPRequestEndpoint`/`OTPVerifyEndpoint`/`DeviceRegisterEndpoint`** typed structs — Phase 3 consumers; pre-Phase-3 fixes CR-02, IN-01/05, IN-02 land in Phase 3 (D-25)
- **`MockURLProtocol` fixture registry** — 14 fixtures shipped; Phase 3 adds `otp-verify-rate-limited.json`
- **`KeychainStore`** with access group + first-launch wipe (FOUND-02) — Phase 3 adds `deleteAll(under:)` API (D-16)
- **`PIIScrubber` + structured `Logger`** — Phase 3 uses for all logging; never `print` or direct `os_log`
- **`DeepLinkRouter`** queue-until-bootstrap — usable from Phase 3+ deep-link auth flows (out of M1 scope but the contract exists)

### Established Patterns (Phase 3 follows verbatim)

- **MVVM + Coordinators with initializer DI** — no singletons, no `.shared` (ARCH-04)
- **Abrupt root-swap with fresh AppContainer per AppPhase** (D-10/ADR 0002) — Phase 3 reuses for `.auth`/`.role`/`.anotherActiveSession` transitions
- **Cross-feature communication through `Core/` protocols only** (ARCH-05) — `AuthCoordinator` calls Profile/Logout via `Core/Auth/` services, never imports `Features/Profile/`
- **`#if DEBUG` compile-out for dev affordances** (D-13/D-14 from Phase 1) — any Phase 3 dev affordance follows same gate
- **Structured `LogField` PIIScrubber API** (D-16 from Phase 1) — Phase 3 uses for OTP/auth/lock/logout events; the `AnalyticsField` decision (D-23) extends this discipline to coordinates

### Integration Points (where Phase 3 wires into Phase 1+2 surfaces)

- `AppContainer.init` — registers SessionRestoreService, BiometricService, SensitiveActionService, LogoutService, Auth401ResponseInterceptor
- `SceneDelegate.scene(_:willConnectTo:options:)` — replaces hardcoded `.role(.shipper)` default with `SessionRestoreService.probe()` result
- `SceneDelegate` — adds `.sessionDidInvalidate` notification observer (alongside the existing `.devMenuNetworkConfigRequested` observer pattern)
- `AppCoordinator.makeRoot(for:)` — fills `.auth` and `.anotherActiveSession` cases
- `Roles/<Role>/<Role>TabBarController` × 5 — adds `UINavigationItem.rightBarButtonItem` for the avatar/profile affordance
- `Core/Networking/APIClient` — adds Auth401ResponseInterceptor; adds 429 Retry-After parsing into `NetworkError.rateLimited`
- `.swiftlint.yml` — adds 5th custom rule `ban_raw_coordinate_literal`

</code_context>

<specifics>
## Specific Ideas

- **The "fixed Phase 1 visible win" framing** — Phase 1 deliberately built the role-shell scaffolding so Phase 3 becomes mostly product-flow code. Plans should reflect this: most of Phase 3 is wiring + new VCs + service composition, NOT new Core/ subsystems
- **Top-bar avatar over Profile-as-5th-tab** — preserving TechStack.md §4 verbatim is more important than discoverability convenience
- **Backend-enforced rate-limit with Retry-After header** — iOS surfaces a backend-authoritative countdown; never count attempts locally (a process restart would reset, defeating AUTH-02's purpose)
- **Single LogoutService source of truth** — three different triggers (Profile tap, AUTH-05 401, DEV-06) MUST produce identical end states; symmetric teardown is a security guarantee, not a convenience
- **`.deviceOwnerAuthentication` (passcode fallback) for SESSION unlock; strict biometric for SENSITIVE actions** — different LAContext policies per flow; the SE ACL on `authorizationKey` enforces the latter at the hardware level
- **GEO-03 compile-time enforcement via type families, not runtime guards** — the only way to safely write the `AnalyticsField` enum is to *not* have a coordinate case; future-engineer-can't-add-coords-to-logs is the real product guarantee
- **Pre-Phase-3 carryover fixes (CR-02, IN-01/05, IN-02) are in scope** — without them the first `/device/register` call is broken, so they MUST land before Phase 3's wiring lights up the real path

</specifics>

<deferred>
## Deferred Ideas

### Resolved during this discussion (no longer deferred)

- ~~Profile tab placement~~ → resolved in D-03 (top-bar avatar affordance)
- ~~GEO-03 phantom-typed AnalyticsEvent + raw-coordinate SwiftLint ban~~ → resolved in D-23 + D-24

### Open clarifications routed to other phases

- **Real `/auth/me` endpoint and JWT exp validation** — explicitly deferred from cold-boot probe (D-04). When backend ships and the iOS team wants stronger session-validity guarantees pre-paint, this becomes a Phase 6+ refinement
- **Sensitive-action call sites** (tender, accept, BOL signing) — Phase 3 ships infra (D-11/D-12); M2+ adds call sites
- **App Attest assertion in `/device/register`** — Phase 4 (DEV-04); `DeviceRegisterEndpoint` is structured to add the field non-breakingly
- **Re-bind device flow** — Phase 3 ships a stub VC for `LockReason.biometricReEnrolled`; the actual re-bind flow (re-OTP + re-generate authorizationKey) is M2+
- **DEV-06 actual re-KYC switch flow** — Phase 3 ships placeholder `AnotherActiveSessionViewController`; re-KYC itself is M2+

### Future re-evaluation triggers

- **`lastSuccess` persistence (D-29)** — currently in-memory; revisit only if a future product decision wants to skip biometric on cold-boot for some sessions (which contradicts the current SESS-01/SC-2 contract)
- **Top-bar avatar vs eventual Profile tab** — if M2+ adds significant profile-management surface area (account settings, notification prefs, identity-status detail), revisit whether a Profile tab makes more sense than a modal

### Out of Phase 3 scope (existing phase assignments)

- App Attest productionization — Phase 4 (DEV-04)
- Physical-device CI hardening — Phase 4 (CI-03)
- KYC capture + resumable upload — Phase 5

### Scope-creep parking lot

None — discussion stayed within Phase 3 boundary.

</deferred>

---

*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Context gathered: 2026-04-21*
