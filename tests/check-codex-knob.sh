#!/usr/bin/env bash
# Self-check for the per-task Codex model + effort tuning (docs/codex-tuning.md).
#
# Five things can break silently and are worth one assert each:
#   1. The direct-codex fragments. Both slots pin a model AND an effort; a regression that drops
#      the -m silently reverts the slot to whatever ~/.codex/config.toml says.
#   2. The two dex backend forms, which resolve three-way (explicit entry > model+effort > default).
#      The default row is the one that matters: a regression here silently re-tiers every pipeline.
#   3. Every codex exec call site must carry both knobs.
#   4. Every dex resolution site must use the identical fragment — partial updates are the drift
#      that actually happened once (the poll-loop re-runs kept an older form).
#   5. The dex provisioning jq must be additive (keeps every other key), idempotent, carry the
#      model+effort it was named for, and refuse a model/effort pair this account cannot run.
#
# Run: bash tests/check-codex-knob.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

review() { echo -m "${CODEX_MODEL_REVIEW:-gpt-5.6-sol}" -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-high}"; }
build()  { echo -m "${CODEX_MODEL_BUILD:-gpt-5.6-luna}" -c model_reasoning_effort="${CODEX_EFFORT_BUILD:-high}"; }

echo "1. direct-codex fragments"
got="$(review)"
[ "$got" = "-m gpt-5.6-sol -c model_reasoning_effort=high" ] && ok "review default -> sol @ high" || fail "review default -> '$got'"
got="$(build)"
[ "$got" = "-m gpt-5.6-luna -c model_reasoning_effort=high" ] && ok "build default -> luna @ high" || fail "build default -> '$got'"
got="$(CODEX_EFFORT_REVIEW=xhigh review)"
[ "$got" = "-m gpt-5.6-sol -c model_reasoning_effort=xhigh" ] && ok "review effort override" || fail "review effort override -> '$got'"
got="$(CODEX_MODEL_BUILD=gpt-5.6-terra build)"
[ "$got" = "-m gpt-5.6-terra -c model_reasoning_effort=high" ] && ok "build model override" || fail "build model override -> '$got'"

# The dex phases have neither a --model nor an effort flag, so their knob picks a *clis entry name*
# that carries both. Three-way: an explicitly named entry wins, else codex-<model>-<effort>.
applycli()  { echo "${DEX_CLI_BUILD:-codex-${CODEX_MODEL_BUILD:-gpt-5.6-luna}-${CODEX_EFFORT_BUILD:-high}}"; }
reviewcli() { echo "${DEX_CLI_REVIEW:-codex-${CODEX_MODEL_REVIEW:-gpt-5.6-sol}-${CODEX_EFFORT_REVIEW:-high}}"; }

echo "2. dex backend resolution"
got="$(applycli)"
[ "$got" = "codex-gpt-5.6-luna-high" ] && ok "apply default -> codex-gpt-5.6-luna-high" || fail "apply default -> '$got'"
got="$(reviewcli)"
[ "$got" = "codex-gpt-5.6-sol-high" ] && ok "review default -> codex-gpt-5.6-sol-high" || fail "review default -> '$got'"
got="$(CODEX_EFFORT_BUILD=xhigh applycli)"
[ "$got" = "codex-gpt-5.6-luna-xhigh" ] && ok "build effort -> luna-xhigh" || fail "build effort -> '$got'"
got="$(CODEX_MODEL_REVIEW=gpt-5.6-terra reviewcli)"
[ "$got" = "codex-gpt-5.6-terra-high" ] && ok "review model -> terra-high" || fail "review model -> '$got'"
got="$(DEX_CLI_BUILD=mine CODEX_EFFORT_BUILD=low applycli)"
[ "$got" = "mine" ] && ok "explicit entry beats model+effort" || fail "explicit entry -> '$got'"
# Every derived name must keep the codex- prefix: the live-worker guard greps 'dex --cli codex',
# so a derived name that lost the prefix would make the guard blind to its own worker.
for e in low medium high xhigh max; do
  case "$(CODEX_EFFORT_BUILD=$e applycli)$(CODEX_EFFORT_REVIEW=$e reviewcli)" in
    codex-*codex-*) ;; *) fail "derived name for '$e' lost the codex- prefix" ;;
  esac
