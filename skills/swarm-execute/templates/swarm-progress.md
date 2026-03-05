# Swarm Progress Entry Template

Use this template when appending batch-level progress to `tasks/progress.txt` after merging each batch.

---

## Template

```markdown
### [YYYY-MM-DD HH:MM] Batch {{BATCH_NUMBER}} — {{EXECUTION_MODE}}

**Stories in batch**: {{STORY_LIST}}
**Teammates**: {{TEAMMATE_COUNT}} concurrent
**Execution mode**: parallel (Agent Teams swarm)

| Story        | Title           | Status     | Review     | Merge Order     | Teammate          |
| ------------ | --------------- | ---------- | ---------- | --------------- | ----------------- |
| {{STORY_ID}} | {{STORY_TITLE}} | {{STATUS}} | {{REVIEW}} | {{MERGE_ORDER}} | {{TEAMMATE_NAME}} |

**Merge sequence** (by priority):
{{MERGE_SEQUENCE}}

**Post-merge quality gates**: {{QUALITY_GATE_RESULT}}

#### Aggregated Findings

{{AGGREGATED_FINDINGS}}

#### Errors (if any)

| Story        | Error             | Resolution     |
| ------------ | ----------------- | -------------- |
| {{STORY_ID}} | {{ERROR_MESSAGE}} | {{RESOLUTION}} |
```

---

## Placeholder Reference

| Placeholder               | Value                                | Example                                                              |
| ------------------------- | ------------------------------------ | -------------------------------------------------------------------- |
| `{{BATCH_NUMBER}}`        | Sequential batch number              | `1`                                                                  |
| `{{EXECUTION_MODE}}`      | `parallel` or `sequential`           | `parallel (2 teammates)`                                             |
| `{{STORY_LIST}}`          | Comma-separated story IDs            | `US-001, US-005`                                                     |
| `{{TEAMMATE_COUNT}}`      | Number of concurrent teammates       | `2`                                                                  |
| `{{STORY_ID}}`            | Story identifier                     | `US-001`                                                             |
| `{{STORY_TITLE}}`         | Story title from prd.json            | `Core API key scoping`                                               |
| `{{STATUS}}`              | `completed` or `failed` or `blocked` | `completed`                                                          |
| `{{MERGE_ORDER}}`         | Order merged (by priority)           | `1st`                                                                |
| `{{REVIEW}}`              | Review gate result                   | `pass`, `pass after fix (2 blockers fixed)`, `overridden`, `skipped` |
| `{{TEAMMATE_NAME}}`       | Worktree/teammate identifier         | `worker-us-001`                                                      |
| `{{MERGE_SEQUENCE}}`      | Ordered list of merges               | `1. US-001 (P1) ✓  2. US-005 (P5) ✓`                                 |
| `{{QUALITY_GATE_RESULT}}` | `✓ all passing` or failure details   | `✓ all passing`                                                      |
| `{{AGGREGATED_FINDINGS}}` | Combined findings from all teammates | Architecture decisions, patterns, etc.                               |
| `{{ERROR_MESSAGE}}`       | Specific error from a teammate       | `Type error in payment.service.ts:42`                                |
| `{{RESOLUTION}}`          | How the error was resolved           | `Fixed return type to match interface`                               |

---

## Example Entry

```markdown
### 2026-02-22 14:30 Batch 1 — parallel (2 teammates)

**Stories in batch**: US-001, US-005
**Teammates**: 2 concurrent
**Execution mode**: parallel (Agent Teams swarm)

| Story  | Title                    | Status    | Review | Merge Order | Teammate      |
| ------ | ------------------------ | --------- | ------ | ----------- | ------------- |
| US-001 | Core API key scoping     | completed | pass   | 1st         | worker-us-001 |
| US-005 | Admin key scope overview | completed | pass   | 2nd         | worker-us-005 |

**Merge sequence** (by priority):

1. US-001 (P1) ✓ — merged cleanly
2. US-005 (P5) ✓ — merged cleanly

**Post-merge quality gates**: ✓ all passing

#### Aggregated Findings

- Architecture: Used NestJS SetMetadata for scope decorators (consistent with existing auth pattern)
- Pattern: All guards in this project extend AuthGuard('jwt') — follow this for new guards
- Pattern: Admin endpoints use separate guard chain from client endpoints

#### Errors (if any)

| Story  | Error                                  | Resolution                           |
| ------ | -------------------------------------- | ------------------------------------ |
| US-001 | Circular dependency in scopes.guard.ts | Used forwardRef() to break the cycle |
```
