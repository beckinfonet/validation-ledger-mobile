// validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift
// Phase 5 Plan 05 — KYC-02: the face-capture view model.
//
// VM contract copied from `OTPViewModel` — `@MainActor final class`, a nested
// `State: Equatable, Sendable`, a `state` `didSet` firing `onStateChange`,
// `on…: ((…) -> Void)?` callbacks, and initializer DI (ARCH-04).
//
// === MANUAL SHUTTER (debug session `kyc-upload-capture-bugs`, Issue 1b) ===
// SUPERSEDES the D-04 hands-free auto-fire. The selfie screen no longer
// auto-captures: the user fires the shutter explicitly, exactly like the
// `VehicleCaptureViewModel` plain-photo screens. The Vision quality gate
// (plan 03 `FaceQualityGate` / `SteadyHoldTracker`) is RETAINED — but it is
// repurposed: the gate-signal stream now drives the SHUTTER-ENABLED state, so
// the shutter unlocks only while the face-quality gate holds a steady `.pass`
// (the user still cannot capture a bad selfie). The steady-hold dwell remains
// the de-bounce — a transient `.pass` does not unlock the shutter. See the
// Resolution in `.planning/debug/resolved/kyc-upload-capture-bugs.md`.
//
// KYC-04 / Pitfall 5: at capture the VM reads `GeoContext.freshLocation()`;
// a stale fix throws and capture is blocked with the GPS-stale copy. On success
// the upload `Data` is produced via `GPSMetadataInjector.uploadData(from:
// location:)` — straight from the `AVCapturePhoto`, never through a UIKit image
// decode (the trust boundary — Pitfall 6) — and written into the
// `KYCSessionStore` so plan 04's `KYCUploader` can pick it up.

import AVFoundation
import CoreLocation
import Foundation
import UIKit

/// Drives the face-capture screen: the live quality-gate stream (now gating the
/// manual shutter — Issue 1b), the manual-shutter capture, the capture-time GPS
/// injection, and persistence of the captured bytes into the KYC session.
@MainActor
final class FaceCaptureViewModel {

    // MARK: - State

    /// The capture screen's UI state.
    enum State: Equatable, Sendable {
        /// Waiting for the quality gate — `reason` drives the live inline cue.
        /// The shutter is DISABLED in this state.
        case adjusting(FaceAdjustReason?)
        /// The gate passes and is holding steady (~0.5s) — the shutter is
        /// ENABLED; the user may fire it (Issue 1b). The "Hold still" cue shows.
        case readyToCapture
        /// A still-photo capture is in flight.
        case capturing
        /// Capture is blocked because the GPS fix is stale/unavailable (Pitfall 5).
        case locationUnavailable
        /// A still-photo capture timed out — the capture source is presumed
        /// dead (e.g. after an ungraceful force-quit). RECOVERABLE: the shutter
        /// stays ARMED so the user can retry, exactly like `.locationUnavailable`
        /// (Test 10 gap — the camera self-heals on the next attempt).
        case captureUnavailable
        /// The shot is captured — the preview screen is presented.
        case captured
        /// A non-recoverable capture failure.
        case failed(String)
    }

    private(set) var state: State = .adjusting(nil) {
        didSet { onStateChange?(state) }
    }

    /// A render-only `UIImage` of the just-captured shot, for the D-07
    /// Use/Retake preview screen. Decoded from the `AVCapturePhoto` purely to
    /// be SHOWN — this is NOT the upload byte source. The upload `Data` is
    /// produced separately via `GPSMetadataInjector.uploadData(from:location:)`
    /// straight from the `AVCapturePhoto` (Pitfall 6 — the GPS-EXIF trust
    /// boundary), and never passes through this UIKit decode.
    private(set) var capturedPreviewImage: UIImage?

    // MARK: - Callbacks (UIKit-first — no Combine)

    /// Fired on every `state` transition.
    var onStateChange: ((State) -> Void)?

    /// Fired once the user confirms the still preview ("Use photo" — D-07).
    /// `KYCCoordinator` advances the flow on this.
    var onCaptureConfirmed: (() -> Void)?

