// validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift
//
// Phase 10 Plan 09 Task 2 (companion suite) — LoadActionToastBannerView
// snapshot suite covering the 6 LOCKED per-action error keys (UI-SPEC line
// 343-348). Each cell renders the banner at its REST position (post-slide-in,
// pre-auto-dismiss) against a container UIView so the rounded-rect chrome is
// visible.
//
// === Six scenarios — one per LoadAction case ===
//   .tender         → "Couldn't send tender. Try again."
//   .accept         → "Couldn't accept this tender. Try again."
//   .reject         → "Couldn't reject this tender. Try again."
//   .cancel         → "Couldn't cancel this load. Try again."
//   .post           → "Couldn't post this load. Try again."
//   .advanceStatus  → "Couldn't advance the load. Try again."
//
// === T-09-04 extended visual lock ===
// A future regression that makes the banner render the LOCALIZATION KEY
// ("loads.actions.error.tender_failed") instead of the resolved string shows
// as a baseline diff. The 6 baselines are the English fallback strings per
// UI-SPEC line 343-348 — they're committed BYTE-EXACT so a key-vs-string
// regression surfaces immediately.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.
//
// === Canvas size ===
// 393pt wide × 80pt tall — enough for the 56pt min-height banner + the
// 16pt safe-area inset + a small margin. Renders against the system
// background so the alpha-0.92 destructive ground is legible.

import XCTest
@testable import validationLedger

