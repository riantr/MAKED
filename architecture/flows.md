# MAKED Flow Visualization

**Skill**: `flow-visualizer` + `graphviz`
**Scope**: Current-state request, data, and lifecycle flows.
**Audience**: Developers who need to understand how actions move through the system.

## Flows modelled

1. **Server startup** — process boot to listening socket.
2. **Cold load (deep link)** — browser navigates to `/about`, gets `index.html`,
   JS boots, fetches data, renders the page.
3. **Client-side navigation** — user clicks a nav link, SPA routes without a
   server round-trip.
4. **API request** — `GET /api/pages/:slug` through middleware, handler,
   database, and back.
5. **Page content data flow** — from seed data through SQLite to JSON to DOM.

## Reading order

1. `flows.dot` — all five flows in one graph (start here for the big picture).
2. Individual flow descriptions below.
3. `flows.evidence.md` — source references for each step.

## Flow descriptions

### 1. Server startup

```
env vars (MAKED_PORT, MAKED_HOST, MAKED_DB, MAKED_DIST)
  → parse_port / env_or
  → create_app(db_path)
    → Database::open(path)
      → sqlite3.Connection::open
      → migrate() — CREATE TABLE IF NOT EXISTS (pages, entries, sessions, session_steps)
    → seed(seed_pages()) — 8 pages via UPSERT
    → seed([home_page, not_found_page])
    → App::new()
    → add_middleware(logging_middleware)
    → build_api(app, db, db_path) — registers 37 routes
  → app.to_module() — adapts to moonback Module
  → moonback.App(root) with static + spa_fallback middleware
  → moonback.listen(port)
  → server.serve(listener) — blocking
```

**Key property**: the server is fully ready before the first request arrives.
Schema creation and content seeding are synchronous and idempotent.

### 2. Cold load (deep link to /about)

```
Browser → GET /about
  → moonback middleware chain (outermost first):
    1. static_files: no file at dist/about → passes through
    2. spa_fallback: GET, not /api/*, no dot in last segment → wants_spa_shell = true
       → read dist/index.html → 200 text/html
    3. routes: the route module; the shell above already answered this request
  ← Browser receives index.html
  → <script src="main.js"> loads
  → rabbita.new(app).mount("app")
    → start(emit): model = initial(), cmd = GET /api/bootstrap
    → HTTP GET /api/bootstrap
      → routes module: matches GET /api/bootstrap
      → logging_middleware: logs "GET /api/bootstrap -> 200"
      → handler: db.all_pages() → map to_json → Response::json
      ← 200 {"pages": [...], "entries": [...], "entry_domains": [...], "session_state": {...}}
    → Loaded(Ok(json)) → update: decode_pages, loaded = true
    → on_url_changed fires with current URL /about
    → UrlChanged → update: current = slug_of("/about") = "about"
    → view(model): header + page_view(about_page)
  ← Browser renders the About page
```

**Key property**: the SPA fallback must distinguish browser navigations from
API 404s. It checks: GET/HEAD, not `/api/*`, no dot in last path segment.

### 3. Client-side navigation (click "Data" in nav)

```
User clicks <li on_click=push_url("/data")>
  → rabbita nav.push_url("/data")
    → History API: pushState({}, "", "/data")
    → on_url_changed subscription fires
  → UrlChanged(url) → update: current = slug_of("/data") = "data"
  → view(model): header(active="data") + domain_cards + page_view(data_page)
  ← Browser re-renders (no server request)
```

**Key property**: zero server round-trips. All page content was loaded at
startup and is held in memory. A route change is a map lookup, not a fetch.

### 4. API request (GET /api/pages/:slug)

```
Browser → GET /api/pages/model
  → moonback middleware chain:
    1. routes module: matches GET /api/pages/:slug, captures slug="model"
    2. logging_middleware wraps handler
      → Request(moonback_req)
      → req.param("slug") → Some("model")
      → db.page_by_slug("model")
        → prepare SELECT ... WHERE slug = ?
        → reset(clear_bindings=true)
        → bind(1, "model")
        → step() → true → read_page(stmt) → Page { slug: "model", ... }
        → finalize()
      → Some(page) → Response::json(page.to_json())
      → response.send(res) → res.send_json(body, status=200)
    → eprintln("GET /api/pages/model -> 200")
  ← 200 {"slug": "model", "title": "Model", ...}
```

**Key property**: the Request wrapper adapts moonback's StringView-keyed params
to String-keyed, so handlers never touch StringView lifetimes.

### 5. Page content data flow

```
seed_pages() → Array[Page] (8 pages, hardcoded HTML bodies)
  → Database::seed(pages)
    → prepare INSERT ... ON CONFLICT(slug) DO UPDATE
    → for each page: reset → bind(12 params) → step
    → finalize
  → [SQLite file: maked.db, pages table]
  → Database::all_pages()
    → prepare SELECT ... ORDER BY sort ASC, slug ASC
    → while step(): push read_page(stmt)
    → finalize
  → Array[Page] → map(Page::to_json) → Array[Json]
  → {"pages": [...]} → HTTP response
  → Frontend: decode_pages(json) → Array[Page] (frontend.Page)
  → view(model) → @html.div / @html.article / inner_html(body)
  → rabbita vdom → browser DOM
```

**Key property**: the body is an HTML fragment stored in SQLite, rendered via
`inner_html` (dangerous_inner_html). It is safe here because the backend is the
sole writer of that column -- the reader's own records are a different table
and a different endpoint, and they are rendered as text.
