#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"
RD="$TMP/state/linear-groom/MDZ-238"

dim() { # dim <name> <verdict> <confidence> <stance> <evidence-json> [reason] [dup]
  cat >"$RD/wave1/$1.json" <<EOF
{"dimension":"$1","verdict":"$2","confidence":"$3","deletion_stance":"$4",
 "delete_reason":${6:-null},"duplicate_of":${7:-null},
 "findings":[{"summary":"s","detail":"d"}],"evidence":$5}
EOF
}

reset() {
  rm -rf "$RD"; mkdir -p "$RD/wave1"
  cp "$HERE/fixtures/ticket-complete.json" "$RD/ticket.json"
  python3 "$ROOT/scripts/10-lint.py" --ticket "$RD/ticket.json" --out "$RD/gaps.json"
  printf '## 🎯 Contexto\n\nborrador\n' >"$TMP/draft.md"
}

verdict() { python3 -c "import json;print(json.load(open('$1'))['verdict'])"; }
blocked()  { python3 -c "import json;print(','.join(json.load(open('$1'))['safeguard']['blocked_by']))"; }

run() {
  python3 "$ROOT/scripts/40-synthesize.py" --ticket-id MDZ-238 \
    --draft "$TMP/draft.md" --triage-label needs-triage --out "$1" 2>"$TMP/syn.err"
}

EV='[{"kind":"commit","ref":"a1b2c3d","note":"fixed here"}]'
NOEV='[]'

# --- all four conditions met -> DELETE-CANDIDATE ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  ok               high neutral  "$NOEV"
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p1.json" || fail "synthesize failed: $(cat "$TMP/syn.err")"
[ "$(verdict "$TMP/p1.json")" = "DELETE-CANDIDATE" ] \
  && ok "emits DELETE-CANDIDATE when all four conditions hold" \
  || fail "got $(verdict "$TMP/p1.json")"

# --- condition 1: low confidence blocks ---
reset
dim veracity    delete-candidate low  supports "$EV" '"already-resolved"'
dim duplicates  ok               high neutral  "$NOEV"
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p2.json"
[ "$(verdict "$TMP/p2.json")" = "FIXABLE" ] && ok "low confidence degrades to FIXABLE" \
  || fail "got $(verdict "$TMP/p2.json")"
case "$(blocked "$TMP/p2.json")" in *confidence*) ok "names the confidence condition" ;;
  *) fail "blocked_by: $(blocked "$TMP/p2.json")" ;; esac

# --- condition 2: no evidence blocks ---
reset
dim veracity    delete-candidate high supports "$NOEV" '"obsolete"'
dim duplicates  ok               high neutral  "$NOEV"
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p3.json"
[ "$(verdict "$TMP/p3.json")" = "FIXABLE" ] && ok "missing evidence degrades to FIXABLE" \
  || fail "got $(verdict "$TMP/p3.json")"
case "$(blocked "$TMP/p3.json")" in *evidence*) ok "names the evidence condition" ;;
  *) fail "blocked_by: $(blocked "$TMP/p3.json")" ;; esac

# --- condition 3: an 'opposes' vote blocks ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  ok               high neutral  "$NOEV"
dim feasibility ok               high opposes  "$NOEV"
run "$TMP/p4.json"
[ "$(verdict "$TMP/p4.json")" = "FIXABLE" ] && ok "an opposing dimension degrades to FIXABLE" \
  || fail "got $(verdict "$TMP/p4.json")"
case "$(blocked "$TMP/p4.json")" in *opposes*) ok "names the opposing vote" ;;
  *) fail "blocked_by: $(blocked "$TMP/p4.json")" ;; esac

# --- condition 4: an UNAVAILABLE dimension blocks ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  ok               high neutral  "$NOEV"
printf 'codex died\n' >"$RD/wave1/feasibility.UNAVAILABLE"
run "$TMP/p5.json"
[ "$(verdict "$TMP/p5.json")" = "FIXABLE" ] \
  && ok "an UNAVAILABLE dimension degrades to FIXABLE" || fail "got $(verdict "$TMP/p5.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p5.json'))
sys.exit(0 if d['unavailable_dimensions']==['feasibility'] else 1)
" && ok "records the unavailable dimension" || fail "unavailable_dimensions wrong"

