---
status: resolved
trigger: "User stuck on KYC \"Under review\" status screen during device UAT (2026-05-20). Only Back and Sign-out are tappable; pull-to-refresh and Submit re-fire both bounce back here. Two stacked root causes identified upfront."
created: 2026-05-20T00:00:00Z
updated: 2026-05-20T00:00:00Z
---

## Current Focus

hypothesis: TWO ROOT CAUSES CONFIRMED — (A) KYCStatusViewController is missing `navigationItem.hidesBackButton = true` so the system nav-bar back leaks through on a terminal screen that the D-14 design explicitly marks "never trapped" via Sign-out only; (B) MockDefaultFixtures.kycStatusResponseJSON() is pinned to `"overall_status":"under_review"` for GET /kyc/status, so a device-UAT build cannot progress past the under_review verdict to reach the role shell — by design per 05-UAT.md:69, but blocks Phase 6+ device UAT.
test: Code-paths traced for both causes (KYCStatusViewController.swift no hidesBackButton vs NotAvailableInRegionViewController.swift:23 sets it on the only other terminal screen; MockDefaultFixtures.swift:177-186 literal-string pin; KYCStatusViewModel.mapState clearSession ONLY on .verified so back→Review is non-destructive but unproductive).
expecting: Both confirmed by direct file reads — no further investigation needed.
next_action: COMPLETE — both fixes shipped + tested. Awaiting device-UAT confirmation by the user with the new `-MockKYCStatusVerified` launch arg set.

## Symptoms

expected: After KYC submission the status screen renders the verdict — Pending / Under Review / Verified / Rejected. On a terminal "Under review" verdict, the only escape is the D-14 Sign-out affordance (preserves partial KYC session on disk per D-02). On a device UAT build the tester needs a path to reach the role shell to exercise Phase 6+ surfaces.
actual: On the physical iPhone (DEBUG build, networkConfig == .mock), after submitting KYC the user lands on the Under-Review status screen with TWO tappable affordances: a system nav-bar Back (unintended — the screen is terminal by design) and the D-14 Sign-out. Back pops to KYCReviewViewController which re-reads the persisted KYCSession (all 6 photos still committed) and lets the user re-tap Submit, which re-fires POST /kyc/submit and re-pushes the same Under Review status — a bounce loop. Pull-to-refresh re-fires GET /kyc/status which always returns under_review. No path forward to the role shell.
errors: None — both behaviors are working as written. The Back button is a leaking affordance against design intent (no nav-item override); the mock's pin to under_review is a documented M1 limitation (05-UAT.md:69).
reproduction: On the DEBUG iOS build with the mock networkConfig — start KYC, capture the 6 artifacts, tap Submit on the Review screen, arrive at the Under Review status screen.
started: Discovered during device UAT of Phase 9 work (2026-05-20) — see [[phase-9-execution-closeout]] in user memory; Phase 9 has 6 device-UAT items pending.

## Eliminated

- hypothesis: "Going Back wipes the persisted KYCSession and forces re-capture of all 6 photos."
  reason: "KYCStatusViewModel.mapState calls store.clearSession() ONLY on the .verified path (KYCStatusViewModel.swift:206-216). Under .underReview the session is untouched, and KYCReviewViewController.viewWillAppear -> viewModel.refresh() reads the persisted KYCSession off disk (KYCReviewViewController.swift:165-173). So Back→Review is non-destructive on artifacts; the user merely bounces. Their report 'start the whole process over' is the user-side experience of an unproductive loop, not literal re-capture."

- hypothesis: "KYCStatusViewController has a custom nav-bar back chrome that we'd need to redesign."
  reason: "grep across validationLedger/ for chevron.backward / chevron.left / backButtonAppearance / UINavigationBarAppearance / backIndicatorImage returned zero matches. The visible back affordance in the screenshot is the standard iOS 26 system back-button, rendered as a capsule chevron by the OS, not a custom button. The fix is therefore the one-line `navigationItem.hidesBackButton = true` already used by NotAvailableInRegionViewController.swift:23 — no chrome rework needed."

## Evidence

- timestamp: 2026-05-20T00:00:00Z
  checked: KYCStatusViewController.swift (the file rendering this screen).
  found: "viewDidLoad sets title via NSLocalizedString(\"kyc.status.nav_title\", value: \"Verification\", ...) — matches the photo's nav title (line 126-130). The .underReview state renders SF Symbol \"hourglass\" + headline \"Under review\" + body \"Our team is reviewing your identity. This usually takes a short while.\" (line 236-249) — matches the photo's icon + heading + body verbatim. No navigationItem.hidesBackButton assignment anywhere in the file."
  implication: "Confirmed identification of the screen and confirmed Root Cause A (back-button leak on terminal screen)."

