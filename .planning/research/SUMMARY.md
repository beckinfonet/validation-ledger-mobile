# Project Research Summary

**Project:** Validation Ledger — iOS Client
**Domain:** Identity-verified freight iOS client (UIKit-first, five-role, security-sensitive)
**Researched:** 2026-04-20
**Confidence:** HIGH

---

## Executive Summary

Validation Ledger is an identity-first freight iOS application targeting five user roles (Shipper, Broker, Carrier, Dispatch, Factoring) on a device-bound trust platform. The 2026 market context directly validates the product thesis: Verified Carrier's "Verified Pickup" shipped April 15 2026 as the first sign that the freight industry is converging on dock-handoff QR verification — Validation Ledger extends that pattern with a rotating 30s-TTL backend-signed QR, Secure Enclave device-bound keys, chain-of-trust visualization as a first-class UI surface, and one-active-device enforcement that no existing competitor implements. The recommended build approach is UIKit-first MVVM + hand-rolled Coordinators + initializer DI via AppContainer, with an App/ → Features/ → Core/ (protocols) dependency direction enforced by directory structure from day one.

The M1 milestone (4 weeks, 1–2 engineers) should be understood as having two distinct layers of work. The visible layer is OTP auth + role-switched tab shell + persistent session + logout for all five roles with placeholder tabs. The invisible but load-bearing layer is eight foundational conventions that must be established before any feature code is written: PII scrubber, first-launch Keychain wipe, MVVM-C memory rules, simulator/device CI split, dual-pin cert pinning, PrivacyInfo.xcprivacy skeleton, SessionLockService unified invariant, and bootstrap-aware DeepLinkRouter. Research converges on a 30% infrastructure tax that is not reflected in TechStack.md §10's milestone table — the roadmap must budget this explicitly or M1 will slip.

The two non-negotiable differentiators that shape M1's technical obligations are D3 (Secure Enclave device-bound identity) and D1 (chain-of-trust visualization). D3 must be partially realized in M1 Phase 1 because every signed-request feature in M2+ (tender signing, refuse-to-tender enforcement) layers on top of it. D1 is the M2 centerpiece and cannot be deferred further without undermining the product's primary identity claim. The most significant external dependency in the project is the Critical Alerts entitlement from Apple — it has a 2–8 week response time and must be filed no later than M2, not M5.

---

## Key Findings

### Recommended Stack

The stack is fully pinned with HIGH confidence from verified sources. The notable differences from TechStack.md §2.1's pre-GSD shortlist are corrections of abandoned libraries and stale IDE guidance. Every library version below was verified against GitHub releases on 2026-04-20.

**Core technologies:**

