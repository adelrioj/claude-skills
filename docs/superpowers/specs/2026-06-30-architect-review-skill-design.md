# `/architect-review` — Adversarial Completeness & Wiring Review

**Date:** 2026-06-30
**Status:** Approved design

## Problem

After a feature is built — typically as the final step of a `/ship-it` run, right
after `/review-pr` — there is no skill that checks whether the feature is *actually
complete and integrated*. The existing review skills cover different altitudes:

- `/code-review` and `/review-pr` find **line-level correctness** issues on the diff.
- `/spec-review-codex` / `-local` harden the **spec, before** any code exists.

None of them answer the question the user actually asks at the end of a build:

> "Do a deep pass at everything you built and make sure it's wired properly and
> works as intended. Find gaps, bits we didn't implement, anything that makes the
> feature incomplete — code that was created but never wired, failure cases, edge
> cases."

This skill fills that gap: an **architect-level adversarial review for completeness
and integration**, run on a finished implementation.

## What It Is

A diagnostic skill (`/architect-review`) that dispatches a **fresh-context Claude
subagent** to hunt for completeness and wiring gaps in the feature on the current
branch, then presents a ranked, evidence-backed report. It **fixes nothing** — it is
a finder, like `/ponytail-audit`, not a fixer like `/spec-review-codex`.

### Why a subagent (the adversarial mechanism)

The main loop *built* this code, so it shares the author's blind spots — the same
gap in reasoning that left code unwired also prevents noticing it on self-review.
A fresh `Agent` subagent re-derives "is this actually reachable / complete?" from
the code alone, with no memory of how it got written. This mirrors the independence
rationale of `spec-review-codex`, but uses a Claude subagent instead of the `codex`
CLI so the skill has **no external CLI dependency** and installs anywhere.

### Why report-only (no fix loop)

The user's intent is diagnostic — surface what's wrong so *they* decide. Report-only
also keeps the skill small: no fix/re-review loop, no convergence or enumeration-creep
logic to port from the spec-review family. The subagent reviews a *static* tree
(no moving target), which makes findings cleaner.

## Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| Reviewer | Fresh-context Claude `Agent` subagent (no `codex` dependency) |
| Output mode | **Report only** — ranked findings, fixes nothing |
| Scope | Branch diff vs. base, with **whole-repo tracing** to confirm reachability |
| Spec oracle | **Auto-discover**, degrade gracefully to code-only |

## Scope

The review **focuses findings on the feature just built** — the diff of the current
branch against its base (`main`/`master`) — but the subagent traces the **entire
repository** to confirm whether new code is reached. A diff-only review cannot tell
"created but not wired" from "wired elsewhere"; only whole-repo tracing can.

If there is no branch diff (e.g. on `main`, or nothing committed) and the user gave
no explicit target argument, the skill asks what to review rather than guessing.

An explicit argument (file, directory, or feature description) overrides diff-based
scoping: review exactly what was named.

## The Intent Oracle (auto-discovered)

To distinguish "looks fine" from "incomplete feature", the reviewer needs to know
what was *supposed* to exist. The skill auto-discovers, best-effort:

- The newest design spec: `docs/superpowers/specs/*-design.md` (by date prefix).
- An implementation plan if present: `tasks/` (e.g. `tasks/dex-plan.md`, `tasks/prd.json`).

If found, these are passed to the subagent as the **intent oracle** — the source of
truth for which promised features/tasks must be present and wired. If none is found,
the review proceeds **code-only**: completeness is judged purely from the code's own
internal promises (referenced-but-missing, defined-but-unwired). The oracle is an
enhancement, never a precondition.

## The Findings Taxonomy

The subagent runs this fixed checklist. Each category names a concrete failure mode:

| Type | Definition |
|------|-----------|
| **Unwired** | A symbol / file / endpoint / handler / migration defined in the changeset but never invoked, registered, exported, routed, or scheduled. |
| **Missing** | Referenced by the changeset (or promised by the intent oracle) but never defined. |
| **Incomplete** | Partial vs. stated intent: stub branches, `TODO` / `pass` / `NotImplemented`, half-handled cases, a config flag/field read but never acted on, a code path created but not finished. |
| **Bug / edge-case** | Null / empty / error / boundary paths the new code opens but does not close. |
| **Risk** | Wired but fragile integration: order-dependence, missing migration/index, an untested seam, a silent-failure path. |

