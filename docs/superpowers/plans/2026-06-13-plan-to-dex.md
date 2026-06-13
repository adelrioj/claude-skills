# /plan-to-dex Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/plan-to-dex` skill that translates a hardened Superpowers plan into a dex-compatible `plan.md`, imports it via `dex import`, and runs dex's `apply`/`review` loop end to end with codex as the fixed backend.

**Architecture:** A self-contained Claude Code skill (`SKILL.md` + one template), no shell scripts of our own — the `dex` CLI is the runtime. The skill reuses `/plan-to-ralph`'s plan-location and validation *patterns* (copied, not shared), but emits dex's checkbox-group markdown (one Task heading = one iteration) instead of `prd.json`. Backend is pinned to `--cli codex`; the skill sets no `--model` and never writes `.dex/config.json`.

**Tech Stack:** Markdown skill format (YAML frontmatter + body); `dex` CLI (`import`/`apply`/`review`/`finalize`); `codex` CLI as the fixed backend; `jq` for validating JSON wiring files; `bash` for verification round-trips.

**Spec:** docs/superpowers/specs/2026-06-13-plan-to-dex-design.md

---

## File Structure

| File | Responsibility |
| ---- | -------------- |
| `skills/plan-to-dex/SKILL.md` | The skill: frontmatter (triggering) + the full translate→import→apply→review procedure Claude follows |
| `skills/plan-to-dex/templates/dex-plan.md` | The `{{PLACEHOLDER}}` checkbox-group template the skill fills in and feeds to `dex import` |
| `.claude-plugin/plugin.json` | Plugin manifest — add `dex` keyword, refresh description, bump version |
| `.claude-plugin/marketplace.json` | Marketplace entry — refresh description/keywords |
| `CLAUDE.md` | Project guidance — add `/plan-to-dex` to Skills + a "dex path" Key Convention |
| `README.md` | User-facing docs — add `/plan-to-dex` skill blurb + usage |

`SKILL.md` is one focused file because it is read whole by Claude at invocation; splitting it would fragment the procedure. The template is separate so the literal output format lives in one inspectable place.

A note on verification: a skill is prose Claude follows, so most tasks verify **structurally** (required sections present, no placeholder strings, JSON valid). The one genuinely behavioral check is a **dex round-trip** (Task 2): importing a golden filled-in plan into a throwaway dex workspace and asserting `dex import` accepts it (and rejects a checkbox-less file). That proves the emitted format is one `dex apply` can actually parse.

---

## Task 1: Scaffold the skill + frontmatter

**Files:**
- Create: `skills/plan-to-dex/SKILL.md`

- [ ] **Step 1: Write the failing check**

Create the verification script inline (run it before the file exists):

Run:
```bash
test -f skills/plan-to-dex/SKILL.md && \
  python3 -c "import yaml,sys; d=open('skills/plan-to-dex/SKILL.md').read(); fm=d.split('---')[1]; m=yaml.safe_load(fm); assert m['name']=='plan-to-dex'; assert m['user-invocable'] is True; assert 'plan to dex' in m['description'].lower(); print('OK')"
```
Expected: FAIL — `test -f` returns non-zero because the file does not exist yet.

- [ ] **Step 2: Create `skills/plan-to-dex/SKILL.md` with frontmatter and section skeleton**

Write exactly this content (sections after the skeleton are filled in later tasks):

````markdown
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

<!-- filled in Task 3 -->

## Step 2: Validate the Plan

<!-- filled in Task 3 -->

## Step 3: Translate to dex plan.md

<!-- filled in Task 4 -->

## Step 4: Preflight Checks

<!-- filled in Task 5 -->

## Step 5: Confirm

<!-- filled in Task 5 -->

## Step 6: Run the dex Chain

<!-- filled in Task 5 -->

## Step 7: Handoff Report

<!-- filled in Task 5 -->
````

- [ ] **Step 3: Run the check to verify it passes**

