///| SQLite storage for MAKED page content.
///
/// The public surface is deliberately small -- `open`, `page_by_slug`,
/// `all_pages`, `seed` -- and every statement is prepared, stepped and
/// finalized inside a helper. Three SQLite behaviours drove that shape, each
/// verified against the real package rather than assumed:
///
/// 1. `prepare` only *compiles*. A statement that is never `step`ped never
///    runs, and `finalize` alone silently discards it -- so DDL goes through
///    `exec`, which always steps.
/// 2. A statement that has run to completion must be `reset` before it can be
///    reused with different parameters. `bind` overwrites bindings in place,
///    so re-binding without a reset re-runs the old query with new values.
/// 3. `finalize` reports the error code of the most recent evaluation, so a
///    failed `step` poisons the later `finalize`; the helpers here absorb that
///    where the error has already been handled, and propagate it where it has
///    not.

///|
pub(all) struct Database {
  connection : @sqlite3.Connection
}

///|
/// Open (creating if absent) the database at `path`.
pub fn Database::open(path : String) -> Database raise {
  let connection = @sqlite3.Connection::open(path)
  let db = { connection, }
  db.migrate()
  db
}

///|
pub fn Database::close(self : Database) -> Unit raise {
  self.connection.close()
}

///|
/// Run a statement for its effect. Always steps: a prepared-but-unstepped
/// statement is a no-op that looks like it worked.
fn Database::exec(self : Database, sql : String) -> Unit raise {
  let stmt = self.connection.prepare(sql)
  // finalize() re-raises whatever the last evaluation reported, so the step
  // error has to be read here or it would resurface from finalize with a
  // misleading call site.
  let step_error = try {
    ignore(stmt.step())
    None
  } catch {
    err => Some(err)
  }
  let finalize_error = try {
    stmt.finalize()
    None
  } catch {
    err => Some(err)
  }
  match step_error {
    Some(err) => raise err
    None =>
      match finalize_error {
        Some(err) => raise err
        None => ()
      }
  }
}

