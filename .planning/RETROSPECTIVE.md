# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — M1 Foundation

**Shipped:** 2026-05-18
**Phases:** 6 | **Plans:** 55 | **Tasks:** 128 | **Span:** ~28 days (2026-04-20 → 2026-05-18)

### What Was Built

- UIKit/iOS-17 foundation: module layout, 8 foundational conventions, PII-scrubbing logger, hand-rolled Keychain, SwiftLint custom rules, sim/device CI split.
- Contract-first networking: `APIClient` + 7 typed M1 endpoints + `MockURLProtocol` fixtures, idempotency/retry interceptors, dual-pin SPKI cert pinning, Secure Enclave two-key keystore.
- 5-role OTP auth → role-distinct tab shells, session persistence across cold boot, biometric re-prompt, clean logout; App Attest wired into the first-login `/device/register` path with a physical-device CI lane.
- KYC capture flow (face → DL → vehicle) with capture-time EXIF GPS injection + a resumable chunked `KYCUploader` actor + 4-state status UI.

### What Worked

- **Contract-first mock networking** — building the entire milestone against `MockURLProtocol` fixtures meant zero backend blocking across all 6 phases; the live backend swap is a clean M2 task with no client refactor.
- **Explicit 30% infrastructure-tax budget** — naming the tax up front meant Phase 1's heavy tooling load never read as "behind schedule". M1 landed in 28 days, on its 4-week target.
- **Wave-0 RED test scaffolding** — seeding stub `@Suite` test files before implementation (Phases 3 and 5) gave every plan a pre-existing red→green target to modify rather than create.
- **Splitting App Attest into its own Phase 4** — kept Apple's undocumented App Attest rate-limits from threatening the Phase 3 visible-win demo.
- **Audit → closure-phase loop** — the first v1.0 milestone audit caught the unwired App Attest first-login gap that no individual phase verification had surfaced; inserting Phase 6 closed it cleanly before the milestone closed.

### What Was Inefficient

- **Phase 4 shipped 11 plans without ever running `/gsd-verify-work`** — the missing `04-VERIFICATION.md` directly hid the DEV-04 first-login gap, caught only at the milestone audit. A verification gate per phase would have surfaced it a full phase earlier.
- **Physical-device UAT accumulated unbounded** — ~24 HUMAN-UAT scenarios were deferred phase after phase with no hardware/runner cadence; they are now one large parallel backlog instead of incremental sign-offs.
- **Live-camera defects only surfaced on hardware** — Phase 5 needed an extended on-device debugging cycle (3 debug sessions, ~19 device-only defects) because AVFoundation/Vision produce no simulator frames.
- **SUMMARY frontmatter hygiene drifted** — several Phase 3 summaries left `one_liner` empty or as a literal `"One-liner:"` placeholder, and SHELL-01..04 never reached the `requirements-completed` frontmatter; this surfaced as noise in the auto-generated milestone accomplishments.

### Patterns Established

- Protocol-backed services with simulator-testable pure decision logic and a thin device-only live layer (`CameraSession`/`FaceQualityGate`, `KeyStore`).
- Phantom-typed payload fields turning a security invariant into a compile error (GEO-03: raw coordinates un-attachable to logs/analytics).
- `#if DEBUG` launch-argument test seams for device XCUITests (`-KYCTestSeedForUITest`, `-MockOTPRoleForUITest`).
- `AppContainer` initializer-DI composition root; `SceneDelegate`-level root-swap on role change.
- Sim/device CI split — unit tests on every PR, a physical-device security-surface lane on every merge to `main`.

### Key Lessons

1. **Run `/gsd-verify-work` per phase, not just at milestone audit** — the one unverified phase (4) is exactly where the milestone's only real gap hid.
2. **Treat physical-device UAT as a scheduled track with its own cadence** — open-ended phase-by-phase deferral lets it compound silently into a 24-item backlog.
3. **Contract-first mock networking fully decoupled iOS from the backend** — worth the upfront fixture cost; revisit only when the live backend lands in M2.
4. **Budget the infrastructure tax explicitly** — naming the 30% kept Phase 1 from reading as "behind"; the 28-day actual confirmed the estimate.

### Cost Observations

- Model mix: not separately instrumented this milestone (`model_profile: quality`).
- Sessions: not separately tracked.
- Notable: the audit-then-closure-phase loop added one 4-plan phase but converted a `gaps_found` close into a clean `tech_debt` close — cheap insurance relative to shipping the gap.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 M1 Foundation | 6 | 55 | First milestone — established the GSD phase/plan/wave workflow; added Phase 6 via audit-driven insertion |

### Cumulative Quality

| Milestone | Tests | Coverage | Dependency Additions |
|-----------|-------|----------|----------------------|
| v1.0 M1 Foundation | ~391 simulator unit/UI tests + device security-surface suites | ~77% `Core/` | 2 SPM packages (Nuke, SwiftLintPlugins); 0 analytics/crash SDKs |

### Top Lessons (Verified Across Milestones)

1. Per-phase verification gates catch cross-phase gaps that individual phase work cannot see. *(v1.0 — to be re-tested in M2.)*
2. Contract-first mocking decouples a client from an in-parallel backend with no late refactor. *(v1.0 — to be re-tested in M2.)*
