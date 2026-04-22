# Roadmap: Validation Ledger iOS Client — M1 Foundation

## Overview

M1 Foundation is the 4-week milestone that takes the app from "Xcode SwiftUI template scaffold" to "all five roles can OTP-login, see a role-distinct tab shell, cold-boot into a persisted session, cleanly log out, and complete KYC capture with a resumable upload." The 8 foundational conventions (FOUND-01..08) land in Phase 1 — retrofitting them later costs exponentially more. Networking + Secure Enclave device binding land in Phase 2 so Phase 3's OTP-auth flow composes them cleanly. Phase 3 delivers the fixed visible win: the five-role shell with session persistence and logout. Phase 4 adds App Attest and physical-device CI once the security surfaces exist to exercise them. Phase 5 builds KYC capture and the resumable upload pipeline on top of the mature foundation.

Phase ordering follows `.planning/research/ARCHITECTURE.md` "Build order for M1 Foundation" literally (App/ skeleton → UI/ tokens → Core/Logging → Core/Storage/Keychain → Core/KeyStore → Core/Networking → Core/Auth → AuthCoordinator → RoleCoordinator → SessionLockService → Core/Identity → production PII rules). The one deviation: App Attest (DEV-04) is split from Phase 3 into its own small Phase 4 alongside physical-device CI (CI-03) because both are infrastructure hardening that shouldn't block the Phase 3 visible-win demo if Apple App Attest rate limits bite during testing.

## Infrastructure Tax Budget (30%)

Per `.planning/research/PITFALLS.md` Pitfall 20 + research/SUMMARY.md: **~30% of M1 engineering time goes to infrastructure** (CI sim/device split, SwiftLint custom rules, PII scrubber middleware, PrivacyInfo.xcprivacy skeleton, cert-rotation runbook, MVVM-C memory-conventions ADR, error-mapping boilerplate, hand-rolled Keychain wrapper, MockURLProtocol fixtures). This is not reflected in TechStack.md §10's 4-week estimate. Phase 1 absorbs most of it; expect it to compound into Phase 2 and Phase 3. If Phase 1 is behind at week 2, defer DEV-04 (App Attest) and GEO-02 (country pre-check) into Phase 4 and push KYC/UPL into a hypothetical M1.5 rather than cutting FOUND-* or ARCH-* corners.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned M1 Foundation work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Foundational Conventions & Scaffolding** - UIKit module layout + 8 conventions + tooling + logging + Keychain + sim CI *(completed 2026-04-21, 8 HUMAN-UAT items pending)*
- [x] **Phase 2: Networking Contract & Device Keys** - Contract-first mock networking + cert pinning + Secure Enclave keypair + token storage *(completed 2026-04-21, 3 HUMAN-UAT items pending)*
- [x] **Phase 3: OTP Auth + Role Shell + Session** - The fixed Phase 1 goal: 5 roles OTP-login to distinct tab shells, cold-boot into persisted session, clean logout *(completed 2026-04-22, 4 HUMAN-UAT items pending physical-device test)*
- [ ] **Phase 4: App Attest & Physical-Device CI Hardening** - App Attest productionization + on-device CI pipeline for Secure Enclave / Keychain biometric / App Attest paths
- [ ] **Phase 5: KYC Capture & Upload Pipeline** - Live face + DL + vehicle capture with GPS metadata, resumable chunked upload, KYC status UI

## Phase Details

