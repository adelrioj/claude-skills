# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin bundling skills for autonomous story execution, adversarial spec review, and workflow support. Two execution skills drive a feature to completion through external orchestrators — `/plan-to-dex` (the dex orchestrator) and `/swarm-execute` (parallel Codex workers via the Workflow tool). Two spec-review skills harden brainstorming design specs via adversarial review (one backed by OpenAI Codex, one by a local LMStudio model). Two helpers round it out — `/handoff` (compact a conversation for a fresh agent) and `/sprint-status-update` (Notion sprint board → Slack recap).

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

### `/sprint-status-update`
Generates a company-wide Slack message summarizing the current sprint by querying the Notion sprint board (and bug-reports database), categorizing deliveries, and formatting a scannable update. Database URLs and data-source collection ids are pinned in the skill; the active sprint is detected from the board's view-exclusion filter. Use on Fridays or at sprint boundaries.

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
