---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
reviewed: 2026-05-18T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/App/AppCoordinator.swift
  - validationLedger/App/AppSession.swift
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/Core/Attestation/AttestedKeyStore.swift
  - validationLedger/Core/Storage/Keychain/KeychainKey.swift
  - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
  - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
  - validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
  - validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift
  - validationLedger/Roles/RoleCoordinator.swift
  - validationLedger/UI/LimitedTrustBannerView.swift
  - validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift
  - validationLedgerTests/App/AppSessionTrustTierObservationTests.swift
  - validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift
  - validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
  - validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift
  - validationLedgerTests/KYC/KYCStatusViewModelTests.swift
  - validationLedgerTests/Storage/KeychainScopeTests.swift
findings:
  critical: 1
  warning: 7
  info: 5
  total: 13
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-05-18T00:00:00Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

Phase 6 closes the DEV-04 gap (App Attest at first login), adds the trustTier
producer/consumer flow, and folds three audit fixes. The implementation is
generally careful — PII discipline is consistently observed, the fail-closed
posture is enforced in routing, and the `device.trustTier` Keychain scope
invariant is well-pinned by tests.

However, the App Attest orchestration in `OTPViewModel.verify()` STEP 5 has a
**correctness bug in the trustTier producer path**: the `challengeExpired`
retry-once path is not the only retry vector — the `registerFailed` state
silently overwrites a still-valid prior trustTier under one ordering, and more
importantly there is a **logic gap where a successful login persists a trustTier
but a `registerFailed`/`retryRegister` cycle never re-clears or re-validates
it**. The trustTier persisted to Keychain on a prior partial success is never
reconciled. There is also a real **state-machine bug**: `verify()` enters STEP 1
unconditionally on `retryRegister()` and re-issues `OTPVerify` with a code that
the backend already consumed — the documented "idempotent" claim is false for
the OTP-verify endpoint.

Additionally, the new `.trustTierDidChange` observation channel posts a
notification from `AppSession.init` indirectly-safe path but the
`AppCoordinator` observer uses `MainActor.assumeIsolated` inside a
`NotificationCenter` callback, which is fragile. Several quality issues around
duplicated wiring and a dead code path round out the findings.

## Critical Issues

### CR-01: `retryRegister()` re-issues a consumed OTP code — `verify()` is not idempotent at STEP 1

**File:** `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift:432-435` (and `147-168`)

**Issue:** `retryRegister()` is documented (lines 425-431) as safe to re-run
because "Keychain.set is upsert", "generateDeviceIdentityKeys ... is safe to
re-call", and "/device/register is Idempotency-Key-protected". It calls
`await verify()`, which **unconditionally restarts at STEP 1** —
`apiClient.request(OTPVerifyEndpoint(otpSessionID:code:))`.

The OTP-verify endpoint is a one-time-code consumption endpoint. An OTP code,
once verified, is consumed server-side. On `retryRegister()` the same
`otpSessionID` + `code` is POSTed again. The realistic backend outcomes are:

- HTTP 401 (code already consumed / session expired) → `verify()` hits the
  `statusCode == 401` catch (line 160) and sets `state = .error("Invalid code.
  Try again.")`. The user is now stuck on a generic "invalid code" error after a
  *register* failure they had no way to influence — the recovery path
  (`retryRegister`) actively destroys the recoverable `.registerFailed` state.
- HTTP 429 → restarts the rate-limit countdown spuriously.

The retry path that the entire D-27 "step 5 failure does NOT clear keychain —
retry-able" design rests on is broken: it cannot actually retry STEP 5 in
isolation because it re-runs STEPS 1-4. The `OTPViewModelTests.retryRegisterIsIdempotent`
test does not catch this because `AttestBackend` serves `/auth/otp/verify` with
an unconditional 200 regardless of how many times it is called — the mock does
not model OTP-code single-use, so the test gives false confidence.

**Fix:** Split the orchestration so `retryRegister()` resumes from STEP 5
without re-verifying the OTP. Cache the `OTPVerifyEndpoint.Response` (and the
generated key material) on first success and have `retryRegister()` re-enter at
the register POST:

