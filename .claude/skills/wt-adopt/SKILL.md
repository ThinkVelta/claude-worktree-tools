---
name: wt-adopt
description: Analyze the repo stack, customize wt-setup.sh for worktree-aware development, and run a health check. Use this when the user just installed the worktree tools and needs to configure them, when they changed their stack and need to update the setup script, or when they want to check if their repo is worktree-friendly. Also triggers for `/wt-adopt [--check-only]`.
model: opus
allowed-tools: Bash Read Write Edit Glob Grep
argument-hint: "[--check-only]"
---

# Worktree Adopt

Analyze this repository's stack and customize `scripts/wt-setup.sh` for worktree-aware development. Then run a health check.

**User input:** $ARGUMENTS

If `$ARGUMENTS` contains `--check-only`, skip Phase 2 (writing) and only run Phase 1 (analysis) and Phase 3 (health check).

---

## Phase 1 — Analyze the repository

Read the following files (if they exist) to understand the stack. Use Glob and Read — do not guess.

### Package managers and languages

Check for these files at the repo root:

| File                                                               | What to learn                                                     |
| ------------------------------------------------------------------ | ----------------------------------------------------------------- |
| `package.json`                                                     | Package manager, scripts, workspaces, dependencies                |
| `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `bun.lockb` | Which package manager is in use                                   |
| `pnpm-workspace.yaml` / `lerna.json` / `nx.json`                   | Monorepo structure                                                |
| `pyproject.toml` / `setup.py` / `requirements.txt` / `Pipfile`     | Python stack, package manager (uv/pip/poetry)                     |
| `uv.lock` / `poetry.lock`                                          | Python lock file — confirms package manager                       |
| `go.mod`                                                           | Go stack                                                          |
| `Cargo.toml`                                                       | Rust stack                                                        |
| `Gemfile`                                                          | Ruby stack                                                        |
| `Makefile`                                                         | Available targets (especially `setup`, `install`, `dev`, `build`) |

### Infrastructure and services

| File                                                        | What to learn                                       |
| ----------------------------------------------------------- | --------------------------------------------------- |
| `Dockerfile` / `docker-compose.yml` / `docker-compose.yaml` | Services, exposed ports, port configuration         |
| `.env.example` / `.env.template`                            | Expected environment variables, default port values |
| `.tool-versions` / `.node-version` / `.python-version`      | Runtime version requirements                        |

### Port detection

Search for port-related patterns:

```bash
grep -rn "PORT\|:3000\|:3001\|:5000\|:5173\|:8000\|:8080\|:4200" \
  docker-compose.yml docker-compose.yaml .env.example Dockerfile Makefile package.json 2>/dev/null
```

Also check source code for hardcoded ports in server startup files.

### Monorepo detection

```bash
ls -d */package.json */pyproject.toml 2>/dev/null
```

If multiple package manifests exist in subdirectories, note each workspace and its stack.

Record all findings before proceeding.

---

## Phase 2 — Customize `scripts/wt-setup.sh`

**Skip this phase if `--check-only` was specified.**

Read the existing `scripts/wt-setup.sh`. If it does not exist, tell the user to install the toolkit first:

> Setup script not found. Run `npx @thinkvelta/claude-worktree-tools` to install it, then re-run `/wt-adopt`.

### Update the REPO-SPECIFIC PORT CONFIG section

**Do not blindly introduce `*_PORT` variables.** First analyze how the repo already encodes ports in its environment. The right pattern depends on what already exists — pick one that matches, don't add a parallel system.

#### Step 1 — Classify each port-bearing env var

For each port found in Phase 1, identify which env var carries it. There are three common shapes:

| Shape                    | Example                              | What to do                                                                                                |
| ------------------------ | ------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| **URL-embedded**         | `BACKEND_URL=http://localhost:8000`  | Rewrite the URL with the new port. Don't introduce a separate `BACKEND_PORT` — that would be duplicative. |
| **Bare port var**        | `PORT=8000` or `BACKEND_PORT=8000`   | Rewrite the port var directly. This is the simplest case.                                                 |
| **Both, with port var as source** | `PORT=8000` + `URL=http://localhost:${PORT}` | Rewrite only the bare port var; the URL resolves at read time. |

If a URL is the source of truth (the app reads the URL and parses the port out of it), changing only a `PORT` var does nothing — the app will still hit the wrong port. Always trace which variable is actually consumed.

