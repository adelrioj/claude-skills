# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin bundling skills for autonomous story execution, adversarial spec review, multi-model answer synthesis, OrbStack port-collision migration, and workflow support.

## Skills

**`/plan-to-dex`** — Run a hardened Superpowers plan through the [dex](https://github.com/francescoalemanno/dex) orchestrator. Translates the plan into dex's checkbox-group `plan.md` (one task = one iteration), imports it, and runs `dex apply` → `dex review` autonomously with codex as the fixed backend. Requires the `dex` and `codex` CLIs.

**`/swarm-execute`** — Implement a feature as parallel user stories: Claude orchestrates via the Workflow (ultracode) tool, Codex workers write all code in isolated worktrees, architect + QA reviews gate every merge. Takes a plain-language request or a plan/spec file directly — no `prd.json` or `tasks/` files. Requires the `codex` CLI.

**`/spec-review-codex`** — Adversarial review of design specs using OpenAI Codex as an independent reviewer. Sends the spec to Codex for rigorous review against a 10-category checklist, fixes CRITICAL and IMPORTANT findings, and loops until the spec passes with zero blocking issues (max 3 iterations). Designed to catch bugs, contradictions, ambiguities, and gaps that self-review misses due to author bias.

**`/spec-review-local`** — Same adversarial review loop, but the reviewer is a local model served by [LMStudio](https://lmstudio.ai) via the `pi` CLI. Auto-detects whatever LLM is currently loaded in LMStudio — no hardcoded model. Works fully offline; the reviewer is restricted to read-only tools.

**`/handoff`** — Compact the current conversation into a handoff document so a fresh agent can pick up the work. Writes to the OS temp directory, includes a "suggested skills" section, references existing artifacts by path instead of duplicating them, and redacts secrets/PII.

**`/sprint-status-update`** — Generate a company-wide sprint recap for Slack from the Notion sprint board: categorizes deliveries, summarizes bug reports, and formats a scannable update. Use on Fridays or at sprint boundaries.

**`/orbstack-compatible`** — Make a Docker Compose project stop colliding on host ports across worktrees/projects by moving containerized services onto OrbStack routable domains (`<service>.<project>.orb.local`). Strips `ports:` from the base compose, adds an opt-in `docker-compose.ports.yml` for Windows/CI, rewrites local env URLs to domains, then verifies live. Requires OrbStack as the active Docker engine.

**`/fusion`** — Run a prompt through a blind multi-model panel — 2× Opus subagents, GPT-5.5 via `codex`, and a local LMStudio model via `pi` — then have a separate Opus judge synthesize the responses into a single verdict. Subscription-only: all panelists use authenticated CLIs or Agent subagents; no API keys required. Pass `opus`, `codex`, or `local` as an optional argument to restrict the panel to a single seat. The local panelist auto-detects whatever model is currently loaded in LMStudio (override base URL with `FUSION_LMSTUDIO_URL`). Any panelist seat that is unavailable (missing CLI, unloaded model, timeout) is dropped gracefully and the panel continues. Provenance for every run is saved to `~/.claude/fusion-runs/` (never committed). Ported from fusion-fable (MIT); the Gemini/`agy` seat is intentionally dropped in favor of the local `pi`/LMStudio seat. Requires: `codex` CLI authenticated, `pi` CLI in PATH, LMStudio running with a model loaded (for the local seat).

**`/ship-it`** — Run the whole feature pipeline from a thumbs-upped design spec to a reviewed PR in one invocation: hardens the spec with `/spec-review-codex`, writes the implementation plan, executes it via `/plan-to-dex`, opens a PR with `/commit-commands:commit-push-pr`, then runs `/review-pr` and fixes CRITICAL/IMPORTANT findings (up to 3 passes). A pure conductor — it invokes the existing units live and duplicates none of their logic. The heavy steps (spec-review, plan-writing, dex execution) run as execute-and-report subagents that return only a compact result, keeping their raw codex/dex output out of the conductor's context. Sequential, fully autonomous, best-effort: it never halts on quality, recording any leftover findings in a final report instead. Requires the `codex` and `dex` CLIs plus the `pr-review-toolkit` and `commit-commands` plugins.

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

## Spec Review

Two interchangeable skills run an adversarial review loop over brainstorming design specs (any file matching `docs/superpowers/specs/*-design.md`):

| Skill | Reviewer | Requirements |
|-------|----------|--------------|
| `/spec-review-codex` | OpenAI Codex (`codex exec`) | [Codex CLI](https://github.com/openai/codex) installed and authenticated |
| `/spec-review-local` | Local model via `pi` + LMStudio | `pi` in PATH, LMStudio running at `http://127.0.0.1:1234` with an LLM loaded |

**What happens:**

1. The skill locates the spec (argument, or the most recent `*-design.md` in `docs/superpowers/specs/`)
2. The spec is sent to the reviewer with a 10-category review checklist
3. The reviewer verifies the spec's file paths and code references against the actual codebase and returns findings (CRITICAL / IMPORTANT / ADVISORY / MINOR) with a PASS or NEEDS REVISION verdict
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
