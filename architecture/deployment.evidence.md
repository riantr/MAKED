# Deployment Evidence

## Runtime topology

| Claim | Source | Confidence |
|-------|--------|------------|
| Single native process serves everything | `cmd/server/main.mbt:25-52` | high |
| Listens on port from MAKED_PORT env (default 8080) | `cmd/server/main.mbt:26` | high |
| SQLite path from MAKED_DB env (default maked.db) | `cmd/server/main.mbt:27` | high |
| Static files from MAKED_DIST env (default frontend/dist) | `cmd/server/main.mbt:28` | high |
| Warns if dist directory not found at startup | `cmd/server/main.mbt:29-32` | high |
| Middleware order: routes → static → spa_fallback | `cmd/server/main.mbt:41-46` | high |
| No TLS, no reverse proxy, localhost only | `cmd/server/main.mbt:48` (prints `127.0.0.1`) | high |

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
| SQLite accessed via FFI, not network | `backend/database.mbt:27` (`sqlite3.Connection::open`) | high |
| Static files read via async/fs | `backend/maked_app.mbt:70` (`@fs.read_file`) | high |

## Deployment gaps (evidence of absence)

| Gap | Evidence | Confidence |
|-----|----------|------------|
| No Dockerfile | `find` for Dockerfile returns nothing | high |
| No docker-compose.yml | `find` returns nothing | high |
| No systemd unit | `find` for *.service returns nothing | high |
| No CI/CD beyond copilot setup | Only `.github/workflows/copilot-setup-steps.yml` exists | high |
| No health check endpoint | No `/health` route in `backend/api.mbt` | high |
| No structured logging | `println` in `backend/maked_app.mbt:38` is the only log output | high |
| No metrics/observability | No prometheus, open telemetry, or stats imports | high |
| No backup strategy | No cron, no WAL config, no backup code | high |
