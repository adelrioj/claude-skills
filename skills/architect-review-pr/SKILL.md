---
name: architect-review-pr
description: "Use after a feature is built — e.g. the final step of a ship-it run, right after review-pr — to check it is actually complete and wired, not just line-correct. Dispatches a fresh-context Claude subagent that traces the whole repo to hunt completeness and integration gaps in the branch's changes, reports ranked, evidence-backed findings, then fixes the CRITICAL ones and verifies with a fresh re-review (capped at 3 passes; pass report-only to skip fixing). Triggers on: architect review, architecture review, completeness review, wiring review, is this wired, did we finish this, find the gaps, incomplete feature, created but not wired, dead code check, deep pass on what we built."
user-invocable: true
---

# Architect Review — Adversarial Completeness & Wiring

An **architect-level adversarial review for completeness and integration**, run on a
finished implementation. It answers the question the other review skills don't:

> "Do a deep pass at everything you built and make sure it's wired properly and works
> as intended. Find gaps, bits we didn't implement, code created but never wired,
> failure cases, edge cases."

This skill **finds first, then fixes what is CRITICAL** — the same review-then-fix shape
`/ship-it` Step 6 drives around `/review-pr`. The reviewer subagent is a pure finder: it
reports ranked, evidence-backed findings and **edits nothing**. Then the main loop applies
a fix for each CRITICAL finding and re-dispatches a *fresh* reviewer to verify, converging
or capping at 3 passes like `/spec-review-codex`. IMPORTANT and below stay report-only.
Pass a bare `report-only` token to skip the fix loop entirely (`/ship-it` Step 7 does —
its conductor owns its own fix/commit loop).

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

**Why the reviewer never fixes.** The finder's value is a *static* tree and a clean
adversarial stance — a reviewer that edits mid-review reviews a moving target and starts
defending its own patches. So fixing is the main loop's job, *between* passes, and every
verification pass is a **new** fresh-context subagent reading the tree as it now stands.
Findings below CRITICAL are the user's call, never auto-fixed.

---

## Flow

### Step 0 — Preflight & scope

1. **In a git repo?** Run `git rev-parse --is-inside-work-tree`. If it fails, STOP with:
   > "Not in a git repository — nothing to review."
2. **Split the argument before reading any of it as scope.** Strip two tokens first:
   - a `report-path=<absolute path>` token (that is how `/ship-it` passes
     `$RUN_DIR/architect-review.md`) — take it as the report path;
   - a bare `report-only` token — it disables the fix loop (Step 4).

   Remove both from the argument. Whatever remains — possibly nothing — is the scope.
   Doing this first is the point: read in the other order, a caller's `report-path=…`
   looks exactly like "the user named a target" in step 3, and the skill reviews its own
   output path instead of the branch.
3. **An explicit argument overrides everything.** If what remains names a target (a file, a
   directory, or a feature description), that IS the scope — skip diff computation and
   review exactly what was named (still trace the whole repo for reachability).
4. **Otherwise, scope to the branch diff.** Resolve the base branch: use `main` if it exists, else `master` (`git rev-parse --verify <name>`). Then compute:
   - changed-file list: `git diff --name-only <base>...HEAD`
   - full diff: `git diff <base>...HEAD`

   (Three-dot `<base>...HEAD` diffs against the merge-base — only what this branch
   changed, not unrelated drift on the base.)
5. **No diff AND no scope left after the split** (you are on the base branch, or nothing is
   committed) → **ask the user what to review.** This is the only blocking question — do not
   guess. Bare tokens with nothing else count as "no argument": `report-path=…` says where
   to write and `report-only` says not to fix — neither says what to review.
6. **Finish resolving the report path.** If step 2 found a `report-path=`, use it verbatim.
   Otherwise mint it:
   `REPORT_PATH="${TMPDIR:-/tmp}/architect-review-pr-$(date +%s).md"`. Hold it in a variable —
   the same value goes into the subagent prompt and is read back in Step 3. **Never resolve
   the report by globbing `architect-review-pr-*.md`**: a stale report from an earlier session
   on a *different* branch satisfies that glob, and presenting it as this run's findings is a
   worse failure than having no report at all.

Announce the resolved scope in one line, then proceed:
> "Architect-reviewing `<scope>`<, oracle: path | code-only><, report-only>. Dispatching the subagent."

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
(see Deliberate simplifications). This dispatch is review pass 1; the Step 4 fix loop reuses
this exact prompt for its verification passes.

