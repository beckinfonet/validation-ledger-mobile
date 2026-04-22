// validationLedgerTests/Networking/DeviceChallengeEndpointTests.swift
// Phase 4 Plan 05 Task 2 — D-05 GET /device/challenge fixture round-trip.
//
// Covers D-05 (Plan 05 T2): the GET /device/challenge endpoint returns
// { challenge: base64, expires_at: ISO8601, nonce: string }. APIClient uses
// .convertFromSnakeCase + .iso8601 strategies — this test pins the decode
// path end-to-end against the Plan 02 success fixture.
//
// Uses APIClient.defaultDecoder() to match production exactly (any drift in
// the default decoder configuration would surface here).

import Testing
import Foundation
@testable import validationLedger

@Suite("D-05 — GET /device/challenge decodes fixture round-trip")
struct DeviceChallengeEndpointTests {

    @Test("Fixture decodes into Response with all 3 fields")
    func decodesResponse() throws {
        let data = try FixtureLoader.loadFixture("device-challenge-success")
        // Use APIClient's actual decoder so this test surfaces any
        // drift in decoder configuration (.convertFromSnakeCase / .iso8601).
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceChallengeEndpoint.Response.self, from: data)

        #expect(!response.challenge.isEmpty, "D-05: challenge field MUST be non-empty")
        #expect(response.nonce == "nonce-abc-123",
                "D-05: nonce MUST decode from fixture verbatim")
        // Challenge is base64 in the wire format; client SHA-256s the decoded bytes (D-06).
        #expect(Data(base64Encoded: response.challenge) != nil,
                "D-05: challenge field MUST be base64-decodable so the client can SHA-256 the decoded bytes per D-06")
    }

    @Test("Fixture decodes expiresAt as a Date (ISO-8601 round-trip)")
    func decodesExpiresAt() throws {
        let data = try FixtureLoader.loadFixture("device-challenge-success")
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(DeviceChallengeEndpoint.Response.self, from: data)

        // Exact fixture value: "2026-04-22T12:01:00Z"
        let formatter = ISO8601DateFormatter()
        let expected = formatter.date(from: "2026-04-22T12:01:00Z")
        #expect(expected != nil)
        #expect(response.expiresAt == expected,
                "D-05: expires_at MUST decode via .iso8601 strategy to the fixture's ISO-8601 timestamp")
    }

    @Test("Endpoint shape: path is /device/challenge, method is GET, body is nil")
    func endpointShape() {
        let ep = DeviceChallengeEndpoint()
        #expect(ep.path == "/device/challenge",
                "D-05: endpoint path MUST be /device/challenge")
        #expect(ep.method == .get,
                "D-05: endpoint method MUST be GET (no body required)")
        #expect(ep.body == nil,
                "D-05: GET endpoint body MUST be nil (EmptyBody sentinel via APIEndpoint)")
    }
}
