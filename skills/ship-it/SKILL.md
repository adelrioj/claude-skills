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

The heavy steps (1, 2, 4, 6) emit a lot of output — codex review iterations, the full plan, dex `apply`/`review` logs across every task, and the `/review-pr` panel's finding-by-finding trace. To keep that out of the conductor's context, **Steps 1, 2, 4, and 6 run as subagents**: a subagent (the `Agent` tool) does the step's work *inside its own context*, absorbs all the raw output, and hands back **only** the structured contract (`outcome` / `state` / `notes`). The conductor's context never holds the raw logs. (Steps 1/2/4 invoke the step's Skill inside the subagent — verified that an `Agent` subagent can call the `Skill` tool; Step 6's subagent runs the `/review-pr` panel and then applies the CRITICAL/IMPORTANT fixes itself.)

**The contract is a file, not a return message.** A subagent's final message is a *single-delivery, unrecoverable* channel: in observed runs, subagents completed their work and then ended with a bare `{"type":"idle_notification","idleReason":"available"}` and no contract — 5 of 5 steps in one run, 4 of 5 in the run before. A direct `SendMessage` re-ask recovered **none** of them. So every subagent is given a conductor-chosen absolute path and **writes its contract there, incrementally, before returning**; the conductor reads the file and treats the return message as corroboration. The one contract that ever survived this failure survived because a subagent had written it to a file mid-run. See "Step Subagents" for the mechanics and "Control Flow" for what a missing contract means.

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

Pipeline state (spec path, plan path, branch, PR number, leftover findings) lives in **conversation memory plus the per-step contract files** in `$RUN_DIR` — never written to the workspace. `$RUN_DIR` is one throwaway directory in the OS temp dir, minted at preflight, holding every step contract, Step 7's architect review report, and the final report. Nothing the pipeline persists ever lands in the repo.

---

## Step 0: Preflight

Run these checks **before any mutation**. Preflight failure is the **only** hard abort; once past it, the never-halt policy governs.

