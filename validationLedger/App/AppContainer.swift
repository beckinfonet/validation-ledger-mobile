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
import DeviceCheck

/// Phase 4 DEV-04 (D-09): result of `AppContainer.preflightAttestationEntitlement(...)`.
///
/// Unlike `preflightSecureEnclave` which returns `Bool` + fatalErrors in the production
/// miss path, entitlement absence is RECOVERABLE (ship a fix, re-sign, re-upload
/// TestFlight). A fatalError would brick every user with a bad build. D-09 routes
/// the miss to `attestationStatus: "entitlementMissing"` at the `/device/register`
/// call site so the backend decides policy (D-12).
///
/// rawValues are the exact strings flowed through PII-safe logger events —
/// `LogField.event` is the only field ever used; no entitlement contents or
/// `attestationObject` bytes reach the logger.
public enum AttestationEntitlementPreflightResult: String, Sendable {
    case available
    case missing
    case simulatorBypass
}

final class AppContainer {

    // MARK: - DEBUG-only UI-test dependency overrides (Phase 3 Plan 12 / D-32)
    //
    // Warning 4 mitigation: the 5 role smoke UI tests (Plan 12) drive the full OTP
    // flow end-to-end via -MockOTPRoleForUITest. The default LocationProvider +
    // CountryGate call real CLLocationManager + CLGeocoder (permission prompt +
    // network geocode) which are flaky/blocking on CI sims. SceneDelegate's
    // -MockOTPRoleForUITest path sets these two static overrides BEFORE constructing
    // the AppContainer for presentRoot; AppContainer.init prefers them over the
    // Default* implementations. Release builds compile zero bytes for this path.
    #if DEBUG
    static var uiTestLocationProvider: (any LocationProvider)?
    static var uiTestCountryGate: (any CountryGate)?
    // Phase 4 Plan 08 (D-11 / D-12): UI-test override for AppSession.trustTier.
    // The LimitedTrustBannerTests XCUITests need to drive the role shell
    // immediately under a specific trustTier without waiting for the real
    // /device/register response → session.trustTier mutation path (that wiring
    // is Plan 07's scope). SceneDelegate's -MockOTPTrustTierForUITest handler
    // sets this override BEFORE AppContainer construction; init seeds
    // AppSession(trustTier:) from the override when present, else the safe
    // default `.softwareOnly`. Release builds compile zero bytes for this
    // path (T-03-12-01 / T-APP-ATTEST-11 mitigation analog).
    static var uiTestTrustTierOverride: TrustTier?
    #endif

    let env: Environment
    let logger: any Logger
    let keychainStore: KeychainStore
    let keyStore: any KeyStoreProtocol
    let biometricService: any BiometricService
    let sessionLock: any SessionLockService
    let networkClient: any NetworkClient
    let apiClient: APIClient
    let deepLinkRouter: DeepLinkRouter

    // Phase 3 Plan 09 additions (Plan 11 refines composition root):
    // AuthCoordinator (Plan 09) consumes these to drive D-20 geo gate.
    let locationProvider: any LocationProvider
    let countryGate: any CountryGate

    // Phase 3 Plan 11 additions (composition-root wiring for D-04/D-11/D-16/D-28):
    //   - sessionRestore:  Keychain probe for cold-boot routing (D-04/D-05)
    //   - sensitiveAction: WWDC22 single-prompt SE-signing funnel (D-11 / AUTH-06)
    //   - logoutService:   single source of truth for session teardown (D-16/D-17)
    // Dependency order in init:
    //   biometricService → sessionLock → sessionRestore → (locationProvider, countryGate)
    //                                   → sensitiveAction → logoutService → apiClient
    // logoutService is constructed BEFORE apiClient so Auth401ResponseInterceptor can
    // inject the service into its responseInterceptor (D-28).
    let sessionRestore: any SessionRestoreService
    let sensitiveAction: any SensitiveActionService
    let logoutService: any LogoutService

    // Phase 4 Plan 06 additions (DEV-04):
    //   - attestationService: selected via #if DEBUG && targetEnvironment(simulator)
    //     mirroring the KeyStore gate (Pattern 9 analog). Production device +
    //     Release → DCAppAttestAttestationService. Debug + simulator →
    //     SimulatorBypassAttestationService (file-gated; not compiled into Release).
    //   - session: mutable main-actor state holder carrying trustTier (D-12).
    //     Plan 07 SceneDelegate heartbeat helper + Plan 08 LimitedTrustBanner
    //     both read/write through this single holder.
    public let attestationService: any AttestationService
    public let session: AppSession

