// validationLedgerTests/Support/UIKitSnapshot.swift
// Phase 8 Plan 01 Task 1 (Wave 0) — hand-rolled UIView → UIImage snapshot baseline.
//
// This is the app-wide snapshot mechanism for Phase 8+ UI tests. Phase 8 Plans 02
// (badges), 04 (LoadRowCell), and 05 (SkeletonLoadRowCell silhouette match) all
// consume `UIKitSnapshot.image(of:size:)` to render a layed-out UIView into a
// deterministic UIImage; failing snapshots attach via `UIKitSnapshot.attach(_:name:to:)`
// so they survive into the CI artefact bundle for visual inspection.
//
// === Why hand-rolled rather than a SwiftPM dep ===
// CLAUDE.md constraints:
//   - "Tech stack: Swift Package Manager only — no CocoaPods, no Carthage."
//   - "Dependencies: Pre-approved shortlist only ... Anything outside this list
//      requires explicit approval."
// `swift-snapshot-testing` (or any other snapshot library) is NOT on the
// pre-approved shortlist; the lowest-risk path is the iOS-bundled
// `UIGraphicsImageRenderer` + `view.layer.render(in:)` precedent already used
// by `KYCThumbnailTests.sampleJPEG(side:)` (line 34, KYCThumbnailTests.swift).
// 08-RESEARCH.md Assumption A2 confirms: "no new SwiftPM dep is added."
// 08-VALIDATION.md Wave 0 Requirements bullet 1 pins the target path.
//
// === Threat-model note (T-08-04, PII) ===
// This helper is structural — it takes any UIView and renders its pixels. The
// callers (Phase 8 tests) bind synthetic party names from the existing fixture
// corpus only. CLAUDE.md "Zero PII in analytics or crash logs" — extended here
// to "zero PII in CI snapshot artefacts."

import UIKit
import XCTest

/// Hand-rolled UIView → UIImage snapshot baseline. Used by Phase 8 snapshot
/// tests (badge components, LoadRowCell, SkeletonLoadRowCell silhouette).
/// Adds zero SwiftPM dependencies — composes `UIGraphicsImageRenderer` and
/// `CALayer.render(in:)` from the iOS SDK only.
enum UIKitSnapshot {

    /// Render `view` to a `UIImage` at the given `size`.
    ///
    /// The implementation sets `view.bounds` to `(0, 0, size.width, size.height)`,
    /// forces a layout pass via `layoutIfNeeded()`, and rasterises the layer tree
    /// via `view.layer.render(in: ctx.cgContext)`. The renderer's format defaults
    /// to the device's native scale, which keeps Phase 8 snapshots stable across
    /// the iPhone 17 simulator (the project's pinned simulator-lane device — see
    /// `ios-test-suite-pitfalls` project memory).
    ///
    /// - Parameters:
    ///   - view: the UIView to snapshot. Must be configured before calling
    ///     (subviews added, constraints active or frame set).
    ///   - size: the target render size. The view's `bounds` is reset to this
    ///     size; callers that want intrinsic-content sizing should pass the
    ///     view's `systemLayoutSizeFitting(...)` result.
    /// - Returns: A `UIImage` containing the rendered view.
    static func image(of view: UIView, size: CGSize) -> UIImage {
        view.bounds = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }

    /// Attach a rendered snapshot to the running `XCTestCase` so the image
    /// survives into the CI artefact bundle. Phase 8 snapshot tests call this
    /// from their assertion sites; the attachment is keyed by `name` for
    /// human triage in Xcode's test report.
    ///
    /// - Parameters:
    ///   - image: the rendered snapshot.
    ///   - name: a human-readable identifier for the attachment (shown in
    ///     Xcode's test navigator; should include the test scenario, e.g.
    ///     `"LoadRowCell-broker-flagged"`).
    ///   - testCase: the running `XCTestCase` to attach to.
    ///   - lifetime: defaults to `.keepAlways` so the artefact survives a
    ///     passing run (callers can pass `.deleteOnSuccess` to keep the CI
    ///     bundle lean).
    static func attach(
        _ image: UIImage,
        name: String,
        to testCase: XCTestCase,
        lifetime: XCTAttachment.Lifetime = .keepAlways
    ) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = lifetime
        testCase.add(attachment)
    }
}
