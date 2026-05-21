// validationLedgerTests/Loads/LoadActionTitleResolverTests.swift
// Phase 10 Plan 02 Task 2 — pure-title-resolver coverage.
//
// `LoadActionTitleResolver` is the pure namespace the Phase 10 action region
// (Plan 04) calls AFTER the policy gate opens — it produces the visible
// button title for each `LoadAction`. The `.advanceStatus` action is the
// only one whose title depends on the load's current status (Dispatch /
// Mark in transit / Mark delivered per UI-SPEC line 277-280); every other
// action carries a status-independent string.
//
// The resolver lives in `validationLedger/Core/Load/` (NOT in
// `Features/Loads/`) so the Plan 04 lint test — which greps
// `Features/Loads/**/*ViewController.swift` and `**/*Cell.swift` for
// `switch.*\.status` — does NOT trip on the title computation. The
// `nextStatus(from:)` switch is exhaustive (no `default:` arm) so a future
// LoadStatus case lands here at compile time, not silently.
//
// === Why XCTest ===
// Matches the `validationLedgerTests/Loads/` Plan-10 convention (the sibling
// `RoleLoadPolicyAvailableActionsTests` is also XCTest); the verify block
// uses `-only-testing:validationLedgerTests/LoadActionTitleResolverTests`
// (XCTest folder-path syntax is broken on this project — confirmed empirically
// while running Task 1's RED phase; class-name only is the canonical form).

import XCTest
@testable import validationLedger

final class LoadActionTitleResolverTests: XCTestCase {

    // MARK: - Test 1 — Simple-action titles (UI-SPEC line 273-278)

    /// Every non-advanceStatus action returns the LOCKED English fallback
    /// title per UI-SPEC. `currentStatus: nil` is acceptable for these —
    /// the resolver MUST NOT trap on a nil status for status-independent
    /// actions.
    func test_title_simpleActions() {
        let cases: [(LoadAction, String)] = [
            (.tender, "Tender"),
            (.accept, "Accept"),
            (.reject, "Reject"),
            (.cancel, "Cancel load"),
            (.post,   "Post"),
        ]
        for (action, expected) in cases {
            XCTAssertEqual(
                LoadActionTitleResolver.title(for: action, currentStatus: nil),
                expected,
                "LoadActionTitleResolver.title(for: .\(action), currentStatus: nil) " +
                "MUST return the LOCKED UI-SPEC title \"\(expected)\"."
            )
        }
    }

    // MARK: - Tests 2-4 — `.advanceStatus` titles per UI-SPEC line 277-280

    /// .accepted → "Dispatch" (the carrier dispatches the load from accepted
    /// to dispatched).
    func test_title_advanceStatus_fromAccepted_isDispatch() {
        XCTAssertEqual(
            LoadActionTitleResolver.title(for: .advanceStatus, currentStatus: .accepted),
            "Dispatch",
            "title(.advanceStatus, .accepted) MUST be \"Dispatch\" (UI-SPEC line 278)."
        )
    }

    /// .dispatched → "Mark in transit".
    func test_title_advanceStatus_fromDispatched_isMarkInTransit() {
        XCTAssertEqual(
            LoadActionTitleResolver.title(for: .advanceStatus, currentStatus: .dispatched),
            "Mark in transit",
            "title(.advanceStatus, .dispatched) MUST be \"Mark in transit\" (UI-SPEC line 279)."
        )
    }

    /// .inTransit → "Mark delivered".
    func test_title_advanceStatus_fromInTransit_isMarkDelivered() {
        XCTAssertEqual(
            LoadActionTitleResolver.title(for: .advanceStatus, currentStatus: .inTransit),
            "Mark delivered",
            "title(.advanceStatus, .inTransit) MUST be \"Mark delivered\" (UI-SPEC line 280)."
        )
    }

    // MARK: - Tests 5-6 — `.advanceStatus` fallback (defensive)

    /// The policy gate prevents `.advanceStatus` from rendering on `.posted`
    /// (carrier on .posted has no actions), but the resolver MUST NOT crash
    /// if it sees that combination — return a non-empty generic fallback so
    /// any out-of-band caller gets something rather than a trap.
    func test_title_advanceStatus_fromOtherStatus_returnsGenericFallback() {
        let title = LoadActionTitleResolver.title(for: .advanceStatus, currentStatus: .posted)
        XCTAssertFalse(
            title.isEmpty,
            "title(.advanceStatus, .posted) MUST return a non-empty fallback (defensive)."
        )
        // Specifically the generic "Advance" — locked here so the fallback
        // is observable to the lint and stays stable across localization.
        XCTAssertEqual(
            title,
            "Advance",
            "title(.advanceStatus, .posted) MUST return the generic \"Advance\" fallback."
        )
    }

    /// `currentStatus: nil` MUST also return the generic fallback (never
    /// trap on a nil status).
    func test_title_advanceStatus_currentStatusNil_returnsGenericFallback() {
        XCTAssertEqual(
            LoadActionTitleResolver.title(for: .advanceStatus, currentStatus: nil),
            "Advance",
            "title(.advanceStatus, nil) MUST return the generic \"Advance\" fallback."
        )
    }

    // MARK: - Tests 7-10 — `nextStatus(from:)` pure helper

    /// .accepted → .dispatched.
    func test_nextStatus_fromAccepted_isDispatched() {
        XCTAssertEqual(
            LoadActionTitleResolver.nextStatus(from: .accepted),
            .dispatched,
            "nextStatus(from: .accepted) MUST be .dispatched."
        )
    }

    /// .dispatched → .inTransit.
    func test_nextStatus_fromDispatched_isInTransit() {
        XCTAssertEqual(
            LoadActionTitleResolver.nextStatus(from: .dispatched),
            .inTransit,
            "nextStatus(from: .dispatched) MUST be .inTransit."
        )
    }

    /// .inTransit → .delivered.
    func test_nextStatus_fromInTransit_isDelivered() {
        XCTAssertEqual(
            LoadActionTitleResolver.nextStatus(from: .inTransit),
            .delivered,
            "nextStatus(from: .inTransit) MUST be .delivered."
        )
    }

    /// Every other LoadStatus → nil. Iterate the full enum so a future
    /// LoadStatus case forces an explicit decision (the resolver's exhaustive
    /// switch already gives compile-time enforcement; this test guards
    /// against an accidental "return self" or default-arm regression).
    func test_nextStatus_fromOtherStatus_isNil() {
        let nonAdvanceStatuses: [LoadStatus] = LoadStatus.allCases.filter {
            $0 != .accepted && $0 != .dispatched && $0 != .inTransit
        }
        for status in nonAdvanceStatuses {
            XCTAssertNil(
                LoadActionTitleResolver.nextStatus(from: status),
                "nextStatus(from: .\(status)) MUST be nil — only the three " +
                "advance cells (accepted/dispatched/inTransit) advance."
            )
        }
    }
}
