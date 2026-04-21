#!/usr/bin/env bash
# scripts/install-hooks.sh — Validation Ledger iOS Client
# Run once after cloning the repo: `bash scripts/install-hooks.sh`
# Installs the pre-commit hook that runs SwiftLint + SwiftFormat on staged files.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOK_SRC="$REPO_ROOT/scripts/pre-commit.sh"

# Resolve hooks directory — handles both normal clones (.git/hooks/) and git
# worktrees (which route through .git/worktrees/<name>/hooks/ or share the
# common git dir's hooks/ directory). `git rev-parse --git-common-dir` returns
# the shared git dir across worktrees.
GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
if [ ! -d "$GIT_COMMON_DIR" ]; then
    # Relative path — resolve against worktree root
    GIT_COMMON_DIR="$REPO_ROOT/$GIT_COMMON_DIR"
fi
HOOKS_DIR="$GIT_COMMON_DIR/hooks"
mkdir -p "$HOOKS_DIR"
HOOK_DEST="$HOOKS_DIR/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
    echo "install-hooks: source hook not found at $HOOK_SRC"
    exit 1
fi

# Remove existing hook if present
if [ -e "$HOOK_DEST" ] || [ -L "$HOOK_DEST" ]; then
    echo "install-hooks: backing up existing hook to ${HOOK_DEST}.backup"
    mv "$HOOK_DEST" "${HOOK_DEST}.backup"
fi

# Symlink using an absolute path so the link works regardless of whether
# the hooks dir is a sibling of scripts/ (main repo) or nested inside
# .git/worktrees/<name>/ (worktree).
ln -s "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_SRC"

echo "✓ pre-commit hook installed: $HOOK_DEST → $HOOK_SRC"
echo "  Bypass in emergencies with: git commit --no-verify"
