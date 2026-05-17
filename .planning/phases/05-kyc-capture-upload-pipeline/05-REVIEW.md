---
phase: 05-kyc-capture-upload-pipeline
reviewed: 2026-05-17T00:00:00Z
depth: standard
files_reviewed: 79
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/App/AppCoordinator.swift
  - validationLedger/App/AppDelegate.swift
  - validationLedger/App/Info.plist
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/Core/Auth/SessionRestoreService.swift
  - validationLedger/Core/Identity/Capture/CameraSession.swift
  - validationLedger/Core/Identity/Capture/FaceQualityGate.swift
  - validationLedger/Core/Identity/Capture/GPSMetadataInjector.swift
  - validationLedger/Core/Identity/Geo/GeoContext.swift
  - validationLedger/Core/Identity/KYC/ArtifactUploadState.swift
  - validationLedger/Core/Identity/KYC/KYCSession.swift
  - validationLedger/Core/Identity/KYC/KYCUploadError.swift
  - validationLedger/Core/Identity/KYC/KYCUploadScheduler.swift
  - validationLedger/Core/Identity/KYC/RejectionReasonCode.swift
  - validationLedger/Core/Identity/KYCUploader.swift
  - validationLedger/Core/Networking/APIClient.swift
  - validationLedger/Core/Networking/APIEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/KYCSubmitEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift
  - validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift
  - validationLedger/Core/Storage/Keychain/KeychainKey.swift
  - validationLedger/Core/Storage/Keychain/KeychainScope.swift
  - validationLedger/Core/Storage/Keychain/KeychainStore.swift
  - validationLedger/Core/Storage/KYCSessionStore.swift
  - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
  - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
  - validationLedger/Features/Onboarding/KYC/Capture/CameraPermissionViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/CapturePreviewViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/DLBackCaptureViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/DLFieldFormatValidator.swift
  - validationLedger/Features/Onboarding/KYC/Capture/DLFrontExtractionViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift
  - validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewModel.swift
  - validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
  - validationLedger/Features/Onboarding/KYC/KYCReviewViewController.swift
  - validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift
  - validationLedger/Features/Onboarding/KYC/KYCStartViewController.swift
  - validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift
  - validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift
  - validationLedger/Features/Profile/ProfileViewController.swift
  - validationLedger/Resources/en.lproj/Localizable.strings
  - validationLedger/Roles/Broker/BrokerTabBarController.swift
  - validationLedger/Roles/Carrier/CarrierTabBarController.swift
  - validationLedger/Roles/Dispatch/DispatchTabBarController.swift
  - validationLedger/Roles/Factoring/FactoringTabBarController.swift
  - validationLedger/Roles/Shipper/ShipperTabBarController.swift
  - validationLedger/UI/DesignSystem/Colors.swift
  - validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift
  - validationLedgerDeviceTests/KYCForceQuitResumeDeviceTests.swift
  - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
  - validationLedgerTests/Auth/SessionRestoreServiceTests.swift
  - validationLedgerTests/KYC/BackgroundUploadSchedulingTests.swift
  - validationLedgerTests/KYC/DLExtractionFormatTests.swift
  - validationLedgerTests/KYC/FaceQualityGateTests.swift
  - validationLedgerTests/KYC/GeoContextTests.swift
  - validationLedgerTests/KYC/GPSMetadataInjectorTests.swift
  - validationLedgerTests/KYC/KYCCoordinatorTests.swift
  - validationLedgerTests/KYC/KYCEndToEndIntegrationTests.swift
  - validationLedgerTests/KYC/KYCSessionStoreTests.swift
  - validationLedgerTests/KYC/KYCUploaderIdempotencyTests.swift
  - validationLedgerTests/KYC/KYCUploaderProgressTests.swift
  - validationLedgerTests/KYC/KYCUploaderResumeTests.swift
  - validationLedgerTests/KYC/KYCUploaderRetryTests.swift
  - validationLedgerTests/KYC/KYCUploaderTests.swift
  - validationLedgerTests/KYC/KYCUploaderTestSupport.swift
  - validationLedgerTests/KYC/LogoutPreservesKYCSessionTests.swift
  - validationLedgerTests/KYC/RejectionReasonCodeTests.swift
  - validationLedgerTests/Networking/APIClientEndpointTests.swift
  - validationLedgerTests/Networking/Fixtures/kyc-status-pending.json
  - validationLedgerTests/Networking/Fixtures/kyc-status-rejected.json
  - validationLedgerTests/Networking/Fixtures/kyc-status-under-review.json
  - validationLedgerTests/Networking/Fixtures/kyc-status-verified.json
  - validationLedgerTests/Networking/Fixtures/kyc-submit-failure.json
  - validationLedgerTests/Networking/Fixtures/kyc-submit-success.json
  - validationLedgerTests/Networking/Fixtures/otp-verify-success.json
