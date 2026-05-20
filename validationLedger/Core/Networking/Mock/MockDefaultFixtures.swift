// validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift
// Phase 4 Plan 04-11 — DEBUG-only physical-device mock fixtures.
//
// Problem: a DEBUG build on a physical device runs with networkConfig == .mock
// by default (AppContainer.defaultNetworkConfig), so all HTTP flows through
// MockURLProtocol. MockURLProtocol is explicitly empty by default — Phase 2
// Plan 01 removed the /ping default so every test registers its own fixtures.
// For the organic tap-through flow (no launch args) on a real device, this
// leaves no handlers registered and every request falls through to the built-in
// 404 — which manifests as a silent hang at "Send code" because neither the
// PhoneEntryViewModel nor OTPViewModel surfaces a loud error state yet.
//
// Fix: register a small set of default handlers covering the endpoints the
// organic onboarding flow hits — phone-entry → OTP verify → device register →
// the 6-artifact KYC upload flow → /kyc/submit. Lets a developer walk the whole
// flow on a real device with zero backend.
//
// === KYC upload endpoints (debug session `kyc-upload-capture-bugs`, Issue 2a) ===
// Phase 4 added device-mock fixtures for the 5 auth/device endpoints but the
// Phase-5 KYC upload endpoints (`/kyc/upload/init`, `/kyc/upload/chunk`,
// `/kyc/upload/commit`, `/kyc/submit`) were never added. On a DEBUG device run
// every artifact's init POST 404'd, `KYCUploader.upload` threw before persisting
// any `ArtifactUploadState`, and the Review screen reported `.pending` forever —
// Submit could never enable. The four handlers below close that gap with canned
// 200 responses mirroring each shipped endpoint's `Response` shape. See the
// Resolution in `.planning/debug/resolved/kyc-upload-capture-bugs.md`.
//
// === KYC status verified-toggle (debug session `kyc-status-under-review-trap`) ===
// During Phase 9 device UAT the `under_review` pin (intentional — mirrors the
// real backend's post-submit verdict) blocked the only path past the D-12 gate
// into the role shell, so the tester could not exercise Phase 6+ surfaces.
// `-MockKYCStatusVerified` is an opt-in launch argument that flips GET
// /kyc/status's `overall_status` to `verified` so the status screen lands on
// the verified verdict and the "Continue" CTA into the role shell becomes
// reachable. Same launch-argument pattern + `#if DEBUG` gating as
// `-MockOTPRoleForUITest` (AppContainer.swift:547). Release builds compile this
// to zero bytes — the whole file is `#if DEBUG`.
//
// Release impact: ZERO. Entire file wrapped in `#if DEBUG`. AppContainer's
// call site is ALSO `#if DEBUG` gated + conditioned on `resolvedConfig == .mock`
// + not `-MockOTPRoleForUITest` — triple-gated. Release builds also force
// networkConfig to `.live` via defaultNetworkConfig(env:), so MockURLProtocol
// does not even exist in the URLSession's protocolClasses in Release.
//
// Non-goals:
//   - Not a replacement for `-MockOTPRoleForUITest` (that path bypasses the OTP
//     flow entirely; Phase 3 Plan 12 exercises it).
//   - Not a test double — tests register their own fixtures + call
//     MockURLProtocol.reset().
//   - Not a security surface — hard-coded session token is labelled dev-only.
//
// Design: one catch-all MockURLProtocol.Handler inspects (method, path) and
// routes to a canned response builder. Unknown paths return nil so the
// MockURLProtocol built-in 404 kicks in — missing fixtures surface loudly
// rather than hanging.

#if DEBUG
import Foundation

public enum MockDefaultFixtures {

    /// Launch-argument flag (DEBUG-only) that flips GET /kyc/status's
    /// `overall_status` to `"verified"`. Mirrors the `-MockOTPRoleForUITest`
    /// pattern (AppContainer.swift:547). Off by default — the organic
    /// device-UAT path still hits the realistic `under_review` verdict the
    /// real backend emits post-submit.
    ///
    /// Set in Xcode → Edit Scheme → Run → Arguments → Arguments Passed On Launch.
    public static let verifiedKYCStatusLaunchFlag = "-MockKYCStatusVerified"

