// validationLedgerTests/KYC/FaceQualityGateTests.swift
// Requirement: KYC-02 / D-04 — face-capture quality gate over Vision observations.
// GREEN suite (plan 05-03). RED scaffold landed in Wave 0 / plan 05-01.
//
// The TESTABLE core of the face quality gate is two pure pieces:
//   1. `evaluate(faceBoundingBox:brightness:)` — the per-frame decision
//      (noFace / adjust(reason) / pass). It is a `static` member of the
//      `FaceQualityGate` protocol family; the tests reach it through the
//      concrete `VisionFaceQualityGate` conformer (Swift does not permit a
//      static member call on a bare protocol metatype).
//   2. `SteadyHoldTracker` — given a stream of signals + timestamps, reports
//      `readyToFire` only after `.pass` has held continuously for the dwell (D-04).
// Neither needs a camera — the live `VNDetectFaceRectanglesRequest` /
// `AVCaptureSession` surface is behind a protocol for device CI (RESEARCH
// Pitfall 1). These tests drive the pure functions directly.

import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import validationLedger

@Suite("FaceQualityGate — gate logic + steady-hold (KYC-02 / D-04)")
struct FaceQualityGateTests {

    // MARK: - evaluate(): pass

    @Test("A centered, large-enough, well-lit face passes the gate")
    func centeredLargeWellLitFacePasses() {
        // Centered on (0.5, 0.5), width 0.45 > 0.35 threshold.
        let box = CGRect(x: 0.275, y: 0.30, width: 0.45, height: 0.40)
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: box, brightness: 0.6)
        #expect(signal == .pass)
    }

    // MARK: - evaluate(): noFace

    @Test("No face observation yields a noFace signal")
    func noObservationYieldsNoFace() {
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: nil, brightness: 0.6)
        #expect(signal == .noFace)
    }

    // MARK: - evaluate(): adjust

    @Test("An off-center face yields adjust(.notCentered)")
    func offCenterFaceYieldsAdjustNotCentered() {
        // midX ≈ 0.15 — far outside the 0.12 centering tolerance.
        let box = CGRect(x: 0.0, y: 0.30, width: 0.40, height: 0.40)
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: box, brightness: 0.6)
        #expect(signal == .adjust(.notCentered))
    }

    @Test("A face that is too small yields adjust(.tooSmall)")
    func tooSmallFaceYieldsAdjustTooSmall() {
        // Centered but width 0.20 < 0.35 threshold.
        let box = CGRect(x: 0.40, y: 0.40, width: 0.20, height: 0.20)
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: box, brightness: 0.6)
        #expect(signal == .adjust(.tooSmall))
    }

    @Test("A centered, large face in low light yields adjust(.tooDark)")
    func lowLightFaceYieldsAdjustTooDark() {
        // Centered + large, but brightness 0.05 is below the low-light floor.
        let box = CGRect(x: 0.275, y: 0.30, width: 0.45, height: 0.40)
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: box, brightness: 0.05)
        #expect(signal == .adjust(.tooDark))
    }

    @Test("A nil brightness reading does not block an otherwise-passing face")
    func nilBrightnessDoesNotBlockPass() {
        // brightness == nil — the gate cannot assess light, so it must not
        // fail on darkness; a centered+large face still passes.
        let box = CGRect(x: 0.275, y: 0.30, width: 0.45, height: 0.40)
        let signal = VisionFaceQualityGate.evaluate(faceBoundingBox: box, brightness: nil)
        #expect(signal == .pass)
    }

    // MARK: - SteadyHoldTracker

    @Test("A single transient pass does NOT report readyToFire")
    func singleTransientPassDoesNotFire() {
        var tracker = SteadyHoldTracker(dwell: 0.5)
        // One pass at t=0 — no elapsed time has accumulated yet.
        let ready = tracker.update(signal: .pass, at: 0.0)
        #expect(ready == false)
    }

    @Test("A pass held continuously for the full dwell reports readyToFire")
    func passHeldForDwellReportsReady() {
        var tracker = SteadyHoldTracker(dwell: 0.5)
        #expect(tracker.update(signal: .pass, at: 0.0) == false)   // pass begins
        #expect(tracker.update(signal: .pass, at: 0.3) == false)   // 0.3s < 0.5s
        #expect(tracker.update(signal: .pass, at: 0.55) == true)   // 0.55s ≥ 0.5s
    }

    @Test("A non-pass signal mid-dwell resets the steady-hold timer")
    func nonPassSignalResetsTheTimer() {
        var tracker = SteadyHoldTracker(dwell: 0.5)
        #expect(tracker.update(signal: .pass, at: 0.0) == false)
        #expect(tracker.update(signal: .pass, at: 0.4) == false)
        // An adjust at 0.45 breaks the hold — the timer resets.
        #expect(tracker.update(signal: .adjust(.notCentered), at: 0.45) == false)
        // A new pass at 0.5 has only just begun — not yet 0.5s of continuous hold.
        #expect(tracker.update(signal: .pass, at: 0.5) == false)
        #expect(tracker.update(signal: .pass, at: 0.8) == false)   // 0.3s into the NEW hold
        #expect(tracker.update(signal: .pass, at: 1.05) == true)   // 0.55s into the new hold
    }

    @Test("A noFace signal mid-dwell resets the steady-hold timer")
    func noFaceSignalResetsTheTimer() {
        var tracker = SteadyHoldTracker(dwell: 0.5)
        #expect(tracker.update(signal: .pass, at: 0.0) == false)
        #expect(tracker.update(signal: .noFace, at: 0.3) == false)
        #expect(tracker.update(signal: .pass, at: 0.4) == false)
        #expect(tracker.update(signal: .pass, at: 1.0) == true)    // 0.6s into the new hold
    }

    // MARK: - Vision orientation (debug session round 5 / Bug B)

    /// Regression lock for the auto-fire-has-no-frames bug (debug session
    /// `front-camera-preview-black`, round 5 / Bug B). The video-data-output
    /// pipeline feeds `CVPixelBuffer`s to Vision; if the orientation is wrong
    /// Vision finds NO faces and never throws — the auto-fire silently never
    /// triggers. The front camera in portrait must be `.leftMirrored`; using
    /// the back-camera value (`.right`) leaves a front face rotated 180°.

    @Test("Front camera in portrait maps to .leftMirrored for Vision")
    func frontCameraPortraitOrientationIsLeftMirrored() {
        #expect(VisionImageOrientation.portrait(for: .front) == .leftMirrored)
    }

    @Test("Back camera in portrait maps to .right for Vision")
    func backCameraPortraitOrientationIsRight() {
        #expect(VisionImageOrientation.portrait(for: .back) == .right)
    }

    @Test("Front and back portrait orientations are distinct")
    func frontAndBackPortraitOrientationsDiffer() {
        // The front camera's feed is mirrored; the back camera's is not. If a
        // refactor collapsed both to one value, front-camera face detection
        // would break — this guards against that.
        #expect(VisionImageOrientation.portrait(for: .front)
                != VisionImageOrientation.portrait(for: .back))
    }
}

