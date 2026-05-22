---
phase: 02-networking-contract-device-keys
plan: 03
subsystem: networking
tags: [ios, networking, fixtures, decode-tests, mock, swift-testing, net-02, m1]

# Dependency graph
requires:
  - phase: 02-networking-contract-device-keys
    plan: 01
    provides: "MockURLProtocol.register/reset NSLock-guarded API"
  - phase: 02-networking-contract-device-keys
    plan: 02
    provides: "APIEndpoint protocol + APIClient facade + 7 M1 endpoint structs"
provides:
  - "MockURLProtocol.registerFixture<E: APIEndpoint>(for:path:method:statusCode:body:) — one-line fixture registration for every Wave 1+ test"
  - "14 JSON fixtures (7 endpoints × success + failure) under validationLedgerTests/Networking/Fixtures/ — contract source-of-truth for Plan 04/05/07 and Phase 3"
  - "FixtureLoader.loadFixture(name) — bundle-scoped JSON loader using Bundle(for: FixtureBundleMarker.self); subdirectory-first lookup with flat fallback"
  - "APIClientEndpointTests — 14 @Test cases proving every M1 endpoint decodes success + fails with NetworkError.httpError on failure fixtures"
  - "Explicit CodingKeys pattern for Response types with trailing-acronym property names (e.g., `*ID`)"
  - "Core/Networking/Mock/ directory layout — MockURLProtocol.swift + MockFixture.swift colocated"
affects:
  - "02-04 (Interceptors) — RetryInterceptor tests use registerFixture + FixtureLoader for the happy-path + retryable-5xx fixtures"
  - "02-05 (Cert pinning) — may use registerFixture to assert pinningFailed propagation; FixtureLoader available"
  - "02-07 (Environment / AppContainer) — integration tests will reuse the 14 fixtures end-to-end against the wired APIClient"
  - "03 (Phase 3 AuthRepository) — OTPRequestEndpoint + OTPVerifyEndpoint fixtures exist; AuthRepository tests can register them directly"
  - "05 (Phase 5 KYCUploader) — 4 KYC fixtures exist; KYCUploader tests reuse them across init/chunk/commit/status"
  - "Future endpoint additions — any new endpoint with acronym-in-property-name needs explicit CodingKeys with camelCase raw values"

# Tech tracking
tech-stack:
  added: []  # Foundation + swift-testing + JSON; no new SPM deps
  patterns:
    - "registerFixture<E: APIEndpoint>(...) — type-parameterized fixture registration; match by path + method, endpoint type is documentation-only"
    - "Bundle(for: FixtureBundleMarker.self) — private-class bundle-marker pattern for XCTest + Swift Testing resource access (no Bundle.module dependency)"
    - "Explicit CodingKeys with camelCase raw values when .convertFromSnakeCase is active — acronyms in property names (*ID) require this bridge because strategy maps `_id` to lowercase `Id`"
    - "makeClient() test helper — ephemeral URLSessionConfiguration + MockURLProtocol + URLSessionNetworkClient + APIClient per test (zero cross-test state)"
    - "assertHTTPError generic helper — catch NetworkError.httpError, assert status; Issue.record on success-or-wrong-error"
    - "Per-test MockURLProtocol.reset() at entry + defer { reset() } — triple-layer defense alongside @Suite(.serialized)"

key-files:
  created:
    - "validationLedger/Core/Networking/Mock/MockFixture.swift"
    - "validationLedgerTests/Networking/APIClientEndpointTests.swift"
    - "validationLedgerTests/Networking/FixtureLoader.swift"
    - "validationLedgerTests/Networking/Fixtures/otp-request-success.json"
    - "validationLedgerTests/Networking/Fixtures/otp-request-failure.json"
    - "validationLedgerTests/Networking/Fixtures/otp-verify-success.json"
    - "validationLedgerTests/Networking/Fixtures/otp-verify-failure.json"
    - "validationLedgerTests/Networking/Fixtures/device-register-success.json"
    - "validationLedgerTests/Networking/Fixtures/device-register-failure.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-init-success.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-init-failure.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-chunk-success.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-chunk-failure.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-commit-success.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-upload-commit-failure.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-status-success.json"
    - "validationLedgerTests/Networking/Fixtures/kyc-status-failure.json"
  modified:
    - "validationLedger/Core/Networking/Mock/MockURLProtocol.swift — moved from Core/Networking/MockURLProtocol.swift via `git mv`; header comment updated for new path"
    - "validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift — explicit CodingKeys for otpSessionID"
    - "validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift — explicit CodingKeys for userID"
    - "validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift — explicit CodingKeys for deviceID"
    - "validationLedger/Core/Networking/Endpoints/KYCUploadInitEndpoint.swift — explicit CodingKeys for uploadID"
    - "validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift — explicit CodingKeys for artifactID"
    - "validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift — explicit CodingKeys for Artifact.artifactID"

