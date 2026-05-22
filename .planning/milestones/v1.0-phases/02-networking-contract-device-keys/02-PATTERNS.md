# Phase 2: Networking Contract & Device Keys — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 23 new/modified files
**Analogs found:** 23 / 23 (all have a direct in-repo analog or a RESEARCH.md sketch that is the authoritative pattern source — see Match Quality column)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Core/Networking/NetworkClient.swift` | core-impl (fix CR-01) | request-response | `Core/Networking/NetworkClient.swift` lines 26–37 (self — force-cast site) | exact (self-fix) |
| `Core/Networking/NetworkError.swift` | core-enum | transform | `Core/Storage/Keychain/KeychainStore.swift` lines 8–13 (`KeychainError`) | role-match |
| `Core/Networking/APIEndpoint.swift` | core-protocol | request-response | `Core/KeyStore/KeyStoreProtocol.swift` lines 15–18 | role-match |
| `Core/Networking/APIClient.swift` | core-service | request-response | `Core/Networking/NetworkClient.swift` (protocol + impl pattern) | role-match |
| `Core/Networking/Endpoints/OTPRequestEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/KYCUploadInitEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Endpoints/KYCStatusEndpoint.swift` | core-model | request-response | `02-RESEARCH.md` Pattern 1 lines 359–367 | research-sketch |
| `Core/Networking/Interceptors/RequestInterceptor.swift` | core-protocol | request-response | `Core/KeyStore/KeyStoreProtocol.swift` (protocol shape) | role-match |
| `Core/Networking/Interceptors/IdempotencyInterceptor.swift` | core-impl | request-response | `02-RESEARCH.md` Pattern 5 lines 694–705 | research-sketch |
| `Core/Networking/Interceptors/RetryInterceptor.swift` | core-impl | request-response | `02-RESEARCH.md` Pattern 6 lines 726–783 | research-sketch |
| `Core/Networking/Mock/MockURLProtocol.swift` | test-scaffold (extend) | request-response | `Core/Networking/MockURLProtocol.swift` lines 9–40 (self — WR-01 fix + registry) | exact (extend self) |
| `Core/Networking/Mock/MockFixture.swift` | core-model | transform | `02-RESEARCH.md` Pattern 2 lines 421–443 | research-sketch |
| `Core/Networking/CertificatePinning/PinnedSPKIs.swift` | core-config | static | `02-RESEARCH.md` Pattern 4 lines 549–570 | research-sketch |
| `Core/Networking/CertificatePinning/SPKIHasher.swift` | core-util | transform | `02-RESEARCH.md` Pattern 4 lines 622–649 | research-sketch |
| `Core/Networking/CertificatePinning/PinningSessionDelegate.swift` | core-impl (fill in) | event-driven | `Core/Networking/CertificatePinning/PinningSessionDelegate.swift` lines 10–22 (self skeleton) | exact (fill in self) |
| `Core/KeyStore/KeyStoreProtocol.swift` | core-protocol (extend) | request-response | `Core/KeyStore/KeyStoreProtocol.swift` lines 15–18 (self) | exact (extend self) |
| `Core/KeyStore/SoftwareKeyStore.swift` | core-impl (extend) | request-response | `Core/KeyStore/SoftwareKeyStore.swift` lines 8–19 (self) | exact (extend self) |
| `Core/KeyStore/SecureEnclaveKeyStore.swift` | core-impl (fill in) | request-response | `Core/KeyStore/SoftwareKeyStore.swift` lines 8–19 (structural analog) | role-match |
| `Core/Identity/DeviceFingerprint.swift` | core-service | CRUD (Keychain read/write) | `Core/Storage/Keychain/KeychainStore.swift` lines 43–53 (get pattern), lines 24–41 (upsert pattern) | role-match |
| `App/AppContainer.swift` | composition-root (extend) | request-response | `App/AppContainer.swift` lines 50–58 (self — session factory site) | exact (extend self) |
| `App/Environment.swift` | config (extend) | static | `App/Environment.swift` lines 14–29 (self) | exact (extend self) |
| `validationLedgerTests/Networking/APIClientEndpointTests.swift` | test-unit | assertion | `validationLedgerTests/Networking/MockURLProtocolTests.swift` lines 14–25 | exact |
| `validationLedgerTests/Networking/IdempotencyInterceptorTests.swift` | test-unit | assertion | `validationLedgerTests/Storage/KeychainStoreTests.swift` lines 6–48 (Swift Testing struct shape) | role-match |
| `validationLedgerTests/Networking/RetryInterceptorTests.swift` | test-unit | assertion | `validationLedgerTests/Storage/KeychainStoreTests.swift` lines 6–48 | role-match |
| `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift` | test-unit | assertion | `validationLedgerTests/Networking/MockURLProtocolTests.swift` lines 1–26 | exact |
| `validationLedgerTests/Networking/CertificatePinningTests.swift` | test-unit | assertion | `validationLedgerTests/Networking/MockURLProtocolTests.swift` lines 14–25 | role-match |
| `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` | test-device | assertion | `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` lines 15–31 | exact |
| `validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift` | test-device | assertion | `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` lines 15–31 | role-match |
| `docs/cert-rotation.md` | doc (expand) | static | `docs/cert-rotation.md` (self skeleton) | exact (fill in self) |

---

## Pattern Assignments

### `Core/Networking/NetworkClient.swift` — CR-01 force-cast fix

**Role:** core-impl (bug fix)
**Analog:** Self — `Core/Networking/NetworkClient.swift` lines 26–37

The force-cast `response as! HTTPURLResponse` on lines 28 and 35 must become a guarded cast that throws. The error case is `NetworkError.unexpectedResponseType`.

**Current broken pattern** (lines 26–37):
```swift
func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(from: url)
    return (data, response as! HTTPURLResponse)  // CR-01: force-cast
}

