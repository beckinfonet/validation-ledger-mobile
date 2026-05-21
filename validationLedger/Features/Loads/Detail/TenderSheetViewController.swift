// validationLedger/Features/Loads/Detail/TenderSheetViewController.swift
//
// Phase 10 Plan 06 — TenderSheetViewController (D-06 / D-08 / D-09 / D-10 /
// D-11 + ACTION-04 carrier-level gate; T-10-04 CRITICAL platform thesis).
//
// === What this is ===
// The modal sheet content view-controller fired by `LoadDetailViewController.
// presentTenderSheet()` (Plan 04 stub → Plan 06 real). Presented via
// `UISheetPresentationController` `.medium` detent (`.large` available);
// `largestUndimmedDetentIdentifier = .medium`; `prefersGrabberVisible = true`.
// Sheet presentation lives on the PRESENTING side (LoadDetailViewController);
// this content VC is presentation-agnostic.
//
// === Sheet presentation 7-line recipe (Pitfall 7 LOCK — do NOT refactor) ===
// The verbatim 7-line block Phase 9 established (VerificationBasisSheetVC +
// HandoffDetailSheetVC). The block is INLINED at the call site
// (`LoadDetailViewController.presentTenderSheet(directory:)`), NOT factored
// into a helper. Drift to "factor into helper" reduces the grep count and
// trips T-10-PR-01 invariant.
//
// === Carrier-level ACTION-04 gate (CRITICAL — T-10-04 platform thesis) ===
// Per D-08 + UI-SPEC line 446: unverified/flagged/pending carriers stay
// VISIBLE-BUT-DISABLED in the picker with an inline reason ("Flagged —
// cannot tender" etc.). The badge stays at full alpha (UI-SPEC line 446);
// the contentView dims to 0.6; userInteractionEnabled = false. Hiding the
// disabled rows is the wrong choice — the broker SEES the fraud signal.
//
// === Three-condition Send-button gate (D-11 / UI-SPEC line 453) ===
//   isEnabled = (selectedCarrier != nil
//               && selectedCarrier.verificationState == .verified
//               && resolvedDeadline > Date())
// Helper line below Send explains which gate is closed (per UI-SPEC line
// 371-373 LOCKED copy):
//   - no_carrier         : "Pick a carrier to send."
//   - unverified_carrier : "Pick a verified carrier." (defensive — D-08
//                          should prevent this, belt-and-suspenders)
//   - past_deadline      : "Pick a future deadline."
//
// === Pitfall 8 — helper line FIXED HEIGHT + alpha 0/1 toggle ===
// The Send-button helper label uses a fixed-height label with alpha
// toggling — NOT isHidden — so the sheet detent does not REFLOW when the
// user picks a carrier. Test 13 of TenderSheetViewControllerTests is the
// regression guard.
//
// === Closure shape (Open Question 4 resolution) ===
//   onSend:   (_ targetPartyID: String, _ respondByAt: Date) async -> Void
//   onCancel: () -> Void
// The sheet does NOT know the role — the parent VC composes the full
// RequestBody when its closure fires (so the same sheet works for shipper
// and broker without modification). On Send the sheet awaits onSend; the
// parent dismisses the sheet on 200 from its `.loaded` render path. On
// failure the parent keeps the sheet visible; the toast slides in OVER
// the parent (largestUndimmedDetentIdentifier = .medium keeps parent
// interactive).
//
// === Accessibility identifiers (ISSUE-04 fix — Plan 10-10 contract) ===
//   - root view: `load-detail.tender-sheet`
//   - carrier row: `load-detail.tender-sheet/carrier-row.<partyID>`
//   - deadline chip: `load-detail.tender-sheet/deadline-chip.<token>`
//       (token ∈ "1h" | "4h" | "24h" | "48h" | "custom")
//   - send button: `load-detail.tender-sheet/send-button`
//
// === Threat-model anchors ===
//   - T-10-04 (CRITICAL): carrier-level ACTION-04 gate. The picker filters
//     by `.verified` for selectability + Send button enable. Server is
//     canonical (Phase 7 D-18); client is defense-in-depth.
//   - T-10-PR-01: Pitfall 7 — sheet 7-line recipe INLINED at the call site.
//     Drift to "factor into helper" trips the grep count >= 3 invariant.
//   - T-10-PR-02: Pitfall 8 — Send helper line is FIXED-HEIGHT + alpha 0/1.
//   - T-09-04 view-layer lock: this file has ZERO Logger / os_log / OSLog
//     calls. Server error text from the directory fetch is suppressed by
//     the parent VC; the sheet renders no server-supplied error copy.

