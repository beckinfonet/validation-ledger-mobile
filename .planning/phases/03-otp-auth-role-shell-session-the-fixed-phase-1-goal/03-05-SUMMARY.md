---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 05
subsystem: networking
tags: [ios, networking, rate-limiting, wave-1, tdd, auth-02, d-02]

# Dependency graph
requires:
  - phase: 02-networking-contract-and-device-keys
    provides: "APIClient response-handling block + NetworkError typed surface + MockURLProtocol NSLock-guarded handler registry + FixtureLoader"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "validationLedgerTests/Networking/APIClientRateLimitTests.swift Wave 0 stub + validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json fixture body — filled / paired in this plan"
provides:
  - "NetworkError.rateLimited(retryAfter: TimeInterval) — typed rate-limit error surface"
  - "APIClient.parseRetryAfter(from:now:) — RFC 7231 delta-seconds + HTTP-date parser with test-injectable `now` parameter"
  - "APIClient 429 detection branch BEFORE the generic httpError throw — transport-boundary fold; OTPViewModel (Plan 09) pattern-matches NetworkError.rateLimited(let retryAfter) to drive 1-Hz Verify-button-disable countdown"
  - "Default fallback: 60 seconds when Retry-After header is missing OR malformed (T-03-05-03 tampering mitigation via max(0, ...) clamp)"
  - "4 new green tests filling the Wave 0 APIClientRateLimitTests stub"
  - "Updated APIClientEndpointTests.otpRequestFailure — Phase 2 baseline asserted 429→httpError; Plan 05 contract changes 429→rateLimited"
affects:
  - "03-09 (OTPViewModel D-27 7-step orchestration) — can now pattern-match `catch NetworkError.rateLimited(let retryAfter)` to drive the Verify-button countdown"
  - "03-07 (Auth401ResponseInterceptor) — unaffected (401 path is orthogonal to 429 path); the typed error patterns in this plan establish the convention that Auth401ResponseInterceptor follows"
  - "M2+ any endpoint that rate-limits — the typed error surface is now uniform across all endpoints; no per-endpoint rate-limit handling needed"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Transport-boundary typed-error fold: 429 is detected INSIDE APIClient.request<E> (not in a ResponseInterceptor) because it produces a typed error with zero side effects. Auth401ResponseInterceptor (Plan 07) is a separate ResponseInterceptor because logout IS a side effect. Pattern: typed error folds live at the boundary; side-effecting reactions live in interceptors."
    - "Test-injectable clock via optional `now: Date = .now` parameter. parseRetryAfter(from:now:) keeps HTTP-date assertions deterministic in test (`parseRetryAfterHttpDate` passes a fixed `now` + a future date formatted against the same now). Production callers always use the default. No protocol extraction needed — the default parameter is sufficient for a static parser."
    - "Negative-value clamp via max(0, ...) on both delta-seconds and HTTP-date paths. Non-conforming servers that return Retry-After: -5 or HTTP-dates in the past are treated as 'retry now' (0 seconds) — not negative intervals which would underflow downstream countdown math."

key-files:
  created: []
  modified:
    - validationLedger/Core/Networking/NetworkError.swift
    - validationLedger/Core/Networking/APIClient.swift
    - validationLedgerTests/Networking/APIClientRateLimitTests.swift
    - validationLedgerTests/Networking/APIClientEndpointTests.swift

