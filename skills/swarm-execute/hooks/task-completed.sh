#!/usr/bin/env bash
#
# TaskCompleted hook for swarm-execute
#
# Prevents a teammate from marking a task complete unless quality gates pass.
# Only triggers for tasks matching the [US-XXX] pattern (swarm story tasks).
#
# Quality gate commands are read from tasks/prd.json "qualityGates" array,
# making this hook portable across projects (no hardcoded commands).
#
# Exit codes:
#   0 — Allow task completion
#   2 — Block completion, stderr sent as feedback to teammate
#

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract task subject from JSON input
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // ""')

# Only gate tasks that match swarm story pattern [US-XXX]
if ! echo "$TASK_SUBJECT" | grep -qE '^\[US-[0-9]+\]'; then
  exit 0
fi

STORY_ID=$(echo "$TASK_SUBJECT" | grep -oE 'US-[0-9]+')

# Locate prd.json — search from current directory upward
PRD_FILE=""
SEARCH_DIR="$(pwd)"
while [ "$SEARCH_DIR" != "/" ]; do
  if [ -f "$SEARCH_DIR/tasks/prd.json" ]; then
    PRD_FILE="$SEARCH_DIR/tasks/prd.json"
    break
  fi
  SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

if [ -z "$PRD_FILE" ]; then
  echo "WARNING: tasks/prd.json not found. Skipping quality gate validation." >&2
  exit 0
fi

# Read quality gates from prd.json
GATE_COUNT=$(jq -r '.qualityGates // [] | length' "$PRD_FILE")

if [ "$GATE_COUNT" -eq 0 ]; then
  echo "WARNING: No qualityGates defined in $PRD_FILE. Skipping quality gate validation." >&2
  exit 0
fi

echo "TaskCompleted hook: Validating $GATE_COUNT quality gate(s) for $STORY_ID..." >&2

# Run each quality gate in order — fail fast on first failure
FAILED=0
for i in $(seq 0 $((GATE_COUNT - 1))); do
  GATE_CMD=$(jq -r ".qualityGates[$i]" "$PRD_FILE")
  echo "Running: $GATE_CMD ..." >&2
  if ! eval "$GATE_CMD" 2>&1; then
    echo "BLOCKED: '$GATE_CMD' failed for $STORY_ID. Fix the issue before marking complete." >&2
    FAILED=1
    break
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "Quality gates failed for $STORY_ID. Task completion blocked." >&2
  exit 2
fi

echo "All quality gates passed for $STORY_ID. Allowing task completion." >&2
exit 0
