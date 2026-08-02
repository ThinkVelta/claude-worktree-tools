---
name: wt-open
description: Create or reopen a git worktree for parallel development. Use this whenever the user wants to work on something in parallel, start a new task without disrupting their current branch, spin up an isolated environment for an agent, or mentions worktrees, parallel branches, or "work on X separately". Also triggers for `/wt-open [branch | task description]`.
model: sonnet
allowed-tools: Bash Read Glob Grep
argument-hint: "[branch | task description] [--base <branch>]"
---

# Worktree Open

Create or reopen a git worktree for parallel development, then guide the user to launch a Claude Code session in it.

**User input:** $ARGUMENTS

## Step 1 — Parse the user's intent

Determine what the user wants from `$ARGUMENTS`:

| Input pattern                                                                                                           | Action                                 |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| Empty (no arguments)                                                                                                    | Ask the user what they want to work on |
| Looks like a branch name (contains `/`, or starts with `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `ci/`, `test/`) | Use as the branch name directly        |
| Natural language (a task description like "add auth to the API")                                                        | Derive a branch name (see below)       |

### Deriving a branch name from a task description

Generate a branch name following this convention:

- Pattern: `<type>/<1-4-word-slug>`
- Type: `feat`, `fix`, `refactor`, `chore`, `docs`, `ci`, `test` — infer from the description
- Slug: lowercase, hyphen-separated, max 4 words, no special characters
- Examples: `feat/auth-api-refactor`, `fix/login-timeout`, `chore/upgrade-deps`

Do not ask the user to confirm the branch name, just use it and proceed immediately.

## Step 2 — Determine base branch

If the user specified `--base <branch>` in their arguments, use that.

Otherwise, default to the current branch. If the current branch looks like a feature branch and the user is creating a sub-feature, confirm whether they want to branch from `main` instead. Use multiple-choice for easy user selection.

## Step 3 — Check if this worktree already exists

First derive the **canonical** worktree directory, exactly as `scripts/wt-setup.sh` does. This is
the only path `--reopen` will accept, so it — not `git worktree list` — is what decides whether a
reopen is possible:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SAFE_BRANCH="$(printf '%s' "<branch-name>" | tr '/' '-')"
BRANCH_HASH="$(printf '%s' "<branch-name>" | cksum | awk '{printf "%08x", $1}')"
WORKTREE_DIR="${REPO_ROOT}/.claude/worktrees/${SAFE_BRANCH}-${BRANCH_HASH}"
```

Two things about this are load-bearing:

- The `-${BRANCH_HASH}` suffix is **not optional**. It is what keeps `feat/a/b` and `feat-a-b` from
  colliding once slashes are flattened to hyphens.
- The hash must be fed by `printf '%s'`, **never `echo`**. `echo` appends a newline and `cksum`
  hashes it, giving a different digest — and unlike the `SAFE_BRANCH` line, command substitution
  cannot strip that newline, because `cksum` has already consumed it.

Then ask git where the branch is actually checked out, if anywhere. Git is authoritative about
that, and a branch can only be checked out in one worktree at a time:

```bash
EXISTING_WT="$(git worktree list --porcelain | awk -v b="refs/heads/<branch-name>" '
    /^worktree / { wt = substr($0, 10) }
    /^branch /   { if ($2 == b) print wt }
  ')"
```

Classify from **both** answers:

**`EXISTING_WT` equals `$WORKTREE_DIR`** — the managed worktree is already there.

- This is a **reopen**. Run setup with `--reopen` (Step 4).

**`EXISTING_WT` is non-empty but is some other path** — the branch is checked out somewhere this
skill does not manage: the main working tree (you are on that branch right now), or a worktree
someone created by hand.

- **Stop.** Do not pass `--reopen`: the script validates only its own canonical path and would die
  with a confusing "Cannot reopen: … no .git entry found" pointing at a directory that never
  existed. Do not try to create one either — git refuses to check a branch out twice.
- Tell the user where it is and let them choose:

  > `<branch-name>` is already checked out in `$EXISTING_WT`, which isn't a managed worktree.
  > Work there directly, or switch that checkout to another branch first and rerun `/wt-open`.

**`EXISTING_WT` is empty** — no worktree holds this branch.

- Create one (Step 4), whether or not the branch itself already exists — the script creates the
  branch too when it does not exist yet.
- If a leftover `$WORKTREE_DIR` directory is in the way, the script runs `git worktree prune`
  first. That clears stale *metadata* only, so if the directory itself survives the script stops
  with `Directory … exists but is not a git worktree. Remove it manually.` Do not expect creation
  to succeed through that — relay the message and let the user remove the directory.

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

The setup script ends with a summary that includes a `Path:` line. **Use that path** — it is the
directory git actually created. Never re-derive it here or hand the user a path you computed
yourself; if the two ever disagree, the script is right.

After the setup script completes, print:

```text
Worktree ready!

  Branch:  <branch-name>
  Path:    <worktree-path>
  Status:  new | reopened

To start working in this worktree, navigate to it and launch a Claude Code session or open in VSCode:
  cd <worktree-path>
  claude  # Starts a Claude Code session in this worktree
  code  # Opens the worktree in a new VSCode window
```

## Design principles

This skill is **deterministic** — the same branch name always produces the same worktree path and ports, so the user can bookmark URLs and expect consistency. It's also **idempotent** — running it twice with the same branch reopens rather than duplicates, which means the user never has to worry about accidentally creating a mess.

Git only allows a branch to be checked out in one worktree at a time, so the setup script will refuse if the branch is already in use elsewhere. If that happens, surface the error clearly so the user knows which worktree has it.

If the setup script fails partway through, just report what happened. Don't try to auto-clean — partial state is easier for the user to inspect and fix (via `/wt-close`) than state that was silently deleted.
