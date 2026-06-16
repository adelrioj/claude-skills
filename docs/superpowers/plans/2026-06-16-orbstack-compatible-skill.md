# /orbstack-compatible Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/orbstack-compatible` skill that transforms an arbitrary Docker Compose project to use OrbStack routable domains, eliminating host-port collisions across worktrees/projects.

**Architecture:** A single self-contained `skills/orbstack-compatible/SKILL.md` defining a linear, autonomous transform (detect → inventory → transform → guardrails → verify). The deliverable is the markdown instruction file itself; "implementation" is authoring that file plus wiring it into the repo's docs/manifests. No helper scripts or reference docs.

**Tech Stack:** Claude Code plugin skill (markdown + YAML frontmatter); the skill's runtime targets `docker` / `docker compose` and OrbStack on macOS/Linux.

**Source spec:** `docs/superpowers/specs/2026-06-16-orbstack-compatible-skill-design.md` — read it before starting; decisions D1–D4 and the verified OrbStack facts are binding.

---

## File Structure

- **Create** `skills/orbstack-compatible/SKILL.md` — the entire skill (frontmatter + procedure). One responsibility: guide the OrbStack transform.
- **Modify** `README.md` — add the skill's one-line entry to the `## Skills` list.
- **Modify** `CLAUDE.md` — add a `### /orbstack-compatible` subsection under `## Skills`, and the relevant `## Key Conventions` bullets.
- **Modify** `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` — refresh the prose `description` to mention the new skill.

No code modules, so verification is: frontmatter validity, name/dir match, grep-based content checks, a `skill-creator` triggering eval, and a manual dry-run against the `payments-api` reference.

---

## Task 1: Create the skill file

**Files:**
- Create: `skills/orbstack-compatible/SKILL.md`

- [ ] **Step 1: Define the acceptance check (what "done" means for this file)**

The file must: live at `skills/orbstack-compatible/SKILL.md`; have valid YAML frontmatter with `name: orbstack-compatible` (matching the directory), `user-invocable: true`, and a trigger-rich `description`; and contain the five phases plus the four caveats. These are checked in Step 3.

- [ ] **Step 2: Write the file**

Create `skills/orbstack-compatible/SKILL.md` with EXACTLY this content:

````markdown
---
name: orbstack-compatible
description: "Use when a Docker Compose project should stop colliding on host ports across git worktrees or separate projects, by switching containerized services to OrbStack routable domains instead of published host ports. Edits docker-compose and local env files directly, then verifies live. Requires OrbStack as the active Docker engine (aborts otherwise). Triggers on: make orbstack compatible, orbstack migrate, fix docker port collisions, eliminate docker port collisions across worktrees, orbstack ports, make project orbstack-compatible."
user-invocable: true
---

# Make a Project OrbStack-Compatible

Eliminate Docker **host-port collisions** across git worktrees and separate projects by
moving containerized services off published host ports and onto OrbStack's routable
per-project domains (`<service>.<project>.orb.local`). A published host port is global
singleton state — only one container can bind `5432` at a time. OrbStack gives every
container a routable IP and DNS name, so the port mapping (and the collision class)
disappears instead of being dodged with offsets.

**Scope:** containerized Compose services only. Host-run dev servers (Node/Next on
3000/3001/…) are out of scope — OrbStack cannot route to host processes (see Phase 4,
document-only).

---

## The Job

1. **Detect** — confirm OrbStack is the active Docker engine (abort with setup guidance otherwise).
2. **Inventory** — find compose files, published ports, env connection vars, worktree scripts.
3. **Transform** — strip `ports:` from base compose, add an opt-in ports overlay, rewrite local env URLs to domains.
4. **Guardrails** — surface the four caveats; flag hardcoded hosts; document host-port residue.
5. **Verify** — bring services up under OrbStack and connect via domain; report and show the diff.

This skill runs autonomously and edits files directly. Re-running on an
already-transformed repo is a no-op (Phase 3 checks for it).

---

## Phase 1 — Detect (hard prerequisite)

OrbStack must be the active Docker engine. Check:

```bash
docker info 2>/dev/null | grep -qi 'orbstack' && echo OK || echo MISSING
```

If `MISSING` (or `docker` is absent), **abort without editing anything** and tell the user:

> OrbStack is not the active Docker engine, so the live transform/verify can't run.
> Install it (`brew install orbstack`) and make it the active engine (open the OrbStack
> app, or run `orb start`), then re-run this skill. OrbStack is macOS/Linux only and is
> free for personal use, paid for commercial use.

Do not offer to install it automatically — engine choice is a per-developer, machine-level
decision.

---

## Phase 2 — Inventory

Build a picture of the project before touching it.

1. **Compose files:** find all of them, including profiles and existing overlays:

   ```bash
   ls docker-compose*.y*ml compose*.y*ml 2>/dev/null
   ```

2. **Published ports:** Read each compose file. For every service, record its `ports:`
   mappings as `host:container` (resolving `${VAR:-default}` to note both the env var and
   the default). A service with no `ports:` is internal-only — leave it untouched.

3. **Env connection vars:** find env files (`.env*`, `*.env`) and the connection
   variables they set — `DATABASE_URL`, `REDIS_URL`, `*_HOST`/`*_PORT` pairs, S3/MinIO
   endpoints, etc. Note which host (`localhost`/`127.0.0.1`/a service name) and which port
   each points at, so Phase 3 can rewrite them.

4. **Worktree/port script:** look for a `cw.sh`-style script (often under `.claude/` or
   `scripts/`) that computes per-worktree port offsets and writes env files. Do not edit
   it — note it for the Phase 4 document-only guidance.

Report the inventory to the user, then proceed (no approval gate — this skill is autonomous).

---

## Phase 3 — Transform (edit directly)

**Idempotency guard:** if the base compose already has no `ports:` and a
`docker-compose.ports.yml` already exists, the project is already transformed — skip to
Phase 5.

For each containerized service with published ports:

1. **Strip `ports:` from the base `docker-compose.yml`.** Prefer targeted edits that
   preserve comments and formatting (read the service block, remove only its `ports:`
   list). Leave everything else (image, env, volumes, healthcheck) intact.

2. **Create `docker-compose.ports.yml`** re-adding exactly the mappings you removed, in
   the same `${VAR:-default}:container` form. This overlay is **opt-in** — it is NOT
   `docker-compose.override.yml` (which Compose auto-merges and would re-publish ports for
   everyone, defeating the purpose). Windows teammates and CI use it explicitly:

   ```yaml
   # docker-compose.ports.yml
   # Opt-in published host ports for environments without OrbStack (Windows, CI).
   # Use:  docker compose -f docker-compose.yml -f docker-compose.ports.yml up
   #   or: COMPOSE_FILE=docker-compose.yml:docker-compose.ports.yml docker compose up
   services:
     postgres:
       ports:
         - '${DB_PORT:-5432}:5432'
   ```

3. **Add an HTTP multi-port label only where needed.** If a service exposes multiple
   ports and at least one is HTTP (e.g. MinIO API + console), OrbStack may not auto-detect
   the right one. Add `dev.orbstack.http-port=<port>` to that service. Do NOT add
   `dev.orbstack.domains` (custom) labels — a custom stable domain would be claimed by
   every worktree and re-collide. Rely on the default `<service>.<project>.orb.local`,
   which is unique per worktree because `<project>` = `COMPOSE_PROJECT_NAME`.

4. **Rewrite local env-file connection URLs to domains.** For each connection var found in
   Phase 2, replace the host with `<service>.${COMPOSE_PROJECT_NAME:-<folder>}.orb.local`
   and use the **container** port (not the old host port). Example:

   ```diff
   - DATABASE_URL=postgresql://postgres:postgres@localhost:5432/payments_dev
   + DATABASE_URL=postgresql://postgres:postgres@postgres.${COMPOSE_PROJECT_NAME:-payments-api}.orb.local:5432/payments_dev
   - REDIS_URL=redis://localhost:6379
   + REDIS_URL=redis://redis.${COMPOSE_PROJECT_NAME:-payments-api}.orb.local:6379
   ```

   Only edit **local** env files. Do NOT touch CI env (which sets `localhost:PORT`) and do
   NOT bake `.orb.local` into source code or test fixtures — config stays env-driven so CI
   keeps working against the opt-in ports overlay.

