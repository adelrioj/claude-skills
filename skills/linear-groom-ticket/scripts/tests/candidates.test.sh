#!/bin/bash
# Tests for scripts/20-candidates.py — the offline candidate assembler.
# The Linear reads are the agent's job (MCP); this script only assembles the
# candidate set from the part files the agent writes, so the test stages those
# parts directly. No orca, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

CAND="$ROOT/scripts/20-candidates.py"

# stage_parts <run-dir> — a ticket.json plus a .candidate-parts dir with a
# search result (MDZ-100, MDZ-238-self, a dup of MDZ-101) and one open-state
# list (MDZ-101, MDZ-100 again — the dup must collapse).
stage_parts() {
  local rd="$1"
  mkdir -p "$rd/.candidate-parts"
  cp "$HERE/fixtures/ticket-complete.json" "$rd/ticket.json"
  cat >"$rd/.candidate-parts/search.json" <<'JSON'
{"result":{"issues":[
  {"identifier":"MDZ-238","title":"self must be excluded","state":{"name":"To Do"},"url":"u0"},
  {"identifier":"MDZ-100","title":"join predicate dropped","state":{"name":"To Do"},"url":"u1"},
  {"identifier":"MDZ-101","title":"unrelated","state":{"name":"Backlog"},"url":"u2"}
]}}
JSON
  cat >"$rd/.candidate-parts/open-1.json" <<'JSON'
{"result":{"issues":[
  {"identifier":"MDZ-100","title":"join predicate dropped","state":{"name":"To Do"},"url":"u1"},
  {"identifier":"MDZ-102","title":"only in open list","state":{"name":"In Progress"},"url":"u3"}
]}}
JSON
}

# --- basic dedup + shape ---------------------------------------------------
RD="$TMP/state/linear-groom/MDZ-238"
stage_parts "$RD"
# MDZ-100 carries the ticket's own spec URL — a shared identifier.
printf '{"result":{"issue":{"description":"see https://example.invalid/spec for the JOIN work"}}}\n' \
  >"$RD/.candidate-parts/body-MDZ-100.json"
printf '{"result":{"issue":{"description":"nothing in common here"}}}\n' \
  >"$RD/.candidate-parts/body-MDZ-101.json"
printf '{"result":{"issue":{"description":"open-only candidate body"}}}\n' \
  >"$RD/.candidate-parts/body-MDZ-102.json"

python3 "$CAND" --run-dir "$RD" --ticket MDZ-238 >"$TMP/c.out" 2>"$TMP/c.err" \
  || fail "20-candidates failed: $(cat "$TMP/c.err")"
[ -f "$RD/candidates.json" ] && ok "writes candidates.json" || fail "no candidates.json"

python3 - "$RD/candidates.json" <<'PY' && ok "dedup, self-exclusion and shared-identifier extraction" || fail "assembly shape wrong"
import json, sys
d = json.load(open(sys.argv[1]))
idents = [c["identifier"] for c in d["candidates"]]
assert "MDZ-238" not in idents, "ticket must exclude itself: %r" % idents
assert idents.count("MDZ-100") == 1, "MDZ-100 must appear once (dup collapsed): %r" % idents
assert set(idents) == {"MDZ-100", "MDZ-101", "MDZ-102"}, idents
byid = {c["identifier"]: c for c in d["candidates"]}
# the ticket's spec URL is a shared identifier
assert "https://example.invalid/spec" in d["ticket_identifiers"], d["ticket_identifiers"]
assert "https://example.invalid/spec" in (byid["MDZ-100"].get("identifiers") or []), byid["MDZ-100"]
assert byid["MDZ-100"]["description_chars"] and byid["MDZ-100"]["excerpt"], byid["MDZ-100"]
assert d["bodies_fetched"] == 3, d
PY

# --- the body-read cap marks later candidates skipped, never fetched -------
RD2="$TMP/state2/linear-groom/MDZ-238"
stage_parts "$RD2"
for id in MDZ-100 MDZ-101 MDZ-102; do
  printf '{"result":{"issue":{"description":"body of %s"}}}\n' "$id" >"$RD2/.candidate-parts/body-$id.json"
done
LINEAR_GROOM_BODY_LIMIT=1 python3 "$CAND" --run-dir "$RD2" --ticket MDZ-238 >"$TMP/c2.out" 2>"$TMP/c2.err" \
  || fail "20-candidates failed with cap=1: $(cat "$TMP/c2.err")"
python3 - "$RD2/candidates.json" <<'PY' && ok "body cap: first fetched, rest marked excerpt_skipped" || fail "cap accounting wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["body_limit"] == 1, d
assert d["bodies_fetched"] == 1, d
assert d["bodies_skipped_by_cap"] == 2, d
past_cap = d["candidates"][1:]
assert all(c["excerpt"] is None and "excerpt_skipped" in c for c in past_cap), past_cap
PY

# --- an unreadable body degrades one candidate, never aborts the run -------
RD3="$TMP/state3/linear-groom/MDZ-238"
stage_parts "$RD3"
printf '{"result":{"issue":{"description":"fine"}}}\n' >"$RD3/.candidate-parts/body-MDZ-100.json"
printf 'get_issue MDZ-101 failed — description unavailable\n' >"$RD3/.candidate-parts/bodyerr-MDZ-101.txt"
printf '{"result":{"issue":{"description":"fine too"}}}\n' >"$RD3/.candidate-parts/body-MDZ-102.json"
python3 "$CAND" --run-dir "$RD3" --ticket MDZ-238 >"$TMP/c3.out" 2>"$TMP/c3.err" \
  || fail "20-candidates aborted on a single unreadable body: $(cat "$TMP/c3.err")"
python3 - "$RD3/candidates.json" <<'PY' && ok "an unreadable body is recorded per-candidate, not fatal" || fail "body-error accounting wrong"
import json, sys
d = json.load(open(sys.argv[1]))
byid = {c["identifier"]: c for c in d["candidates"]}
assert d["bodies_failed"] == 1, d
assert byid["MDZ-101"]["excerpt"] is None and "excerpt_error" in byid["MDZ-101"], byid["MDZ-101"]
assert d["bodies_fetched"] == 2, d
PY

# --- missing parts dir is a hard, explicit failure ------------------------
RD4="$TMP/state4/linear-groom/MDZ-238"
mkdir -p "$RD4"
cp "$HERE/fixtures/ticket-complete.json" "$RD4/ticket.json"
if python3 "$CAND" --run-dir "$RD4" --ticket MDZ-238 >"$TMP/c4.out" 2>"$TMP/c4.err"; then
  fail "20-candidates should fail when the parts dir is missing"
else
  grep -q "candidate parts" "$TMP/c4.err" && ok "missing parts dir fails loudly" \
    || fail "wrong error for missing parts: $(cat "$TMP/c4.err")"
fi

exit "$FAILED"
