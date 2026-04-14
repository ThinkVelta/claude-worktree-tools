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

| File | Purpose |
|------|---------|
| `scripts/wt-setup.sh` | Bash script that bootstraps a worktree (env files, ports, dependencies) |
| `.claude/skills/wt-open/SKILL.md` | Create or reopen a worktree |
| `.claude/skills/wt-merge/SKILL.md` | Merge a worktree branch back (PR or local merge) |
| `.claude/skills/wt-close/SKILL.md` | Tear down a worktree cleanly |
| `.claude/skills/wt-list/SKILL.md` | List active worktrees with status |
| `.claude/skills/wt-adopt/SKILL.md` | Customize setup script for your repo's stack |

It also appends `.claude/worktrees` to your `.gitignore`.

## Skills

### `/wt-open [branch | task description]`

Creates a new worktree or reopens an existing one. Accepts a branch name (`feat/auth`) or a natural language description ("add auth to the API") from which it derives a branch name. Runs the setup script to copy `.env` files, derive ports, and install dependencies.

### `/wt-merge [branch] [--local] [--into <target>]`

Merges a worktree's branch back. Default: pushes and opens a PR via `gh`. With `--local` or `--into`: merges locally (useful for batching small fixes or branch decomposition). Cleans up the worktree after merge.

### `/wt-close [branch] [--force] [--keep-branch]`

Tears down a worktree safely. Checks for uncommitted changes and unpushed commits before removing. Asks whether to delete the branch based on merge status.

### `/wt-list [--stale]`

Lists all active worktrees with: branch name, clean/dirty status, ahead/behind remote, last commit, and staleness warnings (3+ days inactive).

### `/wt-adopt [--check-only]`

Reads your repo's stack (package.json, pyproject.toml, Dockerfile, docker-compose, .env.example, Makefile, etc.) and customizes `scripts/wt-setup.sh` to fit. Runs a health check that flags hardcoded ports, missing env templates, and other worktree-unfriendly patterns.

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

- **Copied `.env` files** from the main repo (preserving directory structure)
- **Deterministic port offsets** (0-99, derived from the worktree path hash) so each worktree runs services on different ports
- **Installed dependencies** via the detected package manager

The same branch name always produces the same worktree path and port offset. Running `/wt-open` on an existing branch reopens rather than duplicates.

## Local development & testing

To test the package locally without publishing to npm:

```bash
# Run test.sh with a target directory (creates a temp git repo there)
./test.sh /tmp/my-test-repo

# Or let it use the default location
./test.sh
```

`test.sh` creates a temporary git repo, runs `bin/init.js` against it, and verifies that all files are installed correctly. It also tests `--dry-run`, `--force`, and `--scripts-dir` flags.

To manually test in an existing repo:

```bash
cd /path/to/your/repo
node /path/to/claude-worktree-tools/bin/init.js
```

## License

MIT
