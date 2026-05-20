// validationLedgerTests/Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift
// Phase 8 Plan 03 Task 3 — SkeletonLoadRowCell silhouette + shimmer lock.
//
// === Why XCTest, not Swift Testing ===
// Snapshot tests in Phase 8 use XCTest (XCTAttachment compatibility). See
// LoadRowCellSnapshotTests / VerificationBadgeViewSnapshotTests file headers
// for the locked precedent.
//
// === Locked test surface ===
//   1. Silhouette structural match — at default Dynamic Type the skeleton's
//      contentView height matches the real LoadRowCell's contentView height
//      within ±8pt (the silhouette is intentionally a bit shorter — it omits
//      the equipment/weight row and the second status row).
//   2. Shimmer re-attaches on prepareForReuse (RESEARCH §Pitfall 1).
//   3. Accessibility — single VoiceOver element labeled "Loading".

import XCTest
@testable import validationLedger

class SkeletonLoadRowCellSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private static let rowSize = CGSize(width: 375, height: 88)

    /// Build a synthetic, fully-populated LoadListItem mirroring the helper
    /// used by LoadRowCellSnapshotTests. Synthetic identifiers only (T-08-09).
    private func makeRealItem() -> LoadListItem {
        let load = Load(
            id: "VL-9099",
            referenceNumber: "REF-SYNTH-9099",
            origin: LoadStop(city: "Anaheim", state: "CA", postalCode: "92805", country: "US"),
            destination: LoadStop(city: "Atlanta", state: "GA", postalCode: "30303", country: "US"),
            equipment: "dry_van",
            weight: 42500,
            rate: Decimal(2500),
            pickupAt: Date(timeIntervalSince1970: 1_780_000_000),
            deliverAt: Date(timeIntervalSince1970: 1_780_500_000),
            status: .posted,
            stateHistory: [],
            respondByAt: nil,
            tenderEligibility: nil
        )
        return LoadListItem(load: load, displayedCounterparty: nil)
    }

    // MARK: - 1. Silhouette structural match at default Dynamic Type

    func test_skeletonSilhouetteMatchesLoadRowCellAtDefaultDynamicType() {
        let realCell = LoadRowCell()
        realCell.bounds = CGRect(origin: .zero, size: Self.rowSize)
        realCell.configure(item: makeRealItem())
        realCell.layoutIfNeeded()

        let skeletonCell = SkeletonLoadRowCell()
        skeletonCell.bounds = CGRect(origin: .zero, size: Self.rowSize)
        skeletonCell.layoutIfNeeded()

        // Attach both rendered snapshots for visual review.
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: realCell, size: Self.rowSize),
            name: "LoadRowCell-default-dynamic-type", to: self
        )
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: skeletonCell, size: Self.rowSize),
            name: "SkeletonLoadRowCell-default-dynamic-type", to: self
        )

        // Structural assertion: the skeleton's contentView height tracks the
        // real cell's contentView height within ±8pt at default Dynamic Type.
        // (The skeleton is intentionally lighter — fewer rows, smaller block
        // heights — so the tolerance is a one-sided "skeleton may be shorter
        // by up to 8pt"; a future tightening can drop the tolerance after a
        // designer review).
        let delta = abs(skeletonCell.contentView.bounds.height
                        - realCell.contentView.bounds.height)
        XCTAssertLessThanOrEqual(delta, 8.0,
                                 "Skeleton-vs-real cell height delta must be <= 8pt; got: \(delta) pt")
    }

    // MARK: - 2. Shimmer re-attaches on prepareForReuse (Pitfall 1)

    func test_shimmerAnimationRestartsOnPrepareForReuse() {
        let cell = SkeletonLoadRowCell()
        cell.bounds = CGRect(origin: .zero, size: Self.rowSize)
        cell.layoutIfNeeded()

        // After init + layoutSubviews, the shimmer animation MUST be attached.
        XCTAssertNotNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                        "shimmer must be attached after init + layoutIfNeeded")

        // Manually strip the animation — simulates an internal UIKit lifecycle
        // event that drops the animation (rotation, size-class change).
        cell.shimmerLayer.removeAnimation(forKey: "shimmer")
        XCTAssertNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                     "precondition: animation must be cleared after removeAnimation")

        // prepareForReuse re-attaches.
        cell.prepareForReuse()
        XCTAssertNotNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                        "Pitfall 1: prepareForReuse must re-attach the shimmer animation")
    }

    // MARK: - 3. Accessibility — single VoiceOver element labeled "Loading"

    func test_skeletonAccessibilityIsSingleElementLabeledLoading() {
        let cell = SkeletonLoadRowCell()
        XCTAssertTrue(cell.isAccessibilityElement,
                      "skeleton row must be a single VoiceOver element")
        XCTAssertEqual(cell.accessibilityLabel, "Loading",
                       "skeleton row a11y label must be the literal 'Loading'")
    }
}
