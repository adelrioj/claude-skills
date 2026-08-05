#!/usr/bin/env bash
# Self-check for the per-task Codex effort tuning (docs/codex-tuning.md).
#
# Three things can break silently and are worth one assert each:
#   1. The two expansion forms. Review must resolve to xhigh with nothing set; build must vanish.
#   2. Every codex exec call site must carry an effort knob.
#   3. The dex provisioning jq must be additive (keeps every other key) and idempotent.
#
# Run: bash tests/check-codex-knob.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

review() { echo -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-xhigh}"; }
build()  { echo ${CODEX_EFFORT_BUILD:+-c model_reasoning_effort="$CODEX_EFFORT_BUILD"}; }

echo "1. shell expansion"
got="$(CODEX_EFFORT_REVIEW="" review)"
[ "$got" = "-c model_reasoning_effort=xhigh" ] && ok "review unset -> xhigh" || fail "review unset -> '$got'"
got="$(CODEX_EFFORT_REVIEW=medium review)"
[ "$got" = "-c model_reasoning_effort=medium" ] && ok "review set -> medium" || fail "review set -> '$got'"
got="$(CODEX_EFFORT_BUILD="" build)"
[ -z "$got" ] && ok "build unset -> empty (inherits config)" || fail "build unset -> '$got'"
got="$(CODEX_EFFORT_BUILD=low build)"
[ "$got" = "-c model_reasoning_effort=low" ] && ok "build set -> low" || fail "build set -> '$got'"

# A call site is a line that *starts* the command — in a SKILL.md that means a line inside a
# fenced bash block. Mid-sentence mentions (`a bare pgrep -fl 'codex exec'`) are prose, not
# commands, and anchoring to line-start is what separates the two. The forward window covers a
# backslash-continued invocation spread over several lines.
echo "2. every codex exec call site carries a knob"
sites=0
while IFS=: read -r file line _; do
  sites=$((sites + 1))
  sed -n "$((line > 2 ? line - 2 : 1)),$((line + 10))p" "$file" | grep -q 'CODEX_EFFORT_\(BUILD\|REVIEW\)\|model_reasoning_effort' \
    && ok "$file:$line" || fail "$file:$line has no effort knob nearby"
done < <(grep -rnE '^[[:space:]]*codex exec' skills/ --include='*.md' --include='*.sh' --include='*.js' | grep -v 'codex exec resume')
# Guard against the check quietly passing because it found nothing to check.
[ "$sites" -gt 0 ] && ok "$sites call site(s) scanned" || fail "no codex exec call sites found — the pattern has drifted"

echo "3. dex codex-xhigh provisioning is additive + idempotent"
if command -v jq >/dev/null; then
  cfg=$(mktemp)
  # a config with a user key that must survive, and a sibling clis entry
  echo '{"timeout":1200,"clis":{"codex":{"command":"codex","args":["exec"]}}}' > "$cfg"
  provision() {
    jq -e '.clis["codex-xhigh"]' "$1" >/dev/null 2>&1 || {
      t=$(mktemp)
      jq '.clis["codex-xhigh"] = {command:"codex", args:["exec","--yolo","--ephemeral","--json","-c","model_reasoning_effort=xhigh"], stdin:true, env:{}, output_format:"json_nd"}' \
        "$1" > "$t" && mv "$t" "$1" && echo provisioned
    }
  }
  [ "$(provision "$cfg")" = "provisioned" ] && ok "first run provisions" || fail "first run did not provision"
  jq -e '.timeout == 1200 and (.clis.codex.args == ["exec"])' "$cfg" >/dev/null \
    && ok "unrelated keys survive" || fail "provisioning clobbered unrelated keys"
  jq -e '.clis["codex-xhigh"].args | index("model_reasoning_effort=xhigh")' "$cfg" >/dev/null \
    && ok "entry carries the xhigh arg" || fail "entry missing the xhigh arg"
  # a user's own version must win
  jq '.clis["codex-xhigh"].mine = true' "$cfg" > "$cfg.2" && mv "$cfg.2" "$cfg"
  [ -z "$(provision "$cfg")" ] && jq -e '.clis["codex-xhigh"].mine' "$cfg" >/dev/null \
    && ok "second run is a no-op, user's version preserved" || fail "second run overwrote the entry"
  rm -f "$cfg"
else
  fail "jq not installed — cannot check provisioning"
fi

echo
[ "$fails" -eq 0 ] && { echo "all checks passed"; exit 0; }
echo "$fails check(s) failed"; exit 1
