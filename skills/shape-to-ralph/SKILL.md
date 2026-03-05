---
name: shape-to-ralph
description: 'Convert sliced breadboard from shaping directly into Ralph prd.json for autonomous execution. Bypasses plan generation — shaping artifacts ARE the spec. Triggers on: shape to ralph, shaping to ralph, breadboard to ralph, slices to ralph.'
user-invocable: true
---

# Shape-to-Ralph Converter

Convert shaping artifacts (requirements, breadboard, slices) directly into Ralph's prd.json format. No intermediate plan needed — the shaped slices ARE the spec.

The shaping doc and slices doc are the **source of truth**. Do NOT re-interview the user or regenerate requirements.

---

## When to Use

- A `/shaping` session has produced a selected shape with breadboard
- The breadboard has been sliced into vertical increments (V1, V2...)
- Each slice has an affordance table and demo statement
- You want autonomous execution via Ralph (not interactive execution)

## When NOT to Use

- No shape selected yet — run `/shaping` first
- No breadboard — run `/breadboarding` first
- No slices — run slicing in `/breadboarding` first
- You want interactive execution — use `/shape-to-plan` instead

---

## The Job

1. Locate and validate shaping artifacts
2. Map slices to Ralph user stories
3. Detect slice dependencies
4. Validate story sizes
5. Inject quality gates into every story
6. Present review summary for user approval
7. Resolve branch name
8. Write files and show handoff message

**Output files:**

- `tasks/prd.json` — Ralph-compatible PRD
- `tasks/progress.txt` — Empty iteration log for Ralph to append to
- `tasks/findings.md` — Cross-iteration knowledge seeded with shape architecture

**Do NOT** run `./scripts/ralph.sh`. The user reviews prd.json first.

---

## Step 1: Locate and Validate Shaping Artifacts

If the user provided file paths as arguments, use them. Otherwise, scan `docs/shaping/` for files with `shaping: true` frontmatter.

You need two documents:

| Document        | Contains                                                    | How to Find                                             |
| --------------- | ----------------------------------------------------------- | ------------------------------------------------------- | --- | --- |
| **Shaping doc** | Requirements (R), selected shape, parts table, fit check    | Look for file with `## Requirements` and `## Fit Check` |
| **Slices doc**  | Slice summary, per-slice affordance tables, demo statements | Look for file with `## Slice Summary` or `              | V1  | `   |

They may be the same file if slicing was done inline.

**Validate the shaping doc:**

- [ ] Requirements (R) exist with at least R0
- [ ] A shape is selected (referenced as "selected" or has a `## Detail` section)
- [ ] Fit check exists showing selected shape passes all must-have R's
- [ ] Parts table exists for the selected shape

**Validate the slices doc:**

- [ ] Slice summary table exists (V1, V2... with mechanism and demo columns)
- [ ] Each slice has an affordance table (UI and/or Code affordances)
- [ ] Every slice has a demo statement
- [ ] No flagged unknowns remain in the selected shape's parts

If any check fails, STOP. Tell the user what's missing and which skill to invoke:

| Missing                           | Invoke                             |
| --------------------------------- | ---------------------------------- |
| No requirements or shapes         | `/shaping`                         |
| No fit check or no shape selected | `/shaping` (fit check phase)       |
| No breadboard                     | `/breadboarding`                   |
| No slices                         | `/breadboarding` (slicing section) |
| Flagged unknowns remain           | `/shaping` (spike to resolve)      |

---

## Step 2: Map Slices to Stories

For each slice in the slice summary:

| Shaping Artifact  | Ralph Story Field    | Mapping Rule                                     |
| ----------------- | -------------------- | ------------------------------------------------ |
| Slice number (V1) | `id`                 | `US-{NNN}` zero-padded (V1 = US-001)             |
| Slice name        | `title`              | Verbatim from slice summary                      |
| Demo statement    | `acceptanceCriteria` | Rewrite as machine-verifiable checks (see below) |
| Slice number      | `priority`           | Sequential, matching slice order                 |
| —                 | `passes`             | Always `false`                                   |
| Affordance table  | `notes`              | Formatted as story context (see below)           |

### Machine-Verifiable Acceptance Criteria

Each demo statement becomes 1-3 machine-verifiable criteria. Also extract testable behaviors from the slice's wiring:

