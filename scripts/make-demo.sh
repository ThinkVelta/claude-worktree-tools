#!/usr/bin/env bash
# make-demo.sh — Regenerate the worked example shown in README.md.
#
# Usage:
#   ./scripts/make-demo.sh            # print the fenced block to stdout
#   ./scripts/make-demo.sh --write    # splice it into README.md in place
#
# Why this exists: the README needs to show what the toolkit actually does, and
# the obvious way to get that — record a real session in a real repo — puts the
# maintainer's home directory, project layout and shell history on the internet.
# It already did once. So the demo is generated instead: a throwaway repo with
# invented content, the real script run against it, plain stdout captured, and
# the scratch path rewritten to a neutral one.
#
# The scrub is ASSERTED, not assumed (see "Refuse to emit a leak" below). That is
# the part that matters: a previous hand-scrubbed terminal recording passed a
# grep of the raw file and still leaked, because the terminal had redrawn the
# real path one character at a time and no contiguous match existed. Plain
# captured stdout has no such redraw, and the assertion proves it every run.
# ──────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Everything a reader sees. Invented, and deliberately nothing to do with this
# repo or its author.
DEMO_ROOT="/home/dev"
DEMO_REPO="acme-api"
DEMO_BRANCH="feat/rate-limiting"
BEGIN_MARKER="<!-- BEGIN GENERATED DEMO -->"
END_MARKER="<!-- END GENERATED DEMO -->"

# A real allowlist: after the one permitted fixture path is masked out, NO
# absolute path may remain, whatever its root. An earlier version enumerated
# roots (/Users/, /home/, /tmp/, …) and called itself an allowlist, which it
# was not — /opt/company/repo, /srv/build, /mnt/x and /Volumes/work all sailed
# through. Enumerating roots cannot be made complete, so don't try.
#
# Matches a `/` that begins a path: at line start, or after any character that
# cannot itself be part of a path. Enumerating the boundary characters instead
# (whitespace, quote, `=`, `(`) left `output[/Users/alice]`, `path,/Volumes/x`
# and `value{/opt/y}` slipping through — the same "enumerate what I thought of"
# mistake as the earlier root list, one level down.
#
# `/` is excluded from the boundary class on purpose, so `https://host/path`
# does not read as an absolute path.
#
# test.sh reads this declaration rather than keeping a copy.
ABSOLUTE_PATH_RE='(^|[^[:alnum:]_./-])/[[:alnum:]_.-]'

WRITE=false
KEEP_ON_FAILURE=false
for arg in "$@"; do
  case "$arg" in
    --write) WRITE=true ;;
    --keep-on-failure) KEEP_ON_FAILURE=true ;;
    *)
      echo "usage: make-demo.sh [--write] [--keep-on-failure]" >&2
      exit 2
      ;;
  esac
done

WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null || true; find "$WORK" -mindepth 1 -delete 2>/dev/null || true; rmdir "$WORK" 2>/dev/null || true' EXIT

# macOS hands out /var/folders/… but git reports the resolved /private/var/…
# form, so both spellings have to be rewritten or half the prefix survives and
# the demo shows a path like /private/home/dev.
WORK_PHYS="$(cd "$WORK" && pwd -P)"

TARGET="$WORK/$DEMO_REPO"
mkdir -p "$TARGET"

git -C "$TARGET" init --quiet -b main
git -C "$TARGET" config user.name "Dev"
git -C "$TARGET" config user.email "dev@example.invalid"
# Fixed timestamps so the commit SHAs the script echoes are stable and
# `make demo` is idempotent — otherwise every regeneration churns the README.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+00:00"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00+00:00"
printf 'PORT=8000\nDATABASE_URL=postgres://localhost:5432/acme\n' >"$TARGET/.env.example"
printf '# acme-api\n\nA small service.\n' >"$TARGET/README.md"
git -C "$TARGET" add -A
git -C "$TARGET" commit --quiet -m "initial commit"

# Install the toolkit from THIS checkout, so the demo always shows current behaviour.
(cd "$TARGET" && node "$REPO_ROOT/bin/init.js" >/dev/null)
git -C "$TARGET" add -A
git -C "$TARGET" commit --quiet -m "add worktree toolkit"

