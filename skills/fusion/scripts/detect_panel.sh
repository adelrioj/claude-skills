#!/usr/bin/env bash
# detect_panel.sh — figure out which panelist CLIs are available and recommend a Fusion panel.
#
# Opus 4.8 is always a panelist (Agent subagents) and always the judge — no CLI check. This
# script probes the EXTERNAL panelists: GPT-5.5 via codex, and the local LMStudio model via pi.
#
# Output: human-readable lines + a final `SLUG=...` line the orchestrator greps.

LMSTUDIO_URL="${FUSION_LMSTUDIO_URL:-http://127.0.0.1:1234}"

have() { command -v "$1" >/dev/null 2>&1; }

codex_ok=false; local_ok=false; model=""
have codex && codex_ok=true

if have pi && have jq && have curl; then
  model="$(curl -s --max-time 5 "$LMSTUDIO_URL/api/v0/models" \
    | jq -r '[.data[] | select(.state == "loaded" and .type == "llm")][0].id // empty' 2>/dev/null)"
  [ -n "$model" ] && local_ok=true
fi

echo "panelist availability (Opus 4.8 is always a panelist + the judge, via Agent subagents):"
echo "  opus   : yes (Agent subagents — always available)"
printf "  gpt5.5 : %s (codex CLI)\n"           "$([ "$codex_ok" = true ] && echo yes || echo NO)"
printf "  local  : %s (pi + LMStudio)\n"       "$([ "$local_ok" = true ] && echo "yes ($model)" || echo NO)"
echo

if   $codex_ok && $local_ok; then slug="opus-codex-local"
elif $codex_ok;              then slug="opus-codex"
else                              slug="opus-opus"
fi

echo "recommended panel: $slug"
echo "SLUG=$slug"
