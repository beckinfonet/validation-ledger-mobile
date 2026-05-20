# Validation Ledger — iOS Client

## What This Is

Native iOS client (iPhone + iPad, iOS 17+) for Validation Ledger — a verified-identity freight platform that attacks fraud (double/triple brokering, chameleon carriers, factoring fraud) by making identity and the chain-of-trust between shippers, brokers, carriers, dispatch, and factoring parties verifiable in real time. The iOS app is where most verification happens physically — at the dock, in the cab, in the broker's office.

As of v1.0, the app has shipped its M1 Foundation: all five roles can OTP-authenticate into role-distinct tab shells, persist a session across cold boot, complete KYC capture, and resume a chunked upload — on a UIKit/iOS-17 base with device-bound Secure Enclave keys and App Attest.

## Core Value

**Identity that cannot be spoofed and a chain-of-trust that cannot be faked.** Every design decision on iOS serves making the person and the counterparty on the other end of a freight transaction demonstrably real.

## Current State

**Shipped:** v1.0 "M1 Foundation" — 2026-05-18 (6 phases, 55 plans, ~28 days).

The foundation is in place: UIKit module layout, the 8 foundational conventions, contract-first mock networking, Secure Enclave device keys, App Attest, 5-role OTP auth + session, and the KYC capture + resumable upload pipeline. ~28,700 LOC of Swift across 207 files. The v1.0 milestone audit closed `tech_debt` — 67/67 requirements satisfied, 6/6 phases verified, 8/8 E2E flows wired, zero critical blockers.

**Next:** v1.1 "Load Flows" — the load slice of the original M2 "Core Flows," scoped down to a focused mini-milestone (see Current Milestone below).

## Current Milestone: v1.1 Load Flows

**Goal:** Deliver the load domain end-to-end on iOS — role-filtered load list, load detail with an interactive chain-of-trust graph, and per-role tender/accept/reject — built entirely against `MockURLProtocol` fixtures.

**Target features:**
- Role-filtered load list — each of the 5 roles sees its relevant loads
- Load detail screen
- Interactive chain-of-trust graph — shipper → broker → carrier → dispatch → factoring node-graph with per-party verification state, tappable for each party's verification basis
- Per-role tender / accept / reject action sets across all 5 roles
- New load-domain mock endpoints + fixtures, extending M1's contract-first `MockURLProtocol` pattern

**Scope decision:** This is the load slice of the original M2 "Core Flows," deliberately scoped down to a focused mini-milestone. Real backend integration, real-time updates (WebSocket/SSE), APNs push, the analytics/crash-vendor pick, and the file-based background `URLSession` rework are deferred to a later milestone — they all require infrastructure (a running server) that the iOS client builds against mocks without. The production backend remains a separate GSD project.

## Requirements

### Validated

<!-- Shipped in v1.0 "M1 Foundation" (2026-05-18). Full requirement-level detail with evidence in .planning/milestones/v1.0-REQUIREMENTS.md. -->

All 67 M1 Foundation requirements shipped and verified across 6 phases:

- ✓ **Foundational conventions (FOUND-01..08)** — PII-scrubbing logger, first-launch Keychain wipe, MVVM-C memory ADR, sim/device CI split, cert-pinning skeleton, PrivacyInfo manifest, SessionLockService, DeepLinkRouter — v1.0
- ✓ **Architecture & module layout (ARCH-01..06)** — UIKit AppDelegate/SceneDelegate (no SwiftUI in the launch path), iOS 17 target, TechStack §3.2 module layout, AppContainer initializer-DI, no-cross-feature-import lint rule, RoleCoordinator root-swap — v1.0
- ✓ **Stack & dependencies (STACK-01..04)** — SwiftPM-only (Nuke + SwiftLintPlugins), SwiftLint + SwiftFormat, Swift Testing + XCUITest, zero analytics/crash SDKs — v1.0
- ✓ **Networking contract (NET-01..05)** — 7 typed M1 endpoints + APIClient, MockURLProtocol fixtures, one-line mock/live swap, idempotency-key interceptor, GET retry backoff — v1.0
- ✓ **Authentication (AUTH-01..06)** — E.164 phone entry, mocked OTP + 3-fail rate-limit, Keychain token storage, logout, 401 auto-logout, sensitive-action re-prompt infrastructure — v1.0
- ✓ **Device binding & integrity (DEV-01..06)** — Secure Enclave EC P-256 keypair, two-key pattern, SoftwareKeyStore fallback + refuse-launch, App Attest at first login, device fingerprint, another-active-session placeholder — v1.0
- ✓ **Role shell (SHELL-01..04)** — RoleCoordinator reads role, 5 distinct tab shells, shared shell elements, role not client-changeable — v1.0
- ✓ **Session management (SESS-01..04)** — cold-boot persistence, >5min-background biometric re-prompt, biometric-re-enrollment re-bind stub, clean logout teardown — v1.0
- ✓ **Geolocation (GEO-01..03)** — location permission at first auth, US country pre-check, compile-time coordinate barrier — v1.0
- ✓ **Transport security (SEC-01..03)** — dual-pin SPKI cert pinning, ATS-strict Info.plist, Keychain-for-tokens lint rule — v1.0
- ✓ **KYC capture (KYC-01..06)** — KYCCoordinator capture flow, Vision face quality gate, VisionKit DL scan, capture-time EXIF GPS injection, 4-state status UI, encrypted on-disk resume — v1.0
- ✓ **Upload pipeline (UPL-01..05)** — chunked KYCUploader, disk-persisted resume, jittered backoff, determinate progress, BGProcessingTask continuation — v1.0
- ✓ **Logging & observability (LOG-01..03)** — Logger-only (lint-enforced), 5 log levels, DEBUG OSLogStore viewer — v1.0
- ✓ **Testing & CI (CI-01..04)** — ≥70% Core/ coverage gate, 5 role smoke tests, physical-device CI lane, docs/ci.md — v1.0

v1.0 closed with a `tech_debt` milestone audit — see `.planning/milestones/v1.0-MILESTONE-AUDIT.md`. ~24 physical-device HUMAN-UAT scenarios remain unexecuted; they are real-hardware observation tasks against verified code, carried as a parallel verification track, not blockers.

### Active

<!-- v1.1 "Load Flows" scope — hypotheses until shipped + validated. Detailed in .planning/REQUIREMENTS.md. -->

- [ ] Role-filtered load list — each of the 5 roles sees its relevant loads
- [ ] Load detail screen
- [ ] Interactive chain-of-trust graph — shipper→broker→carrier→dispatch→factoring node-graph with per-party verification state, tappable for verification basis
- [ ] Per-role tender / accept / reject action sets across all 5 roles
- [x] **LOAD-01, LOAD-02** — Load-domain mock endpoints + fixtures, contract-first foundation (`Core/Load/` value types, `RoleLoadPolicy`, 3 typed endpoints, 22-fixture matrix, DEBUG `MockLoadFixtureRegistry`) — Phase 7, 2026-05-19

### Deferred from M2 (post-v1.1)

<!-- The rest of the original M2 "Core Flows" scope — needs a running backend, addressed in a later milestone. -->

- [ ] Real-time load updates (WebSocket or SSE)
- [ ] APNs push registration with deep links + notification categories; Critical Alerts entitlement
- [ ] Real backend integration — M1's contract-first JSON stubs swap to the live backend
- [ ] File-based background `URLSession` upload rework (ratified M2 follow-up — M1 shipped the foreground chunk loop + BGProcessingTask continuation)
- [ ] Crash/analytics vendor pick behind a `CrashReporter` protocol

### Carried tech debt

<!-- From the v1.0 audit — not in v1.1 scope; address opportunistically or in a dedicated cleanup phase. -->

- [ ] Nyquist validation gaps — Phase 1 `01-VALIDATION.md` is an unfilled draft, Phase 2 has none (`/gsd-validate-phase 1`, `/gsd-validate-phase 2`)
- [ ] `OTPViewModel.retryRegister()` re-issues an already-consumed OTP code — recovery-path robustness (06-REVIEW CR-01)
- [ ] Dead code: `UITabBarController.wrapWithLimitedTrustBanner` — superseded by the AppCoordinator-owned banner container
- [ ] CR-02b PIIScrubber DL regex over-redaction · CR-04 unguarded SPKI placeholders before Release · IN-02 sim/device signature wire-format mismatch
- [ ] `CameraPermissionViewController` exists but is never presented — product decision pending (blocking screen vs. inline copy)