# The escape byte comes from printf rather than a `\x1b` literal: GNU sed
# understands that escape, but it is not in POSIX and BSD seds vary. Building
# the byte first works everywhere.
ESC="$(printf '\033')"

# Single scrubber, used for the emitted demo AND for every diagnostic. Nothing
# in this script prints captured output any other way — a failure path that
# dumps the raw capture would spill the real scratch path into a terminal or a
# public CI log, which is the whole thing this script exists to prevent.
# Longest prefix first, so the resolved form never leaves a stub like /private.
scrub() {
  sed -e "s/${ESC}\[[0-9;]*m//g" \
    -e "s|$WORK_PHYS|$DEMO_ROOT|g" \
    -e "s|$WORK|$DEMO_ROOT|g" \
    "$1"
}

# Run the real script and capture plain stdout+stderr. No tty, so no redraw.
RAW="$WORK/raw.txt"
(cd "$TARGET" && bash scripts/wt-setup.sh "$DEMO_BRANCH" --base main) >"$RAW" 2>&1 || {
  # Deliberately NOT printing the capture, and NOT printing where it is.
  # scrub() only rewrites the scratch path and ANSI; anything else the failing
  # script echoed has not been checked yet, and this branch runs before the
  # privacy checks below. The scratch path is not safe to print either —
  # mktemp honours $TMPDIR, which can sit under a home directory, and this
  # repo's CI logs are public.
  echo "demo run failed. Captured output withheld and removed: it has not been" >&2
  echo "privacy-checked, and neither has the path it was written to." >&2
  if [[ "$KEEP_ON_FAILURE" == true ]]; then
    trap - EXIT
    echo "Retained for inspection at: $RAW" >&2
    echo "(--keep-on-failure was passed; do not pass it in CI)" >&2
  else
    echo "Re-run locally with --keep-on-failure to inspect it." >&2
  fi
  exit 1
}

CLEAN="$WORK/clean.txt"
scrub "$RAW" >"$CLEAN"

# ---------------------------------------------------------------------------
# Refuse to emit a leak
# ---------------------------------------------------------------------------
# Anything that could identify the machine this ran on is a hard failure. The
# generator is the only place this can be enforced, because by the time the
# output is in the README nobody re-checks it.
#
# Every check runs against the output with the ALLOWED demo path masked out
# first. That ordering matters twice over:
#
#   * It makes the absolute-path check an allowlist — "no absolute path may
#     survive except the invented one" — rather than a denylist of the
#     machine values we happened to think of.
#   * It removes a guaranteed false positive. The demo path is /home/dev/…, so
#     a developer whose username is `dev` (or whose $HOME is /home/dev) would
#     otherwise trip the guard on the fixture itself and never be able to
#     regenerate. The same goes for any username that is a substring of the
#     fixture — `api`, `acme`, `demo`.
# Masked to a PLACEHOLDER, not to nothing: deleting the prefix would turn
# /home/dev/acme-api/.claude/… into /.claude/…, which is itself an absolute
# path and would trip the check below on the fixture it is meant to permit.
DEMO_PREFIX="$DEMO_ROOT/$DEMO_REPO"
MASKED="$WORK/masked.txt"
sed "s|$DEMO_PREFIX|DEMOPATH|g" "$CLEAN" >"$MASKED"

USERNAME="$(id -un)"
leaked=""

# Absolute paths: after masking, NO absolute path may remain, whatever its root.
if grep -qE "$ABSOLUTE_PATH_RE" "$MASKED"; then
  leaked="${leaked}  - an absolute path that is not the fixture"$'\n'
fi

