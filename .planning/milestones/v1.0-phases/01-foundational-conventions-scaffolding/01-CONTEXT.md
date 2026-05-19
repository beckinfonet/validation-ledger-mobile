# Phase 1: Foundational Conventions & Scaffolding — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Rebuild the Xcode SwiftUI scaffold as the UIKit module layout specified in TechStack.md §3.2 (with `.planning/research/ARCHITECTURE.md` refinements), land the 8 foundational conventions (FOUND-01..08) that must exist before feature code is written, and stand up the tooling/CI/logging baseline every later phase depends on.

**No user-visible behavior in this phase.** After Phase 1, the project *has conventions*. The first visible win (5-role OTP login + role shell) is Phase 3 and deliberately rides on the Phase 1 scaffolding.

**In scope (from REQUIREMENTS.md traceability, 26 requirements):**
FOUND-01..08, ARCH-01..06, STACK-01..04, LOG-01..03, SEC-02, SEC-03, CI-01, CI-02, CI-04.

**Out of scope (fixed by ROADMAP.md — belongs in Phases 2–5):**
- Networking `APIClient` real endpoints, `MockURLProtocol` fixtures, cert-pinning activation (Phase 2: NET-*, SEC-01, DEV-01..03, DEV-05)
- OTP auth flow, role shell wiring to real session, geolocation, session persistence (Phase 3: AUTH-*, SHELL-*, SESS-*, GEO-*, DEV-06)
- App Attest productionization + physical-device CI real assertions (Phase 4: DEV-04, CI-03)
- KYC capture + resumable upload (Phase 5: KYC-*, UPL-*)

</domain>

<decisions>
## Implementation Decisions

### CI — Simulator pipeline

- **D-01:** **GitHub Actions** runs the simulator pipeline on every PR. macOS-latest runner image. Justification: the 1–2 engineer team size favors standard tooling with trivial secret management and rich scripting; Xcode Cloud's 25 hr/month free tier is adequate but its constrained scripting would force a second pipeline later. (FOUND-04, CI-01, CI-04)
- **D-02:** **Simulator CI minimum-gate bar for Phase 1:** `xcodebuild build -destination 'platform=iOS Simulator,...'` must succeed + SwiftLint passes + unit tests pass on `Core/Logging/PIIScrubber`, `Core/Storage/Keychain/KeychainStore`, `Core/Networking/MockURLProtocol` (scaffolding + fixtures), `Core/Auth/SessionLockService` logic. Target coverage **≥70% on `Core/`** (CI-01).
- **D-03:** Simulator CI explicitly excludes Secure Enclave / biometric code paths (they require real hardware).

### CI — Physical-device pipeline

- **D-04:** **Self-hosted runner on the developer MacBook** with an attached iPhone. GitHub Actions self-hosted runner mode. Single source of cost, no dedicated hardware purchase for M1. **Known trade-off:** device-CI runs block the dev machine for 5–15 min each; single point of failure if MacBook is unavailable or on travel. *Flagged for re-evaluation at M2 boundary — migrate to dedicated Mac mini if this becomes a merge bottleneck.*
- **D-05:** **Device CI trigger policy = merge-to-main + security-path PR gate.** Device pipeline runs on (a) every merge to `main` (FOUND-04 default) AND (b) any PR that modifies files under `Core/Auth/`, `Core/KeyStore/`, `Core/Identity/`, or `Core/Networking/CertificatePinning/`. Catches security regressions in review rather than after merge (ref: `.planning/research/PITFALLS.md` Pitfall 5).
- **D-06:** **Device CI minimum-gate bar for Phase 1:** a single smoke test asserting `SecureEnclave.isAvailable == true` and that a test Keychain item can be written + read. Real Secure Enclave keypair assertions land Phase 2 (DEV-01..03); App Attest assertions land Phase 4 (CI-03).

### Role scaffolding — Phase 1 depth

- **D-07:** Phase 1 delivers the **full dev-menu demo** of ARCH-06: the `Role` enum, the `RoleCoordinator` protocol, 5 concrete per-role `UITabBarController` subclasses, and a DEBUG-only developer menu that swaps the root coordinator on tap. **Rationale:** validates the ARCH-06 swap mechanism end-to-end *before* Phase 3's fixed visible-win demo depends on it — reduces Phase 3 risk since Phase 3 becomes pure session→role wiring, not "build the role shell from scratch." Infrastructure-tax budget (30% of M1) absorbs this growth.
- **D-08:** `Roles/` directory layout:
  - `Roles/Role.swift` — the `Role` enum (`.shipper | .broker | .carrier | .dispatch | .factoring`)
  - `Roles/RoleCoordinator.swift` — the protocol contract
  - `Roles/Shipper/ShipperTabBarController.swift` — placeholder, populated per §4 below
  - `Roles/Broker/BrokerTabBarController.swift`
  - `Roles/Carrier/CarrierTabBarController.swift`
  - `Roles/Dispatch/DispatchTabBarController.swift`
  - `Roles/Factoring/FactoringTabBarController.swift`
