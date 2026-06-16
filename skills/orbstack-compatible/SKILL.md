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
   the same `${VAR:-default}:container` form. This overlay is **opt-in** — it is NOT `docker-compose.override.yml` (which Compose auto-merges and would re-publish ports for
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
