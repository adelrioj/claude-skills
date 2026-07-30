# Design — Durable subagent hand-off for `ship-it`, `architect-review-pr`, `blind-spot`

**Date:** 2026-07-30 · **Status:** approved, ready to implement
**Origin:** `/tmp/handoff-shipit-contract-mechanism-2026-07-30.md`, written from a completed
`/ship-it` run on `modernaize` (MDZ-123) in which **5 of 5 step subagents finished their work
and returned no contract**.

---

## Problem

`ship-it` dispatches subagents for Steps 1, 2, 4 and 6 and requires each to return a
three-field contract (`outcome` / `state` / `notes`). In the MDZ-123 run every one of them,
plus the Step 7 architect reviewer, ended with a bare
`{"type":"idle_notification","idleReason":"available"}` and no report.

Three properties make this worse than a flake:

1. **A re-ask does not recover it.** The conductor asked every idled agent explicitly via
   `SendMessage`, quoting what it had already verified and requesting only the three fields.
   None answered.
2. **An idle notification is not a completion signal.** `step7-architect-review` idled three
   separate times *after* its work was done; another agent idled twice. A conductor that reads
   the first idle ping as "step finished, read the contract" reads nothing, repeatedly.
3. **Only files survived.** The Step 4 agent had, unprompted, written `VERIFICATION-LEDGER.md`
   to the scratchpad mid-run. That file is the sole surviving record of its gate numbers.
   Everything else was reconstructed by the conductor from git and direct gate runs.

Nothing was lost in that run only because the conductor distrusted the mechanism and verified
independently. This is a **recurrence** — the prior MDZ-120 run lost 4 of 5 contracts; it has
gone 4/5 → 5/5 with the mitigation already known.

### Root cause

A subagent's final message is a **single-delivery, unrecoverable channel**, and every `ship-it`
step uses it as the sole carrier. The `Agent` tool call itself always returns — sometimes with
an idle ping instead of the contract — so the conductor never hangs; it just reads the wrong
channel and gets nothing.

### The same bug elsewhere

- `architect-review-pr` Step 3: *"Write the subagent's returned markdown to
  `/tmp/architect-review-pr-$(date +%s).md`"*. The conductor can only write a file it received,
  so a lost report **does not exist at all**. Worse, in the MDZ-123 run the only
  `/tmp/architect-review-pr-*.md` on disk was from a **previous session for a different
  ticket** (Jul 29, mdz-121-122) — a conductor globbing that pattern silently adopts a stale
  report for the wrong feature and presents it as this run's findings.
- `blind-spot` Step 2 carries the identical construction.

Audited and **not** affected: `spec-review-codex`, `spec-review-local` and `fusion` write their
findings files from the `codex` / `pi` CLIs, not from a subagent return. `plan-to-dex` has no
report hand-off. `review-codebase` **already uses the correct pattern** — its subagents are told
*"Write the full report to `docs/audits/<KIND>-audit-<DATE>.md`"* and return only a short
summary.

---

## Design

### Principle

Every subagent hand-off gets a **conductor-chosen absolute path**. The subagent authors the
file; the return message becomes corroboration. This is the `review-codebase` pattern, applied
to the two skills that never got it.

### Channels, in priority order

```
Conductor (ship-it)
  RUN_DIR=$(mktemp -d -t ship-it)        # one dir per run, minted at preflight
  ...
  Step N:
    CONTRACT=$RUN_DIR/step-N.contract.md
    Agent("… Write outcome/state/notes to $CONTRACT.
           Write the outcome line and state as soon as you know them,
           append notes as each finding is confirmed. Then return the same text.")
    ── back in the conductor ──
    1. read $CONTRACT                    ← primary, authoritative
    2. git/disk predicate for this step  ← ground truth for `state`
    3. return message                    ← corroboration; ignored if it is an idle ping
```

Incremental writing (skeleton first, `notes` appended as findings land) is what makes the file
survive an agent that idles *mid-work* rather than at the end — the Step 4 ledger is the
existence proof.

### Divergence table — no state is silent

| Contract file | Git predicate | Conductor's reading |
|---|---|---|
| present | agrees | normal — use the file |
| present | **disagrees** | trust git; record the divergence in the final report |
| **missing** | work is there | `finished-with-notes (contract lost — state reconstructed from git)`, continue |
| **missing** | no work | genuine hard failure — skip now-impossible steps, jump to the final report |

A missing contract is **never** grounds to re-ask or re-dispatch.

### Per-step ground-truth predicates

Generalizes Step 4's existing *"check the repo in your own shell, never the subagent's
summary"* rule to every step.

| Step | Predicate that means *done* |
|---|---|
| 1 spec | spec file mtime newer than dispatch, and a `spec-review-findings-*` file exists |
| 2 plan | `test -f <plan-path>` — already present, keep |
| 4 execute | `git status --porcelain` + per-task dex commits in `git log` — already present, keep |
| 6 review | `git status --porcelain` non-empty ⇒ fixes were applied *(this is what actually drove the MDZ-123 loop)* |
| 7 architect | `test -f $RUN_DIR/architect-review.md` |

### `architect-review-pr` and `blind-spot`

Invert the report hand-off: the caller passes `REPORT_PATH` **in**, the subagent creates the
file early and appends findings, and the conductor reads that exact path. **The
`$(date +%s)` glob is removed** — a conductor must never resolve a report by timestamped
pattern, because a stale file from another ticket satisfies the glob.

`architect-review-pr` invoked from `ship-it` receives `$RUN_DIR/architect-review.md`; invoked
standalone it mints its own path once and uses it in both the prompt and the read.

### Why the three-field contract survives

`state` is derivable from disk, but `notes` — the findings list, `file:line — summary
[severity]` — exists nowhere else. Dropping the contract in favour of pure artifact-derived
state would permanently lose the findings channel. The contract stays; only its *carrier*
changes. Its original purpose held up in the failing run: no raw dex/codex logs ever reached
the conductor's context.

---

## Explicitly out of scope

- **`TaskOutput` polling or re-dispatch.** The work completed every time; only reporting failed.
- **Weakening the anti-yield guard.** It is correct and load-bearing — Step 4's poll-to-completion
  rule is why the work landed at all.
- **The `bin/checkstyle-local.sh` false-green** found during the run — a *modernaize* issue,
  recorded separately.

## Scope of the change

| File | Change |
|---|---|
| `skills/ship-it/SKILL.md` | `RUN_DIR` at preflight; contract-as-file in the Step Subagents section and both subagent prompts; per-step predicates; divergence handling; "idle ≠ completion" |
| `skills/architect-review-pr/SKILL.md` | Step 3 inversion; `<REPORT_PATH>` in the prompt template; glob removed |
| `skills/blind-spot/SKILL.md` | Same inversion in Step 2 |
| `docs/skills/ship-it.md` | Conventions updated to describe the file channel |
| `docs/skills/architect-review-pr.md` | Same |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Paired bump to `1.2.12` |

## Verification

The change is skill prose, so the check is structural, not a test run:

1. No `$(date +%s)` remains in a path a conductor later *reads* (writing a fresh path is fine).
2. Every `Agent` dispatch in the three skills names an absolute path the subagent must write.
3. Every conductor-side read names that same variable — no globs.
4. `ship-it`'s never-halt policy still covers all four rows of the divergence table.

Deliberately **not** dogfooded through `/ship-it`: a mid-run failure of the conductor while
shipping a fix to the conductor's own hand-off would be indistinguishable from the bug under
repair.
