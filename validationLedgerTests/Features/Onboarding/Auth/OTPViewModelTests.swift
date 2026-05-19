// validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
// Phase 3 Plan 09 — AUTH-02 + AUTH-03 + D-02 + D-27.
// Phase 6 Plan 02 — DEV-04 first-login App Attest orchestration (STEP 5).
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.
//
// Phase 3 left this suite thin (compile-shape contract + initial-state + rateLimited
// gate). Phase 6 Plan 02 adds the behavioural coverage for the STEP 5 attestation
// orchestration: the verify → GET /device/challenge → POST /device/register sequence
// is now driven end-to-end through MockURLProtocol fixtures + a scriptable
// FakeAttestationService, asserting the D6-04 graceful-skip, D6-05 degrade-and-continue,
// and D6-06 challengeExpired refetch-and-retry-once postures plus the D6-07 PII
// source-grep.

import Testing
import Foundation
@testable import validationLedger

// `.serialized` — the STEP 5 behavioural tests drive the global
// `MockURLProtocol` handler registry. Swift Testing runs `@Test`s in parallel
// by default; without serialization sibling tests register `AttestBackend`
// handlers concurrently and stomp each other (the Phase 2 `.serialized @Suite`
// pattern for suites sharing `MockURLProtocol` global state — see WR-01).
@Suite("OTPViewModel — Retry-After countdown + D-27 7-step orchestration + DEV-04 first-login attestation (AUTH-02, AUTH-03, D-02, D-27, DEV-04)", .serialized)
@MainActor
struct OTPViewModelTests {

    // MARK: - Phase 3 compile-shape + gate contract

    @Test("Initial state is .idle")
    func initialState() {
        let vm = makeVM()
        #expect(vm.state == .idle)
    }

    @Test("verify gate — enabled when code is 6 digits + state is not rateLimited")
    func gateEnabledAtSixDigits() {
        let vm = makeVM()
        vm.code = "123"
        #expect(vm.verifyEnabled == false)
        vm.code = "123456"
        #expect(vm.verifyEnabled == true)
    }

