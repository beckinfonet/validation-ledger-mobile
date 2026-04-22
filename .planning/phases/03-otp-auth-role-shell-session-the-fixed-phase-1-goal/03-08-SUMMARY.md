---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 08
subsystem: identity-geo
tags: [ios, geo, corelocation, clgeocoder, tdd, wave-2, d-20, d-21, geo-01, geo-02]

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "validationLedgerTests/Identity/Geo/LocationProviderTests.swift + CountryGateTests.swift Wave 0 stubs (@Test(.disabled(\"Wave 4 Plan 08 implements\")) placeholders) — both filled in this plan"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 03
    provides: "SwiftLint allow-list `Core/Identity/Geo*/**` for ban_raw_coordinate_literal; PlatformPayloadField.swift (the sanctioned carrier for CLLocationCoordinate2D out to networking endpoints)"
provides:
  - "LocationProvider protocol + DefaultLocationProvider (CLLocationManager async wrapper) in Core/Identity/Geo/ — one-shot fix via manager.requestLocation() bridged with withCheckedThrowingContinuation; D-20 freshness (<30s) + accuracy (<100m horizontal, reject negative) guards enforced inline at didUpdateLocations delegate callback"
  - "LocationError enum with 5 cases (permissionDenied / staleFix / lowAccuracy / timedOut / underlying)"
  - "CountryGate protocol + DefaultCountryGate (CLGeocoder reverse-geocode wrapper) in Core/Identity/Geo/ — D-21 defense-in-depth refusal: empty placemarks / nil isoCountryCode / any throw → GeoError.cannotResolveCountry"
  - "PlacemarkLike seam protocol + CLPlacemarkAdapter adapter — decouples callers from CLPlacemark (whose init() is unavailable on iOS, making subclass fakes infeasible). Tests use plain StubPlacemark struct; production uses CLPlacemarkAdapter wrapping the real CLPlacemark."
  - "ReverseGeocoder seam protocol + CLReverseGeocoder production impl — wraps CLGeocoder.reverseGeocodeLocation(_:)"
  - "GeoError enum (Sendable, Equatable) — single case cannotResolveCountry per D-21 collapse"
  - "Info.plist NSLocationWhenInUseUsageDescription key with user-facing rationale mentioning 'United States' — required by iOS for CLLocationManager.requestWhenInUseAuthorization to prompt without crashing (GEO-01)"
  - "11 new green tests (5 LocationProviderTests + 6 CountryGateTests) — covers protocol surfaces, D-20 source-grep invariants, D-21 three refusal paths, Info.plist presence + copy assertions"
affects:
  - "03-09 (PhoneEntryViewModel) — injects `any LocationProvider` + `any CountryGate` to orchestrate D-20 5-step geo gate before POST /auth/otp/request"
  - "03-11 (AppContainer composition root) — registers DefaultLocationProvider + DefaultCountryGate; wires into PhoneEntryViewModel"
  - "03-12 (RoleShellSmokeTests UI harness) — will need StubLocationProviderForUITest + StubCountryGateForUITest to bypass real GPS/geocoder in UI tests; the protocol seams landed here make those stubs trivial"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Continuation bridge: withCheckedThrowingContinuation stored on the CLLocationManagerDelegate to bridge one-shot delegate callback (didUpdateLocations / didFailWithError) to async/await. Nil-and-clear pattern on both resume paths to avoid double-resume."
    - "Defense-in-depth error collapse (D-21): single `GeoError.cannotResolveCountry` absorbs empty-placemarks / nil-iso / throw-on-network / any-other-throw into one refusal path. Backend re-verifies authoritatively; client gate blocks accidental non-US attempts."
    - "PlacemarkLike protocol seam: when Apple SDK types have unavailable `init()` (e.g., CLPlacemark), a minimal-surface protocol + production adapter (wraps real Apple type) + test struct (plain value type) is the canonical Swift testability pattern. Avoids the fragile subclass-with-override pattern."
    - "Source-grep invariants via #filePath-relative URL with 4 deleteLastPathComponent hops (Geo → Identity → validationLedgerTests → repoRoot) — xcodebuild's CWD is derived-data-scoped, not repo-root, so CWD-relative reads fail. Plan 03 used 3 hops from Identity/; this plan is one level deeper, hence 4."

