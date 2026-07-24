---
name: ship-it
description: "Use when a thumbs-upped design spec is ready and you want the whole spec-to-PR pipeline to run autonomously — hardens the spec, writes the plan, executes it via dex, opens a PR, runs PR review, and closes with an architect completeness review — in one invocation. Triggers on: ship it, ship-it, run the pipeline, spec to PR, autonomous feature pipeline, conductor."
user-invocable: true
---

# Ship-It Conductor

Run the full feature pipeline from a thumbs-upped design spec to a reviewed pull request, autonomously, in one invocation. This skill is a **pure conductor**: it sequences existing units and owns the transitions between them. It duplicates none of their logic — each unit is invoked **live**, so improvements to those units are always picked up.

**Pipeline (sequential):** harden spec → write plan → resolve branch → execute → open PR → review loop → architect review.

**Policy:** fully autonomous, best-effort, **never halt on quality**. The only hard abort is a failed preflight. A non-clean *quality* outcome (open IMPORTANTs, review notes) is recorded and the chain continues. A hard failure that makes the next step *impossible* (e.g. zero code produced → nothing to commit) skips the now-impossible steps and jumps to the final report — it never fabricates a downstream artifact.

**Underlying units (invoked live, never reimplemented):** `spec-review-codex`, `writing-plans`, `plan-to-dex`, `architect-review-pr`, and the `/review-pr` panel (all invoked live — `/review-pr` is run *inside* the Step 6 subagent), plus the `/commit-commands:commit-push-pr` slash command. (Step 6 does **not** use the built-in `/code-review` — that skill is flagged `disable-model-invocation` and cannot be called programmatically from an autonomous run; `/review-pr` has no such flag and runs the full specialized-agent panel.)

---

## Step Isolation

The heavy steps (1, 2, 4, 6) emit a lot of output — codex review iterations, the full plan, dex `apply`/`review` logs across every task, and the `/review-pr` panel's finding-by-finding trace. To keep that out of the conductor's context, **Steps 1, 2, 4, and 6 run as subagents**: a subagent (the `Agent` tool) does the step's work *inside its own context*, absorbs all the raw output, and returns **only** the structured contract (`outcome` / `state` / `notes`). The conductor's context never holds the raw logs. (Steps 1/2/4 invoke the step's Skill inside the subagent — verified that an `Agent` subagent can call the `Skill` tool; Step 6's subagent runs the `/review-pr` panel and then applies the CRITICAL/IMPORTANT fixes itself.)

Steps 3, 5, 7 run in the main loop: Step 3 is two git commands (no context cost), Step 5 is outward-facing and cheap (you want PR creation visible), and Step 7's `architect-review-pr` dispatches its own fresh-context subagent, so the deep repo tracing already stays out of the conductor's context. Step 6's fix loop (commit/push between passes) is driven by the conductor in the main loop, but each review-and-fix pass is a subagent whose contract *is* the leftover-findings report — no separate boundary verifier is needed. Because `/review-pr` itself launches analyzer agents via the `Task` tool, the Step 6 subagent may nest agents one level deeper; if this harness disallows a subagent spawning its own subagents, the subagent runs the review aspects inline in its own context instead (same findings, lower parallelism) — see its prompt.

---

## The Job

1. Preflight (fail fast)
2. Step 1 — Harden the spec via `spec-review-codex`
3. Step 2 — Write the implementation plan via `writing-plans` (from the *hardened* spec)
4. Step 3 — Resolve a feature branch
5. Step 4 — Execute via `plan-to-dex` (includes its final Opus review)
6. Step 5 — Open the PR via `/commit-commands:commit-push-pr`
7. Step 6 — Review + fix loop: a subagent runs the `/review-pr` panel and applies the CRITICAL/IMPORTANT fixes
8. Step 7 — Architect completeness review via `architect-review-pr` (report-only)
9. Emit the final report

Pipeline state (spec path, plan path, branch, PR number, leftover findings) lives in **conversation memory and the subagent hand-offs** (the execute-and-report and review-and-fix subagents return — the same three-field contract) — never written to the workspace. The only persisted artifacts are the final report and Step 7's architect review report (both in the OS temp dir).

---

## Step 0: Preflight

Run these checks **before any mutation**. Preflight failure is the **only** hard abort; once past it, the never-halt policy governs.

1. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; required by spec-review-codex and plan-to-dex."
2. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`."
3. **`pr-review-toolkit` plugin present:** the `/review-pr` command file must exist on disk — `find ~/.claude/plugins -path '*commands/review-pr.md' -print -quit | grep -q .` — else STOP: "pr-review-toolkit plugin not installed; required for the Step 6 review." (Same disk pre-check rationale as below: a slash command's resolvability can't be tested without invoking it, and the early abort avoids running the whole pipeline only to fail at the review step.)
4. **`commit-commands` plugin present:** the `/commit-commands:commit-push-pr` command file must exist on disk — `find ~/.claude/plugins -path '*commands/commit-push-pr.md' -print -quit | grep -q .` — else STOP: "commit-commands plugin not installed; required to open the PR." (A pre-check on disk is used because a slash command's resolvability cannot be tested without invoking it, and the early abort avoids running the whole pipeline only to fail at the PR step.)
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
| 6 | Review loop | subagent runs `/review-pr` + applies fixes | clean, or capped at 3 passes | leftover findings |
| 7 | Architect review | `Skill(architect-review-pr)` | report written (report-only) | architect findings |

**Isolation:** Steps 1, 2, 4, 6 run as subagents (raw output stays in the subagent); Steps 3, 5, 7 run in the main loop, and Step 6's commit/push fix loop is driven by the conductor around its per-pass review-and-fix subagent (see Step Isolation).

---

## Step 1: Harden the Spec

Dispatch an execute-and-report subagent (see "Step Subagents") that runs `Skill(spec-review-codex)` on the spec resolved in preflight — letting its full 3-iteration fix loop run — and returns the contract: `outcome` is `clean` / `finished-with-notes` / `failed` (a PASS maps to `clean`; an open-IMPORTANTs cap to `finished-with-notes`), `state` = the current (possibly rewritten) spec path. Record it; **continue regardless** (never halt on quality).

## Step 2: Write the Plan

Dispatch an execute-and-report subagent that runs `Skill(writing-plans)` on the **hardened** spec from Step 1 and returns the plan path as `state`. This is the earliest generative step — do not re-brainstorm or re-interview. `writing-plans` writes to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`. After the subagent returns, the conductor confirms the file exists on disk: `test -f <plan-path>`. If no plan file exists on disk (hard failure), skip to the final report (Steps 3-6 are impossible without a plan).

## Step 3: Resolve the Branch

`plan-to-dex` refuses `main`/`master`. Get the current branch (`git rev-parse --abbrev-ref HEAD`):
- If already on a feature branch, reuse it.
- Else create one from the spec filename slug: `git switch -c feat/<spec-slug>`.

Record the branch name.

## Step 4: Execute

Dispatch an execute-and-report subagent (see "Step Subagents") that runs `Skill(plan-to-dex)` with the plan path from Step 2 — letting the dex `apply`/`review` loop run to completion, including its own final Opus review — and returns the contract: `state` = dex status + a one-line diff summary; `notes` = any failed dex tasks. This step emits the most output of any in the pipeline, so the dex logs staying in the subagent's context (not the conductor's) is the biggest isolation win.

**`dex apply` is long-running** — it routinely exceeds the 10-minute foreground Bash ceiling. The subagent MUST run plan-to-dex's poll-to-completion loop (re-run `dex apply` foreground, max timeout, until all `.dex/plan.md` checkboxes are `[x]` or dex reports terminal) **inside its own invocation**. It MUST NOT background `dex apply` and return — a subagent's background processes are reaped on return, so the apply dies and only the dex setup commit lands. See the anti-yield guard in the subagent prompt below.

**Post-step zero-diff check:** after the subagent returns, the conductor checks the repo **in its own shell** — never from the subagent's `state` summary — by running `git status --porcelain` and inspecting `git log` for dex commits. If dex produced **zero diff** (no working-tree changes and no dex commits), there is nothing to commit → skip Steps 5-6 and jump to the final report. Do not open an empty PR. Verifying against git directly (not the summary) is what stops a mis-summary from fabricating a PR.

## Step 5: Open the PR

Run the `/commit-commands:commit-push-pr` slash command to commit, push the branch, and open the PR. Capture the PR number and URL from its output. If no PR is created (hard failure), skip Step 6 and jump to the final report.

