# Dependency Evidence

## Package dependencies (from moon.pkg files)

| Package | Import block | Source |
|---------|-------------|--------|
| backend/ | sqlite3, async/fs, async/http, moonback, unstable_static | `backend/moon.pkg:8-15` |
| backend/ (test only) | async | `backend/moon.pkg:20-21` |
| frontend/ | rabbita, rabbita/cmd, rabbita/html, rabbita/http, rabbita/nav, rabbita/sub, rabbita/svg, rabbita/url, core/math | `frontend/moon.pkg:12-22` |
| frontend/ (test only) | core/string | `frontend/moon.pkg:27-28` |
| cmd/server/ | backend (@maked), async, async/fs, core/env, core/string, moonback | `cmd/server/moon.pkg:3-10` |
| cmd/web/ | frontend (@frontend), rabbita | `cmd/web/moon.pkg:3-6` |

## Dependency versions (from moon.mod)

| Dependency | Version | Source |
|-----------|---------|--------|
| moonbit-community/rabbita | 0.16.6 | `moon.mod:48` |
| moonbit-community/sqlite3 | 0.2.3 | `moon.mod:49` |
| moonbitlang/async | 0.22.5 | `moon.mod:51` |
| moonbitlang/moonback | 0.8.9 | `moon.mod:52` |
| moonbitlang/x | 0.5.6 | `moon.mod:54` |

## Change impact evidence

### backend/pages.mbt → frontend JSON contract

| Backend function | JSON key produced | Frontend consumer | Source |
|-----------------|-------------------|-------------------|--------|
| `Page::to_json()` | "slug" | `get_string(json, "slug", "")` | `backend/pages.mbt:34`, `frontend/page.mbt:69` |
| `Page::to_json()` | "title" | `get_string(json, "title", "")` | `backend/pages.mbt:35`, `frontend/page.mbt:70` |
| `Page::to_json()` | "letter" | `get_string(json, "letter", "")` | `backend/pages.mbt:36`, `frontend/page.mbt:71` |
| `Page::to_json()` | "role" | `get_string(json, "role", "")` | `backend/pages.mbt:37`, `frontend/page.mbt:72` |
| `Page::to_json()` | "summary" | `get_string(json, "summary", "")` | `backend/pages.mbt:38`, `frontend/page.mbt:73` |
| `Page::to_json()` | "body" | `get_string(json, "body", "")` | `backend/pages.mbt:39`, `frontend/page.mbt:74` |
| `Page::to_json()` | "in_navigation" | `get_bool(json, "in_navigation", false)` | `backend/pages.mbt:40`, `frontend/page.mbt:75` |
| `Page::to_json()` | "sort" | `get_int(json, "sort", 0)` | `backend/pages.mbt:41`, `frontend/page.mbt:76` |

### backend/database.mbt → SQLite lifecycle

| Safeguard | What it prevents | Test that catches removal | Source |
|-----------|-----------------|--------------------------|--------|
| `exec()` always steps | DDL silently skipped | "migrate is idempotent" | `backend/database.mbt:41-66`, test:158-172 |
| `seed()` resets before each bind | Stale bindings carry over | "seeding two pages in one call" | `backend/database.mbt:112`, test:112-144 |
| `page_by_slug()` resets (defensive) | Future reuse bug | Mutation test (equivalent mutant) | `backend/database.mbt:155` |
| `finalize()` error propagation | Poisoned finalize masks step error | "seeded pages round-trip" | `backend/database.mbt:52-65`, test:40-48 |

### frontend/app.mbt → rabbita TEA contract

| rabbita signature | frontend implementation | Source |
|-------------------|------------------------|--------|
| `create_state_with_init(init~, update~, subscriptions~)` | `start` as init, `update`, `subscriptions` | `frontend/app.mbt:151-155` |
| `update : (Model, Msg, Emit[Msg]) -> (Model, Cmd)` | `fn update(model, msg, _emit) -> (Model, @cmd.none)` | `frontend/app.mbt:63-86` |
| `subscriptions : (Model, Emit[Msg]) -> Sub` | `fn subscriptions(_model, emit) -> @sub.on_url_changed(...)` | `frontend/app.mbt:93-95` |
| `Emit::map : (a -> Msg) -> Emit[a] -> Emit[Msg]` | Used to lift URL and HTTP results into Msg | `frontend/app.mbt:94, 111` |
