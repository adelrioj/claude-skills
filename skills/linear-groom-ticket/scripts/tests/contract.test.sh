#!/bin/bash
# Asserts that every file and flag SKILL.md documents actually exists.
# Cheap protection against SKILL.md drifting away from the scripts.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FAILED=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

for f in \
  SKILL.md reference/stopwords.txt \
  prompts/veracity.md prompts/duplicates.md prompts/feasibility.md prompts/editor.md \
  schemas/wave1-veracity.json schemas/wave1-duplicates.json \
  schemas/wave1-feasibility.json schemas/plan.json \
  scripts/10-lint.py scripts/20-candidates.py \
  scripts/30-wave1.sh scripts/40-synthesize.py \
  scripts/lib/common.sh scripts/lib/jsonutil.py scripts/lib/validate.py \
  scripts/lib/repocheck.py scripts/lib/keywords.py scripts/lib/identifiers.py scripts/lib/entitled.py
do
  [ -f "$ROOT/$f" ] && ok "exists: $f" || fail "missing: $f"
done

# The ticket templates are owned by the to-linear skill and read from there —
# this skill deliberately ships none of its own, so that a ticket is linted
# against the same shape it was filed with. A moved or renamed template is a
# silent "every section is missing" verdict, so the path is asserted here too.
for f in templates/bug.md templates/story.md
do
  [ -f "$ROOT/../to-linear/$f" ] && ok "exists: to-linear/$f" \
    || fail "missing: to-linear/$f"
done

# The skill's prose doc. In this plugin a skill ships no README of its own —
# none of its sibling skills do — and the per-skill detail lives at the plugin
# root instead, which CLAUDE.md points at as the thing to read before touching
# a skill. So this asserts the doc that convention actually requires, at the
# path the convention puts it. (Before this skill moved into the plugin it
# checked for a sibling README.md, which is why that name may still appear in
# the standalone repo's history.)
DOC="$ROOT/../../docs/skills/linear-groom-ticket.md"
[ -f "$DOC" ] && ok "exists: docs/skills/linear-groom-ticket.md (plugin root)" \
  || fail "missing docs/skills/linear-groom-ticket.md at the plugin root"

# The stub notice must be gone.
grep -q "NOT YET IMPLEMENTED" "$ROOT/SKILL.md" \
  && fail "SKILL.md still carries the NOT YET IMPLEMENTED stub notice" \
  || ok "stub notice removed from SKILL.md"

# Every script path SKILL.md mentions must exist. Matches both bare
# "scripts/xxx.sh" and nested "scripts/tests/xxx.sh" references.
grep -o -E 'scripts(/[0-9a-zA-Z_-]+)*\.(sh|py)' "$ROOT/SKILL.md" | sort -u | while read -r path; do
  [ -f "$ROOT/$path" ] || { printf '  FAIL SKILL.md references missing %s\n' "$path"; exit 1; }
done || FAILED=1

# The approval gate must be documented — this skill must never write unprompted.
grep -q -i "approval gate" "$ROOT/SKILL.md" && ok "SKILL.md documents the approval gate" \
  || fail "SKILL.md does not mention the approval gate"

# The transport is the Linear MCP now, not orca. SKILL.md must not reach for the
# local orca CLI anywhere — a single `orca` mention is a regression back to the
# removed, machine-specific pipeline.
if grep -q -i -E '\borca\b' "$ROOT/SKILL.md"; then
  printf '  FAIL SKILL.md still mentions orca; the transport is the Linear MCP\n'
  grep -n -i -E '\borca\b' "$ROOT/SKILL.md" | sed 's/^/    /'
  FAILED=1
else
  ok "SKILL.md never mentions orca (Linear I/O goes through the MCP)"
fi

# And it must name the Linear MCP as the transport, so a reader knows where the
# writes actually go.
grep -q -i "linear mcp" "$ROOT/SKILL.md" \
  && ok "SKILL.md names the Linear MCP as the transport" \
  || fail "SKILL.md does not name the Linear MCP"

# --- prompt <-> schema key-set coherence ------------------------------------
# Each prompts/<dim>.md embeds a JSON skeleton the model is told to fill in,
# and schemas/wave1-<dim>.json validates what comes back. Nothing binds the
# two. Rename a field in one and not the other and the only symptom is a real
# run burning two codex calls for that dimension and reporting UNAVAILABLE —
# an environment-shaped failure with a content cause, which is the worst kind
# to debug. This asserts the skeleton's key set equals the schema's, at the
# top level and inside the findings/evidence item objects.
for dim in veracity duplicates feasibility; do
  if python3 - "$ROOT/prompts/$dim.md" "$ROOT/schemas/wave1-$dim.json" <<'PY'
import json, sys

prompt = open(sys.argv[1]).read()
schema = json.load(open(sys.argv[2]))
start = prompt.index('{"dimension"')
skeleton, _ = json.JSONDecoder().raw_decode(prompt[start:])

def compare(label, got, want):
    if set(got) == set(want):
        return True
    sys.stderr.write(
        "%s: prompt has %s, schema declares %s\n"
        % (label, sorted(set(got)), sorted(set(want)))
    )
    return False

props = schema["properties"]
good = compare("top level", skeleton, props)
for field in ("findings", "evidence"):
    item_props = props[field]["items"]["properties"]
    good = compare(field + " item", skeleton[field][0], item_props) and good
sys.exit(0 if good else 1)
PY
  then
    ok "prompts/$dim.md's JSON skeleton matches schemas/wave1-$dim.json's key set"
  else
    fail "prompts/$dim.md and schemas/wave1-$dim.json disagree on the key set"
  fi
done

exit "$FAILED"
