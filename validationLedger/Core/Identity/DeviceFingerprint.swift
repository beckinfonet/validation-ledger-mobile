// validationLedger/Core/Identity/DeviceFingerprint.swift
// DEV-05: Assemble the /device/register payload's device-fingerprint field.
//
// Contents: { model (hardware identifier), iosVersion, installUUID }
//   - model: via `utsname()` (e.g., "iPhone15,2") — more specific than UIDevice.model (which just says "iPhone")
//   - iosVersion: UIDevice.current.systemVersion (e.g., "17.5.1")
//   - installUUID: per-install UUIDv4, generated on first call, persisted in Keychain thereafter
//
// Install UUID is stored in Keychain (not UserDefaults) because:
//   - Keychain survives app uninstalls (unless FOUND-02 wipe runs) — good for debugging device history
//   - UserDefaults is cleared on uninstall — the FOUND-02 keychain wiper clears the installUUID too, so
//     reinstalling gives a fresh UUID (intended — the fingerprint represents the current install session)
//   - Accessibility: .afterFirstUnlockThisDeviceOnly — available post-boot without user unlock, non-syncable
//
// No PrivacyInfo.xcprivacy changes needed:
//   - utsname() is not a required-reason API
//   - UIDevice.systemVersion is not a required-reason API
//   - Install UUID is app-scoped (not IDFA-like)

import Foundation
import UIKit

public struct DeviceFingerprint: Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String

    public init(model: String, iosVersion: String, installUUID: String) {
        self.model = model
        self.iosVersion = iosVersion
        self.installUUID = installUUID
    }

    /// Factory: read or generate the installUUID via the supplied KeychainStore.
    /// The model + iOS version are always fresh from UIDevice/utsname.
    public static func current(keychain: KeychainStore) throws -> DeviceFingerprint {
        let installUUID = try Self.resolveInstallUUID(keychain: keychain)
        return DeviceFingerprint(
            model: UIDevice.current.modelIdentifier(),
            iosVersion: UIDevice.current.systemVersion,
            installUUID: installUUID
        )
    }

    // MARK: - Install UUID persistence

    /// Keychain key used for the persisted install UUID. Exposed for tests (not for callers).
    static let installUUIDKey = KeychainKey(rawValue: "device.install_uuid")

    static func resolveInstallUUID(keychain: KeychainStore) throws -> String {
        if let existing = try? keychain.get(installUUIDKey),
           let decoded = String(data: existing, encoding: .utf8) {
            return decoded
        }
        let fresh = UUID().uuidString
        try keychain.set(
            Data(fresh.utf8),
            for: installUUIDKey,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        return fresh
    }
}

/// Hardware identifier (e.g., "iPhone15,2") via utsname() — more specific than UIDevice.model.
extension UIDevice {
    func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
