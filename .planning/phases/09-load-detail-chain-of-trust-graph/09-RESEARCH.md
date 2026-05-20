# Phase 9: Load Detail & Chain-of-Trust Graph — Research

**Researched:** 2026-05-20
**Domain:** Custom-rendered, interactive UIKit node-graph hosted inside a composed iPhone/iPad detail screen — pinch+pan+double-tap gestures, CAShapeLayer edges + animated halos, VoiceOver-traversable accessibility container, `UISheetPresentationController` tap surfaces, snapshot-test posture, and a Phase 7 `TrustNode` contract refactor (`priorRelationshipCount: Int` → `priorRelationships: [PriorRelationship]`).
**Confidence:** HIGH on gesture arbitration, accessibility container model, sheet detents, and Codable contract refactor (verified against Apple docs, the in-repo Phase 7/8 precedents, and the in-repo v1.1 stack-research decisions). HIGH on snapshot-test posture (Phase 8 already shipped the hand-rolled `UIKitSnapshot.swift` helper that Phase 9 directly reuses). MEDIUM-HIGH on `CAShapeLayer` performance at the scale Phase 9 needs (5 nodes × 4 edges × 1 banner shimmer × ≤1 animated halo) — far below any documented performance cliff, but the in-repo `SkeletonLoadRowCell` Pitfall 1 ("animation gets stripped on lifecycle events") applies one-for-one to the pulse halo and is called out below.

This research is **not** meant to re-litigate CONTEXT.md design decisions. It is meant to ensure the planner has the right `<read_first>` citations, the right gotcha warnings in `<acceptance_criteria>`, and the right approach picked from the iOS literature when writing each task.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (22 — D-01 through D-22)

**Screen Composition (D-01..D-03)**
- **D-01:** Graph dominates iPhone (`horizontalSizeClass == .compact`), filling the upper ~60–70% of the screen as the focal region. Pinned summary header above; bill-of-lading scroll body below.
- **D-02:** iPhone below-the-fold = bill-of-lading scroll (status timeline → freight rows → parties inline → chain-integrity verdict block).
- **D-03:** iPad regular width = side-by-side split. Graph fills LEFT ~60% fixed canvas; RIGHT ~40% pane = bill-of-lading content. Branches on `traitCollection.horizontalSizeClass`.

**Graph Interaction Model (D-04..D-06)**
- **D-04:** Pinch zoom + double-tap recenter. `TrustGraphView` inside `UIScrollView` with `minimumZoomScale=1.0`, `maximumZoomScale=2.5`. Native two-finger pan + pinch. Separate `UITapGestureRecognizer(numberOfTapsRequired: 2)` for double-tap-recenter (scale ~1.8x on node, reset on empty canvas, ~250ms ease-in-out). Single-tap on node opens TRUST-03 sheet; single-tap on edge opens TRUST-04 sheet. **Resolves ROADMAP spike item (b).**
- **D-05:** Default zoom = fit-all-nodes tight. Whole chain visible at-a-glance on first frame.
- **D-06:** Fixed role slots. shipper top-left / broker upper-center / carrier center / dispatch right-of-carrier / factoring bottom-right. Same normalized geometry rescaled for iPhone-tall vs. iPad-wide. **Resolves spike item (d).**

**Tap Surfaces (D-07..D-08)**
- **D-07:** TRUST-03 (node-tap) AND TRUST-04 (edge-tap) both ship at full quality. No trim. ROADMAP's edge-tap scope-trim is rejected.
- **D-08:** Both tap surfaces use `UISheetPresentationController` with `[.medium, .large]` detents. At `.medium` the graph stays visible behind the sheet (`largestUndimmedDetentIdentifier = .medium`). On iPad renders as a floating card.

**Verification-Basis Sheet Content (D-09..D-11)**
- **D-09:** Role-relevant facts only. KYC (everyone), Device-binding (everyone), USDOT (Carrier + Dispatch ONLY — row HIDDEN for Shipper/Factoring), Prior relationships (everyone).
- **D-10:** Prior relationships rendered as tappable LIST (chevron affordance), NOT a count. Row tap is inert in Phase 9 (deferred).
- **D-11:** Chain-integrity reason rendered inline only when this node's `partyID ∈ implicatedNodeIDs`.

**Phase 7 Contract Evolution (D-12..D-14) — Phase 9 owns this**
- **D-12:** **Breaking change.** `TrustNode.priorRelationshipCount: Int` replaced by `TrustNode.priorRelationships: [PriorRelationship]`. Same posture as Phase 8 D-02 (`[Load]` → `[LoadListItem]`).
- **D-13:** New `PriorRelationship` value type at `validationLedger/Core/Load/PriorRelationship.swift`. Pure `Decodable & Sendable`. Indicative fields: `loadID: String`, `occurredAt: Date`, `counterpartyRole: Role`, `counterpartyDisplayName: String?`. Wire mapping under `.convertFromSnakeCase`; explicit `CodingKey` only for `loadID` (trailing-acronym field — raw value `"loadId"`).
- **D-14:** Phase 7 fixture re-authoring is a Phase 9 deliverable. Every `load-detail-VL-*.json` fixture: `prior_relationship_count` → `prior_relationships: [...]` on every `TrustNode`, with realistic prior-load history. Fraud archetypes get curated history (chameleon carriers: 0 priors; clean carriers: 5+).

**Fraud Visual Language (D-15..D-16)**
- **D-15:** Tiered visual response. `clean` → no chrome. `caution` → yellow banner + yellow static halo + yellow dashed edges + dim-others. `compromised` → red banner + red pulse halo (`opacity 0.6→1.0`, `1.2s`, `easeInEaseOut`, infinite repeat) + red dashed edges + dim-others. **Pulse is the "this is BAD" tell; color is the "how bad" tell.** **Resolves spike item (a).**
- **D-16:** Banner is fixed (never scrolls away). Verdict block in body is a separate scrollable second-render of same data. Duplication is intentional.

**Status Timeline (D-17..D-18)**
- **D-17:** Hybrid 6-pill horizontal stepper + current-state expanded card. Renders from `Load.stateHistory`.
- **D-18:** Side-states (rejected/expired/cancelled) NOT surfaced. Architectural separation: trust-graph = fraud surface; timeline = pure logistics. A previously-rejected-then-retendered load looks identical to a clean one in the timeline.

**Loading / Error States (D-19..D-20)**
- **D-19:** Skeleton-with-shimmer for `.loading`. Follows Phase 8 D-10 app-wide pattern. iPad skeleton mirrors split layout.
- **D-20:** No `.empty` state. State machine is `.loading` → `.loaded(load, chainOfTrust)` → `.error(message)`. Error = `UIContentUnavailableView`. Server error text NEVER reaches screen.

**VoiceOver / Accessibility (D-21..D-22) — Resolves spike item (c)**
- **D-21:** Traversal order locked. iPhone: pinned header → banner → graph (as one container) → timeline → freight rows → parties → verdict block. iPad: banner → right pane FIRST → left pane (graph) SECOND. Rotor pre-jump to graph supported.
- **D-22:** Graph accessibility container. `TrustGraphView.isAccessibilityElement = false`; `accessibilityElements` = ordered array of node views (role order: shipper → broker → carrier → dispatch → factoring) followed by edge invisible-companion views (deterministic `(fromPartyID, toPartyID)` lex order). Each child sets `accessibilityTraits = .button` so VoiceOver double-tap activates the sheet. **Pinch-zoom DISABLED while `UIAccessibility.isVoiceOverRunning == true`** (set `minimumZoomScale = maximumZoomScale = 1.0`; re-enable via `UIAccessibility.didChangeNotification` observer). Reduce-motion suppresses pulse (`UIAccessibility.isReduceMotionEnabled`).

### Claude's Discretion

- Exact role-slot coordinates (UI-SPEC pins them: iPhone `(0.18,0.18) (0.50,0.30) (0.50,0.55) (0.82,0.55) (0.50,0.85)`; iPad split-left `(0.18,0.22) (0.40,0.30) (0.50,0.55) (0.78,0.45) (0.82,0.78)` — normalized 0..1).
- Exact zoom animation curve and duration (UI-SPEC: `0.25s` ease-in-out; `1.8x` zoom on double-tap-node).
- Exact `maximumZoomScale` (`2.5`).
- Exact pulse animation parameters (`1.2s`, opacity `0.6→1.0→0.6`, `easeInEaseOut`, `repeatCount = .infinity`).
- Exact `PriorRelationship` field set (indicative D-13 — planner finalizes).
- iPad split-percentage (`60/40` locked in UI-SPEC).
- Node visual chrome (UI-SPEC: rounded square `cornerRadius 12pt`, `0.5pt` separator border, halo inset `-6pt`).
- Edge-color rules for `.unverified` edges in `.clean` chains (UI-SPEC default: solid neutral-grey regardless of per-edge state).
- Banner copy template (UI-SPEC: "Risk flagged: {reason}" / "Chain compromised: {reason}").
- Terminal-state card content (UI-SPEC: `delivered` hides row-3; `cancelled` shows "This load was cancelled.").
- Sheet detent configuration (UI-SPEC: `[.medium, .large]` for both tap surfaces).
- Coordinator pattern for list → detail navigation (CONTEXT recommends thin `LoadDetailCoordinator` to continue precedent).
- Wire-bridge for `prior_relationships` → `priorRelationships` handled by `APIClient.defaultDecoder()`'s `.convertFromSnakeCase`. Explicit `CodingKey` only for `loadID` on `PriorRelationship`.

### Deferred Ideas (OUT OF SCOPE)

- Tap a prior-relationship row to push another `LoadDetailVC` (Phase 9 ships inert affordance; wiring is a future-phase concern).
- Audit-history view rendering side-states inline on the timeline or as a disclosure (explicitly deferred per D-18).
- Pull-to-refresh on the detail screen (one-shot fetch in v1.1).
- Map / live truck-location pin (deferred to M3 background location).
- Editable load fields (PROJECT.md OOS).
- Edge-color rules for `.unverified` edges in `.clean` chains (UI-SPEC concern; defaults to solid neutral-grey).
- Banner copy A/B variants.
- Tap-to-recenter haptic feedback (small polish; planner may include or defer).
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **LOAD-05** | User can open a load detail screen from a load-list row | The Phase 8 `LoadListViewController` (already shipped) is currently inert on `collectionView(_:didSelectItemAt:)`. Phase 9 wires this hook to navigate to `LoadDetailViewController`. The `LoadDetailEndpoint(loadID:)` typed Phase 7 endpoint is already in tree (`validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift`); `APIClient.request<LoadDetailEndpoint>` returns `{ load: Load, chainOfTrust: ChainOfTrust }` in one round-trip. Coordinator-pattern precedent from `KYCCoordinator.swift` + `AppContainer.makeLoadListScreen(role:)` (see § Reference-Implementation Analogs). |
| **LOAD-06** | User sees a load status timeline on load detail (6-pill primary lifecycle) | `Load.stateHistory: [LoadStatusEvent]` from Phase 7 D-02 carries `{ status, timestamp, actor }`. Phase 9 renders the 6-pill stepper + current-state expanded card per D-17/D-18. Side-states NOT surfaced. Stepper pill colors come from `LoadStatusBadgeView`'s color ramp (reused); the current-pill uses `DS.Colors.primary` blue (logistics-progress signal, NOT fraud signal). |
| **TRUST-01** | User sees an interactive chain-of-trust graph on load detail | The phase's marquee deliverable. `TrustGraphView: UIView` containing one `TrustNodeView: UIView` per `TrustNode` and one `CAShapeLayer` per `TrustEdge`, hosted in `UIScrollView`. Pan via native scroll-view pan; pinch via native scroll-view pinch + delegate `viewForZooming`. Fixed role slots per D-06. v1.1 stack-research already ratified Option A (custom UIView + CAShapeLayer) over UICollectionView / SpriteKit / Grape (see § Standard Stack alternatives). |
| **TRUST-03** | User can tap a graph node to see verification basis | `VerificationBasisSheetViewController` opens via `UISheetPresentationController` with `[.medium, .large]` detents. Sheet content order per D-09/D-10/D-11. KYC + device-binding rows everyone; USDOT row Carrier + Dispatch only; Prior relationships LIST with chevron affordance; "Why this party is flagged" block conditional. |
| **TRUST-04** | User can tap a graph edge to see the handoff/tender detail | `HandoffDetailSheetViewController` opens via same `UISheetPresentationController` infrastructure. Sheet content: Handoff header + relationship-state row + tender-ref row + conditional "Why this handoff is flagged" block. Edge tap target is an INVISIBLE companion `UIView` overlaid on the edge's path (28pt band — the `CAShapeLayer` itself is non-interactive layer-only chrome). |
| **TRUST-05** | User sees double-/triple-brokering risk rendered on the graph | Fully driven by `ChainIntegrity.verdict` + `ChainIntegrity.implicatedNodeIDs` + `ChainIntegrity.implicatedEdgeIDs` + `ChainIntegrity.reason` from the fixture — NEVER computed client-side (Phase 7 D-18). The four-state visual language (D-15) renders `clean/caution/compromised` with the locked color/halo/dim/pulse semantics. Render-only — no derivation. |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- **UIKit-first, programmatic (no XIB / Storyboard).** Phase 9 is the most sensitive surface in v1.1 — SwiftUI is explicitly forbidden here. Every view is `UIView` / `UIViewController` / `CAShapeLayer` constructed programmatically.
- **SwiftPM only — Phase 9 adds ZERO new dependencies.** Confirmed against `Package.swift` (Nuke 13.0.2 + SwiftLintPlugins 0.63.2 — no other deps). The trust-graph rendering decision (`.planning/research/STACK.md` Option A) explicitly ratifies this: custom `UIView` per node + `CAShapeLayer` edges adds nothing new. `swift-snapshot-testing` is explicitly NOT added (see § Snapshot-Test Posture).
- **iOS 17 deployment minimum.** Every API Phase 9 needs is iOS-17-native: `UISheetPresentationController` with detents, `UIContentUnavailableView`, `largestUndimmedDetentIdentifier`, `prefersScrollingExpandsWhenScrolledToEdge`, modern `UIScrollView.zoom(to:animated:)`, `UIAccessibility.isVoiceOverRunning`, `UIAccessibility.isReduceMotionEnabled`.
- **iPad must render natively, not just scale.** D-03's side-by-side split layout (LEFT 60% graph + RIGHT 40% body) is the iPad-native contract; the same role-slot logic rescales (D-06).
- **Zero PII in analytics or crash logs.** No party `displayName`, `partyID`, or load `referenceNumber` reaches a `Logger.event(_:fields:)` call. Snapshot test artefacts use synthetic fixture data only (`UIKitSnapshot.swift` already enforces this — see § Snapshot-Test Posture).
- **All AI traffic backend-mediated** — N/A this phase (no AI surface).
- **DS tokens only** (`DS.Spacing.*`, `DS.Colors.*`, `DS.Typography.*`). UI-SPEC adds exactly **one** new public color member: `DS.Colors.caution = .systemYellow`. No new spacing or typography tokens.
- **GSD workflow enforcement** — every file change comes from a GSD command.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Trust-graph rendering (nodes, edges, halos, banner, dim-others) | iOS — `Features/Loads/Detail/TrustGraphView.swift` | — | UIKit `UIView` + `CAShapeLayer`. Read-only render of server data. Stack-research Option A. |
| Gesture arbitration (pinch / pan / single-tap / double-tap × outer scroll) | iOS — `TrustGraphView` + `UIScrollView` host + per-`TrustNodeView` recognizers | — | All recognizers live on the iOS view layer; no backend involvement. |
| Per-node verification basis text + icon mapping | iOS — `VerificationBasisSheetViewController` | — | Server supplies typed `TrustNode` facts (Phase 7 D-07); iOS controls presentation. |
| Edge handoff text + tender-ref rendering | iOS — `HandoffDetailSheetViewController` | — | Server supplies `TrustEdge.tenderRef` + `relationshipState`; iOS renders. |
| Chain-integrity verdict color / banner / halo / pulse | iOS — `ChainIntegrityBannerView` + `TrustGraphView` halo layers | — | `ChainIntegrity.verdict` + `ChainIntegrity.reason` + `implicated{Node,Edge}IDs` are server-supplied (Phase 7 D-08); iOS renders. NO client-side computation (Phase 7 D-18). |
| Status timeline pill rendering (6-pill stepper + current-state card) | iOS — `Features/Loads/Detail/StatusTimelineView.swift` | — | `Load.stateHistory` is server-supplied; iOS picks current status, hides side-states (D-18), maps to UI. |
| State machine (`.loading` / `.loaded(load, chainOfTrust)` / `.error(message)`) | iOS — `LoadDetailViewModel` | — | Single state enum + `didSet` callback mirrors `LoadListViewModel` precedent. |
| Skeleton-with-shimmer for `.loading` | iOS — `Features/Loads/Detail/LoadDetailSkeletonView.swift` | — | Mirrors Phase 8 `SkeletonLoadRowCell` pattern (`CAGradientLayer` + `CABasicAnimation` on `"locations"`). |
| Modal sheet presentation (TRUST-03 + TRUST-04) | iOS — `LoadDetailViewController.present(_:animated:)` | — | iOS-17-native `UISheetPresentationController` with `[.medium, .large]` detents. |
| Navigation: list-row tap → push detail VC | iOS — `LoadListViewController.collectionView(_:didSelectItemAt:)` + new `LoadDetailCoordinator` or factory closure | — | Continues the `KYCCoordinator` + `AppContainer.makeLoadListScreen(role:)` factory precedent. |
| Codable contract: `[PriorRelationship]` decode | iOS — `Core/Load/PriorRelationship.swift` + Phase 7 `ChainOfTrust.swift` (modified) | — | Pure value-type contract change. `.convertFromSnakeCase` handles `prior_relationships` → `priorRelationships`; explicit `CodingKey` only for `loadID`. |
| Fixture re-authoring | Test fixtures (`validationLedgerTests/Networking/Fixtures/load-detail-VL-*.json`) | — | D-14 deliverable. Phase 7's named-load library is the authoring frame. |
| Trust derivation, chain integrity computation | OUT OF SCOPE (server / fixture only) | — | Phase 7 D-18 — iOS is a passive renderer. |