key-files:
  created:
    - validationLedger/Core/Identity/Geo/LocationProvider.swift
    - validationLedger/Core/Identity/Geo/CountryGate.swift
  modified:
    - validationLedger/App/Info.plist
    - validationLedgerTests/Identity/Geo/LocationProviderTests.swift
    - validationLedgerTests/Identity/Geo/CountryGateTests.swift

key-decisions:
  - "PlacemarkLike protocol seam adopted over CLPlacemark subclass for test fakes — CLPlacemark.init() is unavailable on iOS, so subclass + super.init() fails at compile time. The plan's Task 2 Step C note explicitly pre-authorized this fallback ('if Xcode rejects the override … use a protocol seam'). Production gains a 3-line CLPlacemarkAdapter + a 6-line CLReverseGeocoder.map — tests gain a 2-line StubPlacemark struct. Simpler AND more robust to future Apple SDK changes."
  - "Info.plist path correction: plan stated `validationLedger/Resources/Info.plist` but the project's INFOPLIST_FILE setting in validationLedger.xcodeproj/project.pbxproj points to `validationLedger/App/Info.plist` (verified on line 492 + line 520). `validationLedger/Resources/` contains PrivacyInfo.xcprivacy + en.lproj only. Edited the actual file the build uses. Documented as Rule 3 blocking env correction (Deviation 1 below)."
  - "Destination substitution (same as Plans 01, 02, 03, 05, 06, 07 before): iPhone 17 Pro / iOS 26.4 because plan-specified iPhone 15 / iOS 17.5 runtime is not installed. Project deployment target is iOS 17.0 — any iOS 17+ destination is equivalent for verification. Documented as Rule 3 blocking env correction (Deviation 2 below)."
  - "Test-helper 4-deleteLastPathComponent-hops fix during Task 1 GREEN — initial 3-hop resolution (per Plan 03 PlatformPayloadFieldTests.swift convention) landed at `validationLedgerTests/` not the repo root, because this file is one directory deeper (Identity/Geo/ vs Identity/). Caught by test failure with NSPOSIXErrorDomain Code=2 on first GREEN run. Rule 1 bug fix: one additional deleteLastPathComponent call. Documented as Deviation 3."
  - "D-20 guards hardcoded to 30s / 100m with named parameters `maxAge` / `maxAccuracy` having matching defaults — API evolution story preserves D-20 contract while letting future callers tune. Source-grep invariants test the hardcoded inline values to lock the contract regardless of future parameterization."
  - "GeoError = single-case enum. Kept explicit `Equatable` conformance even though Swift auto-synthesizes it for a payload-free enum — signals intent + permits pattern-matching use in tests without relying on auto-synthesis of future cases."
  - "No changes to validationLedger.xcodeproj/project.pbxproj — new files in Core/Identity/Geo/ are auto-included via the Phase 1 PBXFileSystemSynchronizedRootGroup setup (ADR 0002 derivative). Zero pbxproj churn."
  - "SwiftLint binary resolution — used the SwiftPM-managed .build/artifacts/swiftlintplugins/SwiftLintBinary.artifactbundle (0.63.2, pinned in Package.swift per Phase 1) via the shared monorepo .build directory; not a globally-installed swiftlint (not present)."

patterns-established:
  - "Apple-SDK-testability-via-protocol-seam: when an Apple type (e.g., CLPlacemark) has unavailable initializers, define a minimal-surface protocol carrying only the properties the call site needs, provide a production adapter wrapping the Apple type, and let tests supply a plain value-type struct. Pattern scales to any future CLLocation / CLGeocoder / MKPlacemark / LAContext-style seams."
  - "Defense-in-depth single-error-collapse for D-21-style gates: one enum case absorbs all failure modes. Callers see one branch to handle; product experience is consistent (cannot-verify-country → refuse) regardless of underlying cause. Paired with backend authoritative re-verification — client gate is never the sole trust point."

requirements-completed:
  - GEO-01
  - GEO-02

# Metrics
duration: ~8min
completed: 2026-04-21
---

# Phase 03 Plan 08: LocationProvider + CountryGate + Info.plist Summary

**CLLocationManager one-shot async wrapper + CLGeocoder D-21 defense-in-depth reverse-geocode refusal gate + Info.plist location-usage rationale — PhoneEntryViewModel (Plan 09) now has both protocol seams it needs to orchestrate the D-20 5-step geo gate.**

## Performance