### Phase 1: Foundational Conventions & Scaffolding
**Goal**: Rebuild the Xcode SwiftUI scaffold as the UIKit module layout specified in TechStack.md §3.2 (with ARCHITECTURE.md refinements), land the 8 foundational conventions that must exist before feature code is written, and stand up the tooling/CI/logging baseline that every later phase depends on. No user-visible behavior; but after this phase the project *has* conventions.
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, ARCH-01, ARCH-02, ARCH-03, ARCH-04, ARCH-05, ARCH-06, STACK-01, STACK-02, STACK-03, STACK-04, LOG-01, LOG-02, LOG-03, SEC-02, SEC-03, CI-01, CI-02, CI-04
**Success Criteria** (what must be TRUE):
  1. A reviewer cloning the repo and running `xcodebuild` against the main scheme builds cleanly with iOS 17.0 deployment target, SwiftPM-only dependencies, no SwiftUI code in the app launch path, and a UIKit `AppDelegate` + `SceneDelegate` + `AppContainer` composition root.
  2. A unit test asserts that the PII scrubber redacts E.164 phone numbers, DL numbers, full names, MC/DOT numbers, email addresses, and coordinates from a fixed set of sample payloads — and the same test suite fails a SwiftLint custom rule when `print()`, direct `os_log(...)`, or raw coordinate literals appear in application code.
  3. Deleting and reinstalling the app on device wipes the Keychain (verified by a debug-only button that enumerates Keychain items before and after first launch) — the `didCompleteFirstLaunch` UserDefaults flag gates this.
  4. CI runs two pipelines: simulator tests on every PR (excluding security code), physical-device tests on every merge to `main` (placeholder tests for now — real assertions land in Phase 2/3/4). Both pipelines are documented in `docs/ci.md`.
  5. `PrivacyInfo.xcprivacy` is in Copy Bundle Resources and declares required-reason APIs already in use (UserDefaults, CoreLocation scaffolding, UIPasteboard if any) — verified by extracting the `.ipa` produced by CI and inspecting its contents.
**Plans:** 7 plans
Plans:
- [x] 01-01-PLAN.md — Wave 0: Xcode project retarget to iOS 17.0 + test target registration + delete SwiftUI scaffold
- [x] 01-02-PLAN.md — Wave 1: Package.swift (Nuke + SwiftLintPlugins) + .gitignore + .swiftformat + docs/{ci,cert-rotation}.md + 3 ADRs
- [x] 01-03-PLAN.md — Wave 1: Core/ services — Logging + PIIScrubber + KeychainStore + KeyStore + SessionLockService + DeepLinkRouter + NetworkClient skeleton + tests
- [x] 01-04-PLAN.md — Wave 1: Roles enum + 5 TabBarControllers + UI/DesignSystem + Features/ placeholders + PrivacyInfo.xcprivacy + ATS-strict Info.plist
- [x] 01-05-PLAN.md — Wave 2: App composition root — AppDelegate + SceneDelegate + AppContainer + AppCoordinator + DevMenu (DEBUG-only shake gesture, role switcher, Keychain inspector, log viewer) *(Task 3 manual verification deferred to HUMAN-UAT)*
- [x] 01-06-PLAN.md — Wave 2: SwiftLint + 4 custom rules (D-19) + SwiftFormat + pre-commit hook + planted-violation validation
- [x] 01-07-PLAN.md — Wave 3: CI workflows (simulator + device) + CI-02 placeholder UI tests + D-06 device smoke test + PrivacyInfo + coverage gates *(Task 5 manual verification deferred to HUMAN-UAT)*

### Phase 2: Networking Contract & Device Keys
**Goal**: Stand up the contract-first networking stack — typed models for every M1 endpoint, MockURLProtocol returning canned JSON, dual-pin certificate pinning, idempotency-key interceptor — and the Secure Enclave keystore so Phase 3's OTP verify can register a device-bound EC P-256 keypair. After this phase, the networking and key primitives exist; what's missing is an end-user flow to exercise them.
**Depends on**: Phase 1
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05, SEC-01, DEV-01, DEV-02, DEV-03, DEV-05
**Success Criteria** (what must be TRUE):
  1. A unit test calls every M1 endpoint (OTP request, OTP verify, device register, KYC upload init/chunk/commit, KYC status) via the `APIClient` with `MockURLProtocol` registered, and asserts both success and failure fixtures decode into the typed Swift models without any call-site changes.
  2. Switching `AppContainer.networking` between `.mock` and `.live(baseURL:)` in a single line changes the base URL for all subsequent requests with no other call-site changes — verified by a dev-menu toggle that flips it at runtime.
  3. On a physical device, generating an EC P-256 keypair in the Secure Enclave via `SecureEnclaveKeyStore` with `.biometryCurrentSet` ACL, signing a test payload, and verifying the signature using the public key round-trips; the same test on the simulator uses `SoftwareKeyStore` and succeeds with a `#if DEBUG` capability flag.
  4. A release build refuses to launch on any device where `SecureEnclave.isAvailable` returns false (verified by a forced-stub test in the device CI pipeline).
  5. Cert-pinning dual-pin (leaf + backup SPKI hash) rejects a connection to a staging host configured with a third, un-pinned cert — verified by a networking integration test, and the cert-rotation runbook at `docs/cert-rotation.md` documents the 30-day rotation window.
