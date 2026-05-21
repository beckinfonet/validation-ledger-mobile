# Phase 10 — Deferred Items

## Out-of-scope test failures observed during Plan 10-08

### AppContainerLoadEndpointsConfigSwapTests — pre-existing failures on wave base (7284d40)

Both **`mockConfigEndToEndSwap`** and **`mockConfigEndToEndDecode`** in `validationLedgerTests/App/AppContainerNetworkConfigTests.swift` (suite `AppContainerLoadEndpointsConfigSwapTests` at lines 156-300+) fail with **`httpError(statusCode: 404, data: 0 bytes)`**.

- Verified failures pre-exist on the wave-base commit `7284d40a27c8e53e48ed015993303c66f1e6340f` (Plan 10-08 was reset to that base, tests run in isolation — same 2/3 failures).
- Discovery point: post-Task-1 plan-verification run (Plan 10-08).
- Affected tests:
  - `loadEndpointsConfigSwap: with .mock config + load-fixture registry, the 3 Load endpoints flow through apiClient.request<E> end-to-end` (line 182)
  - `loadEndpointsConfigSwap: .mock pipeline decodes each endpoint's Response into the correct typed value (registry → MockURLProtocol → APIClient → Decodable)` (line 265)
- Likely cause (NOT investigated — out of scope): the WR-01 process-lifetime guard `hasRegisteredAppDefaults` in `MockLoadFixtureRegistry` interacts poorly with these tests' `MockURLProtocol.reset()` call BEFORE `AppContainer.init` — if the guard is already `true` from an earlier test, the in-Container call is a no-op and the handler array stays empty after reset. The fix is the same `resetForTestOnly()` seam Plan 10-08 added (used by `MockLoadFixtureRegistryActionToggleTests`); applying it to `AppContainerLoadEndpointsConfigSwapTests.resetMockURLProtocol()` would close the failure.
- Plan 10-08 does NOT touch this file. Recommended ownership: a follow-up to Plan 07-06 (or a Phase 11 housekeeping item).
- Plan 10-08's own 16 new tests + adjacent suites (`IdempotencyInterceptorTests`, `LoadDetailViewModelTests`, `LoadDetailViewModelActionTests`, `AppContainerNetworkConfigTests` (NET-03 suite, NOT the SC #5 suite)) all pass cleanly with Plan 10-08's changes applied.
