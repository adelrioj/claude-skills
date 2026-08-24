# shellcheck shell=bash
# Shared helpers for the linear-groom scripts. Source, do not execute.
# Bash 3.2 compatible.

: "${LINEAR_GROOM_CODEX:=codex}"
# Wave-1 model + effort. Named CODEX_MODEL_BUILD / CODEX_EFFORT_BUILD to match
# the plugin-wide convention (docs/codex-tuning.md) so tests/check-codex-knob.sh
# can see this pin like any other. The plugin reserves the `_BUILD` pair for
# code-writing and `_REVIEW` for review passes, and wave 1 is analysis, not
# code — so this is a deliberate exception, argued in
# docs/skills/linear-groom-ticket.md. Do not "fix" it to the _REVIEW pair
# without reading that section.
: "${CODEX_MODEL_BUILD:=gpt-5.6-luna}"
: "${CODEX_EFFORT_BUILD:=high}"

# Consumed by scripts that source this file (30-wave1.sh -> lib/entitled.py),
# not within common.sh itself, so shellcheck cannot see the use.
# shellcheck disable=SC2034
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  printf 'linear-groom: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# run_dir <ticket> -> prints the run directory path (does not create it)
run_dir() {
  printf '%s/linear-groom/%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"
}
