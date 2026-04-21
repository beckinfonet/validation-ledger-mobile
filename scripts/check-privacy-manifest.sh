#!/usr/bin/env bash
# scripts/check-privacy-manifest.sh
# Verifies PrivacyInfo.xcprivacy is in the built .app bundle (Pitfall P14).
# Run AFTER xcodebuild completes; fails the build if the manifest is absent.
#
# App Store submission via Transporter will reject builds missing PrivacyInfo with
# the ITMS-91053 error. This script catches that gap in CI before it reaches review.

set -euo pipefail

SCHEME="${SCHEME:-validationLedger}"
PROJECT="${PROJECT:-validationLedger.xcodeproj}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 15,OS=17.5}"

# Ask xcodebuild for the build products directory.
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -showBuildSettings 2>/dev/null | awk '/[[:space:]]CONFIGURATION_BUILD_DIR[[:space:]]/ {print $3; exit}')

if [ -z "$BUILD_DIR" ]; then
    echo "ERROR: Could not resolve CONFIGURATION_BUILD_DIR from xcodebuild"
    echo "       Tried: xcodebuild -project '$PROJECT' -scheme '$SCHEME' -destination '$DESTINATION'"
    exit 1
fi

APP_PATH="$BUILD_DIR/${SCHEME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: .app bundle not found at $APP_PATH. Did the build run?"
    exit 1
fi

if [ ! -f "$APP_PATH/PrivacyInfo.xcprivacy" ]; then
    echo "ERROR: PrivacyInfo.xcprivacy missing from $APP_PATH"
    echo "       Fix: Xcode → Target → Build Phases → Copy Bundle Resources → add PrivacyInfo.xcprivacy"
    echo "       Pitfall P14: submission via Transporter will reject with ITMS-91053."
    exit 1
fi

echo "OK: PrivacyInfo.xcprivacy present at $APP_PATH/PrivacyInfo.xcprivacy"
