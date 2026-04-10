# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin providing three skills for autonomous story execution using "Ralph" — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration.

## Plugin Structure

This is a Claude Code plugin (`.claude-plugin/plugin.json`). Skills live under `skills/`, each with:
- `SKILL.md` — The skill definition (frontmatter + instructions Claude follows)
- `scripts/` — Shell scripts (`ralph.sh` for Claude Code, `ralph-codex.sh` for OpenAI Codex)
- `templates/` — Template files (`prd.json`, `progress.txt`, `findings.md`) with `{{PLACEHOLDER}}` syntax

## Skills

### `/plan-to-ralph`
Converts a Superpowers implementation plan into `tasks/prd.json`. Reads `docs/plans/` for plan files. Outputs `tasks/prd.json`, `tasks/progress.txt`, `tasks/findings.md`.

### `/shape-to-ralph`
Converts shaping artifacts (requirements, breadboard, slices) directly into `tasks/prd.json`. Reads `docs/shaping/` for shaping docs. Same output files as plan-to-ralph.

### `/swarm-execute`
Parallel execution of `prd.json` stories using Claude Code Agent Teams. Performs dependency analysis (text scanning, file overlap, affordance cross-references), generates parallel batches, spawns teammates in worktrees, runs architect + QA review gates per story, and merges sequentially by priority.

## Architecture: The Ralph Loop

Both `plan-to-ralph` and `shape-to-ralph` produce the same output format consumed by Ralph scripts:

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
