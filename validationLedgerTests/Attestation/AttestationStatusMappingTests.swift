// validationLedgerTests/Attestation/AttestationStatusMappingTests.swift
// Phase 4 Plan 05 Task 1 — D-09 enum routing + wire-format pinning.
//
// Covers D-09 (Plan 05 T1): six-value AttestationStatus wire contract.
// DCAppAttestAttestationService.statusForDCError(_:) is `private` (deliberate —
// PII discipline: the mapping is an internal implementation detail of the
// production service), so this suite pins the externally-observable invariant:
// the AttestationStatus enum's raw values themselves.
//
// A regression that renames a case (e.g. `.entitlementMissing` → `.noEntitlement`)
// would silently break the /device/register wire contract with the backend fixture
// recognizer (Plan 02 device-register-software-only.json and future attestation-
// status fixtures). These tests pin the exact rawValue strings so any rename
// or casing change fails at test time.
//
// PII discipline: failure messages reference only AttestationStatus.rawValue
// strings — never attestedKeyId / attestationObject bytes.

import Testing
import Foundation
@testable import validationLedger

@Suite("AttestationStatus mapping — D-09 enum routing")
struct AttestationStatusMappingTests {

    // MARK: - D-09 wire-format pinning (all 6 cases)

    @Test("D-09 — AttestationStatus.attested rawValue is 'attested'")
    func attestedRawValue() {
        #expect(AttestationStatus.attested.rawValue == "attested")
    }

    @Test("D-09a — AttestationStatus.unsupported rawValue is 'unsupported'")
    func unsupportedRawValue() {
        #expect(AttestationStatus.unsupported.rawValue == "unsupported")
    }

    @Test("D-09b — AttestationStatus.entitlementMissing rawValue is 'entitlementMissing' (DCError.featureUnsupported route)")
    func entitlementMissingRawValue() {
        #expect(AttestationStatus.entitlementMissing.rawValue == "entitlementMissing")
    }

    @Test("D-09c — AttestationStatus.quotaExceeded rawValue is 'quotaExceeded' (DCError.serverUnavailable / Pitfall 2)")
    func quotaExceededRawValue() {
        #expect(AttestationStatus.quotaExceeded.rawValue == "quotaExceeded")
    }

    @Test("D-09d — AttestationStatus.simulatorBypass rawValue is 'simulatorBypass' (SimulatorBypassAttestationService)")
    func simulatorBypassRawValue() {
        #expect(AttestationStatus.simulatorBypass.rawValue == "simulatorBypass")
    }

    @Test("D-09e — AttestationStatus.error rawValue is 'error' (DCError.invalidInput / .invalidKey / .unknownSystemFailure route)")
    func errorRawValue() {
        #expect(AttestationStatus.error.rawValue == "error")
    }

    // MARK: - Combined pinning — single test that locks ALL 6 values

    @Test("D-09 — AttestationStatus rawValue wire format pinned for all 6 cases")
    func wireFormatStability() {
        // If any of these flip, the backend contract silently breaks. Pin each.
        #expect(AttestationStatus.attested.rawValue            == "attested")
        #expect(AttestationStatus.unsupported.rawValue         == "unsupported")
        #expect(AttestationStatus.entitlementMissing.rawValue  == "entitlementMissing")
        #expect(AttestationStatus.quotaExceeded.rawValue       == "quotaExceeded")
        #expect(AttestationStatus.simulatorBypass.rawValue     == "simulatorBypass")
        #expect(AttestationStatus.error.rawValue               == "error")
    }

    // MARK: - Codable round-trip — JSON encoding uses the rawValue strings

    @Test("D-09 — JSONEncoder encodes each AttestationStatus to its rawValue string verbatim")
    func codableRoundTripAllCases() throws {
        let allCases: [AttestationStatus] = [
            .attested,
            .unsupported,
            .entitlementMissing,
            .quotaExceeded,
            .simulatorBypass,
            .error
        ]
        let encoder = JSONEncoder()
        for status in allCases {
            // Top-level enums aren't JSON-encodable in some older toolchains;
            // wrap in a single-field object to exercise the same path as
            // DeviceRegisterEndpoint.RequestBody's attestationStatus field.
            let wrapper = ["attestation_status": status]
            let data = try encoder.encode(wrapper)
            let str = String(data: data, encoding: .utf8) ?? ""
            #expect(
                str.contains("\"\(status.rawValue)\""),
                "D-09: expected rawValue '\(status.rawValue)' in JSON, got: \(str)"
            )
        }
    }

    @Test("D-09 — JSONDecoder decodes each rawValue back to its AttestationStatus case")
    func codableDecodeRoundTrip() throws {
        let cases: [(String, AttestationStatus)] = [
            ("attested", .attested),
            ("unsupported", .unsupported),
            ("entitlementMissing", .entitlementMissing),
            ("quotaExceeded", .quotaExceeded),
            ("simulatorBypass", .simulatorBypass),
            ("error", .error)
        ]
        let decoder = JSONDecoder()
        for (wire, expected) in cases {
            let json = "{\"attestation_status\":\"\(wire)\"}"
            let data = Data(json.utf8)
            let decoded = try decoder.decode([String: AttestationStatus].self, from: data)
            #expect(
                decoded["attestation_status"] == expected,
                "D-09: wire value '\(wire)' must decode to \(expected); got \(String(describing: decoded["attestation_status"]))"
            )
        }
    }
}
