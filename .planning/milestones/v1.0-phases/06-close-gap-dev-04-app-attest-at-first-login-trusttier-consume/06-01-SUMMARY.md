---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
plan: 01
subsystem: attestation-storage
tags: [keychain, attestation, trust-tier, dev-04]
requires: []
provides:
  - KeychainKey.trustTier (device.trustTier) attestation-group key
  - AttestedKeyStore.readTrustTier() / writeTrustTier(_:) accessors
affects:
  - validationLedger/Core/Storage/Keychain/KeychainKey.swift
  - validationLedger/Core/Attestation/AttestedKeyStore.swift
tech-stack:
  added: []
  patterns:
    - "Keychain accessor pair mirroring attestedKeyId: itemNotFound→nil read, .afterFirstUnlockThisDeviceOnly write"
    - "Fail-safe enum re-hydration: TrustTier(rawValue:) yields nil on unknown wire value (never .hardwareAttested)"
key-files:
  created:
    - validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift
  modified:
    - validationLedger/Core/Storage/Keychain/KeychainKey.swift
    - validationLedger/Core/Attestation/AttestedKeyStore.swift
    - validationLedgerTests/Storage/KeychainScopeTests.swift
decisions:
  - "device.trustTier deliberately excluded from KeychainScope.session — preserved across logout like device.attestedKeyId (D6-02); no delete accessor exists"
  - "Verification simulator switched from plan-specified 'iPhone 16' (unavailable on this host) to 'iPhone 17' (Rule 3 — blocking issue)"
metrics:
  duration: 7min
  completed: 2026-05-18
requirements: [DEV-04]
---

# Phase 6 Plan 01: trustTier Keychain Foundation Summary

JWT-free Keychain hand-off channel for the first-login trust tier: a new `device.trustTier` Keychain key in the attestation key group plus `readTrustTier()` / `writeTrustTier(_:)` accessors on `AttestedKeyStore` that mirror the existing `attestedKeyId` pair, with fail-safe enum re-hydration and a preserve-across-logout scope pin.

## What Was Built

- **`KeychainKey.trustTier`** — a `public static let trustTier = KeychainKey(rawValue: "device.trustTier")` static in the `device.` attestation key group (alongside `attestedKeyId` / `lastHeartbeatAt`), with a comment documenting the Phase 6 DEV-04 (D6-01/D6-02) lifecycle: backend-driven, written by `OTPViewModel` (Plan 02) from the `/device/register` response, read by the role-shell `AppContainer` (Plan 03), persisted across the post-OTP container swap, never in `KeychainScope.session`.
- **`AttestedKeyStore.readTrustTier() throws -> TrustTier?`** — `keychain.get(.trustTier)`, `guard let raw = String(data:encoding:.utf8)`, return `TrustTier(rawValue: raw)`. Translates `KeychainError.itemNotFound` to `nil`. An unknown wire value yields `nil` (fail-safe — callers fall back to `.softwareOnly`, never `.hardwareAttested`).
- **`AttestedKeyStore.writeTrustTier(_:) throws`** — `keychain.set(Data(tier.rawValue.utf8), for: .trustTier, accessibility: .afterFirstUnlockThisDeviceOnly)`.
- No `deleteTrustTier` accessor — D6-02 keeps the item across logout; there is no delete site and it is not wired into `LogoutService`.
- **`AttestedKeyStoreTrustTierTests`** — a Swift Testing `@Suite` with 4 `@Test`: round-trip `.hardwareAttested`, round-trip `.softwareOnly`, fresh-store-nil (itemNotFound→nil, does not throw), and overwrite.
- **`KeychainScopeTests` extension** — 2 new `@Test`: `device.trustTier` is NOT in `KeychainScope.session`, and `device.trustTier` survives `deleteAll(under: .session)` (D6-02 preserve-across-logout).

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Add device.trustTier KeychainKey + AttestedKeyStore accessors | `3f03152` | KeychainKey.swift, AttestedKeyStore.swift |
| 2 | Wave 0 RED tests — trustTier round-trip + preserve-across-logout scope pin | `f4b5c02` | AttestedKeyStoreTrustTierTests.swift, KeychainScopeTests.swift |

## Verification

- `xcodebuild build -scheme validationLedger` (iPhone 17 simulator) — succeeds, no compile errors. Only pre-existing Swift 6 concurrency warnings in `AppCoordinator.swift` / `Logger.swift` / `APIClientEndpointTests.swift` (out of scope — not touched by this plan).
- `xcodebuild test` for `AttestedKeyStoreTrustTierTests` + `KeychainScopeTests` — **10 tests across 2 suites pass, 0 failures**.
- `grep -rn 'device.trustTier' validationLedger/` — the production-code string is declared exactly once (KeychainKey.swift:49); the only other line is the explanatory comment at :46.
- `grep -rn 'deleteTrustTier' validationLedger/` — 0 matches (D6-02 — no delete accessor).
- `KeychainScope.session.contains(.trustTier) == false`; `.attestedKeyId` membership unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Verification simulator destination unavailable**
- **Found during:** Task 1 verification
- **Issue:** The plan's `<verify>` blocks specify `platform=iOS Simulator,name=iPhone 16`. That simulator is not installed on this host — `xcodebuild -showdestinations` lists `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone Air`, etc. (OS 26.3.1), but no plain `iPhone 16`.
- **Fix:** Ran the build and test commands against `name=iPhone 17` instead. The destination is the only thing changed; the scheme, test targets, and `-only-testing` filters are exactly as the plan specifies.
- **Files modified:** None (verification-command-only change).
- **Commit:** N/A (no code change).

## TDD Gate Compliance

Task 2 carries `tdd="true"`, but the plan body explicitly prescribes a collapsed RED-then-GREEN cycle: *"Task 1 already landed the production code, so they should pass on first run — if any fails, that is a real defect in Task 1 to fix, not a test to weaken."* Consequently the `feat` commit (`3f03152`, Task 1 production code) precedes the `test` commit (`f4b5c02`, Task 2 tests) — the reverse of strict RED-first ordering. This is plan-intended (the foundation key + accessors must land first as the storage contract Plans 02/03 build against). `tdd_mode` is `false` in `config.json`, and the orchestrator passed neither `MVP_MODE` nor `TDD_MODE`, so the MVP+TDD runtime gate does not apply. All 10 tests passed on first run, confirming Task 1's implementation is correct — no test was weakened.

## Self-Check: PASSED

- FOUND: validationLedger/Core/Storage/Keychain/KeychainKey.swift (modified)
- FOUND: validationLedger/Core/Attestation/AttestedKeyStore.swift (modified)
- FOUND: validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift (created)
- FOUND: validationLedgerTests/Storage/KeychainScopeTests.swift (modified)
- FOUND commit: 3f03152
- FOUND commit: f4b5c02
