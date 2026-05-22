// validationLedger/Features/Loads/Detail/TrustGraphView.swift
//
// Phase 9 Plan 06 Task 2 — TRUST-01 / TRUST-05 marquee canvas. Hosts the
// UIScrollView + content container + 5 fixed role-slot TrustNodeViews +
// CAShapeLayer edges + halo layers + pulse animation + the D-22
// accessibility container, with the D-04 gesture choreography +
// size-class-driven role-slot coordinate switch.
//
// === Composition (D-01 / D-04 / D-05 / D-06 / D-15 / D-22) ===
// - `scrollView`: inner UIScrollView, viewForZooming returns
//   `contentContainer`. Inner-pan minimumNumberOfTouches is clamped to 2
//   (D-04 — outer page scroll preserved; see setUp() for the call site);
//   maximumNumberOfTouches likewise clamped to 2 (belt-and-braces);
//   minimumZoomScale = 1.0, maximumZoomScale = 2.5.
// - `contentContainer`: zoomable subview hosting per-node TrustNodeViews
//   AND the CAShapeLayer edges (drawn into its layer in z-order BELOW the
//   node chrome) AND the CAShapeLayer halos (drawn into its layer ABOVE
//   the edges but BELOW node chrome — chrome paints on top so the node's
//   label stays readable).
// - `accessibilityElements = orderedNodes + orderedEdges` (D-22): nodes
//   in fixed role order shipper → broker → carrier → dispatch → factoring,
//   edges sorted by (fromPartyID, toPartyID) lex order.
//
// === Fraud visual language (D-15 — tiered) ===
// - .clean → no halo, solid neutral edges. Pulse: never.
// - .caution → yellow halo (STATIC, no pulse) + yellow dashed implicated
//   edges + dim-others to 50%. Pulse: never.
// - .compromised → red halo + ANIMATED PULSE (opacity 0.6→1.0, 1.2s,
//   easeInEaseOut, autoreverses, infinite, isRemovedOnCompletion=false) +
//   red dashed implicated edges + dim-others to 50%. Reduce-motion
//   suppresses pulse — halo paints solid (color still signals compromised).
//
// Pulse-only-on-compromised invariant: the pulse is added ONLY in the
// .compromised codepath inside `startPulseIfNeeded()`. Caution halos NEVER
// pulse. PATTERNS E3 (SkeletonLoadRowCell.startShimmer) is the lifecycle
// mirror: re-attach in BOTH `layoutSubviews()` AND
// `traitCollectionDidChange(_:)` (Pitfall 1 / RESEARCH §2 line 967).
//
// === Edge tap-target (UI-SPEC line 208 / RESEARCH §1 line 241) ===
// Each edge has TWO render surfaces: a CAShapeLayer for the stroke (chrome
// only, no interaction) + a 28pt-band invisible UIView companion for the
// 44pt tap target. The companion view carries the single-tap recognizer
// that surfaces TRUST-04 (sheet wiring in Plan 08; this plan ships the
// companion + closure).
//
// === Gesture model (D-04) ===
// - Inner scroll pan: 2-finger only (preserves outer page scroll).
// - Per-node single-tap → onSingleTap(partyID) → nodeTapped(partyID).
// - Per-node double-tap → onDoubleTap(view) → recenterAndZoom(to: view) →
//   scrollView zooms to ~1.8x centered on the node, ~250ms easeInEaseOut.
// - Empty-canvas double-tap (recognizer on scrollView) → reset to 1.0.
// - Per-edge single-tap → onEdgeTap(edgeID) → edgeTapped(edgeID).
// - singleTap.require(toFail: doubleTap) — locked in TrustNodeView, NOT
//   here. TrustGraphView consumes the closure surface.
//
// === Accessibility (D-22) ===
// - `isAccessibilityElement = false` (container, NOT leaf — Pitfall 4 lock).
// - `accessibilityElements = orderedNodes + orderedEdges` published after
//   every `configure(chainOfTrust:)`.
// - Per-node label composed via `composedNodeLabel(for:chainOfTrust:)`:
//   "<role>, <displayName>, verification state: <state>, KYC <basis>[, USDOT
//   <authorityStatus>][, Implicated in chain compromise.]".
// - VoiceOver-active: scrollView.minimumZoomScale = maximumZoomScale = 1.0
//   (pinch suspended); per-node double-tap recognizers disabled. Observer
//   on UIAccessibility.didChangeNotification keeps the state in sync.
// - Reduce-motion: pulse suppressed at the halo-attach gate.
//
// === Threat-model anchors ===
// T-09-03: every visual treatment is driven by chainIntegrity.verdict +
// implicatedNodeIDs/EdgeIDs membership lookups against server-supplied
// Sets. No `derive*()` methods exist in this file (locked by source-grep).
// T-09-04: zero logger calls in this file; the composed labels render
// only server-supplied displayNames (synthetic in the Phase 7 fixture
// corpus per D-13).
// T-09-08: the novel gesture choreography is locked at source-grep level
// for the minimumNumberOfTouches == 2 + maximumNumberOfTouches == 2.
// T-09-09: the novel accessibility-container model is locked at source-
// grep level for isAccessibilityElement = false.
//
// === iOS 17 deployment minimum ===
// `UIAccessibility.isVoiceOverRunning`, `.isReduceMotionEnabled`,
// `UIGestureRecognizer.name`, `UIScrollView.setZoomScale(_:animated:)` are
// all iOS 11+. No iOS 18-only APIs.

