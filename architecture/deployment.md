# MAKED Deployment Topology

**Skill**: `deployment-topology-analyzer` + `graphviz`
**Scope**: Current-state runtime topology and build/deploy pipeline.
**Audience**: Developers who need to understand where and how the system runs.

## Current deployment model

MAKED runs as a **single native process** on a developer machine. There is no
cloud deployment, container orchestration, or reverse proxy. The same binary
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
  → _build/native/release/cmd/server.cjs (or native binary)
```

### Frontend (js)

```
moon build --release --target js cmd/web
  → frontend/dist/main.js (single self-contained bundle, no imports)
```

### Static assets

| File | Source | Purpose |
|------|--------|---------|
| `frontend/dist/index.html` | Hand-written or generated | SPA shell |
| `frontend/dist/main.js` | `moon build cmd/web` | Rabbita SPA bundle |
| `frontend/dist/styles.css` | Hand-written | Site stylesheet |

### Run

```
moon run --target native cmd/server
  → reads MAKED_PORT (default 8080)
  → reads MAKED_DB (default maked.db)
  → reads MAKED_DIST (default frontend/dist)
  → opens SQLite, seeds content, starts HTTP server
```

## Runtime topology

| Component | Type | Location | Port |
|-----------|------|----------|------|
| moonback HTTP server | Process | Developer machine | 8080 (configurable) |
| SQLite database | File | `maked.db` (configurable) | N/A (FFI) |
| Static files | Directory | `frontend/dist/` (configurable) | N/A (served by moonback) |
| Browser | Client | Developer machine | ephemeral |

## Environment variables

| Variable | Default | Purpose | Source |
|----------|---------|---------|--------|
| `MAKED_PORT` | `8080` | HTTP listen port | `cmd/server/main.mbt:26` |
| `MAKED_DB` | `maked.db` | SQLite database path | `cmd/server/main.mbt:27` |
| `MAKED_DIST` | `frontend/dist` | Frontend build output directory | `cmd/server/main.mbt:28` |

## Network boundaries

| Boundary | What crosses it | Protocol |
|----------|----------------|----------|
| Browser → server | HTTP requests (HTML, JS, CSS, JSON) | HTTP/1.1 on localhost |
| Server → SQLite | FFI calls (prepare, step, bind, finalize) | In-process FFI |
| Server → filesystem | File reads (index.html, main.js, styles.css) | In-process fs |

There are **no external network calls**. The server does not call any external
API, does not connect to any remote database, and does not phone home.

## Deployment gaps

| Gap | Impact | Recommendation |
|-----|--------|----------------|
| No container image (Docker/OCI) | Cannot deploy to cloud without manual setup | Add Dockerfile for reproducible builds |
| No CI/CD pipeline (beyond GitHub Actions copilot setup) | No automated test/deploy | Extend `.github/workflows/` with test + build + deploy |
| No process manager (systemd/supervisor) | Server dies with terminal | Add systemd unit or use a process manager |
| No TLS termination | HTTP only, localhost only | Add reverse proxy (nginx/caddy) for production |
| No health check endpoint | No way to monitor liveness | Add `GET /health` returning `{"status": "ok"}` |
| No structured logging | One-line println per request | Add JSON logging middleware |
| No metrics/observability | No visibility into performance | Add Prometheus metrics or similar |
| No backup strategy for SQLite | Data loss if file deleted | Add periodic backup or WAL mode + replication |
