---
phase: 05-kyc-capture-upload-pipeline
reviewed: 2026-05-18T18:00:00Z
depth: standard
review_scope: gap-closure (plans 05-11/05-12/05-13 — device-UAT automation)
files_reviewed: 10
files_reviewed_list:
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/App/AppContainer.swift
  - validationLedger/Core/Storage/KYCSessionStore.swift
  - validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift
  - validationLedgerUITests/KYCForceQuitResumeUITests.swift
  - validationLedgerUITests/KYCProfileEntryUITests.swift
  - validationLedgerUITests/KYCHardGateUITests.swift
  - validationLedgerUITests/KYCCaptureLifecycleUITests.swift
  - .github/workflows/ci-device.yml
  - docs/ci.md
findings:
  critical: 1
  warning: 5
  info: 4
  total: 10
status: issues_found
---

# Phase 5: Code Review Report (gap-closure — device-UAT automation)

**Reviewed:** 2026-05-18T18:00:00Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Reviewed the Phase 5 gap-closure changes (plans 05-11/05-12/05-13 — device-UAT
automation — plus three checkpoint-resolution fixes) against base `60270ca`.
This review supersedes the prior gaps-only review (plans 05-09/05-10), which is
preserved in git history; the scope here is strictly the 05-11/12/13 diff.

The change set adds a `-KYCTestSeedForUITest` DEBUG launch-argument seam
(SceneDelegate + AppContainer + KYCSessionStore), four device XCUITest classes,
a `kyc_status` fix to the existing MockOTP fixture, and CI-device wiring.

The `#if DEBUG` gating is consistently applied — the new seam (enum, static,
init-time consumption, scene-connect parsing, biometric-lock suppression,
KYCSessionStore helper) is uniformly inside `#if DEBUG`, and the seeded
credential values are fixed synthetic placeholders carrying no real PII. The
Release-zero-footprint threat-model story holds.

However, the seam has a real correctness bug (CR-01): the
`AppContainer.kycTestSeed` static is **never reset to `nil`** after consumption,
so the DEBUG seeding side-effect — destructive Keychain + on-disk writes —
re-fires on every `AppContainer` constructed for the remainder of the process,
including the throwaway probe container, the real `presentRoot` container, and
every later role / network-config swap. Several quality issues compound it: the
seam never calls `MockURLProtocol.reset()` and leaves its fixture source
implicit, the throwaway container spins up and orphans a full composition root,
the biometric-lock suppression is over-scoped, the `.midUpload` seed is
internally inconsistent, and a capture-lifecycle XCUITest hard-fails (rather
than skips) on the simulator.

No structural pre-pass (`<structural_findings>`) was provided.

## Critical Issues

### CR-01: `AppContainer.kycTestSeed` static is never cleared — KYC seed re-fires on every subsequent container construction

**File:** `validationLedger/App/SceneDelegate.swift:242-254`,
`validationLedger/App/AppContainer.swift:107`, `523-589`

**Issue:**
The `-KYCTestSeedForUITest` block sets the process-global static
`AppContainer.kycTestSeed = seed` (SceneDelegate.swift:245) and never clears it.
`AppContainer.init` reads that static and, when non-nil, **unconditionally
re-writes the Keychain `session`-scope state** (`sessionToken`, `sessionRole`,
`kycStatus`) and — for `.midUpload` — re-seeds the on-disk `KYCSessionStore`
(AppContainer.swift:523-589).

Every `AppContainer` is a fresh instance per ADR-0002, and the static persists
for the whole process. The seam therefore re-seeds on **every** subsequent
container construction in the process:

1. The throwaway probe container at SceneDelegate.swift:251 — seeds once.
2. The real `presentRoot` container at SceneDelegate.swift:400/406 — seeds again.
3. Any DevMenu NetworkConfig swap (`presentRoot(.role(.shipper))`) — seeds again.
4. Any role swap / re-`presentRoot` — seeds again.

Concrete consequences:

- **`.midUpload` resume semantics are silently corrupted.** The
  `KYCForceQuitResumeUITests` header (KYCForceQuitResumeUITests.swift:18-21)
  explicitly states "The seam RE-SEEDS on every launch" and frames its
  assertions around that — but the re-seed is not per-launch, it is
  per-`AppContainer`. If the app under test ever performs a real chunk upload
  that advances `chunksAcked` past 5 (or commits the artifact), the *next*
  `AppContainer` construction overwrites that progress back to
  `chunksAcked == 5, committed == false`. The test's stated goal — proving the
  *persisted* session survives a kill — is undermined by a seam that clobbers
  persisted progress every time a container is built.
