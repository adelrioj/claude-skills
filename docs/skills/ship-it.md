# `/ship-it`

Pure conductor that chains the existing units into one autonomous spec→PR pipeline. Six-step sequential process: hardens the spec via `/spec-review-codex`, writes the implementation plan, executes it via `/plan-to-dex`, opens a PR with `/commit-commands:commit-push-pr`, runs `/review-pr` and fixes CRITICAL/IMPORTANT findings (up to 3 passes); merging stays manual. A preflight (codex + dex on PATH, `pr-review-toolkit` + `commit-commands` plugins present via an on-disk command-file check, spec located) is the sole hard abort. The heavy Skill steps (1/2/4) run as **execute-and-report subagents** that return only a structured three-field contract, keeping raw codex/dex output out of the conductor's context; Steps 3/5/6 run in the main loop, with one boundary-verifier subagent after PR-review. Never halts on quality findings; records any leftover issues in a final report. Requires the `codex` and `dex` CLIs plus the `pr-review-toolkit` and `commit-commands` plugins.

## Conventions

- `/ship-it` is a pure conductor — it invokes spec-review-codex, writing-plans, plan-to-dex, /commit-commands:commit-push-pr, and /review-pr LIVE and duplicates none of their logic
- `/ship-it` is best-effort and never halts on quality; the only hard abort is a failed preflight; a hard failure that makes the next step impossible skips downstream steps and jumps to the final report — it never fabricates a downstream artifact (no empty PR)
- `/ship-it` keeps no state on disk except the final report, which is written /handoff-style to the OS temp dir, never the workspace
- `/ship-it` runs the heavy Skill steps (1/2/4) as execute-and-report subagents that return only a three-field contract (outcome/state/notes), keeping raw codex/dex output out of the conductor's context; Steps 3/5/6 run in the main loop. The zero-diff check is always verified against git in the conductor's own shell, never from a subagent summary, so a mis-summary can't fabricate a PR
