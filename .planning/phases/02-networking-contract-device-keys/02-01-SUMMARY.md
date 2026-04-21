---
phase: 02-networking-contract-device-keys
plan: 01
subsystem: networking
tags: [ios, swift, urlsession, nslock, swift-testing, wave-0, phase-1-followup, cr-01, wr-01]

# Dependency graph
requires:
  - phase: 01-foundational-conventions-scaffolding
    provides: "NetworkClient protocol + URLSession-backed impl, MockURLProtocol scaffold, Swift Testing convention"
provides:
  - "NetworkError enum (7 cases) — typed networking error surface consumed by APIClient + interceptors"
  - "RequestInterceptor + ResponseInterceptor protocols — Wave 2 (Plan 04) interceptor contract"
  - "Force-cast-free NetworkClient.get/post (CR-01 closed) — non-HTTP responses throw NetworkError.unexpectedResponseType"
  - "NSLock-guarded MockURLProtocol.register/reset API (WR-01 closed) — parallel-test safe handler registry"
  - "MockURLProtocolRegistryTests suite (5 @Test cases) — proves WR-01 lock + .serialized trait invariants"
affects:
  - "02-02 (APIEndpoint + APIClient) — consumes NetworkError, RequestInterceptor, ResponseInterceptor"
  - "02-03 (Fixtures) — consumes MockURLProtocol.register + will move MockURLProtocol to Core/Networking/Mock/"
  - "02-04 (Interceptors) — implements RequestInterceptor + ResponseInterceptor (Idempotency, Retry)"
  - "02-05 (Cert pinning) — throws NetworkError.pinningFailed"
  - "02-07 (Environment) — throws NetworkError.baseURLMissing (closes WR-06 carryover)"

# Tech tracking
tech-stack:
  added: []  # Foundation-only; no new SPM deps
  patterns:
    - "Typed-error enum convention (parallels KeychainError) for all networking surface"
    - "NSLock.withLock { } guards for any public static mutable state in the main target"
    - "@Suite(.serialized) trait + MockURLProtocol.reset() at every @Test entry — triple-layer defense for shared test state"
    - "guard-let cast + typed throw replaces force-cast — CR-01 fix pattern to be applied project-wide"
    - "Two-protocol split: RequestInterceptor (header-only) + ResponseInterceptor (send-wrapper) keeps interceptor contract minimal"

key-files:
  created:
    - "validationLedger/Core/Networking/NetworkError.swift"
    - "validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift"
    - "validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift"
  modified:
    - "validationLedger/Core/Networking/NetworkClient.swift — CR-01 fix (guard-cast throws)"
    - "validationLedger/Core/Networking/MockURLProtocol.swift — WR-01 fix (NSLock-guarded register/reset, defaultPingHandler removed)"
    - "validationLedgerTests/Networking/MockURLProtocolTests.swift — updated to register own /ping fixture + .serialized trait"

key-decisions:
  - "Kept MockURLProtocol.swift at Core/Networking/MockURLProtocol.swift (did NOT move to Core/Networking/Mock/) — Plan 03 owns the directory move alongside MockFixture.swift; moving early would add a second pbxproj/sync change to Wave 0 with no corresponding benefit."
  - "Handler typealias marked @Sendable (not just the protocol surface) — Swift 6 concurrency checks propagate through the closure type into _handlers stored array; without @Sendable the registry cannot be locked-shared across actors."
  - "Chose guard-let + Issue.record over XCTFail in tests for the HTTPURLResponse downcast — consistent with CR-01 philosophy (no force-casts, even in test code) and matches Swift Testing idiom."
  - "Kept register API as append-only (no registerFirst/registerLast variants) — first-match-wins is already deterministic by registration order; adding variants adds surface without adding expressiveness."
  - "iPhone 17 Pro / iOS 26.4 used for local simulator test runs (dev machine has no iOS 17.5 runtime) — matches the Phase 1 substitution precedent documented in 01-07-SUMMARY.md. CI YAML still targets iOS 17.5 per docs/ci.md."

