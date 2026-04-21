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

**Trigger:** `push` to `main` OR `pull_request` touching security paths (D-05)
- Security paths: `validationLedger/Core/Auth/**`, `validationLedger/Core/KeyStore/**`, `validationLedger/Core/Identity/**`, `validationLedger/Core/Networking/CertificatePinning/**`
**Runner:** self-hosted MacBook with connected iPhone (D-04)
**Runner labels:** `[self-hosted, macOS, device]`
**Xcode:** 26.4 (dev machine's installed Xcode)
**Steps:**
1. Checkout
2. `xcodebuild test -destination 'platform=iOS,id=$DEVICE_UDID' -only-testing:validationLedgerDeviceTests`
3. The single Phase-1 smoke test (D-06):
   - `#expect(SecureEnclave.isAvailable == true)` — fails on iPad without SEP, iPhone 5s and older
   - Keychain write → read → delete round-trip on a test key

**Self-hosted runner setup:** See `docs/adr/0003-module-layout-and-target-strategy.md` for the M2-boundary re-evaluation trigger; see GitHub Actions docs for runner labeling.

## Known Trade-off

Self-hosted runner occupies the dev MacBook for ~5–15 min per run. Re-evaluate at M2 boundary (see `.planning/STATE.md` Blockers/Concerns). Migration path: dedicated Mac mini or MacStadium when a second engineer joins or when device CI starts blocking merges in practice.

## Secrets

| Secret | Where Stored | Used In |
|--------|--------------|---------|
| `DEVICE_UDID` | GitHub Actions repo secret | `ci-device.yml` |

No API keys, signing certs, or provisioning profiles live in CI for Phase 1 (TestFlight submission is M5).

## Related

- `docs/cert-rotation.md` — cert rotation runbook (skeleton in Phase 1; full content Phase 2)
- `docs/adr/0003-module-layout-and-target-strategy.md` — single-target decision + re-evaluation triggers
- `.planning/research/PITFALLS.md` — CI-related pitfalls P8, P20
