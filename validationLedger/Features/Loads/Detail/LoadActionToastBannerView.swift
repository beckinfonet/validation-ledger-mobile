// validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift
//
// Phase 10 Plan 07 / D-15 — the transient action-failure toast banner.
// Mounted by `LoadDetailViewController.presentToastBanner(copyKey:)` on
// the `.actionFailed` render arm. Sibling of the chain-overlay alpha-fade
// subview (Plan 07's other piece) — both are transient subviews pinned at
// attach time and torn down in animation completion blocks.
//
// === Locked surface (UI-SPEC § LoadActionToastBannerView lines 458-475) ===
// Every property below is line-anchored to the UI-SPEC table. The view is
// PRESENTATION-ONLY:
//   * `configure(text:)` takes a LOCALIZED string the VC resolved. The view
//     NEVER touches `NSLocalizedString` and NEVER reads keys.
//   * `playSlideIn(in:topAnchor:after:onComplete:)` animates the rounded-
//     rect into rest position, fires a medium-impact haptic at slide-in
//     start, posts a VoiceOver `.announcement` after settle, schedules a
//     3.5s auto-dismiss timer.
//   * `playSlideOutAndRemove(onComplete:)` animates the rounded-rect off-
//     screen, removes from superview in the animation completion, fires
//     the supplied closure. Idempotent — a second call mid-animation is
//     dropped (no double-onComplete, no crash).
//   * Tap, swipe-up (translation.y < -12), and the 3.5s timer all route
//     through `playSlideOutAndRemove`. Swipe-DOWN is ignored.
//
// === T-09-04 view-layer lock (extended for Phase 10 D-15) ===
// `configure(text:)` is the ONLY way to set the visible copy. Server-
// supplied error text NEVER reaches the screen — the VM's
// `errorCopyKey(for:)` (LoadDetailViewModel.swift:490) maps the failed
// action to one of 6 LOCKED localization keys; the VC's `presentToastBanner
// (copyKey:)` resolves the key via `NSLocalizedString`; THIS view receives
// the already-resolved string. The view has zero key-resolution surface.
//
// === No third-party toast libraries (CLAUDE.md + RESEARCH § Don't Hand-Roll line 481) ===
// The banner is `UIView.animate` + `transform` + `alpha` — pure UIKit. No
// snack-bar / toast / message-banner third-party SwiftPM dependency.
// Phase 10 ships ZERO new dependencies; this view's hand-rolled animation
// IS that invariant in code form. The grep gate in 10-07-PLAN.md Task 1
// done-list asserts the absence of the forbidden import names; this
// comment refers to them by category only so the grep stays clean.
//
// === Pitfall 1 mirror (single-ref discipline) ===
// The VC's `currentToast: LoadActionToastBannerView?` follows the same
// idempotent-mount + clear-in-completion discipline as `chainOverlay`. The
// `onRemoved` callback below is the seam — when the banner removes itself
// from its superview (auto-dismiss, tap, swipe, or explicit slide-out),
// `onRemoved?()` fires; the VC's mount routine wires `onRemoved` to clear
// `currentToast` so a subsequent failure can mount cleanly.
//
// === iOS 17 deployment minimum ===
// All APIs used (UIImpactFeedbackGenerator, UITapGestureRecognizer,
// UIPanGestureRecognizer, UIView.animate, Timer.scheduledTimer,
// UIAccessibility.post) are iOS 10+. No iOS 18-only APIs.

import UIKit

@MainActor
public final class LoadActionToastBannerView: UIView {

    // MARK: - Locked timing constants (UI-SPEC lines 466-468)

    /// Slide-in animation duration — 0.28s .curveEaseOut.
    private static let slideInDuration: TimeInterval = 0.28
    /// Slide-out animation duration — 0.22s .curveEaseIn.
    private static let slideOutDuration: TimeInterval = 0.22
    /// Auto-dismiss delay measured from slide-in completion — 3.5s
    /// (overridable via `autoDismissDelayForTesting`).
    private static let defaultAutoDismissDelay: TimeInterval = 3.5
    /// Swipe-up dismissal threshold — translation.y < -12pt.
    private static let swipeUpThreshold: CGFloat = -12

