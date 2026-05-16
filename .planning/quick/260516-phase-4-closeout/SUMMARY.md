---
quick_id: 260516-phase-4-closeout
description: Close out Phase 4 — device CI online + gate main
status: in-progress
branch: ci/phase-4-device-ci-online
pr: "#1 — https://github.com/beckinfonet/validation-ledger-mobile/pull/1"
updated: 2026-05-16
---

# Phase 4 Close-Out — Progress Handoff

> Context was cleared mid-task. This file is the resume point. Branch
> `ci/phase-4-device-ci-online` is fully committed and pushed (10 commits);
> working tree is clean. PR #1 is open against `main`, not merged.

## ✅ DONE — Simulator CI is fully GREEN

The simulator CI (`ci-simulator.yml`) had **never passed** — it always failed at
SwiftLint, hiding a stack of latent breakage. All fixed; run 25974633024 is green
(SwiftLint, build, 236 unit tests + 5 UI smoke tests, PrivacyInfo, coverage 73.15%,
Release sim-bypass guard — all ✓).

Nine root-cause fixes (commits on the branch):

1. `7c0b24f` — SwiftLint binary never vendored: use `swift package resolve`, not
   `xcodebuild -resolvePackageDependencies`.
2. `24e3e42` — 8 real SwiftLint violations in `MockOTPRoleFixtureRegistry.swift`.
3. `b0d66f8` — app won't compile on Xcode 16.4: pinned CI to **Xcode 26.3**
   (project uses Swift 6.2 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
4. `f263bfb` — `validationLedgerDeviceTests` was missing from the `validationLedger`
   scheme; added the `TestableReference`.
5. `f6bb90c` — `SecureEnclaveSmokeTests.swift` missing `import Foundation`.
6. `f6a74aa` — device test target lacked `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
   (it had never compiled).
7. `b81092f` — test destination `iPhone 15,OS=17.5` doesn't exist on Xcode 26.3
   (→ `iPhone 17`); + updated a stale Phase-3 carrier-routing test broken by
   Phase 4's limited-trust banner wrapper.
8. `6a66f7a` — coverage gate: excluded `SecureEnclaveKeyStore.swift` +
   `DCAppAttestAttestationService.swift` (0% on simulator by design — Secure
   Enclave / App Attest). Core/ coverage 64.37% → 73.15%, clears the 70% gate.
9. `fce79d5` — added `workflow_dispatch` trigger to `ci-device.yml` (the one
   originally-planned change).

## ⛔ BLOCKED — Device CI codesigning

`ci-device.yml` builds the device test target now, but fails codesigning the
XCTest injection dylibs: **`errSecInternalComponent`**. The self-hosted runner's
`codesign` cannot use the signing key non-interactively.

The user ran `security set-key-partition-list` once — it did NOT fix it.

### RESUME HERE — device CI

**Step 1 (user, on the runner host = `Bakytbeks-MacBook-Pro`).** In a Terminal:
```
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "<login password>" ~/Library/Keychains/login.keychain-db
launchctl kickstart -k gui/$(id -u)/actions.runner.beckinfonet-validation-ledger-mobile.Bakytbeks-MacBook-Pro
```
If that still fails: run the runner interactively in the logged-in desktop
session instead of as a LaunchAgent — `cd ~/actions-runner && ./run.sh` — so it
inherits the unlocked GUI keychain.

**Step 2.** Re-run the device job:
`gh run rerun --failed <latest ci-device.yml run id>` (or push any commit).

**Step 3.** Triage. Once codesigning passes, the device tests build + run on the
iPhone 16. Next watched risk: `AppAttestRoundTripTests` calls Apple's App Attest
servers — needs the App Attest entitlement in the signed build.

## REMAINING WORK (after device CI is green)

- **Part C — gate `main`.** `gh api` PUT branch protection: require status checks
  `device-security-surface` + `CI (Simulator) / test`, strict (up-to-date).
  Verify with a throwaway PR carrying a deliberate device-test failure.
- **Part D — close out.**
  - `.planning/phases/04-*/04-10-SUMMARY.md`: `status: checkpoint_pending` → `complete`;
    fill `requirements_completed` (CI-03, DEV-04).
  - `docs/ci.md`: tick the Plan 04-10 Task 5 HUMAN-UAT checklist.
  - `ROADMAP.md`: mark Phase 4 `[x]` — "(completed 2026-05-16, 5 visual UAT items pending)".
  - `STATE.md`: reconcile (it is stale — claims 27/27 plans / phase 3; truth is
    Phase 4 complete on disk, 38/38 plans).
- **Merge PR #1.**

If device CI signing stays blocked: fallback is to merge PR #1 with the simulator
CI green, gate `main` on `CI (Simulator) / test` only, and treat device-CI signing
as separate follow-up.

## Environment facts (verified 2026-05-16)

- Self-hosted runner `Bakytbeks-MacBook-Pro` online (labels `self-hosted, macOS, ARM64, device`).
- Connected device: iPhone 16, `DEVICE_UDID` secret = `00008140-000E15E83EE9801C` (set).
- `gh` CLI installed + authed (beckinfonet, repo+workflow scopes).
- `gsd-sdk query init.*` is broken on this machine (`structuredClone` — old Node);
  work around it with plain `git` / `gh`.

## OUT OF SCOPE (do not do here)

- The 5 visual/perceptual items in `04-HUMAN-UAT.md` (stays `status: partial`).
- The Phase 1–3 verification debt (15 human_needed items).