# --- READY: everything ok and no gaps ---
reset
dim veracity    ok high opposes "$NOEV"
dim duplicates  ok high neutral "$NOEV"
dim feasibility ok high opposes "$NOEV"
run "$TMP/p6.json"
[ "$(verdict "$TMP/p6.json")" = "READY" ] && ok "emits READY when nothing needs work" \
  || fail "got $(verdict "$TMP/p6.json")"

# --- READY must not rewrite the description ---
python3 -c "
import json,sys
d=json.load(open('$TMP/p6.json'))
sys.exit(0 if d['description_new'] is None and not d['labels_add'] else 1)
" && ok "READY proposes no description change and no labels" \
  || fail "READY proposed edits"

# --- a duplicate produces the relation with the right type ---
reset
dim veracity    ok               high neutral "$NOEV"
dim duplicates  delete-candidate high supports '[{"kind":"issue","ref":"MDZ-100","note":"same change"}]' '"duplicate"' '"MDZ-100"'
dim feasibility ok               high neutral "$NOEV"
run "$TMP/p7.json"
python3 -c "
import json,sys
d=json.load(open('$TMP/p7.json'))
sys.exit(0 if d['relations']==[{'type':'duplicate-of','related':'MDZ-100'}] else 1)
" && ok "duplicate yields a duplicate-of relation" \
  || fail "relations: $(python3 -c "import json;print(json.load(open('$TMP/p7.json'))['relations'])")"

# --- gaps alone are enough for FIXABLE ---
reset
cp "$HERE/fixtures/ticket-no-dod.json" "$RD/ticket.json"
python3 "$ROOT/scripts/10-lint.py" --ticket "$RD/ticket.json" --out "$RD/gaps.json"
dim veracity    ok high opposes "$NOEV"
dim duplicates  ok high neutral "$NOEV"
dim feasibility ok high opposes "$NOEV"
python3 "$ROOT/scripts/40-synthesize.py" --ticket-id MDZ-238 \
  --draft "$TMP/draft.md" --out "$TMP/p8.json" 2>/dev/null
[ "$(verdict "$TMP/p8.json")" = "FIXABLE" ] \
  && ok "a missing required section alone yields FIXABLE" || fail "got $(verdict "$TMP/p8.json")"

# --- two coherent proposers with different reasons: precedence picks 'duplicate' ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  delete-candidate high supports '[{"kind":"issue","ref":"MDZ-77","note":"same change"}]' '"duplicate"' '"MDZ-77"'
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p9.json" || fail "synthesize failed: $(cat "$TMP/syn.err")"
[ "$(verdict "$TMP/p9.json")" = "DELETE-CANDIDATE" ] \
  && ok "two coherent proposers still yield DELETE-CANDIDATE when all four conditions hold" \
  || fail "got $(verdict "$TMP/p9.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p9.json'))
sys.exit(0 if d['reason']=='duplicate' else 1)
" && ok "precedence selects 'duplicate' over 'already-resolved'" \
  || fail "reason: $(python3 -c "import json;print(json.load(open('$TMP/p9.json'))['reason'])")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p9.json'))
sys.exit(0 if d['relations']==[{'type':'duplicate-of','related':'MDZ-77'}] else 1)
" && ok "the precedence-selected proposer's duplicate_of becomes the relation" \
  || fail "relations: $(python3 -c "import json;print(json.load(open('$TMP/p9.json'))['relations'])")"

# --- the audit comment names every proposing dimension and its reason ---
python3 -c "
import json,sys
body=json.load(open('$TMP/p9.json'))['comments'][0]['body']
ok = 'veracity=already-resolved' in body and 'duplicates=duplicate' in body and \"Selected reason 'duplicate'\" in body
sys.exit(0 if ok else 1)
" && ok "the comment names both proposers, their reasons, and the selection" \
  || fail "comment did not record the disagreement: $(python3 -c "import json;print(json.load(open('$TMP/p9.json'))['comments'][0]['body'])")"