    // Phase 5 Plan 05 additions (KYC capture + upload pipeline):
    //   - kycSessionStore: encrypted on-disk in-progress KYC session store
    //     (plan 02). Deliberately NOT wired into LogoutService teardown — the
    //     on-disk KYC session survives a logout (D-02).
    //   - geoContext:      fresh-CLLocation cache over locationProvider for
    //     capture-time GPS injection (plan 03 / KYC-04 / Pitfall 5).
    //   - kycUploader:     resumable chunked-upload pipeline (plan 04 / UPL-01).
    //     KYCCoordinator kicks `upload(artifactType:)` per captured artifact
    //     (D-01 pipelined upload).
    let kycSessionStore: KYCSessionStore
    let geoContext: GeoContext
    let kycUploader: KYCUploader

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
    ///   - biometricServiceOverride: Phase 4 Plan 06 (D-14) test seam. Defaults to `nil` so all
    ///                               existing callers (Phase 1/2/3 app launch path, existing tests)
    ///                               are unchanged. Plan 09 device tests pass
    ///                               `biometricServiceOverride: SeededBiometricService(...)` to
    ///                               inject a deterministic LAContext result without prompting
    ///                               for real Face ID in unattended CI. When non-nil, the override
    ///                               replaces the `DefaultBiometricService` that init would otherwise
    ///                               construct; `sessionLock` + `sensitiveAction` observe the override
    ///                               transitively because they resolve `biometricService` through the
    ///                               container.
    init(
        env: Environment,
        networkConfig: NetworkConfig? = nil,
        isSecureEnclaveAvailable: Bool = SecureEnclave.isAvailable,
        biometricServiceOverride: (any BiometricService)? = nil
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
        //
        // Phase 4 Plan 06 (D-14): when `biometricServiceOverride` is non-nil,
        // substitute it for the DefaultBiometricService that init would otherwise
        // construct. Plan 09 device tests inject SeededBiometricService through
        // this seam so `.success` is returned synchronously without a real Face
        // ID prompt on a physical device under unattended CI. Downstream
        // services (sessionLock, sensitiveAction) read through the override
        // because they bind to the same local `biometricService` value below.
        let featureLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.biometric"
        )
        let biometricService: any BiometricService
        if let override = biometricServiceOverride {
            biometricService = override
        } else {
            biometricService = DefaultBiometricService(
                keychain: self.keychainStore,
                logger: featureLogger
            )
        }
        self.biometricService = biometricService
        let sessionLock = DefaultSessionLockService(
            biometric: biometricService,
            keychain: self.keychainStore
        )
        self.sessionLock = sessionLock

