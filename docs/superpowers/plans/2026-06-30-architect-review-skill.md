# `/architect-review` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a report-only `/architect-review` skill that dispatches a fresh Claude subagent to hunt completeness and wiring gaps in a finished feature, then registers it in the plugin docs.

**Architecture:** A single self-contained `SKILL.md` (no scripts, no templates) whose body IS the implementation — the four-step flow (preflight/scope → discover intent oracle → dispatch ONE `Agent` subagent → surface the ranked report) plus the subagent prompt composed inline at dispatch time. Skills auto-discover from `skills/*/SKILL.md`, so "wiring" the skill is just creating the file with valid frontmatter and adding parity entries to `README.md` and `CLAUDE.md`. No `plugin.json`/`marketplace.json` edits and no version bump — CI owns the version (`bump-version.yml`).

**Tech Stack:** Markdown skill definition (YAML frontmatter + prose instructions), the Claude Code `Agent` tool (subagent dispatch), `git diff`/`grep` for scope and evidence. No new runtime, no external CLI dependency — that independence from `codex` is the whole point of using a subagent.

## Global Constraints

- The skill is **report-only** — it edits nothing, has no fix loop, no convergence/enumeration-creep logic. Contrast `/spec-review-codex`, which fix-loops.
- The reviewer is a **fresh-context Claude `Agent` subagent** — deliberately NOT the `codex` CLI, so the skill has **no external CLI dependency** and installs anywhere.
- Findings are **scoped to the feature on the branch** (diff vs base `main`/`master`) but the subagent **traces the whole repo** to confirm reachability.
- The **evidence gate is mandatory**: no `Unwired`/`Missing` finding is reported without a cited empty-result search proving the gap — an uncited claim is downgraded to a question.
- Severity model reused from the family — `CRITICAL` / `IMPORTANT` / `ADVISORY` / `MINOR` — but **informational only** (ranking/triage); nothing loops on it.
- The only on-disk artifact is `/tmp/architect-review-<ts>.md` (audit trail), **never committed**.
- Files in scope, per the spec's Files section: `skills/architect-review/SKILL.md`, `README.md`, `CLAUDE.md`. Nothing else.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `skills/architect-review/SKILL.md` | The entire skill: frontmatter (triggering), the four-step flow, the inline subagent prompt, the boundaries, the ponytail simplifications. | Create |
| `README.md` | User-facing skills list — add a `/architect-review` entry matching the existing entries' depth. | Modify |
| `CLAUDE.md` | Project instructions — add a `### /architect-review` entry under `## Skills`, a one-clause mention in the intro `## What This Is`, and Key Conventions bullets. | Modify |

**Explicitly out of scope** (do not touch): `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (their descriptions are non-exhaustive summaries), and any version field (CI's `bump-version.yml` owns it). The spec's Files section names only the three files above.

There is no `scripts/` or `templates/` directory for this skill — the spec is explicit that the review prompt lives **inline** in `SKILL.md`, composed at dispatch like ship-it's subagent prompts, and there is no helper script to run.

---

### Task 1: Author the `/architect-review` skill definition

**Files:**
- Create: `skills/architect-review/SKILL.md`

**Interfaces:**
- Consumes: nothing (self-contained; the Claude Code `Agent` tool at runtime).
- Produces: a user-invocable skill named `architect-review`. The README and CLAUDE.md entries in Task 2 must use the exact slug `architect-review` and the command form `/architect-review`.

- [ ] **Step 1: Write the failing structural check**

There is no test framework for markdown skills — the honest, dependency-free "test" is a structural check on the frontmatter and required body concepts. Save this as a scratch script and run it; it will fail because the file does not exist yet.

```bash
cat > /tmp/check-architect-review.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
f=skills/architect-review/SKILL.md
fail=0
note() { echo "MISSING: $1"; fail=1; }

[ -f "$f" ] || { echo "MISSING: file $f"; exit 1; }

# --- frontmatter ---
head -1 "$f" | grep -qx -- '---'            || note "opening --- on line 1"
grep -qx 'name: architect-review' "$f"      || note "name: architect-review"
grep -qx 'user-invocable: true' "$f"        || note "user-invocable: true"
grep -q  '^description:' "$f"               || note "description: line"