- **Duration:** ~8 min (wall-clock; 4 git commits: 2 RED + 2 GREEN)
- **Started:** 2026-04-21 20:57 local (first commit 8bfb9ad)
- **Completed:** 2026-04-21 21:02 local (last task commit 59c02a1)
- **Tasks:** 2 / 2 (both `tdd="true"` — RED/GREEN atomic commits per task)
- **Files created:** 2 source (LocationProvider.swift, CountryGate.swift)
- **Files modified:** 3 (Info.plist + 2 Wave 0 test stubs filled)

## Accomplishments

- **LocationProvider landed** — `protocol LocationProvider : AnyObject, Sendable` + `enum LocationError` (5 cases) + `@MainActor final class DefaultLocationProvider : NSObject, LocationProvider, CLLocationManagerDelegate`. One-shot fix via `manager.requestLocation()` bridged with `withCheckedThrowingContinuation`. D-20 freshness (<30s) + accuracy (<100m horizontal, reject negative) guards enforced inline at the `didUpdateLocations` delegate callback. `kCLLocationAccuracyHundredMeters` desiredAccuracy tier — right for country check; `.Best` would cost fix-time without changing the answer.
- **CountryGate landed with D-21 defense-in-depth** — `protocol CountryGate : AnyObject, Sendable` + `final class DefaultCountryGate` + `enum GeoError` (single `cannotResolveCountry` case). All failure paths collapse to the single error: empty placemarks, nil `isoCountryCode`, any thrown error (network / timeout / CLError) → `throw GeoError.cannotResolveCountry`. Backend re-verifies authoritatively; this client gate blocks accidental non-US auth attempts.
- **`PlacemarkLike` protocol seam + `CLPlacemarkAdapter`** replace the plan's suggested `CLPlacemark`-subclass test fake (CLPlacemark has `'init()' is unavailable in iOS` — subclass pattern fails at compile). Plan Task 2 Step C note explicitly pre-authorized this fallback. Production uses `CLReverseGeocoder` → `[CLPlacemark]` → `CLPlacemarkAdapter` → `[any PlacemarkLike]`; tests inject `StubGeocoder` returning `[StubPlacemark]`.
- **`ReverseGeocoder` seam protocol** exposed for tests (`reverseGeocode(_:) async throws -> [any PlacemarkLike]`) with production implementation `CLReverseGeocoder` wrapping `CLGeocoder.reverseGeocodeLocation(_:)`.
- **Info.plist `NSLocationWhenInUseUsageDescription` added** with copy: *"Validation Ledger uses your location at sign-in to verify you're in the United States, our service area."* This copy is required by iOS for the `requestWhenInUseAuthorization()` prompt to render without crashing — and the "United States" mention is required by App Store reviewers + product spec. `plutil -lint` passes.
- **11 green tests across 2 suites** — 5 LocationProviderTests (protocol surface + LocationError 5-case exhaustion + source-grep for `manager.requestLocation()` + `withCheckedThrowingContinuation` + D-20 freshness/accuracy guards + construction smoke) + 6 CountryGateTests (US passthrough + non-US passthrough + 3 D-21 refusal paths + Info.plist key+copy assertion).
- **SwiftLint clean** — `swiftlint lint --strict validationLedger/` reports 0 violations across 63 files. The `ban_raw_coordinate_literal` rule (Plan 03 D-24) correctly allows `CLLocation(latitude:longitude:)` construction inside `Core/Identity/Geo/` and `validationLedgerTests/`; the test's SF coordinates compile cleanly.
- **Full test-target build succeeds** — `xcodebuild build-for-testing` → `** TEST BUILD SUCCEEDED **`. Zero regression on existing suites.
- **Zero pbxproj churn** — both new files in `Core/Identity/Geo/` auto-included via Phase 1 `PBXFileSystemSynchronizedRootGroup` setup.
- **Requirements GEO-01 + GEO-02 COMPLETE** per plan frontmatter `requirements: [GEO-01, GEO-02]`.

## Task Commits

TDD gate order verified in git log: each task has a RED `test(...)` commit followed by a GREEN `feat(...)` commit.

| Commit | Type | Task | Subject |
|--------|------|------|---------|
| `8bfb9ad` | test | 1 RED | add failing tests for LocationProvider (Task 1 RED) |
| `3fc398a` | feat | 1 GREEN | add LocationProvider CLLocationManager async wrapper (Task 1 GREEN) |
| `0b09e9e` | test | 2 RED | add failing tests for CountryGate + Info.plist key (Task 2 RED) |
| `59c02a1` | feat | 2 GREEN | add CountryGate + Info.plist location rationale (Task 2 GREEN) |

