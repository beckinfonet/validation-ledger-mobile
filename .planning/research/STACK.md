# Stack Research — v1.1 "Load Flows"

**Domain:** Load domain for a security-sensitive identity-verified freight iOS client (UIKit-first, iOS 17, SwiftPM-only, MockURLProtocol contract-first networking, MVVM + Coordinators)
**Researched:** 2026-05-19
**Milestone:** v1.1 "Load Flows" — subsequent milestone on a shipped v1.0 codebase
**Confidence:** HIGH

> Scope of this research is deliberately narrow. v1.1 reuses M1's validated stack wholesale (UIKit, iOS 17, SwiftPM, hand-rolled `APIClient` + `MockURLProtocol`, Secure Enclave keystore, App Attest, MVVM + Coordinators, initializer-DI `AppContainer`, SwiftLint + SwiftFormat, Swift Testing + XCUITest, Nuke for images). None of that is re-opened here — see `.planning/research/v1.0/STACK.md` for that work. The one genuinely open question for v1.1 is **how to render the interactive chain-of-trust node-graph in UIKit on iOS 17.** This file answers that and nothing else.

---

## TL;DR — The Recommendation

**Build the chain-of-trust graph with first-party Apple frameworks. Add zero new dependencies.**

| Concern | Pick | Rationale (one line) |
|---|---|---|
| Graph rendering | **Custom `UIView` subclasses, one per node** + a container view drawing edges in `CAShapeLayer` | A 5-node directed chain is trivial UIKit; nodes-as-views gives free hit-testing, accessibility, and Auto Layout. |
| Layout algorithm | **Hand-coded fixed layered layout** (left→right or top→bottom column-per-stage) | The chain is a known, fixed topology (shipper→broker→carrier→dispatch→factoring). No layout algorithm is needed — positions are deterministic. |
| Pan / zoom | **`UIScrollView` host with `viewForZooming`** | The standard, accessibility-correct UIKit pan/zoom container. Zero custom gesture math. |
| Node tap | **`UITapGestureRecognizer` per node view** (or `UIControl` subclass) | Native hit-testing; each node is a real view, not a drawn region. |
| Accessibility | **Native — each node view is its own `accessibilityElement`** | A graph drawn into a single layer/canvas is invisible to VoiceOver; views are not. This is the decisive reason against SpriteKit / single-canvas approaches. |
| iPad-native render | **Auto Layout + size classes on the same views** | Views adapt; a fixed-pixel canvas does not render natively on iPad. |

**Dependency-shortlist verdict: NO exception required.** The trust-graph does not justify a new SwiftPM dependency. The pre-approved shortlist stands unchanged. `Package.swift` stays at exactly two dependencies (Nuke 13.0.2, SwiftLintPlugins 0.63.2).

---

## Recommended Stack (Detailed)

### Core Technologies — all first-party, all already in the M1 toolchain

| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **UIKit** (`UIView`, `UIControl`, `UIScrollView`) | iOS 17 SDK | Trust-graph nodes, container, pan/zoom host | Spec-locked: CLAUDE.md mandates UIKit for all sensitive surfaces, and the trust-graph *is* the product's core trust surface. Each of the 5 parties is a real `UIView` — this buys hit-testing, Auto Layout, Dynamic Type, and VoiceOver for free. |
| **Core Animation** (`CAShapeLayer`, `CALayer`, `UIBezierPath`) | iOS 17 SDK | Drawing the 4 directed edges between the 5 nodes | Edges are non-interactive decoration — exactly what `CAShapeLayer` is for. A handful of `UIBezierPath` strokes with an arrowhead. GPU-composited, animatable for state transitions, costs nothing. |
| **UIKit gesture recognizers** (`UITapGestureRecognizer`, `UIScrollView` built-in pinch/pan) | iOS 17 SDK | Tap-a-node-for-verification-basis, pan, zoom | `UIScrollView`'s `viewForZooming` delegate is the canonical UIKit pan/zoom solution; tap recognizers on each node view give precise per-node hit detection with no geometry math. |
| **`MockURLProtocol` + `APIClient` + `Endpoint`** | in-repo (M1) | New load-domain endpoints and fixtures | Reuse verbatim. v1.1 adds `Endpoint` conformers (load list, load detail) and JSON fixtures under the existing `Core/Networking/Mock/` registry pattern. No networking-stack change. |
| **MVVM + Coordinators**, initializer-DI `AppContainer` | in-repo (M1) | `LoadListViewModel`, `LoadDetailViewModel`, a `LoadsCoordinator` | Reuse verbatim. The trust-graph is a view inside the load-detail screen; its data comes from `LoadDetailViewModel`. No architecture change. |
| **`UICollectionView`** (compositional layout) | iOS 17 SDK | The role-filtered **load list** (not the graph) | Already the default for M1 list surfaces. Listed here only to be explicit: the *list* uses `UICollectionView`; the *graph* does not. |

