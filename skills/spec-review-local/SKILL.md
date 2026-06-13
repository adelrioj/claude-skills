---
name: spec-review-local
description: "Use when a brainstorming design spec has been written and needs adversarial review before implementation planning, using a local model served by LMStudio (via the pi CLI) as the independent reviewer. Works offline — no hosted API needed. Triggers on: spec review local, local spec review, review spec locally, lmstudio review, review spec, spec review."
user-invocable: true
---

# Spec Review via pi (local LMStudio model)

Adversarial review of design specs using a local `pi` agent backed by whatever model is currently loaded in LMStudio. Loops until the spec passes with zero CRITICAL and zero IMPORTANT findings.

**Why a different agent:** The spec was written by this Claude instance. Self-review has author bias — the same blind spots that produced the issue prevent detecting it. The pi agent runs a different model (served locally by LMStudio at `http://127.0.0.1:1234`) with no shared conversation context, making it an effective adversarial reviewer. Pi has filesystem tools, so it verifies file paths and code references against the actual repo.

**Sibling skill:** `spec-review-codex` does the same review with OpenAI Codex — use it when a hosted frontier model is preferred and available.

---

## The Job

1. Locate the spec file
2. Detect the loaded LMStudio model
3. Send to pi for adversarial review
4. Read findings
5. If verdict is NEEDS REVISION: fix the spec, loop back to step 3
6. If verdict is PASS: report clean to user
7. Maximum 3 review iterations (prevent infinite loops)

**Do NOT** proceed to implementation planning until the spec passes review.

**Prerequisite:** `pi` must be on PATH and LMStudio must be running at `http://127.0.0.1:1234` with at least one LLM loaded. Model detection (Step 2) verifies this — abort with a clear error if no model is loaded.

---

## Step 1: Locate the Spec

1. If the user provided a file path as argument, use it
2. Otherwise, scan `docs/superpowers/specs/` for the most recent spec by date prefix (YYYY-MM-DD). Match `*-design.md`
3. If no spec found, ask the user for the path (this is the only blocking question — without a spec there is nothing to review)

Read the spec file, then announce and proceed immediately — do not wait for confirmation:
> "Sending `<spec-path>` to pi (local model via LMStudio) for adversarial review."

This skill runs autonomously: it is a self-validator that hardens the spec *before* it reaches the user. Pausing for human approval at the start or between iterations defeats its purpose. Go straight to Step 2.

---

## Step 2: Detect the Loaded Model

Ask LMStudio which LLM is currently loaded — do not hardcode a model name:

```bash
MODEL="$(curl -s --max-time 5 http://127.0.0.1:1234/api/v0/models \
  | jq -r '[.data[] | select(.state == "loaded" and .type == "llm")][0].id // empty')"

if [ -z "$MODEL" ]; then
  echo "ERROR: no LLM loaded in LMStudio at http://127.0.0.1:1234" >&2
  exit 1
fi
echo "Using LMStudio model: $MODEL"
```

- **curl fails / connection refused:** LMStudio is not running. Report this to the user and stop — do not loop.
- **Empty result:** LMStudio is running but no LLM is loaded. Report this to the user and stop.
- **Multiple models loaded:** the first one is used; mention which in the announcement.

Reuse the detected `$MODEL` for every iteration in this run.

---

## Step 3: Send to pi for Review

Build the pi command. The review prompt lives at `${CLAUDE_PLUGIN_ROOT}/skills/spec-review-local/spec-review-prompt.md`.

The reviewer needs to read the spec and the codebase but **must not modify anything**, so restrict pi to read-only tools (`read,grep,find,ls,bash`). Capture pi's stdout into the findings file rather than asking the model to write the file itself.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REVIEW_PROMPT="${PLUGIN_ROOT}/skills/spec-review-local/spec-review-prompt.md"
SPEC_FILE="<path-to-spec>"
FINDINGS_FILE="/tmp/spec-review-findings-$(date +%s).md"

PROMPT="$(cat "$REVIEW_PROMPT")

---

# Spec to Review

$(cat "$SPEC_FILE")

---

# Instructions

