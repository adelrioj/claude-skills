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
Parallel execution of `prd.json` stories using Claude Code Agent Teams. Performs dependency analysis (text scanning, file overlap, affordance cross-references), generates parallel batches, spawns teammates in worktrees, runs architect + QA review gates per story, and merges sequentially by priority.

### `/spec-review-codex`
Adversarial review of design specs using OpenAI Codex (`codex exec`) as an independent reviewer. Sends the spec with a 10-category review checklist, reads findings from a `/tmp` file Codex writes, fixes CRITICAL and IMPORTANT issues, and loops until the spec passes (max 3 iterations). Requires the `codex` CLI in PATH and authenticated. Codex is invoked with `--dangerously-bypass-approvals-and-sandbox` so it can read the codebase and write the findings file.

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

The ralph scripts (`ralph.sh`) loop: read prd.json -> find lowest-priority incomplete story -> pipe prompt to `claude --print` -> check if story marked complete -> repeat. `ralph-codex.sh` does the same with `codex exec --full-auto`.

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
- Quality gate commands are never hardcoded — they're read from `prd.json.qualityGates` array at runtime
- `e2eCommand` in prd.json is optional; omit the field entirely if not detected (never set to null/empty)
- Shell scripts use `set -euo pipefail` and require `jq` for JSON parsing
- Ralph scripts track consecutive failures per story and stop after 3 retries (`MAX_STORY_RETRIES=3`)
- Swarm teammates never touch shared files (`prd.json`, `progress.txt`, `findings.md`, `swarm-state.json`) — only the lead orchestrator writes to these
- Spec review findings are written to `/tmp/spec-review-findings-<timestamp>.md` — preserved for audit, never committed to the repo
- The spec review loop caps at 3 iterations to prevent infinite fix/re-break cycles
- Hooks live in `hooks/hooks.json` at the plugin root — the plugin system does not discover hooks nested inside skill directories