///|
/// Create the schema if it is not there yet.
///
/// `CREATE TABLE IF NOT EXISTS` keeps this idempotent, so starting the server
/// twice against the same file is safe and does not wipe edited content.
fn Database::migrate(self : Database) -> Unit raise {
  self.exec(
    (
      #|CREATE TABLE IF NOT EXISTS pages (
      #|  slug    TEXT PRIMARY KEY,
      #|  title   TEXT NOT NULL,
      #|  letter  TEXT NOT NULL DEFAULT '',
      #|  role    TEXT NOT NULL DEFAULT '',
      #|  summary TEXT NOT NULL DEFAULT '',
      #|  body    TEXT NOT NULL DEFAULT '',
      #|  nav     INTEGER NOT NULL DEFAULT 0,
      #|  sort    INTEGER NOT NULL DEFAULT 0
      #|)
    ),
  )
  self.exec("CREATE INDEX IF NOT EXISTS pages_sort ON pages (sort)")
  // User-authored workspace entries. A separate table from `pages` on purpose:
  // a page is site navigation, an entry is a user's record, and a user record
  // must never be able to put itself into the navigation bar. `id` is assigned
  // by SQLite, so creation order needs no application clock, and `created_at`
  // is stamped by SQLite's `strftime` for the same reason.
  self.exec(
    (
      #|CREATE TABLE IF NOT EXISTS entries (
      #|  id         INTEGER PRIMARY KEY AUTOINCREMENT,
      #|  domain     TEXT NOT NULL,
      #|  title      TEXT NOT NULL,
      #|  body       TEXT NOT NULL DEFAULT '',
      #|  created_at TEXT NOT NULL DEFAULT ''
      #|)
    ),
  )
  // Sessions: the named explorations, and the steps inside them.
  //
  // A session's steps are a tree, not a list. Each step records the step it
  // came from (`parent_step_id`) and the session records which step it is
  // standing on (`head_step_id`). Rewinding moves the head back and leaves
  // the steps beyond it in the table as the other branches; a list would have
  // had to delete them, and "let me try the other road from step 7" is the
  // whole reason to keep a history at all.
  self.exec(
    (
      #|CREATE TABLE IF NOT EXISTS sessions (
      #|  id             INTEGER PRIMARY KEY AUTOINCREMENT,
      #|  name           TEXT NOT NULL,
      #|  parent_id      INTEGER NOT NULL DEFAULT 0,
      #|  forked_step_id INTEGER NOT NULL DEFAULT 0,
      #|  head_step_id   INTEGER NOT NULL DEFAULT 0,
      #|  start_cursor   TEXT NOT NULL DEFAULT 'M',
      #|  mode           TEXT NOT NULL DEFAULT 'structured',
      #|  created_at     TEXT NOT NULL DEFAULT '',
      #|  updated_at     TEXT NOT NULL DEFAULT ''
      #|)
    ),
  )
  self.exec(
    (
      #|CREATE TABLE IF NOT EXISTS session_steps (
      #|  id               INTEGER PRIMARY KEY AUTOINCREMENT,
      #|  session_id       INTEGER NOT NULL,
      #|  parent_step_id   INTEGER NOT NULL DEFAULT 0,
      #|  domain           TEXT NOT NULL,
      #|  domain_title     TEXT NOT NULL,
      #|  slot             TEXT NOT NULL,
      #|  slot_designation TEXT NOT NULL,
      #|  outcome          TEXT NOT NULL,
      #|  outcome_kind     TEXT NOT NULL DEFAULT '',
      #|  detail           TEXT NOT NULL,
      #|  position_before  TEXT NOT NULL,
      #|  position_after   TEXT NOT NULL,
      #|  cursor_after     TEXT NOT NULL,
      #|  group_state      TEXT NOT NULL,
      #|  mode             TEXT NOT NULL,
      #|  source           TEXT NOT NULL DEFAULT 'drive',
      #|  drive            TEXT NOT NULL DEFAULT '',
      #|  undecided        INTEGER NOT NULL DEFAULT 0,
      #|  available        TEXT NOT NULL DEFAULT '',
      #|  blocked          TEXT NOT NULL DEFAULT '',
      #|  created_at       TEXT NOT NULL DEFAULT ''
      #|)
    ),
  )
  self.exec(
    "CREATE INDEX IF NOT EXISTS session_steps_session ON session_steps (session_id)",
  )
  // A column added after the first release of the table.
  //
  // `CREATE TABLE IF NOT EXISTS` does not add a column to a table that already
  // exists, so a database written by an older version keeps its old shape
  // unless it is altered -- and `ALTER TABLE ... ADD COLUMN` fails loudly when
  // the column is already there. So the check comes first, and the alter only
  // runs on the databases that need it.
  //
  // The old rows keep an empty kind. A step recorded before the kind was
  // stored still has its word, and the word is enough for a reader; what it
  // does not have is a kind to reason about, and the measures that want one
  // treat an empty kind as "not a move" rather than guessing.
  if !self.has_column("session_steps", "outcome_kind") {
    self.exec(
      "ALTER TABLE session_steps ADD COLUMN outcome_kind TEXT NOT NULL DEFAULT ''",
    )
  }
}

///|
/// Whether a table has a column.
///
/// `PRAGMA table_info` is the way to ask; there is no other. It comes back one
/// row per column, and the second column of each row is the column's name.
/// The table name is interpolated into the statement, so it has to be a name
/// this file chose -- never anything a reader supplied.
fn Database::has_column(
  self : Database,
  table : String,
  column : String,
) -> Bool raise {
  let stmt = self.connection.prepare("PRAGMA table_info(" + table + ")")
  stmt.reset(clear_bindings=true)
  let mut found = false
  while stmt.step() {
    let name : String = stmt.column(index=1)
    if name == column {
      found = true
    }
  }
  stmt.finalize()
  found
}

