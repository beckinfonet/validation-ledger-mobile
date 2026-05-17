// validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewModel.swift
// Phase 5 Plan 05 — KYC-04 / D-06: the plain-photo capture view model.
//
// Drives the still-capture path shared by the DL-back (D-06 — a plain framed
// photo, no PDF417/AAMVA barcode scan) and the three vehicle artifacts (truck /
// trailer / plate — KYC-04). Parameterized by `ArtifactType` so one VM + one VC
// serve all four plain-photo screens.
//
// VM contract copied from `OTPViewModel` (initializer DI — ARCH-04, callbacks,
// no Combine). The capture path is the SAME as `FaceCaptureViewModel`'s: read a
// fresh GPS fix (blocking capture if stale — Pitfall 5), capture the still,
// inject GPS straight from the `AVCapturePhoto` (Pitfall 6 — never a UIKit image
// decode), persist the bytes for `KYCUploader` (D-01).

import AVFoundation
import CoreLocation
import Foundation
import UIKit

/// Drives a plain-photo capture screen (DL-back / truck / trailer / plate).
@MainActor
final class VehicleCaptureViewModel {

    // MARK: - State

    /// The plain-photo capture screen's UI state.
    enum State: Equatable, Sendable {
        /// Idle — the shutter is armed.
        case ready
        /// A still-photo capture is in flight.
        case capturing
        /// Capture is blocked because the GPS fix is stale/unavailable (Pitfall 5).
        case locationUnavailable
        /// The shot is captured — the preview screen is presented.
        case captured
        /// A non-recoverable capture failure.
        case failed(String)
    }

    private(set) var state: State = .ready {
        didSet { onStateChange?(state) }
    }

    /// A render-only `UIImage` of the just-captured shot, for the D-07
    /// Use/Retake preview screen. Decoded from the `AVCapturePhoto` purely to
    /// be SHOWN — this is NOT the upload byte source. The upload `Data` is
    /// produced separately via `GPSMetadataInjector.uploadData(from:location:)`
    /// straight from the `AVCapturePhoto` (Pitfall 6 — the GPS-EXIF trust
    /// boundary), and never passes through this UIKit decode.
    private(set) var capturedPreviewImage: UIImage?

    // MARK: - Callbacks

    var onStateChange: ((State) -> Void)?

    /// Fired once the user confirms the still preview ("Use photo" — D-07).
    var onCaptureConfirmed: (() -> Void)?

    // MARK: - Dependencies (initializer DI — ARCH-04)

    /// The artifact this screen captures — drives the instruction header copy
    /// and the persistence key.
    let artifactType: KYCUploadInitEndpoint.ArtifactType

    private let cameraSession: any CameraSession
    private let geoContext: GeoContext
    private let gpsInjector: GPSMetadataInjector
    private let sessionStore: KYCSessionStore
    private let logger: any Logger

    private var captureInFlight = false

    init(
        artifactType: KYCUploadInitEndpoint.ArtifactType,
        cameraSession: any CameraSession,
        geoContext: GeoContext,
        gpsInjector: GPSMetadataInjector,
        sessionStore: KYCSessionStore,
        logger: any Logger
    ) {
        self.artifactType = artifactType
        self.cameraSession = cameraSession
        self.geoContext = geoContext
        self.gpsInjector = gpsInjector
        self.sessionStore = sessionStore
        self.logger = logger
    }

    /// The camera preview layer for the VC to host. Render-only (Pitfall 6).
    var previewLayer: AVCaptureVideoPreviewLayer {
        cameraSession.previewLayer
    }

    /// The live `AVCaptureSession` for the VC's `CameraPreviewView` backing
    /// layer (debug session `front-camera-preview-black`, round 4). Read off
    /// the session's own preview layer so there is exactly ONE session instance
    /// (the one `start()`/`stop()`/`capture()` act on). Render-only.
    var captureSession: AVCaptureSession? {
        cameraSession.previewLayer.session
    }

