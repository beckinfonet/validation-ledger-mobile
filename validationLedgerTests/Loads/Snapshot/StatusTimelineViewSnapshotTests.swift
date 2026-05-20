// validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift
//
// Phase 9 Plan 05 Task 1 (TDD GREEN target) — populated suite locking the
// `StatusTimelineView` (D-17 6-pill stepper + current-state expanded card)
// against the Phase 7 `Load.stateHistory` payload + the D-18 architectural
// separation (side-states are NOT surfaced).
//
// Wave 0 shell was created by Plan 02 as 7 XCTSkip stubs. This file replaces
// those with 8 real test methods (per the plan's acceptance criteria —
// ≥7 methods; 6 primary lifecycle states + cancelled terminal + the D-18
// side-state-rejected gate).
//
// === D-18 reminder (side-states are intentionally invisible on the timeline) ===
// The timeline is a LOGISTICS surface; the trust-graph is the FRAUD surface.
// `pickCurrentStatus(from:)` walks history in REVERSE and returns the most
// recent event whose status is in the primary-lifecycle set (or is the
// terminal `.cancelled` side-state). Side-states `.rejected` / `.expired` /
// `.draft` / `.podCaptured` / `.invoiced` / `.funded` are skipped — the
// previous primary-lifecycle status remains "current". This is the
// architectural separation that the trust-graph + chain-integrity banner
// surface fraud signals SEPARATELY from the timeline.
//
// `test_sideStateRejectedDoesNotAdvanceStepper` is the explicit lock for the
// D-18 invariant — adding side-state rendering to the timeline must fail
// this test loudly. Re-read 09-CONTEXT D-18 before touching it.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.

import XCTest
@testable import validationLedger

class StatusTimelineViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// iPhone 17 portrait width (393pt) × ~200pt timeline-region height — the
    /// stable canvas Phase 9 RESEARCH §3 pins for snapshot determinism.
    private static let canvasSize = CGSize(width: 393, height: 200)

    /// Primary-lifecycle order (D-17). Index here = index in the stepper.
    private static let primaryLifecycle: [LoadStatus] = [
        .posted, .tendered, .accepted, .dispatched, .inTransit, .delivered,
    ]

    /// Build a synthetic `Load` whose `stateHistory` ends with a primary
    /// event of the given `status`, walking forward through the lifecycle
    /// prefix [.posted, .tendered, ..., status]. Each event carries a
    /// synthetic `LoadParty` actor with role `.broker`.
    private func makeLoad(endingAt status: LoadStatus) -> Load {
        // Build prefix of the lifecycle up to and including `status`.
        // For statuses NOT in primaryLifecycle (`.cancelled`), the caller
        // uses `makeLoad(history:)` directly.
        guard let idx = Self.primaryLifecycle.firstIndex(of: status) else {
            fatalError("makeLoad(endingAt:) only handles primary-lifecycle statuses; use makeLoad(history:) for side-state cases")
        }
        let prefix = Array(Self.primaryLifecycle[0...idx])
        // Hand-author monotonic timestamps so the renderer's
        // RelativeDateTimeFormatter has a stable reference point.
        var t = Date(timeIntervalSince1970: 1_780_000_000)
        let events: [LoadStatusEvent] = prefix.map { s in
            let event = LoadStatusEvent(status: s, timestamp: t, actor: Self.syntheticActor)
            t.addTimeInterval(3600)
            return event
        }
        return makeLoad(currentStatus: status, history: events)
    }

    /// Build a synthetic `Load` with a caller-supplied state history. Used
    /// for the side-state and terminal-cancelled paths.
    private func makeLoad(currentStatus: LoadStatus, history: [LoadStatusEvent]) -> Load {
        // The aggregate Load's `status` field is the canonical-lifecycle
        // position; for fixture-style stateHistory of side-states it may
        // diverge from history.last?.status (e.g. a rejected→returned-to-
        // posted load). For the timeline tests we set it to the
        // history's last event status for simplicity — the timeline
        // renderer reads stateHistory, not status, per D-02.
        return Load(
            id: "VL-SYNTH",
            referenceNumber: "REF-SYNTH",
            origin: LoadStop(city: "Dallas", state: "TX",
                             postalCode: "75201", country: "US"),
            destination: LoadStop(city: "Atlanta", state: "GA",
                                  postalCode: "30303", country: "US"),
            equipment: "dry_van",
            weight: 42500,
            rate: Decimal(2500),
            pickupAt: Date(timeIntervalSince1970: 1_780_500_000),
            deliverAt: Date(timeIntervalSince1970: 1_781_000_000),
            status: currentStatus,
            stateHistory: history,
            respondByAt: nil,
            tenderEligibility: nil
        )
    }

    private static let syntheticActor = LoadParty(
        partyID: "party-broker-synth",
        role: .broker,
        displayName: "Synthetic Broker"
    )

    /// Build and render the timeline at the canonical canvas size.
    private func renderedView(load: Load) -> StatusTimelineView {
        let view = StatusTimelineView()
        view.configure(load: load)
        view.bounds = CGRect(origin: .zero, size: Self.canvasSize)
        view.layoutIfNeeded()
        return view
    }

    /// Convenience: read the pill subview at the given index. Each pill is
    /// the test-introspection target whose backgroundColor + transform
    /// encode the per-state styling per UI-SPEC § Pill state styles.
    private func pillView(in view: StatusTimelineView, at index: Int) -> UIView {
        let pills = view._testPillViews()
        XCTAssertEqual(pills.count, 6,
                       "StatusTimelineView MUST expose exactly 6 stepper pills (D-17).")
        return pills[index]
    }

    /// Assert the pill at `index` has the COMPLETED treatment:
    /// `DS.Colors.surface` fill + no `+20%` transform.
    private func assertCompleted(_ view: StatusTimelineView, at index: Int,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let pill = pillView(in: view, at: index)
        XCTAssertEqual(pill.backgroundColor, DS.Colors.surface,
                       "Pill[\(index)] (completed) MUST use DS.Colors.surface background.",
                       file: file, line: line)
        XCTAssertEqual(pill.transform, .identity,
                       "Pill[\(index)] (completed) MUST NOT carry the +20% transform.",
                       file: file, line: line)
    }

    /// Assert the pill at `index` has the CURRENT treatment:
    /// `DS.Colors.primary` fill + `transform.scaleX == 1.2`.
    private func assertCurrent(_ view: StatusTimelineView, at index: Int,
                               file: StaticString = #filePath, line: UInt = #line) {
        let pill = pillView(in: view, at: index)
        XCTAssertEqual(pill.backgroundColor, DS.Colors.primary,
                       "Pill[\(index)] (current) MUST use DS.Colors.primary background (UI-SPEC line 302).",
                       file: file, line: line)
        // The +20% transform encodes the "draw-the-eye" current pill (UI-SPEC line 302).
        XCTAssertEqual(Double(pill.transform.a), 1.2, accuracy: 0.001,
                       "Pill[\(index)] (current) MUST carry the +20% scale transform.",
                       file: file, line: line)
    }

    /// Assert the pill at `index` has the FUTURE treatment:
    /// `.clear` fill + 1pt `DS.Colors.separator` border.
    private func assertFuture(_ view: StatusTimelineView, at index: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        let pill = pillView(in: view, at: index)
        XCTAssertEqual(pill.backgroundColor, .clear,
                       "Pill[\(index)] (future) MUST use .clear background.",
                       file: file, line: line)
        XCTAssertEqual(pill.layer.borderWidth, 1.0,
                       "Pill[\(index)] (future) MUST have a 1pt outline border.",
                       file: file, line: line)
        XCTAssertEqual(pill.transform, .identity,
                       "Pill[\(index)] (future) MUST NOT carry the +20% transform.",
                       file: file, line: line)
    }

    // MARK: - 6 primary-lifecycle stepper snapshots (D-17)

    func test_postedStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .posted))

        // Current = .posted (index 0). No completed pills before; all 5
        // others are future.
        assertCurrent(view, at: 0)
        for i in 1..<6 { assertFuture(view, at: i) }

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-posted-current", to: self)
    }

    func test_tenderedStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .tendered))

        assertCompleted(view, at: 0)
        assertCurrent(view, at: 1)
        for i in 2..<6 { assertFuture(view, at: i) }

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-tendered-current", to: self)
    }

    func test_acceptedStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .accepted))

        for i in 0..<2 { assertCompleted(view, at: i) }
        assertCurrent(view, at: 2)
        for i in 3..<6 { assertFuture(view, at: i) }

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-accepted-current", to: self)
    }

    func test_dispatchedStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .dispatched))

        for i in 0..<3 { assertCompleted(view, at: i) }
        assertCurrent(view, at: 3)
        for i in 4..<6 { assertFuture(view, at: i) }

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-dispatched-current", to: self)
    }

    func test_inTransitStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .inTransit))

        for i in 0..<4 { assertCompleted(view, at: i) }
        assertCurrent(view, at: 4)
        assertFuture(view, at: 5)

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-inTransit-current", to: self)
    }

    func test_deliveredStepper_currentStateRendersExpectedFrame() {
        let view = renderedView(load: makeLoad(endingAt: .delivered))

        // .delivered is the terminal happy-path state: all 5 prior pills
        // are completed, .delivered itself is the current (last) pill.
        for i in 0..<5 { assertCompleted(view, at: i) }
        assertCurrent(view, at: 5)

        // Per UI-SPEC § Terminal-state card content lines 322-324: Row 3
        // (next-milestone hint) is hidden when current is .delivered.
        XCTAssertTrue(view._testRow3IsHidden(),
                      "Terminal .delivered MUST hide Row 3 (no next-milestone projection — UI-SPEC line 324).")

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-delivered-current", to: self)
    }

    // MARK: - Terminal cancelled (side-state surfaced ONLY on Row 3 copy)

    func test_cancelledTerminalCard_rendersThisLoadWasCancelledCopy() {
        // .cancelled is a terminal side-state. Per UI-SPEC line 325, the
        // Row 3 copy reads "This load was cancelled." — NOT a projection.
        var t = Date(timeIntervalSince1970: 1_780_000_000)
        let history: [LoadStatusEvent] = [
            LoadStatusEvent(status: .posted,     timestamp: t, actor: Self.syntheticActor),
            LoadStatusEvent(status: .tendered,   timestamp: t.advanced(by: 3600),  actor: Self.syntheticActor),
            LoadStatusEvent(status: .accepted,   timestamp: t.advanced(by: 7200),  actor: Self.syntheticActor),
            LoadStatusEvent(status: .dispatched, timestamp: t.advanced(by: 10800), actor: Self.syntheticActor),
            LoadStatusEvent(status: .cancelled,  timestamp: t.advanced(by: 14400), actor: Self.syntheticActor),
        ]
        _ = t  // silence "var never mutated after assignment"
        let load = makeLoad(currentStatus: .cancelled, history: history)
        let view = renderedView(load: load)

        // Locked copy: Row 3 contains the lowercase substring "cancelled".
        let row3 = view._testRow3Text() ?? ""
        XCTAssertTrue(row3.lowercased().contains("cancelled"),
                      "Cancelled terminal MUST render the locked 'This load was cancelled.' copy in Row 3. Got: \(row3)")

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-cancelled-terminal", to: self)
    }

    // MARK: - D-18 architectural-separation gate

    /// Given history [posted, tendered, rejected]: rejected is a side-state
    /// and is skipped; current = .tendered (NOT .posted, and NOT advanced
    /// past .tendered). This locks the D-18 architectural separation: the
    /// timeline does NOT advance on side-states — only the trust-graph +
    /// chain-integrity banner surface fraud signals.
    func test_sideStateRejectedDoesNotAdvanceStepper() {
        var t = Date(timeIntervalSince1970: 1_780_000_000)
        let history: [LoadStatusEvent] = [
            LoadStatusEvent(status: .posted,   timestamp: t,                       actor: Self.syntheticActor),
            LoadStatusEvent(status: .tendered, timestamp: t.advanced(by: 3600),    actor: Self.syntheticActor),
            LoadStatusEvent(status: .rejected, timestamp: t.advanced(by: 7200),    actor: Self.syntheticActor),
        ]
        _ = t
        // The aggregate Load.status for a rejected-and-returned load is
        // typically `.posted` (D-04), but the timeline's current-pick logic
        // walks stateHistory in reverse — independent of Load.status.
        let load = makeLoad(currentStatus: .posted, history: history)
        let view = renderedView(load: load)

        // Per D-18: .rejected is skipped; .tendered (index 1) is current.
        assertCompleted(view, at: 0)                    // .posted
        assertCurrent(view, at: 1)                      // .tendered (current — NOT advanced past)
        assertFuture(view, at: 2)                       // .accepted
        for i in 3..<6 { assertFuture(view, at: i) }    // .dispatched / .inTransit / .delivered

        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: "StatusTimeline-sideStateRejected", to: self)
    }
}
