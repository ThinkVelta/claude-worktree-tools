# `.claude/` — Claude Code configuration

This directory configures how Claude Code works on **this** repo: rules it follows, skills
(slash commands) it can invoke, guard hooks, and permission settings.

Note this directory's double role here: it is dev tooling *and* a live copy of what the package
ships. See "The `wt-*` skills are the product" below before editing anything under `skills/wt-*`.

## Layout

| Path | Role |
| - | - |
| `CLAUDE.md` (repo root) | Project orientation — loaded into every Claude session |
| `settings.json` | Project-shared permissions, hooks wiring, env defaults (committed) |
| `settings.local.json` | Per-developer overrides (gitignored, do NOT commit) |
| `rules/` | Always-on, path-scoped rules layered into the system prompt |
| `hooks/` | Guard scripts wired in `settings.json` that mechanically enforce repo rules |
| `skills/` | Slash commands, one folder with a `SKILL.md` each |
| `agents/` | Subagent definitions (model, tools, playbook) skills delegate to via `agent:` |
| `worktrees/` | Parallel-branch checkouts managed by the `/wt-*` skills (gitignored) |
| `agent-memory/` | Machine-local agent scratch state (gitignored) |

Everything in `.claude/` is committed and shared **except** the machine-local state:
`settings.local.json`, `agent-memory/`, `worktrees/`, and `*.lock` are gitignored.

The contents of each directory are self-describing — every skill carries its own frontmatter
(`name`, `description`) and every rule file opens with its scope. Browse the directory rather
than relying on an inventory here; a listing would go stale the moment something is added or
renamed.

## How the pieces fit

- **`CLAUDE.md`** is loaded by Claude Code at session start. Think of it as the README a
  teammate would skim before touching the codebase.
- **`rules/*.md`** are *always-on* context. Every rule is layered into the system prompt for the
  paths it declares. Keep them short and durable — they cost tokens on every interaction.
- **`hooks/`** holds guard scripts (wired in `settings.json`) that enforce repo rules
  mechanically rather than by prose — a block takes effect before the tool call runs.
- **`skills/*/SKILL.md`** define slash commands that the user types.
- **`agents/*.md`** define the subagents some skills fork into: a skill whose frontmatter names
  an `agent:` (e.g. `/commit`, `/pr-open`, `/cleanup`) delegates its playbook to the matching
  file here, which pins the model and tool allowlist for that run. Agent identity comes from the
  `name:` frontmatter field, not the filename or path.
- **`settings.json`** controls permissions (which tool calls run without prompting), hook
  wiring, and environment defaults. Per-project.
- **`settings.local.json`** is the same shape but per-developer and gitignored — for personal
  allow-lists.

## The `wt-*` skills are the product

`templates/skills/wt-*/SKILL.md` is the **source of truth**: `bin/init.js` copies those files
verbatim into whatever repo a user runs `npx @thinkvelta/claude-worktree-tools` in.
`.claude/skills/wt-*/SKILL.md` is this repo dogfooding its own output — the two copies are
byte-identical, `test.sh` asserts it, and they must stay that way. Edit `templates/`, then
mirror into `.claude/skills/` (or vice versa) **in the same commit**, and verify:

```bash
for s in wt-open wt-close wt-cleanup wt-help wt-list wt-merge wt-adopt; do
  diff -q ".claude/skills/$s/SKILL.md" "templates/skills/$s/SKILL.md"
done
```

The other skills (`/commit`, `/pr-open`, `/pr-iterate`, `/pr-babysit`, `/cleanup`) and their
agents are dev tooling only — they are not shipped.

## Hooks

| Hook | Event | What it does |
| - | - | - |
| `guard-bash.sh` | `PreToolUse(Bash)` | Blocks non-explicit/protected/force pushes, `git commit --no-verify`, `gh pr merge`, and reads of `.env` files. Parses through wrappers, `sh -c`, `eval`, brace expansion, and `git -C`. |
| `redact-secrets.sh` + `.jq` | `PostToolUse(Bash)` | Masks API keys, tokens, JWTs, and inline URL credentials in Bash output before the model or the transcript sees it. Fails open (no `jq` → no redaction, never a broken tool call). |

Two consequences worth knowing:

- The push guard requires an explicit, non-protected destination. `git push`, `git push origin`,
  and `git push -u origin HEAD` are all blocked; `git push -u origin <feature-branch>` and
  `git push origin HEAD:refs/heads/<feature-branch>` are allowed.
- The `.env` guard is literal-matching, so reading *about* `.env` through a shell reader trips it:
  `grep -rn "\.env" templates/` is blocked. Use the Grep/Read tools (unaffected — the hooks only
  match `Bash`) or drop the dot: `grep -rn "env" templates/wt-setup.sh`.
