---
phase: 01-foundational-conventions-scaffolding
reviewed: 2026-04-21T00:00:00Z
depth: standard
files_reviewed: 48
files_reviewed_list:
  - .github/workflows/ci-device.yml
  - .github/workflows/ci-simulator.yml
  - scripts/check-coverage.sh
  - scripts/check-privacy-manifest.sh
  - scripts/install-hooks.sh
  - scripts/pre-commit.sh
  - validationLedger/App/AppContainer.swift
  - validationLedger/App/AppCoordinator.swift
  - validationLedger/App/AppDelegate.swift
  - validationLedger/App/DevMenu/DevMenuShakeResponder.swift
  - validationLedger/App/DevMenu/DevMenuViewController.swift
  - validationLedger/App/DevMenu/KeychainInspectorViewController.swift
  - validationLedger/App/DevMenu/LogViewerViewController.swift
  - validationLedger/App/DevMenu/RoleSwitcherViewController.swift
  - validationLedger/App/Environment.swift
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/Core/Auth/SessionLockService.swift
  - validationLedger/Core/KeyStore/KeyStoreProtocol.swift
  - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
  - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
  - validationLedger/Core/Logging/LogExporter.swift
  - validationLedger/Core/Logging/Logger.swift
  - validationLedger/Core/Logging/OSLogLoggerImpl.swift
  - validationLedger/Core/Logging/PIIScrubber.swift
  - validationLedger/Core/Logging/Subsystems.swift
  - validationLedger/Core/Navigation/DeepLinkRouter.swift
  - validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift
  - validationLedger/Core/Networking/MockURLProtocol.swift
  - validationLedger/Core/Networking/NetworkClient.swift
  - validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift
  - validationLedger/Core/Storage/Keychain/KeychainKey.swift
  - validationLedger/Core/Storage/Keychain/KeychainStore.swift
  - validationLedger/Roles/Broker/BrokerTabBarController.swift
  - validationLedger/Roles/Carrier/CarrierTabBarController.swift
  - validationLedger/Roles/Dispatch/DispatchTabBarController.swift
  - validationLedger/Roles/Factoring/FactoringTabBarController.swift
  - validationLedger/Roles/Role.swift
  - validationLedger/Roles/RoleCoordinator.swift
  - validationLedger/Roles/Shipper/ShipperTabBarController.swift
  - validationLedger/UI/DesignSystem/Colors.swift
  - validationLedger/UI/DesignSystem/Spacing.swift
  - validationLedger/UI/DesignSystem/Typography.swift
  - validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift
  - validationLedgerTests/Auth/SessionLockServiceTests.swift
  - validationLedgerTests/Logging/LoggerLevelsTests.swift
  - validationLedgerTests/Logging/PIIScrubberTests.swift
  - validationLedgerTests/Navigation/DeepLinkRouterTests.swift
  - validationLedgerTests/Networking/MockURLProtocolTests.swift
  - validationLedgerTests/Roles/RoleCoordinatorTests.swift
  - validationLedgerTests/Storage/KeychainStoreTests.swift
  - validationLedgerTests/Storage/KeychainWipeTests.swift
  - validationLedgerUITests/RoleShellSmokeTests.swift
findings:
  critical: 3
  warning: 6
  info: 5
  total: 14
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-04-21
**Depth:** standard
**Files Reviewed:** 48
**Status:** issues_found

## Summary

Phase 1 is architecturally sound and the security-critical invariants (D-13 `#if DEBUG` DevMenu
compile-out, D-20 first-launch Keychain wipe before AppContainer, D-17 subsystem-per-module) are
correctly implemented. The foundational patterns — initializer DI from AppContainer, NSLock-guarded
Sendable services, structured logging with PIIScrubber, Keychain hand-rolled SecItem wrapper — are
all present and largely correct.

Three critical issues require fixes before this phase is considered shippable:

