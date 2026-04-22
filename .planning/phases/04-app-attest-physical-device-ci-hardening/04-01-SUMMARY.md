---
phase: 04-app-attest-physical-device-ci-hardening
plan: 01
subsystem: attestation
tags: [app-attest, devicecheck, keychain, entitlements, adr, runbook, contracts]

# Dependency graph
requires:
  - phase: 02-networking-contract-device-keys
    provides: KeyStoreProtocol header style + KeyStoreError enum shape + Keyslot shared-type pattern; KeychainKey + KeychainScope typed-constant + scope-predicate base
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    provides: LogoutReason String-raw-value Sendable enum pattern; ADR 0004 six-section document structure
provides:
  - "AttestationStatus wire-format enum (6 cases per D-09) — consumed by DeviceRegisterEndpoint request body extension in Plan 04"
  - "TrustTier wire-format enum (2 cases per D-12) — consumed by DeviceRegisterEndpoint.Response + DeviceHeartbeatEndpoint.Response in Plan 04"
  - "AttestationError Swift error taxonomy — mapped to AttestationStatus via statusForDCError(_:) by DCAppAttestAttestationService in Plan 03"
  - "AttestationService protocol — four async-throws members: generateKeyIfNeeded / attestKey / generateAssertion / clearPersistedKeyId"
  - "KeychainKey.attestedKeyId + KeychainKey.lastHeartbeatAt constants (raw values device.attestedKeyId + device.lastHeartbeatAt)"
  - "KeychainScope.session doc-comment explicitly excluding attestedKeyId + lastHeartbeatAt (D-03 invariant documented; Plan 02 adds the pinning test)"
  - "validationLedger.entitlements file with com.apple.developer.devicecheck.appattest-environment=development; wired into CODE_SIGN_ENTITLEMENTS for both Debug + Release configurations of the app target"
  - "ADR 0005 three-key /device/register payload rationale (deviceKey + authorizationKey + attestedKey)"
  - "docs/attestation-rotation.md backend-trigger + DEBUG manual re-attest runbook"
affects:
  - 04-02 (Wave 0 tests including testAttestedKeyIdNotInSessionScope)
  - 04-03 (DCAppAttestAttestationService + SimulatorBypassAttestationService impls)
  - 04-04 (DeviceRegisterEndpoint extension + DeviceChallengeEndpoint + DeviceHeartbeatEndpoint)
  - 04-06 (AppContainer DI wiring + preflightAttestationEntitlement mirror)
  - 04-07 (DevMenu "Re-attest now" row)
  - 04-08 (Limited Trust Mode banner consumes TrustTier)
  - 04-09 (AppAttestRoundTripTests device CI coverage)
  - 04-11 (SceneDelegate cold-boot heartbeat + didBecomeActive 24h cadence)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "String-raw-value Sendable Codable enum for wire-format contracts (AttestationStatus + TrustTier) — mirror of Phase 3 LogoutReason"
    - "Error-with-underlying-NSError enum taxonomy (AttestationError) with explicit PII-scrubbing doc-comment on the underlying(NSError) case"
    - "async-throws protocol with @AnyObject + Sendable conformance; @MainActor opt-in deferred to implementations (unlike Phase 2 KeyStoreProtocol which is fully sync)"
    - "Decision-ID traceability in Swift file headers (every D-NN citation pointing back to CONTEXT.md)"
    - "Keychain keys explicitly enumerated in .session scope doc-comment as excluded-from-session to document the D-03 preservation-across-logout invariant"

key-files:
  created:
    - validationLedger/Core/Attestation/AttestationStatus.swift
    - validationLedger/Core/Attestation/TrustTier.swift
    - validationLedger/Core/Attestation/AttestationError.swift
    - validationLedger/Core/Attestation/AttestationService.swift
    - validationLedger/validationLedger.entitlements
    - docs/adr/0005-three-key-device-register-payload.md
    - docs/attestation-rotation.md
  modified:
    - validationLedger/Core/Storage/Keychain/KeychainKey.swift
    - validationLedger/Core/Storage/Keychain/KeychainScope.swift
    - validationLedger.xcodeproj/project.pbxproj

