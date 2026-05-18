---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
plan: 03
subsystem: app-shell
tags: [trust-tier, app-attest, dev-04, keychain, limited-trust-banner, kyc-status, uikit]

requires:
  - phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume (Plan 01)
    provides: KeychainKey.trustTier + AttestedKeyStore.readTrustTier()/writeTrustTier()
  - phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume (Plan 02)
    provides: OTPViewModel STEP 5 persists /device/register trustTier to Keychain (producer)
provides:
  - AppContainer seeds AppSession.trustTier from the persisted device.trustTier Keychain item (D6-01 consumer)
  - AppSession.trustTier is observable — .trustTierDidChange Notification posted from a didSet (D6-10)
  - LimitedTrustBannerContainerViewController — a re-renderable banner host; the banner appears/removes on a trustTier mutation
  - uiTestTrustTierOverride DEBUG seam deleted at all 3 sites (D6-03)
  - KYCStatusViewModel refreshes Keychain .kycStatus after a successful GET /kyc/status (D6-08)
  - Profile-entry KYC status "Continue" CTA dismisses/pops the screen back to the Profile tab (D6-09)
affects: [trust-tier consumers, KYC status routing, role-shell banner, future heartbeat plans]

tech-stack:
  added: []
  patterns:
    - "Observable plain @MainActor class via NotificationCenter — a Notification.Name posted from a property didSet, scoped to the instance as the post `object`; the project's .sessionDidInvalidate precedent. NO SwiftUI @Observable/ObservableObject (UIKit-first)."
    - "Re-renderable UIKit banner: a parent container VC hosts the tab bar as a child + toggles the banner subview in place on update(trustTier:) — no root-swap, no animation (ADR 0002 abrupt-replace)."
    - "Keychain cache-refresh after a typed-endpoint success: mirror the OTPViewModel .kycStatus write exactly (.afterFirstUnlockThisDeviceOnly); a write failure degrades gracefully and never breaks the fetch."

key-files:
  created:
    - validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift
    - validationLedgerTests/App/AppSessionTrustTierObservationTests.swift
  modified:
    - validationLedger/App/AppSession.swift
    - validationLedger/App/AppContainer.swift
    - validationLedger/App/AppCoordinator.swift
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/UI/LimitedTrustBannerView.swift
    - validationLedger/Roles/RoleCoordinator.swift
    - validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift
    - validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
    - validationLedgerTests/KYC/KYCStatusViewModelTests.swift
    - validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift

key-decisions:
  - "D6-10 observation mechanism: NotificationCenter (Option A), not a closure (Option B) — AppCoordinator and AppSession are constructed separately by SceneDelegate, and the project's .sessionDidInvalidate is the precedent for exactly this cross-object UIKit observation; the post is scoped to the AppSession instance so a sibling/dropped container cannot drive the wrong banner."
  - "wrapWithLimitedTrustBanner now ALWAYS returns a LimitedTrustBannerContainerViewController (even on the .hardwareAttested branch) — Phase 4 returned the bare tab bar on that branch, which made the banner un-re-renderable; the container is required so a mid-session tier mutation can add a banner."
  - "D6-09 Profile Continue CTA: pop when the KYC status VC is on a UINavigationController (the Profile push path), dismiss when presented modally (the defensive fallback) — discovered from ProfileViewController.kycStatusTapped(); NOT the KYCCoordinator onKYCSubmitted role-shell routing."
  - "Verification simulator switched from plan-specified 'iPhone 16' (unavailable on this host) to 'iPhone 17' (Rule 3 — blocking issue); identical substitution to Plans 06-01/06-02."

patterns-established:
  - "Observable plain @MainActor class via a Notification.Name posted from a didSet."
  - "Re-renderable banner container VC that toggles a subview in place (no root-swap)."

requirements-completed: [DEV-04]

duration: 24min
completed: 2026-05-18
---

# Phase 6 Plan 03: trustTier Consumer + Folded Audit Fixes Summary

**The role-shell `AppContainer` seeds `AppSession.trustTier` from the persisted `device.trustTier` Keychain item, `AppSession.trustTier` becomes observable so the `LimitedTrustBanner` re-renders on mutation, the DEBUG `uiTestTrustTierOverride` seam is deleted, `KYCStatusViewModel` refreshes the cached `kycStatus` after `GET /kyc/status`, and the Profile-entry KYC "Continue" CTA dismisses back to the Profile tab.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-05-18T15:22:00Z
- **Completed:** 2026-05-18T15:46:00Z
- **Tasks:** 2
- **Files modified:** 12 (8 source, 2 new test files, 2 test files edited)

