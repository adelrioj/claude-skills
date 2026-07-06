---
name: claude-md-slim
description: "Use when CLAUDE.md has grown bloated and is taxing every session's context — the inverse of claude-md-improver. Triages each block into session-invariant rules (stay always-on) vs feature/subsystem detail (page out to docs/ behind a plain-path pointer), moving — never deleting — the detail so nothing is lost and the always-on token bill drops. Triggers on: slim claude.md, minimal claude.md, claude.md is bloated, shrink claude.md, split claude.md, make claude.md minimal, page out claude.md, claude.md too long, reduce project memory, point claude.md to docs, trim claude md."
user-invocable: true
---

# CLAUDE.md Slim — Page Out the Bloat

Makes the **root `CLAUDE.md` minimal** by keeping only what every session needs
always-on and **moving everything else to `docs/`** behind one-line pointers. The
inverse objective of `claude-md-improver`: that skill's gradient points at
*completeness* (it adds), this one's points at *minimal always-on context* (it
extracts). Opposite gradients, so opposite skills — don't ask the improver to slim,
it structurally can't.

**Why this exists (the evidence).** *"Less Context, Better Agents"* (Lodha et al.,
arXiv:2606.10209) found that full always-on history hit 71% task completion at 1.48M
tokens, while **pruned + summarized** context hit 91.6% at ~553K — less always-on
context, detail retrieved on demand, is both *cheaper and more reliable*. `CLAUDE.md`
is loaded into **every** session whether or not the task touches it; it is the
always-on-history problem in miniature.

**The load-time fact that makes or breaks this.** Paging out only helps if the pointer
is loaded **lazily**:

| Mechanism | Loaded when | Reduces always-on context? |
|---|---|---|
| Prose in `CLAUDE.md` | every session, eagerly | no |
| `@path` import | every session, eagerly (expanded at load) | **no — reorganizes only** |
| Plain path reference (`see docs/x.md for X`) | on demand, when the task needs it | **yes** |

**This skill uses plain-path pointers, NEVER `@`-imports.** An `@`-import feels like
splitting while paying the full token bill — it defeats the entire purpose.

**Where it sits in the family:**
- `claude-md-improver` — audit for *completeness/quality*; adds.
- `claude-md-slim` — cut *always-on size*; extracts. This skill.

**Fixer, not finder** (unlike `/architect-review-pr`, `/blind-spot`). It edits
`CLAUDE.md` and writes `docs/` files — so it **confirms the triage plan before
applying**, and **moves rather than deletes** (no information is lost; the root just
gets smaller and the detail becomes reachable-on-demand).

---

## The triage rule (the whole point)

For each block/bullet in the target `CLAUDE.md`, ask: **does this apply to EVERY task,
or only when touching a specific area?**

**STAYS always-on** — session-invariant rules, true regardless of what you're doing:
- Safety / non-negotiable constraints (things that must never happen).
- Build / test / lint / run commands (needed constantly).
- Repo-wide gates on any edit: commit-message format, branch rules, "run X before commit".
- One-line "what this is" orientation.
- The **pointer index** to `docs/` (added by this skill).

**PAGES OUT to `docs/<topic>.md`** — detail that only matters when in that area:
- Per-skill / per-feature / per-subsystem deep conventions.
- Long rationale ("why we did X this way") essays.
- Enumerations of edge-case rules for one component.
- Anything a session that never touches that area would never need.

Tie-breaker: if you're unsure whether a block is invariant, **page it out** — a missed
pointer costs one on-demand read; a kept paragraph costs every session forever.

---

## Flow

1. **Locate the target.** Default: the repo-root `CLAUDE.md`. If an argument names a
   path, use it. Confirm the file exists; if there's no `CLAUDE.md`, say so and stop —
   there's nothing to slim.

2. **Baseline.** Record current size: `wc -lc <path>`. This is the before-number the
   final check compares against.

3. **Triage.** Read the whole file. Classify every block per the rule above into
   STAYS vs a named `docs/<topic>.md` bucket. Group paged-out blocks by natural topic
   (one doc per subsystem/skill/concern — don't scatter into 30 tiny files).

4. **Present the plan — do not edit yet.** Show a table: each paged-out topic → target
   `docs/` path → the one-line pointer that will replace it in root; and the list of
   blocks that STAY. State the projected root size. Ask the user to approve, adjust the
   split, or cancel. **This confirm gate is mandatory** — `CLAUDE.md` is the user's
   project memory.

5. **Apply (on approval).**
   - Write each `docs/<topic>.md` with the extracted blocks verbatim (move, don't
     rewrite — preserve the exact wording so nothing is lost).
   - Rewrite root `CLAUDE.md`: the STAYS blocks, plus a short **plain-path pointer
     index** — e.g. `- Swarm-execute internals & conventions: see docs/swarm-execute.md`.
     Plain paths only; never `@docs/...`.
   - Leave everything **uncommitted** — the maintainer owns git.

6. **Verify the win (mandatory pre-return check).** Re-run `wc -lc <path>` and report
   before → after for the root, and confirm every paged-out block now lives in a
   `docs/` file (grep a distinctive phrase from each extracted section in its new home).
   If the root didn't actually shrink, or any block is missing from both root and docs,
   the slim failed — say so, don't claim success.

---

## Key rules

- **Move, never delete.** Every paged-out block lands verbatim in a `docs/` file. The
  no-data-loss guarantee is non-negotiable — this is a reorganizer, not a trimmer.
- **Plain-path pointers only, never `@`-imports** — an `@`-import stays eagerly loaded
  and defeats the skill.
- **Confirm before applying** — the plan (step 4) is shown and approved before any file
  is written; `CLAUDE.md` is precious.
- **Everything uncommitted** — reports and edits are left for the maintainer to review
  and commit.
- **Root stays coherent** — a slimmed `CLAUDE.md` must still read as a complete
  orientation on its own (what this is + the invariant rules + where to find the rest),
  not a stub of dangling links.
- Scope to the target file. Handle nested `CLAUDE.md` files only if the user names them —
  don't sweep the tree.
