# Codex model and reasoning effort, per task

Several skills drive the `codex` CLI, either directly (`spec-review-codex`) or through `dex`
(`plan-to-dex`, and `ship-it` via both). Left alone, all of them inherit whatever single model and
effort sit in `~/.codex/config.toml` — the same setting for bulk code-writing and for adversarial
review, which are not the same job.

**This needs no setup.** The skills pin both the model and the tier themselves; the environment
variables below exist only for people who want something other than the built-in defaults.

## What the skills do out of the box

Two slots, two models. **The cheap fast model implements; the frontier model reviews. Both at
`high`.**

| Slot | Model | Effort | Where |
|---|---|---|---|
| Spec review | `gpt-5.6-sol` | `high` | `spec-review-codex` (`-m` + `-c`) |
| dex `review` | `gpt-5.6-sol` | `high` | `plan-to-dex` Step 6, via `--cli codex-gpt-5.6-sol-high` |
| dex `apply` | `gpt-5.6-luna` | `high` | `plan-to-dex` Step 6, via `--cli codex-gpt-5.6-luna-high` |

`gpt-5.6-luna` is "fast and affordable agentic coding"; `gpt-5.6-sol` is "latest frontier agentic
coding" (codex's own descriptions). Implementation is the bulk of the token spend and its work is
already specified by a hardened plan, so it runs on luna. Adversarial review is the pass whose entire
job is finding what you missed, so it runs on sol. Nothing inherits from `~/.codex/config.toml` any
more — the pipeline behaves identically on every machine.

### Pinning a model is a real tradeoff, taken deliberately

Slugs age, and not every account is entitled to every model, so a hardcoded `-m gpt-5.6-sol` *will*
eventually break on some machine — and codex fails on an unknown model with a message that reaches
nobody from inside a subagent. The mitigation is an entitlement gate, not a hope: `plan-to-dex` Step 4
and `ship-it` Step 0 both validate the resolved model **and its effort** against
`~/.codex/models_cache.json` — codex's own list of what this account can run — before anything is
spent. `gpt-5.6-luna` at `ultra` fails there even though both words are individually valid, because
luna caps at `max`.

That gate is **skipped, not failed, when the cache file is absent**: it is a cache, and treating a
cold one as "unentitled" would block a machine whose model is perfectly fine. Standalone
`spec-review-codex` has no gate at all — if codex rejects the model, re-run with
`CODEX_MODEL_REVIEW=<an entitled slug>`.

To see what your account has: `jq -r '.models[].slug' ~/.codex/models_cache.json`.

## Overriding

Two axes — **build** and **review** — three variables each. **Reach for the model and effort words
first**: they retier every slot on their axis at once, including the dex phases, and need no dex
config work from you.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `CODEX_MODEL_REVIEW` | any entitled slug | `gpt-5.6-sol` | The review model, everywhere: the direct-codex `-m` **and** the `codex-<model>-<effort>` entry `dex review` names |
| `CODEX_EFFORT_REVIEW` | `low` `medium` `high` `xhigh` `max` `ultra`¹ | `high` | The review tier, everywhere, same two places |
| `CODEX_MODEL_BUILD` | any entitled slug | `gpt-5.6-luna` | The build model: the `dex apply` entry, and any future direct-`codex` build site |
| `CODEX_EFFORT_BUILD` | as above¹ | `high` | The build tier, same places |
| `DEX_CLI_BUILD` | a dex `clis` key | — | Names the `dex apply` backend outright. **Wins over the `_BUILD` pair** |
| `DEX_CLI_REVIEW` | a dex `clis` key | — | Names the `dex review` backend outright. **Wins over the `_REVIEW` pair** |

¹ Which efforts exist is **per model**: sol and terra go to `ultra`, luna stops at `max`, the 5.4/5.5
family at `xhigh`. The entitlement gate checks the pair, so an effort the chosen model does not
support is caught before the run rather than mid-pipeline.

Each dex phase resolves in a single expansion, three-way — explicit entry, then model+effort, then the
phase default:

```bash
apply  → ${DEX_CLI_BUILD:-codex-${CODEX_MODEL_BUILD:-gpt-5.6-luna}-${CODEX_EFFORT_BUILD:-high}}
review → ${DEX_CLI_REVIEW:-codex-${CODEX_MODEL_REVIEW:-gpt-5.6-sol}-${CODEX_EFFORT_REVIEW:-high}}
```

| Set | spec review | dex `apply` | dex `review` |
|---|---|---|---|
| nothing | `sol` @ `high` | `codex-gpt-5.6-luna-high` | `codex-gpt-5.6-sol-high` |
| `CODEX_EFFORT_REVIEW=xhigh` | `sol` @ `xhigh` | `codex-gpt-5.6-luna-high` | `codex-gpt-5.6-sol-xhigh` |
| `CODEX_EFFORT_BUILD=xhigh` | `sol` @ `high` | `codex-gpt-5.6-luna-xhigh` | `codex-gpt-5.6-sol-high` |
| `CODEX_MODEL_BUILD=gpt-5.6-sol` | `sol` @ `high` | `codex-gpt-5.6-sol-high` | `codex-gpt-5.6-sol-high` |
| `DEX_CLI_BUILD=my-entry` | `sol` @ `high` | `my-entry` | `codex-gpt-5.6-sol-high` |

