// validationLedgerTests/KYC/CameraSessionLifecycleTests.swift
// Phase 5 Plan 10 — Test 10 gap: the force-quit shutter-wedge fix.
// Requirements: KYC-02 / KYC-04.
//
// === Why this is a simulator suite, not a device suite ===
// A live `AVCaptureSession` produces no frames on the simulator (RESEARCH
// Pitfall 1) and an `AVCapturePhoto` cannot be synthesized off-device, so this
// suite does NOT drive a real capture. It exercises the observable,
// simulator-safe behavior of the wedge fix: the capture VMs' new recoverable-
// failure path. A `StubCameraSession` whose `capturePhoto()` throws
// `CameraSessionError.captureTimedOut` stands in for a dead capture source —
// exactly the on-device condition after an ungraceful force-quit.
//
// The two compounding lifecycle defects the fix closes (diagnosed in
// `.planning/debug/kyc-force-quit-camera-stuck.md`):
//   1. `capturePhoto()` awaited forever on a dead source — now timeout-bounded,
//      throws `.captureTimedOut`.
//   2. `AVFoundationCameraSession` registered zero runtime-error / app-lifecycle
//      observers — now self-heals (covered by the grep gate in <verify>, since
//      the live `AVCaptureSession` observers are not simulator-exercisable).
//
// What this suite proves about the VM layer:
//   • A `.captureTimedOut` from `capturePhoto()` clears `captureInFlight` — the
//     next `capture()` is NOT a silent no-op (the wedge).
//   • The VM lands in the recoverable `.captureUnavailable` state, NOT the
//     dead-shutter `.capturing`/`.failed` — so the VC re-enables the shutter.
//   • After the timeout-driven `.captureUnavailable`, a SECOND `capture()`
//     genuinely re-fires: the state machine moves back through `.capturing`,
//     proving the shutter is re-armed (a no-op would never reach `.capturing`).
//
// `@Suite(.serialized)` — the suite drives `@MainActor` VM state and the stub
// camera's per-call scripting; serialized keeps each `@Test`'s scripting isolated.

import Testing
import AVFoundation
import CoreLocation
import Foundation
@testable import validationLedger

@Suite("Camera session lifecycle — force-quit shutter-wedge fix (Test 10 gap)", .serialized)
@MainActor
struct CameraSessionLifecycleTests {

    // MARK: - Capture-timeout → recoverable state (VehicleCaptureViewModel)

