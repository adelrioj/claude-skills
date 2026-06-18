# Design: `/fusion` — multi-model panel with a local LMStudio panelist

**Date:** 2026-06-18
**Status:** Approved (brainstorming) — pending implementation plan
**Topic:** Port [fusion-fable](https://github.com/duolahypercho/fusion-fable) (MIT) into this plugin as a `/fusion` skill, replacing the Gemini/`agy` panelist with the local LMStudio model via `pi`. Claude and Codex panelists run over subscription; no API keys anywhere.

---

## 1. Purpose & Context

fusion-fable improves answer quality by running a prompt through several frontier models **independently and blind**, then having Opus 4.8 judge and synthesize a single grounded answer. The value comes from independence ("harvested, not manufactured") — consensus, contradictions, and blind spots surface only when panelists never see each other's work.

This plugin already has the building blocks fusion needs: subagent dispatch (Opus panelists), the `codex exec` invocation pattern (swarm-execute), and the `pi` + LMStudio local-model pattern (spec-review-local). This design ports fusion-fable's pipeline while swapping its most fragile component — the Gemini panelist (`run_gemini.sh`, ~50 lines fighting `agy` bug #76 with a PTY wrapper + JSONL-transcript fallback) — for a clean local panelist driven by `pi` against LMStudio's HTTP API.

**Constraint — subscription only:** Opus panelists are in-process Agent subagents (Claude Code plan). The GPT-5.5 panelist is the authenticated `codex` CLI (ChatGPT/codex subscription). The local panelist is free/offline. No design path introduces an API key.

---

## 2. Architecture

Pipeline (unchanged from upstream): **detect → preflight → blind parallel fan-out → Opus judge → grounded final → provenance save.** Opus is always the judge; the pipeline is not reversible (non-Opus panelists cannot spawn Opus callbacks).

A single user-invocable skill `/fusion` orchestrates it, staying a thin conductor over ported shell scripts.

### Panel availability ladder

| Slug | Panelists | Requires |
|------|-----------|----------|
| `opus-opus` | 2× independent Opus subagents | nothing (always available) |
| `opus-codex` | Opus + GPT-5.5 | `codex` CLI authenticated |
| `opus-codex-local` | Opus + GPT-5.5 + local LMStudio model | `codex` + `pi` on PATH + a model loaded in LMStudio |

`/fusion` auto-selects the richest available slug. An optional argument forces a panel:
- `/fusion` → auto-detect richest
- `/fusion opus` → force `opus-opus` (offline, zero external CLI)
- `/fusion codex` → force `opus-codex`
- `/fusion local` → force `opus-codex-local`

If a forced panel is unavailable (e.g. `local` but no model loaded), the skill **reports the gap and falls back to the richest available panel** — it never silently claims a panelist ran when it did not.

---

## 3. The external panelist runners

### 3.1 `run_local.sh` (replaces `run_gemini.sh`)

The major simplification. No PTY, no bug-#76 workaround, no `_pty_run.py`.

1. **Model detection** — query LMStudio's `/api/v0/models` for the first loaded LLM (the exact snippet from `spec-review-local`); never hardcode a model name. If none loaded, exit non-zero so the orchestrator degrades the panel.
   ```bash
   MODEL="$(curl -s --max-time 5 http://127.0.0.1:1234/api/v0/models \
     | jq -r '[.data[] | select(.state == "loaded" and .type == "llm")][0].id // empty')"
   [ -z "$MODEL" ] && { echo "[run_local.sh] no LLM loaded in LMStudio — skip this panelist." >&2; exit 1; }
   ```
2. **Run** the panelist:
   ```bash
   pi --provider lmstudio --model "$MODEL" \
      --tools read,grep,find,ls,bash \
      --no-session --print "$(cat "$prompt_file")" > "$output_file"
   ```
   The local model gets read/grep/find/ls/bash (consistent with spec-review-local) so it can inspect the ephemeral repo copy and run/verify code. It has **no web search** — `pi` against a local model exposes filesystem/bash tools only.
3. **Timeout** — wrapped in `_fusion_lib.sh`'s timeout helper, default `FUSION_LOCAL_TIMEOUT=600` (local models are slow; matches spec-review-local's 600s budget) versus 300s for codex.
4. **Anti-empty guard** — never exit 0 with an empty `$output_file`; on empty, exit non-zero so the orchestrator drops the local panelist.

### 3.2 `run_codex.sh` (ported, one change)

Ported nearly verbatim from upstream. The single change, per repo convention (CLAUDE.md bans `--dangerously-bypass-approvals-and-sandbox`):

- Replace `--dangerously-bypass-approvals-and-sandbox` with `--sandbox workspace-write`.
- Keep web search via `-c tools.web_search=true`, reasoning effort, ephemeral repo copy, `-o/--output-last-message` capture, 300s timeout, and exit codes 124 (timeout) / 1 (failure) for graceful degradation.