import UIKit
import QuartzCore

public final class TrustGraphView: UIView {

    // MARK: - Internal storage

    /// Inner scroll view — exposed as `internal` so unit tests can introspect
    /// the pan-gesture configuration directly. Production callers route
    /// through `configure(chainOfTrust:)` and the closure callbacks.
    internal let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.minimumZoomScale = 1.0
        s.maximumZoomScale = 2.5
        s.bouncesZoom = true
        s.showsHorizontalScrollIndicator = false
        s.showsVerticalScrollIndicator = false
        return s
    }()

    /// The zoomable content view — `viewForZooming(in:)` returns this. Holds
    /// the per-node TrustNodeViews as subviews and the edge / halo
    /// CAShapeLayers in its layer hierarchy.
    private let contentContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private var nodeViews: [TrustNodeView] = []
    private var edgeLayers: [CAShapeLayer] = []
    private var edgeArrowheadLayers: [CAShapeLayer] = []
    private var edgeCompanionViews: [EdgeCompanionView] = []
    private var haloLayers: [CAShapeLayer] = []
    /// Subset of haloLayers carrying the compromised verdict — only these
    /// receive the pulse animation. PATTERNS E3 mirror.
    private var compromisedHaloLayers: [CAShapeLayer] = []

    /// Snapshot of the data the configure call ingested; needed in
    /// `layoutSubviews` to recompute node positions + edge paths against
    /// the live canvas geometry.
    private var currentChain: ChainOfTrust?

    /// Empty-canvas double-tap recognizer. Attached to `scrollView` so a
    /// double-tap missing every node still resets the zoom (D-05).
    private let emptyCanvasDoubleTap = UITapGestureRecognizer()

    // MARK: - Test seams (internal — accessed by @testable import)

    /// Override for `UIAccessibility.isVoiceOverRunning`. Production code
    /// leaves this nil and reads the real notification; tests drive both
    /// branches deterministically via `_testInvokeVoiceOverChange(isOn:)`.
    internal var voiceOverActiveOverride: Bool?

    /// Override for `UIAccessibility.isReduceMotionEnabled`. Production code
    /// leaves this nil; tests set it before configure to lock the pulse-
    /// suppression invariant.
    internal var reduceMotionOverride: Bool?

    private var isVoiceOverOn: Bool {
        voiceOverActiveOverride ?? UIAccessibility.isVoiceOverRunning
    }

    private var isReduceMotionOn: Bool {
        reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled
    }

    /// Test-only inspection — return the halo layers for animation
    /// introspection in the snapshot suite (Pitfall 8 lock).
    internal func _testHaloLayers() -> [CAShapeLayer] { haloLayers }

    /// Test-only — fire the empty-canvas double-tap path without a real
    /// touch sequence.
    internal func _testInvokeDoubleTapOnEmptyCanvas() {
        handleEmptyCanvasDoubleTap()
    }

    /// Test-only — fire the per-node double-tap path on the first node view
    /// (the shipper in role-ordered fixtures). Used by gesture tests that
    /// just need to prove the zoom transition fires.
    internal func _testInvokeDoubleTapOnAnyNode() {
        guard let any = nodeViews.first else { return }
        recenterAndZoom(to: any)
    }

    /// Test-only — drive the VoiceOver-active branch via the override seam
    /// + the same observer hook the production NotificationCenter callback
    /// uses.
    internal func _testInvokeVoiceOverChange(isOn: Bool) {
        voiceOverActiveOverride = isOn
        accessibilityFeaturesChanged()
    }

    // MARK: - Callbacks (consumed by LoadDetailViewController in this plan)

    /// Fires with the tapped node's `partyID`. LoadDetailViewController
    /// presents the TRUST-03 verification-basis sheet (sheet wiring lands
    /// in Plan 07; this plan ships the closure surface and the VC stub).
    internal var nodeTapped: ((String) -> Void)?

    /// Fires with the tapped edge's `edgeID`. LoadDetailViewController
    /// presents the TRUST-04 handoff-detail sheet (Plan 08).
    internal var edgeTapped: ((String) -> Void)?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("TrustGraphView is constructed programmatically only")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Role-slot coordinate tables (D-06)

    private static let iPhoneSlots: [Role: CGPoint] = [
        .shipper:   CGPoint(x: 0.18, y: 0.18),
        .broker:    CGPoint(x: 0.50, y: 0.30),
        .carrier:   CGPoint(x: 0.50, y: 0.55),
        .dispatch:  CGPoint(x: 0.82, y: 0.55),
        .factoring: CGPoint(x: 0.50, y: 0.85),
    ]
    private static let iPadSlots: [Role: CGPoint] = [
        .shipper:   CGPoint(x: 0.18, y: 0.22),
        .broker:    CGPoint(x: 0.40, y: 0.30),
        .carrier:   CGPoint(x: 0.50, y: 0.55),
        .dispatch:  CGPoint(x: 0.78, y: 0.45),
        .factoring: CGPoint(x: 0.82, y: 0.78),
    ]

    /// Role-slot lookup driven by the current trait collection's
    /// horizontalSizeClass (D-06 / D-03). `.regular` → iPad slots; anything
    /// else → iPhone slots.
    private var roleSlots: [Role: CGPoint] {
        traitCollection.horizontalSizeClass == .regular ? Self.iPadSlots : Self.iPhoneSlots
    }

    // MARK: - setUp

    private func setUp() {
        accessibilityIdentifier = "load-detail.trust-graph"
        // D-22 Pitfall 4 LOCK — container, NOT leaf.
        isAccessibilityElement = false
        backgroundColor = DS.Colors.background

        addSubview(scrollView)
        scrollView.addSubview(contentContainer)
        scrollView.delegate = self

        // D-04 LOCK — outer page scroll preservation (RESEARCH §1 line 214-215).
        // The grep gate in 09-06-PLAN.md acceptance criteria locks these at
        // the source level.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Content container = same size as scrollView's bounds at 1x
            // zoom (fit-all-nodes-tight per D-05). The container resizes
            // implicitly via the scroll-view's content-size machinery; we
            // pin the four edges to the scroll-view's frameLayoutGuide so
            // the canvas tracks the visible bounds at zoom 1.0.
            contentContainer.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentContainer.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // Empty-canvas double-tap (D-05 reset). The recognizer is on the
        // scrollView so a tap hitting bare canvas (between nodes / outside
        // edges) is captured. Per-node double-taps win because the node
        // view's recognizer is attached to a subview (cancelsTouchesInView
        // default).
        emptyCanvasDoubleTap.numberOfTapsRequired = 2
        emptyCanvasDoubleTap.name = "trust-graph.emptyCanvasDoubleTap"
        emptyCanvasDoubleTap.addTarget(self, action: #selector(handleEmptyCanvasDoubleTap))
        scrollView.addGestureRecognizer(emptyCanvasDoubleTap)

        // D-22 accessibility-feature observers — keep VoiceOver clamp +
        // reduce-motion suppression in sync with the system state.
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityFeaturesChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityFeaturesChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    // MARK: - Public API — configure from a ChainOfTrust

    /// Render the marquee canvas from the WHOLE server-supplied
    /// ChainOfTrust. Every visual treatment (badge state, halo color, edge
    /// dash, dim opacity, accessibilityLabel) flows from this payload
    /// VERBATIM per Phase 7 D-18 LOCK (no client-side derivation).
    public func configure(chainOfTrust: ChainOfTrust) {
        currentChain = chainOfTrust

        // Tear down existing render — nodes, edge layers, halos.
        nodeViews.forEach { $0.removeFromSuperview() }
        nodeViews.removeAll()
        edgeLayers.forEach { $0.removeFromSuperlayer() }
        edgeLayers.removeAll()
        edgeArrowheadLayers.forEach { $0.removeFromSuperlayer() }
        edgeArrowheadLayers.removeAll()
        edgeCompanionViews.forEach { $0.removeFromSuperview() }
        edgeCompanionViews.removeAll()
        haloLayers.forEach { $0.removeFromSuperlayer() }
        haloLayers.removeAll()
        compromisedHaloLayers.removeAll()

        let integrity = chainOfTrust.integrity
        let isChainClean = integrity.verdict == .clean
        let implicatedNodeSet = Set(integrity.implicatedNodeIDs)
        let implicatedEdgeSet = Set(integrity.implicatedEdgeIDs)

        // === Build nodes (one TrustNodeView per node) ===
        // TrustNodeView's setUp() declares TAMIC = false; we override to
        // true here because per-node positioning is driven by frame
        // writes in `layoutSubviews()`, not constraints. (Phase 9 device
        // UAT 2026-05-20 — debug session trust-graph-device-bugs.)
        for node in chainOfTrust.nodes {
            let v = TrustNodeView()
            v.translatesAutoresizingMaskIntoConstraints = true
            let isImplicated = implicatedNodeSet.contains(node.partyID)
            let isDimmed = !isChainClean && !isImplicated
            v.configure(node: node, isImplicated: isImplicated, isDimmed: isDimmed)

            v.onSingleTap = { [weak self] partyID in self?.nodeTapped?(partyID) }
            v.onDoubleTap = { [weak self] nodeView in self?.recenterAndZoom(to: nodeView) }

            contentContainer.addSubview(v)
            nodeViews.append(v)
        }

        // === Build edges (CAShapeLayer chrome + invisible companion view) ===
        // Edges sorted by (fromPartyID, toPartyID) lex order — deterministic
        // for D-22 accessibility ordering.
        let sortedEdges = chainOfTrust.edges.sorted { lhs, rhs in
            if lhs.fromPartyID != rhs.fromPartyID { return lhs.fromPartyID < rhs.fromPartyID }
            return lhs.toPartyID < rhs.toPartyID
        }
        for edge in sortedEdges {
            // Edge stroke — CAShapeLayer (chrome only, NOT a tap target).
            let layer = CAShapeLayer()
            layer.lineWidth = 2.0
            layer.fillColor = nil
            let isImplicated = implicatedEdgeSet.contains(edge.edgeID)
            applyEdgeStyle(layer: layer, edge: edge, integrity: integrity, isImplicated: isImplicated)
            contentContainer.layer.addSublayer(layer)
            edgeLayers.append(layer)

            // Arrowhead layer.
            let arrow = CAShapeLayer()
            arrow.fillColor = layer.strokeColor
            arrow.strokeColor = layer.strokeColor
            arrow.opacity = layer.opacity
            contentContainer.layer.addSublayer(arrow)
            edgeArrowheadLayers.append(arrow)

            // Companion tap-target view (UI-SPEC line 208 — 28pt band
            // overlay positioned + rotated in layoutSubviews).
            let companion = EdgeCompanionView(edgeID: edge.edgeID, edge: edge)
            companion.translatesAutoresizingMaskIntoConstraints = false
            companion.isAccessibilityElement = true
            companion.accessibilityTraits = .button
            companion.accessibilityIdentifier = "load-detail.trust-graph.edge.\(edge.edgeID)"
            companion.onSingleTap = { [weak self] eid in self?.edgeTapped?(eid) }
            contentContainer.addSubview(companion)
            edgeCompanionViews.append(companion)
        }

        // === Halo layers (D-15) — one per implicated node when verdict != clean ===
        for node in chainOfTrust.nodes where implicatedNodeSet.contains(node.partyID) && !isChainClean {
            let halo = CAShapeLayer()
            halo.fillColor = (integrity.verdict == .compromised
                              ? UIColor.systemRed.cgColor
                              : UIColor.systemYellow.cgColor)
            halo.opacity = 1.0
            // Add halos as siblings of node subviews — UNDER the node chrome
            // so the chrome paints on top (label readability). The
            // contentContainer's layer hierarchy places sublayers BELOW
            // subviews by default unless we explicitly insertSublayer
            // at: 0 — but the platform default is sublayer-then-subview,
            // which is what we want (subviews always render above sublayers
            // in the same layer). The chrome thus paints over the halo.
            contentContainer.layer.insertSublayer(halo, at: 0)
            haloLayers.append(halo)
            if integrity.verdict == .compromised {
                compromisedHaloLayers.append(halo)
            }
        }

        // === D-22 accessibility container ===
        applyAccessibilityElements(for: chainOfTrust)

        // === D-22 VoiceOver-active branch — clamp zoom when active ===
        applyVoiceOverClamp()

        // Pulse + layout — recomputed against live geometry below.
        setNeedsLayout()
        layoutIfNeeded()
        startPulseIfNeeded()
    }

    // MARK: - Edge styling (D-15)

    /// Apply the D-15 tiered styling to an edge layer based on the chain
    /// verdict + the per-edge implicated flag. Implementation reads only
    /// the server-supplied `integrity.verdict` + `implicatedEdgeIDs`
    /// membership lookup (T-09-03 lock).
    private func applyEdgeStyle(layer: CAShapeLayer, edge: TrustEdge,
                                integrity: ChainIntegrity, isImplicated: Bool) {
        switch integrity.verdict {
        case .clean:
            layer.strokeColor = DS.Colors.separator.cgColor
            layer.lineDashPattern = nil
            layer.opacity = 1.0
        case .caution:
            if isImplicated {
                layer.strokeColor = UIColor.systemYellow.cgColor
                layer.lineDashPattern = [6, 4]
                layer.opacity = 1.0
            } else {
                layer.strokeColor = DS.Colors.separator.cgColor
                layer.lineDashPattern = nil
                // Dim-others — non-implicated edges fade when chain != clean.
                layer.opacity = 0.5
            }
        case .compromised:
            if isImplicated {
                layer.strokeColor = UIColor.systemRed.cgColor
                layer.lineDashPattern = [6, 4]
                layer.opacity = 1.0
            } else {
                layer.strokeColor = DS.Colors.separator.cgColor
                layer.lineDashPattern = nil
                layer.opacity = 0.5
            }
        }
    }

    // MARK: - Accessibility container (D-22)

    /// Compose the D-22 ordered accessibilityElements array:
    ///   1. Nodes in fixed role order (shipper, broker, carrier, dispatch,
    ///      factoring) filtered to present.
    ///   2. Edges sorted by (fromPartyID, toPartyID) lex order — same order
    ///      already established when we built `edgeCompanionViews` above.
    /// Also calls `applyComposedAccessibilityLabel(_:)` on each node + sets
    /// the composed label on each edge companion view.
    private func applyAccessibilityElements(for chain: ChainOfTrust) {
        let roleOrder: [Role] = [.shipper, .broker, .carrier, .dispatch, .factoring]
        var orderedNodes: [TrustNodeView] = []
        for role in roleOrder {
            for nodeView in nodeViews {
                if let node = chain.nodes.first(where: { $0.partyID == nodeView.partyID }),
                   node.role == role {
                    nodeView.applyComposedAccessibilityLabel(
                        composedNodeLabel(for: node, chain: chain)
                    )
                    orderedNodes.append(nodeView)
                }
            }
        }

        // Edge companions already sorted in `configure(chainOfTrust:)`.
        for companion in edgeCompanionViews {
            if let edge = chain.edges.first(where: { $0.edgeID == companion.edgeID }) {
                companion.accessibilityLabel = composedEdgeLabel(for: edge, chain: chain)
            }
        }

        accessibilityElements = orderedNodes + edgeCompanionViews
    }

    /// Compose the per-node VoiceOver label per UI-SPEC lines 841-845.
    /// Reads only server-supplied fields; the implicated-suffix is a
    /// membership lookup against `chainIntegrity.implicatedNodeIDs`.
    private func composedNodeLabel(for node: TrustNode, chain: ChainOfTrust) -> String {
        var parts: [String] = []
        parts.append(node.role.displayName)
        parts.append(node.displayName)
        parts.append("verification state: \(node.verificationState.rawValue)")

        // KYC basis summary.
        if let when = node.kycCompletedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("KYC verified \(formatter.localizedString(for: when, relativeTo: Date()))")
        } else {
            parts.append("KYC not completed")
        }

        // Device-binding summary.
        switch node.deviceBindingStatus {
        case .bound:      parts.append("device bound")
        case .unbound:    parts.append("device not registered")
        case .mismatched: parts.append("device mismatched")
        }

        // USDOT summary — SKIP for shipper / factoring per UI-SPEC line 419.
        if node.role == .carrier || node.role == .dispatch {
            switch node.usdotAuthorityStatus {
            case .active:        parts.append("USDOT active")
            case .revoked:       parts.append("USDOT revoked")
            case .suspended:     parts.append("USDOT suspended")
            case .notApplicable: break // skip
            }
        }

        var label = parts.joined(separator: ", ")
        // D-11 / UI-SPEC line 845 — implicated-suffix appended when this
        // node is in `chainIntegrity.implicatedNodeIDs`.
        if chain.integrity.implicatedNodeIDs.contains(node.partyID) {
            label += ". Implicated in chain compromise."
        }
        return label
    }

    /// Compose the per-edge VoiceOver label per UI-SPEC line 849.
    private func composedEdgeLabel(for edge: TrustEdge, chain: ChainOfTrust) -> String {
        let fromRole = chain.nodes.first(where: { $0.partyID == edge.fromPartyID })?.role.displayName ?? "Party"
        let toRole = chain.nodes.first(where: { $0.partyID == edge.toPartyID })?.role.displayName ?? "Party"
        var label = "Handoff from \(fromRole) to \(toRole), relationship state: \(edge.relationshipState.rawValue)"
        if chain.integrity.implicatedEdgeIDs.contains(edge.edgeID) {
            label += ". Implicated in chain compromise."
        }
        return label
    }

    // MARK: - Layout

    /// Position nodes from role-slot fractional coordinates + the live
    /// canvas dimensions; recompute edge paths; recompute halo paths;
    /// recompute edge companion-view frames + rotation. Pitfall 1 re-attach
    /// for the pulse animation.
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let chain = currentChain else { return }
        // BUG-FIX (Phase 9 device UAT 2026-05-20 — debug session
        // trust-graph-device-bugs): the contentContainer is sized
        // implicitly via Auto Layout (pinned to `scrollView.frameLayoutGuide`
        // in `setUp()`). When `self`'s layoutSubviews fires for the first
        // time after `configure(chainOfTrust:)`, the constraint chain
        // self → scrollView → contentContainer has NOT yet propagated, so
        // `contentContainer.bounds` is still (0, 0) at this point. The
        // pre-fix code then `guard`ed on `canvas.width > 0` and returned
        // early — frame writes for every TrustNodeView never ran, leaving
        // every node parked at the origin (0, 0). The compromised-chain
        // halo CAShapeLayer paths (set further down in this method) also
        // never wrote, so the implicated halo painted a degenerate solid
        // square from its `fillColor` alone with no chrome to occlude it
        // (Bug B). Forcing the inner scroll-view + content-container
        // layout pass here is the LEAST-INVASIVE fix: it flushes the
        // constraint solver through the scroll-view's nested guides
        // before we read `contentContainer.bounds`. The TrustGraphView
        // layout-test suite (TrustGraphViewLayoutTests) pins the
        // resulting frame positions against the role-slot table so a
        // future re-introduction of either bug fails CI.
        scrollView.layoutIfNeeded()
        contentContainer.layoutIfNeeded()
        let canvas = contentContainer.bounds
        guard canvas.width > 0 && canvas.height > 0 else { return }

        // Position each node view from its role's fractional slot.
        let slots = roleSlots
        let nodeSize: CGSize = CGSize(width: 90, height: 90)
        var nodeCenterByPartyID: [String: CGPoint] = [:]
        for nodeView in nodeViews {
            guard let node = chain.nodes.first(where: { $0.partyID == nodeView.partyID }),
                  let slot = slots[node.role] else { continue }
            let cx = canvas.width * slot.x
            let cy = canvas.height * slot.y
            nodeView.frame = CGRect(
                x: cx - nodeSize.width / 2,
                y: cy - nodeSize.height / 2,
                width: nodeSize.width,
                height: nodeSize.height
            )
            nodeCenterByPartyID[node.partyID] = CGPoint(x: cx, y: cy)
        }

        // Halo paths — inset −6pt from the node chrome frame, cornerRadius
        // 12 + 6 (UI-SPEC line 192-193).
        var haloIndex = 0
        for node in chain.nodes where chain.integrity.implicatedNodeIDs.contains(node.partyID)
                                       && chain.integrity.verdict != .clean {
            guard haloIndex < haloLayers.count,
                  let center = nodeCenterByPartyID[node.partyID] else { continue }
            let chromeFrame = CGRect(
                x: center.x - nodeSize.width / 2,
                y: center.y - nodeSize.height / 2,
                width: nodeSize.width,
                height: nodeSize.height
            )
            let path = UIBezierPath(roundedRect: chromeFrame.insetBy(dx: -6, dy: -6),
                                    cornerRadius: 12 + 6)
            haloLayers[haloIndex].path = path.cgPath
            haloIndex += 1
        }

        // Edge paths + arrowheads + companion-view positioning.
        // Walk the same sorted edges we built in configure.
        let sortedEdges = chain.edges.sorted { lhs, rhs in
            if lhs.fromPartyID != rhs.fromPartyID { return lhs.fromPartyID < rhs.fromPartyID }
            return lhs.toPartyID < rhs.toPartyID
        }
        for (idx, edge) in sortedEdges.enumerated() {
            guard idx < edgeLayers.count,
                  let fromC = nodeCenterByPartyID[edge.fromPartyID],
                  let toC = nodeCenterByPartyID[edge.toPartyID] else { continue }
            // Shrink the edge endpoints to the node chrome boundary so the
            // stroke doesn't cross under the node chrome.
            let chromeInset: CGFloat = nodeSize.width / 2
            let path = UIBezierPath()
            let (adjustedFrom, adjustedTo) = endpointsShrunkByChromeRadius(
                from: fromC, to: toC, by: chromeInset
            )
            path.move(to: adjustedFrom)
            path.addLine(to: adjustedTo)
            edgeLayers[idx].path = path.cgPath
            // RESEARCH §2 line 266 — keep stroke constant-in-screen-space
            // across zoom. lineWidth = 2.0 / scrollView.zoomScale.
            edgeLayers[idx].lineWidth = max(0.5, 2.0 / scrollView.zoomScale)

            // Arrowhead at the to-end — 7pt filled triangle in stroke color.
            let arrowPath = arrowheadPath(at: adjustedTo, towards: adjustedFrom, size: 7)
            edgeArrowheadLayers[idx].path = arrowPath.cgPath

            // Companion tap-target view — 28pt band centered on the segment
            // midpoint, rotated to align with the segment direction.
            if idx < edgeCompanionViews.count {
                let companion = edgeCompanionViews[idx]
                let dx = adjustedTo.x - adjustedFrom.x
                let dy = adjustedTo.y - adjustedFrom.y
                let length = sqrt(dx * dx + dy * dy)
                let midX = (adjustedFrom.x + adjustedTo.x) / 2
                let midY = (adjustedFrom.y + adjustedTo.y) / 2
                companion.transform = .identity
                companion.frame = CGRect(x: midX - length / 2, y: midY - 14, width: length, height: 28)
                companion.transform = CGAffineTransform(rotationAngle: atan2(dy, dx))
            }
        }

        // Pitfall 1 re-attach — recompute pulse attachment on every layout.
        startPulseIfNeeded()
    }

    /// Re-attach pulse on size-class / trait changes (Pitfall 1 + D-06
    /// role-slot coordinate switch).
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Size-class flip switches the role-slot coordinate table — re-layout.
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            setNeedsLayout()
        }
        startPulseIfNeeded()
    }

    /// Endpoint trim so the edge stroke stops at the node chrome boundary.
    /// Assumes circular chrome bounds — adequate for the 90×90 rounded
    /// squares we draw; the visual difference at the chrome corner is
    /// imperceptible at the canvas scale.
    private func endpointsShrunkByChromeRadius(
        from: CGPoint, to: CGPoint, by radius: CGFloat
    ) -> (CGPoint, CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 2 * radius else { return (from, to) }
        let ux = dx / length
        let uy = dy / length
        let newFrom = CGPoint(x: from.x + ux * radius, y: from.y + uy * radius)
        let newTo = CGPoint(x: to.x - ux * radius, y: to.y - uy * radius)
        return (newFrom, newTo)
    }

    private func arrowheadPath(at tip: CGPoint, towards: CGPoint, size: CGFloat) -> UIBezierPath {
        let dx = tip.x - towards.x
        let dy = tip.y - towards.y
        let angle = atan2(dy, dx)
        let p = UIBezierPath()
        p.move(to: tip)
        p.addLine(to: CGPoint(
            x: tip.x - size * cos(angle - .pi / 6),
            y: tip.y - size * sin(angle - .pi / 6)
        ))
        p.addLine(to: CGPoint(
            x: tip.x - size * cos(angle + .pi / 6),
            y: tip.y - size * sin(angle + .pi / 6)
        ))
        p.close()
        return p
    }

    // MARK: - Pulse animation (D-15 — compromised ONLY)

    /// Re-attach the pulse animation on compromised halo layers if it's
    /// missing AND reduce-motion is OFF. PATTERNS E3 mirror — the guard
    /// prevents re-adding on every layout pass.
    ///
    /// **Pulse-only-on-compromised invariant**: this method iterates ONLY
    /// `compromisedHaloLayers`. Caution halos (in `haloLayers` but NOT in
    /// `compromisedHaloLayers`) NEVER receive the pulse. The source-level
    /// invariant is the predicate that gates inclusion in
    /// `compromisedHaloLayers` inside `configure(chainOfTrust:)`.
    private func startPulseIfNeeded() {
        guard !isReduceMotionOn else {
            // Reduce-motion ON — strip any existing pulse, paint solid.
            for halo in compromisedHaloLayers {
                halo.removeAnimation(forKey: "pulse")
                halo.opacity = 1.0
            }
            return
        }
        for halo in compromisedHaloLayers {
            guard halo.animation(forKey: "pulse") == nil else { continue }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.6
            pulse.toValue = 1.0
            pulse.duration = 1.2
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            halo.add(pulse, forKey: "pulse")
        }
    }

    // MARK: - Recenter+zoom (D-04)

    /// Recenter on the tapped node and zoom to ~1.8x with a ~250ms
    /// easeInEaseOut animation (RESEARCH §6 lines 626-666). When VoiceOver
    /// is active the zoom is clamped (D-22), so the zoom call is a no-op.
    private func recenterAndZoom(to nodeView: TrustNodeView) {
        guard !isVoiceOverOn else { return }
        let targetScale: CGFloat = 1.8
        let nodeCenter = nodeView.center
        let visibleSize = CGSize(
            width: scrollView.bounds.width / targetScale,
            height: scrollView.bounds.height / targetScale
        )
        let targetRect = CGRect(
            x: nodeCenter.x - visibleSize.width / 2,
            y: nodeCenter.y - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [self] in
            self.scrollView.zoom(to: targetRect, animated: false)
        }
    }

    @objc private func handleEmptyCanvasDoubleTap() {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [self] in
            self.scrollView.setZoomScale(1.0, animated: false)
            self.scrollView.setContentOffset(.zero, animated: false)
        }
    }

    // MARK: - VoiceOver / reduce-motion observers

    /// Re-apply the D-22 VoiceOver clamp + pulse-suppression branch on the
    /// system-state-change notifications. Also called directly by the
    /// `_testInvokeVoiceOverChange(isOn:)` test seam.
    @objc private func accessibilityFeaturesChanged() {
        applyVoiceOverClamp()
        startPulseIfNeeded()
    }

    private func applyVoiceOverClamp() {
        if isVoiceOverOn {
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 1.0
            // Disable per-node + empty-canvas double-tap recognizers.
            emptyCanvasDoubleTap.isEnabled = false
            for nodeView in nodeViews {
                for recognizer in nodeView.gestureRecognizers ?? []
                    where recognizer.name == "trust-node.doubleTap" {
                    recognizer.isEnabled = false
                }
            }
        } else {
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 2.5
            emptyCanvasDoubleTap.isEnabled = true
            for nodeView in nodeViews {
                for recognizer in nodeView.gestureRecognizers ?? []
                    where recognizer.name == "trust-node.doubleTap" {
                    recognizer.isEnabled = true
                }
            }
        }
    }
}

