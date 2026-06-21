# Design: `/ship-it` — autonomous spec→PR conductor

**Date:** 2026-06-21
**Status:** Approved (brainstorming) — pending implementation plan
**Topic:** A new conductor skill that automates the manual, sequential pipeline the user runs today (spec review → plan → execute → PR → PR review) so the whole chain runs from one invocation instead of launching each step by hand.

---

## 1. Purpose & Context

Today the user hardens a feature by hand, launching four units one after another and copying state between them:

1. `/spec-review-codex` (3 iterations + fixes)
2. `/plan-to-dex` (all dex phases + the final Opus review)
3. `/commit-commands:commit-push-pr` (open the PR)
4. `/review-pr` (review + fix CRITICAL/IMPORTANT)

The toil is not in running any single step — each is already a working skill/command — it is in **launching them in order and threading state between them** (which plan, which branch, which PR). `/ship-it` removes exactly that toil.

It is a **pure conductor**: it sequences the existing units, verifies each transition, and reports. It duplicates **no** logic from the underlying units — they remain the single source of truth, invoked live (so edits to `spec-review-codex`, `plan-to-dex`, etc. are always picked up, never snapshotted).

### Why a conductor, not a Workflow

The four units are main-conversation-loop skills/commands. The `Workflow` (ultracode) tool spawns headless background subagents that cannot call the `Skill` tool or replay a slash command — re-implementing each unit inside agent prompts would duplicate four maintained skills and lose the interactive `dex apply`/`review` and spec-fix loops. The pipeline is also inherently **sequential** (each step gated on the last), so it gains nothing from Workflow's fan-out while paying its costs (background detachment, copy-paste drift). A main-loop conductor reuses the units live and stays in the foreground where the interactive loops want to be.

### Relationship to the original idea

The user's first framing was "a workflow with at least one agent per step." Refined during brainstorming: a literal agent-per-step does not fit, because the units run *in the main loop*. Subagents are retained where they earn their keep — as **boundary verifiers** at the three block edges (after spec-review, after execution, after PR-review) that extract structured state and detect "finished-but-not-clean" without bloating the conductor's context.

---

## 2. Architecture

A single user-invocable skill `/ship-it` runs a **sequential, best-effort, never-halt** pipeline. The conductor owns the *transitions* (success detection, state extraction, branch resolution, the never-halt decision); the units own the *work*.

### Inputs & preconditions

- **Argument:** path to the thumbs-upped design spec. If omitted, locate the newest `docs/superpowers/specs/*-design.md` and confirm with the user before starting.
- **Entry assumption:** the spec exists and has the user's thumbs-up; the **plan does not yet exist** — the conductor generates it from the *hardened* spec (step 2), so the plan is never built from a pre-review spec.
- **Preflight (fail fast, before any mutation):** verify `codex` CLI, `dex` CLI, and the `pr-review-toolkit` + `commit-commands` plugins are all present. Any missing → abort with setup guidance (same abort-with-guidance pattern as `/orbstack-compatible`). Preflight is the **only** thing that aborts the run; once past it, the never-halt policy governs.

### The pipeline

| # | Step | Unit invoked | Success bar | State handed forward |
|---|------|-------------|-------------|----------------------|
| 1 | Harden spec | `Skill(spec-review-codex)` | PASS, or 3-iteration cap reached | (possibly rewritten) spec path |
| 2 | Write plan | `Skill(writing-plans)` | plan file written | plan path |
| 3 | Resolve branch | conductor itself | on a non-`main`/`master` feature branch | branch name |
| 4 | Execute | `Skill(plan-to-dex)` (incl. final Opus review) | dex `apply`/`review` loop completes | changed files / dex status |
| 5 | Open PR | `/commit-commands:commit-push-pr` | PR created | PR number / URL |
| 6 | Review loop | `/review-pr` + fix CRITICAL/IMPORTANT | clean, or 3 passes reached | leftover findings |

