// validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift
//
// Phase 8 Plan 02 Task 3 — LoadStatusBadgeView snapshot + tone-tier assertions.
//
// === Why XCTest, not Swift Testing ===
// Same rationale as VerificationBadgeViewSnapshotTests — UIKitSnapshot.attach
// requires the XCTestCase.add(_:) API surface. See sibling-file header for
// the full justification + Plans-04-and-05 precedent note.
//
// === Locked test surface ===
//   - 4 representative tone-tier tests (per UI-SPEC §Color status table):
//     - test_draftStatusRendersPreLifeTone:           .systemGray6
//     - test_inTransitStatusRendersInProgressTone:    .tertiarySystemFill
//     - test_deliveredStatusRendersDoneTone:          .systemGray5
//     - test_cancelledStatusRendersTerminalErrorWithStrikethrough: .systemGray5
//       + NSAttributedString with .strikethroughStyle
//   - 1 ramp-isolation lock (T-08-06 secondary):
//     - test_statusBadgeNeverReusesVerificationRampColors loops every
//       LoadStatus case and asserts backgroundColor is neither
//       DS.Colors.primary nor DS.Colors.destructive.
//
// === T-08-05 (PII) ===
// Tests construct views with synthetic enum values only — no party names
// or IDs ever reach the rendered image.

import XCTest
@testable import validationLedger

class LoadStatusBadgeViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// Wider than VerificationBadgeView's pill — accommodates the longest
    /// uppercase status label ("POD CAPTURED").
    private static let pillSize = CGSize(width: 180, height: 28)

    // MARK: - Tone-tier representative tests

    func test_draftStatusRendersPreLifeTone() {
        let view = LoadStatusBadgeView()
        view.configure(status: .draft)

        XCTAssertEqual(view.backgroundColor, .systemGray6,
                       "Draft status (pre-life tone) background must be .systemGray6.")

        // Pre-life tone uses plain `label.text`, not attributedText.
        XCTAssertEqual(view.statusBadgeLabelText, "DRAFT",
                       "Draft status label text must be exactly 'DRAFT' (uppercase).")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "LoadStatusBadge-draft", to: self)
    }

    func test_inTransitStatusRendersInProgressTone() {
        let view = LoadStatusBadgeView()
        view.configure(status: .inTransit)

        XCTAssertEqual(view.backgroundColor, .tertiarySystemFill,
                       "In-transit status (in-progress tone) background must be .tertiarySystemFill.")

        XCTAssertEqual(view.statusBadgeLabelText, "IN TRANSIT",
                       "In-transit label must be 'IN TRANSIT' (space-separated uppercase).")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "LoadStatusBadge-inTransit", to: self)
    }

    func test_deliveredStatusRendersDoneTone() {
        let view = LoadStatusBadgeView()
        view.configure(status: .delivered)

        XCTAssertEqual(view.backgroundColor, .systemGray5,
                       "Delivered status (done tone) background must be .systemGray5.")

        XCTAssertEqual(view.statusBadgeLabelText, "DELIVERED",
                       "Delivered status label text must be exactly 'DELIVERED'.")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "LoadStatusBadge-delivered", to: self)
    }

    func test_cancelledStatusRendersTerminalErrorWithStrikethrough() {
        let view = LoadStatusBadgeView()
        view.configure(status: .cancelled)

        XCTAssertEqual(view.backgroundColor, .systemGray5,
                       "Cancelled status (terminal-error tone) background must be .systemGray5.")

        // The terminal-error tone renders via NSAttributedString with
        // .strikethroughStyle. Extract the attribute at index 0 and assert
        // it represents a single-line strikethrough.
        let attributed = view.statusBadgeAttributedText
        XCTAssertNotNil(attributed,
                        "Cancelled status must render via NSAttributedString (terminal-error tone uses strikethrough).")

        if let attributed = attributed {
            let strikeAttr = attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
            XCTAssertEqual(strikeAttr, NSUnderlineStyle.single.rawValue,
                           "Cancelled status attributedText must carry .strikethroughStyle = .single.")
            XCTAssertEqual(attributed.string, "CANCELLED",
                           "Cancelled label string must be exactly 'CANCELLED' (Pitfall 7: double-l).")
        }

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "LoadStatusBadge-cancelled", to: self)
    }

    // MARK: - Ramp-isolation lock (T-08-06 secondary)

    /// LOCK: the status badge MUST NEVER reuse the verification color ramp
    /// (DS.Colors.primary / DS.Colors.destructive). Loop every LoadStatus
    /// case and assert the resolved backgroundColor is neither.
    /// Sharing color across two unrelated meanings is the design bug
    /// UI-SPEC §Color "Status badge color rules" explicitly forbids.
    func test_statusBadgeNeverReusesVerificationRampColors() {
        let view = LoadStatusBadgeView()
        for status in LoadStatus.allCases {
            view.configure(status: status)
            XCTAssertNotEqual(view.backgroundColor, DS.Colors.primary,
                              "Status .\(status.rawValue) must not reuse DS.Colors.primary (verification ramp).")
            XCTAssertNotEqual(view.backgroundColor, DS.Colors.destructive,
                              "Status .\(status.rawValue) must not reuse DS.Colors.destructive (verification ramp).")
        }
    }
}

// MARK: - Test introspection helpers
//
// LoadStatusBadgeView's `label` is private (correct encapsulation). For the
// snapshot suite we expose a minimal read-only window via a test-bundle
// extension that walks the view's subview tree to find the label. This
// keeps the production view's surface clean while giving tests deterministic
// access to the rendered text.

private extension UIView {
    func firstLabelInTree() -> UILabel? {
        if let l = self as? UILabel { return l }
        for sub in subviews {
            if let l = sub.firstLabelInTree() { return l }
        }
        return nil
    }
}

extension LoadStatusBadgeView {
    /// Test-only window onto the rendered plain `text`. Returns nil for the
    /// terminal-error tone (which uses `attributedText` instead).
    var statusBadgeLabelText: String? {
        return firstLabelInTree()?.text
    }

    /// Test-only window onto the rendered `attributedText` — populated only
    /// for the terminal-error tone (rejected / expired / cancelled).
    var statusBadgeAttributedText: NSAttributedString? {
        return firstLabelInTree()?.attributedText
    }
}
