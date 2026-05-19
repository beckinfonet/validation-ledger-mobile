// validationLedgerTests/Load/VerificationStateDecoderTests.swift
// Phase 7 LOAD-02 / D-09: fail-closed decoder coverage for VerificationState.
//
// This suite is the exhaustive test surface for the Phase 7 security primitive
// (Plan 07-01 Task 2). Coverage shape:
//   1. PRESENT-KNOWN wire value (every CaseIterable case) → matching case.
//   2. PRESENT-UNKNOWN wire value (multiple unknowns)     → .unverified
//      (fail-closed; proves the rule is value-agnostic, not "compromised"-specific).
//   3. MISSING parent field on a wrapping struct          → DecodingError.
//   4. The closed case set has exactly 4 cases (closure assertion).
//
// No MockURLProtocol touch — pure JSONDecoder fixture-strings; suite need not
// be .serialized.

import Testing
import Foundation
@testable import validationLedger

@Suite("VerificationState fail-closed decoder (D-09)")
struct VerificationStateDecoderTests {

    @Test("Known wire value decodes to matching case (every CaseIterable case)")
    func knownWireValueDecodesToMatchingCase() throws {
        let decoder = JSONDecoder()
        for kase in VerificationState.allCases {
            let json = Data("\"\(kase.rawValue)\"".utf8)
            let decoded = try decoder.decode(VerificationState.self, from: json)
            #expect(decoded == kase, "Expected \(kase.rawValue) to decode to \(kase) but got \(decoded)")
        }
    }

    @Test("Unknown wire value decodes to .unverified (D-09 fail-closed)")
    func unknownWireValueFailClosed() throws {
        let decoder = JSONDecoder()
        // A plausible future server superstring — must NOT upgrade trust.
        let compromised = Data("\"compromised\"".utf8)
        let trusted = Data("\"trusted\"".utf8)
        let quarantined = Data("\"quarantined\"".utf8)

        #expect(try decoder.decode(VerificationState.self, from: compromised) == .unverified)
        // Repeated unknowns prove the rule is not value-specific.
        #expect(try decoder.decode(VerificationState.self, from: trusted) == .unverified)
        #expect(try decoder.decode(VerificationState.self, from: quarantined) == .unverified)
    }

    @Test("Missing field on parent throws DecodingError (D-09 strict contract)")
    func missingFieldOnParentThrows() {
        // Inline wrapping struct — proves the absence of `verificationState`
        // on a parent surfaces as a hard DecodingError (key not found), NOT a
        // silent .unverified default. The decoder uses .convertFromSnakeCase
        // exactly as APIClient.defaultDecoder() does (Phase 7 contract).
        struct Party: Decodable {
            let verificationState: VerificationState
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let emptyParent = Data("{}".utf8)

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(Party.self, from: emptyParent)
        }
    }

    @Test("VerificationState exposes exactly 4 closed cases")
    func closedCaseSet() {
        let cases = VerificationState.allCases
        #expect(cases.count == 4)
        // Each named case is present.
        #expect(cases.contains(.verified))
        #expect(cases.contains(.pending))
        #expect(cases.contains(.unverified))
        #expect(cases.contains(.flagged))
    }
}