- **D-09:** **Tab inventory per role matches TechStack.md §4 exactly.** Each tab is a placeholder `UIViewController` with only its SF Symbol icon + tab title — no content. Phase 3 fills content.
  - Shipper: Loads, Brokers, BOL, Assistant
  - Broker: Loads, Carriers, Network, Assistant
  - Carrier: Loads, Drivers, Documents, Assistant
  - Dispatch: Loads, Fleet, Drivers, Assistant
  - Factoring: Invoices, Carriers, Chain, Assistant
- **D-10:** **Root-swap mechanism at `SceneDelegate` level** per `.planning/research/ARCHITECTURE.md` architecture amendment #3: on role change, `SceneDelegate` constructs a fresh `AppCoordinator` on a fresh `AppContainer` scope so the old coordinator tree deallocates deterministically. No `TabBarCoordinator` mutation. Abrupt replace — not a cross-dissolve (this is a dev affordance, not a product flow).

### Dev menu

- **D-11:** **Single centralized `DevMenu`** — hosts the role switcher (from D-07), the Keychain-item inspector required by Success Criterion 3 (deletes-on-reinstall verification), and the `OSLogStore` viewer required by LOG-03. Adding debug surfaces post-Phase-1 means adding one entry to this menu, not building a new screen each time.
- **D-12:** **Invocation = iPhone shake gesture** (`UIResponder.motionEnded(_:with:)`), matched by `Device → Shake` in Simulator. Straightforward for a solo developer and universally muscle-memorable.
- **D-13:** **Release-build safety = `#if DEBUG` compile-out.** The entire `DevMenu` target + its shake responder + its imports are wrapped in `#if DEBUG` so they are *physically absent* from Release/TestFlight binaries. No runtime flag, no `NSUserDefaults` toggle — the code does not exist in builds that leave developer machines. This is stronger than a runtime guard for a security-first product.
- **D-14:** `DevMenu` lives at `App/DevMenu/` (it is a composition-root concern, not a product Feature — it manipulates the coordinator graph that Features cannot see). It imports from `Core/` freely since it is build-included only in DEBUG.

### Claude's Discretion

The following gray areas were not discussed and default to the choices below. The planner will confirm or adjust; you can override in this file before execution.

- **D-15 (Module/target layout):** **Single Xcode target with directory groups** for Phase 1. Per `.planning/research/SUMMARY.md`: "no payoff on single-module M1" for xcodegen/tuist. ARCH-05's "no cross-feature import" is enforced by the SwiftLint custom rule (D-19), not by separate SPM packages. A future split to local SPM packages is a mechanical refactor when the project outgrows a single target. Nuke stays as an external SwiftPM dependency.
- **D-16 (PII scrubber API shape):** **Hybrid, structured preferred.** Primary API is structured with typed fields — `logger.info(event: .otpSent, fields: [.phone: rawPhone])` — where the `Field` type drives the scrubbing rule per category (phone → E.164 mask; name → first-initial-only; coordinates → redacted entirely; etc.). Secondary string overload exists for ad-hoc debug messages and *also* routes through the same scrubber before emit, so string-based calls cannot bypass redaction. Structured is preferred in code review; the string API is a pressure valve, not an encouraged path.
- **D-17 (Logging subsystems):** One `OSLog` subsystem per top-level `Core/` module (`com.maldin.validationLedger.networking`, `.auth`, `.keystore`, `.storage`, `.identity`, `.navigation`, etc.), with categories inside (e.g., Networking: `.request`, `.response`, `.pinning`, `.retry`). Standard OSLog pattern; supports per-subsystem live-filter in Console.app.
- **D-18 (ADR layout):** **`docs/adr/NNNN-title.md`** — numbered, immutable once Accepted, superseded (not edited) when decisions change. Phase 1 ships at minimum:
  - `docs/adr/0001-mvvm-c-memory-conventions.md` (satisfies FOUND-03 "documented in `CLAUDE.md` and enforced at review" — the CLAUDE.md reference will link here)
  - `docs/adr/0002-role-coordinator-swap-pattern.md` (satisfies ARCH-06)
  - `docs/adr/0003-module-layout-and-target-strategy.md` (records D-15 and its re-evaluation trigger)
  - `docs/ci.md` (satisfies CI-04)
  - `docs/cert-rotation.md` skeleton only in Phase 1 (FOUND-05 full runbook content is a Phase 2 deliverable — skeleton exists so the path is reserved)