---

## Standard Stack

### Core (in tree — Phase 9 adds **zero** new dependencies)

| Framework | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| UIKit | iOS 17 SDK | View hierarchy (VCs, `UIView`, `UIScrollView`, `UISheetPresentationController`, `UIContentUnavailableView`, `UIStackView`, gesture recognizers, hit-testing, Auto Layout) | [VERIFIED: in-tree Phase 8 `LoadListViewController` + Phase 4 `LimitedTrustBannerView` + Phase 5 `KYCStatusViewController` all UIKit-programmatic] CLAUDE.md UIKit-first mandate; in-repo `.planning/research/STACK.md` Option A ratified for the trust-graph. |
| QuartzCore / Core Animation | iOS 17 SDK | `CAShapeLayer` for edges + halos; `CABasicAnimation` for pulse + shimmer; `CAGradientLayer` for skeleton shimmer | [VERIFIED: in-tree `SkeletonLoadRowCell.swift` already uses the identical pattern Phase 9 needs] First-party framework; zero deps. |
| Foundation | iOS 17 SDK | `Decodable & Sendable` value types; `JSONDecoder` with `.convertFromSnakeCase` + `.iso8601`; `RelativeDateTimeFormatter`; `DateFormatter` | [VERIFIED: in-tree `APIClient.defaultDecoder()` already configured] First-party. |

### Phase 8 / Phase 7 Components Reused (zero modifications to the reused parts)

| Component | File | Phase 9 Usage |
|-----------|------|---------------|
| `VerificationBadgeView` | `validationLedger/UI/Components/VerificationBadgeView.swift` | Per-node inside `TrustNodeView`; per-edge inside `HandoffDetailSheetViewController`'s relationship-state row; per-party inline in the bill-of-lading body; sheet header. The 4-state ramp + fail-closed nil are LOCKED — Phase 9 must not re-implement the badge. |
| `LoadStatusBadgeView` | `validationLedger/UI/Components/LoadStatusBadgeView.swift` | Pinned summary header (top of detail VC); current-state expanded card row 1 (`StatusTimelineView`). The 13-state pill is LOCKED. |
| `DS.Spacing` | `validationLedger/UI/DesignSystem/Spacing.swift` | Every distance. Phase 9 uses only existing tokens (`xs/sm/md/lg/xl/xxl`). No new spacing tokens. |
| `DS.Colors` | `validationLedger/UI/DesignSystem/Colors.swift` | Every color. Phase 9 ADDS exactly one public member: `DS.Colors.caution = .systemYellow` (locked in UI-SPEC). `DS.Colors.destructive` gains documented secondary roles (compromised banner / halo / dashed edges). |
| `DS.Typography` | `validationLedger/UI/DesignSystem/Typography.swift` | Every label. No new typography tokens. |
| `UIKitSnapshot` | `validationLedgerTests/Support/UIKitSnapshot.swift` | The app-wide snapshot-test mechanism Phase 8 established. Phase 9 reuses it for `TrustGraphView`, `TrustNodeView`, `ChainIntegrityBannerView`, `StatusTimelineView`, and skeleton snapshot tests. (See § Snapshot-Test Posture for the full recipe.) |
| `LoadDetailEndpoint` | `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift` | Returns `{ load: Load, chainOfTrust: ChainOfTrust }` in one round-trip. UNCHANGED — Phase 9 consumes verbatim. |
| `Load` / `LoadStatus` / `LoadStatusEvent` | `validationLedger/Core/Load/*.swift` | UNCHANGED. |
| `ChainIntegrity` / `VerificationState` / `TrustEdge` | `validationLedger/Core/Load/*.swift` | UNCHANGED. (`TrustNode` is the only Phase 7 type Phase 9 modifies — see § Codable Contract Refactor.) |
| `MockURLProtocol` latency + forced-failure injectors | `validationLedger/Core/Networking/Mock/MockURLProtocol.swift` | Drives `.loading` skeleton + `.error` state without new test infra. UNCHANGED. |
| `MockLoadFixtureRegistry` | `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` | Phase 9 extends ADDITIVELY (one extra detail fixture for the dimmed-others rendering, planner discretion). |

### Alternatives Considered (already ratified in `.planning/research/STACK.md`)

| Instead of UIKit + CAShapeLayer (Option A) | Could Use | Why Phase 9 doesn't |
|--------------------------------------------|-----------|---------------------|
| Custom `UIView` per node + `CAShapeLayer` edges | `UICollectionView` with custom layout (Option B) | Awkward — collection views are for many recycled scrolling items; the graph has 5 fixed nodes. More code, more concepts, no benefit. |
| | SpriteKit (Option C) | **Disqualifying:** weak/partial VoiceOver support. Unacceptable for the product's core trust-verification surface. |
| | `Grape` (third-party SwiftPM, Option D) | **SwiftUI-only renderer** — violates UIKit-first on the most sensitive surface in v1.1. Force-directed simulation is the wrong tool for a fixed 5-node chain. Needs an unjustified dependency-shortlist exception. |
| | `swift-snapshot-testing` for snapshot tests | M1 deliberately did NOT adopt it. Phase 8 D-09 shipped the hand-rolled `UIKitSnapshot` helper (`UIGraphicsImageRenderer` + `view.layer.render(in:)` + `XCTAttachment`). Phase 9 reuses this without exception (see § Snapshot-Test Posture). |

**Installation:** None. `Package.swift` is unchanged.

**Version verification:** N/A — no external packages added or upgraded.

---

## Package Legitimacy Audit

**Not applicable for Phase 9.** Phase 9 installs zero new packages. `Package.swift` continues to declare exactly the two pre-approved dependencies (Nuke 13.0.2 + SwiftLintPlugins 0.63.2). Both were vetted at v1.0 milestone close and are unchanged.

| Package | Registry | Age | Source Repo | Disposition |
|---------|----------|-----|-------------|-------------|
| (none added in Phase 9) | — | — | — | — |

The slopcheck legitimacy gate is therefore vacuously satisfied — there are no new packages to check.

---

## 1. Gesture Arbitration on `TrustGraphView`

> Resolves CONTEXT D-04 (the marquee gesture-arbitration spike item (b)). This is the single highest-stakes technical question in Phase 9 — get this wrong and either the graph swallows the page scroll, or double-tap fires the wrong sheet, or VoiceOver double-tap-to-activate breaks.

### The four gesture surfaces (in arbitration priority)

| Surface | Recognizer | Owner | Behaviour |
|---------|-----------|-------|-----------|
| Inner `UIScrollView` two-finger pan | `UIScrollView.panGestureRecognizer` (native) | The graph's own `UIScrollView` | Pans only when `zoomScale > 1.0`. **Critical:** `panGestureRecognizer.minimumNumberOfTouches = 2`. This makes single-finger drags propagate to the OUTER page scroll view — the marquee "graph doesn't steal body scroll" guarantee. [CITED: Apple — `UIScrollView.panGestureRecognizer`](https://developer.apple.com/documentation/uikit/uiscrollview/pangesturerecognizer) |
| Inner `UIScrollView` pinch | `UIScrollView.pinchGestureRecognizer` (native) | The graph's own `UIScrollView` | Scales between `minimumZoomScale = 1.0` and `maximumZoomScale = 2.5`. Pinch inherently requires 2 fingers, so there's no propagation conflict. `viewForZooming` returns the `TrustGraphView`. |
| Double-tap on node (recenter+zoom) | `UITapGestureRecognizer(numberOfTapsRequired: 2)` attached to each `TrustNodeView` | The node | Animate-recenter+zoom to that node (~250ms ease-in-out, scale 1.8x). |
| Single-tap on node (open sheet) | `UITapGestureRecognizer(numberOfTapsRequired: 1)` attached to each `TrustNodeView` | The node | Opens `VerificationBasisSheetViewController`. **MUST** call `singleTap.require(toFail: doubleTap)` or the single-tap fires on the leading edge of every double-tap. |
| Single-tap on edge (open sheet) | `UITapGestureRecognizer(numberOfTapsRequired: 1)` attached to the edge's invisible companion `UIView` | The edge | Opens `HandoffDetailSheetViewController`. No double-tap on edges, so no `require(toFail:)` needed. |
| Double-tap on empty canvas (reset) | `UITapGestureRecognizer(numberOfTapsRequired: 2)` attached to `TrustGraphView`'s background | The graph | Resets zoom to fit-all-nodes-tight + center (~250ms ease-in-out). |
| Outer page-level `UIScrollView` (iPhone body) | Native single-finger pan | The bill-of-lading body | Single-finger vertical drags ALWAYS scroll the body. Two-finger drags hit the graph's `UIScrollView` instead. |

### The canonical recipe

```swift
// In TrustGraphView.setUp() or in LoadDetailViewController:
graphScrollView.delegate = self
graphScrollView.minimumZoomScale = 1.0
graphScrollView.maximumZoomScale = 2.5

// === Step 1 — outer scroll-view safety ===
// Two-finger-minimum on the graph's own scroll view means single-finger
// vertical drags propagate to the outer (bill-of-lading) UIScrollView.
graphScrollView.panGestureRecognizer.minimumNumberOfTouches = 2
graphScrollView.panGestureRecognizer.maximumNumberOfTouches = 2

// === Step 2 — single-tap MUST wait for double-tap to fail ===
let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
singleTap.numberOfTapsRequired = 1
let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
doubleTap.numberOfTapsRequired = 2

// CRITICAL: without this, the single-tap recognizer fires on the leading
// edge of every double-tap, opening the sheet right before the recenter
// animation tries to run. require(toFail:) is the textbook arbitration.
singleTap.require(toFail: doubleTap)

nodeView.addGestureRecognizer(singleTap)
nodeView.addGestureRecognizer(doubleTap)
```