key-decisions:
  - "Transport-boundary placement for 429 parsing (NOT a ResponseInterceptor): per RESEARCH §iOS API #4, rate-limit is a typed-error fold with zero side effects — belongs at the same line that throws httpError today. Auth401ResponseInterceptor (Plan 07) stays a ResponseInterceptor because logout IS a side effect. Pattern: folds live at transport boundary; side-effecting reactions live in interceptors."
  - "parseRetryAfter as a static extension method (not an instance method or free function): (a) static keeps it testable without constructing an APIClient, (b) extension scope keeps it co-located with the 429 detection call site, (c) the `now: Date = .now` default parameter provides test-determinism for HTTP-date assertions without needing an injected clock protocol."
  - "Default fallback of 60 seconds when Retry-After is missing OR malformed. Rationale: OTPViewModel needs SOME countdown value to show the user; 60s matches the otp-verify-rate-limited.json fixture body (which has `retry_after_seconds: 60`) and the Phase 2 AUTH-02 VALIDATION.md documented expectation. Not a server-policy override — the server's authoritative value is always used when present; 60s is only the defensive fallback."
  - "Phase 2 APIClientEndpointTests.otpRequestFailure contract update: the pre-Plan-05 assertion was `httpError(429)`. Plan 05's core contract change is 429→rateLimited (not httpError). The test had to update to match — this is the plan's explicit intent, not a regression. Documented in the GREEN commit body + the deviation below."
  - "Destination substitution (same as Plans 01-04): iPhone 17 Pro / iOS 26.4 because the plan-specified iPhone 15 / iOS 17.5 runtime is not installed. Project deployment target is iOS 17.0 — any iOS 17+ simulator is equivalent for verification. Documented as Deviation 2 below (Rule 3 blocking env correction)."
  - "Pattern syntax fix in test 4: `catch let NetworkError.rateLimited(_)` was syntactically invalid (`let` with only `_` binds nothing). Rewrote as `catch NetworkError.rateLimited` which pattern-matches the case without binding the associated value. Compile fix, not a behavior change."

patterns-established:
  - "Transport-boundary typed-error fold vs. side-effecting ResponseInterceptor decision rule: if the response handling produces a typed error and nothing else, fold inside APIClient.request<E>. If it triggers an external side effect (logout, UI navigation, telemetry), use a ResponseInterceptor. Plan 05's 429 fold + Plan 07's Auth401 interceptor together establish the two sides of this split."
  - "Optional `now: Date = .now` parameter pattern for pure-function time injection: avoids the weight of a Clock protocol when the only test-determinism need is a fixed reference point. Applied to parseRetryAfter; same pattern viable for any time-sensitive pure function."

requirements-completed:
  - AUTH-02

# Metrics
duration: 5min
completed: 2026-04-21
---

# Phase 03 Plan 05: APIClient 429 + Retry-After Parsing Summary

**Typed `NetworkError.rateLimited(retryAfter:)` case + `APIClient.parseRetryAfter` (RFC 7231) + 429 detection branch at the transport boundary landed. 4 new green tests + 1 Phase 2 contract-update test + 0 regressions across APIClientEndpointTests / RetryInterceptorTests (27/27 across 3 suites pass).**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-21 20:18:00Z (RED test commit f631907)
- **Completed:** 2026-04-21 20:24:00Z (GREEN commit 8aa8723)
- **Tasks:** 1 / 1 (TDD: split RED + GREEN = 2 commits)
- **Files modified:** 4 (2 source + 2 test — 1 Wave 0 stub filled, 1 Phase 2 test contract-updated)
- **Files created:** 0

## Accomplishments

- **`NetworkError.rateLimited(retryAfter: TimeInterval)` case added.** Placed after `baseURLMissing` in the existing enum. Doc comment references D-02 and AUTH-02 and explains the countdown consumer pattern (OTPViewModel Plan 09).
- **APIClient 429 detection branch.** Inserted BEFORE the existing `guard (200...299).contains(response.statusCode)` check inside `request<E>`. 429 responses now throw `NetworkError.rateLimited(retryAfter:)` with the parsed `Retry-After` value (or 60s fallback). 4xx/5xx non-429 responses continue to throw `NetworkError.httpError` unchanged.
- **`APIClient.parseRetryAfter(from:now:)` static extension method.** RFC 7231 compliant — handles both delta-seconds (integer) and HTTP-date (RFC-1123 GMT) formats. Returns nil on missing/malformed headers; returns `max(0, ...)` clamped values on negative / past-date inputs (T-03-05-03 mitigation). The `now: Date = .now` default parameter enables deterministic HTTP-date testing.
- **4 new tests in APIClientRateLimitTests (Wave 0 stub filled).** All pass green on iPhone 17 Pro / iOS 26.4 simulator.
- **Phase 2 APIClientEndpointTests.otpRequestFailure updated.** The Phase 2 baseline asserted `httpError(429)`; Plan 05's transport-boundary fold changes that contract to `rateLimited`. Test rewritten to match the new contract; default-fallback 60s applies because `registerFixture` doesn't inject `Retry-After`.
- **Zero regression.** Full 3-suite run (APIClientRateLimitTests + APIClientEndpointTests + RetryInterceptorTests) green: 27/27 pass in 0.125s.

