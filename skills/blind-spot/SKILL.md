---
name: blind-spot
description: "Use BEFORE starting work on a task to surface the unknown-unknowns you're about to walk into but can't see. Dispatches a fresh-context Claude subagent that hunts what you don't know you don't know about the codebase, the domain, and the decisions ahead, calibrated to your stated experience, then reports ranked, evidence-backed findings and fixes nothing. Triggers on: blind spot pass, blindspot, unknown unknowns, what don't I know, what am I missing, help me prompt better, I know nothing about, teach me my unknowns, before I start, de-risk this task, surface my blind spots."
user-invocable: true
---

# Blind-Spot Pass — Adversarial Unknown-Unknowns Discovery

A **pre-implementation pass that surfaces the unknown-unknowns of a task you're about
to start** — what you don't know you don't know about this codebase, this domain, and
the decisions ahead — so you can prompt from the territory instead of a partial map.

this is a **finder, not a fixer** — it reports ranked, evidence-backed findings 
and **edits nothing, plans nothing, starts no work**. 
You fold the briefing into your next prompt, `/brainstorming`, or `/writing-plans`.

**Why a fresh subagent (the adversarial mechanism).** The main loop absorbs your framing
of the task and inherits your blind spots — the same gap that makes an unknown *unknown*
to you also biases a self-review that shares your context. A fresh `Agent` subagent,
given only the task + the codebase + your stated experience, re-derives "what's
surprising here?" without that inherited framing. Payoff: a Claude subagent, **no external CLI dependency**,
installs anywhere.

**Why report-only.** The intent is diagnostic — surface what you can't see so *you*
decide how to re-scope. Report-only keeps the skill small (no fix / interview /
convergence loop) and composable.

---

## Flow

### Step 0 — Preflight & scope

1. **No task described?** If the invocation names no forthcoming task, ask the one
   blocking question and stop until answered — do not guess:
   > "What are you about to work on? Tell me the task, and (optionally) how familiar you
   > already are with this area — that's what I calibrate the pass to."
