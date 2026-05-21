// validationLedgerTests/Loads/LoadActionPredictorTests.swift
//
// Phase 10 Plan 01 Task 2 — exhaustive coverage of the pure
// `LoadActionPredictor.predict(load:action:body:) -> Load` function.
//
// Locked targets (10-01-PLAN.md <behavior>):
//   Test 1  — .post on .draft predicts .posted.
//   Test 2  — .tender on .posted predicts .tendered + body.respondByAt (Pitfall 3).
//   Test 3  — .tender on .rejected predicts .tendered (D-04 retender alias).
//   Test 4  — .tender on .expired predicts .tendered (D-04 retender alias).
//   Test 5  — .accept on .tendered predicts .accepted + respondByAt = nil.
//   Test 6  — .reject on .tendered predicts .rejected + respondByAt = nil
//             (transitional visible state; server may return .posted directly).
//   Test 7  — .cancel from every non-terminal status predicts .cancelled
//             + respondByAt = nil.
//   Test 8  — .advanceStatus walks the canonical accepted → dispatched →
//             inTransit → delivered ladder.
//   Test 9  — pure-function purity: source Load.status is unchanged.
//   Test 10 — out-of-policy combination returns current unchanged
//             (defensive no-op contract).
//
// File-shape analog: XCTest convention chosen to match the Loads/ folder's
// XCTest neighbors (LoadDetailViewControllerCompositionTests, etc.). All
// fixtures are built from a single file-private `makeLoad(status:respondByAt:)`
// helper that decodes a minimal JSON literal through APIClient.defaultDecoder()
// — matches LoadListEnvelopeDecodeTests' synthesized-JSON convention so the
// test-side decoder configuration mirrors the production decoder exactly.
//
// === Predictor contract ===
//   The predictor TRUSTS the policy gate: a call with an out-of-policy
//   (action, status) combination is a contract bug in the caller and the
//   predictor returns `current` unchanged (Test 10). The defensive no-op
//   contains the blast radius without crashing the in-flight VM transition.

import XCTest
@testable import validationLedger

final class LoadActionPredictorTests: XCTestCase {

    // MARK: - Fixture helper (file-private; mirrors LoadListEnvelopeDecodeTests synthesized-JSON pattern)

    /// Build a Load test double via the production decoder. The JSON literal
    /// is minimal-valid — every required field on Load.swift, every field
    /// the predictor cares about overrideable via the `status` and
    /// `respondByAt` arguments. Empty `state_history` and `tender_eligibility`
    /// omitted are both safe — `stateHistory` requires the key but accepts
    /// `[]`; `tender_eligibility` is `Decodable` optional and tolerates a
    /// missing key per the synthesized `decodeIfPresent`.
    ///
    /// `respondByAt` is wired as an ISO-8601 string when non-nil, omitted
    /// when nil (Load.respondByAt is `Date?` — `decodeIfPresent` returns nil
    /// for the missing key).
    ///
    /// `@MainActor` matches the project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor` — `Load`'s synthesized `Decodable` conformance is
    /// main-actor isolated in this codebase, so the decode call site must be
    /// main-actor too (Swift 6 enforces this; Swift 5 mode warns).
    @MainActor
    private func makeLoad(status: LoadStatus, respondByAt: Date? = nil) throws -> Load {
        let respondByAtJSON: String = {
            guard let respondByAt else { return "" }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let iso = formatter.string(from: respondByAt)
            return ",\n  \"respond_by_at\": \"\(iso)\""
        }()

        let json = """
        {
          "id": "VL-PRED-1",
          "reference_number": "REF-PRED-1",
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
          "weight": 42500,
          "rate": 3850.0,
          "pickup_at": "2026-04-02T08:00:00Z",
          "deliver_at": "2026-04-06T17:00:00Z",
          "status": "\(status.rawValue)",
          "state_history": []\(respondByAtJSON)
        }
        """
        return try APIClient.defaultDecoder().decode(Load.self, from: Data(json.utf8))
    }

