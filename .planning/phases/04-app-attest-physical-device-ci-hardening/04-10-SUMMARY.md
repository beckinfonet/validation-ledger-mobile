---
phase: 04-app-attest-physical-device-ci-hardening
plan: 10
subsystem: ci-pipeline
tags: [ci, device-ci, branch-protection, flakiness, release-guard]
status: checkpoint_pending
requirements_completed: []  # CI-03 + DEV-04 pending HUMAN-UAT close
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
  duration: "~20min (tasks 1-3)"
  completed_date: "pending HUMAN-UAT (Task 5)"
  commits:
    - "cd7aab8 ci(04-10): upgrade device CI — full security surface + single-retry + flaky notify"
    - "d2e44e9 ci(04-10): add flaky-pass Slack reporter + wire Release-strings guard into sim CI"
    - "7c08aa9 docs(04-10): document Phase 4 device pipeline + branch-protection runbook"
---

# Phase 4 Plan 10: CI pipeline (CI-03 + D-15 + D-16) Summary — PRELIMINARY (checkpoint_pending)

CI-03 device-pipeline-as-required-status-check: full security surface + single-retry + flaky-pass Slack notifier + Release-strings leak guard wired at the YAML + script layer; final branch-protection configuration awaits a repo admin's manual action in the GitHub UI (Pitfall 4 first-run dance).

## Status

**PRELIMINARY** — Tasks 1-3 complete and committed on `main`. Task 4 (originally listed as Task 5 in the orchestrator prompt's scope count) is a HUMAN-UAT checkpoint that can only be performed by the repo admin via github.com → Settings → Branches, and only AFTER the updated `ci-device.yml` has run at least once on `main` so the new job name `device-security-surface` appears in the required-status-check dropdown.

Finalize this SUMMARY after the admin confirms the configuration and posts the test-PR verification evidence.

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

## HUMAN-UAT Checkpoint (Task 5 — OPEN)

**What the repo admin must do (once these commits are pushed to GitHub and `device-security-surface` has run at least once on `main`):**

1. Navigate to **github.com/&lt;org&gt;/&lt;repo&gt;/settings/branches** → edit the `main` rule (or create one).
2. Check **"Require status checks to pass before merging"**.
3. Add `device-security-surface` to the required-checks list (the name from `ci-device.yml`).
4. Keep `CI (Simulator) / test` (or equivalent simulator job name) in the required list.
5. Enable **"Require branches to be up to date before merging"** if not already.
6. Save.
7. Open a test PR that deliberately fails `validationLedgerDeviceTests` (e.g., add a transient `#expect(false)` to `AppAttestRoundTripTests`), confirm `device-security-surface` goes red, confirm merge is blocked ("Required check failing"), remove the failure, confirm merge re-enables, close the test PR without merging, delete the branch.
8. Record confirmation (screenshot or text) in this SUMMARY when the HUMAN-UAT finalizes.

**Resume signal:** `approved` — configuration complete + gate verified → orchestrator finalizes this SUMMARY, updates STATE.md + ROADMAP.md, and closes Wave 5.
**Alt:** `deferred: &lt;reason&gt;` — admin permission unavailable; document owner and follow-up date.

## Future Work

- Close CI-03 + DEV-04 in REQUIREMENTS.md traceability table after HUMAN-UAT `approved`.
- Create `docs/ops-incidents.md` on first break-glass event (admin override of branch protection).
- Validate `scripts/report-flaky-passes.sh` against a real xcresult containing a retry — the JSON-format grep may need refinement once we see production xcresult retry markers (expected first retry occurrence will be logged as evidence for format confirmation).
- If the Release-strings guard step proves too slow on every simulator PR, reroute to a dedicated workflow gated on `paths: validationLedger/Core/Attestation/**`.
