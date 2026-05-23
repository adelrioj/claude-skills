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
2. Otherwise, scan for the most recent plan file by date prefix (YYYY-MM-DD), in this order:
   - `docs/superpowers/plans/` (default for `superpowers:writing-plans` ≥ 5.1.0)
   - `docs/plans/` (legacy location, kept for older repos)
   Match `YYYY-MM-DD-*.md` (do NOT match `*-design.md` — design docs are provided separately)
3. If no plan found: **STOP** — `"No implementation plan found. Run /superpowers:writing-plans first."`

Read the plan file. Then check the header for a `**Spec:**` line (5.1.0+ plans may carry one pointing at `docs/superpowers/specs/<slug>-design.md`). Ask:

> Do you have a companion design doc?
> - If the plan's `**Spec:**` line points at `docs/superpowers/specs/<file>`, suggest that path and ask "use this, or override?"
> - Otherwise, prompt for the path or accept Enter to skip.

No silent auto-loading — always confirm with the user.

**Single-file plans:** Plans from `superpowers:writing-plans` 5.1.0+ are self-contained — the header carries `**Goal:**`, `**Architecture:**`, and `**Tech Stack:**` lines that supply the design context. Accept "skip" for the design doc and extract architecture context from the plan header in Step 9.

**Header callout to ignore:** 5.1.0+ plans begin with a blockquote callout starting `> **For agentic workers:** REQUIRED SUB-SKILL:`. This is metadata pointing engineers at `subagent-driven-development` or `executing-plans`; it is **not** a task. Skip it during validation and mapping.

---

## Step 2: Validate the Plan

Verify the plan contains:

- A `**Goal:**` line (5.1.0 header) or `## Goal` section (legacy)
- At least one task heading: `### Task N: [Component Name]` (any heading level). Older plans may also use `## Task N:` — accept either.
- A `**Files:**` block per task with `Create:` / `Modify:` / `Test:` bullets (5.1.0). Older plans may list paths inline (`src/...`, `.github/...`) — accept either.
- Per-step verification: each task contains `- [ ] **Step N:**` checkboxes, with `Run: <command>` + `Expected: <output>` lines on the verification steps (5.1.0). Older plans may have task-level `Run:`/`Expected:` — accept either.

If validation fails, list what's missing and ask if user wants to proceed. **Never invent requirements to fill gaps.**

---

## Step 3: Map Tasks to Stories

**Granularity rule:** One Task = one Ralph user story = one Ralph iteration. The 5 sub-steps inside a 5.1.0 task (Write test → Verify fail → Implement → Verify pass → Commit) all happen **within** that single iteration. Do **not** split sub-steps into separate stories.

For each `Task N:` heading in the plan:

| Plan Element                              | Ralph Story Field    | Mapping Rule                                                    |
| ----------------------------------------- | -------------------- | --------------------------------------------------------------- |
| Task number                               | `id`                 | `US-{NNN}` zero-padded                                          |
| Task name (Component Name)                | `title`              | Verbatim from heading (after the number)                        |
| Task context                              | `description`        | "As a developer, I want..." (20 words max, derived from task)   |
| `Run:` / `Expected:` from sub-steps       | `acceptanceCriteria` | Lift each `Run:` line as a criterion (see below)                |
| Task number                               | `priority`           | Sequential (encodes dependency ordering)                        |
| —                                         | `passes`             | Always `false`                                                  |
| Paths from the `**Files:**` block         | `notes`              | `"Files: Create src/foo.ts, Modify src/bar.ts, Test tests/foo.test.ts. Source: Task N"` |

### Acceptance Criteria from Sub-Steps

5.1.0 tasks carry exact verification commands, but the **format varies in the wild**:

- **Template form** (from `writing-plans` SKILL.md): a literal `Run: <command>` line followed by `Expected: <output>`.
- **Common real-world form**: a fenced ```` ```bash ```` / ```` ```sh ```` / unlabeled fenced block immediately under the step heading, followed by an `Expected: ...` paragraph.

Treat both as equivalent. Extraction rule:

> A "verification pair" is *(command-source, `Expected:` paragraph)* where the command-source is **either** a `Run:` line **or** the first fenced code block under the step heading whose language hint is `bash`, `sh`, or unset.

