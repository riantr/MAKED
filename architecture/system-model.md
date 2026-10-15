# MAKED System Model

**Skill**: `system-modeler` + `c4model` + `graphviz`
**Scope**: Current-state architecture of the MAKED_moonbit project.
**Audience**: Developers who need to understand what the system is, how it is
structured, and where the boundaries lie.

## What MAKED is

MAKED is a two-target web application written entirely in
[MoonBit](https://docs.moonbitlang.com). It organises content around five
domains (Model, Attack, Knowledge, Experience, Data) arranged as a closed ring
around a taijitu. The content is small, read-only, and served from SQLite.

| Target | Compile target | Entry point | Runs in |
|--------|---------------|-------------|---------|
| Backend | `native` | `cmd/server/main.mbt` | Server process |
| Frontend | `js` | `cmd/web/main.mbt` | Browser |

A single native process serves both the JSON API and the built SPA bundle, so
there is no second web server and no CORS.

## Reading order

1. **C4 System Context** (`system-model.dsl` &mdash; `system_context` view):
   who uses the system and what external systems it talks to (answer: just a
   browser and a static-filesystem).
2. **C4 Container** (`system-model.dsl` &mdash; `container` view): the two
   compile targets and the SQLite store.
3. **Component graph** (`system-model.dot`): internal modules of the backend
   and frontend, with dependency edges labelled by what crosses them.
4. **Evidence** (`system-model.evidence.md`): which files back each claim.

## Key architectural decisions

1. **Flask-style micro-framework (`backend/app.mbt`)** &mdash; `App` owns a
   route table and ordered middleware chain; handlers are
   `async (Request) -> Response`. A thin adapter bridges to moonback's
   `(Request, Responder) -> Unit` shape.

2. **Single-process deployment** &mdash; `cmd/server` serves the JSON API,
   static files from `frontend/dist`, and an SPA fallback for client-side
   routes. No reverse proxy, no CORS.

3. **SPA + JSON API** &mdash; The frontend (rabbita) fetches all pages in one
   `GET /api/pages` call, then routes client-side via the History API. The
   backend's `spa_fallback` middleware distinguishes browser navigations from
   API 404s.

4. **SQLite storage** &mdash; `Database` is a thin wrapper over
   `moonbit-community/sqlite3`. Schema is created idempotently via
   `CREATE TABLE IF NOT EXISTS`; content is seeded on every start with
   `INSERT ... ON CONFLICT DO UPDATE`.

5. **Read-only content model** &mdash; Nine public pages (five ring domains +
   tutorial, about, tasks, plus index and 404). No auth, no write path.

## Assumptions

- **High confidence**: all claims trace directly to source files listed in the
  evidence document.
- **Not modelled**: deployment environment (cloud vs. local), monitoring,
  logging infrastructure, CI/CD pipeline beyond the GitHub Actions workflow.
- **Unknown**: whether the system is used by anyone beyond the developer; no
  analytics or tracking code was found.
