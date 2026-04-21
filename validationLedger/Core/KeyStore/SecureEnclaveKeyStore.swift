// validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
// STUB — Phase 1 presence only (so AppContainer's #else branch compiles).
// Real SEP-backed P256 signing lands Phase 2 alongside DEV-01/02/03.

import Foundation
import CryptoKit

final class SecureEnclaveKeyStore: KeyStoreProtocol {
    func sign(_ data: Data) throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
    func publicKeyRepresentation() throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
}
