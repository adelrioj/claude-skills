---
name: architect-review-pr
description: "Use after a feature is built — e.g. the final step of a ship-it run, right after review-pr — to check it is actually complete and wired, not just line-correct. Dispatches a fresh-context Claude subagent that traces the whole repo to hunt completeness and integration gaps in the branch's changes, then reports ranked, evidence-backed findings and fixes nothing. Triggers on: architect review, architecture review, completeness review, wiring review, is this wired, did we finish this, find the gaps, incomplete feature, created but not wired, dead code check, deep pass on what we built."
user-invocable: true
---

# Architect Review — Adversarial Completeness & Wiring

An **architect-level adversarial review for completeness and integration**, run on a
finished implementation. It answers the question the other review skills don't:

> "Do a deep pass at everything you built and make sure it's wired properly and works
> as intended. Find gaps, bits we didn't implement, code created but never wired,
> failure cases, edge cases."

This skill is a **finder, not a fixer** — like `/ponytail-audit`, it reports ranked,
evidence-backed findings and **edits nothing**. Contrast `/spec-review-codex`, which
fix-loops. There is no fix loop, no convergence logic, and no external CLI dependency.

**Where it sits in the family:**
- `/code-review`, `/review-pr` — line-level *correctness* on the diff.
- `/spec-review-codex` / `-local` — harden the *spec, before* any code exists.
- `/architect-review-pr` — *completeness & wiring* of the finished feature. This skill.

**Why a fresh subagent (the adversarial mechanism).** The main loop *built* this code,
so it shares the author's blind spots — the same gap in reasoning that left code unwired
also prevents noticing it on self-review. A fresh `Agent` subagent re-derives "is this
actually reachable / complete?" from the code alone, with no memory of how it got
written. Same independence rationale as `spec-review-codex`, but a Claude subagent
instead of the `codex` CLI, so the skill has **no external CLI dependency** and installs
anywhere.

**Why report-only.** The intent is diagnostic — surface what's wrong so the user decides.
Report-only keeps the skill small (no fix/re-review loop to port) and the findings clean
(the subagent reviews a *static* tree — no moving target).

---

## Flow

### Step 0 — Preflight & scope

1. **In a git repo?** Run `git rev-parse --is-inside-work-tree`. If it fails, STOP with:
   > "Not in a git repository — nothing to review."
2. **An explicit argument overrides everything.** If the user named a target (a file, a
   directory, or a feature description), that IS the scope — skip diff computation and
   review exactly what was named (still trace the whole repo for reachability).
3. **Otherwise, scope to the branch diff.** Resolve the base branch: use `main` if it exists, else `master` (`git rev-parse --verify <name>`). Then compute:
   - changed-file list: `git diff --name-only <base>...HEAD`
   - full diff: `git diff <base>...HEAD`

   (Three-dot `<base>...HEAD` diffs against the merge-base — only what this branch
   changed, not unrelated drift on the base.)
4. **No diff AND no argument** (you are on the base branch, or nothing is committed) →
   **ask the user what to review.** This is the only blocking question — do not guess.
5. **Resolve the report path, once.** A caller can supply it as `report-path=<absolute path>`
   (that is how `/ship-it` passes `$RUN_DIR/architect-review.md`); strip that token from the
   argument before interpreting anything else as scope, so a report path is never mistaken for
   a review target and vice versa. If one was supplied, use it verbatim. Otherwise mint it:
   `REPORT_PATH="${TMPDIR:-/tmp}/architect-review-pr-$(date +%s).md"`. Hold it in a variable —
   the same value goes into the subagent prompt and is read back in Step 3. **Never resolve
   the report by globbing `architect-review-pr-*.md`**: a stale report from an earlier session
   on a *different* branch satisfies that glob, and presenting it as this run's findings is a
   worse failure than having no report at all.

Announce the resolved scope in one line, then proceed:
> "Architect-reviewing `<scope>`<, oracle: path | code-only>. Dispatching the subagent."

### Step 1 — Discover the intent oracle (best-effort)

