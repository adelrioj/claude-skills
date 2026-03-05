# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin with shared skills for autonomous story execution using Ralph — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration.

## Skills

**`/plan-to-ralph`** — Convert a Superpowers implementation plan into Ralph's `prd.json` format. Maps plan tasks to user stories with machine-verifiable acceptance criteria, injects quality gates, and seeds cross-iteration context.

**`/shape-to-ralph`** — Convert shaping artifacts (requirements, breadboard, slices) directly into Ralph's `prd.json` format. No intermediate plan needed — the shaped slices ARE the spec.

**`/swarm-execute`** — Execute `prd.json` stories in parallel using Claude Code Agent Teams. Reads existing `tasks/prd.json` from `/shape-to-ralph` or `/plan-to-ralph`.

The ralph skills each include two execution scripts:
- **`ralph.sh`** — Runs the loop with Claude Code (`claude --print`)
- **`ralph-codex.sh`** — Runs the loop with OpenAI Codex (`codex exec --full-auto`)

## Install

Add as a Claude Code plugin:

```bash
claude plugin add adelrioj/claude-skills
```

Or install locally for development:

```bash
git clone https://github.com/adelrioj/claude-skills.git
claude --plugin-dir ./claude-skills
```

## Uninstall

```bash
claude plugin remove claude-skills
```

## Usage

After converting a plan or shape to `tasks/prd.json`:

```bash
# Claude Code
${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh
${CLAUDE_PLUGIN_ROOT}/skills/shape-to-ralph/scripts/ralph.sh

# OpenAI Codex
${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph-codex.sh --model o3
${CLAUDE_PLUGIN_ROOT}/skills/shape-to-ralph/scripts/ralph-codex.sh --model o4-mini
```

All scripts auto-detect the project root via `git rev-parse --show-toplevel`, so they work correctly from any location.
