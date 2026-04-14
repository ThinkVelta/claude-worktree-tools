#!/usr/bin/env bash
# local-install.sh — Install the toolkit into THIS repo and run /wt-adopt.
#
# Convenience wrapper for local development: installs skill files via
# try-install.sh, then invokes Claude Code to analyze the stack and
# customize wt-setup.sh.
#
# Usage:
#   ./local-install.sh
# ──────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf '\033[1;34m==>\033[0m Installing toolkit into current repo\n'
"${SCRIPT_DIR}/try-install.sh" . --force

printf '\033[1;34m==>\033[0m Running /wt-adopt to analyze stack and customize setup (this can take a few moments)\n'
claude -p "/wt-adopt" --dangerously-skip-permissions
printf '\033[1;34m==>\033[0m Finished running /wt-adopt\n'
