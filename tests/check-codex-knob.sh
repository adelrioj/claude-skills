#!/usr/bin/env bash
# Self-check for the per-task Codex model + effort tuning (docs/codex-tuning.md).
#
# Six things can break silently and are worth one assert each:
#   1. The direct-codex fragments. Both slots pin a model AND an effort; a regression that drops
#      the -m silently reverts the slot to whatever ~/.codex/config.toml says.
#   2. The two dex backend forms, which resolve three-way (explicit entry > model+effort > default).
#      The default row is the one that matters: a regression here silently re-tiers every pipeline.
#   3. Every codex exec call site must carry both knobs.
#   4. Every dex resolution site must use the identical fragment — partial updates are the drift
#      that actually happened once (the poll-loop re-runs kept an older form).
#   5. The dex provisioning jq must be additive (keeps every other key), idempotent, carry the
#      model+effort it was named for, and refuse a model/effort pair this account cannot run.
#   6. The linear-triage-ticket skill's embedded runtime: the watchdog/retry/read contracts as
#      text, plus both embedded python blocks compiled and exercised for real (watchdog timeout
#      + exit passthrough, validator exit taxonomy + C5 normalisation). Section "3b" below.
#
# Run: bash tests/check-codex-knob.sh

# The ok/fail helpers always return zero, so these compact checks are true
# if/else expressions; several grep patterns intentionally contain literal `$`.
# shellcheck disable=SC2015,SC2016
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
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
# The scan result is captured rather than piped straight into the loop, because
# the checks below must interrogate WHAT THE SCAN MATCHED. Asserting against the
# source files instead would prove only that a call site exists in the repo, and
# would keep saying ok while the scan pattern quietly stopped matching it.
VAR_FORM='^[[:space:]]*"?\$\{?[A-Za-z_]*CODEX[A-Za-z0-9_]*\}?"? exec'
scan="$(grep -rnE "$VAR_FORM"'|^[[:space:]]*codex exec' \
          skills/ --include='*.md' --include='*.sh' --include='*.js' | grep -v 'codex exec resume')"
sites=0
while IFS=: read -r file line _; do
  [ -n "${file:-}" ] || continue
  sites=$((sites + 1))
  window="$(sed -n "$((line > 2 ? line - 2 : 1)),$((line + 10))p" "$file")"
  if echo "$window" | grep -q 'CODEX_MODEL_\(BUILD\|REVIEW\)' && echo "$window" | grep -q 'CODEX_EFFORT_\(BUILD\|REVIEW\)'; then
    ok "$file:$line"
  else
    fail "$file:$line is missing a model or effort knob"
  fi
done <<EOF
$scan
EOF
# Guard against the check quietly passing because it found nothing to check.
[ "$sites" -gt 0 ] && ok "$sites call site(s) scanned" || fail "no codex exec call sites found — the pattern has drifted"
# A literal `codex exec` is not the only way to start codex. A script that
# invokes it through a variable — `"$LINEAR_GROOM_CODEX" exec`, the indirection
# that lets a test suite substitute a double — was invisible to this scan until
# the variable form was added to the pattern, so section 3 passed while
# reporting one call site and skipping another.
#
# This asserts against `$scan`, i.e. against what the pattern actually matched.
# An earlier version of this check grepped the source tree instead, and stayed
# green through a mutation that narrowed the pattern back — a check that passed
# by a different route than the one it was written to protect. Narrow the
# pattern now and this goes red.
#
# Known and accepted hole: the variable must have CODEX in its name. That is
# what keeps the pattern from flagging every other `"\$SOMETHING" exec` in the
# repo as a codex site, and it means a variable named \`\$CLI\` would still escape.
if printf '%s\n' "$scan" | grep -qE "^[^:]+:[0-9]+:$(printf '%s' "$VAR_FORM" | sed 's/^\^//')"; then
  ok "the scan matched a variable-invoked codex call site"
else
  fail "the scan matched no variable-invoked call site — the pattern narrowed, or the last such call site left the repo"
fi

