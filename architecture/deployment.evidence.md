# Deployment Evidence

## Runtime topology

| Claim | Source | Confidence |
|-------|--------|------------|
| Single native process serves everything | `cmd/server/main.mbt:42-95` | high |
| Listens on port from MAKED_PORT env (default 8080) | `cmd/server/main.mbt:42` | high |
| Listens on host from MAKED_HOST env (default 127.0.0.1) | `cmd/server/main.mbt:43` | high |
| SQLite path from MAKED_DB env (default maked.db) | `cmd/server/main.mbt:44` | high |
| Static files from MAKED_DIST env (default frontend/dist) | `cmd/server/main.mbt:45` | high |
| Warns if dist directory not found at startup | `cmd/server/main.mbt:46-47` | high |
| Middleware order: routes → static → spa_fallback | `cmd/server/main.mbt:74-80` | high |
| No TLS, no reverse proxy; MAKED_HOST widens the reach | `cmd/server/main.mbt:63-67` | high |

## Build pipeline

| Claim | Source | Confidence |
|-------|--------|------------|
| Backend built with `--target native` | `cmd/server/moon.pkg:12` | high |
| Frontend built with `--target js` | `cmd/web/moon.pkg:8` | high |
| cmd/web produces single self-contained main.js | `cmd/web/main.mbt:1-6` | high |
| No bundler or import map needed | `cmd/web/main.mbt:4-5` | high |
| frontend/dist contains index.html, main.js, styles.css | `frontend/dist/` directory listing | high |

## Network boundaries

| Claim | Source | Confidence |
|-------|--------|------------|
| No outbound network calls | No HTTP client code in backend (only in frontend via rabbita) | high |
| SQLite accessed via FFI, not network | `backend/database.mbt:26` (`sqlite3.Connection::open`) | high |
| Static files read via async/fs | `backend/maked_app.mbt:81` (`@fs.read_file`) | high |

## Deployment gaps (evidence of absence)

| Gap | Evidence | Confidence |
|-----|----------|------------|
| No systemd unit | `find` for *.service returns nothing | high |
| No health check endpoint | No `/health` route in `backend/api.mbt` | high |
| No structured logging | `println` in `backend/maked_app.mbt:61` is the only log output | high |
| No metrics/observability | No prometheus, open telemetry, or stats imports | high |
| No backup strategy | No cron, no WAL config, no backup code | high |

## What is no longer a gap

| Was a gap | Now | Source |
|-----------|-----|--------|
| No Dockerfile | `Dockerfile` builds the bundle and the native server, and `docker-compose.yml` runs it | `Dockerfile`, `docker-compose.yml` |
| No CI/CD beyond copilot setup | `.github/workflows/ci.yml` runs six jobs on every push, and `publish.yml` builds the release | `.github/workflows/ci.yml`, `.github/workflows/publish.yml` |
| No tests in CI | `moon test` runs for both targets, plus the contract, component, static and dynamic analysis gates | `.github/workflows/ci.yml` |
| No prebuilt binaries | Three platforms are built and attached to the release: linux-x86_64, macos-arm64, windows-x64 | `.github/workflows/publish.yml` |
