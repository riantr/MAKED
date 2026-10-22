# MAKED Evolution Plan

**Skill**: `evolution-planner` + `c4model`
**Scope**: The state MAKED was in before the evolution, the target state options,
the migration slices, and the reasoning behind the order they were taken in.
**Audience**: Developers who need to understand what MAKED is, where it came
from, and why it is shaped the way it is.

> **This document describes the past.** It was written when MAKED was nine
> read-only pages on one SQLite file with four GET endpoints and sixteen tests.
> Every slice below has since been implemented: there is a CI pipeline, a
> Dockerfile, a write path, sessions, the collective, an agent's server and a
> Chinese front end. The "Current state" table and the slices are kept as they
> were written, because the reasoning is the point -- but read them as history.
> For the system as it is today, read [system-model.md](system-model.md) and
> the [README](../README.md).

## Current state (as built, at the time this was written)

| Aspect | Current |
|--------|---------|
| Architecture | Two-target MoonBit: native backend + js frontend |
| Deployment | Single process, developer machine, localhost:8080 |
| Content | 9 read-only pages, seeded from hardcoded data |
| Storage | SQLite file, no backup, no WAL |
| API | 4 GET endpoints, no auth, no write path |
| Frontend | rabbita SPA, one fetch at startup, client-side routing |
| Observability | One-line stderr logging per request |
| CI/CD | GitHub Actions copilot setup only |
| Testing | 16 tests (8 backend + 8 frontend), mutation-tested |

## Target state options

### Option A: Production-ready single server

Make the current architecture deployable to a VPS or cloud VM.

| Change | Effort | Value |
|--------|--------|-------|
| Add Dockerfile | Low | Reproducible builds, easy deployment |
| Add systemd unit | Low | Process survives terminal close |
| Add reverse proxy (Caddy/nginx) | Medium | TLS, compression, static caching |
| Add `/health` endpoint | Low | Liveness monitoring |
| Add structured JSON logging | Low | Log aggregation compatibility |
| SQLite WAL mode + periodic backup | Low | Durability, concurrent reads |
| Add `moon test` to CI | Low | Automated test gate |

**Total effort**: ~2-3 days
**When to choose**: You want to put MAKED on the internet soon.

### Option B: Content management (write path)

Add the ability to edit page content without redeploying.

| Change | Effort | Value |
|--------|--------|-------|
| Add auth middleware (JWT or session) | Medium | Protect write endpoints |
| Add POST/PUT/PATCH handlers | Medium | CRUD on pages |
| Add admin UI (new rabbita app or separate page) | High | Content editing |
| Add input sanitization | Medium | XSS prevention (currently safe because no user input) |
| Add audit log table | Low | Track who changed what |
| Add file upload (images) | High | Rich content |

**Total effort**: ~1-2 weeks
**When to choose**: The content needs to change frequently, or multiple editors.

### Option C: Multi-domain deployment

Serve MAKED for multiple audiences or brands from one codebase.

| Change | Effort | Value |
|--------|--------|-------|
| Add tenant/workspace concept to schema | Medium | Multi-tenancy |
| Add host-based routing | Medium | Different content per domain |
| Add per-tenant seeding | Medium | Different defaults |
| Add tenant admin UI | High | Self-service onboarding |

**Total effort**: ~2-3 weeks
**When to choose**: You want to reuse MAKED as a platform for multiple sites.

### Option D: Framework extraction

Extract the Flask-style micro-framework into a reusable MoonBit package.

| Change | Effort | Value |
|--------|--------|-------|
| Split `backend/app.mbt` into `maked/framework` | Low | Reusable App/Handler/Middleware |
| Split `backend/request.mbt` + `response.mbt` | Low | Reusable request/response types |
| Split `backend/database.mbt` into `maked/sqlite_orm` | Medium | Reusable SQLite helpers |
| Publish to MoonBit package registry | Low | Community adoption |
| Add documentation + examples | Medium | Developer experience |

**Total effort**: ~3-5 days
**When to choose**: You want to contribute to the MoonBit ecosystem.

## Migration slices

Each slice is an independently deployable increment. Order matters: later
slices depend on earlier ones.

### Slice 1: CI gate (prerequisite for everything)

```
Current:  moon test runs locally only
Target:   moon test runs on every push/PR

Steps:
  1. Add moon test to .github/workflows/
  2. Add moon build --target native cmd/server (compile check)
  3. Add moon build --target js cmd/web (compile check)
  4. Fail the build if any step fails

Risk: low
Effort: 2 hours
Blocks: all other slices
```