**Plans:** 7 plans
Plans:
- [x] 02-01-PLAN.md — Wave 0: NetworkError + RequestInterceptor protocols + CR-01/WR-01 Phase 1 fixes
- [x] 02-02-PLAN.md — Wave 1: NET-01 APIEndpoint protocol + APIClient facade + 7 M1 endpoint structs
- [x] 02-03-PLAN.md — Wave 1: NET-02 MockURLProtocol fixture registry + 14 JSON fixtures + endpoint decode tests
- [x] 02-04-PLAN.md — Wave 2: NET-04 IdempotencyInterceptor + NET-05 RetryInterceptor + tests
- [x] 02-05-PLAN.md — Wave 2: SEC-01 dual-pin SPKI cert pinning + SPKIHasher + PinningSessionDelegate + cert-rotation runbook
- [x] 02-06-PLAN.md — Wave 2: DEV-01/02/03/05 Secure Enclave two-key keystore + DeviceFingerprint + ADR 0004 *(device tests pending HUMAN-UAT)*
- [x] 02-07-PLAN.md — Wave 3: NET-03 AppContainer integration + SEC-01 integration test + DEV-03 SC-4 forced-stub test + dev-menu toggle *(Task 8 HUMAN-UAT pending)*

### Phase 3: OTP Auth + Role Shell + Session (the fixed Phase 1 goal)
**Goal**: Deliver the user-decision-fixed Phase 1 visible win: any of the 5 roles (Shipper, Broker, Carrier, Dispatch, Factoring) can enter a phone number, verify a mocked OTP, land on a role-distinct tab shell with placeholder tabs, cold-boot back into that session without re-OTP, and cleanly log out — with `SessionLockService` as the single source of truth for biometric re-prompt across cold-boot and 5-minute-background paths.
**Depends on**: Phase 2
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, SHELL-01, SHELL-02, SHELL-03, SHELL-04, SESS-01, SESS-02, SESS-03, SESS-04, GEO-01, GEO-02, GEO-03, DEV-06
**Success Criteria** (what must be TRUE):
  1. Any of the 5 roles can enter an E.164 phone number, type the mocked `123456` OTP, and land on a tab shell whose tabs match TechStack.md §4 for that role — verified by a smoke UI test per role (5 tests total, one per role).
  2. Killing and relaunching the app with a valid session token in Keychain skips the phone-entry screen and routes directly to the role shell, *and* shows a biometric prompt (via `SessionLockService.shouldRequireBiometric`) before content is visible — verified on a physical device by toggling airplane mode + force-quit + relaunch.
  3. Backgrounding the app for >5 minutes then returning triggers the same biometric prompt via the same `SessionLockService` code path; backgrounding for <5 minutes does not.
  4. Logging out from the Profile tab wipes Keychain tokens, clears the Secure Enclave authorization key's ACL, tears down the role coordinator stack, and returns to the phone-entry screen — verified by inspecting Keychain items post-logout.
  5. Attempting to auth while `CLLocationManager` reports a non-US country is refused client-side with a clear error, and raw coordinates never appear in any log message or analytics event (phantom-typed `AnalyticsEvent` makes the latter a compile error).
