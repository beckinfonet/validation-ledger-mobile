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
}

// MARK: - Live AVFoundation implementation

/// The live `CameraSession` over `AVCaptureSession` + `AVCapturePhotoOutput`.
///
/// Not simulator-testable — `isCameraAvailable` returns false there so the
/// capture VCs branch away. The continuation-bridged still-capture delegate
/// follows the `LocationProvider` pattern.
@MainActor
public final class AVFoundationCameraSession: NSObject, CameraSession,
                                              AVCapturePhotoCaptureDelegate {

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
        guard Self.isCameraAvailable else {
            throw CameraSessionError.cameraUnavailable
        }

        // Resolve authorization FIRST. An AVCaptureSession configured + started
        // before the camera-permission grant resolves never receives the
        // camera feed — the preview stays black even after the user taps
        // "Allow". `requestPermission()` prompts on `.notDetermined` and
        // returns only once the user has decided.
        let status = await requestPermission()
        guard status == .authorized else {
            throw CameraSessionError.permissionDenied
        }

        // Configure inputs, then start — both on the session queue, off the
        // main thread (`startRunning()` is blocking).
        try configureSessionInputs(position: position)
        start()
    }

    public nonisolated func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
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
        try sessionQueue.sync { [session, photoOutput] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove any existing inputs before (re)configuring.
            for input in session.inputs {
                session.removeInput(input)
            }
            let device = try Self.captureDevice(for: position)
            guard let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                throw CameraSessionError.configurationFailed
            }
            session.addInput(input)

            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
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
            throw CameraSessionError.cameraUnavailable
        }
        return device
    }
}
