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

Inheriting is not the same as being invisible: because the stock entry's tier lives outside the
skills, both `plan-to-dex`'s Step 5 confirmation and `ship-it`'s preflight read
`model_reasoning_effort` out of `~/.codex/config.toml` and print `codex (inherits <effort>)`. The
same pipeline genuinely does build at different depths on different machines — that is the design —
so the tier it actually used is stated up front and repeated in `ship-it`'s final report rather than
left for you to infer. No key in the config prints a bare `codex`; guessing a number there would be
worse than saying nothing.

**The model is never pinned.** Model ids age, and not every account is entitled to every model —
a hardcoded `-m gpt-5.6-sol` would be a bug six months from now on a machine that never opted in.
Set the model in `~/.codex/config.toml` as usual; the skills only ever touch the effort tier.

## Overriding

Two axes, two variables each. **Reach for the effort words first** — they retier every slot on their
axis at once, including the dex phases, and need no dex config work from you.

| Variable | Values | Effect |
|---|---|---|
| `CODEX_EFFORT_REVIEW` | `low` `medium` `high` `xhigh` | The review tier, everywhere: replaces `xhigh` on the direct-codex review call **and** selects `codex-<effort>` for `dex review` |
| `CODEX_EFFORT_BUILD` | `low` `medium` `high` `xhigh` | The build tier: selects `codex-<effort>` for `dex apply` (unset = the stock `codex` entry, inheriting your config). Also pins any future direct-`codex` build site |
| `DEX_CLI_BUILD` | a dex `clis` key | Names the `dex apply` backend outright. **Wins over `CODEX_EFFORT_BUILD`** |
| `DEX_CLI_REVIEW` | a dex `clis` key | Names the `dex review` backend outright. **Wins over `CODEX_EFFORT_REVIEW`** |

Each dex phase resolves in a single expansion, three-way — explicit entry, then effort word, then the
phase default:

```bash
apply  → ${DEX_CLI_BUILD:-codex${CODEX_EFFORT_BUILD:+-$CODEX_EFFORT_BUILD}}
review → ${DEX_CLI_REVIEW:-codex-${CODEX_EFFORT_REVIEW:-xhigh}}
```

| Set | spec review | dex `apply` | dex `review` |
|---|---|---|---|
| nothing | `xhigh` | `codex` (inherits config) | `codex-xhigh` |
| `CODEX_EFFORT_REVIEW=high` | `high` | `codex` | `codex-high` |
| `CODEX_EFFORT_BUILD=xhigh` | `xhigh` | `codex-xhigh` | `codex-xhigh` |
| `DEX_CLI_BUILD=my-entry` | `xhigh` | `my-entry` | `codex-xhigh` |

`plan-to-dex` Step 4 provisions whichever `codex-<effort>` entries a run resolves to, so an effort
word needs no setup. A `DEX_CLI_*` name is **not** auto-created — that entry is yours to define, and
inventing one would turn a typo into a silently-working backend. An effort word outside the four
values yields a name like `codex-fastest` that fails the same allowlist and surfaces as dex's
`unknown CLI`.

Set them in the shell that launches Claude Code — every Bash call and subagent inherits them.

```fish
set -gx CODEX_EFFORT_REVIEW high   # every review pass — spec review AND dex review — drops to high
set -gx CODEX_EFFORT_BUILD xhigh   # build as deep as review, without touching ~/.codex/config.toml
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

`plan-to-dex` Step 4 adds exactly the entries this run's two phases resolve to, if they are missing,
and never touches them again — the write is additive (jq creates `.clis` if absent, every other key
survives) and guarded, so your own `codex-xhigh` wins if you have one. The effort in `args` is derived
from the name, so `CODEX_EFFORT_BUILD=low` provisions a `codex-low` that really runs at `low`. With
nothing set it writes exactly one key, `codex-xhigh`, as it always did. To undo:
`jq 'del(.clis["codex-xhigh"])'`.

`--cli` resolves against the map keys, not PATH: `dex --cli bogus review` answers
`unknown CLI "bogus"; configured agents: amp, claude, codex, …` — that list is the key set, merged
with dex's built-ins.

> ⚠️ **Name any custom entry `codex-*`.** `plan-to-dex` and `ship-it` both guard against returning
> while a worker is still alive using `pgrep -f '[d]ex --cli codex|[c]odex exec'`. A cmdline of
> `dex --cli codex-xhigh apply` still contains the literal `dex --cli codex`, so the guard keeps
> working untouched. An entry named `deep` or `slow` would make the guard blind to its own worker —
> exactly the failure it exists to catch.

## Adding a new Codex call site

Pick the axis, then the backend, and copy the matching form:

```bash
# direct codex, review: pinned, overridable
codex exec -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-xhigh}" …
# direct codex, build: inherit unless the user says otherwise
codex exec ${CODEX_EFFORT_BUILD:+-c model_reasoning_effort="$CODEX_EFFORT_BUILD"} …
# through dex, build / review: the entry name carries the effort
dex --cli "${DEX_CLI_BUILD:-codex${CODEX_EFFORT_BUILD:+-$CODEX_EFFORT_BUILD}}" apply
dex --cli "${DEX_CLI_REVIEW:-codex-${CODEX_EFFORT_REVIEW:-xhigh}}" review
```

A dex site must also run Step 4's provisioning first, or the entry its knob names may not exist.

Type the fragment **literally** into the command — never resolve it to a concrete effort yourself.
If you ever add a `Workflow` script or a helper that builds the command in JavaScript, remember
those run in a sandbox with no `process.env`: emit the fragment as literal text (backslash-escaped
inside a template literal) and let the worker's own shell expand it.

Then run `bash tests/check-codex-knob.sh`. It asserts both expansion forms behave, that every
`codex exec` call site carries a knob, and that the dex provisioning snippet is additive and
idempotent.
