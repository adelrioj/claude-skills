# /fusion Skill with Local LMStudio Panelist — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/fusion` skill to this plugin that ports fusion-fable's independence-then-synthesis pipeline, with the Gemini/`agy` panelist replaced by the local LMStudio model via `pi`.

**Architecture:** A single user-invocable `skills/fusion/` skill orchestrates a blind parallel fan-out to a panel of models (Opus subagents + GPT-5.5 via `codex` + local model via `pi`), then Opus judges and synthesizes. Orchestration lives in ported shell scripts under `scripts/`; `SKILL.md` is a thin conductor. All panelists run over subscription — no API keys.

**Tech Stack:** Bash (panelist runners + detection), Perl (timeout helper, inherited from upstream), `pi` CLI + LMStudio HTTP API (`/api/v0/models`), `codex exec`, `jq`, `curl`. Markdown skill definition.

## Global Constraints

- Subscription-only: Opus via Agent subagents, GPT-5.5 via authenticated `codex`, local via `pi`/LMStudio. No design path introduces an API key.
- The codex panelist uses `--sandbox workspace-write` — NEVER `--dangerously-bypass-approvals-and-sandbox` (banned by CLAUDE.md).
- The local panelist auto-detects the loaded LMStudio model via `/api/v0/models` — never hardcode a model id.
- Panel slugs are exactly: `opus-opus`, `opus-codex`, `opus-codex-local`.
- Every runner degrades gracefully: a missing CLI / unloaded model / timeout exits non-zero (127 / 1 / 124) so the orchestrator drops that panelist rather than failing the run. A runner NEVER exits 0 with an empty output file.
- Shell scripts use `set -uo pipefail` (runners) and are sourced/executed exactly as upstream; `_fusion_lib.sh` is sourced, not executed.
- Provenance is written to `~/.claude/fusion-runs/<timestamp>/`, outside the repo, never committed.
- Default timeouts: `FUSION_TIMEOUT=300` (codex), `FUSION_LOCAL_TIMEOUT=600` (local).
- Attribution: credit upstream fusion-fable (MIT, https://github.com/duolahypercho/fusion-fable) in the `SKILL.md` header.

---

## File Structure

```
skills/fusion/
├── SKILL.md                  # Task 7 — thin orchestrator + frontmatter/triggers
├── scripts/
│   ├── _fusion_lib.sh        # Task 1 — ported verbatim (timeout helper, have())
│   ├── detect_panel.sh       # Task 2 — probe codex + pi/LMStudio
│   ├── run_local.sh          # Task 3 — pi/LMStudio panelist (replaces run_gemini.sh)
│   ├── run_codex.sh          # Task 4 — codex panelist, --sandbox workspace-write
│   └── preflight.sh          # Task 5 — informational estimate, adapted slugs
└── references/
    ├── panel.md              # Task 6 — panel description (local seat)
    └── judge_rubric.md       # Task 6 — judge weighting rubric
```

Plugin docs touched in Task 8: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, `CLAUDE.md`.

A `shellcheck` pass is the standing test for every shell file. If `shellcheck` is not installed, substitute `bash -n <file>` (syntax-only) and note it.

---

### Task 1: Scaffold skill + shared timeout library

**Files:**
- Create: `skills/fusion/scripts/_fusion_lib.sh`

**Interfaces:**
- Produces: `FUSION_TIMEOUT` (default 300), `have <cmd>` (returns 0 if cmd on PATH), `_run_with_timeout <secs> <cmd...>` (runs cmd, returns its exit code, or 124 on timeout). Every other runner sources this file.

- [ ] **Step 1: Create the library file verbatim from upstream**

```bash
#!/usr/bin/env bash
# _fusion_lib.sh — shared helpers for the Fusion panelist runners.
#
# Sourced (not executed) by run_codex.sh and run_local.sh:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/_fusion_lib.sh"
#
# Why this exists: macOS has no `timeout`/`gtimeout` (those ship with GNU coreutils,
# not installed here). _run_with_timeout reproduces GNU `timeout` semantics with a
# small self-contained perl fork+alarm wrapper: it sends SIGTERM on the deadline,
# then SIGKILL after a 2s grace, returns the command's real exit status, and returns
# 124 when the command was killed for running over time.

# Default per-panelist budget in seconds; override with FUSION_TIMEOUT.
FUSION_TIMEOUT="${FUSION_TIMEOUT:-300}"

have() { command -v "$1" >/dev/null 2>&1; }

# _run_with_timeout SECONDS cmd [args...]
# Exit status = the command's own status, or 124 if it was killed for timing out.
_run_with_timeout() {
  local secs="$1"; shift
  perl -e '
    my $secs = shift @ARGV;
    my $pid = fork();
    exit 127 unless defined $pid;
    if ($pid == 0) { exec @ARGV or exit 127; }   # child: become the real command
    local $SIG{ALRM} = sub { kill "TERM", $pid; sleep 2; kill "KILL", $pid; };
    alarm $secs;
    waitpid($pid, 0);
    my $rc = $?;
    alarm 0;
    exit 124 if ($rc & 127);   # killed by a signal (our TERM/KILL) => timed out
    exit($rc >> 8);            # otherwise propagate the command exit code
  ' "$secs" "$@"
}
```

- [ ] **Step 2: Verify it sources and the helpers work**

Run:
```bash
bash -c '. skills/fusion/scripts/_fusion_lib.sh; have bash && echo "have-ok"; echo "FUSION_TIMEOUT=$FUSION_TIMEOUT"; _run_with_timeout 5 true && echo "fast-ok"; _run_with_timeout 1 sleep 3; echo "timeout-rc=$?"'
```
Expected output includes:
```
have-ok
FUSION_TIMEOUT=300
fast-ok
timeout-rc=124
```

- [ ] **Step 3: Lint**

Run: `shellcheck skills/fusion/scripts/_fusion_lib.sh || bash -n skills/fusion/scripts/_fusion_lib.sh`
Expected: no errors (shellcheck may warn on the perl heredoc string — acceptable; `bash -n` must pass clean).

- [ ] **Step 4: Commit**

```bash
git add skills/fusion/scripts/_fusion_lib.sh
git commit -m "feat(fusion): add shared timeout library for panelist runners"
```

---

### Task 2: Panel detection

**Files:**
- Create: `skills/fusion/scripts/detect_panel.sh`

**Interfaces:**
- Consumes: `FUSION_LMSTUDIO_URL` env (default `http://127.0.0.1:1234`).
- Produces: stdout ending in a `SLUG=<slug>` line where slug ∈ {`opus-opus`, `opus-codex`, `opus-codex-local`}. The orchestrator greps this line.

- [ ] **Step 1: Create the detection script**

```bash
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
```

- [ ] **Step 2: Make executable and run it**

Run:
```bash
chmod +x skills/fusion/scripts/detect_panel.sh
skills/fusion/scripts/detect_panel.sh
```
Expected: prints the availability block and a final `SLUG=` line. On a machine with no `codex` and no loaded LMStudio model, the last line is exactly `SLUG=opus-opus`. (The slug reflects the local environment — assert only that a valid slug from the allowed set is printed.)

- [ ] **Step 3: Verify the slug is grep-able**

Run: `skills/fusion/scripts/detect_panel.sh | grep -oE 'SLUG=(opus-opus|opus-codex|opus-codex-local)$'`
Expected: exactly one matching line.

- [ ] **Step 4: Lint**

Run: `shellcheck skills/fusion/scripts/detect_panel.sh || bash -n skills/fusion/scripts/detect_panel.sh`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add skills/fusion/scripts/detect_panel.sh
git commit -m "feat(fusion): add panel detection (codex + pi/LMStudio probe)"
```

---

### Task 3: Local LMStudio panelist runner

**Files:**
- Create: `skills/fusion/scripts/run_local.sh`

**Interfaces:**
- Consumes: `_fusion_lib.sh` (`have`, `_run_with_timeout`); env `FUSION_LMSTUDIO_URL` (default `http://127.0.0.1:1234`), `FUSION_LOCAL_TIMEOUT` (default 600).
- Produces: CLI `run_local.sh <prompt_file> <output_file>`. Writes the model's answer to `<output_file>`. Exit codes: 0 ok; 127 no `pi`; 1 no model loaded / empty answer / error; 124 timeout; 2 bad prompt file.

- [ ] **Step 1: Create the runner**

```bash
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
```

- [ ] **Step 2: Make executable; verify graceful skip when no model is loaded**

This is the key degradation path and is testable without LMStudio. Point the runner at a dead port so model detection returns empty.

Run:
```bash
chmod +x skills/fusion/scripts/run_local.sh
printf 'What is 2+2?' > /tmp/fusion-test-prompt.md
FUSION_LMSTUDIO_URL="http://127.0.0.1:9" skills/fusion/scripts/run_local.sh /tmp/fusion-test-prompt.md /tmp/fusion-test-out.md; echo "rc=$?"
```
Expected (when `pi` IS installed): stderr says `no LLM loaded in LMStudio at http://127.0.0.1:9 — skip this panelist.` and `rc=1`. (When `pi` is NOT installed: stderr says `pi CLI not installed` and `rc=127`.) Either way the runner degrades, never hangs, and writes no output file.

- [ ] **Step 3: Verify empty prompt is rejected**

Run:
```bash
: > /tmp/fusion-empty.md
skills/fusion/scripts/run_local.sh /tmp/fusion-empty.md /tmp/fusion-out.md; echo "rc=$?"
```
Expected: stderr `prompt file missing or empty`, `rc=2`.

- [ ] **Step 4: Lint**

Run: `shellcheck skills/fusion/scripts/run_local.sh || bash -n skills/fusion/scripts/run_local.sh`
Expected: clean (`bash -n` must pass; shellcheck SC2086 on the deliberately-unquoted `--tools` list is not present here — all args are quoted).

- [ ] **Step 5: Commit**

```bash
git add skills/fusion/scripts/run_local.sh
git commit -m "feat(fusion): add local LMStudio panelist runner via pi"
```

---

### Task 4: Codex panelist runner (sandbox = workspace-write)

**Files:**
- Create: `skills/fusion/scripts/run_codex.sh`

**Interfaces:**
- Consumes: `_fusion_lib.sh` (`have`, `_run_with_timeout`, `FUSION_TIMEOUT`).
- Produces: CLI `run_codex.sh <prompt_file> <output_file> [reasoning_effort]`. Writes the panelist's final message to `<output_file>`. Exit codes: 0 ok; 124 timeout; 1 failure/empty; 2 bad prompt file.

This is upstream `run_codex.sh` ported verbatim **except** the sandbox flag: `--dangerously-bypass-approvals-and-sandbox` → `--sandbox workspace-write`.

- [ ] **Step 1: Create the runner**

```bash
#!/usr/bin/env bash
# run_codex.sh — run one GPT-5.5 panelist (via codex) on a prompt, with web search + bash.
#
# Usage:
#   run_codex.sh <prompt_file> <output_file> [reasoning_effort]
#
# - <prompt_file>   : file containing the FULL panelist prompt (verbatim user task + brief instruction)
# - <output_file>   : where the panelist's final answer is written (clean, just the answer)
# - reasoning_effort: low | medium | high | xhigh   (default: xhigh)
#
# Notes:
# - `-o/--output-last-message` writes ONLY the agent's final message — no streaming noise to parse.
# - The panelist runs against a temporary copy of the current repo/workdir, so its file writes do
#   not touch your live checkout.
# - `--sandbox workspace-write` confines writes to that throwaway copy (this repo bans
#   --dangerously-bypass-approvals-and-sandbox). `-c tools.web_search=true` enables web search.
# - The throwaway copy is deleted when the panelist exits.
# - There is no `timeout`/`gtimeout` on stock macOS, so the codex run is wrapped in the perl
#   timeout helper (FUSION_TIMEOUT, default 300s). On timeout the runner exits 124 so the
#   orchestrator drops GPT-5.5 and degrades the panel gracefully.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_fusion_lib.sh"

prompt_file="${1:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
output_file="${2:?usage: run_codex.sh <prompt_file> <output_file> [reasoning_effort]}"
effort="${3:-xhigh}"

case "$prompt_file" in /*) ;; *) prompt_file="$(pwd -P)/$prompt_file" ;; esac
case "$output_file" in /*) ;; *) output_file="$(pwd -P)/$output_file" ;; esac

if [ ! -s "$prompt_file" ]; then
  echo "[run_codex.sh] prompt file is missing or empty: $prompt_file" >&2
  exit 2
fi
mkdir -p "$(dirname "$output_file")"
rm -f "$output_file"

if ! have codex; then
  echo "[run_codex.sh] codex CLI not installed — skip this panelist." >&2
  exit 127
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/fusion-codex.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
workdir="$scratch/workdir"

source_root="$(pwd -P)"
source_subdir=""
if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  source_root="$(cd "$git_root" && pwd -P)"
  current_dir="$(pwd -P)"
  case "$current_dir" in
    "$source_root") source_subdir="" ;;
    "$source_root"/*) source_subdir="${current_dir#"$source_root"/}" ;;
    *) source_subdir="" ;;
  esac
fi

mkdir -p "$workdir"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude '.git/index.lock' \
    --exclude '.git/shallow.lock' \
    --exclude '.git/worktrees/*/index.lock' \
    "$source_root"/ "$workdir"/
else
  cp -R "$source_root"/. "$workdir"/
fi

panel_cwd="$workdir"
if [ -n "$source_subdir" ]; then
  panel_cwd="$workdir/$source_subdir"
fi

_run_with_timeout "$FUSION_TIMEOUT" codex exec \
  --skip-git-repo-check \
  --ephemeral \
  --cd "$panel_cwd" \
  --sandbox workspace-write \
  -c tools.web_search=true \
  -c "model_reasoning_effort=$effort" \
  -o "$output_file" \
  - < "$prompt_file" \
  > "$scratch/stream.log" 2>&1

status=$?
if [ "$status" -eq 124 ]; then
  echo "[run_codex.sh] codex timed out after ${FUSION_TIMEOUT}s; tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  exit 124
fi
if [ "$status" -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_codex.sh] codex exited $status; tail of log:" >&2
  tail -20 "$scratch/stream.log" >&2
  exit 1
fi
echo "[run_codex.sh] ok -> $output_file"
```

- [ ] **Step 2: Make executable; confirm the banned flag is absent and the required flag is present**

Run:
```bash
chmod +x skills/fusion/scripts/run_codex.sh
grep -c -- '--dangerously-bypass-approvals-and-sandbox' skills/fusion/scripts/run_codex.sh; echo "banned-count=^"
grep -c -- '--sandbox workspace-write' skills/fusion/scripts/run_codex.sh; echo "required-count=^"
```
Expected: the banned-flag count is `0`; the required-flag count is `1`.

- [ ] **Step 3: Verify graceful skip when codex absent / empty prompt rejected**

Run:
```bash
: > /tmp/fusion-empty.md
skills/fusion/scripts/run_codex.sh /tmp/fusion-empty.md /tmp/fusion-out.md; echo "rc=$?"
```
Expected: stderr `prompt file is missing or empty`, `rc=2`. (Full codex execution requires an authenticated `codex` + network and is exercised in Task 7's end-to-end check, not here.)

- [ ] **Step 4: Lint**

Run: `shellcheck skills/fusion/scripts/run_codex.sh || bash -n skills/fusion/scripts/run_codex.sh`
Expected: clean under `bash -n`.

- [ ] **Step 5: Commit**

```bash
git add skills/fusion/scripts/run_codex.sh
git commit -m "feat(fusion): add codex panelist runner (--sandbox workspace-write)"
```

---

### Task 5: Preflight estimate

**Files:**
- Create: `skills/fusion/scripts/preflight.sh`

**Interfaces:**
- Produces: CLI `preflight.sh <slug> <prompt_file>`. Prints an informational estimate, always exits 0.

- [ ] **Step 1: Create the script (slugs adapted to opus-codex-local family)**

```bash
#!/usr/bin/env bash
# preflight.sh — pre-run, NON-BLOCKING sanity check the orchestrator shows before fanning out.
#
# Usage:
#   preflight.sh <slug> <prompt_file>
#
# Prints a rough token/call estimate (so a heavy question doesn't surprise you) plus a codex
# cap reminder. It NEVER blocks — it only informs. Always exits 0.

set -uo pipefail

slug="${1:?usage: preflight.sh <slug> <prompt_file>}"
prompt_file="${2:?usage: preflight.sh <slug> <prompt_file>}"

case "$slug" in
  opus-codex-local)      n=3 ;;
  opus-codex|opus-opus)  n=2 ;;
  *)                     n=2 ;;
esac

words=0
[ -f "$prompt_file" ] && words="$(wc -w < "$prompt_file" | tr -d ' ')"
# ~1.3 tokens/word, very rough; output usually dwarfs input on deep questions.
in_tokens=$(( words * 4 / 3 ))

echo "preflight (informational — not a gate):"
echo "  panel        : $slug  ($n panelists + 1 Opus judge pass)"
echo "  prompt size  : ~${words} words (~${in_tokens} input tokens) sent to EACH of $n panelists"
echo "  note         : each panelist also generates a full answer, and the judge reads all $n;"
echo "                 real token cost is several× the input. Heavy deep-research questions are slow."
echo "  timeouts     : codex ${FUSION_TIMEOUT:-300}s (FUSION_TIMEOUT); local ${FUSION_LOCAL_TIMEOUT:-600}s (FUSION_LOCAL_TIMEOUT)"

if command -v codex >/dev/null 2>&1; then
  echo "  codex (GPT-5.5) : installed — quota isn't readable non-interactively; if a run fails on"
  echo "                    cap, check '/status' inside codex. Panel degrades gracefully if it does."
else
  echo "  codex (GPT-5.5) : NOT installed — GPT-5.5 panelist will be skipped."
fi

exit 0
```

- [ ] **Step 2: Make executable and run for each slug**

Run:
```bash
chmod +x skills/fusion/scripts/preflight.sh
printf 'Explain CAP theorem tradeoffs.' > /tmp/fusion-test-prompt.md
skills/fusion/scripts/preflight.sh opus-codex-local /tmp/fusion-test-prompt.md; echo "rc=$?"
skills/fusion/scripts/preflight.sh opus-opus /tmp/fusion-test-prompt.md | grep -q '2 panelists' && echo "opus-opus-ok"
```
Expected: first call prints `3 panelists + 1 Opus judge pass` and `rc=0`; second prints `opus-opus-ok`.

- [ ] **Step 3: Lint**

Run: `shellcheck skills/fusion/scripts/preflight.sh || bash -n skills/fusion/scripts/preflight.sh`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add skills/fusion/scripts/preflight.sh
git commit -m "feat(fusion): add non-blocking preflight estimate"
```

---

### Task 6: Reference docs (panel + judge rubric)

**Files:**
- Create: `skills/fusion/references/panel.md`
- Create: `skills/fusion/references/judge_rubric.md`

**Interfaces:**
- Consumes: nothing.
- Produces: two reference docs the SKILL.md links to for the fan-out instructions and judge weighting.

- [ ] **Step 1: Write `panel.md`**

```markdown
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
```

- [ ] **Step 2: Write `judge_rubric.md`**

```markdown
# Fusion Judge Rubric

Opus 4.8 reads every panelist's answer **fresh** (it did not participate in their reasoning)
and produces one grounded result. It never averages or smooths.

## 1. Classify the task

- **Artifact** (code, config, scripts): treat panelist answers as candidate implementations.
  Run the candidates, observe actual behavior, merge what worked, then **re-verify** the merged
  result. Deliver fully working output, not a description.
- **Research / analysis**: produce a structured synthesis covering consensus, contradictions,
  partial coverage, unique insights, and blind spots.

## 2. Weight the panelists

Weight by grounding, not eloquence:
- **Higher weight** to panelists who consulted primary sources (web search) or ran code to verify.
- **Lower weight** to the local panelist on any claim that needs web grounding — it has no web
  search. Its strengths are reasoning and local code/file inspection; lean on it there, discount
  it on current-events / external-fact claims.
- A lone dissenting answer that is *verified* (ran the code, cited the source) outweighs a
  confident majority that did not.

## 3. Deliver

- Attribute material contributions to each seat in the audit trail.
- State which panelists ran and which were dropped (and why).
- Never present a smoothed average — present the grounded best answer with its evidence.
```

- [ ] **Step 3: Verify both files exist and mention the local-seat web-search caveat**

Run:
```bash
test -f skills/fusion/references/panel.md && test -f skills/fusion/references/judge_rubric.md && echo "files-ok"
grep -q 'no web search' skills/fusion/references/panel.md && echo "panel-caveat-ok"
grep -q 'no web search' skills/fusion/references/judge_rubric.md && echo "rubric-caveat-ok"
```
Expected: `files-ok`, `panel-caveat-ok`, `rubric-caveat-ok`.

- [ ] **Step 4: Commit**

```bash
git add skills/fusion/references/panel.md skills/fusion/references/judge_rubric.md
git commit -m "docs(fusion): add panel fan-out contract and judge rubric"
```

---

### Task 7: SKILL.md orchestrator

**Files:**
- Create: `skills/fusion/SKILL.md`

**Interfaces:**
- Consumes: all scripts in `scripts/` and both `references/` docs.
- Produces: the user-invocable `/fusion` skill.

- [ ] **Step 1: Write `SKILL.md`**

````markdown
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
````

- [ ] **Step 2: Validate frontmatter and plugin loads the skill**

Run:
```bash
head -5 skills/fusion/SKILL.md | grep -q 'name: fusion' && echo "name-ok"
grep -q 'user-invocable: true' skills/fusion/SKILL.md && echo "invocable-ok"
grep -q 'fusion-fable' skills/fusion/SKILL.md && echo "attribution-ok"
```
Expected: `name-ok`, `invocable-ok`, `attribution-ok`.

- [ ] **Step 3: End-to-end smoke test of the offline panel**

Load the plugin and exercise the always-available panel so the orchestration is proven without external CLIs:

Run: `claude --plugin-dir . -p "/fusion opus What are two tradeoffs of optimistic locking?"`
Expected: the skill detects `opus-opus`, fans out to two Opus subagents, judges, delivers a synthesized answer, and reports a `~/.claude/fusion-runs/<timestamp>/` provenance path. (If `codex`/LMStudio are available locally, optionally repeat with `/fusion` to confirm the richer panel; otherwise note it as untested in this environment.)

- [ ] **Step 4: Commit**

```bash
git add skills/fusion/SKILL.md
git commit -m "feat(fusion): add /fusion orchestrator skill"
```

---

### Task 8: Plugin integration (manifests + docs)

**Files:**
- Modify: `.claude-plugin/plugin.json` (version, description, keywords)
- Modify: `.claude-plugin/marketplace.json` (list the skill)
- Modify: `README.md` (list the skill)
- Modify: `CLAUDE.md` (Skills section + Key Conventions)

**Interfaces:**
- Consumes: the completed `skills/fusion/`.
- Produces: discoverable, documented skill.

- [ ] **Step 1: Bump version + extend keywords/description in `plugin.json`**

Read `.claude-plugin/plugin.json` first. Bump `version` (e.g. `1.1.3` → `1.2.0`, a new feature). Add `"fusion"` and `"multi-model"` to `keywords` (`lmstudio` is already present). Extend `description` to mention the fusion multi-model panel. Keep valid JSON.

- [ ] **Step 2: List the skill in `marketplace.json`**

Read `.claude-plugin/marketplace.json` and add `/fusion` to wherever the other skills are enumerated, matching the existing entry style. Keep valid JSON.

- [ ] **Step 3: Add a `/fusion` section to `README.md`**

Match the existing per-skill blurb format. Summarize: blind multi-model panel (2× Opus + GPT-5.5 via codex + local LMStudio via pi), Opus judges, subscription-only, `opus`/`codex`/`local` override arg, prerequisites.

- [ ] **Step 4: Add `/fusion` to `CLAUDE.md`**

Under "## Skills", add a `### /fusion` entry (one paragraph mirroring the others). Under "## Key Conventions", add these lines verbatim:

```markdown
- `/fusion` panelists are subscription-only — Opus via Agent subagents, GPT-5.5 via authenticated `codex`, local via `pi`/LMStudio; no API keys anywhere
- `/fusion` runs the codex panelist with `--sandbox workspace-write` (never the banned `--dangerously-bypass-approvals-and-sandbox`); web search via `-c tools.web_search=true`
- `/fusion` auto-detects the loaded LMStudio model via `/api/v0/models` (override base URL with `FUSION_LMSTUDIO_URL`), never hardcoding a model id — same pattern as `/spec-review-local`
- `/fusion` provenance lives in `~/.claude/fusion-runs/`, never committed; any panelist seat degrades gracefully (missing CLI / unloaded model / timeout → dropped, panel continues)
- `/fusion` is a port of fusion-fable (MIT); the Gemini/`agy` seat and its PTY/bug-#76 workaround are intentionally dropped in favor of the local `pi`/LMStudio seat
```

- [ ] **Step 5: Validate JSON and confirm docs reference the skill**

Run:
```bash
jq empty .claude-plugin/plugin.json && jq empty .claude-plugin/marketplace.json && echo "json-ok"
grep -q '/fusion' README.md && grep -q 'fusion' CLAUDE.md && echo "docs-ok"
```
Expected: `json-ok`, `docs-ok`.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json README.md CLAUDE.md
git commit -m "docs(fusion): document /fusion in manifests, README, and CLAUDE.md"
```

---

## Self-Review

**1. Spec coverage** (each design section → task):
- §2 panel ladder + override → Task 2 (detect), Task 7 (override + fallback). ✓
- §3.1 run_local.sh (model detect, tools, timeout, anti-empty) → Task 3. ✓
- §3.2 run_codex.sh (workspace-write) → Task 4. ✓
- §4 orchestration steps 0–6 → Task 7. ✓
- §5 file layout (incl. dropped _pty_run.py/run_gemini.sh) → Tasks 1–7 create exactly the kept files; nothing creates the dropped ones. ✓
- §5 detect_panel.sh slug logic → Task 2. ✓
- §6 plugin integration (plugin.json, marketplace.json, README, CLAUDE.md, attribution) → Task 8 + Task 7 header. ✓
- §6 prerequisites → Task 7 SKILL.md. ✓
- §7 out-of-scope (no gemini, no API keys, no install.sh) → respected; no task adds them. ✓

**2. Placeholder scan:** No TBD/TODO. Every shell file has complete content; every verification step has an exact command + expected output. Reference docs and SKILL.md are written in full. ✓

**3. Type/name consistency:** Slugs `opus-opus`/`opus-codex`/`opus-codex-local` are identical across detect_panel.sh (Task 2), preflight.sh (Task 5), and SKILL.md (Task 7). Runner CLIs match their SKILL.md call sites: `run_codex.sh <prompt> <out> [effort]`, `run_local.sh <prompt> <out>`. Env vars `FUSION_TIMEOUT`/`FUSION_LOCAL_TIMEOUT`/`FUSION_LMSTUDIO_URL` are used consistently. ✓