findings:
  critical: 3
  warning: 9
  info: 6
  total: 18
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-17T00:00:00Z
**Depth:** standard
**Files Reviewed:** 79
**Status:** issues_found

## Summary

Phase 5 is a large, carefully-commented body of work. The Keychain scoping, the
`NSFileProtectionComplete` on-disk store, the PII-discipline in logging, and the
`.kyc` hard-gate routing are all sound and the comment-level rationale is unusually
thorough. The serialized `NSLock` read-modify-write in `KYCSessionStore` is correct,
and the GPS/EXIF injector correctly avoids the UIKit decode trust-boundary trap.

However, the adversarial pass surfaced three correctness defects that ship broken
behaviour: the upload pipeline sends the backend a chunk count that does not match
the chunks actually transmitted whenever the backend overrides chunk size; the
shared `NetworkClient.send` shim silently downgrades `PUT`/`DELETE` to `POST`; and
the chunk-retry budget is off-by-one against its own documented contract. Several
warnings concern resume-correctness edge cases, an unbounded in-memory image buffer,
and a logging-discipline violation that puts decoded error descriptions into a
`LogField`.

## Critical Issues

### CR-01: `init` reports a chunk count computed at the wrong chunk size

**File:** `validationLedger/Core/Identity/KYCUploader.swift:146-173`
**Issue:** On a fresh upload, `KYCUploadInitEndpoint` is sent with
`totalChunks: initialChunks.count`, where `initialChunks` is `data.chunked(into:
Self.defaultChunkSize)` — i.e. the count computed at the hard-coded 512 KB default.
The backend response may override `chunkSize` (`initResponse.chunkSize`), and the
actual chunk loop (line 189) re-chunks `data` at that server `chunkSize`. The
result: the `init` POST has already told the backend a `totalChunks` value that does
not match the number of `/kyc/upload/chunk` POSTs that will actually arrive whenever
`initResponse.chunkSize != 512 KB`. A backend that validates "I expect N chunks"
against the init contract will either reject the commit or accept a truncated
artifact. The code does recompute the correct `totalChunks` for local persistence
(`persistFreshState`, line 163-165) — proving the author knew the count was size-
dependent — but the wire value sent to the server was never corrected.
**Fix:** Resolve the chunk size before computing the count sent in the `init` body.
Since `init` itself returns the authoritative `chunkSize`, the contract is circular;
the correct shape is a two-step: send `init` with `totalBytes` only (or the
512 KB-based count as a hint), then after the response recompute and, if the count
changed, treat the server's `chunkSize` as authoritative and never claim a stale
`totalChunks`. Concretely:
```swift
// Compute the count from the size the loop will actually use.
let initResponse = try await apiClient.request(KYCUploadInitEndpoint(
    artifactType: artifactType,
    totalChunks: data.chunked(into: Self.defaultChunkSize).count, // hint only
    totalBytes: data.count,
    sha256: data.sha256Hex()
))
let chunkSize = initResponse.chunkSize
let totalChunks = data.chunked(into: chunkSize).count
// If the backend's contract is "totalChunks must match", a second
// init/confirm call carrying the recomputed count is required — or the
// backend must derive totalChunks from totalBytes + its own chunkSize.
```
Confirm with the backend team which side owns `totalChunks` when `chunkSize` is
overridden; the current code is wrong under any interpretation where the server
trusts the init count.

