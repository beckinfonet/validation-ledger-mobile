# Phase 5: KYC Capture & Upload Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-16
**Phase:** 5-kyc-capture-upload-pipeline
**Areas discussed:** Upload timing, Capture interaction, Status surface & rejection, Flow entry point

---

## Upload timing

### Q1 — When does an artifact's upload start, relative to capture?

| Option | Description | Selected |
|--------|-------------|----------|
| Pipelined per-artifact | Each artifact uploads in the background the instant it's captured; most/all acked by Review. Best fit for dock-LTE reality; naturally exercises UPL-02 resume. | ✓ |
| Batch at Submit | All 6 captured + held encrypted on disk, upload kicks off at Submit. Simpler, one progress surface; risks whole-submission loss on a late failure. | |
| Pipelined, but commit at Submit | Chunks upload in the background; final commit deferred to Submit. | |

**User's choice:** Pipelined per-artifact
**Notes:** —

### Q2 — How long should the in-progress KYC session persist, and what clears it?

| Option | Description | Selected |
|--------|-------------|----------|
| Until complete or explicit cancel | Encrypted on-disk session survives cold boots indefinitely; cleared on full submit or explicit discard. Footprint small (committed artifacts deleted immediately). | ✓ |
| Cleared on logout too | Same, but logout also wipes the partial KYC. Tighter; restart-from-zero after logout. | |
| TTL-bounded (24–48h) | Auto-purge after a fixed window. Minimizes lingering images; loses work across a weekend. | |

**User's choice:** Until complete or explicit cancel
**Notes:** Logout does NOT wipe the partial session.

### Q3 — How should the Review screen behave with artifacts in mixed upload states?

| Option | Description | Selected |
|--------|-------------|----------|
| Submit gated on all 6 acked | Per-artifact status shown; Submit disabled until all committed; failed artifacts show inline Retry/Retake. Submit = "all confirmed on backend". | ✓ |
| Submit allowed mid-upload | Submit advances to status screen; uploads finish in background. Faster, but "submitted" no longer guarantees data is up. | |
| Review only after all uploaded | A "finishing upload" wait gate sits before Review. Simplest Review screen; adds a blocking wait on poor coverage. | |

**User's choice:** Submit gated on all 6 acked
**Notes:** —

---

## Capture interaction

### Q1 — How does the face-capture shutter fire?

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-capture on quality pass | Oval guide; fires automatically when Vision detected/centered/in-focus gates hold steady. Lowest friction. | ✓ |
| Manual shutter with readiness cue | Shutter enabled only once gates pass; user controls the moment. | |
| Manual shutter, gates advisory only | Shutter always enabled; gates only hint. Simplest; more low-quality captures. | |

**User's choice:** Auto-capture on quality pass
**Notes:** —

### Q2 — After DataScanner extracts DL-front text, what does the user see?

| Option | Description | Selected |
|--------|-------------|----------|
| Read-only confirm + rescan | Extracted fields shown read-only ("Looks good / Rescan"); no hand-editing. Photo is authoritative; editable fields are a fraud vector. | ✓ |
| Editable confirmation screen | Editable fields to correct OCR. Effectively a "bypass the format gate" affordance. | |
| Silent extraction, photo only | No confirmation screen. Fastest; garbled OCR invisible until rejection. | |

**User's choice:** Read-only confirm + rescan
**Notes:** —

### Q3 — How should the DL-back step work?

| Option | Description | Selected |
|--------|-------------|----------|
| Plain framed photo | No barcode scan; documentary, consistent with vehicle shots. Avoids per-state AAMVA parsing. | ✓ |
| Scan the PDF417 barcode | Decode AAMVA data on the back. Richer data; per-state quirks, low marginal value vs authoritative backend. | |

**User's choice:** Plain framed photo
**Notes:** —

### Q4 — What happens after an artifact is captured, before the next step?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-shot "Use / Retake" preview | Still preview before advancing; catches bad shots in context. | ✓ |
| Auto-advance, retake on Review | Capture immediately advances; retake only on Review screen, out of context. | |

**User's choice:** Per-shot "Use / Retake" preview
**Notes:** —

---

## Status surface & rejection

### Q1 — Where does the KYC status screen live?

| Option | Description | Selected |
|--------|-------------|----------|
| Post-submit screen + role-shell affordance | Status shown after Submit AND reachable later from a role-shell (Profile) affordance. Two entry points, one screen. | ✓ |
| Post-submit screen only | Shown once after Submit; no later in-app path. | |
| Role-shell affordance only | Submit drops straight into the shell; status only via Profile. No immediate post-submit feedback. | |

**User's choice:** Post-submit screen + role-shell affordance
**Notes:** —

