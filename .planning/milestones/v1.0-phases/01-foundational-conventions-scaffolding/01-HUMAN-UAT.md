---
status: partial
phase: 01-foundational-conventions-scaffolding
source: [01-VERIFICATION.md]
started: 2026-04-21T12:05:00Z
updated: 2026-04-21T12:05:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Simulator UIKit launch — tab bar renders correctly
expected: App launches on iPhone 17 Pro / iOS 26.4 (or latest available) simulator. Root view is a UITabBarController with 4 tabs matching Shipper role: Loads, Brokers, BOL, Assistant. Each tab has the correct SF Symbol. No crash, no SwiftUI render path.
command: `xcodebuild -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' build && open -a Simulator`, then Xcode Cmd+R
result: [pending]

### 2. Keychain Inspector shows 0 items on fresh install (FOUND-02)
expected: Device → Erase All Content and Settings (or long-press app icon → Delete App). Relaunch. Shake → DevMenu → Keychain Inspector. Entry count reads "(empty — 0 items)". Proves KeychainWiper.wipeOnFirstLaunch fires before AppContainer resolves.
result: [pending]

### 3. PII string-path name redaction (CR-02a end-to-end demo)
expected: Add `logger.info("test User Jane Doe failed KYC")` to SceneDelegate briefly. Rerun. Shake → Log Viewer. The entry shows `test User J. D. failed KYC` (name initial-masked via scrubString namePattern). Remove the test log after verification.
result: [pending]

### 4. Role swap observed in Xcode console (ADR-0002 proof)
expected: Shake → Role Switcher → Broker. Tabs change to Loads/Carriers/Network/Assistant. Xcode console (not simulator) shows log line sequence: `app_coordinator_deinit` → `app_container_deinit` → `app_container_init` → `app_coordinator_init event=role.broker`. Proves ARC-driven deterministic teardown before new root renders. Repeat for Carrier/Dispatch/Factoring/back-to-Shipper.
result: [pending]

### 5. CI Simulator pipeline runs green on a PR (FOUND-04 / CI-01)
expected: Configure a GitHub remote if none exists. `git checkout -b verify-phase-1 && git commit --allow-empty -m "chore: trigger CI" && git push -u origin verify-phase-1`. Open PR against main. `CI (Simulator)` workflow runs on the PR and exits green within ~12 min.
result: [pending]

### 6. Planted-violation → CI reject → revert → CI green (D-19 end-to-end enforcement)
expected: On the verify-phase-1 branch, add `print("test")` to any non-test `.swift` file. Push. `CI (Simulator)` FAILS at the SwiftLint step (ban_print violation). Revert the commit. Push. CI goes green again.
result: [pending]

### 7. Device CI pipeline runs green on merge to main (FOUND-04 / CI-02)
expected: Register a self-hosted macOS runner (labels `self-hosted`, `macOS`, `device`). Add GitHub secret `DEVICE_UDID` with value `48F5B3CC-0E06-50CE-BFD4-8A0A136E144D` (your paired iPhone 15 Pro Max). Merge the verify-phase-1 PR. `CI (Device)` workflow triggers on the push-to-main and runs SecureEnclaveSmokeTests on the physical iPhone. Exits green.
result: [pending]

### 8. PrivacyInfo.xcprivacy present in .ipa archive (FOUND-06 / SEC-02)
expected: Archive the app via Xcode → Product → Archive → Distribute App → Export (ad-hoc or development). `unzip -p validationLedger.ipa Payload/validationLedger.app/PrivacyInfo.xcprivacy` outputs the XML. Alternative: `scripts/check-privacy-manifest.sh` against a locally-built `.app` already passed (sufficient for Phase 1; true .ipa extraction is scoped to M5 pre-submission).
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0
blocked: 0

## Gaps

None at present. All 5 ROADMAP Phase 1 Success Criteria programmatically verified. This UAT covers the 8 remaining human-observation items that require a running simulator, physical device, or GitHub infrastructure.

## Notes

- CR-02a (PIIScrubber scrubString missing name sweep) was resolved in commit `ad69b72` during Phase 1 execution; Test 3 validates the user-visible effect.
- CR-01 (NetworkClient force-cast) and CR-03 (DevMenu force-unwrap) from 01-REVIEW.md are NOT blocking Phase 1 but should be addressed during Phase 2 and Phase 3 respectively (or via `/gsd-code-review-fix 1`).
- iOS 17.5 simulator runtime is NOT installed on the dev machine. Use iPhone 17 Pro / iOS 26.4 locally; CI YAML correctly targets iPhone 15 / iOS 17.5 on GitHub-hosted runners.
- Paired physical iPhone for Test 7: iPhone 15 Pro Max, UDID `48F5B3CC-0E06-50CE-BFD4-8A0A136E144D`.
