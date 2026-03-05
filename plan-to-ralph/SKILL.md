---
name: plan-to-ralph
description: 'Use when converting a Superpowers implementation plan into Ralph prd.json format for autonomous execution. Triggers on: convert plan to ralph, plan to prd.json, ralph from plan, convert superpowers plan.'
user-invocable: true
---

# Plan-to-Ralph Converter

Convert a Superpowers implementation plan into Ralph's prd.json format with pre-seeded cross-iteration context.

The plan is the **source of truth**. Do NOT re-interview the user or regenerate requirements.

---

## The Job

1. Locate and validate the implementation plan
2. Accept optional design doc for architecture context
3. Map plan tasks to Ralph user stories
4. Detect TDD pairs and suggest merges
5. Validate story sizes
6. Inject quality gates into every story
7. Present review summary for user approval
8. Resolve branch name
9. Write files and show handoff message

**Output files:**

- `tasks/prd.json` — Ralph-compatible PRD
- `tasks/progress.txt` — Empty iteration log for Ralph to append to
- `tasks/findings.md` — Cross-iteration knowledge file seeded with architecture context

**Do NOT** run Ralph. The user reviews prd.json first.

---

## Step 1: Locate the Plan

1. If the user provided a file path as argument, use it
2. Otherwise, scan `docs/plans/` for the most recent plan file by date prefix (YYYY-MM-DD). Match any of: `*-plan.md`, `*-implementation.md` (do NOT match `*-design.md` — design docs are provided separately)
3. If no plan found: **STOP** — `"No implementation plan found. Run /superpowers:writing-plans first."`

Read the plan file. Then ask:

> Do you have a companion design doc? Provide the path, or press Enter to skip.

No auto-detection. The user explicitly provides the design doc path.

**Single-file plans:** If the plan itself contains architecture decisions (e.g., a `## Decisions` table or `## Architecture` section), it doubles as its own design doc. In this case, accept "skip" for the design doc and extract architecture context directly from the plan file in Step 9.

---

## Step 2: Validate the Plan

Verify the plan contains:

- A `**Goal:**` line or `## Goal` section
- At least one numbered section heading: `## Task N:`, `## Component N:`, `## Step N:`, or `## Phase N:` (any heading level, any of these labels)
- File paths in tasks (`Create:`, `Modify:`, `Test:`, `**File:**`, or paths like `src/...`, `.github/...`)
- Verification steps — either per-task (`Run:`, `Expected:`, or test/lint commands) OR a global `## Testing Strategy` / `## Testing` / `## Verification` section

If verification steps are global rather than per-task, distribute them to relevant stories during mapping (Step 3).

If validation fails, list what's missing and ask if user wants to proceed. **Never invent requirements to fill gaps.**

---

## Step 3: Map Tasks to Stories

For each numbered section in the plan (`## Task N:`, `## Component N:`, `## Step N:`, or `## Phase N:`):

| Plan Element       | Ralph Story Field    | Mapping Rule                                                    |
| ------------------ | -------------------- | --------------------------------------------------------------- |
| Section number     | `id`                 | `US-{NNN}` zero-padded                                          |
| Section name       | `title`              | Verbatim from heading (after the number)                        |
| Section context    | `description`        | "As a developer, I want..." (20 words max, derived from task)   |
| Verification steps | `acceptanceCriteria` | Rewrite as machine-verifiable checks (see below)                |
| Section number     | `priority`           | Sequential after any merges (encodes dependency ordering)       |
| —                  | `passes`             | Always `false`                                                  |
| File paths         | `notes`              | `"Files: Create src/foo.ts, Modify src/bar.ts. Source: Task N"` |

**Global verification distribution:** If the plan has a global testing section instead of per-task verification, map each test scenario to the most relevant story. Tests that span multiple stories go on the last story in the dependency chain.

### Machine-Verifiable Acceptance Criteria

Every criterion must be checkable by running a command or inspecting output:

| Vague (from plan)                | Machine-verifiable (for Ralph)                 |
| -------------------------------- | ---------------------------------------------- |
| "Works correctly"                | Remove or replace with specific test assertion |
| `Run: pnpm test; Expected: PASS` | `"pnpm test passes"`                           |
| "Validate JSON is well-formed"   | `"JSON parses without errors"`                 |
| "Code is clean"                  | `"pnpm lint passes"`                           |

If vague criteria can't be made verifiable, flag them in the review summary (Step 7).

---

## Step 4: Detect TDD Pairs

Scan adjacent tasks for TDD patterns:

- Task N contains "write failing test" / "write test" / "add test"
- Task N+1 contains "implement" / "make test pass" / "write minimal code"

**Do NOT auto-merge.** Flag as suggestions for the review summary:

```
TDD pairs detected (suggest merging):
  Tasks 3+4 -> "Auth guard" (test + implementation)
  Tasks 7+8 -> "Webhook validation" (test + implementation)
```

If user approves a merge:

- Title uses the implementation task's component name
- Acceptance criteria combine both test expectations and implementation verification
- Priority numbers recalculated to stay sequential

---

## Step 5: Validate Story Sizes

After mapping (and any merges), check each story:

- **Too small:** 1 acceptance criterion AND touches 1 file — suggest merge with adjacent story sharing same component
- **Too big:** >8 acceptance criteria OR touches >5 files — suggest split
- **Rule of thumb:** If you can't describe the change in 2-3 sentences, it's too big for one Ralph iteration

