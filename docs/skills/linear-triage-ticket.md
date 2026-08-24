# `/linear-triage-ticket`

Takes one Linear ticket that `/linear-groom-ticket` has made coherent, reads the
repository the ticket is about, and produces an evidence-backed priority,
complexity rating and effort on the team's configured estimate scale. It
records the reasoning and which ticket claims were checked against code, then
writes only after an explicit gate. This page is the long-form *why*;
`skills/linear-triage-ticket/SKILL.md` is the procedure and the two must agree.

## 1. What it is and where it sits

The four-skill chain is:

```
/to-linear → /linear-groom-ticket → /linear-triage-ticket → /linear-spec-ticket
 ticket exists       ticket coherent       ticket sized             ticket has a spec
```

`/to-linear` creates the ticket, grooming makes its description coherent,
triage sizes and prioritises one ticket with evidence, and `/linear-spec-ticket`
writes its design spec. Triage does not groom, write a spec, or change workflow
state. Its output is priority, complexity and effort with the reasoning
attached and a record of verified and unverified ticket claims.

Runtime dependencies are the Linear MCP, `codex`, and `python3`; `orca` is
optional and is used only to write and verify an enabled native estimate.

## 2. Why the transport is split (D1)

Neither transport can honestly own the whole job:

| Capability | Linear MCP | `orca linear` |
|---|---|---|
| Read `priority` | yes (`{"value":4,"name":"Low"}`) | yes (bare int) |
| Read estimate back | no — the key is absent entirely | yes |
| Write priority | yes (`save_issue`) | yes (`priority set --to <name>`) |
| Write estimate | yes, but unverifiable | yes |
| Update a comment in place | yes (`save_comment` with `id`) | no — only `comment add` |

The Linear MCP is therefore the required transport for the ticket reads, the
priority write and the rationale comment. If those tools are absent, the
server is not connected: stop. `orca` is never a fallback for those channels.
The only `orca` capability is the estimate: resolve exactly one workspace by
matching the MCP team UUID, read the estimate baseline in that workspace,
write it after approval, and read it back. The two payloads must identify the
same issue by UUID and URL before that channel is enabled.

An MCP-only design could send an estimate but could not prove it landed. An
`orca`-only design would lose comment idempotency and inherit
`linear_write_unconfirmed` on every write. Splitting by capability preserves
the read-back where it is needed and in-place updates where they are needed.

The cost is real: two authentication surfaces, two failure modes, and behaviour
that differs between machines. A machine without a usable `orca` channel still
does the MCP-backed work and reports the effort in the comment; the estimate
degrades to unavailable rather than making the whole triage fail. The exact
reason is shown at the gate before approval.

## 3. Why configuration precedes write-then-verify (D2)

An issue's absent or `null` estimate does not reveal whether estimates are
disabled or merely unset. Before analysis, the skill resolves the team's
enabled state, scale, extended range, and allowed values from explicit team
metadata. The current MCP and Orca team payloads may omit those settings; when
they do, the caller confirms enabled/disabled and selects the exact configured
Linear scale. The skill never uses a write as a capability probe.

Effort is ranked on that scale: exponential, Fibonacci, linear, or T-shirt,
including extended values only when configured. T-shirt labels retain their
numeric API mapping. A disabled team still gets the effort in the rationale
comment, but the native write is skipped entirely.

For enabled teams, the workspace is resolved once and passed explicitly to
every `orca` command; `--current` is never relied on. The skill records the
estimate baseline, writes the configured numeric value after approval, and
immediately reads the issue again. There are three meaningful
outcomes:

| Read-back | Meaning |
|---|---|
| Equals the value sent | Estimate applied; report the value. |
| `null` or absent | Estimate not applied. The effort remains in the comment and the run succeeds. |
| A third value | Estimate state uncertain. Report both numbers verbatim and require manual resolution. Never auto-restore or retry with a guessed scale. |

A third value is indistinguishable from a concurrent edit or a configuration
change. Restoring the requested value could destroy someone else's write, so
uncertainty is never silently repaired. A successful write call is not proof;
the read-back is the verdict. If `orca` is unavailable or the identity check
fails, the estimate write is skipped and the gate says so.

## 4. Why the comment, never the description (D5)

Grooming replaces the entire description with the wave-2 editor's draft via
`save_issue`, against `skills/to-linear/templates/{bug,story}.md`. Those
templates have no Priority, Complexity or Effort section. `10-lint.py` only
reads the sections named by the template, so an extra `## Triage` heading is
invisible to linting. The next `/linear-groom-ticket` run would therefore
silently delete a triage stored in the description.

The durable homes are deliberately narrow:

| Where | Durability |
|---|---|
| Native `priority` | Survives grooming. |
| Native `estimate`, when it lands | Survives grooming. |
| One living comment | Survives grooming and carries complexity plus the full rationale. |
| Description | Destroyed by the next grooming run. |

Adding `## Triage` to `skills/to-linear/templates/story.md` is forbidden. The
file is shared by `/to-linear` and `10-lint.py`; changing it would make every
ticket already filed against the template report a new missing required section on its next grooming.
The shared template is not the place to add an optional triage payload.

The comment is MCP-only because only `save_comment` accepts a comment id and
can update it in place. The skill matches `<!-- linear-triage:v1 -->` only as
the normalized first line: zero matches creates, one updates that id, and more
than one stops for manual cleanup. `orca linear` offers only `comment add`, not
an update verb. That matters because grooming itself lists repeated audit
comments as an unfixed gap, while triage is expected to be rerun as the ticket
and code change.