- **`.underReview` / `.midUpload` re-writes `kycStatus = "verified"` and a
  synthetic `sessionToken` repeatedly**, resurrecting an authenticated session
  even after a logout. `LogoutService.logout` wipes the `session`-scope Keychain
  (including `kycStatus`), and the KYCCoordinator sign-out path
  (AppCoordinator.swift:113-118) routes through it. But the very next
  `AppContainer` the SceneDelegate builds re-seeds the verified session, so a
  logout inside a seeded UITest cannot actually reach a clean `.needsAuth`
  state — the seam re-authenticates the user behind the test's back. Any future
  UITest exercising logout under the seed will observe non-deterministic
  routing.
- It weakens the threat-model claim the surrounding comments make
  (AppContainer.swift:88-92, 519-522). The Release claim still holds (the block
  is `#if DEBUG`), but within DEBUG the seam is far stickier than the comments
  describe — they say it seeds "BEFORE the probe runs," with no acknowledgement
  that it also runs on every later container for the rest of the process.

The `-MockOTPRoleForUITest` precedent this code claims to mirror does NOT have
this problem: its static overrides (`uiTestLocationProvider`,
`uiTestCountryGate`, `uiTestTrustTierOverride`) are *idempotent reads* — a stub
provider, a tier value; re-reading them has no side effect. `kycTestSeed` is
different: consuming it performs *destructive Keychain + disk writes*. A
side-effecting seed static must be cleared after first consumption.

**Fix:**
Clear the static inside the `#if DEBUG` consumption block in `AppContainer.init`
immediately after reading it, so the seed fires exactly once (the throwaway
probe container), and the real `presentRoot` container then sees the genuine
seeded Keychain state via the probe — not a re-seed:

```swift
#if DEBUG
if let seed = AppContainer.kycTestSeed {
    AppContainer.kycTestSeed = nil   // consume-once: seed exactly the first container
    // ... existing seeding body ...
}
#endif
```

This matches the SceneDelegate comment at lines 247-253 ("Throwaway container
TRIGGERS the DEBUG seeding side-effect ... presentRoot below builds a fresh,
fully-wired container"). With consume-once, the throwaway container writes the
Keychain + on-disk seed, and the real container relies on that already-written
state. Confirm in a test run that the throwaway container's `KYCSessionStore`
and the real container's both resolve to the same Application Support directory
(they should — neither injects a `directory:`), so the on-disk `.midUpload` seed
survives for the test.

## Warnings

### WR-01: `-KYCTestSeedForUITest` seam never calls `MockURLProtocol.reset()` and leaves its fixture source implicit

**File:** `validationLedger/App/SceneDelegate.swift:231-256`

**Issue:**
The seam forces `.mock` network config (line 244) so `MockURLProtocol`
intercepts `GET /kyc/status` and the KYC upload routes, and the test headers
(KYCProfileEntryUITests.swift:8-11, 68-70) rely on the plan 05-09 mock fixtures
serving an `under_review` verdict. But the seam never calls
`MockURLProtocol.reset()` and never registers any fixtures itself — unlike
`-MockOTPRoleForUITest`, whose `MockOTPRoleFixtureRegistry.registerForRole` opens
with `MockURLProtocol.reset()` (MockOTPRoleFixtureRegistry.swift:37).

The fixture registration the seam depends on happens implicitly in
`AppContainer.init`: `MockDefaultFixtures.registerAppDefaults()` runs when
`.mock` AND `-MockOTPRoleForUITest` is NOT present (AppContainer.swift:427-432).
The KYC seam satisfies that guard, so defaults *do* register — but the guard
condition does not mention `-KYCTestSeedForUITest` at all, and with CR-01
unfixed it registers on *every* container construction with no `reset()` between
them. The seam's correctness depends on a registration branch in a different
file whose guard is incidental, not intentional.

**Fix:**
Make the fixture contract explicit: either register the KYC fixtures directly in
the `-KYCTestSeedForUITest` block (with a leading `MockURLProtocol.reset()`,
mirroring `registerForRole`), or add an explicit comment + the
`-KYCTestSeedForUITest` term to the `AppContainer.init` guard so it is clear
`MockDefaultFixtures.registerAppDefaults()` is the deliberate provider for this
seam and serves the `under_review` `/kyc/status` verdict the device tests
require. Do not leave the fixture source implicit.

### WR-02: Throwaway probe container spins up and orphans a full composition root

**File:** `validationLedger/App/SceneDelegate.swift:251`

**Issue:**
`_ = AppContainer(env: .current, networkConfig: .mock)` constructs a full
`AppContainer` purely for its DEBUG seeding side-effect, then discards it. Unlike
the `-MockOTPRoleForUITest` `scrubContainer` (also a throwaway, but it only does
a stateless Keychain `deleteAll`), this throwaway builds the *entire* dependency
graph: `keyStore`, `apiClient` (URLSession), `attestationService` (with
preflight logging), `kycSessionStore`, `kycUploader`, a stand-alone
`kycUploadScheduler`, etc.

`SessionRestoreProbe` exists specifically because "construct an AppContainer and
throw it away" is the wrong pattern — its header (SessionRestoreProbe.swift
lines 11-16) documents the observer-leak hazard of throwaway containers
(`DefaultSessionLockService` subscribes to `UIApplication` notifications). The
KYC seam reintroduces exactly the throwaway-container pattern that helper was
written to avoid. The orphaned graph also emits a confusing extra
`app_container_init` / `app_container_deinit` log pair that will mislead anyone
reading device-CI logs.

