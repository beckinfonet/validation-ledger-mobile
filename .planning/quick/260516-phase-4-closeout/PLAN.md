---
quick_id: 260516-phase-4-closeout
description: Close out Phase 4 — bring self-hosted device CI online and gate main
created: 2026-05-16
branch: ci/phase-4-device-ci-online
status: in-progress
mode: direct-orchestration
---

# Quick Task: Close Out Phase 4 — Device CI Online + Gate `main`

## Why

Phase 4 is complete on disk (11/11 plans + summaries) but ROADMAP.md still has
it unchecked. Plan 04-10's `04-10-SUMMARY.md` is `status: checkpoint_pending`:
the device CI pipeline (`ci-device.yml`) was built but never had a self-hosted
runner behind it, and branch protection for `main` was never configured. A
self-hosted runner (`Bakytbeks-MacBook-Pro`) is now online with an iPhone 16
connected — so the checkpoint can finally close.

## Environment (verified 2026-05-16)

- Runner `Bakytbeks-MacBook-Pro` online, labels `[self-hosted, macOS, ARM64, device]`
- iPhone 16 (`iPhone17,3`) connected, devicectl id `2A0FF35F-B9DC-583C-96F6-14D4C3FFD70D`
- `gh` CLI authed (beckinfonet, repo+workflow scopes)
- `ci-simulator.yml` is RED on `main` (SwiftLint step)
- `DEVICE_UDID` repo secret missing; branch protection on `main` absent

## Tasks

### Part A — Fix `ci-simulator.yml`
SwiftLint step fails: it looks for the binary at `.build/artifacts/.../macos/swiftlint`
but the prior step runs `xcodebuild -resolvePackageDependencies`, which vendors
packages into DerivedData and does not download the binary artifact to `.build/`.
Fix: replace the resolve step with `swift package resolve`, which downloads the
pinned SwiftLint 0.63.2 binary artifact to exactly `.build/artifacts/...`.
(Verified locally 2026-05-16.)

### Part B — `ci-device.yml` + first green run
1. Add a `workflow_dispatch:` trigger to `ci-device.yml`.
2. Create the `DEVICE_UDID` repo secret = iPhone 16 id.
3. Open a PR (touches both workflow files → triggers `device-security-surface`
   on the self-hosted runner + `CI (Simulator) / test`).
4. Triage to green. WATCHED RISK: `AppAttestRoundTripTests` needs a code-signed
   device build with the App Attest entitlement — if it fails on signing, PAUSE
   and check with the user.
5. Merge once green → `device-security-surface` registers as a check on `main`.

### Part C — Gate `main`
Set branch protection via `gh api`: require `device-security-surface` +
`CI (Simulator) / test`, strict (up-to-date). Verify with a throwaway PR
carrying a deliberate device-test failure → confirm merge blocked → confirm
fix unblocks → close the test PR.

### Part D — Close out
- `04-10-SUMMARY.md`: `status: checkpoint_pending` → `complete`; fill
  `requirements_completed` (CI-03, DEV-04).
- `docs/ci.md`: tick the Plan 04-10 Task 5 HUMAN-UAT checklist.
- `ROADMAP.md`: mark Phase 4 `[x]` — "(completed 2026-05-16, 5 visual UAT items pending)".
- `STATE.md`: reconcile (stale — claims 27/27 plans / phase 3; truth is Phase 4
  complete, 38/38 plans).

## Out of scope
- The 5 visual/perceptual items in `04-HUMAN-UAT.md` (stays `status: partial`).
- The Phase 1–3 verification debt.