For each verification pair found, emit one `acceptanceCriteria` entry:

| Verification pair in plan                                                                 | acceptanceCriteria entry                            |
| ----------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `Run: pytest tests/path/test.py -v` + `Expected: PASS`                                    | `"pytest tests/path/test.py -v passes"`             |
| ```` ```\nuv run pytest tests/foo_test.py -v\n``` ```` + `Expected: all 4 tests PASS.`    | `"uv run pytest tests/foo_test.py -v: all 4 tests pass"` |
| `Run: pnpm typecheck` + `Expected: no errors`                                             | `"pnpm typecheck passes"`                           |
| Multi-line bash block (e.g. `cd …; pytest …`)                                             | Use the last meaningful command as the criterion stem; keep the `Expected:` summary as the assertion |
| Step shows a code block only, no `Expected:` paragraph after                              | Skip — it's an implementation step, not verification |

**Human-verification steps:** if the `Expected:` paragraph says "Inspect the output", "If WARN lines appear...", or otherwise requires human judgment, do **not** silently convert it to a machine criterion. Emit it as `acceptanceCriteria` text prefixed with `"[manual] "` (e.g. `"[manual] no WARN lines in spread verifier output"`) and flag it in the review summary (Step 7). Ralph will surface manual criteria in iteration logs rather than auto-pass them.

Older plans may use vague language. For those, rewrite:

| Vague (legacy)                   | Machine-verifiable (for Ralph)                 |
| -------------------------------- | ---------------------------------------------- |
| "Works correctly"                | Remove or replace with specific test assertion |
| "Validate JSON is well-formed"   | `"JSON parses without errors"`                 |
| "Code is clean"                  | `"<lint command> passes"`                      |

If a step lacks both a verification pair and any verifiable criterion, flag it in the review summary (Step 7).

---

## Step 4: TDD Bundling (5.1.0 plans only)

5.1.0+ plans from `superpowers:writing-plans` already bundle TDD **inside** each task as 5 sub-steps (Write test → Verify fail → Implement → Verify pass → Commit). There is nothing to merge — one Ralph iteration runs the whole TDD cycle for one task.

**Only run the legacy detection below on plans that pre-date 5.1.0** — i.e. plans where you see separate top-level tasks like "Task 3: Write test for auth guard" and "Task 4: Implement auth guard".

Legacy detection:

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

The `findings.md` template has an Architecture Decisions section and a Resources section that must be seeded from the plan (and design doc if provided) to give the first Ralph iteration a head start:

**Architecture Decisions table — extract in this order:**

1. If a design doc was provided, extract its key decisions
2. From a 5.1.0 plan header: take the `**Architecture:**` sentence(s) and add as a single row — Decision = the approach in one phrase, Rationale = the "because…" clause if present, else `—`
3. From legacy plans: extract any `## Decisions` table or `## Architecture` section verbatim
4. If none of the above yield content, leave the table empty with a placeholder row: `| (none yet) | — |`

**Resources section — also seed from the plan header:**

- From a 5.1.0 plan header: take the `**Tech Stack:**` line. If it's a bullet list, copy the bullets. If it's a comma-separated prose sentence (common in practice — e.g. `Python 3.13, pandas, numpy, Optuna, statsmodels.stats.multitest.multipletests for BH-FDR`), split on top-level commas and emit one bullet per item, stripping trailing qualifier clauses (`X for Y` → `X`).
- If the plan header has a `**Spec:**` line, add it as a bullet: `- Design spec: <path>`.
- Skip if the header doesn't have a Tech Stack line.

Never invent decisions or stack entries — only extract what the source documents state.

### Show Handoff

```
Converted [M] tasks -> [N] user stories
  tasks/prd.json:      Ralph-compatible PRD
  tasks/progress.txt:  iteration log (initially empty)
  tasks/findings.md:   cross-iteration knowledge (seeded from plan/design)
  Source plan:         [resolved plan path]
  Branch:             [resolved branch name]

Ready to run (resolve ${CLAUDE_PLUGIN_ROOT} to the actual plugin install path before displaying):
  ${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh
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
