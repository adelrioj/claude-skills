---
name: swarm-execute
description: >-
  Use when a feature should be implemented as parallel user stories by a swarm:
  Claude orchestrates, Codex workers implement in isolated worktrees via the
  Workflow (ultracode) tool. Takes a plain-language feature request or a
  plan/spec file directly — no prd.json or tasks/ files needed.
  Triggers on: swarm execute, parallel execute, run stories parallel, swarm this.
user-invocable: true
---

# Swarm Execute — Parallel Story Execution via Workflow + Codex Workers

Implement a feature as parallel user stories. You are the **lead orchestrator**: you decompose, batch, author workflows, merge, and enforce quality. **Codex writes all the code** — workers are Claude agents whose only code-writing instrument is the OpenAI Codex CLI. You NEVER implement stories yourself (exception: minimal merge-fallout fixes in Step 5).

All state lives in this conversation and in git. No `tasks/prd.json`, no `progress.txt`, no `findings.md`, no `swarm-state.json`. Cross-batch knowledge flows through structured workflow outputs that you aggregate into the next batch's `args`. Durable recovery state is the git history itself: story-ID-tagged merge commits plus persisted worktrees.

---

## When to Use

- The user gives a feature request, or points at a plan/spec document, and wants parallel autonomous execution
- The work decomposes into ≥2 stories with at least some independence
- `codex` CLI is installed and authenticated

## When NOT to Use

- Single story or strictly sequential chain — implement directly (or delegate the one story to Codex via `/codex:rescue`)
- The user wants the file-based Ralph loop (`/plan-to-ralph` + `ralph.sh`) — that flow still exists for headless terminal execution

---

## Step 0: Prerequisites

STOP with a clear message on any failure:

| Check | How | On failure |
| --- | --- | --- |
| Codex CLI available | `command -v codex` | "codex CLI not found. Install: `npm install -g @openai/codex`, then `codex login`." |
| Git repo, clean tree | `git status --porcelain` empty | "Uncommitted changes. Commit or stash first." |
| Input exists | Feature request text, or a readable plan/spec path | Ask the user what to build (the only blocking question) |

Then pick the working branch: if the user named one, use it; if HEAD is the default branch, create `feat/<slug-from-request>` and switch to it; otherwise stay on the current branch. Record it as `baseBranch`.

---

## Step 1: Intake — Build the Story Table In-Memory

Two entry modes, one convergence point.

**Mode A — plain-language request:** Explore the repo first (relevant modules, conventions, test layout — use Explore agents for breadth). Then decompose the request into vertical-slice stories. Each story must be independently implementable and testable.

**Mode B — plan/spec file path:** Read the document. Parse tasks/phases/slices into stories. Preserve traceability: each story's `notes` cites its source ("Task N from `<path>`").

Both modes converge on the **story table** — held in conversation memory, never written to disk:

| Field | Content |
| --- | --- |
| `id` | `US-001`, `US-002`, … |
| `title`, `description` | What and why |
| `acceptanceCriteria[]` | Verifiable outcomes |
| `filesCreate[]`, `filesModify[]` | Predicted file paths |
| `dependsOn[]` | Story IDs (filled in Step 2) |
| `priority` | Number; doubles as merge order |
| `notes` | Source reference, wiring hints, anything a worker needs |

**Verify file predictions against the repo before batching**: every `filesModify` path must exist; every `filesCreate` parent directory should exist or be flagged. Mispredicted files silently break dependency analysis and conflict detection — this is the step most likely to produce bad batches.

### Detect Quality Gates

Never hardcode. Detect from the repo, in priority order:

1. CI config (`.github/workflows/*.yml`, `.gitlab-ci.yml`) — ground truth for what gates merges
2. `package.json` scripts (`test`, `lint`, `typecheck`, `build`) with the package manager from the lockfile
3. Ecosystem equivalents: Makefile targets, `pyproject.toml` (pytest/ruff/mypy), `Cargo.toml` (cargo test/clippy), `go.mod` (go test ./..., go vet)
4. Commands stated in the repo's CLAUDE.md / CONTRIBUTING.md

