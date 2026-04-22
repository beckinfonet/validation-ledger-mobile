// validationLedgerTests/Networking/EndpointEncodingTests.swift
// Phase 3 Plan 02: assert IN-01 + IN-05 explicit CodingKeys produce correct
// snake_case wire format for acronym-tail properties under .convertToSnakeCase.
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.

import Testing
import Foundation
@testable import validationLedger

@Suite("Endpoint encoding — acronym CodingKeys snake_case bridge (Pre-Phase-3 IN-01, IN-05)")
struct EndpointEncodingTests {

    private static let snakeEncoder: JSONEncoder = {
        let e = JSONEncoder()
        // Mirrors APIClient.swift line ~86: JSONEncoder.keyEncodingStrategy = .convertToSnakeCase.
        // Without explicit CodingKeys on acronym-tail properties, this strategy produces
        // "otp_session_i_d" / "install_u_u_i_d" / "upload_i_d" — these tests lock the fix.
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    @Test("IN-01 — OTPVerifyEndpoint.RequestBody encodes otpSessionID → otp_session_id")
    func otpVerifyRequestBody() throws {
        let body = OTPVerifyEndpoint.RequestBody(otpSessionID: "abc", code: "123456")
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"otp_session_id\""), "Expected otp_session_id in JSON, got: \(str)")
        #expect(!str.contains("otp_session_i_d"), "Mangled key still present: \(str)")
        #expect(str.contains("\"code\""))
    }

    @Test("IN-05 — DeviceRegisterEndpoint.DeviceFingerprintPayload encodes installUUID → install_uuid")
    func deviceRegisterFingerprint() throws {
        let payload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
            model: "iPhone15,2",
            iosVersion: "17.5",
            installUUID: "11111111-1111-1111-1111-111111111111"
        )
        let json = try Self.snakeEncoder.encode(payload)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"install_uuid\""), "Expected install_uuid in JSON, got: \(str)")
        #expect(str.contains("\"ios_version\""), "ios_version should still snake-case correctly")
        #expect(str.contains("\"model\""))
        #expect(!str.contains("install_u_u_i_d"), "Mangled key still present: \(str)")
    }

    @Test("IN-05 — KYCUploadChunkEndpoint.RequestBody encodes uploadID → upload_id")
    func kycUploadChunk() throws {
        let body = KYCUploadChunkEndpoint.RequestBody(
            uploadID: "u-1",
            chunkIndex: 0,
            chunkData: "AAAA",
            chunkSha256: "deadbeef"
        )
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"upload_id\""), "Expected upload_id in JSON, got: \(str)")
        #expect(str.contains("\"chunk_index\""))
        #expect(str.contains("\"chunk_data\""))
        #expect(str.contains("\"chunk_sha256\""))
        #expect(!str.contains("upload_i_d"), "Mangled key still present: \(str)")
    }

    @Test("IN-05 — KYCUploadCommitEndpoint.RequestBody encodes uploadID → upload_id")
    func kycUploadCommit() throws {
        let body = KYCUploadCommitEndpoint.RequestBody(uploadID: "u-1")
        let json = try Self.snakeEncoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""
        #expect(str.contains("\"upload_id\""), "Expected upload_id in JSON, got: \(str)")
        #expect(!str.contains("upload_i_d"), "Mangled key still present: \(str)")
    }
}
