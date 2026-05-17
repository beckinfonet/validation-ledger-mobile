// validationLedger/Core/Identity/Capture/CameraSession.swift
// Phase 5 Plan 03 — KYC-02 / KYC-04: the AVCaptureSession lifecycle wrapper.
//
// `CameraSession` is a `public protocol` over `AVCaptureSession` lifecycle —
// configure, start, stop, switch front/back device, capture a still photo,
// expose the preview layer. The live `AVFoundationCameraSession` Default impl
// uses the continuation-bridged-delegate pattern copied from
// `Core/Identity/Geo/LocationProvider.swift` (a `public protocol` + a
// `public final class Default…: NSObject, …Delegate` that bridges delegate
// callbacks via `CheckedContinuation`, with `@MainActor` public methods and
// `nonisolated` delegate callbacks hopping back via `Task { @MainActor … }`).
//
// === SIMULATOR GATE (RESEARCH Pitfall 1) ===
// `AVCaptureSession` produces no real frames on the simulator. `isCameraAvailable`
// is a static gate the capture VCs (plan 05) branch on so the simulator never
// instantiates a live capture session. The live `AVCaptureSession` body comes
// from RESEARCH Pattern 1 — it is NOT simulator-testable; keeping it behind this
// protocol keeps plan 05's VCs and plan 04's pipeline testable.

import AVFoundation
import Foundation
import OSLog

// MARK: - Camera-path diagnostic log

/// Dedicated OSLog channel for KYC camera-path diagnosis (debug session
/// `front-camera-preview-black`). Every line carries the `kyc_camera` prefix so
/// the on-device console can be filtered with a single grep token. This is
/// deliberately a standalone `os.Logger` (not the injected `Logger`) so the
/// instrumentation needs no DI plumbing through `AVFoundationCameraSession()`'s
/// zero-arg construction. Carries no PII — only AVFoundation/layout facts.
let kycCameraLog = os.Logger(
    subsystem: LoggingSubsystem.identity,
    category: "camera"
)

// MARK: - Error surface

/// Failures surfaced by a `CameraSession`.
public enum CameraSessionError: Error, Sendable {
    /// No camera hardware is available (e.g. the simulator) — `isCameraAvailable`
    /// is false. Callers should branch before constructing a live session.
    case cameraUnavailable
    /// Camera authorization is denied/restricted — the user must grant it in Settings.
    case permissionDenied
    /// The capture session could not be configured (no usable capture device/input).
    case configurationFailed
    /// A still-photo capture failed.
    case captureFailed(Error)
}

/// Which camera the session is bound to.
public enum CameraPosition: Sendable {
    case front
    case back
}

// MARK: - Protocol

/// An `AVCaptureSession` lifecycle wrapper behind a protocol so the live
/// capture surface is swappable and the consuming VCs/pipeline stay testable.
public protocol CameraSession: AnyObject {
    /// Request camera authorization, prompting the first time.
    @MainActor func requestPermission() async -> AVAuthorizationStatus

    /// Configure the session for the given camera position. Throws
    /// `CameraSessionError.cameraUnavailable` on hardware without a camera.
    @MainActor func configure(position: CameraPosition) throws

    /// Resolve camera authorization, then (only if granted) configure the
    /// session for `position` and start it running.
    ///
    /// This is the correct entry point for the capture screens: an
    /// `AVCaptureSession` started BEFORE the camera-permission grant resolves
    /// never receives the camera feed — the preview stays black even after the
    /// user taps "Allow". Awaiting `requestPermission()` here guarantees the
    /// session is configured + started only once authorization is resolved.
    ///
    /// Throws `CameraSessionError.permissionDenied` when authorization is
    /// denied/restricted, `.cameraUnavailable` on hardware with no camera, or
    /// `.configurationFailed` if the front/back input cannot be added.
    @MainActor func startAuthorizedSession(position: CameraPosition) async throws

    /// Start the capture session running.
    @MainActor func start()

    /// Stop the capture session.
    @MainActor func stop()

    /// Switch between the front and back camera.
    @MainActor func switchCamera(to position: CameraPosition) throws

    /// Capture a single still photo, returning the `AVCapturePhoto` so the
    /// caller can run it through `GPSMetadataInjector.uploadData(from:location:)`.
    @MainActor func capturePhoto() async throws -> AVCapturePhoto

    /// The preview layer for on-screen display. Distinct from the upload path —
    /// the preview is render-only and is never the upload byte source.
    @MainActor var previewLayer: AVCaptureVideoPreviewLayer { get }

    /// A live video-frame sink (KYC-02 / D-04). When non-`nil`, the session
    /// delivers every `CMSampleBuffer` from its `AVCaptureVideoDataOutput` to
    /// this closure on a background queue — this is what feeds the Vision
    /// `FaceQualityGate` for the face-capture auto-fire. Render/analysis only;
    /// never the upload byte source (the upload path is `capturePhoto()` —
    /// RESEARCH Pitfall 6).
    ///
    /// `@Sendable` because the closure is invoked from the video-data-output's
    /// serial delegate queue, not the main actor.
    @MainActor var videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)? { get set }
}

