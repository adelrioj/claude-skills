# `/review-codebase` — design

## What & why

A launcher skill that fires the three **Fable adversarial audits** — codebase, docs, and
process — from [this gist](https://gist.github.com/diegomarino/04970a2b8d9cc419de3ba05b9a03db5a),
all at once, against the current repo. It automates the gist's launcher (`_fable-audits.txt`):
instead of the user fetching the prompts into `.prompts/` and pasting a `/goal` per prompt,
the skill embeds the three prompts and dispatches one fresh subagent per audit.

Sits alongside the existing review family:
- `/code-review`, `/review-pr` — line-level correctness on a diff.
- `/spec-review-codex` / `-local` — harden the spec before code exists.
- `/architect-review-pr` — completeness & wiring of a finished feature (one subagent).
- **`/review-codebase`** — whole-system adversarial audit across three lenses (three subagents).

## Decisions (approved)

1. **Prompts embedded as templates** — source of truth, self-contained like every skill here.
   SKILL.md documents the gist origin so a maintainer can re-sync deliberately.
2. **Parallel subagents** — three fresh `Agent` subagents fire in one message, each isolated,
   each writing its own report. Keeps raw audit output out of the main loop (fusion pattern).
3. **Report + optional fix pass** — reports land uncommitted; skill then *offers* a remediation
   pass on CRITICAL findings. Never auto-runs, never commits.

## Templates (`skills/review-codebase/templates/`)

| File | Origin |
|------|--------|
| `codebase-audit.md` | gist `fable-audit-codebase.txt`, verbatim (already project-agnostic) |
| `docs-audit.md` | gist `fable-audit-docs.txt`, verbatim (already project-agnostic) |
| `process-audit.md` | gist `fable-audit-process.txt`, **generalized** |

The `/goal` prefix line and its 4KB size caveat are dropped from the embedded copies — a
subagent receives the file as its whole task, so the launcher's "name the file, agent Reads
it" trick isn't needed inside the template; the SKILL.md dispatch does the naming.

**Process-prompt generalization** — the gist's process audit is saturated with
fable/somostodos specifics. Keep: the role (walk every journey twice — human-via-docs and
agent-via-exit-codes), the empirical-in-throwaway-workspace method, the per-record
state-machine build, and the hunt categories (dead ends, missing processes, re-run/second-call
semantics, agent ergonomics, docs/process drift, concurrency). **Drop**: the `# Context`
prior-fix list, the `publication.status`/vault/ingest specifics, and the
`pdftotext`/`tesseract`/`real-smoke-hardening.mjs` shim instructions — replaced with a generic
"test in a throwaway workspace under a gitignored dir; stub external binaries via PATH shims if
the flows need them." Output contract (P1, P2… IDs; `docs/audits/process-audit-<date>.md`) is
kept as-is.

## SKILL.md flow

1. **Preflight** — `git rev-parse --is-inside-work-tree`; STOP if not a repo. Resolve
   `DATE=$(date +%F)`. Target = cwd.
2. **Scope arg** (optional) — `codebase`, `docs`, and/or `process` select a subset; default all
   three. (Mirrors `/fusion`'s seat-override arg.)
3. **Dispatch** — fire one `Agent` subagent (`general-purpose`) per selected audit, **in
   parallel** (one message, N calls). Each prompt:
   > Read `${CLAUDE_PLUGIN_ROOT}/skills/review-codebase/templates/<kind>-audit.md` in full and
   > execute it to the letter against this repository (cwd). Write the report to
   > `docs/audits/<kind>-audit-<DATE>.md` (create the dir). Report-only — make NO code change, do
   > NOT commit or touch git state. Return ONLY the short exec summary the prompt specifies
   > (severity counts + top 3–5 findings + report path).
4. **Consolidate** — print one table: kind | severity counts | report path.
5. **Optional fix pass** — offer to remediate CRITICAL findings. If the user accepts, fix by
   cited ID (Cn/Dn/Pn), leaving changes in the working tree **uncommitted** (reports too —
   maintainer owns git). Never auto-run; never commit.

## Deliberate simplifications (ponytail)

- **Embed, don't fetch** — no network dependency, no `.prompts/` written into the user's repo.
  Re-sync is a documented manual step, not runtime machinery.
- **One subagent per lens, flat parallel** — no dependency graph; the three audits are
  independent. No batching, no merge logic beyond concatenating three summaries.
- **Fix pass is opt-in and dumb** — no fix/re-review convergence loop (that's the spec-review
  family). One offer, one pass, stop. Upgrade path: add a re-review loop only if fixes prove to
  regress reports.
- **No scripts** — dispatch is composed inline in SKILL.md, like `/architect-review-pr`.

## Requirements

None beyond a git repo. No external CLI (subagents are Claude `Agent`s, not `codex`) — installs
anywhere, same as `/architect-review-pr`.
