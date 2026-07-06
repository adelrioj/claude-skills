# `/orbstack-compatible`

Transforms an arbitrary Docker Compose project to use OrbStack routable domains so
containerized services stop colliding on host ports across worktrees/projects. General
(any `docker-compose*.yml`), edits files directly then verifies live. Requires OrbStack as
the active Docker engine — aborts with setup guidance otherwise. Strips `ports:` from the
base compose; re-adds them in an **opt-in** `docker-compose.ports.yml` (NOT the
auto-merged `override.yml`) for Windows/CI; rewrites local env connection URLs to
`<service>.${COMPOSE_PROJECT_NAME:-<folder>}.orb.local:<container-port>` (default per-project
domain, never a custom `dev.orbstack.domains` label that would re-collide across worktrees).
Host-run dev-server ports are document-only — OrbStack can't route to host processes.

## Conventions

- `/orbstack-compatible` keeps the OrbStack fallback in an **opt-in** `docker-compose.ports.yml`, never `docker-compose.override.yml` — Compose auto-merges `override.yml`, which would re-publish host ports for OrbStack users and defeat the transform
- `/orbstack-compatible` relies on OrbStack's default `<service>.<project>.orb.local` domain (unique per worktree via `COMPOSE_PROJECT_NAME`) and never sets a custom `dev.orbstack.domains` label — a fixed custom domain would be claimed by every worktree and re-collide
- `/orbstack-compatible` keeps connection config env-driven (domain in local env files, `localhost:PORT` in CI via the ports overlay) and never bakes `.orb.local` into source code or test fixtures
