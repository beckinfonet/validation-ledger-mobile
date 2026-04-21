// validationLedger/App/AppContainer.swift
// ARCH-04: initializer-DI composition root. No singletons, no runtime DI library.
//
// Invariant: SceneDelegate.presentRoot(_:) allocates a fresh AppContainer + AppCoordinator
// per role change (D-10 / ADR 0002 — abrupt replace). Previous container deallocates
// via ARC on next runloop tick, emitting the `app_container_deinit` log.
//
// KeyStore selection is gated at compile time:
//   - #if DEBUG && targetEnvironment(simulator) → SoftwareKeyStore (P256 in memory)
//   - #else → SecureEnclaveKeyStore, with SecureEnclave.isAvailable pre-check
//             (fatalError on production device lacking SEP — Pitfall P8 mitigation /
//             FR-iOS-DEV MUST: refuse to launch without SEP).

import Foundation
import CryptoKit

final class AppContainer {
    let env: Environment
    let logger: any Logger
    let keychainStore: KeychainStore
    let keyStore: any KeyStoreProtocol
    let sessionLock: any SessionLockService
    let networkClient: any NetworkClient
    let deepLinkRouter: DeepLinkRouter

    init(env: Environment) {
        self.env = env

        // One logger for the composition root itself. Feature / VM loggers get their
        // own subsystem per D-17 when Features land in Phase 3+.
        self.logger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.app,
            category: "bootstrap"
        )

        self.keychainStore = KeychainStore(accessGroup: env.keychainAccessGroup)

        #if DEBUG && targetEnvironment(simulator)
        self.keyStore = SoftwareKeyStore()
        #else
        guard SecureEnclave.isAvailable else {
            // FR-iOS-DEV MUST: refuse to launch on a production device lacking SEP.
            fatalError("Production build requires Secure Enclave; device reports SecureEnclave.isAvailable = false")
        }
        self.keyStore = SecureEnclaveKeyStore()
        #endif

        self.sessionLock = DefaultSessionLockService()

        // MockURLProtocol registration — DEBUG-only (per Plan 03 T-03-05 mitigation).
        let sessionConfig = URLSessionConfiguration.ephemeral
        #if DEBUG
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        #endif
        self.networkClient = URLSessionNetworkClient(
            config: .mock,                    // Phase 1 — Phase 2 swaps to .live(baseURL:)
            session: URLSession(configuration: sessionConfig)
        )

        self.deepLinkRouter = DeepLinkRouter()

        logger.info(event: .init("app_container_init"), fields: [.event: env.name])
    }

    deinit {
        logger.info(event: .init("app_container_deinit"), fields: [:])
        // D-10 / ADR 0002: deinit observability — SceneDelegate root-swap drops the
        // old container; this log confirms deterministic ARC-driven deallocation.
    }
}
