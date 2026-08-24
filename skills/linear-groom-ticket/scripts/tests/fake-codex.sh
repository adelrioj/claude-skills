#!/bin/bash
# Test double for `codex exec`. Writes a canned payload to the path given by
# --output-last-message. Mode from $FAKE_CODEX_MODE; per-dimension call state
# in $FAKE_CODEX_STATE (needed by the 'flaky' mode).
set -uo pipefail

OUT=""
MODEL=""
EFFORT=""
PROMPT=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --output-last-message|-o) OUT="$arg" ;;
    -m) MODEL="$arg" ;;
    -c) case "$arg" in model_reasoning_effort=*) EFFORT="$arg" ;; esac ;;
  esac
  prev="$arg"
done
# The prompt is the last positional argument.
PROMPT="${!#}"

if [ -n "${FAKE_CODEX_LOG:-}" ]; then
  # Ruling (task 7, item 3): $FAKE_CODEX_LOG is a single file appended with
  # `>>` concurrently by up to three backgrounded fake-codex.sh invocations.
  # O_APPEND write atomicity is only guaranteed for pipe writes under
  # PIPE_BUF; a record carrying the full (multi-KB, prompt-inlined) argv can
  # exceed that and interleave with a concurrent writer's record, corrupting
  # a `^call` line boundary and making `grep -c '^call'` counts wrong in
  # either direction — including a false pass. The count and pinning
  # assertions only ever grep for the `call` marker, `out=`, the model, and
  # `model_reasoning_effort=<effort>`, so log only that: it keeps every
  # record far under PIPE_BUF, which makes the single `printf` append
  # effectively atomic and removes the interleaving class outright. The
  # prompt itself (which can span many physical lines) is dropped from the
  # log entirely rather than merely flattened.
  printf 'call out=%s -m %s -c %s\n' "$OUT" "$MODEL" "$EFFORT" >>"$FAKE_CODEX_LOG"
fi

# Which dimension is this? Read it out of the prompt text.
DIM=unknown
case "$PROMPT" in
  *'"dimension":"veracity"'*)    DIM=veracity ;;
  *'"dimension":"duplicates"'*)  DIM=duplicates ;;
  *'"dimension":"feasibility"'*) DIM=feasibility ;;
esac

emit_good() {
  cat >"$OUT" <<EOF
{"dimension":"$DIM","verdict":"needs-work","confidence":"medium",
 "deletion_stance":"neutral","delete_reason":null,"duplicate_of":null,
 "findings":[{"summary":"fake finding for $DIM","detail":"from fake-codex"}],
 "evidence":[{"kind":"file","ref":"fake.py:1","note":"fake"}]}
EOF
}

case "${FAKE_CODEX_MODE:-good}" in
  good) emit_good; exit 0 ;;
  junk) printf 'I think the ticket is fine, honestly.\n' >"$OUT"; exit 0 ;;
  boom) echo "fake-codex: exploded" >&2; exit 1 ;;
  flaky)
    marker="${FAKE_CODEX_STATE:-/tmp}/called-$DIM"
    if [ -f "$marker" ]; then emit_good; else : >"$marker"; printf 'nope\n' >"$OUT"; fi
    exit 0
    ;;
  mixed)
    # Exercises the PRODUCED > 0 boundary: every dimension except the one
    # named in $FAKE_CODEX_FAIL_DIM succeeds; that one persistently fails.
    if [ "$DIM" = "${FAKE_CODEX_FAIL_DIM:-}" ]; then
      printf 'nope, this dimension always fails in mixed mode\n' >"$OUT"
    else
      emit_good
    fi
    exit 0
    ;;
  *) echo "fake-codex: unknown mode ${FAKE_CODEX_MODE:-}" >&2; exit 9 ;;
esac
