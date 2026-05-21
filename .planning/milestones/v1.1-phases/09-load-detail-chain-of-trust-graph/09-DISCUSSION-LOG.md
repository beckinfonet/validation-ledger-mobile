# Phase 9: Load Detail & Chain-of-Trust Graph - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-20
**Phase:** 9 — Load Detail & Chain-of-Trust Graph
**Areas discussed:** Screen composition, Graph layout & gestures, Tap surfaces & TRUST-04 scope, Fraud + timeline visual language

---

## Screen Composition

### Q1 — First frame on iPhone

| Option | Description | Selected |
|--------|-------------|----------|
| Graph dominates | Graph fills upper 60–70%; summary header pinned above (ref#, origin→destination, status badge); timeline + detail rows below the fold. | ✓ |
| Summary leads, graph below | Single vertical scroll: summary header → status timeline → trust graph in a tall section below. | |
| Balanced split | Summary + timeline in top third; graph in bottom two-thirds (fixed, non-scrolling). | |
| Two-panel segmented | UISegmentedControl swapping between "Overview" and "Trust Graph" panels. | |

**User's choice:** Graph dominates. The trust graph IS the screen — marquee posture.

### Q5 — Default zoom on graph open

| Option | Description | Selected |
|--------|-------------|----------|
| Fit-all-nodes tight | Auto-fits to make all present nodes as large as possible while showing every node + edge. | ✓ |
| Auto-zoom to flagged | Centers on the first flagged node/edge; falls back to fit-all if clean. | |
| Always centered + 1.0x | Natural geometry; no auto-zoom. | |
| Fit-all on iPhone, 1.0x on iPad | Form-factor-different defaults. | |

**User's choice:** Fit-all-nodes tight. Every load opens with the full trust picture.

### Q6 — iPad right pane content

| Option | Description | Selected |
|--------|-------------|----------|
| Full bill-of-lading | Pinned header → timeline → freight detail rows → parties inline → chain-integrity verdict. | ✓ |
| Timeline + verdict only | Trust signals first; freight metadata second. | |
| Mirror iPhone below-fold | Single source of layout truth. | |
| Summary card + nothing else | Minimal right pane; banner + verdict live inside the graph canvas. | |

**User's choice:** Full bill-of-lading. The whole load record, top to bottom, in the right pane on iPad.

---

## Graph Layout & Gestures

### Q2 — Gesture model

| Option | Description | Selected |
|--------|-------------|----------|
| Pan + pinch-to-zoom | UIScrollView w/ min=1.0, max=2.5; tap on node. | |
| Pan only, no zoom | Wider-than-screen canvas; horizontal pan reveals more. | |
| Fixed-fit, no pan/zoom | Single zoom level per device; only tap is interactive. | |
| Pinch zoom + double-tap reset | Pinch + two-finger pan; double-tap node → recenter+zoom; double-tap empty → reset. | ✓ |

**User's choice:** Pinch zoom + double-tap reset. Most polished feel; highest spike complexity.

### Q3 — Node positions

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed role slots | Hard-coded per role; missing roles simply absent. | ✓ |
| Fixture-supplied x/y | TrustNode carries x + y; iOS reads. | |
| Client-computed layered | Sugiyama-style topology layout at runtime. | |
| Hybrid: slots + fixture override | Default slots; optional TrustNode.x/y wins when supplied. | |

**User's choice:** Fixed role slots. Recognizable canvas — "I check the carrier spot for the red glow."

### Q4 — iPad layout

| Option | Description | Selected |
|--------|-------------|----------|
| Side-by-side split | Graph fills LEFT 60%; details in RIGHT 40% scrollable pane. | ✓ |
| Wider canvas, same composition | Single-column "graph dominates"; iPad gets wider/taller canvas. | |
| Split-view master/detail | UISplitViewController with load list sidebar. | |
| Two-pane segmented per iPhone | iPad behaves identically to iPhone. | |

**User's choice:** Side-by-side split. Best exploits the iPad form factor; satisfies "render natively, not just scale."

---

## Tap Surfaces & TRUST-04 Scope

### Q7 — TRUST-04 scope-trim call

| Option | Description | Selected |
|--------|-------------|----------|
| Ship both, full quality | TRUST-03 + TRUST-04 ship with the same surface treatment. | ✓ |
| Ship both, edge simpler | Node gets rich sheet; edge gets lighter inline tooltip. | |
| Pre-bake trim path | Ship node-tap only; defer edge-tap to follow-up. | |
| Ship both, defer if running long | Default ambition is both; explicit "if-late" cut in plan. | |

**User's choice:** Ship both at full quality. No trim, no defer.

### Q8 — Tap surface kind

| Option | Description | Selected |
|--------|-------------|----------|
| Modal sheet w/ detents | UISheetPresentationController .medium + .large; graph stays visible at .medium. | ✓ |
| Pushed full-screen VC | Standard nav push; loses graph context. | |
| Inline expand-in-place | Tapped node animates to card-state on canvas. | |
| Popover on iPad, sheet on iPhone | Form-factor-aware UIPopoverPresentationController. | |

**User's choice:** Modal sheet w/ detents. iOS 17-native; graph stays visible behind at medium detent.

### Q9 — Verification-basis sheet content

| Option | Description | Selected |
|--------|-------------|----------|
| All 4, always shown | All 4 facts as rows; "Not applicable" muted for Shipper/Factoring USDOT. | |
| Role-relevant only | USDOT hidden for Shipper/Factoring. | |
| All 4 with prior-relationship LIST | All 4 + list of prior load IDs (contract extension). | |
| All 4 + chain-integrity reason | All 4 + "why this node is flagged" block when implicated. | |
| Other (combination) | Role-relevant + LIST + chain-integrity reason. | ✓ |

**User's choice:** Role-relevant facts + prior-relationship LIST + chain-integrity reason inline when implicated.

### Q10 — Contract extension approach

| Option | Description | Selected |
|--------|-------------|----------|
| Additive optional | Add priorRelationshipExamples?: [...] alongside the existing Int count. | |
| Replace count w/ list | Drop priorRelationshipCount: Int; replace with priorRelationships: [PriorRelationship]. | ✓ |
| Defer the list | Ship bare count for now; LIST in follow-up phase. | |

**User's choice:** Replace count with list. Phase 9 owns the Phase 7 contract evolution.

---

## Fraud + Timeline Visual Language

### Q11 — Marquee fraud signal (compromised load)

| Option | Description | Selected |
|--------|-------------|----------|
| Red glow + banner | Flagged node red halo + flagged edge red dashed + red banner. | |
| Red badge + verdict block | Existing VerificationBadgeView red state; verdict block below graph (not banner). | |
| Red + pulse + banner + dim others | All-in marquee: pulse + banner + dimmed cleans. | ✓ |
| Tier-by-verdict | Visual intensity scales with verdict (none/yellow/red). | |

**User's choice:** Red + pulse + banner + dim others. Theatrical fraud signal.

### Q12 — Verdict-tier behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Red for any non-clean | Treat caution and compromised identically. | |
| Yellow for caution, red for compromised | Same UI mechanics; color scales per verdict. | |
| Pulse only on compromised | Both verdicts get banner + glow + dim; pulse only on compromised. | ✓ |

**User's choice:** Pulse only on compromised. Pulse = "this is BAD"; color = "how bad."

### Q13 — Status timeline visual frame

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical timeline | Stacked rows with relative time + actor; mail-app pattern. | |
| Horizontal stepper | 6 connected pills; compact one-line. | |
| Hybrid: stepper + current expanded | Horizontal stepper on top + current state expanded card below. | ✓ |
| Vertical w/ side-state branches | Vertical timeline + indented branches for rejects/expiries. | |

**User's choice:** Hybrid stepper + current-state card. Quick overview + active context.

### Q14 — Side-states in timeline

| Option | Description | Selected |
|--------|-------------|----------|
| Inline caption | "Previously rejected once." caption under the stepper. | |
| Expandable history block | Disclosure "View full history (8 events)." | |
| Side-state chips above stepper | Tap "REJECTED ×2" chip → sheet of events. | |
| Don't surface side-states here | Stepper renders only primary lifecycle; audit-history is future concern. | ✓ |

**User's choice:** Don't surface side-states here. Architectural separation — trust-graph = fraud surface; timeline = logistics surface.

---

## Claude's Discretion

The user explicitly delegated to the planner / UI-researcher:

- Exact role-slot coordinates on the canvas (the geometry that makes the 5 fixed slots look balanced at fit-all-nodes-tight zoom on both iPhone and iPad split widths).
- Exact zoom animation curve + duration (~250ms ease-in-out indicative).
- Exact `maximumZoomScale` value (2.5 indicative).
- Exact pulse animation parameters on compromised nodes (~1.2s, 0.6→1.0 opacity indicative).
- Exact `PriorRelationship` field set on the new value type.
- Exact iPad split percentage (60/40 indicative).
- Exact `TrustNodeView` chrome (rounded square vs. circle), size, label placement.
- Edge-color rules when chain is clean but an individual edge is unverified.
- Banner copy template.
- Terminal-state card content (when load is delivered or cancelled).
- Whether row-tap from `LoadListViewController` wires through a coordinator pattern or direct push.

---

## Deferred Ideas

- Tap a prior-relationship row → push another LoadDetailVC (Phase 9 ships affordance, inert wiring).
- Audit-history view rendering side-states inline (explicitly deferred per D-18).
- Pull-to-refresh on load detail (future post-v1.1 with real-time updates).
- Map / live truck-location on detail (M3).
- Editable load fields (PROJECT.md OOS).
- Edge-color rules for unverified edges in clean chains (UI-SPEC concern).
- Banner copy A/B variants (UI-SPEC + copywriting).
- Haptic feedback on node-tap and double-tap reset.

## Reviewed Todos (not folded)

- `device-ci-biometric-infra.md` — v1.0 device-CI infrastructure todo, matched on generic keywords; unrelated to a UI feature. Not folded (third consecutive review across Phases 7, 8, 9).
