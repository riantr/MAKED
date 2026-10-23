# MAKED Dependency Analysis

**Skill**: `dependency-impact-analyzer` + `graphviz`
**Scope**: Current-state package dependencies, external dependency graph, and
change-impact analysis for each project package.
**Audience**: Developers evaluating the blast radius of a change.

## Package dependency graph

The project has six packages. Dependencies flow strictly downward:

```
cmd/server ──→ backend ──→ moonback, sqlite3, async/*
cmd/web   ──→ frontend ──→ rabbita/*
cmd/mcp   ──→ backend ──→ colmugx/mcp, async/*
```

There are **no cycles**. Backend and frontend share no direct dependency; they
communicate only through the JSON API contract at runtime.

### Internal dependencies

| Package | Depends on (internal) | Depends on (external) |
|---------|----------------------|----------------------|
| `backend/` | (none) | moonback, moonback/unstable_static, sqlite3, yaml, async/fs, async/http, pdflite/markdown, moonbit_doubleML, pyroduct (src, group, society), core (debug, env, json, math, string) |
| `frontend/` | (none) | rabbita, rabbita/cmd, rabbita/html, rabbita/http, rabbita/nav, rabbita/sub, rabbita/svg, rabbita/url, core (json, math, string) |
| `cmd/server/` | backend | moonback, async, async/fs, core/env, core/string |
| `cmd/web/` | frontend | rabbita |
| `cmd/mcp/` | backend | colmugx/mcp, colmugx/mcp/protocol/tool, colmugx/mcp/protocol/types, colmugx/mcp/runtime, async, async/io, async/stdio, core (debug, env, json, string) |
| root `moon.pkg` | (empty) | (none) |

### External dependency tree

```
moonbitlang/moonback@0.8.9          ← HTTP server framework
moonbitlang/async@0.22.5            ← Async runtime (fs, http, process)
moonbit-community/sqlite3@0.2.3     ← SQLite FFI bindings
moonbit-community/rabbita@0.16.6    ← Elm-style SPA framework
moonbit-community/yaml@0.0.8        ← The mapping table's syntax
moonbitlang/pdflite@0.4.0           ← Markdown export
moonbitlang/x@0.5.6                 ← Utility library (transitive)
riantr/moonbit_doubleML@0.164.15    ← The causal estimate
riantr/pyroduct@0.1.32              ← The state machine and the collective
colmugx/mcp@0.18.1                  ← The agent's server
```

## Change impact analysis

### If you change `backend/database.mbt`

**Blast radius**: backend, cmd/mcp

| Affected | What breaks |
|----------|-------------|
| `backend/api.mbt` | `db.all_pages()`, `db.page_by_slug()` callers |
| `backend/maked_app.mbt` | `Database::open()`, `db.seed()` callers |
| `backend/database_test.mbt` | All 8 storage tests |

**Key risk**: SQLite statement lifecycle (prepare → reset → bind → step →
finalize) is the silent-failure surface. The tests are mutation-tested
(`tools/mutate-backend.ps1`) to ensure removing any safeguard is caught.

### If you change `backend/app.mbt`

**Blast radius**: backend, cmd/server

| Affected | What breaks |
|----------|-------------|
| `backend/api.mbt` | `App::get()`, `App::post()`, `App::put()`, `App::delete()`, `App::route()` |
| `backend/maked_app.mbt` | `App::new()`, `App::add_middleware()` |
| `cmd/server/main.mbt` | `app.to_module()` |

**Key risk**: the Handler/Middleware type signatures. Changing them ripples
through every route registration and middleware factory.

### If you change `frontend/app.mbt`

**Blast radius**: frontend, cmd/web

| Affected | What breaks |
|----------|-------------|
| `frontend/views.mbt` | `view()` calls header, domain_cards, page_view, etc. |
| `frontend/page.mbt` | `find_page()`, `navigation()` called from view |
| `frontend/logo.mbt` | `logo()`, `logo_mark()` called from view |
| `cmd/web/main.mbt` | `app()` is the mount entry point |
| `frontend/frontend_test.mbt` | slug_of, navigation, find_page tests |

**Key risk**: the Msg enum and Model struct. rabbita's `create_state_with_init`
fixes the update/subscription signatures, so changing them requires matching
the framework's expected shape.

### If you change `frontend/page.mbt`

**Blast radius**: frontend only

| Affected | What breaks |
|----------|-------------|
| `frontend/app.mbt` | `decode_pages()`, `find_page()`, `navigation()` |
| `frontend/views.mbt` | Page struct field access |
| `frontend/frontend_test.mbt` | decode_pages, navigation, find_page tests |

**Key risk**: the JSON field names in `get_string`/`get_int`/`get_bool` must
match `backend/pages.mbt`'s `Page::to_json()` keys. No compile-time check.

### If you change `backend/pages.mbt`

**Blast radius**: backend, cmd/mcp, frontend (via JSON contract)

| Affected | What breaks |
|----------|-------------|
| `backend/database.mbt` | `Page` struct fields, `seed()` parameters, the `pages` table's columns |
| `backend/bootstrap.mbt` | `seed_pages()` callers |
| `backend/api.mbt` | `Page::to_json()`, `domains_json()`, `ring_domains()`, the `?lang=` handlers |
| `backend/database_test.mbt` | All tests that construct Page or assert on seed content |
| `frontend/page.mbt` | the decoder's field names must match `to_json()`'s keys |
| `frontend/frontend_test.mbt` | the JSON fixtures the decoder is tested against |
| `tools/mutate-backend.ps1` | the guards that point at the bilingual fields |

**Key risk**: the four fields that carry a word the machine owns -- title,
role, summary and body -- exist twice, once per language, and `Lang::pick`
is the single place the choice is made. A field added to one language and
not the other is not a compile error; it is a surface that silently stays
in one language. The frontend's JSON decoder is total by design, so a field
name that changes renders empty strings instead of crashing, and the
JSON contract has no schema validation.

### If you change `frontend/logo.mbt`

**Blast radius**: frontend only

| Affected | What breaks |
|----------|-------------|
| `frontend/views.mbt` | `logo()`, `logo_mark()` |
| `frontend/frontend_test.mbt` | node_xy, node_percent, nodes tests (4 tests) |

**Key risk**: ring geometry. The tests pin literal coordinates, so a geometry
change requires updating both the implementation and the expected_centres()
literals in the test.

### If you change `cmd/server/main.mbt`

**Blast radius**: cmd/server only (entry point, no downstream consumers)

### If you change `cmd/web/main.mbt`

**Blast radius**: cmd/web only (entry point, no downstream consumers)

## Dependency coupling assessment

| Coupling | Assessment |
|----------|-----------|
| backend ↔ frontend | **Low** — JSON API contract only, no shared types. Risk: silent drift in field names. |
| backend → moonback | **Medium** — Handler adapter, Module construction, Responder lifecycle. |
| backend → sqlite3 | **Medium** — Statement lifecycle (prepare/reset/bind/step/finalize). |
| frontend → rabbita | **High** — TEA signatures, Html type, subscription model, HTTP client. |
| cmd/server → backend | **Low** — Eight function calls: install_from_environment, current_model, create_app, to_module, static_files, spa_fallback, current_corpus, describe. |
| cmd/web → frontend | **Minimal** — One function call: app(). |
| cmd/mcp → backend | **Low** — The loop's tools, read through the backend's agent module. |
