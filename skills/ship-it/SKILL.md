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