# --- required body concepts (spec coverage) ---
for kw in \
  "Unwired" "Missing" "Incomplete" "Risk" "edge" \
  "Evidence" "Agent" "report-only" "trace" \
  "CRITICAL" "IMPORTANT" "ADVISORY" "MINOR" \
  "main.*master" "intent oracle" "Completeness verdict" \
  "architect-review-" ; do
  grep -qiE "$kw" "$f" || note "concept /$kw/"
done

[ "$fail" -eq 0 ] && echo "OK: architect-review SKILL.md structurally complete"
exit "$fail"
EOF
chmod +x /tmp/check-architect-review.sh
/tmp/check-architect-review.sh
```

Expected: `MISSING: file skills/architect-review/SKILL.md` (exit 1).

- [ ] **Step 2: Create the skill file with the full content below**

Create `skills/architect-review/SKILL.md` with exactly this content:

````markdown
---
name: architect-review
description: "Use after a feature is built — e.g. the final step of a ship-it run, right after review-pr — to check it is actually complete and wired, not just line-correct. Dispatches a fresh-context Claude subagent that traces the whole repo to hunt completeness and integration gaps in the branch's changes, then reports ranked, evidence-backed findings and fixes nothing. Triggers on: architect review, architecture review, completeness review, wiring review, is this wired, did we finish this, find the gaps, incomplete feature, created but not wired, dead code check, deep pass on what we built."
user-invocable: true
---

# Architect Review — Adversarial Completeness & Wiring

An **architect-level adversarial review for completeness and integration**, run on a
finished implementation. It answers the question the other review skills don't:

> "Do a deep pass at everything you built and make sure it's wired properly and works
> as intended. Find gaps, bits we didn't implement, code created but never wired,
> failure cases, edge cases."

This skill is a **finder, not a fixer** — like `/ponytail-audit`, it reports ranked,
evidence-backed findings and **edits nothing**. Contrast `/spec-review-codex`, which
fix-loops. There is no fix loop, no convergence logic, and no external CLI dependency.

**Where it sits in the family:**
- `/code-review`, `/review-pr` — line-level *correctness* on the diff.
- `/spec-review-codex` / `-local` — harden the *spec, before* any code exists.
- `/architect-review` — *completeness & wiring* of the finished feature. This skill.

**Why a fresh subagent (the adversarial mechanism).** The main loop *built* this code,
so it shares the author's blind spots — the same gap in reasoning that left code unwired
also prevents noticing it on self-review. A fresh `Agent` subagent re-derives "is this
actually reachable / complete?" from the code alone, with no memory of how it got
written. Same independence rationale as `spec-review-codex`, but a Claude subagent
instead of the `codex` CLI, so the skill has **no external CLI dependency** and installs
anywhere.

**Why report-only.** The intent is diagnostic — surface what's wrong so the user decides.
Report-only keeps the skill small (no fix/re-review loop to port) and the findings clean
(the subagent reviews a *static* tree — no moving target).

---

## Flow

### Step 0 — Preflight & scope

1. **In a git repo?** Run `git rev-parse --is-inside-work-tree`. If it fails, STOP with:
   > "Not in a git repository — nothing to review."
2. **An explicit argument overrides everything.** If the user named a target (a file, a
   directory, or a feature description), that IS the scope — skip diff computation and
   review exactly what was named (still trace the whole repo for reachability).
3. **Otherwise, scope to the branch diff.** Resolve the base branch: use `main` if it
   exists, else `master` (`git rev-parse --verify <name>`). Then compute:
   - changed-file list: `git diff --name-only <base>...HEAD`
   - full diff: `git diff <base>...HEAD`

   (Three-dot `<base>...HEAD` diffs against the merge-base — only what this branch
   changed, not unrelated drift on the base.)
4. **No diff AND no argument** (you are on the base branch, or nothing is committed) →
   **ask the user what to review.** This is the only blocking question — do not guess.

Announce the resolved scope in one line, then proceed:
> "Architect-reviewing `<scope>`<, oracle: path | code-only>. Dispatching the subagent."

### Step 1 — Discover the intent oracle (best-effort)

The reviewer tells "looks fine" from "incomplete feature" by knowing what was *supposed*
to exist. Auto-discover, best-effort — none of these is required:

- Newest design spec: the highest date-prefixed `docs/superpowers/specs/*-design.md`.
- Implementation plan if present: `tasks/` (e.g. `tasks/dex-plan.md`, `tasks/prd.json`)
  or the newest `docs/superpowers/plans/*.md`.

If found, pass it to the subagent as the **intent oracle** — the source of truth for
which promised features/tasks must be present and wired. If none is found, the review
proceeds **code-only**: completeness is judged purely from the code's own internal
promises (referenced-but-missing, defined-but-unwired). **Note in the report whether an
oracle was used.** The oracle is an enhancement, never a precondition.

### Step 2 — Dispatch ONE architect-review subagent

Dispatch a single fresh subagent via the **Agent tool** (`subagent_type: general-purpose`).
Compose the prompt from the template below, filling `<BASE>`, `<SCOPE>`, and `<ORACLE>`.
The subagent **reviews and reports only — it must edit nothing.** One subagent, not a
panel (see Deliberate simplifications).

### Step 3 — Report

1. Write the subagent's returned markdown to `/tmp/architect-review-$(date +%s).md`
   (audit trail, never committed).
2. Present the ranked findings in chat: the summary counts, the findings most-severe
   first, and the completeness verdict.
3. **STOP. Fix nothing.** If the user wants fixes applied, that is a separate, explicit
   request — this skill's contract ends at the report.

---

## The subagent prompt

Compose this at dispatch, substituting `<BASE>`, `<SCOPE>`, and `<ORACLE>`:

```
You are a fresh-context software architect reviewing a FINISHED implementation for
COMPLETENESS and WIRING. You did not write this code and have no memory of how it was
built — re-derive everything from the code itself. You are READ-ONLY: trace, reason,
and report. Do not edit, create, or delete any file.

## What to review (scope)

<SCOPE>
  # substitute exactly ONE of:
  # (a) branch diff:
  #   "The feature is the change on this branch vs <BASE>. Get the changed files with
  #    `git diff --name-only <BASE>...HEAD` and the full diff with
  #    `git diff <BASE>...HEAD`. Changed files:
  #    <name-only list>"
  # (b) explicit target:
  #   "Review this target: <argument>. Trace how it is (or isn't) integrated into the
  #    rest of the repository."

Focus your FINDINGS on the feature above, but trace the ENTIRE repository with Grep and
Read to confirm whether new code is actually reached. A diff-only review cannot tell
"created but not wired" from "wired elsewhere" — only whole-repo tracing can.

## Intent oracle

<ORACLE>
  # substitute exactly ONE of:
  # if found:
  #   "Here is the source of truth for what this feature was supposed to be. Anything it
  #    promises that is absent or unwired is a Missing/Incomplete finding:
  #    <spec/plan contents or path>"
  # if none:
  #   "No design spec or plan was found. Review CODE-ONLY: judge completeness from the
  #    code's own internal promises (referenced-but-missing, defined-but-unwired). Do not
  #    invent requirements the code never implies."

## Findings taxonomy (run this fixed checklist)

- Unwired    — a symbol / file / endpoint / handler / migration defined in the changeset
               but never invoked, registered, exported, routed, or scheduled.
- Missing    — referenced by the changeset (or promised by the oracle) but never defined.
- Incomplete — partial vs. stated intent: stub branches, TODO / pass / NotImplemented,
               half-handled cases, a config flag/field read but never acted on, a code
               path created but not finished.
- Bug/edge   — null / empty / error / boundary paths the new code opens but never closes.
- Risk       — wired but fragile: order-dependence, a missing migration/index, an
               untested seam, a silent-failure path.

## Evidence gate (MANDATORY — this is what keeps the report trustworthy)

The signature failure of a wiring review is the FALSE POSITIVE: declaring code dead when
it is in fact reached indirectly. Before reporting ANY Unwired or Missing finding, you
MUST check for indirect wiring and CITE the search that proves the gap:

- callers / imports / references (grep the symbol across the repo)
- string-keyed dispatch (the symbol's name used as a string in a registry / map / config)
- dependency-injection / decorator / plugin-registration patterns
- barrel files / re-exports (index.*, __init__.py, mod.rs, ...)
- dynamic dispatch / reflection / convention-based discovery
- config, env, CI, or manifest references (for files, hooks, schedules)

A finding with no cited empty-result search is DOWNGRADED to a question, not reported as
a finding. Cite the actual command you ran and show that it returned nothing.

## Severity (informational ranking — nothing loops on it)

CRITICAL / IMPORTANT / ADVISORY / MINOR. Rank findings most-severe first. Severity is
triage only; this skill fixes nothing, so severity gates nothing.

## Output — return a single markdown document, and nothing else

1. Summary table: counts per severity, and whether an intent oracle was used.
2. Findings, most-severe first. Each finding:
   - **Type** (taxonomy) · **Severity**
   - **Location**: `file:line`
   - **What**: one sentence
   - **Evidence**: the cited search / reasoning that proves it (for Unwired/Missing, the
     empty-result command you ran)
   - **Suggested fix**: one line, advisory only
3. **Completeness verdict**: COMPLETE or GAPS FOUND, in one sentence.

Your entire final message is this document — it is consumed as-is, not machine-parsed.
```

The main loop does not parse the result beyond surfacing it — report-only means there is
no machine-readable contract to enforce (unlike ship-it's three-field hand-off).

---

## What this skill is NOT

- **Not a fixer** — it never edits code. (Contrast `/spec-review-codex`, which fix-loops.)
- **Not a correctness linter** — line-level bugs unrelated to completeness are out of
  scope; that is `/code-review` / `/review-pr`. Overlap on integration-caused bugs is
  intentional and fine.
- **Not a whole-repo audit by default** — scope is the feature on the branch;
  `/ponytail-audit` already covers whole-repo over-engineering sweeps. (The subagent
  *traces* the whole repo, but *reports* on the feature.)

## Deliberate simplifications (ponytail)

- **One subagent, not a panel.** A single well-prompted architect covers the whole
  taxonomy. Upgrade path: fan out one subagent per taxonomy dimension and merge — add
  only if single-agent recall proves insufficient.
- **Report-only, no fix loop.** No convergence / enumeration-creep machinery to port.
- **No new CLI dependency.** Subagent over `codex`, so the skill installs anywhere.
- **No on-disk state** beyond the `/tmp` report (audit trail), never committed —
  consistent with the rest of the plugin.
````

- [ ] **Step 3: Run the structural check to verify it passes**

```bash
/tmp/check-architect-review.sh
```

Expected: `OK: architect-review SKILL.md structurally complete` (exit 0).

- [ ] **Step 4: Verify the frontmatter parses as YAML**

The structural grep does not prove the frontmatter is *valid* YAML. Parse just the
frontmatter block (macOS ships `ruby`):

```bash
awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' skills/architect-review/SKILL.md \
  | ruby -ryaml -e 'd=YAML.load(STDIN.read); raise "bad name" unless d["name"]=="architect-review"; raise "not invocable" unless d["user-invocable"]==true; puts "frontmatter OK"'
```

Expected: `frontmatter OK`. (If `ruby` is unavailable, load the plugin instead — see
Step 5 — which is the real acceptance test.)

- [ ] **Step 5: Verify the skill loads in Claude Code**

The definitive check is that Claude Code discovers the skill. In a scratch shell:

```bash
claude --plugin-dir . -p "/help" 2>&1 | grep -i architect-review || echo "NOTE: verify interactively — run 'claude --plugin-dir .' and confirm /architect-review is listed"
```

Expected: the line mentions `architect-review`, or the NOTE prompts an interactive
confirm. (Skills auto-discover from `skills/*/SKILL.md`; no registration is needed for
loading — Task 2 only adds human-facing docs.)

- [ ] **Step 6: Commit**

```bash
git add skills/architect-review/SKILL.md
git commit -m "feat(architect-review): add report-only completeness & wiring review skill"
```

---

### Task 2: Register the skill in `README.md` and `CLAUDE.md`

**Files:**
- Modify: `README.md` (append a `/architect-review` entry after the `/ship-it` entry)
- Modify: `CLAUDE.md` (intro clause in `## What This Is`; a `### /architect-review` entry under `## Skills`; Key Conventions bullets)

