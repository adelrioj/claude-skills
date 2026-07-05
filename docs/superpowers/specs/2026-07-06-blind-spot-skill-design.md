# `/blind-spot` — Adversarial Unknown-Unknowns Discovery

**Date:** 2026-07-06
**Status:** Approved design

## Problem

Two field notes on working with Claude Fable motivate this skill:

- Thariq's *"A Field Guide to Fable: Finding Your Unknowns"* — the quality of agentic
  work is bottlenecked by the human's ability to surface their **unknowns** (the gap
  between the map they give Claude and the territory the work lives in). His highest-
  leverage pre-implementation move is a **"blind spot pass"**: ask Claude to teach you
  your **unknown-unknowns** before you start, calibrated to what you already know.
- Diego Marino's *Fable adversarial audits* gist — the house rigor for a review:
  **adversarial framing + evidence-gated findings + stable IDs + impact ranking.**

This repo already covers the *artifact-facing, backward-looking* review direction well
— `/architect-review` (completeness & wiring), `/spec-review-*` (harden the spec),
`/ponytail-audit` (over-engineering). What it lacks is the *human-facing,
forward-looking* direction: a pass that runs **before** work and hunts what the human
is about to walk into but cannot see.

`/brainstorming` explores *what to build*. `/architect-review` checks *what you built
is wired*. Neither answers:

> "I'm about to work on X. What don't I know that I don't know — about this codebase,
> this domain, and the choices I'm about to make — that would change how I approach it?"

## What It Is

A diagnostic skill (`/blind-spot`) that dispatches a **fresh-context Claude subagent**
to hunt the **unknown-unknowns** of a *forthcoming* task the user describes, calibrated
to the user's stated experience level, then presents a ranked, evidence-backed briefing.
It **fixes nothing and changes no plan** — a finder, like `/architect-review`, not a
fixer. The user re-prompts their real work with what they learned.

It is the **forward-looking twin of `/architect-review`**: same report-only shape, same
fresh-subagent independence, same evidence gate — pointed at the terrain *ahead* of a
task instead of the wiring *behind* a finished one.

### Position in the family (pre → pre → post)

| Skill | Altitude | Question answered |
|-------|----------|-------------------|
| `/brainstorming` | pre | *What* should I build? (intent, scope, design) |
| **`/blind-spot`** | **pre** | **What can't I see about the terrain before I build?** |
| `/architect-review` | post | Is what I built actually wired and complete? |

### Why a fresh subagent (the mechanism)

The main loop absorbs the user's framing of the task and inherits their blind spots —
the same gap that makes an unknown *unknown* to the user also biases a self-review that
shares their context. A fresh `Agent` subagent, given only the task description + the
codebase + the stated experience level, re-derives "what's surprising here?" without
that inherited framing. Same independence rationale as `/architect-review`, and same
consequence: a Claude subagent, **no external CLI dependency**, installs anywhere.

### Why report-only

The intent is diagnostic — surface what the user can't see so *they* decide how to
re-scope. Report-only keeps the skill small (no fix/interview/convergence loop to
build) and composable: its output is a briefing the user folds into their next prompt,
`/brainstorming`, or `/writing-plans`.

## Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| Skill count | **One skill** (`/blind-spot`) + a `docs/unknowns-cheatsheet.md`; the Field Guide's other techniques stay as cheat-sheet prompts, not skills (they overlap existing skills) |
| Character | **Adversarial + evidence-gated** — every claimed unknown backed by a cited search or explicitly flagged as external domain knowledge; ranked by impact |
| Ending | **One-shot report**, then STOP — no interactive interview loop (that stays a cheat-sheet prompt) |
| Output | **Markdown to `/tmp`** by default + chat summary; **offer** an optional HTML briefing artifact |
| Reviewer | Fresh-context Claude `Agent` subagent (no `codex` dependency) |

## Input & Scope

Unlike `/architect-review` (which scopes to a *diff*), `/blind-spot` scopes to a
**forthcoming task the user describes**, plus an **optional experience signal**:

- `/blind-spot I'm adding a new OAuth provider but know nothing about the auth modules here`
- `/blind-spot I need to color-grade this video and don't know what color grading is`
  (pure-domain — the codebase may be irrelevant)
- `/blind-spot expert in React, new to this repo — building the settings page`

**No task described → one blocking question** (mirrors `/architect-review`'s no-diff
case): ask what the user is about to work on. Do not guess.

The task may be **codebase-facing, domain-facing, or both**. The subagent decides which
axes are relevant from the task text — a pure-domain task ("color grading") yields
mostly domain-gap findings with little codebase tracing; a "new to this repo" task
yields mostly codebase-landmine findings.

## Mechanism

### Preflight & scope (Step 0)

1. If the invocation has **no task description**, ask the one blocking question and stop
   until answered.
2. Being in a git repo is **not required** — a pure-domain blind-spot pass is valid with
   no repo. If in a repo, the subagent may trace it; if not, it runs domain-only.
