---
phase: 4
slug: app-attest-physical-device-ci-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-22
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> **Source:** `04-RESEARCH.md` § Validation Architecture (Dimension 8)

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (unit) + XCTest (UI/device via `validationLedgerDeviceTests`) |
| **Config file** | `validationLedger.xcodeproj/xcshareddata/xcschemes/validationLedgerDeviceTests.xcscheme` |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerTests` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15' -retry-tests-on-failure -test-iterations 2` |
| **Full device-suite command** | `xcodebuild test -scheme validationLedger -destination 'generic/platform=iOS' -only-testing:validationLedgerDeviceTests -retry-tests-on-failure -test-iterations 2` |
| **Estimated runtime** | ~90s simulator / ~4–6min device (SE + Keychain + App Attest round-trips) |

---

## Sampling Rate

- **After every task commit:** Run quick simulator command
- **After every plan wave:** Run full simulator suite
- **After Wave containing device-only targets:** Run full device-suite command on physical iPhone runner
- **Before `/gsd-verify-work`:** Full suite (simulator + device) must be green
- **Max feedback latency:** ~90s simulator, ~6min device

---

## Per-Task Verification Map

> **Planner fills this table.** Every plan task must list the task ID, plan number, wave, REQ-ID, threat ref, secure behavior, test type (unit / integration / device CI / human UAT), and automated command. See `04-RESEARCH.md` § Validation Architecture for the D-01..D-16 coverage matrix that anchors this table.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| {to-be-filled-by-planner} | | | | | | | | | |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

> Stubs/fixtures that must exist before any D-01..D-16 decision can be validated. Planner must enumerate exact file list; 04-RESEARCH.md § "Wave 0 Gaps" enumerates 18 new files.

- [ ] `validationLedger/Core/Attestation/AttestationService.swift` — protocol + `AttestationStatus` + `AttestationError` enum (D-02, D-09)
- [ ] `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` — real `DCAppAttestService` wrapper (D-01, D-05, D-06, D-07)
- [ ] `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` — DEBUG-only simulator bypass (D-10)
- [ ] `validationLedger/Core/Attestation/AttestedKeyStore.swift` — Keychain persistence wrapper (D-01, D-03)
- [ ] `validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift` — GET /device/challenge (D-05)
- [ ] `validationLedger/Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift` — POST /device/heartbeat (D-07)
- [ ] `validationLedger/Core/Networking/Mock/` — fixtures for `/device/challenge`, attestation-aware `/device/register`, `/device/heartbeat` happy + error paths
- [ ] `validationLedger/UI/RoleShell/LimitedTrustBanner.swift` — non-dismissible banner view (D-11, D-12)
- [ ] `validationLedger/validationLedger.entitlements` — App Attest entitlement (development + production variants)
- [ ] `.planning/adr/0005-three-key-device-register-payload.md` — ADR documenting the three-key payload (D-02)
- [ ] `docs/attestation-rotation.md` — re-attestation runbook (D-04)
- [ ] `validationLedgerDeviceTests/` fixtures for seeded `LAContext` (D-14)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Limited Trust banner renders above tabs on real device with entitlement missing | DEV-04 | Visual layout + non-dismissibility only observable on hardware | Install TestFlight build with entitlement stripped, log in, confirm banner visible above tab bar with copy "Limited trust mode — this device can't fully verify…" |
| DEBUG "Re-attest now" dev-menu row triggers full re-attestation | D-04 | Dev-menu shake gesture + Keychain state inspection | Shake device → Dev Menu → tap "Re-attest now" → verify `attestedKeyId` Keychain item regenerated (timestamp/UUID changes) and `/device/register` re-posts |
| CI merge-gate actually blocks PR merge | CI-03 (SC-3) | GitHub branch-protection behavior only observable in a real PR | Open a PR with an intentional device-test failure → confirm "Merge" button is disabled with "Required check failing" → fix + confirm merge re-enables |
| App Attest quota-exceeded path recovers gracefully | D-09 (quotaExceeded) | Apple's rate-limit timing is undocumented + cannot be forced deterministically | Monitor TestFlight crash/log channel for `AttestationStatus.quotaExceeded` occurrences; verify client backs off + eventually succeeds without user-facing error |
| Hardware-attested trust tier round-trips through mock backend | DEV-04 (SC-1) | Physical iPhone only — simulator emits `simulatorBypass`, can't prove the real-SE + real-AppAttest path | Run `validationLedgerDeviceTests` on physical iPhone runner + inspect posted `/device/register` payload has `attestationStatus: "attested"` + valid `attestationObject` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all 18 MISSING file references from 04-RESEARCH.md
- [ ] No watch-mode flags in CI commands
- [ ] Feedback latency < 90s simulator / < 6min device
- [ ] Every D-01..D-16 decision has at least one validation path (unit / integration / device CI / human UAT)
- [ ] DEV-04 + CI-03 requirement IDs each covered by at least one validation
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
