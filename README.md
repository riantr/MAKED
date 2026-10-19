# MAKED on MoonBit

**A recursively self-evolving modelling framework** — designed around an adversarial knowledge loop.

Current release: **v0.1.7** — published as [`riantr/MAKED`](https://mooncakes.io) on mooncakes.io.

MAKED is a five-domain recursive cognitive architecture: Model → Data → Experience → Attack → Knowledge forms a closed ring, each domain being the adversarial overcoming of the one before it. The system drives state transitions through its own cycle — from arxiv research papers, to causal inference, to the pyroduct state machine — forming a self-driving closed loop of knowledge evolution.

Technical implementation: [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita@0.16.5) single-page frontend + a Flask-style micro-framework backend on [moonback](https://mooncakes.io), with SQLite storage. The state machine is [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.32)@0.1.32, which also supplies the English rendering (`en_label` / `en_gloss` / `en_designation`) that every user-visible string here comes from.

What a person can do with it: put their own model, dataset or recorded failure into the [workspace](#workspace); run an exploration as a named [session](#sessions) whose every step is recorded with the reason it was possible, which can be replayed, forked, and exported as Markdown or JSON; and read the loop itself — which positions the transition table offers, and which it refuses.

## Core Concepts

### The Five-Domain Ring (M → D → E → A → K)

| Letter | Domain | Pyroduct Position | Drive Slot | Structural Relation |
|---|---|---|---|---|
| M | Model | Standing | derived from the table | the model stands, one foot in the past and one in the future |
| D | Data | Encounter | derived from the table | the model's inescapable encounter with the other (data) |
| E | Experience | Honor | derived from the table | experience absorbed as a reward bestowed by the idol |
| A | Attack | Evil | derived from the table | attack as the hard, cold thing that contracts the horizon |
| K | Knowledge | Discipline | derived from the table | knowledge distilled by enduring and clearing the reefs |

The ring order M → D → E → A → K is the path the logo draws clockwise, not the alphabetical order of the names.

### The Three-Layer State Machine

1. **Subject layer**: every domain owns an independent pyroduct state machine (34 positions × 8 slots × 53 transitions)
2. **Group layer**: group states that coordinate across domains (Scattered → Converging → Common Tongue → Settled, 20 states)
3. **Society layer**: not yet implemented

**Flexible starting point**: the loop may start at any domain (Model by default); switch the starting domain with `POST /api/loop/reset/:domain`. Each domain's state machine initialises independently — only the `current` pointer changes.

### Drive Slots Come from the Transition Table, Not from Semantics

Which slots can actually push a given position is answered by the pyroduct transition table: `exitable_slots` lists the slots that have an outgoing edge from that position, and `drive_slot` prefers one among them that genuinely moves. Of the 272 = 34 × 8 combinations, 228 are `Block` — no way out.

This rule was forced by measurement. Earlier, each domain hard-coded one "semantically corresponding" drive slot (Model meets data → Co-being); the five slots that came out of that had **not one outgoing edge** in the transition table: stepping the loop 18 times in a row left all five domains' positions completely unchanged, while the `next_domain` ring pointer rotated as usual and the page looked perfectly normal.

The behaviour now:

| Case | Behaviour |
|---|---|
| The table has a `Moved` outgoing edge | Take it; `drive_slot` reports the concrete slot |
| Only `Held` / `Same` outgoing edges | Record them faithfully; the position does not move and the cursor does not advance |
| Only `Open` outgoing edges | `undecided: true`, listing the candidates, **does not choose for the subject** |
| No outgoing edge at all | `blocked: true`, `drive_slot` is the empty string |

The eight slot names are **pyroduct's**, not MAKED's: `Situation`, `Orientation`, `Antecedent`, `Action`, `Feedback`, `Holding`, `Co-being`, `Unveiling`. MAKED displays them verbatim and its own parser reads them back out of the dependency, so a rename upstream reaches the page instead of being papered over with a second copy. The words differ from the code identifiers on purpose — the code identifier is `Occasion` while the reading is `Situation`, because *occasion* is a particular ceremony and 处境 is the situation one finds oneself in.

The ring order M → D → E → A → K → M is kept as the **presentation order** — it is the order the logo draws and the way the site narrates itself; but it is no longer treated as evidence that the state machine moved.

### The Adversarial Knowledge Loop

The key difference from a traditional data pipeline: the **Attack** domain. The model is not "fed" by data, it is "forged" by attack. Research papers are mapped onto pyroduct triggers by keyword heuristics, driving state machine transitions; DoubleML causal inference estimates the causal effect of a paper's "novelty" on its "influence".

## Quick Start

### Run it in a container

The first barrier in this project is not the code, it is the installation: a
MoonBit toolchain, a C toolchain, and a build step. If you only want to *look*
at MAKED, you should have to install none of that.

```bash
docker compose up --build
```

Then open <http://127.0.0.1:8080/>. The image holds the server and the browser
files it serves; the database is created and seeded on first run, and lives in
a named volume so your records survive the container being replaced.

**From v0.1.7**, the image is also published, so the clone is not
needed either:

```bash
docker run --rm -p 8080:8080 -v maked-data:/data ghcr.io/riantr/maked:latest
```

A package on ghcr.io is private until someone says otherwise, and only the
owner can say it: **Settings → Package settings → Change visibility →
Public**, once, for `riantr/maked`. Until that is done, the published image
pulls only with a GitHub token that can read it.

### Or take a prebuilt binary

**From v0.1.7**, every tag also carries a ready-to-run build for
three platforms, with the browser files beside the executable:

| Platform | Asset |
|---|---|
| Linux x86-64 | `maked-<version>-linux-x86_64.tar.gz` |
| macOS (Apple Silicon) | `maked-<version>-macos-arm64.tar.gz` |
| Windows x64 | `maked-<version>-windows-x64.zip` |

Unpack it, run the executable in that directory, and open
<http://127.0.0.1:8080/>. `RUN.txt` inside the archive says the same thing.
Downloads: <https://github.com/riantr/MAKED/releases>

### Or build it from source

```bash
.\build.ps1
moon run --release --target native cmd/server
```

Open <http://127.0.0.1:8080/>.

`build.ps1` builds the browser bundle, stages it to the backend's serving location, type-checks the backend, runs all tests, and builds the server. The backend serves both the JSON API and the frontend static files, so there is no second web server and no CORS configuration.

The container image and the prebuilt binaries are produced by the same release
run that publishes the package: `.github/workflows/publish.yml` builds all
three platforms and the image, and attaches the archives to the GitHub
release. The image is rebuilt and smoke-tested on every push by `ci.yml`, so a
broken image is caught before it is ever tagged.

### Environment Variables

| Variable | Default | Meaning |
|---|---|---|
| `MAKED_PORT` | `8080` | listen port |
| `MAKED_HOST` | `127.0.0.1` | listen address — `0.0.0.0` to be reachable from other machines |
| `MAKED_DB` | `maked.db` | SQLite file path |
| `MAKED_DIST` | `frontend/dist` | frontend build output directory |

## API

### Pages and Domains

| Route | Returns |
|---|---|
| `GET /api/status` | database path, page count, the five domains |
| `GET /api/pages` | all pages (sorted by sort) |
| `GET /api/pages/:slug` | a single page, or 404 |
| `GET /api/domains` | the five domains (ring order) |

### Workspace

The user's own records. Until this existed the API was read-only: everything the
site served was seed content written by the maintainer.

| Route | Returns |
|---|---|
| `GET /api/entries` | every workspace record, oldest first, plus the five domain letters |
| `POST /api/entries` | create one from `{domain, title, body}`; 201 with the stored record, or 400 with a reason |
| `DELETE /api/entries/:id` | remove one; 200, or 404 if there was no such record |

`domain` must be one of `M`, `D`, `E`, `A`, `K`; `title` must not be blank.
Both limits are enforced server-side and the refusal names the field and the
limit, so a rejected record says why rather than failing silently.

**There is no auth.** Anyone who can reach the port can read and delete every
record. That is acceptable while the server binds localhost and stores one
person's working set, and it stops being acceptable the moment the server is
published — see the entry-barrier work, which is what makes that reachable.

#### The workspace screen

`/workspace` is the route where those records are written and read. It is a
client-side route, so it survives a cold load and a deep link alike.

- The domain is chosen by **pressing its letter**, not by picking from a
  dropdown. The five letters are the whole vocabulary, and a row of five
  buttons says at a glance which one is in effect.
- The form refuses locally what the server would refuse anyway — no domain, or
  a blank title — and says which one it was, without a round trip.
- Every outcome is stated in words in the same place: saved, refused, or the
  server unreachable. A button that does nothing is the failure this project
  exists to remove, so the screen never stays quiet about one.
- The records already saved sit next to the form that made them, each with its
  own delete button.

The list arrives with the pages in one `/api/bootstrap` request. Two requests at
start-up is the shape that used to lose responses: two GETs in flight at once
meant the client sometimes never saw either answer, and the screen sat on
"Loading…" with nothing in the console to say why. The chain is one request at
a time, and `/api/bootstrap` and `/api/entries` are sent as `no-store` — a
cached copy of the list would be a stale claim about what the server holds.

### Sessions

A named exploration, kept. The loop state used to be a module-level singleton:
one exploration, no name, no history that outlived the process, and nothing to
take away. A user who spent twenty steps working out why their model would not
move had nowhere to put any of it, and restarting the server threw it away.

| Route | Returns |
|---|---|
| `GET /api/sessions` | every session, most recently touched first, with the active one marked |
| `POST /api/sessions` | create one from `{name}`; 201 with the session state, or 400 with a reason |
| `GET /api/sessions/:id` | one session: its path, the branches off it, and the live loop status |
| `POST /api/sessions/:id/activate` | make it the active session and replay it into the loop |
| `POST /api/sessions/:id/replay` | rewind to `{step}`; the steps beyond it are kept, not deleted |
| `POST /api/sessions/:id/branch` | fork a new session at `{step}`, named `{name}`; 201 |
| `POST /api/sessions/:id/rename` | rename it from `{name}` |
| `DELETE /api/sessions/:id` | forget it and its steps |
| `GET /api/sessions/:id/export?format=md` | the session as Markdown, as a download |
| `GET /api/sessions/:id/export?format=json` | the session as JSON (`maked.session.v1`) |

Every step taken through the loop is recorded in the active session, with the
domain, the slot, the outcome, the positions before and after, and **why the
step was possible**: which slots had an outgoing edge at that position, which
had none, whether the table declined to choose, and what its own drive slot
was. That snapshot is taken when the step is taken, not looked up afterwards, so
it describes the moment rather than the table as it stands now.

**A session's steps are a tree, not a list.** Each step records the step it
came from, and the session records which step it is standing on. Rewinding moves
the head back and leaves the steps beyond it in the table as the other
branches; a list would have had to delete them, and "let me try the other road
from step 7" is the whole reason to keep a history at all. A fork copies the
path up to a step into a new session and leaves the original exactly as it was.

**Replay re-derives, it does not restore.** A step records the domain and the
slot, not a snapshot of the positions, so putting a session back together runs
those steps through the transition table again. What comes back is the state the
table really produces, so a record that had drifted from the table shows up as a
different result rather than as a quiet lie.

The server restores the most recently touched session on start-up, so a restart
is not amnesia. The whole session state — the list, the active session, its
path, the branches off it — rides along in `/api/bootstrap`, so the start-up
chain stays two requests rather than three.

#### The sessions screen

`/sessions` is the route where the history is read. Like `/workspace`, it is a
client-side route, so it survives a cold load and a deep link alike.

- The timeline is one entry per step: what moved, from where to where, what the
  transition table said, and why that step was possible at all.
- Each step offers **Go back to here** (rewind; the steps beyond it are kept and
  become the roads not taken) and **Fork from here** (a new named session with a
  copy of the path up to that step).
- A session can be renamed, exported as Markdown or JSON, opened again later,
  and deleted. A delete takes two presses, because a history is worth more than
  the click that deletes it.
- The "why" line is written by the server. A second copy of that rule in the
  browser would be a second thing to keep in step with the first.

### State Loop

| Route | Returns |
|---|---|
| `GET /api/loop/status` | current domain, position, history, domain states, group state, mode |
| `GET /api/loop/slots` | the eight drive slots (URL-safe name + English designation + English gloss) |
| `GET /api/loop/mode` | the current mode (structured/free) |
| `POST /api/loop/step` | advance one ring step (using the current domain's default drive slot) |
| `POST /api/loop/step/:slot` | advance one ring step (using a named slot: the URL-safe name or the English designation, case-insensitively) |
| `POST /api/loop/reset` | reset to the initial state |
| `POST /api/loop/reset/:domain` | reset with the given domain as the starting point (accepts a letter or the English name) |
| `POST /api/loop/mode/:mode` | switch mode (structured/free) |
| `GET /api/loop/continuations?depth=N` | the model's own "all possible continuations" (`after_open`) |

Besides the original fields, `GET /api/loop/status` also returns `drive_slot_name`, `blocked`, `undecided`,
`open_slots` (the slots that really have an outgoing edge at the current position, with their outcomes),
and `at_anchor` / `drivable` for each domain.

`/api/loop/continuations` is built on pyroduct's `after_open` — the transition table's own answer to "all
possible continuations", as distinct from `expand`, which requires the caller to name a slot sequence
up front. It lists only edges that really exist and **does not choose for the subject**: when the same
position is reachable by several routes it is listed once at the shortest distance, and the slot-grouped
view is where the alternative routes become visible.

### Loop Modes

- **Structured mode**: follows the ring order M→D→E→A→K, uses the designated drive slot for each domain, and always advances to the next domain after a step
- **Free mode**: driven by any slot, exploring the state space; it stays in the current domain when the outcome is `Block` ("no way out"), otherwise it advances

Structured mode is the default. Free mode allows exploring transition paths through the pyroduct state space that do not follow the ring order.

### Research Loop

| Route | Returns |
|---|---|
| `GET /api/research/papers` | arxiv SNN papers + trigger mapping |
| `POST /api/research/drive` | fetch papers and drive the loop |
| `GET /api/research/causal` | DoubleML causal inference results |

## Project Structure

```
backend/          micro-framework, storage layer, API routes, state loop engine
  app.mbt           App: route table + ordered middleware chain
  request.mbt       Request wrapper
  response.mbt      Response value and dispatch
  database.mbt      SQLite storage layer
  pages.mbt         content model + nine pages of seed data
  api.mbt           JSON API routes
  loop.mbt          five-domain ring loop engine (subject + group state machines)
  session.mbt       named explorations: the step tree, replay, forking, export
  research.mbt      arxiv research paper fetching and trigger mapping
  causal.mbt        DoubleML causal inference
  maked_app.mbt     assembly, static files, SPA fallback
frontend/         rabbita single-page application
  app.mbt           state machine and router
  views.mbt         header, domain cards, page rendering
  entries.mbt       workspace records and the draft that becomes one
  session.mbt       sessions and the step timeline, decoded from the server
  logo.mbt          five-ring mark (SVG)
  loop_state.mbt    loop state visualisation
  page.mbt          typed accessors for the backend JSON
cmd/server/       native entry point
cmd/web/          js entry point (browser bundle)
Dockerfile        container image: build stage, then a runtime stage with
                  no toolchain in it
docker-compose.yml  the container with a volume for the records
packaging/RUN.txt what a user reads after unpacking a prebuilt binary
tools/            CI and test tooling
ci.sh             CI pipeline (15 gates)
```

## CI Pipeline

```bash
bash ci.sh              # all 15 gates
bash ci.sh --quick      # skip the slow gates
bash ci.sh --unit-only  # type check + unit tests only
```

There is no bash on this Windows machine, so `ci.sh` cannot be run locally; the parts that can be reproduced
locally are covered by `.\build.ps1`
(bundle → check → backend tests → frontend tests → server build). Of the 15 gates, 9 exist only as a
shell implementation and cannot be reproduced locally.

### Mutation Checks

Beyond the mutation gate inside `bash ci.sh`, there are three scans that can be run separately:

```
.\tools\mutate-backend.ps1     # 11 mutations, 0 survived, 1 expected-equivalent
.\tools\mutate-frontend.ps1    # 15 mutations, 0 survived
.\tools\mutate-loop.ps1        # 14 mutations, 0 survived, 1 expected-equivalent
```

That one EQUIV in `mutate-loop` is deliberate: measurement shows that all 34 positions **do have outgoing
edges**, so the `None` branch of `drive_slot` is currently unreachable. It stays in the roster on purpose —
if the transition table ever gains a genuinely dead position, it will flip to `KILLED`, and that is exactly
the signal we want.

| Gate | Tool | What it checks |
|---|---|---|
| native-check | `moon check --target native` | backend type safety |
| js-check | `moon check --target js` | frontend type safety |
| fmt | `moon fmt --check` | code formatting |
| tree | `moon tree` | dependency audit |
| unit-native | `moon test --target native` | 171 backend tests (includes the BDD suite below) |
| unit-js | `moon test --target js` | 42 frontend tests |
| coverage | `moon test --enable-coverage` | coverage |
| bench | `moon bench` | benchmarks |
| prove | `moon prove` | formal verification (Why3) |
| bdd | `bdd_test.mbt` | 13 Given/When/Then scenarios |
| contract | `contract-test.sh` | 46 API contract assertions |
| component | `component-test.sh` | 6 cross-module integration checks |
| sast | `sast-check.sh` | 11 static security checks |
| mutation | `mutation-test.sh` | 10 mutation tests (80% kill rate) |
| dast | `dast-check.sh` | 5 dynamic security checks |

## Request Handling

Three layers, outside in:

1. `static_files`: serves real files from `frontend/dist`
2. `spa_fallback`: an unmatched browser navigation returns `index.html` (so `/about` cold-loads correctly)
3. the router: serves `/api/...`, everything else returns a JSON 404

The fallback excludes `/api/` paths. A final segment containing a dot is treated as an asset (a missing stylesheet returns 404 rather than HTML). A route conflict aborts startup (`fail`, not `raise`).

## The Two Initial Fetches Are Chained, Not Batched

`init` issues **one** request (`GET /api/bootstrap`). The loop status (`GET /api/loop/status`) is requested from the `Loaded` handler, after the first response has already arrived.

The bootstrap carries everything else the app needs to start: the pages, the workspace entries, and the session state (the list of sessions, the active one, its path and the branches off it). Each of those rode along with the first response rather than needing a request of its own, because a third hop at start-up is where this chain used to die.

Batching the two with `@cmd.batch` looks equivalent and is not. With the batch, every click-initiated POST still reached the server and still changed state, but **no response ever came back**: Step, Reset and the slot buttons all mutated the backend while the view stayed frozen on stale data, with no error shown anywhere. Chaining the second request restores them.

The cause was not root-caused — the same build works when the init issues a GET and a POST, and fails when it issues two GETs, which points at how two concurrent requests are dispatched rather than at anything in the loop engine. The safe rule to preserve: **issue the two initial fetches one after the other.** Re-batching them is a silent regression that no unit test catches.

## Deep Links Need A `<base>` Tag

`index.html` carries `<base href="/" />`, and it is load-bearing.

rabbita resolves a relative request URL against `document.baseURI`, which
without that tag is the *document's* URL. At `/` that happens to be the origin
and everything works, but on `/about` the app asked the server for
`/about/api/pages`; the SPA fallback answered it with `index.html`, the JSON
parse failed, and the page said "Server unavailable" with nothing logged.

Client-side navigation hid this completely: `push_url` changes the URL without
reloading, so the document stayed at `/` and the bug was invisible until
anything forced a real load of a sub-path — a refresh, a shared link, a cold
open of `/about`.

## SQLite Storage Layer

Three key behaviours (verified, not assumed):

1. `prepare` only compiles, it does not execute. A statement that was never `step`ped is silently dropped by `finalize` — DDL goes through `exec`
2. A finished statement must be `reset` before it can be reused. `bind` overwrites the bindings in place
3. `finalize` reports the error code of the most recent evaluation — a failed `step` poisons the following `finalize`

Four tables: `pages` (the site's own content), `entries` (the user's workspace
records), and `sessions` + `session_steps` (the named explorations and the
tree of steps inside them). The last two are what make the history outlive the
process: the steps are rows, not memory.

## Release Conventions

- Patch version progression: v0.1.x (no minor releases unless specified)
- Gitee for day-to-day storage, GitHub for releases
- Run `bash ci.sh` and get an all-green result before releasing

## License

Apache-2.0
