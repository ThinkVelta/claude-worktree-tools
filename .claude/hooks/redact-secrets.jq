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

# Is this PEM body actually a base64 payload, rather than text that merely
# looks like one? Concatenate the body lines (dropping the RFC 1421 headers of
# an encrypted key) and check the result is real base64: base64 alphabet, legal
# terminal padding, and a total length divisible by 4 — which the base64
# encoding of any byte string always is.
#
# This lives in jq because a regex cannot express it. Validating quartets
# PER LINE, which is the regex-shaped version of the same idea, rejects real
# keys: OpenSSH ed25519 bodies wrap at 70 characters and EC bodies carry
# 27/30/36-character lines, none of them multiples of 4. Wrap width is exactly
# what concatenating removes, so the check here is both stricter and safe.
#
# The length floor is on the CONCATENATED payload, so a key wrapped at a narrow
# width still passes. The smallest real body is an ed25519 PKCS#8 at 48 bytes
# of DER.
#
# Deliberately does NOT decode and inspect for a DER prefix. Only 2 of the 5
# key types openssl and ssh-keygen emit start with DER `0x30`: an encrypted
# body is raw ciphertext (observed `cc 50 6f bb`) and an OpenSSH body begins
# `6f 70 65 6e` — "open", from `openssh-key-v1`. Requiring DER would stop
# masking both, turning over-redaction into disclosure.
def pem_body_ok:
    ( [splits("\r?\n")]
      | map(select(length > 0
                   and ((startswith("Proc-Type:") or startswith("DEK-Info:")) | not)))
      | join("") ) as $b64
    | ($b64 | length) as $n
    | $n >= 40
      and ($n % 4) == 0
      and ($b64 | test("^[A-Za-z0-9+/]+={0,2}$"));

def redact:
    # ── 1. value-shape: tokens recognizable by prefix/shape anywhere ────────
    #
    # `\b` appears on the two sk- rules ONLY, and deliberately nowhere else.
    #
    # It is needed there: `sk-[A-Za-z0-9_-]{16,}` fires inside ordinary words,
    # and "risk-management-dashboard-v2" / "disk-utilization-report-2024" were
    # both mangled in output containing no secret at all.
    #
    # It is harmful everywhere else. `\b` requires a non-word character before
    # the prefix, so a token concatenated after one — `credential_github_pat_…`,
    # `tokenAKIA…` — stops matching and the secret goes out in the clear. For a
    # redaction filter a false negative is worse than a false positive, so the
    # anchor is only justified where a false positive was actually observed.
    # These prefixes are distinctive enough not to need it.
    # AI providers (sk-ant- before generic sk- so it isn't shadowed)
    gsub("\\bsk-ant-[A-Za-z0-9_-]{16,}"; "sk-ant-[REDACTED]")             # Anthropic API key
  | gsub("\\bsk-[A-Za-z0-9_-]{16,}"; "sk-[REDACTED]")                     # OpenAI API key (incl. sk-proj-)
    # Supabase
  | gsub("sbp_[A-Za-z0-9]{20,}"; "sbp_[REDACTED]")                     # Supabase access token
  | gsub("sb_secret_[A-Za-z0-9_-]{8,}"; "sb_secret_[REDACTED]")        # Supabase secret key (new format)
  | gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"; "[REDACTED-JWT]")  # JWT (Supabase anon/service keys)
    # Sentry
  | gsub("sntrys_[A-Za-z0-9_-]{8,}"; "sntrys_[REDACTED]")              # Sentry auth token
    # Git hosts
  | gsub("github_pat_[A-Za-z0-9_]{20,}"; "github_pat_[REDACTED]")      # GitHub fine-grained PAT
  | gsub("gh[oprsu]_[A-Za-z0-9]{20,}"; "gh_[REDACTED]")                # GitHub classic PAT/OAuth/server/user/refresh
  | gsub("glpat-[A-Za-z0-9_-]{20,}"; "glpat-[REDACTED]")               # GitLab PAT
    # Payments
  | gsub("(sk|rk)_(live|test)_[A-Za-z0-9]{16,}"; "[REDACTED-STRIPE-KEY]")  # Stripe secret/restricted key
    # Cloud / SaaS
  | gsub("A(KIA|SIA)[0-9A-Z]{16}"; "[REDACTED-AWS-KEY]")               # AWS access key id (incl. temporary ASIA)
  | gsub("AIza[0-9A-Za-z_-]{35}"; "[REDACTED-GOOGLE-KEY]")             # Google API key
  | gsub("ya29\\.[0-9A-Za-z_-]{20,}"; "[REDACTED-GOOGLE-OAUTH]")       # Google OAuth access token
  | gsub("xox[baprs]-[A-Za-z0-9-]{10,}"; "[REDACTED-SLACK-TOKEN]")     # Slack token (bot/user/app/refresh)
  | gsub("xapp-[A-Za-z0-9-]{10,}"; "[REDACTED-SLACK-TOKEN]")           # Slack app-level token
  | gsub("SG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}"; "[REDACTED-SENDGRID-KEY]")  # SendGrid
  | gsub("npm_[A-Za-z0-9]{36}"; "npm_[REDACTED]")                      # npm token
    # PEM private-key blocks (multi-line). Two layers, because no single one was
    # enough — each earlier attempt failed differently:
    #   * `[\s\S]*?` matches from ANY BEGIN marker to ANY later END marker — on
    #     a `grep -rn 'PRIVATE KEY' .` transcript that deleted 21 of 24 lines of
    #     ordinary output between two unrelated hits;
    #   * a base64-only CHARACTER CLASS drops encrypted keys, whose
    #     `Proc-Type:` / `DEK-Info:` headers contain `:` `,` `-`. Naming the two
    #     headers readmits them without re-opening the body to arbitrary text;
    #   * a character class of any kind is still too weak, because letters and
    #     spaces both belong to it — so ordinary prose between two same-labelled
    #     markers was still swallowed. Requiring whole LINES to be base64 (which
    #     excludes the space) closes that, but not a body whose every line is a
    #     single word: `hello` is valid base64 alphabet too.
    #
    # So the regex decides only the SHAPE — matching labels, plausible lines —
    # and `pem_body_ok` decides whether the payload is really base64. The line
    # validation stays in the regex even though jq revalidates: it lets the regex
    # backtrack to a farther END when a nearer one yields an invalid body, so a
    # real key following a stray marker is still masked. `\k<lbl>` forces the END
    # label to match BEGIN, so `BEGIN RSA` cannot pair with a later `END EC`.
    # `\r?` tolerates CRLF. A block that fails validation is returned via `.all`,
    # byte for byte.
  | gsub("(?<all>-----BEGIN(?<lbl>[A-Z ]*)PRIVATE KEY-----\\r?\\n(?<body>(?:(?:[A-Za-z0-9+/=]+|(?:Proc-Type|DEK-Info):[^\\n]*)?\\r?\\n)*?)-----END\\k<lbl>PRIVATE KEY-----)";
         if (.body | pem_body_ok) then "[REDACTED-PRIVATE-KEY]" else .all end)
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
