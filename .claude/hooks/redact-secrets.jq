# Secret-redaction filter for the PostToolUse(Bash) hook.
#
# Reads the hook payload on stdin and masks secrets in `.tool_response` (the
# PostToolUse field carrying the tool result) before the model and the
# transcript ever see it. Emits the `updatedToolOutput` wrapper ONLY when
# something was actually redacted; otherwise emits nothing (`empty`), so the
# unmodified output passes through untouched (zero churn on the common
# no-secret case).
#
# Two complementary passes:
#   1. value-shape — mask a secret by its recognizable prefix/shape ANYWHERE it
#      appears (so it's caught even when used bare, e.g. in a URL or a CLI flag).
#   2. key-name    — mask the value after a known sensitive KEY in `KEY=VALUE` /
#      `KEY: VALUE` / `"KEY": "VALUE"` form. This catches SHAPELESS secrets
#      (RAILWAY_TOKEN, AUTH_SECRET, …) in the dominant leak vector: env / .env /
#      `printenv` / `export` / config dumps, where key and value appear together.
#
# Edit the patterns below to add/remove tokens and sensitive key names.
#
# ── READ THIS BEFORE CHANGING THE PLUMBING AT THE BOTTOM ────────────────────
# Every pattern here is written for RAW TEXT: `\s` means a real newline, `\t` a
# real tab, `"` a real quote. Applying them to a JSON *serialization* (`tojson`
# / `tostring` on the response object) silently breaks four of them at once,
# because in that form a newline is the two characters `\` and `n`, a tab is
# `\` and `t`, and a quote is `\` and `"`:
#
#   * the key-name value group stops at no newline, so one match eats every
#     following line — a 5,001-line output collapsed to a single line, 99.99%
#     of it deleted;
#   * `{"KEY": "VALUE"}` never matches, so shapeless secrets leak from config
#     dumps;
#   * `KEY<tab>=<tab>VALUE` never matches, same leak;
#   * a match that stops mid-escape emits invalid JSON, `fromjson` throws, and
#     the wrapper's fail-open design passes the ORIGINAL through — the whole
#     secret, unmasked.
#
# So: walk the structure and redact each decoded string. Do not reintroduce
# tojson/tostring.
# ───────────────────────────────────────────────────────────────────────────