## Files Created (2)

### `validationLedger/Core/Identity/Geo/LocationProvider.swift` (NEW, 123 lines)

- `protocol LocationProvider : AnyObject, Sendable`
- `enum LocationError : Error, Sendable` (5 cases)
- `@MainActor final class DefaultLocationProvider : NSObject, LocationProvider, CLLocationManagerDelegate`
- Uses `manager.requestLocation()` (one-shot) + `withCheckedThrowingContinuation`
- `loc.timestamp.timeIntervalSinceNow < -30` (staleness) + `horizontalAccuracy > 100 || horizontalAccuracy < 0` (accuracy) guards at `didUpdateLocations`
- `nonisolated` delegate callbacks hop back to `@MainActor` via `Task { @MainActor [weak self] in ... }`

### `validationLedger/Core/Identity/Geo/CountryGate.swift` (NEW, 99 lines)

- `enum GeoError : Error, Sendable, Equatable` — `cannotResolveCountry`
- `protocol PlacemarkLike : Sendable` — `var isoCountryCode: String? { get }`
- `struct CLPlacemarkAdapter : PlacemarkLike, @unchecked Sendable` — production adapter over CLPlacemark
- `protocol ReverseGeocoder : Sendable` — async throws seam
- `struct CLReverseGeocoder : ReverseGeocoder` — wraps `CLGeocoder.reverseGeocodeLocation(_:)`
- `protocol CountryGate : AnyObject, Sendable`
- `final class DefaultCountryGate : CountryGate, @unchecked Sendable` with default `geocoder: any ReverseGeocoder = CLReverseGeocoder()`
- D-21 collapse: `catch is GeoError { throw GeoError.cannotResolveCountry } catch { throw GeoError.cannotResolveCountry }` + guard against empty placemarks + nil-or-empty-string isoCountryCode

## Files Modified (3)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/App/Info.plist` | Added `NSLocationWhenInUseUsageDescription` key + value with "United States" copy | +7 |
| `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` | Filled Wave 0 stub with 5 @Tests (protocol surface + error cases + 2 source-grep invariants + init smoke) | +77 / -5 |
| `validationLedgerTests/Identity/Geo/CountryGateTests.swift` | Filled Wave 0 stub with 6 @Tests (US/non-US + 3 D-21 refusals + Info.plist assertion) + `StubPlacemark` + `StubGeocoder` fakes | +126 / -6 |

### Info.plist snippet

```xml
<!-- GEO-01 / D-20 / Phase 3 Plan 08: location permission rationale.
     CLLocationManager.requestWhenInUseAuthorization crashes without this key.
     Copy mentions "United States" per product spec + App Store reviewer
     expectation; CountryGateTests.infoPlistHasUsageDescription asserts both. -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Validation Ledger uses your location at sign-in to verify you're in the United States, our service area.</string>
```

## Test Results

**LocationProviderTests — 5 passed (all new, filled from Wave 0 stub):**

```
✔ LocationProvider protocol surface — requestPermission + currentLocation signatures
✔ LocationError has all 5 cases
✔ LocationProvider source uses requestLocation (one-shot), NOT startUpdatingLocation
✔ LocationProvider source enforces D-20 freshness + accuracy guards
✔ DefaultLocationProvider initializes on simulator without throwing
```

**CountryGateTests — 6 passed (all new, filled from Wave 0 stub):**

```
✔ US placemark → returns 'US'
✔ Non-US placemark → returns the actual ISO (caller decides refusal)
✔ Empty placemarks array → throws GeoError.cannotResolveCountry (D-21)
✔ Nil isoCountryCode in placemark → throws GeoError.cannotResolveCountry (D-21)
✔ Geocoder network failure → throws GeoError.cannotResolveCountry (D-21 defense-in-depth)
✔ Info.plist contains NSLocationWhenInUseUsageDescription
```

**Total:** `** TEST SUCCEEDED **` — 11 tests in 2 suites, 0 failures. Execution: 0.012s.

**Full test-target build:** `** TEST BUILD SUCCEEDED **`. No regression on any of the existing 17+ test suites.

**SwiftLint:** `Done linting! Found 0 violations, 0 serious in 63 files.`

**plutil:** `validationLedger/App/Info.plist: OK`

## ReverseGeocoder Seam Form Chosen

