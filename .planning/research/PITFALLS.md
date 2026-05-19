# Pitfalls Research — v1.1 "Load Flows"

**Domain:** Adding a load domain (role-filtered list, load detail, interactive UIKit chain-of-trust graph, per-role tender/accept/reject) to an existing shipped UIKit / MVVM-C iOS app, built entirely against `MockURLProtocol` fixtures with no backend.
**Researched:** 2026-05-19
**Confidence:** HIGH on UIKit gesture/diffable-data-source/Core Animation API behavior (current Apple docs + verified community post-mortems). HIGH on the mock-to-live and trust/security pitfalls (they derive directly from the project's documented v1.0 contract-first pattern and zero-PII constraint). MEDIUM on the exact graph-layout approach (no graph library is pre-approved; recommendation is to hand-roll, see Pitfall 1).

**Scope note for the roadmap author:** This file covers ONLY pitfalls introduced by the v1.1 load features. Foundation pitfalls (Secure Enclave, Keychain-survives-uninstall, cert pinning, PII scrubber existence, MVVM-C retain cycles, App Attest) are already shipped and verified in v1.0 — see `.planning/research/v1.0/PITFALLS.md`. They are referenced here only where a v1.1 feature *re-triggers* or *depends on* them (e.g., the trust graph must use the existing PII scrubber; tender actions must reuse the v1.0 idempotency-key interceptor). v1.1 is iOS-only against fixtures; no real-time, no push, no backend — pitfalls assume that constraint.

**Phase labels** below (Phase A–D) are suggested v1.1 phase groupings, not committed roadmap phases:
- **Phase A — Load domain model + mock endpoints/fixtures** (the contract)
- **Phase B — Role-filtered load list**
- **Phase C — Load detail + interactive chain-of-trust graph**
- **Phase D — Per-role tender/accept/reject actions**

---

## Critical Pitfalls

### Pitfall 1: Reaching for a third-party graph library — or SwiftUI Canvas — for the chain-of-trust graph

**What goes wrong:**
The interactive chain-of-trust graph (shipper → broker → carrier → dispatch → factoring, tappable nodes with per-party verification state) reads like a "graph visualization" problem, so the instinct is to pull in a force-directed graph SPM package, or to build the node-graph in SwiftUI because declarative layout is faster. Both violate hard project constraints. The dependency shortlist is closed (URLSession wrapper, KeychainAccess, Nuke/SDWebImage, CoreImage, AVFoundation, Vision) — a graph library is not on it and needs explicit approval. SwiftUI is permitted only for "non-critical surfaces like Settings/static lists"; the trust graph is the single most trust-load-bearing surface in the milestone, so it must be UIKit. Either choice gets caught at review and forces a rewrite mid-milestone.

A second failure mode: even if a graph library *were* approved, generic force-directed/physics layout is wrong for this data. The chain of trust is a fixed-topology linear DAG of exactly 5 known party types in a known order. A physics simulation produces a different layout every render, breaks VoiceOver ordering, and makes the graph look unstable/untrustworthy — the opposite of the product message.

**Why it happens:**
"Interactive node-graph" pattern-matches to GraphViz/D3/force-directed libraries. SwiftUI's `Canvas` and `Path` look like the fastest way to draw nodes and edges. Neither the dependency constraint nor the "UIKit for critical surfaces" rule is top-of-mind when scoping a visualization task.

**How to avoid:**
1. Treat the trust graph as a **deterministic, fixed-layout UIKit custom view**, not a graph-algorithm problem. The topology is always the same 5 ordered roles; positions are computed, not simulated. Hand-roll it: a `UIScrollView` (or plain `UIView`) host containing `CALayer`/`UIView` node subviews plus `CAShapeLayer` edges. No SPM dependency required — this keeps the closed shortlist intact.
2. Lay out nodes with deterministic math (a horizontal/vertical chain on iPhone, a wider native layout on iPad — see Pitfall 5). Same input → same pixels, every time. This is also what makes it testable.
3. If a node-graph library is genuinely wanted, it requires **explicit approval before Phase C starts** — raise it during roadmap creation, not mid-build. Default assumption: hand-rolled, no dependency.
4. Keep it UIKit — the graph is a "critical surface" by the spec's own wording. SwiftUI is not an option here.

**Warning signs:**
- A new entry in `Package.swift` / `Package.resolved` for a graph/chart/visualization package.
- `import SwiftUI` appearing in `Features/Loads/`.
- Node positions that differ between two renders of the same load.
- Phrases like "force-directed" or "physics" in the graph plan.

**Phase to address:** Phase C. The graph rendering approach (hand-rolled UIKit, deterministic layout, no dependency) must be a ratified decision in the Phase C plan before any graph code is written.

---

### Pitfall 2: Gesture conflicts on the trust graph — node taps swallowed by scroll/pan, or pan stolen from an enclosing scroll view

**What goes wrong:**
The graph needs at least three gestures: tap a node (open that party's verification basis), pan/scroll to see the whole chain (5 nodes won't fit one iPhone screen), and possibly pinch-to-zoom. When the graph view is itself inside a scrolling load-detail screen (`UIScrollView` or `UITableView`/`UICollectionView`), the gestures fight:
- A tap on a node is interpreted as the start of a scroll and never fires `touchUpInside` — the user taps a party and nothing happens.
- A pan inside the graph scrolls the *outer* load-detail screen instead of panning the graph, or vice versa — the graph and the page scroll-jack each other.
- Pinch-to-zoom on the graph triggers nothing because the gesture is consumed by an ancestor, or zooming the graph also drags the page.

The result is a flagship feature that feels broken on the first demo and reads as "untrustworthy" on a trust product.

**Why it happens:**
UIKit's default gesture arbitration delivers a touch to the deepest hit-tested view, and `UIScrollView`'s pan recognizer aggressively claims drags. Nested scroll views and tap targets inside scroll views are a known-hard UIKit problem. Developers test on the simulator with a trackpad where the distinction between "tap" and "tiny drag" is cleaner than on a real finger, so conflicts surface late.

**How to avoid:**
1. Decide the interaction model explicitly and write it into the Phase C plan: is the graph a self-contained zoom/pan `UIScrollView`, or a fixed-size view inside the page scroll? Recommended: graph is a **fixed-aspect view sized to its content**, the *page* scrolls; the graph itself only handles node taps (and optional pinch). This removes the pan-vs-scroll conflict entirely.
2. If the graph must independently pan/zoom, embed it in its own `UIScrollView` and use `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` and `UIGestureRecognizerDelegate` to define precedence deliberately. Use `UIScrollView`'s `panGestureRecognizer.require(toFail:)` relationships rather than hoping arbitration does the right thing.
3. Make node tap targets generous — minimum 44×44pt hit area per Apple HIG, even if the rendered node glyph is smaller. A node that is visually 28pt with a 44pt hit region tolerates imprecise dock-glove taps.
4. Implement `point(inside:with:)` / `hitTest(_:with:)` on the graph container so taps that land on edges-between-nodes or empty canvas do not register as node taps (and do not get mis-routed).
5. Test on a physical device with a finger, not the simulator with a trackpad — the existing v1.0 device CI lane is the place to add a graph interaction smoke test.

**Warning signs:**
- Taps on nodes that "sometimes" work.
- The load-detail page scrolling when the user meant to pan the graph.
- No `UIGestureRecognizerDelegate` on the graph despite nested scrolling.
- Graph interaction only ever tested on the simulator.
- Node hit areas equal to the rendered glyph size.

**Phase to address:** Phase C. Gesture arbitration must be designed up front; retrofitting it after the graph renders is a partial rewrite.

---

### Pitfall 3: The trust graph shows "verified" the client cannot actually attest — security-critical for a fraud-prevention product

**What goes wrong:**
The chain-of-trust graph renders each party with a verification state (verified / pending / unverified). The tempting client implementation derives that state locally — checks whether a field is present, whether an MC number "looks valid," whether a counterparty has a KYC-complete flag in the fixture, and paints a green checkmark. For a product whose entire premise is "identity that cannot be spoofed and a chain-of-trust that cannot be faked," a client that *computes* trust is a fraud vector: a tampered response, a stale cache, or a mock fixture quietly becomes an authoritative-looking "verified" badge. The user trusts the green check; the green check trusts unverified data.

This is the v1.1 re-trigger of the v1.0 "client never validates claims; backend is sole authority" security rule (v1.0 Security Mistakes table) — but now it has a *visual surface*, which is far more dangerous because a green checkmark is a stronger trust signal than any JSON field.

A related failure: the graph caches the last-fetched chain and re-displays it offline or on a stale screen, showing a chain-of-trust that *looks* current but isn't — v1.0 explicitly bans "offline chain-of-trust."

**Why it happens:**
Against mocks there is no backend to be the authority, so "verification state" has to come from *somewhere* — and the path of least resistance is to compute it on the client from fixture fields. Once that code exists, the live swap (Pitfall 9) doesn't remove it; it just keeps running alongside the real signal.

**How to avoid:**
1. **Verification state is a server-supplied, opaque enum on every party in the load contract** — `verificationState: "verified" | "pending" | "unverified" | "revoked" | "unknown"` plus a server-supplied human-readable `verificationBasis`. The client *renders* it; the client never *derives* it. Design this into the load-domain contract in Phase A.
2. The client must have **no code path that upgrades a party's displayed trust** based on local logic. No "if MC number present → verified." Lint/review for any conditional that maps a non-state field to a verification visual.
3. Default to the *least*-trusted rendering when state is absent, malformed, or unknown — never default a missing field to "verified." Treat `unknown` as visually distinct and non-reassuring.
4. **No offline / cached chain-of-trust.** The graph is only valid for a freshly fetched load. If the load fetch is stale or failed, show an explicit "trust chain unavailable" state, not the last-known graph.
5. Make the mock fixtures *honest* about this (Pitfall 8): fixtures must include parties in `pending`, `unverified`, and `revoked` states so the UI is built and tested against the un-reassuring cases, not just the all-green happy path.
6. The tappable "verification basis" detail must show the *server's* stated basis, verbatim — never client-composed reassurance copy.

**Warning signs:**
- Any client-side function returning a verification verdict.
- A missing/unknown verification field rendering as green/verified.
- The graph displaying after a failed or stale load fetch.
- Fixtures where every party is `verified`.
- Client code constructing the "why this party is verified" explanation text.

**Phase to address:** Phase A (contract: verification state is server-supplied and opaque) and Phase C (rendering: render-only, fail-closed to least-trusted).

---

### Pitfall 4: Optimistic tender/accept/reject UI against mocks that always succeed — building a UI that has never seen a failure

**What goes wrong:**
Tender/accept/reject actions feel best with optimistic UI: tap "Accept," the load immediately moves to the accepted state, the action set updates, no spinner. Against `MockURLProtocol` fixtures that return `200` instantly, this looks perfect — and that is the trap. The optimistic path is the *only* path that ever gets exercised. The rollback path (server rejects the action, returns `409 Conflict` because another party already accepted, returns `422` because the load moved state, times out, returns `401`) is never written, or is written and never run. When the live backend lands (post-v1.1), the first real `409` leaves the UI showing "accepted" for a load that is actually still tendered — a correctness failure on a fraud product where load state *is* the chain of custody.

A subtler version: the optimistic update mutates the in-memory load object, the action "succeeds" against the mock, but nothing reconciles the optimistic local state with the authoritative server representation — so the displayed load drifts from truth with every action.

**Why it happens:**
Mocks that only model the happy path make optimistic UI look free. There's no server to say no, so "what happens when the server says no" never gets built. Optimistic UI is genuinely the right UX — the mistake is shipping it without its rollback half.

**How to avoid:**
1. For every optimistic action, build the **rollback path in the same plan as the forward path** — they are one unit of work, not two. Tap → apply optimistic state → on failure, revert to the pre-action state *and* surface a non-modal error ("Couldn't accept — this load was already accepted by another party").
2. Capture the pre-action snapshot before mutating, so rollback is exact. Don't reconstruct the prior state — store it.
3. **Mock fixtures must include the rejection cases** (see Pitfall 8): a fixture set where accept returns `409` (already-accepted race), `422` (load no longer in a tenderable state), `401` (session expired mid-action), and a delayed/timeout response. The optimistic UI is not "done" until it has been demoed against each.
4. After a successful action, the server response is the new source of truth for that load — reconcile the optimistic state against the returned representation rather than trusting the local mutation. Against mocks, make the success fixture return the *full updated load*, so this reconciliation code exists and runs from day one.
5. For destructive/irreversible-feeling actions (reject), consider a confirm step rather than pure optimism — a mis-tapped reject on a load is expensive.
6. Reuse the v1.0 idempotency-key interceptor on every tender/accept/reject request so a retry after an ambiguous failure can't double-apply (see Pitfall 6).

**Warning signs:**
- Action handlers with a success branch and no failure branch.
- No fixture returns a non-2xx for a load action.
- The pre-action state isn't captured before the optimistic mutation.
- Optimistic UI demoed only against instant-200 mocks.
- The success fixture returns `{}` or `204` instead of the updated load.

**Phase to address:** Phase D (actions), with the failure/latency fixtures created in Phase A.

---

### Pitfall 5: iPad gets a scaled-up iPhone trust graph instead of a native layout

**What goes wrong:**
The constraint is explicit: "iPad must render natively (not just scale)" because dispatch and factoring users frequently work on iPad. The load list and especially the chain-of-trust graph are easy to build iPhone-first — a single-column list, a vertically-stacked 5-node chain — and then let iPad just stretch it. On a 12.9" iPad that produces a comically tall thin chain in a sea of whitespace, or a one-column list that wastes two-thirds of the screen. It "works" so it ships, and the iPad experience silently degrades the product for two of its five roles.

The trust graph is the worst offender: a vertical chain that's fine on iPhone looks broken on iPad, and a layout that adapts node spacing but not *arrangement* still isn't "native."

**Why it happens:**
iPhone-first is the default development posture; iPad is tested last or only via the simulator's "scale" affordance. Auto Layout will happily stretch a single-column layout to any width without complaint, so there is no error to catch it. v1.0 shipped placeholder role shells, so this is the first milestone where real iPad layout decisions actually bite.

**How to avoid:**
1. Design **two layouts up front** for the load list and the graph: a compact-width layout (iPhone, multitasking-narrow iPad) and a regular-width layout (iPad full-screen). Drive the choice off `UITraitCollection.horizontalSizeClass`, not device idiom — this also handles iPad Split View and Slide Over correctly.
2. Load list on regular width: consider a multi-column `UICollectionViewCompositionalLayout`, or a list + detail split (`UISplitViewController`) so iPad shows list and load detail side by side. Compact width: single column.
3. Trust graph on regular width: a wider, more horizontal arrangement that uses the available width; compact width: the chain folds. The graph's deterministic layout (Pitfall 1) should take available size as an input and arrange accordingly.
4. The graph view must respond to `traitCollectionDidChange` and to bounds changes — iPad multitasking resizes the window live; a graph laid out once at load time will be wrong after a Split View drag.
5. Add iPad (regular-width) checks to the existing v1.0 per-role render smoke tests — one pass per role on an iPad size class.

**Warning signs:**
- Layout code that branches on `UIDevice.current.userInterfaceIdiom` instead of size class.
- The graph or list never tested in iPad Split View / Slide Over.
- A single column layout on a 12.9" iPad.
- The graph laid out once and never re-laid-out on bounds change.

**Phase to address:** Phase B (list) and Phase C (graph). Native iPad layout is a first-class acceptance criterion for both, not a polish-phase afterthought.

---

### Pitfall 6: Tender/accept/reject without idempotency or invalid-transition guards — double-apply and impossible state

**What goes wrong:**
Two related correctness failures on the load action set:
- **Double-apply:** the user taps "Accept," the request is slow (or fails ambiguously — request sent, response lost), they tap again. Without an idempotency key reused across the retry, that's two accept requests. Against a mock it's harmless; against a real backend it can double-tender a load or create two acceptances. On a fraud product the load action history *is* the chain of custody — a duplicated action corrupts it.
- **Invalid transition:** the action set offered to the user isn't gated by the load's current state. A load already `delivered` still shows "Reject"; a `cancelled` load still shows "Accept." The client lets the user attempt a transition the load can't make, and either the UI lies (optimistically applies it) or the user gets an opaque error.

**Why it happens:**
v1.0 already shipped an idempotency-key interceptor (NET-04) — but it was built for the KYC/auth endpoints. It's easy to add the new load-action endpoints *without* wiring them through that interceptor, because nothing forces it. And against mocks, double-submits and invalid transitions both silently "succeed," so neither is visible in development.

**How to avoid:**
1. **Every tender/accept/reject request goes through the existing v1.0 idempotency-key interceptor.** Generate the key when the user initiates the action (not per-retry), so all retries of *that* action share one key. Verify in Phase D that the new endpoints are registered with the interceptor — make it a review checklist item.
2. Disable the action control the instant it's tapped (in-flight), so a second tap is physically impossible while the first is pending. Optimistic UI (Pitfall 4) helps here — the control updates immediately — but also explicitly guard the in-flight state.
3. **Available actions are a pure function of (load state, viewer role)** — compute the offered action set from the load's current state and never offer an action the state can't accept. See Pitfall 7 for where that logic lives.
4. The backend is still the authority on whether a transition is allowed (it is post-v1.1, and the mock should emulate it now): even with client-side gating, a `409`/`422` from a stale-state action must be handled (Pitfall 4).

**Warning signs:**
- New `Features/Loads` action endpoints not listed in the idempotency interceptor's registration.
- An action button that can be tapped twice before the first request resolves.
- The action set rendered statically instead of computed from load state.
- A new idempotency key generated on each retry instead of per-action.

**Phase to address:** Phase D, with the idempotency-interceptor wiring verified explicitly because it's a v1.0 component the new endpoints must opt into.

---

### Pitfall 7: Load state machine + role-action gating leaking into view controllers

**What goes wrong:**
The load domain has a state machine (e.g., `draft → tendered → accepted → in_transit → delivered → closed`, plus `rejected`/`cancelled`) and a role-permission matrix (which of the 5 roles may tender, accept, reject, in which states). The natural-but-wrong place to put this is the view layer: the load-detail view controller has a `switch load.status` deciding which buttons to show, the list cell has its own copy of "can this role act on this load," and each of the 5 role tab shells re-implements the gating slightly differently. The business rules end up smeared across views, duplicated, and inconsistent — and because views are the hardest layer to unit-test, the rules are effectively untested. A wrong gate on a fraud product means a role performing an action it should not be able to (e.g., a carrier accepting a load tendered to a different carrier).

This is the v1.1-specific shape of the v1.0 "Massive ViewModel" pitfall — except here the logic doesn't even reach the ViewModel, it stops in the VC.

**Why it happens:**
A `switch` on status inside `cellForItemAt` or `viewDidLoad` is the shortest path to "show the right buttons." With 5 roles each having a tab shell, copy-paste across roles is faster than a shared abstraction. There's no compiler pressure to centralize.

**How to avoid:**
1. Model the load state machine **once, as a value type in the load domain layer** (Phase A): an explicit `LoadState` enum and a single `allowedActions(for role: Role, in state: LoadState) -> [LoadAction]` function (or a transition table). This is pure, deterministic, and trivially unit-testable — and *one* place defines the rules for all 5 roles.
2. ViewModels call that function and hand the view a ready-made list of actions to render. **Views render the action list; views contain zero `switch load.status`.** The 5 role shells share this — they do not each re-derive gating.
3. Represent illegal states as unrepresentable where practical — e.g., a load action carries the state it's valid from, so an action can't be constructed for a wrong state.
4. Unit-test the transition table directly: every (role, state) pair → expected action set. This is cheap, exhaustive, and the v1.0 ≥70% Core/ coverage gate should cover the load-domain module.
5. The client state machine mirrors the server's, but the **server remains the authority** — client gating is a UX affordance (don't offer impossible actions), not the enforcement boundary (Pitfall 4, Pitfall 6).

