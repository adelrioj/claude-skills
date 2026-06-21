# /ship-it Conductor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/ship-it` conductor skill that runs the user's spec→PR pipeline (spec-review → write-plan → execute → PR → PR-review) end-to-end from one invocation, sequentially, best-effort, never halting on quality.

**Architecture:** A single `user-invocable` skill at `skills/ship-it/SKILL.md`. It is a *pure conductor*: it invokes the existing units **live** (`spec-review-codex`, `writing-plans`, `plan-to-dex`, `/commit-commands:commit-push-pr`, `/review-pr`) via the Skill tool / slash commands and duplicates none of their logic. It owns only the *transitions*: preflight, success detection, state extraction, branch resolution, the never-halt decision, and a final report. Three boundary-verifier subagents (after spec-review, after execution, after PR-review) extract structured state without bloating the conductor's context.

**Tech Stack:** Markdown SKILL.md (frontmatter + instructions Claude follows). No scripts, no templates. Underlying CLIs (`codex`, `dex`, `gh`) are owned by the units, not by this skill. Validation is structural (grep assertions) plus the `plugin-dev:skill-reviewer` agent.

## Global Constraints

- The deliverable is `skills/ship-it/SKILL.md` — an instruction file, no `scripts/` or `templates/`.
- **Pure conductor — duplicate NO logic** from the underlying units; invoke them live so edits to them are always picked up.
- Underlying units invoked: `Skill(spec-review-codex)`, `Skill(writing-plans)`, `Skill(plan-to-dex)`, the `/commit-commands:commit-push-pr` slash command, the `/review-pr` slash command.
- **Sequential, fully autonomous, best-effort, never halt on quality.** The only hard abort is preflight failure. A hard failure that makes the next step impossible → skip downstream + jump to final report; never fabricate a downstream artifact.
- **Branch guard:** `plan-to-dex` refuses `main`/`master`; the conductor resolves a `feat/<spec-slug>` branch *before* step 4 (execution), reusing the current feature branch if already on one.
- **PR-review loop:** re-review after each fix pass; stop at no CRITICAL/IMPORTANT remaining OR 3 passes, whichever first.
- **No state on disk** except the final report; pipeline state lives in conversation memory + verifier hand-offs (same as `swarm-execute`).
- **Final report** is the deliverable contract: per-step outcome, PR URL, every unresolved CRITICAL/IMPORTANT, failed dex tasks, resume guidance — written in `/handoff` style to the **OS temp dir, never the workspace**.
- Use `${CLAUDE_PLUGIN_ROOT}` in any runtime path shown to users (repo convention).
- Skill registration must stay in sync across `plugin.json`, `marketplace.json`, `README.md`, and `CLAUDE.md`.
- Frontmatter `description` follows the repo pattern: `"Use when ... Triggers on: <comma list>."` and `user-invocable: true`.

---

### Task 1: SKILL.md skeleton — frontmatter, The Job, and preflight

**Files:**
- Create: `skills/ship-it/SKILL.md`

**Interfaces:**
- Produces: the skill file every later task appends to; the frontmatter `name: ship-it`; a `## Step 0: Preflight` section other tasks reference.

- [ ] **Step 1: Write the structural test (validation script)**

Create the check that this task's output must satisfy. Run after writing the file.

```bash
# tests/check-ship-it-task1.sh  (throwaway; do not commit)
f=skills/ship-it/SKILL.md
grep -q '^name: ship-it$' "$f" || { echo FAIL: name; exit 1; }
grep -q '^user-invocable: true$' "$f" || { echo FAIL: user-invocable; exit 1; }
grep -q 'Triggers on:' "$f" || { echo FAIL: triggers; exit 1; }
grep -q '## Step 0: Preflight' "$f" || { echo FAIL: preflight heading; exit 1; }
for tool in codex dex 'pr-review-toolkit' 'commit-commands'; do
  grep -q "$tool" "$f" || { echo "FAIL: preflight missing $tool"; exit 1; }
done
echo PASS
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash tests/check-ship-it-task1.sh`
Expected: FAIL (file does not exist yet — `grep` errors / `FAIL: name`).

- [ ] **Step 3: Write the file**

Create `skills/ship-it/SKILL.md` with exactly this content:

````markdown
---
name: ship-it
description: "Use when a thumbs-upped design spec is ready and you want the whole spec-to-PR pipeline to run autonomously — hardens the spec, writes the plan, executes it via dex, opens a PR, and runs PR review — in one invocation. Triggers on: ship it, ship-it, run the pipeline, spec to PR, autonomous feature pipeline, conductor."
user-invocable: true
---