    /// The instruction header copy for this artifact (UI-SPEC capture cues).
    var instructionText: String {
        switch artifactType {
        case .dlBack:
            return NSLocalizedString(
                "kyc.dlback.instruction",
                value: "Photograph the back of your license.",
                comment: "DL-back capture instruction header (D-06)"
            )
        case .truck:
            return NSLocalizedString(
                "kyc.truck.instruction",
                value: "Take a photo of the truck.",
                comment: "Truck capture instruction header"
            )
        case .trailer:
            return NSLocalizedString(
                "kyc.trailer.instruction",
                value: "Take a photo of the trailer.",
                comment: "Trailer capture instruction header"
            )
        case .plate:
            return NSLocalizedString(
                "kyc.plate.instruction",
                value: "Take a photo of the license plate.",
                comment: "License-plate capture instruction header"
            )
        case .face, .dlFront:
            // Face / DL-front have their own dedicated screens — this VM is
            // only constructed for the four plain-photo artifacts.
            return ""
        }
    }

    // MARK: - Lifecycle

    /// Start the (back) camera. No-ops the live session on the simulator
    /// (RESEARCH Pitfall 1).
    ///
    /// The session start is routed through `startAuthorizedSession` so camera
    /// authorization is resolved BEFORE the `AVCaptureSession` is configured +
    /// started. A session started before the permission grant resolves never
    /// receives the camera feed — the preview would stay black even after the
    /// user grants access. Awaiting the permission resolution closes that race.
    func start() {
        guard AVFoundationCameraSession.isCameraAvailable else {
            logger.info(event: LogEvent("kyc_vehicle_capture_no_camera"),
                        fields: [.event: artifactType.rawValue])
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cameraSession.startAuthorizedSession(position: .back)
                self.state = .ready
            } catch CameraSessionError.permissionDenied {
                self.logger.warn(
                    event: LogEvent("kyc_vehicle_capture_permission_denied"),
                    fields: [.event: self.artifactType.rawValue]
                )
                self.state = .failed(NSLocalizedString(
                    "kyc.error.camera_permission",
                    value: "Camera access is needed to verify your identity. Turn it on in Settings.",
                    comment: "KYC camera-permission-denied capture error"
                ))
            } catch {
                self.state = .failed(NSLocalizedString(
                    "kyc.error.camera_unavailable",
                    value: "The camera isn't available on this device.",
                    comment: "KYC camera-unavailable error"
                ))
            }
        }
    }

    func stop() {
        cameraSession.stop()
    }

    func resetForRetake() {
        captureInFlight = false
        capturedPreviewImage = nil
        state = .ready
    }

    func confirmCapture() {
        onCaptureConfirmed?()
    }

    // MARK: - Capture (KYC-04 / Pitfall 5/6)

    /// Fire the shutter — invoked by the VC's shutter button.
    func capture() {
        guard !captureInFlight else { return }
        captureInFlight = true
        state = .capturing
        Task { [weak self] in
            await self?.performCapture()
        }
    }

    private func performCapture() async {
        // KYC-04 / Pitfall 5 — a stale/unavailable fix blocks capture.
        let location: CLLocation
        do {
            location = try await geoContext.freshLocation()
        } catch {
            logger.warn(event: LogEvent("kyc_vehicle_capture_gps_stale"),
                        fields: [.event: artifactType.rawValue])
            captureInFlight = false
            state = .locationUnavailable
            return
        }

        let photo: AVCapturePhoto
        do {
            photo = try await cameraSession.capturePhoto()
        } catch {
            logger.error(event: LogEvent("kyc_vehicle_capture_failed"),
                         fields: [.event: artifactType.rawValue])
            captureInFlight = false
            state = .failed(NSLocalizedString(
                "kyc.error.camera_unavailable",
                value: "The camera isn't available on this device.",
                comment: "KYC camera-unavailable error"
            ))
            return
        }

        // Pitfall 6 — GPS injected straight from the AVCapturePhoto.
        guard let uploadData = gpsInjector.uploadData(from: photo, location: location) else {
            logger.error(event: LogEvent("kyc_vehicle_capture_encode_failed"),
                         fields: [.event: artifactType.rawValue])
            captureInFlight = false
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

    /// Write the captured bytes into the on-disk KYC session for `KYCUploader`.
    private func persist(_ data: Data) {
        do {
            var session = (try sessionStore.loadSession()) ?? KYCSession()
            session.artifactData[artifactType.rawValue] = data
            try sessionStore.persist(session)
        } catch {
            logger.error(event: LogEvent("kyc_vehicle_capture_persist_failed"),
                         fields: [.event: artifactType.rawValue])
        }
    }
}
