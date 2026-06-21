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

## Execution Modes

The heavy Skill steps (1, 2, 4) emit a lot of output — codex review iterations, the full plan, dex `apply`/`review` logs across every task. How that output reaches the conductor depends on the mode:

A **boundary verifier** is a subagent that extracts the three-field contract from a *completed* step without performing any of the step's work. The two modes differ in whether a subagent also *runs* the heavy steps:

- **Isolated mode:** dispatch Steps 1, 2, and 4 as **execute-and-report subagents** — a subagent (the `Agent` tool) invokes the step's Skill *inside its own context*, absorbs all the raw output, and returns **only** the structured contract (`outcome` / `state` / `notes`). The conductor's context never holds the raw logs. In this mode the Step 1/Step 4 boundary verifiers (A/B) are *folded into* the subagent's return — they are not separate dispatches.
- **Monitored mode:** invoke Steps 1, 2, 4 as `Skill(...)` in the **main conversation** so a human can watch dex churn and catch a wrong guess live, then dispatch the boundary verifier (A for Step 1, B for Step 4) afterward to extract state. Step 2 gets no verifier in this mode — the conductor reads the plan path from the Skill's output directly. Costs main context; buys observability.

Steps 3, 5, 6 always run in the main loop regardless of mode: Step 3 is two git commands (no context cost), Step 5 is outward-facing and cheap (you want PR creation visible), and Step 6's `/review-pr` already spawns its own specialized agents — wrapping it in another subagent would nest agents and hide the findings you are monitoring. Verifier C stays a post-step dispatch in both modes.

**Default: monitored.** Unless the user explicitly requests isolated mode (or a long, trusted run where context preservation dominates), run in monitored mode.

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

Pipeline state (spec path, plan path, branch, PR number, leftover findings) lives in **conversation memory and the subagent hand-offs** (the execute-and-report subagent or boundary-verifier returns — the same three-field contract) — never written to the workspace. The only persisted artifact is the final report (written to the OS temp dir).

---

## Step 0: Preflight

Run these checks **before any mutation**. Preflight failure is the **only** hard abort; once past it, the never-halt policy governs.

1. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; required by spec-review-codex and plan-to-dex."
2. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`."
3. **`pr-review-toolkit` plugin present:** the `/review-pr` command file must exist on disk — `find ~/.claude/plugins -path '*commands/review-pr.md' -print -quit | grep -q .` — else STOP: "pr-review-toolkit plugin not installed; required for the PR review step." (A pre-check on disk is used because a slash command's resolvability cannot be tested without invoking it, and the early abort avoids running the whole pipeline only to fail at the PR step.)
4. **`commit-commands` plugin present:** the `/commit-commands:commit-push-pr` command file must exist on disk — `find ~/.claude/plugins -path '*commands/commit-push-pr.md' -print -quit | grep -q .` — else STOP: "commit-commands plugin not installed; required to open the PR."
5. **Spec located:** the argument is a path to a design spec; if omitted, find the newest `docs/superpowers/specs/*-design.md` and confirm it with the user before starting. If no file matches that glob, STOP and ask the user to provide the spec path explicitly.

On any STOP, print the missing item plus its remedy and exit without touching the repo.

---

## Pipeline Overview

| # | Step | Unit invoked | Success bar | State handed forward |
|---|------|-------------|-------------|----------------------|
| 1 | Harden spec | `Skill(spec-review-codex)` | PASS, or 3-iteration cap | (possibly rewritten) spec path |
| 2 | Write plan | `Skill(writing-plans)` | plan file written | plan path |
| 3 | Resolve branch | conductor itself | on a non-`main`/`master` branch | branch name |
| 4 | Execute | `Skill(plan-to-dex)` (incl. Opus review) | dex loop completes | dex status + diff summary |
| 5 | Open PR | `/commit-commands:commit-push-pr` | PR created | PR number / URL |
| 6 | Review loop | `/review-pr` + fix | clean, or capped at 3 attempts | leftover findings |

**Mode legend:** Steps 1, 2, 4 run as execute-and-report subagents in **isolated** mode (or in the main loop with a trailing verifier in **monitored** mode); Steps 3, 5, 6 always run in the main loop (see Execution Modes).

---

## Step 1: Harden the Spec

Run `Skill(spec-review-codex)` on the spec resolved in preflight; let it run its full 3-iteration fix loop.

- **Isolated mode:** dispatch an execute-and-report subagent (see "Step Subagents") that invokes the Skill and returns the contract directly — `state` = the current (possibly rewritten) spec path.
- **Monitored mode:** invoke the Skill in the main loop, then dispatch **Verifier Agent A** to read its outcome.

Either way the result is: `clean` / `finished-with-notes` / `failed` (a PASS maps to `clean`; an open-IMPORTANTs cap to `finished-with-notes`), plus the current spec path. Record it; **continue regardless** (never halt on quality).

## Step 2: Write the Plan

Run `Skill(writing-plans)` on the **hardened** spec from Step 1 (isolated mode: inside an execute-and-report subagent; monitored mode: main loop, **no trailing verifier** — the conductor reads the plan path from the Skill's output directly). This is the earliest generative step — do not re-brainstorm or re-interview. `writing-plans` writes to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` and reports the path; the subagent (or the conductor) returns that path as `state`. Confirm the file exists on disk: `test -f <plan-path>`. If no plan file exists on disk (hard failure), skip to the final report (Steps 3-6 are impossible without a plan).

## Step 3: Resolve the Branch

`plan-to-dex` refuses `main`/`master`. Get the current branch (`git rev-parse --abbrev-ref HEAD`):
- If already on a feature branch, reuse it.
- Else create one from the spec filename slug: `git switch -c feat/<spec-slug>`.

Record the branch name.

## Step 4: Execute

Run `Skill(plan-to-dex)` with the plan path from Step 2; let it run the dex `apply`/`review` loop to completion, including its own final Opus review. This step emits the most output of any in the pipeline, so isolated mode benefits most here.

- **Isolated mode:** dispatch an execute-and-report subagent (see "Step Subagents") that invokes the Skill and returns the contract — `state` = dex status + a one-line diff summary; `notes` = any failed dex tasks. The dex logs stay in the subagent's context, not the conductor's.
- **Monitored mode:** invoke the Skill in the main loop, then dispatch **Verifier Agent B** for the same report.

**Post-step zero-diff check (both modes):** the conductor checks the repo **in its own shell** — never from the subagent's `state` summary — by running `git status --porcelain` and inspecting `git log` for dex commits. If dex produced **zero diff** (no working-tree changes and no dex commits), there is nothing to commit → skip Steps 5-6 and jump to the final report. Do not open an empty PR. Verifying against git directly (not the summary) is what stops a mis-summary from fabricating a PR.

## Step 5: Open the PR

Run the `/commit-commands:commit-push-pr` slash command to commit, push the branch, and open the PR. Capture the PR number and URL from its output. If no PR is created (hard failure), skip Step 6 and jump to the final report.

## Step 6: Review Loop

Loop, up to **3 passes**:
1. Run the `/review-pr` slash command against the PR.
2. If it reports no CRITICAL and no IMPORTANT findings → the PR is clean; exit the loop.
3. Otherwise the conductor itself fixes **only** the CRITICAL and IMPORTANT findings directly in this conversation (not via a sub-skill), leaving ADVISORY/MINOR, then commits, pushes, and re-reviews.

After 3 passes, stop even if findings remain. Dispatch **Verifier Agent C** to collect any leftover CRITICAL/IMPORTANT for the final report.

---

## Step Subagents & Boundary Verifiers

Every subagent here — whether it *runs* a step (isolated mode) or only *verifies* one (monitored mode, and Step 6 in both modes) — returns the same three-field contract:

- `outcome`: `clean` | `finished-with-notes` | `failed`
- `state`: the artifact to hand forward (per-step below)
- `notes`: any leftover CRITICAL/IMPORTANT findings or failure reason, verbatim enough to act on (empty if none)

**Per-step `state`:**
- **Step 1 — spec review** (isolated: execute-and-report subagent; monitored: Verifier Agent A): `state` = current spec path; `notes` = open IMPORTANTs if the loop hit its cap.
- **Step 2 — plan** (isolated: execute-and-report subagent; monitored: conductor inline): `state` = plan path.
- **Step 4 — execution** (isolated: execute-and-report subagent; monitored: Verifier Agent B): `state` = dex status + one-line diff summary; `notes` = any failed dex tasks.
- **Step 6 — PR review** (Verifier Agent C, both modes): `state` = PR URL; `notes` = leftover CRITICAL/IMPORTANT after 3 passes.

### Execute-and-report subagent prompt (isolated mode, Steps 1/2/4)

The subagent runs the step AND returns the contract — the raw output stays in *its* context:

> You are executing one step of an autonomous pipeline. Invoke `Skill(<step-skill>)` with these inputs: <inputs>. Let it run to completion. Then return **only** the three-field contract — `outcome` (`clean` | `finished-with-notes` | `failed`), `state` (<the artifact for this step>), `notes` (verbatim leftover CRITICAL/IMPORTANT or failure reason; empty if none). Do not paste the step's raw output, logs, or findings back — only the contract. If the step fails, write its full output tail to a temp file and put that path in `notes`.

### Verifier subagent prompt (monitored mode, and Step 6)

The verifier reads a completed step's output and extracts state — it never performs the step's work:

> You are a boundary verifier. Read **only** the step output provided below — do not perform any work or run any commands beyond what is needed to read state. Return exactly three fields: `outcome` (`clean` | `finished-with-notes` | `failed`), `state` (<the artifact to extract>), `notes` (verbatim leftover CRITICAL/IMPORTANT or failure reason; empty if none).
>
> Step output:
> {paste the just-completed step's output here}

If the step ran in the main loop and its output is large, instruct the verifier to read it from the conversation turn above rather than pasting a block.

Keep every subagent prompt scoped to one step so the conductor's own context stays lean.

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