The reviewer tells "looks fine" from "incomplete feature" by knowing what was *supposed*
to exist. Auto-discover, best-effort — none of these is required:

- Newest design spec: the highest date-prefixed `docs/superpowers/specs/*-design.md`.
- Implementation plan if present: `tasks/` (e.g. `tasks/dex-plan.md`, `tasks/prd.json`)
  or the newest `docs/superpowers/plans/*.md`.

If found, pass it to the subagent as the **intent oracle** — the source of truth for
which promised features/tasks must be present and wired. If none is found, the review
proceeds **code-only**: completeness is judged purely from the code's own internal
promises (referenced-but-missing, defined-but-unwired). **Note in the report whether an
oracle was used.** The oracle is an enhancement, never a precondition.

### Step 2 — Dispatch ONE architect-review-pr subagent

Dispatch a single fresh subagent via the **Agent tool** (`subagent_type: general-purpose`).
Compose the prompt from the template below, filling `<BASE>`, `<SCOPE>`, `<ORACLE>`, and
`<REPORT_PATH>`. The subagent **writes the report file itself and reports only — the report
path is the one file it may create, and it must edit nothing else.** One subagent, not a panel
(see Deliberate simplifications).

### Step 3 — Report

1. **Read the report at `REPORT_PATH`** — the exact path from Step 0.5, not a glob. The
   subagent authors that file; the conductor does not write it from the return message. A
   subagent that completes its review and then idles without returning sends no message, so a
   conductor that writes what it "received" produces **no report at all** — and one that globs
   a timestamped pattern silently picks up another branch's stale report.
2. **If `REPORT_PATH` does not exist**, say exactly that ("the subagent produced no report at
   `<path>`") and stop. Do **not** re-dispatch, do not re-ask the subagent (a direct re-ask
   does not recover a lost hand-off), and do not fall back to a glob.
3. Present the ranked findings in chat: the summary counts, the findings most-severe
   first, and the completeness verdict.
4. **STOP. Fix nothing.** If the user wants fixes applied, that is a separate, explicit
   request — this skill's contract ends at the report.

---

## The subagent prompt

Compose this at dispatch, substituting `<BASE>`, `<SCOPE>`, `<ORACLE>`, and `<REPORT_PATH>`:

```
You are a fresh-context software architect reviewing a FINISHED implementation for
COMPLETENESS and WIRING. You did not write this code and have no memory of how it was
built — re-derive everything from the code itself. You are READ-ONLY on the repository:
trace, reason, and report. Do not edit or delete any file, and create exactly one — your
report at <REPORT_PATH> (see Output). Nothing else.

## What to review (scope)

<SCOPE>
  # substitute exactly ONE of:
  # (a) branch diff:
  #   "The feature is the change on this branch vs <BASE>. Get the changed files with
  #    `git diff --name-only <BASE>...HEAD` and the full diff with
  #    `git diff <BASE>...HEAD`. Changed files:
  #    <name-only list>"
  # (b) explicit target:
  #   "Review this target: <argument>. Trace how it is (or isn't) integrated into the
  #    rest of the repository."

Focus your FINDINGS on the feature above, but trace the ENTIRE repository with Grep and
Read to confirm whether new code is actually reached. A diff-only review cannot tell
"created but not wired" from "wired elsewhere" — only whole-repo tracing can.

## Intent oracle

<ORACLE>
  # substitute exactly ONE of:
  # if found:
  #   "Here is the source of truth for what this feature was supposed to be. Anything it
  #    promises that is absent or unwired is a Missing/Incomplete finding:
  #    <spec/plan contents or path>"
  # if none:
  #   "No design spec or plan was found. Review CODE-ONLY: judge completeness from the
  #    code's own internal promises (referenced-but-missing, defined-but-unwired). Do not
  #    invent requirements the code never implies."

## Findings taxonomy (run this fixed checklist)

- Unwired    — a symbol / file / endpoint / handler / migration defined in the changeset
               but never invoked, registered, exported, routed, or scheduled.
- Missing    — referenced by the changeset (or promised by the oracle) but never defined.
- Incomplete — partial vs. stated intent: stub branches, TODO / pass / NotImplemented,
               half-handled cases, a config flag/field read but never acted on, a code
               path created but not finished.
- Bug/edge   — null / empty / error / boundary paths the new code opens but never closes.
- Risk       — wired but fragile: order-dependence, a missing migration/index, an
               untested seam, a silent-failure path.

## Evidence gate (MANDATORY — this is what keeps the report trustworthy)

The signature failure of a wiring review is the FALSE POSITIVE: declaring code dead when
it is in fact reached indirectly. Before reporting ANY Unwired or Missing finding, you
MUST check for indirect wiring and CITE the search that proves the gap:

- callers / imports / references (grep the symbol across the repo)
- string-keyed dispatch (the symbol's name used as a string in a registry / map / config)
- dependency-injection / decorator / plugin-registration patterns
- barrel files / re-exports (index.*, __init__.py, mod.rs, ...)
- dynamic dispatch / reflection / convention-based discovery
- config, env, CI, or manifest references (for files, hooks, schedules)

A finding with no cited empty-result search is DOWNGRADED to a question, not reported as
a finding. Cite the actual command you ran and show that it returned nothing.

## Severity (informational ranking — nothing loops on it)

CRITICAL / IMPORTANT / ADVISORY / MINOR. Rank findings most-severe first. Severity is
triage only; this skill fixes nothing, so severity gates nothing.

## Output — WRITE the report to <REPORT_PATH>, then return it

Your report is delivered by **writing it to <REPORT_PATH>** with the `Write` tool. That exact
absolute path, and no other. Returning the report as a message is NOT how it is delivered.

Write it **incrementally, as you go**: create the file with the summary table as soon as you
have your first finding, then append each finding as its evidence gate passes. Do not hold the
report in your head until the end — if this invocation ends without the file on disk, the
review is lost, and no one can ask you for it afterwards.

When the file is complete, also return the same markdown as your final message (corroboration
only — the file is what gets read).

The document itself:

1. Summary table: counts per severity, and whether an intent oracle was used.
2. Findings, most-severe first. Each finding:
   - **Type** (taxonomy) · **Severity**
   - **Location**: `file:line`
   - **What**: one sentence
   - **Evidence**: the cited search / reasoning that proves it (for Unwired/Missing, the
     empty-result command you ran)
   - **Suggested fix**: one line, advisory only
3. **Completeness verdict**: COMPLETE or GAPS FOUND, in one sentence.

The document is consumed as-is, not machine-parsed — but it is consumed **from the file**.
```

The main loop does not parse the result beyond surfacing it — report-only means there is
no machine-readable contract to enforce. It does depend on `<REPORT_PATH>` existing, for the
same reason ship-it's three-field hand-off is now written to a file: a subagent's final message
is a single-delivery, unrecoverable channel that a completed-but-idled subagent never sends.
The file is the carrier; the return is corroboration. (`review-codebase` has always worked this
way — its audits write to `docs/audits/` and return only a summary.)

---

## What this skill is NOT

- **Not a fixer** — it never edits code. (Contrast `/spec-review-codex`, which fix-loops.)
- **Not a correctness linter** — line-level bugs unrelated to completeness are out of
  scope; that is `/code-review` / `/review-pr`. Overlap on integration-caused bugs is
  intentional and fine.
- **Not a whole-repo audit by default** — scope is the feature on the branch;
  `/ponytail-audit` already covers whole-repo over-engineering sweeps. (The subagent
  *traces* the whole repo, but *reports* on the feature.)

## Deliberate simplifications (ponytail)

- **One subagent, not a panel.** A single well-prompted architect covers the whole
  taxonomy. Upgrade path: fan out one subagent per taxonomy dimension and merge — add
  only if single-agent recall proves insufficient.
- **Report-only, no fix loop.** No convergence / enumeration-creep machinery to port.
- **No new CLI dependency.** Subagent over `codex`, so the skill installs anywhere.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.
