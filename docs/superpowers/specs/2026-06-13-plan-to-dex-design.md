# Design: `/plan-to-dex` skill

**Date:** 2026-06-13
**Status:** Approved — ready for implementation plan
**Author:** brainstorming session (adelrioj + Claude)

---

## Goal

Add a `/plan-to-dex` skill that **translates an already-hardened Superpowers
implementation plan into a [dex](https://github.com/francescoalemanno/dex)-compatible
`plan.md`, imports it, and runs dex's autonomous loop end to end** — as a
sibling to `/plan-to-ralph`, giving the repo a uniform `/plan-to-<runtime>`
surface across both execution backends.

dex is a structured orchestrator for AI coding agents (Rust binary). It runs the
same core pattern as the Ralph loop — one task per fresh-context agent
invocation — but with reliability machinery the bash Ralph loop lacks: stalemate
detection, exponential-backoff retries, idle-timeout kills, and a parallel
multi-reviewer stage. This skill lets the repo's existing
`brainstorming → spec-review → writing-plans` pipeline feed dex **without dex
re-deriving the plan** via its own `dex plan` command.

## Architecture

dex exposes a first-class `dex import <file.md>` subcommand that **installs a
markdown file verbatim as `.dex/plan.md`** after one validation: the file must
contain at least one open `- [ ]` checkbox under some heading
(`validate_candidate_plan`). dex's plan parser treats **each markdown heading
(`#`–`######`) as one task group**, and `dex apply` executes **the first group
that still has an open checkbox**, handing the agent the *entire group body*
(checkboxes + surrounding prose) in one fresh-context iteration, then exiting and
re-reading. This is structurally identical to the Ralph rule of *one task = one
iteration*.

Because `dex import` is a verbatim copy, **the markdown the skill emits is
exactly what `dex apply` parses** — the skill owns the structure completely and
needs no JSON schema, no `progress.txt`/`findings.md` seeding (dex carries its
own state under `.dex/`), and no machine-verifiable-criteria rewriting (dex's
agent reads `Expected:` prose, unlike Ralph's bash loop). The result is a skill
roughly one-third the weight of `/plan-to-ralph`.

**Tech stack:** Markdown skill (`SKILL.md`) + one template; the `dex` CLI is the
runtime (no shell scripts of our own). Requires the `dex` binary on PATH plus at
least one supported coding CLI (`codex`, `claude`, or `pi`-for-LMStudio).

## Tech Stack

- `dex` CLI (`dex import`, `dex apply`, `dex review`, `dex finalize`)
- A coding CLI driver selected via dex's `--cli` flag: `codex`, `claude`, or
  `pi` (LMStudio-backed, local)
- Claude Code plugin skill format (`SKILL.md` frontmatter + body)

---

## Components

### Skill directory layout

```
skills/plan-to-dex/
  SKILL.md                 # the skill definition + translation instructions
  templates/dex-plan.md    # checkbox plan.md template with {{PLACEHOLDER}} syntax
```

No `scripts/` directory — dex is the execution runtime.

### Invocation

```
/plan-to-dex [plan-path] [--cli codex|claude|pi]
```

- `plan-path` (optional): explicit path to a Superpowers plan. If omitted, the
  skill scans for the most recent plan (same logic as plan-to-ralph Step 1).
- `--cli` (optional): dex backend driver. If omitted, the skill **asks** which
  backend to use (codex / LMStudio-via-pi / claude), since the choice is
  consequential; only if the user explicitly defers does it fall through to
  dex's own auto-detect. Once chosen, passed through to every `dex` invocation.

---

## Data flow / pipeline

1. **Locate + validate plan** — reuse plan-to-ralph Steps 1–2 logic
   (scan `docs/superpowers/plans/` then `docs/plans/`; validate `**Goal:**` +
   `### Task N:` headings + `**Files:**` block + per-step verification). This
   logic is **copied into this skill, not shared** — matching the repo
   convention that each skill stays self-contained (cf. spec-review prompt
   duplication noted in CLAUDE.md). On validation failure: list what's missing,
   ask whether to proceed; never invent requirements.

2. **Translate → `tasks/dex-plan.md`** — the core transform (see below).

3. **Preflight checks** —
   - `dex` present on PATH (else STOP with install hint).
   - Chosen `--cli` binary present (`which`); if `--cli pi`, warn that LMStudio
     must be running at `http://127.0.0.1:1234` with a model loaded.
   - **Branch guard:** if the current git branch is `main`/`master`, resolve a
     feature branch (use a provided name, else ask) and switch to it before any
     `dex apply`. `dex apply` auto-commits across iterations; those commits must
     land on a throwaway branch.

4. **One confirmation** — present the generated task list (N tasks, the `--cli`
   driver, the resolved branch, any `[manual]` criteria) and a single
   "this will autonomously implement and commit; proceed? [Y/n]". This is the
   standard confirm-before-hard-to-reverse-action check, **not** a plan review
   gate — the user already hardened the plan upstream. The user may decline.

5. **Run the chain** — stream output, passing `--cli` through every call:
   ```
   dex import --force tasks/dex-plan.md
   dex apply
   dex review
   ```
   Stop and report on `STALEMATE` or any non-zero exit.

6. **Handoff report** — branch name, tasks completed, where `dex review`
   findings landed (`.dex/review-*.md`), and the suggested next step
   (`dex finalize --onto main`).

---

## The translation format (load-bearing)

For each `### Task N: Component` in the source plan, emit one dex task group:

```markdown
### Task 3: Auth guard

**Files:** Create `src/auth/guard.ts`, Modify `src/router.ts`, Test `tests/auth/guard.test.ts`

- [ ] Write failing test in `tests/auth/guard.test.ts` — `pnpm test tests/auth/guard.test.ts` should FAIL
- [ ] Implement guard in `src/auth/guard.ts` so the test passes
- [ ] Verify `pnpm test tests/auth/guard.test.ts` PASSES
- [ ] Quality gates: `pnpm typecheck` and `pnpm lint` pass
- [ ] Commit
```

**Rules:**

- **One Task heading = one dex task group = one iteration.** dex hands the whole
  group body to the agent at once; the 5 TDD sub-steps become 5 checkboxes under
  the heading — **not** 5 separate groups/headings.
- `**Files:**` and `Run:`/`Expected:` details ride along as prose / checkbox
  text. dex passes the entire group body to the agent as its instructions.
- **Quality gates** are auto-detected exactly as plan-to-ralph Step 6
  (`package.json` scripts, `Makefile` targets, `pyproject.toml`, `Cargo.toml`)
  and appended as a checkbox on **every** task, so each iteration self-verifies.
  There is **no** top-level `qualityGates` array — dex has no equivalent; the
  agent simply runs the commands named in the checkbox.
- **`[manual]` criteria** (human-judgment verification steps, per plan-to-ralph's
  rule) are emitted as a checkbox prefixed `[manual] ` and surfaced in the
  Step 4 confirmation — so the user knows dex's agent will tick them off without
  true verification.
- An optional leading `## Overview` group carries the plan's `**Goal:**` as
  context. It has no open checkbox, so dex keeps it as context but never
  executes it.

### Mapping table

| Superpowers plan element        | → dex `plan.md`                                            |
| ------------------------------- | --------------------------------------------------------- |
| `### Task N: Component` heading  | `### Task N: Component` heading (one group = one iteration) |
| 5 TDD sub-steps                  | five `- [ ]` checkboxes under that heading                |
| `**Files:**` block               | preserved verbatim as prose (agent context)               |
| `Run:` / `Expected:` lines       | folded into the relevant checkbox text                    |
| Detected quality gates           | a `- [ ] Quality gates: ...` checkbox per task            |
| `[manual]` verification step     | `- [ ] [manual] ...` checkbox, surfaced in confirmation   |
| Plan `**Goal:**`                 | optional `## Overview` context group (no checkbox)        |

---

## Error handling

- **No plan found:** STOP — "No implementation plan found. Run
  /superpowers:writing-plans first."
- **Plan fails validation:** list missing elements, ask whether to proceed,
  never fabricate requirements.
- **`dex` not on PATH:** STOP with the install one-liner.
- **`--cli` binary missing:** STOP naming the missing binary; for `pi`, add the
  LMStudio-must-be-running hint.
- **On `main`/`master`:** do not run `dex apply`; resolve a feature branch first.
- **`dex apply` STALEMATE / non-zero exit:** stop the chain, report the dex
  output verbatim, do not proceed to `dex review`.

---

## What is deliberately NOT carried over from plan-to-ralph

- No `prd.json`, `tasks/progress.txt`, or `tasks/findings.md` — dex owns its
  state under `.dex/`.
- No top-level `qualityGates` array.
- No machine-verifiable-criteria rewriting — dex's agent reads `Expected:` prose
  directly.

## Known limitations

- **Checkbox trust:** dex advances when a checkbox is marked `- [x]`. If an
  iteration's agent ticks a box without truly satisfying it, dex proceeds
  anyway; `dex review` is the backstop. (Same trust model as Ralph's
  story-`passes` flag.)
- **`--cli pi` (LMStudio) for `apply` is the riskiest combo** — a local model
  doing autonomous multi-iteration writes. Documented as "supported, but prefer
  `codex`/`claude` for `apply`; `pi` is better suited to `dex review`."
- **No per-plan review gate** — by explicit design choice, the skill runs the
  full `import → apply → review` chain after a single confirmation. The branch
  guard is the only hard safety stop.

---

## Repo wiring

- New `skills/plan-to-dex/` (SKILL.md + templates/dex-plan.md).
- Register in `marketplace.json` if skills are enumerated there.
- Update `CLAUDE.md`: add `/plan-to-dex` to the Skills section and a "dex path"
  bullet to Key Conventions alongside the Ralph entries.
- Update `README.md` install/usage.

## Out of scope (YAGNI)

- A `dex plan` wrapper / generate-from-scratch mode (explicitly rejected during
  brainstorming — the skill translates an existing hardened plan only).
- A "translate, else generate" hybrid.
- Sharing plan-location/validation code with plan-to-ralph (repo favors
  self-contained skills).
- `dex research` / `dex bare` integration.