patterns-established:
  - "NetworkError — canonical error enum for all Phase 2 networking code; every async throws site throws exclusively through these 7 cases"
  - "MockURLProtocol.register + MockURLProtocol.reset — only sanctioned mutation paths for the handler registry; direct access to _handlers is private behind handlersLock"
  - "@Suite(.serialized) is MANDATORY for any test suite that mutates MockURLProtocol handlers (Plan 03+ fixture tests will inherit this)"
  - "RequestInterceptor vs ResponseInterceptor dichotomy — header-injecting interceptors (Idempotency, Auth) conform to RequestInterceptor; send-wrapping interceptors (Retry, CircuitBreaker) conform to ResponseInterceptor"

requirements-completed: []  # No REQ-IDs in Plan 01 frontmatter (Wave 0 gate plan; REQ coverage begins Wave 1)

# Metrics
duration: 5min
completed: 2026-04-21
---

# Phase 2 Plan 01: Networking Type Gate Summary

**Typed NetworkError enum + RequestInterceptor/ResponseInterceptor protocols + NSLock-guarded MockURLProtocol registry — closes Phase 1 CR-01 (force-cast DoS) and WR-01 (parallel-test handler race) as Wave 0 prerequisite for the remaining 6 Phase 2 plans.**

## Performance

- **Duration:** ~5 min (296s wall clock)
- **Started:** 2026-04-21T19:03:17Z
- **Completed:** 2026-04-21T19:08:13Z
- **Tasks:** 5 (all atomic, each with its own commit)
- **Files created:** 3 (NetworkError.swift, RequestInterceptor.swift, MockURLProtocolRegistryTests.swift)
- **Files modified:** 3 (NetworkClient.swift, MockURLProtocol.swift, MockURLProtocolTests.swift)

## Accomplishments

- **CR-01 closed:** `URLSessionNetworkClient.get/post` no longer force-casts `URLResponse` to `HTTPURLResponse`. Non-HTTP responses now throw `NetworkError.unexpectedResponseType(URLResponse)` — grep-verified: 0 `as! HTTPURLResponse` matches remain, 2 guard-cast throws present (one per method).
- **WR-01 closed:** `MockURLProtocol.handlers` global mutable static is gone. Handler registry is now behind `NSLock.withLock { }` with explicit `register(_:)`, `reset()`, and private `currentHandlers` getter. The Phase 1 `defaultPingHandler` default handler is deleted — every test registers its own fixture.
- **Wave 1/2 type surface landed:** `NetworkError` enum (7 cases: `unexpectedResponseType`, `httpError`, `decodingFailed`, `encodingFailed`, `retriesExhausted`, `pinningFailed`, `baseURLMissing`) + `RequestInterceptor` / `ResponseInterceptor` protocols with async-throws signatures. Plans 02 (APIClient), 04 (interceptors), 05 (pinning), 07 (environment) all now have their contract types.
- **Updated Phase 1 test rescued:** `MockURLProtocolTests.pingFixture` now registers its own `/ping` handler via the new API, applies `.serialized`, uses guard-cast + `Issue.record` instead of the old force-cast. Both @Test cases pass.
- **WR-01 validation suite added:** `MockURLProtocolRegistryTests` has 5 @Test cases (reset/register/first-match-wins/404-fallback/cycle-hygiene), all pass under `.serialized`. Serves as the regression harness for any future change to the lock or handler ordering.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create NetworkError + Interceptor protocols** — `0f3c4e3` (feat)
2. **Task 2: CR-01 — replace NetworkClient force-casts with guard-cast throws** — `1865b43` (fix)
3. **Task 3: WR-01 — NSLock-guarded MockURLProtocol with register/reset/currentHandlers** — `36b6558` (fix)
4. **Task 4: Update Phase 1 MockURLProtocolTests to use new register/reset API** — `e1b1bd4` (test)
5. **Task 5: Add MockURLProtocolRegistryTests — WR-01 validation suite, 5 @Test cases** — `b67f0cb` (test)

**Plan metadata commit:** pending (final SUMMARY commit will land after this file is written)

## Files Created/Modified

### Created