Keep gates as a **list of individual commands** (never `&&`-joined — a joined line hides which gate failed). Detect an optional e2e command the same way; it runs only at final validation (Step 6), never per-story. If none detected, omit it entirely.

**Run the gates once on the clean base now.** A failing baseline means pre-existing breakage would be blamed on workers and burn remediation attempts — stop and tell the user.

---

## Step 2: Dependency Analysis

Three passes, conservative by default. With structured story fields, passes 1–2 are now deterministic; text scanning is the safety net.

1. **Declared dependencies** — `dependsOn` from the plan/spec, plus text patterns in descriptions/notes (`depends on`, `requires X from`, `builds on`, `extends`, `uses X created in`).
2. **File overlap (hard signal)** — B modifies a file A creates → B depends on A. A and B modify the same file → serialize by priority. Module-index special case: A creates `foo.service.ts`, B modifies `foo.module.ts` to register it → B depends on A.
3. **Cross-references (weak signal)** — affordance IDs / shared concepts; confirmation only, never the sole basis for an edge.

**When uncertain, serialize.** False parallelization costs merge conflicts and wasted tokens; false serialization only costs time.

Output a dependency map with per-edge rationale (auditable):

```
US-002 → depends on [US-001]   (file overlap: US-002 modifies payment.service.ts created by US-001)
US-005 → independent           (no overlap, no references)
```

---

## Step 3: Batch Plan + User Approval

Topological sort into batches: batch 1 = zero-dependency stories; batch N = stories whose dependencies all sit in earlier batches. Within a batch, order by priority (= merge order). Then verify **no two stories in a batch touch the same file** — on conflict, demote the lower-priority story to the next batch; repeat until conflict-free.

Present the plan and wait for approval — this is the one mandatory human gate:

```
Swarm Execution Plan
─────────────────────
Branch: <baseBranch>      Stories: N      Batches: K
Quality gates: <detected list> (baseline: passing)
E2E: <command or "none detected">

Batch 1 (parallel): US-001 [P1] <title> | US-005 [P5] <title>   — files: no overlap ✓
Batch 2 (after 1):  US-002 [P2] <title> ← depends on US-001
...

Workers: Claude agents in isolated worktrees, all code written by Codex
(`codex exec --sandbox workspace-write`, foreground). Reviews: architect + QA
per story, max 2 attempts, before merge.

Proceed? [Y/adjust/cancel]
```

`adjust` is first-class: apply the user's changes (e.g. "move US-003 to batch 3"), re-verify conflicts, re-present.

---

## Step 4: Execute Each Batch — One Workflow Invocation Per Batch

The canonical script ships at `${CLAUDE_PLUGIN_ROOT}/skills/swarm-execute/templates/swarm-workflow.js`. It is **static** — all per-run data goes in `args`. Invoke it per batch:

```
Workflow:
  scriptPath: ${CLAUDE_PLUGIN_ROOT}/skills/swarm-execute/templates/swarm-workflow.js
  args:
    batch: <n>
    baseBranch: <baseBranch>
    baseSha: <git rev-parse HEAD — run this NOW, after the previous batch's merges>
    gates: [<individual gate commands>]
    e2eCommand: <only if detected — omit otherwise>
    findingsDigest: <aggregated learnings, "" for batch 1>
    projectContext: <one-paragraph feature summary + source doc path>
    stories: [<this batch's stories from the story table>]
```

What the script does per story (read it before first use; adapt a copy only if the project demands it):