**Interfaces:**
- Consumes: the skill slug `architect-review` and command form `/architect-review` created in Task 1 — these must match exactly.
- Produces: nothing consumed by later tasks (final task).

- [ ] **Step 1: Write the failing registration check**

```bash
cat > /tmp/check-architect-register.sh <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
fail=0
grep -q '`/architect-review`' README.md || { echo "MISSING: README.md entry"; fail=1; }
grep -q '### `/architect-review`' CLAUDE.md || { echo "MISSING: CLAUDE.md skill section"; fail=1; }
grep -q '`/architect-review`.*report-only\|report-only.*architect-review' CLAUDE.md \
  || grep -qi 'architect-review.*evidence gate' CLAUDE.md \
  || { echo "MISSING: CLAUDE.md Key Convention for architect-review"; fail=1; }
[ "$fail" -eq 0 ] && echo "OK: architect-review registered in README + CLAUDE"
exit "$fail"
EOF
chmod +x /tmp/check-architect-register.sh
/tmp/check-architect-register.sh
```

Expected: `MISSING: README.md entry` (exit 1).

- [ ] **Step 2: Add the README entry**

In `README.md`, immediately after the `**`/ship-it`**` paragraph (the last skill in the
`## Skills` list), insert this new paragraph:

```markdown
**`/architect-review`** — After a feature is built, check it is actually complete and wired, not just line-correct. Dispatches a fresh-context Claude subagent that traces the whole repo to hunt completeness and integration gaps in the branch's changes — code created but never wired, referenced-but-missing symbols, half-finished paths, unclosed edge cases — then reports ranked, evidence-backed findings and fixes nothing. Report-only (a finder like `/ponytail-audit`, not a fixer), with no external CLI dependency. Every reported `Unwired`/`Missing` gap cites the empty-result search that proves it, so false "dead code" positives are filtered out. Scopes findings to the branch diff vs base but traces the whole repository for reachability; an explicit file/directory/feature argument overrides the diff scope.
```

