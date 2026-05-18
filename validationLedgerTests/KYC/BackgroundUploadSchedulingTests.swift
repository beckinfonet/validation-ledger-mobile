// validationLedgerTests/KYC/BackgroundUploadSchedulingTests.swift
// Requirement: UPL-05 — background upload-continuation scheduling logic.
// GREEN (plan 05-07): the RED Wave-0 scaffold is replaced with real assertions
// over a `BGTaskScheduling` fake. `BGTaskScheduler` itself cannot run under the
// simulator test host (registration traps, submit is a no-op), so the scheduling
// DECISION logic in `KYCUploadScheduler.scheduleUploadContinuation` is exercised
// against the fake — it asserts a `BGProcessingTaskRequest` is submitted under
// `com.maldin.validationLedger.kyc-upload` when an upload is pending, and NOT
// submitted when none is.

import Testing
import Foundation
import BackgroundTasks
@testable import validationLedger

@Suite("BackgroundUploadScheduling — BGTask scheduling logic (UPL-05)")
struct BackgroundUploadSchedulingTests {

    // MARK: - Fakes

    /// Records `register` + `submit` calls so tests can assert the scheduling
    /// decision without touching the real `BGTaskScheduler`.
    final class FakeBGTaskScheduling: BGTaskScheduling, @unchecked Sendable {
        private let lock = NSLock()
        private var _registeredIdentifiers: [String] = []
        private var _submittedRequests: [BGTaskRequest] = []

        var registeredIdentifiers: [String] {
            lock.lock(); defer { lock.unlock() }
            return _registeredIdentifiers
        }
        var submittedRequests: [BGTaskRequest] {
            lock.lock(); defer { lock.unlock() }
            return _submittedRequests
        }

        func register(
            forTaskWithIdentifier identifier: String,
            launchHandler: @escaping @Sendable (BGTask) -> Void
        ) -> Bool {
            lock.lock(); _registeredIdentifiers.append(identifier); lock.unlock()
            return true
        }

        func submit(_ request: BGTaskRequest) throws {
            lock.lock(); _submittedRequests.append(request); lock.unlock()
        }
    }

    private final class NoOpLogger: Logger, @unchecked Sendable {
        func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
        func log(_ level: LogLevel, _ message: String) {}
    }

    private func makeScheduler() -> (KYCUploadScheduler, FakeBGTaskScheduling) {
        let fake = FakeBGTaskScheduling()
        let scheduler = KYCUploadScheduler(scheduler: fake, logger: NoOpLogger())
        return (scheduler, fake)
    }

    // MARK: - Tests

    @Test("UPL-05: an incomplete upload schedules a BGProcessingTask on backgrounding")
    func incompleteUploadSchedulesBackgroundTask() throws {
        let (scheduler, fake) = makeScheduler()

        scheduler.scheduleUploadContinuation(hasPendingUploads: true)

        #expect(fake.submittedRequests.count == 1,
                "a pending upload must submit exactly one BGProcessingTaskRequest")
        let request = try #require(fake.submittedRequests.first)
        #expect(request is BGProcessingTaskRequest,
                "the submitted request must be a BGProcessingTaskRequest")
        #expect(request.identifier == KYCUploadScheduler.taskIdentifier,
                "the request identifier must match the Info.plist BGTask identifier")
        #expect(request.identifier == "com.maldin.validationLedger.kyc-upload",
                "the BGTask identifier is the bundle-scoped kyc-upload identifier")
    }

    @Test("UPL-05: a BGProcessingTaskRequest requires network, not external power")
    func scheduledRequestRequiresNetworkNotPower() throws {
        let (scheduler, fake) = makeScheduler()

        scheduler.scheduleUploadContinuation(hasPendingUploads: true)

        let request = try #require(fake.submittedRequests.first as? BGProcessingTaskRequest)
        #expect(request.requiresNetworkConnectivity == true,
                "a chunk upload needs the network")
        #expect(request.requiresExternalPower == false,
                "KYC uploads are small — do not gate on a charger")
    }

    @Test("UPL-05: no pending upload submits NO BGProcessingTask")
    func noPendingUploadSchedulesNothing() {
        let (scheduler, fake) = makeScheduler()

        scheduler.scheduleUploadContinuation(hasPendingUploads: false)

        #expect(fake.submittedRequests.isEmpty,
                "with no incomplete upload, no BGProcessingTaskRequest is submitted")
    }

    @Test("UPL-05: registerHandler registers under the kyc-upload identifier")
    func registerHandlerUsesKYCUploadIdentifier() {
        let (scheduler, fake) = makeScheduler()

        scheduler.registerHandler()

        #expect(fake.registeredIdentifiers == ["com.maldin.validationLedger.kyc-upload"],
                "the launch handler registers under the Info.plist BGTask identifier")
    }
}
