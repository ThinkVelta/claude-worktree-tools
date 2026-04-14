---
name: wt-help
description: Answer common questions about working with worktrees — VSCode integration, gitignore, port offsets, env files, workflow tips. Use this when the user asks how worktrees work, why something looks different in their editor, how to see diffs, or has any question about the worktree setup. Also triggers for `/wt-help [topic]`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Glob
    - Grep
  argument-hint: "[topic]"
---

# Worktree Help

Answer the user's question about working with worktrees. Use `$ARGUMENTS` to determine what they're asking about. If empty, print the topic list below and ask what they need help with.

## Topics

### vscode — "How do I see my worktree in VSCode?"

Worktrees live inside `.claude/worktrees/`, which is gitignored. This is correct and required — without the gitignore entry, git would try to track the worktree's files as part of the parent repo.

This means the main repo's Source Control panel will **not** show worktree changes. That's by design.

**To get full VSCode support (diffs, Source Control, file explorer) for a worktree, open it in its own window:**

```bash
code .claude/worktrees/<branch-dir>
```

This gives you a separate VSCode instance scoped to that branch — exactly like working in a second repo.

**Alternative: multi-root workspace.** If you prefer one window:

1. File > Add Folder to Workspace...
2. Select the worktree directory under `.claude/worktrees/`
3. Source Control will show both repos in separate sections

Separate windows is the more common pattern — it avoids confusion about which branch you're editing.

### gitignore — "Why is the worktree in .gitignore? Is that correct?"

Yes, it's required. Worktrees are not nested repos — they're git's own mechanism for checking out a branch into a separate directory. Git tracks them internally (`git worktree list`).

If you removed the gitignore entry, git would try to track the worktree's files as content of the parent repo, creating duplicated and conflicting files. The gitignore entry prevents this.

Think of each worktree as a lightweight clone that shares git history but has its own working directory. You wouldn't expect a clone to show up inside the original repo's Source Control either.

### workflow — "What's the typical workflow?"

1. **`/wt-open <task>`** — Creates a worktree with its own branch, copies `.env` files, installs dependencies, derives unique ports.
2. **Open it:** `code .claude/worktrees/<branch-dir>` or `cd .claude/worktrees/<branch-dir> && claude`
3. **Work normally** — commit, run tests, use Claude Code, all scoped to that branch.
4. **`/wt-merge`** — Push and open a PR (default), or merge locally into another branch.
5. **`/wt-close`** — Tear down the worktree when done.

You can have multiple worktrees active at the same time. Use `/wt-list` to see them all.

### ports — "How do port offsets work?"

Each worktree gets a deterministic port offset (0–99) derived from its directory path. This means:

- The same branch always gets the same ports (you can bookmark URLs).
- Different worktrees get different ports (no collisions, usually).
- Ports are written to the worktree's `.env` file by the setup script.

Example: if your app normally runs on port 3000 and the worktree's offset is 17, it runs on port 3017 in that worktree.

The offset is configured by `/wt-adopt` in the `REPO-SPECIFIC PORT CONFIG` section of `scripts/wt-setup.sh`. If ports aren't being offset, run `/wt-adopt` to set it up.

### env — "What happens with .env files?"

The setup script copies all `.env*` files from the main repo into the worktree, preserving directory structure. This includes nested `.env` files in monorepo subdirectories.

On `--reopen`, `.env` files are re-copied from the main repo. This is intentional — it picks up any changes you made to `.env` in the main repo since the worktree was created.

Symlinked `.env` files are skipped (the target is copied, not the symlink).

### local-merge — "When should I use local merge instead of a PR?"

Two main scenarios:

**Batching small fixes:** You have several tiny worktrees (typo fix, dep bump, color tweak). Instead of opening 5 PRs, merge them all locally into one branch and open a single PR:

```
/wt-merge fix/typo --into feat/cleanup
/wt-merge fix/deps --into feat/cleanup
/wt-merge fix/color --into feat/cleanup
# Then open one PR from feat/cleanup
```

**Branch decomposition:** You split a large feature into sub-tasks, each in its own worktree. Merge them back into the parent branch locally, then open one PR from the parent:

```
/wt-merge feat/auth-nav --into feat/auth
/wt-merge feat/auth-table --into feat/auth
# Then open one PR from feat/auth
```

### commands — "What commands are available?"

| Command                                          | Purpose                              |
| ------------------------------------------------ | ------------------------------------ |
| `/wt-open [branch or description]`               | Create or reopen a worktree          |
| `/wt-merge [branch] [--local] [--into <target>]` | Merge back via PR or locally         |
| `/wt-close [branch] [--force] [--keep-branch]`   | Tear down a worktree                 |
| `/wt-list [--stale]`                             | List worktrees with status           |
| `/wt-adopt [--check-only]`                       | Configure setup script for your repo |
| `/wt-help [topic]`                               | This help                            |

## Instructions

Match the user's question to the closest topic above and answer using that content. If their question doesn't match any topic, answer based on your knowledge of git worktrees and the worktree tools setup in this repo.

Keep answers concise and practical. Include the `code <path>` command when relevant — it's the most useful tip for new users.
