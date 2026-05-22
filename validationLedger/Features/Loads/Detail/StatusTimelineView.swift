// validationLedger/Features/Loads/Detail/StatusTimelineView.swift
//
// Phase 9 LOAD-06 / D-17 / D-18 — the status timeline.
//
// Mirrors `LoadStatusBadgeView` pill geometry (PATTERNS table row 20) +
// `LoadListViewController.errorStateView` vertical UIStackView posture.
//
// === D-17: hybrid layout ===
// A 6-pill horizontal stepper renders the primary lifecycle (Posted →
// Tendered → Accepted → Dispatched → In-Transit → Delivered). Below the
// stepper, a "current-state expanded card" shows the active state in
// detail: badge + relative timestamp, actor display name, next-milestone
// hint copy. Per UI-SPEC § Status Timeline lines 287-326.
//
// === D-18: side-states NOT surfaced (ARCHITECTURAL SEPARATION) ===
// The stepper renders ONLY the 6 primary cases. Side-state events in
// `Load.stateHistory` (.rejected / .expired / .draft / .podCaptured /
// .invoiced / .funded) are skipped when picking the current status —
// `pickCurrentStatus(from:)` walks the history in REVERSE and returns the
// most recent primary-lifecycle event. The previous primary status
// remains current.
//
// The single sanctioned exception is `.cancelled` — a terminal side-state
// that DOES surface as the current pill + replaces Row 3 with the locked
// "This load was cancelled." copy per UI-SPEC line 325. Pulling on this
// thread (adding more side-state rendering, audit-history disclosure)
// re-opens an explicitly-deferred design decision (CONTEXT D-18 +
// Deferred Ideas — audit-history view is a future phase).
//
// The timeline is a LOGISTICS surface. The trust-graph + chain-integrity
// banner are the FRAUD surface. Don't blur the boundary.
//
// === Threat-model anchors ===
// T-09-03 (Tampering — client-side trust derivation): this view reads ONLY
//   the LoadStatus enum cases + LoadStatusEvent (status, timestamp, actor).
//   It NEVER inspects ChainIntegrity / verificationState / implicated*
//   fields — the source-assertion grep gate locks this (`grep -v '^//'` +
//   `grep -cE 'chainIntegrity|verificationState|implicatedNode|
//   implicatedEdge'` returns 0). Adding any such field-reference here is
//   a fraud-surface leak into the logistics surface.
// T-09-04 (PII): no `Logger` / `os_log` / `OSLog` here — the view layer is
//   logging-free per the Phase 8 LoadListViewController file-header lock
//   (T-08-08). The actor display name is server-supplied (already PII-zero
//   in the fixture corpus per Phase 7 D-13) and rendered verbatim.
// T-09-07 (Spoofing — misleading "current" from corrupt history): the
//   `pickCurrentStatus(from:)` walk skips side-states. A history
//   `[posted, tendered, rejected]` resolves to `.tendered`, NOT `.posted`
//   and NOT advanced past `.tendered`. Locked by
//   `test_sideStateRejectedDoesNotAdvanceStepper`.
//
// === Accessibility ===
// The 6-pill stepper is a single combined element (UI-SPEC line 870):
// `stepperStack.isAccessibilityElement = true` with a composed label of
// the form "Status timeline. Posted, Tendered complete. Accepted current.
// Dispatched, In transit, Delivered upcoming." The current-state card is
// its own element with a composed label concatenating Rows 1+2+3.

import UIKit

public final class StatusTimelineView: UIView {

    // MARK: - Constants (D-17 primary lifecycle order)

    /// The 6 primary lifecycle cases (D-17), in render order.
    /// Side-states (`.rejected, .expired, .draft, .podCaptured, .invoiced,
    /// .funded, .cancelled`) are NOT in this list — D-18.
    private static let primaryLifecycle: [LoadStatus] = [
        .posted, .tendered, .accepted, .dispatched, .inTransit, .delivered,
    ]