## Task Commits

Each phase followed TDD with atomic RED → GREEN commits (worktree mode, `--no-verify` per parallel-execution policy):

| Commit | Type | Subject |
|--------|------|---------|
| `f631907` | test | add failing tests for 429 + Retry-After parsing (AUTH-02, D-02) |
| `8aa8723` | feat | parse 429 + Retry-After into NetworkError.rateLimited (AUTH-02, D-02) |

**Plan metadata commit:** pending (appended with SUMMARY.md by orchestrator).

## Files Modified (4)

### Source (2)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/Networking/NetworkError.swift` | +1 `case rateLimited(retryAfter: TimeInterval)` + doc comment | +7 |
| `validationLedger/Core/Networking/APIClient.swift` | +429 detection branch (BEFORE the httpError guard) + `parseRetryAfter(from:now:)` static extension method (RFC 7231: delta-seconds + HTTP-date) | +44 |

### Test (2)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedgerTests/Networking/APIClientRateLimitTests.swift` | Wave 0 stub filled with 4 real @Tests: rateLimitedDeltaSeconds, rateLimitedDefaultFallback, parseRetryAfterHttpDate, non429StillHttpError; plus `makeAPIClient()` helper mirroring APIClientEndpointTests.makeClient() shape | +140 / -7 |
| `validationLedgerTests/Networking/APIClientEndpointTests.swift` | Phase 2 test `otpRequestFailure` rewritten: 429 now expected to throw `NetworkError.rateLimited(retryAfter: 60)` (default fallback), not `httpError(429)` — Plan 05 contract change | +22 / -10 |

## Test Results

**APIClientRateLimitTests — 4 passed (all new, filled from Wave 0 stub):**

```
✔ 429 + Retry-After: 60 (delta-seconds) → NetworkError.rateLimited(retryAfter: 60)
✔ 429 + NO Retry-After header → NetworkError.rateLimited(retryAfter: 60) (default fallback)
✔ parseRetryAfter handles HTTP-date format (RFC-1123 GMT)
✔ Non-429 5xx still throws httpError (no regression)
```

**APIClientEndpointTests — 14 passed (13 untouched + 1 contract-updated):**

The `otpRequestFailure` test now asserts `NetworkError.rateLimited(retryAfter: 60)` — matches the Plan 05 contract. The other 13 tests (7 success-fixture decodes + 6 non-429 failure-fixture `httpError` asserts across Device/KYC endpoints) are unchanged and still pass.

**RetryInterceptorTests — 9 passed (Phase 2 baseline; no regression):**

All 9 retry/backoff tests unchanged. RetryInterceptor is GET-only; Plan 05's change affects only the 429 code path which is unrelated to retry mechanics for this plan's scope.

**Combined run:** `** TEST SUCCEEDED **` — 27 tests in 3 suites, 0.125s total (iPhone 17 Pro / iOS 26.4 simulator, `-parallel-testing-enabled NO`).

## Decisions Made

- **Transport-boundary placement for 429 parsing** (NOT a ResponseInterceptor). Per RESEARCH §iOS API #4: rate-limit is a typed-error fold with zero side effects — belongs at the same line that throws httpError today. Auth401ResponseInterceptor (Plan 07) stays a ResponseInterceptor because logout IS a side effect. The contrast establishes a two-sided split rule: folds live at transport boundary; side-effecting reactions live in interceptors.
- **`parseRetryAfter` as a static extension method** on APIClient (not an instance method, not a free function). Static keeps it testable without constructing an APIClient; extension scope keeps it co-located with the 429 call site; `now: Date = .now` default parameter gives test determinism without introducing a Clock protocol.
- **Default fallback of 60 seconds** when Retry-After is missing OR unparseable. Matches the plan's must_haves (`APIClient defaults to 60 seconds when Retry-After header is absent or malformed`), the fixture body (`retry_after_seconds: 60`), and Phase 2 AUTH-02 VALIDATION documentation. The server's authoritative value is always used when present; 60s is only the defensive fallback.
- **Phase 2 APIClientEndpointTests.otpRequestFailure contract update.** The Phase 2 baseline asserted `httpError(429)`; the ENTIRE purpose of Plan 05 is to change 429 from `httpError` to `rateLimited`. Updating the test to match is NOT a regression — it IS the plan's intent. Documented in the GREEN commit body and Deviation 1 below.
- **`catch NetworkError.rateLimited` instead of `catch let NetworkError.rateLimited(_)`.** The `let` with only `_` binds nothing — emits a warning ("let pattern has no effect"). Clean syntax is `catch NetworkError.rateLimited` when you don't need the associated value. Compile fix, not a behavior change.
- **Destination substitution (same as Plans 01-04):** iPhone 17 Pro / iOS 26.4 because plan-specified iPhone 15 / iOS 17.5 runtime is not installed in this environment; project deployment target is iOS 17.0 so any iOS 17+ destination is equivalent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug / planned test update] APIClientEndpointTests.otpRequestFailure asserted the pre-Plan-05 contract (`httpError(429)`); updated to assert the new contract (`rateLimited(retryAfter: 60)`)**

