# Remediation Required — {{STORY_ID}}: {{STORY_TITLE}}

Your implementation of {{STORY_ID}} has been reviewed by architect and QA reviewers. **Blockers were found that must be fixed before merge.**

Fix only the blockers listed below. Do not address suggestions — those are informational only.

## Story Context (for reference)

**Story**: {{STORY_ID}} — {{STORY_TITLE}}
**Description**: {{STORY_DESCRIPTION}}

### Acceptance Criteria

{{ACCEPTANCE_CRITERIA}}

## Blockers to Fix

### Architect Review Blockers

{{ARCHITECT_BLOCKERS}}

### QA Review Blockers

{{QA_BLOCKERS}}

## Your Workflow

1. **Read each blocker** — Understand the issue and the suggested fix
2. **Fix each blocker** — Make the minimum change needed. Do not refactor unrelated code.
3. **Re-run quality gates**:
   ```bash
   {{QUALITY_GATES}}
   ```
4. **Commit your fixes**:
   ```bash
   git add [specific files]
   git commit -m "fix(scope): address review blockers for {{STORY_ID}}"
   ```
5. **Mark your task as completed** — The lead will re-run reviews on your updated branch

## Critical Rules

1. **Fix only blockers** — Suggestions are not actionable items. Ignore them.
2. **Minimal changes** — Fix exactly what's flagged. Do not take this as an opportunity to refactor.
3. **All quality gates must pass** — Do not mark complete if any gate fails.
4. **Commit on your existing branch** — You are still in your worktree. Do not create new branches.
5. **This is normal** — Review cycles are part of the process. Fix, commit, complete.