# --- 'duplicate' reason wins but duplicate_of is null: keep verdict, drop the relation, say so ---
reset
dim veracity    ok               high neutral  "$NOEV"
dim duplicates  delete-candidate high supports '[{"kind":"issue","ref":"MDZ-1","note":"looks the same"}]' '"duplicate"'
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p10.json" || fail "synthesize failed: $(cat "$TMP/syn.err")"
[ "$(verdict "$TMP/p10.json")" = "DELETE-CANDIDATE" ] \
  && ok "duplicate with a null duplicate_of keeps the DELETE-CANDIDATE verdict" \
  || fail "got $(verdict "$TMP/p10.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p10.json'))
ok = d['relations']==[] and 'needs-triage' in d['labels_add'] and \
     'no duplicate_of ticket was identified' in d['comments'][0]['body']
sys.exit(0 if ok else 1)
" && ok "no relation is fabricated and the comment says a human must find the ticket" \
  || fail "plan: $(cat "$TMP/p10.json")"

# --- delete-candidate with a non-supports stance is an incoherent answer, never a proposer ---
reset
dim veracity    delete-candidate high neutral "$EV" '"already-resolved"'
dim duplicates  ok               high neutral "$NOEV"
dim feasibility ok               high neutral "$NOEV"
run "$TMP/p11.json"
[ "$(verdict "$TMP/p11.json")" = "FIXABLE" ] \
  && ok "delete-candidate with a non-supports stance degrades to FIXABLE" \
  || fail "got $(verdict "$TMP/p11.json")"
case "$(blocked "$TMP/p11.json")" in *incoherent*) ok "names the incoherent self-contradiction" ;;
  *) fail "blocked_by: $(blocked "$TMP/p11.json")" ;; esac

# --- Important 1: an incoherent dimension blocks deletion even when a
# DIFFERENT, fully coherent dimension independently satisfies all four
# conditions. This is the case that actually exercises the incoherent-guard
# statement at evaluate_safeguard's top, not the coherent_proposers-empty
# early return (p11 above exercises the early return instead, since it has
# no other proposer). ---
reset
dim veracity    delete-candidate high neutral  "$EV" '"already-resolved"'
dim duplicates  delete-candidate high supports '[{"kind":"issue","ref":"MDZ-50","note":"dup"}]' '"duplicate"' '"MDZ-50"'
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p12.json"
[ "$(verdict "$TMP/p12.json")" = "FIXABLE" ] \
  && ok "an incoherent dimension blocks deletion even alongside a coherent qualifying proposer" \
  || fail "got $(verdict "$TMP/p12.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p12.json'))
sys.exit(0 if d['relations']==[] else 1)
" && ok "no relation is created when blocked by incoherence" \
  || fail "relations: $(python3 -c "import json;print(json.load(open('$TMP/p12.json'))['relations'])")"
case "$(blocked "$TMP/p12.json")" in *incoherent*) ok "blocked_by still names the incoherence" ;;
  *) fail "blocked_by: $(blocked "$TMP/p12.json")" ;; esac

# --- Important 2: blocked_by names every failed condition, not just the first ---
reset
dim veracity    delete-candidate low  supports "$NOEV" '"obsolete"'
dim duplicates  ok               high neutral  "$NOEV"
# feasibility.json intentionally absent -> unavailable, a second, independent failure
run "$TMP/p13.json"
[ "$(verdict "$TMP/p13.json")" = "FIXABLE" ] && ok "two simultaneous failures still degrade to FIXABLE" \
  || fail "got $(verdict "$TMP/p13.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p13.json'))['safeguard']['blocked_by']
sys.exit(0 if len(d) >= 2 else 1)
" && ok "blocked_by carries at least two entries for two simultaneous failures" \
  || fail "blocked_by: $(blocked "$TMP/p13.json")"
case "$(blocked "$TMP/p13.json")" in *confidence*) ok "names the confidence failure" ;;
  *) fail "blocked_by missing confidence: $(blocked "$TMP/p13.json")" ;; esac
case "$(blocked "$TMP/p13.json")" in *unavailable_dimensions*) ok "names the unavailable-dimension failure" ;;
  *) fail "blocked_by missing unavailable_dimensions: $(blocked "$TMP/p13.json")" ;; esac

