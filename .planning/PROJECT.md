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

### Active

<!-- Milestone 1 ("Foundation") scope. Hypotheses until shipped + validated on real users. -->

**Phase 2 target (Networking Contract & Device Keys)**

- [ ] Contract-first networking layer: typed Swift models for TechStack.md §7 endpoints + URLProtocol-based mock that swaps to live URLs without model changes (NET-01..05)
- [ ] Certificate pinning active with dual-pin SPKI hashes in production (SEC-01; FOUND-05 skeleton already present)
- [ ] Secure Enclave EC P-256 keypair generation + `/device/register` integration (DEV-01..DEV-05)
- [ ] `AppContainer.networking` one-line mock ↔ live toggle (NET-03)

**Phase 3 target (OTP Auth + Role Shell + Session)**

- [ ] Phone + SMS OTP auth shim (FR-iOS-AUTH MUSTs) against mock backend (AUTH-01..06)
- [ ] Session persistence across cold boot + clean logout + >5min background → biometric re-prompt (SESS-01..04)
- [ ] Client-side country pre-check via `CLLocationManager` (GEO-01..03)

**Phase 4 target (Attestation + Device CI Hardening)**
- [ ] App Attest productionization (DEV-04)
- [ ] Physical-device CI runs SecureEnclave + Keychain biometric + App Attest paths on every merge (CI-03)

**Phase 5 target (KYC Capture + Upload)**
- [ ] KYC capture flow with GPS EXIF injection (KYC-01..06)
- [ ] Resumable chunked upload pipeline (UPL-01..05)

**Follow-up items flagged during Phase 1 execution:**
- [ ] CR-01: `NetworkClient.get/post` force-cast `as! HTTPURLResponse` — address in Phase 2 networking work (guard-cast + typed `NetworkError.unexpectedResponseType`)
- [ ] CR-02b: PIIScrubber DL regex `\b[A-Z]{1,2}[0-9]{5,8}\b` is over-eager (matches transaction IDs like `TX1234567`) — narrow to validated US state codes at a later pass
- [ ] CR-03: DevMenu `Row(rawValue: indexPath.row)!` force-unwrap — DEBUG-only; trivial fix
- [ ] WR-01: `MockURLProtocol.handlers` global mutable static — add synchronization in Phase 2 when fixtures grow
- [ ] WR-03: `DeepLinkRouter.bootstrapComplete()` post-unlock routing race — narrow window; revisit in Phase 3 deep-link integration
- [ ] 8 HUMAN-UAT items (see `01-HUMAN-UAT.md`) — run `/gsd-verify-work 1` when ready

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

**Codebase state (as of 2026-04-21, Phase 1 complete):**
UIKit module layout landed per TechStack.md §3.2. Xcode project retargeted to iOS 17.0 with SwiftPM-only dependencies (Nuke 13.0.2 + SwiftLintPlugins 0.63.2). Composition root is `AppDelegate` + `SceneDelegate` + `AppContainer` (initializer DI, zero singletons). Core services present: `Logger` + `PIIScrubber` (6-category redaction, structured + string paths), `KeychainStore` + `KeychainWiper`, `KeyStoreProtocol` (Software + SecureEnclave), `DefaultSessionLockService`, `DeepLinkRouter`, `NetworkClient` skeleton + `MockURLProtocol`, `PinningSessionDelegate` skeleton. Five role `UITabBarController`s + `RoleCoordinator` with ADR-0002 root-swap. DEBUG-only `DevMenu` (shake-gesture → RoleSwitcher / KeychainInspector / LogViewer) empirically excluded from Release binary. SwiftLint 4 custom rules (ban_print, ban_direct_os_log, ban_userdefaults_tokens, no_cross_feature_import) enforced via pre-commit + CI. Two CI pipelines (simulator on PR, device on merge-to-main). 32 unit tests + 5 UI tests all green. 77.43% Core/ coverage. Phase 2 (Networking Contract & Device Keys) is next.

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
*Last updated: 2026-04-21 after Phase 1 (Foundational Conventions & Scaffolding) completion*
