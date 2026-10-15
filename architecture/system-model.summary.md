# System Model Summary

## What was modelled

The current-state architecture of MAKED_moonbit: a two-target MoonBit web
application with a native backend (Flask-style micro-framework on moonback +
SQLite) and a JavaScript frontend (rabbita SPA).

## What each artifact answers

| Artifact | Question it answers |
|----------|-------------------|
| `system-model.md` | What is this system? What are the key decisions? |
| `system-model.dsl` | What are the system boundary, actors, and containers? (C4) |
| `system-model.dot` | What modules exist and what depends on what? (Component graph) |
| `system-model.evidence.md` | Which files back each claim? |

## Key findings

1. **Clean two-target split**: backend is native-only, frontend is js-only.
   Each package declares its own target; the module declares the union.

2. **Single-process deployment**: one native binary serves API + static + SPA
   fallback. No reverse proxy, no CORS configuration needed.

3. **Thin framework layer**: the backend's `App` is ~135 lines and deliberately
   mirrors Flask's shape. It does not reimplement routing; it adapts between
   `async (Request) -> Response` and moonback's `(Request, Responder) -> Unit`.

4. **Read-only content model**: 9 pages stored in SQLite, seeded on every
   start. No auth, no write API. The original django CMS had admin + Celery;
   this scope is the nine public pages only.

5. **Elm-style frontend**: rabbita TEA (Model/Update/View/Subscription). One
   HTTP request at startup, then client-side routing via History API.

6. **Well-tested invariants**: 16 tests across backend and frontend, focused
   on silent-failure modes (SQLite statement lifecycle, ring geometry, JSON
   decoding total functions).

## Gaps and unknowns

- **Deployment**: no IaC, Dockerfile, or deployment config found. The system
  appears to run locally via `moon run cmd/server`.
- **CI/CD**: a GitHub Actions workflow exists (`.github/workflows/copilot-setup-steps.yml`)
  but was not inspected.
- **Monitoring/observability**: request logging is one line per request to
  stdout. No metrics, tracing, or alerting.
- **Users**: no analytics, no auth. Unknown whether anyone besides the
  developer uses this.

## Next actions

- Render `system-model.dot` with Graphviz (`dot -Tsvg`) to produce a visual
  component graph.
- Open `system-model.dsl` in Qoder Canvas to view C4 diagrams.
- If the system grows, consider adding a deployment topology model.

## Maintenance note

Regenerate this model when:
- A new package is added to the module.
- The middleware chain or routing strategy changes.
- A write path or auth layer is introduced.
- The frontend switches from rabbita to another framework.
