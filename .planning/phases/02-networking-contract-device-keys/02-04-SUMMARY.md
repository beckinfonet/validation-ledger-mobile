---
phase: 02-networking-contract-device-keys
plan: 04
subsystem: networking
tags: [ios, networking, interceptors, idempotency, retry, net-04, net-05, m1, wave-2]

# Dependency graph
requires:
  - phase: 02-networking-contract-device-keys
    plan: 01
    provides: "RequestInterceptor + ResponseInterceptor protocols; NetworkError.retriesExhausted"
  - phase: 02-networking-contract-device-keys
    plan: 02
    provides: "APIClient facade with interceptor-chain composition (responseInterceptors.reversed().reduce)"
  - phase: 02-networking-contract-device-keys
    plan: 03
    provides: "MockURLProtocol.registerFixture + FixtureLoader (available for future integration tests; not required by Plan 04)"
provides:
  - "IdempotencyInterceptor — RequestInterceptor that injects Idempotency-Key: UUID().uuidString on POST + PUT only; preserves caller-supplied keys (Phase 5 replay path)"
  - "RetryInterceptor — ResponseInterceptor with GET-only exponential-backoff retry on 5xx + retryable URLError set; default 3 retries, 500ms base, ×2^attempt, ±20% jitter, 4000ms ceiling"
  - "Test convention: direct-closure ResponseInterceptor tests with actor-backed Counter (no MockURLProtocol mutation needed for interceptor unit tests)"
  - "Test convention: Foundation UUID(uuidString:) as the cleanest UUID-format assertion"
affects:
  - "02-07 (Environment / AppContainer) — will wire `[IdempotencyInterceptor()]` as requestInterceptors and `[RetryInterceptor()]` as responseInterceptors on the production APIClient"
  - "03 (Phase 3 AuthRepository) — POSTs (OTP request/verify) automatically carry Idempotency-Key via the composed APIClient; OTP-verify failures no longer duplicate on retry storms"
  - "04 (Phase 4 DEV-04) — device-register POST carries Idempotency-Key; attestation retries inherit idempotency dedup"
  - "05 (Phase 5 KYCUploader) — chunk POST Idempotency-Key behavior is consistent with NET-04; UPL-02 resumable-chunk replay uses its own explicit-key path (Phase 5 inserts key before APIClient call; IdempotencyInterceptor preserves it)"

# Tech tracking
tech-stack:
  added: []  # Foundation only; no new SPM deps
  patterns:
    - "Struct-based Sendable interceptors with no mutable state — copy-cheap into interceptor arrays"
    - "Method-gate pattern for RequestInterceptor (POST+PUT for idempotency, GET-only for retry) via `guard let method = request.httpMethod, method == ...`"
    - "Overwrite-guard pattern (`guard request.value(forHTTPHeaderField:) == nil`) — interceptors must never blindly clobber caller-supplied headers"
    - "Exponential backoff with ceiling + jitter: `min(baseDelayMs << attempt, ceilingMs) ± 20% uniform jitter` in milliseconds → Task.sleep(nanoseconds:)"
    - "Final-5xx-returns-response (NOT throws) — retry exhaustion on HTTP surface returns the last response so APIClient's status-code check converts it to NetworkError.httpError uniformly; throws only if every attempt caught a URLError and no response was ever captured"
    - "Parameterized Swift Testing (`@Test(arguments:)`) for status-code × method matrices — one function signature, N test cases, consistent assertions"
    - "Actor-backed Counter for async test-body invocation counting — Sendable-safe under Swift 6, avoids @unchecked hacks"
    - "Internal-access backoff math (`delayForAttempt`, `isRetryable`) — exposed to `@testable import validationLedger` without leaking into the public surface"

key-files:
  created:
    - "validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift"
    - "validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift"
    - "validationLedgerTests/Networking/IdempotencyInterceptorTests.swift"
    - "validationLedgerTests/Networking/RetryInterceptorTests.swift"
  modified: []

