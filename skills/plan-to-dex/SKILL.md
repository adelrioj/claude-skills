---
name: plan-to-dex
description: 'Use when running an already-hardened Superpowers implementation plan through the dex orchestrator (codex backend) instead of the Ralph loop. Triggers on: convert plan to dex, plan to dex, dex from plan, run plan with dex, plan-to-dex.'
user-invocable: true
---

# Plan-to-Dex Runner

Translate a Superpowers implementation plan into a [dex](https://github.com/francescoalemanno/dex)-compatible `plan.md`, import it, and run dex's autonomous loop (`apply` → `review`) end to end with **codex** as the fixed backend.

The plan is the **source of truth**. Do NOT re-interview the user, regenerate requirements, or let dex re-plan via `dex plan`.

**Backend is fixed to codex** (`--cli codex`): the skill never asks which backend, never sets `--model`, and never writes `.dex/config.json`. The model is whatever the user's codex install defaults to.

---

## The Job

1. Locate and validate the implementation plan
2. Translate plan tasks into a dex checkbox-group `plan.md`
3. Preflight (dex + codex on PATH; branch guard)
4. One confirmation before the autonomous chain
5. Run `dex import` → `dex apply --cli codex` → `dex review --cli codex`
6. Show the handoff report

**Output file:** `tasks/dex-plan.md` — the translated plan, then installed by `dex import` into `.dex/plan.md`.

---

## Step 1: Locate the Plan

1. If the user provided a file path as argument, use it.
2. Otherwise, scan for the most recent plan file by date prefix (`YYYY-MM-DD`), in this order:
   - `docs/superpowers/plans/` (default for `superpowers:writing-plans` ≥ 5.1.0)
   - `docs/plans/` (legacy location)
   Match `YYYY-MM-DD-*.md` (do NOT match `*-design.md` — those are design docs).
3. If no plan found: **STOP** — "No implementation plan found. Run /superpowers:writing-plans first."

Read the plan file. 5.1.0+ plans are self-contained — the header carries `**Goal:**`, `**Architecture:**`, and `**Tech Stack:**`. A companion design doc is optional and not required here.

**Header callout to ignore:** 5.1.0+ plans begin with a blockquote `> **For agentic workers:** REQUIRED SUB-SKILL:`. It is metadata, not a task — skip it.

## Step 2: Validate the Plan

Verify the plan contains:

- A `**Goal:**` line (5.1.0 header) or `## Goal` section (legacy)
- At least one task heading: `### Task N: [Component Name]` (accept `## Task N:` too)
- A `**Files:**` block per task with `Create:` / `Modify:` / `Test:` bullets (older plans may list paths inline — accept either)
- Per-step verification: `- [ ] **Step N:**` checkboxes with `Run:`/`Expected:` lines, OR a fenced bash block followed by an `Expected:` paragraph

If validation fails, list what is missing and ask whether to proceed. **Never invent requirements to fill gaps.**

## Step 3: Translate to dex plan.md

Read the template at `${CLAUDE_PLUGIN_ROOT}/skills/plan-to-dex/templates/dex-plan.md` and write the result to `tasks/dex-plan.md` (`mkdir -p tasks` first).

**Granularity rule:** one source `### Task N: Component` = one dex `### Task N: Component` heading = **one dex iteration**. dex hands the entire group body (heading + checkboxes + prose) to codex at once. The 5 TDD sub-steps inside a task become **checkboxes under that heading** — never separate headings.

For each source Task, emit one group following this mapping:

| Source plan element            | → dex `plan.md`                                            |
| ------------------------------ | --------------------------------------------------------- |
| `### Task N: Component` heading  | `### Task N: Component` heading (one group = one iteration) |
| TDD sub-steps (test→fail→impl→pass→commit) | `- [ ]` checkboxes under that heading            |
| `**Files:**` block               | preserved as a `**Files:**` prose line (codex context)    |
| `Run:` / `Expected:` lines       | folded into the relevant checkbox text                    |
| Detected quality gates           | a `- [ ] Quality gates: <cmds> pass` checkbox per task    |
| `[manual]` verification step     | `- [ ] [manual] ...` checkbox, surfaced in the confirmation |
| Plan `**Goal:**`                 | the `## Overview` context group (no checkbox)             |

Example of one emitted group:

```markdown
### Task 3: Auth guard

**Files:** Create `src/auth/guard.ts`, Modify `src/router.ts`, Test `tests/auth/guard.test.ts`

- [ ] Write failing test in `tests/auth/guard.test.ts` — `pnpm test tests/auth/guard.test.ts` should FAIL
- [ ] Implement guard in `src/auth/guard.ts` so the test passes
- [ ] Verify `pnpm test tests/auth/guard.test.ts` PASSES
- [ ] Quality gates: `pnpm typecheck` and `pnpm lint` pass
- [ ] Commit
```

### Quality-gate detection

Detect project quality tooling and append a `Quality gates:` checkbox to **every** task:

| File             | Check for                           | Quality-gate commands              |
| ---------------- | ----------------------------------- | ---------------------------------- |
| `package.json`   | `typecheck`, `lint`, `test` scripts | `pnpm typecheck`, `pnpm lint`, …   |
| `Makefile`       | `test`, `lint`, `typecheck` targets | `make typecheck`, …                |
| `pyproject.toml` | `pytest`, `ruff`, `mypy`            | `pytest`, `ruff check`, …          |
| `Cargo.toml`     | —                                   | `cargo test`, `cargo clippy`       |

If no tooling is detected, ask: "What commands must pass for every task?" Unlike `/plan-to-ralph`, do **not** write a top-level array — dex has no equivalent; codex just runs the commands named in the checkbox.

### Manual criteria

If a verification step requires human judgment ("inspect the output", "if WARN lines appear…"), emit it as `- [ ] [manual] <text>` and list every `[manual]` checkbox in the Step 5 confirmation, so the user knows codex will tick it without true verification.

## Step 4: Preflight Checks

<!-- filled in Task 5 -->

## Step 5: Confirm

<!-- filled in Task 5 -->

## Step 6: Run the dex Chain

<!-- filled in Task 5 -->

## Step 7: Handoff Report

<!-- filled in Task 5 -->