`plan-to-dex` Step 4 provisions whichever `codex-<model>-<effort>` entries a run resolves to, so a
model or effort word needs no setup. A `DEX_CLI_*` name is **not** auto-created — that entry is yours
to define, and inventing one would turn a typo into a silently-working backend. A model or effort the
account cannot run is refused by the entitlement gate, leaving no entry, so it surfaces as dex's
`unknown CLI` rather than as a config polluted with an unusable backend.

Set them in the shell that launches Claude Code — every Bash call and subagent inherits them.

```fish
set -gx CODEX_EFFORT_REVIEW xhigh          # deeper reviews — spec review AND dex review
set -gx CODEX_MODEL_BUILD gpt-5.6-sol      # implement on the frontier model too (costs more)
```

`ship-it` validates all six at preflight, because **everything here fails open**: `codex exec -m nope`
and `-c model_reasoning_effort=garbage` are both accepted until the run is underway, and
`dex --cli nope` prints `unknown CLI` and **still exits 0**. None of it is visible from inside a
subagent, which is exactly where these run.

## Why dex needs a provisioned entry

dex 0.4.9 has no `--model` flag and no effort option — `dex --help` lists only `--cli`, `--verbose`,
`--timeout`, `--update-prompts`, and there is no `CODEX_MODEL`-style environment variable on the
codex side either. The one lever is *which* `clis` entry `--cli` names, and those live in
`~/.config/dex/config.json`:

```json
"codex-gpt-5.6-sol-high": {
  "command": "codex",
  "args": ["exec", "--yolo", "--ephemeral", "--json", "-m", "gpt-5.6-sol", "-c", "model_reasoning_effort=high"],
  "stdin": true, "env": {}, "output_format": "json_nd"
}
```

The entry name embeds the full slug rather than a short alias (`codex-sol-high`) on purpose: no
mapping table to keep in sync, and the name states exactly what runs.

`plan-to-dex` Step 4 adds exactly the entries this run's two phases resolve to, if they are missing,
and never touches them again — the write is additive (jq creates `.clis` if absent, every other key
survives) and guarded, so your own entry of that name wins if you have one. Both the model and the
effort in `args` are derived from the name, so `CODEX_MODEL_BUILD=gpt-5.6-terra` provisions a
`codex-gpt-5.6-terra-high` that really runs terra. With nothing set it writes two keys,
`codex-gpt-5.6-luna-high` and `codex-gpt-5.6-sol-high`. To undo:
`jq 'del(.clis["codex-gpt-5.6-luna-high"], .clis["codex-gpt-5.6-sol-high"])'`.

`--cli` resolves against the map keys, not PATH: `dex --cli bogus review` answers
`unknown CLI "bogus"; configured agents: amp, claude, codex, …` — that list is the key set, merged
with dex's built-ins.

> ⚠️ **Name any custom entry `codex-*`.** `plan-to-dex` and `ship-it` both guard against returning
> while a worker is still alive using `pgrep -f '[d]ex --cli codex|[c]odex exec'`. A cmdline of
> `dex --cli codex-gpt-5.6-luna-high apply` still contains the literal `dex --cli codex`, so the guard keeps
> working untouched. An entry named `deep` or `slow` would make the guard blind to its own worker —
> exactly the failure it exists to catch.

## Adding a new Codex call site

Pick the axis, then the backend, and copy the matching form. **Both the model and the effort, always
— a site that pins only the effort silently reverts to the machine's model.**

```bash
# direct codex, review
codex exec -m "${CODEX_MODEL_REVIEW:-gpt-5.6-sol}" -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-high}" …
# direct codex, build
codex exec -m "${CODEX_MODEL_BUILD:-gpt-5.6-luna}" -c model_reasoning_effort="${CODEX_EFFORT_BUILD:-high}" …
# through dex: the entry name carries both
dex --cli "${DEX_CLI_BUILD:-codex-${CODEX_MODEL_BUILD:-gpt-5.6-luna}-${CODEX_EFFORT_BUILD:-high}}" apply
dex --cli "${DEX_CLI_REVIEW:-codex-${CODEX_MODEL_REVIEW:-gpt-5.6-sol}-${CODEX_EFFORT_REVIEW:-high}}" review
```

A dex site must also run Step 4's provisioning first, or the entry its knob names may not exist. A new
*pinned-model* site should carry the entitlement gate too, or it will fail with codex's own unhelpful
error on a machine that lacks the slug.

Type the fragment **literally** into the command — never resolve it to a concrete model or effort
yourself. If you ever add a `Workflow` script or a helper that builds the command in JavaScript,
remember those run in a sandbox with no `process.env`: emit the fragment as literal text
(backslash-escaped inside a template literal) and let the worker's own shell expand it.

Then run `bash tests/check-codex-knob.sh`. It asserts the four expansion forms behave, that every
`codex exec` call site pins **both** model and effort, that every dex resolution site uses the
identical fragment (partial updates are the drift that has actually happened), that provisioning is
additive/idempotent and derives args from the entry name, that the entitlement gate refuses an
unrunnable pair while a cold cache skips it, and that the two pinned defaults are entitled on the
machine running the test.
