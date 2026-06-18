---
name: fusion
description: "Use to raise answer quality on a hard prompt by running it through a blind multi-model panel, then having Opus judge and synthesize one grounded answer. Panelists: 2x Opus subagents, GPT-5.5 via codex, and a local LMStudio model via pi — all over subscription, no API keys. Triggers on: fusion, run through fusion, fuse models, multi-model panel, panel of models, second opinion from multiple models."
user-invocable: true
---

# Fusion — multi-model panel with a local LMStudio seat

Ported from [fusion-fable](https://github.com/duolahypercho/fusion-fable) (MIT). This variant
replaces the Gemini/`agy` panelist with the local LMStudio model via `pi`. Opus and GPT-5.5
panelists run over subscription; no API keys.

**Pipeline:** detect → preflight → blind parallel fan-out → Opus judge → grounded final → provenance.

Read `references/panel.md` (fan-out contract) and `references/judge_rubric.md` (judging) before
fanning out. Scripts live in `${CLAUDE_PLUGIN_ROOT}/skills/fusion/scripts/`.

## Argument

`/fusion [panel]` — optional panel override:
- (none) → auto-detect the richest available panel
- `opus`  → force `opus-opus` (offline, no external CLI)
- `codex` → force `opus-codex`
- `local` → force `opus-codex-local`

The user's actual question is the rest of the conversation / prompt — pass it to panelists verbatim.

## Step 0 — Detect

Run `scripts/detect_panel.sh` and grep the `SLUG=` line for the auto-detected panel.

```bash
SLUG="$("${CLAUDE_PLUGIN_ROOT}/skills/fusion/scripts/detect_panel.sh" | grep -oE 'SLUG=(opus-opus|opus-codex|opus-codex-local)$' | cut -d= -f2)"
```

If the user forced a panel, honor it **only if available**. If a forced panel needs a seat that
detection shows is absent (e.g. `local` but no model loaded, or `codex` but no `codex` CLI),
tell the user the seat is unavailable and **fall back to the detected `$SLUG`** — never claim a
panelist ran when it did not.

## Step 1 — Preflight

Write the user's verbatim task to a temp prompt file, then:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/fusion/scripts/preflight.sh" "$SLUG" "$PROMPT_FILE"
```

Show the output. It is informational only — never block on it.

## Step 2 — Blind fan-out (concurrent)

Launch every seat for `$SLUG` at once, each blind to the others. Use a per-run id (e.g. a
timestamp) so temp files never collide.

- **Opus seats** (always 1, or 2 in `opus-opus`): dispatch each as an Agent subagent, handing it
  the user's task verbatim with instructions to use web search + bash and return only its answer.
  Do not let subagents see each other's work.
- **GPT-5.5 seat** (`opus-codex`, `opus-codex-local`): run
  `scripts/run_codex.sh "$PROMPT_FILE" /tmp/fusion-$RUN-codex.md` in the background.
- **Local seat** (`opus-codex-local`): run
  `scripts/run_local.sh "$PROMPT_FILE" /tmp/fusion-$RUN-local.md` in the background.

Wait for all to finish. Any seat whose runner exited non-zero is **dropped** — note it and
continue with whatever answers landed.

## Step 3 — Judge

Following `references/judge_rubric.md`: read every landed answer fresh, classify the task
(artifact vs research), weight web-grounded panelists above the no-web local seat, and produce
one grounded result. For artifact tasks, run/verify the merged candidate before delivering.

## Step 4 — Deliver

Present the working artifact or grounded analysis. Never average or smooth.

## Step 5 — Provenance

Archive every panelist answer plus the final to `~/.claude/fusion-runs/<timestamp>/` (outside the
repo; never committed). Include the panel slug and which seats ran vs were dropped.

## Step 6 — Present audit trail

Tell the user the panel composition, which seats contributed, which were dropped and why, and the
provenance directory path.

## Prerequisites

- `opus-opus`: always works, fully offline.
- `opus-codex`: authenticated `codex` CLI on PATH.
- `opus-codex-local`: `codex` + `pi` on PATH + LMStudio running at `http://127.0.0.1:1234`
  (override with `FUSION_LMSTUDIO_URL`) with a model loaded. `jq` and `curl` are required for
  model detection.