### Step 3 — Report

1. **Read the report at `REPORT_PATH`** — the exact path from Step 0.6, not a glob. The
   subagent authors that file; the conductor does not write it from the return message. A
   subagent that completes its review and then idles without returning sends no message, so a
   conductor that writes what it "received" produces **no report at all** — and one that globs
   a timestamped pattern silently picks up another branch's stale report.
2. **If `REPORT_PATH` does not exist**, say exactly that ("the subagent produced no report at
   `<path>`") and stop. Do **not** re-dispatch, do not re-ask the subagent (a direct re-ask
   does not recover a lost hand-off), and do not fall back to a glob.
3. Present the ranked findings in chat: the summary counts, the findings most-severe
   first, and the completeness verdict.
4. **No CRITICAL findings, or `report-only` was passed → STOP here. Fix nothing.**
   IMPORTANT and below are never auto-fixed — they are the user's call. Otherwise
   continue to the fix loop.

### Step 4 — Fix loop (CRITICAL only; skipped by `report-only`)

CRITICAL findings are fixed by the main loop and verified by a fresh reviewer — the
fix/re-review shape of `/spec-review-codex`, capped at **3 review passes total** (the
Step 2 dispatch counts as pass 1).

Each pass:

1. **Apply a fix for every CRITICAL finding in the latest report**, in the main loop,
   guided by the finding's Location / Evidence / Suggested fix. Announce each as you
   apply it: `<location> — <one-line fix>`. Working tree only — **never commit**; the
   user owns git. Stay in scope: each fix answers its finding, nothing else. Skip a
   CRITICAL only if you judge it a false positive despite the evidence gate — say so,
   with your counter-evidence.
2. **If every CRITICAL was skipped** (all judged false positives), stop — an unchanged
   tree only re-yields the same report. Present the skips; the user arbitrates.
3. **Re-dispatch a fresh reviewer** — Step 2's prompt verbatim, same scope and oracle,
   plus one line appended to the scope block: *"Uncommitted fixes in the working tree
   are part of the feature under review."* (The subagent reads the tree, so it sees
   them; the line stops it from reporting the dirty tree itself as a finding.) New
   report path per pass — `REPORT_PATH_N="${REPORT_PATH%.md}.pass-<N>.md"` — never
   overwrite an earlier pass's report, never glob.
4. **Read the new report from its exact path.** Missing file → same rule as Step 3.2:
   say so and stop; the previous pass's report plus the fixes applied stand as the
   result. Otherwise:
   - **Zero CRITICALs** → converged. Present the final report, the list of fixes
     applied, and stop.
   - **A fixed CRITICAL comes back unchanged** → the fix is contested; do not ratchet.
     Present both positions (the fix you applied, the reviewer's re-finding) and stop —
     the user arbitrates.
   - **New or remaining CRITICALs, and fewer than 3 passes run** → next pass.

After 3 passes, stop even if CRITICALs remain: present the leftovers most-severe first
and say the cap was hit. Every pass's report stays on disk as the audit trail.

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

## Severity (CRITICAL gates the fix loop)

CRITICAL / IMPORTANT / ADVISORY / MINOR. Rank findings most-severe first. Mark CRITICAL
only what genuinely breaks the feature — an unreachable core path, promised behavior that
is absent, a data-loss edge — because the caller applies a fix for every CRITICAL you
report. IMPORTANT and below are informational; nothing loops on them.

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

The main loop parses nothing beyond the findings' severity markers — the report is prose,
and the fix loop works from the findings as written. It does depend on `<REPORT_PATH>`
existing, for the same reason ship-it's three-field hand-off is written to a file: a
subagent's final message is a single-delivery, unrecoverable channel that a
completed-but-idled subagent never sends. The file is the carrier; the return is
corroboration. (`review-codebase` has always worked this way — its audits write to
`docs/audits/` and return only a summary.)

---

## What this skill is NOT

- **Not a general fixer** — only CRITICAL findings are auto-fixed, by the main loop
  between reviewer passes; the reviewer subagent never edits, and nothing is ever
  committed. `report-only` restores the pure-finder behavior.
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
- **Fix loop is main-loop + fresh re-review, capped at 3.** No fixer subagent, no
  contract files — the report is the hand-off, and never-committed keeps rollback
  trivial (`git checkout`). CRITICAL-only keeps the loop short; widen to IMPORTANT
  only if leftovers prove chronic.
- **No new CLI dependency.** Subagent over `codex`, so the skill installs anywhere.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.
