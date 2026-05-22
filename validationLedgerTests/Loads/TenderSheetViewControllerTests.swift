// validationLedgerTests/Loads/TenderSheetViewControllerTests.swift
//
// Phase 10 Plan 06 Task 1 — unit tests for `TenderSheetViewController` (NEW)
// and `TenderSheetCarrierRowView` (NEW).
//
// === Test scope (15 tests; mirrors Plan 06 Task 1 <behavior>) ===
//   - Test 1  : table renders all 6 carriers (D-08 visible-but-disabled)
//   - Test 2  : verified row userInteractionEnabled=true; flagged row =false;
//               contentView alpha 1.0 vs 0.6; badgeView alpha stays 1.0
//               (UI-SPEC line 446)
//   - Test 3  : disabled reason copy matches verification state per
//               loads.detail.tender.carrier.disabled.* keys
//   - Test 4  : Send button initially disabled; helper says "Pick a carrier"
//   - Test 5  : selecting a verified row enables Send + hides helper line
//   - Test 6  : verified row + past deadline disables Send; helper says
//               "Pick a future deadline."
//   - Test 7  : 5 deadline chips (1h / 4h / 1 day / 2 days / Custom…);
//               "1 day" initially selected (UI-SPEC line 447)
//   - Test 8  : chip tap updates the resolved-time line
//   - Test 9  : Custom… chip reveals a UIDatePicker (UI-SPEC line 449)
//   - Test 10 : Send invokes onSend with the correct (targetPartyID, deadline)
//   - Test 11 : during in-flight onSend, sheet stays visible + spinner +
//               isEnabled=false (UI-SPEC line 454)
//   - Test 12 : Cancel button invokes onCancel
//   - Test 13 : helper toggles via alpha 0/1 (NOT isHidden) — fixed height
//               preserved (Pitfall 8)
//   - Test 14 : empty directory => Send permanently disabled
//   - Test 15 : directory with no .verified carriers => Send permanently
//               disabled (carrier-level ACTION-04 gate)
//
// === Why XCTest, not Swift Testing ===
// Matches the Wave 1/2/3 XCTest neighbors in this folder. Mixing XCTest and
// Swift Testing in one `-only-testing` invocation is a known pitfall on this
// project (ios-test-suite-pitfalls memory).
//
// === -only-testing canonical form ===
// `xcodebuild test -only-testing:validationLedgerTests/TenderSheetViewControllerTests`
// — class-name only, NO folder segment (Plan 04 deviation note 6).

import XCTest
@testable import validationLedger

final class TenderSheetViewControllerTests: XCTestCase {

    // MARK: - Window retention (avoid `view.window == nil` race when the
    // local `UIWindow` falls out of scope at the end of `makeSheet`).

    private var retainedWindows: [UIWindow] = []

    override func tearDown() {
        retainedWindows.removeAll()
        super.tearDown()
    }

    // MARK: - In-test directory factory

    /// 6-carrier roster mirroring the Plan 05 fixture partyIDs:
    ///   2 .verified (Acme + Northwind), 2 .pending (Cascadia + Summit),
    ///   1 .unverified (Anonymous), 1 .flagged (Chameleon). 6 rows let
    ///   Test 1's row-count check stay stable across fixture edits.
    private func makeStandardDirectory() -> [TrustNode] {
        [
            TrustNode(
                partyID: "party-carrier-acme",
                role: .carrier,
                displayName: "Acme Logistics Inc.",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: "0123456",
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier-northwind",
                role: .carrier,
                displayName: "Northwind Freight Co.",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: "0234567",
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier-cascadia",
                role: .carrier,
                displayName: "Cascadia Cartage",
                verificationState: .pending,
                kycCompletedAt: nil,
                deviceBindingStatus: .unbound,
                usdotNumber: "0345678",
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier-summit",
                role: .carrier,
                displayName: "Summit Routing LLC",
                verificationState: .pending,
                kycCompletedAt: nil,
                deviceBindingStatus: .unbound,
                usdotNumber: nil,
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier-anonymous",
                role: .carrier,
                displayName: "Anonymous Hauling",
                verificationState: .unverified,
                kycCompletedAt: nil,
                deviceBindingStatus: .unbound,
                usdotNumber: nil,
                usdotAuthorityStatus: .notApplicable,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier-chameleon",
                role: .carrier,
                displayName: "Chameleon Cargo LLC",
                verificationState: .flagged,
                kycCompletedAt: nil,
                deviceBindingStatus: .mismatched,
                usdotNumber: "9999991",
                usdotAuthorityStatus: .revoked,
                priorRelationships: []
            ),
        ]
    }

