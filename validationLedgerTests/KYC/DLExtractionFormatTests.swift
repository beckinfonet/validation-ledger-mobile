// validationLedgerTests/KYC/DLExtractionFormatTests.swift
// Requirement: KYC-03 — client-side driver's-license field format check.
// GREEN — implemented by plan 05-05.
//
// Exercises `DLFieldFormatValidator` — the pure, simulator-testable client-side
// format gate (D-05) behind the auto-rescan prompt. The live OCR / scan portion
// runs on the device lane (DLExtractionScannerDeviceTests) + HUMAN-UAT.

import Testing
import Foundation
@testable import validationLedger

@Suite("DLExtractionFormat — client-side DL field format check (KYC-03)")
struct DLExtractionFormatTests {

    /// A fixed reference instant so the not-in-the-past check is deterministic.
    private var referenceNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 16
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("KYC-03: a well-formed name / DL number / future expiry passes")
    func validFieldsPass() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan A. Carter",
            dlNumber: "D1234567",
            expiry: "08/14/2029",
            now: referenceNow
        )
        #expect(result == .valid)
        #expect(result.isValid)
    }

    @Test("KYC-03: an empty name is rejected")
    func emptyNameRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "   ",
            dlNumber: "D1234567",
            expiry: "08/14/2029",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for an empty name")
            return
        }
        #expect(errors.contains(.nameInvalid))
    }

    @Test("KYC-03: a name with digits / symbols is rejected (OCR misread)")
    func garbledNameRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "J0rdan #C@rter",
            dlNumber: "D1234567",
            expiry: "08/14/2029",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for a garbled name")
            return
        }
        #expect(errors.contains(.nameInvalid))
    }

    @Test("KYC-03: an expired-date expiry is rejected")
    func expiredExpiryRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan Carter",
            dlNumber: "D1234567",
            expiry: "01/02/2020",   // before referenceNow (2026-05-16)
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for an expired license")
            return
        }
        #expect(errors.contains(.expiryInPast))
    }

    @Test("KYC-03: an unparseable expiry string is rejected")
    func unparseableExpiryRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan Carter",
            dlNumber: "D1234567",
            expiry: "not-a-date",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for an unparseable expiry")
            return
        }
        #expect(errors.contains(.expiryUnparseable))
    }

    @Test("KYC-03: an empty DL number is rejected")
    func emptyDLNumberRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan Carter",
            dlNumber: "",
            expiry: "08/14/2029",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for an empty DL number")
            return
        }
        #expect(errors.contains(.dlNumberInvalid))
    }

    @Test("KYC-03: a DL number with punctuation is rejected")
    func punctuatedDLNumberRejected() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan Carter",
            dlNumber: "D-123-456",
            expiry: "08/14/2029",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for a punctuated DL number")
            return
        }
        #expect(errors.contains(.dlNumberInvalid))
    }

    @Test("KYC-03: multiple bad fields surface multiple errors at once")
    func multipleErrorsSurfaced() {
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "",
            dlNumber: "!!",
            expiry: "garbage",
            now: referenceNow
        )
        guard case let .invalid(errors) = result else {
            Issue.record("expected .invalid for three bad fields")
            return
        }
        #expect(errors.contains(.nameInvalid))
        #expect(errors.contains(.dlNumberInvalid))
        #expect(errors.contains(.expiryUnparseable))
    }

    @Test("KYC-03: a state DL number embedding letters is accepted (loose plausibility)")
    func alphanumericDLNumberAccepted() {
        // Per RESEARCH Assumption A5 the DL-number check is a loose plausibility
        // window, not a per-state regex — letters are valid.
        let validator = DLFieldFormatValidator()
        let result = validator.validate(
            name: "Jordan Carter",
            dlNumber: "X9Y8Z7654",
            expiry: "12/31/2030",
            now: referenceNow
        )
        #expect(result.isValid)
    }
}
