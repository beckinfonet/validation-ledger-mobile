// validationLedgerTests/Networking/APIClientEndpointTests.swift
// NET-01 + NET-02 acceptance: every M1 endpoint decodes its success fixture into the typed
// Response struct AND throws NetworkError.httpError on its failure fixture.
//
// @Suite(.serialized) is mandatory — every @Test body mutates MockURLProtocol's handler registry.
// Each @Test calls MockURLProtocol.reset() at entry and defer { reset() } for safety.

import Testing
import Foundation
@testable import validationLedger

@Suite("APIClient — M1 endpoint contracts (NET-01 + NET-02)", .serialized)
struct APIClientEndpointTests {

    // MARK: - Helpers

    private static let testBaseURL = URL(string: "https://mock.local")!

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let networkClient = URLSessionNetworkClient(
            config: .mock,
            session: session
        )
        return APIClient(
            baseURL: Self.testBaseURL,
            networkClient: networkClient,
            requestInterceptors: [],
            responseInterceptors: []
        )
    }

    /// Helper: assert the thrown error is NetworkError.httpError with the expected status.
    private func assertHTTPError<T>(_ expression: () async throws -> T, expectedStatus: Int) async {
        do {
            _ = try await expression()
            Issue.record("Expected NetworkError.httpError(\(expectedStatus)) but request succeeded")
        } catch let NetworkError.httpError(code, _) {
            #expect(code == expectedStatus)
        } catch {
            Issue.record("Expected NetworkError.httpError but got \(error)")
        }
    }

    // MARK: - OTPRequestEndpoint

    @Test("OTPRequestEndpoint: success fixture decodes into typed Response")
    func otpRequestSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("otp-request-success")
        MockURLProtocol.registerFixture(
            for: OTPRequestEndpoint.self,
            path: "/auth/otp/request",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(OTPRequestEndpoint(phone: "+14155550129"))
        #expect(response.otpSessionID == "sess-abc-123")
        #expect(response.expiresInSeconds == 120)
    }

    @Test("OTPRequestEndpoint: failure fixture (429) throws NetworkError.rateLimited (Phase 3 Plan 05 contract)")
    func otpRequestFailure() async {
        // Phase 3 Plan 05 / AUTH-02 / D-02: 429 now throws NetworkError.rateLimited
        // (not .httpError). This test was previously asserting .httpError(429) — that
        // was the Phase 2 baseline before the transport-boundary rate-limit fold landed.
        // Updated to match the new typed-error contract. The registerFixture call does
        // not set a Retry-After header, so the parseRetryAfter fallback (60s) applies.
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("otp-request-failure")
            MockURLProtocol.registerFixture(
                for: OTPRequestEndpoint.self,
                path: "/auth/otp/request",
                method: .post,
                statusCode: 429,
                body: fixture
            )
            let client = makeClient()
            do {
                _ = try await client.request(OTPRequestEndpoint(phone: "+14155550129"))
                Issue.record("Expected NetworkError.rateLimited; got success")
            } catch let NetworkError.rateLimited(retryAfter) {
                // Default-fallback 60s because registerFixture did not inject Retry-After.
                #expect(retryAfter == 60)
            } catch {
                Issue.record("Expected NetworkError.rateLimited; got \(error)")
            }
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - OTPVerifyEndpoint

    @Test("OTPVerifyEndpoint: success fixture decodes session + role + user")
    func otpVerifySuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("otp-verify-success")
        MockURLProtocol.registerFixture(
            for: OTPVerifyEndpoint.self,
            path: "/auth/otp/verify",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(OTPVerifyEndpoint(otpSessionID: "sess-abc-123", code: "123456"))
        #expect(response.sessionToken == "test-session-token-xyz")
        #expect(response.role == "carrier")
        #expect(response.userID == "u-42")
    }

    @Test("OTPVerifyEndpoint: failure fixture (401) throws NetworkError.httpError")
    func otpVerifyFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("otp-verify-failure")
            MockURLProtocol.registerFixture(
                for: OTPVerifyEndpoint.self,
                path: "/auth/otp/verify",
                method: .post,
                statusCode: 401,
                body: fixture
            )
            let client = makeClient()
            await assertHTTPError({ try await client.request(OTPVerifyEndpoint(otpSessionID: "sess-abc-123", code: "000000")) }, expectedStatus: 401)
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - DeviceRegisterEndpoint

    @Test("DeviceRegisterEndpoint: success fixture decodes deviceID + iso8601 registeredAt")
    func deviceRegisterSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("device-register-success")
        MockURLProtocol.registerFixture(
            for: DeviceRegisterEndpoint.self,
            path: "/device/register",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let fingerprint = DeviceRegisterEndpoint.DeviceFingerprintPayload(
            model: "iPhone15,2",
            iosVersion: "17.5.1",
            installUUID: "00000000-0000-0000-0000-000000000001"
        )
        let response = try await client.request(
            DeviceRegisterEndpoint(devicePublicKey: "BASE64-DEVICE-KEY", fingerprint: fingerprint)
        )
        #expect(response.deviceID == "dev-abc-123")
        // ISO-8601: 2026-04-21T12:00:00Z
        let expected = ISO8601DateFormatter().date(from: "2026-04-21T12:00:00Z")!
        #expect(response.registeredAt == expected)
    }

    @Test("DeviceRegisterEndpoint: failure fixture (409) throws NetworkError.httpError")
    func deviceRegisterFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("device-register-failure")
            MockURLProtocol.registerFixture(
                for: DeviceRegisterEndpoint.self,
                path: "/device/register",
                method: .post,
                statusCode: 409,
                body: fixture
            )
            let client = makeClient()
            let fingerprint = DeviceRegisterEndpoint.DeviceFingerprintPayload(
                model: "iPhone15,2",
                iosVersion: "17.5.1",
                installUUID: "00000000-0000-0000-0000-000000000001"
            )
            await assertHTTPError(
                { try await client.request(
                    DeviceRegisterEndpoint(devicePublicKey: "BASE64-DEVICE-KEY", fingerprint: fingerprint)
                ) },
                expectedStatus: 409
            )
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - KYCUploadInitEndpoint

    @Test("KYCUploadInitEndpoint: success fixture decodes uploadID + chunkSize")
    func kycUploadInitSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("kyc-upload-init-success")
        MockURLProtocol.registerFixture(
            for: KYCUploadInitEndpoint.self,
            path: "/kyc/upload/init",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(
            KYCUploadInitEndpoint(artifactType: .face, totalChunks: 12, totalBytes: 6_291_456, sha256: "deadbeef")
        )
        #expect(response.uploadID == "up-abc-123")
        #expect(response.chunkSize == 524288)
    }

    @Test("KYCUploadInitEndpoint: failure fixture (413) throws NetworkError.httpError")
    func kycUploadInitFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("kyc-upload-init-failure")
            MockURLProtocol.registerFixture(
                for: KYCUploadInitEndpoint.self,
                path: "/kyc/upload/init",
                method: .post,
                statusCode: 413,
                body: fixture
            )
            let client = makeClient()
            await assertHTTPError(
                { try await client.request(
                    KYCUploadInitEndpoint(artifactType: .face, totalChunks: 1, totalBytes: 50_000_000, sha256: "x")
                ) },
                expectedStatus: 413
            )
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - KYCUploadChunkEndpoint

    @Test("KYCUploadChunkEndpoint: success fixture decodes ack + chunksAcked")
    func kycUploadChunkSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("kyc-upload-chunk-success")
        MockURLProtocol.registerFixture(
            for: KYCUploadChunkEndpoint.self,
            path: "/kyc/upload/chunk",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(
            KYCUploadChunkEndpoint(uploadID: "up-abc", chunkIndex: 0, chunkData: "AAAA", chunkSha256: "deadbeef")
        )
        #expect(response.ackedChunk == 0)
        #expect(response.chunksAcked == 1)
        #expect(response.totalChunks == 12)
    }

    @Test("KYCUploadChunkEndpoint: failure fixture (400) throws NetworkError.httpError")
    func kycUploadChunkFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("kyc-upload-chunk-failure")
            MockURLProtocol.registerFixture(
                for: KYCUploadChunkEndpoint.self,
                path: "/kyc/upload/chunk",
                method: .post,
                statusCode: 400,
                body: fixture
            )
            let client = makeClient()
            await assertHTTPError(
                { try await client.request(
                    KYCUploadChunkEndpoint(uploadID: "up-abc", chunkIndex: 3, chunkData: "WRONG", chunkSha256: "mismatch")
                ) },
                expectedStatus: 400
            )
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - KYCUploadCommitEndpoint

    @Test("KYCUploadCommitEndpoint: success fixture decodes artifactID + status")
    func kycUploadCommitSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("kyc-upload-commit-success")
        MockURLProtocol.registerFixture(
            for: KYCUploadCommitEndpoint.self,
            path: "/kyc/upload/commit",
            method: .post,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(KYCUploadCommitEndpoint(uploadID: "up-abc"))
        #expect(response.artifactID == "art-xyz-789")
        #expect(response.status == "pending_review")
    }

    @Test("KYCUploadCommitEndpoint: failure fixture (409) throws NetworkError.httpError")
    func kycUploadCommitFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("kyc-upload-commit-failure")
            MockURLProtocol.registerFixture(
                for: KYCUploadCommitEndpoint.self,
                path: "/kyc/upload/commit",
                method: .post,
                statusCode: 409,
                body: fixture
            )
            let client = makeClient()
            await assertHTTPError(
                { try await client.request(KYCUploadCommitEndpoint(uploadID: "up-abc")) },
                expectedStatus: 409
            )
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }

    // MARK: - KYCStatusEndpoint (GET)

    @Test("KYCStatusEndpoint: success fixture decodes overallStatus + nested artifacts")
    func kycStatusSuccess() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let fixture = try FixtureLoader.loadFixture("kyc-status-success")
        MockURLProtocol.registerFixture(
            for: KYCStatusEndpoint.self,
            path: "/kyc/status",
            method: .get,
            statusCode: 200,
            body: fixture
        )
        let client = makeClient()
        let response = try await client.request(KYCStatusEndpoint())
        #expect(response.overallStatus == "under_review")
        #expect(response.artifacts.count == 3)
        #expect(response.artifacts[2].rejectionReason?.contains("blurry") == true)
    }

    @Test("KYCStatusEndpoint: failure fixture (401) throws NetworkError.httpError")
    func kycStatusFailure() async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        do {
            let fixture = try FixtureLoader.loadFixture("kyc-status-failure")
            MockURLProtocol.registerFixture(
                for: KYCStatusEndpoint.self,
                path: "/kyc/status",
                method: .get,
                statusCode: 401,
                body: fixture
            )
            let client = makeClient()
            await assertHTTPError({ try await client.request(KYCStatusEndpoint()) }, expectedStatus: 401)
        } catch {
            Issue.record("Setup failed: \(error)")
        }
    }
}
