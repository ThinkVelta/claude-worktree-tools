---
description: Conventions for the CLI, the shell scripts, the test suite and the build harness.
paths:
  - "bin/**"
  - "*.sh"
  - "scripts/**"
  - "Makefile"
---

## Judgment

- Minimum code that solves the problem. No speculative flags, abstractions, or configurability.
- Touch only what the request requires; match the surrounding style. Don't refactor adjacent code.
- Default to no comment. Reserve them for non-obvious WHY: workarounds, subtle invariants.
- Unclear or ambiguous? Say so and ask — don't pick an interpretation silently.

## `bin/init.js`

- **Zero runtime dependencies**, forever. ESM only, `node:` builtins only. Anything that would
  need a package belongs outside the shipped code.
- Must run on the oldest node in the CI matrix — no syntax or API newer than `engines.node`.
- Never overwrite without `--force`; `--dry-run` must write nothing at all.
- Fail with an actionable message, never a raw stack trace.

## Shell

- `set -euo pipefail`, quoted expansions, shellcheck-clean.
- macOS bash 3.2 **and** Linux: no `mapfile`, no associative arrays, no `readlink -f`, no
  `grep -P`, no bare `sed -i` (BSD and GNU disagree on the backup-suffix argument).
- Never `rm -rf`; `make clean` deliberately only prints what to remove.

## Verify before finishing

Run `make ci` (pre-commit over the whole tree, then the smoke suite). A behaviour change means a
new check in `test.sh`, in the same commit.

**`git add` new files before you trust `make lint`.** `pre-commit run --all-files` visits
git-*tracked* files only, so a brand-new script is silently skipped and lint goes green on a file
nothing has checked. Stage first, then lint.
