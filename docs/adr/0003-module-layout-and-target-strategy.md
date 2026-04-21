# ADR 0003: Module Layout and Target Strategy

**Status:** Accepted
**Date:** 2026-04-20
**Supersedes:** None

## Context

`TechStack.md §3.2` lays out the module structure: `App/`, `Core/{Networking, Auth, KeyStore, Identity, Storage, Logging, Analytics, Security, AIKit, Navigation}`, `Features/{Onboarding, Loads, BOL, Scanner, Assistant, Profile, Settings}`, `Roles/`, `UI/`, `Resources/`.

Two viable targeting strategies exist:
1. **Single Xcode target with directory groups.** `Features/X` and `Features/Y` live in the same target; "don't import across features" is a convention enforced by review + lint.
2. **Per-Feature local SwiftPM packages.** Each `Features/X` is its own module with a `Package.swift`; cross-feature imports are compile-time errors.

Research findings (`.planning/research/SUMMARY.md`): "no payoff on single-module M1." Per-Feature SPM packages add build-time cost + tooling complexity with zero value when the codebase has < 15 Features.

## Decision

**Single Xcode target with directory groups (option 1) for Phase 1 and onward, re-evaluated at M2 boundary.**

- The app target is `validationLedger` (single PBXNativeTarget).
- Source code is organized in directory groups per the TechStack.md §3.2 layout.
- Cross-feature isolation (ARCH-05) is enforced by **SwiftLint custom rule `no_cross_feature_import`** (Plan 06 ships the rule) — NOT by SPM package boundaries.
- External SwiftPM dependencies (Nuke, SwiftLintPlugins) are declared in the companion `Package.swift` at the repo root (see ADR-TBD or Plan 02 for format).

## Consequences

- **Build speed (Phase 1):** Fast. Single module compiles as one unit.
- **Isolation:** Weaker than compile-enforced. A developer CAN write `import Features_Loads` from `Features/BOL/` if Features were modules, but since they are NOT modules, that statement is meaningless — lint rule `no_cross_feature_import` triggers zero Phase 1 violations (future-proofing for when Features become modules).
- **Testing cost:** Single test target (`validationLedgerTests`) covers all `Core/` + any Feature code that lands in Phase 3+.
- **Refactor cost if we later split:** Medium. Moving a Feature to its own SPM package requires adding a `Package.swift`, declaring types `public`, updating imports in consumers. ~1–2 engineer-days per Feature.

## Re-evaluation Triggers

Revisit this decision when ANY of:
1. The codebase crosses **~15 Features** (compile-time linting becomes valuable).
2. ARCH-05 lint violations start slipping through review (lint rule is insufficient — compile-enforce needed).
3. A second engineer joins and parallel feature work causes merge conflicts in shared-type files (module boundaries enforce isolation).
4. Build time for the single target exceeds ~60s cold (modularization buys parallel compilation).
5. M2 boundary checkpoint — planner should explicitly re-ask at that time.

## Related

- `CONTEXT.md` D-15 (single Xcode target decision), D-18 (ADR layout)
- `.planning/research/SUMMARY.md` ("no payoff on single-module M1")
- `REQUIREMENTS.md` ARCH-03, ARCH-05
- `.planning/research/ARCHITECTURE.md` §Recommended Project Structure
