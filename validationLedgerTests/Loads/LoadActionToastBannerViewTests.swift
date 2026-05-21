// validationLedgerTests/Loads/LoadActionToastBannerViewTests.swift
//
// Phase 10 Plan 07 Task 1 — unit tests for `LoadActionToastBannerView`.
//
// Locks (UI-SPEC § LoadActionToastBannerView lines 458-475 + D-15):
//   - Rounded-rect, cornerRadius 12pt, background DS.Colors.destructive at
//     alpha 0.92.
//   - SF Symbol `exclamationmark.triangle.fill` (white) + UILabel (white,
//     numberOfLines 2) inside a horizontal UIStackView.
//   - `configure(text:)` is pure presentation — the VC owns key-resolution.
//     The view NEVER touches NSLocalizedString.
//   - `playSlideIn(in:topAnchor:after:onComplete:)` posts a VoiceOver
//     `.announcement`, fires a medium-impact haptic, schedules a 3.5s
//     auto-dismiss timer.
//   - Tap, swipe-up (translation.y < -12), and the 3.5s timer all trigger
//     `playSlideOutAndRemove`.
//   - Swipe-DOWN is IGNORED.
//   - Double-dismiss is idempotent (no double-onComplete; no crash).
//   - `required init?(coder:)` traps with fatalError (lint-as-test below).
//   - `accessibilityViewIsModal == false` (UI-SPEC line 475 — VoiceOver
//     focus is not trapped).
//
// === Why XCTest, not Swift Testing ===
// Matches the Phase 10 wave 1/2/3 XCTest neighbors. Animation tests use
// XCTest expectations (`XCTestExpectation.fulfill()`).
//
// === Test-seam strategy ===
// LoadActionToastBannerView exposes a small `internal` surface guarded by
// `#if DEBUG` for test-only injection:
//   - `internal var hapticGeneratorForTesting: UIImpactFeedbackGenerator`
//     (settable so a spy subclass can record `impactOccurred()`).
//   - `internal func handleTapForTesting()` / `internal func
//     handlePanForTesting(translationY:state:)` — invoke the gesture
//     handlers directly without staging a real `UIGestureRecognizer`.
//   - `internal var autoDismissDelayForTesting: TimeInterval` — tests
//     override the 3.5s default to 0.05s for the timer-fire assertion.
//   - `internal var voiceOverAnnouncementSpy: ((String?) -> Void)?` — set
//     by the test; the view invokes it from `playSlideIn`'s slide-in
//     completion in place of `UIAccessibility.post`.
// Production callers see the locked timing constants; test code sees the
// overridable seams via `@testable import validationLedger`.

import XCTest
@testable import validationLedger

final class LoadActionToastBannerViewTests: XCTestCase {

    // MARK: - Helpers

