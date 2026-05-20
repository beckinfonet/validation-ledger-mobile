// validationLedger/Features/Loads/LoadListViewController.swift
// Phase 8 Plan 03 — LOAD-03 / LOAD-04 / LOAD-07 / LOAD-08: the role-filtered
// loads-list screen.
//
// File-shape analog: KYCStatusViewController.swift (the canonical 4-state UIKit
// VC in this codebase). Same posture:
//   - programmatic UIKit (no SwiftUI — CLAUDE.md sensitive-surface mandate)
//   - `init(viewModel:)` + initializer-DI (ARCH-04)
//   - `viewDidLoad → layoutContent / wireActions / bindViewModel`
//   - `viewWillAppear → Task { await viewModel.fetchLoads() }`
//   - `@objc pulledToRefresh` driving the refresh control
//
// === Compositional layout (RESEARCH §Pattern 1 + §Pitfall 5) ===
// `UICollectionViewCompositionalLayout` with a section-provider closure that
// builds a `.list` section per environment. iPad SC-#5 readable-content is
// applied at the SECTION LEVEL (`section.contentInsetsReference =
// .readableContent`) — Pitfall 5 — so it reacts to size-class changes
// without manual constraint plumbing.
//
// === Diffable datasource (RESEARCH §Pattern 1 + 08-CONTEXT D-08) ===
// `UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>` with a
// single `enum LoadListSection { case main }` (D-08 — single section from day
// one, additive enum extension later). `LoadRowItem` is a `Hashable` wrapper
// keyed by `item.load.id` so diffs are stable across refreshes (Phase 9+
// item-content changes can drive `reconfigureItems` without a full reload).
//
// === Cell registration (RESEARCH §Pattern 1) ===
// `UICollectionView.CellRegistration<LoadRowCell, LoadListItem>` — the cell
// is registered once, then dequeued per indexPath. The registration closure
// is intentionally MINIMAL: it just calls `cell.configure(item:)` (Pitfall 6 —
// the cell sets its own accessibilityIdentifier from `item.load.id`; the
// registration closure does not). This keeps Phase 9+'s LoadDetail row-tap
// gesture wiring on the cell's content view, not on the registration closure.
//
// === Skeleton overlay (RESEARCH §Anti-Patterns lines 443) ===
// `.loading` SWAPS to a SKELETON OVERLAY — a separate UIStackView background
// view containing 6 SkeletonLoadRowCells, NOT a datasource swap. RESEARCH
// explicitly forbids "applying a skeleton item type to the datasource" — that
// pattern conflates content (data) with chrome (loading) and produces a
// visible row-replacement animation when the real data arrives.
//
// === Empty / error states ===
// `.empty` uses `UIContentUnavailableConfiguration.empty()` — no button, no
// accessibilityIdentifier walk ambiguity (the Task 1 A1 spike confirmed the
// configuration surface has no public hook for setting the empty-state host
// view's identifier without a post-render walk, so we set
// `accessibilityIdentifier` on the host view by walking ONLY for the empty
// case where the host is unambiguous — no button to confuse).
//
// `.error` uses a HAND-ROLLED `UIStackView` background view per the Task 1
// A1 spike VERDICT B: the `UIContentUnavailableConfiguration` surface has no
// public hook for setting `accessibilityIdentifier` on the retry button, and
// the only post-render mechanism (recursive subview walk) is fragile across
// iOS minor versions. The hand-rolled view carries the locked identifiers
// directly: `loads-list.error-state` on the host, `loads-list.error-state
// .retry` on the button. See `.spike-a1-notes.md` for the full rationale.
//
// === UIRefreshControl race-safe apply (RESEARCH §Pitfall 4) ===
// `endRefreshing()` runs INSIDE the `dataSource.apply(_:animatingDifferences:
// completion:)` completion handler for the `.loaded` state, NEVER at the top
// of `render(state:)`. Per Pitfall 4: ending refresh before the snapshot
// commits leaves the refresh affordance and the row-insert animation
// competing — the result is a visible "snap" where rows appear with the
// spinner still spinning. For `.empty / .error` the snapshot is empty, so
// `endRefreshing()` is synchronous there (no race window).
//
// === No client-side reordering or pruning (D-06 + D-18 + UI-SPEC line 448) ===
// `render(.loaded)` calls `snap.appendItems(items.map(LoadRowItem.init), …)`
// — exact wire order, no Swift sequence reorder/exclude operations anywhere
// in this file. The server is the trust boundary; iOS is a passive renderer.
//
// === Pagination-cursor discipline (UI-SPEC line 448) ===
// The VC NEVER reads the pagination cursor. The associated value flows
// through `LoadListViewModel.State.loaded(items, _)` but only the `items`
// arm is destructured here — the cursor is bound to `_`. A grep in this
// file for the cursor symbol-name must return zero (locked by Plan 03
// verification §6).
//
// === No logging (T-08-08) ===
// The view layer never calls into the logger. Every observable from the
// fetch path is captured in the VM's `logger.info / .error(event:fields:)`
// calls; the VC just routes state to UI.

