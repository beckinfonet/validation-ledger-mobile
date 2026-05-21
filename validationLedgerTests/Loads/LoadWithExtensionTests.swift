// validationLedgerTests/Loads/LoadWithExtensionTests.swift
// Phase 10 Plan 01 Task 1 — TDD coverage for the additive
// `Load.with(status:respondByAt:)` extension that the LoadActionPredictor
// (Task 2) uses to construct fresh predicted Load values.
//
// Per RESEARCH § Open Question 1: same-module access — the helper is
// `internal func` consumed by `LoadActionPredictor` (same module). No public
// init exposure; Phase 7's public surface on Load is unchanged.
//
// The test decodes an existing fixture (`load-detail-VL-1001.json`) so the
// source Load carries the full shape — id, references, stops, equipment,
// weight, rate, status, stateHistory, respondByAt, tenderEligibility — and
// asserts that the returned Load differs ONLY in the two mutated fields.

import XCTest
@testable import validationLedger

final class LoadWithExtensionTests: XCTestCase {

    /// Decode VL-1001 — the canonical shared-world fixture (Phase 7 D-11) —
    /// through the production decoder configuration so the source Load is
    /// fully formed (stateHistory, every field exercised).
    private func loadFromFixture() throws -> Load {
        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        let response = try APIClient.defaultDecoder()
            .decode(LoadDetailEndpoint.Response.self, from: data)
        return response.load
    }

    // MARK: - Behavior (Plan 01 Task 1 <behavior> block)

    /// `load.with(status: .tendered, respondByAt: <date>)` returns a new Load
    /// with EXACTLY those two fields changed and every other field equal.
    func test_with_setsStatusAndRespondByAt_otherFieldsEqual() throws {
        let original = try loadFromFixture()
        let newDate = Date(timeIntervalSinceReferenceDate: 12345)
        let updated = original.with(status: .tendered, respondByAt: newDate)

        // Mutated fields
        XCTAssertEqual(updated.status, .tendered)
        XCTAssertEqual(updated.respondByAt, newDate)

        // Every other field unchanged
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.referenceNumber, original.referenceNumber)
        XCTAssertEqual(updated.origin.city, original.origin.city)
        XCTAssertEqual(updated.origin.state, original.origin.state)
        XCTAssertEqual(updated.origin.postalCode, original.origin.postalCode)
        XCTAssertEqual(updated.origin.country, original.origin.country)
        XCTAssertEqual(updated.destination.city, original.destination.city)
        XCTAssertEqual(updated.destination.state, original.destination.state)
        XCTAssertEqual(updated.destination.postalCode, original.destination.postalCode)
        XCTAssertEqual(updated.destination.country, original.destination.country)
        XCTAssertEqual(updated.equipment, original.equipment)
        XCTAssertEqual(updated.weight, original.weight)
        XCTAssertEqual(updated.rate, original.rate)
        XCTAssertEqual(updated.pickupAt, original.pickupAt)
        XCTAssertEqual(updated.deliverAt, original.deliverAt)
        XCTAssertEqual(updated.stateHistory.count, original.stateHistory.count)
        XCTAssertEqual(updated.tenderEligibility?.canTender, original.tenderEligibility?.canTender)
        XCTAssertEqual(updated.tenderEligibility?.disabledReason, original.tenderEligibility?.disabledReason)
    }

    /// The source Load is unchanged (value-type purity guard — Test 9 in Task 2
    /// will lock this same invariant at the predictor layer; this asserts it
    /// at the helper layer as a redundant safety net).
    func test_with_doesNotMutateSource() throws {
        let original = try loadFromFixture()
        let originalStatus = original.status
        let originalRespondByAt = original.respondByAt
        _ = original.with(status: .cancelled, respondByAt: Date())
        XCTAssertEqual(original.status, originalStatus)
        XCTAssertEqual(original.respondByAt, originalRespondByAt)
    }

    /// `load.with(status: .cancelled, respondByAt: nil)` correctly nils
    /// respondByAt even when the source carried a non-nil value (covers the
    /// .accept/.reject/.cancel arms in the predictor that clear the deadline).
    func test_with_clearsRespondByAtToNil() throws {
        let original = try loadFromFixture()
        // Synthesize a pre-state with a non-nil respondByAt by chaining
        // through the helper itself — this is safe because the test ABOVE
        // already locks the round-trip equality.
        let withDeadline = original.with(
            status: .tendered,
            respondByAt: Date(timeIntervalSinceReferenceDate: 99999)
        )
        XCTAssertNotNil(withDeadline.respondByAt)

        let cleared = withDeadline.with(status: .cancelled, respondByAt: nil)
        XCTAssertEqual(cleared.status, .cancelled)
        XCTAssertNil(cleared.respondByAt,
                     "with(...) must propagate explicit nil respondByAt — not silently keep the previous non-nil value")
    }
}
