// validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift
//
// Phase 9 Plan 04 — D-01/D-02 iPhone composition: the bill-of-lading
// body shell. UIScrollView + vertical UIStackView container with FIVE
// arranged section placeholders, plus the pinned summary header populated
// by this plan.
//
// === Structural reference (PATTERNS table row 21 — KYCStatusViewController) ===
// The scrollView geometry mirrors KYCStatusViewController:35-50 + 147-177:
//   * outer UIScrollView, alwaysBounceVertical = true.
//   * inner vertical UIStackView, DS.Spacing.lg spacing.
//   * contentStack leading/trailing pin to scrollView.frameLayoutGuide
//     (NOT contentLayoutGuide — frame guide locks the horizontal width so
//     the stack content cannot scroll horizontally; the contentLayoutGuide
//     would otherwise size to the largest subview width).
//   * contentStack top/bottom pin to scrollView.contentLayoutGuide so
//     vertical scroll content size grows with the stack.
//
// === Section composition (UI-SPEC § Section order lines 339-345) ===
//   1. Pinned summary header (THIS plan populates).
//   2. Timeline placeholder (Plan 05 — LOAD-06 StatusTimelineView).
//   3. Freight details placeholder (Plan 05 — freight detail rows).
//   4. Parties placeholder (later plan — inline party list).
//   5. Verdict block placeholder (Plan 09 — chain-integrity verdict block,
//      `isHidden = true` by default; Plan 09 unhides when verdict != .clean).
//
// Plan 06 (TrustGraphView) does NOT live inside this body view — the
// trust graph is the dominant region ABOVE the body on iPhone, and lives
// in the LEFT pane on iPad. The body view is the scrollable bill-of-
// lading content (D-02). Plan 09 manages the iPad split-pane geometry
// from the VC level; the body view itself never branches on size class.
//
// === Pinned summary header content (UI-SPEC § Pinned summary header lines 149-159) ===
// Horizontal stack: reference-number label + origin→destination label +
// reused Phase 8 LoadStatusBadgeView. All labels carry
// `adjustsFontForContentSizeCategory = true` for Dynamic Type support.
//
// === Accessibility identifier namespace (UI-SPEC lines 760-775) ===
//   - root view: "load-detail.body"
//   - pinned-header container: "load-detail.pinned-header"
//   - reference-number label: "load-detail.pinned-header.reference-number"
//   - status badge: "load-detail.pinned-header.status-badge"
//   - timeline container: "load-detail.timeline"
//   - freight container: "load-detail.body.freight-section"
//   - parties container: "load-detail.body.parties-section"
//   - verdict block container: "load-detail.body.verdict-block"
// Downstream plans inject their actual content INTO these named
// containers; the identifier on the container survives the inject.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): the body view consumes
// ONLY `load.referenceNumber`, `load.origin`, `load.destination`, and
// `load.status` — none of which are trust-bearing. The body view does NOT
// inspect the trust-graph payload fields (per-node trust state, chain-
// level verdict, flagged-party-ID set); those land in Plans 06 and 09.
// T-09-04 (PII): the body view never logs. Per the Phase 8 LoadListView
// Controller file-header lock (T-08-08), the view layer is logging-free.

import UIKit

public final class LoadDetailBodyView: UIView {

    // MARK: - ScrollView + contentStack (PATTERNS table row 21)

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.lg
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - Pinned summary header (populated by THIS plan)