    // MARK: - Stepper subviews

    private let stepperStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.distribution = .fillEqually
        s.alignment = .center
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var pillViews: [UIView] = []
    private var pillLabels: [UILabel] = []

    /// CR-01 cache: when the most recent event in stateHistory is
    /// `.cancelled`, this stores the index in `primaryLifecycle` of the
    /// furthest primary-lifecycle status reached BEFORE the cancel — so
    /// the stepper can render completed pills as "done" + the pre-cancel
    /// pill as "current," instead of regressing every pill to "future"
    /// (which hid the load's actual progress prior to cancellation).
    /// `nil` whenever currentStatus != .cancelled.
    private var priorPrimaryForCancelledIdx: Int?

    // MARK: - Card subviews (current-state expanded card)

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = DS.Colors.surface
        v.layer.cornerRadius = 8
        v.layer.masksToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "load-detail.timeline.current-card"
        return v
    }()

    private let cardStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = DS.Spacing.sm
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let row1Badge: LoadStatusBadgeView = {
        let v = LoadStatusBadgeView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        return v
    }()

    private let row1Timestamp: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let row2Actor: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.label
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let row3NextMilestone: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("StatusTimelineView is constructed programmatically only")
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Pitfall 8 (mirrors LoadStatusBadgeView line 98): recompute pill
        // cornerRadius on every layout pass so Dynamic Type growth keeps
        // the full-pill shape — never a slab.
        for pill in pillViews {
            pill.layer.cornerRadius = pill.bounds.height / 2
        }
    }

    private func setUp() {
        backgroundColor = .clear
        accessibilityIdentifier = "load-detail.timeline"

        buildStepper()
        buildCard()

        // Vertical outer stack: [stepperStack, cardView].
        let outerStack = UIStackView(arrangedSubviews: [stepperStack, cardView])
        outerStack.axis = .vertical
        outerStack.alignment = .fill
        outerStack.spacing = DS.Spacing.md   // UI-SPEC line 313 — md gap.
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func buildStepper() {
        for status in Self.primaryLifecycle {
            let label = UILabel()
            label.font = DS.Typography.footnote
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.text = Self.uppercaseLabel(for: status)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isUserInteractionEnabled = false

            let pill = UIView()
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.layer.masksToBounds = true
            pill.accessibilityIdentifier =
                "load-detail.timeline.stepper.pill.\(status.rawValue)"
            pill.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: DS.Spacing.xs),
                label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -DS.Spacing.xs),
                label.topAnchor.constraint(equalTo: pill.topAnchor, constant: DS.Spacing.xs),
                label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -DS.Spacing.xs),
            ])

            pillViews.append(pill)
            pillLabels.append(label)
            // Wrap each pill in a stretchy container so the .fillEqually
            // distribution gives every slot the same width while the pill
            // itself stays centered + intrinsic-sized inside its slot.
            let slot = UIView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
                pill.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                pill.leadingAnchor.constraint(greaterThanOrEqualTo: slot.leadingAnchor),
                pill.trailingAnchor.constraint(lessThanOrEqualTo: slot.trailingAnchor),
                pill.topAnchor.constraint(greaterThanOrEqualTo: slot.topAnchor),
                pill.bottomAnchor.constraint(lessThanOrEqualTo: slot.bottomAnchor),
            ])
            stepperStack.addArrangedSubview(slot)
        }

        // UI-SPEC line 870 — single combined element. The composed label
        // is rebuilt every `configure(load:)` based on the current status.
        stepperStack.isAccessibilityElement = true
        stepperStack.accessibilityTraits = .staticText
    }

    private func buildCard() {
        // Row 1 — badge + relative timestamp (horizontal stack).
        let row1 = UIStackView(arrangedSubviews: [row1Badge, row1Timestamp])
        row1.axis = .horizontal
        row1.alignment = .center
        row1.spacing = DS.Spacing.sm
        row1.translatesAutoresizingMaskIntoConstraints = false

        cardStack.addArrangedSubview(row1)
        cardStack.addArrangedSubview(row2Actor)
        cardStack.addArrangedSubview(row3NextMilestone)

        cardView.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: DS.Spacing.md),
            cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -DS.Spacing.md),
            cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: DS.Spacing.md),
            cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -DS.Spacing.md),
        ])

        cardView.isAccessibilityElement = true
        cardView.accessibilityTraits = .staticText
    }

    // MARK: - Public API

    /// Render the timeline from a Decodable Load.
    ///
    /// Per T-09-03 / D-18: reads ONLY `load.stateHistory: [LoadStatusEvent]`.
    /// The aggregate `Load.status` field is NOT consulted — D-02 says
    /// stateHistory is the source-of-truth for the timeline UI.
    public func configure(load: Load) {
        let currentStatus = Self.pickCurrentStatus(from: load.stateHistory)
        let currentEvent = load.stateHistory.last { $0.status == currentStatus }

        // CR-01: when current is .cancelled, find the index of the
        // furthest primary-lifecycle status reached BEFORE the cancel so
        // applyPillStates can mark prior pills as completed + the
        // pre-cancel pill as current. Resolved here (where stateHistory is
        // in scope) so applyPillStates stays history-agnostic.
        if currentStatus == .cancelled {
            let priorPrimary = load.stateHistory
                .reversed()
                .first(where: { Self.primaryLifecycle.contains($0.status) })?.status
            priorPrimaryForCancelledIdx = priorPrimary.flatMap {
                Self.primaryLifecycle.firstIndex(of: $0)
            }
        } else {
            priorPrimaryForCancelledIdx = nil
        }

        applyPillStates(currentStatus: currentStatus)
        configureRow1(currentStatus: currentStatus, event: currentEvent)
        configureRow2(event: currentEvent)
        configureRow3(currentStatus: currentStatus)

        stepperStack.accessibilityLabel = Self.composedStepperA11yLabel(currentStatus: currentStatus)
        cardView.accessibilityLabel = composedCardA11yLabel(currentStatus: currentStatus, event: currentEvent)
    }

    // MARK: - Current-status pick (D-18 — side-states do NOT advance current)

    /// Walk history in REVERSE; return the first event whose status is in
    /// the primary 6-pill lifecycle OR is the terminal `.cancelled`
    /// (which surfaces ONLY in the card's Row 3 copy, not advancing the
    /// stepper past its prior primary state — but the card content
    /// switches per UI-SPEC line 325).
    ///
    /// Empty / all-side-state histories fall back to `.posted` so the
    /// stepper renders something sensible rather than crashing.
    internal static func pickCurrentStatus(from history: [LoadStatusEvent]) -> LoadStatus {
        // Special-case the terminal side-state .cancelled when it's the
        // most recent event — the card's Row 3 copy gets the locked
        // "This load was cancelled." string. The stepper itself still
        // shows the prior primary lifecycle position for completed pills.
        if let last = history.last, last.status == .cancelled {
            return .cancelled
        }
        for event in history.reversed() {
            if primaryLifecycle.contains(event.status) {
                return event.status
            }
        }
        return .posted
    }

    // MARK: - Pill state application

    private func applyPillStates(currentStatus: LoadStatus) {
        // For .cancelled (terminal side-state surfaced ONLY in Row 3):
        // The stepper renders the prior-primary-lifecycle position as
        // current. Per UI-SPEC line 325, the badge shows CANCELLED with
        // strikethrough — but the stepper highlight uses the latest
        // PRIMARY status before the cancellation (because that's where
        // the load actually stopped on the happy path).
        //
        // Concretely: for [posted, tendered, accepted, dispatched, cancelled]
        // the stepper highlights `.dispatched` as current. The cancelled
        // signal lives in the card copy, NOT the pill highlight.
        //
        // CR-01 fix (Phase 9 review): when currentStatus is .cancelled, we
        // CANNOT fall through to "all pills future" — that hides every
        // primary stage the load definitively passed through before the
        // cancel. .cancelled is a terminal event, not a current pipeline
        // position; we treat it as "after all prior stages." For non-
        // primary fallback (e.g. a malformed history that leaves us with
        // some side-state), keep the original -1 fallback so all pills go
        // future and the bad-data signal is visible.
        let currentIdx: Int
        if let i = Self.primaryLifecycle.firstIndex(of: currentStatus) {
            currentIdx = i
        } else if currentStatus == .cancelled {
            // Walk the configured history off the view? We don't have it
            // here — but pickCurrentStatus's contract guarantees that when
            // .cancelled is the most recent event the stepper should mark
            // the last-non-cancelled primary as the visual "current"
            // position. configure(load:) stores the picked status; the
            // history walk lives there. We re-derive the furthest primary
            // index from priorPrimary the same way pickCurrentStatus does
            // — but applyPillStates is intentionally history-agnostic.
            // The clean separation: when currentStatus == .cancelled, the
            // furthest primary index is exposed via the cached
            // `priorPrimaryForCancelledIdx` set by configure(load:).
            currentIdx = priorPrimaryForCancelledIdx ?? -1
        } else {
            // Other non-primary fallback (.draft / .rejected / .expired /
            // .podCaptured / .invoiced / .funded): no primary pill is
            // "current" — render all primaries as future. Per D-18 these
            // statuses shouldn't be returned by pickCurrentStatus, but if
            // a malformed history pierces that contract, fail visibly.
            currentIdx = -1
        }

        for (i, _) in Self.primaryLifecycle.enumerated() {
            let pill = pillViews[i]
            let label = pillLabels[i]
            if i < currentIdx {
                applyCompletedStyle(pill: pill, label: label)
            } else if i == currentIdx {
                applyCurrentStyle(pill: pill, label: label)
            } else {
                applyFutureStyle(pill: pill, label: label)
            }
        }
    }

    private func applyCompletedStyle(pill: UIView, label: UILabel) {
        pill.backgroundColor = DS.Colors.surface
        pill.layer.borderWidth = 0
        pill.layer.borderColor = nil
        pill.transform = .identity
        label.textColor = DS.Colors.labelSecondary
    }

    private func applyCurrentStyle(pill: UIView, label: UILabel) {
        pill.backgroundColor = DS.Colors.primary
        pill.layer.borderWidth = 0
        pill.layer.borderColor = nil
        // UI-SPEC line 302 — +20% scale draws the eye.
        pill.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        label.textColor = .white
    }

    private func applyFutureStyle(pill: UIView, label: UILabel) {
        pill.backgroundColor = .clear
        pill.layer.borderWidth = 1.0
        pill.layer.borderColor = DS.Colors.separator.cgColor
        pill.transform = .identity
        label.textColor = DS.Colors.labelSecondary
    }

    // MARK: - Card row population

    private func configureRow1(currentStatus: LoadStatus, event: LoadStatusEvent?) {
        // Row 1 left: status badge. The badge handles its own strikethrough
        // on terminal-error tones (rejected/expired/cancelled) per the
        // Phase 8 LoadStatusBadgeView spec — so .cancelled here renders
        // with strikethrough automatically.
        row1Badge.configure(status: currentStatus)

        // Row 1 right: relative timestamp ("2 hours ago"). Fall back to
        // an empty string if the event is missing (shouldn't happen for
        // a non-empty stateHistory — the pick logic always returns a
        // status that came from a real event).
        if let ts = event?.timestamp {
            let formatter = RelativeDateTimeFormatter()
            row1Timestamp.text = formatter.localizedString(for: ts, relativeTo: Date())
        } else {
            row1Timestamp.text = ""
        }
    }

    private func configureRow2(event: LoadStatusEvent?) {
        if let actor = event?.actor {
            row2Actor.text = actor.displayName
            row2Actor.isHidden = false
        } else {
            row2Actor.text = nil
            // Per UI-SPEC line 317 — Row 2 is HIDDEN entirely (not "n/a")
            // when actor is nil. System-driven transitions (auto-expiry)
            // simply don't render an actor line.
            row2Actor.isHidden = true
        }
    }

    private func configureRow3(currentStatus: LoadStatus) {
        let hint = Self.nextMilestoneHint(for: currentStatus)
        if let hintText = hint {
            row3NextMilestone.text = hintText
            row3NextMilestone.isHidden = false
        } else {
            row3NextMilestone.text = nil
            row3NextMilestone.isHidden = true
        }
    }

    // MARK: - Next-milestone hint mapping (UI-SPEC § Copywriting lines 665-674)

    /// Returns the localized next-milestone hint for `status`, or `nil`
    /// when the row should be hidden (terminal `.delivered` / post-
    /// delivery / other non-applicable cases).
    internal static func nextMilestoneHint(for status: LoadStatus) -> String? {
        switch status {
        case .posted:
            return NSLocalizedString(
                "loads.detail.timeline.next.posted",
                value: "Awaiting tender.",
                comment: "Phase 9 timeline Row 3 — next-milestone hint for current=.posted."
            )
        case .tendered:
            return NSLocalizedString(
                "loads.detail.timeline.next.tendered",
                value: "Awaiting carrier response.",
                comment: "Phase 9 timeline Row 3 — next-milestone hint for current=.tendered."
            )
        case .accepted:
            return NSLocalizedString(
                "loads.detail.timeline.next.accepted",
                value: "Awaiting dispatch.",
                comment: "Phase 9 timeline Row 3 — next-milestone hint for current=.accepted."
            )
        case .dispatched:
            return NSLocalizedString(
                "loads.detail.timeline.next.dispatched",
                value: "Awaiting pickup.",
                comment: "Phase 9 timeline Row 3 — next-milestone hint for current=.dispatched."
            )
        case .inTransit:
            return NSLocalizedString(
                "loads.detail.timeline.next.in_transit",
                value: "Awaiting delivery.",
                comment: "Phase 9 timeline Row 3 — next-milestone hint for current=.inTransit."
            )
        case .delivered:
            // Terminal happy-path — no projection (UI-SPEC line 671).
            return nil
        case .cancelled:
            return NSLocalizedString(
                "loads.detail.timeline.next.cancelled",
                value: "This load was cancelled.",
                comment: "Phase 9 timeline Row 3 — terminal-cancelled copy (UI-SPEC line 672)."
            )
        case .draft:
            return NSLocalizedString(
                "loads.detail.timeline.next.draft",
                value: "Not yet posted.",
                comment: "Phase 9 timeline Row 3 — draft default (UI-SPEC line 674 planner-added default)."
            )
        case .rejected, .expired, .podCaptured, .invoiced, .funded:
            // These don't drive the timeline per D-18; if they ever
            // become current (they shouldn't, per pickCurrentStatus),
            // hide Row 3 rather than render misleading copy.
            return nil
        }
    }

    // MARK: - Pill labels (locked uppercase copy)

    private static func uppercaseLabel(for status: LoadStatus) -> String {
        switch status {
        case .posted:
            return NSLocalizedString(
                "loads.detail.timeline.pill.posted",
                value: "POSTED",
                comment: "Phase 9 timeline stepper pill label — posted."
            )
        case .tendered:
            return NSLocalizedString(
                "loads.detail.timeline.pill.tendered",
                value: "TENDERED",
                comment: "Phase 9 timeline stepper pill label — tendered."
            )
        case .accepted:
            return NSLocalizedString(
                "loads.detail.timeline.pill.accepted",
                value: "ACCEPTED",
                comment: "Phase 9 timeline stepper pill label — accepted."
            )
        case .dispatched:
            return NSLocalizedString(
                "loads.detail.timeline.pill.dispatched",
                value: "DISPATCHED",
                comment: "Phase 9 timeline stepper pill label — dispatched."
            )
        case .inTransit:
            return NSLocalizedString(
                "loads.detail.timeline.pill.in_transit",
                value: "IN TRANSIT",
                comment: "Phase 9 timeline stepper pill label — in transit (space-separated per UI-SPEC line 662)."
            )
        case .delivered:
            return NSLocalizedString(
                "loads.detail.timeline.pill.delivered",
                value: "DELIVERED",
                comment: "Phase 9 timeline stepper pill label — delivered."
            )
        // The 7 non-primary cases never render in the stepper (D-18).
        // The switch must be exhaustive so the compiler catches enum
        // additions; we return empty strings here — these branches are
        // unreachable because the stepper only renders primaryLifecycle.
        case .draft, .rejected, .expired, .cancelled,
             .podCaptured, .invoiced, .funded:
            return ""
        }
    }

    // MARK: - Composed accessibility labels (UI-SPEC line 870)

    /// Build the single combined stepper accessibility label, e.g.
    /// "Status timeline. Posted, Tendered complete. Accepted current.
    /// Dispatched, In transit, Delivered upcoming."
    internal static func composedStepperA11yLabel(currentStatus: LoadStatus) -> String {
        let prefix = NSLocalizedString(
            "loads.detail.timeline.a11y.prefix",
            value: "Status timeline.",
            comment: "Phase 9 timeline stepper a11y label — leading prefix (UI-SPEC line 870)."
        )

        // Split primaryLifecycle by index relative to currentStatus.
        let currentIdx = primaryLifecycle.firstIndex(of: currentStatus) ?? -1

        var parts: [String] = [prefix]

        if currentIdx > 0 {
            let completed = primaryLifecycle.prefix(currentIdx).map(a11ySpoken(for:)).joined(separator: ", ")
            let completeSentence = String(
                format: NSLocalizedString(
                    "loads.detail.timeline.a11y.complete",
                    value: "%@ complete.",
                    comment: "Phase 9 timeline a11y — '%@' is comma-separated completed statuses."
                ),
                completed
            )
            parts.append(completeSentence)
        }

        if currentIdx >= 0 {
            let currentSentence = String(
                format: NSLocalizedString(
                    "loads.detail.timeline.a11y.current",
                    value: "%@ current.",
                    comment: "Phase 9 timeline a11y — '%@' is the current status (spoken form)."
                ),
                a11ySpoken(for: currentStatus)
            )
            parts.append(currentSentence)
        } else {
            // Side-state path (e.g. .cancelled). Surface the locked copy
            // so VoiceOver users hear the cancellation as part of the
            // stepper label rather than a silent stepper.
            if currentStatus == .cancelled {
                parts.append(NSLocalizedString(
                    "loads.detail.timeline.a11y.cancelled",
                    value: "Cancelled.",
                    comment: "Phase 9 timeline a11y — terminal-cancelled spoken sentence."
                ))
            }
        }

        if currentIdx + 1 < primaryLifecycle.count {
            let upcomingRange = (currentIdx + 1)..<primaryLifecycle.count
            let upcoming = primaryLifecycle[upcomingRange].map(a11ySpoken(for:)).joined(separator: ", ")
            let upcomingSentence = String(
                format: NSLocalizedString(
                    "loads.detail.timeline.a11y.upcoming",
                    value: "%@ upcoming.",
                    comment: "Phase 9 timeline a11y — '%@' is comma-separated upcoming statuses."
                ),
                upcoming
            )
            parts.append(upcomingSentence)
        }

        return parts.joined(separator: " ")
    }

    /// Build the card a11y label by concatenating Row 1 + Row 2 + Row 3.
    private func composedCardA11yLabel(currentStatus: LoadStatus, event: LoadStatusEvent?) -> String {
        var parts: [String] = []
        parts.append(Self.a11ySpoken(for: currentStatus))
        if let ts = event?.timestamp {
            let formatter = RelativeDateTimeFormatter()
            parts.append(formatter.localizedString(for: ts, relativeTo: Date()))
        }
        if let actor = event?.actor {
            parts.append(String(
                format: NSLocalizedString(
                    "loads.detail.timeline.a11y.card.actor",
                    value: "by %@",
                    comment: "Phase 9 timeline current-card a11y — actor display name suffix."
                ),
                actor.displayName
            ))
        }
        if let hint = Self.nextMilestoneHint(for: currentStatus) {
            parts.append(hint)
        }
        return parts.joined(separator: ". ")
    }

    /// Spoken form for a LoadStatus (for VoiceOver only — distinct from
    /// the visible uppercase pill label).
    private static func a11ySpoken(for status: LoadStatus) -> String {
        switch status {
        case .posted:     return NSLocalizedString("loads.detail.timeline.a11y.spoken.posted",     value: "Posted",     comment: "Phase 9 timeline a11y spoken — posted.")
        case .tendered:   return NSLocalizedString("loads.detail.timeline.a11y.spoken.tendered",   value: "Tendered",   comment: "Phase 9 timeline a11y spoken — tendered.")
        case .accepted:   return NSLocalizedString("loads.detail.timeline.a11y.spoken.accepted",   value: "Accepted",   comment: "Phase 9 timeline a11y spoken — accepted.")
        case .dispatched: return NSLocalizedString("loads.detail.timeline.a11y.spoken.dispatched", value: "Dispatched", comment: "Phase 9 timeline a11y spoken — dispatched.")
        case .inTransit:  return NSLocalizedString("loads.detail.timeline.a11y.spoken.in_transit", value: "In transit", comment: "Phase 9 timeline a11y spoken — in transit.")
        case .delivered:  return NSLocalizedString("loads.detail.timeline.a11y.spoken.delivered",  value: "Delivered",  comment: "Phase 9 timeline a11y spoken — delivered.")
        case .cancelled:  return NSLocalizedString("loads.detail.timeline.a11y.spoken.cancelled",  value: "Cancelled",  comment: "Phase 9 timeline a11y spoken — cancelled.")
        case .draft:      return NSLocalizedString("loads.detail.timeline.a11y.spoken.draft",      value: "Draft",      comment: "Phase 9 timeline a11y spoken — draft.")
        case .rejected:   return NSLocalizedString("loads.detail.timeline.a11y.spoken.rejected",   value: "Rejected",   comment: "Phase 9 timeline a11y spoken — rejected.")
        case .expired:    return NSLocalizedString("loads.detail.timeline.a11y.spoken.expired",    value: "Expired",    comment: "Phase 9 timeline a11y spoken — expired.")
        case .podCaptured: return NSLocalizedString("loads.detail.timeline.a11y.spoken.pod_captured", value: "POD captured", comment: "Phase 9 timeline a11y spoken — POD captured.")
        case .invoiced:   return NSLocalizedString("loads.detail.timeline.a11y.spoken.invoiced",   value: "Invoiced",   comment: "Phase 9 timeline a11y spoken — invoiced.")
        case .funded:     return NSLocalizedString("loads.detail.timeline.a11y.spoken.funded",     value: "Funded",     comment: "Phase 9 timeline a11y spoken — funded.")
        }
    }

    // MARK: - Test seams (@testable import validationLedger)

    /// Snapshot tests need access to the 6 pill subviews to assert the
    /// per-state DS-token styling. Returning a copy of the array keeps
    /// callers from mutating internal state.
    internal func _testPillViews() -> [UIView] {
        return pillViews
    }

    /// Snapshot tests need to assert Row 3 is hidden on the terminal
    /// `.delivered` path (UI-SPEC line 324).
    internal func _testRow3IsHidden() -> Bool {
        return row3NextMilestone.isHidden
    }

    /// Snapshot tests need to read the Row 3 text on the
    /// terminal-cancelled path (UI-SPEC line 325 — locked copy).
    internal func _testRow3Text() -> String? {
        return row3NextMilestone.text
    }
}