Also identify any **derived vars** that must be kept consistent: `CORS_ALLOWED_ORIGINS`, redirect URLs, OAuth callback URLs, email confirmation links — these often hardcode the same host:port and need rewriting too.

#### Step 2 — Pick a pattern and fill in the section

**Pattern A — Bare port vars (simple).** Use when the repo's `.env.example` exposes ports as standalone variables.

```bash
# === REPO-SPECIFIC PORT CONFIG (filled in by /wt-adopt) ===
BACKEND_PORT=$((8000 + PORT_OFFSET))
FRONTEND_PORT=$((3000 + PORT_OFFSET))

update_env_var() {
  local file="$1" key="$2" val="$3"
  [[ -f "$file" ]] || return 0
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "${file}.bak"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

update_env_var "${WORKTREE_DIR}/.env" BACKEND_PORT "$BACKEND_PORT"
update_env_var "${WORKTREE_DIR}/.env" FRONTEND_PORT "$FRONTEND_PORT"

info "Ports — backend: ${BACKEND_PORT}, frontend: ${FRONTEND_PORT}"
```

**Pattern B — URL-embedded ports.** Use when the repo already has `BACKEND_URL` / `FRONTEND_URL` (or similar) as the source of truth. Rewrite the URLs, plus any derived vars (CORS, callbacks).

```bash
# === REPO-SPECIFIC PORT CONFIG (filled in by /wt-adopt) ===
# BACKEND_URL and FRONTEND_URL are the source of truth — the app parses
# the port out of them. Rewrite both URLs, plus CORS_ALLOWED_ORIGINS so
# the worktree's frontend can talk to its own backend.
BACKEND_PORT=$((8000 + PORT_OFFSET))
FRONTEND_PORT=$((3000 + PORT_OFFSET))

update_env_var() { ... }  # same helper as above

update_env_var "${WORKTREE_DIR}/.env" BACKEND_URL "http://localhost:${BACKEND_PORT}"
update_env_var "${WORKTREE_DIR}/.env" FRONTEND_URL "http://localhost:${FRONTEND_PORT}"
update_env_var "${WORKTREE_DIR}/.env" CORS_ALLOWED_ORIGINS "http://localhost:${FRONTEND_PORT}"

info "Ports — backend: ${BACKEND_PORT}, frontend: ${FRONTEND_PORT}"
```

**Hybrid:** mix patterns when each service uses a different shape (e.g., backend has `PORT=`, frontend has `FRONTEND_URL=`). Use the actual variable names from the repo — never invent ones that don't already exist.

### Update the REPO-SPECIFIC INSTALL section

Based on the detected package manager, uncomment and fill in the install section.

| Detection                    | Install command                                             |
| ---------------------------- | ----------------------------------------------------------- |
| `pnpm-lock.yaml` exists      | `(cd "${WORKTREE_DIR}" && pnpm install --frozen-lockfile)`  |
| `yarn.lock` exists           | `(cd "${WORKTREE_DIR}" && yarn install --frozen-lockfile)`  |
| `bun.lockb` exists           | `(cd "${WORKTREE_DIR}" && bun install)`                     |
| `package-lock.json` exists   | `(cd "${WORKTREE_DIR}" && npm ci)`                          |
| `uv.lock` exists             | `(cd "${WORKTREE_DIR}" && uv sync)`                         |
| `poetry.lock` exists         | `(cd "${WORKTREE_DIR}" && poetry install)`                  |
| `requirements.txt` exists    | `(cd "${WORKTREE_DIR}" && pip install -r requirements.txt)` |
| `Gemfile.lock` exists        | `(cd "${WORKTREE_DIR}" && bundle install)`                  |
| Makefile with `setup` target | `make -C "${WORKTREE_DIR}" setup`                           |

For monorepos, chain multiple install commands.

#### Watch for interactive prompts

`wt-setup.sh` runs unattended — any command that prompts for input will hang the worktree creation. Before wiring an install/setup command in, check whether it prompts. This is **stack-agnostic**: it can happen with Make targets, npm scripts, Python entrypoints, or shell scripts.

| Toolchain         | Look for                                                                              |
| ----------------- | ------------------------------------------------------------------------------------- |
| Shell / Make      | `read -p`, `read -r` without `< /dev/null`, `gum input`, `whiptail`, `dialog`         |
| npm / package.json `scripts` | Scripts that delegate to interactive CLIs (`prisma init`, `vercel login`, etc.) |
| Python            | `input(`, `click.prompt`, `inquirer.prompt`, `rich.prompt.Prompt`                     |
| Setup wrappers    | A top-level `setup` / `prepare` / `bootstrap` target that wraps a non-interactive one |