- [ ] **Step 3: Add the intro clause in CLAUDE.md `## What This Is`**

In `CLAUDE.md`, find the sentence in the `## What This Is` paragraph:

> Two spec-review skills harden brainstorming design specs via adversarial review (one backed by OpenAI Codex, one by a local LMStudio model).

Insert this sentence immediately after it:

```markdown
`/architect-review` runs a fresh-subagent adversarial completeness-and-wiring review over a *finished* feature — report-only, no CLI dependency.
```

- [ ] **Step 4: Add the `### /architect-review` entry in CLAUDE.md `## Skills`**

In `CLAUDE.md`, immediately after the `### /ship-it` entry (the last skill section, which
ends before `## Development`), insert:

```markdown
### `/architect-review`
Adversarial **completeness & wiring** review of a finished feature — the diagnostic pass that runs after `/review-pr`, answering "is this actually done and integrated?" (not "is each line correct?", which is `/code-review` / `/review-pr`). Dispatches ONE fresh-context Claude `Agent` subagent (no `codex` dependency — installs anywhere) that scopes findings to the branch diff vs base (`main`/`master`) but traces the WHOLE repo to confirm reachability, running a fixed 5-type taxonomy (Unwired / Missing / Incomplete / Bug-edge / Risk) behind a mandatory **evidence gate**: no `Unwired`/`Missing` finding is reported without a cited empty-result search proving the gap — else it is downgraded to a question. **Report-only** — a finder like `/ponytail-audit`, never a fixer; writes the ranked report to `/tmp/architect-review-<ts>.md` (uncommitted) and STOPs. Auto-discovers an intent oracle (newest `*-design.md` or `tasks/` plan) best-effort, degrading to code-only. No scripts or templates — the subagent prompt is composed inline in `SKILL.md`.
```

