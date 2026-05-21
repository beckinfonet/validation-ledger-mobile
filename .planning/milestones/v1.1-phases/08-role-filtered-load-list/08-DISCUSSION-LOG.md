# Phase 8: Role-Filtered Load List - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `08-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 8-role-filtered-load-list
**Areas discussed:** Row Counterparty Contract, Pagination Posture, List Sort/Grouping Order, Loading-State Visual

---

## Area 1 — Row Counterparty Contract

**Question 1:** How should the list-row counterparty + verification badge data reach iOS?

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Server projects a TrustNode | Server returns a pre-selected `displayedCounterparty: TrustNode?` per row — already role-resolved. iOS reads `node.displayName + node.verificationState`; never picks. Preserves D-18. UI-SPEC's preferred direction. | ✓ |
| (b) Flat scalar pair on the row | Two flat fields: `counterparty_name: String?`, `counterparty_verification_state: VerificationState?` — minimum bytes. Lightest payload; loses structural alignment with `TrustNode`. | |
| (c) Abbreviated ChainOfTrust on each row | List response carries an abbreviated `chain_of_trust` per row; iOS picks the counterparty via a `RoleLoadPolicy`-like helper. Violates D-18. | |

**User's choice:** (a) Server projects a TrustNode.

---

**Question 2:** Where does the server-projected `displayedCounterparty: TrustNode?` attach in the Swift model?

| Option | Description | Selected |
|--------|-------------|----------|
| On Load itself, optional | Add `public let displayedCounterparty: TrustNode?` to `Load`. Smallest blast radius; field is meaningful on a list row, vestigial on a detail row. | |
| New LoadListItem envelope | `struct LoadListItem { let load: Load; let displayedCounterparty: TrustNode? }`. Changes `Response.loads` from `[Load]` to `[LoadListItem]`. Keeps Load pure; meaning of every field unambiguous; aligns with v1.0 pattern. | ✓ |
| Sibling array on Response | Parallel `counterparties: [TrustNode?]` indexed by row position. Parallel-array data modeling is fragile (index drift). | |

**User's choice:** New `LoadListItem` envelope.

---

**Question 3:** When `LoadListItem.displayedCounterparty` is `nil` on the wire, what should the row render?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail-closed: render UNVERIFIED | `nil` → neutral-grey UNVERIFIED badge with name suppressed (or `—`). Matches D-09 fail-closed posture. | ✓ |
| Hide the badge entirely | `nil` → no verification badge at all. Less visual noise but creates ambiguity. | |
| Make it non-optional, decode-required | Treat absence as a hard decode error. Forces every fixture row to carry a counterparty (even drafts) — fixture-authoring pain. | |

**User's choice:** Fail-closed — render the UNVERIFIED badge.

---

**Question 4:** The 6 list-fixture JSONs currently have no party data — every row needs a `displayedCounterparty` added. What's the scope?

| Option | Description | Selected |
|--------|-------------|----------|
| In Phase 8 — update all fixtures + add a degraded edge fixture | Phase 8 owns the contract extension + fixture-data authoring + a new `loads-list-degraded-counterparty.json` exercising the fail-closed path. Keeps everything Phase 8 needs inside Phase 8. | ✓ |
| Phase 8 contract change + a Phase 7 follow-up plan for fixtures | Cleaner phase boundary but creates cross-phase dependency. | |
| Use a side-channel during Phase 8 only | `MockLoadFixtureRegistry` injects synthetic counterparty post-decode. Creates known fakeness; debt for M3 swap. | |

**User's choice:** In Phase 8 — update all fixtures + add a degraded edge fixture.

---

## Area 2 — Pagination Posture

**Question 1:** What's Phase 8's posture toward the `LoadListEndpoint.Response.nextCursor` field?

The user initially asked for simpler terms; clarification provided in plain language explaining the trade-offs between decode-only, infinite-scroll, and a "Load more" button. The clarification framed the choice around demo volume (named-load library ≈ 12 loads) and the fact that adding the consumer later is strictly additive.

| Option | Description | Selected |
|--------|-------------|----------|
| Decode-only — ignore nextCursor in v1.1 | VM decodes `nextCursor` but never reads it. No infinite-scroll, no button, no second-page fixture. Future consumer additive. | ✓ |
| Wire infinite-scroll now | Auto-fetch-on-scroll loop. Needs multi-page fixture + stale-cursor failure case. Bigger Phase 8. | |
| Ship a 'Load more' button | Button row at list end when `nextCursor != nil`. Less code than infinite-scroll, but adds chrome the UI-SPEC didn't anticipate. | |

