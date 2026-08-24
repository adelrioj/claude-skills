#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state"
export LINEAR_GROOM_CODEX="$HERE/fake-codex.sh"
# The entitlement gate must never make the suite depend on what THIS machine
# is entitled to run. Absent cache => gate skipped; the gate's own behaviour is
# tested below against fixtures.
export CODEX_MODELS_CACHE="$TMP/no-such-cache.json"
export FAKE_CODEX_STATE="$TMP"
RD="$TMP/state/linear-groom/MDZ-238"

setup_run() {
  rm -rf "$RD"; mkdir -p "$RD/wave1"
  cp "$HERE/fixtures/ticket-complete.json" "$RD/ticket.json"
  python3 "$ROOT/scripts/10-lint.py" --ticket "$RD/ticket.json" --out "$RD/gaps.json"
  printf '{"ticket":"MDZ-238","query":"q","candidates":[]}\n' >"$RD/candidates.json"
}

# --- happy path: three valid outputs ---
setup_run
export FAKE_CODEX_MODE=good
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >"$TMP/w1.out" 2>"$TMP/w1.err" \
  || fail "wave1 failed on the happy path: $(cat "$TMP/w1.err")"
for dim in veracity duplicates feasibility; do
  [ -f "$RD/wave1/$dim.json" ] && ok "produced wave1/$dim.json" || fail "missing $dim.json"
done

# --- codex invoked exactly three times (call-count, not a timing assertion) ---
setup_run
export FAKE_CODEX_LOG="$TMP/codex.log"; : >"$FAKE_CODEX_LOG"
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1
[ "$(grep -c '^call' "$FAKE_CODEX_LOG")" = "3" ] \
  && ok "invoked codex exactly three times" \
  || fail "codex calls: $(grep -c '^call' "$FAKE_CODEX_LOG")"
unset FAKE_CODEX_LOG

# --- caching: a second run does not re-invoke codex ---
export FAKE_CODEX_LOG="$TMP/codex2.log"; : >"$FAKE_CODEX_LOG"
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1
[ ! -s "$FAKE_CODEX_LOG" ] && ok "valid cached outputs are not regenerated" \
  || fail "re-invoked codex despite cache: $(cat "$FAKE_CODEX_LOG")"

# --- --force ignores the cache ---
: >"$FAKE_CODEX_LOG"
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 --force >/dev/null 2>&1
[ "$(grep -c '^call' "$FAKE_CODEX_LOG")" = "3" ] && ok "--force re-runs every dimension" \
  || fail "--force did not re-run"
unset FAKE_CODEX_LOG

# --- retry: junk once, then valid ---
setup_run
export FAKE_CODEX_MODE=flaky
rm -f "$TMP"/called-*
export FAKE_CODEX_LOG="$TMP/codex3.log"; : >"$FAKE_CODEX_LOG"
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1
[ "$(grep -c '^call' "$FAKE_CODEX_LOG")" = "6" ] \
  && ok "each dimension retries exactly once on invalid output" \
  || fail "expected 6 calls (3 fail + 3 retry), got $(grep -c '^call' "$FAKE_CODEX_LOG")"
[ -f "$RD/wave1/veracity.json" ] && ok "the retry result is kept" || fail "no output after retry"
unset FAKE_CODEX_LOG

# --- persistent junk on all three: every dimension UNAVAILABLE, exit 1 ---
setup_run
export FAKE_CODEX_MODE=junk
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>"$TMP/w2.err"
rc=$?
[ "$rc" -eq 1 ] && ok "exits 1 when every dimension is unavailable" || fail "expected 1, got $rc"
for dim in veracity duplicates feasibility; do
  [ -f "$RD/wave1/$dim.UNAVAILABLE" ] || fail "no UNAVAILABLE marker for $dim"
done
ok "writes an UNAVAILABLE marker per failed dimension"
[ -s "$RD/wave1/veracity.UNAVAILABLE" ] && ok "the UNAVAILABLE marker is non-empty (holds a reason)" \
  || fail "veracity.UNAVAILABLE exists but is empty"
[ ! -f "$RD/wave1/veracity.json" ] && ok "no bogus .json left beside UNAVAILABLE" \
  || fail "invalid output was kept as .json"

# --- mixed: one dimension UNAVAILABLE, two valid — exercises PRODUCED > 0 ---
setup_run
export FAKE_CODEX_MODE=mixed
export FAKE_CODEX_FAIL_DIM=duplicates
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>"$TMP/wmixed.err"
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 when at least one dimension is available" || fail "expected 0, got $rc"
[ -f "$RD/wave1/veracity.json" ] && ok "veracity.json produced in mixed mode" || fail "missing veracity.json in mixed mode"
[ -f "$RD/wave1/feasibility.json" ] && ok "feasibility.json produced in mixed mode" || fail "missing feasibility.json in mixed mode"
[ -f "$RD/wave1/duplicates.UNAVAILABLE" ] && ok "the failing dimension still gets its own UNAVAILABLE marker" \
  || fail "missing duplicates.UNAVAILABLE in mixed mode"
unset FAKE_CODEX_FAIL_DIM

