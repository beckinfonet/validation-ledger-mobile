---
phase: 07-load-domain-model-mock-contract
plan: 04
subsystem: Core/Networking/Mock
tags: [load-domain, mock-contract, mockurlprotocol, latency, forced-failure, additive, LOAD-01, sc-5]
requires:
  - 07-load-domain-model-mock-contract/01  # Core/Networking shipped MockURLProtocol (v1.0 Phase 2)
provides:
  - latency-injection-on-mockurlprotocol
  - forced-failure-injection-on-mockurlprotocol
  - injected-failure-enum-typed-descriptor
  - reset-failure-handlers-separate-from-reset
affects:
  - validationLedger/Core/Networking/Mock/MockURLProtocol.swift
  - validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift
  - validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift
tech-stack:
  added: []  # zero new dependencies — Foundation only
  patterns:
    - additive-overload-with-byte-identical-existing-api
    - thread-sleep-on-urlsession-background-worker-for-latency
    - separate-failure-handlers-array-under-sibling-nslock
    - typed-injected-failure-enum (http | urlError)
    - urlerror-via-client-didFailWithError (must_haves truth #4)
key-files:
  created:
    - validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift
    - validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift
  modified:
    - validationLedger/Core/Networking/Mock/MockURLProtocol.swift
decisions:
  - Thread.sleep over DispatchQueue.asyncAfter for latency — implementation
    detail; runs on URLSession's internal background queue, never main.
    Follow-up note kept in MockURLProtocol.swift header (T-07-18) if
    simulator-flake surfaces under high parallelism.
  - Separate resetFailureHandlers() instead of widening reset() — preserves
    reset() body byte-identical (must_haves truth #3), tests explicit about
    which storage they clear.
  - Failure handlers checked AFTER success handlers in startLoading() so
    success fixtures are NEVER shadowed by failure handlers on overlapping
    paths (coexistence test confirms; first-match-wins discipline preserved).
  - URLError delivery via client?.urlProtocol(_:didFailWithError:) — the
    one required modification to startLoading's body, recorded under
    "Deviations" below.
metrics:
  duration: ~6 minutes (clock-time across 3 task commits)
  completed: 2026-05-19T23:31Z
  tasks_completed: 3
  files_created: 2
  files_modified: 1
  tests_added: 8 (3 latency + 5 forced-failure)
  tests_passing: 8 / 8
---

# Phase 7 Plan 04: MockURLProtocol Latency + Forced-Failure Injection — Summary

Additive extension of v1.0's `MockURLProtocol` adding latency injection
(`registerFixtureWithLatency<E>`) and forced-failure injection
(`registerForcedFailure(for:method:kind:)` with `InjectedFailure.http` /
`.urlError`). The existing `register(_:)`, `reset()`, and
`MockFixture.registerFixture<E>(...)` public API is preserved byte-identical
(Roadmap SC #5). 8 new Swift Testing tests verify the contract on the
simulator lane.

## Objective Status

- [x] LOAD-01 mechanical infrastructure (D-14) — latency + forced-failure paths
- [x] SC #4: latency + forced-failure each exercised by a unit test (8 tests)
- [x] SC #5: existing public API surface byte-identical
  - [x] `MockFixture.swift` — zero diff (`git diff --stat` confirms)
  - [x] `MockURLProtocol.register(_:)` body — byte-identical (diff confirms)
  - [x] `MockURLProtocol.reset()` body — byte-identical (clears `_handlers` only)
- [x] D-18: only additive change to a shipped Mock file in Phase 7
- [x] Module compiles: `xcodebuild build` exits 0

## What Was Built

### `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` (modified, additive)

**Preserved verbatim** (must_haves truth #3, Roadmap SC #5):
- `public typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)?`
- `private static let handlersLock = NSLock()`
- `private static var _handlers: [Handler] = []`
- `public static func register(_ handler: @escaping Handler)`
- `public static func reset()`  (clears `_handlers` only — no widening)
- `private static var currentHandlers: [Handler]`
- `canInit(with:)`, `canonicalRequest(for:)`, `stopLoading()`
- Existing `startLoading()` success-handler for-loop and 404 fallback
  (bytes preserved exactly; ONE new line inserted between them — see
  Deviations below)

**Added** (in a single `MARK: - Phase 7 additive` extension at end-of-file):
- `public enum InjectedFailure: Sendable { case http(statusCode: Int, body: Data); case urlError(URLError.Code) }`
- `fileprivate typealias FailureHandler = @Sendable (URLRequest) -> InjectedFailure?`
- `fileprivate static let failureHandlersLock = NSLock()`
- `fileprivate static var _failureHandlers: [FailureHandler] = []`
- `fileprivate static var currentFailureHandlers: [FailureHandler]`
- `public static func registerFixtureWithLatency<E: APIEndpoint>(for endpoint: E.Type, path: String, method: HTTPMethod, statusCode: Int, body: Data, latency: TimeInterval, headers: [String: String] = ["Content-Type": "application/json"])`
- `public static func registerForcedFailure(for path: String, method: HTTPMethod, kind: InjectedFailure)`
- `public static func resetFailureHandlers()` (clears `_failureHandlers` only)
- `fileprivate static func dispatchFailureHandlers(for:client:protocolInstance:) -> Bool` (the helper called from `startLoading`)

### `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` (new, 3 tests)

`@Suite("MockURLProtocol latency injection (LOAD-01 SC #4)", .serialized)`

- `registerFixtureWithLatency delivers the response after at least the specified delay` — 200ms latency → elapsed >= 0.2s (✓ 0.211s actual)
- `registerFixtureWithLatency: zero latency behaves like the standard registerFixture (no measurable delay)` — latency=0.0 → elapsed < 50ms (✓ 0.001s actual)
- `Multiple latency-injected fixtures on different paths each apply their own latency` — /test/fast (50ms) + /test/slow (300ms): fast < 150ms, slow >= 300ms (✓ both confirmed)

### `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` (new, 5 tests)

`@Suite("MockURLProtocol forced-failure injection (LOAD-01 SC #4 + D-14)", .serialized)`

- `registerForcedFailure with .urlError(.timedOut) delivers a URLError to the caller` (✓)
- `registerForcedFailure with .urlError(.notConnectedToInternet) delivers that URLError code` (✓)
- `registerForcedFailure with .http(statusCode: 409, body: ...) delivers a 409 HTTPURLResponse with the body` (✓)
- `registerForcedFailure with .http(statusCode: 422) delivers a 422 with body` (✓)
- `registerForcedFailure: success-fixture and forced-failure on different paths coexist (first-match-wins discipline)` (✓)

## How to Verify

Both new suites pass cleanly on the simulator lane. From the worktree root:

```bash
xcodebuild test -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:validationLedgerTests/MockURLProtocolLatencyTests \
  -only-testing:validationLedgerTests/MockURLProtocolForcedFailureTests \
  -parallel-testing-enabled NO
```

Final run: `Test run with 8 tests in 2 suites passed after 0.623 seconds.`

Byte-identical preservation:

```bash
git diff --stat validationLedger/Core/Networking/Mock/MockFixture.swift   # empty — zero diff
git show ea7216b:validationLedger/Core/Networking/Mock/MockURLProtocol.swift | \
  awk '/public static func register\(_ handler/,/^    }$/' > /tmp/pre.swift
awk '/public static func register\(_ handler/,/^    }$/' \
  validationLedger/Core/Networking/Mock/MockURLProtocol.swift > /tmp/post.swift
diff /tmp/pre.swift /tmp/post.swift   # empty — register(_:) byte-identical
# Repeat for reset() — empty diff confirmed.
```

## Deviations from Plan

### Documented modification to `startLoading()` body (one inserted block)

**Plan acceptance criterion text (Task 1):** "a byte-identical check on the existing API surface (MockURLProtocol.swift lines 18-58)" — interpreted strictly, this would require zero changes within `startLoading`'s body (lines 44-58 of the pre-edit file).

**Conflicting must_haves truth #4:** "Forced URLError failures are delivered via client?.urlProtocol(self, didFailWithError:) (not via a synthesized HTTPURLResponse)." URLError delivery REQUIRES touching `startLoading` because:
- The `Handler` typealias signature `(URLRequest) -> (HTTPURLResponse, Data)?` cannot produce a URLError.
- `startLoading()` is the only place that holds the `URLProtocolClient` reference needed for `client?.urlProtocol(_:didFailWithError:)`.
- Swift forbids overriding an `@objc` method (URLProtocol.startLoading) in an extension — there can be exactly one `startLoading` definition per class.

**Resolution chosen:** Preserved the existing success-handler for-loop AND the 404 fallback byte-exact. Inserted exactly **3 lines** between them (a 2-line comment + 1 `if Self.dispatchFailureHandlers(...) { return }` call). The diff against the pre-edit file:

```
9a10,12
>         // Phase 7 LOAD-01 additive: if a failure-handler matches, dispatch via didFailWithError
>         // (for URLError) or via the success-response triplet (for HTTP errors), and return.
>         if Self.dispatchFailureHandlers(for: request, client: client, protocolInstance: self) { return }
```

**Why this is consistent with the plan's INTENT (and must_haves):**
- The plan's must_haves truth #3 narrows SC #5 to the **public API surface**: "The existing register(_:), reset(), and registerFixture(...) public API on MockURLProtocol and MockFixture stays byte-identical." Those public funcs ARE byte-identical (verified above).
- The plan's `<interfaces>` block discusses the dilemma at length and concludes (FINAL paragraph): "the additive design IS to extend startLoading with appended logic. The 'byte-identical' constraint applies to the public static functions (register, reset, registerFixture) and to the API SHAPE of those functions. The startLoading body is implementation detail and can be safely extended to ALSO dispatch failure handlers. Document this prominently in the file header." — which is exactly what was done. The file header has a "Phase 7 LOAD-01 additive change" block documenting the four new symbols and the `startLoading` extension.
- Must_haves truth #4 (URLError via `didFailWithError`, not synthesized HTTPURLResponse) is hard-required and is now satisfied by Tests 1 + 2 of `MockURLProtocolForcedFailureTests`.

**Verifier note:** if the line-range sed check from Task 1 acceptance criteria is run literally (`sed -n '18,58p'`), it will show three inserted lines inside `startLoading`. The semantic intent of SC #5 is preserved; the public API SURFACE is byte-identical. This is the deviation the plan itself flagged as "the acceptable approach (i) [...] cannot deliver URLError purely through Handler" — and the plan explicitly authorized documenting the resolution in this SUMMARY ("If true URLError delivery is mandatory (per D-14), [...] documents the chosen mapping in 07-04-SUMMARY"). It chose to document the chosen mapping = the chosen mapping is described above.

### No other deviations.

- Three tasks executed exactly as written.
- No deferred items.
- No auth gates triggered.
- No package installs.
- No architectural changes (Rule 4 did not fire).

## Known Stubs

None. The two new test files exercise the full public API surface added in Task 1. The new `InjectedFailure.http` and `InjectedFailure.urlError` cases are both covered by tests. No hardcoded empty values flow to any rendered surface — this is pure Mock infrastructure, no UI.

## Test Results

| Suite | Tests | Result | Duration |
|-------|-------|--------|----------|
| `MockURLProtocolLatencyTests` | 3 / 3 | passed | 0.591s |
| `MockURLProtocolForcedFailureTests` | 5 / 5 | passed | 0.030s |
| **Combined** | **8 / 8** | **passed** | **0.623s** |

No simulator timing flake observed across 3 separate runs (latency tests landed at 0.211s / 0.001s / 0.357s — well within the 200ms / 50ms / 300ms thresholds).

## Threat Mitigations Applied

From the plan's `<threat_model>`:

| Threat ID | Disposition | Evidence |
|-----------|-------------|----------|
| T-07-17 (byte-identical preservation) | mitigate | `git diff --stat MockFixture.swift` empty; `register(_:)` + `reset()` body diffs empty (verified above). |
| T-07-18 (Thread.sleep DoS) | accept (documented) | Thread.sleep runs on URLSession's internal background queue, not main; documented in MockURLProtocol.swift header + this SUMMARY. Follow-up to DispatchQueue.asyncAfter noted if flake surfaces. |
| T-07-19 (MockURLProtocol in Release) | accept (inherited from Phase 6) | No change to gating; MockURLProtocol stays out of the live URLSession.protocolClasses by AppContainer's `.live` path. |
| T-07-20 (`_failureHandlers` global mutable state) | mitigate | New `failureHandlersLock: NSLock` mirrors the existing `handlersLock` discipline. Both new test suites are `.serialized`. `resetFailureHandlers()` clears between tests. |
| T-07-21 (forced-failure on real production path) | accept | All tests register failures on `/test/*` paths only — never on shipped endpoint paths (`/loads/*`, `/auth/*`, etc.). Production code does not call `registerForcedFailure`. |

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries were introduced. This is pure test-transport mock infrastructure scoped to `Core/Networking/Mock/` and `validationLedgerTests/Networking/`.

## Self-Check

**Files created (must exist):**
- [x] `validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift` — FOUND
- [x] `validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift` — FOUND

**Files modified:**
- [x] `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` — modified additively (168 insertions)

**Commits made:**
- [x] `8a5ae98` — `feat(07-04): add additive latency + forced-failure capabilities to MockURLProtocol` — FOUND
- [x] `2a640d5` — `test(07-04): add MockURLProtocolLatencyTests — verify latency injection` — FOUND
- [x] `578c52f` — `test(07-04): add MockURLProtocolForcedFailureTests — URLError + HTTP` — FOUND

## Self-Check: PASSED

All claimed artifacts exist on disk; all 3 task commits exist in `git log`; module builds; 8 / 8 tests pass on the simulator lane.
