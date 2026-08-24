---
name: linear-groom-ticket
description: "Use when a Linear ticket needs to be made ready to work on, or judged not worth working on. Analyses one ticket across four dimensions — whether its claims hold in the code, whether it is complete against the team template, whether it duplicates another ticket, and whether it is implementable — then proposes a corrected description and applies it to Linear only after you approve. Triggers on: groom this ticket, prepare NBS-123, is this ticket ready, revisa este ticket, ¿este ticket está listo?, deja el ticket listo para trabajar, candidato a borrar, dedupe this ticket."
user-invocable: true
---

# Grooming a Linear ticket

Analyse one Linear ticket, fix it, or mark it a deletion candidate. Nothing is
written to Linear before you approve it. This skill issues no workflow-state
command — it never transitions a ticket. It *can* create a missing label, but
only as a write shown at the approval gate like any other.

**Transport: the Linear MCP.** Every Linear read and write is an MCP tool call
on the same server `/to-linear` uses (`get_issue`, `list_issue_labels`,
`list_issue_statuses`, `list_issues`, `save_issue`, `save_comment`,
`create_issue_label`, …); load them with ToolSearch if they are deferred.
`save_issue` is one tool for create and update — every call here passes `id`,
because omitting it files a new ticket, which this skill never does. The MCP is agent-only, so **you**
make every call — there is no script that talks to Linear, by design, because a
script cannot reach the MCP. The deterministic scripts here do only the offline
work (template lint, wave-1 analysis, plan synthesis); the Linear I/O around
them is yours.

**A duplicate is a comment by default — a policy, not a missing tool.** The
MCP *can* write the relation: `save_issue` takes `duplicateOf`, `blocks`,
`blockedBy` and `relatedTo`, all append-only. This skill still records a
duplicate as a comment naming the canonical ticket and its URL, plus the triage
label, and the reason is specific to `duplicateOf`: **that write was observed to
move the ticket's state on its own**, when the removed local pipeline's
`relation add` silently transitioned an observed ticket into a `Duplicate`-type state with
nothing in the activity log. Linear has a `Duplicate` state and no other
relation type has one to move to. That collides with the one promise this skill
makes — it never changes a ticket's workflow state — so the comment keeps the
promise true.

`duplicate-of` is also the **only** relation type `40-synthesize.py` ever puts in
a plan, so in practice this policy governs every relation the skill writes. The
non-duplicate types were checked and are state-safe: a `blocks` write on
A verified cross-team pair (2026-08-20) added the relation on both sides and left both
tickets' `stateHistory` untouched.

The native relation is therefore **opt-in, not unavailable**: if the caller
explicitly asks for it at the approval gate, write it and read the state back
(step 7). Never write it silently.

**Announce at start:** "Using linear-groom-ticket to groom `<TICKET>`."

## Prerequisites — check first, fail loudly

```bash
command -v codex || echo MISSING_CODEX
python3 -c "import jsonschema" 2>&1
```

And the Linear MCP: the tools above must be available. If the only Linear tools
visible are `authenticate`/`complete_authentication`, the connector is not
authenticated — ask the user to run `/mcp`, select the Linear connector, and
retry. Never fall back to a local CLI or hand-rolled GraphQL; there is no shared
API key.

Any missing prerequisite: stop and tell the user exactly which one. Do not
improvise a substitute — the safeguards live in these tools.

## The one rule

**You never write to Linear without explicit approval in this conversation.**
Every write is an MCP call, made only after the approval gate, and only for
what the approved `$RD/plan.json` contains — the plan is the output of the
deletion safeguard and the editor gate, so writing anything not in it (or
writing before the gate) bypasses every safeguard the earlier steps built (the
repo/ticket plausibility check, the deletion-evidence rule, the staleness
check, the pre-overwrite snapshot). Step 7 is the only place writes happen, and
it follows the plan exactly.

**And never hand-edit `$RD/plan.json`.** It is what drives those writes, so
editing it is the same bypass by an easier route: a hand-written `verdict`,
`reason` or `safeguard` condemns a ticket on your say-so rather than on the
analysis. If the plan is wrong, fix the input and re-run `40-synthesize.py`.

