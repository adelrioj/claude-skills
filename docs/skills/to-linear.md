# `/to-linear`

Turns the current conversation into a properly-templated Linear ticket — a `bug` or `story` issue,
or an `epic` as a Linear **project** — filed on whichever team the current repo belongs to. Every
coordinate that was once one project's (workspace, team, label vocabulary, state names) is resolved
at run time, so the same skill installs into any repo against any workspace. Creates only; updating (`save_issue` with an `id`) and status
moves are out of scope. Drives the **Linear MCP**, the transport every Linear skill in this plugin now uses.

## Conventions

- **Neither workspace nor team is hardcoded, and they resolve differently on purpose.** The MCP has
  **no workspace parameter** — the token binds the session to one workspace — so the workspace is
  read back and confirmed (`$LINEAR_WORKSPACE` as an optional STOP-guard for checkouts that must
  only ever file into one place), never selected. Team *is* selectable, and resolves as
  invocation → `$LINEAR_TEAM` → repo docs/branch grep for `KEY-123` → `list_teams` + ask. `.envrc`
  (`export LINEAR_TEAM=MDZ`, `export LINEAR_WORKSPACE=…`) is the pin a repo carries; the grep is the
  fallback for repos that only document the convention in `CLAUDE.md`/git rules. Both are named in
  the pre-filing summary. Never auto-pick when several teams match — a workspace commonly carries a
  company-wide team alongside the engineering ones, and filing there puts the ticket in front of the
  wrong people
- **Status is resolved by `type`, never by name.** `list_issue_statuses` and take the status whose
  `type` is `backlog`. Team state names disagree (`Backlog` / `Todo` / `To Do`) and a hardcoded
  name is a silent failure. Setting it explicitly rather than omitting the field is deliberate: it
  guards against a team whose default state is not backlog. Filing into any other state is out of
  scope — triage moves tickets
- **Three types, two labels.** `bug` → `Bug`, `story` → `Feature`, `epic` → a project. There is no
  `improvement` type: the bug-vs-improvement judgement call was the thing people got wrong most, so
  tech debt / refactor / chore / hardening are **stories** and those words are story aliases. The
  test is "is it broken for someone today?" — if not, story. `story.md` and the skill both say to
  drop the "As a `<role>`" framing for a debt story rather than invent a user for it
- **One label, and only if it exists.** The type label is matched case-insensitively against
  `list_issue_labels`; if absent, file with no label and say so. **Never create a label** and no
  topical labels by default — a project-specific label vocabulary (`parsers`, `til`, `sas`, …) means
  nothing in another repo, and inventing one is how label sets rot. A topical label goes on only when
  the user names it and it already exists. Never set an import marker (`Migrated` and friends)
- **Templates are read, never recalled** — `templates/{bug,story,epic}.md`, plain markdown because
  that is what Linear descriptions accept. Every section the template defines stays, with an honest
  `TBD — …` placeholder where information is missing rather than invented detail. They were
  neutralized on import: `File.java` → `path/to/file.ext`, Flyway/TIL-spec examples → generic
  migration/contract wording, `team MDZ` → the resolved team
- **Titles are short because Linear derives `branchName` from them**, and the identifier in that
  branch is what links the PR back — a merged linked PR is what closes the issue. `priority` is set
  only when severity is clear from the conversation; unconfigured fields (estimates, cycles are off
  on some teams) are left alone rather than guessed at
- **A project means a finite body of work with a target date**, not a category bucket — standalone
  bugs and stories get no project. Epics file with `save_project` (short `summary` for list views,
  `content` for the body), then their child stories as issues carrying the project. No initiative
  link: the workspace does not use them
- **MCP only.** If the only Linear tools visible are `authenticate`/`complete_authentication`, ask
  the user to run `/mcp` and pick the Linear connector — never hand-roll GraphQL, there is no shared
  API key in any of these repos
- Linear writes are outward-facing, so the skill creates directly by default but shows the draft
  first when the user is mid-thought or the content is thin
- **`templates/` is shared with `/linear-groom-ticket`, and this skill owns it.** Grooming's
  `10-lint.py` reads `bug.md`/`story.md` from here rather than shipping its own copy, picking one
  per ticket from its type label. So a template edit changes what gets filed *and* what counts as
  a complete ticket — run `bash skills/linear-groom-ticket/scripts/tests/run.sh` after touching
  one. Two consequences for how the templates are written: a section is **required** unless its
  body carries an `optional` HTML-comment marker (Environment Details, Additional Context,
  Technical Notes carry it; everything else is required), and the headings are load-bearing —
  grooming matches them case- and emoji-insensitively but not by meaning, so renaming
  `Definition of Done` to `Definition of Done (DoD)` makes it a different section
- **Sibling skill, opposite verb.** `/to-linear` creates; `/linear-groom-ticket` grooms a ticket
  that already exists. Both write over the **Linear MCP**; they differ in shape, not transport —
  grooming *rewrites* human-authored text, so it runs an offline analysis pipeline behind an
  approval gate and a test suite, while filing is a single create call. Neither sets a workflow
  state after creation — grooming has no state-transition path at all, and this skill's one state
  write is the backlog status at creation time
- **Epics are not groomed.** `epic.md` becomes a Linear *project*, and grooming operates on
  issues, so that template has one consumer only
- **A repo carrying its own local `.claude/skills/to-linear` copy shadows this one.** If you find a
  divergent local copy, the plugin version is the maintained one — delete the local copy rather than
  patching both, since a ticket filed against one template shape and linted against another reports
  every section missing
