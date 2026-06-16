# Design: `/orbstack-compatible` skill

## Problem

Developers who run multiple git worktrees (and multiple unrelated projects) that each
spin up Docker services hit **host-port collisions**. A published host port (`5432`,
`6379`, `3000`, …) is global singleton state: only one container can bind it at a time,
so a second worktree/project fails to start or silently talks to the wrong service.

There are two distinct collision problems:

1. **Container naming** — already solved by `COMPOSE_PROJECT_NAME`.
2. **Host-port addressing** — the hard part this skill targets.

Probabilistic offset schemes (hash the branch name → port offset) have birthday
collisions and are blind to other projects.

## Solution overview

A guided, autonomous transform that makes an arbitrary Compose-based project
**OrbStack-compatible**, eliminating the host-port collision class for containerized
services rather than dodging it with offsets.

OrbStack gives every container a routable IP and a default DNS domain
(`<service>.<project>.orb.local`). Containers become reachable from the macOS/Linux
host **without any `ports:` mapping** — so the global-singleton host port disappears
entirely. Because `<project>` derives from `COMPOSE_PROJECT_NAME` (already set per
worktree), the domain is naturally unique per worktree with no further bookkeeping.

The skill is **general** (works on any repo with `docker-compose*.yml`, validated
against the `payments-api` reference case), **edits files directly then verifies**, and
treats OrbStack-as-active-engine as a **hard prerequisite** (aborts with setup guidance
otherwise). Host-run dev-server ports (the part OrbStack cannot fix) are handled
**document-only**.

## Verified OrbStack facts (confirmed against docs.orbstack.dev, not memory)

- **Default Compose domain:** `<service>.<project>.orb.local`, where `<project>` is the
  Compose project name (defaults to the folder, overridable via `COMPOSE_PROJECT_NAME`).
- **Custom-domain label:** `dev.orbstack.domains` (comma-separated, `.local` TLD only) —
  **NOT** `dev.orb.domains` as an earlier handoff guessed. This skill deliberately does
  **not** use custom domains (see Decision D2).
- **HTTP multi-port override:** `dev.orbstack.http-port=<port>` label, for an HTTP
  service exposing multiple ports where auto-detection is ambiguous.
- **No host ports needed:** containers are reached via their domain; "port numbers are
  not needed for web services."
- **TCP services (Postgres/Redis):** the docs are explicit for *web* services but
  **vague for raw TCP**. The reliable mechanism is the routable container IP that the
  domain resolves to, so `postgres.<project>.orb.local:5432` connects at the container's
  own internal port. Because the docs do not guarantee this in writing, the skill
  **verifies it empirically** (Phase 5) and falls back to documenting container-IP
  access if a domain connection fails.

## Key decisions

### D1 — Fallback ports go in an opt-in overlay, not `docker-compose.override.yml`

Compose auto-merges `docker-compose.override.yml` **by default**. Putting the fallback
`ports:` there would re-publish host ports for OrbStack users too, reintroducing the
collisions. Instead:

- **Base `docker-compose.yml`** — `ports:` removed. This is what everyone gets by
  default locally → no host ports → collision class gone.
- **New `docker-compose.ports.yml`** — re-adds the `${VAR:-default}:container` mappings,
  included only on demand: `docker compose -f docker-compose.yml -f docker-compose.ports.yml up`,
  or `COMPOSE_FILE=docker-compose.yml:docker-compose.ports.yml`. Windows teammates and CI
  opt in here. Overlay `ports:` lists merge additively, so this is clean.

### D2 — Use the default per-project domain, not a custom `dev.orbstack.domains` label

A custom stable domain (e.g. `postgres.payments.local`) would be claimed by **every**
worktree's container → collision returns at the domain layer. The default
`<service>.<project>.orb.local` is unique per worktree for free, because `<project>` =
`COMPOSE_PROJECT_NAME`. So the skill adds **no domain labels** and relies on the default.
Exception: add `dev.orbstack.http-port` on a multi-port **HTTP** service (e.g. MinIO)
only when auto-detection would be ambiguous.

