---
name: pr-open
description: Create a pull request for the current branch. Analyzes all commits, runs validation, and opens a well-formatted PR on GitHub. Always targets `main`. Invoke with `/pr-open`.
allowed-tools: Bash Read Glob Grep mcp__plugin_linear_linear
context: fork
agent: pr-open
---

Create a pull request for the current branch targeting `main`.

You should use the `/pr-open` agent to perform this task, as it is designed to analyze all commits
on the current branch, run necessary validations, and open a well-formatted pull request on GitHub.
