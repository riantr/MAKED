# MAKED_moonbit Architecture Evolution Summary

> **This document describes the past.** It is the summary of the analysis
> that produced MAKED's migration slices, written when the tree was a
> prototype: 76 tests, no CI, no container, no write path. Every slice it
> names has since been implemented. The findings are kept as they were
> written, because the reasoning is the point -- but read them as history.
> For the system as it is today, read
> [architecture/system-model.md](architecture/system-model.md) and the
> [README](README.md).

## Core Findings

By using the Architecture Visualization plugin for the analysis, **6 evolution slices** were identified for taking MAKED_moonbit from prototype to production-ready system, to be implemented in 3 phases.

## Key Problem Diagnosis

### 1. Loop blocking issue (most urgent)
**Status at the time of the analysis**: the hard-coded default drive slot of all 5 domains returned `Block` (no path) in the pyroduct transition table, so the Loop could not advance.

**Root cause**: pyroduct's transition table had no valid transition path configured for MAKED's 5 domain positions (Standing/Encounter/Honor/Evil/Discipline).

**Impact**: the core functionality was unusable — clicking the front-end Step button left the state unchanged.

**Resolution**: drive slots are no longer hard-coded per domain; they are now derived from the pyroduct transition table at runtime (`drive_slot(state)` prefers an edge whose outcome is `Moved`, otherwise the first exitable slot), and the API reports `blocked` / `undecided` honestly instead of rotating a cursor that changes no position. See "Slice 1 Completed" in `architecture/evolution-roadmap.md`.

### 2. Test coverage blind spot
**Status**: all 76 unit tests pass, but API integration tests are missing.

**Root cause**: moonback's Request type is opaque and cannot be instantiated in tests.

**Impact**: the complete request-response flow of the API endpoints cannot be verified, so refactoring carries high risk.

### 3. State management coupling
**Status**: module-level global state `g_loop_state : Array[LoopState]` uses the singleton pattern.

**Root cause**: MoonBit has no `let mut` module-level bindings, so the Array singleton is the standard workaround.

**Impact**: hard to test (mock state cannot be injected), hard to extend (multi-tenancy cannot be supported).

## Evolution Roadmap

### Phase 1: unlock the core functionality (1-2 weeks)

**Slice 1: unlock Loop forward progress**
- **Approach**: add a slot selector to the front end, use the `step_with_slot(slot)` API
- **Effort**: 1-2 days
- **Risk**: low
- **Validation**: the Loop can execute a complete M→D→E→A→K cycle

**Slice 2: integration test infrastructure**
- **Approach**: bring in an HTTP client testing framework, start a test server instance
- **Effort**: 2-3 days
- **Risk**: medium (moonback may lack test helpers)
- **Validation**: integration tests for the 3 Loop API endpoints pass

**Key decision**:
- Coordinate a change to the transition table with the pyroduct maintainers?
- Recommendation: wrap the slot selection logic at the MAKED layer first, while discussing the long-term solution in parallel

### Phase 2: harden the architecture (2-3 weeks)

**Slice 3: state management refactor**
- **Approach**: introduce the `AppContext` struct, dependency injection instead of global state
- **Effort**: 3-5 days
- **Risk**: high (breaks the existing API, all tests have to be updated)
- **Prerequisite**: Slice 2 (integration test safety net)
- **Validation**: multiple independent AppContext instances can be created

**Slice 4: configuration system**
- **Approach**: define the `LoopConfig` struct, load it from a file / environment variables
- **Effort**: 2-3 days
- **Risk**: low
- **Prerequisite**: Slice 3 (context passes the configuration)
- **Validation**: a configuration file can change Loop behaviour

### Phase 3: production readiness (2-3 weeks)

**Slice 5: state persistence**
- **Approach**: extend the database schema, persist after every step
- **Effort**: 2-3 days
- **Risk**: medium
- **Prerequisite**: Slice 3 (context manages the Database)
- **Validation**: state stays consistent after a server restart