// MARK: - UIScrollViewDelegate (zoom + line-width recompute)

extension TrustGraphView: UIScrollViewDelegate {

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainer
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // RESEARCH §2 line 318 — keep edge stroke constant-in-screen-space.
        for layer in edgeLayers {
            layer.lineWidth = max(0.5, 2.0 / scrollView.zoomScale)
        }
        startPulseIfNeeded()
    }
}

// MARK: - EdgeCompanionView — invisible 28pt tap-target band

/// 28pt-band invisible UIView companion overlaid on each edge's CAShapeLayer
/// stroke (UI-SPEC line 208). The companion carries the single-tap
/// recognizer that surfaces TRUST-04; the CAShapeLayer is chrome-only.
///
/// Width × 28pt is the touch-target band per RESEARCH §1 line 241 — a 28pt
/// band at every realistic edge angle gives ≥ 44pt diagonal hit area
/// (HIG floor).
final class EdgeCompanionView: UIView {

    let edgeID: String
    let edge: TrustEdge
    var onSingleTap: ((String) -> Void)?

    private let singleTap = UITapGestureRecognizer()

    init(edgeID: String, edge: TrustEdge) {
        self.edgeID = edgeID
        self.edge = edge
        super.init(frame: .zero)
        backgroundColor = .clear // invisible — the chrome is the CAShapeLayer.
        // Single-tap recognizer dispatched to the closure.
        singleTap.numberOfTapsRequired = 1
        singleTap.name = "trust-graph.edge.singleTap"
        singleTap.addTarget(self, action: #selector(handleSingleTap))
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("EdgeCompanionView is constructed programmatically only")
    }

    @objc private func handleSingleTap() {
        onSingleTap?(edgeID)
    }
}