### D3 — Connection config stays env-driven; rewrite only local env files

Code reads connection targets from env vars. The skill rewrites **local** env files so
URLs point at the `.orb.local` domain; it leaves CI env (which sets `localhost:PORT`)
untouched, and never bakes `.orb.local` into source or test fixtures. Domain form uses
`${COMPOSE_PROJECT_NAME:-<folder>}` so it auto-isolates per worktree.

### D4 — Host-run dev-server ports are document-only

OrbStack cannot route to host processes (Node/Next dev servers on 3000/3001/…), so
those still need a small per-worktree offset. The skill **documents** the residual
collision and, if it finds a `cw.sh`-style worktree/port script, points out which offset
logic becomes dead after the transform and recommends slimming it — but does **not**
edit that script.

## Phases (the linear procedure in `SKILL.md`)

1. **Detect** — confirm OrbStack is the active Docker engine via `docker info`. If not,
   **abort** with setup guidance (`brew install orbstack`; switch engine in the OrbStack
   app or via `orb`) and make no edits.
2. **Inventory** — find all `docker-compose*.yml` (including profiles); list services
   with published `ports:`; classify containerized services vs host-run processes; find
   env files and the connection vars they set (`DATABASE_URL`, `REDIS_URL`,
   `*_HOST`/`*_PORT` pairs, S3/MinIO endpoint); detect any `cw.sh`-style worktree script.
3. **Transform (edit directly)** — strip `ports:` from base compose; write
   `docker-compose.ports.yml` with the removed mappings; rewrite local env-file
   connection URLs to `<service>.${COMPOSE_PROJECT_NAME:-<folder>}.orb.local:<container-port>`;
   add `dev.orbstack.http-port` only where D2's exception applies. Idempotent —
   re-running on an already-transformed repo is a no-op.
4. **Guardrails** — emit the four caveats below; grep source/fixtures for hardcoded
   `localhost:<port>` or `.orb.local` and flag them; apply D4 (document-only host ports).
5. **Verify** — `docker compose up -d`, then actually connect to each service at its
   `.orb.local` domain + container port (empirical, per the TCP note above). Report
   per-service pass/fail; on a failed domain connection, document routable container-IP
   access and flag it. Show `git diff`; leave committing to the user.

## Caveats the skill MUST surface

1. **macOS/Linux only** — Windows teammates need published ports; the `docker-compose.ports.yml`
   overlay preserves that path.
2. **CI has no OrbStack** — connection config must stay env-driven (domain locally,
   `localhost:PORT` in CI). Never bake `.orb.local` into code or fixtures.
3. **Licensing** — OrbStack is free for personal use, paid for commercial use.
4. **Engine swap is per-dev opt-in** — machine-level; cannot be enforced from the repo.

## Edge cases

- Services already without `ports:` (internal-only) → untouched.
- A service genuinely needing a fixed host port (e.g. an external webhook expecting
  `localhost:X`) → kept in the ports overlay and flagged as not fully eliminable.
- Compose profiles / multiple compose files → inventory all, transform each.
- Non-darwin host → engine detection still governs; OS is informational (OrbStack also
  runs on Linux). Windows is excluded by caveat 1.

## Non-goals

- Rewriting host-run dev-server port logic (document-only, D4).
- Installing or switching the Docker engine automatically (abort + guide instead).
- Project-specific hardcoding — the skill is general; `payments-api` is only the
  validation case.

## Structure & validation

- Single self-contained `skills/orbstack-compatible/SKILL.md` (matches repo convention,
  e.g. the `handoff` skill). No helper scripts or reference docs.
- Frontmatter: `name: orbstack-compatible`, `user-invocable: true`, and a trigger-rich
  `description`.
- Validation: dry-run mentally against `payments-api` (postgres/redis/minio); run a
  `skill-creator` triggering eval on the description.
- README and CLAUDE.md updated to list the new skill.