### Supporting Libraries

**None.** v1.1 adds no library. The existing two SwiftPM dependencies are unchanged:

| Library | Version | Purpose | When to Use |
|---|---|---|---|
| **Nuke** | `13.0.2` (pinned `exact`) | Async image load/cache | Already wired. v1.1 may reuse it for any party logo/avatar shown inside a node, or a load photo on the detail screen. No version bump needed. |
| **SwiftLintPlugins** | `0.63.2` (`from`) | Lint enforcement | Unchanged. |

### Development Tools

No additions. v1.1 uses the M1 toolchain as-is: Xcode 26.x, SwiftLint + SwiftFormat, Swift Testing for unit tests, XCUITest for UI/device tests, the sim/device CI split.

One **testing note** specific to the graph: snapshot tests are a strong fit for the trust-graph's discrete visual states (all-verified, one-party-unverified, one-party-revoked, etc.) because the layout is deterministic and non-animating at rest. M1 did not adopt `swift-snapshot-testing` (it was MEDIUM-confidence in v1.0 STACK and never installed). v1.1 can verify graph rendering with **`XCUITest` screenshot assertions** or plain `Tests/` view-configuration unit tests instead — do **not** add `swift-snapshot-testing` solely for this. If the team later wants pixel snapshots broadly, that is a separate, milestone-level dependency decision, not a Load-Flows one.

---

## The Trust-Graph Rendering Decision (the actual research question)

Four candidate approaches were evaluated against: interactivity (pan/zoom/tap), layout for a ~5-node directed chain, iPad-native rendering, accessibility, and maintenance cost for a 1–2 engineer team.

### Option A — Custom `UIView` per node + `CAShapeLayer` edges ✅ RECOMMENDED

**What it is:** Each party (shipper, broker, carrier, dispatch, factoring) is a `UIView` (or `UIControl`) subclass — a card showing the party name, role, and a verification-state badge. A container `UIView` lays the 5 nodes out in fixed positions and draws the 4 connecting edges into `CAShapeLayer`s. The container sits inside a `UIScrollView` for pan/zoom.

| Criterion | Assessment |
|---|---|
| Interactivity | **Excellent.** Each node is a real view → native hit-testing, `UITapGestureRecognizer` or `UIControl` `.touchUpInside` per node. Pan/zoom via `UIScrollView.viewForZooming`. Zero custom gesture math. |
| Layout (~5 nodes) | **Trivial.** The topology is *fixed and known*: a linear directed chain of exactly 5 stages. Positions are a hand-coded layered layout (one column/row per stage). No graph-layout algorithm needed. Auto Layout constraints or a manual `layoutSubviews` both work. |
| iPad-native | **Excellent.** Auto Layout + size classes → the graph reflows for iPad's wider canvas natively (e.g. horizontal chain on iPad, vertical on compact-width iPhone). Satisfies the "iPad must render natively, not scale" constraint. |
| Accessibility | **Excellent — and decisive.** Each node is its own view → each is automatically a VoiceOver `accessibilityElement` with its own label/traits ("Broker, verification verified, double-tap for basis"). Edges can be exposed via `accessibilityElements` ordering or a summary element. This is impossible to get right with a single-canvas drawing. |
| Maintenance cost | **Lowest.** Pure UIKit — the exact framework the 1–2 engineer team is fluent in (CLAUDE.md rationale). No new framework to learn, no dependency to track, no upgrade risk. ~200–400 LOC total. |

**Why this wins:** The problem is not "render an arbitrary graph" — it is "render one specific, fixed 5-stage chain, interactively, accessibly, on iPhone and iPad." That is a basic UIKit layout problem, not a graph-visualization problem. Reaching for SpriteKit or a graph library is over-engineering a known, tiny, static topology.

### Option B — `UICollectionView` with a custom `UICollectionViewLayout`

**What it is:** Nodes are cells; a custom layout positions them; edges drawn in a layout decoration view or a background layer.

| Criterion | Assessment |
|---|---|
| Interactivity | Good — cell selection is native; pan/zoom needs extra work (collection views scroll, but free-form zoom is not built in). |
| Layout | Workable but **awkward** — `UICollectionViewLayout` is designed for flowing/scrolling content, not fixed 2D node placement with connecting edges. Edges-as-decoration-views is fiddly. |
| iPad-native | Good. |
| Accessibility | Good — cells are accessibility elements. |
| Maintenance | **Higher than Option A for no benefit.** A custom `UICollectionViewLayout` is more code and more concepts than just placing 5 views. Collection views earn their keep with *many, recycled, scrolling* items; a 5-node graph has none of those properties. |

