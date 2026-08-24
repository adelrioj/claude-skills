#!/bin/bash
# Tests for scripts/lib/repocheck.py — the repo<->ticket plausibility gate the
# agent runs in SKILL.md step 1 after fetching the ticket over the Linear MCP.
# Pure and offline: no Linear, no orca, no network. (These assertions used to
# live inside fetch.test.sh, which drove them through the deleted 00-fetch.sh.)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- basename match ---
mkdir -p "$TMP/modernaize" && (cd "$TMP/modernaize" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-complete.json" --repo "$TMP/modernaize" >"$TMP/rc1.json"
rc=$?
[ "$rc" -eq 0 ] && ok "repocheck matches team name against repo basename" \
  || fail "repocheck exit $rc for modernaize/MDZ"

# --- clear mismatch ---
mkdir -p "$TMP/unrelated-thing" && (cd "$TMP/unrelated-thing" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-complete.json" --repo "$TMP/unrelated-thing" >"$TMP/rc2.json"
rc=$?
[ "$rc" -eq 3 ] && ok "repocheck exits 3 on mismatch" || fail "expected exit 3, got $rc"
grep -q '"matched": false' "$TMP/rc2.json" \
  && ok "mismatch payload records matched:false" || fail "payload: $(cat "$TMP/rc2.json")"

# --- commit-subject signal ---
mkdir -p "$TMP/whatever" && (
  cd "$TMP/whatever" && git init -q \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "MDZ-238 do a thing"
)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-complete.json" --repo "$TMP/whatever" >/dev/null
[ $? -eq 0 ] && ok "repocheck matches MDZ-nnn tokens in commit subjects" \
  || fail "commit-subject signal did not fire"

# --- short team key must not false-match via the origin hostname ---
mkdir -p "$TMP/anyname" && (
  cd "$TMP/anyname" && git init -q \
    && git remote add origin https://github.com/acme/anyname.git
)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-short-team-om.json" --repo "$TMP/anyname" >"$TMP/rc3.json"
rc=$?
[ "$rc" -eq 3 ] && ok "short team key OM does not false-match github.com in origin URL" \
  || fail "expected exit 3 for OM vs github.com, got $rc: $(cat "$TMP/rc3.json")"

# --- short team key must not false-match inside an ordinary basename ---
mkdir -p "$TMP/identity-service" && (cd "$TMP/identity-service" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-short-team-it.json" --repo "$TMP/identity-service" >"$TMP/rc4.json"
rc=$?
[ "$rc" -eq 3 ] && ok "short team key IT does not false-match inside 'identity-service'" \
  || fail "expected exit 3 for IT vs identity-service, got $rc: $(cat "$TMP/rc4.json")"

# --- signal 2 must not open the gate on ONE common word of a team name. ---
mkdir -p "$TMP/customer-data-warehouse" && (cd "$TMP/customer-data-warehouse" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-team-data-platform.json" \
  --repo "$TMP/customer-data-warehouse" >"$TMP/rc5.json"
rc=$?
[ "$rc" -eq 3 ] \
  && ok "team name 'Data Platform' does not match 'customer-data-warehouse' on one word" \
  || fail "expected exit 3 for Data Platform vs customer-data-warehouse, got $rc: $(cat "$TMP/rc5.json")"

mkdir -p "$TMP/core-utils" && (cd "$TMP/core-utils" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-team-core.json" --repo "$TMP/core-utils" >"$TMP/rc6.json"
rc=$?
[ "$rc" -eq 3 ] && ok "single-word team name 'Core' does not match 'core-utils'" \
  || fail "expected exit 3 for Core vs core-utils, got $rc: $(cat "$TMP/rc6.json")"

# --- the genuine multi-word match must survive the tightening ---
mkdir -p "$TMP/acme-data-platform" && (cd "$TMP/acme-data-platform" && git init -q)
python3 "$ROOT/scripts/lib/repocheck.py" \
  --ticket "$HERE/fixtures/ticket-team-data-platform.json" \
  --repo "$TMP/acme-data-platform" >"$TMP/rc7.json"
rc=$?
[ "$rc" -eq 0 ] && ok "the full team name 'Data Platform' still matches 'acme-data-platform'" \
  || fail "expected exit 0 for Data Platform vs acme-data-platform, got $rc: $(cat "$TMP/rc7.json")"

exit "$FAILED"