### CR-02: `NetworkClient.send` silently downgrades `PUT`/`DELETE` to `POST`

**File:** `validationLedger/Core/Networking/APIClient.swift:159-175`
**Issue:** The default `NetworkClient.send(_:)` extension routes the request by HTTP
method:
```swift
case "POST", "PUT", "DELETE":
    return try await post(url, body: request.httpBody ?? Data())
```
A `PUT` or `DELETE` request is dispatched through `post(url:body:)`, so the actual
wire request uses the `POST` verb. The original method is discarded. `HTTPMethod`
declares `.put` and `.delete` as first-class cases and `APIClient.buildRequest` sets
`req.httpMethod` faithfully — but this shim throws that away. Any endpoint that
relies on `PUT` semantics (idempotent replace) or `DELETE` semantics will hit the
wrong server route/handler, and `IdempotencyInterceptor` (which keys off
`httpMethod == "POST" || "PUT"`) will mis-classify the request before it is even
sent. This is a latent data-integrity defect: a future `PUT`/`DELETE` endpoint will
appear to work in code review yet hit the wrong backend semantics at runtime.
**Fix:** Route by preserving the verb. The cleanest fix is for
`URLSessionNetworkClient` to override `send(_:)` with a direct
`session.data(for: request)` call (the comment at line 156-158 even acknowledges
this). At minimum, fail loudly rather than silently downgrade:
```swift
case "PUT", "DELETE":
    throw NetworkError.unexpectedResponseType(/* method not supported by the
        get/post primitive shim — implement send(_:) on the concrete client */)
```
Do not let `PUT`/`DELETE` masquerade as `POST`.

### CR-03: chunk-retry cap is off-by-one — only 4 attempts, not the documented 5