**Warning signs:**
- `switch load.status` or `if load.state ==` inside a `UIViewController` or cell.
- Role-permission logic duplicated across `Roles/Shipper`, `Roles/Broker`, etc.
- No standalone unit test for "which actions can role X take on a load in state Y."
- The action-gating logic only exists where it's rendered.

**Phase to address:** Phase A (the state machine + permission matrix as a tested value-type module) before any role action UI is built in Phase D.

---

### Pitfall 8: Mock fixtures that only model the happy path — no errors, no latency, no empty/large datasets

**What goes wrong:**
v1.0's `MockURLProtocol` returns a fixture instantly with a fixed status code. If the v1.1 load fixtures follow that pattern naively, every load list loads instantly, every load has a full 5-party chain, every action returns `200`. The UI gets built and demoed against a world that has no slow networks, no empty states, no partial data, no errors. Then:
- There's no loading state because the mock never made the user wait → first real slow fetch shows a frozen blank screen.
- There's no empty state because every fixture has loads → a role with zero relevant loads shows a blank list that looks broken.
- There's no error state because every fixture is `200` → a real `500`/timeout shows nothing or crashes.
- There's no large-list behavior because the fixture has 6 loads → cell reuse / scroll perf (Pitfall 11) is never exercised.
- The trust graph is only ever all-green because no fixture has a `pending`/`revoked` party (Pitfall 3).

