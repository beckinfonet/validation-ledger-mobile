---
phase: 04-app-attest-physical-device-ci-hardening
plan: 10
subsystem: ci-pipeline
tags: [ci, device-ci, branch-protection, flakiness, release-guard]
status: complete
requirements_completed: [CI-03, DEV-04]
dependency_graph:
  requires:
    - ".github/workflows/ci-device.yml (Phase 1 baseline)"
    - ".github/workflows/ci-simulator.yml (Phase 1 baseline + prior extensions)"
    - "scripts/verify-release-no-sim-bypass.sh (Plan 04-05 Task 3)"
    - "validationLedgerDeviceTests/* (Plan 04-09 suites)"
  provides:
    - ".github/workflows/ci-device.yml (device-security-surface job, full security surface, D-13/D-15 retry + Slack)"
    - ".github/workflows/ci-simulator.yml (Release-strings guard step, D-10)"
    - "scripts/report-flaky-passes.sh (D-15 flaky Slack notifier)"
    - "docs/ci.md (Phase 4 runbook + first-run branch-protection dance + HUMAN-UAT checklist)"
  affects:
    - "Branch protection rule for main (requires HUMAN admin action — Task 5)"
    - "Merge gating for every future PR to main (after HUMAN-UAT closes)"
tech_stack:
  added: []
  patterns:
    - "xcodebuild -retry-tests-on-failure -test-iterations 2 for single-retry flake policy (D-15)"
    - "xcrun xcresulttool + grep-based retry-marker detection (format-resilient)"
    - "Slack webhook POST with optional-env best-effort fallback (|| true)"
    - "strings(1) grep on Release xcarchive binary for leaked debug symbols (D-10)"
key_files:
  created:
    - "scripts/report-flaky-passes.sh"
  modified:
    - ".github/workflows/ci-device.yml"
    - ".github/workflows/ci-simulator.yml"
    - "docs/ci.md"
decisions: []
metrics:
  duration: "~20min (tasks 1-3); Task 5 closed by the 2026-05-16 close-out quick task"
  completed_date: "2026-05-16"
  commits:
    - "cd7aab8 ci(04-10): upgrade device CI — full security surface + single-retry + flaky notify"
    - "d2e44e9 ci(04-10): add flaky-pass Slack reporter + wire Release-strings guard into sim CI"
    - "7c08aa9 docs(04-10): document Phase 4 device pipeline + branch-protection runbook"
    - "72fa3ee ci: Phase 4 close-out (PR #1 squash) — keychain unlock, NSFaceIDUsageDescription, doc-PR-safe gate"
---

# Phase 4 Plan 10: CI pipeline (CI-03 + D-15 + D-16) Summary — PRELIMINARY (checkpoint_pending)

CI-03 device-pipeline-as-required-status-check: full security surface + single-retry + flaky-pass Slack notifier + Release-strings leak guard wired at the YAML + script layer; final branch-protection configuration awaits a repo admin's manual action in the GitHub UI (Pitfall 4 first-run dance).

## Status

**COMPLETE** — Tasks 1-3 landed in the original execution (commits `cd7aab8` / `d2e44e9` /
`7c08aa9`). Task 5 (the branch-protection HUMAN-UAT checkpoint) was closed by the
2026-05-16 Phase 4 close-out quick task — see
`.planning/quick/260516-phase-4-closeout/SUMMARY.md` for the full record.

The close-out also found that the CI delivered by Tasks 1-3 had **never actually passed**:
simulator CI always failed at SwiftLint (hiding latent breakage) and device CI had never
run a green build. CI-03 is only genuinely satisfied now that both pipelines are green and
the merge gate is live. See "Close-Out Addendum" below.

## What Landed (Tasks 1-3)

### Task 1 — `.github/workflows/ci-device.yml` upgraded (commit `cd7aab8`)