- timestamp: 2026-05-20T00:00:00Z
  checked: validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController.swift — the only other terminal-by-design screen in the app.
  found: "Line 23: `navigationItem.hidesBackButton = true  // terminal — no back path (T-03-10-05 mitigation)`."
  implication: "Established the exact precedent + comment pattern to mirror for the KYC status fix."

- timestamp: 2026-05-20T00:00:00Z
  checked: .planning/milestones/v1.0-phases/05-kyc-capture-upload-pipeline/05-CONTEXT.md decision blocks (D-12, D-14).
  found: "D-14: 'Sign-out affordance in the KYC chrome ... Prevents the trapped-on-a-screen anti-pattern.' Section line 166: 'Hard gate, but never trapped — KYC blocks the role shell (D-12) yet always offers an in-flow sign-out (D-14). Both halves are intentional.'"
  implication: "Design intent: Sign-out is the SOLE intentional escape from the KYC gate. Any other escape affordance (like a leaking nav-back) contradicts D-14."

- timestamp: 2026-05-20T00:00:00Z
  checked: validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift lines 177-186 (kycStatusResponseJSON) and 170-175 (kycSubmitResponseJSON).
  found: "Both fixtures are literal-string-pinned: submit returns `{\"overall_status\":\"under_review\"}`, status returns `{\"overall_status\":\"under_review\",\"artifacts\":[]}`. The doc comments call this out as intentional: 'under_review is the real backend's post-submit status — it lets the plan-06 Status screen render its under-review state organically.'"
  implication: "Confirmed Root Cause B — the mock is hard-pinned and there is no toggle in this file."

- timestamp: 2026-05-20T00:00:00Z
  checked: .planning/milestones/v1.0-phases/05-kyc-capture-upload-pipeline/05-UAT.md line 69.
  found: "'Blocked by ... the lack of a path to a verified KYC status ... The M1 mock returns under_review, so a verified-status fixture or live backend is needed to exercise this.'"
  implication: "This is a known/documented M1 limitation — the tester is hitting exactly the gap the UAT note called out. Resolving it via a debug-only toggle is the right scope (no live backend in M1)."

- timestamp: 2026-05-20T00:00:00Z
  checked: KYCStatusViewModel.swift mapState (lines 190-217) — verifies what under_review does NOT do.
  found: "On .underReview the VM emits state = .underReview and returns. The store.clearSession() destructive call (D-02) fires ONLY on .verified. Therefore Back → Review re-reads the persisted KYCSession intact."
  implication: "Confirms the elimination of the 'going back wipes session' hypothesis."

## Suggested Fix Direction

PRODUCT FIX (Root Cause A):
- Add `navigationItem.hidesBackButton = true` inside KYCStatusViewController.viewDidLoad with the same `// terminal — no back path (D-14 mitigation)` style comment used by NotAvailableInRegionViewController.swift:23.
- Add a unit/UI test (mirror existing KYCStatus tests) asserting `navigationItem.hidesBackButton` is true after viewDidLoad / push.

TEST-INFRA FIX (Root Cause B):
- Find an existing debug-toggle pattern in MockDefaultFixtures.swift or AppContainer.swift (look for UserDefaults flags, scheme env vars like `PROCESS_INFO_*`, or DEBUG-conditional branches that read configuration).
- Add a debug-only toggle that swaps GET /kyc/status's overall_status from "under_review" to "verified" when set. Must compile out of release (`#if DEBUG` or equivalent gate) — release builds keep `under_review`.
- Document the toggle in 05-UAT.md (replace the "blocked by lack of verified-status fixture" note with the new affordance).
- A unit test driving the mock through both branches confirms the toggle works.

VALIDATION GUARDRAILS:
- Do NOT run a bare `xcodebuild test` (false ~67 failures per ios-test-suite-pitfalls). Use the scoped serial simulator-lane command.
- Cross-phase regression: Phase 5/6/7/8 KYC + role-shell suites must stay green after both fixes.

## Resolution

