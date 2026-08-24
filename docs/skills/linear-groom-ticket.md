# linear-groom-ticket

Grooms **one** Linear ticket: analyses it, rewrites it so it is ready to work
on, or marks it a deletion candidate. Nothing reaches Linear before a human
approves it.

Templates are **not** this skill's own: `10-lint.py` reads `skills/to-linear/templates/{bug,story}.md`, the same files `/to-linear` fills when it *creates* a ticket, chosen per ticket from its type label (`Bug` → `bug.md`, anything else → `story.md`). The skill ships no `reference/ticket-template.md` any more, and forking one back in re-opens the bug it closes: a ticket filed against one shape and linted against another reports every section missing and is restructured on its first grooming. `--template` still forces one file for a deliberate exception; `gaps.json` carries `template`/`template_path`, and step 4 hands the editor that path. Ticket prose is **English** — `prompts/editor.md` translates a Spanish ticket rather than matching it, so grooming an old Spanish ticket restructures and translates it (the original survives in the revert-snapshot comment). Spanish stays where it is load-bearing: the skill's own trigger phrases, and `keywords.py`/`stopwords.txt`, which tokenize Spanish titles for the duplicate search.

The Linear I/O is the agent's, over the **Linear MCP** — the MCP is agent-only,
so no script can call it. Deterministic scripts own the offline steps instead:
template linting, duplicate-candidate assembly from the parts the agent fetches,
JSON-schema validation, and plan synthesis. Agents own the judgement calls.
Three `codex` analysts run in parallel (veracity, duplicates, feasibility); one
Claude Sonnet subagent drafts the corrected description from their findings.

## Why this skill is shaped the way it is

Every guard below exists because something failed, most of them during live
runs rather than in the 330-assertion offline suite. Read this before
"simplifying" any of them.

**No write happens before you approve, and only what the plan contains.** The
agent performs every Linear write itself as an MCP call, but only in step 7,
only after the approval gate, and only for what the approved `$RD/plan.json`
holds — writing anything else, or writing before the gate, bypasses every
safeguard the earlier steps built (the repo-plausibility gate, the
deletion-evidence rule, the pre-overwrite snapshot comment, the staleness
check). `SKILL.md` also forbids hand-editing `plan.json`, which would condemn a
ticket on a hand-written verdict rather than on the analysis.

**The deletion verdict has four conditions, and every degradation path fails
toward keeping the ticket.** `DELETE-CANDIDATE` requires high confidence, hard
evidence, no dimension voting `opposes`, and no unavailable dimension. A
dimension that says `delete-candidate` while not supporting deletion is treated
as incoherent and blocks the verdict for the whole run.

**`DELETE-CANDIDATE` may be structurally rarer than it should be.** Wave 1 is
parallel, so the feasibility analyst never learns what veracity found — and
work that is already merged still reads as perfectly implementable. An analyst
answering "could this be built?" can therefore veto the one who checked "has
this already been built?". Do not read a long run of healthy verdicts as proof
the tickets are healthy.

**A duplicate is recorded as a comment by default — a policy, not a missing
tool.** `save_issue` takes `duplicateOf`, `blocks`, `blockedBy` and `relatedTo`
(all append-only), so the relation write is available. The skill still defaults
to a comment naming the canonical ticket and its URL, plus the triage label,
because of the old pipeline's observed side effect: Linear silently
transitioned the issue on a `duplicate` relation add, absent from the activity
log. The hazard is specific to that type — `duplicate-of` is also the only type
`40-synthesize.py` ever plans, so it governs every relation the skill writes —
and the non-duplicate types were verified state-safe on a cross-team pair
(2026-08-20), where a `blocks` write moved neither ticket's `stateHistory`. A
skill whose one promise is "never moves the state" cannot make that write by
default. The comment is purely additive, so the skill changes a ticket's
workflow state on no verdict — unless the caller explicitly opts into the
native relation at the approval gate, in which case step 7 writes it and reads
the state back so any move is reported rather than silent.

**Every write is verified by reading it back.** The MCP is the only writer and
it can report a write it could not confirm, so the agent re-reads the issue (the
description after an overwrite, the comment list after a comment) and treats the
write as landed only if the sent text is there. A read-back that finds no trace
is the failure signal, not the tool's own optimism.

**Linear normalises markdown on save** (`-` bullets become `*`, bare URLs
become autolinks, bold markers move, whitespace reflows), so a read-back is
never byte-identical to what was sent. A tolerant comparison that erases bold
markers and whitespace structure reaches exact equality; it is lossy, and that
is the price of being able to recognise our own write at all.

