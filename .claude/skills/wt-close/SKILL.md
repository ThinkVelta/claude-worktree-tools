---
name: wt-close
description: Finish work in a worktree — push, remove the worktree, and optionally delete the branch. Use this when the user is done with a worktree, wants to clean up, push and move on, or mentions they no longer need a parallel environment. Also triggers for `/wt-close [branch] [--push] [--force]`.
model: sonnet
allowed-tools: Bash Read Glob Grep
argument-hint: "[branch | path] [--push] [--force]"
---

# Worktree Close

Finish work in a worktree: check for unsaved work, optionally push, remove the worktree, and let the user decide what happens to the branch.

**User input:** $ARGUMENTS

## Placeholders and shell state

This skill writes `<worktree-path>`, `<branch>` and `<main-repo-path>` in its commands. **Substitute the literal resolved value every time** — do not carry them as shell variables between Bash calls.

Claude Code's Bash tool does not persist shell state: a variable set in one call is empty in the next. A `$MAIN_REPO` assigned in Step 4 and used in Step 7 expands to nothing — and `git -C ""` does not fail. It exits `0` and operates on whatever repository the current directory happens to be in, so the command appears to succeed while acting on the wrong repo. Assign a variable only when it is used inside the *same* Bash call.

## Step 1 — Identify the worktree to close

**Priority order:**

1. If `$ARGUMENTS` contains a branch name or worktree path, use that.
2. If the current directory is inside a worktree (not the main working tree), use the current worktree.
3. If neither, list worktrees with `git worktree list` and ask the user to pick one.

```bash
git worktree list --porcelain
```

Record three values from the output and reuse them literally from here on:

- `<worktree-path>` — the worktree being closed
- `<branch>` — the branch checked out in it
- `<main-repo-path>` — the **first** `worktree` entry, which is always the main working tree

The main working tree cannot be closed. If the user targets it, explain the difference and stop.

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

## Step 3 — Push if requested

If `--push` was in `$ARGUMENTS`, or the user mentioned pushing:

```bash
git -C "<worktree-path>" push -u origin "<branch>"
```

If push fails, report the error and stop. If no `--push` flag, skip this step — unpushed commits are reported in Step 5, after Step 4 has counted them.

## Step 4 — Verify branch state (do not guess)

Before picking a default in Step 5, you MUST verify the branch's actual state. The branch name is not evidence. Asserting "PR is open", "PR is merged", or "N unpushed commits" without running the commands below is a hallucination — do not do it.

**4a. Refresh remote tracking refs.** Without this, a remote branch deleted after a merge still appears to exist locally:

```bash
git -C "<main-repo-path>" fetch --prune origin
```

**4b. Check PR state.** This works even if the remote head branch was deleted post-merge:

```bash
gh pr list --head "<branch>" --state all --json number,state,mergedAt --limit 1 --jq '.[0]' 2>&1
```

Interpret the result:

- `state: "MERGED"` → branch landed. Record as **merged**.
- `state: "OPEN"` → PR awaiting review. Record as **open PR**.
- `state: "CLOSED"` and `mergedAt: null` → abandoned. Record as **closed without merge**.
- Empty output → no PR for this branch. Fall through to 4c.
- An error (`gh` not installed, not authenticated, no GitHub remote) → **not the same as "no PR"**. Say which it was, then fall through to 4c and rely on the local check alone.

**4c. If 4b gave no answer, check merge status against the base branch locally.**

Resolve the base branch first — do not assume `main`:

```bash
git -C "<main-repo-path>" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'
```

If that prints nothing, the clone has no recorded default branch. Try `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, and if that also fails, ask the user rather than guessing — a wrong base silently reports unmerged work as merged. `git remote set-head origin -a` records it permanently.

Then, substituting the resolved base:

```bash
git -C "<main-repo-path>" rev-list --count "origin/<base>..<branch>"
```

- Count `0` → branch fully merged into base. Record as **merged**.
- Count `> 0` → branch has unmerged work. Record as **unmerged**.
- Command errors with `unknown revision` → `origin/<base>` is missing locally; 4a should have fetched it. Report that rather than recording a state.

**4d. Count unpushed commits — only if the remote branch still exists:**

```bash
git -C "<main-repo-path>" show-ref --verify --quiet "refs/remotes/origin/<branch>" && \
  git -C "<main-repo-path>" rev-list --count "origin/<branch>..<branch>"