1. **Implement** — a worker agent in an isolated worktree (`isolation: 'worktree'`). The worker drives `codex exec --sandbox workspace-write` (foreground, from the worktree, prompt via stdin heredoc) for ALL code-writing, verifies Codex actually changed something (working tree OR new commits — Codex may self-commit), runs each gate individually, loops Codex on failures (max 3 fix invocations), commits, and returns a schema-enforced report: `{storyId, committed, branch, worktreePath, headSha, filesChanged, gates, summary, findings{decisions,errors,patterns}}`. The script retries once in a fresh worktree when the result is null, uncommitted, or has failing gates (the `committed` flag is cross-checked against the reported gate results, never trusted alone).
2. **Review** — architect + QA agents in parallel; read-only by contract, non-isolated; they diff the persisted worktree via `git -C <worktreePath> diff <baseSha>..HEAD`. Schema-enforced verdicts with concrete fixes per blocker. Disjoint scopes (architect: conventions/architecture/security; QA: behavior coverage/assertion quality). A story passes ONLY when both reviewers returned a verdict and both verdicts are `pass` — a dead reviewer is retried once, then the story is blocked (a missing verdict never becomes a pass); a `blocked` verdict without actionable blockers also blocks (remediation would be impossible).
3. **Remediate** — if blocked: one non-isolated agent operating **inside the persisted worktree path** (never a fresh worktree — a fresh copy lacks the implementation) drives Codex to fix only the blockers, re-runs gates, commits. Then re-review. Hard cap: 2 review attempts total.

The workflow returns `{batch, results: [{storyId, status: pass|blocked|failed, impl, reviews, attempts, blockers?, orphanedWorktrees}]}`.

