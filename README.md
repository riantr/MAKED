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
it, type-checks the backend, runs **both** test suites, and builds the server.
The backend serves the JSON API *and* the built frontend from one process, so
there is no second web server and no CORS to configure.

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
  database_test.mbt
  pages.mbt       content model + the seed content for the nine pages
  api.mbt         the JSON API
  maked_app.mbt   assembly, static files and the SPA fallback
frontend/         the rabbita SPA
  app.mbt         state machine and routing
  views.mbt       header, domain cards, page rendering
  logo.mbt        the five-ring mark, as SVG
  page.mbt        typed accessors over the backend's JSON
  frontend_test.mbt
  dist/           static shell served by the backend
cmd/server/       native entry point
cmd/web/          js entry point (the browser bundle)
tools/            mutation checks (see "Tests have teeth")
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

## How a request is answered

Three layers, outermost first:

1. `static_files` serves a real file from `frontend/dist`.
2. `spa_fallback` answers an unmatched browser navigation with `index.html`,
   so `/about` works on a cold load.
3. the router serves `/api/...` and returns a JSON 404 for anything else.

The fallback excludes `/api/` on purpose. moonback's own `history_fallback`
runs the downstream handler and rewrites **any** 404 into `index.html`, which
cannot tell a browser deep link from a legitimate API 404 — with it,
`GET /api/pages/nope` came back as `200 text/html`. A last segment containing a
dot is treated as an asset, so a missing stylesheet 404s rather than quietly
returning HTML the browser would try to execute.

A conflicting route aborts start-up rather than being dropped: `to_module` uses
`fail`, not `raise`, because the `Module` closure carries no error type and a
`raise` inside it goes nowhere.

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

## Tests have teeth

Passing tests are not evidence — a test can pass because it never reached the
code, or because its expectation was recomputed from the implementation's own
inputs. So both suites are covered by mutation checks in `tools/`: each entry
deliberately breaks one behaviour and asserts the suite goes red.

```
.\tools\mutate-backend.ps1      # 11 mutations: 0 survivors, 1 expected-equivalent
.\tools\mutate-frontend.ps1     # 15 mutations, 0 survivors
```

A mutation marked *expected-equivalent* is one that cannot fail any test, and
hardening a test against it would only assert something unobservable. The one in
the backend is the `reset` in `page_by_slug`, which prepares a fresh statement
on every call and so has no previous bindings to clear. It is kept listed
because that function is the obvious candidate for statement reuse, at which
point the same mutation becomes a real bug and the entry flips to `KILLED`.

Two traps the harnesses already hit, both of which look like a weak test and are
not — both are documented at the top of each script:

- A mutation anchor that does not occur in the file makes
  `String::Replace` a silent no-op, and the mutation is then reported as a
  survivor. Anchors are asserted before the patch; a miss is an `ERROR`.
- Expectation derived from the implementation is the failure this caught: the
  ring test compared each node's distance against `RING_R`, so shrinking the
  radius to 64 moved the nodes and the expectation together and the suite stayed
  green. The geometry is now pinned to literal coordinates.

The ring order is the case a plain "tidying" would break: `M → D → E → A → K`
draws five perfectly even nodes and merely looks wrong, so one test names both
orders explicitly.
