#!/usr/bin/env bash
# wt-setup.sh — Bootstrap a git worktree for parallel AI-agent development.
# Part of @thinkvelta/claude-worktree-tools.
#
# Usage:
#   ./scripts/wt-setup.sh <branch-name> [--base <base-branch>] [--reopen]
#
# Sections marked "REPO-SPECIFIC" are filled in by /wt-adopt.
# The "USER-DEFINED EXTRA SETUP" section is yours to customize freely.
# ──────────────────────────────────────────────────────────────

set -euo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║  GENERIC (do not edit)                                      ║
# ╚══════════════════════════════════════════════════════════════╝

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2
  exit 1
}

info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33mWARN:\033[0m %s\n' "$1" >&2
}

success() {
  printf '\033[1;32m==>\033[0m %s\n' "$1"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

BRANCH_NAME=""
BASE_BRANCH=""
REOPEN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ -z "${2:-}" ]] && die "--base requires a branch name argument"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --reopen)
      REOPEN=true
      shift
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -n "$BRANCH_NAME" ]] && die "Unexpected argument: $1 (branch name already set to '$BRANCH_NAME')"
      BRANCH_NAME="$1"
      shift
      ;;
  esac
done

[[ -z "$BRANCH_NAME" ]] && die "Usage: wt-setup.sh <branch-name> [--base <base-branch>] [--reopen]"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "Not inside a git repository"

# Convert slashes to hyphens for a human-readable prefix, then append a short
# hash of the original branch name to prevent collisions between branches that
# only differ in slash-vs-hyphen positions (e.g. feat/a-b vs feat/a/b).
SAFE_BRANCH="$(printf '%s' "$BRANCH_NAME" | tr '/' '-')"
BRANCH_HASH="$(printf '%s' "$BRANCH_NAME" | cksum | awk '{printf "%08x", $1}')"
WORKTREE_DIR="${REPO_ROOT}/.claude/worktrees/${SAFE_BRANCH}-${BRANCH_HASH}"

# Default base branch: main, then master, then current HEAD.
if [[ -z "$BASE_BRANCH" ]]; then
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    BASE_BRANCH="main"
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    BASE_BRANCH="master"
  else
    BASE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      || die "Cannot determine default base branch"
  fi
fi

# ┌──────────────────────────────────────────────────────────────┐
# │  Step 0 — Create the worktree                               │
# └──────────────────────────────────────────────────────────────┘

if [[ "$REOPEN" = true ]]; then
  # --reopen: skip creation, verify the worktree exists.
  if [[ ! -f "$WORKTREE_DIR/.git" ]]; then
    die "Cannot reopen: $WORKTREE_DIR is not a valid worktree (no .git entry found)"
  fi
  info "Reopening existing worktree at ${WORKTREE_DIR}"
else
  # --- Pre-checks -----------------------------------------------------------

  # Verify base branch exists.
  git show-ref --verify --quiet "refs/heads/${BASE_BRANCH}" 2>/dev/null \
    || die "Base branch '${BASE_BRANCH}' does not exist locally"

  # Check whether the branch is already checked out in another worktree.
  CHECKED_OUT_IN="$(
    git worktree list --porcelain \
      | awk -v branch="refs/heads/${BRANCH_NAME}" '
          /^worktree / { wt = substr($0, 10) }
          /^branch /   { if ($2 == branch) print wt }
        '
  )"
  if [[ -n "$CHECKED_OUT_IN" ]]; then
    die "Branch '${BRANCH_NAME}' is already checked out in worktree: ${CHECKED_OUT_IN}"
  fi

  # If the directory exists but is stale (not a valid worktree), prune first.
  if [[ -d "$WORKTREE_DIR" ]]; then
    if [[ ! -f "$WORKTREE_DIR/.git" ]]; then
      warn "Stale worktree directory detected — running git worktree prune"
      git worktree prune
      if [[ -d "$WORKTREE_DIR" ]]; then
        die "Directory ${WORKTREE_DIR} exists but is not a git worktree. Remove it manually."
      fi
    fi
  fi

  # --- Create the worktree ---------------------------------------------------

  # Ensure the parent directory exists.
  mkdir -p "$(dirname "$WORKTREE_DIR")"

  BRANCH_EXISTS=false
  if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}" 2>/dev/null; then
    BRANCH_EXISTS=true
  fi

  if [[ "$BRANCH_EXISTS" = true ]]; then
    info "Branch '${BRANCH_NAME}' exists — adding worktree (no new branch)"
    git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
  else
    info "Creating new branch '${BRANCH_NAME}' from '${BASE_BRANCH}'"
    git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" "$BASE_BRANCH"
  fi
fi

