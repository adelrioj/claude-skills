#!/usr/bin/env bash
# Self-check for the per-task Codex effort tuning (docs/codex-tuning.md).
#
# Four things can break silently and are worth one assert each:
#   1. The two expansion forms. Review must resolve to xhigh with nothing set; build must vanish.
#   2. The two dex backend forms, which resolve three-way (explicit entry > effort word > default).
#      The default row is the one that matters: a regression here silently re-tiers every pipeline.
#   3. Every codex exec call site must carry an effort knob.
#   4. The dex provisioning jq must be additive (keeps every other key) and idempotent, for any
#      codex-<effort> name — and must refuse to invent an entry for a name it did not derive.
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

# The dex phases have no effort flag, so their knob picks a *clis entry name* instead. Three-way:
# an explicitly named entry wins, else an effort word becomes codex-<effort>, else the default.
applycli()  { echo "${DEX_CLI_BUILD:-codex${CODEX_EFFORT_BUILD:+-$CODEX_EFFORT_BUILD}}"; }
reviewcli() { echo "${DEX_CLI_REVIEW:-codex-${CODEX_EFFORT_REVIEW:-xhigh}}"; }

echo "2. dex backend resolution"
got="$(applycli)"
[ "$got" = "codex" ] && ok "apply default -> codex (inherits config)" || fail "apply default -> '$got'"
got="$(reviewcli)"
[ "$got" = "codex-xhigh" ] && ok "review default -> codex-xhigh" || fail "review default -> '$got'"
got="$(CODEX_EFFORT_BUILD=low applycli)"
[ "$got" = "codex-low" ] && ok "build effort -> codex-low" || fail "build effort -> '$got'"
got="$(CODEX_EFFORT_REVIEW=high reviewcli)"
[ "$got" = "codex-high" ] && ok "review effort -> codex-high" || fail "review effort -> '$got'"
got="$(DEX_CLI_BUILD=mine CODEX_EFFORT_BUILD=low applycli)"
[ "$got" = "mine" ] && ok "explicit entry beats effort word" || fail "explicit entry -> '$got'"
# Every derived name must keep the codex- prefix: the live-worker guard greps 'dex --cli codex',
# so a derived name that lost the prefix would make the guard blind to its own worker.
for e in low medium high xhigh; do
  case "$(CODEX_EFFORT_BUILD=$e applycli)$(CODEX_EFFORT_REVIEW=$e reviewcli)" in
    codex-*codex-*) ;; *) fail "derived name for '$e' lost the codex- prefix" ;;
  esac
done
ok "derived names keep the codex- prefix (guard stays sighted)"

# A call site is a line that *starts* the command — in a SKILL.md that means a line inside a
# fenced bash block. Mid-sentence mentions (`a bare pgrep -fl 'codex exec'`) are prose, not
# commands, and anchoring to line-start is what separates the two. The forward window covers a
# backslash-continued invocation spread over several lines.
echo "3. every codex exec call site carries a knob"
sites=0
while IFS=: read -r file line _; do
  sites=$((sites + 1))
  sed -n "$((line > 2 ? line - 2 : 1)),$((line + 10))p" "$file" | grep -q 'CODEX_EFFORT_\(BUILD\|REVIEW\)\|model_reasoning_effort' \
    && ok "$file:$line" || fail "$file:$line has no effort knob nearby"
done < <(grep -rnE '^[[:space:]]*codex exec' skills/ --include='*.md' --include='*.sh' --include='*.js' | grep -v 'codex exec resume')
# Guard against the check quietly passing because it found nothing to check.
[ "$sites" -gt 0 ] && ok "$sites call site(s) scanned" || fail "no codex exec call sites found — the pattern has drifted"

