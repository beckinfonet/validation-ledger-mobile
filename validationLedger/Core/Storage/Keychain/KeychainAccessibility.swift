// validationLedger/Core/Storage/Keychain/KeychainAccessibility.swift
import Foundation
import Security

public enum KeychainAccessibility: Sendable {
    /// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — default for session tokens per AUTH-03.
    case afterFirstUnlockThisDeviceOnly
    /// kSecAttrAccessibleWhenUnlockedThisDeviceOnly — strictest; UI-active required.
    case whenUnlockedThisDeviceOnly

    var cfValue: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}
