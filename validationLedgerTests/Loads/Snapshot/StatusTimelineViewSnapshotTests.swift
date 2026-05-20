// validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 71 (Wave 0 list).
//   - PATTERNS.md table row line 37 — closest analog
//     `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (PATTERNS E8).
//
// Shell covering the 6 primary-lifecycle current-state snapshots (Posted →
// Tendered → Accepted → Dispatched → In-Transit → Delivered) per D-17 plus
// the terminal `cancelled` card. Populated by Plan 05 when the
// `StatusTimelineView` production type lands.
//
// === D-18 reminder (side-states not surfaced) ===
// The timeline renders ONLY the primary 6-pill lifecycle. A rejected /
// expired event in `stateHistory` is intentionally invisible here. If a
// future test author is tempted to add side-state assertions, re-read
// 09-CONTEXT D-18 first — that surface is a future audit-history phase.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.

import XCTest
@testable import validationLedger

class StatusTimelineViewSnapshotTests: XCTestCase {

    func test_postedStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_tenderedStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_acceptedStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_dispatchedStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_inTransitStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_deliveredStepper_currentStateRendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }

    func test_cancelledTerminalCard_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 05")
    }
}