- **D-19 (SwiftLint custom rules — all four ship in Phase 1):**
  - Ban `print(_:)` calls in application code (LOG-01)
  - Ban direct `os_log(...)` calls outside `Core/Logging/` (LOG-01)
  - Ban `UserDefaults` writes to keys named `*token*`, `*key*`, `*session*` (SEC-03)
  - Ban `Features/X` importing `Features/Y` — ARCH-05 "no-cross-feature-import" (cross-feature comms through `Core/` protocol existentials only)
  - Deferred to Phase 3 (not Phase 1 scope): raw-coordinate-literal ban for GEO-03 phantom-typed `AnalyticsEvent`. Landing it in Phase 1 would fail on zero violations anyway; lands with GEO-03 in Phase 3.
- **D-20 (First-launch Keychain wipe):** Implemented in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` **before** any auth service is resolved from `AppContainer`. Reads `UserDefaults.standard.bool(forKey: "didCompleteFirstLaunch")`; if false, enumerates Keychain items under the app's access group via `SecItemCopyMatching(kSecMatchLimitAll)` and deletes each; then sets the flag. The enumerate-before-delete is what makes the DevMenu Keychain inspector (D-11) useful — it can show "before wipe / after wipe" on a test install.
- **D-21 (`PrivacyInfo.xcprivacy` declared APIs for Phase 1):** `NSPrivacyAccessedAPITypeUserDefaults` (reason `CA92.1` — app functionality; used by `didCompleteFirstLaunch` flag, debug toggles), `NSPrivacyAccessedAPICategoryActiveKeyboard`/`UIPasteboard` *not* declared until an actual use is added. Third-party SDK list: **empty**. File must be in **Copy Bundle Resources** (not just the project tree) per research Pitfall 7 — a grep-able CI check verifies this.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### Product spec (authoritative for the iOS client)

- `TechStack.md` — the 13-section iOS spec. PROJECT.md is the GSD-managed derivative; when they disagree on product-level questions, TechStack.md wins.
- `TechStack.md §2` — platform, stack, and iOS floor (17.0)
- `TechStack.md §3.2` — baseline module layout (refined by research/ARCHITECTURE.md amendments)
- `TechStack.md §4` — role tab inventories (the D-09 source of truth)
- `TechStack.md §10` — M1 milestone scope (does NOT include the 30% infrastructure tax — see PITFALLS.md)

### Planning artifacts

- `.planning/PROJECT.md` — product description, core value, constraints (UIKit-first, SwiftPM-only, iOS 17.0, zero-PII-in-analytics), key decisions table
- `.planning/REQUIREMENTS.md` — 67 v1 requirements with phase traceability; Phase 1 owns 26
- `.planning/ROADMAP.md` — 5-phase M1 structure + success criteria per phase + infrastructure-tax budget statement
- `.planning/STATE.md` — session continuity + decisions log

### Research (HIGH confidence, verified 2026-04-20)

- `.planning/research/SUMMARY.md` — executive summary; validates stack, architecture, and M1-critical pitfalls
- `.planning/research/ARCHITECTURE.md` — **critical for Phase 1** — refined directory structure, 4 architecture amendments to TechStack.md §3, and the "Build order for M1 Foundation" 12-step table that Phase 1 implements steps 1–9 of
- `.planning/research/STACK.md` — version-pinned library choices (Nuke 13.0.2, SwiftLint 0.63.2, SwiftFormat 0.61.0, Swift Testing, no KeychainAccess)
- `.planning/research/PITFALLS.md` — the 8 foundational conventions (P1–P8) that justify Phase 1's scope + M2–M5 pitfalls
- `.planning/research/FEATURES.md` — competitor analysis; M1 table-stakes vs. differentiators
- `.planning/research/TechStack.md` — archived copy of the spec as it was when research ran

### Codebase map

- `.planning/codebase/STRUCTURE.md` — current state of the scaffold (SwiftUI template only, no architectural layers)
- `.planning/codebase/ARCHITECTURE.md` — current (near-empty) architecture snapshot
- `.planning/codebase/CONVENTIONS.md` — current (Xcode-default) conventions
- `.planning/codebase/STACK.md` — current stack snapshot (SwiftUI + Foundation only)
- `.planning/codebase/CONCERNS.md`, `INTEGRATIONS.md`, `TESTING.md` — baseline maps

### Artifacts Phase 1 will author (not yet existing — planner creates)

- `docs/adr/0001-mvvm-c-memory-conventions.md` — FOUND-03
- `docs/adr/0002-role-coordinator-swap-pattern.md` — ARCH-06
- `docs/adr/0003-module-layout-and-target-strategy.md` — D-15 + re-evaluation trigger
- `docs/ci.md` — CI-04 (documents D-01..D-06)
- `docs/cert-rotation.md` — FOUND-05 skeleton (full runbook Phase 2)
- `Resources/PrivacyInfo.xcprivacy` — FOUND-06, SEC-02 (D-21)
- `.swiftlint.yml` + custom rule definitions — STACK-02, D-19
- `.swiftformat` — STACK-02
- `.github/workflows/ci-simulator.yml` — D-01, D-02
- `.github/workflows/ci-device.yml` (or runner config) — D-04, D-05, D-06

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

**None.** The project is a raw Xcode SwiftUI template:
- `validationLedger/validationLedger/validationLedgerApp.swift` — `@main` SwiftUI app, will be replaced by UIKit `AppDelegate`+`SceneDelegate` per ARCH-01
- `validationLedger/validationLedger/ContentView.swift` — placeholder SwiftUI view, deleted in ARCH-01
- `validationLedger/validationLedger/Assets.xcassets/` — accent color + app icon asset sets; retained
- `validationLedger.xcodeproj/project.pbxproj` — Xcode project; deployment target must drop from current 26.4 to 17.0 (ARCH-02)

### Established Patterns

**None yet.** Phase 1 is where all conventions are established. Key new patterns Phase 1 introduces (referenced by every later phase):
- `AppContainer` — the composition root; only place that knows concrete `Core/` implementations
- `Core/Logging/Logger` protocol + `PIIScrubber` — the ONLY logging path
- `Core/Storage/Keychain/KeychainStore` — hand-rolled SecItem wrapper
- `RoleCoordinator` swap at `SceneDelegate` level
- Features consume `Core/` protocols only; never import other Features

### Integration Points

- **`SceneDelegate`** — where `RoleCoordinator` swap happens (D-10)
- **`AppDelegate`** — where first-launch Keychain wipe runs (D-20) before `AppContainer` resolves
- **`AppContainer`** — initializer-DI composition root; every `Core/` service is registered here
- **`.swiftlint.yml` + plugin** — where all four custom rules (D-19) live

</code_context>

<specifics>
## Specific Ideas

- "Full dev-menu demo" over smaller scoping — the user values validating the architectural swap mechanism in Phase 1 rather than trusting it implicitly into Phase 3's visible-win demo
- Tab inventory per TechStack.md §4 exactly — no generic placeholders, even for Phase 1 stubs
- Developer-MacBook-as-runner is a deliberate M1 cost-saver with a known "revisit when second engineer joins" trigger
- `#if DEBUG` compile-out for DevMenu is stronger than a runtime flag and matches the product's security-first posture