def redact:
    # ── 1. value-shape: tokens recognizable by prefix/shape anywhere ────────
    # `\b` on every prefix: without it `sk-[A-Za-z0-9_-]{16,}` fires inside
    # ordinary words — "risk-management-dashboard-v2" and
    # "disk-utilization-report-2024" both became "…sk-[REDACTED]", mangling
    # output containing no secret at all.
    # AI providers (sk-ant- before generic sk- so it isn't shadowed)
    gsub("\\bsk-ant-[A-Za-z0-9_-]{16,}"; "sk-ant-[REDACTED]")             # Anthropic API key
  | gsub("\\bsk-[A-Za-z0-9_-]{16,}"; "sk-[REDACTED]")                     # OpenAI API key (incl. sk-proj-)
    # Supabase
  | gsub("\\bsbp_[A-Za-z0-9]{20,}"; "sbp_[REDACTED]")                     # Supabase access token
  | gsub("\\bsb_secret_[A-Za-z0-9_-]{8,}"; "sb_secret_[REDACTED]")        # Supabase secret key (new format)
  | gsub("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"; "[REDACTED-JWT]")  # JWT (Supabase anon/service keys)
    # Sentry
  | gsub("\\bsntrys_[A-Za-z0-9_-]{8,}"; "sntrys_[REDACTED]")              # Sentry auth token
    # Git hosts
  | gsub("\\bgithub_pat_[A-Za-z0-9_]{20,}"; "github_pat_[REDACTED]")      # GitHub fine-grained PAT
  | gsub("\\bgh[oprsu]_[A-Za-z0-9]{20,}"; "gh_[REDACTED]")                # GitHub classic PAT/OAuth/server/user/refresh
  | gsub("\\bglpat-[A-Za-z0-9_-]{20,}"; "glpat-[REDACTED]")               # GitLab PAT
    # Payments
  | gsub("\\b(sk|rk)_(live|test)_[A-Za-z0-9]{16,}"; "[REDACTED-STRIPE-KEY]")  # Stripe secret/restricted key
    # Cloud / SaaS
  | gsub("\\bA(KIA|SIA)[0-9A-Z]{16}"; "[REDACTED-AWS-KEY]")               # AWS access key id (incl. temporary ASIA)
  | gsub("\\bAIza[0-9A-Za-z_-]{35}"; "[REDACTED-GOOGLE-KEY]")             # Google API key
  | gsub("\\bya29\\.[0-9A-Za-z_-]{20,}"; "[REDACTED-GOOGLE-OAUTH]")       # Google OAuth access token
  | gsub("\\bxox[baprs]-[A-Za-z0-9-]{10,}"; "[REDACTED-SLACK-TOKEN]")     # Slack token (bot/user/app/refresh)
  | gsub("\\bxapp-[A-Za-z0-9-]{10,}"; "[REDACTED-SLACK-TOKEN]")           # Slack app-level token
  | gsub("\\bSG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}"; "[REDACTED-SENDGRID-KEY]")  # SendGrid
  | gsub("\\bnpm_[A-Za-z0-9]{36}"; "npm_[REDACTED]")                      # npm token
    # PEM private-key blocks (multi-line). Three constraints, each earning its
    # keep:
    #   * body limited to base64 + whitespace, because an unrestricted
    #     `[\s\S]*?` matches from ANY BEGIN marker to ANY later END marker — on
    #     a `grep -rn 'PRIVATE KEY' .` transcript that deleted 21 of 24 lines of
    #     ordinary output between two unrelated hits;
    #   * plus the two RFC 1421 header lines by name. Encrypted keys carry
    #     `Proc-Type:` and `DEK-Info:`, whose `:` `,` `-` are not base64, so a
    #     base64-only body silently stops redacting exactly the keys someone
    #     bothered to encrypt. Naming the two headers admits them without
    #     re-opening the body to arbitrary text;
    #   * END label must match BEGIN (`\1`), so `BEGIN RSA` cannot pair with a
    #     later `END EC` and swallow everything between.
  | gsub("-----BEGIN([A-Z ]*)PRIVATE KEY-----(?:[A-Za-z0-9+/=[:space:]]|(?:Proc-Type|DEK-Info):[^\\n]*)*?-----END\\1PRIVATE KEY-----"; "[REDACTED-PRIVATE-KEY]")
    # URLs / connection strings
  | gsub("(?<pre>[a-zA-Z][a-zA-Z0-9+.-]*://[^/@\\s:]+:)[^/@\\s]+@"; "\(.pre)[REDACTED]@")  # inline credentials (scheme://user:PASSWORD@)
    # ── 2. key-name: value after a known sensitive key ──────────────────────
    # Matches KEY<quote?><:|=><quote?>VALUE and keeps the key+separator, masking
    # the value. [ \t] only (not \s) so it never spans newlines.
    #
    # The value group is a tempered token: it excludes whitespace/quote/comma as
    # before, and additionally refuses to cross a literal backslash-n. Streams
    # that carry `\n` as two characters — `docker inspect`, `kubectl -o json`,
    # `gh api`, `terraform output -json`, or a .env storing a PEM as
    # `KEY="...\n..."` — would otherwise be swallowed whole while the physical
    # line count stayed unchanged, so a line-count audit would score it clean.
    # `(?!\\n)` stops exactly there while still allowing a lone backslash, so a
    # secret containing one is masked in full rather than leaking its tail.
    #
    # KNOWN GAP, deliberate: a key at end-of-line with its value on the NEXT
    # line (YAML block style) is not matched — masking arbitrary following lines
    # would over-redact far more than it protects. Shapeless secrets in that
    # form pass through; keep them out of tool output.
  | gsub("(?<k>RAILWAY_TOKEN|AUTH_SECRET|SUPABASE_SERVICE_KEY|SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY|SUPABASE_AUTH_KEY|SUPABASE_DB_PASSWORD|SENTRY_AUTH_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|DATABASE_URL|POSTGRES_URL|DB_PASSWORD|DATABASE_PASSWORD|STRIPE_SECRET_KEY|GITHUB_TOKEN|GH_TOKEN|NPM_TOKEN|GOOGLE_API_KEY|SENDGRID_API_KEY)(?<s>[\"']?[ \\t]*[:=][ \\t]*[\"']?)(?<v>(?:(?!\\\\n)[^\\s\"',])+)";
          "\(.k)\(.s)[REDACTED]");

# Walk the response and redact each DECODED string, rather than serializing the
# whole object and running the patterns over the JSON text. See the header: the
# serialized form breaks four patterns at once, one of them by failing open and
# disclosing the secret in full. Walking also preserves the tool's output shape,
# which Claude Code validates `updatedToolOutput` against.
def redact_walk:
    if type == "string" then redact
    elif type == "object" then with_entries(.value |= redact_walk)
    elif type == "array" then map(redact_walk)
    else . end;

.tool_response as $original
| ($original | redact_walk) as $redacted
| if $redacted == $original then empty
  else { hookSpecificOutput: { hookEventName: "PostToolUse",
                               updatedToolOutput: $redacted } }
  end