**Fix:**
Extract the DEBUG seeding logic into a static helper (e.g.
`AppContainer.applyKYCTestSeed(_:)`) that constructs only a `KeychainStore` and a
`KYCSessionStore` — the two stores the seed actually writes — and call it from
the SceneDelegate block instead of constructing a full `AppContainer`. This
mirrors `SessionRestoreProbe`'s minimal-surface discipline and removes the
orphaned graph plus the duplicate init/deinit logs.

### WR-03: Biometric-lock suppression is over-scoped — it silently disables the SESS-02 foreground re-prompt as well as the SESS-01 cold-boot lock

**File:** `validationLedger/App/SceneDelegate.swift:475-487`

**Issue:**
`presentBiometricLockIfNeeded` now early-returns whenever
`-KYCTestSeedForUITest` is present (SceneDelegate.swift:486). The intent is
documented and `#if DEBUG`-gated, so there is no Release impact — that part is
sound.

The problem is scope: the suppression is unconditional for the whole process and
covers *both* call sites of `presentBiometricLockIfNeeded` — the cold-boot
`.role` restore (SESS-01) AND `handleDidBecomeActive` (SESS-02, the >5-min
background-timeout re-prompt). `KYCCaptureLifecycleUITests` deliberately
backgrounds (`press(.home)`) and foregrounds (`activate()`) the app under the
seed; with the seam active, `handleDidBecomeActive` will never present the
biometric lock on foreground. Any future seeded UITest intended to exercise the
SESS-02 background-timeout re-prompt is silently impossible, and a regression
breaking SESS-02 would not be caught on the device lane while the seam is
active. The comment (lines 477-486) only mentions the cold-boot SESS-01 case; it
does not acknowledge SESS-02 is also disabled.

**Fix:**
Narrow the suppression to the cold-boot path only — pass a `suppressForUITest`
flag from `presentRoot(_:checkLockState:)` into `presentBiometricLockIfNeeded`,
and leave `handleDidBecomeActive` free to present the lock — or, at minimum,
update the comment to state that SESS-02 foreground re-prompt is also suppressed
and record it in `docs/ci.md` as a known device-lane coverage gap.

### WR-04: `KYCCaptureLifecycleUITests` hard-fails on the simulator instead of skipping

**File:** `validationLedgerUITests/KYCCaptureLifecycleUITests.swift:77-119`

**Issue:**
The test header (lines 24-30) correctly states the test "is meaningful only on
the device CI lane" and "is simply not expected to pass on the simulator" —
because the simulator produces no camera frames, so the Vision face-quality gate
never reaches `.readyToCapture` and the shutter stays disabled. The CI-device
workflow scopes the device lane to this class explicitly (ci-device.yml:126).

But the test has no skip guard. `XCTAssertTrue(shutter.isHittable, ...)`
(line 113) is an unconditional hard assertion. If this class runs on a simulator
destination — a developer running the whole `validationLedgerUITests` target
locally, or a future CI change — it produces a hard red failure, not a skip. A
test known to fail on a whole class of destinations should `XCTSkip` on that
destination so it self-documents and cannot produce a misleading red.

**Fix:**
Add an explicit simulator skip at the top of the test:

```swift
#if targetEnvironment(simulator)
throw XCTSkip("Test 10 requires live camera frames — device lane only.")
#endif
```

The test bundle runs on the same destination as the host, so
`targetEnvironment(simulator)` in the test target correctly identifies the sim
destination.

### WR-05: `seedMidUploadStateForUITest` seeds `localDataAvailable: true` with no corresponding `artifactData` — an internally inconsistent on-disk session

**File:** `validationLedger/Core/Storage/KYCSessionStore.swift:271-294`

**Issue:**
The seeded `ArtifactUploadState` sets `localDataAvailable: true` (line 289),
which by its own contract (`ArtifactUploadState.swift:57-59`) means the local
artifact `Data` copy exists. But `seedMidUploadStateForUITest` only writes
`session.uploadStates[...]` (KYCSessionStore.swift:291-293) — it never populates
`session.artifactData["face"]`. The seeded session therefore claims the local
face-image bytes are available while `KYCSession.data(for: .face)` returns `nil`.

