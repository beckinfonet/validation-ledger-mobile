// validationLedgerTests/KYC/RejectionReasonCodeTests.swift
// Requirement: D-11 — rejection reason code → human copy mapping + unknown-code
// fallback. Turned GREEN by plan 05-02.
//
// Covers: each defined backend code string decodes to its enum case; a known
// code maps to a finalized localized sentence; an unknown/unmapped code degrades
// to the generic fallback sentence (never crashes, never surfaces the raw code);
// the enum is Decodable so it can be used directly where a code is decoded.

import Testing
import Foundation
@testable import validationLedger

@Suite("RejectionReasonCode — code→copy mapping + unknown fallback (D-11)")
struct RejectionReasonCodeTests {

    @Test("D-11: every defined backend code string decodes to its enum case")
    func everyDefinedCodeDecodes() throws {
        for code in RejectionReasonCode.allCases {
            let decoded = RejectionReasonCode(rawValue: code.rawValue)
            #expect(decoded == code)
        }
        // The controlled vocabulary is at least the RESEARCH example set.
        #expect(RejectionReasonCode.allCases.count >= 9)
    }

    @Test("D-11: a known code maps to a finalized localized copy sentence")
    func knownCodeMapsToCopy() {
        let copy = RejectionReasonCode.copy(for: "dl_front_glare")
        // Finalized, plain, action-oriented English — not the raw code.
        #expect(copy != "dl_front_glare")
        #expect(!copy.isEmpty)
        #expect(copy == RejectionReasonCode.dlFrontGlare.localizedCopy)
    }

    @Test("D-11: every defined code has non-empty localized copy distinct from its raw value")
    func everyCodeHasCopy() {
        for code in RejectionReasonCode.allCases {
            let copy = code.localizedCopy
            #expect(!copy.isEmpty)
            #expect(copy != code.rawValue)
        }
    }

    @Test("D-11: an unknown code falls back to the generic sentence, never the raw code")
    func unknownCodeFallsBackToGeneric() {
        let unknownCopy = RejectionReasonCode.copy(for: "some_future_code")
        // Degrades gracefully — never crashes, never returns the raw input.
        #expect(unknownCopy != "some_future_code")
        #expect(!unknownCopy.isEmpty)
        // It is the SAME generic sentence regardless of which unknown code.
        #expect(unknownCopy == RejectionReasonCode.copy(for: "another_unknown_code"))
    }

    @Test("D-11: RejectionReasonCode is Decodable from a JSON string")
    func decodableFromJSON() throws {
        let json = "\"face_not_centered\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RejectionReasonCode.self, from: json)
        #expect(decoded == .faceNotCentered)
    }

    @Test("D-11: the unknown-code fallback path covers the known JSON-decode case too")
    func codeMapsToCopyWithUnknownFallback() {
        // Known code → its own copy.
        #expect(RejectionReasonCode.copy(for: "dl_expired") == RejectionReasonCode.dlExpired.localizedCopy)
        // Unknown code → generic, and the raw string never leaks.
        let generic = RejectionReasonCode.copy(for: "totally_made_up_code")
        #expect(generic != "totally_made_up_code")
        #expect(!generic.isEmpty)
    }
}