# --- Important 3: marker-independence — no .UNAVAILABLE file at all, just an
# absent .json. Mirrors the condition-4 test (p5) exactly except that no
# marker is written; this is the only test that would catch a regression
# back to requiring the marker for a dimension to count as unavailable. ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  ok               high neutral  "$NOEV"
# feasibility.json absent, and — unlike the condition-4 test above — no
# .UNAVAILABLE marker is written either.
run "$TMP/p14.json"
python3 -c "
import json,sys
d=json.load(open('$TMP/p14.json'))
sys.exit(0 if d['unavailable_dimensions']==['feasibility'] else 1)
" && ok "an absent .json with no marker at all still counts as unavailable" \
  || fail "unavailable_dimensions: $(python3 -c "import json;print(json.load(open('$TMP/p14.json'))['unavailable_dimensions'])")"
[ "$(verdict "$TMP/p14.json")" = "FIXABLE" ] \
  && ok "the marker-independent unavailable dimension still yields FIXABLE" \
  || fail "got $(verdict "$TMP/p14.json")"

# --- Important 4: a blocked single proposal still tells the human why
# deletion was proposed (the reason and duplicate_of), not just that it was
# blocked. ---
reset
dim veracity    delete-candidate high supports '[{"kind":"issue","ref":"MDZ-9","note":"same change"}]' '"duplicate"' '"MDZ-9"'
dim duplicates  ok               high neutral "$NOEV"
dim feasibility ok               high opposes "$NOEV"
run "$TMP/p15.json"
[ "$(verdict "$TMP/p15.json")" = "FIXABLE" ] \
  && ok "a single proposer blocked by an opposing vote still yields FIXABLE" \
  || fail "got $(verdict "$TMP/p15.json")"
python3 -c "
import json,sys
body=json.load(open('$TMP/p15.json'))['comments'][0]['body']
sys.exit(0 if \"veracity proposed deletion for reason 'duplicate' (duplicate_of: MDZ-9)\" in body else 1)
" && ok "the blocked single-proposer comment states the proposed reason and duplicate_of" \
  || fail "comment: $(python3 -c "import json;print(json.load(open('$TMP/p15.json'))['comments'][0]['body'])")"

# --- Minor 3: on a blocked multi-proposer plan the comment says the reason
# WOULD HAVE BEEN selected, not that it was, since plan.json's reason is null ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  delete-candidate high supports '[{"kind":"issue","ref":"MDZ-5","note":"dup"}]' '"duplicate"' '"MDZ-5"'
dim feasibility ok               high opposes "$NOEV"
run "$TMP/p16.json"
[ "$(verdict "$TMP/p16.json")" = "FIXABLE" ] \
  && ok "two proposers blocked by an opposing vote still yield FIXABLE" \
  || fail "got $(verdict "$TMP/p16.json")"
python3 -c "
import json,sys
body=json.load(open('$TMP/p16.json'))['comments'][0]['body']
sys.exit(0 if \"Would have been selected reason 'duplicate'\" in body else 1)
" && ok "the blocked multi-proposer comment says 'would have been selected', not 'selected'" \
  || fail "comment: $(python3 -c "import json;print(json.load(open('$TMP/p16.json'))['comments'][0]['body'])")"

# --- Minor 5: the evidence list attributes each item to its dimension ---
python3 -c "
import json,sys
body=json.load(open('$TMP/p1.json'))['comments'][0]['body']
sys.exit(0 if '**veracity** — \`commit\` a1b2c3d' in body else 1)
" && ok "the evidence list names which dimension cited each item" \
  || fail "comment: $(python3 -c "import json;print(json.load(open('$TMP/p1.json'))['comments'][0]['body'])")"

# --- Minor 6: when every dimension is unavailable, refuse (exit 1) and
# write no plan file at all — the one non-zero exit in the script. ---
reset
python3 "$ROOT/scripts/40-synthesize.py" --ticket-id MDZ-238 \
  --draft "$TMP/draft.md" --triage-label needs-triage --out "$TMP/p17.json" 2>"$TMP/syn17.err"
rc=$?
[ "$rc" -eq 1 ] && ok "refuses with exit 1 when every dimension is unavailable" \
  || fail "exit code was $rc, expected 1"
[ ! -e "$TMP/p17.json" ] && ok "no plan file is written on the all-unavailable refusal" \
  || fail "a plan file was written despite the refusal"

# --- Ruling: READY with an unavailable dimension records analysis_incomplete
# and says so in the comment, without inventing a new verdict or proposing edits ---
reset
dim veracity    ok high neutral "$NOEV"
dim duplicates  ok high neutral "$NOEV"
# feasibility never ran: no .json, no marker.
run "$TMP/p18.json"
[ "$(verdict "$TMP/p18.json")" = "READY" ] \
  && ok "READY still applies when the missing dimension raised no issue" \
  || fail "got $(verdict "$TMP/p18.json")"
python3 -c "
import json,sys
d=json.load(open('$TMP/p18.json'))
ok = d['safeguard']['analysis_incomplete'] is True and \
     d['description_new'] is None and not d['labels_add']
sys.exit(0 if ok else 1)
" && ok "analysis_incomplete is set and READY still proposes no edits" \
  || fail "plan: $(cat "$TMP/p18.json")"
python3 -c "
import json,sys
body=json.load(open('$TMP/p18.json'))['comments'][0]['body']
sys.exit(0 if 'feasibility did not run, so this analysis is incomplete' in body else 1)
" && ok "the READY comment names the dimension that did not run" \
  || fail "comment: $(python3 -c "import json;print(json.load(open('$TMP/p18.json'))['comments'][0]['body'])")"

# --- delete-candidate + supports + high + hard evidence but NO delete_reason
# is incoherent too, not a qualifying proposal. Before this, such an output was
# schema-valid, satisfied all four conditions, and produced a plan condemning
# the ticket with reason null whose comment read "proposed deletion for reason
# 'None'". It must fail toward KEEPING the ticket. ---
reset
dim veracity    delete-candidate high supports "$EV"
dim duplicates  ok               high neutral  "$NOEV"
dim feasibility ok               high neutral  "$NOEV"
run "$TMP/p19.json"
[ "$(verdict "$TMP/p19.json")" = "FIXABLE" ] \
  && ok "delete-candidate with a missing delete_reason degrades to FIXABLE" \
  || fail "got $(verdict "$TMP/p19.json")"
case "$(blocked "$TMP/p19.json")" in *"delete_reason is missing"*) ok "blocked_by names the missing delete_reason" ;;
  *) fail "blocked_by: $(blocked "$TMP/p19.json")" ;; esac