- [ ] **Step 5: Add the Key Conventions bullets in CLAUDE.md**

In `CLAUDE.md`, at the end of the `## Key Conventions` list (after the last `/ship-it`
bullet), append these four bullets verbatim:

```markdown
- `/architect-review` is report-only — it dispatches a fresh Claude subagent and fixes nothing (contrast the spec-review family's fix loop); the only on-disk artifact is the `/tmp/architect-review-<ts>.md` audit report, never committed
- `/architect-review` uses a Claude `Agent` subagent, not `codex` — deliberately no external CLI dependency so it installs anywhere; the subagent is read-only and returns its markdown report as its final message (no machine-readable contract to parse, unlike ship-it's three-field hand-off)
- `/architect-review`'s evidence gate is the quality lever: no `Unwired`/`Missing` finding ships without a cited empty-result search (callers, string-keyed dispatch, DI/decorator, barrel re-exports, dynamic dispatch, config/CI/manifest) proving the gap — an uncited claim is downgraded to a question, not reported
- `/architect-review` scopes FINDINGS to the branch diff vs base but traces the WHOLE repo for reachability — a diff-only review can't distinguish "created but not wired" from "wired elsewhere"; an explicit file/dir/feature argument overrides diff scoping, and no-diff-no-argument is the only blocking question
```

