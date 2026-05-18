# Validation Ledger — iOS Client

## What This Is

Native iOS client (iPhone + iPad, iOS 17+) for Validation Ledger — a verified-identity freight platform that attacks fraud (double/triple brokering, chameleon carriers, factoring fraud) by making identity and the chain-of-trust between shippers, brokers, carriers, dispatch, and factoring parties verifiable in real time. The iOS app is where most verification happens physically — at the dock, in the cab, in the broker's office.

## Core Value

**Identity that cannot be spoofed and a chain-of-trust that cannot be faked.** Every design decision on iOS serves making the person and the counterparty on the other end of a freight transaction demonstrably real.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

**Validated in Phase 1: Foundational Conventions & Scaffolding (2026-04-21)**

- [x] UIKit-first module layout per TechStack.md §3.2 (`App/`, `Core/`, `Features/`, `UI/`, `Resources/`) replacing the SwiftUI scaffold — *AppDelegate + SceneDelegate + AppContainer + AppCoordinator landed*
- [x] iOS 17.0 deployment target, Xcode 16.4+ CI floor, Swift 5.9+, SwiftPM-only dependencies — *Package.swift pins Nuke 13.0.2 + SwiftLintPlugins 0.63.2 exactly*
- [x] MVVM + Coordinators pattern with initializer DI via a single `AppContainer` — *0 matches for `.shared` in App/; initializer DI throughout; ADR 0001 memory conventions*
- [x] Keychain-backed token storage scaffold — *hand-rolled KeychainStore + KeychainWiper (FOUND-02 first-launch wipe)*
- [x] Secure Enclave `KeyStoreProtocol` skeleton with SoftwareKeyStore simulator/test fallback — *Pitfall P8 simulator-only gate via `#if DEBUG && targetEnvironment(simulator)`; real keypair generation wiring lands in Phase 2 (SEC-01/DEV-01)*
- [x] Role-switched tab-bar shell for all 5 roles (Shipper, Broker, Carrier, Dispatch, Factoring) with placeholder tabs per TechStack.md §4 — *5 TabBarControllers + RoleCoordinator + ADR 0002 swap pattern*
- [x] Structured logging with PII scrubber in `Core/Logging/` using `os_log` / `OSLogStore` — *Logger protocol + OSLogLoggerImpl + PIIScrubber (6-category redaction, both structured + string paths after CR-02a fix); LogViewer in DevMenu (DEBUG-only per D-13)*
- [x] SessionLockService single source of truth scaffold (FOUND-07) — *`DefaultSessionLockService` with NSLock guarding; cold-boot / background-timeout / explicit-logout triggers all route through it*
- [x] DeepLinkRouter pre-bootstrap queue (FOUND-08)
- [x] SwiftLint with 4 custom rules (ban_print, ban_direct_os_log, ban_userdefaults_tokens, no_cross_feature_import) enforced via pre-commit hook + CI
- [x] Two CI pipelines (simulator on PR, device on merge-to-main) with 77.43% Core/ coverage gate (CI-01/CI-02/CI-04)
- [x] PrivacyInfo.xcprivacy in Copy Bundle Resources (FOUND-06)
- [x] ATS-strict Info.plist, zero `NSAllowsArbitraryLoads` (SEC-02)

**Validated in Phase 2: Networking Contract & Device Keys (2026-04-21)**

