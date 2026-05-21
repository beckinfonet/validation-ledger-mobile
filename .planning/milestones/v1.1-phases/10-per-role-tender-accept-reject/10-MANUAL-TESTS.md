# Phase 10 — Manual Test Checklist

> Source: `10-VALIDATION.md § Manual-Only Verifications` (lines 105–113)
> plus an end-to-end happy-path device flow that complements the
> XCUITest corpus (`LoadActionFlowsTests`). Run on physical devices
> before `/gsd:verify-work 10` is invoked.

## Run Posture

- **Hardware:** iPhone 17 (compact baseline) AND iPad Air (regular
  baseline). iPhone SE-class device recommended for the tender-sheet
  ergonomics check.
- **Build:** Phase 10 build (plans 10-01 through 10-10) installed via
  TestFlight or Xcode device-run.
- **Default launch args:** `-MockOTPRoleForUITest <role>
  -MockKYCStatusVerified` (bypasses OTP + the D-12 KYC gate; project
  memory `mock-kyc-status-verified-toggle`). Toggle the role per the
  entry.
- **Failure-injection launch args (Phase 10 D-19, DEBUG-only):**
  - `-MockActionServerError500` — every action POST returns 500
    (drives the rollback path).
  - `-MockActionLatencySlow` — inserts ~1.5s delay before the response
    (makes the optimistic spinner + chain overlay visible).
- **Reviewer scope:** each entry is independently verifiable. FAILs
  file into `10-VALIDATION.md § Gaps` for `/gsd:verify-work` triage.
- **PII posture (T-09-04 / T-10-PR-01):** every fixture uses SYNTHETIC
  party names + synthetic VL-#### load IDs. No customer data.

---

## 1. Toast banner animation feel (ACTION-05 / D-15 / UI-SPEC line 458-475)

**Why manual:** Animation timing is a feel call. XCUITest's
`LoadActionFlowsTests.test_rollbackOnServerError500` proves the
rollback wiring is correct end-to-end; this entry validates the user
experience matches the spec.

**Launch args:** `-MockOTPRoleForUITest carrier -MockKYCStatusVerified
-MockActionServerError500 -MockActionLatencySlow`.

**Steps:**

1. Launch; carrier loads tab renders. Open VL-1004 (the `.tendered`
   carrier load). Scroll to the action region.
2. **Tap Accept.** During the ~1.5s latency: Accept button spinner
   appears alongside title; chain overlay fades in (0.2s, alpha
   0 → 1 — UI-SPEC line 487); both buttons disabled.
3. **After the 500 fires:** chain overlay fades out (0.25s); badge
   SNAPS to **TENDERED** (no animation); toast SLIDES DOWN from
   top safe-area (0.28s `.curveEaseOut`); medium-impact haptic
   fires at slide-in start. Toast copy:
   "Couldn't accept this tender. Try again." (resolved from
   `loads.actions.error.accept_failed`); red destructive ground
   alpha 0.92 + white text + white exclamation icon.
4. **Dwell:** banner sits 3.5s, then auto-dismisses (0.22s
   `.curveEaseIn` slide-out).
5. **Manual dismiss tests:** trigger another failure → TAP toast →
   slides out immediately. Trigger a third → SWIPE UP (translation.y
   < -12pt) → also dismisses. Swiping DOWN does NOT dismiss
   (UI-SPEC lock).
6. **Light + dark mode:** toggle Settings → Display & Brightness
   mid-dwell. Both render with adequate contrast.
7. **VoiceOver (optional):** with VoiceOver ON, repeat steps 2-3.
   Toast copy is announced via `.announcement` after slide-in.

**Pass criteria:** slide-in is smooth (no stutter, no late haptic);
dwell "long enough to read, not annoying"; tap + swipe-up dismissals
work; both modes contrasted; haptic intensity is "medium" —
noticeable but not jarring.

**Pass:** [ ] iPhone 17  [ ] iPad Air

---

## 2. Tender sheet `.medium` detent ergonomics (ACTION-04 / D-06 / UI-SPEC line 446)