A real interrupted mid-upload always still holds its `artifactData` blob (the
bytes are only freed at commit, per `commitAndFreeArtifactData`). A resume cursor
that says "localDataAvailable, 5/12 acked" with zero bytes on disk is a state the
production code never produces. The current four XCUITests do not trigger a real
`resumeAllPendingUploads` (the `KYCForceQuitResumeUITests` comment at lines 22-29
says it asserts only that the role shell + status screen render) — so this does
not break the *current* tests, but it is a latent trap: the seed is named
"mid-upload," and a future test that actually drives `resumeAllPendingUploads`
against it will hit a `nil`-artifact-data path mid-upload.

**Fix:**
Either seed a non-empty synthetic `artifactData["face"]` blob (a few KB of zeroed
`Data` is fine for a test — well under the multi-MB real size, document it as
synthetic per the existing T-05-11-03 PII note), or set
`localDataAvailable: false` and add a comment that this seed models the
post-commit cursor only, not a resumable upload. Given the SC-2 intent is
"force-quit *mid-upload*," seeding the synthetic blob is the faithful choice.

## Info

### IN-01: `seedMidUploadStateForUITest` magic numbers should be named constants

**File:** `validationLedger/Core/Storage/KYCSessionStore.swift:273-278`

**Issue:** `512 * 1024`, `12`, and `12 * chunkSize - 1` are inline literals.
They are explained well in the comment, but the `-1` "partial trailing chunk"
trick is the kind of off-by-one that silently breaks if someone edits
`totalChunks` without re-deriving `totalBytes`.

**Fix:** Hoist to named `private static let` constants (`seedChunkSize`,
`seedTotalChunks`) and keep the comment explaining the intentional
`totalChunks * chunkSize - 1`.

### IN-02: Four XCUITest files duplicate the `launch(seed:)` / heading-query / `setUp()` helpers verbatim

**File:** `validationLedgerUITests/KYCProfileEntryUITests.swift:44-58`,
`KYCHardGateUITests.swift:40-55`, `KYCCaptureLifecycleUITests.swift:57-70`,
`KYCForceQuitResumeUITests.swift:60-80`

**Issue:** `launch(seed:)`, the `descendants(matching:.any)[...]` heading-query
helper, and the `setUp()` body (`executionTimeAllowance = 30`,
`continueAfterFailure = false`) are copy-pasted across all four new XCUITest
classes. `waitForHittable` exists only in `KYCForceQuitResumeUITests` but is the
same device-flake mitigation the other classes would benefit from.

**Fix:** Extract a shared `KYCUITestCase: XCTestCase` base class holding
`launch(seed:)`, the query helper, `waitForHittable`, and the `setUp()` defaults.
Lower priority — test code, small duplication — but it will drift as the suite
grows.

### IN-03: `docs/ci.md` "Device Pipeline" section still documents the pre-Phase-5 25-min timeout and step list

**File:** `docs/ci.md:54`, `60`, `70-76`

**Issue:** `docs/ci.md` line 54 still says "**Timeout:** 25 min", and the "Steps"
list (56-64) / "Coverage (D-13)" suite list (70-76) describe only the in-process
`validationLedgerDeviceTests` surface. The new "Phase 5 Device XCUITest Lane"
section (130-167) correctly documents the 25 → 35 bump and the four XCUITest
classes — so the document contradicts itself: one section says 25 min and lists
only device tests, a later section says 35 min and adds four XCUITests. The
actual workflow is `timeout-minutes: 35` (ci-device.yml:77).

**Fix:** Update the "Device Pipeline" section (lines 54, 60) to say 35 min and
reference the Phase 5 XCUITest lane, or add a forward-pointer so the two
sections do not read as contradictory.

### IN-04: `ci-device.yml` `changes`-job `PATTERN` was extended but `docs/ci.md`'s "Security surface" bullet list was not

**File:** `docs/ci.md:46-48`, `.github/workflows/ci-device.yml:55`

**Issue:** The workflow `PATTERN` regex now includes `validationLedgerUITests/`
(ci-device.yml:55, mentioned at docs/ci.md:164). But the canonical "Security
surface — the device job runs when a PR touches any of:" bullet list at
docs/ci.md:46-48 was not updated to include `validationLedgerUITests/**`. A
reader checking that list to predict whether their PR triggers the device lane
gets the wrong answer.

**Fix:** Add `validationLedgerUITests/**` to the bullet list at docs/ci.md:46-48
so the documented security surface matches the regex in the workflow.

---

_Reviewed: 2026-05-18T18:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (gap-closure — plans 05-11/05-12/05-13)_
