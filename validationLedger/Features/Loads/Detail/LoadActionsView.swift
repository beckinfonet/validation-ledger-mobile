// validationLedger/Features/Loads/Detail/LoadActionsView.swift
//
// Phase 10 Plan 04 Task 1 — the per-role action region rendered inline in
// `LoadDetailBodyView.contentStack` at index 2 (between `timelineContainer`
// and `freightDetailsContainer`).
//
// === Phase 10 decision anchors ===
//
// D-01 (CONTEXT) — mount index 2 inside `LoadDetailBodyView.contentStack`.
//                  The body's 5-child arrangement grows to 6 with this region.
//                  Visually reads as part of the body's vertical rhythm.
//
// D-02 (CONTEXT) — action buttons arranged SIDE-BY-SIDE EQUAL WIDTH in a
//                  horizontal `UIStackView` with `.fillEqually` distribution.
//                  NOT primary-vs-secondary visual hierarchy. 44pt min touch
//                  target is preserved; Dynamic Type allows vertical
//                  re-stacking when content gets long.
//
// D-03 (CONTEXT) — destructive actions (`.cancel`, `.reject`) receive
//                  `DS.Colors.destructive` tint, separate from the
//                  equal-weight layout decision.
//
// D-04 (CONTEXT) — empty caption never collapses. When the policy returns
//                  `[]`, this view renders a centered localized caption per
//                  the 3-rule table (Factoring / terminal / generic). The
//                  region keeps its vertical footprint (24pt top + bottom
//                  padding) so the body's scroll order does not visually
//                  snap closed.
//
// D-09 (CONTEXT) — load-level tender gate. When
//                  `Load.tenderEligibility?.canTender == false` AND the
//                  visible action set contains `.tender`, the Tender button
//                  renders `isEnabled = false` with an inline reason below
//                  — server-supplied `disabledReason` rendered VERBATIM
//                  (UI-SPEC line 290 — DOCUMENTED exception to the no-server-
//                  text rule because `disabledReason` is load-state metadata,
//                  NOT error-response payload).
//
// D-12 (CONTEXT) — in-flight rendering. During `.actionInFlight`, this view
//                  re-renders against the PRE-TAP action set (NOT the
//                  predicted post-tap action set) with the tapped button
//                  showing its spinner and other buttons disabled. The
//                  configure() signature accepts `inFlight: LoadAction?` for
//                  this purpose. Only on `.loaded` does the action set snap
//                  forward — owned by the VC, not this view.
//
// === UI-SPEC anchors ===
//   - § Component Geometry lines 407-422 (the LOCKED geometry).
//   - § Action button titles lines 270-282 (LOCKED titles — delegated to
//     `LoadActionTitleResolver.title(for:currentStatus:)` from Plan 02).
//   - § ACTION-07 disabled-reason lines 284-295 (server-supplied disabledReason).
//   - § Empty-state captions lines 297-313 (Factoring / terminal / generic).
//   - § Respond-by countdown lines 315-335 (static, not live counter).
//
// === ROADMAP § Phase 10 lock — no `switch.*\.status` in this file ===
// The `currentStatus` argument is consumed ONLY by
// `LoadActionTitleResolver.title(for: .advanceStatus, currentStatus:)` and
// by the empty-state-caption interpolation — neither is a `switch` on
// status. The resolver lives in `Core/Load/` (T-10-01 mitigation), keeping
// the `Features/Loads/` lint test (`LoadDetailNoStatusSwitchTests`) green.
//
// === Threat model anchors ===
// T-10-01 (Wrong action shown for role × status) — mitigate. This view
//   consumes the `actions[]` argument VERBATIM; never recomputes against
//   `currentStatus`. The VC computes via `RoleLoadPolicy.availableActions(...)`.
// T-10-04 (Tender to unverified counterparty) — partial mitigate. The
//   `tenderEligibility.canTender == false` path here disables the Tender
//   button + renders the server-supplied reason. The carrier-level picker
//   gate is Plan 06.
// T-10-PR-01 (Pitfall 6 — in-flight against post-tap set) — mitigate. The
//   `inFlight` parameter on configure() is just a UI marker; the actions[]
//   list is the source of truth and never recomputed here.
// T-10-PR-02 (Pitfall 5 — `in_transit` underscore leakage) — mitigate. The
//   terminal-state caption uses `LoadStatus.localizedDisplayName` from Plan 01.
//
// === Accessibility identifier namespace ===
//   - root view:                "load-detail.actions"
//   - empty-state caption label: "load-detail.actions.empty-caption"
//   - disabled-reason label:     "load-detail.actions.disabled-reason"
//   - respond-by label:          "load-detail.actions.respond-by"
//   - per-button identifier:     "load-detail.actions.button.<actionRawValue>"

