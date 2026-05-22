// validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift
// Phase 8 Plan 03 — LOAD-08 / D-10: the app-wide skeleton-with-shimmer pattern.
//
// === Pattern note (D-10) — established here, reused project-wide ===
// Phase 8 establishes the app-wide skeleton-with-shimmer pattern. Future
// list-style fetch surfaces (Phase 9+ chain-of-trust party list, any list
// endpoint that ships in v1.2+) SHOULD follow this precedent. The previously
// shipped KYCStatusViewController centered `UIActivityIndicatorView` is NOT
// back-ported (CONTEXT.md D-10 — incremental adoption; KYC is a single-screen
// flow where the skeleton would be visually heavier than the value it adds).
//
// Recipe (verified across two list surfaces in the design contract):
//   1. Silhouette-match `UIView` blocks laid out to mirror the real cell's
//      hierarchy — same outer layout margins, same vertical rhythm, similar
//      block widths so the eye sees "row content arriving" not "loading
//      indicator".
//   2. A single `CAGradientLayer` on contentView with `colors = [.clear,
//      .white α=.25, .clear]` and `locations = [0, 0.5, 1]`, animated by a
//      `CABasicAnimation` on `keyPath: "locations"` cycling from
//      `[-1, -0.5, 0]` → `[1, 1.5, 2]` over 1.2s, `repeatCount = .infinity`.
//   3. Re-attach the animation in BOTH `prepareForReuse()` AND
//      `layoutSubviews()` (RESEARCH §Pitfall 1 — the animation gets stripped
//      on either lifecycle event; re-adding in only one of the two leaves
//      the shimmer stuck on rotation / size-class change / cell-reuse).
//   4. STACK-04: no third-party shimmer library. `QuartzCore` is iOS-bundled.
//
// === Accessibility ===
// `isAccessibilityElement = true; accessibilityLabel = "Loading"` — VoiceOver
// announces the row ONCE, not block-by-block. The same skeleton-with-shimmer
// recipe should keep this discipline in future list surfaces.
//
// === Test-target reachability ===
// `shimmerLayer` is `internal let` (not `private let`) so
// SkeletonLoadRowCellSnapshotTests can probe its `animation(forKey: "shimmer")`
// via `@testable import validationLedger`.

import UIKit
import QuartzCore

public final class SkeletonLoadRowCell: UICollectionViewListCell {

    // MARK: - Subviews — silhouette blocks (mirror LoadRowCell's 5-row hierarchy)

    private static func makeBlock() -> UIView {
        let v = UIView()
        v.backgroundColor = .systemGray5
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private let referenceBlock = SkeletonLoadRowCell.makeBlock()
    private let statusBlock = SkeletonLoadRowCell.makeBlock()
    private let originDestinationBlock = SkeletonLoadRowCell.makeBlock()
    private let pickupDeliverBlock = SkeletonLoadRowCell.makeBlock()
    private let rateBlock = SkeletonLoadRowCell.makeBlock()

    // MARK: - Shimmer layer

    /// `internal` so SkeletonLoadRowCellSnapshotTests can poll
    /// `animation(forKey: "shimmer")` via `@testable import validationLedger`.
    let shimmerLayer: CAGradientLayer = {
        let l = CAGradientLayer()
        l.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.25).cgColor,
            UIColor.clear.cgColor,
        ]
        l.startPoint = CGPoint(x: 0, y: 0.5)
        l.endPoint = CGPoint(x: 1, y: 0.5)
        l.locations = [0, 0.5, 1]
        return l
    }()

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
        startShimmer()
    }

    public required init?(coder: NSCoder) {
        fatalError("SkeletonLoadRowCell is constructed programmatically only")
    }

    // MARK: - Layout

    private func setUp() {
        backgroundColor = DS.Colors.background

        // VoiceOver: announce the skeleton row as a single "Loading" element.
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString(
            "loads.row.skeleton.a11y",
            value: "Loading",
            comment: "Phase 8 SkeletonLoadRowCell — VoiceOver label announced once per skeleton row"
        )
        // XCUITest identifier — under the "loads-list.loading-indicator"
        // namespace owned by the LoadListViewController's skeleton overlay.
        // The overlay sets its own loads-list.loading-indicator identifier;
        // individual skeleton rows carry the .row sub-namespace so a future
        // XCUITest can count skeleton rows without traversing the layout.
        accessibilityIdentifier = "loads-list.loading-indicator.row"

        // Row 1: reference (large block) | status (small block)
        let row1 = UIStackView(arrangedSubviews: [referenceBlock, statusBlock])
        row1.axis = .horizontal
        row1.alignment = .center
        row1.spacing = DS.Spacing.sm

        // Row 2: origin → destination (wide block)
        let row2 = UIStackView(arrangedSubviews: [originDestinationBlock])
        row2.axis = .horizontal
        row2.alignment = .center

        // Row 3: pickup-deliver block (medium) + rate block (small, right-aligned)
        let row3 = UIStackView(arrangedSubviews: [pickupDeliverBlock, UIView(), rateBlock])
        row3.axis = .horizontal
        row3.alignment = .center
        row3.spacing = DS.Spacing.sm

        let outer = UIStackView(arrangedSubviews: [row1, row2, row3])
        outer.axis = .vertical
        outer.alignment = .fill
        outer.spacing = DS.Spacing.sm
        outer.isLayoutMarginsRelativeArrangement = true
        outer.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        outer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Heights — body-text blocks at 16pt, footnote blocks at 12pt
            referenceBlock.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            statusBlock.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            originDestinationBlock.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            pickupDeliverBlock.heightAnchor.constraint(equalToConstant: 12),
            rateBlock.heightAnchor.constraint(equalToConstant: 12),

            // Widths (multiplier-based so the silhouette tracks Dynamic Type
            // and orientation changes):
            referenceBlock.widthAnchor.constraint(
                equalTo: row1.widthAnchor, multiplier: 0.45),
            statusBlock.widthAnchor.constraint(
                equalTo: row1.widthAnchor, multiplier: 0.20),
            originDestinationBlock.widthAnchor.constraint(
                equalTo: row2.widthAnchor, multiplier: 0.80),
            pickupDeliverBlock.widthAnchor.constraint(
                equalTo: row3.widthAnchor, multiplier: 0.40),
            rateBlock.widthAnchor.constraint(
                equalTo: row3.widthAnchor, multiplier: 0.20),
        ])

        // Attach the shimmer layer on top of the contentView so it overlays
        // every silhouette block at once.
        contentView.layer.addSublayer(shimmerLayer)
    }

    // MARK: - layoutSubviews — Pitfall 1: re-attach on size-class / rotation

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 1: animations get stripped on bounds changes; reposition the
        // gradient layer AND re-attach the keyframe animation if it's gone.
        shimmerLayer.frame = contentView.bounds
        startShimmer()
    }

    // MARK: - prepareForReuse — Pitfall 1: re-attach on cell recycle

    public override func prepareForReuse() {
        super.prepareForReuse()
        startShimmer()
    }

    // MARK: - Shimmer animation

    /// Attach the shimmer keyframe animation IF it isn't already attached.
    /// The guard prevents re-adding on every layout pass (which would reset
    /// the animation's phase and produce a visible "stutter").
    private func startShimmer() {
        guard shimmerLayer.animation(forKey: "shimmer") == nil else { return }
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1, -0.5, 0]
        anim.toValue = [1, 1.5, 2]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        shimmerLayer.add(anim, forKey: "shimmer")
    }
}