| Technology | Version | Purpose | Rationale |
|---|---|---|---|
| Xcode | 26.4.1 stable (floor Xcode 16.x in CI) | Build toolchain | TechStack.md says "Xcode 15+" — stale. Xcode 15 has no Swift Testing, no Swift 6 mode, no iOS 26 SDK. Floor CI at Xcode 16; dev at Xcode 26.4.1. |
| Swift | 5.9 floor in Package.swift; Swift 6 mode per-module | Language | Matches spec intent; new Core/ modules can opt into Swift 6 strict concurrency immediately. |
| UIKit / iOS 17.0 | iOS 17 SDK | Primary UI framework | Spec-locked. No SwiftUI on camera/KYC/scanner/BOL. |
| URLSession + thin wrapper | native | HTTP transport | No Alamofire — overkill for 5-endpoint M1 on a zero-PII product. |
| Hand-rolled KeychainStore | native (SecItem) | Token + key-handle storage | OVERRIDES TechStack.md: KeychainAccess last released 2021-03-01 (v4.2.2); last commit 2023-11-12. Abandoned. A 150-line SecItem wrapper in Core/Storage/Keychain/ is smaller than the vendoring cost and is auditable. |
| CryptoKit SecureEnclave.P256.Signing | native | Device-bound keypair (FR-iOS-DEV) | P-256 is the only SEP-supported curve. Device-bound, non-exportable, non-restorable by design. |
| Native URLSessionDelegate cert pinning | native | SPKI-hash cert pinning (FR-iOS-SEC) | TrustKit (3.0.7) is maintained but adds a dep for ~80 lines of delegate code. Use native; pin SPKI hash (not full cert) for rotation resilience. |
| Nuke 13.0.2 | 2026-04-15 | Async image load + cache | OVERRIDES TechStack.md tie: Nuke wins over SDWebImage — fully Sendable, @globalActor ImagePipelineActor, Swift 6-clean. SDWebImage is ~85% ObjC. |
| Swift Testing + XCTest | bundled with Xcode 16+ | Unit tests + UI tests | Swift Testing for all new unit tests; XCTest for UI tests. No Quick/Nimble. |
| MockURLProtocol (hand-rolled) | in-repo | Contract-first mock networking | Core/Networking/Mock/MockURLProtocol swaps with live BASE_URL without model changes. Mocker 3.0.2 in test target only. |
| swift-snapshot-testing 1.19.2 | 2026-03-30 | Visual regression for key screens | Chain-of-trust timeline, BOL render, QR screen. |
| SwiftLint 0.63.2 via SwiftLintPlugins | 2026-01-26 | Style enforcement | SwiftPM build tool plugin. Custom rules for PII scrubber audit points. |
| SwiftFormat 0.61.0 (nicklockwood) | 2026-04-11 | Automated formatting | Pre-commit hook + Xcode Run Script phase. |
| os_log / OSLog / OSLogStore | native | Structured logging + PII scrubbing | M1 only. Crash vendor deferred to M2 per PROJECT.md. |

**Libraries NOT used (with reasons):** KeychainAccess (abandoned 2021), Alamofire (overkill), SDWebImage (ObjC-heavy), Quick/Nimble (superseded), TrustKit (one host — native suffices), XCoordinator (abandoned 2023-02-28), Swinject/Resolver (spec-locked out), RxSwift (no role in 2026), tuist/xcodegen (no payoff on single-module M1).

**TechStack.md items research invalidates:**

| TechStack.md says | Correct posture |
|---|---|
| "Xcode 15+" | Floor Xcode 16.x in CI; Xcode 26.4.1 locally |
| "KeychainAccess or hand-rolled" | Hand-rolled only — KeychainAccess is abandoned |
| "Crash/analytics: pick one in M1" | Deferred to M2; M1 uses os_log/OSLogStore |
| "Image loading: Nuke or SDWebImage" | Nuke 13.0.2 only |
| FR-iOS-GEO impossible-travel as MUST on client | Already downgraded to SHOULD in PROJECT.md; backend enforces |

---

### Expected Features

The competitive analysis confirms the product is in the identity-first freight stack camp. Verified Pickup's April 2026 launch is the strongest external validator of the product thesis. Validation Ledger's delta over Verified Pickup: rotating 30s-TTL backend-signed QR vs. static encrypted QR; Secure Enclave device-bound keys (no competitor does this); chain-of-trust visualization as first-class UI; all five roles in one binary.

**M1 table stakes:**
- T1 Phone + SMS OTP auth
- T2 Biometric re-prompt on sensitive actions
- T3 Role-switched tab-bar shell for all five roles with placeholder tabs
- T4 Live face + DL front/back capture (no liveness enforcement in M1)
- T5 Vehicle/trailer/plate photo capture with GPS metadata
- T6 Resumable upload pipeline with visible progress
- T7 KYC status UI with rejection-reason text

**M1 differentiators (non-negotiable — foundational code must land in M1):**
- D3 Secure Enclave device-bound EC P-256 keypair + one-active-device enforcement — every M2+ signed-request feature builds on this
- D5 Client-side US-only country pre-check
- D6 Screenshot block on DL-capture screen (KYC subset; extended to BOL/QR in M3)
- D11 App Attest / DeviceCheck on login payload
- D12 .biometryCurrentSet Keychain access control on device key

