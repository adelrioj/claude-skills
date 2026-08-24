<!--
This becomes a Linear PROJECT on the resolved team, not an issue.
  - the project's short description = the one-line goal below, plain text, shown in list views.
  - the project's `content` = everything from "## Goal" down, as markdown.
File it with the Linear MCP `save_project` tool (no `id` — that is what makes it a create); link an initiative only if the
workspace actually uses them — most do not.
-->

## Goal

One paragraph: what is true when this epic is done that is not true today. Written so a
non-engineer can tell whether it succeeded.

## Why now

The trigger. An incident, a customer commitment, a platform constraint, a cost. An epic without
a "why now" is a backlog item wearing a costume.

## Scope

What this epic covers.

**Out of scope:** the adjacent work people will assume is included. Name it, and say which epic
or ticket owns it instead.

## Breakdown

The stories this splits into. File these as issues with this project set once the project
exists.

- [ ] …
- [ ] …

If the breakdown has hard ordering (a migration before a read path, a parser change before an
enrichment one), say so here — Linear milestones can carry it if the ordering is load-bearing.

## Risks and unknowns

What could make this take twice as long, and what is still unknown at the time of writing. Be
honest about the parts nobody has looked at yet.

## Success criteria

How we will know it worked — the metric, the alert that stops firing, the manual check. Not
"the code is merged".
