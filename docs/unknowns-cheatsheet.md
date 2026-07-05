# Finding Your Unknowns — A Cheat Sheet

Working with a strong agentic model, **the quality of the work is bottlenecked by your
ability to surface your unknowns** — the gap between the *map* you give Claude (prompts,
context, skills) and the *territory* the work lives in (the codebase, the domain, the
real constraints). Reducing and planning for unknowns *is* the skill of agentic coding,
and it's learnable.

This is a copy-paste prompt library for doing that, organized by phase. You won't use
every technique every time — it's a collection to reach into. Where a technique already
has a dedicated skill in this plugin, it's marked → so this doubles as a
"which-tool-for-which-unknown" map.

Sources: Thariq's *"A Field Guide to Fable: Finding Your Unknowns"* (the techniques and
the quadrant model) and Diego Marino's *Fable adversarial audits* gist (evidence-gated,
ID'd, ranked findings).

---

## The four quadrants of unknowns

Before you prompt, sort what you know about the task:

| | **Known** | **Unknown** |
|---|---|---|
| **Known** | **Known knowns** — what's already in your prompt. What you tell the agent you want. | **Known unknowns** — gaps you're aware of but haven't figured out yet. |
| **Unknown** | **Unknown knowns** — so obvious you'd never write it down, but you'd recognize it instantly ("I know it when I see it"). | **Unknown unknowns** — what you haven't considered at all. What you don't even know to ask. |

Each quadrant has a technique that flushes it out. The two hardest — **unknown knowns**
(surfaced by prototypes) and **unknown unknowns** (surfaced by a blind-spot pass) — are
where the leverage is, because discovering them mid-implementation is expensive.

---

## Give Claude your starting point (applies to everything below)

The single most important input to any of these: **tell Claude where *you* are.** Your
experience with this problem and codebase, where you are in your thinking, what you've
ruled out. It searches code and the web faster than you and knows more about the average
topic — but only if it knows what you already know, so it doesn't waste the pass telling
you things you don't need or assuming expertise you don't have.

> Context on me before we start: I'm [role/experience]. With *this* problem I've [done X /
> ruled out Y / never touched Z]. Treat me as a thought partner, not a spec to execute.

---

## Pre-implementation

### Blind-spot pass — for unknown-unknowns → **`/blind-spot`**

When you're working in an unfamiliar part of the codebase or an unfamiliar domain, you
have unknown-unknowns: you don't know what to ask, what "good" looks like, what prior work
exists, or what potholes to avoid. Ask Claude to find them *for* you and teach them back.
Use the literal words "blind spot pass" and "unknown unknowns."

> I'm adding a new auth provider but I know nothing about the auth modules in this
> codebase. Do a blindspot pass to help me figure out my relevant unknown-unknowns and
> help me prompt you better.

> I don't know what color grading is but I need to grade this video. Teach me my
> unknown-unknowns about color grading so I can prompt better.

→ In this plugin, `/blind-spot` runs this as an adversarial, evidence-gated pass with a
fresh subagent and a ranked briefing.

### Brainstorm & prototype — for unknown-knowns → **`/brainstorming`**

When success criteria are the "I'll know it when I see it" kind (especially visual
design), verbalize them *early* by reacting to cheap artifacts, before implementation
makes them expensive to change. Small spec changes cause large code changes; reverting is
costly. Start most sessions here to set scope — Claude finds high-value approaches you'd
miss and prevents you from setting scope too narrow or too wide.

> I want a dashboard for this data but I have no visual taste and don't know what's
> possible. Make me an HTML page with 4 wildly different design directions so I can react.

> Before wiring anything up, make a single HTML file mocking the new editor toolbar with
> fake data. I want to react to the layout before you touch the real app.

> Here's my rough problem: users churn after onboarding. Search the codebase and
> brainstorm 10 places we could intervene, cheapest to most ambitious. I'll tell you which
> resonate.

### Interview me — for known-unknowns and ambiguity

After brainstorming, you'll still have unknowns. Have Claude interview *you*, one question
at a time, and prioritize the questions whose answers change the architecture.

> Interview me one question at a time about anything ambiguous in this task. Prioritize
> questions where my answer would change the architecture. Wait for each answer before the
> next question.

### References — when you can't describe it, point at it

Sometimes you lack the language, or describing it in words would take forever. The best
reference is **source code** — a library that implements the behavior you want, a
component you like — even in a different language. Point Claude at the folder and say what
to look for. (This is also how Claude Design works: point it at a module on a site you
like and it reads the underlying markup and structure, not just a screenshot.)

> This Rust crate in `vendor/rate-limiter` implements the exact backoff behavior I want.
> Read it and reimplement the same semantics in our TypeScript API client.

### Implementation plan — surface the decisions most likely to change → **`/writing-plans`**

When you think you're ready, ask for a plan that *leads with the parts you're most likely
to tweak* — data models, type interfaces, UX flows — so Claude surfaces the things you may
actually need to alter, instead of burying them under mechanical detail.

> Write an implementation plan, but lead with the decisions I'm most likely to change:
> data model changes, new type interfaces, and anything user-facing. Bury the mechanical
> refactoring at the bottom — I trust you on that part.

---

## During implementation

### Implementation notes — capture deviations as they surface

No amount of planning kills every unknown-unknown; the agent finds edge cases mid-work.
Have it keep a temporary `implementation-notes.md` logging decisions and deviations, so
the *next* attempt learns from this one.

> Keep an `implementation-notes.md` file. If you hit an edge case that forces you to
> deviate from the plan, pick the conservative option, log it under "Deviations," and keep
> going.

---

## Post-implementation

### Pitches & explainers — get buy-in

Shipping means getting approvals. A pitch/explainer artifact accelerates understanding
(reviewers start with the same unknowns you did) and approvals (experts want to see you
accounted for the failure points they'd anticipate).

> Package the prototype, the spec, and the implementation notes into a single doc I can
> drop in Slack to get buy-in. Lead with the demo GIF.

### Quizzes — verify *you* understand what shipped

After a long session Claude may have done more than you realize, and diffs give only a
shallow read since behavior depends on existing code paths. Have Claude quiz you — and
only merge once you pass.

> Give me an HTML report on this change — context, intuition, what was done and why — with
> a quiz at the bottom on the changes that I must pass before I merge.

### Completeness & wiring check → **`/architect-review`**

Confirm the feature is actually finished and integrated, not just line-correct: code
created but never wired, referenced-but-missing symbols, half-finished paths, unclosed
edge cases.

> /architect-review

---

## Quick map

| Technique | Phase | Unknown it flushes | Tool |
|-----------|-------|--------------------|------|
| Blind-spot pass | pre | unknown-unknowns | **`/blind-spot`** |
| Brainstorm & prototype | pre | unknown-knowns | `/brainstorming` |
| Interview me | pre | known-unknowns | this cheat sheet |
| References | pre | can't-describe-it | this cheat sheet |
| Implementation plan | pre | decisions likely to change | `/writing-plans` |
| Implementation notes | during | edge cases found mid-build | this cheat sheet |
| Pitches & explainers | post | reviewers' unknowns | this cheat sheet |
| Quizzes | post | *your* understanding of the change | this cheat sheet |
| Completeness & wiring | post | created-but-not-wired | `/architect-review` |
