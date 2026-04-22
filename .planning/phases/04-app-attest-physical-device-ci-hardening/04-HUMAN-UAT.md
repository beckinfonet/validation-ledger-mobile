---
phase: 04-app-attest-physical-device-ci-hardening
status: partial
source: [04-08-PLAN.md §Task 4, 04-08-SUMMARY.md]
started: "2026-04-22T11:30:00-07:00"
updated: "2026-04-22T11:30:00-07:00"
---

## Current Test

Awaiting human testing on iPhone landscape + iPad (portrait, landscape, Split View) + gesture dismiss attempts.

## Tests

### 1. Banner safe-area pinning on iPhone landscape
expected: Banner pinned to safe-area top in landscape orientation. No Dynamic Island overlap. Full D-11 copy legible (may wrap to 2 lines at narrower widths).
result: pending

### 2. Banner non-dismissibility via user gestures
expected: Swipe left/right/up/down on the banner — does NOT dismiss. Tap on the banner — does NOT toggle/hide. `isUserInteractionEnabled = false` enforces this at the UIKit layer.
result: pending

### 3. Banner layout on iPad Pro 11-inch (portrait)
expected: Banner renders above the tab bar, full width, pinned to safe-area top. Copy renders on a single line at 11" wide.
result: pending

### 4. Banner layout on iPad Pro 11-inch (landscape + Split View)
expected: Banner pinned to safe-area top in landscape. In Split View (drag another app into the right half), banner reflows to the narrower width, still pinned.
result: pending

### 5. Yellow tone acceptability
expected: `systemYellow @ 85% alpha` is legible against the role shell's white/system-background behind it, across ambient light conditions (indoor fluorescent, sunlight, night mode). If ambient-light tweaks are needed, raise a follow-up for a Phase 4.1 plan.
result: pending

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps

*(none yet — gaps populate when tests fail / raise blockers)*

## Reproduction

Prerequisites: DEBUG build on a physical iPhone or iPad (no launch args needed — Plan 04-11 ships
default mock fixtures for the organic walk-through).

```
# Build + install DEBUG on target device via Xcode or xcodebuild
xcodebuild -scheme validationLedger -configuration Debug \
  -destination 'platform=iOS,name=<your device>' clean build

# On device:
# 1. Open app
# 2. Grant location permission
# 3. Enter any US phone → Send code
# 4. Enter any 6 digits → Verify
# 5. Face ID prompt (or cancel — flow continues)
# 6. Role shell renders with the yellow Limited-Trust banner at top
```

Notes:
- iPhone portrait already confirmed PASS on 2026-04-22 11:30 PT (screenshot).
- `-MockOTPTrustTierForUITest softwareOnly` launch arg (via Xcode scheme) is NOT required — Plan 04-11's
  AppContainer default already seeds `AppSession(trustTier: .softwareOnly)` in DEBUG+mock+no-UITest-arg mode.