key-decisions:
  - "Final-5xx path RETURNS the last response (does not throw) — RetryInterceptor lets APIClient's 200-299 gate be the single place that maps HTTP status → NetworkError.httpError. Throws NetworkError.retriesExhausted only when every attempt caught a URLError and no response was captured (request never landed). Matches Research Pattern 6."
  - "`delayForAttempt` and `isRetryable` have internal access (not private) so RetryInterceptorTests can exercise the math directly via @testable import. Keeping them non-public avoids leaking the implementation into the public API surface."
  - "Added overflow safeguard in `delayForAttempt` — if attempt ≥ 62 the shift would overflow UInt64, so saturate to UInt64.max before clamping to ceilingMs. Plan specified attempt ≤ maxRetries = 3 in practice; the test `backoffCeiling` runs attempt = 10, still safe. Safeguard is belt-and-braces for future callers."
  - "Non-retryable URLError cases (e.g., `.cancelled`, `.userCancelledAuthentication`) rethrow AFTER a single attempt — matches Research Pattern 6 classification. `.cancelled` is caller-initiated abort; retrying would be hostile."
  - "Retry URLError set matches Research Pattern 6 verbatim — {networkConnectionLost, timedOut, notConnectedToInternet, cannotConnectToHost, dnsLookupFailed}. No additions. Any Phase 3+ need to add a code (e.g., `.internationalRoamingOff`) goes through a separate change + test."
  - "Test used iPhone 17 Pro / iOS 26.4 — matches Phase 1 + Plan 02-01/02/03 precedent. Dev machine has no iOS 17.5 runtime; CI pins 17.5 per docs/ci.md. Local-vs-CI split is well-established."
  - "Did NOT wire interceptors into AppContainer — per plan scope (Plan 07 owns composition). files_modified scope is strictly the 4 new files."

patterns-established:
  - "Interceptor implementation pattern — `public struct` + explicit `public init()` + `Sendable` via no-mutable-state + method-gate at top of intercept + overwrite-guard where relevant. Any future interceptor (auth-token, circuit-breaker) follows this shape."
  - "Interceptor test pattern — no MockURLProtocol needed. For RequestInterceptor: call `interceptor.intercept(request)` and assert on the returned URLRequest. For ResponseInterceptor: pass a direct `send:` closure counting invocations with an actor. Fast, isolated, ordering-independent."
  - "Final-retry-returns-response semantics — this plan establishes the convention for HTTP-layer retry exhaustion. Any future retry variant (e.g., Retry-After header support) should match it so callers see a consistent NetworkError.httpError for any non-2xx outcome."

requirements-completed:
  - NET-04   # POSTs carry Idempotency-Key: UUID().uuidString header
  - NET-05   # GET-only exponential-backoff retry on 5xx + retryable URLError; max 3 retries

# Metrics
duration: ~8min
completed: 2026-04-21
---

# Phase 2 Plan 04: Idempotency + Retry Interceptors Summary

**IdempotencyInterceptor (injects UUID Idempotency-Key on POST/PUT; preserves caller-supplied keys) + RetryInterceptor (GET-only exponential-backoff retry on 5xx + retryable URLErrors with jitter+ceiling) + comprehensive @Test coverage — closes NET-04 and NET-05, gives Plan 07 a drop-in interceptor pair, and establishes the interceptor test convention for the rest of Phase 2+.**

## Performance

- **Duration:** ~8 min (493s wall clock)
- **Started:** 2026-04-21T19:48:29Z
- **Completed:** 2026-04-21T19:56:42Z
- **Tasks:** 4 (all atomic, each with its own commit)
- **Files created:** 4 (2 interceptors, 2 test files)
- **Files modified:** 0
- **Tests added:** 14 @Test methods (5 Idempotency + 9 Retry, plus parameterized expansion to 23 test invocations)

## Accomplishments

