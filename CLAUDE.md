# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin bundling skills for autonomous story execution, adversarial spec review, multi-model answer synthesis, and workflow support. Two execution skills drive a feature to completion through external orchestrators — `/plan-to-dex` (the dex orchestrator) and `/swarm-execute` (parallel Codex workers via the Workflow tool). Two spec-review skills harden brainstorming design specs via adversarial review (one backed by OpenAI Codex, one by a local LMStudio model). `/architect-review-pr` runs a fresh-subagent adversarial completeness-and-wiring review over a *finished* feature — report-only, no CLI dependency. `/review-codebase` fires three parallel fresh-subagent audits (codebase, docs, process) over the *whole* repo, each writing a ranked report, then offers an opt-in fix pass. `/fusion` runs a prompt through a blind multi-model panel (Opus subagents + GPT-5.5 via Codex + a local LMStudio model via `pi`) and has Opus judge and synthesize one grounded answer. `/ship-it` chains the existing units into one autonomous spec→PR pipeline. `/orbstack-compatible` migrates a Docker Compose project onto OrbStack routable domains to end host-port collisions. `/handoff` rounds it out — compact a conversation for a fresh agent.

## Plugin Structure

This is a Claude Code plugin (`.claude-plugin/plugin.json`). Skills live under `skills/`, each with:
- `SKILL.md` — The skill definition (frontmatter + instructions Claude follows)
- `scripts/` — Helper scripts, where a skill needs them (e.g. `swarm-execute/templates/swarm-workflow.js`)
- `templates/` — Template files with `{{PLACEHOLDER}}` syntax, where a skill needs them

If hooks are ever added, they live at the plugin root under `hooks/hooks.json` — they are registered globally, not per-skill. (The plugin currently ships no hooks; the former spec-review PostToolUse hook was removed.)

## Skills

