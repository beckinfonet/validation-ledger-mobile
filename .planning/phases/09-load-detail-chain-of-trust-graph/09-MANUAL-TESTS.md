# Phase 9 — Manual Device-Test Checklist

> Source: `09-VALIDATION.md § Manual-Only Verifications` (lines 87–99).
> Companion to the Phase 9 automated test corpus — this checklist captures
> the visual / gesture / VoiceOver behaviours that snapshot tests and
> XCUITests cannot fully assert. Run on physical devices before
> `/gsd:verify-work 9` is invoked.

## Run Posture

- **Hardware required:** iPhone 17 (compact-width baseline) AND iPad Air
  (regular-width baseline). Both devices must be on iOS 17.0 minimum (the
  project's deployment target).
- **Build prerequisite:** Phase 9 build (every plan from 09-01 through
  09-10) installed via TestFlight or Xcode device-run.
- **Launch posture:** `-MockOTPRoleForUITest broker` enabled. The broker
  role's fixture roster contains all three fraud archetypes (VL-1009
  double-broker compromised, VL-1010 chameleon-carrier compromised,
  VL-1011 factoring-fraud compromised) plus the caution / clean
  archetypes — so all visual treatments are reachable from one role.
- **Reviewer scope:** each entry is independently verifiable; check the
  device-specific boxes as you go. A FAIL on any entry should be filed
  back into `09-VALIDATION.md` under a new "Gaps" section for
  `/gsd:verify-work` to triage.