key-decisions:
  - "Fixture JSON files land flat in the test bundle, not under a Fixtures/ subdirectory — Xcode's PBXFileSystemSynchronizedRootGroup auto-includes JSON resources but flattens the directory when building the .xctest bundle. FixtureLoader tries subdirectory-first lookup (Fixtures/<name>.json) then falls back to flat (<name>.json). Flat-lookup is the active path."
  - "CodingKeys raw values must be the CAMEL-CASE form when .convertFromSnakeCase is active — the decoder first converts JSON snake_case to camelCase, THEN looks up CodingKeys. First attempt used snake_case raw values; the decoder then complained \"Key 'session_token' not found\" because it was looking for 'sessionToken'. Correct raw value: 'sessionToken' (or omitted to use synthesized). For acronym bridges: `case userID = \"userId\"` (lowercase 'd' from convertFromSnakeCase)."
  - "registerFixture's `for: E.Type` parameter is documentation-only — match is by path + method strings. The endpoint type makes the test fluent ('this fixture is bound to OTPRequestEndpoint') and enforces at the call site that readers think in endpoints, not raw paths."
  - "ISO-8601 assertion uses a fresh ISO8601DateFormatter().date(from: \"2026-04-21T12:00:00Z\") — exercises APIClient's .iso8601 strategy end-to-end. If a future decoder change drops fractional seconds or breaks Z-suffix handling, DeviceRegisterEndpoint's test catches it."
  - "Cross-suite parallelism requires -parallel-testing-enabled NO when running multiple MockURLProtocol-dependent suites together — Swift Testing runs sibling @Suites in parallel by default even when each has `.serialized`. `.serialized` only serializes WITHIN a suite. The plan's single-suite <verify> command passes as-is; multi-suite runs need the flag. This matches Phase 1's CI policy."
  - "Local test destination: iPhone 17 Pro / iOS 26.4 — consistent with Phase 1 and Plan 02-01/02-02 precedent. Dev machine has no iOS 17.5 runtime; CI pins 17.5 per docs/ci.md."

patterns-established:
  - "registerFixture<E: APIEndpoint>(...) is the canonical fixture-registration path for Wave 1+ tests — Plan 04 RetryInterceptor + Plan 05 pinning + Plan 07 AppContainer integration all use this API"
  - "FixtureLoader.loadFixture(name) is the canonical fixture-loading path for test bundles — any future test that needs a committed JSON blob uses this helper"
  - "Explicit CodingKeys with camelCase raw values — required for any Response/RequestBody property ending in an all-caps acronym (*ID, *URL, *UUID) when .convertFromSnakeCase is enabled. Document in endpoint file comment. This becomes a project-wide convention for future endpoints."
  - "Bundle(for: <PrivateMarker>.self) — private final class marker pattern for test-bundle access; works identically in XCTest and Swift Testing"
  - "Per-test MockURLProtocol.reset() at entry + defer — triple-layer defense (suite .serialized + entry reset + defer reset). This becomes mandatory boilerplate for every @Test that touches the mock registry."

requirements-completed:
  - NET-02   # every M1 endpoint decodes its success + failure fixture; unit test proves decode contract

# Metrics
duration: ~13min
completed: 2026-04-21
---

# Phase 2 Plan 03: Fixtures + APIClient Endpoint Decode Tests Summary

