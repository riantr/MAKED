# MAKED on MoonBit

**A recursively self-evolving modelling framework** — designed around an adversarial knowledge loop.

Current release: **v0.1.7** — published as [`riantr/MAKED`](https://mooncakes.io) on mooncakes.io.

MAKED is a five-domain recursive cognitive architecture: Model → Data → Experience → Attack → Knowledge forms a closed ring, each domain being the adversarial overcoming of the one before it. The system drives state transitions through its own cycle — from arxiv research papers, to causal inference, to the pyroduct state machine — forming a self-driving closed loop of knowledge evolution.

Technical implementation: [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita@0.16.5) single-page frontend + a Flask-style micro-framework backend on [moonback](https://mooncakes.io), with SQLite storage. The state machine is [riantr/pyroduct](https://mooncakes.io/docs/riantr/pyroduct@0.1.32)@0.1.32, which also supplies the English rendering (`en_label` / `en_gloss` / `en_designation`) that every user-visible string here comes from.

What a person can do with it: put their own model, dataset or recorded failure into the [workspace](#workspace); run an exploration as a named [session](#sessions) whose every step is recorded with the reason it was possible, which can be replayed, forked, and exported as Markdown or JSON; read the loop itself — which positions the transition table offers, and which it refuses — and read it in sentences: [what each step did, and what the last five steps mean together](#the-loop-says-what-it-did); and read the run's worth as numbers: [whether it is still finding ground, and whether it is doing better than it was at the start](#the-run-is-measured-so-it-can-be-wrong).

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
| `GET /api/sessions/:id/export?format=md` | the session as Markdown, as a download, with the sentences and "The run so far" |
| `GET /api/sessions/:id/export?format=json` | the session as JSON (`maked.session.v1`), with the `summary` |

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

**The state under `session` is the *active* session.** A route that acts on
some other session names its subject as well, so the answer is about the
session the caller asked about: `POST /api/sessions/:id/rename` returns the
renamed session under `renamed`, next to the state it changed. Without that,
renaming a session that is not the live one would answer with a session the
caller never asked about — a response that looks right and is about the wrong
thing.

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
- The [measures](#the-run-is-measured-so-it-can-be-wrong) are on the panel and
  in the export: whether the run is still finding ground, how far it has
  ranged, and whether its last five steps found less than its first five did.

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
  narration.mbt     the sentences: what a step did, and what a run of steps means
  metrics.mbt       the measures: new ground, settling, spread, drift, and the
                    comparison of the run's beginning with its end
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
integration-test.ps1  the end-to-end tests over real HTTP
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

`ci.yml` runs four jobs: the unit tests on both targets, the two builds, the
container, and the **integration** job — the end-to-end suite over real HTTP,
which `ci.yml` did not run at all before. The script is PowerShell rather than
bash so that one file serves this machine and the runner: the runner's ubuntu
image carries `pwsh`.

### Mutation Checks

Beyond the mutation gate inside `bash ci.sh`, there are three scans that can be run separately:

```
.\tools\mutate-backend.ps1     # 25 mutations, 0 survived, 1 expected-equivalent
.\tools\mutate-frontend.ps1    # 15 mutations, 0 survived
.\tools\mutate-loop.ps1        # 16 mutations, 0 survived, 1 expected-equivalent
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
| unit-native | `moon test --target native` | 219 backend tests (includes the BDD suite below) |
| unit-js | `moon test --target js` | 62 frontend tests |
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

The cause was not root-caused — the same build works when the init issues a GET and a POST, and fails when it issues two GETs, which points at how two concurrent requests are dispatched rather than at anything in the loop engine. The safe rule to preserve: **issue the two initial fetches one after the other.** Re-batching them is a silent regression that no unit test catches; the [integration tests](#the-integration-tests-are-the-net-for-that-class-of-bug) check the source for it.

## The Integration Tests Are The Net For That Class Of Bug

```powershell
.\tools\integration-test.ps1              # builds the server, then runs 109 checks
.\tools\integration-test.ps1 -SkipBuild   # reuse the binary that is already built
```

The unit tests cannot catch the bug described above: it is a property of the
HTTP round-trip, not of any one function, and the container job only asks one
question of a running image. So the whole route table is exercised over real
HTTP, and the requests are fired **concurrently** with the assertions made on
what the server ended up with, not only on what came back.

That distinction is the whole point. A lost response and a lost write are the
same bug seen from two ends, so there are two checks, and they are kept
separately because they are kept in separate places:

| Check | What it holds the server to |
|---|---|
| eight concurrent GETs all came back with a body | the answers are not lost |
| eight concurrent POSTs all came back with a body | the answers are not lost |
| the server ended up with all eight of them | the loop's in-memory history grew |
| all eight of them were written down | the session's steps reached the disk |

The third and the fourth are not the same check. A server that accepts a
request and forgets to write it down passes the third — the loop's history is
in memory and it did grow — and fails the fourth. A write lost on the way to
the disk is lost for good: the screen would look right until the process
ended, and then the walk would be gone.

The script also checks the two ways a route can be useless while looking
fine: a route that answers 200 with a body nobody can read, and a refusal
that arrives as a 400 with an empty body — the "the button is broken but it
does not say why" failure, in a different costume.

**A test that has never failed is not known to work.** Each of the two halves
of the failure class was proved by breaking the server on purpose and
watching the suite go red:

| The probe | What went red |
|---|---|
| the step route stops recording the step | "and all eight of them were written down" |
| the step route answers with an empty body | "eight concurrent POSTs all came back with a body" |
| the rename route answers about the active session | "the answer names the renamed session" |

The third one matters because **the unit suite structurally cannot reach a
route.** A handler is `async (Request) -> Response` over moonback's own
request, and there is no way to build one in a test. Anything a route does is
covered by the integration test alone — which is why it runs in CI, and why
`ci.yml` grew an `integration` job.

Two of the checks read the source rather than the server, because the
regression they guard against *is* a source change:

- the frontend does not use `@cmd.batch`. The comments are stripped before
  the search, because a line that says "never with @cmd.batch" is the
  opposite of a violation, and a plain substring search cannot tell the two
  apart — it reads the comment as the crime.
- the start-up issues exactly one request.

### The First CI Run Of This Suite Failed, And It Was The Test

The first time this suite ran on the runner, seven checks went red: every
error response came back with the right status code and an **empty body**.
The server was answering perfectly well.

The cause was in the test. Windows PowerShell throws a `WebException` whose
response is an `HttpWebResponse`, and the body of that is a stream.
PowerShell 7 throws an `HttpResponseException` whose response is an
`HttpResponseMessage`, whose body is in `Content` and which has no stream at
all. A reader that knew only the first shape read every error on PowerShell 7
as an empty body — and the suite then reported a server that was sending
them correctly all along.

Two things came out of that, and both are in the script now:

- the reader understands both shapes, and the request asks for a 4xx not to
  throw where the PowerShell in use can do that, so the body is where a body
  always is;
- **the reader is checked before anything relies on it.** Three mocks — one
  per exception shape, and one for a response with no body at all — are read
  first, so a reader that cannot read an error says so plainly instead of
  turning seven refusals into seven empty ones.

The lesson is the one this whole file is about: a test that has only ever
run on one machine does not know what it does not know. The suite passed on
Windows, and the runner was the first place it was asked the question.

## The Loop Says What It Did

A person looking at the loop used to see labels rotating: `M · Action · Moved`,
then `D · Co-being · Moved`, then `E · Holding · Undecided`. The labels are
true and they are the machine's own vocabulary, and they tell a reader nothing
about what the machine is doing. "Self-evolution" read as a state machine
enjoying itself.

So the server now writes the sentences. Three of them, and they answer three
questions a person actually has:

| Question | Answer | Where it comes from |
|---|---|---|
| Why did it move? | "The model formulator moved from Standing to Freedom through Action. Action was the slot the table drives with here, and the cursor advanced to the data turbine." | `narration`, on the step |
| What did this step change? | the same sentence: the position before, the position after, the slot, and where the cursor went | `narration`, on the step |
| What do the last five steps mean together? | "The last 5 steps visited the model formulator once, the data turbine once, the experience absorber once, the attack generator once and the knowledge distiller once. Four of them moved a position. The group is Common Tongue." | `summary`, on the session state |

**The sentences are written on the server.** The machine's words still come
from pyroduct — the position labels, the slot designations, the domain
titles — but the sentences that tie them together are MAKED's, and they live
in one place: `backend/narration.mbt`. A second copy in the browser would be a
second thing to keep in step with the first, and the one in the browser would
be the one that drifts. The same reason the "why" line is a sentence written
by the server.

**The slot's provenance is part of the sentence.** "The table drives with
here" and "you chose this" are different claims, and the outcome alone does
not tell them apart. A sentence that said the table chose a slot the reader
picked would be the machine taking credit for a decision it did not make.

**A summary is a summary.** Five steps, not the whole history: past five the
sentence stops being about something a reader can hold in their head. The
number is in the sentence itself — "The last 5 steps" — so it is a fact about
the summary rather than a private choice inside it.

**The document you take away says it too.** The sentences are not only on the
screen: the Markdown export puts the sentence under each step's heading and
opens with "The run so far", and the JSON export carries the summary as a
`summary` field. An export that dropped them would be the list of labels
again — the exact thing the sentences exist to replace — and the export is
the artefact most likely to be read later, on its own, by someone who was not
there. So the export is held to the same wording as the page: the integration
test compares the exported document against the sentence the API served for
that step, rather than against a phrase the test wrote itself.

### A Step's Answer Carries The Session State
`POST /api/loop/step` answers with the loop status *and* the session state,
folded in under `session_state`. The panel needs both halves: what the
machine is doing now, and the history the steps are being recorded into.
They used to arrive on two requests, and the second was only made at
start-up — so the panel's step count stopped moving after the first click,
and its summary described a run one step out of date.

## The Run Is Measured, So It Can Be Wrong

A framework that cannot be measured cannot be falsified, and the question
this answers is the one a person has after twenty clicks: **is this run
better than the five steps I took before it?**

Before, the only answer was the step count, and the step count always says
yes. A run that has repeated the same ten positions for fifteen steps has a
bigger number than the five steps that found ten new ones, and looks like
progress on anything you can count.

So the loop is measured, and the measures are written next to the reading
they support.

| Measure | What it counts | The question it answers |
|---|---|---|
| **New ground** | steps in the window that reached a position the run had not been on before | is it still finding anything? |
| **Settling** | steps at the end of the window that reached nothing new | is it settling, or stuck? |
| **Slots used** | distinct drive slots in the window, out of the eight | is it walking one line through the table? |
| **Domains visited** | distinct domains in the window, out of the five | is the whole ring being used? |
| **Positions covered** | positions the run has stood on, out of the thirty-four | how much of the space has it reached? |

Each one is a number *and* a sentence, and the sentence is the part that
matters: "The last 5 steps reached no position the run had not been on
before: they added nothing to the map." is a claim that can be wrong, and a
reader who disagrees with it can look at the path and say so.

**Settling and stuck are not the same thing, and the measure says which one
it is looking at.** A run whose steps moved into positions it already knew
has *arrived* — that is the goal, and it reads "the run is settling rather
than exploring". A run whose steps did not move at all has *stopped*, and it
reads "the last 5 steps did not move the subject at all: the run is stuck,
not settling". The recorded outcome tells the two apart: "Moved" is the only
outcome that puts the subject somewhere else, and a reader told "settling"
about a run that cannot move would sit there waiting for a convergence that
is never coming.

**The measures are taken over a window of the last five steps, not over the
whole run.** This is the decision the whole design rests on. A number that
grows with the length of the run answers "how much did I do" rather than "how
good was it" — the length is the reader's own doing, so a measure that rose
because the run was longer would make every run look like an improvement. Five
is also the window the run summary already uses: one rule for "the last few
steps" in the whole product.

**And so the run is compared with itself.** The last five steps are measured
against the first five:

> The last 5 steps reached 0 new positions; the first 5 reached 5. The run is
> finding less new ground than it did at the start.

That sentence is the answer to "is twenty steps better than five". Often it
is "no", and saying so is the point: a run that has stopped finding ground
is a run whose remaining steps cost time and give nothing back.

Two things the measures deliberately do **not** do:

- **They are not combined into one score.** A single number out of five
  measures would hide which of them fell, and a number nobody can argue with
  is the thing this section exists to avoid. They are reported separately, and
  a reader can see which one is bad.
- **They are not derived in the browser.** The measures need the whole path
  and the size of the state space to say anything true, so the server
  computes them, in `backend/metrics.mbt`, and the client shows what it is
  given. The denominators — eight slots, five domains, thirty-four positions
  — are read out of pyroduct rather than written down in MAKED, so a table
  that grows makes the numbers grow with it.

The measures ride along with the session state, so they are current on the
loop panel after every step, and they are in the export: a reader with the
document and not the page has something to judge the run by.

### The First Real Run Said The Machine Was Stuck

The measures were written against hand-built paths, and the first run they
were pointed at was a real one: twelve clicks of the Step button on a fresh
server. The path says the ring went M → D → E → A → K, moved on every step,
and then — from step six on — did nothing at all:

```
1. M Action    Moved      Standing -> Freedom     (cursor: D)
2. D Co-being  Moved      Encounter -> Opening    (cursor: E)
3. E Holding   Moved      Honor -> Habit          (cursor: A)
4. A Unveiling Moved      Evil -> Shame           (cursor: K)
5. K Feedback  Moved      Cultivation -> Tranquility (cursor: M)
6. M Situation Undecided  Freedom -> Freedom      (cursor: M)
7. M Situation Undecided  Freedom -> Freedom      (cursor: M)
... and so on, for ever
```

The cursor comes back to the model formulator, the model formulator's drive
slot at that position is the one the table declines to choose from, and the
subject does not move — so the cursor does not advance, and the next step is
the same step. Stepping by hand does not help: at that position seven of the
eight slots have no edge at all, and the eighth is the undecided one.

Before the measures, that run looked like a run of twelve steps. It was
twelve steps of a machine that had stopped. The step counter cannot see the
difference between "exploring" and "going round in circles", which is the
whole reason the measures exist — and the first thing they did was say so:

> The last 5 steps reached no position the run had not been on before: they
> added nothing to the map.
>
> The last 5 steps did not move the subject at all: the run is stuck, not
> settling.
>
> The last 5 steps reached 0 new positions; the first 5 reached 5. The run is
> finding less new ground than it did at the start.

The wedge is a defect in the loop's behaviour, and it is reported here
rather than hidden: the machine is not allowed to invent a choice the
transition table declined to make — that would be a worse lie — but a run
that cannot move should say so, and there should be a way out. The next
step of this work is that way out.

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
- On this machine that means `.\build.ps1`, the three mutation scans, and
  `.\tools\integration-test.ps1` — the last one is the only gate that
  exercises a route, and a route is where a release can break

## License

Apache-2.0
