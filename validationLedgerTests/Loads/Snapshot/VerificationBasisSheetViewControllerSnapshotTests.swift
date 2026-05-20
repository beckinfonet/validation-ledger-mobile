// validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 73 (Wave 0 list).
//   - PATTERNS.md table row line 39 — closest analog
//     `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (PATTERNS E8).
//   - RESEARCH §3 + §5 lines 401-504 — sheet snapshot configuration recipe.
//
// Shell covering the 4 scenarios pinned by D-09 + UI-SPEC:
//   1. clean × Carrier — KYC + device-binding + USDOT + 5+ priors.
//   2. clean × Shipper — KYC + device-binding + priors (USDOT row hidden).
//   3. caution × Broker (implicated) — inline "Why this party is flagged"
//      block per D-11.
//   4. compromised × Carrier (implicated) — same inline block, red treatment.
//
// Populated by Plan 07 (VerificationBasisSheetViewController production type).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Sheet
// snapshots render the sheet's `view` at the medium-detent representative
// size (~393×500 pt) — NOT the floating presentation chrome.

import XCTest
@testable import validationLedger

class VerificationBasisSheetViewControllerSnapshotTests: XCTestCase {

    func test_cleanCarrier_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 07")
    }

    func test_cleanShipper_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 07")
    }

    func test_cautionImplicatedBroker_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 07")
    }

    func test_compromisedImplicatedCarrier_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 07")
    }
}