func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = body
    let (data, response) = try await session.data(for: req)
    return (data, response as! HTTPURLResponse)  // CR-01: force-cast
}
```

**Replacement pattern:**
```swift
func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse else {
        throw NetworkError.unexpectedResponseType(response)
    }
    return (data, http)
}
```

Apply identically to `post`. The `NetworkError.unexpectedResponseType` case is defined in `Core/Networking/NetworkError.swift` (new file, Pattern Assignment below).

---

### `Core/Networking/NetworkError.swift` — typed error enum

**Role:** core-enum
**Analog:** `Core/Storage/Keychain/KeychainStore.swift` lines 8–13

Copy the `KeychainError` enum shape — `public enum`, `Error & Sendable` conformance, named cases, one associated value where diagnostic context is useful.

**Copy this structural pattern** (from `KeychainStore.swift` lines 8–13):
```swift
public enum KeychainError: Error, Sendable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
}
```

**Apply to `NetworkError`:**
```swift
// Core/Networking/NetworkError.swift
public enum NetworkError: Error, Sendable {
    case unexpectedResponseType(URLResponse)   // CR-01 fix site
    case httpError(statusCode: Int, data: Data)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case retriesExhausted
    case pinningFailed
}
```

**Import block:** `import Foundation` only. No `Security` or `CryptoKit` needed here.

---

### `Core/Networking/APIEndpoint.swift` — typed endpoint protocol

**Role:** core-protocol
**Analog:** `Core/KeyStore/KeyStoreProtocol.swift` lines 1–18

The `KeyStoreProtocol` establishes the project convention for core protocols: `public protocol`, `AnyObject` (or `Sendable` for value-type protocols), minimal surface, associated types only where necessary. `APIEndpoint` follows the same header style but is a value-type protocol (structs conform, not classes).

**Copy header + public/internal access pattern** (from `KeyStoreProtocol.swift` lines 1–18):
```swift
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
```

**Apply to `APIEndpoint`** (from `02-RESEARCH.md` Pattern 1 lines 342–357):
```swift
// Core/Networking/APIEndpoint.swift
// Protocol for typed M1 endpoints. Conforming structs carry path + method + body/response types.
// APIClient.request(_:) is the one call site; mock fixtures key off path + method.

import Foundation

