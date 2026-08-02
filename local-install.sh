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

# /wt-adopt rewrites scripts/wt-setup.sh, so it needs write permission. Ask for
# it interactively by default rather than disabling the permission prompts —
# this file is public, and a script that silently passes
# --dangerously-skip-permissions is exactly the thing people copy without
# reading. Opt in explicitly when running unattended:
#   WT_SKIP_PERMISSIONS=1 ./local-install.sh
if [[ "${WT_SKIP_PERMISSIONS:-0}" == "1" ]]; then
  claude -p "/wt-adopt" --dangerously-skip-permissions
else
  claude "/wt-adopt"
fi

printf '\033[1;34m==>\033[0m Finished running /wt-adopt\n'