## Step 6: Review Loop

The built-in `/code-review` **cannot** be invoked from an autonomous run (it is flagged `disable-model-invocation`). Instead, each pass dispatches one **review-and-fix subagent** (see "Step Subagents") that runs the whole `/review-pr` panel against the PR, then applies **only** the CRITICAL and IMPORTANT findings to the working tree (leaving ADVISORY/MINOR). The subagent does **not** commit; the conductor owns the commit/push loop so the fixes land as real branch commits.

Loop, up to **3 passes**:
1. Dispatch the review-and-fix subagent, giving it the PR number/URL from Step 5. The explicit PR target matters: after Step 5's push, the branch's default review range (`@{upstream}...HEAD`) is empty, so `/review-pr` reviews the PR's full diff vs its base, not that empty range.
2. If the subagent **applied no fixes this pass** → exit the loop (an unchanged tree only re-yields the same result — leftover ADVISORY/MINOR or deliberately-skipped findings alone are terminal, not a reason to re-review).
3. Otherwise the conductor commits and pushes the applied fixes, then re-dispatches (next pass). Findings the subagent **left** (ADVISORY/MINOR, or a CRITICAL/IMPORTANT it judged false-positive or out of diff scope) are recorded, not re-litigated.

After 3 passes, stop even if findings remain. The subagent's returned contract already carries the leftover findings (file:line — summary, with severity) for the final report — no separate boundary verifier runs.

## Step 7: Architect Review

Run `Skill(architect-review-pr)` against the branch — the completeness & wiring pass ("is this actually done and integrated?") that complements Step 6's line-level review. No inputs beyond the branch: it scopes findings to the branch diff vs base on its own. It runs in the main loop (it already dispatches its own fresh-context subagent — see Step Isolation) and it is **report-only**: the conductor records the report path and its ranked findings (Unwired / Missing / Incomplete / Bug-edge / Risk) verbatim enough to act on, fixes nothing, and continues to the final report (never halt on quality).

Because it reviews the **branch diff**, not the PR object, it runs even when Step 5 failed to open a PR — only a zero diff from Step 4 skips it.

---

## Step Subagents

Every subagent — the three execute-and-report subagents (Steps 1/2/4) and the review-and-fix subagent (Step 6, one dispatch per pass) — returns the same three-field contract:

- `outcome`: `clean` | `finished-with-notes` | `failed`
- `state`: the artifact to hand forward (per-step below)
- `notes`: any leftover CRITICAL/IMPORTANT findings or failure reason, verbatim enough to act on (empty if none)

**Per-step `state`:**
- **Step 1 — spec review:** `state` = current (possibly rewritten) spec path; `notes` = open IMPORTANTs if the loop hit its cap.
- **Step 2 — plan:** `state` = plan path.
- **Step 4 — execution:** `state` = dex status + one-line diff summary; `notes` = any failed dex tasks.
- **Step 6 — PR review:** `state` = PR URL; `notes` = the CRITICAL/IMPORTANT findings applied this pass, plus leftover findings (ADVISORY/MINOR or a CRITICAL/IMPORTANT left unfixed) — each as `file:line — summary [severity]`. The conductor reads whether any fixes were applied to decide whether to commit/push and re-dispatch.

### Execute-and-report subagent prompt (Steps 1/2/4)

The subagent runs the step AND returns the contract — the raw output stays in *its* context:

> You are executing one step of an autonomous pipeline. Invoke `Skill(<step-skill>)` with these inputs: <inputs>. Let it run to completion. **You MUST NOT return until the step reaches a terminal state.** If the step launches a long-running process (e.g. `dex apply` or `dex review`, or a spec-review codex pass), poll it to completion **in THIS invocation** — returning reaps any backgrounded work and silently discards the result.
>
> **FORBIDDEN — every one of these has caused a silent failure in past runs:**
> - Never run the step's long process with `run_in_background: true`.
> - Never arm a `Monitor` / waiter / `ScheduleWakeup` to "come back later" — nothing re-invokes you after you return; the child is reaped and the work is lost.
> - Never return on an intermediate "waiting for / running in background / iteration N in progress" state.
>
> Run the step's own poll-to-completion loop **foreground** until it is genuinely done. To wait on a foreground pid, block on it directly (`wait <pid>`, or `while kill -0 <pid> 2>/dev/null; do sleep 15; done`) — never rely on any waiter or `Monitor` to resume you.
>
> **Pre-return verification (mandatory) — run these and confirm before returning; if any fails, keep looping:**
> - **No live worker:** `pgrep -fl 'dex --cli codex|codex exec'` prints nothing.
> - **Step 4 (dex) only:** `grep -c '\[ \]' .dex/plan.md` prints `0` (or dex reported a terminal `STALEMATE`/quota state you name), AND `git log --oneline` shows per-task dex commits, not just the lone `dex import` setup commit.
> - **The step's own output declares completion** (spec-review PASS/cap, plan file written, or dex loop terminal) — not "in progress".
>
> Then return **only** the three-field contract — `outcome` (`clean` | `finished-with-notes` | `failed`), `state` (<the artifact for this step>), `notes` (verbatim leftover CRITICAL/IMPORTANT or failure reason; empty if none). Do not paste the step's raw output, logs, or findings back — only the contract. If the step fails, write its full output tail to a temp file and put that path in `notes`.

### Review-and-fix subagent prompt (Step 6)

Dispatch a `general-purpose` subagent once per pass. It runs the whole `/review-pr` panel, applies the CRITICAL/IMPORTANT fixes, and returns the contract — the raw finding-by-finding trace stays in *its* context:

> You are the reviewer-fixer for one pass of an autonomous pipeline. Run the `/review-pr` slash command (`pr-review-toolkit:review-pr`) against PR <PR# / URL> and let its full specialized-agent panel complete. Review the PR's full diff versus its base branch, not the empty `@{upstream}...HEAD` range. (`/review-pr` launches its analyzers via the `Task` tool; if this environment does not let you, as a subagent, spawn your own subagents, then perform each of `/review-pr`'s review aspects yourself, inline in this context — do not skip the review.)
>
> Then fix the reported findings: apply a fix to the working tree for **every CRITICAL and IMPORTANT** finding, leaving ADVISORY/MINOR untouched. Skip a CRITICAL/IMPORTANT only if you judge it a false positive or outside the PR diff — and record why. Stay in scope: no behavior changes beyond each fix, nothing outside the PR diff. **Do NOT commit or push** — the conductor commits your applied fixes.
>
> Then return **only** the three-field contract — `outcome` (`clean` if the panel found no CRITICAL/IMPORTANT | `finished-with-notes` if you applied fixes or left findings | `failed`), `state` (the PR URL), `notes`: list each finding you **applied** and each you **left** as `file:line — summary [severity]` (empty only if the panel found nothing). Do not paste the raw review trace or diffs back — only the contract.

Keep every subagent prompt scoped to one step so the conductor's own context stays lean.

---

## Control Flow — Never Halt

Fully autonomous, best-effort:

- **Non-clean quality outcome** (spec-review ended at the cap with open IMPORTANTs; PR-review still has findings after 3 passes; architect findings; review notes) → **record and continue** to the next step.
- **Hard failure that makes the next step impossible** (no plan written; dex produced zero diff; no PR created) → **skip the now-impossible steps and jump to the Final Report**. The conductor **never fabricates** a downstream artifact — no empty PR, no review of nothing. Only Step 6 depends on the PR: if the PR fails but a diff exists, Step 7 still runs (it reviews the branch, not the PR).
- **Preflight failure** is the sole hard abort (see Step 0).

"Never halt" means *never block on quality* — it does **not** mean invent work that cannot exist.

---

## Final Report

Because nothing stops mid-run to flag problems, the final report is the contract. Always emit it at the end of any run that cleared preflight. Write it in `/handoff` style to the **OS temporary directory, never the workspace**, and also summarize it in the conversation. Include:

- **Per-step outcome** for all 7 steps: `clean` / `finished-with-notes` / `skipped (reason)` / `failed (reason)`.
- **PR:** number + URL, or an explicit note that no PR was opened and why.
- **Unresolved findings:** every leftover CRITICAL/IMPORTANT from spec-review, every unfixed/skipped PR-review finding, **and** the architect review's ranked findings, verbatim enough to act on.
- **Failed dex tasks:** any task the dex loop could not complete.
- **Resume guidance:** what to pick up by hand, with paths to the spec, plan, branch, PR, and architect review report.
