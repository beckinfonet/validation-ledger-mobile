---
status: resolved
trigger: "KYCSessionStore lost-update data race (Phase 5, plan 05-06 checkpoint blocker). KYCSessionStore is @unchecked Sendable with no lock/serial queue, every method is a non-atomic read-modify-write (loadSession -> mutate -> persist) of the whole kyc-session.json file, accessed concurrently from the @MainActor capture path and the KYCUploader background actor. D-01 pipelined upload runs the chunk loop while the user keeps capturing, so capture and uploader read-modify-write cycles silently clobber each other. User-reported symptom: capture works on device but artifacts do not appear preserved. SECONDARY decision: KYCUploader.deleteLocalArtifactData wipes artifactData post-commit (D-02), so KYCReviewViewModel renders no thumbnails for committed artifacts -- conflicts with fix commit 33dbdb0."
created: 2026-05-17T18:30:00Z
updated: 2026-05-17T19:45:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "KYCSessionStore has a lost-update data race. The store is `@unchecked Sendable` with NO lock and NO serial queue; every public method is a non-atomic read-modify-write of the entire kyc-session.json file (loadSession decodes the whole file -> caller mutates the struct -> persist re-encodes and writes the whole file). It is accessed concurrently from two genuinely parallel execution contexts: (1) the @MainActor capture path (FaceCaptureViewModel.persist, VehicleCaptureViewModel.persist, DLFrontScanViewController.persist) and (2) the KYCUploader background actor (persistFreshState, markChunkAcked, markCommitted, deleteLocalArtifactData). D-01 pipelined upload is DESIGNED to overlap them — KYCCoordinator.kickUpload fires `Task { await uploader.upload(...) }` on every capture-confirm and the user immediately captures the next artifact. When a capture's load->mutate->persist interleaves with an uploader's load->mutate->persist, whichever persists last wins and the other write is silently dropped (lost update, both directions: a fresh capture can be clobbered, or an uploader state update can be clobbered)."
  confirming_evidence:
    - "KYCSessionStore.swift:46 — `public final class KYCSessionStore: @unchecked Sendable` with no NSLock/DispatchQueue/os_unfair_lock anywhere in the file (grep confirmed; the only `actor` near the store is KYCUploader)."
    - "All four writers use the identical non-atomic pattern: `var session = (try store.loadSession()) ?? KYCSession(); session.artifactData[key] = data; try store.persist(session)` — FaceCaptureViewModel.swift:321, VehicleCaptureViewModel.swift:267, DLFrontScanViewController.swift:316; KYCUploader's mutate-helpers do the same load->mutate->persist."
    - "KYCCoordinator.kickUpload (KYCCoordinator.swift:219) spawns `Task { await uploader.upload(artifactType:) }` on each confirmCapture; the comment states the chunk loop 'runs while the user keeps shooting' (D-01). Capture VMs run on @MainActor; KYCUploader is an `actor` (background executor). The store calls are synchronous so they execute on whichever thread calls them — MainActor thread vs uploader executor thread, genuinely parallel."
  falsification_test: "After serializing the store's read-modify-write, a stress test that hammers the store from a MainActor-like context and a background-actor context concurrently must never lose a write — the final session must contain every artifact and every upload-state mutation."
  fix_rationale: "RESOLVED with option (a)+atomic-API: a single private NSLock guards every public method AND an atomic `withSession(_:)` read-modify-write API loads/mutates/persists under one held lock so a caller's whole load->mutate->persist is atomic — not just each file op. The crux noted in the original rationale (a per-method lock still races a caller doing loadSession() then a separate persist()) is addressed precisely by `withSession`; every capture writer and uploader mutate-helper routes through it. NSLock keeps the synchronous API, so the SceneDelegate synchronous caller has zero async ripple. The merged commit-and-free path (`commitAndFreeArtifactData`) folds the former markCommitted + deleteLocalArtifactData two-call sequence into ONE atomic update so no concurrent capture can interleave between commit and free."
  blind_spots: "The race is timing-dependent; the falsification harness uses real OS Threads + a semaphore rendezvous to make the interleave deterministic rather than relying on luck. Device confirmation remains the ultimate proof and is the close-out's open follow-up."