Run:
```bash
python3 -c "import yaml; m=yaml.safe_load(open('skills/plan-to-dex/SKILL.md').read().split('---')[1]); assert m['name']=='plan-to-dex'; assert m['user-invocable'] is True; assert 'plan to dex' in m['description'].lower(); print('OK')"
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add skills/plan-to-dex/SKILL.md
git commit -m "feat(plan-to-dex): scaffold skill frontmatter and section skeleton"
```

---

## Task 2: Author the dex-plan template + prove it imports

This is the load-bearing correctness check: the template must produce markdown that `dex import` accepts (≥1 open `- [ ]` under a heading) and `dex apply` would parse as one group per Task heading.

**Files:**
- Create: `skills/plan-to-dex/templates/dex-plan.md`

- [ ] **Step 1: Write the failing round-trip test**

Create the test script and run it before the template exists:

Run:
```bash
bash -euo pipefail -c '
GOLDEN=$(mktemp /tmp/dex-golden-XXXX.md)
cat > "$GOLDEN" <<EOF
# Widget Cache — dex plan

## Overview

Add an LRU cache to the widget service.

Source plan: docs/superpowers/plans/2099-01-01-widget-cache.md

### Task 1: LRU cache

**Files:** Create \`src/cache.ts\`, Test \`tests/cache.test.ts\`

- [ ] Write failing test in \`tests/cache.test.ts\` — \`npm test\` should FAIL
- [ ] Implement LRU cache in \`src/cache.ts\` so the test passes
- [ ] Verify \`npm test\` PASSES
- [ ] Quality gates: \`npm run typecheck\` passes
- [ ] Commit
EOF

# positive: a well-formed plan imports cleanly
POS=$(mktemp -d); ( cd "$POS" && git init -q && dex import "$GOLDEN" >/dev/null 2>&1 && test -f .dex/plan.md ) || { echo "POSITIVE FAILED"; exit 1; }

# negative: a checkbox-less file is rejected
NEG=$(mktemp -d); BAD=$(mktemp /tmp/dex-bad-XXXX.md); printf "# No tasks here\n\nJust prose.\n" > "$BAD"
( cd "$NEG" && git init -q && ! dex import "$BAD" >/dev/null 2>&1 ) || { echo "NEGATIVE FAILED (bad file was accepted)"; exit 1; }

# template-shape check: the committed template, with placeholders swapped for a checkbox, must also import
TPL=skills/plan-to-dex/templates/dex-plan.md
test -f "$TPL" || { echo "TEMPLATE MISSING"; exit 1; }
RENDER=$(mktemp /tmp/dex-render-XXXX.md)
sed -e "s/{{[A-Z0-9_]*}}/placeholder/g" "$TPL" > "$RENDER"
REN=$(mktemp -d); ( cd "$REN" && git init -q && dex import "$RENDER" >/dev/null 2>&1 && test -f .dex/plan.md ) || { echo "TEMPLATE DID NOT IMPORT"; exit 1; }

echo "OK"
'
```
Expected: FAIL — prints `TEMPLATE MISSING` and exits non-zero (the template file does not exist yet). The positive/negative golden checks pass, confirming the test harness itself works.

- [ ] **Step 2: Create `skills/plan-to-dex/templates/dex-plan.md`**

Write exactly this content:

````markdown
# {{FEATURE_NAME}} — dex plan

## Overview

{{GOAL_SENTENCE}}

Source plan: {{PLAN_FILE_PATH}}

<!--
  One source Task = one "### Task N:" heading = one dex iteration.
  dex hands the whole group (heading + checkboxes + prose) to codex at once,
  then exits and re-reads. Repeat the block below per source task.
  Quality-gate checkbox is appended to EVERY task. [manual] criteria get a
  "[manual] " prefix so a human knows codex will tick them without real proof.
-->

### Task {{N}}: {{COMPONENT_NAME}}

**Files:** {{FILE_LIST}}

