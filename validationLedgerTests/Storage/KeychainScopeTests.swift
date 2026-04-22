// validationLedgerTests/Storage/KeychainScopeTests.swift
// Phase 4 DEV-04 / D-03: pin the invariant that attestedKeyId + lastHeartbeatAt
// are NOT members of KeychainScope.session, so logout (SESS-04) preserves them.
// See docs/adr/0005-three-key-device-register-payload.md.
//
// PARALLEL-WAVE NOTE: KeychainKey.attestedKeyId + KeychainKey.lastHeartbeatAt are
// added by plan 04-01 (sibling Wave-1 plan). This file will NOT compile in isolation
// inside the 04-02 worktree — the two symbols resolve only after the Wave-1 merge.
// That coordination is intentional: this test file's purpose is to pin the D-03
// invariant that 04-01 creates.

import Testing
@testable import validationLedger

@Suite("KeychainScope — D-03: attestation keys preserved across logout")
struct KeychainScopeTests {

    @Test("D-03 — attestedKeyId is NOT in .session scope")
    func testAttestedKeyIdNotInSessionScope() {
        #expect(KeychainScope.session.contains(.attestedKeyId) == false,
                "D-03 requires attestedKeyId to survive logout; adding it to .session breaks the invariant")
    }

    @Test("D-03 — lastHeartbeatAt is NOT in .session scope")
    func testLastHeartbeatAtNotInSessionScope() {
        #expect(KeychainScope.session.contains(.lastHeartbeatAt) == false,
                "D-03 requires lastHeartbeatAt to survive logout so next heartbeat is contiguous")
    }

    @Test("Regression — existing session members still in .session scope")
    func testSessionMembersUnchanged() {
        #expect(KeychainScope.session.contains(.sessionToken) == true)
        #expect(KeychainScope.session.contains(.sessionRole) == true)
        #expect(KeychainScope.session.contains(.sessionUserID) == true)
        #expect(KeychainScope.session.contains(.biometricDomainState) == true)
    }

    @Test("Regression — installUUID still NOT in .session (DEV-05 invariant)")
    func testInstallUUIDNotInSessionScope() {
        #expect(KeychainScope.session.contains(.installUUID) == false)
    }
}