# --- vrc=3 (jsonschema unimportable): FATAL, not retried, not a plain 0/3 reading ---
setup_run
export FAKE_CODEX_MODE=good
mkdir -p "$TMP/pystub"
printf 'raise ImportError("stub: jsonschema unavailable (test)")\n' >"$TMP/pystub/jsonschema.py"
export FAKE_CODEX_LOG="$TMP/codex5.log"; : >"$FAKE_CODEX_LOG"
PYTHONPATH="$TMP/pystub" bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>"$TMP/wfatal.err"
[ "$(grep -c '^call' "$FAKE_CODEX_LOG")" = "3" ] \
  && ok "a broken validator (vrc=3) is not retried" \
  || fail "expected 3 calls (no retry on fatal), got $(grep -c '^call' "$FAKE_CODEX_LOG")"
grep -qi "FATAL" "$RD/wave1/veracity.UNAVAILABLE" 2>/dev/null \
  && ok "the marker names the environment problem, not a model failure" \
  || fail "veracity.UNAVAILABLE missing or not marked FATAL: $(cat "$RD/wave1/veracity.UNAVAILABLE" 2>/dev/null)"
grep -qi "FATAL" "$TMP/wfatal.err" \
  && ok "the run-level summary surfaces the FATAL condition, not a plain N/3 reading" \
  || fail "no FATAL banner in stderr: $(cat "$TMP/wfatal.err")"
unset FAKE_CODEX_LOG

# --- codex crash is also UNAVAILABLE, not a hang or a silent pass ---
setup_run
export FAKE_CODEX_MODE=boom
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1
[ -f "$RD/wave1/feasibility.UNAVAILABLE" ] && ok "a non-zero codex exit becomes UNAVAILABLE" \
  || fail "crash did not produce an UNAVAILABLE marker"

# --- the entitlement gate (plugin convention: pins are checked, not trusted) ---
# Five behaviours, and the ordering one matters most: the gate must refuse
# BEFORE any codex call, or it has saved nothing over just letting the run fail.
setup_run
export FAKE_CODEX_MODE=good
export FAKE_CODEX_LOG="$TMP/gate.log"; : >"$FAKE_CODEX_LOG"
CODEX_MODELS_CACHE="$HERE/fixtures/models-cache.json" \
  bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1 \
  && ok "an entitled pin runs" || fail "entitled pin was refused"

setup_run
: >"$FAKE_CODEX_LOG"
CODEX_MODELS_CACHE="$HERE/fixtures/models-cache.json" CODEX_EFFORT_BUILD=xhigh \
  bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>"$TMP/gate.err"
[ "$?" -ne 0 ] && ok "an effort the model does not support is refused" \
  || fail "luna@xhigh was allowed, which the fixture forbids"
[ ! -s "$FAKE_CODEX_LOG" ] && ok "the refusal spends no codex call" \
  || fail "codex was invoked before the gate refused: $(cat "$FAKE_CODEX_LOG")"
grep -q -i "entitle" "$TMP/gate.err" && ok "the error names the entitlement problem" \
  || fail "error does not mention entitlement: $(cat "$TMP/gate.err")"
grep -q -i "not a verdict on the ticket" "$TMP/gate.err" \
  && ok "the error says this is not a verdict on the ticket" \
  || fail "error could be read as a finding about the ticket: $(cat "$TMP/gate.err")"

setup_run
CODEX_MODELS_CACHE="$HERE/fixtures/models-cache.json" CODEX_MODEL_BUILD=gpt-9-nope \
  bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1 \
  && fail "an unentitled model was allowed" || ok "an unentitled model is refused"

# The cache is a cache, not the authority: absent must skip the gate, not fail it.
setup_run
export FAKE_CODEX_MODE=good
CODEX_MODELS_CACHE="$TMP/definitely-absent.json" CODEX_MODEL_BUILD=gpt-9-nope \
  bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1 \
  && ok "an absent cache skips the gate rather than failing it" \
  || fail "absent cache blocked the run"

# A cache that exists but cannot be parsed is "cannot confirm", and the gate
# fails closed — the alternative is spending three codex calls to learn less.
setup_run
CODEX_MODELS_CACHE="$HERE/fixtures/models-cache-malformed.json" \
  bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1 \
  && fail "an unparseable cache was waved through" \
  || ok "an unparseable cache fails closed"

# --- the pinned model reaches codex ---
# Ruling F5: no second test double and no ARGV_LOG — fake-codex.sh already logs
# its full argv (including the prompt) to FAKE_CODEX_LOG when set, so reuse it.
setup_run
export FAKE_CODEX_MODE=good
export FAKE_CODEX_LOG="$TMP/codex4.log"; : >"$FAKE_CODEX_LOG"
bash "$ROOT/scripts/30-wave1.sh" MDZ-238 >/dev/null 2>&1
grep -q "gpt-5.6-luna" "$FAKE_CODEX_LOG" && ok "passes the pinned model to codex" \
  || fail "model not in argv: $(cat "$FAKE_CODEX_LOG")"
grep -q "model_reasoning_effort=high" "$FAKE_CODEX_LOG" && ok "passes the pinned reasoning effort to codex" \
  || fail "effort not in argv: $(cat "$FAKE_CODEX_LOG")"
unset FAKE_CODEX_LOG

exit "$FAILED"
