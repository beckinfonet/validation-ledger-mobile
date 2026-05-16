# CI Pipelines

> Documents the two CI pipelines per FOUND-04 + CI-04.
> Workflow YAML lives at `.github/workflows/ci-simulator.yml` and `.github/workflows/ci-device.yml` (created by Plan 07).

## Overview

Two pipelines run:
- **Simulator** (every PR) — `.github/workflows/ci-simulator.yml`
- **Device** (every merge to main + security-path PR) — `.github/workflows/ci-device.yml`

## Xcode Version Policy

- **Dev machine + self-hosted device runner:** Xcode 26.3.
- **Simulator CI:** pins Xcode 26.3 via `sudo xcode-select -s /Applications/Xcode_26.3.app` in workflow.
- **Reason:** the project's `.pbxproj` enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` — Xcode 26 / Swift 6.2 build settings. Xcode 16.x silently ignores them, so the `@MainActor`-assuming composition root (`AppContainer`) fails actor-isolation checks and the app does not compile. CI must therefore run an Xcode that supports these settings. 26.3 matches the dev machine and the device runner, and is present on the `macos-15-arm64` GitHub runner image. The earlier "floor 16.4" policy predated the project's adoption of Swift 6.2 concurrency settings.

## Simulator Pipeline

**Trigger:** `pull_request` on `main`
**Runner:** `macos-latest` (GitHub-hosted) — D-01
**Xcode:** 26.3 (required for Swift 6.2 `SWIFT_DEFAULT_ACTOR_ISOLATION` — see Xcode Version Policy)
**Steps:**
1. Checkout
2. Select Xcode 26.3
3. Install iOS 17 simulator runtime (fallback — image usually has it)
4. Restore SwiftPM cache
5. SwiftLint `--strict` (fail-fast before tests)
6. `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage YES -only-testing:validationLedgerTests -only-testing:validationLedgerUITests/RoleShellSmokeTests`
7. `PrivacyInfo.xcprivacy` presence check (grep-able script per D-21 / FOUND-06)
8. Coverage parser: `Core/` ≥ 70% (CI-01)

**Excluded:** Secure Enclave + biometric + App Attest tests (D-03 — require real hardware). These live in `validationLedgerDeviceTests/` and are gated out by the `-only-testing:` flags above.
**Coverage target:** ≥70% on `Core/` (CI-01). `SecureEnclaveKeyStore.swift` and `DCAppAttestAttestationService.swift` are excluded from the simulator coverage measurement — Secure Enclave and App Attest are non-functional on the simulator, so this pipeline structurally cannot cover them (0% by design). Their coverage is the device pipeline's responsibility (`SecureEnclaveKeyStoreTests` + `AppAttestRoundTripTests`). With those excluded, simulator-measured `Core/` coverage is 73.15%.

## Device Pipeline

**Trigger:** every `push` to `main` and every `pull_request` to `main`. There is intentionally **no `paths:` filter** on the trigger — the expensive device job is path-gated at the *job* level instead (see Job structure).

**Job structure (doc-PR-safe gate):**
- `changes` — GitHub-hosted `ubuntu-latest`, ~15s. Diffs the PR (`base...head`) and decides whether the security surface changed; outputs `device=true|false`. A `push` to `main` or a `workflow_dispatch` always yields `device=true`.
- `device-security-surface` — self-hosted; `needs: changes`; runs only when `device=true`, otherwise **skipped**.

The workflow triggers on every PR so the required `device-security-surface` check is always reported. When no security path changed, the device job is skipped — and GitHub counts a skipped required check as passing — so a docs- or UI-only PR is never left stuck "waiting for status", and the self-hosted Mac runner stays free. (This replaces the old trigger-level `paths:` filter, which would have left non-security PRs blocked on a required check that never runs — see Branch Protection below.)