# ┌──────────────────────────────────────────────────────────────┐
# │  Step 1 — Copy .env files recursively                       │
# └──────────────────────────────────────────────────────────────┘

info "Copying .env files from main repo to worktree"

ENV_COUNT=0

while IFS= read -r -d '' env_file; do
  # Compute relative path from repo root.
  rel_path="${env_file#"${REPO_ROOT}"/}"

  # Create the target directory if needed.
  target_dir="${WORKTREE_DIR}/$(dirname "$rel_path")"
  mkdir -p "$target_dir"

  # Copy the file (overwrites on --reopen intentionally).
  cp "$env_file" "${WORKTREE_DIR}/${rel_path}"
  ENV_COUNT=$((ENV_COUNT + 1))
done < <(
  find "$REPO_ROOT" \
    -maxdepth 10 \
    -name '.env*' \
    -type f \
    -not -path "${REPO_ROOT}/.git/*" \
    -not -path "${REPO_ROOT}/.claude/*" \
    -print0
)

if [[ "$ENV_COUNT" -gt 0 ]]; then
  info "Copied ${ENV_COUNT} .env file(s)"
else
  info "No .env files found to copy"
fi

# ┌──────────────────────────────────────────────────────────────┐
# │  Step 2 — Derive stable port offset                         │
# └──────────────────────────────────────────────────────────────┘

# Deterministic offset from the worktree directory name (0–99).
# Same path always produces the same offset across reopens.
PORT_OFFSET="$(printf '%s' "$WORKTREE_DIR" | cksum | awk '{print $1 % 100}')"

info "Port offset for this worktree: ${PORT_OFFSET}"


# ╔══════════════════════════════════════════════════════════════╗
# ║  REPO-SPECIFIC PORT CONFIG (filled in by /wt-adopt)         ║
# ╚══════════════════════════════════════════════════════════════╝

# Uncomment and adjust the port variables below for your project.
# PORT_OFFSET (0–99) is derived above and is deterministic per worktree.
#
# Example for a typical full-stack app:
#
#   BACKEND_PORT=$((8000 + PORT_OFFSET))
#   FRONTEND_PORT=$((3000 + PORT_OFFSET))
#
#   # Update ports in the worktree .env (upsert pattern)
#   update_env_var() {
#     local file="$1" key="$2" val="$3"
#     if grep -q "^${key}=" "$file" 2>/dev/null; then
#       sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "${file}.bak"
#     else
#       echo "${key}=${val}" >> "$file"
#     fi
#   }
#
#   update_env_var "${WORKTREE_DIR}/.env" PORT "$BACKEND_PORT"
#   update_env_var "${WORKTREE_DIR}/.env" FRONTEND_PORT "$FRONTEND_PORT"
#
#   info "Ports — backend: ${BACKEND_PORT}, frontend: ${FRONTEND_PORT}"


# ╔══════════════════════════════════════════════════════════════╗
# ║  REPO-SPECIFIC INSTALL (filled in by /wt-adopt)             ║
# ╚══════════════════════════════════════════════════════════════╝

# Uncomment the install commands for your project.
#
# Node.js (npm):
#   info "Installing dependencies"
#   (cd "${WORKTREE_DIR}" && npm ci)
#
# Node.js (pnpm):
#   info "Installing dependencies"
#   (cd "${WORKTREE_DIR}" && pnpm install --frozen-lockfile)
#
# Python (uv):
#   info "Installing dependencies"
#   (cd "${WORKTREE_DIR}" && uv sync)
#
# Makefile:
#   info "Running setup"
#   make -C "${WORKTREE_DIR}" setup


# ╔══════════════════════════════════════════════════════════════╗
# ║  USER-DEFINED EXTRA SETUP                                   ║
# ╚══════════════════════════════════════════════════════════════╝

# Add any additional setup steps below. This section is never overwritten
# by /wt-adopt — it is yours to customize.
#
# Examples:
#   # Seed a local database
#   (cd "${WORKTREE_DIR}" && python manage.py migrate)
#
#   # Create a branch-specific database
#   createdb "myapp_$(echo "$BRANCH_NAME" | tr '/' '_')"
#
#   # Build step / warmup
#   (cd "${WORKTREE_DIR}" && npm run build)


# ╔══════════════════════════════════════════════════════════════╗
# ║  GENERIC — Summary (do not edit)                            ║
# ╚══════════════════════════════════════════════════════════════╝

echo ""
success "Worktree ready!"
echo ""
printf '  %-14s %s\n' "Branch:" "$BRANCH_NAME"
printf '  %-14s %s\n' "Base:" "$BASE_BRANCH"
printf '  %-14s %s\n' "Path:" "$WORKTREE_DIR"
printf '  %-14s %s\n' "Port offset:" "$PORT_OFFSET"
echo ""
