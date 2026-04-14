---
name: pr-iterate
description: Address the latest review feedback on the current branch's open PR. Fetches comments, triages relevance, implements fixes or replies with reasoning, then commits.
metadata:
  context: fork
  agent: pr-iterate
  allowed_tools:
    - Bash
    - Read
    - Write
    - Edit
    - Glob
    - Grep
---

Iterate on the open pull request for the current branch.

Fetches the latest review feedback, evaluates each item, implements relevant fixes, comments on items that are not applicable, validates everything, and commits the result. The user handles pushing.

You should use the `/pr-iterate` agent to perform this task, as it is designed to handle the entire
process of iterating on a pull request based on review feedback.
