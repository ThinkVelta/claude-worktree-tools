---
description: templates/ is the shipped deliverable — it lands verbatim in other people's repos.
paths:
  - "templates/**"
  - ".claude/skills/wt-**"
---

Everything under `templates/` is copied **verbatim** by `bin/init.js` into a user's repo.

- Write for a stranger's repo: no paths, branch names, or assumptions from this repository.
- `templates/skills/wt-*/SKILL.md` and `.claude/skills/wt-*/SKILL.md` must stay byte-identical.
  Change one, mirror the other **in the same commit**, and verify with `diff -q`. `test.sh`
  asserts this, so a half-mirrored change turns the suite red.
- Keep `templates/wt-setup.sh`'s four sections intact — generic (do not edit), repo-specific port
  config, repo-specific install, user extras. `/wt-adopt` fills the middle two by matching the
  section banners; renaming or reordering them breaks it.
- Skill frontmatter is a contract: `name`, `description`, `model`, `allowed-tools`,
  `argument-hint`. `description` is the routing signal — keep the trigger phrasing.
- Any change to installed files or CLI flags updates `README.md` and `CLAUDE.md` in the same commit.
