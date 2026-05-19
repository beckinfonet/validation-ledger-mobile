---
status: partial
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
source: [06-VERIFICATION.md]
started: 2026-05-18T23:04:46Z
updated: 2026-05-18T23:04:46Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. LimitedTrustBanner re-render on mid-session trustTier mutation
expected: When `AppSession.trustTier` changes at runtime (e.g. a heartbeat downgrades `.hardwareAttested` → `.softwareOnly`), the LimitedTrustBanner appears/disappears in place with no animation and no root-swap. The role-shell tab-bar hierarchy is unchanged — only the banner subview toggles.
result: [pending]

### 2. Profile-entry KYC status "Continue" CTA pop/dismiss behavior
expected: From the role shell → Profile tab → KYC status entry point, tapping "Continue" pops (nav-stack path) or dismisses (modal path) the screen and lands the user back on the Profile tab — NOT a root-swap to the role shell. No coordinator handoff, no role-shell recreation.
result: [pending]

### 3. Banner physical-device UAT (carried from Phase 4)
expected: The 5 open Phase 4 LimitedTrustBanner device-UAT items pass on device — iPhone landscape safe-area pinning, gesture non-dismiss, iPad portrait/landscape/Split View layout, yellow-tone legibility. See `04-HUMAN-UAT.md` items 1–5.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
