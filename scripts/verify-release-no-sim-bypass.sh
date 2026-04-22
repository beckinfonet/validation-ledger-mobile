#!/bin/sh
# scripts/verify-release-no-sim-bypass.sh
# Phase 4 Plan 05 Task 3 — D-10 guard: confirm SimulatorBypassAttestationService
# code does NOT ship in a Release archive. This script is the binary-level
# enforcement of the #if DEBUG && targetEnvironment(simulator) gate that
# wraps the entire SimulatorBypassAttestationService.swift file.
#
# Who invokes this:
#   - Engineers BEFORE cutting any TestFlight/Release build (spot-check).
#   - Plan 10 ci-simulator.yml Release-strings guard step (Wave 5).
#
# How it works:
#   1. Archive the app in Release configuration (code-signing disabled so
#      CI runners without Apple Developer certificates can still exercise
#      this gate; the produced archive is not redistributable, which is fine
#      for a string-grep integrity check).
#   2. Resolve the built binary inside the xcarchive.
#   3. Run `strings` on the binary and grep for any "sim-bypass-" occurrence.
#   4. Fail with non-zero exit code if any match is found; print up to 20
#      offending lines for diagnosis.
#
# Exit codes:
#   0 — No sim-bypass-* strings in the Release binary. D-10 enforced.
#   1 — Build failed OR one or more sim-bypass-* strings leaked into Release.
#
# Local usage:
#   $ chmod +x scripts/verify-release-no-sim-bypass.sh
#   $ scripts/verify-release-no-sim-bypass.sh
#
# Optional arg: custom output directory (default: build/release-check).

set -eu

OUT_DIR="${1:-build/release-check}"
mkdir -p "$OUT_DIR"
ARCHIVE_PATH="$OUT_DIR/validationLedger.xcarchive"

echo "== Archiving Release build =="
xcodebuild archive \
  -project validationLedger.xcodeproj \
  -scheme validationLedger \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  | tail -50

APP_BINARY="$ARCHIVE_PATH/Products/Applications/validationLedger.app/validationLedger"
if [ ! -f "$APP_BINARY" ]; then
  echo "ERROR: Release binary not found at $APP_BINARY"
  exit 1
fi

echo "== Grepping Release binary for sim-bypass leaks =="
# Run `strings` on $APP_BINARY (xcarchive path: Products/Applications/validationLedger.app/validationLedger)
# and pipe through `grep -c "sim-bypass-"`. Returns 0 when the DEBUG && simulator
# gate excludes SimulatorBypassAttestationService from the Release archive.
# `|| true` keeps the pipe from failing under `set -e` when grep finds no match.
MATCH_COUNT=$(strings "$APP_BINARY" | grep -c "sim-bypass-" || true)
if [ "$MATCH_COUNT" -gt 0 ]; then
  echo "FAIL: Found $MATCH_COUNT occurrences of 'sim-bypass-' in Release binary:"
  strings "$APP_BINARY" | grep "sim-bypass-" | head -20
  echo ""
  echo "D-10 violated: SimulatorBypassAttestationService code is leaking into Release."
  echo "Check validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift"
  echo "is properly gated by '#if DEBUG && targetEnvironment(simulator)'."
  exit 1
fi

echo "PASS: No 'sim-bypass-' strings in Release binary (D-10 enforced)."