**Why manual:** Sheet-detent ergonomics are subjective. The
`UISheetPresentationController` is locked to `.medium` with
`largestUndimmedDetentIdentifier = .medium`,
`prefersGrabberVisible = true`. Whether the Send button is reachable
with the thumb on iPhone SE class needs eyes on it.

**Launch args:** `-MockOTPRoleForUITest broker -MockKYCStatusVerified`.

**Steps:**

1. Launch as broker. Open VL-1003 (`.posted`, `can_tender=true`).
   Scroll to the action region. Tap **Tender**. Sheet presents at
   `.medium` detent.
2. **Posture (iPhone 17):** sheet top edge at ~50% of screen height;
   grabber visible; page below does NOT dim
   (`largestUndimmedDetentIdentifier` lock — load detail's pinned
   header + trust graph remain visible above the sheet). First
   verified carrier row visible without sheet-scroll; deadline
   chips (1h/4h/24h/48h/Custom) below the picker; Send button at
   bottom.
3. **One-handed thumb-reach (iPhone SE class):** hold device in ONE
   hand. With thumb alone reach: first verified carrier row → 24h
   chip → Send. Send MUST be reachable without re-gripping (re-grip
   is a FAIL).
4. **Detent expansion:** drag grabber UP → sheet expands to
   `.large` (full-screen above safe-area top); page dims. Drag DOWN
   → collapses back.
5. **Cancel via grabber drag:** at `.medium`, drag grabber DOWN past
   screen bottom. Sheet dismisses (onSend NOT fired).
6. **iPad Air (landscape):** repeat steps 1-2. Sheet renders as a
   **floating card** centered horizontally, occupying ~40% of the
   screen (iOS 17
   `widthFollowsPreferredContentSizeWhenEdgeAttached = true` on
   regular-width) — NOT a full-width bottom sheet.

**Pass criteria:** sheet in lower 50% on iPhone; all elements
reachable by thumb on iPhone SE without re-gripping; detent
expansion + drag-to-dismiss work; iPad renders as a floating card.

**Pass:** [ ] iPhone SE-class  [ ] iPhone 17  [ ] iPad Air

---

## 3. 65-cell snapshot matrix legibility at Default + Large Dynamic Type (ACTION-01 / UI-SPEC line 537)

**Why manual:** The Plan 09 snapshot matrix records 65 baseline PNGs
(5 roles × 13 LoadStatus); the bytes match the running build, but
whether each cell READS cleanly at Default vs. Large is a visual
judgment the snapshot bytes cannot make.

**Prerequisites:** Plan 09 baselines committed; snapshot suite green
(per `10-VALIDATION.md § 65-cell snapshot matrix § Verify command`).

**Steps:**

1. **Baseline spot-check (macOS Preview):** open
   `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/`
   and inspect 5 PNGs — one per role: `broker-posted.png`,
   `shipper-tendered.png`, `carrier-tendered.png`,
   `dispatch-accepted.png`, `factoring-invoiced.png`. For each:
   button titles do NOT truncate; empty-state caption (where
   applicable) reads cleanly; disabled-reason inline label (where
   applicable) reads cleanly; destructive actions (`Cancel load`,
   `Reject`) render with `DS.Colors.destructive` tint, visibly
   distinct from primary.
2. **Dynamic Type lift (iPhone 17 device):** Settings →
   Accessibility → Display & Text Size → Larger Text → slide to
   **Large** (first step above Default; NOT yet an
   accessibility-large category). Re-launch.
3. Open VL-1003 (broker × .posted), VL-1004 (carrier × .tendered),
   VL-1010 (carrier × .accepted, 1-button case). In each: button
   row stays HORIZONTAL (axis-flip only triggers at
   accessibility-large+ per `LoadActionsView.applyDynamicTypeAxis`
   line 257); titles do NOT truncate; the inline "Respond by
   HH:mm" label on VL-1004 reads cleanly.
4. **Optional — Accessibility Medium:** lift to "Accessibility
   Medium" (second panel under the slider). Re-open VL-1003 +
   VL-1004; the row flips to vertical with no overlap or clipping.

**Pass criteria:** all 5 baselines read cleanly at Default; at
Large, no truncation; Respond-by + disabled-reason inline labels
readable; destructive tinting distinguishable; (optional)
Accessibility Medium+ vertical-flip is clean.

