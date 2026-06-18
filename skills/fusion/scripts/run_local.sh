#!/usr/bin/env bash
# run_local.sh — run one local LMStudio panelist via the `pi` CLI (read/grep/find/ls/bash tools).
#
# Usage:
#   run_local.sh <prompt_file> <output_file>
#
# Replaces upstream run_gemini.sh. No PTY workaround needed — pi talks to LMStudio over HTTP, so
# the agy bug-#76 machinery is gone. The model is auto-detected from LMStudio's /api/v0/models
# (never hardcoded). If no model is loaded, the runner exits non-zero so the orchestrator drops
# the local panelist and degrades the panel.
#
# Config (env):
#   FUSION_LMSTUDIO_URL   LMStudio base URL (default http://127.0.0.1:1234)
#   FUSION_LOCAL_TIMEOUT  per-panelist budget in seconds (default 600; local models are slow)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_fusion_lib.sh"

prompt_file="${1:?usage: run_local.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_local.sh <prompt_file> <output_file>}"

LMSTUDIO_URL="${FUSION_LMSTUDIO_URL:-http://127.0.0.1:1234}"
LOCAL_TIMEOUT="${FUSION_LOCAL_TIMEOUT:-600}"

case "$prompt_file" in /*) ;; *) prompt_file="$(pwd -P)/$prompt_file" ;; esac
case "$output_file" in /*) ;; *) output_file="$(pwd -P)/$output_file" ;; esac

if [ ! -s "$prompt_file" ]; then
  echo "[run_local.sh] prompt file missing or empty: $prompt_file" >&2
  exit 2
fi
mkdir -p "$(dirname "$output_file")"
rm -f "$output_file"

if ! have pi; then
  echo "[run_local.sh] pi CLI not installed — skip this panelist." >&2
  exit 127
fi

MODEL="$(curl -s --max-time 5 "$LMSTUDIO_URL/api/v0/models" \
  | jq -r '[.data[] | select(.state == "loaded" and .type == "llm")][0].id // empty')"
if [ -z "$MODEL" ]; then
  echo "[run_local.sh] no LLM loaded in LMStudio at $LMSTUDIO_URL — skip this panelist." >&2
  exit 1
fi
echo "[run_local.sh] using LMStudio model: $MODEL" >&2

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-local.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

_run_with_timeout "$LOCAL_TIMEOUT" \
  pi --provider lmstudio --model "$MODEL" \
     --tools read,grep,find,ls,bash \
     --no-session --print "$(cat "$prompt_file")" \
  > "$output_file" 2> "$scratch/stderr.log"
status=$?

if [ "$status" -eq 124 ]; then
  echo "[run_local.sh] pi timed out after ${LOCAL_TIMEOUT}s; tail of stderr:" >&2
  tail -20 "$scratch/stderr.log" >&2
  exit 124
fi
if [ "$status" -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_local.sh] pi exited $status or produced no answer; tail of stderr:" >&2
  tail -20 "$scratch/stderr.log" >&2
  exit 1
fi
echo "[run_local.sh] ok -> $output_file"
