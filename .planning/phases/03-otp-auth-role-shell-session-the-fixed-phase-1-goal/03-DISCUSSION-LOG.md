# Phase 3: OTP Auth + Role Shell + Session — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `03-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-04-21
**Phase:** 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
**Areas discussed:** Auth flow + Profile placement + cold-boot restore; SessionLockService Phase 3 extension + AUTH-06 infra; Biometric host UX + Logout/DEV-06 teardown contract; Geo pre-check UX + GEO-03 phantom-typed AnalyticsEvent

---

## Auth flow + Profile placement + cold-boot restore

### Q1 — How should the OTP flow be wired structurally?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated AuthCoordinator in Features/Onboarding/Auth/ | New AuthCoordinator owns a UINavigationController with PhoneEntryViewController → OTPViewController → onAuthenticated(role) callback. Mirrors planned KYCCoordinator + Roles/RoleCoordinator symmetry. | ✓ |
| Thin VCs orchestrated directly by AppCoordinator | AppCoordinator pushes phone-entry then OTP VCs onto its own UINavigationController. Less ceremony but mixes auth concerns into AppCoordinator. | |
| PhoneEntry/OTP as VMs hung off SceneDelegate | SceneDelegate constructs the auth VCs directly. Smallest surface but breaks ARCH-04/D-10 fresh-AppContainer-per-phase invariant. | |

**User's choice:** Dedicated AuthCoordinator in Features/Onboarding/Auth/

---

### Q2 — Profile + logout placement (Phase 1 deferred to here)

| Option | Description | Selected |
|--------|-------------|----------|
| Top-bar avatar affordance (no extra tab) | UINavigationItem.rightBarButtonItem on every role's TabBar; tap presents modal ProfileViewController with logout button. Preserves TechStack.md §4 verbatim. | ✓ |
| Add Profile as 5th tab to each role | Append Profile tab (person.crop.circle SF Symbol) to all 5 TabBarControllers. Trivially discoverable but changes §4 inventory. | |
| Assistant tab hosts a Profile sub-surface | Assistant tab gets Profile section. Conflates AI assistant with account management — confusing once M4 Assistant becomes real Claude UI. | |

**User's choice:** Top-bar avatar affordance (no extra tab) — preserves TechStack.md §4 verbatim

---

### Q3 — Cold-boot session restore probe location + "valid" definition

| Option | Description | Selected |
|--------|-------------|----------|
| SceneDelegate runs SessionRestoreService.probe() before first presentRoot | "valid" = sessionToken + role both present in Keychain. No JWT exp parse, no /auth/me round-trip. Backend's first call returns 401 if stale → AUTH-05 fires. | ✓ |
| AppCoordinator probes in init, posts callback to SceneDelegate | Couples auth state to AppCoordinator; means SceneDelegate constructs THEN swaps — one extra root-swap per cold-boot. | |
| Probe + JWT exp + /auth/me round-trip before any UI | Blocks first paint by network round-trip; needs new endpoint + fixture. Defer to M2 — backend doesn't exist yet. | |

**User's choice:** SceneDelegate runs SessionRestoreService.probe() before first presentRoot

---

### Q4 — AUTH-02 rate-limit countdown surface

| Option | Description | Selected |
|--------|-------------|----------|
| Backend returns 429 with Retry-After header; OTPViewModel renders countdown Timer | APIClient parses Retry-After into NetworkError.rateLimited(retryAfter:). 1-Hz Timer countdown + disabled Verify button. New fixture otp-verify-rate-limited.json. | ✓ |
| Backend returns 429 with retryAfterSeconds in JSON body | Easier mock/parse but less HTTP-spec; backend has to commit body-format. | |
| iOS counts failures locally + enforces 60s without backend signal | Violates AUTH-02 "backend-enforced" — process restart resets counter. | |

**User's choice:** Backend returns 429 with Retry-After header; OTPViewModel renders countdown Timer

---

## SessionLockService Phase 3 extension + AUTH-06 infra

### Q1 — Distinguishing cold-boot vs >5min vs re-enrolled in the lock API

| Option | Description | Selected |
|--------|-------------|----------|
| Single bool stays + add LockReason enum returned alongside | lockState(now:) -> LockState where LockState = .unlocked \| .locked(reason: LockReason) and LockReason = .coldBoot \| .backgroundTimeout \| .biometricReEnrolled \| .neverUnlocked. | ✓ |
| Single bool stays + separate properties for each trigger | shouldRequireBiometric + isColdBoot + didDetectReEnrollment props. More state to keep in sync. | |
| Three separate methods, one per trigger | shouldRequireBiometricForColdBoot, ForBackgroundReturn, ForReEnrollment. Verbose; out-of-sync risk. | |