```

If `refs/remotes/origin/<branch>` does not exist (typical after merge + auto-delete), do NOT invent a number — say "remote branch no longer exists" instead.

## Step 5 — Present cleanup options

If Step 4d found unpushed commits and the user did not pass `--push`, say so first:

> This branch has N unpushed commit(s) that are not backed up to the remote. Add `--push` to push before closing, or continue to close without pushing.

Then ask the user what they'd like to do:

1. **Remove worktree only** — removes the worktree directory but keeps the branch. Good when the work might continue later or a PR is still open.
2. **Remove worktree + delete branch** — full cleanup. Good when the branch has been merged or is no longer needed. The delete flag follows Step 4's recorded state (see Step 6).
3. **Keep everything** — cancel the close. The worktree and branch remain as-is.

Pick the default from the state recorded in Step 4:

- **merged** → default to option 2
- **open PR** → default to option 1
- **closed without merge** → default to option 1, and mention the PR was closed without merging
- **unmerged** (no PR) → default to option 1
- **state could not be determined** → default to option 1, and say why

If `--force` was specified, skip the prompt and use option 2. The branch-delete flag still follows Step 4's recorded state — `--force` overrides the prompt and the uncommitted-changes guard, not the branch-safety logic.

## Step 6 — Execute the chosen action

**Critical for both options: `cd` into the main repo FIRST, in the same Bash call as the removal.**

Claude Code's Bash tool persists its working directory across calls and resolves it at the start of each one. If the session is currently inside the worktree, removing it leaves that persistent cwd pointing at a directory that no longer exists, and *every* later call — a `-D` retry, the Step 7 prune, anything at all — fails with "No such file or directory" before its command runs. Chaining commands with `&&` only protects that one call; it does not fix the cwd for what comes after. `cd "<main-repo-path>"` before the removal does, because the main repo still exists once the worktree is gone.

### Option 1: Remove worktree only

```bash
cd "<main-repo-path>" && git worktree remove "<worktree-path>"
```

If the worktree is dirty and the user confirmed discard:

```bash
cd "<main-repo-path>" && git worktree remove --force "<worktree-path>"
```

### Option 2: Remove worktree + delete branch

The worktree must be removed before the branch delete — `git branch -d` refuses to delete a branch that is checked out in a worktree.

Pick the delete flag from Step 4's recorded state:

- **merged** → use `git branch -D`. Squash and rebase merges rewrite commits, so the branch's SHAs are not reachable from the base branch and `-d` refuses even though the work landed. Left alone, that orphans the branch. A verified merge — GitHub `MERGED`, or a local rev-list count of `0` — is authoritative, so force-delete is correct here.
- **open PR**, **closed without merge**, **unmerged**, **undetermined** → use `git branch -d` (safe delete). If it refuses, surface the message instead of escalating.

Run it as a **single Bash call** so the `cd` lands before the removal:

```bash
# Step 4 recorded "merged":
cd "<main-repo-path>" && git worktree remove "<worktree-path>" && git branch -D "<branch>"

# Every other state:
cd "<main-repo-path>" && git worktree remove "<worktree-path>" && git branch -d "<branch>"
```

If `git branch -d` refuses, tell the user:

> Branch `<branch>` has unmerged commits. Keeping the branch. To force-delete: `git branch -D <branch>`

The worktree is already gone at that point and the cwd is safely in the main repo, so this is a recoverable end state — not a failure to retry.

### Option 3: Keep everything

Do nothing. Confirm to the user that the worktree is still active.

## Step 7 — Prune and confirm

```bash
git -C "<main-repo-path>" worktree prune
```

Use `-C` with the literal path rather than relying on the cwd Step 6 left behind. An unsubstituted variable expands to `git -C ""`, which exits `0` and prunes whichever repo the current directory belongs to — a successful-looking prune of the wrong repository.

Print a summary:

```text
Worktree closed.

  Path:    <worktree-path> (removed)
  Branch:  <branch> (deleted | kept | pushed)
```

## Guiding principles

**The main working tree is not a worktree.** It's the user's primary repo checkout — removing it would be catastrophic. If someone accidentally targets it, explain the difference.

**Uncommitted work is sacred.** Silently discarding changes is one of the worst things a tool can do. The user should always see what's at risk and explicitly choose to discard. The `--force` flag exists for when they've already made that choice.

**Verify state, never infer it.** A branch name, a worktree's existence, and a plausible-sounding history are not evidence of what happened to a PR. Every claim about merge state or commit counts comes from a command run in this session, or is not made at all.

**Default to `git branch -d` (safe delete) — but `-D` is correct when the merge is verified.** `-d` tests commit reachability, which squash and rebase merges defeat. When Step 4 recorded **merged**, use `-D`; in every other state stick with `-d` and surface the refusal rather than overriding it.

**Use `git worktree remove`, not `rm -rf`.** Git tracks worktree metadata internally; removing the directory without telling git leaves stale references that cause confusing errors later. If anything goes wrong, `git worktree prune` cleans up the metadata.
