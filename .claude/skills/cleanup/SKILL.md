---
name: cleanup
description: Clean the codebase by making sure all lint checks and all tests pass. Invoke with `/cleanup`.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
context: fork
agent: cleanup
background: false
---

Fix all lint errors and test failures in the codebase. Run `make lint` and `make test`, fix any
issues found, and repeat until everything passes.

Note: this is the repo's own health check. It is unrelated to `/wt-cleanup`, which tidies up stale
git worktrees.

IMPORTANT: Do NOT commit any changes — this skill only fixes code. The human handles committing (via `/commit`).

IMPORTANT: Launch the cleanup agent and let it run to completion autonomously. When the agent returns, relay its summary to the user.
