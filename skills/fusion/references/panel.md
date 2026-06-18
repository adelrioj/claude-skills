# Fusion Panel — fan-out contract

Fusion runs a prompt through a **panel** of models that answer **independently and blind**,
then Opus 4.8 judges and synthesizes. Independence is the whole point: consensus,
contradictions, and blind spots only surface when no panelist sees another's answer.

## Panelists

| Seat | How it runs | Tools | Notes |
|------|-------------|-------|-------|
| Opus (×1 or ×2) | Agent subagents (in-process) | web search + bash | Always available. Two independent subagents in `opus-opus`. |
| GPT-5.5 | `scripts/run_codex.sh` (`codex exec`, `--sandbox workspace-write`) | web search + bash, ephemeral repo copy | Optional; needs authenticated `codex`. |
| Local | `scripts/run_local.sh` (`pi` → LMStudio) | read/grep/find/ls/bash — **no web search** | Optional; needs `pi` + a model loaded in LMStudio. Lower grounding: cannot consult primary web sources. |

## Fan-out rules

- Every panelist receives the user's task **verbatim**. No assigned personas — each answers straight.
- Launch all panelists **concurrently**. Each external runner writes to a unique temp file
  `/tmp/fusion-<run>-<panelist>.md`.
- A panelist that exits non-zero (missing CLI, unloaded model, timeout) is **dropped**; the panel
  degrades to the remaining seats. Never block the run on one panelist.
- Opus is always also the judge; the pipeline is one-directional (non-Opus panelists cannot
  spawn Opus callbacks).

## Subscription posture

All seats run over subscription — Opus via the Claude Code plan, GPT-5.5 via the `codex`
subscription, local via LMStudio (free/offline). No panelist uses an API key.
