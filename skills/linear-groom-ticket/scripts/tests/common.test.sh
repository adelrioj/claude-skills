#!/bin/bash
# Tests for scripts/lib/common.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0

ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

# Isolate run-dir state so we never touch the real one.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"

# shellcheck source=/dev/null
. "$ROOT/scripts/lib/common.sh"

# --- run_dir ---
got="$(run_dir NBS-238)"
want="$TMP/state/linear-groom/NBS-238"
[ "$got" = "$want" ] && ok "run_dir honours XDG_STATE_HOME" \
  || fail "run_dir: got '$got' want '$want'"


# --- jsonutil fence stripping ---
got="$(printf '```json\n{"a":1}\n```' | python3 -c '
import sys
sys.path.insert(0, "'"$ROOT"'/scripts/lib")
import jsonutil
print(jsonutil.load_lenient(sys.stdin.read())["a"])
')"
[ "$got" = "1" ] && ok "load_lenient strips a json fence" \
  || fail "load_lenient: got '$got' want '1'"

exit "$FAILED"