**Why it happens:**
Fixtures are written to make the feature *demo*, and a demo wants the happy path. The v1.0 `MockURLProtocol` has no built-in notion of latency or failure injection, so adding those is extra work that's easy to skip.

**How to avoid:**
1. For the load domain, build a **fixture matrix, not a fixture** — for each endpoint: happy path, empty result, large result (50–100+ loads), partial/degraded data (a load with an incomplete chain, missing optional fields), and each error class (`401`, `409`, `422`, `500`, timeout).
2. Extend `MockURLProtocol` (or the fixture registration helper) to support **injectable latency and failure** — a fixture can be registered with a delay and/or a forced error. v1.0's `MockURLProtocol` is synchronous and instant; adding a delay capability now is what makes loading-state and timeout code real. This is a Phase A deliverable.
3. Make it trivial to flip the active fixture set at runtime in DEBUG (the existing `App/DevMenu` is the place) so QA and the engineer can drive empty/error/large states without recompiling.
4. **Acceptance criterion for every load screen:** it has been demoed against the empty, error, and slow fixture — not just the happy fixture. Add this to the "looks done but isn't" checklist.
5. The fixture *shapes* must match the eventual backend contract, not be convenient JSON (Pitfall 9).

**Warning signs:**
- One fixture per endpoint, all `200`.
- No latency anywhere in the mock layer.
- No empty-state or error-state UI in the load screens.
- The load list fixture has <10 items.
- Every party in every chain fixture is `verified`.