**Slice 6: observability**
- **Approach**: structured logging + metrics export
- **Effort**: 2-3 days
- **Risk**: low
- **Prerequisite**: Slice 3 (context passes the Logger)
- **Validation**: the `/metrics` endpoint returns metrics data

## Dependency Graph

```
Slice 1 (unblock Loop)         ──┐
                                 ├──→ Slice 3 (state refactor) ──┬──→ Slice 4 (config system)
Slice 2 (integration tests)   ───┘                               ├──→ Slice 5 (persistence)
                                                                 └──→ Slice 6 (observability)
```

**Critical path**: Slice 1 → Slice 3 → Slice 4/5/6

## Risk Matrix

| Risk | Impact | Probability | Mitigation |
|------|------|------|----------|
| moonback does not support context passing | Slice 3 cannot be implemented | Medium | Validate with a POC first |
| pyroduct maintainers do not cooperate | Slice 1 option B is not viable | Low | Options A/C already exist as fallbacks |
| The refactor breaks existing functionality | Regression bugs | Medium | Slice 2 establishes an integration test safety net first |
| Persistence introduces performance problems | Increased response latency | Low | Asynchronous writes + batch commits |

## Next Steps

### This week (immediate)
1. **Implement Slice 1A**: add a slot selector to the front end
   - Add 8 slot buttons in `loop_view` in `frontend/views.mbt`
   - Each button calls `POST /api/loop/step?slot=<slot_name>`
   - Verify that the Loop can cycle through completely

2. **Evaluate the feasibility of Slice 2**: research moonback test support
   - Check whether the moonback documentation has testing utilities
   - If not, consider using a mock server or testing only the domain logic

### Next week (short term)
3. **Implement Slice 2**: establish integration test infrastructure
   - Create `backend/api_integration_test.mbt`
   - Start a test server (random port)
   - Write end-to-end tests for the 3 Loop API endpoints

4. **Evaluate the feasibility of Slice 3**: POC for moonback context support
   - Create an experimental branch
   - Try adding a context parameter to a single API endpoint
   - Verify whether moonback supports custom context passing

### This month (mid term)
5. **Decision point**: decide whether to push Slice 3 forward based on the POC result
   - If moonback supports context → roll the refactor out in full
   - If not → keep the current design and focus on the alternatives for Slices 4/5/6

## Success Criteria

- [ ] The Loop can execute a complete M→D→E→A→K cycle (Slice 1)
- [ ] API integration tests cover every endpoint (Slice 2)
- [ ] Multiple independent AppContext instances can be created (Slice 3)
- [ ] A configuration file can change Loop behaviour (Slice 4)
- [ ] State stays consistent after a server restart (Slice 5)
- [ ] Logs and metrics can be collected in a production environment (Slice 6)

## Deliverables

1. **`architecture/evolution-roadmap.md`**: the detailed evolution roadmap, containing the approach, effort, risks and validation signals of the 6 slices
2. **`architecture/current-vs-target.dot`**: comparison diagram of the current architecture against the target architecture (Graphviz DOT format)
3. **`architecture/migration-dependency.dot`**: migration dependency graph, showing the dependencies between slices and the critical path
4. **`architecture/evolution-summary.md`**: this document, summarising the core findings and the next steps

## Tool Usage Summary

This analysis used the following skills of the Architecture Visualization plugin:
- **`explore`**: recognised this as a "how does the architecture evolve" question and routed it to evolution-planner
- **`evolution-planner`**: analysed the gap between the current state and the target state, and formulated the migration slices and the roadmap
- **`graphviz`** (implicit): created the architecture diagram and the dependency graph in DOT format

The analysis is based on the following evidence:
- Code structure: the dependencies and the responsibility split of the 5 packages
- Test coverage: the distribution and the blind spots of the 76 tests
- Runtime behaviour: the Loop engine's Block problem
- Framework constraints: the opacity of moonback Request