**Verdict:** Reasonable but strictly worse than Option A here. Use `UICollectionView` for the **load list** (many rows, recycling, scrolling — its sweet spot), not for the graph.

### Option C — SpriteKit (`SKScene`, `SKNode`, `SKShapeNode`, `SKCameraNode`)

**What it is:** A game-engine scene; nodes are `SKSpriteNode`/`SKShapeNode`; an `SKCameraNode` provides pan/zoom; edges are `SKShapeNode` paths.

| Criterion | Assessment |
|---|---|
| Interactivity | Good for pan/zoom (camera node); tap requires manual `touchesBegan` + node hit-testing. |
| Layout | Manual — same fixed-position math as Option A, but in scene coordinates. |
| iPad-native | Scene scales; getting *native* (not scaled) iPad layout means re-deriving positions per size class anyway. |
| Accessibility | **Poor — disqualifying.** SpriteKit's accessibility story is weak: `SKNode` accessibility is limited, VoiceOver support is partial and historically buggy, and a scene is fundamentally a rendered surface, not a view tree. For a product whose *entire premise is trust and verifiability*, a trust-graph that VoiceOver users cannot inspect is a real defect. |
| Maintenance | **Higher.** SpriteKit is a game framework — a new mental model (scenes, the run loop, nodes-not-views) for a team picked for *UIKit* fluency. `SKShapeNode` performance pitfalls are well documented. Heavy machinery for 5 static cards. |

**Verdict:** Rejected. Justifiable only for large, animated, force-directed graphs (hundreds of nodes). v1.1 has five. The accessibility gap alone rules it out given the product's trust mandate.

### Option D — Third-party SwiftPM graph/diagram library (e.g. Grape)

**What it is:** A dependency that renders graphs. The most credible current Swift option is **Grape** (`SwiftGraphs/Grape`, latest **1.1.0**, Jan 2026; iOS 17 / Swift tools 5.9; D3-inspired force simulation).

| Criterion | Assessment |
|---|---|
| Interactivity | Grape provides a `ForceDirectedGraph` with pan/zoom/drag built in. |
| Layout | Force-directed (physics simulation) — designed to *discover* layout for unknown topologies. v1.1's topology is **fixed and known**, so a force simulation is the wrong tool: it would animate 5 nodes into a layout we already know exactly. |
| iPad-native | Renders on iPad, but as a SwiftUI canvas. |
| Accessibility | The graph is drawn into a SwiftUI `Canvas`-style surface → same accessibility weakness as a single-canvas approach; individual node VoiceOver elements are not a documented feature. |
| **`Grape`-specific blockers** | (1) **It is SwiftUI-only.** `Grape`'s `ForceDirectedGraph` is a SwiftUI `View`. CLAUDE.md forbids SwiftUI on sensitive surfaces, and the trust-graph is the most sensitive surface in the app — embedding it via `UIHostingController` directly violates the UIKit-first constraint for exactly the wrong screen. (The `ForceSimulation` sub-module is UIKit-agnostic, but it only does physics math, not rendering — using it still leaves you hand-rolling the entire renderer, i.e. Option A plus a useless dependency.) (2) **It needs a dependency-shortlist exception** — and there is no justification for one. (3) New dependency = upgrade tracking, Swift-6/iOS-version compatibility risk, attack surface — all of which v1.0 STACK explicitly minimized for this zero-PII security app. |
| Maintenance | **Highest.** A dependency the team must learn, track, and trust, solving a problem (arbitrary-graph layout) the project does not have. |

**Verdict:** Rejected. Grape is a good library for its purpose — interactive *force-directed* graphs of *unknown* topology. v1.1's trust-graph is neither. Recommending it would mean a SwiftUI violation on the app's core trust surface plus an unjustified shortlist exception.

### Decision Matrix

| Criterion | A: UIView + CAShapeLayer | B: UICollectionView | C: SpriteKit | D: Grape (3rd-party) |
|---|---|---|---|---|
| Interactivity (pan/zoom/tap) | ✅ Excellent | 🟡 Good | 🟡 Good | ✅ Good |
| Layout for fixed 5-node chain | ✅ Trivial | 🟡 Awkward | 🟡 Manual | ❌ Wrong tool (force sim) |
| iPad-native rendering | ✅ Excellent | ✅ Good | 🟡 Scales | 🟡 SwiftUI canvas |
| Accessibility / VoiceOver | ✅ Excellent | ✅ Good | ❌ Poor | ❌ Poor |
| UIKit-first constraint | ✅ Compliant | ✅ Compliant | ✅ Compliant | ❌ SwiftUI-only |
| Dependency-shortlist constraint | ✅ No new dep | ✅ No new dep | ✅ No new dep | ❌ Needs exception |
| Maintenance cost (1–2 eng) | ✅ Lowest | 🟡 Medium | ❌ High | ❌ Highest |

