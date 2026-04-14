---
name: wt-open
description: Create or reopen a git worktree for parallel development. Invoke with `/wt-open [branch | task description]`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Glob
    - Grep
  argument-hint: "[branch-name | task description]"
---

# Worktree Open

Create or reopen a git worktree for parallel development, then guide the user to launch a Claude Code session in it.

**User input:** $ARGUMENTS

## Step 1 — Parse the user's intent

Determine what the user wants from `$ARGUMENTS`:

| Input pattern | Action |
|---|---|
| Empty (no arguments) | Ask the user what they want to work on |
| Looks like a branch name (contains `/`, or starts with `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `ci/`, `test/`) | Use as the branch name directly |
| Natural language (a task description like "add auth to the API") | Derive a branch name (see below) |

### Deriving a branch name from a task description

Generate a branch name following this convention:
- Pattern: `<type>/<2-4-word-slug>`
- Type: `feat`, `fix`, `refactor`, `chore`, `docs`, `ci`, `test` — infer from the description
- Slug: lowercase, hyphen-separated, max 4 words, no special characters
- Examples: `feat/auth-api-refactor`, `fix/login-timeout`, `chore/upgrade-deps`

**Confirm the derived branch name with the user before proceeding.**

## Step 2 — Determine base branch

If the user specified `--base <branch>` in their arguments, use that.

Otherwise, default to the current branch. If the current branch looks like a feature branch and the user is creating a sub-feature, confirm whether they want to branch from `main` instead.

## Step 3 — Check if this worktree already exists

Run:

```bash
git worktree list --porcelain
```

Derive the expected worktree directory:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SAFE_BRANCH="$(echo "<branch-name>" | tr '/' '-')"
WORKTREE_DIR="${REPO_ROOT}/.claude/worktrees/${SAFE_BRANCH}"
```

**If the worktree directory exists and is valid** (has a `.git` file):
- This is a **reopen**. Run setup with `--reopen` flag (Step 4).

**If the branch exists but has no worktree**:
- Create a new worktree for the existing branch (Step 4).

**If neither exists**:
- Create both the branch and worktree (Step 4).

## Step 4 — Run the setup script

Verify the setup script exists:

```bash
test -f "$(git rev-parse --show-toplevel)/scripts/wt-setup.sh"
```

If it does NOT exist, tell the user:
> Setup script not found at `scripts/wt-setup.sh`. Run `/wt-adopt` first to generate it, or install the toolkit with `npx @thinkvelta/claude-worktree-tools`.

If it exists, run it:

**New worktree:**
```bash
bash "$(git rev-parse --show-toplevel)/scripts/wt-setup.sh" "<branch-name>" --base "<base-branch>"
```

**Reopen existing worktree:**
```bash
bash "$(git rev-parse --show-toplevel)/scripts/wt-setup.sh" "<branch-name>" --reopen
```

## Step 5 — Print result and next steps

After the setup script completes, print:

```
Worktree ready!

  Branch:  <branch-name>
  Path:    <worktree-path>
  Status:  new | reopened

To start working in this worktree:
  cd <worktree-path> && claude
```

## Important rules

- **Deterministic:** The same branch name always produces the same worktree path and ports.
- **Idempotent:** Running this command twice with the same branch reopens the existing worktree.
- **Never create a worktree if the branch is already checked out elsewhere.** The setup script handles this check, but if it fails, report the error clearly.
- If the setup script fails at any step, report what happened. Do not attempt cleanup — the user or `/wt-close` can handle it.
