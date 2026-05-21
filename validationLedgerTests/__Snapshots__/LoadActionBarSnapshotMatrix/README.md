# LoadActionBarSnapshotMatrix Baselines

Phase 10 Plan 09 — visual baselines for `LoadActionsView` per the 65-cell
(Role × LoadStatus) regression gate (UI-SPEC line 537 + VALIDATION.md § 65-Cell
Snapshot Matrix).

## Contents

- 65 cells: `actions-<role>-<status>.png` — one per (Role × LoadStatus) pair.
- 5 ACTION-07 disabled variants: `actions-disabled-<role>.png`.
- 3 empty-state caption locks: `actions-empty-factoring.png`,
  `actions-empty-terminal-delivered.png`, `actions-empty-terminal-inTransit.png`.
- 3 situational locks: in-flight tender (`actions-inflight-broker-tender.png`),
  future-deadline respond-by, past-due respond-by.

**Total: 76 baselines** (per `LoadActionBarSnapshotMatrixTests.swift` Tests 1-8).

## Recording / re-recording

Recorded 2026-05-21 by Plan 10-09 against iPhone 17 simulator (iOS 26.3.1).

To re-record after a deliberate UI change lands:

```bash
RECORD_SNAPSHOTS=YES xcodebuild test \
  -project validationLedger.xcodeproj -scheme validationLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:validationLedgerTests/LoadActionBarSnapshotMatrixTests \
  -skip-testing:validationLedgerDeviceTests \
  -parallel-testing-enabled NO
```

Eyeball-review every PNG before committing. Then re-run WITHOUT the env var
to confirm the VERIFY pass is green against the new baselines.

Phase 9.1 D-05 precedent: deliberate UI changes that touch any of these 76
cells require a re-record commit in the same PR as the source change.

## CI workflow

`SNAPSHOT_BASELINE_DIR=$PWD/validationLedgerTests/__Snapshots__` may be set
to redirect baseline I/O to an explicit path (matches the env-var escape
hatch in `LoadActionBarSnapshotMatrixTests.baselineDirectoryURL`). The
default walk-up resolution finds this directory automatically when the
test bundle runs against the source tree.