Flag in review summary. User decides whether to merge/split.

---

## Step 6: Inject Quality Gates

Auto-detect project quality tooling:

| File             | Check for                           | Inject                                         |
| ---------------- | ----------------------------------- | ---------------------------------------------- |
| `package.json`   | `typecheck`, `lint`, `test` scripts | `"pnpm typecheck passes"`, etc.                |
| `Makefile`       | `test`, `lint`, `typecheck` targets | `"make typecheck passes"`, etc.                |
| `pyproject.toml` | `pytest`, `ruff`, `mypy`            | `"pytest passes"`, etc.                        |
| `Cargo.toml`     | —                                   | `"cargo test passes"`, `"cargo clippy passes"` |

Append detected quality gates to **every** story's acceptance criteria.

Additionally, write the detected commands to the top-level `qualityGates` array in `prd.json` (e.g., `["pnpm typecheck", "pnpm lint", "pnpm test"]`). Ralph reads this array at runtime to know which commands to execute — **it does not hardcode any quality gate commands**.

**Why per-story AND top-level:** Acceptance criteria tell Ralph what "done" looks like for each story. The top-level `qualityGates` array tells Ralph exactly which shell commands to run. Both are needed — criteria for verification, commands for execution.

If no tooling detected, ask: `"What commands must pass for every story?"`

### E2E Command Detection

Also check for an E2E test command (used only by `/swarm-execute` at final validation, not per-story):

| File             | Check for                            | Write to prd.json               |
| ---------------- | ------------------------------------ | ------------------------------- |
| `package.json`   | `test:e2e` script                    | `"e2eCommand": "pnpm test:e2e"` |
| `Makefile`       | `test-e2e` or `e2e` target           | `"e2eCommand": "make e2e"`      |
| `pyproject.toml` | `e2e` or `playwright` in test config | `"e2eCommand": "..."`           |

If no E2E command detected, **omit** the `e2eCommand` field from `prd.json` entirely (do not set it to null or empty string).

---

## Step 7: Present Review Summary

Before writing any files, present:

```
Plan-to-Ralph Conversion Summary
---------------------------------
Source plan: [path]
Design doc: [path or "not provided"]
Branch: [resolved branch name]

Stories: N (from M tasks)
Quality gates: [detected commands]

TDD pairs detected (suggest merging):
  [Tasks N+M -> "Component" (test + implementation)]

Flagged stories:
  [US-NNN - reason. Suggestion.]

Output files:
  tasks/prd.json      -> Ralph-compatible PRD
  tasks/progress.txt  -> iteration log (initially empty)
  tasks/findings.md   -> cross-iteration knowledge (seeded from plan/design)

Approve? [Y/adjust/cancel]
```

- **Y**: Write all files
- **adjust**: Ask which stories to modify, apply changes, re-present
- **cancel**: Abort without writing

---

## Step 8: Resolve Branch Name

Determine `branchName` in order:

1. If the user provided a branch name argument, use it
2. If the current git branch is not `main`/`master`, use the current branch
3. Otherwise, ask: `"What branch should Ralph work on?"`

Do not invent `ralph/` prefixed branches.

---

## Step 9: Write Files & Handoff

First, ensure the output directory exists: `mkdir -p tasks`

### Templates

Read the templates from this skill's `templates/` directory and populate them with values from the plan and design doc:

| Template                 | Output               | Placeholders                                           |
| ------------------------ | -------------------- | ------------------------------------------------------ |
| `templates/prd.json`     | `tasks/prd.json`     | Project name, branch, quality gates, stories from plan |
| `templates/progress.txt` | `tasks/progress.txt` | Feature name, plan path, design doc path, date         |
| `templates/findings.md`  | `tasks/findings.md`  | Architecture decisions from plan/design doc            |

Replace all `{{PLACEHOLDER}}` values with content derived from the plan and design doc. One user story per plan task — repeat the story object in `userStories` array for each task.

### Seeding findings.md

The `findings.md` template has an Architecture Decisions section that must be seeded from the plan and/or design doc to give the first Ralph iteration a head start:

- If a design doc was provided, extract its key decisions into the Architecture Decisions table
- If the plan contains a `## Decisions` table or architectural notes, extract those
- If neither has extractable decisions, leave the table empty with a placeholder row: `| (none yet) | — |`
- Never invent decisions — only extract what the source documents state

### Show Handoff

```
Converted [M] tasks -> [N] user stories
  tasks/prd.json:      Ralph-compatible PRD
  tasks/progress.txt:  iteration log (initially empty)
  tasks/findings.md:   cross-iteration knowledge (seeded from plan/design)
  Source plan:         docs/plans/[file]
  Branch:             [resolved branch name]

Ready to run:
  .claude/skills/plan-to-ralph/scripts/ralph.sh
```

---

## Checklist Before Writing

- [ ] Plan validated (Goal + tasks + file paths + verification steps)
- [ ] All criteria are machine-verifiable (no vague language)
- [ ] Quality gates appended to every story
- [ ] TDD pair suggestions shown to user
- [ ] Story sizes validated (none too small or too big without flagging)
- [ ] User approved the review summary
- [ ] Branch name resolved (not invented)
- [ ] tasks/progress.txt created with iteration log header
- [ ] tasks/findings.md created and seeded with architecture decisions from plan/design doc