    /// Build a `LoadActionEndpoint.RequestBody` with `respondByAt` populated
    /// — the predictor's `.tender` arm reads `body.respondByAt` (Pitfall 3).
    private func tenderBody(respondByAt: Date) -> LoadActionEndpoint.RequestBody {
        LoadActionEndpoint.RequestBody(
            actorRole: .broker,
            targetPartyID: "party-carrier-acme",
            respondByAt: respondByAt,
            note: nil
        )
    }

    // MARK: - Test 1 — .post on .draft

    @MainActor
    func test_post_onDraft_predictsPosted() throws {
        let current = try makeLoad(status: .draft)
        let predicted = LoadActionPredictor.predict(load: current, action: .post, body: nil)
        XCTAssertEqual(predicted.status, .posted)
        XCTAssertNil(predicted.respondByAt,
                     ".post on .draft must NOT carry a respondByAt — nothing tender-related yet")
    }

    // MARK: - Test 2 — .tender on .posted (Pitfall 3: body.respondByAt, NOT load.respondByAt)

    @MainActor
    func test_tender_onPosted_predictsTendered_withBodyRespondByAt() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let current = try makeLoad(status: .posted, respondByAt: nil)
        XCTAssertNil(current.respondByAt, "pre-tap posted load has no respondByAt")