[CITED: Apple — `UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldrecognizesimultaneouslywith:))

### Gotchas and tradeoffs

| Gotcha | Why it bites | Mitigation |
|--------|-------------|------------|
| **Tap fires on leading edge of double-tap.** Without `require(toFail:)`, every double-tap causes a 200ms-or-so single-tap → sheet-opens-then-animation-recenters-behind-it artifact. | `UITapGestureRecognizer` with `numberOfTapsRequired = 1` recognizes as soon as the touch ends, before the system knows whether a second tap is coming. | `singleTap.require(toFail: doubleTap)` on EVERY single-tap-on-node. Edges don't need it (no double-tap on edge). |
| **VoiceOver double-tap conflicts with our double-tap.** VoiceOver uses single-finger-double-tap as its "activate" gesture. If our recognizer is active during VoiceOver, VoiceOver's activate gesture either fires both or fires nothing. | D-22 mitigation: when `UIAccessibility.isVoiceOverRunning == true`, DISABLE the double-tap recognizers (`isEnabled = false`) AND set `minimumZoomScale = maximumZoomScale = 1.0`. The graph stays at fit-all-nodes-tight. Re-enable in `UIAccessibility.didChangeNotification` observer. | [VERIFIED: D-22 + Apple `UIAccessibility.isVoiceOverRunning` docs] |
| **Outer page scroll steals graph pan.** If the graph's `UIScrollView.panGestureRecognizer.minimumNumberOfTouches` is left at the default 1, every single-finger drag inside the graph region pans the graph (and the outer body cannot scroll past the graph region on iPhone). | Set `minimumNumberOfTouches = 2`. The graph is zoomable via pinch (2 fingers) and pannable via 2-finger drag; the user reaches the bill-of-lading body with a 1-finger drag. | Confirmed against Apple docs + in-repo `.planning/research/PITFALLS.md` Pitfall 2 ("gesture conflicts on the trust graph"). [VERIFIED: Apple `UIScrollView.panGestureRecognizer` docs + Phase 4-era research pitfall doc] |
| **Edge tap target is too thin.** `CAShapeLayer` strokes at 2pt are far smaller than the 44pt HIG touch-target floor. | UI-SPEC mitigation: each edge gets an INVISIBLE companion `UIView` overlaid on the edge's path, sized to a 28pt band (which gives 44pt+ diagonal at every realistic edge angle). The view carries the recognizer; the `CAShapeLayer` is layer-only chrome. | [VERIFIED: UI-SPEC § Edge tap target locks this geometry] |
| **`shouldRecognizeSimultaneouslyWith` overuse.** Returning `true` everywhere from the `UIGestureRecognizerDelegate` is the "make it work" hack that breaks scroll arbitration in subtle ways. | The recipe above uses ONLY `require(toFail:)` and the `minimumNumberOfTouches` knob. No `UIGestureRecognizerDelegate.shouldRecognizeSimultaneouslyWith` override is needed for Phase 9. If a future phase needs one, document why. | [CITED: Apple gesture-arbitration model] |
| **Double-tap on a node propagates to the empty-canvas double-tap.** If the user double-taps on a node, both the node's double-tap AND the canvas-background's double-tap could fire (recenter+zoom AND reset). | iOS gesture delivery normally stops at the deepest hit-tested view, so the node's recognizer wins. But: explicitly setting `cancelsTouchesInView = true` (default) on the node's double-tap is the belt-and-braces. | [VERIFIED: Apple `UIGestureRecognizer.cancelsTouchesInView` default behavior] |

### Acceptance criteria the planner should encode in tasks

- [ ] `graphScrollView.panGestureRecognizer.minimumNumberOfTouches == 2` set in `TrustGraphView.setUp()` AND verified by a unit test that reads the property after construction.
- [ ] Every single-tap recognizer on every `TrustNodeView` has `require(toFail: doubleTap)` called against the same node's double-tap recognizer.
- [ ] A unit test simulates: double-tap on `TrustNodeView` → assert that `VerificationBasisSheetViewController` was NOT presented AND `UIScrollView.zoomScale` advanced toward 1.8.
- [ ] A unit test simulates: single-tap on `TrustNodeView` → assert that `VerificationBasisSheetViewController` was presented after a `doubleTap.fail()` window.
- [ ] A UI test with `UIAccessibility.isVoiceOverRunning` toggled to true (via the `XCUIDevice` accessibility helpers) asserts that `graphScrollView.minimumZoomScale == graphScrollView.maximumZoomScale == 1.0`.
- [ ] An XCUITest scrolls the outer page body with a SINGLE-FINGER drag starting inside the graph region and asserts the body moved (proving the graph didn't swallow the gesture).

---

## 2. `CAShapeLayer` Performance + Animation Correctness

> The scale Phase 9 operates at — **5 nodes × 4 edges × 1 banner × ≤1 animated pulse halo at any given time** — is two orders of magnitude below any documented `CAShapeLayer` performance cliff. The bigger risk is the animation-lifecycle pitfall the in-repo `SkeletonLoadRowCell` already documents.

### What CAShapeLayer is good at — and where Phase 9 fits

| Property | Behaviour | Phase 9 implication |
|----------|-----------|---------------------|
| GPU-composited path rendering | `CAShapeLayer` strokes its `path` once per `path`/`bounds` change, then GPU composites it. Re-rendering is free for the lifetime of an unchanged path. | At default zoom + pinch, the edge paths recompute only when node positions change (which is on `layoutSubviews()` and on size-class transitions). The 4 edges are static at rest. |
| Transform handling | `CALayer.transform` (and `UIScrollView.zoomScale`-driven transform on the host view) is a free GPU operation. The path itself doesn't re-render. | **The pinch zoom does NOT require path re-rendering.** The `UIScrollView` scales the `TrustGraphView`'s `transform`; all CAShapeLayer paths come along for the ride. This is the marquee performance win of the layer-only edge approach. [CITED: [calayer.com — CAShapeLayer in Depth](https://www.calayer.com/core-animation/2016/05/22/cashapelayer-in-depth.html)] |
| Stroke widths at non-1.0 scale | A `2pt` stroke becomes `2 × zoomScale` points on screen — a 2.5x zoom paints a 5pt line, which looks heavy. | UI-SPEC's "constant in screen space (scaled inversely with zoom)" rule for edge strokes means the planner SHOULD recompute `strokeWidth = 2.0 / zoomScale` inside `scrollViewDidZoom(_:)`. The cleanest implementation: iterate the edge layers + set `lineWidth` per zoom change. (Alternative: leave it as-is and accept thicker strokes when zoomed in — UI-SPEC discretionary call.) |
| `shouldRasterize` | When `true`, the layer is rendered once to a bitmap and the bitmap is composited. Faster for static complex paths; SLOWER and BLURRY when the layer is transformed or animated. | **DO NOT set `shouldRasterize = true` on halo or edge layers.** The halo pulses (`opacity` animation) — rasterizing kills that. The graph pinch-zooms — rasterizing produces a blurry transform. The 5×4 scale doesn't need rasterization. [CITED: [Medium — 7 ways to speed up your UI on iOS](https://medium.com/@daniel_larsson/7-ways-to-to-speed-up-your-ui-on-ios-2d1be9bc11f0)] |
| `drawsAsynchronously` | Off-loads `-drawInContext:` calls to a background thread. Only helps `-drawInContext:`-heavy custom layers; `CAShapeLayer` already draws on GPU. | **N/A for Phase 9** — `CAShapeLayer` doesn't go through `-drawInContext:`. Setting it would do nothing useful and could mask real issues. |

### The pulse animation — the marquee fraud signal

```swift
// D-15: compromised verdict + node implicated → red halo + animated pulse.
// The halo is a separate CAShapeLayer, sibling-BELOW the chrome UIView in
// the TrustGraphView layer tree (so the chrome paints over it).
let halo = CAShapeLayer()
halo.path = UIBezierPath(roundedRect: nodeChromeFrame.insetBy(dx: -6, dy: -6),
                         cornerRadius: 12 + 6).cgPath  // matches chrome corner radius + halo inset
halo.fillColor = DS.Colors.destructive.cgColor
halo.opacity = 1.0  // resting state (snapshot test asserts this static frame)

let pulse = CABasicAnimation(keyPath: "opacity")
pulse.fromValue = 0.6
pulse.toValue = 1.0
pulse.duration = 1.2
pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
pulse.autoreverses = true            // 0.6 → 1.0 → 0.6 per cycle (1.2s each direction = 2.4s round trip)
                                     // OR set duration = 0.6 and autoreverses = true for a 1.2s round trip.
                                     // UI-SPEC D-15 specifies "1.2s loop, opacity 0.6→1.0, infinite repeat" —
                                     // planner picks the literal interpretation.
pulse.repeatCount = .infinity
pulse.isRemovedOnCompletion = false
halo.add(pulse, forKey: "pulse")
```

### The animation-lifecycle pitfall (`SkeletonLoadRowCell` already documented this)

> **This is the single most important non-obvious gotcha in `CAShapeLayer` + `CABasicAnimation` work, and it's already documented in the codebase at `SkeletonLoadRowCell.swift` lines 17–24:**
>
> *"Re-attach the animation in BOTH `prepareForReuse()` AND `layoutSubviews()` (RESEARCH §Pitfall 1 — the animation gets stripped on either lifecycle event; re-adding in only one of the two leaves the shimmer stuck on rotation / size-class change / cell-reuse)."*

For Phase 9, the analogous re-attach sites are:

| Event | Why animation may strip | Mitigation |
|-------|-------------------------|------------|
| `layoutSubviews()` on `TrustGraphView` | Bounds change (size-class transition iPhone→iPad split) re-runs the layer tree. Pulses can detach silently. | Iterate halo layers and re-add the `pulse` animation IF `halo.animation(forKey: "pulse") == nil` (the `SkeletonLoadRowCell` `startShimmer()` guard pattern). |
| `traitCollectionDidChange(_:)` | Compact→regular layout rebuild re-attaches the graph layer tree. | Re-attach via the same `startPulseIfNeeded()` helper called from layout. |
| Verdict change (e.g. fixture swap during a demo flow) | If a halo layer is removed + re-added without re-binding the animation, it goes static. | The verdict change rebuilds the halo layer set entirely; the new layers attach the animation in their construction path. |
| `UIAccessibility.isReduceMotionEnabled == true` | The pulse must be suppressed (D-22). | At construction time, check `UIAccessibility.isReduceMotionEnabled`; if true, skip the `halo.add(pulse, forKey: "pulse")` call but still set `halo.opacity = 1.0` so the color signal remains. Observer on `UIAccessibility.reduceMotionStatusDidChangeNotification` re-runs the construction path on change. [CITED: [Apple — `UIAccessibility.isReduceMotionEnabled`](https://developer.apple.com/documentation/uikit/uiaccessibility/isreducemotionenabled)] |
| `UIAccessibility.isVoiceOverRunning == true` | D-22 disables pinch-zoom; the pulse can stay (it's a color signal, not a gesture conflict). | No special handling needed — the pulse continues. |

### Pinch-zoom and CAShapeLayer paths

The marquee question: **when the user pinches to zoom, do the CAShapeLayer paths need re-rendering?**

**Answer: NO.** `UIScrollView` applies a CGAffineTransform to its `viewForZooming` view (the `TrustGraphView`). The `TrustGraphView`'s `CALayer` (and every sublayer including all the edge CAShapeLayers + halo CAShapeLayers) inherits the transform. The paths themselves are pre-rendered relative to the layer's bounds; the transform scales the rendered output on the GPU. This is the same mechanism that makes `UIImageView`-on-zoom buttery-smooth.

**The one exception:** stroke widths. A `lineWidth = 2.0` stroke at `zoomScale = 2.5` becomes 5pt on screen. UI-SPEC's "constant in screen space" rule means the planner SHOULD recompute `lineWidth = 2.0 / zoomScale` in `scrollViewDidZoom(_:)`. The arrowhead path (a 7pt × 7pt filled triangle) similarly should rescale, OR be drawn at a larger CGPath scale and let the transform shrink it. Pick one — UI-SPEC discretion.

### Banner shimmer (one banner, one CAGradientLayer)

The `ChainIntegrityBannerView` is **NOT** specified to shimmer in UI-SPEC. Re-reading UI-SPEC § Banner: it's a static rendered view (`isUserInteractionEnabled = false`). The skeleton's CAGradientLayer shimmer is the only shimmer in Phase 9 — and it's directly inherited from `SkeletonLoadRowCell`'s identical mechanism. There is no banner shimmer + halo pulse stacking pitfall.

### Acceptance criteria

- [ ] Halo CAShapeLayer is a SIBLING of the chrome UIView in `TrustGraphView`'s sublayer tree (NOT a subview of `TrustNodeView`) so the halo's pulse animation does not invalidate the node's own layout pass.
- [ ] `halo.opacity = 1.0` is set BEFORE `halo.add(pulse, forKey: "pulse")` — so if Reduce Motion is on (no animation added) the halo still renders at full opacity (color signal preserved).
- [ ] `startPulseIfNeeded()` helper guards re-attachment via `halo.animation(forKey: "pulse") == nil` (mirrors `SkeletonLoadRowCell.startShimmer()`).
- [ ] `traitCollectionDidChange(_:)` re-invokes `startPulseIfNeeded()` for every compromised halo layer.
- [ ] `UIAccessibility.reduceMotionStatusDidChangeNotification` observer re-runs the halo construction path.
- [ ] No `shouldRasterize = true` set anywhere on halo, edge, or banner layers (assert via a code-grep test).
- [ ] No `drawsAsynchronously = true` set anywhere on `CAShapeLayer` instances (assert via grep test).
- [ ] Snapshot test asserts the static frame `opacity = 1.0` (the upper bound), per UI-SPEC § Snapshot Test Posture. (See § Snapshot-Test Posture below.)

---

## 3. Snapshot-Test Posture for `TrustGraphView`

> **The team has already committed.** Phase 8 shipped `validationLedgerTests/Support/UIKitSnapshot.swift` — a hand-rolled `UIView → UIImage` baseline using `UIGraphicsImageRenderer` + `view.layer.render(in:)` + `XCTAttachment`. Phase 9 reuses it without exception. **No new SwiftPM dependency is added.**

### Why the hand-rolled approach (already locked)

`.planning/research/STACK.md` and Phase 8's `UIKitSnapshot.swift` file header BOTH explicitly ratify this:

> *"M1 did not adopt `swift-snapshot-testing` (it was MEDIUM-confidence in v1.0 STACK and never installed). v1.1 can verify graph rendering with `XCUITest` screenshot assertions or plain `Tests/` view-configuration unit tests instead — do **not** add `swift-snapshot-testing` solely for this. If the team later wants pixel snapshots broadly, that is a separate, milestone-level dependency decision, not a Load-Flows one."*

> *"`swift-snapshot-testing` (or any other snapshot library) is NOT on the pre-approved shortlist; the lowest-risk path is the iOS-bundled `UIGraphicsImageRenderer` + `view.layer.render(in:)` precedent already used by `KYCThumbnailTests.sampleJPEG(side:)`."* — `UIKitSnapshot.swift` lines 15–20

### The recipe (verbatim from `UIKitSnapshot.swift`)

```swift
import XCTest
@testable import validationLedger

class TrustGraphViewSnapshotTests: XCTestCase {

    func test_compromisedVerdict_iPhonePortrait_dynamicTypeLarge_rendersExpectedFrame() {
        let view = TrustGraphView()
        view.configure(chainOfTrust: .compromisedDoubleBrokeredFixture)
        // Set Dynamic Type via the override trait at the test level.
        // (TraitOverride pattern — see Phase 8 LoadRowCellSnapshotTests.)

        // Lay out + render to a deterministic CGSize.
        let image = UIKitSnapshot.image(
            of: view,
            size: CGSize(width: 393, height: 600)  // iPhone 17 portrait width × graph region height
        )
        UIKitSnapshot.attach(image, name: "TrustGraph-compromised-iPhonePortrait", to: self)

        // Layer-geometry assertions (more robust than pixel diffs for animated subjects):
        XCTAssertEqual(view.haloLayers.count, /* implicated node count */)
        for halo in view.haloLayers {
            XCTAssertEqual(halo.opacity, 1.0,
                "Static snapshot frame must lock halo at full opacity, not mid-pulse.")
            XCTAssertEqual(halo.fillColor, DS.Colors.destructive.cgColor,
                "Compromised verdict halo must be DS.Colors.destructive.")
        }
    }
}
```

### Options matrix — why hand-rolled wins

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. `UIKitSnapshot` (hand-rolled, already in tree)** | Zero new deps. Already proven on `VerificationBadgeView`, `LoadStatusBadgeView`, `LoadRowCell`, `SkeletonLoadRowCell`. PII-zero by construction (synthetic fixture data only). Attaches to `XCTestCase` so artefacts survive in the CI bundle for visual triage. | Pixel-diff comparison is not automated — the human reviews the attached image. (For Phase 9's deterministic-rendering scope this is acceptable; the snapshot tests function as VISUAL REGRESSION TRIAGE, not a pass/fail gate.) | ✅ **RECOMMENDED — already locked.** |
| **B. `pointfreeco/swift-snapshot-testing`** | Automated pixel-diff. Trait-collection overrides built-in. SwiftUI + UIKit + multi-device. | ❌ Not on the pre-approved dependency shortlist. ❌ Adding it would require explicit approval against CLAUDE.md's "Anything outside this list requires explicit approval." ❌ M1 milestone close explicitly decided NOT to adopt. ❌ `.planning/research/STACK.md` explicitly REJECTS adding it for this feature ("a broad snapshot-testing adoption is a separate, milestone-level decision, not a Load-Flows one"). | ❌ **REJECTED — locked.** |
| **C. Property-based assertions on layer geometry only (no image)** | No image artefact in CI; tests are fast. Robust to font-rendering jitter. | Loses the visual-triage value. A regression that doesn't change layer counts/colors (e.g. a stack-spacing token gets the wrong value) might pass. | ⚠️ **AS A COMPLEMENT.** Phase 9 should do BOTH: attach the image via `UIKitSnapshot.attach(_:name:to:)` (Option A) AND assert layer geometry / count / color (Option C). The two together catch both visual regressions (image) AND semantic regressions (geometry). |

### Snapshot test surface for Phase 9 (the 12-fingerprint budget UI-SPEC names)

Per UI-SPEC § Trust Graph Visual Language § Snapshot test posture: 3 verdicts × 2 devices × 2 Dynamic-Type sizes = **12 graph snapshots**, plus the per-component snapshots:

| Component | Snapshot count | Notes |
|-----------|---------------|-------|
| `TrustGraphView` | 12 (3 verdicts × iPhone-portrait + iPad-landscape-split × Large + XXXLarge) | Static frame of the pulse (`opacity = 1.0`). |
| `TrustNodeView` (per-verification-state × per-role) | ≤ 4 × 5 = 20 (planner trims to e.g. 4–6 representative) | Reuse the existing `VerificationBadgeView` snapshot fixtures. |
| `ChainIntegrityBannerView` | 2 (caution + compromised; clean is `isHidden`) | Per-verdict color + icon. |
| `StatusTimelineView` | 6 (one per primary-lifecycle current status) | Stepper + current-card. |
| `LoadDetailSkeletonView` | 2 (iPhone + iPad) | Mirrors `SkeletonLoadRowCellSnapshotTests` posture. |
| `VerificationBasisSheetViewController` | 4 (clean × Carrier; clean × Shipper; caution-implicated × Broker; compromised-implicated × Carrier) | Each fact row + the conditional "Why this party is flagged" block. |
| `HandoffDetailSheetViewController` | 3 (clean / caution-implicated / compromised-implicated) | Smaller surface; fewer fingerprints. |

### Acceptance criteria

- [ ] No `Package.swift` change. `Package.resolved` byte-identical after Phase 9.
- [ ] Every `*SnapshotTests.swift` file uses `UIKitSnapshot.image(of:size:)` and `UIKitSnapshot.attach(_:name:to:)`. No `import SnapshotTesting` anywhere.
- [ ] Every snapshot test that exercises a `compromised` verdict asserts `halo.opacity == 1.0` BEFORE rendering (so the snapshot captures the resting frame, NOT a mid-pulse animation frame).
- [ ] Every snapshot test uses synthetic fixture data (PII-zero per `UIKitSnapshot.swift` lines 22–27 threat-model note).

---

## 4. VoiceOver / Accessibility Container Patterns

> Resolves D-21/D-22. The technical question: how do you implement `accessibilityElements` on a parent `UIView` whose visual children are subviews, where each subview is independently tappable AND the parent itself swallows pinch/double-tap gestures?

### The canonical Apple recipe — for OUR use case

The relevant Apple model is the **"accessibility container"** pattern. Two layers of state are independent:

| Property | Semantics | Phase 9 setting |
|----------|-----------|-----------------|
| `isAccessibilityElement` on the parent | If `true`: parent IS an element; VoiceOver speaks the parent's label and IGNORES `accessibilityElements`. If `false`: parent IS NOT an element; VoiceOver traverses `accessibilityElements` instead. | **`false`** on `TrustGraphView`. |
| `accessibilityElements` on the parent | An ordered array of children (UIViews or `UIAccessibilityElement` synthetic elements) that VoiceOver traverses in order. | Ordered: 5 (or fewer) `TrustNodeView` in role order, then `TrustEdge` invisible companion views in `(fromPartyID, toPartyID)` lex order. |
| `isAccessibilityElement` on EACH child | If `true`: the child is a leaf element VoiceOver focuses + activates. | **`true`** on each `TrustNodeView` AND each edge invisible companion view. |
| `accessibilityTraits` on each child | Defines VoiceOver behaviour on activate. `.button` → VoiceOver's single-finger-double-tap fires the recognizer. | **`.button`** on every node and every edge. |
| `accessibilityLabel` on each child | The spoken description. | Per D-22 composition rule (see § Concrete recipe). |

### Why setting `isAccessibilityElement = false` + `accessibilityElements = [...]` is enough

[CITED: [createwithswift.com — Preparing your App for VoiceOver](https://www.createwithswift.com/preparing-your-app-for-voice-over-hiding-elements-from-the-accessible-interface/) + Apple `UIAccessibility` / `UIAccessibilityContainer` informal protocol]

The `UIAccessibilityContainer` informal protocol on `UIView` exposes `accessibilityElements` as a public property. Setting it directly is the supported path on iOS 17 — you do NOT need to override `accessibilityElementCount()` / `accessibilityElement(at:)` / `index(ofAccessibilityElement:)` (those are the older NSObject-level protocol surface, useful only for non-UIView containers or for synthesizing virtual elements).

The deque.com article that the search surfaced describes a DIFFERENT pattern (parent IS the element, children are absorbed into one combined label). **That's wrong for Phase 9.** Phase 9 wants each child individually focusable + activatable, which is the `isAccessibilityElement = false` + `accessibilityElements = [...]` pattern.

### Concrete recipe (per D-22)

```swift
// In TrustGraphView.setUp() or in didSet on `chainOfTrust`:

isAccessibilityElement = false  // CRITICAL: container, not leaf.
                                 // If this is true, accessibilityElements is ignored.

let orderedNodes: [TrustNodeView] = nodeViewsInRoleOrder()  // shipper, broker, carrier, dispatch, factoring
let orderedEdges: [UIView] = edgeCompanionViewsSortedByFromTo()  // (fromPartyID, toPartyID) lex
accessibilityElements = orderedNodes + orderedEdges  // D-22 traversal order

for nodeView in orderedNodes {
    nodeView.isAccessibilityElement = true
    nodeView.accessibilityTraits = .button
    nodeView.accessibilityLabel = composedNodeLabel(for: nodeView.node,
                                                    isImplicated: chainOfTrust.integrity.implicatedNodeIDs.contains(nodeView.node.partyID),
                                                    verdict: chainOfTrust.integrity.verdict)
}

for edgeCompanion in orderedEdges {
    edgeCompanion.isAccessibilityElement = true
    edgeCompanion.accessibilityTraits = .button
    edgeCompanion.accessibilityLabel = composedEdgeLabel(for: edgeCompanion.edge,
                                                          isImplicated: chainOfTrust.integrity.implicatedEdgeIDs.contains(edgeCompanion.edge.edgeID),
                                                          verdict: chainOfTrust.integrity.verdict)
}

// VoiceOver's "double-tap to activate" fires the .button trait → the
// regular single-tap codepath (which opens the sheet) runs. Same recognizer.
```

### The composed node label (D-22)

```text
"{Role display name}, {display name}, verification state: {state}, KYC {basis summary}, {implicated suffix if applicable}"
```

Concrete example: *"Broker, Acme Brokerage, verification state: verified, KYC verified 2 months ago, device bound."*

When implicated: *"... device bound. Implicated in chain compromise."* — the trailing sentence is the fraud signal in VoiceOver-readable form.

### Gotchas

| Gotcha | Why it bites | Mitigation |
|--------|-------------|------------|
| **`isAccessibilityElement = true` on container with `accessibilityElements` set.** VoiceOver IGNORES `accessibilityElements` when `isAccessibilityElement == true`. The parent gets spoken; children are invisible. | This is the #1 mistake in accessibility-container code. | Assertion test: `XCTAssertFalse(graphView.isAccessibilityElement)` after construction. |
| **Hit-test order ≠ accessibility-element order.** Subviews are added in arbitrary order (the layout engine may add them shipper-first, broker-second, …, OR carrier-first if it's added before the shipper). `accessibilityElements` must be ORDERED EXPLICITLY (D-22 role order), not derived from `subviews`. | Without an explicit ordered array, VoiceOver traverses in `subviews` order, which is layout-engine-dependent. | Build the `accessibilityElements` array from the `TrustNode.role` enum order, not from `subviews`. |
| **VoiceOver double-tap conflicts with our double-tap.** See § Gesture Arbitration above. D-22 mitigation: pinch-zoom + double-tap disabled while VoiceOver runs. | The recognizer's `isEnabled = false` is enough — VoiceOver's activate-gesture then drives the `.button` trait. | Observer on `UIAccessibility.didChangeNotification` toggles both `minimumZoomScale/maximumZoomScale` AND `doubleTap.isEnabled`. |
| **Edge invisible companion views still receive VoiceOver focus.** The 28pt band view IS a real view; VoiceOver doesn't know it's "invisible." Good — that's exactly what D-22 wants. | The companion is `accessibilityElement = true` with `.button` traits — VoiceOver-double-tap-to-activate fires the same tap recognizer the sighted user uses. | [VERIFIED: UI-SPEC § Edge tap target] |
| **The `accessibilityElements` array must be REGENERATED on verdict/data change.** If the array references node views that have been removed (e.g. the load now has 3 nodes instead of 5), VoiceOver will crash on the stale references. | Set `accessibilityElements` AFTER every layout/data update. | Call `applyAccessibilityElements()` in `didSet` on the `chainOfTrust` configuration property. |
| **Banner pinning order in the iPad split.** UI-SPEC says iPad reads right-pane-first. The traversal order is therefore: banner → right pane elements → left pane (graph). The view-controller-level `accessibilityElements` array must reflect this. | `LoadDetailViewController.view.accessibilityElements = [bannerOrNil, rightPaneContainer, leftPaneGraphContainer].compactMap{$0}` — order matters. | Mirror D-21 traversal order in the parent VC's `accessibilityElements` array. |

### Acceptance criteria

- [ ] `TrustGraphView.isAccessibilityElement == false` (assertion test).
- [ ] `TrustGraphView.accessibilityElements?.count == nodes.count + edges.count` after configuration.
- [ ] First N elements of `accessibilityElements` are `TrustNodeView` in the order `[shipper, broker, carrier, dispatch, factoring]` (absent roles skipped).
- [ ] Remaining elements are edge companion views in `(fromPartyID, toPartyID)` lex order.
- [ ] Each node's `accessibilityLabel` matches the D-22 composed-string template.
- [ ] Implicated nodes have ", Implicated in chain compromise." suffix; clean nodes do not.
- [ ] Each node's `accessibilityTraits == .button`.
- [ ] When `UIAccessibility.isVoiceOverRunning` is toggled true, `graphScrollView.minimumZoomScale == graphScrollView.maximumZoomScale == 1.0`.
- [ ] An XCUITest with VoiceOver simulated (via `XCUIElement.activate()` and `accessibilityActivate()`) presses each node and asserts the sheet opens.

---

## 5. `UISheetPresentationController` with `.medium` + `.large` Detents

> Resolves D-08. The canonical iOS-17 configuration to satisfy "sheet presented over the graph with graph remaining visible at `.medium`, expandable to `.large`."

### The canonical configuration

```swift
// In LoadDetailViewController, on node-tap or edge-tap:
let sheetVC = VerificationBasisSheetViewController(node: node, integrity: chainOfTrust.integrity)
sheetVC.modalPresentationStyle = .pageSheet  // iOS default for sheet presentations on iPhone

if let sheet = sheetVC.sheetPresentationController {
    sheet.detents = [.medium(), .large()]
    sheet.selectedDetentIdentifier = .medium        // open at .medium
    sheet.prefersGrabberVisible = true              // visual grabber affordance per UI-SPEC
    sheet.largestUndimmedDetentIdentifier = .medium // CRITICAL: at .medium, graph stays visible behind (no dim)
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false  // scrolling sheet content does NOT auto-promote to .large
                                                             // (UI-SPEC: user EXPLICITLY drags grabber to expand)
    sheet.prefersEdgeAttachedInCompactHeight = true  // iPhone landscape — sheet attaches to bottom edge
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
}

present(sheetVC, animated: true)
```

[CITED: [Apple — `UISheetPresentationController`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller) + [Filip Nemecek — How to configure UIKit bottom sheet with custom size](https://nemecek.be/blog/159/how-to-configure-uikit-bottom-sheet-with-custom-size)]

### Property-by-property semantics

| Property | iOS version | Phase 9 value | Why |
|----------|-------------|---------------|-----|
| `detents` | iOS 15+ | `[.medium(), .large()]` | D-08 locked. |
| `selectedDetentIdentifier` | iOS 15+ (programmatic), iOS 16+ (animated) | `.medium` | Opens at `.medium` per D-08 (graph stays visible). |
| `prefersGrabberVisible` | iOS 15+ | `true` | UI-SPEC: discoverable grabber so user knows the sheet is resizable. |
| `largestUndimmedDetentIdentifier` | iOS 15+ | `.medium` | **CRITICAL.** Without this, the sheet DIMS the graph behind at `.medium` (default behavior). Setting it to `.medium` means: at `.medium` (or smaller) the graph behind is undimmed and interactive; at `.large` the graph behind is dimmed (the user is reading the sheet — full focus). [CITED: Apple `largestUndimmedDetentIdentifier`] |
| `prefersScrollingExpandsWhenScrolledToEdge` | iOS 15+ | `false` | When `true` (default), scrolling sheet content to its edge auto-promotes the sheet from `.medium` to `.large`. UI-SPEC posture: the user dictates the detent via the grabber, not via scroll inertia. (This matters for the prior-relationships LIST in TRUST-03 — without `false`, scrolling to the bottom of a long list pops the sheet to `.large` mid-scroll.) [CITED: [SparrowCode — UISheetPresentationController](https://sparrowcode.io/en/tutorials/uisheetpresentationcontroller)] |
| `prefersEdgeAttachedInCompactHeight` | iOS 15+ | `true` | iPhone landscape: sheet attaches to bottom edge as a floating card rather than full-width attached. |
| `widthFollowsPreferredContentSizeWhenEdgeAttached` | iOS 15+ | `true` | Edge-attached sheet width matches content size. |
| `isModalInPresentation` | iOS 13+ | `false` (default) | UI-SPEC: dismissal via swipe-down-on-grabber or backdrop tap (both supported when `false`). |

### iPad floating-card behaviour (no extra config needed)

On iPad regular width, `UISheetPresentationController` automatically renders the sheet as a centered floating card (the system handles it — no API call). The accessibility identifier on the sheet's root view still works the same way. Phase 9 sets `accessibilityIdentifier = "load-detail.verification-basis-sheet"` or `"load-detail.handoff-detail-sheet"` on the sheet VC's root view, per UI-SPEC § Accessibility identifiers.

### iOS 17 noteworthy differences from iOS 15/16

- iOS 16 added the `.custom(_:resolver:)` detent for arbitrary heights — Phase 9 doesn't need this (the two stock detents are sufficient per D-08).
- iOS 17 added `UISheetPresentationController.Detent.heightResolutionContext` for adaptive detents based on `traitCollection`. Phase 9 doesn't need this either.
- No iOS 17 deprecations affect the API surface Phase 9 uses.

### Gotchas

| Gotcha | Why it bites | Mitigation |
|--------|-------------|------------|
| **Forgetting `largestUndimmedDetentIdentifier = .medium`.** Default behavior dims the presenting view behind the sheet at ALL detents. UI-SPEC's "graph stays visible at .medium" depends entirely on this property. | If the planner skips this, the marquee posture is broken — the user can't see the graph node they were just looking at. | Single-line acceptance criterion. |
| **Setting `.modalPresentationStyle = .formSheet` instead of `.pageSheet`.** `.formSheet` on iPhone is full-screen modal; the detent system only applies to `.pageSheet`. | `UISheetPresentationController` is a no-op when not in a `.pageSheet` context. | Use `.pageSheet` (or the default for sheets — `.automatic`). |
| **Setting detents on `sheetPresentationController` AFTER `present(_:animated:)`.** The detent change animates after, leaving a visible "snap." | The system gives a callback opportunity ONCE the sheet is created — but setting detents before `present(_:animated:)` is cleaner. | Set all sheet properties BEFORE calling `present(_:animated:)`. |
| **`prefersScrollingExpandsWhenScrolledToEdge = true` (default) with a long content list.** The user scrolls the prior-relationships list to its bottom, and the sheet promotes from `.medium` to `.large` mid-gesture — feels like a hijack. | UI-SPEC discretion lean toward `false` here so the grabber stays the explicit affordance. | Set `false` if the sheet has scrollable content (TRUST-03 with a long prior-relationships list). |

### Acceptance criteria

- [ ] `sheet.largestUndimmedDetentIdentifier == .medium` (assertion via reflection or via XCUITest visual: graph remains visible behind the sheet at `.medium` detent).
- [ ] `sheet.selectedDetentIdentifier == .medium` on first present.
- [ ] `sheet.prefersGrabberVisible == true`.
- [ ] `sheet.prefersScrollingExpandsWhenScrolledToEdge == false` for sheets with scrollable content.
- [ ] Accessibility identifier on the sheet's root view is `"load-detail.verification-basis-sheet"` or `"load-detail.handoff-detail-sheet"` per UI-SPEC.
- [ ] An XCUITest at iPhone portrait asserts that, after the sheet opens at `.medium`, the graph region is still hit-testable behind the sheet (proves `largestUndimmedDetentIdentifier == .medium` worked).
- [ ] iPad XCUITest asserts the sheet renders as a floating card (not full-screen).

---

## 6. `UIScrollView.viewForZooming(in:)` + `zoomScale` Recentering Math

> Resolves D-04 + D-05. The canonical recipe for "open at fit-all-nodes-tight; double-tap on node → animate to ~1.8x centered on that node; double-tap on empty canvas → reset."

### The `viewForZooming(in:)` delegate method

```swift
extension TrustGraphView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self  // the TrustGraphView is the zoomable content view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Optional: recompute edge lineWidth = 2.0 / scrollView.zoomScale
        // so strokes stay "constant in screen space" per UI-SPEC.
        // Also: re-attach pulse animations if a transform triggered detachment.
        startPulseIfNeeded()
    }
}
```

[CITED: [Apple — `UIScrollView.viewForZooming`](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:))]

### Default-zoom (fit-all-nodes-tight) recipe

```swift
override func layoutSubviews() {
    super.layoutSubviews()

    // 1. Compute bounding box of all node center coordinates in
    //    TrustGraphView-local coordinates.
    let boundingBox = boundingBoxOfAllNodeCenters()  // CGRect

    // 2. Inflate by chrome half-width + DS.Spacing.lg (24pt) on every side.
    let nodeRadius = nodeWidth / 2.0
    let inflated = boundingBox.insetBy(dx: -(nodeRadius + DS.Spacing.lg),
                                       dy: -(nodeRadius + DS.Spacing.lg))

    // 3. Compute the fit zoom (Auto Layout does this implicitly via constraints,
    //    OR explicitly by setting the inner content's frame).
    // The clean approach: lay out the node positions in normalized 0..1 coords,
    //    THEN multiply by canvas dimensions at layoutSubviews time. The fit-all-tight
    //    is then automatic — the canvas dimensions ARE the fit-all-tight container.
    // scrollView.zoomScale stays at 1.0; the user's pinch operates on top.

    // 4. Re-attach pulse animations on any halo layers that may have lost them
    //    in the layout pass.
    startPulseIfNeeded()
}
```

### Double-tap-on-node recenter math

```swift
@objc func handleDoubleTapOnNode(_ gr: UITapGestureRecognizer) {
    guard let nodeView = gr.view as? TrustNodeView else { return }

    let targetScale: CGFloat = 1.8  // UI-SPEC pin
    let nodeCenter = nodeView.center  // in TrustGraphView-local coordinates

    // Compute the destination rect for UIScrollView.zoom(to:animated:).
    // The rect is in CONTENT-VIEW coordinates (TrustGraphView's coordinate space)
    // — NOT screen / scrollView coordinates.
    //
    // We want a rect of size (scrollView.bounds.size / targetScale) centered on
    // nodeCenter. UIScrollView will then animate to that rect and clamp/center
    // appropriately.
    let visibleSize = CGSize(
        width: graphScrollView.bounds.width / targetScale,
        height: graphScrollView.bounds.height / targetScale
    )
    let targetRect = CGRect(
        x: nodeCenter.x - visibleSize.width / 2,
        y: nodeCenter.y - visibleSize.height / 2,
        width: visibleSize.width,
        height: visibleSize.height
    )

    UIView.animate(
        withDuration: 0.25,
        delay: 0,
        options: .curveEaseInOut,
        animations: {
            self.graphScrollView.zoom(to: targetRect, animated: false)
            // Note: zoom(to:animated:) animates internally; we wrap UIView.animate
            // around it ONLY to get the .curveEaseInOut curve. If the
            // default zoom-to animation curve looks good (it's roughly easeInOut),
            // call graphScrollView.zoom(to: targetRect, animated: true) directly
            // and skip the UIView.animate wrapper.
        }
    )
}
```

[CITED: [Apple — `UIScrollView.zoom(to:animated:)`](https://developer.apple.com/documentation/uikit/uiscrollview/1619388-zoom) + [TimOliver gist — Zooming to a specific CGPoint](https://gist.github.com/TimOliver/71be0a8048af4bd86ede)]

### Double-tap-on-empty-canvas reset

```swift
@objc func handleDoubleTapOnEmptyCanvas(_ gr: UITapGestureRecognizer) {
    UIView.animate(
        withDuration: 0.25,
        delay: 0,
        options: .curveEaseInOut,
        animations: {
            self.graphScrollView.setZoomScale(1.0, animated: false)
            self.graphScrollView.setContentOffset(.zero, animated: false)
        }
    )
}
```

### Edge cases

| Case | Behaviour | Mitigation |
|------|-----------|------------|
| **Zooming when content is larger than bounds.** At `zoomScale = 1.0` the graph is fit-all-tight (no overflow). Pinching to 1.8x makes content larger than bounds; `UIScrollView` clamps the contentOffset to keep content inside the scrollable area. | This is `UIScrollView`'s native behavior and is correct. | No mitigation needed. |
| **Double-tapping a node at the canvas EDGE.** The recenter math centers `targetRect` on the node, but `UIScrollView.zoom(to:)` clamps to the content area. The node may end up partway off-center if it's near an edge. | This is expected — `UIScrollView` does not place content outside its scrollable area. | Acceptable per UI-SPEC. |
| **Recenter animation jank during the pinch's velocity.** If the user double-taps DURING a pinch, the velocity from the pinch interferes with the recenter animation. | Disable double-tap recognition while `graphScrollView.pinchGestureRecognizer.state == .changed`. Or simpler: ignore the double-tap if the recenter animation would set the same scale. | Belt-and-braces: in `handleDoubleTapOnNode`, early-return if `abs(graphScrollView.zoomScale - targetScale) < 0.01` AND the targetRect overlaps the current visible rect by > 90%. |
| **`contentSize` not yet computed at first `layoutSubviews()`.** Fit-all-tight computation depends on the canvas dimensions; if the host view's layout hasn't completed, the canvas dimensions are wrong. | Defer the fit-all-tight calculation to a `setNeedsLayout()` + `layoutIfNeeded()` cycle. | Standard UIKit layout discipline — let `layoutSubviews()` run with valid `bounds.size`. |

### Acceptance criteria

- [ ] `graphScrollView.viewForZooming(in:)` returns the `TrustGraphView`.
- [ ] At first appearance, `graphScrollView.zoomScale == 1.0` AND all nodes are visible within the canvas without clipping.
- [ ] Double-tap on a node animates `graphScrollView.zoomScale` toward 1.8 over ~0.25s.
- [ ] Double-tap on empty canvas resets `graphScrollView.zoomScale` to 1.0 AND `contentOffset` to `.zero`.
- [ ] Snapshot test at zoom-1.8 (after a programmatic `setZoomScale(1.8, animated: false)`) renders an at-zoom node clearly.

---

## 7. Codable Contract Refactor: `PriorRelationship`

> Resolves D-12 + D-13 + D-14.

### The breaking change

```swift
// BEFORE (Phase 7, currently in tree at validationLedger/Core/Load/ChainOfTrust.swift:117):
public struct TrustNode: Decodable, Sendable {
    // ... other fields ...
    public let priorRelationshipCount: Int
    private enum CodingKeys: String, CodingKey {
        case partyID = "partyId"
        case role; case displayName; case verificationState
        case kycCompletedAt; case deviceBindingStatus
        case usdotNumber; case usdotAuthorityStatus
        case priorRelationshipCount
    }
}

