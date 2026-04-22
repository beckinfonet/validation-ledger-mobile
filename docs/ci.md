# CI Pipelines

> Documents the two CI pipelines per FOUND-04 + CI-04.
> Workflow YAML lives at `.github/workflows/ci-simulator.yml` and `.github/workflows/ci-device.yml` (created by Plan 07).

## Overview

Two pipelines run:
- **Simulator** (every PR) — `.github/workflows/ci-simulator.yml`
- **Device** (every merge to main + security-path PR) — `.github/workflows/ci-device.yml`

## Xcode Version Policy

- **Dev machine:** Xcode 26.4 (current stable locally).
- **CI:** pins Xcode 16.4 via `sudo xcode-select -s /Applications/Xcode_16.4.app` in workflow.
- **Reason:** CI uses the floor version so Swift Testing (bundled in Xcode 16+) + iOS 17 SDK availability are both guaranteed without surprises. `macos-latest` GitHub runner image typically ships Xcode 16.x + 26.x; pinning removes ambiguity. Dev machines get newer Xcode for iteration speed.

## Simulator Pipeline

**Trigger:** `pull_request` on `main`
**Runner:** `macos-latest` (GitHub-hosted) — D-01
**Xcode:** floor 16.4 (bundled iOS 17 SDK + Swift Testing)
**Steps:**
1. Checkout
2. Select Xcode 16.4
3. Install iOS 17 simulator runtime (fallback — image usually has it)
4. Restore SwiftPM cache
5. SwiftLint `--strict` (fail-fast before tests)
6. `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -enableCodeCoverage YES -only-testing:validationLedgerTests/Logging -only-testing:validationLedgerTests/Storage -only-testing:validationLedgerTests/Networking -only-testing:validationLedgerTests/Auth -only-testing:validationLedgerTests/Navigation -only-testing:validationLedgerTests/Roles`
7. `PrivacyInfo.xcprivacy` presence check (grep-able script per D-21 / FOUND-06)
8. Coverage parser: `Core/` ≥ 70% (CI-01)

**Excluded:** Secure Enclave + biometric + App Attest tests (D-03 — require real hardware). These live in `validationLedgerDeviceTests/` and are gated out by the `-only-testing:` flags above.
**Coverage target:** ≥70% on `Core/` (CI-01).

## Device Pipeline

**Trigger:** `push` to `main` OR `pull_request` touching security paths (D-05, extended in Phase 4)
- Phase 1 security paths: `validationLedger/Core/Auth/**`, `validationLedger/Core/KeyStore/**`, `validationLedger/Core/Identity/**`, `validationLedger/Core/Networking/CertificatePinning/**`
- Phase 4 additions: `validationLedger/Core/Attestation/**`, `validationLedger/Core/Storage/Keychain/**`, `validationLedgerDeviceTests/**`, `.github/workflows/ci-device.yml`

**Runner:** self-hosted MacBook with connected iPhone (D-04)
**Runner labels:** `[self-hosted, macOS, device]`
**Xcode:** 26.4 (dev machine's installed Xcode)
**Job name:** `device-security-surface` (stable — required for branch-protection UI check-name lookup per Pitfall 4).
**Timeout:** 25 min (bumped from 15 in Phase 4 — App Attest round-trip adds latency).

**Steps (Phase 4 upgraded):**
1. Checkout
2. `xcodebuild test -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests -retry-tests-on-failure -test-iterations 2 -resultBundlePath build/DeviceTestResults.xcresult`
3. Upload `DeviceTestResults.xcresult` as a 14-day-retention artifact.
4. Invoke `scripts/report-flaky-passes.sh` on the xcresult — Slack-notifies on any pass-after-retry (D-15).

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

### First-run branch-protection dance (Pitfall 4)

GitHub branch-protection only lists check names that have actually run on the protected branch. The first time Phase 4's upgraded `ci-device.yml` lands, follow this sequence:

1. Merge the Phase 4 PR containing `ci-device.yml` changes — this triggers the workflow on `main` via the `push: branches: [main]` trigger.
2. Wait for the workflow to complete (pass or fail — only completion matters).
3. Navigate to **Settings → Branches → Edit `main` rule**.
4. Under **Require status checks to pass**, tick the checkbox.
5. Select `device-security-surface` from the available-checks dropdown. (If not present, the workflow hasn't run yet — go back to step 2.)
6. Also keep `CI (Simulator) / test` (or whatever the simulator job is named) checked.
7. Save.

After this one-time setup, every future PR to `main` is gated by both simulator CI + device CI.

**HUMAN-UAT checklist (Plan 04-10 Task 5 — completed by repo admin via github.com UI):**

- [ ] `device-security-surface` job has run at least once on `main` (verify in Actions tab).
- [ ] Branch-protection rule for `main` exists with "Require status checks to pass before merging" enabled.
- [ ] `device-security-surface` is in the required-checks list for `main`.
- [ ] `CI (Simulator) / test` remains in the required-checks list for `main`.
- [ ] "Require branches to be up to date before merging" is enabled.
- [ ] Verified on a test PR: deliberate `validationLedgerDeviceTests` failure → `device-security-surface` red → Merge button shows "Required check failing" → disabled.
- [ ] Fix the deliberate failure → push → Merge button re-enables.
- [ ] Test PR closed without merging; test branch deleted.
- [ ] Screenshot or text-confirmation of the above recorded in the Phase 4 SUMMARY.

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

No API keys, signing certs, or provisioning profiles live in CI for Phase 1 (TestFlight submission is M5).
`SLACK_WEBHOOK_URL` is optional — `scripts/report-flaky-passes.sh` silent-exits when unset.

## Related

- `docs/cert-rotation.md` — cert rotation runbook (skeleton in Phase 1; full content Phase 2)
- `docs/adr/0003-module-layout-and-target-strategy.md` — single-target decision + re-evaluation triggers
- `.planning/research/PITFALLS.md` — CI-related pitfalls P8, P20