**Security surface — the device job runs when a PR touches any of:**
- Phase 1 paths (D-05): `validationLedger/Core/Auth/**`, `validationLedger/Core/KeyStore/**`, `validationLedger/Core/Identity/**`, `validationLedger/Core/Networking/CertificatePinning/**`
- Phase 4 additions: `validationLedger/Core/Attestation/**`, `validationLedger/Core/Storage/Keychain/**`, `validationLedger/App/Info.plist`, `validationLedgerDeviceTests/**`, `.github/workflows/ci-device.yml`

**Runner:** self-hosted MacBook with connected iPhone (D-04)
**Runner labels:** `[self-hosted, macOS, device]`
**Xcode:** runner default (Xcode 26.x — see Xcode Version Policy).
**Job name:** `device-security-surface` (stable — referenced verbatim in branch protection).
**Timeout:** 25 min (bumped from 15 in Phase 4 — App Attest round-trip adds latency).

**Steps (`device-security-surface` job — Phase 4 upgraded):**
1. Checkout
2. Show Xcode version
3. Unlock signing keychain — `security unlock-keychain` + `set-key-partition-list` so the LaunchAgent runner can codesign non-interactively (see Secrets → `KEYCHAIN_PASSWORD`).
4. `xcodebuild test -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests -retry-tests-on-failure -test-iterations 2 -resultBundlePath build/DeviceTestResults.xcresult`
5. Upload `DeviceTestResults.xcresult` as a 14-day-retention artifact.
6. Invoke `scripts/report-flaky-passes.sh` on the xcresult — Slack-notifies on any pass-after-retry (D-15).

**Self-hosted runner setup:** See `docs/adr/0003-module-layout-and-target-strategy.md` for the M2-boundary re-evaluation trigger; see GitHub Actions docs for runner labeling.

## Phase 4 Device Pipeline

**Requirement:** CI-03 — physical-device tests on every merge to main, with merge-gate.

**Coverage (D-13):** `.github/workflows/ci-device.yml` runs the full `validationLedgerDeviceTests` target on the self-hosted macOS runner with attached iPhone. Suites in the current surface:
1. `SecureEnclaveKeyStoreTests` — Phase 2 DEV-01/DEV-02 SE round-trip
2. `SecureEnclaveSmokeTests` — Phase 1 smoke
3. `KeychainBiometricACLTests` — Phase 4 D-14 seeded-LAContext Keychain ACL path
4. `AppAttestRoundTripTests` — Phase 4 D-13-3 real-hardware App Attest round-trip
5. `LogoutClearsAuthorizationKeyTests` — Phase 4 D-13-4 SE ACL clearing + D-03 attestedKeyId preservation

**Flakiness policy (D-15):** `-retry-tests-on-failure -test-iterations 2` retries a failed test ONCE. On pass-after-retry, `scripts/report-flaky-passes.sh` POSTs to the Slack webhook (`SLACK_WEBHOOK_URL` secret) so engineers investigate. On fail-twice, the workflow is red. Quarantine is explicit: engineer adds a `.flaky` Swift annotation to the test + opens a tracking issue — implicit quarantine is not acceptable.

**Merge gate (D-16):** The job `device-security-surface` is a required GitHub branch-protection status check on `main`. Red pipeline blocks merge. Admins CAN override via GitHub UI for break-glass situations — this is a documented residual risk (solo-dev org; no adversarial admin assumed; record every override in `docs/ops-incidents.md`).

### Branch protection (D-16)

`main` requires two status checks before merge, configured via the GitHub API
(`gh api -X PUT .../branches/main/protection`):

- `device-security-surface` — the device CI job (its real result on a security PR, or its
  skipped pass on a non-security PR).
- `test` — the `CI (Simulator)` job.

Both run with **"Require branches to be up to date before merging"** (strict) — a PR must
be current with `main` before its green checks count.

**Why no UI "dropdown dance" (the old Pitfall 4):** GitHub's branch-protection *UI* only
offers check names that have already run on the branch. The *API* has no such limitation —
it accepts the check context string directly — so the gate is set with `gh api` and takes
effect immediately. The `push: branches: [main]` trigger still runs the device surface on
every merge to `main`.