// AFTER (Phase 9 D-12):
public struct TrustNode: Decodable, Sendable {
    // ... other fields ...
    public let priorRelationships: [PriorRelationship]
    private enum CodingKeys: String, CodingKey {
        case partyID = "partyId"
        case role; case displayName; case verificationState
        case kycCompletedAt; case deviceBindingStatus
        case usdotNumber; case usdotAuthorityStatus
        case priorRelationships  // ← REPLACES priorRelationshipCount
    }
}
```

### The new value type

```swift
// validationLedger/Core/Load/PriorRelationship.swift — NEW file
import Foundation

/// A prior load this party has shared with the inspecting party — surfaced in
/// the Phase 9 verification-basis sheet (TRUST-03 / D-10). Server-supplied;
/// iOS renders only.
///
/// Wire-format mapping under APIClient.defaultDecoder()'s .convertFromSnakeCase:
///   `load_id`                  → loadID (explicit CodingKey, raw value "loadId")
///   `occurred_at`              → occurredAt (synthesized; ISO 8601)
///   `counterparty_role`        → counterpartyRole (synthesized; Role rawValue)
///   `counterparty_display_name` → counterpartyDisplayName (synthesized)
///
/// Trailing-acronym convention matches Phase 7 TrustNode.partyID and Phase 7
/// TrustEdge.{edgeID, fromPartyID, toPartyID} — see ChainOfTrust.swift lines
/// 118-132 + 161-170 for the established pattern.
public struct PriorRelationship: Decodable, Sendable {

