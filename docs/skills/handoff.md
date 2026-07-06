# `/handoff`

Compacts the current conversation into a handoff document so a fresh agent can pick up the work. Writes to the OS temp directory (never the workspace), includes a "suggested skills" section, references existing artifacts (PRDs, plans, ADRs, issues, diffs) by path rather than duplicating them, and redacts secrets/PII. Accepts an optional argument describing what the next session will focus on.

## Conventions

- `/handoff` writes only to the OS temp directory and references existing artifacts by path instead of duplicating them