- **Found during:** GREEN regression check — `xcodebuild test -only-testing:...APIClientEndpointTests` failed because `otpRequestFailure` recorded an issue: "Expected NetworkError.httpError but got rateLimited(retryAfter: 60.0)".
- **Issue:** The Phase 2 test exercised a 429 response path and asserted `NetworkError.httpError(statusCode: 429, data: ...)`. Plan 05's core contract change is 429 → `NetworkError.rateLimited(retryAfter:)` — so the Phase 2 assertion is now incorrect by design. Without updating the test, GREEN cannot hold.
- **Fix:** Rewrote the test body to assert `catch let NetworkError.rateLimited(retryAfter)` with `#expect(retryAfter == 60)`. The registerFixture call doesn't set a Retry-After header, so the 60s default-fallback applies. Renamed the test display name to reflect the new contract (`throws NetworkError.rateLimited (Phase 3 Plan 05 contract)`).
- **Files modified:** `validationLedgerTests/Networking/APIClientEndpointTests.swift` (diff +22 / -10).
- **Verification:** Re-run shows 14/14 APIClientEndpointTests pass + 9/9 RetryInterceptorTests + 4/4 APIClientRateLimitTests = 27/27 across 3 suites.
- **Committed in:** 8aa8723 (GREEN — same commit as the contract change).
- **Rationale:** This is a Rule 1 auto-fix (broken test assertion due to an intentional contract change), not a regression. Analogous to Plan 02's `signSize` test rewrite in the RED phase: when the new source behavior invalidates an existing test's assumption, the test updates alongside the source. The plan's own `action` Step D No-regression guidance says "The 429 detection happens BEFORE the `(200...299)` guard" — meaning any test that asserted `httpError(429)` before this plan is, by plan definition, exercising the old contract and must update.

**2. [Rule 3 — Blocking env correction, same as Plans 01-04] Substituted `iPhone 17 Pro / iOS 26.4` for plan-specified `iPhone 15 / iOS 17.5` destination**