- [x] Contract-first networking: 7 typed M1 endpoint structs + APIClient facade + MockURLProtocol with 14 success/failure fixtures (NET-01, NET-02) — 14 `APIClientEndpointTests` pass
- [x] `AppContainer.makeSession(networkConfig:)` one-line mock ↔ live swap + DevMenu toggle (NET-03) — 4 `AppContainerNetworkConfigTests` pass
- [x] IdempotencyInterceptor injects UUID `Idempotency-Key` on POST/PUT/PATCH/DELETE; respects caller-supplied keys for Phase 5 replay (NET-04) — 5 tests
- [x] RetryInterceptor GET-only with jittered exponential backoff; 0 retries on POST/PUT/DELETE; max 3; handles 5xx + 5 URLError cases (NET-05) — 9 tests
- [x] Dual-pin SPKI certificate pinning with compile-time `PinnedSPKIs` constants, `SPKIHasher` (26-byte EC P-256 ASN.1 + SHA-256), `PinningSessionDelegate` single-completion invariant across all 5 return paths, 3-cert integration test (SEC-01) — 13 tests; `docs/cert-rotation.md` fully fleshed to 30-day runbook
- [x] Secure Enclave two-key pattern: `deviceKey` (`.devicePasscode` ACL) + `authorizationKey` (`.biometryCurrentSet` ACL) via `SecKeyCreateRandomKey` + `SecAccessControlCreateWithFlags` (NOT CryptoKit wrapper — lacks `.biometryCurrentSet` support) (DEV-01, DEV-02) — ADR 0004 locks design
- [x] SoftwareKeyStore simulator fallback via `#if DEBUG && targetEnvironment(simulator)` (DEV-03) — 4 extended tests + `AppContainer.preflightSecureEnclave()` + `RefuseLaunchWithoutSecureEnclaveTests` (5 tests in device target; Release refuses launch when SecureEnclave.isAvailable == false)
- [x] DeviceFingerprint (model, iOS version, install UUID Keychain-persisted) for `/device/register` payloads (DEV-05) — 4 tests
- [x] Phase 1 carryovers closed: CR-01 NetworkClient force-cast → guard + `NetworkError.unexpectedResponseType`; WR-01 `MockURLProtocol.handlers` now NSLock-guarded with `.serialized @Suite` pattern
- [x] ci-simulator.yml propagates `-parallel-testing-enabled NO` (sibling Swift Testing @Suite's defeat `.serialized` otherwise when sharing MockURLProtocol global state)
- [x] 90 unit tests + 5 UI tests across 17 suites pass; 76.82% Core/ coverage (> 70% gate)
- [x] Release binary D-13 proof preserved: 0 matches for `DevMenu|LogViewer|RoleSwitcher|KeychainInspector|NetworkConfigToggle` in `strings` dump

**Validated in Phase 5: KYC Capture & Upload Pipeline (2026-05-17)**

- [x] KYC capture flow — `KYCCoordinator` orchestrates face → DL front/back → vehicle/trailer/plate → review → submit; 6 UIKit capture screens + Use/Retake preview + read-only DL extraction; Vision face-quality gate + DataScanner DL OCR (KYC-01..04)
- [x] GPS EXIF injection at capture via `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination` (never `UIImage`); `GeoContext` <30s/<100m freshness gate — `KYCGPSUploadPayloadIntegrationTests` proves GPS survives into the upload chunk payload (KYC-04 / SC-1)
- [x] Resumable chunked upload pipeline — `KYCUploader` actor: 512KB-default chunks, disk-persisted `chunksAcked` resume cursor, 5-attempt jittered backoff, per-chunk idempotency keys (no duplicate commits), `BGProcessingTaskRequest` background continuation (UPL-01..05)
- [x] Encrypted on-disk `KYCSessionStore` (`NSFileProtectionComplete`) survives backgrounding and logout (D-02); 4-state KYC status UI (Pending/Under Review/Verified/Rejected) with controlled-vocabulary rejection copy; Profile-tab status entry point (KYC-05, KYC-06)
- [ ] 4 physical-device HUMAN-UAT items pending (`05-HUMAN-UAT.md`): SC-2 force-quit resume UX, SC-4 background-upload completion, D-08 Profile entry, D-12 hard gate — run `/gsd-verify-work 5` after on-device testing

**Validated in Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification (2026-05-18)**

- [x] App Attest fires at first login (DEV-04 / Phase 4 SC-1) — `OTPViewModel.verify()` STEP 5 orchestrates `generateKeyIfNeeded() → GET /device/challenge → attestKey() → POST /device/register`; the hardcoded `attestationStatus: .unsupported` is gone. Graceful-skip, degrade-and-continue, and `challengeExpired` refetch-and-retry-once postures all implemented (D6-04..D6-07)
- [x] trustTier producer→Keychain→consumer wiring — `OTPViewModel` captures the `/device/register` response and persists `trustTier` via `AttestedKeyStore.writeTrustTier`; `AppContainer` seeds `AppSession.trustTier` from the `device.trustTier` Keychain item; observable banner re-render (D6-10); `uiTestTrustTierOverride` test seam deleted (D6-03). Closes the cross-phase wiring break the milestone audit found
- [x] Retroactive `04-VERIFICATION.md` (CI-03 verification half) — full Phase 4 re-verification (3 SC + DEV-04 + CI-03, score 3/3); closes Critical Gap #1 from the v1.0 milestone audit
- [ ] 3 physical-device HUMAN-UAT items pending (`06-HUMAN-UAT.md`): banner mid-session re-render, Profile-entry KYC "Continue" CTA, 5 carried Phase 4 banner UAT items — run `/gsd-verify-work 6` after on-device testing

### Active

<!-- Milestone 1 ("Foundation") scope. Hypotheses until shipped + validated on real users. -->

**Validated in Phase 3: OTP Auth + Role Shell + Session (2026-04-22)**

- [x] Phone + SMS OTP auth shim against mock backend (AUTH-01..06) — AuthCoordinator + PhoneEntry/OTP VCs + VMs, 3-attempt 60s rate-limit, Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` token storage, 401 auto-logout, SensitiveActionService WWDC22 single-prompt
- [x] Session persistence across cold boot + clean logout + >5min background → biometric re-prompt (SESS-01..04) — SessionLockService 4-branch lockState state machine (.coldBoot / .backgroundTimeout / .biometricReEnrolled / .neverUnlocked), SceneDelegate presents BiometricLockViewController on cold-boot .role transition + didBecomeActiveNotification observer (plan 03-13 gap closure), LogoutService funnel posts .sessionDidInvalidate. 4 physical-device HUMAN-UAT items pending.
- [x] 5-role tab-bar shell with distinct tabs per TechStack.md §4 (SHELL-01..04) — RoleCoordinator role-switched roots, 5 role UI smoke tests (plan 03-12) green
- [x] Client-side country pre-check via `CLLocationManager` (GEO-01..03) — LocationProvider + CountryGate + NSLocationWhenInUseUsageDescription + SwiftLint `ban_raw_coordinate_literal` + phantom-typed `AnalyticsEvent` making raw coordinates a compile error
- [x] "Another active session" switch-device placeholder (DEV-06) — AnotherActiveSessionViewController + LogoutReason.anotherActiveSession routing

### Active

**Phase 4 target (Attestation + Device CI Hardening)** — ✅ DEV-04 + CI-03 closed via the Phase 6 gap-closure 2026-05-18 (see "Validated in Phase 6" above)
- [x] App Attest productionization (DEV-04) — wired into the first-login path in Phase 6 (`OTPViewModel` STEP 5)
- [x] Physical-device CI runs SecureEnclave + Keychain biometric + App Attest paths on every merge (CI-03) — pipeline shipped in Phase 4; the missing retroactive `04-VERIFICATION.md` was produced in Phase 6

**Phase 5 target (KYC Capture + Upload)** — ✅ validated 2026-05-17 (see "Validated in Phase 5" above). Device-UAT automation gap-closure completed 2026-05-18 (plans 05-11/12/13): 4 of the 5 device-UAT items are now automated as device XCUITests on the `ci-device.yml` lane (verified 4/4 on hardware); 2 genuinely-manual items remain in `05-HUMAN-UAT.md` (SC-4 background upload, Test-10 camera-fault injection)

**Pre-Phase-3 required fixes — resolved in Phase 3 plan 03-02 (2026-04-22):**
- [x] **CR-02 (Phase 2 review)**: `SecureEnclaveKeyStore.generateKey(slot:)` idempotent guard landed
- [x] **IN-01/05 (Phase 2 review)**: Explicit CodingKeys added for `otpSessionID`, `uploadID` x2, `installUUID`
- [x] **IN-02 (Phase 2 review)**: DER X9.62 unification across SoftwareKeyStore (sim) and SecureEnclaveKeyStore (device)

**Follow-up items still open (non-blocking, may fix during Phase 3 or via `/gsd-code-review-fix`):**
- [ ] CR-02b (Phase 1): PIIScrubber DL regex over-eager (matches transaction IDs like `TX1234567`) — narrow to validated US state codes
- [ ] CR-03 (Phase 1): DevMenu `Row(rawValue: indexPath.row)!` force-unwrap — DEBUG-only; trivial fix
- [ ] CR-03 (Phase 2): SceneDelegate NotificationCenter silent-fail cast + missing `@MainActor` annotation on mutable property — Swift 6 concurrency hygiene
- [ ] CR-04 (Phase 2): `noReleasePlaceholders` test gated `#if !DEBUG` but CI only runs DEBUG — no CI enforcement that PHASE2-TODO SPKI values don't ship. Convert to a script-based grep gate in ci-simulator.yml OR add a Release-config CI job.
- [ ] WR-02 (Phase 2): `DeviceFingerprint.resolveInstallUUID` silently swallows Keychain errors via `try?` — before-first-unlock window can regenerate install UUID on every launch; backend sees "new device"
- [ ] WR-03 (Phase 1): `DeepLinkRouter.bootstrapComplete()` post-unlock routing race — narrow window; revisit during Phase 3 deep-link integration
- [ ] WR-06 (Phase 2): Xcode 16.4 CI pin vs TechStack.md 26.4 — version skew
- [ ] IN-02 (Phase 2): SoftwareKeyStore (sim) returns 64-byte compact ECDSA; SecureEnclaveKeyStore (device) returns DER X9.62 — backend receives different wire-format bytes sim vs device. Pick one format at the protocol level.
- [ ] 8 HUMAN-UAT items from Phase 1 (`01-HUMAN-UAT.md`) + 3 HUMAN-UAT items from Phase 2 (`02-HUMAN-UAT.md`) — run `/gsd-verify-work 1` and `/gsd-verify-work 2` when device CI / simulator access is available

**M1 Foundation — subsequent phases (post-Phase 1)**

- [ ] FR-iOS-KYC capture: live face, DL front+back, vehicle/trailer/plate photos with GPS metadata (liveness detection deferred from M1)
- [ ] Resumable upload pipeline with retry + exponential backoff + visible progress
- [ ] KYC status UI: Pending / Under Review / Verified / Rejected with rejection reasons
- [ ] App Attest / DeviceCheck attestation on login
- [ ] FR-iOS-GEO client-side country check + location permission UX (no impossible-travel pre-check on client — moved to SHOULD)
- [ ] Certificate pinning + strict ATS (FR-iOS-SEC)
- [ ] Jailbreak + Secure Enclave availability detection; refuse production login if Secure Enclave unavailable

**Future milestones (M2–M5)**

- [ ] M2: Role-based Load list/detail, chain-of-trust visualization, tender/accept/reject, real-time updates (WS or SSE)
- [ ] M3: eBOL rendering, rotating live QR (30s TTL), QR scanner, push notifications with deep links, screenshot blocking
- [ ] M4: Claude Sonnet 4.5 assistant UI (backend-mediated), offline mode, accessibility pass, analytics instrumentation
- [ ] M5: Crash-rate tuning, device matrix QA, TestFlight closed beta launch, App Store submission prep

### Out of Scope

<!-- Explicit boundaries. -->

**For the entire iOS v1:**

- Android client — separate effort, separate codebase
- Web client — separate effort, shared backend
- Admin console — web, not iOS
- Offline QR verification — fraud window too large
- Passkey / WebAuthn migration — v2
- Non-English localization — v2 (string catalog structured for it)
- Apple Watch, CarPlay, iMessage extension — out of v1

**For M1 Foundation specifically (deferred, not dropped):**

- Liveness detection on KYC capture — defer to later milestone; M1 KYC captures artifacts without liveness checks. Revisit after M1 internal testing reveals false-reject tolerance.
- Crash/analytics vendor pick (Sentry vs. Firebase Crashlytics vs. self-hosted) — deferred to M2 per §12 Open Q7. M1 uses `os_log` + `OSLogStore` only.
- Impossible-travel pre-check on client (FR-iOS-GEO MUST) — downgraded to SHOULD; backend enforces.
- Real backend integration — the iOS milestone works against contract-first JSON stubs. Backend gets its own `/gsd-new-project` later; M2 onward integrates.

**Out of this GSD project entirely:**

- Backend platform (Go/Python service, data schema, API implementation, FMCSA integration) — separate GSD initialization
- Anthropic/Claude direct calls from iOS — all AI traffic is backend-mediated per FR-iOS-AI; this iOS project contains only the assistant client that talks to the backend

## Context

**Product context:**
Validation Ledger exists because the trucking industry loses billions annually to identity fraud — brokers accepting loads with forged MC numbers, carriers with chameleon histories, factoring companies paying out on double-brokered shipments. Existing TMS platforms trust self-reported identity. Validation Ledger's premise is that every party on a load is identity-verified with device-bound keys, and every counterparty relationship is visible as a verifiable chain-of-trust.

**Companion document:**
TechStack.md (in repo root) is the iOS client's detailed technical spec — 13 sections covering stack, architecture, five roles, eleven FR groups (auth/KYC/device/geo/security/load/BOL/scanner/AI/notifications/offline), non-functional targets, milestones M1–M5, out-of-scope, and open questions. This PROJECT.md is the GSD-managed derivative; when they disagree, TechStack.md wins for product-level questions and PROJECT.md wins for scope currently in play.

**Codebase state (as of 2026-04-21, Phase 2 complete):**
Phase 1 baseline stable (UIKit scaffold + Core services + SwiftLint + CI). Phase 2 adds: full contract-first networking stack — 7 typed M1 endpoint structs (`APIEndpoint` protocol) + `APIClient` facade + MockURLProtocol fixture registry (14 JSON fixtures, NSLock-guarded, `.serialized` Swift Testing pattern) + IdempotencyInterceptor (POST/PUT/PATCH/DELETE) + RetryInterceptor (GET-only, jittered exponential backoff) + dual-pin SPKI certificate pinning (`PinnedSPKIs` compile-time constants + `SPKIHasher` 26-byte EC P-256 ASN.1 + `PinningSessionDelegate` single-completion invariant) + `docs/cert-rotation.md` full 30-day runbook. Secure Enclave two-key pattern (`SecKeyCreateRandomKey` + `SecAccessControlCreateWithFlags`, NOT CryptoKit wrapper — the wrapper lacks `.biometryCurrentSet` support). `deviceKey` (`.devicePasscode`) + `authorizationKey` (`.biometryCurrentSet`), ADR 0004. `SoftwareKeyStore` simulator parity. `DeviceFingerprint` (model + iOS version + Keychain-persisted install UUID). `AppContainer.makeSession(networkConfig:)` one-line .mock/.live swap with `PinningSessionDelegate` installed ONLY on `.live` branch. `Environment.release` runtime-enforces non-nil apiBaseURL. DEBUG-only `NetworkConfigToggleViewController` in DevMenu. `RefuseLaunchWithoutSecureEnclaveTests` in device target. ci-simulator.yml propagates `-parallel-testing-enabled NO`. 90 unit tests + 5 UI tests across 17 suites green; 76.82% Core/ coverage. Phase 3 (OTP Auth + Role Shell + Session) is next — the fixed Phase 1 user-visible win.

**Team context:**
1–2 iOS engineers using AI coding tools, targeting 6-month closed-beta (M1–M5). Backend is built in parallel in a separate codebase; iOS does not wait on it — contract-first JSON stubs keep the client unblocked.

## Constraints

- **Tech stack**: UIKit-first (SwiftUI permitted only for non-critical surfaces like Settings/static lists); all camera/KYC/scanner/BOL screens must be UIKit — Rationale: mature for sensitive-surface interaction, no SwiftUI rendering quirks on camera layers, the team's UIKit fluency.
- **Tech stack**: Swift Package Manager only — no CocoaPods, no Carthage. Rationale: shallow dependency graph, avoids the tooling split.
- **Platform**: iOS 17.0 minimum deployment — Rationale: spec requirement; enables modern Vision APIs, UIKit updates, Swift Concurrency without backports.
- **Devices**: iPhone + iPad, iPad must render natively (not just scale) — Rationale: dispatch and factoring users frequently work on iPad.
- **Security**: Zero PII in analytics or crash logs; all tokens in Keychain; all keys in Secure Enclave; no sensitive data in `UserDefaults` — Rationale: product's entire premise is trust — a security shortcut invalidates the platform.
- **Distribution**: TestFlight closed beta for v1; App Store submission is M5 — Rationale: spec-defined milestone.
- **Dependencies**: Pre-approved shortlist only (URLSession wrapper, KeychainAccess or hand-rolled, Nuke/SDWebImage for images, Sentry/Firebase for crash — TBD, CoreImage for QR generation, AVFoundation for scanning, Apple Vision for liveness). Anything outside this list requires explicit approval.
- **AI traffic**: iOS never calls Anthropic directly; all Claude assistant calls go through backend-mediated endpoints — Rationale: keeps authorization, grounding, and tool-use server-enforced.
- **Geographic**: US-only logins enforced by backend; iOS performs a client-side country pre-check via `CLLocationManager` — Rationale: regulatory scope and fraud-profile control.
- **Timeline**: M1 target is weeks 1–4 of a 24-week v1 plan — Rationale: spec §10. If engineers commit to the full M1 in <3 months, revisit scope assumptions.
- **Team size**: 1–2 iOS engineers + AI coding tools — Rationale: dictates architectural simplicity (MVVM+Coordinators over TCA, initializer DI over Swinject).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Treat TechStack.md as the authoritative v1 iOS spec, refined through GSD | User wrote a detailed spec before GSD init; forcing a rewrite wastes context | ✓ Good |
| Initialize GSD against M1 Foundation only; remaining milestones live in TechStack.md §10 until their time | M1 is "project skeleton through KYC capture"; keeps the roadmap right-sized for a 4-week milestone | — Pending |
| Rebuild the SwiftUI Xcode scaffold as UIKit in Phase 1 | Spec mandates UIKit-first for sensitive surfaces; scaffold was Xcode's default, not a design choice | — Pending |
| Lower deployment target from iOS 26.4 (scaffold default) to iOS 17.0 | Spec-defined minimum; iOS 26.4 is not a real customer target | — Pending |
| Phase 1 goal: OTP auth + role-switched tab shell + persistent session + logout, all 5 roles with placeholder tabs | Leanest slice that exercises UIKit module layout, auth shim, Keychain, Secure Enclave, role-based nav, and the mock networking layer | — Pending |
| Backend planning lives in a separate `/gsd-new-project`; iOS uses contract-first JSON stubs via URLProtocol for M1 | User is building backend too but wants iOS unblocked. Contract-first model means no refactor when live backend lands | — Pending |
| All five roles ship in M1 with minimal placeholder UI | Validates the role-switching architecture at the shell level before features multiply | — Pending |
| Defer liveness detection entirely from M1 KYC | §12 Open Q1 parked until M1 reveals the false-reject tolerance of Vision-only approaches | — Pending |
| Defer crash/analytics vendor pick to M2; M1 uses `os_log` + `OSLogStore` | §12 Open Q7; don't add SDK weight before real failure data shows what to instrument | — Pending |
| Downgrade FR-iOS-GEO impossible-travel pre-check from MUST to SHOULD on client | Expensive to build correctly, backend enforces it anyway; not worth the M1 cycles | — Pending |
| Keep MVVM + Coordinators; keep spec's dependency shortlist as-written | Matches team size + spec defaults; no evidence yet to override | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-18 after Phase 6 — DEV-04 App Attest first-login wiring + trustTier consumer + retroactive 04-VERIFICATION.md (plans 06-01..04)*