- [ ] {{STEP_WRITE_FAILING_TEST}}
- [ ] {{STEP_IMPLEMENT}}
- [ ] {{STEP_VERIFY_TESTS_PASS}}
- [ ] Quality gates: {{QUALITY_GATE_COMMANDS}} pass
- [ ] Commit
````

- [ ] **Step 3: Run the round-trip test to verify it passes**

Run: (the same script from Step 1)
```bash
bash -euo pipefail -c '
GOLDEN=$(mktemp /tmp/dex-golden-XXXX.md)
cat > "$GOLDEN" <<EOF
# Widget Cache — dex plan

## Overview

Add an LRU cache to the widget service.

### Task 1: LRU cache

**Files:** Create \`src/cache.ts\`, Test \`tests/cache.test.ts\`

- [ ] Write failing test in \`tests/cache.test.ts\` — \`npm test\` should FAIL
- [ ] Implement LRU cache in \`src/cache.ts\` so the test passes
- [ ] Verify \`npm test\` PASSES
- [ ] Quality gates: \`npm run typecheck\` passes
- [ ] Commit
EOF
POS=$(mktemp -d); ( cd "$POS" && git init -q && dex import "$GOLDEN" >/dev/null 2>&1 && test -f .dex/plan.md ) || { echo "POSITIVE FAILED"; exit 1; }
NEG=$(mktemp -d); BAD=$(mktemp /tmp/dex-bad-XXXX.md); printf "# No tasks here\n\nJust prose.\n" > "$BAD"
( cd "$NEG" && git init -q && ! dex import "$BAD" >/dev/null 2>&1 ) || { echo "NEGATIVE FAILED"; exit 1; }
TPL=skills/plan-to-dex/templates/dex-plan.md
RENDER=$(mktemp /tmp/dex-render-XXXX.md)
sed -e "s/{{[A-Z0-9_]*}}/placeholder/g" "$TPL" > "$RENDER"
REN=$(mktemp -d); ( cd "$REN" && git init -q && dex import "$RENDER" >/dev/null 2>&1 && test -f .dex/plan.md ) || { echo "TEMPLATE DID NOT IMPORT"; exit 1; }
echo "OK"
'
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add skills/plan-to-dex/templates/dex-plan.md
git commit -m "feat(plan-to-dex): add dex-plan template, verified via dex import round-trip"
```

---

## Task 3: Write Steps 1–2 (locate + validate the plan)

**Files:**
- Modify: `skills/plan-to-dex/SKILL.md` (replace the `## Step 1` and `## Step 2` placeholders)

- [ ] **Step 1: Replace the Step 1 + Step 2 placeholder sections**

In `skills/plan-to-dex/SKILL.md`, replace the two lines:
```
## Step 1: Locate the Plan

<!-- filled in Task 3 -->

## Step 2: Validate the Plan

<!-- filled in Task 3 -->
```
with exactly:

````markdown
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
````

- [ ] **Step 2: Verify the sections are present and the placeholders are gone**

Run:
```bash
grep -q "scan for the most recent plan file" skills/plan-to-dex/SKILL.md && \
grep -q "Never invent requirements" skills/plan-to-dex/SKILL.md && \
! grep -q "filled in Task 3" skills/plan-to-dex/SKILL.md && echo "OK"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/plan-to-dex/SKILL.md
git commit -m "feat(plan-to-dex): add plan location and validation steps"
```

---

## Task 4: Write Step 3 (the translation rules)

This is the core transform. It documents how source Tasks map to dex task groups and how quality gates / `[manual]` steps are handled.

**Files:**
- Modify: `skills/plan-to-dex/SKILL.md` (replace the `## Step 3` placeholder)

- [ ] **Step 1: Replace the Step 3 placeholder section**

Replace:
```
## Step 3: Translate to dex plan.md

<!-- filled in Task 4 -->
```
with exactly:

````markdown
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
````

- [ ] **Step 2: Verify Step 3 content is present and consistent with the template**