    /// Build a container view, attach the banner, run a layout pass so
    /// bounds are real (not .zero), then return the pair.
    @MainActor
    private func makeMountedBanner(
        text: String = "Couldn't send tender. Try again."
    ) -> (banner: LoadActionToastBannerView, container: UIView) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let banner = LoadActionToastBannerView()
        banner.configure(text: text)
        return (banner, container)
    }

    // MARK: - Test 1 — subview hierarchy (icon + label inside horizontal stack)

    @MainActor
    func test_init_subviewHierarchy_isCorrect() {
        let banner = LoadActionToastBannerView()
        // Find the UIStackView in the banner subtree.
        let stacks = banner.subviewsRecursive(of: UIStackView.self)
        XCTAssertEqual(stacks.count, 1, "Banner contains exactly one UIStackView (the icon + label horizontal stack)")
        let stack = stacks[0]
        XCTAssertEqual(stack.axis, .horizontal)
        // Stack must contain a UIImageView with the locked SF Symbol + a UILabel.
        let icon = stack.arrangedSubviews.compactMap { $0 as? UIImageView }.first
        let label = stack.arrangedSubviews.compactMap { $0 as? UILabel }.first
        XCTAssertNotNil(icon, "Stack contains a UIImageView (icon)")
        XCTAssertNotNil(label, "Stack contains a UILabel (message)")
        XCTAssertEqual(icon?.tintColor, .white, "Icon tint is white")
        XCTAssertEqual(label?.textColor, .white, "Label text color is white")
        XCTAssertEqual(label?.numberOfLines, 2, "Label is two-line max per UI-SPEC line 472")
    }

    // MARK: - Test 2 — background alpha 0.92, base DS.Colors.destructive

    @MainActor
    func test_init_backgroundColor_isDestructive92Alpha() {
        let banner = LoadActionToastBannerView()
        let expected = DS.Colors.destructive.withAlphaComponent(0.92)
        // Compare via CGColor component readback — UIColor equality is
        // sensitive to color-space and dynamic-color comparisons in tests.
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        var exR: CGFloat = 0, exG: CGFloat = 0, exB: CGFloat = 0, exA: CGFloat = 0
        XCTAssertNotNil(banner.backgroundColor)
        banner.backgroundColor?.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        expected.getRed(&exR, green: &exG, blue: &exB, alpha: &exA)
        XCTAssertEqual(bgA, 0.92, accuracy: 0.01, "Background alpha is 0.92 per UI-SPEC line 464")
        XCTAssertEqual(bgR, exR, accuracy: 0.01)
        XCTAssertEqual(bgG, exG, accuracy: 0.01)
        XCTAssertEqual(bgB, exB, accuracy: 0.01)
    }

    // MARK: - Test 3 — cornerRadius == 12

    @MainActor
    func test_init_cornerRadius_isTwelvePoint() {
        let banner = LoadActionToastBannerView()
        XCTAssertEqual(banner.layer.cornerRadius, 12, "Corner radius is 12pt per UI-SPEC line 463")
    }

    // MARK: - Test 4 — configure(text:) sets the label text VERBATIM (no key resolution in the view)

    @MainActor
    func test_configure_setsLabelText() {
        let banner = LoadActionToastBannerView()
        banner.configure(text: "Couldn't send tender. Try again.")
        let label = banner.subviewsRecursive(of: UILabel.self).first
        XCTAssertEqual(label?.text, "Couldn't send tender. Try again.")
        // The view's own accessibility label mirrors the visible text.
        XCTAssertEqual(banner.accessibilityLabel, "Couldn't send tender. Try again.")
    }

    // MARK: - Test 5 — required init?(coder:) traps (lint-as-test source check)

    /// Swift's fatalError-trap inside `required init?(coder:)` is not
    /// catchable at runtime via XCTAssertThrowsError. Per the standing
    /// pattern set by `ChainIntegrityBannerView`'s analog, the trap is
    /// LINTED via a source-grep test — the symbol `fatalError(` MUST appear
    /// inside the view source file.
    func test_init_requiredInitCoder_traps_sourceGrep() throws {
        let thisFile = URL(fileURLWithPath: #file)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // Loads/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo>/
        let target = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Features")
            .appendingPathComponent("Loads")
            .appendingPathComponent("Detail")
            .appendingPathComponent("LoadActionToastBannerView.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path),
                      "LoadActionToastBannerView.swift must exist at \(target.path)")
        let src = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(src.contains("fatalError("),
                      "required init?(coder:) MUST trap with fatalError per programmatic-only invariant")
        XCTAssertTrue(src.contains("required init?(coder"),
                      "view exposes the required NSCoder init for compiler conformance even though it traps")
    }

    // MARK: - Test 6 — playSlideIn posts a VoiceOver .announcement

    @MainActor
    func test_playSlideIn_postsVoiceOverAnnouncement() {
        let (banner, container) = makeMountedBanner(text: "Couldn't accept this tender. Try again.")
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()

        let exp = expectation(description: "VoiceOver .announcement posted with banner text")
        var announced: String?
        banner.voiceOverAnnouncementSpy = { text in
            announced = text
            exp.fulfill()
        }
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)
        // Slide-in animation is 0.28s; the announcement fires in the
        // completion block. Wait 1.0s for headroom.
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(announced, "Couldn't accept this tender. Try again.")
    }

    // MARK: - Test 7 — playSlideIn triggers impactFeedback

    @MainActor
    func test_playSlideIn_triggersImpactFeedback() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()

        // Inject a spy haptic generator.
        let spy = SpyHapticGenerator(style: .medium)
        banner.hapticGeneratorForTesting = spy

        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)
        XCTAssertEqual(spy.impactCount, 1, "Medium-impact haptic fires exactly once at slide-in start")
    }

    // MARK: - Test 8 — playSlideIn pins below the supplied top anchor with DS.Spacing.md

    @MainActor
    func test_playSlideIn_pinsToTopAndContainerLayoutMarginsGuide() {
        let (banner, container) = makeMountedBanner()
        // Use a window so safeAreaInsets resolve correctly.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.addSubview(container)
        container.frame = window.bounds

        container.addSubview(banner)
        // Caller's responsibility per the API contract: pin leading/trailing
        // BEFORE invoking playSlideIn (the method only manages the vertical
        // slide-in animation + the auto-dismiss timer).
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()

        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        // After the slide-in animation completes the banner sits at
        // container.top + DS.Spacing.md. Wait for the 0.28s animation.
        let exp = expectation(description: "Slide-in settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            container.layoutIfNeeded()
            // The banner's frame.origin.y is approximately the top anchor's
            // y (0 for container.topAnchor) + DS.Spacing.md = 16 (post
            // identity transform).
            XCTAssertEqual(banner.frame.origin.y, DS.Spacing.md, accuracy: 1.0,
                           "Banner settles at top + DS.Spacing.md after slide-in")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.5)
    }

    // MARK: - Test 9 — pre-animation transform is off-screen

    @MainActor
    func test_playSlideIn_preAnimationFrameIsOffScreen() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()

        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)
        // `UIView.animate`'s animations closure synchronously sets the
        // model-layer's transform to `.identity` (its end state); reading
        // `banner.transform` after the call would observe `.identity`,
        // not the pre-animation value. The view captures the pre-animation
        // transform via `preAnimationTransformForTesting` BEFORE entering
        // the animate block — that is the deterministic seam tests use.
        XCTAssertGreaterThan(banner.bounds.height, 0,
                             "Banner has laid-out intrinsic height before slide-in")
        let expectedY = -(banner.bounds.height + 24)
        let captured = banner.preAnimationTransformForTesting
        XCTAssertNotNil(captured, "Pre-animation transform captured before UIView.animate commits")
        XCTAssertEqual(captured?.ty ?? 0, expectedY, accuracy: 1.0,
                       "Pre-anim transform is -(banner.bounds.height + 24) per UI-SPEC line 467")
    }

    // MARK: - Test 10 — tap triggers slide-out

    @MainActor
    func test_tap_triggersSlideOut() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        let exp = expectation(description: "Tap dismisses the banner")
        // Wait for slide-in to settle, then tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            banner.handleTapForTesting()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                XCTAssertNil(banner.superview, "Banner removed from superview after tap → slide-out")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 11 — swipe-up triggers slide-out

    @MainActor
    func test_swipeUp_triggersSlideOut() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        let exp = expectation(description: "Swipe-up dismisses the banner")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Translation.y < -12 → trigger slide-out.
            banner.handlePanForTesting(translationY: -20, state: .ended)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                XCTAssertNil(banner.superview, "Banner removed from superview after swipe-up")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 12 — swipe-DOWN is ignored

    @MainActor
    func test_swipeDown_ignored() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        let exp = expectation(description: "Swipe-down does NOT dismiss the banner")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Translation.y > 0 (downward swipe) → no slide-out.
            banner.handlePanForTesting(translationY: 20, state: .ended)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                XCTAssertNotNil(banner.superview, "Banner stays mounted after a downward swipe")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 13 — auto-dismiss timer fires (uses test-only short delay)

    @MainActor
    func test_autoDismiss_after3p5seconds() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        // Override the auto-dismiss delay to 0.05s so the test runs fast.
        banner.autoDismissDelayForTesting = 0.05
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        let exp = expectation(description: "Auto-dismiss timer fires and removes the banner")
        // Wait for slide-in + override-delay + slide-out animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            XCTAssertNil(banner.superview,
                         "Banner auto-dismissed via the (overridden) short delay timer")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 14 — playSlideOutAndRemove calls onComplete + removes from superview

    @MainActor
    func test_playSlideOutAndRemove_callsOnCompleteAndRemovesFromSuperview() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)

        let exp = expectation(description: "onComplete fires; banner removed")
        banner.playSlideOutAndRemove(onComplete: {
            // Closure must fire after the 0.22s slide-out animation.
            XCTAssertNil(banner.superview, "Banner is removed when onComplete fires")
            exp.fulfill()
        })
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 15 — double-tap during slide-out is idempotent (no crash, no double-onComplete)

    @MainActor
    func test_doubleTapDuringSlideOut_doesNotCrash() {
        let (banner, container) = makeMountedBanner()
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutIfNeeded()
        banner.playSlideIn(in: container, topAnchor: container.topAnchor, after: 0, onComplete: nil)

        var completionCount = 0
        let exp = expectation(description: "Slide-out completes exactly once")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // First slide-out — supplies the completion closure.
            banner.playSlideOutAndRemove(onComplete: {
                completionCount += 1
            })
            // Second slide-out 0.05s later (mid-animation). Should be a no-op.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                banner.playSlideOutAndRemove(onComplete: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                XCTAssertEqual(completionCount, 1,
                               "playSlideOutAndRemove is idempotent — second call is dropped")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Test 16 — accessibilityViewIsModal == false

    @MainActor
    func test_accessibilityViewIsModal_false() {
        let banner = LoadActionToastBannerView()
        XCTAssertFalse(banner.accessibilityViewIsModal,
                       "VoiceOver focus is not trapped — UI-SPEC line 475")
    }
}

// MARK: - Test doubles

/// Spy haptic generator that records `impactOccurred()` calls.
/// Subclasses `UIImpactFeedbackGenerator` so the typed `var
/// hapticGeneratorForTesting: UIImpactFeedbackGenerator` accepts it without
/// a protocol-wrapper hop.
@MainActor
private final class SpyHapticGenerator: UIImpactFeedbackGenerator {
    private(set) var impactCount = 0
    override func impactOccurred() {
        super.impactOccurred()
        impactCount += 1
    }
}

// MARK: - Subview lookup helper

private extension UIView {
    /// Recursive subview lookup by exact type. Used by the banner tests
    /// instead of repeatedly walking `subviews` arms.
    func subviewsRecursive<T: UIView>(of type: T.Type) -> [T] {
        var out: [T] = []
        for sub in subviews {
            if let hit = sub as? T { out.append(hit) }
            out.append(contentsOf: sub.subviewsRecursive(of: type))
        }
        return out
    }
}