@Suite("CameraSession — hardware availability gate (RESEARCH Pitfall 1)")
struct CameraSessionAvailabilityTests {

    @Test("isCameraAvailable is false on the simulator so no live session is built")
    func cameraUnavailableOnSimulator() {
        // The simulator has no camera hardware — the availability gate must
        // report false so the capture VCs branch away from a live session.
        #expect(AVFoundationCameraSession.isCameraAvailable == false)
    }

    /// Regression lock for the black-preview defect (debug session
    /// `front-camera-preview-black`): an `AVCaptureSession` started BEFORE the
    /// camera-permission grant resolves never receives the camera feed. The
    /// fix routes every capture screen's session start through
    /// `startAuthorizedSession`, which awaits `requestPermission()` first.
    /// This test pins that permission-gated entry point onto the `CameraSession`
    /// protocol so a future change cannot quietly drop it and reintroduce the
    /// start-before-grant race.
    @Test("CameraSession exposes the permission-gated startAuthorizedSession entry point")
    @MainActor
    func cameraSessionExposesAuthorizedStart() async {
        let session: any CameraSession = AVFoundationCameraSession()
        // Referencing the method as a value proves it is part of the protocol
        // contract — the capture VMs MUST start the session through this path,
        // never via a bare configure()/start() that races the permission grant.
        let authorizedStart: (CameraPosition) async throws -> Void = session.startAuthorizedSession
        _ = authorizedStart
    }

    /// Regression lock for the auto-fire-has-no-frames defect (debug session
    /// `front-camera-preview-black`, round 5 / Bug B). The D-04 face-capture
    /// auto-fire needs a live `CMSampleBuffer` stream — the `videoFrameHandler`
    /// is the seam the `FaceCaptureViewModel` wires to feed the Vision gate. If
    /// a refactor drops this from the protocol, the gate goes frame-starved and
    /// the capture screen becomes a dead end again.
    @Test("CameraSession exposes the videoFrameHandler frame-sink seam")
    @MainActor
    func cameraSessionExposesVideoFrameHandler() async {
        let session: any CameraSession = AVFoundationCameraSession()
        // It must be settable and start out nil (no handler until the VM wires
        // one in `observeGateSignals`).
        #expect(session.videoFrameHandler == nil)
        var received = 0
        session.videoFrameHandler = { _ in received += 1 }
        #expect(session.videoFrameHandler != nil)
        session.videoFrameHandler = nil
        #expect(session.videoFrameHandler == nil)
        _ = received
    }
}
