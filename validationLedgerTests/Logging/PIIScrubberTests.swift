// validationLedgerTests/Logging/PIIScrubberTests.swift
import Testing
@testable import validationLedger

@Suite("PIIScrubber — 6 category redaction contract")
struct PIIScrubberTests {
    let scrubber = PIIScrubber.default

    @Test("E.164 phone masked to first-3-last-2")
    func phoneMasked() {
        let out = scrubber.scrub([.phone: "+14155550129"])
        #expect(out[.phone] as? String == "+1415•••0129")
    }

    @Test("DL number fully redacted")
    func dlRedacted() {
        let out = scrubber.scrub([.driversLicense: "CA1234567"])
        #expect(out[.driversLicense] as? String == "[REDACTED:DL]")
    }

    @Test("Full name → initial-only")
    func fullNameMasked() {
        let out = scrubber.scrub([.fullName: "Jane Doe"])
        #expect(out[.fullName] as? String == "J. D.")
    }

    @Test("MC/DOT numbers fully redacted", arguments: [
        (LogField.mcNumber, "MC-123456", "[REDACTED:MC]"),
        (LogField.dotNumber, "DOT1234567", "[REDACTED:DOT]"),
    ])
    func mcDotRedacted(field: LogField, input: String, expected: String) {
        let out = scrubber.scrub([field: input])
        #expect(out[field] as? String == expected)
    }

    @Test("Email local-part masked")
    func emailMasked() {
        let out = scrubber.scrub([.email: "jane.doe@acme.com"])
        #expect(out[.email] as? String == "j•••e@acme.com")
    }

    @Test("Coordinates REMOVED entirely")
    func coordinatesRemoved() {
        let out = scrubber.scrub([.coordinates: "37.7749,-122.4194"])
        #expect(out[.coordinates] == nil, "coordinates must be removed, not masked")
    }

    @Test("String-path fallback catches inline PII")
    func stringPathCatchesPhone() {
        let out = scrubber.scrubString("User phone +14155550129 attempted OTP")
        #expect(!out.contains("+14155550129"))
        #expect(out.contains("+1415•••0129") || out.contains("[REDACTED:PHONE]"))
    }
}