3. Parse an **experience signal** from the task text if present (e.g. "know nothing
   about", "expert in", "new to"); default to "unstated — assume working proficiency,
   ask nothing, calibrate conservatively."
4. Announce scope in one line, then dispatch:
   > "Blind-spot pass on `<task>` (experience: `<signal|unstated>`). Dispatching the subagent."

### Dispatch ONE subagent (Step 1)

A single fresh `Agent` (`subagent_type: general-purpose`), prompt composed inline in
`SKILL.md` (no scripts/templates, like `/architect-review`). Read-only: it may Grep,
Read, WebSearch/WebFetch, and reason, but must **edit nothing**.

### Hunt taxonomy (the fixed checklist)

Things the user does not know they don't know about the task ahead:

1. **Domain gap** — a concept, term, technique, or prior art in the problem space the
   user (at their stated level) likely lacks. *External knowledge — flag as such.*
2. **Codebase landmine** — an existing pattern, constraint, invariant, or historical
   decision in the area the task touches that will bite an unaware change.
3. **Hidden coupling / blast radius** — what the task will affect that isn't obvious
   from its description (callers, shared state, migrations, cross-cutting config).
4. **"What good looks like"** — the house quality bar / convention / idiom the user
   would violate without knowing it exists.
5. **Unseen decision fork** — a choice the task forces that the user doesn't yet know
   *is* a choice, especially architecture-altering ones.
6. **Unknown known** — an assumption so obvious to the user they'd never state it, that
   Claude would otherwise guess wrong on. Surfaced as: "you probably assume X — confirm,
   because the code/domain suggests Y is also plausible."

### Evidence gate (honestly adapted)

Architect-review's rule, adjusted for a pass that spans code *and* domain:

- **Codebase-grounded finding** → MUST cite the grep/read that surfaced it. An uncited
  codebase claim is downgraded to a question, not reported as a finding.
- **Domain finding** → cannot cite the repo, so it is **explicitly labeled `[external
  knowledge]`** (optionally with a source if web search was used). It must never be
  dressed up as a codebase-derived fact. This keeps the report honest about what is
  observed in *this* repo vs. brought in from general/world knowledge.

### Ranking

By a **would-change-your-approach** impact score — **High / Medium / Low** — highest
first. The Field Guide's entire point is prioritizing unknowns whose answers change the
architecture; the ranking makes that the primary sort, above finding type.

### Output (Step 2)

Subagent returns one markdown document with:

1. **Summary table** — counts per impact level, per taxonomy type, and whether the pass
   was codebase / domain / both.
2. **Findings**, highest-impact first. Each: **Type** · **Impact** · stable **ID**
   (`U1, U2…`) · **What you don't know** (one sentence) · **Evidence** (cited search for
   codebase findings, `[external knowledge]` label for domain) · **What to do about it**
   (a question to answer, a reference to read, or a prompt clarification to add before
   starting).
3. **Sharpened brief** — 2–4 sentences the user can paste to start the real work with the
   top unknowns pre-resolved or explicitly deferred.

The main loop then:

1. Writes the document to `/tmp/blind-spot-$(date +%s).md` (uncommitted audit trail).
2. Presents the ranked findings + summary + sharpened brief in chat.
3. **Offers** an HTML briefing artifact: *"Want an HTML version to skim or share?"* —
   renders via the Artifact tool only on a yes.
4. **STOP.** Fixes nothing, starts no work. Acting on the briefing is a separate,
   explicit request.

## The cheat sheet: `docs/unknowns-cheatsheet.md`

A reusable, copy-paste prompt library distilling the Field Guide's techniques,
phase-organized (pre / during / post implementation), each cross-referencing the repo
skill that already does it — so it doubles as a "which skill for which unknown" map:

| Technique | Phase | Maps to |
|-----------|-------|---------|
| Blind-spot pass | pre | **`/blind-spot`** |
| Brainstorm & prototype | pre | `/brainstorming` |
| Interview me | pre | cheat-sheet prompt (main loop) |
| References (point at source) | pre | cheat-sheet prompt |
| Implementation plan | pre | `/writing-plans` |
| Implementation notes | during | cheat-sheet prompt |
| Pitches & explainers | post | cheat-sheet prompt |
| Quizzes | post | cheat-sheet prompt |
| Completeness / wiring check | post | `/architect-review` |

Also carries the four-quadrant unknowns model (known/unknown × known/unknown) as the
framing header, and credits both sources (Thariq's field guide, Diego's audit gist).

## Wiring

- New `skills/blind-spot/SKILL.md` — self-contained, inline subagent prompt, no
  scripts/templates (mirrors `/architect-review`'s structure and size, ~150–200 lines).
- New `docs/unknowns-cheatsheet.md`.
- `CLAUDE.md` — add a `### /blind-spot` section under "Skills" and the matching Key
  Conventions bullets (evidence-gate-is-the-lever, report-only, forward-twin framing).
- `README.md` / `.claude-plugin/marketplace.json` — add the skill to any human-facing
  skill list found there (verified during implementation).

## Deliberate Simplifications (ponytail)

- **One subagent, not a panel.** One well-prompted pass covers the taxonomy. Upgrade
  path: fan out one subagent per axis (domain vs. codebase) and merge — only if
  single-agent recall proves insufficient.
- **Report-only, no interview loop.** The "interview me" follow-up stays a cheat-sheet
  prompt; folding it in would rebuild `/brainstorming`'s dialogue machinery.
- **No CLI dependency.** Claude subagent over `codex`, so it installs anywhere.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.
- **Git repo optional.** A pure-domain pass needs no repo; not gating on one keeps the
  color-grading case in scope.

## What This Skill Is NOT

- **Not `/brainstorming`.** Brainstorming decides *what to build* through dialogue;
  blind-spot surfaces *what you can't see* about a task you've already chosen, in one
  shot. They compose: blind-spot → then brainstorm the resolved scope.
- **Not a fixer or a planner.** It never edits code or writes a plan. (Feed its output
  to `/writing-plans` or your next prompt.)
- **Not `/architect-review`.** That reviews a finished diff for wiring; this reviews a
  *forthcoming task* for the human's blind spots. Opposite ends of the same axis.