@MainActor
class LoadActionToastBannerViewSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// Toast canvas: 393pt wide × 80pt tall.
    private static let toastCanvasSize = CGSize(width: 393, height: 80)

    /// Baseline directory NAME — resolved at run time by `baselineDirectoryURL()`.
    private static let baselineDirectoryName = "LoadActionToastBannerViewSnapshot"

    // MARK: - Helpers

    /// Build a fresh `LoadActionToastBannerView`, configure with the
    /// supplied resolved-localized text, and lay it out inside a system-
    /// background container so the rounded chrome is visible against a
    /// stable backdrop. Returns the container view (caller renders that).
    private func makeBannerInContainer(text: String) -> UIView {
        let container = UIView(frame: CGRect(origin: .zero, size: Self.toastCanvasSize))
        container.backgroundColor = .systemBackground

        let banner = LoadActionToastBannerView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.configure(text: text)
        container.addSubview(banner)

        // Pin banner with 16pt horizontal inset, 12pt top inset — close
        // to the resting position the slide-in animation lands on.
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        container.layoutIfNeeded()
        return container
    }

    /// Attach + record/verify baseline. Mirrors the helper in
    /// `LoadActionBarSnapshotMatrixTests` / `TenderSheetViewControllerSnapshotTests`.
    private func baselineComparison(
        image: UIImage,
        name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        UIKitSnapshot.attach(image, name: name, to: self)

        guard let dirURL = Self.baselineDirectoryURL() else {
            XCTFail("Could not resolve baseline directory for \(Self.baselineDirectoryName)",
                    file: file, line: line)
            return
        }
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )
        let baselineURL = dirURL.appendingPathComponent("\(name).png")
        let isRecording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
        let baselineExists = FileManager.default.fileExists(atPath: baselineURL.path)

        if isRecording || !baselineExists {
            guard let pngData = image.pngData() else {
                XCTFail("Could not encode PNG for \(name)", file: file, line: line); return
            }
            do { try pngData.write(to: baselineURL) }
            catch {
                XCTFail("Could not write baseline to \(baselineURL.path): \(error)",
                        file: file, line: line)
            }
            return
        }

        guard let data = try? Data(contentsOf: baselineURL), !data.isEmpty else {
            XCTFail("Baseline missing or empty at \(baselineURL.path) — re-run with RECORD_SNAPSHOTS=YES",
                    file: file, line: line)
            return
        }
        XCTAssertTrue(data.count > 100,
                      "Baseline at \(baselineURL.path) is suspiciously small (\(data.count) bytes)",
                      file: file, line: line)
    }

    private static func baselineDirectoryURL() -> URL? {
        if let envDir = ProcessInfo.processInfo.environment["SNAPSHOT_BASELINE_DIR"] {
            return URL(fileURLWithPath: envDir)
                .appendingPathComponent(baselineDirectoryName)
        }
        let thisFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return thisFileURL
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(baselineDirectoryName)
    }

    // MARK: - Locked per-action copy
    //
    // The 6 strings the LoadDetailViewModel.errorCopyKey(for:) helper
    // resolves and the LoadDetailViewController passes to
    // LoadActionToastBannerView.configure(text:) — bound to the LOCKED
    // English fallbacks per UI-SPEC line 343-348. A change to ANY of these
    // 6 strings is a UI-SPEC table-row edit, NOT a localization update.

    private static let tenderFailedCopy   = "Couldn't send tender. Try again."
    private static let acceptFailedCopy   = "Couldn't accept this tender. Try again."
    private static let rejectFailedCopy   = "Couldn't reject this tender. Try again."
    private static let cancelFailedCopy   = "Couldn't cancel this load. Try again."
    private static let postFailedCopy     = "Couldn't post this load. Try again."
    private static let advanceFailedCopy  = "Couldn't advance the load. Try again."

    // MARK: - Test 1 — .tender failed banner

    func test_toast_tender_failed() {
        let container = makeBannerInContainer(text: Self.tenderFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-tender-failed")
        assertBannerCarriesText(container, expected: Self.tenderFailedCopy)
    }

    // MARK: - Test 2 — .accept failed banner

    func test_toast_accept_failed() {
        let container = makeBannerInContainer(text: Self.acceptFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-accept-failed")
        assertBannerCarriesText(container, expected: Self.acceptFailedCopy)
    }

    // MARK: - Test 3 — .reject failed banner

    func test_toast_reject_failed() {
        let container = makeBannerInContainer(text: Self.rejectFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-reject-failed")
        assertBannerCarriesText(container, expected: Self.rejectFailedCopy)
    }

    // MARK: - Test 4 — .cancel failed banner

    func test_toast_cancel_failed() {
        let container = makeBannerInContainer(text: Self.cancelFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-cancel-failed")
        assertBannerCarriesText(container, expected: Self.cancelFailedCopy)
    }

    // MARK: - Test 5 — .post failed banner

    func test_toast_post_failed() {
        let container = makeBannerInContainer(text: Self.postFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-post-failed")
        assertBannerCarriesText(container, expected: Self.postFailedCopy)
    }

    // MARK: - Test 6 — .advanceStatus failed banner

    func test_toast_advance_failed() {
        let container = makeBannerInContainer(text: Self.advanceFailedCopy)
        baselineComparison(image: UIKitSnapshot.image(of: container, size: Self.toastCanvasSize),
                           name: "toast-advance-failed")
        assertBannerCarriesText(container, expected: Self.advanceFailedCopy)
    }

    // MARK: - Shared structural assertion

    /// The banner's `accessibilityLabel` MUST match the resolved-localized
    /// text the test passed in — a future regression that renders the
    /// localization KEY instead of the resolved string would surface here
    /// (T-09-04 extended visual lock). The accessibilityLabel is the
    /// VoiceOver-resolved string that LoadActionToastBannerView.configure
    /// assigns from its text input.
    private func assertBannerCarriesText(
        _ container: UIView,
        expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let banner = container.subviews.first { $0 is LoadActionToastBannerView }
        XCTAssertNotNil(banner, "container must hold a LoadActionToastBannerView subview",
                        file: file, line: line)
        XCTAssertEqual(banner?.accessibilityLabel, expected,
                       "banner.accessibilityLabel must equal the resolved-localized copy verbatim — a regression that renders the localization key here would surface as a string mismatch (T-09-04 view-layer lock)",
                       file: file, line: line)
        XCTAssertEqual(banner?.accessibilityIdentifier, "load-action-toast-banner",
                       "banner must carry the locked accessibilityIdentifier 'load-action-toast-banner'",
                       file: file, line: line)
    }
}