**14 JSON fixtures (7 M1 endpoints × success + failure) + MockFixture.registerFixture extension + FixtureLoader helper + APIClientEndpointTests (14 @Test cases) — closes NET-02 and makes the wire contract executable, not descriptive.**

## Performance

- **Duration:** ~13 min (817s wall clock)
- **Started:** 2026-04-21T19:28:20Z
- **Completed:** 2026-04-21T19:41:57Z
- **Tasks:** 3 (all atomic, each with its own commit)
- **Files created:** 18 (1 extension, 1 FixtureLoader, 14 JSON fixtures, 1 test file, +1 SUMMARY pending)
- **Files modified:** 7 (MockURLProtocol.swift moved; 6 endpoint files updated with explicit CodingKeys)

## Accomplishments

- **NET-02 landed in full:** 14 JSON fixture files are the canonical wire-contract source-of-truth. Every M1 endpoint has a success fixture + a failure fixture. The APIClientEndpointTests suite proves each fixture decodes into the typed `E.Response` for success paths and throws `NetworkError.httpError` with the expected status code for failure paths.
- **registerFixture API shipped:** `MockURLProtocol.registerFixture<E: APIEndpoint>(for:path:method:statusCode:body:)` is the one-line fixture-registration API. Default header is `Content-Type: application/json`, overridable. Plan 04+ and Phase 3+ reuse this verbatim.
- **FixtureLoader bundle-scoped JSON loader:** `FixtureLoader.loadFixture("otp-request-success")` returns `Data` via `Bundle(for: FixtureBundleMarker.self)`. Subdirectory-first (`Fixtures/<name>.json`) with flat fallback (`<name>.json`). The flat path is active because Xcode's `PBXFileSystemSynchronizedRootGroup` flattens JSON resources into the bundle root.
- **Directory reorg complete:** `MockURLProtocol.swift` moved from `Core/Networking/` to `Core/Networking/Mock/`; `MockFixture.swift` lives alongside it. `validationLedgerTests/Networking/Fixtures/` directory established for the 14 JSON files.
- **Contract-drift regression guard in place:** The suite uses `@Suite(.serialized)` and every test resets `MockURLProtocol.handlers` at entry and in `defer`. Fixtures are tested ON the real APIClient decode path (not a parallel stand-alone decode) — any future drift between fixture wire shape and endpoint Response type fails fast.
- **Two testing invariants proven end-to-end:** (1) `APIClient.defaultDecoder()`'s `.iso8601` date strategy correctly parses `"2026-04-21T12:00:00Z"` into `DeviceRegisterEndpoint.Response.registeredAt`. (2) `.convertFromSnakeCase` + explicit `CodingKeys` correctly bridges snake_case wire keys into camelCase-with-acronym Swift property names.

## Task Commits

Each task was committed atomically:

1. **Task 1: Move MockURLProtocol + add MockFixture.registerFixture extension** — `ff91ee8` (feat)
2. **Task 2: 14 JSON fixtures + FixtureLoader** — `9665b18` (feat)
3. **Task 3: APIClientEndpointTests + CodingKeys acronym bridge** — `526e29b` (feat)

**Plan metadata commit:** pending (final SUMMARY commit lands after this file is written)

## Files Created/Modified

### Created

- `validationLedger/Core/Networking/Mock/MockFixture.swift` — `extension MockURLProtocol` with `public static func registerFixture<E: APIEndpoint>(for:path:method:statusCode:body:headers:)`. Default Content-Type header, caller-overridable.
- `validationLedgerTests/Networking/APIClientEndpointTests.swift` — 14 @Test cases under `@Suite("APIClient — M1 endpoint contracts (NET-01 + NET-02)", .serialized)`. Private `makeClient()` + `assertHTTPError` helpers.
- `validationLedgerTests/Networking/FixtureLoader.swift` — `enum FixtureLoader` with `static func loadFixture(_:) throws -> Data`. Uses `private final class FixtureBundleMarker {}` + `Bundle(for: FixtureBundleMarker.self)`.
- 14 JSON fixtures under `validationLedgerTests/Networking/Fixtures/`:
  - `otp-request-success.json` / `otp-request-failure.json`
  - `otp-verify-success.json` / `otp-verify-failure.json`
  - `device-register-success.json` / `device-register-failure.json`
  - `kyc-upload-init-success.json` / `kyc-upload-init-failure.json`
  - `kyc-upload-chunk-success.json` / `kyc-upload-chunk-failure.json`
  - `kyc-upload-commit-success.json` / `kyc-upload-commit-failure.json`
  - `kyc-status-success.json` / `kyc-status-failure.json`

