# System Model Evidence

Every claim in `system-model.md` and the diagrams traces to one or more source
files. Confidence is **high** unless noted otherwise.

## Module structure

| Claim | Source | Confidence |
|-------|--------|------------|
| Module name is `riantr/MAKED` | `moon.mod` | high |
| Two targets: `js+native` | `moon.mod:25` | high |
| Five project packages: root, backend, frontend, cmd/server, cmd/web | `moon.pkg` files (5 found, excluding `.mooncakes/`) | high |
| Backend is native-only | `backend/moon.pkg:23` (`supported_targets = "native"`) | high |
| Frontend is js-only | `frontend/moon.pkg:24` (`supported_targets = "js"`) | high |
| cmd/server is native executable | `cmd/server/moon.pkg:1,12` | high |
| cmd/web is js executable | `cmd/web/moon.pkg:1,8` | high |

## Backend architecture

| Claim | Source | Confidence |
|-------|--------|------------|
| Flask-style App with route table + middleware chain | `backend/app.mbt:16-36` | high |
| Handler type is `async (Request) -> Response` | `backend/app.mbt:16` | high |
| Middleware type is factory pattern | `backend/app.mbt:22-23` | high |
| Adapter bridges to moonback's `(Request, Responder) -> Unit` | `backend/app.mbt:92-95` | high |
| Catch-all GET `/*rest` returns JSON 404 | `backend/app.mbt:127-134` | high |
| Route conflicts use `fail` (not `raise`) | `backend/app.mbt:117-124` | high |
| 4 API endpoints: /api/status, /api/pages, /api/pages/:slug, /api/domains | `backend/api.mbt:10-44` | high |
| Database wraps sqlite3.Connection | `backend/database.mbt:20-22` | high |
| Schema: `pages` table with 8 columns | `backend/database.mbt:74-88` | high |
| Seed uses `INSERT ... ON CONFLICT DO UPDATE` | `backend/database.mbt:94-123` | high |
| Three SQLite behaviours drove the helper shape | `backend/database.mbt:1-17` | high |
| Page struct with 8 fields, derives Eq | `backend/pages.mbt:16-25` | high |
| 9 seed pages: 5 ring domains + tutorial, about, tasks + index + 404 | `backend/pages.mbt:121-169` | high |
| Ring order: M -> D -> E -> A -> K (clockwise, not spelling order) | `backend/pages.mbt:49-57` | high |
| Request wraps moonback Request | `backend/request.mbt:9` | high |
| Response is a value type with Body enum | `backend/response.mbt:10-21` | high |
| create_app assembles everything, adds logging middleware | `backend/maked_app.mbt:11-29` | high |
| SPA fallback distinguishes browser nav from API 404 | `backend/maked_app.mbt:63-101` | high |
| Static files served from `frontend/dist` | `backend/maked_app.mbt:53-55` | high |

## Frontend architecture

| Claim | Source | Confidence |
|-------|--------|------------|
| Elm-style TEA (Model/Update/View) via rabbita | `frontend/app.mbt:12-157` | high |
| Single fetch: `GET /api/pages` at startup | `frontend/app.mbt:108-113` | high |
| Client-side routing via History API subscription | `frontend/app.mbt:93-95` | high |
| `slug_of` maps URL path to page slug | `frontend/app.mbt:50-57` | high |
| All pages held in memory after first load | `frontend/app.mbt:26-31` | high |
| Page struct mirrors backend, decodes JSON totally | `frontend/page.mbt:16-114` | high |
| Views: header, domain cards, page view, not found, loading, error | `frontend/views.mbt:28-131` | high |
| Logo: SVG ring + taijitu, HTML letter overlay | `frontend/logo.mbt:1-207` | high |
| Ring geometry: 5 nodes clockwise from top, radius 68, viewBox 200x200 | `frontend/logo.mbt:42-70` | high |
| Node colors: M indigo, D green, E red, A yellow, K grey | `frontend/logo.mbt:31-39` | high |
| `dangerous_inner_html` used for page bodies (safe: backend is sole writer) | `frontend/views.mbt:89-103` | high |

## Entry points

| Claim | Source | Confidence |
|-------|--------|------------|
| cmd/server: reads MAKED_PORT, MAKED_DB, MAKED_DIST from env | `cmd/server/main.mbt:26-28` | high |
| cmd/server: assembles moonback Module with routes + static + spa fallback | `cmd/server/main.mbt:41-46` | high |
| cmd/web: mounts frontend.app via rabbita | `cmd/web/main.mbt:9` | high |
| cmd/web produces single self-contained main.js | `cmd/web/main.mbt:1-6` | high |

## Dependencies

| Dependency | Version | Used by | Source |
|-----------|---------|---------|--------|
| moonbit-community/rabbita | 0.16.4 | frontend | `moon.mod:30` |
| moonbit-community/sqlite3 | 0.2.3 | backend | `moon.mod:31` |
| moonbitlang/async | 0.22.4 | backend | `moon.mod:32` |
| moonbitlang/moonback | 0.8.6 | backend | `moon.mod:33` |
| moonbitlang/x | 0.5.5 | (transitive) | `moon.mod:34` |

## Tests

| Test file | What it covers | Source |
|-----------|---------------|--------|
| `backend/database_test.mbt` | 8 tests: round-trip, ring order, re-seed idempotency, CJK content, multi-row seed, missing slug, migrate idempotency, navigation | high |
| `frontend/frontend_test.mbt` | 8 tests: slug_of, navigation order, find_page, decode_pages (valid + malformed), ring geometry, ring radius, ring percentages, node colors | high |

## Tools

| File | Purpose |
|------|---------|
| `tools/mutate-backend.ps1` | Mutation testing for backend (removes safeguards, asserts tests catch it) |
| `tools/mutate-frontend.ps1` | Mutation testing for frontend |
