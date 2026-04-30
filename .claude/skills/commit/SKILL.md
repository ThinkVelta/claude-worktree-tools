---
name: commit
description: Cluster changes into logical commits and create Conventional Commits. Invoke with `/commit` or `/commit <message>`.
allowed-tools: Bash Read Glob Grep
argument-hint: "[commit message]"
context: fork
agent: commit
---

Cluster all pending changes into logical groups and create a separate Conventional Commit for each group. Execute immediately — do NOT propose or ask for confirmation.

If a single argument is provided (e.g., `/commit feat: add login page`), stage everything and commit with that message as a single commit.
Otherwise, analyze the changes, cluster them by logical purpose, and create one commit per cluster.

IMPORTANT: Do NOT push to the remote — this skill only creates local commits. The human handles pushing.

IMPORTANT: Launch the commit agent and let it run to completion autonomously. Do NOT summarize or preview the clusters before committing — just execute. When the agent returns, relay its summary table to the user.
