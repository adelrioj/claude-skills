# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin with shared skills for autonomous story execution using Ralph — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration.

## Skills

**`/plan-to-ralph`** — Convert a Superpowers implementation plan into Ralph's `prd.json` format. Maps plan tasks to user stories with machine-verifiable acceptance criteria, injects quality gates, and seeds cross-iteration context.

**`/shape-to-ralph`** — Convert shaping artifacts (requirements, breadboard, slices) directly into Ralph's `prd.json` format. No intermediate plan needed — the shaped slices ARE the spec.

**`/swarm-execute`** — Execute `prd.json` stories in parallel using Claude Code Agent Teams. Reads existing `tasks/prd.json` from `/shape-to-ralph` or `/plan-to-ralph`.

**`/brainstorming-spec-review`** — Adversarial review of design specs using Codex as an independent reviewer. Sends the spec to Codex for rigorous review against a 10-category checklist, fixes CRITICAL and IMPORTANT findings, and loops until the spec passes with zero blocking issues (max 3 iterations). Designed to catch bugs, contradictions, ambiguities, and gaps that self-review misses due to author bias.

The ralph skills each include two execution scripts:
- **`ralph.sh`** — Runs the loop with Claude Code (`claude --print`)
- **`ralph-codex.sh`** — Runs the loop with OpenAI Codex (`codex exec --full-auto`)

## Install

Add the marketplace, then install the plugin:

```bash
claude plugin marketplace add adelrioj/claude-skills
claude plugin install claude-skills@claude-skills-marketplace
```

Restart Claude Code for the plugin to load.

## Update

```bash
claude plugin marketplace update claude-skills-marketplace
claude plugin update claude-skills@claude-skills-marketplace
```

## Uninstall

```bash
claude plugin uninstall claude-skills@claude-skills-marketplace
```

To also remove the marketplace:

```bash
claude plugin marketplace remove claude-skills-marketplace
```

## Local Development

For developing the plugin locally (session-only):

```bash
git clone https://github.com/adelrioj/claude-skills.git
claude --plugin-dir ./claude-skills
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

## Automatic Spec Review After Brainstorming

This plugin includes a PostToolUse hook that automatically triggers `/brainstorming-spec-review` when the Superpowers brainstorming skill writes a design spec (any file matching `specs/*-design.md`).

**What happens:**

1. You run `/brainstorming` as usual and iterate on the design
2. Brainstorming writes the spec to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
3. The hook detects the spec file and tells Claude to invoke `/brainstorming-spec-review`
4. Claude sends the spec to Codex for adversarial review
5. Codex returns findings (CRITICAL / IMPORTANT / MINOR) with a PASS or NEEDS REVISION verdict
6. Claude fixes CRITICAL and IMPORTANT findings, then re-sends to Codex
7. Loop continues until Codex returns PASS (max 3 iterations)
8. Brainstorming continues to the user review step with a hardened spec

**Requirements:**

- [OpenAI Codex CLI](https://github.com/openai/codex) installed and authenticated (`codex` available in PATH)
- The hook fires automatically — no manual invocation needed after install

**Manual invocation:**

You can also run the review independently on any spec file:

```
/brainstorming-spec-review docs/superpowers/specs/2026-04-10-my-feature-design.md
```

Or without arguments to auto-detect the most recent spec:

```
/brainstorming-spec-review
```

**Disabling the hook:**

To use brainstorming without automatic Codex review, remove or rename `hooks/hooks.json` in the plugin directory and restart Claude Code.
