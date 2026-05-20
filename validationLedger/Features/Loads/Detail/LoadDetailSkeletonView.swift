// validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift
//
// Phase 9 Plan 04 — D-19: skeleton-with-shimmer for the `.loading` state of
// the load detail screen. Mirrors the Phase 8 app-wide skeleton pattern
// established by `SkeletonLoadRowCell` (PATTERNS E3 lines 60-100, 167-198).
//
// === D-19 silhouette composition (UI-SPEC § iPhone skeleton lines 484-501) ===
// iPhone (single column) [RenderMode.iPhonePortrait]:
//   * Pinned-header rectangle (top, full-width, 60pt tall).
//   * Graph region with 5 grey circles at the D-06 iPhone role-slot
//     coordinates — (0.18, 0.18) shipper · (0.50, 0.30) broker ·
//     (0.50, 0.55) carrier · (0.82, 0.55) dispatch · (0.50, 0.85)
//     factoring — connected by 4 thin grey edge lines.
//   * 3 grey placeholder body rows below (varying widths).
//
// iPad split silhouette (D-03 / Plan 09) [RenderMode.iPadSplit]:
//   * Left pane (~60% width): graph region with 5 grey circles at the D-06
//     iPad role-slot coordinates + 4 connector lines (mirror of the iPhone
//     graph silhouette, rescaled to the pane aspect).
//   * Right pane (~40% width): pinned-header rectangle (top) + 4 grey body
//     rows below (one extra row vs. iPhone — the right pane is taller because
//     it isn't graph-dominated; UI-SPEC line 503-505).
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
// === RenderMode (Plan 09) ===
// `renderMode: RenderMode = .iPhonePortrait { didSet { rebuildSilhouette() }}`
// flips the silhouette geometry. The VC sets it based on its own
// `compositionLayout` (iPhone compact → .iPhonePortrait; iPad regular →
// .iPadSplit). The shimmer layer is preserved across mode flips — only the
// silhouette subviews are torn down and rebuilt.
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

    // MARK: - RenderMode (Plan 09 — iPhone vs iPad split silhouette)

    /// The silhouette geometry to render. iPhone single-column (Plan 04
    /// original) vs iPad horizontal-split (Plan 09 holdover). Flipped by
    /// the VC's `traitCollectionDidChange(_:)` per its compositionLayout.
    public enum RenderMode: Sendable {
        case iPhonePortrait
        case iPadSplit
    }

    /// The current render mode. Flipping it triggers a silhouette rebuild
    /// (the shimmer layer is preserved — only the silhouette subviews are
    /// torn down and rebuilt). Defaults to iPhone portrait.
    public var renderMode: RenderMode = .iPhonePortrait {
        didSet {
            guard oldValue != renderMode else { return }
            rebuildSilhouette()
        }
    }

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

    /// Build a tagged body-row block (grey rectangle that participates in
    /// the silhouette assertion via its accessibilityIdentifier).
    private static func makeBodyRow() -> UIView {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.body-row"
        return v
    }

    /// Build a tagged pinned-header block.
    private static func makePinnedHeader() -> UIView {
        let v = makeBlock()
        v.accessibilityIdentifier = "load-detail.skeleton.pinned-header"
        return v
    }

    // MARK: - Reduce-motion notification observer

    private var reduceMotionObserver: NSObjectProtocol?

    // MARK: - Silhouette state (per-mode geometry, rebuilt on renderMode flip)

    /// All silhouette subviews currently mounted. Tracked so
    /// `rebuildSilhouette()` can tear them down without disturbing the
    /// `shimmerLayer` (which is a sublayer of `self.layer`, not a subview).
    private var silhouetteSubviews: [UIView] = []

    /// The role-slot circles for the current mode (5 circles in role order).
    /// Stored so `layoutSubviews()` can re-position them against the live
    /// graph-region bounds without rebuilding the silhouette.
    private var roleCircles: [UIView] = []

    /// The connector edges for the current mode (4 edges shipper→broker,
    /// broker→carrier, carrier→dispatch, carrier→factoring). Positioned by
    /// frame in layoutSubviews against the live circle frames.
    private var connectorEdges: [UIView] = []

    /// The graph-region container for the current mode (left pane in iPad
    /// split, full-width strip below the pinned header in iPhone). Used as
    /// the coordinate space for circle/edge positioning.
    private var graphRegion: UIView?

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

        // Build the initial silhouette per the default renderMode.
        rebuildSilhouette()
    }

    /// Tear down the existing silhouette + rebuild for the current
    /// `renderMode`. The shimmer layer is preserved (it's a sublayer of
    /// `self.layer`, not a subview, so it survives the subview teardown).
    private func rebuildSilhouette() {
        // Tear down prior silhouette.
        silhouetteSubviews.forEach { $0.removeFromSuperview() }
        silhouetteSubviews.removeAll()
        roleCircles.removeAll()
        connectorEdges.removeAll()
        graphRegion = nil

        switch renderMode {
        case .iPhonePortrait:
            buildIPhonePortraitSilhouette()
        case .iPadSplit:
            buildIPadSplitSilhouette()
        }

        // Force a layout so the role-slot circles + connector edges get
        // positioned against the live graph-region bounds for snapshot
        // determinism on the immediate `layoutIfNeeded()` test pattern.
        setNeedsLayout()
    }

    /// Build the iPhone single-column silhouette (Plan 04 original):
    /// pinned header (60pt) + graph region (400pt with 5 role circles + 4
    /// connector edges) + 3 body rows (60% / 90% / 70% widths).
    private func buildIPhonePortraitSilhouette() {
        let pinnedHeader = Self.makePinnedHeader()
        let graph = makeGraphRegion()
        let row1 = Self.makeBodyRow()
        let row2 = Self.makeBodyRow()
        let row3 = Self.makeBodyRow()

        let outer = UIStackView(arrangedSubviews: [
            pinnedHeader, graph, row1, row2, row3,
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
        silhouetteSubviews.append(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            pinnedHeader.heightAnchor.constraint(equalToConstant: 60),
            pinnedHeader.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            pinnedHeader.trailingAnchor.constraint(equalTo: outer.layoutMarginsGuide.trailingAnchor),

            graph.heightAnchor.constraint(equalToConstant: 400),
            graph.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            graph.trailingAnchor.constraint(equalTo: outer.layoutMarginsGuide.trailingAnchor),

            row1.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row1.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            row1.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.6),

            row2.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row2.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            row2.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.9),

            row3.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row3.leadingAnchor.constraint(equalTo: outer.layoutMarginsGuide.leadingAnchor),
            row3.widthAnchor.constraint(equalTo: outer.layoutMarginsGuide.widthAnchor, multiplier: 0.7),
        ])
    }

    /// Build the iPad split silhouette (Plan 09 / D-03): horizontal split
    /// with the graph region on the left (~60% width) and the pinned-header
    /// + 4 body rows on the right (~40% width).
    private func buildIPadSplitSilhouette() {
        let graph = makeGraphRegion()
        let pinnedHeader = Self.makePinnedHeader()
        let row1 = Self.makeBodyRow()
        let row2 = Self.makeBodyRow()
        let row3 = Self.makeBodyRow()
        let row4 = Self.makeBodyRow()

        // Right pane: pinned header + 4 body rows in a vertical stack.
        let rightPane = UIStackView(arrangedSubviews: [
            pinnedHeader, row1, row2, row3, row4,
        ])
        rightPane.axis = .vertical
        rightPane.alignment = .leading
        rightPane.spacing = DS.Spacing.md
        rightPane.isLayoutMarginsRelativeArrangement = true
        rightPane.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        rightPane.translatesAutoresizingMaskIntoConstraints = false

        // Horizontal split: graph (left) + rightPane (right).
        let split = UIStackView(arrangedSubviews: [graph, rightPane])
        split.axis = .horizontal
        split.alignment = .fill
        split.distribution = .fill
        split.spacing = 0
        split.translatesAutoresizingMaskIntoConstraints = false

        addSubview(split)
        silhouetteSubviews.append(split)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: topAnchor),
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 60/40 split — matches the VC's iPad composition (UI-SPEC line 143).
            graph.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.60),

            pinnedHeader.heightAnchor.constraint(equalToConstant: 60),
            pinnedHeader.leadingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.leadingAnchor),
            pinnedHeader.trailingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.trailingAnchor),

            row1.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row1.leadingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.leadingAnchor),
            row1.widthAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.widthAnchor, multiplier: 0.9),

            row2.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row2.leadingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.leadingAnchor),
            row2.widthAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.widthAnchor, multiplier: 0.7),

            row3.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row3.leadingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.leadingAnchor),
            row3.widthAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.widthAnchor, multiplier: 0.85),

            row4.heightAnchor.constraint(equalToConstant: DS.Spacing.md),
            row4.leadingAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.leadingAnchor),
            row4.widthAnchor.constraint(equalTo: rightPane.layoutMarginsGuide.widthAnchor, multiplier: 0.6),
        ])
    }

    /// Build the shared graph-region container with 5 role-slot circles +
    /// 4 connector edges. Used by BOTH iPhone and iPad silhouettes; the
    /// circles' fractional coordinates against the region bounds are the
    /// SAME role-slot table — they just rescale to whatever bounds the
    /// region ends up with (iPhone: ~600pt wide × 400pt; iPad split left:
    /// ~600pt wide × 768pt). The role-slot recognizability transfers across
    /// devices (PROJECT.md "fixed role slots is a recognizability decision").
    private func makeGraphRegion() -> UIView {
        let region = UIView()
        region.translatesAutoresizingMaskIntoConstraints = false

        let shipper = Self.makeCircle()
        let broker = Self.makeCircle()
        let carrier = Self.makeCircle()
        let dispatch = Self.makeCircle()
        let factoring = Self.makeCircle()
        let circles = [shipper, broker, carrier, dispatch, factoring]
        for c in circles {
            region.addSubview(c)
            NSLayoutConstraint.activate([
                c.widthAnchor.constraint(equalToConstant: 24),
                c.heightAnchor.constraint(equalToConstant: 24),
            ])
        }
        roleCircles = circles

        let e1 = Self.makeEdge() // shipper → broker
        let e2 = Self.makeEdge() // broker → carrier
        let e3 = Self.makeEdge() // carrier → dispatch
        let e4 = Self.makeEdge() // carrier → factoring
        for e in [e1, e2, e3, e4] {
            region.addSubview(e)
        }
        connectorEdges = [e1, e2, e3, e4]

        graphRegion = region
        return region
    }

    // MARK: - layoutSubviews — Pitfall 1 re-attach + circle positioning

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Position the role-slot circles by frame using the D-06 iPhone
        // fractional coordinates against the live graphRegion bounds.
        // The SAME coordinate table is used for iPad split — the geometry
        // rescales to the available pane bounds (recognizability transfers
        // across devices per PROJECT.md "fixed role slots").
        // Coordinates are the CENTER of each circle; subtract 12 (half the
        // 24pt side) to derive the frame origin.
        if let g = graphRegion?.bounds, g.width > 0 && g.height > 0,
           roleCircles.count == 5, connectorEdges.count == 4 {
            positionCircle(roleCircles[0], atX: 0.18, y: 0.18, in: g) // shipper
            positionCircle(roleCircles[1], atX: 0.50, y: 0.30, in: g) // broker
            positionCircle(roleCircles[2], atX: 0.50, y: 0.55, in: g) // carrier
            positionCircle(roleCircles[3], atX: 0.82, y: 0.55, in: g) // dispatch
            positionCircle(roleCircles[4], atX: 0.50, y: 0.85, in: g) // factoring

            // Connector edges — recomputed against the live circle centers.
            positionEdge(connectorEdges[0], from: roleCircles[0].center, to: roleCircles[1].center)
            positionEdge(connectorEdges[1], from: roleCircles[1].center, to: roleCircles[2].center)
            positionEdge(connectorEdges[2], from: roleCircles[2].center, to: roleCircles[3].center)
            positionEdge(connectorEdges[3], from: roleCircles[2].center, to: roleCircles[4].center)
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
}