///|
/// Insert or update pages by slug. Re-seeding is how the server starts, so
/// the same file can be restarted without losing the schema.
pub fn Database::seed(self : Database, pages : Array[Page]) -> Unit raise {
  let upsert =
    #|INSERT INTO pages (slug, title, letter, role, summary, body, nav, sort)
    #|VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    #|ON CONFLICT(slug) DO UPDATE SET
    #|  title = excluded.title,
    #|  letter = excluded.letter,
    #|  role = excluded.role,
    #|  summary = excluded.summary,
    #|  body = excluded.body,
    #|  nav = excluded.nav,
    #|  sort = excluded.sort
  let stmt = self.connection.prepare(upsert)
  for page in pages {
    // reset(clear_bindings) before every use: without the reset this statement
    // re-runs with stale bindings, and without clear_bindings a parameter that
    // is not re-bound keeps its previous value.
    stmt.reset(clear_bindings=true)
    stmt.bind(index=1, page.slug)
    stmt.bind(index=2, page.title)
    stmt.bind(index=3, page.letter)
    stmt.bind(index=4, page.role)
    stmt.bind(index=5, page.summary)
    stmt.bind(index=6, page.body)
    stmt.bind(index=7, if page.in_navigation { 1L } else { 0L })
    stmt.bind(index=8, page.sort.to_int64())
    ignore(stmt.step())
  }
  stmt.finalize()
}

///|
fn read_page(stmt : @sqlite3.Statement) -> Page raise {
  {
    slug: stmt.column(index=0),
    title: stmt.column(index=1),
    letter: stmt.column(index=2),
    role: stmt.column(index=3),
    summary: stmt.column(index=4),
    body: stmt.column(index=5),
    in_navigation: (stmt.column(index=6) : Int64) != 0L,
    sort: (stmt.column(index=7) : Int64).to_int(),
  }
}

///|
const SELECT_COLUMNS : String = "slug, title, letter, role, summary, body, nav, sort"

///|
pub fn Database::page_by_slug(self : Database, slug : String) -> Page? raise {
  let stmt = self.connection.prepare(
    "SELECT " + SELECT_COLUMNS + " FROM pages WHERE slug = ?",
  )
  // This reset is defensive, not load-bearing: the statement is prepared fresh
  // here and has never stepped, so there are no previous bindings to clear.
  // Removing it does not change any observable behaviour --
  // `tools/mutate-backend.ps1` asserts exactly that and is expected to report
  // the removal as an equivalent mutant. It is kept because this function is
  // the obvious candidate for statement reuse, and the same line becomes
  // load-bearing the moment that happens.
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, slug)
  let found = if stmt.step() { Some(read_page(stmt)) } else { None }
  stmt.finalize()
  found
}

///|
pub fn Database::all_pages(self : Database) -> Array[Page] raise {
  let stmt = self.connection.prepare(
    "SELECT " + SELECT_COLUMNS + " FROM pages ORDER BY sort ASC, slug ASC",
  )
  let pages = []
  while stmt.step() {
    pages.push(read_page(stmt))
  }
  stmt.finalize()
  pages
}

///|
const ENTRY_COLUMNS : String = "id, domain, title, body, created_at"

///|
fn read_entry(stmt : @sqlite3.Statement) -> Entry raise {
  {
    id: stmt.column(index=0),
    domain: stmt.column(index=1),
    title: stmt.column(index=2),
    body: stmt.column(index=3),
    created_at: stmt.column(index=4),
  }
}

///|
/// Every entry, oldest first.
///
/// Ordering by `id` rather than `created_at` because the two could disagree:
/// `id` is assigned by the same transaction that inserts the row, so it cannot
/// be wrong or duplicated, whereas a clock can jump backwards between two
/// inserts and reorder the workspace under the user.
pub fn Database::all_entries(self : Database) -> Array[Entry] raise {
  let stmt = self.connection.prepare(
    "SELECT " + ENTRY_COLUMNS + " FROM entries ORDER BY id ASC",
  )
  let entries = []
  while stmt.step() {
    entries.push(read_entry(stmt))
  }
  stmt.finalize()
  entries
}

