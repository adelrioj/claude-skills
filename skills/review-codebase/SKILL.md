---
name: review-codebase
description: "Use to run a whole-system adversarial audit of the current repo across three lenses at once — codebase (defects, incoherences, affordance gaps), docs (drift, structure, coverage), and process (end-to-end workflow dead ends). Dispatches three fresh Claude subagents in parallel, each writing a ranked findings report to docs/audits/, then offers an optional fix pass on CRITICAL findings. Triggers on: review codebase, audit codebase, audit this repo, adversarial audit, codebase audit, docs audit, process audit, fable audit, three reviews, full audit, whole-system review, find everything wrong."
user-invocable: true
---

# Review Codebase — Three-Lens Adversarial Audit

Fires the three **Fable adversarial audits** — codebase, docs, and process — against the
current repository, all at once. It automates the launcher from
[this gist](https://gist.github.com/diegomarino/04970a2b8d9cc419de3ba05b9a03db5a): instead
of fetching the prompts into `.prompts/` and pasting a `/goal` per prompt, the three prompts
are **embedded as templates** and each is dispatched to its own fresh-context subagent.

**Where it sits in the review family:**
- `/code-review`, `/review-pr` — line-level *correctness* on a diff.
- `/spec-review-codex` / `-local` — harden the *spec, before* code exists.
- `/architect-review-pr` — *completeness & wiring* of one finished feature (one subagent).
- **`/review-codebase`** — *whole-system* audit across three lenses (three subagents). This skill.

**Why fresh subagents (the adversarial mechanism).** Each audit re-derives its findings from
the code alone, with no memory of how the system was built — the same independence rationale
as `/architect-review-pr`. Three run in **parallel**, isolated, so each full-repo audit's raw
output stays out of the main loop. No external CLI — subagents
are Claude `Agent`s, so the skill installs anywhere.

**Report + optional fix.** Each audit is report-first: it writes a ranked, ID'd findings report
to `docs/audits/` and returns only a short summary. After the three land, the skill *offers* a
remediation pass on CRITICAL findings — opt-in, never automatic, never committed.

---

## Flow

### Step 0 — Preflight & scope

1. **In a git repo?** Run `git rev-parse --is-inside-work-tree`. If it fails, STOP with:
   > "Not in a git repository — nothing to audit."
2. **Resolve the date once:** `DATE=$(date +%F)`. Target repo = current working directory.
3. **Which lenses?** Parse the optional argument for `codebase`, `docs`, and/or `process`
   (any subset, space/comma-separated). Default = **all three**.

Announce the resolved scope in one line, then proceed:
> "Auditing `<repo>` across <lenses>. Dispatching <N> subagent(s) in parallel."

### Step 1 — Dispatch the audits in parallel

For each selected lens, dispatch one fresh subagent via the **Agent tool**
(`subagent_type: general-purpose`). Fire them **in a single message, one Agent call per lens**,
so they run concurrently.

First resolve the templates dir to an **absolute path** and substitute it into each prompt —
a subagent's Read tool will not expand `${CLAUDE_PLUGIN_ROOT}`. Run
`echo "${CLAUDE_PLUGIN_ROOT}/skills/review-codebase/templates"` in Bash and use the printed
path as `<TEMPLATES>` below. Each subagent's prompt (substitute `<TEMPLATES>`,
`<KIND>` = `codebase`/`docs`/`process`, and `<DATE>`):

```
Read <TEMPLATES>/<KIND>-audit.md in full and
execute its instructions to the letter against THIS repository (the current working
directory) — that file is your task spec, not reference to summarize or improve. Stay
strictly within the scope it defines.

Write the full report to docs/audits/<KIND>-audit-<DATE>.md (create the directory if
missing). REPORT-ONLY: make no code change, and do not commit, push, or otherwise touch git
state — the maintainer owns git. Leave the report uncommitted.

Use this severity scale for every finding and in the summary counts: CRITICAL / IMPORTANT /
ADVISORY / MINOR.

Write the report INCREMENTALLY as you go — create the file as soon as you have your first
finding and append each one as you confirm it. Do not compose the whole report at the end: if
this invocation ends without the file on disk, the audit is lost, and nobody can ask you for it
afterwards.

Not done until the prompt's Output/stop criteria are met exactly as written. Return ONLY the
short exec summary the prompt specifies (per-severity counts + top 3-5 findings + the report
path) — the full detail lives in the file, and the file is what the caller reads.
```

