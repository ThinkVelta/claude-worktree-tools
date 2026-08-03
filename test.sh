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
# Test 12: worktree path derivation agrees between the script and the skills
# ---------------------------------------------------------------------------

section "Test 12 — worktree path derivation is consistent"

# The setup script is the single source of truth for where a worktree lands.
# A skill that documents a different derivation sends the agent to a directory
# that was never created, so assert the two cannot drift apart.

# Substring checks would not be enough here: `printf '%s\n'` contains `printf`
# but hashes a trailing newline, and a skill can name ${BRANCH_HASH} without
# ever defining it. So RUN the derivation each skill documents and compare the
# directory name it produces against the one Test 8 watched wt-setup.sh create.
#
# `eval` on file content is normally a smell; here the input is a tracked file
# in this repo and running it is the only way to test what it actually computes.

for tpl in "${SCRIPT_DIR}"/templates/skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$tpl")")"
  grep -qF 'WORKTREE_DIR=' "$tpl" 2>/dev/null || continue

  # Pull the assignment lines out of the fenced block and bind them to the same
  # branch name Test 8 used.
  derivation="$(grep -E '^(SAFE_BRANCH|BRANCH_HASH|WORKTREE_DIR)=' "$tpl" | sed "s|<branch-name>|${TEST_BRANCH}|g")"

  if [[ -z "$derivation" ]]; then
    fail "${skill}: mentions WORKTREE_DIR but documents no derivation to check"
    continue
  fi

  # Run it once against a known REPO_ROOT and report the full path it computes.
  # WORKTREE_DIR starts empty so a derivation that never assigns it, or that
  # references an undefined BRANCH_HASH, yields something that cannot match.
  #
  # Keep every comment OUT of the $( ) below. bash 3.2 (still /bin/bash on
  # macOS) scans command substitutions naively, so an apostrophe inside a
  # comment in there is read as an opening quote and the script dies with
  # "unexpected EOF while looking for matching". Both variables below are read
  # by the evaluated derivation, hence the SC2034 waiver.
  # shellcheck disable=SC2034
  documented_path="$(
    REPO_ROOT="/repo"
    WORKTREE_DIR=""
    eval "$derivation" >/dev/null 2>&1
    printf '%s' "$WORKTREE_DIR"
  )"

  if [[ "$documented_path" == "/repo/.claude/worktrees/${TEST_BRANCH_DIR}" ]]; then
    pass "${skill}: documented derivation produces the path wt-setup.sh creates"
  else
    fail "${skill}: documented derivation gives '${documented_path}', expected '/repo/.claude/worktrees/${TEST_BRANCH_DIR}'"
  fi
done

# ---------------------------------------------------------------------------
# Test 13: the README demo is generated, current, and leak-free
# ---------------------------------------------------------------------------

section "Test 13 — README demo block is up to date"

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
    # The pattern is READ FROM the generator rather than restated here. An
    # earlier version kept a second copy and asserted the two matched; they
    # drifted anyway (the generator rejected /tmp/, this check did not), and
    # comparing quoted source text is brittle. One declaration, no copy.
    gen_line="$(grep -m1 '^ABSOLUTE_PATH_RE=' "$DEMO_SH" || true)"
    if [ -z "$gen_line" ]; then
      fail "scripts/make-demo.sh declares no ABSOLUTE_PATH_RE to reuse"
      ABSOLUTE_PATH_RE='(^|[[:space:]])/[[:alnum:]]'
    else
      eval "$gen_line"
      pass "absolute-path pattern read from the generator"
    fi

    # A pattern that matches nothing would make every check below vacuous, so
    # prove it discriminates. Foreign roots must be rejected whatever character
    # precedes them — a space-only fixture hid a real gap, where paths after
    # `[`, `,` or `{` bypassed the guard.
    re_ok=true
    for bad in \
      'Path: /opt/company/repo' \
      'Path: /Volumes/work/repo' \
      'output[/Users/alice/project]' \
      'path,/Volumes/private/repo' \
      'value{/opt/company/repo}' \
      '/home/bob/repo at line start'; do
      printf '%s\n' "$bad" | grep -qE "$ABSOLUTE_PATH_RE" || re_ok=false
    done
    # …and the masked fixture, plus a URL, must NOT be rejected.
    for good in \
      'Path: DEMOPATH/.claude/worktrees/x' \
      '$ ./scripts/wt-setup.sh feat/rate-limiting' \
      'see https://example.com/a/b'; do
      ! printf '%s\n' "$good" | grep -qE "$ABSOLUTE_PATH_RE" || re_ok=false
    done
    if [ "$re_ok" = true ]; then
      pass "pattern rejects foreign paths at any boundary, accepts the fixture"
    else
      fail "pattern does not discriminate foreign paths from the masked fixture"
    fi

    # Placeholder, not deletion: removing the prefix would leave /.claude/…,
    # itself an absolute path, and fail on the fixture it is meant to permit.
    sed 's|/home/dev/acme-api|DEMOPATH|g' "$DEMO_ACTUAL" >"${DEMO_ACTUAL}.masked"
    if grep -qE "$ABSOLUTE_PATH_RE" "${DEMO_ACTUAL}.masked"; then
      fail "README demo block contains an absolute path that is not the fixture"
      grep -nE "$ABSOLUTE_PATH_RE" "${DEMO_ACTUAL}.masked" | head -3 || true
    else
      pass "README demo block contains no absolute path but the fixture"
    fi
  else
    fail "make-demo.sh failed or refused to emit (see ${TARGET_DIR}/demo-err.txt)"
  fi
