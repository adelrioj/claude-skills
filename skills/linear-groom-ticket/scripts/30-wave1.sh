#!/bin/bash
# Deterministic three-way fan-out of codex analysis agents.
#
# The number of agents, their prompts, their model and their reasoning effort
# are written here in bash. No model decides any of it. Output validation is
# done by validate.py with a bounded retry, so a malformed answer degrades to
# UNAVAILABLE rather than silently poisoning the verdict.
#
# Usage: 30-wave1.sh <TICKET> [--force]
# Exit: 0 if at least one dimension produced valid output, 1 if none did.
# Bash 3.2 compatible: no `wait -n`, no associative arrays.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib/common.sh"

TICKET="${1:-}"
[ -n "$TICKET" ] || die "usage: 30-wave1.sh <TICKET> [--force]"
shift
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

RD="$(run_dir "$TICKET")"
for required in ticket.json gaps.json candidates.json; do
  [ -f "$RD/$required" ] || die "missing $RD/$required — run 00-fetch.sh, 10-lint.py, 20-candidates.sh first"
done
mkdir -p "$RD/wave1"

# --- entitlement gate -------------------------------------------------------
# Plugin convention (docs/codex-tuning.md): a pinned model+effort pair is
# checked against the local models cache before it is used, because a pin ages
# and entitlements differ per account. Failing here costs nothing; failing
# later costs three codex calls that all come back UNAVAILABLE — an
# environment problem wearing the mask of "the models couldn't answer", which
# is the failure this skill works hardest to keep distinguishable.
#
# The cache is a cache, not truth: when it is absent the gate is SKIPPED, not
# failed. $CODEX_MODELS_CACHE exists so the test suite can point at a fixture
# (or at nothing) and stay hermetic — the suite must not pass or fail based on
# what this particular machine happens to be entitled to.
: "${CODEX_MODELS_CACHE:=$HOME/.codex/models_cache.json}"
if [ -s "$CODEX_MODELS_CACHE" ]; then
  if ! python3 "$SKILL_ROOT/scripts/lib/entitled.py" \
       "$CODEX_MODELS_CACHE" "${CODEX_MODEL_BUILD:-gpt-5.6-luna}" "${CODEX_EFFORT_BUILD:-high}"; then
    die "wave1: ${CODEX_MODEL_BUILD:-gpt-5.6-luna} @ ${CODEX_EFFORT_BUILD:-high} is not entitled on this account per $CODEX_MODELS_CACHE. This is an environment/entitlement problem, not a verdict on the ticket. Override with CODEX_MODEL_BUILD / CODEX_EFFORT_BUILD."
  fi
fi

# Build the context block a dimension needs. Inlined into the prompt rather
# than passed as a path: the run dir sits outside the repo and codex runs the
# model under --sandbox read-only.
context_for() {
  case "$1" in
    veracity)
      printf '=== TICKET (Linear MCP get_issue) ===\n'
      cat "$RD/ticket.json"
      ;;
    duplicates)
      printf '=== TICKET UNDER ANALYSIS (Linear MCP get_issue) ===\n'
      cat "$RD/ticket.json"
      printf '\n=== DUPLICATE CANDIDATES (assembled, unjudged) ===\n'
      cat "$RD/candidates.json"
      ;;
    feasibility)
      printf '=== TICKET (Linear MCP get_issue) ===\n'
      cat "$RD/ticket.json"
      printf '\n=== TEMPLATE COMPLETENESS LINT (deterministic, no LLM) ===\n'
      cat "$RD/gaps.json"
      ;;
  esac
}

# invoke <dim> <outfile> <logfile> <extra-instruction>
invoke() {
  local dim="$1" out="$2" log="$3" extra="$4"
  local prompt
  prompt="$(cat "$HERE/../prompts/$dim.md")
$(context_for "$dim")
$extra"
  "$LINEAR_GROOM_CODEX" exec \
    -m "${CODEX_MODEL_BUILD:-gpt-5.6-luna}" \
    -c model_reasoning_effort="${CODEX_EFFORT_BUILD:-high}" \
    --sandbox read-only \
    --output-last-message "$out" \
    "$prompt" >"$log" 2>&1
}