python3 -c "
import json,sys
d=json.load(open('$TMP/p19.json'))
sys.exit(0 if d['reason'] is None and d['safeguard']['proposers']==[] \
         and d['safeguard']['incoherent_dimensions']==['veracity'] else 1)
" && ok "a reasonless delete-candidate is recorded as incoherent, never as a proposer" \
  || fail "safeguard: $(python3 -c "import json;print(json.load(open('$TMP/p19.json'))['safeguard'])")"

# --- residual mutation gap from Task 7: 'opposes' (condition 3) and
# 'unavailable_dimensions' (condition 4) failing SIMULTANEOUSLY. Without this
# case an if->elif slip confined to that adjacent pair would survive the
# suite, in the one file where an untested mutation costs a ticket. ---
reset
dim veracity    delete-candidate high supports "$EV" '"already-resolved"'
dim duplicates  ok               high opposes  "$NOEV"
# feasibility.json intentionally absent -> unavailable
run "$TMP/p20.json"
[ "$(verdict "$TMP/p20.json")" = "FIXABLE" ] \
  && ok "opposes and unavailable failing together still degrade to FIXABLE" \
  || fail "got $(verdict "$TMP/p20.json")"
case "$(blocked "$TMP/p20.json")" in *opposes*) ok "names the opposes failure in the adjacent pair" ;;
  *) fail "blocked_by missing opposes: $(blocked "$TMP/p20.json")" ;; esac
case "$(blocked "$TMP/p20.json")" in *unavailable_dimensions*) ok "names the unavailable failure in the adjacent pair" ;;
  *) fail "blocked_by missing unavailable_dimensions: $(blocked "$TMP/p20.json")" ;; esac

# =========================================================================
# Fix 3: the editor draft gate.
#
# The draft is copied VERBATIM into description_new and written to a real
# person's ticket. On the first live run the wave-2 editor leaked its own
# tool-call closing tags into draft.md and they reached the live ticket,
# because nothing here validated the editor's output at all — while the
# analysts' output was validated hard (JSON Schema, bounded retry,
# UNAVAILABLE). Exit 2, distinct from the exit 1 for all-dimensions-unavailable.
# =========================================================================