| Demo statement                       | Machine-verifiable criteria                                                                                      |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| "Widget shows real data from API"    | `"API endpoint returns data matching expected schema"`, `"Component renders data from API response"`             |
| "Type 'dharma', results filter live" | `"Search input triggers filtered API call after debounce"`, `"Results list updates to show only matching items"` |
| "Scroll down, more items load"       | `"Scroll to bottom triggers next page fetch"`, `"New items append to existing list"`                             |
| "Refresh preserves search"           | `"Search state persists in URL query params"`, `"Page load with query params restores search results"`           |

**Rules:**

- Every criterion must be checkable by running a command or inspecting output
- Never use vague language ("works correctly", "is clean")
- Derive criteria from BOTH the demo statement AND the slice's wiring (Wires Out / Returns To)
- If a demo statement can't be made verifiable, flag it in the review summary

### Story Notes (from Affordance Tables + File Tables)

Format each slice's affordance table and file table into structured notes. Include file paths when the slices doc provides them — they save Ralph from wasting turns searching:

```
Files:
  CREATE: src/auth/decorators/required-scopes.decorator.ts — @RequiredScopes() decorator using SetMetadata
  MODIFY: src/auth/guards/client-auth.guard.ts — Set request.apiKeyScopes from validation result
  CREATE: src/auth/guards/scopes.guard.spec.ts — Unit tests for ScopesGuard

Affordances:
  UI: U1 (search input, type → N1), U2 (loading spinner, render)
  Code: N1 (activeQuery.next, call → N2), N2 (activeQuery subscription, observe → N3)

Wiring summary: User types in search input → triggers debounced query → calls search service → updates results display

Mechanism from shape: F3 (Search input with debounce, min 3 chars)

Source: Slice V2 from [shaping doc path]
```

**Include file paths when the slices doc has a "Files to create/modify" table.** Each Ralph iteration is a fresh AI instance with limited turns — known file paths prevent wasted exploration. If the slices doc does not have file tables, omit the Files section and let Ralph discover paths from the codebase.

---

## Step 3: Detect Slice Dependencies

Slices are already ordered by dependency (V1 before V2, etc.), but verify:

- Check each slice's Wires Out — if an affordance wires to something in a later slice, that's expected (stub/no-op until later)
- Check each slice's affordance table — if it references affordances from a previous slice, that dependency is correct
- If a later slice has NO dependency on any earlier slice, flag it — it might be parallelizable

Flag findings in the review summary:

```
Slice dependencies (from wiring analysis):
  V2 depends on V1: N2 (subscription) wires to N3 (performSearch, built in V1)
  V3 depends on V1: N12 (appendNextPage) wires to N4 (rawSearch, built in V1)
  V4 depends on V2: N10 (initializeState) wires to N1 (activeQuery, built in V2)
  V5 is independent: could run in parallel with V3-V4
```

---

## Step 4: Validate Story Sizes

After mapping, check each story:

- **Too small:** 1 acceptance criterion AND 1-2 affordances — suggest merge with adjacent slice
- **Too big:** >8 acceptance criteria OR >12 affordances — suggest split
- **Right size:** 3-8 affordances with 2-5 acceptance criteria

Flag in review summary. User decides whether to merge/split.

---

## Step 5: Inject Quality Gates

Auto-detect project quality tooling:

| File             | Check for                           | Inject                                         |
| ---------------- | ----------------------------------- | ---------------------------------------------- |
| `package.json`   | `typecheck`, `lint`, `test` scripts | `"pnpm typecheck passes"`, etc.                |
| `Makefile`       | `test`, `lint`, `typecheck` targets | `"make typecheck passes"`, etc.                |
| `pyproject.toml` | `pytest`, `ruff`, `mypy`            | `"pytest passes"`, etc.                        |
| `Cargo.toml`     | —                                   | `"cargo test passes"`, `"cargo clippy passes"` |

Append detected quality gates to **every** story's acceptance criteria.

Additionally, write the detected commands to the top-level `qualityGates` array in `prd.json` (e.g., `["pnpm typecheck", "pnpm lint", "pnpm test"]`). Ralph reads this array at runtime to know which commands to execute — **it does not hardcode any quality gate commands**.

**Why per-story AND top-level:** Acceptance criteria tell Ralph what "done" looks like for each story. The top-level `qualityGates` array tells Ralph exactly which shell commands to run. Both are needed — criteria for verification, commands for execution.

