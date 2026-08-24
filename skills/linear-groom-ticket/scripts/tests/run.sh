#!/bin/bash
# Runs the static-analysis gate, then every *.test.sh in this directory.
# Exit non-zero if any stage fails.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
SHELLCHECK_SKIPPED=0

# --- Static analysis gate -------------------------------------------------
#
# Two tiers, deliberately different, because the two kinds of script carry
# different risk:
#
#   Production scripts (scripts/*.sh, scripts/lib/*.sh) are held to
#   the DEFAULT severity of shellcheck — notes included. This is the code that
#   talks to a real Linear workspace, so a style smell there is worth reading.
#   These files must produce zero findings.
#
#   Test scripts (scripts/tests/*.sh) are held to `warning` and above only.
#   The suite's assertion idiom — `[ cond ] && ok "msg" || fail "msg"` — trips
#   SC2015 ("A && B || C is not if-then-else") at ~159 sites. That note is not
#   wrong: if `ok` ever failed, `fail` would run too. But `ok` is a bare
#   `printf`, so the residual risk is a printf failure, and rewriting 159
#   assertions by hand carries more risk of introducing a wrong assertion than
#   it removes. Warnings and errors in test code still fail this gate.
#
# If you add a new production script, it must pass the default tier. If a
# finding there is genuinely a false positive, annotate it at the site with
# `# shellcheck disable=SCxxxx` AND a comment saying why — never widen the
# tier or add a global suppression.
shellcheck_gate() {
  printf '\n== shellcheck (static analysis)\n'

  if ! command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_SKIPPED=1
    printf '  SKIPPED — shellcheck is not installed, so static analysis DID NOT RUN.\n'
    printf '  This run proves less than a normal one. Install it with:\n'
    printf '      brew install shellcheck\n'
    return 0
  fi

  local prod tests rc=0
  prod="$(find "$ROOT/scripts" -maxdepth 2 -name '*.sh' -not -path "$ROOT/scripts/tests/*" | sort)"
  tests="$(find "$HERE" -maxdepth 1 -name '*.sh' | sort)"

  printf '  production (default severity, notes included):\n'
  # shellcheck disable=SC2086  # deliberate word-splitting: one path per line
  if shellcheck $prod; then
    printf '    ok   %s file(s) clean\n' "$(printf '%s\n' "$prod" | wc -l | tr -d ' ')"
  else
    printf '    FAIL production scripts have shellcheck findings (see above)\n'
    rc=1
  fi

  printf '  tests (warning severity and above):\n'
  # shellcheck disable=SC2086  # deliberate word-splitting: one path per line
  if shellcheck --severity=warning $tests; then
    printf '    ok   %s file(s) clean\n' "$(printf '%s\n' "$tests" | wc -l | tr -d ' ')"
  else
    printf '    FAIL test scripts have shellcheck warnings or errors (see above)\n'
    rc=1
  fi

  return "$rc"
}

if ! shellcheck_gate; then FAILED=1; fi

# Hermetic by default: no test may consult the real ~/.codex/models_cache.json.
export CODEX_MODELS_CACHE="${CODEX_MODELS_CACHE_TEST:-/nonexistent/models_cache.json}"

# --- Test files -----------------------------------------------------------
for t in "$HERE"/*.test.sh; do
  [ -f "$t" ] || continue
  printf '\n== %s\n' "$(basename "$t")"
  if ! bash "$t"; then FAILED=1; fi
done

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  if [ "$SHELLCHECK_SKIPPED" -eq 1 ]; then
    echo "ALL TESTS PASSED (shellcheck SKIPPED — not installed, static analysis unverified)"
  else
    echo "ALL TESTS PASSED"
  fi
else
  echo "TESTS FAILED"
fi
exit "$FAILED"
