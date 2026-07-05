Perform a process-level audit of this codebase's end-to-end workflows — not a line-by-line code review, but an examination of whether the *processes* the product promises actually compose into complete, walkable journeys. Find holes, dead ends, missing transitions, and steps where a user or agent gets stranded.

# Role
Act as a product-minded staff engineer walking every documented journey twice: once as a first-time human user following only the docs, once as an autonomous agent chaining commands via exit codes and JSON output. No loyalty to the current flows.

# Scope — processes to walk (empirically, in throwaway workspaces)
First, discover this project's real journeys. Read the README, docs/**, specs/**/quickstart.md, `--help` output, and the command/entry-point surface to enumerate the end-to-end flows the product actually promises. Typical shapes to look for (adapt to what this repo does — do not assume any of these exist):
- Onboarding: empty install → health/doctor check → init/config → ready-to-use. Where does a newcomer get stranded? Is every suggested fix executable verbatim?
- Core lifecycle(s): the primary create → transform → review → finalize pipeline this product exists to run. Walk it start to finish, then re-run steps out of order and against half-completed prior state.
- Review/approval loops, if any: does an item that enters a "needs attention" state have a command that moves it forward, and a recovery/reopen path if rejected?
- Persistence/filing/output: idempotency AND exit code on re-run; collision/suffix behavior; partial failure (kill mid-operation, unwritable target).
- Side processes: any secondary workflow the docs promise (memory/history lifecycles, artifact generation + validation, background/preflight checks).
- Cross-process coherence: enumerate every state a record/entity can occupy across all subsystems and check there is a command that moves each state forward. Build the real state machine; mark unreachable states and absorbing dead ends.

# Hunt for
- Dead ends: states with no exit command, fixable today only by hand-editing workspace/state files.
- Missing processes: steps that the docs, README, or quickstarts promise but no command implements.
- Re-run/second-call semantics: every mutating command run twice, out of order, and against a half-completed prior run.
- Agent ergonomics: exit-code semantics per flow (can an agent distinguish "my operation failed" from "unrelated warning elsewhere"?), JSON/output contract stability across commands, help text vs actual flags, error-output parseability.
- Docs/process drift: walk each documented journey command-by-command against reality.
- Concurrency: two invocations against the same workspace/state at once.

# Method
- Build real throwaway workspaces under a gitignored directory (e.g. `*.local/`); never mutate the real repo or the user's data. If a flow shells out to external binaries the environment lacks (converters, OCR, cloud CLIs, etc.), stub them via PATH shims so the flow can be exercised — note where you did so.
- Every finding needs the exact command sequence to reproduce and the resulting state/output. Mark CONFIRMED (reproduced) vs PLAUSIBLE (traced only).
- Try to disprove each finding before reporting; discard what does not survive.

# Output
Write full report -> docs/audits/process-audit-<YYYY-MM-DD>.md. Create dir if missing. Leave uncommitted (maintainer owns git).
Every finding = stable ID (P1, P2... severity order); a fixing agent cites these.
Sections, top-heavy (summary + map first, detail last):
1. Summary table: ID | severity | process | one-line issue | CONFIRMED/PLAUSIBLE.
2. Process map: real per-record state machine (states, transitions, owning command); mark dead ends + unreachable states.
3. Gaps/errors by process, severity order. Each: ID, file:line or command sequence, concrete stranded-user scenario, CONFIRMED/PLAUSIBLE, recommended direction.
4. Missing-process backlog: command/flag/skill needed per documented journey to complete end-to-end; prioritize by unblocking value.
5. Open questions: maintainer-only.
Chat reply = short exec summary only: counts by severity + top 3-5 findings + report path. Rest lives in file.

Thorough over brief. Spend effort where flows break; one line where they hold.
