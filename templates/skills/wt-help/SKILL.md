---
name: wt-help
description: Answer common questions about working with worktrees — VSCode integration, gitignore, port offsets, env files, workflow tips. Use this when the user asks how worktrees work, why something looks different in their editor, how to see diffs, or has any question about the worktree setup. Also triggers for `/wt-help [topic]`.
model: haiku
allowed-tools: Bash Read Glob Grep
argument-hint: "[question]"
---

# Worktree Help

`$ARGUMENTS` is the user's question. If empty, print the **Overview** section below verbatim. Otherwise, answer their question using the **FAQ** section as your primary reference, falling back to your knowledge of git worktrees and this repo's setup.

Keep answers concise and practical. When relevant, include `code .claude/worktrees/<branch-dir>` — it's the single most useful tip for new users.

---

## Overview (print when `$ARGUMENTS` is empty)

**claude-worktree-tools** is a toolkit for running multiple branches of the same repo in parallel, each in its own isolated git worktree, with Claude Code skills that handle the lifecycle for you.

**Why it exists.** Switching branches mid-task is disruptive: you stash, rebuild, lose dev server state, and risk polluting one branch's `.env` with another's. Worktrees give each branch its own directory, dependencies, ports, and env — so you (or a Claude agent) can spin up a parallel task without touching what you're already working on. This package automates the boring parts: derived ports, copied env files, dependency installs, cleanup, and merge/close flows.

**Links**

- Repo: https://github.com/ThinkVelta/claude-worktree-tools
- Issues: https://github.com/ThinkVelta/claude-worktree-tools/issues
- Git worktrees docs: https://git-scm.com/docs/git-worktree

**Available `/wt-*` skills**

| Command                                              | Purpose                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------- |
| `/wt-adopt [--check-only]`                           | One-time setup: customize `wt-setup.sh` for this repo's stack |
| `/wt-open [branch or description] [--base <branch>]` | Create or reopen a worktree (env, deps, ports handled)        |
| `/wt-list [--stale]`                                 | List active worktrees with branch, sync state, staleness      |
| `/wt-merge <branch> --into <target> [--no-close]`    | Local git merge of one branch into another                    |
| `/wt-close [branch] [--push] [--force]`              | Push, remove the worktree, optionally delete the branch       |
| `/wt-cleanup [--dry-run]`                            | Batch cleanup of stale worktrees and orphaned branches        |
| `/wt-help [question]`                                | This help — ask any worktree question in natural language     |

Ask `/wt-help <your question>` for anything specific (VSCode setup, ports, env files, merge strategy, etc.).

---

## FAQ

**Q: How do I see a worktree in VSCode?**
Open it as its own window: `code .claude/worktrees/<branch-dir>`. The main repo's Source Control panel won't show worktree changes — that's by design (worktrees are gitignored). Alternative: File → Add Folder to Workspace for a multi-root setup.

**Q: Why is `.claude/worktrees/` in `.gitignore`?**
Required. Worktrees are git's own checkout mechanism, not nested repos. Without the gitignore entry, git would try to track the worktree's files as content of the parent repo. `git worktree list` is how git tracks them.

**Q: What's the typical workflow?**
`/wt-open <task>` → `code .claude/worktrees/<branch-dir>` → work & commit → `/wt-close --push` (or `/wt-merge` to fold into another branch first). Use `/wt-list` to see everything in flight.

**Q: How do port offsets work?**
Each worktree gets a deterministic 0–99 offset derived from its path, written into its `.env`. Same branch → same ports (bookmarkable). Different worktrees → no collisions. Configure which env vars to offset in the `REPO-SPECIFIC PORT CONFIG` section of `scripts/wt-setup.sh` (run `/wt-adopt` to set up).

**Q: What happens to `.env` files?**
All `.env*` files are copied from the main repo into the worktree, preserving directory structure (monorepo-friendly). On `--reopen`, they're re-copied so worktrees pick up changes from the main repo. Symlinked `.env` files are skipped.

**Q: When should I use `/wt-merge` instead of opening a PR?**
Two cases: **batching small fixes** (merge several tiny worktrees into one branch, open one PR), and **branch decomposition** (split a big feature into sub-worktrees, fold them back into the parent, then open one PR from the parent). For everything else, just `/wt-close --push` and PR normally.

**Q: Can I run multiple worktrees at once?**
Yes — that's the whole point. Each has isolated deps, ports, and env. Run `/wt-list` to see them all. A common pattern: one worktree for your main task, others for parallel Claude agents working on smaller things.

**Q: How do I update dependencies in a worktree?**
Run your normal install command inside the worktree directory (`pnpm install`, `bun install`, etc.). The worktree has its own `node_modules` — installs don't affect the main repo or other worktrees.

**Q: What if I forget about a worktree?**
`/wt-list --stale` shows worktrees with no recent activity. `/wt-cleanup` batch-removes stale ones (use `--dry-run` first to preview).

**Q: Is the main repo affected when I work in a worktree?**
No. The main repo's working directory, branch, and dev server are untouched. Only the shared `.git` directory is updated when you commit (which is the same as any branch switch).

**Q: My setup script isn't doing what I want — how do I customize it?**
Edit `scripts/wt-setup.sh` directly, or re-run `/wt-adopt` to regenerate it. The script is intentionally checked in and editable per repo.

**Q: How do I delete a branch and its worktree completely?**
`/wt-close <branch> --force` removes the worktree and deletes the local branch. Add `--push` first if you want to push before tearing down.