    @Test("A capturePhoto() timeout clears captureInFlight and lands in the recoverable .captureUnavailable state (vehicle)")
    func vehicleCaptureTimeoutReachesRecoverableState() async throws {
        let camera = StubCameraSession()
        camera.captureBehavior = .throwError(CameraSessionError.captureTimedOut)
        let viewModel = makeVehicleViewModel(camera: camera)

        var observed: [VehicleCaptureViewModel.State] = []
        viewModel.onStateChange = { observed.append($0) }

        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()

        #expect(viewModel.state == .captureUnavailable,
                "a capture timeout lands in the recoverable, shutter-enabled state — not .failed")
        #expect(!observed.contains(where: { if case .failed = $0 { return true } else { return false } }),
                "a capture timeout must NOT route through the dead-shutter .failed state")
        #expect(observed.contains(.capturing),
                "the capture genuinely fired (passed through .capturing) before timing out")
    }

    @Test("After a capture timeout the shutter is re-armed — a second capture() is not a silent no-op (vehicle)")
    func vehicleShutterReArmsAfterTimeout() async throws {
        let camera = StubCameraSession()
        camera.captureBehavior = .throwError(CameraSessionError.captureTimedOut)
        let viewModel = makeVehicleViewModel(camera: camera)

        // First capture — times out, lands recoverable.
        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()
        #expect(viewModel.state == .captureUnavailable)

        // The wedge: pre-fix, `captureInFlight` was still true here, so this
        // second `capture()` was a silent no-op forever. Post-fix it re-fires.
        var observedAfter: [VehicleCaptureViewModel.State] = []
        viewModel.onStateChange = { observedAfter.append($0) }
        camera.resetCaptureCount()

        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()

        #expect(camera.capturePhotoCallCount == 1,
                "the second capture() genuinely reached the camera — the shutter is re-armed")
        #expect(observedAfter.contains(.capturing),
                "the second capture() moved the state machine through .capturing — not a no-op")
    }

    // MARK: - Capture-timeout → recoverable state (FaceCaptureViewModel)

    @Test("A capturePhoto() timeout clears captureInFlight and lands in the recoverable .captureUnavailable state (face)")
    func faceCaptureTimeoutReachesRecoverableState() async throws {
        let camera = StubCameraSession()
        camera.captureBehavior = .throwError(CameraSessionError.captureTimedOut)
        let viewModel = makeFaceViewModel(camera: camera)

        var observed: [FaceCaptureViewModel.State] = []
        viewModel.onStateChange = { observed.append($0) }

        // The face VM's `capture()` is guarded on `.readyToCapture` — drive the
        // VM there first via a steady-`.pass` gate stream so `capture()` fires.
        viewModel.forceReadyToCaptureForTest()
        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()

        #expect(viewModel.state == .captureUnavailable,
                "a capture timeout lands in the recoverable, shutter-enabled state — not .failed")
        #expect(!observed.contains(where: { if case .failed = $0 { return true } else { return false } }),
                "a capture timeout must NOT route through the dead-shutter .failed state")
    }

    @Test("After a capture timeout the shutter is re-armed — a second capture() is not a silent no-op (face)")
    func faceShutterReArmsAfterTimeout() async throws {
        let camera = StubCameraSession()
        camera.captureBehavior = .throwError(CameraSessionError.captureTimedOut)
        let viewModel = makeFaceViewModel(camera: camera)

        viewModel.forceReadyToCaptureForTest()
        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()
        #expect(viewModel.state == .captureUnavailable)

        camera.resetCaptureCount()
        // Re-arm the gate-driven shutter, then fire again.
        viewModel.forceReadyToCaptureForTest()
        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()

        #expect(camera.capturePhotoCallCount == 1,
                "the second capture() genuinely reached the camera — the shutter is re-armed")
    }

    // MARK: - Non-timeout capture errors keep the .failed path

    @Test("A non-timeout capture error still lands in the non-recoverable .failed state (vehicle)")
    func vehicleNonTimeoutErrorStaysFailed() async throws {
        let camera = StubCameraSession()
        camera.captureBehavior = .throwError(
            CameraSessionError.captureFailed(StubError.synthetic)
        )
        let viewModel = makeVehicleViewModel(camera: camera)

        viewModel.capture()
        await camera.waitForCaptureSettled()
        await Self.drainMainActor()

        if case .failed = viewModel.state {
            // expected
        } else {
            Issue.record("a non-timeout capture error must keep the .failed path; got \(viewModel.state)")
        }
    }

    // MARK: - VM construction helpers

    private func makeVehicleViewModel(camera: StubCameraSession) -> VehicleCaptureViewModel {
        VehicleCaptureViewModel(
            artifactType: .truck,
            cameraSession: camera,
            geoContext: Self.makeFreshGeoContext(),
            gpsInjector: GPSMetadataInjector(),
            sessionStore: Self.makeStore(),
            logger: NoopLifecycleLogger()
        )
    }

    private func makeFaceViewModel(camera: StubCameraSession) -> FaceCaptureViewModel {
        FaceCaptureViewModel(
            cameraSession: camera,
            faceQualityGate: StubFaceQualityGate(),
            geoContext: Self.makeFreshGeoContext(),
            gpsInjector: GPSMetadataInjector(),
            sessionStore: Self.makeStore(),
            logger: NoopLifecycleLogger()
        )
    }

    /// A `GeoContext` whose stub `LocationProvider` always returns a fresh fix,
    /// so `freshLocation()` never blocks capture — the capture path proceeds to
    /// `capturePhoto()`, which is the behavior under test.
    private static func makeFreshGeoContext() -> GeoContext {
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 39.0, longitude: -77.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        return GeoContext(locationProvider: AlwaysFreshLocationProvider(fix: fix))
    }

    private static func makeStore() -> KYCSessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kyc-camera-lifecycle-\(UUID().uuidString)", isDirectory: true)
        // The store ctor only throws if the directory cannot be created — a
        // fresh unique temp dir never fails. Force-unwrap is test-acceptable.
        return try! KYCSessionStore(directory: dir)
    }

    /// Yield repeatedly so every `Task { @MainActor … }` enqueued by the VM's
    /// `performCapture()` continuation has run before the assertion reads state.
    private static func drainMainActor() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

