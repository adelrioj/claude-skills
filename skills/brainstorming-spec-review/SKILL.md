---
name: brainstorming-spec-review
description: "Use when a brainstorming design spec has been written and needs adversarial review before implementation planning. Sends spec to a local pi agent (qwen via LMStudio) for rigorous review, fixes findings, and loops until no critical or important issues remain. Triggers on: review spec, spec review, validate spec, check spec quality, brainstorming review."
user-invocable: true
---

# Spec Review via pi (local qwen)

Adversarial review of design specs using a local `pi` agent backed by qwen (LMStudio) as an independent reviewer. Loops until the spec passes with zero CRITICAL and zero IMPORTANT findings.

**Why a different agent:** The spec was written by this Claude instance. Self-review has author bias — the same blind spots that produced the issue prevent detecting it. The pi agent runs a different model (qwen3.6-35b-a3b via LMStudio at `http://127.0.0.1:1234`) with no shared conversation context, making it an effective adversarial reviewer. Pi has filesystem tools, so it verifies file paths and code references against the actual repo just like Codex did.

---

## The Job

1. Locate the spec file
2. Send to pi for adversarial review
3. Read findings
4. If verdict is NEEDS REVISION: fix the spec, loop back to step 2
5. If verdict is PASS: report clean to user
6. Maximum 3 review iterations (prevent infinite loops)

**Do NOT** proceed to implementation planning until the spec passes review.

**Prerequisite:** `pi` must be on PATH and `lmstudio/qwen3.6-35b-a3b` (or similarly named qwen model) must be loaded in LMStudio at `http://127.0.0.1:1234`. Verify with `pi --list-models | grep -i qwen` — abort with a clear error if no qwen model is listed.

---

## Step 1: Locate the Spec

1. If the user provided a file path as argument, use it
2. Otherwise, scan `docs/superpowers/specs/` for the most recent spec by date prefix (YYYY-MM-DD). Match `*-design.md`
3. If no spec found, ask the user for the path (this is the only blocking question — without a spec there is nothing to review)

Read the spec file, then announce and proceed immediately — do not wait for confirmation:
> "Sending `<spec-path>` to pi (local qwen via LMStudio) for adversarial review."

This skill runs autonomously: it is a self-validator that hardens the spec *before* it reaches the user. Pausing for human approval at the start or between iterations defeats its purpose. Go straight to Step 2.

---

## Step 2: Send to pi for Review

Build the pi command. The review prompt lives at `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-spec-review/spec-review-prompt.md`.

The reviewer needs to read the spec and the codebase but **must not modify anything**, so restrict pi to read-only tools (`read,grep,find,ls,bash`). Capture pi's stdout into the findings file rather than asking the model to write the file itself.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REVIEW_PROMPT="${PLUGIN_ROOT}/skills/brainstorming-spec-review/spec-review-prompt.md"
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
   --model qwen3.6-35b-a3b \
   --tools read,grep,find,ls,bash \
   --no-session \
   --print "$PROMPT" > "$FINDINGS_FILE"
```

Run this via Bash. The model's complete response (including findings and summary) lands in `$FINDINGS_FILE` via stdout capture.

**Timeout:** 600 seconds. A local 35B model is slower than hosted Codex; budget accordingly. If pi times out, report the timeout to the user and ask whether to retry or skip.

**On connection failure** (LMStudio not running, model not loaded): pi will exit non-zero. Report the exact stderr to the user and stop — do not loop.

---

## Step 3: Read and Present Findings

Read the findings file. Parse the summary table at the bottom for counts and verdict.

Present to the user:
> **Spec Review — Iteration N/3**
>
> | Severity | Count |
> |----------|-------|
> | CRITICAL | X |
> | IMPORTANT | X |
> | MINOR | X |
>
> **Verdict:** PASS / NEEDS REVISION

If PASS → go to Step 5.
If NEEDS REVISION → go to Step 4.

List each CRITICAL and IMPORTANT finding (not MINOR) with its title, problem, and suggested fix so the run stays transparent, then go straight to Step 4 and fix them. Do not ask for approval before fixing — the autonomous fix/re-review loop is the core of the skill.

---

## Step 4: Fix and Loop

For each finding (CRITICAL first, then IMPORTANT):

1. Read the quoted spec text from the finding
2. Read the suggested fix
3. Apply the fix using Edit tool
4. Briefly note what was changed

After all fixes are applied:
- Increment the iteration counter
- If iteration < 3 → go back to Step 2
- If iteration = 3 → report to user:
  > "Reached maximum review iterations (3). Remaining findings: [list]. Please review the spec manually before proceeding."

---

## Step 5: Report Clean

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

---

## Iteration State

Track across iterations:
- `iteration`: Current iteration number (1-3)
- `spec_path`: Path to the spec being reviewed
- `findings_files`: List of findings file paths (for audit trail)
- `fixed_count`: Total findings fixed across all iterations

All findings files are preserved in `/tmp/` for the user to inspect after the review completes.
