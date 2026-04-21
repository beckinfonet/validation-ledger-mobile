#!/usr/bin/env bash
# scripts/pre-commit.sh — Validation Ledger iOS Client
# Runs SwiftFormat --lint and SwiftLint --strict on staged .swift files.
# Invoked by .git/hooks/pre-commit (symlinked via scripts/install-hooks.sh).
#
# To bypass in an emergency: `git commit --no-verify`. Don't make a habit.

set -euo pipefail

# Find staged .swift files (added/changed/modified).
STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$' || true)
if [ -z "$STAGED" ]; then
    exit 0   # No Swift files staged — nothing to lint
fi

# Resolve swiftlint — prefer SwiftPM plugin artifact bundle (vendored via Package.swift),
# fall back to SwiftPM CLI resolution, fall back to Homebrew.
REPO_ROOT=$(git rev-parse --show-toplevel)
SWIFTLINT_ARTIFACT="$REPO_ROOT/.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint"
if [ -x "$SWIFTLINT_ARTIFACT" ]; then
    SWIFTLINT_CMD="$SWIFTLINT_ARTIFACT"
elif command -v swift &>/dev/null && swift run swiftlint --version &>/dev/null; then
    SWIFTLINT_CMD="swift run swiftlint"
elif command -v swiftlint &>/dev/null; then
    SWIFTLINT_CMD="swiftlint"
else
    echo "pre-commit: SwiftLint not found — run \`swift package resolve\` to vendor it, or install via Homebrew (brew install swiftlint)"
    exit 1
fi

# Resolve swiftformat — Homebrew or system install only (not vendored via SwiftPM).
if command -v swiftformat &>/dev/null; then
    SWIFTFORMAT_CMD="swiftformat"
else
    echo "pre-commit: SwiftFormat not found — install via Homebrew (brew install swiftformat)"
    echo "(continuing without format check — SwiftLint still runs)"
    SWIFTFORMAT_CMD=""
fi

echo "→ Pre-commit checks on $(echo "$STAGED" | wc -l | tr -d ' ') staged Swift file(s)"

# SwiftFormat — lint mode (does not mutate staged files; developer is expected to have run
# `swiftformat .` or Xcode's Editor → Code Actions → Format before staging).
if [ -n "$SWIFTFORMAT_CMD" ]; then
    echo "→ SwiftFormat (lint only)"
    # shellcheck disable=SC2086
    $SWIFTFORMAT_CMD --lint --config .swiftformat $STAGED
fi

# SwiftLint — strict mode (any violation = abort commit).
echo "→ SwiftLint (strict)"
# SwiftLint CLI takes paths as trailing args; pass staged files (max 20 to avoid arg-length issues).
FILES_TO_LINT=$(echo "$STAGED" | tr '\n' ' ' | awk '{for(i=1;i<=NF && i<=20;i++) printf "%s ", $i; print ""}')
# shellcheck disable=SC2086
$SWIFTLINT_CMD --strict --config .swiftlint.yml $FILES_TO_LINT

echo "✓ Pre-commit checks passed"
