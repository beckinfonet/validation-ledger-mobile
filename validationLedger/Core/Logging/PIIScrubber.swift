// validationLedger/Core/Logging/PIIScrubber.swift
// Hybrid PII scrubber per D-16: structured path preferred, string path is pressure valve.
// Both paths route through the same redaction rules — string path cannot bypass.

import Foundation

public struct PIIScrubber: Sendable {
    public static let `default` = PIIScrubber()

    public init() {}

    /// Structured path — redacts per-field per the rule table.
    /// Note: Phase 3 D-23 / GEO-03 removed the `.coordinates` LogField case entirely;
    /// coordinates can no longer reach this switch by construction (they flow through
    /// `Core/Identity/PlatformPayloadField` to networking endpoint payloads only).
    /// The string-path fallback below still regex-sweeps for coordinate-shaped
    /// substrings (lat,lon pairs) in free-form log strings as a secondary defense.
    public func scrub(_ fields: [LogField: Any]) -> [LogField: Any] {
        var out: [LogField: Any] = [:]
        for (field, value) in fields {
            switch field {
            case .phone:
                if let s = value as? String { out[field] = Self.maskPhone(s) }
            case .driversLicense:
                out[field] = "[REDACTED:DL]"
            case .fullName:
                if let s = value as? String { out[field] = Self.initialOnly(s) }
            case .mcNumber:
                out[field] = "[REDACTED:MC]"
            case .dotNumber:
                out[field] = "[REDACTED:DOT]"
            case .email:
                if let s = value as? String { out[field] = Self.maskEmail(s) }
            case .count, .duration, .event:
                out[field] = value  // safe — pass through
            }
        }
        return out
    }

    /// String path — regex sweep for known PII patterns; forced route for string-based
    /// Logger calls so they cannot bypass redaction.
    public func scrubString(_ message: String) -> String {
        var s = message

        // Phone — E.164
        let phonePattern = #"\+?[1-9]\d{9,14}"#
        s = Self.regexReplace(s, pattern: phonePattern) { match in
            Self.maskPhone(match)
        }

        // Coordinates — "37.7749,-122.4194" style
        let coordsPattern = #"-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}"#
        s = Self.regexReplace(s, pattern: coordsPattern) { _ in "[REDACTED:GPS]" }

        // Email
        let emailPattern = #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#
        s = Self.regexReplace(s, pattern: emailPattern) { Self.maskEmail($0) }

        // Full name — requires ≥2 consecutive Capitalized words (Jane Doe, John Q Public).
        // Single Capitalized words (California, Broker) pass through to avoid over-redaction
        // of domain terms. Trade-off closes CR-02a / D-16 ("string-based calls cannot bypass
        // redaction") at the cost of redacting multi-word Proper Nouns in log messages.
        let namePattern = #"\b[A-Z][a-z]+(?:\s[A-Z][a-z]+)+\b"#
        s = Self.regexReplace(s, pattern: namePattern) { Self.initialOnly($0) }

        // MC/DOT
        let mcDotPattern = #"\b(MC|DOT)[- ]?\d{5,8}\b"#
        s = Self.regexReplace(s, pattern: mcDotPattern, options: [.caseInsensitive]) { match in
            match.lowercased().hasPrefix("mc") ? "[REDACTED:MC]" : "[REDACTED:DOT]"
        }

        // DL-ish patterns (state-code + digits)
        let dlPattern = #"\b[A-Z]{1,2}[0-9]{5,8}\b"#
        s = Self.regexReplace(s, pattern: dlPattern) { _ in "[REDACTED:DL]" }

        return s
    }

    // MARK: - Private helpers

    private static func maskPhone(_ s: String) -> String {
        // "+14155550129" → "+1415•••0129" (first 5 + last 4, middle masked)
        guard s.count >= 9 else { return "[REDACTED:PHONE]" }
        let first = s.prefix(5)
        let last  = s.suffix(4)
        return "\(first)•••\(last)"
    }

    private static func initialOnly(_ s: String) -> String {
        // "Jane Doe" → "J. D."
        let parts = s.split(separator: " ")
        guard !parts.isEmpty else { return "[REDACTED:NAME]" }
        return parts.map { part -> String in
            guard let first = part.first else { return "" }
            return "\(first)."
        }.joined(separator: " ")
    }

    private static func maskEmail(_ s: String) -> String {
        // "jane.doe@acme.com" → "j•••e@acme.com" (first + last of local part)
        let parts = s.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return "[REDACTED:EMAIL]" }
        let local = parts[0]
        let domain = parts[1]
        guard local.count >= 2 else { return "[REDACTED:EMAIL]" }
        let first = local.first!
        let last = local.last!
        return "\(first)•••\(last)@\(domain)"
    }

    private static func regexReplace(
        _ input: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        let matches = regex.matches(in: input, range: range).reversed()
        var out = input
        for match in matches {
            guard let matchRange = Range(match.range, in: out) else { continue }
            let original = String(out[matchRange])
            let replaced = transform(original)
            out.replaceSubrange(matchRange, with: replaced)
        }
        return out
    }
}