- `validationLedger/Core/Networking/NetworkError.swift` — Typed networking error enum; 7 cases covering every throw site Wave 1/2 plans need. Public + Error + Sendable.
- `validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift` — `RequestInterceptor` (async URLRequest mutator) + `ResponseInterceptor` (async send-wrapper). Both Sendable protocols. Directory created by this plan.
- `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` — 5 @Test cases under `@Suite(.serialized)` validating the WR-01 fix: reset, register+fetch, first-match-wins, 404 fallback, register/reset cycle hygiene.

### Modified

- `validationLedger/Core/Networking/NetworkClient.swift` — CR-01 fix: both `get(_:)` and `post(_:body:)` replaced `response as! HTTPURLResponse` with `guard let http = response as? HTTPURLResponse else { throw NetworkError.unexpectedResponseType(response) }`. File header updated for Phase 2 Plan 01 context.
- `validationLedger/Core/Networking/MockURLProtocol.swift` — WR-01 fix: full replacement. Removed `public static var handlers`; removed `defaultPingHandler`; added `handlersLock: NSLock`, private `_handlers`, public `register(_:)`, public `reset()`, private `currentHandlers`. Handler typealias marked `@Sendable`.
- `validationLedgerTests/Networking/MockURLProtocolTests.swift` — Updated for new API: `@Suite(.serialized)` trait added; `pingFixture` now registers its own /ping handler + `defer { reset() }`; force-cast replaced with guard-let + `Issue.record`.

## Decisions Made

1. **MockURLProtocol stays at `Core/Networking/MockURLProtocol.swift` (not moved to `Core/Networking/Mock/`)** — Plan 03 owns the directory move alongside `MockFixture.swift`. Moving in Wave 0 would be an isolated pbxproj/sync change with no batching benefit, and would force Plan 03 to also update the file's location in its task list.
2. **`Handler` typealias marked `@Sendable`, not just the protocols** — Swift 6 propagates sendability through stored closure types; the array `_handlers: [Handler]` cannot be lock-shared across actors unless the closure type itself is Sendable.
3. **Used `guard-let + Issue.record`, not `as! HTTPURLResponse`, in the test bodies** — Consistent with the CR-01 philosophy (no force-casts anywhere, production or test). Swift Testing's `Issue.record` is the idiomatic equivalent of XCTFail.
4. **Kept `register` as append-only** — First-match-wins is deterministic by registration order; no `registerFirst/registerLast` variants needed. Tests that want priority can reset + re-register in the desired order.
5. **Local test destination: iPhone 17 Pro / iOS 26.4** — Dev machine has no iOS 17.5 simulator runtime available (only iOS 15.2, 18.0–18.4, 26.2, 26.4). This matches the Phase 1 precedent documented in `01-07-SUMMARY.md`: CI YAML pins iOS 17.5 via `-downloadPlatform iOS -buildVersion 17.5` fallback; local dev uses the newest installed runtime. Apple guarantees forward-compat from iOS 17.0 deployment target.

## Deviations from Plan

**None — plan executed exactly as written.**

The plan's verbose `<action>` blocks gave full source text for every new file and the full replacement block for both modified source files. Every grep-verification, every `done` criterion, every build/test command in the plan worked on the first attempt.

Minor, non-deviation substitution:
- Plan `<verify>` and `<action>` blocks specify `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. Local dev machine has no iOS 17.5 runtime, so substituted `iPhone 17 Pro, OS=26.4` per the Phase 1 precedent. This is an environmental substitution, not a plan deviation — the plan itself acknowledges CI targets 17.5 and Phase 1 already established the local-vs-CI split.

## Issues Encountered

None. The `read-before-edit` hook fired twice on legitimate edits (NetworkClient.swift Edit, MockURLProtocol.swift Write, MockURLProtocolTests.swift Write) where the files had been Read earlier in the session — the edits succeeded regardless because the session history contained the Read calls. No impact on outcomes.

## Verification Results

### Invariant checks (grep)

| Check | Expected | Actual |
|---|---|---|
| `as! HTTPURLResponse` in NetworkClient.swift | 0 | 0 |
| `throw NetworkError.unexpectedResponseType` in NetworkClient.swift | 2 | 2 |
| `handlersLock.withLock` in MockURLProtocol.swift | ≥3 | 3 |
| `public static var handlers` in MockURLProtocol.swift | 0 | 0 |
| `@Sendable` in MockURLProtocol.swift | ≥1 | 2 |
| `defaultPingHandler` in MockURLProtocol.swift (code) | 0 | 0 (only a comment mentions the removal) |
| `.serialized` in MockURLProtocolTests.swift | ≥1 | 2 (suite + possibly trait-internal ref) |
| `.serialized` in MockURLProtocolRegistryTests.swift | ≥1 | 2 |
| `@Test` count in MockURLProtocolRegistryTests.swift | 5 | 5 |

### Build + test

- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'` — **BUILD SUCCEEDED** (run after Task 1, Task 2, Task 3).
- `xcodebuild test -only-testing:validationLedgerTests/MockURLProtocolTests` — **2/2 tests pass** (canRegister, pingFixture).
- `xcodebuild test -only-testing:validationLedgerTests/MockURLProtocolRegistryTests` — **5/5 tests pass** (resetEmpties, registerReturnsFixture, firstMatchWins, unmatchedReturns404, cycleHygiene).
- Combined run of both networking suites: **7/7 tests pass** in 0.017s.