## Steps

Let `$T` be the ticket **identifier** (like `NBS-238`) — if you were handed a
Linear URL, resolve it to the identifier first, because it names the run
directory. Resolve this skill's directory into `$S`; every step below uses it:

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/linear-groom-ticket"
echo "$S"
```

Run that `echo` and keep the **printed absolute path**. You need the literal
path, not the variable, the moment you hand a file to a subagent in step 4: a
subagent's `Read` tool does not expand `${CLAUDE_PLUGIN_ROOT}`, so an editor
dispatched with the unexpanded form cannot open its own prompt.

### 1. Fetch and gate on the repo

Compute the run directory and fetch the ticket over the MCP into it, in the
shape the offline scripts expect:

```bash
RD="${XDG_STATE_HOME:-$HOME/.local/state}/linear-groom/$T"
mkdir -p "$RD/wave1"
echo "$RD"
```

Then, through the Linear MCP:

- `get_issue(id: "$T")` → write `$RD/ticket.json`. Read the team key/name, the
  state, the labels, and the full body (comments, relations, children,
  attachments, activity) from the response and lay them out **exactly** like
  this — the `--full` extras sit beside `issue`, under `result`:

  ```json
  {"result": {
    "issue": {
      "identifier": "NBS-238",
      "title": "…",
      "description": "…markdown…",
      "team": {"key": "NBS", "name": "Nimbus"},
      "state": {"name": "To Do", "type": "unstarted"},
      "labels": [{"name": "Story"}],
      "url": "https://linear.app/…"
    },
    "comments": [], "children": [], "attachments": [],
    "relations": [], "activity": []
  }}
  ```

- `list_issue_labels(team: "<key>")` → `$RD/labels.json` as
  `{"result": {"labels": [{"name": "Bug"}, …]}}`
- `list_issue_statuses(team: "<key>")` → `$RD/states.json` as
  `{"result": {"states": [{"name": "To Do", "type": "unstarted"}, …]}}`

Then run the repo-plausibility gate — a Linear ticket does not record its
repository, and grooming from the wrong repo makes the veracity analyst read
the wrong codebase and falsely condemn a good ticket:

```bash
python3 "$S/scripts/lib/repocheck.py" --ticket "$RD/ticket.json" --repo "$PWD"
```

Exit `0`: plausible, carry on. Exit `3`: the ticket does not plausibly belong
to `$PWD` — this is the gate doing its job, **not** a crash. Show the user the
`signals` from its stdout JSON and ask what to do; do not waive it on your own
initiative. Any other exit: the check could not reach a verdict — stop, do not
proceed with the gate in an unknown state.

### 2. Lint and gather candidates

```bash
python3 "$S/scripts/10-lint.py" --ticket "$RD/ticket.json" --out "$RD/gaps.json"
```

`10-lint.py` measures the ticket against the template the `to-linear` skill owns
(`skills/to-linear/templates/`) — `bug.md` when the ticket carries a `Bug` type
label, `story.md` otherwise. **One source of truth on purpose:** `/to-linear`
files tickets against those templates, so grooming lints the shape the ticket was
filed with. Its stderr names which template it used, and `gaps.json` carries
`template` and `template_path`. Override with `--template <file>` only to lint
against a shape deliberately different from the filed one.

Then assemble the duplicate candidate set. The MCP reads are yours; the assembly
is deterministic and offline. Derive the query, then gather parts into
`$RD/.candidate-parts/`:

```bash
QUERY="$(python3 "$S/scripts/lib/keywords.py" --ticket "$RD/ticket.json" --max 6 | tr '\n' ' ')"
mkdir -p "$RD/.candidate-parts"
```

- `list_issues(query: "$QUERY", limit: 25)` → `$RD/.candidate-parts/search.json`
  as `{"result": {"issues": [{"identifier","title","state":{"name"},"url"}, …]}}`
- For each **open** state (every state in `states.json` whose `type` is
  `backlog`, `unstarted` or `started`), `list_issues` filtered to that state →
  `$RD/.candidate-parts/open-<N>.json`, one file per state, same shape.
- For the first `LINEAR_GROOM_BODY_LIMIT` (default 8) candidates, `get_issue(id)`
  → `$RD/.candidate-parts/body-<IDENT>.json` as
  `{"result": {"issue": {"description": "…"}}}`. If a body read fails, write one
  line to `$RD/.candidate-parts/bodyerr-<IDENT>.txt` instead — not fatal, it
  degrades one candidate's evidence.

**A failed candidate-LIST call (`list_issues`) is fatal — stop and retry.** A
silently short candidate set can hide a duplicate entirely, and nothing
downstream can tell the set was ever short. A failed body read is not. Then:

```bash
python3 "$S/scripts/20-candidates.py" --run-dir "$RD" --ticket "$T"
```

Read its stderr: it reports how many candidates are unique, how many bodies were
read, how many were skipped by the cap, and which could not be read. Bodies are
what let the duplicates analyst find a **shared identifier** (same Actions run,
same commit, same URL) instead of guessing from titles.

### 3. Wave 1 — three codex analysts in parallel

```bash
bash "$S/scripts/30-wave1.sh" "$T"
```

This takes a few minutes: three `gpt-5.6-luna` processes at high reasoning
effort, one per dimension (veracity, duplicates, feasibility). Read what it
prints to stderr carefully — there are two different messages and they mean
different things:

- **`wave1: N/3 dimensions available`** — the normal summary line. If `N < 3`,
  read the matching `$RD/wave1/<dim>.UNAVAILABLE` marker: the model never
  produced a valid answer after a retry, or `codex` itself failed. An
  unavailable dimension blocks any deletion verdict, and the user should know
  which one and why.
- **A `wave1: FATAL —` banner, printed before that summary line** — this means
  `python3`'s `jsonschema` module could not be imported, so the validator
  itself could not run for at least one dimension. **This is an environment
  problem, not a verdict on the ticket.** Do not read the `N/3` line that
  follows it as "the models couldn't answer" — nothing was asked. Tell the
  user to fix the Python environment (e.g. `pip install jsonschema`) and
  re-run `30-wave1.sh`; do not proceed to synthesis on a FATAL run.

Before any of that, the script checks the pinned model and effort against
`$CODEX_MODELS_CACHE` (default `~/.codex/models_cache.json`) and **refuses to
start** if this account cannot run that pair — exit 1, zero `codex` calls, and
the message says so. Read it as an entitlement problem and nothing else: it is
not a FATAL validator banner and it is not a verdict on the ticket. Fix the
entitlement or override with `CODEX_MODEL_BUILD` / `CODEX_EFFORT_BUILD`. A
missing cache file skips the gate rather than failing it.

Only after confirming there is no FATAL banner, read `$RD/wave1/*.json` for
the dimensions that succeeded.

### 4. Wave 2 — the editor (Claude Sonnet)

Dispatch **one** subagent with the `Agent` tool, `model: "sonnet"`. Its prompt
is the contents of `$S/prompts/editor.md`, followed by, clearly labelled:

- the template `10-lint.py` selected — read `template_path` out of `$RD/gaps.json`
  (`jq -r .template_path "$RD/gaps.json"`), which is an absolute path already
- `$RD/ticket.json`
- `$RD/gaps.json`
- every `$RD/wave1/*.json`

**Write out every one of those paths in full, expanded.** `$S` and `$RD` are
your shell's variables, not the subagent's, and `$S` expands from
`${CLAUDE_PLUGIN_ROOT}`, which a subagent's `Read` tool leaves untouched. Paste
the absolute paths you printed in step 1 — or paste the file contents inline. A
subagent handed `$S/prompts/editor.md` reports the file as missing and then
drafts a description with no instructions and no template, which reads as a
plausible draft and is not one.

Instruct it to return only the description markdown. Write its reply verbatim to
`$RD/draft.md` — do not edit it yourself. If it returns prose around the
markdown, dispatch it once more saying so; do not hand-clean the output, because
then nobody reviewed what actually reaches the ticket.

This wave runs **after** wave 1 by design: the editor cannot write an honest
description before knowing whether the work is already done.

### 5. Synthesise the plan

```bash
python3 "$S/scripts/40-synthesize.py" --ticket-id "$T" --draft "$RD/draft.md" \
  --run-dir "$RD" --triage-label needs-triage --out "$RD/plan.json"
```

Pass `--run-dir "$RD"` as shown. Without it the script derives the run
directory from `$T`, and a differently-cased id would miss the directory you
created.

The verdict and the deletion safeguard are computed here, in code — do not
second-guess them. Exit 1 means every dimension was unavailable; no plan is
written, and you must go back to `30-wave1.sh` rather than inventing a verdict
yourself.

**Exit 2 means the editor's draft is not fit to write to a ticket** and no plan
was written either. The draft becomes the ticket description verbatim, so it is
gated hard: it is refused when empty or whitespace-only, when it contains agent
tool-call markup (`</invoke>`, `<invoke`, `</content>`, `antml` — this is not
hypothetical, a wave-2 editor leaked its own closing tags into a live ticket
once), or when it has no `## ` headings at all although every template defines
them. The error names the offending token and line. **Do not clean the draft up
and re-run** — nothing is stripped on purpose, because a contaminated draft
means the editor step went wrong. Re-dispatch the wave-2 editor (step 4) and
read what it returns.

Read `$RD/plan.json`'s `safeguard` object before showing anything to the user:

- `safeguard.deletion_allowed` / `safeguard.blocked_by`: if `blocked_by` is
  non-empty, deletion was proposed and deliberately downgraded — that is the
  design working, and the user must see every reason listed.
- `safeguard.analysis_incomplete`: `true` whenever any dimension is
  unavailable, **regardless of verdict, including on a `READY` verdict**. When
  it is `true`, do not present the result as a complete audit. Say the ticket
  looks ready (or fixable, or a delete-candidate) *on the dimensions that
  ran*, and name every dimension in `unavailable_dimensions` that did not run.
- `safeguard.incoherent_dimensions`: dimensions whose `verdict` was
  `delete-candidate` but whose answer does not hold together — either the
  `deletion_stance` was not `supports`, or there was no `delete_reason` at all
  (a condemnation with nothing machine-readable behind it). Both are treated
  identically. These are never counted in `safeguard.proposers` and they always
  block deletion for the whole run, even if another dimension proposed deletion
  cleanly. `blocked_by` names which of the two it was.
- **If `safeguard.incoherent_dimensions` is non-empty and
  `safeguard.proposers` also contains an entry**, say this to the user in one
  explicit sentence — do not make them infer it from two separate lines:
  *dimension X proposed deletion with qualifying evidence, but dimension Y
  contradicted itself (said delete-candidate while not supporting deletion),
  so the tool declined to delete and a human decides.* Name the actual X and Y
  from `safeguard.proposers` and `safeguard.incoherent_dimensions`.

Check `$RD/labels.json` yourself: if `needs-triage` does not exist on the team,
either pass `--triage-label` with one that does, or plan to create it — the MCP
has `create_issue_label`, so a missing label is a write to approve, not a dead
end. `40-synthesize.py` does not verify the label; it writes whatever you pass
into the plan. Checking here is what lets the approval gate name the label
creation up front instead of surprising the user with it in step 7.

### 6. The approval gate

Show the user, in this order:

1. **The verdict** (`READY`, `FIXABLE`, or `DELETE-CANDIDATE`) and, for
   `DELETE-CANDIDATE`, the reason and its evidence.
2. **Per dimension**: verdict, confidence, stance, and the one-line findings.
   Name every `UNAVAILABLE` dimension explicitly. If `analysis_incomplete` is
   true, say so in plain words (see step 5).
3. **The safeguard adjacency sentence** from step 5 whenever it applies
   (incoherent dimension blocking a different dimension's qualifying proposal).
4. **The description diff** — run `diff` between the original and the draft and
   show it, not two full documents:
   ```bash
   python3 -c "
   import json,sys
   p=json.load(open('$RD/plan.json'))
   open('$RD/orig.md','w').write(p['original_description'])
   " && diff -u "$RD/orig.md" "$RD/draft.md" | head -120
   ```
5. **The exact writes**, read straight from the plan — never a paraphrase:
   ```bash
   python3 -c "
   import json
   p=json.load(open('$RD/plan.json'))
   print('description overwrite:', 'yes' if p.get('description_new') else 'no')
   print('labels to add:', p['labels_add'])
   print('relations:', [(r['type'], r['related']) for r in p['relations']])
   print('comments:', len(p['comments']))
   "
   ```
   Then describe, in plain words, what step 7 will do with each: the
   description overwrite (preceded by a snapshot comment holding the original),
   the label adds — naming any label that does not yet exist on the team and
   will be **created** first — the audit comment, and, for any `duplicate-of`
   relation, **a comment naming the canonical ticket plus the triage label
   rather than a native relation**. Say why that last one is a comment: the
   relation write is available (`save_issue(duplicateOf:)`) but was seen to
   transition a ticket's state by itself, and this skill promises not to move
   state. Offer the native relation as an explicit opt-in. Say that all of
   these are additive, that the snapshot makes the description overwrite
   reversible by hand, and that **nothing here changes the ticket's workflow
   state** unless the caller opts into the relation.

Then ask whether to apply. **Stop and wait.** A `READY` verdict proposes nothing
by default; ask whether the user even wants the audit comment.

### 7. Apply

Only after an explicit yes. Read `$RD/plan.json` and perform its writes through
the Linear MCP, **in this order**, reading each one back to confirm it landed.
Write nothing that is not in the approved plan, and issue no state transition.

**If the plan writes a new description** (`description_new` is non-null):

1. **Staleness check.** `get_issue(id: "$T")` and compare the live description
   against `plan.original_description`, **ignoring Linear's own markdown
   re-normalisation** — it rewrites `-` bullets to `*`, turns bare URLs into
   autolinks, moves `**bold**` markers and re-flows whitespace, so the live
   text is never byte-identical. Compare with those stripped. If it still
   differs, **someone edited the ticket since grooming** — STOP, nothing
   written. Recover by re-fetching (step 1) and re-synthesising (step 5); that
   costs no `codex` calls, because wave-1 findings are cached. But those cached
   findings describe the text *before* the edit: if the edit was substantive,
   re-run `bash "$S/scripts/30-wave1.sh" "$T" --force` first so the verdict is
   computed against the ticket you are about to groom. Show the user the diff
   and let them decide; do not decide silently.
2. **Snapshot.** Post a comment holding `plan.original_description` verbatim,
   prefixed with a marker line (e.g. `<!-- linear-groom:snapshot -->`), so the
   overwrite is reversible by hand.
3. **Overwrite.** `save_issue(id: "$T", description: "<plan.description_new>")` —
   the whole-field replace is what is wanted here, since the draft *is* the new
   body. (Do not use `patch`; the draft is not a delta.)
4. **Read back.** `get_issue(id: "$T")` and confirm the stored description
   matches what you sent (tolerant of the re-normalisation above). If it does
   not, STOP and report — the snapshot comment holds the original.

**Labels** (any verdict): for each entry in `plan.labels_add`, check
`$RD/labels.json`. A label that is missing is **created**, not a STOP:
`create_issue_label(name: "<label>", teamId: "<the ticket's team UUID>")`, but
only if the approval gate named that creation — an unapproved label is an
unapproved write like any other. Then add it via `save_issue(id: "$T", labels:
[<every existing label> + <new>])` and read the issue back to confirm.

> **`labels` replaces the full set.** Unlike the relation parameters, it is not
> append-only: any label you omit is *removed*. Send the ticket's current labels
> from step 1's `get_issue` plus the additions, never the additions alone.

**Relations** (`plan.relations`): record each one as a comment — for
`duplicate-of`, `"Duplicate of <related>: <its url>"`; for the others, a
one-line statement of the relationship. `save_issue` *can* write the real
relation (`duplicateOf`, `blocks`, `blockedBy`, `relatedTo`, all append-only),
and the comment is a deliberate policy rather than a missing tool: a
`duplicateOf` write was observed to transition a ticket's state with no
activity-log entry, and this skill promises not to move state. Since
`duplicate-of` is the only type a plan ever carries, that covers every relation
this skill would write. Tell the user in the report that it was recorded as a
comment and why.

**If the caller explicitly opted into the native relation** at the approval
gate, write it — `save_issue(id: "$T", duplicateOf: "<related>")` — then
`get_issue(id: "$T")` and compare the state to what step 1 recorded. Read
`stateHistory`, not just the current state: a transition Linear makes for you
shows up there whether or not it reaches the activity log. **If the state moved,
say so in the report as a state change the caller caused**; do not try to move
it back, and never write a relation that was not opted into.

**Comments** (`plan.comments`): post each `body` as a comment. The audit comment
is last.

If any write fails, report which steps completed and stop; the snapshot comment
(posted before the overwrite) holds the original description. Re-running the same
approved plan is the supported recovery — the staleness check will recognise a
description you already wrote (tolerant of re-normalisation) and let you repeat
the remaining additive steps, which are safe to repeat.

## Re-running

Wave 1 caches: a valid `$RD/wave1/<dim>.json` is not regenerated. Pass `--force`
to `30-wave1.sh` to re-run the analysis. Everything else is cheap to repeat.

The cache is keyed on nothing but the file's own validity — it does **not**
notice that `ticket.json`, `candidates.json` or `gaps.json` changed underneath
it. So after a re-fetch that brought in edited ticket text, the cached findings
still describe the **previous** text, and re-running only `40-synthesize.py`
produces a verdict from findings computed against text that no longer exists.
Cheap and correct are different questions: if the ticket changed
substantively, `--force`.

## Reporting honestly

- If a dimension is `UNAVAILABLE`, say so — do not present a two-dimension
  analysis as if it were complete.
- If a `FATAL` banner appeared in `30-wave1.sh`, say the environment is broken,
  not that the ticket has a problem.
- If the analysts disagree, show the disagreement rather than picking a side.
- If the verdict is `READY`, say the ticket needed nothing. That is a real
  result, not a failure to find work.
- **`DELETE-CANDIDATE` may be structurally rare — possibly rarer than it should
  be.** Condition 3 of the safeguard blocks deletion on *any* `opposes` vote,
  and wave 1 is parallel by design, so the feasibility and duplicates analysts
  never learn what veracity found. A ticket describing work that is already
  merged still reads as perfectly implementable, so an analyst answering
  "could this be built?" can veto the verdict of the analyst who checked "has
  this already been built?". If you never see a `DELETE-CANDIDATE` across many
  groomings, do not conclude the tickets are all healthy — suspect this, and
  say so.

## Tests

```bash
bash "$S/scripts/tests/run.sh"
```

The suite runs with no tokens and no network: it exercises the offline scripts
only (template lint, candidate assembly, plan synthesis, plan-schema
validation, the repo-plausibility gate). `$LINEAR_GROOM_CODEX` points at a codex
test double; the Linear I/O is the agent's job and is not scripted, so there is
nothing to fake. Run it after touching any script.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CODEX_MODEL_BUILD` | `gpt-5.6-luna` | Wave-1 model (pinned, not inherited from `~/.codex/config.toml`) |
| `CODEX_EFFORT_BUILD` | `high` | Wave-1 reasoning effort |
| `CODEX_MODELS_CACHE` | `~/.codex/models_cache.json` | Where the entitlement gate looks. Absent file → gate skipped, not failed. Exists but unparseable → the run is refused, because "cannot confirm" is not "fine" |
| `LINEAR_GROOM_CODEX` | `codex` | Codex CLI, overridden by the test suite |
| `LINEAR_GROOM_BODY_LIMIT` | `8` | How many candidate descriptions `20-candidates.py` reads (one `get_issue` call each). The cap and the number skipped by it are always printed to stderr |
| `LINEAR_GROOM_EXCERPT_CHARS` | `400` | Length of the per-candidate `excerpt`. The full length is reported separately as `description_chars` |
| `XDG_STATE_HOME` | `~/.local/state` | Parent of the run directory |