**Form adopted:** protocol-seam (PlacemarkLike + CLPlacemarkAdapter), NOT the `CLPlacemark` subclass.

**Why:** `CLPlacemark.init()` is marked `unavailable` in iOS — attempting to declare `init(isoCountryCode:) { ... super.init() }` fails with `'init()' is unavailable in iOS`. This is a modern-SDK Apple behavior (CLPlacemark is to be constructed only by CLGeocoder). The plan's Task 2 Step C note anticipated this contingency and explicitly pre-authorized the protocol-seam fallback.

**What changed vs. plan:**
- **ReverseGeocoder.reverseGeocode return type:** plan had `[CLPlacemark]`; actual is `[any PlacemarkLike]`.
- **DefaultCountryGate internal guard:** `placemarks.first?.isoCountryCode` is the same call site — `PlacemarkLike` carries only that one property.
- **Production call path:** `CLGeocoder → [CLPlacemark] → map(CLPlacemarkAdapter.init) → [any PlacemarkLike]` — one extra map, negligible cost.
- **Test call path:** `StubGeocoder` returns `[any PlacemarkLike]` populated from `[StubPlacemark]` — a simple value-type struct.

**Future robustness bonus:** if Apple changes CLPlacemark (e.g., adds new required fields, changes isoCountryCode semantics), the seam absorbs the shock — only `CLPlacemarkAdapter` needs to adapt. Tests are decoupled from CLPlacemark entirely.

## Decisions Made

- **PlacemarkLike seam vs. CLPlacemark subclass** — chose the seam; see above for full rationale.
- **Info.plist path** — corrected to `validationLedger/App/Info.plist` (verified via project.pbxproj INFOPLIST_FILE setting).
- **Destination substitution** — iPhone 17 Pro / iOS 26.4 instead of plan's iPhone 15 / iOS 17.5 (same env-adaptive pattern used by Plans 01–07 before).
- **D-20 guard parameterization** — `currentLocation(maxAge:maxAccuracy:)` takes the values as parameters with defaults of 30 / 100. Source-grep invariants lock the hardcoded inline literals (`< -30`, `> 100`, `< 0`) regardless of future parameterization.
- **GeoError.Equatable conformance** — explicit rather than auto-synthesized; signals intent and permits pattern-match use in tests.
- **Delegate callback MainActor hop** — `nonisolated` callbacks always hop to `@MainActor` via `Task { @MainActor [weak self] in ... }`. Avoids potential data races + matches the D-31 plan guidance that UI-affecting state must land on main.
- **`@unchecked Sendable`** on `DefaultCountryGate` + `CLPlacemarkAdapter` — both have immutable state (struct adapter wraps a `let`, class gate holds an `any ReverseGeocoder`). `@unchecked` is the correct annotation; `Sendable` auto-derivation doesn't reach through `any ReverseGeocoder`.
- **Zero pbxproj changes** — preserved by the Phase 1 PBXFileSystemSynchronizedRootGroup setup.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking Env Correction] Info.plist path: plan said `validationLedger/Resources/Info.plist`, actual is `validationLedger/App/Info.plist`**
- **Found during:** Task 2 pre-edit — running `find . -name Info.plist` confirmed the Info.plist lives at `validationLedger/App/Info.plist`; `validationLedger/Resources/` contains only `PrivacyInfo.xcprivacy` + `en.lproj/`.
- **Verified:** `validationLedger.xcodeproj/project.pbxproj` lines 492 + 520 have `INFOPLIST_FILE = validationLedger/App/Info.plist;`.
- **Fix:** Edited the actual build-used Info.plist. Test assertion + Edit tool invocation reference the `App/` path.
- **Files modified:** `validationLedger/App/Info.plist` (not `Resources/Info.plist`).
- **Verification:** `plutil -lint validationLedger/App/Info.plist` → `OK`. Test `infoPlistHasUsageDescription` reads from the same path and asserts both key and "United States" copy.
- **Committed in:** `59c02a1` (Task 2 GREEN).

