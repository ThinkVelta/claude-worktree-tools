---
name: wt-close
description: Tear down a git worktree cleanly with safety checks. Invoke with `/wt-close [branch] [--force] [--keep-branch]`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Glob
    - Grep
  argument-hint: "[branch | path] [--force] [--keep-branch]"
---

# Worktree Close

Safely tear down a git worktree: check for unsaved work, remove the worktree directory, decide about the branch, and clean up.

**User input:** $ARGUMENTS

## Step 1 — Identify the worktree to close

**Priority order:**

1. If `$ARGUMENTS` contains a branch name or worktree path, use that.
2. If the current directory is inside a worktree (not the main working tree), use the current worktree.
3. If neither, list worktrees with `git worktree list` and ask the user to pick one.

Parse `git worktree list --porcelain` to find the worktree path and branch. Identify the main working tree (the first entry).

**Never close the main working tree.** If the user is trying to close the main working tree, explain that it cannot be removed as a worktree.

## Step 2 — Check for uncommitted changes

```bash
git -C "<worktree-path>" status --porcelain
```

**If clean** (empty output): proceed to Step 3.

**If dirty** (uncommitted changes):

Show the user what's pending:

```bash
git -C "<worktree-path>" status --short
```

Then present options:

1. **Commit first** (recommended) — suggest running `/commit` in the worktree, then re-run `/wt-close`
2. **Discard changes** — proceed with force removal (requires explicit confirmation)
3. **Abort** — cancel the close operation

If `--force` was in `$ARGUMENTS`, skip this prompt and proceed with force removal.

**Never silently discard uncommitted work.**

## Step 3 — Check for unpushed commits

```bash
git -C "<worktree-path>" log --oneline @{upstream}..HEAD 2>/dev/null
```

If there are unpushed commits (and no `--force` flag):

> Warning: This branch has X unpushed commit(s). They will still exist on the local branch after worktree removal, but are not backed up to the remote.

List the commits so the user can see what's at risk. Ask whether to continue.

## Step 4 — Remove the worktree

**If clean or user confirmed discard:**

```bash
git worktree remove "<worktree-path>"
```

**If force removal was confirmed (dirty worktree):**

```bash
git worktree remove --force "<worktree-path>"
```

If removal fails (e.g., a process is still using the directory), report the error. Suggest the user close any editors or terminals open in that directory.

## Step 5 — Branch cleanup

Unless `--keep-branch` was in `$ARGUMENTS`, decide whether to delete the branch.

### Check merge status

```bash
git branch --merged main | grep -w "<branch>"
```

### Check for open PRs

```bash
gh pr list --head "<branch>" --state open --json number,url 2>/dev/null
```

(Skip this check if `gh` is not available.)

### Decision logic

| Scenario                           | Default action                                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Branch is merged into main         | Suggest delete. Confirm with user, then run `git branch -d "<branch>"`                                  |
| Branch has an open PR              | Keep the branch. Inform: "Branch has an open PR — keeping it."                                          |
| Branch is NOT merged and no PR     | Keep the branch. Inform: "Branch is not fully merged — keeping it. To delete: `git branch -D <branch>`" |
| `--keep-branch` flag was specified | Keep the branch regardless.                                                                             |

**Never run `git branch -D` automatically.** Only use `git branch -d` (safe delete). If the user wants to force-delete an unmerged branch, tell them the command to run manually.

## Step 6 — Prune and confirm

```bash
git worktree prune
```

Print a summary:

```
Worktree closed.

  Path:    <worktree-path> (removed)
  Branch:  <branch> (deleted | kept)
```

## Important rules

- **Never close the main working tree.**
- **Never silently discard uncommitted changes** without `--force` or explicit user confirmation.
- **Never use `git branch -D`** (force delete). Only `git branch -d`.
- **Never use `rm -rf`** on the worktree directory. Always use `git worktree remove`.
- If anything fails, run `git worktree prune` to clean up stale references.
