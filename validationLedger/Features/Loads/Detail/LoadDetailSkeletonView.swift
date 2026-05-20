// validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift
//
// Phase 9 Plan 04 — D-19: skeleton-with-shimmer for the `.loading` state of
// the load detail screen. Mirrors the Phase 8 app-wide skeleton pattern
// established by `SkeletonLoadRowCell` (PATTERNS E3 lines 60-100, 167-198).
//
// === D-19 silhouette composition (UI-SPEC § iPhone skeleton lines 484-501) ===
// iPhone (single column):
//   * Pinned-header rectangle (top, full-width, 60pt tall).
//   * Graph region with 5 grey circles at the D-06 iPhone role-slot
//     coordinates — (0.18, 0.18) shipper · (0.50, 0.30) broker ·
//     (0.50, 0.55) carrier · (0.82, 0.55) dispatch · (0.50, 0.85)
//     factoring — connected by 4 thin grey edge lines.
//   * 3 grey placeholder body rows below (varying widths).
//
// iPad split silhouette (D-03) is Plan 09 — this file ships a placeholder
// `renderSplitSilhouette()` stub the future plan replaces.
//
// === Shimmer lifecycle — PATTERNS E3 + RESEARCH §2 Pitfall 1 ===
// The CABasicAnimation on `shimmerLayer` is stripped by UIKit on bounds-
// change / size-class events. Re-attach in BOTH `layoutSubviews()` AND
// `traitCollectionDidChange(_:)` (cell skeletons use `prepareForReuse()`
// here; Phase 9 is a UIView with no recycle, so the second hook is the
// trait-change one — RESEARCH §2 line 967).
//
// `internal let shimmerLayer` (NOT private) so
// `LoadDetailSkeletonViewSnapshotTests` can probe
// `animation(forKey: "shimmer")` via `@testable import validationLedger`,
// mirroring the Phase 8 `SkeletonLoadRowCell.shimmerLayer` discipline.
//
// === Reduce-motion suppression (UI-SPEC line 869) ===
// When `UIAccessibility.isReduceMotionEnabled == true`, the shimmer
// animation is NOT attached — the skeleton stays static-grey. A test seam
// `reduceMotionOverride: Bool?` allows
// `LoadDetailSkeletonViewSnapshotTests.test_reduceMotion_suppressesShimmer`
// to drive both branches deterministically (UIAccessibility.isReduceMotion
// Enabled is not directly settable from test code).
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): the skeleton consumes
// NO fixture data. Pure structural placeholder shapes. None of the trust-
// graph payload fields are referenced — the per-node trust enum, the
// chain-level verdict, and the flagged-party-ID set all land in Plans 06
// and 09 (the graph + the verdict block).
// T-09-04 (Information Disclosure — PII): same — the skeleton never renders
// freight reference numbers, party names, or any other server-supplied
// surface. Verified by grep gate in 09-04-PLAN acceptance criteria.
// T-09-06 (DoS — stripped shimmer): mitigated by the
// `startShimmer()` re-attach gate in `layoutSubviews()` AND
// `traitCollectionDidChange(_:)`, locked by snapshot-suite tests
// `test_shimmerAnimationRestartsOnLayoutSubviews` +
// `test_shimmerAnimationRestartsOnTraitCollectionChange`.
//
// === Accessibility identifier namespace (UI-SPEC § Accessibility identifiers) ===
//   - root view: "load-detail.skeleton"
//   - pinned-header rectangle: "load-detail.skeleton.pinned-header"
//   - each role-slot circle: "load-detail.skeleton.circle"
//   - each body row: "load-detail.skeleton.body-row"
// The sub-element identifiers are NOT in UI-SPEC's locked-identifier table
// (which only locks the root); they are an internal testing convention so
// `test_iPhoneSilhouette_rendersExpectedFrame` can count blocks without
// walking the auto-layout tree.

import UIKit
import QuartzCore

public final class LoadDetailSkeletonView: UIView {

    // MARK: - Shimmer layer (PATTERNS E3 verbatim — same gradient mechanics
    //          as SkeletonLoadRowCell)
    //
    // `internal` so `LoadDetailSkeletonViewSnapshotTests` can probe
    // `animation(forKey: "shimmer")` via `@testable import validationLedger`.
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

