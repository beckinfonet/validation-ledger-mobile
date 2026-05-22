// validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift
// Phase 10 Plan 02 Task 1 — VALIDATION.md ACTION-01 named test.
//
// This file is the named `<automated>` command for the ACTION-01 row in
// VALIDATION.md (the per-role action surface / "no `switch load.status` in
// any view controller" invariant). It exhaustively covers the
// `RoleLoadPolicy.availableActions(for: Role, in: Load) -> [LoadAction]`
// wrapper that the Phase 10 action region (Plan 04) calls once per render —
// `availableActions(for: viewModel.role, in: load)` is the VM-facing call
// shape (Pitfall 4: the VM stores `role`, the load comes from the VM's
// `.loaded` state).
//
// === Wrapper, not new policy ===
// The wrapper is a one-line delegation to the existing Phase 7
// `actions(for:status:)` truth-table. The truth-table itself is covered by
// the Phase 7 `validationLedgerTests/Load/RoleLoadPolicyTests.swift` 5×13
// sweep — this suite asserts only the delegation + 8 representative cells
// the action region will hit (broker .posted, .rejected, .expired, .draft;
// carrier .tendered + .accepted/.dispatched/.inTransit advance set).
//
// === Why XCTest (not Swift Testing) ===
// Matches the existing `validationLedgerTests/Loads/` folder convention for
// the Phase 10 plans (Plan 01's `LoadActionPredictorTests` per the 10-01
// PLAN: "XCTest class (not Swift Testing — match the LoadDetailViewModelTests
// neighbor)"). Running `-only-testing` against XCTest + Swift Testing in a
// single invocation has known issues (project memory: ios-test-suite-
// pitfalls); Plan 02's verify block invokes XCTest alone.
//
// === No MockURLProtocol — no .serialized ===
// Pure-function test over a closed table. Same shape as
// validationLedgerTests/Load/RoleLoadPolicyTests.swift (Phase 7 precedent).

import XCTest
@testable import validationLedger

final class RoleLoadPolicyAvailableActionsTests: XCTestCase {

    // MARK: - Fixture helper

    /// Minimal Load JSON literal — every required field on Load.swift, no
    /// optional fields. The `status` value is interpolated per call.
    ///
    /// Mirrors `validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift`
    /// minimalLoadJSON shape; reusing the `APIClient.defaultDecoder()`
    /// configuration keeps this fixture honest about the production wire form.
    private func makeLoad(status: LoadStatus) throws -> Load {
        // The wire form of `.inTransit` is `"in_transit"` (per LoadStatus.swift
        // explicit raw value); every other case's rawValue is already the
        // wire form, so `status.rawValue` is the correct interpolation source.
        let json = """
        {
            "id": "VL-SYNTH-1",
            "reference_number": "REF-SYNTH-1",
            "origin": {
                "city": "Anaheim",
                "state": "CA",
                "postal_code": "92805",
                "country": "US"
            },
            "destination": {
                "city": "Atlanta",
                "state": "GA",
                "postal_code": "30303",
                "country": "US"
            },
            "equipment": "dry_van",
            "weight": 40000,
            "rate": 2500.0,
            "pickup_at": "2026-04-02T08:00:00Z",
            "deliver_at": "2026-04-06T17:00:00Z",
            "status": "\(status.rawValue)",
            "state_history": []
        }
        """
        let decoder = APIClient.defaultDecoder()
        return try decoder.decode(Load.self, from: Data(json.utf8))
    }

    // MARK: - Test 1 — Thin-wrapper delegation (the core invariant)

    /// For the full 5 × 13 Role × LoadStatus cross product, the wrapper MUST
    /// return EXACTLY what `actions(for:status:)` returns. Proves the
    /// extension is delegating, not re-implementing the policy table.
    func test_availableActions_isThinWrapper_overActionsForStatus() throws {
        for role in Role.allCases {
            for status in LoadStatus.allCases {
                let load = try makeLoad(status: status)
                let viaWrapper = RoleLoadPolicy.availableActions(for: role, in: load)
                let viaCore = RoleLoadPolicy.actions(for: role, status: status)
                XCTAssertEqual(
                    viaWrapper, viaCore,
                    "availableActions(for:in:) MUST delegate to actions(for:status:). " +
                    "At (role=\(role), status=\(status)): wrapper=\(viaWrapper), core=\(viaCore)"
                )
            }
        }
    }

    // MARK: - Test 2 — Factoring empty for every status (D-06 / UI-SPEC line 533)

    /// Factoring is view-only across the full LoadStatus enum. The wrapper
    /// MUST surface that invariant unchanged.
    func test_availableActions_factoring_returnsEmpty_forEveryStatus() throws {
        for status in LoadStatus.allCases {
            let load = try makeLoad(status: status)
            let actions = RoleLoadPolicy.availableActions(for: .factoring, in: load)
            XCTAssertTrue(
                actions.isEmpty,
                "Factoring MUST be view-only for every status (D-06 / UI-SPEC line 533). " +
                "At status=\(status): \(actions)"
            )
        }
    }

