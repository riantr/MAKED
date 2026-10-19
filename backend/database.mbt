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
