# Agents Guide — Claude Worktree Tools

## Project overview

`@thinkvelta/claude-worktree-tools` is an npm package that installs worktree lifecycle files into any git repo. When a user runs `npx @thinkvelta/claude-worktree-tools`, it writes a bash setup script and five Claude Code skills into the target repo.

## Repository structure

```
bin/init.js                          CLI entry point (ESM, zero deps)
templates/wt-setup.sh                Bash script template → target's scripts/wt-setup.sh
templates/skills/wt-*/SKILL.md       Skill templates → target's .claude/skills/wt-*/SKILL.md
try-install.sh                       Local install script (dev use)
test.sh                              Smoke test suite
Makefile                             lint, test, ci targets
.github/workflows/ci.yml             CI: lint + test matrix
```

## Key concepts

- **Templates live in `templates/`** and get copied verbatim into target repos by `bin/init.js`. The root `.claude/` directory is dev tooling for this project — it is not part of the deliverable.
- **`bin/init.js`** is the only runtime code. It reads templates, writes them to the target repo, and updates `.gitignore`. Zero dependencies, pure `node:fs`/`node:path`.
- **`wt-setup.sh`** has four sections: generic (do not edit), repo-specific port config (filled by `/wt-adopt`), repo-specific install (filled by `/wt-adopt`), and user-defined extra setup (never auto-filled).
- **Skills** use YAML frontmatter with `name`, `description`, and `metadata` (including `allowed_tools` and `argument-hint`). They run inline in the user's Claude Code session (no agent fork).

## Conventions

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `test:`)
- Feature branches (`feature/...`), never commit directly to `main`
- ESM (`"type": "module"` in package.json), Node >= 18
- No runtime dependencies
- macOS + Linux compatible bash (no GNU-only flags)
- Never use `rm -rf` — tell the user what to remove
- Never use `cd X && command` in Bash tool calls — use `git -C` or subshells

## Testing

```bash
make ci          # lint + test
make test        # smoke tests only
make lint        # markdownlint + shellcheck + bash -n
./test.sh        # runs tests, defaults to tmp/ inside the repo
```

## Try locally

```bash
./try-install.sh /path/to/any/repo            # install into a real repo
./try-install.sh /path/to/any/repo --dry-run  # preview without writing
./try-install.sh /path/to/any/repo --force    # overwrite existing files
```