- **NET-04 landed in full:** `IdempotencyInterceptor` is a public `struct` conforming to `RequestInterceptor`, Sendable, no mutable state. Injects `Idempotency-Key: UUID().uuidString` on POST + PUT only; GET and DELETE pass through unchanged; caller-supplied Idempotency-Key headers are preserved (Phase 5 replay path intact). Per Research Pattern 5.
- **NET-05 landed in full:** `RetryInterceptor` is a public `struct` conforming to `ResponseInterceptor`, Sendable, configurable via init (default maxRetries=3, baseDelayMs=500, ceilingMs=4000). GET-only retry gate at the top of intercept; POST/PUT/DELETE pass through single-attempt. Exponential backoff: `min(baseDelayMs << attempt, ceilingMs) ± 20% jitter`. Retryable URLError set: `{networkConnectionLost, timedOut, notConnectedToInternet, cannotConnectToHost, dnsLookupFailed}` — verbatim from Research Pattern 6.
- **14 @Test methods cover every branch:** 5 for Idempotency (POST inject, PUT inject, GET no-inject, DELETE no-inject, existing-key preserve), 9 for Retry (5xx retry × 4 status codes, non-5xx no-retry × 7 status codes, non-GET no-retry × 3 methods, retryable URLError exhaust, non-retryable URLError rethrow, isRetryable accept × 5 codes, isRetryable reject × 4 codes, delayForAttempt base ± 20%, delayForAttempt ceiling). Parameterized tests expand to 23 total test invocations.
- **Test harness convention established:** Both test files use direct interceptor invocation — no MockURLProtocol mutation. RetryInterceptorTests uses an `actor Counter` for Sendable-safe invocation counting under Swift 6. Fast base/ceiling values (1ms base, 16ms ceiling) keep the full Retry suite under ~200ms wall clock.
- **Final-5xx semantics clarified:** On retry budget exhaustion with captured responses (i.e., server returned 500 on every attempt), the interceptor RETURNS the last response rather than throwing. APIClient's existing `(200...299).contains` gate converts it to `NetworkError.httpError(statusCode:, data:)` uniformly. Throws `NetworkError.retriesExhausted` (or the last caught URLError) only when every attempt caught a URLError with no captured response. This matches Research Pattern 6's sketch and gives callers one consistent error case to handle.
- **Plan 07 wiring confirmed unblocked:** APIClient accepts `requestInterceptors: [any RequestInterceptor]` and `responseInterceptors: [any ResponseInterceptor]` init parameters (Plan 02); this plan ships both struct conformances ready to be passed in. Plan 07's AppContainer constructor will add `requestInterceptors: [IdempotencyInterceptor()], responseInterceptors: [RetryInterceptor()]` with zero other changes required.

## Task Commits

Each task was committed atomically:

1. **Task 1: IdempotencyInterceptor implementation** — `72f87b2` (feat)
2. **Task 2: IdempotencyInterceptorTests (5 @Test)** — `a34a629` (test)
3. **Task 3: RetryInterceptor implementation** — `80f347a` (feat)
4. **Task 4: RetryInterceptorTests (9 @Test, parameterized → 23 invocations)** — `f166180` (test)

**Plan metadata commit:** pending (final SUMMARY commit lands after this file is written).

## Files Created/Modified

### Created

- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` — 29 lines. `public struct IdempotencyInterceptor: RequestInterceptor` with `public init()` and the `intercept(_:)` body. Method-gate on POST/PUT; overwrite-guard via `guard request.value(forHTTPHeaderField: "Idempotency-Key") == nil`.
- `validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift` — 121 lines. `public struct RetryInterceptor: ResponseInterceptor` with configurable init (maxRetries, baseDelayMs, ceilingMs), GET-only gate, `for attempt in 0...maxRetries` retry loop with `Task.sleep(nanoseconds:)` backoff, internal-access `delayForAttempt(_:)` and `isRetryable(_:)` helpers, final-5xx-returns-response semantics, `NetworkError.retriesExhausted` throw on all-URLError exhaustion with no captured response.
- `validationLedgerTests/Networking/IdempotencyInterceptorTests.swift` — 70 lines. `@Suite("IdempotencyInterceptor — header injection (NET-04)")` with 5 `@Test` methods and 2 private helpers (`makeRequest`, `isValidUUID`).
- `validationLedgerTests/Networking/RetryInterceptorTests.swift` — 205 lines. `@Suite("RetryInterceptor — GET-only + backoff (NET-05)")` with 9 `@Test` methods (3 parameterized), private `actor Counter`, and 3 private helpers (`request`, `httpResponse`, `fastInterceptor`).

### Modified

None. Plan 04 is purely additive.

## Answers to Plan `<output>` Questions

1. **Retry-exhausted semantics — which path?** The implementation takes the **return-last-5xx-response** path (NOT throw `retriesExhausted`). When every retry attempt receives a 5xx response, `RetryInterceptor` returns the last `(Data, HTTPURLResponse)` pair; APIClient's `(200...299).contains(response.statusCode)` gate then throws `NetworkError.httpError(statusCode: 5xx, data: ...)`. `NetworkError.retriesExhausted` is thrown only when every retry caught a URLError and no response was ever captured. This matches Research Pattern 6 and the plan's behavior spec. **Plan 07 integration-test expectation:** for a 500-on-every-attempt scenario, expect `NetworkError.httpError(statusCode: 500, ...)`, NOT `NetworkError.retriesExhausted`. For a `URLError.networkConnectionLost`-on-every-attempt scenario, expect the URLError or `NetworkError.retriesExhausted` (acceptable per spec; implementation throws the last caught URLError since one was always captured).

2. **Additional URLError codes beyond Research Pattern 6?** None. The retryable set is verbatim: `{networkConnectionLost, timedOut, notConnectedToInternet, cannotConnectToHost, dnsLookupFailed}`. Any Phase 3+ additions (e.g., `.internationalRoamingOff`, `.callIsActive`) require an explicit follow-up plan with corresponding test coverage in `isRetryableAcceptsDocumentedCodes`.

3. **Chosen defaults for AppContainer wiring:** `maxRetries: 3`, `baseDelayMs: 500`, `ceilingMs: 4_000`. These are the init defaults — Plan 07 can simply call `RetryInterceptor()` and `IdempotencyInterceptor()` with no arguments. If environment-specific tuning becomes desirable (staging = longer retries, release = tighter), Plan 07 can pass configured instances; the default-argument init supports both patterns.

4. **Plan 07 wiring flag:** Plan 07 wires `requestInterceptors: [IdempotencyInterceptor()]` and `responseInterceptors: [RetryInterceptor()]` on the APIClient inside `AppContainer.init`. Both defaults match Research Pattern 6 and the NET-04/NET-05 specs. No further configuration is required unless Plan 07 chooses to surface knobs via Environment.

## Decisions Made

1. **Final-5xx returns response rather than throws.** The interceptor's role is to retry transiently; the caller's role (via APIClient) is to map HTTP-status to `NetworkError.httpError`. Keeping those roles separate means the retry interceptor is composable with any future response interceptor (e.g., a rate-limit interceptor that also wants to consume the response). If RetryInterceptor threw on 5xx, APIClient would need two branches (`NetworkError.httpError` for non-retry 5xx paths, `NetworkError.retriesExhausted` for retry paths). Uniformity wins.
2. **Internal access for `delayForAttempt` + `isRetryable`.** Private would force `@testable` into awkward indirection; public would leak implementation details. Internal + `@testable import validationLedger` hits the sweet spot — tests exercise the math directly, production callers see only the `init` + `intercept` surface.
3. **Overflow guard in `delayForAttempt`.** The plan example (`baseDelayMs << attempt`) is safe at `attempt ≤ 3`, but the `backoffCeiling` test runs `attempt = 10` and any future caller might go higher. Added `if attempt >= 62 { rawShift = UInt64.max }` short-circuit — saturates to ceiling regardless. Zero cost in the hot path (attempts 0–3).
4. **actor Counter instead of AtomicInt or `@unchecked Sendable` wrapper.** Swift 6 concurrency-checks mark captured mutable variables inside `@Sendable` closures. `actor Counter` is the first-party fix — no `@unchecked`, no Foundation `OSAllocatedUnfairLock`, no Atomics import. Reads cost one `await`; in unit tests that's ~1µs.
5. **Did NOT wire into AppContainer.** Plan scope explicitly excludes composition; Plan 07 owns that. Any interceptor wiring here would be out-of-scope and would collide with Plan 07's future edits to `App/AppContainer.swift`.
6. **Local test destination iPhone 17 Pro / iOS 26.4.** Dev machine has no iOS 17.5 runtime; matches Plan 02-01/02/03 precedent. CI YAML targets iOS 17.5 via `docs/ci.md`.

## Deviations from Plan

**None — plan executed exactly as written.**

The plan's `<action>` blocks were production-ready: both interceptor implementations and both test files worked on first build/test attempt. The only micro-adjustments beyond the plan's verbatim sketch were:

- **Added `precondition` assertions in `RetryInterceptor.init`** for `maxRetries >= 0`, `baseDelayMs > 0`, `ceilingMs >= baseDelayMs` — catches init-time misconfiguration in DEBUG builds. Not a plan deviation; a Rule 2 critical-operation guard (correctness under invalid config).
- **Added `if attempt >= 62` overflow guard in `delayForAttempt`** — Rule 2 critical correctness for future callers that might pass large attempt indices. Zero cost in the default configuration.
- **Used `let five_hundred = httpResponse(statusCode: 500)` outside the `send:` closure** in `nonGETDoesNotRetry` to avoid `self.` capture warnings under strict-concurrency — minor test-body refactor, no behavior change.

Environmental substitution (local iPhone 17 Pro vs plan's iPhone 15) is documented as a precedent-matching non-deviation — see plan `<environmental_note>` and the Plan 02-01/02/03 SUMMARY precedent.

## Issues Encountered

1. **Transient simulator teardown crash on one RetryInterceptorTests run.** First `xcodebuild test -only-testing:validationLedgerTests/RetryInterceptorTests` run reported `** TEST FAILED **` with `Early unexpected exit, operation never finished bootstrapping`, but the per-test output showed all 9 @Test methods passed. Re-ran identical command — `** TEST SUCCEEDED **` with 9/9 pass. Also reproducible on the 5-suite combined run (`** TEST FAILED **` on one attempt, `** TEST SUCCEEDED **` on re-run; 35/35 tests pass both times). Root cause appears to be a simulator-side bootstrap flake, not a test-code bug — the test run completes successfully and all tests pass; the failure is in the xcodebuild harness's session-teardown phase. No action taken; flagging for CI policy (re-run on exit-code failure if per-test output is all-pass). Logged here for Plan 07's integration-test plan to watch out for.
2. **`read-before-edit` hook compatibility.** No impact — all Writes succeeded because this plan creates new files (no Edit-before-Read scenarios).

## Verification Results

### Invariant checks (grep)

| Check | Expected | Actual |
|---|---|---|
| `setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")` in IdempotencyInterceptor.swift | 1 | 1 |
| `request.value(forHTTPHeaderField: "Idempotency-Key") == nil` in IdempotencyInterceptor.swift (overwrite guard) | 1 | 1 |
| `request.httpMethod == "GET"` in RetryInterceptor.swift (method gate) | 1 | 1 |
| `NetworkError.retriesExhausted` references in RetryInterceptor.swift | ≥1 | 2 (comment + throw) |
| `@Test` methods in IdempotencyInterceptorTests.swift | 5 | 5 |
| `@Test` methods in RetryInterceptorTests.swift | 9 | 9 |
| Suite on IdempotencyInterceptor tests | 1 | 1 (no `.serialized` — no shared state) |
| Suite on RetryInterceptor tests | 1 | 1 (no `.serialized` — no shared state) |
| Files under Core/Networking/Interceptors/ | 3 (RequestInterceptor + Idempotency + Retry) | 3 |
| Files under validationLedgerTests/Networking/ matching `Interceptor*Tests.swift` | 2 | 2 |