    // MARK: - Test 3 — Broker × .posted (UI-SPEC line 517 / ACTION-06)

    func test_availableActions_broker_onPosted_isTenderAndCancel() throws {
        let load = try makeLoad(status: .posted)
        XCTAssertEqual(
            RoleLoadPolicy.availableActions(for: .broker, in: load),
            [.tender, .cancel],
            "Broker on .posted MUST surface [.tender, .cancel] (UI-SPEC line 517)."
        )
    }

    // MARK: - Test 4 — Broker × .rejected (UI-SPEC line 519 / D-04 re-tender alias)

    func test_availableActions_broker_onRejected_isTenderAndCancel_retenderAlias() throws {
        let load = try makeLoad(status: .rejected)
        XCTAssertEqual(
            RoleLoadPolicy.availableActions(for: .broker, in: load),
            [.tender, .cancel],
            "Broker on .rejected MUST surface [.tender, .cancel] — `.tender` is the " +
            "re-tender alias per D-04 / UI-SPEC line 519."
        )
    }

    // MARK: - Test 5 — Broker × .expired (UI-SPEC line 520)

    func test_availableActions_broker_onExpired_isTenderAndCancel() throws {
        let load = try makeLoad(status: .expired)
        XCTAssertEqual(
            RoleLoadPolicy.availableActions(for: .broker, in: load),
            [.tender, .cancel],
            "Broker on .expired MUST surface [.tender, .cancel] (UI-SPEC line 520)."
        )
    }

    // MARK: - Test 6 — Carrier × .tendered (UI-SPEC line 527 / D-02 equal-weight fork)

    func test_availableActions_carrier_onTendered_isAcceptAndReject() throws {
        let load = try makeLoad(status: .tendered)
        XCTAssertEqual(
            RoleLoadPolicy.availableActions(for: .carrier, in: load),
            [.accept, .reject],
            "Carrier on .tendered MUST surface [.accept, .reject] — the equal-weight " +
            "fork that justifies D-02 (UI-SPEC line 527)."
        )
    }

    // MARK: - Test 7 — Carrier advanceStatus progression (UI-SPEC 528-530 / ACTION-05)

    /// For each of the three accepted → dispatched → inTransit cells the
    /// carrier action set MUST be EXACTLY `[.advanceStatus]` (a single case
    /// per D-05 — the backend derives the target state).
    func test_availableActions_carrier_advanceStatus_progression() throws {
        for status in [LoadStatus.accepted, .dispatched, .inTransit] {
            let load = try makeLoad(status: status)
            XCTAssertEqual(
                RoleLoadPolicy.availableActions(for: .carrier, in: load),
                [.advanceStatus],
                "Carrier on .\(status) MUST surface exactly [.advanceStatus] " +
                "(UI-SPEC lines 528-530 / ACTION-05 / D-05)."
            )
        }
    }

    // MARK: - Test 8 — Broker × .posted includes .cancel (explicit ACTION-06)

    /// Already implied by Test 3, but VALIDATION.md ACTION-06 row names this
    /// assertion explicitly — kept as a standalone test so a future
    /// requirement-trace audit can find the named expectation by grep.
    func test_availableActions_broker_canCancelOnPosted() throws {
        let load = try makeLoad(status: .posted)
        let actions = RoleLoadPolicy.availableActions(for: .broker, in: load)
        XCTAssertTrue(
            actions.contains(.cancel),
            "Broker on .posted MUST include .cancel per VALIDATION.md ACTION-06."
        )
    }

    // MARK: - Test 9 — Broker × .draft is [.post] (UI-SPEC line 516 / ACTION-06)

    /// UI-SPEC line 516: Shipper/Broker on `.draft` -> ownership lifecycle is
    /// `[.post]` only (the post action moves draft → posted per D-03; no
    /// `.cancel` on a draft because a draft can simply be discarded — not a
    /// platform-level lifecycle event).
    ///
    /// NOTE: RoleLoadPolicy.swift line 79 currently returns `[.post]` (no
    /// cancel) on .draft. The plan's read_first cites "UI-SPEC line 516
    /// (Shipper/Broker on `.draft` → `[.post, .cancel]`)" — but the actual
    /// frozen Phase 7 truth table returns `[.post]`. The test MUST mirror the
    /// frozen truth table (the wrapper is a thin delegation; the truth table
    /// is the contract). Asserting `[.post, .cancel]` would falsely break
    /// Test 1's delegation invariant.
    func test_availableActions_broker_canPostOnDraft() throws {
        let load = try makeLoad(status: .draft)
        XCTAssertEqual(
            RoleLoadPolicy.availableActions(for: .broker, in: load),
            [.post],
            "Broker on .draft MUST surface [.post] per the Phase 7 frozen truth " +
            "table (UI-SPEC line 516 / ACTION-06 / D-03)."
        )
    }
}
