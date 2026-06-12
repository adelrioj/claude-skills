# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin providing skills for autonomous story execution using "Ralph" — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration — plus two spec review skills that harden brainstorming design specs via adversarial review (one backed by OpenAI Codex, one by a local LMStudio model).

## Plugin Structure

This is a Claude Code plugin (`.claude-plugin/plugin.json`). Skills live under `skills/`, each with:
- `SKILL.md` — The skill definition (frontmatter + instructions Claude follows)
- `scripts/` — Shell scripts (`ralph.sh` for Claude Code, `ralph-codex.sh` for OpenAI Codex)
- `templates/` — Template files (`prd.json`, `progress.txt`, `findings.md`) with `{{PLACEHOLDER}}` syntax

If hooks are ever added, they live at the plugin root under `hooks/hooks.json` — they are registered globally, not per-skill. (The plugin currently ships no hooks; the former spec-review PostToolUse hook was removed.)

## Skills

### `/plan-to-ralph`
Converts a Superpowers implementation plan into `tasks/prd.json`. Reads `docs/superpowers/plans/` for plan files (5.1.0+ default), falling back to `docs/plans/` for legacy repos. Outputs `tasks/prd.json`, `tasks/progress.txt`, `tasks/findings.md`.

### `/swarm-execute`
Parallel feature implementation orchestrated by Claude via the Workflow (ultracode) tool, with all story code written by Codex workers. Takes a plain-language request or a plan/spec file directly — no `prd.json` or `tasks/` files; all state lives in conversation memory and git. The lead decomposes into stories, runs dependency analysis (declared deps, file overlap, cross-references), batches conflict-free, then invokes one Workflow per batch from the static script `skills/swarm-execute/templates/swarm-workflow.js` (parameterized entirely via `args`). Each story: Codex-driven implementation in an isolated worktree → architect + QA review, itself performed by Codex (`--sandbox read-only`) with driver agents translating findings into schema-enforced verdicts → one remediation pass in the persisted worktree → re-review (max 2 attempts). All in-workflow agents run on Haiku — they are process-followers; Codex does the code-level thinking. The lead merges sequentially by priority between workflow invocations. Requires the `codex` CLI.

### `/spec-review-codex`
Adversarial review of design specs using OpenAI Codex (`codex exec`) as an independent reviewer. Sends the spec with a 10-category review checklist, captures findings via `--output-last-message` into a `/tmp` file, fixes CRITICAL and IMPORTANT issues, and loops until the spec passes (max 3 iterations). Requires the `codex` CLI in PATH and authenticated. Codex is invoked with `--sandbox read-only` so it can read the codebase to verify references but cannot modify files.

### `/spec-review-local`
Same review loop, but the reviewer is `pi` backed by whatever LLM is currently loaded in LMStudio at `http://127.0.0.1:1234` — the model id is auto-detected via LMStudio's `/api/v0/models` endpoint, never hardcoded. Requires `pi` CLI in PATH and a model loaded in LMStudio. The reviewer is invoked with `--tools read,grep,find,ls,bash` so it can verify codebase references but cannot modify files; findings are captured via stdout redirection.

Both spec-review skills share the same review prompt (`spec-review-prompt.md`, duplicated per skill so each stays self-contained), the same severity model (CRITICAL/IMPORTANT/MINOR), and the same autonomous fix/re-review loop.

## Architecture: The Ralph Loop

`plan-to-ralph` produces the output format consumed by Ralph scripts:

```
tasks/prd.json       — Stories with acceptance criteria + quality gates
tasks/progress.txt   — Iteration log (append-only)
tasks/findings.md    — Cross-iteration knowledge (architecture decisions, errors, patterns)
```

The ralph scripts (`ralph.sh`) loop: read prd.json -> find lowest-priority incomplete story -> pipe prompt to `claude --print` -> check if story marked complete -> repeat. `ralph-codex.sh` does the same with `codex exec --dangerously-bypass-approvals-and-sandbox`.

Key design: each Ralph iteration is a **fresh AI instance** with no conversation memory. All cross-iteration context flows through `findings.md` and `progress.txt`. The prompt templates (`ralph-prompt.md`, `ralph-codex-prompt.md`) instruct the AI to read these files first.

## Development

### Local testing

```bash
claude --plugin-dir ./claude-skills
```

### Distribution

Distributed via marketplace (`marketplace.json`). Install/update/uninstall commands are in README.md.

## Key Conventions

- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin install path at runtime — always use this in script references shown to users
- Scripts auto-detect project root via `git rev-parse --show-toplevel`
- Quality gate commands are never hardcoded — Ralph reads them from `prd.json.qualityGates`; swarm-execute detects them from the repo (CI config → package.json scripts → ecosystem files → CLAUDE.md) and runs them as individual commands, never `&&`-joined
- `e2eCommand` in prd.json is optional; omit the field entirely if not detected (never set to null/empty). Same rule for swarm-execute's detected e2e command — it runs only at final validation
- Shell scripts use `set -euo pipefail` and require `jq` for JSON parsing
- Ralph scripts track consecutive failures per story and stop after 3 retries (`MAX_STORY_RETRIES=3`)
- Swarm-execute keeps no state on disk — story table, batch plan, merge ledger, and findings digest live in conversation memory; recovery state is git history (story-ID-tagged merge commits) plus persisted worktrees
- Swarm workers delegate ALL code-writing to `codex exec --sandbox workspace-write`, and swarm reviewers delegate review to `codex exec --sandbox read-only` (findings file at `/tmp/swarm-review-b<batch>-<storyId>-<reviewer>-<attempt>.md` via `--output-last-message`) — foreground only, never `--background`, `--resume-last`, or `--dangerously-bypass-approvals-and-sandbox`
- Only the swarm lead merges, sequentially by priority, between Workflow invocations — never agents, never in parallel
- Spec review findings are written to `/tmp/spec-review-findings-<timestamp>.md` — preserved for audit, never committed to the repo
- The spec review loop caps at 3 iterations to prevent infinite fix/re-break cycles
- Hooks live in `hooks/hooks.json` at the plugin root — the plugin system does not discover hooks nested inside skill directories