### Build + test

- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'` — **BUILD SUCCEEDED** (post-Task 1 and post-Task 3).
- `xcodebuild test -only-testing:validationLedgerTests/IdempotencyInterceptorTests` — **5/5 tests pass** in 0.008s.
- `xcodebuild test -only-testing:validationLedgerTests/RetryInterceptorTests` — **9/9 @Test methods pass** (23 test invocations including parameterized) in 0.159s.
- `xcodebuild test -only-testing:validationLedgerTests/IdempotencyInterceptorTests -only-testing:validationLedgerTests/RetryInterceptorTests` — **14 tests in 2 suites pass** in 0.033s (parallel). No MockURLProtocol state → no `.serialized` needed on these two suites.
- Full Networking subtarget (5 suites: Idempotency + Retry + APIClientEndpoint + MockURLProtocol + MockURLProtocolRegistry) with `-parallel-testing-enabled NO` — **35/35 tests pass** in 0.127s. No regressions in Plan 01/02/03 suites.

## Reuse by Wave 2+ / Phase 3+ Plans

| Symbol introduced | Consumer (upcoming plan / phase) |
|---|---|
| `IdempotencyInterceptor()` | Plan 07: `AppContainer.apiClient` init; Phase 3 POSTs inherit Idempotency-Key; Phase 4 DEV-04; Phase 5 KYC chunks |
| `RetryInterceptor()` + `RetryInterceptor(maxRetries:baseDelayMs:ceilingMs:)` | Plan 07: AppContainer; future GET calls (KYC status polling, dashboards) inherit retry |
| Interceptor test convention (direct closure + actor Counter) | Future interceptor plans (auth-token, circuit-breaker, rate-limit) |
| `delayForAttempt` / `isRetryable` internal surface | RetryInterceptorTests and any future retry variant in this module |
| Final-5xx-returns-response semantic | Plan 07 integration tests (expect `NetworkError.httpError` from 5xx-storm; not `retriesExhausted`) |