**M2 centerpiece (non-negotiable):**
- D1 Chain-of-trust visualization — TechStack §13 calls it "the single most important screen." Depends on T8 + T9. M2 must deliver this well; placeholder is not acceptable.
- D4 Refuse-to-tender-to-unverified counterparty with inline reason
- T11 Tender / Accept / Reject flow with device-key signing

**M3 dock-and-BOL tier:**
- D2 Live rotating QR (30s TTL, backend-signed) — external backend signing service dependency; largest cross-team dep in M3
- T14 eBOL render + PDF share; T15 QR scanner at dock; T16 POD capture
- D6 Screenshot block extended to eBOL, QR, chain-of-trust

**Anti-features (deliberately NOT built):**
- No "remember me" / no self-serve password reset / no multi-device simultaneous login
- No third-party chat SDK (defer messaging to M4/v2)
- No third-party analytics in M1 (os_log only)
- No offline QR verification (fraud window too large)
- Background location only for Carrier role with active load, explicit opt-in

---

### Architecture Approach

TechStack.md §3 holds up in 2026 with four surgical amendments. MVVM + hand-rolled Coordinators + initializer DI via AppContainer is the 2026 consensus for UIKit apps at 1–2 engineer scale.

**Directory structure (corrected from TechStack.md §3.2):**

```
App/            — composition root; the ONLY place that knows concrete Core/ implementations
Core/
  Networking/   — NetworkClient actor + MockURLProtocol + Interceptors + CertificatePinning/
  Auth/         — SessionStore actor + OTPService + BiometricService
  KeyStore/     — NEW (split from Security/): SecureEnclaveKeyManager + SoftwareKeyStore (sim)
  Attestation/  — NEW (split from Security/): AppAttestService + DeviceCheckService
  Security/     — NARROWED: ScreenshotGuard + ScreenRecordingDetector + JailbreakHeuristics
  Storage/      — hand-rolled KeychainStore + EncryptedQueueStore + Cache
  Identity/     — KYCCoordinator + DocumentScanner + UploadPipeline
  Realtime/     — RealtimeChannel protocol (impl M2)
  Logging/      — PIIScrubber + OSLog Loggers per subsystem + LogExporter
  Analytics/    — phantom-typed AnalyticsEvent (NoOpAnalytics impl in M1)
  AIKit/        — AssistantClient (M4)
Features/       — self-contained; consume Core/ protocol types only
Roles/          — NEW: RoleCoordinator + per-role subdirs
UI/             — design system; depends on nothing
Resources/      — Assets, Localizable.strings, PrivacyInfo.xcprivacy
```

**Four architecture amendments to TechStack.md §3:**

1. Split Core/Security/ into Core/KeyStore/ (key material), Core/Attestation/ (device integrity), Core/Security/ (runtime defenses). Certificate pinning lives in Core/Networking/CertificatePinning/ — it is a networking concern.

2. Features hold protocol existentials (any AuthService, any NetworkClient), never concrete implementation types. This is what makes features testable.

3. Role-based shell uses RoleCoordinator swap at the SceneDelegate level, not TabBarCoordinator mutation. SceneDelegate.presentRoot(.role(newRole)) constructs a fresh AppCoordinator on a fresh AppContainer scope — all old ViewModels, Tasks, and Combine subscriptions deallocate deterministically.

4. Roles/ is a new top-level directory. The five-role requirement is too big for App/ nested coordinators and too cross-cutting for one Features/ module.

**Build order for M1 Foundation (use as roadmap phase scaffolding):**