**Why the device check never blocks a non-security PR:** `ci-device.yml` triggers on every
PR, and its `device-security-surface` job is *skipped* (not absent) when no security path
changed. GitHub counts a skipped required check as passing — so the required check is
always satisfied, whether the device tests ran or were skipped. A trigger-level `paths:`
filter would instead leave the check un-reported and the PR stuck "waiting for status".

**HUMAN-UAT checklist (Plan 04-10 Task 5):**

- [ ] Branch-protection rule for `main` requires `device-security-surface` + `test`, strict.
- [ ] Verified on a test PR touching `validationLedgerDeviceTests/`: a deliberate device-test
      failure turns `device-security-surface` red and the PR's merge is blocked.
- [ ] Fix the deliberate failure → `device-security-surface` green → merge re-enables.
- [ ] Verified a non-security PR: `device-security-surface` reports `skipped` and does not
      block the merge.
- [ ] Test PR(s) closed without merging; test branch(es) deleted.
- [ ] Verification evidence recorded in `.planning/phases/04-app-attest-physical-device-ci-hardening/04-10-SUMMARY.md`.

**Break-glass:** If `main` ends up blocked with no valid path forward (e.g., a device-runner outage), admins can temporarily un-tick the required-status-check in Settings, merge, then re-tick. Record these events in the PR description + an incident note in `docs/ops-incidents.md` (create the file if needed). D-16 explicitly accepts this admin-override residual risk for a solo-dev org.

### Simulator-bypass leak guard (D-10)

Every simulator CI run also invokes `scripts/verify-release-no-sim-bypass.sh`, which archives the app in Release config (code-signing disabled) and greps the binary for `sim-bypass-` strings. Any match fails the workflow — catches a regression where `SimulatorBypassAttestationService` loses its `#if DEBUG && targetEnvironment(simulator)` gate.

### Re-attestation CI coverage (D-04)

`validationLedgerTests/Attestation/BackendDrivenReattestationTest` exercises the `clearPersistedKeyId() → regenerate` flow against a mocked `attestationInvalid` response. For full integration coverage (server-error-interceptor wired to attestation service), see Plan 09 + the attestation-rotation runbook at `docs/attestation-rotation.md`.

## Known Trade-off

Self-hosted runner occupies the dev MacBook for ~5–15 min per run (25-min ceiling in Phase 4 with the App Attest round-trip). Re-evaluate at M2 boundary (see `.planning/STATE.md` Blockers/Concerns). Migration path: dedicated Mac mini or MacStadium when a second engineer joins or when device CI starts blocking merges in practice.

## Secrets

| Secret | Where Stored | Used In |
|--------|--------------|---------|
| `DEVICE_UDID` | GitHub Actions repo secret | `ci-device.yml` |
| `SLACK_WEBHOOK_URL` | GitHub Actions repo secret (Phase 4) | `ci-device.yml` (flaky-pass notifier) |
| `KEYCHAIN_PASSWORD` | GitHub Actions repo secret (Phase 4) | `ci-device.yml` (unlock signing keychain) |

No API keys, signing certs, or provisioning profiles live in CI for Phase 1 (TestFlight submission is M5).
`SLACK_WEBHOOK_URL` is optional — `scripts/report-flaky-passes.sh` silent-exits when unset.

`KEYCHAIN_PASSWORD` is the runner account's macOS login password. The self-hosted runner
runs as a LaunchAgent whose process context cannot reach the unlocked login keychain an
interactive shell sees, so codesigning the XCTest injection dylibs fails with
`errSecInternalComponent`. The `ci-device.yml` "Unlock signing keychain" step runs
`security unlock-keychain` + `set-key-partition-list` before `xcodebuild` to permit
non-interactive `codesign`. Set it once with `gh secret set KEYCHAIN_PASSWORD` (paste the
login password at the prompt — it stays out of shell history and CI logs).

## Related

- `docs/cert-rotation.md` — cert rotation runbook (skeleton in Phase 1; full content Phase 2)
- `docs/adr/0003-module-layout-and-target-strategy.md` — single-target decision + re-evaluation triggers
- `.planning/research/PITFALLS.md` — CI-related pitfalls P8, P20