**User's choice:** Single bool stays + add LockReason enum returned alongside

---

### Q2 — Who owns UIApplication.didEnterBackground/didBecomeActive observation?

| Option | Description | Selected |
|--------|-------------|----------|
| SessionLockService self-subscribes in init | Takes NotificationCenter dep, holds tokens, removes in deinit. SessionLockService gains UIKit import. | ✓ |
| SceneDelegate observes + calls into SessionLockService | SceneDelegate becomes busier orchestrator; SessionLockService stays UIKit-free. | |
| AppCoordinator owns + delegates to SessionLockService | AppCoordinator is recreated on every root-swap (D-10) → observer registration churns. | |

**User's choice:** SessionLockService self-subscribes in init

---

### Q3 — Biometric re-enrollment detection (SESS-03)

| Option | Description | Selected |
|--------|-------------|----------|
| LAContext.evaluatedPolicyDomainState diff (Apple's canonical approach) | Persist domainState in Keychain after each biometric success; compare on lock check. Fast, Apple-documented. | ✓ |
| Probe authorizationKey access; catch errSecAuthFailed/errSecInteractionNotAllowed | Ground truth but slower (SE round-trip); error code can also fire on user-denied → disambiguation needed. | |
| Both — LAContext probe as fast path, SE probe as confirmation | Belt + suspenders; prevents false-positive re-bind prompts. Slightly more code; safer. | |

**User's choice:** LAContext.evaluatedPolicyDomainState diff (Apple's canonical approach)

---

### Q4 — AUTH-06 sensitive-action infrastructure surface

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated SensitiveActionService in Core/Auth/ | authorize(payload:reason:) async throws -> Signature. Calls KeyStore.sign(slot:.authorization,...) which auto-prompts biometric via SE ACL. M1: zero call sites. | ✓ |
| Method on SessionLockService | Conflates "should I show a lock screen" with "should this user sign this tender". Awkward. | |
| Stub protocol only, defer concrete impl to M2 | Lightest M1 touch but no runtime wiring proof. Skip. | |

**User's choice:** Dedicated SensitiveActionService in Core/Auth/

---

## Biometric host UX + Logout/DEV-06 teardown contract

### Q1 — Biometric host UX pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Full-screen BiometricLockViewController (dedicated VC overlaid modally) | Different copy per LockReason. Content never visible behind it. Meets SC-2 unambiguously. | ✓ |
| Blurred overlay on top of the role shell | UIVisualEffectView overlay. Content laid out + accessible to screenshot — slight SC-2 exposure. | |
| Black screen + immediate LAContext prompt, no host VC | Minimal UX but retry / re-enrollment-copy UI is awkward. | |

**User's choice:** Full-screen BiometricLockViewController (dedicated VC overlaid modally)

---

### Q2 — Fail/cancel behavior on session-unlock LAContext path

| Option | Description | Selected |
|--------|-------------|----------|
| Retry indefinitely; no lockout on session unlock | iOS-system biometric lockout (5 system failures → passcode) is the only limit. | |
| Biometric with device-passcode fallback (.deviceOwnerAuthentication) | Auto-falls-back to device passcode after biometric failures. Sensitive actions stay strict biometric via SE ACL. | ✓ |
| 3 failed attempts → force logout | Could log user out from accidental triggers. Skip. | |

**User's choice:** Biometric with device-passcode fallback (.deviceOwnerAuthentication)

---

### Q3 — Logout teardown orchestration owner

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated LogoutService in Core/Auth/ (single source of truth) | logout(reason:) orchestrates: in-memory wipe → Keychain wipe → SE ACL clear → domainState clear → sessionLock.invalidate → notification. SceneDelegate observes → routing. | ✓ |
| AuthCoordinator.logout() with shared private helpers | Couples logout to a Feature coordinator that may not exist when trigger fires (e.g., 401 from deep link). | |
| Inline at each call site | Three places to bug-fix when teardown order changes. | |

**User's choice:** Dedicated LogoutService in Core/Auth/ (single source of truth)

---

### Q4 — DEV-06 routing (logout + show "another active session" placeholder)

| Option | Description | Selected |
|--------|-------------|----------|
| Extend AppPhase: add .anotherActiveSession; LogoutReason drives the route | SceneDelegate's .sessionDidInvalidate observer reads reason from userInfo; maps to .auth or .anotherActiveSession. New AnotherActiveSessionViewController. | ✓ |
| Notification carries the destination VC factory closure | Maximally flexible but untyped — invariants like "no cycles back to logged-in screen" not enforced. | |
| DEV-06 handler routes itself, doesn't go through LogoutService notification | Sidesteps the notification; breaks symmetry across logout triggers. | |

