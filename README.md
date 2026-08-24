# Claude Skills

A [Claude Code](https://claude.com/claude-code) plugin bundling **orchestration skills** — multi-agent pipelines, adversarial review loops, a Linear ticket lifecycle, and workflow support — that drive Codex, [dex](https://github.com/francescoalemanno/dex), [Symphony](https://github.com/openai/symphony), and local models to do the heavy lifting.

## Skills

Fourteen skills, grouped by where they fit in a feature's life. Each is a slash command.

### Ticket — get the work written down and sized

| Skill | What it does | Needs |
|---|---|---|
| `/to-linear` | Turns the current conversation into a properly-templated Linear issue — `bug` or `story` — or an `epic` as a Linear **project**. Owns the templates the grooming skill lints against. Creates only; never updates or moves. | Linear MCP |
| `/linear-groom-ticket` | Makes one ticket ready to work on, or judges it not worth working on. Three parallel Codex analysts (do its claims hold in the code / does it duplicate another ticket / is it implementable) plus a template-completeness lint, then a proposed rewrite you approve before anything is written. | Linear MCP, `codex`, `python3` |
| `/linear-triage-ticket` | Priority, complexity and effort for one groomed ticket, each backed by evidence read out of the repo. Two parallel Codex analysts behind a signal-safe watchdog; writes the priority, the estimate where provable, and one living rationale comment — after you approve. | Linear MCP, `codex`, `python3`; `orca` optional (estimate only) |
| `/linear-spec-ticket` | Drafts a design spec from the ticket plus the codebase and uploads it to the ticket as a **file attachment**. A `refresh` mode re-uploads it after `/spec-review-codex` hardens it. Never moves the ticket. | Linear MCP, `curl` |
| `/spec-to-symphony` | Hands an already-specced ticket's build to a [Symphony](https://github.com/openai/symphony) pipeline: puts the spec on the remote under the filename that deployment actually reads, proves it landed, then arms the existing ticket. Reads every value from the governing workflow config and refuses to guess one. | Linear MCP, `git`, a Symphony deployment |

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

The Linear skills need the Linear MCP connected. `.mcp.json` registers it for local development; installed from the marketplace, connect it with `/mcp`. Test suites:

```bash
bash tests/check-codex-knob.sh                         # the codex model/effort pins
bash tests/check-linear-mcp-tools.sh                   # the Linear MCP tool names the skills call
bash skills/linear-groom-ticket/scripts/tests/run.sh   # offline: no network, no tokens, codex doubled
```

## How it fits together

The skills are composable, and there are two entry points depending on whether the work is tracked.

**From a ticket:** `/to-linear` files it → `/linear-groom-ticket` makes it coherent → `/linear-triage-ticket` sizes it → `/linear-spec-ticket` attaches a spec → `/spec-review-codex` hardens the spec on disk → `/linear-spec-ticket <IDENT> refresh` re-uploads it → `/spec-to-symphony` hands the build to an autonomous pipeline. Each stage owns exactly one transition and none of them moves the ticket except the last, which moves it only after proving the spec is on the remote.

**From a conversation:** `/blind-spot` before you start → `/spec-review-codex` (or `-local`) to harden the design → `/plan-to-dex` to build → `/architect-review-pr` to check wiring → `/handoff` if you run out of context. `/ship-it` chains most of that into a single autonomous pass. `/review-codebase` is a standalone second opinion you can reach for anytime.

**Nothing about your Linear workspace or Symphony deployment is hardcoded.** The Linear MCP has no workspace parameter — the connector's token binds the session — so the workspace is read back and shown to you, never selected. Team resolves from `$LINEAR_TEAM` or the repo's own conventions, statuses resolve by **type** rather than by name (teams disagree on `Backlog` vs `Todo` vs `To Do`), and every Symphony value — intake state, spec path, branch, whether a stage can read attachments — is read out of the governing workflow config at runtime. `/spec-to-symphony` stops rather than infer one. Optional pins for a checkout that should only ever talk to one place: `$LINEAR_WORKSPACE`, `$LINEAR_TEAM`, `$SYMPHONY_WORKFLOW`.

Per-skill detail and conventions live in [`docs/skills/`](docs/skills/).

The skills that drive `codex` (directly or through `dex`) pin **both the model and the reasoning effort** per task — `gpt-5.6-luna` at `high` for implementation, `gpt-5.6-sol` at `high` for adversarial review — regardless of what your `~/.codex/config.toml` says. That needs no setup on your part, and every pin is checked against your own entitlements in `~/.codex/models_cache.json` before a run is spent. See [`docs/codex-tuning.md`](docs/codex-tuning.md) for why, and for the environment variables that override it.

## License

MIT