**2. [Rule 3 — Blocking Env Correction] Simulator destination: iPhone 15 / iOS 17.5 not installed**
- **Found during:** Task 1 RED `xcodebuild build-for-testing` invocation.
- **Issue:** `xcrun simctl list devices available` shows iPhone 17 Pro simulators on iOS 26.4 (same runtime Plans 01–07 used). Plan-specified iPhone 15 / iOS 17.5 runtime is not installed in this environment.
- **Fix:** All `xcodebuild test` / `build-for-testing` runs used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`. Project deployment target is iOS 17.0 — any iOS 17+ destination is equivalent for verification.
- **Files modified:** None (CLI invocation only).
- **Verification:** `** TEST SUCCEEDED **` / `** TEST BUILD SUCCEEDED **` on all runs.
- **Committed in:** N/A — no source change.

**3. [Rule 1 — Test Helper Bug] Source-grep URL resolved to `validationLedgerTests/validationLedger/...` instead of repo root**
- **Found during:** Task 1 GREEN first test run — 2 of 5 tests failed with `NSPOSIXErrorDomain Code=2 "No such file or directory"` on `LocationProvider.swift` path.
- **Issue:** Initial test-helper `locationProviderSource()` used 3 `deleteLastPathComponent()` hops (per Plan 03 PlatformPayloadFieldTests.swift convention). But PlatformPayloadFieldTests is at `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — one directory shallower than this plan's `validationLedgerTests/Identity/Geo/LocationProviderTests.swift`. Needed 4 hops to reach repo root.
- **Fix:** Added one more `deleteLastPathComponent()` call to both `locationProviderSource` + `infoPlistSource` helpers. Same fix-pattern to be applied to future test files at `validationLedgerTests/<subsystem>/<sub-subsystem>/` depth.
- **Files modified:** `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` (helper only).
- **Verification:** All 5 LocationProviderTests pass; all 6 CountryGateTests pass (shares the same 4-hop helper pattern).
- **Committed in:** `3fc398a` (rolled into Task 1 GREEN commit since the helper was landing as part of the initial file anyway).

**4. [Rule 1 — Plan Contingency Activation] CLPlacemark subclass in Task 2 RED test file failed to compile (`'init()' is unavailable in iOS`)**
- **Found during:** Task 2 RED `xcodebuild build-for-testing` error output.
- **Issue:** Test file defined `private final class TestPlacemark : CLPlacemark` with `init(isoCountryCode: String?) { ... super.init() }`. Compile error: `'init()' is unavailable in iOS` — CLPlacemark in modern iOS SDK forbids subclass + super-init.
- **Fix:** Switched to the plan's Task 2 Step C pre-authorized fallback: `PlacemarkLike` protocol + `CLPlacemarkAdapter` production adapter + `StubPlacemark` test struct. Modified `CountryGate.swift` to take `[any PlacemarkLike]` from `ReverseGeocoder.reverseGeocode`; test file's `StubGeocoder` + `StubPlacemark` updated accordingly.
- **Files modified:** `validationLedger/Core/Identity/Geo/CountryGate.swift` (landed with seam baked in from first write), `validationLedgerTests/Identity/Geo/CountryGateTests.swift` (TestPlacemark → StubPlacemark + StubGeocoder return type).
- **Verification:** All 6 CountryGateTests pass.
- **Committed in:** `59c02a1` (Task 2 GREEN).

---

**Total deviations:** 4 auto-fixed (2 Rule 3 blocking env corrections, 2 Rule 1 bugs — 1 in test helper, 1 in plan-anticipated SDK contingency).
**Impact on plan:** No scope change. All plan `success_criteria` checkboxes + `must_haves.truths` + `must_haves.artifacts` `contains` patterns satisfied as written, with `ReverseGeocoder.reverseGeocode` return type documented as `[any PlacemarkLike]` rather than `[CLPlacemark]` (plan explicitly pre-authorized this in Task 2 Step C note).

## TDD Gate Compliance

Plan frontmatter has `autonomous: true` but both tasks declare `tdd="true"`. Gate sequence verified in `git log --oneline`:

| Task | RED commit | GREEN commit | RED-evidence | GREEN-evidence |
|------|-----------|--------------|--------------|----------------|
| 1 (LocationProvider) | `8bfb9ad` (test) | `3fc398a` (feat) | `** TEST BUILD FAILED **` — 5+ "cannot find 'LocationProvider' / 'DefaultLocationProvider' / 'LocationError'" errors | 5 tests pass + full build succeeds + 0 lint violations |
| 2 (CountryGate + Info.plist) | `0b09e9e` (test) | `59c02a1` (feat) | `** TEST BUILD FAILED **` — "cannot find 'ReverseGeocoder' / 'DefaultCountryGate' / 'GeoError'" + "'init()' is unavailable in iOS" on the TestPlacemark subclass (caught the SDK contingency at compile) | 6 tests pass + plutil -lint OK + 0 lint violations |