- Renamed job `smoke` → `device-security-surface` (stable name required for branch-protection per Pitfall 4).
- Extended `paths:` filter with Phase 4 surfaces: `Core/Attestation/**`, `Core/Storage/Keychain/**`, `validationLedgerDeviceTests/**`, and the workflow file itself.
- Dropped the `-only-testing:SecureEnclaveSmokeTests` restriction — the full `validationLedgerDeviceTests` target now runs (D-13 full surface: SE round-trip, SE smoke, Keychain biometric ACL, App Attest round-trip, logout-clears-auth-key).
- Added `-retry-tests-on-failure -test-iterations 2` — D-15 single-retry policy. Pass on retry → workflow green + flaky-pass ping; fail twice → workflow red → merge blocked by D-16.
- Bumped `timeout-minutes` 15 → 25 for App Attest round-trip latency.
- Uploads `DeviceTestResults.xcresult` as a 14-day-retention artifact on every run (always(), pass or fail).
- Wires `scripts/report-flaky-passes.sh` post-test as a best-effort Slack notifier (`|| true` — never fails the workflow even if Slack is unreachable).

### Task 2 — `scripts/report-flaky-passes.sh` NEW + `ci-simulator.yml` extended (commit `d2e44e9`)

- **New script** `scripts/report-flaky-passes.sh` (POSIX sh, executable, `sh -n` clean):
  - Input: xcresult bundle path (silent exit 0 if missing).
  - Parses via `xcrun xcresulttool get --format json`; grep-based retry-marker detection (`isRetry`, `retry_count`, `numberOfTestRetries`, fallback on `retried`) for format resilience across Xcode versions.
  - Silent exits when: no xcresult, xcresulttool fails, zero retries, or `SLACK_WEBHOOK_URL` unset (each logged).
  - POSTs a concise message including `GITHUB_SHA` / `GITHUB_RUN_ID` when available.
- **ci-simulator.yml** gains a `Verify Release binary has no sim-bypass symbols (D-10 guard)` step after the coverage gate, invoking the pre-existing `scripts/verify-release-no-sim-bypass.sh` (Plan 04-05 Task 3) on every simulator CI run.

### Task 3 — `docs/ci.md` updated (commit `7c08aa9`)

- Replaced the Phase 1 "Device Pipeline" section with the Phase 4 upgraded surface (job name, timeout, retry flags, artifact, Slack step).
- Added a "Phase 4 Device Pipeline" section documenting D-13 coverage (5 suites), D-15 flakiness policy (explicit `.flaky` + tracking issue for quarantine — no implicit muting), D-16 merge-gate semantics + admin-override residual-risk acceptance.
- Added a "First-run branch-protection dance (Pitfall 4)" subsection — the exact 7-step github.com UI procedure to register `device-security-surface` as a required status check after it has run on main once.
- Added an inline HUMAN-UAT checklist for Task 5 (10 checkboxes) covering the admin UI action and the test-PR verification flow.
- Added the simulator-bypass leak guard subsection (D-10).
- Added `SLACK_WEBHOOK_URL` to the Secrets table (optional; script silent-exits when unset).

## Deviations from Plan

