// validationLedger/App/AppContainer.swift
// ARCH-04: initializer-DI composition root. No singletons, no runtime DI library.
//
// Invariant: SceneDelegate.presentRoot(_:) allocates a fresh AppContainer + AppCoordinator
// per role change (D-10 / ADR 0002 — abrupt replace). Previous container deallocates
// via ARC on next runloop tick, emitting the `app_container_deinit` log.
//
// KeyStore selection is gated at compile time:
//   - #if DEBUG && targetEnvironment(simulator) → SoftwareKeyStore (P256 in memory)
//   - #else → SecureEnclaveKeyStore, with Self.preflightSecureEnclave(...) gate
//             (fatalError on production device lacking SEP — Pitfall P8 mitigation /
//             FR-iOS-DEV MUST: refuse to launch without SEP).
//
// Phase 2 Plan 07 additions:
//   - apiClient: typed-endpoint facade composing NetworkClient + IdempotencyInterceptor + RetryInterceptor
//   - makeSession(networkConfig:) factory — the ONE place URLSessions are constructed
//   - defaultNetworkConfig(env:) — #if DEBUG → .mock; else → .live(baseURL: env.apiBaseURL) (fatalError if nil)
//   - isSecureEnclaveAvailable parameter (default: SecureEnclave.isAvailable) — injection seam
//     for the DEV-03 forced-stub device test (validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests)
//   - preflightSecureEnclave(isSecureEnclaveAvailable:isSimulatorBuild:isDebugBuild:) — pure-Bool
//     extract of the keystore-gate logic so tests can assert false-path outcome without triggering fatalError
//
// Invariants preserved:
//   - PinningSessionDelegate is ONLY installed on the .live URLSession (Pitfall 5 — mock session
//     must NOT get pinning, else https://mock.local fails every request)
//   - MockURLProtocol is ONLY in the .mock URLSession's protocolClasses
//   - DEBUG+simulator branch uses SoftwareKeyStore (DEV-03)
//   - Production refuses launch if isSecureEnclaveAvailable == false

import Foundation
import CryptoKit

final class AppContainer {
    let env: Environment
    let logger: any Logger
    let keychainStore: KeychainStore
    let keyStore: any KeyStoreProtocol
    let biometricService: any BiometricService
    let sessionLock: any SessionLockService
    let networkClient: any NetworkClient
    let apiClient: APIClient
    let deepLinkRouter: DeepLinkRouter

    /// Primary initializer.
    ///
    /// - Parameters:
    ///   - env: `Environment.current` in production; tests inject a custom env.
    ///   - networkConfig: optional override for NET-03 mock/live selection. `nil` defers to
    ///                    `defaultNetworkConfig(env:)` — DEBUG → `.mock`, Release → `.live(baseURL:)`.
    ///                    DevMenu's NetworkConfigToggleViewController (DEBUG-only) injects a custom
    ///                    value to flip the live/mock switch at runtime.
    ///   - isSecureEnclaveAvailable: defaults to the real `SecureEnclave.isAvailable` check.
    ///                               The DEV-03 device test injects `false` to verify the Release
    ///                               fatalError path via `preflightSecureEnclave` without actually
    ///                               triggering the trap (the preflight static returns the decision).
    init(
        env: Environment,
        networkConfig: NetworkConfig? = nil,
        isSecureEnclaveAvailable: Bool = SecureEnclave.isAvailable
    ) {
        self.env = env

        // One logger for the composition root itself. Feature / VM loggers get their
        // own subsystem per D-17 when Features land in Phase 3+.
        self.logger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.app,
            category: "bootstrap"
        )

        self.keychainStore = KeychainStore(accessGroup: env.keychainAccessGroup)

        // KeyStore selection — Phase 1 gate preserved; DEV-03 fatalError path now consults the
        // pure-Bool `preflightSecureEnclave` static so device tests can assert on the gate logic.
        #if DEBUG && targetEnvironment(simulator)
        self.keyStore = SoftwareKeyStore()
        #else
        guard Self.preflightSecureEnclave(isSecureEnclaveAvailable: isSecureEnclaveAvailable) else {
            // FR-iOS-DEV MUST / DEV-03 SC-4: refuse to launch on a production device lacking SEP.
            fatalError("Production build requires Secure Enclave; device reports SecureEnclave.isAvailable = false")
        }
        self.keyStore = SecureEnclaveKeyStore()
        #endif