`git log --oneline` shows chronological order: `test(03-08) RED` → `feat(03-08) GREEN` for both tasks. No TDD gate violations.

## Known Stubs

**None introduced by this plan.**

Plan 01's Wave 0 stubs `LocationProviderTests.swift` + `CountryGateTests.swift` are now filled with 5 + 6 real `@Test`s respectively — removed from the pending-stub ledger (2 of 13 Wave 0 stubs now closed; 11 remain per Plan 01 summary Stub-to-Plan Mapping).

The protocol seams (`LocationProvider`, `CountryGate`, `ReverseGeocoder`, `PlacemarkLike`) are intentional seams — NOT stubs. `DefaultLocationProvider` and `DefaultCountryGate` are the production implementations that ship in Phase 3.

## Threat Flags

Per plan `<threat_model>`, 5 Phase 3-08 threats enumerated; dispositions + landed evidence:

| Threat ID | Category | Disposition | Mitigation landed? | Evidence |
|-----------|----------|-------------|---------------------|----------|
| T-03-08-01 | Client-side geocode bypass attempts | accept | N/A (backend re-verifies) | — |
| T-03-08-02 | Coordinates leaked to logs via LocationProvider success path | mitigate | YES (cross-plan) | `LocationProvider.currentLocation` returns `CLLocation` — cannot flow into `Logger.log([LogField])` because LogField has no coordinate case (Plan 03 D-23). Phantom-typed `PlatformPayloadField` is the sole sanctioned carrier. |
| T-03-08-03 | Non-US user bypass by killing network mid-geocode | mitigate | YES | `DefaultCountryGate.resolveCountry` catches ALL errors + empty arrays + nil iso → `GeoError.cannotResolveCountry`. Tests `networkFailureRefuses` + `nilIsoRefuses` + `emptyPlacemarksRefuses` lock the three paths. |
| T-03-08-04 | Missing Info.plist NSLocationWhenInUseUsageDescription → crash | mitigate | YES | `infoPlistHasUsageDescription` test asserts the key + copy. `plutil -lint` asserts XML validity. |
| T-03-08-05 | CLGeocoder rate-limit DoS | accept | N/A (one-shot at sign-in is well within budget) | — |

**No new threat surface introduced** beyond what was enumerated in the plan's `<threat_model>`. `PlacemarkLike` + `ReverseGeocoder` seams are testability seams — no new network endpoints, no new file access, no new schema.

## Issues Encountered

- **CLPlacemark `init()` unavailability** caught the plan's contingency branch (Task 2 Step C note). The switch to a protocol seam was clean; the production implementation gained a 3-line adapter. Worth noting for future Apple-SDK-based services: any Apple type with an `init()` marked `unavailable` forbids subclassing + super-init. Default to a protocol seam from the start.
- **Test-helper path-hop count varies with test file depth.** Plan 03 used 3 hops (tests at `validationLedgerTests/Identity/`); this plan uses 4 hops (tests at `validationLedgerTests/Identity/Geo/`). Future test files at deeper paths will need more hops. Consider centralizing a helper in a test-target-wide extension — deferred, not in scope for this plan.

## User Setup Required

**None.** No external services, no secrets, no dashboard changes. All work is source + Info.plist + test + tooling-config edits, all verifiable via `xcodebuild test` + `plutil -lint` + `swiftlint lint --strict`.

**At runtime on a real device + first `requestWhenInUseAuthorization()` call** (lands via Plan 09 + Plan 10), the user will see the iOS system permission prompt with the "Validation Ledger uses your location at sign-in to verify you're in the United States, our service area." rationale. No action needed now — this is observed in Plan 09/10 HUMAN-UAT.

## Next Phase Readiness

