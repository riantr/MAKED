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
}

///|
/// Insert or update pages by slug. Re-seeding is how the server starts, so
/// the same file can be restarted without losing the schema.
pub fn Database::seed(self : Database, pages : Array[Page]) -> Unit raise {
  let upsert = (
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
  )
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