### Future milestones (M3–M5)

- [ ] M3: eBOL rendering, rotating live QR (30s TTL), QR scanner at dock, screenshot blocking, background location, liveness-detection re-decision
- [ ] M4: Claude-Sonnet assistant UI (backend-mediated), offline mode, accessibility pass, analytics instrumentation
- [ ] M5: crash-rate tuning, device-matrix QA, TestFlight closed beta, App Store submission

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
- Self-serve password/token reset, multi-device login — anti-features; account recovery requires re-KYC, one active device per user is core to identity binding
- Client-composed BOL PDFs, client-side QR payload validation — anti-features; backend is the sole authority
- Third-party chat / analytics / marketing SDKs — anti-features; privacy posture is non-negotiable

**Deferred past M1:** v1.1 "Load Flows" takes the load slice (list/detail/trust-graph/tender). Real backend integration, real-time updates, and APNs/notifications are deferred to a post-v1.1 milestone (they need a running server); liveness detection on KYC capture and the crash/analytics vendor pick remain M3/M4 respectively. See Requirements → Deferred from M2.

**Out of this GSD project entirely:**

- Backend platform (Go/Python service, data schema, API implementation, FMCSA integration) — separate GSD initialization
- Anthropic/Claude direct calls from iOS — all AI traffic is backend-mediated per FR-iOS-AI; this iOS project contains only the assistant client that talks to the backend

## Context

**Product context:**
Validation Ledger exists because the trucking industry loses billions annually to identity fraud — brokers accepting loads with forged MC numbers, carriers with chameleon histories, factoring companies paying out on double-brokered shipments. Existing TMS platforms trust self-reported identity. Validation Ledger's premise is that every party on a load is identity-verified with device-bound keys, and every counterparty relationship is visible as a verifiable chain-of-trust.

**Companion document:**
TechStack.md (in repo root) is the iOS client's detailed technical spec — 13 sections covering stack, architecture, five roles, eleven FR groups (auth/KYC/device/geo/security/load/BOL/scanner/AI/notifications/offline), non-functional targets, milestones M1–M5, out-of-scope, and open questions. This PROJECT.md is the GSD-managed derivative; when they disagree, TechStack.md wins for product-level questions and PROJECT.md wins for scope currently in play.

**Codebase state (v1.0 "M1 Foundation" shipped, 2026-05-18):**
~28,700 LOC of Swift across 207 files, six phases. The architecture is settled: UIKit `AppDelegate` + `SceneDelegate` + `AppContainer` (initializer-DI composition root) + `AppCoordinator`; `Core/` modules for Networking, Auth, KeyStore, Attestation, Identity, Storage, Logging, Navigation; `Features/` and `Roles/` for the 5-role tab shells; MVVM + Coordinators throughout. Networking is contract-first against `MockURLProtocol` fixtures — no live backend in M1. Secure Enclave two-key pattern (`deviceKey` `.devicePasscode` + `authorizationKey` `.biometryCurrentSet`), App Attest wired into the first-login `/device/register` path. KYC capture (`KYCCoordinator`) + a resumable chunked `KYCUploader` actor. A sim/device CI split runs unit tests on every PR and a physical-device security-surface lane on every merge to `main`. The v1.0 milestone audit verified 67/67 requirements and 8/8 E2E flows.

**Known issues / technical debt:** the carried tech-debt list under Requirements → Active. Highest-signal items: the Nyquist validation gaps on Phases 1–2, the `retryRegister()` consumed-OTP recovery-path bug, and ~24 physical-device HUMAN-UAT scenarios that were never executed (no hardware/runner access in the build environment). None blocks M2.