```swift
// Store STEP 1-4 outputs on first success.
private var verifiedResponse: OTPVerifyEndpoint.Response?
private var generatedDeviceKeys: (devicePub: Data, authPub: Data)?

public func retryRegister() async {
    guard case .registerFailed = state else { return }
    // Resume from STEP 5 only — do NOT re-consume the OTP code.
    guard let resp = verifiedResponse,
          let keys = generatedDeviceKeys else {
        // No cached state — fall back to a full re-verify (rare).
        await verify()
        return
    }
    await runDeviceRegister(verifyResp: resp,
                            devicePub: keys.devicePub,
                            authPub: keys.authPub)
}
```

Update the mock `AttestBackend` to serve `/auth/otp/verify` with a 200 only on
the first call and a 401 thereafter, so the regression is pinned.

## Warnings

### WR-01: A successful register persists `trustTier` but `registerFailed` leaves a stale `device.trustTier` in Keychain

**File:** `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift:282-286`; `validationLedger/Core/Attestation/AttestedKeyStore.swift:106-133`

**Issue:** `device.trustTier` is written on a successful `/device/register`
(line 286, `try? attestedKeyStore.writeTrustTier(...)`). It is intentionally
*never* deleted (`AttestedKeyStore` has no `deleteTrustTier`, and it is excluded
from `LogoutService` teardown — D6-02). Consider this sequence on a single
install:

1. Login A succeeds → `device.trustTier = hardwareAttested` persisted.
2. User logs out. `device.trustTier` survives (by design).
3. Login B on the *same install* — but now the device has been jailbroken /
   App Attest entitlement was pulled / the key was compromised — STEP 5
   degrades (`.error`) or the register POST fails → `state = .registerFailed`,
   and the `writeTrustTier` line at 286 is **never reached**.
4. The user retries, or the app is killed. `AppContainer` (line 421) seeds
   `AppSession.trustTier` from the **stale `hardwareAttested`** Keychain value
   from Login A.

Result: the LimitedTrustBanner is **suppressed** on a session whose backend
posture is unknown/degraded, because the consumer reads a stale tier that no
longer reflects reality. This directly contradicts the stated safety posture
("brief over-showing of the banner is preferable to ever missing it" —
`AppSession.swift:8-11`). The fail-safe only covers *unknown wire values* and
*never-written* state; it does not cover *stale-but-valid* state.

**Fix:** On a `registerFailed` outcome (and on a non-`.attested` STEP-5
degrade), conservatively downgrade the persisted tier rather than leaving the
prior value:

```swift
} catch {
    logger.warn(event: .init("device_register_failed"),
                fields: [.event: String(describing: error)])
    // A failed register must not leave a stale-optimistic tier behind.
    try? attestedKeyStore.writeTrustTier(.softwareOnly)
    state = .registerFailed
    return
}
```

Alternatively, clear `device.trustTier` at logout (it caches a *session-derived*
verdict, not an install-stable identity like `attestedKeyId`) — the D6-02
"preserve like attestedKeyId" rationale is questionable: a trust *tier* is a
backend verdict that can change between logins, unlike the install-bound key id.

### WR-02: `MainActor.assumeIsolated` inside a NotificationCenter callback is fragile

**File:** `validationLedger/App/AppCoordinator.swift:152-166`

**Issue:** The `.trustTierDidChange` observer closure calls
`MainActor.assumeIsolated { ... }`. The observer is registered with
`queue: .main`, so the closure *is* delivered on the main thread — but
`assumeIsolated` asserts main-*actor* isolation, which is a stronger and
runtime-trapping claim. If a future edit changes the registration to
`queue: nil` (deliver on posting thread) — and the post originates from
`AppSession.trustTier.didSet`, which runs wherever the mutation happens — this
becomes a hard crash (`fatalError`) instead of a graceful no-op. The
`AppSession` is `@MainActor` so mutations *should* be main-actor, but the
notification dispatch decouples that guarantee.

The codebase already has the correct pattern: `SceneDelegate`'s
`.sessionDidInvalidate` observer (lines 94-108) is also `queue: .main` and
simply does its work directly without `assumeIsolated`. The
`AppSessionTrustTierObservationTests` mutation observer (line 29-36) likewise
uses no `assumeIsolated`.

**Fix:** Annotate the observer body to inherit main-actor context the same way
sibling observers do, or hop explicitly:

```swift
) { [weak self] note in
    Task { @MainActor in
        guard let self,
              let bannerContainer = self.limitedTrustBannerContainer else { return }
        let raw = note.userInfo?[AppSession.trustTierUserInfoKey] as? String
        let newTier = raw.flatMap { TrustTier(rawValue: $0) } ?? .softwareOnly
        bannerContainer.update(trustTier: newTier)
    }
}
```