    /// The prior load's stable VL-#### reference number. Renders as "VL-1023"
    /// in the verification-basis sheet's prior-relationships list.
    public let loadID: String

    /// When this party last worked with the inspecting counterparty on a
    /// prior load. Renders as relative time ("3 months ago") via
    /// RelativeDateTimeFormatter.
    public let occurredAt: Date

    /// The OTHER party's role on that prior load — used to render the
    /// "Broker → Carrier" framing in the sheet row.
    public let counterpartyRole: Role

    /// The OTHER party's display name on that prior load. Optional — the
    /// framing renders without it ("Broker → Carrier"). Per UI-SPEC § Open
    /// Questions #1, the planner decides whether the sheet row renders
    /// "Broker → Carrier" or "Broker (Acme Brokerage) → Carrier".
    public let counterpartyDisplayName: String?

    /// Acronym bridge — see ChainOfTrust.swift TrustNode.CodingKeys for
    /// rationale. `loadID` is the only trailing-acronym field; the other
    /// three map cleanly under `.convertFromSnakeCase`.
    private enum CodingKeys: String, CodingKey {
        case loadID = "loadId"  // wire-key "load_id" → .convertFromSnakeCase → "loadId" → matches raw value
        case occurredAt
        case counterpartyRole
        case counterpartyDisplayName
    }
}
```

### Does `.convertFromSnakeCase` cleanly handle a nested array of structs with their own snake_case keys?

**YES — verified.** [CITED: [Sarunw — How to set custom CodingKey for convertFromSnakeCase decoding strategy](https://sarunw.com/posts/how-to-set-custom-codingkey-for-convertfromsnakecase-decoding-strategy/)]

The `.convertFromSnakeCase` strategy is applied **recursively** through the entire JSON tree. When `JSONDecoder` decodes a `TrustNode` containing a `prior_relationships: [...]` array:

1. The outer key `prior_relationships` is converted to `priorRelationships` and matched against `TrustNode.CodingKeys.priorRelationships`.
2. For each element in the array, `JSONDecoder` recursively decodes a `PriorRelationship`.
3. Inside each element, `load_id` is converted to `loadId`, which then matches `PriorRelationship.CodingKeys.loadID` (whose raw value is `"loadId"` — post-conversion form).
4. `occurred_at` → `occurredAt` (synthesized, no explicit CodingKey needed).
5. `counterparty_role` → `counterpartyRole` (synthesized).
6. `counterparty_display_name` → `counterpartyDisplayName` (synthesized).

**The critical rule** [VERIFIED via Sarunw docs + in-tree Phase 7 `ChainOfTrust.swift` pattern]: when `.convertFromSnakeCase` is enabled, explicit `CodingKeys` raw values must use the **camelCase post-conversion form**, NOT the wire snake_case form. So `loadID = "loadId"` is correct; `loadID = "load_id"` would NOT match.

### Wire fixture shape (the `D-14` re-authoring contract)

```json
{
  "nodes": [
    {
      "party_id": "party-carrier-001",
      "role": "carrier",
      "display_name": "Reliable Carriers Inc.",
      "verification_state": "verified",
      "kyc_completed_at": "2026-03-15T14:30:00Z",
      "device_binding_status": "bound",
      "usdot_number": "1234567",
      "usdot_authority_status": "active",
      "prior_relationships": [
        {
          "load_id": "VL-1019",
          "occurred_at": "2026-02-01T09:00:00Z",
          "counterparty_role": "broker",
          "counterparty_display_name": "Acme Brokerage"
        },
        {
          "load_id": "VL-1011",
          "occurred_at": "2025-12-15T11:00:00Z",
          "counterparty_role": "broker",
          "counterparty_display_name": "Acme Brokerage"
        }
      ]
    }
  ]
}
```

### Fixture-as-product-surface (D-14)

Per D-14: every existing `load-detail-VL-*.json` fixture is re-authored. The data is a **product surface**, not test scaffolding. Specifically:

- **Clean carriers (the "good guy" archetype)** carry 5+ prior relationships with the same broker — a recognizable trust history.
- **Chameleon carriers (the "bad guy" archetype — Phase 7 D-13(b))** carry 0 prior relationships — surfacing in the sheet as *"First time working together."* (UI-SPEC § Verification-basis sheet copywriting empty-state). The line itself is a fraud signal.
- **Double-brokered loads (the "worst guy" archetype — Phase 7 D-13(a))** carry a `flagged` carrier node where `priorRelationships.isEmpty` AND the `ChainIntegrity.verdict == .compromised` AND the carrier's `partyID ∈ implicatedNodeIDs`.

### Gotchas

| Gotcha | Why it bites | Mitigation |
|--------|-------------|------------|
| **`loadID = "load_id"` in CodingKeys raw value.** When `.convertFromSnakeCase` is enabled, the decoder converts the wire key FIRST, then matches against your CodingKey raw values. Raw value `"load_id"` will NEVER match — the decoder is looking for the post-conversion `"loadId"`. | The decoder silently emits `keyNotFound`. | Use `"loadId"` as the raw value, not `"load_id"`. Phase 7 `ChainOfTrust.swift` already follows this convention; copy verbatim. |
| **Removing `priorRelationshipCount` from CodingKeys but keeping the property.** A property without a CodingKey is a synthesized-from-property-name match. After `.convertFromSnakeCase`, `priorRelationshipCount` would match the wire key `prior_relationship_count` — but D-14 removes that wire key. Result: `keyNotFound`. | The Phase 7 fixture re-authoring REMOVES `prior_relationship_count` and ADDS `prior_relationships`. The Swift struct property name MUST move from `priorRelationshipCount` to `priorRelationships` (no aliasing). | Single-shot rename in the struct + the CodingKeys enum + every fixture, in the same commit. |
| **Breaking change to a shipped contract.** Phase 7 is technically shipped (LOAD-02 marked Complete). Phase 8 may have hard-coded references to `priorRelationshipCount` in production code paths. | Check Phase 8: `LoadListItem` is the only consumer of `TrustNode` properties on the list surface, and `LoadListItem` uses ONLY `displayName + verificationState`, NOT `priorRelationshipCount`. ✅ Safe to break. (Verified via grep across `Features/Loads/`.) | A grep test asserts no remaining references to `priorRelationshipCount` after Phase 9 lands. |
| **Decoding tests need updating.** Phase 7's `TrustNodeDecodeTests` (or analogous) asserts `priorRelationshipCount == 3` (or whatever). Phase 9 updates to `priorRelationships.count == 3`. | Failed-decode noise if missed. | Phase 9 Wave 0 task: enumerate all `priorRelationshipCount` references in `validationLedgerTests/` and rewrite them. |

### Acceptance criteria

- [ ] `validationLedger/Core/Load/PriorRelationship.swift` exists with the exact shape above.
- [ ] `validationLedger/Core/Load/ChainOfTrust.swift` has `priorRelationshipCount: Int` REMOVED and `priorRelationships: [PriorRelationship]` ADDED.
- [ ] `TrustNode.CodingKeys` enum: `priorRelationshipCount` case REMOVED, `priorRelationships` case ADDED.
- [ ] `PriorRelationship.CodingKeys.loadID = "loadId"` (post-conversion form, NOT `"load_id"`).
- [ ] Every `validationLedgerTests/Networking/Fixtures/load-detail-VL-*.json` has `prior_relationship_count` replaced by `prior_relationships: [...]` on every `TrustNode`.
- [ ] Existing Phase 7 decode tests updated to read `priorRelationships.count` instead of `priorRelationshipCount`.
- [ ] A grep across the source tree for `priorRelationshipCount` returns ZERO matches after Phase 9 lands.
- [ ] A new decode test asserts a `PriorRelationship` array decodes correctly with the wire shape above, including the `load_id` → `loadID` bridge.

---

## 8. Reference-Implementation Analogs in This Repo

> The pattern-mapper agent runs after research. This section calls out the strongest analogs by file path so the pattern-mapper has a head start. **Every file path below is a direct citation; the planner should encode these as `<read_first>` references in the relevant tasks.**

### `UIScrollView`-hosted custom views with gesture wiring

- **No exact analog exists** for a custom-rendered zoomable canvas — this is novel Phase 9 ground. Closest in-repo: none. Phase 9 is establishing this pattern.
- **External reference (cite in plan):** Apple's [`UIScrollView.viewForZooming`](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:)) + [`UIScrollView.zoom(to:animated:)`](https://developer.apple.com/documentation/uikit/uiscrollview/1619388-zoom).

### `CAShapeLayer` + `CABasicAnimation` (THE STRONGEST IN-REPO ANALOG)

- **`validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift`** — Phase 8 D-09's app-wide skeleton-with-shimmer pattern. **THE Pitfall 1 mitigation** (re-attach in BOTH `prepareForReuse()` AND `layoutSubviews()`) is documented in lines 17–24. The `startShimmer()` private helper at lines 189–198 with its `animation(forKey:) == nil` guard is the EXACT pattern Phase 9's `startPulseIfNeeded()` should mirror.
- **Use this analog for:** halo pulse animation lifecycle; edge `CAShapeLayer` setup; skeleton shimmer for `LoadDetailSkeletonView` (D-19).

### `UISheetPresentationController` presentations

- **No in-repo analog yet** — Phase 9 is the first user of `UISheetPresentationController` in the codebase (the v1.0 shell uses `UINavigationController` push + `present(_:)` of full-screen modals only).
- **Use external reference (cite in plan):** [Apple `UISheetPresentationController`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller) + the Filip Nemecek guide above.

### Accessibility containers

- **`validationLedger/UI/LimitedTrustBannerView.swift`** — Phase 4's banner. NOT a container (it's a leaf — `isAccessibilityElement = true; accessibilityTraits = .staticText`). Useful as a precedent for the BANNER analog (Phase 9's `ChainIntegrityBannerView` mirrors its file shape exactly).
- **`validationLedger/UI/Components/VerificationBadgeView.swift`** — also a leaf (`isAccessibilityElement = true; accessibilityTraits = .staticText`). The "fail-closed-via-literal-'not'-prefix" VoiceOver discipline is the strongest accessibility precedent.
- **No in-repo container analog yet.** Phase 9's `TrustGraphView` (container) is novel. Phase 8's `LoadListViewController` doesn't count — it uses a `UICollectionView` which manages cell-level accessibility automatically (each cell is its own leaf element).
- **Use external reference (cite in plan):** [Apple `UIAccessibilityContainer` informal protocol](https://developer.apple.com/documentation/uikit/uiaccessibilitycontainer).

### Snapshot tests (THE STRONGEST IN-REPO ANALOGS)

- **`validationLedgerTests/Support/UIKitSnapshot.swift`** — the hand-rolled snapshot helper. Phase 9 reuses verbatim.
- **`validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift`** — per-state snapshot pattern. 4 visual-state tests + 1 fail-closed nil test + 1 pill-cornerRadius-recompute test. Phase 9's `TrustNodeView` snapshot tests follow this shape.
- **`validationLedgerTests/Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift`** — skeleton + shimmer snapshot pattern; asserts shimmer animation attachment via internal `shimmerLayer.animation(forKey: "shimmer")` probe. Phase 9's `LoadDetailSkeletonViewSnapshotTests` mirrors this.
- **`validationLedgerTests/Loads/Snapshot/LoadRowCellSnapshotTests.swift`** — multi-state cell snapshot pattern. Phase 9's `TrustGraphViewSnapshotTests` (12-fingerprint matrix) follows this shape.

### Composition root + factory closure (`makeLoadDetailScreen(loadID:)`)

- **`validationLedger/App/AppContainer.swift`** lines 218–247 — Phase 8's `makeLoadListScreen(role:)` factory. The exact shape Phase 9 mirrors for `makeLoadDetailScreen(loadID:)`:
  - `@MainActor func makeLoadDetailScreen(loadID: String) -> UIViewController`
  - Constructs `LoadDetailViewModel(loadID: loadID, apiClient: apiClient, logger: …)`
  - Returns a `LoadDetailViewController(viewModel: vm)`.
- The factory closure is wired into `LoadListViewController` via the same threading pattern that `kycStatusScreenFactory` uses (file header in `AppContainer.swift`).

### MVVM + state-machine VC

- **`validationLedger/Features/Loads/LoadListViewController.swift`** — Phase 8's state-machine VC. The state-driven `render(state:)` dispatcher (lines 441–568) is the template Phase 9's `LoadDetailViewController.render(state:)` mirrors. Key patterns:
  - `viewWillAppear → Task { await viewModel.fetchLoads() }` (Phase 9: `viewModel.loadDetail()`).
  - `bindViewModel()` with explicit `render(state: viewModel.state)` pump (WR-06 — lines 416–430).
  - `MainActor.assumeIsolated { ... }` inside the state-change closure for explicit isolation.
  - State subviews (skeleton overlay, error-state stack) added and toggled by `isHidden`, not by view-controller swap.
- **`validationLedger/Features/Loads/LoadListViewModel.swift`** — the VM template (not read in research but follows the obvious pattern).
- **`validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift`** — the v1.0 canonical fetch-on-appear UIKit precedent (cited in Phase 8 RESEARCH.md as the file-shape analog).

### Coordinator pattern (list → detail navigation)

- **`validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift`** — the canonical coordinator pattern. Owns the push + retains state across pushes. Phase 9 SHOULD continue the precedent: a thin `LoadDetailCoordinator` (or just the factory closure pattern if state retention isn't needed).
- **`validationLedger/App/AppCoordinator.swift`** lines 26–45 — documents the "strong reference to coordinator" retain pattern. Without this retention the coordinator deallocates immediately after `present/push`.

### Phase 7 contract (READ ONLY)

- **`validationLedger/Core/Load/ChainOfTrust.swift`** — the `TrustNode` + `TrustEdge` types. **Phase 9 MODIFIES `TrustNode` (D-12).** The trailing-acronym CodingKeys pattern (`partyID = "partyId"`, `edgeID = "edgeId"`, etc.) is the template `PriorRelationship.CodingKeys.loadID = "loadId"` follows.
- **`validationLedger/Core/Load/ChainIntegrity.swift`** — the verdict + reason + implicated IDs. UNCHANGED.
- **`validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift`** — UNCHANGED. Phase 9 consumes it.
- **`validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift`** — the canonical `nonisolated public struct APIEndpoint` shape with `EmptyBody`/typed `Response`. Pattern reference.

### Design system tokens (READ ONLY)

- **`validationLedger/UI/DesignSystem/Spacing.swift`** — the 6-token spacing scale Phase 9 consumes (xs/sm/md/lg/xl/xxl). No new tokens.
- **`validationLedger/UI/DesignSystem/Colors.swift`** — Phase 9 ADDS ONE public member: `public static let caution: UIColor = .systemYellow`. Otherwise UNCHANGED.
- **`validationLedger/UI/DesignSystem/Typography.swift`** — UNCHANGED.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pan + pinch zoom on the graph | Custom gesture math; `UIPanGestureRecognizer` + `UIPinchGestureRecognizer` glued together | `UIScrollView` with native `panGestureRecognizer` + `pinchGestureRecognizer` + `viewForZooming` delegate | iOS has shipped this since iOS 3.0. Custom gesture math fails on inertial scrolling, momentum, edge bounce, and accessibility. |
| Single-tap vs double-tap arbitration | Time-based "wait 200ms then fire single" custom code | `UITapGestureRecognizer.require(toFail:)` | Apple's gesture-arbitration engine handles this correctly across iOS versions and Dynamic Type / accessibility settings. |
| Modal sheet with detents | Manually animating a `UIView` up from the bottom edge with a `UIPanGestureRecognizer` for drag-to-dismiss | `UISheetPresentationController` with `[.medium, .large]` detents | iOS-17-native. Handles iPad floating-card, swipe-down dismiss, grabber affordance, undimmed-presenting-view for free. |
| Error state UI | Hand-rolled `UIStackView` of centered icon + heading + body + button | `UIContentUnavailableView` with `UIContentUnavailableConfiguration` | iOS-17-native. Phase 8 documented one exception (the LoadList error state uses hand-rolled because accessibility identifier on the retry button is unreachable through `UIContentUnavailableConfiguration`). Phase 9 should follow the SAME exception path: hand-rolled error state with locked accessibility identifiers. |
| Skeleton shimmer | Custom `CABasicAnimation` from scratch | The `SkeletonLoadRowCell.startShimmer()` pattern (`CAGradientLayer` + `CABasicAnimation` on `"locations"` + `animation(forKey:) == nil` re-attach guard) | Already battle-tested in Phase 8. Reuse the exact mechanics. |
| Snapshot tests | A new SwiftPM dependency for snapshot testing | `validationLedgerTests/Support/UIKitSnapshot.swift` (already in tree) | Zero new deps. Already proven on 4 Phase 8 surfaces. |
| Graph layout algorithm | Sugiyama / force-directed / hand-rolled tree layout | Fixed normalized role-slot coordinates per D-06 | The topology is exactly 5 fixed roles. An algorithm solves a problem that does not exist. |
| Trust derivation | Client-side "is this party verified?" logic | Server-supplied `VerificationState` + `ChainIntegrity.verdict` rendered verbatim | Phase 7 D-18 LOCKED. A client that computes trust is a fraud vector for a fraud-prevention product. |

**Key insight:** Phase 9 is the marquee surface of v1.1, but architecturally it is a thin renderer over already-fixed data. EVERY gesture, animation, sheet, and snapshot mechanism Phase 9 needs already exists in the iOS SDK or in the Phase 7/8 precedent. Phase 9's job is composition, not invention.

---

## Common Pitfalls

### Pitfall 1: Animation strips on layout / size-class transition

**What goes wrong:** The compromised pulse halo stops animating after a rotation, a split-multitasking-width change, or a verdict swap.

**Why it happens:** `CAShapeLayer` animations are detached from the layer when its `bounds` change (the layer tree is invalidated and re-rendered). If the halo's `add(pulse, forKey:)` was a one-shot call in the construction path, the animation is gone after the layout pass.

**How to avoid:** Mirror `SkeletonLoadRowCell.startShimmer()` — a `startPulseIfNeeded()` helper guarded by `halo.animation(forKey: "pulse") == nil`, called from BOTH `layoutSubviews()` AND `traitCollectionDidChange(_:)`.

**Warning signs:** Pulse works in the simulator at initial launch but stops after rotation or after returning from background.

### Pitfall 2: Single-tap fires on the leading edge of double-tap

**What goes wrong:** Double-tapping a node opens the sheet (single-tap codepath) AND animates the recenter+zoom — the user sees the sheet pop up, then animate behind it.

**Why it happens:** `UITapGestureRecognizer(numberOfTapsRequired: 1)` recognizes as soon as touch-ends, before the system knows a second tap is coming.

**How to avoid:** `singleTap.require(toFail: doubleTap)` on every single-tap-on-node recognizer.

**Warning signs:** Sheet flashes briefly during double-tap; logs show both `handleSingleTap` AND `handleDoubleTap` firing.

### Pitfall 3: Outer page scroll is swallowed by graph

**What goes wrong:** On iPhone, the user single-finger-drags up to scroll the bill-of-lading body, but the drag starts inside the graph region — the graph's `UIScrollView` claims the gesture and pans the graph (which is at zoomScale=1.0, so nothing happens visually — the body just doesn't scroll).

**Why it happens:** `UIScrollView.panGestureRecognizer.minimumNumberOfTouches` defaults to 1. Any single-finger drag inside the scroll view's bounds is claimed.

**How to avoid:** `graphScrollView.panGestureRecognizer.minimumNumberOfTouches = 2`. Single-finger drags then propagate to the outer page scroll view.

**Warning signs:** On iPhone, scrolling the body works fine OUTSIDE the graph region but feels "stuck" when the drag starts inside.

### Pitfall 4: `isAccessibilityElement = true` on the container

**What goes wrong:** VoiceOver speaks "Trust graph" once and then skips to the next view-controller element — it never reaches the nodes or edges.

**Why it happens:** When `isAccessibilityElement == true`, VoiceOver treats the view as a leaf and IGNORES `accessibilityElements`.

**How to avoid:** `TrustGraphView.isAccessibilityElement = false`.

**Warning signs:** VoiceOver traversal skips from the banner directly to the timeline — the graph is invisible to the accessibility tree.

### Pitfall 5: `.convertFromSnakeCase` + wrong CodingKey raw value

**What goes wrong:** Decode fails with `keyNotFound` even though the wire JSON has the field.

**Why it happens:** `.convertFromSnakeCase` converts wire keys to camelCase BEFORE matching against `CodingKeys` raw values. A raw value of `"load_id"` will never match because the decoder is looking for `"loadId"`.

**How to avoid:** When `.convertFromSnakeCase` is enabled, CodingKey raw values use the POST-CONVERSION camelCase form: `loadID = "loadId"`, NOT `"load_id"`.

**Warning signs:** Decode tests pass against the Swift type but fail against the JSON fixture; error message is `keyNotFound(CodingKeys(stringValue: "loadId", intValue: nil), ...)`.

### Pitfall 6: VoiceOver double-tap conflicts with our double-tap

**What goes wrong:** VoiceOver-on user double-taps to "activate" a node, but our double-tap recognizer fires the recenter+zoom AND VoiceOver tries to fire the `.button` activate at the same time — UX is wedged.

**Why it happens:** VoiceOver maps single-finger-double-tap to "activate the current element." Our double-tap recognizer is also listening for single-finger-double-tap.

**How to avoid:** D-22 mitigation — when `UIAccessibility.isVoiceOverRunning == true`:
- Disable double-tap recognizers (`isEnabled = false`).
- Set `minimumZoomScale = maximumZoomScale = 1.0` (no zoom).
- VoiceOver's activate-gesture then fires the node's `.button` trait → the single-tap codepath runs.

**Warning signs:** With VoiceOver on, tapping a node either does nothing or triggers an unexpected zoom.

### Pitfall 7: Setting `largestUndimmedDetentIdentifier` is forgotten

**What goes wrong:** Sheet opens at `.medium`, but the graph behind is DIMMED — the marquee "graph stays visible" posture is broken.

**Why it happens:** Default behavior dims the presenting view at ALL detents. `largestUndimmedDetentIdentifier` is the property that explicitly allows interaction with (and undimming of) the presenting view at a specific detent.

**How to avoid:** `sheet.largestUndimmedDetentIdentifier = .medium`.

**Warning signs:** The screen looks "interrupted" — sheet over a grey overlay — even at `.medium`.

### Pitfall 8: Pixel-level snapshot regression on the pulse mid-frame

**What goes wrong:** The compromised halo snapshot is brittle — depending on when the test fires, the halo could be at `opacity = 0.6`, `0.8`, `1.0`, anywhere between. Two consecutive runs produce different fingerprints.

**Why it happens:** `CABasicAnimation` runs on its own clock, independent of the test's render pass.

**How to avoid:** Per UI-SPEC § Snapshot Test Posture — snapshot the **static frame** at `halo.opacity = 1.0` (the upper bound), NOT the animated mid-frame. The test sets `halo.opacity = 1.0` and does NOT add the pulse animation before calling `UIKitSnapshot.image(of:size:)`.

**Warning signs:** Snapshot tests fail intermittently with subtle opacity differences.

---

## Code Examples

Verified patterns from official sources and in-repo Phase 8 precedent.

### Gesture wiring (combining the canonical recipes)

```swift
// In TrustGraphView.setUp():