## 5. Why triage uses `_REVIEW`, not groom's `_BUILD` (D11)

Triage is analysis: two read-only Codex analysts provide evidence, one for
impact and priority and one for complexity and effort. The skill uses the
`_REVIEW` pair:

```
-m "${CODEX_MODEL_REVIEW:-gpt-5.6-sol}" -c model_reasoning_effort="${CODEX_EFFORT_REVIEW:-high}"
```

`docs/codex-tuning.md` reserves `_REVIEW` for analysis and `_BUILD` for
code-writing. `/linear-groom-ticket` uses `_BUILD` as a deliberate documented
exception: its `gpt-5.6-luna`/high pair was validated in specific live runs,
including measured duplicate-analysis behaviour. That evidence does not exist
for this skill and must not be borrowed. The two skills therefore intentionally
disagree on the pin; documenting the divergence prevents a later reader from
"fixing" either one.

## 6. Why the rationale is English (D9)

The sibling rules operate on different outputs. `/linear-spec-ticket` creates
an attachment for the humans who requested a design and writes it in the
ticket's language. Triage writes ticket prose into a comment below a
description that grooming has already normalised to English. The repository
rule in `CLAUDE.md` is that ticket prose is English, so this comment is English
even when the source ticket was not. The distinction is principled, not an
accidental inconsistency between the Linear skills.

## 7. Known gaps

Written down rather than hidden. None blocks the ticket; all are real.

1. **"No Linear write before approval" is enforced by instruction, not by code.** Inherited whole from `/linear-spec-ticket`, whose docs concede *"the gate text is the whole protection"*. There is no `--dry-run`; the printed plan block (D10) is a mitigation, not an enforcement. A script pipeline would fix it and is explicitly deferred.

2. **An agent caller can approve its own gates.** Same gap the sibling records. The gate is written to be usable by an agent and offers no compensating inspection mechanism.

3. **Estimate settings may require caller confirmation.** The connected MCP and Orca payloads do not always expose enabled state, scale, or extended range. The skill pauses before analysis and asks instead of probing with a write.

4. **Configuration discovery is partly manual.** Until a transport exposes all team estimate settings, a caller can select the wrong scale. The gate prints the chosen scale and source so the choice is reviewable before any write.

5. **The skill behaves differently on two machines.** With `orca`, the estimate is written and proved; without it, it lives in the comment. Stated at the gate so it is never a surprise, but it is real variance in what the skill does.

6. **Cross-repo tickets need the right `cd`.** A team whose work spans two repos gives the skill no way to pick one for you; it can only make you confirm the one you are standing in. `--repo` is deferred.

7. **A triage goes stale invisibly.** An observed ticket changed workflow state with no activity-log entry at all. The provenance stamp (D12) lets a reader *notice* staleness; nothing detects it, and nothing expires a triage.

8. **No offline tests of the Linear-facing behaviour.** `tests/check-codex-knob.sh` pins the skill's textual contracts, compiles both embedded Python blocks, and exercises the watchdog's timeout and exit-passthrough for real — but like `/linear-spec-ticket`, nothing that touches Linear can be exercised without a live workspace. The failure-modes table, the FORBIDDEN list and the live runs in the DoD are what stand in for a suite — a real loss, not a simplification.

9. **The two Linear skills disagree on the codex pin** (`_REVIEW` here, `_BUILD` in groom) **and on output language** (English here and in groom, ticket-language in spec-ticket). Both divergences are argued in the docs page. A reader who finds only one of the two files will read it as an inconsistency.

10. **The staleness recheck is not atomic.** Step 6 re-reads and compares immediately before writing, which shrinks the race from minutes to seconds but cannot close it: Linear offers no compare-and-swap, so a concurrent edit landing inside the recheck→write window is still overwritten last-write-wins.

11. **Nothing prevents a future `## Triage` description section.** `10-lint.py` cannot see an extra section, so if someone adds one anyway it will be deleted by the next grooming with no warning and no suspicious diff. The prohibition lives in prose, in two files.

## 8. Explicitly deferred

| Deferred | Why |
|---|---|
| **A `--repo <path>` flag** (D4) | Doubles the preflight surface for a case `cd` solves. A team whose work spans more than one repo is handled by the origin-confirm gate; if triaging one project's tickets from another project's checkout becomes routine, revisit. |
| **A script pipeline with `--dry-run` and an offline suite** (D10) | The writes are small, scalar, recoverable, and individually provable by read-back, which is the guarantee scripts would buy. Revisit if triage ever gains a destructive write. The cost — no code-enforced approval gate — is in Known gaps. |
| **A `/blind-spot` pass inside the skill** | `/linear-spec-ticket` runs one because it authors a design document. Triage reads code to size work already described; a full unknown-unknowns pass would double the runtime for a judgement two codex analysts already cover. The report path/glob/stale-report hazards therefore do not arise here. |
| **Bulk or backlog triage** | Out of scope by the ticket. Every per-ticket guarantee in this design (origin confirm, gate, read-back) is per-ticket, and none of them survives a loop unattended. |
| **A run-directory namespace and the `$T` normalisation trap** (**L2**) | Largely moot — no scripts ship; the only on-disk state is the dispatch step's throwaway `mktemp -d` run dir, deleted by its EXIT trap. Recorded so a future script-bearing revision knows to use `linear-triage/`, never share `linear-groom/`, and always pass an explicit run dir. |
| **Reconciling the two skills' codex pins** (**M5**) | Both are correct for their own evidence. Documented divergence beats a re-tier that invalidates groom's validated live runs. |
