# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin bundling skills for autonomous story execution, adversarial spec/feature review, whole-repo audits, the Linear ticket lifecycle, and workflow support. Each skill's full description and its conventions live in `docs/skills/<name>.md` — **read the relevant one when working on that skill**; only session-invariant rules are kept here to stay out of every session's always-on context.

## Plugin Structure

This is a Claude Code plugin (`.claude-plugin/plugin.json`). Skills live under `skills/`, each with:
- `SKILL.md` — The skill definition (frontmatter + instructions Claude follows)
- `templates/` — Template files with `{{PLACEHOLDER}}` syntax, where a skill needs them (e.g. `review-codebase/templates/`)
- `scripts/` — Helper scripts, where a skill needs them. One skill ships any: `linear-groom-ticket` (a deterministic bash/Python pipeline with its own offline suite under `scripts/tests/`). Its scripts self-locate from `${BASH_SOURCE[0]}`, so they do not read `${CLAUDE_PLUGIN_ROOT}` — but a **subagent** given a `${CLAUDE_PLUGIN_ROOT}` path cannot expand it, so any path handed to one must be expanded first
- **The Linear ticket templates are shared, not per-skill.** `skills/to-linear/templates/{bug,story,epic}.md` is the single source of truth: `/to-linear` fills them to file a ticket and `/linear-groom-ticket` lints against the same file (`10-lint.py` picks `bug.md` for a `Bug`-labelled ticket, `story.md` otherwise). **Never fork a copy into another skill** — a ticket filed against one shape and linted against another reports every section missing and gets restructured on its first grooming. Sections are required unless their body carries an `optional` HTML-comment marker, and ticket prose is **English** (`prompts/editor.md` translates whatever arrives). Editing a template changes both skills, so run `bash skills/linear-groom-ticket/scripts/tests/run.sh`

If hooks are ever added, they live at the plugin root under `hooks/hooks.json` — they are registered globally, not per-skill. (The plugin currently ships no hooks; the former spec-review PostToolUse hook was removed.)

## Skills

Full detail + per-skill conventions are in `docs/skills/`. Read the one you're touching:

| Skill | Doc | One-liner |
|---|---|---|
| `/plan-to-dex` | `docs/skills/plan-to-dex.md` | Superpowers plan → dex `plan.md`, runs dex apply/review (codex backend) |
| `/spec-review-codex`, `/spec-review-local` | `docs/skills/spec-review.md` | Adversarial spec review + fix loop (Codex / local LMStudio reviewer) |
| `/to-linear` | `docs/skills/to-linear.md` | Conversation → templated Linear ticket (bug / story / epic-project); **owns the templates `/linear-groom-ticket` lints against** |
| `/linear-groom-ticket` | `docs/skills/linear-groom-ticket.md` | Grooms one Linear ticket (3 parallel codex analysts + Sonnet editor) against `/to-linear`'s templates; scripts own offline analysis, Linear I/O uses the MCP, human approves before any write |
| `/linear-triage-ticket` | `docs/skills/linear-triage-ticket.md` | Triage one groomed ticket — priority, complexity, effort with reasoning attached (2 parallel codex analysts); MCP + `codex` + `python3`, optional `orca` only for the estimate, human approves before any write |
| `/linear-spec-ticket` | `docs/skills/linear-spec-ticket.md` | Drafts the spec onto a groomed ticket and attaches it as a file; a `refresh` mode re-uploads it after `/spec-review-codex`. **Never moves the ticket.** MCP-only: `prepare_attachment_upload` → signed `PUT` (`curl`, the one non-tool step) → `create_attachment_from_upload`; no API key |
| `/spec-to-symphony` | `docs/skills/spec-to-symphony.md` | Hands an already-specced ticket's build to a Symphony pipeline (pushed branch + proof + arm). Continues an existing ticket; never creates one |
| `/handoff` | `docs/skills/handoff.md` | Compact the conversation into a handoff doc for a fresh agent |
| `/ship-it` | `docs/skills/ship-it.md` | Pure conductor chaining the units into one spec→PR pipeline |
| `/architect-review-pr` | `docs/skills/architect-review-pr.md` | Completeness & wiring review of a finished feature (finds, then fixes CRITICALs; `report-only` to skip) |
| `/blind-spot` | `docs/skills/blind-spot.md` | Unknown-unknowns pass *before* starting a task (report-only) |
| `/review-codebase` | `docs/skills/review-codebase.md` | Three parallel whole-repo audits (codebase / docs / process) |
| `/claude-md-slim` | `docs/skills/claude-md-slim.md` | Minimize this file — page per-skill detail out to `docs/` (inverse of claude-md-improver) |

## Development

### Local testing

