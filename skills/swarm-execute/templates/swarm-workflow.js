export const meta = {
  name: 'swarm-batch',
  description: 'Execute one batch of stories in parallel: Codex implements in worktrees, architect+QA reviews gate each story',
  phases: [
    { title: 'Implement', detail: 'one Codex-driven worker per story, each in its own worktree' },
    { title: 'Review', detail: 'architect + QA lenses per story, each review performed by Codex read-only and translated into a structured verdict' },
    { title: 'Remediate', detail: 'Codex fixes blockers inside the persisted worktree, then re-review' },
  ],
}

// args: {
//   batch: number,
//   baseBranch: string,        // feature branch the lead will merge into
//   baseSha: string,           // git rev-parse HEAD at batch start — reviewers diff against this
//   gates: string[],           // quality gate commands, run individually in order
//   e2eCommand?: string,       // present only if detected; workers NEVER run it (lead-only, final validation)
//   findingsDigest: string,    // lead-aggregated learnings from earlier batches ('' for batch 1)
//   projectContext: string,    // one-paragraph feature summary + source doc path if any
//   stories: [{ id, title, description, acceptanceCriteria: string[], notes,
//               filesCreate: string[], filesModify: string[], priority: number }],
// }

const IMPL_SCHEMA = {
  type: 'object',
  required: ['storyId', 'committed', 'branch', 'worktreePath', 'headSha', 'filesChanged', 'gates', 'summary', 'findings'],
  properties: {
    storyId: { type: 'string' },
    committed: { type: 'boolean' },
    branch: { type: 'string' },
    worktreePath: { type: 'string' },
    headSha: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    gates: { type: 'array', items: { type: 'object', required: ['command', 'passed'], properties: { command: { type: 'string' }, passed: { type: 'boolean' }, note: { type: 'string' } } } },
    summary: { type: 'string' },
    codexInvocations: { type: 'number' },
    findings: {
      type: 'object',
      required: ['decisions', 'errors', 'patterns'],
      properties: {
        decisions: { type: 'array', items: { type: 'string' } },
        errors: { type: 'array', items: { type: 'string' } },
        patterns: { type: 'array', items: { type: 'string' } },
      },
    },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['storyId', 'reviewer', 'verdict', 'summary', 'blockers', 'suggestions'],
  properties: {
    storyId: { type: 'string' },
    reviewer: { type: 'string', enum: ['architect', 'qa'] },
    verdict: { type: 'string', enum: ['pass', 'blocked'] },
    summary: { type: 'string' },
    blockers: { type: 'array', items: { type: 'object', required: ['file', 'issue', 'fix'], properties: { file: { type: 'string' }, line: { type: 'number' }, issue: { type: 'string' }, fix: { type: 'string' }, category: { type: 'string' } } } },
    suggestions: { type: 'array', items: { type: 'object', required: ['file', 'issue'], properties: { file: { type: 'string' }, line: { type: 'number' }, issue: { type: 'string' }, fix: { type: 'string' }, category: { type: 'string' } } } },
  },
}

if (typeof args === 'string') { args = JSON.parse(args) }
const gateList = args.gates.map((g, i) => `${i + 1}. \`${g}\``).join('\n')

function siblingSummary(story) {
  const others = args.stories.filter(s => s.id !== story.id)
  if (!others.length) return 'No other stories in this batch — you are the only worker.'
  return others.map(s => `- ${s.id}: ${s.title} — creates: ${s.filesCreate.join(', ') || '(none)'}; modifies: ${s.filesModify.join(', ') || '(none)'}`).join('\n')
}

function storyHeader(story) {
  return `**Story**: ${story.id} — ${story.title}
**Description**: ${story.description}

### Acceptance Criteria
${story.acceptanceCriteria.map(c => `- ${c}`).join('\n')}

### Notes
${story.notes || '(none)'}

### Planned files
CREATE: ${story.filesCreate.join(', ') || '(none)'}
MODIFY: ${story.filesModify.join(', ') || '(none)'}`
}

function implPrompt(story) {
  return `You are a swarm worker implementing exactly one user story in an isolated git worktree (your current working directory). Other workers implement other stories concurrently in their own worktrees.

# Division of labor — NON-NEGOTIABLE
ALL code-writing is delegated to the OpenAI Codex CLI. You never write or edit source files yourself. Your job is to drive Codex, verify its output, run quality gates, and commit. You may only touch files directly to resolve a trivial mechanical issue Codex repeatedly fails at (e.g. a one-line lockfile conflict) — and must record doing so in findings.errors.

# Assignment
${storyHeader(story)}

# Project context
${args.projectContext}

# Learnings from earlier batches
${args.findingsDigest || '(first batch — none yet)'}

# Concurrent siblings in this batch (do NOT touch their files)
${siblingSummary(story)}

# Procedure
1. Orient: read the existing code around the planned CREATE/MODIFY files. Note conventions, test layout, and anything in the learnings above that applies.
2. Drive Codex (foreground, sandboxed to this worktree; pass the prompt via stdin heredoc — robust for multi-line prompts):
   \`\`\`bash
   codex exec --sandbox workspace-write - <<'PROMPT'
   <implementation prompt>
   PROMPT
   \`\`\`
   Compose the implementation prompt yourself: include the story, acceptance criteria, the exact files to create/modify, the conventions you observed, an instruction to write tests first, and an instruction to LEAVE ALL CHANGES UNCOMMITTED — you commit, not Codex. Run it from the worktree root (your cwd). Codex's sandbox has NO network: if the story needs a new dependency, YOU run the package-manager install yourself in the worktree, then re-invoke Codex. Do NOT use --dangerously-bypass-approvals-and-sandbox, and never resume sessions (no \`codex exec resume\` / \`resume --last\`, no companion \`task --resume-last\` or \`--background\`).
3. Verify Codex actually changed something: \`git status --porcelain\` is non-empty OR \`git log ${args.baseSha}..HEAD --oneline\` shows new commits (Codex may commit despite instructions); the decisive check is \`git diff --name-only ${args.baseSha}\` (covers working tree + commits) being non-empty. A Codex run that returns advice without edits counts as a failed invocation — re-prompt with more explicit file-level instructions.
4. Run every quality gate INDIVIDUALLY, in order:
${gateList}
   On any failure, send the failing output back to Codex in a new \`codex exec --sandbox workspace-write\` invocation scoped to fixing that failure, then re-run ALL gates. Maximum 3 Codex fix invocations; if gates still fail, stop and report committed=false with the failure in findings.errors.
   ${args.e2eCommand ? 'NEVER run the e2e command (`' + args.e2eCommand + '`) — it is lead-only, final-validation-only.' : ''}
5. Commit on the worktree branch once all gates pass:
   \`git add <specific files>\` then \`git commit -m "<type>(<scope>): [${story.id}] <description>"\` (Conventional Commits, no AI-attribution footers).
6. Report via structured output: storyId="${story.id}", committed, branch (\`git rev-parse --abbrev-ref HEAD\`), worktreePath (\`pwd\` absolute), headSha (\`git rev-parse HEAD\`), filesChanged (from \`git diff --name-only ${args.baseSha}..HEAD\`), per-gate results, codexInvocations count, a one-paragraph summary, and findings (decisions made, errors hit + resolutions, codebase patterns discovered — these feed the next batch's workers).

# Rules
- One story only. Never touch sibling stories' files or anything outside this story's scope.
- All gates must pass before committing. committed=true means: work committed AND all gates green.
- Stay in this worktree. Never switch branches, never push, never merge.`
}

function reviewerPrompt(story, impl, reviewer, attempt) {
  const checklist = reviewer === 'architect'
    ? `Scope: conventions, architecture, security. Check for:
- Convention violations vs the surrounding codebase (naming, structure, import style, framework idioms)
- Missing or inconsistent error handling on new code paths
- Code duplication that should reuse existing helpers
- Needless complexity (layers, abstractions, options the story did not ask for)
- Security issues (injection, unvalidated input, secrets, unsafe defaults)
Do NOT review test adequacy or functional coverage — that is the QA reviewer's scope.`
    : `Scope: functional correctness and test quality. Test existence != test adequacy. Check:
- Enumerate every new/changed behavior in the diff; verify each has a test
- Edge cases and error paths: are failures, empty inputs, and boundaries tested?
- Assertion quality: do tests assert outcomes, or merely that nothing threw?
- Mock accuracy: do mocks match the real collaborators' contracts?
- Would the tests catch a plausible regression of this change?
Do NOT review conventions, naming, structure, or security — that is the architect's scope.`
  const outFile = `/tmp/swarm-review-b${args.batch}-${story.id}-${reviewer}-${attempt}.md`
  return `You are the ${reviewer.toUpperCase()} review driver for one story. The review itself is performed by the OpenAI Codex CLI — your job is to compose its prompt, run it, sanity-check its findings, and translate them into a structured verdict. You never review the code yourself except in the fallback below.

You are READ-ONLY with respect to the repository. You run in the main repository, NOT in the worker's worktree. Never modify any repo file anywhere (Codex writing ${outFile} is expected). Review attempt ${attempt} of 2.

# Story under review
${storyHeader(story)}

# Where the change lives
Persisted worktree: ${impl.worktreePath} (branch ${impl.branch}, HEAD ${impl.headSha}). Diff base: ${args.baseSha}.

# Procedure
1. Run Codex FROM the worktree (foreground, read-only sandbox, prompt via stdin heredoc; never resume sessions):
   \`\`\`bash
   cd "${impl.worktreePath}" && codex exec --sandbox read-only --output-last-message ${outFile} - <<'PROMPT'
   <review prompt>
   PROMPT
   \`\`\`
   Compose the review prompt yourself. It MUST contain:
   - The story, acceptance criteria, and planned files from the assignment above
   - Instructions to inspect the change via \`git diff ${args.baseSha}..HEAD\` (and \`--name-only\`) and to read full files for context
   - This checklist, verbatim:
${checklist}
   - Output rules: one finding per line, format \`SEVERITY | file:line | issue | concrete fix\` where SEVERITY is BLOCKER or SUGGESTION. BLOCKER only for issues a reasonable senior reviewer would refuse to merge; style nits are SUGGESTION. ${reviewer === 'qa' ? 'For missing coverage, the fix must state the specific test to write. ' : ''}Every fix must be concrete — never "needs fixing" without how. If nothing is found, output exactly NO FINDINGS.
2. Read ${outFile}. If it is missing or empty, re-run Codex once. If that also fails, perform the review YOURSELF with the same checklist (\`git -C "${impl.worktreePath}" diff ${args.baseSha}..HEAD\`; read full files via \`git -C "${impl.worktreePath}" show HEAD:<path>\`) and state in your summary that Codex was unavailable.
3. Sanity-check before adopting findings — Codex output is input, not verdict: discard any finding naming a file absent from \`git -C "${impl.worktreePath}" diff --name-only ${args.baseSha}..HEAD\` (unless you verify it is a genuine cross-file concern), and spot-check that each BLOCKER cites code that actually exists at the stated location. Drop anything you cannot verify.

# Verdict rules
- "pass": zero surviving blockers. Suggestions are informational only.
- "blocked": one or more blockers. Every blocker must name a file (and line where possible) and a CONCRETE fix${reviewer === 'qa' ? ' — for missing coverage, state the specific test to write' : ''} — never "needs fixing" without how.

Return structured output with storyId="${story.id}" and reviewer="${reviewer}".`
}

function remediationPrompt(story, impl, blockers) {
  return `You are fixing review blockers for one story. The implementation lives in a PERSISTED worktree — you are NOT isolated; you must operate on that exact directory.

Worktree: ${impl.worktreePath} (branch ${impl.branch})

# Division of labor — NON-NEGOTIABLE
ALL code-writing is delegated to the Codex CLI, invoked FROM the worktree:
\`\`\`bash
cd "${impl.worktreePath}" && codex exec --sandbox workspace-write - <<'PROMPT'
<fix prompt — instruct Codex to leave changes UNCOMMITTED; you commit, not Codex>
PROMPT
\`\`\`
You verify, run gates, and commit. You never edit source files yourself. Codex's sandbox has no network — run any needed package-manager command yourself. Never resume sessions (no \`codex exec resume\`, no companion \`task --resume-last\`/\`--background\`).

# Story (context only — do not expand scope)
${storyHeader(story)}

# Blockers to fix (fix ONLY these — ignore suggestions, refactor nothing else)
${blockers.map((b, i) => `${i + 1}. [${b.category || 'issue'}] ${b.file}${b.line ? ':' + b.line : ''} — ${b.issue}\n   Fix: ${b.fix}`).join('\n')}

# Procedure
1. Compose a Codex fix prompt listing each blocker with its file:line and required fix. Run it as above.
2. Verify changes landed (\`git -C "${impl.worktreePath}" status --porcelain\`).
3. Re-run ALL quality gates individually from the worktree:
${gateList}
4. Commit: \`git -C "${impl.worktreePath}" add <files>\` then commit message \`fix(<scope>): [${story.id}] address review blockers\`.
5. Report structured output: storyId="${story.id}", committed (true only if all blockers addressed AND gates green), branch, worktreePath, headSha, filesChanged (cumulative, \`git -C "${impl.worktreePath}" diff --name-only ${args.baseSha}..HEAD\`), gates, codexInvocations count, summary of what changed, findings (decisions/errors/patterns — use empty arrays where nothing applies).`
}

async function implementStory(story, attempt) {
  const impl = await agent(implPrompt(story), {
    label: `impl:${story.id}${attempt > 1 ? `#${attempt}` : ''}`,
    phase: 'Implement',
    isolation: 'worktree',
    schema: IMPL_SCHEMA,
    model: 'haiku', // babysitter role: Codex does the code-level thinking; the schema + procedure keep the driver on rails
  })
  return impl
}

function implOk(impl) {
  // Never trust the committed flag alone — cross-check the reported gate results.
  return Boolean(impl && impl.committed && impl.gates.every(g => g.passed))
}

async function runReview(story, impl, reviewer, tag, attempt) {
  // One retry if the reviewer agent dies — a missing verdict must never become a pass.
  let r = await agent(reviewerPrompt(story, impl, reviewer, attempt), { label: `${tag}:${story.id}#${attempt}`, phase: 'Review', schema: REVIEW_SCHEMA, model: 'haiku' })
  if (!r) {
    log(`${story.id}: ${reviewer} reviewer died on attempt ${attempt} — retrying once`)
    r = await agent(reviewerPrompt(story, impl, reviewer, attempt), { label: `${tag}:${story.id}#${attempt}-retry`, phase: 'Review', schema: REVIEW_SCHEMA, model: 'haiku' })
  }
  return r
}

async function runStory(story) {
  // Implement (1 retry on hard failure — fresh worktree; orphaned worktrees are reported, never reused)
  const orphans = []
  let impl = await implementStory(story, 1)
  let implAttempts = 1
  if (!implOk(impl)) {
    if (impl && impl.worktreePath && !orphans.includes(impl.worktreePath)) orphans.push(impl.worktreePath)
    log(`${story.id}: implementation attempt 1 failed — retrying in a fresh worktree`)
    impl = await implementStory(story, 2)
    implAttempts = 2
  }
  if (!implOk(impl)) {
    if (impl && impl.worktreePath && !orphans.includes(impl.worktreePath)) orphans.push(impl.worktreePath)
    return { storyId: story.id, status: 'failed', impl: impl || null, orphanedWorktrees: orphans, implAttempts, attempts: 0, reviews: [] }
  }

  // Review -> remediate (once) -> re-review. Max 2 review attempts.
  // Gate rules: a story passes ONLY when BOTH reviewers returned a verdict and BOTH verdicts are 'pass'.
  let attempt = 1
  while (true) {
    const [arch, qa] = await parallel([
      () => runReview(story, impl, 'architect', 'arch', attempt),
      () => runReview(story, impl, 'qa', 'qa', attempt),
    ])
    const reviews = [arch, qa].filter(Boolean)
    if (!arch || !qa) {
      return { storyId: story.id, status: 'blocked', impl, reviews, attempts: attempt, orphanedWorktrees: orphans,
        blockers: [{ file: '(review)', issue: `${!arch ? 'architect' : ''}${!arch && !qa ? ' and ' : ''}${!qa ? 'qa' : ''} reviewer died after retry — no verdict`, fix: 'lead must re-run the review or escalate; do not merge unreviewed' }] }
    }
    const blockedReviews = reviews.filter(r => r.verdict === 'blocked')
    if (blockedReviews.length === 0) {
      return { storyId: story.id, status: 'pass', impl, reviews, attempts: attempt, orphanedWorktrees: orphans }
    }
    const blockers = blockedReviews.flatMap(r => r.blockers)
    if (blockers.length === 0) {
      // 'blocked' verdict with no actionable blockers — remediation is impossible; escalate.
      return { storyId: story.id, status: 'blocked', impl, reviews, attempts: attempt, orphanedWorktrees: orphans,
        blockers: [{ file: '(review)', issue: `${blockedReviews.map(r => r.reviewer).join(', ')} returned a blocked verdict without actionable blockers`, fix: 'lead must inspect the review summaries and decide' }] }
    }
    if (attempt >= 2) {
      return { storyId: story.id, status: 'blocked', impl, reviews, attempts: attempt, blockers, orphanedWorktrees: orphans }
    }
    log(`${story.id}: ${blockers.length} blocker(s) — remediating in ${impl.worktreePath}`)
    const fix = await agent(remediationPrompt(story, impl, blockers), { label: `fix:${story.id}`, phase: 'Remediate', schema: IMPL_SCHEMA, model: 'haiku' })
    if (implOk(fix)) {
      impl = { ...impl, headSha: fix.headSha, filesChanged: fix.filesChanged, gates: fix.gates,
        codexInvocations: (impl.codexInvocations ?? 0) + (fix.codexInvocations ?? 0),
        findings: {
          decisions: [...impl.findings.decisions, ...fix.findings.decisions],
          errors: [...impl.findings.errors, ...fix.findings.errors],
          patterns: [...impl.findings.patterns, ...fix.findings.patterns],
        } }
    } else {
      return { storyId: story.id, status: 'blocked', impl, reviews, attempts: attempt, blockers, remediationFailed: true, orphanedWorktrees: orphans }
    }
    attempt++
  }
}

log(`Batch ${args.batch}: ${args.stories.length} stories, base ${args.baseSha.slice(0, 8)} on ${args.baseBranch}`)
// Positional mapping — a crashed runStory must surface as a failed story, never vanish from results.
const raw = await parallel(args.stories.map(s => () => runStory(s)))
const results = raw.map((r, i) => r ?? ({ storyId: args.stories[i].id, status: 'failed', impl: null, reviews: [], attempts: 0, implAttempts: 0, orphanedWorktrees: [], note: 'story pipeline crashed — check for stray worktrees' }))
const passed = results.filter(r => r.status === 'pass').length
log(`Batch ${args.batch} done: ${passed} pass, ${results.filter(r => r.status === 'blocked').length} blocked, ${results.filter(r => r.status === 'failed').length} failed`)
return { batch: args.batch, results }
