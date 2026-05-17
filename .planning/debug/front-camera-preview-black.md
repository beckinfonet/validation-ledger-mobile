---
status: verifying
trigger: "Front-camera preview does NOT open in the KYC face-capture screen on a physical iPhone — preview area is solid black."
created: 2026-05-17T00:00:00Z
updated: 2026-05-17T12:00:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "The preview is black because `previewContainer` (a plain `UIView`) has ZERO height. It is an arranged subview of a vertical `UIStackView` with the default `distribution = .fill`, and it has NO height constraint and NO intrinsic content size (a plain UIView reports `UIView.noIntrinsicMetric` on both axes). The other arranged subviews — the instruction label, cue label, (and for vehicle capture) the shutter button — all have real intrinsic heights. With the stack pinned top-and-bottom to the safe area and `previewContainer` the only axis member with no height preference, Auto Layout has nothing forcing the container tall, so it collapses to height 0. `previewLayer.frame = previewContainer.bounds` then copies a zero-height rect → the preview layer is 0pt tall → the `.black` container background is all that shows → solid-black preview area while the labels/title/buttons render normally."
  confirming_evidence:
    - "FaceCaptureViewController.swift:107 — `UIStackView(arrangedSubviews: [instructionLabel, previewContainer, cueLabel])`, `stack.axis = .vertical`, NO `stack.distribution` set so it defaults to `.fill`."
    - "FaceCaptureViewController.swift:114-131 — the stack is pinned to all FOUR safe-area edges (top + bottom). NO height/aspect constraint anywhere on `previewContainer`. grep for `previewContainer.*Anchor` / `heightAnchor` in the file: zero matches."
    - "FaceCaptureViewController.swift:36-42 — `previewContainer` is a bare `UIView` (background `.black`). A bare UIView's `intrinsicContentSize` is `(noIntrinsicMetric, noIntrinsicMetric)` — it gives Auto Layout no height preference."
    - "VehicleCaptureViewController.swift:96-124 — IDENTICAL defect: `previewContainer` plain UIView, vertical `.fill` stack, pinned top+bottom, only `shutterButton` gets a height constraint (`>= 44`), `previewContainer` gets none. DL-back/truck/trailer/plate all inherit this."
    - "viewDidLayoutSubviews sets `previewLayer.frame = previewContainer.bounds` — but that is CIRCULAR: if `previewContainer.bounds` is itself zero-height, the copy is zero-height too. The prior session's 'zero frame eliminated' check only proved the COPY happens, never that the SOURCE bounds are non-zero."
    - "Symptom fingerprint matches exactly: chrome (labels/title/buttons — all have intrinsic size) renders fine; ONLY the preview area (the no-intrinsic-size container) is black."
  falsification_test: "If this hypothesis is wrong, giving `previewContainer` an explicit non-zero height (a height/aspect constraint, or a min-height) would NOT make the preview appear. It will, because once the container has real bounds the AVCaptureVideoPreviewLayer — already correctly bound to the started session — renders into a visible rect."
  fix_rationale: "Constrain `previewContainer` to a definite size: pin a 3:4 portrait aspect ratio (`heightAnchor == widthAnchor * 4/3`) so the container always has a non-zero, device-independent height. This addresses the root cause (zero-height host view) directly. The session/permission/preview-layer wiring from b2983a9 is correct and is kept. Diagnostic logging is also added to the camera path so the on-device run produces decisive evidence and confirms the fix."
  blind_spots: "Cannot run a live camera on the simulator (RESEARCH Pitfall 1) — on-device re-verification is required. The aspect-ratio constant (3:4) is a layout choice; if the oval guide or chrome looks off the constant can be tuned, but a non-zero height is the load-bearing fix. The added logging will print the resolved `previewContainer.bounds` so the tester's run definitively confirms height is now non-zero."

## Symptoms

expected: "Front-camera live preview renders in the KYC face-capture screen on a physical iPhone after granting camera permission."
actual: "Face-capture screen chrome renders correctly but the preview area is solid black — no live front-camera feed."
errors: "None reported — no crash, no error state. Silent black preview."
reproduction: "Fresh install, DEBUG container (event=debug), route to kyc.carrier, tap Get started, grant the camera permission prompt, reach the Verify identity screen."
started: "Phase 05 device verification — first time the live camera path ran on a physical device."

