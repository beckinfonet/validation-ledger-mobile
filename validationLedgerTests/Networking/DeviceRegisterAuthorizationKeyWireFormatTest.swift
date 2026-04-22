// validationLedgerTests/Networking/DeviceRegisterAuthorizationKeyWireFormatTest.swift
// Phase 4 Plan 05 Task 4 — D-02 three-key payload wire format pin.
//
// Covers D-02 (Plan 05 T4): the /device/register payload now carries THREE
// separate public keys:
//   - device_public_key           — P-256 device identity (Phase 2 DEV-01; existing)
//   - authorization_public_key    — P-256 authorization key (Phase 4 DEV-02; NEW)
//   - attestation_object          — CBOR blob from DCAppAttestService (D-06; optional)
//
// This test pins the exact snake_case wire key "authorization_public_key"
// on BOTH the .attested branch and a .entitlementMissing branch — the
// authorization key is a REQUIRED (non-Optional) field on the RequestBody,
// so it must be present regardless of attestation status (D-09f only omits
// attestedKeyId + attestationObject, NOT authorizationPublicKey).
//
// Regression guard: if a future engineer mangles authorizationPublicKey to
// "authorization_publickey" or similar via a wrong CodingKeys override, this
// test fails — protects the backend contract.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-02 — DeviceRegisterEndpoint wire format includes authorization_public_key")
struct DeviceRegisterAuthorizationKeyWireFormatTest {

    private static let snakeEncoder: JSONEncoder = APIClient.defaultEncoder()

    private func fingerprint() -> DeviceRegisterEndpoint.DeviceFingerprintPayload {
        DeviceRegisterEndpoint.DeviceFingerprintPayload(
            model: "iPhone15,2",
            iosVersion: "17.5",
            installUUID: "22222222-2222-2222-2222-222222222222"
        )
    }

    @Test("attested payload — JSON contains authorization_public_key snake_case key + value")
    func attestedIncludesAuthorizationKey() throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: "keyid-abc",
            attestationObject: Data("cbor".utf8),
            attestationStatus: .attested,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        #expect(str.contains("\"authorization_public_key\":\"ak-b64\""),
                "D-02: wire format MUST carry authorization_public_key when status=.attested; got: \(str)")
        #expect(str.contains("\"device_public_key\":\"dk-b64\""),
                "D-02 regression: device_public_key must also be present in three-key payload; got: \(str)")
    }

    @Test("non-attested payload — authorization_public_key still present (REQUIRED field)")
    func nonAttestedStillIncludesAuthorizationKey() throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: nil,
            attestationObject: nil,
            attestationStatus: .entitlementMissing,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        #expect(str.contains("\"authorization_public_key\":\"ak-b64\""),
                "D-02: authorization_public_key is REQUIRED (non-Optional); MUST encode for every status; got: \(str)")
        #expect(str.contains("\"device_public_key\":\"dk-b64\""),
                "D-02: device_public_key is REQUIRED; MUST encode for every status; got: \(str)")
        #expect(!str.contains("\"attested_key_id\""),
                "D-09f guard: attested_key_id MUST be omitted when status != attested")
        #expect(!str.contains("\"attestation_object\""),
                "D-09f guard: attestation_object MUST be omitted when status != attested")
    }

    @Test("wire key is exactly 'authorization_public_key' — no mangling, no camelCase leak")
    func authorizationKeyWireSpelling() throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: nil,
            attestationObject: nil,
            attestationStatus: .simulatorBypass,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        // Guard against wrong snake_case mangling:
        #expect(!str.contains("\"authorizationPublicKey\""),
                "D-02: camelCase authorizationPublicKey MUST NOT leak through the wire (got: \(str))")
        #expect(!str.contains("\"authorization_publickey\""),
                "D-02: mangled authorization_publickey (missing underscore) MUST NOT occur (got: \(str))")
        #expect(!str.contains("\"auth_public_key\""),
                "D-02: shortened auth_public_key MUST NOT occur; exact key is authorization_public_key (got: \(str))")

        // And assert the exact spelling:
        #expect(str.contains("\"authorization_public_key\""),
                "D-02: exact wire key 'authorization_public_key' MUST appear; got: \(str)")
    }

    @Test("all 6 AttestationStatus values keep authorization_public_key in the payload",
          arguments: [
              AttestationStatus.attested,
              AttestationStatus.unsupported,
              AttestationStatus.entitlementMissing,
              AttestationStatus.quotaExceeded,
              AttestationStatus.simulatorBypass,
              AttestationStatus.error
          ])
    func authorizationKeyPresentForEveryStatus(status: AttestationStatus) throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: status == .attested ? "keyid" : nil,
            attestationObject: status == .attested ? Data("cbor".utf8) : nil,
            attestationStatus: status,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"authorization_public_key\":\"ak-b64\""),
                "D-02: authorization_public_key MUST be present for status=\(status.rawValue); got: \(str)")
    }
}