// 1. Pinch + pan via native UIScrollView (the host wraps TrustGraphView)
graphScrollView.delegate = self
graphScrollView.minimumZoomScale = 1.0
graphScrollView.maximumZoomScale = 2.5
graphScrollView.panGestureRecognizer.minimumNumberOfTouches = 2  // outer-scroll safety

// 2. Double-tap-on-empty-canvas reset, attached to TrustGraphView itself
let canvasDoubleTap = UITapGestureRecognizer(target: self,
                                              action: #selector(handleDoubleTapOnEmptyCanvas(_:)))
canvasDoubleTap.numberOfTapsRequired = 2
canvasDoubleTap.delegate = self  // for cancelsTouchesInView discipline
addGestureRecognizer(canvasDoubleTap)
```

```swift
// In TrustNodeView.setUp():

let singleTap = UITapGestureRecognizer(target: self,
                                        action: #selector(handleSingleTap(_:)))
singleTap.numberOfTapsRequired = 1

let doubleTap = UITapGestureRecognizer(target: self,
                                        action: #selector(handleDoubleTap(_:)))
doubleTap.numberOfTapsRequired = 2

// CRITICAL: single-tap must wait for double-tap to fail.
singleTap.require(toFail: doubleTap)

addGestureRecognizer(singleTap)
addGestureRecognizer(doubleTap)

// VoiceOver-double-tap-to-activate (D-22)
isAccessibilityElement = true
accessibilityTraits = .button
```

[CITED: Apple `UIGestureRecognizer` docs + Phase 8 PITFALLS.md gesture-arbitration entry]

### Halo pulse with re-attach guard

```swift
// In TrustGraphView — sibling-below-chrome CAShapeLayer per implicated node

private func makeHaloLayer(for nodeFrame: CGRect, verdict: ChainIntegrity.Verdict) -> CAShapeLayer {
    let halo = CAShapeLayer()
    let path = UIBezierPath(roundedRect: nodeFrame.insetBy(dx: -6, dy: -6),
                            cornerRadius: 18)  // node corner 12 + halo inset 6
    halo.path = path.cgPath
    halo.fillColor = (verdict == .caution
                      ? DS.Colors.caution.cgColor
                      : DS.Colors.destructive.cgColor)
    halo.opacity = 1.0  // resting frame — what snapshot tests assert
    return halo
}

private func startPulseIfNeeded(on halo: CAShapeLayer) {
    // Reduce-motion suppression (D-22)
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    // Caution halo does NOT pulse (D-15: pulse ONLY on compromised)
    guard halo.fillColor == DS.Colors.destructive.cgColor else { return }
    // Re-attach guard — same pattern as SkeletonLoadRowCell.startShimmer()
    guard halo.animation(forKey: "pulse") == nil else { return }

    let pulse = CABasicAnimation(keyPath: "opacity")
    pulse.fromValue = 0.6
    pulse.toValue = 1.0
    pulse.duration = 1.2
    pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    pulse.autoreverses = true
    pulse.repeatCount = .infinity
    pulse.isRemovedOnCompletion = false
    halo.add(pulse, forKey: "pulse")
}

override func layoutSubviews() {
    super.layoutSubviews()
    // Re-attach pulse animations after any layout pass (Pitfall 1)
    haloLayers.forEach(startPulseIfNeeded)
}

override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    // Compact↔regular transitions re-run the layer tree (Pitfall 1)
    haloLayers.forEach(startPulseIfNeeded)
}
```

[VERIFIED: derived from in-tree `SkeletonLoadRowCell.swift` lines 189–198 + Apple `CABasicAnimation` + `UIAccessibility.isReduceMotionEnabled` docs]

### Sheet presentation (TRUST-03 + TRUST-04 shared infrastructure)

```swift
// In LoadDetailViewController:

private func presentVerificationBasis(for node: TrustNode) {
    let sheetVC = VerificationBasisSheetViewController(node: node,
                                                        integrity: chainOfTrust.integrity)
    sheetVC.view.accessibilityIdentifier = "load-detail.verification-basis-sheet"
    configureSheet(sheetVC)
    present(sheetVC, animated: true)
}

private func presentHandoffDetail(for edge: TrustEdge) {
    let sheetVC = HandoffDetailSheetViewController(edge: edge,
                                                    integrity: chainOfTrust.integrity)
    sheetVC.view.accessibilityIdentifier = "load-detail.handoff-detail-sheet"
    configureSheet(sheetVC)
    present(sheetVC, animated: true)
}

private func configureSheet(_ vc: UIViewController) {
    guard let sheet = vc.sheetPresentationController else { return }
    sheet.detents = [.medium(), .large()]
    sheet.selectedDetentIdentifier = .medium
    sheet.prefersGrabberVisible = true
    sheet.largestUndimmedDetentIdentifier = .medium  // graph stays visible at .medium (D-08)
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false  // grabber, not scroll, expands
}
```

[CITED: Apple `UISheetPresentationController` docs]

### Accessibility container

```swift
// In TrustGraphView.applyAccessibilityElements() — called after every layout/data update

private func applyAccessibilityElements() {
    isAccessibilityElement = false  // CRITICAL: container, not leaf

    let orderedNodes = nodeViewsInRoleOrder()  // [shipper, broker, carrier, dispatch, factoring]
    let orderedEdges = edgeCompanionViewsByFromToLex()

    accessibilityElements = orderedNodes + orderedEdges

    for nodeView in orderedNodes {
        nodeView.isAccessibilityElement = true
        nodeView.accessibilityTraits = .button
        nodeView.accessibilityLabel = composedNodeLabel(node: nodeView.node)
    }
    for edgeView in orderedEdges {
        edgeView.isAccessibilityElement = true
        edgeView.accessibilityTraits = .button
        edgeView.accessibilityLabel = composedEdgeLabel(edge: edgeView.edge)
    }
}
```

[CITED: Apple `UIAccessibility` / `UIAccessibilityContainer` informal protocol + D-22]

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UIAlertController` for "modal info" | `UISheetPresentationController` with `[.medium, .large]` detents | iOS 15+ (refined iOS 16/17) | Sheets are the modern Apple-blessed surface for "show me more about this without leaving the parent screen." Phase 9 D-08 uses this directly. |
| Centered `UIActivityIndicatorView` for `.loading` | Skeleton-with-shimmer placeholder mimicking the loaded silhouette | Industry shift ~2018+; Phase 8 D-09 adopted for v1.1 | Reduces perceived load time; user knows what content is coming. Phase 9 D-19 follows. |
| Hand-rolled "no data" state | `UIContentUnavailableView` with `UIContentUnavailableConfiguration` | iOS 17 | Native iOS-17 component. Phase 8 used it for `.empty` and documented the workaround for `.error` (accessibility identifier on the retry button is unreachable). Phase 9 should hand-roll the error state per Phase 8's precedent. |
| `UICollectionView` for any list | Same | — | Still the right tool for lists with many recycled scrolling items. NOT the right tool for the 5-node trust graph. |
| `pointfreeco/swift-snapshot-testing` for snapshots | `UIGraphicsImageRenderer` + `XCTAttachment` (the `UIKitSnapshot` helper) | Phase 8 deliberate decision | Zero new deps. Phase 9 reuses Phase 8's helper verbatim. |

**Deprecated/outdated:**

- **Don't:** add `swift-snapshot-testing` for snapshot tests in this phase (M1 + v1.1 both deliberately decided no).
- **Don't:** use SwiftUI for the trust graph (CLAUDE.md sensitive-surface mandate + UIKit-fluency rationale).
- **Don't:** use SpriteKit / `Grape` / any other graph library (already evaluated and rejected in `.planning/research/STACK.md`).
- **Don't:** add a force-directed layout algorithm (5 fixed roles — algorithm solves a problem that doesn't exist).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `UIScrollView.panGestureRecognizer.minimumNumberOfTouches = 2` propagates single-finger drags to enclosing scroll views | § 1 Gesture Arbitration | LOW — verified against Apple `UIScrollView.panGestureRecognizer` docs + in-repo Phase 4 research `PITFALLS.md` Pitfall 2. The risk is the iPhone bill-of-lading body scroll feeling "stuck" when the user starts a vertical drag inside the graph region. An XCUITest must confirm propagation. |
| A2 | `largestUndimmedDetentIdentifier = .medium` keeps the presenting view (graph) interactive AND undimmed at `.medium` detent | § 5 Sheet Detents | LOW — verified against Apple `UISheetPresentationController` docs (multiple sources). Risk if wrong: graph dims when sheet opens, breaking the marquee D-08 posture. |
| A3 | `CAShapeLayer` paths do NOT need re-rendering when the host view's `transform` changes (e.g. during `UIScrollView` zoom) | § 2 CAShapeLayer Performance | LOW — verified against general iOS Core Animation knowledge. The risk is unnecessary performance work; the worse risk is mistakenly recomputing paths in `scrollViewDidZoom(_:)` and trashing performance. |
| A4 | `.convertFromSnakeCase` recursively applies through nested arrays of structs with their own snake_case keys | § 7 Codable Refactor | LOW — verified against Sarunw + the in-tree Phase 7 `ChainOfTrust.swift` already does this for `TrustNode.priorRelationshipCount` (wire key `prior_relationship_count`). The new `prior_relationships` array follows the same recursion. |
| A5 | Setting `accessibilityElements` on a UIView container (with `isAccessibilityElement = false`) is the supported iOS 17 path for ordered traversal of child UIView elements that remain individually activatable | § 4 Accessibility Containers | LOW — verified against Apple `UIAccessibilityContainer` informal protocol + multiple community references. The risk is misimplementation that collapses children into a single combined element (the WRONG pattern described in the deque.com article). Acceptance criteria assertion test mitigates. |
| A6 | The `SkeletonLoadRowCell.startShimmer()` re-attach pattern (animation guard + re-attach on `layoutSubviews()` + `prepareForReuse()`) maps one-for-one to the halo pulse re-attach pattern (animation guard + re-attach on `layoutSubviews()` + `traitCollectionDidChange(_:)`) | § 2 + § Code Examples | LOW — same `CABasicAnimation`-strips-on-bounds-change root cause. The `prepareForReuse` site doesn't apply (TrustGraphView isn't a cell); `traitCollectionDidChange` does (iPhone↔iPad split). |