## Accomplishments

- **D6-01 consumer closed.** `AppContainer.init` replaces the old `#if DEBUG` `AppSession`-construction branch with `let seededTrustTier = (try? attestedKeyStore.readTrustTier()) ?? .softwareOnly`. The auth-phase `trustTier` (Plan 06-02 persists it to Keychain) now survives the ADR 0002 abrupt-replace and re-hydrates on both the post-OTP role shell and a cold-boot restore — the cross-phase wiring break the v1.0 audit found is closed.
- **D6-10 / WARNING-2 — `AppSession.trustTier` is observable.** A `didSet` posts `.trustTierDidChange` (a new `Notification.Name`, scoped to the `AppSession` instance, carrying the new tier's `rawValue` in `userInfo`). `AppSession` stays a plain `@MainActor final class` — NO SwiftUI `@Observable`/`ObservableObject` (CLAUDE.md UIKit-first). `AppCoordinator` subscribes for the `.role` phase and re-renders the banner with no animation, no root-swap.
- **Re-renderable banner.** New `LimitedTrustBannerContainerViewController` hosts the role tab bar as a child and shows/removes the `LimitedTrustBannerView` on `update(trustTier:)`. `wrapWithLimitedTrustBanner` now always returns this container (Phase 4 returned the bare tab bar on the hardware-attested branch, which could not later grow a banner).
- **D6-03 — `uiTestTrustTierOverride` deleted at all 3 sites:** the declaration + comment block (`AppContainer`), the `#if DEBUG` seed-read branch (subsumed by the Keychain seed read), and the `SceneDelegate` write. `grep -rn uiTestTrustTierOverride validationLedger/` returns 0. The `-MockOTPTrustTierForUITest` launch arg, the `uiTestTrustTier` computation, and `MockOTPRoleFixtureRegistry.registerForRole` are kept — the fixture path now drives the real consumer end-to-end.
- **D6-08 / WARNING-1 — `kycStatus` refresh.** `KYCStatusViewModel.init` grows a `KeychainStore` param; `fetchStatus()` refreshes Keychain `.kycStatus` after a successful `GET /kyc/status` (mirroring `OTPViewModel`'s write exactly — `.afterFirstUnlockThisDeviceOnly`). Fail-closed routing is preserved — a non-`verified` status is cached verbatim and still routes the cold-boot probe to the KYC gate. A Keychain-write failure degrades gracefully.
- **D6-09 — Profile "Continue" CTA.** `AppContainer.makeKYCStatusScreen()` wires `viewModel.onVerified` to dismiss/pop the status screen back to the Profile tab — NOT the `KYCCoordinator` `onKYCSubmitted` role-shell routing (nonsensical from a Profile entry already inside the role shell).

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1 RED: failing tests — AppSession observation + AppContainer seeding** — `d7720cc` (test)
2. **Task 1 GREEN: observable AppSession.trustTier + AppContainer Keychain seeding + delete uiTest override** — `36872ec` (feat)
3. **Task 2 RED: failing tests — kycStatus Keychain refresh** — `3f8769f` (test)
4. **Task 2 GREEN: kycStatus refresh after GET /kyc/status + Profile Continue CTA** — `1dbfa15` (feat)

No REFACTOR commits — both GREEN implementations needed no follow-up cleanup.

## Files Created/Modified

- `validationLedger/App/AppSession.swift` — `trustTier` `didSet` posts `.trustTierDidChange`; added the `Notification.Name` + `trustTierUserInfoKey`. Still a plain `@MainActor final class`.
- `validationLedger/App/AppContainer.swift` — seeds `AppSession` via `readTrustTier()`; deleted the `uiTestTrustTierOverride` declaration; `makeKYCStatusScreen()` passes `keychainStore` + wires `onVerified`.
- `validationLedger/App/AppCoordinator.swift` — `.role` case builds + retains a `LimitedTrustBannerContainerViewController`; subscribes to `.trustTierDidChange` (scoped to `container.session`) and re-renders the banner; observer torn down in `deinit`.
- `validationLedger/App/SceneDelegate.swift` — deleted the `uiTestTrustTierOverride` write line; kept the `-MockOTPTrustTierForUITest` parsing + `registerForRole`.
- `validationLedger/UI/LimitedTrustBannerView.swift` — added `LimitedTrustBannerContainerViewController` (the re-renderable banner host).
- `validationLedger/Roles/RoleCoordinator.swift` — `wrapWithLimitedTrustBanner` now always returns the container VC.
- `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift` — `init` grows a `KeychainStore` param; `fetchStatus()` refreshes `.kycStatus` via `refreshCachedKYCStatus(_:)`.
- `validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift` — `pushStatus()` passes `container.keychainStore`; its `onVerified` post-submit routing unchanged.
- `validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift` (new) — 3 `@Test`: seeds from `.hardwareAttested` / `.softwareOnly` / falls back to `.softwareOnly` when absent.
- `validationLedgerTests/App/AppSessionTrustTierObservationTests.swift` (new) — 2 `@Test`: mutation posts the notification with the new tier; the post is instance-scoped.
- `validationLedgerTests/KYC/KYCStatusViewModelTests.swift` — 3 new `@Test`: verified-fetch caches `verified`; non-verified-fetch caches the value verbatim (fail-closed preserved); a fresh status overwrites a stale cached value.
- `validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift` — construction-site updated for the new `keychain:` param (Rule 3).

## Decisions Made

- **D6-10 mechanism — NotificationCenter, not a closure.** `AppCoordinator` and `AppSession` are constructed separately by `SceneDelegate`/`AppContainer`; the project's `.sessionDidInvalidate` is the established precedent for cross-object UIKit observation. The post is scoped to the `AppSession` instance (`object:`) so a sibling scene or a dropped (root-swapped) container cannot drive the wrong banner. A closure (`OTPViewModel.onStateChange` precedent) would couple `AppSession` to whoever wired it; the notification keeps `AppSession` decoupled.
- **`wrapWithLimitedTrustBanner` always returns the container.** Phase 4 returned the bare tab bar on the `.hardwareAttested` branch. That made the banner un-re-renderable — a mid-session downgrade had no parent VC to host a banner. Always installing `LimitedTrustBannerContainerViewController` is the minimal change that makes D6-10 possible.
- **D6-09 dismissal — pop or dismiss, decided at tap time.** `ProfileViewController.kycStatusTapped()` *pushes* the KYC status VC onto Profile's `UINavigationController` (primary path) with a modal-present fallback. `onVerified` therefore pops when the VC is on a nav stack (and is not the nav root), otherwise dismisses. The VC is captured weakly (the VM owns the closure, the VC owns the VM — a strong capture would cycle).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `KYCEndToEndIntegrationTests` construction site needed the new `keychain` param**
- **Found during:** Task 2 GREEN (first `xcodebuild test` of `KYCStatusViewModelTests`).
- **Issue:** Adding the required `keychain:` parameter to `KYCStatusViewModel.init` broke a fourth, un-listed construction site — `validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift:106` — with `error: missing argument for parameter 'keychain'`. The plan named only two construction sites (`AppContainer.makeKYCStatusScreen()` + `KYCCoordinator.pushStatus()`).
- **Fix:** Passed a uniquely-serviced test `KeychainStore(service: "vl.test.kyc.e2e.\(UUID())")` at that site — the same isolated-partition pattern the other KYC test suites use.
- **Files modified:** `validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift` (committed in Task 2's `1dbfa15`).
- **Verification:** `KYCStatusViewModelTests` and `KYCEndToEndIntegrationTests` both compile and pass.
- **Committed in:** `1dbfa15`.

**2. [Rule 3 - Blocking] Verification simulator destination unavailable**
- **Found during:** Task 1 / Task 2 verification.
- **Issue:** The plan's `<verify>` blocks specify `platform=iOS Simulator,name=iPhone 16`, which is not installed on this host (per the executor environment note — available: iPhone 17 / 17 Pro / Air / 16e).
- **Fix:** Ran all build/test commands against `name=iPhone 17`. The destination is the only change; scheme, test targets, and `-only-testing` filters are exactly as the plan specifies. Identical substitution to Plans 06-01 and 06-02.
- **Files modified:** None (verification-command-only change).
- **Committed in:** N/A.

---

**Total deviations:** 2 auto-fixed (both Rule 3 - Blocking).
**Impact on plan:** Both were necessary to compile/verify; neither expanded scope. The fourth construction site is a direct consequence of the planned `KYCStatusViewModel.init` signature change.

## Issues Encountered

- **Cross-suite `MockURLProtocol` race on a combined run.** Running 9 `MockURLProtocol`-driving suites in one `xcodebuild test` process produced 5 spurious failures (`KYCStatusViewModelTests` saw `.underReview` instead of `.pending`; others saw `404`/`dev-mock-otp-session`) — a sibling suite's fixtures leaking through the global handler registry. This is the documented known race in the executor environment note (`.serialized` only serializes *within* a suite, not *across* suites). Each affected suite passes cleanly in isolation — confirmed standalone for `KYCStatusViewModelTests` (8/8), `AppContainerNetworkConfigTests` (4/4), and `KYCEndToEndIntegrationTests` (2/2). Verification was therefore done in race-safe groupings (one process per `MockURLProtocol` suite). Not a regression from this plan.

## Verification

- `AppContainerTrustTierSeedingTests` + `AppSessionTrustTierObservationTests` (iPhone 17) — **5 tests in 2 suites pass, 0 failures**.
- `KYCStatusViewModelTests` (iPhone 17, run standalone) — **8 tests pass, 0 failures** (5 pre-existing + 3 new D6-08).
- Race-safe Group A (`AppContainerTrustTierSeedingTests`, `AppSessionTrustTierObservationTests`, `AppCoordinatorPhase3RoutingTests`, `AttestedKeyStoreTrustTierTests`, `KeychainScopeTests`, `KYCCoordinatorTests`) — **31 tests in 6 suites pass, 0 failures**.
- `AppContainerNetworkConfigTests` (standalone) — 4/4 pass; `KYCEndToEndIntegrationTests` (standalone) — 2/2 pass — confirming the combined-run failures are the known cross-suite `MockURLProtocol` race, not a regression.
- `validationLedgerUITests/LimitedTrustBannerTests` (iPhone 17 UI lane) — **2 tests pass, 0 failures**. The `uiTestTrustTierOverride` seam is gone; the `-MockOTPTrustTierForUITest` fixture path drives the real `OTPViewModel -> Keychain -> AppContainer` seed consumer end-to-end for both `.softwareOnly` (banner visible) and `.hardwareAttested` (banner absent) — 06-RESEARCH Pitfall 6 confirmed.
- `grep -rn 'uiTestTrustTierOverride' validationLedger/` — **0 matches** (declaration, comment, and all 3 sites removed).
- `grep -c 'uiTestLocationProvider'` / `'kycTestSeed'` / `'MockOTPRoleFixtureRegistry.registerForRole'` in `SceneDelegate.swift` — unchanged (1 / 3 / 1).
- `AppContainer.swift` references `readTrustTier`; `AppCoordinator.swift` subscribes to `trustTierDidChange`; `KYCStatusViewModel.swift` writes `.kycStatus`; `AppSession.swift` has no `ObservableObject`/`@Observable` conformance (the single grep match is the doc comment stating it is deliberately absent).

## TDD Gate Compliance

Both tasks carry `tdd="true"` and the RED → GREEN gate sequence is satisfied in git history:
1. **Task 1** — `test(06-03)` (`d7720cc`) landed the 5 tests RED (they reference `.trustTierDidChange` / `AppSession.trustTierUserInfoKey`, not yet present); `feat(06-03)` (`36872ec`) landed the GREEN implementation; all 5 pass.
2. **Task 2** — `test(06-03)` (`3f8769f`) landed the 3 D6-08 tests RED (they call `KYCStatusViewModel.init` with the not-yet-added `keychain:` param — a compile-level RED); `feat(06-03)` (`1dbfa15`) landed the GREEN implementation; all 8 `KYCStatusViewModelTests` pass.

No REFACTOR commits — neither GREEN implementation needed follow-up cleanup. `tdd_mode` is `false` in `config.json` and the orchestrator passed neither `MVP_MODE` nor `TDD_MODE`, so the MVP+TDD runtime gate does not apply.

## Known Stubs

None. No hardcoded empty values, placeholder text, or unwired data sources were introduced.

## Next Phase Readiness

- The consumer half of the DEV-04 trustTier flow is complete: producer (06-02) → Keychain → consumer (06-03). The `LimitedTrustBanner` is now honest about the device's current trust state on every role-shell entry and re-renders on a mid-session heartbeat (D-12) mutation.
- All three folded audit fixes (D6-03 seam deletion, D6-08 `kycStatus` refresh, D6-09 Profile CTA) are landed.
- No blockers introduced. The cross-suite `MockURLProtocol` race remains a pre-existing test-infra item (already in Phase 4 deferred-items); it does not affect production code.

---
*Phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume*
*Completed: 2026-05-18*