# Ship-It Conductor

Run the full feature pipeline from a thumbs-upped design spec to a reviewed pull request, autonomously, in one invocation. This skill is a **pure conductor**: it sequences existing units and owns the transitions between them. It duplicates none of their logic — each unit is invoked **live**, so improvements to those units are always picked up.

**Pipeline (sequential):** harden spec → write plan → resolve branch → execute → open PR → review loop.

**Policy:** fully autonomous, best-effort, **never halt on quality**. The only hard abort is a failed preflight. A non-clean *quality* outcome (open IMPORTANTs, review notes) is recorded and the chain continues. A hard failure that makes the next step *impossible* (e.g. zero code produced → nothing to commit) skips the now-impossible steps and jumps to the final report — it never fabricates a downstream artifact.

**Underlying units (invoked live, never reimplemented):** `spec-review-codex`, `writing-plans`, `plan-to-dex` (all via the Skill tool), and the `/commit-commands:commit-push-pr` + `/review-pr` slash commands.

---

## The Job

1. Preflight (fail fast)
2. Step 1 — Harden the spec via `spec-review-codex`
3. Step 2 — Write the implementation plan via `writing-plans` (from the *hardened* spec)
4. Step 3 — Resolve a feature branch
5. Step 4 — Execute via `plan-to-dex` (includes its final Opus review)
6. Step 5 — Open the PR via `/commit-commands:commit-push-pr`
7. Step 6 — Review + fix loop via `/review-pr`
8. Emit the final report

Pipeline state (spec path, plan path, branch, PR number, leftover findings) lives in **conversation memory and the verifier hand-offs** — never written to disk. The only written artifact is the final report.

---

## Step 0: Preflight

Run these checks **before any mutation**. Preflight failure is the **only** hard abort; once past it, the never-halt policy governs.

1. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; required by spec-review-codex and plan-to-dex."
2. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`."
3. **`pr-review-toolkit` plugin present:** the `/review-pr` command must resolve — else STOP: "pr-review-toolkit plugin not installed; required for the PR review step."
4. **`commit-commands` plugin present:** the `/commit-commands:commit-push-pr` command must resolve — else STOP: "commit-commands plugin not installed; required to open the PR."
5. **Spec located:** the argument is a path to a design spec; if omitted, find the newest `docs/superpowers/specs/*-design.md` and confirm it with the user before starting.

On any STOP, print the missing item plus its remedy and exit without touching the repo.
````

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash tests/check-ship-it-task1.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rm -f tests/check-ship-it-task1.sh
git add skills/ship-it/SKILL.md
git commit -m "feat(ship-it): scaffold SKILL.md with frontmatter and preflight"
```

---

### Task 2: The 6-step pipeline body

**Files:**
- Modify: `skills/ship-it/SKILL.md` (append the pipeline sections)

**Interfaces:**
- Consumes: `## Step 0: Preflight` and the spec path resolved there.
- Produces: `## Step 1` … `## Step 6` headings and a pipeline table; the branch-resolution rule (`feat/<spec-slug>`) that Task 3's never-halt section references.

- [ ] **Step 1: Write the structural test**

```bash
# tests/check-ship-it-task2.sh  (throwaway)
f=skills/ship-it/SKILL.md
for h in '## Step 1: Harden the Spec' '## Step 2: Write the Plan' \
         '## Step 3: Resolve the Branch' '## Step 4: Execute' \
         '## Step 5: Open the PR' '## Step 6: Review Loop'; do
  grep -qF "$h" "$f" || { echo "FAIL: missing $h"; exit 1; }
done
grep -q 'spec-review-codex' "$f" && grep -q 'writing-plans' "$f" \
  && grep -q 'plan-to-dex' "$f" && grep -q 'commit-push-pr' "$f" \
  && grep -q 'review-pr' "$f" || { echo FAIL: unit refs; exit 1; }
grep -qE 'feat/<?spec-slug>?' "$f" || { echo FAIL: branch rule; exit 1; }
grep -q '3 passes' "$f" || { echo FAIL: review loop cap; exit 1; }
echo PASS
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash tests/check-ship-it-task2.sh`
Expected: FAIL: missing `## Step 1: Harden the Spec`

- [ ] **Step 3: Append the pipeline body**

Append to `skills/ship-it/SKILL.md`:

````markdown
---

## Pipeline Overview

| # | Step | Unit invoked | Success bar | State handed forward |
|---|------|-------------|-------------|----------------------|
| 1 | Harden spec | `Skill(spec-review-codex)` | PASS, or 3-iteration cap | (possibly rewritten) spec path |
| 2 | Write plan | `Skill(writing-plans)` | plan file written | plan path |
| 3 | Resolve branch | conductor itself | on a non-`main`/`master` branch | branch name |
| 4 | Execute | `Skill(plan-to-dex)` (incl. Opus review) | dex loop completes | dex status + diff summary |
| 5 | Open PR | `/commit-commands:commit-push-pr` | PR created | PR number / URL |
| 6 | Review loop | `/review-pr` + fix | clean, or 3 passes | leftover findings |

---

## Step 1: Harden the Spec

Invoke `Skill(spec-review-codex)` on the spec resolved in preflight. Let it run its full 3-iteration fix loop. When it returns, dispatch **Verifier Agent A** (see "Boundary Verifiers") to read its outcome and report: PASS / finished-with-open-IMPORTANTs / failed, plus the current spec path (it may have been rewritten). Record the outcome; **continue regardless** (never halt on quality).

## Step 2: Write the Plan

Invoke `Skill(writing-plans)` on the **hardened** spec from Step 1. This is the earliest generative step — do not re-brainstorm or re-interview. When the plan file is written, capture its path. If `writing-plans` produces no plan file (hard failure), skip to the final report (Steps 3-6 are impossible without a plan).

## Step 3: Resolve the Branch

`plan-to-dex` refuses `main`/`master`. Get the current branch (`git rev-parse --abbrev-ref HEAD`):
- If already on a feature branch, reuse it.
- Else create one from the spec filename slug: `git switch -c feat/<spec-slug>`.

Record the branch name.

## Step 4: Execute

Invoke `Skill(plan-to-dex)` with the plan path from Step 2; let it run the dex `apply`/`review` loop to completion, including its own final Opus review. When it returns, dispatch **Verifier Agent B** to report: did the loop complete, which (if any) dex tasks failed, and a one-line diff summary. Record it.

**Hard-failure branch:** if dex produced **zero diff** (`git status --porcelain` empty and no dex commits), there is nothing to commit — skip Steps 5-6 and jump to the final report. Do not open an empty PR.

## Step 5: Open the PR

Run the `/commit-commands:commit-push-pr` slash command to commit, push the branch, and open the PR. Capture the PR number and URL from its output. If no PR is created (hard failure), skip Step 6 and jump to the final report.

## Step 6: Review Loop

Loop, up to **3 passes**:
1. Run the `/review-pr` slash command against the PR.
2. If it reports no CRITICAL and no IMPORTANT findings → the PR is clean; exit the loop.
3. Otherwise fix **only** the CRITICAL and IMPORTANT findings (leave ADVISORY/MINOR), commit, push, and re-review.

After 3 passes, stop even if findings remain. Dispatch **Verifier Agent C** to collect any leftover CRITICAL/IMPORTANT for the final report.
````

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash tests/check-ship-it-task2.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rm -f tests/check-ship-it-task2.sh
git add skills/ship-it/SKILL.md
git commit -m "feat(ship-it): add the 6-step pipeline body"
```

---

### Task 3: Boundary verifiers, never-halt control flow, and final report

**Files:**
- Modify: `skills/ship-it/SKILL.md` (append the remaining sections)

**Interfaces:**
- Consumes: the `## Step 1/4/6` references to "Verifier Agent A/B/C"; the branch and PR state from Task 2.
- Produces: `## Boundary Verifiers`, `## Control Flow — Never Halt`, `## Final Report` sections that complete the skill.

- [ ] **Step 1: Write the structural test**

```bash
# tests/check-ship-it-task3.sh  (throwaway)
f=skills/ship-it/SKILL.md
for h in '## Boundary Verifiers' '## Control Flow' '## Final Report'; do
  grep -qF "$h" "$f" || { echo "FAIL: missing $h"; exit 1; }
done
for v in 'Verifier Agent A' 'Verifier Agent B' 'Verifier Agent C'; do
  grep -qF "$v" "$f" || { echo "FAIL: missing $v"; exit 1; }
done
# never fabricate a downstream artifact + temp-dir report
grep -qi 'never fabricate' "$f" || { echo FAIL: fabricate rule; exit 1; }
grep -qiE 'temp(orary)? (dir|directory)' "$f" || { echo FAIL: temp dir; exit 1; }
grep -qi 'never.*workspace\|not the workspace\|never the workspace' "$f" || { echo FAIL: workspace rule; exit 1; }
echo PASS
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash tests/check-ship-it-task3.sh`
Expected: FAIL: missing `## Boundary Verifiers`

- [ ] **Step 3: Append the final sections**

Append to `skills/ship-it/SKILL.md`:

````markdown
---

## Boundary Verifiers

After the three block edges, dispatch a small subagent (the `Agent` tool) that reads **only** the just-completed step's output and returns structured state. It verifies and extracts — it never performs the step's work.

Each verifier returns exactly:
- `outcome`: `clean` | `finished-with-notes` | `failed`
- `state`: the artifact to hand forward (see per-agent below)
- `notes`: any leftover CRITICAL/IMPORTANT findings or failure reason, verbatim enough to act on

- **Verifier Agent A** (after Step 1 — spec review): `state` = current spec path; `notes` = open IMPORTANTs if the loop hit its cap.
- **Verifier Agent B** (after Step 4 — execution): `state` = dex status + one-line diff summary; `notes` = any failed dex tasks.
- **Verifier Agent C** (after Step 6 — PR review): `state` = PR URL; `notes` = leftover CRITICAL/IMPORTANT after 3 passes.

Keep each verifier prompt scoped to one step's output so the conductor's own context stays lean.

---

## Control Flow — Never Halt

Fully autonomous, best-effort:

- **Non-clean quality outcome** (spec-review ended at the cap with open IMPORTANTs; PR-review still has CRITICAL/IMPORTANT after 3 passes; review notes) → **record and continue** to the next step.
- **Hard failure that makes the next step impossible** (no plan written; dex produced zero diff; no PR created) → **skip the now-impossible steps and jump to the Final Report**. The conductor **never fabricates** a downstream artifact — no empty PR, no review of nothing.
- **Preflight failure** is the sole hard abort (see Step 0).

"Never halt" means *never block on quality* — it does **not** mean invent work that cannot exist.

---

## Final Report

Because nothing stops mid-run to flag problems, the final report is the contract. Always emit it at the end of any run that cleared preflight. Write it in `/handoff` style to the **OS temporary directory, never the workspace**, and also summarize it in the conversation. Include:

- **Per-step outcome** for all 6 steps: `clean` / `finished-with-notes` / `skipped (reason)` / `failed (reason)`.
- **PR:** number + URL, or an explicit note that no PR was opened and why.
- **Unresolved findings:** every leftover CRITICAL/IMPORTANT from spec-review **and** PR-review, verbatim enough to act on.
- **Failed dex tasks:** any task the dex loop could not complete.
- **Resume guidance:** what to pick up by hand, with paths to the spec, plan, branch, and PR.
````

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash tests/check-ship-it-task3.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
rm -f tests/check-ship-it-task3.sh
git add skills/ship-it/SKILL.md
git commit -m "feat(ship-it): add verifiers, never-halt control flow, final report"
```

---

### Task 4: Register the skill across manifests and docs

**Files:**
- Modify: `.claude-plugin/plugin.json` (description + keywords)
- Modify: `.claude-plugin/marketplace.json` (plugin description + keywords)
- Modify: `README.md` (add `/ship-it` to the Skills section)
- Modify: `CLAUDE.md` ("What This Is", a `### /ship-it` entry under Skills, and Key Conventions)

**Interfaces:**
- Consumes: the finished `skills/ship-it/SKILL.md`.
- Produces: a discoverable, documented skill consistent across all four registries.

- [ ] **Step 1: Write the structural test**

```bash
# tests/check-ship-it-task4.sh  (throwaway)
grep -q 'ship-it' .claude-plugin/plugin.json || { echo 'FAIL: plugin.json'; exit 1; }
grep -q 'ship-it' .claude-plugin/marketplace.json || { echo 'FAIL: marketplace.json'; exit 1; }
grep -q '`/ship-it`' README.md || { echo 'FAIL: README'; exit 1; }
grep -q 'ship-it' CLAUDE.md || { echo 'FAIL: CLAUDE.md'; exit 1; }
echo PASS
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash tests/check-ship-it-task4.sh`
Expected: FAIL: plugin.json

- [ ] **Step 3: Make the edits**

1. **`.claude-plugin/plugin.json`** — append `"conductor"` and `"pipeline"` to `keywords`, and extend `description` to mention "spec-to-PR conductor (ship-it)".

2. **`.claude-plugin/marketplace.json`** — mirror the same: add `"conductor"` to `keywords` and mention `ship-it` in the plugin `description`.

3. **`README.md`** — add this entry to the `## Skills` list (after `/fusion`, matching the existing bold-lead format):

```markdown
**`/ship-it`** — Run the whole feature pipeline from a thumbs-upped design spec to a reviewed PR in one invocation: hardens the spec with `/spec-review-codex`, writes the implementation plan, executes it via `/plan-to-dex`, opens a PR with `/commit-commands:commit-push-pr`, then runs `/review-pr` and fixes CRITICAL/IMPORTANT findings (up to 3 passes). A pure conductor — it invokes the existing units live and duplicates none of their logic. Sequential, fully autonomous, best-effort: it never halts on quality, recording any leftover findings in a final report instead. Requires the `codex` and `dex` CLIs plus the `pr-review-toolkit` and `commit-commands` plugins.
```

4. **`CLAUDE.md`** — three edits:
   - In **"What This Is"**, add a sentence noting `/ship-it` chains the existing units into one autonomous spec→PR pipeline.
   - Add a `### /ship-it` subsection under `## Skills` summarizing: pure conductor, 6-step sequential pipeline, never-halt policy, three boundary verifiers, final report to temp dir, preflight as sole hard abort.
   - Add to `## Key Conventions`:
     - `- /ship-it is a pure conductor — it invokes spec-review-codex, writing-plans, plan-to-dex, /commit-commands:commit-push-pr, and /review-pr LIVE and duplicates none of their logic`
     - `- /ship-it is best-effort and never halts on quality; the only hard abort is a failed preflight; a hard failure that makes the next step impossible skips downstream steps and jumps to the final report — it never fabricates a downstream artifact (no empty PR)`
     - `- /ship-it keeps no state on disk except the final report, which is written /handoff-style to the OS temp dir, never the workspace`

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash tests/check-ship-it-task4.sh`
Expected: PASS

- [ ] **Step 5: Validate JSON did not break**

Run: `python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); json.load(open('.claude-plugin/marketplace.json')); print('JSON OK')"`
Expected: `JSON OK`

- [ ] **Step 6: Commit**

```bash
rm -f tests/check-ship-it-task4.sh
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md CLAUDE.md
git commit -m "docs(ship-it): register skill in manifests, README, and CLAUDE.md"
```

---

### Task 5: Quality gate via skill-reviewer

**Files:**
- Modify: `skills/ship-it/SKILL.md` (apply review fixes, if any)

**Interfaces:**
- Consumes: the complete skill + registration.
- Produces: a reviewed, corrected skill ready to use.

- [ ] **Step 1: Dispatch the reviewer**

Dispatch the `plugin-dev:skill-reviewer` agent at `skills/ship-it/SKILL.md`. Ask it to check: description triggers effectiveness, instruction clarity, that the conductor never duplicates unit logic, and that the never-halt policy reads unambiguously.

- [ ] **Step 2: Triage findings**

List the reviewer's findings. Apply fixes for anything that affects trigger reliability, correctness, or the never-halt/never-fabricate contract. Skip purely stylistic nits that conflict with the repo's existing skill voice.

- [ ] **Step 3: Re-run all structural checks**

Run the four checks from Tasks 1-4 (re-create them inline if needed) to confirm fixes did not remove a required element.
Expected: all PASS.

- [ ] **Step 4: Commit (only if changes were made)**

```bash
git add skills/ship-it/SKILL.md
git commit -m "fix(ship-it): apply skill-reviewer findings"
```

---

## Self-Review

**Spec coverage** (design §-by-§ → task):
- §2 inputs/preconditions/preflight → Task 1 (Step 0).
- §2 pipeline table + per-step + branch ordering → Task 2.
- §2 boundary verifiers → Task 3.
- §3 never-halt control flow → Task 3.
- §4 final report contract → Task 3.
- §5 components/boundaries (conductor reuses units live) → enforced in Global Constraints + Task 1 body + Task 4 CLAUDE.md conventions.
- §6 out-of-scope (no Workflow, no merge, no state files) → respected; nothing in any task adds them.
- Discoverability (not in design but required by repo convention) → Task 4.
- Quality → Task 5.
No gaps found.

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every step shows the actual file content or exact command.

**Type/name consistency:** "Verifier Agent A/B/C" used identically in Task 2 references and Task 3 definitions; `feat/<spec-slug>` branch rule consistent; step headings (`## Step N: ...`) match between the Task 2 body and the Task 3 grep assertions.