- **Found during:** RED build verification (`xcodebuild build-for-testing` step).
- **Issue:** `xcrun simctl list devices available` shows no iPhone 15 / iOS 17.5 runtime. Available: iOS 15.2, 18.0–18.4, 26.2, 26.4. Project Xcode SDK is 26.4 per CLAUDE.md; deployment target is iOS 17.0 per project.pbxproj.
- **Fix:** All `xcodebuild build-for-testing` / `test` invocations used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`. iOS 17.0 deployment target makes any iOS 17+ simulator equivalent for verification.
- **Files modified:** None (CLI only).
- **Verification:** `** TEST SUCCEEDED **` on all runs.
- **Committed in:** N/A — test-run CLI only.

**3. [Rule 1 — Syntactic bug in test pattern] `catch let NetworkError.rateLimited(_)` rewritten to `catch NetworkError.rateLimited`**

- **Found during:** RED build verification — Swift compiler warning: "'let' pattern has no effect; sub-pattern didn't bind any variables" on test 4 (`non429StillHttpError`).
- **Issue:** `catch let NetworkError.rateLimited(_)` is syntactically ambiguous: `let` requires a variable binding; `(_)` binds nothing. The warning would have been an error under strict mode. The intent was "match the rateLimited case; don't care about the value" — clean syntax for that is `catch NetworkError.rateLimited` (the `catch` clause pattern-matches without binding).
- **Fix:** Rewrote the single catch arm on line 143 to `catch NetworkError.rateLimited { Issue.record(...) }`.
- **Files modified:** `validationLedgerTests/Networking/APIClientRateLimitTests.swift` (1 line; done in the RED commit).
- **Verification:** Warning cleared; test 4 compiles + runs green.
- **Committed in:** f631907 (RED — same commit as the initial test authoring; fix applied before the RED commit landed).

---

**Total deviations:** 3 auto-fixed (1 intentional contract-update to keep tests in sync with plan intent; 1 blocking env correction; 1 test syntax fix).
**Impact on plan:** No scope change. All `success_criteria`, all `must_haves.truths`, and all `must_haves.artifacts` `contains` patterns satisfied as written. Deviation 1 is called for by the plan's own contract change — not a surprise.

## TDD Gate Compliance

Plan frontmatter does not carry `type: tdd`, but the single task has `tdd="true"`. Gate sequence:

| Task | RED commit | GREEN commit | RED confirmation |
|------|-----------|--------------|-------------------|
| 1 (429 + Retry-After) | `f631907` (test) | `8aa8723` (feat) | Expected RED errors confirmed: `type 'NetworkError' has no member 'rateLimited'` (×3 sites) + `type 'APIClient' has no member 'parseRetryAfter'` in the HTTP-date test. |

RED commit precedes GREEN commit; `git log --oneline` verifies chronological order. No TDD gate violations.

## Known Stubs

**None introduced by this plan.** Plan 01's Wave 0 stub `APIClientRateLimitTests.swift` is now filled with 4 real `@Test`s — removed from the pending-stub ledger. The 10 other Wave 0 stubs remain intact and traceable to their owning plans per Plan 01's Stub-to-Plan Mapping table.

## Threat Flags

Per plan `<threat_model>`: 4 threats — T-03-05-01 (spoofing / OTP brute force) mitigated via the typed `rateLimited` surface; T-03-05-02 (absurdly high Retry-After) accepted as server policy; T-03-05-03 (malformed / tampered Retry-After) mitigated via `max(0, ...)` clamp + default fallback; T-03-05-04 (error body PII disclosure) accepted (NetworkError.rateLimited carries only a TimeInterval, no body).

| Threat ID | Component | Mitigation landed? | Evidence |
|-----------|-----------|---------------------|----------|
| T-03-05-01 Spoofing / OTP brute force | /auth/otp/verify | YES | `NetworkError.rateLimited(retryAfter:)` surfaces backend-authoritative countdown; OTPViewModel (Plan 09) consumes the typed case. iOS does NOT count locally (D-02). `rateLimitedDeltaSeconds` test proves round-trip through MockURLProtocol + fixture. |
| T-03-05-02 Absurdly high Retry-After | parseRetryAfter | ACCEPTED | No client-side cap on Retry-After; server policy is authoritative. M2+ may add UX warning for >1h countdowns (non-blocking). |
| T-03-05-03 Tampered Retry-After (negative / garbage) | parseRetryAfter | YES | `TimeInterval(raw)` returns nil for non-numeric → default 60s fallback; `max(0, seconds)` clamps negative; `max(0, date.timeIntervalSince(now))` clamps past-dates. `rateLimitedDefaultFallback` test covers missing-header case. |
| T-03-05-04 Error body PII disclosure | NetworkError.rateLimited | ACCEPTED | NetworkError.rateLimited carries only a TimeInterval (no body). Fixture body has no PII. PIIScrubber (Phase 1) scrubs any future log statements. No body is surfaced to callers. |

**No new threat surface introduced.** Changes are: (a) adding a typed error case (reduces attack surface — callers can't accidentally treat 429 as a decode success); (b) adding a header parser (read-only, defensive against tampering); (c) updating a Phase 2 test to match the new contract. No new network endpoints, no file access, no schema change. No threat flags.

## Issues Encountered

- **Phase 2 test `otpRequestFailure` invalidated by the plan's contract change.** Expected — the ENTIRE point of Plan 05 is to change the 429 contract from `httpError` to `rateLimited`. Test was updated to match. Documented in Deviation 1 above.
- **`catch let NetworkError.rateLimited(_)` pattern syntax.** Swift's `let ... (_)` pattern binds nothing, so it emits a "let pattern has no effect" warning. Fixed inline to `catch NetworkError.rateLimited` (pattern-match without binding). Documented in Deviation 3.
- **Parallel-testing flakes on the full simulator suite** (pre-existing per WR-01 / Plan 04 observations). Not exercised here — ran Plan 05 verification with `-parallel-testing-enabled NO` matching the ci-simulator.yml config.

## User Setup Required

None. No external services, no secrets, no dashboard changes. All work is source + test edits verifiable via `xcodebuild test`.

## Next Wave Readiness

- **Plan 09 (OTPViewModel D-27 7-step orchestration)** can now pattern-match `catch NetworkError.rateLimited(let retryAfter)` to drive the 1-Hz Verify-button-disable countdown. The typed error surface is the ONLY path from transport to view-model for rate-limit state — no raw status codes, no raw headers leak to the ViewModel.
- **Plan 07 (Auth401ResponseInterceptor / LogoutService / SensitiveActionService)** is unaffected — 401 and 429 are orthogonal paths. Plan 07's interceptor registers alongside RetryInterceptor in `AppContainer.makeSession`; the `wrapped` composition in APIClient still sees 429 at the response boundary BEFORE any interceptor would observe it (429 detection is inline in `request<E>`, not in a ResponseInterceptor — see Key Decision #1).
- **Plan 06 (SessionRestoreService + BiometricService)** unaffected — no rate-limit handling in its scope; the typed error contract doesn't touch SESS-01..04.
- **M2+ endpoints that rate-limit** (tender/accept, KYC upload, assistant calls) automatically inherit the typed `rateLimited` surface — no per-endpoint rate-limit handling needed. The fold happens uniformly inside `APIClient.request<E>`.
- **Downstream verifier should check:** the 4 plan `<verify>.automated` grep assertions pass (`case rateLimited(retryAfter: TimeInterval)` in NetworkError.swift; `Retry-After` in APIClient.swift; `rateLimited(retryAfter:` in APIClient.swift; `parseRetryAfter` in APIClient.swift). Confirmed locally; all 4 green.

## Self-Check

Files claimed modified:

- `validationLedger/Core/Networking/NetworkError.swift` — FOUND (diff +7 lines; `case rateLimited(retryAfter: TimeInterval)` present after `case baseURLMissing`)
- `validationLedger/Core/Networking/APIClient.swift` — FOUND (diff +44 lines; 429 detection branch before `guard (200...299)`; `parseRetryAfter(from:now:)` extension at bottom)
- `validationLedgerTests/Networking/APIClientRateLimitTests.swift` — FOUND (diff +140 / -7; Wave 0 placeholder replaced with 4 real `@Test`s + `makeAPIClient()` helper)
- `validationLedgerTests/Networking/APIClientEndpointTests.swift` — FOUND (diff +22 / -10; `otpRequestFailure` rewritten to assert `rateLimited(retryAfter: 60)`)

Commits claimed made:

- `f631907` (RED — failing tests for 429 + Retry-After) — FOUND in git log
- `8aa8723` (GREEN — parse 429 + Retry-After, update Phase 2 test) — FOUND in git log

Plan `<verify>.automated` grep acceptance checks:

| # | Check | Result |
|---|-------|--------|
| 1 | `case rateLimited(retryAfter: TimeInterval)` in NetworkError.swift | PASS |
| 2 | `Retry-After` in APIClient.swift | PASS |
| 3 | `rateLimited(retryAfter:` in APIClient.swift | PASS |
| 4 | `parseRetryAfter` in APIClient.swift | PASS |
| 5 | `xcodebuild test -only-testing:...APIClientRateLimitTests -only-testing:...APIClientEndpointTests` | PASS (14 + 4 = 18 tests; 27 across 3 suites when RetryInterceptorTests included) |

Plan `<success_criteria>` block — all 5 criteria:

- [x] `NetworkError.rateLimited(retryAfter:)` case present
- [x] APIClient parses 429 + Retry-After at the response boundary (BEFORE httpError throw)
- [x] `parseRetryAfter` handles both delta-seconds and HTTP-date forms; defaults to 60 on missing/malformed
- [x] 4 tests in APIClientRateLimitTests pass
- [x] No regression in Phase 2 APIClientEndpointTests / RetryInterceptorTests (1 test contract-updated, 22 others unchanged and green)

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
