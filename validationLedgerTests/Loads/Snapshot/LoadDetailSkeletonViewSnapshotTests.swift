// validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift
//
// Phase 9 Plan 02 Task 1 — Wave 0 shell.
//
// Locked targets:
//   - VALIDATION.md line 72 (Wave 0 list).
//   - PATTERNS.md table row line 38 — direct twin
//     `Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift` (PATTERNS E9
//     for the shimmer re-attach lifecycle assertion).
//
// Shell covering:
//   - iPhone full-silhouette snapshot.
//   - iPad split-silhouette snapshot.
//   - Pitfall 1 lifecycle assertion: `shimmerLayer.animation(forKey:
//     "shimmer")` re-attaches on `layoutSubviews()` (Phase 9 has no
//     cell-recycle, so the hook is `layoutSubviews()` and
//     `traitCollectionDidChange(_:)`, NOT `prepareForReuse()` — see
//     PATTERNS.md table row line 38 + RESEARCH §2 Pitfall 1).
//
// Populated by Plan 04 (LoadDetailSkeletonView production type).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.

import XCTest
@testable import validationLedger

class LoadDetailSkeletonViewSnapshotTests: XCTestCase {

    func test_iPhoneSilhouette_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 04")
    }

    func test_iPadSplitSilhouette_rendersExpectedFrame() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 04")
    }

    // Pitfall 1 — Phase 9's no-cell-recycle equivalent of the
    // SkeletonLoadRowCell `test_shimmerAnimationRestartsOnPrepareForReuse`
    // assertion. The Phase 9 lifecycle hook is `layoutSubviews()` + a
    // `traitCollectionDidChange(_:)` re-attach (rotation, size-class change).
    func test_shimmerAnimationRestartsOnLayoutSubviews() throws {
        throw XCTSkip("Wave 0 shell — populated by Plan 04")
    }
}
