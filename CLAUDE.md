# Claude Worktree Tools

Worktree lifecycle toolkit for parallel AI-agent development with Claude Code.

## Project overview

`@thinkvelta/claude-worktree-tools` is an npm package that installs worktree lifecycle files into
any git repo. When a user runs `npx @thinkvelta/claude-worktree-tools`, it writes a bash setup
script and the `wt-*` Claude Code skills into the target repo.

## Repository structure

```text
bin/init.js                          CLI entry point (ESM, zero deps)
templates/wt-setup.sh                Bash script template → target's scripts/wt-setup.sh
templates/skills/wt-*/SKILL.md       Skill templates → target's .claude/skills/wt-*/SKILL.md
scripts/wt-setup.sh                  This repo's own installed copy (dogfooding)
try-install.sh                       Install from the published package (dev use)
local-install.sh                     Install from this checkout (dev use)
test.sh                              Smoke test suite
Makefile                             help, prepare, lint, test, ci, clean
.github/workflows/ci.yml             CI: lint + OS × node test matrix
.github/workflows/pr.yml             CI: automated Codex PR review
```

## Key concepts

- **Templates live in `templates/`** and get copied verbatim into target repos by `bin/init.js`.
  The root `.claude/` directory is dev tooling for this project — it is not part of the
  deliverable (`package.json` ships only `bin/` and `templates/`).
- **`.claude/skills/wt-*/SKILL.md` mirrors `templates/skills/wt-*/SKILL.md` byte-for-byte** —
  this repo dogfoods its own output, and `test.sh` asserts the two copies are identical. Edit
  `templates/`, mirror into `.claude/skills/`, **in the same commit**.
- **`bin/init.js`** is the only runtime code. It reads templates, writes them to the target repo,
  and updates `.gitignore`. Zero dependencies, pure `node:fs`/`node:path`.
- **`wt-setup.sh`** has four sections: generic (do not edit), repo-specific port config (filled by
  `/wt-adopt`), repo-specific install (filled by `/wt-adopt`), and user-defined extra setup (never
  auto-filled).
- **Skills** use YAML frontmatter with `name`, `description`, `model`, `allowed-tools` and
  `argument-hint`. The `wt-*` skills run inline in the user's Claude Code session (no agent fork).

## Commands

- `make` / `make help` — list every target
- `make prepare` — install the git hooks (pre-commit + commit-msg); run once per clone
- `make lint` — `uvx pre-commit run --all-files`: markdownlint, shellcheck, shfmt, actionlint,
  file hygiene. **It rewrites files** (markdownlint, shfmt, whitespace fixers) and reports a
  failure when it does — re-run it and commit what changed.
- `make test` — `bash test.sh tmp/test-make`; prints `<N> passed`
- `make ci` — lint + test, the local equivalent of CI
- `./try-install.sh /path/to/any/repo [--dry-run|--force]` — install into a real repo

Tool versions are pinned in `.mise.toml` (`mise install` provisions them) and, for every linter,
in `.pre-commit-config.yaml`.

## Conventions

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `test:`),
  enforced by the commitizen commit-msg hook
- Feature branches (`feature/...`, `feat/...`, `fix/...`, `chore/...`), never commit directly to `main`
- ESM (`"type": "module"` in package.json), Node >= 20
- **No runtime dependencies, ever** — `bin/init.js` imports only `node:*` builtins
- macOS + Linux compatible bash (no GNU-only flags, nothing beyond bash 3.2)
- Never use `rm -rf` — tell the user what to remove
- Never use `cd X && command` in Bash tool calls — use `git -C` or a subshell

## Git workflow

Feature branches branch off `main` and PR back into it; a human merges every PR.

- Push only your own feature branch, always with an explicit refspec
  (`git push -u origin HEAD:refs/heads/<feature-branch>`)
- Never `gh pr merge`, never `git commit --no-verify` — a PreToolUse hook blocks both mechanically
- PRs receive an automated Codex review comment; address its points or reply explaining why not
- **Comment before pushing, always**: the reviewer snapshots the PR when new commits arrive, so an
  explanation posted after the push is invisible to the round that push triggered
- **Write PR bodies and commit messages to a file, then `--body-file` / `-F`**: passing prose with
  backticks or `$` inline to `gh`/`git` through a shell lets it substitute or execute them

## Before finishing any task

`make lint` and `make test` must both pass.

## Rules and skills

Always-on, path-scoped conventions live in `.claude/rules/`; repeatable workflows live in
`.claude/skills/` as slash commands (`/commit`, `/pr-open`, `/pr-iterate`, `/pr-babysit`,
`/cleanup`, plus the shipped `/wt-open`, `/wt-close`, `/wt-list`, `/wt-merge`, `/wt-cleanup`,
`/wt-adopt`, `/wt-help`). See `.claude/README.md` for how the pieces fit together.