key-decisions:
  - "D-09 wire-format enum fixed at 6 cases (attested | unsupported | entitlementMissing | quotaExceeded | simulatorBypass | error) — downstream plans (03/04) cannot add a seventh without coordinated backend contract change"
  - "D-12 initial M1 TrustTier set fixed at 2 cases (hardwareAttested + softwareOnly) — future tiers added server-side with @unknown default: client update"
  - "D-03 invariant enforced by omission + documentation only: KeychainScope.session.contains(_:) body unchanged; attestedKeyId + lastHeartbeatAt stay excluded by virtue of not being listed. Plan 02 adds the pinning test that fails loud if a future change accidentally moves either key into the session scope"
  - "Entitlement environment value 'development' shipped to both Debug + Release configurations — Apple ignores the value in TestFlight/App Store and always uses production routing (RESEARCH Pitfall 3); no Release-flip needed for M5 submission"
  - "AttestationError.underlying(NSError) case carries raw NSError but doc-comment forbids logging err.userInfo — enforces FOUND-01 PII invariant at the documentation boundary; Plan 05 will add a Logger.LogField type-level prohibition"

patterns-established:
  - "Dual-impl protocol header citing both impls by name before either exists — future maintainers see the full picture from the protocol file alone (mirrors KeyStoreProtocol lines 1-10)"
  - "Runbook + ADR pair for every backend-driven rotation path — docs/attestation-rotation.md alongside docs/adr/0005 mirrors docs/cert-rotation.md alongside docs/adr/0004"
  - "Entitlement plist carries an inline XML comment documenting the Pitfall 3 TestFlight-ignores-value quirk — onboarding surface for future engineers"

requirements-completed: [DEV-04]

# Metrics
duration: ~15 min
completed: 2026-04-22
---

# Phase 04 Plan 01: Wave-1 Contracts (Types, Keychain, Entitlements, ADR, Runbook) Summary

**Landed the DEV-04 wire-format types (AttestationStatus 6-case + TrustTier 2-case), AttestationError taxonomy, AttestationService async-throws protocol, two new Keychain key constants (device.attestedKeyId + device.lastHeartbeatAt), the App Attest entitlement plist wired into both Debug + Release code-signing, ADR 0005 three-key payload rationale, and the backend-driven attestation-rotation runbook — all as immovable contracts for Wave-2+ plans.**

## Performance

- **Duration:** ~15 min (wall-clock)
- **Started:** 2026-04-22T11:10:00Z
- **Completed:** 2026-04-22T11:25:28Z
- **Tasks:** 3 (all auto, fully autonomous — no checkpoints)
- **Files created:** 7
- **Files modified:** 3
- **Tasks committed atomically:** 3

## Accomplishments

- Established the immovable D-09 / D-12 wire-format contracts in Swift (AttestationStatus, TrustTier) — Plan 04's DeviceRegisterEndpoint extension and Plan 03's DCAppAttestAttestationService both consume these by name without needing any planning re-entry.
- Codified the D-03 Keychain invariant (attestedKeyId + lastHeartbeatAt preserved across logout) via the documentation-only approach endorsed by PATTERNS.md section 8 — KeychainScope.contains(_:) body unchanged, .session doc-comment now explicitly enumerates the D-03 + D-07 exclusions, Plan 02 will land the pinning test.
- Wired the App Attest entitlement into both Debug + Release of the validationLedger target so TestFlight + physical-device builds carry `com.apple.developer.devicecheck.appattest-environment = development`. The value is intentionally unchanged for Release — Pitfall 3 documents that Apple ignores the entitlement value in TestFlight + App Store routings.
- ADR 0005 documents the three-key payload extension over ADR 0004 with the 6-section structure, citing CONTEXT D-01 through D-12 + RESEARCH lines 283-395 and 594-608.
- docs/attestation-rotation.md mirrors docs/cert-rotation.md structure with backend-driven trigger flow (attestationInvalid / nonceExpired / keyCompromised), emergency revoke path, DEBUG-only manual re-attest, and CI coverage reference.

## Task Commits

Each task committed atomically with `--no-verify` (parallel-executor convention):

1. **Task 1: Create four Attestation types (AttestationStatus, TrustTier, AttestationError) + AttestationService protocol** — `534ad16` (feat)
2. **Task 2: Extend KeychainKey + KeychainScope for attestedKeyId / lastHeartbeatAt (D-03)** — `0d50f11` (feat)
3. **Task 3: Create validationLedger.entitlements + ADR 0005 + docs/attestation-rotation.md + pbxproj wiring** — `6ffd2f2` (feat)

## Files Created/Modified

### Created