    /// True when `-MockKYCStatusVerified` is present in this process's launch
    /// arguments. Evaluated once per request (cheap — argv is a tiny array).
    /// `internal` so the unit test can observe the default-off contract.
    static var verifiedKYCStatusOverrideActive: Bool {
        ProcessInfo.processInfo.arguments.contains(verifiedKYCStatusLaunchFlag)
    }

    /// Register the organic-onboarding default handlers with MockURLProtocol.
    /// Called once per AppContainer construction from the DEBUG-only gated
    /// block in AppContainer.init. Idempotent enough for the single call site.
    public static func registerAppDefaults() {
        MockURLProtocol.register(dispatchHandler)
    }

    /// Catch-all dispatch. Returns nil for unknown paths so MockURLProtocol's
    /// built-in 404 kicks in (Plan 04-11: loud misses over silent hangs).
    static let dispatchHandler: MockURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        switch (method, path) {
        case ("POST", "/auth/otp/request"):
            return make200(body: otpRequestResponseJSON(), url: request.url)

        case ("POST", "/auth/otp/verify"):
            // Dev-mock is forgiving: any body accepted. An earlier revision tried to
            // inspect `request.httpBody` for a 6-digit code, but async URLSession often
            // moves the body into `httpBodyStream` so `httpBody` is nil — which made
            // the mock return 400 for legitimate requests and get stuck in the OTP
            // screen's generic error state. Unconditional 200 is the right default
            // for the DEBUG tap-through walkthrough.
            return make200(body: otpVerifyResponseJSON(), url: request.url)

        case ("GET", "/device/challenge"):
            return make200(body: deviceChallengeResponseJSON(), url: request.url)

        case ("POST", "/device/register"):
            return make200(body: deviceRegisterResponseJSON(), url: request.url)

        case ("POST", "/device/heartbeat"):
            return make200(body: deviceHeartbeatResponseJSON(), url: request.url)

        // --- KYC upload flow (Issue 2a) ----------------------------------
        case ("POST", "/kyc/upload/init"):
            return make200(body: kycUploadInitResponseJSON(), url: request.url)

        case ("POST", "/kyc/upload/chunk"):
            return make200(body: kycUploadChunkResponseJSON(), url: request.url)

        case ("POST", "/kyc/upload/commit"):
            return make200(body: kycUploadCommitResponseJSON(), url: request.url)

        case ("POST", "/kyc/submit"):
            return make200(body: kycSubmitResponseJSON(verifiedOverride: verifiedKYCStatusOverrideActive), url: request.url)

        case ("GET", "/kyc/status"):
            return make200(body: kycStatusResponseJSON(verifiedOverride: verifiedKYCStatusOverrideActive), url: request.url)

        default:
            return nil  // Fall through to MockURLProtocol built-in 404.
        }
    }

    // MARK: - JSON bodies

    /// APIClient uses `.convertFromSnakeCase`, so wire-format keys are snake_case.
    /// Mirror each endpoint's fixture shape in `validationLedgerTests/Networking/Fixtures/`.
    private static func otpRequestResponseJSON() -> Data {
        Data(#"{"otp_session_id":"dev-mock-otp-session","expires_in_seconds":300}"#.utf8)
    }

    private static func otpVerifyResponseJSON() -> Data {
        Data(#"{"session_token":"dev-mock-session-token","role":"carrier","user_id":"dev-mock-user"}"#.utf8)
    }

    private static func deviceChallengeResponseJSON() -> Data {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let nonce = UUID().uuidString
        // base64("dev-mock-challenge") = "ZGV2LW1vY2stY2hhbGxlbmdl"
        return Data(#"{"challenge":"ZGV2LW1vY2stY2hhbGxlbmdl","expires_at":"\#(expiresAt)","nonce":"\#(nonce)"}"#.utf8)
    }

    private static func deviceRegisterResponseJSON() -> Data {
        let registeredAt = ISO8601DateFormatter().string(from: Date())
        // trust_tier: softwareOnly so the Plan 04-08 Limited-Trust banner appears
        // organically on the role shell for physical-device verification.
        return Data(#"{"device_id":"dev-mock-device","registered_at":"\#(registeredAt)","trust_tier":"softwareOnly"}"#.utf8)
    }

    private static func deviceHeartbeatResponseJSON() -> Data {
        let acceptedAt = ISO8601DateFormatter().string(from: Date())
        return Data(#"{"heartbeat_accepted_at":"\#(acceptedAt)","trust_tier":"softwareOnly"}"#.utf8)
    }

    // MARK: - KYC upload JSON bodies (Issue 2a)

    /// `POST /kyc/upload/init` → `KYCUploadInitEndpoint.Response` (uploadId,
    /// chunkSize). `chunkSize` echoes the uploader's 512 KB default so the
    /// uploader does not re-chunk; a fresh `uploadId` per request keeps each
    /// artifact's chunk/commit calls distinct.
    private static func kycUploadInitResponseJSON() -> Data {
        let uploadID = "dev-mock-upload-\(UUID().uuidString)"
        let chunkSize = 512 * 1024
        return Data(#"{"upload_id":"\#(uploadID)","chunk_size":\#(chunkSize)}"#.utf8)
    }

    /// `POST /kyc/upload/chunk` → `KYCUploadChunkEndpoint.Response` (ackedChunk,
    /// chunksAcked, totalChunks). The dev-mock cannot reliably read the request
    /// body (`URLProtocol` moves it to `httpBodyStream`), so it cannot know the
    /// chunk index or total. It returns `totalChunks: 0` — and `KYCUploader`'s
    /// chunk loop is built to fall back to its own locally-computed total when
    /// the server reports `0` (see `KYCUploader.upload`, the `total` line). The
    /// loop advances its resume cursor on its own loop index, never on these
    /// fields, so an unconditional ack reliably completes every chunk.
    private static func kycUploadChunkResponseJSON() -> Data {
        Data(#"{"acked_chunk":0,"chunks_acked":1,"total_chunks":0}"#.utf8)
    }

    /// `POST /kyc/upload/commit` → `KYCUploadCommitEndpoint.Response`
    /// (artifactId, status). A fresh `artifactId` per commit; `pending_review`
    /// is the real backend's post-commit status.
    private static func kycUploadCommitResponseJSON() -> Data {
        let artifactID = "dev-mock-artifact-\(UUID().uuidString)"
        return Data(#"{"artifact_id":"\#(artifactID)","status":"pending_review"}"#.utf8)
    }

    /// `POST /kyc/submit` → `KYCSubmitEndpoint.Response` (overallStatus).
    /// `under_review` is the real backend's post-submit status — it lets the
    /// plan-06 Status screen render its under-review state organically.
    /// When `verifiedOverride` is true (driven by the `-MockKYCStatusVerified`
    /// launch arg at the call site), returns `verified` instead so the
    /// post-submit hand-off lands on a passing verdict consistent with
    /// `kycStatusResponseJSON(verifiedOverride:)`.
    ///
    /// `internal` (not private) so the override-branch is unit-testable without
    /// mutating process-wide `ProcessInfo.arguments`.
    static func kycSubmitResponseJSON(verifiedOverride: Bool) -> Data {
        if verifiedOverride {
            return Data(#"{"overall_status":"verified"}"#.utf8)
        }
        return Data(#"{"overall_status":"under_review"}"#.utf8)
    }

    /// `GET /kyc/status` → `KYCStatusEndpoint.Response` (overallStatus,
    /// artifacts). `under_review` matches `kycSubmitResponseJSON()`'s
    /// post-submit status, so the status screen reached straight after Submit
    /// shows a consistent verdict. `artifacts` is an empty array because the
    /// device mock cannot inspect the request body to know which artifact IDs
    /// to echo — and the under-review verdict copy needs no per-artifact
    /// rejection detail. An empty array decodes cleanly into `[Artifact]`.
    ///
    /// When `verifiedOverride` is true (driven by the `-MockKYCStatusVerified`
    /// launch arg at the call site), returns `verified` instead so the status
    /// screen lands on the verified verdict and the "Continue" CTA into the
    /// role shell becomes reachable — the device-UAT escape hatch documented
    /// in `kyc-status-under-review-trap` and 05-UAT.md test 12.
    ///
    /// `internal` (not private) so the override-branch is unit-testable without
    /// mutating process-wide `ProcessInfo.arguments`.
    static func kycStatusResponseJSON(verifiedOverride: Bool) -> Data {
        if verifiedOverride {
            return Data(#"{"overall_status":"verified","artifacts":[]}"#.utf8)
        }
        return Data(#"{"overall_status":"under_review","artifacts":[]}"#.utf8)
    }

    // MARK: - HTTPURLResponse builders

    private static func make200(body: Data, url: URL?) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "https://mock.local/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }

}
#endif
