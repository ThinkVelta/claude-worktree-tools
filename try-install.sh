#!/usr/bin/env bash
# try-install.sh — Install the toolkit into a local repo for testing.
#
# This is the local equivalent of `npx @thinkvelta/claude-worktree-tools`.
# It runs bin/init.js against the target repo, adding the worktree skill
# files and setup script without touching anything else.
#
# Usage:
#   ./try-install.sh <path-to-repo> [--force] [--dry-run]
#
# Examples:
#   ./try-install.sh ~/Projects/my-app
#   ./try-install.sh ~/Projects/my-app --force
#   ./try-install.sh ~/Projects/my-app --dry-run
# ──────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_JS="${SCRIPT_DIR}/bin/init.js"

TARGET_DIR="${1:-}"
shift || true

if [[ -z "$TARGET_DIR" ]]; then
  echo "Usage: try-install.sh <path-to-repo> [--force] [--dry-run]"
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "error: $TARGET_DIR does not exist"
  exit 1
fi

(cd "$TARGET_DIR" && node "$INIT_JS" "$@")
