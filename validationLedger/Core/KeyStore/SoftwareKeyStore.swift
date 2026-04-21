// validationLedger/Core/KeyStore/SoftwareKeyStore.swift
// In-memory P256 keypair — SIMULATOR + DEBUG ONLY.
// AppContainer's #if DEBUG && targetEnvironment(simulator) branch is the only resolver.

import Foundation
import CryptoKit

final class SoftwareKeyStore: KeyStoreProtocol {
    private let privateKey = P256.Signing.PrivateKey()

    func sign(_ data: Data) throws -> Data {
        let signature = try privateKey.signature(for: data)
        return signature.rawRepresentation
    }

    func publicKeyRepresentation() throws -> Data {
        privateKey.publicKey.rawRepresentation
    }
}