**If this table seems short:** it's intentional. Phase 9's design is exhaustively locked in CONTEXT.md (22 decisions, 4 ROADMAP spike items pre-resolved) and UI-SPEC.md (940 lines, 87KB). The technical investigation surface for research is narrowly scoped to the 8 executor-facing landmines this document addresses, and every recommendation is backed either by Apple docs OR by an in-repo Phase 7/8 precedent. The honest research finding is that there are **no genuine open technical questions** for Phase 9 — only execution discipline. The Assumptions Log catalogues the few claims that lean on external docs without an in-repo verifying precedent.

---

## Open Questions

> Honest catalog of gaps the planner should resolve at plan-time (none are blocking).

1. **Edge stroke width at zoom > 1.0.** UI-SPEC says "constant in screen space (scaled inversely with zoom)." The cleanest implementation is `scrollViewDidZoom(_:)` setting `edge.lineWidth = 2.0 / zoomScale` on every edge. Alternative: leave the stroke as-is and accept thicker lines at zoom — the UI-SPEC line "scaled inversely with zoom" can be interpreted as "the stroke renders 2pt at every zoom level" (active inverse scaling). The planner should pick one and lock it in the task acceptance criteria.

2. **`PriorRelationship.counterpartyDisplayName` rendering decision.** UI-SPEC § Open Questions #1 — planner picks "Broker → Carrier" vs "Broker (Acme Brokerage) → Carrier" in the prior-relationships list rows. If the latter, ensure the framing string truncates gracefully. Defer-to-default is the simpler line (no counterparty display name in the framing).

3. **Coordinator vs direct push from `LoadListViewController`.** CONTEXT § Claude's Discretion delegates to planner. The KYCCoordinator precedent argues for a thin `LoadDetailCoordinator`; the simpler `AppContainer.makeLoadDetailScreen(loadID:)` factory closure threaded through `LoadListViewController` is the lower-friction continuation of Phase 8's `kycStatusScreenFactory` pattern. Both are correct; planner picks the consistent one.

4. **Dimmed-others fixture.** UI-SPEC § Open Questions #4 — a test fixture exercising the dimmed-non-implicated-nodes treatment across all three verdicts would simplify snapshot testing. The planner adds this to `MockLoadFixtureRegistry` ADDITIVELY (or reuses an existing fraud-archetype fixture if its data already exhibits the rendering).

5. **`autoreverses` vs manual `from → to → from` keyframe for the pulse.** Two valid interpretations of D-15's "1.2s loop, opacity 0.6 → 1.0, infinite repeat":
   - `duration = 0.6, autoreverses = true, repeatCount = .infinity` → 1.2s round trip 0.6→1.0→0.6.
   - `duration = 1.2, autoreverses = true, repeatCount = .infinity` → 2.4s round trip.
   The first matches the UI-SPEC literal "1.2s loop" more cleanly. The planner pins one.

---

## Environment Availability