**Tradeoff (accepted):** under `workspace-write`, macOS keychain-backed tools like `gh` may not work for the codex panelist. A fusion panelist needs web + reasoning, not `gh`, so this is acceptable.

---

## 4. Orchestration (`SKILL.md`)

`SKILL.md` is a thin conductor over the scripts, following upstream's step structure:

- **Step 0 — Detect.** Run `detect_panel.sh`; grep the `SLUG=` line. If the user passed an argument, validate it against availability; force-with-fallback if unavailable (Section 2).
- **Step 1 — Preflight.** `preflight.sh` prints an informational token/call estimate. Never blocks.
- **Step 2 — Blind fan-out.** Launch all panelists concurrently:
  - Opus panelists → Agent subagents, each handed the user's task verbatim with web + bash, no shared context.
  - `run_codex.sh` and `run_local.sh` → launched in parallel, each writing to a unique temp file `/tmp/fusion-<run>-<panelist>.md` to prevent cross-session collisions.
  - No panelist sees another's answer.
- **Step 3 — Judge.** Orchestrator Opus reads all panelist files fresh and classifies the task:
  - *Artifact* (code/config/scripts): run both candidates, observe behavior, merge what worked, re-verify the merged result.
  - *Research/analysis*: structured synthesis over consensus, contradictions, partial coverage, unique insights, blind spots.
  - Weight panelists who consulted primary sources or ran code higher; the local panelist (no web) is weighted accordingly.
- **Step 4 — Deliver.** Working artifact or grounded analysis — never averaged or smoothed.
- **Step 5 — Provenance.** Archive all panelist answers + the final to `~/.claude/fusion-runs/<timestamp>/` (outside the repo; matches upstream `~/.claude/fusion-runs/`). Never committed.
- **Step 6 — Present** the deliverable with audit trail + panel composition.

`references/panel.md` and `references/judge_rubric.md` are ported, edited to describe the local panelist and its lower tool-grounding (no web) in place of Gemini.

---

## 5. File layout

New `skills/fusion/`:

```
skills/fusion/
├── SKILL.md                  # thin orchestrator; user-invocable frontmatter + triggers
├── scripts/
│   ├── _fusion_lib.sh        # ported: timeout helper, have(), shared config (timeouts)
│   ├── detect_panel.sh       # probe codex + pi/LMStudio loaded-model (NOT agy)
│   ├── preflight.sh          # ported; estimate updated for the local panel
│   ├── run_codex.sh          # --sandbox workspace-write
│   └── run_local.sh          # pi/LMStudio (replaces run_gemini.sh + _pty_run.py)
└── references/
    ├── panel.md              # edited: local seat
    └── judge_rubric.md       # edited: weight tool-limited local panelist
```

**Dropped from upstream:** `_pty_run.py`, `run_gemini.sh` (agy-only), the `commands/` dir (this repo uses user-invocable skills, not command files), and `install.sh` (this plugin installs via marketplace).

### `detect_panel.sh` changes

Probe `codex` (unchanged) and replace the `agy` probe with a local-panelist probe: `pi` on PATH **and** a model loaded in LMStudio (the `/api/v0/models` curl). Slug selection:
```
codex_ok && local_ok  → opus-codex-local
codex_ok              → opus-codex
else                  → opus-opus
```
Opus is never probed (always available via subagents).

---

## 6. Plugin integration (documentation touchpoints)

- **`.claude-plugin/plugin.json`** — bump version; extend `description` and `keywords` (add `fusion`, `multi-model`; `lmstudio` already present).
- **`CLAUDE.md`** — add a `/fusion` entry under "Skills"; add Key Conventions lines:
  - fusion panelists are subscription-only — Opus via subagents, GPT-5.5 via authenticated `codex`, local via `pi`/LMStudio; no API keys.
  - the codex panelist uses `--sandbox workspace-write` (never the banned `--dangerously-bypass-approvals-and-sandbox`).
  - the local panelist auto-detects the loaded LMStudio model via `/api/v0/models`, never hardcoded.
  - fusion provenance lives in `~/.claude/fusion-runs/`, never committed to the repo.
- **`README.md`** + **`.claude-plugin/marketplace.json`** — list the skill.
- **Attribution** — credit upstream fusion-fable (MIT) in the `SKILL.md` header.

### Prerequisites (documented in SKILL.md)
- `opus-opus`: always works, fully offline.
- `opus-codex`: authenticated `codex` CLI on PATH.
- `opus-codex-local`: `codex` + `pi` on PATH + LMStudio running at `http://127.0.0.1:1234` with a model loaded.

---

## 7. Out of scope (YAGNI)

- Gemini/`agy` support and its PTY/bug-#76 machinery.
- API-key auth paths for any panelist.
- A custom `dev.orbstack`/install script — marketplace install only.
- Multi-host LMStudio endpoints — the `127.0.0.1:1234` default mirrors spec-review-local; advanced users can override via env if a runner exposes it, but it is not a designed feature.