This trades the synchronous in-place update for a one-runloop hop but removes
the trap. If synchronous update is required, document the `queue: .main`
coupling as load-bearing.

### WR-03: Cold-boot heartbeat can overwrite a fresh first-login `trustTier` with a stale-session result, and never re-seeds the banner

**File:** `validationLedger/App/SceneDelegate.swift:283-287, 636`; `AppCoordinator.swift:141-167`

**Issue:** On cold-boot `.restored`, `performHeartbeatIfNeeded` runs and on
success does `container.session.trustTier = heartbeatResponse.trustTier`
(SceneDelegate line 636). That mutation posts `.trustTierDidChange`, which the
`AppCoordinator` observer consumes to re-render the banner — good.

But the heartbeat helper is **fire-and-forget** and `performHeartbeatIfNeeded`
*reads* `device.trustTier` from `AppContainer.session` only as the seed; it does
**not** persist the heartbeat's `trustTier` back to `device.trustTier` Keychain
(it only writes `lastHeartbeatAt` — line 637). So:

- First-login persists `device.trustTier` (OTPViewModel).
- Heartbeat updates `AppSession.trustTier` in memory only.
- Next cold boot re-seeds `AppSession` from the now-stale `device.trustTier`
  Keychain value, *not* the last heartbeat verdict.
- The 24h heartbeat threshold means the banner can show the wrong tier for up
  to 24h after a heartbeat-driven downgrade/upgrade.

The producer story is inconsistent: `/device/register` persists, `/device/heartbeat`
does not. Either both should persist to `device.trustTier`, or the seed comment
in `AppContainer.swift:401-413` is misleading about "correct from frame 1 ... on
a cold-boot session restore."

**Fix:** Persist the heartbeat's `trustTier` alongside `lastHeartbeatAt`:

```swift
container.session.trustTier = heartbeatResponse.trustTier
try attestedKeyStore.writeLastHeartbeatAt(heartbeatResponse.heartbeatAcceptedAt)
try? attestedKeyStore.writeTrustTier(heartbeatResponse.trustTier)
```

### WR-04: `AppContainer.makeKYCStatusScreen()` `onVerified` closure is unreachable in the verified-clear scenario it claims to handle

**File:** `validationLedger/App/AppContainer.swift:189-197`; `KYCStatusViewModel.swift:236-239`

**Issue:** `makeKYCStatusScreen()` wires `viewModel.onVerified` to a
pop/dismiss. `KYCStatusViewModel.onVerified` is fired only by
`continueToRoleShell()` (line 236-239), which is guarded by
`guard case .verified = state`. The Profile entry-point status screen is opened
while the user is *already inside the role shell* — meaning they are already
KYC-verified in the common case, so opening the status screen, fetching, and
landing on `.verified` is the expected path. The "Continue" CTA then just
dismisses. That is intentional per the D6-09 comment.

The subtle bug: there is no comment-documented or wired path for the case where
the Profile-opened status screen lands on `.rejected` and the user recaptures
an artifact. `viewModel.onRecapture` is **never wired** in
`makeKYCStatusScreen()` (contrast `KYCCoordinator.pushStatus()` line 503 which
does wire `onRecapture`). A rejected artifact's "Retake" button on the
Profile-opened status screen calls `recapture(artifactType:)` →
`onRecapture?(...)` → **nil callback, silent no-op**. The user taps Retake and
nothing happens.

**Fix:** Either wire `onRecapture` in `makeKYCStatusScreen()` to push a capture
flow, or — if recapture from the Profile entry point is deliberately out of
scope — disable/hide the Retake affordance when the VM was constructed without
an `onRecapture` target, and document the decision. A silently-dead button is a
defect.

### WR-05: `LimitedTrustBannerContainerViewController.update()` leaves the child unconstrained on a redundant first call

**File:** `validationLedger/UI/LimitedTrustBannerView.swift:165-202`

**Issue:** `update(trustTier:)` has four branches. The `else if childTopConstraint == nil`
branch (line 191) handles "first call, no banner needed". But trace the
**banner-present-then-removed-then-re-added** path:

1. First call `update(.softwareOnly)` → `shouldShowBanner = true`, `banner == nil`
   → creates banner, sets `childTopConstraint` to banner-bottom. OK.
