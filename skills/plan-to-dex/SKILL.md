---
name: plan-to-dex
description: 'Use when running an already-hardened Superpowers implementation plan through the dex orchestrator (codex backend). Triggers on: convert plan to dex, plan to dex, dex from plan, run plan with dex, plan-to-dex.'
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
5. Run `dex import` → `dex --cli codex apply` → `dex --cli codex review`
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

If no tooling is detected, ask: "What commands must pass for every task?" Do **not** write a top-level array of gate commands — dex has no equivalent; codex just runs the commands named in the checkbox.

### Manual criteria

If a verification step requires human judgment ("inspect the output", "if WARN lines appear…"), emit it as `- [ ] [manual] <text>` and list every `[manual]` checkbox in the Step 5 confirmation, so the user knows codex will tick it without true verification.

## Step 4: Preflight Checks

1. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`".
2. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; this skill runs dex with the codex backend."
3. **`--cli` flag form:** `dex --cli codex --help` should exit 0 — confirms `--cli` is accepted as a global option (the form Step 6 uses). If this fails, a future dex version may have moved `--cli` under the subcommand; run `dex --help` to check and adjust the Step 6 commands accordingly. (Validated against dex 0.4.9, where `--cli` is global.)
4. **Branch guard:** get the current branch (`git rev-parse --abbrev-ref HEAD`). If it is `main` or `master`, resolve a feature branch (use a name the user provided, else ask for one) and `git switch -c <name>` before any `dex apply`. `dex apply` auto-commits across iterations — those commits must land on a throwaway branch, never `main`/`master`.

## Step 5: Confirm

Present a single confirmation and wait for a yes/no:

```
plan-to-dex — ready to run
--------------------------
Source plan: <path>
Tasks:       <N>  (→ <N> dex iterations)
Backend:     codex  (dex --cli codex)
Branch:      <resolved branch>
Manual criteria (codex will tick without proof):
  - [manual] <text>            # omit this block if none

This runs dex autonomously: it will implement and COMMIT across <N> iterations,
then run a multi-reviewer pass. Proceed? [y/N]
```

This is the standard confirm-before-a-hard-to-reverse-action check, NOT a plan review gate — the plan was hardened upstream. If the user declines, stop (the `tasks/dex-plan.md` file is already written for them to inspect).

## Step 6: Run the dex Chain

Run these in order, streaming output. Do NOT set `--model`; do NOT edit `.dex/config.json`.

```bash
dex import --force tasks/dex-plan.md
dex --cli codex apply        # long-running — see the poll-to-completion contract below
dex --cli codex review       # ALSO long-running — same poll-to-completion contract
```

`--cli` is a **global** dex option (validated against dex 0.4.9) and must precede the subcommand — `dex --cli codex apply`, not `dex apply --cli codex` (the latter errors with `Unrecognized argument: --cli`). `dex import` takes a path arg and needs no `--cli`.

### `dex apply` AND `dex review` are long-running — poll each to completion in THIS invocation

Both phases drive codex through work that **will likely exceed a single foreground Bash timeout** (the harness caps foreground Bash at 10 minutes / `600000ms`). Run each foreground with the **maximum timeout**, then **loop** — the contract is identical for both.

**`dex apply`:**
1. Run `dex --cli codex apply` (foreground, `timeout: 600000`).
2. Re-read `.dex/plan.md` after the pass.
3. If any checkbox is still `[ ]` **and** dex did not report a terminal state, run `dex --cli codex apply` again (it resumes where it left off).
4. Repeat until **all checkboxes are `[x]`** or dex reports terminal (`STALEMATE` / non-zero exit).

**`dex review`:** the same loop — re-run `dex --cli codex review` foreground at max timeout every time the 10-min ceiling truncates it, until it reaches a terminal state: it prints its completion line (`Review complete` / `DONE`) and/or writes `.dex/review-*.md`, or reports a terminal `STALEMATE` / non-zero exit. **Terminal on quota:** if codex exhausts its usage quota *after* apply is fully done (every `.dex/plan.md` checkbox `[x]`) and at least one reviewer pass has written its findings, treat the quota state as terminal — report it and stop. Do NOT loop forever on quota backoff.

**FORBIDDEN — no escape hatches (this is exactly where past runs failed):**
- **Never** run `dex apply` or `dex review` with `run_in_background: true`.
- **Never** arm a `Monitor` / waiter / `ScheduleWakeup` to "come back later" — nothing re-invokes a returned invocation, so the child is reaped and only the `dex import` setup commit lands.
- **Never** return on an intermediate "waiting for / running in background / iteration N in progress" state.

Backgrounded work dies the instant this invocation (especially a subagent) returns. The loop MUST reach a terminal state inside the current invocation. If you need to wait on a foreground pid, block on it directly (`wait <pid>`, or `while kill -0 <pid> 2>/dev/null; do sleep 15; done`) — never rely on any waiter or `Monitor` to resume you.

### Before you return: pre-return verification (mandatory)

Do NOT return until you have **run these three checks and can state their results**. If any check fails, keep looping — returning early is a bug, not a shortcut:

1. **Plan done:** `grep -c '\[ \]' .dex/plan.md` prints `0` — every checkbox is `[x]` (or dex printed a terminal `STALEMATE`/quota state, which you name explicitly).
2. **No live worker _in this worktree_:**

   ```bash
   pgrep -f '[d]ex --cli codex|[c]odex exec' | while read -r p; do
     lsof -a -d cwd -p "$p" -Fn 2>/dev/null | grep -q "^n$(pwd -P)" && echo "live worker $p"
   done
   ```

   prints **nothing**. Two details are load-bearing, and a bare `pgrep -fl 'dex --cli codex|codex exec'` gets both wrong:
   - **Scope to your own worktree.** Concurrent `/ship-it` runs in sibling worktrees have their own `dex --cli codex apply` and `codex exec` processes. A machine-wide `pgrep` sees them, reports a "live worker" that is not yours, and makes this check permanently unsatisfiable. The `lsof -d cwd` filter keeps only processes whose working directory is under this worktree.
   - **Bracket the first character** (`[d]ex`, `[c]odex`). Without it the pattern matches the command line of the shell running the check — the check reports itself as a live worker and never passes.

   **Never kill, signal, or wait on a process you did not start.** A sibling run's dex is not your problem, and killing it corrupts that run. If this check still prints after your own foreground `dex` command returned, you backgrounded it — that is the only failure it is looking for.
3. **Commits landed:** `git log --oneline` shows per-task dex commits (not just the lone `dex import` setup commit), and `git status` is as expected.

- If `dex apply` prints `STALEMATE` or exits non-zero, STOP — report dex's output verbatim and do NOT run `dex review`.
- If `dex import` fails validation, STOP and show the error (the translated file lacks an open checkbox — a translation bug).

## Step 7: Handoff Report

After the chain completes, report:

```
plan-to-dex complete
--------------------
Branch:           <branch>
Tasks completed:  <done>/<total>   (from dex plan-step counts)
Review findings:  .dex/review-*.md
Next:             review the diff, then `dex finalize --onto main`
```

Do NOT run `dex finalize` automatically — merging back is the user's call.