**The wave-2 draft is gated hard** (exit 2) on empty output, tool-call markup
(`</invoke>`, `<invoke`, `</content>`, `antml`) or the absence of any `## `
heading. A wave-2 editor once leaked its own closing tags into a live ticket.
Nothing is stripped on purpose: contaminated output means the editor step went
wrong, so it is re-dispatched rather than cleaned up.

**The offline suite covers the deterministic half only.** Template lint,
candidate assembly, plan synthesis, schema validation and the repo gate run
with no network and no tokens; the Linear I/O is the agent's, made over the
MCP, so it has no scripted double and is exercised only on a live run. Keep the
safeguards in `SKILL.md` step 7 (snapshot before overwrite, read-back after
every write) honest, because nothing offline can prove them for you.

## Conventions specific to this skill

**The Codex pin uses the `_BUILD` pair, and that is a deliberate exception.**
`docs/codex-tuning.md` reserves `CODEX_MODEL_BUILD` / `CODEX_EFFORT_BUILD` for
code-writing and the `_REVIEW` pair for review passes. Wave 1 is analysis, not
code, so by that taxonomy it belongs on `_REVIEW` — but `gpt-5.6-luna` @ `high`
is the pair the skill's two live runs were validated against, including the
measured improvement from `medium` to `high` confidence on the duplicates
dimension. Re-tiering it invalidates that evidence, so it stays on `_BUILD`
until someone re-runs the validation. Both knobs still work, and
`tests/check-codex-knob.sh` sees the call site.

**Paths handed to subagents must be expanded.** A subagent's `Read` tool does
not expand `${CLAUDE_PLUGIN_ROOT}`, so the wave-2 dispatch pastes absolute
paths (or file contents) rather than the variable. An editor that cannot open
its own prompt still returns a plausible-looking draft.

**The entitlement gate is skipped on an absent cache and closed on an
unparseable one.** `~/.codex/models_cache.json` is a cache, not the authority
on what an account can run, so its absence must not block a working machine.
A file that exists but cannot be parsed is "cannot confirm", and the run is
refused — the alternative is spending three `codex` calls to learn the same
thing in a worse costume, because three failed analysts look exactly like a
ticket nobody can judge.

**The offline suite must stay hermetic.** No test may consult the real models
cache; `CODEX_MODELS_CACHE` points at a fixture or at nothing. A suite whose
result depends on this machine's entitlements is not a suite.

## Known gaps

Written down rather than hidden. None is a blocker; all are real.

- Nothing dedupes a repeated audit comment across re-runs.
- The repo↔ticket gate verifies **identity, not freshness** — it will happily
  pass against a checkout many commits behind `origin/main`, and the veracity
  analyst then judges the ticket against stale code.
- No `--no-triage-label`, so a blocked-deletion `FIXABLE` plan is inapplicable
  on a team that has no triage label.
- The candidate body cap reads the **first** 8 candidates, unranked, so
  open-state candidates appended late can be the ones skipped.
- `tolerant_description()` models one observed normalisation, not Linear's
  full ruleset.
- No per-dimension timeout: a hung `codex exec` hangs `wait` with no
  wall-clock bound.
- A duplicate defaults to a comment plus the triage label rather than a native
  relation (a policy, because the relation write moves the state), so unless the
  caller opts in, cross-ticket duplicate links are not machine-navigable in
  Linear the way a relation would be.

## Prerequisites

The **Linear MCP** (the `linear` server, authenticated — its tools are
`mcp__linear__*`; the same one `/to-linear` uses), `codex` (entitled to the pinned model), and Python 3 with
`jsonschema`. The `jsonschema` import is checked before wave 1 and a failure
raises a distinct `FATAL` banner, kept separate from "the models could not
answer" on purpose.

## Tests

```bash
bash skills/linear-groom-ticket/scripts/tests/run.sh
```

No network, no tokens, no Linear workspace: the suite exercises the offline
scripts only, and `$LINEAR_GROOM_CODEX` points at a codex double (the Linear
I/O is the agent's and is not scripted, so there is nothing to fake).
`shellcheck` gates the run in two tiers (production scripts at default severity,
tests at warning and above); if it is not installed the summary line says the
static analysis did not happen rather than quietly passing.

Beyond the suite: `docs/superpowers/specs/2026-08-17-linear-groom-ticket-design.md`
records the design and the rejected alternatives.
