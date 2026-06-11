# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin with shared skills for autonomous story execution using Ralph — a loop that reads `tasks/prd.json` and drives Claude Code or OpenAI Codex through one user story per iteration.

## Skills

**`/plan-to-ralph`** — Convert a Superpowers implementation plan into Ralph's `prd.json` format. Maps plan tasks to user stories with machine-verifiable acceptance criteria, injects quality gates, and seeds cross-iteration context.

**`/swarm-execute`** — Execute `prd.json` stories in parallel using Claude Code Agent Teams. Reads existing `tasks/prd.json` from `/plan-to-ralph`.

**`/spec-review-codex`** — Adversarial review of design specs using OpenAI Codex as an independent reviewer. Sends the spec to Codex for rigorous review against a 10-category checklist, fixes CRITICAL and IMPORTANT findings, and loops until the spec passes with zero blocking issues (max 3 iterations). Designed to catch bugs, contradictions, ambiguities, and gaps that self-review misses due to author bias.

**`/spec-review-local`** — Same adversarial review loop, but the reviewer is a local model served by [LMStudio](https://lmstudio.ai) via the `pi` CLI. Auto-detects whatever LLM is currently loaded in LMStudio — no hardcoded model. Works fully offline; the reviewer is restricted to read-only tools.

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

After converting a plan to `tasks/prd.json`:

```bash
# Claude Code
${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh

# OpenAI Codex
${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph-codex.sh --model o3
```

All scripts auto-detect the project root via `git rev-parse --show-toplevel`, so they work correctly from any location.

## Spec Review

Two interchangeable skills run an adversarial review loop over brainstorming design specs (any file matching `docs/superpowers/specs/*-design.md`):

| Skill | Reviewer | Requirements |
|-------|----------|--------------|
| `/spec-review-codex` | OpenAI Codex (`codex exec`) | [Codex CLI](https://github.com/openai/codex) installed and authenticated |
| `/spec-review-local` | Local model via `pi` + LMStudio | `pi` in PATH, LMStudio running at `http://127.0.0.1:1234` with an LLM loaded |

**What happens:**

1. The skill locates the spec (argument, or the most recent `*-design.md` in `docs/superpowers/specs/`)
2. The spec is sent to the reviewer with a 10-category review checklist
3. The reviewer verifies the spec's file paths and code references against the actual codebase and returns findings (CRITICAL / IMPORTANT / MINOR) with a PASS or NEEDS REVISION verdict
4. Claude fixes CRITICAL and IMPORTANT findings, then re-sends for review
5. Loop continues until the reviewer returns PASS (max 3 iterations)

The loop runs autonomously — no approval prompts between iterations. Findings files are preserved in `/tmp/spec-review-findings-<timestamp>.md` for audit.

**Invocation:**

```
/spec-review-codex docs/superpowers/specs/2026-04-10-my-feature-design.md
/spec-review-local docs/superpowers/specs/2026-04-10-my-feature-design.md
```

Or without arguments to auto-detect the most recent spec:

```
/spec-review-codex
/spec-review-local
```