fi

# ---------------------------------------------------------------------------
# Test 14: the secret-redaction hook actually redacts
# ---------------------------------------------------------------------------

section "Test 14 — redact-secrets hook masks without destroying"

# This hook failed silently in four different ways across the org before anyone
# noticed, because a broken filter and a healthy one look identical from
# outside: emitting nothing on exit 0 is its DESIGNED "nothing to redact"
# signal. So assert behaviour, not shape.
#
# Sentinels: SECRET_SENTINEL must never survive; every KEEP_nn must.

REDACT_SH="${SCRIPT_DIR}/.claude/hooks/redact-secrets.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped: jq not installed — the hook fails open without it by design)"
elif [ ! -f "$REDACT_SH" ]; then
  fail ".claude/hooks/redact-secrets.sh is missing"
else
  SECRET_SENTINEL="Qw7Ab9XyZ2Lm4Np8"

  redact_case() { # <label> <stdout literal> <expect: masked|passthrough>
    local label="$1" body="$2" expect="$3" payload out stdout_out
    payload=$(jq -n --arg s "$body" \
      '{hook_event_name:"PostToolUse",tool_name:"Bash",
        tool_response:{stdout:$s,stderr:"",interrupted:false}}')
    out=$(printf '%s' "$payload" | "$REDACT_SH" 2>/dev/null)

    if [ -z "$out" ]; then
      stdout_out="$body" # nothing emitted => Claude Code keeps the original
    else
      stdout_out=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null)
      if [ -z "$stdout_out" ]; then
        fail "${label}: hook emitted output that is not a valid replacement"
        return
      fi
    fi

    if [ "$expect" = "masked" ] && printf '%s' "$stdout_out" | grep -qF "$SECRET_SENTINEL"; then
      fail "${label}: secret survived redaction"
      return
    fi
    # Secret-free output must come back byte-identical. Checking only the line
    # count and one sentinel would let over-redaction through — the `sk-` rule
    # firing inside ordinary words did exactly that, and looked clean.
    if [ "$expect" = "passthrough" ] && [ "$stdout_out" != "$body" ]; then
      fail "${label}: secret-free output was modified"
      return
    fi
    # Nothing benign may be destroyed, and no line may vanish.
    local want_lines got_lines
    want_lines=$(printf '%s' "$body" | grep -c '')
    got_lines=$(printf '%s' "$stdout_out" | grep -c '')
    if [ "$want_lines" != "$got_lines" ]; then
      fail "${label}: line count changed ${want_lines} -> ${got_lines}"
      return
    fi
    if printf '%s' "$body" | grep -qF 'KEEP_01' && ! printf '%s' "$stdout_out" | grep -qF 'KEEP_01'; then
      fail "${label}: destroyed benign output"
      return
    fi
    pass "$label"
  }

  # The four forms that leaked or destroyed output in other repos' copies.
  redact_case "plain KEY=VALUE" "AUTH_SECRET=${SECRET_SENTINEL}
KEEP_01" masked
  redact_case "JSON config dump" "{\"AUTH_SECRET\": \"${SECRET_SENTINEL}\"}
KEEP_01" masked
  redact_case "YAML quoted value" "AUTH_SECRET: \"${SECRET_SENTINEL}\"
KEEP_01" masked
  redact_case "tab separator" "$(printf 'AUTH_SECRET\t=\t%s\nKEEP_01' "$SECRET_SENTINEL")" masked
  # Secret-free output must come through untouched. This is the over-redaction
  # guard: `sk-` used to fire inside ordinary words.
  redact_case "no secret present" "risk-management-dashboard-v2
