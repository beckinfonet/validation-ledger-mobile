#!/usr/bin/env bash
# scripts/check-coverage.sh
# Parses xcodebuild -enableCodeCoverage output and fails if Core/ coverage
# falls below the CI-01 target (>= 70%).
# Usage: ./scripts/check-coverage.sh <path/to/result.xcresult> [threshold]
# Default threshold: 70.

set -euo pipefail

XCRESULT="${1:?Usage: $0 <xcresult-path> [threshold-percent]}"
THRESHOLD="${2:-70}"

if [ ! -d "$XCRESULT" ]; then
    echo "ERROR: xcresult bundle not found at $XCRESULT"
    exit 1
fi

# Extract coverage JSON via xcrun xccov.
# xccov view --report produces a human table; --json produces structured data.
JSON=$(xcrun xccov view --report --json "$XCRESULT" 2>/dev/null || echo "{}")

if [ "$JSON" = "{}" ]; then
    echo "ERROR: xccov could not parse $XCRESULT (try: xcrun xccov view --report --json <path>)"
    exit 1
fi

# Sum covered / executable lines across files under validationLedger/Core/.
# xccov JSON shape: targets[].files[].{path, coveredLines, executableLines}
#
# Device-only exclusions: Secure Enclave and App Attest APIs are non-functional
# on the iOS Simulator, so this (simulator) pipeline structurally cannot execute
# a single line of these files — they sit at 0% here by design. Their coverage
# is the device pipeline's responsibility: validationLedgerDeviceTests runs
# SecureEnclaveKeyStoreTests + AppAttestRoundTripTests on real hardware.
# Counting them against the simulator gate measures the wrong thing.
COVERAGE_LINE=$(echo "$JSON" | python3 -c '
import json, sys
DEVICE_ONLY = (
    "Core/KeyStore/SecureEnclaveKeyStore.swift",
    "Core/Attestation/DCAppAttestAttestationService.swift",
)
data = json.load(sys.stdin)
covered = 0
executable = 0
for target in data.get("targets", []):
    for file in target.get("files", []):
        path = file.get("path", "")
        if "/Core/" in path and not any(path.endswith(d) for d in DEVICE_ONLY):
            covered += file.get("coveredLines", 0)
            executable += file.get("executableLines", 0)
if executable == 0:
    print(f"ERROR: no files under Core/ found in coverage report", file=sys.stderr)
    sys.exit(2)
pct = 100.0 * covered / executable
print(f"{pct:.2f}")
')

echo "Core/ coverage: ${COVERAGE_LINE}% (threshold: ${THRESHOLD}%)"

# Integer compare (floor) — if coverage < threshold, fail.
COVERED_INT=$(echo "$COVERAGE_LINE" | awk '{print int($1)}')
if [ "$COVERED_INT" -lt "$THRESHOLD" ]; then
    echo "FAIL: Core/ coverage ${COVERAGE_LINE}% is below threshold ${THRESHOLD}%"
    exit 1
fi

echo "OK: Coverage gate passed"