        // Phase 3 Plan 11 — D-04/D-05: cold-boot session restore (synchronous Keychain
        // probe). The probe is separately callable as a lightweight SessionRestoreProbe
        // helper from SceneDelegate before first presentRoot (Blocker 6); the container
        // exposes the same service for any post-bootstrap re-probe callers.
        let restoreLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.restore"
        )
        self.sessionRestore = DefaultSessionRestoreService(
            keychain: self.keychainStore,
            logger: restoreLogger
        )

        // Phase 3 Plan 09: CLLocationManager + CLGeocoder wrappers for D-20 geo gate
        // (consumed by PhoneEntryViewModel). Plan 11 leaves construction default-ctor;
        // a future refactor may inject test doubles via the AppContainer init.
        //
        // Phase 3 Plan 12 / D-32 Warning 4: UI smoke tests need a deterministic,
        // network-free, prompt-free geo path. SceneDelegate's -MockOTPRoleForUITest
        // launchArg path sets `AppContainer.uiTestLocationProvider` +
        // `AppContainer.uiTestCountryGate` BEFORE constructing this container;
        // init prefers those stubs over the Default* implementations. Entire path
        // is `#if DEBUG`-gated — Release compiles to Default* only.
        #if DEBUG
        self.locationProvider = AppContainer.uiTestLocationProvider ?? DefaultLocationProvider()
        self.countryGate = AppContainer.uiTestCountryGate ?? DefaultCountryGate()
        #else
        self.locationProvider = DefaultLocationProvider()
        self.countryGate = DefaultCountryGate()
        #endif

        // Phase 3 Plan 11 — D-11 / AUTH-06: sensitive-action funnel (WWDC22 single-prompt
        // pattern). M1 ships with ZERO call sites; the constructibility + the SE signWith
        // path are the entire AUTH-06 surface for M1. M2+ tender/accept/BOL signing
        // plumbs call sites through this service.
        let sensitiveLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.sensitive"
        )
        self.sensitiveAction = DefaultSensitiveActionService(
            keyStore: self.keyStore,
            logger: sensitiveLogger
        )

        // Phase 3 Plan 11 — D-16 / D-17: single source of truth for session teardown.
        // Three call sites funnel here: ProfileViewController "Log out" (Plan 10);
        // Auth401ResponseInterceptor (wired below); DEV-06 another-active-session path
        // (placeholder in M1). MUST be constructed BEFORE apiClient so Auth401Interceptor
        // can inject it into the response-interceptor chain.
        let logoutLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.logout"
        )
        let logoutService = DefaultLogoutService(
            keychain: self.keychainStore,
            keyStore: self.keyStore,
            sessionLock: sessionLock,
            logger: logoutLogger,
            notificationCenter: .default
        )
        self.logoutService = logoutService

        // Phase 4 Plan 06 (DEV-04): attestation service selection mirrors the
        // KeyStore simulator/device gate (Pattern 9 analog — see PATTERNS.md
        // lines 453-465). Production device + Release compiles
        // DCAppAttestAttestationService; DEBUG + simulator compiles
        // SimulatorBypassAttestationService (file-gated; not present in
        // Release artifacts, verified by Plan 05's Release-strings grep).
        //
        // preflightAttestationEntitlement LOGS the result but does NOT
        // fatalError (unlike preflightSecureEnclave): D-09 routes a missing
        // entitlement to attestationStatus = "entitlementMissing" so the
        // backend decides policy (D-12). A fatalError in Release would brick
        // every user with a bad build — recoverable via re-sign/re-upload.
        //
        // PII discipline (T-APP-ATTEST-02 mitigation): logger fields are
        // left empty ([:]). The event-name string alone ("attestation_preflight_*")
        // carries the status; LogField is a closed enum that does not admit
        // entitlement contents or attestationObject bytes.
        let attestationPreflight = Self.preflightAttestationEntitlement()
        switch attestationPreflight {
        case .simulatorBypass:
            logger.info(event: .init("attestation_preflight_simulatorBypass"), fields: [:])
        case .available:
            logger.info(event: .init("attestation_preflight_available"), fields: [:])
        case .missing:
            logger.error(event: .init("attestation_preflight_missing"), fields: [:])
        }

        let attestationLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.attestation"
        )
        let attestedKeyStore = AttestedKeyStore(keychain: self.keychainStore)

        #if DEBUG && targetEnvironment(simulator)
        self.attestationService = SimulatorBypassAttestationService(keychain: self.keychainStore)
        _ = attestedKeyStore      // retain the constructed store — sim path uses its own
        #else
        self.attestationService = DCAppAttestAttestationService(
            keyStore: attestedKeyStore,
            logger: attestationLogger
        )
        #endif

        // D-12 safe default: .softwareOnly so LimitedTrustBanner (Plan 08) renders
        // until the first /device/register or /device/heartbeat response lands.
        // Plan 08 (D-11/D-12) UI-test seam: if SceneDelegate set
        // `uiTestTrustTierOverride` via the -MockOTPTrustTierForUITest launchArg,
        // seed AppSession with that tier so XCUITests can drive both
        // .softwareOnly (banner visible) and .hardwareAttested (banner absent)
        // code paths deterministically. Production path is unaffected
        // (override nil → safe default).
        #if DEBUG
        self.session = AppSession(trustTier: AppContainer.uiTestTrustTierOverride ?? .softwareOnly)
        #else
        self.session = AppSession(trustTier: .softwareOnly)
        #endif

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

        // Phase 4 Plan 04-11: DEBUG-only physical-device mock fixtures.
        //
        // Without this, a DEBUG build on a physical device (networkConfig == .mock
        // by default) would hang at Send code because MockURLProtocol has no
        // registered handlers for the organic tap-through flow. Registering
        // defaults here lets a developer walk through phone-entry → OTP verify →
        // role shell with any 6-digit code and zero backend.
        //
        // Gated on three conditions (all must hold):
        //   (a) #if DEBUG — Release compiles this block to zero bytes.
        //   (b) resolvedConfig == .mock — if DevMenu flipped to .live, skip.
        //   (c) -MockOTPRoleForUITest launch arg NOT present — that path has
        //       its own fixtures via MockOTPRoleFixtureRegistry (SceneDelegate).
        //
        // Registration must happen AFTER the URLSession is wired (MockURLProtocol
        // in protocolClasses) and BEFORE apiClient fires any request.
        #if DEBUG
        let isUITestRolePath = ProcessInfo.processInfo.arguments.contains("-MockOTPRoleForUITest")
        if case .mock = resolvedConfig, !isUITestRolePath {
            MockDefaultFixtures.registerAppDefaults()
        }
        #endif

        // API client composition (Plan 02 typed facade + Plan 04 interceptors + Plan 11 Auth401).
        // Callers (Phase 3 AuthRepository, Phase 5 KYCUploader) inject `appContainer.apiClient`;
        // they do NOT construct their own APIClient or URLSession.
        //
        // Phase 3 D-28: Auth401ResponseInterceptor is appended to the response chain so any
        // HTTP 401 from a non-OTP path triggers LogoutService.logout(.auth401). Order matters:
        // RetryInterceptor runs first (may retry the request before we see a final 401), then
        // Auth401ResponseInterceptor observes the final response.
        //
        // Phase 4 D-04: AttestationErrorResponseInterceptor is appended AFTER Auth401 so a
        // 401 on /device/heartbeat routes through Auth401 (session-expiry logout path) and is
        // NOT absorbed by a body-decode of a spurious attestationInvalid error. The attestation
        // interceptor's path filter + status-code filter + error-code filter keep the two
        // interceptors orthogonal — they never act on the same response.
        let apiBaseURL = Self.apiBaseURL(for: resolvedConfig)
        self.apiClient = APIClient(
            baseURL: apiBaseURL,
            networkClient: networkClient,
            requestInterceptors: [IdempotencyInterceptor()],
            responseInterceptors: [
                RetryInterceptor(),
                Auth401ResponseInterceptor(logoutService: logoutService),
                AttestationErrorResponseInterceptor(
                    attestationService: self.attestationService,
                    logger: attestationLogger
                ),
            ]
        )

        self.deepLinkRouter = DeepLinkRouter()

        // Phase 5 Plan 05 — KYC capture + upload services. Constructed AFTER
        // apiClient + locationProvider since kycUploader depends on apiClient and
        // geoContext builds on locationProvider.
        //
        // KYCSessionStore.init throws on a file-system failure constructing its
        // protected directory. The composition root is non-throwing, so a
        // failure here is a fatal misconfiguration (a non-writable app
        // container) — fail fast rather than ship a launch that cannot persist
        // an in-progress KYC session.
        let kycStore: KYCSessionStore
        do {
            kycStore = try KYCSessionStore()
        } catch {
            fatalError("KYCSessionStore could not initialize its protected directory: \(error)")
        }
        self.kycSessionStore = kycStore
        self.geoContext = GeoContext(locationProvider: self.locationProvider)
        let kycLogger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.identity,
            category: "identity.kyc"
        )
        self.kycUploader = KYCUploader(
            apiClient: self.apiClient,
            store: kycStore,
            logger: kycLogger
        )

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

    // MARK: - DEV-04 attestation preflight (D-09 graceful-skip mirror of preflightSecureEnclave)

    /// Preflight the App Attest entitlement. UNLIKE `preflightSecureEnclave`, this
    /// does NOT fatalError when the entitlement is missing — entitlement absence
    /// is recoverable (ship a fix, re-sign, re-upload TestFlight). D-09's
    /// graceful-skip contract routes a miss to `attestationStatus: "entitlementMissing"`
    /// at the `/device/register` call site so the backend decides policy (D-12).
    ///
    /// Returns an `AttestationEntitlementPreflightResult` enum (not `Bool`) to
    /// distinguish simulator-bypass from true device availability — the call
    /// site in `init` logs all three cases for operational visibility.
    ///
    /// Defaults mirror `preflightSecureEnclave`: tests inject explicit values
    /// to simulate production Release + device.
    static func preflightAttestationEntitlement(
        isSupported: Bool = DCAppAttestService.shared.isSupported,
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
    ) -> AttestationEntitlementPreflightResult {
        if isDebugBuild && isSimulatorBuild {
            // Simulator + DEBUG path uses SimulatorBypassAttestationService (D-10);
            // entitlement absence is expected and harmless.
            return .simulatorBypass
        }
        return isSupported ? .available : .missing
    }
}
