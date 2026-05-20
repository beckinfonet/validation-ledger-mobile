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
    ///
    /// Phase 4 Plan 08 (D-11 / D-12): the `trustTier` parameter controls the
    /// `trust_tier` field of the /device/register response. Default
    /// `.hardwareAttested` preserves existing Phase 3 RoleShellSmokeTests
    /// behavior (banner absent). The Phase 4 LimitedTrustBannerTests pass
    /// `trustTier: .softwareOnly` to drive the banner-visible path. The
    /// response body mirrors the canonical fixtures at
    /// `validationLedgerTests/Networking/Fixtures/device-register-{success,software-only}.json`.
    static func registerForRole(_ role: Role, trustTier: TrustTier = .hardwareAttested) {
        MockURLProtocol.reset()

        // OTP request → returns otpSessionID
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/request" else { return nil }
            let body = Data("""
            {"otp_session_id": "ui-test-session-id", "expires_in_seconds": 300}
            """.utf8)
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        // OTP verify → returns sessionToken + role + userID + kycStatus.
        // Phase 5 D-12: OTPViewModel routes a verified user whose
        // `kyc_status == "verified"` straight to the role shell; any other value
        // (or an absent field) routes into the `.kyc` hard gate and fails CLOSED
        // (T-05-07-02). RoleShellSmokeTests + LimitedTrustBannerTests drive the
        // OTP flow expecting to land on the role tab bar, so the mock verify
        // response MUST carry `"kyc_status": "verified"` — a returning verified
        // user. Pre-Phase-5 this fixture omitted the field; the D-12 gate then
        // diverted all 5 smoke tests to the KYC gate (caught by the post-merge
        // gate during Plan 05-11 execution).
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/verify" else { return nil }
            let body = Data("""
            {
                "session_token": "ui-test-token",
                "role": "\(role.rawValue)",
                "user_id": "ui-test-user-\(role.rawValue)",
                "kyc_status": "verified"
            }
            """.utf8)
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        // Device register → returns success with role-independent identifiers +
        // Phase 4 D-12 `trust_tier` field. Default .hardwareAttested preserves
        // Phase 3 RoleShellSmokeTests (banner absent). Phase 4 Plan 08
        // LimitedTrustBannerTests passes .softwareOnly to drive the banner-
        // visible path. The response body mirrors the canonical fixtures at
        // `validationLedgerTests/Networking/Fixtures/device-register-{success,software-only}.json`.
        let trustTierRawValue = trustTier.rawValue
        MockURLProtocol.register { req in
            guard req.url?.path == "/device/register" else { return nil }
            let body = Data("""
            {"device_id": "ui-test-device-id", "registered_at": "2026-04-21T00:00:00Z", "trust_tier": "\(trustTierRawValue)"}
            """.utf8)
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        // Phase 8 LOAD-03 (Plan 04 — RoleLoadsTabSmokeTests dependency).
        // After the OTP+device-register fixtures are registered, ALSO register
        // the Phase 7/8 load-domain handlers so the UI-test path serves the
        // envelope-wrapped role-filtered loads-list fixture when the user
        // taps the Loads (Invoices on Factoring) tab.
        MockLoadFixtureRegistry.registerAppDefaults()
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
        // Apple Park — Cupertino, US. A plain `CLLocation` literal — the
        // `ban_raw_coordinate_literal` rule only matches the coordinate-pair
        // constructor (`CLLocationCoordinate2D`), not `CLLocation`, so this
        // DEBUG-only stub is not flagged and needs no disable directive.
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