</specifics>

<deferred>
## Deferred Ideas

### Open clarifications (not scope changes — route to the right phase)

- **Profile tab reconciliation** — AUTH-04 (Phase 3) says "log out from the Profile tab" but TechStack.md §4 does not list a Profile tab for any role. Options to resolve in Phase 3 CONTEXT.md: (a) add Profile as a 5th tab per role, (b) Profile lives behind a top-bar avatar affordance (not a bottom tab), (c) the Assistant tab hosts a profile sub-surface. **Not a Phase 1 blocker** — Phase 1 ships §4 tabs verbatim; Phase 3 resolves logout placement.
- **Cert rotation runbook content** — FOUND-05 is mapped to Phase 1 but the full runbook depends on Phase 2's cert pinning implementation. Phase 1 ships the skeleton file at `docs/cert-rotation.md` to reserve the path; Phase 2 fills it alongside SEC-01.

### Future re-evaluation triggers (not in any phase yet; surface when the trigger fires)

- **Dev-MacBook-as-device-runner** (from D-04): revisit at M2 boundary OR when a second engineer joins. If device CI starts blocking merges in practice, migrate to a dedicated Mac mini runner.
- **Single Xcode target vs. SPM packages** (from D-15): revisit when the codebase crosses ~15 Features or when ARCH-05 lint violations start slipping through review.

### Out of Phase 1 scope (existing phase assignments)

- Raw-coordinate-literal SwiftLint ban — lands with GEO-03 in Phase 3
- Real Secure Enclave keypair generation, cert pinning activation, `APIClient` typed endpoints — Phase 2
- 5-role OTP login, session persistence, biometric re-prompt, logout — Phase 3
- App Attest productionization + device CI real assertions — Phase 4
- KYC capture + resumable upload — Phase 5

### Scope-creep parking lot

None — discussion stayed within Phase 1 boundary.

</deferred>

---

*Phase: 01-foundational-conventions-scaffolding*
*Context gathered: 2026-04-20*
