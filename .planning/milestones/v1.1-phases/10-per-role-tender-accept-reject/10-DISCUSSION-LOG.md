# Phase 10: Per-Role Tender / Accept / Reject - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-21
**Phase:** 10-per-role-tender-accept-reject
**Areas discussed:** Action-bar composition, Tender flow UX, Optimistic UI semantics, Action-failure exercise mechanism

User asked for plain language (no GSD/internal jargon) while discussing the four areas.

---

## Action-Bar Composition

### Q1 — Where the action buttons sit

| Option | Description | Selected |
|--------|-------------|----------|
| Pinned to the bottom | Bar locked to the bottom edge, always visible no matter how far you scroll. Like a checkout CTA. | |
| Inline in the scroll | Buttons sit inside the scrolling body, right after the status timeline. To act, you scroll to them. Quieter visually — doesn't compete with the chain-of-trust card up top. | ✓ |
| Floating button(s) | Floating action button hovering bottom-right. Modern and out of the way, but unusual on a freight app. | |

**Notes:** The action region lives INSIDE `LoadDetailBodyView` (not as a separate top-level region). Less composition surgery; sits next to the freight context.

### Q2 — Button layout when there are 2–3 actions

| Option | Description | Selected |
|--------|-------------|----------|
| Primary + secondary | One filled (main action) + one outlined (secondary). Clear visual hierarchy. | |
| Side-by-side equal weight | Both buttons same size, side by side. Treats reject/accept as equally weighted choices — matches the underlying fork semantics. | ✓ |
| Stacked, all primary | All buttons filled, stacked vertically full-width. Simplest, but costs hierarchy. | |

**Notes:** Destructive actions (Cancel / Reject) still get destructive tint — a UI-SPEC visual concern, not a layout concern.

### Q3 — Empty state when no legal actions

| Option | Description | Selected |
|--------|-------------|----------|
| Region disappears entirely | No buttons, no placeholder text — surrounding sections close up. | |
| Tasteful caption | Region still there, renders explanatory copy ("Load delivered. No actions available." / "View-only role."). | ✓ |
| Mixed | Disappear silently for Factoring, show caption for terminal states. | |

**Notes:** Region is ALWAYS in the body (consistent layout); content swaps between buttons and caption.

### Q4 — iPad split-layout placement

| Option | Description | Selected |
|--------|-------------|----------|
| Right pane, after the timeline | Same as iPhone — the action region is part of the body, body is the right pane, so identical iPhone/iPad logic — just rescales. | ✓ |
| Spanning bottom bar | iPad-only: action region promotes to a bar pinned to bottom spanning both panes. | |
| Floating on the graph | iPad-only floating action card hovers over the graph. | |

---

## Tender Flow UX

### Q1 — What happens when broker taps "Tender"

| Option | Description | Selected |
|--------|-------------|----------|
| Modal sheet with picker + deadline | Sheet slides up with carrier picker + date/time deadline + Send button. Cancellable. | ✓ |
| Two-tap with defaults | Defaults a carrier + deadline, shows confirm sheet you can adjust. | |
| Inline on the detail screen | Tender button expands inline (action region grows) to show the form. | |

### Q2 — Where the carrier list comes from

| Option | Description | Selected |
|--------|-------------|----------|
| Static demo directory fixture | New JSON fixture (`tender-carrier-directory.json`) + new mock endpoint. Same list for every load. Works on `.posted` loads (which have no carriers in the chain yet). | ✓ |
| Carriers on this load's chain | Read carrier TrustNodes from the already-loaded ChainOfTrust. Empty for `.posted` loads — the canonical happy path. | |
| Hardcoded in Swift | Small `let mockCarriers: [TrustNode] = [...]` in the picker view. Less consistent with fixture-driven mock approach. | |

### Q3 — ACTION-07 enforcement in the picker

| Option | Description | Selected |
|--------|-------------|----------|
| Visible but disabled, with reason | Unverified + flagged carriers appear in the list but are unselectable, with verification badge + inline reason ("Not verified — cannot tender"). | ✓ |
| Hidden entirely | Only verified carriers appear. Cleanest UI but misses the platform-thesis moment. | |
| Visible and selectable, blocked on confirm | All carriers selectable; Send button hard-disables on unverified pick. | |

**Notes:** This is also the platform-thesis surface for v1.1 — where the broker meets "identity that cannot be spoofed."

### Q4 — Deadline picker UX

| Option | Description | Selected |
|--------|-------------|----------|
| Preset chips + custom | Quick-pick chips (1h / 4h / 24h / 48h) + Custom… opens full UIDatePicker. Default chip is 24h. | ✓ |
| Full date/time picker only | UIDatePicker only. More precise but slower for the common case. | |
| Hours-from-now slider | Slider 1–72h with resolved time below. Unusual on iOS. | |

---

## Optimistic UI Semantics