## Eliminated

- hypothesis: "DEBUG build injects a mock/stub camera instead of the real AVFoundationCameraSession."
  evidence: "KYCCoordinator.pushFaceCapture() constructs AVFoundationCameraSession() directly (line 252). No #if DEBUG branch, no mock. The real session is wired."
  timestamp: 2026-05-17T00:00:00Z
- hypothesis: "VC failed to load / lay out."
  evidence: "Tester reports all chrome (title, back, sign-out, instruction, cue) renders correctly — VC loaded and laid out fine."
  timestamp: 2026-05-17T00:00:00Z
- hypothesis: "[DISPROVEN ROOT CAUSE — round 1] AVFoundationCameraSession starts the AVCaptureSession before camera authorization is resolved (start-before-grant race)."
  evidence: "Commit b2983a9 added startAuthorizedSession() — awaits requestPermission() and only then configures + starts the session — plus an off-main serial queue. The tester re-tested on the physical iPhone and the preview is STILL solid black. The tester's device already had camera permission granted, so startAuthorizedSession's requestPermission() returns .authorized immediately and proceeds to configure + start — and it is still black. The defect is therefore NOT permission timing. b2983a9 is kept (permission-gating + off-main session work are still correct) but it is NOT the root cause."
  timestamp: 2026-05-17T12:00:00Z
- hypothesis: "[round 1 — INCORRECTLY eliminated] Preview layer has a zero frame / wrong frame."
  evidence: "Round 1 eliminated this by noting viewDidLayoutSubviews sets previewLayer.frame = previewContainer.bounds. That elimination was WRONG — it is circular. Copying previewContainer.bounds into previewLayer.frame does nothing if previewContainer.bounds is itself zero-height. Round 2 found previewContainer IS zero-height (plain UIView, no height constraint, no intrinsic size, in a .fill vertical stack) — this IS the root cause. Re-opened and confirmed."
  timestamp: 2026-05-17T12:00:00Z
- hypothesis: "Preview layer's session ≠ the session that gets startRunning()."
  evidence: "CameraSession.swift:112 — a single `private let session = AVCaptureSession()`. `_previewLayer` (line 114-118, lazy) is built as `AVCaptureVideoPreviewLayer(session: session)` against that same instance. start()/stop() (lines 173-185) call startRunning()/stopRunning() on the same `session`. VM.previewLayer and VC.previewLayer both resolve to the one `_previewLayer`. Session identity is correct — not the bug."
  timestamp: 2026-05-17T12:00:00Z
- hypothesis: "Front-camera device discovery returns nil / NSCameraUsageDescription missing."
  evidence: "captureDevice(for: .front) uses AVCaptureDevice.DiscoverySession([.builtInWideAngleCamera], .video, .front) — valid on every iPhone. Info.plist (validationLedger/App/Info.plist:81) contains NSCameraUsageDescription with a non-empty string (CameraUsageDescriptionTests asserts this). If discovery failed it would throw .cameraUnavailable and the VM would show the 'camera isn't available' failure copy — the tester sees the normal chrome, not that error. Not the bug."
  timestamp: 2026-05-17T12:00:00Z

## Evidence

- timestamp: 2026-05-17T00:00:00Z
  checked: "FaceCaptureViewModel.start() and the CameraSession protocol surface."
  found: "start() calls configure(.front) + start() with no requestPermission() call; the protocol HAS requestPermission() but it has zero callers in the capture path."
  implication: "[round 1] Thought to be the root cause — disproven in round 2: b2983a9 fixed this and the preview is still black."
- timestamp: 2026-05-17T12:00:00Z
  checked: "Round-2 re-test result reported by the tester after b2983a9 shipped."
  found: "Preview STILL solid black on the physical iPhone. The device already had camera permission granted, so startAuthorizedSession's requestPermission() returns .authorized immediately and still proceeds to a black preview."
  implication: "Permission timing is DISPROVEN as the (sole) root cause. The defect is downstream of permission — in the preview-rendering wiring or layout."
