# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin bundling skills for autonomous story execution, adversarial spec/feature review, multi-model answer synthesis, and workflow support. Each skill's full description and its conventions live in `docs/skills/<name>.md` — **read the relevant one when working on that skill**; only session-invariant rules are kept here to stay out of every session's always-on context.

## Plugin Structure

This is a Claude Code plugin (`.claude-plugin/plugin.json`). Skills live under `skills/`, each with:
- `SKILL.md` — The skill definition (frontmatter + instructions Claude follows)
- `scripts/` — Helper scripts, where a skill needs them (e.g. `swarm-execute/templates/swarm-workflow.js`)
- `templates/` — Template files with `{{PLACEHOLDER}}` syntax, where a skill needs them

If hooks are ever added, they live at the plugin root under `hooks/hooks.json` — they are registered globally, not per-skill. (The plugin currently ships no hooks; the former spec-review PostToolUse hook was removed.)

## Skills

Full detail + per-skill conventions are in `docs/skills/`. Read the one you're touching:

| Skill | Doc | One-liner |
|---|---|---|
| `/plan-to-dex` | `docs/skills/plan-to-dex.md` | Superpowers plan → dex `plan.md`, runs dex apply/review (codex backend) |
| `/swarm-execute` | `docs/skills/swarm-execute.md` | Parallel feature build via Workflow; all code by Codex workers in worktrees |
| `/spec-review-codex`, `/spec-review-local` | `docs/skills/spec-review.md` | Adversarial spec review + fix loop (Codex / local LMStudio reviewer) |
| `/handoff` | `docs/skills/handoff.md` | Compact the conversation into a handoff doc for a fresh agent |
| `/orbstack-compatible` | `docs/skills/orbstack-compatible.md` | Migrate Compose project onto OrbStack routable domains (port-collision fix) |
| `/fusion` | `docs/skills/fusion.md` | Blind multi-model panel (Opus + Codex + local) → Opus judge synthesis |
| `/ship-it` | `docs/skills/ship-it.md` | Pure conductor chaining the units into one spec→PR pipeline |
| `/architect-review-pr` | `docs/skills/architect-review-pr.md` | Completeness & wiring review of a finished feature (report-only) |
| `/blind-spot` | `docs/skills/blind-spot.md` | Unknown-unknowns pass *before* starting a task (report-only) |
| `/review-codebase` | `docs/skills/review-codebase.md` | Three parallel whole-repo audits (codebase / docs / process) |
| `/claude-md-slim` | `docs/skills/claude-md-slim.md` | Minimize this file — page per-skill detail out to `docs/` (inverse of claude-md-improver) |

## Development

### Local testing

```bash
claude --plugin-dir ./claude-skills
```

### Distribution

Distributed via marketplace (`.claude-plugin/marketplace.json`). Install/update/uninstall commands are in README.md.

## Key Conventions

Repo-wide rules that apply to any task. Per-skill conventions live in each skill's `docs/skills/<name>.md`.

- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin install path at runtime — always use this in script references shown to users
- Shell scripts use `set -euo pipefail` and require `jq` for JSON parsing
- Hooks live in `hooks/hooks.json` at the plugin root — the plugin system does not discover hooks nested inside skill directories
- **Patch bumps are automatic — do not hand-bump for an ordinary change.** `.github/workflows/bump-version.yml` patch-bumps BOTH `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` on any push to `main` touching `skills/**`, `hooks/**`, or `.claude-plugin/**`, unless that push already changed the version (its `[skip ci]` commit is the loop guard). Bump by hand only for an intentional **minor/major** — and then bump both files together, which also suppresses the bot for that push. A PR with no version change is correct, not an oversight