**Plans:** 12 plans (updated post-checker revision: Plans 06 and 08-original split per Blockers 5 and Warning 3)
Plans:
- [x] 03-01-PLAN.md — Wave 0: test scaffolding stubs + otp-verify-rate-limited.json fixture
- [x] 03-02-PLAN.md — Wave 1: Pre-Phase-3 carryover fixes (CR-02 SE idempotent + IN-01/05 acronym CodingKeys + IN-02 DER unification) — frontmatter requirements: [AUTH-03, SESS-04] (prerequisite lineage)
- [x] 03-03-PLAN.md — Wave 1: GEO-03 compile-time discipline (PlatformPayloadField + LogField cleanup + SwiftLint ban_raw_coordinate_literal)
- [x] 03-04-PLAN.md — Wave 1 (depends_on: [02]): Keychain + KeyStore extensions (KeychainScope, deleteAll(under:), deleteKey(slot:))
- [x] 03-05-PLAN.md — Wave 1: APIClient 429 + Retry-After parsing → NetworkError.rateLimited
- [x] 03-06-PLAN.md — Wave 2: Core/Auth lock+restore+biometric (BiometricService + SessionLockService extension incl SESS-03 + SessionRestoreService)
- [x] 03-07-PLAN.md — Wave 2 (depends_on: [06]): Core/Auth logout+sensitive+401 (LogoutService + SensitiveActionService WWDC22 single-prompt + Auth401ResponseInterceptor + KeyStoreProtocol context-aware overload)
- [x] 03-08-PLAN.md — Wave 2: Geo subsystem (LocationProvider + CountryGate + Info.plist NSLocationWhenInUseUsageDescription)
- [x] 03-09-PLAN.md — Wave 3: Auth flow UI (AuthCoordinator + PhoneEntry VC+VM + OTP VC+VM)
- [x] 03-10-PLAN.md — Wave 3 (depends_on: [09]): Lock/Region/Profile UI (BiometricLock + NotAvailableInRegion + AnotherActiveSession + Profile VCs + Environment.supportEmail)
- [x] 03-11-PLAN.md — Wave 4: Composition root (AppContainer + SessionRestoreProbe lightweight cold-boot helper + SceneDelegate observer + AppCoordinator + 5 role TabBar avatar wiring)
- [x] 03-12-PLAN.md — Wave 5: 5 role UI smoke tests (D-32 SC-1 — driven by -MockOTPRoleForUITest launchArg + mandatory StubLocationProvider/StubCountryGate injection per Warning 4)
- [x] 03-13-PLAN.md — Wave 6 (gap-closure): SceneDelegate wires BiometricLockViewController over .role cold-boot + didBecomeActive observer (SESS-01/02/03 — closes 03-VERIFICATION.md gap 1)

### Phase 4: App Attest & Physical-Device CI Hardening
**Goal**: Add App Attest to the device registration flow with server-side counter/challenge handling, and harden the physical-device CI pipeline to actually exercise Secure Enclave keypair generation, Keychain biometric-bound item storage, and App Attest assertion generation on every merge to `main`. After this phase, the attestation surface exists and the test surface that exercises it is real.
**Depends on**: Phase 3
**Requirements**: DEV-04, CI-03
**Success Criteria** (what must be TRUE):
  1. On a physical device, first successful OTP verify generates an App Attest key once, persists its identifier to Keychain, and includes an assertion (server-generated challenge + request-body hash) in the `/device/register` payload — verified by inspecting the registered payload against the mock backend's counter/challenge check.
  2. On a device where App Attest is unavailable (older hardware, entitlement missing), registration proceeds with a logged warning and a graceful-skip flag in the payload — no user-facing error.
  3. CI physical-device pipeline runs Secure Enclave keypair-generation + Keychain biometric-bound storage + App Attest assertion tests on every merge to `main`, and blocks merges that break any of them — verified by intentionally breaking one test and confirming the pipeline fails.