    // MARK: - Internal subviews

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.image = UIImage(systemName: "exclamationmark.triangle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    private let messageLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.textColor = .white
        lbl.font = DS.Typography.body
        lbl.numberOfLines = 2
        lbl.lineBreakMode = .byWordWrapping
        lbl.adjustsFontForContentSizeCategory = true
        return lbl
    }()

    private lazy var contentStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [iconImageView, messageLabel])
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = DS.Spacing.sm
        s.isLayoutMarginsRelativeArrangement = true
        s.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: DS.Spacing.md,
            leading: DS.Spacing.md,
            bottom: DS.Spacing.md,
            trailing: DS.Spacing.md
        )
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - State

    /// Timer scheduled at slide-in completion; invalidated on any dismissal
    /// path (tap, swipe, second explicit slide-out, or natural fire).
    private var autoDismissTimer: Timer?

    /// True once `playSlideOutAndRemove` has begun. Guards Test 15 — a
    /// second `playSlideOutAndRemove` call mid-animation is dropped so the
    /// onComplete fires exactly once and the view does not double-remove.
    private var slideOutInProgress = false

    /// Lazy generator — `prepare()` is called at slide-in start; the
    /// actual haptic fires immediately after. Replaceable in DEBUG for
    /// test injection (see `hapticGeneratorForTesting`).
    private var hapticGenerator: UIImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Closure fired in `removeFromSuperview()` override. The VC's
    /// `presentToastBanner(copyKey:)` routine sets this to clear its
    /// `currentToast` ref so a subsequent `.actionFailed` transition can
    /// mount a fresh banner cleanly (Pitfall 1 single-ref discipline mirror).
    public var onRemoved: (() -> Void)?

    // MARK: - DEBUG test seams

    #if DEBUG
    /// Replace the medium-impact haptic generator with a spy. Used by
    /// `LoadActionToastBannerViewTests.test_playSlideIn_triggersImpactFeedback`.
    internal var hapticGeneratorForTesting: UIImpactFeedbackGenerator {
        get { hapticGenerator }
        set { hapticGenerator = newValue }
    }

    /// Override the 3.5s auto-dismiss delay. Tests set this to ~0.05s so
    /// the timer fires in test-realistic time.
    internal var autoDismissDelayForTesting: TimeInterval?

    /// Set by the test; the view invokes this in `playSlideIn`'s slide-in
    /// completion instead of `UIAccessibility.post(notification:argument:)`
    /// — `UIAccessibility.post` is not introspectable from XCTest without
    /// global notification-center spying.
    internal var voiceOverAnnouncementSpy: ((String?) -> Void)?

    /// Invoke the tap handler directly. Used in lieu of staging a real
    /// UITapGestureRecognizer state change in tests.
    internal func handleTapForTesting() { handleTap() }

    /// Invoke the pan handler with a synthetic translation and gesture
    /// state. Used in lieu of building a real UIPanGestureRecognizer
    /// transaction in tests.
    internal func handlePanForTesting(translationY: CGFloat, state: UIGestureRecognizer.State) {
        if state == .ended && translationY < Self.swipeUpThreshold {
            playSlideOutAndRemove(onComplete: nil)
        }
    }

    /// Captures the pre-animation transform inside `playSlideIn` BEFORE
    /// the UIView.animate call. UIView.animate's animations closure sets
    /// the model layer's transform to `.identity` synchronously, so
    /// reading `banner.transform` after `playSlideIn` returns would always
    /// observe `.identity` (the model-layer end value) — not the pre-
    /// animation transform we set. This seam exposes the pre-animation
    /// transform deterministically.
    internal private(set) var preAnimationTransformForTesting: CGAffineTransform?
    #endif

    // MARK: - Init

    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadActionToastBannerView does not support NSCoder; programmatic only — Phase 10 D-15")
    }

    private func setUp() {
        // UI-SPEC line 463-464 — rounded-rect, alpha-0.92 destructive ground.
        backgroundColor = DS.Colors.destructive.withAlphaComponent(0.92)
        layer.cornerRadius = 12

        // VoiceOver — single static-text element; focus is NOT trapped
        // (accessibilityViewIsModal is false by default; we leave it alone).
        isAccessibilityElement = true
        accessibilityTraits.insert(.staticText)
        // UI-SPEC line 475 — explicit assignment is for source-clarity only.
        accessibilityViewIsModal = false

        // Locked accessibility identifier for XCUITest probes (mirrors
        // chain-integrity-banner / chain-updating-overlay precedents).
        accessibilityIdentifier = "load-action-toast-banner"

        // Mount the icon + label stack.
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])

        // Tap-to-dismiss + swipe-up-to-dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    // MARK: - Public API

    /// Set the visible message. PURE presentation — the VC owns key
    /// resolution; this method receives a localized string and renders it
    /// verbatim (UI-SPEC § T-09-04 view-layer lock).
    public func configure(text: String) {
        messageLabel.text = text
        messageLabel.accessibilityLabel = text
        accessibilityLabel = text
    }

    /// Animate the banner into rest position (top + DS.Spacing.md).
    /// Fires a medium-impact haptic at slide-in start, posts a VoiceOver
    /// `.announcement` after settle, schedules a 3.5s auto-dismiss timer.
    ///
    /// Caller is responsible for adding `self` to `container`'s view
    /// hierarchy and pinning `leading`/`trailing` constraints BEFORE this
    /// call. This method only manages the vertical-translation animation
    /// and timing surface.
    public func playSlideIn(
        in container: UIView,
        topAnchor: NSLayoutYAxisAnchor,
        after delay: TimeInterval = 0,
        onComplete: (() -> Void)? = nil
    ) {
        // Pin our top to the supplied anchor (NB: leading/trailing are pinned
        // by the caller).
        let topConstraint = self.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.md)
        topConstraint.isActive = true

        // Lay out so bounds.height is real before we compute the off-screen
        // transform.
        container.layoutIfNeeded()

        let preY = -(bounds.height + 24)
        let preAnim = CGAffineTransform(translationX: 0, y: preY)
        transform = preAnim
        alpha = 1
        #if DEBUG
        preAnimationTransformForTesting = preAnim
        #endif

        // Medium-impact haptic at slide-in start (UI-SPEC line 470).
        hapticGenerator.prepare()
        hapticGenerator.impactOccurred()

        UIView.animate(
            withDuration: Self.slideInDuration,
            delay: delay,
            options: [.curveEaseOut],
            animations: {
                self.transform = .identity
            },
            completion: { [weak self] _ in
                guard let self else { return }
                // VoiceOver announcement (UI-SPEC line 474).
                #if DEBUG
                if let spy = self.voiceOverAnnouncementSpy {
                    spy(self.messageLabel.text)
                } else {
                    UIAccessibility.post(notification: .announcement, argument: self.messageLabel.text)
                }
                #else
                UIAccessibility.post(notification: .announcement, argument: self.messageLabel.text)
                #endif
                onComplete?()
                self.scheduleAutoDismiss()
            }
        )
    }

    /// Animate the banner off-screen and remove from superview. Fires
    /// `onComplete` after the animation completes. Idempotent — a second
    /// call mid-animation is dropped (no double-onComplete, no crash).
    public func playSlideOutAndRemove(onComplete: (() -> Void)? = nil) {
        guard !slideOutInProgress else { return }
        slideOutInProgress = true
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        UIView.animate(
            withDuration: Self.slideOutDuration,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.transform = CGAffineTransform(translationX: 0, y: -(self.bounds.height + 24))
                self.alpha = 0
            },
            completion: { [weak self] _ in
                self?.removeFromSuperview()
                onComplete?()
            }
        )
    }

    // MARK: - removeFromSuperview override (fires onRemoved hook)

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        onRemoved?()
    }

    // MARK: - Private

    @objc private func handleTap() {
        playSlideOutAndRemove(onComplete: nil)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: self)
        guard translation.y < Self.swipeUpThreshold else { return }
        playSlideOutAndRemove(onComplete: nil)
    }

    /// Start the auto-dismiss timer. Delay is `defaultAutoDismissDelay`
    /// unless `autoDismissDelayForTesting` overrides it (DEBUG only).
    private func scheduleAutoDismiss() {
        let delay: TimeInterval
        #if DEBUG
        delay = autoDismissDelayForTesting ?? Self.defaultAutoDismissDelay
        #else
        delay = Self.defaultAutoDismissDelay
        #endif
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.playSlideOutAndRemove(onComplete: nil)
            }
        }
    }
}