- **PII posture (T-09-04):** every fixture referenced uses SYNTHETIC
  party names ("Global Exports Co.", "FreightWise Brokerage", "Keystone
  Freight Group", "Red Rock Carriers", "Overland Dispatch", "BridgeCap
  Capital") and synthetic VL-#### load IDs only. No customer data is
  exercised by this checklist.
- **Repudiation posture (T-09-12):** every entry has explicit
  per-device pass/fail checkboxes; the completed file is the audit
  artefact `/gsd:verify-work` consumes.

---

## 1. Pinch-zoom gesture feel + outer-scroll preservation (TRUST-01 / D-04 / RESEARCH §1)

**Why manual:** Multi-touch + gesture-recognizer interaction quality is
observation-only; snapshot tests can't assert "feel". The automated
XCUITest
(`LoadDetailFlowTests.test_singleFingerScroll_propagatesPastGraph_toBodyScrollView`)
proves the gesture wiring is correct; this entry validates that the
end-user experience matches.

**Prerequisites:** iPhone 17 + iPad Air, physical devices.

**Steps:**

1. Launch the app; complete OTP as broker (mock OTP `123456`).
2. Tap any load in the list (suggest VL-1001 — the clean archetype, no
   banner / dim-others to obscure baseline behaviour).
3. The detail screen renders with the trust graph dominating the upper
   ~62% of the screen on iPhone, or the left 60% of the split on iPad.
4. **Single-finger drag UP starting inside the graph region.**
   - **Expected:** the outer page body scrolls UP (revealing the
     status-timeline → freight rows → parties section → verdict block
     stacked below the graph). The graph itself does NOT pan.
5. **Two-finger PINCH inside the graph region** (spread fingers apart to
   zoom in; pinch them together to zoom out).
   - **Expected:** the graph zooms smoothly between
     `minimumZoomScale=1.0` and `maximumZoomScale=3.0` (the locked
     UI-SPEC range). Edge stroke widths do NOT visually thicken with
     zoom (inverse-scale compensation per UI-SPEC).
6. **Two-finger DRAG inside the graph (while zoomed > 1.0).**
   - **Expected:** the graph pans inside its bounds; the outer page
     does NOT scroll.
7. **DOUBLE-TAP on the broker node (FreightWise Brokerage on VL-1001).**
   - **Expected:** the graph animates to recenter and zoom (~250ms
     ease-in-out) at ~1.8x scale on that node. The verification-basis
     sheet does NOT appear (single-tap is wired to
     `.require(toFail: doubleTap)`).
8. **DOUBLE-TAP on empty canvas inside the graph (away from any node).**
   - **Expected:** the graph resets to fit-all-nodes-tight zoom +
     centre (`zoomScale` returns to 1.0).
9. **SINGLE-TAP on the broker node.**
   - **Expected:** after the double-tap-fail window (~250ms), the
     verification-basis sheet presents at `.medium` detent over the
     graph. The graph remains interactive + undimmed behind the sheet
     (D-08 `largestUndimmedDetentIdentifier = .medium` lock).

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## 2. Halo pulse animation on compromised node (TRUST-05 / D-15)

**Why manual:** `CABasicAnimation` continuity across `layoutSubviews()`
and trait changes is the same lifecycle hazard the Phase 8
`SkeletonLoadRowCell` documented (Pitfall 1 / RESEARCH §2 line 967).
Automated snapshot tests capture a single frame; the pulse continuity
across rotation + lock-screen-resume needs eyes on it.

**Prerequisites:** iPad Air (the device with the natural rotation
boundary). iPhone 17 also valid for the static pulse + lock-screen
behaviours.

**Steps:**

1. Launch as broker. Open VL-1009 (the double-broker compromised
   archetype) — the Keystone Freight Group node is the implicated
   broker.
2. **Static pulse:** observe the Keystone node — the red halo should
   pulse at the locked cadence (opacity oscillates ~0.4 ↔ 1.0 every
   ~1.4s). The pulse should be continuous; no stutter, no restart.
3. **Rotation continuity (iPad only):** while the pulse is running,
   rotate the iPad portrait→landscape. The composition flips from
   single-column to side-by-side split (D-03). The pulse should
   **continue without restart artefact** — no momentary opacity
   reset to 1.0 and no visible stutter at the trait flip.
4. **Lock-screen resume:** lock the device (power button); wait 3
   seconds; unlock. The pulse should be running at the same cadence
   when the screen comes back. (Implementation: `CABasicAnimation` is
   suspended by the system on lock and resumed automatically.)
5. **Backgrounding:** background the app (swipe-up to home); wait 3
   seconds; foreground via app switcher. Pulse should be running at
   the same cadence on return.

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## 3. VoiceOver traversal order on flagged archetype (TRUST-01 / D-21 / D-22)

**Why manual:** Apple's VoiceOver runtime is not fully scriptable from
XCUITest. The accessibility-tests in the Phase 9 corpus
(`TrustGraphViewAccessibilityTests`) lock the `accessibilityElements`
ordering at the API level, but the actual VoiceOver swipe-walk +
double-tap-to-activate behaviour needs a human listener.

**Prerequisites:** iPhone 17 + iPad Air. Enable VoiceOver before
launching the app (Settings → Accessibility → VoiceOver, or
triple-click side button if the shortcut is configured).

**Steps:**

1. With VoiceOver ON, launch the app; complete OTP as broker.
2. Open VL-1009 (compromised double-broker archetype — a flagged chain
   exercises the full traversal).
3. **iPhone traversal:** swipe RIGHT repeatedly from the top of the
   screen. Confirm the order:
   - Pinned header (reference number → origin→dest → status badge,
     read as a combined element)
   - Chain-integrity banner (locked label: `"Chain integrity:
     Compromised. {reason}"`)
   - Trust graph region (announced as a container) — inside the
     container, swipe RIGHT to walk node-shipper → node-broker →
     node-carrier → node-dispatch → node-factoring, then the edges in
     `fromID/toID` order
   - Status timeline (announced as a single combined element)
   - Freight detail rows
   - Parties section
   - Chain-integrity verdict block (D-02)
4. **iPad traversal (rotate to landscape for the split):** swipe
   RIGHT from the top:
   - Chain-integrity banner (full-width, above the split)
   - Right pane: pinned header → status timeline → freight rows →
     parties → verdict block (freight metadata FIRST per D-21)
   - Left pane: trust graph region (traversed AFTER the right pane on
     iPad)
5. **Activate via VoiceOver:** with the implicated Keystone node
   focused, double-tap. Confirm the verification-basis sheet
   presents. The graph remains visible behind the sheet (D-08).
6. **VoiceOver suspends pinch-zoom:** while VoiceOver is on, attempt a
   two-finger pinch inside the graph region. Confirm the graph does
   NOT zoom (per D-22 the `minimumZoomScale == maximumZoomScale ==
   1.0` while `UIAccessibility.isVoiceOverRunning`).

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## 4. iPad split layout — split percentage + rotation behaviour (D-03)

**Why manual:** Layout aesthetic ("does it look right") is
observational. The 60/40 ratio is locked numerically in
`LoadDetailViewController.buildIPadSplitLayout()`, but how the
rotation animation reads to the user — does the split feel jarring,
or natural? — needs eyes on it.

**Prerequisites:** iPad Air physical device. (PROJECT.md constraint:
"iPad must render natively, not just scale.")

**Steps:**

1. Launch as broker on iPad. Open VL-1005 (caution archetype — has
   both a banner AND a non-trivial chain, exercising the full split
   geometry).
2. **Portrait posture:** confirm single-column compact composition —
   pinned header at top → chain-integrity banner → trust graph
   (occupying ~62% of vertical space) → body (timeline / freight /
   parties / verdict block) scrolling below.
3. **Rotate to landscape:** confirm the side-by-side ~60/40 split
   animates IN — the trust graph occupies the LEFT 60% of the
   horizontal width; the right 40% pane stacks pinned header →
   timeline → freight → parties → verdict block in a scrollable
   column. The chain-integrity banner sits full-width ABOVE the
   split.
4. **Tap a node in the iPad split layout:** confirm the sheet renders
   as a **floating card** (iOS 17 `UISheetPresentationController`'s
   `widthFollowsPreferredContentSizeWhenEdgeAttached = true` posture
   on regular-width) — NOT a full-height bottom sheet.
5. **Rotate back to portrait:** the split collapses back to
   single-column; the graph's zoom + pan state is preserved across
   the rotation (UI-SPEC line 813 `savedZoom + savedOffset` capture).
6. **iPad-only verdict:** during rotation, the chain-integrity banner
   remains visible at all times (it does not flicker out during the
   composition rebuild).

**Pass:** [ ] iPad Air

---

## 5. Skeleton-with-shimmer continuity (D-19)

**Why manual:** Shimmer must visually match Phase 8's
`SkeletonLoadRowCell` cadence (D-10 horizontal sweep). The cadence is
locked in code, but matching it across two different rendering
contexts (the row cell vs the full-screen detail silhouette) needs a
side-by-side eye check.

**Prerequisites:** iPhone 17 + iPad Air. Requires the artificial
2-second fetch delay — toggle via the test-stub mock URL protocol or
slow down the network in Settings → Developer → Network Link
Conditioner (Edge profile is sufficient).

**Steps:**

1. Launch as broker; force the artificial 2s delay.
2. Tap a load row.
3. **Loading silhouette appears:** confirm the skeleton renders
   - Pinned-header rectangle (top)
   - Placeholder graph region: 5 grey circles in the role slots
     (shipper / broker / carrier / dispatch / factoring), connected
     by grey edge stubs
   - 3–4 grey placeholder body rows below
4. **Horizontal shimmer:** a left→right `CAGradientLayer` sweep moves
   across the skeleton at the same cadence as the load-list shimmer
   from Phase 8. Side-by-side compare: open the loads list (which
   shows row-cell shimmer if the list is also delayed) and the
   skeleton — the sweep speed should match.
5. **iPad skeleton split:** on iPad in landscape, the skeleton mirrors
   the split layout — graph silhouette on the LEFT 60%, placeholder
   body rows on the RIGHT 40%.
6. **Transition to `.loaded`:** when the fetch completes, the skeleton
   swaps to the real layout — the swap should feel instant (no
   crossfade / no double-paint).

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## 6. Dim-others treatment on compromised verdict (TRUST-05 / D-15)

**Why manual:** The `0.6 → 1.0` non-implicated-node opacity ratio is
an aesthetic decision visible only with eyes on it; an automated
snapshot test asserts the opacity values are set, but whether the
result reads as "the flagged node is the focus" — and not "the chart
looks broken" — is subjective.

**Prerequisites:** iPhone 17 + iPad Air.

**Steps:**

1. Launch as broker. Open VL-1009 (compromised double-broker
   archetype). VL-1009 implicates the Keystone Freight Group node.
2. **Focus check:** the Keystone node renders at full opacity (1.0)
   with the red pulsing halo (per entry 2).
3. **Dim-others check:** the other 5 chain nodes (Global Exports,
   FreightWise Brokerage, Red Rock Carriers, Overland Dispatch,
   BridgeCap Capital) render at ~0.6 opacity — visibly dimmer than
   the implicated node, but still readable.
4. **Edge dim-others (D-15):** the two implicated edges
   (`edge-VL-1009-broker-broker` and `edge-VL-1009-broker-carrier`)
   render at full opacity with the flagged-stroke treatment (red
   dashed); the other three edges render at ~0.6 opacity with the
   normal solid grey stroke.
5. **Read test:** at a glance (under 2 seconds of screen time), the
   user's eye should land on the Keystone node + its two implicated
   edges — the visual emphasis should TELL the story without reading
   any copy.
6. **Caution-tier comparison:** open VL-1005 (caution archetype). The
   dim-others treatment should ALSO apply (a caution chain has
   implicated party/edge sets per D-15) but at the yellow / caution
   colour tier instead of red / compromised.
7. **Clean-tier baseline:** open VL-1001 (clean archetype). NO
   dim-others — all 5 nodes render at full opacity. This is the
   baseline that proves the dim-others treatment is verdict-driven,
   not always-on.

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## Reviewer Sign-Off

Reviewer name: ___________________________

Date: ___________________________

Device build: ___________________________ (commit SHA from
`validationLedger`'s `Settings → About` screen, when available; or
the TestFlight build number).

iPhone 17 result: [ ] PASS — all 6 entries  [ ] FAIL — list entry
numbers below.

iPad Air result: [ ] PASS — all 6 entries  [ ] FAIL — list entry
numbers below.

**Failures (file into `09-VALIDATION.md` § Gaps for
`/gsd:verify-work` triage):**

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________
