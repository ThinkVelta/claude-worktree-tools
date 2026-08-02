---
description: General coding rules for the entire repository
---

# General Rules

- Use Conventional Commits for all commit messages: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`
- Always work in feature branches (`feature/...`), never commit directly to `main`
- Keep changes focused — one feature or fix per branch
- Write clear commit messages that explain WHY, not just WHAT
- Use `/commit` skill for staging and committing changes. It never pushes.
- **Push only your own feature branch, and only with an explicit refspec**
  (`git push -u origin HEAD:refs/heads/<feature-branch>`). The `/pr-open`, `/pr-iterate` and
  `/pr-babysit` skills are the only ones that push, once each. Bare `git push`, force pushes,
  pushes to `main`, and `gh pr merge` are blocked by a PreToolUse hook — merging is the human's call.
- **Never run `rm -rf`** — instead, tell the user which directory/files to remove and let them do it manually.
- **Never use compound `cd X && command` in Bash calls.** Always run commands directly from the target directory. Use `git -C <path>` for git commands, or set the working directory before running. This avoids permission prompts triggered by `cd && git` compound commands.