**User's choice:** Extend AppPhase: add .anotherActiveSession; LogoutReason drives the route

---

## Geo pre-check UX + GEO-03 phantom-typed AnalyticsEvent

### Q1 — When does CLLocationManager fire in the OTP flow?

| Option | Description | Selected |
|--------|-------------|----------|
| At phone-entry screen Submit tap, BEFORE POST /auth/otp/request | Reverse-geocode + country check before POST. Matches GEO-02 "refuse to SUBMIT auth attempt if country ≠ US" verbatim. | ✓ |
| At OTP-verify Submit tap, BEFORE POST /auth/otp/verify | OTP SMS already sent — wastes a backend send for non-US users. | |
| At app launch, before any auth UI | Violates GEO-01 ("not at app launch") verbatim. | |

**User's choice:** At phone-entry screen Submit tap, BEFORE POST /auth/otp/request

---

### Q2 — Permission-denied UX

| Option | Description | Selected |
|--------|-------------|----------|
| Block: "Location required for US-only verification" screen with "Open Settings" deep-link | Submit stays disabled until permission granted. Matches GEO-02 refuse-to-submit. | ✓ |
| Allow submit with null coords; let backend reject | Wastes round-trip; misleading error message. | |
| Proceed without location pre-check entirely; rely on backend IP-geo | Violates GEO-02 MUST. | |

**User's choice:** Block: "Location required for US-only verification" screen with "Open Settings" deep-link

---

### Q3 — Country ≠ US refusal pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated NotAvailableInRegionViewController (terminal screen) | Pushed onto auth nav. "Learn more" + "Try again" buttons. Terminal — user can't accidentally retry via Submit. | ✓ |
| UIAlertController with "OK" that returns to phone-entry | Cycle problem if location stuck on Canada. | |
| Inline error label on phone-entry screen, Submit re-enabled | Looks like phone-format error. Confusing copy hierarchy. | |

**User's choice:** Dedicated NotAvailableInRegionViewController (terminal screen)

---

### Q4 — GEO-03 phantom-typed AnalyticsEvent type design

| Option | Description | Selected |
|--------|-------------|----------|
| Two disjoint type families: AnalyticsField (no coord case) + PlatformPayloadField (the only carrier of CLLocationCoordinate2D) | AnalyticsField has no .coordinate case — passing a coord to log/analytics is a compile error. SwiftLint rule bans CLLocationCoordinate2D(latitude: outside Endpoints/Geo/tests. | ✓ |
| Phantom-tagged Coordinate<Tag> wrapper | struct Coordinate<Tag> with PlatformAPI / AnalyticsAllowed phantom tags. Maximally clever; harder for AI tools to bypass. | |
| Runtime guard + SwiftLint rule, no compile-time enforcement | Violates GEO-03 wording ("makes raw coordinates un-attachable AT COMPILE TIME"). | |

**User's choice:** Two disjoint type families: AnalyticsField (no coord case) + PlatformPayloadField (the only carrier of CLLocationCoordinate2D)

---

## Claude's Discretion

Areas not asked about — captured as defaults in CONTEXT.md `<decisions>` D-26..D-33; planner confirms or adjusts:

- D-26 Phone-entry input UX (US-only +1 lock; phonePad keyboard; (XXX) XXX-XXXX display formatting; submit enabled when 10 digits entered)
- D-27 /device/register orchestration timing (sequential after OTP-verify, before role-shell present, on a "Setting up your account..." progress screen)
- D-28 AUTH-05 401 interceptor wiring (new Auth401ResponseInterceptor; excludes /auth/otp/* paths)
- D-29 lastSuccess persistence (in-memory only; cold-boot intentionally re-prompts)
- D-30 LogoutReason exact values (.userInitiated, .auth401, .anotherActiveSession — String raw values)
- D-31 Thread/actor model for LAContext (MainActor-bound services; UI state lands on main)
- D-32 CI-02 placeholder smoke tests upgraded to real (5 UI tests, one per role, via -MockOTPRoleForUITest launchArg)
- D-33 Cached role/userID Keychain keys (session.role, session.userID; KeychainStore.deleteAll(under:) API added)

## Deferred Ideas

None routed to other phases during this discussion. The two longest-running deferrals from Phase 1 (Profile tab placement; GEO-03 phantom-typed AnalyticsEvent) were both resolved here.