If the chosen command prompts, prefer one of:

1. **Fall through to a non-interactive subcommand.** Many `setup` targets are thin wrappers around `install-deps` + something interactive (e.g., `supabase login`, `git config`). Wire the install-only subtarget directly: `make backend-setup` instead of `make prepare`, `npm run install-deps` instead of `npm run setup`.
2. **Pass non-interactive flags.** `--yes`, `--non-interactive`, `--no-input`, `CI=1`, `DEBIAN_FRONTEND=noninteractive`.
3. **Pipe a default.** `yes "" | <command>` or `<command> < /dev/null` if the prompts are skippable.

If none of those work, leave the interactive step out of `wt-setup.sh` and surface it as a `[SUGGEST]` in the health check so the user runs it manually after the worktree is created.

### Preserve other sections

When editing `wt-setup.sh`:

- **Keep** the GENERIC sections untouched.
- **Keep** the USER-DEFINED EXTRA SETUP section untouched (even if empty).
- **Only replace** content between the REPO-SPECIFIC section markers.

Show the user a summary of proposed changes before writing. Apply with the Edit tool.

### Update .gitignore

Verify `.claude/worktrees` is in `.gitignore`. If not, append it.

---

## Phase 3 — Health check report

Run diagnostics and present a structured report.

### Status checks (pass/fail)

| Check                                          | How to verify                                             |
| ---------------------------------------------- | --------------------------------------------------------- |
| `.claude/worktrees` in `.gitignore`            | `grep -q '.claude/worktrees' .gitignore`                  |
| `scripts/wt-setup.sh` exists and is executable | `test -x scripts/wt-setup.sh`                             |
| `.env` files found                             | `find . -name '.env*' -not -path './.git/*' -type f`      |
| Install command detected                       | Verify the REPO-SPECIFIC INSTALL section is filled in     |
| Services and ports identified                  | Verify the REPO-SPECIFIC PORT CONFIG section is filled in |
| Script syntax valid                            | `bash -n scripts/wt-setup.sh`                             |

### Warnings (potential problems)

Scan for these issues:

| Warning                            | What to look for                                                            |
| ---------------------------------- | --------------------------------------------------------------------------- |
| Hardcoded ports in Dockerfiles     | `EXPOSE <number>` without `ARG`, hardcoded `--port` in `CMD`                |
| Hardcoded ports in docker-compose  | Port mappings like `"3000:3000"` without variable substitution              |
| Hardcoded ports in source code     | Port numbers in config files or server startup scripts                      |
| Services not reading PORT from env | Server code that uses a literal port number                                 |
| Large `node_modules`               | Check if `node_modules` > 500MB (each worktree gets its own copy)           |
| No `.env.example`                  | New developers and the setup script have no reference for required env vars |

### Suggestions (actionable recommendations)

For each issue found, print a specific, actionable suggestion with file and line reference:

```
[SUGGEST] Dockerfile:12 — EXPOSE 8000
  Change to: ARG PORT=8000 / EXPOSE $PORT
  And update CMD to read $PORT from environment.

[SUGGEST] docker-compose.yml:8 — "3000:3000"
  Change to: "${PORT_FRONTEND:-3000}:3000"

[SUGGEST] No .env.example found
  Create one with default values for all required environment variables.
  This helps the setup script and new developers.
```

### Summary

End with a compact summary:

```
Health Check Summary
════════════════════
Stack:        <detected stack>
Script:       scripts/wt-setup.sh (configured | needs setup)
Checks:       X passed, Y warnings
Suggestions:  Z actionable items
```

## Guiding principles

**Minimal footprint.** This skill only writes to `scripts/wt-setup.sh` and `.gitignore`. It analyzes Dockerfiles, source code, and config files but never modifies them — those are the user's domain. The health check _suggests_ changes to those files, but the user decides whether and how to apply them.

**Show before writing.** The user should see what you plan to change in `wt-setup.sh` before you write it. They may have context about their stack that the analysis missed.

**Safe to re-run.** The repo-specific sections get overwritten each time (that's the point — pick up stack changes), but the user-defined extra setup section is always preserved. This makes `/wt-adopt` a safe "refresh" command after stack changes.
