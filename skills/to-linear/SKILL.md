---
name: to-linear
description: 'Create a properly-templated Linear issue or epic-project (bug, story, epic) from the current conversation, on whichever team this repo files to. Use this WHENEVER the user wants to write, file, log, or create a ticket/story/bug/epic. Triggers on: write a bug ticket, file this as a bug, log a defect, create a user story, file tech debt, turn this into an epic, file a ticket, to linear, to-linear.'
user-invocable: true
---

# To Linear

Turn the current conversation into a properly-structured Linear ticket, filed on the right team
with the right template. **Workspace, team, labels and states are all resolved at run time**, so the
same skill works from any repo against any Linear workspace with no per-repo edit.

## Invocation

`/to-linear [type] [notes]` — or just describe the intent ("file this as a bug").

- **No type given** → infer from conversation context (see below).
- **Explicit type given** → always wins over inference.
- **Trailing notes** → free text to fold in (extra context, a title hint, scope notes). Optional.

## Resolving the type

Three types, deliberately. There is no separate "improvement" type: **tech debt, refactors and
hardening are stories**, filed with the story template.

| Type | Aliases (case-insensitive) |
|---|---|
| `bug` | bug, bugfix, bug report, defect, regression |
| `story` | story, user story, us, feature, improvement, tech debt, chore, refactor, hardening |
| `epic` | epic |

**Inferring** when no type is given:

- Something is broken *now* — a reproduced defect, an error, a regression → `bug`
- Anything else that should exist or should change: a requested capability, tech debt, a missing
  guard, a hardening task with no user-visible break → `story`
- A body of work spanning multiple stories, needing a target date → `epic`

The line is **"is it broken for someone today?"** — if not, it is a `story`, however
engineering-flavoured it sounds. If inference is genuinely ambiguous between two types, ask
rather than guess.

## Type → template + destination

| Type | Template | Becomes | Type label |
|---|---|---|---|
| `bug` | `templates/bug.md` | Linear issue | `Bug` |
| `story` | `templates/story.md` | Linear issue | `Feature` |
| `epic` | `templates/epic.md` | Linear **project** on the resolved team | — |

Templates live in `templates/` next to this file. Read the one you need with the Read tool and
fill its sections — they are plain markdown, which is exactly what Linear descriptions accept.
Do not reproduce a template from memory; read the file.

Keep every section the template defines. If a section has no information yet, write an honest
placeholder ("TBD — needs repro steps") rather than inventing detail. Add extra `##` sections
freely when the ticket needs them. For a story that is tech debt rather than a user-facing
capability, the "As a … I want …" line is often a poor fit — replace it with a one-line statement
of what should change and why, and keep every other section.

## Tooling: the Linear MCP

All reads and writes go through the **Linear MCP** tools (`save_issue`, `save_project`,
`list_teams`, `list_issue_labels`, `list_issue_statuses`, …). Load them with
ToolSearch if they are deferred.

**`save_issue` both creates and updates**, and `id` is the switch: omit it and the call creates a
new issue, pass it and the call updates that one. There is no separate create tool and no
separate update tool — the same holds for `save_project` and `save_comment`. A create with a stray `id` is an
overwrite of someone else's ticket, so the omission is load-bearing, not cosmetic.

If the only Linear tools visible are `authenticate`/`complete_authentication`, the MCP is not
authenticated — ask the user to run `/mcp` and select the Linear connector, then retry. Do not
fall back to hand-rolled GraphQL calls; there is no shared API key.

## Step 1: Resolve the destination (before drafting anything)

**Workspace — resolve it, never hardcode it, and always show it before writing.** The Linear MCP
takes **no workspace parameter**: the connector's token binds the session to exactly one workspace,
so the workspace is not something you select, it is something you *read back and confirm*. Resolve
in this order:

1. **`$LINEAR_WORKSPACE`** — `printenv LINEAR_WORKSPACE`. Set it (in `.envrc`, alongside
   `$LINEAR_TEAM`) in any checkout that must only ever file into one workspace. It is a **guard, not
   a selector**: if the connector is bound to a different workspace, that is a mismatch you STOP on,
   because there is no parameter with which to redirect the write.
2. **Otherwise read it back** from the connector — the workspace/organization on the `list_teams`
   result, or the host path of any returned issue `url` (`https://linear.app/<workspace>/…`).

**Name the resolved workspace in the pre-filing summary, every time**, and name the team beside it.
Multiple Linear connectors can be configured, and the failure this prevents is filing a correct
ticket into the wrong company's tracker — which no read-back after the fact undoes.

**Team** varies per repo. Resolve in this order and stop at the first hit:

1. **The invocation says so** — "file this on TRA", or a pasted issue/project URL. Explicit wins.
2. **`$LINEAR_TEAM`** — `printenv LINEAR_TEAM`. This is the per-checkout pin; repos set it in
   `.envrc` (`export LINEAR_TEAM=MDZ`).
3. **The repo's own docs** — the ticket-key convention is usually written down:
   `grep -rEn '\b[A-Z]{2,6}-[0-9]+\b|linear\.app' CLAUDE.md AGENTS.md README.md .claude/ docs/ 2>/dev/null | head -30`.
   A branch rule like `MDZ-123-short-description` names the key outright. Recent branches work
   too: `git branch -a --format='%(refname:short)' | grep -oE '[A-Z]{2,6}-[0-9]+' | sort -u`.
4. **Ask** — `list_teams`. Exactly one team ⇒ use it. Several ⇒ ask which, showing the keys.
   Do not pick the alphabetically-first one, and do not assume the company-wide team is the
   engineering one — workspaces commonly carry both, and filing into the company-wide team puts the
   ticket in front of the wrong people.

Then, on the resolved team, read what actually exists before writing:

- `list_issue_statuses` — find the status whose **`type` is `backlog`**. Match on the type, never
  on the name: teams disagree (`Backlog`, `Todo`, `To Do`) and hardcoding a name silently fails.
- `list_issue_labels` — confirm the type label exists (see below).

## Step 2: Labels — one, usually

- **Set exactly one type label**: `Bug` for a bug, `Feature` for a story. Match
  case-insensitively against what `list_issue_labels` returned. If neither exists on this team,
  file without a label and say so in your closing summary — **never create a label.**
- **No topical labels by default.** Add one only when the user explicitly names it, and only if
  it already exists. Never invent one.
- Never set an import/migration marker label (e.g. `Migrated`) — those mean "came from the old
  tracker", not "belongs to this ticket".

## Step 3: Filing an issue (bug / story)

Call `save_issue` **with no `id`** (that is what makes it a create) and:

- `team`: the team resolved in Step 1
- `title`: specific and one line — it carries the finding, not the area. "Proactive messages
  never receive platform_name, so the brand redactor no-ops" beats "Redactor bug". Keep it short:
  Linear derives `branchName` from it, and the identifier in that branch is what links the PR
  back (merging a linked PR is what closes the issue on most teams). Follow the repo's own git
  rules if it has one.
- `description`: the filled template markdown
- `labels`: the single type label from Step 2
- `state`: the `type: backlog` status resolved in Step 1

Rules:

- **The status is backlog and nothing else.** Never file straight into an in-progress or review
  state — triage moves tickets, this skill does not.
- **Only set a project when the work belongs to a real epic-project.** Standalone bugs and
  stories get no project. A project means "a finite body of work with a target date", not a
  category bucket.
- Set `priority` when severity is clear from the conversation; otherwise leave it off rather
  than guessing.
- If a field is not configured on the team (estimates and cycles are off for some), leave it
  alone rather than trying to set it.

Return the issue URL and identifier (e.g. `MDZ-231`) from the response.

## Step 4: Filing an epic (a project)

Call `save_project` **with no `id`** and:

- `team`: the team resolved in Step 1
- `name`: the epic title
- `summary`/`description` (the short field): the one-line goal, plain text, shown in list views
- `content`: the full markdown body from `templates/epic.md`
- `targetDate`: if one is known

Check whether the workspace uses initiatives before linking to one — it currently does not. Then
file the child stories as issues with the new project set on each, each one following Step 3.

## Notes

- This skill **creates**. Updating an existing issue is the same `save_issue` with an `id`; moving status afterwards
  is not this skill's job.
- Linear writes are outward-facing. Default to creating directly, but if the user is clearly
  mid-thought or the content is thin, show the draft first.
- **Making an existing ticket ready to work on is `/linear-groom-ticket`**, not this skill —
  it analyses one filed ticket, redrafts it against the team template, and applies the result
  after you approve. This skill only creates. `/to-linear` then `/linear-groom-ticket` is the
  normal path for a ticket filed from a thin conversation.
- Handing a ticket to an autonomous pipeline is `/spec-to-symphony`, not this skill — it has its
  own arming, branch and spec-path contract, and drives a Symphony pipeline rather than just filing.
  It also **continues** a ticket rather than creating one, so this skill is its upstream: `/to-linear`
  files, `/linear-groom-ticket` grooms, `/linear-spec-ticket` attaches the spec, `/spec-to-symphony`
  pushes it to the remote and arms.
