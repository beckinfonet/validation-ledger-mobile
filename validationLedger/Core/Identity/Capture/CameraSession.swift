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
import UIKit

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
    /// A still-photo capture did not complete within the timeout — the capture
    /// source is presumed dead (e.g. after an ungraceful force-quit tore down
    /// the `mediaserverd` connection). The caller should surface a RECOVERABLE
    /// error and may rebuild the session. Distinct from `captureFailed`: the
    /// delegate never fired at all, rather than firing with an error.
    case captureTimedOut
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

    /// The timeout task racing the delegate callback for `capturePhoto()`. When
    /// the delegate resumes the continuation first it cancels this task so the
    /// timeout cannot fire afterwards; when the timeout fires first it resumes
    /// the continuation itself. `nil` while no capture is in flight.
    private var captureTimeoutTask: Task<Void, Never>?

    /// How long `capturePhoto()` waits for the photo-output delegate before it
    /// declares the capture source dead. Long enough that a slow-but-healthy
    /// capture is never mis-flagged; short enough that the user is not left
    /// staring at a dead shutter after an ungraceful force-quit (Test 10 gap).
    private static let captureTimeout: Duration = .seconds(5)

    /// The camera position the session is currently configured for. Set by
    /// `configureSessionInputs`/`startAuthorizedSession`; read by the
    /// runtime-error rebuild and the foreground restart so they restore the
    /// right camera. `nil` until the session has been configured once.
    private var currentPosition: CameraPosition?

    /// Whether the session is INTENDED to be running — set `true` by `start()`,
    /// `false` by `stop()`. The background-stop / foreground-restart and the
    /// interruption-end restart consult this so they only restore a session the
    /// caller actually wanted running, never one a VC had already stopped.
    private var intendedRunning = false

    /// `NotificationCenter` observer tokens for the runtime-error / interruption
    /// / app-lifecycle observers. Removed in `deinit` so no callback fires after
    /// the session is torn down and the array does not leak.
    private var observerTokens: [NSObjectProtocol] = []

    public override init() {
        super.init()
        registerLifecycleObservers()
    }

    deinit {
        // `deinit` is nonisolated — only touch the tokens array, which is safe
        // to read here (no other actor can mutate it once the object is being
        // deallocated). Removing the observers prevents any post-teardown callback.
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
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
        currentPosition = position
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
        currentPosition = position
        start()
        kycCameraLog.info("kyc_camera event=start_authorized_session.end")
    }

    public func start() {
        // Record the caller's INTENT before the blocking work hops to the
        // session queue — the background-stop / foreground-restart and the
        // interruption-end restart consult `intendedRunning` to know whether to
        // restore the session. Setting it on the main actor keeps it a single,
        // race-free source of truth.
        intendedRunning = true
        startSession()
    }

    public func stop() {
        // An EXPLICIT caller stop (a VC's `viewWillDisappear`) — the session is
        // no longer intended running, so a later foreground will NOT restart it.
        intendedRunning = false
        stopSession()
    }

    /// Start the `AVCaptureSession` running. The blocking `startRunning()` hops
    /// onto `sessionQueue` (Apple documents it MUST NOT run on the main thread).
    /// Does NOT touch `intendedRunning` — the runtime-error rebuild and the
    /// foreground/interruption-end restart call this to restore a session whose
    /// intent is already recorded.
    private func startSession() {
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

    /// Stop the `AVCaptureSession`. Does NOT touch `intendedRunning` — the
    /// background-stop observer calls this so a backgrounded session is torn
    /// down (the force-quit mitigation) while the intent to run survives, so the
    /// next foreground transition restores it.
    private func stopSession() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    public func switchCamera(to position: CameraPosition) throws {
        try configureSessionInputs(position: position)
        currentPosition = position
    }

    // MARK: - Runtime-error / interruption / app-lifecycle resilience (Test 10 gap)

    /// Register the `AVCaptureSession` runtime-error / interruption observers
    /// and the `UIApplication` background/foreground observers.
    ///
    /// Test 10 gap (`.planning/debug/kyc-force-quit-camera-stuck.md`): before
    /// this, `AVFoundationCameraSession` registered ZERO observers and bound
    /// session start/stop only to VC view lifecycle. An ungraceful force-quit
    /// skips `viewWillDisappear`, the prior session is never `stopRunning()`-ed,
    /// the `mediaserverd` capture-source connection is torn down abruptly, and
    /// the relaunched session can fail to re-establish a live source. These
    /// observers make the session self-heal: rebuild on a runtime error, and
    /// stop/restart cleanly across background/foreground.
    ///
    /// Notification callbacks fire on arbitrary threads — every closure hops to
    /// the main actor (the established `photoOutput` delegate pattern) before
    /// touching `@MainActor` state. Tokens are stored for `deinit` removal.
    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        // AVCaptureSession.runtimeErrorNotification — the dead-source signal.
        // After an ungraceful force-quit the `mediaserverd` connection is gone
        // (`FigCaptureSourceRemote err=-17281`). NOTE: a bare `err=-17281` on a
        // CLEAN launch is benign (the `front-camera-preview-black` round-4
        // note) — but a runtime-error notification AFTER startup is a real
        // dead-source signal, so rebuild the session here.
        observerTokens.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] note in
                let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code.rawValue
                Task { @MainActor [weak self] in
                    self?.handleRuntimeError(code: code)
                }
            }
        )

        // App background — stop the session. The prior process's session must
        // not be left running across background; a backgrounded-then-killed app
        // has already cleanly stopped. `intendedRunning` is PRESERVED so the
        // foreground transition can restore it.
        observerTokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleDidEnterBackground()
                }
            }
        )

        // App foreground — restart a session that was intended-running before
        // backgrounding. Re-run `configureSessionInputs` first (safe to always
        // do) in case a runtime error fired while backgrounded.
        observerTokens.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWillEnterForeground()
                }
            }
        )

        // Session interruption (a phone call, another app taking the camera).
        observerTokens.append(
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { _ in
                Task { @MainActor in
                    kycCameraLog.info("kyc_camera event=session.was_interrupted")
                }
            }
        )

        // Interruption ended — restart if the session was intended-running.
        observerTokens.append(
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleInterruptionEnded()
                }
            }
        )
    }

    /// `runtimeErrorNotification` handler — rebuild the (presumed-dead) session.
    private func handleRuntimeError(code: Int?) {
        kycCameraLog.error("kyc_camera event=runtime_error error_code=\(code ?? 0, privacy: .public) — rebuilding session")
        // Rebuild only when a position was previously configured — there is
        // nothing to restore before the first `configure`/`startAuthorizedSession`.
        guard let position = currentPosition else {
            kycCameraLog.info("kyc_camera event=runtime_error.no_position — nothing to rebuild")
            return
        }
        do {
            try configureSessionInputs(position: position)
        } catch {
            kycCameraLog.error("kyc_camera event=runtime_error.rebuild_failed error=\(String(describing: error), privacy: .public)")
            return
        }
        // Restart only if the caller wanted the session running.
        if intendedRunning {
            startSession()
        }
    }

    /// `didEnterBackgroundNotification` handler — stop the session, preserving
    /// the intent so the foreground transition can restore it.
    private func handleDidEnterBackground() {
        kycCameraLog.info("kyc_camera event=app.did_enter_background intendedRunning=\(self.intendedRunning, privacy: .public) — stopping session")
        stopSession()
    }

    /// `willEnterForegroundNotification` handler — restart a session that was
    /// intended-running before backgrounding.
    private func handleWillEnterForeground() {
        guard intendedRunning, let position = currentPosition else {
            kycCameraLog.info("kyc_camera event=app.will_enter_foreground.no_restore intendedRunning=\(self.intendedRunning, privacy: .public)")
            return
        }
        kycCameraLog.info("kyc_camera event=app.will_enter_foreground — restoring session")
        // Always re-run config before start: a runtime error may have fired
        // while backgrounded, leaving the session with a dead input.
        do {
            try configureSessionInputs(position: position)
        } catch {
            kycCameraLog.error("kyc_camera event=app.will_enter_foreground.reconfigure_failed error=\(String(describing: error), privacy: .public)")
            return
        }
        startSession()
    }

    /// `interruptionEndedNotification` handler — restart if intended-running.
    private func handleInterruptionEnded() {
        kycCameraLog.info("kyc_camera event=session.interruption_ended intendedRunning=\(self.intendedRunning, privacy: .public)")
        if intendedRunning {
            startSession()
        }
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
        // Bridge the single delegate callback into an async result, BOUNDED by a
        // timeout. `photoOutput(_:didFinishProcessingPhoto:error:)` resumes the
        // continuation on a healthy capture; the timeout task resumes it with
        // `.captureTimedOut` when the delegate never fires (a dead capture
        // source — after an ungraceful force-quit the `mediaserverd` connection
        // is gone and the delegate is never invoked, so an unbounded await would
        // hang the capture flow forever; Test 10 gap).
        //
        // Exactly-once resume: both the delegate and the timeout route through
        // `resolveCapture(...)`, which check-and-clears `captureContinuation`
        // under `@MainActor` isolation. Whichever fires first wins; the loser
        // sees a `nil` continuation and is a no-op.
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            self.captureTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.captureTimeout)
                guard let self, !Task.isCancelled else { return }
                guard self.captureContinuation != nil else { return }
                kycCameraLog.error("kyc_camera event=capture.timed_out timeout_s=\(Self.captureTimeout.components.seconds, privacy: .public) — capture source presumed dead")
                self.resolveCapture(.failure(CameraSessionError.captureTimedOut))
            }
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Resume the in-flight `capturePhoto()` continuation EXACTLY ONCE.
    ///
    /// Both the photo-output delegate and the timeout task call this. The
    /// check-and-clear of `captureContinuation` is atomic with respect to the
    /// other caller because both run on the `@MainActor` — so a delegate
    /// callback that lands after the timeout already fired (and a timeout that
    /// fires after the delegate already resumed) both see a `nil` continuation
    /// and do nothing. Also cancels the timeout task so it cannot fire later.
    private func resolveCapture(_ result: Result<AVCapturePhoto, Error>) {
        guard let continuation = captureContinuation else { return }
        captureContinuation = nil
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
        continuation.resume(with: result)
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
            // Route through the exactly-once resolver: if the timeout already
            // fired (a slow delegate after a 5s+ stall) this is a no-op, and the
            // resolver cancels the timeout task when the delegate wins the race.
            if let error {
                self.resolveCapture(.failure(CameraSessionError.captureFailed(error)))
            } else {
                self.resolveCapture(.success(photo))
            }
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
