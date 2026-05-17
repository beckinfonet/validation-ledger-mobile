---
quick_id: 260516-phase-4-closeout
description: Close out Phase 4 — device CI online + gate main
status: complete
branch: "ci/phase-4-device-ci-online (merged) → chore/phase-4-closeout"
pr: "#1 — merged (squash 72fa3ee)"
updated: 2026-05-16
---

# Phase 4 Close-Out — Complete

Phase 4 (App Attest & Physical-Device CI Hardening) is closed out. Both CI pipelines are
green, `main` is gated by branch protection, and PR #1 is merged.

## What was delivered

### Simulator CI — fixed (9 root-cause fixes)

`ci-simulator.yml` had **never passed** — it always failed at SwiftLint, masking a stack
of latent breakage. All fixed; the pipeline is green (SwiftLint, build, 236 unit tests +
5 UI smoke tests, PrivacyInfo, Core/ coverage 73.15%, Release sim-bypass guard).

### Device CI — brought online

`ci-device.yml` had never produced a green build. Three blockers fixed:

1. **Codesigning (`errSecInternalComponent`)** — the self-hosted runner is a LaunchAgent
   whose process context can't reach the unlocked login keychain. Diagnosis: a
   non-interactive `codesign` succeeds in an interactive shell, proving the partition list
   was already correct and the runner's keychain/session context was the blocker. Fixed
   with an in-workflow `security unlock-keychain` + `set-key-partition-list` step reading a
   new `KEYCHAIN_PASSWORD` repo secret.
2. **App crashed on device** — the device test suite ran on real hardware for the first
   time and the app crashed: `Info.plist` lacked `NSFaceIDUsageDescription`, required by
   any on-device `LAContext` biometric access. Added the key + a simulator-side guard test
   (`BiometricServiceTests.infoPlistHasFaceIDUsageDescription`).
3. **Doc-PR-safe gate** — restructured `ci-device.yml`: it triggers on every PR (no
   trigger-level `paths:` filter) with a fast GitHub-hosted `changes` job that skips the
   `device-security-surface` job when no security-surface path changed. GitHub counts a
   skipped required check as passing, so non-security PRs are never stranded.

Result: 24 device tests pass on the iPhone 16 (Secure Enclave, Keychain biometric-ACL,
App Attest round-trip, logout SE-ACL clearing).

### Branch protection on `main`

Configured via `gh api`: required status checks `device-security-surface` + `test`,
`strict: true` (require branches up to date), `enforce_admins: false` (admin-overridable
break-glass per D-16 / threat `T-CI-03-01`).

**Gate verified:**
- **Block** — test PR #2 with a deliberate `#expect(Bool(false))` device-test failure →
  `device-security-surface` red → PR `mergeStateStatus: BLOCKED`. Closed without merging.
- **Green** — PR #1 merged with both required checks green + strict satisfied.
- **Skip** — this close-out PR (non-security) shows `device-security-surface` as `skipped`
  and is not blocked by it.

### Phase 4 close-out bookkeeping

- `04-10-SUMMARY.md` — `status: complete`, `requirements_completed: [CI-03, DEV-04]`,
  Close-Out Addendum + Task 5 evidence added.
- `docs/ci.md` — Device Pipeline + Branch Protection sections rewritten; HUMAN-UAT
  checklist closed.
- `REQUIREMENTS.md` — CI-03 + DEV-04 requirement-list checkboxes flipped to `[x]`.
- `ROADMAP.md` — Phase 4 marked `[x]` (completed 2026-05-16, 5 visual UAT items pending).
- `STATE.md` — reconciled (Phase 4 complete, 38/38 plans, Phase 5 next).

## Out of scope (carried forward)

- The 5 visual/perceptual items in `04-HUMAN-UAT.md` — stay `partial`.
- Phase 1–3 verification debt (15 `human_needed` items).
- REQUIREMENTS.md traceability table — uniformly `Pending` for all ~38 requirements
  (never maintained); a separate cleanup.