### Q1 — In-flight behavior before server responds

| Option | Description | Selected |
|--------|-------------|----------|
| Action region only locks | Tapped button spins; all action buttons disable; rest of screen stays put. On 200 screen swaps to new state at once. | |
| Full screen predicts | Status, timeline, action set all visually advance immediately. On error the whole screen rolls back + error shows. | ✓ |
| Pessimistic with full overlay | Full-screen modal spinner blocks the screen until response. | |

**Notes:** The bolder UI choice. Means the screen has a `predicted: Load` state during in-flight.

### Q2 — Chain-of-trust card during predict

| Option | Description | Selected |
|--------|-------------|----------|
| Predict load only, freeze the chain card | Chain stays exactly as it was; swaps to fresh chainOfTrust on 200. | |
| Predict load + chain together | Predict the chain too (e.g. add a faint predicted edge). Heavy state machine; chain is the trust surface so wrong-prediction risk is highest there. | |
| Subtle "updating…" overlay on the chain | Chain stays at pre-tap state, renders with low-opacity refresh indicator. Signals "this card will refresh" without making any trust claim. | ✓ |

**Notes:** Architecturally honest — load state is the client's to predict; trust is the server's to confirm.

### Q3 — Failure display when state rolls back

| Option | Description | Selected |
|--------|-------------|----------|
| Inline error in the action region | Localized one-line error near the buttons + Try again button. | |
| Top toast / banner | Brief banner slides down from the top, auto-dismisses after ~3-4s. | ✓ |
| Alert dialog | UIAlertController blocks the screen. Heaviest interaction. | |

**Notes:** Generic localized copy ONLY — server-supplied error text never reaches the screen.

### Q4 — List refresh after action on pop-back

| Option | Description | Selected |
|--------|-------------|----------|
| Re-fetch on pop-back | Existing `viewWillAppear → fetchLoads()` handles it. Zero new wiring. Costs one round-trip. | ✓ |
| Push update from detail back to list | Cross-VM coupling / observer pattern. Snappier but introduces a custom channel. | |
| Both — push then re-fetch as backup | Push immediately + re-fetch in background. Best of both, most code. | |

---

## Action-Failure Exercise Mechanism

### Q1 — How QA triggers the 409/422/500 paths

| Option | Description | Selected |
|--------|-------------|----------|
| Launch-arg toggles (DEBUG-only) | `-MockActionConflict409`, `-MockActionValidation422`, `-MockActionServerError500`. Same pattern as `-MockKYCStatusVerified` / `-Mock2DTrustGraphOnIPhone`. | ✓ |
| DEBUG dev menu (in-app) | Hidden gesture / dev tab. More discoverable but adds in-app UI. | |
| Per-fixture XCUITest only | Test-code only; no way to feel the rollback during hand-held UAT. | |

### Q2 — How to see the in-flight state on real hardware

| Option | Description | Selected |
|--------|-------------|----------|
| Pair the failure toggles with a latency toggle | `-MockActionLatencySlow` (~1.5s). Combined with a failure toggle so the predict + chain overlay + rollback are all visible. | ✓ |
| Always inject latency in DEBUG | Fixed delay in every DEBUG build. Slows down every dev iteration. | |
| No latency in dev | Skip — device UAT won't see the optimistic middle frame. | |

---

## Claude's Discretion

These were noted as planner-finalized without re-asking the user:

- Exact `LoadActionsView` class structure / file partitioning
- Exact `TenderSheetViewController` partitioning (one file vs. picker + deadline subviews)
- Exact carrier-directory endpoint path + RequestBody/Response struct shape
- Exact carrier-directory fixture list (~6–8 carriers across the four VerificationState values)
- Static vs. live-updating respond-by countdown for carrier/dispatch's view of `.tendered`
- Exact toast banner taxonomy (per-action keys vs. single key with action-name interpolation)
- Exact predicted-state derivation `(Load, LoadAction) → Load` pure function
- Exact chain-overlay visual (opacity, spinner badge, animation timing)
- Destructive button tint (`DS.Colors.destructive` is the natural pick)
- Exact mock-toggle precedence when multiple failure flags are set
- Exact `-MockActionLatencySlow` interval (~1.5s indicative)
- Localization keys (UI-SPEC 10 finalizes namespace)
- VM state-enum exact case shape
- XCUITest coverage matrix

## Deferred Ideas

- Stable-idempotency-key replay for retry-on-failure
- Push-from-detail observer for instantaneous list refresh
- Live-updating respond-by countdown (vs. static)
- Multi-field load-creation form for `.post` (LOAD-F1)
- Tap-carrier-row in picker to push verification-basis sheet
- Audit-history surface for prior tenders/rejections/expiries
- Inline note field on action submissions
- Real backend tender/accept/reject
- Push notifications on tender received / tender response
- Background tender expiry handling on the client
