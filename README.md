# Claude Worktree Tools

**Give Claude Code its own branch, its own directory, and its own ports — in one command.**

[![npm](https://img.shields.io/npm/v/@thinkvelta/claude-worktree-tools)](https://www.npmjs.com/package/@thinkvelta/claude-worktree-tools)
[![license](https://img.shields.io/npm/l/@thinkvelta/claude-worktree-tools)](LICENSE)

Run several agents on the same repo at once without them tripping over each other's working
directory, `.env`, or dev-server port.

<!-- BEGIN GENERATED DEMO -->
<!-- Regenerate with `make demo`. Do not hand-edit. -->

```console
$ cd /home/dev/acme-api
$ ./scripts/wt-setup.sh feat/rate-limiting --base main
==> Creating new branch 'feat/rate-limiting' from 'main'
Preparing worktree (new branch 'feat/rate-limiting')
HEAD is now at 40eae58 add worktree toolkit
==> Copying .env files from main repo to worktree
==> Copied 1 .env file(s)
==> Port offset for this worktree: 8

==> Worktree ready!

  Branch:        feat/rate-limiting
  Base:          main
  Path:          /home/dev/acme-api/.claude/worktrees/feat-rate-limiting-7628ffc0
  Port offset:   8

```

<!-- END GENERATED DEMO -->

## Install

From anywhere inside your git repo:

```bash
npx @thinkvelta/claude-worktree-tools
```

This writes `scripts/wt-setup.sh`, the `.claude/skills/wt-*/` skill files, and appends
`.claude/worktrees` to your `.gitignore`. Review the changes, then commit them.

Then open Claude Code in the repo and run:

```text
/wt-adopt
```

`/wt-adopt` reads your stack (package.json, pyproject.toml, Dockerfile, docker-compose,
`.env.example`, Makefile, …) and rewrites `scripts/wt-setup.sh` to match — install commands, ports
to offset, env files to copy. It also runs a health check that flags hardcoded ports and other
worktree-unfriendly patterns.

Both steps are **one-time per repo**. After that you just use the `/wt-*` skills.

```text
/wt-open implement the auth refactor from issue 42
```

### Tailor it before you commit

`/wt-adopt` gets you most of the way, but every repo has quirks:

- Open `scripts/wt-setup.sh` and adjust the install commands, port list, and any custom bootstrap
  steps (DB seeding, codegen, symlinks…) the heuristic couldn't infer.
- Skim the installed skills under `.claude/skills/wt-*/SKILL.md`. They're plain markdown — edit
  branch-naming conventions, default base branches, or merge strategies to match your team.
- Commit the customizations so the rest of your team inherits them.

### Install flags

| Flag                   | Purpose                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `--force`, `-f`        | Overwrite existing files. Required for re-installs or updates.                                                           |
| `--dry-run`, `-n`      | Print what would be written without touching the filesystem.                                                             |
| `--skills-only`        | Install only the `/wt-*` skills under `.claude/skills/`. Skips `wt-setup.sh` and the `.gitignore` entry. See note below. |
| `--scripts-dir <path>` | Where to place `wt-setup.sh` relative to repo root (default: `scripts`). Must stay inside the repo.                      |
| `--help`, `-h`         | Show CLI help.                                                                                                           |

> **Updating later.** Once you've customized `scripts/wt-setup.sh` for your repo, you don't want a
> subsequent install to overwrite it. Use
> `npx @thinkvelta/claude-worktree-tools --skills-only --force` to refresh just the skill files.

## Why

When you run Claude Code in your repo, you share one working directory. Git worktrees give the
agent its own directory on its own branch, but setting up a worktree means copying `.env` files,
deriving ports, running install commands — 5-10 minutes of tax per worktree. This toolkit automates
that to near-zero.

Two layers:

1. **A bash script** handles everything Claude can't see: copying `.env` files, deriving ports,
   running install commands.
2. **Claude Code skills** provide the orchestration layer: naming branches, deciding merge
   strategies, tracking worktree state.

## The skills

| Skill                                             | What it does                                                                                                                                                                                                          |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/wt-open [branch \| description]`                | Create or reopen a worktree. Accepts a branch name (`feat/auth`) or a natural-language description it derives one from. Runs the setup script to copy `.env` files, derive ports, and install dependencies.           |
| `/wt-close [branch] [--push] [--force]`           | Finish work in a worktree. Optionally pushes to origin, then lets you choose: remove worktree only, remove worktree + delete branch, or keep everything.                                                              |
| `/wt-merge <branch> --into <target> [--no-close]` | Local `git merge` of one worktree branch into another. Useful for batching small fixes into one branch, or folding sub-features back into a parent before opening a single PR.                                        |
| `/wt-list [--stale]`                              | List active worktrees with branch, clean/dirty status, ahead/behind remote, last commit age, and staleness warnings.                                                                                                  |
| `/wt-cleanup [--dry-run]`                         | Batch housekeeping: finds stale worktrees (7+ days inactive), missing directories, orphaned branches, and branches whose remote was deleted after a PR merge. Presents a report and lets you choose what to clean up. |
| `/wt-adopt [--check-only]`                        | Reads your repo's stack and rewrites `scripts/wt-setup.sh` to match. Runs a health check that flags hardcoded ports, missing env templates, and other worktree-unfriendly patterns.                                   |
| `/wt-help [question]`                             | Overview and FAQ — VSCode integration, ports, env files, merge strategies. Good starting point for new users.                                                                                                         |

Plus `scripts/wt-setup.sh`, the bash script that does the actual bootstrapping. That is the file
you customize.

## How it works

Worktrees are created under `.claude/worktrees/<branch>-<hash>/` inside your repo. Each one gets:

- **Copied `.env` files** from the main repo, preserving directory structure — copied by a script,
  not by an LLM.
- **A deterministic port offset** (0-99, derived from a hash of the worktree path) so each worktree
  runs its services on different ports and you can compare them side by side.
- **Installed dependencies** via the detected package manager, customized for your repo through
  `/wt-adopt`.

The same branch name always produces the same worktree path and port offset, so `/wt-open` on an
existing branch reopens rather than duplicates.

## Requirements

- Node.js >= 20
- Git
- Unix-like environment (macOS, Linux, or WSL on Windows)
- [GitHub CLI](https://cli.github.com/) (`gh`) — optional; `/wt-cleanup` uses it to spot branches
  whose PR has already been merged

## Support this project

If this saves you time, the cheapest way to help costs nothing:

- ⭐ Star the repo — it's how other people find it.
- 🐛 Tell us where it broke. Friction reports on a real repo are worth more than feature requests.
- 🧩 Contribute a `/wt-adopt` recipe for a stack it handles badly.
- ✍️ Improve a skill playbook — they're plain markdown, and a clearer instruction helps every user's
  agent.

If you'd rather support it financially, the Sponsor button at the top of the repo covers both
GitHub Sponsors and PayPal.

## Contributing

See [CLAUDE.md](CLAUDE.md) for the repo layout, conventions, and how to run the checks, and
[RELEASING.md](RELEASING.md) for the publish flow.

```bash
make            # list every target
make prepare    # install the git hooks — run once per clone
make ci         # lint + tests, the local equivalent of CI
```

## License

MIT — see [LICENSE](LICENSE).