## Phase 1 Follow-ups Closed

| ID | Title | Closed in commit |
|---|---|---|
| CR-01 | `URLSessionNetworkClient` force-casts `URLResponse` → `HTTPURLResponse` | `1865b43` (Task 2) |
| WR-01 | `MockURLProtocol.handlers` global mutable state — concurrent test mutations cause races | `36b6558` (Task 3) |

WR-06 (`Environment.release apiBaseURL: nil` with no enforcement) is a Plan 07 follow-up — not closed here. The `NetworkError.baseURLMissing` case is the landing zone for Plan 07's enforcement.

## Wave 1/2 Plan Consumers of This Plan's Surface

| Symbol introduced | Consumer file(s) (by upcoming plan) |
|---|---|
| `NetworkError` (all 7 cases) | Plan 02: `APIClient.swift`, `APIEndpoint.swift`; Plan 04: `RetryInterceptor.swift`, `IdempotencyInterceptor.swift`; Plan 05: `PinningSessionDelegate.swift` (pinningFailed); Plan 07: `Environment.swift` (baseURLMissing) |
| `RequestInterceptor` | Plan 04: `IdempotencyInterceptor.swift`, future auth/token interceptors |
| `ResponseInterceptor` | Plan 04: `RetryInterceptor.swift`, future circuit-breaker/timing interceptors |
| `MockURLProtocol.register(_:)` / `.reset()` | Plan 03: every fixture test; Plan 04+: every interceptor test that drives a mock transport |
| `MockURLProtocol.Handler` typealias | Plan 03: `MockFixture.swift` `registerFixture<E: APIEndpoint>(...)` extension |

## User Setup Required

None — no external service configuration needed for this plan. (OTP, App Attest, push notification config land Phases 3–4.)

## Next Phase Readiness

- **Plan 02 ready:** `NetworkError` + interceptor protocols compiled and Sendable-clean; APIClient can throw exclusively through these cases.
- **Plan 03 ready:** `MockURLProtocol.register/reset` is the sanctioned fixture API; lock + `.serialized` pattern is proven by the 5-test registry suite.
- **Plan 04 ready:** Both interceptor protocols exist with the exact async-throws signatures Wave 2 expects.
- **No blockers.** Wave 0 gate is closed.

## Self-Check: PASSED

Files verified on disk:

- `validationLedger/Core/Networking/NetworkError.swift` — **FOUND**
- `validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift` — **FOUND**
- `validationLedger/Core/Networking/NetworkClient.swift` — **FOUND** (modified)
- `validationLedger/Core/Networking/MockURLProtocol.swift` — **FOUND** (modified)
- `validationLedgerTests/Networking/MockURLProtocolTests.swift` — **FOUND** (modified)
- `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` — **FOUND**

Commits verified in git log:

- `0f3c4e3` (Task 1 feat) — **FOUND**
- `1865b43` (Task 2 fix) — **FOUND**
- `36b6558` (Task 3 fix) — **FOUND**
- `e1b1bd4` (Task 4 test) — **FOUND**
- `b67f0cb` (Task 5 test) — **FOUND**

---
*Phase: 02-networking-contract-device-keys*
*Plan: 01*
*Completed: 2026-04-21*