> Skip rationale: Phase 9 has zero external dependencies beyond what's already in tree. The audit below is for completeness.

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| UIKit | All Phase 9 view code | ✓ | iOS 17 SDK | — |
| QuartzCore (CAShapeLayer, CAGradientLayer, CABasicAnimation) | Edge rendering, halo pulse, skeleton shimmer | ✓ | iOS 17 SDK | — |
| Foundation (JSONDecoder, RelativeDateTimeFormatter, DateFormatter) | Codable decode, sheet timestamps | ✓ | iOS 17 SDK | — |
| Xcode 26.4 / iOS 17 simulator | Build + test | ✓ (CLAUDE.md) | 26.4 / iOS 17 | — |
| `validationLedgerTests/Support/UIKitSnapshot.swift` | Phase 9 snapshot tests | ✓ (in tree from Phase 8) | n/a | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (existing; Swift Testing also in tree but Phase 9 snapshot + accessibility tests use XCTest per `UIKitSnapshot.swift` lines 5–11) |
| Config file | `validationLedger.xcodeproj/project.pbxproj` |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:validationLedgerTests/Loads -enableCodeCoverage NO` |
| Full suite command | The scoped serial simulator-lane command per project memory `ios-test-suite-pitfalls.md` (avoids ~67 false failures from bare `xcodebuild test`) |
| Phase gate | Full suite green before `/gsd:verify-work` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LOAD-05 | Row tap opens detail VC | XCUITest (smoke) | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_rowTap_pushesDetail` | ❌ Wave 0 |
| LOAD-06 | Status timeline renders 6-pill stepper | Snapshot + unit | `-only-testing:validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests` | ❌ Wave 0 |
| TRUST-01 | Interactive chain-of-trust graph renders nodes + edges | Snapshot + gesture unit | `-only-testing:validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests` + `-only-testing:validationLedgerTests/Loads/TrustGraphViewGestureTests` | ❌ Wave 0 |
| TRUST-03 | Node tap opens verification basis sheet | XCUITest | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_nodeTap_opensVerificationBasisSheet` | ❌ Wave 0 |
| TRUST-04 | Edge tap opens handoff sheet | XCUITest | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_edgeTap_opensHandoffSheet` | ❌ Wave 0 |
| TRUST-05 | Compromised verdict renders red halo + banner + dim-others | Snapshot + assertion | `-only-testing:validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests/test_compromisedVerdict_rendersExpectedFrame` | ❌ Wave 0 |
| (gesture) | `singleTap.require(toFail: doubleTap)` is set | Unit | `-only-testing:validationLedgerTests/Loads/TrustNodeViewGestureTests/test_singleTap_requiresDoubleTapFail` | ❌ Wave 0 |
| (a11y) | `TrustGraphView.isAccessibilityElement == false` + ordered `accessibilityElements` | Unit | `-only-testing:validationLedgerTests/Loads/TrustGraphViewAccessibilityTests` | ❌ Wave 0 |
| (decode) | `PriorRelationship` decodes correctly with `load_id` → `loadID` bridge | Unit | `-only-testing:validationLedgerTests/Loads/PriorRelationshipDecodeTests` | ❌ Wave 0 |
| (contract) | Every `load-detail-VL-*.json` has `prior_relationships` (D-14) | Unit | `-only-testing:validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** scoped XCTest run for the test file the task touches (matches Phase 8 cadence).
- **Per wave merge:** full suite via the serial simulator-lane command.
- **Phase gate:** Full suite green AND every snapshot artefact attached to the test run for human visual triage.

### Wave 0 Gaps

- [ ] `validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift` — 12 fingerprints (3 verdicts × 2 devices × 2 Dynamic Type)
- [ ] `validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/TrustNodeViewGestureTests.swift` — single-tap-requires-doubleTap-fail
- [ ] `validationLedgerTests/Loads/TrustGraphViewGestureTests.swift` — minimumNumberOfTouches + VoiceOver-suspends-zoom
- [ ] `validationLedgerTests/Loads/TrustGraphViewAccessibilityTests.swift` — container model + ordered elements
- [ ] `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` — state machine + error mapping
- [ ] `validationLedgerTests/Loads/PriorRelationshipDecodeTests.swift` — load_id → loadID bridge
- [ ] `validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` — D-14 contract enforcement (every fixture has `prior_relationships`)
- [ ] `validationLedgerUITests/LoadDetailFlowTests.swift` — 5-role smoke flow + sheet-opens assertions + outer-scroll-propagation assertion

---

## Security Domain

> Phase 9 is a read-only render layer. Security work focuses on (a) the platform's no-client-derived-trust invariant (Phase 7 D-18 already locked), (b) zero PII in analytics / logs / snapshot artefacts, (c) the fail-closed decoder invariants Phase 7 already locked. No new authentication, session, or cryptography work.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (no auth UI; uses existing session) | n/a |
| V3 Session Management | No | n/a |
| V4 Access Control | Implicit (role-filtered backend; Phase 7 D-18 locks no client-side trust derivation) | Server-supplied `verificationState` + `chainIntegrity.verdict` rendered verbatim. NO client-side derivation. |
| V5 Input Validation | Yes (Codable decoding from mock fixtures) | `Decodable` synthesized init + `.convertFromSnakeCase` + Phase 7 fail-closed value-type decoders (`VerificationState`, `ChainIntegrity.Verdict`). Phase 9 adds one new value type (`PriorRelationship`) — pure `Decodable & Sendable`, no custom decoder needed beyond the trailing-acronym CodingKey. |
| V6 Cryptography | No (no new cryptography) | n/a |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Spoofed verification state via tampered response | Tampering / Information Disclosure | Phase 7 D-09 fail-closed decode: unknown wire values degrade to `.unverified` (least-trusted). `ChainIntegrity.Verdict` unknown values degrade to `.compromised` (loudest fraud signal, OPPOSITE direction — see UI-SPEC § Pre-fraud-tier color invariants). |
| Client-side trust derivation creating a "verified" badge from incomplete data | Tampering | Phase 7 D-18 LOCK: every field rendered is server-supplied. No computed Bool. Phase 9 enforces by sourcing the badge state ONLY from `TrustNode.verificationState` and never from local logic. |
| PII leak in snapshot test artefacts | Information Disclosure | `UIKitSnapshot.swift` lines 22–27 LOCK: synthetic fixture data only. Phase 9 snapshot tests construct views with the existing fixture corpus; no party names / IDs / load numbers are introduced. |
| PII leak in logger events | Information Disclosure | The view layer NEVER calls logger (LoadListViewController file header: "No logging (T-08-08)"). Phase 9 follows: any logging happens in the VM via the existing PII-scrub logger. |
| Stale-data display after refresh failure | Tampering / Repudiation | Phase 9 has no refresh affordance (one-shot fetch). A failed fetch transitions to `.error` and offers Try-again; no stale data is shown. |
| Hostile fixture content as fraud-archetype rendering | Information Disclosure | Fixtures are PII-zero by construction (Phase 7 fixture-authoring discipline). Fraud archetypes use synthetic company names. |

---

## Sources

### Primary (HIGH confidence)

- **In-repo** `validationLedger/Features/Loads/LoadListViewController.swift` — Phase 8's state-machine VC; the file-shape template for `LoadDetailViewController`.
- **In-repo** `validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift` — the canonical animation re-attach pattern (lines 17–24 + 169–198).
- **In-repo** `validationLedger/UI/Components/VerificationBadgeView.swift` — the fail-closed accessibility-label discipline + the badge reuse target.
- **In-repo** `validationLedger/UI/LimitedTrustBannerView.swift` — the banner file-shape template Phase 9's `ChainIntegrityBannerView` mirrors.
- **In-repo** `validationLedger/Core/Load/ChainOfTrust.swift` lines 117–132 — the trailing-acronym CodingKeys pattern + the field Phase 9 modifies.
- **In-repo** `validationLedger/Core/Networking/APIClient.swift` lines 110–115 — the `.convertFromSnakeCase` decoder.
- **In-repo** `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` — the canonical `nonisolated public struct APIEndpoint` shape.
- **In-repo** `validationLedger/App/AppContainer.swift` lines 218–247 — the factory closure pattern for `makeLoadDetailScreen(loadID:)`.
- **In-repo** `validationLedgerTests/Support/UIKitSnapshot.swift` — the snapshot helper Phase 9 reuses.
- **In-repo** `validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` — the snapshot test template.
- **In-repo** `.planning/research/STACK.md` lines 59–155 — the trust-graph rendering decision (Option A vs B vs C vs D).
- **In-repo** `.planning/research/PITFALLS.md` lines 45–72 — Pitfall 2 "Gesture conflicts on the trust graph."
- **In-repo** `.planning/phases/09-load-detail-chain-of-trust-graph/09-CONTEXT.md` — the 22 locked decisions.
- **In-repo** `.planning/phases/09-load-detail-chain-of-trust-graph/09-UI-SPEC.md` — the 940-line design contract.

### Secondary (MEDIUM-HIGH confidence — Apple official docs)

- [Apple — `UIScrollView.panGestureRecognizer`](https://developer.apple.com/documentation/uikit/uiscrollview/pangesturerecognizer)
- [Apple — `UIScrollView.zoom(to:animated:)`](https://developer.apple.com/documentation/uikit/uiscrollview/1619388-zoom)
- [Apple — `UIScrollViewDelegate.viewForZooming(in:)`](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:))
- [Apple — `UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldrecognizesimultaneouslywith:))
- [Apple — `UISheetPresentationController`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller)
- [Apple — `largestUndimmedDetentIdentifier`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/largestundimmeddetentidentifier)
- [Apple — `UIAccessibility.isReduceMotionEnabled`](https://developer.apple.com/documentation/uikit/uiaccessibility/isreducemotionenabled)
- [Apple — `UIAccessibility` / `UIAccessibilityContainer`](https://developer.apple.com/documentation/uikit/uiaccessibility)
- [Apple — `CABasicAnimation`](https://developer.apple.com/documentation/quartzcore/cabasicanimation)
- [Apple — `CAShapeLayer`](https://developer.apple.com/documentation/quartzcore/cashapelayer)

### Tertiary (MEDIUM confidence — community resources, verified against Apple docs or in-repo precedent)

- [Sarunw — How to set custom CodingKey for the convertFromSnakeCase decoding strategy](https://sarunw.com/posts/how-to-set-custom-codingkey-for-convertfromsnakecase-decoding-strategy/) — confirmed `CodingKeys` raw values use post-conversion camelCase form.
- [TimOliver gist — Zooming to a specific CGPoint inside a UIScrollView](https://gist.github.com/TimOliver/71be0a8048af4bd86ede) — recipe for centering zoom on a specific subview anchor.
- [Filip Nemecek — How to configure UIKit bottom sheet with custom size](https://nemecek.be/blog/159/how-to-configure-uikit-bottom-sheet-with-custom-size) — sheet detent configuration examples.
- [SparrowCode — UISheetPresentationController](https://sparrowcode.io/en/tutorials/uisheetpresentationcontroller) — `prefersScrollingExpandsWhenScrolledToEdge` behaviour.
- [calayer.com — CAShapeLayer in Depth](https://www.calayer.com/core-animation/2016/05/22/cashapelayer-in-depth.html) — CAShapeLayer GPU-composited path rendering.
- [createwithswift.com — Preparing your App for VoiceOver](https://www.createwithswift.com/preparing-your-app-for-voice-over-hiding-elements-from-the-accessible-interface/) — accessibility-element-vs-container distinction.

---

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH — every framework is in-tree iOS 17 SDK; zero new dependencies; the stack decision was ratified in `.planning/research/STACK.md` already.
- **Architecture:** HIGH — every pattern has an in-repo Phase 7/8 precedent. The Composition (state-machine VC), animation lifecycle (`SkeletonLoadRowCell`), banner file shape (`LimitedTrustBannerView`), snapshot helper (`UIKitSnapshot`), and factory closure (`makeLoadListScreen(role:)`) are all proven in tree.
- **Pitfalls:** HIGH — every pitfall is either documented by Apple, surfaced in the codebase's existing pattern files (Phase 4 + Phase 8 PITFALLS.md / RESEARCH.md), or named in CONTEXT.md / UI-SPEC.md directly.
- **Gesture arbitration:** HIGH — `require(toFail:)` + `panGestureRecognizer.minimumNumberOfTouches = 2` is the textbook iOS recipe. The VoiceOver double-tap interaction is explicitly resolved by D-22.
- **CAShapeLayer performance:** MEDIUM-HIGH — the 5×4×1 scale is far below any documented cliff; the lifecycle re-attach pitfall is the only real risk, and Phase 8's `SkeletonLoadRowCell` already shipped the mitigation.
- **Snapshot posture:** HIGH — the team already locked in `UIKitSnapshot.swift` at Phase 8; Phase 9 is reusing established machinery.
- **Codable refactor:** HIGH — the `.convertFromSnakeCase` recursion + trailing-acronym CodingKey pattern is already in tree at `ChainOfTrust.swift`; Phase 9 is mechanical replication.
- **Accessibility container:** HIGH — the parent `isAccessibilityElement = false` + ordered `accessibilityElements` pattern is verified against Apple docs + multiple community references; the wrong pattern (collapse to single element) is explicitly rejected.

**Research date:** 2026-05-20
**Valid until:** 2026-06-20 (30 days — stable iOS-17-SDK surface; no Apple-side API churn expected)

---

## RESEARCH COMPLETE

**Phase:** 9 — Load Detail & Chain-of-Trust Graph
**Confidence:** HIGH

### Key Findings

1. **No new dependencies.** Phase 9 is a thin renderer over already-fixed iOS 17 SDK primitives (`UIScrollView`, `CAShapeLayer`, `UISheetPresentationController`, `UIAccessibility`) plus Phase 7/8 in-tree helpers (`UIKitSnapshot.swift`, `SkeletonLoadRowCell`'s shimmer pattern, `VerificationBadgeView`, `LoadStatusBadgeView`, DS tokens). Zero `Package.swift` change.
2. **The gesture arbitration recipe is canonical iOS.** `UIScrollView.panGestureRecognizer.minimumNumberOfTouches = 2` + `singleTap.require(toFail: doubleTap)` together solve the marquee spike item (b). No `UIGestureRecognizerDelegate.shouldRecognizeSimultaneouslyWith` override is needed.
3. **The halo pulse lifecycle is already documented in tree.** `SkeletonLoadRowCell.startShimmer()`'s re-attach-on-`layoutSubviews()`-with-`animation(forKey:) == nil`-guard pattern (lines 169–198) maps one-for-one to Phase 9's `startPulseIfNeeded()`. The same Pitfall 1 ("animation gets stripped on lifecycle events") applies; the same mitigation works.
4. **Snapshot posture is locked.** Phase 8 shipped `UIKitSnapshot.swift`. Phase 9 reuses it verbatim. No `swift-snapshot-testing` dependency — explicitly rejected by `.planning/research/STACK.md` and the file header of `UIKitSnapshot.swift`.
5. **The `PriorRelationship` Codable refactor follows the existing trailing-acronym pattern.** `loadID = "loadId"` raw value (post-conversion form under `.convertFromSnakeCase`) mirrors `partyID = "partyId"` in `ChainOfTrust.swift:118-132`. Mechanical replication, not novel work.
6. **The accessibility container model is `isAccessibilityElement = false` + ordered `accessibilityElements` array.** Each child stays individually focusable with `.button` traits — VoiceOver-double-tap fires the same tap recognizer the sighted user uses. The deque.com-suggested "collapse children to single combined element" pattern is the WRONG one for Phase 9.

### File Created

`/Users/ustatb01/development/mobileApps/validation-ledger-mobile/.planning/phases/09-load-detail-chain-of-trust-graph/09-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Zero new deps; iOS 17 SDK + in-tree helpers only. Already ratified by `.planning/research/STACK.md`. |
| Architecture | HIGH | Every novel-to-Phase-9 view has an in-repo file-shape analog: state-machine VC (`LoadListViewController`), banner (`LimitedTrustBannerView`), animation lifecycle (`SkeletonLoadRowCell`), snapshot test (`VerificationBadgeViewSnapshotTests`), trailing-acronym CodingKey (`ChainOfTrust.swift`), composition-root factory (`makeLoadListScreen(role:)`). |
| Gesture Arbitration | HIGH | Canonical iOS recipe; in-repo `.planning/research/PITFALLS.md` Pitfall 2 already documented the spike. |
| CAShapeLayer + Animation | MEDIUM-HIGH | 5×4×1 scale far below any documented cliff; the only real risk is the animation-strips-on-layout pitfall, which `SkeletonLoadRowCell` already mitigated and Phase 9 mirrors. |
| Snapshot Posture | HIGH | Locked by Phase 8's `UIKitSnapshot.swift` shipping decision. |
| Accessibility Container | HIGH | Verified against Apple + multiple community sources; the WRONG pattern (single-element collapse) is named explicitly. |
| Sheet Detents | HIGH | iOS-17-native; the `largestUndimmedDetentIdentifier = .medium` knob is the single critical setting. |
| Codable Refactor | HIGH | In-repo `ChainOfTrust.swift` already does the same pattern for the same kind of field. |

### Open Questions

5 minor planner-time decisions catalogued in § Open Questions — all are pick-one-and-lock-it; none are blocking. (Edge stroke width at zoom; `counterpartyDisplayName` rendering; Coordinator vs factory; dimmed-others fixture; pulse `autoreverses` literal interpretation.)

### Ready for Planning

Research complete. Phase 9 has the smallest "open technical territory" of any v1.1 phase to date — CONTEXT.md locked 22 decisions, UI-SPEC.md is 940 lines of pinned design contract, and every executor-facing landmine identified in this research either has a direct in-repo precedent (Phase 7 or Phase 8) or a canonical Apple iOS 17 recipe. The planner can write tasks with high confidence in `<read_first>` citations, `<acceptance_criteria>` formulations, and the approach picked from the iOS literature.
