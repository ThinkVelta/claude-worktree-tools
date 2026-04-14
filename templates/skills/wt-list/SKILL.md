---
name: wt-list
description: List active worktrees with branch, status, sync state, and staleness info. Invoke with `/wt-list`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Glob
    - Grep
  argument-hint: "[--stale]"
---

# Worktree List

List all active worktrees with rich context: branch, status, sync state, and staleness detection.

**User input:** $ARGUMENTS

## Step 1 — Gather worktree data

```bash
git worktree list --porcelain
```

Parse the output to extract for each worktree:

- **Path** (`worktree <path>`)
- **HEAD commit** (`HEAD <sha>`)
- **Branch** (`branch refs/heads/<name>`) or `(detached HEAD)`

Identify the main working tree (first entry) and label it as such.

If there are no worktrees beyond the main working tree, report:

> No additional worktrees found. Use `/wt-open` to create one.

Then stop.

## Step 2 — Enrich each worktree

For each worktree, gather the following:

### Clean/dirty status

```bash
git -C "<path>" status --porcelain 2>/dev/null | wc -l | tr -d ' '
```

- `0` → "clean"
- `>0` → report count of modified files

### Ahead/behind remote

```bash
git -C "<path>" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null
```

Output format: `<behind>\t<ahead>`. If no upstream is set, note "no remote".

### Last commit

```bash
git -C "<path>" log -1 --format="%cr|%s" 2>/dev/null
```

This gives relative time and subject (e.g., `2 hours ago|add JWT validation`).

### Staleness check

```bash
git -C "<path>" log -1 --format="%ct" 2>/dev/null
```

Compare the commit timestamp to now. Flag as **stale** if the last commit is **3 or more days old**.

## Step 3 — Format the output

Present each worktree as a block, for example:

```
Active worktrees:

  main (main working tree)
    /path/to/repo
    Clean | Last commit: 1h ago "update deps"

  feat/auth
    .claude/worktrees/feat-auth
    Clean | 2 ahead | Last commit: 2h ago "add JWT validation"
    Ports: offset 17

  feat/billing
    .claude/worktrees/feat-billing
    1 modified file | 0 ahead | Last commit: 20m ago "wip: invoice model"
    Ports: offset 42

  fix/typo-header
    .claude/worktrees/fix-typo-header
    Clean | 1 ahead | Last commit: 3d ago "fix typo in header"
    Ports: offset 91
    ⚠ Stale (no commits in 3+ days)
```

If `$ARGUMENTS` contains `--stale`, only show worktrees flagged as stale.

## Step 4 — Recommendations

After the listing, add actionable suggestions for any issues found:

- **Stale worktrees:** "Consider closing stale worktrees with `/wt-close <branch>` to keep your workspace tidy."
- **Dirty worktrees:** "Worktree `<branch>` has uncommitted changes. Consider committing with `/commit`."
- **Behind remote:** "Worktree `<branch>` is behind its remote. Consider pulling."
- **Port offset collisions:** If two worktrees share the same port offset, warn about potential port conflicts.

## Important rules

- **This command is read-only.** Never modify any worktree, branch, or file.
- If a worktree path no longer exists on disk, note it as "missing" and suggest running `git worktree prune`.
- Handle errors gracefully — if a worktree is in a broken state, report what you can and skip what you cannot.