### Modified

- `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — moved from `Core/Networking/MockURLProtocol.swift` via `git mv`; file header updated to document the new location. Logic unchanged from Plan 02-01's NSLock-guarded registry.
- `validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift` — added explicit `CodingKeys` to `Response`: `case otpSessionID = "otpSessionId"`, `case expiresInSeconds`.
- `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` — added explicit `CodingKeys` to `Response`: `case sessionToken`, `case role`, `case userID = "userId"`.
- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — added explicit `CodingKeys` to `Response`: `case deviceID = "deviceId"`, `case registeredAt`.
- `validationLedger/Core/Networking/Endpoints/KYCUploadInitEndpoint.swift` — added explicit `CodingKeys` to `Response`: `case uploadID = "uploadId"`, `case chunkSize`.
- `validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` — added explicit `CodingKeys` to `Response`: `case artifactID = "artifactId"`, `case status`.
- `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` — added explicit `CodingKeys` to nested `Response.Artifact`: `case artifactID = "artifactId"`, `case status`, `case rejectionReason`. Outer `Response`'s `overallStatus` + `artifacts` properties use synthesized CodingKeys (no acronym, so `.convertFromSnakeCase` handles them).

## Decisions Made

1. **Fixture JSON files live flat in the test bundle, not under a `Fixtures/` subdirectory.** Xcode's `PBXFileSystemSynchronizedRootGroup` auto-includes the JSON files under `validationLedgerTests/Networking/Fixtures/` but flattens them when building the `.xctest` bundle. Verified post-build: `find build -name "*.json" -path "*.xctest*"` returns all 14 at the bundle root, no `Fixtures/` subdirectory. `FixtureLoader` handles both layouts (subdirectory-first, flat-fallback); the flat-fallback path is the one actually hit. No `Copy Bundle Resources` phase modification needed.
2. **CodingKeys raw values must be in the CAMEL-CASE form when `.convertFromSnakeCase` is active.** First attempt used snake_case raw values (`case userID = "user_id"`); decoder failed with "Key 'session_token' not found" because `.convertFromSnakeCase` transforms JSON keys to camelCase BEFORE CodingKeys lookup. Correct form: `case userID = "userId"` (lowercase 'd' from strategy output). Non-acronym properties may omit the raw value to use synthesized CodingKey.
3. **registerFixture takes `for: E.Type` as documentation-only; match is by path + method strings.** The plan's sketch specified this and it holds up in practice — readers of the call site see "this fixture is bound to OTPRequestEndpoint" at a glance, but the match semantics are purely `request.url?.path == path && request.httpMethod == method.rawValue`. No runtime use of the endpoint type.
4. **ISO-8601 date assertion is a fresh `ISO8601DateFormatter().date(from: "2026-04-21T12:00:00Z")`.** Exercises APIClient's `.iso8601` strategy end-to-end. If a future APIClient default-decoder change drops fractional seconds or breaks Z-suffix handling, the DeviceRegisterEndpoint success test catches it immediately — not in Plan 06 or Plan 07.
5. **Cross-suite parallelism requires `-parallel-testing-enabled NO` when running multiple MockURLProtocol-dependent suites together.** Swift Testing runs sibling `@Suite`s in parallel by default; `.serialized` only serializes WITHIN a suite. This is a known Swift Testing limitation for shared global state. The plan's `<verify>` command (single suite) passes cleanly. Matches Phase 1's CI policy precedent.
6. **Local test destination: iPhone 17 Pro / iOS 26.4** — consistent with Phase 1 + Plan 02-01/02-02 precedent. Dev machine has no iOS 17.5 runtime; CI pins 17.5 per docs/ci.md.

## Deviations from Plan

Three deviations — two auto-fixed Rule 1/2, one environmental:

### 1. [Rule 1 - Bug] Missing CodingKeys for acronym-in-property-name Response types

- **Found during:** Task 3, first test run (the tests caught the contract drift exactly as T-02-09 predicted — fixture-to-Response-type drift fails fast).
- **Issue:** Six endpoint Response types have property names ending in all-caps acronyms (`otpSessionID`, `userID`, `deviceID`, `uploadID`, `artifactID`). JSONDecoder's `.convertFromSnakeCase` strategy maps `otp_session_id` → `otpSessionId` (lowercase 'd'), not `otpSessionID` (uppercase). Decoder threw `keyNotFound` on every success fixture (6 of 7 endpoints; KYCUploadChunkEndpoint.Response has no acronym property and worked fine).
- **First-attempt fix:** Added explicit CodingKeys with **snake_case** raw values (`case userID = "user_id"`). Rebuilt, ran tests: **still failed** with `keyNotFound`, now for the snake_case key. Root cause: `.convertFromSnakeCase` transforms JSON keys BEFORE CodingKeys lookup, so CodingKeys raw values must be the post-conversion CAMEL-CASE form (`case userID = "userId"`).
- **Second-attempt fix (successful):** Corrected raw values to camelCase. Non-acronym properties (like `sessionToken`, `registeredAt`, `chunkSize`) can omit the raw value and use synthesized CodingKey.
- **Files modified:** `OTPRequestEndpoint.swift`, `OTPVerifyEndpoint.swift`, `DeviceRegisterEndpoint.swift`, `KYCUploadInitEndpoint.swift`, `KYCUploadCommitEndpoint.swift`, `KYCStatusEndpoint.swift`. All bundled into the Task 3 commit.
- **Commit:** `526e29b`
- **Why this wasn't in the plan:** Plan 02-02's endpoint definitions relied entirely on `.convertFromSnakeCase` as the single-source bridge between wire snake_case and Swift camelCase. The acronym edge case in JSONDecoder is well-known but was missed at the endpoint-definition stage because Plan 02-02 didn't include decode tests. Plan 03's tests exposed it. This is exactly the regression-guard purpose documented in the plan's threat model (T-02-09). The fix is permanent and establishes a pattern for all future endpoints.

### 2. [Rule 2 - Test infra observation] Cross-suite parallelism in Swift Testing

- **Found during:** Task 3, after all 14 single-suite tests passed. Ran the full `Networking/` test subtarget (MockURLProtocolTests + MockURLProtocolRegistryTests + APIClientEndpointTests = 21 tests). 3 tests flaked — a `MockURLProtocolRegistryTests` test saw a 404 where it expected 200, and a `DeviceRegisterEndpoint` success test saw an `httpError(404)`.
- **Issue:** Swift Testing runs sibling `@Suite`s in parallel by default. Each of the three suites declares `.serialized`, but that only serializes tests WITHIN the suite. Across suites, `MockURLProtocol.handlers` (global state guarded by NSLock) is mutated concurrently by tests in different suites — one suite's `reset()` nukes another suite's registered fixture mid-flight.
- **Resolution:** Running with `-parallel-testing-enabled NO` passes 21/21. The plan's `<verify>` command scopes to a single suite (`-only-testing:validationLedgerTests/Networking/APIClientEndpointTests`) — that passes as-is with no flag change. This matches Phase 1's CI policy (Keychain tests use the same pattern).
- **Not fixed in code:** A scheme-level or parent-suite-level change is out of this plan's scope. Documenting here and recommending `-parallel-testing-enabled NO` for CI runs of the full Networking subtarget.
- **Follow-up recommendation (tracked for a future test-infra plan):** Either (a) restructure the three Networking suites under a common parent `@Suite` with `.serialized`, or (b) add `-parallel-testing-enabled NO` to the scheme's TestAction, or (c) make MockURLProtocol handler registry per-URLSession-configuration rather than global static. Option (c) is the most invasive but would enable full parallelism.

### 3. [Environmental] Local simulator: iPhone 17 Pro / iOS 26.4 instead of plan's iPhone 15 / iOS 17.5

- Plan `<verify>` block specifies `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. Dev machine has no iOS 17.5 runtime. Substituted `iPhone 17 Pro, OS=26.4` per Phase 1 + Plan 02-01/02-02 precedent. CI YAML still targets iOS 17.5.
- Not a plan deviation — environmental substitution documented in prior summaries; the plan acknowledges the CI-vs-local split.

