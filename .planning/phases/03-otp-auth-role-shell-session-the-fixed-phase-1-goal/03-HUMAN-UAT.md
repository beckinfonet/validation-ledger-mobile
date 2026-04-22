---
status: partial
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
source: [03-VERIFICATION.md]
started: 2026-04-21T00:00:00Z
updated: 2026-04-21T00:00:00Z
---

## Current Test

[awaiting human testing — blocked by BiometricLockViewController wiring gap; see 03-VERIFICATION.md gaps section]

## Tests

### 1. Cold-boot biometric prompt (SC-2 / SESS-01) on physical device
expected: After completing OTP on a device with Face/Touch ID enrolled, force-quit the app, re-launch. BiometricLockViewController appears OVER the role shell (no tab content visible behind). After biometric auth, role shell becomes interactive.
result: [pending — blocked by SceneDelegate wiring gap]

### 2. >5min background → biometric on return (SC-3 / SESS-02)
expected: Background the app (home button) for >5 minutes, foreground it. BiometricLockViewController appears. Background for <5 minutes, foreground. BiometricLockViewController does NOT appear.
result: [pending — blocked by SceneDelegate wiring gap]

### 3. Biometric re-enrollment triggers re-bind placeholder (SESS-03)
expected: Settings → Face ID → Reset Face ID → re-enroll. Re-launch app. BiometricLockViewController shows .biometricReEnrolled reason copy ("Biometric changed" / "You'll need to re-bind this device").
result: [pending — blocked by SceneDelegate wiring gap]

### 4. Secure Enclave authorization key ACL cleared on logout (SC-4 SE-inspection portion)
expected: After logout, Keychain inspection on device shows sessionToken / session.role / session.userID absent AND SE authorizationKey SecItem absent AND deviceKey still PRESENT (device identity preserved per D-16).
result: [pending — physical device required]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 3

## Gaps

### Gap 1: BiometricLockViewController wiring (blocks tests 1, 2, 3)

- status: failed
- source: 03-VERIFICATION.md
- path: validationLedger/App/SceneDelegate.swift
- missing: SceneDelegate does not query sessionLock.lockState() before presentRoot(.role(role)); does not observe UIApplication.didBecomeActiveNotification; no construction site for BiometricLockViewController anywhere in the codebase.
- fix: In SceneDelegate.presentRoot(.role(role)) after building the role root VC, check container.sessionLock.lockState(now: .now) and — when .locked — present BiometricLockViewController modally (fullScreen) over the role VC. Also add a didBecomeActive observer that re-runs the same check on foreground. Handle .biometricReEnrolled with a placeholder re-bind route.
