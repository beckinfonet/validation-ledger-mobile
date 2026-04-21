// validationLedger/Core/KeyStore/KeyStoreProtocol.swift
// Protocol for device-bound signing keys. Implementations:
//   - SoftwareKeyStore: simulator + DEBUG only (Phase 1)
//   - SecureEnclaveKeyStore: production device (Phase 2+)
// AppContainer (Plan 05) selects via #if DEBUG && targetEnvironment(simulator).

import Foundation

public enum KeyStoreError: Error, Sendable {
    case notImplemented
    case signingFailed
    case keyUnavailable
}

public protocol KeyStoreProtocol: AnyObject, Sendable {
    func sign(_ data: Data) throws -> Data
    func publicKeyRepresentation() throws -> Data
}
