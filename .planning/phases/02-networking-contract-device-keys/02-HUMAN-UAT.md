---
status: partial
phase: 02-networking-contract-device-keys
source: [02-VERIFICATION.md]
started: 2026-04-21T14:00:00Z
updated: 2026-04-21T14:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. DevMenu NetworkConfig toggle — visual verification (SC-2)
expected: Open Xcode, Cmd+R on iPhone 17 Pro / iOS 26.4. App launches with tab bar. Device → Shake (Ctrl+Cmd+Z) → DevMenu modal → tap "Network Config (DEBUG)". Tap "Use Mock" — Xcode console shows `app_container_deinit` followed by `app_container_init`; app remains usable against mock fixtures. Tap "Use Live" — an alert appears explaining that `.live(baseURL:)` requires a configured Environment. Tap "Reset to default" — matches original bootstrap config.
why_human: Requires interactive shake gesture + console-log observation; cannot run headlessly.
result: [pending]

### 2. Physical-device SecureEnclaveKeyStoreTests (SC-3)
expected: Self-hosted macOS runner paired with iPhone 15 Pro Max (UDID `48F5B3CC-0E06-50CE-BFD4-8A0A136E144D`) + GitHub secret `DEVICE_UDID` set. Push a branch; device CI pipeline runs `xcodebuild test -destination 'id=48F5B3CC-0E06-50CE-BFD4-8A0A136E144D' -only-testing:validationLedgerDeviceTests/SecureEnclaveKeyStoreTests`. All 6 tests pass: key generation (both slots), sign + verify round-trip, ACL enforcement (deviceKey=.devicePasscode, authorizationKey=.biometryCurrentSet), delete idempotency.
why_human: Secure Enclave primitives are physical-device only; simulator keystore is `SoftwareKeyStore` per `#if DEBUG && targetEnvironment(simulator)`. Runner activation is Phase 1 HUMAN-UAT #7 carryover.
result: [pending]

### 3. Physical-device RefuseLaunchWithoutSecureEnclaveTests (SC-4)
expected: On the same device CI runner, `xcodebuild test -only-testing:validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests` runs 5 tests. `preflightSecureEnclave(isAvailable:false, buildConfiguration:.release)` expectation triggers fatalError as assertion fires; matrix corners (DEBUG ✓, RELEASE + SE present ✓, RELEASE + SE absent ✗) all behave per spec.
why_human: Device-only; requires the runner activation from Phase 1 HUMAN-UAT #7.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps

None as programmatic gaps. All 5 ROADMAP Phase 2 Success Criteria verified in code. This UAT covers the 3 interactive/device-CI observation items.

## Notes

**Pre-Phase-3 fix items** (deferred; tracked in PROJECT.md Active):
- **CR-02** — `SecureEnclaveKeyStore.generateKey(slot:)` needs an idempotent guard to prevent duplicate Keychain inserts on reinstall. Without it, a second `generateDeviceIdentityKeys()` call silently creates a pub/priv key mismatch. Fix is ~5 lines: `if let existing = try? loadPublicKey(slot: slot) { return existing }` at top of `generateKey`.
- **IN-01/05** — 4 `RequestBody` properties with acronym tails need explicit `CodingKeys`:
  - `OTPVerifyEndpoint.RequestBody.otpSessionID` → `case otpSessionID = "otp_session_id"`
  - `KYCUploadChunkEndpoint.RequestBody.uploadID` → `case uploadID = "upload_id"`
  - `KYCUploadCommitEndpoint.RequestBody.uploadID` → `case uploadID = "upload_id"`
  - `DeviceRegisterEndpoint.DeviceFingerprintPayload.installUUID` → `case installUUID = "install_uuid"`

Without these, `.convertToSnakeCase` produces `otp_session_i_d`, `upload_i_d`, `install_u_u_i_d` — mock tests pass (any shape accepted) but first real backend call in Phase 3 returns 400.

**Other code-review items** (non-blocking, tracked):
- CR-01 APIClient.send default extension drops interceptor-injected headers for non-URLSessionNetworkClient conformers — not a live issue until a second `NetworkClient` conformer is added
- CR-03 SceneDelegate NotificationCenter silent fail + missing `@MainActor` — Swift 6 concurrency hygiene
- CR-04 `noReleasePlaceholders` gate doesn't run in CI (DEBUG-only CI) — needs a Release-config CI job OR rewrite as a script-based grep gate
- WR-02 DeviceFingerprint Keychain read silently swallows errors — may cause install-UUID drift during Keychain-locked window
- WR-06 Xcode 16.4 CI pin vs TechStack.md 26.4

**Paired physical iPhone for Tests 2 + 3:** iPhone 15 Pro Max, UDID `48F5B3CC-0E06-50CE-BFD4-8A0A136E144D`.
