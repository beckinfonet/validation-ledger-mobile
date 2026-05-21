// validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
// Phase 9 LOAD-05 / D-01 / D-20 — the programmatic-UIKit detail VC shell.
//
// === Plan 09 (D-01/D-02/D-03/D-15/D-16/D-19/D-21) composition refactor ===
// This file evolved through Plans 03 → 04 → 06 → 07 → 08; Plan 09 is the
// composition refactor that ships the chain-integrity banner + verdict
// block + iPhone-vs-iPad layout branch + D-21 accessibility traversal
// order + iPad-split skeleton silhouette.
//
// Layout topology, by horizontalSizeClass:
//   iPhone (.compact):
//     view (VC.view)
//     ├─ pinnedHeaderTopLevelView (NEW top-level — duplicate pinned header
//     │  owned by the VC; pinned to safeAreaLayoutGuide.top; bodyView's
//     │  embedded pinned header is hidden via hidesPinnedSummaryHeader=true)
//     ├─ chainIntegrityBanner (rendered when verdict != .clean; pinned
//     │  below pinned header)
//     ├─ trustGraphView (pinned below banner; height ~62% of view.safeArea
//     │  height — D-01 dominance)
//     └─ bodyView (pinned below trustGraphView; full body below the graph)
//   iPad (.regular):
//     view
//     ├─ chainIntegrityBanner (rendered when verdict != .clean; pinned to
//     │  safeAreaLayoutGuide.top, full width above the split)
//     └─ horizontalSplit:
//         ├─ trustGraphView (left 60% — graph fills the dominant pane)
//         └─ rightPaneContainer (right 40%; bodyView with embedded pinned
//             header shown — hidesPinnedSummaryHeader=false)
//
// === D-21 VoiceOver traversal order ===
// The VC's `view.accessibilityElements` array is published after every
// `render(state:)` `.loaded` pass + after every composition rebuild on
// `traitCollectionDidChange(_:)`. Order:
//   iPhone: [pinnedHeader, banner-if-non-clean, trustGraphView, bodyView]
//   iPad:   [banner-if-non-clean, bodyView (right pane first — freight
//            metadata before the graph), trustGraphView]
// The bodyView is itself a single accessibility container — its embedded
// timeline / freight rows / parties / verdict-block sub-elements are
// VoiceOver-walkable inside it via the system default.
//
// === Composition rebuild safety (T-09-11) ===
// `traitCollectionDidChange(_:)` deactivates the prior composition's
// constraints + reassembles the new geometry, but it does NOT tear down
// the `trustGraphView` / `bodyView` / `skeletonView` instances. The pulse
// animation lifecycle is preserved across rebuilds (Pitfall 1 / RESEARCH
// §2 line 967): TrustGraphView.traitCollectionDidChange(_:) re-attaches
// the pulse on every trait change; that handler still fires because the
// instance is reused. The graph's zoomScale + contentOffset are explicitly
// captured before teardown + restored after (UI-SPEC line 813).
//
// === Error-state hand-rolled rationale (D-20, Phase 8 § Don't Hand-Roll exception) ===
// `UIContentUnavailableView` is the iOS-17-native error-state container,
// but its `Configuration.button` does NOT surface an
// `accessibilityIdentifier` field — the button's identifier cannot be
// locked from outside. Phase 8's UI-SPEC § Don't Hand-Roll Exceptions
// documents this case as the sanctioned exception to "prefer the system
// container." The LoadListViewController error-state (Phase 8 Plan 03,
// lines 240-298) is the canonical hand-rolled template Phase 9 mirrors here.
//
// === D-20 state subviews are pre-attached, hidden by default ===
// Three sibling container views (`skeletonContainer`, `errorContainer`,
// `bodyContainer`) are added in `layoutContent()`. `render(state:)` toggles
// `isHidden` per case. The containers stay attached across state transitions
// so subviews are installed ONCE.
//
// === Zero logging (T-08-08 / T-09-04 — VIEW-LAYER LOCK) ===
// This file has ZERO `Logger` / `os_log` / `OSLog` calls. The VM does any
// logging the screen produces. Per the Phase 8 LoadListViewController file-
// header lock (T-08-08), the view layer is logging-free — a value the
// negative grep gate in 09-04-PLAN acceptance criteria enforces.
//
// === Zero PII leak from .error state (T-09-04) ===
// The VM's error case carries the locked localized generic copy from
// `LoadDetailViewModel.userFacingMessage(for:)` (Plan 03) as its
// associated value, but `render(state:)` IGNORES that associated value
// entirely. The error-state UI renders only the three locked
// NSLocalizedString copies — heading, body, retry-button title.
//
// === Accessibility identifier namespace ===
// `view.accessibilityIdentifier = "load-detail"` (the LOCKED root per
// UI-SPEC § Accessibility identifiers). Per-container identifiers:
//   - `load-detail.skeleton`
//   - `load-detail.error-state`
//   - `load-detail.error-state.retry`
//   - `load-detail.body`
//   - `chain-integrity-banner` (Plan 09 — the marquee fraud banner)
//   - `load-detail.pinned-header` (when iPhone top-level; the body's
//                                  embedded header carries the same id)
//
// === iOS 17 deployment minimum ===
// No iOS 18-only APIs used. `traitCollection.horizontalSizeClass`,
// `safeAreaLayoutGuide`, `UIView.isHidden`, `UIStackView`,
// `UIButton.Configuration.borderedProminent()`, are iOS 13+.

import UIKit

#if DEBUG
/// Phase 9.1 D-12 / D-13 / D-14 — DEBUG-only launch-arg toggle that flips the
/// iPhone Load Detail composition from the new vertical-tree layout
/// (`EveryoneOnLoadStripView` + `ChainOfVouchesView`) back to the Phase 9
/// 2D `TrustGraphView` + standalone `ChainIntegrityBannerView`.
///
/// **Off by default** — Release builds never compile this enum (entire
/// declaration is `#if DEBUG`); the iPhone-2D code path is unreachable in
/// production (D-13). DEBUG builds still have to be **explicitly opted in**
/// via Xcode → Edit Scheme → Run → Arguments → Arguments Passed On Launch.
///
/// Use cases (D-14): App Store / marketing screenshots, press shots, demo
/// videos — the Phase 9 pulse-on-compromised halo is visually striking and
/// dramatizes the fraud archetypes even though the 2D layout is unreadable
/// for actual chain-reading at iPhone widths. The flag preserves that
/// artifact without dragging dead code into the Release binary.
///
/// Mirrors the `MockDefaultFixtures.verifiedKYCStatusLaunchFlag` precedent
/// (`Core/Networking/Mock/MockDefaultFixtures.swift:60-76`): same
/// `ProcessInfo.processInfo.arguments.contains(...)` parse shape, same
/// `#if DEBUG` gating, same launch-arg literal cadence.
public enum Debug2DGraphOverride {
    /// Locked launch-arg literal (D-12). Add to a scheme's arguments to
    /// force the legacy 2D TrustGraphView on the iPhone code path.
    public static let launchFlag = "-Mock2DTrustGraphOnIPhone"