```bash
claude --plugin-dir ./claude-skills
```

Skill test suites (run by `.github/workflows/tests.yml` on every PR — run them before pushing):

```bash
bash tests/check-codex-knob.sh                         # the codex model/effort pins
bash tests/check-linear-mcp-tools.sh                   # the Linear MCP tool names the skills call
bash skills/linear-groom-ticket/scripts/tests/run.sh   # offline, no network, no tokens
```

The groom suite needs `python3 jsonschema` for its offline validators and `shellcheck` (absent, the suite passes but reports that static analysis did **not** happen — CI treats that as a green worth refusing, so install it rather than reading the skip as clean). On macOS `pip install` into the system python is blocked by PEP 668, so use a venv: `python3 -m venv /tmp/venv && /tmp/venv/bin/pip install jsonschema && PATH=/tmp/venv/bin:$PATH bash skills/linear-groom-ticket/scripts/tests/run.sh`, plus `brew install shellcheck`. Running the suite drops `__pycache__/` dirs beside the scripts; they are gitignored and safe to delete

### Distribution

Distributed via marketplace (`.claude-plugin/marketplace.json`). Install/update/uninstall commands are in README.md.

## Key Conventions

Repo-wide rules that apply to any task. Per-skill conventions live in each skill's `docs/skills/<name>.md`.

- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin install path at runtime — always use this in script references shown to users
- Codex model **and** effort are set by the skill, never by the user's setup — **`gpt-5.6-luna` @ `high` builds, `gpt-5.6-sol` @ `high` reviews**. Direct sites pin both: `-m "${CODEX_MODEL_REVIEW:-gpt-5.6-sol}" -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-high}"` (build: the `_BUILD` pair). dex phases have neither flag, so they name an entry carrying both: `--cli "${DEX_CLI_BUILD:-codex-${CODEX_MODEL_BUILD:-gpt-5.6-luna}-${CODEX_EFFORT_BUILD:-high}}"` / `"${DEX_CLI_REVIEW:-codex-${CODEX_MODEL_REVIEW:-gpt-5.6-sol}-${CODEX_EFFORT_REVIEW:-high}}"` — explicit entry > model+effort > default, and `plan-to-dex` Step 4 provisions the derived `codex-<model>-<effort>`. Keep the `codex-` prefix (the live-worker `pgrep` guard depends on it). **Pinning a slug is a deliberate tradeoff** (ids age, entitlements vary), so every pin is gated on `~/.codex/models_cache.json` — validate the model *and* its effort, skip the gate when that cache is absent. Add both knobs to any new call site and run `tests/check-codex-knob.sh` — `docs/codex-tuning.md`
- **The Linear MCP is the `linear` server (`mcp__linear__*`), registered in `.mcp.json`, and its create/update tools are one tool each.** `save_issue` creates when `id` is omitted and updates when it is passed — same for `save_project`, `save_comment`. There is no `create_issue`/`update_issue`/`create_comment`/`create_project`; a skill naming one instructs a write that silently never happens. Three parameter semantics differ and all three bite: `labels` **replaces** the full set (omitted labels are removed), the relation params (`duplicateOf`, `blocks`, `blockedBy`, `relatedTo`) are **append-only**, and `patch` edits the description in place so appending a line never round-trips a groomed body. Referencing a new Linear tool means adding it to `tests/check-linear-mcp-tools.sh`'s known-good list — that edit is where someone consciously accepts the name
- **No Linear or Symphony coordinate is hardcoded in this plugin, and that is a rule, not an accident.** Workspace is *read back* (the MCP has no workspace parameter — the token binds the session; `$LINEAR_WORKSPACE` is an optional STOP-guard, never a selector), team resolves invocation → `$LINEAR_TEAM` → repo grep → ask, statuses resolve by **`type`** never by name, the estimate scale is resolved into `estimate-settings.json`, and every Symphony value (intake state, spec path, branch, attachment support, clobber guard) is read out of the governing workflow config at runtime — `/spec-to-symphony` STOPs rather than infer one. Adding a hardcoded state name, workspace slug, or spec path is the regression to watch for
- Shell scripts use `set -euo pipefail` and require `jq` for JSON parsing
- Hooks live in `hooks/hooks.json` at the plugin root — the plugin system does not discover hooks nested inside skill directories
- **Patch bumps are automatic — do not hand-bump for an ordinary change.** `.github/workflows/bump-version.yml` patch-bumps BOTH `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` on any push to `main` touching `skills/**`, `hooks/**`, or `.claude-plugin/**`, unless that push already changed the version (its `[skip ci]` commit is the loop guard). Bump by hand only for an intentional **minor/major** — and then bump both files together, which also suppresses the bot for that push. A PR with no version change is correct, not an oversight