## Test Bundle Resource Configuration

- **Question from plan `<output>`:** Did `PBXFileSystemSynchronizedRootGroup` auto-include the Fixtures directory, or did Xcode require explicit Copy Bundle Resources phase addition?
- **Answer:** `PBXFileSystemSynchronizedRootGroup` auto-included all 14 JSON files at build time. No pbxproj edit needed. **However**, the directory structure is FLATTENED in the resulting `.xctest` bundle — all 14 JSON files land at the bundle root, not under `Fixtures/`. `FixtureLoader`'s subdirectory-first / flat-fallback design handles this transparently. Tests currently hit the flat-lookup path.

## Decoder-Strategy Workaround

- **Question from plan `<output>`:** Any decoder-strategy workaround needed (e.g., ISO-8601 fractional seconds tripping the default iso8601 strategy)?
- **Answer:** No ISO-8601 workaround needed. `"2026-04-21T12:00:00Z"` parses cleanly with `.iso8601`.
- **Unexpected workaround: explicit CodingKeys for acronym-in-property-name Response types.** See Deviation 1. Any future endpoint with a property like `*ID` / `*URL` / `*UUID` needs the same bridge. The pattern is documented in comments in every affected endpoint file.

## Fixture Contract as Source-of-Truth

Per plan `<output>` and threat T-02-10: **the 14 fixtures are now the canonical wire-contract source-of-truth** for:

| Fixture | Consumed by (future) |
|---|---|
| `otp-request-*.json` | Plan 04 (retry), Plan 07 (integration), Phase 3 AuthRepository |
| `otp-verify-*.json` | Plan 04, Plan 07, Phase 3 AuthRepository |
| `device-register-*.json` | Plan 06 (DeviceFingerprint), Phase 3 post-OTP, Phase 4 DEV-04 |
| `kyc-upload-init-*.json` | Plan 05 (KYCUploader), Plan 07 |
| `kyc-upload-chunk-*.json` | Plan 05 chunk loop, Plan 05 UPL-02 resume |
| `kyc-upload-commit-*.json` | Plan 05 UPL-01 final step |
| `kyc-status-*.json` | Plan 05 KYC-05 status polling UI |

**Backend-alignment flag:** When the backend ships, iterate fixtures to match real wire output, verified by the same `APIClientEndpointTests` suite. Any endpoint whose fixture is out-of-date vs. backend will fail decode-test first, before any caller sees it.

## Reuse by Wave 1+ Plans

| Symbol introduced | Consumer plan / phase |
|---|---|
| `MockURLProtocol.registerFixture` | Plan 04 RetryInterceptor tests; Plan 05 pinning tests; Plan 07 integration tests; Phase 3 AuthRepository tests; Phase 5 KYCUploader tests |
| `FixtureLoader.loadFixture` | Every test in Wave 1+ that needs a committed JSON blob |
| 14 JSON fixtures | Listed in table above |
| Explicit CodingKeys pattern | Every future endpoint with acronym-in-property-name; documented in each affected endpoint file |
| `Core/Networking/Mock/` directory layout | Any future mock transport utilities (e.g., a mock retry-after clock) |

## Verification Results

### Invariant checks (grep + ls)

| Check | Expected | Actual |
|---|---|---|
| Files under `validationLedgerTests/Networking/Fixtures/` | 14 | 14 |
| `python3 -c "import json; json.load(open(...))"` on each fixture | valid | 14/14 valid |
| `public static func registerFixture` in MockFixture.swift | 1 | 1 |
| `@Test` count in APIClientEndpointTests.swift | 14 | 14 |
| `MockURLProtocol.reset()` calls in APIClientEndpointTests.swift | ≥14 | 28 (entry + defer per test) |
| `MockURLProtocol.registerFixture` calls in APIClientEndpointTests.swift | 14 | 14 |
| `client.request(` calls in APIClientEndpointTests.swift | 14 | 14 |
| `loadFixture(` calls in APIClientEndpointTests.swift | 14 | 14 |
| `.serialized` trait on APIClientEndpointTests suite | 1 | 1 |
| MockURLProtocol.swift at Core/Networking/Mock/MockURLProtocol.swift | yes | yes |
| MockURLProtocol.swift at Core/Networking/MockURLProtocol.swift (old location) | no | no |