## The Evidence Gate (the quality lever)

The signature failure of any "what's not wired?" review is the **false positive**:
declaring code dead when it is in fact reached indirectly. Before reporting any
`Unwired` or `Missing` finding, the subagent MUST check for **indirect wiring** and
**cite the search that proves the gap**:

- callers / imports / references (`grep` the symbol across the repo)
- string-keyed dispatch (the symbol's name used as a string in a registry/map/config)
- dependency-injection / decorator / plugin-registration patterns
- barrel files / re-exports (`index.*`, `__init__.py`, `mod.rs`, etc.)
- dynamic dispatch / reflection / convention-based discovery
- config, env, CI, or manifest references (for files, hooks, schedules)

A finding with no cited empty-result search is **downgraded to a question**, not
reported as a finding. This single rule is what keeps the report trustworthy.

## Severity Model

Reuse the family's model for consistency:
`CRITICAL` / `IMPORTANT` / `ADVISORY` / `MINOR`. Findings are ranked most-severe first.
Because the skill is report-only, severity is informational (ranking + triage), not a
gate — nothing loops on it.

## Flow

```
Step 0  Preflight & scope
        - in a git repo? (else STOP)
        - resolve base branch (main|master); compute `git diff --name-only <base>...HEAD`
          and the full diff
        - explicit argument overrides → review the named target
        - no diff AND no argument → ask the user what to review (only blocking question)

Step 1  Discover the intent oracle (best-effort)
        - newest docs/superpowers/specs/*-design.md
        - tasks/ plan if present
        - none found → code-only (note it, continue)

Step 2  Dispatch ONE architect-review subagent (Agent tool)
        Input: the diff (names + full), the oracle (if any), the taxonomy checklist,
               the evidence-gate rule.
        Mandate: trace the WHOLE repo with Grep/Read; verify reachability;
                 cite evidence per finding; return ranked markdown report.

Step 3  Report
        - write the subagent's report to /tmp/architect-review-<ts>.md (audit, uncommitted)
        - present the ranked findings table in chat
        - STOP. Fix nothing.
```

### Subagent contract

The subagent returns a single markdown document:

1. A summary table: counts per severity, and whether an intent oracle was used.
2. Findings, most-severe first. Each finding has: **Type** (taxonomy), **Severity**,
   **Location** (`file:line`), **What** (one sentence), **Evidence** (the cited
   search / reasoning that proves it), **Suggested fix** (one line, advisory only).
3. A closing "Completeness verdict": COMPLETE / GAPS FOUND, one sentence.

The main loop does not parse this beyond surfacing it — report-only means there is no
machine-readable contract to enforce, unlike ship-it's three-field hand-off.

## What This Skill Is NOT

- Not a fixer — it never edits code (contrast `/spec-review-codex`, which fix-loops).
- Not a correctness linter — line-level bugs unrelated to completeness are out of
  scope; that is `/code-review` / `/review-pr`. (Overlap on integration-caused bugs
  is intentional and fine.)
- Not a whole-repo audit by default — scope is the feature on the branch. `/ponytail-audit`
  already covers whole-repo over-engineering sweeps.

## Deliberate Simplifications (ponytail)

- **One subagent, not a panel.** A single well-prompted architect covers the whole
  taxonomy. Upgrade path: fan out one subagent per taxonomy dimension and merge — add
  only if single-agent recall proves insufficient.
- **Report-only, no fix loop.** No convergence / enumeration-creep machinery to port.
- **No new CLI dependency.** Subagent over `codex`, so the skill installs anywhere.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.

## Integration with `/ship-it`

Out of scope for this spec to wire automatically. The skill is standalone and
user-invocable; the user runs it manually after a ship-it review (their current habit).
A future change could add it as ship-it Step 7, but that is a separate decision.

## Files

- `skills/architect-review/SKILL.md` — the skill definition.
- `README.md` and `CLAUDE.md` — add a `/architect-review` entry to the skills list,
  mirroring the existing entries' depth.

No scripts or templates needed — the review prompt lives inline in `SKILL.md`
(the subagent prompt is composed at dispatch time, like ship-it's subagent prompts),
and there is no helper script to run.
