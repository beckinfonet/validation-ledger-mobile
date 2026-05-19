# Phase 3: OTP Auth + Role Shell + Session — Research

**Researched:** 2026-04-21
**Domain:** UIKit auth orchestration (phone-entry → OTP → role shell), `LAContext` + Secure Enclave biometric flows, `CLLocationManager` + `CLGeocoder` US-pre-check, `URLSession` 429 Retry-After parsing, MVVM-C with initializer-DI through `AppContainer`, phantom-typed enum compile-time enforcement, SwiftLint custom regex rule, and three pre-Phase-3 Phase-2 carryover fixes (CR-02, IN-01/05, IN-02).
**Confidence:** HIGH for all 18 focus areas — every iOS API in scope (`LAContext`, `LAPolicy`, `evaluatedPolicyDomainState`, `CLLocationManager`/`CLGeocoder`, `SecKeyCreateSignature` + `kSecUseAuthenticationContext`, `UIApplication.didEnterBackgroundNotification`, `UINavigationItem.rightBarButtonItem`, `XCUIApplication.launchArguments`) is directly documented by Apple, exercised by an existing Phase 1+2 surface in this codebase, or both. The single MEDIUM-confidence area is the **double-prompt-vs-single-prompt** decision in `SensitiveActionService` (D-11/D-12) — the WWDC22 "Streamline local authorization" pattern is canonical, but D-12 explicitly says "M1 wires it; ZERO call sites" so the choice can be deferred to M2 with a one-line architectural note. CONTEXT.md's 33 locked decisions remove almost all design ambiguity from this phase — research is API-confirmation work, not design exploration.

<user_constraints>
## User Constraints (from 03-CONTEXT.md)

### Locked Decisions

The 33 decisions D-01..D-33 from `03-CONTEXT.md` are reproduced verbatim below. Planner MUST honor every one; researcher only fills gaps inside their boundaries.

#### Auth flow architecture (AUTH-01..05, SHELL-01..04)

- **D-01:** Dedicated `AuthCoordinator` in `Features/Onboarding/Auth/` — owns a `UINavigationController` hosting `PhoneEntryViewController` → `OTPViewController`. On verify success calls `onAuthenticated(role:)` callback that bubbles to `AppCoordinator` → `SceneDelegate` root-swaps to `.role(role)`. Mirrors the planned `KYCCoordinator` pattern (KYC-01) and the existing `Roles/RoleCoordinator` symmetry.
- **D-02:** AUTH-02 rate-limit countdown comes from the backend, NOT iOS local count. Backend returns HTTP 429 with `Retry-After` header on the 4th OTP-verify attempt. `APIClient` parses `Retry-After` into a typed `NetworkError.rateLimited(retryAfter: TimeInterval)`. `OTPViewModel` starts a 1-Hz `Timer` that decrements + disables the Verify button; on countdown=0 → enables button, clears error. New fixture: `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` + `MockURLProtocol` handler returning 429 + `Retry-After: 60`.
- **D-03:** Top-bar avatar affordance for Profile + logout — preserves TechStack.md §4 tab inventory verbatim. Each role's `UITabBarController` adds a `UINavigationItem.rightBarButtonItem` showing a circular avatar/initial; tap presents a modal `ProfileViewController` with the logout button. No 5th "Profile" tab on any role.

#### Session restore on cold-boot (SESS-01)

- **D-04:** `SessionRestoreService` in `Core/Auth/` with `func probe() -> SessionRestoreResult` returning `.restored(role: Role)` or `.needsAuth`. Reads Keychain for both `sessionToken` and a cached `role` string. "Valid" client-side = both Keychain items present. No JWT exp parse, no `/auth/me` round-trip. Backend's first authenticated call returns 401 if the token is server-side stale → AUTH-05 auto-logout fires.
- **D-05:** `SceneDelegate` runs the probe before first `presentRoot(_:)` — replaces the current Phase 1 default of `presentRoot(.role(.shipper))`. If `.restored(role)` → `presentRoot(.role(role))`; if `.needsAuth` → `presentRoot(.auth)`. Phase 3 also fills `case .auth` in `AppCoordinator.makeRoot(for:)` with `AuthCoordinator`.
- **D-06:** After OTP-verify success, cache `role` + `userID` in Keychain (alongside the `sessionToken` already mandated by AUTH-03). Three new Keychain writes after a successful verify, all under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

#### SessionLockService Phase 3 extension (SESS-01..04)

- **D-07:** `SessionLockService` API extends to `func lockState(now: Date) -> LockState` where `LockState = .unlocked | .locked(reason: LockReason)` and `LockReason = .coldBoot | .backgroundTimeout | .biometricReEnrolled | .neverUnlocked`. Existing `shouldRequireBiometric(now:)` may stay as a convenience wrapper or be deleted — planner chooses based on call-site count.
- **D-08:** `SessionLockService` self-subscribes to `UIApplication.didEnterBackgroundNotification` + `didBecomeActiveNotification` in init. Takes a `NotificationCenter` injected dep (default `.default`); holds observer tokens; removes them in `deinit`. SessionLockService gains a UIKit import.
- **D-09:** Biometric re-enrollment detection (SESS-03) uses `LAContext.evaluatedPolicyDomainState` diff. Persist `domainState` (Data) in Keychain after each biometric success. On `lockState(now:)` call, instantiate a fresh `LAContext`, read its current `domainState`, compare to stored. If changed → return `LockState.locked(reason: .biometricReEnrolled)`. The `BiometricLockViewController` for that reason routes the user to a "re-bind device" placeholder.
- **D-10:** `Core/Auth/BiometricService` is the LAContext wrapper. Exposes `func evaluate(reason: String, fallback: BiometricFallback) async throws -> Void` where `BiometricFallback = .none | .devicePasscode`. Used by both the session-unlock path (`.devicePasscode`) and `SensitiveActionService` (`.none` — strict biometric).

#### AUTH-06 Sensitive-action infrastructure (M1: empty action list)

- **D-11:** Dedicated `SensitiveActionService` in `Core/Auth/` with protocol `func authorize(_ payload: Data, reason: String) async throws -> Signature`. Implementation:
  1. Calls `BiometricService.evaluate(reason:, fallback: .none)` — strict biometric, no passcode.
  2. On success calls `keyStore.signWithAuthorization(payload)` which (because the SE key has `.biometryCurrentSet` ACL) AUTOMATICALLY re-prompts biometric a second time. Planner decides whether to suppress the explicit `evaluate` step and rely solely on the SE-driven biometric — both are valid; simpler is better.
  3. Maps `LAError` codes to typed `SensitiveActionError`: `.userCancel`, `.biometryLockout`, `.biometricReEnrolled`, `.signFailed(underlying:)`.
- **D-12:** M1 wiring: `SensitiveActionService` is constructed in `AppContainer` and exposed as a property; ZERO call sites in M1. A unit test asserts the service is constructible and its `authorize` method exists with the correct signature; that is the entirety of M1's AUTH-06 surface.

#### Biometric host UX (SESS-01..03)

- **D-13:** Full-screen `BiometricLockViewController` (dedicated VC overlaid modally). When SceneDelegate observes `lockState != .unlocked` (timing: on `didBecomeActive`, on cold-boot probe, on app-foreground), it presents a full-screen `BiometricLockViewController` over the role shell. Logo + reason-specific copy + "Unlock" button that retriggers `LAContext` on tap.
- **D-14:** Reason-specific copy:
  - `.coldBoot` → "Welcome back" + "Verify identity to continue"
  - `.backgroundTimeout` → "Session paused" + "Verify to continue"
  - `.biometricReEnrolled` → "Biometric changed" + "You'll need to re-bind this device" → routes to a stub re-bind placeholder
  - `.neverUnlocked` → same as `.coldBoot`
- **D-15:** Session-unlock LAContext policy = `.deviceOwnerAuthentication` (biometric with device-passcode fallback). After biometric failures, iOS auto-falls-back to passcode. Sensitive-action authorization (AUTH-06) stays strict biometric-only because the SE `authorizationKey` ACL is `.biometryCurrentSet`.

#### Logout teardown contract (SESS-04, AUTH-04)

- **D-16:** Dedicated `LogoutService` in `Core/Auth/` is the single source of truth — `func logout(reason: LogoutReason) async`. Orchestration:
  1. Clear in-memory session state.
  2. `keychainStore.deleteAll(under: .session)` — wipes `sessionToken`, cached `role`, `userID`.
  3. `keyStore.deleteKey(slot: .authorization)` — `SecItemDelete` on the SE `authorizationKey`. The `deviceKey` is preserved across logout — it's device identity, not session-bound.
  4. Clear stored `LAContext.evaluatedPolicyDomainState` from Keychain.
  5. `sessionLock.invalidate()`.
  6. Post `.sessionDidInvalidate` `Notification` with `userInfo[.logoutReason] = reason`.
- **D-17:** Three call sites: `ProfileViewController` "Log out" tap → `.userInitiated`; `APIClient` response interceptor on HTTP 401 → `.auth401`; DEV-06 path on backend "another active session" → `.anotherActiveSession`.

#### DEV-06 routing

- **D-18:** Extend `AppPhase`: add `case anotherActiveSession`. SceneDelegate observes `.sessionDidInvalidate`; reads `reason`; maps `.userInitiated`/`.auth401` → `presentRoot(.auth)`; `.anotherActiveSession` → `presentRoot(.anotherActiveSession)`.
- **D-19:** New `AnotherActiveSessionViewController` in `Features/Onboarding/Auth/` (or a new `Features/Onboarding/AccountStatus/` group). Copy: explanation that another device is signed in; re-KYC required to switch (M2+); plus a "Contact support" affordance (defaults to `mailto:` to a constant in `Environment.supportEmail`).

#### Geo pre-check (GEO-01..03)

- **D-20:** Location request fires at phone-entry Submit, BEFORE `POST /auth/otp/request`. `PhoneEntryViewModel` orchestrates: `requestWhenInUseAuthorization()` → await fresh `CLLocation` (<30s age, <100m horizontal accuracy) → `CLGeocoder.reverseGeocodeLocation` → if `placemark.isoCountryCode != "US"` push `NotAvailableInRegionViewController` (no POST fires) → if US → POST `/auth/otp/request`; coordinates attached to the request payload (NOT to logs/analytics).
- **D-21:** Permission-denied = blocking state with Settings deep-link (`UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`). Submit stays disabled until permission granted. **Reverse-geocode network failure = treat as "cannot verify country = refuse"** (matches GEO-02 defense-in-depth posture).
- **D-22:** Country ≠ US = dedicated `NotAvailableInRegionViewController` pushed onto the auth nav. Terminal in this nav stack — user can't accidentally retry via Submit on phone-entry.

#### GEO-03 phantom-typed AnalyticsField (Phase 1 D-19 deferred)

- **D-23:** Two disjoint type families enforce "coordinates only flow to platform-API payloads" at compile time:
  - `AnalyticsField`/`LogField` (existing): MUST NOT have any `.coordinate`/`.latitude`/`.longitude`/`.location` case. (Verified: `LogField` in `Core/Logging/Logger.swift` has `.coordinates` case but its label is the redaction sentinel, not a value-carrying coordinate slot — see "Specifics" below.)
  - NEW `Core/Identity/PlatformPayloadField.swift` enum: `case coordinate(CLLocationCoordinate2D)`, `case timestamp(Date)`, etc. Consumed ONLY by `Core/Networking/Endpoints/` payload builders. Analytics + Logger APIs cannot accept this type.
- **D-24:** New SwiftLint custom rule `ban_raw_coordinate_literal`. Pattern: `CLLocationCoordinate2D(latitude:` outside `validationLedger/Core/Networking/Endpoints/**`, `validationLedger/Core/Identity/Geo*/**`, `validationLedger*Tests/**`. Lives in `.swiftlint.yml` alongside the four Phase 1 custom rules.

#### Pre-Phase-3 carryover fixes (in scope)

- **D-25:** Three Phase-2 review items land in Phase 3:
  - **CR-02:** `SecureEnclaveKeyStore.generateKey(slot:)` idempotent guard — second call silently inserts a new key alongside the old.
  - **IN-01/05:** 4 `RequestBody` properties with acronym tails need explicit `CodingKeys` (`otpSessionID` in `OTPVerifyEndpoint.RequestBody`, `uploadID` in 2 upload endpoints, `installUUID` in `DeviceRegisterEndpoint.DeviceFingerprintPayload`).
  - **IN-02:** Pick ONE protocol-level signature format (DER X9.62 recommended); SoftwareKeyStore wraps to match.

#### Claude's Discretion (D-26 .. D-33)

- **D-26 (Phone-entry input UX):** US-only `+1` locked; `UIKeyboardType.phonePad`; format display as `(XXX) XXX-XXXX`; Submit enabled when 10 digits.
- **D-27 (`/device/register` orchestration):** 7-step sequence after OTP-verify (persist Keychain → device key → auth key → POST /device/register → BiometricService.evaluate → presentRoot). On a "Setting up your account..." progress screen; step-5 failure shows retry without blowing the session.
- **D-28 (`AUTH-05 401 interceptor`):** New `Auth401ResponseInterceptor` in `Core/Networking/Interceptors/`. On any non-OTP-flow 401 → `LogoutService.logout(reason: .auth401)`. Excludes `/auth/otp/request` and `/auth/otp/verify`.
- **D-29 (`lastSuccess` persistence):** In-memory only for M1. Cold-boot intentionally returns `LockState.locked(reason: .coldBoot)`.
- **D-30 (LogoutReason):** `enum LogoutReason: String { case userInitiated, auth401, anotherActiveSession }`.
- **D-31 (Thread/actor model):** All LAContext + biometric ops are `async throws` on a `MainActor`-bound service unless evidence shows otherwise.
- **D-32 (CI-02 placeholder smoke tests upgrade):** Each test launches with `-MockOTPRoleForUITest <role>` launchArgument that drives the OTPVerify mock fixture to return that specific role; asserts TabBar renders + tab titles match TechStack.md §4 verbatim + logout returns to phone-entry.
- **D-33 (Cached role storage key):** `kSecAttrAccount` values `"session.role"` and `"session.userID"`. `KeychainStore.deleteAll(under: .session)` API added.

### Claude's Discretion (research-level recommendations layered on D-26..D-33)

These are within the planner's authority to confirm/reject:

- **Reverse-geocode timeout** (D-20 fold): cap `CLGeocoder.reverseGeocodeLocation` call at 6 seconds via `Task.timeout`-style wrapper; on timeout treat as D-21 reverse-geocode-network-failure (refuse).
- **Cold-boot probe timing** (D-04 fold): probe runs synchronously in `SceneDelegate.scene(_:willConnectTo:)` before first `presentRoot`. Keychain read of `session.token` + `session.role` is a sub-millisecond operation; no need for an interim launch screen.
- **`SessionLockService.invalidate()` extension** (D-07 fold): existing `invalidate()` clears `lastSuccess`. Phase 3 also clears the stored `domainState` blob from Keychain on `invalidate()`. (This already lines up with D-16 step 4.)
- **`BiometricLockViewController` dismissal**: dismiss on the main actor after a `Task` completes biometric flow; avoid dismissing during the modal presentation animation (race trap).
- **`SensitiveActionService` D-11/D-12 single-vs-double-prompt resolution**: planner picks single-prompt via WWDC22 `kSecUseAuthenticationContext` pattern (researcher recommendation — see §iOS API #5/#13 below). M1 has zero call sites; the choice is encoded in the service implementation but exercised only by the constructibility unit test.

### Deferred Ideas (OUT OF SCOPE for Phase 3)

- App Attest assertion in `/device/register` payload — Phase 4 (DEV-04).
- Real backend URL — `Environment.apiBaseURL` stays `nil` for both DEBUG/Release until backend exists.
- Sensitive-action call sites (tender/accept/BOL signing) — M2+; Phase 3 ships infra with zero call sites.
- KYC capture / upload — Phase 5.
- Background location for active loads — M3 (BG-01).
- Real `/auth/me` endpoint and JWT exp validation — Phase 6+ refinement.
- Re-bind device flow (post `LockReason.biometricReEnrolled`) — Phase 3 ships a stub; full flow is M2+.
- DEV-06 actual re-KYC switch flow — Phase 3 ships placeholder VC; re-KYC itself is M2+.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (verbatim from REQUIREMENTS.md) | Research Support |
|----|---------------------------------------------|------------------|
| AUTH-01 | User enters US phone (E.164) on UIKit onboarding screen; client-side format + backend-authoritative validation | §iOS API #4 (E.164 input + format), §Recommended File Layout (PhoneEntry VC/VM), §Validation Architecture row AUTH-01 |
| AUTH-02 | SMS OTP (mocked `123456`); 3-failed-attempt rate limit (60s, backend-enforced; iOS surfaces countdown) | §iOS API #4 (Retry-After parsing), §Pre-Phase-3 carryover (none directly), §Validation Architecture row AUTH-02 |
| AUTH-03 | On verify, sessionToken stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Already supported by Phase 1 KeychainStore; §iOS API #14 (cold-boot probe), §Validation Architecture row AUTH-03 |
| AUTH-04 | Logout from Profile tab wipes Keychain, clears SE auth-key ACL, returns to phone-entry | §iOS API #16 (LogoutService teardown), §Recommended File Layout (LogoutService), §Validation Architecture row AUTH-04 |
| AUTH-05 | Auto-logout on backend 401; no "keep me logged in" | §iOS API #4 (interceptor wiring), §Recommended File Layout (Auth401ResponseInterceptor), §Validation Architecture row AUTH-05 |
| AUTH-06 | Sensitive actions infra (M1: empty action list, infra wired) | §iOS API #5 (SE biometric prompt), §iOS API #13 (single-vs-double-prompt), §Recommended File Layout (SensitiveActionService), §Validation Architecture row AUTH-06 |
| SHELL-01 | RoleCoordinator reads role from session payload, instantiates role-appropriate root | Already supported by `Roles/RoleCoordinator` + `AppCoordinator.roleCoordinator(for:)`; D-05 wires it; §Validation Architecture row SHELL-01 |
| SHELL-02 | 5 role TabBarControllers with TechStack §4 tabs (Phase 1 ships placeholders) | Already shipped Phase 1; §iOS API #8 (top-bar avatar), §Validation Architecture row SHELL-02 |
| SHELL-03 | Shared shell elements (top-level nav, profile/settings affordance) implemented once and reused | §iOS API #8 (`UINavigationItem.rightBarButtonItem` shared helper), §Recommended File Layout (ProfileViewController), §Validation Architecture row SHELL-03 |
| SHELL-04 | Role cannot be changed client-side (no "switch role" button) | No code change needed — preserved by D-05/D-06 (role is read-only from session payload), §Validation Architecture row SHELL-04 |
| SESS-01 | Session persists across cold boot; valid token skips OTP, goes to role shell | §iOS API #14 (SessionRestoreService.probe), §iOS API #6 (BiometricLockVC modal), §Validation Architecture row SESS-01 |
| SESS-02 | Background >5min triggers biometric; <5min does not | §iOS API #7 (UIApplication notifications self-subscription), §Validation Architecture row SESS-02 |
| SESS-03 | Biometric re-enrollment invalidates auth key; re-bind flow stub | §iOS API #1 (evaluatedPolicyDomainState diff), §Validation Architecture row SESS-03 |
| SESS-04 | Clean logout wipes Keychain tokens, SE auth-key ACL, in-memory session, role coordinator stack | §iOS API #16 (LogoutService teardown contract), §Validation Architecture row SESS-04 |
| GEO-01 | CLLocationManager permission with clear purpose string at first auth attempt | §iOS API #3 (CLLocationManager + Info.plist key), §Validation Architecture row GEO-01 |
| GEO-02 | Client-side US-only pre-check via reverse geocode; refuse non-US | §iOS API #3 (CLGeocoder + isoCountryCode), §Validation Architecture row GEO-02 |
| GEO-03 | Coordinates only flow to platform-API payloads; phantom-typed AnalyticsField makes raw coordinates un-attachable at compile time | §iOS API #9 (PlatformPayloadField design), §iOS API #10 (SwiftLint rule), §Validation Architecture row GEO-03 |
| DEV-06 | "Another active session" → switch device flow with placeholder + support contact | §iOS API #12 (AppPhase routing), §Recommended File Layout (AnotherActiveSessionViewController), §Validation Architecture row DEV-06 |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Phone entry UI + E.164 formatting | `Features/Onboarding/Auth/PhoneEntryViewController` (UIKit) | `Features/Onboarding/Auth/PhoneEntryViewModel` (Combine state) | Sensitive-surface UIKit per CLAUDE.md; ViewModel owns phone-format state + Submit-enable + location-permission state. |
| OTP entry UI + countdown | `Features/Onboarding/Auth/OTPViewController` (UIKit) | `Features/Onboarding/Auth/OTPViewModel` (1-Hz Timer) | Same UIKit-first rationale; ViewModel owns the countdown derived from `NetworkError.rateLimited(retryAfter:)`. |
| Auth flow navigation | `Features/Onboarding/Auth/AuthCoordinator` | `App/AppCoordinator` (parent) | Coordinator owns the `UINavigationController`; AppCoordinator constructs it for `case .auth`. |
| Session restore on cold-boot | `Core/Auth/SessionRestoreService` | `App/SceneDelegate` (caller) | Service is pure logic over Keychain reads; SceneDelegate calls `probe()` synchronously before `presentRoot`. |
| Biometric LAContext wrapper | `Core/Auth/BiometricService` | `App/AppContainer` (composition) | Wraps `LAContext.evaluatePolicy` + `evaluatedPolicyDomainState` read; consumed by `SessionLockService` + `SensitiveActionService`. |
| Session-lock state machine | `Core/Auth/SessionLockService` (extended) | `App/SceneDelegate` (observer of notifications) | Owns `lockState(now:)` + `LockReason`; self-subscribes to UIApplication notifications per D-08. |
| Sensitive-action infra | `Core/Auth/SensitiveActionService` | `Core/KeyStore/KeyStoreProtocol` (signWithAuthorization) | Single facade combining biometric prompt + SE signing for sensitive ops. M1: zero call sites. |
| Logout teardown | `Core/Auth/LogoutService` | `Core/Storage/Keychain/KeychainStore` + `Core/KeyStore/KeyStoreProtocol` + `Core/Auth/SessionLockService` | Single source of truth; three call sites all funnel through `logout(reason:)`. |
| 401 → auto-logout | `Core/Networking/Interceptors/Auth401ResponseInterceptor` | `Core/Auth/LogoutService` | Response interceptor in the existing chain; excludes OTP paths. |
| 429 Retry-After parsing | `Core/Networking/APIClient` (response decoder) | `Core/Networking/NetworkError` (typed case) | Parsed at the boundary where HTTPURLResponse becomes typed error; surfaced as `NetworkError.rateLimited(retryAfter:)`. |
| US-only geo pre-check | `Core/Identity/Geo/LocationProvider` (CLLocationManager wrapper) + `Core/Identity/Geo/CountryGate` (reverse geocode) | `Features/Onboarding/Auth/PhoneEntryViewModel` | Geo lives in `Core/Identity/` per ARCH-03 + the D-24 SwiftLint allow-list. |
| Coordinate-cannot-be-logged invariant | `Core/Identity/PlatformPayloadField` (NEW enum) | `.swiftlint.yml` `ban_raw_coordinate_literal` rule | Type-system enforcement (compile-time) + lint enforcement (CI-time) form belt-and-suspenders. |
| BiometricLockVC modal overlay | `Features/Onboarding/Auth/BiometricLockViewController` (UIKit) | `App/SceneDelegate` (presenter) | Presented from SceneDelegate over the role shell at the AppPhase boundary. |
| Profile modal | `Features/Profile/ProfileViewController` (UIKit) | Each role's `*TabBarController` (presenter via avatar `UIBarButtonItem`) | One VC; presented from any of the 5 tab bars via the shared helper in `Roles/RoleCoordinator` extension. |
| AnotherActiveSession placeholder | `Features/Onboarding/Auth/AnotherActiveSessionViewController` | `App/AppCoordinator` (`case .anotherActiveSession`) | Lives alongside other Onboarding/Auth VCs per D-19 (no new directory). |

**Why this matters:** Three boundaries are easy to violate and each has a downstream consequence:
1. **Logout MUST funnel through `LogoutService`** — three call sites (Profile tap, 401 interceptor, DEV-06) producing different end states is a Phase-3 security regression.
2. **Coordinates MUST stay in `Core/Networking/Endpoints/**` and `Core/Identity/Geo*/**`** — the lint rule + PlatformPayloadField enum together prevent leakage into logs/analytics. If a planner adds a coordinate to a `LogField` value, GEO-03 is silently violated.
3. **`SessionRestoreService.probe()` MUST run before `presentRoot` on cold-boot** — running after means the user briefly sees the wrong shell (Phase 1 default `.shipper`) then a swap, which fails SC-2 ("biometric prompt BEFORE content is visible").

## Standard Stack

### Core (all native iOS APIs — zero new SwiftPM deps)

| Library / API | Version | Purpose | Phase 3 Usage | Source |
|---------------|---------|---------|---------------|--------|
| `LocalAuthentication` (`LAContext`, `LAPolicy`, `LAError`) | iOS 17+ | Biometric prompt + domain-state read | Session unlock, sensitive-action authorize, SESS-03 re-enrollment detection | [VERIFIED: [Apple LAContext docs](https://developer.apple.com/documentation/localauthentication/lacontext)] |
| `CoreLocation` (`CLLocationManager`, `CLGeocoder`, `CLPlacemark`) | iOS 17+ | Location permission + reverse geocode → ISO country code | Phone-entry geo pre-check (GEO-01..02) | [VERIFIED: [Apple CLLocationManager docs](https://developer.apple.com/documentation/corelocation/cllocationmanager)] |
| `Security` framework (`SecKey*`, `SecAccessControl*`, `kSecUseAuthenticationContext`) | iOS 17+ | SE key signing + LAContext binding to SecKey ops | Phase 2's SecureEnclaveKeyStore + Phase 3's SensitiveActionService binding | [VERIFIED: [Apple Streamline local authorization WWDC22](https://developer.apple.com/videos/play/wwdc2022/10108/)] |
| `Foundation.URLSession` + `HTTPURLResponse` | iOS 17+ | 429 status + `Retry-After` header parsing | New `NetworkError.rateLimited(retryAfter:)` case | [VERIFIED: [MDN Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After), [HTTP.dev Retry-After](https://http.dev/retry-after)] |
| `Foundation.Notification` + `UIApplication.didEnterBackgroundNotification`/`didBecomeActiveNotification` | iOS 17+ | Background-time tracking trigger | `SessionLockService.init` self-subscribes (D-08) | [VERIFIED: [Apple UIApplication notifications](https://developer.apple.com/documentation/uikit/uiapplication)] |
| `UIKit.UINavigationItem` + `UIBarButtonItem` (custom view) | iOS 17+ | Top-bar avatar affordance | Each role TabBar's `selectedViewController?.navigationItem.rightBarButtonItem` (D-03) | [VERIFIED: [Apple UINavigationItem docs](https://developer.apple.com/documentation/uikit/uinavigationitem)] |
| `XCTest.XCUIApplication` (`launchArguments`) | iOS 17+ | UI-test driven mock-fixture selection | `-MockOTPRoleForUITest <role>` (D-32) | [VERIFIED: existing Phase 1 `RoleShellSmokeTests.swift` uses `-ForceRoleForUITest` already] |

### Supporting (none — Phase 3 adds ZERO new SwiftPM deps)

CLAUDE.md's pre-approved shortlist (`URLSession wrapper`, `KeychainAccess` or hand-rolled, Nuke/SDWebImage, Sentry/Firebase, CoreImage, AVFoundation, Vision) is more than enough — Phase 3 only uses `LocalAuthentication` + `CoreLocation` + iOS-bundled frameworks already permitted. No new dependency requires "explicit approval" because nothing new is being added.

### Alternatives Considered

| Instead of | Could Use | Why NOT in Phase 3 |
|------------|-----------|--------------------|
| `LAContext.evaluatePolicy(closure)` | `LAContext.evaluatePolicy(_:localizedReason:)` async/await variant | Phase 3 needs to fold biometric outcomes into a Combine/Concurrency-driven UI flow with `MainActor` UI dismissal. iOS 15+ ships an async/await variant (closure callback bridged automatically); use it. **However:** `evaluatedPolicyDomainState` is only set after a successful evaluation, so the call can't be skipped. [VERIFIED: [Apple evaluatePolicy docs](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:))] |
| `CLLocationManager` delegate pattern | `CLLocationUpdate.liveUpdates()` (iOS 17+) AsyncSequence | One-shot location for auth pre-check is not a stream. The continuation-bridged delegate pattern (or a one-shot `CLLocationUpdate.Once`-style wrapper) is simpler. Researcher recommends a `withCheckedThrowingContinuation` wrapper around the delegate (see §iOS API #3). [VERIFIED: [createwithswift Core Location async](https://www.createwithswift.com/updating-the-users-location-with-core-location-and-swift-concurrency-in-swiftui/)] |
| `MKLocalSearch.reverseGeocode` (MapKit) | `CLGeocoder.reverseGeocodeLocation` (CoreLocation) | MapKit reverse-geocode is for map-context use; CoreLocation's CLGeocoder is the standard for non-map auth flows. CLGeocoder's `placemark.isoCountryCode` returns ISO 3166-1 alpha-2 ("US" for the United States). [VERIFIED: [Apple CLGeocoder docs](https://developer.apple.com/documentation/corelocation/clgeocoder)] |
| Local rate-limit count in iOS | Backend Retry-After header (D-02 locked) | Process restart resets a local count, defeating AUTH-02. Backend is the source of truth. [LOCKED: D-02] |
| App Attest assertion in `/device/register` for Phase 3 | Defer to Phase 4 (DEV-04) | Out of scope for Phase 3. The endpoint is structured to accept an optional `attestation` field non-breakingly later. [LOCKED: ROADMAP.md Phase 4 boundary] |
| Phone-number formatting library (e.g., libphonenumber port) | Hand-rolled US-only `(XXX) XXX-XXXX` mask + E.164 conversion | US-only constraint (D-26) makes a 30-LOC formatter cheaper than adding a dependency. CLAUDE.md "shallow dep graph" preference. [LOCKED: D-26] |

### Version Verification

No new SwiftPM packages. iOS SDK primitives are tied to the iOS 17.0 deployment target (Phase 1).

```bash
# Confirm iOS deployment target unchanged
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 17.0" validationLedger.xcodeproj/project.pbxproj
# Expected: 8 (Phase 1 VERIFIED)

# Confirm no new SwiftPM deps added since Phase 2
grep -E "Alamofire|Moya|KeychainAccess|XCoordinator|SwiftLocation|AsyncLocationKit" Package.swift
# Expected: no output
```

## Architecture Patterns

### System Architecture Diagram (Phase 3 data flow)

```
COLD-BOOT PATH:
SceneDelegate.scene(_:willConnectTo:) ─▶ SessionRestoreService.probe()
                                              │
       ┌───────────────────┬──────────────────┴───┐
       ▼                   ▼                       ▼
   .needsAuth         .restored(role)         (read failure)
       │                   │                       │
       ▼                   ▼                       ▼
 presentRoot(.auth)  presentRoot(.role)    treat as .needsAuth
                          │
                          ▼
                  SessionLockService.lockState(now: .now)
                          │
        ┌─────────────────┼──────────────────┬───────────────────┐
        ▼                 ▼                  ▼                   ▼
   .locked(.coldBoot)  .locked(.bgTimeout) .locked(.bioReEnrolled) .unlocked
        │                 │                  │                   │
        ▼                 ▼                  ▼                   ▼
  present BiometricLockVC                                  no overlay; show role shell
        │
        │ user taps Unlock
        ▼
  BiometricService.evaluate(reason: copy[reason], fallback: .devicePasscode)
        │
   LAContext.evaluatePolicy(.deviceOwnerAuthentication) async
        │
   ┌────┴────┐
   ▼         ▼
 success    LAError
   │         │
   ▼         ▼
record domainState + lastSuccess     map → UI; show retry / re-bind
   │
   ▼
dismiss BiometricLockVC; reveal role shell

OTP AUTH PATH:
PhoneEntryVC ─▶ PhoneEntryVM.submit()
                     │
                     ▼
              LocationProvider.requestPermission() + currentLocation()
                     │
   ┌─────────────────┼──────────────────┬───────────────────┐
   ▼                 ▼                  ▼                   ▼
 .authorized      .denied        .notDetermined         (no fix in time)
   │                 │                  │                   │
   ▼                 ▼                  ▼                   ▼
   CLGeocoder    show "Open Settings" wait permission     refuse (D-21)
       │             │                  │                   │
       ▼             └─────re-run via Try Again────────┐    │
   isoCountryCode == "US"                              │    │
       │                                                │    │
   ┌───┴───┐                                            │    │
   ▼       ▼                                            │    │
  yes      no                                            │    │
   │       │                                            │    │
   │       ▼                                            │    │
   │  push NotAvailableInRegionVC (terminal)            │    │
   ▼                                                    │    │
APIClient.request(OTPRequestEndpoint(phone))            │    │
       │                                                │    │
       ▼                                                │    │
  push OTPVC; user enters 123456                        │    │
       │                                                │    │
       ▼                                                │    │
APIClient.request(OTPVerifyEndpoint(otpSessionID, code))│    │
       │                                                │    │
   ┌───┴────────────────┐                               │    │
   ▼                    ▼                               │    │
  200 → success       429 rateLimited(retryAfter)        │    │
   │                    │                               │    │
   │                    ▼                               │    │
   │             OTPVM starts 1-Hz Timer                 │    │
   │             countdown disable Verify; on 0 enable   │    │
   ▼
D-27 7-step orchestration (progress overlay):
  1. Persist sessionToken/role/userID to Keychain
  2. keyStore.generateDeviceIdentityKeys() — DEV-01/02 (idempotent guard from D-25)
  3. (already done step 2's two-key generate)
  4. APIClient.request(DeviceRegisterEndpoint(...))
  5. BiometricService.evaluate(reason: "Sign in to Validation Ledger", fallback: .none)
     ↳ records initial domainState + lastSuccess
  6. presentRoot(.role(role))

LOGOUT PATH (3 triggers all funnel here):
ProfileVC tap   → LogoutService.logout(.userInitiated)
401 interceptor → LogoutService.logout(.auth401)
DEV-06 signal   → LogoutService.logout(.anotherActiveSession)
                                  │
                                  ▼
                           1. clear in-memory session
                           2. keychain.deleteAll(under: .session)
                           3. keyStore.deleteKey(slot: .authorization)
                           4. clear stored evaluatedPolicyDomainState
                           5. sessionLock.invalidate()
                           6. NotificationCenter.post(.sessionDidInvalidate, [logoutReason: reason])
                                  │
                                  ▼
                           SceneDelegate observer maps reason → AppPhase:
                             .userInitiated/.auth401 → .auth
                             .anotherActiveSession   → .anotherActiveSession
                                  │
                                  ▼
                           presentRoot(target)
```

### Recommended Project Structure (Phase 3 end state — additions only)

```
validationLedger/
├── App/
│   ├── SceneDelegate.swift                                  # MODIFY: probe → presentRoot; .sessionDidInvalidate observer; AppPhase.anotherActiveSession routing
│   ├── AppCoordinator.swift                                 # MODIFY: case .auth → AuthCoordinator; case .anotherActiveSession → AnotherActiveSessionViewController
│   └── AppContainer.swift                                   # MODIFY: construct SessionRestoreService, BiometricService, SensitiveActionService, LogoutService, Auth401ResponseInterceptor
├── Core/
│   ├── Auth/
│   │   ├── SessionLockService.swift                         # MODIFY: extend with lockState(now:), self-subscribe to UIApplication notifications
│   │   ├── SessionRestoreService.swift                      # NEW
│   │   ├── BiometricService.swift                           # NEW
│   │   ├── SensitiveActionService.swift                     # NEW (M1: constructed but no call sites)
│   │   └── LogoutService.swift                              # NEW
│   ├── Identity/
│   │   ├── PlatformPayloadField.swift                       # NEW (GEO-03 phantom-typed enum)
│   │   ├── DeviceFingerprint.swift                          # already exists
│   │   └── Geo/
│   │       ├── LocationProvider.swift                       # NEW (CLLocationManager async wrapper)
│   │       └── CountryGate.swift                            # NEW (CLGeocoder reverse-geocode → "US"?)
│   ├── KeyStore/
│   │   ├── SecureEnclaveKeyStore.swift                      # MODIFY: CR-02 idempotent guard; deleteKey(slot:); IN-02 already returns DER
│   │   ├── SoftwareKeyStore.swift                           # MODIFY: IN-02 wrap rawRepresentation → DER; deleteKey(slot:) noop
│   │   └── KeyStoreProtocol.swift                           # MODIFY: add deleteKey(slot:)
│   ├── Networking/
│   │   ├── APIClient.swift                                  # MODIFY: parse 429 + Retry-After → NetworkError.rateLimited(retryAfter:)
│   │   ├── NetworkError.swift                               # MODIFY: add .rateLimited(retryAfter: TimeInterval)
│   │   ├── Endpoints/
│   │   │   ├── OTPVerifyEndpoint.swift                      # MODIFY: IN-01 — explicit CodingKeys for `otpSessionID` in RequestBody
│   │   │   ├── DeviceRegisterEndpoint.swift                 # MODIFY: IN-05 — explicit CodingKeys for `installUUID` in DeviceFingerprintPayload
│   │   │   ├── KYCUploadChunkEndpoint.swift                 # MODIFY: IN-05 — explicit CodingKeys for `uploadID`
│   │   │   └── KYCUploadCommitEndpoint.swift                # MODIFY: IN-05 — explicit CodingKeys for `uploadID`
│   │   └── Interceptors/
│   │       └── Auth401ResponseInterceptor.swift             # NEW
│   └── Storage/
│       └── Keychain/
│           ├── KeychainStore.swift                          # MODIFY: add deleteAll(under: KeychainScope) API
│           ├── KeychainKey.swift                            # MODIFY: add `.sessionRole`, `.sessionUserID`, `.biometricDomainState`
│           └── KeychainScope.swift                          # NEW (enum: .session)
├── Features/
│   ├── Onboarding/
│   │   └── Auth/
│   │       ├── AuthCoordinator.swift                        # NEW
│   │       ├── PhoneEntryViewController.swift               # NEW
│   │       ├── PhoneEntryViewModel.swift                    # NEW
│   │       ├── OTPViewController.swift                      # NEW
│   │       ├── OTPViewModel.swift                           # NEW
│   │       ├── BiometricLockViewController.swift            # NEW
│   │       ├── NotAvailableInRegionViewController.swift     # NEW
│   │       └── AnotherActiveSessionViewController.swift     # NEW
│   └── Profile/
│       └── ProfileViewController.swift                      # NEW (modal with logout button)
├── Roles/
│   ├── RoleCoordinator.swift                                # MODIFY: extension to install avatar UIBarButtonItem on each tab's nav (D-03 shared helper)
│   ├── Shipper/ShipperTabBarController.swift                # MODIFY: wrap tabs in UINavigationControllers; add avatar item
│   ├── Broker/BrokerTabBarController.swift                  # same
│   ├── Carrier/CarrierTabBarController.swift                # same
│   ├── Dispatch/DispatchTabBarController.swift              # same
│   └── Factoring/FactoringTabBarController.swift            # same
├── Resources/
│   └── Info.plist                                           # MODIFY: add NSLocationWhenInUseUsageDescription
└── .swiftlint.yml                                           # MODIFY: add 5th custom rule `ban_raw_coordinate_literal`

validationLedgerTests/
├── Networking/Fixtures/
│   └── otp-verify-rate-limited.json                         # NEW (D-02; 429 + Retry-After: 60)
├── Auth/
│   ├── SessionRestoreServiceTests.swift                     # NEW
│   ├── SessionLockServiceTests.swift                        # MODIFY: add lockState(now:) cases
│   ├── LogoutServiceTests.swift                             # NEW
│   ├── BiometricServiceTests.swift                          # NEW (sim-side; biometric semantics on device tests)
│   └── SensitiveActionServiceTests.swift                    # NEW (constructibility + signature shape only — D-12)
├── Networking/
│   └── Auth401ResponseInterceptorTests.swift                # NEW
├── Identity/
│   ├── PlatformPayloadFieldTests.swift                      # NEW (compile-shape assertion)
│   └── Geo/
│       ├── LocationProviderTests.swift                      # NEW (mock CLLocationManager via injectable protocol)
│       └── CountryGateTests.swift                           # NEW (injected geocoder protocol)
└── Features/Onboarding/Auth/
    ├── PhoneEntryViewModelTests.swift                       # NEW
    └── OTPViewModelTests.swift                              # NEW

validationLedgerUITests/
└── RoleShellSmokeTests.swift                                # MODIFY: 5 tests now drive OTP fixture; assert tabs + logout (D-32)

validationLedgerDeviceTests/
├── BiometricSESmokeTests.swift                              # NEW (HUMAN-UAT for SC-2/SC-3 cold-boot + bg5min biometric)
└── EvaluatedPolicyDomainStateTests.swift                    # NEW (HUMAN-UAT for SESS-03 re-enrollment)
```

### Pattern 1: AuthCoordinator owning the auth UINavigationController

**What:** A coordinator that owns `UINavigationController(rootViewController: PhoneEntryViewController(...))`, exposes its `rootViewController` to `AppCoordinator`, and bubbles `onAuthenticated(role:)` up via a closure.
**When to use:** D-01 — every Phase 3 auth flow goes through this.

```swift
// Features/Onboarding/Auth/AuthCoordinator.swift
import UIKit

@MainActor
public final class AuthCoordinator {
    public let rootViewController: UIViewController
    public var onAuthenticated: ((Role) -> Void)?

    private let nav: UINavigationController
    private let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
        let phoneVM = PhoneEntryViewModel(
            apiClient: container.apiClient,
            location: container.locationProvider,
            countryGate: container.countryGate,
            logger: container.logger
        )
        let phoneVC = PhoneEntryViewController(viewModel: phoneVM)
        self.nav = UINavigationController(rootViewController: phoneVC)
        self.rootViewController = nav
        phoneVM.onPhoneSubmitted = { [weak self] otpSessionID in
            self?.pushOTP(otpSessionID: otpSessionID)
        }
    }

    private func pushOTP(otpSessionID: String) {
        let vm = OTPViewModel(
            otpSessionID: otpSessionID,
            apiClient: container.apiClient,
            keychain: container.keychainStore,
            keyStore: container.keyStore,
            biometric: container.biometricService,
            logger: container.logger
        )
        let vc = OTPViewController(viewModel: vm)
        vm.onAuthenticated = { [weak self] role in
            self?.onAuthenticated?(role)
        }
        nav.pushViewController(vc, animated: true)
    }
}
```

### Pattern 2: One-shot `CLLocationManager` async wrapper using `withCheckedThrowingContinuation`

**What:** Bridge the delegate-callback `CLLocationManager` to `async`/`await` for a single fresh-fix request.
**When to use:** Phone-entry geo pre-check (GEO-01..02). Not a stream — one-shot.

```swift
// Core/Identity/Geo/LocationProvider.swift
import CoreLocation
import Foundation

public protocol LocationProvider: AnyObject, Sendable {
    func requestPermission() async -> CLAuthorizationStatus
    /// Returns a fresh fix (<30s old, <100m horizontal accuracy) or throws.
    func currentLocation(maxAge: TimeInterval, maxAccuracy: CLLocationDistance) async throws -> CLLocation
}

public enum LocationError: Error, Sendable {
    case permissionDenied
    case staleFix
    case lowAccuracy
    case timedOut
    case underlying(Error)
}

@MainActor
public final class CLLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func requestPermission() async -> CLAuthorizationStatus {
        if manager.authorizationStatus != .notDetermined {
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { cont in
            self.permissionContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation(
        maxAge: TimeInterval = 30,
        maxAccuracy: CLLocationDistance = 100
    ) async throws -> CLLocation {
        guard manager.authorizationStatus == .authorizedWhenInUse
              || manager.authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            manager.requestLocation()  // one-shot
        }
        // Caller wraps with Task.timeout for the 6s ceiling.
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.permissionContinuation?.resume(returning: manager.authorizationStatus)
            self.permissionContinuation = nil
        }
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard let loc = locations.last else { return }
            // Freshness + accuracy guard
            if loc.timestamp.timeIntervalSinceNow < -30 {
                self.locationContinuation?.resume(throwing: LocationError.staleFix)
            } else if loc.horizontalAccuracy > 100 || loc.horizontalAccuracy < 0 {
                self.locationContinuation?.resume(throwing: LocationError.lowAccuracy)
            } else {
                self.locationContinuation?.resume(returning: loc)
            }
            self.locationContinuation = nil
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: LocationError.underlying(error))
            self.locationContinuation = nil
        }
    }
}
```

[VERIFIED: [createwithswift Core Location async](https://www.createwithswift.com/updating-the-users-location-with-core-location-and-swift-concurrency-in-swiftui/) + [Hacking with Swift store continuations](https://www.hackingwithswift.com/quick-start/concurrency/how-to-store-continuations-to-be-resumed-later)]

### Pattern 3: `LAContext` async/await with `evaluatedPolicyDomainState` capture

**What:** Use the iOS-15+ closure callback bridged into `withCheckedThrowingContinuation`, then read `domainState` immediately after success.

```swift
// Core/Auth/BiometricService.swift
import LocalAuthentication
import Foundation

public enum BiometricFallback: Sendable {
    case none           // Strict biometric (sensitive actions)
    case devicePasscode // Biometric with passcode fallback (session unlock)
}

public protocol BiometricService: AnyObject, Sendable {
    /// Evaluates the requested policy. On success, updates the stored domain state in Keychain.
    func evaluate(reason: String, fallback: BiometricFallback) async throws

    /// Reads the current LAContext.evaluatedPolicyDomainState (nil before any evaluatePolicy call).
    /// Used by SessionLockService.lockState to detect SESS-03 re-enrollment.
    func currentDomainState() -> Data?
}

@MainActor
public final class DefaultBiometricService: BiometricService {
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(keychain: KeychainStore, logger: any Logger) {
        self.keychain = keychain
        self.logger = logger
    }

    public func evaluate(reason: String, fallback: BiometricFallback) async throws {
        let ctx = LAContext()
        let policy: LAPolicy = (fallback == .devicePasscode)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        // Verify policy is evaluable before trying — avoids LAError.passcodeNotSet bubbling
        // up unexpectedly in tests.
        var canError: NSError?
        guard ctx.canEvaluatePolicy(policy, error: &canError) else {
            throw canError ?? NSError(domain: LAErrorDomain, code: LAError.invalidContext.rawValue)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? NSError(domain: LAErrorDomain, code: LAError.authenticationFailed.rawValue))
                }
            }
        }

        // After successful evaluation, persist the domain state (D-09).
        if let domainState = ctx.evaluatedPolicyDomainState {
            try? keychain.set(
                domainState,
                for: .biometricDomainState,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
    }

    public func currentDomainState() -> Data? {
        // Read fresh per call — a new LAContext sees current enrollment.
        let ctx = LAContext()
        var err: NSError?
        // Must call canEvaluatePolicy first — domainState is nil otherwise.
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return ctx.evaluatedPolicyDomainState
    }
}
```

[VERIFIED: [Apple evaluatedPolicyDomainState docs](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatedpolicydomainstate) — "This property is set only when evaluatePolicy is called and successful Touch ID or Face ID authentication was performed, OR when canEvaluatePolicy succeeds for a biometric policy." + [Carver Code: How to Detect a Change in Biometrics on iOS](https://carvercode.com/articles/how-to-detect-a-change-in-biometrics-on-ios/) — confirms canEvaluatePolicy populates the property]

### Anti-Patterns to Avoid

- **Storing `LAContext` as a service property and reusing it across calls.** Every biometric prompt should construct a fresh `LAContext` — re-using one leads to confusing cached-prompt behavior and is implicated in the WWDC22 talk on local-authorization streamlining. [VERIFIED: [WWDC22 Streamline local authorization flows](https://developer.apple.com/videos/play/wwdc2022/10108/)]
- **Reading `evaluatedPolicyDomainState` BEFORE calling `evaluatePolicy` or `canEvaluatePolicy`.** It returns nil. Phase 3 must `canEvaluatePolicy` first to populate the state for the comparison-only read. [VERIFIED: Apple docs above]
- **Counting OTP attempts locally to drive AUTH-02 countdown.** A process restart resets the count; backend-authoritative `Retry-After` is the only correct source. [LOCKED: D-02]
- **Passing raw `CLLocationCoordinate2D` to `LogField`/`AnalyticsField`.** Compile-time enforced by D-23 (no `.coordinate` case in `LogField`); lint-enforced by D-24 (no raw literal outside allow-listed paths).
- **Allowing the cold-boot probe to be async.** Synchronous Keychain reads are sub-millisecond; an async probe means the app paints `.shipper` then swaps, breaking SC-2.
- **Skipping the `.biometricDomainState` clear in `LogoutService.logout`.** Without step 4, a logout-then-relogin user is incorrectly told "biometric changed" the first time they cold-boot post-relogin (because the stored blob now mismatches whatever the next session records). [Confirmed: D-16 step 4 is explicit about this.]
- **Putting Profile as a 5th tab.** TechStack §4 inventory is locked verbatim per D-03.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Biometric prompt + result handling | Custom UIAlertController + Keychain "biometric_token" pattern | `LAContext.evaluatePolicy` async wrapper + `LAError` mapping | Apple owns the OS-level prompt UI; rolling your own breaks "biometric on device == OS biometric" trust contract. |
| Biometric re-enrollment detection | Custom enrolled-fingerprint count tracking via SecItem queries | `LAContext.evaluatedPolicyDomainState` `Data` blob diff | Apple provides this exact opaque blob for this exact purpose. Documented since iOS 9. |
| One-shot location fetch | Custom timeout + retry loop on `startUpdatingLocation` | `requestLocation` (one-shot delegate call) wrapped in `withCheckedThrowingContinuation` | `requestLocation` is the OS-supported one-shot; no need to manage start/stop lifecycle. |
| Reverse-geocode → country | Hand-coded lat/lon → country bounding-box check | `CLGeocoder.reverseGeocodeLocation` → `placemark.isoCountryCode` | Bounding boxes are wrong at borders; Apple's geocoder uses authoritative data. |
| 429 Retry-After parsing | Per-call response inspection at every endpoint | Single `APIClient` decode site that maps 429 → `NetworkError.rateLimited(retryAfter:)` | Headers are HTTP-protocol concerns — they belong in the transport layer, not endpoint code. |
| Phone-number formatting (US-only) | Adding libphonenumber dep | Hand-rolled 30-LOC formatter (US-only per D-26) | Dep cost > one-formatter cost. Different from international formatting (which would justify the dep). |
| Coordinate-can't-be-logged invariant | Code-review discipline alone | Phantom-typed enum (`PlatformPayloadField` vs `LogField`) + SwiftLint regex rule | Runtime guards rely on the engineer remembering; type system + lint enforce it. |
| LogoutService teardown | Per-trigger duplicate cleanup blocks | Single `LogoutService.logout(reason:)` funnel | Three triggers MUST produce identical end states; symmetric teardown is a security guarantee. |

**Key insight:** Phase 3 is mostly *integration* of Apple-provided primitives behind a small set of `Core/Auth/` services. Almost none of it is novel logic — the engineering value is in the boundaries (single LogoutService, single APIClient 429 site, single SessionRestoreService probe site).

## iOS-API Deep Dives (the 18 focus areas)

### 1. `LAContext.evaluatedPolicyDomainState` diff pattern (D-09, SESS-03)

**API:** `LAContext.evaluatedPolicyDomainState: Data?` — opaque `Data` blob representing currently-enrolled biometric template set.

**When non-nil:** Set ONLY after either `evaluatePolicy(_:localizedReason:reply:)` succeeds OR `canEvaluatePolicy(_:error:)` succeeds for a biometric policy. A freshly-allocated `LAContext` returns `nil` until you call one of those. [VERIFIED: [Apple evaluatedPolicyDomainState docs](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatedpolicydomainstate)]

**What changes the blob:** Adding/removing a Face ID enrollment, adding/removing a Touch ID fingerprint, switching between biometric kinds, or system passcode change in some scenarios. Apple does NOT document the exact bytes — treat it as an opaque equality check.

**Persistence:** Phase 3 stores the `Data` blob in Keychain (NOT UserDefaults — security-sensitive). Use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (consistent with sessionToken).

**Lifecycle integration (D-09 + D-16):**
- After every successful biometric evaluate (BiometricService.evaluate), capture `ctx.evaluatedPolicyDomainState` and write to Keychain key `biometric.domainState`.
- On `SessionLockService.lockState(now:)`, read the stored blob, instantiate a fresh `LAContext`, call `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error:)` to populate the property, read the current blob, byte-compare.
- On match → continue with the existing background-grace logic. On mismatch → return `.locked(.biometricReEnrolled)`.
- On `LogoutService.logout`, delete the stored blob (D-16 step 4).

**Older `policyDomainState` API:** This name was used in some older Stack Overflow answers; the canonical iOS-17 property is `evaluatedPolicyDomainState`. There is NO `policyDomainState` in the current public API. [VERIFIED: [Apple LAContext docs](https://developer.apple.com/documentation/localauthentication/lacontext)]

**Confidence:** HIGH

### 2. `LAContext` policies and `LAError` codes (D-15)

**Policies (D-15-relevant):**
- `.deviceOwnerAuthenticationWithBiometrics` — biometric only; falls back to nothing if biometric fails. Used for sensitive-action authorization (D-11).
- `.deviceOwnerAuthentication` — biometric with system-managed passcode fallback. After 5 biometric failures, iOS auto-prompts passcode. Used for session unlock (D-15).
- `.deviceOwnerAuthenticationWithCompanion` (iOS 18+) — Watch fallback; out of scope for iOS 17 floor.

**Async/await usage on iOS 17+:** Apple does NOT ship a built-in `evaluatePolicy` async overload — bridge via `withCheckedThrowingContinuation` (Pattern 3 above). The closure callback can fire on an arbitrary queue per Apple docs; the continuation's `resume` is thread-safe. The continuation's resume thread is the LAContext callback thread, which is why D-31 mandates the calling service is `MainActor` so the *next* statement executes on main.

**`LAError` cases to handle:**
| Case | Meaning | UX |
|------|---------|-----|
| `.userCancel` | User tapped Cancel on the OS prompt | Silent — leave on Lock VC; user retries via Unlock button |
| `.userFallback` | User tapped "Use Passcode" (only meaningful with `.deviceOwnerAuthentication`) | OS handles fallback; we land back in success on next callback |
| `.systemCancel` | iOS dismissed (e.g., another app foregrounded) | Silent — re-prompt on next active |
| `.appCancel` | App canceled (we did not) | Should not happen — log warn |
| `.passcodeNotSet` | Device has no passcode set at all | Show "Enable a device passcode in Settings" copy |
| `.biometryNotAvailable` | No biometric hardware | Show "Use device passcode" — only `.deviceOwnerAuthentication` works |
| `.biometryNotEnrolled` | Hardware present, no enrolled prints/face | Show "Enroll Face ID/Touch ID in Settings" |
| `.biometryLockout` | Too many failed attempts at biometric; passcode required | OS handles via `.deviceOwnerAuthentication` fallback |
| `.invalidContext` | Reused/invalid LAContext | Log error — should not happen with fresh-context discipline |
| `.notInteractive` | LAContext set `.interactionNotAllowed` | Should not happen — we don't set this flag |
| `.authenticationFailed` | Generic failure (couldn't match) | Show "Try again" |

**MainActor interaction:** see Pattern 3 above. `BiometricService` is `@MainActor`-bound (D-31).

**Recommended retry/cancel UX:** On `.userCancel` or any failure, leave the user on `BiometricLockViewController` with a "Try again" button. Don't auto-retry — it confuses the user when the OS prompt vanishes.

[VERIFIED: [Apple LAError docs](https://developer.apple.com/documentation/localauthentication/laerror) + [Hacking with Swift Touch ID/Face ID](https://www.hackingwithswift.com/read/28/4/touch-to-activate-touch-id-face-id-and-localauthentication)]

**Confidence:** HIGH

### 3. `CLLocationManager` + `CLGeocoder` reverse-geocode flow (D-20, D-21, GEO-01..02)

**Permission API:**
- `requestWhenInUseAuthorization()` — appropriate for D-20 (foreground-only auth pre-check). NOT `.always` — that triggers the OS warning "this app wants background location" which we don't need until M3 BG-01.
- Authorization is async via `locationManagerDidChangeAuthorization(_:)` delegate; bridge with continuation as in Pattern 2.

**Info.plist key:** `NSLocationWhenInUseUsageDescription` is REQUIRED — the app crashes at the permission prompt without it. Suggested copy: "Validation Ledger uses your location at sign-in to verify you're in the United States, our service area." [VERIFIED: [Apple Requesting Authorization for Location Services](https://developer.apple.com/documentation/corelocation/requesting-authorization-for-location-services)]

**One-shot vs continuous:** Use `manager.requestLocation()` for the one-shot — it triggers a single delegate callback with the freshest fix. Pair with `manager.desiredAccuracy = kCLLocationAccuracyHundredMeters` (good enough for country-check; faster than `kCLLocationAccuracyBest`).

**Freshness + accuracy enforcement (D-20):**
- `loc.timestamp.timeIntervalSinceNow > -30` (i.e., not older than 30 seconds)
- `loc.horizontalAccuracy <= 100` AND `loc.horizontalAccuracy >= 0` (negative = invalid fix)

**`CLGeocoder.reverseGeocodeLocation`:**
- Async API: `reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark]` (iOS 13+).
- Returns array of placemarks, usually one. Use `.first?.isoCountryCode`.
- `isoCountryCode`: ISO 3166-1 alpha-2; "US" for the United States. Can be `nil` if the geocoder couldn't determine a country (extremely rare on land; happens in international waters, certain disputed regions).
- Apple-imposed rate limit: undocumented but ~1 request/second per app; for a one-shot at sign-in this is never an issue.
- Network requirement: CLGeocoder uses the network for forward/reverse geocoding. Offline behavior: throws `CLError.network`. Per D-21, treat as "cannot verify country = refuse" (defense-in-depth posture).

**Settings deep-link (D-21):**
```swift
guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
UIApplication.shared.open(url)
```
This opens the app's specific settings page in iOS Settings. Documented since iOS 8. [VERIFIED: [Apple openSettingsURLString docs](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)]

**Researcher recommendation for the timeout:** wrap `CLGeocoder.reverseGeocodeLocation` in a 6-second `Task.timeout`; on timeout, refuse with "Cannot verify your location. Try again."

[VERIFIED: [Apple CLGeocoder docs](https://developer.apple.com/documentation/corelocation/clgeocoder) + [Apple CLPlacemark.isoCountryCode docs](https://developer.apple.com/documentation/corelocation/clplacemark/isocountrycode)]

**Confidence:** HIGH

### 4. URLSession 429 Retry-After parsing (D-02, AUTH-02)

**Header formats per RFC 7231:**
- Delta-seconds: `Retry-After: 60` (non-negative integer, seconds to wait)
- HTTP-date: `Retry-After: Wed, 21 Oct 2026 07:28:00 GMT`

**Parsing approach (recommended for Phase 3):**

```swift
// Core/Networking/APIClient.swift (modify the response handling block)
extension APIClient {
    static func parseRetryAfter(from response: HTTPURLResponse, now: Date = .now) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw) {
            return max(0, seconds)
        }
        // HTTP-date fallback
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }
}
```

**APIClient integration (modify `request<E>` after the status-code check):**

```swift
guard (200...299).contains(response.statusCode) else {
    if response.statusCode == 429 {
        let retryAfter = Self.parseRetryAfter(from: response) ?? 60
        throw NetworkError.rateLimited(retryAfter: retryAfter)
    }
    throw NetworkError.httpError(statusCode: response.statusCode, data: data)
}
```

**Why parse at the APIClient boundary:** Per the Architectural Responsibility Map, transport-protocol concerns (header parsing, status-code mapping) belong in the transport layer. The OTPViewModel consumes a typed `NetworkError.rateLimited(retryAfter:)` — it never sees the raw header.

**Existing pipeline support:** APIClient already has the response-pipeline boundary (the `wrapped` function composition in `request<E>`). Adding the 429 case is a 3-line modification, not a new interceptor. The Auth401ResponseInterceptor (D-28) is a separate `ResponseInterceptor` because it must trigger a side effect (logout) — but rate-limiting is a typed error, so it lives at the decode boundary.

**MockURLProtocol fixture (D-02):**
```json
// validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json
{
  "error": "rate_limited",
  "message": "Too many attempts. Try again in 60 seconds."
}
```

```swift
// Test side — returns 429 + Retry-After: 60
MockURLProtocol.register { req in
    guard req.url?.path == "/auth/otp/verify" else { return nil }
    let body = FixtureLoader.data(named: "otp-verify-rate-limited")
    let resp = HTTPURLResponse(
        url: req.url!,
        statusCode: 429,
        httpVersion: "HTTP/1.1",
        headerFields: ["Retry-After": "60", "Content-Type": "application/json"]
    )!
    return (resp, body)
}
```

[VERIFIED: [MDN Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After) + [HTTP.dev Retry-After expert guide](https://http.dev/retry-after)]

**Confidence:** HIGH

### 5. Secure Enclave key signing with `.biometryCurrentSet` ACL (D-11, D-15)

**Phase 2 already established:**
- `SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], &acError)` — exact flags for the `authorizationKey` ACL.
- `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave` generates the key in-enclave.
- `SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, &error)` — signing call returns DER X9.62.

**Behavior on signing with `.biometryCurrentSet` ACL:** When the SecKey was created with this flag, calling `SecKeyCreateSignature` AUTOMATICALLY presents the OS biometric prompt before performing the operation. iOS internally creates an LAContext, runs the prompt, then continues the signing call. **No app-side LAContext call is required for the prompt to appear.**

**Key insight from WWDC22 ([Streamline local authorization flows](https://developer.apple.com/videos/play/wwdc2022/10108/)):** You can avoid a double-prompt in the SensitiveActionService by binding your own LAContext to the SecKey query via `kSecUseAuthenticationContext`:

```swift
let ctx = LAContext()
try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                             localizedReason: "Sign tender request") // PROMPT 1

// Now bind ctx to the SecKey query so signing does NOT re-prompt
let query: [CFString: Any] = [
    kSecClass: kSecClassKey,
    kSecAttrApplicationTag: Keyslot.authorization.applicationTag,
    kSecReturnRef: true,
    kSecUseAuthenticationContext: ctx,    // ← KEY LINE
]
var item: CFTypeRef?
SecItemCopyMatching(query as CFDictionary, &item)
let key = item as! SecKey
let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, nil)
// No SECOND prompt — ctx already authorized, SE accepts the bound context
```

**`.biometryCurrentSet` invalidation on biometric re-enrollment:**
- The ACL is hardware-enforced. Re-enrollment makes the key permanently undecryptable.
- `SecKeyCreateSignature` will throw `errSecAuthFailed` (-25293) or similar on the next sign attempt after re-enrollment.
- This intersects with D-09: `evaluatedPolicyDomainState` diff catches re-enrollment BEFORE the user attempts a sensitive action; the SecKey error is the backstop.

**Error mapping for `SensitiveActionError`:**
| LAError / OSStatus | SensitiveActionError |
|--------------------|----------------------|
| `LAError.userCancel` | `.userCancel` |
| `LAError.biometryLockout` | `.biometryLockout` |
| `errSecAuthFailed` after sign | `.biometricReEnrolled` (assume; backstops D-09 detection) |
| Other | `.signFailed(underlying:)` |

**Performance:** SE signing on-device is ~50-200ms per sign (well within UX budgets). On simulator, `SoftwareKeyStore` is sub-millisecond.

[VERIFIED: [Apple SecKeyCreateSignature docs](https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)) + [Gridnev — Biometry-protected entries in iOS keychain](https://medium.com/@alx.gridnev/biometry-protected-entries-in-ios-keychain-6125e130e0d5) + [WWDC22 Streamline local authorization flows](https://developer.apple.com/videos/play/wwdc2022/10108/)]

**Confidence:** HIGH

### 6. UIKit modal-overlay pattern for `BiometricLockViewController` (D-13)

**Recommended presentation style:** `.fullScreen` modal from the SceneDelegate's `window.rootViewController`.

**Why not a window overlay:** A separate `UIWindow` at a higher window level would also work, but introduces multi-window complexity (especially under iOS 13+ multiscene). The `.fullScreen` modal:
- Preserves the underlying VC state — when dismissed, the role tab bar and its child VC stack are intact.
- Captures all input — the user cannot tap behind it.
- Is what every banking/password-vault app on iOS does (proven pattern).

**Presentation code:**
```swift
// SceneDelegate or AppCoordinator (whoever owns the root)
func presentBiometricLock(reason: LockReason) {
    let lockVC = BiometricLockViewController(reason: reason, biometric: container.biometricService) {
        // dismiss on success
        self.window?.rootViewController?.dismiss(animated: false)
    }
    lockVC.modalPresentationStyle = .fullScreen
    window?.rootViewController?.present(lockVC, animated: false)
}
```

**Z-order guarantee:** A `.fullScreen` modal is presented above the view hierarchy of the presenter. As long as it's presented before any other modal, it stays on top.

**Multiscene (iOS 13+) consideration:** Each `UIScene` has its own `window`; the BiometricLockVC must be presented per-scene. Since CLAUDE.md's M1 plan is single-scene (typical), this is moot — but the SceneDelegate pattern handles it correctly automatically.

**VoiceOver focus capture:** Setting `lockVC.view.accessibilityViewIsModal = true` captures VoiceOver focus inside the lock VC, so the user can't VoiceOver-swipe to elements behind. Critical for accessibility compliance.

**Dismissal lifecycle:** Dismiss with `animated: false` to avoid revealing content during the dismiss animation (security posture).

**Comparison to common open-source patterns:** Lockbox-style apps and 1Password-style apps use this exact `.fullScreen` modal approach. No serious app uses a custom UIWindow approach — too many edge cases (status bar, in-call banner, screen recording overlay).

[VERIFIED: [Apple modalPresentationStyle docs](https://developer.apple.com/documentation/uikit/uimodalpresentationstyle/fullscreen) + [Apple accessibilityViewIsModal docs](https://developer.apple.com/documentation/objectivec/nsobject/accessibilityviewismodal)]

**Confidence:** HIGH

### 7. `UIApplication.didEnterBackgroundNotification` + `didBecomeActiveNotification` self-subscription (D-08)

**Recommended pattern:** Service-layer subscriber holding NSNotificationCenter observer tokens, removed in `deinit`.

```swift
// Core/Auth/SessionLockService.swift (extension for D-08)
import UIKit
import Foundation

@MainActor
public final class DefaultSessionLockService: SessionLockService {
    private var lastSuccess: Date?
    private var enteredBackgroundAt: Date?
    private let backgroundGrace: TimeInterval = 5 * 60
    private let biometric: any BiometricService
    private let keychain: KeychainStore
    private let notificationCenter: NotificationCenter
    private var bgToken: NSObjectProtocol?
    private var fgToken: NSObjectProtocol?

    public init(
        biometric: any BiometricService,
        keychain: KeychainStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.biometric = biometric
        self.keychain = keychain
        self.notificationCenter = notificationCenter
        bgToken = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enteredBackgroundAt = Date()
        }
        fgToken = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // SceneDelegate observes the same notification and queries lockState — no work here.
        }
    }

    deinit {
        if let bgToken { notificationCenter.removeObserver(bgToken) }
        if let fgToken { notificationCenter.removeObserver(fgToken) }
    }

    public func lockState(now: Date) -> LockState {
        // 1) Re-enrollment check (highest priority)
        if let stored = try? keychain.get(.biometricDomainState),
           let current = biometric.currentDomainState(),
           stored != current {
            return .locked(reason: .biometricReEnrolled)
        }
        // 2) Cold-boot — never authenticated this process
        guard let last = lastSuccess else {
            return .locked(reason: .coldBoot)
        }
        // 3) Background timeout
        if let bgAt = enteredBackgroundAt, now.timeIntervalSince(bgAt) > backgroundGrace {
            return .locked(reason: .backgroundTimeout)
        }
        return .unlocked
    }

    public func recordBiometricSuccess(at date: Date) {
        lastSuccess = date
        enteredBackgroundAt = nil
    }

    public func invalidate() {
        lastSuccess = nil
        enteredBackgroundAt = nil
        try? keychain.delete(.biometricDomainState)
    }
}
```

**Weak-self trap:** Use `[weak self]` in the closure. Without it, the service captures itself strongly, the observer holds it indefinitely, and `deinit` never fires. With the existing tokens removed in `deinit`, the closure capture is the only retain cycle risk.

**MainActor isolation:** Notifications posted by UIKit are posted on the main thread; setting the queue to `.main` ensures the closure also runs on main, so the `MainActor`-bound state mutation is safe. Swift 6 will require explicit `Task { @MainActor in ... }` wrapping if the service moves to non-main isolation later.

**Existing API survives:** The `shouldRequireBiometric(now:) -> Bool` method can be deleted (D-07 says "may stay or be deleted — planner chooses"). With only one Phase 1 caller (`SessionLockServiceTests`), deletion is clean.

**SessionLockService gains a UIKit import:** D-08 acknowledges this. Acceptable trade per the decision.

[VERIFIED: [Apple UIApplication notification names](https://developer.apple.com/documentation/uikit/uiapplication) + [Apple addObserver docs](https://developer.apple.com/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:))]

**Confidence:** HIGH

### 8. `UINavigationItem.rightBarButtonItem` avatar affordance for 5 UITabBarControllers (D-03)

**Approach:** Each tab in each role's TabBar is wrapped in a `UINavigationController`. The shared helper installs a `UIBarButtonItem` with a custom view (circular initial) on each child VC's `navigationItem.rightBarButtonItem`. Tap presents the modal `ProfileViewController`.

**Why per-tab (vs once at the tab-controller level):** A `UITabBarController` has no navigation bar of its own — only its child VCs do. Each child must be a `UINavigationController` (or have one as its root) for the bar to appear. The shared helper iterates the 4 tabs and installs the same item on each.

**Phase 1 current state:** `ShipperTabBarController.makeTab(...)` returns a bare `UIViewController`. Phase 3 must wrap each in a `UINavigationController`:

```swift
// Roles/RoleCoordinator.swift (extension — shared helper)
public extension RoleCoordinator where Self: UITabBarController {
    func installAvatarAffordance(presenter: @escaping (UIViewController) -> Void) {
        guard let viewControllers else { return }
        for vc in viewControllers {
            let nav = (vc as? UINavigationController) ?? UINavigationController(rootViewController: vc)
            let avatar = AvatarBarButtonItemFactory.make { [weak self] in
                guard let self else { return }
                let profile = ProfileViewController()
                profile.modalPresentationStyle = .formSheet  // sheet on iPhone, popover-friendly on iPad
                self.present(UINavigationController(rootViewController: profile), animated: true)
            }
            nav.viewControllers.first?.navigationItem.rightBarButtonItem = avatar
        }
    }
}
```

**iPhone vs iPad rendering:**
- iPhone: `.formSheet` falls back to `.fullScreen` automatically on compact width — natural sheet behavior.
- iPad: `.formSheet` renders as a centered modal, which respects CLAUDE.md's "iPad must render natively, not just scale". For a popover from the avatar (preferred iPad UX), use `.popover` and set `popoverPresentationController?.barButtonItem = sender`.

**Researcher recommendation:** Use `.formSheet` for M1. If iPad QA flags it, upgrade to a popover variant in a future plan.

**Avatar visual:** A `UIView` with a UILabel showing the user's initial (read from `Keychain[.sessionUserID]` or a separate cached display name — out of M1 scope to fetch from backend; show "?" or first char of role for M1).

[VERIFIED: [Apple UINavigationItem.rightBarButtonItem docs](https://developer.apple.com/documentation/uikit/uinavigationitem/rightbarbuttonitem) + [Apple UIModalPresentationStyle.formSheet](https://developer.apple.com/documentation/uikit/uimodalpresentationstyle/formsheet)]

**Confidence:** HIGH

### 9. Phantom-typed enum compile-time enforcement (D-23, GEO-03)

**Existing state:** `Core/Logging/Logger.swift` already defines `LogField` with a `.coordinates` case — but this is a redaction sentinel (the case name without an associated value). The `log(_:event:fields: [LogField: Any])` API takes `LogField` keys with `Any` values, so technically a coordinate could be passed as a value.

**Phase 3 hardening for D-23:**
1. **Delete the `.coordinates` case from `LogField`.** Without it, no key in `[LogField: Any]` can be associated with a coordinate, and the redaction step can't accidentally let one through (because there's no entry to redact). The hand-rolled scrubber for string fields catches stray coordinate-shaped strings via regex (Phase 1 PIIScrubber already does this).
2. **Add `Core/Identity/PlatformPayloadField.swift`:**

```swift
// Core/Identity/PlatformPayloadField.swift
import CoreLocation
import Foundation

/// Disjoint type from LogField/AnalyticsField. Coordinates can ONLY be passed via this enum,
/// which is consumed ONLY by Core/Networking/Endpoints/ payload builders. Logger/Analytics
/// signatures cannot accept this type — passing one yields a compile error like:
///   "Cannot convert value of type 'PlatformPayloadField' to expected element type 'LogField'"
public enum PlatformPayloadField: Sendable {
    case coordinate(CLLocationCoordinate2D)
    case timestamp(Date)
    case userIdentifier(String)
    case sessionToken(String)
    // Extend as endpoint payloads grow. NEVER add this to Logger/Analytics call sites.
}
```

3. **Endpoint payload builders** (the only consumers) reference this type when assembling a request body that includes coordinates — e.g., a future tender-endpoint builder accepts `[PlatformPayloadField]`.

**Why two disjoint types:** Subtyping or extension of `LogField` would let a future engineer add `case coordinate(...)` and break the invariant. Two parallel types with no shared protocol means there is no syntactic path from "I have a `CLLocationCoordinate2D`" to "the Logger accepts it." The compiler is the enforcer.

**Verify by codebase grep before/after:**
```bash
# BEFORE Phase 3 — confirms LogField has .coordinates case
grep -n "case coordinates" validationLedger/Core/Logging/Logger.swift
# AFTER Phase 3 Plan — should return zero results
```

**Confidence:** HIGH

### 10. SwiftLint custom regex rule for `ban_raw_coordinate_literal` (D-24)

**SwiftLint custom rule schema:** Rules under `custom_rules:` in `.swiftlint.yml` accept `name`, `regex`, `match_kinds` (optional — restricts to syntax categories like `comment`, `identifier`), `severity`, `included` (regex-on-path; only files matching get linted), `excluded` (regex-on-path; files matching are skipped from this rule).

**Recommended rule (alongside existing 4):**

```yaml
custom_rules:
  # ... 4 existing rules unchanged ...

  # Rule 5 — GEO-03: ban raw CLLocationCoordinate2D literals outside the geo / endpoint allow-list.
  # Forces engineers to construct coordinates only inside the few files that legitimately
  # build them; the phantom-typed PlatformPayloadField then routes them only to /endpoints/.
  ban_raw_coordinate_literal:
    name: "Do not construct raw CLLocationCoordinate2D outside geo / endpoint paths"
    regex: 'CLLocationCoordinate2D\s*\(\s*latitude\s*:'
    message: "Raw coordinate construction is restricted to Core/Identity/Geo*/, Core/Networking/Endpoints/, and tests. Wrap coordinates in PlatformPayloadField for transport."
    excluded: '.*/(Core/Identity/Geo[^/]*|Core/Networking/Endpoints|.*Tests)/.*'
    severity: error
```

**Notes vs the existing four:**
- Same severity (`error`) and same regex/message style as `ban_print` and `ban_direct_os_log`.
- `excluded:` is a regex on the path — not a list — so we use a single pattern that allow-lists all three groups (`Geo*` subfolders, `Endpoints/`, `*Tests/`).
- Note that the `included:` directive at the top of `.swiftlint.yml` already restricts SwiftLint to `validationLedger/`; the test directories are already excluded at the top level. We still include `*Tests/` in the rule's allow-list defensively in case the top-level scope changes.

**Plant-violation validation (pattern Phase 1 used for the other rules):** Add a temporary line like `let bad = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)` in `validationLedger/App/AppDelegate.swift`, run SwiftLint, confirm the rule fires, then remove the planted violation.

[VERIFIED: [SwiftLint custom rules docs](https://github.com/realm/SwiftLint#defining-custom-rules) + Phase 1 `.swiftlint.yml` precedent]

**Confidence:** HIGH

### 11. DER X9.62 vs 64-byte compact ECDSA signature normalization (D-25, IN-02)

**What each store currently returns:**
- `SecureEnclaveKeyStore` (device): `SecKeyCreateSignature(_, .ecdsaSignatureMessageX962SHA256, _, _)` returns DER-encoded ASN.1 SEQUENCE of `r` and `s` integers (X9.62). Length variable (~70-72 bytes). [VERIFIED: Phase 2 RESEARCH.md + [Apple SecKeyAlgorithm docs](https://developer.apple.com/documentation/security/seckeyalgorithm)]
- `SoftwareKeyStore` (sim): CryptoKit's `P256.Signing.PrivateKey.signature(for:).rawRepresentation` returns the 64-byte compact format (32-byte `r` || 32-byte `s`). [VERIFIED: [Apple P256.Signing.ECDSASignature docs](https://developer.apple.com/documentation/cryptokit/p256/signing/ecdsasignature)]

**The mismatch:** Backend currently sees one of two wire formats depending on whether the request originated from a sim build or device build. Backend has to handle both — bad. Pick ONE.

**D-25 recommendation: DER X9.62.** It's what the SE returns natively (zero conversion on the device path), and CryptoKit exposes `derRepresentation` on `P256.Signing.ECDSASignature` for trivial conversion on the sim path.

**Code change for `SoftwareKeyStore`:**
```swift
// Core/KeyStore/SoftwareKeyStore.swift (modify both sign methods)
func sign(_ data: Data) throws -> Data {
    let signature = try devicePrivateKey.signature(for: data)
    return signature.derRepresentation   // was: signature.rawRepresentation
}

func signWithAuthorization(_ data: Data) throws -> Data {
    let signature = try authPrivateKey.signature(for: data)
    return signature.derRepresentation   // was: signature.rawRepresentation
}
```

**Test verification:** A unit test should assert that both `SoftwareKeyStore.sign(...)` and (via injected fake) the SE-format check produce DER-shaped output (starts with `0x30` SEQUENCE tag).

[VERIFIED: [Apple P256.Signing.ECDSASignature.derRepresentation docs](https://developer.apple.com/documentation/cryptokit/p256/signing/ecdsasignature/derrepresentation)]

**Confidence:** HIGH

### 12. AppCoordinator/RoleCoordinator root-swap-with-fresh-AppContainer (D-04/D-05/D-18, ADR 0002)

**Existing pattern:** `SceneDelegate.presentRoot(_:)` constructs a fresh `AppContainer` + `AppCoordinator` per phase change. This is the locked ADR 0002 pattern.

**Phase 3 changes to `SceneDelegate.scene(_:willConnectTo:)`:**

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    self.window = window

    // ... DEBUG observer setup unchanged ...

    #if DEBUG
    // CI-02 / D-32: -MockOTPRoleForUITest replaces -ForceRoleForUITest semantics.
    // -ForceRoleForUITest may be retained for backward-compat or removed; D-32 recommends new path.
    if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-MockOTPRoleForUITest"),
       idx + 1 < ProcessInfo.processInfo.arguments.count,
       let role = Role(rawValue: ProcessInfo.processInfo.arguments[idx + 1]) {
        // UI-test path: skip auth, jump to role with biometric pre-disabled
        presentRoot(.role(role))
        window.makeKeyAndVisible()
        return
    }
    #endif

    // D-04/D-05: synchronous probe before first paint
    let restoreService = AppContainer.makeRestoreService()  // ad-hoc factory; reads Keychain
    let initial: AppPhase = switch restoreService.probe() {
        case .restored(let role): .role(role)
        case .needsAuth: .auth
    }
    presentRoot(initial)
    window.makeKeyAndVisible()

    // D-18: observe LogoutService notifications for re-routing
    NotificationCenter.default.addObserver(
        forName: .sessionDidInvalidate,
        object: nil,
        queue: .main
    ) { [weak self] note in
        guard let reason = note.userInfo?[Notification.Name.LogoutReasonKey] as? LogoutReason else {
            self?.presentRoot(.auth)
            return
        }
        switch reason {
        case .userInitiated, .auth401: self?.presentRoot(.auth)
        case .anotherActiveSession: self?.presentRoot(.anotherActiveSession)
        }
    }
}
```

**Phase 3 changes to `AppCoordinator.makeRoot(for:)`:**

```swift
private static func makeRoot(for phase: AppPhase, container: AppContainer) -> UIViewController {
    switch phase {
    case .launch:
        // Same as before — SceneDelegate now skips this for the cold-boot probe
        return ShipperTabBarController()
    case .auth:
        let coord = AuthCoordinator(container: container)
        coord.onAuthenticated = { role in
            NotificationCenter.default.post(name: .roleResolved, object: nil, userInfo: ["role": role])
        }
        return coord.rootViewController
    case .role(let role):
        let coord = Self.roleCoordinator(for: role)
        coord.installAvatarAffordance(presenter: { _ in })
        return coord
    case .anotherActiveSession:
        return AnotherActiveSessionViewController(supportEmail: container.env.supportEmail)
    }
}
```

**Note:** `makeRoot` needs the container (was a static taking only `phase` in Phase 1) — refactor accordingly. The static-vs-instance shape was a Phase 1 simplification.

**`AppPhase` extension (D-18):**
```swift
public enum AppPhase {
    case launch
    case auth
    case role(Role)
    case anotherActiveSession   // NEW — D-18
}
```

**Confidence:** HIGH

### 13. AUTH-06 SensitiveActionService design (D-11/D-12)

**The single-prompt-vs-double-prompt question (D-11 explicitly leaves to planner):**

**Option A — Single prompt (researcher recommendation):** Use the WWDC22 `kSecUseAuthenticationContext` pattern (see §iOS API #5).
- One LAContext.evaluatePolicy → one OS biometric prompt
- Pass that authorized LAContext into the SecKey query → SecKeyCreateSignature does NOT re-prompt
- Cleaner UX; single user-visible event

**Option B — Double prompt (let the SE drive both):** Skip the explicit evaluate; just call `SecKeyCreateSignature` and let `.biometryCurrentSet` ACL trigger one prompt.
- Then if the planner adds an "are you sure?" step that needs explicit `LAContext.evaluatePolicy` later, that becomes a separate prompt → double
- Simpler initial code; pushes design decisions to M2 when call sites land

**Researcher recommendation: Option A.** The complexity is in the future call sites, not the wiring; encoding the `kSecUseAuthenticationContext` pattern now means M2 call sites get single-prompt UX for free.

**M1 implementation (Option A):**

```swift
// Core/Auth/SensitiveActionService.swift
import Foundation
import LocalAuthentication
import Security

public protocol SensitiveActionService: AnyObject, Sendable {
    func authorize(_ payload: Data, reason: String) async throws -> Data  // DER X9.62 signature
}

public enum SensitiveActionError: Error, Sendable {
    case userCancel
    case biometryLockout
    case biometricReEnrolled
    case signFailed(underlying: Error)
}

@MainActor
public final class DefaultSensitiveActionService: SensitiveActionService {
    private let biometric: any BiometricService
    private let keyStore: any KeyStoreProtocol
    private let logger: any Logger

    public init(biometric: any BiometricService, keyStore: any KeyStoreProtocol, logger: any Logger) {
        self.biometric = biometric
        self.keyStore = keyStore
        self.logger = logger
    }

    public func authorize(_ payload: Data, reason: String) async throws -> Data {
        // M1 has zero call sites — this method exists but is exercised only by a constructibility test (D-12).
        do {
            try await biometric.evaluate(reason: reason, fallback: .none)
        } catch let lae as LAError {
            switch lae.code {
            case .userCancel: throw SensitiveActionError.userCancel
            case .biometryLockout: throw SensitiveActionError.biometryLockout
            default: throw SensitiveActionError.signFailed(underlying: lae)
            }
        }
        do {
            return try keyStore.signWithAuthorization(payload)
        } catch {
            // Could be errSecAuthFailed → re-enrollment backstop
            throw SensitiveActionError.signFailed(underlying: error)
        }
    }
}
```

**M1 unit test (the entire AUTH-06 surface per D-12):**

```swift
@Test func sensitiveActionServiceConstructible() {
    let svc = DefaultSensitiveActionService(
        biometric: StubBiometricService(),
        keyStore: SoftwareKeyStore(),
        logger: NoOpLogger()
    )
    // Method exists with the correct signature
    let _: (Data, String) async throws -> Data = svc.authorize
}
```

**Note on `kSecUseAuthenticationContext` integration:** The full pattern requires the `SensitiveActionService` to construct its own LAContext, evaluate it, and pass it through to a SecKey query. Phase 2's `SecureEnclaveKeyStore.signWithAuthorization` currently builds its own SecKey query without an externally-supplied context. To enable Option A in M1, either:
- (a) Add an overload `signWithAuthorization(_ data: Data, context: LAContext)` to KeyStoreProtocol — minimal change
- (b) Defer the optimization to M2 when call sites need it — Option A pattern is documented but not wired

D-12 says "ZERO call sites in M1" — researcher recommends (b): document the WWDC22 pattern in code comments inside `SensitiveActionService` for the M2 implementer, but the M1 wiring uses the existing Phase-2 `signWithAuthorization` which double-prompts. The constructibility test passes either way.

[VERIFIED: [WWDC22 Streamline local authorization](https://developer.apple.com/videos/play/wwdc2022/10108/) + Phase 2 SecureEnclaveKeyStore.swift]

**Confidence:** MEDIUM (only because of the Option A vs B planner choice — both are valid patterns)

### 14. `SessionRestoreService.probe()` cold-boot design (D-04/D-05)

**Recommended interface:**

```swift
// Core/Auth/SessionRestoreService.swift
import Foundation

public enum SessionRestoreResult: Sendable {
    case restored(role: Role)
    case needsAuth
}

public protocol SessionRestoreService: Sendable {
    /// Reads Keychain SYNCHRONOUSLY. Sub-millisecond — safe to call on the main thread before first paint.
    func probe() -> SessionRestoreResult
}

public final class DefaultSessionRestoreService: SessionRestoreService, @unchecked Sendable {
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(keychain: KeychainStore, logger: any Logger) {
        self.keychain = keychain
        self.logger = logger
    }

    public func probe() -> SessionRestoreResult {
        // BOTH must be present for a valid restore (D-04).
        let token = (try? keychain.get(.sessionToken)).flatMap { String(data: $0, encoding: .utf8) }
        let roleString = (try? keychain.get(.sessionRole)).flatMap { String(data: $0, encoding: .utf8) }

        guard let token, !token.isEmpty,
              let roleString, let role = Role(rawValue: roleString) else {
            // Partial state cleanup — D-04 says clean up the partial state
            try? keychain.delete(.sessionToken)
            try? keychain.delete(.sessionRole)
            try? keychain.delete(.sessionUserID)
            return .needsAuth
        }
        return .restored(role: role)
    }
}
```

**Synchronous reads:** `SecItemCopyMatching` is a synchronous C API; in practice it's < 1ms for a single item. SceneDelegate calls `probe()` directly before `presentRoot` — no spinner needed.

**Partial state handling:** If only the token or only the role is present, treat as `.needsAuth` AND clean up the partial state (avoids zombie keychain items).

**Performance budget:** SceneDelegate must call this and `presentRoot(_:)` before the user sees anything. Three Keychain reads + a switch is well under 5ms total.

**Thread isolation:** Service is plain `Sendable` (not `@MainActor`); SceneDelegate calls it from the main thread on cold-boot. Safe because `KeychainStore` is `@unchecked Sendable` with internal locking via the Security framework.

**Confidence:** HIGH

### 15. Swift Concurrency + MainActor isolation for biometric/LAContext paths (D-31)

**Recommended actor isolation per service:**

| Service | Actor isolation | Rationale |
|---------|-----------------|-----------|
| `SessionLockService` | `@MainActor` | Notification observers fire on main; `enteredBackgroundAt` mutation is per-event |
| `BiometricService` | `@MainActor` | LAContext callback can fire on arbitrary queue; UI dismissal must be main; main-bound service localizes the boundary |
| `SensitiveActionService` | `@MainActor` | Same as BiometricService — calls into it |
| `LogoutService` | `@MainActor` | Calls into MainActor services + posts a Notification (which observers expect on main) |
| `SessionRestoreService` | `Sendable` (not actor-isolated) | Synchronous, no UI, called from main on cold-boot |
| `LocationProvider` | `@MainActor` | Delegate callbacks on arbitrary queue but bridged to main via `Task { @MainActor in ... }` |

**LAContext callback handling:** `evaluatePolicy(_:localizedReason:reply:)`'s reply closure is invoked on a queue Apple does not document. The continuation's `resume(...)` is thread-safe; the *next statement after `try await`* runs on the actor of the caller. Since `BiometricService` is `@MainActor`, the post-success domain-state read happens on main.

**Sendable conformances:**
- `SessionLockService`/`BiometricService`/`SensitiveActionService`/`LogoutService` — `AnyObject + Sendable`. With `@MainActor` isolation, conformance is automatic.
- `SessionRestoreService` — `Sendable` (struct- or class-shaped). The `DefaultSessionRestoreService` uses `@unchecked Sendable` because Keychain calls are stateless.

**Project-wide hint:** Phase 1+2 use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (per `OTPRequestEndpoint.swift` comment). Sticking with main-actor defaults across `Core/Auth/` services keeps the model consistent.

**Confidence:** HIGH

### 16. OTPVerifyEndpoint orchestration sequence (D-27)

**Locked 7-step sequence per D-27:**

```swift
// OTPViewModel.verify(code:) (sketch)
@MainActor
func verify(code: String, otpSessionID: String, location: CLLocationCoordinate2D) async {
    state = .verifying
    do {
        // STEP 1: OTP verify call
        let resp = try await apiClient.request(OTPVerifyEndpoint(otpSessionID: otpSessionID, code: code))
        // STEP 2: Persist sessionToken/role/userID to Keychain (D-06)
        state = .settingUp(progress: 1, total: 6)
        try keychain.set(Data(resp.sessionToken.utf8), for: .sessionToken, accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data(resp.role.utf8), for: .sessionRole, accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data(resp.userID.utf8), for: .sessionUserID, accessibility: .afterFirstUnlockThisDeviceOnly)

        // STEP 3+4: Generate device + auth keys (idempotent guard from CR-02 makes this safe to re-run)
        state = .settingUp(progress: 2, total: 6)
        let (devicePub, _) = try keyStore.generateDeviceIdentityKeys()

        // STEP 5: POST /device/register
        state = .settingUp(progress: 4, total: 6)
        let fingerprint = try DeviceFingerprint.current(keychain: keychain)
        let payload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
            model: fingerprint.model, iosVersion: fingerprint.iosVersion, installUUID: fingerprint.installUUID
        )
        do {
            _ = try await apiClient.request(DeviceRegisterEndpoint(
                devicePublicKey: devicePub.base64EncodedString(),
                fingerprint: payload
            ))
        } catch {
            // D-27: step 5 failure shows retry without blowing the session
            state = .registerFailed(retry: { Task { await self.verify(code: code, otpSessionID: otpSessionID, location: location) } })
            return
        }

        // STEP 6: BiometricService.evaluate to record initial domainState
        state = .settingUp(progress: 5, total: 6)
        try await biometric.evaluate(reason: "Sign in to Validation Ledger", fallback: .none)
        sessionLock.recordBiometricSuccess(at: .now)

        // STEP 7: presentRoot
        state = .settingUp(progress: 6, total: 6)
        guard let role = Role(rawValue: resp.role) else {
            state = .error(.unknownRole(resp.role))
            return
        }
        onAuthenticated?(role)
    } catch let net as NetworkError {
        state = .error(.network(net))
    } catch {
        state = .error(.unknown(error))
    }
}
```

**"Setting up your account..." progress UI:** A simple full-screen overlay with a `UIActivityIndicatorView` + step-label ("Generating device key…", "Registering device…", "Verifying biometric…"). Lives inside OTPViewController as a child VC — dismisses automatically when state transitions back to `.idle` or away from `.settingUp`.

**Step-5 failure recovery (per D-27):** Retry button calls back into the same orchestration starting at step 5; the Keychain writes from step 2 + the SE keys from step 3+4 survive (idempotent guard ensures safety).

**Confidence:** HIGH

### 17. 5 role UI smoke tests (D-32, SC-1)

**Phase 1 placeholder:** `validationLedgerUITests/RoleShellSmokeTests.swift` already has 5 tests using `-ForceRoleForUITest <role>` to skip auth and land on a role.

**Phase 3 upgrade per D-32:** Replace with `-MockOTPRoleForUITest <role>` that drives the OTP flow end-to-end via mocked fixtures. Each test:
1. Launch app with `-MockOTPRoleForUITest carrier` (etc.)
2. Wait for phone-entry screen
3. Type `5551234567`, tap Submit
4. Wait for OTP screen
5. Type `123456`, tap Verify
6. Assert role-appropriate tab bar appears
7. Assert tab titles match TechStack §4 verbatim
8. Tap avatar → ProfileVC modal appears
9. Tap Logout → assert phone-entry returns

**MockOTPRoleForUITest wiring:** SceneDelegate (DEBUG only) reads the launchArgument; the value is passed to `AppContainer` to register a one-off `MockURLProtocol` handler that overrides `OTPVerifyEndpoint`'s response with a fixed role.

**Test sketch (carrier example):**

```swift
func testCarrierFullFlow() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-MockOTPRoleForUITest", "carrier"]
    app.launch()

    // Phone entry
    let phoneField = app.textFields["phone-entry-field"]
    XCTAssertTrue(phoneField.waitForExistence(timeout: 5))
    phoneField.tap()
    phoneField.typeText("5551234567")
    app.buttons["phone-entry-submit"].tap()

    // OTP entry
    let otpField = app.textFields["otp-field"]
    XCTAssertTrue(otpField.waitForExistence(timeout: 5))
    otpField.tap()
    otpField.typeText("123456")
    app.buttons["otp-verify"].tap()

    // Carrier tabs (TechStack §4 verbatim)
    XCTAssertTrue(app.tabBars.buttons["Loads"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.tabBars.buttons["Drivers"].exists)
    XCTAssertTrue(app.tabBars.buttons["Documents"].exists)
    XCTAssertTrue(app.tabBars.buttons["Assistant"].exists)

    // Logout via avatar
    app.buttons["nav-avatar"].tap()
    app.buttons["profile-logout"].tap()

    // Back to phone entry
    XCTAssertTrue(app.textFields["phone-entry-field"].waitForExistence(timeout: 5))
}
```

**Why XCUITest (not Swift Testing) per STACK-03:** UI tests run as separate processes against the launched app; XCTest's `XCUIApplication` is the only supported entry point.

**Confidence:** HIGH

### 18. HUMAN-UAT vs automatable success criteria

**The 5 SCs from ROADMAP.md:**
1. **SC-1:** 5 roles can OTP → land on TechStack §4 tabs — **AUTOMATABLE** (XCUITest, see #17).
2. **SC-2:** Cold-boot with valid token shows biometric prompt before content — **HUMAN-UAT** (real biometric hardware required; airplane mode + force-quit + relaunch is a physical-device scenario).
3. **SC-3:** Background >5min triggers biometric; <5min does not — **HUMAN-UAT** (real backgrounding + clock-advance behavior on device; can't fake `UIApplication` lifecycle in XCUITest reliably for >5min).
4. **SC-4:** Logout wipes Keychain + SE auth-key ACL + role coordinator + returns to phone-entry — **PARTIALLY AUTOMATABLE.** XCUITest can verify "returns to phone-entry"; a unit test on `LogoutService` can verify Keychain + SE deletion. Inspecting Keychain post-logout via the DevMenu Keychain inspector is HUMAN-UAT.
5. **SC-5:** Non-US auth refused; raw coordinates never in any log/analytics — **AUTOMATABLE.** Unit tests on `CountryGate` (with injected geocoder fake) verify refusal; phantom-typed enum compile error verifies the lint constraint; SwiftLint CI run verifies the rule fires on planted violations.

**Distribution:** 3 of 5 fully automatable; 2 require physical device + manual interaction.

**Confidence:** HIGH

## Pre-Phase-3 Carryover Fix Details

### CR-02: `SecureEnclaveKeyStore.generateKey(slot:)` idempotent guard

**Bug:** Calling `generateKey(slot: .device)` twice silently inserts a second SE key with the same `kSecAttrApplicationTag`. A subsequent `loadPrivateKey(slot: .device)` returns whichever the OS finds first — could be the old key, breaking pub/priv pairing.

**Fix (5 lines at top of `generateKey`):**

```swift
private func generateKey(slot: Keyslot) throws -> Data {
    // CR-02: idempotent guard — return the existing public key if a key already exists for this slot.
    if let existingPub = try? loadPublicKey(slot: slot) {
        return existingPub
    }
    // ... rest of the existing implementation unchanged ...
    var acError: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(...) else { ... }
    // ...
}
```

**Why this works:** `loadPublicKey` calls `loadPrivateKey` which queries SecItem; if errSecItemNotFound, we proceed with generation. If the key exists, we return its public bytes — same return shape, no duplicate insertion.

**Test:** Call `generateKey(slot: .device)` twice; assert both calls return identical `Data`.

### IN-01: `OTPVerifyEndpoint.RequestBody.otpSessionID` CodingKeys

**Bug:** With `keyEncodingStrategy = .convertToSnakeCase`, JSONEncoder converts `otpSessionID` to `otp_session_i_d` (treats trailing acronym character-by-character). Backend expects `otp_session_id`.

**Fix:**

```swift
public struct RequestBody: Encodable, Sendable {
    public let otpSessionID: String
    public let code: String

    private enum CodingKeys: String, CodingKey {
        case otpSessionID = "otp_session_id"  // explicit override
        case code
    }
}
```

**Note:** This is the inverse of the Response-side fix already in `OTPVerifyEndpoint.Response`. The encoder strategy and decoder strategy mirror each other; both need explicit overrides.

### IN-05: `uploadID` (KYCUploadChunkEndpoint, KYCUploadCommitEndpoint) + `installUUID` (DeviceRegisterEndpoint.DeviceFingerprintPayload)

Same pattern. Add explicit CodingKeys to each `RequestBody` / nested `Encodable` struct that has an acronym-tail property:

```swift
// DeviceRegisterEndpoint.DeviceFingerprintPayload
public struct DeviceFingerprintPayload: Encodable, Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String

    private enum CodingKeys: String, CodingKey {
        case model
        case iosVersion = "ios_version"
        case installUUID = "install_uuid"   // explicit
    }
    // ... init unchanged ...
}
```

(Same pattern for KYCUploadChunkEndpoint and KYCUploadCommitEndpoint `uploadID`.)

### IN-02: `SoftwareKeyStore` returns DER X9.62 (matching SE)

See §iOS API #11 above — change both `sign(_:)` and `signWithAuthorization(_:)` in `SoftwareKeyStore` to return `signature.derRepresentation` instead of `signature.rawRepresentation`.

## Common Pitfalls

### Pitfall 1: `evaluatedPolicyDomainState` is nil before first evaluate/canEvaluate
**What goes wrong:** SessionLockService.lockState() compares stored vs current domain state; current is nil; comparison fails or always-equals; re-enrollment is undetected.
**Why:** The property only becomes non-nil after a successful `evaluatePolicy` OR successful `canEvaluatePolicy` call.
**How to avoid:** Always call `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error:)` before reading the property in `BiometricService.currentDomainState()`. (Pattern 3 above.)
**Warning signs:** SESS-03 device tests fail intermittently; "biometric changed" copy never appears in QA.

### Pitfall 2: Reverse geocode network failure not refused
**What goes wrong:** GEO-01 country gate accepts a missing `isoCountryCode` and lets the auth attempt proceed; user in non-US territory gets through.
**Why:** Engineer treats CLGeocoder error as "couldn't determine = neutral" instead of "couldn't determine = refuse".
**How to avoid:** D-21 explicit decision: any geocode failure (network, timeout, nil placemark, nil isoCountryCode) → refuse with the same NotAvailableInRegionVC.
**Warning signs:** GEO-02 unit tests pass but QA in airplane mode succeeds (should refuse).

### Pitfall 3: Logout race — UI dismisses before Keychain wipe completes
**What goes wrong:** Profile tap → root-swap to .auth → user re-enters phone → cold-boot probe re-reads stale Keychain values → gets routed back to role shell.
**Why:** Notification posted before async Keychain delete completes.
**How to avoid:** `LogoutService.logout(reason:)` is `async`; the `.sessionDidInvalidate` Notification post is the LAST step (D-16 step 6). SceneDelegate's observer reacts AFTER all teardown is complete.
**Warning signs:** Logout works in unit tests but fails in UI tests; intermittent "logged out then logged back in" QA reports.

### Pitfall 4: SwiftLint custom rule's regex over-matches
**What goes wrong:** `ban_raw_coordinate_literal` rule fires on `// CLLocationCoordinate2D(latitude:` in a comment, blocking the build for documentation.
**Why:** Custom rules apply to all syntax kinds by default unless `match_kinds:` is restricted.
**How to avoid:** Add `match_kinds: ["identifier", "typeidentifier"]` to the rule, OR test the rule by planting violations in comments (Phase 1 plant-violation pattern) and confirming the rule does NOT fire on comment text.
**Warning signs:** CI fails on a doc-comment in a Geo file outside the allow-list.

### Pitfall 5: BiometricLockVC presented over wrong VC during root-swap
**What goes wrong:** SceneDelegate sets `window.rootViewController = newCoord.rootViewController` then immediately calls `window.rootViewController.present(lockVC)`. iOS returns "view controller has no view in window hierarchy yet" → present silently fails.
**Why:** `present` requires the presenter to be in the window hierarchy; just-set rootVC may not have laid out.
**How to avoid:** Defer the present to the next runloop: `DispatchQueue.main.async { window.rootViewController?.present(lockVC, animated: false) }`. Or present from the AppCoordinator's init AFTER the rootVC is wired.
**Warning signs:** First cold-boot biometric never appears; second cold-boot works.

### Pitfall 6: `notificationCenter.addObserver(forName:object:queue:using:)` retain cycle
**What goes wrong:** SessionLockService observer closure captures `self` strongly; service can never deinit.
**Why:** The block-based addObserver returns a token, not a deregistration; the closure is held by NotificationCenter.
**How to avoid:** Use `[weak self]` in the closure; remove tokens in `deinit`. (Shown in §iOS API #7.)
**Warning signs:** AppContainer.deinit logs missing on root-swap; memory growing on repeated swaps.

## Code Examples

### `KeychainStore.deleteAll(under:)` extension (D-16, D-33)

```swift
// Core/Storage/Keychain/KeychainScope.swift (NEW)
import Foundation

public enum KeychainScope: Sendable {
    case session  // session.token, session.role, session.userID, biometric.domainState
}

extension KeychainKey {
    public static let sessionRole         = KeychainKey(rawValue: "session.role")
    public static let sessionUserID       = KeychainKey(rawValue: "session.userID")
    public static let biometricDomainState = KeychainKey(rawValue: "biometric.domainState")
}

// Core/Storage/Keychain/KeychainStore.swift (modify)
extension KeychainStore {
    public func deleteAll(under scope: KeychainScope) throws {
        let keys: [KeychainKey] = switch scope {
        case .session: [.sessionToken, .sessionRole, .sessionUserID, .biometricDomainState]
        }
        for key in keys {
            try delete(key)  // existing API; idempotent
        }
    }
}
```

### `LogoutService` (D-16)

```swift
// Core/Auth/LogoutService.swift (NEW)
import Foundation

public enum LogoutReason: String, Sendable {
    case userInitiated
    case auth401
    case anotherActiveSession
}

extension Notification.Name {
    public static let sessionDidInvalidate = Notification.Name("validationLedger.sessionDidInvalidate")
    public static let LogoutReasonKey = Notification.Name("validationLedger.LogoutReasonKey")
}

public protocol LogoutService: AnyObject, Sendable {
    func logout(reason: LogoutReason) async
}

@MainActor
public final class DefaultLogoutService: LogoutService {
    private let keychain: KeychainStore
    private let keyStore: any KeyStoreProtocol
    private let sessionLock: any SessionLockService
    private let logger: any Logger
    private let notificationCenter: NotificationCenter

    public init(
        keychain: KeychainStore,
        keyStore: any KeyStoreProtocol,
        sessionLock: any SessionLockService,
        logger: any Logger,
        notificationCenter: NotificationCenter = .default
    ) {
        self.keychain = keychain
        self.keyStore = keyStore
        self.sessionLock = sessionLock
        self.logger = logger
        self.notificationCenter = notificationCenter
    }

    public func logout(reason: LogoutReason) async {
        // 1. In-memory state — service-layer state is held by callers; nothing to clear here.
        // 2. Wipe session Keychain entries
        try? keychain.deleteAll(under: .session)
        // 3. Delete SE authorization key (deviceKey preserved)
        try? keyStore.deleteKey(slot: .authorization)
        // 4. Already covered by deleteAll(.session) — biometric.domainState is in the .session scope set
        // 5. Invalidate session lock
        sessionLock.invalidate()
        // 6. Post notification (LAST step, after all teardown complete — Pitfall 3)
        logger.info(event: .init("logout"), fields: [.event: reason.rawValue])
        notificationCenter.post(
            name: .sessionDidInvalidate,
            object: nil,
            userInfo: [Notification.Name.LogoutReasonKey: reason]
        )
    }
}
```

### `Auth401ResponseInterceptor` (D-28)

```swift
// Core/Networking/Interceptors/Auth401ResponseInterceptor.swift (NEW)
import Foundation

public struct Auth401ResponseInterceptor: ResponseInterceptor {
    private let logout: any LogoutService
    private static let excludedPaths: Set<String> = ["/auth/otp/request", "/auth/otp/verify"]

    public init(logout: any LogoutService) { self.logout = logout }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await send(request)
        if response.statusCode == 401,
           let path = request.url?.path,
           !Self.excludedPaths.contains(path) {
            // Fire-and-forget — caller still gets the 401 response to handle/decode normally
            Task { await logout.logout(reason: .auth401) }
        }
        return (data, response)
    }
}
```

## State of the Art

| Old Approach | Current Approach (iOS 17+) | When Changed | Impact |
|--------------|----------------------------|--------------|--------|
| `LAContext.evaluatePolicy(_:_:reply:)` closure | Continuation-bridged async/await | iOS 15+ async APIs available; no built-in async overload for evaluatePolicy specifically | Use `withCheckedThrowingContinuation` (Pattern 3) — Apple has not shipped a built-in async wrapper |
| `CLLocationManager` delegate one-shot | `CLLocationUpdate.liveUpdates()` AsyncSequence (iOS 17+) | iOS 17 | One-shot pre-check is not a stream — continuation-bridge of `requestLocation` is simpler. Streaming is for active tracking |
| Two-prompt biometric flow | `kSecUseAuthenticationContext` single-prompt (WWDC22) | iOS 16 | M2 sensitive-action call sites benefit; M1 documents the pattern |
| URLSession local-retry-policy | Custom `ResponseInterceptor` (Phase 2 RetryInterceptor) | N/A — URLSession never offered configurable retry | Phase 2 already shipped this |
| SwiftUI for sensitive surfaces | UIKit for sensitive surfaces | CLAUDE.md project constraint | Locked — no change |

**Deprecated/outdated:**
- `policyDomainState` (older API name) → replaced by `evaluatedPolicyDomainState` years ago. Don't reference the old name in code or comments.
- `CLLocationManager.startUpdatingLocation` for one-shot use → use `requestLocation` or `liveUpdates()`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `CLGeocoder.reverseGeocodeLocation` async-throws variant exists since iOS 13 | iOS API #3 | LOW — well-documented; if wrong, fallback to closure-bridged is trivial |
| A2 | Single-prompt via `kSecUseAuthenticationContext` is the correct WWDC22 pattern for M2 sensitive actions | iOS API #5, #13 | MEDIUM — D-12 ZERO call sites in M1 means the choice doesn't bite until M2; design note suffices |
| A3 | `SwiftLint custom_rules.excluded` accepts a single regex pattern (not a list) | iOS API #10 | LOW — verified by Phase 1's `ban_direct_os_log` rule which uses the same shape |
| A4 | `signature.derRepresentation` on `P256.Signing.ECDSASignature` is available in iOS 13+ | iOS API #11 | LOW — Apple docs confirm |
| A5 | `LAContext.evaluatedPolicyDomainState` reliably differs after biometric re-enrollment across iOS 17.x point releases | iOS API #1, Pitfall 1 | MEDIUM — Apple does not document the stability guarantee, but every public source (Carver Code, SwiftRocks, etc.) confirms it works in production |
| A6 | `addObserver(forName:object:queue:using:)` in `init` and `removeObserver` in `deinit` is sufficient for proper cleanup; no need for didEnter notification token registration in scene-aware init | iOS API #7 | LOW — standard pattern; multi-scene apps may need per-scene wiring (single-scene M1 is fine) |
| A7 | Backend will return `Retry-After` as delta-seconds (not HTTP-date) in the M1 mock fixture | iOS API #4 | LOW — both formats handled by parser |

## Open Questions

1. **Should the Phase-1 `-ForceRoleForUITest` argument be removed in favor of `-MockOTPRoleForUITest`?**
   - What we know: Phase 1's argument bypasses auth entirely; D-32's new argument drives the OTP flow.
   - What's unclear: whether the Phase-1 path is still useful for debugging (DevMenu role switcher).
   - Recommendation: keep both; `-ForceRoleForUITest` is debug-only and harmless to retain. Plans should NOT remove existing tests that rely on it.

2. **What's the correct E.164 formatter for US numbers?**
   - What we know: D-26 says US-only `+1`; format display as `(XXX) XXX-XXXX`.
   - What's unclear: whether the `+1` is shown to the user or implicit.
   - Recommendation: Show the `+1` as a static prefix label to the left of the input field; the input itself accepts only the 10 digits.

3. **What avatar visual to show when there's no profile data yet?**
   - What we know: Sessions resolved by D-04 have `userID` in Keychain — but no display name (backend doesn't return one in mock).
   - What's unclear: should the avatar show role initial, "?", or a system icon?
   - Recommendation: M1 uses the role's first letter with a system tint background (S/B/C/D/F). Replace with real initials in M2 when backend ships a `displayName` field.

4. **Should `BiometricService.evaluate` accept a custom `LAContext` (DI for testing)?**
   - What we know: A fresh LAContext is created internally for each call (per anti-pattern note).
   - What's unclear: whether tests inject a fake.
   - Recommendation: Use a `BiometricService` protocol with a `StubBiometricService` for unit tests; don't try to mock `LAContext` itself (it's a system class with private init paths).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 15+ | Build all phases | ✓ (assumed; per CLAUDE.md) | 26.4 in TechStack | — |
| iOS 17.0 SDK | Build all phases | ✓ | 17.0+ | — |
| LocalAuthentication framework | All biometric paths | ✓ (built-in) | iOS 17 | — |
| CoreLocation framework | GEO-01..02 | ✓ (built-in) | iOS 17 | — |
| Security framework | SE keys, ACL, signing | ✓ (built-in, Phase 2 already uses) | iOS 17 | — |
| SwiftLint binary | `.swiftlint.yml` rule enforcement | ✓ (Phase 1 SwiftLintPlugins SPM dep) | 0.63.2 | — |
| Physical iPhone with Face ID/Touch ID enrolled | SC-2, SC-3, SC-4 partial, SESS-03 device tests | (User-supplied; HUMAN-UAT) | — | Simulator can run all unit tests; device tests are HUMAN-UAT |
| Backend | NONE in Phase 3 (mock-only — Environment.apiBaseURL nil) | N/A | — | MockURLProtocol drives all flows |

**Missing dependencies with no fallback:** None — Phase 3 is fully mock-driven on the backend side.

**Missing dependencies with fallback:** Physical biometric device — fallback is HUMAN-UAT for the SCs that require it (SC-2, SC-3 explicit per CONTEXT.md).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (unit, per Phase 1 STACK-03) + XCTest/XCUITest (UI tests, per STACK-03) |
| Config files | `validationLedger.xcodeproj/xcshareddata/xcschemes/*.xcscheme` (test plans); no separate config |
| Quick run command (sim, unit only) | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerTests` |
| Quick UI test (single role smoke) | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerUITests/RoleShellSmokeTests/testCarrierFullFlow` |
| Full sim suite | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15'` |
| Device suite (HUMAN-UAT) | `xcodebuild test -scheme validationLedger -destination 'platform=iOS,name=<device>' -only-testing:validationLedgerDeviceTests` |
| SwiftLint | `swiftlint lint --strict validationLedger/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTH-01 | E.164 phone input + format display | unit | `xcodebuild test ... -only-testing:.../PhoneEntryViewModelTests` | ❌ Wave 0 |
| AUTH-02 | 429 → countdown timer disables Verify; on 0 enables | unit | `.../OTPViewModelTests/test429Countdown` | ❌ Wave 0 |
| AUTH-02 | APIClient parses 429 + Retry-After to NetworkError.rateLimited | unit | `.../APIClientTests/test429RetryAfterParsing` | ❌ extends existing tests |
| AUTH-03 | sessionToken stored in Keychain after verify | unit | `.../OTPViewModelTests/testStoresSessionToken` | ❌ Wave 0 |
| AUTH-04 | Logout wipes Keychain + SE auth-key | unit | `.../LogoutServiceTests/testWipesKeychainAndAuthKey` | ❌ Wave 0 |
| AUTH-04 | Logout returns to phone-entry | UI | `.../RoleShellSmokeTests/testCarrierFullFlow` (logout step) | ⚠️ existing file, needs upgrade |
| AUTH-05 | 401 (non-OTP path) → triggers logout | unit | `.../Auth401ResponseInterceptorTests/test401TriggersLogout` | ❌ Wave 0 |
| AUTH-05 | 401 on /auth/otp/verify does NOT trigger logout | unit | `.../Auth401ResponseInterceptorTests/test401OnOTPPathExcluded` | ❌ Wave 0 |
| AUTH-06 | SensitiveActionService constructible with correct signature | unit | `.../SensitiveActionServiceTests/testConstructibleWithSignature` | ❌ Wave 0 |
| SHELL-01 | RoleCoordinator instantiates correct shell per role | unit | `.../AppCoordinatorTests/testRoleCoordinatorMapping` | ❌ Wave 0 |
| SHELL-02 | Each role's TabBar has correct tabs (TechStack §4) | UI | 5 × `.../RoleShellSmokeTests/test*FullFlow` | ⚠️ exists; upgrade for D-32 |
| SHELL-03 | Avatar item appears on each tab | UI | `.../RoleShellSmokeTests/test*FullFlow` (avatar tap) | ⚠️ exists; extend |
| SHELL-04 | No "switch role" UI exists | unit | `.../FeaturesProfileTests/testNoSwitchRoleAffordance` (grep test) | ❌ Wave 0 |
| SESS-01 | SessionRestoreService.probe with both keys → .restored | unit | `.../SessionRestoreServiceTests/testRestoresWithBothKeys` | ❌ Wave 0 |
| SESS-01 | Probe with missing keys → .needsAuth + cleans partial state | unit | `.../SessionRestoreServiceTests/testNeedsAuthOnPartial` | ❌ Wave 0 |
| SESS-01 | Cold-boot biometric prompt before content | device | HUMAN-UAT | N/A — physical |
| SESS-02 | >5min background → biometric on return | device | HUMAN-UAT | N/A — physical |
| SESS-02 | <5min background → no biometric | device | HUMAN-UAT | N/A — physical |
| SESS-02 | Logic: enteredBackgroundAt + grace > 5min returns .locked | unit | `.../SessionLockServiceTests/testBackgroundTimeoutGate` | ⚠️ extends existing |
| SESS-03 | domainState diff returns .locked(.biometricReEnrolled) | unit | `.../SessionLockServiceTests/testDomainStateDiff` | ❌ Wave 0 |
| SESS-03 | Real biometric re-enrollment triggers detection | device | HUMAN-UAT | N/A — physical |
| SESS-04 | LogoutService teardown order matches D-16 | unit | `.../LogoutServiceTests/testTeardownOrder` | ❌ Wave 0 |
| GEO-01 | requestPermission triggers prompt; status callback bridged | unit | `.../LocationProviderTests/testPermissionFlow` | ❌ Wave 0 |
| GEO-02 | CountryGate returns refuse on non-US placemark | unit | `.../CountryGateTests/testRefusesNonUS` | ❌ Wave 0 |
| GEO-02 | CountryGate refuses on geocode failure (D-21) | unit | `.../CountryGateTests/testRefusesOnFailure` | ❌ Wave 0 |
| GEO-03 | PlatformPayloadField cannot substitute for LogField | unit (compile-shape) | `.../PlatformPayloadFieldTests/testTypesAreDisjoint` | ❌ Wave 0 |
| GEO-03 | SwiftLint rule fires on planted violation | CI lint | `swiftlint lint --strict` after planted line | manual planted-violation pattern (Phase 1 precedent) |
| DEV-06 | .anotherActiveSession reason routes to AnotherActiveSessionVC | unit | `.../SceneDelegate*Tests/testAnotherActiveSessionRouting` | ❌ Wave 0 |
| Pre-Phase-3 CR-02 | generateKey idempotent — second call returns same pubkey | unit (sim) | `.../SoftwareKeyStoreTests/testGenerateKeyIdempotent` (sim path); device variant in DeviceTests | ❌ Wave 0 |
| Pre-Phase-3 IN-01/05 | Encoded JSON has correct snake_case acronym keys | unit | `.../EndpointEncodingTests/testAcronymCodingKeys` | ❌ Wave 0 |
| Pre-Phase-3 IN-02 | SoftwareKeyStore.sign returns DER-shaped bytes | unit | `.../SoftwareKeyStoreTests/testSignReturnsDER` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Run the file-scoped unit tests for the file changed (`xcodebuild test ... -only-testing:validationLedgerTests/Auth/<File>Tests`).
- **Per wave merge:** Full simulator suite (`xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 15'`) + SwiftLint pass.
- **Phase gate:** Full simulator suite green + SwiftLint zero violations + 5/5 RoleShellSmokeTests pass + HUMAN-UAT items captured (SC-2, SC-3, SC-4 Keychain inspector, SESS-03 device).

### Wave 0 Gaps

- [ ] `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` — covers SESS-01
- [ ] `validationLedgerTests/Auth/LogoutServiceTests.swift` — covers AUTH-04, SESS-04
- [ ] `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` — covers AUTH-06 constructibility
- [ ] `validationLedgerTests/Auth/BiometricServiceTests.swift` — covers BiometricService stub-able shape (no real LAContext on sim)
- [ ] `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` — covers AUTH-05
- [ ] `validationLedgerTests/Networking/APIClientRateLimitTests.swift` — covers AUTH-02 429 parsing
- [ ] `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` — required fixture
- [ ] `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — covers GEO-03 type disjointness
- [ ] `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` — covers GEO-01
- [ ] `validationLedgerTests/Identity/Geo/CountryGateTests.swift` — covers GEO-02
- [ ] `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` — covers AUTH-01
- [ ] `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` — covers AUTH-02 + AUTH-03 + D-27 orchestration
- [ ] `validationLedgerTests/App/AppCoordinatorTests.swift` — covers SHELL-01 + DEV-06 routing
- [ ] `validationLedgerTests/Networking/EndpointEncodingTests.swift` — covers IN-01/IN-05 acronym CodingKeys
- [ ] Extend `validationLedgerTests/Auth/SessionLockServiceTests.swift` — add SESS-02 logic tests + SESS-03 domainState diff tests
- [ ] Extend `validationLedgerTests/KeyStore/SoftwareKeyStoreTests.swift` — add IN-02 DER-shape test + CR-02 idempotent test
- [ ] Upgrade `validationLedgerUITests/RoleShellSmokeTests.swift` — drive full OTP flow per D-32 (SC-1, SC-4 partial)
- [ ] New `validationLedgerDeviceTests/EvaluatedPolicyDomainStateTests.swift` — HUMAN-UAT for SESS-03 on real device

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | OTP via mocked SMS (AUTH-01..02); session token in Keychain (AUTH-03); strict accessibility class `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| V3 Session Management | yes | SessionLockService biometric re-prompt (SESS-01..04); single LogoutService source of truth (SESS-04); cold-boot session restore via Keychain (SESS-01) |
| V4 Access Control | yes | One-active-device enforcement (DEV-06); role established at account creation, not changeable client-side (SHELL-04); auto-logout on 401 (AUTH-05) |
| V5 Input Validation | yes | E.164 phone format (AUTH-01); CLGeocoder result validation + freshness (GEO-01..02); deny-by-default for missing isoCountryCode (D-21) |
| V6 Cryptography | yes | Secure Enclave EC P-256 keys (Phase 2); `.biometryCurrentSet` ACL on authorizationKey (D-15); DER X9.62 signature normalization (IN-02); never hand-roll crypto |
| V7 Error Handling & Logging | yes | PIIScrubber redacts phone/email/coords (Phase 1); zero raw coordinates in logs (GEO-03 phantom-typed enum); `LAError` mapped to typed `SensitiveActionError` (D-11) |
| V8 Data Protection | yes | Tokens in Keychain (AUTH-03); SE keys never extractable; logout wipes session + clears SE auth-key ACL (AUTH-04, SESS-04) |
| V9 Communication | partial | Cert pinning active in Phase 2 (SEC-01); Phase 3 inherits — no new comms surface |
| V10 Malicious Code | partial | App Attest deferred to Phase 4 (DEV-04); Phase 3 only refuses launch if SE unavailable (Phase 2 SC-4) |
| V11 Business Logic | yes | US-only geo gate (GEO-01..02); deny-on-failure posture (D-21); no self-serve recovery (anti-feature, requires re-KYC) |

### Known Threat Patterns for Phase 3 stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| OTP brute-force on /auth/otp/verify | Spoofing | Backend 429 + Retry-After (D-02); iOS surfaces countdown but is not the enforcer |
| Stolen sessionToken from Keychain after device theft | Information disclosure | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` requires device unlock once post-boot to read; biometric re-prompt at app foreground (SESS-02) caps exposure |
| Biometric re-enrollment used to hijack signed-in session | Elevation of privilege | `.biometryCurrentSet` ACL on SE auth-key invalidates on re-enrollment; SessionLockService domainState diff detects + prompts re-bind (SESS-03) |
| Geo-spoofing client to bypass US-only check | Tampering | Backend re-verifies (defense in depth); client check is GEO-02 + denies on failure |
| Coordinate leak via analytics | Information disclosure | Phantom-typed enum + SwiftLint rule (GEO-03 + D-23/D-24) make raw coordinates a compile error in non-allow-listed paths |
| Logout race leaving stale session in Keychain | Repudiation, EoP | Single LogoutService funnel (D-16); notification posted LAST (Pitfall 3) |
| Replay of /device/register payload | Spoofing | Idempotency-Key interceptor (Phase 2 NET-04); Phase 4 will add App Attest assertion (DEV-04) |
| 401 storm causing repeated logouts | DoS | Auth401ResponseInterceptor logs out once and lets the response surface; subsequent 401s on the now-logged-out path are no-ops |

## Sources

### Primary (HIGH confidence)
- [Apple LAContext docs](https://developer.apple.com/documentation/localauthentication/lacontext) — biometric APIs
- [Apple evaluatedPolicyDomainState docs](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatedpolicydomainstate) — D-09 detection invariant
- [Apple LAError docs](https://developer.apple.com/documentation/localauthentication/laerror) — error mapping
- [Apple CLLocationManager docs](https://developer.apple.com/documentation/corelocation/cllocationmanager)
- [Apple CLGeocoder docs](https://developer.apple.com/documentation/corelocation/clgeocoder)
- [Apple CLPlacemark.isoCountryCode docs](https://developer.apple.com/documentation/corelocation/clplacemark/isocountrycode)
- [Apple SecKeyCreateSignature docs](https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:))
- [Apple SecKeyAlgorithm docs](https://developer.apple.com/documentation/security/seckeyalgorithm) — DER X9.62 confirmation
- [Apple P256.Signing.ECDSASignature docs](https://developer.apple.com/documentation/cryptokit/p256/signing/ecdsasignature) — derRepresentation property
- [Apple openSettingsURLString docs](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring) — D-21 deep-link
- [Apple UIApplication notifications](https://developer.apple.com/documentation/uikit/uiapplication) — D-08 trigger names
- [Apple UINavigationItem.rightBarButtonItem](https://developer.apple.com/documentation/uikit/uinavigationitem/rightbarbuttonitem) — D-03 affordance
- [Apple modalPresentationStyle.fullScreen](https://developer.apple.com/documentation/uikit/uimodalpresentationstyle/fullscreen) — D-13 BiometricLockVC
- [Apple Streamline local authorization flows — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10108/) — single-prompt SE binding pattern
- [Apple Requesting Authorization for Location Services](https://developer.apple.com/documentation/corelocation/requesting-authorization-for-location-services) — Info.plist key
- Phase 2 RESEARCH.md (in repo) — SE two-key + biometryCurrentSet behavior
- Existing Phase 1+2 code (in repo) — SessionLockService, KeychainStore, APIClient, SecureEnclaveKeyStore, RoleCoordinator, MockURLProtocol, fixtures, SwiftLint rule shapes

### Secondary (MEDIUM confidence — verified against authoritative source)
- [SwiftLint custom rules docs](https://github.com/realm/SwiftLint#defining-custom-rules) — D-24 rule shape (cross-checked against existing `.swiftlint.yml`)
- [createwithswift Core Location async](https://www.createwithswift.com/updating-the-users-location-with-core-location-and-swift-concurrency-in-swiftui/) — continuation-bridge pattern
- [Hacking with Swift store continuations](https://www.hackingwithswift.com/quick-start/concurrency/how-to-store-continuations-to-be-resumed-later)
- [Carver Code: How to Detect a Change in Biometrics on iOS](https://carvercode.com/articles/how-to-detect-a-change-in-biometrics-on-ios/) — confirms canEvaluatePolicy populates domainState
- [Gridnev — Biometry-protected entries in iOS keychain](https://medium.com/@alx.gridnev/biometry-protected-entries-in-ios-keychain-6125e130e0d5) — `kSecUseAuthenticationContext` real-world usage
- [SwiftRocks: Detecting TouchID fingerprint changes](https://swiftrocks.com/detecting-touchid-fingerprint-changes)
- [Hacking with Swift Touch ID/Face ID](https://www.hackingwithswift.com/read/28/4/touch-to-activate-touch-id-face-id-and-localauthentication)

### Tertiary (LOW confidence — validation needed before locking)
- [HTTP.dev Retry-After expert guide](https://http.dev/retry-after) — header format examples (cross-verified with MDN)
- [MDN Retry-After](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Retry-After) — header format spec
- [DaveDeLong: HTTP in Swift, Part 12 Retrying](https://davedelong.com/blog/2020/07/23/http-in-swift-part-12-retrying/) — Swift implementation patterns

## Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| 1 | `evaluatedPolicyDomainState` returns nil unexpectedly on a fresh LAContext, breaking SESS-03 detection silently | MEDIUM | HIGH | BiometricService.currentDomainState() always calls `canEvaluatePolicy` first (Pattern 3); device test asserts non-nil after canEvaluate; HUMAN-UAT step in DeviceTests verifies actual re-enrollment behavior |
| 2 | Cold-boot probe race: SceneDelegate paints role shell BEFORE BiometricLockVC presents, briefly leaking content | MEDIUM | MEDIUM | Use Pitfall 5 mitigation — defer present to next runloop OR present from AppCoordinator init AFTER rootVC is wired; UI test asserts no visible role-shell text before biometric prompt |
| 3 | LogoutService notification post-before-async-completion race causes "logged out then logged back in" | LOW | HIGH | D-16 ordering: notification post is step 6, AFTER all other teardown is await-completed. LogoutServiceTests asserts ordering (notification observer fires only after Keychain is empty). |
| 4 | SwiftLint custom rule over-matches commented-out coordinate examples → blocks builds | LOW | LOW | Add `match_kinds: ["identifier", "typeidentifier"]` if testing reveals comment matches; planted-violation test confirms rule scope |
| 5 | Phase-2 SecureEnclaveKeyStore CR-02 idempotent guard not deployed before D-27 step 3+4 → first OTP-verify post-relogin produces a second SE key, breaking signing | HIGH (will happen if not fixed) | HIGH | D-25 includes CR-02 in Phase 3 scope as a Wave 0 prerequisite; planner orders the fix BEFORE any task that calls generateDeviceIdentityKeys for the second time |

## Metadata

**Confidence breakdown:**
- iOS APIs (LAContext, CLLocationManager, SecKey, URLSession header parsing, UIApplication notifications, UIKit nav-item): **HIGH** — every API is documented by Apple and most are exercised by existing Phase 1+2 code in this repo
- Architecture patterns (root-swap-with-fresh-AppContainer, single LogoutService funnel, AuthCoordinator): **HIGH** — patterns already locked by ADR 0002 + Phase 1+2 precedent
- Pitfalls (notification retain cycles, cold-boot race, geocode-network-failure semantics): **HIGH** — well-known iOS patterns; D-21 explicitly addresses the geocode failure
- AUTH-06 single-vs-double-prompt (D-11/D-12): **MEDIUM** — both options valid; researcher recommends Option A but D-12 says zero call sites in M1, deferring real consequence to M2
- Pre-Phase-3 carryover fixes (CR-02, IN-01/05, IN-02): **HIGH** — fixes are mechanical; tests assert exact wire format

**Research date:** 2026-04-21
**Valid until:** 2026-05-21 (30 days; iOS 17 SDK + locked CONTEXT decisions are stable surfaces)

## RESEARCH COMPLETE