    /// True when `-Mock2DTrustGraphOnIPhone` is present in this process's
    /// launch arguments. Evaluated once per composition build (cheap —
    /// argv is a tiny array). `public` so the
    /// `LoadDetailViewControllerDebug2DOverrideTests` suite can lock the
    /// default-off contract (D-14).
    public static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchFlag)
    }
}
#endif

public final class LoadDetailViewController: UIViewController {

    // MARK: - CompositionLayout (Plan 09 — iPhone single-column vs iPad split)

    /// Layout posture for the current `traitCollection.horizontalSizeClass`.
    /// iPhone compact → `.iPhoneCompact`; iPad regular → `.iPadRegularSplit`.
    /// `traitCollectionDidChange(_:)` flips this when the size class
    /// crosses the boundary, then calls `buildLayoutForCurrentComposition()`.
    private enum CompositionLayout {
        case iPhoneCompact
        case iPadRegularSplit
    }

    /// Current layout posture. Initialized in `viewDidLoad` from the trait
    /// collection's initial value.
    private var compositionLayout: CompositionLayout = .iPhoneCompact

    // MARK: - Dependencies

    private let viewModel: LoadDetailViewModel

    // MARK: - Skeleton (D-19) — Plan 04 populates the container with this subview

    private let skeletonView = LoadDetailSkeletonView()

    // MARK: - Body (D-01 / D-02) — Plan 04 populates the container with this subview

    private let bodyView = LoadDetailBodyView()

    // MARK: - Trust graph (Plan 06 — D-01 / D-04 / D-06 / D-15 / D-22)
    //
    // The MARQUEE region of the screen. Plan 09 places it ABOVE `bodyView`
    // on iPhone (with the pinned-header + banner stacked above it) and in
    // the LEFT 60% of the iPad split. Trust graph height locks to ~62% of
    // the safe-area height on iPhone per UI-SPEC line 119 (D-01 dominance).

    private let trustGraphView = TrustGraphView()

    // MARK: - Phase 9.1 iPhone vertical-tree components (R3 / R4 / R5 / R8)
    //
    // On iPhone compact, these REPLACE the Phase 9 `trustGraphView` + the
    // standalone `chainIntegrityBanner` mount (R4 — the verdict pill is now
    // folded INSIDE `chainOfVouchesView`'s footer). On iPad regular, neither
    // is mounted — the Phase 9 composition (TrustGraphView + standalone
    // banner) is preserved verbatim (R10).
    //
    // The DEBUG-only `-Mock2DTrustGraphOnIPhone` flag flips the iPhone path
    // back to the Phase 9 composition for marketing screenshots (D-12 /
    // D-13 / D-14). Release builds cannot reach the iPhone-2D code path
    // (the flag enum is `#if DEBUG`-only).

    private let everyoneOnLoadStripView = EveryoneOnLoadStripView()
    private let chainOfVouchesView = ChainOfVouchesView()

