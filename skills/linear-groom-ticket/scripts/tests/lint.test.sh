#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

field() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))$2)" "$1"; }

# --- complete ticket: nothing required is missing ---
python3 "$ROOT/scripts/10-lint.py" \
  --ticket "$HERE/fixtures/ticket-complete.json" \
  --out "$TMP/gaps-complete.json" || fail "lint exited non-zero on complete ticket"
got="$(field "$TMP/gaps-complete.json" '["missing_required"]')"
[ "$got" = "[]" ] && ok "complete ticket has no missing required sections" \
  || fail "expected [] missing, got $got"
got="$(field "$TMP/gaps-complete.json" '["signals"]["dod_bullets"]')"
[ "$got" = "2" ] && ok "counts DoD bullets" || fail "dod_bullets: got $got want 2"
got="$(field "$TMP/gaps-complete.json" '["signals"]["link_count"]')"
[ "$got" = "1" ] && ok "counts links" || fail "link_count: got $got want 1"

# --- ticket missing DoD, with an empty User Story ---
python3 "$ROOT/scripts/10-lint.py" \
  --ticket "$HERE/fixtures/ticket-no-dod.json" \
  --out "$TMP/gaps-nodod.json" || fail "lint exited non-zero on incomplete ticket"
got="$(field "$TMP/gaps-nodod.json" '["missing_required"]')"
case "$got" in
  *"Definition of Done"*) ok "reports the absent DoD section" ;;
  *) fail "missing_required did not name the DoD: $got" ;;
esac
got="$(python3 -c "
import json,sys
d=json.load(open('$TMP/gaps-nodod.json'))
print([s['status'] for s in d['sections'] if s['key']=='userstory'][0])
")"
[ "$got" = "empty" ] && ok "a heading with no body is 'empty', not 'present'" \
  || fail "user story status: got '$got' want 'empty'"

# --- optional sections are never required ---
got="$(python3 -c "
import json
d=json.load(open('$TMP/gaps-nodod.json'))
print([s['required'] for s in d['sections'] if s['key']=='technicalnotes'][0])
")"
[ "$got" = "False" ] && ok "'<!-- optional -->' marks a section not required" \
  || fail "technical notes required: got '$got' want 'False'"

# --- the required set comes from the template file, not from code ---
cat >"$TMP/tiny-template.md" <<'EOF'
## Only This
Body.
EOF
python3 "$ROOT/scripts/10-lint.py" \
  --ticket "$HERE/fixtures/ticket-complete.json" \
  --template "$TMP/tiny-template.md" \
  --out "$TMP/gaps-tiny.json" || fail "lint failed with a custom template"
got="$(field "$TMP/gaps-tiny.json" '["missing_required"]')"
case "$got" in
  *"Only This"*) ok "required sections are read from the template file" ;;
  *) fail "custom template ignored: $got" ;;
esac

# --- the template is chosen by the ticket's type label ---
got="$(field "$TMP/gaps-complete.json" '["template"]')"
[ "$got" = "story.md" ] && ok "an unlabelled/Story ticket is linted against story.md" \
  || fail "template for a Story ticket: got '$got' want story.md"

python3 "$ROOT/scripts/10-lint.py" \
  --ticket "$HERE/fixtures/ticket-bug-labelled.json" \
  --out "$TMP/gaps-bug.json" || fail "lint exited non-zero on a Bug-labelled ticket"
got="$(field "$TMP/gaps-bug.json" '["template"]')"
[ "$got" = "bug.md" ] && ok "a Bug-labelled ticket is linted against bug.md" \
  || fail "template for a Bug ticket: got '$got' want bug.md"
got="$(field "$TMP/gaps-bug.json" '["missing_required"]')"
[ "$got" = "[]" ] && ok "a complete bug report satisfies bug.md" \
  || fail "expected [] missing for the bug fixture, got $got"

# A bug linted against the story template would report the story sections as gaps.
# This is the regression that matters: it is what a mis-selected template looks like.
got="$(python3 -c "
import json
d=json.load(open('$TMP/gaps-bug.json'))
print(sorted(s['key'] for s in d['sections']))
")"
case "$got" in
  *acceptancecriteria*) fail "bug ticket was linted against the story template: $got" ;;
  *summary*) ok "bug sections, not story sections, are the ones measured" ;;
  *) fail "unexpected section set for a bug: $got" ;;
esac

# --- the templates live in the to-linear skill, and this path must not rot ---
for tpl in bug.md story.md; do
  [ -f "$ROOT/../to-linear/templates/$tpl" ] \
    && ok "shared template exists: to-linear/templates/$tpl" \
    || fail "missing shared template: to-linear/templates/$tpl"
done

exit "$FAILED"
