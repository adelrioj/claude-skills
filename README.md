# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin bundling **orchestration skills** — multi-agent pipelines, adversarial review loops, and workflow support — that drive Codex, [dex](https://github.com/francescoalemanno/dex), and local models to do the heavy lifting.

## Skills

Nine skills, grouped by where they fit in a feature's life. Each is a slash command.

### Plan — sharpen intent before code

| Skill | What it does | Needs |
|---|---|---|
| `/blind-spot` | Pre-work pass that surfaces the *unknown-unknowns* of a task — what you don't know you don't know about this codebase, domain, and the decisions ahead. Report-only, fixes nothing. | — |
| `/spec-review-codex` | Adversarial review of a design spec with OpenAI Codex as an independent reviewer against a 10-category checklist; fixes CRITICAL/IMPORTANT findings and loops until it passes (max 3). | `codex` |
| `/spec-review-local` | Same review loop, but the reviewer is a local model served by [LMStudio](https://lmstudio.ai) via `pi`. Auto-detects the loaded model; runs fully offline, read-only. | `pi` + LMStudio |

### Build — turn a plan into shipped code

| Skill | What it does | Needs |
|---|---|---|
| `/plan-to-dex` | Runs a hardened [Superpowers](https://github.com/obra/superpowers) plan through the dex orchestrator: translates it into dex's checkbox `plan.md` (one task = one iteration), then runs `dex apply` → `dex review` autonomously with Codex as the backend. | `dex` + `codex` |
| `/ship-it` | Pure conductor: spec → reviewed PR in one invocation. Chains `/spec-review-codex`, plan-writing, `/plan-to-dex`, PR creation, `/review-pr` + fix passes, and a closing `/architect-review-pr` completeness report. Autonomous, best-effort; records leftover findings instead of halting. | `codex`, `dex`, `pr-review-toolkit`, `commit-commands` |

### Review — check the finished work

| Skill | What it does | Needs |
|---|---|---|
| `/architect-review-pr` | Completeness & wiring review of a built feature — hunts code created but never wired, referenced-but-missing symbols, half-finished paths. Scopes to the branch diff, traces the whole repo, cites the empty search that proves each gap. Report-only. | — |
| `/review-codebase` | Whole-system adversarial audit across three lenses at once (codebase / docs / process) via three parallel subagents, each writing a ranked report to `docs/audits/`; optional fix pass on CRITICAL findings. | — |

### Maintain — keep the workspace lean

| Skill | What it does | Needs |
|---|---|---|
| `/handoff` | Compacts the current conversation into a handoff doc so a fresh agent can pick up — includes a "suggested skills" section, references artifacts by path, redacts secrets/PII. | — |
| `/claude-md-slim` | The inverse of claude-md-improver: pages bloated `CLAUDE.md` detail out to `docs/` behind one-line pointers, keeping only session-invariant rules always-on. Moves, never deletes. | — |

## Install

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
claude plugin marketplace remove claude-skills-marketplace   # optional: also drop the marketplace
```

## Local development

```bash
git clone https://github.com/adelrioj/claude-skills.git
claude --plugin-dir ./claude-skills
```

## How it fits together

The skills are composable. A typical flow: `/blind-spot` before you start → `/spec-review-codex` (or `-local`) to harden the design → `/plan-to-dex` to build → `/architect-review-pr` to check wiring → `/handoff` if you run out of context. `/ship-it` chains most of that into a single autonomous pass. `/review-codebase` is a standalone second opinion you can reach for anytime.

Per-skill detail and conventions live in [`docs/skills/`](docs/skills/).

The skills that drive `codex` (directly or through `dex`) run their **review** passes at `xhigh` reasoning effort regardless of what your `~/.codex/config.toml` says, and leave code-writing at your own setting. That needs no setup on your part. See [`docs/codex-tuning.md`](docs/codex-tuning.md) for why, and for the environment variables that override it.

## License

MIT