1. **`codex` on PATH:** `command -v codex` — else STOP: "codex CLI not found; required by spec-review-codex and plan-to-dex."
2. **`dex` on PATH:** `command -v dex` — else STOP: "dex not found. Install: `curl -sSfL https://raw.githubusercontent.com/francescoalemanno/dex/main/install.sh | bash`."
3. **Codex tuning overrides resolve — only if the user set any.** The pipeline's review passes run at `xhigh` by default with no setup (`docs/codex-tuning.md`); the four override variables are the only thing that can be wrong here, and both backends **fail open** — `codex exec -c model_reasoning_effort=garbage` and dex's `unknown CLI "<name>"` (which still exits 0) each sail past unnoticed from inside a subagent, running the whole pipeline at the wrong tier. Validate only what the user actually set:

   ```bash
   for e in "${CODEX_EFFORT_BUILD:-}" "${CODEX_EFFORT_REVIEW:-}"; do
     case "$e" in ''|low|medium|high|xhigh) ;; *) echo "BAD codex effort: $e" ;; esac
   done
   for c in "${DEX_CLI_BUILD:-}" "${DEX_CLI_REVIEW:-}"; do
     [ -z "$c" ] && continue
     cat "${XDG_CONFIG_HOME:-$HOME/.config}/dex/config.json" .dex/config.json 2>/dev/null \
       | jq -se --arg c "$c" 'any(.[]; (.clis // {}) | has($c))' >/dev/null \
       || echo "MISSING dex cli entry: $c"
   done
   APPLY="${DEX_CLI_BUILD:-codex${CODEX_EFFORT_BUILD:+-$CODEX_EFFORT_BUILD}}"
   [ "$APPLY" = codex ] && APPLY="codex$(sed -n 's/^model_reasoning_effort *= *"\(.*\)"/ (inherits \1)/p' ~/.codex/config.toml | head -1)"
   echo "codex tiers → spec-review: ${CODEX_EFFORT_REVIEW:-xhigh} | dex apply: $APPLY | dex review: ${DEX_CLI_REVIEW:-codex-${CODEX_EFFORT_REVIEW:-xhigh}}"
   ```

   Any `BAD`/`MISSING` line → STOP naming the variable and its bad value. With nothing set the validation prints nothing, so the check costs a user who never opted in exactly one silent command. Do **not** check for `codex-xhigh` or any `codex-<effort>` entry here — `plan-to-dex` provisions those in its own Step 4, which runs later and would make an up-front check spuriously fail on a first run. The `DEX_CLI_*` loop checks only entries the user *named themselves*, which `plan-to-dex` deliberately never auto-creates.

   **The `echo` is not decoration.** It is the only place the resolved tiers ever become visible: `plan-to-dex` prints its own `Backend: apply → …, review → …` line, but it runs as a Step 4 **subagent** whose entire output is compressed to a three-field contract, so that line never reaches the user. Type the `${…:-…}` fragments literally and let the shell resolve them — never substitute a tier you assumed. Echo the line verbatim into the preflight summary and carry it into the Final Report.

   **The `inherits` lookup exists because the build tier is the one thing the fragment cannot state.** `dex apply` defaults to the stock `codex` entry, whose effort comes from `~/.codex/config.toml` — so the same pipeline builds at `low` on one machine and `xhigh` on another, and printing the entry *name* alone would hide that completely. Reading the config makes the tier explicit without pinning it (pinning build is deliberately not this pipeline's call — `docs/codex-tuning.md`). No output when the key is absent: codex's own default applies, and inventing a number here would be a guess.

4. **Required plugins installed:** `pr-review-toolkit` (Step 6's `/review-pr`), `commit-commands` (Step 5's PR), and `superpowers` (Step 2's `writing-plans`). Check the **install registry**, not the filesystem:

   ```bash
   for p in pr-review-toolkit commit-commands superpowers; do
     jq -e --arg p "$p" '[.plugins | keys[] | select(startswith($p + "@"))] | length > 0' \
       ~/.claude/plugins/installed_plugins.json >/dev/null || echo "MISSING: $p"
   done
   ```

   Any `MISSING` line → STOP naming the plugin and what it is needed for. **Do not check with `find ~/.claude/plugins -path '*commands/<cmd>.md'`** — that matches copies inside the `marketplaces/` clones and stale `cache/` versions, so it passes for *any* plugin the marketplace carries whether installed or not, converting a fast preflight abort into a late Step 2/5/6 failure. `installed_plugins.json` (keys are `<name>@<marketplace>`) is the ground truth. If that file does not exist (older Claude Code), fall back to the `find` check and note the weaker signal.

   A pre-check is used at all because a slash command's or skill's resolvability cannot be tested without invoking it, and the early abort avoids running the whole pipeline only to fail at the step that needs it. `superpowers` is easy to forget here — `writing-plans` is the one unit that is not part of this plugin, so its absence otherwise surfaces only after a full codex spec-review has already been spent.
5. **Spec located:** the argument is a path to a design spec; if omitted, find the newest `docs/superpowers/specs/*-design.md` and confirm it with the user before starting. If no file matches that glob, STOP and ask the user to provide the spec path explicitly.

On any STOP, print the missing item plus its remedy and exit without touching the repo.

**Advisory check (warn, never abort) — can the active `gh` account open the PR?**

```bash
gh repo view --json viewerPermission -q .viewerPermission
```

If it prints anything other than `ADMIN` / `MAINTAIN` / `WRITE` (or errors), print a warning up front: *"the active `gh` account lacks write access here — Step 5 will fail with `GraphQL: must be a collaborator`; switch accounts before the run, or expect a no-PR outcome."* Then **continue** — the run still produces a hardened spec, a plan, committed code on a branch, and the Step 7 architect review, so a missing PR is a skipped step, not a reason to abort. This check exists because `gh` account state is *global machine state*, invisible in the repo, and its failure otherwise surfaces an hour into the pipeline where it reads as a conductor bug. The conductor never switches accounts itself — that mutates state outside the repo and outside the user's request.

**Then mint the run directory, once.** If the harness gives this session a scratchpad directory, mint it **there** — `RUN_DIR=$(mktemp -d "<scratchpad>/ship-it-XXXXXX")` — because scratchpad writes are pre-approved, while a path under `/tmp` is neither the workspace nor the scratchpad and can require permission approval in modes short of `bypassPermissions`/`acceptEdits`. **A permission prompt inside an unattended subagent is a stall that produces no contract at all** — the exact failure this whole design exists to prevent, arriving through the door marked "safe". With no scratchpad available, fall back to `RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ship-it-XXXXXX")`; spell the template out rather than using `mktemp -d -t ship-it`, which is BSD-only (GNU `mktemp` rejects a template with no `X`s). Print it. Every step contract, the architect report, and the final report live here — **each at a path the conductor fixes up front and passes to the subagent**. Hold `$RUN_DIR` for the whole run and never re-derive it. Never locate any of these artifacts by globbing a timestamped pattern: a stale file from an earlier run on a *different* ticket satisfies the glob, and adopting it silently is worse than having no artifact at all.

---

## Pipeline Overview

| # | Step | Unit invoked | Success bar | State handed forward |
|---|------|-------------|-------------|----------------------|
| 1 | Harden spec | `Skill(claude-skills:spec-review-codex)` | PASS, or 3-iteration cap | (possibly rewritten) spec path |
| 2 | Write plan | `Skill(superpowers:writing-plans)` | plan file written | plan path |
| 3 | Resolve branch | conductor itself | on a non-`main`/`master` branch | branch name |
| 4 | Execute | `Skill(claude-skills:plan-to-dex)` (incl. Opus review) | dex loop completes | dex status + diff summary |
| 5 | Open PR | `/commit-commands:commit-push-pr` | PR created | PR number / URL |
| 6 | Review loop | subagent runs `/review-pr` + applies fixes | clean, or capped at 3 passes | leftover findings |
| 7 | Architect review | `Skill(claude-skills:architect-review-pr)` | report written (report-only) | architect findings |

**Isolation:** Steps 1, 2, 4, 6 run as subagents (raw output stays in the subagent); Steps 3, 5, 7 run in the main loop, and Step 6's commit/push fix loop is driven by the conductor around its per-pass review-and-fix subagent (see Step Isolation).

**Hand-off paths (fixed at preflight, passed in, read back):**

| Step | Contract / report path | Ground-truth predicate the conductor checks itself |
|---|---|---|
| 1 | `$RUN_DIR/step-1.contract.md` | a `/tmp/spec-review-findings-*` file (literal `/tmp`, see Step 1) **whose mtime postdates dispatch** exists |
| 2 | `$RUN_DIR/step-2.contract.md` | `test -f <plan-path>` |
| 4 | `$RUN_DIR/step-4.contract.md` | commits after `HEAD_0`, **or** working-tree changes — in both cases *excluding* the pipeline's own by-products (see Step 4) |
| 6 | `$RUN_DIR/step-6.pass-<N>.contract.md` | `git status --porcelain` **differs from the pre-dispatch snapshot** ⇒ fixes were applied this pass |
| 7 | `$RUN_DIR/architect-review.md` | `test -f` that path |

The predicate is checked **in the conductor's own shell**, never read off a subagent's summary. This is what stops a lost or wrong contract from fabricating a downstream artifact.

**Every predicate is anchored to a value captured *before* dispatch** — an mtime, a commit SHA. Record them as you go. This is not pedantry: a bare existence check (`ls spec-review-findings-*`) or a bare `git log` grep is satisfied by an artifact from a *previous run on a different ticket*, which is the same failure as globbing for a report. A predicate that can't tell this run's work from last run's is not ground truth.

**A predicate must prove the step RAN, not that it CHANGED something.** These are different, and conflating them is how a clean result gets misread as a failure: a spec review that passes on iteration 1 rewrites nothing, so "the spec was modified" would report "no work" for the *best* possible outcome and, per the fourth divergence row, skip the rest of the pipeline. Anchor on the artifact the step always produces (the findings file), and treat "the spec was rewritten" as a separate, informational signal about whether fixes were applied.

---

## Step 1: Harden the Spec

**Capture the dispatch timestamp first:** `T0=$(date +%s)`, plus the spec's own mtime (`stat -f %m <spec>` on macOS, `stat -c %Y` on Linux). Both are needed below.

Dispatch an execute-and-report subagent (see "Step Subagents") with contract path `$RUN_DIR/step-1.contract.md`, that runs `Skill(claude-skills:spec-review-codex)` on the spec resolved in preflight — letting its full 3-iteration fix loop run — and writes the contract: `outcome` is `clean` / `finished-with-notes` / `failed` (a PASS maps to `clean`; an open-IMPORTANTs cap to `finished-with-notes`), `state` = the current (possibly rewritten) spec path.

Then read the contract file and check the predicate yourself:

- **Did the review run?** A file matching **`/tmp/spec-review-findings-*`** exists with mtime **≥ `T0`**. `spec-review-codex` writes one per iteration whether it PASSes or finds problems, so this is the signal that holds in every outcome.
  - **The literal `/tmp` is not a typo — do not "normalize" it to `$TMPDIR` or `${TMPDIR:-/tmp}`.** `spec-review-codex` and `spec-review-local` both hardcode `FINDINGS_FILE="/tmp/spec-review-findings-$(date +%s).md"`, while `$TMPDIR` on macOS is `/var/folders/…/T/`. Looking in the wrong directory makes a *successful* review read as "nothing happened" — and if the contract is also lost (the exact case this design exists for), that lands on divergence row 4 and aborts Steps 2-7. Match the producer's path, not the local convention. If `spec-review-*` ever changes where it writes, this predicate changes with it.
  - The mtime bound is equally load-bearing — without it, a findings file left over from an earlier run on a different spec satisfies the check.
- **Were fixes applied?** The spec's mtime is newer than its pre-dispatch value. This is **informational only** — a PASS on the first iteration rewrites nothing, and an unchanged spec is the *best* outcome, never evidence that the step failed. Never gate control flow on it.

If the contract is missing but the review demonstrably ran, record `finished-with-notes (contract lost — spec reviewed, findings not summarized)` and carry the spec path forward unchanged. Record whatever you have; **continue regardless** (never halt on quality).

## Step 2: Write the Plan

Dispatch an execute-and-report subagent with contract path `$RUN_DIR/step-2.contract.md`, that runs `Skill(superpowers:writing-plans)` on the **hardened** spec from Step 1 and writes the plan path as `state`. This is the earliest generative step — do not re-brainstorm or re-interview. `writing-plans` writes to `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.

Read the contract, then confirm the plan on disk yourself: `test -f <plan-path>`. If the contract is missing, recover the path from the predicate — the newest of `docs/superpowers/plans/*.md` **or** `docs/plans/*.md` (superpowers moved this location at 5.1.0 and `plan-to-dex` still honors the legacy one, so a machine on an older superpowers writes to a path the new-location-only glob never finds) **whose mtime postdates this step's dispatch** — and record `finished-with-notes (contract lost — plan path recovered from disk)`. The mtime bound is what makes this recovery safe rather than a repeat of the stale-artifact bug: without it, a plan from an earlier feature is the newest match and the pipeline would go on to implement the wrong thing.

**No plan file on disk is a hard failure regardless of what the contract says.** A contract that reports a plan path which `test -f` cannot find is *not* the ordinary "predicate disagrees" case — trusting the predicate here means accepting that no plan exists, and Steps 3-6 are impossible without one. Skip to the final report. Never dispatch Step 4 with a plan path you have just proven absent.

## Step 3: Resolve the Branch

`plan-to-dex` refuses `main`/`master`. Get the current branch (`git rev-parse --abbrev-ref HEAD`):
- If already on a feature branch, reuse it.
- Else create one from the spec filename slug: `git switch -c feat/<spec-slug>`.

Record the branch name.

## Step 4: Execute

Dispatch an execute-and-report subagent (see "Step Subagents") with contract path `$RUN_DIR/step-4.contract.md`, that runs `Skill(claude-skills:plan-to-dex)` with the plan path from Step 2 — letting the dex `apply`/`review` loop run to completion, including its own final Opus review — and writes the contract: `state` = dex status + a one-line diff summary; `notes` = any failed dex tasks. This step emits the most output of any in the pipeline, so the dex logs staying in the subagent's context (not the conductor's) is the biggest isolation win. It is also the longest step, which is exactly why its contract must be written incrementally rather than composed at the end.

**`dex apply` is long-running** — it routinely exceeds the 10-minute foreground Bash ceiling. The subagent MUST run plan-to-dex's poll-to-completion loop (re-run `dex apply` foreground, max timeout, until all `.dex/plan.md` checkboxes are `[x]` or dex reports terminal) **inside its own invocation**. It MUST NOT background `dex apply` and return — a subagent's background processes are reaped on return, so the apply dies and only the dex setup commit lands. See the anti-yield guard in the subagent prompt below.

**Capture `HEAD_0=$(git rev-parse HEAD)` before dispatching.** Step 3 may have *reused* an existing feature branch that already carries dex commits from an earlier run, so "are there dex commits in `git log`" cannot distinguish this step's work from a previous one's. The pre-dispatch SHA can.

**Post-step zero-diff check:** after the subagent returns, the conductor checks the repo **in its own shell** — never from the subagent's `state` summary, and never skipped just because the contract file looks convincing.

**The predicate must measure *implementation*, not activity.** A naive "clean tree *and* `HEAD` unmoved" test can never fire, so it would wave a scaffolding-only run straight through to an empty PR: the tree is *already* dirty before dispatch (Step 1's spec rewrite and Step 2's plan file are both uncommitted), and `dex import --force` always produces its setup commit, so `HEAD` always moves — even when `dex apply` implements nothing. Exclude the pipeline's own by-products from both halves:

```bash
git log --oneline "$HEAD_0"..HEAD -- . ':(exclude)tasks/dex-plan.md' ':(exclude).dex/' ':(exclude)docs/superpowers/'
git status --porcelain --                . ':(exclude)tasks/dex-plan.md' ':(exclude).dex/' ':(exclude)docs/superpowers/'
```

If **both** print nothing, dex produced zero implementation → skip Steps 5-6 and jump to the final report, recording `failed (dex produced no implementation — only the dex import setup commit)`. Do not open an empty PR. (`git log` with an exclude pathspec drops commits that touch *only* the excluded paths, which is exactly the `dex import` commit.) Verifying against git directly is what stops a mis-summary, or a *lost* summary, from fabricating a PR.

This check is the template the other steps' predicates follow: git is the authority, the contract is the narrative.

## Step 5: Open the PR

**First, quarantine the pipeline's by-products.** `/commit-commands:commit-push-pr` commits **everything dirty** with no path scoping (its tool allowlist is `git …` + `gh pr create` and nothing else), so dex's scratch state would land in the feature PR. Move the untracked ones into the run dir — regenerable from the plan, and still inspectable afterwards:

```bash
mkdir -p "$RUN_DIR/artifacts"
for p in tasks/dex-plan.md .dex; do
  if [ -e "$p" ] && ! git ls-files --error-unmatch "$p" >/dev/null 2>&1 && ! git check-ignore -q "$p"; then
    mv "$p" "$RUN_DIR/artifacts/"
  fi
done
```

Only *untracked and unignored* paths move: a repo that tracks or already ignores them has made its own decision, and the conductor does not overrule it. The hardened spec and the plan file **stay** — they are real documentation of the change and belong in the PR.

Then run the `/commit-commands:commit-push-pr` slash command to commit, push the branch, and open the PR. Capture the PR number and URL from its output.

If no PR is created, that is a hard failure for Step 6 only → record it and skip to Step 7 (which reviews the branch, not the PR). When the failure is a permissions/auth error (`must be a collaborator`, `403`), record it as `failed (gh account lacks write access on this repo)` rather than a generic failure, so the final report points at machine state instead of at the pipeline.

## Step 6: Review Loop

The built-in `/code-review` **cannot** be invoked from an autonomous run (it is flagged `disable-model-invocation`). Instead, each pass dispatches one **review-and-fix subagent** (see "Step Subagents") that runs the whole `/review-pr` panel against the PR, then applies **only** the CRITICAL and IMPORTANT findings to the working tree (leaving ADVISORY/MINOR). The subagent does **not** commit; the conductor owns the commit/push loop so the fixes land as real branch commits.

Loop, up to **3 passes**:
1. **Compute the review scope yourself and pass it in.** `git diff --name-only <base>...HEAD` (base = the PR's base branch) — hold both the file list and its count as `SCOPE_N`. Then dispatch the review-and-fix subagent with contract path `$RUN_DIR/step-6.pass-<N>.contract.md` (a fresh path per pass — never overwrite a previous pass's contract, and never glob for "the latest one"), giving it the PR number/URL from Step 5 **and that explicit file list**.

   Both halves matter. `/review-pr`'s own command file scopes itself from the working tree (`git diff --name-only`, "agents analyze git diff by default") — which is **empty** after Step 5 commits and pushes. So the default behaviour of the command the pipeline depends on is to review nothing, report clean, and terminate this loop as a success. Prose telling the subagent to "review the PR's full diff versus its base" is a fix that rests entirely on instruction-following beating a written default; handing it the concrete file list plus a count the conductor can check is a fix that does not.
2. **Decide whether fixes were applied by diffing the working tree against a snapshot taken before dispatch, not from the contract.** Capture `SNAP_N=$(git status --porcelain)` *immediately before* dispatching the pass; after it returns, this pass applied fixes iff `git status --porcelain` differs from `SNAP_N`. Do **not** test for a merely non-empty tree: any leftover untracked file — a stray artifact, an editor temp file, a by-product Step 5 did not quarantine — satisfies non-emptiness on *every* pass, which drives useless commit-and-re-dispatch cycles straight to the 3-pass cap and reports fixes that never happened. The snapshot diff is authoritative and works even when the pass's contract is missing.
3. **Validate the pass's scope before believing a clean result.** The contract's `state` must report how many files the panel actually reviewed. If it reports **0** (or the count is absent) while `SCOPE_N` was non-zero, this pass reviewed nothing: record it as `failed (empty review scope — panel reviewed 0 of <SCOPE_N> changed files)` and **do not read it as clean**. Re-dispatch once with the file list restated; if it happens again, stop the loop and say so in the final report. A clean verdict over an empty scope is indistinguishable from a genuine clean one unless the scope is checked — and it is the more likely of the two.
4. If **no fixes were applied** (and the scope checked out) → exit the loop (an unchanged tree only re-yields the same result — leftover ADVISORY/MINOR or deliberately-skipped findings alone are terminal, not a reason to re-review).
5. Otherwise the conductor commits and pushes the applied fixes, then re-dispatches (next pass). Findings the subagent **left** (ADVISORY/MINOR, or a CRITICAL/IMPORTANT it judged false-positive or out of diff scope) are read from the pass contract and recorded, not re-litigated.

After 3 passes, stop even if findings remain. Each pass's contract file carries that pass's leftover findings (file:line — summary, with severity) for the final report — no separate boundary verifier runs. If a pass's contract is missing, record `pass <N>: fixes applied (contract lost — findings not summarized)` and, when the cap is hit this way, note in the final report that the last commit's changes were never summarized by the panel — a follow-up `/review-pr` scoped to that commit is the remedy.

## Step 7: Architect Review

Run `Skill(claude-skills:architect-review-pr)` against the branch — the completeness & wiring pass ("is this actually done and integrated?") that complements Step 6's line-level review. **Invoke it with `report-path=$RUN_DIR/architect-review.md`** — its documented token for a caller-supplied report path, which it uses instead of minting its own. Pass no scope argument: it scopes findings to the branch diff vs base on its own. It runs in the main loop (it already dispatches its own fresh-context subagent — see Step Isolation) and it is **report-only**: the conductor reads that exact path and records its ranked findings (Unwired / Missing / Incomplete / Bug-edge / Risk) verbatim enough to act on, fixes nothing, and continues to the final report (never halt on quality).

**Read only `$RUN_DIR/architect-review.md`.** Never glob `architect-review-pr-*.md` in the temp dir — a report from a previous session on a *different* ticket satisfies that pattern, and presenting stale findings as this run's is a worse outcome than reporting none. If the file does not exist, record Step 7 as `failed (no architect report produced)` and say so in the final report.

Because it reviews the **branch diff**, not the PR object, it runs even when Step 5 failed to open a PR — only a zero diff from Step 4 skips it.

---

## Step Subagents

Every subagent — the three execute-and-report subagents (Steps 1/2/4) and the review-and-fix subagent (Step 6, one dispatch per pass) — delivers the same three-field contract, **by writing it to a `$RUN_DIR` path the conductor supplies at dispatch**:

- `outcome`: `clean` | `finished-with-notes` | `failed`
- `state`: the artifact to hand forward (per-step below)
- `notes`: any leftover CRITICAL/IMPORTANT findings or failure reason, verbatim enough to act on (empty if none)

**Why a file.** `state` is largely re-derivable from git and disk, but `notes` — the findings, `file:line — summary [severity]` — exists nowhere else in the world. That is why the contract survives as a concept while its carrier changes: an artifact-derived pipeline could recover every path and status and would still permanently lose the findings. The file is the only channel that has ever survived a subagent that finished and idled.

**Incremental, not composed-at-the-end.** The subagent writes `outcome` and `state` as soon as it knows them and appends each `notes` entry as it is confirmed. A contract written only just before returning still dies if the subagent idles mid-work; a contract written as it goes survives with partial content, and partial content is what let the one surviving hand-off be reconstructed.

**Per-step `state`:**
- **Step 1 — spec review:** `state` = current (possibly rewritten) spec path; `notes` = open IMPORTANTs if the loop hit its cap.
- **Step 2 — plan:** `state` = plan path.
- **Step 4 — execution:** `state` = dex status + one-line diff summary; `notes` = any failed dex tasks.
- **Step 6 — PR review:** `state` = PR URL + `reviewed: <N> of <SCOPE_N> files` (the scope evidence — see Step 6); `notes` = the CRITICAL/IMPORTANT findings applied this pass, plus leftover findings (ADVISORY/MINOR or a CRITICAL/IMPORTANT left unfixed) — each as `file:line — summary [severity]`. Whether fixes were applied is decided from the working-tree snapshot diff, not from this field.

### Execute-and-report subagent prompt (Steps 1/2/4)

The subagent runs the step AND writes the contract — the raw output stays in *its* context.

> ⚠️ **Co-edit warning — the only deliberate duplication in this skill.** The FORBIDDEN list and the pre-return verification block below are duplicated **verbatim** from `skills/plan-to-dex/SKILL.md` (a conductor that duplicates none of its units' logic still has to carry the anti-yield guard, because the guard binds *this* subagent, not the skill it invokes). The same text also appears in `docs/skills/plan-to-dex.md`. Touch any of the three and you must touch all three: `grep -rn '\[d\]ex --cli codex' skills/ docs/` finds every site — update them in one commit or they drift silently.

> You are executing one step of an autonomous pipeline. Invoke `Skill(<step-skill>)` with these inputs: <inputs>. Let it run to completion. **You MUST NOT return until the step reaches a terminal state.** If the step launches a long-running process (e.g. `dex apply` or `dex review`, or a spec-review codex pass), poll it to completion **in THIS invocation** — returning reaps any backgrounded work and silently discards the result.
>
> **AUTONOMOUS — NO USER IS REACHABLE. The skills you invoke were written for interactive use and WILL try to ask you questions. Every one of them is pre-approved.**
> - Treat every confirmation gate in the invoked skill as an answered **yes** and proceed. Never ask, never wait for input, never stop to present a choice. (`plan-to-dex` Step 5 presents `Proceed? [y/N]` — the answer is yes; its plan-validation "ask whether to proceed" and its quality-gate "What commands must pass?" are answered from the repo's own tooling, and its branch guard uses the branch the conductor already resolved.)
> - **`writing-plans` (Step 2): STOP the moment the plan file is written.** Its final "Execution Handoff" section asks **"Which approach?"** and attaches a REQUIRED SUB-SKILL (`subagent-driven-development` / `executing-plans`) to each answer. Do **not** pick one, do **not** invoke either sub-skill, do **not** begin implementing the plan — Step 4 of this pipeline executes it via dex, and implementing here duplicates that work on the same branch. Writing the plan file is your entire job.
> - **`spec-review-codex` (Step 1): on its 120s codex timeout, retry once.** Its skill says to ask the user whether to retry or skip — you cannot. Retry once; if it times out again, record `failed` with the timeout in `notes` and finalize the contract.
> - If you ever find yourself with a question and no way to ask it, answer it from the repo and record the assumption in `notes`. A stalled subagent delivers nothing.
>
> **Your contract file is `<CONTRACT_PATH>`. This is how you report — not your final message.** Create it with the `Write` tool **now, before you start the step**, containing `outcome: running` and the inputs you were given. Update it as the step progresses: set `state` the moment the artifact exists, append each `notes` entry as you confirm it, and set the final `outcome` when the step is terminal. Subagents in this pipeline have repeatedly finished their work and then ended without delivering a final message; nobody can ask you for the contract afterwards, and a re-ask has never recovered one. The file is the only channel that survives. Keep it current as you go, not composed at the end.
>
> **FORBIDDEN — every one of these has caused a silent failure in past runs:**
> - Never run the step's long process with `run_in_background: true`.
> - Never arm a `Monitor` / waiter / `ScheduleWakeup` to "come back later" — nothing re-invokes you after you return; the child is reaped and the work is lost.
> - Never return on an intermediate "waiting for / running in background / iteration N in progress" state.
>
> Run the step's own poll-to-completion loop **foreground** until it is genuinely done. To wait on a foreground pid, block on it directly (`wait <pid>`, or `while kill -0 <pid> 2>/dev/null; do sleep 15; done`) — never rely on any waiter or `Monitor` to resume you.
>
> **Pre-return verification (mandatory) — run these and confirm before returning; if any fails, keep looping:**
> - **No live worker _in this worktree_:** `pgrep -f '[d]ex --cli codex|[c]odex exec' | while read -r p; do lsof -a -d cwd -p "$p" -Fn 2>/dev/null | grep -q "^n$(pwd -P)" && echo "live worker $p"; done` prints nothing. The `lsof -d cwd` filter and the bracketed first characters are both required: a bare `pgrep -fl 'dex --cli codex|codex exec'` matches concurrent `/ship-it` runs in sibling worktrees *and* the shell running the check itself, so it can never pass. **Never kill, signal, or wait on a process you did not start** — a sibling run's dex is not yours to reap.
> - **Step 4 (dex) only:** `grep -c '\[ \]' .dex/plan.md` prints `0` (or dex reported a terminal `STALEMATE`/quota state you name), AND `git log --oneline` shows per-task dex commits, not just the lone `dex import` setup commit.
> - **The step's own output declares completion** (spec-review PASS/cap, plan file written, or dex loop terminal) — not "in progress".
>
> Then finalize `<CONTRACT_PATH>` so it holds exactly the three fields — `outcome` (`clean` | `finished-with-notes` | `failed`), `state` (<the artifact for this step>), `notes` (verbatim leftover CRITICAL/IMPORTANT or failure reason; empty if none) — and return the same three fields as your final message (corroboration; the file is what the conductor reads). Do not paste the step's raw output, logs, or findings into either — only the contract. If the step fails, write its full output tail to a separate temp file and put that path in `notes`.
>
> **Never** leave `<CONTRACT_PATH>` at `outcome: running` after the step is terminal, and never delete it — a stale-but-present contract is recoverable, a missing one is not.

### Review-and-fix subagent prompt (Step 6)

Dispatch a `general-purpose` subagent once per pass. It runs the whole `/review-pr` panel, applies the CRITICAL/IMPORTANT fixes, and writes the contract — the raw finding-by-finding trace stays in *its* context:

> You are the reviewer-fixer for one pass of an autonomous pipeline.
>
> **Your contract file is `<CONTRACT_PATH>`. This is how you report — not your final message.** Create it with the `Write` tool before you begin, and append each finding to it **as you triage it** — the finding, its severity, and whether you applied a fix or left it and why. Do not accumulate the findings list in your head to write at the end: subagents in this pipeline have finished their work and then ended without delivering a final message, and a re-ask has never recovered one. Findings exist nowhere but this file — the conductor can re-derive from git that fixes landed, but never *which* findings they answered.
>
> Run the `/review-pr` slash command (`pr-review-toolkit:review-pr`) against PR <PR# / URL> and let its full specialized-agent panel complete. **Review exactly these <SCOPE_N> changed files — this list is your scope, and it is authoritative:** <file list>. Do **not** let the review scope itself from the working tree: `/review-pr` defaults to `git diff --name-only`, which is empty on this branch because the changes are already committed and pushed, and a review of an empty scope reports "clean" while having examined nothing. If the panel comes back having looked at 0 files, that is a failed pass — say so rather than reporting clean. (`/review-pr` launches its analyzers via the `Task` tool; if this environment does not let you, as a subagent, spawn your own subagents, then perform each of `/review-pr`'s review aspects yourself, inline in this context — do not skip the review.)
>
> Then fix the reported findings: apply a fix to the working tree for **every CRITICAL and IMPORTANT** finding, leaving ADVISORY/MINOR untouched. Skip a CRITICAL/IMPORTANT only if you judge it a false positive or outside the PR diff — and record why. Stay in scope: no behavior changes beyond each fix, nothing outside the PR diff. **Do NOT commit or push** — the conductor commits your applied fixes.
>
> Then finalize `<CONTRACT_PATH>` so it holds exactly the three fields — `outcome` (`clean` if the panel found no CRITICAL/IMPORTANT | `finished-with-notes` if you applied fixes or left findings | `failed`), `state` (the PR URL **plus `reviewed: <N> of <SCOPE_N> files` — the count the panel actually examined; the conductor treats a missing or zero count as a failed pass, so never omit it and never round it up**), `notes`: each finding you **applied** and each you **left**, as `file:line — summary [severity]` (empty only if the panel found nothing) — and return the same three fields as your final message (corroboration; the file is what the conductor reads). Do not paste the raw review trace or diffs into either — only the contract.

Keep every subagent prompt scoped to one step so the conductor's own context stays lean.

**The conductor never asks a subagent for its contract again.** If a contract file is missing, the step's ground-truth predicate decides what happened (see the hand-off table and Control Flow). Do not `SendMessage` the idled agent, do not poll `TaskOutput`, and do not re-dispatch the step — the work completed; only the reporting failed, and re-running it risks duplicating real mutations.

---

## Control Flow — Never Halt

Fully autonomous, best-effort:

- **Non-clean quality outcome** (spec-review ended at the cap with open IMPORTANTs; PR-review still has findings after 3 passes; architect findings; review notes) → **record and continue** to the next step.
- **Hard failure that makes the next step impossible** (no plan written; dex produced zero diff; no PR created) → **skip the now-impossible steps and jump to the Final Report**. The conductor **never fabricates** a downstream artifact — no empty PR, no review of nothing. Only Step 6 depends on the PR: if the PR fails but a diff exists, Step 7 still runs (it reviews the branch, not the PR).
- **Preflight failure** is the sole hard abort (see Step 0).

"Never halt" means *never block on quality* — it does **not** mean invent work that cannot exist.

### A lost contract is a reporting failure, not a step failure

**An idle notification is not a completion signal.** A subagent may end with a bare `{"type":"idle_notification","idleReason":"available"}` — and may do so repeatedly, several times *after* its work is done. That payload says nothing about whether the step succeeded. Only the contract file and the step's ground-truth predicate do.

Read the two together, and name the result — never let a gap pass silently:

| Contract file | Ground-truth predicate | Conductor's reading |
|---|---|---|
| present | agrees | normal — use the contract |
| present | **disagrees** | **trust the predicate**, and record the divergence in the final report |
| **missing** | work is there | `finished-with-notes (contract lost — state reconstructed from git)`; reconstruct `state` from the predicate, carry it forward, and record that this step's `notes` are unavailable |
| **missing** | no work | genuine hard failure — skip the now-impossible steps and jump to the final report |

The third row is the common case and it is **not** a reason to halt, re-ask, or re-dispatch: the step's real work is on disk. What is lost is the summary, and the final report must say so per step rather than presenting a gap as a clean run. The fourth row is the only one that changes control flow.

---

## Final Report

Because nothing stops mid-run to flag problems, the final report is the contract. Always emit it at the end of any run that cleared preflight. Write it in `/handoff` style to **`$RUN_DIR/final-report.md`** — the OS temp dir, never the workspace — and also summarize it in the conversation. Include:

- **Per-step outcome** for all 7 steps: `clean` / `finished-with-notes` / `skipped (reason)` / `failed (reason)`.
- **Hand-off integrity:** any step whose contract file was missing or disagreed with its predicate, named explicitly (`step 4: contract lost — state reconstructed from git`). A run that lost contracts is not a clean run, and the reader must be able to tell which summaries are missing rather than assuming those steps had nothing to say. Cite `$RUN_DIR` so the surviving contracts can be inspected.
- **Codex tiers used:** the preflight line verbatim (`spec-review: … | dex apply: … | dex review: …`). Both backends fail open on a bad tier, and no step reports the tier it actually ran at, so this line is the only record of whether an hour of pipeline ran deep or cheap.
- **PR:** number + URL, or an explicit note that no PR was opened and why.
- **Unresolved findings:** every leftover CRITICAL/IMPORTANT from spec-review, every unfixed/skipped PR-review finding, **and** the architect review's ranked findings, verbatim enough to act on.
- **Failed dex tasks:** any task the dex loop could not complete.
- **Resume guidance:** what to pick up by hand, with paths to the spec, plan, branch, PR, and architect review report.