test: "validationLedgerTests/KYC/KYCSessionStoreConcurrencyTests.swift — three deterministic lost-update repros on real OS threads (interleaved withSession writes both survive; a capture write racing an uploader chunk-ack both survive; 40 concurrent atomic increments all land). All RED on the unsynchronized store, GREEN after the NSLock + withSession fix."
expecting: "Current code: concurrent writers lose updates (final session missing artifacts or upload-state mutations). Fixed code: every write survives."
next_action: "RESOLVED — see Resolution."

## Symptoms

expected: "Every KYC artifact captured on device (face, dl_front, dl_back, truck, trailer, plate) is durably persisted to KYCSessionStore and survives — the artifact bytes and per-artifact upload state are never silently lost while other artifacts are being captured or uploaded."
actual: "User reports: capture works on device but artifacts do not appear preserved ('I dont see that it is getting preserved'). Consistent with concurrent capture/upload writes clobbering each other on the unsynchronized store."
errors: "None — the failure is SILENT. A lost update produces no exception; the losing writer's persist() succeeds, it just wrote a stale snapshot. No log line fires."
reproduction: "Run the KYC capture flow on a physical iPhone (simulator has no camera). With the mock backend, each artifact's D-01 pipelined upload (init->chunk->commit->deleteLocalArtifactData) completes in milliseconds, overlapping the next artifact's capture+persist — the collision window is hit on essentially every capture."
started: "Phase 05 plan 05-06 device-testing checkpoint. The capture flow (plans 05-03/05/06) was first exercised end-to-end on device only at this checkpoint; the simulator could not surface it."

## Eliminated

## Evidence

- timestamp: 2026-05-17T18:30:00Z
  checked: "KYCSessionStore.swift — full file; grep for NSLock/DispatchQueue/os_unfair_lock/.lock/actor across KYCSessionStore.swift + KYCUploader.swift."
  found: "KYCSessionStore is `public final class ... @unchecked Sendable` (line 46) with ZERO synchronization primitives. persist() does JSONEncoder().encode then Data.write(.completeFileProtection, .atomic); loadSession() does Data(contentsOf:) then JSONDecoder().decode; mutate()/markChunkAcked()/markCommitted()/deleteLocalArtifactData() all do loadSession()->mutate->persist(). The `.atomic` write option only prevents a torn single file write — it provides no mutual exclusion between two independent read-modify-write cycles."
  implication: "Every store mutation is a non-atomic read-modify-write. Two concurrent callers each snapshot the file, each mutate their own copy, each write back — last writer wins, the other's change is lost."

- timestamp: 2026-05-17T18:30:00Z
  checked: "FaceCaptureViewModel.persist (line 321), VehicleCaptureViewModel.persist (line 267), DLFrontScanViewController.persist (line 316), KYCUploader.upload/persistFreshState (lines 85-187/349-371)."
  found: "All capture writers run on @MainActor (the VMs are @MainActor; DLFrontScanViewController is a UIViewController). KYCUploader is declared `public actor` — its body, including the synchronous store.loadSession()/persist()/markChunkAcked()/markCommitted()/deleteLocalArtifactData() calls, runs on the actor's own (background) executor. The two contexts run on different threads with no shared lock."
  implication: "MainActor capture writes and uploader-actor writes to the shared single KYCSessionStore instance are genuinely parallel and unsynchronized."

- timestamp: 2026-05-17T18:30:00Z
  checked: "KYCCoordinator.kickUpload (line 219), confirmCapture (line 238); D-01 design comments (lines 25-32)."
  found: "On each capture-confirm, confirmCapture() calls kickUpload(for:) which does `Task { await uploader.upload(artifactType:) }` and returns immediately; the user advances to the next capture screen. D-01 is explicitly documented: 'the upload runs while the user keeps shooting the remaining artifacts.' Against the mock backend the full init->chunk->commit->deleteLocalArtifactData cycle completes in milliseconds."
  implication: "The pipelined upload is DESIGNED to overlap the next capture. The race window is not an edge case — it is on the main path of every multi-artifact KYC run."

