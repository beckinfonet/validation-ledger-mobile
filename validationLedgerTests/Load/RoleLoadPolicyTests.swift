// validationLedgerTests/Load/RoleLoadPolicyTests.swift
// Phase 7 LOAD-02 (D-03, D-04, D-05, D-06): exhaustive coverage of the
// RoleLoadPolicy.actions(for:status:) resolver — the Roadmap SC #2 5×13
// matrix sweep + the Factoring-empty-everywhere invariant + the
// Shipper≡Broker / Carrier≡Dispatch identity rows + 6 specific-transition
// assertions per D-03/D-04/D-05.
//
// This suite does NOT touch MockURLProtocol — it tests a pure function over
// the closed (Role, LoadStatus) → [LoadAction] table. No `.serialized`
// suite marker required (analog: KYC/RejectionReasonCodeTests is also a
// pure-vocabulary suite without .serialized).
//
// LoadAction is `String, ..., CaseIterable` (Plan 01 Task 1) — Swift
// synthesizes `Equatable` for String-raw enums automatically, which makes
// `[LoadAction]` arrays comparable with `==` element-wise. No additional
// conformance change is needed.

import Testing
import Foundation
@testable import validationLedger

@Suite("RoleLoadPolicy exhaustive 5 × 13 matrix (D-06)")
struct RoleLoadPolicyTests {

    // MARK: - Test 1 — Totality (Roadmap SC #2 5 × 13 sweep)

    @Test("Policy table is total: every (Role, LoadStatus) pair returns a defined [LoadAction] without crashing")
    func policyIsTotal() {
        // Exhaustive sweep — 5 roles × 13 statuses = 65 calls. Each call
        // MUST return a defined value (possibly empty) without trapping or
        // throwing. The compiler's exhaustive-switch checker already
        // guarantees this at build time; this test catches any future
        // accidental introduction of `fatalError`/`preconditionFailure`
        // in the resolver body.
        for role in Role.allCases {
            for status in LoadStatus.allCases {
                _ = RoleLoadPolicy.actions(for: role, status: status)
            }
        }
        #expect(true) // reached without crash — 5 × 13 = 65 calls completed
    }

    // MARK: - Test 2 — Factoring-empty invariant (D-06)

    @Test("Factoring returns empty action set for every LoadStatus (D-06)")
    func factoringIsEmptyForEveryStatus() {
        for status in LoadStatus.allCases {
            #expect(
                RoleLoadPolicy.actions(for: .factoring, status: status).isEmpty,
                "Factoring must be view-only for every status (D-06) — failed at \(status)"
            )
        }
    }

    // MARK: - Test 3 — Shipper ≡ Broker identity (D-06)

    @Test("Shipper and Broker return identical action sets for every LoadStatus (D-06)")
    func shipperEqualsBrokerForEveryStatus() {
        for status in LoadStatus.allCases {
            let shipperActions = RoleLoadPolicy.actions(for: .shipper, status: status)
            let brokerActions = RoleLoadPolicy.actions(for: .broker, status: status)
            #expect(
                shipperActions == brokerActions,
                "D-06 — Shipper ≡ Broker must hold for every status. At \(status): shipper=\(shipperActions), broker=\(brokerActions)"
            )
        }
    }

    // MARK: - Test 4 — Carrier ≡ Dispatch identity (D-06)

    @Test("Carrier and Dispatch return identical action sets for every LoadStatus (D-06)")
    func carrierEqualsDispatchForEveryStatus() {
        for status in LoadStatus.allCases {
            let carrierActions = RoleLoadPolicy.actions(for: .carrier, status: status)
            let dispatchActions = RoleLoadPolicy.actions(for: .dispatch, status: status)
            #expect(
                carrierActions == dispatchActions,
                "D-06 — Carrier ≡ Dispatch must hold for every status. At \(status): carrier=\(carrierActions), dispatch=\(dispatchActions)"
            )
        }
    }

    // MARK: - Test 5 — Specific transitions per D-03 / D-04 / D-05

    @Test("Specific transitions are exactly the documented actions (D-03/D-04/D-05)")
    func specificTransitionsMatchTruthTable() {
        // D-03 — post moves draft → posted (single ownership action).
        #expect(RoleLoadPolicy.actions(for: .shipper, status: .draft) == [.post])

        // D-03 — tender gate is posted-only; cancel always available.
        #expect(RoleLoadPolicy.actions(for: .broker, status: .posted) == [.tender, .cancel])

        // D-03 — carrier decision point on an active tender.
        #expect(RoleLoadPolicy.actions(for: .carrier, status: .tendered) == [.accept, .reject])

        // D-05 — single advanceStatus action across accepted / dispatched / inTransit.
        #expect(RoleLoadPolicy.actions(for: .dispatch, status: .accepted) == [.advanceStatus])

        // Terminal — delivered has no actions for any role.
        #expect(RoleLoadPolicy.actions(for: .shipper, status: .delivered) == [])

        // Terminal — cancelled has no actions for any role.
        #expect(RoleLoadPolicy.actions(for: .broker, status: .cancelled) == [])
    }

    // MARK: - Coverage sanity — sweep size matches Roadmap SC #2

    @Test("Exhaustive sweep covers exactly 5 × 13 = 65 (Role, LoadStatus) pairs")
    func sweepCovers65Pairs() {
        var pairCount = 0
        for _ in Role.allCases {
            for _ in LoadStatus.allCases {
                pairCount += 1
            }
        }
        #expect(Role.allCases.count == 5, "Roadmap SC #2 expects 5 roles")
        #expect(LoadStatus.allCases.count == 13, "Roadmap SC #2 expects 13 LoadStatus cases")
        #expect(pairCount == 65, "Roadmap SC #2 expects exactly 5 × 13 = 65 (Role, LoadStatus) pairs")
    }
}