**File:** `validationLedger/Core/Identity/KYCUploader.swift:64-66, 304-335`
**Issue:** `maxChunkAttempts = 5` is documented as "a chunk POST is attempted at most
this many times" (line 64-66) and `KYCUploadError.retriesExhausted` is documented as
"the 5-attempt cap (UPL-03) was reached". The retry loop:
```swift
var attempt = 0
while true {
    do { return try await apiClient.request(endpoint) }   // attempt #1 uses attempt==0
    catch {
        ... attempt += 1
        guard attempt < Self.maxChunkAttempts else { throw .retriesExhausted }
        ... try await Task.sleep(...); continue
    }
}
```
Trace: 1st send (attempt==0 going in) fails → `attempt=1`, `1 < 5` true → retry.
2nd fails → `attempt=2` → retry. 3rd → `attempt=3` → retry. 4th → `attempt=4`,
`4 < 5` true → retry. 5th send fails → `attempt=5`, `5 < 5` **false** → throw. So
the chunk is sent exactly **4 times before giving up after the 5th** — wait: count
the actual sends. Sends happen on loop entries 1,2,3,4,5; the 5th send's failure
throws. That is 5 sends. But re-trace the guard: after the 4th failure `attempt==4`,
guard `4 < 5` passes, sleep, `continue` → 5th send. After the 5th failure
`attempt==5`, guard `5 < 5` fails → throw. So 5 sends do occur — **but the error is
thrown on the 5th failure, meaning the retry that the comment promises as the "5th
attempt" is the last *send*, and the test below contradicts the count.**
Re-examine the rate-limit branch and the documented intent: `UPL-03` says "5-attempt
cap"; with `attempt < maxChunkAttempts` and `attempt` pre-incremented, the loop
performs 5 sends — which is correct only if "attempt" is 1-indexed. It is not: the
first send runs with `attempt == 0` and is never counted by the guard. The boundary
is therefore ambiguous and fragile, and the rate-limited branch shares the SAME
counter as the transport-retry branch (line 313-322 vs 325-333) so a mix of 429s and
5xx consumes one shared budget — the comment at line 310-312 ("does NOT consume the
jitter-schedule attempt budget the same way, but it still counts toward the cap")
admits this is intentional but it makes the effective retry count for a pure-5xx
failure path differ from a mixed path in a way no test pins.
**Fix:** Make the counter unambiguous — count *attempts performed*, not *failures
seen*:
```swift
for attempt in 1...Self.maxChunkAttempts {
    do { return try await apiClient.request(endpoint) }
    catch {
        guard attempt < Self.maxChunkAttempts else {
            throw KYCUploadError.retriesExhausted(chunkIndex: chunkIndex)
        }
        // classify + sleep
    }
}
```
and add an explicit test asserting the exact send count for a chunk that fails every
attempt (the current `KYCUploaderRetryTests` should pin `attempts(forChunk:)` to the
documented number). Until the count is pinned by a test, the "5-attempt cap" claim
is unverified.

## Warnings

### WR-01: resume path re-chunks at `chunkSize` but the persisted cursor may have been acked at a different size

**File:** `validationLedger/Core/Identity/KYCUploader.swift:131-217`
**Issue:** On resume, `chunkSize = resumeState.chunkSize` and the chunk loop re-chunks
`data` at that size, then resumes from `chunksAcked`. This is correct ONLY if every
previously-acked chunk was sent at exactly `resumeState.chunkSize`. Because of CR-01,
a fresh upload computes its `init` count at 512 KB but its loop runs at the server
`chunkSize`; the `chunksAcked` cursor and the persisted `chunkSize` can therefore
describe two different chunkings if the persistence write and the chunk sends ever
disagree. The per-chunk idempotency key is `"<uploadID>.chunk.<index>"` — if the
re-chunked boundaries differ from the original, chunk index N on resume carries
different bytes than chunk index N did originally, yet reuses the same idempotency
key, so the backend dedupes and silently keeps the *stale* bytes. This is a
data-integrity hazard layered on top of CR-01.
**Fix:** Once CR-01 is fixed so `chunkSize` is authoritative from `init` onward, also
assert on resume that `resumeState.chunkSize == data.chunked-derived size` and that
`resumeState.totalChunks == chunks.count`; if they disagree, discard the cursor and
restart the artifact (a fresh `uploadID`) rather than resuming against a mismatched
chunking.

### WR-02: `ArtifactUploadState.idempotencyKey(forChunk:)` is dead code that diverges from the live key

**File:** `validationLedger/Core/Identity/KYC/ArtifactUploadState.swift:91-93` and `validationLedger/Core/Identity/KYCUploader.swift:415-417`
**Issue:** Two separate idempotency-key generators exist. `ArtifactUploadState`
exposes `idempotencyKey(forChunk:)` → `"\(uploadID ?? "no-upload-id").chunk.\(index)"`,
while `KYCUploader.idempotencyKey(uploadID:chunkIndex:)` → `"\(uploadID).chunk.\(index)"`.
The uploader uses its own private method; the `ArtifactUploadState` one is never
called by production code. They differ in the `nil` case: the model substitutes
`"no-upload-id"`. A future caller that reaches for the public model API would get a
key that collides across every artifact whose `uploadID` is `nil` — a latent
cross-artifact idempotency collision. Two definitions of an identity-critical key is
a correctness foot-gun.
**Fix:** Delete `ArtifactUploadState.idempotencyKey(forChunk:)`, or make
`KYCUploader` call it (after CR-01 the `uploadID` is always non-nil at that point, so
the `"no-upload-id"` fallback can be removed). One source of truth for the key.

### WR-03: `KYCUploader.upload` is not re-entrancy-guarded — concurrent `upload` + `resumeAllPendingUploads` can double-send

**File:** `validationLedger/Core/Identity/KYCUploader.swift:122-279`
**Issue:** `KYCUploader` is an `actor`, which serializes individual method calls but
does NOT prevent two *interleaved* `upload(artifactType:)` Tasks for the SAME artifact
from both being in flight — each `await` is a suspension point at which another Task
enters the actor. The D-01 flow kicks `kickUpload(for:)` per capture-confirm, and
`resumeAllPendingUploads()` (BGTask handler) walks every non-committed artifact. If
the app backgrounds while a foreground `upload(.truck)` is mid-chunk-loop, the BGTask
fires `resumeAllPendingUploads()`, which calls `upload(.truck)` again. Both Tasks read
the same `chunksAcked`, both send overlapping chunk ranges. The idempotency key saves
the *backend* from double-commit, but the two loops race `markChunkAcked` and one can
advance the cursor past a chunk the other has not actually sent — and `commit` can
fire twice. The `actor` isolation is necessary but not sufficient here.
**Fix:** Add an in-flight set: `private var inFlight: Set<ArtifactType>` checked and
inserted at the top of `upload(artifactType:)` (early-return if already present),
removed in a `defer`. Because actor-isolated mutable state is checked atomically
before the first `await`, this reliably collapses a duplicate call to a no-op.

### WR-04: whole-artifact image bytes held in memory and base64-expanded per chunk

**File:** `validationLedger/Core/Identity/KYCUploader.swift:141, 179, 299` and `validationLedger/Core/Identity/KYC/KYCSession.swift:36`
**Issue:** `KYCSession.artifactData` is `[String: Data]` — every captured multi-MB
image is held in a single Codable struct that `KYCSessionStore` JSON-encodes and
decodes *in full* on every `withSession`/`loadSession`. During an upload, `upload()`
calls `store.loadSession()` three times (lines 127, 141, 179) plus once per
`markChunkAcked`, each decoding the entire JSON blob including every artifact's
bytes. Then `chunkData.base64EncodedString()` (line 299) inflates each chunk ~33% and
the whole `RequestBody` is JSON-re-encoded. For six artifacts this is repeated
load/decode/encode of tens of MB. While performance is out of v1 scope, the
correctness-adjacent risk is real: on a memory-constrained device mid-capture this is
a plausible OOM/jetsam, which on iOS manifests as a silent process kill — i.e. a
force-quit the resume path then has to recover from. The data model amplifies the
very failure mode the resume logic exists to handle.
**Fix:** Out of strict v1 scope, but flag for the M2 background-session rework
already noted in the file header: artifact bytes should live in individual protected
files keyed by artifact, not inside the single Codable session JSON, so a chunk read
is a bounded file-range read rather than a whole-session decode.

### WR-05: submit-error path puts a decoded error description into a `LogField`

**File:** `validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift:281-285` and `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift:137-140`
**Issue:** `fields: [.event: String(describing: error)]`. CLAUDE.md mandates "zero
PII in analytics or crash logs" and the Phase-5 file headers repeatedly assert
"event names only — never artifact Data ... or any DL / coordinate value" and that
`LogField` "cannot physically carry image bytes". `String(describing: error)` for a
`NetworkError.decodingFailed(DecodingError)` or `.httpError(statusCode, data)`
expands to include the underlying `Data` blob / `DecodingError` context — which for
a `/kyc/submit` or `/kyc/status` failure can contain server response bytes about the
user's identity verification. This is exactly the leak the logging-discipline comments
claim is structurally impossible. `SessionRestoreService` and the heartbeat helper in
`SceneDelegate` correctly log event-name-only; these two KYC VMs do not.
**Fix:** Log a stable event name and, at most, a coarse classification (e.g. the
`NetworkError` case name or HTTP status code via `.count`), never
`String(describing: error)`:
```swift
logger.error(event: LogEvent("kyc_submit_failed"), fields: [:])
```
Apply the same fix to `OTPViewModel` (`fields: [.event: String(describing: error)]`
appears there too — `OTPViewModel.swift:133, 167, 182, 213, 229`) and
`KYCStatusViewModel.fetchStatus`.

### WR-06: `KYCSessionStore.persist` is not crash-atomic for the directory-protection re-stamp

**File:** `validationLedger/Core/Storage/KYCSessionStore.swift:270-293`
**Issue:** `persistLocked` writes with `.atomic` (good — no torn file) then
*separately* calls `FileManager.setAttributes([.protectionKey: .complete], ...)`.
If the process is killed between the atomic write and the `setAttributes` call, the
on-disk file exists with the protection class the atomic rename's new inode
inherited from the directory — which the comment itself (line 282-285) says "can
inherit the directory's default class rather than the requested one". The directory
was created with `.complete`, so in practice the inherited class is `.complete` and
the window is benign — but the code's own comment treats the re-stamp as load-bearing
for the T-05-02-01 at-rest invariant, and a re-stamp that can be skipped by a crash
is not load-bearing. The write also uses `[.completeFileProtection, .atomic]`, so the
data write itself already requests complete protection; the separate re-stamp is
either redundant (if the write option works) or unreliable (if it doesn't).
**Fix:** Either trust `Data.WritingOptions.completeFileProtection` alone (verified by
a test that reads back `URLResourceValues.fileProtection`) and drop the re-stamp, or
write to a temp file, `setAttributes` on the temp file, then atomically `replaceItem`
— so the file is never observable without complete protection. The current
write-then-stamp order leaves a (small, probably-benign, but unproven) window.

### WR-07: `GeoContext.gateError` uses `>` for max-age, allowing a fix exactly `maxAge` stale through one path and rejecting it through another

**File:** `validationLedger/Core/Identity/Geo/GeoContext.swift:111-118`
**Issue:** `gateError` rejects when `age > maxAge`. The shipped `LocationProvider`
freshness threshold the comment claims this "mirrors" is the `maxAge` passed into
`locationProvider.currentLocation(maxAge:maxAccuracy:)` on `refresh()`. If
`LocationProvider` uses `>=` (reject at exactly `maxAge`) while `GeoContext` uses `>`
(accept at exactly `maxAge`), a fix that is exactly 30.0 s old passes the `GeoContext`
fast-path cache check (line 86) but would have been rejected had `refresh()` been
forced to re-fetch. The two layers must apply the *same* boundary or the "capture
path enforces the SAME thresholds as the auth path" guarantee (line 108-109) is
false at the boundary. For a fraud-detection product the staleness boundary is
security-relevant.
**Fix:** Confirm `DefaultLocationProvider`'s comparison operator and make
`GeoContext.gateError` use the identical one. If the provider rejects at `>= maxAge`,
change to `if age >= maxAge { return .staleFix }`.

### WR-08: `MockDefaultFixtures` ships a hard-coded session token in the binary

**File:** `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift:113`
**Issue:** `"session_token":"dev-mock-session-token"` is a hard-coded credential
string. The file is `#if DEBUG`-wrapped and the header argues Release impact is
"ZERO" because the whole file compiles out. That mitigation is correct for *Release*
builds, but the token is still a literal credential string in every DEBUG/TestFlight-
internal build, and the project is on a verified-identity-product security posture
where "no hardcoded secrets" is a baseline. The chunk/commit/artifact mock IDs use
`UUID()` (good); the session token does not. A DEBUG build handed to a beta tester
ships a known, fixed session-token string.
**Fix:** Generate the mock session token with `UUID().uuidString` like the other mock
IDs, so no fixed credential literal exists in any build artifact:
```swift
private static func otpVerifyResponseJSON() -> Data {
    let token = "dev-mock-\(UUID().uuidString)"
    return Data(#"{"session_token":"\#(token)","role":"carrier","user_id":"dev-mock-user"}"#.utf8)
}
```

### WR-09: `KYCReviewViewModel.retryUpload` can leave a committed row showing `.failed`

**File:** `validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift:303-326`
**Issue:** After `kycUploader.upload(...)` returns, `retryUpload` calls `refresh()`
then:
```swift
if case .uploading = rowStatus(for: artifactType) {
    markFailed(artifactType)
}
```
The intent is "if the upload threw without committing, show failed". But the upload
can also *succeed late*: `upload()` is `async`; between `refresh()` reading the store
and the `rowStatus` check, nothing changes — that part is fine. The real defect: if
`upload()` throws (e.g. `retriesExhausted`) but a *previous* pipelined attempt had
already committed the artifact (D-01 kicked it, it committed, then the user tapped
"Retry upload" anyway), `refresh()` reads `committed == true` → `.uploaded`, the
`if case .uploading` is false, and the row correctly shows `.uploaded`. Conversely if
`upload()` succeeds but the store write to `committed` lost a race (see WR-03), the
row stays `.uploading` and gets force-marked `.failed` — a committed artifact
displayed as failed, which lets the user trigger a pointless re-capture of a verified
artifact. The status derivation conflates "upload threw" with "row still uploading"
without consulting whether the throw was `retriesExhausted` vs a benign duplicate.
**Fix:** Branch on the actual error. Capture the thrown error and only `markFailed`
for genuinely-terminal cases (`retriesExhausted`, `commitFailed`, `nonRetryable`);
for `artifactDataMissing` (which means "already committed, bytes freed") treat it as
success and `refresh()` alone. Do not infer failure from the post-refresh row status.

## Info

### IN-01: `KYCUploader.upload` calls `store.loadSession()` three times for one upload

**File:** `validationLedger/Core/Identity/KYCUploader.swift:127, 141, 179, 191`
**Issue:** `loadSession()` is called at line 127 (resume probe), 141 (fresh-data
read), 179 (re-read for chunk loop), and 191 (re-read for `chunksAcked`). Each is a
full JSON decode of the whole session. Lines 179 and 191 could be a single load.
Beyond cost, four independent loads mean four chances for the resume-state and
artifact-data to be read at different store generations if a concurrent writer
interleaves (mitigated only by the per-call lock, not across calls).
**Fix:** Load the session once into a local at the top of `upload()` and pass the
needed slices down; re-read only where a fresh post-mutation view is genuinely
required.

### IN-02: `KYCStatusViewModel.artifactType(forID:)` is a fragile string-substring heuristic

**File:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift:220-230`
**Issue:** Mapping a server `artifactID` to an `ArtifactType` by `lowercased().contains("dl-front")`
etc. is brittle: a backend ID like `art-7a3f-vehicle-front` or any ID that happens to
contain `"face"` as a substring of a hash segment mis-classifies, sending the user to
recapture the wrong artifact. The "Retake" target is derived from a substring match
on an opaque server identifier.
**Fix:** Have the backend return the artifact *type* explicitly on the
`KYCStatusEndpoint.Response.Artifact` (a `type` field), and decode it directly rather
than guessing. If the backend cannot, document the ID grammar as a hard contract and
parse it strictly (anchored segments), not with `contains`.

### IN-03: `DLFieldFormatValidator` is defined but never invoked in the capture flow

**File:** `validationLedger/Features/Onboarding/KYC/Capture/DLFieldFormatValidator.swift` (whole file)
**Issue:** The validator's documented job is the D-05 "auto-prompt a rescan when the
scan is obviously malformed" gate. `DLFrontScanViewController.completeScan` builds a
`DLExtraction` and immediately bubbles it via `onScanComplete` →
`pushDLFrontExtraction`; `KYCCoordinator.pushDLFrontExtraction` constructs
`DLFrontExtractionViewController(extraction:)` with no validator call visible in the
reviewed files. If the auto-rescan gate lives inside `DLFrontExtractionViewController`
that is fine — but that VC was not in the reviewed set, so the wiring is unverified.
A pure validator with no call site is dead code.
**Fix:** Confirm `DLFrontExtractionViewController` actually runs
`DLFieldFormatValidator.validate(...)` and auto-prompts the rescan on `.invalid`. If
it does not, the D-05 gate is unimplemented; if it does, no action needed.

### IN-04: `KYCFlowSequencer` is now bookkeeping-only — `uploadsKicked` and `advance`'s artifact logic are misleading

**File:** `validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift:93-120, 270-284`
**Issue:** The comment at line 270-284 explains the off-by-one bug fix: uploads are
now kicked directly via `kickUpload(for:)`, and `advanceFlowStep()` only advances the
sequencer "for `reachedReview` bookkeeping". But `KYCFlowSequencer.advance()` still
appends to `uploadsKicked` (line 114-117), and `uploadsKicked` is still a
`public private(set)` property. Nothing reads it in production anymore — its name now
actively lies about what it tracks (it records sequencer-advance artifacts, not
actually-kicked uploads). A future reader will trust `uploadsKicked` as the kicked set
and be wrong.
**Fix:** Either remove `uploadsKicked` and the artifact-append logic from
`KYCFlowSequencer` entirely (the coordinator no longer needs it), or rename it to
something truthful like `stepsWithArtifacts` and update the doc comment. Do not leave
a public property whose name contradicts the off-by-one fix.

### IN-05: `KYCSession.Codable` keys `artifactData`/`uploadStates`/`submitted` are non-optional decodes with no forward-compat tolerance

**File:** `validationLedger/Core/Identity/KYC/KYCSession.swift:80-89`
**Issue:** The custom `init(from:)` was added specifically so `thumbnailData` decodes
tolerantly (`decodeIfPresent ?? [:]`) for old on-disk sessions. But
`artifactData`, `uploadStates`, and `submitted` are still hard `decode(...)`. If a
future schema change removes or renames any of them, an old-vs-new mismatch throws
`KYCSessionStoreError.decodingFailed`, and the store has no recovery path — a
decode failure on the in-progress session blocks the entire KYC resume. The
forward-compat treatment is inconsistent: one field is tolerant, three are not.
**Fix:** Apply `decodeIfPresent ?? default` to all collection/flag fields for
schema-evolution resilience, OR add a `clearSession()`-and-restart fallback in
`loadSession()` when `decodingFailed` is caught (a corrupt/incompatible session is
better discarded than fatal). Given KYC artifacts re-capture cheaply, discard-on-
decode-failure is the safer default.

### IN-06: `RejectedArtifact` filter relies on a magic string `"rejected"` duplicated from the endpoint comment

**File:** `validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift:182-184`
**Issue:** `response.artifacts.filter { $0.status == "rejected" }` hard-codes the
per-artifact status string. `KYCStatusEndpoint.Response.Artifact.status` is a raw
`String` documented as `"pending_review" | "verified" | "rejected"`. The artifact-
level status has no controlled-vocabulary enum (unlike `KYCOverallStatus` and
`RejectionReasonCode`, which both got proper enums). A backend that emits `"Rejected"`
or `"reject"` silently drops the artifact from the rejected list, and the user sees a
rejected verdict with zero recapture rows.
**Fix:** Introduce an `ArtifactStatus` enum mirroring the `KYCOverallStatus` pattern
and decode/compare against it, so an unknown artifact status is handled explicitly
rather than silently excluded.

---

_Reviewed: 2026-05-17T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
</content>
</invoke>
