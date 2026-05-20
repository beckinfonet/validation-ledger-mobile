// validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 70 (Wave 0 list).
//   - PATTERNS.md table row line 36 — closest analog
//     `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (PATTERNS E8)
//     + `validationLedgerUITests/Loads/...LimitedTrustBannerTests` for the
//     banner-specific a11y assertions (when Plan 09 fills them in).
//
// Shell covering:
//   - `caution` verdict snapshot (yellow banner).
//   - `compromised` verdict snapshot (red banner).
//   - `clean` verdict unit-test: banner `isHidden == true`.
// Populated by Plan 09 (ChainIntegrityBannerView production type).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.
//
// === T-09-04 (PII) ===
// Wave 0 shells contain no data; Plan 09 will source banner copy from the
// Phase 7 fixture corpus (`chain_integrity.reason`) only.

import XCTest
@testable import validationLedger

class ChainIntegrityBannerViewSnapshotTests: XCTestCase {

    func test_cautionVerdict_rendersYellowBanner() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 09")
    }

    func test_compromisedVerdict_rendersRedBanner() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 09")
    }

    // Unit-style assertion (no snapshot): `.clean` verdict hides the banner.
    func test_cleanVerdict_bannerIsHidden() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 09")
    }
}
