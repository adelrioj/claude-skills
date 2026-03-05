# Claude Skills

Shared [Claude Code](https://claude.com/claude-code) skills for autonomous story execution using Ralph — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration.

## Skills

**`/plan-to-ralph`** — Convert a Superpowers implementation plan into Ralph's `prd.json` format. Maps plan tasks to user stories with machine-verifiable acceptance criteria, injects quality gates, and seeds cross-iteration context.

**`/shape-to-ralph`** — Convert shaping artifacts (requirements, breadboard, slices) directly into Ralph's `prd.json` format. No intermediate plan needed — the shaped slices ARE the spec.

**`/swarm-execute`** — Execute `prd.json` stories in parallel using Claude Code Agent Teams. Reads existing `tasks/prd.json` from `/shape-to-ralph` or `/plan-to-ralph`.

The ralph skills each include two execution scripts:
- **`ralph.sh`** — Runs the loop with Claude Code (`claude --print`)
- **`ralph-codex.sh`** — Runs the loop with OpenAI Codex (`codex exec --full-auto`)

## Install

```bash
git clone https://github.com/adelrioj/claude-skills.git ~/.local/share/claude-skills
~/.local/share/claude-skills/install.sh
```

## Uninstall

```bash
rm ~/.claude/skills/plan-to-ralph ~/.claude/skills/shape-to-ralph ~/.claude/skills/swarm-execute
rm -rf ~/.local/share/claude-skills
```

## Update

```bash
cd ~/.local/share/claude-skills && git pull
```

Changes apply immediately to all projects — symlinks point to the repo.

## Usage

After converting a plan or shape to `tasks/prd.json`:

```bash
# Claude Code
.claude/skills/plan-to-ralph/scripts/ralph.sh
.claude/skills/shape-to-ralph/scripts/ralph.sh

# OpenAI Codex
.claude/skills/plan-to-ralph/scripts/ralph-codex.sh --model o3
.claude/skills/shape-to-ralph/scripts/ralph-codex.sh --model o4-mini
```

All scripts auto-detect the project root via `git rev-parse --show-toplevel`, so they work correctly when symlinked from any project.