| Step | What | Rationale |
|---|---|---|
| 1 | App/ skeleton + AppContainer + SceneDelegate | Everything plugs in here |
| 2 | UI/ design tokens | Unblocks all VCs |
| 3 | Core/Logging (os_log + PII scrubber stub) | Every module uses it |
| 4 | Core/Storage/Keychain/KeychainStore | Prerequisite for Core/Auth |
| 5 | Core/KeyStore (SecureEnclaveKeyManager + SoftwareKeyStore) | Device test gate established here |
| 6 | Core/Networking (NetworkClient + MockURLProtocol + Interceptors + PinningDelegate) | Contract-first; every feature needs this |
| 7 | Core/Auth (SessionStore + OTPService + BiometricService) | First multi-Core service composition |
| 8 | AppCoordinator + Features/Onboarding/AuthCoordinator (OTP screens) | First user-facing flow; validates MVVM+C+Combine |
| 9 | Roles/RoleCoordinator + 5 placeholder tab bars | Phase 1 goal |
| 10 | Session persistence + biometric re-prompt wiring | Foundation complete signal |
| 11 | Core/Identity/KYCCoordinator + capture UI + upload pipeline | Final M1 deliverable |
| 12 | PII scrubber production rules + NoOpAnalytics | Required before any beta |

---

### Critical Pitfalls

Eight M1-critical foundational conventions — must be established before feature work proliferates.

1. **Keychain first-launch wipe (Pitfall 2):** iOS Keychain survives app delete+reinstall; prior user's tokens are accessible on reinstall. On first launch, check a UserDefaults boolean (UserDefaults IS cleared on uninstall); if absent, enumerate-and-delete all Keychain items under the app's access group before any auth work. Free to prevent in Phase 1; expensive to retrofit.

2. **PII scrubber from day one (Pitfall 4):** Build Core/Logging/PIIScrubber in M1 Phase 1 as the ONLY logging API. No direct os_log, no print. Enforce via SwiftLint custom rule. URL query params must never carry PII. Deep link URLs use opaque UUIDs. VC titles must not contain dynamic user data.