**Codex invocation rules baked into the script (keep them if you adapt it):** foreground only, `--sandbox workspace-write` (never `--dangerously-bypass-approvals-and-sandbox`), never resume sessions — no `codex exec resume` / `resume --last`, and no companion `task --resume-last`/`--background` (parallel workers can resume each other's threads; background jobs die with the session) — one Codex invocation at a time per worktree, instruct Codex to leave changes uncommitted (the worker commits), and always verify changes landed via `git diff --name-only <baseSha>` (covers working tree AND any self-made commits) — a write-incapable or confused Codex run "succeeds" with advice text instead of edits. Codex's sandbox has **no network**: workers run package-manager installs themselves, then re-invoke Codex.

**Determinism rules:** no timestamps or randomness inside the script (banned by the Workflow runtime). All labels derive from story IDs (`impl:US-001`, `arch:US-001#1`). Anything wall-clock goes in via `args`.

---

## Step 5: Merge — Lead-Only, Sequential, Between Workflows

After the batch workflow returns, **you** merge. Never delegate merging to agents (index/lock races, and conflict resolution needs judgment), never merge in parallel, never merge while a workflow is still running.

For each story with `status: "pass"`, in priority order:

1. **Sanity-check the result** (belt-and-braces against script bugs): `reviews` must contain both an `architect` and a `qa` verdict of `pass`. If not, treat the story as blocked and escalate — never merge unreviewed code.
2. Record `git rev-parse HEAD` as `preMergeSha` in the merge ledger, then bring the branch in: try `git merge --no-ff <branch> -m "feat(<scope>): [US-XXX] <title>"`. If the branch is unknown in the main repo (worktree isolation may not share refs), fetch it first: `git fetch "<worktreePath>" "<branch>:<branch>"`, then merge.
3. **Textual conflict** (merge aborts): resolve using both stories' context from the story table — favor preserving both stories' acceptance criteria. If the resolution is not obvious, `git merge --abort` and escalate to the user. Never force a resolution you can't justify.
4. Run all gates post-merge (individually). Passing in isolation doesn't guarantee passing after merge.
5. **Gate failure post-merge**: fix it yourself — minimal change only, never re-implement the story — commit as `fix(<scope>): resolve integration fallout from [US-XXX]` (honest message: it's integration fallout, not necessarily a conflict). Max 2 fix attempts; then roll back with `git reset --hard <preMergeSha>` (safe: merges are lead-only, sequential, unpushed) and mark the story blocked. Do **not** `git revert -m 1` — a revert commit poisons any later re-merge of the preserved branch.
6. Record in the merge ledger: storyId → branch → merge SHA → post-merge gate result.
7. Clean up: `git worktree list` — if listed, `git worktree remove --force <path>`; otherwise delete the directory, then `git worktree prune`. Delete the merged story branch with `git branch -d <branch>` (`-d` refuses if unmerged — itself a useful signal). Also remove any `orphanedWorktrees` reported for the story.

For each story with `status: "blocked"`, escalate:

```
US-XXX blocked after N review attempts. Remaining blockers: [file:line — issue]
Worktree preserved at <path> (branch <branch>).
Options: 1. Override — merge anyway   2. Skip   3. Abort swarm
```

For each story with `status: "failed"` (no committed implementation — `impl` may be null):

```
US-XXX failed implementation after <implAttempts> worktree attempt(s).
Orphaned worktrees: <list, or "none">
Options: 1. Retry in the next batch   2. Skip   3. Abort swarm
```

**On Skip, re-check dependents**: consult the dependency map; any not-yet-run story depending on the skipped one is removed from later batches and reported (it would land in a world missing its prerequisite). Blocked stories' worktrees are never deleted — they hold recoverable work.

### Findings Aggregation — the Bridge Between Batches

Before the next batch, fold every story's `findings` (decisions, errors + resolutions, patterns) and any fixed review blockers into a concise `findingsDigest` string. Next batch's workers receive it via `args` — their quality depends on it. Keep it a digest, not a transcript: deduplicate, drop story-specific noise, keep anything that prevents a repeated mistake. Hard bound: ~30 bullet lines / ~2,000 characters — when over, drop the oldest story-specific items first and keep cross-cutting conventions and error resolutions.

Then loop to Step 4 for the next batch (recompute `baseSha` — it must include this batch's merges).

---

## Step 6: Completion

1. Run all gates one final time on the assembled branch.
2. If an e2e command was detected, run it now (only here — never per-story or per-batch).
3. Verify no leftover worktrees (`git worktree list`); list any survivors (blocked stories) for the user.
4. Present the summary:

```
Swarm Execution Complete
─────────────────────────
Branch: <baseBranch>    Batches: K    Stories: M passed / N total
Merge ledger: US-001 → a1b2c3d ✓gates | US-002 → e4f5a6b ✓gates | ...
Reviews: X first-pass, Y after remediation, Z overridden, W skipped
Final gates: ✓    E2E: ✓ / not detected
Codex invocations: ~<sum of reported codexInvocations — approximate; the field is optional>
```

---

## Critical Rules

1. **You never implement stories** — Codex writes all story code via the workers. Your only code-writing is minimal merge-fallout fixes (Step 5.4).
2. **One workflow per batch; merges between workflows.** The merge is the batch barrier — batch N+1's worktrees must be copied from a base containing batch N's merges. Recompute `baseSha` before every batch.
3. **Merging is lead-only and sequential by priority.** No merge agents, no parallel merges.
4. **Conservative dependency analysis** — when uncertain, serialize.
5. **No external state files.** Story table, batch plan, merge ledger, findings digest: conversation memory. Recovery: git history + persisted worktrees.
6. **Reviews gate merges** — architect + QA per story, max 2 attempts, then escalate. Reviewers are read-only and never get worktree isolation; remediation always targets the persisted worktree path.
7. **Gates run per-worker AND post-merge**, individually, never `&&`-joined. E2E only at final validation.
8. **Codex discipline**: foreground, `--sandbox workspace-write`, never resume sessions (`codex exec resume`, companion `task --resume-last`/`--background`), verify changes via `git diff --name-only <baseSha>`, workers run package installs themselves (Codex has no network).
9. **User approves the plan** before any worker spawns; `adjust` is first-class.
10. **Skipping a story disqualifies its dependents** — re-check the dependency map on every skip.

---

## Recovery

If the session dies mid-swarm: the story table is gone, but the git state is not. On re-invocation with the same request/spec:

1. `git log --oneline` — merge commits tagged `[US-XXX]` show which stories already landed.
2. `git worktree list` + stray worktree directories — persisted worktrees hold unmerged implementations; review and merge or discard them first.
3. Rebuild the story table from the original input, mark landed stories done, re-run Steps 2–3 on the remainder (code has changed — dependencies may have too), and continue.
