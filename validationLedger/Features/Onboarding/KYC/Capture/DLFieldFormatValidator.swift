// validationLedger/Features/Onboarding/KYC/Capture/DLFieldFormatValidator.swift
// Phase 5 Plan 05 — KYC-03 / D-05: the client-side driver's-license field
// format check.
//
// === WHY THIS IS A *CLIENT-SIDE* CHECK ONLY (KYC-03) ===
// The backend is authoritative for identity verification. This validator's only
// job is the D-05 "catch a bad scan early" gate: when `DataScannerViewController`
// produces obviously-malformed text, the extraction screen auto-prompts a rescan
// instead of advancing. It is NOT a per-state AAMVA parser — DL formats vary by
// US state (RESEARCH Assumption A5), so the DL-number check is a deliberately
// LOOSE plausibility range, not a regex. The uploaded photo is the authoritative
// artifact (D-05 / anti-feature A13) — these fields are never hand-editable.
//
// Pure value type — no UIKit, no camera, no I/O — so it is fully simulator-
// testable (`DLExtractionFormatTests`).

import Foundation

/// A single extracted-field format failure. Surfaced to the extraction screen
/// so a rescan is auto-prompted (D-05).
public enum DLFieldError: Equatable, Sendable {
    /// The name is empty, or contains characters outside letters/spaces/hyphens/
    /// apostrophes/periods.
    case nameInvalid
    /// The DL number is empty or outside the plausible length/charset range.
    case dlNumberInvalid
    /// The expiry could not be parsed as a date.
    case expiryUnparseable
    /// The expiry parsed but is in the past — the license is expired.
    case expiryInPast
}

/// The outcome of a client-side DL-field format check.
public enum DLFormatResult: Equatable, Sendable {
    /// Every field passed the plausibility check.
    case valid
    /// One or more fields failed — the extraction screen auto-prompts a rescan.
    case invalid([DLFieldError])

    /// Convenience — `true` when the result is `.valid`.
    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// Pure, simulator-testable client-side format check for `DataScanner`-extracted
/// driver's-license fields. KYC-03 / D-05 — the gate behind the auto-rescan.
public struct DLFieldFormatValidator {

    // MARK: - Plausibility bounds

    /// Loose DL-number length window. US state DL numbers run roughly 5–20
    /// characters; the window is intentionally generous (RESEARCH Assumption
    /// A5 — not a per-state regex).
    private static let minDLNumberLength = 4
    private static let maxDLNumberLength = 20

    /// The characters a plausible name may contain — letters, spaces, and the
    /// punctuation found in real names. Anything else means the OCR misread.
    private static let namePunctuation = CharacterSet(charactersIn: " -'.")

    /// The characters a plausible DL number may contain — letters and digits
    /// only (some states embed letters; none use punctuation).
    private static let dlNumberAllowed = CharacterSet.alphanumerics

    public init() {}

    // MARK: - Validation

    /// Run the client-side format check over the three extracted fields.
    ///
    /// - Parameters:
    ///   - name: the extracted full name.
    ///   - dlNumber: the extracted DL number.
    ///   - expiry: the extracted expiry string, as scanned.
    ///   - now: the reference instant for the not-in-the-past check. Injectable
    ///     so tests are deterministic; defaults to the current date.
    /// - Returns: `.valid`, or `.invalid` carrying every failed check.
    public func validate(
        name: String,
        dlNumber: String,
        expiry: String,
        now: Date = Date()
    ) -> DLFormatResult {
        var errors: [DLFieldError] = []

        if !isNamePlausible(name) {
            errors.append(.nameInvalid)
        }
        if !isDLNumberPlausible(dlNumber) {
            errors.append(.dlNumberInvalid)
        }

        switch parseExpiry(expiry) {
        case .none:
            errors.append(.expiryUnparseable)
        case let .some(date) where date < now:
            errors.append(.expiryInPast)
        case .some:
            break  // a future / today expiry is valid
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Field checks

    /// A plausible name is non-empty (after trimming) and contains only letters
    /// plus the small punctuation set real names use.
    private func isNamePlausible(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for scalar in trimmed.unicodeScalars {
            let isLetter = CharacterSet.letters.contains(scalar)
            let isPunct = Self.namePunctuation.contains(scalar)
            if !isLetter && !isPunct {
                return false
            }
        }
        return true
    }

    /// A plausible DL number is non-empty, within the loose length window, and
    /// alphanumeric. Deliberately not a per-state regex (Assumption A5).
    private func isDLNumberPlausible(_ dlNumber: String) -> Bool {
        let trimmed = dlNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minDLNumberLength,
              trimmed.count <= Self.maxDLNumberLength else {
            return false
        }
        for scalar in trimmed.unicodeScalars where !Self.dlNumberAllowed.contains(scalar) {
            return false
        }
        return true
    }

    /// Parse the expiry string against the date formats a US DL commonly prints.
    /// Returns `nil` when none of the formats match.
    private func parseExpiry(_ expiry: String) -> Date? {
        let trimmed = expiry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        // Common US DL expiry layouts — MM/dd/yyyy is the dominant one.
        let candidateFormats = ["MM/dd/yyyy", "MM-dd-yyyy", "yyyy-MM-dd", "MM/dd/yy"]
        for format in candidateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}
