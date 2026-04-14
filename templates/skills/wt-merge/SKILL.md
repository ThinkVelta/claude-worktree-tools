---
name: wt-merge
description: Merge a worktree branch back via PR (default) or local merge, then clean up. Invoke with `/wt-merge [branch] [--local] [--into <target>]`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Glob
    - Grep
  argument-hint: "[branch] [--local] [--into <target>] [--no-close]"
---

# Worktree Merge

Merge a worktree's branch back into the target. Default: push and create a PR via GitHub CLI. Alternative: local merge for batching work.

**User input:** $ARGUMENTS

## Step 1 — Determine which worktree to merge

**If currently inside a worktree** (not the main working tree):
- Use the current worktree's branch.

**If `$ARGUMENTS` specifies a branch name or worktree path:**
- Use that. Verify it has an associated worktree via `git worktree list --porcelain`.

**If neither:**
- List all worktrees with `git worktree list` and ask the user which one to merge.

Record the worktree path and branch name for subsequent steps.

## Step 2 — Pre-flight checks

### 2a — Clean working tree

```bash
git -C "<worktree-path>" status --porcelain
```

If there are uncommitted changes, **stop** and tell the user:
> This worktree has uncommitted changes. Please commit them first (e.g., run `/commit` in the worktree) or discard them, then re-run `/wt-merge`.

List the dirty files so they can see what's pending.

### 2b — Commits to merge

```bash
git -C "<worktree-path>" log --oneline main..<branch>
```

If there are no commits ahead of the target, **stop**:
> Branch `<branch>` has no new commits relative to `main`. Nothing to merge.

### 2c — Remote tracking

```bash
git -C "<worktree-path>" rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
```

Note whether the branch already has an upstream remote. This determines if we need to push.

## Step 3 — Choose merge strategy

Parse `$ARGUMENTS` for strategy flags:

| Flag in arguments | Strategy |
|---|---|
| (no flags, default) | **PR flow** — push and open a PR on GitHub |
| `--local` | **Local merge** into `main` (or current branch of main worktree) |
| `--into <target-branch>` | **Local merge** into the specified branch |

---

### Strategy A — PR flow (default)

#### Push the branch

```bash
git -C "<worktree-path>" push -u origin "<branch>"
```

If push fails, report the error and stop.

#### Create the PR

First, gather the commit log for the PR body:

```bash
git -C "<worktree-path>" log --oneline main..<branch>
```

Then create the PR:

```bash
gh pr create --base main --head "<branch>" --title "<pr-title>" --body "<pr-body>"
```

- Derive the PR title from the branch name using Conventional Commits style (e.g., `feat/auth-refactor` becomes `feat: auth refactor`).
- The PR body should summarize the commits.

If `gh` is not installed or not authenticated, fall back to:
> Branch pushed. Create a PR manually at: `https://github.com/<owner>/<repo>/compare/<branch>`

#### Chain to close

Print the PR URL. Then proceed to **Step 4** (worktree cleanup) unless `--no-close` was in the arguments.

---

### Strategy B — Local merge

#### Identify the merge target

- If `--into <target>` was specified, use that branch.
- If `--local` was specified without a target, merge into `main`.

Find the worktree where the target branch is checked out:

```bash
git worktree list --porcelain
```

If the target branch is in the main working tree, use that path. If it's in another worktree, use that worktree's path.

#### Perform the merge

```bash
git -C "<target-worktree-path>" merge "<branch>" --no-ff
```

**If merge conflicts occur:**
1. List the conflicting files:
   ```bash
   git -C "<target-worktree-path>" diff --name-only --diff-filter=U
   ```
2. Report the conflicts clearly to the user.
3. **Stop.** Do NOT attempt to auto-resolve. Tell the user to resolve conflicts in the target worktree, then re-run `/wt-close` manually.

On success, proceed to **Step 4**.

**When to use local merge:** Two key scenarios:
- **Batching small fixes:** Several small worktree branches (typo, dep bump, color tweak) merged locally into one branch before opening a single PR.
- **Branch decomposition:** Sub-branches (`feat/auth-nav`, `feat/auth-table`) merged back into a parent branch (`feat/auth`), with one PR from the parent at the end.

## Step 4 — Clean up the worktree (unless --no-close)

If `--no-close` was in the arguments, skip this step and just print the result.

Otherwise, perform the same cleanup as `/wt-close`:

1. Remove the worktree:
   ```bash
   git worktree remove "<worktree-path>"
   ```

2. Delete the branch (safe delete only):
   ```bash
   git branch -d "<branch>"
   ```
   If this fails (branch not fully merged), keep the branch and inform the user.

3. Prune stale references:
   ```bash
   git worktree prune
   ```

Print a summary of what was done.

## Important rules

- **Never force-push.**
- **Never use `git branch -D`** (force delete). Only `git branch -d` (safe delete).
- **Never auto-resolve merge conflicts.** Always stop and let the user handle them.
- If `gh` CLI is not available, degrade gracefully: push the branch and print a manual PR URL.
- Default to PR flow. Local merge is for users who explicitly request it.
