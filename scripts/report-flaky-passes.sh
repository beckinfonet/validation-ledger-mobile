#!/bin/sh
# scripts/report-flaky-passes.sh
# Phase 4 Plan 10 Task 2 — D-15 flakiness-visibility reporter.
#
# Parses an xcresult bundle for tests that retried and passed on retry; POSTs
# to a Slack webhook so engineers see a flaky-pass signal instead of silent
# workflow-green masking of a real regression.
#
# Input:
#   $1 = path to .xcresult bundle (required).
#
# Environment:
#   SLACK_WEBHOOK_URL — if unset, the script exits 0 after logging (no post).
#   GITHUB_SHA, GITHUB_RUN_ID — included in the Slack message when present.
#
# Silent-exit-0 conditions:
#   (a) no xcresult supplied OR bundle missing.
#   (b) xcresulttool fails (format change, corrupt bundle).
#   (c) no retry markers detected in the result JSON.
#   (d) SLACK_WEBHOOK_URL unset (logged, skipped).
#
# Best-effort: ci-device.yml invokes this with `|| true` so the reporter
# never fails the workflow — masking-of-a-flake is worse than a missed ping.

set -eu

XCRESULT_PATH="${1:-}"
if [ -z "$XCRESULT_PATH" ] || [ ! -d "$XCRESULT_PATH" ]; then
    echo "No xcresult provided or bundle missing; skipping flaky-pass report."
    exit 0
fi

# Use xcrun xcresulttool (native Xcode) to extract test summary JSON.
JSON_OUT="/tmp/xcresult-$$.json"
xcrun xcresulttool get --path "$XCRESULT_PATH" --format json > "$JSON_OUT" 2>/dev/null || {
    echo "xcresulttool failed; skipping flaky-pass report."
    rm -f "$JSON_OUT"
    exit 0
}

# Look for any ActionTestMetadata with retry attempts > 1. The exact JSON path
# depends on Xcode version; grepping for common retry markers is the simplest
# format-resilient approach.
RETRY_COUNT=$(grep -c '"isRetry":true\|"retry_count":\|"numberOfTestRetries":' "$JSON_OUT" 2>/dev/null || echo 0)
# Fallback on a broader term if above nets nothing (xcresult JSON format varies):
if [ "$RETRY_COUNT" -eq 0 ]; then
    RETRY_COUNT=$(grep -c 'retried' "$JSON_OUT" 2>/dev/null || echo 0)
fi

rm -f "$JSON_OUT"

if [ "$RETRY_COUNT" -eq 0 ]; then
    echo "No test retries detected; quiet exit."
    exit 0
fi

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "Detected $RETRY_COUNT retry markers in xcresult, but SLACK_WEBHOOK_URL unset; skipping post."
    exit 0
fi

MESSAGE="validationLedger device CI — flaky-pass detected ($RETRY_COUNT retry markers). Commit: ${GITHUB_SHA:-unknown}. Run: ${GITHUB_RUN_ID:-unknown}. See artifact 'device-test-results'. Add .flaky annotation + tracking issue if this recurs (D-15)."

curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"text\": \"$MESSAGE\"}" \
    "$SLACK_WEBHOOK_URL" \
    || echo "Slack POST failed; continuing anyway."
