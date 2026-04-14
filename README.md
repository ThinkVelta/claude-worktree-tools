# Claude Worktree Tools

A standalone, installable toolkit that gives any repo a complete worktree lifecycle for parallel AI-agent development with Claude Code.

## Why

When you run Claude Code in your repo, you share one working directory. Git worktrees give the agent its own directory on its own branch, but setting up a worktree means copying `.env` files, deriving ports, running install commands — 5-10 minutes of tax per worktree. This toolkit automates that to near-zero.

Two layers:

1. **A bash script** handles everything Claude can't see: copying `.env` files, deriving ports, running install commands.
2. **Claude Code skills** (`/wt-open`, `/wt-merge`, `/wt-close`, `/wt-list`, `/wt-adopt`) provide the orchestration layer: naming branches, deciding merge strategies, tracking worktree state.

## Quick start

```bash
# 1. Install the toolkit into your repo
npx @thinkvelta/claude-worktree-tools

# 2. Open Claude Code and customize the setup script for your stack
/wt-adopt

# 3. Create a worktree and start working
/wt-open implement the auth refactor from issue 42
```

## What it installs

| File                                 | Purpose                                                                 |
| ------------------------------------ | ----------------------------------------------------------------------- |
| `scripts/wt-setup.sh`                | Bash script that bootstraps a worktree (env files, ports, dependencies) |
| `.claude/skills/wt-open/SKILL.md`    | Create or reopen a worktree                                             |
| `.claude/skills/wt-merge/SKILL.md`   | Merge a worktree branch into another branch                             |
| `.claude/skills/wt-close/SKILL.md`   | Finish work — push, remove worktree, optionally delete branch           |
| `.claude/skills/wt-list/SKILL.md`    | List active worktrees with status                                       |
| `.claude/skills/wt-adopt/SKILL.md`   | Customize setup script for your repo's stack                            |
| `.claude/skills/wt-help/SKILL.md`    | Answer common questions about worktree workflow                         |
| `.claude/skills/wt-cleanup/SKILL.md` | Batch cleanup of stale worktrees and orphaned branches                  |

It also appends `.claude/worktrees` to your `.gitignore`.

## Skills

### `/wt-open [branch | task description]`

Creates a new worktree or reopens an existing one. Accepts a branch name (`feat/auth`) or a natural language description ("add auth to the API") from which it derives a branch name. Runs the setup script to copy `.env` files, derive ports, and install dependencies.

### `/wt-merge <branch> --into <target> [--no-close]`

Merges a worktree's branch into another branch using `git merge`. Always a real merge — for pushing to remote, use `/wt-close --push`. Useful for batching small fixes into one branch or folding sub-feature branches back into a parent.

### `/wt-close [branch] [--push] [--force]`

Finishes work in a worktree. Optionally pushes the branch to origin (`--push`), then lets you choose: remove worktree only, remove worktree + delete branch, or keep everything.

### `/wt-cleanup [--dry-run]`

Batch housekeeping: finds stale worktrees (7+ days inactive), missing worktree directories, orphaned branches, and local branches whose remote was deleted (e.g. after a PR merge on GitHub). Presents a report and lets you choose what to clean up.

### `/wt-list [--stale]`

Lists all active worktrees with: branch name, clean/dirty status, ahead/behind remote, last commit, and staleness warnings (3+ days inactive).

### `/wt-adopt [--check-only]`

Reads your repo's stack (package.json, pyproject.toml, Dockerfile, docker-compose, .env.example, Makefile, etc.) and customizes `scripts/wt-setup.sh` to fit. Runs a health check that flags hardcoded ports, missing env templates, and other worktree-unfriendly patterns.

### `/wt-help [topic]`

Answers common questions about working with worktrees: VSCode integration, why `.gitignore` is needed, how port offsets work, `.env` file handling, local merge workflows, and more. Good starting point for new users.

## CLI flags

```
npx @thinkvelta/claude-worktree-tools [options]

Options:
  --force, -f            Overwrite existing files
  --dry-run, -n          Print what would happen without writing
  --scripts-dir <path>   Directory for wt-setup.sh (default: scripts)
  --help, -h             Show help
```

## Requirements

- Node.js >= 18
- Git
- Unix-like environment (macOS, Linux, or WSL on Windows)
- [GitHub CLI](https://cli.github.com/) (`gh`) — optional, used by `/wt-merge` for PR creation

## How it works

Worktrees are created under `.claude/worktrees/<branch-name>/` inside your repo. Each worktree gets:

- **Copied `.env` files** from the main repo (preserving directory structure), copied by a script not an LLM
- **Deterministic port offsets** (0-99, derived from the worktree path hash) so each worktree runs services on different ports so you can compare them side-by-side
- **Installed dependencies** via the detected package manager, customized for your repo through `/wt-adopt`

The same branch name always produces the same worktree path and port offset. Running `/wt-open` on an existing branch reopens rather than duplicates.

## Local development & testing

### Try it on a real repo

`try-install.sh` is the local equivalent of `npx @thinkvelta/claude-worktree-tools`. It installs the toolkit files into any git repo:

```bash
./try-install.sh /path/to/your/repo
./try-install.sh /path/to/your/repo --dry-run   # preview without writing
./try-install.sh /path/to/your/repo --force      # overwrite existing files
```

### Run the test suite

`test.sh` runs automated smoke tests (install, flags, idempotency, worktree creation):

```bash
./test.sh                    # uses a temp directory
./test.sh /tmp/my-test-repo  # uses the specified directory
make test                    # same thing via Makefile
make ci                      # lint + test
```