disk-utilization-report-2024
KEEP_01" passthrough

  # …and the other direction. A distinctive token concatenated after a word
  # character must STILL be masked: putting `\b` on every prefix (rather than
  # just the collision-prone sk- ones) turned each of these into a bypass.
  redact_concat() { # <label> <token>
    local label="$1" tok="$2" payload out stdout_out
    payload=$(jq -n --arg s "credential_${tok}
KEEP_01" '{hook_event_name:"PostToolUse",tool_name:"Bash",
               tool_response:{stdout:$s,stderr:"",interrupted:false}}')
    out=$(printf '%s' "$payload" | "$REDACT_SH" 2>/dev/null)
    if [ -z "$out" ]; then
      fail "${label}: concatenated token was not redacted at all"
      return
    fi
    stdout_out=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null)
    if printf '%s' "$stdout_out" | grep -qF "$tok"; then
      fail "${label}: concatenated token survived"
    elif ! printf '%s' "$stdout_out" | grep -qF 'KEEP_01'; then
      fail "${label}: destroyed benign output"
    else
      pass "$label"
    fi
  }

  redact_concat "concatenated github_pat_ masked" "github_pat_ABCDEFGHIJKLMNOPQRSTUV"
  redact_concat "concatenated ghp_ masked" "ghp_ABCDEFGHIJKLMNOPQRSTUVWX01"
  redact_concat "concatenated AKIA masked" "AKIAIOSFODNN7EXAMPLE"

  # The value group is a tempered token. Both halves of that need pinning, or
  # it can revert to a plain class without the suite noticing.
  #
  # (a) it must not cross a LITERAL backslash-n — two characters, as emitted by
  #     docker inspect / kubectl -o json / gh api. Note the double quotes: bash
  #     does not interpret \n there, so this really is backslash + n.
  tempered_body="AUTH_SECRET=${SECRET_SENTINEL}\nKEEP_01 KEEP_02"
  payload=$(jq -n --arg s "$tempered_body" \
    '{hook_event_name:"PostToolUse",tool_name:"Bash",
      tool_response:{stdout:$s,stderr:"",interrupted:false}}')
  out=$(printf '%s' "$payload" | "$REDACT_SH" 2>/dev/null)
  got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null)
  #     KEEP_01 is the discriminating sentinel, not KEEP_02: an untempered
  #     class stops at the first real SPACE, so it swallows `\nKEEP_01` but
  #     leaves KEEP_02 standing. Asserting on KEEP_02 would pass either way.
  if [ -z "$out" ]; then
    fail "literal backslash-n: secret was not redacted at all"
  elif printf '%s' "$got" | grep -qF "$SECRET_SENTINEL"; then
    fail "literal backslash-n: secret survived"
  elif ! printf '%s' "$got" | grep -qF 'KEEP_01'; then
    fail "literal backslash-n: content after the escape was swallowed"
  else
    pass "literal backslash-n does not swallow what follows"
  fi

  # (b) a LONE backslash inside a secret must stay inside the match, so the
  #     value is masked in full. Excluding all backslashes (an earlier attempt)
  #     leaked everything after the first one.
  backslash_tail="zAbQwLm4Np8"
  payload=$(jq -n --arg s "AUTH_SECRET=Xy\\${backslash_tail}
KEEP_01" '{hook_event_name:"PostToolUse",tool_name:"Bash",
            tool_response:{stdout:$s,stderr:"",interrupted:false}}')
  out=$(printf '%s' "$payload" | "$REDACT_SH" 2>/dev/null)
  got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null)
  if [ -z "$out" ]; then
    fail "lone backslash: secret was not redacted at all"
  elif printf '%s' "$got" | grep -qF "$backslash_tail"; then
    fail "lone backslash: value leaked its tail after the backslash"
  elif ! printf '%s' "$got" | grep -qF 'KEEP_01'; then
    fail "lone backslash: destroyed benign output"
  else
    pass "lone backslash in a secret is masked in full"
  fi

  # PEM blocks. The encrypted form carries Proc-Type/DEK-Info headers whose
  # `:` `,` `-` are not base64 — a base64-only body stops redacting exactly the
  # keys someone bothered to encrypt, which is the wrong way round.
  # Assembled at runtime: a literal PEM header in this file would be caught by
  # the detect-private-key hook, which is working as intended.
  D5="-----"
  KW="PRIVATE KEY"                          # split from the label so the phrase detect-private-key
  PEM_BEGIN_RSA="${D5}BEGIN RSA ${KW}${D5}" # blacklists never appears here
  PEM_END_RSA="${D5}END RSA ${KW}${D5}"
  PEM_END_EC="${D5}END EC ${KW}${D5}"
  PEM_BEGIN="${D5}BEGIN ${KW}${D5}" # unlabelled PKCS#8 form
  PEM_END="${D5}END ${KW}${D5}"

  redact_pem() { # <label> <body> <expect: masked|passthrough>
    local label="$1" body="$2" expect="$3" payload out stdout_out
    payload=$(jq -n --arg s "$body" \
      '{hook_event_name:"PostToolUse",tool_name:"Bash",
        tool_response:{stdout:$s,stderr:"",interrupted:false}}')
    out=$(printf '%s' "$payload" | "$REDACT_SH" 2>/dev/null)
    if [ -z "$out" ]; then
      stdout_out="$body"
    else
      stdout_out=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null)
    fi
    if [ "$expect" = "masked" ]; then
      if printf '%s' "$stdout_out" | grep -qF "PRIVATE KEY${D5}"; then
        fail "${label}: private key block survived"
      elif ! printf '%s' "$stdout_out" | grep -qF 'KEEP_01'; then
        fail "${label}: destroyed benign output"
      else
        pass "$label"
      fi
    else
      if [ "$stdout_out" != "$body" ]; then
        fail "${label}: unrelated output was modified"
      else
        pass "$label"
      fi
    fi
  }

  # Body lines are 64 characters, the width openssl actually wraps at. Earlier
  # revisions of these fixtures used 12-20 character bodies, which no real key
  # has, and so could not detect a rule that requires a substantial base64 line.
  redact_pem "plain PEM masked" "${PEM_BEGIN_RSA}