---

## Phase 4 — Guardrails

1. **Surface the four caveats** to the user:
   - **macOS/Linux only** — Windows teammates need published ports; the
     `docker-compose.ports.yml` overlay preserves that path.
   - **CI has no OrbStack** — keep connection config env-driven (domain locally,
     `localhost:PORT` in CI via the ports overlay). Never bake `.orb.local` into code/fixtures.
   - **Licensing** — OrbStack is free for personal use, paid for commercial use.
   - **Engine swap is per-dev opt-in** — machine-level; cannot be enforced from the repo.

2. **Flag hardcoded hosts.** Grep source and fixtures for connection targets that bypass
   env config:

   ```bash
   grep -rnE '(localhost|127\.0\.0\.1):[0-9]{2,5}|\.orb\.local' \
     --include='*.ts' --include='*.js' --include='*.py' --include='*.go' \
     --include='*.json' --include='*.yaml' --include='*.yml' . 2>/dev/null
   ```

   Report any hits as things the user must make env-driven; do not auto-edit source code.

3. **Document host-run ports (do not edit).** If Phase 2 found a `cw.sh`-style script,
   tell the user which of its logic is now dead: container services no longer need port
   offsets, so only the host app ports (e.g. 3000/3001/3002) and `COMPOSE_PROJECT_NAME`
   still matter. Recommend slimming the script's `configure_docker_isolation`/offset logic
   accordingly — but leave the script unedited.

---

## Phase 5 — Verify

Prove the transform actually works before claiming success.

1. Bring services up under OrbStack:

   ```bash
   docker compose up -d
   ```

2. For each transformed service, confirm it is reachable at its domain + container port.
   Resolve the real project name from `docker compose ps` if `COMPOSE_PROJECT_NAME` is
   unset. Examples:

   ```bash
   # TCP reachability (Postgres / Redis): nc returns success if the port accepts a connection
   nc -z -w3 postgres.<project>.orb.local 5432 && echo "postgres OK"
   nc -z -w3 redis.<project>.orb.local 6379 && echo "redis OK"
   ```

   Prefer a real protocol check when the client is available (`pg_isready -h <domain>`,
   `redis-cli -h <domain> ping`).

3. **On failure** — if a domain won't accept a TCP connection (the OrbStack docs guarantee
   domain access for web services but are vague on raw TCP), fall back to documenting
   routable container-IP access (copy the container IP from the OrbStack app or
   `docker inspect`) and flag the service as needing manual confirmation. Do not claim the
   transform passed.

4. Show the user the full diff and let them commit:

   ```bash
   git status && git --no-pager diff
   ```

   Do not commit on the user's behalf — this skill edits the user's separate project repo.

---

## Edge Cases

- **Internal-only services** (no `ports:`) — leave untouched.
- **A service that genuinely needs a fixed host port** (e.g. an external webhook expecting
  `localhost:X`) — keep its mapping in `docker-compose.ports.yml`, used by default for that
  service, and flag it as not fully eliminable.
- **Compose profiles / multiple compose files** — inventory and transform each.
- **Non-darwin host** — engine detection (Phase 1) governs; OrbStack also runs on Linux.
  Windows is excluded by caveat 1.
````

- [ ] **Step 3: Verify the file is well-formed and complete**

Run:

```bash
test -f skills/orbstack-compatible/SKILL.md && \
awk '/^---$/{n++} n==1 && /^name:/{print} n==1 && /^user-invocable:/{print} END{if(n<2) print "FRONTMATTER NOT CLOSED"}' skills/orbstack-compatible/SKILL.md && \
grep -c -E '## Phase [1-5]' skills/orbstack-compatible/SKILL.md
```

Expected output: `name: orbstack-compatible`, `user-invocable: true`, and a phase count of `5`.