**Branch ordering (step 3):** sits *between* plan and execution because `plan-to-dex` refuses to run on `main`/`master`. If already on a feature branch, reuse it; otherwise create `feat/<spec-slug>`. The PR is not opened until step 5.

**PR review loop (step 6):** re-review after each fix pass; stop when no CRITICAL/IMPORTANT remain **or** after 3 passes, whichever comes first. Leftovers are recorded for the final report. Mirrors `spec-review-codex`'s 3-iteration cap.

### Boundary verifier agents

Dispatched after steps **1, 4, and 6** (the three block edges). Each is a small subagent that reads the just-completed step's output and returns **structured state**:

- did the step meet its success bar? (clean / finished-with-notes / failed)
- the artifact to hand forward (spec path / dex status+diff summary / leftover findings)

They keep the conductor's main context lean and make the never-halt decision explicit rather than inferred from scrolled-past output. They do **not** perform the step's work — only verify and extract.

---

## 3. Control flow — best-effort, never halt

The user chose **fully autonomous, best-effort, never halt on quality**:

- A **non-clean quality outcome** (spec-review ended at the cap with open IMPORTANTs; PR-review still has CRITICAL/IMPORTANT after 3 passes; review notes) → **record and continue** to the next step.
- A **hard failure that makes the next step impossible** (e.g. dex produces zero diff → nothing to commit → no PR to review) → this is not a quality issue and cannot be pushed through. The conductor **skips the now-impossible downstream steps and jumps straight to the final report**. It never fabricates a downstream artifact (no empty PR, no review of nothing).
- Preflight failure is the sole hard abort (see §2).

So "never halt" means *never block on quality*; it does not mean *invent work that cannot exist*. Every deviation — leftover findings, skipped steps, failed dex tasks — surfaces in the final report.

---

## 4. Final report — the deliverable contract

Because nothing stops to flag problems mid-run, the **final report is the contract**. The conductor always emits, at the end of any run that cleared preflight:

- **Per-step outcome:** clean / finished-with-notes / skipped (with reason) / failed (with reason), for all 6 steps.
- **PR:** number + URL (or an explicit note that no PR was opened, and why).
- **Unresolved findings:** every leftover CRITICAL/IMPORTANT from spec-review **and** from PR-review, verbatim enough to act on.
- **Failed dex tasks:** any task the dex loop could not complete.
- **Resume guidance:** what the user should pick up by hand, written in the `/handoff` style and saved to a file (OS temp dir, never the workspace) so the leftovers are recoverable.

---

## 5. Components & boundaries

| Unit | Purpose | Depends on |
|------|---------|-----------|
| `/ship-it` SKILL.md | Sequence the 6 steps, own transitions, enforce never-halt, emit final report | the 4 underlying units + `writing-plans` + 3 verifier subagents |
| Verifier subagent (×3) | Read one step's output, return structured pass/notes/fail + extracted state | the step's emitted output only |
| Underlying units (unchanged) | Do the actual spec-review / planning / execution / PR / PR-review work | their own CLIs (`codex`, `dex`, `gh`) |

The conductor can be understood without reading any unit's internals: it only needs each unit's **success signal** and **output location**. A unit's internals can change freely as long as that contract holds.

---

## 6. Out of scope (YAGNI)

- **No parallelism / Workflow fan-out** — the chain is sequential (see §2).
- **No re-interviewing or re-brainstorming** — the spec arrives thumbs-upped; `writing-plans` is the earliest generative step.
- **No merge / deploy** — the pipeline ends at a reviewed PR; merging stays manual.
- **No per-step pause/checkpoint UI** — fully autonomous by decision; control is exercised by reading the final report and resuming leftovers.
- **No state files on disk** — pipeline state (plan path, branch, PR number, findings) lives in conversation memory + the verifier hand-offs, like `swarm-execute`. The only written artifact is the final report.

---

## 7. Open questions

None blocking. Naming, entry point, autonomy, halt policy, PR-review loop bound, and verifier retention were all settled during brainstorming.