    /// Build a TenderSheetViewController with the standard directory + a
    /// no-op send/cancel pair. Tests that need to capture callbacks override
    /// the closures inline.
    @MainActor
    private func makeSheet(
        directory: [TrustNode]? = nil,
        onSend: @escaping @MainActor (_ targetPartyID: String, _ respondByAt: Date) async -> Void = { _, _ in },
        onCancel: @escaping () -> Void = {}
    ) -> TenderSheetViewController {
        let dir = directory ?? makeStandardDirectory()
        let vc = TenderSheetViewController(directory: dir, onSend: onSend, onCancel: onCancel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        // Retain the window on the test instance so `view.window != nil`
        // holds for the lifetime of the test (avoids the local-scope GC
        // that strands the VC's view without a host window).
        retainedWindows.append(window)
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 400, height: 700)
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Helpers (table view + row introspection)

    /// All visible carrier row cells in the table view.
    @MainActor
    private func carrierRows(_ vc: TenderSheetViewController) -> [TenderSheetCarrierRowView] {
        var rows: [TenderSheetCarrierRowView] = []
        let table = vc.tableViewForTesting
        for section in 0..<table.numberOfSections {
            for row in 0..<table.numberOfRows(inSection: section) {
                let ip = IndexPath(row: row, section: section)
                if let cell = table.cellForRow(at: ip) as? TenderSheetCarrierRowView {
                    rows.append(cell)
                }
            }
        }
        return rows
    }

    @MainActor
    private func futureDate(_ seconds: TimeInterval = 24 * 3600) -> Date {
        Date(timeIntervalSinceNow: seconds)
    }

    @MainActor
    private func pastDate(_ seconds: TimeInterval = 3600) -> Date {
        Date(timeIntervalSinceNow: -seconds)
    }

    // MARK: - Test 1 — table renders all 6 carriers (D-08 visible-but-disabled)

    @MainActor
    func test_sheet_rendersAllSixCarriersInPicker() {
        let vc = makeSheet()
        let table = vc.tableViewForTesting
        let total = (0..<table.numberOfSections).reduce(0) { acc, s in
            acc + table.numberOfRows(inSection: s)
        }
        XCTAssertEqual(total, 6, "D-08: all 6 carriers (including unverified/flagged/pending) MUST be visible in the picker — hiding them is the wrong choice per the platform thesis.")
    }

    // MARK: - Test 2 — verified vs disabled (alpha + interaction)

    @MainActor
    func test_verifiedCarrier_isSelectable_otherIsDisabled() {
        let vc = makeSheet()
        let rows = carrierRows(vc)
        XCTAssertEqual(rows.count, 6, "Cell instances must exist for all 6 carriers")

        // Acme is at index 0 (verified); Chameleon is at index 5 (flagged).
        let acme = rows[0]
        let chameleon = rows[5]

        XCTAssertTrue(acme.isUserInteractionEnabled, "Verified row MUST be interactive")
        XCTAssertFalse(chameleon.isUserInteractionEnabled, "Flagged row MUST be non-interactive (D-08)")
        XCTAssertEqual(acme.contentView.alpha, 1.0, accuracy: 0.001, "Verified row contentView alpha = 1.0")
        XCTAssertEqual(chameleon.contentView.alpha, 0.6, accuracy: 0.001, "Disabled row contentView alpha = 0.6 (UI-SPEC line 446)")
        XCTAssertEqual(chameleon.badgeViewForTesting.alpha, 1.0, accuracy: 0.001, "Disabled row's badge MUST stay at full alpha — the badge is the SIGNAL (UI-SPEC line 446)")
    }

    // MARK: - Test 3 — disabled reason copy

    @MainActor
    func test_disabledCarrier_inlineReason_matchesVerificationState() {
        let vc = makeSheet()
        let rows = carrierRows(vc)

        // Acme (.verified) — reason hidden
        XCTAssertTrue(rows[0].reasonLabelForTesting.isHidden,
                      "Verified row reason label hidden (no disabled copy)")
        // Cascadia (.pending) — pending copy
        XCTAssertFalse(rows[2].reasonLabelForTesting.isHidden,
                       "Pending row reason label visible")
        XCTAssertEqual(rows[2].reasonLabelForTesting.text,
                       "Verification pending — cannot tender",
                       "Pending copy matches loads.detail.tender.carrier.disabled.pending")
        // Anonymous (.unverified)
        XCTAssertEqual(rows[4].reasonLabelForTesting.text,
                       "Not verified — cannot tender",
                       "Unverified copy matches loads.detail.tender.carrier.disabled.unverified")
        // Chameleon (.flagged)
        XCTAssertEqual(rows[5].reasonLabelForTesting.text,
                       "Flagged — cannot tender",
                       "Flagged copy matches loads.detail.tender.carrier.disabled.flagged")
    }

    // MARK: - Test 4 — Send initially disabled + no-carrier helper

    @MainActor
    func test_sendButton_initiallyDisabled_noCarrierSelected() {
        let vc = makeSheet()
        XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                       "Send must be disabled on init (no carrier selected)")
        // Pitfall 8 — helper is fixed-height; visible via alpha = 1.
        XCTAssertEqual(vc.helperLabelForTesting.alpha, 1.0, accuracy: 0.001,
                       "Helper line visible when Send disabled")
        XCTAssertEqual(vc.helperLabelForTesting.text, "Pick a carrier to send.",
                       "loads.detail.tender.helper.no_carrier copy")
    }

