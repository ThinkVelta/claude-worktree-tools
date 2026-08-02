---
name: pr-open
description: Create a pull request for the current branch. Analyzes all commits, runs validation, and opens a well-formatted PR on GitHub. Always targets `main`. Invoke with `/pr-open`.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
context: fork
agent: pr-open
background: false
---

Create a pull request for the current branch targeting `main`.

Launch the `pr-open` agent, which analyzes every commit on the branch, runs `make lint` and
`make test`, and opens a well-formatted PR on GitHub via `gh pr create`.

IMPORTANT: The agent never merges, never force-pushes, and never touches `main`. The only writes
it may perform are `gh pr create` and a single explicit push of the current feature branch
(`git push -u origin HEAD:refs/heads/<branch>`).

IMPORTANT: Let the agent run to completion autonomously. When it returns, relay the PR URL,
title, target branch, and commit count to the user.