    private let referenceNumberLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.headline
        l.textColor = DS.Colors.label
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        // Reference number gets the highest content-hugging priority so it
        // wins screen space over the origin→destination at AX5+ when the
        // pinned header truncates.
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.accessibilityIdentifier = "load-detail.pinned-header.reference-number"
        return l
    }()

    private let originDestinationLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.label
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.lineBreakMode = .byTruncatingTail
        l.numberOfLines = 1
        return l
    }()

    private let statusBadge: LoadStatusBadgeView = {
        let v = LoadStatusBadgeView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.pinned-header.status-badge"
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        return v
    }()

    private let pinnedSummaryHeader: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.surface
        v.accessibilityIdentifier = "load-detail.pinned-header"
        return v
    }()

    // MARK: - Section placeholder containers (downstream plans populate)

    /// Timeline placeholder. Plan 05 populates this with a
    /// `StatusTimelineView` (D-17 stepper + current-state card). The
    /// container preserves the locked `load-detail.timeline` identifier
    /// as the addressable target for XCUITest; the hosted view also
    /// carries the same identifier (set inside `StatusTimelineView.
    /// setUp()`) so either lookup resolves the same accessibility node.
    let timelineContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.timeline"
        return v
    }()

    /// Plan 05 — the hosted status timeline (D-17 + D-18). Mounted into
    /// `timelineContainer` in `setUp()`; configured on every
    /// `configure(load:)` from the load's `stateHistory`.
    private let statusTimeline = StatusTimelineView()

    let freightDetailsContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.body.freight-section"
        return v
    }()

    let partiesContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.body.parties-section"
        return v
    }()

    /// Verdict-block placeholder — Plan 09 (D-15 chain-integrity verdict
    /// block) unhides this when the chain verdict != .clean. Hidden by
    /// default so the body has clean layout for clean loads.
    let verdictBlockContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.body.verdict-block"
        v.isHidden = true
        return v
    }()

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadDetailBodyView is constructed programmatically only")
    }

    // MARK: - Layout

    private func setUp() {
        backgroundColor = DS.Colors.background
        accessibilityIdentifier = "load-detail.body"

        // Compose the pinned summary header: horizontal stack of
        // [referenceNumber] [originDestination] [statusBadge].
        let headerStack = UIStackView(arrangedSubviews: [
            referenceNumberLabel,
            originDestinationLabel,
            statusBadge,
        ])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = DS.Spacing.sm
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        pinnedSummaryHeader.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(
                equalTo: pinnedSummaryHeader.leadingAnchor, constant: DS.Spacing.md),
            headerStack.trailingAnchor.constraint(
                equalTo: pinnedSummaryHeader.trailingAnchor, constant: -DS.Spacing.md),
            headerStack.topAnchor.constraint(
                equalTo: pinnedSummaryHeader.topAnchor, constant: DS.Spacing.sm),
            headerStack.bottomAnchor.constraint(
                equalTo: pinnedSummaryHeader.bottomAnchor, constant: -DS.Spacing.sm),
        ])

        // Assemble the vertical stack — 5 sections per UI-SPEC § Section order.
        // Each placeholder is left empty for downstream plans to populate.
        contentStack.addArrangedSubview(pinnedSummaryHeader)
        contentStack.addArrangedSubview(timelineContainer)
        contentStack.addArrangedSubview(freightDetailsContainer)
        contentStack.addArrangedSubview(partiesContainer)
        contentStack.addArrangedSubview(verdictBlockContainer)

        // Plan 05 — mount the status timeline inside its container,
        // pinned edge-to-edge. The container survives across configure
        // calls; only `statusTimeline.configure(load:)` re-runs on data
        // refresh.
        statusTimeline.translatesAutoresizingMaskIntoConstraints = false
        timelineContainer.addSubview(statusTimeline)
        NSLayoutConstraint.activate([
            statusTimeline.topAnchor.constraint(equalTo: timelineContainer.topAnchor),
            statusTimeline.leadingAnchor.constraint(equalTo: timelineContainer.leadingAnchor),
            statusTimeline.trailingAnchor.constraint(equalTo: timelineContainer.trailingAnchor),
            statusTimeline.bottomAnchor.constraint(equalTo: timelineContainer.bottomAnchor),
        ])

        // Mount the scrollView + contentStack — PATTERNS table row 21.
        addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            // ScrollView fills the body view.
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // ContentStack horizontal: pin to scrollView.frameLayoutGuide
            // (locks horizontal width — no horizontal scroll).
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            // ContentStack vertical: pin to scrollView.contentLayoutGuide
            // (content height drives scroll size).
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Plan 09 — pinned-header visibility flag (D-01 / I-05 locked path)

    /// When `true`, the embedded `pinnedSummaryHeader` is hidden — the
    /// `LoadDetailViewController` owns a top-level pinned-header instance
    /// instead (iPhone composition: header at the top of the VC view, above
    /// the chain-integrity banner). When `false` (default), the body's
    /// embedded pinned header is shown (iPad composition: header at the
    /// top of the right pane). The flag is the LOCKED path per Plan 09
    /// I-05 — Planner ruled out extracting `PinnedSummaryHeaderView` into
    /// its own type; the body keeps the pinned-header subview and the VC
    /// controls visibility through this flag.
    public var hidesPinnedSummaryHeader: Bool = false {
        didSet {
            pinnedSummaryHeader.isHidden = hidesPinnedSummaryHeader
        }
    }

    // MARK: - Plan 09.1 — nested-scroll support for iPhone vertical-tree composition

    /// When `true`, the embedded `scrollView` does not scroll on its own —
    /// the body's contentStack drives the view's intrinsic height so the
    /// VC's outer iPhone-vertical-tree scroll view owns scrolling for the
    /// whole composition (strip + card + body sections scroll as one).
    /// When `false` (default — preserves the Phase 9 standalone iPad +
    /// DEBUG-legacy posture), the body's scrollView scrolls internally.
    ///
    /// Setting `true` ALSO activates a height constraint pinning the body
    /// view's height to the contentStack's height so the body grows
    /// vertically with its content (instead of clipping to the parent's
    /// frame). The constraint is deactivated when the flag flips back.
    ///
    /// Plan 09.1 R8: the iPhone vertical-tree composition wraps
    /// `[EveryoneOnLoadStripView, ChainOfVouchesView, LoadDetailBodyView]`
    /// in the VC's outer `iPhoneVerticalTreeScrollView`. With this flag
    /// set, scrolling lives entirely on the outer scroll view — no nested
    /// `UIScrollView` rubber-band fight.
    public var isInternalScrollEnabled: Bool = true {
        didSet {
            guard isInternalScrollEnabled != oldValue else { return }
            scrollView.isScrollEnabled = isInternalScrollEnabled
            updateIntrinsicHeightPin()
        }
    }

    /// Active when `isInternalScrollEnabled == false`. Pins the body view's
    /// height to the contentStack's height so the body grows vertically
    /// with its content (the outer VC scroll view scrolls the whole stack).
    private var intrinsicHeightPin: NSLayoutConstraint?

    private func updateIntrinsicHeightPin() {
        intrinsicHeightPin?.isActive = false
        intrinsicHeightPin = nil
        if !isInternalScrollEnabled {
            let pin = heightAnchor.constraint(equalTo: contentStack.heightAnchor)
            pin.priority = .required
            pin.isActive = true
            intrinsicHeightPin = pin
        }
    }

    // MARK: - Public API — populate the pinned summary header from a Load

    /// Populate the pinned summary header content from the Decodable Load.
    ///
    /// Per T-09-03: this consumes ONLY the four pinned-header fields
    /// (referenceNumber, origin, destination, status). No trust-payload
    /// fields are inspected. The reference number renders verbatim per
    /// UI-SPEC § Copywriting line 654 ("no prefix"); the origin →
    /// destination follows the Phase 8 LoadRowCell format
    /// `"City, ST → City, ST"` with the literal U+2192 arrow.
    public func configure(load: Load) {
        referenceNumberLabel.text = load.referenceNumber
        originDestinationLabel.text =
            "\(load.origin.city), \(load.origin.state) → \(load.destination.city), \(load.destination.state)"
        statusBadge.configure(status: load.status)

        // Plan 05 — cascade the configure into the hosted timeline. The
        // timeline reads only `load.stateHistory` (D-02) — no trust-payload
        // fields, preserving the T-09-03 separation locked at this file's
        // top.
        statusTimeline.configure(load: load)
    }

    /// Plan 09 (D-01 / I-05 locked path) — convenience overload that
    /// applies the `hidesPinnedSummaryHeader` flag in the same call as the
    /// Load-driven configure. The VC calls this in its `render(state:)`
    /// `.loaded(...)` branch after picking the composition layout for the
    /// current `horizontalSizeClass`.
    ///
    /// Equivalent to `hidesPinnedSummaryHeader = hidesPinnedHeader` followed
    /// by `configure(load:)`, surfaced as a single method so the VC's
    /// composition-driven configure path is one atomic call instead of two.
    public func configure(load: Load, hidesPinnedHeader: Bool) {
        hidesPinnedSummaryHeader = hidesPinnedHeader
        configure(load: load)
    }

    // MARK: - Plan 09 — install the chain-integrity verdict block (D-02)

    /// Populate the in-body chain-integrity verdict block from the chain
    /// integrity payload. Called by `LoadDetailViewController.render(state:)`
    /// AFTER `configure(load:)` (the VC owns the chainOfTrust storage from
    /// Plan 07). For `verdict == .clean` the slot collapses to zero height
    /// (`isHidden = true`); the verdict block view is NOT instantiated.
    ///
    /// Per T-09-03: every input (`verdict`, `reason`, `implicatedNodeCount`)
    /// is server-supplied; no client derivation. Per T-09-04: `reason`
    /// flows verbatim into the block's body text — no logger touches it.
    ///
    /// Idempotent: clears any prior block before re-installing so repeated
    /// `render(state:)` cycles do not leak views.
    public func installVerdictBlock(verdict: ChainIntegrity.Verdict,
                                    reason: String?,
                                    implicatedNodeCount: Int) {
        // Clear any prior block — the container survives across render
        // cycles, only the content is rebuilt.
        verdictBlockContainer.subviews.forEach { $0.removeFromSuperview() }

        guard verdict != .clean else {
            // Clean → no block, slot collapses (the parent contentStack
            // uses .fill alignment, so an empty hidden subview drops out
            // of layout).
            verdictBlockContainer.isHidden = true
            return
        }

        let block = ChainIntegrityVerdictBlockView(
            verdict: verdict,
            reason: reason,
            implicatedNodeCount: implicatedNodeCount
        )
        block.translatesAutoresizingMaskIntoConstraints = false
        verdictBlockContainer.addSubview(block)
        NSLayoutConstraint.activate([
            block.topAnchor.constraint(equalTo: verdictBlockContainer.topAnchor),
            block.bottomAnchor.constraint(equalTo: verdictBlockContainer.bottomAnchor),
            block.leadingAnchor.constraint(equalTo: verdictBlockContainer.leadingAnchor),
            block.trailingAnchor.constraint(equalTo: verdictBlockContainer.trailingAnchor),
        ])
        verdictBlockContainer.isHidden = false
    }
}
