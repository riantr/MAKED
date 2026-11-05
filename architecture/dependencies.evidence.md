# Dependency Evidence

## Package dependencies (from moon.pkg files)

| Package | Import block | Source |
|---------|-------------|--------|
| backend/ | sqlite3, yaml, async/fs, async/http, core/debug, core/env, core/json, core/math, core/string, moonback, moonback/unstable_static (@static), pdflite/markdown (@pdflite_md), moonbit_doubleML (@dml), pyroduct/group, pyroduct/society, pyroduct/src (@sm) | `backend/moon.pkg:8-25` |
| backend/ (test only) | async | `backend/moon.pkg:29-31` |
| frontend/ | rabbita, rabbita/cmd, rabbita/html, rabbita/http, rabbita/nav, rabbita/sub, rabbita/svg, rabbita/url, core/json, core/math, core/string | `frontend/moon.pkg:16-26` |
| frontend/ (test only) | core/debug | `frontend/moon.pkg:30-32` |
| cmd/server/ | backend (@maked), async, async/fs, core/env, core/string, moonback | `cmd/server/moon.pkg:2-9` |
| cmd/web/ | frontend, rabbita | `cmd/web/moon.pkg:2-5` |
| cmd/mcp/ | backend (@maked), mcp, mcp/tool, mcp/types (@mcp_types), mcp/runtime, async, async/io, async/stdio, core/debug, core/env, core/json, core/string | `cmd/mcp/moon.pkg:16-29` |

## Dependency versions (from moon.mod)

| Dependency | Version | Source |
|-----------|---------|--------|
| moonbit-community/rabbita | 0.17.0 | `moon.mod:48` |
| moonbit-community/sqlite3 | 0.2.3 | `moon.mod:49` |
| moonbit-community/yaml | 0.0.8 | `moon.mod:50` |
| moonbitlang/async | 0.22.7 | `moon.mod:51` |
| moonbitlang/moonback | 0.8.10 | `moon.mod:52` |
| moonbitlang/pdflite | 0.4.1 | `moon.mod:53` |
| moonbitlang/x | 0.5.7 | `moon.mod:54` |
| riantr/moonbit_doubleML | 0.164.62 | `moon.mod:55` |
| riantr/pyroduct | 0.1.35 | `moon.mod:56` |
| colmugx/mcp | 0.18.2 | `moon.mod:57` |

## Change impact evidence

### backend/pages.mbt → frontend JSON contract

| Backend function | JSON key produced | Frontend consumer | Source |
|-----------------|-------------------|-------------------|--------|
| `Page::to_json()` | "slug" | `get_string(json, "slug", "")` | `backend/pages.mbt:106`, `frontend/page.mbt:131` |
| `Page::to_json()` | "title" | `get_string(json, "title", "")` | `backend/pages.mbt:107`, `frontend/page.mbt:132` |
| `Page::to_json()` | "letter" | `get_string(json, "letter", "")` | `backend/pages.mbt:108`, `frontend/page.mbt:133` |
| `Page::to_json()` | "role" | `get_string(json, "role", "")` | `backend/pages.mbt:109`, `frontend/page.mbt:134` |
| `Page::to_json()` | "summary" | `get_string(json, "summary", "")` | `backend/pages.mbt:110`, `frontend/page.mbt:135` |
| `Page::to_json()` | "body" | `get_string(json, "body", "")` | `backend/pages.mbt:111`, `frontend/page.mbt:136` |
| `Page::to_json()` | "in_navigation" | `get_bool(json, "in_navigation", false)` | `backend/pages.mbt:112`, `frontend/page.mbt:137` |
| `Page::to_json()` | "sort" | `get_int(json, "sort", 0)` | `backend/pages.mbt:113`, `frontend/page.mbt:138` |
| `Page::to_json()` | "corrected" | `get_bool(json, "corrected", false)` | `backend/pages.mbt:114`, `frontend/page.mbt:139` |
| `Page::to_json()` | "corrected_at" | `get_string(json, "corrected_at", "")` | `backend/pages.mbt:115`, `frontend/page.mbt:140` |

The four keys that carry a word the machine owns -- title, role, summary and
body -- are chosen by the language the request asked for, and the client
reads the same key either way. `Lang::pick` is the single place that choice
is made, so a key is never written in one language and read in another.

The two keys that carry a correction are the reader's own words: `corrected`
says whether they are the reader's, and `corrected_at` says when they were
written. The client reads both, so a page that speaks the reader's words says
so on the way to the screen.

### backend/database.mbt → SQLite lifecycle

| Safeguard | What it prevents | Test that catches removal | Source |
|-----------|-----------------|--------------------------|--------|
| `exec()` always steps | DDL silently skipped | "migrate is idempotent and exec really executes" | `backend/database.mbt:41-66`, test:208-222 |
| `seed()` resets before each bind | Stale bindings carry over | "seeding two pages in one call does not repeat the first" | `backend/database.mbt:275`, test:128-194 |
| `page_by_slug()` resets (defensive) | Future reuse bug | Mutation test (equivalent mutant) | `backend/database.mbt:343` |
| `finalize()` error propagation | Poisoned finalize masks step error | "seeded pages round-trip through SQLite" | `backend/database.mbt:52-65`, test:40-48 |

### frontend/app.mbt → rabbita TEA contract

| rabbita signature | frontend implementation | Source |
|-------------------|------------------------|--------|
| `create_state_with_init(init~, update~, subscriptions~)` | `start` as init, `update`, `subscriptions` | `frontend/app.mbt:1845` |
| `update : (Model, Msg, Emit[Msg]) -> (Model, Cmd)` | `fn update(model, msg, _emit) -> (Model, @cmd.none)` | `frontend/app.mbt:477` |
| `subscriptions : (Model, Emit[Msg]) -> Sub` | `fn subscriptions(_model, emit) -> @sub.on_url_changed(...)` | `frontend/app.mbt:1765-1769` |
| `Emit::map : (a -> Msg) -> Emit[a] -> Emit[Msg]` | Used to lift URL and HTTP results into Msg | `frontend/app.mbt:1766` |