///|
/// Store one entry and return it as stored, including the id SQLite assigned.
///
/// `last_insert_rowid()` is a scalar SQL function, so it is read through the
/// same prepare/step/column path as any other query. It is read on the *same
/// connection* immediately after the insert, which is what makes it this
/// insert's rowid rather than some other session's.
pub fn Database::insert_entry(
  self : Database,
  domain : String,
  title : String,
  body : String,
) -> Entry raise {
  let insert = self.connection.prepare(
    (
      #|INSERT INTO entries (domain, title, body, created_at)
      #|VALUES (?, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    ),
  )
  // reset(clear_bindings) before use: a statement prepared here has never
  // stepped, so there is nothing to clear, but this is the shape every write
  // path in this file has to keep.
  insert.reset(clear_bindings=true)
  insert.bind(index=1, domain)
  insert.bind(index=2, title)
  insert.bind(index=3, body)
  ignore(insert.step())
  insert.finalize()
  let id_stmt = self.connection.prepare("SELECT last_insert_rowid()")
  id_stmt.reset(clear_bindings=true)
  let id : Int64 = if id_stmt.step() { id_stmt.column(index=0) } else { 0L }
  id_stmt.finalize()
  let created_stmt = self.connection.prepare(
    "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
  )
  created_stmt.reset(clear_bindings=true)
  let created_at = if created_stmt.step() {
    created_stmt.column(index=0)
  } else {
    ""
  }
  created_stmt.finalize()
  { id, domain, title, body, created_at, }
}

///|
/// Delete one entry by id.
///
/// Returns whether a row was actually removed, so the API can answer 404 for an
/// id that was never there instead of a 200 that lies about having deleted
/// something.
pub fn Database::delete_entry(self : Database, id : Int64) -> Bool raise {
  let stmt = self.connection.prepare("DELETE FROM entries WHERE id = ?")
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, id)
  ignore(stmt.step())
  stmt.finalize()
  self.connection.changes() > 0L
}

///|
const SESSION_COLUMNS : String = "id, name, parent_id, forked_step_id, head_step_id, start_cursor, mode, created_at, updated_at"

///|
fn read_session(stmt : @sqlite3.Statement) -> Session raise {
  {
    id: stmt.column(index=0),
    name: stmt.column(index=1),
    parent_id: stmt.column(index=2),
    forked_step_id: stmt.column(index=3),
    head_step_id: stmt.column(index=4),
    start_cursor: stmt.column(index=5),
    mode: stmt.column(index=6),
    created_at: stmt.column(index=7),
    updated_at: stmt.column(index=8),
  }
}

///|
/// Every session, most recently touched first.
///
/// `updated_at` is the sort key rather than `created_at` because the session
/// a user wants is the one they were just working in, and `id` breaks the tie
/// between two sessions touched in the same second -- SQLite stamps
/// `updated_at` to the second, so two steps in quick succession can share one.
pub fn Database::all_sessions(self : Database) -> Array[Session] raise {
  let stmt = self.connection.prepare(
    "SELECT " +
    SESSION_COLUMNS +
    " FROM sessions ORDER BY updated_at DESC, id DESC",
  )
  let sessions = []
  while stmt.step() {
    sessions.push(read_session(stmt))
  }
  stmt.finalize()
  sessions
}