**Team context:**
1–2 iOS engineers using AI coding tools, targeting a 24-week v1 closed-beta (M1–M5). M1 shipped on its 4-week target. Backend is built in parallel in a separate codebase; iOS does not wait on it — contract-first JSON stubs kept the client unblocked through all of M1.

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
- **Timeline**: M1 target was weeks 1–4 of a 24-week v1 plan — *met: M1 shipped in ~28 days.* The 30% infrastructure-tax budget held.
- **Team size**: 1–2 iOS engineers + AI coding tools — Rationale: dictates architectural simplicity (MVVM+Coordinators over TCA, initializer DI over Swinject).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Treat TechStack.md as the authoritative v1 iOS spec, refined through GSD | User wrote a detailed spec before GSD init; forcing a rewrite wastes context | ✓ Good |
| Initialize GSD against M1 Foundation only; remaining milestones live in TechStack.md §10 until their time | Keeps the roadmap right-sized for a 4-week milestone | ✓ Good — M1 shipped on its 4-week target |
| Rebuild the SwiftUI Xcode scaffold as UIKit in Phase 1 | Spec mandates UIKit-first for sensitive surfaces; scaffold was Xcode's default | ✓ Good — zero SwiftUI in the launch path |
| Lower deployment target from iOS 26.4 (scaffold default) to iOS 17.0 | Spec-defined minimum; iOS 26.4 is not a real customer target | ✓ Good |
| Phase 1 visible win = OTP auth + role-switched tab shell + persistent session + logout, all 5 roles | Leanest slice exercising the full foundation | ✓ Good — delivered in Phase 3 ("the fixed Phase 1 goal") |
| Backend planning lives in a separate `/gsd-new-project`; iOS uses contract-first JSON stubs for M1 | Keeps iOS unblocked; contract-first means no refactor when the live backend lands | ✓ Good — all of M1 built against mocks, zero backend blocking |
| All five roles ship in M1 with minimal placeholder UI | Validates the role-switching architecture before features multiply | ✓ Good — 5 distinct shells render |
| Defer liveness detection entirely from M1 KYC | §12 Open Q1 parked until M1 reveals Vision-only false-reject tolerance | — Pending (M3 re-decision) |
| Defer crash/analytics vendor pick; M1 uses `os_log` + `OSLogStore` | Don't add SDK weight before real failure data | — Pending (M2/M4) |
| Downgrade FR-iOS-GEO impossible-travel pre-check from MUST to SHOULD on client | Expensive to build correctly; backend enforces it anyway | ✓ Good — GEO shipped without it |
| Keep MVVM + Coordinators; keep the spec's dependency shortlist as-written | Matches team size + spec defaults | ✓ Good — held cleanly through M1 |
| 5-phase M1 structure; split App Attest (DEV-04) + device CI into its own Phase 4 | App Attest rate-limits shouldn't block the Phase 3 visible-win demo | ✓ Good |
| Budget infrastructure tax at 30% of M1 engineering time (PITFALLS P20) | Make the tax explicit so it isn't discovered at week 2 | ✓ Good — 28-day actual confirms the estimate |
| Phase 5: `KYCUploader` uses the foreground `APIClient` chunk loop + `BGProcessingTaskRequest`; file-based background `URLSession` deferred | Ratified user decision — ships resumable upload without the background-session rework | — Pending (M2 follow-up) |
| Phase 5: selfie capture uses a manual shutter, superseding the D-04 hands-free auto-fire | Device debugging showed auto-fire unreliable; Vision gate repurposed to gate shutter-enabled state | ✓ Good |
| Insert Phase 6 from the v1.0 audit to close DEV-04 / CI-03 gaps before milestone close | The audit found App Attest unwired at first login + Phase 4 unverified | ✓ Good — audit→closure-phase loop worked; re-audit closed `tech_debt` |
| Scope the original M2 "Core Flows" down to v1.1 "Load Flows" — load list/detail/trust-graph/tender only; defer real backend, real-time, push, analytics, background `URLSession` | M2 was too large for a focused cycle; the load domain is a coherent vertical slice buildable against M1's `MockURLProtocol` pattern with zero backend dependency | — Pending |
| Build v1.1 against `MockURLProtocol` fixtures; keep the production backend a separate GSD project | M1 proved contract-first iOS dev needs no running server; upholds the documented iOS/backend separation | — Pending |

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
*Last updated: 2026-05-20 — Phase 8 (Role-Filtered Load List) complete; LOAD-03, LOAD-04, LOAD-07, LOAD-08, TRUST-02 delivered (15/15 must-haves verified; 5 device-UAT items pending — see 08-HUMAN-UAT.md)*