    // MARK: - Reduce-motion test seam

    /// Test-only override for `UIAccessibility.isReduceMotionEnabled`. When
    /// non-nil, `isReduceMotionOn` returns this value instead of polling the
    /// runtime API. The test surface uses it because the runtime API is not
    /// directly settable from XCTest. Production callers leave this nil; the
    /// production path observes the real `UIAccessibility` notification.
    var reduceMotionOverride: Bool?

    private var isReduceMotionOn: Bool {
        reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled
    }

    // MARK: - Silhouette block factory (mirrors SkeletonLoadRowCell.makeBlock)

    /// Build a single grey silhouette block — `DS.Colors.surface` fill,
    /// 4pt rounded corners (per UI-SPEC silhouette diagram approximation).
    /// Mirrors `SkeletonLoadRowCell.makeBlock()` (PATTERNS E3 line 60).
    private static func makeBlock() -> UIView {
        let v = UIView()
        v.backgroundColor = DS.Colors.surface
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    /// Build a 24×24pt grey circle for a role slot. The corner radius is
    /// fixed at 12pt (half the side) so the shape stays circular without a
    /// layoutSubviews recompute.
    private static func makeCircle() -> UIView {
        let v = UIView()
        v.backgroundColor = DS.Colors.surface
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.skeleton.circle"
        return v
    }

    /// Build a 2pt grey "edge" line connecting two role-slot circles.
    /// Implemented as a thin UIView positioned by frame in `layoutSubviews`
    /// (simpler than `CAShapeLayer` for the 4 lines this skeleton needs).
    private static func makeEdge() -> UIView {
        let v = UIView()
        v.backgroundColor = DS.Colors.surface
        // No accessibility identifier — edges are visual only, not part of
        // the structural-count assertion in
        // test_iPhoneSilhouette_rendersExpectedFrame.
        return v
    }

    // MARK: - Subviews — pinned header / role circles / connector edges / body rows

    private let pinnedHeaderBlock: UIView = {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.pinned-header"
        return v
    }()

    /// Graph region container — non-scrolling parent for the 5 role-slot
    /// circles + 4 connector edges. Fixed 400pt height (D-19 silhouette
    /// guidance — the production rule is `safeAreaLayoutGuide.layoutFrame
    /// .height * 0.62`; the skeleton hard-codes so the silhouette geometry
    /// is deterministic for snapshot tests).
    private let graphRegion: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // The 5 role-slot circles, named by Role per D-06.
    private let shipperCircle = LoadDetailSkeletonView.makeCircle()
    private let brokerCircle = LoadDetailSkeletonView.makeCircle()
    private let carrierCircle = LoadDetailSkeletonView.makeCircle()
    private let dispatchCircle = LoadDetailSkeletonView.makeCircle()
    private let factoringCircle = LoadDetailSkeletonView.makeCircle()

    /// 4 connector edges drawn between adjacent role-slot circle pairs.
    /// Positioned by frame in layoutSubviews against the live circle frames.
    private let edge1 = LoadDetailSkeletonView.makeEdge() // shipper → broker
    private let edge2 = LoadDetailSkeletonView.makeEdge() // broker → carrier
    private let edge3 = LoadDetailSkeletonView.makeEdge() // carrier → dispatch
    private let edge4 = LoadDetailSkeletonView.makeEdge() // carrier → factoring

    // The 3 body rows below the graph (varying widths per the UI-SPEC
    // silhouette diagram).
    private let bodyRow1: UIView = {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.body-row"
        return v
    }()
    private let bodyRow2: UIView = {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.body-row"
        return v
    }()
    private let bodyRow3: UIView = {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.body-row"
        return v
    }()

    // MARK: - Reduce-motion notification observer

    private var reduceMotionObserver: NSObjectProtocol?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadDetailSkeletonView is constructed programmatically only")
    }