///|
pub fn Database::session_by_id(self : Database, id : Int64) -> Session? raise {
  let stmt = self.connection.prepare(
    "SELECT " + SESSION_COLUMNS + " FROM sessions WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, id)
  let found = if stmt.step() { Some(read_session(stmt)) } else { None }
  stmt.finalize()
  found
}

///|
/// Store a new session and return it as stored.
///
/// `created_at` and `updated_at` are stamped by SQLite's own `strftime`
/// rather than by the application clock, for the reason the entries table
/// uses: an id that a clock assigned would have to be trusted, and a clock
/// can jump backwards between two inserts.
pub fn Database::insert_session(
  self : Database,
  name : String,
  parent_id : Int64,
  forked_step_id : Int64,
  start_cursor : String,
  mode : String,
) -> Session raise {
  let insert = self.connection.prepare(
    (
      #|INSERT INTO sessions
      #|  (name, parent_id, forked_step_id, head_step_id, start_cursor, mode, created_at, updated_at)
      #|VALUES (?, ?, ?, 0, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    ),
  )
  insert.reset(clear_bindings=true)
  insert.bind(index=1, name)
  insert.bind(index=2, parent_id)
  insert.bind(index=3, forked_step_id)
  insert.bind(index=4, start_cursor)
  insert.bind(index=5, mode)
  ignore(insert.step())
  insert.finalize()
  let id_stmt = self.connection.prepare("SELECT last_insert_rowid()")
  id_stmt.reset(clear_bindings=true)
  let id : Int64 = if id_stmt.step() { id_stmt.column(index=0) } else { 0L }
  id_stmt.finalize()
  let stamp_stmt = self.connection.prepare(
    "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
  )
  stamp_stmt.reset(clear_bindings=true)
  let stamp = if stamp_stmt.step() { stamp_stmt.column(index=0) } else { "" }
  stamp_stmt.finalize()
  {
    id,
    name,
    parent_id,
    forked_step_id,
    head_step_id: 0L,
    start_cursor,
    mode,
    created_at: stamp,
    updated_at: stamp,
  }
}

///|
/// Rename a session. Returns whether a row was actually renamed, so the API
/// can answer 404 for an id that was never there.
pub fn Database::rename_session(
  self : Database,
  id : Int64,
  name : String,
) -> Bool raise {
  let stmt = self.connection.prepare(
    "UPDATE sessions SET name = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, name)
  stmt.bind(index=2, id)
  ignore(stmt.step())
  stmt.finalize()
  self.connection.changes() > 0L
}

///|
/// Move a session's head. The head is the step the session is standing on.
pub fn Database::set_session_head(
  self : Database,
  id : Int64,
  head : Int64,
) -> Unit raise {
  let stmt = self.connection.prepare(
    "UPDATE sessions SET head_step_id = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, head)
  stmt.bind(index=2, id)
  ignore(stmt.step())
  stmt.finalize()
}

///|
/// Record where a session starts and which mode it runs in.
///
/// Set when the session is reset: the start is the point the session began
/// from, and a reset changes it, because after a reset the session is a new
/// walk from a new place rather than a continuation of the old one.
pub fn Database::set_session_start(
  self : Database,
  id : Int64,
  cursor : String,
  mode : String,
) -> Unit raise {
  let stmt = self.connection.prepare(
    "UPDATE sessions SET start_cursor = ?, mode = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, cursor)
  stmt.bind(index=2, mode)
  stmt.bind(index=3, id)
  ignore(stmt.step())
  stmt.finalize()
}

///|
/// Record which mode a session runs in.
///
/// Separate from `set_session_start` because changing the mode does not
/// change where the session starts, and a reset does both. Folding them into
/// one function would mean a mode change also moved the session's start.
pub fn Database::set_session_mode(
  self : Database,
  id : Int64,
  mode : String,
) -> Unit raise {
  let stmt = self.connection.prepare(
    "UPDATE sessions SET mode = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, mode)
  stmt.bind(index=2, id)
  ignore(stmt.step())
  stmt.finalize()
}

///|
/// Record that a session was just worked in.
pub fn Database::touch_session(self : Database, id : Int64) -> Unit raise {
  let stmt = self.connection.prepare(
    "UPDATE sessions SET updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, id)
  ignore(stmt.step())
  stmt.finalize()
}

///|
/// Forget a session and every step in it.
///
/// The steps go first: a step without its session would be a row nothing can
/// reach, and the table would grow with each reset.
pub fn Database::delete_session(self : Database, id : Int64) -> Bool raise {
  let steps = self.connection.prepare(
    "DELETE FROM session_steps WHERE session_id = ?",
  )
  steps.reset(clear_bindings=true)
  steps.bind(index=1, id)
  ignore(steps.step())
  steps.finalize()
  let stmt = self.connection.prepare("DELETE FROM sessions WHERE id = ?")
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, id)
  ignore(stmt.step())
  stmt.finalize()
  self.connection.changes() > 0L
}

///|
const STEP_COLUMNS : String = "id, session_id, parent_step_id, domain, domain_title, slot, slot_designation, outcome, outcome_kind, detail, position_before, position_after, cursor_after, group_state, mode, source, drive, undecided, available, blocked, created_at"

///|
fn read_step(stmt : @sqlite3.Statement) -> SessionStep raise {
  {
    id: stmt.column(index=0),
    session_id: stmt.column(index=1),
    parent_step_id: stmt.column(index=2),
    domain: stmt.column(index=3),
    domain_title: stmt.column(index=4),
    slot: stmt.column(index=5),
    slot_designation: stmt.column(index=6),
    outcome: stmt.column(index=7),
    outcome_kind: stmt.column(index=8),
    detail: stmt.column(index=9),
    position_before: stmt.column(index=10),
    position_after: stmt.column(index=11),
    cursor_after: stmt.column(index=12),
    group_state: stmt.column(index=13),
    mode: stmt.column(index=14),
    source: stmt.column(index=15),
    drive: stmt.column(index=16),
    undecided: (stmt.column(index=17) : Int64) != 0L,
    available: stmt.column(index=18),
    blocked: stmt.column(index=19),
    created_at: stmt.column(index=20),
  }
}

///|
/// Store one step and return it as stored.
pub fn Database::insert_step(
  self : Database,
  draft : StepDraft,
) -> SessionStep raise {
  let insert = self.connection.prepare(
    (
      #|INSERT INTO session_steps
      #|  (session_id, parent_step_id, domain, domain_title, slot, slot_designation, outcome, outcome_kind, detail,
      #|   position_before, position_after, cursor_after, group_state, mode, source, drive, undecided,
      #|   available, blocked, created_at)
      #|VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    ),
  )
  insert.reset(clear_bindings=true)
  insert.bind(index=1, draft.session_id)
  insert.bind(index=2, draft.parent_step_id)
  insert.bind(index=3, draft.domain)
  insert.bind(index=4, draft.domain_title)
  insert.bind(index=5, draft.slot)
  insert.bind(index=6, draft.slot_designation)
  insert.bind(index=7, draft.outcome)
  insert.bind(index=8, draft.outcome_kind)
  insert.bind(index=9, draft.detail)
  insert.bind(index=10, draft.position_before)
  insert.bind(index=11, draft.position_after)
  insert.bind(index=12, draft.cursor_after)
  insert.bind(index=13, draft.group_state)
  insert.bind(index=14, draft.mode)
  insert.bind(index=15, draft.source)
  insert.bind(index=16, draft.drive)
  insert.bind(index=17, if draft.undecided { 1L } else { 0L })
  insert.bind(index=18, draft.available)
  insert.bind(index=19, draft.blocked)
  ignore(insert.step())
  insert.finalize()
  let id_stmt = self.connection.prepare("SELECT last_insert_rowid()")
  id_stmt.reset(clear_bindings=true)
  let id : Int64 = if id_stmt.step() { id_stmt.column(index=0) } else { 0L }
  id_stmt.finalize()
  let stamp_stmt = self.connection.prepare(
    "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
  )
  stamp_stmt.reset(clear_bindings=true)
  let stamp = if stamp_stmt.step() { stamp_stmt.column(index=0) } else { "" }
  stamp_stmt.finalize()
  {
    id,
    session_id: draft.session_id,
    parent_step_id: draft.parent_step_id,
    domain: draft.domain,
    domain_title: draft.domain_title,
    slot: draft.slot,
    slot_designation: draft.slot_designation,
    outcome: draft.outcome,
    outcome_kind: draft.outcome_kind,
    detail: draft.detail,
    position_before: draft.position_before,
    position_after: draft.position_after,
    cursor_after: draft.cursor_after,
    group_state: draft.group_state,
    mode: draft.mode,
    source: draft.source,
    drive: draft.drive,
    undecided: draft.undecided,
    available: draft.available,
    blocked: draft.blocked,
    created_at: stamp,
  }
}

///|
/// Every step of a session, oldest rowid first.
///
/// The order is the insertion order, not the tree order: the tree is walked
/// by the callers that need a path, and the row order is enough to make the
/// branches come out in the order they were tried.
pub fn Database::steps_of_session(
  self : Database,
  session_id : Int64,
) -> Array[SessionStep] raise {
  let stmt = self.connection.prepare(
    "SELECT " +
    STEP_COLUMNS +
    " FROM session_steps WHERE session_id = ? ORDER BY id ASC",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, session_id)
  let steps = []
  while stmt.step() {
    steps.push(read_step(stmt))
  }
  stmt.finalize()
  steps
}

///|
pub fn Database::step_by_id(self : Database, id : Int64) -> SessionStep? raise {
  let stmt = self.connection.prepare(
    "SELECT " + STEP_COLUMNS + " FROM session_steps WHERE id = ?",
  )
  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, id)
  let found = if stmt.step() { Some(read_step(stmt)) } else { None }
  stmt.finalize()
  found
}
