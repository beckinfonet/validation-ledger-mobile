// validationLedger/Core/Storage/Keychain/KeychainKey.swift
import Foundation

public struct KeychainKey: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    // Typed keys used across Phase 2+ (declared here so the storage layer
    // is the source-of-truth for key names — avoids string-typo bugs).
    public static let sessionToken = KeychainKey(rawValue: "session.token")
    public static let installUUID  = KeychainKey(rawValue: "install.uuid")
}