2. `update(.hardwareAttested)` → `!shouldShowBanner`, `banner != nil` → removes
   banner, sets `childTopConstraint` to safe-area. OK.
3. `update(.hardwareAttested)` again (idempotent re-apply, which the doc and
   `AppSessionTrustTierObservationTests` explicitly say happens — a no-op set
   still posts) → `!shouldShowBanner` true, but `banner == nil` now, so the
   `else if !shouldShowBanner, let existing = banner` branch is skipped, and the
   `else if childTopConstraint == nil` branch is **also** skipped because
   `childTopConstraint` is non-nil. Net: no-op. OK by luck.

The real gap: the **very first call ever** with `shouldShowBanner == true`
works, and the first call with `shouldShowBanner == false` works. But there is
no branch for "banner should show, banner already shown" or "banner should
hide, banner already hidden" — those fall through to the bottom `else if` which
only fires when `childTopConstraint == nil`. That is fine *today* because the
first call always sets `childTopConstraint`. It is fragile: if any future code
path calls `update` before `viewDidLoad`/`loadViewIfNeeded` resolves, or if the
construction order changes, the child tab bar can be left with no top
constraint → an Auto Layout ambiguity (zero-height or misplaced tab bar). The
`loadViewIfNeeded()` at line 166 mitigates but the branch structure is not
obviously correct.

**Fix:** Make the constraint management explicit and unconditional — always
ensure exactly one active `childTopConstraint` at the end of `update`,
regardless of branch:

```swift
public func update(trustTier: TrustTier) {
    loadViewIfNeeded()
    let shouldShowBanner = (trustTier != .hardwareAttested)
    if shouldShowBanner && banner == nil { /* add banner */ }
    else if !shouldShowBanner && banner != nil { /* remove banner */ }
    // Always (re)pin the child to the correct anchor.
    childTopConstraint?.isActive = false
    let anchor = banner?.bottomAnchor ?? view.safeAreaLayoutGuide.topAnchor
    childTopConstraint = child.view.topAnchor.constraint(equalTo: anchor)
    childTopConstraint?.isActive = true
    view.layoutIfNeeded()
}
```

### WR-06: `String(describing: error)` flows into logger fields on the non-attestation register failure paths

**File:** `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift:237-238, 275-276, 198-199, 213-214, 296-297`

**Issue:** The project security posture is "zero PII in analytics or crash
logs." The `buildAttestationFields()` helper is correctly PII-clean (event name
+ `AttestationStatus.rawValue` only — and `OTPViewModelTests.attestationCatchesAreFreeOfStringDescribing`
pins that). But the surrounding `verify()` failure paths still log
`fields: [.event: String(describing: error)]`:

- line 237-238 `device_register_failed` (DeviceFingerprint failure)
- line 275-276 `device_register_failed` (register POST failure — the catch-all)
- line 198-199 `otp_verify_keychain_failed`
- line 213-214 `otp_verify_keygen_failed`
- line 296-297 `initial_biometric_failed_sim_or_cancel`

`String(describing:)` of an arbitrary `Error` can include `NSError.userInfo`,
which for Keychain (`OSStatus`-backed errors), network errors, and
`DeviceFingerprint` errors may carry diagnostic strings, URLs, or — in the
register-POST catch — the raw HTTP response. The `device_register_failed` catch
at line 274-280 in particular sits directly downstream of a `NetworkError.httpError(statusCode, data)`,
and `String(describing:)` on that case will stringify the associated `Data`
payload. The PII-discipline test scopes itself only to `attestation_first_login`
events, so it does not catch these.

**Fix:** Replace `String(describing: error)` with a closed-set classification —
e.g. log only an error *category* (`keychain` / `network` / `keygen`) or the
`NetworkError` case name without associated values. The attestation paths
already model the correct pattern; apply it uniformly:

```swift
logger.warn(event: .init("device_register_failed"), fields: [:])
```

### WR-07: `KYCStatusViewModel.fetchStatus()` also logs `String(describing: error)` (same PII concern)