**Plans:** 10 plans
Plans:
- [ ] 04-01-PLAN.md — Wave 1: Foundational types + protocol + KeychainKey extensions + entitlement + ADR 0005 + attestation-rotation runbook
- [ ] 04-02-PLAN.md — Wave 1: Wave 0 test scaffolding — 4 JSON fixtures + KeychainScopeTests (D-03 pin) + FakeAttestationService + SeededLAContext
- [ ] 04-03-PLAN.md — Wave 2: AttestationService implementations — DCAppAttestAttestationService (production) + SimulatorBypassAttestationService (DEBUG+sim) + AttestedKeyStore
- [ ] 04-04-PLAN.md — Wave 2: Endpoints — DeviceChallenge (GET) + DeviceHeartbeat (POST) + DeviceRegister three-key payload extension + trustTier response
- [ ] 04-05-PLAN.md — Wave 3: 12 simulator-side tests — D-01/D-04/D-05/D-06/D-07c/D-07d/D-08/D-09/D-09f/D-10/D-02-wire/D-04-interceptor + Release-strings grep guard script
- [ ] 04-06-PLAN.md — Wave 3: AppContainer wiring — attestationService + preflightAttestationEntitlement + AppSession trustTier holder + biometricServiceOverride test seam (D-14)
- [ ] 04-07-PLAN.md — Wave 4: SceneDelegate cold-boot + 24h warm-foreground heartbeat + DevMenu 'Re-attest now' row + AttestationErrorResponseInterceptor (D-07 + D-04 automatic + manual paths)
- [ ] 04-08-PLAN.md — Wave 4: LimitedTrustBannerView (UIKit non-dismissible) + RoleCoordinator wrap extension + 2 XCUITests + iPad landscape checkpoint (D-11 + D-12)
- [ ] 04-09-PLAN.md — Wave 4: Device-CI tests — AppAttestRoundTripTests + KeychainBiometricACLTests + LogoutClearsAuthorizationKeyTests (D-13 + D-14 + D-03 on device)
- [ ] 04-10-PLAN.md — Wave 5: CI pipeline — ci-device.yml upgrade + ci-simulator.yml Release guard + report-flaky-passes.sh + docs/ci.md + branch-protection HUMAN checkpoint (CI-03 + D-15 + D-16)

### Phase 5: KYC Capture & Upload Pipeline
**Goal**: Build `KYCCoordinator` + capture flow (face → DL front/back → vehicle/trailer/plate) with GPS metadata attached at capture time via `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination` GPS injection (never through `UIImage`), and the resumable chunked upload pipeline (idempotency-keyed, jittered backoff, background URLSessionConfiguration). KYC status UI renders Pending/Under Review/Verified/Rejected with rejection-reason copy finalized in M1.
**Depends on**: Phase 4
**Requirements**: KYC-01, KYC-02, KYC-03, KYC-04, KYC-05, KYC-06, UPL-01, UPL-02, UPL-03, UPL-04, UPL-05
**Success Criteria** (what must be TRUE):
  1. A user in any role can complete the full KYC capture flow (face → DL front → DL back → truck photo → trailer photo → plate photo → review → submit), and each captured artifact has EXIF GPS metadata attached from a fresh (<30s, <100m accuracy) `CLLocation` — verified by a unit test that round-trips a known GPS value through the pipeline and asserts it reaches the upload payload.
  2. Killing the app mid-upload and relaunching resumes from the last committed chunk (not restart from zero) — verified by a physical-device test that force-quits during a 6MB upload and confirms `chunksAcked/totalChunks` restores correctly.
  3. The KYC status screen renders Pending / Under Review / Verified / Rejected states with backend-provided rejection-reason copy (controlled vocabulary) — verified by driving all four states through mock fixtures.
  4. Uploads continue in the background via `URLSessionConfiguration.background(withIdentifier:)` + `BGProcessingTaskRequest` — verified by backgrounding the app mid-upload and confirming completion notification fires.
  5. Exponential backoff with jitter caps retries at 5 attempts on 5xx / network errors; server-side idempotency keys prevent duplicate chunk commits — verified by a stress test that injects transient failures and asserts no duplicate chunks land.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundational Conventions & Scaffolding | 7/7 | Complete | 2026-04-21 |
| 2. Networking Contract & Device Keys | 7/7 | Complete | 2026-04-21 |
| 3. OTP Auth + Role Shell + Session | 13/13 | Complete | 2026-04-22 |
| 4. App Attest & Physical-Device CI Hardening | 0/TBD | Not started | - |
| 5. KYC Capture & Upload Pipeline | 0/TBD | Not started | - |

---
*Roadmap created: 2026-04-20*
*Milestone: M1 Foundation (4 weeks, 1–2 engineers)*
*Phase 1 planned: 2026-04-20 (7 plans, 4 waves)*
*Next: `/gsd-execute-phase 1`*
*Phase 2 planned: 2026-04-21 (7 plans, 4 waves)*
*Phase 3 planned: 2026-04-21 (10 plans, 6 waves) — revised 2026-04-21 to 12 plans, 6 waves per checker feedback (Blockers 1-6 + Warnings 1-5)*
