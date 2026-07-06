# `/fusion`

Runs a prompt through a blind multi-model panel (2× Opus subagents + GPT-5.5 via `codex exec --sandbox workspace-write` + local LMStudio model via `pi`) then has a separate Opus judge synthesize the responses into a single verdict. Subscription-only: Opus seats use Agent subagents; Codex and `pi` seats use authenticated CLIs. Accepts an optional `opus`/`codex`/`local` override argument to restrict to a single seat. The local panelist auto-detects the loaded LMStudio model via `/api/v0/models` (override base URL with `FUSION_LMSTUDIO_URL`), never hardcoding a model id. Any unavailable seat (missing CLI, unloaded model, timeout) is dropped gracefully and the panel continues. Provenance is written to `~/.claude/fusion-runs/`, never committed. Ported from fusion-fable (MIT); the Gemini/`agy` seat and its PTY/bug-#76 workaround are intentionally dropped in favor of the local `pi`/LMStudio seat.

## Conventions

- `/fusion` panelists are subscription-only — Opus via Agent subagents, GPT-5.5 via authenticated `codex`, local via `pi`/LMStudio; no API keys anywhere
- `/fusion` runs the codex panelist with `--sandbox workspace-write` (never the banned `--dangerously-bypass-approvals-and-sandbox`); web search via `-c tools.web_search=true`
- `/fusion` auto-detects the loaded LMStudio model via `/api/v0/models` (override base URL with `FUSION_LMSTUDIO_URL`), never hardcoding a model id — same pattern as `/spec-review-local`
- `/fusion` provenance lives in `~/.claude/fusion-runs/`, never committed; any panelist seat degrades gracefully (missing CLI / unloaded model / timeout → dropped, panel continues)
- `/fusion` is a port of fusion-fable (MIT); the Gemini/`agy` seat and its PTY/bug-#76 workaround are intentionally dropped in favor of the local `pi`/LMStudio seat
