// validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
// Phase 9 LOAD-05 / D-01 / D-20 — the programmatic-UIKit detail VC shell.
//
// === Plan 04 (D-19 + D-20) extension on the Plan 03 shell ===
// Plan 03 shipped the three pre-attached empty UIView containers
// (`skeletonContainer`, `errorContainer`, `bodyContainer`) and the
// state-driven `render(state:)` dispatcher. Plan 04 populates them:
//   * `skeletonContainer` ← `LoadDetailSkeletonView` (D-19, shipped in this plan).
//   * `errorContainer`    ← hand-rolled error UI per Phase 8 exception
//                            (D-20 — UIContentUnavailableView's accessibility-
//                            identifier limitation makes the locked
//                            "load-detail.error-state.retry" identifier
//                            unreachable; the LoadListViewController error-
//                            state precedent (lines 240-298) is mirrored).
//   * `bodyContainer`     ← `LoadDetailBodyView` (Plan 04 ships the scroll
//                            container + pinned summary header; Plans 05,
//                            06, 09 populate the timeline / parties /
//                            verdict-block placeholders inside it).
// `render(state:)` toggles `isHidden` per case + invokes
// `bodyView.configure(load:)` on `.loaded` so the pinned summary header
// renders with real data.
//
// === Error-state hand-rolled rationale (D-20, Phase 8 § Don't Hand-Roll exception) ===
// `UIContentUnavailableView` is the iOS-17-native error-state container,
// but its `Configuration.button` does NOT surface an
// `accessibilityIdentifier` field — the button's identifier cannot be
// locked from outside, and the rendered button is not addressable via the
// public view hierarchy with a stable identifier. Phase 8's UI-SPEC § Don't
// Hand-Roll Exceptions documents this case as the sanctioned exception to
// "prefer the system container." The LoadListViewController error-state
// (Phase 8 Plan 03, lines 240-298) is the canonical hand-rolled template
// Phase 9 mirrors here.
//
// === D-20 state subviews are pre-attached, hidden by default ===
// Three sibling container views are added in `layoutContent()`:
//   - `skeletonContainer` — populated by Plan 04 with `LoadDetailSkeletonView`.
//   - `errorContainer`    — populated by Plan 04 with the hand-rolled
//                           error UI (D-20).
//   - `bodyContainer`     — populated by Plan 04 (pinned header + section
//                           placeholders); Plans 05/06/09 inject into the
//                           body's named placeholders.
// `render(state:)` toggles `isHidden` per case. The containers stay attached
// to the view hierarchy across state transitions so Plans 04-09 install
// their subviews ONCE (in their own viewDidLoad-equivalent hook) instead of
// rebuilding on every state change.
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
// NSLocalizedString copies — heading, body, retry-button title. The
// negative grep gate on the associated-value identifier returns 0
// occurrences in this file (locked by the Plan 04 acceptance criteria).
//
// === Accessibility identifier namespace ===
// `view.accessibilityIdentifier = "load-detail"` (the LOCKED root per
// UI-SPEC § Accessibility identifiers). Per-container identifiers:
//   - `load-detail.skeleton`
//   - `load-detail.error-state`
//   - `load-detail.error-state.retry`
//   - `load-detail.body`
// `LoadDetailFlowTests` (XCUITest) probes these from day one — once-locked,
// future plans MUST NOT rename without a corresponding XCUITest update.
//
// === iOS 17 deployment minimum ===
// No iOS 18-only APIs used. `safeAreaLayoutGuide`, `UIView.isHidden`,
// `UIStackView`, `UIButton.Configuration.borderedProminent()` are iOS 15+.

import UIKit

public final class LoadDetailViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: LoadDetailViewModel

    // MARK: - Skeleton (D-19) — Plan 04 populates the container with this subview

    private let skeletonView = LoadDetailSkeletonView()

    // MARK: - Body (D-01 / D-02) — Plan 04 populates the container with this subview

    private let bodyView = LoadDetailBodyView()

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

    /// Body container — Plan 04 (header), 05 (timeline), 06 (graph), 09
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

    // MARK: - Error-state UI (D-20 — hand-rolled per Phase 8 § Don't Hand-Roll exception)
    //
    // Hand-rolled per the rationale in the file header. Mirrors
    // `LoadListViewController.errorStateView` (Phase 8 Plan 03, lines
    // 240-298). The retry button's `accessibilityIdentifier` is the locked
    // XCUITest probe `load-detail.error-state.retry`.

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

        // Plan 04 — install the state-specific subviews into the
        // pre-attached state containers.
        installSkeletonView()
        installBodyView()
        installErrorView()

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

    /// Pin `bodyView` (D-01) edge-to-edge inside `bodyContainer`.
    private func installBodyView() {
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyView)
        NSLayoutConstraint.activate([
            bodyView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])
    }

    /// Assemble the hand-rolled error-state subviews per D-20. Mirrors
    /// LoadListViewController.errorStateView (Phase 8 Plan 03, lines
    /// 240-298) — vertical stack of [icon, heading, body, retry] centered
    /// in the error container.
    private func installErrorView() {
        let stack = UIStackView(arrangedSubviews: [errorIcon, errorHeading, errorBody, errorRetryButton])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        // UI-SPEC § Spacing line 547 — error-state heading-to-body uses xl
        // gap; the surrounding stack uses md spacing and the layoutMargins
        // bracket the retry button vertically.
        stack.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.xl, left: DS.Spacing.lg,
            bottom: DS.Spacing.xl, right: DS.Spacing.lg
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        errorContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            // Center vertically + horizontally in the container; leading/
            // trailing pin so the stack's labels can wrap inside the safe
            // horizontal width.
            stack.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.trailingAnchor),
        ])
    }

    private func wireActions() {
        // D-20 — retry button re-fires viewModel.fetchLoadDetail() through
        // the same code path the initial viewWillAppear fetch used. The
        // VM's BL-01 cancel-and-replace handles any in-flight task; the
        // retry simply supersedes whatever was last attempted.
        errorRetryButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { [viewModel = self.viewModel] in
                await viewModel.fetchLoadDetail()
            }
        }, for: .touchUpInside)
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

    // MARK: - State → UI dispatcher (D-20 — isHidden toggles + body configure on .loaded)

    private func render(state: LoadDetailViewModel.State) {
        switch state {
        case .loading:
            skeletonContainer.isHidden = false
            bodyContainer.isHidden = true
            errorContainer.isHidden = true

        case .loaded(let load, _):
            // Plan 04 — wire the pinned summary header from the Load
            // aggregate. The chainOfTrust associated value is captured
            // (the `_` discard) but NOT used here: Plans 06 (TrustGraphView)
            // and 09 (chain-integrity verdict block + banner) consume it
            // from the VM's `state` at their own composition hooks.
            //
            // Per T-09-03 (no client trust): bodyView.configure(load:) reads
            // only referenceNumber + origin + destination + status — none of
            // which are trust-bearing.
            bodyView.configure(load: load)

            skeletonContainer.isHidden = true
            errorContainer.isHidden = true
            bodyContainer.isHidden = false

        case .error:
            // T-09-04 — the .error associated `message` is NEVER read here.
            // The error-state UI renders only the three locked
            // NSLocalizedString copies (heading, body, retry). Server-
            // supplied error text is logged by the VM but never surfaces.
            skeletonContainer.isHidden = true
            bodyContainer.isHidden = true
            errorContainer.isHidden = false
        }
    }
}
