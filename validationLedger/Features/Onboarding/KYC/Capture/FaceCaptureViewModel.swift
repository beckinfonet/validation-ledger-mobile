// validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift
// Phase 5 Plan 05 — KYC-02 / D-04: the face-capture view model.
//
// VM contract copied from `OTPViewModel` — `@MainActor final class`, a nested
// `State: Equatable, Sendable`, a `state` `didSet` firing `onStateChange`,
// `on…: ((…) -> Void)?` callbacks, and initializer DI (ARCH-04).
//
// D-04: the photo auto-fires when the Vision quality gate (plan 03
// `FaceQualityGate` / `SteadyHoldTracker`) holds `.pass` steady ~0.5s. The
// live gate-signal stream is a device-only surface (RESEARCH Pitfall 1) — the
// VM consumes the protocol; the SteadyHoldTracker decision logic is pure.
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

/// Drives the face-capture screen: the live quality-gate stream, the D-04
/// steady-hold auto-fire, the capture-time GPS injection, and persistence of the
/// captured bytes into the KYC session.
@MainActor
final class FaceCaptureViewModel {

    // MARK: - State

    /// The capture screen's UI state.
    enum State: Equatable, Sendable {
        /// Waiting for the quality gate — `reason` drives the live inline cue.
        case adjusting(FaceAdjustReason?)
        /// The gate passes and is holding steady (~0.5s) — the "Hold still" cue.
        case holding
        /// A still-photo capture is in flight.
        case capturing
        /// Capture is blocked because the GPS fix is stale/unavailable (Pitfall 5).
        case locationUnavailable
        /// The shot is captured — the preview screen is presented.
        case captured
        /// A non-recoverable capture failure.
        case failed(String)
    }

    private(set) var state: State = .adjusting(nil) {
        didSet { onStateChange?(state) }
    }

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

    /// The D-04 auto-fire trigger — `.pass` must hold ~0.5s before the shutter
    /// fires. Pure value type; exercised in plan 03's `FaceQualityGateTests`.
    private var steadyHold = SteadyHoldTracker()

    /// `true` once a capture has fired — guards against a double auto-fire while
    /// the still-capture is in flight.
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

    /// Stop the camera + the signal stream.
    func stop() {
        faceQualityGate.stop()
        cameraSession.stop()
    }

    /// Reset the screen for a Retake (D-07) — clears the steady-hold run.
    func resetForRetake() {
        steadyHold.reset()
        captureInFlight = false
        state = .adjusting(nil)
    }

    /// Confirm the still preview ("Use photo" — D-07). Bubbles to the coordinator.
    func confirmCapture() {
        onCaptureConfirmed?()
    }

    // MARK: - Quality-gate stream → D-04 auto-fire

    private func observeGateSignals() {
        let stream = faceQualityGate.signals()
        Task { [weak self] in
            for await signal in stream {
                self?.handle(signal: signal)
            }
        }
    }

    /// Apply one gate signal: update the live cue, and on a steady `.pass` hold
    /// auto-fire the shutter (D-04).
    private func handle(signal: FaceGateSignal) {
        guard !captureInFlight else { return }

        let readyToFire = steadyHold.update(
            signal: signal,
            at: Date().timeIntervalSinceReferenceDate
        )

        switch signal {
        case .noFace:
            state = .adjusting(nil)
        case let .adjust(reason):
            state = .adjusting(reason)
        case .pass:
            state = .holding
            if readyToFire {
                fireCapture()
            }
        }
    }

    // MARK: - Capture (KYC-04 / Pitfall 5/6)

    private func fireCapture() {
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
        state = .captured
    }

    /// Write the captured face bytes into the on-disk KYC session so plan 04's
    /// `KYCUploader` can pick them up for the pipelined upload (D-01).
    private func persist(_ data: Data) {
        do {
            var session = (try sessionStore.loadSession()) ?? KYCSession()
            session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = data
            try sessionStore.persist(session)
        } catch {
            logger.error(event: LogEvent("kyc_face_capture_persist_failed"), fields: [:])
        }
    }
}
