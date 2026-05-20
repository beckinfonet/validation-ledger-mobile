// validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift
//
// Phase 9 Plan 04 Task 1 — populates the Wave 0 shell from Plan 02.
//
// Locked targets:
//   - 09-04-PLAN.md Task 1 (Acceptance Criteria — 4 of 5 tests are real
//     assertions; iPad split remains skipped until Plan 09).
//   - 09-PATTERNS.md table row line 38 — direct twin
//     `Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift` (PATTERNS E9
//     for the shimmer re-attach lifecycle assertion).
//   - 09-UI-SPEC.md § Skeleton lines 480-516 — iPhone silhouette diagram +
//     shimmer mechanics + accessibility-identifier locks.
//
// Test plan (5 methods — 4 real, 1 placeholder):
//   - test_iPhoneSilhouette_rendersExpectedFrame() — silhouette geometry
//     assertion + UIKitSnapshot attach for visual review.
//   - test_iPadSplitSilhouette_rendersExpectedFrame() — skipped (Plan 09).
//   - test_shimmerAnimationRestartsOnLayoutSubviews() — PATTERNS E9
//     verbatim, the Pitfall 1 mitigation gate.
//   - test_shimmerAnimationRestartsOnTraitCollectionChange() — second
//     re-attach hook required by RESEARCH §2 line 967.
//   - test_reduceMotion_suppressesShimmer() — UI-SPEC line 869 reduce-
//     motion suppression invariant, exercised via the
//     `reduceMotionOverride` test seam.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Mirrors
// the existing snapshot-suite locked precedent across Loads/Snapshot/.

import XCTest
@testable import validationLedger

class LoadDetailSkeletonViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// iPhone portrait silhouette canvas size — 393pt (iPhone 17 width) by
    /// 700pt (a representative below-status-bar height that fits the pinned
    /// header + graph region + body rows without clipping).
    private static let iPhoneCanvasSize = CGSize(width: 393, height: 700)

    // MARK: - 1. iPhone silhouette renders the expected frame

    func test_iPhoneSilhouette_rendersExpectedFrame() {
        let view = LoadDetailSkeletonView()
        view.bounds = CGRect(origin: .zero, size: Self.iPhoneCanvasSize)
        view.layoutIfNeeded()

        // Attach the rendered snapshot for visual review on CI.
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPhoneCanvasSize),
            name: "LoadDetailSkeleton-iPhonePortrait", to: self
        )

        // Structural assertions — UI-SPEC § iPhone skeleton lines 484-501:
        //   * one pinned-header rectangle (the top-most silhouette block).
        //   * 5 grey circles in the role slots (D-06 iPhone coordinates).
        //   * 3+ grey body rows below the graph region.
        //
        // The skeleton tags each functional block via its
        // `accessibilityIdentifier` so the suite can count them without
        // walking the auto-layout tree.
        let allSubviews = collectAllSubviews(view)
        let circles = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.circle" }
        let bodyRows = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.body-row" }
        let pinnedHeaders = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.pinned-header" }

        XCTAssertEqual(circles.count, 5,
                       "iPhone silhouette must render 5 role-slot circles (UI-SPEC D-06 — shipper, broker, carrier, dispatch, factoring)")
        XCTAssertGreaterThanOrEqual(bodyRows.count, 3,
                                    "iPhone silhouette must render at least 3 grey body rows (UI-SPEC silhouette diagram)")
        XCTAssertEqual(pinnedHeaders.count, 1,
                       "iPhone silhouette must render exactly one pinned-header rectangle at top")

        // Root accessibility-identifier lock — UI-SPEC § Accessibility identifiers.
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.skeleton",
                       "LoadDetailSkeletonView root identifier must be the locked 'load-detail.skeleton'")
    }

    // MARK: - 2. iPad split silhouette — Plan 09 (D-03 iPad split layout)

    /// iPad landscape canvas — 1024×768 (iPad mini landscape; the smallest
    /// regular-width target). The split silhouette renders a left pane
    /// (skeleton graph circles) + a right pane (skeleton pinned-header
    /// rectangle + 4 body rows). The iPad mode also leaves the iPhone-only
    /// pinned-header rectangle inside the right pane (not at the top of the
    /// view tree).
    private static let iPadCanvasSize = CGSize(width: 1024, height: 768)

    func test_iPadSplitSilhouette_rendersExpectedFrame() {
        let view = LoadDetailSkeletonView()
        view.renderMode = .iPadSplit
        view.bounds = CGRect(origin: .zero, size: Self.iPadCanvasSize)
        view.layoutIfNeeded()

        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.iPadCanvasSize),
            name: "LoadDetailSkeleton-iPadSplit", to: self
        )

        // Structural assertions — UI-SPEC § iPad skeleton lines 503-505:
        //   * left pane carries 5 role-slot circles (one per Role).
        //   * right pane carries the pinned-header rectangle.
        //   * right pane carries ≥ 4 body rows (Plan 09 silhouette guidance).
        let allSubviews = collectAllSubviews(view)
        let circles = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.circle" }
        let bodyRows = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.body-row" }
        let pinnedHeaders = allSubviews.filter { $0.accessibilityIdentifier == "load-detail.skeleton.pinned-header" }

        XCTAssertEqual(circles.count, 5,
                       "iPad split silhouette must render 5 role-slot circles in the left pane (D-06 mirror)")
        XCTAssertGreaterThanOrEqual(bodyRows.count, 4,
                                    "iPad split silhouette must render at least 4 grey body rows in the right pane (Plan 09 silhouette)")
        XCTAssertEqual(pinnedHeaders.count, 1,
                       "iPad split silhouette must render exactly one pinned-header rectangle at the top of the right pane")

        // Root identifier unchanged across renderMode flips.
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.skeleton",
                       "root identifier survives the renderMode flip")
    }

    // MARK: - 3. Shimmer re-attach on layoutSubviews (PATTERNS E9, Pitfall 1)

    func test_shimmerAnimationRestartsOnLayoutSubviews() {
        let view = LoadDetailSkeletonView()
        view.bounds = CGRect(origin: .zero, size: Self.iPhoneCanvasSize)
        view.layoutIfNeeded()

        // After init + layoutSubviews, the shimmer animation MUST be attached.
        XCTAssertNotNil(view.shimmerLayer.animation(forKey: "shimmer"),
                        "shimmer must be attached after init + layoutIfNeeded")

        // Manually strip the animation — simulates an internal UIKit lifecycle
        // event that drops the animation (rotation, size-class change).
        view.shimmerLayer.removeAnimation(forKey: "shimmer")
        XCTAssertNil(view.shimmerLayer.animation(forKey: "shimmer"),
                     "precondition: animation must be cleared after removeAnimation")

        // Force a layout pass — layoutSubviews must re-attach the shimmer.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertNotNil(view.shimmerLayer.animation(forKey: "shimmer"),
                        "Pitfall 1: layoutSubviews must re-attach the shimmer animation")
    }

    // MARK: - 4. Shimmer re-attach on traitCollectionDidChange (RESEARCH §2 line 967)

    func test_shimmerAnimationRestartsOnTraitCollectionChange() {
        let view = LoadDetailSkeletonView()
        view.bounds = CGRect(origin: .zero, size: Self.iPhoneCanvasSize)
        view.layoutIfNeeded()

        // Clear the animation to verify the trait-change hook re-attaches it.
        view.shimmerLayer.removeAnimation(forKey: "shimmer")
        XCTAssertNil(view.shimmerLayer.animation(forKey: "shimmer"),
                     "precondition: animation must be cleared")

        // Trigger the trait-collection-change hook directly. UIKit's runtime
        // overload is open on UIView; passing `nil` for previousTraitCollection
        // is the canonical "trait changed" invocation pattern.
        view.traitCollectionDidChange(nil)

        XCTAssertNotNil(view.shimmerLayer.animation(forKey: "shimmer"),
                        "Pitfall 1: traitCollectionDidChange must re-attach the shimmer animation")
    }

    // MARK: - 5. Reduce-motion suppresses the shimmer (UI-SPEC line 869)

    func test_reduceMotion_suppressesShimmer() {
        let view = LoadDetailSkeletonView()
        view.bounds = CGRect(origin: .zero, size: Self.iPhoneCanvasSize)

        // Inject reduce-motion = true via the test seam BEFORE the first
        // layout pass so the initial startShimmer() honors the override.
        view.reduceMotionOverride = true
        view.layoutIfNeeded()

        XCTAssertNil(view.shimmerLayer.animation(forKey: "shimmer"),
                     "Reduce-motion ON: shimmer animation must NOT be attached (UI-SPEC line 869)")

        // Flip the override off and re-layout — shimmer should re-attach.
        view.reduceMotionOverride = false
        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertNotNil(view.shimmerLayer.animation(forKey: "shimmer"),
                        "Reduce-motion OFF: shimmer animation must re-attach after layoutSubviews")
    }

    // MARK: - Subview traversal helper

    /// Depth-first walk of the view tree collecting every UIView descendant.
    /// Used by the silhouette structural assertion to find blocks by their
    /// accessibility identifier without coupling the test to the exact
    /// auto-layout hierarchy (which Plan 09 may rearrange when it adds the
    /// iPad split silhouette).
    private func collectAllSubviews(_ root: UIView) -> [UIView] {
        var out: [UIView] = []
        var stack: [UIView] = [root]
        while let next = stack.popLast() {
            out.append(next)
            stack.append(contentsOf: next.subviews)
        }
        return out
    }
}