2. **A git repo is NOT required.** A pure-domain blind-spot pass (e.g. "I don't know what
   color grading is") is valid with no repo. If in a repo, the subagent may trace it; if
   not, it runs domain-only.
3. **Parse an experience signal** from the task text if present ("know nothing about",
   "expert in", "new to this repo", "first time touching…"). If absent, default to
   *"unstated — assume working proficiency, calibrate conservatively, ask nothing."*
4. Announce scope in one line, then dispatch:
   > "Blind-spot pass on `<task>` (experience: `<signal | unstated>`). Dispatching the subagent."

### Step 1 — Dispatch ONE blind-spot subagent

**Mint the report path first, once:** `REPORT_PATH="${TMPDIR:-/tmp}/blind-spot-$(date +%s).md"`.
Hold it in a variable — the same value is substituted into the prompt below and read back in
Step 2. Never re-derive it, and never resolve the report by globbing `blind-spot-*.md`: a
stale report from an earlier pass on a *different* task satisfies that glob and would be
presented as this pass's findings.

Dispatch a single fresh subagent via the **Agent tool** (`subagent_type: general-purpose`).
Compose the prompt from the template below, filling `<TASK>`, `<EXPERIENCE>`, and
`<REPORT_PATH>`. The subagent **writes the report file itself** and is otherwise
**read-only**: it may Grep, Read, WebSearch, and WebFetch to investigate, and `Write` only
`<REPORT_PATH>` — it must **edit, create, or delete nothing else**. One subagent, not a panel
(see Deliberate simplifications).

### Step 2 — Report

1. Read the report the subagent wrote at `REPORT_PATH`. The subagent authors the file; do not
   write it from the subagent's return message — a subagent that finishes its work but idles
   without returning leaves no message to write, and the report would silently not exist.
   If `REPORT_PATH` is missing, say so plainly ("the subagent produced no report") and stop —
   do not re-dispatch and do not fall back to a glob.
2. Present in chat: the summary counts, the findings **highest-impact first**, and the
   **sharpened brief**.
3. **Offer** an HTML briefing: *"Want an HTML version to skim or share?"* — render it via
   the **Artifact** tool only if the user says yes. (Load the `artifact-design` skill
   first if you build one.)
4. **STOP. Fix nothing, start nothing.** Acting on the briefing is a separate, explicit
   request — this skill's contract ends at the report.

---

## The subagent prompt

Compose this at dispatch, substituting `<TASK>` and `<EXPERIENCE>`:

```
You are a fresh-context senior engineer and domain researcher running a BLIND-SPOT PASS
for someone about to START a task. Your job is NOT to do the task — it is to surface the
UNKNOWN-UNKNOWNS: what they don't know they don't know about the codebase, the domain,
and the decisions ahead, so they can prompt and plan from the real territory. You have no
memory of how they framed this; re-derive what's surprising from the code and the domain
itself. You are READ-ONLY: investigate, reason, and report. Do not edit, create, or
delete any file.

## The task they're about to start

<TASK>

## Their experience level (calibrate to this — do not lecture on what they already know)

<EXPERIENCE>
  # substitute the parsed signal, or:
  # "Unstated. Assume working proficiency. Calibrate conservatively — surface genuinely
  #  non-obvious unknowns, not beginner facts. Do not ask them questions."

## How to investigate

Decide which axes the task actually spans and weight your effort accordingly:
- CODEBASE-facing task → Grep and Read the areas it will touch: existing patterns,
  invariants, callers, shared state, migrations, config, tests, conventions, and any
  historical decisions encoded in the code. If not in a git repo / no relevant code
  exists, say so and skip this axis.
- DOMAIN-facing task → use WebSearch/WebFetch and your own knowledge for concepts, prior
  art, terminology, standard approaches, and common failure modes in the problem space.
- Most real tasks span BOTH. A "new to this repo" task leans codebase; an "I don't know
  what X is" task leans domain.

## Hunt taxonomy (run this fixed checklist)

Things they do not know they don't know about the task ahead:

1. Domain gap        — a concept, term, technique, or prior art in the problem space they
                       (at their level) likely lack. EXTERNAL knowledge — flag as such.
2. Codebase landmine — an existing pattern, constraint, invariant, or historical decision
                       in the area the task touches that will bite an unaware change.
3. Hidden coupling   — what the task will affect that isn't obvious from its description:
                       callers, shared state, migrations, cross-cutting config, blast radius.
4. What good looks like — the house quality bar / convention / idiom they'd violate
                       without knowing it exists.
5. Unseen decision fork — a choice the task forces that they don't yet know IS a choice,
                       especially architecture-altering ones.
6. Unknown known     — an assumption so obvious to them they'd never state it, that an
                       agent would otherwise guess wrong on. Frame as: "you probably
                       assume X — confirm, because the code/domain suggests Y is also live."

## Evidence gate (MANDATORY — this is what keeps the report trustworthy)

The signature failure of this pass is the CONFIDENT HALLUCINATION: a plausible "unknown"
that isn't real, or a world-knowledge guess dressed up as a fact about THIS repo.

- CODEBASE-grounded finding → you MUST cite the grep/read that surfaced it (the command
  and what it showed). An uncited codebase claim is DOWNGRADED to an open question, not
  reported as a finding.
- DOMAIN finding → you cannot cite this repo, so label it `[external knowledge]` (add a
  source if you web-searched). NEVER present a domain/world-knowledge claim as if it were
  observed in the codebase.

## Ranking (the primary sort)

Rank findings by WOULD-CHANGE-YOUR-APPROACH impact: High / Medium / Low, highest first.
The whole point is prioritizing unknowns whose answers change the architecture — impact
sorts ABOVE finding type.

## Output — WRITE the report to a file, then return it

Your report is delivered by **writing it to `<REPORT_PATH>`**, not by returning it. Use the
`Write` tool on exactly that absolute path — it is the only file you may create.

Write it **incrementally, as you go**: create the file with the summary table as soon as you
have your first finding, then append each finding as you confirm it. Do not hold the whole
report in your head until the end — if this invocation ends without the file, the report is
lost, and returning it as a message is not a substitute.

When the file is complete, also return the same markdown as your final message (corroboration
— the file is what is read).

The document itself:

1. Summary table: counts per impact level, per taxonomy type, and whether the pass was
   codebase / domain / both.
2. Findings, highest-impact first. Each finding:
   - **ID** (U1, U2, …) · **Type** (taxonomy) · **Impact** (High/Med/Low)
   - **What you don't know**: one sentence.
   - **Evidence**: the cited grep/read for codebase findings; `[external knowledge]`
     (+ source) for domain findings.
   - **What to do about it**: one line — a question to answer, a reference to read, or a
     prompt clarification to add BEFORE starting.
3. **Sharpened brief**: 2–4 sentences the user can paste to start the real work with the
   top unknowns pre-resolved or explicitly deferred.

The document is consumed as-is, not machine-parsed — but it is consumed **from the file**.
```

The main loop does not parse the result beyond surfacing it — report-only means there is
no machine-readable contract to enforce. It does, however, depend on the file existing: the
subagent's final message is a single-delivery channel that a completed-but-idled subagent
never sends, so `<REPORT_PATH>` is the durable carrier and the return is corroboration.

---

## What this skill is NOT

- **Not `/brainstorming`.** Brainstorming decides *what to build* through dialogue;
  blind-spot surfaces *what you can't see* about a task you've already chosen, in one
  shot. They compose: blind-spot → then brainstorm the resolved scope.
- **Not a fixer or a planner.** It never edits code or writes a plan. Feed its output to
  `/writing-plans` or your next prompt. (Contrast `/spec-review-codex`, which fix-loops.)
- **Not architect review.** That reviews a finished diff for wiring; this reviews a
  *forthcoming task* for your blind spots. Opposite ends of the same axis.

## Deliberate simplifications (ponytail)

- **One subagent, not a panel.** One well-prompted pass covers the taxonomy. Upgrade
  path: fan out one subagent per axis (domain vs. codebase) and merge — only if
  single-agent recall proves insufficient.
- **Report-only, no interview loop.** The "interview me" follow-up stays a cheat-sheet
  prompt (`docs/unknowns-cheatsheet.md`); folding it in would rebuild `/brainstorming`'s
  dialogue machinery.
- **No CLI dependency.** Claude subagent over `codex`, so the skill installs anywhere.
- **Git repo optional.** A pure-domain pass needs no repo; not gating on one keeps the
  color-grading case in scope.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.

## Origins

Synthesizes two field notes on working with Claude Fable: Thariq's *"A Field Guide to
Fable: Finding Your Unknowns"* (the blind-spot pass and the known/unknown quadrant model)
and Diego Marino's *Fable adversarial audits* gist (adversarial framing + evidence-gated,
ID'd, impact-ranked findings). The reusable prompt library for the rest of the field
guide's techniques lives in `docs/unknowns-cheatsheet.md`.
