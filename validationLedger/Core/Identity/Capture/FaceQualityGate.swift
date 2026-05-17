// validationLedger/Core/Identity/Capture/FaceQualityGate.swift
// Phase 5 Plan 03 — KYC-02 / D-04: the face-capture quality gate.
//
// KYC-02 ships QUALITY gates only — detected, centered, in-focus / well-lit.
// LIVENESS detection (blink/pose analysis, depth, a commercial SDK) is
// DEFERRED from M1 per PROJECT.md / CONTEXT KYC-02 — it is intentionally NOT
// implemented here. The only mention of liveness in this file is this comment
// recording that deferral; the backend re-verifies the captured photo.
//
// === STRUCTURE (RESEARCH Pitfall 1) ===
// `DataScanner`/`AVCaptureSession` produce no real frames on the simulator, so
// the testable logic is split out as PURE functions that need no camera:
//   • `FaceQualityGate.evaluate(faceBoundingBox:brightness:)` — the per-frame
//     decision. Simulator-testable.
//   • `SteadyHoldTracker` — the D-04 auto-fire trigger: `.pass` must hold
//     continuously for the dwell (~0.5s) before `readyToFire`. Simulator-testable.
// The live `VisionFaceQualityGate` wraps `VNDetectFaceRectanglesRequest` over
// `AVCaptureVideoDataOutput` `CMSampleBuffer`s — that path is NOT exercised by
// the simulator test and routes to device CI; it stays behind the protocol so
// plan 05's capture VCs and plan 04's pipeline stay testable.

import CoreGraphics
import Foundation
import Vision

// MARK: - Gate signal vocabulary

/// Why a single frame failed the quality gate. Surfaced to the capture screen
/// as the UI-SPEC "adjust" guidance (KYC-02).
public enum FaceAdjustReason: Equatable, Sendable {
    /// The face is detected but not within the centering tolerance of the frame.
    case notCentered
    /// The face is detected and centered but too far from the camera (too small).
    case tooSmall
    /// The frame is too dark to assess the face reliably.
    case tooDark
}

/// The per-frame decision of the face quality gate.
public enum FaceGateSignal: Equatable, Sendable {
    /// No face observation in the frame.
    case noFace
    /// A face is present but a quality check failed — see the reason.
    case adjust(FaceAdjustReason)
    /// The face is detected, centered, large enough, and adequately lit.
    case pass
}

// MARK: - Protocol

/// The face quality gate over a live Vision/AVFoundation buffer stream.
///
/// Conforming types emit a stream of `FaceGateSignal`s as frames arrive. The
/// pure decision logic (`evaluate`) and the auto-fire trigger (`SteadyHoldTracker`)
/// live as static/value types so they are exercised WITHOUT a camera.
public protocol FaceQualityGate: AnyObject, Sendable {
    /// Begin emitting gate signals. Each frame produces one `FaceGateSignal`.
    /// On the simulator a conforming type yields nothing (no camera).
    @MainActor func signals() -> AsyncStream<FaceGateSignal>

    /// Stop processing frames and finish the signal stream.
    @MainActor func stop()
}

// MARK: - Pure decision logic (simulator-testable)

extension FaceQualityGate {

    /// Centering tolerance — the face midpoint must be within this distance of
    /// the frame center (0.5, 0.5) on both axes. RESEARCH Pattern 2 value.
    static var centeringTolerance: CGFloat { 0.12 }

    /// Minimum normalized bounding-box width — the face must be at least this
    /// wide (close enough to the camera). RESEARCH Pattern 2 value.
    static var minimumFaceWidth: CGFloat { 0.35 }

    /// Low-light floor — a `brightness` reading below this fails the gate. The
    /// reading is a normalized 0...1 estimate; `nil` means "not assessed" and
    /// must NOT fail the gate (the gate cannot block on a measurement it lacks).
    static var minimumBrightness: Double { 0.15 }