### Slice 2: Containerization

```
Current:  manual moon build + moon run
Target:   docker build + docker run

Steps:
  1. Write Dockerfile (multi-stage: build native + build js + runtime)
  2. Add .dockerignore
  3. Test: docker build . && docker run -p 8080:8080 maked
  4. Add docker-compose.yml with volume mount for maked.db

Risk: low
Effort: 4 hours
Depends on: Slice 1 (optional but recommended)
```

### Slice 3: Production hardening

```
Current:  localhost HTTP, stderr logging, no health check
Target:   TLS, structured logging, health endpoint, backup

Steps:
  1. Add GET /health → {"status": "ok"}
  2. Replace the stderr log line with JSON logging middleware
  3. Add SQLite WAL mode (PRAGMA journal_mode=WAL)
  4. Add Caddyfile or nginx.conf for TLS termination
  5. Add cron job for SQLite backup (cp maked.db maked.db.bak)

Risk: medium (TLS config can be tricky)
Effort: 1 day
Depends on: Slice 2
```

### Slice 4: Content editing (optional)

```
Current:  read-only, content hardcoded in seed_pages()
Target:   authenticated write API + minimal admin UI

Steps:
  1. Add auth middleware (API key or JWT)
  2. Add POST /api/pages (create)
  3. Add PUT /api/pages/:slug (update)
  4. Add DELETE /api/pages/:slug (delete)
  5. Add input sanitization for body field
  6. Add audit_log table
  7. Build admin SPA (separate from public frontend)

Risk: high (auth + XSS are security-critical)
Effort: 1-2 weeks
Depends on: Slice 3 (production hardening first)
```

## Decision records

### ADR-001: Single-process deployment (current)

**Status**: Accepted
**Context**: MAKED is a small content site with 10 pages. A multi-service
architecture would add operational complexity without proportional benefit.
**Decision**: Serve API + static + SPA from one native process.
**Consequences**:
- (+) No CORS, no reverse proxy needed for development.
- (+) One binary to build, deploy, and monitor.
- (-) Cannot scale API and static independently.
- (-) Server restart required for code changes.
**Revisit when**: Traffic exceeds single-process capacity, or static asset
delivery becomes a bottleneck.

### ADR-002: Read-only content model (current)

**Status**: Accepted
**Context**: The original django CMS had admin + Celery. This deployment has
no editors and the content rarely changes.
**Decision**: No write API. Content is seeded from hardcoded data on startup.
**Consequences**:
- (+) No auth to get wrong. No XSS risk from user input.
- (+) Simpler testing (no state mutation in API).
- (-) Content changes require code change + redeploy.
**Revisit when**: Content needs to change more than once a month.

### ADR-003: SQLite as the only data store (current)

**Status**: Accepted
**Context**: MAKED has < 20 rows of content. PostgreSQL would be overkill.
**Decision**: SQLite file, no replication, no migration framework.
**Consequences**:
- (+) Zero infrastructure. The database is a file.
- (+) Trivially backupable (cp).
- (-) Single-writer limitation (not a problem for read-only).
- (-) No full-text search beyond LIKE queries.
**Revisit when**: Content exceeds ~10k rows, or full-text search is needed.

### ADR-004: rabbita for frontend (current)

**Status**: Accepted
**Context**: MoonBit's ecosystem is young. rabbita is the primary Elm-style
SPA framework for the js target.
**Decision**: Use rabbita for the frontend. Accept its constraints (no SSR,
no static site generation, History API routing only).
**Consequences**:
- (+) Type-safe frontend in MoonBit.
- (+) TEA model is well-understood and testable.
- (-) No SSR means cold loads depend on JS execution.
- (-) rabbita is early-stage; API may change.
**Revisit when**: SSR or SEO becomes critical, or rabbita is abandoned.

## Roadmap

```
Now          +1 week        +2 weeks       +1 month       +2 months
 │            │              │              │              │
 ▼            ▼              ▼              ▼              ▼
 [Slice 1]    [Slice 2]      [Slice 3]      [Slice 4]      [Future]
 CI gate      Containerize   Harden         Edit content   Framework
              + deploy       + monitor      (optional)     extraction
              to VPS                                        (optional)
```

**Recommended next step**: Slice 1 (CI gate). It is a 2-hour task that
unlocks everything else and has zero risk.
