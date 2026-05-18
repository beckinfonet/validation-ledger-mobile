// validationLedgerTests/KYC/KYCCoordinatorTests.swift
// Requirement: KYC-01 — KYC capture flow-state sequencing.
// GREEN — implemented by plan 05-05.
//
// The KYC capture flow's step ordering and the D-01 "kick a pipelined upload
// once per capture-confirm" rule live in the pure value type `KYCFlowSequencer`
// (KYCCoordinator owns one and drives the actual nav). `KYCCoordinator` itself
// instantiates live AVFoundation/Vision services that produce no frames on the
// simulator (RESEARCH Pitfall 1) — so the simulator suite exercises the
// sequencer directly, exactly as plan 05-03 exercised `FaceQualityGate.evaluate`
// via its pure core. The live capture flow is verified on the device lane +
// HUMAN-UAT (plan 05-05's Task 4 checkpoint).

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCCoordinator — capture flow-state sequencing (KYC-01)")
struct KYCCoordinatorTests {

    @Test("KYC-01: the sequencer starts at the KYC-flow-start step")
    func startsAtStart() {
        let sequencer = KYCFlowSequencer()
        #expect(sequencer.current == .start)
        #expect(sequencer.reachedReview == false)
        #expect(sequencer.uploadsKicked.isEmpty)
    }

    @Test("KYC-01: the coordinator sequences capture steps in order and routes to Review last")
    func flowStateSequencing() {
        var sequencer = KYCFlowSequencer()

        // The full KYC-01 push chain: start → face → DL front → DL front
        // extraction → DL back → truck → trailer → plate → review.
        let expectedOrder: [KYCFlowStep] = [
            .face, .dlFront, .dlFrontExtraction, .dlBack,
            .truck, .trailer, .plate, .review,
        ]
        for expected in expectedOrder {
            let advancedTo = sequencer.advance()
            #expect(advancedTo == expected)
            #expect(sequencer.current == expected)
        }

        // Review is the terminal step — a further advance is a no-op.
        #expect(sequencer.reachedReview)
        #expect(sequencer.advance() == nil)
        #expect(sequencer.current == .review)
    }

    @Test("D-01: a pipelined upload is kicked once per capture step, in capture order")
    func pipelinedUploadKickedPerCapture() {
        var sequencer = KYCFlowSequencer()
        // Advance through the whole flow.
        while sequencer.advance() != nil {}

        // Exactly the 6 KYC artifacts, in capture order — the non-capture steps
        // (start, dlFrontExtraction, review) kick no upload (D-01).
        #expect(sequencer.uploadsKicked == [.face, .dlFront, .dlBack, .truck, .trailer, .plate])
    }

    @Test("KYC-01: dlFrontExtraction is a confirm screen — it captures no artifact")
    func extractionStepCapturesNothing() {
        // The DL-front artifact is captured at .dlFront; .dlFrontExtraction is
        // the read-only confirmation screen (D-05) and carries no artifact.
        #expect(KYCFlowStep.dlFront.artifact == .dlFront)
        #expect(KYCFlowStep.dlFrontExtraction.artifact == nil)
        #expect(KYCFlowStep.start.artifact == nil)
        #expect(KYCFlowStep.review.artifact == nil)
    }

    @Test("KYC-01: every flow step has a defined position; review has no successor")
    func stepOrdering() {
        #expect(KYCFlowStep.allCases.count == 9)
        #expect(KYCFlowStep.start.next == .face)
        #expect(KYCFlowStep.plate.next == .review)
        #expect(KYCFlowStep.review.next == nil)
    }
}