**File:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift:144-147, 213-216`

**Issue:** Same class of issue as WR-06. `kyc_status_fetch_failed` (line 145-147)
logs `String(describing: error)` where `error` is whatever `apiClient.request`
threw — a `NetworkError.httpError(_, data)` will stringify the response body.
`kyc_session_clear_failed` (line 213-216) logs `String(describing: error)` from a
file-system error, which can embed the on-disk KYC session path. The on-disk
KYC artifact directory is a protected-data location; leaking its path into logs
weakens the security posture even if the path itself is not "PII" in the
strictest sense. Note `refreshCachedKYCStatus`'s own failure log (line 180-185)
is correctly `fields: [:]` — the file is internally inconsistent.

**Fix:** Drop the `String(describing: error)` argument from both calls; log the
event name only, matching `refreshCachedKYCStatus`.

## Info

### IN-01: `KYCStatusViewModel.KYCOverallStatus.from(_:)` is a redundant wrapper

**File:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift:50-52`

**Issue:** `static func from(_ raw: String) -> KYCOverallStatus? { KYCOverallStatus(rawValue: raw) }`
is an exact alias for the synthesized `init?(rawValue:)`. It adds an API surface
with no behavior. The single call site (`mapState`, line 191) could call
`KYCOverallStatus(rawValue:)` directly.

**Fix:** Remove `from(_:)` and call the rawValue initializer at the use site, or
keep it only if a future mapping (alias handling) is genuinely planned — in
which case add a comment saying so.

### IN-02: Duplicate banner-wrapping logic across two construction sites

**File:** `validationLedger/Roles/RoleCoordinator.swift:97-101`; `validationLedger/App/AppCoordinator.swift:100-104`

**Issue:** `UITabBarController.wrapWithLimitedTrustBanner(trustTier:)` constructs
a `LimitedTrustBannerContainerViewController`, calls `update`, and returns it.
`AppCoordinator.init` `.role` case (lines 100-104) does the *exact same three
steps inline* (`LimitedTrustBannerContainerViewController(child:)` +
`update(trustTier:)`), then additionally retains the container. The
`wrapWithLimitedTrustBanner` extension is now effectively dead for the real app
path — `AppCoordinator` bypasses it because it needs the container reference for
the observer. Grep suggests `wrapWithLimitedTrustBanner` may have no remaining
non-test callers.

**Fix:** Either have `AppCoordinator` call `wrapWithLimitedTrustBanner` and
recover the container via a cast (`as? LimitedTrustBannerContainerViewController`),
or delete the now-unused extension and the `RoleCoordinator` `UITabBarController`
extension that hosts it. Two ways to do the same thing invites drift.

### IN-03: `AttestationFields` `status` can be `.error` while the producer never distinguishes "skip" vs "degrade" downstream

**File:** `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift:346-381`

**Issue:** `buildAttestationFields()` returns `status = .error` for both a
non-decodable challenge (line 362-363) and any thrown failure (line 378-379).
The D6-05 comment frames `.error` as "transient degrade." But a non-decodable
challenge is a *backend contract violation*, not a transient device condition —
conflating them under `.error` means the backend cannot distinguish a flaky
network from a malformed challenge response it itself sent. This is a wire-
contract observability gap, not a crash, hence Info.

**Fix:** Consider a distinct log event for the base64-decode failure (it already
logs `attestation_first_login_degraded` generically) so operations can tell the
two apart, even if both map to `attestationStatus = .error` on the wire.

### IN-04: Magic number `86400` repeated for the 24h heartbeat threshold

**File:** `validationLedger/App/SceneDelegate.swift:579`

**Issue:** `Date().timeIntervalSince(last) < 86400` uses a bare literal. The
comment explains it ("86400s = 24 hours") but a named constant
(`static let heartbeatIntervalSeconds: TimeInterval = 24 * 60 * 60`) is clearer
and prevents a typo on any future edit.

**Fix:** Extract a named constant.

### IN-05: `OTPViewModelTests` mock does not model OTP single-use — masks CR-01

**File:** `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift:441-446`

**Issue:** `AttestBackend` serves `/auth/otp/verify` with an unconditional 200
on every call. `retryRegisterIsIdempotent` relies on this to "pass." Because the
mock does not model the consume-once semantics of a real OTP backend, the test
asserts an idempotency property that does not hold against a real server (see
CR-01). The test is not *wrong* in isolation but it gives false confidence in
the retry path.

**Fix:** After CR-01 is fixed, update `AttestBackend` to return 200 for the
first `/auth/otp/verify` and 401 for subsequent calls within a test, and assert
`retryRegister()` does not re-hit `/auth/otp/verify`.

---

_Reviewed: 2026-05-18T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