    // MARK: - Test 5 — selecting verified carrier enables Send

    @MainActor
    func test_selectingVerifiedCarrier_enablesSend() {
        let vc = makeSheet()
        // Programmatic row selection at index 0 (Acme — verified).
        vc.selectCarrierForTesting(at: 0)
        XCTAssertTrue(vc.sendButtonForTesting.isEnabled,
                      "Send becomes enabled after picking a verified carrier (default 1-day deadline is in the future)")
        // Pitfall 8 — helper toggles via alpha, not isHidden.
        XCTAssertEqual(vc.helperLabelForTesting.alpha, 0.0, accuracy: 0.001,
                       "Helper alpha=0 when Send is enabled (Pitfall 8 fixed-height + alpha toggle)")
        XCTAssertFalse(vc.helperLabelForTesting.isHidden,
                       "Helper MUST remain non-hidden (alpha-only toggle keeps layout stable)")
    }

    // MARK: - Test 6 — past deadline gate

    @MainActor
    func test_sendButton_helperCopy_pastDeadlineGate() {
        let vc = makeSheet()
        vc.selectCarrierForTesting(at: 0)
        vc.setCustomDeadlineForTesting(pastDate())
        XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                       "Send disabled when deadline is in the past")
        XCTAssertEqual(vc.helperLabelForTesting.alpha, 1.0, accuracy: 0.001,
                       "Helper visible when Send disabled")
        XCTAssertEqual(vc.helperLabelForTesting.text, "Pick a future deadline.",
                       "loads.detail.tender.helper.past_deadline copy")
    }

    // MARK: - Test 7 — 5 chips; "1 day" initially selected

    @MainActor
    func test_deadlineChips_renderFive_oneDayDefault() {
        let vc = makeSheet()
        let chips = vc.deadlineChipsForTesting
        XCTAssertEqual(chips.count, 5, "Exactly 5 deadline chips per UI-SPEC line 447")
        let titles = chips.compactMap { $0.configuration?.title ?? $0.titleLabel?.text }
        XCTAssertEqual(titles, ["1 hour", "4 hours", "1 day", "2 days", "Custom…"],
                       "Locked chip titles in order (UI-SPEC line 447 + Plan 06 interfaces)")
        // The "1 day" chip (index 2) is the default-selected one.
        XCTAssertEqual(vc.selectedChipIndexForTesting, 2,
                       "Default selection is '1 day' (UI-SPEC line 447)")
    }

    // MARK: - Test 8 — chip tap updates resolved-time line

    @MainActor
    func test_chipTap_updatesResolvedTimeLine() {
        let vc = makeSheet()
        // Tap the "4 hours" chip (index 1).
        vc.tapChipForTesting(at: 1)
        let expected = LoadActionsView.RespondByFormatter.format(
            Date(timeIntervalSinceNow: 4 * 3600))
        // The resolved-time label format is "↳ <formatted>"; just assert it
        // CONTAINS the formatted body (substring match is robust against the
        // tiny seconds-of-drift between the chip tap and the test's
        // recomputation of "4 hours from now").
        // We assert a partial-time match: the formatted time-of-day is
        // deterministic at minute precision under the project test runner.
        let resolved = vc.resolvedTimeLabelForTesting.text ?? ""
        XCTAssertTrue(resolved.hasPrefix("↳ "),
                      "Resolved-time line uses locked '↳ %@' format (loads.detail.tender.deadline.resolved.format)")
        // The minute portion of the formatted expectation will match if we
        // are within the same minute, which is reliable for the +4h test.
        let minuteMatch = String(expected.prefix(4))  // e.g. "5:00" or "5:30"
        XCTAssertTrue(resolved.contains(minuteMatch),
                      "Resolved-time line contains the formatted 4-hour-future minute-of-day. resolved=\(resolved) expected fragment=\(minuteMatch)")
    }

    // MARK: - Test 9 — Custom… chip reveals UIDatePicker

    @MainActor
    func test_customChip_revealsDatePicker() {
        let vc = makeSheet()
        XCTAssertTrue(vc.datePickerForTesting.isHidden,
                      "Date picker hidden before Custom… tap")
        // Tap the "Custom…" chip (index 4).
        vc.tapChipForTesting(at: 4)
        XCTAssertFalse(vc.datePickerForTesting.isHidden,
                       "Date picker revealed below the chip row when Custom… selected (UI-SPEC line 449)")
    }

    // MARK: - Test 10 — onSend invoked with correct request body

    @MainActor
    func test_onSendClosure_invokedWithCorrectRequestBody() async throws {
        var capturedID: String?
        var capturedDate: Date?
        let exp = expectation(description: "onSend invoked")
        let vc = makeSheet(onSend: { partyID, deadline in
            capturedID = partyID
            capturedDate = deadline
            exp.fulfill()
        })
        vc.selectCarrierForTesting(at: 0)  // Acme
        // Capture the resolved deadline before the tap.
        let expectedDeadline = vc.resolvedDeadlineForTesting
        vc.tapSendForTesting()
        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertEqual(capturedID, "party-carrier-acme",
                       "onSend called with selected carrier's partyID")
        if let actual = capturedDate {
            XCTAssertEqual(actual.timeIntervalSince1970,
                           expectedDeadline.timeIntervalSince1970,
                           accuracy: 0.5,
                           "onSend called with the resolved deadline date")
        } else {
            XCTFail("onSend deadline not captured")
        }
    }

    // MARK: - Test 11 — sheet stays visible during in-flight onSend

    @MainActor
    func test_onSend_keepsSheetVisibleDuringInFlight() async throws {
        let started = expectation(description: "onSend entered")
        let resumeContinuation = expectation(description: "test signals onSend to complete")
        let vc = makeSheet(onSend: { _, _ in
            started.fulfill()
            // Suspend briefly so the test can observe the in-flight state.
            try? await Task.sleep(nanoseconds: 200_000_000)
            resumeContinuation.fulfill()
        })
        vc.selectCarrierForTesting(at: 0)
        XCTAssertNotNil(vc.view.window, "Sheet's view is in a window before tap")

        vc.tapSendForTesting()
        await fulfillment(of: [started], timeout: 2.0)
        // While onSend is awaiting, the sheet stays presented + the Send
        // button shows the spinner + is disabled.
        XCTAssertNotNil(vc.view.window,
                        "Sheet stays visible during in-flight onSend (UI-SPEC line 454)")
        XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                       "Send disabled during in-flight (double-submit safety)")
        XCTAssertTrue(vc.sendButtonForTesting.configuration?.showsActivityIndicator ?? false,
                      "Send button shows spinner during in-flight")
        await fulfillment(of: [resumeContinuation], timeout: 2.0)
    }

    // MARK: - Test 12 — onCancel invoked on cancel tap

    @MainActor
    func test_onCancelClosure_invokedOnCancelTap() {
        var cancelled = false
        let vc = makeSheet(onCancel: { cancelled = true })
        vc.tapCancelForTesting()
        XCTAssertTrue(cancelled, "onCancel invoked when nav-bar Cancel tapped")
    }

    // MARK: - Test 13 — helper toggles via alpha (NOT isHidden) — fixed height preserved

    @MainActor
    func test_sheetHelperLine_alphaToggleNotIsHidden() {
        let vc = makeSheet()
        vc.view.layoutIfNeeded()
        let heightBefore = vc.helperLabelForTesting.frame.height
        XCTAssertGreaterThan(heightBefore, 0,
                             "Helper label has non-zero height before selection (visible state)")
        // Now pick a verified carrier — helper alpha goes to 0 but height stays.
        vc.selectCarrierForTesting(at: 0)
        vc.view.layoutIfNeeded()
        let heightAfter = vc.helperLabelForTesting.frame.height
        XCTAssertEqual(heightAfter, heightBefore, accuracy: 0.5,
                       "Helper label fixed-height — alpha toggle does NOT change height (Pitfall 8)")
        XCTAssertFalse(vc.helperLabelForTesting.isHidden,
                       "Helper MUST never be isHidden — alpha-only toggle so the detent does not reflow")
    }

    // MARK: - Test 14 — empty directory => Send permanently disabled

    @MainActor
    func test_emptyDirectory_sendButton_permanentlyDisabled() {
        let vc = makeSheet(directory: [])
        XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                       "Empty directory => Send disabled")
        XCTAssertEqual(vc.helperLabelForTesting.text, "Pick a carrier to send.",
                       "no_carrier helper copy")
    }

    // MARK: - Test 15 — directory without any .verified carriers => Send permanently disabled

    @MainActor
    func test_directoryWithNoVerifiedCarriers_sendButton_permanentlyDisabled() {
        let all = makeStandardDirectory()
        // Drop the two .verified carriers (Acme + Northwind).
        let onlyDisabled = Array(all.dropFirst(2))
        let vc = makeSheet(directory: onlyDisabled)
        // Try to tap each row programmatically — none of them is selectable.
        for index in 0..<onlyDisabled.count {
            vc.selectCarrierForTesting(at: index)
            XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                           "Send MUST stay disabled when only unverified/flagged/pending carriers exist (carrier-level ACTION-04 gate) — failed at index \(index)")
        }
    }

    // MARK: - Test 16 — CR-01 defense-in-depth — handleSendTap refuses to
    // fire onSend for a non-verified carrier even if `selectedCarrierIndex`
    // is forced into a non-verified row via a programmatic seam that
    // bypasses the row-level and delegate-level gates.

    @MainActor
    func test_handleSendTap_refusesNonVerifiedCarrier_defenseInDepth() async throws {
        // The standard directory's index 5 is Chameleon (.flagged); index 4
        // is Anonymous (.unverified); index 2/3 are Cascadia/Summit
        // (.pending). NONE of these may produce an onSend call from
        // handleSendTap regardless of selectedCarrierIndex's value.
        var onSendCalled = false
        let vc = makeSheet(onSend: { _, _ in
            onSendCalled = true
        })

        // Force the model into the dangerous state: selectedCarrierIndex
        // points at a non-verified row. Real user UI cannot reach this
        // state (cell isUserInteractionEnabled = false; delegate guards),
        // but a future bug, voice-control edge, or programmatic test path
        // could. The defense-in-depth guard in handleSendTap MUST hold.
        for (index, label) in [(2, "pending"), (3, "pending"),
                               (4, "unverified"), (5, "flagged")] {
            vc.forceSelectedCarrierIndexForTesting(index)
            vc.tapSendForTesting()
            // Give any (incorrectly-fired) async onSend a chance to run.
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertFalse(onSendCalled,
                           "T-10-04 CRITICAL: handleSendTap MUST NOT fire onSend for a \(label) carrier (index \(index)) even when selectedCarrierIndex is forced past the surface gates — defense-in-depth.")
            XCTAssertFalse(vc.sendButtonForTesting.isEnabled,
                           "Send button MUST be re-disabled after the defense-in-depth guard rejects the tap at index \(index).")
        }
    }
}
