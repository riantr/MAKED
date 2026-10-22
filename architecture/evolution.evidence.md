# Evolution Evidence

> **This document describes the past.** It is a record of it: every claim
> below was true of MAKED before the slices were implemented, and each one
> is now false -- there is a Dockerfile, there is a CI pipeline with six
> jobs, there is a write path, and the suites have grown from sixteen tests
> to hundreds. The claims are kept in their original form because they are
> the *reason* the slices exist: a reader who wants to know why MAKED has a
> container or a pipeline needs to know that there was a time when it had
> neither. For the system as it is today, see
> [system-model.evidence.md](system-model.evidence.md).

## State evidence (as built, at the time this was written)

All current-state claims are sourced in `system-model.evidence.md`. This
document adds evidence for the evolution recommendations.

## Slice 1: CI gate

| Claim | Evidence | Confidence |
|-------|----------|------------|
| Only workflow is copilot-setup-steps.yml | `.github/workflows/copilot-setup-steps.yml` (only file in workflows/) | high |
| `moon test` passes locally | `backend/database_test.mbt` (8 tests), `frontend/frontend_test.mbt` (8 tests) | high |
| `moon build` compiles both targets | `cmd/server/moon.pkg` (native), `cmd/web/moon.pkg` (js) | high |
| No test step in any CI config | Grep for "moon test" in `.github/` returns nothing | high |

## Slice 2: Containerization

| Claim | Evidence | Confidence |
|-------|----------|------------|
| No Dockerfile exists | `find` for Dockerfile returns nothing | high |
| No docker-compose.yml exists | `find` for docker-compose* returns nothing | high |
| Backend needs native target to build | `cmd/server/moon.pkg:12` (`supported_targets = "native"`) | high |
| Frontend needs js target to build | `cmd/web/moon.pkg:8` (`supported_targets = "js"`) | high |
| SQLite is a file, not a service | `backend/database.mbt:27` (`sqlite3.Connection::open(path)`) | high |
| MAKED_DB env var controls database path | `cmd/server/main.mbt:27` | high |
| MAKED_DIST env var controls static path | `cmd/server/main.mbt:28` | high |

## Slice 3: Production hardening

| Claim | Evidence | Confidence |
|-------|----------|------------|
| No /health endpoint | `backend/api.mbt` has 4 routes, none is /health | high |
| Logging is println, not structured | `backend/maked_app.mbt:38` (`println(...)`) | high |
| SQLite WAL not configured | No `PRAGMA journal_mode` in `backend/database.mbt` | high |
| No TLS termination | Server binds to 127.0.0.1, no TLS config | high |
| No reverse proxy config | No Caddyfile, nginx.conf, or similar | high |

## Slice 4: Content editing

| Claim | Evidence | Confidence |
|-------|----------|------------|
| No write API exists | `backend/api.mbt` has only GET routes | high |
| No auth middleware | `backend/maked_app.mbt:19` adds only logging_middleware | high |
| No input sanitization | `frontend/views.mbt:96` uses inner_html directly | high |
| inner_html is safe only because backend is sole writer | `frontend/views.mbt:89-94` (comment explains) | high |
| No audit log table | `backend/database.mbt:74-88` creates only `pages` table | high |

## Slice 5: Framework extraction

| Claim | Evidence | Confidence |
|-------|----------|------------|
| App/Handler/Middleware are generic, not MAKED-specific | `backend/app.mbt:16-36` (no reference to pages, content, etc.) | high |
| Request/Response are generic HTTP types | `backend/request.mbt`, `backend/response.mbt` (no domain logic) | high |
| Database is thin over sqlite3, could be extracted | `backend/database.mbt:1-17` (generic SQLite helpers) | medium |
| pages.mbt is MAKED-specific, not extractable | `backend/pages.mbt` (domain content, ring domains) | high |
| api.mbt is MAKED-specific, not extractable | `backend/api.mbt` (domain endpoints) | high |

## ADR evidence

### ADR-001: Single-process deployment

| Evidence | Source |
|----------|--------|
| One binary serves API + static + SPA | `cmd/server/main.mbt:41-52` |
| No CORS config needed | No CORS middleware in `backend/maked_app.mbt` |
| Static middleware serves from same process | `backend/maked_app.mbt:53-55` |

### ADR-002: Read-only content

| Evidence | Source |
|----------|--------|
| All API routes are GET | `backend/api.mbt:10-44` (only `app.get` calls) |
| No POST/PUT/PATCH/DELETE handlers | Grep for `app.post`, `app.put`, etc. returns nothing |
| Content seeded from hardcoded function | `backend/maked_app.mbt:13` (`seed_pages()`) |

### ADR-003: SQLite only

| Evidence | Source |
|----------|--------|
| Only database dependency is sqlite3 | `moon.mod:49`, `backend/moon.pkg:9` |
| No PostgreSQL, MySQL, or other DB imports | Grep for database drivers returns only sqlite3 |
| Schema is one table with 8 columns | `backend/database.mbt:76-88` |

### ADR-004: rabbita frontend

| Evidence | Source |
|----------|--------|
| Frontend imports rabbita exclusively | `frontend/moon.pkg:13-20` |
| No other frontend framework in dependencies | `moon.mod` lists only rabbita for frontend |
| TEA pattern via create_state_with_init | `frontend/app.mbt:151-155` |
