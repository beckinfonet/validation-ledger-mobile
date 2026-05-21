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

## Milestone: v1.1 — Load Flows

**Shipped:** 2026-05-21
**Phases:** 5 (7, 8, 9, 9.1, 10) | **Plans:** 35 | **Tasks:** 65 | **Span:** ~3 days execution (2026-05-19 → 2026-05-21)

### What Was Built

- Contract-first load domain: the `Core/Load/` value-type kernel with fail-closed decoders, `RoleLoadPolicy`, 3 typed endpoints, a 22-fixture matrix.
- Role-filtered load list for all 5 roles — diffable `LoadListViewController`, the reusable TRUST-02 verification badge, skeleton/empty/error states, pull-to-refresh.
- Load detail with a status timeline and the marquee interactive chain-of-trust graph (pannable/zoomable, tap-node-for-basis, tap-edge-for-handoff).
- Phase 9.1 (inserted from device UAT): the iPhone chain-of-vouches redesign — vertical attribution tree + role strip, with a `DS.Colors.Verification` single-source helper.
- Per-role tender/accept/reject — `RoleLoadPolicy`-driven action region, optimistic predict + server-confirmed rollback, two-gate tender-to-unverified hard-disable.

### What Worked

- **The Phase 7 contract-first gate held** — locking the `Core/Load/` kernel + endpoints + fixture matrix before any UI meant Phases 8/9/10 each decoded a stable contract; no schema churn rippled downstream.
- **Device-UAT-driven phase insertion (9.1)** — the 2026-05-20 device UAT caught the iPhone trust-graph slot-collision defect; inserting Phase 9.1 fixed it cleanly, and the redesign strengthened TRUST-02 as a side effect (the shared color helper + R12 grep gate).
- **Tooling-enforced invariants** — the R12 negative-grep gate and the "zero `switch load.status` in `Features/Loads/`" lint-as-test turned design rules into CI-checkable structure rather than discipline.
- **Code-review-then-re-verify loop on Phase 10** — 10 code-review findings (2 Critical + 8 Warning) fixed across 9 commits, then re-verified — caught a real T-10-04 defense-in-depth gap before close.

### What Was Inefficient

- **SUMMARY frontmatter hygiene drifted again** — LOAD-05/LOAD-06 never reached the `requirements-completed` frontmatter of plans 09-03/09-05, surfacing as 2 "partial" requirements at the milestone audit despite both being fully implemented and verified. Same class of defect flagged in the v1.0 retrospective — not yet fixed at the source.
- **A test-isolation defect rode from Phase 8 to milestone close** — Phase 8's WR-01 idempotency-guard fix left `AppContainerLoadEndpointsConfigSwapTests` red; it was visible in 09- and 10-VERIFICATION.md but only fixed at milestone close (quick task `260521-l9p`). A red test should be fixed in the phase that reddens it.
- **Physical-device UAT compounded again** — ≈20 v1.1 HUMAN-UAT scenarios deferred phase-by-phase, exactly the pattern the v1.0 retrospective flagged; the parallel device-UAT track still has no scheduled cadence.
- **Auto-generated milestone accomplishments were unusable** — `milestone.complete` dumped raw SUMMARY text (including `"One-liner:"` placeholders and `[Rule 1 — Bug]` deviation lines) and the MILESTONES.md entry needed a full manual rewrite — a direct downstream cost of the frontmatter-hygiene drift.

### Patterns Established

- Contract-first domain kernel as a hard phase gate — no UI phase starts before the value types + endpoints + fixtures decode green.
- Fail-closed enum decoders (`VerificationState → .unverified`, `ChainIntegrity.Verdict → .compromised`) as the security primitive for a trust-rendering UI.
- Negative-grep gates (R12) + lint-as-test (`switch load.status`) to enforce single-source-of-truth and policy-only gating structurally.
- Size-class-routed composition — one VC mounting different subviews per `horizontalSizeClass` while preserving the other class's surface unchanged.
- DEBUG launch-arg failure toggles (`-MockActionConflict409`, …) for exercising optimistic-UI rollback paths.

### Key Lessons

1. **Fix a red test in the phase that reddens it** — the Phase 8 → Phase 10 test-isolation leak proves a red suite tolerated for "later" rides all the way to milestone close.
2. **SUMMARY `requirements-completed` frontmatter needs a per-plan gate** — two milestones running, the same hygiene drift produced "partial" requirements and unusable auto-accomplishments. Worth a planner/executor checklist item or a CI check.
3. **Device-UAT can drive useful scope** — Phase 9.1 shows real-hardware feedback inserted as a phase beats a minimal patch; but the un-run device-UAT backlog still needs a cadence (v1.0 lesson, still open).
4. **The audit→quick-fix→close sequence works** — the milestone audit flagging the 2 red tests, fixing them via a tracked quick task, then closing, kept the milestone from shipping with a known red suite.

### Cost Observations

- Model mix: not separately instrumented (`model_profile: quality` — opus planner/executor, sonnet checker/verifier).
- Sessions: v1.1 executed fast — ~3 days wall-clock for 35 plans across 5 phases.
- Notable: Phase 9.1 (5 plans, inserted) cost less than re-opening Phase 9 would have, and left the codebase better (shared color helper, R12 gate) than a minimal patch.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 M1 Foundation | 6 | 55 | First milestone — established the GSD phase/plan/wave workflow; added Phase 6 via audit-driven insertion |
| v1.1 Load Flows | 5 | 35 | Contract-first domain kernel as a hard phase gate; first device-UAT-driven phase insertion (9.1); tooling-enforced invariants (R12 grep gate, lint-as-test) |

### Cumulative Quality

| Milestone | Tests | Coverage | Dependency Additions |
|-----------|-------|----------|----------------------|
| v1.0 M1 Foundation | ~391 simulator unit/UI tests + device security-surface suites | ~77% `Core/` | 2 SPM packages (Nuke, SwiftLintPlugins); 0 analytics/crash SDKs |
| v1.1 Load Flows | Project total grew past ~600 simulator tests; 86 new snapshot baselines in Phase 10 alone | not separately re-measured | 0 — UIKit/Foundation/QuartzCore only, no new SPM packages |

### Top Lessons (Verified Across Milestones)

1. Per-phase verification gates catch cross-phase gaps that individual phase work cannot see. *(v1.0; reaffirmed v1.1 — Phase 10's per-phase re-verify caught the T-10-04 gap.)*
2. Contract-first mocking decouples a client from an in-parallel backend with no late refactor. *(v1.0; reaffirmed v1.1 — the Phase 7 `Core/Load/` contract gated all UI phases with zero schema churn.)*
3. SUMMARY `requirements-completed` frontmatter hygiene drifts without a gate — it produced empty `one_liner`s in v1.0 and 2 "partial" requirements in v1.1. *(v1.0 + v1.1 — recurring; needs a per-plan check.)*
4. A red test tolerated for "later" rides to milestone close — fix it in the phase that reddens it. *(v1.1 — to be re-tested in M2.)*
