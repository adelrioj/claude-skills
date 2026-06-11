---
name: spec-review-codex
description: "Use when a brainstorming design spec has been written and needs adversarial review before implementation planning, using OpenAI Codex as the independent reviewer. Requires the codex CLI. Triggers on: spec review codex, codex spec review, review spec with codex, codex review, review spec, spec review."
user-invocable: true
---

# Spec Review via Codex

Adversarial review of design specs using Codex as an independent reviewer. Loops until the spec passes with zero CRITICAL and zero IMPORTANT findings.

**Why a different agent:** The spec was written by this Claude instance. Self-review has author bias — the same blind spots that produced the issue prevent detecting it. Codex is a fresh model with no shared conversation context, making it an effective adversarial reviewer. Codex has filesystem access, so it verifies file paths and code references against the actual repo.

**Sibling skill:** `spec-review-local` does the same review with a local model served by LMStudio — use it when offline or when Codex is unavailable.

---

## The Job

1. Locate the spec file
2. Send to Codex for adversarial review
3. Read findings
4. If verdict is NEEDS REVISION: fix the spec, loop back to step 2
5. If verdict is PASS: report clean to user
6. Maximum 3 review iterations (prevent infinite loops)

**Do NOT** proceed to implementation planning until the spec passes review.

**Prerequisite:** `codex` must be on PATH and authenticated. Verify with `command -v codex` — abort with a clear error if missing.

---

## Step 1: Locate the Spec

1. If the user provided a file path as argument, use it
2. Otherwise, scan `docs/superpowers/specs/` for the most recent spec by date prefix (YYYY-MM-DD). Match `*-design.md`
3. If no spec found, ask the user for the path (this is the only blocking question — without a spec there is nothing to review)

Read the spec file, then announce and proceed immediately — do not wait for confirmation:
> "Sending `<spec-path>` to Codex for adversarial review."

This skill runs autonomously: it is a self-validator that hardens the spec *before* it reaches the user. Pausing for human approval at the start or between iterations defeats its purpose. Go straight to Step 2.

---

## Step 2: Send to Codex for Review

Build the Codex command. The review prompt lives at `${CLAUDE_PLUGIN_ROOT}/skills/spec-review-codex/spec-review-prompt.md`.

The reviewer needs to read the spec and the codebase but **must not modify anything**, so run Codex with the read-only sandbox. Capture the findings via `--output-last-message` (which writes Codex's final message to the findings file) rather than asking the model to write the file itself.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REVIEW_PROMPT="${PLUGIN_ROOT}/skills/spec-review-codex/spec-review-prompt.md"
SPEC_FILE="<path-to-spec>"
FINDINGS_FILE="/tmp/spec-review-findings-$(date +%s).md"

codex exec --sandbox read-only --output-last-message "$FINDINGS_FILE" "$(cat "$REVIEW_PROMPT")

---

# Spec to Review

$(cat "$SPEC_FILE")

---

# Instructions

1. Follow the review procedure above against this spec.
2. Verify all file paths, function names, and line numbers referenced in the spec against the actual codebase. The repository root is the current working directory. You are sandboxed read-only — do not attempt to write or modify files.
3. Your final message must be the complete findings document.
4. Use the exact output format specified in the review prompt.
5. End with the Summary table and Verdict."
```

Run this via Bash. Codex's final message (the findings) lands in `$FINDINGS_FILE` via `--output-last-message`.

**Timeout:** 120 seconds. If Codex times out, report the timeout to the user and ask whether to retry or skip.

**On failure** (codex not authenticated, network error): codex will exit non-zero. Report the exact stderr to the user and stop — do not loop.

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

When Codex returns PASS:

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