MIIEowIBAAKCAQEAr4V2mCVJ0kFtLqPZ8Nx3QwErTyUiOpAsDfGhJkLzXcVbNm12
QwErTyUiOpAsDfGhJkLzXcVbNm34
${PEM_END_RSA}
KEEP_01" masked

  redact_pem "encrypted PEM masked" "${PEM_BEGIN_RSA}
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-256-CBC,0123456789ABCDEF

MIIEowIBAAKCAQEAr4V2mCVJ0kFtLqPZ8Nx3QwErTyUiOpAsDfGhJkLzXcVbNm12
QUJDREVGR0g=
${PEM_END_RSA}
KEEP_01" masked

  # The smallest real private key shape: an ed25519 PKCS#8 body is 48 bytes of
  # DER, one single 64-character base64 line. Nothing legitimate is shorter, so
  # this pins the low end of the length requirement.
  redact_pem "minimal single-line key masked" "${PEM_BEGIN}
MC4CAQAwBQYDK2VwBCIEIHqLmNoPqRsTuVwXyZ0123456789AbCdEfGhIjKlMnOp
${PEM_END}
KEEP_01" masked

  # Two unrelated grep hits must not be paired up and everything between them
  # deleted; nor may a BEGIN pair with a differently-labelled END.
  redact_pem "grep transcript untouched" "a.pem:1:${PEM_BEGIN_RSA}
KEEP_01 docs/notes.md:44 mentions keys
b.pem:9:${PEM_END_RSA}" passthrough

  redact_pem "mismatched labels untouched" "${PEM_BEGIN_RSA}
KEEP_01 unrelated output
${PEM_END_EC}" passthrough

  # Same labels, and the intervening text is letters and spaces only — both of
  # which live in any base64-ish character class. This is why the body has to
  # be validated line by line rather than character by character; the grep
  # fixture above passes on punctuation alone and would not have caught it.
  # No underscore or punctuation anywhere in the prose — those are outside any
  # base64-ish class and would make this fixture pass for the wrong reason.
  # Pure letters and spaces is what actually discriminates. (passthrough
  # compares byte-for-byte, so no sentinel is needed.)
  redact_pem "prose between same labels untouched" "${PEM_BEGIN_RSA}
this is ordinary prose with only letters and spaces
and another such line here
${PEM_END_RSA}" passthrough

  # Single-word lines are valid base64-ALPHABET lines, so "letters only" is not
  # enough on its own — the payload itself has to be checked.
  redact_pem "single-word lines untouched" "${PEM_BEGIN_RSA}
hello
world
${PEM_END_RSA}" passthrough

  # Nor is "contains a long run" enough: this body has a 41-character line. It
  # is rejected because the concatenated payload is 59 characters, and base64
  # always encodes to a multiple of 4.
  redact_pem "long alphabetic run untouched" "${PEM_BEGIN_RSA}
ThisIsALongIdentifierOfFortyPlusCharsHere
SomeMoreOutputText
${PEM_END_RSA}" passthrough
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