done
ok "derived names keep the codex- prefix (guard stays sighted)"

# A call site is a line that *starts* the command — in a SKILL.md that means a line inside a
# fenced bash block. Mid-sentence mentions (`a bare pgrep -fl 'codex exec'`) are prose, not
# commands, and anchoring to line-start is what separates the two. The forward window covers a
# backslash-continued invocation spread over several lines.
echo "3. every codex exec call site pins model AND effort"
sites=0
while IFS=: read -r file line _; do
  sites=$((sites + 1))
  window="$(sed -n "$((line > 2 ? line - 2 : 1)),$((line + 10))p" "$file")"
  if echo "$window" | grep -q 'CODEX_MODEL_\(BUILD\|REVIEW\)' && echo "$window" | grep -q 'CODEX_EFFORT_\(BUILD\|REVIEW\)'; then
    ok "$file:$line"
  else
    fail "$file:$line is missing a model or effort knob"
  fi
done < <(grep -rnE '^[[:space:]]*codex exec' skills/ --include='*.md' --include='*.sh' --include='*.js' | grep -v 'codex exec resume')
# Guard against the check quietly passing because it found nothing to check.
[ "$sites" -gt 0 ] && ok "$sites call site(s) scanned" || fail "no codex exec call sites found — the pattern has drifted"

echo "4. every dex backend resolution in skills/ uses the canonical fragment"
# Selector is `DEX_CLI_*:-codex` — that is what a *resolution* looks like. It excludes prose
# mentions (bare `$DEX_CLI_BUILD`) and ship-it's validation loop (`${DEX_CLI_BUILD:-}`, empty
# default), both of which legitimately do not resolve a backend name.
dexsites=0
while IFS=: read -r file line text; do
  dexsites=$((dexsites + 1))
  case "$text" in
    *'${DEX_CLI_BUILD:-codex-${CODEX_MODEL_BUILD:-gpt-5.6-luna}-${CODEX_EFFORT_BUILD:-high}}'* \
    |*'${DEX_CLI_REVIEW:-codex-${CODEX_MODEL_REVIEW:-gpt-5.6-sol}-${CODEX_EFFORT_REVIEW:-high}}'*) ok "$file:$line" ;;
    *) fail "$file:$line uses a stale/partial dex backend fragment" ;;
  esac
done < <(grep -rnE 'DEX_CLI_(BUILD|REVIEW):-codex' skills/ --include='*.md' --include='*.sh')
[ "$dexsites" -gt 0 ] && ok "$dexsites resolution site(s) scanned" || fail "no dex resolution sites found — the pattern has drifted"

