# Phase 2: Deferred Items

Out-of-scope issues discovered during plan execution. These are tracked here, not fixed,
so they don't bleed into unrelated commits.

## Phase 2 Plan 02 (2026-04-21)

### Pre-existing warning: LogField main-actor-isolated Hashable conformance

**File:** `validationLedger/Core/Logging/Logger.swift`

**Warning text:**
```
main actor-isolated conformance of 'LogField' to 'Hashable' cannot be used in
nonisolated context; this is an error in the Swift 6 language mode
```

**Lines:** 32, 34, 36, 38, 40 (5 occurrences)

**Root cause:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the Xcode project.
`LogField` is used in a nonisolated context but its Hashable conformance is
main-actor-isolated by the default. Same pattern that required `nonisolated` on the
endpoint structs in this plan.

**Fix (for a future Core/Logging cleanup plan):** Mark `LogField` as `nonisolated`
(or annotate its conformance accordingly).

**Out of scope here because:** Plan 02's scope boundary is
`Core/Networking/{APIEndpoint, APIClient, Endpoints/*}.swift`. `Core/Logging/Logger.swift`
was not modified by this plan — the warnings pre-date Plan 02 and will not block the
build (they are warnings in Swift 5 mode, errors only in Swift 6 mode, and the project
is on Swift 5.0 per `SWIFT_VERSION = 5.0`).

## 2026-04-21 — Plan 06 executor

**Pre-existing failing test (OUT OF SCOPE for Plan 06):**
- `validationLedgerTests/Networking/APIClientEndpointTests.swift:49` — "OTPRequestEndpoint: success fixture decodes into typed Response" fails with `.httpError(statusCode: 404)`
- Introduced in commit `526e29b` (Plan 02-03)
- NOT caused by Plan 06 changes (KeyStore/Identity work)
- Flagged for Plan 03/04 re-visit (fixture path resolution in parallel-executor handler registry)
