// validationLedgerTests/Networking/DeviceHeartbeatEndpointTests.swift
// Phase 4 Plan 05 Task 2 — D-07d POST /device/heartbeat + D-12 trustTier decode.
//
// Covers D-07d (Plan 05 T2): the RequestBody snake_case wire format
// (session_token / attested_key_id / assertion) and Response decoding of
// { heartbeat_accepted_at, trust_tier }.
// Covers D-12 (Plan 05 T2): trustTier decodes to the TrustTier enum — the
// backend fixture for the happy path returns "hardwareAttested".
//
// Uses APIClient.defaultEncoder / .defaultDecoder so drift in the production
// codec configuration (.convertToSnakeCase / .convertFromSnakeCase / .iso8601)
// surfaces here.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-07d + D-12 — POST /device/heartbeat encodes request + decodes trustTier")
struct DeviceHeartbeatEndpointTests {

    // MARK: - D-07d: Request body encoding

    @Test("D-07d — RequestBody encodes snake_case keys: session_token, attested_key_id, assertion")
    func requestBodyEncoding() throws {
        let body = DeviceHeartbeatEndpoint.RequestBody(
            sessionToken: "session-xyz",
            attestedKeyId: "keyid-abc",
            assertion: Data("assertion-bytes".utf8)
        )
        let encoder = APIClient.defaultEncoder()
        let json = try encoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        #expect(str.contains("\"session_token\""),
                "D-07d: wire format MUST use session_token snake_case key; got: \(str)")
        #expect(str.contains("\"attested_key_id\""),
                "D-07d: wire format MUST use attested_key_id snake_case key; got: \(str)")
        #expect(str.contains("\"assertion\""),
                "D-07d: assertion field MUST be present in request body")

        // assertion Data base64-encodes by default in JSONEncoder — pin this
        // so a strategy change surfaces as a failure.
        let base64 = Data("assertion-bytes".utf8).base64EncodedString()
        #expect(str.contains("\"\(base64)\""),
                "D-07d: assertion Data MUST base64-encode as default Encodable behavior; got: \(str)")
    }

    @Test("D-07d — Endpoint shape: path is /device/heartbeat, method is POST, body is non-nil")
    func endpointShape() {
        let ep = DeviceHeartbeatEndpoint(
            sessionToken: "s",
            attestedKeyId: "k",
            assertion: Data()
        )
        #expect(ep.path == "/device/heartbeat",
                "D-07d: endpoint path MUST be /device/heartbeat")
        #expect(ep.method == .post,
                "D-07d: endpoint method MUST be POST")
        #expect(ep.body != nil,
                "D-07d: POST body MUST be non-nil")
    }

    // MARK: - D-12: Response decode — trustTier routing

    @Test("D-12 — Response decodes trustTier from fixture (hardwareAttested)")
    func responseDecodeHardwareAttested() throws {
        let data = try FixtureLoader.loadFixture("device-heartbeat-success")
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceHeartbeatEndpoint.Response.self, from: data)

        #expect(response.trustTier == .hardwareAttested,
                "D-12: success fixture MUST decode trust_tier: 'hardwareAttested' to TrustTier.hardwareAttested")
    }

    @Test("D-12 — Response decodes heartbeatAcceptedAt as Date (ISO-8601)")
    func responseDecodeAcceptedAt() throws {
        let data = try FixtureLoader.loadFixture("device-heartbeat-success")
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceHeartbeatEndpoint.Response.self, from: data)

        let formatter = ISO8601DateFormatter()
        let expected = formatter.date(from: "2026-04-22T12:00:00Z")
        #expect(expected != nil)
        #expect(response.heartbeatAcceptedAt == expected,
                "D-07d: heartbeat_accepted_at MUST decode via .iso8601 strategy to fixture timestamp")
    }

    @Test("D-12 — trustTier MUST default to .softwareOnly when fixture encodes 'softwareOnly'")
    func trustTierSoftwareOnlyDecodes() throws {
        // Construct an inline JSON that mirrors the heartbeat shape but with
        // trust_tier: softwareOnly to exercise the alternate enum route.
        let json = #"{"heartbeat_accepted_at":"2026-04-22T12:00:00Z","trust_tier":"softwareOnly"}"#
        let data = Data(json.utf8)
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceHeartbeatEndpoint.Response.self, from: data)
        #expect(response.trustTier == .softwareOnly,
                "D-12: trust_tier: 'softwareOnly' MUST decode to TrustTier.softwareOnly")
    }
}
