# MAKED Deployment Topology

**Skill**: `deployment-topology-analyzer` + `graphviz`
**Scope**: Current-state runtime topology and build/deploy pipeline.
**Audience**: Developers who need to understand where and how the system runs.

## Current deployment model

MAKED runs as a **single native process** on a developer machine, or as a
container built from the repository's `Dockerfile`. There is no cloud
deployment, container orchestration, or reverse proxy. The same binary
serves the API, static files, and SPA fallback.

```
┌─────────────────────────────────────────────────┐
│  Developer machine (Windows/Linux/macOS)        │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  moon run cmd/server (native binary)      │  │
│  │                                           │  │
│  │  ┌─────────┐ ┌──────────┐ ┌───────────┐  │  │
│  │  │ moonback│ │  static  │ │   spa     │  │  │
│  │  │  router │ │  files   │ │  fallback │  │  │
│  │  │ /api/*  │ │ dist/*   │ │ /*.html   │  │  │
│  │  └────┬────┘ └────┬─────┘ └─────┬─────┘  │  │
│  │       │           │             │         │  │
│  │       ▼           ▼             ▼         │  │
│  │  ┌─────────┐ ┌──────────────────────┐     │  │
│  │  │ SQLite  │ │  frontend/dist/      │     │  │
│  │  │maked.db │ │  index.html          │     │  │
│  │  │         │ │  main.js             │     │  │
│  │  │         │ │  styles.css          │     │  │
│  │  └─────────┘ └──────────────────────┘     │  │
│  │                                           │  │
│  │  :8080 (HTTP)                             │  │
│  └───────────────────────────────────────────┘  │
│       ▲                                         │
│       │ HTTP                                    │
│  ┌────┴────┐                                    │
│  │ Browser │                                    │
│  └─────────┘                                    │
└─────────────────────────────────────────────────┘
```

## Build pipeline

### Backend (native)

```
moon build --release --target native cmd/server
  → _build/native/release/build/cmd/server/server
    (server.exe on Windows)
```

### Frontend (js)

```
moon build --release --target js cmd/web
  → _build/js/release/build/cmd/web/web.js
```

`build.ps1`, `ci.yml` and the `Dockerfile` copy that file to
`frontend/dist/main.js`, which is the file the server serves. It is a single
self-contained bundle, with no imports.

### Static assets

| File | Source | Purpose |
|------|--------|---------|
| `frontend/dist/index.html` | Hand-written | SPA shell |
| `frontend/dist/main.js` | `build.ps1`, `ci.yml` and the `Dockerfile`, from `_build/js/release/build/cmd/web/web.js` | Rabbita SPA bundle |
| `frontend/dist/styles.css` | Hand-written | Site stylesheet |

### Run

```
moon run --target native cmd/server
  → reads MAKED_PORT (default 8080)
  → reads MAKED_HOST (default 127.0.0.1)
  → reads MAKED_DB (default maked.db)
  → reads MAKED_DIST (default frontend/dist)
  → opens SQLite, seeds content, starts HTTP server
```

### As a container

```
docker compose up --build
  → builds the browser bundle and the native server, and runs one process
```

The image is built by `Dockerfile`; `docker-compose.yml` runs it with the
database on a volume so the reader's own work survives the container.

The image declares its own liveness check: `HEALTHCHECK` polls
`GET /api/status`, so the container's health is the server's own status
route.

## Runtime topology

| Component | Type | Location | Port |
|-----------|------|----------|------|
| moonback HTTP server | Process | Developer machine, or a container | 8080 (configurable) |
| SQLite database | File | `maked.db` (configurable) | N/A (FFI) |
| Static files | Directory | `frontend/dist/` (configurable) | N/A (served by moonback) |
| Browser | Client | Developer machine | ephemeral |

## Environment variables

| Variable | Default | Purpose | Source |
|----------|---------|---------|--------|
| `MAKED_PORT` | `8080` | HTTP listen port | `cmd/server/main.mbt:42` |
| `MAKED_HOST` | `127.0.0.1` | Interface to listen on | `cmd/server/main.mbt:43` |
| `MAKED_DB` | `maked.db` | SQLite database path | `cmd/server/main.mbt:44` |
| `MAKED_DIST` | `frontend/dist` | Frontend build output directory | `cmd/server/main.mbt:45` |

## Network boundaries

| Boundary | What crosses it | Protocol |
|----------|----------------|----------|
| Browser → server | HTTP requests (HTML, JS, CSS, JSON) | HTTP/1.1 on localhost |
| Server → SQLite | FFI calls (prepare, step, bind, finalize) | In-process FFI |
| Server → filesystem | File reads (index.html, main.js, styles.css) | In-process fs |
| Server → corpus feed | Corpus fetch (the arXiv API or an RSS feed) | HTTP to the feed you configured |

There is **one outbound call**: the server fetches the corpus you configured --
the arXiv API or an RSS feed -- with `@http.get(url)`
(`backend/corpus_sources.mbt:905`). It does not connect to any remote
database, and it does not phone home.

## Deployment gaps

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| No process manager (systemd/supervisor) | Server dies with terminal | Add systemd unit or use a process manager |
| No TLS termination | HTTP only | Add reverse proxy (nginx/caddy) for production |
| No structured logging | One-line stderr log per request | Add JSON logging middleware |
| No exported metrics, tracing, or alerting | The run's own measures ride in the session payload; nothing collects them | Add Prometheus metrics or similar |
| No backup strategy for SQLite | Data loss if file deleted | Add periodic backup or WAL mode + replication |
