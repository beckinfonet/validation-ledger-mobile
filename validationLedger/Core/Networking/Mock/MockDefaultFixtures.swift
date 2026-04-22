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
// Fix: register a small set of default handlers covering the five endpoints
// the organic onboarding flow hits. Lets a developer walk through phone-entry →
// OTP verify → role shell with any 6-digit code and zero backend.
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

    /// Register the organic-onboarding default handlers with MockURLProtocol.
    /// Called once per AppContainer construction from the DEBUG-only gated
    /// block in AppContainer.init. Idempotent enough for the single call site.
    public static func registerAppDefaults() {
        MockURLProtocol.register(dispatchHandler)
    }

    /// Catch-all dispatch. Returns nil for unknown paths so MockURLProtocol's
    /// built-in 404 kicks in (Plan 04-11: loud misses over silent hangs).
    private static let dispatchHandler: MockURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        switch (method, path) {
        case ("POST", "/auth/otp/request"):
            return make200(body: otpRequestResponseJSON(), url: request.url)

        case ("POST", "/auth/otp/verify"):
            if isAnySixDigitCode(request.httpBody) {
                return make200(body: otpVerifyResponseJSON(), url: request.url)
            } else {
                return makeError(
                    status: 400,
                    code: "invalid_code",
                    message: "Enter any 6 digits for the dev mock.",
                    url: request.url
                )
            }

        case ("GET", "/device/challenge"):
            return make200(body: deviceChallengeResponseJSON(), url: request.url)

        case ("POST", "/device/register"):
            return make200(body: deviceRegisterResponseJSON(), url: request.url)

        case ("POST", "/device/heartbeat"):
            return make200(body: deviceHeartbeatResponseJSON(), url: request.url)

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

    private static func makeError(status: Int, code: String, message: String, url: URL?) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "https://mock.local/")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"{"error_code":"\#(code)","message":"\#(message)"}"#.utf8)
        return (response, body)
    }

    // MARK: - Request body inspection

    /// Accepts any OTPVerifyEndpoint.Request JSON whose `code` field is exactly
    /// 6 numeric characters. The APIClient encodes Request bodies with
    /// `.convertToSnakeCase`, so `otpSessionID` arrives as `otp_session_id`
    /// and `code` as `code`. We look for ANY string value matching ^[0-9]{6}$
    /// to avoid coupling to exact key names — keeps the dev mock forgiving.
    private static func isAnySixDigitCode(_ body: Data?) -> Bool {
        guard let body,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        for value in obj.values {
            if let s = value as? String,
               s.count == 6,
               s.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return true
            }
        }
        return false
    }
}
#endif