### `/plan-to-dex`
Translates a Superpowers implementation plan into a [dex](https://github.com/francescoalemanno/dex)-compatible `plan.md`, imports it via `dex import`, and runs dex's `apply`/`review` loop end to end. Backend is fixed to codex (`dex --cli codex`); the skill sets no model and never writes `.dex/config.json`. One source Task = one `### Task N:` heading = one dex iteration. Output: `tasks/dex-plan.md`. Requires the `dex` and `codex` CLIs. Refuses to run `dex apply` on `main`/`master` — resolves a feature branch first.

### `/swarm-execute`
Parallel feature implementation orchestrated by Claude via the Workflow (ultracode) tool, with all story code written by Codex workers. Takes a plain-language request or a plan/spec file directly — no `prd.json` or `tasks/` files; all state lives in conversation memory and git. The lead decomposes into stories, runs dependency analysis (declared deps, file overlap, cross-references), batches conflict-free, then invokes one Workflow per batch from the static script `skills/swarm-execute/templates/swarm-workflow.js` (parameterized entirely via `args`). Each story: Codex-driven implementation in an isolated worktree → architect + QA review, itself performed by Codex (`--sandbox read-only`) with driver agents translating findings into schema-enforced verdicts → one remediation pass in the persisted worktree → re-review (max 2 attempts). All in-workflow agents run on Haiku — they are process-followers; Codex does the code-level thinking. The lead merges sequentially by priority between workflow invocations. Requires the `codex` CLI.

### `/spec-review-codex`
Adversarial review of design specs using OpenAI Codex (`codex exec`) as an independent reviewer. Sends the spec with a 10-category review checklist, captures findings via `--output-last-message` into a `/tmp` file, fixes CRITICAL and IMPORTANT issues, and loops until the spec passes (max 3 iterations). Requires the `codex` CLI in PATH and authenticated. Codex is invoked with `--sandbox read-only` so it can read the codebase to verify references but cannot modify files.

### `/spec-review-local`
Same review loop, but the reviewer is `pi` backed by whatever LLM is currently loaded in LMStudio at `http://127.0.0.1:1234` — the model id is auto-detected via LMStudio's `/api/v0/models` endpoint, never hardcoded. Requires `pi` CLI in PATH and a model loaded in LMStudio. The reviewer is invoked with `--tools read,grep,find,ls,bash` so it can verify codebase references but cannot modify files; findings are captured via stdout redirection.

Both spec-review skills share the same review prompt (`spec-review-prompt.md`, duplicated per skill so each stays self-contained — keep the two copies byte-identical), the same severity model (CRITICAL/IMPORTANT/ADVISORY/MINOR), and the same autonomous fix/re-review loop. The prompt classifies the spec by *altitude* (design vs detailed-implementation): for a design spec, a coverage rule anchored on a named source of truth (characterization suite, golden master, referenced source range) counts as complete, so enumeration-completeness observations are ADVISORY (non-blocking), not IMPORTANT. Only CRITICAL and IMPORTANT block PASS and drive the loop.

### `/handoff`
Compacts the current conversation into a handoff document so a fresh agent can pick up the work. Writes to the OS temp directory (never the workspace), includes a "suggested skills" section, references existing artifacts (PRDs, plans, ADRs, issues, diffs) by path rather than duplicating them, and redacts secrets/PII. Accepts an optional argument describing what the next session will focus on.

### `/orbstack-compatible`
Transforms an arbitrary Docker Compose project to use OrbStack routable domains so
containerized services stop colliding on host ports across worktrees/projects. General
(any `docker-compose*.yml`), edits files directly then verifies live. Requires OrbStack as
the active Docker engine — aborts with setup guidance otherwise. Strips `ports:` from the
base compose; re-adds them in an **opt-in** `docker-compose.ports.yml` (NOT the
auto-merged `override.yml`) for Windows/CI; rewrites local env connection URLs to
`<service>.${COMPOSE_PROJECT_NAME:-<folder>}.orb.local:<container-port>` (default per-project
domain, never a custom `dev.orbstack.domains` label that would re-collide across worktrees).
Host-run dev-server ports are document-only — OrbStack can't route to host processes.

### `/fusion`
Runs a prompt through a blind multi-model panel (2× Opus subagents + GPT-5.5 via `codex exec --sandbox workspace-write` + local LMStudio model via `pi`) then has a separate Opus judge synthesize the responses into a single verdict. Subscription-only: Opus seats use Agent subagents; Codex and `pi` seats use authenticated CLIs. Accepts an optional `opus`/`codex`/`local` override argument to restrict to a single seat. The local panelist auto-detects the loaded LMStudio model via `/api/v0/models` (override base URL with `FUSION_LMSTUDIO_URL`), never hardcoding a model id. Any unavailable seat (missing CLI, unloaded model, timeout) is dropped gracefully and the panel continues. Provenance is written to `~/.claude/fusion-runs/`, never committed. Ported from fusion-fable (MIT); the Gemini/`agy` seat and its PTY/bug-#76 workaround are intentionally dropped in favor of the local `pi`/LMStudio seat.

### `/ship-it`
Pure conductor that chains the existing units into one autonomous spec→PR pipeline. Six-step sequential process: hardens the spec via `/spec-review-codex`, writes the implementation plan, executes it via `/plan-to-dex`, opens a PR with `/commit-commands:commit-push-pr`, runs `/review-pr` and fixes CRITICAL/IMPORTANT findings (up to 3 passes); merging stays manual. A preflight (codex + dex on PATH, `pr-review-toolkit` + `commit-commands` plugins present via an on-disk command-file check, spec located) is the sole hard abort. The heavy Skill steps (1/2/4) run as **execute-and-report subagents** that return only a structured three-field contract, keeping raw codex/dex output out of the conductor's context; Steps 3/5/6 run in the main loop, with one boundary-verifier subagent after PR-review. Never halts on quality findings; records any leftover issues in a final report. Requires the `codex` and `dex` CLIs plus the `pr-review-toolkit` and `commit-commands` plugins.

### `/architect-review-pr`
Adversarial **completeness & wiring** review of a finished feature — the diagnostic pass that runs after `/review-pr`, answering "is this actually done and integrated?" (not "is each line correct?", which is `/code-review` / `/review-pr`). Dispatches ONE fresh-context Claude `Agent` subagent (no `codex` dependency — installs anywhere) that scopes findings to the branch diff vs base (`main`/`master`) but traces the WHOLE repo to confirm reachability, running a fixed 5-type taxonomy (Unwired / Missing / Incomplete / Bug-edge / Risk) behind a mandatory **evidence gate**: no `Unwired`/`Missing` finding is reported without a cited empty-result search proving the gap — else it is downgraded to a question. **Report-only** — a finder like `/ponytail-audit`, never a fixer; writes the ranked report to `/tmp/architect-review-pr-<ts>.md` (uncommitted) and STOPs. Auto-discovers an intent oracle (newest `*-design.md` or `tasks/` plan) best-effort, degrading to code-only. No scripts or templates — the subagent prompt is composed inline in `SKILL.md`.

### `/review-codebase`
Fires the three **Fable adversarial audits** (codebase / docs / process, from [this gist](https://gist.github.com/diegomarino/04970a2b8d9cc419de3ba05b9a03db5a)) against the *whole current repo* at once — the whole-system counterpart to `/architect-review-pr`'s single-feature wiring pass. The three prompts are **embedded as templates** (`skills/review-codebase/templates/{codebase,docs,process}-audit.md`); the skill dispatches ONE fresh Claude `Agent` subagent per lens **in parallel** (no `codex` dependency), each Reading its template and executing it against the cwd, each writing a ranked, ID'd report (`C…`/`D…`/`P…`) to `docs/audits/<kind>-audit-<YYYY-MM-DD>.md`, returning only a short exec summary. The lead consolidates the three summaries into one table, then **offers an opt-in fix pass** on CRITICAL findings (single pass, by cited ID) — never automatic, and reports+fixes always left **uncommitted** (maintainer owns git). Optional arg selects a subset of lenses; default all three. `codebase`/`docs` templates are verbatim from the gist; `process` is **generalized** — the gist's is project-specific, so the embedded copy keeps role/method/hunt/output but drops the fable-only context. No external CLI — installs anywhere.

## Development

### Local testing

```bash
claude --plugin-dir ./claude-skills
```

### Distribution

Distributed via marketplace (`.claude-plugin/marketplace.json`). Install/update/uninstall commands are in README.md.

## Key Conventions

- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin install path at runtime — always use this in script references shown to users
- `/plan-to-dex` pins the dex backend to codex and never writes `.dex/config.json` — the model is codex's own default; dex owns all execution state under `.dex/`
- BOTH `dex apply` and `dex review` are long-running (each exceeds the 10-min foreground Bash ceiling) — `/plan-to-dex` Step 6 mandates the same foreground poll-to-completion loop for each (re-run the phase, re-read `.dex/plan.md`, until all checkboxes `[x]` or terminal; `dex review`'s terminal includes the codex-quota case once apply is fully done and ≥1 reviewer pass has written findings) and forbids `run_in_background`/`Monitor`/"arm a watcher and yield". The guard has teeth via a **mandatory pre-return checklist** — the invocation must run and report `grep -c '\[ \]' .dex/plan.md` → `0`, `pgrep -fl 'dex --cli codex|codex exec'` empty, and per-task dex commits present before returning. `/ship-it`'s execute-and-report subagent prompt carries the identical FORBIDDEN list + pre-return checklist, because a subagent's backgrounded processes are reaped on return — backgrounding leaves only the dex setup commit
- Quality gate commands are never hardcoded — swarm-execute detects them from the repo (CI config → package.json scripts → ecosystem files → CLAUDE.md) and runs them as individual commands, never `&&`-joined; plan-to-dex names them in each dex checkbox
- A detected e2e command is optional — omit it entirely if not detected (never set to null/empty); swarm-execute runs it only at final validation
- Swarm-execute keeps no state on disk — story table, batch plan, merge ledger, and findings digest live in conversation memory; recovery state is git history (story-ID-tagged merge commits) plus persisted worktrees
- Swarm workers delegate ALL code-writing to `codex exec --sandbox workspace-write`, and swarm reviewers delegate review to `codex exec --sandbox read-only` (findings file at `/tmp/swarm-review-b<batch>-<storyId>-<reviewer>-<attempt>.md` via `--output-last-message`) — foreground only, never `--background`, `--resume-last`, or `--dangerously-bypass-approvals-and-sandbox`
- Only the swarm lead merges, sequentially by priority, between Workflow invocations — never agents, never in parallel
- Spec review findings are written to `/tmp/spec-review-findings-<timestamp>.md` — preserved for audit, never committed to the repo
- The spec review loop caps at 3 iterations to prevent infinite fix/re-break cycles, and also stops early as PASS-with-notes if successive iterations' IMPORTANT findings converge on finer-grained enumeration of the same concern rather than new substance (enumeration-creep detection)
- Spec review verdicts are altitude-calibrated: PASS requires zero CRITICAL and zero IMPORTANT; ADVISORY/MINOR never block. Findings that demand a design spec re-enumerate detail a named source of truth already pins must be reframed as a coverage rule (with a `Decision:` note), not enumerated — the altitude analogue of "never change the architectural approach"
- `/handoff` writes only to the OS temp directory and references existing artifacts by path instead of duplicating them
- Shell scripts use `set -euo pipefail` and require `jq` for JSON parsing
- Hooks live in `hooks/hooks.json` at the plugin root — the plugin system does not discover hooks nested inside skill directories
- `/orbstack-compatible` keeps the OrbStack fallback in an **opt-in** `docker-compose.ports.yml`, never `docker-compose.override.yml` — Compose auto-merges `override.yml`, which would re-publish host ports for OrbStack users and defeat the transform
- `/orbstack-compatible` relies on OrbStack's default `<service>.<project>.orb.local` domain (unique per worktree via `COMPOSE_PROJECT_NAME`) and never sets a custom `dev.orbstack.domains` label — a fixed custom domain would be claimed by every worktree and re-collide
- `/orbstack-compatible` keeps connection config env-driven (domain in local env files, `localhost:PORT` in CI via the ports overlay) and never bakes `.orb.local` into source code or test fixtures
- `/fusion` panelists are subscription-only — Opus via Agent subagents, GPT-5.5 via authenticated `codex`, local via `pi`/LMStudio; no API keys anywhere
- `/fusion` runs the codex panelist with `--sandbox workspace-write` (never the banned `--dangerously-bypass-approvals-and-sandbox`); web search via `-c tools.web_search=true`
- `/fusion` auto-detects the loaded LMStudio model via `/api/v0/models` (override base URL with `FUSION_LMSTUDIO_URL`), never hardcoding a model id — same pattern as `/spec-review-local`
- `/fusion` provenance lives in `~/.claude/fusion-runs/`, never committed; any panelist seat degrades gracefully (missing CLI / unloaded model / timeout → dropped, panel continues)
- `/fusion` is a port of fusion-fable (MIT); the Gemini/`agy` seat and its PTY/bug-#76 workaround are intentionally dropped in favor of the local `pi`/LMStudio seat
- `/ship-it` is a pure conductor — it invokes spec-review-codex, writing-plans, plan-to-dex, /commit-commands:commit-push-pr, and /review-pr LIVE and duplicates none of their logic
- `/ship-it` is best-effort and never halts on quality; the only hard abort is a failed preflight; a hard failure that makes the next step impossible skips downstream steps and jumps to the final report — it never fabricates a downstream artifact (no empty PR)
- `/ship-it` keeps no state on disk except the final report, which is written /handoff-style to the OS temp dir, never the workspace
- `/ship-it` runs the heavy Skill steps (1/2/4) as execute-and-report subagents that return only a three-field contract (outcome/state/notes), keeping raw codex/dex output out of the conductor's context; Steps 3/5/6 run in the main loop. The zero-diff check is always verified against git in the conductor's own shell, never from a subagent summary, so a mis-summary can't fabricate a PR
- `/architect-review-pr` is report-only — it dispatches a fresh Claude subagent and fixes nothing (contrast the spec-review family's fix loop); the only on-disk artifact is the `/tmp/architect-review-pr-<ts>.md` audit report, never committed
- `/architect-review-pr` uses a Claude `Agent` subagent, not `codex` — deliberately no external CLI dependency so it installs anywhere; the subagent is read-only and returns its markdown report as its final message (no machine-readable contract to parse, unlike ship-it's three-field hand-off)
- `/architect-review-pr`'s evidence gate is the quality lever: no `Unwired`/`Missing` finding ships without a cited empty-result search (callers, string-keyed dispatch, DI/decorator, barrel re-exports, dynamic dispatch, config/CI/manifest) proving the gap — an uncited claim is downgraded to a question, not reported
- `/architect-review-pr` scopes FINDINGS to the branch diff vs base but traces the WHOLE repo for reachability — a diff-only review can't distinguish "created but not wired" from "wired elsewhere"; an explicit file/dir/feature argument overrides diff scoping, and no-diff-no-argument is the only blocking question
- `/review-codebase` embeds the three gist audit prompts as `skills/review-codebase/templates/{codebase,docs,process}-audit.md` (source of truth, never fetched at runtime) and fires one fresh Claude `Agent` subagent per lens IN PARALLEL — the whole-repo counterpart to `/architect-review-pr`'s single-feature pass; each subagent Reads its template and runs it against the cwd, so the launcher's 4KB `/goal` limit never applies
- `/review-codebase` reports land in `docs/audits/<kind>-audit-<YYYY-MM-DD>.md` (uncommitted, maintainer owns git); the fix pass is OPT-IN and single-pass (address CRITICAL by cited `C…`/`D…`/`P…` ID, then STOP) — never auto-run, never committed, and NOT the spec-review family's converging fix/re-review loop
- `/review-codebase`'s `codebase`/`docs` templates are byte-verbatim from the gist; `process` is deliberately GENERALIZED (gist original is project-specific to fable's ingest/vault/publication flows) — keep role/method/hunt/output, drop the fable-only context; re-sync from the gist is a documented manual step, never runtime machinery