## Next Phase Readiness

- **Plan 05 (Cert pinning) — not blocked by this plan.** Different file set (CertificatePinning/); runs in parallel in Wave 2.
- **Plan 06 (Secure Enclave) — not blocked by this plan.** Different file set (KeyStore/ + Identity/); runs in parallel in Wave 2.
- **Plan 07 (Environment + AppContainer wiring) ready:** `IdempotencyInterceptor()` and `RetryInterceptor()` are drop-in ready. Plan 07 adds two array literals in AppContainer's APIClient init; no further changes needed.
- **Phase 3 AuthRepository ready:** OTP POSTs will carry `Idempotency-Key` once Plan 07 wires the interceptor chain. No code change needed in AuthRepository itself.
- **Phase 5 KYCUploader ready:** Chunk POSTs will carry `Idempotency-Key`. UPL-02 resumable-replay path sets the key BEFORE calling APIClient; IdempotencyInterceptor's overwrite-guard preserves it, so replay-with-same-key works end-to-end.
- **No blockers for Wave 2 parallel plans or downstream phases.**

## Self-Check: PASSED

Files verified on disk:

- `validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift` — **FOUND**
- `validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift` — **FOUND**
- `validationLedgerTests/Networking/IdempotencyInterceptorTests.swift` — **FOUND**
- `validationLedgerTests/Networking/RetryInterceptorTests.swift` — **FOUND**

Commits verified in git log:

- `72f87b2` (Task 1 feat) — **FOUND**
- `a34a629` (Task 2 test) — **FOUND**
- `80f347a` (Task 3 feat) — **FOUND**
- `f166180` (Task 4 test) — **FOUND**

---
*Phase: 02-networking-contract-device-keys*
*Plan: 04*
*Completed: 2026-04-21*