**Phase to address:** Phase A — the fixture matrix and the latency/failure-injection capability are foundational; every subsequent phase consumes them.

---

### Pitfall 9: Over-fitting load features to fixture shapes — the mock-to-live swap forces a client refactor

**What goes wrong:**
The whole point of v1.1's mock-only scope is that v1.0 proved contract-first dev needs no server, and the live backend swap is "one line" (NET-02). That promise only holds if the load features are built against a *contract*, not against the *fixtures*. The over-fitting failure modes:
- The load list isn't paginated because the fixture is one flat array — the live backend returns pages, and the list, ViewModel, and diffable snapshot logic all need rework.
- Decoding is loose: the JSON decoder tolerates the exact fixture shape, optional-vs-required is guessed, date formats match whatever the fixture author typed. The live backend's slightly different (but valid) JSON throws decode errors.
- IDs are hardcoded: a screen navigates to "load `LOAD-001`" because that's the fixture ID, or a test asserts against a literal fixture ID embedded in product code.
- The graph assumes exactly 5 parties always present because every fixture has 5 — the live backend returns a load with a chain still being assembled (3 parties) and the graph crashes or renders wrong.
- Error handling keys off fixture-specific error bodies instead of HTTP status + a typed error contract.

When the live backend lands post-v1.1, "swap the base URL" turns into a multi-week refactor — defeating the entire scoping rationale.

**Why it happens:**
The fixture is concrete and in front of you; the contract is abstract. It's faster to decode exactly what the fixture contains. Pagination, partial chains, and strict decoding feel like premature work when there's no server to demand them.