    @Test("D-27 contract — OTPViewModel source uses BiometricService.evaluate and DeviceRegisterEndpoint in the verify flow")
    func sourceReferencesExpectedCollaborators() throws {
        let source = try Self.readSource("validationLedger/Features/Onboarding/Auth/OTPViewModel.swift")
        #expect(source.contains("OTPVerifyEndpoint"),
                "OTPViewModel must call OTPVerifyEndpoint (D-27 step 1)")
        #expect(source.contains("generateDeviceIdentityKeys"),
                "OTPViewModel must generate device/auth identity keys (D-27 steps 3-4)")
        #expect(source.contains("DeviceRegisterEndpoint"),
                "OTPViewModel must call DeviceRegisterEndpoint (D-27 step 5)")
        #expect(source.contains("biometric.evaluate"),
                "OTPViewModel must invoke biometric.evaluate (D-27 step 6)")
        #expect(source.contains("onAuthenticated"),
                "OTPViewModel must surface onAuthenticated callback (D-27 step 7)")
    }

    @Test("D-02 contract — OTPViewModel source pattern-matches NetworkError.rateLimited to drive countdown")
    func sourceHandlesRateLimited() throws {
        let source = try Self.readSource("validationLedger/Features/Onboarding/Auth/OTPViewModel.swift")
        #expect(source.contains("NetworkError.rateLimited"),
                "OTPViewModel must pattern-match NetworkError.rateLimited (D-02)")
        #expect(source.contains("Timer"),
                "OTPViewModel must drive a Timer-based countdown (D-02)")
    }

    // MARK: - DEV-04 — STEP 5 first-login attestation orchestration

    @Test("DEV-04 / D6-04 happy — .attested status sends a register payload with non-nil attestedKeyId + attestationObject")
    func attestedHappyPathSendsRealPayload() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))
        attest.nextAttestKey = .success(Data("real-attestation-object".utf8))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        let body = try #require(backend.lastRegisterBody, "register POST must have been sent")
        #expect(body["attestation_status"] as? String == "attested",
                "DEV-04: .attested status must reach the register payload")
        #expect(body["attested_key_id"] as? String == "real-key-id-abc",
                "DEV-04: a .attested register payload carries the real attestedKeyId")
        #expect(body["attestation_object"] != nil,
                "DEV-04: a .attested register payload carries the attestationObject")
        #expect(attest.generateKeyIfNeededCallCount == 1)
        #expect(attest.attestKeyCallCount == 1)
        // Login completes.
        if case .success = vm.state {} else {
            Issue.record("verify() must reach .success after a happy-path attestation; got \(vm.state)")
        }
    }

    @Test("DEV-04 / D6-01 — the captured /device/register trustTier is persisted to Keychain")
    func registerTrustTierPersistedToKeychain() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.registerTrustTier = "hardwareAttested"
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))

        let keychain = Self.freshKeychain()
        let vm = makeVM(attestation: attest, keychain: keychain)
        vm.code = "123456"
        await vm.verify()

        let store = AttestedKeyStore(keychain: keychain)
        #expect(try store.readTrustTier() == .hardwareAttested,
                "D6-01: the /device/register trustTier must be persisted to Keychain via writeTrustTier")
    }

    @Test("D6-04 graceful skip — .unsupported status sends attestationStatus=.unsupported with nil attestation fields; login completes")
    func unsupportedGracefulSkip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("", .unsupported))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        let body = try #require(backend.lastRegisterBody, "register POST must still be sent on graceful skip")
        #expect(body["attestation_status"] as? String == "unsupported",
                "D6-04: a non-.attested status flows through to the register payload")
        #expect(body["attested_key_id"] == nil,
                "D6-04: a graceful-skip payload omits attestedKeyId (D-09 omission)")
        #expect(body["attestation_object"] == nil,
                "D6-04: a graceful-skip payload omits attestationObject (D-09 omission)")
        #expect(attest.attestKeyCallCount == 0,
                "D6-04: a non-.attested status must NOT call attestKey")
        #expect(backend.challengeCount == 0,
                "D6-04: a non-.attested status must NOT fetch a challenge")
        #expect(Self.loginCompleted(vm.state),
                "D6-04: login must still complete on graceful skip; got \(vm.state)")
    }

    @Test("D6-04 graceful skip — .entitlementMissing also takes the skip path")
    func entitlementMissingGracefulSkip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("", .entitlementMissing))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        let body = try #require(backend.lastRegisterBody)
        #expect(body["attestation_status"] as? String == "entitlementMissing")
        #expect(body["attested_key_id"] == nil)
        #expect(body["attestation_object"] == nil)
        #expect(Self.loginCompleted(vm.state))
    }

    @Test("D6-05 degrade — GET /device/challenge errors → attestationStatus=.error, fields nil, register STILL posted, login completes")
    func challengeFetchFailureDegradesAndContinues() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.challengeFailsWith = 503     // transient server error on the challenge fetch
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        let body = try #require(backend.lastRegisterBody, "D6-05: register POST must STILL be sent after a challenge failure")
        #expect(body["attestation_status"] as? String == "error",
                "D6-05: a transient challenge failure degrades the payload to attestationStatus=.error")
        #expect(body["attested_key_id"] == nil,
                "D6-05: a degraded payload omits attestedKeyId")
        #expect(body["attestation_object"] == nil,
                "D6-05: a degraded payload omits attestationObject")
        #expect(Self.loginCompleted(vm.state),
                "D6-05: login is never blocked by a transient attestation failure; got \(vm.state)")
    }

    @Test("D6-05 degrade — attestKey throws → attestationStatus=.error, fields nil, register STILL posted, login completes")
    func attestKeyFailureDegradesAndContinues() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))
        attest.nextAttestKey = .failure(FakeAttestError.attestKeyFailed)

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        let body = try #require(backend.lastRegisterBody, "D6-05: register POST must STILL be sent after attestKey throws")
        #expect(body["attestation_status"] as? String == "error",
                "D6-05: an attestKey failure degrades the payload to attestationStatus=.error")
        #expect(body["attested_key_id"] == nil)
        #expect(body["attestation_object"] == nil)
        #expect(Self.loginCompleted(vm.state),
                "D6-05: login completes after an attestKey failure; got \(vm.state)")
    }

    @Test("D6-06 retry — challengeExpired on the FIRST register POST → refetch challenge, re-attest, retry once, login completes")
    func challengeExpiredRefetchesAndRetriesOnce() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.registerExpiredCount = 1     // first POST → challengeExpired, second → 200
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        #expect(backend.registerCount == 2,
                "D6-06: a challengeExpired register error triggers exactly one retry (2 total POSTs)")
        #expect(backend.challengeCount == 2,
                "D6-06: the retry refetches GET /device/challenge before re-attesting")
        #expect(attest.attestKeyCallCount == 2,
                "D6-06: the retry re-runs attestKey against the fresh challenge")
        #expect(Self.loginCompleted(vm.state),
                "D6-06: login completes after a successful retry; got \(vm.state)")
    }

    @Test("D6-06 second expiry surfaces — two consecutive challengeExpired responses → no second retry, state → .registerFailed")
    func secondChallengeExpirySurfaces() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.registerExpiredCount = 2     // both POSTs → challengeExpired
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()

        #expect(backend.registerCount == 2,
                "D6-06: a second consecutive challengeExpired is NOT retried again — exactly 2 POSTs")
        #expect(vm.state == .registerFailed,
                "D6-06: a second consecutive challengeExpired surfaces as .registerFailed; got \(vm.state)")
    }

    @Test("Pitfall 2 — retryRegister after .registerFailed re-runs verify() and produces a well-formed register payload")
    func retryRegisterIsIdempotent() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let backend = AttestBackend()
        backend.registerFailUntil = 1        // first POST → 500, then 200
        backend.install()

        let attest = FakeAttestationService()
        attest.nextGenerateKeyIfNeeded = .success(("real-key-id-abc", .attested))

        let vm = makeVM(attestation: attest)
        vm.code = "123456"
        await vm.verify()
        #expect(vm.state == .registerFailed,
                "first verify() must land in .registerFailed when register POST fails")

        // Re-run via retryRegister — the orchestration is idempotent.
        backend.lastRegisterBody = nil
        await vm.retryRegister()

        let body = try #require(backend.lastRegisterBody,
                                "retryRegister() must re-run verify() and re-POST /device/register")
        #expect(body["attestation_status"] as? String == "attested",
                "retryRegister() produces a well-formed attestation payload on the retry")
        #expect(body["device_public_key"] != nil,
                "retryRegister() produces a complete three-key register payload")
        #expect(Self.loginCompleted(vm.state),
                "retryRegister() completes login once the register POST succeeds; got \(vm.state)")
    }

    @Test("D6-07 PII — the STEP 5 attestation catch blocks contain no String(describing:) token")
    func attestationCatchesAreFreeOfStringDescribing() throws {
        let source = try Self.readSource("validationLedger/Features/Onboarding/Auth/OTPViewModel.swift")

        // Scope the grep to the attestation log calls: every attestation log event
        // is named with the `attestation_first_login` prefix (D6-07 / Pattern A).
        // Assert no such log call passes a `String(describing:` token in its fields.
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() {
            guard line.contains("attestation_first_login") else { continue }
            // Inspect the log call's immediate window (event name + fields argument
            // may wrap across a couple of lines).
            let windowEnd = min(index + 3, lines.count - 1)
            let window = lines[index...windowEnd].joined(separator: "\n")
            #expect(!window.contains("String(describing:"),
                    "D6-07: attestation log call near line \(index + 1) must NOT pass String(describing:) — PII discipline (T-06-02-01)")
            #expect(!window.contains(".localizedDescription"),
                    "D6-07: attestation log call near line \(index + 1) must NOT pass .localizedDescription")
            #expect(!window.contains(".userInfo"),
                    "D6-07: attestation log call near line \(index + 1) must NOT pass NSError.userInfo")
        }
        // Sanity: the attestation logging exists at all (so the grep is not vacuous).
        #expect(source.contains("attestation_first_login"),
                "STEP 5 must emit at least one attestation_first_login_* log event")
    }

    // MARK: - Helpers

    private func makeVM(
        attestation: any AttestationService = FakeAttestationService(),
        keychain: KeychainStore? = nil
    ) -> OTPViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let net = URLSessionNetworkClient(config: .mock, session: session)
        let api = APIClient(
            baseURL: URL(string: "https://mock.local")!,
            networkClient: net,
            requestInterceptors: [],
            responseInterceptors: []
        )
        let kc = keychain ?? Self.freshKeychain()
        let ks = SoftwareKeyStore()
        let bio = StubBio()
        let lock = DefaultSessionLockService(biometric: bio, keychain: kc)
        return OTPViewModel(
            otpSessionID: "sess-abc-123",
            apiClient: api,
            keychain: kc,
            keyStore: ks,
            biometric: bio,
            sessionLock: lock,
            attestationService: attestation,
            logger: NoOpLogger()
        )
    }

    private static func freshKeychain() -> KeychainStore {
        KeychainStore(service: "vl.test.otpvm.\(UUID().uuidString)")
    }

    /// `verify()` reaching `.success` is "login completed" — STEP 6/7 of verify()
    /// set `.success` before firing the onAuthenticated/onKYCRequired callbacks,
    /// so a `.success` state is the observable proof login was not blocked.
    private static func loginCompleted(_ state: OTPViewModel.State) -> Bool {
        if case .success = state { return true }
        return false
    }

    // MARK: - Source-path resolver (matches BiometricServiceTests helper, 3 hops → repo root)

    private static func repoRootURL(from filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        url.deleteLastPathComponent()   // drop OTPViewModelTests.swift
        url.deleteLastPathComponent()   // drop Auth/
        url.deleteLastPathComponent()   // drop Onboarding/
        url.deleteLastPathComponent()   // drop Features/
        url.deleteLastPathComponent()   // drop validationLedgerTests/
        return url
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Test fakes

@MainActor
private final class StubBio: BiometricService {
    nonisolated func currentDomainState() -> Data? { nil }
    func evaluate(reason: String, fallback: BiometricFallback) async throws {}
}

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}

