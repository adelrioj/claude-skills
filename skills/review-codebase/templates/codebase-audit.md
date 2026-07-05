Perform an exhaustive, adversarial audit of this entire codebase -- surfacing not just defects but design incoherences, unexpected affordances, doc drift, and mismatches between what the code invites me to do and what it actually does.

# Role
Act simultaneously as senior staff engineer, skeptical first-time API consumer, and adversarial reviewer. No loyalty to the current design. Understand the system deeply enough to challenge it, not merely validate it.

# Scope
Read the codebase in full -- do not sample. Build a model of:
- Entry points and real (not documented) execution paths.
- Module boundaries and the contracts between them (explicit and implied).
- Data models, invariants, and where they're actually enforced vs. assumed.
- External surfaces: APIs, CLIs, config, env vars, file formats, network calls.
- The docs/onboarding path a newcomer would actually follow.

# Hunt for (go beyond bugs)
1. Correctness -- logic errors, races, off-by-one, unhandled edges, silently swallowed failures, wrong error propagation.
2. Alternative/unintended paths -- second call? concurrent calls? empty/null/huge input? partial failure mid-op? retries? the "holding it wrong" path?
3. Incoherences -- names that lie about behavior, two modules solving one problem differently, config honored here and ignored there, duplicated sources of truth that can drift, dead code, contradictory defaults.
4. Affordance mismatches -- "I expected to do X this way but can't, or it does something else." Where does the API shape promise a capability the code doesn't deliver? Where is the easy path also the dangerous one?
5. Missing functionality -- things a reasonable user expects (validation, idempotency, cleanup, observability, cancellation, timeouts) but that are absent.
6. Boundary & safety -- leaky abstractions, invariants in the wrong layer, trust in unvalidated input crossing a boundary; injection, path traversal, unbounded growth, resource leaks, missing authz, exposed secrets -- only where real.
7. Documentation -- README/docstrings/comments that are wrong, stale, or contradict the code; undocumented public behavior, params, errors, or side effects; examples that wouldn't run; missing "why" behind non-obvious decisions.
8. Developer experience -- can a newcomer build, run, test, and debug from the docs alone? Confusing errors, silent misconfig, missing types/CI/tests, setup footguns, high-friction workflows.

# Method (adversarial, then verify)
- Per area, state how it SHOULD behave, then read to confirm or refute. Flag every expectation-vs-reality gap.
- Trace the top critical paths end-to-end, quoting the lines that matter. Check every doc example/command against the code.
- Every finding needs a concrete scenario: specific inputs/state -> the wrong or surprising result. No vague "could be improved."
- Mark each finding CONFIRMED (traced) or PLAUSIBLE (suspected). Try to disprove yourself first; discard findings that don't survive scrutiny.

# Output
Write full report -> docs/audits/codebase-audit-<YYYY-MM-DD>.md. Create dir if missing. Leave uncommitted (maintainer owns git).
Every finding = stable ID (C1, C2... severity order); a fixing agent cites these.
Sections, top-heavy (summary + map first, detail last):
1. Summary table: ID | severity | area | one-line issue | file:line | CONFIRMED/PLAUSIBLE.
2. System map: architecture, real execution paths, key invariants -- so I can check your understanding.
3. Findings by hunt category, severity order. Each: ID, file:line, one-line issue, concrete failure/surprise scenario (inputs/state -> wrong result), CONFIRMED/PLAUSIBLE, recommended direction.
4. Design tensions: 3-5 deepest structural issues (the approach is wrong, not a line); each with the alternative you'd weigh.
5. Expectation gaps: short "expected X, found Y" list for affordance/docs/DX.
6. Open questions: what code alone can't resolve; maintainer answers.
Chat reply = short exec summary only: counts by severity + top 3-5 findings + report path. Rest lives in file.

Be thorough over brief. Prioritize insight density and specificity over reassurance. Where something is sound, say so once and move on -- spend your effort where it isn't.