Run:
```bash
grep -q "one dex iteration" skills/plan-to-dex/SKILL.md && \
grep -q "Quality-gate detection" skills/plan-to-dex/SKILL.md && \
grep -q "\[manual\]" skills/plan-to-dex/SKILL.md && \
grep -q "do \*\*not\*\* write a top-level array" skills/plan-to-dex/SKILL.md && \
! grep -q "filled in Task 4" skills/plan-to-dex/SKILL.md && echo "OK"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/plan-to-dex/SKILL.md
git commit -m "feat(plan-to-dex): add translation rules (task-group mapping, quality gates, manual criteria)"
```

---

## Task 5: Write Steps 4–7 (preflight, confirm, run chain, handoff)

**Files:**
- Modify: `skills/plan-to-dex/SKILL.md` (replace the Step 4–7 placeholders)

- [ ] **Step 1: Replace the four placeholder sections**

Replace the block from `## Step 4: Preflight Checks` through the final `<!-- filled in Task 5 -->` with exactly:

````markdown
## Step 4: Preflight Checks

1. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`".
2. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; this skill runs dex with the codex backend."
3. **Branch guard:** get the current branch (`git rev-parse --abbrev-ref HEAD`). If it is `main` or `master`, resolve a feature branch (use a name the user provided, else ask for one) and `git switch -c <name>` before any `dex apply`. `dex apply` auto-commits across iterations — those commits must land on a throwaway branch, never `main`/`master`.

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
dex apply --cli codex
dex review --cli codex
```

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
````

- [ ] **Step 2: Verify codex-pinned execution and safety rails are present**

Run:
```bash
grep -q "dex apply --cli codex" skills/plan-to-dex/SKILL.md && \
grep -q "dex review --cli codex" skills/plan-to-dex/SKILL.md && \
grep -q "dex import --force tasks/dex-plan.md" skills/plan-to-dex/SKILL.md && \
grep -q "is .main. or .master." skills/plan-to-dex/SKILL.md && \
grep -q "Do NOT set .--model" skills/plan-to-dex/SKILL.md && \
! grep -q "filled in Task 5" skills/plan-to-dex/SKILL.md && echo "OK"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add skills/plan-to-dex/SKILL.md
git commit -m "feat(plan-to-dex): add preflight, confirmation, codex-pinned run chain, and handoff"
```

---

## Task 6: Repo wiring (manifest, marketplace, CLAUDE.md, README)

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update `.claude-plugin/plugin.json`**

Add `"dex"` to the `keywords` array (after `"codex"`), and bump `"version"` from `"1.0.7"` to `"1.1.0"` (new feature). Append to the `description` so it reads:
```
"...drives Claude Code or OpenAI Codex through one user story per iteration, plus a plan-to-dex runner for the dex orchestrator"
```

- [ ] **Step 2: Update `.claude-plugin/marketplace.json`**

In the `plugins[0]` entry: add `"dex"` to `keywords`, bump `"version"` to `"1.1.0"`, and extend `"description"` to mention `plan-to-dex`.

- [ ] **Step 3: Verify both JSON files are valid and consistent**

Run:
```bash
jq -e '.version=="1.1.0" and (.keywords|index("dex"))' .claude-plugin/plugin.json >/dev/null && \
jq -e '.plugins[0].version=="1.1.0" and (.plugins[0].keywords|index("dex"))' .claude-plugin/marketplace.json >/dev/null && \
echo "OK"
```
Expected: `OK`

- [ ] **Step 4: Update `CLAUDE.md`**