- timestamp: 2026-05-17T18:30:00Z
  checked: "KYCUploader.deleteLocalArtifactData call (KYCUploader.swift:184); KYCReviewViewModel.refresh (KYCReviewViewModel.swift:151-160); KYCSessionStore.deleteLocalArtifactData (line 150)."
  found: "SECONDARY (separate from the race): after a successful commit KYCUploader calls store.deleteLocalArtifactData(artifactType), which removes artifactData[artifact] (D-02 footprint control). KYCReviewViewModel.refresh sets `thumbnailData: session?.data(for: artifact)` which is then nil for every committed artifact. Against the mock backend every artifact commits seconds after capture, so by the time the user reaches Review, artifactData is empty and the Review grid shows no thumbnails — only status badges."
  implication: "This is design-as-built (D-02), NOT the race — but it ALSO reads to a user as 'not preserved', and it directly conflicts with fix commit 33dbdb0 'Review screen renders the captured-photo thumbnails'. D-02 deletes the bytes those thumbnails render from. Needs a product decision: keep deleting post-commit and show badge-only on Review, vs. retain a small downscaled thumbnail copy. Settle in this session alongside the race fix."

- timestamp: 2026-05-17T19:00:00Z
  checked: "Falsification harness — KYCSessionStoreConcurrencyTests.swift run on the UNSYNCHRONIZED store, then re-run after the NSLock + withSession fix."
  found: "On the unsynchronized store the three repros FAIL: interleaved writes drop one artifact, a capture racing an uploader chunk-ack drops one of the two mutations, and the 40-increment counter lands well short of 40. After the fix all three are GREEN — every write survives, the 40-increment counter lands exactly 40. The harness deliberately runs real OS `Thread`s (not the cooperative pool) with a `DispatchSemaphore` rendezvous so the load->persist windows overlap DETERMINISTICALLY."
  implication: "Confirms a TRUE multi-thread data race, not a theoretical interleave. The MainActor capture executor and the KYCUploader actor executor are genuinely distinct OS threads; the failure reproduces every run once the load->persist windows are forced to overlap."

## Resolution

root_cause: |
  A confirmed multi-thread lost-update data race on KYCSessionStore. The store was
  `@unchecked Sendable` with NO synchronization primitive, and every mutation was a
  non-atomic load -> mutate -> persist of the whole single kyc-session.json file.
  It was reached concurrently from two genuinely parallel OS-thread contexts: the
  @MainActor capture path (FaceCaptureViewModel / VehicleCaptureViewModel /
  DLFrontScanViewController each doing `loadSession()` then a separate `persist()`)
  and the KYCUploader background-actor executor (persistFreshState / markChunkAcked
  / markCommitted / deleteLocalArtifactData). D-01 pipelined upload is DESIGNED to
  overlap them — `KYCCoordinator.kickUpload` fires the upload Task on every
  capture-confirm while the user immediately captures the next artifact. When a
  capture's read-modify-write interleaved with an uploader's, whichever persisted
  LAST overwrote the other's snapshot and the losing write was silently dropped
  (no exception, no log) — so a freshly captured artifact, or an upload-state
  cursor advance, could vanish. The `.atomic` write option guards only a torn
  single-file write; it provides zero mutual exclusion between two independent
  read-modify-write cycles. The falsification harness (real OS threads + a
  semaphore rendezvous) reproduced the lost update deterministically, confirming a
  true thread race rather than a theoretical interleave.

  SECONDARY (a separate, conflated symptom): post-commit D-02 footprint control
  (`deleteLocalArtifactData`) wiped `artifactData[artifact]`, so `KYCReviewViewModel
  .refresh()` — which sourced its thumbnail straight from `artifactData` — rendered
  no thumbnail for any committed artifact, directly undoing fix commit 33dbdb0.

