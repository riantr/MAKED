# MAKED_moonbit Evolution Roadmap

## Current Status (evidence-backed)

### Architecture Structure
- **5 packages**: backend (native lib), frontend (js lib), cmd/server (native exe), cmd/web (js exe), root
- **Dual-target compilation**: native (backend service) + js (frontend SPA)
- **Core integration**: the pyroduct state machine drives the five-domain M→D→E→A→K loop

### Test Coverage
- All 76 tests pass (64 native + 12 JS)
- Unit tests cover: Loop engine, page data, response construction, App routing
- Missing: API integration tests, Request wrapper tests

### Key Problems
1. ~~**Loop blocking**~~ **Resolved** (see "Slice 1 Completed" below)
2. **State management**: module-level mutable state uses an `Array[LoopState]` singleton pattern
3. **Test blind spot**: moonback Request is an opaque type, so test instances cannot be constructed
4. **No configuration system**: transition rules are hard-coded inside the pyroduct dependency

---

## Slice 1 Completed (2026-10-17)

**Root cause**: `Domain::slot_to_next` hard-coded one drive slot per domain by semantics — the rationale being "this slot represents this domain's structural relation to the next domain". The five slots that rationale produced had **not a single outgoing edge** in the pyroduct transition table. Measured: after 18 consecutive steps the positions of all five domains had not moved at all, every outcome was `Block` (no path); meanwhile the `next_domain` ring pointer kept rotating as usual, so the page looked perfectly normal.

**Fix** (option 2 + 3):

| Change | Location |
|---|---|
| Removed `Domain::slot_to_next`; `drive_slot(state)` now derives the slot from the transition table | `backend/loop.mbt` |
| `exitable_slots(state)` exposes the slots that genuinely have an outgoing edge from the current position | `backend/loop.mbt` |
| `is_undecided(state)`: honestly flags the case where the table refuses to choose, instead of choosing on behalf of the subject | `backend/loop.mbt` |
| `StepEffect`: Moved/Held/Same count as progress, Undecided/Block do not | `backend/loop.mbt` |
| `to_json`'s `current_position` now reads the real position (it used to read a static anchor) | `backend/loop.mbt` |
| status adds `open_slots` / `blocked` / `undecided` / `at_anchor` | `backend/loop.mbt` |
| `GET /api/loop/continuations?depth=N`: uses `after_open` to hand back the model's own continuations | `backend/api.mbt` |

**Measured result** (real service via `moon run`):

```
Initial:  M Standing  drive=Action  open_slots=[act/Moved]
1: M xAction = Moved    M=Freedom   cursor=D
2: D xCo-being = Moved              cursor=E
3: E xHolding = Moved              cursor=A
4: A xUnveiling = Moved            cursor=K
5: K xFeedback = Moved            cursor=M
6: M xSituation = Undecided   M=Freedom    cursor=M   ← the table refuses to choose, the cursor does not advance
```

`/api/loop/continuations` starting from Encounter: `Encounter@1 Opening@1 Frustration@2 Selfhood@3`.

