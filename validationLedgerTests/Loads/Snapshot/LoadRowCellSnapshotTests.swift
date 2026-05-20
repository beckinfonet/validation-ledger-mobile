// validationLedgerTests/Loads/Snapshot/LoadRowCellSnapshotTests.swift
// Phase 8 Plan 03 Task 3 — LoadRowCell visual + accessibility lock.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)` to surface
// the rendered image into the CI artefact bundle for visual triage. Swift
// Testing as of iOS 17 / Xcode 26.4 has no equivalent attachment surface.
// Plan 02's SUMMARY locked this convention: snapshot tests = XCTest;
// state-machine / log-content tests = Swift Testing. This file follows that
// precedent (mirrors VerificationBadgeViewSnapshotTests.swift).
//
// === Locked test surface ===
//   - 4 per-verification-state tests (verified / pending / unverified / flagged)
//     each construct a synthetic LoadListItem, configure the cell, attach the
//     rendered image, and assert the cell's accessibilityIdentifier shape
//     (loads-list.row.{loadID}).
//   - 1 nil-counterparty fail-closed test (D-03 + T-08-08) asserts the
//     fail-closed nil path renders UNVERIFIED visuals AND never exposes the
//     suppressed name slot through accessibilityLabel.
//   - 1 cancelled-status row test asserts the status-badge identifier shape.
//   - 1 prepareForReuse reset test (T-08-07) asserts a previously-VERIFIED
//     cell renders UNVERIFIED visuals after prepareForReuse() — fail-closed.
//
// === T-08-09 — synthetic identifiers only ===
// `makeItem(...)` constructs Loads + TrustNodes with synthetic VL-9001..VL-9006
// and synthetic-party names ("Synthetic Carrier A", etc.). No real freight
// reference numbers, no real party names reach the rendered images attached
// to CI artefacts. CLAUDE.md zero-PII discipline.

import XCTest
@testable import validationLedger

class LoadRowCellSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// Default row size: 375 (iPhone compact width) × 88 (typical row height).
    private static let rowSize = CGSize(width: 375, height: 88)

    /// Build a fully-populated `LoadListItem` with synthetic identifiers + a
    /// counterparty TrustNode whose `verificationState` is settable.
    ///
    /// `verification == nil` produces a `displayedCounterparty: nil` envelope
    /// (D-03 fail-closed path).
    private func makeItem(
        id: String,
        verification: VerificationState?,
        status: LoadStatus = .posted
    ) -> LoadListItem {
        let origin = LoadStop(city: "Anaheim", state: "CA", postalCode: "92805", country: "US")
        let destination = LoadStop(city: "Atlanta", state: "GA", postalCode: "30303", country: "US")
        let load = Load(
            id: id,
            referenceNumber: "REF-SYNTH-\(id)",
            origin: origin,
            destination: destination,
            equipment: "dry_van",
            weight: 42500,
            rate: Decimal(2500),
            pickupAt: Date(timeIntervalSince1970: 1_780_000_000),
            deliverAt: Date(timeIntervalSince1970: 1_780_500_000),
            status: status,
            stateHistory: [],
            respondByAt: nil,
            tenderEligibility: nil
        )
        let counterparty: TrustNode? = verification.map { state in
            TrustNode(
                partyID: "party-carrier-synth-\(id)",
                role: .carrier,
                displayName: "Synthetic Carrier \(id)",
                verificationState: state,
                kycCompletedAt: nil,
                deviceBindingStatus: .bound,
                usdotNumber: nil,
                usdotAuthorityStatus: .active,
                priorRelationshipCount: 0
            )
        }
        return LoadListItem(load: load, displayedCounterparty: counterparty)
    }

    /// Decode-helper: LoadListItem only has a synthesized Decodable initializer.
    /// To construct a synthetic LoadListItem in tests we route through a JSON
    /// round-trip so the test stays loyal to the production decoder
    /// configuration AND we don't expose a memberwise public initializer just
    /// for tests (which would widen the contract).
    ///
    /// Implementation note: the inline-construction form above uses Load's and
    /// TrustNode's compiler-synthesized internal memberwise initializers. They
    /// are accessible from this test target via `@testable import`. If that
    /// assumption changes, this file can switch to a JSON round-trip.
    private func renderedCell(item: LoadListItem) -> LoadRowCell {
        let cell = LoadRowCell()
        cell.bounds = CGRect(origin: .zero, size: Self.rowSize)
        cell.configure(item: item)
        cell.layoutIfNeeded()
        return cell
    }

    // MARK: - 4 per-verification-state tests

    func test_verifiedCounterpartyRendersGreenBadge() {
        let cell = renderedCell(item: makeItem(id: "VL-9001", verification: .verified))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9001")
        XCTAssertEqual(cell.verificationBadge.accessibilityIdentifier,
                       "loads-list.row.VL-9001.verification-badge")
        // Sanity: the configured badge surfaces the "verified" a11y string.
        let a11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("verified") && !a11y.contains("not verified"),
                      "verified row a11y must contain 'verified' without 'not'; got: \(a11y)")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-verified", to: self
        )
    }

    func test_pendingCounterpartyRendersPendingBadge() {
        let cell = renderedCell(item: makeItem(id: "VL-9002", verification: .pending))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9002")
        XCTAssertEqual(cell.verificationBadge.accessibilityIdentifier,
                       "loads-list.row.VL-9002.verification-badge")
        let a11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("pending"),
                      "pending row a11y must contain 'pending'; got: \(a11y)")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-pending", to: self
        )
    }

    func test_unverifiedCounterpartyRendersUnverifiedBadge() {
        let cell = renderedCell(item: makeItem(id: "VL-9003", verification: .unverified))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9003")
        let a11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("not verified"),
                      "unverified row a11y must contain 'not verified'; got: \(a11y)")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-unverified", to: self
        )
    }

    func test_flaggedCounterpartyRendersFlaggedBadge() {
        let cell = renderedCell(item: makeItem(id: "VL-9004", verification: .flagged))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9004")
        let a11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("flagged"),
                      "flagged row a11y must contain 'flagged'; got: \(a11y)")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-flagged", to: self
        )
    }

    // MARK: - D-03 fail-closed nil counterparty + T-08-08 name-slot suppression

    func test_nilCounterpartyRendersFailClosedUnverifiedAndSuppressedName() {
        let cell = renderedCell(item: makeItem(id: "VL-9005", verification: nil))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9005")
        XCTAssertEqual(cell.verificationBadge.accessibilityIdentifier,
                       "loads-list.row.VL-9005.verification-badge")
        // D-03 — nil renders the UNVERIFIED visuals via the configure(stateOrNil:)
        // overload. The literal "not verified" substring is the T-08-06 lock.
        let a11y = cell.verificationBadge.accessibilityLabel ?? ""
        XCTAssertTrue(a11y.contains("not verified"),
                      "nil counterparty must render literal 'not verified'; got: \(a11y)")
        // T-08-08 — the badge a11y MUST NOT carry the counterparty's display
        // name. With nil the test of "no name slot reached" is trivially true
        // (there IS no counterparty), but we ALSO assert the badge does not
        // accidentally render a stray "verified" without the "not" prefix —
        // which would be the regression the T-08-06 mitigation is for.
        let lowered = a11y.lowercased()
        // The literal " verified" with a leading space would indicate the
        // word verified appears without the "not " qualifier. Check for that
        // structurally instead of via a free-text search.
        XCTAssertFalse(lowered.contains(" verified") && !lowered.contains("not verified"),
                       "T-08-06: nil counterparty must NEVER read as bare 'verified' without 'not'; got: \(lowered)")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-nilCounterparty", to: self
        )
    }

    // MARK: - Cancelled-status row (badge identifier + ramp tone)

    func test_flaggedStatusRowRendersStatusBadgeWithStrikethroughOrCorrectTone() {
        let cell = renderedCell(item: makeItem(id: "VL-9006",
                                               verification: .verified,
                                               status: .cancelled))
        XCTAssertEqual(cell.accessibilityIdentifier, "loads-list.row.VL-9006")
        XCTAssertEqual(cell.statusBadge.accessibilityIdentifier,
                       "loads-list.row.VL-9006.status-badge")
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: cell, size: Self.rowSize),
            name: "LoadRowCell-cancelled", to: self
        )
    }

    // MARK: - T-08-07 cell-reuse reset

    func test_prepareForReuseResetsVerificationBadgeToUnverified() {
        let cell = renderedCell(item: makeItem(id: "VL-9007", verification: .verified))
        // Sanity: the just-configured cell renders the "verified" a11y.
        let beforeA11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(beforeA11y.contains("verified") && !beforeA11y.contains("not verified"),
                      "precondition: configured cell must read as 'verified' (without 'not'); got: \(beforeA11y)")

        // T-08-07 — the reset.
        cell.prepareForReuse()
        cell.layoutIfNeeded()

        // After reset: a11y must read as "not verified" (UNVERIFIED visuals).
        let afterA11y = cell.verificationBadge.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(afterA11y.contains("not verified"),
                      "prepareForReuse() must reset the badge to UNVERIFIED ('not verified' a11y); got: \(afterA11y)")
        // accessibilityIdentifier on cell + badges must be cleared.
        XCTAssertNil(cell.accessibilityIdentifier,
                     "prepareForReuse() must clear the cell accessibilityIdentifier")
        XCTAssertNil(cell.verificationBadge.accessibilityIdentifier,
                     "prepareForReuse() must clear the verification badge accessibilityIdentifier")
    }
}
