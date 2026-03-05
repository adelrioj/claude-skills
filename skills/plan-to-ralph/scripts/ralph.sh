#!/bin/bash
set -euo pipefail

###############################################################################
# ralph.sh — Autonomous coding loop using Claude Code
#
# Reads tasks/prd.json for user stories, runs one Claude iteration per story,
# and loops until all stories pass or max iterations reached.
#
# Usage:
#   ${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh
#   ${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh --max-iterations 5
#   ${CLAUDE_PLUGIN_ROOT}/skills/plan-to-ralph/scripts/ralph.sh --dry-run
#
# Based on: https://github.com/snarktank/ralph
###############################################################################

# ── Configuration ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PRD_FILE="$PROJECT_DIR/tasks/prd.json"
PROGRESS_FILE="$PROJECT_DIR/tasks/progress.txt"
FINDINGS_FILE="$PROJECT_DIR/tasks/findings.md"
PROMPT_FILE="$SCRIPT_DIR/ralph-prompt.md"

MAX_ITERATIONS=15
DRY_RUN=false
MAX_TURNS=50

# ── Parse Arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-turns)
      MAX_TURNS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --max-iterations N  Maximum loop iterations (default: 15)"
      echo "  --max-turns N       Max Claude turns per iteration (default: 50)"
      echo "  --dry-run           Show what would run without executing"
      echo "  -h, --help          Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────

if [[ ! -f "$PRD_FILE" ]]; then
  echo "Error: prd.json not found at $PRD_FILE"
  echo "Run /plan-to-ralph first to generate it."
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: ralph-prompt.md not found at $PROMPT_FILE"
  exit 1
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "Creating tasks/progress.txt..."
  cat > "$PROGRESS_FILE" <<'EOF'
# Progress

## Iteration Log

<!-- Ralph appends timestamped entries below this line -->
EOF
fi

if [[ ! -f "$FINDINGS_FILE" ]]; then
  echo "Creating tasks/findings.md..."
  cat > "$FINDINGS_FILE" <<'EOF'
# Findings

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| (none yet) | — |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|

## Patterns Discovered

-

## Resources

-
EOF
fi

if ! command -v claude &>/dev/null; then
  echo "Error: 'claude' CLI not found. Install Claude Code first."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: 'jq' not found. Install with: brew install jq"
  exit 1
fi

# ── Helper Functions ──────────────────────────────────────────────────────────

remaining_stories() {
  jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE"
}

next_story_id() {
  jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].id // empty' "$PRD_FILE"
}

next_story_title() {
  jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].title // empty' "$PRD_FILE"
}

prd_project() {
  jq -r '.project // "unknown"' "$PRD_FILE"
}

prd_branch() {
  jq -r '.branchName // empty' "$PRD_FILE"
}

# ── Branch Verification ──────────────────────────────────────────────────────

EXPECTED_BRANCH=$(prd_branch)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [[ -n "$EXPECTED_BRANCH" && -n "$CURRENT_BRANCH" && "$EXPECTED_BRANCH" != "$CURRENT_BRANCH" ]]; then
  echo "Error: prd.json expects branch '$EXPECTED_BRANCH' but you are on '$CURRENT_BRANCH'."
  echo "Switch branches with: git checkout $EXPECTED_BRANCH"
  exit 1
fi

# ── Main Loop ─────────────────────────────────────────────────────────────────

PROJECT_NAME=$(prd_project)

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Ralph Autonomous Loop                     ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
printf "║  Project:    %-48s║\n" "$PROJECT_NAME"
printf "║  Branch:     %-48s║\n" "$CURRENT_BRANCH"
echo "║  PRD:        tasks/prd.json                                  ║"
echo "║  Progress:   tasks/progress.txt                              ║"
echo "║  Findings:   tasks/findings.md                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Stories remaining: $(remaining_stories)"
echo "Max iterations:    $MAX_ITERATIONS"
echo "Max turns/iter:    $MAX_TURNS"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] Would execute up to $MAX_ITERATIONS iterations."
  echo "[DRY RUN] Next story: $(next_story_id) - $(next_story_title)"
  exit 0
fi

ITERATION=0
LAST_STORY_ID=""
CONSECUTIVE_FAILURES=0
MAX_STORY_RETRIES=3

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))
  REMAINING=$(remaining_stories)

  # Check if all stories are done
  if [[ "$REMAINING" -eq 0 ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  All stories complete! Ralph is done."
    echo "═══════════════════════════════════════════════════════════════"
    break
  fi

  STORY_ID=$(next_story_id)
  STORY_TITLE=$(next_story_title)
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  echo "───────────────────────────────────────────────────────────────"
  echo "  Iteration $ITERATION/$MAX_ITERATIONS"
  echo "  Story:     $STORY_ID — $STORY_TITLE"
  echo "  Remaining: $REMAINING stories"
  echo "  Started:   $TIMESTAMP"
  echo "───────────────────────────────────────────────────────────────"

  # Run Claude Code with the prompt piped via stdin
  set +e
  claude --print \
    --dangerously-skip-permissions \
    --max-turns "$MAX_TURNS" \
    < "$PROMPT_FILE"
  EXIT_CODE=$?
  set -e

  END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo ""
  echo "  Iteration $ITERATION finished at $END_TIMESTAMP (exit code: $EXIT_CODE)"

  # If Claude exited with an error, stop the loop
  if [[ $EXIT_CODE -ne 0 ]]; then
    echo "  Claude exited with error code $EXIT_CODE. Stopping loop."
    exit 1
  fi

  # Post-iteration completion check: verify the story was actually marked complete
  STORY_STILL_PENDING=$(jq --arg id "$STORY_ID" \
    '[.userStories[] | select(.id == $id and .passes == false)] | length' "$PRD_FILE")

  if [[ "$STORY_STILL_PENDING" -gt 0 ]]; then
    # Track consecutive failures on the same story
    if [[ "$STORY_ID" == "$LAST_STORY_ID" ]]; then
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    else
      CONSECUTIVE_FAILURES=1
    fi
    LAST_STORY_ID="$STORY_ID"

    echo "  ⚠ Warning: Story $STORY_ID still marked as incomplete after iteration."
    echo "  Consecutive failures on this story: $CONSECUTIVE_FAILURES/$MAX_STORY_RETRIES"
    echo "  Check tasks/progress.txt and tasks/findings.md."

    if [[ $CONSECUTIVE_FAILURES -ge $MAX_STORY_RETRIES ]]; then
      echo ""
      echo "  Story $STORY_ID failed $MAX_STORY_RETRIES consecutive iterations. Stopping."
      echo "  Review findings.md and progress.txt, then re-run to continue."
      exit 1
    fi
  else
    echo "  ✓ Story $STORY_ID marked complete."
    LAST_STORY_ID=""
    CONSECUTIVE_FAILURES=0
  fi

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────

FINAL_REMAINING=$(remaining_stories)
TOTAL_STORIES=$(jq '.userStories | length' "$PRD_FILE")
COMPLETED=$((TOTAL_STORIES - FINAL_REMAINING))

echo "═══════════════════════════════════════════════════════════════"
echo "  Ralph Loop Summary"
echo "═══════════════════════════════════════════════════════════════"
echo "  Iterations run:   $ITERATION"
echo "  Stories completed: $COMPLETED / $TOTAL_STORIES"
echo "  Stories remaining: $FINAL_REMAINING"
echo "═══════════════════════════════════════════════════════════════"

if [[ "$FINAL_REMAINING" -gt 0 ]]; then
  echo ""
  echo "  Not all stories completed. Re-run to continue."
  exit 1
fi