**Verification**: `tools/mutate-loop.ps1`, 14 mutations, 0 unexpected survivors (1 EQUIV: all 34 positions have an outgoing edge, so `drive_slot`'s None branch is currently unreachable and stays on the books). Tests 137 → 152.

**New API fields**: `GET /api/loop/status` additionally returns `drive_slot_name` / `blocked` / `undecided` / `open_slots` / `at_anchor` / `drivable`; `GET /api/loop/continuations` is a new endpoint.

---

## Target State

### Functional Goals
- The Loop can advance normally through the M→D→E→A→K cycle
- Support custom transition thresholds/rules
- Loop state can be persisted
- Complete API test coverage

### Architectural Goals
- Explicit state management (dependency injection instead of module-level globals)
- Configuration-driven transition rules
- Clear layering: domain logic / application services / infrastructure
- Production-ready observability (logging, metrics)

---

## Evolution Slices (ordered by dependency)

### Slice 1: Unlock Loop Forward Progress ✅ Completed

See "Slice 1 Completed" above. What was actually adopted was neither the originally recommended A (add a front-end slot selector) nor B (modify pyroduct), but **letting the transition table speak**: the drive slot is derived from the table, `blocked` is reported honestly when a position has no outgoing edge, and `undecided` is reported honestly when the table refuses to choose, in which case the candidates are handed to a human. Option A only exposes the dead end; the loop still does not move.

---

### Slice 2: Integration Test Infrastructure (high priority, medium risk)

**Problem**: the complete request-response flow of the API endpoints cannot be tested

**Approach**:
1. Bring in an HTTP client testing framework (e.g. MoonBit's http testing tooling)
2. Start a test server instance (random port)
3. Write end-to-end tests:
   - `GET /api/loop/status` returns the correct JSON
   - `POST /api/loop/step` advances the state
   - `POST /api/loop/reset` resets the state

**Technical challenges**:
- moonback may lack test helper tooling
- The server start/stop lifecycle has to be handled

**Validation signals**:
- Integration tests for the 3 Loop API endpoints pass
- The coverage report no longer excludes the integration test blind spot

**Dependencies**: none

---

### Slice 3: State Management Refactor (medium priority, high risk)

**Problem**: the module-level `Array[LoopState]` singleton is hard to test and to extend

**Current pattern**:
```moonbit
let g_loop_state : Array[LoopState] = [LoopState::new()]
pub fn get_loop_state() -> LoopState { g_loop_state[0] }
```

**Target pattern**: explicit dependency injection
```moonbit
// Application context
struct AppContext {
  loop_state : Ref[LoopState]  // or a similar reference type
  database : Database
  config : AppConfig
}

// API handlers receive the context
app.get("/api/loop/status", ctx => {
  let state = ctx.loop_state.get()
  Response::json(state.to_json())
})
```

**Migration steps**:
1. Create the `AppContext` struct
2. Change the `maked_app` builder to accept a context
3. Migrate the API handlers step by step from global functions to context methods
4. Delete the module-level global state

**Risks**:
- Breaking existing API signatures
- All tests have to be modified
- moonback may not support context passing

**Validation signals**:
- All existing tests pass (may need updating)
- Multiple independent AppContext instances can be created
- Unit tests can inject a mock context

**Dependencies**: Slice 2 (integration tests ensure the refactor does not break functionality)

---

### Slice 4: Configuration System (medium priority, low risk)

**Problem**: transition rules are hard-coded in pyroduct and cannot be adjusted at runtime

**Approach**:
1. Define the configuration struct:
```moonbit
struct LoopConfig {
  default_slot_strategy : String  // "default" | "round_robin" | "random"
  fallback_slots : Map[Domain, Array[Slot]]
  max_retries_on_block : Int
}
```

2. Load the configuration from a file / environment variables
3. The Loop engine uses the configuration to decide the slot selection strategy

**Validation signals**:
- Loop behaviour can be changed through a configuration file
- Tests pass under different configurations

**Dependencies**: Slice 3 (context passing is needed to deliver the configuration)

---

### Slice 5: State Persistence (low priority, medium risk)

**Problem**: the server loses Loop state on restart

**Approach**:
1. Extend the database schema:
```sql
CREATE TABLE loop_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),  -- single-row table
  current_domain TEXT NOT NULL,
  history_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

2. Persist after every step
3. Restore from the database at startup

**Validation signals**:
- Loop state stays consistent after a server restart
- Concurrent access does not corrupt the state

**Dependencies**: Slice 3 (context is needed to manage the database connection)

---

### Slice 6: Observability (low priority, low risk)

**Problem**: missing the logging and metrics that a production environment needs

**Approach**:
1. Structured logging:
   - Every Loop step logs: domain, slot, outcome, duration
   - API requests log: method, path, status, duration

2. Metrics export:
   - Loop iteration count
   - Outcome distribution (Moved/Held/Block/Open/Same)
   - API request latency

**Validation signals**:
- Log output follows the structured format
- Metrics are reachable through the `/metrics` endpoint

**Dependencies**: Slice 3 (context passes the logger / metrics collector)

---

## Evolution Roadmap

```
Phase 1 (immediate): unlock the core functionality
├─ Slice 1: unblock the Loop with step_with_slot
└─ Slice 2: establish integration test infrastructure

Phase 2 (short term): harden the architecture
├─ Slice 3: state management refactor (dependency injection)
└─ Slice 4: configuration system

Phase 3 (mid term): production readiness
├─ Slice 5: state persistence
└─ Slice 6: observability
```

## Key Decision Points

### Decision 1: pyroduct transition table strategy
→- **Constraint**: pyroduct is an external dependency, modifying it requires coordination
- **Options**:
  - Wait for a pyroduct update (passive)
  - Fork pyroduct and customise it (proactive)
  - Wrap the slot selection logic at the MAKED layer (compromise)
- **Recommendation**: implement the compromise first, and communicate with the pyroduct maintainers in parallel

### Decision 2: timing of the state management refactor
- **Constraint**: the refactor breaks the existing API and requires updating all tests
- **Risk**: the moonback framework may not support the context-passing pattern
- **Mitigation**: run a small-scale experiment first (a single API endpoint), then roll it out once feasibility is confirmed

### Decision 3: testing strategy
- **Constraint**: moonback Request is an opaque type
- **Options**:
  - Wait for moonback to provide test helpers
  - Use a mock server instead of real requests
  - Test only the logic that does not depend on Request
- **Recommendation**: a hybrid strategy — test domain logic first, and wait for framework support before adding integration tests

## Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|------|------|----------|
| moonback does not support context passing | Slice 3 cannot be implemented | Medium | Validate with a POC first |
| pyroduct maintainers do not cooperate | Slice 1 option B is not viable | Low | Options A/C already exist as fallbacks |
| The refactor breaks existing functionality | Regression bugs | Medium | Slice 2 establishes an integration test safety net first |
| Persistence introduces performance problems | Increased response latency | Low | Asynchronous writes + batch commits |

## Next Steps

1. **This week**: implement Slice 1A (add a slot selector to the front end), verify that the Loop can cycle through completely
2. **Next week**: implement Slice 2 (integration test infrastructure), establish a regression test safety net
3. **This month**: evaluate the feasibility of Slice 3 (moonback context support), decide whether to push the refactor forward

---

## Success Criteria

- The Loop can execute a complete M→D→E→A→K cycle (Slice 1)
- API integration tests cover every endpoint (Slice 2)
- Multiple independent AppContext instances can be created (Slice 3)
- A configuration file can change Loop behaviour (Slice 4)
- State stays consistent after a server restart (Slice 5)
- Logs and metrics can be collected in a production environment (Slice 6)