import UIKit

// MARK: - File-private diffable identifiers
//
// `LoadListSection` and `LoadRowItem` are declared at file scope rather than
// nested inside `LoadListViewController` so they pick up the default
// `nonisolated` posture of value types. Under the project's
// `-default-isolation=MainActor` build setting, type declarations nested
// inside a UIViewController inherit MainActor isolation by default — which
// makes their `Hashable` conformance MainActor-isolated, which in turn
// cannot satisfy the `Sendable` requirement on
// `UICollectionViewDiffableDataSource`'s `SectionIdentifierType` /
// `ItemIdentifierType` type parameters. Hoisting them to file scope and
// keeping their visibility `fileprivate` preserves the encapsulation while
// silencing the cross-actor conformance error.

/// Single-case section (08-CONTEXT D-08). Future filters/groupings are
/// additive enum extensions — the datasource type signature already
/// supports multiple sections.
///
/// `nonisolated` because the project's `-default-isolation=MainActor` build
/// setting would otherwise infer MainActor isolation on this nominal type;
/// `UICollectionViewDiffableDataSource`'s `SectionIdentifierType` requires
/// `Sendable + Hashable` where the conformances themselves must be
/// nonisolated.
nonisolated fileprivate enum LoadListSection: Hashable, Sendable { case main }

/// Diffable item wrapper. Hash AND `==` are BOTH keyed on `item.load.id` so
/// two snapshots that share a load id are treated as the SAME item by the
/// diffable data source — verification-state / counterparty changes on the
/// same load id then trigger `reconfigureItems` (re-render in place), NOT
/// delete + insert (row-swap animation).
///
/// WR-03 — pre-WR-03, `==` delegated to `LoadListItem == LoadListItem`, which
/// also compares the counterparty's `partyID` and `verificationState` (see
/// `LoadListViewModel.swift` `extension LoadListItem: Equatable`). That made
/// a row with the same load id but a refreshed verification state UNEQUAL,
/// so the data source classified it as one delete + one insert — producing a
/// visible row-replace animation and breaking the file-header's
/// `reconfigureItems`-on-payload-change promise. The Hashable contract was
/// also subtly violated by the asymmetry (equal items hash equal — `==`
/// could disagree because it compared more fields than the hash, so two
/// items with the same id but different counterparties hashed equal but
/// compared unequal). Both halves are now consistent: identity is `load.id`,
/// payload changes drive `reconfigureItems` via the explicit set passed to
/// `apply(_:animatingDifferences:)`.
///
/// `nonisolated` mirrors `LoadListSection` above. `@unchecked Sendable` is
/// safe because `LoadListItem` is itself `Sendable` (Plan 01) and this
/// wrapper holds only a let-binding of that value — no mutable state.
nonisolated fileprivate struct LoadRowItem: Hashable, @unchecked Sendable {
    let item: LoadListItem
    func hash(into hasher: inout Hasher) {
        hasher.combine(item.load.id)
    }
    static func == (l: LoadRowItem, r: LoadRowItem) -> Bool {
        // WR-03 — identity-only comparison. Same id → same diffable item;
        // payload differences are detected separately in `render(.loaded)`
        // and surface as `reconfigureItems`.
        l.item.load.id == r.item.load.id
    }
}