public protocol APIEndpoint<Response>: Sendable {
    associatedtype RequestBody: Encodable & Sendable
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: RequestBody? { get }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
```

---

### `Core/Networking/Endpoints/*.swift` — seven M1 endpoint structs

**Role:** core-model (one file per endpoint)
**Analog:** `02-RESEARCH.md` Pattern 1 lines 359–367 (`OTPRequestEndpoint` sketch)

All seven endpoint files follow the same struct shape. Copy verbatim from the research sketch and adapt path / body / response types per endpoint.

**Canonical shape** (from `02-RESEARCH.md` Pattern 1 lines 359–367):
```swift
// Core/Networking/Endpoints/OTPRequestEndpoint.swift
public struct OTPRequestEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable { public let phone: String }
    public struct Response: Decodable, Sendable {
        public let otpSessionID: String
        public let expiresInSeconds: Int
    }
    public let path = "/auth/otp/request"
    public let method: HTTPMethod = .post
    public let body: RequestBody?
    public init(phone: String) { self.body = RequestBody(phone: phone) }
}
```

**Naming rule:** File name = type name. Type name = `{Resource}{Verb}Endpoint`. Nested `RequestBody` and `Response` types declared inside the struct, not at file scope — this avoids global namespace collision between similarly-named types across endpoints.

**Import block:** `import Foundation` only.

**For GET endpoints** (e.g., `KYCStatusEndpoint`): `RequestBody` is `Never` (or a purpose-built empty struct that's `Encodable`); `body` always returns `nil`. Do not force `Never` if it complicates the protocol conformance — a private empty `struct EmptyBody: Encodable, Sendable {}` is fine.

---

### `Core/Networking/APIClient.swift` — typed facade over NetworkClient

**Role:** core-service
**Analog:** `Core/Networking/NetworkClient.swift` (structural analog — protocol + class pattern)

`NetworkClient` defines the raw-data transport protocol and a concrete `URLSessionNetworkClient`. `APIClient` wraps it and adds typed encoding/decoding. Follow the same pattern: final class, initializer-injected dependencies, no singletons.

**Copy the class/init shape** (from `NetworkClient.swift` lines 17–24):
```swift
final class URLSessionNetworkClient: NetworkClient, @unchecked Sendable {
    private let session: URLSession
    private let config: NetworkConfig

    init(config: NetworkConfig, session: URLSession) {
        self.config = config
        self.session = session
    }
    // ...
}
```

**Apply to `APIClient`** (from `02-RESEARCH.md` Pattern 3 lines 474–494 + §Architectural Responsibility Map):
```swift
// Core/Networking/APIClient.swift
import Foundation

public final class APIClient: Sendable {
    private let baseURL: URL
    private let networkClient: any NetworkClient
    private let requestInterceptors: [any RequestInterceptor]
    private let responseInterceptors: [any ResponseInterceptor]

    public init(
        baseURL: URL,
        networkClient: any NetworkClient,
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = []
    ) {
        self.baseURL = baseURL
        self.networkClient = networkClient
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
    }

    public func request<E: APIEndpoint>(_ endpoint: E) async throws -> E.Response {
        // 1. Build URLRequest from endpoint
        // 2. Apply request interceptors in order
        // 3. Apply response interceptors (RetryInterceptor wraps the send)
        // 4. Decode response into E.Response
        // ...
    }
}
```

**Encode/decode:** Use `JSONEncoder` / `JSONDecoder` with `.convertFromSnakeCase` / `.convertToSnakeCase` key strategies — matches the backend convention typical for Node/Python APIs. Declare these as static lets on `APIClient`.

**Error propagation:** All errors are rethrown as `NetworkError` variants. The caller never sees raw `DecodingError`.

---

### `Core/Networking/Interceptors/RequestInterceptor.swift` — interceptor protocols

**Role:** core-protocol
**Analog:** `Core/KeyStore/KeyStoreProtocol.swift` lines 15–18 (protocol shape convention)

Two protocols in one file (kept together because they form a conceptual pair):

**Copy from `02-RESEARCH.md` Pattern 5 lines 682–692:**
```swift
// Core/Networking/Interceptors/RequestInterceptor.swift
public protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

public protocol ResponseInterceptor: Sendable {
    func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse)
}
```

`RequestInterceptor` mutates a `URLRequest` before send (header injection).
`ResponseInterceptor` wraps the entire send call (retry, circuit-breaker).
Separating the protocols keeps `IdempotencyInterceptor` (header-only, `RequestInterceptor`) from needing the more complex `ResponseInterceptor` signature.

---

### `Core/Networking/Interceptors/IdempotencyInterceptor.swift`

**Role:** core-impl (RequestInterceptor)
**Analog:** `02-RESEARCH.md` Pattern 5 lines 694–705

**Copy verbatim:**
```swift
// Core/Networking/Interceptors/IdempotencyInterceptor.swift
public struct IdempotencyInterceptor: RequestInterceptor {
    public init() {}
    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        guard let method = request.httpMethod,
              method == "POST" || method == "PUT" else { return request }
        // Only inject if absent — caller may have set it (explicit replay path for Phase 5).
        guard request.value(forHTTPHeaderField: "Idempotency-Key") == nil else { return request }
        var req = request
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        return req
    }
}
```

**Import block:** `import Foundation` only.

**Struct, not class:** The interceptors have no mutable state; `struct` is correct and `Sendable` for free.

---

### `Core/Networking/Interceptors/RetryInterceptor.swift`

**Role:** core-impl (ResponseInterceptor)
**Analog:** `02-RESEARCH.md` Pattern 6 lines 726–783

**Copy verbatim** (the research sketch is production-ready):
```swift
// Core/Networking/Interceptors/RetryInterceptor.swift
public struct RetryInterceptor: ResponseInterceptor {
    private let maxRetries: Int
    private let baseDelayMs: UInt64
    private let ceilingMs: UInt64

    public init(maxRetries: Int = 3, baseDelayMs: UInt64 = 500, ceilingMs: UInt64 = 4000) {
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.ceilingMs = ceilingMs
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        guard request.httpMethod == "GET" else { return try await send(request) }
        // ...retry loop with delayForAttempt + isRetryable...
    }
}
```

Full sketch including `delayForAttempt` and `isRetryable` is in `02-RESEARCH.md` lines 765–783.

**Import block:** `import Foundation` only (`Task.sleep` is in `_Concurrency` which Swift imports implicitly).

---

### `Core/Networking/Mock/MockURLProtocol.swift` — WR-01 fix + registry

**Role:** test-scaffold (extend existing file)
**Analog:** Self — `Core/Networking/MockURLProtocol.swift` lines 9–40

The Phase 1 file is the starting point. The entire file is REPLACED (not line-patched) with the WR-01-fixed version. Two changes relative to Phase 1:
1. Replace the bare `public static var handlers` array with a `NSLock`-guarded pair (`handlersLock` + `_handlers`).
2. Add `register(_:)` and `reset()` public class methods so tests use the explicit API instead of directly mutating the array.

**Phase 1 pattern to REMOVE** (lines 10):
```swift
public static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)?] = [defaultPingHandler]
```

**Replacement pattern** (from `02-RESEARCH.md` Pattern 2 lines 382–443):
```swift
public final class MockURLProtocol: URLProtocol {
    public typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)?

    private static let handlersLock = NSLock()
    private static var _handlers: [Handler] = []

    public static func register(_ handler: @escaping Handler) {
        handlersLock.withLock { _handlers.append(handler) }
    }

    public static func reset() {
        handlersLock.withLock { _handlers.removeAll() }
    }

    private static var currentHandlers: [Handler] {
        handlersLock.withLock { _handlers }
    }
    // ...rest of startLoading / stopLoading unchanged in structure...
}
```

The Phase 1 `defaultPingHandler` for `/ping` is REMOVED — each test registers its own fixture via `MockURLProtocol.register(_:)` and calls `MockURLProtocol.reset()` before registering. No global default fixtures survive into Phase 2.

---

### `Core/Networking/Mock/MockFixture.swift`

**Role:** core-model (fixture container)
**Analog:** `02-RESEARCH.md` Pattern 2 lines 421–443 (`registerFixture` extension sketch)

This is a thin namespace for the `registerFixture` convenience. It is a Swift `extension` on `MockURLProtocol`, placed in a separate file to keep the main `MockURLProtocol.swift` focused on the URLProtocol mechanics.

**Copy from `02-RESEARCH.md` Pattern 2 lines 421–443:**
```swift
// Core/Networking/Mock/MockFixture.swift
extension MockURLProtocol {
    public static func registerFixture<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data
    ) {
        register { request in
            guard request.url?.path == path,
                  request.httpMethod == method.rawValue else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }
    }
}
```

JSON fixture files (`*.json`) live in `Core/Networking/Mock/Fixtures/` and are loaded from the test bundle, not from the main app bundle.

---

### `Core/Networking/CertificatePinning/PinnedSPKIs.swift`

**Role:** core-config (compile-time constants)
**Analog:** `02-RESEARCH.md` Pattern 4 lines 549–570

No in-repo analog — this pattern (compile-time SPKI constants baked into the binary) is new to the project. The research sketch is authoritative.

**Copy verbatim** (from `02-RESEARCH.md` Pattern 4 lines 549–570):
```swift
// Core/Networking/CertificatePinning/PinnedSPKIs.swift
public struct PinnedSPKIs: Sendable {
    public let primary: String   // Base64-encoded SHA-256 of SubjectPublicKeyInfo (DER)
    public let backup: String

    public static let staging = PinnedSPKIs(
        primary: "PHASE2-TODO-STAGING-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-STAGING-BACKUP-SPKI-SHA256-BASE64"
    )
    public static let release = PinnedSPKIs(
        primary: "PHASE2-TODO-RELEASE-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-RELEASE-BACKUP-SPKI-SHA256-BASE64"
    )
    public static var current: PinnedSPKIs {
        #if DEBUG
        return .staging
        #else
        return .release
        #endif
    }
}
```

`PHASE2-TODO` markers are intentional — real SPKI hashes cannot be filled in until the backend TLS certificate exists. The `docs/cert-rotation.md` runbook (also Phase 2 scope) documents the openssl extraction procedure for when real hashes are available.

**Do NOT put hashes in Info.plist or JSON.** Compile-time Swift constants in the binary are the security requirement (see `02-RESEARCH.md` §Alternatives Considered, NSPinnedDomains entry).

---

### `Core/Networking/CertificatePinning/SPKIHasher.swift`

**Role:** core-util (transform: SecCertificate → SHA-256 Base64 string)
**Analog:** `02-RESEARCH.md` Pattern 4 lines 622–649

No in-repo analog. Copy verbatim from the research sketch.

**Copy verbatim** (from `02-RESEARCH.md` Pattern 4 lines 622–649):
```swift
// Core/Networking/CertificatePinning/SPKIHasher.swift
import Foundation
import Security
import CryptoKit

public enum SPKIHasher {
    private static let ecP256ASN1Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    public static func spkiSHA256Base64(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        var spki = Data()
        spki.append(contentsOf: ecP256ASN1Header)
        spki.append(keyData)
        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }
}
```

**Import block:** `Foundation`, `Security`, `CryptoKit` — all three are required.

**Note on ASN.1 header:** The 26-byte header is specific to EC P-256 keys. If the backend serves RSA certs, a different header is needed. Flag for backend team confirmation. Do not generalize in Phase 2 — add an `algorithm` parameter in Phase 4 if needed.

---

### `Core/Networking/CertificatePinning/PinningSessionDelegate.swift` — fill in skeleton

**Role:** core-impl (URLSessionDelegate, event-driven challenge)
**Analog:** Self — `Core/Networking/CertificatePinning/PinningSessionDelegate.swift` lines 10–22 (Phase 1 skeleton)

The skeleton already has the correct class declaration, `NSObject` inheritance, `URLSessionDelegate` conformance, and the challenge callback signature. Phase 2 replaces only the `completionHandler(.performDefaultHandling, nil)` placeholder body.

**Phase 1 skeleton to KEEP** (lines 10–22):
```swift
public final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    public override init() { super.init() }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Phase 2 replaces this body
        completionHandler(.performDefaultHandling, nil)
    }
}
```

**Add `pins` property and replace `override init` with designated init** (from `02-RESEARCH.md` Pattern 4 lines 577–616):
```swift
public final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    private let pins: PinnedSPKIs
    public init(pins: PinnedSPKIs) { self.pins = pins; super.init() }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // 1. Evaluate chain + hostname + expiry
        // 2. Extract leaf SPKI hash via SPKIHasher
        // 3. Accept if hash == pins.primary || hash == pins.backup
        // 4. Reject otherwise (.cancelAuthenticationChallenge)
    }
}
```

Full implementation is in `02-RESEARCH.md` Pattern 4 lines 577–616.

**Critical invariant:** `PinningSessionDelegate` is ONLY installed on the `.live` URLSession. The mock session (`.mock` config in `AppContainer`) must never receive `PinningSessionDelegate` — it would reject `https://mock.local` with a pinning failure. This gate lives in `AppContainer.makeSession(networkConfig:)`.

---

### `Core/KeyStore/KeyStoreProtocol.swift` — extend with Phase 2 surface

**Role:** core-protocol (extend existing)
**Analog:** Self — `Core/KeyStore/KeyStoreProtocol.swift` lines 15–18

The Phase 1 protocol has two methods. Phase 2 adds two more. Keep the existing methods unchanged — no callers break.

**Current Phase 1 protocol** (lines 15–18):
```swift
public protocol KeyStoreProtocol: AnyObject, Sendable {
    func sign(_ data: Data) throws -> Data
    func publicKeyRepresentation() throws -> Data
}
```

**Phase 2 extension** (from `02-RESEARCH.md` Pattern 7 lines 936–944):
```swift
public protocol KeyStoreProtocol: AnyObject, Sendable {
    func sign(_ data: Data) throws -> Data
    func publicKeyRepresentation() throws -> Data

    // Phase 2 additions:
    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data)
    func signWithAuthorization(_ data: Data) throws -> Data
}
```

Also extend `KeyStoreError` (lines 9–13) with the new `keyGenerationFailed` case:
```swift
public enum KeyStoreError: Error, Sendable {
    case notImplemented
    case signingFailed
    case keyUnavailable
    case keyGenerationFailed(CFError?)   // Phase 2 addition
}
```

---

### `Core/KeyStore/SoftwareKeyStore.swift` — extend to match new protocol surface

**Role:** core-impl (extend existing)
**Analog:** Self — `Core/KeyStore/SoftwareKeyStore.swift` lines 8–19

The Phase 1 `SoftwareKeyStore` uses a single `P256.Signing.PrivateKey`. Phase 2 needs two keys (matching the two-key pattern on device). Add a second `authorizationPrivateKey` property and implement the two new protocol methods.

**Phase 1 pattern to preserve** (lines 8–19):
```swift
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
```

**Phase 2 additions:**
```swift
final class SoftwareKeyStore: KeyStoreProtocol {
    private let devicePrivateKey = P256.Signing.PrivateKey()       // deviceKey slot
    private let authPrivateKey = P256.Signing.PrivateKey()         // authorizationKey slot

    func sign(_ data: Data) throws -> Data {
        let signature = try devicePrivateKey.signature(for: data)
        return signature.rawRepresentation
    }

    func publicKeyRepresentation() throws -> Data {
        devicePrivateKey.publicKey.rawRepresentation
    }

    func generateDeviceIdentityKeys() throws -> (devicePublicKey: Data, authorizationPublicKey: Data) {
        // SoftwareKeyStore: keys are already generated at init; just return their representations.
        return (
            devicePrivateKey.publicKey.rawRepresentation,
            authPrivateKey.publicKey.rawRepresentation
        )
    }

    func signWithAuthorization(_ data: Data) throws -> Data {
        // No biometric prompt on simulator — sign directly.
        let signature = try authPrivateKey.signature(for: data)
        return signature.rawRepresentation
    }
}
```

---

### `Core/KeyStore/SecureEnclaveKeyStore.swift` — fill in Phase 1 stub

**Role:** core-impl (fill in fatalError stub)
**Analog:** `Core/KeyStore/SoftwareKeyStore.swift` lines 8–19 (structural shape); `02-RESEARCH.md` Pattern 7 lines 804–933 (full implementation)

The Phase 1 file has the correct class declaration and `fatalError` stubs. Replace the stubs with the real implementation. Do NOT change the class name, access level, or file header comment style.

**Phase 1 stub to REPLACE** (lines 8–15):
```swift
final class SecureEnclaveKeyStore: KeyStoreProtocol {
    func sign(_ data: Data) throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
    func publicKeyRepresentation() throws -> Data {
        fatalError("SecureEnclaveKeyStore not implemented until Phase 2 (DEV-01/02/03)")
    }
}
```

**Full implementation pattern** is in `02-RESEARCH.md` Pattern 7 lines 804–933. Key structural points:
- Inner `enum Keyslot` (`.device`, `.authorization`) carries the `kSecAttrApplicationTag` data per slot — avoids stringly-typed tag construction at call sites.
- `generateKey(slot:flags:)` private method takes `SecAccessControlCreateFlags` — called twice in `generateDeviceIdentityKeys()` with different flag sets.
- `loadPrivateKey(slot:)` uses `SecItemCopyMatching` to retrieve the `SecKey` reference from the Secure Enclave by tag (the key material never leaves the enclave).
- `sign(data:slot:)` uses `SecKeyCreateSignature` with `.ecdsaSignatureMessageX962SHA256`.

**Import block:** `Foundation`, `Security`, `CryptoKit` (for type interop, even though key generation uses Security framework directly).

**Do NOT use `SecureEnclave.P256.Signing.PrivateKey` (CryptoKit convenience wrapper):** It does not expose `.biometryCurrentSet` ACL. Use `SecKeyCreateRandomKey` + `SecAccessControlCreateWithFlags` as shown in the research sketch. See `02-RESEARCH.md` §Alternatives Considered, CryptoKit row.

---

### `Core/Identity/DeviceFingerprint.swift`

**Role:** core-service (new file, new directory `Core/Identity/`)
**Analog:** `Core/Storage/Keychain/KeychainStore.swift` lines 43–53 (get pattern) + lines 24–41 (upsert pattern)

`DeviceFingerprint.current(keychain:)` is a static factory that reads or generates the install UUID from Keychain — the same upsert-on-read pattern as `KeychainStore.set(_:for:accessibility:)` but calling `KeychainStore.get` first.

**Copy the upsert-read pattern** (from `KeychainStore.swift` lines 43–53):
```swift
public func get(_ key: KeychainKey) throws -> Data {
    var query = baseQuery(for: key)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    guard let data = item as? Data else { throw KeychainError.invalidData }
    return data
}
```

**Apply the try? + generate-and-persist pattern** (from `02-RESEARCH.md` Pattern 8 lines 965–985):
```swift
// Core/Identity/DeviceFingerprint.swift
import UIKit

public struct DeviceFingerprint: Encodable, Sendable {
    public let model: String
    public let iosVersion: String
    public let installUUID: String

    public static func current(keychain: KeychainStore) throws -> DeviceFingerprint {
        let installUUIDKey = KeychainKey(rawValue: "device.install_uuid")
        let installUUID: String
        if let existing = try? keychain.get(installUUIDKey),
           let decoded = String(data: existing, encoding: .utf8) {
            installUUID = decoded
        } else {
            installUUID = UUID().uuidString
            try keychain.set(
                Data(installUUID.utf8),
                for: installUUIDKey,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
        return DeviceFingerprint(
            model: UIDevice.current.modelIdentifier(),
            iosVersion: UIDevice.current.systemVersion,
            installUUID: installUUID
        )
    }
}
```

`UIDevice.modelIdentifier()` extension using `utsname()` is also in `02-RESEARCH.md` Pattern 8 lines 988–996.

**Import block:** `UIKit` (for `UIDevice`). No `Foundation` import needed — `UIKit` re-exports it.

**Keychain accessibility:** `.afterFirstUnlockThisDeviceOnly` — same as used in `KeychainStoreTests.swift` lines 13 and 27. This is the correct profile for device-scoped data that must survive a reboot without user unlock.

---

### `App/AppContainer.swift` — URLSession factory switch (NET-03)

**Role:** composition-root (extend existing)
**Analog:** Self — `App/AppContainer.swift` lines 50–58 (current session construction site)

Phase 2 extracts the inline session construction into a private static `makeSession(networkConfig:)` method and adds `APIClient` as a stored property. The keyStore gate (`#if DEBUG && targetEnvironment(simulator)`) is NOT touched.

**Current Phase 1 session construction** (lines 50–58):
```swift
let sessionConfig = URLSessionConfiguration.ephemeral
#if DEBUG
sessionConfig.protocolClasses = [MockURLProtocol.self]
#endif
self.networkClient = URLSessionNetworkClient(
    config: .mock,
    session: URLSession(configuration: sessionConfig)
)
```

**Replacement pattern** (from `02-RESEARCH.md` Pattern 3 lines 474–531):
```swift
// In AppContainer.init(env:):
let session = Self.makeSession(networkConfig: Self.defaultNetworkConfig(env: env))
let networkClient = URLSessionNetworkClient(config: networkConfig, session: session)
let interceptors: [any RequestInterceptor] = [
    IdempotencyInterceptor(),
    RetryInterceptor(maxRetries: 3),
]
self.apiClient = APIClient(
    baseURL: networkConfig.baseURL ?? URL(string: "https://mock.local")!,
    networkClient: networkClient,
    requestInterceptors: interceptors
)

// Private static helpers:
private static func defaultNetworkConfig(env: Environment) -> NetworkConfig {
    #if DEBUG
    return .mock
    #else
    guard let baseURL = env.apiBaseURL else {
        fatalError("Release build requires Environment.apiBaseURL — fill in WR-06 before Release build")
    }
    return .live(baseURL: baseURL)
    #endif
}

private static func makeSession(networkConfig: NetworkConfig) -> URLSession {
    switch networkConfig {
    case .mock:
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    case .live:
        return URLSession(
            configuration: .default,
            delegate: PinningSessionDelegate(pins: PinnedSPKIs.current),
            delegateQueue: nil
        )
    }
}
```

**Invariant to preserve:** `PinningSessionDelegate` is ONLY in the `.live` branch. The `.mock` branch must not install it. The `logger.info(event: .init("app_container_init"), ...)` call at line 62 is preserved as-is.

---

### `App/Environment.swift` — extend with PHASE-2-TODO marker

**Role:** config (extend existing)
**Analog:** Self — `App/Environment.swift` lines 14–29

Phase 1 already has `apiBaseURL: URL?` as a property (`nil` in both DEBUG and release). Phase 2 adds a `PHASE-2-TODO` comment and no functional change (real URLs depend on the backend GSD project). The `NetworkConfig` extension on `App/Environment.swift` is NOT needed here — `NetworkConfig.baseURL` is on `NetworkConfig` itself (see `AppContainer` pattern above).

**Current pattern to preserve** (lines 14–29):
```swift
public static let current: Environment = {
    #if DEBUG
    return Environment(
        name: "debug",
        keychainAccessGroup: nil,
        apiBaseURL: nil               // Phase 1: mock network only
    )
    #else
    return Environment(
        name: "release",
        keychainAccessGroup: nil,
        apiBaseURL: nil
    )
    #endif
}()
```

**Phase 2 update:** Replace the `// Phase 1: mock network only` comment with `// PHASE-2-TODO: set to staging URL once backend GSD project ships (WR-06)`. No functional change.

---

## Test Pattern Assignments

### `validationLedgerTests/Networking/APIClientEndpointTests.swift`

**Role:** test-unit (NET-01 + NET-02)
**Analog:** `validationLedgerTests/Networking/MockURLProtocolTests.swift` lines 1–26

Follow the same Swift Testing structure: `@Suite` with string label, `@Test` per scenario, `async throws` for async tests.

**Copy the setup pattern** (from `MockURLProtocolTests.swift` lines 14–25):
```swift
@Test("GET /ping fixture returns 200 + {\"ok\":true}")
func pingFixture() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    let url = URL(string: "https://mock.local/ping")!
    let (data, response) = try await session.data(from: url)
    let http = response as! HTTPURLResponse
    #expect(http.statusCode == 200)
}
```

**Apply to endpoint tests:**
```swift
@Suite("APIClient — OTP endpoints", .serialized)   // .serialized because MockURLProtocol.handlers is mutated
struct APIClientOTPTests {
    @Test("OTP request success decodes typed model")
    func otpRequestSuccess() async throws {
        MockURLProtocol.reset()
        // load fixture JSON from test bundle
        // MockURLProtocol.registerFixture(for: OTPRequestEndpoint.self, ...)
        // let resp = try await client.request(OTPRequestEndpoint(phone: "+14155550129"))
        // #expect(resp.otpSessionID == ...)
    }
}
```

**Every suite that mutates `MockURLProtocol.handlers` MUST use `.serialized`.** This is mandatory (WR-01 fix rationale — see `02-RESEARCH.md` Pattern 2).

---

### `validationLedgerTests/Networking/IdempotencyInterceptorTests.swift`

**Role:** test-unit (NET-04)
**Analog:** `validationLedgerTests/Storage/KeychainStoreTests.swift` lines 6–48

`KeychainStoreTests` is the project's best example of a focused unit test suite: `@Suite` string + `struct`, multiple `@Test` methods, `throws` (or `async throws`), `#expect` for positive assertions, `#expect(throws:)` for error cases.

**Copy the test struct shape** (from `KeychainStoreTests.swift` lines 6–12):
```swift
@Suite("KeychainStore — SecItem round-trip (Phase 1 simulator; device equivalent in DeviceTests)")
struct KeychainStoreTests {
    @Test("set → get round-trips Data")
    func setGet() throws { ... }
}
```

**Apply to `IdempotencyInterceptorTests`:**
```swift
@Suite("IdempotencyInterceptor — header injection")
struct IdempotencyInterceptorTests {
    @Test("injects Idempotency-Key on POST")
    func injectsOnPOST() async throws { ... }

    @Test("injects Idempotency-Key on PUT")
    func injectsOnPUT() async throws { ... }

    @Test("does NOT inject on GET")
    func noInjectionOnGET() async throws { ... }

    @Test("does NOT overwrite existing Idempotency-Key")
    func doesNotOverwrite() async throws { ... }
}
```

Do NOT assert the exact UUID value — only assert that the header is present (or absent). The `UUID()` output is non-deterministic.

---

### `validationLedgerTests/Networking/RetryInterceptorTests.swift`

**Role:** test-unit (NET-05)
**Analog:** `validationLedgerTests/Storage/KeychainStoreTests.swift` lines 6–48

Parameterized `@Test` is the right approach for status-code coverage. Swift Testing supports `@Test(arguments:)`:

```swift
@Suite("RetryInterceptor — GET retry gate")
struct RetryInterceptorTests {
    @Test("retries on 5xx status codes", arguments: [500, 502, 503, 504])
    func retriesOn5xx(statusCode: Int) async throws { ... }

    @Test("does NOT retry on POST", arguments: ["POST", "PUT", "DELETE"])
    func noRetryOnNonGET(method: String) async throws { ... }
}
```

This follows the same structural pattern as `KeychainStoreTests` but uses parameterized arguments. No `MockURLProtocol` handler mutation here — use a direct throwing closure as the `send` argument to `RetryInterceptor.intercept(send:request:)`.

---

### `validationLedgerTests/Networking/MockURLProtocolRegistryTests.swift`

**Role:** test-unit (WR-01 validation)
**Analog:** `validationLedgerTests/Networking/MockURLProtocolTests.swift` lines 1–26

The Phase 1 `MockURLProtocolTests` is the direct structural template. Phase 2's registry test replaces direct array mutation tests with `register`/`reset` API tests.

**Copy the Phase 1 suite header** (from `MockURLProtocolTests.swift` lines 6–7):
```swift
@Suite("MockURLProtocol — scaffolding (Phase 1)")
struct MockURLProtocolTests {
```

**Phase 2 version:**
```swift
@Suite("MockURLProtocol — fixture registry + lock safety", .serialized)
struct MockURLProtocolRegistryTests {
    @Test("register + reset lifecycle")
    func registerReset() { ... }

    @Test("registered handler returns fixture data")
    func handlerReturnsFixture() async throws { ... }

    @Test("reset clears all handlers")
    func resetClearsHandlers() async throws { ... }
}
```

---

### `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift`

**Role:** test-device (DEV-01 / DEV-02 real-device round-trip)
**Analog:** `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` lines 15–31

The Phase 1 device test is the exact structural template: `@Suite`, `@Test`, `#expect`, `@testable import validationLedger`, target membership = `validationLedgerDeviceTests` (NOT the simulator test target).

**Copy the suite structure** (from `SecureEnclaveSmokeTests.swift` lines 15–31):
```swift
@Suite("Device Smoke — Phase 1 D-06 minimum gate")
struct SecureEnclaveSmokeTests {
    @Test("Secure Enclave is available on device")
    func secureEnclaveAvailable() {
        #expect(SecureEnclave.isAvailable == true)
    }

    @Test("Keychain round-trip on device")
    func keychainRoundTrip() throws { ... }
}
```

**Apply to `SecureEnclaveKeyStoreTests`:**
```swift
@Suite("SecureEnclaveKeyStore — DEV-01/02 device round-trip")
struct SecureEnclaveKeyStoreTests {
    @Test("generateDeviceIdentityKeys returns two distinct public keys")
    func generateReturnsTwoKeys() throws { ... }

    @Test("sign with deviceKey produces valid ECDSA signature")
    func signWithDeviceKey() throws { ... }

    @Test("signWithAuthorization with authorizationKey succeeds (biometric bypassed in CI)")
    func signWithAuthorizationKey() throws { ... }

    @Test("loadPrivateKey after app relaunch retrieves persistent key by tag")
    func persistentKeyRetrieval() throws { ... }
}
```

**Target membership:** `validationLedgerDeviceTests` only. Running SE tests on the simulator must NOT be possible — match the Phase 1 precedent and the comment in `SecureEnclaveSmokeTests.swift` lines 7–9.

---

### `validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift`

**Role:** test-device (DEV-03 forced-stub, SC-4)
**Analog:** `validationLedgerDeviceTests/SecureEnclaveSmokeTests.swift` lines 15–31

This test is a CI gate: a forced-stub device that reports `SecureEnclave.isAvailable == false` should trigger a `fatalError` in `AppContainer.init`. Testing `fatalError` paths requires special care — the test should assert the condition that WOULD cause the fatalError, not call `AppContainer.init` directly on a real device (which would crash the test runner).

The pattern: test that `SecureEnclave.isAvailable == true` on the target device and verify the production code path would refuse on a false value by unit-testing the guard condition in isolation.

**Copy the assertion shape** (from `SecureEnclaveSmokeTests.swift` lines 17–19):
```swift
@Test("Secure Enclave is available on device")
func secureEnclaveAvailable() {
    #expect(SecureEnclave.isAvailable == true)
}
```

---

## Shared Patterns

### Swift Testing Struct Shape

**Source:** `validationLedgerTests/Storage/KeychainStoreTests.swift` lines 1–48
**Apply to:** All new test files in `validationLedgerTests/Networking/`

```swift
import Testing
import Foundation
@testable import validationLedger

@Suite("Descriptive name — what is being tested (Phase N context if relevant)")
struct SomeTests {
    @Test("behavior under test — written as outcome statement")
    func camelCaseFunctionName() throws {
        // Arrange → Act → #expect
    }
}
```

Rules:
- `import Testing` always first.
- `@testable import validationLedger` for access to internal types.
- `@Suite` string is human-readable. `@Test` string is the assertion statement.
- `#expect` for positive assertions; `#expect(throws:)` for error cases.
- `async throws` for async test methods; `throws` for sync.
- Every suite that mutates `MockURLProtocol.handlers` adds `.serialized` to `@Suite`.

---

### MockURLProtocol Fixture Registration

**Source:** `Core/Networking/MockURLProtocol.swift` (Phase 2 version)
**Apply to:** All test files that exercise networking code

```swift
// In @Test body:
MockURLProtocol.reset()   // always reset before each test
let fixtureData = ...     // load from test bundle or inline Data literal
MockURLProtocol.registerFixture(
    for: SomeEndpoint.self,
    path: "/some/path",
    method: .post,
    statusCode: 200,
    body: fixtureData
)
// ... exercise APIClient ...
```

Rule: `MockURLProtocol.reset()` is called at the top of every `@Test` body that uses fixtures, not in a `setUp`-style hook — this avoids test-order dependencies even within a `.serialized` suite.

---

### Initializer-DI (no singletons)

**Source:** `App/AppContainer.swift` lines 17–70
**Apply to:** `APIClient`, `DeviceFingerprint.current(keychain:)`, `SecureEnclaveKeyStore`, `PinningSessionDelegate`

```swift
// Pattern: all dependencies injected via init; no static var shared; no lazy singletons
final class SomeService {
    private let dependency: SomeDependency

    init(dependency: SomeDependency) {
        self.dependency = dependency
    }
}
```

For value-type services (structs), inject dependencies as parameters to the static factory method:
```swift
public static func current(keychain: KeychainStore) throws -> DeviceFingerprint { ... }
```

---

### Error Throwing (typed, not fatalError)

**Source:** `Core/Storage/Keychain/KeychainStore.swift` lines 35–40, 50–53
**Apply to:** `NetworkClient` (CR-01 fix), `SecureEnclaveKeyStore`, `APIClient`

```swift
// Pattern: guard-let + throw typed error; never force-unwrap or fatalError in production paths
guard let http = response as? HTTPURLResponse else {
    throw NetworkError.unexpectedResponseType(response)
}
guard status == errSecSuccess else {
    throw KeychainError.unexpectedStatus(status)
}
```

`fatalError` is reserved for programmer errors caught at init time (missing SE on production device in `AppContainer`, or missing `apiBaseURL` in release builds). All recoverable runtime failures throw typed errors.

---

### File Header Comments

**Source:** `Core/Networking/NetworkClient.swift` lines 1–4, `Core/KeyStore/KeyStoreProtocol.swift` lines 1–5
**Apply to:** All new Phase 2 files

```swift
// validationLedger/Core/Networking/SomeFile.swift
// One-line purpose statement.
// Phase notes: what was here before, what Phase 2 adds, what is left for Phase N.
```

Three-line maximum for the header block. No `Copyright` lines (not established in Phase 1). No `Created by` lines (Xcode default — strip or leave; Phase 1 files do not have them).

---

## No Analog Found

All Phase 2 files have either a direct in-repo analog or a RESEARCH.md sketch that functions as the authoritative pattern. There are no files requiring pure invention.

The closest to "no analog" are:
- `Core/Networking/CertificatePinning/PinnedSPKIs.swift` — compile-time SPKI constants are new to the project. `02-RESEARCH.md` Pattern 4 lines 549–570 is the only pattern source.
- `Core/Networking/CertificatePinning/SPKIHasher.swift` — ASN.1 header + CryptoKit SHA-256 is new. `02-RESEARCH.md` Pattern 4 lines 622–649 is the only pattern source.
- `Core/Identity/DeviceFingerprint.swift` + `Core/Identity/` directory — first file in the `Identity` module. `KeychainStore` Keychain upsert pattern is the structural analog.

---

## Metadata

**Analog search scope:** All files under `validationLedger/` (main target), `validationLedgerTests/`, `validationLedgerDeviceTests/`
**Files scanned:** 15 source files read directly; 02-RESEARCH.md sections read for code sketches
**Pattern extraction date:** 2026-04-21
