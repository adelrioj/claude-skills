# Fixtures

Reference inputs for sanity-checking `/plan-to-ralph` after upstream changes to `superpowers:writing-plans`.

## Files

### `2026-05-23-sample-superpowers-plan.md`

A synthetic ~120-line plan in the `superpowers:writing-plans` 5.1.0 format. Deliberately exercises every real-world format variation `/plan-to-ralph` must handle.

| Variation                                                | Where in fixture            | Why it's there                                                                 |
| -------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------ |
| `> **For agentic workers:** REQUIRED SUB-SKILL:` callout | Line 3                      | Must be skipped during validation/mapping — it's metadata, not a task          |
| `**Goal:**` / `**Architecture:**` / `**Tech Stack:**`    | Header                      | Source for `findings.md` Architecture Decisions + Resources seeding            |
| `**Spec:**` line in header                               | Header                      | Should auto-suggest as design doc path (Step 1)                                |
| `**Tech Stack:**` as comma-separated prose (not bullets) | Header                      | Splitter must handle prose form (`X, Y, Z for W`)                              |
| `**Files:**` block with `Create:` / `Modify:` / `Test:`  | Task 1, Task 2              | Source for the `notes` field on each story                                     |
| Verification via fenced bash block + `Expected:` line    | Task 1 Steps 2/4, Task 2 Step 4 | Must produce one `acceptanceCriteria` entry per pair                       |
| Verification via literal `Run:` / `Expected:` lines      | Task 2 Step 2               | Template form — must also produce an `acceptanceCriteria` entry                |
| Human-verification step ("Inspect the output")           | Task 3 Step 1               | Must emit as `"[manual] ..."` and flag in review summary, not silently convert |
| Task with no code changes                                | Task 3                      | Should still become a story; `notes` indicates manual verification             |

## How to use

`/plan-to-ralph` is interpreted by Claude at runtime (not a parser), so there's no automated unit test. Use this fixture for **manual regression checks** after editing the skill:

1. From a scratch directory, run:
   ```bash
   mkdir -p /tmp/p2r-check/docs/superpowers/plans
   cp tests/fixtures/2026-05-23-sample-superpowers-plan.md \
      /tmp/p2r-check/docs/superpowers/plans/
   cd /tmp/p2r-check
   ```
2. Invoke `/plan-to-ralph` in Claude Code with this plugin loaded.
3. At the review-summary step (before files are written), confirm:
   - 3 stories produced (one per Task)
   - Each story has ≥ 1 `acceptanceCriteria` entry sourced from a fenced bash block or `Run:` line
   - Task 3's manual step appears as a `"[manual] ..."` criterion AND is called out in the flagged-stories section
   - The design doc prompt suggests `docs/superpowers/specs/2026-05-23-receipt-export-design.md` (from the `**Spec:**` line)
   - `findings.md` Resources section lists `Node.js 20`, `Fastify 4`, `Prisma`, `csv-stringify`, `vitest` (Tech Stack split on commas, trailing `for X` qualifiers stripped)

If any expectation fails, the skill regressed on that variation.

## When to update the fixture

Add a new task/section to the fixture **only** when `superpowers:writing-plans` ships a new format variation we hadn't seen before. Keep the fixture small — its job is to surface format drift, not to be a realistic project.
