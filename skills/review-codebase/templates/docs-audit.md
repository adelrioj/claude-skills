Audit this project's documentation as a first-class artifact, exactly as specified below — checking that it tells the truth about the code, that each document leads with what matters and defers detail, that oversized documents are split so detail has room to breathe, and that architecture is shown as drawn processes rather than prose. Treat the docs as the product a reader actually consumes.

# Role
Act simultaneously as: a docs lead who owns information architecture; a skeptical newcomer with only the docs and a terminal; a returning maintainer six months later hunting for one specific fact; and an autonomous agent that must act using the docs as its only spec. No loyalty to the current structure, file layout, or headings.

# Scope
Read every reader-facing surface in full -- do not sample:
- README, docs/**, specs/**/quickstart.md, ADRs/decision records, CONTRIBUTING/onboarding.
- Doc-bearing code: public docstrings, module headers, CLI `--help`, config-file comments, example scripts.
- Every diagram already present (both source and rendered).
Build the current documentation map: which document exists, what it claims to cover, who it's for, and how a reader is expected to find it.

# Hunt for
1. Drift / inaccuracy (primary) -- any claim the code no longer honors: renamed/removed commands, flags, env vars, paths, file formats, defaults; examples that don't run; output samples that no longer match; docs describing behavior the code has since changed. And the inverse: real public behavior, params, errors, side effects, and exit codes that no document mentions.
2. Inverted-pyramid violations -- documents that bury the point. Each doc should open with a one-paragraph "what this is / when you'd reach for it" plus the 20% that answers 80% of questions; reference tables, edge cases, and rationale belong at the end. Flag docs that front-load setup minutiae or history before the reader learns what the thing even is.
3. Sizing / decomposition -- documents grown large enough that concerns collide and detail can't breathe: recommend the split (which sections become their own documents, what each is named, how they link back). Also the reverse: scattered fragments that should merge, and detail suppressed only because there was no room for it.
4. Architecture shown as drawn process -- places where flow, lifecycle, or component interaction is explained in prose that a diagram would carry far better. Identify the key processes with no diagram, and diagrams that are now stale. Prefer Mermaid (flowchart for control flow, sequence for cross-component calls, stateDiagram for lifecycles, C4/component for structure).
5. Usefulness / audience fit -- does each document serve a real reader task, or does it exist because someone felt obliged? Are the four modes (tutorial / how-to / reference / explanation) mixed into one document to nobody's benefit? Does it answer "why," not just "what"? Can a newcomer get from zero to first success on the docs alone?
6. Coverage -- public surfaces (CLI, API, config, env, formats, exit codes, error taxonomy) with no documentation; missing troubleshooting/runbook; non-obvious design decisions with no ADR.
7. Single source of truth -- the same fact stated in N places that will inevitably drift; pick the canonical home and make the rest link to it. Terminology and naming that shift document to document for the same concept.
8. Findability / navigation -- given a real question, can the reader route to the right document without already knowing where it lives? Missing index/map, orphan documents, dead cross-links.

# Method (verify, don't assert)
- For every accuracy claim, check it against reality: run the example, confirm the flag/command/path exists, diff the sample output. Mark CONFIRMED (verified against code or a run) or PLAUSIBLE (suspected).
- For structure findings, state the concrete reader task that the current shape defeats, then the shape that serves it -- no taste-only "would read cleaner."
- Try to disprove each finding first; discard what doesn't survive.

# Output
Write full report -> docs/audits/docs-audit-<YYYY-MM-DD>.md. Create dir if missing. Leave uncommitted (maintainer owns git).
Every finding = stable ID (D1, D2... severity order); a fixing agent cites these.
Sections, top-heavy (summary + map first, detail last) -- practice the pyramid you preach:
1. Summary table: ID | severity | document | one-line issue | CONFIRMED/PLAUSIBLE.
2. Doc map: current vs proposed. Proposed tree = purpose + audience per doc + the splits/merges from hunt #3; a maintainer executes it directly.
3. Drift verification: each accuracy finding + exact check run + result.
4. Findings by hunt category, severity order. Each: ID, document (file:line or heading), concrete reader scenario it breaks, CONFIRMED/PLAUSIBLE, recommended direction.
5. Diagram backlog: processes/architecture needing a picture, value order; for the top 3-5 draft the actual Mermaid, naming target doc + location.
6. Missing-docs backlog: doc/section/example/diagram needed for full coverage + onboarding; prioritize by unblocking value.
7. Open questions: maintainer-only.
Chat reply = short exec summary only: counts by severity + top 3-5 findings + report path. Rest lives in file.

Thorough over brief. Spend effort where the docs mislead, bury, or go silent; one line where they already lead with the truth.