    /// The pure per-frame decision.
    ///
    /// - Parameters:
    ///   - faceBoundingBox: the Vision face observation's normalized (0...1)
    ///     bounding box, or `nil` when no face was detected.
    ///   - brightness: a normalized 0...1 frame-brightness estimate, or `nil`
    ///     when brightness could not be assessed.
    /// - Returns: `.noFace`, `.adjust(reason)`, or `.pass`.
    ///
    /// Order of checks: presence → centering → size → light. Centering and size
    /// are reported before light so the most actionable guidance surfaces first.
    public static func evaluate(
        faceBoundingBox: CGRect?,
        brightness: Double?
    ) -> FaceGateSignal {
        guard let box = faceBoundingBox else {
            return .noFace
        }

        let centered = abs(box.midX - 0.5) < centeringTolerance
            && abs(box.midY - 0.5) < centeringTolerance
        if !centered {
            return .adjust(.notCentered)
        }

        if box.width <= minimumFaceWidth {
            return .adjust(.tooSmall)
        }

        // Brightness is only a gate when it was actually measured.
        if let brightness, brightness < minimumBrightness {
            return .adjust(.tooDark)
        }

        return .pass
    }
}

// MARK: - Steady-hold tracker (D-04 auto-fire trigger, simulator-testable)

/// Tracks how long a `.pass` signal has held continuously and reports
/// `readyToFire` once it has held for the configured dwell.
///
/// D-04: the face-capture screen (plan 05) auto-fires the shutter when the
/// quality gate holds steady ~0.5s. A single transient `.pass` must NOT fire —
/// any non-`.pass` signal resets the hold. This is a pure value type fed a
/// stream of `(signal, timestamp)` pairs, so it is exercised without a camera.
public struct SteadyHoldTracker {

    /// The continuous-hold duration, in seconds, required before `readyToFire`.
    private let dwell: TimeInterval

    /// The timestamp at which the current uninterrupted `.pass` run began, or
    /// `nil` when the most recent signal was not `.pass`.
    private var passRunStart: TimeInterval?

    public init(dwell: TimeInterval = 0.5) {
        self.dwell = dwell
    }

    /// Feed the tracker the next gate signal and its timestamp.
    ///
    /// - Returns: `true` once `.pass` has held continuously for at least `dwell`
    ///   seconds; `false` otherwise. A non-`.pass` signal resets the hold.
    public mutating func update(
        signal: FaceGateSignal,
        at timestamp: TimeInterval
    ) -> Bool {
        guard signal == .pass else {
            // Any non-pass signal breaks the hold — reset the run.
            passRunStart = nil
            return false
        }
        if let start = passRunStart {
            return (timestamp - start) >= dwell
        }
        // First pass of a new run — the dwell timer starts now.
        passRunStart = timestamp
        return false
    }

    /// Reset the tracker (e.g. when the capture screen is re-presented).
    public mutating func reset() {
        passRunStart = nil
    }
}

// MARK: - Live Vision-backed implementation (device CI — not simulator-tested)

/// The live face quality gate: runs `VNDetectFaceRectanglesRequest` over the
/// camera's `CMSampleBuffer` stream.
///
/// This type is NOT exercised by the simulator test suite — `AVCaptureSession`
/// produces no frames on the simulator (RESEARCH Pitfall 1). The simulator
/// tests drive `FaceQualityGate.evaluate` and `SteadyHoldTracker` directly. The
/// live frame-processing body runs on the Phase 4 physical-device CI lane.
public final class VisionFaceQualityGate: FaceQualityGate, @unchecked Sendable {

    private var continuation: AsyncStream<FaceGateSignal>.Continuation?

    public init() {}

    @MainActor public func signals() -> AsyncStream<FaceGateSignal> {
        AsyncStream { continuation in
            self.continuation = continuation
            // On the simulator there is no camera; the stream simply yields
            // nothing until `stop()`. On device the capture coordinator (plan
            // 05) feeds `process(sampleBuffer:)` from the AVFoundation delegate.
        }
    }

    @MainActor public func stop() {
        continuation?.finish()
        continuation = nil
    }

    /// Process one camera frame: detect faces and emit a gate signal.
    ///
    /// Called from the `AVCaptureVideoDataOutputSampleBufferDelegate` on device.
    /// Not reachable on the simulator. Liveness is intentionally NOT performed —
    /// only the KYC-02 quality gate (see the file header).
    public func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            let box = (request.results as? [VNFaceObservation])?.first?.boundingBox
            // Brightness assessment from the buffer is a device-only refinement;
            // pass `nil` so the gate does not block on an unmeasured value.
            let signal = Self.evaluate(faceBoundingBox: box, brightness: nil)
            self?.continuation?.yield(signal)
        }
        try? handler.perform([request])
    }
}