root_cause: |
  Two stacked, independent root causes — both confirmed by direct file reads, both fixed:

  (A) PRODUCT — KYCStatusViewController.viewDidLoad never called `navigationItem.hidesBackButton = true`, so the system iOS 26 nav-bar back-button leaked through on a terminal-by-design screen. Tapping back popped to KYCReviewViewController, which read the persisted KYCSession intact (clearSession() only fires on verified per KYCStatusViewModel.swift:206), re-enabled Submit, and re-pushed the same Under-Review status — a bounce loop violating D-14's "hard gate, never trapped, sign-out is the only escape" contract.

  (B) TEST-INFRA — MockDefaultFixtures.kycStatusResponseJSON (and its companion kycSubmitResponseJSON) were literal-string-pinned to `"overall_status":"under_review"`. This is intentional for organic device walkthroughs (mirrors the real backend's post-submit verdict) but blocks every device-UAT path past the D-12 gate, because there is no way to reach the verified state without a live backend in M1. 05-UAT.md test 12 was already blocked by exactly this gap.

fix: |
  Three atomic commits on branch `docs/phase-8-ui-spec`:

  - `628b75e fix(05): hide nav back button on KYC status — terminal screen (D-14)`
    One line in KYCStatusViewController.viewDidLoad:
    `navigationItem.hidesBackButton = true  // terminal — no back path (D-14 mitigation)`
    Mirrors NotAvailableInRegionViewController.swift:23 verbatim style.

  - `55202b9 test(05): regression — KYCStatusViewController hides nav back button`
    New file validationLedgerTests/KYC/KYCStatusViewControllerBackButtonTests.swift
    drives viewDidLoad via loadViewIfNeeded() and asserts navigationItem.hidesBackButton == true.
    Locks the D-14 terminal-screen contract against future refactors.

  - `16a78ed chore(05): add -MockKYCStatusVerified launch-arg toggle for device UAT`
    MockDefaultFixtures.swift: split the two JSON builders into pure
    `kycSubmitResponseJSON(verifiedOverride:)` / `kycStatusResponseJSON(verifiedOverride:)`
    helpers (internal access — test-target visible), with the dispatch handler
    reading `verifiedKYCStatusOverrideActive` (which checks
    ProcessInfo.processInfo.arguments for `-MockKYCStatusVerified`). Pattern mirrors
    `-MockOTPRoleForUITest` (AppContainer.swift:547). Whole file remains
    `#if DEBUG`-wrapped — Release builds compile to zero bytes.
    MockDefaultFixturesKYCTests.swift extended with 5 new @Test cases covering
    both branches of both JSON builders + an off-by-default contract on
    `verifiedKYCStatusOverrideActive`.

  - `dfa2fc4 docs(05): note -MockKYCStatusVerified toggle in UAT test 12 (D-08)`
    Updates 05-UAT.md test 12's blocked-note with the new toggle + how to set it
    (Xcode Edit Scheme → Run → Arguments → -MockKYCStatusVerified).

verification: |
  Two scoped serial-simulator test runs on iPhone 17 (iOS 26.3 simulator), per
  ios-test-suite-pitfalls (NO bare xcodebuild test):

  - Touched suites:
    `-only-testing:validationLedgerTests/MockDefaultFixturesKYCTests`
    `-only-testing:validationLedgerTests/KYCStatusViewControllerBackButtonTests`
    Result: ✅ 12 tests in 2 suites passed (2.975s).

  - Cross-phase regression:
    `-only-testing:validationLedgerTests/KYCStatusViewModelTests`
    `-only-testing:validationLedgerTests/KYCEndToEndIntegrationTests`
    `-only-testing:validationLedgerTests/KYCCoordinatorTests`
    Result: ✅ 15 tests in 3 suites passed (2.928s). The internal-access refactor
    of the JSON builders did not break any consumer.

  Tier-2 `xcrun swiftc -parse` clean on every touched source/test file.

  Device-UAT confirmation handoff to user (physical iPhone):
    1. fix(05) back-button: organic flow — submit KYC, land on Under-Review
       status screen, confirm the system back-button is GONE. Only the D-14
       Sign-out should be tappable.
    2. chore(05) toggle: in Xcode → Edit Scheme → Run → Arguments → Arguments
       Passed On Launch, add `-MockKYCStatusVerified`. Re-run, walk KYC, on the
       Status screen confirm the verdict reads "You're verified" and "Continue"
       lands on the role shell. Phase 9 device UAT can then exercise the
       Profile "Verification status" row (05-UAT test 12) and any other
       past-D-12-gate surface.

files_changed:
  - validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift  # fix(05) — +1 line in viewDidLoad
  - validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift          # chore(05) — toggle + JSON builder refactor
  - validationLedgerTests/KYC/KYCStatusViewControllerBackButtonTests.swift   # test(05) — new regression test (49 lines)
  - validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift              # chore(05) — +5 @Test cases for the toggle
  - .planning/milestones/v1.0-phases/05-kyc-capture-upload-pipeline/05-UAT.md  # docs(05) — test 12 note flips to new toggle