If no tooling detected, ask: `"What commands must pass for every story?"`

### E2E Command Detection

Also check for an E2E test command (used only by `/swarm-execute` at final validation, not per-story):

| File             | Check for                            | Write to prd.json               |
| ---------------- | ------------------------------------ | ------------------------------- |
| `package.json`   | `test:e2e` script                    | `"e2eCommand": "pnpm test:e2e"` |
| `Makefile`       | `test-e2e` or `e2e` target           | `"e2eCommand": "make e2e"`      |
| `pyproject.toml` | `e2e` or `playwright` in test config | `"e2eCommand": "..."`           |

If no E2E command detected, **omit** the `e2eCommand` field from `prd.json` entirely (do not set it to null or empty string).

---

## Step 6: Present Review Summary

Before writing any files, present:

```
Shape-to-Ralph Conversion Summary
-----------------------------------
Shaping doc: [path]
Slices doc: [path]
Selected shape: [shape letter + title]
Branch: [resolved branch name]

Requirements covered:
  R0: [text] — covered by V1, V2
  R1: [text] — covered by V3
  ...

Stories: N (from M slices)
Quality gates: [detected commands]

Slice dependencies:
  [V2 depends on V1: reason]
  [V5 is independent: could parallelize]

Flagged stories:
  [US-NNN - reason. Suggestion.]

Output files:
  tasks/prd.json      -> Ralph-compatible PRD
  tasks/progress.txt  -> iteration log (initially empty)
  tasks/findings.md   -> cross-iteration knowledge (seeded from shape)

Approve? [Y/adjust/cancel]
```

- **Y**: Write all files
- **adjust**: Ask which stories to modify, apply changes, re-present
- **cancel**: Abort without writing

---

## Step 7: Resolve Branch Name

Determine `branchName` in order:

1. If the user provided a branch name argument, use it
2. If the current git branch is not `main`/`master`, use the current branch
3. Otherwise, ask: `"What branch should Ralph work on?"`

Do not invent branch prefixes.

---

## Step 8: Write Files & Handoff

First, ensure the output directory exists: `mkdir -p tasks`

### Templates

Read the templates from this skill's `templates/` directory and populate them with values from the shaping artifacts:

| Template                 | Output               | Placeholders                                             |
| ------------------------ | -------------------- | -------------------------------------------------------- |
| `templates/prd.json`     | `tasks/prd.json`     | Project name, branch, quality gates, stories from slices |
| `templates/progress.txt` | `tasks/progress.txt` | Feature name, doc paths, shape info, date                |
| `templates/findings.md`  | `tasks/findings.md`  | Architecture decisions, requirements, slice mapping      |

Replace all `{{PLACEHOLDER}}` values with content derived from the shaping artifacts. One user story per slice — repeat the story object in `userStories` array for each slice.

### Seeding findings.md

The `findings.md` template has sections that must be seeded from shaping artifacts to give the first Ralph iteration a head start:

- **Architecture Decisions** — Extract key mechanisms from the shape's parts table with rationale from fit check notes
- **Requirements Context** — Copy the full requirements table from the shaping doc
- **Slice-to-Story Mapping** — One row per slice showing traceability to Ralph stories

Never invent decisions — only extract what the source documents state.

### Show Handoff

```
Converted [M] slices -> [N] user stories
  tasks/prd.json:      Ralph-compatible PRD
  tasks/progress.txt:  iteration log (initially empty)
  tasks/findings.md:   cross-iteration knowledge (seeded from shape)
  Shaping doc:         [path]
  Slices doc:          [path]
  Branch:              [resolved branch name]

Ready to run:
  ${CLAUDE_PLUGIN_ROOT}/skills/shape-to-ralph/scripts/ralph.sh
```

---

## Checklist Before Writing

- [ ] Shaping artifacts validated (R + selected shape + fit check + breadboard + slices)
- [ ] Every slice has machine-verifiable acceptance criteria
- [ ] Every R is traceable to at least one story
- [ ] Quality gates appended to every story
- [ ] Slice dependencies verified and documented
- [ ] Story sizes validated (none too small or too big without flagging)
- [ ] User approved the review summary
- [ ] Branch name resolved (not invented)
- [ ] tasks/progress.txt created with iteration log header
- [ ] tasks/findings.md seeded with shape architecture and requirements context