The `process` audit is empirical: it builds throwaway workspaces under a gitignored dir and may
stub external binaries via PATH shims — that is expected and stays out of the real tree.

### Step 2 — Consolidate

**Read each lens's report from its own path** — `docs/audits/<KIND>-audit-<DATE>.md`, which you
fixed at Step 0 and passed into the prompt. Do not build the table from the subagents' returned
summaries: a subagent that finishes its audit and then ends without a final message leaves no
summary to collect, and the report on disk is complete regardless. The return is corroboration;
the file is the deliverable.

For each selected lens, `test -f` its report:

- **Present** → take the counts and top findings from the file.
- **Missing** → that audit produced nothing. Say so plainly in the table row and move on. Never
  re-dispatch, and never substitute another lens's or an earlier run's report — a `<DATE>`-stamped
  path from a previous audit of the same repo will happily exist and quietly report stale findings
  as today's.

Then print one table:

| lens | CRITICAL | IMPORTANT | ADVISORY | MINOR | report |
|------|---------:|----------:|---------:|------:|--------|
| codebase | … | … | … | … | `docs/audits/codebase-audit-<DATE>.md` |
| docs | … | … | … | … | `docs/audits/docs-audit-<DATE>.md` |
| process | … | … | … | … | `docs/audits/process-audit-<DATE>.md` |

Below it, list the top findings each audit surfaced (by ID). If a lens's report file is absent — the only evidence that matters, whether or not its subagent returned anything — say so plainly. If a subagent failed or produced
no report, say so plainly — do not fabricate a summary.

### Step 3 — Offer a fix pass (opt-in)

If any audit reported CRITICAL findings, ask:
> "N CRITICAL findings across the reports. Want me to fix them now? (Reports and any fixes stay
> uncommitted — you own git.)"

- If **yes**: address CRITICAL findings by cited ID (Cn/Dn/Pn), reading each report for the
  file:line and scenario. Leave every change in the working tree **uncommitted**. One pass —
  no fix/re-review convergence loop (that's the spec-review family). Then STOP.
- If **no** (or no CRITICALs): STOP. The reports are the deliverable.

Never auto-run the fix pass. Never commit — not the reports, not the fixes.

---

## Templates

Embedded under `templates/`, the source of truth for what each subagent runs:

| File | Lens |
|------|------|
| `codebase-audit.md` | Defects, incoherences, affordance mismatches, doc drift, DX (IDs `C1…`). |
| `docs-audit.md` | Doc drift, inverted-pyramid, sizing, missing diagrams, coverage (IDs `D1…`). |
| `process-audit.md` | End-to-end workflow dead ends, missing transitions, re-run semantics (IDs `P1…`). |

Ported from the gist above (MIT-spirited author prompts). `codebase` and `docs` are verbatim;
`process` is **generalized** — the gist's version is written for one specific project (its
ingest/vault/publication lifecycle and `pdftotext` shims), so the embedded copy keeps the role,
method, hunt categories, and output contract but drops the project-specific context. To re-sync
after the gist changes, re-fetch with
`gh gist view 04970a2b8d9cc419de3ba05b9a03db5a -f fable-audit-<kind>.txt -r` and reconcile by
hand (keep the `process` generalization).

---

## What this skill is NOT

- **Not a diff review** — it audits the *whole* repo, not a branch's changes. For line-level
  correctness on a diff use `/code-review` or `/review-pr`; for one feature's wiring use
  `/architect-review-pr`.
- **Not a fix-loop** — the fix pass is a single opt-in remediation, not the spec-review family's
  converging fix/re-review cycle.
- **Not a committer** — reports and fixes always land uncommitted; the maintainer owns git.

## Deliberate simplifications (ponytail)

- **Embed, don't fetch** — no network dependency and no `.prompts/` written into the user's
  repo. Re-sync is a documented manual step, not runtime machinery.
- **One subagent per lens, flat parallel** — the three audits are independent; no dependency
  graph, no batching, no merge logic beyond concatenating three summaries.
- **Fix pass is opt-in and single-pass** — no convergence/enumeration-creep machinery. Upgrade
  path: add a re-review loop only if fixes prove to regress reports.
- **No scripts** — the dispatch prompt is composed inline here, like `/architect-review-pr`.