**Pass:** [ ] iPhone 17 (Default)  [ ] iPhone 17 (Large)
  [ ] iPhone 17 (Accessibility Medium — optional)

---

## 4. End-to-end happy-path device flow (ACTION-01..09)

**Why manual:** The 6 XCUITest flows cover the per-action contracts
in isolation. This entry stitches them into a **broker → carrier
hand-off** that a human reviewer walks start-to-end, validating that
the per-screen transitions FEEL right.

**Prerequisites:** iPhone 17 physical device.
- Broker phase: `-MockOTPRoleForUITest broker -MockKYCStatusVerified`.
- Carrier phase: stop, restart with `-MockOTPRoleForUITest carrier
  -MockKYCStatusVerified`.
- Mock fixture note: the action-success payload (Phase 7) always
  returns VL-1004/.accepted (single canonical body for ALL actions);
  POSTs surface that state regardless of starting fixture (Threat
  T-07-31 accept disposition; documented limitation for v1.1).

**Steps — Broker phase:**

1. Launch as broker. Open VL-1003. Scroll to action region. Tap
   **Tender**.
2. Tender sheet presents. Pick first verified carrier (Acme Trucking
   Inc.). Tap **1h** chip. Tap **Send**.
3. Sheet dismisses on 200. Badge advances to **ACCEPTED** (canonical
   success payload returns VL-1004/.accepted; displayed load swaps
   from VL-1003 to VL-1004).
4. Pop back via nav-bar back. Loads list re-renders via
   `viewWillAppear → fetchLoads()` (ACTION-09 / D-18). Note: static
   mock list fixture does NOT mutate on POST — VL-1003's row text is
   unchanged. Mock limitation, not a bug.
5. Stop the app.

**Steps — Carrier phase:**

6. Restart with carrier launch args. VL-1004 still shows `.tendered`
   (un-mutated baseline; broker-phase POSTs don't modify this
   fixture's source).
7. Open VL-1004. Scroll to action region. Tap **Accept**. Badge
   advances to **ACCEPTED**. Action region re-renders against
   `.accepted` — new set is `[.advanceStatus]`; row shows single
   **Dispatch** button.
8. Tap **Dispatch** → **DISPATCHED** + **Mark in transit** button.
9. Tap **Mark in transit** → **IN TRANSIT** + **Mark delivered**.
10. Tap **Mark delivered** → **DELIVERED**. Action region renders
    terminal-state empty caption:
    **"This load is delivered. No actions available."** — CRITICAL:
    reads "delivered" (lowercase, no underscore), NOT "DELIVERED"
    or "in_transit" (Pitfall 5 lock; UI-SPEC line 304).
11. Pop back. Row treatment matches terminal-state design.

**Pass criteria:** every tap drives the predicted state forward
without user-visible stutter; pinned-header badge updates correctly
at each step; terminal-state caption reads "This load is delivered";
end-to-end completes under 60 seconds (broker ≤ 20s, carrier ≤ 40s).

**Pass:** [ ] iPhone 17

---

## Reviewer Sign-Off

Reviewer name: ___________________________

Date: ___________________________

Device build: ___________________________ (commit SHA from
`validationLedger`'s `Settings → About`, when available; or the
TestFlight build number).

| Entry | iPhone 17 | iPad Air | iPhone SE-class |
| ----- | --------- | -------- | --------------- |
| §1 Toast banner animation feel | [ ] PASS [ ] FAIL | [ ] PASS [ ] FAIL | n/a |
| §2 Tender sheet `.medium` detent | [ ] PASS [ ] FAIL | [ ] PASS [ ] FAIL | [ ] PASS [ ] FAIL |
| §3 65-cell matrix legibility (Default + Large) | [ ] PASS [ ] FAIL | n/a | n/a |
| §4 End-to-end happy-path flow | [ ] PASS [ ] FAIL | n/a | n/a |

**Failures** (file into `10-VALIDATION.md § Gaps` for
`/gsd:verify-work` triage):

____________________________________________________________

____________________________________________________________

After completing this checklist, mark the phase as `human_verified`
in STATE.md and proceed to `/gsd:close-phase`.
