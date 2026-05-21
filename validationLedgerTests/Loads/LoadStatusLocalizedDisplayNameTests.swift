// validationLedgerTests/Loads/LoadStatusLocalizedDisplayNameTests.swift
// Phase 10 Plan 01 Task 1 — TDD coverage for the additive
// `LoadStatus.localizedDisplayName` computed property (Pitfall 5 anchor).
//
// The Plan 04 terminal empty-state caption interpolates this string at
// `loads.actions.empty.terminal.format` (10-UI-SPEC.md lines 297-313). Pitfall 5
// in 10-RESEARCH.md mandates the lowercase, space-separated form — NEVER the
// raw enum rawValue (which would emit "in_transit" with the underscore).
//
// XCTest convention chosen to match the Loads/ folder's XCTest neighbors
// (LoadDetailViewControllerCompositionTests, etc.). Pure value-type assertion
// surface — no MockURLProtocol, no .serialized requirement.

import XCTest
@testable import validationLedger

final class LoadStatusLocalizedDisplayNameTests: XCTestCase {

    /// Pitfall 5 (10-RESEARCH.md) — naive implementation would pass the rawValue
    /// `"in_transit"` (with an underscore) directly to the empty-state format
    /// string. The localizedDisplayName MUST emit space-separated lowercase
    /// English for every case.
    func test_everyCaseReturnsNonEmptyString() {
        for status in LoadStatus.allCases {
            let display = status.localizedDisplayName
            XCTAssertFalse(
                display.isEmpty,
                "localizedDisplayName for \(status) must be non-empty"
            )
        }
    }

    /// Underscore-from-rawValue leakage guard — the rawValue forms
    /// `"in_transit"` and `"pod_captured"` MUST NEVER appear verbatim in
    /// the displayed string. (Pitfall 5 regression lock.)
    func test_noUnderscoreLeaksFromRawValue() {
        for status in LoadStatus.allCases {
            let display = status.localizedDisplayName
            XCTAssertFalse(
                display.contains("_"),
                "localizedDisplayName for \(status) leaked an underscore (\"\(display)\") — rawValue must NOT pass through verbatim"
            )
        }
    }

    /// English fallback values per the Plan 01 Task 1 <action> table.
    func test_englishFallbackValues_lowercaseSpaceSeparated() {
        XCTAssertEqual(LoadStatus.draft.localizedDisplayName,        "draft")
        XCTAssertEqual(LoadStatus.posted.localizedDisplayName,       "posted")
        XCTAssertEqual(LoadStatus.tendered.localizedDisplayName,     "tendered")
        XCTAssertEqual(LoadStatus.accepted.localizedDisplayName,     "accepted")
        XCTAssertEqual(LoadStatus.dispatched.localizedDisplayName,   "dispatched")
        XCTAssertEqual(LoadStatus.inTransit.localizedDisplayName,    "in transit")
        XCTAssertEqual(LoadStatus.delivered.localizedDisplayName,    "delivered")
        XCTAssertEqual(LoadStatus.rejected.localizedDisplayName,     "rejected")
        XCTAssertEqual(LoadStatus.expired.localizedDisplayName,      "expired")
        XCTAssertEqual(LoadStatus.cancelled.localizedDisplayName,    "cancelled")
        XCTAssertEqual(LoadStatus.podCaptured.localizedDisplayName,  "pod captured")
        XCTAssertEqual(LoadStatus.invoiced.localizedDisplayName,     "invoiced")
        XCTAssertEqual(LoadStatus.funded.localizedDisplayName,       "funded")
    }

    /// Every string is lowercase (no upper-case letters slipped through the
    /// fallback table) — the Plan 04 empty-state caption interpolates inline
    /// and would render "We couldn't find any Tendered loads." (wrong) if a
    /// case slipped through capitalized.
    func test_allStringsAreLowercase() {
        for status in LoadStatus.allCases {
            let display = status.localizedDisplayName
            XCTAssertEqual(
                display,
                display.lowercased(),
                "localizedDisplayName for \(status) must be lowercase (was \"\(display)\")"
            )
        }
    }
}