# Machine values, also checked post-masking. Very short values are skipped:
# masking cannot make a 1-3 character username meaningful to test, and the
# path allowlist above already covers the case that matters.
for pattern in "$HOME" "$USERNAME" "$WORK" "$WORK_PHYS"; do
  [[ -z "$pattern" || "$pattern" == "/" || ${#pattern} -lt 4 ]] && continue
  if grep -qF -- "$pattern" "$MASKED" 2>/dev/null; then
    leaked="${leaked}  - a machine-identifying value (${#pattern} chars)"$'\n'
  fi
done

# The demo path itself must be present, and must be the invented one.
if ! grep -qF -- "$DEMO_PREFIX/.claude/worktrees/" "$CLEAN"; then
  leaked="${leaked}  - expected worktree path under $DEMO_PREFIX is absent"$'\n'
fi

# The port offset is cksum(worktree path) % 100, so the number the script
# printed belongs to the scratch path, not the one the reader sees. Rewrite it
# to the offset the DISPLAYED path really produces, so a reader can reproduce
# it. Without this the demo would show a number that is simply wrong for the
# path next to it.
DEMO_SAFE="$(printf '%s' "$DEMO_BRANCH" | tr '/' '-')"
DEMO_HASH="$(printf '%s' "$DEMO_BRANCH" | cksum | awk '{printf "%08x", $1}')"
DEMO_WT="$DEMO_ROOT/$DEMO_REPO/.claude/worktrees/${DEMO_SAFE}-${DEMO_HASH}"
DEMO_OFFSET="$(printf '%s' "$DEMO_WT" | cksum | awk '{print $1 % 100}')"
REAL_OFFSET="$(sed -n 's/.*Port offset for this worktree: \([0-9][0-9]*\).*/\1/p' "$CLEAN" | head -1)"

if [[ -z "$REAL_OFFSET" ]]; then
  leaked="${leaked}  - could not find the port offset in the captured output"$'\n'
elif ! grep -qF -- "$DEMO_WT" "$CLEAN"; then
  leaked="${leaked}  - displayed worktree path is not $DEMO_WT"$'\n'
fi

if [[ -n "$leaked" ]]; then
  # Report WHICH pattern matched, never the matching text. Dumping the captured
  # output here would print the very thing the guard exists to withhold,
  # straight into a terminal or a CI log — and CI logs for this repo are public.
  printf 'ERROR: refusing to emit the demo — these patterns survived the scrub:\n%s' "$leaked" >&2
  echo "Inspect the capture yourself if you need to; it is NOT printed here on purpose." >&2
  echo "Fix the substitution in $0 before regenerating." >&2
  exit 1
fi

# Anchor on end-of-line rather than a word boundary: BSD sed has no \b.
sed "s/\(Port offset[^0-9]*\)[0-9][0-9]*$/\1${DEMO_OFFSET}/" "$CLEAN" >"$CLEAN.tmp"
mv "$CLEAN.tmp" "$CLEAN"

if grep -qE 'Port offset' "$CLEAN" && ! grep -qE "Port offset[^0-9]*${DEMO_OFFSET}\$" "$CLEAN"; then
  echo "ERROR: port offset rewrite did not take (wanted ${DEMO_OFFSET}, from ${REAL_OFFSET})." >&2
  exit 1
fi

BLOCK="$WORK/block.md"
{
  echo "$BEGIN_MARKER"
  # shellcheck disable=SC2016  # literal markdown, not a shell expansion
  echo '<!-- Regenerate with `make demo`. Do not hand-edit. -->'
  echo ''
  echo '```console'
  echo "\$ cd $DEMO_ROOT/$DEMO_REPO"
  echo "\$ ./scripts/wt-setup.sh $DEMO_BRANCH --base main"
  cat "$CLEAN"
  echo '```'
  echo ''
  echo "$END_MARKER"
} >"$BLOCK"

if [[ "$WRITE" != true ]]; then
  cat "$BLOCK"
  exit 0
fi

README="$REPO_ROOT/README.md"
if ! grep -qF "$BEGIN_MARKER" "$README" || ! grep -qF "$END_MARKER" "$README"; then
  echo "ERROR: $README has no $BEGIN_MARKER / $END_MARKER pair to splice into." >&2
  exit 1
fi

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v blockfile="$BLOCK" '
  $0 == begin { inblock = 1; while ((getline line < blockfile) > 0) print line; close(blockfile); next }
  $0 == end   { inblock = 0; next }
  !inblock    { print }
' "$README" >"$README.new"

mv "$README.new" "$README"
echo "README.md updated."
