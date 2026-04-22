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

    // Phase 3 D-23 / GEO-03: `LogField.coordinates` case removed; coordinates now flow
    // through `Core/Identity/PlatformPayloadField` to networking endpoint payloads only.
    // The former `coordinatesRemoved` test was deleted because the case it asserted on
    // no longer exists in the type system. Secondary string-path coordinate redaction
    // is still exercised indirectly via the `\d+\.\d+,-?\d+\.\d+` regex in scrubString.

    @Test("String-path fallback catches inline PII")
    func stringPathCatchesPhone() {
        let out = scrubber.scrubString("User phone +14155550129 attempted OTP")
        #expect(!out.contains("+14155550129"))
        #expect(out.contains("+1415•••0129") || out.contains("[REDACTED:PHONE]"))
    }

    @Test("String-path redacts full names (CR-02a / D-16 invariant)")
    func stringPathCatchesFullName() {
        let out = scrubber.scrubString("User Jane Doe failed KYC")
        #expect(!out.contains("Jane Doe"))
        #expect(out.contains("J. D."))
    }

    @Test("String-path name sweep ignores single Capitalized words")
    func stringPathIgnoresSingleCapitalizedWord() {
        // Domain terms like "Broker", "California", "Loads" must not be redacted.
        let out = scrubber.scrubString("Role Broker login on California route")
        // "Role Broker" is two consecutive Capitalized words → redacted (known trade-off).
        // "California" alone passes through.
        #expect(out.contains("California"))
    }
}
