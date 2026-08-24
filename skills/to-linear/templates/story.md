<!--
An `optional` HTML-comment marker under a heading (see below) tells
/linear-groom-ticket's completeness lint that the section is not required. Linear
renders nothing for it and filling this template ignores it. Delete sections from
the ticket you write, never from this file.
-->

## User Story

As a **<role>**, I want **<capability>** so that **<outcome>**.

For tech debt, a refactor or a hardening task there is no role — replace this line with
one sentence: what should change, and why it cannot stay as it is.

## Context

Why this is worth doing now, and what exists today. Link the spec or design doc if one drove
this. Name the surfaces involved — backend, frontend, workers, infra — because a story that
silently spans three of them is the one that slips.

## Scope

What is in. Be concrete enough that someone can tell when they have drifted out of it.

**Out of scope:** what is deliberately not in this story, and where it lives instead.

## Acceptance Criteria

- [ ] …
- [ ] …

Each line should be checkable by someone who did not write the story. "Works correctly" is not
checkable; "returns 403 for a user without the `EDITOR` role" is.

## Technical Notes
<!-- optional -->

The constraints whoever picks this up must know before they start: the migration ordering,
the flag that gates it, the sibling module that also needs the change, the schema or contract
version dance if one is involved.

## Definition of Done

Tests, migration applied, flag state on each environment, docs updated — whatever "done"
actually requires here beyond the code merging.