    // MARK: - Dependencies (initializer DI — ARCH-04)

    private let cameraSession: any CameraSession
    private let faceQualityGate: any FaceQualityGate
    private let geoContext: GeoContext
    private let gpsInjector: GPSMetadataInjector
    private let sessionStore: KYCSessionStore
    private let logger: any Logger

    /// The Vision quality gate's steady-hold de-bounce (plan 03). RETAINED from
    /// the D-04 design but REPURPOSED (Issue 1b): `.pass` must hold ~0.5s before
    /// the tracker reports `true` — and that now drives the SHUTTER-ENABLED
    /// state, not an auto-fire. Pure value type; exercised in plan 03's
    /// `FaceQualityGateTests`.
    private var steadyHold = SteadyHoldTracker()

    /// `true` once a capture has fired — guards against a double-fire while the
    /// still-capture is in flight (e.g. a double-tap on the shutter).
    private var captureInFlight = false

    init(
        cameraSession: any CameraSession,
        faceQualityGate: any FaceQualityGate,
        geoContext: GeoContext,
        gpsInjector: GPSMetadataInjector,
        sessionStore: KYCSessionStore,
        logger: any Logger
    ) {
        self.cameraSession = cameraSession
        self.faceQualityGate = faceQualityGate
        self.geoContext = geoContext
        self.gpsInjector = gpsInjector
        self.sessionStore = sessionStore
        self.logger = logger
    }

    /// The camera preview layer for the VC to host. Render-only — never the
    /// upload byte source (Pitfall 6).
    var previewLayer: AVCaptureVideoPreviewLayer {
        cameraSession.previewLayer
    }

    /// The live `AVCaptureSession` for the VC's `CameraPreviewView` backing
    /// layer (debug session `front-camera-preview-black`, round 4). The VC
    /// hosts the preview via a `layerClass`-override view whose backing layer
    /// IS an `AVCaptureVideoPreviewLayer` — this exposes the session to wire
    /// into it, replacing the fragile manual add-as-sublayer pattern. Read off
    /// the session's own preview layer so there is exactly ONE session instance
    /// (the one `start()`/`stop()`/`capturePhoto()` act on). Render-only.
    var captureSession: AVCaptureSession? {
        cameraSession.previewLayer.session
    }

    // MARK: - Lifecycle

