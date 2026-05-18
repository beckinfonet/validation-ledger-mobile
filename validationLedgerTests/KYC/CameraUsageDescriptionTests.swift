// validationLedgerTests/KYC/CameraUsageDescriptionTests.swift
// Phase 5 KYC capture pipeline: regression guard for the camera-permission crash.
// CameraSession / CameraPermissionViewController open an AVCaptureSession for the
// selfie, driver's-license, and vehicle photo steps. AVCaptureDevice video access
// traps the app at runtime when Info.plist is missing NSCameraUsageDescription —
// the KYC capture flow crashed on "Get started" the instant it reached the camera.
// Mirrors CountryGateTests.infoPlistHasUsageDescription /
// BiometricServiceTests.infoPlistHasFaceIDUsageDescription.

import Testing
import Foundation
@testable import validationLedger

@Suite("Camera usage description — KYC capture camera access crashes without it")
struct CameraUsageDescriptionTests {

    @Test("Info.plist contains a non-empty NSCameraUsageDescription")
    func infoPlistHasCameraUsageDescription() throws {
        let source = try Self.infoPlistSource()
        #expect(source.contains("NSCameraUsageDescription"),
                "Info.plist missing NSCameraUsageDescription — the KYC capture flow crashes on a real device when CameraSession opens AVCaptureSession without it")

        let value = try #require(Self.cameraUsageDescriptionValue(in: source),
                                 "NSCameraUsageDescription must be followed by a <string> value")
        #expect(!value.isEmpty,
                "NSCameraUsageDescription must have a non-empty user-facing rationale string")
    }

    // MARK: - Helpers

    /// Reads Info.plist via #filePath-relative URL. This file lives at
    /// validationLedgerTests/KYC/CameraUsageDescriptionTests.swift — 3 hops to repo root.
    /// The project's Info.plist lives at validationLedger/App/Info.plist
    /// (verified against validationLedger.xcodeproj INFOPLIST_FILE setting).
    static func infoPlistSource(file: StaticString = #filePath) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = fileURL
            .deletingLastPathComponent()  // KYC/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo root>
        let target = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("App")
            .appendingPathComponent("Info.plist")
        return try String(contentsOf: target, encoding: .utf8)
    }

    /// Extracts the <string> value that immediately follows the
    /// <key>NSCameraUsageDescription</key> entry in the plist source.
    static func cameraUsageDescriptionValue(in source: String) -> String? {
        guard let keyRange = source.range(of: "<key>NSCameraUsageDescription</key>"),
              let openTag = source.range(of: "<string>", range: keyRange.upperBound..<source.endIndex),
              let closeTag = source.range(of: "</string>", range: openTag.upperBound..<source.endIndex)
        else { return nil }
        return String(source[openTag.upperBound..<closeTag.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