### Build + test

- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath build` — **BUILD SUCCEEDED** (post-Task 1 and post-Task 3)
- `xcodebuild test ... -only-testing:validationLedgerTests/APIClientEndpointTests` (plan's verify command) — **Test run with 14 tests in 1 suite passed** in 0.046s. All 14 pass.
- Full Networking subtarget (3 suites, 21 tests) with `-parallel-testing-enabled NO` — **21/21 pass** in 0.056s.
- Full Networking subtarget with default parallelism — 18/21 pass; 3 cross-suite races (see Deviation 2). CI policy is `-parallel-testing-enabled NO`.
- Post-build fixture bundle check: `find build -name "*.json" -path "*.xctest*"` returns **14 files** (all flattened at bundle root).

## Issues Encountered

1. **CodingKeys acronym bug caught on first test run (Rule 1).** Took two fix-attempts — first attempt used snake_case CodingKeys raw values (wrong because `.convertFromSnakeCase` converts keys BEFORE lookup). Second attempt used camelCase raw values, which is the correct post-strategy form. Documented in file comments.
2. **Cross-suite parallelism race on full Networking subtarget run (Rule 2 test infra note).** Resolved with `-parallel-testing-enabled NO` for multi-suite runs. Plan's single-suite verify command is unaffected.
3. **The `read-before-edit` hook fired on every endpoint-file edit during Task 3's CodingKeys fix.** All edits succeeded anyway because session history contained the Reads. No impact on outcomes.

## Next Phase Readiness

- **Plan 04 (Interceptors) ready:** `MockURLProtocol.registerFixture` is the fixture API; `otp-request-success.json` + a 503/429 failure fixture are usable for RetryInterceptor tests. `FixtureLoader` ready.
- **Plan 05 (Cert pinning) ready:** Any fixture is usable through `registerFixture`; pinning tests will likely inject a TLS failure at the session delegate level rather than via fixtures, but the helper API is available if needed.
- **Plan 07 (Environment / AppContainer) ready:** Integration tests will compose `APIClient(baseURL:)` via Environment and exercise end-to-end against all 14 fixtures. No new infrastructure needed — everything reuses Plan 03's surface.
- **Phase 3 (AuthRepository) ready:** OTP request + verify fixtures pre-exist. Session token + role contract is fixed in the fixtures and typed in `OTPVerifyEndpoint.Response`.
- **Phase 4 (DEV-04 App Attest) ready:** `device-register-*.json` fixtures are the baseline; Phase 4 extends the request body (non-breaking Decodable addition), and the success fixture stays compatible.
- **Phase 5 (KYCUploader) ready:** All four KYC endpoints + their fixtures exist. Chunk-resume tests can build on `kyc-upload-chunk-*.json` + `kyc-upload-init-success.json` partial-chunks scenarios.
- **No blockers.**

## Self-Check: PASSED

Files verified on disk:

- `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — **FOUND**
- `validationLedger/Core/Networking/Mock/MockFixture.swift` — **FOUND**
- `validationLedgerTests/Networking/APIClientEndpointTests.swift` — **FOUND**
- `validationLedgerTests/Networking/FixtureLoader.swift` — **FOUND**
- 14 JSON fixtures under `validationLedgerTests/Networking/Fixtures/` — **FOUND (14/14)**
- Old location `validationLedger/Core/Networking/MockURLProtocol.swift` — **ABSENT (correctly)**

Commits verified in git log:

- `ff91ee8` (Task 1 feat) — **FOUND**
- `9665b18` (Task 2 feat) — **FOUND**
- `526e29b` (Task 3 feat) — **FOUND**

---
*Phase: 02-networking-contract-device-keys*
*Plan: 03*
*Completed: 2026-04-21*