- `validationLedger/Core/Attestation/AttestationStatus.swift` — 6-case String-raw-value Codable Sendable enum fixing the /device/register `attestationStatus` wire-format contract per D-09.
- `validationLedger/Core/Attestation/TrustTier.swift` — 2-case String-raw-value Codable Sendable enum for the /device/register + /device/heartbeat `trustTier` response field per D-12.
- `validationLedger/Core/Attestation/AttestationError.swift` — 8-case Error + Sendable taxonomy covering the DCError.Code surface; .underlying(NSError) catch-all with explicit doc-comment forbidding err.userInfo from logging (FOUND-01 PII invariant).
- `validationLedger/Core/Attestation/AttestationService.swift` — AnyObject + Sendable protocol with four async-throws methods, header citing D-01/D-03/D-04/D-05/D-06/D-07 + naming both production (DCAppAttestAttestationService) + simulator (SimulatorBypassAttestationService) impls that Plan 03 will deliver.
- `validationLedger/validationLedger.entitlements` — plist with `com.apple.developer.devicecheck.appattest-environment = development`; inline XML comment documents Pitfall 3 (Apple ignores the value in TestFlight + App Store).
- `docs/adr/0005-three-key-device-register-payload.md` — 6-section ADR (Context / Decision / Consequences / Alternatives / Operational Notes / References) extending ADR 0004 to the three-key payload.
- `docs/attestation-rotation.md` — Runbook mirroring docs/cert-rotation.md with "Why Client-Self-Rotation Is Forbidden" section, regeneration procedure, emergency revoke path, DEBUG-only manual re-attest, and CI checks references.

### Modified