In the `## Skills` section, add a `### /plan-to-dex` subsection after `/plan-to-ralph`:
```markdown
### `/plan-to-dex`
Translates a Superpowers implementation plan into a [dex](https://github.com/francescoalemanno/dex)-compatible `plan.md`, imports it via `dex import`, and runs dex's `apply`/`review` loop end to end. Backend is fixed to codex (`dex --cli codex`); the skill sets no model and never writes `.dex/config.json`. One source Task = one `### Task N:` heading = one dex iteration. Output: `tasks/dex-plan.md`. Requires the `dex` and `codex` CLIs. Refuses to run `dex apply` on `main`/`master` — resolves a feature branch first.
```
In `## Key Conventions`, add a bullet:
```markdown
- `/plan-to-dex` pins the dex backend to codex and never writes `.dex/config.json` — the model is codex's own default; dex owns all execution state under `.dex/`
```

- [ ] **Step 5: Update `README.md`**

In `## Skills`, add after the `/plan-to-ralph` blurb:
```markdown
**`/plan-to-dex`** — Run a hardened Superpowers plan through the [dex](https://github.com/francescoalemanno/dex) orchestrator instead of the Ralph loop. Translates the plan into dex's checkbox-group `plan.md` (one task = one iteration), imports it, and runs `dex apply` → `dex review` autonomously with codex as the fixed backend. Requires the `dex` and `codex` CLIs.
```

- [ ] **Step 6: Verify the docs mention the skill**

Run:
```bash
grep -q "plan-to-dex" CLAUDE.md && grep -q "plan-to-dex" README.md && echo "OK"
```
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CLAUDE.md README.md
git commit -m "docs(plan-to-dex): wire skill into manifest, marketplace, CLAUDE.md, and README"
```

---

## Task 7: Final integration verification

A verification-only gate — no new files. Confirms the finished skill has no leftover placeholders, is internally consistent, and the format still round-trips through dex.

**Files:** none (verification only)

- [ ] **Step 1: Assert no leftover scaffold placeholders or plan red flags**

Run:
```bash
! grep -nE "filled in Task|TBD|TODO|FIXME" skills/plan-to-dex/SKILL.md && \
test "$(grep -c '## Step' skills/plan-to-dex/SKILL.md)" -ge 7 && echo "OK"
```
Expected: `OK`

- [ ] **Step 2: Re-run the dex round-trip on the committed template**

Run:
```bash
bash -euo pipefail -c '
TPL=skills/plan-to-dex/templates/dex-plan.md
RENDER=$(mktemp /tmp/dex-final-XXXX.md)
sed -e "s/{{[A-Z0-9_]*}}/placeholder/g" "$TPL" > "$RENDER"
DIR=$(mktemp -d); ( cd "$DIR" && git init -q && dex import "$RENDER" >/dev/null 2>&1 && test -f .dex/plan.md ) && echo "OK"
'
```
Expected: `OK`

- [ ] **Step 3: Confirm the skill is discoverable as a plugin skill**

Run:
```bash
ls skills/plan-to-dex/SKILL.md skills/plan-to-dex/templates/dex-plan.md && \
python3 -c "import yaml; m=yaml.safe_load(open('skills/plan-to-dex/SKILL.md').read().split('---')[1]); assert m['user-invocable'] is True; print('discoverable OK')"
```
Expected: file paths listed + `discoverable OK`

- [ ] **Step 4: Commit (only if Steps 1–3 surfaced fixes)**

```bash
git add -A && git commit -m "test(plan-to-dex): final integration verification" || echo "nothing to commit"
```

---

## Self-Review Notes

- **Spec coverage:** translation format (Task 4 + Task 2 template) ✓; codex-pinned backend, no `--model`, no `.dex/config.json` (Tasks 1,5) ✓; branch guard (Task 5) ✓; single confirmation (Task 5) ✓; locate/validate reuse (Task 3) ✓; "deliberately NOT carried over" — no prd.json/progress/findings, no top-level qualityGates array (Task 4 note) ✓; repo wiring (Task 6) ✓.
- **Out-of-scope respected:** no `dex plan` wrapper, no multi-backend prompt, no model selection — none appear in any task.
- **Naming consistency:** output file is `tasks/dex-plan.md` and installed target is `.dex/plan.md` throughout; backend flag is `--cli codex` in every run command.
