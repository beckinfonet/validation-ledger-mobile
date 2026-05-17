// validationLedgerTests/KYC/KYCUploaderTestSupport.swift
// Phase 5 Plan 04 — shared test scaffolding for the KYCUploader* suites.
//
// KYCUploader drives the SHIPPED init/chunk/commit endpoints through the real
// APIClient + URLSessionNetworkClient + MockURLProtocol. The mock handler must
// therefore behave like a real KYC backend: parse the chunk index out of the
// request body, return an incrementing `chunksAcked`, and (for the retry/
// idempotency suites) record per-chunk request counts + idempotency keys.
//
// `URLProtocol` moves `URLRequest.httpBody` into `httpBodyStream`, so a handler
// that needs the body must drain the stream — `bodyData(from:)` below does that.

import Foundation
import CryptoKit
@testable import validationLedger

/// Test-only SHA-256 hex helper — production code computes the same value via its
/// own private `Data.sha256Hex()`; this is the independent oracle the tests check
/// the init-body hash against.
extension Data {
    var kycUploaderSHA256HexForTest: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

enum KYCUploaderTestSupport {

    // MARK: - APIClient assembly (MockURLProtocol-backed, real interceptors)

    /// The mock base URL every KYCUploader test uses.
    static let baseURL = URL(string: "https://mock.local")!

    /// Build an `APIClient` wired to `MockURLProtocol` with the real
    /// `IdempotencyInterceptor` — so a caller-supplied `Idempotency-Key`
    /// (set by `KYCUploader` via the endpoint header seam) survives end-to-end.
    static func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let networkClient = URLSessionNetworkClient(config: .mock, session: session)
        return APIClient(
            baseURL: baseURL,
            networkClient: networkClient,
            requestInterceptors: [IdempotencyInterceptor()],
            responseInterceptors: []
        )
    }

    // MARK: - Request-body draining

    /// Read the request body, draining `httpBodyStream` when `URLProtocol` has
    /// moved the body off `httpBody`.
    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Decode the `chunkIndex` field out of a `/kyc/upload/chunk` request body.
    /// The wire body is snake_case JSON (`APIClient.defaultEncoder`).
    static func chunkIndex(from request: URLRequest) -> Int? {
        let body = bodyData(from: request)
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["chunk_index"] as? Int
    }

    // MARK: - Test logger

    /// A no-op `Logger` for tests — KYCUploader requires a logger dep.
    static func makeLogger() -> Logger { NoopTestLogger() }

    final class NoopTestLogger: Logger {
        func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
        func log(_ level: LogLevel, _ message: String) {}
    }

    // MARK: - Store assembly

    /// A `KYCSessionStore` rooted in a fresh unique temp directory.
    static func makeStore() throws -> KYCSessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kyc-uploader-tests-\(UUID().uuidString)", isDirectory: true)
        return try KYCSessionStore(directory: dir)
    }

    /// Deterministic artifact bytes of an exact length (so chunk math is exact).
    static func artifactData(byteCount: Int) -> Data {
        Data((0..<byteCount).map { UInt8($0 & 0xFF) })
    }

    // MARK: - Mock HTTP responses

    /// Build a 200 JSON response for a MockURLProtocol handler.
    static func make200(_ json: String, url: URL?) -> (HTTPURLResponse, Data) {
        let resolved = url ?? URL(string: "https://mock.local")!
        let resp = HTTPURLResponse(
            url: resolved, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, Data(json.utf8))
    }

    /// Build an arbitrary-status JSON response for a MockURLProtocol handler.
    static func makeResponse(status: Int, json: String, url: URL?) -> (HTTPURLResponse, Data) {
        let resolved = url ?? URL(string: "https://mock.local")!
        let resp = HTTPURLResponse(
            url: resolved, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, Data(json.utf8))
    }

    // MARK: - Backend handler

    /// A mutable, lock-guarded recorder so a `@Sendable` MockURLProtocol handler
    /// can tally requests + capture idempotency keys across a test.
    final class BackendRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _initCount = 0
        private var _commitCount = 0
        /// chunkIndex -> number of POSTs seen for that index
        private var _chunkAttempts: [Int: Int] = [:]
        /// chunkIndex -> set of distinct Idempotency-Key header values seen
        private var _chunkKeys: [Int: Set<String>] = [:]
        /// chunkIndex -> number of *successful* (2xx) acks emitted
        private var _chunkSuccesses: [Int: Int] = [:]

        var initCount: Int { lock.withLock { _initCount } }
        var commitCount: Int { lock.withLock { _commitCount } }
        var totalChunkRequests: Int { lock.withLock { _chunkAttempts.values.reduce(0, +) } }

        func attempts(forChunk index: Int) -> Int { lock.withLock { _chunkAttempts[index] ?? 0 } }
        func keys(forChunk index: Int) -> Set<String> { lock.withLock { _chunkKeys[index] ?? [] } }
        func successes(forChunk index: Int) -> Int { lock.withLock { _chunkSuccesses[index] ?? 0 } }

        func recordInit() { lock.withLock { _initCount += 1 } }
        func recordCommit() { lock.withLock { _commitCount += 1 } }
        func recordChunkAttempt(_ index: Int, key: String?) {
            lock.withLock {
                _chunkAttempts[index, default: 0] += 1
                if let key { _chunkKeys[index, default: []].insert(key) }
            }
        }
        func recordChunkSuccess(_ index: Int) {
            lock.withLock { _chunkSuccesses[index, default: 0] += 1 }
        }
    }
}