- [ ] **Step 6: Run the registration check to verify it passes**

```bash
/tmp/check-architect-register.sh
```

Expected: `OK: architect-review registered in README + CLAUDE` (exit 0).

- [ ] **Step 7: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs(architect-review): register skill in README and CLAUDE.md"
```

---

## Self-Review

**1. Spec coverage** — every section of the spec maps to a task:

| Spec element | Where implemented |
|--------------|-------------------|
| What It Is: report-only finder, fresh subagent, no CLI dep | Task 1 Step 2 — header + "Why report-only" + Deliberate simplifications |
| Why a subagent (adversarial independence) | Task 1 Step 2 — "Why a fresh subagent" |
| Decisions table (reviewer / output mode / scope / oracle) | Task 1 Step 2 — Flow Steps 0–3 + subagent prompt |
| Scope: diff vs base + whole-repo tracing; arg override; no-diff-no-arg asks | Task 1 Step 2 — Step 0 + subagent prompt "What to review" |
| Intent oracle: auto-discover, degrade to code-only | Task 1 Step 2 — Step 1 + subagent prompt "Intent oracle" |
| Findings taxonomy (5 types) | Task 1 Step 2 — subagent prompt "Findings taxonomy" |
| Evidence gate (cite empty-result search; else downgrade to question) | Task 1 Step 2 — subagent prompt "Evidence gate" |
| Severity model (informational, no gate) | Task 1 Step 2 — subagent prompt "Severity" |
| Flow Steps 0–3 (preflight, oracle, dispatch, report to /tmp) | Task 1 Step 2 — Flow |
| Subagent contract (summary table, findings fields, verdict) | Task 1 Step 2 — subagent prompt "Output" |
| What This Skill Is NOT (3 boundaries) | Task 1 Step 2 — "What this skill is NOT" |
| Deliberate Simplifications (4) | Task 1 Step 2 — "Deliberate simplifications" |
| Integration with ship-it = out of scope | Not wired — honored by omission; noted in Global Constraints scope |
| Files: SKILL.md + README.md + CLAUDE.md | Task 1 (SKILL.md), Task 2 (README + CLAUDE) |
| No scripts/templates (prompt inline) | File Structure note + Task 1 creates only SKILL.md |

No gaps found.

**2. Placeholder scan** — the SKILL.md subagent prompt uses `<BASE>`, `<SCOPE>`, `<ORACLE>` deliberately; each has explicit substitution instructions inline (the `# substitute exactly ONE of:` comments), so they are template slots, not plan placeholders. No `TBD`/`TODO`/"handle edge cases"/"similar to Task N" anywhere. The full content of every file change is present verbatim.

**3. Type/name consistency** — the slug `architect-review` and command `/architect-review` are identical across the frontmatter, README entry, CLAUDE.md entries, and both verification scripts. The report path `/tmp/architect-review-<ts>.md` and the taxonomy type names (Unwired / Missing / Incomplete / Bug-edge / Risk) are consistent between the SKILL.md body and the CLAUDE.md summary. The subagent is dispatched via the `Agent` tool with `subagent_type: general-purpose` in Step 2, matching the "no `codex` dependency" convention.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-30-architect-review-skill.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