3. **Dual-pin cert pinning with rotation plan (Pitfall 3):** Pin two SPKI hashes from day one — current leaf public key AND a pre-provisioned backup. Single-hash pinning bricks all users on cert rotation (Let's Encrypt is 90-day). Write the cert rotation runbook before M5.

4. **MVVM-C memory conventions codified before M2 (Pitfall 5):** House rules in an ADR at end of M1 Phase 1 — every sink starts with [weak self]; assign(to:on:) is banned (no weak variant); Coordinators hold VMs, VMs hold weak var coordinator. Undiscovered retain cycles compound through M2–M3 and require a feature freeze to fix.

5. **Simulator/device CI split for Secure Enclave code (Pitfall 8):** SecureEnclave.isAvailable returns false on simulator. Two CI pipelines from Phase 1: (a) unit tests on simulator excluding security code, (b) real-device smoke tests gating PRs that touch Core/Auth/, Core/KeyStore/, Core/Identity/. Set up the device pipeline in M1 — not M3.

6. **SessionLockService as unified biometric re-prompt invariant (Pitfall 10):** Single SessionLockService.shouldRequireBiometric reads lastBiometricSuccessTimestamp from Keychain; called unconditionally on every app activation. Root UI starts behind an opaque lock screen. Two separate code paths for cold launch vs. foreground is the failure mode.

7. **PrivacyInfo.xcprivacy skeleton in M1, not M5 (Pitfall 14):** Must be in Copy Bundle Resources (not just the project tree) and declare required-reason APIs. Missing it fails App Store submission validation. Add skeleton in M1 Phase 1; verify in the .ipa at M3 TestFlight.

8. **Bootstrap-aware DeepLinkRouter sketch in Phase 1 (Pitfall 18):** Push notifications (M3) fire scene(_:openURLContexts:) before app bootstrap completes. Central DeepLinkRouter with bootstrap-aware pending queue must be designed in M1 even though push notifications don't land until M3 — retrofitting into a mature coordinator graph is painful.

**Additional M2–M5 pitfalls to track:**
- Critical Alerts entitlement (Pitfall 17): File by M2. 2–8 week Apple response. Prepare .timeSensitive fallback.
- App Attest rate limits (Pitfall 13): Generate key once; persist to Keychain; regenerate only on DCErrorInvalidKey.
- Biometric re-enrollment bricks SE session (Pitfall 1): DeviceKeyService must handle errSecItemNotFound → re-bind flow and errSecAuthFailed → Settings deep link. Test on physical device by re-enrolling Face ID.
- KYC GPS metadata stripped by UIImage (Pitfall 6): Capture path must be AVCapturePhoto.fileDataRepresentation() → CGImageDestination GPS injection; never through UIImage before upload.
- 30% infrastructure tax not in TechStack.md §10 (Pitfall 20): Logging, error handling, CI, accessibility, privacy manifest, tooling together consume ~30% of M1. Budget it explicitly.

---

## Implications for Roadmap

The roadmap consumer is gsd-roadmapper. Scope is M1 Foundation only (4 weeks, 1–2 engineers). Phase 1 goal is fixed by PROJECT.md: OTP auth + role-switched tab shell + persistent session + logout for all five roles with placeholder tabs.

### Phase 1: UIKit Foundation + Security Skeleton

**Rationale:** Codebase is currently a SwiftUI Xcode template scaffold. Phase 1 must rebuild it as UIKit, establish the directory structure, wire the eight foundational conventions, and deliver the Phase 1 goal. Nothing in M2 is possible without this. Security conventions are cheaper to establish here than at any future phase.

**Delivers:**
- UIKit module layout: App/, Core/ (Logging, Storage/Keychain, KeyStore, Networking, Auth, Security), Features/Onboarding/, Roles/, UI/, Resources/
- AppContainer + AppCoordinator + SceneDelegate composition root
- Core/Logging/PIIScrubber — the ONLY logging path from day one
- Core/Storage/Keychain/KeychainStore with first-launch Keychain wipe
- Core/KeyStore/SecureEnclaveKeyManager + SoftwareKeyStore + simulator/device CI split declared
- Core/Networking/NetworkClient actor + MockURLProtocol + dual-pin PinningSessionDelegate + AuthInterceptor + DeviceSignatureInterceptor + IdempotencyInterceptor
- Core/Auth/SessionStore actor + OTPService + BiometricService + SessionLockService
- OTP phone entry + OTP verification screens (MVVM-C pattern validated end-to-end)
- Roles/RoleCoordinator + 5 placeholder tab bars (one per role)
- Session persistence + biometric re-prompt wiring (foundation complete signal)
- PrivacyInfo.xcprivacy skeleton in Copy Bundle Resources
- SwiftLint + SwiftFormat + pre-commit hooks + CI pipelines (sim + device)
- DeepLinkRouter skeleton with bootstrap-aware queue (protocol sketch; full impl M3)
- UI/ design tokens (colors, spacing, typography)
- Core/Analytics/NoOpAnalytics stub

**Features addressed:** T1, T2, T3 (shell), T22 (logout wiring), D3 (SE keypair generation + registration), D12 (.biometryCurrentSet on device key)

**Pitfalls this phase MUST prevent:** P1 (Keychain wipe), P2 (PII scrubber), P3 (dual-pin), P4 (MVVM-C memory conventions ADR), P5 (sim/device CI split), P6 (SessionLockService), P7 (PrivacyInfo.xcprivacy), P8 (DeepLinkRouter skeleton)

**Infrastructure tax:** Budget 30% of Phase 1 for CI, tooling, error handling boilerplate, ADR writing. If week 2 shows Phase 1 behind, defer D11 (App Attest) and D5 (country pre-check) to M1 Phase 2 — they are SHOULD-tier.

**Research flag:** Standard patterns. No per-phase research needed.

---

### Phase 2: KYC Capture + Upload Pipeline

**Rationale:** After the foundation is solid, the first real product feature is identity capture. This is M1's "subsequent phases" scope from PROJECT.md. The upload pipeline architecture must be decided here because it shapes the backend API contract.

**Delivers:**
- Core/Identity/KYCCoordinator + LivenessDetector (Vision, no third-party SDK in M1) + DocumentScanner + UploadPipeline
- Live face capture (T4 — no liveness enforcement; liveness decision deferred per Open Q1)
- DL front + back capture with GPS metadata via AVCapturePhoto.fileDataRepresentation() → CGImageDestination GPS injection (never via UIImage)
- Vehicle/trailer/plate photo capture with GPS metadata (T5)
- Resumable chunked upload with jittered exponential backoff + idempotency keys + background URLSessionConfiguration (T6)
- KYC status UI with rejection-reason text (T7)
- Screenshot block on DL-capture screen (D6 subset)
- App Attest / DeviceCheck on login payload (D11)
- Client-side US-only country pre-check (D5)
- Jailbreak heuristics reporting to backend (Core/Security/JailbreakHeuristics)
- MC/DOT entry + backend FMCSA lookup (T21 — SHOULD; defer under schedule pressure)

**Features addressed:** T4, T5, T6, T7, T21, D5, D6 (KYC subset), D11

**Pitfalls this phase MUST prevent:** Pitfall 6 (UIImage strips GPS), Pitfall 7 (whole-file upload is not resumable — must be chunked), Pitfall 13 (App Attest key generated once, not on every launch)

**Research flag:** Needs research during planning. Chunked upload + background URLSession + idempotency key contract is non-trivial. App Attest server-side counter/challenge design needs to be specified as part of the API contract work.

---

### Phase Ordering Rationale

- Phase 1 before Phase 2: Networking layer, Keychain, and security conventions must exist before identity capture code is written. There is no safe order reversal.
- D3 (Secure Enclave) in Phase 1, not Phase 2: Signed-request device headers are needed by every M2 feature. DeviceSignatureInterceptor must be wired in Phase 1 so M2 features do not require a retrofit.
- D1 (chain-of-trust visualization) NOT in M1: It depends on T8 and T9 (M2 features). M1 should focus on the SE foundation so D1 can be delivered well in M2. Do not ship a D1 placeholder in M1.
- DeepLinkRouter skeleton in Phase 1, not M3: Push notification work (M3) is an implementation pass, not a design-from-scratch pass inside a mature coordinator graph.
- Physical-device CI in Phase 1, not M3: Set up the device pipeline early; gate it on changes to Core/Auth/, Core/KeyStore/, Core/Identity/.

### Research Flags

**Needs /gsd-research-phase during planning:**
- M1 Phase 2 (KYC + Upload): Chunked multipart upload contract design, App Attest server-side counter/challenge spec, AVCapturePhoto → CGImageDestination GPS pipeline.
- M2 (Load flows + chain-of-trust): Chain-of-trust visualization data model, WebSocket vs. SSE capability advertisement protocol, tender-signing request body canonicalization.
- M3 (BOL + rotating QR): Rotating QR backend signing contract — no published competitor precedent; requires a security review pass before M3 starts.
- Critical Alerts entitlement (file at M2): Research Apple's current acceptance bar for freight/identity products; prepare fallback to .timeSensitive.

**Standard patterns (skip research-phase):**
- M1 Phase 1 (Foundation): MVVM + Coordinators + AppContainer + hand-rolled Keychain + URLSession — well-documented, no novel integration.
- M4 (Offline queue + AI assistant): Well-understood SQLite + idempotency pattern; AI assistant is backend-mediated SSE stream with no novel iOS work.
- M5 (Beta hardening): App Store submission, privacy manifest, TestFlight — procedural.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All library versions verified against GitHub releases API on 2026-04-20. KeychainAccess and XCoordinator abandonment verified by release date and commit recency. Xcode 26.4.1 verified against Apple developer pages. SEP constraints verified against Apple Developer Documentation + Forums thread 748611. |
| Features | HIGH | Table stakes cross-verified against 6+ competitor 2026 product docs. Differentiators (D1–D3, D6, D11, D12) validated against Verified Pickup / Highway / Trustd gap analysis. Anti-features grounded in 2026 iOS security guidance and FMCSA fraud patterns. |
| Architecture | HIGH | MVVM + Coordinators 2026 consensus verified against multiple sources. Module split rationale grounded in Apple docs and enterprise iOS architecture references. SecureEnclave.isAvailable simulator behavior confirmed via Apple Developer Forums 748611. |
| Pitfalls | HIGH (P1–P6, P8); MEDIUM (P7 App Store timing, P13 App Attest rate limits) | Pitfalls verified against Apple docs, WWDC23/24, Let's Encrypt 2024 rotation incident. App Store review behavior is quarterly-variable. App Attest rate limits are undocumented. |

**Overall confidence:** HIGH

### Gaps to Address

- **Liveness SDK decision (Open Q1):** Vision-only liveness may have false-reject rates above acceptable threshold. Decision gate is M1 results. If FRR is unacceptable, budget Jumio/Onfido/Persona at M2.
- **Rotating QR security review:** No competitor does a 30s-TTL backend-signed rotating QR. Explicit security review (ideally external) required before M3 ships.
- **Critical Alerts entitlement:** Apple response is 2–8 weeks and acceptance is not guaranteed. Roadmap should treat "entitlement granted" as a dependency with a hard deadline at M2 and .timeSensitive fallback as the default path.
- **SIM-swap / biometric re-enrollment recovery UX (Open Q5):** "Re-bind this device" UX must be designed in M1 — is it full re-KYC or a lighter recovery? The answer shapes DeviceKeyService error handling in Phase 1.
- **Crash vendor pick (Open Q7):** Deferred to M2. When chosen, wrap SDK behind a CrashReporter protocol in Core/Analytics/ with beforeSend hook running through the PII scrubber.
- **iPad bespoke layouts vs. adaptive (Open Q3):** Deferred to post-M2. Roles/ directory supports iPad-specific coordinators without a refactor — plan for it but do not build in M1.

---

## Sources

### Primary (HIGH confidence — verified 2026-04-20)

- Apple Developer Documentation — SecureEnclave.P256, DCAppAttestService, CLLocationUpdate, URLSessionWebSocketTask, PrivacyInfo.xcprivacy required-reason APIs
- Apple Developer Forums thread 748611 — Secure Enclave simulator unavailability confirmed
- Apple Developer Forums thread 706428 — SEP inter-device key limitations
- Apple Xcode system requirements page — Xcode 26.4.1 stable; floor 16.x for Swift Testing
- GitHub releases API (2026-04-20): KeychainAccess v4.2.2 (2021-03-01, abandoned), Nuke 13.0.2 (2026-04-15, active), XCoordinator v2.2.1 (2023-02-28, abandoned), SwiftLintPlugins 0.63.2 (2026-01-26, active), SwiftFormat 0.61.0 (2026-04-11, active), swift-snapshot-testing 1.19.2 (2026-03-30, active), Mocker 3.0.2 (2024-01-15, active), TrustKit 3.0.7 (2025-06-04, active)
- Verified Carrier "Verified Pickup" launch — GlobeNewswire + FleetOwner, April 15 2026 — primary market validation
- Highway, Trustd, Samsara Driver, Uber Freight, McLeod, Vector eBOL — product docs and App Store listings

### Secondary (MEDIUM confidence — community consensus)

- Jumio / UXCam / Zyphe — KYC abandonment data (15–30% with generic rejection copy; 25–30% improvement with specific reasons)
- FMCSA MOTUS rollout coverage (Trucksafe, Overdrive, iDispatchHub 2025–2026)
- Swift by Sundell, SwiftUI by Majid 2026 articles — Swift Concurrency + Combine coexistence patterns
- Approov, NowSecure 2026 mobile security assessment reports
- Let's Encrypt R3 → R10/R11 intermediate rotation 2024 — cert pinning real-world failure case

### Tertiary (LOW confidence — training data; used for background only)

- Stack Overflow CLLocationUpdate.liveUpdates discussions — corroborated by Apple WWDC notes; used for Pitfall 11 background only

---

*Research completed: 2026-04-20*
*Ready for roadmap: yes*
*Downstream consumer: gsd-roadmapper scoping M1 Foundation phases*
