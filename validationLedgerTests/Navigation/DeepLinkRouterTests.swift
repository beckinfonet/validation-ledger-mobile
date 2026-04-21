// validationLedgerTests/Navigation/DeepLinkRouterTests.swift
import Testing
import Foundation
@testable import validationLedger

@Suite("DeepLinkRouter — bootstrap-aware queue (FOUND-08)")
struct DeepLinkRouterTests {
    @Test("URLs received pre-bootstrap are queued, not routed")
    func queuesWhileCold() {
        let router = DeepLinkRouter()
        let url = URL(string: "validationledger://load/123")!
        router.receive(url)
        #expect(router.pendingCount == 1)
    }

    @Test("bootstrapComplete() drains queue and flips state")
    func bootstrapDrainsQueue() {
        let router = DeepLinkRouter()
        router.receive(URL(string: "validationledger://a")!)
        router.receive(URL(string: "validationledger://b")!)
        #expect(router.pendingCount == 2)
        router.bootstrapComplete()
        #expect(router.pendingCount == 0)
        #expect(router.isReady == true)
    }

    @Test("URLs received after bootstrap route immediately (queue stays empty)")
    func afterBootstrapRoutesImmediately() {
        let router = DeepLinkRouter()
        router.bootstrapComplete()
        router.receive(URL(string: "validationledger://c")!)
        #expect(router.pendingCount == 0)
    }
}