    /// Start the camera + the quality-gate signal stream. On the simulator
    /// `isCameraAvailable` is false so this no-ops the live session
    /// (RESEARCH Pitfall 1).
    ///
    /// The session start is routed through `startAuthorizedSession` so camera
    /// authorization is resolved BEFORE the `AVCaptureSession` is configured +
    /// started. A session started before the permission grant resolves never
    /// receives the camera feed — the preview would stay black even after the
    /// user grants access. Awaiting the permission resolution closes that race.
    func start() {
        guard AVFoundationCameraSession.isCameraAvailable else {
            logger.info(event: LogEvent("kyc_face_capture_no_camera"), fields: [:])
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cameraSession.startAuthorizedSession(position: .front)
            } catch CameraSessionError.permissionDenied {
                self.logger.warn(
                    event: LogEvent("kyc_face_capture_permission_denied"),
                    fields: [:]
                )
                self.state = .failed(NSLocalizedString(
                    "kyc.error.camera_permission",
                    value: "Camera access is needed to verify your identity. Turn it on in Settings.",
                    comment: "KYC camera-permission-denied capture error"
                ))
                return
            } catch {
                self.state = .failed(NSLocalizedString(
                    "kyc.error.camera_unavailable",
                    value: "The camera isn't available on this device.",
                    comment: "KYC camera-unavailable error"
                ))
                return
            }
            self.observeGateSignals()
        }
    }

    /// Stop the camera + the signal stream. Clears the live-frame handler so no
    /// buffers reach the gate after the screen leaves (debug session
    /// `front-camera-preview-black`, round 5 / Bug B).
    func stop() {
        cameraSession.videoFrameHandler = nil
        faceQualityGate.stop()
        cameraSession.stop()
    }

    /// Reset the screen for a Retake (D-07) — clears the steady-hold run and
    /// the stale render-only preview image. The shutter re-locks until the
    /// quality gate next holds a steady `.pass` (Issue 1b).
    func resetForRetake() {
        steadyHold.reset()
        captureInFlight = false
        capturedPreviewImage = nil
        state = .adjusting(nil)
    }

    /// Confirm the still preview ("Use photo" — D-07). Bubbles to the coordinator.
    func confirmCapture() {
        onCaptureConfirmed?()
    }

    // MARK: - Quality-gate stream → shutter-enabled state (Issue 1b)

    /// Wire the live camera-frame pipeline into the Vision gate, then consume
    /// the gate's signal stream to drive the SHUTTER-ENABLED state (Issue 1b).
    ///
    /// Debug session `front-camera-preview-black` round 5 / Bug B: this is the
    /// frame source. Order matters — `signals()` installs the `AsyncStream`
    /// continuation; only AFTER that is the `videoFrameHandler` set, so the
    /// first processed buffer always has a live continuation to yield into.
    /// Each `CMSampleBuffer` is handed to `VisionFaceQualityGate.process(
    /// sampleBuffer:)`, which runs Vision face detection and yields a
    /// `FaceGateSignal`; `handle(signal:)` then drives the shutter-enable gate.
    /// The handler runs on the camera's serial frame queue (`@Sendable`); the
    /// gate's `process` is `nonisolated`.
    private func observeGateSignals() {
        let stream = faceQualityGate.signals()

        // Forward every camera frame to the gate. `faceQualityGate` is
        // `Sendable` and `process(sampleBuffer:cameraPosition:)` is
        // `nonisolated`, so this closure is safely `@Sendable` — it never
        // touches `@MainActor` state.
        let gate = faceQualityGate
        cameraSession.videoFrameHandler = { sampleBuffer in
            gate.process(sampleBuffer: sampleBuffer, cameraPosition: .front)
        }

        Task { [weak self] in
            for await signal in stream {
                self?.handle(signal: signal)
            }
        }
    }

    /// Apply one gate signal: update the live cue and the shutter-enabled state.
    ///
    /// Issue 1b: the gate stream no longer auto-fires the shutter. It drives the
    /// `.adjusting` ↔ `.readyToCapture` transition — the shutter is enabled only
    /// once the gate holds a steady `.pass` (the `SteadyHoldTracker` de-bounce).
    /// A non-`.pass` signal re-locks the shutter so a bad selfie cannot be shot.
    private func handle(signal: FaceGateSignal) {
        // While a capture is in flight (or already captured), gate signals are
        // ignored — the shutter state must not flip under the preview screen.
        guard !captureInFlight else { return }
        if case .captured = state { return }

        let gateHeld = steadyHold.update(
            signal: signal,
            at: Date().timeIntervalSinceReferenceDate
        )

        switch signal {
        case .noFace:
            state = .adjusting(nil)
        case let .adjust(reason):
            state = .adjusting(reason)
        case .pass:
            // The shutter unlocks only once the steady-hold de-bounce confirms
            // the `.pass` has held ~0.5s — a transient pass keeps it locked.
            state = gateHeld ? .readyToCapture : .adjusting(nil)
        }
    }

    // MARK: - Capture (manual shutter — Issue 1b / KYC-04 / Pitfall 5/6)

    /// Fire the shutter — invoked by the VC's shutter button (Issue 1b). Mirrors
    /// `VehicleCaptureViewModel.capture()`. A no-op unless the shutter is
    /// currently enabled (`.readyToCapture`) and no capture is already in flight,
    /// so a stray tap while the gate is failing cannot shoot a bad selfie.
    func capture() {
        guard !captureInFlight, state == .readyToCapture else { return }
        captureInFlight = true
        state = .capturing
        Task { [weak self] in
            await self?.performCapture()
        }
    }

    /// The capture path: read a fresh GPS fix (blocking capture if stale —
    /// Pitfall 5), capture the still, inject GPS straight from the
    /// `AVCapturePhoto` (Pitfall 6), and persist the bytes for `KYCUploader`.
    private func performCapture() async {
        // KYC-04 / Pitfall 5 — a stale/unavailable fix blocks capture.
        let location: CLLocation
        do {
            location = try await geoContext.freshLocation()
        } catch {
            logger.warn(event: LogEvent("kyc_face_capture_gps_stale"), fields: [:])
            captureInFlight = false
            steadyHold.reset()
            state = .locationUnavailable
            return
        }

        let photo: AVCapturePhoto
        do {
            photo = try await cameraSession.capturePhoto()
        } catch CameraSessionError.captureTimedOut {
            // The capture source is presumed dead (Test 10 gap — an ungraceful
            // force-quit tore down the `mediaserverd` connection). RECOVERABLE:
            // re-arm the shutter (`captureInFlight = false`), reset the
            // steady-hold de-bounce so the gate re-evaluates cleanly, and land
            // in `.captureUnavailable` — a shutter-recoverable state — instead
            // of the dead-shutter `.failed`.
            logger.warn(event: LogEvent("kyc_face_capture_timed_out"), fields: [:])
            captureInFlight = false
            steadyHold.reset()
            state = .captureUnavailable
            return
        } catch {
            logger.error(event: LogEvent("kyc_face_capture_failed"), fields: [:])
            captureInFlight = false
            steadyHold.reset()
            state = .failed(NSLocalizedString(
                "kyc.error.camera_unavailable",
                value: "The camera isn't available on this device.",
                comment: "KYC camera-unavailable error"
            ))
            return
        }

        // Pitfall 6 — GPS injected straight from the AVCapturePhoto. The bytes
        // never pass through a UIKit image decode/re-encode.
        guard let uploadData = gpsInjector.uploadData(from: photo, location: location) else {
            logger.error(event: LogEvent("kyc_face_capture_encode_failed"), fields: [:])
            captureInFlight = false
            steadyHold.reset()
            state = .failed(NSLocalizedString(
                "kyc.error.camera_unavailable",
                value: "The camera isn't available on this device.",
                comment: "KYC camera-unavailable error"
            ))
            return
        }

        persist(uploadData)

        // Render-only preview image for the D-07 Use/Retake screen. Decoded
        // from the photo's own file representation so EXIF orientation is
        // honoured and the still is shown right-side-up. This is a SEPARATE,
        // display-only path — `uploadData` above already carries the upload
        // bytes straight from the `AVCapturePhoto` (Pitfall 6); this decode
        // never feeds the upload.
        capturedPreviewImage = previewImage(from: photo)

        state = .captured
    }

    /// Decode a render-only `UIImage` from the captured photo for the D-07
    /// preview. Uses `fileDataRepresentation()` so the EXIF orientation tag is
    /// applied — the still is shown upright, not rotated. Display-only; never
    /// the upload byte source (Pitfall 6).
    private func previewImage(from photo: AVCapturePhoto) -> UIImage? {
        guard let data = photo.fileDataRepresentation() else { return nil }
        return UIImage(data: data)
    }

    #if DEBUG
    /// Test-only seam (Test 10 gap simulator suite). Drives the VM into
    /// `.readyToCapture` so `capture()` — which is guarded on that state — can
    /// fire WITHOUT a live Vision frame stream (`isCameraAvailable` is false on
    /// the simulator, so `observeGateSignals()` never runs there). DEBUG-only:
    /// it never compiles into a Release build, exactly like the DevMenu seams.
    func forceReadyToCaptureForTest() {
        state = .readyToCapture
    }
    #endif

    /// Write the captured face bytes into the on-disk KYC session so plan 04's
    /// `KYCUploader` can pick them up for the pipelined upload (D-01).
    ///
    /// Uses the store's atomic `withSession` read-modify-write. A bare
    /// `loadSession()` then `persist()` (two separate store calls) would race
    /// the `KYCUploader` actor's concurrent load->mutate->persist and silently
    /// drop this capture or an upload-state mutation (debug:
    /// kyc-session-store-data-race).
    private func persist(_ data: Data) {
        do {
            try sessionStore.withSession { session in
                session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = data
            }
        } catch {
            logger.error(event: LogEvent("kyc_face_capture_persist_failed"), fields: [:])
        }
    }
}