**Option A wins on every criterion that matters.** Recommendation is unambiguous.

---

## Integration Points (how the graph fits the existing architecture)

- **Where it lives:** `validationLedger/Features/Loads/` — the directory already exists (currently just `.gitkeep`). Suggested files: `LoadListViewController.swift`, `LoadDetailViewController.swift`, `TrustGraphView.swift` (the container), `TrustGraphNodeView.swift` (the per-party node), `LoadsCoordinator.swift`, plus `LoadListViewModel` / `LoadDetailViewModel`.
- **Data source:** `LoadDetailViewModel` fetches load detail (including the 5 parties and each party's verification state) via a new `Endpoint` conformer through the existing `APIClient`. The view model hands `TrustGraphView` a plain value-type model (e.g. `[TrustGraphParty]`); the view does no networking. Tapping a node calls back to the coordinator (closure on the view model's init, per the M1 SwiftUI-bridge pattern in v1.0 STACK) to present the verification-basis screen.
- **Networking / mocks:** Add load-domain `Endpoint`s under `Core/Networking/Endpoints/` and JSON fixtures registered in the `Core/Networking/Mock/` registry (mirroring `MockOTPRoleFixtureRegistry` / `MockDefaultFixtures`). The fixtures must cover every verification-state permutation the graph needs to render (verified / pending / unverified / revoked per party) so the discrete graph states are testable without a backend.
- **DI:** `LoadsCoordinator` and the view models receive `APIClient` (and `Logger`, etc.) from `AppContainer` via initializer injection — no change to the composition root beyond registering the new coordinator.
- **Role filtering:** The load *list* is role-filtered; `LoadListViewModel` receives the current role from the existing session/`RoleCoordinator` context. The trust-graph itself renders the same 5-party chain for all roles — only the per-role tender/accept/reject action set on the detail screen varies (a view-model concern, not a graph-rendering one).
- **Security constraints carry over unchanged:** no PII in logs (use the existing `Logger`), nothing sensitive in `UserDefaults`. The graph renders data already in memory from an authenticated fetch — it introduces no new storage or key surface.

---

## What NOT to Add (explicit)

| Avoid | Why | Use Instead |
|---|---|---|
| **Grape** (`SwiftGraphs/Grape`) or any third-party graph/diagram SwiftPM package | SwiftUI-only renderer (violates UIKit-first on the core trust surface); needs a dependency-shortlist exception with no justification; force-directed layout is the wrong tool for a fixed 5-node chain; adds upgrade/compat/attack surface a zero-PII security app should not. | Custom `UIView` nodes + `CAShapeLayer` edges (Option A). |
| **SpriteKit** for the trust-graph | Weak/partial VoiceOver support — unacceptable for the product's core trust-verification surface; a game-engine mental model for a UIKit-fluent team; `SKShapeNode` performance pitfalls; over-engineered for 5 static nodes. | Option A. |
| **A graph-layout algorithm** (Sugiyama / layered / force-directed, hand-rolled or library) | The topology is fixed and known (shipper→broker→carrier→dispatch→factoring). Node positions are deterministic constants. An algorithm solves a problem that does not exist. | A hand-coded fixed layered layout — one column/row per stage. |
| **`swift-snapshot-testing`** added *just* for the graph | M1 deliberately did not adopt it. Adding a dependency for one feature's tests is disproportionate; the graph's deterministic states are coverable with XCUITest screenshots or view-config unit tests. | XCUITest screenshot assertions / plain view-configuration unit tests. A broad snapshot-testing adoption is a separate, milestone-level decision. |
| **`UICollectionView` for the graph** | Custom `UICollectionViewLayout` is more code and more concepts than placing 5 views; collection views pay off with many recycled scrolling items, none of which a 5-node graph has. | `UICollectionView` for the load *list* (its sweet spot); Option A for the graph. |
| **A new networking/real-time dependency** (WebSocket client, SSE library) | v1.1 is explicitly mock-only — no backend, no real-time. The verification state is static fixture data for this milestone. | The existing `MockURLProtocol` + `APIClient` with new fixtures. |
| **Any analytics/crash SDK** | Still out of scope (deferred per PROJECT.md); zero-PII posture unchanged. | Existing `Logger` (`os_log` / `OSLogStore`). |
| **CocoaPods / Carthage** | Spec-locked: SwiftPM-only. | SwiftPM (no new packages anyway). |