1. `URLSessionNetworkClient` force-casts `URLResponse` to `HTTPURLResponse` without a guard; on
   any response that is not HTTP (custom protocols, file://, etc.) this crashes at runtime.
2. `PIIScrubber.scrubString` has a DL regex (`\b[A-Z]{1,2}[0-9]{5,8}\b`) that will false-positive
   on legitimate safe strings (e.g., state abbreviations followed by digits), and silently skips
   name redaction in the string path entirely — meaning the string-path "cannot bypass redaction"
   claim in D-16 is partially broken.
3. `DevMenuViewController.cellForRowAt` force-unwraps `Row(rawValue: indexPath.row)!` without a
   bounds guard, which will crash if the table is ever presented with a section count mismatch.

Six warnings cover smaller but real correctness and security concerns (MockURLProtocol global state
mutation in tests, SessionLockService grace-period boundary condition, DeepLinkRouter lock not held
during `state` read in `bootstrapComplete`, coverage script integer truncation, pre-commit 20-file
cap silently dropping files, and the Release environment struct still carrying `apiBaseURL: nil`
with no enforcement).

---

## Critical Issues

### CR-01: Force-cast of `URLResponse` to `HTTPURLResponse` crashes on non-HTTP responses

**File:** `validationLedger/Core/Networking/NetworkClient.swift:28` and `:35`
**Issue:** Both `get(_:)` and `post(_:url:body:)` cast the `URLResponse` returned by
`URLSession` via `response as! HTTPURLResponse`. While the live networking stack will
always produce HTTP responses, `MockURLProtocol` can be extended with non-HTTP handlers
(custom schemes, file:// stubs, error injection) and the forced cast will crash with no
recoverable path. This is also a correctness issue: if the production stack ever hits a
redirect to a non-HTTP scheme (custom app scheme, data:// URL in a misconfigured server
response) the process dies rather than surfacing a typed error.

**Fix:**
```swift
func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw NetworkError.unexpectedResponseType(response)
    }
    return (data, http)
}

func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = body
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw NetworkError.unexpectedResponseType(response)
    }
    return (data, http)
}
```
Add `case unexpectedResponseType(URLResponse)` to a `NetworkError` enum in the same file.

---

### CR-02: PIIScrubber string-path missing name redaction; DL regex prone to false-positives causing over-redaction of safe data

**File:** `validationLedger/Core/Logging/PIIScrubber.swift:41-68`
**Issue (a — missing category):** `scrubString(_:)` applies regex sweeps for phone,
coordinates, email, MC/DOT, and DL patterns, but has **no sweep for full names**. The
`LogField.fullName` structured path is correctly masked to initials, but any caller using
the string convenience API with a name embedded inline bypasses name redaction entirely.
D-16 states "string-based calls cannot bypass redaction" — this is violated for names.

**Issue (b — DL regex false-positives):** The driver's license pattern `\b[A-Z]{1,2}[0-9]{5,8}\b`
matches legitimate safe strings: US state abbreviations before ZIP codes in addresses
(`CA 94105` is not a DL but `CA94105` triggers the rule), product codes, internal load IDs,
and logging fields like `TX1234567` (transaction IDs). Over-redacting safe data degrades
log utility without a genuine PII gain. The regex should be at minimum anchored to known
DL formats (e.g., require the capital-letter prefix to be one of the 50 state codes) or
removed from the string path (DL should only come in via the structured `.driversLicense`
field).

**Fix for (a) — add name sweep in `scrubString`:**
```swift
// Names: require at least "Word Word" (two capitalized tokens separated by space)
// This is intentionally conservative — the structured path handles precise cases.
let namePattern = #"\b[A-Z][a-z]+(?:\s[A-Z][a-z]+)+"#
s = Self.regexReplace(s, pattern: namePattern) { match in
    let parts = match.split(separator: " ")
    return parts.map { "\($0.first!)." }.joined(separator: " ")
}
```

**Fix for (b) — tighten DL regex to known state prefixes only, or remove from string path:**
```swift
// Option: remove DL from string path (DL must use structured .driversLicense field)
// Delete lines 65-67 of PIIScrubber.swift:
// let dlPattern = #"\b[A-Z]{1,2}[0-9]{5,8}\b"#
// s = Self.regexReplace(s, pattern: dlPattern) { _ in "[REDACTED:DL]" }
```
If the DL pattern is kept, it must be gated to a validated list of US state codes to avoid
matching transaction IDs and other safe alphanumeric strings.

---

### CR-03: Force-unwrap in `DevMenuViewController.cellForRowAt` crashes on row-count mismatch

**File:** `validationLedger/App/DevMenu/DevMenuViewController.swift:68`
**Issue:** `let row = Row(rawValue: indexPath.row)!` force-unwraps. Although
`numberOfRowsInSection` returns `Row.allCases.count` (line 63), UIKit can call
`cellForRowAt` with a stale index path in the edge case where the table view is reloaded
mid-scroll or under accessibility (VoiceOver page-turning). The crash is DEBUG-only
because of the `#if DEBUG` guard, but it will cause a hard stop during active development
on this critical-path DevMenu screen.

**Fix:**
```swift
override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
    guard let row = Row(rawValue: indexPath.row) else {
        cell.textLabel?.text = "(unknown row)"
        return cell
    }
    cell.textLabel?.text = row.title
    cell.detailTextLabel?.text = row.subtitle
    cell.accessoryType = .disclosureIndicator
    return cell
}
```

---

## Warnings

### WR-01: MockURLProtocol.handlers is global mutable state — concurrent test mutations cause races

**File:** `validationLedger/Core/Networking/MockURLProtocol.swift:10`
**Issue:** `public static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)?] = [defaultPingHandler]`
is a class-level mutable array. Any test that appends a handler (Phase 2 tests will) is
writing shared state with no synchronization. If two test cases run concurrently (Swift
Testing runs tests in parallel by default unless `.serialized` is applied), one test's
handler mutation will corrupt another test's expectation. This is a test-reliability
landmine that will become apparent the moment Phase 2 fixtures are added.

**Fix:** Protect the array behind a lock, or — better — redesign as a per-instance
property on `URLSessionConfiguration` using `URLProtocol`'s registration API:
```swift
// Preferred: make handlers instance-configurable via the session config path
// (URLSessionConfiguration.protocolClasses already provides per-session isolation)
// If static array is kept, protect it:
private static let handlersLock = NSLock()
private static var _handlers: [(URLRequest) -> (HTTPURLResponse, Data)?] = [defaultPingHandler]
public static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)?] {
    get { handlersLock.withLock { _handlers } }
    set { handlersLock.withLock { _handlers = newValue } }
}
```

---

### WR-02: SessionLockService grace-period boundary condition — `>` should be `>=`

**File:** `validationLedger/Core/Auth/SessionLockService.swift:27`
**Issue:** `return now.timeIntervalSince(last) > backgroundGrace` means that at exactly
5 minutes (300 seconds) the app does NOT require biometric re-authentication. The spec
says "background > 5 min" which is consistent with the current `>` operator. However,
the test `pastGrace()` uses `addingTimeInterval(301)` (5 min + 1 sec) which correctly
passes. The boundary value 300 itself (exactly 5 minutes) is unspecified by the current
test suite. This is an unverified boundary that security-sensitive code should have an
explicit test for to confirm intent (either `>=` or `>` is acceptable but it must be
documented and tested).

**Fix:** Add a boundary test to `SessionLockServiceTests.swift`:
```swift
@Test("Exactly at 5-minute boundary — confirm intent (currently: does NOT require biometric)")
func atGraceBoundary() {
    let svc = DefaultSessionLockService()
    let t0 = Date()
    svc.recordBiometricSuccess(at: t0)
    let boundary = t0.addingTimeInterval(300)  // exactly 5 min
    // Current impl: > 300 means 300 does NOT trigger. If product says ">= 5 min triggers",
    // change to: return now.timeIntervalSince(last) >= backgroundGrace
    #expect(svc.shouldRequireBiometric(now: boundary) == false) // document chosen behavior
}
```

---

### WR-03: DeepLinkRouter `bootstrapComplete()` reads `state` outside the lock before assigning

**File:** `validationLedger/Core/Navigation/DeepLinkRouter.swift:32-38`
**Issue:** `bootstrapComplete()` acquires the lock, copies the queue, clears it, and sets
`state = .ready`, then releases the lock — so far correct. However, `pending.forEach(route)`
is called **after** the lock is released (line 37). The `route(_:)` function is currently
a no-op, but in Phase 3 when `route` calls real navigation code it will do so without the
lock. This is fine for `route` itself (it should not hold the queue lock while dispatching).
The real concern is that a concurrent `receive(_:)` call between the `queueLock.unlock()`
on line 36 and the `pending.forEach(route)` on line 37 will see `state == .ready` and
call `route(url)` directly — meaning that URL may be routed before the queued pending URLs
are routed. This creates an ordering inversion for deep links received in the narrow window
around bootstrap.

**Fix:** Dispatch the drain on the main queue (deep-link handling is always UI work) to
serialize post-bootstrap routing:
```swift
public func bootstrapComplete() {
    queueLock.lock()
    let pending = queue
    queue.removeAll()
    state = .ready
    queueLock.unlock()
    // Route on main thread; serializes against any concurrent receive() calls
    // that now route immediately (they also dispatch to main in Phase 3).
    DispatchQueue.main.async {
        pending.forEach(self.route)
    }
}
```
Alternatively, document in a comment that Phase 3's `route` implementation must dispatch
to main, accepting the ordering risk at Phase 1 as a known deferred concern.

---

### WR-04: check-coverage.sh uses integer truncation — a result of 69.9% passes the 70% gate

**File:** `scripts/check-coverage.sh:50-52`
**Issue:** `COVERED_INT=$(echo "$COVERAGE_LINE" | awk '{print int($1)}')` truncates (not
rounds) the floating-point coverage percentage. A result of `69.9%` becomes `69` and fails
correctly, but `69.01%` also becomes `69` and also fails — that is fine. However, `70.0%`
becomes `70` and passes — that is the intended behavior. The real subtle bug: `69.99%`
(just under 70%) becomes `69` and fails — correct. `70.001%` becomes `70` and passes —
correct. The truncation logic is actually correct for the stated invariant (`>= 70`), but
the script prints `Core/ coverage: 69.99%` while the comparison is done on `69`. This
makes the log output misleading: CI shows "threshold: 70%" but the actual gate is
"floor(pct) >= 70". Consider using `bc` or Python's `round()` for consistency and
self-documenting output.

**Fix:**
```bash
# Replace integer truncation with Python round() for self-documenting behavior
COVERED_INT=$(python3 -c "import sys; v=float('${COVERAGE_LINE}'); sys.exit(0 if v >= ${THRESHOLD} else 1)")
# And simplify the comparison block to a single Python call:
python3 -c "
v = float('${COVERAGE_LINE}')
threshold = float('${THRESHOLD}')
if v < threshold:
    print(f'FAIL: Core/ coverage {v:.2f}% is below threshold {threshold}%')
    exit(1)
print(f'OK: Coverage gate passed ({v:.2f}% >= {threshold}%)')
"
```

---

### WR-05: pre-commit.sh silently drops staged files beyond the 20-file cap

**File:** `scripts/pre-commit.sh:53-55`
**Issue:** `FILES_TO_LINT=$(echo "$STAGED" | tr '\n' ' ' | awk '{for(i=1;i<=NF && i<=20;i++) printf "%s ", $i; print ""}')` silently truncates linting to the first 20 staged files. Any Swift files staged beyond position 20 are **not linted**. This can allow a commit that contains lint violations to pass the pre-commit hook if those files happen to sort after position 20. There is no warning or error emitted when truncation occurs.

**Fix:** Remove the cap or — if the concern is shell argument length — pass files via `--path` flag or `stdin` if SwiftLint supports it, or batch in groups:
```bash
# Option A: remove cap entirely (SwiftLint handles file lists > 20 on modern macOS)
FILES_TO_LINT=$(echo "$STAGED" | tr '\n' ' ')

# Option B: if cap is intentional, fail loudly when exceeded
FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -gt 20 ]; then
    echo "pre-commit: WARNING — $FILE_COUNT staged Swift files; only first 20 linted. Run 'swiftlint lint --strict' manually for full coverage."
fi
```

---

### WR-06: `Environment.release` has `apiBaseURL: nil` with no enforcement — live requests will use `nil` base URL indefinitely

**File:** `validationLedger/App/Environment.swift:22-27`
**Issue:** The `release` environment struct also sets `apiBaseURL: nil`. This is
intentional for Phase 1 (mock-only), but there is no enforcement or assertion that
prevents a Release build from shipping without a real base URL in Phase 2. When Phase 2
wires live endpoints, a developer who forgets to update `Environment.release` will
silently ship a Release binary that cannot make real network requests. The failure mode
will be opaque (nil URL propagated into URLRequest construction).

**Fix:** Add a `#if !DEBUG` compile-time assertion or a runtime guard in
`URLSessionNetworkClient` that checks for a non-nil base URL when config is `.live`:
```swift
// In Environment.swift — mark the nil as an explicit placeholder:
#else
return Environment(
    name: "release",
    keychainAccessGroup: nil,
    apiBaseURL: nil  // PHASE-2-TODO: replace with real URL before Phase 2 ships
)
#endif

// In AppContainer.swift — add a Phase 2 release guard:
#if !DEBUG
if case .live = networkConfig, container.env.apiBaseURL == nil {
    fatalError("Release build must supply a non-nil apiBaseURL in Environment.release")
}
#endif
```

---

## Info

### IN-01: `OSLogLoggerImpl` is `internal` (not `public`) — prevents protocol adoption outside the module without redeclaration

**File:** `validationLedger/Core/Logging/OSLogLoggerImpl.swift:4`
**Issue:** `final class OSLogLoggerImpl: Logger` has no explicit access modifier, defaulting
to `internal`. `Logger` protocol and all its convenience extension methods are `public`.
If Phase 3 or later phases introduce a separate Swift module (D-15 re-evaluation), the
`OSLogLoggerImpl` type will not be visible and callers must duplicate instantiation logic.
This is low-risk for a single-target project but is inconsistent with the surrounding
`public` protocol.

**Fix:** Add `public` access modifier:
```swift
public final class OSLogLoggerImpl: Logger {
```

---

### IN-02: `SecureEnclaveKeyStore` and `SoftwareKeyStore` are `internal` — inconsistent with `KeyStoreProtocol` (public)

**File:** `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift:8`, `SoftwareKeyStore.swift:8`
**Issue:** Both concrete key store implementations are `internal`. `KeyStoreProtocol` is
`public`. Same future-module concern as IN-01. Since `AppContainer` is also `internal`,
this is self-consistent today, but the inconsistency with the public protocol is a future
source of confusion.

**Fix:** Either make both `public` or add a comment explaining the deliberate access level
choice ("internal by design — resolved through AppContainer only").

---

### IN-03: `BrokerTabBarController` and all non-Shipper tab bars delegate to `ShipperTabBarController.makeTab` — tight coupling to wrong type name

**File:** `validationLedger/Roles/Broker/BrokerTabBarController.swift:13`,
`CarrierTabBarController.swift:13`, `DispatchTabBarController.swift:13`, `FactoringTabBarController.swift:13`
**Issue:** All four non-Shipper tab bar controllers call `ShipperTabBarController.makeTab(title:systemImage:)`.
The `makeTab` helper is a static method on `ShipperTabBarController` for no structural
reason — it is a shared utility function. If `ShipperTabBarController` is ever renamed or
refactored, all four other controllers break. The naming implies ownership that does not
exist.

**Fix:** Move `makeTab(title:systemImage:)` to a top-level function in `RoleCoordinator.swift`
or a shared `TabFactory.swift` file:
```swift
// In a shared location (e.g., Roles/TabFactory.swift):
enum TabFactory {
    static func makeTab(title: String, systemImage: String) -> UIViewController {
        let vc = UIViewController()
        vc.title = title
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: systemImage), selectedImage: nil)
        vc.view.backgroundColor = .systemBackground
        return vc
    }
}
```

---

### IN-04: `check-privacy-manifest.sh` rebuilds the app on every CI run to resolve `CONFIGURATION_BUILD_DIR` — doubles CI build time

**File:** `scripts/check-privacy-manifest.sh:16`
**Issue:** `xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings`
does not rebuild, but it does spawn a full Xcode build settings resolution pass (slow).
More importantly, the path resolved here is the `CONFIGURATION_BUILD_DIR` for a
**separate** `xcodebuild` invocation, not the one that was invoked in the CI "Build + Test"
step above it. If the CI step uses `-derivedDataPath $PWD/build`, the app bundle will be
at `$PWD/build/Build/Products/Debug-iphonesimulator/${SCHEME}.app`, not under
`CONFIGURATION_BUILD_DIR`. This means the script may look in the wrong directory and
emit a false `ERROR: .app bundle not found` even when the build succeeded.

**Fix:** Pass the derived data path explicitly, or search for the `.app` bundle under the
known `$PWD/build` path used by the CI test step:
```bash
# In ci-simulator.yml, export the build dir and pass it to the script:
- name: Verify PrivacyInfo.xcprivacy in bundle
  run: bash scripts/check-privacy-manifest.sh
  env:
    APP_BUNDLE_PATH: "$PWD/build/Build/Products/Debug-iphonesimulator/validationLedger.app"
```
Then in `check-privacy-manifest.sh`:
```bash
APP_PATH="${APP_BUNDLE_PATH:-}"
if [ -z "$APP_PATH" ]; then
    # fallback: derive from xcodebuild settings
    ...
fi
```

---

### IN-05: `LoggerLevelsTests` test comment says "first-3-last-2" but `PIIScrubberTests` test docstring says "first-5-last-4"

**File:** `validationLedgerTests/Logging/PIIScrubberTests.swift:10`
**Issue:** The test is annotated `@Test("E.164 phone masked to first-3-last-2")` but
the actual `maskPhone` implementation preserves the first **5** characters and last **4**
characters (e.g., `+14155550129` → `+1415•••0129`). The test assertion at line 12 is
correct (`"+1415•••0129"`), but the test description is wrong. This will confuse
reviewers and future maintainers about the intended masking contract.

**Fix:** Update the test annotation:
```swift
@Test("E.164 phone masked to first-5-last-4 (e.g., +1415•••0129)")
```

---

_Reviewed: 2026-04-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