- [ ] **Step 4: Verify the four caveats and the two corrections are present**

Run:

```bash
grep -q 'docker-compose.ports.yml' skills/orbstack-compatible/SKILL.md && \
grep -q 'NOT .docker-compose.override.yml' skills/orbstack-compatible/SKILL.md && \
grep -q 'dev.orbstack.domains' skills/orbstack-compatible/SKILL.md && \
grep -qiE 'free for personal use' skills/orbstack-compatible/SKILL.md && \
echo "ALL PRESENT"
```

Expected: `ALL PRESENT`.

- [ ] **Step 5: Commit**

```bash
git add skills/orbstack-compatible/SKILL.md
git commit -m "feat: add /orbstack-compatible skill"
```

---

## Task 2: Add the skill to README.md

**Files:**
- Modify: `README.md` (the `## Skills` list, after the `/sprint-status-update` entry)

- [ ] **Step 1: Add the one-line entry**

After the `**`/sprint-status-update`**` line in the `## Skills` section, add:

```markdown

**`/orbstack-compatible`** — Make a Docker Compose project stop colliding on host ports across worktrees/projects by moving containerized services onto OrbStack routable domains (`<service>.<project>.orb.local`). Strips `ports:` from the base compose, adds an opt-in `docker-compose.ports.yml` for Windows/CI, rewrites local env URLs to domains, then verifies live. Requires OrbStack as the active Docker engine.
```

- [ ] **Step 2: Verify**

Run: `grep -c 'orbstack-compatible' README.md`
Expected: `1` (or more if other references exist).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: list /orbstack-compatible in README"
```

---

## Task 3: Document the skill in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (add a `### /orbstack-compatible` subsection under `## Skills`; add `## Key Conventions` bullets)

- [ ] **Step 1: Add the skill subsection**

Under `## Skills`, after the `### /sprint-status-update` subsection, add:

```markdown
### `/orbstack-compatible`
Transforms an arbitrary Docker Compose project to use OrbStack routable domains so
containerized services stop colliding on host ports across worktrees/projects. General
(any `docker-compose*.yml`), edits files directly then verifies live. Requires OrbStack as
the active Docker engine — aborts with setup guidance otherwise. Strips `ports:` from the
base compose; re-adds them in an **opt-in** `docker-compose.ports.yml` (NOT the
auto-merged `override.yml`) for Windows/CI; rewrites local env connection URLs to
`<service>.${COMPOSE_PROJECT_NAME:-<folder>}.orb.local:<container-port>` (default per-project
domain, never a custom `dev.orbstack.domains` label that would re-collide across worktrees).
Host-run dev-server ports are document-only — OrbStack can't route to host processes.
```

- [ ] **Step 2: Add Key Conventions bullets**

In the `## Key Conventions` list, append:

```markdown
- `/orbstack-compatible` keeps the OrbStack fallback in an **opt-in** `docker-compose.ports.yml`, never `docker-compose.override.yml` — Compose auto-merges `override.yml`, which would re-publish host ports for OrbStack users and defeat the transform
- `/orbstack-compatible` relies on OrbStack's default `<service>.<project>.orb.local` domain (unique per worktree via `COMPOSE_PROJECT_NAME`) and never sets a custom `dev.orbstack.domains` label — a fixed custom domain would be claimed by every worktree and re-collide
- `/orbstack-compatible` keeps connection config env-driven (domain in local env files, `localhost:PORT` in CI via the ports overlay) and never bakes `.orb.local` into source code or test fixtures
```

- [ ] **Step 3: Verify**

