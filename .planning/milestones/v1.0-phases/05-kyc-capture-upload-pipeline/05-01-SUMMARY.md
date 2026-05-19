---
phase: 05-kyc-capture-upload-pipeline
plan: 01
subsystem: testing
tags: [networking, swift-testing, xctest, bgtaskscheduler, info-plist, kyc, fixtures, tdd-red]

# Dependency graph
requires:
  - phase: 02-networking-contract-device-keys
    provides: APIEndpoint protocol, APIClient facade, MockURLProtocol fixture registry, KYCUploadCommitEndpoint template
provides:
  - APIEndpoint.headers per-request header seam wired through APIClient.buildRequest
  - OTPVerifyEndpoint.Response.kycStatus optional field (D-13)
  - KYCSubmitEndpoint — POST /kyc/submit D-03 thin finalizer
  - BGTaskScheduler Info.plist registration (com.maldin.validationLedger.kyc-upload)
  - 6 new KYC JSON fixtures + 1 updated otp-verify fixture
  - 15 compiling RED simulator test suites under validationLedgerTests/KYC/
  - 1 compiling RED device-test scaffold (DLExtractionScannerDeviceTests)
affects: [05-02, 05-03, 05-04, 05-05, 05-06, 05-07, 05-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-request header seam — APIEndpoint.headers with [:] default extension, applied in buildRequest before the interceptor loop"
    - "Wave 0 contract-first scaffolding — all Phase 5 contract changes + RED test suites land once so plans 02-08 build against a fixed surface"
    - "Nyquist RED scaffold — every later <verify><automated> references a compiling-but-failing suite that already exists"

key-files:
  created:
    - validationLedger/Core/Networking/Endpoints/KYCSubmitEndpoint.swift
    - validationLedgerTests/KYC/ (15 RED simulator test suites)
    - validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift
    - validationLedgerTests/Networking/Fixtures/kyc-status-pending.json
    - validationLedgerTests/Networking/Fixtures/kyc-status-under-review.json
    - validationLedgerTests/Networking/Fixtures/kyc-status-verified.json
    - validationLedgerTests/Networking/Fixtures/kyc-status-rejected.json
    - validationLedgerTests/Networking/Fixtures/kyc-submit-success.json
    - validationLedgerTests/Networking/Fixtures/kyc-submit-failure.json
  modified:
    - validationLedger/Core/Networking/APIEndpoint.swift
    - validationLedger/Core/Networking/APIClient.swift
    - validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift
    - validationLedger/App/Info.plist
    - validationLedgerTests/Networking/Fixtures/otp-verify-success.json
    - validationLedgerTests/Networking/APIClientEndpointTests.swift

key-decisions:
  - "kycStatus declared String? optional with no default — absent/malformed value decodes to nil, downstream routing fail-closes to the KYC gate (threat T-05-01-01)"
  - "APIEndpoint.headers applied before the requestInterceptors loop so a caller-supplied Idempotency-Key reaches IdempotencyInterceptor (which already skips a present key)"
  - "RED scaffolds use #expect(Bool(false), ...) placeholders — they reference no not-yet-existing production type, so they compile cleanly and fail by design"

patterns-established:
  - "Per-request header seam: protocol requirement + [:] default extension keeps every existing endpoint compiling unchanged"
  - "RED suite header comment names the requirement and the plan number that delivers GREEN"

requirements-completed: [UPL-05]

# Metrics
duration: 33min
completed: 2026-05-16
---

# Phase 5 Plan 01: Wave 0 Scaffolding Summary

**Phase 5 networking contract (header seam, kycStatus field, KYCSubmitEndpoint) + BGTask Info.plist registration + 15 RED simulator suites + 1 RED device-test scaffold + 7 JSON fixtures, all compiling against a fixed target surface.**

## Performance

- **Duration:** 33 min
- **Started:** 2026-05-16T22:00:00Z
- **Completed:** 2026-05-16T22:33:00Z
- **Tasks:** 3
- **Files modified:** 25 (10 created, 6 modified, 9 RED suites — counted in created)

## Accomplishments

- Landed the full Phase 5 networking contract once: `APIEndpoint.headers` per-request header seam wired through `APIClient.buildRequest`, `OTPVerifyEndpoint.Response.kycStatus` optional field (D-13), and the new `KYCSubmitEndpoint` D-03 thin finalizer (`POST /kyc/submit`).
- Registered the BGTask continuation identifier (`com.maldin.validationLedger.kyc-upload`) + `processing` background mode in `Info.plist` so `BGTaskScheduler.register` does not trap at runtime (UPL-05).
- Created 15 compiling RED simulator test suites under `validationLedgerTests/KYC/` and 1 RED XCTest device-test scaffold (`DLExtractionScannerDeviceTests`) — every later plan's automated verification now references a suite that already exists (Nyquist rule).
- Added 6 new KYC JSON fixtures + updated `otp-verify-success.json`, plus an OTP-verify regression test proving the optional `kycStatus` addition is backward compatible and a `KYCSubmitEndpoint` decode test.

## Task Commits

Each task was committed atomically:

1. **Task 1: APIEndpoint header seam + OTPVerifyEndpoint kycStatus + KYCSubmitEndpoint** - `ad6c6f7` (feat)
2. **Task 2: BGTask Info.plist keys + 7 JSON fixtures** - `1f03045` (chore)
3. **Task 3: 15 RED simulator suites + device-test scaffold + regression tests** - `f3af65d` (test)

**Plan metadata:** see final docs commit.

## Files Created/Modified

- `validationLedger/Core/Networking/APIEndpoint.swift` - Added `headers` protocol requirement + `[:]` default extension
- `validationLedger/Core/Networking/APIClient.swift` - `buildRequest` applies `endpoint.headers` before the interceptor loop
- `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` - Added optional `kycStatus: String?` + CodingKeys case
- `validationLedger/Core/Networking/Endpoints/KYCSubmitEndpoint.swift` - New `POST /kyc/submit` D-03 finalizer endpoint
- `validationLedger/App/Info.plist` - `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes=processing`
- `validationLedgerTests/Networking/Fixtures/otp-verify-success.json` - Added `kyc_status: "verified"`
- `validationLedgerTests/Networking/Fixtures/kyc-status-{pending,under-review,verified,rejected}.json` - 4 KYC-status fixtures
- `validationLedgerTests/Networking/Fixtures/kyc-submit-{success,failure}.json` - 2 KYC-submit fixtures
- `validationLedgerTests/Networking/APIClientEndpointTests.swift` - OTP-verify kycStatus regression test + KYCSubmitEndpoint success test
- `validationLedgerTests/KYC/*.swift` (15 files) - RED simulator suites: KYCUploader (Tests/Resume/Retry/Progress/Idempotency), GPSMetadataInjector, KYCSessionStore, KYCStatusViewModel, KYCReviewViewModel, RejectionReasonCode, GeoContext, FaceQualityGate, DLExtractionFormat, KYCCoordinator, BackgroundUploadScheduling
- `validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift` - RED XCTest device scaffold for the KYC-03 DataScannerViewController integration
- `validationLedger.xcodeproj/project.pbxproj` - Xcode-normalized explicit target dependencies (build-tool generated)

## Decisions Made

- `kycStatus` is `String?` optional with no default — an absent or malformed value decodes to `nil`, and Plan 05-07 routing treats `nil` as "not verified" (fail-closed to the KYC gate, not the role shell). Mitigates threat T-05-01-01.
- The header seam runs before the `requestInterceptors` loop so a caller-supplied `Idempotency-Key` (set later by `KYCUploader`) reaches `IdempotencyInterceptor`, which already skips a present key.
- RED scaffolds use `#expect(Bool(false), "RED: ...")` placeholders rather than referencing not-yet-existing production types — this keeps every file compiling cleanly while still failing by design.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator destination `iPhone 16` unavailable — substituted `iPhone 16e`**
- **Found during:** Task 1 (build verification)
- **Issue:** The plan's `<verify><automated>` commands target `platform=iOS Simulator,name=iPhone 16`, but this environment's installed simulators only include `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, and `iPhone Air` — no plain `iPhone 16`.
- **Fix:** Ran all `xcodebuild build` / `build-for-testing` / `test` verifications against `iPhone 16e` instead. Source/test code is destination-agnostic; only the verification destination changed.
- **Files modified:** None (verification command only).
- **Verification:** `** BUILD SUCCEEDED **` and `** TEST BUILD SUCCEEDED **` on `iPhone 16e`.
- **Committed in:** N/A (no code change).

**2. [Rule 1 - Plan counting error] Created 15 KYC simulator suites, not 14**
- **Found during:** Task 3 (file creation)
- **Issue:** The plan's task body and acceptance criteria say "14 simulator test files", but both the `files_modified` frontmatter (15 enumerated `validationLedgerTests/KYC/*Tests.swift` paths) and the suite→requirement map in the task body enumerate **15** distinct suites (KYCUploader x5 + 10 others).
- **Fix:** Created all 15 enumerated suites — the explicit named list is authoritative over the "14" count. Each maps to a named Phase 5 requirement and the plan that turns it GREEN.
- **Files modified:** `validationLedgerTests/KYC/` (15 files).
- **Verification:** `ls validationLedgerTests/KYC/ | wc -l` returns 15; all 15 compile via `build-for-testing`; `grep -rl "import Testing"` returns 15.
- **Committed in:** `f3af65d` (Task 3 commit).

**3. [Rule 3 - Blocking] `plutil -lint` does not validate JSON on this toolchain — used `python3 json.tool`**
- **Found during:** Task 2 (fixture verification)
- **Issue:** The plan's Task 2 `<verify>` runs `plutil -lint` on the JSON fixtures, but this environment's `plutil` rejects JSON files with "Unexpected character { at line 1" — even the pre-existing `kyc-status-success.json` fails the same way. `plutil -lint` only validates plist content here, not JSON.
- **Fix:** Validated all 7 JSON fixtures with `python3 -c "json.load(...)"` (equivalent JSON well-formedness check). `Info.plist` still validated with `plutil -lint` (it is a real plist — passed OK).
- **Files modified:** None (verification command only).
- **Verification:** All 7 fixtures report `OK` via `python3 json.load`; `Info.plist` reports `OK` via `plutil -lint`; `build-for-testing` (which bundles + decodes the fixtures) succeeds.
- **Committed in:** N/A (no code change).

---

**Total deviations:** 3 auto-fixed (2 blocking environment/tooling, 1 plan counting error).
**Impact on plan:** No scope creep. Deviations 1 and 3 are local toolchain substitutions for unavailable simulator/lint tools — the delivered artifacts are unchanged. Deviation 2 follows the plan's own enumerated file list over an inconsistent count in prose; all 15 suites are required by later plans.

## Issues Encountered

- The Xcode project file (`project.pbxproj`) was normalized by Xcode during the first build — explicit `PBXContainerItemProxy` target-dependency entries were added for the test targets. This is benign build-tool output that makes the test targets' dependency on the app target explicit; included in the final docs commit to keep the project file consistent.

## Known Stubs

The 15 RED simulator suites and the 1 RED device-test scaffold are **intentional stubs** — they fail by design (`#expect(Bool(false), ...)` / `XCTFail("RED: ...")`) until later plans land production code. This is the Wave 0 Nyquist-rule contract: each suite's header comment names the requirement and the plan number that turns it GREEN (05-02 through 05-07). Not a defect — the plan's success criteria explicitly require these suites to be RED.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The Phase 5 networking contract is fully landed and frozen: header seam, `kycStatus` field, `KYCSubmitEndpoint`. Plans 05-02 through 05-08 build against a stable target surface with no contract churn.
- BGTask Info.plist registration is in place for UPL-05.
- 15 RED simulator suites + 1 RED device-test scaffold compile and fail by design — plans 05-02 (KYCSessionStore, RejectionReasonCode), 05-03 (GPSMetadataInjector, GeoContext, FaceQualityGate), 05-04 (KYCUploader x5), 05-05 (DLExtractionFormat, KYCCoordinator, device scanner), 05-06 (KYCStatusViewModel, KYCReviewViewModel), 05-07 (BackgroundUploadScheduling) each turn their named suite GREEN.
- No existing test regressed — the OTP-verify regression test confirms the optional `kycStatus` addition is backward compatible.

## Self-Check: PASSED

All created files verified on disk (KYCSubmitEndpoint.swift, DLExtractionScannerDeviceTests.swift, kyc-submit-success.json, KYCUploaderTests.swift, 05-01-SUMMARY.md). All 3 task commits verified in git history (ad6c6f7, 1f03045, f3af65d).

---
*Phase: 05-kyc-capture-upload-pipeline*
*Completed: 2026-05-16*