**User's choice:** Decode-only — ignore `nextCursor` in v1.1.

---

## Area 3 — List Sort and Grouping

**Question 1:** How are rows ordered inside the role's Loads tab?

| Option | Description | Selected |
|--------|-------------|----------|
| Server-supplied order — iOS renders as-is | iOS renders `Response.loads` in the exact array order returned. Server decides the meaningful sort. Matches D-18. | ✓ |
| Client-side sort by pickupAt ascending | iOS sorts every list by `pickupAt` ascending. Predictable, debuggable; overrides server-side sort logic. | |
| Client-side sort by status priority + pickupAt | Two-key sort: status bucket-rank, then `pickupAt`. Bakes product taxonomy into binary. | |

**User's choice:** Server-supplied order — iOS renders as-is.

---

**Question 2:** And the grouping/section structure inside the list?

The user asked for plain-language clarification of the trade-offs. The follow-up explanation framed flat list vs server-driven sections vs client-side sections in terms of Mail/Files UX precedents, contract complexity, and future-cost of each. The user then asked specifically about future-cost ("what would be the complexity to come back to it?") — answered with: client-side sections/filters land additively in ~half a day if Phase 8 ships with (1) an enum-typed datasource section and (2) `UICollectionViewCompositionalLayout(.list)`. Only server-driven sections later are expensive (~1-2 days + contract churn).

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — flat list now + enum section type + .list layout | Single flat section. Datasource typed against `enum LoadListSection { case main }`; layout `.list`. Future sections/filters land additively in ~half a day. | ✓ |
| Flat list, but skip the enum-section forward-looking choice | Datasource typed against `Int`. Slightly less code now; ~30 extra minutes of refactor if sections added later. | |

**User's choice:** Flat list + enum section type + `.list` layout — preserve additive future paths.

---

## Area 4 — Loading-State Visual

**Question 1:** Which loading-state visual does Phase 8 ship?

The user asked for plain-language explanation. The follow-up framed centered spinner (a circle in the middle of a blank screen — matches the v1.0 KYC status precedent) vs skeleton-with-shimmer (grey ghost of the real list with a subtle animated sweep — like Mail / LinkedIn). Trade-off table: code amount, precedent fit, "feels faster?", future pattern implication.

| Option | Description | Selected |
|--------|-------------|----------|
| Centered spinner — matches v1.0 | Animated `UIActivityIndicatorView` centered on blank screen. ~30 LOC. Matches KYC status screen. No new app-wide pattern. | |
| Skeleton with shimmer | Grey placeholder rows + animated sweep. ~120 LOC + snapshot test. More polished. Establishes a 'skeleton everywhere' pattern. | ✓ |

**User's choice:** Skeleton with shimmer — willing to take on the more polished pattern and establish it as the app-wide loading-state convention.

---

## Claude's Discretion

The planner / researcher may finalize without re-asking:

- Exact skeleton row count (6–8) and shimmer animation timing (~1.0–1.5 s, infinite repeat).
- Tab-wiring strategy (factory-via-AppContainer mirroring `kycStatusScreenFactory` is the obvious choice).
- VM error classification — collapse decode / HTTP 4xx / network to `.error(message:)`; whether `message` is raw description, fixed copy, or a discriminated enum is implementation detail.
- Service-layer abstraction: direct `APIClient` consumption vs typed `LoadListProviding` facade.
- Skeleton block widths/heights — must visually approximate the real cell's three-tier hierarchy.
- Granularity of the Phase 7 fixture diff (one plan vs split).
- MockURLProtocol fixture-swap mechanism for the degraded edge fixture.

---

## Deferred Ideas

- Client-side filter chips / segmented status filter — additive client-side filter; ~half-day. Defer until real list volumes justify it.
- Client-side sections grouped by status bucket — `enum LoadListSection` extension + classifier function. ~half-day. D-08 already makes this additive.
- Infinite-scroll consumer for `nextCursor` — additive VM upgrade when a real backend or multi-page fixture appears.
- Tap-to-reveal verification basis on the list-row badge — UI-SPEC locked the badge as non-interactive on the list; could be added later without contract change.
- Back-port skeleton-with-shimmer to v1.0 surfaces (KYC status screen) — not in Phase 8; possible later cleanup phase.

---

## Reviewed-but-not-folded Todos

- **`device-ci-biometric-infra.md`** — v1.0 physical-device CI infrastructure todo (Face ID prompt hangs the device-CI lane). Matched on generic keywords (`status`, `pending`, `phase`); unrelated to a UI list feature. Not folded — remains a carried v1.0 infrastructure item.
