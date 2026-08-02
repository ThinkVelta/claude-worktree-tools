#!/usr/bin/env bash
# test.sh — Smoke test for @thinkvelta/claude-worktree-tools
#
# Usage:
#   ./test.sh [target-dir]
#
# Creates a temporary git repo (or uses the provided path), runs init.js,
# and verifies that all files are installed correctly.
# ──────────────────────────────────────────────────────────────

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_JS="${SCRIPT_DIR}/bin/init.js"
TARGET_DIR="${1:-${SCRIPT_DIR}/tmp/test-repo-$$}"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  printf '\033[1;31mFAIL:\033[0m %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '\033[1;32m  PASS\033[0m %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf '\033[1;31m  FAIL\033[0m %s\n' "$1"
  FAIL=$((FAIL + 1))
}

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

check_eval() {
  local desc="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

section() {
  echo ""
  printf '\033[1;34m==> %s\033[0m\n' "$1"
}

# ---------------------------------------------------------------------------
# Setup: ensure a git repo exists at the target
# ---------------------------------------------------------------------------

section "Setup"

if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "  Using existing git repo at $TARGET_DIR"
else
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init --quiet -b main
  git -C "$TARGET_DIR" config user.name "claude-worktree-tools test"
  git -C "$TARGET_DIR" config user.email "test@example.invalid"
  git -C "$TARGET_DIR" commit --allow-empty -m "initial commit" --quiet
  echo "  Created test repo at $TARGET_DIR"
fi

# ---------------------------------------------------------------------------
# Test 1: Basic install
# ---------------------------------------------------------------------------

section "Test 1 — Basic install"

(cd "$TARGET_DIR" && node "$INIT_JS" --force)

check "scripts/wt-setup.sh exists" test -f "$TARGET_DIR/scripts/wt-setup.sh"
check "scripts/wt-setup.sh is executable" test -x "$TARGET_DIR/scripts/wt-setup.sh"
check "wt-open skill exists" test -f "$TARGET_DIR/.claude/skills/wt-open/SKILL.md"
check "wt-merge skill exists" test -f "$TARGET_DIR/.claude/skills/wt-merge/SKILL.md"
check "wt-close skill exists" test -f "$TARGET_DIR/.claude/skills/wt-close/SKILL.md"
check "wt-list skill exists" test -f "$TARGET_DIR/.claude/skills/wt-list/SKILL.md"
check "wt-adopt skill exists" test -f "$TARGET_DIR/.claude/skills/wt-adopt/SKILL.md"
check "wt-help skill exists" test -f "$TARGET_DIR/.claude/skills/wt-help/SKILL.md"
check "wt-cleanup skill exists" test -f "$TARGET_DIR/.claude/skills/wt-cleanup/SKILL.md"
check ".gitignore contains .claude/worktrees" grep -q '.claude/worktrees' "$TARGET_DIR/.gitignore"

# Verify skill files have YAML frontmatter
check_eval "wt-open has SKILL.md frontmatter" "head -1 '$TARGET_DIR/.claude/skills/wt-open/SKILL.md' | grep -q '^---'"
check_eval "wt-setup.sh has shebang" "head -1 '$TARGET_DIR/scripts/wt-setup.sh' | grep -q '#!/usr/bin/env bash'"

# ---------------------------------------------------------------------------
# Test 2: Idempotency (second run skips existing files)
# ---------------------------------------------------------------------------

section "Test 2 — Idempotency (skip existing)"

OUTPUT=$( (cd "$TARGET_DIR" && node "$INIT_JS") 2>&1)

if echo "$OUTPUT" | grep -q "skip"; then
  pass "Second run skips existing files"
else
  fail "Second run should skip existing files"
fi

if echo "$OUTPUT" | grep -q "Nothing to do"; then
  pass "Reports nothing to do"
else
  fail "Should report nothing to do"
fi

# ---------------------------------------------------------------------------
# Test 3: --force overwrites
# ---------------------------------------------------------------------------

section "Test 3 — --force flag"

OUTPUT=$( (cd "$TARGET_DIR" && node "$INIT_JS" --force) 2>&1)

if echo "$OUTPUT" | grep -q "overwrite"; then
  pass "--force overwrites files"
else
  fail "--force should overwrite files"
fi

# ---------------------------------------------------------------------------
# Test 4: --dry-run
# ---------------------------------------------------------------------------

section "Test 4 — --dry-run flag"

# Use a subdirectory of the target for the dry-run test
DRY_RUN_DIR="${TARGET_DIR}/.test-dryrun"
mkdir -p "$DRY_RUN_DIR"
git -C "$DRY_RUN_DIR" init --quiet -b main
git -C "$DRY_RUN_DIR" config user.name "claude-worktree-tools test"
git -C "$DRY_RUN_DIR" config user.email "test@example.invalid"
git -C "$DRY_RUN_DIR" commit --allow-empty -m "initial commit" --quiet

OUTPUT=$( (cd "$DRY_RUN_DIR" && node "$INIT_JS" --dry-run) 2>&1)

if echo "$OUTPUT" | grep -q "dry run"; then
  pass "--dry-run prints actions"
else
  fail "--dry-run should print actions"
fi

check "--dry-run does not write files" test ! -f "$DRY_RUN_DIR/scripts/wt-setup.sh"

# ---------------------------------------------------------------------------
# Test 5: --scripts-dir
# ---------------------------------------------------------------------------

section "Test 5 — --scripts-dir flag"

CUSTOM_DIR="${TARGET_DIR}/.test-customdir"
mkdir -p "$CUSTOM_DIR"
git -C "$CUSTOM_DIR" init --quiet -b main
git -C "$CUSTOM_DIR" config user.name "claude-worktree-tools test"
git -C "$CUSTOM_DIR" config user.email "test@example.invalid"
git -C "$CUSTOM_DIR" commit --allow-empty -m "initial commit" --quiet

(cd "$CUSTOM_DIR" && node "$INIT_JS" --scripts-dir "tools")

check "--scripts-dir writes to custom path" test -f "$CUSTOM_DIR/tools/wt-setup.sh"
check "--scripts-dir does not write to default" test ! -f "$CUSTOM_DIR/scripts/wt-setup.sh"

# ---------------------------------------------------------------------------
# Test 6: Not a git repo
# ---------------------------------------------------------------------------

section "Test 6 — Not a git repo"

# Use a truly non-git directory (not inside any git repo)
NONGIT_DIR="$(mktemp -d)"

OUTPUT=$( (cd "$NONGIT_DIR" && node "$INIT_JS") 2>&1 || true)

if echo "$OUTPUT" | grep -q "Not a git repository"; then
  pass "Rejects non-git directory"
else
  fail "Should reject non-git directory"
fi

rmdir "$NONGIT_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 7: wt-setup.sh basic syntax check
# ---------------------------------------------------------------------------

section "Test 7 — Bash script syntax"

check "wt-setup.sh passes bash -n" bash -n "$TARGET_DIR/scripts/wt-setup.sh"

# ---------------------------------------------------------------------------
# Test 8: wt-setup.sh creates a worktree
# ---------------------------------------------------------------------------

section "Test 8 — wt-setup.sh creates a worktree"

# Use a unique branch name per run to avoid collisions when reusing the repo
TEST_BRANCH="test/smoke-$$"

# Mirror the directory-name derivation from wt-setup.sh: slashes → hyphens + 8-char hex hash.
_safe="$(printf '%s' "$TEST_BRANCH" | tr '/' '-')"
_hash="$(printf '%s' "$TEST_BRANCH" | cksum | awk '{printf "%08x", $1}')"
TEST_BRANCH_DIR="${_safe}-${_hash}"
unset _safe _hash

(cd "$TARGET_DIR" && bash scripts/wt-setup.sh "$TEST_BRANCH" --base main) 2>&1 | while IFS= read -r line; do echo "  $line"; done

check "Worktree directory exists" test -d "$TARGET_DIR/.claude/worktrees/$TEST_BRANCH_DIR"
check "Worktree has .git file" test -f "$TARGET_DIR/.claude/worktrees/$TEST_BRANCH_DIR/.git"
check_eval "Branch was created" "git -C '$TARGET_DIR' branch --list '$TEST_BRANCH' | grep -q '$TEST_BRANCH'"

# ---------------------------------------------------------------------------
# Test 9: wt-setup.sh --reopen
# ---------------------------------------------------------------------------

section "Test 9 — wt-setup.sh --reopen"

(cd "$TARGET_DIR" && bash scripts/wt-setup.sh "$TEST_BRANCH" --reopen) 2>&1 | while IFS= read -r line; do echo "  $line"; done

check "Reopen succeeds without error" true
check "Worktree still valid after reopen" test -f "$TARGET_DIR/.claude/worktrees/$TEST_BRANCH_DIR/.git"

# ---------------------------------------------------------------------------
# Test 10: --skills-only
# ---------------------------------------------------------------------------

section "Test 10 — --skills-only flag"

SKILLS_ONLY_DIR="${TARGET_DIR}/.test-skillsonly"
mkdir -p "$SKILLS_ONLY_DIR"
git -C "$SKILLS_ONLY_DIR" init --quiet -b main
git -C "$SKILLS_ONLY_DIR" config user.name "claude-worktree-tools test"
git -C "$SKILLS_ONLY_DIR" config user.email "test@example.invalid"
git -C "$SKILLS_ONLY_DIR" commit --allow-empty -m "initial commit" --quiet

(cd "$SKILLS_ONLY_DIR" && node "$INIT_JS" --skills-only)

check "--skills-only: wt-open skill installed" test -f "$SKILLS_ONLY_DIR/.claude/skills/wt-open/SKILL.md"
check "--skills-only: wt-close skill installed" test -f "$SKILLS_ONLY_DIR/.claude/skills/wt-close/SKILL.md"
check "--skills-only: wt-setup.sh not created" test ! -f "$SKILLS_ONLY_DIR/scripts/wt-setup.sh"
check_eval "--skills-only: .gitignore not modified" "! grep -q '.claude/worktrees' '$SKILLS_ONLY_DIR/.gitignore' 2>/dev/null"

# ---------------------------------------------------------------------------
# Test 11: .claude/skills parity with templates/skills
# ---------------------------------------------------------------------------

section "Test 11 — .claude/skills parity with templates/skills"

for skill in wt-open wt-close wt-cleanup wt-help wt-list wt-merge wt-adopt; do
  src="${SCRIPT_DIR}/.claude/skills/${skill}/SKILL.md"
  tpl="${SCRIPT_DIR}/templates/skills/${skill}/SKILL.md"
  if [ -f "$src" ] && [ -f "$tpl" ]; then
    if diff -q "$src" "$tpl" >/dev/null 2>&1; then
      pass "${skill}: .claude and templates copies are identical"
    else
      fail "${skill}: .claude and templates copies differ"
    fi
  elif [ ! -f "$src" ] && [ ! -f "$tpl" ]; then
    pass "${skill}: both copies absent (not yet added)"
  else
    fail "${skill}: one copy exists but not the other"
  fi
done

# ---------------------------------------------------------------------------
# Test 12: the README demo is generated, current, and leak-free
# ---------------------------------------------------------------------------

section "Test 12 — README demo block is up to date"

# Running the generator here is what puts it under CI, on both OSes in the
# matrix — otherwise a 170-line script that touches sed, cksum and mktemp (all
# of which differ between BSD and GNU) would ship untested. It also catches the
# README drifting from what the setup script actually prints.

DEMO_SH="${SCRIPT_DIR}/scripts/make-demo.sh"
README_MD="${SCRIPT_DIR}/README.md"

if [ ! -f "$DEMO_SH" ]; then
  fail "scripts/make-demo.sh is missing"
elif [ ! -f "$README_MD" ]; then
  fail "README.md is missing"
else
  DEMO_EXPECTED="${TARGET_DIR}/demo-expected.md"
  DEMO_ACTUAL="${TARGET_DIR}/demo-actual.md"

  # A non-zero exit here means the generator failed OR its leak guard fired.
  # Either way the demo must not be trusted.
  if bash "$DEMO_SH" >"$DEMO_EXPECTED" 2>"${TARGET_DIR}/demo-err.txt"; then
    pass "make-demo.sh runs and its privacy assertions hold"

    sed -n '/^<!-- BEGIN GENERATED DEMO -->$/,/^<!-- END GENERATED DEMO -->$/p' \
      "$README_MD" >"$DEMO_ACTUAL"

    if diff -u "$DEMO_ACTUAL" "$DEMO_EXPECTED" >/dev/null 2>&1; then
      pass "README demo block matches the generator output"
    else
      fail "README demo block is stale — run 'make demo' and commit the result"
      diff -u "$DEMO_ACTUAL" "$DEMO_EXPECTED" | head -20 || true
    fi

    # Belt and braces: assert on the committed README itself, not just on the
    # generator, so a hand-edited block cannot smuggle a real path back in.
    # Mask the one allowed prefix, then reject ANY remaining absolute path —
    # an allowlist. A denylist here missed ordinary paths like
    # /home/runner/work/repo that do not happen to be followed by a dot.
    #
    # This list must stay identical to make-demo.sh's; the assertion below
    # enforces that, because the two drifted apart once — the generator
    # rejected /tmp/ and this check did not, so a /tmp path would have passed
    # the committed-README guard.
    FORBIDDEN_PATHS="/Users/ /home/ /root/ /private/ /var/folders/ /tmp/"

    if grep -qF "FORBIDDEN_PATHS=\"${FORBIDDEN_PATHS}\"" "$DEMO_SH"; then
      pass "forbidden-path list matches the generator's"
    else
      fail "forbidden-path list has drifted from scripts/make-demo.sh"
    fi

    sed 's|/home/dev/acme-api||g' "$DEMO_ACTUAL" >"${DEMO_ACTUAL}.masked"
    found_path=""
    for probe in $FORBIDDEN_PATHS; do
      if grep -qF -- "$probe" "${DEMO_ACTUAL}.masked"; then
        found_path="${found_path} ${probe}"
      fi
    done
    if [ -n "$found_path" ]; then
      fail "README demo block contains absolute path(s) that are not the fixture:${found_path}"
    else
      pass "README demo block contains no real filesystem path"
    fi
  else
    fail "make-demo.sh failed or refused to emit (see ${TARGET_DIR}/demo-err.txt)"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "════════════════════════════════════════"
printf '  \033[1;32m%d passed\033[0m' "$PASS"
if [[ "$FAIL" -gt 0 ]]; then
  printf ', \033[1;31m%d failed\033[0m' "$FAIL"
fi
echo ""
echo "════════════════════════════════════════"
echo ""
echo "Test repo at: $TARGET_DIR"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