echo "3b. linear-triage-ticket: embedded watchdog/validator contract"
TRIAGE_SKILL="skills/linear-triage-ticket/SKILL.md"
if grep -q 'start_new_session=True' "$TRIAGE_SKILL" \
   && grep -q 'process.wait(timeout=timeout)' "$TRIAGE_SKILL" \
   && grep -q 'os.killpg(process.pid, signal.SIGTERM)' "$TRIAGE_SKILL" \
   && grep -q 'os.killpg(process.pid, signal.SIGKILL)' "$TRIAGE_SKILL" \
   && grep -q 'signal.signal(watched_signal, terminate)' "$TRIAGE_SKILL" \
   && grep -q "trap 'finish_triage 143' TERM" "$TRIAGE_SKILL" \
   && grep -q 'kill -TERM "$watchdog_pid"' "$TRIAGE_SKILL" \
   && grep -q 'python3 "$RUN_TMP/codex-watchdog.py" 600 ' "$TRIAGE_SKILL" \
   && [ "$(grep -c 'for attempt in 1 2' "$TRIAGE_SKILL")" -eq 2 ]; then
  ok "linear triage analysts have a signal-safe 600-second process-group watchdog and one retry"
else
  fail "linear triage analyst watchdog/retry contract drifted"
fi
if [ "$(grep -c 'get_issue(id: "<IDENT>", includeRelations: true)' "$TRIAGE_SKILL")" -ge 2 ] \
   && grep -q 'orca linear team list --workspace all --json' "$TRIAGE_SKILL" \
   && ! grep -q 'orca linear issue <IDENT> --full --json' "$TRIAGE_SKILL"; then
  ok "linear triage snapshots include relations and pin Orca issue reads to a workspace"
else
  fail "linear triage relation/workspace read contract drifted"
fi
if grep -q 'command -v python3 || echo MISSING_PYTHON3' "$TRIAGE_SKILL" \
   && grep -q 'estimate-settings.json' "$TRIAGE_SKILL" \
   && grep -q 'sized\["complexity"\] != "C5" and effort is None' "$TRIAGE_SKILL" \
   && grep -q 'list_comments.*, paginating to exhaustion' "$TRIAGE_SKILL" \
   && grep -q 'Never use a write as the probe' "$TRIAGE_SKILL"; then
  ok "linear triage preflights Python, validates effort, proves declines, and resolves estimate settings before writes"
else
  fail "linear triage dependency/effort/decline/estimate-setting contract drifted"
fi
# The two <<'PY' heredocs in the skill are copied verbatim to disk at runtime; a
# syntax error would pass every grep above and only explode on a live ticket.
# Extract them (block1 = watchdog, block2 = validator), compile both, then run
# the watchdog for real: a hung command must die at the deadline with exit 124
# and the .timeout marker, and a finished command's exit code must pass through.
TRIAGE_PY_DIR="$(mktemp -d)"
awk -v dir="$TRIAGE_PY_DIR" '
  /<<.PY.$/ { n += 1; capture = 1; next }
  capture && /^PY$/ { capture = 0; next }
  capture { print > (dir "/block" n ".py") }
' "$TRIAGE_SKILL"
if [ -f "$TRIAGE_PY_DIR/block1.py" ] && [ -f "$TRIAGE_PY_DIR/block2.py" ] \
   && python3 -m py_compile "$TRIAGE_PY_DIR/block1.py" "$TRIAGE_PY_DIR/block2.py" 2>/dev/null; then
  ok "both embedded python blocks (watchdog, validator) compile"
else
  fail "an embedded python block is missing or does not compile"
fi
wd_rc=0
python3 "$TRIAGE_PY_DIR/block1.py" 1 bash -c 'sleep 5' watchdog \
  --output-last-message "$TRIAGE_PY_DIR/out" >/dev/null 2>&1 || wd_rc=$?
if [ "$wd_rc" -eq 124 ] && [ -e "$TRIAGE_PY_DIR/out.timeout" ]; then
  ok "watchdog kills a hung command at the deadline (exit 124 + .timeout marker)"