clean_dims() {
  dim veracity    ok high neutral "$NOEV"
  dim duplicates  ok high neutral "$NOEV"
  dim feasibility ok high neutral "$NOEV"
}

# reject <label> <expected-substring>  — draft.md must already be written
reject() {
  rm -f "$TMP/gate.json"
  run "$TMP/gate.json"
  local rc=$?
  [ "$rc" -eq 2 ] && ok "$1 exits 2" || fail "$1: expected 2, got $rc: $(cat "$TMP/syn.err")"
  [ ! -f "$TMP/gate.json" ] && ok "$1 writes no plan" || fail "$1 wrote a plan anyway"
  grep -qF -- "$2" "$TMP/syn.err" && ok "$1 names $2 in the error" \
    || fail "$1 error text: $(cat "$TMP/syn.err")"
}

reset; clean_dims
: >"$TMP/draft.md"
reject "an empty draft" "empty or whitespace-only"

reset; clean_dims
printf '   \n\t\n  \n' >"$TMP/draft.md"
reject "a whitespace-only draft" "empty or whitespace-only"

# The exact contamination observed live: the editor's own tool-call closing
# tags, appended after otherwise valid markdown.
reset; clean_dims
printf '## 🎯 Contexto\n\nborrador\n</content>\n</invoke>\n' >"$TMP/draft.md"
# The FIRST offending token in file order is the one reported — here
# </content> on line 4, not </invoke> on line 5.
reject "the live contamination incident" "</content>"
grep -q "line 4" "$TMP/syn.err" && ok "the contamination error names the line number" \
  || fail "no line number: $(cat "$TMP/syn.err")"
grep -qi "not stripping" "$TMP/syn.err" \
  && ok "the error says the markup is deliberately NOT stripped" \
  || fail "silent about stripping: $(cat "$TMP/syn.err")"

reset; clean_dims
printf '## 🎯 Contexto\n\n<invoke name="Write">\n' >"$TMP/draft.md"
reject "an opening tool-call tag" "<invoke"

reset; clean_dims
printf '## 🎯 Contexto\n\nborrador\n</content>\n' >"$TMP/draft.md"
reject "a stray closing content tag" "</content>"

reset; clean_dims
printf '## 🎯 Contexto\n\nborrador con antml:parameter dentro\n' >"$TMP/draft.md"
reject "the harness namespace prefix" "antml"

# A draft with no level-2 heading at all, when the template defines six, is a
# failed editor run (a refusal, an apology, a bare sentence) rather than a
# deliberate choice.
reset; clean_dims
printf 'I cannot help with that request.\n' >"$TMP/draft.md"
reject "a draft with no level-2 headings" "no level-2"

# ...and a clean draft is still accepted, so the gate is not simply refusing
# everything. This is the assertion that would fail if the gate were widened.
# needs-work on one dimension so the verdict is FIXABLE and the draft is
# actually used as description_new — a READY plan would carry a null one and
# the "nothing was stripped" assertion below would prove nothing.
reset
dim veracity    needs-work high neutral "$NOEV"
dim duplicates  ok         high neutral "$NOEV"
dim feasibility ok         high neutral "$NOEV"
printf '## 🎯 Contexto\n\nborrador limpio\n\n## ✅ Definition of Done (DoD)\n\n- algo\n' >"$TMP/draft.md"
rm -f "$TMP/gate2.json"
run "$TMP/gate2.json"
rc=$?
[ "$rc" -eq 0 ] && ok "a clean draft still passes the gate" \
  || fail "expected 0, got $rc: $(cat "$TMP/syn.err")"
[ -f "$TMP/gate2.json" ] && ok "a clean draft still produces a plan" || fail "no plan written"
python3 -c "
import json,sys
d = json.load(open('$TMP/gate2.json'))
sys.exit(0 if d['description_new'] == open('$TMP/draft.md').read() else 1)
" && ok "the accepted draft reaches description_new verbatim (nothing was stripped)" \
  || fail "description_new differs from the draft"

exit "$FAILED"
