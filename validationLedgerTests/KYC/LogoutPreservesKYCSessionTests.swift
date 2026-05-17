// validationLedgerTests/KYC/LogoutPreservesKYCSessionTests.swift
// Phase 5 Plan 08 Task 1 — D-02 / RESEARCH Assumption A4: logout preserves the
// on-disk KYC session.
// Requirements: KYC-06 / UPL-02 — threat T-05-08-02.
//
// The load-bearing Phase 5 invariant (KYCSessionStore.swift header, 05-CONTEXT
// D-02): `LogoutService.logout` wipes the session-scope Keychain cache — incl.
// the Phase-5 D-13 cached `kycStatus` STRING — but NEVER touches the on-disk
// `KYCSessionStore` blob. A user who logs out mid-KYC and logs back in resumes
// exactly where they left off; the encrypted on-disk artifact session outlives
// the logout by design.
//
// This suite is the explicit A4 acceptance criterion called out in the planner
// notes: it asserts BOTH halves of D-02 in one test — (a) the `session.*`
// Keychain keys including `kycStatus` ARE wiped, and (b) `KYCSessionStore
// .loadSession()` STILL returns the persisted session afterwards.
//
// Per 03-PATTERNS: unit/integration tests use Swift Testing (`import Testing`).

import Testing
import Foundation
@testable import validationLedger

@Suite("LogoutService — preserves the on-disk KYC session (D-02 / A4)")
@MainActor
struct LogoutPreservesKYCSessionTests {

    /// No-op `Logger` so `DefaultLogoutService` has its required dependency.
    private final class NoOpLogger: Logger, @unchecked Sendable {
        func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
        func log(_ level: LogLevel, _ message: String) {}
    }

    /// `BiometricService` stub for `DefaultSessionLockService` (logout's dep).
    private final class StubBiometric: BiometricService {
        nonisolated func currentDomainState() -> Data? { nil }
        func evaluate(reason: String, fallback: BiometricFallback) async throws {}
    }

    @Test("D-02 / A4: logout wipes the session Keychain (incl. kycStatus) but NOT the on-disk KYC session")
    func logoutPreservesOnDiskKYCSession() async throws {
        // --- Arrange: an in-progress KYC session persisted on disk ----------
        // A temp-directory KYCSessionStore seeded with a mid-flow session — a
        // started face upload with one chunk acked. This is the encrypted
        // on-disk blob D-02 says must survive logout.
        let kycDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logout-preserves-kyc-\(UUID().uuidString)", isDirectory: true)
        let kycStore = try KYCSessionStore(directory: kycDir)
        defer { try? FileManager.default.removeItem(at: kycDir) }

        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            Data([0x01, 0x02, 0x03, 0x04])
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            ArtifactUploadState(
                artifactType: .face,
                uploadID: "up-preserved-1",
                totalChunks: 3,
                totalBytes: 4,
                chunkSize: KYCUploader.defaultChunkSize,
                chunksAcked: 1,
                sha256: "",
                committed: false,
                artifactID: nil,
                localDataAvailable: true
            )
        try kycStore.persist(session)

        // Sanity: the session is on disk before logout.
        #expect(try kycStore.loadSession() != nil, "the KYC session is persisted before logout")

        // --- Arrange: a populated session-scope Keychain --------------------
        // Seed every member of `KeychainScope.session`, INCLUDING the Phase-5
        // D-13 cached `kycStatus`. These are the keys logout must wipe.
        let keychain = KeychainStore(service: "vl.test.logout.kyc.\(UUID().uuidString)")
        try keychain.set(Data("tok".utf8), for: .sessionToken,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data("carrier".utf8), for: .sessionRole,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data("user-42".utf8), for: .sessionUserID,
                         accessibility: .afterFirstUnlockThisDeviceOnly)
        try keychain.set(Data("needs_kyc".utf8), for: .kycStatus,
                         accessibility: .afterFirstUnlockThisDeviceOnly)

        // Sanity: the cached kycStatus is in the Keychain before logout.
        #expect((try? keychain.get(.kycStatus)) != nil,
                "the cached kycStatus is in the Keychain before logout")

        // --- Act: run the single-funnel LogoutService teardown -------------
        let keyStore = SoftwareKeyStore()
        _ = try keyStore.generateDeviceIdentityKeys()
        let sessionLock = DefaultSessionLockService(biometric: StubBiometric(), keychain: keychain)
        let logoutService = DefaultLogoutService(
            keychain: keychain,
            keyStore: keyStore,
            sessionLock: sessionLock,
            logger: NoOpLogger(),
            notificationCenter: NotificationCenter()   // isolated for the test
        )
        await logoutService.logout(reason: .userInitiated)

        // --- Assert (a): the session-scope Keychain keys ARE wiped ----------
        #expect(throws: KeychainError.self) { _ = try keychain.get(.sessionToken) }
        #expect(throws: KeychainError.self) { _ = try keychain.get(.sessionRole) }
        #expect(throws: KeychainError.self) { _ = try keychain.get(.sessionUserID) }
        // The D-13 cached KYC status STRING is session metadata — wiped on
        // logout exactly like `sessionRole`.
        #expect((try? keychain.get(.kycStatus)) == nil,
                "the cached kycStatus Keychain key must be wiped on logout (D-13)")

        // --- Assert (b): the on-disk KYC session SURVIVED -------------------
        // The explicit A4 acceptance criterion: KYCSessionStore.loadSession()
        // is still non-nil after logout — the encrypted on-disk blob outlives
        // the logout by design (D-02).
        let survivor = try kycStore.loadSession()
        #expect(survivor != nil,
                "the on-disk KYC session must SURVIVE logout (D-02 / A4)")
        let restored = try #require(survivor)
        let faceState = try #require(
            restored.state(for: .face),
            "the resumable face-upload cursor survived logout"
        )
        #expect(faceState.uploadID == "up-preserved-1",
                "the persisted uploadID survived logout — the user resumes from here")
        #expect(faceState.chunksAcked == 1,
                "the resume cursor survived logout — resume is from chunk 1, not 0")
        #expect(restored.data(for: .face) == Data([0x01, 0x02, 0x03, 0x04]),
                "the in-progress artifact bytes survived logout")
    }
}