---

## Stack Patterns by Variant

**If the chain ever becomes branching/dynamic (multiple carriers, multi-broker chains) in a later milestone:**
- The fixed layered layout still holds for any *tree* — derive node columns from chain depth. Only a genuinely arbitrary graph (cycles, large fan-out) would justify revisiting a layout algorithm or a library.
- Even then, reach for a layered (Sugiyama-style) layout you control before a force-directed library — directed trust chains read best left-to-right, not as a physics blob.

**If a later milestone adds real-time verification-state updates (deferred post-v1.1):**
- The node views just re-render on a new model value pushed by the view model — animate the badge with `CALayer` state transitions. The rendering approach (Option A) does not change; only the data source (mock → live + WebSocket/SSE) does.

**If the team later wants the graph on a SwiftUI surface (not planned — trust-graph is sensitive, stays UIKit):**
- It would not. CLAUDE.md keeps sensitive surfaces UIKit. Documented only to close the loop: do not migrate the trust-graph to SwiftUI.

---

## Version Compatibility

| Item | Version | iOS Min | Notes |
|---|---|---|---|
| UIKit / Core Animation / `UIScrollView` zoom | iOS 17 SDK | 17.0 | First-party; matches the deployment target exactly. No compatibility risk. |
| Nuke (unchanged) | 13.0.2 (pinned `exact`) | 13 | No bump for v1.1. |
| SwiftLintPlugins (unchanged) | 0.63.2 (`from`) | — | No bump for v1.1. |
| Grape (evaluated, **rejected**) | 1.1.0 (2026-01-17) | 17 | iOS 17 / Swift tools 5.9. SwiftUI-only renderer. Not adopted. |

`Package.swift` and `Package.resolved` require **no changes** for v1.1.

---

## Sources

- `.planning/PROJECT.md` — v1.1 scope, constraints, dependency shortlist, mock-only mandate (HIGH — authoritative project doc).
- `.planning/research/v1.0/STACK.md` — validated M1 stack, reused wholesale (HIGH — prior research, context only).
- Repo inspection: `Package.swift`, `Package.resolved` (2 deps: Nuke 13.0.2, SwiftLintPlugins 0.63.2); `validationLedger/Features/Loads/` (exists, empty); `Core/Networking/Mock/` + `Core/Networking/Endpoints/` patterns (HIGH — direct source).
- [Apple — `UIScrollView.minimumZoomScale` / `viewForZooming`](https://developer.apple.com/documentation/uikit/uiscrollview/1619428-minimumzoomscale) — canonical UIKit pan/zoom pattern (HIGH — official docs).
- [Apple — UIKit](https://developer.apple.com/documentation/uikit) — `UIView`, `UIControl`, gesture recognizers, accessibility element model (HIGH — official docs).
- [SwiftGraphs/Grape — GitHub](https://github.com/SwiftGraphs/Grape) and [Grape releases](https://github.com/SwiftGraphs/Grape/releases) — latest 1.1.0 (2026-01-17), iOS 17 / Swift tools 5.9, SwiftUI-only `ForceDirectedGraph`, standalone `ForceSimulation` module (HIGH — repo + release page; evaluated and rejected).
- [Grape — Swift Package Index](https://swiftpackageindex.com/SwiftGraphs/Grape) — package metadata (MEDIUM — index page returned 403 on direct fetch; corroborated via the repo's `Package.swift`).
- WebSearch — SpriteKit pan/zoom (`SKCameraNode`) and `SKShapeNode` performance pitfalls; `CAShapeLayer` as the path-drawing alternative (MEDIUM — community sources, corroborated across results): [SpriteKit touch gestures](https://medium.com/@thomsmed/touch-gestures-and-spritekit-9fe09387104b), [SKCameraNode pan/zoom — Apple Developer Forums](https://developer.apple.com/forums/thread/27843), [Force-directed graphing in iOS](https://medium.com/@joecrozier/force-directed-graphing-in-ios-11202e6e3c48).
- [SwiftGraph (davecom/SwiftGraph)](https://github.com/davecom/SwiftGraph) — noted as a graph *data-structure* library, not visualization; not relevant to rendering (HIGH — repo).

---

*Stack research for: v1.1 "Load Flows" trust-graph rendering decision*
*Researched: 2026-05-19*
*Downstream: v1.1 requirements definition + roadmap creation*