# run_dim <dim> — invoke, validate, retry once, else mark UNAVAILABLE.
# Return codes carry meaning to the caller (via `wait $pid`, since this runs
# backgrounded): 0 = valid output produced, 1 = genuinely unavailable (model
# never produced a valid answer, or codex itself crashed), 2 = FATAL — the
# validator itself could not run (validate.py exit 3, e.g. jsonschema is not
# importable). A FATAL result must not be treated as, or retried as, a bad
# model answer: a second attempt cannot fix a missing python module, and
# reporting it as an ordinary UNAVAILABLE would misdiagnose an environment
# problem as "the models couldn't answer".
run_dim() {
  local dim="$1"
  local final="$RD/wave1/$dim.json"
  local marker="$RD/wave1/$dim.UNAVAILABLE"
  local raw="$RD/wave1/$dim.raw"
  local codexlog="$RD/wave1/$dim.codex.log"
  local schema="$HERE/../schemas/wave1-$dim.json"
  local attempt reason vrc

  if [ "$FORCE" -eq 0 ] && [ -f "$final" ] \
     && python3 "$HERE/lib/validate.py" --schema "$schema" --file "$final" >/dev/null 2>&1; then
    printf '%s: cached\n' "$dim" >&2
    return 0
  fi
  rm -f "$final" "$marker"

  for attempt in 1 2; do
    local extra=""
    if [ "$attempt" -eq 2 ]; then
      extra="
YOUR PREVIOUS REPLY WAS REJECTED: it was not a single JSON object matching the
required shape. Reply with the JSON object only — no prose, no markdown fence."
    fi
    if ! invoke "$dim" "$raw" "$codexlog" "$extra"; then
      reason="codex exited non-zero on attempt $attempt: $(tail -3 "$codexlog" 2>/dev/null | tr '\n' ' ') (full log: $codexlog)"
      continue
    fi

    python3 "$HERE/lib/validate.py" --schema "$schema" --file "$raw" 2>"$raw.err"
    vrc=$?

    if [ "$vrc" -eq 0 ]; then
      mv "$raw" "$final"
      rm -f "$raw.err" "$codexlog"
      printf '%s: ok\n' "$dim" >&2
      return 0
    fi

    if [ "$vrc" -eq 3 ]; then
      # Environment misconfiguration, not a model failure — die immediately,
      # do not burn a retry on it, and label the marker unmistakably.
      reason="FATAL: validate.py could not run (python3's jsonschema module is not importable) — $(tr '\n' ' ' 2>/dev/null <"$raw.err") (codex output: $raw, codex log: $codexlog)"
      printf '%s\n' "$reason" >"$marker"
      rm -f "$raw" "$raw.err"
      printf '%s: %s\n' "$dim" "$reason" >&2
      return 2
    fi

    if [ "$vrc" -eq 2 ]; then
      reason="not JSON on attempt $attempt: $(tr '\n' ' ' 2>/dev/null <"$raw.err") (codex log: $codexlog)"
    else
      reason="wrong shape on attempt $attempt: $(tr '\n' ' ' 2>/dev/null <"$raw.err") (codex log: $codexlog)"
    fi
  done

  printf '%s\n' "$reason" >"$marker"
  rm -f "$raw" "$raw.err"
  printf '%s: UNAVAILABLE (%s)\n' "$dim" "$reason" >&2
  return 1
}

DIMENSIONS="veracity duplicates feasibility"

PIDS=""
for dim in $DIMENSIONS; do
  run_dim "$dim" &
  PIDS="$PIDS $!"
done

FATAL=0
for pid in $PIDS; do
  wait "$pid"
  rc=$?
  [ "$rc" -eq 2 ] && FATAL=1
done

PRODUCED=0
for dim in $DIMENSIONS; do
  [ -f "$RD/wave1/$dim.json" ] && PRODUCED=$((PRODUCED + 1))
done

if [ "$FATAL" -eq 1 ]; then
  {
    printf 'wave1: FATAL — the validator itself could not run for at least one\n'
    printf 'dimension (python3 lacks the jsonschema module). This is an environment\n'
    printf 'problem, not a verdict on the ticket: do NOT read the summary line below\n'
    printf 'as "the models could not answer". Fix the python3 environment (e.g. pip\n'
    printf 'install jsonschema) and re-run. See the *.UNAVAILABLE marker(s) under\n'
    printf '%s/wave1/ for which dimension(s) hit this.\n' "$RD"
  } >&2
fi

printf 'wave1: %d/3 dimensions available\n' "$PRODUCED" >&2
[ "$PRODUCED" -gt 0 ] || exit 1
exit 0