# A skill types the fragment at several sites (the command, the poll-loop re-run, the confirmation
# display). Updating some and missing others is the actual drift that happened once: the re-run
# commands kept an older two-way form, so a retiered run would silently revert on every retry.
echo "4. every dex backend resolution in skills/ uses the canonical fragment"
# Selector is `DEX_CLI_*:-codex` — that is what a *resolution* looks like. It excludes prose
# mentions (bare `$DEX_CLI_BUILD`) and ship-it's validation loop (`${DEX_CLI_BUILD:-}`, empty
# default), both of which legitimately do not resolve a backend name.
dexsites=0
while IFS=: read -r file line text; do
  dexsites=$((dexsites + 1))
  case "$text" in
    *'${DEX_CLI_BUILD:-codex${CODEX_EFFORT_BUILD:+-$CODEX_EFFORT_BUILD}}'* \
    |*'${DEX_CLI_REVIEW:-codex-${CODEX_EFFORT_REVIEW:-xhigh}}'*) ok "$file:$line" ;;
    *) fail "$file:$line uses a stale/partial dex backend fragment" ;;
  esac
done < <(grep -rnE 'DEX_CLI_(BUILD|REVIEW):-codex' skills/ --include='*.md' --include='*.sh')
[ "$dexsites" -gt 0 ] && ok "$dexsites resolution site(s) scanned" || fail "no dex resolution sites found — the pattern has drifted"

echo "5. dex codex-<effort> provisioning is additive + idempotent + allowlisted"
if command -v jq >/dev/null; then
  cfg=$(mktemp)
  # a config with a user key that must survive, and a sibling clis entry
  echo '{"timeout":1200,"clis":{"codex":{"command":"codex","args":["exec"]}}}' > "$cfg"
  # Mirrors Step 4 of plan-to-dex: same allowlist, same jq, one name per call.
  provision() {
    case "$2" in codex-low|codex-medium|codex-high|codex-xhigh) ;; *) return ;; esac
    jq -e --arg c "$2" '.clis[$c]' "$1" >/dev/null 2>&1 || {
      t=$(mktemp)
      jq --arg c "$2" --arg e "${2#codex-}" \
        '.clis[$c] = {command:"codex", args:["exec","--yolo","--ephemeral","--json","-c","model_reasoning_effort=\($e)"], stdin:true, env:{}, output_format:"json_nd"}' \
        "$1" > "$t" && mv "$t" "$1" && echo provisioned
    }
  }
  [ "$(provision "$cfg" codex-xhigh)" = "provisioned" ] && ok "first run provisions" || fail "first run did not provision"
  jq -e '.timeout == 1200 and (.clis.codex.args == ["exec"])' "$cfg" >/dev/null \
    && ok "unrelated keys survive" || fail "provisioning clobbered unrelated keys"
  jq -e '.clis["codex-xhigh"].args | index("model_reasoning_effort=xhigh")' "$cfg" >/dev/null \
    && ok "entry carries the xhigh arg" || fail "entry missing the xhigh arg"
  # the effort in the args must track the name, not be hardcoded
  provision "$cfg" codex-low >/dev/null
  jq -e '.clis["codex-low"].args | index("model_reasoning_effort=low")' "$cfg" >/dev/null \
    && ok "codex-low carries the low arg" || fail "codex-low args do not track its name"
  # a name this skill never derives must NOT be invented — a typo'd $DEX_CLI_* has to surface
  provision "$cfg" my-entry >/dev/null
  provision "$cfg" codex-fastest >/dev/null
  jq -e '(.clis | has("my-entry") or has("codex-fastest")) | not' "$cfg" >/dev/null \
    && ok "non-allowlisted names are refused" || fail "provisioned an entry it should not invent"
  # a user's own version must win
  jq '.clis["codex-xhigh"].mine = true' "$cfg" > "$cfg.2" && mv "$cfg.2" "$cfg"
  [ -z "$(provision "$cfg" codex-xhigh)" ] && jq -e '.clis["codex-xhigh"].mine' "$cfg" >/dev/null \
    && ok "second run is a no-op, user's version preserved" || fail "second run overwrote the entry"
  rm -f "$cfg"
else
  fail "jq not installed — cannot check provisioning"
fi

echo
[ "$fails" -eq 0 ] && { echo "all checks passed"; exit 0; }
echo "$fails check(s) failed"; exit 1