import UIKit

final class TenderSheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Closures (Open Question 4 resolution)

    /// Awaited by the Send tap. Parent VC composes the full RequestBody
    /// (with actorRole) and calls `viewModel.submit(...)`. Sheet stays
    /// visible during the await (UI-SPEC line 454); parent dismisses on
    /// 200 success.
    private let onSend: @MainActor (_ targetPartyID: String, _ respondByAt: Date) async -> Void

    /// Invoked when the nav-bar Cancel button is tapped. Parent dismisses.
    private let onCancel: () -> Void

    // MARK: - Stored

    private let directory: [TrustNode]

    // MARK: - Internal state

    /// Index of the selected carrier in the directory; nil when no row is
    /// picked yet OR when the user picks a disabled row (defensive — D-08
    /// userInteractionEnabled=false prevents that path).
    private var selectedCarrierIndex: Int?

    /// The currently-active deadline preset (or .custom carrying a Date).
    private enum SelectedDeadline {
        case preset(TimeInterval)    // 1h / 4h / 24h / 48h (offsets from now)
        case custom(Date)
    }
    private var selectedDeadline: SelectedDeadline = .preset(24 * 3600)  // default: 1 day

    /// The 5 chip tokens / titles / interval mapping (UI-SPEC line 447).
    private struct ChipDescriptor {
        let token: String  // "1h" | "4h" | "24h" | "48h" | "custom"
        let title: String
        let interval: TimeInterval?  // nil for "custom"
    }
    private let chipDescriptors: [ChipDescriptor] = [
        .init(token: "1h",     title: NSLocalizedString("loads.detail.tender.deadline.chip.1h",     value: "1 hour",  comment: "Tender sheet deadline preset chip — 1 hour (UI-SPEC line 363)"),  interval: 3600),
        .init(token: "4h",     title: NSLocalizedString("loads.detail.tender.deadline.chip.4h",     value: "4 hours", comment: "Tender sheet deadline preset chip — 4 hours (UI-SPEC line 364)"), interval: 4 * 3600),
        .init(token: "24h",    title: NSLocalizedString("loads.detail.tender.deadline.chip.24h",    value: "1 day",   comment: "Tender sheet deadline preset chip — 24 hours / 1 day (UI-SPEC line 365)"), interval: 24 * 3600),
        .init(token: "48h",    title: NSLocalizedString("loads.detail.tender.deadline.chip.48h",    value: "2 days",  comment: "Tender sheet deadline preset chip — 48 hours / 2 days (UI-SPEC line 366)"), interval: 48 * 3600),
        .init(token: "custom", title: NSLocalizedString("loads.detail.tender.deadline.chip.custom", value: "Custom…", comment: "Tender sheet deadline preset chip — custom date+time picker reveal (UI-SPEC line 367)"), interval: nil),
    ]

    /// Currently-selected chip index (0-4). Default 2 = "1 day" (UI-SPEC line 447).
    private var selectedChipIndex: Int = 2

    // MARK: - Subviews

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = DS.Spacing.md
        s.translatesAutoresizingMaskIntoConstraints = false
        s.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        s.isLayoutMarginsRelativeArrangement = true
        return s
    }()

    private let carrierSectionHeader: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "loads.detail.tender.section.carrier",
            value: "Carrier",
            comment: "Tender sheet — carrier section header (UI-SPEC line 361)"
        ).uppercased()
        return l
    }()

    private let deadlineSectionHeader: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "loads.detail.tender.section.deadline",
            value: "Respond by",
            comment: "Tender sheet — deadline section header (UI-SPEC line 362)"
        ).uppercased()
        return l
    }()

    private let tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .insetGrouped)
        t.estimatedRowHeight = 64
        t.rowHeight = UITableView.automaticDimension
        t.translatesAutoresizingMaskIntoConstraints = false
        t.isScrollEnabled = false  // the outer scrollView handles scrolling
        t.backgroundColor = .clear
        return t
    }()

    private let chipRow: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.alignment = .fill
        s.distribution = .fillEqually
        s.spacing = DS.Spacing.xs
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var chipButtons: [UIButton] = []

    private let datePicker: UIDatePicker = {
        let p = UIDatePicker()
        p.datePickerMode = .dateAndTime
        p.preferredDatePickerStyle = .compact
        p.isHidden = true
        p.translatesAutoresizingMaskIntoConstraints = false
        return p
    }()

    private let resolvedTimeLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let sendButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = NSLocalizedString(
            "loads.detail.tender.button.send",
            value: "Send tender",
            comment: "Tender sheet — Send primary CTA (UI-SPEC line 369)"
        )
        cfg.baseBackgroundColor = DS.Colors.primary
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        b.accessibilityIdentifier = "load-detail.tender-sheet/send-button"   // ISSUE-04 fix
        b.isEnabled = false
        return b
    }()

    /// Helper line BELOW the Send button. FIXED HEIGHT (Pitfall 8) so the
    /// detent does not reflow when its alpha toggles between 0 and 1.
    /// Never `isHidden = true`.
    private let helperLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)

    // MARK: - Init

    public init(
        directory: [TrustNode],
        onSend: @escaping @MainActor (_ targetPartyID: String, _ respondByAt: Date) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.directory = directory
        self.onSend = onSend
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("TenderSheetViewController is constructed programmatically only")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        view.accessibilityIdentifier = "load-detail.tender-sheet"  // ISSUE-04 fix

        installNavigationItem()
        installLayout()
        configureTableView()
        buildChipRow()
        updateResolvedTimeLine()
        updateSendButton()
    }

    private func installNavigationItem() {
        navigationItem.title = NSLocalizedString(
            "loads.detail.tender.sheet.title",
            value: "Send tender",
            comment: "Tender sheet — nav title (UI-SPEC line 360)"
        )
        cancelButton.target = self
        cancelButton.action = #selector(handleCancelTap)
        navigationItem.leftBarButtonItem = cancelButton
    }

    private func installLayout() {
        view.addSubview(scrollView)
        view.addSubview(sendButton)
        view.addSubview(helperLabel)
        scrollView.addSubview(contentStack)

        // Carrier section
        contentStack.addArrangedSubview(carrierSectionHeader)
        contentStack.addArrangedSubview(tableView)

        // Deadline section
        contentStack.addArrangedSubview(deadlineSectionHeader)
        contentStack.addArrangedSubview(chipRow)
        contentStack.addArrangedSubview(datePicker)
        contentStack.addArrangedSubview(resolvedTimeLabel)

        // Helper label fixed-height (Pitfall 8). We pin a constant height of
        // 18pt (single-line footnote default height) so alpha toggling does
        // NOT cause a layout pass to reflow the detent. `isHidden` is NEVER
        // toggled on this label.
        let helperHeight: CGFloat = 18

        NSLayoutConstraint.activate([
            // Scroll view fills above the Send button.
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -DS.Spacing.md),

            // Content stack — pin to scroll's content + width to frame.
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Send button pinned to safe-area bottom with helper below.
            sendButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DS.Spacing.md),
            sendButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DS.Spacing.md),
            sendButton.bottomAnchor.constraint(equalTo: helperLabel.topAnchor, constant: -DS.Spacing.xs),

            // Helper label — fixed height, alpha-toggled (Pitfall 8).
            helperLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DS.Spacing.md),
            helperLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DS.Spacing.md),
            helperLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DS.Spacing.md),
            helperLabel.heightAnchor.constraint(equalToConstant: helperHeight),

            // Carrier list: pin a sensible minimum height so the table actually
            // renders cells when the view layouts (the test layouts at 700pt
            // window height; we give the table room to materialize all rows).
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])

        // Table view height grows to fit content — let intrinsicContentSize
        // drive it. Disable scrolling so the outer scroll handles it.
        tableView.setContentCompressionResistancePriority(.required, for: .vertical)

        sendButton.addTarget(self, action: #selector(handleSendTap), for: .touchUpInside)
        datePicker.addTarget(self, action: #selector(handleDatePickerChanged), for: .valueChanged)
    }

    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TenderSheetCarrierRowView.self,
                           forCellReuseIdentifier: TenderSheetCarrierRowView.reuseIdentifier)
        // Layout the table so all rows materialize for in-test introspection.
        tableView.reloadData()
        tableView.layoutIfNeeded()
        // Re-size table to fit its content rather than scrolling internally —
        // the outer scrollView is the scroller.
        let contentH = tableView.contentSize.height
        if contentH > 0 {
            tableView.heightAnchor.constraint(equalToConstant: contentH).isActive = true
        }
    }

    private func buildChipRow() {
        chipButtons.removeAll()
        for (idx, descriptor) in chipDescriptors.enumerated() {
            let chip = makeChipButton(descriptor: descriptor, selected: idx == selectedChipIndex)
            chip.tag = idx
            chip.addTarget(self, action: #selector(handleChipTap(_:)), for: .touchUpInside)
            chipRow.addArrangedSubview(chip)
            chipButtons.append(chip)
        }
    }

    private func makeChipButton(descriptor: ChipDescriptor, selected: Bool) -> UIButton {
        var cfg: UIButton.Configuration = selected ? .filled() : .bordered()
        cfg.title = descriptor.title
        if selected {
            cfg.baseBackgroundColor = DS.Colors.primary
            cfg.baseForegroundColor = .white
        }
        cfg.background.cornerRadius = 10
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        b.accessibilityIdentifier = "load-detail.tender-sheet/deadline-chip.\(descriptor.token)"  // ISSUE-04 fix
        return b
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        directory.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: TenderSheetCarrierRowView.reuseIdentifier,
            for: indexPath
        ) as! TenderSheetCarrierRowView
        let carrier = directory[indexPath.row]
        cell.configure(carrier: carrier)
        cell.accessibilityIdentifier = "load-detail.tender-sheet/carrier-row.\(carrier.partyID)"  // ISSUE-04 fix
        cell.accessoryType = (selectedCarrierIndex == indexPath.row) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let carrier = directory[indexPath.row]
        // Defensive D-08 — the row should be userInteractionEnabled=false on
        // any non-verified carrier; this guard is belt-and-suspenders.
        guard carrier.verificationState == .verified else {
            tableView.deselectRow(at: indexPath, animated: false)
            return
        }
        let prior = selectedCarrierIndex
        selectedCarrierIndex = indexPath.row
        // Re-render the prior cell to drop its checkmark + the new cell to add it.
        var toReload: [IndexPath] = [indexPath]
        if let prior = prior, prior != indexPath.row {
            toReload.append(IndexPath(row: prior, section: indexPath.section))
        }
        tableView.reloadRows(at: toReload, with: .none)
        tableView.deselectRow(at: indexPath, animated: false)
        updateSendButton()
    }

    // MARK: - Chip / picker handlers

    @objc private func handleChipTap(_ sender: UIButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < chipDescriptors.count else { return }
        selectChip(at: idx)
    }

    private func selectChip(at idx: Int) {
        selectedChipIndex = idx
        let descriptor = chipDescriptors[idx]
        // Update visual state of all chips.
        for (i, chip) in chipButtons.enumerated() {
            let isSelected = (i == idx)
            var cfg: UIButton.Configuration = isSelected ? .filled() : .bordered()
            cfg.title = chipDescriptors[i].title
            if isSelected {
                cfg.baseBackgroundColor = DS.Colors.primary
                cfg.baseForegroundColor = .white
            }
            cfg.background.cornerRadius = 10
            chip.configuration = cfg
        }

        if let interval = descriptor.interval {
            selectedDeadline = .preset(interval)
            datePicker.isHidden = true
        } else {
            // Custom… — reveal the date picker. Seed it with 1 day from now.
            let seed = Date(timeIntervalSinceNow: 24 * 3600)
            datePicker.date = seed
            selectedDeadline = .custom(seed)
            datePicker.isHidden = false
        }
        updateResolvedTimeLine()
        updateSendButton()
    }

    @objc private func handleDatePickerChanged() {
        selectedDeadline = .custom(datePicker.date)
        updateResolvedTimeLine()
        updateSendButton()
    }

    // MARK: - Resolved deadline

    /// The currently-resolved respond-by date based on the selected chip /
    /// picker. Preset chips are offsets from "now" computed at read time
    /// (so the test that reads-then-taps measures the same Date the actual
    /// onSend closure receives, modulo a tiny seconds-of-drift).
    private var resolvedDeadlineDate: Date {
        switch selectedDeadline {
        case .preset(let interval):
            return Date(timeIntervalSinceNow: interval)
        case .custom(let date):
            return date
        }
    }

    private func updateResolvedTimeLine() {
        let formatted = LoadActionsView.RespondByFormatter.format(resolvedDeadlineDate)
        let template = NSLocalizedString(
            "loads.detail.tender.deadline.resolved.format",
            value: "↳ %@",
            comment: "Tender sheet — resolved-time confirmation line below chips (UI-SPEC line 368)"
        )
        resolvedTimeLabel.text = String(format: template, formatted)
    }

    // MARK: - Send-button state (D-11 / UI-SPEC line 453)

    private enum SendButtonState {
        case enabled
        case disabled(helperKey: String, helperValue: String)
    }

    private func computeSendButtonState() -> SendButtonState {
        guard let idx = selectedCarrierIndex, idx >= 0, idx < directory.count else {
            return .disabled(
                helperKey: "loads.detail.tender.helper.no_carrier",
                helperValue: "Pick a carrier to send."
            )
        }
        let carrier = directory[idx]
        guard carrier.verificationState == .verified else {
            // Defensive — D-08 disables the row, so this branch is
            // theoretically unreachable, but include the helper copy for
            // completeness per UI-SPEC line 372.
            return .disabled(
                helperKey: "loads.detail.tender.helper.unverified_carrier",
                helperValue: "Pick a verified carrier."
            )
        }
        guard resolvedDeadlineDate > Date() else {
            return .disabled(
                helperKey: "loads.detail.tender.helper.past_deadline",
                helperValue: "Pick a future deadline."
            )
        }
        return .enabled
    }

    private func updateSendButton() {
        switch computeSendButtonState() {
        case .enabled:
            sendButton.isEnabled = true
            // Pitfall 8 — alpha toggle, NEVER isHidden.
            helperLabel.alpha = 0.0
            helperLabel.text = nil
        case .disabled(let key, let value):
            sendButton.isEnabled = false
            helperLabel.alpha = 1.0
            helperLabel.text = NSLocalizedString(
                key,
                value: value,
                comment: "Tender sheet Send-button helper copy (UI-SPEC line 371-373)"
            )
        }
    }

    // MARK: - Send / Cancel taps

    @objc private func handleSendTap() {
        guard let idx = selectedCarrierIndex, idx >= 0, idx < directory.count else { return }
        let carrier = directory[idx]
        let deadline = resolvedDeadlineDate

        // In-flight visual: disable Send + show spinner. Sheet stays visible
        // (UI-SPEC line 454); parent dismisses on 200 from .loaded render arm.
        sendButton.isEnabled = false
        var cfg = sendButton.configuration
        cfg?.showsActivityIndicator = true
        sendButton.configuration = cfg

        Task { [weak self] in
            await self?.onSend(carrier.partyID, deadline)
            // If still attached, restore Send button (parent may have
            // dismissed by now on success).
            await MainActor.run {
                guard let self else { return }
                var cfg = self.sendButton.configuration
                cfg?.showsActivityIndicator = false
                self.sendButton.configuration = cfg
                self.updateSendButton()
            }
        }
    }

    @objc private func handleCancelTap() {
        onCancel()
    }

    // MARK: - Internal test seams (@testable import surface)

    internal var tableViewForTesting: UITableView { tableView }
    internal var sendButtonForTesting: UIButton { sendButton }
    internal var helperLabelForTesting: UILabel { helperLabel }
    internal var deadlineChipsForTesting: [UIButton] { chipButtons }
    internal var selectedChipIndexForTesting: Int { selectedChipIndex }
    internal var datePickerForTesting: UIDatePicker { datePicker }
    internal var resolvedTimeLabelForTesting: UILabel { resolvedTimeLabel }
    internal var resolvedDeadlineForTesting: Date { resolvedDeadlineDate }

    /// Programmatically select a row (test seam). Mirrors the user-tap path:
    /// delegate's didSelectRowAt receives the indexPath. Skips disabled
    /// carriers (matches the user-tap reality).
    internal func selectCarrierForTesting(at index: Int) {
        guard index >= 0 && index < directory.count else { return }
        let ip = IndexPath(row: index, section: 0)
        self.tableView(tableView, didSelectRowAt: ip)
    }

    /// Set a custom respond-by deadline (test seam — bypasses the chip row).
    internal func setCustomDeadlineForTesting(_ date: Date) {
        selectedDeadline = .custom(date)
        updateResolvedTimeLine()
        updateSendButton()
    }

    /// Tap a chip programmatically (test seam).
    internal func tapChipForTesting(at index: Int) {
        guard index >= 0 && index < chipDescriptors.count else { return }
        selectChip(at: index)
    }

    /// Tap the Send button (test seam — exercises the in-flight path).
    internal func tapSendForTesting() {
        handleSendTap()
    }

    /// Tap the Cancel button (test seam).
    internal func tapCancelForTesting() {
        handleCancelTap()
    }
}
