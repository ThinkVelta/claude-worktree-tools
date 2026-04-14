---
name: wt-adopt
description: Analyze the repo stack, customize wt-setup.sh, and run a health check. Invoke with `/wt-adopt`.
metadata:
  allowed_tools:
    - Bash
    - Read
    - Write
    - Edit
    - Glob
    - Grep
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

| File | What to learn |
|---|---|
| `package.json` | Package manager, scripts, workspaces, dependencies |
| `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `bun.lockb` | Which package manager is in use |
| `pnpm-workspace.yaml` / `lerna.json` / `nx.json` | Monorepo structure |
| `pyproject.toml` / `setup.py` / `requirements.txt` / `Pipfile` | Python stack, package manager (uv/pip/poetry) |
| `uv.lock` / `poetry.lock` | Python lock file — confirms package manager |
| `go.mod` | Go stack |
| `Cargo.toml` | Rust stack |
| `Gemfile` | Ruby stack |
| `Makefile` | Available targets (especially `setup`, `install`, `dev`, `build`) |

### Infrastructure and services

| File | What to learn |
|---|---|
| `Dockerfile` / `docker-compose.yml` / `docker-compose.yaml` | Services, exposed ports, port configuration |
| `.env.example` / `.env.template` | Expected environment variables, default port values |
| `.tool-versions` / `.node-version` / `.python-version` | Runtime version requirements |

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

Based on the ports found in Phase 1, uncomment and fill in the port config section.

Example for a Next.js + FastAPI project:

```bash
# === REPO-SPECIFIC PORT CONFIG (filled in by /wt-adopt) ===
BACKEND_PORT=$((8000 + PORT_OFFSET))
FRONTEND_PORT=$((3000 + PORT_OFFSET))

update_env_var() {
  local file="$1" key="$2" val="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "${file}.bak"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

update_env_var "${WORKTREE_DIR}/.env" PORT "$BACKEND_PORT"
update_env_var "${WORKTREE_DIR}/.env" FRONTEND_PORT "$FRONTEND_PORT"

info "Ports — backend: ${BACKEND_PORT}, frontend: ${FRONTEND_PORT}"
```

Use the actual variable names and ports found in the repo's `.env.example` or configuration files.

### Update the REPO-SPECIFIC INSTALL section

Based on the detected package manager, uncomment and fill in the install section.

| Detection | Install command |
|---|---|
| `pnpm-lock.yaml` exists | `(cd "${WORKTREE_DIR}" && pnpm install --frozen-lockfile)` |
| `yarn.lock` exists | `(cd "${WORKTREE_DIR}" && yarn install --frozen-lockfile)` |
| `bun.lockb` exists | `(cd "${WORKTREE_DIR}" && bun install)` |
| `package-lock.json` exists | `(cd "${WORKTREE_DIR}" && npm ci)` |
| `uv.lock` exists | `(cd "${WORKTREE_DIR}" && uv sync)` |
| `poetry.lock` exists | `(cd "${WORKTREE_DIR}" && poetry install)` |
| `requirements.txt` exists | `(cd "${WORKTREE_DIR}" && pip install -r requirements.txt)` |
| `Gemfile.lock` exists | `(cd "${WORKTREE_DIR}" && bundle install)` |
| Makefile with `setup` target | `make -C "${WORKTREE_DIR}" setup` |

For monorepos, chain multiple install commands.

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

| Check | How to verify |
|---|---|
| `.claude/worktrees` in `.gitignore` | `grep -q '.claude/worktrees' .gitignore` |
| `scripts/wt-setup.sh` exists and is executable | `test -x scripts/wt-setup.sh` |
| `.env` files found | `find . -name '.env*' -not -path './.git/*' -type f` |
| Install command detected | Verify the REPO-SPECIFIC INSTALL section is filled in |
| Services and ports identified | Verify the REPO-SPECIFIC PORT CONFIG section is filled in |
| Script syntax valid | `bash -n scripts/wt-setup.sh` |

### Warnings (potential problems)

Scan for these issues:

| Warning | What to look for |
|---|---|
| Hardcoded ports in Dockerfiles | `EXPOSE <number>` without `ARG`, hardcoded `--port` in `CMD` |
| Hardcoded ports in docker-compose | Port mappings like `"3000:3000"` without variable substitution |
| Hardcoded ports in source code | Port numbers in config files or server startup scripts |
| Services not reading PORT from env | Server code that uses a literal port number |
| Large `node_modules` | Check if `node_modules` > 500MB (each worktree gets its own copy) |
| No `.env.example` | New developers and the setup script have no reference for required env vars |

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

## Important rules

- **Only write to:** `scripts/wt-setup.sh` and `.gitignore`. Never modify source code, Dockerfiles, or any other project files.
- **Always show proposed changes** before writing them.
- **Idempotent:** Safe to re-run. Overwrites repo-specific sections, preserves user-defined sections.
- If `--check-only`, do NOT write any files — only analyze and report.