- `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — Added `attestedKeyId` + `lastHeartbeatAt` constants with exact raw values `device.attestedKeyId` + `device.lastHeartbeatAt` per CONTEXT.md specifics lines 177-178; inline comment cites D-01 + D-03 and names the downstream consumer plans (03, 06, 07, 09) to deter renames.
- `validationLedger/Core/Storage/Keychain/KeychainScope.swift` — Extended the `.session` case doc-comment to explicitly enumerate the D-03 + D-07 exclusions alongside the existing installUUID exclusion. The `contains(_:)` body is unchanged — the D-03 invariant is enforcement-by-omission (Plan 02 adds the pinning test that fails loud if a future change moves either key into the session scope).
- `validationLedger.xcodeproj/project.pbxproj` — Added `CODE_SIGN_ENTITLEMENTS = validationLedger/validationLedger.entitlements;` to both Debug (`EE92A0CD...`) + Release (`EE92A0CE...`) buildSettings of the `validationLedger` target. Diff is 2 lines; no other pbxproj state touched.

## Decisions Made

- **Location of `validationLedger.entitlements`.** The plan's `files_modified` path is `validationLedger/validationLedger.entitlements` — that is, inside the `validationLedger/` app-source folder (so it sits alongside `App/Info.plist`). Placed it there because CODE_SIGN_ENTITLEMENTS paths in pbxproj are SRCROOT-relative and the plan's acceptance grep explicitly searches for `CODE_SIGN_ENTITLEMENTS = validationLedger/validationLedger.entitlements` as that exact relative string.
- **Simulator run for `xcodebuild build` verification.** The plan's verify command specified `iPhone 15`. The local toolchain (Xcode 26.4) ships with iPhone 17 simulators, not iPhone 15 — used `iPhone 17` as the destination. Outcome equivalent; build succeeded.
- **Decision-ID citation distribution.** Plan acceptance required D-01 / D-09 / D-12 each to appear at least once across the four new Attestation files. All six Wave-1 decisions (D-01, D-02, D-03, D-04, D-09, D-12) now have at least one artifact citing them (combined across Swift headers + ADR + runbook).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Xcodebuild reordered project.pbxproj sections on first build**
- **Found during:** Task 1 (first `xcodebuild build` verification)
- **Issue:** Running `xcodebuild` against the project for the first time in this worktree caused Xcode 26.4 to reorder the pbxproj sections (moved `PBXContainerItemProxy` and `PBXFileSystemSynchronizedBuildFileExceptionSet` to the top of the file). Content was equivalent but the diff was noisy and would conflate unrelated reordering with the Task 3 CODE_SIGN_ENTITLEMENTS edit.
- **Fix:** Reverted the pbxproj after the Task 1 build with `git checkout -- validationLedger.xcodeproj/project.pbxproj` so Task 3's pbxproj commit contains ONLY the 2-line CODE_SIGN_ENTITLEMENTS addition.
- **Files modified:** validationLedger.xcodeproj/project.pbxproj (reverted, not committed)
- **Verification:** Subsequent Task 2 + Task 3 `xcodebuild build` runs did NOT re-reorder (Xcode's reorder is a one-time-per-worktree event). The final Task 3 pbxproj diff is exactly 2 lines as planned.
- **Committed in:** N/A (revert only; Task 3 commit `6ffd2f2` carries the clean 2-line edit).

---

**Total deviations:** 1 auto-fixed (1 blocking — a build-tool side-effect cleanup, not a code change)
**Impact on plan:** Zero. The plan executed exactly as written; the one "deviation" was a surgical revert of an xcodebuild side-effect so the CODE_SIGN_ENTITLEMENTS commit stays surgical.

## Issues Encountered

- None. All three tasks executed without blockers. `xcodebuild build` succeeded on first attempt after each task. `plutil -lint` succeeded first try. All grep-based acceptance criteria matched on first check.

## TDD Gate Compliance

Not applicable. Plan frontmatter `type: execute`, not `type: tdd`. Task 2's D-03 invariant has a deferred pinning test explicitly called out in the plan as landing in Plan 02 (Wave 0 tests). This is documented in the acceptance criteria of Task 2 and re-documented in both the modified KeychainScope.swift doc-comment and this Summary — no TDD gate is violated.

## User Setup Required

None — no external service configuration required. The entitlement is a build-time code-signing input, not a runtime configuration. Provisioning profile must include the App Attest capability before a real-device build — that is a dev-team signing workflow note, not an app config step (and is called out in docs/attestation-rotation.md + docs/adr/0005-three-key-device-register-payload.md References section).

## Next Phase Readiness

**Ready for Wave 2 (Plan 02 — Wave 0 tests) and Wave 2 execution (Plans 03 + 04):**

- Plan 02 (Wave 0 tests) can pin:
  - `testAttestedKeyIdNotInSessionScope` — asserts `KeychainScope.session.contains(.attestedKeyId) == false`
  - `testLastHeartbeatAtNotInSessionScope` — same for lastHeartbeatAt
  - AttestationStatus round-trip encoding tests (6 cases, lowercase raw values)
  - TrustTier round-trip decoding tests (2 cases)
- Plan 03 (DCAppAttestAttestationService + SimulatorBypassAttestationService) can implement against the landed protocol without any protocol-shape renegotiation — all four methods are fixed.
- Plan 04 (DeviceRegisterEndpoint extension + DeviceChallengeEndpoint + DeviceHeartbeatEndpoint) can import AttestationStatus + TrustTier by name.
- Plan 06 (AppContainer DI wiring + preflightAttestationEntitlement mirror) can cite ADR 0005 directly; the entitlement is already embedded by codesign so preflight logic sees it at runtime.
- Plan 07 (DevMenu Re-attest row) can call `container.attestationService.clearPersistedKeyId()` per the protocol + per the attestation-rotation runbook's "Manual Re-attestation (DEBUG-only)" section.

**No blockers. No open questions raised during execution.** RESEARCH Open Question 1 (exact backend error-code field names) is documented as a backend-coordination item in the runbook but does not block Plan 02 or Plan 03 — the client emits `AttestationError.underlying(NSError)` as the catch-all until the backend team confirms the wire-format strings.

---

## Self-Check: PASSED

**Files verified present:**
- FOUND: validationLedger/Core/Attestation/AttestationStatus.swift
- FOUND: validationLedger/Core/Attestation/TrustTier.swift
- FOUND: validationLedger/Core/Attestation/AttestationError.swift
- FOUND: validationLedger/Core/Attestation/AttestationService.swift
- FOUND: validationLedger/Core/Storage/Keychain/KeychainKey.swift (modified)
- FOUND: validationLedger/Core/Storage/Keychain/KeychainScope.swift (modified)
- FOUND: validationLedger/validationLedger.entitlements
- FOUND: docs/adr/0005-three-key-device-register-payload.md
- FOUND: docs/attestation-rotation.md
- FOUND: validationLedger.xcodeproj/project.pbxproj (modified, +2 lines)

**Commits verified present in git log:**
- FOUND: 534ad16 feat(04-01): add Attestation types + protocol
- FOUND: 0d50f11 feat(04-01): add attestedKeyId + lastHeartbeatAt Keychain keys
- FOUND: 6ffd2f2 feat(04-01): add App Attest entitlement + ADR 0005 + attestation-rotation runbook

**Build:** `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` → `** BUILD SUCCEEDED **`

**plutil:** `plutil -lint validationLedger/validationLedger.entitlements` → `OK`

---

*Phase: 04-app-attest-physical-device-ci-hardening*
*Completed: 2026-04-22*
