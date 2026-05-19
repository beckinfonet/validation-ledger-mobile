# Phase 4 — Deferred Items

Out-of-scope issues discovered during phase execution. Do not fix inline per the GSD scope-boundary rule.

---

## Pre-existing MockURLProtocol fixture leak / ordering failures (discovered in Plan 04-06)

**Discovered:** 2026-04-22, during Plan 04-06 Task 2 verification run
**Scope:** Pre-existing on the base commit (verified by running the same test set against the pre-task-2 tree — same failures). NOT caused by Plan 04-06 edits (AppContainer.swift attestation wiring + AppSession.swift).
**Affected suites (13 failures observed):**

- `MockURLProtocol — fixture registry + lock safety (WR-01)`
  - "first-match-wins when multiple handlers match overlapping paths"
  - "consecutive register/reset cycles leave no residual state"
- `APIClient — M1 endpoint contracts (NET-01 + NET-02)` — multiple endpoints get 404/500 instead of the expected fixture response
- `AppContainer — NET-03 network config swap` — `.mock` override + Idempotency-Key tests get 404
- `APIClient — 429 + Retry-After parsing (AUTH-02, D-02)` — 429 tests returning unexpected status
- `DeviceFingerprint — simulator installUUID persistence (DEV-05)` — Keychain `unexpectedStatus(-25300)` (itemNotFound) — likely Keychain residue between test runs

**Symptom:** Fixtures registered by a test are either (a) leaking into subsequent tests or (b) the registry is returning the wrong fixture for the path under test. The mismatch between expected 413/401 vs returned 404/500 strongly indicates fixture-ordering or registry-reset race.

**Why deferred:** The plan's scope is attestation wiring into AppContainer. Neither the MockURLProtocol infrastructure nor the affected endpoint tests were modified by Plan 04-06, and the failures reproduce at the base commit without any of Plan 04-06's changes applied. Fixing this would require touching `MockURLProtocol.swift` / the fixture registry / test-isolation harness, outside Plan 04-06's files_modified scope.

**Recommended follow-up:** Surface in Phase 4 verifier or open a standalone fix plan targeting the MockURLProtocol registry reset logic. The Phase 4 CI hardening (04-05) may naturally cover part of this since device-CI test-plan hardening is in scope, but the failure surface is simulator-side unit tests.

**Remediation NOT attempted** per GSD scope-boundary: "Only auto-fix issues DIRECTLY caused by the current task's changes."

---

## Wire real `/device/register` → `AppSession.trustTier` consumer (follow-up from Plan 04-08)

**Discovered:** 2026-04-22, during Plan 04-08 Task 3 execution
**Scope:** Cross-plan — OTPViewModel's D-27 step 5 calls `POST /device/register` but discards the
response (`_ = try await apiClient.request(DeviceRegisterEndpoint(...))`). The response contains
`trust_tier` per D-12, but no consumer writes it into `AppContainer.session.trustTier`. Plan 04-08
needed a way to exercise `.hardwareAttested` via XCUITest; added `AppContainer.uiTestTrustTierOverride`
(DEBUG-only) + `AppSession(trustTier:)` seed from it as a test seam.

**Why deferred:** The production consumer wiring is out-of-scope for 04-08 (the plan frontmatter says
"read trustTier at role-shell construction time" — it's a passive reader, not the producer). The
producer wiring requires changes to `OTPViewModel.verify()` step 5 (capture `resp.trustTier`) +
persist it through `AppContainer.session.trustTier = resp.trustTier`. That's a separate behaviour-change
plan, likely Phase 4.1 or Phase 5.

**User decision:** 2026-04-22 — "Accept, but add follow-up to wire real response consumer." Accepted
the DEBUG-only seam with this explicit follow-up commitment.

**Recommended follow-up:** Open a small plan (Phase 4.1 or Phase 5 kickoff) that:
1. Extends `DeviceRegisterEndpoint.Response` to include `trustTier: TrustTier` (if not already present).
2. Modifies `OTPViewModel.verify()` step 5 to capture the response and write `container.session.trustTier`
   on the main actor.
3. Adds a similar consumer in SceneDelegate's Plan 04-07 heartbeat helper (which already writes
   `container.session.trustTier = heartbeatResponse.trustTier` — verify this is already landed).
4. Marks `AppContainer.uiTestTrustTierOverride` as deprecated or keeps it only for UI-test determinism.

**Current seam behaviour (DO NOT DELETE PREMATURELY):**
- `AppContainer.swift` — DEBUG-only static `uiTestTrustTierOverride: TrustTier?`
- `SceneDelegate.swift` — parses `-MockOTPTrustTierForUITest {softwareOnly|hardwareAttested}` launch arg
  and sets the override before constructing AppContainer
- `AppSession(trustTier:)` — seeded from override OR from `.softwareOnly` default in DEBUG+mock+no-UITest-arg
  mode (Plan 04-11)

Removing the seam before the real producer lands would break Plan 04-08's LimitedTrustBannerTests.