### Q2 — How does the status screen refresh?

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch on appear + pull-to-refresh | GET /kyc/status on every appear + manual pull-to-refresh. No timers. M3 push makes it reactive later. | ✓ |
| Active polling while visible | Poll on a ~15–30s interval while foregrounded. Nicer for the just-submitted watcher; needs a timer. | |
| Fetch on appear only | One fetch per appear; no refresh affordance. | |

**User's choice:** Fetch on appear + pull-to-refresh
**Notes:** —

### Q3 — What is the user's recovery path on rejection?

| Option | Description | Selected |
|--------|-------------|----------|
| Re-capture only rejected artifacts | Per-artifact retake (endpoint already returns rejection per-artifact); verified artifacts stay verified. Cuts re-upload abandonment. | ✓ |
| Restart the whole flow | Any rejection re-runs all 6 captures. Simplest state model; high friction. | |

**User's choice:** Re-capture only rejected artifacts
**Notes:** —

### Q4 — Who owns the rejection-reason copy?

| Option | Description | Selected |
|--------|-------------|----------|
| Backend sends a code, iOS owns the copy | Stable reason codes from backend; iOS maps to localizable copy in the string catalog. | ✓ |
| Backend sends display-ready text | rejectionReason rendered verbatim; not localizable from iOS. | |

**User's choice:** Backend sends a code, iOS owns the copy
**Notes:** Planner defines a typed reason-code enum, coordinates the code set with backend, provides an unknown-code fallback.

---

## Flow entry point

### Q1 — Where does the KYC flow sit relative to OTP-verify and the role shell?

| Option | Description | Selected |
|--------|-------------|----------|
| Hard gate before the role shell | KYC blocks the shell until submitted; new AppPhase case. Matches the research OnboardingCoordinator gate + product premise. | ✓ |
| Launched from inside the role shell | Shell usable immediately; KYC started from a prompt. Weaker identity posture. | |
| Gate, with a "do it later" escape | Gate with deferral into a limited shell. Most state to manage; overlaps the Phase 4 limited-trust banner. | |

**User's choice:** Hard gate before the role shell
**Notes:** —

### Q2 — How is KYC state determined at routing points?

| Option | Description | Selected |
|--------|-------------|----------|
| Cache kycStatus in Keychain, refresh via GET /kyc/status | OTP-verify carries kycStatus, cached in Keychain; cold-boot routes off cache (no round-trip, per Phase 3 D-04), then refreshes. | ✓ |
| Always GET /kyc/status before routing | Blocking network call on every cold boot before first paint; breaks the D-04 pattern. | |

**User's choice:** Cache kycStatus in Keychain, refresh via GET /kyc/status
**Notes:** —

### Q3 — Does the user get an escape hatch inside the KYC gate?

| Option | Description | Selected |
|--------|-------------|----------|
| Sign-out affordance in the KYC chrome | Nav chrome carries sign-out → LogoutService.logout(.userInitiated) → phone-entry; partial session persists for resume. | ✓ |
| No escape — KYC mandatory once entered | Only completion or force-quit leaves the gate. "Can't leave this screen" anti-pattern. | |

**User's choice:** Sign-out affordance in the KYC chrome
**Notes:** —

---

## Claude's Discretion

User selected the recommended option for all 14 questions; no "Other" / "you decide" responses. The following were not pinned in discussion and are left to research/planning (see CONTEXT.md `<decisions>` → Claude's Discretion):

- Camera-session (`AVCaptureSession`) lifecycle and preview-layer management.
- The encrypted on-disk store mechanism for the KYC-06 in-progress session + chunk state (`Core/Storage` currently Keychain-only).
- `GeoContext` actor shape for fresh-`CLLocation` caching (Pitfall 6).
- Background-upload wiring — `URLSessionConfiguration.background` + `BGProcessingTaskRequest` reconciliation.
- `AppPhase` enum shape for the KYC gate.
- Camera-permission-denied UX (reuse Phase 3 GEO pattern).
- GPS-staleness / quality-gate failure copy.
- Stable per-chunk idempotency-key strategy for replay dedup.

## Deferred Ideas

- Screenshot / screen-recording block on the DL-capture screen — research D6 flags it M1, but not a tracked KYC requirement. Flag for roadmap backlog, do not silently expand Phase 5.
- MC/DOT entry + live FMCSA lookup (research T21) — SHOULD-level, M1.5/M2.
- Liveness detection — deferred from M1 per PROJECT.md; end-of-M1 decision gate.
- Active polling / push-driven status refresh — M3 (NOTIF-*).
- Tamper-evident device-signed location field (Pitfall 6 step 5) — M1 does EXIF-only per ROADMAP.
