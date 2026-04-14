---
name: wt-cleanup
description: Batch cleanup of stale worktrees and orphaned branches. Use this when the user wants to tidy up, has accumulated worktrees over time, asks about old branches, or mentions cleaning up their workspace. Also triggers for `/wt-cleanup [--dry-run]`.
model: haiku
allowed-tools: Bash Read Glob Grep
argument-hint: "[--dry-run]"
---

# Worktree Cleanup

Scan for stale worktrees and orphaned branches, then let the user decide what to clean up. This is the batch housekeeping counterpart to `/wt-close` (which handles one worktree at a time).

**User input:** $ARGUMENTS

If `--dry-run` is in the arguments, report what would be cleaned up without making any changes.

## Step 1 — Inventory worktrees

```bash
git worktree list --porcelain
```

For each worktree (excluding the main working tree), gather:

- **Branch name**
- **Path on disk** — verify the directory still exists
- **Last commit date:**
  ```bash
  git -C "<path>" log -1 --format="%ct" 2>/dev/null
  ```
- **Dirty/clean status:**
  ```bash
  git -C "<path>" status --porcelain 2>/dev/null | wc -l | tr -d ' '
  ```

Classify each worktree:

| Status      | Criteria                                                            |
| ----------- | ------------------------------------------------------------------- |
| **Stale**   | Last commit more than 7 days ago and clean (no uncommitted changes) |
| **Missing** | Directory no longer exists on disk (stale git metadata)             |
| **Active**  | Recent commits or has uncommitted changes                           |

## Step 2 — Find stale local branches

First, prune remote-tracking references so git knows which remote branches are gone:

```bash
git fetch --prune
```

Then find local branches that are candidates for cleanup:

```bash
# All local branches (excluding main/master)
git branch --format='%(refname:short)' | grep -v -E '^(main|master)$'

# Branches with worktrees (still in active use)
git worktree list --porcelain | grep '^branch ' | sed 's|branch refs/heads/||'
```

For each local branch that doesn't have a worktree, check:

- **Is it merged into `main`?**
  ```bash
  git branch --merged main | grep -w "<branch>"
  ```
- **Was its remote deleted?** (common after merging a PR on GitHub)
  ```bash
  git branch -vv --format='%(refname:short) %(upstream:track)' | grep '\[gone\]'
  ```
  The `[gone]` marker means the branch once tracked a remote that no longer exists — a strong signal the PR was merged and the remote branch deleted.
- **Does it have an open PR?** (if `gh` is available)
  ```bash
  gh pr list --head "<branch>" --state open --json number 2>/dev/null
  ```

Classify:

| Status              | Criteria                                                                     |
| ------------------- | ---------------------------------------------------------------------------- |
| **Remote deleted**  | Tracked a remote that's gone (PR likely merged and branch deleted on GitHub) |
| **Merged orphan**   | Merged into main, no worktree, no remote — safe to delete                    |
| **Unmerged orphan** | Not merged, no worktree, no remote — may be abandoned work                   |
| **Has open PR**     | Skip — still in use                                                          |

## Step 3 — Present findings

Show a summary grouped by action:

```
Worktree Cleanup Report
═══════════════════════

Stale worktrees (no commits in 7+ days, clean):
  feat/old-experiment    .claude/worktrees/feat-old-experiment    12d ago
  fix/typo-header        .claude/worktrees/fix-typo-header         8d ago

Missing worktrees (directory gone, metadata remains):
  feat/deleted-thing     (path no longer exists)

Branches with deleted remote (PR likely merged on GitHub):
  feat/auth-refactor     remote gone — safe to delete locally
  fix/login-bug          remote gone — safe to delete locally

Orphaned branches (no worktree, no remote):
  feat/abandoned-idea    merged into main — safe to delete
  fix/half-done          NOT merged — review before deleting

Active worktrees (no action needed):
  feat/current-work      .claude/worktrees/feat-current-work       2h ago
```

If `--dry-run`, stop here.

## Step 4 — Let the user choose

Present cleanup options as a checklist — the user picks what to clean up:

- **Prune missing worktrees** — run `git worktree prune` to clear stale metadata
- **Close stale worktrees** — remove worktree directories for stale entries
- **Delete branches with deleted remote** — `git branch -d` for each (their PRs were merged)
- **Delete merged orphan branches** — `git branch -d` for each
- **Skip unmerged orphans** — list them but don't touch (inform the user of `git branch -D` if they want to force)

Ask which of these the user wants to proceed with. Don't auto-execute anything — the user confirms first.

## Step 5 — Execute

For each action the user approved:

```bash
# Prune stale metadata
git worktree prune

# Close stale worktrees
git worktree remove "<path>"

# Delete merged orphan branches
git branch -d "<branch>"
```

Print a summary of what was done:

```
Cleanup complete:
  2 stale worktrees removed
  1 missing worktree pruned
  3 merged orphan branches deleted
  1 unmerged orphan branch kept (fix/half-done)
```

## Guiding principles

**This is a housekeeping tool, not a destructive one.** The default posture is conservative — show what could be cleaned up, let the user decide. The `--dry-run` flag makes it completely safe to explore.

**Merged branches are safe to delete.** Their commits live in the target branch. Unmerged branches might contain work the user forgot about — flag them but don't delete without explicit confirmation.

**Use `git worktree remove`, not `rm -rf`.** And use `git branch -d` (safe delete), not `-D`. If something refuses to delete, that's useful information — surface it.