private enum FakeAttestError: Error {
    case attestKeyFailed
}

/// A lock-guarded MockURLProtocol backend for the STEP 5 verify → challenge → register
/// sequence. Scripts per-call `/device/register` outcomes (challengeExpired / 5xx / 200),
/// records the register POST body + call counts, and serves a fixed OTPVerify + challenge.
///
/// `@unchecked Sendable` is sound: every mutable field is read/written behind `lock`,
/// and the MockURLProtocol handler closure (the only concurrent caller) goes through
/// the lock-guarded accessors.
private final class AttestBackend: @unchecked Sendable {
    private let lock = NSLock()

    // --- Scripted inputs (set before install()) ---
    /// Number of leading `/device/register` POSTs that respond with a `challengeExpired`
    /// error body (HTTP 400). After this count, the POST returns 200.
    var registerExpiredCount = 0
    /// Number of leading `/device/register` POSTs that respond with a generic 500.
    var registerFailUntil = 0
    /// When non-zero, GET /device/challenge responds with this status (transient failure).
    var challengeFailsWith: Int?
    /// trust_tier value baked into the 200 /device/register response body.
    var registerTrustTier = "hardwareAttested"

    // --- Recorded outputs ---
    private var _registerCount = 0
    private var _challengeCount = 0
    private var _lastRegisterBody: [String: Any]?