    // MARK: - iPhone vertical-tree outer scroll (Plan 09.1 R8)
    //
    // Wraps `[everyoneOnLoadStripView, chainOfVouchesView, bodyView]` so the
    // whole composition scrolls as one. Set up lazily on the first iPhone
    // vertical-tree composition build; reused across rebuilds.
    private let iPhoneVerticalTreeScrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        s.backgroundColor = DS.Colors.background
        // Identifier so XCUITest probes (and the LoadDetailViewControllerCompositionTests
        // subview walks) can find the scroll view deterministically.
        s.accessibilityIdentifier = "load-detail.iphone-vertical-tree.scroll-view"
        return s
    }()

    private let iPhoneVerticalTreeContentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = 0  // per-pair custom spacing applied via setCustomSpacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// Last union-rect computed by `handleStripChipTap(role:)` — exposed
    /// under `#if DEBUG` for the W1 union-rect assertion in
    /// `LoadDetailViewControllerCompositionTests`. The composition test
    /// invokes the chip-tap handler then reads this property to verify
    /// the rect spans MULTIPLE rows for multi-node roles (VL-1009 BRK).
    #if DEBUG
    internal var lastUnionRectForTesting: CGRect?
    #endif

    // MARK: - Chain-integrity banner (Plan 09 — D-15 / D-16)
    //
    // Built FRESH on every `render(state:)` `.loaded` pass — the banner's
    // verdict + reason are stored at init time, so a new chainOfTrust
    // verdict requires a new banner instance. The banner self-hides when
    // verdict == .clean (intrinsicContentSize == .zero, isHidden == true);
    // when non-clean it occupies the locked 36pt height with verdict-tier
    // background.

    private var chainIntegrityBanner: ChainIntegrityBannerView?

    // MARK: - Pinned summary header — top-level instance for iPhone (Plan 09)
    //
    // iPhone composition (D-01): the pinned header lives ABOVE the graph
    // at the top of the VC view. The body's embedded pinned header is
    // hidden via `bodyView.hidesPinnedSummaryHeader = true`. iPad
    // composition (D-03): this property is nil — the body's embedded
    // header stays visible at the top of the right pane.
    //
    // The iPhone instance is a duplicate of the body's embedded header — by
    // design (I-05 locked path: do NOT extract PinnedSummaryHeaderView into
    // a new type; keep the duplicate render so the body remains a
    // self-contained surface for the iPad path).

    private var pinnedHeaderTopLevelView: UIView?
    private var pinnedHeaderReferenceLabel: UILabel?
    private var pinnedHeaderOriginDestLabel: UILabel?
    private var pinnedHeaderStatusBadge: LoadStatusBadgeView?

    // MARK: - Cached chain (Plan 07 — node-tap → verification-basis sheet)

    private var cachedChainOfTrust: ChainOfTrust?

    /// Cached load — the most recent `.loaded(load, ...)` payload. Stored so
    /// composition rebuilds (e.g. a rotation that flips horizontalSizeClass)
    /// can re-populate the body + pinned header without re-fetching.
    private var cachedLoad: Load?

    // MARK: - Composition constraints (deactivated/re-built on rebuild)

    /// Constraints belonging to the current composition. Deactivated +
    /// emptied at the start of every `buildLayoutForCurrentComposition()`
    /// call so a size-class flip cleanly tears down the prior topology.
    private var compositionConstraints: [NSLayoutConstraint] = []

    // MARK: - State containers (D-20 — pre-attached, isHidden-toggled)

    /// Skeleton-with-shimmer container. Hosts `skeletonView` (D-19).
    private let skeletonContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.skeleton"
        v.isHidden = true
        return v
    }()

    /// Error-state container. Hosts the hand-rolled error UI per the
    /// Phase 8 § Don't Hand-Roll exception (D-20).
    private let errorContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.error-state"
        v.isHidden = true
        return v
    }()

    /// Body container — Plan 09 owns the iPhone vs iPad composition geometry
    /// inside this container. Stays attached across state transitions.
    private let bodyContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.body"
        v.isHidden = true
        return v
    }()

    // MARK: - iPad split right-pane container (Plan 09 — D-03)
    //
    // Pre-allocated so its identity is stable across composition rebuilds.
    // Mounted into `bodyContainer` only when `compositionLayout ==
    // .iPadRegularSplit`. Hosts the pinned header (body-owned) + the body
    // view stacked below.
    private let rightPaneContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        return v
    }()

    // MARK: - Error-state UI (D-20 — hand-rolled per Phase 8 § Don't Hand-Roll exception)

    private let errorIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        iv.contentMode = .scaleAspectFit
        iv.tintColor = DS.Colors.destructive
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        return iv
    }()

    private let errorHeading: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.title1
        l.textColor = DS.Colors.label
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "loads.detail.error.heading",
            value: "We couldn't load this load",
            comment: "Phase 9 LoadDetailViewController — error-state heading (UI-SPEC §Copywriting line 739)"
        )
        return l
    }()

    private let errorBody: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "loads.detail.error.body",
            value: "Check your connection and try again. The load record is safe.",
            comment: "Phase 9 LoadDetailViewController — error-state body (UI-SPEC §Copywriting line 740). The second sentence reassures: user has no local mutation to lose."
        )
        return l
    }()

    private let errorRetryButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "loads.detail.error.retry",
            value: "Try again",
            comment: "Phase 9 LoadDetailViewController — error-state retry CTA (UI-SPEC §Copywriting line 741)"
        )
        let b = UIButton(configuration: cfg)
        b.tintColor = DS.Colors.primary
        b.accessibilityIdentifier = "load-detail.error-state.retry"
        // 44pt min touch target (CLAUDE.md HIG compliance baseline).
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return b
    }()

    // MARK: - Init

    public init(viewModel: LoadDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadDetailViewController is constructed programmatically only")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        view.accessibilityIdentifier = "load-detail"

        // Pre-attach the three state containers + install per-state subviews.
        layoutBaseContainers()
        installSkeletonView()
        installBodyViewIntoContainer()
        installErrorView()

        // Set the initial compositionLayout from the trait collection AND
        // build the body's composition geometry for that posture.
        compositionLayout = (traitCollection.horizontalSizeClass == .regular)
            ? .iPadRegularSplit
            : .iPhoneCompact
        skeletonView.renderMode = (compositionLayout == .iPadRegularSplit)
            ? .iPadSplit : .iPhonePortrait
        buildLayoutForCurrentComposition()

        // Plan 09.1 — replace the Phase 9 `traitCollectionDidChange(_:)`
        // override with the iOS 17 `registerForTraitChanges` API (RESEARCH
        // Example 3). The closure body delegates to `handleSizeClassChange()`
        // which keeps the existing Phase 9 rebuild logic intact.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (vc: LoadDetailViewController, _: UITraitCollection) in
            vc.handleSizeClassChange()
        }

        wireActions()
        bindViewModel()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // WR-03 fix (Phase 9 review): only fetch when we have no data yet
        // (.loading or .error). If we're already .loaded, every sheet
        // dismissal (verification-basis / handoff-detail) would otherwise
        // re-fire the network request, flash the skeleton over the user's
        // already-rendered content, and re-replace the chain-of-trust
        // payload — visible UI churn and unnecessary load on the backend.
        // Pull-to-refresh + the .error retry CTA remain on the
        // unconditional fetch path (they call fetchLoadDetail() directly).
        switch viewModel.state {
        case .loaded:
            return
        case .loading, .error:
            // Capture `viewModel` to avoid a [weak self] guard for the simple
            // single-call case — the VM is owned by `self`, so its lifetime is
            // bounded by the VC's.
            Task { [viewModel] in await viewModel.fetchLoadDetail() }
        }
    }

    // MARK: - Composition rebuild on size-class flip (Plan 09 / D-03 / Pitfall 1)

    /// On `horizontalSizeClass` change, tear down the prior body composition
    /// constraints + rebuild for the new posture. Preserves the
    /// `trustGraphView` / `bodyView` / `skeletonView` instances so their own
    /// `traitCollectionDidChange(_:)` handlers re-attach
    /// pulse / shimmer (Pitfall 1). Restores `scrollView.zoomScale +
    /// contentOffset` per UI-SPEC line 813.
    ///
    /// Plan 09.1 (RESEARCH Example 3): invoked from the iOS 17
    /// `registerForTraitChanges` closure registered in `viewDidLoad`. The
    /// override-based `traitCollectionDidChange(_:)` method is no longer
    /// present (the closure-based API supersedes it for size-class-bounded
    /// rebuilds).
    internal func handleSizeClassChange() {
        handleSizeClassChange(forceRebuild: false)
    }

    /// Internal seam for unit tests: `forceRebuild: true` rebuilds the
    /// composition even when the size class did not change (used by the
    /// trait-override pattern in `LoadDetailViewController*Tests.swift`
    /// where the override is applied AFTER viewDidLoad has already laid
    /// out the initial composition).
    internal func handleSizeClassChange(forceRebuild: Bool) {
        let newCompositionLayout: CompositionLayout =
            (traitCollection.horizontalSizeClass == .regular)
            ? .iPadRegularSplit
            : .iPhoneCompact
        // Guard: avoid rebuild if the size class didn't actually flip
        // (registerForTraitChanges fires on any registered trait change),
        // unless the caller explicitly requested one.
        guard forceRebuild || newCompositionLayout != compositionLayout else { return }

        // Preserve the graph's pan/zoom state across the rebuild (UI-SPEC line 813).
        let savedZoom = trustGraphView.scrollView.zoomScale
        let savedOffset = trustGraphView.scrollView.contentOffset

        // Tear down composition constraints (but NOT the views themselves).
        NSLayoutConstraint.deactivate(compositionConstraints)
        compositionConstraints.removeAll()

        // Flip composition + skeleton render mode.
        compositionLayout = newCompositionLayout
        skeletonView.renderMode = (compositionLayout == .iPadRegularSplit)
            ? .iPadSplit : .iPhonePortrait

        // Rebuild for the new posture.
        buildLayoutForCurrentComposition()

        // Restore graph state.
        trustGraphView.scrollView.zoomScale = savedZoom
        trustGraphView.scrollView.contentOffset = savedOffset

        // Re-populate body content from the cached payload so the new
        // composition's surfaces render with current data (the body's
        // pinned-header flag is part of the composition contract — needs
        // a re-configure to apply the new posture).
        if let load = cachedLoad, let chain = cachedChainOfTrust {
            applyLoadedRender(load: load, chainOfTrust: chain)
        } else {
            // No cached payload yet — just refresh accessibility ordering
            // for the new composition.
            updateAccessibilityElements()
        }
    }

    // MARK: - Base container layout (state-machine sibling containers)

    private func layoutBaseContainers() {
        view.addSubview(bodyContainer)
        view.addSubview(skeletonContainer)
        view.addSubview(errorContainer)

        let guide = view.safeAreaLayoutGuide
        // All three containers pin edge-to-edge in the safe area. Plan 09's
        // iPhone-vs-iPad composition lives INSIDE `bodyContainer`; the
        // skeleton + error containers stay single-column on both devices.
        NSLayoutConstraint.activate([
            bodyContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            skeletonContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            skeletonContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            skeletonContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            skeletonContainer.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            errorContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }

    /// Pin `skeletonView` (D-19) edge-to-edge inside `skeletonContainer`.
    private func installSkeletonView() {
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        skeletonContainer.addSubview(skeletonView)
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: skeletonContainer.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: skeletonContainer.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: skeletonContainer.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: skeletonContainer.bottomAnchor),
        ])
    }

    /// Pre-add `bodyView` + `trustGraphView` + `rightPaneContainer` as
    /// subviews of `bodyContainer` (without composition constraints) so the
    /// view-hierarchy identity is stable across rebuilds.
    ///
    /// Plan 09.1 R8: `everyoneOnLoadStripView` and `chainOfVouchesView` are
    /// NOT pre-attached here — they only ever live inside
    /// `iPhoneVerticalTreeContentStack` (which itself is only mounted by
    /// `buildIPhoneLayoutVerticalTree()`). The Phase 9 CR-02 reparenting
    /// fix does NOT apply to them (Pitfall 4) — they're iPhone-only and
    /// never move between bodyContainer and rightPaneContainer.
    private func installBodyViewIntoContainer() {
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        trustGraphView.translatesAutoresizingMaskIntoConstraints = false
        rightPaneContainer.translatesAutoresizingMaskIntoConstraints = false

        bodyContainer.addSubview(trustGraphView)
        bodyContainer.addSubview(bodyView)
        bodyContainer.addSubview(rightPaneContainer)
        // rightPaneContainer is only used by iPad composition; hidden until
        // the iPad layout activates it (avoids invisible-but-positioned
        // chrome on iPhone).
        rightPaneContainer.isHidden = true
    }

    /// Assemble the hand-rolled error-state subviews per D-20.
    private func installErrorView() {
        let stack = UIStackView(arrangedSubviews: [errorIcon, errorHeading, errorBody, errorRetryButton])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.xl, left: DS.Spacing.lg,
            bottom: DS.Spacing.xl, right: DS.Spacing.lg
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        errorContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.trailingAnchor),
        ])
    }

    // MARK: - Composition rebuild (Plan 09 — D-01/D-02/D-03)

    /// Activate the appropriate composition for `compositionLayout`.
    /// Records every activated constraint into `compositionConstraints` so
    /// the next size-class flip can deactivate the whole set in one call.
    private func buildLayoutForCurrentComposition() {
        switch compositionLayout {
        case .iPhoneCompact:
            buildIPhoneLayout()
        case .iPadRegularSplit:
            buildIPadSplitLayout()
        }
        view.setNeedsLayout()
    }

    /// Plan 09.1 R5 — dispatcher for the iPhone composition. The default path
    /// (Release + DEBUG without the `-Mock2DTrustGraphOnIPhone` launch flag)
    /// is the new vertical-tree layout from Plans 03 + 04. The DEBUG-only
    /// branch under the flag preserves the Phase 9 2D `TrustGraphView` +
    /// standalone `ChainIntegrityBannerView` composition verbatim (D-12 /
    /// D-13 / D-14 — marketing screenshots use case).
    private func buildIPhoneLayout() {
        #if DEBUG
        if Debug2DGraphOverride.isActive {
            buildIPhoneLayoutLegacyTrustGraph()
            return
        }
        #endif
        buildIPhoneLayoutVerticalTree()
    }

    /// Plan 09.1 R8 — the iPhone vertical-tree composition that mounts
    /// `[pinnedHeader]` above an outer scroll view containing
    /// `[EveryoneOnLoadStripView, ChainOfVouchesView, LoadDetailBodyView]`.
    /// The standalone `ChainIntegrityBannerView` is NOT mounted on this path
    /// (R4 — the verdict pill renders inside `chainOfVouchesView`'s footer).
    ///
    /// Scroll-order locked (UI-SPEC §iPhone Scroll Order):
    /// 1. Pinned summary header (fixed at top, OUTSIDE the scroll view).
    /// 2. EveryoneOnLoadStripView — vertical gap to next: `DS.Spacing.md`.
    /// 3. ChainOfVouchesView card — vertical gap to next: `DS.Spacing.xl`.
    /// 4. LoadDetailBodyView (internal scroll DISABLED — its contentStack
    ///    drives the height so the outer scroll view owns scrolling).
    ///    The body's contentStack contains: timeline → freight → parties →
    ///    verdict block (Plan 04's pre-existing section order).
    private func buildIPhoneLayoutVerticalTree() {
        // Right pane / Phase 9 trust graph / standalone banner all unused
        // on this path. Reparent / hide as needed so a flip from iPad or
        // from the DEBUG legacy path leaves no orphans.
        rightPaneContainer.isHidden = true
        trustGraphView.isHidden = true
        chainIntegrityBanner?.isHidden = true
        // Detach the standalone banner from bodyContainer on iPhone (R4 —
        // not part of the iPhone scroll order on this path; iPad mount
        // remains intact in buildIPadSplitLayout).
        chainIntegrityBanner?.removeFromSuperview()

        // Re-parent bodyView back to bodyContainer if a prior iPad split
        // moved it into rightPaneContainer (mirrors the legacy CR-02 fix).
        // The vertical-tree path will then move bodyView INTO the outer
        // scroll's content stack.
        if bodyView.superview !== bodyContainer {
            bodyView.removeFromSuperview()
            bodyContainer.addSubview(bodyView)
        }

        // Body owns NO pinned header on iPhone — the VC owns a top-level one.
        bodyView.hidesPinnedSummaryHeader = true
        // Plan 09.1: disable bodyView's internal scrolling — the OUTER
        // iPhoneVerticalTreeScrollView owns scrolling for the whole
        // composition (strip + card + body sections scroll as one).
        bodyView.isInternalScrollEnabled = false

        // Ensure the top-level pinned header exists.
        let pinned = ensurePinnedHeaderTopLevelView()
        pinned.isHidden = false

        // Mount the outer scroll view + content stack into bodyContainer
        // (once — subsequent rebuilds reuse the same instance).
        if iPhoneVerticalTreeScrollView.superview !== bodyContainer {
            iPhoneVerticalTreeScrollView.removeFromSuperview()
            bodyContainer.addSubview(iPhoneVerticalTreeScrollView)
        }
        if iPhoneVerticalTreeContentStack.superview !== iPhoneVerticalTreeScrollView {
            iPhoneVerticalTreeContentStack.removeFromSuperview()
            iPhoneVerticalTreeScrollView.addSubview(iPhoneVerticalTreeContentStack)
        }

        // Pre-attach the strip, card, and bodyView into the content stack
        // in canonical iPhone scroll order (R8). Each is removed from any
        // prior superview first so a size-class flip cleanly re-parents.
        everyoneOnLoadStripView.translatesAutoresizingMaskIntoConstraints = false
        chainOfVouchesView.translatesAutoresizingMaskIntoConstraints = false

        // Remove from any prior arrangedSubview / superview before re-inserting.
        for v in iPhoneVerticalTreeContentStack.arrangedSubviews {
            iPhoneVerticalTreeContentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        if everyoneOnLoadStripView.superview != nil {
            everyoneOnLoadStripView.removeFromSuperview()
        }
        if chainOfVouchesView.superview != nil {
            chainOfVouchesView.removeFromSuperview()
        }
        if bodyView.superview != nil {
            bodyView.removeFromSuperview()
        }

        iPhoneVerticalTreeContentStack.addArrangedSubview(everyoneOnLoadStripView)
        iPhoneVerticalTreeContentStack.addArrangedSubview(chainOfVouchesView)
        iPhoneVerticalTreeContentStack.addArrangedSubview(bodyView)

        // Per-pair spacing per UI-SPEC §iPhone Scroll Order:
        //   strip → card  : DS.Spacing.md (16pt)
        //   card  → body  : DS.Spacing.xl (32pt — wider separation so the
        //                    chain block reads as the dominant feature)
        iPhoneVerticalTreeContentStack.setCustomSpacing(DS.Spacing.md, after: everyoneOnLoadStripView)
        iPhoneVerticalTreeContentStack.setCustomSpacing(DS.Spacing.xl, after: chainOfVouchesView)

        // Activate the composition geometry.
        var cs: [NSLayoutConstraint] = [
            // Pinned header — top of bodyContainer; horizontal pin.
            pinned.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            pinned.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            pinned.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),

            // Outer scroll view — fills the area below the pinned header.
            // Vertical gap from pinned header to strip: DS.Spacing.md.
            iPhoneVerticalTreeScrollView.topAnchor.constraint(
                equalTo: pinned.bottomAnchor, constant: DS.Spacing.md),
            iPhoneVerticalTreeScrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            iPhoneVerticalTreeScrollView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            iPhoneVerticalTreeScrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            // Content stack horizontal: pin to frameLayoutGuide so the
            // stack content cannot scroll horizontally.
            iPhoneVerticalTreeContentStack.leadingAnchor.constraint(
                equalTo: iPhoneVerticalTreeScrollView.frameLayoutGuide.leadingAnchor),
            iPhoneVerticalTreeContentStack.trailingAnchor.constraint(
                equalTo: iPhoneVerticalTreeScrollView.frameLayoutGuide.trailingAnchor),

            // Content stack vertical: pin to contentLayoutGuide so vertical
            // scroll content size grows with the stack.
            iPhoneVerticalTreeContentStack.topAnchor.constraint(
                equalTo: iPhoneVerticalTreeScrollView.contentLayoutGuide.topAnchor),
            iPhoneVerticalTreeContentStack.bottomAnchor.constraint(
                equalTo: iPhoneVerticalTreeScrollView.contentLayoutGuide.bottomAnchor),
        ]

        NSLayoutConstraint.activate(cs)
        compositionConstraints = cs
    }

    /// Plan 09.1 D-12 / D-13 — DEBUG-only legacy iPhone composition that
    /// preserves the Phase 9 `[pinnedHeader ↓ banner ↓ trustGraphView ↓
    /// bodyView]` posture verbatim. Reachable only when the
    /// `-Mock2DTrustGraphOnIPhone` launch flag is present AND the build
    /// configuration is DEBUG. Release builds never compile this method.
    #if DEBUG
    private func buildIPhoneLayoutLegacyTrustGraph() {
        // Tear down any new-iPhone vertical-tree mounts (so a flip from the
        // default path to the legacy DEBUG path during a single launch
        // session — unusual, but possible — does not leave orphans).
        iPhoneVerticalTreeScrollView.removeFromSuperview()
        for v in iPhoneVerticalTreeContentStack.arrangedSubviews {
            iPhoneVerticalTreeContentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        if everyoneOnLoadStripView.superview != nil {
            everyoneOnLoadStripView.removeFromSuperview()
        }
        if chainOfVouchesView.superview != nil {
            chainOfVouchesView.removeFromSuperview()
        }
        // Restore body's internal scrolling for the legacy path.
        bodyView.isInternalScrollEnabled = true

        // Right pane is not used on iPhone.
        rightPaneContainer.isHidden = true
        trustGraphView.isHidden = false

        // CR-02 fix (Phase 9 review): re-parent bodyView to bodyContainer
        // in case we're coming back from an iPad split layout — that path
        // moved bodyView into `rightPaneContainer`. Mirrors the symmetric
        // re-parent buildIPadSplitLayout performs on iPhone→iPad.
        if bodyView.superview !== bodyContainer {
            bodyView.removeFromSuperview()
            bodyContainer.addSubview(bodyView)
        }

        // Body owns NO pinned header on iPhone — the VC owns a top-level one.
        bodyView.hidesPinnedSummaryHeader = true

        // Ensure the top-level pinned header exists.
        let pinned = ensurePinnedHeaderTopLevelView()
        pinned.isHidden = false

        // Banner: positioned below the pinned header. Banner instance comes
        // from `applyLoadedRender(...)` — may be nil during the initial
        // loading state; the layout tolerates that by pinning the graph
        // either to the banner or directly below the pinned header.
        let banner = chainIntegrityBanner
        if let banner, banner.superview == nil {
            bodyContainer.addSubview(banner)
        }

        // Activate constraints — bodyContainer pins to safeArea via the
        // outer layoutBaseContainers pass; the inner geometry is laid out
        // against bodyContainer's edges.
        var cs: [NSLayoutConstraint] = [
            // Pinned header — top of bodyContainer; horizontal pin.
            pinned.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            pinned.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            pinned.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
        ]

        // Banner (if present + non-clean): pinned below the header.
        let graphTopAnchor: NSLayoutYAxisAnchor
        if let banner, !banner.isHidden {
            cs.append(contentsOf: [
                banner.topAnchor.constraint(equalTo: pinned.bottomAnchor),
                banner.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            ])
            graphTopAnchor = banner.bottomAnchor
        } else {
            graphTopAnchor = pinned.bottomAnchor
        }

        // Trust graph — pinned below banner (or header); height locks to
        // ~62% of bodyContainer's height (UI-SPEC line 119 / D-01 dominance).
        cs.append(contentsOf: [
            trustGraphView.topAnchor.constraint(equalTo: graphTopAnchor),
            trustGraphView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            trustGraphView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            trustGraphView.heightAnchor.constraint(
                equalTo: bodyContainer.heightAnchor, multiplier: 0.62),

            // Body — fills the remaining vertical space below the graph.
            bodyView.topAnchor.constraint(equalTo: trustGraphView.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])

        NSLayoutConstraint.activate(cs)
        compositionConstraints = cs
    }
    #endif

    /// iPad split composition (D-03 — UNCHANGED by Plan 09.1 per R10):
    /// [banner-if-non-clean (full-width top) ↓ horizontalSplit:
    ///  [trustGraphView (left 60%) | rightPaneContainer (right 40%):
    ///    [bodyView with embedded pinned header shown]]].
    ///
    /// Plan 09.1: also tears down any iPhone vertical-tree mounts so a flip
    /// from .compact → .regular cleanly removes the strip / card / outer
    /// scroll view (they are iPhone-only and would otherwise float as
    /// orphans inside `bodyContainer`).
    private func buildIPadSplitLayout() {
        // Plan 09.1: clear iPhone vertical-tree mounts when entering iPad.
        // The strip and card never mount on iPad (R10 — iPad keeps Phase 9
        // TrustGraphView verbatim).
        for v in iPhoneVerticalTreeContentStack.arrangedSubviews {
            iPhoneVerticalTreeContentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        iPhoneVerticalTreeScrollView.removeFromSuperview()
        if everyoneOnLoadStripView.superview != nil {
            everyoneOnLoadStripView.removeFromSuperview()
        }
        if chainOfVouchesView.superview != nil {
            chainOfVouchesView.removeFromSuperview()
        }
        // Restore the body's internal scrolling for the iPad path (in case
        // we're flipping back from the iPhone vertical-tree layout where it
        // was disabled).
        bodyView.isInternalScrollEnabled = true
        trustGraphView.isHidden = false

        // Body owns its pinned header on iPad — header lives at the top of
        // the right pane.
        bodyView.hidesPinnedSummaryHeader = false

        // Hide the top-level pinned header on iPad (the body owns the
        // visible header).
        pinnedHeaderTopLevelView?.isHidden = true

        rightPaneContainer.isHidden = false

        // Move bodyView INTO rightPaneContainer so the pinned-header it
        // owns appears at the top of the right pane.
        if bodyView.superview !== rightPaneContainer {
            bodyView.removeFromSuperview()
            rightPaneContainer.addSubview(bodyView)
        }

        // Banner (if present + non-clean): pinned to the top of bodyContainer.
        let banner = chainIntegrityBanner
        if let banner, banner.superview == nil {
            bodyContainer.addSubview(banner)
        }

        // Layout: banner pinned at top; trust-graph + right-pane occupy the
        // remaining height in a horizontal split.
        var cs: [NSLayoutConstraint] = []
        let splitTopAnchor: NSLayoutYAxisAnchor
        if let banner, !banner.isHidden {
            cs.append(contentsOf: [
                banner.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
                banner.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            ])
            splitTopAnchor = banner.bottomAnchor
        } else {
            splitTopAnchor = bodyContainer.topAnchor
        }

        cs.append(contentsOf: [
            // Trust graph — left pane, 60% width.
            trustGraphView.topAnchor.constraint(equalTo: splitTopAnchor),
            trustGraphView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            trustGraphView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            trustGraphView.widthAnchor.constraint(equalTo: bodyContainer.widthAnchor, multiplier: 0.60),

            // Right pane — 40% width, pinned to the right edge.
            rightPaneContainer.topAnchor.constraint(equalTo: splitTopAnchor),
            rightPaneContainer.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            rightPaneContainer.leadingAnchor.constraint(equalTo: trustGraphView.trailingAnchor),
            rightPaneContainer.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            rightPaneContainer.widthAnchor.constraint(equalTo: bodyContainer.widthAnchor, multiplier: 0.40),

            // BodyView — fills the right pane.
            bodyView.topAnchor.constraint(equalTo: rightPaneContainer.topAnchor),
            bodyView.bottomAnchor.constraint(equalTo: rightPaneContainer.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: rightPaneContainer.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: rightPaneContainer.trailingAnchor),
        ])

        NSLayoutConstraint.activate(cs)
        compositionConstraints = cs
    }

    /// Build (or return the existing) top-level pinned-header instance.
    /// The header is a duplicate of `bodyView.pinnedSummaryHeader` — by
    /// design (I-05 locked path). On iPhone the body's header is hidden;
    /// this one is the visible one. Re-populated from `cachedLoad` whenever
    /// `applyLoadedRender(...)` runs.
    private func ensurePinnedHeaderTopLevelView() -> UIView {
        if let existing = pinnedHeaderTopLevelView {
            return existing
        }
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = DS.Colors.surface
        container.accessibilityIdentifier = "load-detail.pinned-header"

        let reference = UILabel()
        reference.font = DS.Typography.headline
        reference.textColor = DS.Colors.label
        reference.adjustsFontForContentSizeCategory = true
        reference.translatesAutoresizingMaskIntoConstraints = false
        reference.setContentHuggingPriority(.required, for: .horizontal)
        reference.setContentCompressionResistancePriority(.required, for: .horizontal)
        reference.accessibilityIdentifier = "load-detail.pinned-header.reference-number"

        let originDest = UILabel()
        originDest.font = DS.Typography.body
        originDest.textColor = DS.Colors.label
        originDest.adjustsFontForContentSizeCategory = true
        originDest.translatesAutoresizingMaskIntoConstraints = false
        originDest.lineBreakMode = .byTruncatingTail
        originDest.numberOfLines = 1

        let badge = LoadStatusBadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.accessibilityIdentifier = "load-detail.pinned-header.status-badge"
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [reference, originDest, badge])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DS.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Spacing.md),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DS.Spacing.md),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: DS.Spacing.sm),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DS.Spacing.sm),
        ])

        bodyContainer.addSubview(container)
        pinnedHeaderTopLevelView = container
        pinnedHeaderReferenceLabel = reference
        pinnedHeaderOriginDestLabel = originDest
        pinnedHeaderStatusBadge = badge
        return container
    }

    /// Populate the top-level pinned header's labels from a Load (iPhone-
    /// only — iPad uses the body's embedded header instead).
    private func populatePinnedHeaderTopLevelView(load: Load) {
        pinnedHeaderReferenceLabel?.text = load.referenceNumber
        pinnedHeaderOriginDestLabel?.text =
            "\(load.origin.city), \(load.origin.state) → \(load.destination.city), \(load.destination.state)"
        pinnedHeaderStatusBadge?.configure(status: load.status)
    }

    // MARK: - Wire actions / bind VM

    private func wireActions() {
        errorRetryButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { [viewModel = self.viewModel] in
                await viewModel.fetchLoadDetail()
            }
        }, for: .touchUpInside)

        // Plan 06 — graph callbacks. Set ONCE for the VC's lifetime.
        trustGraphView.nodeTapped = { [weak self] partyID in
            self?.presentVerificationBasisSheet(for: partyID)
        }
        trustGraphView.edgeTapped = { [weak self] edgeID in
            self?.presentHandoffDetailSheet(for: edgeID)
        }

        // Plan 09.1 D-08 / D-09 / D-10 — chip-tap → tree-scroll wiring.
        // Set ONCE for the VC's lifetime. The handler is a no-op on iPad
        // (chainOfVouchesView is not in the iPad composition; rowViews(for:)
        // returns an empty array).
        everyoneOnLoadStripView.onRoleTap = { [weak self] role in
            self?.handleStripChipTap(role: role)
        }
    }

    // MARK: - Plan 09.1 D-08 / D-09 / D-10 / W1 — chip-tap → tree-scroll

    /// Handle a tap on a strip chip (D-08). Scrolls
    /// `iPhoneVerticalTreeScrollView` so the UNION of ALL rows matching
    /// the tapped role is on-screen (W1 — D-10 "the role is suspect, not
    /// just one party"). The multi-broker VL-1009 case surfaces BOTH
    /// broker rows after the scroll, not just the first.
    ///
    /// Window guard (Pitfall 2 / RESEARCH §Pitfall 2 lines 535-543):
    /// `convert(_:to:)` returns garbage when either view is not yet in a
    /// window; defer the scroll to the next runloop in that case.
    ///
    /// Haptic (D-08): `UISelectionFeedbackGenerator.selectionChanged()` —
    /// the soft "selection-changed" click matches the segmented-control
    /// precedent for selecting one item from a small set.
    internal func handleStripChipTap(role: Role) {
        // Mark the chip + matching rows as selected even before the scroll
        // resolves — the user gets immediate visual feedback.
        chainOfVouchesView.applySelectedRole(role)
        everyoneOnLoadStripView.applySelectedRole(role)

        let rows = chainOfVouchesView.rowViews(for: role)
        guard !rows.isEmpty else {
            // No matching rows (shouldn't happen — the chip wouldn't exist
            // unless its role has at least one node in the chain). Defensive
            // no-op: we've already applied the selection visual above.
            return
        }

        // Pitfall 2 — both the rows AND the outer scroll view MUST be in a
        // window before convert(_:to:) returns valid coordinates. If we're
        // off-window (e.g. tapped during a view-controller transition), defer
        // to the next runloop.
        let allRowsInWindow = rows.allSatisfy { $0.window != nil }
        guard iPhoneVerticalTreeScrollView.window != nil, allRowsInWindow else {
            DispatchQueue.main.async { [weak self] in
                self?.handleStripChipTap(role: role)
            }
            return
        }

        // W1 — fold ALL matching row frames into a single UNION rect so the
        // scroll surfaces every implicated row, not just the first. For
        // single-node roles the union equals one row's frame; for multi-node
        // roles (VL-1009 BRK) it spans both broker rows so both are
        // on-screen after the scroll.
        let unionRect = rows.reduce(CGRect.null) { acc, row in
            acc.union(row.convert(row.bounds, to: iPhoneVerticalTreeScrollView))
        }
        guard !unionRect.isNull else { return }

        // Apply a top inset of DS.Spacing.md so the union does not butt
        // against the strip above. insetBy(dx:, dy:) expands when the
        // argument is negative; we use a negative dy to grow the rect by
        // DS.Spacing.md on both vertical edges (top + bottom) so
        // scrollRectToVisible places the union with breathing room.
        let target = unionRect.insetBy(dx: 0, dy: -DS.Spacing.md)

        // Stash for Plan 05 Task 2 (CompositionTests W1 assertion).
        #if DEBUG
        lastUnionRectForTesting = target
        #endif

        iPhoneVerticalTreeScrollView.scrollRectToVisible(target, animated: true)

        // Haptic feedback (D-08).
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            MainActor.assumeIsolated {
                self?.render(state: state)
            }
        }
        // WR-06 — pump the VM's CURRENT state through the renderer once
        // (Swift `didSet` does NOT fire for the initial assignment).
        render(state: viewModel.state)
    }

    // MARK: - State → UI dispatcher (D-20 — isHidden toggles + body configure on .loaded)

    private func render(state: LoadDetailViewModel.State) {
        switch state {
        case .loading:
            skeletonContainer.isHidden = false
            bodyContainer.isHidden = true
            errorContainer.isHidden = true

        case .loaded(let load, let chainOfTrust):
            applyLoadedRender(load: load, chainOfTrust: chainOfTrust)

        case .error:
            // T-09-04 — the .error associated `message` is NEVER read here.
            skeletonContainer.isHidden = true
            bodyContainer.isHidden = true
            errorContainer.isHidden = false
        }
    }

    /// Apply a `.loaded(load, chainOfTrust)` render: cache the payload,
    /// build/refresh the banner from the verdict, install the verdict block
    /// in the body, configure the body + graph, then update accessibility
    /// ordering for the current composition.
    ///
    /// Per T-09-03: every visual surface (banner color, verdict-block tint,
    /// graph halo, accessibilityLabel) is driven by the server-supplied
    /// `chainIntegrity.verdict` + `reason` + implicated sets. No client
    /// derivation; Phase 7 D-18 LOCK.
    private func applyLoadedRender(load: Load, chainOfTrust: ChainOfTrust) {
        // Cache the payload so composition rebuilds (e.g. rotation) can
        // re-render without re-fetching.
        cachedLoad = load
        cachedChainOfTrust = chainOfTrust

        // Build/replace the chain-integrity banner — verdict + reason are
        // stored at init time so a new verdict needs a new instance.
        //
        // Plan 09.1 R4: the standalone banner is now ONLY mounted on iPad
        // (or on the DEBUG iPhone-legacy path). On the default iPhone
        // vertical-tree path, the verdict pill renders INSIDE
        // `chainOfVouchesView`'s footer; the standalone banner is not used
        // and we skip the instance build entirely on that path.
        let needsStandaloneBanner: Bool
        if compositionLayout == .iPadRegularSplit {
            needsStandaloneBanner = true
        } else {
            #if DEBUG
            needsStandaloneBanner = Debug2DGraphOverride.isActive
            #else
            needsStandaloneBanner = false
            #endif
        }

        chainIntegrityBanner?.removeFromSuperview()
        chainIntegrityBanner = nil
        if needsStandaloneBanner {
            let banner = ChainIntegrityBannerView(
                verdict: chainOfTrust.integrity.verdict,
                reason: chainOfTrust.integrity.reason
            )
            banner.translatesAutoresizingMaskIntoConstraints = false
            chainIntegrityBanner = banner
        }

        // Rebuild the composition so the banner participates in its
        // position-and-size constraints. (The banner is part of the
        // composition layout — buildIPhoneLayoutLegacyTrustGraph /
        // buildIPadSplitLayout pin it conditionally on `!banner.isHidden`.)
        NSLayoutConstraint.deactivate(compositionConstraints)
        compositionConstraints.removeAll()
        buildLayoutForCurrentComposition()

        // Populate body — pinned-header flag derives from composition.
        bodyView.configure(
            load: load,
            hidesPinnedHeader: (compositionLayout == .iPhoneCompact)
        )
        if compositionLayout == .iPhoneCompact {
            populatePinnedHeaderTopLevelView(load: load)
        }

        // D-02 — install the in-body verdict block. The body's
        // installVerdictBlock(...) handles the .clean branch defensively
        // (no block instantiated, slot collapses).
        //
        // Plan 09.1 R4: the in-body verdict block is part of Phase 9 body
        // composition; on the iPhone vertical-tree path the chain-of-vouches
        // footer pill is the primary fraud signal but leaving the body's
        // verdict block in place preserves the bill-of-lading section order
        // for users who scroll past the chain card. The body's block self-
        // hides for `.clean` — no visual collision.
        bodyView.installVerdictBlock(
            verdict: chainOfTrust.integrity.verdict,
            reason: chainOfTrust.integrity.reason,
            implicatedNodeCount: chainOfTrust.integrity.implicatedNodeIDs.count
        )

        // Plan 09.1 R5 — configure the new iPhone vertical-tree components
        // on the iPhone default path; the iPad path + DEBUG legacy path
        // continue to configure the Phase 9 trust graph.
        let useIPhoneVerticalTree: Bool = {
            guard compositionLayout == .iPhoneCompact else { return false }
            #if DEBUG
            return !Debug2DGraphOverride.isActive
            #else
            return true
            #endif
        }()

        if useIPhoneVerticalTree {
            // Plan 09.1 R3 — drive both new components from the WHOLE
            // server-supplied ChainOfTrust (R11 — data model FROZEN; no
            // derive*/compute* call).
            everyoneOnLoadStripView.configure(chainOfTrust: chainOfTrust)
            chainOfVouchesView.configure(chainOfTrust: chainOfTrust)
        } else {
            // Plan 06 — drive the marquee graph from the WHOLE server-
            // supplied ChainOfTrust. Every visual treatment (halo, edge
            // dash, dim-others, accessibilityLabel) flows from this payload
            // verbatim per Phase 7 D-18 LOCK.
            trustGraphView.configure(chainOfTrust: chainOfTrust)
        }

        skeletonContainer.isHidden = true
        errorContainer.isHidden = true
        bodyContainer.isHidden = false

        // D-21 — publish the VoiceOver traversal order for the current
        // composition.
        updateAccessibilityElements()
    }

    /// Publish `view.accessibilityElements` per D-21 + UI-SPEC line 827-830.
    /// iPhone: [pinnedHeader, banner-if-non-clean, trustGraphView, bodyView].
    /// iPad:   [banner-if-non-clean, bodyView (right pane first — freight
    ///          metadata before the graph), trustGraphView].
    /// VoiceOver walks the array in publish order; nested accessibility
    /// containers (the bodyView's timeline/freight rows; the trustGraphView's
    /// nodes + edges) are then traversed by the system default.
    private func updateAccessibilityElements() {
        var elements: [Any] = []
        let banner = chainIntegrityBanner

        switch compositionLayout {
        case .iPhoneCompact:
            // Plan 09.1 R6 — iPhone leaf-element model. On the default
            // vertical-tree path: pinned header → strip → card → body.
            // On the DEBUG legacy path: keep the Phase 9 ordering.
            #if DEBUG
            let isLegacyDebugPath = Debug2DGraphOverride.isActive
            #else
            let isLegacyDebugPath = false
            #endif

            if let pinned = pinnedHeaderTopLevelView, !pinned.isHidden {
                elements.append(pinned)
            }
            if isLegacyDebugPath {
                // Phase 9 iPhone composition (legacy DEBUG path).
                if let banner, !banner.isHidden {
                    elements.append(banner)
                }
                elements.append(trustGraphView)
                elements.append(bodyView)
            } else {
                // Plan 09.1 default iPhone vertical-tree composition.
                elements.append(everyoneOnLoadStripView)
                elements.append(chainOfVouchesView)
                elements.append(bodyView)
            }
        case .iPadRegularSplit:
            if let banner, !banner.isHidden {
                elements.append(banner)
            }
            // Right pane traversed first — freight metadata before the graph.
            elements.append(bodyView)
            elements.append(trustGraphView)
        }

        view.accessibilityElements = elements
    }

    // MARK: - TRUST-03 / TRUST-04 sheet presentation (Plans 07/08)

    /// Plan 07 — TRUST-03 / D-08. Present the verification-basis sheet
    /// for the tapped node. The graph callback fires with a partyID; we
    /// look the matching `TrustNode` up inside the cached chain-of-trust
    /// (set in `render(state:)`) and build the sheet content VC.
    ///
    /// Sheet presentation per RESEARCH §5 canonical iOS-17 recipe:
    ///   * detents [.medium, .large]
    ///   * selectedDetentIdentifier = .medium (initial rest state)
    ///   * prefersGrabberVisible = true
    ///   * largestUndimmedDetentIdentifier = .medium  (D-08 CRITICAL —
    ///     keeps the graph behind interactive + undimmed at .medium so
    ///     the user retains chain context while reading)
    ///   * prefersScrollingExpandsWhenScrolledToEdge = false  (D-10 —
    ///     long prior-relationships list does not auto-promote to .large
    ///     mid-scroll)
    ///   * prefersEdgeAttachedInCompactHeight = true
    ///   * widthFollowsPreferredContentSizeWhenEdgeAttached = true
    ///
    /// T-09-03 — the lookup `chainOfTrust.nodes.first(where:)` is a pure
    /// equality test on server-supplied IDs; no client trust derivation.
    /// If no chain is cached yet (race between configure + tap) or the
    /// partyID does not match any node, the call is a defensive no-op —
    /// surfacing nothing is better than presenting an empty sheet.
    private func presentVerificationBasisSheet(for partyID: String) {
        guard let chainOfTrust = cachedChainOfTrust,
              let node = chainOfTrust.nodes.first(where: { $0.partyID == partyID }) else {
            return  // defensive — node disappeared between configure and tap
        }
        let sheetVC = VerificationBasisSheetViewController(
            node: node, integrity: chainOfTrust.integrity)
        sheetVC.modalPresentationStyle = .pageSheet
        if let sheet = sheetVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium  // D-08 + RESEARCH §5 line 519 CRITICAL — keeps the graph interactive + undimmed at .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false  // D-10 — long list does not auto-promote
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        }
        present(sheetVC, animated: true)
    }

    /// Plan 08 — TRUST-04 / D-08. Present the handoff-detail sheet for the
    /// tapped edge. The graph callback fires with an edgeID; we look the
    /// matching `TrustEdge` up inside the cached chain-of-trust (set in
    /// `render(state:)`) and build the sheet content VC.
    ///
    /// Sheet presentation per RESEARCH §5 canonical iOS-17 recipe — SAME
    /// recipe as `presentVerificationBasisSheet(for:)` above (D-08 / UI-SPEC
    /// line 472 "Sheet presentation invariant"). The recipe is inlined at
    /// both call sites so the per-call Pitfall 7 grep gate (expected count
    /// 2 across this file) catches any future drift that breaks the lock
    /// on either site.
    ///
    /// Configuration:
    ///   * detents [.medium, .large]
    ///   * selectedDetentIdentifier = .medium (UI-SPEC line 470 — the
    ///     handoff sheet is naturally less dense; `.medium` is the
    ///     natural resting detent)
    ///   * prefersGrabberVisible = true
    ///   * Pitfall 7 undimmed-detent lock at `.medium` (D-08 CRITICAL —
    ///     keeps the graph behind interactive + undimmed at the resting
    ///     detent so the user retains chain context while reading)
    ///   * prefersScrollingExpandsWhenScrolledToEdge = false  (consistent
    ///     with Plan 07; though the handoff sheet has no long list,
    ///     keeping the same recipe ensures both sheet sites behave
    ///     identically)
    ///   * prefersEdgeAttachedInCompactHeight = true
    ///   * widthFollowsPreferredContentSizeWhenEdgeAttached = true
    ///
    /// T-09-03 — the three lookups (`edges.first(where:)` +
    /// `nodes.first(where:)` × 2) are pure equality tests on server-
    /// supplied IDs; no client trust derivation.
    private func presentHandoffDetailSheet(for edgeID: String) {
        guard let chainOfTrust = cachedChainOfTrust,
              let edge = chainOfTrust.edges.first(where: { $0.edgeID == edgeID }),
              let fromNode = chainOfTrust.nodes.first(where: { $0.partyID == edge.fromPartyID }),
              let toNode = chainOfTrust.nodes.first(where: { $0.partyID == edge.toPartyID }) else {
            return  // defensive — edge or endpoints disappeared between configure and tap
        }
        let sheetVC = HandoffDetailSheetViewController(edge: edge, fromNode: fromNode, toNode: toNode, integrity: chainOfTrust.integrity)
        sheetVC.modalPresentationStyle = .pageSheet
        if let sheet = sheetVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium  // D-08 + RESEARCH §5 line 519 CRITICAL — keeps the graph interactive + undimmed at the resting detent
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false  // consistent with Plan 07 recipe
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        }
        present(sheetVC, animated: true)
    }
}