        // Phase 3 Plan 06: SessionLockService gains biometric + keychain deps
        // (D-07/D-08/D-09 lockState machine). Plan 11 refines composition-root
        // wiring; this is the minimal-change to keep AppContainer compiling once
        // DefaultSessionLockService's init signature changed.
        let featureLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.app,
            category: "auth.biometric"
        )
        let biometricService = DefaultBiometricService(
            keychain: self.keychainStore,
            logger: featureLogger
        )
        self.biometricService = biometricService
        self.sessionLock = DefaultSessionLockService(
            biometric: biometricService,
            keychain: self.keychainStore
        )

        // NET-03: URLSession + NetworkClient construction via the single `makeSession` factory.
        // AppContainer is the ONLY place URLSession is constructed — a grep over `validationLedger/`
        // for `URLSession(` outside this file should return zero non-test hits.
        let resolvedConfig = networkConfig ?? Self.defaultNetworkConfig(env: env)
        let session = Self.makeSession(networkConfig: resolvedConfig)
        let networkClient = URLSessionNetworkClient(
            config: resolvedConfig,
            session: session
        )
        self.networkClient = networkClient

        // API client composition (Plan 02 typed facade + Plan 04 interceptors).
        // Callers (Phase 3 AuthRepository, Phase 5 KYCUploader) inject `appContainer.apiClient`;
        // they do NOT construct their own APIClient or URLSession.
        let apiBaseURL = Self.apiBaseURL(for: resolvedConfig)
        self.apiClient = APIClient(
            baseURL: apiBaseURL,
            networkClient: networkClient,
            requestInterceptors: [IdempotencyInterceptor()],
            responseInterceptors: [RetryInterceptor()]
        )

        self.deepLinkRouter = DeepLinkRouter()

        logger.info(event: .init("app_container_init"), fields: [.event: env.name])
    }

    deinit {
        logger.info(event: .init("app_container_deinit"), fields: [:])
        // D-10 / ADR 0002: deinit observability — SceneDelegate root-swap drops the
        // old container; this log confirms deterministic ARC-driven deallocation.
    }

    // MARK: - NET-03 factory

    /// Default networking config: mock in DEBUG (unless the caller overrides), live in Release.
    /// Release with nil apiBaseURL is a developer error — fatalError blocks shipping a broken binary.
    private static func defaultNetworkConfig(env: Environment) -> NetworkConfig {
        #if DEBUG
        return .mock
        #else
        guard let baseURL = env.apiBaseURL else {
            // WR-06 closure: Release build must supply a non-nil apiBaseURL.
            // Environment.swift PHASE-2-TODO marker + CI grep gate are the source-level sentinels;
            // this fatalError is the runtime sentinel.
            fatalError("Release build requires Environment.release.apiBaseURL — set it before shipping (see docs/ci.md WR-06)")
        }
        return .live(baseURL: baseURL)
        #endif
    }

    /// Resolve the APIClient base URL from the network config.
    /// Mock uses https://mock.local — ATS-compliant placeholder; MockURLProtocol intercepts
    /// before any TLS is attempted, so the URL's domain never resolves and the host string
    /// only matters for building URLRequest paths.
    private static func apiBaseURL(for config: NetworkConfig) -> URL {
        switch config {
        case .mock:
            return URL(string: "https://mock.local")!
        case .live(let url):
            return url
        }
    }

    /// URLSession factory — the ONE place URLSessions are constructed.
    /// Invariant: PinningSessionDelegate attached ONLY on `.live`; MockURLProtocol protocolClasses
    /// set ONLY on `.mock`. Any future plan that suggests building a URLSession elsewhere in the
    /// app must be rejected in review.
    private static func makeSession(networkConfig: NetworkConfig) -> URLSession {
        switch networkConfig {
        case .mock:
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [MockURLProtocol.self]
            // NO PinningSessionDelegate — mock session serves https://mock.local which has no
            // real cert; installing the pinning delegate here would reject every test request.
            return URLSession(configuration: config)
        case .live:
            let config = URLSessionConfiguration.default
            // PinningSessionDelegate installed on .live ONLY. PinnedSPKIs.current returns
            // .staging in DEBUG and .release otherwise (Plan 05 PinnedSPKIs.swift).
            return URLSession(
                configuration: config,
                delegate: PinningSessionDelegate(pins: PinnedSPKIs.current),
                delegateQueue: nil
            )
        }
    }

    // MARK: - DEV-03 preflight (SC-4 test seam)

    /// Preflight the Secure Enclave invariant. Returns true if launch should proceed, false if not.
    /// `AppContainer.init` uses this via the `isSecureEnclaveAvailable` parameter and fatalErrors
    /// on false in production paths — this static lets device tests assert the false-path outcome
    /// WITHOUT triggering the process-aborting fatalError.
    ///
    /// Defaults for `isSimulatorBuild` / `isDebugBuild` reflect the build configuration of the
    /// test process itself; tests inject values to simulate production Release + device.
    static func preflightSecureEnclave(
        isSecureEnclaveAvailable: Bool,
        isSimulatorBuild: Bool = {
            #if targetEnvironment(simulator)
            return true
            #else
            return false
            #endif
        }(),
        isDebugBuild: Bool = {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }()
    ) -> Bool {
        if isDebugBuild && isSimulatorBuild {
            // Simulator + DEBUG path uses SoftwareKeyStore — SE check not required.
            return true
        }
        // Non-simulator (device) OR Release build — SE must be available.
        return isSecureEnclaveAvailable
    }
}
