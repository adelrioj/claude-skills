# Codex model and reasoning effort, per task

Several skills drive the `codex` CLI, either directly (`spec-review-codex`) or through `dex`
(`plan-to-dex`, and `ship-it` via both). Left alone, all of them inherit whatever single model and
effort sit in `~/.codex/config.toml` — the same setting for bulk code-writing and for adversarial
review, which are not the same job.

**This needs no setup.** The skills pin the tier themselves; the environment variables below exist
only for people who want something other than the built-in defaults.

## What the skills do out of the box

| Slot | Default | Where |
|---|---|---|
| Spec review | `-c model_reasoning_effort=xhigh` | `spec-review-codex` |
| dex `review` | `--cli codex-xhigh` (auto-provisioned) | `plan-to-dex` Step 6 |
| dex `apply` | `--cli codex` (the stock entry) | `plan-to-dex` Step 6 |

The asymmetry is deliberate. **Review is pinned up; build is left alone.** Pinning review at `xhigh`
can only improve a pass whose entire job is finding what you missed, and it makes the skills behave
the same on every machine. Pinning *build* would mean silently overriding how someone's code gets
written — a downgrade for anyone whose config says `xhigh`, an upgrade nobody asked to pay for for
anyone whose config says `low`. So build inherits, and the knob is there if you want otherwise.

**The model is never pinned.** Model ids age, and not every account is entitled to every model —
a hardcoded `-m gpt-5.6-sol` would be a bug six months from now on a machine that never opted in.
Set the model in `~/.codex/config.toml` as usual; the skills only ever touch the effort tier.

## Overriding

| Variable | Values | Effect |
|---|---|---|
| `CODEX_EFFORT_REVIEW` | `low` `medium` `high` `xhigh` | Replaces the `xhigh` default on every direct-codex review call |
| `CODEX_EFFORT_BUILD` | `low` `medium` `high` `xhigh` | Pins effort for code-writing (unset = inherit config). **No call site uses it today** — every code-writing path now goes through `dex apply`, so reach for `DEX_CLI_BUILD` instead. Kept for the next direct-`codex` build site; `ship-it` still validates it |
| `DEX_CLI_BUILD` | a dex `clis` key | Backend for `dex apply` (default `codex`) |
| `DEX_CLI_REVIEW` | a dex `clis` key | Backend for `dex review` (default `codex-xhigh`) |

Set them in the shell that launches Claude Code — every Bash call and subagent inherits them.

```fish
set -gx CODEX_EFFORT_REVIEW high   # make every review pass cheaper than the xhigh default
```

`ship-it` validates these at preflight, because both backends fail open on a bad value: codex
accepts a garbage effort string without complaint, and `dex --cli nope` prints `unknown CLI` and
**still exits 0**. Neither is visible from inside a subagent.

## Why dex needs a provisioned entry

dex 0.4.9 has no `--model` flag and no effort option — `dex --help` lists only `--cli`, `--verbose`,
`--timeout`, `--update-prompts`, and there is no `CODEX_MODEL`-style environment variable on the
codex side either. The one lever is *which* `clis` entry `--cli` names, and those live in
`~/.config/dex/config.json`:

```json
"codex-xhigh": {
  "command": "codex",
  "args": ["exec", "--yolo", "--ephemeral", "--json", "-c", "model_reasoning_effort=xhigh"],
  "stdin": true, "env": {}, "output_format": "json_nd"
}
```

`plan-to-dex` Step 4 adds exactly that key if it is missing, and never touches it again — the write
is additive (jq creates `.clis` if absent, every other key survives) and guarded, so your own
`codex-xhigh` wins if you have one. To undo: `jq 'del(.clis["codex-xhigh"])'`.

`--cli` resolves against the map keys, not PATH: `dex --cli bogus review` answers
`unknown CLI "bogus"; configured agents: amp, claude, codex, …` — that list is the key set, merged
with dex's built-ins.

> ⚠️ **Name any custom entry `codex-*`.** `plan-to-dex` and `ship-it` both guard against returning
> while a worker is still alive using `pgrep -f '[d]ex --cli codex|[c]odex exec'`. A cmdline of
> `dex --cli codex-xhigh apply` still contains the literal `dex --cli codex`, so the guard keeps
> working untouched. An entry named `deep` or `slow` would make the guard blind to its own worker —
> exactly the failure it exists to catch.

## Adding a new Codex call site

Pick the axis and copy the matching form:

```bash
# review: pinned, overridable
codex exec -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-xhigh}" …
# build: inherit unless the user says otherwise
codex exec ${CODEX_EFFORT_BUILD:+-c model_reasoning_effort="$CODEX_EFFORT_BUILD"} …
```

Type the fragment **literally** into the command — never resolve it to a concrete effort yourself.
If you ever add a `Workflow` script or a helper that builds the command in JavaScript, remember
those run in a sandbox with no `process.env`: emit the fragment as literal text (backslash-escaped
inside a template literal) and let the worker's own shell expand it.

Then run `bash tests/check-codex-knob.sh`. It asserts both expansion forms behave, that every
`codex exec` call site carries a knob, and that the dex provisioning snippet is additive and
idempotent.