else
  fail "watchdog timeout contract broken (rc=$wd_rc)"
fi
wd_rc=0
python3 "$TRIAGE_PY_DIR/block1.py" 10 bash -c 'exit 7' watchdog \
  --output-last-message "$TRIAGE_PY_DIR/out" >/dev/null 2>&1 || wd_rc=$?
if [ "$wd_rc" -eq 7 ]; then
  ok "watchdog passes a finished command's exit code through"
else
  fail "watchdog exit passthrough broken (rc=$wd_rc)"
fi
# The validator's exit taxonomy is behaviour, not text — run block2 against
# fixtures: 0 = valid, 1 = analyst garbage, 2 = contamination, 3 = harness fault.
echo '{"enabled":true,"name":"linear","values":[1,2,3,5,8],"labels":{},"source":"test"}' \
  > "$TRIAGE_PY_DIR/estimate-settings.json"
vrun() { python3 "$TRIAGE_PY_DIR/block2.py" "$1" "$2" >/dev/null 2>&1; echo $?; }
printf '```json\n{"value": 3, "reasoning": "not 2 because nothing compounds; not 4 because it degrades", "verified": [], "unverified": [], "risk": "none"}\n```\n' > "$TRIAGE_PY_DIR/v.out"
[ "$(vrun impact "$TRIAGE_PY_DIR/v.out")" -eq 0 ] \
  && ok "validator accepts a valid impact 3 with both anti-Medium sentences (rc 0)" \
  || fail "validator rejected a valid impact object"
printf '```json\n{"value": 3, "reasoning": "seems medium", "verified": [], "unverified": [], "risk": "none"}\n```\n' > "$TRIAGE_PY_DIR/v.out"
[ "$(vrun impact "$TRIAGE_PY_DIR/v.out")" -eq 1 ] \
  && ok "validator rejects a 3 missing the anti-Medium sentences (rc 1)" \
  || fail "anti-Medium invariant not enforced behaviorally"
# needle built split so this test file never plants the literal in the repo
printf 'stray %s tag\n```json\n{"value": 1, "reasoning": "x", "verified": [], "unverified": [], "risk": "y"}\n```\n' "ant$(printf 'ml')" > "$TRIAGE_PY_DIR/v.out"
[ "$(vrun impact "$TRIAGE_PY_DIR/v.out")" -eq 2 ] \
  && ok "validator flags namespace contamination (rc 2)" \
  || fail "contamination tripwire broken"
printf '```json\n{"value": {"complexity": "C5", "effort": 5}, "reasoning": "spike first", "verified": [], "unverified": [], "risk": "unknown approach"}\n```\n' > "$TRIAGE_PY_DIR/v.out"
if [ "$(vrun sizing "$TRIAGE_PY_DIR/v.out")" -eq 0 ] && grep -q '"effort":null' "$TRIAGE_PY_DIR/v.out"; then
  ok "validator normalises C5 effort to null in place (rc 0)"
else
  fail "C5 effort normalisation broken"
fi
printf '```json\n{"value": {"complexity": "C2", "effort": null}, "reasoning": "x", "verified": [], "unverified": [], "risk": "y"}\n```\n' > "$TRIAGE_PY_DIR/v.out"
[ "$(vrun sizing "$TRIAGE_PY_DIR/v.out")" -eq 1 ] \
  && ok "validator rejects a non-C5 with null effort (rc 1)" \
  || fail "null-effort invariant not enforced"
mkdir -p "$TRIAGE_PY_DIR/nosettings"
printf '```json\n{"value": {"complexity": "C2", "effort": 2}, "reasoning": "x", "verified": [], "unverified": [], "risk": "y"}\n```\n' > "$TRIAGE_PY_DIR/nosettings/v.out"
[ "$(vrun sizing "$TRIAGE_PY_DIR/nosettings/v.out")" -eq 3 ] \
  && ok "validator reports a missing estimate-settings.json as a harness fault (rc 3)" \
  || fail "harness fault misattributed by the validator"
rm -rf "$TRIAGE_PY_DIR"

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