import UIKit

public final class LoadActionsView: UIView {

    // MARK: - Subviews

    private let backingView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = DS.Colors.surface
        return v
    }()

    /// Horizontal action button row — N buttons distributed `.fillEqually`.
    /// At AX content sizes the axis flips to `.vertical` via
    /// `applyDynamicTypeAxis()`.
    private let buttonRow: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.distribution = .fillEqually
        s.alignment = .fill
        s.spacing = DS.Spacing.sm
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let emptyCaptionLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.caption
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.accessibilityIdentifier = "load-detail.actions.empty-caption"
        l.isHidden = true
        return l
    }()

    private let disabledReasonLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 2
        l.lineBreakMode = .byWordWrapping
        l.textAlignment = .left
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.accessibilityIdentifier = "load-detail.actions.disabled-reason"
        l.isHidden = true
        return l
    }()

    private let respondByLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 1
        l.textAlignment = .left
        l.adjustsFontForContentSizeCategory = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.accessibilityIdentifier = "load-detail.actions.respond-by"
        l.isHidden = true
        return l
    }()

    // MARK: - Test seams

    /// Exposed for `LoadActionsViewTests.test_configure_DynamicTypeAccessibility...`
    /// — the test asserts the row axis post-configure rather than rely on the
    /// underlying stack being private.
    internal var buttonRowAxisForTesting: NSLayoutConstraint.Axis {
        buttonRow.axis
    }

    /// Exposed for `LoadActionsViewTests.test_configure_singleAction_...`
    /// — counts the arranged subviews (real button + invisible spacer for the
    /// single-action case).
    internal var buttonRowArrangedSubviewCountForTesting: Int {
        buttonRow.arrangedSubviews.count
    }

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("LoadActionsView does not support NSCoder; programmatic only — Phase 10 D-01")
    }

    // MARK: - Layout

    private func setUp() {
        accessibilityIdentifier = "load-detail.actions"

        // Register for content-size-category trait changes (iOS 17 API)
        // so the row axis flips even under `traitOverrides.preferredContent
        // SizeCategory` (which does NOT always fire the legacy
        // `traitCollectionDidChange(_:)` override but DOES go through
        // `registerForTraitChanges`).
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: LoadActionsView, _: UITraitCollection) in
            view.applyDynamicTypeAxis()
        }

        addSubview(backingView)
        addSubview(buttonRow)
        addSubview(emptyCaptionLabel)
        addSubview(disabledReasonLabel)
        addSubview(respondByLabel)

        NSLayoutConstraint.activate([
            backingView.topAnchor.constraint(equalTo: topAnchor),
            backingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Button row pins inset by DS.Spacing.md leading/trailing,
            // DS.Spacing.lg top (UI-SPEC line 415).
            buttonRow.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.lg),
            buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.md),
            buttonRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.md),

            // Disabled-reason label sits below the button row, leading-anchored
            // to the row's leading (UI-SPEC line 295). Trailing pinned to keep
            // wrap behavior natural.
            disabledReasonLabel.topAnchor.constraint(
                equalTo: buttonRow.bottomAnchor, constant: DS.Spacing.xs),
            disabledReasonLabel.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            disabledReasonLabel.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),

            // Respond-by label below disabled-reason (or below buttons if no
            // disabled reason); same horizontal alignment.
            respondByLabel.topAnchor.constraint(
                equalTo: disabledReasonLabel.bottomAnchor, constant: DS.Spacing.xs),
            respondByLabel.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            respondByLabel.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),

            // Bottom anchor: pin to the lowest of the two labels with the
            // locked DS.Spacing.lg bottom padding (UI-SPEC line 415).
            respondByLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor, constant: -DS.Spacing.lg),

            // Caption label centered inside the region (empty-state path).
            emptyCaptionLabel.topAnchor.constraint(
                equalTo: topAnchor, constant: DS.Spacing.lg),
            emptyCaptionLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -DS.Spacing.lg),
            emptyCaptionLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: DS.Spacing.md),
            emptyCaptionLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -DS.Spacing.md),
        ])

        // Apply initial Dynamic Type axis posture.
        applyDynamicTypeAxis()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyDynamicTypeAxis()
    }

    /// Flip `buttonRow.axis` to `.vertical` at accessibility content sizes
    /// so button titles never truncate (UI-SPEC line 419).
    private func applyDynamicTypeAxis() {
        let isAX = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        buttonRow.axis = isAX ? .vertical : .horizontal
    }

    // MARK: - Configure (public render contract — Phase 10 D-01)

    /// Render the action region against the supplied action set + role +
    /// current status + ACTION-07 eligibility gate + respond-by date +
    /// in-flight marker. The `onTap` closure fires when the user taps a
    /// button (NOT when in-flight — in-flight taps are no-ops).
    ///
    /// PARAMETERS:
    /// - `actions`:           the pre-computed `[LoadAction]` from
    ///                        `RoleLoadPolicy.availableActions(for:in:)` —
    ///                        this view consumes it verbatim and NEVER
    ///                        recomputes against `currentStatus` (Pitfall 6).
    /// - `role`:              the session role — used for the respond-by
    ///                        visibility predicate (carrier/dispatch only)
    ///                        AND for the empty-state caption (Factoring
    ///                        renders a distinct caption).
    /// - `currentStatus`:     the load's current `LoadStatus` — consumed by
    ///                        `LoadActionTitleResolver.title(for:currentStatus:)`
    ///                        for the `.advanceStatus` button title AND by
    ///                        the empty-state caption format-string
    ///                        interpolation. NEVER `switch`-ed on here.
    /// - `tenderEligibility`: server-supplied ACTION-07 gate.
    /// - `respondByAt`:       optional respond-by date for the inline label.
    /// - `inFlight`:          nil when not in-flight; the tapped LoadAction
    ///                        when in-flight (shows spinner on that button,
    ///                        disables the others).
    /// - `onTap`:             tap handler. Fired with the action whose
    ///                        button was tapped. NO-OP path is enforced at
    ///                        the call site by passing a no-op closure.
    public func configure(
        actions: [LoadAction],
        role: Role,
        currentStatus: LoadStatus,
        tenderEligibility: TenderEligibility?,
        respondByAt: Date?,
        inFlight: LoadAction?,
        onTap: @escaping (LoadAction) -> Void
    ) {
        if actions.isEmpty {
            renderEmptyState(role: role, currentStatus: currentStatus)
        } else {
            renderButtonState(
                actions: actions,
                role: role,
                currentStatus: currentStatus,
                tenderEligibility: tenderEligibility,
                respondByAt: respondByAt,
                inFlight: inFlight,
                onTap: onTap
            )
        }
        updateAccessibilityElements(actions: actions)
    }

    // MARK: - Empty-state rendering (UI-SPEC line 297-313 — LOCKED)

    private func renderEmptyState(role: Role, currentStatus: LoadStatus) {
        // Tear down any prior buttons.
        clearButtonRow()
        buttonRow.isHidden = true
        disabledReasonLabel.isHidden = true
        respondByLabel.isHidden = true
        emptyCaptionLabel.isHidden = false
        emptyCaptionLabel.text = emptyCaptionText(role: role, currentStatus: currentStatus)
    }

    /// Resolve the empty-state caption per the 3-rule table:
    ///   1. Factoring (any status)            -> view-only copy.
    ///   2. Non-Factoring + non-`.draft`      -> "This load is %@. ..." with
    ///                                            LoadStatus.localizedDisplayName.
    ///   3. Non-Factoring + `.draft`          -> generic fallback (defensive).
    ///
    /// **Pitfall 5 scope:** the `localizedDisplayName` interpolation applies
    /// to ANY non-Factoring empty state where the status has a coherent
    /// display name — using the "This load is %@" template even for mid-
    /// lifecycle statuses (.accepted / .dispatched / .inTransit) guarantees
    /// the lowercase-with-space form for every possible empty rendering path,
    /// closing the regression-guard surface across the full LoadStatus enum.
    /// UI-SPEC line 304 cites the terminal set as the canonical example; the
    /// implementation applies the same template universally to keep the
    /// "in_transit" underscore from leaking through ANY caption path
    /// (regression test guard: Test 6 of LoadActionsViewTests).
    private func emptyCaptionText(role: Role, currentStatus: LoadStatus) -> String {
        if role == .factoring {
            return NSLocalizedString(
                "loads.actions.empty.factoring",
                value: "This is a view-only role. No actions available.",
                comment: "Phase 10 Plan 04 LoadActionsView — Factoring view-only caption (UI-SPEC line 303)"
            )
        }
        // `.draft` is the special pre-lifecycle state. For non-Factoring roles
        // the policy would only produce `[]` here on a Shipper/Broker view
        // — but the policy actually returns `[.post]` for `.draft`, so this
        // branch is genuinely unreachable in production. Defensive fallback.
        if currentStatus == .draft {
            return NSLocalizedString(
                "loads.actions.empty.generic",
                value: "No actions available right now.",
                comment: "Phase 10 Plan 04 LoadActionsView — defensive empty caption (UI-SPEC line 305)"
            )
        }
        // Default path — interpolate localizedDisplayName so the underscore
        // form `in_transit` / `pod_captured` never reaches the screen.
        let format = NSLocalizedString(
            "loads.actions.empty.terminal.format",
            value: "This load is %@. No actions available.",
            comment: "Phase 10 Plan 04 LoadActionsView — empty-state caption with status interpolation (UI-SPEC line 304); %@ is LoadStatus.localizedDisplayName"
        )
        return String(format: format, currentStatus.localizedDisplayName)
    }

    // MARK: - Button rendering (UI-SPEC line 411-422 — LOCKED)

    private func renderButtonState(
        actions: [LoadAction],
        role: Role,
        currentStatus: LoadStatus,
        tenderEligibility: TenderEligibility?,
        respondByAt: Date?,
        inFlight: LoadAction?,
        onTap: @escaping (LoadAction) -> Void
    ) {
        emptyCaptionLabel.isHidden = true
        buttonRow.isHidden = false

        // Tear down any prior buttons / spacers.
        clearButtonRow()

        // Build a button per action.
        for action in actions {
            let button = makeButton(
                for: action,
                currentStatus: currentStatus,
                inFlight: inFlight,
                onTap: onTap
            )
            buttonRow.addArrangedSubview(button)
        }

        // UI-SPEC line 417 — single-button case: add an invisible spacer so the
        // row has 2 cells (the single button doesn't span full width).
        if actions.count == 1 {
            let spacer = UIView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.isAccessibilityElement = false
            buttonRow.addArrangedSubview(spacer)
        }

        // ACTION-07 — tenderEligibility gate.
        applyTenderEligibilityGate(
            actions: actions,
            currentStatus: currentStatus,
            tenderEligibility: tenderEligibility,
            inFlight: inFlight
        )

        // Respond-by inline label (carrier/dispatch on .tendered with a date).
        applyRespondByLabel(
            actions: actions,
            role: role,
            currentStatus: currentStatus,
            respondByAt: respondByAt
        )
    }

    private func clearButtonRow() {
        for v in buttonRow.arrangedSubviews {
            buttonRow.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    /// Build a single action button per UI-SPEC line 411-422 + D-03 destructive
    /// tint for `.cancel` / `.reject`. Per D-12, the button's
    /// `showsActivityIndicator` is set on the in-flight button; non-tapped
    /// buttons during in-flight are `isEnabled = false`.
    private func makeButton(
        for action: LoadAction,
        currentStatus: LoadStatus,
        inFlight: LoadAction?,
        onTap: @escaping (LoadAction) -> Void
    ) -> UIButton {
        let title = LoadActionTitleResolver.title(for: action, currentStatus: currentStatus)
        var cfg = UIButton.Configuration.filled()
        cfg.title = title  // title stays attached even mid-flight so tests + a11y
                           // can resolve the button by its semantic identity.
        cfg.baseBackgroundColor = Self.isDestructive(action)
            ? DS.Colors.destructive
            : DS.Colors.primary
        cfg.baseForegroundColor = .white

        // In-flight: this is the tapped button -> show the spinner alongside
        // the title. UIButton.Configuration renders the activity indicator
        // adjacent to the title automatically when showsActivityIndicator
        // is true; this matches the iOS 17 native idiom (RESEARCH Pattern 5).
        if let inFlight, inFlight == action {
            cfg.showsActivityIndicator = true
        }

        let button = UIButton(configuration: cfg)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "load-detail.actions.button.\(action.rawValue)"
        button.accessibilityLabel = title

        // 50pt min height per UI-SPEC line 416 (`heightAnchor >= 50`).
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        button.addAction(UIAction { _ in onTap(action) }, for: .touchUpInside)

        // In-flight: BOTH the tapped button (so the second tap is a no-op
        // while we spin) AND the non-tapped buttons (so a sibling action
        // can't supersede mid-spinner) are disabled. The VC's render path
        // re-enables them on `.loaded` or `.actionFailed`.
        if inFlight != nil {
            button.isEnabled = false
        }

        return button
    }

    /// `.cancel` and `.reject` are the destructive actions per UI-SPEC line
    /// 70-71 + D-03. `.cancel` cancels a load (broker side); `.reject`
    /// rejects a tender (carrier side). Membership check, NOT a switch on
    /// status — the lint contract stays satisfied.
    private static let destructiveActions: Set<LoadAction> = [.cancel, .reject]
    private static func isDestructive(_ action: LoadAction) -> Bool {
        destructiveActions.contains(action)
    }

    /// Apply the ACTION-07 gate: when `actions.contains(.tender)` AND
    /// `tenderEligibility?.canTender == false`, disable the Tender button and
    /// reveal the inline disabled-reason label below the row. The Cancel
    /// button is NEVER gated by `tenderEligibility` per UI-SPEC line 535.
    private func applyTenderEligibilityGate(
        actions: [LoadAction],
        currentStatus: LoadStatus,
        tenderEligibility: TenderEligibility?,
        inFlight: LoadAction?
    ) {
        // In-flight: hide the disabled-reason — the spinner replaces this UI
        // surface for the duration of the transition.
        if inFlight != nil {
            disabledReasonLabel.isHidden = true
            return
        }

        guard let elig = tenderEligibility,
              elig.canTender == false,
              actions.contains(.tender) else {
            disabledReasonLabel.isHidden = true
            return
        }

        // Find the Tender button (by its action-rawValue accessibilityIdentifier
        // we set in `makeButton`).
        if let tenderButton = buttonRow.arrangedSubviews
            .first(where: { ($0 as? UIButton)?.accessibilityIdentifier == "load-detail.actions.button.tender" })
            as? UIButton {
            tenderButton.isEnabled = false
            // VoiceOver hears the reason via accessibilityHint.
            tenderButton.accessibilityHint = elig.disabledReason
        }

        let reasonText: String = {
            if let reason = elig.disabledReason, !reason.isEmpty {
                return reason
            }
            return NSLocalizedString(
                "loads.actions.tender.disabled.generic",
                value: "Tender unavailable",
                comment: "Phase 10 Plan 04 LoadActionsView — generic ACTION-07 disabled-reason fallback (UI-SPEC line 291)"
            )
        }()
        disabledReasonLabel.text = reasonText
        disabledReasonLabel.isHidden = false
    }

    /// Apply the respond-by inline label per UI-SPEC line 322-335.
    /// Visible iff: `role ∈ {.carrier, .dispatch}` AND `currentStatus ==
    /// .tendered` AND `respondByAt != nil` AND `!actions.isEmpty`.
    /// Color: `labelSecondary` for future; `destructive` for past-due.
    private func applyRespondByLabel(
        actions: [LoadAction],
        role: Role,
        currentStatus: LoadStatus,
        respondByAt: Date?
    ) {
        let shouldShow = (role == .carrier || role == .dispatch)
            && currentStatus == .tendered
            && respondByAt != nil
            && !actions.isEmpty

        guard shouldShow, let respondByAt else {
            respondByLabel.isHidden = true
            return
        }

        let formatted = RespondByFormatter.format(respondByAt)
        let isPast = respondByAt < Date()
        let format: String
        if isPast {
            format = NSLocalizedString(
                "loads.actions.respond_by.past_due.format",
                value: "Past due — respond by %@",
                comment: "Phase 10 Plan 04 LoadActionsView — past-due respond-by inline label (UI-SPEC line 324)"
            )
            respondByLabel.textColor = DS.Colors.destructive
        } else {
            format = NSLocalizedString(
                "loads.actions.respond_by.format",
                value: "Respond by %@",
                comment: "Phase 10 Plan 04 LoadActionsView — respond-by inline label (UI-SPEC line 323)"
            )
            respondByLabel.textColor = DS.Colors.labelSecondary
        }
        respondByLabel.text = String(format: format, formatted)
        respondByLabel.isHidden = false
    }

    // MARK: - Accessibility elements (UI-SPEC line 422 — explicit tap order)

    /// Publish `accessibilityElements` per UI-SPEC line 422:
    ///   [each visible button in tap order, then visible inline labels].
    private func updateAccessibilityElements(actions: [LoadAction]) {
        var elements: [Any] = []

        if actions.isEmpty {
            elements.append(emptyCaptionLabel)
        } else {
            for v in buttonRow.arrangedSubviews {
                if let b = v as? UIButton {
                    elements.append(b)
                }
            }
            if !disabledReasonLabel.isHidden {
                elements.append(disabledReasonLabel)
            }
            if !respondByLabel.isHidden {
                elements.append(respondByLabel)
            }
        }

        accessibilityElements = elements
    }

    // MARK: - Respond-by date formatter (UI-SPEC line 326-331 — LOCKED)

    /// Pure date formatter for the carrier/dispatch respond-by inline label.
    /// Four tiers per UI-SPEC line 328-331:
    ///   - Today        : "5:00 PM today"
    ///   - Tomorrow     : "5:00 PM tomorrow"
    ///   - 2–6 days out : "5:00 PM, Wed"
    ///   - 7+ days out  : "5:00 PM, May 28"
    ///
    /// Exposed `internal` so `RespondByLabelTests` can call it directly via
    /// `@testable import validationLedger` without needing a fully-built
    /// `LoadActionsView` instance.
    internal enum RespondByFormatter {

        static func format(_ date: Date) -> String {
            let timeString = timeFormatter.string(from: date)
            let calendar = Calendar.current
            let now = Date()

            if calendar.isDateInToday(date) {
                return "\(timeString) today"
            }
            if calendar.isDateInTomorrow(date) {
                return "\(timeString) tomorrow"
            }

            // Day delta (using start-of-day on both sides keeps a 23h jump
            // from tomorrow→today from sliding into the weekday bucket).
            let startToday = calendar.startOfDay(for: now)
            let startTarget = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0

            if (2...6).contains(days) {
                return "\(timeString), \(weekdayFormatter.string(from: date))"
            }
            return "\(timeString), \(monthDayFormatter.string(from: date))"
        }

        private static let timeFormatter: DateFormatter = {
            let df = DateFormatter()
            df.timeStyle = .short
            df.dateStyle = .none
            return df
        }()

        private static let weekdayFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "E"  // localized weekday short (Mon/Tue/Wed/...)
            return df
        }()

        private static let monthDayFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "MMM d"  // localized month abbr + day (May 28)
            return df
        }()
    }
}
