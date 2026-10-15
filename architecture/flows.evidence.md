# Flow Evidence

## Flow 1: Server startup

| Step | Source | Confidence |
|------|--------|------------|
| env_or reads MAKED_PORT/DB/DIST with fallbacks | `cmd/server/main.mbt:7-12, 26-28` | high |
| parse_port defaults to 8080 on invalid input | `cmd/server/main.mbt:15-22` | high |
| create_app opens DB, seeds, builds API | `backend/maked_app.mbt:11-29` | high |
| Database::open calls migrate (CREATE TABLE IF NOT EXISTS) | `backend/database.mbt:26-31, 73-89` | high |
| seed uses INSERT ... ON CONFLICT DO UPDATE | `backend/database.mbt:94-123` | high |
| 9 seed pages: 5 ring + tutorial, about, tasks | `backend/pages.mbt:121-155` | high |
| home_page and not_found_page seeded separately | `backend/maked_app.mbt:17` | high |
| logging_middleware is the only middleware | `backend/maked_app.mbt:19, 35-41` | high |
| to_module registers catch-all GET /*rest for JSON 404 | `backend/app.mbt:127-134` | high |
| Middleware order: routes → static → spa_fallback | `cmd/server/main.mbt:41-46` | high |

## Flow 2: Cold load

| Step | Source | Confidence |
|------|--------|------------|
| moonback middleware chain: routes first, then static, then spa | `cmd/server/main.mbt:41-46` | high |
| spa_fallback checks: GET/HEAD, not /api/*, no dot in last segment | `backend/maked_app.mbt:90-102` | high |
| spa_fallback reads dist/index.html via async fs | `backend/maked_app.mbt:70-78` | high |
| History fallback deliberately NOT used (would mask API 404s) | `backend/maked_app.mbt:47-55` | high |
| rabbita mount triggers start() which issues GET /api/pages | `frontend/app.mbt:108-113` | high |
| on_url_changed fires on mount when routing is configured | `frontend/app.mbt:100-103` | high |
| slug_of maps /about → about, / → index | `frontend/app.mbt:50-57` | high |

## Flow 3: Client-side navigation

| Step | Source | Confidence |
|------|--------|------------|
| Click handler on <li> (not <a>) because rabbita has no on_click for <a> | `frontend/views.mbt:27, 46` | high |
| push_url uses History API | `frontend/views.mbt:46` (rabbita/nav) | high |
| on_url_changed subscription wraps URL into Msg | `frontend/app.mbt:93-95` | high |
| update sets current = slug_of(url.path), no command issued | `frontend/app.mbt:84` | high |
| All pages already in memory; no second fetch | `frontend/app.mbt:26-31` | high |

## Flow 4: API request

| Step | Source | Confidence |
|------|--------|------------|
| Route pattern /api/pages/:slug captures slug param | `backend/api.mbt:25` | high |
| Request::param adapts StringView → String | `backend/request.mbt:33-35` | high |
| page_by_slug: prepare → reset → bind → step → finalize | `backend/database.mbt:144-159` | high |
| Response::send dispatches on Body enum (Empty/Text/Json) | `backend/response.mbt:43-49` | high |
| logging_middleware prints after handler returns | `backend/maked_app.mbt:36-40` | high |

## Flow 5: Data flow

| Step | Source | Confidence |
|------|--------|------------|
| seed_pages produces hardcoded HTML bodies | `backend/pages.mbt:60-103` | high |
| Page::to_json serializes all 8 fields | `backend/pages.mbt:32-43` | high |
| Frontend Page struct mirrors backend shape | `frontend/page.mbt:16-25` | high |
| decode_pages is total: missing fields get fallbacks | `frontend/page.mbt:42-78` | high |
| page_view uses inner_html (safe: backend is sole writer) | `frontend/views.mbt:89-103` | high |
| rabbita vdom diff → browser DOM | rabbita framework (external dep) | high |