    var registerCount: Int { lock.withLock { _registerCount } }
    var challengeCount: Int { lock.withLock { _challengeCount } }
    var lastRegisterBody: [String: Any]? {
        get { lock.withLock { _lastRegisterBody } }
        set { lock.withLock { _lastRegisterBody = newValue } }
    }

    func install() {
        MockURLProtocol.register { [self] request in
            guard let path = request.url?.path else { return nil }
            switch path {
            case "/auth/otp/verify":
                return Self.jsonResponse(
                    request: request, status: 200,
                    json: #"{"session_token":"tok","role":"carrier","user_id":"u-1","kyc_status":"verified"}"#
                )

            case "/device/challenge":
                return lock.withLock {
                    _challengeCount += 1
                    if let failStatus = challengeFailsWith {
                        return Self.jsonResponse(request: request, status: failStatus,
                                                 json: #"{"error":"challenge service unavailable"}"#)
                    }
                    return Self.jsonResponse(
                        request: request, status: 200,
                        json: #"{"challenge":"Y2hhbGxlbmdlLW5vbmNlLWZvci10ZXN0aW5n","expires_at":"2026-04-22T12:01:00Z","nonce":"nonce-1"}"#
                    )
                }

            case "/device/register":
                return lock.withLock {
                    _registerCount += 1
                    _lastRegisterBody = Self.decodeJSONBody(request)
                    let n = _registerCount
                    if n <= registerExpiredCount {
                        return Self.jsonResponse(request: request, status: 400,
                                                 json: #"{"error_code":"challengeExpired"}"#)
                    }
                    if n <= registerFailUntil {
                        return Self.jsonResponse(request: request, status: 500,
                                                 json: #"{"error_code":"internalServerError"}"#)
                    }
                    return Self.jsonResponse(
                        request: request, status: 200,
                        json: #"{"device_id":"dev-1","registered_at":"2026-04-21T12:00:00Z","trust_tier":"\#(registerTrustTier)"}"#
                    )
                }

            default:
                return nil
            }
        }
    }

    // MARK: - Static helpers

    private static func jsonResponse(request: URLRequest, status: Int, json: String) -> (HTTPURLResponse, Data) {
        let url = request.url ?? URL(string: "https://mock.local")!
        let resp = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, Data(json.utf8))
    }

    /// Drain the request body — `URLProtocol` moves `httpBody` into `httpBodyStream`.
    private static func decodeJSONBody(_ request: URLRequest) -> [String: Any]? {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let bufferSize = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        } else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