echo "5. dex provisioning: additive, idempotent, entitlement-gated"
if command -v jq >/dev/null; then
  cfg=$(mktemp); mc=$(mktemp)
  # a config with a user key that must survive, and a sibling clis entry
  echo '{"timeout":1200,"clis":{"codex":{"command":"codex","args":["exec"]}}}' > "$cfg"
  # a stand-in models_cache.json: luna stops at high, sol goes further
  echo '{"models":[{"slug":"gpt-5.6-luna","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},
                   {"slug":"gpt-5.6-sol","supported_reasoning_levels":[{"effort":"high"},{"effort":"ultra"}]}]}' > "$mc"
  # Mirrors Step 4 of plan-to-dex: same entitlement gate, same jq. $1=cfg $2=cache $3=model $4=effort
  provision() {
    local cli="codex-$3-$4"
    if [ -s "$2" ] && ! jq -e --arg m "$3" --arg e "$4" \
         '.models[] | select(.slug==$m) | [.supported_reasoning_levels[].effort] | index($e)' "$2" >/dev/null 2>&1; then
      echo unavailable; return
    fi
    jq -e --arg c "$cli" '.clis[$c]' "$1" >/dev/null 2>&1 || {
      t=$(mktemp)
      jq --arg c "$cli" --arg m "$3" --arg e "$4" \
        '.clis[$c] = {command:"codex", args:["exec","--yolo","--ephemeral","--json","-m",$m,"-c","model_reasoning_effort=\($e)"], stdin:true, env:{}, output_format:"json_nd"}' \
        "$1" > "$t" && mv "$t" "$1" && echo provisioned
    }
  }
  [ "$(provision "$cfg" "$mc" gpt-5.6-sol high)" = "provisioned" ] && ok "first run provisions" || fail "first run did not provision"
  jq -e '.timeout == 1200 and (.clis.codex.args == ["exec"])' "$cfg" >/dev/null \
    && ok "unrelated keys survive" || fail "provisioning clobbered unrelated keys"
  # the model and effort in args must track the name, not be hardcoded
  provision "$cfg" "$mc" gpt-5.6-luna high >/dev/null
  jq -e '.clis["codex-gpt-5.6-luna-high"].args as $a
         | ($a | index("gpt-5.6-luna")) and ($a | index("model_reasoning_effort=high"))' "$cfg" >/dev/null \
    && ok "entry args carry its own model + effort" || fail "entry args do not track its name"
  jq -e '.clis["codex-gpt-5.6-sol-high"].args | index("gpt-5.6-sol")' "$cfg" >/dev/null \
    && ok "sibling entry keeps its own model" || fail "sibling entry has the wrong model"
  # a pair this account cannot run must be refused, and must not be written
  [ "$(provision "$cfg" "$mc" gpt-5.6-luna ultra)" = "unavailable" ] \
    && ok "unsupported effort for that model is refused" || fail "provisioned luna@ultra, which the cache forbids"
  [ "$(provision "$cfg" "$mc" gpt-9-nope high)" = "unavailable" ] \
    && ok "unentitled model is refused" || fail "provisioned an unentitled model"
  jq -e '(.clis | has("codex-gpt-5.6-luna-ultra") or has("codex-gpt-9-nope-high")) | not' "$cfg" >/dev/null \
    && ok "refused pairs write nothing" || fail "a refused pair still landed in the config"
  # an absent cache must not block a machine whose model is fine (the file is a cache, not truth)
  [ "$(provision "$cfg" /nonexistent gpt-9-nope high)" = "provisioned" ] \
    && ok "absent cache skips the gate, does not fail it" || fail "absent cache blocked provisioning"
  # a user's own version must win
  jq '.clis["codex-gpt-5.6-sol-high"].mine = true' "$cfg" > "$cfg.2" && mv "$cfg.2" "$cfg"
  [ -z "$(provision "$cfg" "$mc" gpt-5.6-sol high)" ] && jq -e '.clis["codex-gpt-5.6-sol-high"].mine' "$cfg" >/dev/null \
    && ok "second run is a no-op, user's version preserved" || fail "second run overwrote the entry"
  rm -f "$cfg" "$mc"
else
  fail "jq not installed — cannot check provisioning"
fi

echo "6. the pinned defaults are entitled on THIS machine (advisory)"
MC="$HOME/.codex/models_cache.json"
if [ -s "$MC" ] && command -v jq >/dev/null; then
  for pair in "gpt-5.6-luna high" "gpt-5.6-sol high"; do
    m="${pair% *}"; e="${pair#* }"
    jq -e --arg m "$m" --arg e "$e" '.models[] | select(.slug==$m) | [.supported_reasoning_levels[].effort] | index($e)' \
      "$MC" >/dev/null 2>&1 && ok "$m @ $e entitled" \
      || fail "$m @ $e NOT entitled here — entitled: $(jq -r '[.models[].slug] | join(", ")' "$MC")"
  done
else
  ok "no models_cache.json — skipped (cold cache is not a failure)"
fi

echo
[ "$fails" -eq 0 ] && { echo "all checks passed"; exit 0; }
echo "$fails check(s) failed"; exit 1
