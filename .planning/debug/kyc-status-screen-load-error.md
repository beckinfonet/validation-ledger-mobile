---
status: investigating
trigger: "After submitting a KYC package, the KYC status screen renders an error state (\"Couldn't load status\") instead of a verdict state (Pending / Under Review / Verified / Rejected)."
created: 2026-05-17T00:00:00Z
updated: 2026-05-17T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — MockDefaultFixtures.dispatchHandler has no ("GET", "/kyc/status") case, so the DEBUG-device organic walkthrough 404s the status fetch.
test: Traced the full chain from MockDefaultFixtures.dispatchHandler -> MockURLProtocol 404 -> APIClient.request -> KYCStatusViewModel.fetchStatus catch -> .error state.
expecting: Confirmed at every link.
next_action: Diagnosis complete — return ROOT CAUSE FOUND. Do not fix (find_root_cause_only).

## Symptoms

expected: After KYC submission the status screen renders the verdict — Pending / Under Review / Verified / Rejected. A Rejected state shows plain-language rejection-reason copy (never raw backend codes) and lets the user re-capture only the rejected artifacts. Pull-to-refresh re-fetches the latest status. (Test 9, KYC-05, D-09.)
actual: The status screen shows "Couldn't load status. We couldn't load your verification status. Pull down to try again." instead of any verdict state. Reproduced by a human tester on a physical iPhone on the M1 DEBUG build against the always-succeeds mock backend.
errors: None reported in console by the tester. Mock backend expected to return an under_review status for GET /kyc/status.
reproduction: Test 9 in .planning/phases/05-kyc-capture-upload-pipeline/05-UAT.md — submit a full 6-artifact KYC package, then observe the KYC status screen.
started: Discovered during Phase 05 UAT (2026-05-17).

## Eliminated

## Evidence

- timestamp: 2026-05-17T00:00:00Z
  checked: MockDefaultFixtures.swift dispatchHandler switch (the DEBUG-only device-mock route registry).
  found: "The (method, path) switch handles POST /auth/otp/request, POST /auth/otp/verify, GET /device/challenge, POST /device/register, POST /device/heartbeat, POST /kyc/upload/init, POST /kyc/upload/chunk, POST /kyc/upload/commit, POST /kyc/submit. There is NO case for (\"GET\", \"/kyc/status\"). The default branch returns nil."
  implication: "On a DEBUG device build (networkConfig == .mock), GET /kyc/status falls through to the default branch and returns nil — no fixture serves the status endpoint."

- timestamp: 2026-05-17T00:00:00Z
  checked: MockURLProtocol.startLoading().
  found: "When no registered handler returns non-nil, startLoading() synthesizes an HTTP 404 response (statusCode 404, empty body) and finishes loading. This is by design — 'No handler matched — return 404 so tests fail loudly rather than hang.'"
  implication: "A missing /kyc/status route produces a 404 HTTP response, not a transport error and not a hang."

- timestamp: 2026-05-17T00:00:00Z
  checked: APIClient.request<E>() status-code handling (lines 61-73).
  found: "After 429 handling, `guard (200...299).contains(response.statusCode) else { throw NetworkError.httpError(statusCode:data:) }`. A 404 fails the guard and throws NetworkError.httpError(statusCode: 404, data: <empty>). Decoding is never reached, so this is NOT a decoding mismatch."
  implication: "GET /kyc/status throws NetworkError.httpError(404) before any JSON decode — the request fires and fails at the HTTP layer."

- timestamp: 2026-05-17T00:00:00Z
  checked: KYCStatusViewModel.fetchStatus() (lines 131-149) and KYCStatusViewController.viewWillAppear (line 138-143).
  found: "viewWillAppear runs `Task { await viewModel.fetchStatus() }` on every appearance. fetchStatus() does `try await apiClient.request(KYCStatusEndpoint())` inside do/catch; ANY thrown error is caught, logged via logger.error(event: 'kyc_status_fetch_failed'), and sets `state = .error(message: 'We couldn't load your verification status. Pull down to try again.')`."
  implication: "The thrown NetworkError.httpError(404) lands in the catch block and produces the .error state — the exact symptom. The error is logged through the app Logger (LogEvent 'kyc_status_fetch_failed'), which is why the tester saw no Xcode-console error: structured app logging is not necessarily visible as a console print, and a 404 is a normal HTTP response so URLSession itself logs nothing."

- timestamp: 2026-05-17T00:00:00Z
  checked: KYCStatusViewController.handle(state:) .error case (lines 304-315).
  found: ".error renders heading 'Couldn't load status' (kyc.status.error.title) + the body message from the VM. Verbatim match to the tester's report: 'Couldn't load status. We couldn't load your verification status. Pull down to try again.'"
  implication: "Symptom string is reproduced exactly by the .error path. No other state produces this copy."

- timestamp: 2026-05-17T00:00:00Z
  checked: KYCStatusViewModelTests.swift (registerStatusFixture) vs MockDefaultFixtures, plus the kyc-upload-capture-bugs precedent.
  found: "KYCStatusViewModelTests registers its OWN /kyc/status MockURLProtocol handler per test (registerStatusFixture / inline register{}). That is why the 31-test KYC simulator suite is GREEN despite this gap — tests never exercise MockDefaultFixtures. MockDefaultFixtures' own header comment documents that the Phase-5 KYC upload endpoints were ADDED in debug session kyc-upload-capture-bugs (Issue 2a) because they had been omitted — GET /kyc/status was overlooked in that same fix. The kyc-flow-device-audit.md audit marked KYCStatusViewController/ViewModel 'CLEAN' because it audited app code, not the mock route registry."
  implication: "Same omission class as kyc-upload-capture-bugs: a real backend endpoint the organic device walkthrough hits, never registered in the device-mock registry. Unit tests cannot catch it because they self-register fixtures."

## Resolution

root_cause: "MockDefaultFixtures.dispatchHandler — the DEBUG-only device-mock route registry used by an organic tap-through walkthrough (networkConfig == .mock) — has no case for (\"GET\", \"/kyc/status\"). When KYCStatusViewController.viewWillAppear triggers KYCStatusViewModel.fetchStatus(), the GET /kyc/status request falls through the dispatch switch's default branch (returns nil), MockURLProtocol.startLoading() synthesizes a 404, APIClient.request() throws NetworkError.httpError(statusCode: 404), and fetchStatus()'s catch block sets state = .error — which the VC renders as 'Couldn't load status'. It is a missing mock route, NOT a decoding mismatch and NOT a non-firing request. The KYC status app code (VM/VC/endpoint/decoder) is correct. This is the same omission class as the resolved kyc-upload-capture-bugs session, which added /kyc/upload/init|chunk|commit + /kyc/submit to this same registry but overlooked GET /kyc/status."
fix: "Diagnosis only (find_root_cause_only) — no fix applied. See Suggested Fix Direction in the returned diagnosis."
verification: "Not applicable — diagnosis only."
files_changed: []
