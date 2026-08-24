#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

V="$ROOT/scripts/lib/validate.py"
S="$ROOT/schemas/wave1-veracity.json"

cat >"$TMP/good.json" <<'EOF'
{"dimension":"veracity","verdict":"delete-candidate","confidence":"high",
 "deletion_stance":"supports","delete_reason":"already-resolved","duplicate_of":null,
 "findings":[{"summary":"Already fixed","detail":"The fix landed in a1b2c3d."}],
 "evidence":[{"kind":"commit","ref":"a1b2c3d","note":"fix(cobol): header facts"}]}
EOF
python3 "$V" --schema "$S" --file "$TMP/good.json" 2>"$TMP/e1" \
  && ok "accepts a valid veracity payload" || fail "rejected valid: $(cat "$TMP/e1")"

# Same payload wrapped in a markdown fence.
{ printf '```json\n'; cat "$TMP/good.json"; printf '```\n'; } >"$TMP/fenced.json"
python3 "$V" --schema "$S" --file "$TMP/fenced.json" 2>"$TMP/e2" \
  && ok "tolerates a surrounding json fence" || fail "fenced rejected: $(cat "$TMP/e2")"

# Missing the required deletion_stance.
python3 -c "
import json
d=json.load(open('$TMP/good.json')); del d['deletion_stance']
json.dump(d, open('$TMP/nostance.json','w'))
"
python3 "$V" --schema "$S" --file "$TMP/nostance.json" 2>"$TMP/e3" \
  && fail "accepted payload with no deletion_stance" \
  || ok "requires deletion_stance"

# A hallucinated extra key must fail, not pass silently.
python3 -c "
import json
d=json.load(open('$TMP/good.json')); d['extraThought']='hmm'
json.dump(d, open('$TMP/extra.json','w'))
"
python3 "$V" --schema "$S" --file "$TMP/extra.json" 2>/dev/null \
  && fail "accepted an unknown property" || ok "rejects unknown properties"

# Wrong dimension for this schema.
python3 -c "
import json
d=json.load(open('$TMP/good.json')); d['dimension']='feasibility'
json.dump(d, open('$TMP/wrongdim.json','w'))
"
python3 "$V" --schema "$S" --file "$TMP/wrongdim.json" 2>/dev/null \
  && fail "accepted the wrong dimension" || ok "pins dimension per schema"

# Unparseable JSON is exit 2, distinct from schema-invalid.
printf 'not json at all' >"$TMP/junk.json"
python3 "$V" --schema "$S" --file "$TMP/junk.json" 2>/dev/null
[ $? -eq 2 ] && ok "unparseable JSON exits 2" || fail "expected exit 2 for junk"

# The other two schemas load and pin their own dimension.
for dim in duplicates feasibility; do
  python3 -c "
import json
d=json.load(open('$TMP/good.json')); d['dimension']='$dim'
json.dump(d, open('$TMP/$dim.json','w'))
"
  python3 "$V" --schema "$ROOT/schemas/wave1-$dim.json" --file "$TMP/$dim.json" 2>/dev/null \
    && ok "wave1-$dim.json accepts its own dimension" || fail "wave1-$dim.json rejected $dim"
done

exit "$FAILED"
