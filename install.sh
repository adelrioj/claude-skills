#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

mkdir -p "$SKILLS_DIR"

for skill in plan-to-ralph shape-to-ralph swarm-execute; do
  ln -sf "$SCRIPT_DIR/$skill" "$SKILLS_DIR/$skill"
  echo "  $SKILLS_DIR/$skill -> $SCRIPT_DIR/$skill"
done