- timestamp: 2026-05-17T12:00:00Z
  checked: "Session instance identity — does the preview layer's session == the session that gets startRunning()."
  found: "CameraSession.swift:112 — one `private let session`. `_previewLayer` (lines 114-118) = `AVCaptureVideoPreviewLayer(session: session)` — same instance. start()/stop() act on the same `session`. VM.previewLayer + VC.previewLayer both resolve to the single `_previewLayer`."
  implication: "Session identity is correct. Ruled out."
- timestamp: 2026-05-17T12:00:00Z
  checked: "FaceCaptureViewController layout — how `previewContainer` is sized."
  found: "previewContainer is a plain UIView (line 36-42, background .black, no intrinsic content size). It is the middle arranged subview of a vertical UIStackView (line 107). `stack.distribution` is NEVER set → defaults to `.fill`. The stack is pinned to ALL FOUR safe-area edges (lines 114-131, top constant +xl, bottom constant -xl). There is NO height constraint, NO aspect constraint anywhere on previewContainer."
  implication: "ROOT CAUSE. In a `.fill` vertical stack the container must take some axis height; with no intrinsic size and no constraint, and the labels having real intrinsic heights, Auto Layout has nothing forcing the container tall — it collapses to height 0. previewLayer.frame := previewContainer.bounds is then a zero-height rect → no preview renders → solid black."
- timestamp: 2026-05-17T12:00:00Z
  checked: "VehicleCaptureViewController layout (DL-back/truck/trailer/plate)."
  found: "Identical defect — previewContainer plain UIView, vertical `.fill` stack pinned top+bottom, only shutterButton gets a height constraint (>= 44), previewContainer gets none (lines 96-124)."
  implication: "Same root cause across all 5 KYC capture screens; the same fix applies to both VCs."

## Resolution

root_cause: "The KYC capture preview area is solid black because the `previewContainer` view that hosts the AVCaptureVideoPreviewLayer collapses to ZERO height. In both FaceCaptureViewController and VehicleCaptureViewController, `previewContainer` is a plain UIView (no intrinsic content size) placed as an arranged subview of a vertical UIStackView whose `distribution` is left at the default `.fill`, with the stack pinned to all four safe-area edges and NO height/aspect constraint on the container. The sibling labels/buttons have real intrinsic heights; the container, with no height preference and no constraint, has an underdetermined axis size that Auto Layout resolves to 0. `previewLayer.frame = previewContainer.bounds` (in viewDidLayoutSubviews) then copies a zero-height rect, so the preview layer is 0pt tall and only the container's .black background shows. The chrome (title, labels, buttons) renders fine because those views have intrinsic sizes. The permission/session/preview-layer wiring from b2983a9 is correct — it was a real but secondary issue, not this symptom's cause."
fix: "Constrain `previewContainer` to a definite, non-zero size. Added a 3:4 portrait aspect-ratio constraint (`previewContainer.heightAnchor == previewContainer.widthAnchor * 4/3`) in both FaceCaptureViewController and VehicleCaptureViewController so the host view always resolves to a real height regardless of device. Comprehensive diagnostic logging was also added across the camera path (VC lifecycle with resolved bounds, device discovery, input/output counts, session.isRunning after start, preview-layer hierarchy + frame, video-connection state, any caught errors) so the tester's next on-device run produces decisive evidence and confirms the preview host bounds are now non-zero."
verification: "Build SUCCEEDED for the iPhone 16e simulator. Live camera cannot run on the simulator (RESEARCH Pitfall 1) — on-device re-verification by the tester is required; the new logging makes that verification decisive."
files_changed:
  - "validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift — added 3:4 aspect-ratio constraint on previewContainer (root-cause fix) + diagnostic logging across lifecycle / preview-layer wiring"
  - "validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift — same aspect-ratio fix + diagnostic logging"
  - "validationLedger/Core/Identity/Capture/CameraSession.swift — diagnostic logging across device discovery / input / output / session start / video connection"
status_note: "Round-2 root cause found (zero-height preview host) + fixed; comprehensive camera-path instrumentation added. Build verified on simulator; on-device re-verification by the tester pending."
