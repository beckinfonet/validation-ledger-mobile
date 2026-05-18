---
status: partial
phase: 05-kyc-capture-upload-pipeline
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md, 05-03-SUMMARY.md, 05-04-SUMMARY.md, 05-05-SUMMARY.md, 05-06-SUMMARY.md, 05-07-SUMMARY.md, 05-08-SUMMARY.md]
started: 2026-05-17T22:28:03Z
updated: 2026-05-18T06:03:47Z
---

## Current Test

[testing paused — 1 item outstanding]

## Tests

### 1. KYC hard gate after OTP (D-12)
expected: After OTP-verifying an account whose KYC is not "verified", the app lands inside the KYC capture flow, not the role tab bar. A non-verified account cannot reach the role shell.
result: pass

### 2. KYC start screen
expected: The KYC flow opens on a "Let's verify your identity" intro / empty-state screen with a "Get started" call-to-action. Tapping it begins the capture sequence.
result: pass

### 3. Face / selfie capture
expected: The face-capture screen shows a live camera preview with an oval face guide. The shutter button enables only when your face is well-positioned (centered, large enough, well-lit) — the Vision face-quality gate. Tapping the shutter captures the selfie.
result: pass

### 4. Use / Retake preview (D-07)
expected: After each capture a still preview appears with "Use" and "Retake". "Retake" returns to the camera; "Use" accepts the shot and advances to the next artifact.
result: pass

### 5. DL front scan + extraction confirm (KYC-03, D-05)
expected: The DL-front step opens a document scanner that reads text off the driver's license. The next screen shows the extracted DL fields (name, DL number, expiry) read-only to confirm; if a field fails format validation you can re-scan.
result: pass

### 6. DL back + vehicle / trailer / plate captures (D-06)
expected: Four plain framed-photo captures complete the 6-artifact set — DL back, then truck, trailer, and plate — each a simple "frame it and shoot" capture with the Use/Retake preview.
result: pass

### 7. Review screen — thumbnail grid + upload status (D-03)
expected: The Review screen shows a 6-cell thumbnail grid, each cell with an upload-status badge (✓ uploaded / ⟳ uploading / ⚠ failed / ⌛ pending). A failed cell offers inline Retry-upload and Retake. "Submit" stays disabled until all 6 artifacts show ✓ uploaded.
result: skipped
reason: "User: only the ✓ uploaded state is observable. The M1 build runs against an always-succeeds mock backend, so the ⟳ uploading / ⚠ failed / ⌛ pending badges and the inline Retry-upload/Retake affordances cannot be exercised without a failure-injecting mock fixture. Confirmed working: the 6-thumbnail grid renders and artifacts reach the ✓ uploaded badge. Failure-state logic is unit-covered by KYCReviewViewModelTests; the live failure-path visual check is deferred."

### 8. Submit → Status transition
expected: Once all 6 artifacts are uploaded, "Submit" enables. Tapping it submits the KYC package once and advances to the KYC status screen.
result: pass

### 9. KYC status screen — states + refresh (D-09, KYC-05)
expected: The status screen renders the verdict — Pending / Under Review / Verified / Rejected. A Rejected state shows plain-language rejection-reason copy (never raw backend codes) and lets you re-capture only the rejected artifacts. Pull-to-refresh re-fetches the latest status.
result: issue
reported: "I see \"Couldn't load status. We couldn't load your verification status. Pull down to try again\" message."
severity: major

### 10. Force-quit resume mid-upload (SC-2)
expected: While a ~6 MB artifact is mid-upload (progress bar partway), force-quit the app and relaunch. The upload resumes from where it left off — the progress bar restores to the prior chunk count, NOT 0% — and the artifact eventually commits.
result: issue
reported: "it survives, but gets stuck at camera open state. Pressing shutter button wont do anything."
severity: blocker

### 11. Background upload completion (SC-4)
expected: With an artifact mid-upload, background the app (Home / swipe up but do NOT kill it). The upload continues in the background and completes — re-opening the app shows the artifact committed (✓).
result: pass

### 12. Profile "Verification status" row (D-08)
expected: For a verified / under-review account in the role shell, opening Profile (the top-bar avatar) shows a "Verification status" row. Tapping it opens the KYC status screen and re-fetches the latest status.
result: blocked
blocked_by: other
reason: "i can't get that far. After kyc doc submission I only see cannot show your status message that I reported earlier. I dont see any profile icon."
note: "Blocked by the Test 9 gap (status screen errors) plus the lack of a path to a verified KYC status — the Profile 'Verification status' row lives in the role shell, reachable only past the D-12 gate (kycStatus == verified). The M1 mock returns under_review, so a verified-status fixture or live backend is needed to exercise this."

### 13. Sign-out from the KYC flow (D-14)
expected: Every KYC capture screen carries a sign-out affordance. Triggering it shows a destructive confirmation; confirming signs out and returns to phone-number entry. The in-progress KYC capture is preserved (resumes on next login); the cached verification status is cleared.
result: pass

## Summary

total: 13
passed: 9
issues: 2
pending: 0
skipped: 1
blocked: 1

## Gaps

- truth: "After submitting KYC, the status screen renders a verdict state (Pending / Under Review / Verified / Rejected) — not an error state"
  status: failed
  reason: "User reported: I see \"Couldn't load status. We couldn't load your verification status. Pull down to try again\" message."
  severity: major
  test: 9
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "After force-quitting mid-upload and relaunching, the KYC flow resumes cleanly — the upload continues from its prior chunk count and the user can keep capturing / advance the flow"
  status: failed
  reason: "User reported: 'it survives, but gets stuck at camera open state. Pressing shutter button wont do anything.' The KYC session persists across the force-quit, but on relaunch the app lands on a camera-open capture screen (vehicle capture VC) that is stuck — the shutter button is unresponsive. Console during the cycle showed FigCaptureSourceRemote err=-17281 (capture source remote connection died); the AVCaptureSession appears not to re-establish a working capture connection after relaunch even though viewDidLayoutSubviews logs report connectionActive=true."
  severity: blocker
  test: 10
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