// MARK: - Live AVFoundation implementation

/// The live `CameraSession` over `AVCaptureSession` + `AVCapturePhotoOutput`.
///
/// Not simulator-testable — `isCameraAvailable` returns false there so the
/// capture VCs branch away. The continuation-bridged still-capture delegate
/// follows the `LocationProvider` pattern.
@MainActor
public final class AVFoundationCameraSession: NSObject, CameraSession,
                                              AVCapturePhotoCaptureDelegate,
                                              AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Hardware availability gate (RESEARCH Pitfall 1). False on the simulator
    /// and on any device with no usable capture device — the capture VCs check
    /// this before constructing a live session. `nonisolated` so a caller on
    /// any actor (and the simulator test) can branch on it without a hop.
    public nonisolated static var isCameraAvailable: Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return !discovery.devices.isEmpty
    }

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    /// The live-frame output (KYC-02 / D-04). Added to the session alongside
    /// `photoOutput` so the Vision `FaceQualityGate` has a `CMSampleBuffer`
    /// stream to consume. The face-capture screen needs this; the plain-photo
    /// (DL-back / truck / trailer / plate) screens do not — but it is harmless
    /// there: with no `videoFrameHandler` set the delegate callback drops every
    /// buffer, and `alwaysDiscardsLateVideoFrames` keeps the queue shallow.
    private let videoDataOutput = AVCaptureVideoDataOutput()

    /// Dedicated SERIAL queue for the `AVCaptureVideoDataOutput` sample-buffer
    /// delegate callbacks (KYC-02 / D-04). Separate from `sessionQueue` so frame
    /// delivery never contends with `startRunning()`/configuration work. The
    /// delegate callback (`captureOutput(_:didOutput:from:)`) is `nonisolated`
    /// and runs here, hopping nothing onto the main actor — it just forwards the
    /// buffer to `videoFrameHandler`, mirroring the `LocationProvider` pattern.
    private let videoFrameQueue = DispatchQueue(
        label: "com.maldin.validationLedger.camera.frames"
    )

    /// Background-queue lock guarding `_videoFrameHandler` — the handler is SET
    /// on the main actor (`videoFrameHandler` setter) and READ on
    /// `videoFrameQueue` (the delegate callback). The lock keeps that
    /// cross-thread access safe without making the whole class lose its
    /// `@MainActor` isolation.
    private let videoFrameHandlerLock = NSLock()
    private nonisolated(unsafe) var _videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)?

    /// A live video-frame sink (KYC-02 / D-04). See the protocol doc. The
    /// face-capture VM sets this to forward each buffer to the Vision gate.
    public var videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)? {
        get {
            videoFrameHandlerLock.lock()
            defer { videoFrameHandlerLock.unlock() }
            return _videoFrameHandler
        }
        set {
            videoFrameHandlerLock.lock()
            _videoFrameHandler = newValue
            videoFrameHandlerLock.unlock()
        }
    }

    private lazy var _previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    /// Dedicated serial queue for `AVCaptureSession` lifecycle work.
    ///
    /// `beginConfiguration`/`commitConfiguration` and especially
    /// `startRunning()` are blocking calls that Apple documents MUST NOT run on
    /// the main thread (`startRunning()` blocks until the session has started —
    /// on the main thread it stalls the UI and the camera pipeline). All session
    /// mutation hops onto this queue; the `@MainActor` API surface stays
    /// unchanged for callers.
    private let sessionQueue = DispatchQueue(label: "com.maldin.validationLedger.camera.session")

    /// Bridges the single `AVCapturePhotoCaptureDelegate` callback into the
    /// `capturePhoto()` async result — the `LocationProvider` continuation pattern.
    private var captureContinuation: CheckedContinuation<AVCapturePhoto, Error>?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .notDetermined else { return status }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    public func configure(position: CameraPosition) throws {
        guard Self.isCameraAvailable else {
            throw CameraSessionError.cameraUnavailable
        }
        try configureSessionInputs(position: position)
    }

    public func startAuthorizedSession(position: CameraPosition) async throws {
        kycCameraLog.info("kyc_camera event=start_authorized_session.begin position=\(position == .front ? "front" : "back", privacy: .public)")
        guard Self.isCameraAvailable else {
            kycCameraLog.error("kyc_camera event=start_authorized_session.camera_unavailable")
            throw CameraSessionError.cameraUnavailable
        }

        // Resolve authorization FIRST. An AVCaptureSession configured + started
        // before the camera-permission grant resolves never receives the
        // camera feed — the preview stays black even after the user taps
        // "Allow". `requestPermission()` prompts on `.notDetermined` and
        // returns only once the user has decided.
        let status = await requestPermission()
        kycCameraLog.info("kyc_camera event=permission_resolved status=\(String(describing: status), privacy: .public)")
        guard status == .authorized else {
            kycCameraLog.error("kyc_camera event=start_authorized_session.permission_denied")
            throw CameraSessionError.permissionDenied
        }

        // Configure inputs, then start — both on the session queue, off the
        // main thread (`startRunning()` is blocking).
        do {
            try configureSessionInputs(position: position)
        } catch {
            kycCameraLog.error("kyc_camera event=configure_inputs.failed error=\(String(describing: error), privacy: .public)")
            throw error
        }
        start()
        kycCameraLog.info("kyc_camera event=start_authorized_session.end")
    }

    public nonisolated func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else {
                kycCameraLog.info("kyc_camera event=session_start.already_running")
                return
            }
            kycCameraLog.info("kyc_camera event=session_start.calling_startRunning inputs=\(session.inputs.count, privacy: .public) outputs=\(session.outputs.count, privacy: .public)")
            session.startRunning()
            kycCameraLog.info("kyc_camera event=session_start.after_startRunning isRunning=\(session.isRunning, privacy: .public)")
        }
    }

    public nonisolated func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    public func switchCamera(to position: CameraPosition) throws {
        try configureSessionInputs(position: position)
    }

    /// Configure the session's camera input + photo output for `position`.
    ///
    /// Runs synchronously on `sessionQueue` (off the main thread —
    /// `beginConfiguration`/`commitConfiguration` are blocking) and rethrows
    /// any `CameraSessionError` raised inside the configuration block to the
    /// caller. `nonisolated` because it touches no `@MainActor` state — only
    /// the thread-safe `AVCaptureSession`/`AVCapturePhotoOutput`, whose access
    /// `sessionQueue` serializes.
    private nonisolated func configureSessionInputs(position: CameraPosition) throws {
        try sessionQueue.sync { [session, photoOutput, videoDataOutput, videoFrameQueue] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove any existing inputs before (re)configuring.
            for input in session.inputs {
                session.removeInput(input)
            }
            let device = try Self.captureDevice(for: position)
            kycCameraLog.info("kyc_camera event=device_discovered name=\(device.localizedName, privacy: .public) position=\(device.position.rawValue, privacy: .public)")
            guard let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                kycCameraLog.error("kyc_camera event=input_creation.failed name=\(device.localizedName, privacy: .public)")
                throw CameraSessionError.configurationFailed
            }
            session.addInput(input)
            kycCameraLog.info("kyc_camera event=input_added inputs=\(session.inputs.count, privacy: .public)")

            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            // KYC-02 / D-04: the live-frame output. The Vision `FaceQualityGate`
            // needs a `CMSampleBuffer` stream — the lone `AVCapturePhotoOutput`
            // never produced one, so the face-capture auto-fire never received
            // frames (debug session `front-camera-preview-black`, round 5 / Bug
            // B). Attach the video-data-output and point its serial delegate
            // queue at `self`; `alwaysDiscardsLateVideoFrames` keeps face
            // detection working on the freshest frame instead of backlogging.
            if !session.outputs.contains(videoDataOutput), session.canAddOutput(videoDataOutput) {
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                videoDataOutput.setSampleBufferDelegate(self, queue: videoFrameQueue)
                session.addOutput(videoDataOutput)
                kycCameraLog.info("kyc_camera event=video_data_output_wired hasConnection=\(videoDataOutput.connection(with: .video) != nil, privacy: .public)")
            }
            kycCameraLog.info("kyc_camera event=configure_inputs.committed inputs=\(session.inputs.count, privacy: .public) outputs=\(session.outputs.count, privacy: .public)")
        }
    }

    public func capturePhoto() async throws -> AVCapturePhoto {
        guard Self.isCameraAvailable else {
            throw CameraSessionError.cameraUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    public var previewLayer: AVCaptureVideoPreviewLayer { _previewLayer }

    // MARK: - AVCapturePhotoCaptureDelegate

    public nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.captureContinuation?.resume(
                    throwing: CameraSessionError.captureFailed(error)
                )
            } else {
                self.captureContinuation?.resume(returning: photo)
            }
            self.captureContinuation = nil
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Live-frame delegate callback (KYC-02 / D-04). Runs on `videoFrameQueue`
    /// (a serial background queue) — `nonisolated`, never hops onto the main
    /// actor. Forwards each `CMSampleBuffer` to `videoFrameHandler`, which the
    /// face-capture VM wires to `VisionFaceQualityGate.process(sampleBuffer:)`.
    /// When no handler is set (the plain-photo screens) every buffer is dropped.
    public nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        videoFrameHandlerLock.lock()
        let handler = _videoFrameHandler
        videoFrameHandlerLock.unlock()
        handler?(sampleBuffer)
    }

    // MARK: - Helpers

    /// Resolve the `.builtInWideAngleCamera` for `position`. `static nonisolated`
    /// so it can run inside the `sessionQueue` configuration block — it touches
    /// no instance or `@MainActor` state.
    private nonisolated static func captureDevice(
        for position: CameraPosition
    ) throws -> AVCaptureDevice {
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: avPosition
        )
        guard let device = discovery.devices.first else {
            kycCameraLog.error("kyc_camera event=device_discovery.empty position=\(avPosition.rawValue, privacy: .public) — no .builtInWideAngleCamera found")
            throw CameraSessionError.cameraUnavailable
        }
        return device
    }
}
