// validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
// Phase 9 LOAD-05 / D-01 / D-20 — the programmatic-UIKit detail VC shell.
//
// File-shape analog: LoadListViewController.swift (PATTERNS E1 — verbatim
// posture for the state-machine VC):
//   - programmatic UIKit (no SwiftUI — CLAUDE.md sensitive-surface mandate)
//   - `init(viewModel:)` + initializer-DI (ARCH-04)
//   - `viewDidLoad → layoutContent / wireActions / bindViewModel`
//   - `viewWillAppear → Task { await viewModel.fetchLoadDetail() }`
//   - `bindViewModel` uses MainActor.assumeIsolated + WR-06 priming pump
//   - render(state:) toggles `isHidden` on pre-attached state subviews,
//     NEVER swaps view controllers
//
// === D-20 state subviews are pre-attached, hidden by default ===
// Three sibling container views are added in `layoutContent()`:
//   - `skeletonContainer` — Plan 04 populates with `LoadDetailSkeletonView`.
//   - `errorContainer`    — Plan 04 populates with the
//                           `UIContentUnavailableView` posture (D-20).
//   - `bodyContainer`     — Plans 04 (header), 05 (timeline), 06 (graph),
//                           09 (banner + iPad split) compose into this.
// `render(state:)` toggles `isHidden` per case. The containers stay attached
// to the view hierarchy across state transitions so Plans 04-09 can install
// their subviews ONCE (in their own viewDidLoad-equivalent hook) instead of
// rebuilding on every state change.
//
// === Zero logging (T-08-08 / T-09-04 — VIEW-LAYER LOCK) ===
// This file has ZERO `Logger` / `os_log` / `OSLog` calls. The VM does any
// logging the screen produces. Per the Phase 8 LoadListViewController file-
// header lock (T-08-08), the view layer is logging-free — a value the
// negative grep gate in 09-03-PLAN acceptance criteria enforces. Plan 04
// MUST preserve this when it populates the containers.
//
// === Accessibility identifier namespace ===
// `view.accessibilityIdentifier = "load-detail"` (the LOCKED root per
// UI-SPEC § Accessibility identifiers). Per-container identifiers:
//   - `load-detail.skeleton`
//   - `load-detail.error-state`
//   - `load-detail.body`
// `LoadDetailFlowTests` (XCUITest) probes these from day one — once-locked,
// future plans MUST NOT rename without a corresponding XCUITest update.
//
// === iOS 17 deployment minimum ===
// No iOS 18-only APIs used. `safeAreaLayoutGuide`, `UIView.isHidden`,
// `UIStackView` are iOS 9+. `UIContentUnavailableView` (Plan 04) is iOS 17+
// — also fine.

import UIKit

public final class LoadDetailViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: LoadDetailViewModel

    // MARK: - State subviews (D-20 — pre-attached, isHidden-toggled)

    /// Skeleton-with-shimmer container. Plan 04 populates with a
    /// `LoadDetailSkeletonView` subview pinned to all edges.
    private let skeletonContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.skeleton"
        v.isHidden = true
        return v
    }()

    /// Error-state container. Plan 04 populates with a `UIContentUnavailableView`
    /// (iOS 17+) carrying the locked `loads.detail.error.generic` copy plus
    /// a "Try again" CTA wired to `viewModel.fetchLoadDetail()`.
    private let errorContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.error-state"
        v.isHidden = true
        return v
    }()

    /// Body container — Plans 04 (header), 05 (timeline), 06 (graph), 09
    /// (banner + iPad split) compose into this. Stays attached across state
    /// transitions; Plan 09 owns the iPad split-pane geometry inside this
    /// container.
    private let bodyContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.background
        v.accessibilityIdentifier = "load-detail.body"
        v.isHidden = true
        return v
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

        layoutContent()
        wireActions()
        bindViewModel()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Capture `viewModel` to avoid a [weak self] guard for the simple
        // single-call case — the VM is owned by `self`, so its lifetime is
        // bounded by the VC's. The Task itself is fire-and-forget; the VM's
        // BL-01 cancel-and-replace handles any stale fetch from a previous
        // appear if the user tabs away and back before the network settles.
        Task { [viewModel] in await viewModel.fetchLoadDetail() }
    }

    // MARK: - Layout

    private func layoutContent() {
        view.addSubview(bodyContainer)
        view.addSubview(skeletonContainer)
        view.addSubview(errorContainer)

        let guide = view.safeAreaLayoutGuide
        // All three containers pin edge-to-edge in the safe area. Plan 09
        // (iPad split) replaces this geometry inside `bodyContainer` via a
        // `traitCollectionDidChange(_:)`-driven internal layout; the outer
        // VC's layout doesn't branch on size class. The skeleton + error
        // containers stay single-column on both devices (Phase 8 precedent).
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

    private func wireActions() {
        // Empty for now — the "Try again" CTA (Plan 04) and the node/edge
        // tap → sheet presentation (Plans 07/08) land in their own plans
        // and add their own wiring inside the relevant container's subview
        // composition. This shell intentionally has no action wiring.
    }

    private func bindViewModel() {
        // The VM is @MainActor; `onStateChange` fires on the same actor as
        // the VC, so the captured closure dispatches directly to
        // render(state:). PATTERNS E1 verbatim posture.
        viewModel.onStateChange = { [weak self] state in
            // `MainActor.assumeIsolated` is the explicit hop assertion — the
            // didSet fires from within the @MainActor isolation, so this is
            // a no-op assertion in production AND silences any compiler
            // warning a future Swift-concurrency tightening might introduce.
            MainActor.assumeIsolated {
                self?.render(state: state)
            }
        }
        // WR-06 — pump the VM's CURRENT state through the renderer once.
        // Swift `didSet` does NOT fire for the property's initial assignment
        // (`var state: State = .loading` at VM init time), so without this
        // explicit pump the skeleton container would stay hidden between
        // `viewDidLoad` completing and the `viewWillAppear` fetch Task's
        // first MainActor hop re-assigning `state = .loading`. The pump
        // guarantees the first paint shows the skeleton, matching the
        // Phase 8 LoadListViewController precedent (PATTERNS E1 lines 90-96).
        render(state: viewModel.state)
    }

    // MARK: - State → UI dispatcher (D-20 — isHidden toggles ONLY)

    private func render(state: LoadDetailViewModel.State) {
        switch state {
        case .loading:
            skeletonContainer.isHidden = false
            bodyContainer.isHidden = true
            errorContainer.isHidden = true

        case .loaded:
            // Plan 04+ populate `bodyContainer`'s subview hierarchy; this
            // shell only toggles visibility. The associated Load +
            // ChainOfTrust are read by Plans 04/05/06/09 from the VM's
            // `state` property at their own composition hooks.
            skeletonContainer.isHidden = true
            errorContainer.isHidden = true
            bodyContainer.isHidden = false

        case .error:
            // The locked generic copy lives on the VM's State.error
            // associated value — Plan 04 populates `errorContainer` with a
            // `UIContentUnavailableView` reading that string. This shell
            // only toggles visibility.
            skeletonContainer.isHidden = true
            bodyContainer.isHidden = true
            errorContainer.isHidden = false
        }
    }
}