final class LoadListViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: LoadListViewModel

    /// BL-02 — the in-screen nav-bar title for THIS screen. Threaded from the
    /// composition root (`AppContainer.makeLoadListScreen(role:)`) so the
    /// role→title mapping lives in ONE place. The Factoring role pre-Phase-8
    /// already locked "Invoices" at the tab-bar layer (T-08-12 / PATTERNS
    /// Q1); pre-BL-02 the tab bar was correct but the nav bar above the list
    /// said "Loads" because `viewDidLoad` unconditionally assigned the "Loads"
    /// localized string. Now the call site decides — Factoring passes
    /// "Invoices", every other role passes "Loads". The literal here is the
    /// FALLBACK (constructed without an explicit title) so tests that build
    /// the VC without the AppContainer factory still produce a sensible
    /// title.
    private let navTitle: String

    init(viewModel: LoadListViewModel, navTitle: String = "Loads") {
        self.viewModel = viewModel
        self.navTitle = navTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("LoadListViewController is constructed programmatically only")
    }

    // MARK: - Subviews

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = DS.Colors.background
        cv.accessibilityIdentifier = "loads-list"
        return cv
    }()

    private let refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.accessibilityIdentifier = "loads-list.refresh-control"
        return rc
    }()

    /// 6 SkeletonLoadRowCells stacked vertically; the overlay is a separate
    /// background view, NOT a datasource swap (RESEARCH §Anti-Pattern).
    private lazy var skeletonOverlay: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        stack.backgroundColor = DS.Colors.background
        stack.accessibilityIdentifier = "loads-list.loading-indicator"
        // VoiceOver: while loading, the overlay is the focus target, NOT the
        // empty collection view behind it.
        stack.accessibilityViewIsModal = true
        for _ in 0..<6 {
            let skel = SkeletonLoadRowCell()
            // Skeleton cells inside the overlay carry their own a11y label
            // ('Loading') so VoiceOver groups identically per row.
            skel.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(skel)
            // Each silhouette row is ~88pt tall to mirror the real row.
            skel.heightAnchor.constraint(equalToConstant: 88).isActive = true
        }
        return stack
    }()

    // MARK: - Error state (VERDICT B — hand-rolled per spike A1)

    /// Locked accessibility identifiers on direct subviews so the XCUITest
    /// surface (Plan 04) can probe them without a recursive walk.
    private let errorIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        iv.contentMode = .scaleAspectFit
        iv.tintColor = DS.Colors.destructive
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        return iv
    }()

    private let errorHeading: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.title2
        l.textColor = DS.Colors.label
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        return l
    }()

    private let errorBody: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        return l
    }()

    private let errorRetryButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "loads.list.error.retry",
            value: "Try again",
            comment: "Phase 8 LoadListViewController — error-state retry CTA (UI-SPEC §Copywriting)"
        )
        let b = UIButton(configuration: cfg)
        b.accessibilityIdentifier = "loads-list.error-state.retry"
        // 44pt min touch target (CLAUDE.md HIG compliance baseline).
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return b
    }()

    private lazy var errorStateView: UIStackView = {
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
        stack.backgroundColor = DS.Colors.background
        stack.isHidden = true
        stack.accessibilityIdentifier = "loads-list.error-state"
        return stack
    }()

    // MARK: - Compositional layout (Pitfall 5 — section-level readable-content)

    /// Build the `.list` compositional layout. iPad SC-#5: section-level
    /// `contentInsetsReference = .readableContent` reacts to size-class
    /// changes automatically — RESEARCH §Pitfall 5 documents this as the
    /// "reactive path" (as opposed to manually pinning the collection view
    /// to `view.readableContentGuide`, which doesn't react to multitasking
    /// width changes on iPad).
    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
            cfg.backgroundColor = DS.Colors.background
            let section = NSCollectionLayoutSection.list(using: cfg, layoutEnvironment: environment)
            section.contentInsetsReference = .readableContent
            return section
        }
    }

    // MARK: - Cell registration + diffable datasource

    private lazy var cellRegistration = UICollectionView.CellRegistration<LoadRowCell, LoadListItem> { cell, _, item in
        // Pitfall 6: accessibilityIdentifier is set inside cell.configure(item:),
        // NOT in this closure.
        cell.configure(item: item)
    }

    private lazy var dataSource = UICollectionViewDiffableDataSource<LoadListSection, LoadRowItem>(collectionView: collectionView) { [unowned self] cv, indexPath, rowItem in
        cv.dequeueConfiguredReusableCell(using: self.cellRegistration, for: indexPath, item: rowItem.item)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // BL-02 — the in-screen nav-bar title comes from `init(viewModel:
        // navTitle:)`. The composition root (`AppContainer.makeLoadListScreen
        // (role:)`) maps role → title (Factoring → "Invoices"; everything
        // else → "Loads"). Setting `title` here propagates into
        // `UINavigationController`'s navigation bar via the `navigationItem
        // .title` fallback — so the Factoring tab now shows "Invoices" BOTH
        // in the tab bar (T-08-12 lock) AND in the nav bar above the list
        // (was previously stuck on "Loads" pre-BL-02).
        title = navTitle
        view.backgroundColor = DS.Colors.background

        layoutContent()
        wireActions()
        bindViewModel()

        // Phase 8 Plan 04 (Rule 1 — bug surfaced by integration wiring):
        // force `cellRegistration` to initialize HERE in viewDidLoad rather
        // than lazily inside the dataSource cell provider. iOS 18 added a
        // runtime guard that asserts when a UICollectionViewCellRegistration
        // is FIRST instantiated inside `-collectionView:cellForItemAtIndexPath:`
        // or a `UICollectionViewDiffableDataSource` cell provider:
        //   "Attempted to dequeue a cell using a registration that was
        //    created inside -collectionView:cellForItemAtIndexPath: or inside
        //    a UICollectionViewDiffableDataSource cell provider. Creating a
        //    new registration each time a cell is requested will prevent
        //    reuse and cause created cells to remain inaccessible in memory
        //    for the lifetime of the collection view. Registrations should
        //    be created up front and reused."
        // Even though we cache the registration in a `lazy var` (single
        // instantiation), the LAZY INIT itself happens inside the cell
        // provider on first call, which trips the iOS 18 guard. Accessing
        // `cellRegistration` first here forces the lazy init out of the
        // cell-provider context — the dataSource then dequeues an
        // already-initialized registration.
        _ = cellRegistration
        // Force the lazy datasource into existence so the first render
        // doesn't pay the lazy-init cost mid-transition.
        _ = dataSource
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await viewModel.fetchLoads() }
    }

    // MARK: - Layout

    private func layoutContent() {
        view.addSubview(collectionView)
        view.addSubview(skeletonOverlay)
        view.addSubview(errorStateView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Collection view fills the safe area.
            collectionView.topAnchor.constraint(equalTo: guide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            // Skeleton overlay sits on top of the (empty) collection view
            // while loading.
            skeletonOverlay.topAnchor.constraint(equalTo: guide.topAnchor),
            skeletonOverlay.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            skeletonOverlay.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            skeletonOverlay.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor),

            // Hand-rolled error view, centered in the safe area.
            errorStateView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            errorStateView.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            errorStateView.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor),
            errorStateView.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor),
        ])
    }

    private func wireActions() {
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        errorRetryButton.addAction(
            UIAction { [weak self] _ in
                Task { await self?.viewModel.fetchLoads() }
            },
            for: .touchUpInside
        )
    }

    private func bindViewModel() {
        // The VM is @MainActor; `onStateChange` fires on the same actor as the
        // VC, so the captured closure dispatches directly to render(state:).
        viewModel.onStateChange = { [weak self] state in
            // `MainActor.assumeIsolated` is the explicit hop assertion — the
            // didSet fires from within the @MainActor isolation, so this is a
            // no-op assertion in production AND silences any compiler warning
            // a future Swift-concurrency tightening might introduce.
            MainActor.assumeIsolated {
                self?.render(state: state)
            }
        }
    }

    // MARK: - Actions

    @objc private func pulledToRefresh() {
        Task { await viewModel.fetchLoads() }
    }

    // MARK: - State → UI dispatcher

    private func render(state: LoadListViewModel.State) {
        switch state {
        case .loading:
            // Hide error chrome, show skeleton overlay.
            errorStateView.isHidden = true
            contentUnavailableConfiguration = nil

            // Apply EMPTY snapshot synchronously so the (real) collection view
            // is empty behind the overlay. Refresh control is NOT ended here
            // — the spinner stays visible while the request is in flight.
            var snap = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
            snap.appendSections([.main])
            dataSource.apply(snap, animatingDifferences: false)

            skeletonOverlay.isHidden = false
            // VoiceOver hand-off — announce the loading state once.
            UIAccessibility.post(notification: .layoutChanged, argument: skeletonOverlay)

        case .empty:
            skeletonOverlay.isHidden = true
            errorStateView.isHidden = true

            var snap = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
            snap.appendSections([.main])
            dataSource.apply(snap, animatingDifferences: false)

            // Empty state — UIContentUnavailableConfiguration is safe here
            // (no button, so no XCUITest target hidden behind UIKit internals).
            var cfg = UIContentUnavailableConfiguration.empty()
            cfg.image = UIImage(systemName: "shippingbox")
            cfg.text = NSLocalizedString(
                "loads.list.empty.title",
                value: "No loads yet",
                comment: "Phase 8 LoadListViewController — empty-state heading"
            )
            cfg.secondaryText = NSLocalizedString(
                "loads.list.empty.body",
                value: "New loads will appear here.",
                comment: "Phase 8 LoadListViewController — empty-state body"
            )
            contentUnavailableConfiguration = cfg

            // Run a single-pass walk to set the host view's
            // accessibilityIdentifier — only the empty path needs this; the
            // error path uses the hand-rolled view per the A1 spike verdict.
            DispatchQueue.main.async { [weak self] in
                self?.setEmptyStateAccessibilityIdentifier()
            }
            refreshControl.endRefreshing()

        case .loaded(let items, _):
            // Plan 01 D-05 — the pagination cursor is destructured to `_`;
            // the VC NEVER reads it (UI-SPEC line 448 anti-pattern lock).
            skeletonOverlay.isHidden = true
            errorStateView.isHidden = true
            contentUnavailableConfiguration = nil

            // WR-03 — build a content-change map BEFORE applying the new
            // snapshot. The diffable data source's `==` on `LoadRowItem` is
            // identity-only (load.id) so it treats refreshed rows as the
            // SAME item; we then explicitly mark those rows for
            // `reconfigureItems` (re-render in place). Pre-WR-03 the data
            // source treated payload-changed rows as delete+insert because
            // `==` compared the full counterparty payload — producing a
            // visible row-replace animation and contradicting the
            // `reconfigureItems`-on-payload-change promise documented in
            // `LoadListViewModel.swift:60-69`.
            let newRowItems = items.map(LoadRowItem.init)
            // Build an id → previous LoadListItem map from the existing
            // snapshot so we can detect content changes (verification state,
            // counterparty id) for the same load id.
            let priorByID: [String: LoadListItem] = Dictionary(
                uniqueKeysWithValues: dataSource.snapshot().itemIdentifiers
                    .map { ($0.item.load.id, $0.item) }
            )
            // `LoadListItem`'s in-VM-file Equatable extension compares
            // load.id + counterparty partyID + counterparty verificationState
            // — i.e. it is precisely the "did this row's payload change"
            // signal we want here. (See LoadListViewModel.swift §
            // "LoadListItem Equatable extension".)
            let changedRowItems = newRowItems.filter { rowItem in
                guard let prior = priorByID[rowItem.item.load.id] else {
                    return false  // newly-arrived row — insert, not reconfigure
                }
                return prior != rowItem.item
            }

            var snap = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
            snap.appendSections([.main])
            // D-06 — exact wire order; no client-side reordering or pruning.
            snap.appendItems(newRowItems, toSection: .main)
            if !changedRowItems.isEmpty {
                // `reconfigureItems` only applies to items that survive the
                // diff (`==` matches an existing id). For brand-new ids, the
                // data source inserts a fresh cell anyway. WR-03 — this is
                // the explicit re-render path the file-header documentation
                // promised; the row stays in place and the cell's
                // `configure(item:)` re-renders with the new envelope.
                snap.reconfigureItems(changedRowItems)
            }

            // Pitfall 4 — endRefreshing() lives INSIDE the apply completion
            // so the refresh affordance and the row-insert animation never
            // race.
            dataSource.apply(snap, animatingDifferences: true) { [weak self] in
                self?.refreshControl.endRefreshing()
            }

        case .error(let message):
            skeletonOverlay.isHidden = true
            contentUnavailableConfiguration = nil

            var snap = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
            snap.appendSections([.main])
            dataSource.apply(snap, animatingDifferences: false)

            // Hand-rolled error state (VERDICT B from A1 spike).
            errorHeading.text = NSLocalizedString(
                "loads.list.error.title",
                value: "We couldn't load loads",
                comment: "Phase 8 LoadListViewController — error-state heading"
            )
            errorBody.text = message
            errorStateView.isHidden = false

            refreshControl.endRefreshing()
        }
    }

    /// Best-effort accessibilityIdentifier set on the empty-state host view.
    /// Runs ONCE per .empty transition, post-render — UIContentUnavailableView
    /// is instantiated by UIKit and a walk is the only public surface.
    private func setEmptyStateAccessibilityIdentifier() {
        for subview in view.recursiveSubviews {
            // `String(describing: type(of: subview))` keys on the class name
            // ("UIContentUnavailableView") without importing private headers.
            if String(describing: type(of: subview)).contains("ContentUnavailable") {
                subview.accessibilityIdentifier = "loads-list.empty-state"
                return
            }
        }
    }
}

// MARK: - Recursive subview walk helper (single use; kept local to this file)

private extension UIView {
    var recursiveSubviews: [UIView] {
        subviews + subviews.flatMap { $0.recursiveSubviews }
    }
}