None — plan executed as written. The plan bundled the two script-creation + sim-CI-extension actions into a single task (plan's "Task 2"); the orchestrator prompt scoped them as separate items but the implementation matches the plan's task structure. All plan `<verify>` / `<acceptance_criteria>` checks confirmed green post-change.

## Verification Evidence

### Task 1 — ci-device.yml
- `grep` confirms: `device-security-surface:` present, `smoke:` absent, `timeout-minutes: 25`, both Phase 4 paths (Core/Attestation + validationLedgerDeviceTests), `-retry-tests-on-failure`, `-test-iterations 2`, `-resultBundlePath`, `retention-days: 14`, `scripts/report-flaky-passes.sh`.
- Python structural check (tabs, line count) clean; `yamllint` not installed on host — validation will happen server-side on push.

### Task 2 — scripts/report-flaky-passes.sh
- Executable (`-rwxr-xr-x`); `sh -n` syntax check passes.
- `xcrun xcresulttool` referenced 1x; `SLACK_WEBHOOK_URL` referenced 5x (definition + unset check + post target + 2 doc refs).
- `shellcheck` not installed on host; script follows the proven idioms from `verify-release-no-sim-bypass.sh` (same Phase 4 shell style).
- ci-simulator.yml contains the "Verify Release binary has no sim-bypass symbols (D-10 guard)" step invoking `scripts/verify-release-no-sim-bypass.sh`.

### Task 3 — docs/ci.md
- All required markers present: "Phase 4 Device Pipeline" header (1), `device-security-surface` (5+), "First-run branch-protection dance" + "Pitfall 4" (2+), D-13/D-14/D-15/D-16 each ≥1, both script names, all three Phase 4 test-suite names.

## Self-Check: PASSED

Files confirmed present:

- FOUND: `.github/workflows/ci-device.yml` (modified)
- FOUND: `.github/workflows/ci-simulator.yml` (modified)
- FOUND: `scripts/report-flaky-passes.sh` (new, executable)
- FOUND: `docs/ci.md` (modified)

Commits confirmed in `git log`:

- FOUND: `cd7aab8` — ci-device.yml upgrade
- FOUND: `d2e44e9` — flaky reporter + sim-CI Release guard
- FOUND: `7c08aa9` — docs/ci.md Phase 4 runbook

## HUMAN-UAT Checkpoint (Task 5 — CLOSED 2026-05-16)

Branch protection on `main` was configured via the GitHub API (`gh api -X PUT
.../branches/main/protection`) — not the Settings UI. The API accepts a check context
string directly, so the historical "Pitfall 4 dropdown dance" does not apply.

- Required status checks: `device-security-surface` + `test`; `strict: true` (require
  branches to be up to date before merging).
- `enforce_admins: false` — admins can override for break-glass; the residual risk
  accepted in D-16 / threat `T-CI-03-01`.

**Gate verified:**

- **Block** — test PR #2 (`test/gate-verify-device-fail`) added a deliberate
  `#expect(Bool(false))` to a device test; `device-security-surface` went red and the PR's
  `mergeStateStatus` became `BLOCKED`. PR closed without merging; branch deleted.
- **Green** — PR #1 merged into `main` with `device-security-surface` + `test` both green
  and the strict check satisfied (squash commit `72fa3ee`).
- **Skip** — a non-security PR (the Phase 4 close-out PR) reports `device-security-surface`
  as `skipped`; GitHub counts a skipped required check as passing, so the PR is not blocked.

## Close-Out Addendum (2026-05-16 quick task)

The CI delivered by Tasks 1-3 was structurally correct but had never run green. The
close-out quick task (`.planning/quick/260516-phase-4-closeout/`) brought it online — only
then was CI-03 genuinely satisfied:

- **Simulator CI** — 9 root-cause fixes. It had always failed at SwiftLint, masking a
  stack of latent breakage (real lint violations, an Xcode-version pin for Swift 6.2
  concurrency settings, a missing device-test scheme reference, a missing import, the
  device target's actor-isolation setting, a stale simulator destination + test, and
  coverage-gate exclusions for device-only files).
- **Device CI codesigning** — the self-hosted LaunchAgent runner could not codesign the
  XCTest injection dylibs (`errSecInternalComponent`). Fixed with an in-workflow
  `security unlock-keychain` + `set-key-partition-list` step reading a new
  `KEYCHAIN_PASSWORD` repo secret.
- **NSFaceIDUsageDescription** — the device tests ran on real hardware for the first time
  and the app crashed: `Info.plist` lacked the Face ID usage-description key that any
  on-device `LAContext` biometric access requires. Added the key + a simulator-side guard
  test (`BiometricServiceTests.infoPlistHasFaceIDUsageDescription`).
- **Doc-PR-safe gate** — `ci-device.yml` was restructured so the required
  `device-security-surface` check is reported on every PR (a fast `changes` job skips the
  device job on non-security PRs). A trigger-level `paths:` filter would instead have left
  non-security PRs stuck on an un-reported required check.

## Future Work

- ~~Close CI-03 + DEV-04 in REQUIREMENTS.md~~ — DONE 2026-05-16: the requirement-list
  checkboxes for CI-03 + DEV-04 are flipped to `[x]` with validation notes. The
  REQUIREMENTS.md *traceability table* (bottom of file) is uniformly `Pending` for all
  ~38 requirements — it was never maintained; fixing it is a separate cleanup, not part
  of this close-out.
- Create `docs/ops-incidents.md` on first break-glass event (admin override of branch protection).
- Validate `scripts/report-flaky-passes.sh` against a real xcresult containing a retry — the JSON-format grep may need refinement once we see production xcresult retry markers (expected first retry occurrence will be logged as evidence for format confirmation).
- If the Release-strings guard step proves too slow on every simulator PR, reroute to a dedicated workflow gated on `paths: validationLedger/Core/Attestation/**`.