**How to avoid:**
1. **Write the load-domain API contract first, as the source of truth** (Phase A): typed request/response models, pagination shape (cursor or page+limit — pick one and build the list against it *now*, even though the mock returns it all at once), the verification-state enum (Pitfall 3), the error contract (typed errors off HTTP status). Fixtures are generated *to satisfy the contract*, not the other way around.
2. **Build the list with pagination from day one** — the ViewModel requests pages, the diffable data source appends pages, infinite-scroll/"load more" exists — even though the Phase A mock can return everything in page 1. This is the single highest-value anti-over-fitting move.
3. **Strict decoding:** model required fields as non-optional, optional fields as optional, deliberately — not "whatever made the fixture decode." Decode dates with an explicit strategy. A decode failure must be a typed, surfaced error, not a silent `nil`.
4. **No hardcoded load/party IDs in product code.** IDs are opaque, server-supplied, treated as `String`/UUID. Tests may use fixture IDs, but product code never branches on a literal ID.
5. The graph must handle a **variable-length / partial chain** — fewer than 5 parties, parties out of order, a party absent. Never index the chain assuming `[0...4]`.
6. Keep the one-line mock/live swap honest: the only difference between mock and live is the `URLProtocol` / base URL — no feature code branches on "are we mocked."

**Warning signs:**
- The load list has no pagination concept.
- Decoding uses `try?` and all-optional models.
- A literal load ID in a non-test source file.
- Graph code that assumes exactly 5 parties.
- `if isMocked` anywhere in feature code.
- The fixture was written before the contract.

**Phase to address:** Phase A (contract + pagination shape + strict models) is the load-bearing one; Phase B and C must honor it (paginated list, variable-length graph).

---

### Pitfall 10: VoiceOver and Dynamic Type on the trust graph treated as a custom-drawn black box

**What goes wrong:**
The chain-of-trust graph, if drawn with `CALayer`/`CAShapeLayer` or `draw(_:)`, is invisible to assistive tech by default — it's just pixels. A VoiceOver user swipes across the graph and hears nothing, or hears "image." For a fraud-prevention product, the verification state of each counterparty is *the* critical information — making it inaccessible isn't a polish gap, it excludes users from the core safety feature. Likewise, node labels drawn at a fixed point size ignore Dynamic Type entirely — a user with large text sees a graph with unreadable party names and verification labels.

The v1.0 "looks done but isn't" checklist already requires Dynamic Type + VoiceOver on the KYC flow; v1.1 must extend that discipline to the graph, and a custom-drawn graph is exactly the kind of surface where it silently doesn't happen.

**Why it happens:**
Custom-drawn UIKit content has no automatic accessibility — unlike standard `UILabel`/`UIButton` which are accessible for free. Drawing into a layer is the fastest way to *render* the graph, and accessibility is a separate, explicit, easily-deferred step. Dynamic Type requires using `UIFont.preferredFont`/text styles and re-laying-out on `UIContentSizeCategory` changes — extra work a custom view doesn't get automatically.

**How to avoid:**
1. Prefer **real `UIView` subviews for nodes** over pure `CALayer` drawing where feasible — a node built from a `UIView` + `UILabel` + image is far easier to make accessible and Dynamic-Type-aware than a drawn layer. Use `CAShapeLayer` for the *edges* (lines), `UIView`s for the *nodes* (the interactive, labeled, trust-bearing parts).
2. Expose each node as an **accessibility element** with a meaningful `accessibilityLabel` (party role + name) and `accessibilityValue` (verification state — "verified", "pending", "not verified"), and an `accessibilityHint` ("double-tap for verification details"). If the graph is one drawn view, implement `accessibilityElements` returning a synthetic element per node, ordered shipper→factoring so VoiceOver traversal matches the chain.
3. Order matters: VoiceOver must traverse the chain in chain order. A deterministic layout (Pitfall 1) makes this straightforward; a physics layout makes it impossible.
4. Node labels use `UIFont.preferredFont(forTextStyle:)` and the view observes `UIContentSizeCategory.didChangeNotification` (or `traitCollectionDidChange`) to re-lay-out when text size changes. At the largest accessibility sizes, the graph may need to reflow (e.g., labels below nodes, or the chain folds) — plan that, don't clip.
5. Add a graph VoiceOver + Dynamic Type pass to the v1.1 "looks done but isn't" checklist; verify with the largest Dynamic Type size and a full VoiceOver swipe-through.

**Warning signs:**
- The graph is one `draw(_:)` view with no `accessibilityElements`.
- Node labels created with `UIFont.systemFont(ofSize:)` (fixed size).
- VoiceOver on the graph announces nothing or "image."
- No re-layout on content size category change.
- Verification state conveyed by color only (also fails color-blind users — pair color with a glyph/label).

**Phase to address:** Phase C — accessibility is built into the graph as it's built, not bolted on. (The full v1 accessibility pass is M4, but the graph is too central to defer entirely.)

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Build the load list as a flat non-paginated array because the mock returns everything | Faster Phase B; no "load more" UI | Live backend returns pages → list, ViewModel, diffable snapshot all reworked; breaks the "one-line swap" promise | Never. Build pagination in Phase B against a paginated mock; the mock can still return one page. |
| Compute verification badge state on the client from fixture fields | Mocks have no backend to be the authority, so this "just works" | A trust signal derived client-side is a fraud vector; survives the live swap as dead-but-running code | Never. Verification state is server-supplied and opaque (Pitfall 3). |
| `switch load.status` inside the load-detail VC / cells | Shortest path to "show the right buttons" | Business rules smeared across 5 role shells, duplicated, untested, inconsistent | Never. State machine + action gating is one tested value-type module (Pitfall 7). |
| Optimistic action UI with only a success branch | Demos beautifully against instant-200 mocks | First real `409`/timeout leaves the UI lying about load state | Never. Rollback path ships in the same plan as the forward path (Pitfall 4). |
| Loose decoding (`try?`, all-optional models) tolerant of the fixture | Fixture decodes on the first try | Live backend's valid-but-different JSON throws or silently drops fields | Never. Strict typed models, explicit optionality, typed decode errors. |
| Hardcode a fixture load/party ID in product code to navigate or branch | Quick to wire a screen during Phase B/C | Breaks the moment IDs are server-generated; couples product code to test data | Never in product code. Test code may reference fixture IDs. |
| Hand-roll the graph as one `draw(_:)` layer with no accessibility | Fastest way to get pixels on screen for a demo | VoiceOver users excluded from the core safety feature; expensive accessibility retrofit | Acceptable as a throwaway spike only; the shipped graph uses `UIView` nodes + accessibility elements (Pitfall 10). |
| `MockURLProtocol` fixtures with only happy-path, instant, all-green data | Fast to write; demo looks great | Loading/empty/error/large-list states never built; surface as bugs post-v1.1 | Never. Fixture matrix + latency/failure injection is a Phase A deliverable (Pitfall 8). |
| Graph laid out once at load time, no re-layout on bounds change | Simpler layout code | Wrong layout after iPad Split View resize or rotation | Never on a product where iPad is first-class; respond to `traitCollectionDidChange` + bounds (Pitfall 5). |
| Add new load-action endpoints without registering them with the v1.0 idempotency interceptor | One less wiring step | Double-apply on retry corrupts the load action history (the chain of custody) | Never. Every load action goes through the interceptor (Pitfall 6). |

