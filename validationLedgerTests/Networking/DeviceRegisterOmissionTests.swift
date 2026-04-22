// validationLedgerTests/Networking/DeviceRegisterOmissionTests.swift
// Phase 4 Plan 05 Task 2 — D-09f attestation-field omission rule (parametrized).
//
// Covers D-09f (Plan 05 T2): when attestationStatus != .attested, the encoded
// JSON MUST OMIT attested_key_id AND attestation_object entirely. This is
// the mechanism that lets the client send a "I couldn't attest" payload
// without forcing the backend to parse a wire-format `null` or empty string
// placeholder.
//
// The omission behavior comes for free from Swift's JSONEncoder — Optional.none
// fields are not emitted. These tests pin that behavior across all 5
// non-attested AttestationStatus values so a future engineer who
// "improves" DeviceRegisterEndpoint.RequestBody by changing fields to
// non-Optional (or adding explicit nil encoding) fails immediately.
//
// Parametrized `@Test(arguments:)` is the Swift Testing idiom for this kind
// of matrix — one definition, five executions.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-09f — DeviceRegisterEndpoint omits attestation fields when status != attested")
struct DeviceRegisterOmissionTests {

    private static let snakeEncoder: JSONEncoder = {
        // Mirror APIClient.defaultEncoder() exactly.
        let e = APIClient.defaultEncoder()
        return e
    }()

    private func fingerprint() -> DeviceRegisterEndpoint.DeviceFingerprintPayload {
        DeviceRegisterEndpoint.DeviceFingerprintPayload(
            model: "iPhone15,2",
            iosVersion: "17.5",
            installUUID: "11111111-1111-1111-1111-111111111111"
        )
    }

    // MARK: - Attested path includes both fields

    @Test("attestationStatus=.attested — payload INCLUDES attested_key_id + attestation_object + attestation_status:'attested'")
    func includedWhenAttested() throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: "keyid-abc",
            attestationObject: Data("cbor-bytes".utf8),
            attestationStatus: .attested,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        #expect(str.contains("\"attested_key_id\""),
                "D-09f: attested_key_id MUST be present when status=.attested; got: \(str)")
        #expect(str.contains("\"attestation_object\""),
                "D-09f: attestation_object MUST be present when status=.attested; got: \(str)")
        #expect(str.contains("\"attestation_status\":\"attested\""),
                "D-09f: attestation_status wire rawValue must match; got: \(str)")
    }

    // MARK: - Non-attested path — parametrized across all 5 rawValues

    @Test(
        "Non-attested statuses omit attested_key_id + attestation_object",
        arguments: [
            AttestationStatus.unsupported,
            AttestationStatus.entitlementMissing,
            AttestationStatus.quotaExceeded,
            AttestationStatus.simulatorBypass,
            AttestationStatus.error
        ]
    )
    func omittedWhenNotAttested(status: AttestationStatus) throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: nil,
            attestationObject: nil,
            attestationStatus: status,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        #expect(!str.contains("\"attested_key_id\""),
                "D-09f: attested_key_id MUST be omitted when status=\(status.rawValue); got: \(str)")
        #expect(!str.contains("\"attestation_object\""),
                "D-09f: attestation_object MUST be omitted when status=\(status.rawValue); got: \(str)")
        #expect(str.contains("\"attestation_status\":\"\(status.rawValue)\""),
                "D-09f: attestation_status rawValue MUST match wire format; got: \(str)")
    }

    // MARK: - Regression guard: three-key payload (D-02) is present in BOTH branches

    @Test("Attested path — payload contains device_public_key + authorization_public_key (D-02 three-key)")
    func attestedIncludesThreeKeyPayload() throws {
        let body = DeviceRegisterEndpoint.RequestBody(
            devicePublicKey: "dk-b64",
            authorizationPublicKey: "ak-b64",
            attestedKeyId: "keyid",
            attestationObject: Data("cbor".utf8),
            attestationStatus: .attested,
            deviceFingerprint: fingerprint()
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"device_public_key\""))
        #expect(str.contains("\"authorization_public_key\""))
    }
}