Run: `grep -c 'orbstack-compatible' CLAUDE.md`
Expected: `4` (one subsection heading + three convention bullets).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document /orbstack-compatible in CLAUDE.md"
```

---

## Task 4: Refresh the plugin manifests

**Files:**
- Modify: `.claude-plugin/marketplace.json` (the plugin `description`)
- Modify: `.claude-plugin/plugin.json` (the `description`)

- [ ] **Step 1: Update marketplace.json description**

In `.claude-plugin/marketplace.json`, change the plugin's `description` value to:

```
"Skills for autonomous story execution (plan-to-dex, swarm-execute), adversarial spec review (spec-review-codex, spec-review-local), OrbStack port-collision migration (orbstack-compatible), and workflow helpers (handoff, sprint-status-update)"
```

- [ ] **Step 2: Update plugin.json description**

In `.claude-plugin/plugin.json`, change the top-level `description` value to:

```
"Skills for autonomous story execution (dex orchestrator and parallel Codex swarm), adversarial spec review (Codex or local LMStudio), OrbStack port-collision migration, and workflow helpers (handoff, sprint status)"
```

- [ ] **Step 3: Verify both files are valid JSON**

Run:

```bash
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null && \
python3 -m json.tool .claude-plugin/plugin.json >/dev/null && \
echo "JSON VALID"
```

Expected: `JSON VALID`.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json .claude-plugin/plugin.json
git commit -m "chore: mention /orbstack-compatible in plugin manifests"
```

---

## Task 5: Validate triggering and behavior

**Files:** none modified (validation only)

- [ ] **Step 1: Run a triggering eval on the description**

Invoke the `skill-creator` skill's eval capability against
`skills/orbstack-compatible/SKILL.md`, using prompts that SHOULD trigger ("my docker
ports keep colliding between worktrees", "make this project orbstack compatible", "switch
my compose services to orbstack domains") and prompts that should NOT ("set up a Postgres
container", "fix my failing CI build"). Confirm the should-trigger prompts select the
skill and the should-not prompts do not.

Expected: clean separation. If a should-trigger prompt misses, widen the `description`
triggers and re-run; if a should-not prompt fires, tighten them.

- [ ] **Step 2: Dry-run the procedure against the reference case (mental walkthrough)**

Using `/Users/adelrioj/development/hurrypayments/payments-api/docker-compose.yml`
(services `postgres`/`redis`/`minio` with `${VAR:-default}:container` mappings) as input,
walk each phase and confirm the skill's instructions produce: base compose with `ports:`
removed; a `docker-compose.ports.yml` containing the three services' original mappings
(postgres 5432, redis 6379, minio 9000+9001); env URLs rewritten to
`postgres.<project>.orb.local:5432` / `redis.<project>.orb.local:6379`; a
`dev.orbstack.http-port` consideration for MinIO's two ports; and the `cw.sh` script
flagged document-only. Note any step that is ambiguous or produces a wrong result and fix
the SKILL.md inline.

Expected: every phase yields the intended artifact with no ambiguity. Do NOT modify the
payments-api repo — this is a walkthrough of the instructions, not an execution.

- [ ] **Step 3: Final verification of the whole change**

Run:

```bash
git --no-pager log --oneline -5 && \
grep -rl 'orbstack-compatible' skills/ README.md CLAUDE.md .claude-plugin/
```

Expected: commits for the skill, README, CLAUDE.md, and manifests; and all five files
reference the skill.

- [ ] **Step 4: Commit any fixes from Steps 1–2**

```bash
git add -A
git commit -m "fix: refine /orbstack-compatible after validation" || echo "no fixes needed"
```

---

## Self-Review Notes

- **Spec coverage:** D1 (opt-in overlay) → Task 1 Phase 3 + Task 3 conventions. D2 (default
  domain) → Phase 3 step 3 + conventions. D3 (env-driven, local only) → Phase 3 step 4 +
  Phase 4 + conventions. D4 (document-only host ports) → Phase 4 step 3. Five phases →
  Phase 1–5. Four caveats → Phase 4 step 1. Verified OrbStack facts → Phase 3/5 wording.
  Validation → Task 5.
- **Placeholders:** none — full SKILL.md content is inlined; `<service>`/`<project>`/`<folder>`
  are intentional runtime template tokens, not plan placeholders.
- **Type/name consistency:** file path, frontmatter `name`, README/CLAUDE/manifest
  references all use `orbstack-compatible`; overlay file is `docker-compose.ports.yml`
  throughout; label is `dev.orbstack.domains` / `dev.orbstack.http-port` throughout.