## Integration Gotchas

Common mistakes when integrating the new load domain with existing v1.0 systems and the (mocked) network layer.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `MockURLProtocol` (v1.0, synchronous) | Reusing it as-is — it returns instantly, so loading/timeout states never get built | Extend the fixture layer with injectable latency + forced-failure before building any load screen (Phase A). |
| v1.0 idempotency-key interceptor (NET-04) | New load-action endpoints not registered with it — only KYC/auth endpoints were | Register every tender/accept/reject endpoint; verify at Phase D review; key generated per-action, shared across retries. |
| v1.0 PII scrubber / Logger (LOG-01, lint-enforced) | Logging the load fixture / party objects raw during development — counterparty names, MC numbers, addresses are PII | All load-domain logging goes through the existing Logger; never log raw load/party objects; the scrubber's denylist may need party-field keys added. |
| v1.0 `APIClient` GET-retry backoff (NET-05) | Assuming GET retry is safe for the load list — fine — but reusing it for action POSTs | GET retry is for idempotent reads only; action POSTs rely on the idempotency key, not blind retry. |
| v1.0 `RoleCoordinator` / 5 tab shells | Each role shell building its own load list/detail/gating — divergent copies | Load list/detail/graph are shared `Features/Loads` components parameterized by role; gating from the shared state-machine module. |
| v1.0 `URLSession` cache policy | Load + chain-of-trust responses served from URL cache → stale trust shown | Authenticated load endpoints use `.reloadIgnoringLocalCacheData` (v1.0 already flags this for chain-of-trust). |
| v1.0 401 auto-logout (AUTH-05) | A `401` mid-action (tender/accept) triggering auto-logout without reverting the optimistic UI | The optimistic-state rollback must run before/with the auto-logout teardown, or the user re-logs-in to a load that lies. |
| v1.0 `DeepLinkRouter` | Adding `validationledger://load/<id>` deep links with the load ID as PII, or not handling cold-launch | Opaque load IDs only; route load deep links through the existing central router (v1.0 cold-launch race handling applies). |

## Performance Traps