        let predicted = LoadActionPredictor.predict(
            load: current,
            action: .tender,
            body: tenderBody(respondByAt: deadline)
        )
        XCTAssertEqual(predicted.status, .tendered)
        XCTAssertEqual(predicted.respondByAt, deadline,
                       "Pitfall 3: predictor MUST read body.respondByAt (the broker's chosen deadline), NOT load.respondByAt (which is nil on a pre-tap posted load)")
    }

    // MARK: - Test 3 — .tender on .rejected (D-04 retender alias)

    @MainActor
    func test_tender_onRejected_predictsTendered_identicalToPosted() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let current = try makeLoad(status: .rejected)
        let predicted = LoadActionPredictor.predict(
            load: current,
            action: .tender,
            body: tenderBody(respondByAt: deadline)
        )
        XCTAssertEqual(predicted.status, .tendered,
                       "D-04 / ACTION-02: retender = .tender on .rejected predicts .tendered (no separate .retender action)")
        XCTAssertEqual(predicted.respondByAt, deadline,
                       "retender on .rejected carries body.respondByAt identically to .tender on .posted")
    }

    // MARK: - Test 4 — .tender on .expired (D-04 retender alias)

    @MainActor
    func test_tender_onExpired_predictsTendered_identicalToPosted() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let current = try makeLoad(status: .expired)
        let predicted = LoadActionPredictor.predict(
            load: current,
            action: .tender,
            body: tenderBody(respondByAt: deadline)
        )
        XCTAssertEqual(predicted.status, .tendered,
                       "D-04 / ACTION-02: retender = .tender on .expired predicts .tendered")
        XCTAssertEqual(predicted.respondByAt, deadline,
                       "retender on .expired carries body.respondByAt identically to .tender on .posted")
    }

    // MARK: - Test 5 — .accept on .tendered

    @MainActor
    func test_accept_onTendered_predictsAccepted_clearsRespondByAt() throws {
        let priorDeadline = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let current = try makeLoad(status: .tendered, respondByAt: priorDeadline)
        let predicted = LoadActionPredictor.predict(load: current, action: .accept, body: nil)
        XCTAssertEqual(predicted.status, .accepted)
        XCTAssertNil(predicted.respondByAt,
                     ".accept must clear respondByAt — the tender deadline is no longer in flight")
    }

    // MARK: - Test 6 — .reject on .tendered (server may return .posted directly per D-04)

    @MainActor
    func test_reject_onTendered_predictsRejected_clearsRespondByAt() throws {
        let priorDeadline = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let current = try makeLoad(status: .tendered, respondByAt: priorDeadline)
        let predicted = LoadActionPredictor.predict(load: current, action: .reject, body: nil)
        XCTAssertEqual(predicted.status, .rejected,
                       "ACTION-04: predicted transitional state is .rejected; server is authoritative and may return .posted directly per D-04")
        XCTAssertNil(predicted.respondByAt,
                     ".reject must clear respondByAt — the tender is no longer in flight")
    }

    // MARK: - Test 7 — .cancel from every non-terminal status

    @MainActor
    func test_cancel_fromEveryNonTerminalStatus_predictsCancelled() throws {
        let nonTerminal: [LoadStatus] = [
            .draft, .posted, .tendered, .accepted,
            .dispatched, .inTransit, .rejected, .expired
        ]
        for status in nonTerminal {
            let current = try makeLoad(
                status: status,
                respondByAt: status == .tendered
                    ? Date(timeIntervalSinceReferenceDate: 6_000_000)
                    : nil
            )
            let predicted = LoadActionPredictor.predict(load: current, action: .cancel, body: nil)
            XCTAssertEqual(predicted.status, .cancelled,
                           ".cancel from \(status) must predict .cancelled (UI-SPEC Per-Action State / Visibility Matrix)")
            XCTAssertNil(predicted.respondByAt,
                         ".cancel must clear respondByAt regardless of source status (.cancel from \(status))")
        }
    }

    // MARK: - Test 8 — .advanceStatus across the three forward transitions (ACTION-05)

    @MainActor
    func test_advanceStatus_eachTransition() throws {
        // .accepted → .dispatched
        let accepted = try makeLoad(status: .accepted)
        let afterAccepted = LoadActionPredictor.predict(load: accepted, action: .advanceStatus, body: nil)
        XCTAssertEqual(afterAccepted.status, .dispatched,
                       "ACTION-05: .advanceStatus on .accepted predicts .dispatched")

        // .dispatched → .inTransit
        let dispatched = try makeLoad(status: .dispatched)
        let afterDispatched = LoadActionPredictor.predict(load: dispatched, action: .advanceStatus, body: nil)
        XCTAssertEqual(afterDispatched.status, .inTransit,
                       "ACTION-05: .advanceStatus on .dispatched predicts .inTransit")

        // .inTransit → .delivered
        let inTransit = try makeLoad(status: .inTransit)
        let afterInTransit = LoadActionPredictor.predict(load: inTransit, action: .advanceStatus, body: nil)
        XCTAssertEqual(afterInTransit.status, .delivered,
                       "ACTION-05: .advanceStatus on .inTransit predicts .delivered")
    }

    // MARK: - Test 9 — pure-function value-type purity guard (T-10-PR-01)

    @MainActor
    func test_pureFunction_doesNotMutateInput() throws {
        let deadline = Date(timeIntervalSinceReferenceDate: 7_000_000)
        let original = try makeLoad(status: .posted)
        XCTAssertEqual(original.status, .posted, "preconditions")

        _ = LoadActionPredictor.predict(
            load: original,
            action: .tender,
            body: tenderBody(respondByAt: deadline)
        )
        XCTAssertEqual(original.status, .posted,
                       "T-10-PR-01: predictor MUST NOT mutate input — value-semantic Swift struct guarantees this; this test is the regression lock")
        XCTAssertNil(original.respondByAt,
                     "T-10-PR-01: input respondByAt MUST remain nil after predict(...) returns a derived Load")
    }

    // MARK: - Test 10 — out-of-policy combination returns current unchanged (defensive no-op)

    @MainActor
    func test_outOfPolicyCombination_returnsCurrent_defensiveNoOp() throws {
        // .accept on .posted is policy-illegal: no role's RoleLoadPolicy entry
        // for .posted includes .accept. The policy gate should have prevented
        // this from reaching the predictor. The contract is: defensive no-op
        // — return current unchanged so a stray call from a hypothetical
        // caller does not crash the in-flight VM transition.
        let current = try makeLoad(status: .posted)
        let predicted = LoadActionPredictor.predict(load: current, action: .accept, body: nil)
        XCTAssertEqual(predicted.status, current.status,
                       "out-of-policy (.accept, .posted) must defensively return current unchanged — no crash, no silent mutation")
        XCTAssertEqual(predicted.id, current.id)
        XCTAssertEqual(predicted.respondByAt, current.respondByAt)
    }
}