- The guard tokenizes the whole Bash command, heredocs included. An inline
  `python3 - <<'PY' … PY` script is fine until a line contains an f-string whose `{…}` placeholder
  holds a comma — `print(f"{fn(a, b)}")` reads as brace expansion and is blocked. (Plain
  comprehensions and dict literals are not affected; verified.) Write the script to a file and run
  it, which is better practice here anyway.
- A backtick anywhere in an operand of a file-reading command reads as command substitution, so
  grepping for markdown code spans is blocked: ``grep -c 'Branch `<branch>`' file.md``. Match on a
  backtick-free substring, or use the Grep tool.

The three hook files are **ported from an upstream source** and should stay as close to verbatim as
possible so future syncs stay reviewable — put repo-specific rules in a sibling hook rather than
editing them. `.pre-commit-config.yaml` fences `.claude/hooks/` off from `shfmt` for the same
reason. The `.sh` files must stay executable (`chmod +x`), and they need `python3` (guard) and `jq`
(redaction) on `PATH`; both fail harmlessly when a dependency is missing.

**Deliberate divergences from upstream** — keep this list exhaustive, and re-apply each one after a
sync:

| File | Change | Why |
| - | - | - |
| `redact-secrets.jq` | redacts each **decoded string** via `redact_walk` instead of the JSON serialization (`tojson`/`fromjson`) | Every pattern in the file is written for raw text — `\s` a real newline, `\t` a real tab, `"` a real quote. Run against a serialization they break four ways at once: the value group crosses `\n` and eats following lines (5,001 → 1 observed); `{"KEY": "VALUE"}` and `KEY<tab>=<tab>VALUE` never match, leaking shapeless secrets from config dumps; and a match that stops mid-escape emits invalid JSON, so `fromjson` throws and the fail-open wrapper passes the **unmasked** original through. |
| `redact-secrets.jq` | `\b` on the two `sk-` prefixes **only** | `sk-[A-Za-z0-9_-]{16,}` fires inside ordinary words — `risk-management-dashboard-v2` and `disk-utilization-report-2024` were both mangled in output containing no secret. It is deliberately **not** on the other fifteen: `\b` needs a non-word character before the prefix, so a token concatenated after one (`credential_github_pat_…`, `tokenAKIA…`) stops matching and the secret goes out in the clear. For a redaction filter a false negative is worse than a false positive, so the anchor is only justified where a false positive was actually observed. |
| `redact-secrets.jq` | PEM body limited to base64, whitespace **and the named encrypted-key headers**; `END` label must match `BEGIN` via `\1` | An unrestricted `[\s\S]*?` matches from any `BEGIN` marker to any later `END`, so a `grep -rn 'PRIVATE KEY' .` transcript lost 21 of 24 lines between two unrelated hits. Restricting to base64 alone then dropped **encrypted** keys, whose `Proc-Type:` / `DEK-Info:` headers contain `:` `,` `-` — naming the two headers readmits them without re-opening the body to arbitrary text. The backreference stops `BEGIN RSA` pairing with a later `END EC` and swallowing everything between. |
| `redact-secrets.jq` | key-name value group is a tempered token, `(?:(?!\\n)[^\s"',])+` | Streams carrying `\n` as two characters (`docker inspect`, `kubectl -o json`, `gh api`) were swallowed whole while the physical line count stayed unchanged — invisible to a line-count audit. Refusing only the two-character sequence keeps a lone backslash inside the value, so a secret containing one is masked in full instead of leaking its tail. |

`test.sh` Test 14 asserts all of this behaviourally. It exists because a broken filter and a
healthy one are indistinguishable from outside: emitting nothing on exit 0 is the *designed*
"nothing to redact" signal, so every failure above was silent. Four ThinkVelta repos shipped a
copy that read the wrong input field and therefore never redacted anything at all, for months,
with nothing to show for it.

## Scopes — which file wins

Claude Code merges config from several scopes:

1. `~/.claude/` — your personal global config
2. `.claude/settings.json` (this repo) — project-shared config
3. `.claude/settings.local.json` (this repo) — your personal project overrides
4. CLI flags

Higher numbers override lower. Project-shared config is the right place for rules every session
should follow; personal overrides go in `.local.json`.

## Editing this directory

- Always work in feature branches; never commit `.claude/` changes directly to `main`.
- Skill/hook edits take effect on the next Claude session — restart the conversation after
  changes to be sure.
- Test new rules in a throwaway conversation before relying on them.
- Changing a `wt-*` skill? Mirror it into `templates/` in the same commit (see above).