fix: |
  PRIMARY — serialize the store's read-modify-write:
  - Added a single private `NSLock` to KYCSessionStore guarding ALL file I/O.
  - Added an atomic `withSession(_:)` read-modify-write API: it loads, hands the
    caller an `inout KYCSession`, and persists — all inside ONE held lock — so a
    caller's whole load->mutate->persist is atomic, not merely each file op (a
    per-method lock would still race a caller doing loadSession() then a separate
    persist()). The internal mutate / markChunkAcked / markCommitted /
    deleteLocalArtifactData helpers hold the lock across their full cycle too.
  - Re-pointed every writer at the atomic API: FaceCaptureViewModel.persist,
    VehicleCaptureViewModel.persist and DLFrontScanViewController.persist now call
    `store.withSession { ... }`; KYCUploader.persistFreshState uses `withSession`.
  - NSLock (not a serial queue or an actor) keeps the store's synchronous API, so
    the synchronous SceneDelegate caller has zero async ripple.

  SECONDARY — retain a small downscaled Review thumbnail post-commit (user chose
  Option 1):
  - Added `thumbnailData: [String: Data]` to KYCSession (keyed by
    ArtifactType.rawValue). A custom `init(from:)` uses `decodeIfPresent` so an
    OLDER on-disk session JSON without the key still decodes, defaulting to `[:]`.
    Added a `thumbnail(for:)` accessor mirroring `data(for:)`.
  - Added KYCThumbnail — a pure Core Graphics (`CGImageSource` /
    `UIImage.jpegData`) downscale helper producing a ~150 px-longest-edge JPEG;
    returns nil for a non-image blob so the commit path can never crash. UIKit
    only, no SwiftUI.
  - Added `KYCSessionStore.commitAndFreeArtifactData(_:artifactID:thumbnail:)`,
    which folds the former markCommitted + deleteLocalArtifactData two-call
    sequence into ONE atomic held-lock update: it marks committed/artifactID,
    retains the thumbnail, frees the multi-MB `artifactData` blob, and clears
    `localDataAvailable`. KYCUploader.upload now downscales the committed image
    (its own work, before the store call so the critical section stays
    await-free) and calls this single atomic method. The multi-MB full image is
    still freed — the D-02 footprint intent holds; a few-KB thumbnail is not the
    full-resolution identity-image exposure D-02 guards.
  - KYCReviewViewModel.refresh() now sources the row image from
    `session.thumbnail(for:)` (the retained downscaled JPEG) and falls back to
    `session.data(for:)` for a not-yet-committed artifact whose full bytes are
    still on disk.

verification: |
  Built for the iPhone 16e simulator with `xcodebuild build-for-testing` —
  TEST BUILD SUCCEEDED, the new files compile cleanly.

  Ran every KYC suite with `-parallel-testing-enabled NO` — 58 tests across 12
  suites, all GREEN:
  - KYCSessionStoreConcurrencyTests — the 3 deterministic lost-update repros (real
    OS threads + semaphore rendezvous): interleaved withSession writes both
    survive, a capture write racing an uploader chunk-ack both survive, 40
    concurrent atomic increments all land. RED on the pre-fix store, GREEN now.
  - KYCThumbnailTests (new) — a committed artifact keeps a renderable thumbnail
    after its full bytes are freed (asserts `data(for:)` is nil AND
    `thumbnail(for:)` decodes to a valid UIImage within the ~150 px cap);
    KYCReviewViewModel.refresh surfaces the post-commit thumbnail; the downscale
    helper produces a small JPEG and returns nil for a non-image blob; an older
    session JSON without the thumbnailData key still decodes.
  - KYCSessionStoreTests, KYCUploaderTests (incl. the D-02 delete test, still
    green), KYCUploaderIdempotency/Resume/Progress/Retry, KYCReviewViewModelTests,
    KYCCoordinatorTests, KYCStatusViewModelTests, KYCCapturePreviewLayoutTests —
    all pass.

  The ~40 MockURLProtocol parallel-execution flakes are a known unrelated baseline
  and are not in play here — every run above used `-parallel-testing-enabled NO`.
  Open follow-up: on-device confirmation of the capture flow remains the ultimate
  proof and is the plan 05-06 checkpoint's remaining device-test step.

files_changed: |
  - validationLedger/Core/Storage/KYCSessionStore.swift — NSLock; atomic
    `withSession`; lock held across every read-modify-write; new
    `commitAndFreeArtifactData` merged commit+free.
  - validationLedger/Core/Identity/KYCUploader.swift — `persistFreshState` uses
    `withSession`; `upload` downscales the committed image and calls
    `commitAndFreeArtifactData` (replacing markCommitted + deleteLocalArtifactData).
  - validationLedger/Core/Identity/KYC/KYCSession.swift — `thumbnailData` field;
    forward-compatible `init(from:)`; `thumbnail(for:)` accessor.
  - validationLedger/Core/Identity/KYC/KYCThumbnail.swift — NEW; Core Graphics
    downscale helper.
  - validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift —
    `refresh()` sources the row image from `thumbnail(for:)` with `data(for:)`
    fallback.
  - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift,
    VehicleCaptureViewModel.swift, DLFrontScanViewController.swift — `persist`
    routes through `withSession`.
  - validationLedgerTests/KYC/KYCSessionStoreConcurrencyTests.swift — NEW;
    deterministic lost-update falsification harness.
  - validationLedgerTests/KYC/KYCThumbnailTests.swift — NEW; post-commit
    thumbnail-retention + downscale + forward-compatible-decode tests.