    deinit {
        if let observer = reduceMotionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Layout

    private func setUp() {
        accessibilityIdentifier = "load-detail.skeleton"
        backgroundColor = DS.Colors.background

        // VoiceOver: announce the skeleton as a single "Loading load detail"
        // element — mirrors SkeletonLoadRowCell's "Loading" discipline. The
        // composite UI-SPEC announcement "Loading load detail" is the
        // intent; here the label is the single-word "Loading" so the
        // skeleton view behaves consistently with the existing list
        // skeleton precedent.
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString(
            "load_detail.skeleton.a11y",
            value: "Loading",
            comment: "Phase 9 LoadDetailSkeletonView — VoiceOver label announced for the loading skeleton"
        )

        // Assemble graph-region subviews. Circles + edges are added but
        // positioned in layoutSubviews against the live bounds (their
        // coordinates are fractional per D-06).
        graphRegion.addSubview(edge1)
        graphRegion.addSubview(edge2)
        graphRegion.addSubview(edge3)
        graphRegion.addSubview(edge4)
        graphRegion.addSubview(shipperCircle)
        graphRegion.addSubview(brokerCircle)
        graphRegion.addSubview(carrierCircle)
        graphRegion.addSubview(dispatchCircle)
        graphRegion.addSubview(factoringCircle)

        // Outer vertical layout — pinned header / graph region / 3 body rows.
        let outer = UIStackView(arrangedSubviews: [
            pinnedHeaderBlock,
            graphRegion,
            bodyRow1,
            bodyRow2,
            bodyRow3,
        ])
        outer.axis = .vertical
        outer.alignment = .leading
        outer.spacing = DS.Spacing.md
        outer.isLayoutMarginsRelativeArrangement = true
        outer.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.lg,
            bottom: DS.Spacing.md, right: DS.Spacing.lg
        )
        outer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            // Pinned header — full width × 60pt tall.
            pinnedHeaderBlock.heightAnchor.constraint(equalToConstant: 60),
            pinnedHeaderBlock.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            pinnedHeaderBlock.trailingAnchor.constraint(equalTo: outer.layoutMarginsGuide.trailingAnchor),

            // Graph region — full width × 400pt tall (deterministic for snapshots).
            graphRegion.heightAnchor.constraint(equalToConstant: 400),
            graphRegion.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            graphRegion.trailingAnchor.constraint(equalTo: outer.layoutMarginsGuide.trailingAnchor),

            // Body rows — varying widths (60%, 90%, 70% of available width)
            // per UI-SPEC silhouette diagram lines 496-499. Heights at 16pt
            // each (matches DS.Spacing.md — body-text size).
            bodyRow1.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            bodyRow1.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            bodyRow1.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.6),

