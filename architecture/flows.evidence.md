# Flow Evidence

## Flow 1: Server startup

| Step | Source | Confidence |
|------|--------|------------|
| env_or reads MAKED_PORT/HOST/DB/DIST with fallbacks | `cmd/server/main.mbt:7-12, 42-45` | high |
| parse_port defaults to 8080 on invalid input | `cmd/server/main.mbt:15-22` | high |
| create_app opens DB, seeds, builds API | `backend/maked_app.mbt:11-29` | high |
| Database::open calls migrate (CREATE TABLE IF NOT EXISTS) | `backend/database.mbt:26-31, 73-245` | high |
| seed uses INSERT ... ON CONFLICT DO UPDATE | `backend/database.mbt:275` | high |
| 8 seeded pages: 5 ring + tutorial, about, tasks | `backend/pages.mbt:421-521` | high |
| home_page and not_found_page seeded separately | `backend/maked_app.mbt:17` | high |
| logging_middleware is the only middleware | `backend/maked_app.mbt:16, 61` | high |
| to_module registers catch-all GET /*rest for JSON 404 | `backend/app.mbt:146-149` | high |
| Middleware order: static_files → spa_fallback → routes | `cmd/server/main.mbt:79-84` | high |

## Flow 2: Cold load

| Step | Source | Confidence |
|------|--------|------------|
| Middleware order: static_files → spa_fallback → routes | `cmd/server/main.mbt:79-84` | high |
| spa_fallback checks: GET/HEAD, not /api/*, no dot in last segment | `backend/maked_app.mbt:91` | high |
| spa_fallback reads dist/index.html via async fs | `backend/maked_app.mbt:91-115` | high |
| The `history_fallback` is deliberately NOT used (would mask API 404s) | `backend/maked_app.mbt:74-80` | high |
| rabbita mount triggers start() which issues GET /api/bootstrap | `frontend/app.mbt:1839` | high |
| The bootstrap's answer asks for the loop status | `frontend/app.mbt:507` | high |
| bootstrap returns `{"pages": [...], "entries": [...], "entry_domains": [...], "session_state": {...}}` | `backend/api.mbt:61-76` | high |
| on_url_changed fires on mount when routing is configured | `frontend/app.mbt:1733` | high |
| slug_of maps /about → about, / → index | `frontend/app.mbt:370` | high |

## Flow 3: Client-side navigation

| Step | Source | Confidence |
|------|--------|------------|
| Click handler on <li> (not <a>) because rabbita has no on_click for <a> | `frontend/views.mbt:13, 83` | high |
| push_url uses History API | `frontend/views.mbt:83` (rabbita/nav) | high |
| on_url_changed subscription wraps URL into Msg | `frontend/app.mbt:1733` | high |
| update sets current = slug_of(url.path), no command issued | `frontend/app.mbt:460` | high |
| All pages already in memory; no second fetch | `frontend/app.mbt:483` | high |

## Flow 4: API request

| Step | Source | Confidence |
|------|--------|------------|
| Route pattern /api/pages/:slug captures slug param | `backend/api.mbt:79` | high |
| Request::param adapts StringView → String | `backend/request.mbt:33` | high |
| page_by_slug: prepare → reset → bind → step → finalize | `backend/database.mbt:343` | high |
| Response::send dispatches on Body enum (Empty/Text/Json) | `backend/response.mbt:81-106` | high |
| logging_middleware prints after handler returns | `backend/maked_app.mbt:65` | high |

## Flow 5: Data flow

| Step | Source | Confidence |
|------|--------|------------|
| seed_pages produces hardcoded HTML bodies | `backend/pages.mbt:422` | high |
| Page::to_json writes 10 fields, the language choosing the wording | `backend/pages.mbt:92-116` | high |
| Frontend Page struct mirrors backend shape | `frontend/page.mbt:18-37` | high |
| decode_pages is total: missing fields get fallbacks | `frontend/page.mbt:148` | high |
| page_view renders a seeded body as markup and a corrected body as text | `frontend/views.mbt:169` | high |
| rabbita vdom diff → browser DOM | rabbita framework (external dep) | high |
