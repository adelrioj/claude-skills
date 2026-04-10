---
name: brainstorming-spec-review
description: "Use when a brainstorming design spec has been written and needs adversarial review before implementation planning. Sends spec to Codex for rigorous review, fixes findings, and loops until no critical or important issues remain. Triggers on: review spec, spec review, validate spec, check spec quality, brainstorming review."
user-invocable: true
---

# Spec Review via Codex

Adversarial review of design specs using Codex as an independent reviewer. Loops until the spec passes with zero CRITICAL and zero IMPORTANT findings.

**Why Codex:** The spec was written by this Claude instance. Self-review has author bias — the same blind spots that produced the issue prevent detecting it. Codex is a fresh model with no shared context, making it an effective adversarial reviewer.

---

## The Job

1. Locate the spec file
2. Send to Codex for adversarial review
3. Read findings
4. If verdict is NEEDS REVISION: fix the spec, loop back to step 2
5. If verdict is PASS: report clean to user
6. Maximum 3 review iterations (prevent infinite loops)

**Do NOT** proceed to implementation planning until the spec passes review.

---

## Step 1: Locate the Spec

1. If the user provided a file path as argument, use it
2. Otherwise, scan `docs/superpowers/specs/` for the most recent spec by date prefix (YYYY-MM-DD). Match `*-design.md`
3. If no spec found, ask the user for the path

Read the spec file and confirm with the user:
> "I'll send `<spec-path>` to Codex for adversarial review. Proceed?"

Wait for confirmation before continuing.

---

## Step 2: Send to Codex for Review

Build the Codex command. The review prompt lives at `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming-spec-review/spec-review-prompt.md`.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REVIEW_PROMPT="${PLUGIN_ROOT}/skills/brainstorming-spec-review/spec-review-prompt.md"
SPEC_FILE="<path-to-spec>"
FINDINGS_FILE="/tmp/spec-review-findings-$(date +%s).md"

codex exec --dangerously-bypass-approvals-and-sandbox "$(cat "$REVIEW_PROMPT")

---

# Spec to Review

$(cat "$SPEC_FILE")

---

# Instructions

1. Follow the review procedure above against this spec.
2. Verify all file paths, function names, and line numbers referenced in the spec against the actual codebase.
3. Write your complete findings to: $FINDINGS_FILE
4. Use the exact output format specified in the review prompt.
5. End with the Summary table and Verdict."
```

Run this via Bash. Codex writes findings to the temp file.

**Timeout:** 120 seconds. If Codex times out, report the timeout to the user and ask whether to retry or skip.

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

Show each CRITICAL and IMPORTANT finding (not MINOR) with its title, problem, and suggested fix. Ask:
> "I'll fix these N issues now. Any you want to handle differently?"

Wait for user response before fixing.

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
