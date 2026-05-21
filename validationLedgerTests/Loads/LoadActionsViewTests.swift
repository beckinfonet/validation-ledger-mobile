// validationLedgerTests/Loads/LoadActionsViewTests.swift
// Phase 10 Plan 04 Task 1 — unit tests for `LoadActionsView` (NEW).
//
// === Why XCTest (not Swift Testing) ===
// Matches the Wave 1/2/3 XCTest neighbors in this folder. Running
// -only-testing against XCTest + Swift Testing in a single invocation has
// known issues (project memory: ios-test-suite-pitfalls).
//
// === -only-testing canonical form ===
// `xcodebuild test -only-testing:validationLedgerTests/LoadActionsViewTests`
// — class-name only, NO folder segment. Per Plan 02/03 deviation notes.
//
// === Test scope ===
// 18 tests covering the configure-method contract per Plan 04 Task 1
// <behavior>:
//   - Test 1  : broker on .posted -> [.tender, .cancel] -> 2 buttons, titles
//   - Test 2  : carrier on .tendered -> [.accept, .reject] -> blue/red colors
//   - Test 3  : carrier on .accepted -> [.advanceStatus] -> "Dispatch" title
//   - Test 4  : empty actions, role .factoring -> factoring caption
//   - Test 5  : empty actions, terminal status -> interpolated caption
//   - Test 6  : empty actions, .inTransit -> "in transit" (Pitfall 5)
//   - Test 7  : tenderEligibility.canTender == false + reason -> disabled+inline
//   - Test 8  : tenderEligibility.canTender == false + nil reason -> generic
//   - Test 9  : in-flight -> tapped shows spinner, others disabled
//   - Test 10 : in-flight uses pre-tap action set (Pitfall 6)
//   - Test 11 : carrier respond-by future date -> labelSecondary
//   - Test 12 : carrier respond-by past date -> destructive
//   - Test 13 : broker on .tendered -> respond-by absent
//   - Test 14 : empty actions -> respond-by absent
//   - Test 15 : Dynamic Type accessibilityLarge -> vertical axis
//   - Test 16 : accessibility elements in tap order
//   - Test 17 : onTap closure called with correct action
//   - Test 18 : single action -> 2-cell stack with spacer

import XCTest
@testable import validationLedger

final class LoadActionsViewTests: XCTestCase {

    private var view: LoadActionsView!

    override func setUp() {
        super.setUp()
        view = LoadActionsView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
    }

