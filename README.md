# MAKED on MoonBit

MAKED rebuilt on MoonBit: a [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita@0.16.4)
single-page frontend, and a Flask-style micro-framework written on top of
[moonback](https://mooncakes.io) for the backend. Page content lives in SQLite.

This is a separate project from the django CMS original in `../MAKED`, which
is kept as a reference and is not modified by this one.

## Run it

```
.\build.ps1
moon run --release --target native cmd/server
```

Then open <http://127.0.0.1:8080/>.

`build.ps1` builds the browser bundle, stages it where the server looks for
it, type-checks the backend, and builds the server. The backend serves the
JSON API *and* the built frontend from one process, so there is no second web
server and no CORS to configure.

### Environment

| variable     | default         | meaning                     |
| ------------ | --------------- | --------------------------- |
| `MAKED_PORT` | `8080`          | listen port                 |
| `MAKED_DB`   | `maked.db`      | SQLite file, created on run |
| `MAKED_DIST` | `frontend/dist` | built frontend to serve     |

## Layout

```
backend/          the micro-framework, storage layer and API routes
  app.mbt         App: route table + ordered middleware chain
  request.mbt     Request wrapper (path/query params)
  response.mbt    Response values and their dispatch
  database.mbt    SQLite storage
  pages.mbt       content model + the seed content for the nine pages
  api.mbt         the JSON API
  maked_app.mbt   assembly
frontend/         the rabbita SPA
  app.mbt         state machine and routing
  views.mbt       header, domain cards, page rendering
  logo.mbt        the five-ring mark, as SVG
  dist/           static shell served by the backend
cmd/server/       native entry point
cmd/web/          js entry point (the browser bundle)
```

## The API

| route                  | returns                               |
| ---------------------- | ------------------------------------- |
| `GET /api/status`      | db path, page count, the five domains  |
| `GET /api/pages`       | every page, in `sort` order           |
| `GET /api/pages/:slug` | one page, or 404                      |
| `GET /api/domains`     | the five domains, in ring order       |

Everything is read-only. The original had an admin, Celery and a flat-page
editor; this scope is the nine public pages, so there is no write path and no
auth to get wrong.

## Two things that are deliberate

**The ring order is M → D → E → A → K**, the clockwise order the logo draws
the domains in — not the order the name is spelled. The original site made the
same choice, and `pages.mbt` encodes it in `sort`.

**What the cycle is meant to achieve was never written down**, and four of the
five domains were still empty scaffolds. The site says so rather than
inventing an answer around it.

## Three SQLite behaviours the storage layer is built around

All three were verified against `moonbit-community/sqlite3` rather than
assumed, and each is commented at the point in `database.mbt` where it matters:

1. `prepare` only *compiles*. A statement that is never `step`ped never runs,
   and `finalize` alone silently discards it — so DDL goes through `exec`,
   which always steps.
2. A statement that has run to completion must be `reset` before reuse.
   `bind` overwrites bindings in place, so re-binding without a reset re-runs
   the old query with new values.
3. `finalize` reports the error code of the most recent evaluation, so a failed
   `step` poisons the later `finalize`.