- **Plan 09 (PhoneEntryViewModel + OTPViewModel) proceeds.** Can now inject `any LocationProvider` + `any CountryGate` (both protocol seams land here) to orchestrate the D-20 5-step geo gate: `requestPermission()` → `currentLocation(maxAge: 30, maxAccuracy: 100)` → `resolveCountry(for:)` → (if != "US" → NotAvailableInRegionViewController) → (else → POST /auth/otp/request with `PlatformPayloadField.coordinate(location.coordinate)` attached to the payload body). The coordinate can NOT flow into logs (Plan 03 D-23 compile-time barrier) or into raw-literal paths (Plan 03 D-24 SwiftLint rule), so the privacy posture is intact end-to-end.
- **Plan 11 (AppContainer composition root) proceeds.** Can now register `DefaultLocationProvider()` + `DefaultCountryGate(geocoder: CLReverseGeocoder())` as two new container properties; wires into PhoneEntryViewModel.
- **Plan 12 (RoleShellSmokeTests UI harness) has easier seams.** The plan anticipated needing `StubLocationProviderForUITest` + `StubCountryGateForUITest`; the protocol-seam shape landed here makes those stubs trivial — StubLocationProviderForUITest returns a hard-coded `CLLocation` of a known US coordinate, StubCountryGateForUITest returns `"US"` without geocoding.
- **HUMAN-UAT items for Plan 09/10.** First real-device run: verify the permission prompt displays the "United States" rationale correctly; verify denial path reaches the NotAvailableInRegionViewController; verify a non-US VPN or geofake hits the GeoError.cannotResolveCountry refusal path. None of these are this plan's scope.
- **Downstream verifier should check:** all 5 `<verify>` block automated assertions (`test -f CountryGate.swift`, `grep -q "func resolveCountry(for location: CLLocation)"`, `grep -q "reverseGeocodeLocation"`, `grep -q "isoCountryCode"`, `grep -q "case cannotResolveCountry"`, `grep -q "NSLocationWhenInUseUsageDescription" Info.plist`, `plutil -lint` OK, `swiftlint lint --strict` 0 violations, `xcodebuild test` green). All confirmed locally.

## Self-Check

Files claimed created:

- `validationLedger/Core/Identity/Geo/LocationProvider.swift` — FOUND (123 lines; `withCheckedThrowingContinuation` + `manager.requestLocation()` + D-20 guards all present)
- `validationLedger/Core/Identity/Geo/CountryGate.swift` — FOUND (99 lines; `protocol CountryGate` + `enum GeoError` + `class DefaultCountryGate` + `protocol ReverseGeocoder` + `struct CLReverseGeocoder` + `protocol PlacemarkLike` + `struct CLPlacemarkAdapter`)

Files claimed modified:

- `validationLedger/App/Info.plist` — FOUND (1 match for `NSLocationWhenInUseUsageDescription`, 1 match for `United States`; `plutil -lint` OK)
- `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` — FOUND (5 `@Test` declarations + `locationProviderSource` helper)
- `validationLedgerTests/Identity/Geo/CountryGateTests.swift` — FOUND (6 `@Test` declarations + `StubGeocoder` + `StubPlacemark` fakes + `infoPlistSource` helper)

Commits claimed made:

- `8bfb9ad` (Task 1 RED) — FOUND in `git log`
- `3fc398a` (Task 1 GREEN) — FOUND in `git log`
- `0b09e9e` (Task 2 RED) — FOUND in `git log`
- `59c02a1` (Task 2 GREEN) — FOUND in `git log`

Plan `<verification>` block — all 7 criteria:

| # | Check | Result |
|---|-------|--------|
| 1 | `Core/Identity/Geo/LocationProvider.swift` exists with one-shot async wrapper + guards | PASS |
| 2 | `Core/Identity/Geo/CountryGate.swift` exists with D-21 defense-in-depth | PASS |
| 3 | Info.plist contains NSLocationWhenInUseUsageDescription + "United States" | PASS (`validationLedger/App/Info.plist` — plan path corrected) |
| 4 | `plutil -lint Info.plist` exits 0 | PASS |
| 5 | `swiftlint lint --strict validationLedger/` 0 violations | PASS (0 violations in 63 files) |
| 6 | LocationProviderTests (5) pass | PASS |
| 7 | CountryGateTests (6) pass | PASS |

Plan `<success_criteria>` block — all 6 criteria:

- [x] LocationProvider protocol + impl with one-shot requestLocation bridge + freshness + accuracy guards
- [x] CountryGate protocol + impl with D-21 defense-in-depth refusal (any failure → cannotResolveCountry)
- [x] ReverseGeocoder seam allows test injection (via `[any PlacemarkLike]` — plan's Task 2 Step C pre-authorized fallback)
- [x] Info.plist NSLocationWhenInUseUsageDescription key present + mentions "United States"
- [x] 11 new tests green (5 + 6)
- [x] SwiftLint passes (Plan 03 allow-list active)

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