            bodyRow2.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            bodyRow2.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            bodyRow2.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.9),

            bodyRow3.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            bodyRow3.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            bodyRow3.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.7),

            // Role-slot circles — fixed 24×24pt (positioned by frame in
            // layoutSubviews per D-06 fractional coordinates).
            shipperCircle.widthAnchor.constraint(equalToConstant: 24),
            shipperCircle.heightAnchor.constraint(equalToConstant: 24),
            brokerCircle.widthAnchor.constraint(equalToConstant: 24),
            brokerCircle.heightAnchor.constraint(equalToConstant: 24),
            carrierCircle.widthAnchor.constraint(equalToConstant: 24),
            carrierCircle.heightAnchor.constraint(equalToConstant: 24),
            dispatchCircle.widthAnchor.constraint(equalToConstant: 24),
            dispatchCircle.heightAnchor.constraint(equalToConstant: 24),
            factoringCircle.widthAnchor.constraint(equalToConstant: 24),
            factoringCircle.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Attach the shimmer overlay on top of the entire skeleton view (not
        // just the contentView — Phase 9 is a UIView, not a UICollectionViewCell).
        layer.addSublayer(shimmerLayer)

        // Observe the system reduce-motion preference so the shimmer state
        // updates on the fly. The override seam takes precedence in tests.
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.setNeedsLayout()
        }
    }

    // MARK: - layoutSubviews — Pitfall 1 re-attach + circle positioning

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Position the role-slot circles by frame using the D-06 iPhone
        // fractional coordinates against the live graphRegion bounds.
        // Coordinates are the CENTER of each circle; subtract 12 (half the
        // 24pt side) to derive the frame origin.
        let g = graphRegion.bounds
        if g.width > 0 && g.height > 0 {
            positionCircle(shipperCircle,   atX: 0.18, y: 0.18, in: g)
            positionCircle(brokerCircle,    atX: 0.50, y: 0.30, in: g)
            positionCircle(carrierCircle,   atX: 0.50, y: 0.55, in: g)
            positionCircle(dispatchCircle,  atX: 0.82, y: 0.55, in: g)
            positionCircle(factoringCircle, atX: 0.50, y: 0.85, in: g)

            // Connector edges — recomputed against the live circle centers.
            positionEdge(edge1, from: shipperCircle.center, to: brokerCircle.center)
            positionEdge(edge2, from: brokerCircle.center, to: carrierCircle.center)
            positionEdge(edge3, from: carrierCircle.center, to: dispatchCircle.center)
            positionEdge(edge4, from: carrierCircle.center, to: factoringCircle.center)
        }

        // Shimmer overlay covers the full skeleton bounds.
        shimmerLayer.frame = bounds

        // Pitfall 1: re-attach the shimmer animation if UIKit stripped it
        // on this layout pass (rotation, size-class change, container resize).
        startShimmer()
    }

    /// Re-attach the shimmer on trait-collection changes (rotation, size-
    /// class swap, dark/light mode flip). RESEARCH §2 line 967 documents
    /// this as the second hook a no-cell-recycle UIView needs to mitigate
    /// Pitfall 1 — `layoutSubviews()` covers bounds changes; this covers
    /// trait changes that don't necessarily trigger a layout pass.
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        startShimmer()
    }

    // MARK: - Shimmer animation

    /// Attach the shimmer keyframe animation IF reduce-motion is OFF AND
    /// the animation isn't already attached. Mirrors PATTERNS E3 lines
    /// 167-198 verbatim, with the reduce-motion gate added per UI-SPEC
    /// line 869.
    ///
    /// Two-step guard:
    ///   1. Reduce-motion ON → remove any existing animation and bail.
    ///      (Covers the runtime case where reduce-motion flips ON after
    ///      the skeleton has already started shimmering.)
    ///   2. Animation already attached → bail (prevents re-adding on every
    ///      layout pass, which would reset the animation's phase and
    ///      produce a visible "stutter").
    private func startShimmer() {
        guard !isReduceMotionOn else {
            shimmerLayer.removeAnimation(forKey: "shimmer")
            return
        }
        guard shimmerLayer.animation(forKey: "shimmer") == nil else { return }
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1, -0.5, 0]
        anim.toValue = [1, 1.5, 2]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        shimmerLayer.add(anim, forKey: "shimmer")
    }

    // MARK: - Geometry helpers

    /// Place a 24×24pt circle centered at the fractional `(x, y)` coordinates
    /// inside the supplied container rect.
    private func positionCircle(_ circle: UIView, atX fx: CGFloat, y fy: CGFloat, in container: CGRect) {
        let cx = container.width * fx
        let cy = container.height * fy
        circle.frame = CGRect(x: cx - 12, y: cy - 12, width: 24, height: 24)
    }

    /// Render a 2pt edge as a thin UIView positioned at the midpoint of
    /// (start, end) and rotated to align with the segment direction.
    private func positionEdge(_ edge: UIView, from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        // Reset transform before resizing so the bounds math is consistent
        // across layout passes (CGAffineTransform composes against the
        // pre-transform frame).
        edge.transform = .identity
        edge.frame = CGRect(x: midX - length / 2, y: midY - 1, width: length, height: 2)
        edge.transform = CGAffineTransform(rotationAngle: atan2(dy, dx))
    }

    // MARK: - iPad split silhouette (Plan 09)

    /// Placeholder for the iPad split-silhouette path. Plan 09 (D-03 iPad
    /// split layout) replaces this stub. Until then, the iPad simulator
    /// renders the iPhone silhouette stretched into the wider canvas —
    /// adequate as a placeholder while we wait for the split-pane work.
    // FIXME(Plan 09): iPad split silhouette — left pane (graph circles)
    //                  + right pane (header + body rows).
    func renderSplitSilhouette() {
        // Intentionally empty — Plan 09 owns the split layout (D-03).
    }
}