Patterns that work at small scale but fail as the load list grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `cellForItemAt` does work that belongs in the model — date formatting, role-gating computation, building the action list per cell | List scroll stutters; CPU spikes while scrolling | Cells are dumb; pre-compute display models (formatted strings, action lists) off the main thread or at decode time; cell config is assignment only | Noticeable at 50+ loads; severe at 200+ |
| Diffable snapshot rebuilt from scratch and `apply`-ed on every minor change (a single load's state) | Whole-list flicker; scroll position jumps; animation churn | Apply targeted snapshots; use `reconfigureItems` for content changes to existing rows (iOS 15+), not full-list reload | As soon as live-ish updates touch the list (even mock-driven refresh) |
| Trust graph rebuilds all node `UIView`s / `CAShapeLayer`s on every state change | Graph flickers; janky on redraw; CPU spike | Build node/edge views once; update only the changed node's verification visual; never tear down and rebuild the whole graph | Every time a party's state changes, or on re-fetch |
| Heavy `CALayer` shadows / `cornerRadius` without `shouldRasterize` / `cornerCurve` on every node and cell | Offscreen-render passes; scroll/redraw jank, worst on older iPads | Avoid unclipped shadows; if needed set `shadowPath`; rasterize static node layers; profile with Core Animation instrument | Graph with 5 shadowed nodes + a list of shadowed cells, on iPad |
| Load list images (party logos, load photos) decoded on the main thread in `cellForItemAt` | Scroll stutter when cells with images appear | Use the v1.0-approved Nuke for async image loading + downsampling; never `UIImage(data:)` synchronously in a cell | Any list with per-row imagery |
| No cell-prefetching / the ViewModel fetches the next page only after the user hits the absolute bottom | Visible pause at the end of each page | Prefetch the next page when the user nears the end (`UICollectionViewDataSourcePrefetching` or a threshold in `willDisplay`) | Paginated list, page 2 onward |
| Recomputing the role-filtered list on the main thread on every snapshot | UI hitch on filter changes | Filtering is a pure function over the loaded set; compute off-main, apply the resulting snapshot on main | Filtering 200+ loads across role criteria |

## Security Mistakes

Domain-specific issues for the load features on a fraud-prevention product. (Foundation security — Keychain, Secure Enclave, cert pinning, PII scrubber existence — is v1.0-shipped; these are v1.1-new.)

| Mistake | Risk | Prevention |
|---------|------|------------|
| Client derives/upgrades a party's "verified" badge from local logic | A green checkmark — the strongest trust signal in the app — vouches for unverified data; tampered/stale response becomes "verified" | Verification state is a server-supplied opaque enum, render-only; fail closed to least-trusted on missing/unknown (Pitfall 3). |
| Caching the chain-of-trust and showing it offline or after a stale fetch | User sees a chain that looks current but isn't — a load could have changed hands | No offline/cached chain-of-trust; show "trust chain unavailable" on stale/failed fetch (v1.0 already bans this). |
| Logging load/party objects during development — counterparty names, MC numbers, addresses, phone numbers | PII leak; on a trust product one screenshot of a log with a counterparty's data ends the trust | Route all load logging through the v1.0 Logger/scrubber; never log raw load/party objects; extend the scrubber denylist with party-field keys; audit before milestone close. |
| Load ID or party identifier in a `validationledger://` deep-link, Spotlight item, or `UIActivityViewController` payload | PII / business-relationship data leaks via Shortcuts, clipboard, share sheet | Deep links and shareable identifiers are opaque UUIDs only; no party PII in any URL. |
| Trusting client-side load state as authoritative for what an action does | Client-side state machine is a UX affordance; if treated as enforcement, a tampered client performs disallowed transitions | Backend is the sole authority on transitions; client gating only hides impossible actions; every action result re-verified server-side (mock should emulate `409`/`422`). |
| Action requests not device-signed (reusing the v1.0 device-signature requirement) | A leaked token alone could tender/accept/reject loads | Tender/accept/reject are sensitive actions — carry the v1.0 device-signed header; the request signature binds method+path+body (v1.0 Security Mistakes table). |
| Verification state conveyed by color alone (green/amber/red) | Color-blind users can't distinguish verified from revoked — a safety-information failure | Pair every verification state with a distinct glyph + text label, not color alone (also an accessibility requirement, Pitfall 10). |
| Showing a `revoked`/`unverified` party with reassuring or ambiguous styling | User proceeds with a load whose counterparty failed verification | Un-trusted states get visually prominent, non-reassuring treatment; the un-happy path is the one the fraud product most needs to be loud. |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Role-filtered list shows a blank screen when a role has zero relevant loads | User thinks the app or their account is broken | Explicit, role-appropriate empty state ("No loads tendered to you yet") — built from a real empty fixture (Pitfall 8). |
| No loading state because mocks are instant | First real slow fetch shows a frozen blank screen | Skeleton/loading state on every load screen, exercised against a latency-injected fixture. |
| Full-screen error on a load-list fetch blip traps the user | User stuck, can't navigate | Inline retry banner for list/detail fetch failures; full-screen only for auth expiry. |
| Tender/accept/reject buttons with no confirmation on the destructive ones | A mis-tapped "Reject" on a load is costly and feels irreversible | Confirm destructive actions; keep non-destructive ones optimistic and instant. |
| Action fails (optimistic rollback) with a generic "Something went wrong" | User doesn't know if the load is accepted or not — on a chain-of-custody product that's alarming | Specific, state-accurate message ("This load was already accepted by another carrier") + the load visibly reverts to its true state. |
| The trust graph shows all-green and reads as decoration | User stops *reading* the graph; the one time a party is `revoked`, they miss it | Make verification state the visual focus; un-trusted parties are loud; tapping a node always reveals the basis, even for verified ones. |
| Graph too small/dense to tap on iPhone; 5 nodes crammed edge-to-edge | Users can't reliably tap the party they want | 44pt minimum hit targets; pan or fold the chain rather than shrinking nodes (Pitfalls 2, 5). |
| Load detail doesn't show *why* an offered action is unavailable (greyed with no reason) | User confused why they can't accept | When an action is gated out, either omit it cleanly or show the reason ("Awaiting broker tender"). |
| iPad shows a single-column list + separately-pushed detail like a stretched iPhone | Wastes the screen the dispatch/factoring users chose for the work | `UISplitViewController` list+detail on regular width (Pitfall 5). |

## "Looks Done But Isn't" Checklist

Run as explicit acceptance criteria before marking v1.1 items complete.

- [ ] **Role-filtered load list:** Each of the 5 roles shows the correct subset. Test: one fixture-driven pass per role; verify a load visible to role A is correctly absent for role B, and the filter is one shared tested function — not 5 copies.
- [ ] **Load list — empty state:** Renders a real empty state, not a blank screen. Test: load the empty fixture for a role.
- [ ] **Load list — error state:** Renders an inline retry, not a frozen screen or crash. Test: load the `500`/timeout fixture.
- [ ] **Load list — loading state:** Shows a skeleton/spinner. Test: load a latency-injected fixture (mock must support delay).
- [ ] **Load list — large dataset:** Smooth scroll, correct cell reuse, no stale content in reused cells. Test: 100+ -item fixture; scroll fast; verify no leftover data in recycled cells.
- [ ] **Load list — pagination:** "Load more"/infinite scroll works even though the mock can return all in page 1. Test: paginated fixture with ≥2 pages.
- [ ] **Diffable data source:** Item identifiers are unique and stable (opaque load IDs, not array indices, not whole value objects). Test: a snapshot with duplicate-ID input must be impossible by construction; content updates use `reconfigureItems`, not full reload.
- [ ] **Trust graph — gestures:** Node taps register reliably; pan/scroll doesn't scroll-jack the page. Test: on a physical device with a finger, not the simulator.
- [ ] **Trust graph — variable chain:** Renders correctly with fewer than 5 parties and with a party in `pending`/`revoked`. Test: partial-chain and revoked-party fixtures.
- [ ] **Trust graph — verification state:** Comes only from the server field; missing/unknown fails closed to least-trusted; nothing client-derived. Test: fixture with a missing verification field renders un-trusted, not verified.
- [ ] **Trust graph — iPad native:** Uses a regular-width layout, not a stretched iPhone chain; re-lays-out on Split View resize. Test: iPad full-screen + Split View drag.
- [ ] **Trust graph — accessibility:** VoiceOver traverses all 5 nodes in chain order, announcing role + verification state; labels scale with Dynamic Type. Test: full VoiceOver swipe + largest text size.
- [ ] **Tender/accept/reject — rollback:** Optimistic UI reverts correctly on failure. Test: `409`/`422`/timeout fixtures; verify the load returns to its true state with a specific message.
- [ ] **Tender/accept/reject — idempotency:** Double-tap and retry-after-ambiguous-failure don't double-apply. Test: action endpoints registered with the v1.0 interceptor; control disabled in-flight.
- [ ] **Tender/accept/reject — gating:** Action set is computed from (state, role), no `switch load.status` in any VC/cell. Test: unit test the transition table for all (role, state) pairs.
- [ ] **Mock-to-live readiness:** No hardcoded fixture IDs in product code; strict typed decoding; no `if isMocked` branches in feature code. Test: grep for literal IDs and `isMocked`; attempt decoding a deliberately-varied-but-valid JSON.
- [ ] **PII hygiene:** No raw load/party object logged anywhere; load IDs in deep links are opaque. Test: grep load-domain logging; inspect any deep-link/share payloads.

## Recovery Strategies

When pitfalls occur despite prevention.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Load features over-fitted to fixture shapes; live swap needs a refactor | HIGH | Reconstruct the contract retroactively; introduce pagination + strict decoding as a dedicated remediation phase; the longer this is deferred the worse it gets — catch it at Phase A. |
| Client-side verification-state derivation shipped | HIGH (security) | Treat as a security incident: remove all client trust-derivation, make state render-only; audit every place a badge is shown; the green checkmark vouched for unverified data while it was live. |
| Graph gesture conflicts discovered at demo | MEDIUM | Re-architect the interaction model (fixed graph + page scroll, or own scroll view with explicit `UIGestureRecognizerDelegate` precedence); contained to the graph view if the graph is a discrete component. |
| Optimistic action UI with no rollback path | MEDIUM | Add the failure branch + pre-action snapshot; build the error/latency fixtures that should have existed; re-test every action against them. |
| State machine / gating smeared across VCs and role shells | MEDIUM-HIGH | Extract the transition table to one tested value-type module; replace every `switch load.status` in views with calls to it; risk is missing a copy — grep exhaustively. |
| Diffable data source crash from non-unique identifiers | LOW-MEDIUM | Switch item identifiers to opaque stable load IDs; ensure `Hashable`/`Equatable` are id-based; the crash is loud and early, so usually caught in dev. |
| iPad shipped as a stretched iPhone layout | MEDIUM | Add the regular-width layouts (split view, multi-column, horizontal graph); the deterministic graph layout makes the graph part cheaper if it took size as input. |
| Mock fixtures happy-path-only; empty/error/loading states missing | LOW-MEDIUM | Build the fixture matrix + latency/failure injection; add the missing UI states — cheap if caught before the live swap, a scramble after. |

## Pitfall-to-Phase Mapping

How v1.1 phases should address these pitfalls.

| # | Pitfall | Prevention Phase | Verification |
|---|---------|------------------|--------------|
| 1 | Third-party graph library / SwiftUI for the trust graph | Phase C (decision ratified before code) | No graph dependency in `Package.swift`; no `import SwiftUI` in `Features/Loads`; deterministic layout. |
| 2 | Graph gesture conflicts (tap vs pan vs scroll) | Phase C | Physical-device interaction smoke test: node taps register, no scroll-jacking. |
| 3 | Client shows "verified" it can't attest | Phase A (contract) + Phase C (render-only) | Fixture with missing verification field renders least-trusted; no client trust-derivation code. |
| 4 | Optimistic action UI with no rollback | Phase D (fixtures from Phase A) | Action demoed against `409`/`422`/timeout fixtures; UI reverts to true state. |
| 5 | iPad gets a scaled-up iPhone layout | Phase B (list) + Phase C (graph) | Per-role render check on an iPad size class; graph re-lays-out on Split View resize. |
| 6 | No idempotency / no invalid-transition guard on actions | Phase D | Action endpoints registered with v1.0 idempotency interceptor; control disabled in-flight. |
| 7 | State machine / gating leaks into views | Phase A (tested module) before Phase D | Unit test covers all (role, state) → action-set pairs; zero `switch load.status` in views. |
| 8 | Happy-path-only mock fixtures | Phase A | Fixture matrix exists (empty/large/error/latency); `MockURLProtocol` supports delay + forced failure. |
| 9 | Over-fitting to fixture shapes (mock→live) | Phase A (contract + pagination + strict models) | List paginated against a ≥2-page fixture; no hardcoded IDs; no `isMocked` branches. |
| 10 | Graph inaccessible to VoiceOver / Dynamic Type | Phase C | VoiceOver traverses all nodes in order; labels scale with Dynamic Type. |

## Sources

- Apple Developer — [UICollectionViewDiffableDataSource](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource) — identifier-based snapshots, uniqueness requirement. HIGH.
- [Demystifying the UICollectionView Crash: DUPLICATE_ITEM_IDENTIFIERS_IN_SECTION_SNAPSHOT](https://medium.com/ios-ic-weekly/demystifying-the-uicollectionview-crash-7f327aa8b210) — root cause of the non-unique-identifier crash, Hashable/Equatable correctness. MEDIUM (community, multi-source corroborated).
- [Diffable data source behavior changes and reconfiguring cells in iOS 15 — Jesse Squires](https://www.jessesquires.com/blog/2021/07/08/diffable-data-source-behavior-changes-and-reconfiguring-cells-in-ios-15/) — use identifiers not model objects; `reconfigureItems` vs `reloadItems`; value-type item pitfall. MEDIUM.
- [Cells Reload Improvements in iOS 15 — Swift Senpai](https://swiftsenpai.com/development/cells-reload-improvements-ios-15/) — `reconfigureItems` semantics for content updates without full reload. MEDIUM.
- [Tips and practices for setting up Diffable Data Sources — Filip Němeček](https://nemecek.be/blog/70/tips-and-practices-for-setting-up-diffable-data-sources) — stable identifiers, snapshot apply practices. MEDIUM.
- Apple Developer — UIKit gesture recognizer / `hitTest(_:with:)` / `UIScrollView` pan arbitration documentation — nested scroll/tap conflict handling. HIGH (training-data-consistent with current Apple docs; standard UIKit behavior).
- Apple Human Interface Guidelines — minimum 44×44pt tap targets; trait-collection-driven adaptive layout. HIGH.
- `.planning/research/v1.0/PITFALLS.md` — prior project pitfalls (foundation, not repeated here); the idempotency-key interceptor, PII scrubber, `MockURLProtocol` contract-first pattern, and "no offline chain-of-trust" / "backend is sole authority" rules referenced as v1.1 dependencies. HIGH (project source of record).
- `.planning/PROJECT.md` and `CLAUDE.md` — v1.1 scope, UIKit-for-critical-surfaces constraint, closed dependency shortlist, iPad-native requirement, zero-PII-in-logs constraint. HIGH (project source of record).
- Codebase inspection — `validationLedger/Core/Networking/Mock/` (`MockURLProtocol`, `MockFixture`) confirmed synchronous/instant fixture model; `Features/Loads/` confirmed empty (`.gitkeep`) — v1.1 builds the load domain from scratch. HIGH (direct inspection).

---
*Pitfalls research for: v1.1 "Load Flows" — load list/detail/trust-graph/tender on an existing UIKit/MVVM-C app against MockURLProtocol fixtures*
*Researched: 2026-05-19*