// MARK: - StubCameraSession

/// A `CameraSession` stub for the simulator suite. `capturePhoto()` is scripted
/// per-test to throw a specific `CameraSessionError` (a dead capture source);
/// every other protocol member is an inert no-op — the suite never drives a
/// live preview or session lifecycle.
@MainActor
final class StubCameraSession: CameraSession {

    enum CaptureBehavior {
        /// `capturePhoto()` throws this error.
        case throwError(Error)
    }

    var captureBehavior: CaptureBehavior = .throwError(CameraSessionError.captureTimedOut)

    /// Count of `capturePhoto()` calls — proves the shutter re-armed (the second
    /// `capture()` after a timeout actually reaches the camera).
    private(set) var capturePhotoCallCount = 0

    /// Set once a `capturePhoto()` call has returned/thrown, so a test can await
    /// the capture settling without a fixed sleep.
    private var captureSettled = false

    private let _previewLayer = AVCaptureVideoPreviewLayer()
    var videoFrameHandler: (@Sendable (CMSampleBuffer) -> Void)?

    func requestPermission() async -> AVAuthorizationStatus { .authorized }
    func configure(position: CameraPosition) throws {}
    func startAuthorizedSession(position: CameraPosition) async throws {}
    func start() {}
    func stop() {}
    func switchCamera(to position: CameraPosition) throws {}

    var previewLayer: AVCaptureVideoPreviewLayer { _previewLayer }

    func capturePhoto() async throws -> AVCapturePhoto {
        capturePhotoCallCount += 1
        captureSettled = false
        defer { captureSettled = true }
        switch captureBehavior {
        case let .throwError(error):
            throw error
        }
    }

    /// Reset the call counter between the two `capture()` calls of a re-arm test.
    func resetCaptureCount() {
        capturePhotoCallCount = 0
        captureSettled = false
    }

    /// Await the in-flight `capturePhoto()` returning/throwing — `capturePhoto()`
    /// here is synchronous-bodied, so this resolves on the first yield.
    func waitForCaptureSettled() async {
        for _ in 0..<50 {
            if captureSettled { return }
            await Task.yield()
        }
    }
}

// MARK: - StubFaceQualityGate

/// An inert `FaceQualityGate` — the lifecycle suite never drives Vision frames;
/// it forces the face VM into `.readyToCapture` directly.
final class StubFaceQualityGate: FaceQualityGate, @unchecked Sendable {
    @MainActor func signals() -> AsyncStream<FaceGateSignal> {
        AsyncStream { _ in }
    }
    nonisolated func process(sampleBuffer: CMSampleBuffer, cameraPosition: CameraPosition) {}
    @MainActor func stop() {}
}

// MARK: - AlwaysFreshLocationProvider

/// A `LocationProvider` that always returns a fresh, accurate fix so the KYC
/// capture path never blocks on GPS — the test isolates the `capturePhoto()`
/// timeout behavior.
final class AlwaysFreshLocationProvider: LocationProvider, @unchecked Sendable {
    private let fix: CLLocation
    init(fix: CLLocation) { self.fix = fix }
    @MainActor func requestPermission() async -> CLAuthorizationStatus { .authorizedWhenInUse }
    @MainActor func currentLocation(
        maxAge: TimeInterval,
        maxAccuracy: CLLocationDistance
    ) async throws -> CLLocation {
        // Return a fix stamped "now" so GeoContext's freshness gate passes.
        CLLocation(
            coordinate: fix.coordinate,
            altitude: fix.altitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            verticalAccuracy: fix.verticalAccuracy,
            timestamp: Date()
        )
    }
}

// MARK: - NoopLifecycleLogger

/// A no-op `Logger` — the VMs require a logger dep; the suite asserts on state,
/// not log output.
final class NoopLifecycleLogger: Logger {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}

// MARK: - StubError

enum StubError: Error { case synthetic }
