# System Model Evidence

Every claim in `system-model.md` and the diagrams traces to one or more source
files. A source names the file and the lines the claim is on, and a row that
quotes a literal that occurs once in the code cites the line where that
literal is. Confidence is **high** unless noted otherwise.

## Module structure

| Claim | Source | Confidence |
|-------|--------|------------|
| Module name is `riantr/MAKED` | `moon.mod` | high |
| Two targets: `js+native` | `moon.mod:43` | high |
| Six project packages: root, backend, frontend, cmd/server, cmd/web, cmd/mcp | `moon.pkg` files (excluding `.mooncakes/`) | high |
| Backend is native-only | `backend/moon.pkg:33` (`supported_targets = "native"`) | high |
| Frontend is js-only | `frontend/moon.pkg:34` (`supported_targets = "js"`) | high |
| cmd/server is native executable | `cmd/server/moon.pkg:1,12` | high |
| cmd/web is js executable | `cmd/web/moon.pkg:1,8` | high |

## Backend architecture

| Claim | Source | Confidence |
|-------|--------|------------|
| Flask-style App with route table + middleware chain | `backend/app.mbt:16-36` | high |
| Handler type is `async (Request) -> Response` | `backend/app.mbt:17` | high |
| Middleware type is factory pattern | `backend/app.mbt:22-23` | high |
| `App::adapt` bridges to moonback's `@moonback.Handler` | `backend/app.mbt:109-112` | high |
| Catch-all GET `/*rest` returns JSON 404 | `backend/app.mbt:146` | high |
| Route conflicts use `fail` (not `raise`) | `backend/app.mbt:141` | high |
| 41 API routes: pages, entries, sessions, loop, research, society, agent | `backend/api.mbt:19-1209` | high |
| Database wraps sqlite3.Connection | `backend/database.mbt:26` | high |
| Schema: `pages` table with 17 columns | `backend/database.mbt:76-88`, `backend/database.mbt:220-244` | high |
| Schema: 5 more columns for a reader's correction of a page | `backend/database.mbt:220-244` | high |
| Schema: also `entries`, `sessions`, `session_steps` tables | `backend/database.mbt:100-134` | high |
| Seed uses `INSERT ... ON CONFLICT DO UPDATE` | `backend/database.mbt:94-123` | high |
| Three SQLite behaviours drove the helper shape | `backend/database.mbt:1-17` | high |
| Page struct with 17 fields (11 English + 6 Chinese), derives Eq | `backend/pages.mbt:31-72` | high |
| 10 seed pages: 5 ring domains + tutorial, about, tasks + index + 404 | `backend/pages.mbt:421-521` | high |
| Ring order: M -> D -> E -> A -> K (clockwise, not spelling order) | `backend/pages.mbt:235` | high |
| Request wraps moonback Request | `backend/request.mbt:9` | high |
| Response is a value type with Body enum | `backend/response.mbt:10-21` | high |
| create_app assembles everything, adds logging middleware | `backend/maked_app.mbt:11-29` | high |
| SPA fallback distinguishes browser nav from API 404 | `backend/maked_app.mbt:63-101` | high |
| Static files served from `frontend/dist` | `backend/maked_app.mbt:53-55` | high |

Five of the seventeen fields of `Page` hold a reader's correction: the title
and the body in each of the two languages, and the moment the correction was
written. The other twelve are the seed's own wording, in the same two
languages, and the seed rewrites them on every start-up -- which is why the
correction lives beside them rather than in them.

## Frontend architecture

| Claim | Source | Confidence |
|-------|--------|------------|
| Elm-style TEA (Model/Update/View) via rabbita | `frontend/app.mbt:124-1860` | high |
| Start-up chain: `GET /api/bootstrap`, then `GET /api/loop/status` | `frontend/app.mbt:1855`, `frontend/app.mbt:523` | high |
| Client-side routing via History API subscription | `frontend/app.mbt:1766` | high |
| `slug_of` maps URL path to page slug | `frontend/app.mbt:370` | high |
| All pages held in memory after first load | `frontend/app.mbt:499` | high |
| Page struct mirrors backend, decodes JSON totally | `frontend/page.mbt:18-145` | high |
| Views: `header`, `domain_cards`, `page_view`, `not_found_view`, `loading_view`, `error_view` | `frontend/views.mbt:31-319` | high |
| Logo: SVG ring + taijitu, HTML letter overlay | `frontend/logo.mbt:1-201` | high |
| Ring geometry: 5 nodes clockwise from top, radius 68, viewBox 200x200 | `frontend/logo.mbt:32-70` | high |
| Node colors: M indigo, D green, E red, A yellow, K grey | `frontend/logo.mbt:12-15, 32-40` | high |
| `page_view` renders a seeded body with `Attrs::inner_html` and a corrected body as text | `frontend/views.mbt:144-157` | high |

## Entry points

| Claim | Source | Confidence |
|-------|--------|------------|
| cmd/server: reads MAKED_PORT, MAKED_HOST, MAKED_DB, MAKED_DIST from env | `cmd/server/main.mbt:42-45` | high |
| cmd/server: assembles moonback Module with static_files + spa_fallback + routes | `cmd/server/main.mbt:74-85` | high |
| cmd/web: mounts frontend.app via rabbita | `cmd/web/main.mbt:9` | high |
| cmd/web produces single self-contained main.js | `cmd/web/main.mbt:1-6` | high |

## Dependencies

| Dependency | Version | Used by | Source |
|-----------|---------|---------|--------|
| moonbit-community/rabbita | 0.17.0 | frontend, cmd/web | `moon.mod:48` |
| moonbit-community/sqlite3 | 0.2.4 | backend | `moon.mod:49` |
| moonbit-community/yaml | 0.0.8 | backend | `moon.mod:50` |
| moonbitlang/async | 0.22.7 | backend, cmd/server, cmd/mcp | `moon.mod:51` |
| moonbitlang/moonback | 0.8.10 | backend, cmd/server | `moon.mod:52` |
| moonbitlang/pdflite | 0.4.1 | backend | `moon.mod:53` |
| moonbitlang/x | 0.5.7 | (transitive) | `moon.mod:54` |
| riantr/moonbit_doubleML | 0.164.62 | backend | `moon.mod:55` |
| riantr/pyroduct | 0.1.35 | backend | `moon.mod:56` |
| colmugx/mcp | 0.18.2 | cmd/mcp | `moon.mod:57` |

A package is named in the **Used by** column when its own `moon.pkg` imports
the dependency, in any of its import blocks: a test import is an import too.
The imports are counted by their module, so `moonbitlang/async` covers
`moonbitlang/async/fs` and `moonbitlang/async/http`. A dependency that no
package imports is written `(transitive)`: none of ours imports it.

## Tests

| Test file | What it covers | Source |
|-----------|---------------|--------|
| `backend/database_test.mbt` | 8 tests: round-trip, ring order, re-seed idempotency, CJK content, multi-row seed, missing slug, migrate idempotency, navigation | high |
| `backend/page_correction_test.mbt` | 12 tests: the reader's words reach the page, a correction survives the next seed, one language leaves the other alone, a correction does not move the page, the refusals | high |
| `frontend/frontend_test.mbt` | 174 tests: slug_of, navigation order, find_page, decode_pages (valid + malformed), ring geometry, ring radius, ring percentages, node colors, and the two languages of every surface | high |

## Tools

| File | Purpose |
|------|---------|
| `tools/mutate-backend.ps1` | Mutation testing for backend (removes safeguards, asserts tests catch it) |
| `tools/mutate-frontend.ps1` | Mutation testing for frontend |
