// validationLedgerTests/KYC/KYCSessionStoreConcurrencyTests.swift
// Debug session: kyc-session-store-data-race (Phase 5, plan 05-06 blocker).
//
// Falsification tests for the KYCSessionStore lost-update data race.
//
// KYCSessionStore is `@unchecked Sendable` and — being a Sendable class reached
// synchronously from the `nonisolated` `KYCUploader` actor under
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — is genuinely `nonisolated`: its
// methods run on whichever executor calls them. Before this fix it had NO lock,
// so the @MainActor capture path and the KYCUploader background actor ran their
// load -> mutate -> persist cycles on two different threads with no mutual
// exclusion (D-01 pipelined upload overlaps capture by design).
//
// These tests run real `Thread`s (NOT the cooperative pool — a `Task.detached`
// whose body does a blocking `Thread.sleep` starves the limited pool and gives
// a false green) and use a `DispatchSemaphore` rendezvous to force the
// load->persist windows of two writers to overlap DETERMINISTICALLY. With the
// store's lock the read-modify-writes serialize and every write survives;
// without it one write is silently clobbered (lost update).
//
// Run with `-parallel-testing-enabled NO`.

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCSessionStore — concurrency / lost-update race (debug: kyc-session-store-data-race)")
struct KYCSessionStoreConcurrencyTests {

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kyc-store-concurrency-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// Run `body` on a fresh detached OS `Thread` (never the cooperative pool)
    /// and return a semaphore the caller waits on for completion.
    private func runOnThread(_ body: @escaping @Sendable () -> Void) -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            body()
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        return done
    }

    /// DETERMINISTIC lost-update repro on two real threads.
    ///
    /// Writer A enters `withSession`, writes `face`, then sleeps 300 ms inside
    /// the closure — modelling the load->(work)->persist gap. Writer B starts
    /// 80 ms into A's window and writes `truck`.
    ///
    /// With an atomic, lock-held `withSession`, B blocks on the lock until A's
    /// persist completes, so B reads A's write and the final session has BOTH
    /// artifacts. Without the lock, B loads the pre-A snapshot, and A — which
    /// persists LAST — overwrites B's `truck`: a lost update.
    @Test("a writer racing an in-flight withSession does not clobber it")
    func interleavedWritesBothSurvive() async throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)
        try store.persist(KYCSession())

        let aDone = runOnThread {
            try? store.withSession { session in
                session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
                    Data(repeating: 0xAA, count: 256)
                Thread.sleep(forTimeInterval: 0.30)
            }
        }

        // Let A get past its load and into the closure window.
        Thread.sleep(forTimeInterval: 0.08)

        let bDone = runOnThread {
            try? store.withSession { session in
                session.artifactData[KYCUploadInitEndpoint.ArtifactType.truck.rawValue] =
                    Data(repeating: 0xBB, count: 256)
            }
        }

        aDone.wait()
        bDone.wait()

        let final = try store.loadSession()
        #expect(final?.data(for: .face) != nil,
                "writer A's artifact was clobbered by an interleaving write")
        #expect(final?.data(for: .truck) != nil,
                "writer B's artifact was clobbered by an interleaving write")
    }

    /// The cross-context variant — exactly the D-01 collision: a slow
    /// capture-style `withSession` (adds artifact bytes) is raced by an
    /// uploader-style `markChunkAcked` (advances the chunk cursor). A correct
    /// store merges both; the unsynchronized store drops one.
    @Test("a capture write and an uploader chunk-ack racing it both survive")
    func captureAndUploaderInterleaveBothSurvive() async throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)

        var seed = KYCSession()
        seed.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            ArtifactUploadState(artifactType: .face, uploadID: "u-face", totalChunks: 10)
        try store.persist(seed)

        let captureDone = runOnThread {
            try? store.withSession { session in
                session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
                    Data(repeating: 0xCC, count: 256)
                Thread.sleep(forTimeInterval: 0.30)
            }
        }

        Thread.sleep(forTimeInterval: 0.08)

        let uploaderDone = runOnThread {
            try? store.markChunkAcked(.face, upTo: 5)
        }

        captureDone.wait()
        uploaderDone.wait()

        let final = try store.loadSession()
        #expect(final?.data(for: .face) != nil,
                "the capture write was clobbered by the uploader chunk-ack")
        #expect(final?.state(for: .face)?.chunksAcked == 5,
                "the uploader chunk-ack was clobbered by the capture write")
    }

    /// Counted-mutations invariant: 40 increments, each on its own real thread,
    /// each through `withSession`, with a small sleep inside the closure to
    /// widen the load->persist window. With the lock every increment lands
    /// (final == 40); without it, lost updates show as final < 40.
    @Test("concurrent atomic increments on parallel threads all land")
    func concurrentIncrementsAllLand() async throws {
        let dir = makeTempDir()
        let store = try KYCSessionStore(directory: dir)

        var seed = KYCSession()
        seed.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            ArtifactUploadState(artifactType: .face, uploadID: "u-face", totalChunks: 1_000)
        try store.persist(seed)

        let iterations = 40
        let dones = (0..<iterations).map { _ in
            runOnThread {
                try? store.withSession { session in
                    guard var state = session.uploadStates["face"] else { return }
                    let observed = state.chunksAcked
                    // Widen the load->persist gap so an unlocked store reliably
                    // interleaves a competing increment in here.
                    Thread.sleep(forTimeInterval: 0.003)
                    state.chunksAcked = observed + 1
                    session.uploadStates["face"] = state
                }
            }
        }
        for done in dones { done.wait() }

        let final = try store.loadSession()
        let acked = final?.state(for: .face)?.chunksAcked ?? -1
        #expect(acked == iterations,
                "lost update: not every concurrent increment was applied")
    }
}
