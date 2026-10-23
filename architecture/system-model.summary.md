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

3. **Thin framework layer**: the backend's `App` is ~150 lines and deliberately
   mirrors Flask's shape. It does not reimplement routing; it adapts between
   `async (Request) -> Response` and moonback's `(Request, Responder) -> Unit`.

4. **A write path for the reader's own work**: 10 pages stored in SQLite and
   seeded on every start, but the reader's own records, explorations and
   tables are writable. The original django CMS had admin + Celery; this
   scope is the ten public pages plus the reader's own working set.

5. **Elm-style frontend**: rabbita TEA (Model/Update/View/Subscription). One
   HTTP request at startup, then client-side routing via History API.

6. **Well-tested invariants**: 562 tests across backend and frontend, focused
   on silent-failure modes (SQLite statement lifecycle, ring geometry, JSON
   decoding total functions), plus 229 mutation anchors and 370 integration
   checks against a server that is really running.

## Gaps and unknowns

- **Deployment**: the container image is built on every push, but there is no
  IaC and no hosted environment.
- **Monitoring/observability**: request logging is one line per request to
  stderr. The run's own metrics are computed and ride in the session payload,
  but nothing exports them: no `/metrics` endpoint, no tracing, no alerting.
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

The claims here are about the tree, so they rot when the tree changes and
nothing notices. The evidence document carries the file and line for each
one; a reader who wants to know whether a claim still holds should check it
there.