1. Follow the review procedure above against this spec.
2. Use the read/grep/find/ls/bash tools to verify all file paths, function names, and line numbers referenced in the spec against the actual codebase. The repository root is the current working directory.
3. Output your complete findings to stdout (this conversation's response). Do not attempt to write files — you don't have write tools.
4. Use the exact output format specified in the review prompt.
5. End with the Summary table and Verdict."

pi --provider lmstudio \
   --model "$MODEL" \
   --tools read,grep,find,ls,bash \
   --no-session \
   --print "$PROMPT" > "$FINDINGS_FILE"
```

Run this via Bash. The model's complete response (including findings and summary) lands in `$FINDINGS_FILE` via stdout capture.

**Timeout:** 600 seconds. A local model is slower than a hosted one; budget accordingly. If pi times out, report the timeout to the user and ask whether to retry or skip.

**On connection failure** (LMStudio stopped mid-run, model unloaded): pi will exit non-zero. Report the exact stderr to the user and stop — do not loop.

---

## Step 4: Read and Present Findings

Read the findings file. Parse the summary table at the bottom for counts and verdict.

Present to the user:
> **Spec Review — Iteration N/3**
>
> | Severity | Count |
> |----------|-------|
> | CRITICAL | X |
> | IMPORTANT | X |
> | ADVISORY | X |
> | MINOR | X |
>
> **Spec altitude:** design / detailed-implementation
> **Verdict:** PASS / NEEDS REVISION

If PASS → go to Step 6. (ADVISORY/MINOR findings may remain on a PASS — surface them as notes, do not loop on them.)
If NEEDS REVISION → go to Step 5.

List each CRITICAL and IMPORTANT finding (not ADVISORY or MINOR) with its title, problem, and suggested fix so the run stays transparent, then go straight to Step 5 and fix them. Do not ask for approval before fixing — the autonomous fix/re-review loop is the core of the skill. **Only CRITICAL and IMPORTANT findings drive the loop**; ADVISORY and MINOR are reported, never fixed-and-re-reviewed.

---

## Step 5: Fix and Loop

For each finding (CRITICAL first, then IMPORTANT — ignore ADVISORY and MINOR here):

1. Read the quoted spec text from the finding
2. Read the suggested fix
3. Decide **comply vs reframe** (see Fixing Guidelines): a normal finding gets the fix applied with the Edit tool; an *altitude* finding (one demanding the spec transcribe detail a named source of truth already pins) gets **reframed** into a coverage rule, not enumerated
4. Apply the edit and briefly note what was changed

**Convergence / enumeration-creep check (before re-running):** Compare this iteration's IMPORTANT findings to the previous iteration's. If they are the same category AND merely finer-grained versions of the same underlying concern (e.g. round 2 said "enumerate the error branches," round 3 says "enumerate even more error branches"), the loop is ratcheting on altitude, not substance. Stop early and report:
> "Findings are converging on enumeration detail, not substance. The design appears sound; the remaining findings are altitude disagreements better treated as ADVISORY. Treating as PASS with notes."

Then go to Step 6 — this is a PASS-with-notes outcome, **not** a max-iteration failure.

Otherwise, after all fixes are applied:
- Increment the iteration counter
- If iteration < 3 → go back to Step 3
- If iteration = 3 → report to user:
  > "Reached maximum review iterations (3). Remaining findings: [list]. Please review the spec manually before proceeding."

---

## Step 6: Report Clean

When pi returns PASS:

> "Spec passed adversarial review (iteration N/3, zero CRITICAL/IMPORTANT findings)."
>
> If there are MINOR findings, list them:
> "N MINOR suggestions (non-blocking): [titles]"

The spec is now ready for implementation planning.

---

## Fixing Guidelines

When fixing findings:

- **CRITICAL (contradictions, wrong references):** Verify the correct information from the codebase before fixing. Do not guess.
- **CRITICAL (missing file paths / functions):** Grep the codebase to find the correct path or function name. Update the spec with verified information.
- **IMPORTANT (ambiguous requirements):** Pick the most reasonable interpretation and make it explicit. Add a "Decision:" note inline so the user sees what was decided.
- **IMPORTANT (missing error paths):** Add a brief failure handling paragraph. Keep it proportional to the spec's existing level of detail.
- **IMPORTANT (missing edge cases):** Add to the relevant section. If there's an edge cases table, add rows. If not, add a bullet list.
- **Never remove content to fix a finding.** Clarify, correct, or expand instead.
- **Never change the architectural approach** to fix a finding. If a finding suggests the approach is wrong, flag it to the user instead of changing it.
- **Reframe, don't comply, on altitude findings.** If a finding asks the spec to transcribe implementation detail (enumerate more branches, cases, or guard returns) that a *named external source of truth* already pins — a characterization suite, golden master, or referenced source range — do NOT enumerate. Instead reframe the requirement as a coverage *rule* pointing at that source, and add a one-line `Decision:` note recording the choice. This is the altitude analogue of "never change the architectural approach": the reviewer is pushing the spec to the wrong altitude, and the right response is to reframe, not obey. If the finding was already ADVISORY, no spec edit is needed at all — just note it.

---

## Iteration State

Track across iterations:
- `iteration`: Current iteration number (1-3)
- `spec_path`: Path to the spec being reviewed
- `model`: The LMStudio model id detected in Step 2
- `findings_files`: List of findings file paths (for audit trail)
- `fixed_count`: Total findings fixed across all iterations
- `important_categories`: The set of categories of this iteration's IMPORTANT findings — compared against the previous iteration to detect enumeration creep (Step 5 convergence check)

All findings files are preserved in `/tmp/` for the user to inspect after the review completes.
