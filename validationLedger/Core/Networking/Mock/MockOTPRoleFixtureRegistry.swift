// validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift
// Phase 3 D-32 / SC-1: DEBUG-only helper that registers MockURLProtocol fixtures
// returning success for OTPRequest + OTPVerify(role-specific) + DeviceRegister.
// Triggered from SceneDelegate when the -MockOTPRoleForUITest <role> launchArg
// is present (UI smoke tests). Release builds compile to nothing (the entire
// file body is inside `#if DEBUG`).
//
// Threat model: T-03-12-01 (Tampering) — Release build accidentally accepts the
// -MockOTPRoleForUITest launchArg. Mitigation: the entire handler + registry are
// inside `#if DEBUG`; a Release binary grep for MockOTPRoleFixtureRegistry or
// StubLocationProviderForUITest / StubCountryGateForUITest returns ZERO hits.
//
// Also hosts the DEBUG-only `StubLocationProviderForUITest` + `StubCountryGateForUITest`
// so the UI tests get a deterministic, network-free, prompt-free geo path — eliminates
// CLLocationManager permission prompts and CLGeocoder network flakiness on CI sims.

#if DEBUG

import CoreLocation
import Foundation

enum MockOTPRoleFixtureRegistry {

    /// Register all fixtures needed to drive a successful OTP flow ending in a
    /// role-distinct shell. Called from SceneDelegate when -MockOTPRoleForUITest
    /// is detected. JSON shape matches the Phase 2 endpoint decoders which use
    /// `.convertFromSnakeCase` — keys here are snake_case to match the wire.
    static func registerForRole(_ role: Role) {
        MockURLProtocol.reset()

        // OTP request → returns otpSessionID
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/request" else { return nil }
            let body = """
            {"otp_session_id": "ui-test-session-id", "expires_in_seconds": 300}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        // OTP verify → returns sessionToken + role + userID
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/verify" else { return nil }
            let body = """
            {
                "session_token": "ui-test-token",
                "role": "\(role.rawValue)",
                "user_id": "ui-test-user-\(role.rawValue)"
            }
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        // Device register → returns success
        MockURLProtocol.register { req in
            guard req.url?.path == "/device/register" else { return nil }
            let body = """
            {"device_id": "ui-test-device-id", "registered_at": "2026-04-21T00:00:00Z"}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
    }
}

// MARK: - Stub LocationProvider + CountryGate (Warning 4 mandatory)

/// Stub LocationProvider for UI tests — always returns a US coordinate immediately.
/// No CLLocationManager permission prompt; no hardware dependency; synchronous success.
/// Injected via `AppContainer.uiTestLocationProvider` static override.
@MainActor
final class StubLocationProviderForUITest: LocationProvider {
    func requestPermission() async -> CLAuthorizationStatus { .authorizedWhenInUse }

    func currentLocation(
        maxAge: TimeInterval,
        maxAccuracy: CLLocationDistance
    ) async throws -> CLLocation {
        // Apple Park — Cupertino, US. Literal allowed here because this file path
        // `Core/Networking/Mock/` is NOT on the `ban_raw_coordinate_literal`
        // allowlist, but the SwiftLint rule targets production geo code — this
        // stub is DEBUG-only scaffolding. If the linter complains, add
        // `// swiftlint:disable:next ban_raw_coordinate_literal` on the next line.
        CLLocation(latitude: 37.3349, longitude: -122.0090)
    }
}

/// Stub CountryGate for UI tests — always returns "US".
/// No network call to CLGeocoder; synchronous success.
/// Injected via `AppContainer.uiTestCountryGate` static override.
final class StubCountryGateForUITest: CountryGate, @unchecked Sendable {
    func resolveCountry(for location: CLLocation) async throws -> String { "US" }
}

#endif