    override func tearDown() {
        view = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// All visible UIButton subviews currently in the action region's button row.
    private func visibleButtons() -> [UIButton] {
        var out: [UIButton] = []
        func walk(_ v: UIView) {
            if let b = v as? UIButton, !b.isHidden { out.append(b) }
            for child in v.subviews { walk(child) }
        }
        walk(view)
        return out
    }

    /// All UILabels in the action region (visible AND hidden — caller filters).
    private func allLabels() -> [UILabel] {
        var out: [UILabel] = []
        func walk(_ v: UIView) {
            if let l = v as? UILabel { out.append(l) }
            for child in v.subviews { walk(child) }
        }
        walk(view)
        return out
    }

    /// Visible UILabels in the action region.
    private func visibleLabels() -> [UILabel] {
        allLabels().filter { !$0.isHidden }
    }

    /// Future date helper (1 hour from now).
    private func futureDate() -> Date { Date(timeIntervalSinceNow: 3600) }

    /// Past date helper (1 hour ago).
    private func pastDate() -> Date { Date(timeIntervalSinceNow: -3600) }

    /// Find the button whose title matches the resolved title for `action`.
    private func button(for action: LoadAction, currentStatus: LoadStatus) -> UIButton? {
        let title = LoadActionTitleResolver.title(for: action, currentStatus: currentStatus)
        return visibleButtons().first { $0.configuration?.title == title || $0.titleLabel?.text == title }
    }

    /// Find the empty-state caption label by accessibility identifier.
    private func emptyCaptionLabel() -> UILabel? {
        allLabels().first { $0.accessibilityIdentifier == "load-detail.actions.empty-caption" }
    }

    /// Find the disabled-reason inline label by accessibility identifier.
    private func disabledReasonLabel() -> UILabel? {
        allLabels().first { $0.accessibilityIdentifier == "load-detail.actions.disabled-reason" }
    }

    /// Find the respond-by label by accessibility identifier.
    private func respondByLabel() -> UILabel? {
        allLabels().first { $0.accessibilityIdentifier == "load-detail.actions.respond-by" }
    }

    // MARK: - Test 1 — broker on .posted -> 2 buttons (Tender + Cancel)

    func test_configure_brokerOnPosted_rendersTwoButtons() {
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let buttons = visibleButtons()
        XCTAssertEqual(buttons.count, 2, "Broker on .posted should render 2 buttons")
        XCTAssertEqual(buttons[0].configuration?.title, "Tender")
        XCTAssertEqual(buttons[1].configuration?.title, "Cancel load")
        XCTAssertTrue(emptyCaptionLabel()?.isHidden ?? true, "Caption must be hidden")
    }

    // MARK: - Test 2 — carrier on .tendered -> Accept (blue) + Reject (red)

    func test_configure_carrierOnTendered_acceptIsBlueRejectIsRed() {
        view.configure(
            actions: [.accept, .reject],
            role: .carrier,
            currentStatus: .tendered,
            tenderEligibility: nil,
            respondByAt: futureDate(),
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let buttons = visibleButtons()
        XCTAssertEqual(buttons.count, 2, "Carrier on .tendered should render 2 buttons")
        XCTAssertEqual(buttons[0].configuration?.baseBackgroundColor, DS.Colors.primary,
                       "Accept button should be primary (blue)")
        XCTAssertEqual(buttons[1].configuration?.baseBackgroundColor, DS.Colors.destructive,
                       "Reject button should be destructive (red)")
        // Respond-by label visible since role is carrier, status is .tendered, and respondByAt != nil
        XCTAssertFalse(respondByLabel()?.isHidden ?? true, "Respond-by label should be visible")
    }

    // MARK: - Test 3 — carrier .accepted -> .advanceStatus title is "Dispatch"

    func test_configure_carrierOnAccepted_advanceStatusTitle_isDispatch() {
        view.configure(
            actions: [.advanceStatus],
            role: .carrier,
            currentStatus: .accepted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let buttons = visibleButtons()
        XCTAssertEqual(buttons.count, 1, "One real advance button rendered")
        XCTAssertEqual(buttons[0].configuration?.title, "Dispatch",
                       "advanceStatus on .accepted -> 'Dispatch' per UI-SPEC line 278")
    }

    // MARK: - Test 4 — empty actions, role .factoring -> factoring caption

    func test_configure_emptyActions_factoring_rendersFactoringCaption() {
        view.configure(
            actions: [],
            role: .factoring,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        XCTAssertTrue(visibleButtons().isEmpty, "No buttons rendered when actions==[]")
        let caption = emptyCaptionLabel()
        XCTAssertNotNil(caption, "Caption label must exist")
        XCTAssertFalse(caption?.isHidden ?? true, "Caption visible for empty actions")
        XCTAssertEqual(caption?.text, "This is a view-only role. No actions available.",
                       "Factoring caption per UI-SPEC line 303")
    }

    // MARK: - Test 5 — empty actions, terminal status -> interpolated caption

    func test_configure_emptyActions_terminal_rendersInterpolatedCaption() {
        view.configure(
            actions: [],
            role: .broker,
            currentStatus: .delivered,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let caption = emptyCaptionLabel()
        XCTAssertEqual(caption?.text, "This load is delivered. No actions available.",
                       "Terminal caption per UI-SPEC line 304 with localizedDisplayName interpolation")
    }

    // MARK: - Test 6 — Pitfall 5 explicit guard — .inTransit must surface "in transit" (with space, not underscore)

    func test_configure_emptyActions_terminal_inTransitDisplayName_hasNoUnderscore() {
        view.configure(
            actions: [],
            role: .broker,
            currentStatus: .inTransit,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let caption = emptyCaptionLabel()
        XCTAssertNotNil(caption?.text)
        XCTAssertTrue(caption?.text?.contains("in transit") ?? false,
                      "Caption must use 'in transit' with space (Pitfall 5)")
        XCTAssertFalse(caption?.text?.contains("in_transit") ?? true,
                       "Caption must NOT contain 'in_transit' underscore (Pitfall 5)")
    }

    // MARK: - Test 7 — tenderEligibility.canTender == false + reason -> disabled + inline

    func test_configure_tenderEligibilityCanTenderFalse_tenderDisabled_withInlineReason() throws {
        let elig = try eligibility(
            canTender: false,
            reason: "Counterparty USDOT authority suspended"
        )
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: elig,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let tender = button(for: .tender, currentStatus: .posted)
        let cancelBtn = button(for: .cancel, currentStatus: .posted)
        XCTAssertNotNil(tender)
        XCTAssertNotNil(cancelBtn)
        XCTAssertFalse(tender?.isEnabled ?? true, "Tender disabled per canTender=false")
        XCTAssertTrue(cancelBtn?.isEnabled ?? false, "Cancel NOT gated by tenderEligibility")

        let reason = disabledReasonLabel()
        XCTAssertFalse(reason?.isHidden ?? true, "Inline reason visible")
        XCTAssertEqual(reason?.text, "Counterparty USDOT authority suspended",
                       "Server-supplied reason rendered verbatim (UI-SPEC line 290)")
    }

    // MARK: - Test 8 — tenderEligibility.canTender == false + nil reason -> generic fallback

    func test_configure_tenderEligibilityCanTenderFalse_nilReason_rendersGenericFallback() throws {
        let elig = try eligibility(canTender: false, reason: nil)
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: elig,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let reason = disabledReasonLabel()
        XCTAssertFalse(reason?.isHidden ?? true)
        XCTAssertEqual(reason?.text, "Tender unavailable",
                       "Generic fallback per loads.actions.tender.disabled.generic")
    }

    // MARK: - Test 9 — in-flight: tapped shows spinner, others disabled

    func test_configure_inFlight_otherButtonsDisabled_tappedButtonShowsSpinner() {
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: .tender,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let tender = button(for: .tender, currentStatus: .posted)
        let cancelBtn = button(for: .cancel, currentStatus: .posted)
        XCTAssertFalse(tender?.isEnabled ?? true, "Tapped Tender button disabled mid-flight")
        XCTAssertFalse(cancelBtn?.isEnabled ?? true, "Non-tapped Cancel button disabled mid-flight")
        // Spinner: configuration.showsActivityIndicator OR an activity indicator subview
        let tenderShowsSpinner = (tender?.configuration?.showsActivityIndicator ?? false)
            || ((tender?.subviews.contains { $0 is UIActivityIndicatorView }) ?? false)
        XCTAssertTrue(tenderShowsSpinner, "Tapped Tender button shows spinner")
    }

    // MARK: - Test 10 — Pitfall 6 — in-flight renders pre-tap action set

    func test_configure_inFlight_actionsList_isPreTapList_pitfall6() {
        view.configure(
            actions: [.tender, .cancel],  // pre-tap action set
            role: .broker,
            currentStatus: .tendered,     // predicted post-tap status
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: .tender,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let buttons = visibleButtons()
        XCTAssertEqual(buttons.count, 2,
                       "Pitfall 6: actions[] argument is the source of truth — pre-tap [.tender, .cancel] survives")
        let titles = buttons.compactMap { $0.configuration?.title }
        XCTAssertTrue(titles.contains("Tender"), "Tender button present in-flight")
        XCTAssertTrue(titles.contains("Cancel load"), "Cancel button present in-flight")
    }

    // MARK: - Test 11 — carrier respond-by future date -> labelSecondary

    func test_configure_carrierOnTendered_respondByLabel_visibleWithFutureDate() {
        view.configure(
            actions: [.accept, .reject],
            role: .carrier,
            currentStatus: .tendered,
            tenderEligibility: nil,
            respondByAt: futureDate(),
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let label = respondByLabel()
        XCTAssertFalse(label?.isHidden ?? true, "Respond-by label visible")
        XCTAssertTrue(label?.text?.contains("Respond by") ?? false,
                      "Respond-by text contains 'Respond by'")
        XCTAssertEqual(label?.textColor, DS.Colors.labelSecondary,
                       "Future date uses labelSecondary (not destructive)")
    }

    // MARK: - Test 12 — carrier respond-by past date -> destructive

    func test_configure_carrierOnTendered_respondByLabel_pastDateIsDestructive() {
        view.configure(
            actions: [.accept, .reject],
            role: .carrier,
            currentStatus: .tendered,
            tenderEligibility: nil,
            respondByAt: pastDate(),
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let label = respondByLabel()
        XCTAssertFalse(label?.isHidden ?? true)
        XCTAssertEqual(label?.textColor, DS.Colors.destructive,
                       "Past-due date uses destructive color")
        XCTAssertTrue(label?.text?.contains("Past due") ?? false,
                      "Past-due copy contains 'Past due'")
    }

    // MARK: - Test 13 — broker on .tendered -> respond-by absent

    func test_configure_brokerOnTendered_respondByLabel_absent() {
        view.configure(
            actions: [.cancel],
            role: .broker,
            currentStatus: .tendered,
            tenderEligibility: nil,
            respondByAt: futureDate(),
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let label = respondByLabel()
        XCTAssertTrue(label?.isHidden ?? false,
                      "Respond-by hidden for broker (UI-SPEC line 335)")
    }

    // MARK: - Test 14 — empty actions -> respond-by absent

    func test_configure_emptyActions_respondByLabel_absent() {
        view.configure(
            actions: [],
            role: .carrier,
            currentStatus: .tendered,
            tenderEligibility: nil,
            respondByAt: futureDate(),
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let label = respondByLabel()
        XCTAssertTrue(label?.isHidden ?? false,
                      "Respond-by hidden when caption takes over")
    }

    // MARK: - Test 15 — Dynamic Type accessibilityLarge -> vertical axis

    func test_configure_DynamicTypeAccessibilityCategory_buttonRowAxis_flipsToVertical() {
        // Embed in a window so traitOverrides actually propagates into the
        // view's traitCollection (off-window views don't always pick up
        // traitOverrides changes — iOS 17 `registerForTraitChanges` requires
        // the view be in a window hierarchy to fire).
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)
        window.makeKeyAndVisible()

        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )

        // Apply accessibility-large trait via traitOverrides on both the view
        // and the window for correct propagation.
        view.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        window.traitOverrides.preferredContentSizeCategory = .accessibilityLarge

        // Trigger trait change handling
        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertEqual(view.buttonRowAxisForTesting, .vertical,
                       "Button row axis flips to vertical at accessibility category (UI-SPEC line 419)")
    }

    // MARK: - Test 16 — accessibility elements in tap order

    func test_configure_setsAccessibilityElements_inTapOrder() {
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        let elements = view.accessibilityElements ?? []
        XCTAssertGreaterThanOrEqual(elements.count, 2,
                                     "At least 2 buttons should be in accessibilityElements")
        let buttons = visibleButtons()
        // First element should be Tender (the first button); second Cancel
        XCTAssertTrue(elements[0] as? UIButton === buttons[0],
                      "First accessibility element is Tender button")
        XCTAssertTrue(elements[1] as? UIButton === buttons[1],
                      "Second accessibility element is Cancel button")
        XCTAssertEqual(buttons[0].accessibilityLabel, "Tender",
                       "Button's accessibilityLabel is the title")
        XCTAssertEqual(buttons[1].accessibilityLabel, "Cancel load")
    }

    // MARK: - Test 17 — onTap closure called with correct action

    func test_configure_onTapClosure_calledWithCorrectAction() {
        var captured: LoadAction?
        view.configure(
            actions: [.tender, .cancel],
            role: .broker,
            currentStatus: .posted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { action in captured = action }
        )
        view.layoutIfNeeded()

        let tender = button(for: .tender, currentStatus: .posted)
        XCTAssertNotNil(tender)
        tender?.sendActions(for: .touchUpInside)
        XCTAssertEqual(captured, .tender, "onTap fired with .tender")
    }

    // MARK: - Test 18 — single action -> 2-cell stack with invisible spacer

    func test_configure_singleAction_rendersInTwoCellStackWithSpacer() {
        view.configure(
            actions: [.advanceStatus],
            role: .carrier,
            currentStatus: .accepted,
            tenderEligibility: nil,
            respondByAt: nil,
            inFlight: nil,
            onTap: { _ in }
        )
        view.layoutIfNeeded()

        XCTAssertEqual(view.buttonRowArrangedSubviewCountForTesting, 2,
                       "Single action lives in a 2-cell stack with an invisible spacer (UI-SPEC line 417)")
        // Exactly one real button visible
        XCTAssertEqual(visibleButtons().count, 1)
    }

    // MARK: - Eligibility fixture builder

    /// Builds a TenderEligibility via JSON (TenderEligibility has no public init).
    private func eligibility(canTender: Bool, reason: String?) throws -> TenderEligibility {
        let reasonJSON: String = {
            if let r = reason { return ",\n  \"disabled_reason\": \"\(r)\"" }
            return ""
        }()
        let json = """
        {
          "can_tender": \(canTender)\(reasonJSON)
        }
        """
        return try APIClient.defaultDecoder().decode(TenderEligibility.self, from: Data(json.utf8))
    }
}
